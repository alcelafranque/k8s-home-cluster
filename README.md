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
