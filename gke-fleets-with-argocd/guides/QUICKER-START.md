# Quicker start
This demo shows you how to bootstrap a Fleet of GKE clusters using ArgoCD as your gitops engine.

## Fleet Cluster setup

1. **Clone the demo repo and copy folders that are required**
```bash
git clone git@github.com:GoogleCloudPlatform/gke-poc-toolkit-demos.git  
cp -rf gke-poc-toolkit-demos/gke-fleets-with-argocd/argo-repo-sync ./
cp -rf gke-poc-toolkit-demos/gke-fleets-with-argocd/argo-cd-gke ./
cp -rf gke-poc-toolkit-demos/gke-fleets-with-argocd/scripts ./ 
rm -rf gke-poc-toolkit-demos
```

2. **Run the Fleet prep script**
First you need to create a github PAT token. Here is a link that explains how. https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token
```bash
# Create a var for your PAT token 
PAT_TOKEN=""
# Name for the private github repo that will be created
REPO=""
./scripts/fleet_prep.sh -p ${GKE_PROJECT_ID} -r ${REPO} -p ${PAT_TOKEN}
# Get your temp argocd admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
# Update your argocd admin password.
argocd account update-password --grpc-web
```
