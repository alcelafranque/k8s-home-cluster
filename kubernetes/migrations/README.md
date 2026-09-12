# Migration Rook 1.19 → 1.20, puis Ceph 19.2.6

Les manifests actifs préparent Rook **1.20.7**, ceph-csi-operator **1.0.4**,
Ceph-CSI **3.17.1** et le driver RBD seul. Le cluster reste en Ceph **19.2.3**
pour séparer les redémarrages Rook/CSI de la mise à jour Ceph.

État confirmé le 6 septembre 2026 : Rook 1.19.3, CSI operator 0.6.0,
CephCluster Ready / HEALTH_WARN. Le chart opérateur sur `main` avait déjà été
passé à 1.20.7 avec les anciennes images forcées. Ne pas réappliquer un chart
1.19 complet : cela pourrait remplacer des CRD/RBAC déjà mis à jour.
Les commandes ci-dessous n’ont pas été exécutées sur le cluster.

## 1. Contrôles avant modification

Vérifier le contexte, Kubernetes >= 1.31, les sauvegardes applicatives et le
retrait effectif de CephFS/RGW. La nouvelle Application CSI ne supprime pas un
ancien Driver CephFS : il faut confirmer qu’aucun PVC/PV ni client direct ne
l’utilise avant son retrait explicite.

```bash
kubectl config current-context
kubectl version
kubectl -n rook-ceph get cephcluster
kubectl -n rook-ceph get deploy rook-ceph-operator ceph-csi-controller-manager -o wide
kubectl -n rook-ceph get drivers.csi.ceph.io,operatorconfigs.csi.ceph.io
kubectl get pv,pvc -A
kubectl -n rook-ceph get pods
```

Depuis une toolbox existante ou un accès administrateur Ceph :

```bash
ceph status
ceph health detail
ceph versions
ceph osd stat
ceph pg stat
```

Diagnostiquer le HEALTH_WARN avant de poursuivre : le statut Ready ne suffit
pas. Attendre des PG `active+clean`, tous les OSD `up/in`, et l’absence de
recovery/backfill en cours. L’ancien inventaire mentionnait `MON_DISK_LOW` et
`BLUESTORE_SLOW_OP_ALERT` ; confirmer leur état actuel et les résoudre s’ils
persistent. Ne pas contourner les contrôles de santé de Rook.

Exporter la configuration actuelle dans un dossier privé ignoré par Git :

```bash
mkdir -p scratch/rook-preupgrade
chmod 700 scratch/rook-preupgrade
kubectl -n rook-ceph get drivers.csi.ceph.io -o yaml > scratch/rook-preupgrade/drivers.yaml
kubectl -n rook-ceph get operatorconfigs.csi.ceph.io -o yaml > scratch/rook-preupgrade/operatorconfigs.yaml
kubectl -n rook-ceph get cephcluster rook-ceph -o yaml > scratch/rook-preupgrade/cluster.yaml
```

Comparer ces exports aux rendus : le Driver conserve `rook-ceph.rbd.csi.ceph.com`,
le cluster CSI `rook-ceph`, le chemin kubelet, deux contrôleurs en hostNetwork,
les priorités et les ressources CPU/mémoire de l’inventaire. Les service accounts
sont désormais créés par le chart drivers. Les versions CSI/sidecars proviennent
du chart opérateur ; elles évoluent volontairement avec cette migration.

## 2. Palier temporaire Rook 1.19.11

Le guide Helm demande au moins Rook 1.19.5 avant 1.20. Pour cet état hybride
précis, mettre à jour seulement l’image de l’opérateur à 1.19.11, en conservant
CSI operator 0.6.0 et les CRD/RBAC déjà présents. Les Applications sont manuelles :
ne pas synchroniser `rook-ceph-operator` depuis `main` pendant ce palier.

```bash
kubectl -n rook-ceph patch deployment rook-ceph-operator --type=strategic \
  --patch-file kubernetes/migrations/rook-1.19.11/operator-image-patch.yaml
kubectl -n rook-ceph rollout status deployment/rook-ceph-operator --timeout=10m
kubectl -n rook-ceph logs deployment/rook-ceph-operator --tail=100
kubectl -n rook-ceph get cephcluster
```

Attendre aussi la fin des réconciliations/redémarrages Ceph et refaire les
contrôles de santé et un test de lecture/écriture RBD. Un Deployment disponible
ne signifie pas que tous les daemons ont fini leur mise à jour.
Si Rook signale des permissions ou CRD manquantes, arrêter et examiner le diff ;
ne pas remplacer les CRD par une ancienne version pour forcer ce palier.

## 3. Synchronisation Rook 1.20 et CSI

Publier les changements et faire apparaître la nouvelle Application
`ceph-csi-drivers` via le parent Argo CD. Elle reste manuelle, comme les deux
Applications Rook. Dans cet ordre, examiner le diff puis synchroniser **sans
prune, force ni replace** :

1. `rook-ceph-operator` : Rook 1.20.7, CSI operator 1.0.4 et leurs CRD/RBAC.
2. `ceph-csi-drivers` : OperatorConfig, Driver RBD et service accounts/RBAC.
3. `rook-ceph-cluster` : chart 1.20.7, Ceph toujours 19.2.3.

Ne pas attendre une validation complète des volumes entre 1 et 2 : la migration
nécessite les nouveaux service accounts pour rendre les drivers opérationnels.
En revanche, vérifier la disponibilité des opérateurs et CRD avant l’étape 2.
`FailOnSharedResource=true` doit rester activé : si Argo signale un objet déjà
suivi par une autre Application, examiner son propriétaire avant de transférer
la gestion. Les CephConnection et ClientProfile restent gérés par Rook.

```bash
kubectl -n rook-ceph rollout status deployment/rook-ceph-operator --timeout=10m
kubectl -n rook-ceph rollout status deployment/ceph-csi-controller-manager --timeout=10m
kubectl -n rook-ceph get drivers.csi.ceph.io,operatorconfigs.csi.ceph.io
kubectl -n rook-ceph get deploy,ds,pods
kubectl get csidrivers.storage.k8s.io
kubectl get storageclass ceph-block
kubectl -n rook-ceph get cephcluster
```

Si l’ancien Driver CephFS subsiste, après vérification de non-utilisation :

```bash
kubectl -n rook-ceph delete drivers.csi.ceph.io rook-ceph.cephfs.csi.ceph.com
```

Attendre les contrôleurs/DaemonSets RBD prêts, tester un nouveau PVC `ceph-block`
(création, écriture, remontage et relecture) et une application existante.
Ne pas supprimer les anciens service accounts ou finalizers en bloc.
Le chart cluster ajoute les ressources du job `cmd-reporter` et fixe les clés CSI
à `aes` ; les paramètres du pool bloc et de sa StorageClass ne changent pas.

## 4. Étape Ceph 19.2.6 séparée

Après validation complète de l’étape 3, la mise à jour se limite au tag Ceph.
Le rendu prêt à examiner se trouve dans `kubernetes/migrations/ceph-19.2.6` :

```bash
kustomize build --enable-helm kubernetes/migrations/ceph-19.2.6
```

Pour l’activer durablement, remplacer `cephImage.tag: v19.2.3` par `v19.2.6`
dans `kubernetes/apps/rook-ceph/values.yaml` (ou fusionner la PR #680 après
rebase), publier, puis synchroniser uniquement `rook-ceph-cluster`.
L’overlay sert de prévisualisation ; ne pas créer une seconde Application qui
adopterait le même CephCluster, ni revenir ensuite à un tag Ceph plus ancien.
Mettre aussi à jour l’image de la toolbox si elle existe hors de ce dépôt.

Attendre la fin du rolling upgrade, vérifier `ceph versions`, `ceph status`,
les PG et les lectures/écritures RBD. Une disponibilité momentanée du Deployment
opérateur ne prouve pas que tous les OSD ont fini leur mise à jour.

Cette version corrige des CVE et introduit le type de clé CephX `aes256k`.
Suivre la procédure officielle de rotation des clés des daemons après l’upgrade,
et vérifier `status.cephx` ; ne pas considérer le seul changement d’image comme
une remédiation complète. Conserver les clés **CSI en `aes`** tant que la prise
en charge AES256K de tous les noyaux clients n’est pas confirmée. CSI 3.17.1 est
nécessaire mais ne suffit pas à prouver cette compatibilité noyau. Ne pas imposer
`allowedCiphers: [aes256k]` ni retirer les anciennes clés utilisées par les volumes.

## Validation hors ligne

Prérequis : Helm, Kustomize, kubeconform, Python 3 et `PyYAML==6.0.3`.

```bash
./scripts/validate-manifests.sh rook-ceph-operator ceph-csi-drivers rook-ceph
./scripts/validate-rook-migration.sh
```

Les schémas Ceph/CSI viennent des CRD du chart opérateur épinglé, au lieu du
catalogue communautaire qui ne connaît pas encore `security.cephx.csi.keyType`.
La validation ne teste pas l’état du cluster, les admissions ni les montages.

PR remplacées par cette préparation : #681 (image Rook), #683 (chart cluster),
#686 (image CSI operator). #645 est repris pour épingler checkout.
#680 reste une étape distincte. Ne pas appliquer #685 (Ceph 21.1.0).

Références :
- [Migration Rook 1.20](https://rook.io/docs/rook/v1.20/Upgrade/rook-upgrade/)
- [Chart drivers et valeurs Rook](https://rook.io/docs/rook/v1.20/Helm-Charts/csi-drivers-chart/)
- [Remédiation CephX](https://rook.io/docs/rook/v1.20/Storage-Configuration/Advanced/cephx-key-rotation/#cve-2025-30156-resolution)
