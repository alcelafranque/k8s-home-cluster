# Opérateurs Rook et Ceph CSI

Le chart `rook-ceph` est épinglé et déploie ses images par défaut : Rook,
ceph-csi-operator, Ceph-CSI et les sidecars associés. `values.yaml` ne surcharge
aucune image, les versions suivent donc le chart.

Depuis Rook 1.20, les paramètres et le RBAC des drivers sont déclarés dans
[`../ceph-csi-drivers`](../ceph-csi-drivers). Les CephConnection et ClientProfile
restent sous le contrôle de Rook.

L’Application Argo CD reste manuelle, avec Server-Side Apply pour les CRD,
`FailOnSharedResource=true`, `Prune=false,Delete=false` et sans finalizer de
suppression en cascade. Les annotations de protection ne modifient pas les
Pod templates.

Ordre de synchronisation : opérateur Rook, drivers CSI, puis cluster.
