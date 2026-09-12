#!/usr/bin/env bash
# Validate kubernetes manifests: kustomize build --enable-helm + kubeconform.
#
# Usage:
#   ./scripts/validate-manifests.sh              # validate every app
#   ./scripts/validate-manifests.sh cilium loki  # validate specific apps only
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPS_DIR="${ROOT}/kubernetes/apps"

# CRDs (CNPG, Gateway API, Cilium, 1Password, ...) are validated against the
# community CRDs-catalog; anything not in the catalog is skipped rather than
# failing the build.
KUBECONFORM_ARGS=(
  -schema-location default
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
  -ignore-missing-schemas
  -summary
)

if [[ $# -gt 0 ]]; then
  apps=("$@")
else
  apps=()
  for dir in "${APPS_DIR}"/*/; do
    apps+=("$(basename "${dir}")")
  done
fi

# Prefer the schemas shipped with the selected Rook operator chart. The public
# catalog can lag behind new Ceph/CSI fields (for example CephX keyType).
validation_tmp="$(mktemp -d)"
trap 'rm -rf "$validation_tmp"' EXIT
for app in "${apps[@]}"; do
  case "$app" in
    rook-ceph|rook-ceph-operator|ceph-csi-drivers)
      kustomize build --enable-helm "${APPS_DIR}/rook-ceph-operator" > "${validation_tmp}/operator.yaml"
      python3 "${ROOT}/scripts/crd-schemas.py" "${validation_tmp}/operator.yaml" "${validation_tmp}/schemas"
      KUBECONFORM_ARGS=(
        -schema-location "${validation_tmp}/schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
        "${KUBECONFORM_ARGS[@]}"
      )
      break
      ;;
  esac
done

failed=()
for app in "${apps[@]}"; do
  dir="${APPS_DIR}/${app}"
  if [[ ! -f "${dir}/kustomization.yaml" ]]; then
    echo "SKIP ${app} (no kustomization.yaml)"
    continue
  fi
  [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::group::${app}"
  echo "=== ${app} ==="
  if ! kustomize build --enable-helm "${dir}" | kubeconform "${KUBECONFORM_ARGS[@]}"; then
    failed+=("${app}")
    [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::error title=validation failed::${app} failed kustomize build or kubeconform"
  fi
  [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::endgroup::"
done

echo
if [[ ${#failed[@]} -gt 0 ]]; then
  echo "FAILED: ${failed[*]}"
  exit 1
fi
echo "OK: all apps validated"
