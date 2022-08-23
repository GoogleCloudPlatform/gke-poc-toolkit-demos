#!/usr/bin/env bash

set -Euo pipefail

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

cd gke-poc-config-sync
git checkout main

APP_DIR=gke-poc-config-sync/${TEAM_NAME}/${APP_NAME}/

rm -rf ${APP_DIR}

git add . && git commit -m "Removed application ${APP_NAME} from main branch."
git push 

echo "Removed application ${APP_NAME} from all branches."







