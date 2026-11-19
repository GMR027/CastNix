#!/usr/bin/env bash
# Despliega la landing de CastNix: construye la imagen, la sube a Docker Hub y actualiza el release de Helm.
# Uso: ./deploy/deploy.sh            (despliegue normal)
#      DRY_RUN=1 ./deploy/deploy.sh  (solo construye y valida el chart; no sube ni despliega)
set -euo pipefail
cd "$(dirname "$0")/.."

NAMESPACE="${NAMESPACE:-castnix}"
RELEASE="${RELEASE:-castnix}"
IMAGE="${IMAGE:-gmr27/castnix}"
CHART="deploy/helm/castnix"
TAG="${TAG:-$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short HEAD 2>/dev/null || echo local)}"

for cmd in docker helm kubectl; do
  command -v "$cmd" >/dev/null || { echo "Falta '$cmd' en el PATH" >&2; exit 1; }
done

if [[ -n "$(git status --porcelain -- index.html assets deploy Dockerfile 2>/dev/null)" ]]; then
  echo "⚠ Hay cambios sin commitear en la landing: se desplegarán igualmente (etiqueta $TAG)."
fi

echo "▶ Contexto de Kubernetes: $(kubectl config current-context) · namespace: $NAMESPACE"
echo "▶ Construyendo $IMAGE:$TAG"
docker build --platform linux/amd64 -t "$IMAGE:$TAG" -t "$IMAGE:latest" .

helm lint "$CHART" >/dev/null
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  helm template "$RELEASE" "$CHART" --namespace "$NAMESPACE" --set image.tag="$TAG" >/dev/null
  echo "✔ DRY_RUN: imagen construida y chart válido. No se subió ni se desplegó nada."
  exit 0
fi

echo "▶ Subiendo imagen"
docker push "$IMAGE:$TAG"
docker push "$IMAGE:latest"

echo "▶ Desplegando con Helm"
helm upgrade --install "$RELEASE" "$CHART" \
  --namespace "$NAMESPACE" --create-namespace \
  --set image.tag="$TAG" \
  --wait --timeout 3m --atomic

kubectl -n "$NAMESPACE" rollout status "deploy/$RELEASE" --timeout=120s
echo "✔ Desplegado $IMAGE:$TAG → https://castnix.iguzman.com.mx"
