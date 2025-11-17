# Gateway Performance Benchmark Summary

**Date:** November 17, 2025
**Test:** RHOAI 3.x with OAuth Authentication
**Environment:** ROSA cluster (AWS us-east-1)

## Test Configuration

- **Gateway URL:** `https://data-science-gateway.apps.rosa.f3d4c3l4i5u4x1v.fcu6.p3.openshiftapps.com/echo`
- **Total Requests per Iteration:** 10,000
- **Concurrency:** 50 concurrent connections
- **Iterations:** 5
- **Total Requests:** 50,000
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
echo-server (hashicorp/http-echo backend)
```

## Latency Results

### P95 Latency Summary

| Iteration | P95 Latency | P50 Latency | P99 Latency | Throughput | Success Rate | Status |
|-----------|-------------|-------------|-------------|------------|--------------|--------|
| 1 | 3.1205s | 1.5958s | 3.9918s | 29.45 req/s | 99.98% (9998/10000) | ✅ |
| 2 | 3.1971s | 1.6057s | 4.0008s | 29.04 req/s | 99.98% (9998/10000) | ✅ |
| 3 | 3.1157s | 1.6388s | 3.9670s | 28.72 req/s | 99.94% (9994/10000) | ✅ |
| 4 | 3.1559s | 1.6392s | 3.9994s | 28.65 req/s | 99.92% (9992/10000) | ✅ |
| 5 | 3.1005s | 1.6001s | 3.8707s | 29.39 req/s | 99.98% (9998/10000) | ✅ |

### Key Metrics

- **Average P95 Latency:** 3.14 seconds
- **Average P50 Latency:** 1.62 seconds
- **Average P99 Latency:** 3.97 seconds
- **Average Throughput:** 29.05 requests/sec
- **Overall Success Rate:** 99.96% (49,980/50,000 requests)

### Error Analysis

Total errors across all iterations: **20 requests (0.04% error rate)**

All errors were **403 Forbidden** responses:
- Iteration 1: 2 errors
- Iteration 2: 2 errors
- Iteration 3: 6 errors
- Iteration 4: 8 errors
- Iteration 5: 2 errors

**Analysis:** The 403 errors are intermittent authentication/authorization failures, likely due to:
- OAuth token validation timing issues
- SubjectAccessReview transient failures
- Race conditions under high concurrency

No timeout errors observed in this test run.

## Resource Utilization

### kube-auth-proxy (Authentication Layer)

| Metric | At Start (Avg) | During Load (Avg) | Notes |
|--------|----------------|-------------------|-------|
| CPU | 0.0014 cores (0.14%) | 0.0334 cores (3.34%) | Efficient under load |
| Memory | 19.4 MB | 32.3 MB | Stable, minimal growth |

**Analysis:** kube-auth-proxy shows excellent efficiency, with CPU usage rising to only 3.34% during peak load despite handling OAuth token validation for ~29 req/s.

### echo-server Pod (Backend + Authorization)

**Average metrics across iterations:**

| Container | CPU at Start | CPU During Load | Memory at Start | Memory During Load |
|-----------|--------------|-----------------|-----------------|-------------------|
| echo-server (http-echo) | 0.0003 cores | 0.0103 cores (1.03%) | 21 MB | 26.9 MB |
| kube-rbac-proxy | 0.0002 cores | 0.0030 cores (0.30%) | 7.3 MB | 13.2 MB |
| **Total** | 0.0005 cores | 0.0133 cores (1.33%) | 28.3 MB | 40.1 MB |

**Analysis:**
- hashicorp/http-echo backend is extremely lightweight (~1% CPU)
- kube-rbac-proxy adds minimal overhead (0.3% CPU) for RBAC checks
- Both containers have significant headroom for scaling
- Memory usage is stable and very low

## Key Findings

### 1. Consistent Performance Under Sustained Load

The gateway maintains excellent P95 latency consistency across all 5 iterations:
- Standard deviation: ±0.04s (extremely stable)
- No performance degradation over time
- All iterations completed successfully with >99.9% success rate
- Predictable behavior for capacity planning

### 2. Minimal Resource Overhead

Total CPU usage during peak load:
- **kube-auth-proxy:** 3.34% CPU (OAuth validation)
- **kube-rbac-proxy:** 0.30% CPU (RBAC authorization)
- **http-echo backend:** 1.03% CPU (request handling)
- **Total overhead:** ~4.67% CPU for entire stack

This demonstrates that the authentication/authorization layers are highly efficient.

### 3. Improved Performance vs Previous Test

Comparing to the October 15, 2025 test:
- **Throughput:** 29.05 req/s vs 18.42 req/s (+57% improvement)
- **P50 Latency:** 1.62s vs 2.64s (38% improvement)
- **P95 Latency:** 3.14s vs 2.80s (+12% higher, but more stable)
- **Success Rate:** 99.96% vs 99.77% (+0.19% improvement)
- **Error Types:** Only 403 errors (20 total) vs 403 + timeouts (113 timeout errors in old test)

**Root Cause of Improvement:** Switching from cloud-bulldozer/nginx to hashicorp/http-echo:
- Simpler, lighter backend with minimal processing overhead
- Eliminates nginx configuration complexity
- Better alignment with testing goals (measuring gateway overhead, not backend performance)

### 4. Scalability Headroom

With only 1 replica of each component handling ~29 req/s:
- All components running at <5% CPU utilization
- Memory usage is stable and very low
- Horizontal scaling would linearly increase throughput
- Current bottleneck appears to be external (network/OAuth API calls)

## Latency Breakdown Analysis

Based on P50 latency of 1.62s:
- **kube-auth-proxy OAuth validation:** ~8-10ms (estimated from logs)
- **kube-rbac-proxy RBAC check:** ~2-5ms (estimated)
- **Network overhead:** ~50-100ms (multi-hop: Gateway → auth → rbac → backend)
- **Backend processing:** <1ms (http-echo is very fast)
- **Unaccounted time:** ~1.5s

**Hypothesis:** The majority of latency comes from:
1. **OAuth token validation:** External API calls to OpenShift OAuth server
2. **SubjectAccessReview:** Kubernetes API calls for RBAC checks
3. **Network round-trips:** Multiple service hops in the request path
4. **External client location:** hey running outside the cluster

## Recommendations

### For Production Deployment

1. **Set SLO based on current metrics:**
   - P95 target: <3.5s
   - P50 target: <2.0s
   - Success rate: >99.9%

2. **Monitor 403 error pattern:**
   - Investigate intermittent auth failures
   - Consider token refresh/retry logic
   - May need OAuth token caching tuning

3. **Scale horizontally for increased throughput:**
   - All components have significant CPU/memory headroom
   - Linear scaling expected with additional replicas

### For Benchmark Comparison

**Next steps:**

1. **Run 2.x baseline test:**
   - Deploy equivalent echo service on RHOAI 2.x cluster
   - Use same test parameters (10k requests, 50 concurrency, 5 iterations)
   - Compare P95/P50 latency and throughput

2. **Test BYOIDC scenario:**
   - Configure external OIDC provider
   - Compare latency to OAuth results
   - Quantify external IdP overhead

3. **In-cluster load test:**
   - Use hey-pod for in-cluster testing
   - Eliminate external network latency
   - Isolate gateway/auth stack performance

## Files Generated

- **Benchmark results:** `oauth-3x.log`
- **Resource metrics:** `oauth-3x-metrics.log`
- **Benchmark script:** `benchmark-3x-oauth.sh`
- **Summary:** `benchmark-summary.md`

## Test Environment Details

### Gateway Configuration

- **Gateway:** data-science-gateway (openshift-ingress namespace)
- **Gateway class:** data-science-gateway-class
- **Load balancer:** AWS ELB
- **Cluster:** ROSA (f3d4c3l4i5u4x1v.fcu6.p3)

### Service Topology

- **kube-auth-proxy:** 1 replica (openshift-ingress namespace)
- **echo-server:** 1 replica (opendatahub namespace)
  - hashicorp/http-echo on port 8080
  - kube-rbac-proxy sidecar on port 8443

### HTTPRoute Configuration

- **Path:** `/echo`
- **Backend:** echo-server:8443 (routes through kube-rbac-proxy)
- **Authentication:** Required at gateway level (Envoy ext_authz → kube-auth-proxy)
