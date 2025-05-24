#!/bin/bash
set -euo pipefail
#############################################################################################
# Variables
#############################################################################################
export KUBECONFIG=/tmp/.kube/config
overlay=kind
kube_context=kind-demo
#############################################################################################
# Create temporary file which contains generated manifests
#############################################################################################
manifests=$(mktemp /tmp/manifests.XXXXXXXXXX)
trap "rm -Rf $manifests" 0 2 3 15
#############################################################################################
# Create crds
#############################################################################################
for file in $(find manifests -mindepth 5 -maxdepth 5 -type f -regex "manifests/[^/]+/[^/]+/overlays/${overlay}/kustomization.yaml" -exec dirname {} \;|sort -u); do
  kustomize build --enable-helm --enable-alpha-plugins --load-restrictor LoadRestrictionsNone ${file} | yq -ojson | jq -s | jq '[.[] | select(.kind == "CustomResourceDefinition")]' | yq e '.[] | split_doc' -P > ${manifests}
  if [[ -s "${manifests}" ]]; then kubectl --context ${kube_context} apply --server-side=true --force-conflicts -f ${manifests}; fi
done
#############################################################################################
# Install kube-system componments
#############################################################################################
ns=kube-system
for file in $(find manifests -mindepth 5 -maxdepth 5 -type f -regex "manifests/${ns}/[^/]+/overlays/${overlay}/kustomization.yaml" -exec dirname {} \;|sort -u); do
  kustomize build --enable-helm --enable-alpha-plugins --load-restrictor LoadRestrictionsNone ${file} > ${manifests}
  if [[ -s "${manifests}" ]]; then kubectl --context ${kube_context} apply --server-side=true --force-conflicts -f ${manifests}; fi
done
#############################################################################################
# Initialize ArgoCD
#############################################################################################
ns=argocd
kubectl --context ${kube_context} get ns ${ns} --no-headers --output name || kubectl --context ${kube_context} create ns ${ns}
for file in $(find manifests -mindepth 5 -maxdepth 5 -type f -regex "manifests/${ns}/[^/]+/overlays/${overlay}/kustomization.yaml" -exec dirname {} \;|sort -u); do
  kustomize build --enable-helm --enable-alpha-plugins --load-restrictor LoadRestrictionsNone ${file} > ${manifests}
  if [[ -s "${manifests}" ]]; then kubectl --context ${kube_context} apply --server-side=true --force-conflicts -f ${manifests}; fi
done
until kubectl --context ${kube_context} -n ${ns} get pod -l 'app.kubernetes.io/part-of=argocd,!batch.kubernetes.io/job-name' -o name | grep -q .; do
  echo "En attente que les pods ArgoCD apparaissent..."
  sleep 2
done
kubectl --context ${kube_context} -n ${ns} wait --for=condition=Ready pod -l 'app.kubernetes.io/part-of=argocd,!batch.kubernetes.io/job-name' --timeout 10m
kubectl --context ${kube_context} -n ${ns} rollout restart deployment/argocd-applicationset-controller
#############################################################################################
# Print informations
#############################################################################################
host=$(kubectl --context ${kube_context} -n ${ns} get ingress argocd-server -ojsonpath='{.spec.rules[0].host}')
echo -e "\e[1m\e[32mhttp://${host}\e[0m" >&2
echo -e "\e[1m\e[32mkubectl --context ${kube_context} -n ${ns} get secrets/argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d \e[0m" >&2
