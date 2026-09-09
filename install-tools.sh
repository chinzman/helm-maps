#!/bin/bash
# =============================================================
# install-tools.sh
# Installs minikube, helm, kubectl via Homebrew
# Run this AFTER Docker Desktop is open and running
# =============================================================

set -e

echo "Installing kubectl..."
brew install kubectl

echo ""
echo "Installing helm..."
brew install helm

echo ""
echo "Installing minikube..."
brew install minikube

echo ""
echo "Installing helm-unittest plugin..."
helm plugin install https://github.com/helm-unittest/helm-unittest --verify=false || echo "(already installed)"

echo ""
echo "=== All done! Versions ==="
kubectl version --client --short
helm version --short
minikube version
