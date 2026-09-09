#!/bin/bash
# =============================================================
# test-local.sh — Complete local test walkthrough
# Run this from the project root folder:
#   cd mlops-helm-assignment
#   bash test-local.sh
# =============================================================

set -e  # Stop immediately if any command fails

CHART_PATH="./helm/ml-api-chart"
VALUES_DEV="./values/values-dev.yaml"
RELEASE_NAME="ml-api-local"
NAMESPACE="ml-local"   # local Minikube namespace — separate from cloud ml-dev/staging/prod
PORT="9090"   # Using 9090 to avoid conflict with Jenkins on 8080

echo ""
echo "=============================================="
echo "  ML API Helm Chart — Local Test Walkthrough"
echo "=============================================="
echo ""

# -------------------------------------------------------
# STEP 1: Start Minikube
# -------------------------------------------------------
echo "STEP 1: Starting Minikube..."
minikube start --driver=docker --cpus=2 --memory=3500mb
echo "Minikube is running!"
echo ""

# -------------------------------------------------------
# STEP 2: Helm lint
# -------------------------------------------------------
echo "STEP 2: Linting the chart..."
helm lint $CHART_PATH -f $VALUES_DEV --strict
echo "Lint passed!"
echo ""

# -------------------------------------------------------
# STEP 3: Template render (dry run — shows generated YAML)
# -------------------------------------------------------
echo "STEP 3: Rendering templates..."
helm template $RELEASE_NAME $CHART_PATH \
  -f $VALUES_DEV \
  --namespace $NAMESPACE \
  > /tmp/rendered-dev.yaml
echo "Rendered YAML saved to /tmp/rendered-dev.yaml"
echo ""

# -------------------------------------------------------
# STEP 4: Install helm-unittest plugin and run unit tests
# -------------------------------------------------------
echo "STEP 4: Running unit tests..."
helm plugin list 2>/dev/null | grep -q unittest || \
    helm plugin install https://github.com/helm-unittest/helm-unittest --verify=false
helm unittest $CHART_PATH
echo ""

# -------------------------------------------------------
# STEP 5: Build our ML API Docker image inside Minikube
# -------------------------------------------------------
echo "STEP 5: Building ML API Docker image inside Minikube..."
eval $(minikube docker-env)
docker build -t ml-api:local ./app/
echo "Image built successfully!"
echo ""

# -------------------------------------------------------
# STEP 6: Deploy chart to Minikube using our image
# -------------------------------------------------------
echo "STEP 6: Deploying chart to Minikube (dev environment)..."
kubectl create namespace $NAMESPACE 2>/dev/null || echo "Namespace already exists"

helm upgrade --install $RELEASE_NAME $CHART_PATH \
  -f $VALUES_DEV \
  -f values/values-local.yaml \
  --namespace $NAMESPACE \
  --wait \
  --timeout 120s

echo ""
echo "Deployed! Pod status:"
kubectl get pods -n $NAMESPACE
echo ""

# -------------------------------------------------------
# STEP 7: Port-forward and call the API
# -------------------------------------------------------
echo "STEP 7: Starting port-forward on port $PORT..."
kubectl port-forward svc/$RELEASE_NAME-ml-api-chart $PORT:80 -n $NAMESPACE &
PF_PID=$!
sleep 3

echo ""
echo "Calling API endpoints..."
echo ""

echo "--- GET / ---"
curl -s http://localhost:$PORT/ | python3 -m json.tool

echo ""
echo "--- GET /health ---"
curl -s http://localhost:$PORT/health | python3 -m json.tool

echo ""
echo "--- GET /ready ---"
curl -s http://localhost:$PORT/ready | python3 -m json.tool

echo ""
echo "--- GET /predict?input=test123 ---"
curl -s "http://localhost:$PORT/predict?input=test123" | python3 -m json.tool

echo ""

# -------------------------------------------------------
# STEP 8: Run helm test (connectivity test pod in-cluster)
# -------------------------------------------------------
echo "STEP 8: Running helm test (in-cluster connectivity test)..."
helm test $RELEASE_NAME -n $NAMESPACE --logs
echo ""

# -------------------------------------------------------
# Useful commands reference
# -------------------------------------------------------
echo "=============================================="
echo "  Useful Commands"
echo "=============================================="
echo ""
echo "See all resources deployed:"
echo "  kubectl get all -n $NAMESPACE"
echo ""
echo "See what values the release was deployed with:"
echo "  helm get values $RELEASE_NAME -n $NAMESPACE"
echo ""
echo "See deployment history:"
echo "  helm history $RELEASE_NAME -n $NAMESPACE"
echo ""
echo "Rollback to previous version:"
echo "  helm rollback $RELEASE_NAME -n $NAMESPACE"
echo ""
echo "Uninstall everything:"
echo "  helm uninstall $RELEASE_NAME -n $NAMESPACE"
echo ""
echo "Stop Minikube:"
echo "  minikube stop"
echo ""

# Stop port-forward
kill $PF_PID 2>/dev/null || true
echo "Port-forward stopped."
echo ""
echo "=== All done! ==="
