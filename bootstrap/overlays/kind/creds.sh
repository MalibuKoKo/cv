#!/usr/bin/env bash

set -euo pipefail

export KUBECONFIG=/tmp/.kube/config

profile=$(for item in $(gdbus call --session --dest org.freedesktop.secrets --object-path "/org/freedesktop/secrets/collection/awsvault" --method org.freedesktop.Secret.Collection.SearchItems '{}' | grep -o "/org/freedesktop/secrets/collection/awsvault/[0-9]*"); do gdbus call --session --dest org.freedesktop.secrets --object-path "$item" --method org.freedesktop.DBus.Properties.Get org.freedesktop.Secret.Item Label 2>/dev/null | cut -d"'" -f2; done | sort -u | fzf --prompt="Choisir un profil AWS: ")

TMP_FILE=$(mktemp /tmp/aws.XXXXXXXXXX)
trap "rm -Rf $TMP_FILE" 0 2 3 15

echo -n "ns: "; until kubectl --context kind-demo get ns crossplane-system >/dev/null 2>&1; do echo -n "."; sleep 1; done; echo -n ". done"; echo
cat << EOF > ${TMP_FILE}
[default]
aws_access_key_id=$(secret-tool lookup profile "${profile}"|yq .Data|base64 -d|yq .AccessKeyID)
aws_secret_access_key=$(secret-tool lookup profile "${profile}"|yq .Data|base64 -d|yq .SecretAccessKey)
EOF

kubectl --context kind-demo --namespace crossplane-system create secret generic aws-org-admin --from-file=creds=${TMP_FILE} --dry-run=client -o yaml | kubectl --context kind-demo --namespace crossplane-system apply -f -
kubectl --context kind-demo --namespace crossplane-system annotate secret aws-org-admin argocd.argoproj.io/tracking-id=crossplane-system-config:/Secret:crossplane-system/aws-org-admin argocd.argoproj.io/compare-options=IgnoreExtraneous argocd.argoproj.io/sync-options=Prune=false

# echo -n "ns: "; until kubectl --context kind-demo get ns ambassador >/dev/null 2>&1; do echo -n "."; sleep 1; done; echo -n ". done"; echo
kubectl --context kind-demo get namespace ambassador || kubectl --context kind-demo create namespace ambassador

# secret-tool store --label="foo" profile foo
profile=$(for item in $(gdbus call --session --dest org.freedesktop.secrets --object-path "/org/freedesktop/secrets/collection/login" --method org.freedesktop.Secret.Collection.SearchItems '{}' | grep -o "/org/freedesktop/secrets/collection/login/[0-9]*"); do gdbus call --session --dest org.freedesktop.secrets --object-path "$item" --method org.freedesktop.DBus.Properties.Get org.freedesktop.Secret.Item Label 2>/dev/null | cut -d"'" -f2; done | sort -u | fzf --prompt="Choisir la license Ambassador Edge Stack: " -q "edge")
secret-tool lookup profile "${profile}" > ${TMP_FILE}

kubectl --context kind-demo --namespace ambassador create secret generic edge-stack-agent-cloud-token --from-file=CLOUD_CONNECT_TOKEN=${TMP_FILE} --dry-run=client -o yaml | kubectl --context kind-demo --namespace ambassador apply -f -
kubectl --context kind-demo --namespace ambassador annotate secret edge-stack-agent-cloud-token argocd.argoproj.io/tracking-id=ambassador-core:/Secret:ambassador/edge-stack-agent-cloud-token argocd.argoproj.io/compare-options=IgnoreExtraneous argocd.argoproj.io/sync-options=Prune=false