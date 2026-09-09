# ml-api-chart

A generic Helm chart for deploying ML model serving APIs on Kubernetes.
Supports dev, staging, and production through environment-specific values files.

---

## Background

The team was copying Kubernetes manifests manually per environment. This caused config drift, slow deployments, and nobody being confident what exactly was running in prod.

The fix was straightforward — one Helm chart with shared templates, and three thin values files that each environment overrides. MLEs don't need to touch the chart itself. They just update the values file for their environment and run one command.

---

## Project Structure

```
ml-api-chart/
├── app/                         # Sample FastAPI ML API (Hello World + /predict)
├── helm/ml-api-chart/           # The Helm chart
│   ├── Chart.yaml
│   ├── values.yaml              # Shared defaults
│   └── templates/               # Kubernetes resource templates
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── ingress.yaml
│       ├── hpa.yaml
│       ├── configmap.yaml
│       ├── serviceaccount.yaml
│       └── tests/
│           └── test-connectivity.yaml
├── helm/ml-api-chart/tests/
│   └── unit_test.yaml           # helm-unittest tests
├── values/
│   ├── values-dev.yaml
│   ├── values-staging.yaml
│   └── values-prod.yaml
├── secrets/                     # Secret management (see secrets/README.md)
├── cicd/                        # Jenkins and GitHub Actions pipelines
├── iac/                         # Terraform root module for EKS deployment
│   ├── providers.tf
│   ├── variables.tf
│   ├── main.tf
│   └── outputs.tf
└── README.md
```

---

## Quick Start — Clone and Run Locally

Target test environment: macOS (Darwin) with Docker Desktop and Minikube.

**Step 1 — Install tools** (skip if already installed):
```bash
brew install kubectl helm minikube
helm plugin install https://github.com/helm-unittest/helm-unittest --verify=false
```
> `--verify=false` is required because the helm-unittest plugin does not publish a GPG signature. This is a known characteristic of the plugin — not a security bypass. Every team using helm-unittest passes this flag.

**Step 2 — Start Docker Desktop** from your Applications folder and wait until it shows "running".

**Step 3 — Start Minikube:**
```bash
minikube start --driver=docker --cpus=2 --memory=3500mb
```

**Step 4 — Build the sample ML API image inside Minikube:**
```bash
eval $(minikube docker-env)
docker build -t ml-api:local ./app/
```

**Step 5 — Deploy (local test of dev configuration):**
```bash
helm upgrade --install ml-api-local ./helm/ml-api-chart \
  -f values/values-dev.yaml \
  -f values/values-local.yaml \
  --namespace ml-local \
  --create-namespace \
  --wait
```
> `values-local.yaml` overrides image source, pull policy, and disables secrets for local use in `ml-local`.
> In cloud deployments, only `values-dev.yaml` is passed to target `ml-dev` — secrets are enabled and managed by ESO.

**Step 6 — Call the API from your machine:**
```bash
kubectl port-forward svc/ml-api-local-ml-api-chart 9090:80 -n ml-local &

curl http://localhost:9090/
curl http://localhost:9090/health
curl "http://localhost:9090/predict?input=test"
```

> Port 9090 is used because 8080 is typically occupied by Jenkins on a local dev machine.

**Step 7 — Run tests:**
```bash
# Unit tests (no cluster needed — tests chart template logic)
helm unittest ./helm/ml-api-chart

# Connectivity test (runs a pod in the cluster, calls all API endpoints)
helm test ml-api-local -n ml-local --logs
```

All 13 unit tests and all 5 connectivity tests should pass.

**Step 8 — Test staging configuration locally the same way:**
```bash
helm upgrade --install ml-api-local ./helm/ml-api-chart \
  -f values/values-staging.yaml \
  -f values/values-local.yaml \
  --namespace ml-local \
  --wait
```

**Cleanup:**
```bash
helm uninstall ml-api-local -n ml-local
minikube stop
```


## Environment Differences

The same chart, deployed differently per environment:

| | Dev | Staging | Production |
|--|--|--|--|
| Image tag | `local` / `latest` | release candidate | pinned semver |
| Replicas | 1 | 2 | 3 (baseline) |
| Service | NodePort | ClusterIP | ClusterIP |
| Ingress | off | on (HTTPS + TLS) | on (HTTPS + TLS) |
| Autoscaling | off | 2–5 replicas | 3–20 replicas |
| CPU limit | 200m | 500m | 1000m |
| Memory limit | 128Mi | 512Mi | 1Gi |
| Pod anti-affinity | none | preferred | required (zone-level) |

---

## How MLEs Use This

See [MLE_GUIDE.md](./MLE_GUIDE.md) — that doc covers day-to-day usage for MLE team members who want to deploy their model API without getting into chart internals.

---

## Secrets

See [secrets/README.md](./secrets/README.md) for the full architecture.

**How secrets are handled between local testing and cloud:**

- **Cloud environments (`values-dev.yaml`, `values-staging.yaml`, `values-prod.yaml`):**
  `secretRef.enabled` is set to `true`. Secrets are managed outside of Git using the **External Secrets Operator (ESO)** connected to AWS Secrets Manager. ESO automatically pulls credentials and synchronizes them into Kubernetes Secrets before pods start.

- **Local testing (`values-local.yaml`):**
  `secretRef.enabled` is overridden to `false`. When you pass `-f values/values-local.yaml` on Minikube, the chart starts immediately without expecting external cloud secrets.

If you specifically want to test secret injection locally, sample dummy secrets are provided:
```bash
kubectl apply -f secrets/local-dev-secret.yaml -n ml-local
```

Secret values never go in values files or in git.

---

## CI/CD

Two pipeline options are provided:

**GitHub Actions** (active — runs automatically on push):
```
.github/workflows/helm-publish.yml
```

**Jenkins** (reference implementation):
```
cicd/Jenkinsfile
```

Both follow the same four stages: lint → unit test → integration test on kind → publish to GHCR.

Publishing only happens on merges to `main`. PRs only run lint and tests.

To install a published chart:
```bash
# Replace <org-or-username> with your target GitHub org or username (e.g. chinzman)
helm install ml-api oci://ghcr.io/<org-or-username>/helm-charts/ml-api-chart \
  --version 0.1.0 \
  -f values/values-prod.yaml \
  --namespace ml-prod --create-namespace
```

---

## Infrastructure as Code

The `iac/` directory provides a Terraform configuration showing how to deploy this chart to EKS using the `helm_release` resource.

Key points:
- `atomic = true` means Terraform rolls back automatically if the deployment fails
- `prevent_destroy` can be enabled in production workspaces to block accidental teardown
- Image tag and chart version are separate variables so they can be upgraded independently

---

## Autoscaling

HPA is configured in staging and prod. A few things worth noting:

When HPA is enabled, the chart intentionally leaves `spec.replicas` out of the Deployment spec. If you don't do this, every `helm upgrade` resets the replica count back to the value in the chart, ignoring whatever the HPA had scaled to. It's a common issue and easy to miss.

Prod scales from CPU 65% (not the usual 80%) to give more headroom before pods get saturated — ML inference can spike quickly.

---

## Version Control

- `Chart.yaml: version` — bumped when templates change
- `Chart.yaml: appVersion` — bumped when the default app image changes
- Image tag in values file — changed by the MLE when deploying a new model version

These three are independent. An MLE can change the image tag without touching the chart version.

Branching: `main` is protected. All changes go through PRs. Chart publishing only happens from `main`.

---

## Deployment History and Rollback

```bash
# See previous deployments (local)
helm history ml-api-local -n ml-local

# Roll back to previous version
helm rollback ml-api-local -n ml-local

# Roll back to a specific revision
helm rollback ml-api-local 2 -n ml-local

# (In cloud environments, replace ml-api-local and ml-local with the target release and namespace, e.g. ml-api-prod -n ml-prod)
```

---

## Key Design Decisions & Engineering Insights

1. **Preventing HPA / Helm Replica Drift:**
   When Horizontal Pod Autoscaling is enabled, Helm charts often include `spec.replicas`. In production, if HPA scales your service to 10 pods during high traffic, running `helm upgrade` would abruptly force the replica count back down to 3, causing service degradation. The Deployment template in this chart conditionally omits `spec.replicas` when HPA is active, letting the Kubernetes HPA controller maintain authority over scaling.

2. **The `values-local.yaml` Developer Experience:**
   Rather than asking developers to hack values files or disable security settings manually, the chart uses an overlay pattern. The base environment files (`values-dev.yaml`, `values-staging.yaml`, `values-prod.yaml`) represent authentic cloud states with secrets enabled. Passing `-f values/values-local.yaml` cleanly overrides only local prerequisites (local image tag, `pullPolicy: Never`, secrets disabled) without mutating git-tracked cloud configurations.

3. **Context-Aware `NOTES.txt` Runbook:**
   Instead of static ASCII art or generic instructions, `NOTES.txt` inspects the active Helm values. If Ingress is disabled, it prints the exact `kubectl port-forward` command with the active release name and namespace, followed by ready-to-run curl commands. If Ingress is enabled, it prints the target URL and TLS details.

4. **Decoupled Versioning Lifecycle:**
   - Platform engineers bump `Chart.yaml:version` (semver) when changing chart templates, probes, or Kubernetes resources.
   - Machine Learning Engineers deploy new model versions simply by overriding `image.tag` in their values file or CI/CD without needing a new Helm chart version.

