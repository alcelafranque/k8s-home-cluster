# Rook / CSI migration implementation plan

**Goal:** Prepare a reviewable Rook 1.20.7 / CSI 1.0.4 configuration, preserving RBD identities, and a separate Ceph 19.2.6 stage.
**Architecture:** Keep manual Argo CD Applications. Add a dedicated CSI drivers Application. Use CRD schemas from the pinned operator chart for validation.
**Tech Stack:** Kustomize, Helm, Argo CD, kubeconform, Python/PyYAML.
**Spec:** User-approved migration order in the conversation: inspect live state, align Rook/CSI, validate RBD, then upgrade Ceph.

- [x] Render and inspect target charts and exported CSI settings.
- [x] Align operator defaults; configure only RBD in the drivers chart; update cluster chart while preserving Ceph 19.2.3 for the first sync.
- [x] Validate against bundled CRDs; add regression checks for RBD identity, driver dependencies and disabled services.
- [x] Prepare Ceph 19.2.6 as a separate overlay and document the 1.19.11 prerequisite, manual sync order, live checks and CephX remediation.
- [x] Run validations and review the full diff.

Live evidence: user reports Rook 1.19.3, CSI operator 0.6.0, CephCluster Ready / HEALTH_WARN. No cluster access in this environment. Do not claim a live upgrade or blindly roll back CRDs already rendered from chart 1.20.7.
