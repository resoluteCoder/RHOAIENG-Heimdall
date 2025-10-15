# Gateway Performance Benchmark Summary

**Date:** October 15, 2025
**Test:** RHOAI 3.x with OAuth Authentication
**Environment:** ROSA cluster (AWS us-east-1)

## Test Configuration

- **Gateway URL:** `https://data-science-gateway.apps.rosa.b9q3t4p8k3y8k9a.vzrg.p3.openshiftapps.com/echo`
- **Total Requests per Iteration:** 10,000
- **Concurrency:** 50 concurrent connections
- **Iterations:** 5
- **Tool:** hey (HTTP load testing)
- **Authentication:** OpenShift OAuth (Bearer token)

## Architecture Tested

```
Client (hey)
    ↓
Gateway (Envoy)
    ↓
kube-auth-proxy (OAuth token validation via ext_authz)
    ↓
kube-rbac-proxy (RBAC authorization via SubjectAccessReview)
    ↓
echo-server (backend service)
```

## Latency Results

### P95 Latency Summary

| Iteration | P95 Latency | P50 Latency | P99 Latency | Throughput | Success Rate | Status |
|-----------|-------------|-------------|-------------|------------|--------------|--------|
| 1 | 2.7535s | 2.6060s | 2.8299s | 19.08 req/s | 100% (10000/10000) | ✅ |
| 2 | 2.8263s | 2.6422s | 3.2003s | 18.77 req/s | 100% (10000/10000) | ✅ |
| 3 | 2.8098s | 2.6427s | 2.9317s | 18.83 req/s | 100% (10000/10000) | ✅ |
| 4 | 2.8191s | 2.6465s | 3.4856s | 18.74 req/s | 100% (10000/10000) | ✅ |
| 5 | 2.8113s | 2.6380s | 12.5513s | 16.66 req/s | 98.9% (9887/10000) | ⚠️ |

### Key Metrics

- **Average P95 Latency:** 2.80 seconds
- **Average P50 Latency:** 2.64 seconds
- **Average Throughput:** 18.42 requests/sec
- **Overall Success Rate:** 99.77% (49,887/50,000 requests)

### Iteration 5 Anomaly

Iteration 5 experienced performance degradation:
- **113 timeout errors:** "context deadline exceeded (Client.Timeout exceeded while awaiting headers)"
- **P99 latency spike:** 12.55 seconds (vs ~3s in other iterations)
- **Slowest request:** 17.76 seconds
- **Root cause:** Likely intermittent cluster resource contention or network issues

## Resource Utilization

### kube-auth-proxy (Authentication Layer)

| Metric | At Start | During Load | Notes |
|--------|----------|-------------|-------|
| CPU | 0.0004 cores (0.04%) | 0.007 cores (0.7%) | Very efficient |
| Memory | ~21 MB | ~22 MB | Stable, no leaks |

**Analysis:** kube-auth-proxy shows excellent efficiency with minimal CPU overhead despite handling OAuth token validation for all requests.

### echo-server Pod (Backend + Authorization)

| Container | CPU at Start | CPU During Load | Memory |
|-----------|--------------|-----------------|--------|
| echo-server | 0.043 cores | 0.73 cores (73%) | ~40 MB |
| kube-rbac-proxy | 0.001 cores | 0.011 cores (1%) | ~47-50 MB |
| **Total** | 0.044 cores | 0.74 cores | ~88-91 MB |

**Analysis:**
- echo-server container is doing most of the work (73% CPU)
- kube-rbac-proxy adds minimal overhead despite performing RBAC checks on every request
- No resource bottlenecks - all components have significant headroom

## Key Findings

### 1. Consistent Latency Under Load

The gateway architecture maintains consistent P95 latency (~2.8s) across iterations, indicating:
- Stable performance under sustained load
- No significant degradation over time
- Predictable response times for capacity planning

### 2. Low Resource Overhead

- **kube-auth-proxy:** Only 0.7% CPU during peak load
- **kube-rbac-proxy:** Only 1% CPU for authorization
- **echo-server:** 73% CPU (actual backend processing)

This suggests the authentication/authorization layers are highly efficient and not resource-constrained.

### 3. Latency Breakdown

Based on logs and metrics:
- **kube-auth-proxy processing:** ~8ms (observed in logs)
- **Total end-to-end latency:** ~2.8s (P95)
- **Unaccounted time:** ~2.79s

The majority of latency comes from:
- Network hops between components
- OAuth token validation API calls
- SubjectAccessReview API calls to Kubernetes
- Backend processing time

### 4. Scalability Headroom

With only 1 replica of each component handling 19 req/s:
- CPU utilization is low across all components
- Horizontal scaling would significantly increase throughput
- No memory pressure or resource bottlenecks observed

## Comparison to Initial Quick Test

**Initial quick test (1,000 requests):**
- P95: 599ms
- Throughput: 18.83 req/s

**Full benchmark (10,000 requests per iteration):**
- P95: 2,800ms
- Throughput: 18.42 req/s

**Difference:** 4.7x increase in latency under sustained load

**Possible explanations:**
- OAuth token validation caching in initial test
- Network condition variations
- Cluster resource contention during sustained load
- Cold start effects in quick test

## Recommendations

### For Production Deployment

1. **Set SLO based on P95:** Plan for ~3 second response times with current architecture
2. **Scale horizontally:** All components have CPU headroom - scaling replicas will increase throughput
3. **Monitor iteration 5 pattern:** Investigate if timeout pattern repeats (may indicate cluster-level issue)
4. **Consider caching:** OAuth token validation caching could reduce latency if not already enabled

### For Benchmark Comparison

**Next steps to complete the epic goals:**

1. **Run 2.x baseline test:**
   - Deploy equivalent echo service on RHOAI 2.x cluster
   - Use same test parameters (10k requests, 50 concurrency)
   - Compare P95 latency to determine 3.x overhead

2. **Test BYOIDC scenario:**
   - Configure external OIDC provider (Keycloak, Auth0, etc.)
   - Run same benchmark with external IdP
   - Compare to OAuth results to quantify external IdP overhead

3. **Enable oauth2-proxy metrics:**
   - Configure separate metrics port without authentication
   - Update ServiceMonitor to scrape application metrics
   - Gain visibility into auth request rates and failure modes

## Files Generated

- **Benchmark results:** `oauth-3x.log`
- **Resource metrics:** `oauth-3x-metrics.log`
- **Test script:** `dev/benchmark-3x-oauth.sh`
- **ServiceMonitor:** `dev/kube-auth-proxy-servicemonitor.yaml`

## Appendix: Test Environment Details

### Gateway Configuration

- **Gateway:** data-science-gateway (openshift-ingress namespace)
- **Gateway class:** data-science-gateway-class
- **Load balancer:** AWS ELB (a35b3cee921a94aef88e33fff4b9ade0-1496440026.us-east-1.elb.amazonaws.com)

### Service Topology

- **kube-auth-proxy:** 1 replica (openshift-ingress namespace)
- **echo-server:** 1 replica (opendatahub namespace)
  - Port 8443: Authenticated endpoint (via kube-rbac-proxy sidecar)
  - Port 8080: Direct endpoint (still goes through kube-auth-proxy at gateway)

### HTTPRoute Configuration

- **Path:** `/echo`
- **Backend:** echo-server:8443 (includes kube-rbac-proxy)
- **Authentication:** Required at gateway level (Envoy ext_authz → kube-auth-proxy)
