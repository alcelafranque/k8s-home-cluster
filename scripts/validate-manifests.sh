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
