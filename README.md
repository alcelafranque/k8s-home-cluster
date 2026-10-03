# 🏠 K8s Home Cluster

Welcome to my Kubernetes home lab! This repository contains the configuration and manifests for my personal Kubernetes cluster running at home. 

## 🎯 Project Goal

The ultimate goal of this project is to migrate 100% of my home infrastructure to Kubernetes. This is an ongoing journey where I'm learning, experimenting, and building a fully self-hosted environment.

## 🚀 What's Inside

This repository contains:
- Kubernetes manifests and configurations
- Infrastructure as Code setup

## 🛠️ Technologies Used

- **Kubernetes** - The orchestration platform
- **Talos** - For managing Kubernetes cluster / nodes

## 🖥️ Hardware Setup

My cluster runs on a mix of ARM and x86 hardware, optimized for low power consumption and cost efficiency:

### Master/Worker Nodes
- **3x Orange Pi 5 Plus (16GB RAM)**
  - ARM-based SBCs fully supported by Talos Linux
  - Very low power consumption (~6-12W per board)
  - 8-core Rockchip RK3588 CPU
  - Support for NVMe 2280
  - Ethernet 2.5GBASE-T

### Additional Worker Node
- **1x Mini PC (Ryzen 4700U)**
  - Running as VMs on a no-name mini PC
  - x86 architecture for workloads that require it

## 🔄 Bootstrap / Disaster Recovery

Everything is GitOps-managed by ArgoCD from `main`. To rebuild from scratch:

### Prerequisites (outside the cluster)

- The **SOPS PGP private key** that decrypts `talos/dorado/talsecret.sops.yaml`.
- **OpenBao** reachable at `https://openbao.lac-coloc.fr` (it is not hosted in this cluster), with the KV v2 data under `kv/k8s/dorado/applications/*`.
- The **AppRole `secret-id`** for the role referenced in `kubernetes/apps/external-secrets/openbao-store.yaml`.
- The **external HAProxy** behind the Kubernetes API endpoint `10.243.2.55:6443`, load-balancing to the three control planes (it is not managed in this repo).

### Steps

1. **Talos**: `cd talos && task config CLUSTER=dorado`, then apply the generated configs (`talosctl apply-config`) and run `talosctl bootstrap` once on a single control plane.
2. **CNI**: the cluster boots without CNI or kube-proxy (`cni: none`, `proxy.disabled: true`). The Cilium chart itself is **not** managed in this repo (only its BGP / LB pool config is), so install Cilium manually with Helm (`kubeProxyReplacement=true`, BGP control plane enabled) before going further.
3. **ArgoCD**: `kubectl apply --server-side -k kubernetes/apps/argocd`. Server-side apply is required because the ArgoCD CRDs are too large for client-side apply. This installs ArgoCD and every `Application`, including ArgoCD itself (self-managed afterwards).
4. **Secrets**: create the only secret that is not in git, the OpenBao AppRole secret used by External Secrets:

   ```bash
   kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
   kubectl -n external-secrets create secret generic openbao-approle \
     --from-literal=secret-id='<approle secret-id>'
   ```

   The `openbao` `ClusterSecretStore` then becomes ready and every `ExternalSecret` resolves.
5. **Storage and data**: `rook-ceph-operator`, `rook-ceph-cluster` and `ceph-csi-drivers` are synced **manually** (see `kubernetes/migrations/README.md`). PVC data is restored from Kopiur snapshots and PostgreSQL from the CNPG barman backups on Backblaze B2.

## 📚 Learning Journey

This is a living project where I'm constantly:
- Adding new services
- Improving configurations
- Learning best practices
- Breaking things and fixing them 😅

## 🙏 Acknowledgments

Special thanks to these awesome projects that inspired and helped me along the way:

- [cbirkenbeul/homelab](https://github.com/cbirkenbeul/homelab)
- [hugginsio/homelab](https://github.com/hugginsio/homelab)
- [lordran/kustomize](https://framagit.org/lordran/kustomize)

---

⚠️ **Note**: This is a personal lab environment. Configurations may not be suitable for production use without proper review and adaptation.

Happy clustering! 🎉
