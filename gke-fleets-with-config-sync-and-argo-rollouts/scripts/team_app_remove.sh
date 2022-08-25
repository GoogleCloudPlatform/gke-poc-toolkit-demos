#!/usr/bin/env bash

set -Euo pipefail

while getopts a:t:p: flag
do
    case "${flag}" in
        a) APP_NAME=${OPTARG};;
        t) TEAM_NAME=${OPTARG};;
        p) PROJECT_ID=${OPTARG};;
    esac
done

echo "::Variable set::"
echo "APP_NAME: ${APP_NAME}"
echo "TEAM_NAME: ${TEAM_NAME}"
echo "PROJECT_ID: ${PROJECT_ID}"




gcloud source repos delete ${APP_NAME} --project=${PROJECT_ID} -q
rm -rf ${TEAM_NAME}/${APP_NAME}
cd gke-poc-config-sync
git checkout main

rm -rf namespaces/${APP_NAME}

git add . && git commit -m "Removed application ${APP_NAME}."
git push 

echo "Removed application ${APP_NAME}."







