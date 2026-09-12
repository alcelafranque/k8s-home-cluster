#!/usr/bin/env bash
# Read-only inventory for adopting an existing Rook installation into Argo CD.
# Run from a machine with kubectl access. Output stays in gitignored scratch/.
set -euo pipefail
umask 077

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <kubectl-context>" >&2
  exit 2
fi
command -v kubectl >/dev/null || { echo "kubectl is required" >&2; exit 1; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "${ROOT}/scratch"
OUT="$(mktemp -d "${ROOT}/scratch/rook-inventory.XXXXXX")"
KUBE=(kubectl --context "$1" --request-timeout=30s)
trap 'echo "Collection incomplete; inspect errors. Partial output: ${OUT}" >&2' ERR

printf '%s\n' "$1" > "${OUT}/context.txt"
"${KUBE[@]}" version -o json > "${OUT}/kubernetes-version.json"
"${KUBE[@]}" get cephclusters.ceph.rook.io -A -o json > "${OUT}/cephclusters.json"
# Discover installed resource types instead of assuming a particular Rook/CSI version.
"${KUBE[@]}" api-resources --api-group=ceph.rook.io --verbs=list -o name > "${OUT}/rook-resource-types.txt"
"${KUBE[@]}" api-resources --api-group=csi.ceph.io --verbs=list -o name > "${OUT}/csi-resource-types.txt"
while IFS= read -r resource; do
  [[ -n "$resource" ]] || continue
  "${KUBE[@]}" get "$resource" -A -o json > "${OUT}/${resource}.json"
done < <(cat "${OUT}/rook-resource-types.txt" "${OUT}/csi-resource-types.txt")
"${KUBE[@]}" get storageclasses.storage.k8s.io -o json > "${OUT}/storageclasses.json"
# Only pod identity and images; no environment variables or mounted credentials.
"${KUBE[@]}" get pods -A -o 'custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,IMAGES:.spec.containers[*].image' > "${OUT}/pod-images.txt"
if command -v helm >/dev/null; then
  helm --kube-context "$1" list -A -o json > "${OUT}/helm-releases.json"
  # Release names/namespaces confirmed in this repository's September inventory.
  # Values may contain credentials: keep these private and review before committing.
  helm --kube-context "$1" get values rook-ceph -n rook-ceph -o json > "${OUT}/operator-values.json"
  helm --kube-context "$1" get values rook-ceph-cluster -n rook-ceph -o json > "${OUT}/cluster-values.json"
  # The chart currently served by the repository can differ from the installed release.
  helm --kube-context "$1" get manifest rook-ceph -n rook-ceph > "${OUT}/operator-manifest.yaml"
else
  echo "Helm unavailable: release inventory skipped." > "${OUT}/helm-unavailable.txt"
fi
printf 'Read-only inventory saved to %s\nNo Kubernetes objects changed. No Kubernetes Secrets exported.\n' "$OUT"
