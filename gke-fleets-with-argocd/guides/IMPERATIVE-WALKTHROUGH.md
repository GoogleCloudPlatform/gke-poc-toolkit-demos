# Imperative Walkthrough
If you want to go through setting the Fleet up step by step, this doc is your jam.

## Fleet Cluster setup

1. **Create static public IP and free DNS names in the cloud.goog domain using Cloud Endpoints DNS service for your argocd UI. [Learn more about configuring DNS on the cloud.goog domain](https://cloud.google.com/endpoints/docs/openapi/cloud-goog-dns-configure).**

```bash
gcloud compute addresses create argocd-ip --global --project ${GKE_PROJECT_ID}
export GCLB_IP=$(gcloud compute addresses describe argocd-ip --project ${GKE_PROJECT_ID} --global --format="value(address)")
echo -e "GCLB_IP is ${GCLB_IP}"

cat <<EOF > argocd-openapi.yaml
swagger: "2.0"
info:
  description: "Cloud Endpoints DNS"
  title: "Cloud Endpoints DNS"
  version: "1.0.0"
paths: {}
host: "argocd.endpoints.${GKE_PROJECT_ID}.cloud.goog"
x-google-endpoints:
- name: "argocd.endpoints.${GKE_PROJECT_ID}.cloud.goog"
  target: "${GCLB_IP}"
EOF

gcloud endpoints services deploy argocd-openapi.yaml --project ${GKE_PROJECT_ID}
```

2. **Generate config for the managed certificate that will be applied to the Ingress**
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

2. **Install argocd with secure GKE Ingress Frontend and give that cluster a specific name to use later on by explicitly adding the cluster to argocd via the cli**
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
    - host: "argocd.endpoints.${GKE_PROJECT_ID}.cloud.goog"
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
argocd login "argocd.endpoints.${GKE_PROJECT_ID}.cloud.goog" --username admin --password ${ARGOCD_SECRET} --grpc-web
argocd cluster add mccp-central-01 --in-cluster --label=env="multi-cluster-controller" --grpc-web -y

## Update your admin password
argocd account update-password --grpc-web

## Create ArgoCD Project for platform team and app team
kubectl apply -f admin-argocd-project.yaml --context ${CLUSTER_NAME}
``` 

4. **Setup a git repo for argocd to sync from. I am going to create a private github repo using the githubcli and setup credtials for that repo. If you plan on using a different git service make sure you adjust these steps for auth with that service.**
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

5. **Next we will create our first argocd applicationset. This application set leverages the matrix generator to create an argocd application for every folder in the argo-repo-sync/multi-cluster-controllers/ folder across every cluster whose argocd secret has a label "env=multi-cluster-controller". In this demo enviroment we have one cluster with that label.**  
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
kubectl apply -f generators/multi-cluster-controller-applicationset.yaml -n argocd --context ${CLUSTER_NAME}
```

6. **Now let's create the config necessary to install a multi cluster ingress for our demo apps that will be used by our app clusters later.**
```bash
gcloud compute addresses create asm-gw-ip --global --project ${GKE_PROJECT_ID}
export ASM_GW_IP=`gcloud compute addresses describe asm-gw-ip --global --format="value(address)"`
echo -e "GCLB_IP is ${ASM_GW_IP}"

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
  target: "${ASM_GW_IP}"
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
  target: "${ASM_GW_IP}"
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
  - "whereami.endpoints.${GKE_PROJECT_ID}.cloud.goog"
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
    networking.gke.io/static-ip: "${ASM_GW_IP}"
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


