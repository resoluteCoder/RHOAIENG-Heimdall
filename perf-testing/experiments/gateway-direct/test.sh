#!/bin/bash
# Gateway Direct Test - No authentication, pure Gateway/Envoy overhead

set -e

ENDPOINT="https://gateway-no-auth.apps.rosa.f3d4c3l4i5u4x1v.fcu6.p3.openshiftapps.com"
GATEWAY_IP="34.225.221.89"  # From: oc get gateway gateway-no-auth -n openshift-ingress

echo "Testing: gateway-direct (Gateway only, NO kube-auth-proxy)"
echo "Endpoint: $ENDPOINT"
echo "Note: Using separate GatewayClass (gateway-no-auth-class) without kube-auth-proxy"
echo ""

# Add temporary /etc/hosts entry for DNS resolution
echo "Adding temporary hosts entry: $GATEWAY_IP gateway-no-auth.apps.rosa.f3d4c3l4i5u4x1v.fcu6.p3.openshiftapps.com"
echo "$GATEWAY_IP gateway-no-auth.apps.rosa.f3d4c3l4i5u4x1v.fcu6.p3.openshiftapps.com" | sudo tee -a /etc/hosts > /dev/null

# Run the test
hey -n 1000 -c 50 \
    -H "Accept: text/html" \
    "${ENDPOINT}" | tee results.log

# Clean up /etc/hosts entry
echo "Cleaning up hosts entry..."
sudo sed -i '/gateway-no-auth.apps.rosa.f3d4c3l4i5u4x1v.fcu6.p3.openshiftapps.com/d' /etc/hosts
