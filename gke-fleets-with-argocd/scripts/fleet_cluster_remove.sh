#!/usr/bin/env bash

set -Euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

while getopts p:n:l: flag
do
    case "${flag}" in
        p) PROJECT_ID=${OPTARG};;
        n) CLUSTER_NAME=${OPTARG};;
        l) CLUSTER_LOCATION=${OPTARG};;
    esac
done

echo "::Variable set::"
echo "PROJECT: ${PROJECT_ID}"
echo "CLUSTER_NAME: ${CLUSTER_NAME}"
echo "CLUSTER_LOCATION: ${CLUSTER_LOCATION}"

gcloud container fleet memberships unregister ${CLUSTER_NAME} --gke-cluster=${CLUSTER_LOCATION}/${CLUSTER_NAME} --project ${PROJECT_ID} -q
gcloud container clusters delete ${CLUSTER_NAME} --zone ${CLUSTER_LOCATION} --project ${PROJECT_ID} -q
# ARGO_CLUSTER_TO_REMOVE=$(argocd cluster list --grpc-web | grep ${CLUSTER_NAME} | awk '{print $1}')
argocd cluster rm ${CLUSTER_NAME} --grpc-web
kctx -d ${CLUSTER_NAME}

