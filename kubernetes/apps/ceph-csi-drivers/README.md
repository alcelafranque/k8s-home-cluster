# Driver Ceph CSI RBD

Le chart `ceph-csi-drivers` **1.0.4** crée uniquement le Driver
`rook-ceph.rbd.csi.ceph.com`, son OperatorConfig et ses service accounts/RBAC.
Le nom du driver et le cluster CSI `rook-ceph` correspondent aux volumes existants.
Les connexions Ceph et profils clients sont laissés à Rook.

Les valeurs reprennent les deux réplicas, le réseau hôte, les priorités et les
ressources CPU/mémoire de l’inventaire. Cette partie est conservée explicitement
pour éviter que la migration n’adopte les autres limites du nouveau chart.
L’image set est fourni par le chart opérateur Rook : inutile de dupliquer les tags.

CephFS, NFS et NVMe-oF sont désactivés. Cela ne supprime pas automatiquement un
ancien Driver CephFS. Son éventuel retrait nécessite la vérification de non-utilisation.

Application manuelle et protégée contre le prune. Voir
[la procédure de migration](../../migrations/README.md) avant synchronisation.
