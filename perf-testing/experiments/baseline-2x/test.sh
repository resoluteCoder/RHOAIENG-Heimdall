#!/bin/bash
# Baseline 2.x Test - Route + oauth-proxy

set -e

ENDPOINT="https://echo-server-2x-opendatahub.apps.rosa.f3d4c3l4i5u4x1v.fcu6.p3.openshiftapps.com"
TOKEN=$(oc whoami -t)

echo "Testing: baseline-2x (Route + oauth-proxy)"
echo "Endpoint: $ENDPOINT"
echo ""

hey -n 1000 -c 50 \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: text/html" \
    "${ENDPOINT}" | tee results.log
