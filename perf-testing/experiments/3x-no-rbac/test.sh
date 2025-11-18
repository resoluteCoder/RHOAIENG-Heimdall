#!/bin/bash
# 3.x No RBAC Test - Gateway + kube-auth-proxy only (no kube-rbac-proxy)

set -e

ENDPOINT="https://data-science-gateway.apps.rosa.f3d4c3l4i5u4x1v.fcu6.p3.openshiftapps.com/echo-no-rbac"
TOKEN=$(oc whoami -t)

echo "Testing: 3x-no-rbac (Gateway + kube-auth-proxy, NO kube-rbac-proxy)"
echo "Endpoint: $ENDPOINT"
echo ""

hey -n 1000 -c 50 \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: text/html" \
    "${ENDPOINT}" | tee results.log
