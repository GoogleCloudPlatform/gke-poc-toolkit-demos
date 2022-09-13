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

REPO=${APP_NAME}
REPO_URL="https://source.developers.google.com/p/${PROJECT_ID}/r/${REPO}"

mkdir -p gke-poc-config-sync/namespaces/${APP_NAME}
cat <<EOF > gke-poc-config-sync/namespaces/${APP_NAME}/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ${APP_NAME}
  annotations:
    configmanagement.gke.io/cluster-selector: selector-prod
  labels:
    istio.io/rev: asm-managed
EOF

cat <<EOF > gke-poc-config-sync/namespaces/${APP_NAME}/repo-sync.yaml
apiVersion: configsync.gke.io/v1beta1
kind: RepoSync
metadata:
  name: repo-sync
  namespace: ${APP_NAME}
spec:
  sourceFormat: unstructured
  git:
    repo: ${REPO_URL}
    branch: main
    dir: "/"
    auth: "gcpserviceaccount"
    gcpServiceAccountEmail: "acm-service-account@${PROJECT_ID}.iam.gserviceaccount.com"
EOF

cat <<EOF > gke-poc-config-sync/namespaces/${APP_NAME}/sync-rolebinding.yaml
 kind: RoleBinding
 apiVersion: rbac.authorization.k8s.io/v1
 metadata:
   name: syncs-repo
   namespace: ${APP_NAME}
 subjects:
 - kind: ServiceAccount
   name: ns-reconciler-${APP_NAME}
   namespace: config-management-system
 roleRef:
   kind: ClusterRole
   name: cluster-admin
   apiGroup: rbac.authorization.k8s.io
EOF

APP_DIR=${TEAM_NAME}/${REPO}
mkdir -p ${APP_DIR}
if [[ $(gcloud source repos describe ${REPO} --project ${PROJECT_ID}) ]]; then
    echo "Adding ${APP_NAME} to Cloud Source Repo ${REPO} and setting up repo-sync."
else
    echo "Creating a new Cloud Source Repo for app ${APP_NAME}."
    gcloud source repos create ${REPO} --project=${PROJECT_ID}
    cd ${TEAM_NAME}
    gcloud source repos clone ${REPO} --project=${PROJECT_ID}
    cd -
    cd gke-poc-config-sync
    git add . && git commit -m "Created app repo and setup ConfigSync for team ${TEAM_NAME}."
    git push 
    cd -
fi

## Bind config sync GSA to namespace repo sync KSA
gcloud iam service-accounts add-iam-policy-binding \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:${PROJECT_ID}.svc.id.goog[config-management-system/ns-reconciler-${APP_NAME}]" \
    "acm-service-account@${PROJECT_ID}.iam.gserviceaccount.com"

kustomize build app-template/prod/ -o ${APP_DIR}
cp -rf  gke-poc-config-sync/clusterregistry ${APP_DIR}/

APP_IMAGE="${APP_IMAGE}"
if [[ "$OSTYPE" == "darwin"* ]]; then
    for file in ${APP_DIR}/*; do
        [ -e "${file}" ]
        echo ${file}
        sed -i '' -e "s/APP_NAME/${APP_NAME}/g" ${file}
        sed -i '' -e "s|APP_IMAGE|${APP_IMAGE}|g" ${file}
        sed -i '' -e "s/TEAM_NAME/${TEAM_NAME}/g" ${file}
        sed -i '' -e "s/APP_HOST_NAME/${APP_HOST_NAME}/g" ${file}
    done
else
    for file in ${APP_DIR}/*; do
        [ -e "${file}" ]
        echo ${file}
        sed -i -e "s/APP_NAME/${APP_NAME}/g" ${file}
        sed -i -e "s|APP_IMAGE|${APP_IMAGE}|g" ${file}
        sed -i -e "s/TEAM_NAME/${TEAM_NAME}/g" ${file}
        sed -i -e "s/APP_HOST_NAME/${APP_HOST_NAME}/g" ${file}
    done
fi
cd ${APP_DIR}

git init -b main
git add . && git commit -m "Added application ${APP_NAME} to team ${TEAM_NAME}."
git push origin main

echo "Added application ${APP_NAME} to team ${TEAM_NAME} and staged for wave one and wave two clusters."