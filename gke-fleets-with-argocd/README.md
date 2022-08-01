# 🚲 GKE Poc Toolkit Demo: GKE Fleet setup with ArgoCD
This demo shows you how to bootstrap a Fleet of GKE clusters using ArgoCD as your gitops engine.

## Fleet Infra setup

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


