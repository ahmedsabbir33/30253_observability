#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_DIR}"

echo "=== [1/2] Removing MicroK8s Alloy release, workloads, and namespaces ==="
microk8s helm3 uninstall alloy -n observability 2>/dev/null || true
microk8s kubectl delete -f kubernetes/workload.yaml --ignore-not-found
microk8s kubectl delete -f kubernetes/namespace.yaml --ignore-not-found

echo "=== [2/2] Stopping Docker Compose stack and removing named volumes ==="
docker compose down -v --remove-orphans

echo "=== Clean teardown complete! ==="
