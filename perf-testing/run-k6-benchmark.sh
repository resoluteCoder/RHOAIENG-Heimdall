#!/bin/bash

# K6 Load Test Wrapper Script
# Deploys k6 pod, runs load test with user-defined parameters,
# collects Prometheus metrics, and cleans up resources.

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default configuration
NAMESPACE="${NAMESPACE:-opendatahub}"
POD_NAME="${POD_NAME:-k6-benchmark}"
CONFIGMAP_NAME="k6-loadtest-script"
K6_POD_YAML="${K6_POD_YAML:-./k6-pod.yaml}"
OUTPUT_DIR="${OUTPUT_DIR:-./results}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RUN_DIR="${OUTPUT_DIR}/${TIMESTAMP}"
OUTPUT_FILE="${RUN_DIR}/k6-test.log"
METRICS_FILE="${RUN_DIR}/k6-metrics.log"
CLEANUP="${CLEANUP:-true}"

# Test parameters (can be overridden via environment variables)
# URL - The endpoint to test (REQUIRED)
# TOKEN - OAuth Bearer token (defaults to oc whoami -t)
RPS="${RPS:-100}"
DURATION="${DURATION:-1m}"
PREALLOC_VUS="${PREALLOC_VUS:-10}"
MAX_VUS="${MAX_VUS:-1000}"

# Print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

K6 Load Testing Wrapper Script

REQUIRED ENVIRONMENT VARIABLES:
  URL                 The endpoint to test (e.g., https://gateway.example.com/echo)

OPTIONAL ENVIRONMENT VARIABLES:
  TOKEN               OAuth Bearer token (default: auto-detect from oc)
  RPS                 Requests per second (default: 100)
  DURATION            Test duration (default: 1m)
  PREALLOC_VUS        Pre-allocated VUs (default: 10)
  MAX_VUS             Maximum VUs (default: 100)
  NAMESPACE           Kubernetes namespace (default: opendatahub)
  POD_NAME            K6 pod name (default: k6-benchmark)
  K6_POD_YAML         Path to k6-pod.yaml (default: ./k6-pod.yaml)
  OUTPUT_DIR          Base output directory (default: ./results)
                      Each run creates a timestamped subdirectory
  CLEANUP             Cleanup resources after test (default: true)

NOTE: Metrics are collected as aggregated values over the entire test window.

EXAMPLES:
  # Basic test with auto-detected token
  URL=https://gateway.example.com/echo ./run-k6-benchmark.sh

  # Custom parameters
  URL=https://gateway.example.com/echo RPS=200 DURATION=5m MAX_VUS=300 ./run-k6-benchmark.sh

  # With custom token and no cleanup
  URL=https://gateway.example.com/echo TOKEN=mytoken CLEANUP=false ./run-k6-benchmark.sh

  # Test RHOAI gateway
  export GATEWAY_URL=\$(oc get gateway -n openshift-ingress data-science-gateway -o jsonpath='{.spec.listeners[0].hostname}')
  URL=https://\${GATEWAY_URL}/echo ./run-k6-benchmark.sh

EOF
    exit 1
}

# Check if help is requested
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    usage
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}K6 Load Test Benchmark${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Validate required parameters
if [ -z "$URL" ]; then
    echo -e "${RED}Error: URL environment variable is required${NC}"
    echo ""
    usage
fi

# Verify required commands
for cmd in kubectl oc; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}Error: '$cmd' command not found. Please install it first.${NC}"
        exit 1
    fi
done

# Check for jq (optional but recommended for better metrics parsing)
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Note: 'jq' not found. Metrics parsing will use fallback method.${NC}"
    echo -e "${YELLOW}For better results, install jq: https://stedolan.github.io/jq/${NC}"
    echo ""
fi

# Get token from oc if not set
if [ -z "$TOKEN" ]; then
    echo "Getting auth token from oc..."
    TOKEN=$(oc whoami -t 2>/dev/null)
    if [ -z "$TOKEN" ]; then
        echo -e "${YELLOW}Warning: No auth token found. Test will run without authentication.${NC}"
        echo -e "${YELLOW}Set TOKEN env var or login with 'oc login' for authenticated tests.${NC}"
    else
        echo -e "${GREEN}✓ Got token from oc${NC}"
    fi
fi

echo ""
echo "Configuration:"
echo "  URL:               $URL"
echo "  Namespace:         $NAMESPACE"
echo "  RPS:               $RPS"
echo "  Duration:          $DURATION"
echo "  Pre-allocated VUs: $PREALLOC_VUS"
echo "  Max VUs:           $MAX_VUS"
echo "  K6 Pod YAML:       $K6_POD_YAML"
echo "  Run Directory:     $RUN_DIR"
echo "  Cleanup:           $CLEANUP"
echo ""

# Create run-specific directory
mkdir -p "$RUN_DIR"

# Test endpoint connectivity (if token is available)
if [ -n "$TOKEN" ]; then
    echo -e "${GREEN}Testing endpoint connectivity...${NC}"
    HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Accept: text/html" \
        "$URL" 2>/dev/null || echo "000")

    if [ "$HTTP_CODE" == "200" ]; then
        echo -e "${GREEN}✓ Endpoint is accessible (HTTP $HTTP_CODE)${NC}"
    else
        echo -e "${YELLOW}Warning: Endpoint returned HTTP $HTTP_CODE (may be expected)${NC}"
    fi
    echo ""
fi

# Function to cleanup resources
cleanup_resources() {
    if [ "$CLEANUP" == "true" ]; then
        echo -e "${YELLOW}Cleaning up resources...${NC}"
        kubectl delete pod "$POD_NAME" -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
        kubectl delete configmap "$CONFIGMAP_NAME" -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
        echo -e "${GREEN}✓ Cleanup complete${NC}"
    else
        echo -e "${YELLOW}Skipping cleanup (CLEANUP=false)${NC}"
        echo "To manually cleanup, run:"
        echo "  kubectl delete pod $POD_NAME -n $NAMESPACE"
        echo "  kubectl delete configmap $CONFIGMAP_NAME -n $NAMESPACE"
    fi
}

# Trap to ensure cleanup on exit
trap cleanup_resources EXIT

# Check if pod or configmap already exists and clean up
if kubectl get pod "$POD_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo -e "${YELLOW}Found existing pod, cleaning up...${NC}"
    kubectl delete pod "$POD_NAME" -n "$NAMESPACE" --wait=true 2>/dev/null || true
fi

if kubectl get configmap "$CONFIGMAP_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo -e "${YELLOW}Found existing configmap, cleaning up...${NC}"
    kubectl delete configmap "$CONFIGMAP_NAME" -n "$NAMESPACE" 2>/dev/null || true
fi

# Deploy k6 pod
echo -e "${GREEN}Deploying k6 pod...${NC}"
if [ ! -f "$K6_POD_YAML" ]; then
    echo -e "${RED}Error: K6 pod YAML file not found: $K6_POD_YAML${NC}"
    exit 1
fi

kubectl apply -f "$K6_POD_YAML" -n "$NAMESPACE"
echo -e "${GREEN}✓ Pod manifest applied${NC}"

# Wait for pod to be ready
echo -e "${GREEN}Waiting for pod to be ready...${NC}"
kubectl wait --for=condition=ready pod/"$POD_NAME" -n "$NAMESPACE" --timeout=60s
echo -e "${GREEN}✓ Pod is ready${NC}"
echo ""

# Initialize output files
cat > "$OUTPUT_FILE" <<EOF
K6 Load Test Results
Generated: $(date)
Configuration:
  URL: $URL
  RPS: $RPS
  Duration: $DURATION
  Pre-allocated VUs: $PREALLOC_VUS
  Max VUs: $MAX_VUS
  Namespace: $NAMESPACE

================================================================================

EOF

# Path to metrics collection script
METRICS_SCRIPT="$(dirname "$0")/collect-prometheus-metrics.sh"

# Record test start time
TEST_START_TIME=$(date +%s)

# Run k6 test
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Running K6 Load Test${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

K6_CMD="k6 run --quiet"
K6_CMD="$K6_CMD -e URL=$URL"
if [ -n "$TOKEN" ]; then
    K6_CMD="$K6_CMD -e TOKEN=$TOKEN"
fi
K6_CMD="$K6_CMD -e RPS=$RPS"
K6_CMD="$K6_CMD -e DURATION=$DURATION"
K6_CMD="$K6_CMD -e PREALLOC_VUS=$PREALLOC_VUS"
K6_CMD="$K6_CMD -e MAX_VUS=$MAX_VUS"
K6_CMD="$K6_CMD /scripts/loadtest-rps.js"

echo "Executing: $K6_CMD"
echo ""

# Run the test and capture output
set +e
kubectl exec "$POD_NAME" -n "$NAMESPACE" -- sh -c "$K6_CMD" 2>&1 | tee -a "$OUTPUT_FILE"
TEST_EXIT_CODE=$?
set -e

# Calculate test duration
TEST_END_TIME=$(date +%s)
TEST_DURATION_SECONDS=$((TEST_END_TIME - TEST_START_TIME))

echo ""
if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✓ K6 test completed successfully${NC}"
else
    echo -e "${YELLOW}⚠ K6 test completed with exit code: $TEST_EXIT_CODE${NC}"
fi
echo ""

# Collect aggregated metrics over the test window
echo -e "${GREEN}Collecting aggregated metrics over test window...${NC}"
if [ -x "$METRICS_SCRIPT" ]; then
    "$METRICS_SCRIPT" --duration "$TEST_DURATION_SECONDS" --start-time "$TEST_START_TIME" --output "$METRICS_FILE"
else
    echo -e "${YELLOW}Warning: Metrics collection script not found or not executable: $METRICS_SCRIPT${NC}"
    echo "Metrics collection skipped" >> "$METRICS_FILE"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Test Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Results saved to: $RUN_DIR"
echo "  Test output:  k6-test.log"
echo "  Metrics:      k6-metrics.log"
echo ""

# Display cleanup info
echo ""
if [ "$CLEANUP" == "true" ]; then
    echo -e "${GREEN}Resources will be cleaned up on exit${NC}"
else
    echo -e "${YELLOW}Resources left running (CLEANUP=false)${NC}"
    echo "Pod: $POD_NAME (namespace: $NAMESPACE)"
fi

echo ""
echo -e "${GREEN}Done!${NC}"

