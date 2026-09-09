# CI/CD Configurations

This folder contains CI/CD pipeline definitions for different CI platforms.

## Available Configurations

| File | Platform | Status |
|------|----------|--------|
| `../.github/workflows/helm-publish.yml` | **GitHub Actions** | ✅ Active — runs automatically on push to `main` |
| `Jenkinsfile` | **Jenkins** | 📄 Reference — use if your team runs a Jenkins server instead |

## Which one is actually running?

**GitHub Actions** is the active pipeline. GitHub automatically detects workflows in `.github/workflows/` — no configuration needed.

The `Jenkinsfile` in this folder is a reference implementation showing the **same 4-stage pipeline** on Jenkins. If the team were using Jenkins instead of GitHub Actions, you would:
1. Copy `Jenkinsfile` to the repo root (Jenkins looks for it there by default)
2. Create a **Multibranch Pipeline** job in Jenkins pointing at this repository
3. Set up the two credentials in Jenkins (`GHCR_TOKEN`, `GHCR_USERNAME`)
4. Remove or disable the GitHub Actions workflow

## Pipeline Stages (same logic on both platforms)

```
Push to main
     │
     ▼
 ┌─────────┐     ┌─────────────┐     ┌──────────────────┐     ┌─────────┐
 │  Lint   │────▶│ Unit Tests  │────▶│ Integration Test │────▶│ Publish │
 │         │     │(helm-unittest│     │  (kind cluster)  │     │ to OCI  │
 └─────────┘     └─────────────┘     └──────────────────┘     └─────────┘
    PRs + main        PRs + main           PRs + main          main only
```

## GitHub Actions vs Jenkins — Key Differences

| Feature | GitHub Actions | Jenkins |
|---|---|---|
| Where pipeline lives | `.github/workflows/*.yml` | `Jenkinsfile` (repo root) |
| Triggered by | GitHub webhook (automatic) | GitHub webhook or poll SCM |
| Credentials | GitHub Secrets (repo settings) | Jenkins Credentials store |
| Agents/runners | GitHub-hosted or self-hosted | Jenkins agents (nodes) |
| Test reporting | Upload artifact | Built-in JUnit plugin (`junit` step) |
| Kind cluster support | `helm/kind-action` orb | Direct `kind` binary on agent |

## Why CI/CD for the chart itself?

Most teams only have CI/CD for their application code. Having a pipeline specifically for the **Helm chart** means:

- A broken chart can never reach the registry (lint + tests gate the publish)
- Every published chart version is traceable to a specific git commit
- The chart is treated as a first-class versioned artifact, not just files in a repo
