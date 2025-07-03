timeout := "300s"

# List tasks.
default:
  just --list


# Bump version
bump:
  git pull
  git fetch --all --tags
  cz bump --changelog --increment $(gum choose PATCH MINOR MAJOR)
  git push origin $(git tag --sort v:refname | cat | tail -n 1)
  git push origin

# Destroys the cluster
stop:
  kind delete cluster --name demo

# Creates a kind cluster
start:
  git submodule update --recursive --init
  hostctl list domains demo argocd.apps.io --out json | jq -e '.[] | select(.IP == "172.40.255.205" and .Status == "on")' || sudo $DEVBOX_PACKAGES_DIR/bin/hostctl add domains demo argocd.apps.io --ip 172.40.255.205
  hostctl list domains demo edge.infra.lan   --out json | jq -e '.[] | select(.IP == "172.40.255.206" and .Status == "on")' || sudo $DEVBOX_PACKAGES_DIR/bin/hostctl add domains demo edge.infra.lan   --ip 172.40.255.206
  mkcert -install
  [ -f manifests/ingress-nginx/core/overlays/kind/tls/tls.crt ] || mkcert -cert-file manifests/ingress-nginx/core/overlays/kind/tls/tls.crt -key-file manifests/ingress-nginx/core/overlays/kind/tls/tls.key apps.io '*.apps.io' 172.40.255.205
  [ -f manifests/ambassador/core/overlays/kind_/tls/tls.crt    ] || mkcert -cert-file manifests/ambassador/core/overlays/kind_/tls/tls.crt -key-file manifests/ambassador/core/overlays/kind_/tls/tls.key infra.lan '*.infra.lan' 172.40.255.206
  docker network inspect kind || docker network create --subnet=172.40.0.0/16 kind
  if [[ $(cat /proc/sys/fs/inotify/max_user_watches) -ne 1048576 ]]; then sudo sysctl fs.inotify.max_user_watches=1048576; fi
  if [[ $(cat /proc/sys/fs/inotify/max_user_instances) -ne 8192  ]]; then sudo sysctl fs.inotify.max_user_instances=8192;  fi
  kind get clusters | grep -q "^demo$" || kind create cluster --name demo --config bootstrap/overlays/kind/config.yaml
  kind export kubeconfig --name demo
  kubectl config use-context kind-demo > /dev/null 2>&1
  bootstrap/overlays/kind/start.sh
  bootstrap/overlays/kind/creds.sh
