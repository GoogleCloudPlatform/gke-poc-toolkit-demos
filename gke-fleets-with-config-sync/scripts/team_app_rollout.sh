#!/usr/bin/env bash

set -Euo pipefail

while getopts a:i:l:t:w: flag
do
    case "${flag}" in
        a) APP_NAME=${OPTARG};;
        i) APP_IMAGE=${OPTARG};;
        l) APP_IMAGE_TAG=${OPTARG};;
        t) TEAM_NAME=${OPTARG};;
        w) WAVE=${OPTARG};;
    esac
done

echo "::Variable set::"
echo "APP_NAME: ${APP_NAME}"
echo "APP_IMAGE: ${APP_IMAGE}"
echo "APP_IMAGE_TAG: ${APP_IMAGE_TAG}"
echo "TEAM_NAME: ${TEAM_NAME}"
echo "WAVE:${WAVE}"

cd gke-poc-config-sync
APP_DIR=${TEAM_NAME}/${APP_NAME}/

if [[ "$OSTYPE" == "darwin"* ]]; then
    if [[ ${WAVE} == "one" ]]; then
        sed -i '' -e "s|image: ${APP_IMAGE}:.*|image: ${APP_IMAGE}:${APP_IMAGE_TAG}|g" ${APP_DIR}rollout-wave1.yaml
        git add . && git commit -m "Updated application ${APP_NAME} image tag to ${APP_IMAGE}:${APP_IMAGE_TAG} on wave ${WAVE} clusters."
        git push 
    elif [[ ${WAVE} == "two" ]]; then
        sed -i '' -e "s|image: ${APP_IMAGE}:.*|image: ${APP_IMAGE}:${APP_IMAGE_TAG}|g" ${APP_DIR}rollout-wave2.yaml
        git add . && git commit -m "Updated application ${APP_NAME} image tag to ${APP_IMAGE}:${APP_IMAGE_TAG} on wave ${WAVE} clusters."
        git push 
    else
        echo "${WAVE} is an unknown wave."
    fi
else 
    if [[ ${WAVE} == "one" ]]; then
        sed -i -e "s|image: ${APP_IMAGE}:.*|image: ${APP_IMAGE}:${APP_IMAGE_TAG}|g" ${APP_DIR}rollout-wave1.yaml
        git add . && git commit -m "Updated application ${APP_NAME} image tag to ${APP_IMAGE}:${APP_IMAGE_TAG} on wave ${WAVE} clusters."
        git push 
    elif [[ ${WAVE} == "two" ]]; then
        sed -i -e "s|image: ${APP_IMAGE}:.*|image: ${APP_IMAGE}:${APP_IMAGE_TAG}|g" ${APP_DIR}rollout-wave2.yaml
        git add . && git commit -m "Updated application ${APP_NAME} image tag to ${APP_IMAGE}:${APP_IMAGE_TAG} on wave ${WAVE} clusters."
        git push 
    else
        echo "${WAVE} is an unknown wave."
    fi
fi


