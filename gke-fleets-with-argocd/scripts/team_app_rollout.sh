#!/usr/bin/env bash

set -Euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

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

cd $script_dir/../argo-repo-sync
APP_DIR=../argo-repo-sync/teams/${TEAM_NAME}/${APP_NAME}/
if [[ "$OSTYPE" == "darwin"* ]]; then
    if [[ ${WAVE} == "one" ]]; then
        git checkout wave-one
        git merge main
        sed -i '' -e "s|image: ${APP_IMAGE}:.*|image: ${APP_IMAGE}:${APP_IMAGE_TAG}|g" ${APP_DIR}rollout.yaml
        git add . && git commit -m "Updated application ${APP_NAME} image tag to ${APP_IMAGE}:${APP_IMAGE_TAG} on wave ${WAVE} clusters."
        git push 
    elif [[ ${WAVE} == "two" ]]; then
        git checkout wave-two
        git merge wave-one
        git add . && git commit -m "Updated application ${APP_NAME} image tag to ${APP_IMAGE}:${APP_IMAGE_TAG} on wave ${WAVE} clusters."
        git push 
    else
        git checkout main
        git merge wave-two
        git add . && git commit -m "Merged application ${APP_NAME} update ${APP_IMAGE}:${APP_IMAGE_TAG} into main."
        git push
    fi
else 
    if [[ ${WAVE} == "one" ]]; then
        git checkout wave-one
        git merge main
        sed -i -e "s|image: ${APP_IMAGE}:.*|image: ${APP_IMAGE}:${APP_IMAGE_TAG}|g" ${APP_DIR}rollout.yaml
        git add . && git commit -m "Updated application ${APP_NAME} image tag to ${APP_IMAGE}:${APP_IMAGE_TAG} on wave ${WAVE} clusters."
        git push 
    elif [[ ${WAVE} == "two" ]]; then
        git checkout wave-two
        git merge wave-one
        git add . && git commit -m "Updated application ${APP_NAME} image tag to ${APP_IMAGE}:${APP_IMAGE_TAG} on wave ${WAVE} clusters."
        git push 
    else
        git checkout main
        git merge wave-two
        git add . && git commit -m "Merged application ${APP_NAME} update ${APP_IMAGE}:${APP_IMAGE_TAG} into main."
        git push
    fi
fi


