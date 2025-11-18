#!/bin/bash
# Baseline 3.x Test - Gateway + kube-auth-proxy + kube-rbac-proxy

set -e

ENDPOINT="https://data-science-gateway.apps.rosa.f3d4c3l4i5u4x1v.fcu6.p3.openshiftapps.com/echo"
TOKEN=$(oc whoami -t)

echo "Testing: baseline-3x (Gateway + kube-auth-proxy + kube-rbac-proxy)"
echo "Endpoint: $ENDPOINT"
echo ""

hey -n 1000 -c 50 \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: text/html" \
    "${ENDPOINT}" | tee results.log
