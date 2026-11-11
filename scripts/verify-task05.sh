#!/usr/bin/env bash
set -euo pipefail

LOKI_URL="http://192.168.56.10:3100"

echo "=================================================================="
echo " TASK 05: MICROK8S WORKLOAD, ALLOY COLLECTOR & LOKI VERIFICATION"
echo "=================================================================="

echo -e "\n[1/5] MicroK8s Workload & Alloy Collector Pod Status:"
microk8s kubectl get pods -n order-workloads -o wide
microk8s kubectl get pods -n observability -o wide

echo -e "\n[2/5] Direct Pod Output via 'microk8s kubectl logs' (Last 6 lines):"
microk8s kubectl logs deployment/order-worker -n order-workloads --tail=6

echo -e "\n[3/5] Verifying Kubernetes Labels Ingested into Docker Compose Loki:"
echo -n "Namespaces in Loki : "
curl -s "${LOKI_URL}/loki/api/v1/label/namespace/values" | jq -c '.data'
echo -n "Pods in Loki       : "
curl -s "${LOKI_URL}/loki/api/v1/label/pod/values" | jq -c '.data'
echo -n "Streams in Loki    : "
curl -s "${LOKI_URL}/loki/api/v1/label/stream/values" | jq -c '.data'
echo -n "Log Levels in Loki : "
curl -s "${LOKI_URL}/loki/api/v1/label/level/values" | jq -c '.data'

echo -e "\n[4/5] LogQL Query 1 — Normal Operational Logs ({namespace=\"order-workloads\", stream=\"stdout\"}):"
curl -sG "${LOKI_URL}/loki/api/v1/query_range" \
  --data-urlencode 'query={namespace="order-workloads", container="order-worker", stream="stdout"} |= "INFO"' \
  --data-urlencode 'limit=3' | jq -r '.data.result[].values[][1]'

echo -e "\n[5/5] LogQL Query 2 — Error Logs ({namespace=\"order-workloads\", stream=\"stderr\"}):"
curl -sG "${LOKI_URL}/loki/api/v1/query_range" \
  --data-urlencode 'query={namespace="order-workloads", container="order-worker", stream="stderr"} |= "ERROR"' \
  --data-urlencode 'limit=3' | jq -r '.data.result[].values[][1]'

echo -e "\n=================================================================="
echo " Task 05 Cross-Check Complete! Save screenshot for Task 05 proof."
echo "=================================================================="
