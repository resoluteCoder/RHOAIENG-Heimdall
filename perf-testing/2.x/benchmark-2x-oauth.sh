#!/bin/bash

# Route Benchmark Script - RHOAI 2.x with OAuth
# Runs multiple iterations of hey tests and collects results

set -e

# Auto-detect Route URL if not provided
if [ -z "$ROUTE_URL" ]; then
    echo "Auto-detecting Route URL..."
    ROUTE_HOST=$(oc get route -n opendatahub echo-server-2x -o jsonpath='{.spec.host}' 2>/dev/null)
    if [ -n "$ROUTE_HOST" ]; then
        ROUTE_URL="https://${ROUTE_HOST}"
        echo "✓ Detected Route URL: $ROUTE_URL"
    else
        echo "Error: Could not auto-detect route. Please set ROUTE_URL env var."
        exit 1
    fi
fi

# Configuration
ENDPOINT=""  # 2.x uses root path, not /echo
# TOKEN must be set via environment variable or obtained via 'oc login'
# Example: export TOKEN=$(oc whoami -t)
ITERATIONS=5
TOTAL_REQUESTS=10000
CONCURRENCY=50
WARMUP_REQUESTS=500
WARMUP_CONCURRENCY=10
OUTPUT_FILE="oauth-2x.log"
METRICS_FILE="oauth-2x-metrics.log"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Route Benchmark - RHOAI 2.x OAuth${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Configuration:"
echo "  Route URL: $ROUTE_URL"
echo "  Total Requests: $TOTAL_REQUESTS"
echo "  Concurrency: $CONCURRENCY"
echo "  Iterations: $ITERATIONS"
echo "  Output File: $OUTPUT_FILE"
echo "  Metrics File: $METRICS_FILE"
echo ""

# Verify hey is installed
if ! command -v hey &> /dev/null; then
    echo -e "${YELLOW}Error: 'hey' command not found. Please install it first.${NC}"
    exit 1
fi

# Verify oc is installed
if ! command -v oc &> /dev/null; then
    echo -e "${YELLOW}Error: 'oc' command not found. Please install it first.${NC}"
    exit 1
fi

# Get token from oc if not set
if [ -z "$TOKEN" ]; then
    echo "Getting auth token from oc..."
    TOKEN=$(oc whoami -t 2>/dev/null)
    if [ -z "$TOKEN" ]; then
        echo -e "${YELLOW}Error: No auth token found. Set TOKEN env var or login with 'oc login'${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Got token from oc${NC}"
fi

# Test endpoint connectivity
echo -e "${GREEN}Testing endpoint connectivity...${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: text/html" \
    "$ROUTE_URL$ENDPOINT")

if [ "$HTTP_CODE" != "200" ]; then
    echo -e "${YELLOW}Error: Endpoint returned HTTP $HTTP_CODE${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Endpoint is accessible${NC}"
echo ""

# Initialize output file
cat > "$OUTPUT_FILE" <<EOF
Route Benchmark Results - RHOAI 2.x with OAuth
Generated: $(date)
Configuration: $TOTAL_REQUESTS requests, $CONCURRENCY concurrency, $ITERATIONS iterations
Route URL: $ROUTE_URL$ENDPOINT

================================================================================

EOF

# Initialize metrics file
cat > "$METRICS_FILE" <<EOF
Resource Metrics - RHOAI 2.x Route Components
Generated: $(date)
Configuration: Collecting metrics every 5 seconds during benchmark

Metrics Collected:
- oauth-proxy CPU usage
- oauth-proxy Memory usage
- echo-server CPU/Memory usage

================================================================================

EOF

# Function to collect Prometheus metrics
collect_metrics() {
    local iteration=$1
    local phase=$2  # "start" or "end"

    echo "=== ITERATION $iteration - $phase - $(date) ===" >> "$METRICS_FILE"

    # Get Prometheus route
    PROM_ROUTE=$(oc get route -n openshift-monitoring prometheus-k8s -o jsonpath='{.spec.host}' 2>/dev/null)
    PROM_TOKEN=$(oc whoami -t 2>/dev/null)

    if [ -n "$PROM_ROUTE" ] && [ -n "$PROM_TOKEN" ]; then
        # Collect oauth-proxy CPU
        echo "## oauth-proxy CPU (rate over 5m):" >> "$METRICS_FILE"
        curl -k -s -H "Authorization: Bearer $PROM_TOKEN" \
            --data-urlencode 'query=rate(container_cpu_user_seconds_total{namespace="opendatahub",container="oauth-proxy"}[5m])' \
            "https://$PROM_ROUTE/api/v1/query" \
            | jq -r '.data.result[] | "\(.metric.pod) \(.value[1])"' >> "$METRICS_FILE" 2>&1 || echo "N/A" >> "$METRICS_FILE"

        # Collect oauth-proxy Memory
        echo "## oauth-proxy Memory (bytes):" >> "$METRICS_FILE"
        curl -k -s -H "Authorization: Bearer $PROM_TOKEN" \
            --data-urlencode 'query=container_memory_working_set_bytes{namespace="opendatahub",container="oauth-proxy"}' \
            "https://$PROM_ROUTE/api/v1/query" \
            | jq -r '.data.result[] | "\(.metric.pod) \(.value[1])"' >> "$METRICS_FILE" 2>&1 || echo "N/A" >> "$METRICS_FILE"

        # Collect echo-server CPU
        echo "## echo-server CPU (rate over 5m):" >> "$METRICS_FILE"
        curl -k -s -H "Authorization: Bearer $PROM_TOKEN" \
            --data-urlencode 'query=rate(container_cpu_user_seconds_total{namespace="opendatahub",pod=~"echo-server.*"}[5m])' \
            "https://$PROM_ROUTE/api/v1/query" \
            | jq -r '.data.result[] | "\(.metric.pod) \(.metric.container) \(.value[1])"' >> "$METRICS_FILE" 2>&1 || echo "N/A" >> "$METRICS_FILE"

        # Collect echo-server Memory
        echo "## echo-server Memory (bytes):" >> "$METRICS_FILE"
        curl -k -s -H "Authorization: Bearer $PROM_TOKEN" \
            --data-urlencode 'query=container_memory_working_set_bytes{namespace="opendatahub",pod=~"echo-server.*"}' \
            "https://$PROM_ROUTE/api/v1/query" \
            | jq -r '.data.result[] | "\(.metric.pod) \(.metric.container) \(.value[1])"' >> "$METRICS_FILE" 2>&1 || echo "N/A" >> "$METRICS_FILE"
    else
        echo "Unable to access Prometheus - using kubectl top instead" >> "$METRICS_FILE"

        # Fallback to oc adm top
        echo "## oauth-proxy resources:" >> "$METRICS_FILE"
        oc adm top pod -n opendatahub --containers 2>/dev/null | grep oauth-proxy >> "$METRICS_FILE" || echo "N/A" >> "$METRICS_FILE"

        echo "## echo-server resources:" >> "$METRICS_FILE"
        oc adm top pod -n opendatahub --containers 2>/dev/null | grep echo-server >> "$METRICS_FILE" || echo "N/A" >> "$METRICS_FILE"
    fi

    echo "" >> "$METRICS_FILE"
}

# Run warmup
echo -e "${GREEN}Running warmup ($WARMUP_REQUESTS requests, $WARMUP_CONCURRENCY concurrency)...${NC}"
hey -n $WARMUP_REQUESTS -c $WARMUP_CONCURRENCY \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: text/html" \
    "$ROUTE_URL$ENDPOINT" > /dev/null 2>&1
echo -e "${GREEN}✓ Warmup complete${NC}"
echo ""

# Run test iterations
for i in $(seq 1 $ITERATIONS); do
    echo -e "${BLUE}=== Running iteration $i/$ITERATIONS ===${NC}"

    # Add iteration header to log
    echo "=== ITERATION $i ===" >> "$OUTPUT_FILE"
    echo "Started: $(date)" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"

    # Collect metrics before test
    collect_metrics $i "START"

    # Run hey and append to log file
    hey -n $TOTAL_REQUESTS -c $CONCURRENCY \
        -H "Authorization: Bearer $TOKEN" \
        -H "Accept: text/html" \
        "$ROUTE_URL$ENDPOINT" >> "$OUTPUT_FILE" 2>&1

    # Collect metrics after test
    collect_metrics $i "END"

    echo "" >> "$OUTPUT_FILE"
    echo "Completed: $(date)" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "--------------------------------------------------------------------------------" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"

    echo -e "${GREEN}✓ Iteration $i complete${NC}"

    # Sleep between iterations (except after the last one)
    if [ $i -lt $ITERATIONS ]; then
        echo "Sleeping 10 seconds before next iteration..."
        sleep 10
        echo ""
    fi
done

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Benchmark Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Results saved to: $OUTPUT_FILE"
echo ""

# Extract and display P95 latencies from all runs
echo -e "${BLUE}P95 Latency Summary:${NC}"
grep "95% in" "$OUTPUT_FILE" | nl

echo ""
echo -e "${BLUE}Quick Stats:${NC}"
echo -n "Average P95: "
grep "95% in" "$OUTPUT_FILE" | awk '{print $3}' | awk '{sum+=$1; count++} END {printf "%.4f secs\n", sum/count}'

echo ""
echo "Full results available in:"
echo "  - Benchmark: $OUTPUT_FILE"
echo "  - Metrics:   $METRICS_FILE"
