#!/usr/bin/env bash
set -euo pipefail

PROM_URL="http://127.0.0.1:9090"

prom_query() {
  local q="$1"
  curl -sG "${PROM_URL}/api/v1/query" --data-urlencode "query=${q}" | jq -r '.data.result[0].value[1] // "0"'
}

echo "=================================================================="
echo " TASK 04: PROMETHEUS TARGETS, 5 PROMQL QUERIES & HOST CROSS-CHECKS"
echo "=================================================================="

echo -e "\n[1] Prometheus Scrape Targets Status (Both must be UP):"
curl -s "${PROM_URL}/api/v1/targets" | jq -r '.data.activeTargets[] | "Job: \(.labels.job) | Endpoint: \(.scrapeUrl) | Health: \(.health) | Interval: \(.scrapeInterval)"'

echo -e "\n[2] Five Required PromQL Expressions (Live Readings):"
echo "  1. Host CPU Utilization (%)     : $(prom_query '100 - (avg by (instance) (rate(node_cpu_seconds_total{job="ubuntu-node-exporter", mode="idle"}[1m])) * 100)') %"
echo "  2. Host RAM Utilization (%)     : $(prom_query '((node_memory_MemTotal_bytes{job="ubuntu-node-exporter"} - node_memory_MemAvailable_bytes{job="ubuntu-node-exporter"}) / node_memory_MemTotal_bytes{job="ubuntu-node-exporter"}) * 100') %"
echo "  3. App Requests / Second (RPS)  : $(prom_query 'sum(rate(order_api_http_requests_total{job="order-api"}[1m]))') req/s"
echo "  4. App Error / Failure Rate (%) : $(prom_query '(sum(rate(order_api_http_requests_total{job="order-api", outcome="failure"}[1m])) / clamp_min(sum(rate(order_api_http_requests_total{job="order-api"}[1m])), 0.0001)) * 100') %"
echo "  5. App p95 Request Latency (s)  : $(prom_query 'histogram_quantile(0.95, sum by (le) (rate(order_api_http_request_duration_seconds_bucket{job="order-api", route="/api/orders"}[1m])))') sec"

echo -e "\n=================================================================="
echo " [3] UBUNTU HOST CLI CROSS-CHECKS VS. PROMETHEUS NODE EXPORTER"
echo "=================================================================="

echo -e "\n--- Cross-Check A: RAM (Prometheus vs. 'free -m') ---"
PROM_MEM_TOTAL_MB=$(prom_query 'node_memory_MemTotal_bytes / 1024 / 1024' | awk '{printf "%.0f", $1}')
PROM_MEM_AVAIL_MB=$(prom_query 'node_memory_MemAvailable_bytes / 1024 / 1024' | awk '{printf "%.0f", $1}')
echo "Prometheus Reading -> MemTotal: ${PROM_MEM_TOTAL_MB} MiB | MemAvailable: ${PROM_MEM_AVAIL_MB} MiB"
echo "Ubuntu CLI Reading -> (free -m):"
free -m

echo -e "\n--- Cross-Check B: Root Filesystem '/' (Prometheus vs. 'df -B1M /') ---"
PROM_DISK_SIZE_MB=$(prom_query 'node_filesystem_size_bytes{mountpoint="/"} / 1024 / 1024' | awk '{printf "%.0f", $1}')
PROM_DISK_AVAIL_MB=$(prom_query 'node_filesystem_avail_bytes{mountpoint="/"} / 1024 / 1024' | awk '{printf "%.0f", $1}')
echo "Prometheus Reading -> Root Size: ${PROM_DISK_SIZE_MB} MiB | Root Available: ${PROM_DISK_AVAIL_MB} MiB"
echo "Ubuntu CLI Reading -> (df -B1M /):"
df -B1M /

echo -e "\n--- Cross-Check C: System Uptime (Prometheus vs. 'uptime' & '/proc/uptime') ---"
PROM_UPTIME_SEC=$(prom_query 'node_time_seconds - node_boot_time_seconds' | awk '{printf "%.0f", $1}')
CLI_UPTIME_SEC=$(awk '{printf "%.0f", $1}' /proc/uptime)
echo "Prometheus Reading -> Uptime: ${PROM_UPTIME_SEC} seconds"
echo "Ubuntu CLI Reading -> /proc/uptime: ${CLI_UPTIME_SEC} seconds | $(uptime -p)"
