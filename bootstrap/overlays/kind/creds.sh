#!/usr/bin/env bash

set -euo pipefail

export KUBECONFIG=/tmp/.kube/config

profile=$(for item in $(gdbus call --session --dest org.freedesktop.secrets --object-path "/org/freedesktop/secrets/collection/awsvault" --method org.freedesktop.Secret.Collection.SearchItems '{}' | grep -o "/org/freedesktop/secrets/collection/awsvault/[0-9]*"); do gdbus call --session --dest org.freedesktop.secrets --object-path "$item" --method org.freedesktop.DBus.Properties.Get org.freedesktop.Secret.Item Label 2>/dev/null | cut -d"'" -f2; done | fzf --prompt="Choisir un profil AWS: ")

echo -n "ns: "; until kubectl --context kind-demo get ns crossplane-system >/dev/null 2>&1; do echo -n "."; sleep 1; done; echo -n ". done"; echo
TMP_FILE=$(mktemp /tmp/aws.XXXXXXXXXX)
trap "rm -Rf $TMP_FILE" 0 2 3 15

cat << EOF > ${TMP_FILE}
[default]
aws_access_key_id=$(secret-tool lookup profile "${profile}"|yq .Data|base64 -d|yq .AccessKeyID)
aws_secret_access_key=$(secret-tool lookup profile "${profile}"|yq .Data|base64 -d|yq .SecretAccessKey)
EOF

kubectl --context kind-demo --namespace crossplane-system create secret generic aws-org-admin --from-file=creds=${TMP_FILE} --dry-run=client -o yaml | kubectl --context kind-demo --namespace crossplane-system apply -f -
kubectl --context kind-demo --namespace crossplane-system annotate secret aws-org-admin argocd.argoproj.io/tracking-id=crossplane-system-config:/Secret:crossplane-system/aws-org-admin argocd.argoproj.io/compare-options=IgnoreExtraneous argocd.argoproj.io/sync-options=Prune=false
