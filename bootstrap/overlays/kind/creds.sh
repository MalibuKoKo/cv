#!/usr/bin/env bash

set -euo pipefail

# vars
KUBE_CONTEXT=kind-demo
NAMESPACE=crossplane-system
CRD=providerconfigs.aws.upbound.io
PROVIDER_CONFIG=default
SECRET=aws-org-admin
K_ARGS="--context ${KUBE_CONTEXT} --namespace ${NAMESPACE}"


export KUBECONFIG=/tmp/.kube/config
TMP_FILE=$(mktemp /tmp/aws.XXXXXXXXXX)
trap "rm -Rf $TMP_FILE" 0 2 3 15


AWS_PROFILE=$(aws-vault list --profiles | fzf --prompt="Choisir un profil AWS: " -q iac)
echo -n "ns: "; until kubectl ${K_ARGS} get ns ${NAMESPACE} >/dev/null 2>&1; do echo -n "."; sleep 1; done; echo -n ". done"; echo

aws-vault export ${AWS_PROFILE} --format ini > ${TMP_FILE}
sed -i "s/${AWS_PROFILE}/default/" ${TMP_FILE}
kubectl ${K_ARGS} create secret generic ${SECRET} --from-file=creds=${TMP_FILE} --dry-run=client -o yaml | kubectl ${K_ARGS} apply -f -
echo "crd: "; until kubectl ${K_ARGS} get crd ${CRD} >/dev/null 2>&1; do echo -n "."; sleep 1; done; echo -n ". done"; echo
echo "object: "; until kubectl ${K_ARGS} get ${CRD} ${PROVIDER_CONFIG} >/dev/null 2>&1; do echo -n "."; sleep 1; done; echo -n ". done"; echo
HASH=$(kubectl ${K_ARGS} get secret ${SECRET} -o json | sha256sum | cut -d ' ' -f1)
kubectl ${K_ARGS} annotate ${CRD} ${PROVIDER_CONFIG} credsHash="$HASH" --overwrite
kubectl ${K_ARGS} apply -f bootstrap/overlays/kind/account.yaml