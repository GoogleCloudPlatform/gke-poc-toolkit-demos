#!/usr/bin/env bash

set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

while getopts p:n:l:c: flag
do
    case "${flag}" in
        p) PROJECT=${OPTARG};;
        n) CLUSTER_NAME=${OPTARG};;
        l) CLUSTER_LOCATION=${OPTARG};;
        c) CONTROL_PLANE_CIDR=${OPTARG};;
    esac
done

echo "::Variable set::"
echo "PROJECT: ${PROJECT}"
echo "CLUSTER_NAME: ${CLUSTER_NAME}"
echo "CLUSTER_LOCATION: ${CLUSTER_LOCATION}"
echo "CONTROL_PLANE_CIDR:${CONTROL_PLANE_CIDR}"

gcloud container fleet memberships unregister ${CLUSTER_NAME} --gke-cluster=${CLUSTER_LOCATION}/${CLUSTER_NAME} -q
gcloud container clusters delete ${CLUSTER_NAME} --zone ${CLUSTER_LOCATION} -q
ARGO_CLUSTER_TO_REMOVE=$(argocd cluster list --grpc-web | grep ${CLUSTER_NAME} | awk '{print $1}')
argocd cluster rm $ARGO_CLUSTER_TO_REMOVE --grpc-web

