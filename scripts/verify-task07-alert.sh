#!/usr/bin/env bash
set -euo pipefail

API_URL="http://127.0.0.1:8000"
GRAFANA_URL="http://127.0.0.1:3000"
MAILPIT_URL="http://127.0.0.1:8025"

echo "=================================================================="
echo " TASK 06 & 07: GRAFANA PROVISIONING, ALERT TRIGGER & MAILPIT TEST"
echo "=================================================================="

echo -e "\n[1/5] Waiting for Grafana & Mailpit APIs to be ready..."
until curl -s "${GRAFANA_URL}/api/health" | grep -q "ok"; do sleep 2; done
until curl -s "${MAILPIT_URL}/api/v1/info" | grep -q "Version"; do sleep 2; done
echo "Grafana and Mailpit are UP!"

echo -e "\n[2/5] Triggering High HTTP 500 Error Rate (>20%) on Order API..."
for i in {1..30}; do
  curl -s -o /dev/null -X POST "${API_URL}/api/orders" \
    -H "Content-Type: application/json" \
    -d '{"item":"alert-trigger","quantity":1,"category":"electronics","payment_method":"bkash","mode":"error500"}' &
done
wait
echo "Sent 30 HTTP 500 requests. Waiting 25 seconds for Prometheus scrape + Grafana Alert evaluation..."
sleep 25

echo -e "\n[3/5] Checking Grafana Alert State via API:"
curl -s -u admin:changeme_local_only "${GRAFANA_URL}/api/prometheus/grafana/api/v1/rules" \
  | jq -r '.data.groups[].rules[] | "Rule: \(.name) | State: \(.state) | Health: \(.health)"'

echo -e "\n[4/5] Checking Delivered Alert Emails in Mailpit Inbox (${MAILPIT_URL}):"
curl -s "${MAILPIT_URL}/api/v1/messages" \
  | jq -r '.messages[] | "From: \(.From.Address) | To: \(.To[0].Address) | Subject: \(.Subject) | Created: \(.Created)"'

echo -e "\n[5/5] Restoring Normal Traffic (40 Valid HTTP 201 Orders) to Resolve Alert..."
for i in {1..40}; do
  curl -s -o /dev/null -X POST "${API_URL}/api/orders" \
    -H "Content-Type: application/json" \
    -d '{"item":"recovery-order","quantity":1,"category":"books","payment_method":"card","mode":"normal"}'
  sleep 0.2
done
echo "Sent 40 valid orders. Check http://192.168.56.10:8025 in your browser to view both FIRING and RESOLVED emails!"
