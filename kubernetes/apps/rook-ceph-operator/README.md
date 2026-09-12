# Opérateurs Rook et Ceph CSI

Le chart `rook-ceph` est fixé à **v1.20.7** et déploie ses images par défaut :
Rook **v1.20.7**, ceph-csi-operator **v1.0.4**, Ceph-CSI **v3.17.1** et les
sidecars associés. `values.yaml` ne surcharge plus les anciennes images.
Ces versions restent reproductibles grâce au chart épinglé.

Depuis Rook 1.20, les paramètres et le RBAC des drivers sont déclarés dans
[`../ceph-csi-drivers`](../ceph-csi-drivers). L’ancien bloc `csi.*` des valeurs
1.19 ne configure plus ces drivers. Les CephConnection et ClientProfile restent
sous le contrôle de Rook.

L’Application Argo CD reste manuelle, avec Server-Side Apply pour les CRD,
`FailOnSharedResource=true`, `Prune=false,Delete=false` et sans finalizer de
suppression en cascade. Les annotations de protection ne modifient pas les
Pod templates.

**Avant le premier sync**, suivre [la procédure de migration](../../migrations/README.md) :
l’opérateur observé est encore en 1.19.3 et nécessite un palier 1.19.11.
Le chart 1.20 ayant déjà été sélectionné, ne pas remettre des CRD 1.19 en place.
Synchroniser ensuite Rook, les drivers CSI, puis le cluster ; valider les volumes
RBD avant la mise à jour Ceph 19.2.6.
