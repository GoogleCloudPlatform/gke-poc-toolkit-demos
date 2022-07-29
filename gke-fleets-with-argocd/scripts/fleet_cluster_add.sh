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

if [[ ${CLUSTER_TYPE} == "autopilot" ]]; then
  gcloud beta container --project ${PROJECT_ID} clusters create-auto ${CLUSTER_NAME} \
    --region ${CLUSTER_LOCATION} \
    --release-channel "rapid" \
    --network "argo-demo" --subnetwork ${CLUSTER_LOCATION} \
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
    --network "argo-demo" \
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
TAGS=`gcloud compute firewall-rules list --filter="Name:gke-gke*" --format="value(targetTags)" --project ${GKE_PROJECT_ID} | uniq`
TAGS=`join_by , $(echo "${TAGS}")`
echo "Network tags for pod ranges are $TAGS"

if [[ $(gcloud compute firewall-rules describe asm-multicluster-pods) ]]; then
  gcloud compute firewall-rules update asm-multicluster-pods \
    --allow=tcp,udp,icmp,esp,ah,sctp \
    --source-ranges="${ALL_CLUSTER_CIDRS}" \
    --target-tags=$TAGS
else
  gcloud compute firewall-rules create asm-multicluster-pods \
    --allow=tcp,udp,icmp,esp,ah,sctp \
    --direction=INGRESS \
    --priority=900 --network=argo-demo \
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
kubectl create ns tools --context ${CLUSTER_NAME}
kubectl create ns asm-gateways --context ${CLUSTER_NAME}
kubectl create ns istio-system --context ${CLUSTER_NAME}

openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
-subj "/CN=frontend.endpoints.${PROJECT_ID}.cloud.goog/O=Edge2Mesh Inc" \
-keyout frontend.endpoints.${PROJECT_ID}.cloud.goog.key \
-out frontend.endpoints.${PROJECT_ID}.cloud.goog.crt

kubectl -n asm-gateways create secret tls edge2mesh-credential \
--key=frontend.endpoints.${PROJECT_ID}.cloud.goog.key \
--cert=frontend.endpoints.${PROJECT_ID}.cloud.goog.crt --context ${CLUSTER_NAME}

rm frontend.endpoints*

mkdir -p tmp
for i in `gcloud container clusters list --project ${PROJECT_ID} --format="value(name)"`; do
    if [[ "$i" != "${CLUSTER_NAME}" ]] && [[ "$i" != "mccp-central-01" ]]; then
        echo -e "Creating kubeconfig secret from cluster ${CLUSTER_NAME} and installing it on cluster ${i}"
        istioctl create-remote-secret --context=${i} --name=${i} > ./tmp/secret-kubeconfig-${i}.yaml
        kubectl apply -f ./tmp/secret-kubeconfig-${i}.yaml --context=${CLUSTER_NAME}
    else
        echo -e "Skipping as the current cluster ${CLUSTER_NAME} is the same as the target cluster ${i} or the mccp-central-01 cluster."
    fi
done
rm -rf tmp

if [[ ${CLUSTER_TYPE} == "autopilot" ]]; then
  argocd cluster add ${CLUSTER_NAME} \
    --label region=${CLUSTER_LOCATION} \
    --label env=prod \
    --label wave="${APP_DEPLOYMENT_WAVE}" \
    --name ${CLUSTER_NAME} \
    --grpc-web \
    --system-namespace tools -y
else
  argocd cluster add ${CLUSTER_NAME} \
    --label region=${REGION} \
    --label env=prod \
    --label wave="${APP_DEPLOYMENT_WAVE}" \
    --name ${CLUSTER_NAME} \
    --grpc-web \
    --system-namespace tools -y
fi

# if [[ ${CLUSTER_TYPE} == "autopilot" ]]; then
# cat <<EOF > ${CLUSTER_NAME}-argo-secret.yaml
# apiVersion: v1
# kind: Secret
# metadata:
#   name: ${CLUSTER_NAME}
#   labels:
#     argocd.argoproj.io/secret-type: cluster
#     env: prod
#     region: ${CLUSTER_LOCATION}
#     wave: "${APP_DEPLOYMENT_WAVE}"
# type: Opaque
# stringData:
#   name: ${CLUSTER_NAME}
#   server: https://connectgateway.googleapis.com/v1beta1/projects/${PROJECT_NUMBER}/locations/global/gkeMemberships/${CLUSTER_NAME}
#   config: |
#     {
#       "execProviderConfig": {
#         "command": "argocd-k8s-auth",
#         "args": ["gcp"],
#         "apiVersion": "client.authentication.k8s.io/v1beta1"
#       },
#       "tlsClientConfig": {
#         "insecure": false,
#         "caData": ""
#       }
#     }
# EOF
# kubectl apply -f ${CLUSTER_NAME}-argo-secret.yaml -n argocd --context mccp-central-01
# else
# cat <<EOF > ${CLUSTER_NAME}-argo-secret.yaml
# apiVersion: v1
# kind: Secret
# metadata:
#   name: ${CLUSTER_NAME}
#   labels:
#     argocd.argoproj.io/secret-type: cluster
#     env: prod
#     region: ${REGION}
#     wave: "${APP_DEPLOYMENT_WAVE}"
# type: Opaque
# stringData:
#   name: ${CLUSTER_NAME}
#   server: https://connectgateway.googleapis.com/v1beta1/projects/${PROJECT_NUMBER}/locations/global/gkeMemberships/${CLUSTER_NAME}
#   config: |
#     {
#       "execProviderConfig": {
#         "command": "argocd-k8s-auth",
#         "args": ["gcp"],
#         "apiVersion": "client.authentication.k8s.io/v1beta1"
#       },
#       "tlsClientConfig": {
#         "insecure": false,
#         "caData": ""
#       }
#     }
# EOF
# kubectl apply -f ${CLUSTER_NAME}-argo-secret.yaml -n argocd --context mccp-central-01
# fi

echo "${CLUSTER_NAME} has been deployed and added to the Fleet."