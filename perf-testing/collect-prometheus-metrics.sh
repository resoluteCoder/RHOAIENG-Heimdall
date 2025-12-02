#!/bin/bash

# Prometheus Metrics Collection Script
# Collects aggregated metrics over a test window from Prometheus

set -e

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Collect aggregated Prometheus metrics over a test window.

REQUIRED ARGUMENTS:
  --duration SECONDS      Test duration in seconds
  --start-time TIMESTAMP  Test start time (unix timestamp)
  --output FILE           Output metrics file path

OPTIONAL ARGUMENTS:
  --prom-route HOST       Prometheus route hostname (auto-detected if not provided)
  --prom-token TOKEN      Prometheus auth token (auto-detected if not provided)

EXAMPLES:
  $0 --duration 120 --start-time 1234567890 --output metrics.log
  $0 --duration 300 --start-time \$(date +%s) --output test-metrics.log --prom-route prometheus.example.com

EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --duration)
            DURATION="$2"
            shift 2
            ;;
        --start-time)
            START_TIME="$2"
            shift 2
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --prom-route)
            PROM_ROUTE="$2"
            shift 2
            ;;
        --prom-token)
            PROM_TOKEN="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Error: Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [ -z "$DURATION" ] || [ -z "$START_TIME" ] || [ -z "$OUTPUT_FILE" ]; then
    echo "Error: Missing required arguments"
    usage
fi

# Helper function to parse Prometheus response
parse_prom_value() {
    local response=$1
    # Try jq first (cleaner output)
    if command -v jq &> /dev/null; then
        echo "$response" | jq -r '.data.result[0].value[1] // "N/A"' 2>/dev/null || echo "N/A"
    else
        # Fallback to grep/sed
        echo "$response" | grep -o '"value":\[[^]]*\]' | head -1 | sed 's/"value":\[.*,"\?\([^"]*\)"\?\]/\1/' 2>/dev/null || echo "N/A"
    fi
}

# Helper function to collect a single metric
collect_metric() {
    local metric_label=$1
    local prom_query=$2
    local prom_route=$3
    local prom_token=$4
    local metrics_file=$5
    
    echo "## ${metric_label}:" >> "$metrics_file"
    local response=$(curl -k -s -H "Authorization: Bearer $prom_token" \
        --data-urlencode "query=${prom_query}" \
        "https://$prom_route/api/v1/query" 2>/dev/null)
    parse_prom_value "$response" >> "$metrics_file"
}

# Write header
timestamp=$(date +"%Y-%m-%d %H:%M:%S")
cat > "$OUTPUT_FILE" <<EOF
K6 Load Test - Prometheus Metrics (Aggregated)
Generated: $(date)
Configuration: Collecting aggregated metrics over entire test window

Metrics Collected (single aggregated value per metric):
- kube-auth-proxy CPU/Memory (avg, max over test duration) - 3.x only
- echo-server CPU/Memory (avg, max over test duration)
- Gateway CPU/Memory (avg, max over test duration) - 3.x Envoy gateway
- Router CPU/Memory (avg, max over test duration) - 2.x OpenShift router
- kube-rbac-proxy CPU/Memory (avg, max over test duration) - sidecar in echo-server, 3.x only
- oauth-proxy CPU/Memory (avg, max over test duration) - 2.x use case
- oauth-apiserver CPU/Memory (avg, max over test duration) - 3.x only
- kube-apiserver CPU/Memory (avg, max over test duration)
- K6 pod resource usage (avg, max over test duration)
- Worker nodes CPU utilization (avg, max over test duration)

================================================================================

=== AGGREGATED METRICS OVER TEST WINDOW ===
Test Start: $(date -r $START_TIME '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d @$START_TIME '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo $START_TIME)
Test End: $timestamp
Duration: ${DURATION}s

EOF

# Get Prometheus route and token if not provided
if [ -z "$PROM_ROUTE" ]; then
    PROM_ROUTE=$(oc get route -n openshift-monitoring prometheus-k8s -o jsonpath='{.spec.host}' 2>/dev/null || true)
fi

if [ -z "$PROM_TOKEN" ]; then
    PROM_TOKEN=$(oc whoami -t 2>/dev/null || true)
    if [ -z "$PROM_TOKEN" ]; then
        # If no token from whoami, try to create one
        PROM_TOKEN=$(oc create token prometheus-k8s -n openshift-monitoring --duration=10m 2>/dev/null || true)
    fi
fi

# Check if Prometheus is accessible
if [ -z "$PROM_ROUTE" ] || [ -z "$PROM_TOKEN" ]; then
    echo "Unable to access Prometheus - metrics not available" >> "$OUTPUT_FILE"
    echo "Note: Aggregated metrics require Prometheus access." >> "$OUTPUT_FILE"
    echo "Point-in-time fallback with 'oc adm top' is not suitable for aggregations." >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    exit 0
fi

# Use the test duration for range queries
range="${DURATION}s"

# Collect metrics for all components
# The script collects metrics for both 2.x and 3.x setups
# Components that don't exist will show N/A

# echo-server metrics
collect_metric "echo-server CPU - Average (cores)" \
    "avg_over_time(rate(container_cpu_usage_seconds_total{namespace=\"opendatahub\",pod=~\"echo-server.*\"}[2m])[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "echo-server CPU - Max (cores)" \
    "max_over_time(rate(container_cpu_usage_seconds_total{namespace=\"opendatahub\",pod=~\"echo-server.*\"}[2m])[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "echo-server Memory - Average (bytes)" \
    "avg_over_time(container_memory_working_set_bytes{namespace=\"opendatahub\",pod=~\"echo-server.*\"}[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "echo-server Memory - Max (bytes)" \
    "max_over_time(container_memory_working_set_bytes{namespace=\"opendatahub\",pod=~\"echo-server.*\"}[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"

# k6-benchmark pod metrics
collect_metric "k6-benchmark CPU - Average (cores)" \
    "avg_over_time(rate(container_cpu_usage_seconds_total{namespace=\"opendatahub\",pod=\"k6-benchmark\"}[2m])[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "k6-benchmark CPU - Max (cores)" \
    "max_over_time(rate(container_cpu_usage_seconds_total{namespace=\"opendatahub\",pod=\"k6-benchmark\"}[2m])[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "k6-benchmark Memory - Average (bytes)" \
    "avg_over_time(container_memory_working_set_bytes{namespace=\"opendatahub\",pod=\"k6-benchmark\"}[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "k6-benchmark Memory - Max (bytes)" \
    "max_over_time(container_memory_working_set_bytes{namespace=\"opendatahub\",pod=\"k6-benchmark\"}[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"

# Router metrics (2.x setup - OpenShift ingress router)
collect_metric "Router CPU - Average (cores)" \
    "avg_over_time(rate(container_cpu_usage_seconds_total{namespace=\"openshift-ingress\",container=\"router\"}[2m])[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "Router CPU - Max (cores)" \
    "max_over_time(rate(container_cpu_usage_seconds_total{namespace=\"openshift-ingress\",container=\"router\"}[2m])[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "Router Memory - Average (bytes)" \
    "avg_over_time(container_memory_working_set_bytes{namespace=\"openshift-ingress\",container=\"router\"}[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "Router Memory - Max (bytes)" \
    "max_over_time(container_memory_working_set_bytes{namespace=\"openshift-ingress\",container=\"router\"}[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"

# oauth-proxy (2.x use case) metrics
collect_metric "oauth-proxy CPU - Average (cores)" \
    "avg_over_time(rate(container_cpu_usage_seconds_total{namespace=\"opendatahub\",pod=~\"echo-server.*\",container=\"oauth-proxy\"}[2m])[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "oauth-proxy CPU - Max (cores)" \
    "max_over_time(rate(container_cpu_usage_seconds_total{namespace=\"opendatahub\",pod=~\"echo-server.*\",container=\"oauth-proxy\"}[2m])[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "oauth-proxy Memory - Average (bytes)" \
    "avg_over_time(container_memory_working_set_bytes{namespace=\"opendatahub\",pod=~\"echo-server.*\",container=\"oauth-proxy\"}[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "oauth-proxy Memory - Max (bytes)" \
    "max_over_time(container_memory_working_set_bytes{namespace=\"opendatahub\",pod=~\"echo-server.*\",container=\"oauth-proxy\"}[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"

# kube-auth-proxy metrics (3.x setup only)
collect_metric "kube-auth-proxy CPU - Average (cores)" \
    "avg_over_time(rate(container_cpu_usage_seconds_total{namespace=\"openshift-ingress\",container=\"kube-auth-proxy\"}[2m])[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "kube-auth-proxy CPU - Max (cores)" \
    "max_over_time(rate(container_cpu_usage_seconds_total{namespace=\"openshift-ingress\",container=\"kube-auth-proxy\"}[2m])[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "kube-auth-proxy Memory - Average (bytes)" \
    "avg_over_time(container_memory_working_set_bytes{namespace=\"openshift-ingress\",container=\"kube-auth-proxy\"}[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "kube-auth-proxy Memory - Max (bytes)" \
    "max_over_time(container_memory_working_set_bytes{namespace=\"openshift-ingress\",container=\"kube-auth-proxy\"}[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"

# Gateway metrics (3.x setup - Istio proxy)
collect_metric "Gateway CPU - Average (cores)" \
    "avg_over_time(rate(container_cpu_usage_seconds_total{namespace=\"openshift-ingress\",container=\"istio-proxy\"}[2m])[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "Gateway CPU - Max (cores)" \
    "max_over_time(rate(container_cpu_usage_seconds_total{namespace=\"openshift-ingress\",container=\"istio-proxy\"}[2m])[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "Gateway Memory - Average (bytes)" \
    "avg_over_time(container_memory_working_set_bytes{namespace=\"openshift-ingress\",container=\"istio-proxy\"}[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "Gateway Memory - Max (bytes)" \
    "max_over_time(container_memory_working_set_bytes{namespace=\"openshift-ingress\",container=\"istio-proxy\"}[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"

# kube-rbac-proxy (sidecar in echo-server) metrics (3.x setup only)
collect_metric "kube-rbac-proxy CPU - Average (cores)" \
    "avg_over_time(rate(container_cpu_usage_seconds_total{namespace=\"opendatahub\",pod=~\"echo-server.*\",container=\"kube-rbac-proxy\"}[2m])[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "kube-rbac-proxy CPU - Max (cores)" \
    "max_over_time(rate(container_cpu_usage_seconds_total{namespace=\"opendatahub\",pod=~\"echo-server.*\",container=\"kube-rbac-proxy\"}[2m])[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "kube-rbac-proxy Memory - Average (bytes)" \
    "avg_over_time(container_memory_working_set_bytes{namespace=\"opendatahub\",pod=~\"echo-server.*\",container=\"kube-rbac-proxy\"}[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "kube-rbac-proxy Memory - Max (bytes)" \
    "max_over_time(container_memory_working_set_bytes{namespace=\"opendatahub\",pod=~\"echo-server.*\",container=\"kube-rbac-proxy\"}[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"

# oauth-apiserver metrics (3.x setup only)
collect_metric "oauth-apiserver CPU - Average (cores)" \
    "avg_over_time(rate(container_cpu_usage_seconds_total{namespace=\"openshift-oauth-apiserver\",container=\"oauth-apiserver\"}[2m])[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "oauth-apiserver CPU - Max (cores)" \
    "max_over_time(rate(container_cpu_usage_seconds_total{namespace=\"openshift-oauth-apiserver\",container=\"oauth-apiserver\"}[2m])[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "oauth-apiserver Memory - Average (bytes)" \
    "avg_over_time(container_memory_working_set_bytes{namespace=\"openshift-oauth-apiserver\",container=\"oauth-apiserver\"}[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "oauth-apiserver Memory - Max (bytes)" \
    "max_over_time(container_memory_working_set_bytes{namespace=\"openshift-oauth-apiserver\",container=\"oauth-apiserver\"}[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"

# kube-apiserver metrics
collect_metric "kube-apiserver CPU - Average (cores)" \
    "avg_over_time(rate(container_cpu_usage_seconds_total{namespace=\"openshift-kube-apiserver\",container=\"kube-apiserver\"}[2m])[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "kube-apiserver CPU - Max (cores)" \
    "max_over_time(rate(container_cpu_usage_seconds_total{namespace=\"openshift-kube-apiserver\",container=\"kube-apiserver\"}[2m])[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "kube-apiserver Memory - Average (bytes)" \
    "avg_over_time(container_memory_working_set_bytes{namespace=\"openshift-kube-apiserver\",container=\"kube-apiserver\"}[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "kube-apiserver Memory - Max (bytes)" \
    "max_over_time(container_memory_working_set_bytes{namespace=\"openshift-kube-apiserver\",container=\"kube-apiserver\"}[$range:])" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"

# Worker nodes CPU utilization (average across all nodes)
collect_metric "Worker nodes total CPU utilization - Average (%)" \
    "avg_over_time((1 - avg(rate(node_cpu_seconds_total{mode=\"idle\"}[2m])))[$range:]) * 100" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"
collect_metric "Worker nodes total CPU utilization - Max (%)" \
    "max_over_time((1 - min(rate(node_cpu_seconds_total{mode=\"idle\"}[2m])))[$range:]) * 100" \
    "$PROM_ROUTE" "$PROM_TOKEN" "$OUTPUT_FILE"

echo "" >> "$OUTPUT_FILE"

