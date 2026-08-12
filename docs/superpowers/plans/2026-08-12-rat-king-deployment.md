# Rat King Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Rat King through Argo CD at `https://rat-king.lac-coloc.fr` with durable Ceph-backed state and hardened runtime settings.

**Architecture:** A standalone Kustomize application will define one Rat King Deployment, one PVC, one ClusterIP Service, and two Gateway API routes. A dedicated Argo CD Application will reconcile that directory into the `rat-king` namespace.

**Tech Stack:** Kubernetes, Kustomize, Argo CD, Gateway API, Envoy Gateway, Ceph RBD, Homepage, Kubeconform

## Global Constraints

- Use the public image `ghcr.io/lac-coloc/rat-king:0.2.3`.
- Do not add an architecture selector; tag `0.2.3` supports `linux/amd64` and `linux/arm64`.
- Run exactly one replica as UID/GID `10001` with filesystem group `10001`.
- Mount a `1Gi`, `ReadWriteOnce`, `ceph-block` PVC at `/data`.
- Expose only `rat-king.lac-coloc.fr`, with HTTPS routing and an HTTP `301` redirect.
- Keep the upstream probes, resource bounds, environment defaults, and 45-second termination grace period.
- Do not add application secrets, image pull secrets, or live `kubectl apply` steps.

---

### Task 1: Workload and Persistent Storage

**Files:**
- Create: `kubernetes/apps/rat-king/kustomization.yaml`
- Create: `kubernetes/apps/rat-king/deployment.yaml`
- Create: `kubernetes/apps/rat-king/pvc.yaml`

**Interfaces:**
- Consumes: the public `ghcr.io/lac-coloc/rat-king:0.2.3` image and the cluster's `ceph-block` StorageClass.
- Produces: a pod selected by `app.kubernetes.io/name: rat-king`, a named `http` container port, and the `rat-king-data` claim used by the workload.

- [ ] **Step 1: Verify the application manifests do not already exist**

Run:

```bash
test ! -e kubernetes/apps/rat-king
```

Expected: exit status `0`, proving this task will not overwrite an existing application.

- [ ] **Step 2: Create the Kustomization**

Create `kubernetes/apps/rat-king/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: rat-king

resources:
  - deployment.yaml
  - pvc.yaml
```

- [ ] **Step 3: Create the persistent claim**

Create `kubernetes/apps/rat-king/pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rat-king-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-block
  resources:
    requests:
      storage: 1Gi
```

- [ ] **Step 4: Create the hardened Deployment**

Create `kubernetes/apps/rat-king/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rat-king
  labels:
    app.kubernetes.io/name: rat-king
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: rat-king
  template:
    metadata:
      labels:
        app.kubernetes.io/name: rat-king
    spec:
      automountServiceAccountToken: false
      terminationGracePeriodSeconds: 45
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
        fsGroupChangePolicy: OnRootMismatch
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: rat-king
          image: ghcr.io/lac-coloc/rat-king:0.2.3
          imagePullPolicy: IfNotPresent
          args:
            - serve
            - --host
            - 0.0.0.0
            - --port
            - "8080"
            - --refresh-interval
            - "21600"
          env:
            - name: BK_REFRESH_INTERVAL_SECONDS
              value: "21600"
            - name: BK_OUTPUT_DIR
              value: /data/site
            - name: BK_STATE_DIR
              value: /data
            - name: BK_HTTP_TIMEOUT_SECONDS
              value: "30"
            - name: BK_CACHE_MAX_RESTAURANTS
              value: "20"
            - name: BK_REFRESH_QUEUE_MAX
              value: "10"
            - name: BK_COLD_LOADS_PER_HOUR
              value: "6"
            - name: BK_SEARCH_MAX_RESULTS
              value: "20"
            - name: PORT
              value: "8080"
          ports:
            - name: http
              containerPort: 8080
              protocol: TCP
          readinessProbe:
            httpGet:
              path: /readyz
              port: http
            initialDelaySeconds: 2
            periodSeconds: 10
            timeoutSeconds: 2
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /healthz
              port: http
            initialDelaySeconds: 5
            periodSeconds: 30
            timeoutSeconds: 2
            failureThreshold: 3
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 250m
              memory: 256Mi
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
          volumeMounts:
            - name: data
              mountPath: /data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: rat-king-data
```

- [ ] **Step 5: Render and verify the workload contract**

Run:

```bash
kubectl kustomize kubernetes/apps/rat-king > /tmp/rat-king-rendered.yaml
yq -e 'select(.kind == "Deployment") | .metadata.namespace == "rat-king" and .spec.replicas == 1 and .spec.template.spec.containers[0].image == "ghcr.io/lac-coloc/rat-king:0.2.3" and .spec.template.spec.containers[0].readinessProbe.httpGet.path == "/readyz" and .spec.template.spec.containers[0].livenessProbe.httpGet.path == "/healthz" and .spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem == true and .spec.template.spec.nodeSelector == null' /tmp/rat-king-rendered.yaml
yq -e 'select(.kind == "PersistentVolumeClaim") | .spec.storageClassName == "ceph-block" and .spec.accessModes == ["ReadWriteOnce"] and .spec.resources.requests.storage == "1Gi"' /tmp/rat-king-rendered.yaml
```

Expected: both `yq` commands print `true` and exit `0`.

- [ ] **Step 6: Commit workload and storage**

```bash
git add kubernetes/apps/rat-king/kustomization.yaml kubernetes/apps/rat-king/deployment.yaml kubernetes/apps/rat-king/pvc.yaml
git commit -m "feat(rat-king): add workload and persistent storage"
```

### Task 2: Service and Gateway Routes

**Files:**
- Create: `kubernetes/apps/rat-king/service.yaml`
- Create: `kubernetes/apps/rat-king/ingress.yaml`
- Modify: `kubernetes/apps/rat-king/kustomization.yaml`

**Interfaces:**
- Consumes: the `app.kubernetes.io/name: rat-king` pod label and named `http` port from Task 1.
- Produces: the `rat-king` Service on port `80` and HTTPS/redirect routes for `rat-king.lac-coloc.fr`.

- [ ] **Step 1: Write failing route assertions**

Run:

```bash
kubectl kustomize kubernetes/apps/rat-king > /tmp/rat-king-rendered.yaml
yq -e 'select(.kind == "Service" and .metadata.name == "rat-king")' /tmp/rat-king-rendered.yaml
yq -e 'select(.kind == "HTTPRoute" and .metadata.name == "rat-king")' /tmp/rat-king-rendered.yaml
```

Expected: both `yq` commands exit `1` because networking resources are not yet present.

- [ ] **Step 2: Create the Service**

Create `kubernetes/apps/rat-king/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: rat-king
  labels:
    app.kubernetes.io/name: rat-king
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: rat-king
  ports:
    - name: http
      port: 80
      targetPort: http
      protocol: TCP
```

- [ ] **Step 3: Create the HTTPS and redirect routes**

Create `kubernetes/apps/rat-king/ingress.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: rat-king
  annotations:
    gethomepage.dev/enabled: "true"
    gethomepage.dev/icon: mdi-crown
    gethomepage.dev/name: Rat King
    gethomepage.dev/description: Burger King Kingdom reward comparator
    gethomepage.dev/group: Tools
spec:
  parentRefs:
    - name: one-gateway-for-all
      namespace: envoy-gateway-system
      sectionName: https
  hostnames:
    - rat-king.lac-coloc.fr
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: rat-king
          port: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: rat-king-http-redirect
spec:
  parentRefs:
    - name: one-gateway-for-all
      namespace: envoy-gateway-system
      sectionName: http
  hostnames:
    - rat-king.lac-coloc.fr
  rules:
    - filters:
        - type: RequestRedirect
          requestRedirect:
            scheme: https
            statusCode: 301
```

- [ ] **Step 4: Register networking resources in Kustomize**

Update `kubernetes/apps/rat-king/kustomization.yaml` to:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: rat-king

resources:
  - deployment.yaml
  - ingress.yaml
  - pvc.yaml
  - service.yaml
```

- [ ] **Step 5: Render and verify the networking contract**

Run:

```bash
kubectl kustomize kubernetes/apps/rat-king > /tmp/rat-king-rendered.yaml
yq -e 'select(.kind == "Service" and .metadata.name == "rat-king") | .spec.ports[0].port == 80 and .spec.ports[0].targetPort == "http"' /tmp/rat-king-rendered.yaml
yq -e 'select(.kind == "HTTPRoute" and .metadata.name == "rat-king") | .metadata.annotations."gethomepage.dev/icon" == "mdi-crown" and .spec.hostnames == ["rat-king.lac-coloc.fr"] and .spec.parentRefs[0].sectionName == "https" and .spec.rules[0].backendRefs[0].port == 80' /tmp/rat-king-rendered.yaml
yq -e 'select(.kind == "HTTPRoute" and .metadata.name == "rat-king-http-redirect") | .spec.parentRefs[0].sectionName == "http" and .spec.rules[0].filters[0].requestRedirect.scheme == "https" and .spec.rules[0].filters[0].requestRedirect.statusCode == 301' /tmp/rat-king-rendered.yaml
```

Expected: all three `yq` commands print `true` and exit `0`.

- [ ] **Step 6: Commit networking**

```bash
git add kubernetes/apps/rat-king/kustomization.yaml kubernetes/apps/rat-king/service.yaml kubernetes/apps/rat-king/ingress.yaml
git commit -m "feat(rat-king): expose service through Gateway API"
```

### Task 3: Argo CD Registration

**Files:**
- Create: `kubernetes/apps/argocd/apps/rat-king.yaml`
- Modify: `kubernetes/apps/argocd/apps/kustomization.yaml`

**Interfaces:**
- Consumes: the renderable `kubernetes/apps/rat-king` directory from Tasks 1 and 2.
- Produces: an Argo CD Application that reconciles Rat King into its own namespace.

- [ ] **Step 1: Verify the Application is absent**

Run:

```bash
kubectl kustomize kubernetes/apps/argocd/apps > /tmp/argocd-apps-rendered.yaml
yq -e 'select(.kind == "Application" and .metadata.name == "rat-king")' /tmp/argocd-apps-rendered.yaml
```

Expected: `yq` exits `1` because Rat King is not registered yet.

- [ ] **Step 2: Create the Argo CD Application**

Create `kubernetes/apps/argocd/apps/rat-king.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rat-king
spec:
  destination:
    namespace: rat-king
    server: https://kubernetes.default.svc
  project: default
  source:
    path: kubernetes/apps/rat-king
    repoURL: https://github.com/alcelafranque/k8s-home-cluster.git
    targetRevision: HEAD
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

- [ ] **Step 3: Register the Application resource**

Add `rat-king.yaml` in alphabetical order between `plik.yaml` and
`syncthing-relay.yaml` in `kubernetes/apps/argocd/apps/kustomization.yaml`.

- [ ] **Step 4: Render and verify the Argo CD contract**

Run:

```bash
kubectl kustomize kubernetes/apps/argocd/apps > /tmp/argocd-apps-rendered.yaml
yq -e 'select(.kind == "Application" and .metadata.name == "rat-king") | .spec.destination.namespace == "rat-king" and .spec.source.path == "kubernetes/apps/rat-king" and .spec.syncPolicy.automated.prune == true and .spec.syncPolicy.automated.selfHeal == true and .spec.syncPolicy.syncOptions == ["CreateNamespace=true"]' /tmp/argocd-apps-rendered.yaml
```

Expected: `yq` prints `true` and exits `0`.

- [ ] **Step 5: Commit Argo CD registration**

```bash
git add kubernetes/apps/argocd/apps/kustomization.yaml kubernetes/apps/argocd/apps/rat-king.yaml
git commit -m "feat(argocd): deploy Rat King application"
```

### Task 4: Full Manifest Validation

**Files:**
- Verify: `kubernetes/apps/rat-king/*.yaml`
- Verify: `kubernetes/apps/argocd/apps/kustomization.yaml`
- Verify: `kubernetes/apps/argocd/apps/rat-king.yaml`

**Interfaces:**
- Consumes: all resources produced in Tasks 1 through 3.
- Produces: validation evidence that the new application renders and conforms to Kubernetes schemas.

- [ ] **Step 1: Run whitespace and YAML render checks**

Run:

```bash
git diff --check HEAD~3..HEAD
kubectl kustomize kubernetes/apps/rat-king > /tmp/rat-king-rendered.yaml
kubectl kustomize kubernetes/apps/argocd/apps > /tmp/argocd-apps-rendered.yaml
```

Expected: all commands exit `0`.

- [ ] **Step 2: Run schema validation through the repository script**

Run:

```bash
nix shell nixpkgs#kustomize nixpkgs#kubeconform -c ./scripts/validate-manifests.sh rat-king
```

Expected: `5 resources found - Valid: 5` followed by `OK: all apps validated`.

- [ ] **Step 3: Recheck deployment invariants from the final render**

Run:

```bash
yq -e 'select(.kind == "Deployment" and .metadata.name == "rat-king") | .spec.replicas == 1 and .spec.template.spec.automountServiceAccountToken == false and .spec.template.spec.securityContext.runAsUser == 10001 and .spec.template.spec.securityContext.runAsGroup == 10001 and .spec.template.spec.securityContext.fsGroup == 10001 and .spec.template.spec.securityContext.seccompProfile.type == "RuntimeDefault" and .spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation == false and .spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem == true and .spec.template.spec.containers[0].securityContext.capabilities.drop == ["ALL"] and .spec.template.spec.containers[0].volumeMounts[0].mountPath == "/data" and .spec.template.spec.volumes[0].persistentVolumeClaim.claimName == "rat-king-data" and .spec.template.spec.nodeSelector == null and .spec.template.spec.imagePullSecrets == null' /tmp/rat-king-rendered.yaml
```

Expected: `yq` prints `true` and exits `0`.

- [ ] **Step 4: Confirm only intended files changed**

Run:

```bash
git status --short
git log -5 --oneline
```

Expected: only pre-existing unrelated untracked files remain; the recent commits contain the Rat King spec, plan, workload, networking, and Argo CD registration.
