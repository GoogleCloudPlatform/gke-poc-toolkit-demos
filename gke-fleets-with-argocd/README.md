# 🚲 GKE Poc Toolkit Demo: GKE Fleet setup with ArgoCD
This demo shows you how to bootstrap a Fleet of GKE clusters using ArgoCD as your gitops engine.

## How to run 

1. **Go through the [GKE PoC Toolkit quickstart](https://github.com/GoogleCloudPlatform/gke-poc-toolkit#quickstart) up until the `gkekitctl create` and stop at step 6 (gkekitctl init).** 

2. **Copy `multi-clusters-networking-acm-standalone-vpc.yaml` from the samples folder to wherever you're running the toolkit from.**

```bash
cp samples/multi-clusters-networking-acm-standalone-vpc.yaml config.yaml
```

3. **Export vars and add them to your GKE POC toolkit config.yaml.**

``` bash 
export GKE_PROJECT_ID=<your-gke-clusters-project-id>
export VPC_PROJECT_ID=<your-sharedvpc-project-id>
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' -e "s/clustersProjectId: \"my-project\"/clustersProjectId: \"${GKE_PROJECT_ID}\"/g" config.yaml
  sed -i '' -e "s/governanceProjectId: \"my-project\"/governanceProjectId: \"${GKE_PROJECT_ID}\"/g" config.yaml
  sed -i '' -e "s/vpcProjectId: \"my-host-project\"/vpcProjectId: \"${VPC_PROJECT_ID}\"/g" config.yaml
else
  sed -i -e "s/clustersProjectId: \"my-project\"/clustersProjectId: \"${GKE_PROJECT_ID}\"/g" config.yaml
  sed -i -e "s/governanceProjectId: \"my-project\"/governanceProjectId: \"${GKE_PROJECT_ID}\"/g" config.yaml
  sed -i -e "s/vpcProjectId: \"my-host-project\"/vpcProjectId: \"${VPC_PROJECT_ID}\"/g" config.yaml
fi
```

4. **Run `./gkekitctl create --config config.yaml` from this directory.** This will take about 15 minutes to run.

5. **Connect to your newly-created GKE clusters**

```bash
gcloud container clusters get-credentials mccp-central-01 --region us-central1 --project ${GKE_PROJECT_ID}
```

6. **We highly recommend installing [kubectx and kubens](https://github.com/ahmetb/kubectx) to switch kubectl contexts between clusters with ease. Once done, you can validate you clusters like so.**

```bash
kubectx mccp-central-01=gke_${GKE_PROJECT_ID}_us-central1_mccp-central-01
kubectl get nodes
```

*Expected output for each cluster*: 
```bash
NAME                                                  STATUS   ROLES    AGE   VERSION
gke-mccp-central-01-linux-gke-toolkit-poo-12b0fa78-grhw   Ready    <none>   11m   v1.21.6-gke.1500
gke-mccp-central-01-linux-gke-toolkit-poo-24d712a2-jm5g   Ready    <none>   11m   v1.21.6-gke.1500
gke-mccp-central-01-linux-gke-toolkit-poo-6fb11d07-h6xb   Ready    <none>   11m   v1.21.6-gke.1500
```

7. **Create static public IP and free DNS names in the cloud.goog domain using Cloud Endpoints DNS service for your argocd UI. [Learn more about configuring DNS on the cloud.goog domain](https://cloud.google.com/endpoints/docs/openapi/cloud-goog-dns-configure).**

```bash
gcloud compute addresses create argocd-ip --global
export GCLB_IP=`gcloud compute addresses describe argocd-ip --global --format="value(address)"`
echo -e "GCLB_IP is ${GCLB_IP}"

cat <<EOF > argocd-openapi.yaml
swagger: "2.0"
info:
  description: "Cloud Endpoints DNS"
  title: "Cloud Endpoints DNS"
  version: "1.0.0"
paths: {}
host: "arogcd.endpoints.${GKE_PROJECT_ID}.cloud.goog"
x-google-endpoints:
- name: "arogcd.endpoints.${GKE_PROJECT_ID}.cloud.goog"
  target: "${GCLB_IP}"
EOF

gcloud endpoints services deploy argocd-openapi.yaml
```

8. **Generate config for the managed certificate that will be applied to the Ingress**
```bash
cat <<EOF > argo-cd-gke/argocd-managed-cert.yaml
apiVersion: networking.gke.io/v1
kind: ManagedCertificate
metadata:
  name: argocd-managed-cert
  namespace: argocd
spec:
  domains:
  - "argocd.endpoints.${GKE_PROJECT_ID}.cloud.goog"
EOF
```

9. **Install argocd with secure GKE Ingress Frontend and give that cluster a specific name to use later on by explicitly adding the cluster to argocd via the cli**
```bash
cat <<EOF > argo-cd-gke/argocd-server-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd
  namespace: argocd
  annotations:
    kubernetes.io/ingress.global-static-ip-name: argocd-ip 
    networking.gke.io/v1beta1.FrontendConfig: argocd-frontend-config
    networking.gke.io/managed-certificates: argocd-managed-cert
spec:
  rules:
    - host: "arogcd.endpoints.${GKE_PROJECT_ID}.cloud.goog"
      http:
        paths:
        - pathType: Prefix
          path: "/"
          backend:
            service:
              name: argocd-server
              port:
                number: 80
EOF

kubectl apply -k argo-cd-gke
ARGOCD_SECRET=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo)
argocd login "arogcd.endpoints.${GKE_PROJECT_ID}.cloud.goog" --username admin --password ${ARGOCD_SECRET} --grpc-web
argocd cluster add mccp-central-01 --in-cluster --label=env="multi-cluster-controller" --grpc-web -y

## Update your admin password
argocd account update-password --grpc-web

## Create ArgoCD Project for platform team
kubectl apply -f admin-argocd-project.yaml --context ${GKE_PROJECT_ID}
``` 

10. **Setup a git repo for argocd to sync from. I am going to create a private github repo using the githubcli and setup credtials for that repo. If you plan on using a different git service make sure you adjust these steps for auth with that service.**
```bash
cd argo-repo-sync && export SYNCDIR=`pwd`
git init
gh repo create argo-repo-sync --private --source=. --remote=upstream
git add . && git commit -m "Initial commit"
git push --set-upstream upstream main
REPO="https://github.com/"$(gh repo list | grep argo-repo-sync | awk '{print $1}')
##Get a github PAT token and add it here
PAT_TOKEN=
argocd repo add ${REPO} --username doesnotmatter --password $PAT_TOKEN --grpc-web
```

11. **Next we will create our first argocd applicationset. This application set leverages the matrix generator to create an argocd application for every folder in the argo-repo-sync/multi-cluster-controllers/ folder across every cluster whose argocd secret has a label "env=multi-cluster-controller". In this demo enviroment we have one cluster with that label.**  
```bash
cat <<EOF > generators/multi-cluster-controller-applicationset.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: mcc-clusters-config-generator
  namespace: argocd
spec:
  generators:
    - matrix:
        generators:
          - git:
              repoURL: ${REPO}
              revision: HEAD
              directories:
                - path: multi-cluster-controllers/*
          - clusters:
              selector:
                matchLabels:
                  env: "multi-cluster-controller"
  template:
    metadata:
      name: '{{name}}-{{path.basename}}'
    spec:
      project: "admin"
      source:
        repoURL: ${REPO}
        targetRevision: HEAD
        path: '{{path}}'
      destination:
        server: '{{server}}' # 'server' field of the secret
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
          allowEmpty: true
        retry:
          limit: 20
          backoff:
            duration: 5s
            factor: 2
            maxDuration: 5m
EOF
kubectl apply -f generators/multi-cluster-controller-applicationset.yaml --context ${CLUSTER_NAME}
```

12. **Now let's create the config necessary to install a multi cluster ingress for our demo apps that will be used by our app clusters later.**
```bash
gcloud compute addresses create asm-gw-ip --global --project ${GKE_PROJECT_ID}
export GCLB_IP=`gcloud compute addresses describe asm-gw-ip --global --format="value(address)"`
echo -e "GCLB_IP is ${GCLB_IP}"

cat <<EOF > rollout-demo-openapi.yaml
swagger: "2.0"
info:
  description: "Cloud Endpoints DNS"
  title: "Cloud Endpoints DNS"
  version: "1.0.0"
paths: {}
host: "rollout-demo.endpoints.${GKE_PROJECT_ID}.cloud.goog"
x-google-endpoints:
- name: "rollout-demo.endpoints.${GKE_PROJECT_ID}.cloud.goog"
  target: "${GCLB_IP}"
EOF

gcloud endpoints services deploy rollout-demo-openapi.yaml --project ${GKE_PROJECT_ID}

cat <<EOF > whereami-openapi.yaml
swagger: "2.0"
info:
  description: "Cloud Endpoints DNS"
  title: "Cloud Endpoints DNS"
  version: "1.0.0"
paths: {}
host: "whereami.endpoints.${GKE_PROJECT_ID}.cloud.goog"
x-google-endpoints:
- name: "whereami.endpoints.${GKE_PROJECT_ID}.cloud.goog"
  target: "${GCLB_IP}"
EOF

gcloud endpoints services deploy whereami-openapi.yaml --project ${GKE_PROJECT_ID}

##For now multicluster ingress has to get the uniq identifier for a managed certificate instead of using the friendly name. That means we are going to install the cert out of band of the config system.
cat <<EOF > multi-cluster-controllers/asm-gateways/rollout-demo-managed-cert.yaml
apiVersion: networking.gke.io/v1
kind: ManagedCertificate
metadata:
  name: rollout-demo-managed-cert
  namespace: istio-system
spec:
  domains:
  - "rollout-demo.endpoints.${GKE_PROJECT_ID}.cloud.goog"
EOF

cat <<EOF > multi-cluster-controllers/asm-gateways/whereami-managed-cert.yaml
apiVersion: networking.gke.io/v1
kind: ManagedCertificate
metadata:
  name: whereami-managed-cert
  namespace: istio-system
spec:
  domains:
  - "wherami.endpoints.${GKE_PROJECT_ID}.cloud.goog"
EOF

kubectl apply -f multi-cluster-controllers/asm-gateways/rollout-demo-managed-cert.yaml --
kubectl apply -f multi-cluster-controllers/asm-gateways/whereami-managed-cert.yaml

export WHEREAMI_MANAGED_CERT=$(kubectl -n istio-system get managedcertificate whereami-managed-cert -ojsonpath='{.status.certificateName}' --context ${CLUSTER_NAME})
export ROLLOUT_DEMO_MANAGED_CERT=$(kubectl -n istio-system get managedcertificate rollout-demo-managed-cert -ojsonpath='{.status.certificateName}' --context ${CLUSTER_NAME})

## Check to make sure that the cert ids are set. If not, wait a few seconds and run the previous command"
echo -e "${ROLLOUT_DEMO_MANAGED_CERT} \n${WHEREAMI_MANAGED_CERT}"

cat <<EOF > multi-cluster-controllers/asm-gateways/multi-cluster-ingress.yaml
apiVersion: networking.gke.io/v1beta1
kind: MultiClusterIngress
metadata:
  name: asm-ingressgateway-xlb-multicluster-ingress
  namespace: asm-gateways
  annotations:
    networking.gke.io/static-ip: "${GCLB_IP}"
    networking.gke.io/pre-shared-certs: "${ROLLOUT_DEMO_MANAGED_CERT},${WHEREAMI_MANAGED_CERT}"
spec:
  template:
    spec:
      backend:
        serviceName: asm-ingressgateway-xlb-multicluster-svc
        servicePort: 443
EOF
## Now push all of the changes to the sync repo
git add . && git commit -m "Added multi-cluster networking configs to the mcc."
git push
```



