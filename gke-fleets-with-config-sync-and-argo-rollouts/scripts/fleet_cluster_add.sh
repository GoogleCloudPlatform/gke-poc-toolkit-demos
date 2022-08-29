#!/usr/bin/env bash

set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

while getopts p:n:l:c:t:w: flag
do
    case "${flag}" in
        p) PROJECT_ID=${OPTARG};;
        n) CLUSTER_NAME=${OPTARG};;
        l) CLUSTER_LOCATION=${OPTARG};;
        c) CONTROL_PLANE_CIDR=${OPTARG};;
        t) CLUSTER_TYPE=${OPTARG};;
        w) APP_DEPLOYMENT_WAVE=${OPTARG};;
    esac
done

echo "::Variable set::"
echo "PROJECT_ID: ${PROJECT_ID}"
echo "CLUSTER_NAME: ${CLUSTER_NAME}"
echo "CLUSTER_LOCATION: ${CLUSTER_LOCATION}"
echo "CONTROL_PLANE_CIDR:${CONTROL_PLANE_CIDR}"
echo "CONTROL_TYPE:${CLUSTER_TYPE}"
echo "APP_DEPLOYMENT_WAVE:${APP_DEPLOYMENT_WAVE}"

REGION=${CLUSTER_LOCATION:0:-2}
PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format="value(projectNumber)")
echo "REGION:${REGION}"
echo "PROJECT_NUMBER:${PROJECT_NUMBER}"
mkdir -p tmp

if [[ ${CLUSTER_TYPE} == "autopilot" ]]; then
  gcloud beta container --project ${PROJECT_ID} clusters create-auto ${CLUSTER_NAME} \
    --region ${CLUSTER_LOCATION} \
    --release-channel "rapid" \
    --network "gke-poc-toolkit" --subnetwork ${CLUSTER_LOCATION} \
    --enable-master-authorized-networks \
    --master-authorized-networks 0.0.0.0/0 \
    --security-group "gke-security-groups@nickeberts.altostrat.com" 
  # gcloud container clusters update ${CLUSTER_NAME} --project ${PROJECT_ID} \
  #   --region ${CLUSTER_LOCATION} \
  #   --enable-master-global-access 
  gcloud container clusters update ${CLUSTER_NAME} --project ${PROJECT_ID} \
    --region ${CLUSTER_LOCATION} \
    --update-labels mesh_id=proj-${PROJECT_NUMBER}
else
  gcloud beta container --project ${PROJECT_ID} clusters create ${CLUSTER_NAME} \
    --zone ${CLUSTER_LOCATION} \
    --release-channel "rapid" \
    --machine-type "e2-medium" \
    --num-nodes "3" \
    --network "gke-poc-toolkit" \
    --subnetwork ${REGION} \
    --enable-ip-alias \
    --enable-autoscaling --min-nodes "3" --max-nodes "10" \
    --enable-autoupgrade --enable-autorepair --max-surge-upgrade 1 --max-unavailable-upgrade 0 \
    --labels mesh_id=proj-${PROJECT_NUMBER} \
    --autoscaling-profile optimize-utilization \
    --workload-pool "${PROJECT_ID}.svc.id.goog" \
    --security-group "gke-security-groups@nickeberts.altostrat.com" \
    --enable-image-streaming --node-locations ${CLUSTER_LOCATION}
    # --master-ipv4-cidr ${CONTROL_PLANE_CIDR} \
    # --enable-private-nodes \
    # --enable-master-authorized-networks \
    # --master-authorized-networks 0.0.0.0/0 \
    # --enable-master-global-access \
fi

function join_by { local IFS="$1"; shift; echo "$*"; }
ALL_CLUSTER_CIDRS=$(gcloud container clusters list --project ${PROJECT_ID} --format='value(clusterIpv4Cidr)' | sort | uniq)
ALL_CLUSTER_CIDRS=$(join_by , $(echo "${ALL_CLUSTER_CIDRS}"))
TAGS=`gcloud compute firewall-rules list --filter="Name:gke-gke*" --format="value(targetTags)" --project ${PROJECT_ID} | uniq`
TAGS=`join_by , $(echo "${TAGS}")`
echo "Network tags for pod ranges are $TAGS"

if [[ $(gcloud compute firewall-rules describe asm-multicluster-pods --project ${PROJECT_ID}) ]]; then
  gcloud compute firewall-rules update asm-multicluster-pods --project ${PROJECT_ID}\
    --allow=tcp,udp,icmp,esp,ah,sctp --network=gke-poc-toolkit \
    --source-ranges="${ALL_CLUSTER_CIDRS}" \
    --target-tags=$TAGS
else
  gcloud compute firewall-rules create asm-multicluster-pods --project ${PROJECT_ID}\
    --allow=tcp,udp,icmp,esp,ah,sctp \
    --direction=INGRESS \
    --priority=900 --network=gke-poc-toolkit \
    --source-ranges="${ALL_CLUSTER_CIDRS}" \
    --target-tags=$TAGS
fi

gcloud container clusters get-credentials ${CLUSTER_NAME} --zone ${CLUSTER_LOCATION} --project ${PROJECT_ID}
gcloud container fleet memberships register ${CLUSTER_NAME} --project ${PROJECT_ID}\
  --gke-cluster=${CLUSTER_LOCATION}/${CLUSTER_NAME} \
  --enable-workload-identity

# gcloud container fleet mesh update \
#     --control-plane automatic \
#     --memberships ${CLUSTER_NAME} \
#     --project ${PROJECT_ID}

kubectx ${CLUSTER_NAME}=gke_${PROJECT_ID}_${CLUSTER_LOCATION}_${CLUSTER_NAME}
cat <<EOF > tmp/namespaces.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: asm-gateways
---
apiVersion: v1
kind: Namespace
metadata:
  name: istio-system
---
apiVersion: v1
kind: Namespace
metadata:
  name: prod-tools
EOF
kubectl apply -f tmp/namespaces.yaml --context ${CLUSTER_NAME}

echo -n "Waiting for the ASM MCP webhook to install."
until kubectl get crd controlplanerevisions.mesh.cloud.google.com
do
  echo -n "...still waiting for ASM Control Plane Revision CRD to be created."
  sleep 5
done
echo "ASM Control Plane Revision CRD has been created."

## Install ASM Control Plane Revision
cat <<EOF > tmp/asm-cpr.yaml
apiVersion: mesh.cloud.google.com/v1alpha1
kind: ControlPlaneRevision
metadata:
  name: asm-managed
  namespace: istio-system
spec:
  type: managed_service
  channel: regular
EOF
kubectl apply -f tmp/asm-cpr.yaml

echo -n "Waiting for the ASM MCP webhook to install."
until kubectl get mutatingwebhookconfigurations istiod-asm-managed
do
  echo -n "...still waiting for ASM MCP webhook creation"
  sleep 5
done
echo "ASM MCP webhook has been created."

## Install Config Sync
cat <<EOF > tmp/config-sync.yaml
applySpecVersion: 1
spec:
  configSync:
    enabled: true
    sourceFormat: "unstructured"
    syncRepo: "https://source.developers.google.com/p/${PROJECT_ID}/r/gke-poc-config-sync"
    syncBranch: "main"
    secretType: "gcpserviceaccount"
    gcpServiceAccountEmail: "acm-service-account@${PROJECT_ID}.iam.gserviceaccount.com"
    policyDir: "/"
    preventDrift: true
  policyController:
    enabled: true
EOF

gcloud alpha container fleet config-management apply \
  --membership=${CLUSTER_NAME} \
  --config=tmp/config-sync.yaml \
  --project=${PROJECT_ID} -q

gcloud projects add-iam-policy-binding ${PROJECT_ID} --role roles/monitoring.viewer --member "serviceAccount:${PROJECT_ID}.svc.id.goog[prod-tools/default]"

openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
-subj "/CN=frontend.endpoints.${PROJECT_ID}.cloud.goog/O=Edge2Mesh Inc" \
-keyout tmp/frontend.endpoints.${PROJECT_ID}.cloud.goog.key \
-out tmp/frontend.endpoints.${PROJECT_ID}.cloud.goog.crt

kubectl -n asm-gateways create secret tls edge2mesh-credential \
--key=tmp/frontend.endpoints.${PROJECT_ID}.cloud.goog.key \
--cert=tmp/frontend.endpoints.${PROJECT_ID}.cloud.goog.crt --context ${CLUSTER_NAME}

cat <<EOF > mesh-config.yaml
apiVersion: v1
data:
  mesh: |-
    accessLogFile: /dev/stdout
    multicluster_mode: connected
    trustDomainAliases: ["${PROJECT_ID}.svc.id.goog"]
kind: ConfigMap
metadata:
  name: istio-asm-managed
  namespace: istio-system
---
apiVersion: v1
data:
kind: ConfigMap
metadata:
  name: asm-options
  namespace: istio-system
EOF
kubectl apply -f mesh-config.yaml --context ${CLUSTER_NAME}

## Check for apps managed certs and create them if they do not exist
if [[ $(gcloud compute ssl-certificates describe whereami-cert --project ${PROJECT_ID}) ]]; then
  echo "Whereami demo app cert already exists"
else
  echo "Creating certificates for whereami demo app."
  gcloud compute ssl-certificates create whereami-cert \
      --domains=whereami.endpoints.${PROJECT_ID}.cloud.goog \
      --global
fi

if [[ $(gcloud compute ssl-certificates describe rollout-demo-cert --project ${PROJECT_ID}) ]]; then
  echo "Rollout demo app cert already exists"
else
  echo "Creating certificate for rollout demo app."
  gcloud compute ssl-certificates create rollout-demo-cert \
      --domains=rollout-demo.endpoints.${PROJECT_ID}.cloud.goog \
      --global
fi

rm -rf tmp
cd gke-poc-config-sync

if [[ ${CLUSTER_TYPE} == "autopilot" ]]; then
cat <<EOF > clusterregistry/${CLUSTER_NAME}.yaml
kind: Cluster
apiVersion: clusterregistry.k8s.io/v1alpha1
metadata:
  name: ${CLUSTER_NAME}
  labels:
    environment: "prod"
    location: "${CLUSTER_LOCATION}"
    wave: "${APP_DEPLOYMENT_WAVE}"
EOF
else
cat <<EOF > clusterregistry/${CLUSTER_NAME}.yaml
kind: Cluster
apiVersion: clusterregistry.k8s.io/v1alpha1
metadata:
  name: ${CLUSTER_NAME}
  labels:
    environment: "prod"
    location: "${REGION}"
    wave: "${APP_DEPLOYMENT_WAVE}"
EOF
fi

git add . && git commit -m "Added ${CLUSTER_NAME} to the cluster registry folder." && git push

echo "${CLUSTER_NAME} has been deployed and added to the Fleet."
