This repo contains scripts for RHOAI 3.0 Gateway performance & scale testing. RHOAI 3.0 introduces significant changes with regard to traffic ingestion: in particular, the HAProxy and oauth-proxy that served as the main Ingress path in RHOAI 2.x, had been replaced with an Istio Gateway that communicates with a kube-auth-proxy to query IDP via an envoy filter and kube-rbac-proxy running as a sidecar on the target pod to validate token and RBAC via SubjectAccessReview API.
The main goal is to evaluate the RHOAI 3.0 Gateway and compare its performance to RHOAI 2.x ingress, particularly in terms of:
- Throughput
- Latency overhead
- Key components resource utilization
