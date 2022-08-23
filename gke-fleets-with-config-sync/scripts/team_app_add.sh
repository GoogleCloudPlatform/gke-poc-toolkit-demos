#!/usr/bin/env bash

set -Euo pipefail


while getopts a:h:i:p:t: flag
do
    case "${flag}" in
        a) APP_NAME=${OPTARG};;
        h) APP_HOST_NAME=${OPTARG};;
        i) APP_IMAGE=${OPTARG};;
        p) PROJECT_ID=${OPTARG};;
        t) TEAM_NAME=${OPTARG};;
    esac
done

echo "::Variable set::"
echo "APP_NAME: ${APP_NAME}"
echo "APP_HOST_NAME: ${APP_HOST_NAME}"
echo "APP_IMAGE: ${APP_IMAGE}"
echo "PROJECT_ID: ${PROJECT_ID}"
echo "TEAM_NAME: ${TEAM_NAME}"

if [ ! -d "gke-poc-config-sync/${TEAM_NAME}" ]; then
  echo "- ${TEAM_NAME}/${APP_NAME}" >> gke-poc-config-sync/kustomization.yaml
fi

APP_DIR=gke-poc-config-sync/${TEAM_NAME}/${APP_NAME}/
mkdir -p ${APP_DIR}
cp app-template/new-app/* ${APP_DIR}

APP_IMAGE="${APP_IMAGE}"
if [[ "$OSTYPE" == "darwin"* ]]; then
    for file in ${APP_DIR}*; do
        [ -e "${file}" ]
        echo ${file}
        sed -i '' -e "s/APP_NAME/${APP_NAME}/g" ${file}
        sed -i '' -e "s|APP_IMAGE|${APP_IMAGE}|g" ${file}
        sed -i '' -e "s/TEAM_NAME/${TEAM_NAME}/g" ${file}
        sed -i '' -e "s/APP_HOST_NAME/${APP_HOST_NAME}/g" ${file}
    done
else
    for file in ${APP_DIR}*; do
        [ -e "${file}" ]
        echo ${file}
        sed -i -e "s/APP_NAME/${APP_NAME}/g" ${file}
        sed -i -e "s|APP_IMAGE|${APP_IMAGE}|g" ${file}
        sed -i -e "s/TEAM_NAME/${TEAM_NAME}/g" ${file}
        sed -i -e "s/APP_HOST_NAME/${APP_HOST_NAME}/g" ${file}
    done
fi

cd gke-poc-config-sync
git add . && git commit -m "Added application ${APP_NAME} to team ${TEAM_NAME}." && git push    

echo "Added application ${APP_NAME} to team ${TEAM_NAME} and staged for wave one and wave two clusters."



