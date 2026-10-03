# Driver Ceph CSI RBD

Le chart `ceph-csi-drivers` crée uniquement le Driver
`rook-ceph.rbd.csi.ceph.com`, son OperatorConfig et ses service accounts/RBAC.
Le nom du driver et le cluster CSI `rook-ceph` correspondent aux volumes existants.
Les connexions Ceph et profils clients sont laissés à Rook.

Les valeurs fixent explicitement les deux réplicas, le réseau hôte, les priorités
et les ressources CPU/mémoire, pour ne pas dépendre des valeurs par défaut du chart.
L’image set est fourni par le chart opérateur Rook : inutile de dupliquer les tags.

CephFS, NFS et NVMe-oF sont désactivés. Cela ne supprime pas automatiquement un
ancien Driver CephFS. Son éventuel retrait nécessite la vérification de non-utilisation.

Application manuelle et protégée contre le prune.
