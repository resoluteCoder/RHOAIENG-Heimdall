#!/bin/bash

set -e

$TOKEN=$(oc whoami -t)
AUTH_HEADER="Authorization: Bearer $TOKEN"

echo "=== Testing Latency vs Concurrency ==="
echo ""

for CONCURRENCY in 1 5 10 20 50 100; do
  echo "--- Concurrency: $CONCURRENCY ---"
  hey -n 1000 -c $CONCURRENCY -H "$AUTH_HEADER" -H "Accept: text/html" "$GATEWAY_URL" 2>&1 | \
    grep -E "Requests/sec|Average|50%|95%|99%"
  echo ""
done

