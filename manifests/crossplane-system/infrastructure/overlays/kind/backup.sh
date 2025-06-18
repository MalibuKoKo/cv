#!/bin/bash

set -euo pipefail

CLUSTERPOLICY_NAME=demo

NAMESPACE=crossplane-system
COMPOSITE_NAME=$(kubectl -n $NAMESPACE get clusterclaims.devopstoolkitseries.com demo -ojsonpath='{.spec.resourceRef.name}')

# 1. Extraire les resourceRefs
TMP_FILE=$(mktemp /tmp/resourceRefs.XXXXXXXXXX)
kubectl -n $NAMESPACE get compositeclusters.devopstoolkitseries.com $COMPOSITE_NAME -ojsonpath='{.spec.resourceRefs}' | yq -P > "$TMP_FILE"

# 2. Initialiser un fichier de ClusterPolicy
DATA_FILE=$(mktemp /tmp/ClusterPolicy.XXXXXXXXXX)
cat << EOF > $DATA_FILE
apiVersion: kyverno.io/v2beta1
kind: ClusterPolicy
metadata:
  name: mutate-cluster
spec:
  rules:
EOF

# 3. Boucle sur chaque ressource
yq -o=json e '.' "$TMP_FILE" | jq -c '.[]' | while read -r res; do
  kind=$(echo "$res" | jq -r '.kind')
  name=$(echo "$res" | jq -r '.name')
  apiVersion=$(echo "$res" | jq -r '.apiVersion')

  # Extraire l'annotation crossplane.io/external-name
  external_name=$(kubectl get "$kind" "$name" \
    --namespace "$NAMESPACE" \
    -ojsonpath='{.metadata.annotations.crossplane\.io/external-name}' 2>/dev/null || true)

  if [[ -n "$external_name" ]]; then
    key="${kind}.${name}"
    echo '  - name: '$key >> "$DATA_FILE"
    echo '    match: {"resources": {"names": ["'$name'"], "kinds": ["'$apiVersion/$kind'"]}}' >> "$DATA_FILE"
    echo '    mutate: {"patchStrategicMerge": {"metadata": {"annotations": {"crossplane.io/external-name": "'$external_name'"}}}}' >> "$DATA_FILE"
  fi
done

mv $DATA_FILE backup.yaml