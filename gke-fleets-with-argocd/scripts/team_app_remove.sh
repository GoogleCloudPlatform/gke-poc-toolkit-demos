#!/usr/bin/env bash

set -Euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

while getopts a:t: flag
do
    case "${flag}" in
        a) APP_NAME=${OPTARG};;
        t) TEAM_NAME=${OPTARG};;
    esac
done

echo "::Variable set::"
echo "APP_NAME: ${APP_NAME}"
echo "TEAM_NAME: ${TEAM_NAME}"

cd $script_dir/../argo-repo-sync
git checkout main

APP_DIR=teams/${TEAM_NAME}/${APP_NAME}
kubectl delete -f generators/${TEAM_NAME}-${APP_NAME}-applicationset-wave-1.yaml -n argocd --context mccp-central-01
kubectl delete -f generators/${TEAM_NAME}-${APP_NAME}-applicationset-wave-2.yaml -n argocd --context mccp-central-01

rm -rf ${APP_DIR}
rm generators/${TEAM_NAME}-${APP_NAME}-*
rm region-clusters-config/us-central-clusters-config/${TEAM_NAME}-${APP_NAME}-destination-rule.yaml
rm region-clusters-config/us-east-clusters-config/${TEAM_NAME}-${APP_NAME}-destination-rule.yaml
rm region-clusters-config/us-west-clusters-config/${TEAM_NAME}-${APP_NAME}-destination-rule.yaml
rm app-clusters-config/asm-gateways/${TEAM_NAME}-${APP_NAME}-*

git add . && git commit -m "Removed application ${APP_NAME} from main branch."
git push 

git checkout wave-one 
git merge main
git add . && git commit -m "Removed application ${APP_NAME} from wave-one branch."
git push 

git checkout wave-two 
git merge main
git add . && git commit -m "Removed application ${APP_NAME} from wave-one branch."
git push 

echo "Removed application ${APP_NAME} from all branches."







