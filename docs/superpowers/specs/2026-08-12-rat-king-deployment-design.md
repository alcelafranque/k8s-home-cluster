# Rat King Deployment Design

## Goal

Deploy Rat King through the repository's existing Argo CD workflow and expose it
at `https://rat-king.lac-coloc.fr`. The deployment must retain its generated
cache across pod replacements and run on either the cluster's AMD64 or ARM64
nodes.

## Architecture

Rat King will be a standalone Argo CD application named `rat-king`, deployed to
the namespace of the same name. The application will point at
`kubernetes/apps/rat-king` and use automated pruning, self-healing, and namespace
creation, matching the repository's other applications.

The application directory will contain native Kubernetes manifests assembled by
Kustomize. Native manifests are preferred over the generic application Helm
chart because Rat King already publishes a small, security-hardened Kubernetes
deployment whose intent can be retained directly and reviewed locally.

## Workload and Security

The Deployment will run one replica of the public, versioned image
`ghcr.io/lac-coloc/rat-king:0.2.3`. This tag is an OCI image index containing
both `linux/amd64` and `linux/arm64`, so the scheduler will not receive an
architecture constraint.

The workload will preserve the upstream runtime configuration:

- port `8080` and the upstream cache, queue, timeout, and refresh defaults;
- liveness at `/healthz` and readiness at `/readyz`;
- bounded CPU and memory requests and limits;
- UID, GID, and filesystem group `10001`;
- non-root execution, a read-only root filesystem, `RuntimeDefault` seccomp,
  no privilege escalation, no Linux capabilities, and no mounted service
  account token;
- a 45-second termination grace period for cooperative shutdown.

No application secret or image pull secret is required.

## Storage

A dedicated PersistentVolumeClaim named `rat-king-data` will provide `1Gi` of
`ReadWriteOnce` storage from the `ceph-block` storage class. It will be mounted
at `/data` and made writable through pod group `10001`.

The Deployment will stay at one replica because Rat King's queue and LRU state
are local to the process and the volume is single-writer. The PVC preserves the
last valid shared and per-restaurant snapshots across pod replacement, avoiding
unnecessary cold reloads from Burger King's public endpoints.

## Networking

A ClusterIP Service named `rat-king` will expose port `80` and target the named
container port `http` on `8080`.

Two Gateway API routes will follow the repository convention:

- the HTTPS listener on `one-gateway-for-all` will route
  `rat-king.lac-coloc.fr` to the Service;
- the HTTP listener will return a permanent `301` redirect to HTTPS.

The HTTPS route will carry Homepage discovery annotations, display Rat King in
the `Tools` group, and use the application's own favicon URL for its icon so no
new dashboard asset is required.

## Runtime Flow and Failure Handling

Argo CD creates the namespace and applies the PVC, Deployment, Service, and
routes. The pod serves HTTP immediately while it initializes its shared data in
the background. It remains absent from ready Service endpoints until `/readyz`
succeeds, while `/healthz` distinguishes a live process from initialization or
upstream-data failures.

Transient failures contacting Burger King's public data sources are handled by
Rat King's built-in bounded retry and backoff behavior. Existing valid snapshots
remain on the PVC and continue to be served. Kubernetes restarts only an
unhealthy process; readiness failures alone stop new traffic without discarding
persistent data.

## Validation

Before completion:

- render `kubernetes/apps/rat-king` with Kustomize;
- validate the rendered resources with the repository's Kubeconform script;
- render the Argo CD application set and confirm the new Application is present;
- inspect the rendered workload for the pinned `0.2.3` tag, one replica, probes,
  security settings, PVC mount, and absence of an architecture selector;
- inspect the rendered routes for the requested hostname and HTTPS redirect.

Live application of the manifests is outside the repository change: Argo CD
will deploy them after the resulting commit reaches the branch it tracks.
