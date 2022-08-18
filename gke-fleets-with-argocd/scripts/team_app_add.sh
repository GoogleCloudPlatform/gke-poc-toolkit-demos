#!/usr/bin/env bash

set -Euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

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

cd $script_dir
APP_DIR=../argo-repo-sync/teams/${TEAM_NAME}/${APP_NAME}/
mkdir -p ${APP_DIR}
cp ../argo-repo-sync/app-template/new-app/* ${APP_DIR}

APP_IMAGE="${APP_IMAGE}"
if [[ "$OSTYPE" == "darwin"* ]]; then
    for file in ${APP_DIR}*; do
        [ -e "${file}" ]
        echo ${file}
        sed -i '' -e "s/APP_NAME/${APP_NAME}/g" ${file}
        sed -i '' -e "s|APP_IMAGE|${APP_IMAGE}|g" ${file}
        sed -i '' -e "s/TEAM_NAME/${TEAM_NAME}/g" ${file}
        # sed -i '' -e "s/WAVE/${WAVE}/g" ${file}
        sed -i '' -e "s/APP_HOST_NAME/${APP_HOST_NAME}/g" ${file}
    done
else
    for file in ${APP_DIR}*; do
        [ -e "${file}" ]
        echo ${file}
        sed -i -e "s/APP_NAME/${APP_NAME}/g" ${file}
        sed -i -e "s|APP_IMAGE|${APP_IMAGE}|g" ${file}
        sed -i -e "s/TEAM_NAME/${TEAM_NAME}/g" ${file}
        # sed -i '' -e "s/WAVE/${WAVE}/g" ${file}
        sed -i -e "s/APP_HOST_NAME/${APP_HOST_NAME}/g" ${file}
    done
fi

mv ${APP_DIR}applicationset-wave-1.yaml ../argo-repo-sync/generators/${TEAM_NAME}-${APP_NAME}-applicationset-wave-1.yaml
mv ${APP_DIR}applicationset-wave-2.yaml ../argo-repo-sync/generators/${TEAM_NAME}-${APP_NAME}-applicationset-wave-2.yaml
mv ${APP_DIR}argocd-project.yaml ../argo-repo-sync/teams/${TEAM_NAME}/
mv ${APP_DIR}virtual-service.yaml ../argo-repo-sync/app-clusters-config/asm-gateways/${TEAM_NAME}-${APP_NAME}-virtual-service.yaml
mv ${APP_DIR}destination-rule-central.yaml ../argo-repo-sync/region-clusters-config/us-central-clusters-config/${TEAM_NAME}-${APP_NAME}-destination-rule.yaml
mv ${APP_DIR}destination-rule-east.yaml ../argo-repo-sync/region-clusters-config/us-east-clusters-config/${TEAM_NAME}-${APP_NAME}-destination-rule.yaml
mv ${APP_DIR}destination-rule-west.yaml ../argo-repo-sync/region-clusters-config/us-west-clusters-config/${TEAM_NAME}-${APP_NAME}-destination-rule.yaml
mv ${APP_DIR}namespace.yaml ../argo-repo-sync/app-clusters-config/asm-gateways/${TEAM_NAME}-${APP_NAME}-namespace.yaml
cd ../argo-repo-sync

git checkout wave-one
git merge main
git add . && git commit -m "Added application ${APP_NAME} to wave-one branch."
git push -u origin wave-one 

git checkout wave-two
git merge wave-one
git add . && git commit -m "Added application ${APP_NAME} to wave-two branch."
git push -u origin wave-two

git checkout main
git merge wave-two
git add . && git commit -m "Added application ${APP_NAME} to team ${TEAM_NAME}."
git push -u origin main   

kubectl apply -f ../argo-repo-sync/teams/${TEAM_NAME}/argocd-project.yaml -n argocd --context mccp-central-01
kubectl apply -f ../argo-repo-sync/generators/${TEAM_NAME}-${APP_NAME}-applicationset-wave-1.yaml -n argocd --context mccp-central-01
kubectl apply -f ../argo-repo-sync/generators/${TEAM_NAME}-${APP_NAME}-applicationset-wave-2.yaml -n argocd --context mccp-central-01

echo "Added application ${APP_NAME} to team ${TEAM_NAME} and staged for wave one and wave two clusters."



