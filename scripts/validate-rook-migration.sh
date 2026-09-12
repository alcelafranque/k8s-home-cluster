#!/usr/bin/env bash
# Integration checks for storage identity and the separately staged Ceph upgrade.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validation_tmp="$(mktemp -d)"
trap 'rm -rf "$validation_tmp"' EXIT
for app in rook-ceph-operator ceph-csi-drivers rook-ceph; do
  kustomize build --enable-helm "${ROOT}/kubernetes/apps/${app}" > "${validation_tmp}/${app}.yaml"
done
kustomize build --enable-helm "${ROOT}/kubernetes/migrations/ceph-19.2.6" > "${validation_tmp}/ceph-update.yaml"
kustomize build "${ROOT}/kubernetes/apps/argocd/apps" > "${validation_tmp}/applications.yaml"
python3 "${ROOT}/scripts/crd-schemas.py" "${validation_tmp}/rook-ceph-operator.yaml" "${validation_tmp}/schemas"
python3 - "$validation_tmp" <<'PY'
import copy
from pathlib import Path
import sys
import yaml

root = Path(sys.argv[1])
def read(name):
    return [x for x in yaml.safe_load_all((root / name).read_text()) if x]
def one(docs, kind, name):
    matches = [x for x in docs if x['kind'] == kind and x['metadata']['name'] == name]
    assert len(matches) == 1, (kind, name, len(matches))
    return matches[0]

operator = read('rook-ceph-operator.yaml')
drivers = read('ceph-csi-drivers.yaml')
cluster = read('rook-ceph.yaml')
applications = read('applications.yaml')
assert {x['kind'] for x in cluster} == {'CephCluster', 'CephBlockPool', 'StorageClass'}
sc = one(cluster, 'StorageClass', 'ceph-block')
rbd_name = sc['provisioner']
assert rbd_name == 'rook-ceph.rbd.csi.ceph.com'
assert sc['parameters']['clusterID'] == 'rook-ceph'
assert sc['parameters']['pool'] == 'ceph-blockpool'
assert sc['reclaimPolicy'] == 'Delete'
assert sc['metadata']['annotations']['storageclass.kubernetes.io/is-default-class'] == 'true'
pool = one(cluster, 'CephBlockPool', 'ceph-blockpool')
assert pool['spec']['replicated']['size'] == 3
assert [x['metadata']['name'] for x in drivers if x['kind'] == 'Driver'] == [rbd_name]
assert not any(x['kind'] in ('CephConnection', 'ClientProfile') for x in drivers)
rbd = one(drivers, 'Driver', rbd_name)['spec']
assert rbd['controllerPlugin']['replicas'] == 2
assert rbd['controllerPlugin']['hostNetwork'] is True
assert rbd['controllerPlugin']['deploymentStrategy']['type'] == 'Recreate'
assert rbd['clusterName'] == 'rook-ceph'
assert rbd['snapshotPolicy'] == 'volumeGroupSnapshot'
config = one(drivers, 'OperatorConfig', 'ceph-csi-operator-config')['spec']['driverSpecDefaults']
assert config['nodePlugin']['kubeletDirPath'] == '/var/lib/kubelet'
# Referenced image set and service accounts must be supplied by these charts.
one(operator, 'ConfigMap', rbd['imageSet']['name'])
for plugin in ('controllerPlugin', 'nodePlugin'):
    sa = rbd[plugin]['serviceAccountName']
    one(drivers, 'ServiceAccount', sa)
    bindings = [x for x in drivers if x['kind'] in ('RoleBinding', 'ClusterRoleBinding')
                and any(s.get('kind') == 'ServiceAccount' and s.get('name') == sa
                        and s.get('namespace') == 'rook-ceph' for s in x.get('subjects', []))]
    assert bindings, sa
for name in ('rook-ceph-operator', 'ceph-csi-drivers', 'rook-ceph-cluster'):
    app = one(applications, 'Application', name)
    assert 'automated' not in app['spec']['syncPolicy']
    assert not app['metadata'].get('finalizers')
    assert 'FailOnSharedResource=true' in app['spec']['syncPolicy']['syncOptions']
for obj in operator + drivers + cluster:
    assert obj['metadata']['annotations']['argocd.argoproj.io/sync-options'] == 'Prune=false,Delete=false'
# The second stage must alter only the Ceph image.
expected = copy.deepcopy(cluster)
ceph = one(expected, 'CephCluster', 'rook-ceph')
# Works both before and after applying the separate 19.2.6 update.
assert ceph['spec']['cephVersion']['image'].startswith('quay.io/ceph/ceph:')
assert ceph['spec']['security']['cephx']['csi']['keyType'] == 'aes'
ceph['spec']['cephVersion']['image'] = 'quay.io/ceph/ceph:v19.2.6'
assert expected == read('ceph-update.yaml')
# A malformed known field must still be rejected by the new schema path.
invalid = copy.deepcopy(ceph)
invalid['spec']['mon']['count'] = 'invalid-count'
(root / 'invalid.yaml').write_text(yaml.safe_dump(invalid))
print('RBD identity, dependencies, manual sync and isolated Ceph stage: OK')
PY
schema_location="${validation_tmp}/schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
kubeconform -schema-location "$schema_location" -schema-location default -summary "${validation_tmp}/ceph-update.yaml"
if kubeconform -schema-location "$schema_location" "${validation_tmp}/invalid.yaml" > "${validation_tmp}/negative.log" 2>&1; then
  echo 'ERROR: invalid CephCluster was accepted' >&2
  exit 1
fi
# Distinguish a real validation failure from a missing schema or download error.
if ! rg -q 'mon/count|/spec/mon/count' "${validation_tmp}/negative.log"; then
  cat "${validation_tmp}/negative.log" >&2
  exit 1
fi
echo 'Malformed CephCluster correctly rejected by the bundled CRD schema'
