# Secrets Management Architecture

## Core Security Principle

> **Secret values never live in this repository — not even in `.gitignore`d files.**
> Once committed to git history, secrets are compromised. We enforce automated external syncing.

---

## Files in This Folder

| File | Used Where | Contains Real Values? |
|------|-----------|----------------------|
| `local-dev-secret.yaml` | Local Minikube only | ❌ Dummy values only |
| `local-staging-secret.yaml` | Local Minikube only | ❌ Dummy values only |
| `external-secret-prod.yaml` | Cloud (prod cluster) | ❌ No values — just pointers to AWS |

---

## How Secrets Work Per Environment

### Local (Dev / Staging / Prod testing on Minikube)

Use the dummy secret files. They contain fake values — safe for local testing.

```bash
# For dev
kubectl apply -f secrets/local-dev-secret.yaml -n ml-local

# For staging
kubectl apply -f secrets/local-staging-secret.yaml -n ml-local
```

Then in the relevant values file, set `secretRef.enabled: true`.

The pod will pick up the secrets as environment variables automatically.

---

### Cloud — Staging and Production (Real Approach)

We use **External Secrets Operator (ESO)** + **AWS Secrets Manager**.

```
AWS Secrets Manager          ESO                    Kubernetes            Pod
(real secret values)  →  (sync agent)  →  (standard K8s Secret)  →  (env vars)
      ↑
  Security team manages this
  Values never leave AWS
  Auto-rotates every 24h
```

**Step 1:** Store the real secret in AWS:
```bash
aws secretsmanager create-secret \
  --name prod/ml-api/secrets \
  --secret-string '{"db_password":"real-pass","api_key":"real-key"}'
```

**Step 2:** Apply the ExternalSecret to the cluster:
```bash
kubectl apply -f secrets/external-secret-prod.yaml -n ml-prod
```

**Step 3:** ESO syncs it into a K8s Secret called `ml-api-prod-secrets` automatically.

**Step 4:** The Helm chart reads it via `secretRef.name: ml-api-prod-secrets`. Done.

---

## Why Not Just Use kubectl create secret?

| Approach | Problem |
|---|---|
| `kubectl create secret` manually | Someone has to know the real value. It's not audited. No rotation. |
| Secret in values file | Gets committed to git accidentally. Permanent security risk. |
| AWS Secrets Manager + ESO ✅ | Values never leave AWS. Auto-rotates. Full audit trail. Nobody handles raw values. |

---

## Production Security & Compliance Highlights

- **Principle of Least Privilege:** Pods are assigned specific IAM roles via IRSA (IAM Roles for Service Accounts) with read-only access to their respective secret paths.
- **Zero Static Credentials:** No AWS Access Keys (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`) are ever embedded into Kubernetes manifests or container images.
- **Automated Secret Rotation:** If a database password or API key is rotated in AWS Secrets Manager, ESO updates the Kubernetes Secret on the next refresh interval without requiring a Helm redeployment.
