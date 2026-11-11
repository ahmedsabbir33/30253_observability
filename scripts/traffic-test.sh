#!/usr/bin/env bash
set -euo pipefail

API_URL="${API_URL:-http://127.0.0.1:8000}"

echo "=================================================================="
echo " Task 03: Order API Telemetry & Multi-Rate Traffic Verification"
echo " Target Endpoint: ${API_URL}"
echo "=================================================================="

echo -e "\n[1/6] Verifying GET /health..."
curl -s "${API_URL}/health" | jq .

echo -e "\n[2/6] Snapshot of Custom Prometheus Metrics BEFORE Traffic..."
curl -s "${API_URL}/metrics" | grep -E "^(order_api_http_requests_total|order_api_orders_created_total|order_api_order_failures_total|order_api_http_request_duration_seconds_count)" || true

echo -e "\n[3/6] Testing Single Requests (HTTP 201 Success, HTTP 400 Validation Error, HTTP 500 Gateway Crash)..."
echo "--> (a) Normal Order Request (Expected: HTTP 201):"
curl -s -w "\nHTTP_STATUS: %{http_code}\n" -X POST "${API_URL}/api/orders" \
  -H "Content-Type: application/json" \
  -d '{"item":"usb-c-dock","quantity":2,"category":"electronics","payment_method":"card","mode":"normal"}'

echo -e "\n--> (b) Controlled Client Validation Error (Expected: HTTP 400):"
curl -s -w "\nHTTP_STATUS: %{http_code}\n" -X POST "${API_URL}/api/orders" \
  -H "Content-Type: application/json" \
  -d '{"item":"usb-c-dock","quantity":0,"category":"electronics","payment_method":"card","mode":"error400"}'

echo -e "\n--> (c) Controlled Server Payment Crash (Expected: HTTP 500):"
curl -s -w "\nHTTP_STATUS: %{http_code}\n" -X POST "${API_URL}/api/orders" \
  -H "Content-Type: application/json" \
  -d '{"item":"usb-c-dock","quantity":1,"category":"electronics","payment_method":"bkash","mode":"error500"}'

echo -e "\n[4/6] Phase A — Steady Low-Rate Traffic (10 requests @ ~3 req/sec)..."
for i in {1..10}; do
  curl -s -o /dev/null -X POST "${API_URL}/api/orders" \
    -H "Content-Type: application/json" \
    -d "{\"item\":\"book-vol-${i}\",\"quantity\":1,\"category\":\"books\",\"payment_method\":\"card\",\"mode\":\"normal\"}"
  sleep 0.3
done
echo "Completed 10 steady low-rate requests."

echo -e "\n[5/6] Phase B — Concurrent High-Rate Burst (30 mixed requests: 18 normal, 6 slow, 6 failed)..."
for i in {1..18}; do
  curl -s -o /dev/null -X POST "${API_URL}/api/orders" \
    -H "Content-Type: application/json" \
    -d "{\"item\":\"grocery-pack-${i}\",\"quantity\":3,\"category\":\"groceries\",\"payment_method\":\"cod\",\"mode\":\"normal\"}" &
done
for i in {1..6}; do
  curl -s -o /dev/null -X POST "${API_URL}/api/orders" \
    -H "Content-Type: application/json" \
    -d "{\"item\":\"4k-monitor-${i}\",\"quantity\":1,\"category\":\"electronics\",\"payment_method\":\"card\",\"mode\":\"slow\"}" &
done
for i in {1..6}; do
  curl -s -o /dev/null -X POST "${API_URL}/api/orders" \
    -H "Content-Type: application/json" \
    -d "{\"item\":\"failed-order-${i}\",\"quantity\":1,\"category\":\"electronics\",\"payment_method\":\"bkash\",\"mode\":\"error500\"}" &
done
wait
echo "Completed 30 concurrent burst requests."

echo -e "\n[6/6] Snapshot of Custom Prometheus Metrics AFTER Traffic (Counters, Outcomes & Histogram Buckets)..."
curl -s "${API_URL}/metrics" | grep -E "^(order_api_http_requests_total|order_api_orders_created_total|order_api_order_failures_total|order_api_http_request_duration_seconds_bucket\{le=\"(0\.05|0\.1|0\.5|1|\+Inf)\".*route=\"/api/orders\"|order_api_http_request_duration_seconds_count)"

echo -e "\n=================================================================="
echo " Task 03 Verification Complete!"
echo "=================================================================="
