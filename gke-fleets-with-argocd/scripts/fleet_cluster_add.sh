#!/usr/bin/env bash

set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

while getopts p:n:l:c:t: flag
do
    case "${flag}" in
        p) PROJECT_ID=${OPTARG};;
        n) CLUSTER_NAME=${OPTARG};;
        l) CLUSTER_LOCATION=${OPTARG};;
        c) CONTROL_PLANE_CIDR=${OPTARG};;
        t) CLUSTER_TYPE=${OPTARG};;
    esac
done

echo "::Variable set::"
echo "PROJECT_ID: ${PROJECT_ID}"
echo "CLUSTER_NAME: ${CLUSTER_NAME}"
echo "CLUSTER_LOCATION: ${CLUSTER_LOCATION}"
echo "CONTROL_PLANE_CIDR:${CONTROL_PLANE_CIDR}"
echo "CONTROL_TYPE:${CLUSTER_TYPE}"

REGION=${CLUSTER_LOCATION:0:-2}
PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format="value(projectNumber)")

if [[ ${CLUSTER_TYPE} == "autopilot" ]]; then
  gcloud beta container --project ${PROJECT_ID} clusters create-auto ${CLUSTER_NAME} \
    --region ${CLUSTER_LOCATION} \
    --release-channel "rapid" \
    --network "argo-demo" --subnetwork ${CLUSTER_LOCATION} \
    --master-ipv4-cidr ${CONTROL_PLANE_CIDR} \
    --enable-private-nodes \
    --enable-master-authorized-networks \
    --master-authorized-networks 0.0.0.0/0 \
    --security-group "gke-security-groups@nickeberts.altostrat.com" 
  gcloud container clusters update ${CLUSTER_NAME} --project ${PROJECT_ID} \
    --region ${CLUSTER_LOCATION} \
    --enable-master-global-access 
  gcloud container clusters update ${CLUSTER_NAME} --project ${PROJECT_ID} \
    --region ${CLUSTER_LOCATION} \
    --update-labels mesh_id=proj-${PROJECT_NUMBER}

else
  gcloud beta container --project ${PROJECT_ID} clusters create ${CLUSTER_NAME} \
    --zone ${CLUSTER_LOCATION} \
    --release-channel "rapid" \
    --machine-type "e2-medium" \
    --num-nodes "3" \
    --network "argo-demo" --subnetwork ${REGION} \
    --master-ipv4-cidr ${CONTROL_PLANE_CIDR} \
    --enable-private-nodes --enable-ip-alias --enable-master-global-access \
    --enable-autoscaling --min-nodes "3" --max-nodes "10" \
    --enable-master-authorized-networks \
    --master-authorized-networks 0.0.0.0/0 \
    --enable-autoupgrade --enable-autorepair --max-surge-upgrade 1 --max-unavailable-upgrade 0 \
    --labels mesh_id=proj-${PROJECT_NUMBER} \
    --autoscaling-profile optimize-utilization \
    --workload-pool "${PROJECT_ID}.svc.id.goog" \
    --security-group "gke-security-groups@nickeberts.altostrat.com" \
    --enable-image-streaming --node-locations ${CLUSTER_LOCATION}
fi

gcloud container clusters get-credentials ${CLUSTER_NAME} --zone ${CLUSTER_LOCATION} --project ${PROJECT_ID}
gcloud container fleet memberships register ${CLUSTER_NAME} --project ${PROJECT_ID}\
  --gke-cluster=${CLUSTER_LOCATION}/${CLUSTER_NAME} \
  --enable-workload-identity

gcloud container fleet mesh update \
    --control-plane automatic \
    --memberships ${CLUSTER_NAME} \
    --project ${PROJECT_ID}

kubectx ${CLUSTER_NAME}=gke_${PROJECT_ID}_${CLUSTER_LOCATION}_${CLUSTER_NAME}
kubectl create ns tools --context ${CLUSTER_NAME}
kubectl create ns asm-gateways --context ${CLUSTER_NAME}

openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
-subj "/CN=frontend.endpoints.${PROJECT_ID}.cloud.goog/O=Edge2Mesh Inc" \
-keyout frontend.endpoints.${PROJECT_ID}.cloud.goog.key \
-out frontend.endpoints.${PROJECT_ID}.cloud.goog.crt

kubectl -n asm-gateways create secret tls edge2mesh-credential \
--key=frontend.endpoints.${PROJECT_ID}.cloud.goog.key \
--cert=frontend.endpoints.${PROJECT_ID}.cloud.goog.crt 

rm frontend.endpoints*

argocd cluster add ${CLUSTER_NAME} \
  --label region=${CLUSTER_LOCATION} \
  --label env=prod \
  --name ${CLUSTER_NAME} \
  --grpc-web \
  --system-namespace tools -y

echo "${CLUSTER_NAME} has been deployed and added to the Fleet."