#!/bin/bash

export GH_ORG=dtsong
export KUBECONFIG=$PWD/kubeconfig.yaml

# Feel free to use any other Kubernetes cluster
kind create cluster --config kind.yaml

# NGINX Ingress installation might differ for your k8s provider
kubectl apply \
    --filename https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/kind/deploy.yaml

# If not using kind, replace `127.0.0.1.nip.io` with the base host accessible through NGINX Ingress
export BASE_HOST=127.0.0.1.nip.io

############################
# Setup: Deploy Crossplane #
############################

# Watch https://youtu.be/n8KjVmuHm7A if you are not familiar with Crossplane

helm repo add crossplane-stable \
    https://charts.crossplane.io/stable

helm repo update

helm upgrade --install \
    crossplane crossplane-stable/crossplane \
    --namespace crossplane-system \
    --create-namespace \
    --wait

##############
# Setup: GCP #
##############

export PROJECT_ID=devops-toolkit-$(date +%Y%m%d%H%M%S)

gcloud projects create $PROJECT_ID

echo https://console.cloud.google.com/marketplace/product/google/container.googleapis.com?project=$PROJECT_ID

# Open the URL and *ENABLE* the API

echo https://console.developers.google.com/apis/library/sqladmin.googleapis.com?project=$PROJECT_ID

# Open the URL and *ENABLE* the API

export SA_NAME=devops-toolkit

export SA="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud iam service-accounts \
    create $SA_NAME \
    --project $PROJECT_ID

export ROLE=roles/admin

gcloud projects add-iam-policy-binding \
    --role $ROLE $PROJECT_ID \
    --member serviceAccount:$SA

gcloud iam service-accounts keys \
    create creds.json \
    --project $PROJECT_ID \
    --iam-account $SA

kubectl --namespace crossplane-system \
    create secret generic gcp-creds \
    --from-file key=./creds.json

kubectl crossplane install provider \
    crossplane/provider-gcp:v0.15.0

kubectl get providers

# Repeat the previous command until `HEALTHY` column is set to `True`

echo "apiVersion: gcp.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  projectID: $PROJECT_ID
  credentials:
    source: Secret
    secretRef:
      namespace: crossplane-system
      name: gcp-creds
      key: key" \
    | kubectl apply --filename -

#########################
# Setup: Deploy Argo CD #
#########################

# Watch https://youtu.be/vpWQeoaiRM4 if you are not familiar with Argo CD

cat argo-cd/base/ingress.yaml \
    | sed -e "s@acme.com@argo-cd.$BASE_HOST@g" \
    | tee argo-cd/overlays/production/ingress.yaml

cat controller/argo-cd.yaml \
    | sed -e "s@vfarcic@$GH_ORG@g" \
    | tee controller/argo-cd.yaml

cat controller/gke.yaml \
    | sed -e "s@vfarcic@$GH_ORG@g" \
    | tee controller/gke.yaml

cat controller/devops-toolkit.yaml \
    | sed -e "s@vfarcic@$GH_ORG@g" \
    | tee controller/devops-toolkit.yaml

cat apps.yaml \
    | sed -e "s@vfarcic@$GH_ORG@g" \
    | tee apps.yaml

git add .

git commit -m "Initial commit"

git push origin install-script

# Watch https://youtu.be/Twtbg6LFnAg if you are not familiar with Kustomize

kustomize build \
    argo-cd/overlays/production \
    | kubectl apply --filename -

kubectl --namespace argocd \
    rollout status \
    deployment argocd-server

export PASS=$(kubectl \
    --namespace argocd \
    get secret argocd-initial-admin-secret \
    --output jsonpath="{.data.password}" \
    | base64 --decode)

argocd login \
    --insecure \
    --username admin \
    --password $PASS \
    --grpc-web \
    argo-cd.$BASE_HOST

argocd account update-password \
    --current-password $PASS \
    --new-password admin123

argocd login \
    --insecure \
    --username admin \
    --password admin123 \
    --grpc-web \
    argo-cd.$BASE_HOST

kubectl apply --filename project.yaml

#######################
# Exploring manifests #
#######################

cat gke/k8s.yaml

cat controller/gke.yaml

cat devops-toolkit/app/k8s.yaml

cat controller/devops-toolkit.yaml

cat devops-toolkit/db/k8s.yaml

cat controller/devops-toolkit-db.yaml

######################
# Applying manifests #
######################

echo http://argo-cd.$BASE_HOST

# Open it and log in using `admin` as both the username and password

cat apps.yaml

kubectl apply --filename apps.yaml

echo https://console.cloud.google.com/kubernetes/list?project=$PROJECT_ID

# Open the URL

echo https://console.cloud.google.com/sql/instances?project=$PROJECT_ID

# Open the URL

gcloud container clusters \
    get-credentials devops-toolkit \
    --region us-east1 \
    --project $PROJECT_ID

kubectl config current-context

# Replace `[...]` with the context
argocd cluster add [...] \
    --name gke

argocd cluster list

# Open `controller/devops-toolkit.yaml` in your favorite editor
# Change `spec.destination.server` to the `SERVER` value from the previous output

git add .

git commit -m "New destination"

git push origin install-script

kubectl --namespace production get pods

########################
# Destroying resources #
########################

rm controller/devops-toolkit-db.yaml

rm controller/devops-toolkit.yaml

git add .

git commit -m "Not any more"

git push origin install-script

echo https://console.cloud.google.com/sql/instances?project=$PROJECT_ID

# Open the URL

kubectl --namespace production get pods
