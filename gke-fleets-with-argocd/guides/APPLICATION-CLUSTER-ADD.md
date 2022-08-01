# Application Clusters Setup
At this point, we have the the multi-cluster controller cluster setup and we need to move on to getting the config repo hydrated with our app clusters configs. First step, we need to make the Anthos Service Mesh(ASM) managed control plane(MCP) which verions of ASM to use for our clusters by setting up the control plane revision object(CPR). We also need to setup the ASM Ingress Gateways that backend the multi-cluster Ingress we created in the last step. This setup has some challenges when using gitops at the moment because we have to ensure that the ASM MCP has detected that CPR and created a mutating webhook in each App cluster. This webhook mutates pods that are being injected with ASM proxies with the proper container image name, among other things, and the ASM GW is just one of these proxies. If the ASM GW pods are deployed before the mutating webhook is installed that GW pod will get stuck in an "image pull backoff" state and never start. ArgoCD has some annotations that helps us out here, sync-waves and hooks. Sync waves allow you to create an order of config creating and hooks, sync hooks particularly, allow you to require that an object deployment is successful after the wave you are in completes and before the next wave starts. To solve for ASM, we have create a  sync hook annotated kubernetes job that checks for the existence of the mutating webhook before the ASM GW deploys. Feel free to take a look at the asm-webhook-wait-job.yaml and deployment.yaml in the asm-gateways folder to see how this is configured.

1. **First we need to create an application set that will look in the "app-clusters-config" folder and generate an application for each folder it contains across all the clusters labeled in argoCD as env=prod.** 
```bash
cat <<EOF > generators/app-clusters-tooling-applicationset.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: app-clusters-config-generator
spec:
  generators:
  - matrix:
      generators:
        - git:
            repoURL: ${REPO}
            revision: HEAD
            directories:
              - path: app-clusters-config/*
        - clusters:
            selector:
              matchLabels:
                env: "prod"
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
        namespace: '{{path.basename}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
          allowEmpty: true
        syncOptions:
          - CreateNamespace=true
          - Validate=false
        retry:
          limit: 20
          backoff:
            duration: 5s
            factor: 2
            maxDuration: 5m
EOF
kubectl apply -f generators/app-clusters-tooling-applicationset.yaml -n argocd --context ${CLUSTER_NAME}

## Now push all of the changes to the sync repo
git add . && git commit -m "Added ASM Ingress Controller and App clusters config applicationset"
git push

gcloud projects add-iam-policy-binding ${GKE_PROJECT_ID} --role roles/monitoring.viewer --member "serviceAccount:${GKE_PROJECT_ID}.svc.id.goog[prod-tools/default]"
```

2. **Next we will create an application set that will look in the "app-clusters-config" folder and generate an application for each folder it contains across all the clusters labeled in argoCD as env=prod.**
```bash
cat <<EOF > generators/team-1-apps-applicationset.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: team-1-app-generator
spec:
  generators:
    - matrix:
        generators:
          - git:
              repoURL: ${REPO}
              revision: HEAD
              directories:
                - path: teams/team-1/*
          - clusters:
              selector:
                matchLabels:
                  region: "us-east1"
  template:
    metadata:
      name: '{{name}}-{{path.basename}}'
    spec:
      project: "team-1"
      source:
        repoURL: ${REPO}
        targetRevision: HEAD
        path: '{{path}}'
      destination:
        server: '{{server}}' # 'server' field of the secret
        namespace: '{{path.basename}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
          allowEmpty: true
        syncOptions:
          - CreateNamespace=true
          - ApplyOutOfSyncOnly=true
        retry:
          limit: 20
          backoff:
            duration: 5s
            factor: 2
            maxDuration: 5m
      ignoreDifferences:
      - group: networking.istio.io
        kind: VirtualService
        jsonPointers:
        - /spec/http/0
EOF
kubectl apply -f generators/team-1-apps-applicationset.yaml --context ${CLUSTER_NAME}
```

3. **Now we can create config for the whereami app and drop it in the team-1 folder**
```bash
cat <<EOF >team-1/whereami/patch.yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: virtualservice
spec:
  gateways:
  - asm-gateways/asm-ingress-gateway-xlb
  hosts:
  - whereami.endpoints.${GKE_PROJECT_ID}.cloud.goog
  http:
  - name: primary
    route:
    - destination:
        host: whereami-stable
        port:
          number: 80
      weight: 100
    - destination:
        host: whereami-canary
        port:
          number: 80
      weight: 0
EOF

## Now push all of the changes to the sync repo
git add . && git commit -m "Added whereami config and team-1 config applicationset"
git push
```

4. **Now we have everything set so that when add a new GKE cluster and join it to argocd with the right label an ASM GW and whereami will be deployed. I wrote a quick bash script to that adds a cluster, registers it to the GKE Fleet, and joins it to ArgoCD.**
```bash

../scripts/fleet_cluster_add.sh -p ${GKE_PROJECT_ID} -n gke-std-central01 -l us-central1-b -c "172.16.10.0/28" -t "autopilot" -w two```