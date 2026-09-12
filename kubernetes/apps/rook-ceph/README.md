# Cluster Rook-Ceph

Le chart `rook-ceph-cluster` est fixé à **v1.20.7**. Il conserve le CephCluster
`rook-ceph`, le CephBlockPool `ceph-blockpool` et la StorageClass par défaut
`ceph-block`. CephFS et RGW sont explicitement désactivés par des listes vides.
Le cluster et le pool bloc gardent leurs paramètres de réplication et de disques
(`useAllNodes: true`, `useAllDevices: true`).

**Ceph reste en v19.2.3 pendant la migration Rook/CSI.** La mise à jour de sécurité
v19.2.6 est préparée dans une étape distincte. Le chart 1.20 ajoute les ressources
du job `cmd-reporter` et conserve les clés CSI de type `aes` pour les clients
noyau existants.

L’Application est manuelle, avec `Prune=false,Delete=false` et sans finalizer de
suppression en cascade. Ne pas désinstaller les anciennes releases Helm après
adoption par Argo CD. Ne pas utiliser Force/Replace ni forcer les finalizers.

Voir [la procédure de migration](../../migrations/README.md) pour le palier
Rook 1.19.11, l’ordre des trois Applications et l’étape Ceph 19.2.6. L’état vivant
confirmé avant migration était Rook 1.19.3 / CSI operator 0.6.0 / HEALTH_WARN ;
le rendu valide ne prouve pas que ce warning est résolu.

## Retrait de CephFS et du stockage objet

Le dépôt désactive CephFS et RGW. Le driver RBD est déclaré dans
`../ceph-csi-drivers` ; les versions CSI suivent le chart opérateur épinglé.
Les protections `Prune=false,Delete=false` empêchent Argo CD de supprimer les
anciennes ressources lors de la synchronisation : leur retrait est explicite.
Ne pas désinstaller les releases Helm complètes, le CephCluster ou le pool bloc.

Depuis une machine connectée au bon cluster, avant de synchroniser l’opérateur :

```bash
kubectl get pvc -A -o wide
kubectl get pv -o custom-columns=NAME:.metadata.name,CLASS:.spec.storageClassName,DRIVER:.spec.csi.driver,STATUS:.status.phase
kubectl get objectbucketclaims.objectbucket.io -A
kubectl get objectbuckets.objectbucket.io
kubectl -n rook-ceph get cephobjectstoreusers.ceph.rook.io
kubectl -n rook-ceph get cephfilesystem ceph-filesystem -o yaml
kubectl -n rook-ceph get cephobjectstore ceph-objectstore -o yaml
```

Vérifier qu’aucun PVC/PV, y compris un PV conservé ou statique, n’utilise CephFS,
et qu’aucun bucket ou client S3/direct ne dépend de ce store. L’absence d’OBC
ne prouve pas que RGW est vide : vérifier aussi les buckets via l’API S3 ou
`radosgw-admin` configuré pour ce store. Vérifier les sous-volumes et les clients
CephFS directs ; arrêter ici si des données doivent être conservées.
L’inventaire local ne contient pas les PVC/PV ni le contenu des buckets et ne
permet donc pas, à lui seul, de valider cette étape.

Après ces vérifications et publication des valeurs sur `main`, synchroniser
manuellement les deux Applications sans prune ni force. Supprimer ensuite
uniquement les ressources suivantes, dont les noms viennent de l’inventaire :

```bash
kubectl delete storageclass ceph-filesystem ceph-bucket
kubectl -n rook-ceph delete cephfilesystemsubvolumegroup.ceph.rook.io ceph-filesystem-csi
kubectl -n rook-ceph delete cephfilesystem.ceph.rook.io ceph-filesystem
kubectl -n rook-ceph delete cephobjectstore.ceph.rook.io ceph-objectstore
```

La suppression du filesystem peut supprimer ses pools et leurs données. Le store
exporté a `preservePoolsOnDelete: true` : ses pools objet peuvent rester après le
retrait de RGW. Leur purge définitive est une opération distincte, à effectuer
seulement après inspection de leur contenu et de leurs dépendances. Ne pas
retirer de finalizers pour forcer une suppression bloquée.

Vérifier ensuite la disparition des MDS/RGW et des composants CSI CephFS,
la santé Ceph et les lectures/écritures des applications utilisant `ceph-block`.
La toolbox n’est pas activée par ce dépôt ; les commandes `ceph` nécessitent
une toolbox existante ou un accès administrateur Ceph équivalent.

## Validation

Prérequis : Helm, Kustomize, kubeconform, Python 3 et PyYAML 6.0.3.

```bash
./scripts/validate-manifests.sh rook-ceph rook-ceph-operator ceph-csi-drivers
./scripts/validate-rook-migration.sh
```

Les schémas Ceph/CSI sont extraits des CRD du chart opérateur épinglé.
Les exports locaux et charts téléchargés ne doivent pas être commités.
