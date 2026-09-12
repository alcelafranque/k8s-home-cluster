# Réparation des permissions du nodeplugin RBD existant

État observé le 8 septembre 2026 : Rook 1.19.3, ceph-csi-operator 0.6.0,
Driver RBD sans serviceAccountName explicite, DaemonSet utilisant
`rbd-nodeplugin-sa`, Application `ceph-csi-drivers` absente. Les nouvelles
créations de pods échouaient faute de compte, puis faute de droit `get nodes`.
La suppression par prune est une hypothèse ; la confirmer dans l’historique Argo.

`rbac.yaml` restaure le compte et les règles du nodeplugin RBD provenant des
[templates officiels CSI operator v0.6.0](https://github.com/ceph/ceph-csi-operator/tree/v0.6.0/deploy/charts/ceph-csi-operator/templates).
Les rôles/bindings ont des noms distincts `rook-recovery-rbd-nodeplugin-*`
pour éviter de remplacer ceux des charts. Ce fichier ne modifie aucun Driver,
DaemonSet, Deployment, image, CRD, pool ou volume. Les droits incluent les accès
aux secrets et volumes prévus par le driver officiel ; ce n’est pas un rôle
cluster-admin.

Depuis le checkout contenant ce fichier, après vérification du contexte :

```bash
kubectl apply -f kubernetes/migrations/rbd-rbac-recovery/rbac.yaml
kubectl auth can-i get node/w1 --as=system:serviceaccount:rook-ceph:rbd-nodeplugin-sa
kubectl -n rook-ceph get pods -l app=rook-ceph.rbd.csi.ceph.com-nodeplugin -o wide
kubectl get csinode w1 -o jsonpath='{.spec.drivers[*].name}{"\n"}'
```

Attendre les pods en 2/2, le driver enregistré sur chaque nœud affecté et le
montage des volumes applicatifs. Si le CSI plante encore, relever les logs de
ce pod. Cette réparation ne vérifie pas les permissions des contrôleurs CSI,
les admissions, ni l’état du stockage. Ne pas redémarrer tous les pods.

La migration 1.20 reste à terminer séparément selon le README parent. Tant que
les workloads utilisent `rbd-nodeplugin-sa`, conserver ces permissions. Après
migration complète, vérifier que plus aucun pod, DaemonSet ou Deployment ne
référence ce compte avant de retirer le compte et les quatre objets de secours.
Le rôle/binding `rook-ceph-rbd-node-recovery` éventuellement créé manuellement
au diagnostic est alors également à supprimer. Ne pas supprimer un compte
encore utilisé pour simplement faire disparaître un diff Argo CD.

Validation locale : cinq objets valides avec kubeconform -strict ; références
RoleBinding/ClusterRoleBinding contrôlées. Aucune application au cluster ici.
