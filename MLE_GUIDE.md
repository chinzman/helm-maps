# MLE Guide — Deploying Your Model API

This guide is for Machine Learning Engineers (MLEs) who want to package, test locally on Minikube, and deploy model serving APIs using the standardized Helm chart.

---

## 1. What the Chart Does For You

You do not need to write raw Kubernetes manifests (Deployment, Service, Ingress, HPA, ServiceAccount). When you deploy this chart, it automatically:
- Creates a **Deployment** with container security, health checks, and tuned CPU/memory limits
- Sets up a **Service** to route incoming traffic
- Configures an **Ingress** with host routing and TLS (in staging/prod)
- Enables a **HorizontalPodAutoscaler (HPA)** to scale pods under inference load (in staging/prod)
- Configures a **ServiceAccount** with IAM roles for cloud resource access (e.g. S3 model artifacts)

Your responsibility is only to specify **what image to run** and **what environment configuration your model needs**.

---

## 2. Configuration Files Overview

| File | Target Environment | Purpose |
|------|-------------------|---------|
| `values/values-local.yaml` | **Local Minikube** (`ml-local`) | Overrides image to local tag, sets `pullPolicy: Never`, disables secrets. Used alongside an environment file. |
| `values/values-dev.yaml` | **Cloud Dev** (`ml-dev`) | Rapid iteration in cloud, single replica, debug logging. |
| `values/values-staging.yaml` | **Cloud Staging** (`ml-staging`) | Pre-production testing, 2-5 autoscaling replicas, ingress enabled. |
| `values/values-prod.yaml` | **Cloud Production** (`ml-prod`) | Live customer traffic, 3-20 replicas, zone anti-affinity, rate limiting, strict security. |

---

## 3. Local Developer Workflow (Testing on Minikube)

Before pushing changes to GitHub or deploying to cloud environments, you can test your exact model API on a local Minikube cluster:

### Step 1: Build your model image in Minikube's Docker daemon
```bash
# Point your local terminal to Minikube's Docker
eval $(minikube docker-env)

# Build your container image (replace my-model with your model name)
docker build -t my-model:local ./app/
```

### Step 2: Deploy locally using the local override file
Combine `values-dev.yaml` with `values-local.yaml`. The local file overrides the registry lookup, so Kubernetes immediately uses your locally built image:
```bash
helm upgrade --install my-model-local ./helm/ml-api-chart \
  -f values/values-dev.yaml \
  -f values/values-local.yaml \
  --set image.repository=my-model \
  --set image.tag=local \
  --namespace ml-local \
  --create-namespace \
  --wait
```

### Step 3: Test and call the API locally
Forward the service port to your machine (using port 9090 to avoid local port conflicts):
```bash
kubectl port-forward svc/my-model-local-ml-api-chart 9090:80 -n ml-local &

# Test endpoints
curl http://localhost:9090/
curl http://localhost:9090/health
curl "http://localhost:9090/predict?input=sample_data"
```

### Step 4: Run chart test suite locally
```bash
# Template unit tests (tests chart YAML logic)
helm unittest ./helm/ml-api-chart

# Live connectivity test (runs test pod in cluster)
helm test my-model-local -n ml-local --logs
```

### Step 5: Clean up local release when finished
```bash
helm uninstall my-model-local -n ml-local
```

---

## 4. Cloud Deployment Commands

Once verified locally, commit your code and image tag. For cloud deployments, **do not pass `values-local.yaml`** — the environment values file alone is used:

### Deploying to Cloud Dev (`ml-dev`):
```bash
helm upgrade --install my-model-dev ./helm/ml-api-chart \
  -f values/values-dev.yaml \
  --set image.repository=ghcr.io/your-org/ml-api \
  --set image.tag=1.2.0 \
  --namespace ml-dev \
  --create-namespace \
  --wait
```

### Deploying to Cloud Staging (`ml-staging`):
```bash
helm upgrade --install my-model-staging ./helm/ml-api-chart \
  -f values/values-staging.yaml \
  --set image.repository=ghcr.io/your-org/ml-api \
  --set image.tag=1.2.0-rc1 \
  --namespace ml-staging \
  --create-namespace \
  --wait
```

### Deploying to Cloud Production (`ml-prod`):
```bash
helm upgrade --install my-model-prod ./helm/ml-api-chart \
  -f values/values-prod.yaml \
  --set image.repository=ghcr.io/your-org/ml-api \
  --set image.tag=1.2.0 \
  --namespace ml-prod \
  --create-namespace \
  --wait
```

---

## 5. How This Impacts the MLE Team & Workflow

### What Was the Old Way?
- **Manual Manifest Duplication:** MLEs had to manually copy YAML folders (`k8s/dev`, `k8s/prod`), edit replica counts, and manually run `kubectl apply`.
- **Configuration Drift:** Dev, staging, and prod configurations drifted apart over time, leading to "works in dev but crashes in prod" incidents.
- **High Kubernetes Burden:** MLEs had to master Kubernetes primitives, security contexts, probes, and HPA configurations instead of focusing on model logic.

### What Changes With This Helm Platform?
1. **Zero Boilerplate for New Models:** Deploying a new model only requires specifying an image tag and environment variables in a thin values file.
2. **Safe, Predictable Promotion:** The exact same template and infrastructure logic runs across local, dev, staging, and production. Environments only differ in scale and operational policies.
3. **Instant Local Verification:** MLEs can test complete Kubernetes deployments locally in Minikube (`ml-local`) using `values-local.yaml` without needing cloud access or messing with production secrets.
4. **Automated Rollback & Auditability:** Every deployment is versioned. If a model performs poorly or experiences latency degradation, rolling back takes one single command (`helm rollback`).
5. **Clear Ownership Separation:**
   - **MLE Team Owns:** Model code, container images, inference logic, and model-specific values (hyperparameters, env variables).
   - **Platform Team Owns:** Helm chart templates, autoscaling policies, networking/ingress, and CI/CD packaging.

---

## 6. Managing Secrets

**Never commit real secrets into any Git repository.**

- **Local Development:** When using `values-local.yaml`, secrets are disabled by default so you can run tests with zero setup. If your model specifically requires secrets during local testing:
  ```bash
  kubectl apply -f secrets/local-dev-secret.yaml -n ml-local
  ```
- **Cloud Environments (Staging/Prod):** Secrets are never managed by hand. The **External Secrets Operator (ESO)** automatically synchronizes encrypted keys from AWS Secrets Manager into the cluster. The pod mounts them as environment variables automatically.

---

## 7. Operations & Troubleshooting

### Inspect Running Pods and Logs
```bash
# Check pod status (use ml-local, ml-dev, ml-staging, or ml-prod)
kubectl get pods -n <namespace>

# View live inference logs
kubectl logs -l app.kubernetes.io/instance=<release-name> -n <namespace> --tail=100 -f
```

### Instant Rollback
```bash
# Check previous deployment revisions
helm history <release-name> -n <namespace>

# Roll back to the previous deployment revision
helm rollback <release-name> -n <namespace>
```

### Common Issues:
- **`Pending` Pods:** Check node resources with `kubectl describe pod -n <namespace>`. Typically means CPU or memory requests exceed local cluster capacity.
- **`ImagePullBackOff`:** Verify the image tag exists in the registry (or when testing locally, ensure `eval $(minikube docker-env)` was run before building).
- **`secret not found`:** In cloud environments, confirm the External Secrets Operator has synced the secret for your namespace. For local testing, ensure `values-local.yaml` is passed.
