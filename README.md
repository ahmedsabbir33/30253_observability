# End-to-End Observability Platform (Docker Compose + MicroK8s)

**Author:** Sabbir Ahmed  
**Candidate ID:** `30253`  
**GitHub:** [@ahmedsabbir33](https://github.com/ahmedsabbir33)  
**Target OS:** Ubuntu 26.04 LTS (Reproducible via Vagrant + VirtualBox or Native Ubuntu Host)  
**Tech Stack:** Node.js (Express + `prom-client`), Prometheus, Node Exporter, Grafana Loki, Grafana Alloy, Grafana Unified Alerting, Mailpit SMTP, Docker Compose v2, MicroK8s

---

## 1. Project Overview & Three Operational Flows

This repository delivers a complete, reproducible observability platform running on Ubuntu 26.04 with **Docker Compose** and **MicroK8s**. It implements and verifies three end-to-end operational flows:

| Flow | Telemetry Source | Collector / Forwarder | Storage / Engine | Visualization & Verification |
| :--- | :--- | :--- | :--- | :--- |
| **01. Live Metrics** | Ubuntu 26.04 Host Kernel + Node.js Order API (`app/`) | Node Exporter (`:9100`) + Prometheus (`5s` scrape interval) | Prometheus TSDB (`prometheus_data` volume) | Grafana 10-Panel Unified Dashboard + Ubuntu CLI (`free`, `df`, `uptime`) cross-checks |
| **02. Kubernetes Logs** | MicroK8s `order-worker` Deployment (`stdout` INFO & `stderr` ERROR) | Grafana Alloy DaemonSet (`observability` namespace) | Grafana Loki (`loki_data` volume in Docker Compose) | Grafana Explore & Dashboard Logs Panel via LogQL + `kubectl logs` cross-check |
| **03. Email Alerting** | Order API HTTP Failure Rate (`outcome="failure"` over `20%`) | Grafana Unified Alerting Engine (`10s` evaluation) | Mailpit SMTP Server (`:1025` via `.env`, or external SMTP) | Delivered `[FIRING]` & `[RESOLVED]` alert emails in Mailpit Web Inbox (`:8025`) |

---

## 2. System Architecture & Cross-Environment Networking

~~text
+-----------------------------------------------------------------------------------+
| Ubuntu 26.04 VM / Host (Loopback: 127.0.0.1 | Private Host-Only IP: 192.168.56.10)|
|                                                                                   |
|  +----------------------------- DOCKER COMPOSE --------------------------------+  |
|  |                                                                             |  |
|  |  [node-exporter :9100] --(5s scrape)--> [prometheus :9090]                  |  |
|  |   (/proc, /sys, /rootfs)                        ^                           |  |
|  |                                                 | (PromQL)                  |  |
|  |  [order-api :8000] ------(5s scrape)------------+                           |  |
|  |   (GET /health, POST /api/orders,               v                           |  |
|  |    GET /metrics + Neubrutalist UI)       [grafana :3000] --(SMTP :1025)--> [mailpit :8025]
|  |                                                 ^                           |  |
|  |                                                 | (LogQL)                   |  |
|  |                                           [loki :3100]                      |  |
|  +-------------------------------------------------|---------------------------+  |
|                                                    ^                              |
|                                                    | HTTP POST /loki/api/v1/push  |
|                                                    | (via 192.168.56.10:3100)     |
|  +------------------------------- MICROK8S --------|---------------------------+  |
|  |                                                 |                           |  |
|  |  Namespace: observability         [grafana-alloy DaemonSet]                 |  |
|  |                                                 ^                           |  |
|  |                                                 | K8s Pods/Log API          |  |
|  |  Namespace: order-workloads       [order-worker Deployment]                 |  |
|  |                                    (stdout: INFO JSON | stderr: ERROR JSON) |  |
|  +-----------------------------------------------------------------------------+  |
+-----------------------------------------------------------------------------------+
~~

### How Cross-Boundary Networking Works (MicroK8s Alloy to Docker Compose Loki)
1. **Strict Endpoint Privacy (Task 02):**  
   All Docker Compose services bind strictly to `127.0.0.1` and the private VirtualBox Host-Only interface `192.168.56.10` (never exposed to public LAN/Wi-Fi interfaces). Node Exporter binds exclusively to `127.0.0.1:9100`.
2. **Crossing the Container Runtime Boundary (Task 05):**  
   Inside a MicroK8s pod, `127.0.0.1` refers to the pod's own network namespace. To push logs from the MicroK8s pod network to the Loki container in Docker Compose without exposing Loki publicly, Loki binds to `192.168.56.10:3100` on the Ubuntu VM's internal interface, and Grafana Alloy pushes log batches to `http://192.168.56.10:3100/loki/api/v1/push`.
3. **MicroK8s Snap Log Path Compatibility:**  
   Because MicroK8s is packaged as a strict Snap on Ubuntu, container logs are written under `/var/snap/microk8s/common/var/log/pods`. Grafana Alloy uses `loki.source.kubernetes` to stream pod logs directly through the Kubernetes API (`pods/log`), parsing JSON fields (`level` and `stream`) and attaching bounded Kubernetes labels (`namespace`, `pod`, `container`, `app`, `node`).

---

## 3. Repository Structure

~~text
30253_observability/
├── Vagrantfile                        # Automated Ubuntu 26.04 VM + Docker + MicroK8s provisioner
├── compose.yaml                       # Docker Compose definition (6 services + 3 named volumes)
├── .env.example                       # Environment template (copied to .env during setup)
├── .gitignore                         # Prevents committing .env, .vagrant/, and node_modules/
├── README.md                          # Architecture, setup, verification, and teardown guide
├── app/                               # Task 03: Instrumented Node.js Order API & Neubrutalist Web UI
│   ├── Dockerfile
│   ├── package.json
│   ├── server.js
│   └── public/
│       └── index.html
├── prometheus/                        # Task 04: Prometheus 5s scrape config (Host + Order API)
│   └── prometheus.yml
├── loki/                              # Task 02 & 05: Loki 3.0 TSDB configuration
│   └── config.yml
├── kubernetes/                        # Task 05: MicroK8s namespaces, workload, and Alloy Helm values
│   ├── namespace.yaml
│   ├── workload.yaml
│   └── alloy-values.yaml
├── grafana/                           # Task 06 & 07: Provisioned datasources, alerting, and 10-panel JSON
│   ├── dashboards/
│   │   └── observability-overview.json
│   └── provisioning/
│       ├── alerting/
│       │   └── alerting.yml
│       ├── dashboards/
│       │   └── dashboards.yml
│       └── datasources/
│           └── datasources.yml
├── alerting/                          # Task 07: SMTP & Alerting configuration documentation
│   └── configuration-notes.md
├── scripts/                           # Automated deployment, traffic generation & verification scripts
│   ├── deploy-all.sh
│   ├── teardown.sh
│   ├── traffic-test.sh
│   ├── verify-task04.sh
│   ├── verify-task05.sh
│   └── verify-task07-alert.sh
└── evidence/                          # Screenshots & verification outputs for Tasks 01–07
    ├── 01-compose-and-cluster.png
    ├── 02-order-api-metrics.png
    ├── 03-prometheus-targets.png
    ├── 04-promql-and-host-crosscheck.png
    ├── 05-microk8s-alloy-loki-logs.png
    ├── 06-grafana-unified-dashboard.png
    ├── 07-grafana-alert-firing.png
    └── 08-delivered-alert-email.png
~~

---

## 4. Reproducible Setup Guide

### Option A: Automated Setup with Vagrant (Recommended)
1. Ensure **VirtualBox** and **Vagrant** are installed on your host machine (with at least 6 GB free RAM and 4 vCPUs).
2. Clone the repository and start the environment:
~~bash
git clone https://github.com/ahmedsabbir33/30253_observability.git
cd 30253_observability
vagrant up
~~
3. During `vagrant up`, Vagrant automatically installs Docker Compose and MicroK8s, copies `.env.example` to `.env`, and executes `./scripts/deploy-all.sh`.

### Option B: Setup on an Existing Ubuntu 26.04 Host
~~bash
git clone https://github.com/ahmedsabbir33/30253_observability.git
cd 30253_observability
cp .env.example .env
sudo ip addr add 192.168.56.10/32 dev lo || true
chmod +x scripts/*.sh
./scripts/deploy-all.sh
~~

### Private Service Endpoints
| Service | Private Host-Only URL | Localhost Forwarded URL | Credentials |
| :--- | :--- | :--- | :--- |
| **Order API & Neubrutalist Chaos UI** | `http://192.168.56.10:8000` | `http://127.0.0.1:8000` | None |
| **Grafana Dashboard & Alerting** | `http://192.168.56.10:3000` | `http://127.0.0.1:3000` | `admin` / `changeme_local_only` |
| **Prometheus UI** | `http://192.168.56.10:9090` | `http://127.0.0.1:9090` | None |
| **Mailpit Web Inbox (Alert Emails)** | `http://192.168.56.10:8025` | `http://127.0.0.1:8025` | None |

---

## 5. Step-by-Step Verification Commands (Tasks 01 to 07)

SSH into the Vagrant VM (`vagrant ssh`) and run:
~~bash
cd ~/30253_observability

# Task 01 & 02: Verify Ubuntu 26.04, Docker Compose, MicroK8s & Volume Persistence
lsb_release -a
docker compose ps
microk8s kubectl get nodes -o wide
docker compose restart prometheus loki grafana

# Task 03: Generate normal orders, slow orders, bursts, and HTTP 400/500 failures
./scripts/traffic-test.sh

# Task 04: Run the 5 PromQL queries and compare with Ubuntu CLI (free -m, df -B1M /, uptime)
./scripts/verify-task04.sh

# Task 05: Verify MicroK8s order-worker & Alloy pods and query Loki via LogQL
./scripts/verify-task05.sh

# Task 06 & 07: Trigger >20% HTTP 500 error rate and verify alert email delivery in Mailpit
./scripts/verify-task07-alert.sh
~~

---

## 6. PromQL & LogQL Reference

### Five Required PromQL Expressions (Task 04)
1. **Host CPU Utilization (%):**
~~promql
100 - (avg by (instance) (rate(node_cpu_seconds_total{job="ubuntu-node-exporter", mode="idle"}[1m])) * 100)
~~
2. **Host RAM Utilization (%):**
~~promql
((node_memory_MemTotal_bytes{job="ubuntu-node-exporter"} - node_memory_MemAvailable_bytes{job="ubuntu-node-exporter"}) / node_memory_MemTotal_bytes{job="ubuntu-node-exporter"}) * 100
~~
3. **Order API Request Rate (Requests/sec):**
~~promql
sum(rate(order_api_http_requests_total{job="order-api"}[1m]))
~~
4. **Order API Error / Failure Rate (%):**
~~promql
(sum(rate(order_api_http_requests_total{job="order-api", outcome="failure"}[1m])) / clamp_min(sum(rate(order_api_http_requests_total{job="order-api"}[1m])), 0.0001)) * 100
~~
5. **Order API p95 Request Latency (Seconds):**
~~promql
histogram_quantile(0.95, sum by (le) (rate(order_api_http_request_duration_seconds_bucket{job="order-api", route="/api/orders"}[1m])))
~~

### Key LogQL Queries (Task 05)
- **All Workload Logs:** `{namespace="order-workloads", container="order-worker"}`
- **Normal Logs (`stdout`):** `{namespace="order-workloads", container="order-worker", stream="stdout"} |= "INFO"`
- **Error Logs (`stderr`):** `{namespace="order-workloads", container="order-worker", stream="stderr"} |= "ERROR"`

---

## 7. Architectural Limitation & Production Improvement

- **Current Limitation:**  
  Grafana Alloy inside MicroK8s pushes logs over unauthenticated HTTP to a static private host IP (`192.168.56.10:3100`), and Prometheus/Loki store data on single-node local Docker volumes.
- **Concrete Production Improvement:**  
  Place an mTLS-authenticated OpenTelemetry/Loki gateway in front of Loki with tenant headers (`X-Scope-OrgID`), abstract the host endpoint via a Kubernetes `Service` + `EndpointSlice` backed by internal DNS instead of a static IP, and configure S3-compatible object storage (MinIO/AWS S3) for durable retention.

---

## 8. Clean Teardown & Reset

~~bash
./scripts/teardown.sh
~~
