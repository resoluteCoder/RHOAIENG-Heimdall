# Root Cause Analysis: RHOAI 3.x Authentication Performance

**Date:** November 18, 2025
**Author:** Performance Testing Team
**Issue:** Historical RHOAI 3.x performance testing showed 34x slower performance compared to 2.x

---

## Executive Summary

Historical performance testing revealed RHOAI 3.x (Gateway + kube-auth-proxy architecture) performed **34x slower** than expected, with P50 latency of 1,588ms. Investigation identified **two root causes** in the previous test configurations:

1. **PRIMARY: CPU resource limits** - kube-auth-proxy was restricted to 50 millicores, causing severe CPU throttling
2. **SECONDARY: Non-lightweight backend** - Previous tests used a custom echo server consuming excessive CPU

After correcting both issues, current benchmarks (November 18, 2025) show RHOAI 3.x delivers **acceptable performance** with P50 latency of 70ms compared to 2.x at 46ms (1.5x difference).

---

## Problem Statement

### Previous Test Results (October-November 2025)

**Historical Observed Behavior:**
- RHOAI 3.x P50 latency: 1,588ms - 2,640ms
- RHOAI 2.x P50 latency: 47ms - 50ms
- **32-56x performance degradation**
- Throughput: 18-29 req/s (3.x) vs 914-931 req/s (2.x)

**Test Configuration Issues:**
- kube-auth-proxy had 50m CPU limit (severe throttling)
- Earlier tests used custom echo backend (73% CPU usage)
- These issues masked actual 3.x performance

**Architecture:**

```
2.x: Client → Route (HAProxy) → oauth-proxy → Backend
3.x: Client → Gateway (Envoy) → kube-auth-proxy (ext_authz) → kube-rbac-proxy → Backend
```

---

## Investigation Process

### Discovery of CPU Throttling Issue

Through systematic testing, we identified that kube-auth-proxy had inappropriate resource limits:

```yaml
resources:
  limits:
    cpu: 50m        # ⚠️ ONLY 0.05 CPU cores!
    memory: 64Mi
  requests:
    cpu: 10m
    memory: 32Mi
```

**Analysis:**
- 50 millicores (0.05 cores) is extremely restrictive
- OAuth token validation is CPU-intensive (JWT validation, signature verification)
- Under 50 concurrent requests, severe CPU throttling occurred
- Caused requests to queue, adding ~1,500ms latency per request

**Action Taken:**
```bash
oc patch deployment kube-auth-proxy -n openshift-ingress --type json \
  -p '[{"op": "remove", "path": "/spec/template/spec/containers/0/resources/limits/cpu"}]'
```

### Discovery of Backend Inefficiency

Earlier tests (October 2025) used a custom echo server that was CPU-intensive:
- Custom echo server: 73% CPU during load
- hashicorp/http-echo: 1.03% CPU during load
- **98.6% reduction** in backend CPU after switching

This backend inefficiency masked the true authentication overhead and made it difficult to isolate performance issues.

---

## Root Causes

### Root Cause #1: CPU Resource Limits (PRIMARY)

**Component:** kube-auth-proxy deployment in openshift-ingress namespace

**Issue:** CPU limit set to 50 millicores (0.05 cores)

**Impact:**
- Severe CPU throttling under concurrent load
- OAuth validation requires cryptographic operations
- Added ~1,500ms latency per request due to throttling

**Why This Happened:**
- Default resource limits set conservatively
- Not validated under realistic concurrent load
- OAuth validation CPU requirements underestimated

**Evidence:**
- Actual peak CPU usage: 0.1743 cores (17.43%)
- Previous limit: 0.05 cores (50m)
- **Peak usage is 3.5x higher than limit** - confirming severe throttling

### Root Cause #2: Non-Lightweight Backend (SECONDARY)

**Component:** Backend service in historical tests

**Issue:** Custom echo server was CPU-intensive

**Impact:**
- Backend consumed 73% CPU, becoming a bottleneck
- Masked true authentication layer performance
- Made it difficult to isolate root causes

**Resolution:**
- Switched to hashicorp/http-echo (lightweight Go binary)
- CPU usage dropped from 73% to 1.03% (98.6% reduction)
- Allows accurate measurement of authentication overhead

---

## Current Performance Status (November 18, 2025)

### Corrected Test Configuration

**Changes Made:**
- ✅ Removed 50m CPU limit from kube-auth-proxy
- ✅ Using hashicorp/http-echo backend for both 2.x and 3.x
- ✅ Same cluster, same test parameters, same day (fair comparison)

**Test Parameters:**
- 10,000 requests per iteration
- 5 iterations (50,000 total requests)
- 50 concurrent connections
- hashicorp/http-echo backend
- OpenShift OAuth Bearer token authentication
- ROSA cluster (f3d4c3l4i5u4x1v.fcu6.p3)

### Performance Results

| Architecture | P50 | P95 | P99 | Throughput | Success Rate |
|--------------|-----|-----|-----|------------|--------------|
| **2.x** (Route + oauth-proxy) | 46ms | 55ms | 66ms | 1,032 req/s | 100% |
| **3.x** (Gateway + kube-auth-proxy) | 70ms | 110ms | 138ms | 668 req/s | 100% |

**Performance Comparison:**

| Metric | 2.x | 3.x | Difference |
|--------|-----|-----|------------|
| **P50 Latency** | 46ms | 70ms | **+24ms (1.5x)** |
| **P95 Latency** | 55ms | 110ms | **+55ms (2.0x)** |
| **P99 Latency** | 66ms | 138ms | **+72ms (2.1x)** |
| **Throughput** | 1,032 req/s | 668 req/s | **1.5x lower** |
| **Success Rate** | 100% | 100% | **Equal** |

### Performance Analysis

The remaining 1.5-2.0x performance difference is due to **architectural differences**, not defects:

1. **Additional Authentication Layer** (~10-15ms)
   - kube-rbac-proxy performs SubjectAccessReview calls
   - Adds RBAC authorization on top of OAuth authentication

2. **ext_authz Protocol Overhead** (~10-15ms)
   - Gateway calls kube-auth-proxy via Envoy ext_authz
   - Additional network hop and gRPC protocol overhead

3. **Additional Network Hop** (~10-15ms)
   - 3.x: Gateway → kube-auth-proxy → kube-rbac-proxy → backend (3 hops)
   - 2.x: Route → oauth-proxy → backend (2 hops)

4. **Gateway API vs Route** (~5-10ms)
   - Envoy Gateway vs HAProxy performance characteristics

**Total architectural overhead: ~35-55ms additional latency**

**Assessment:** This overhead is **acceptable** for the benefits of:
- Enhanced security (RBAC authorization)
- Gateway API features (routing, observability)
- Centralized authentication

---

## Performance Improvement Summary

### Before Fixes (Historical Tests)

**With 50m CPU limit + Custom echo backend:**
- P50 Latency: 1,588ms - 2,640ms
- Throughput: 18-29 req/s
- **32-56x slower than 2.x**

### After Fixes (November 18, 2025)

**No CPU limit + hashicorp/http-echo:**
- P50 Latency: 70ms
- Throughput: 668 req/s
- **1.5x slower than 2.x (acceptable architectural overhead)**

**Improvement from fixing CPU limits:**
- **95.7% faster P50** (1,620ms → 70ms)
- **23x higher throughput** (29 → 668 req/s)

**Improvement from fixing backend:**
- **98.6% reduction in backend CPU** (73% → 1.03%)
- Better isolation of authentication overhead

---

## Resource Utilization (Current)

### kube-auth-proxy CPU Usage

| State | CPU Usage | Notes |
|-------|-----------|-------|
| Idle | 0.00009 cores (0.009%) | Minimal baseline |
| Peak Load | 0.1743 cores (17.43%) | Handling 668 req/s |
| Previous Limit | 0.05 cores (50m) | **Would throttle at 28% of peak needs** |

### Backend Pod Resources

**2.x (Route + oauth-proxy):**
- echo-server: 0.82% CPU
- oauth-proxy: 3.13% CPU
- Total: 3.95% CPU, 57 MB memory

**3.x (Gateway + kube-auth-proxy + kube-rbac-proxy):**
- echo-server: 1.11% CPU
- kube-rbac-proxy: 4.12% CPU
- kube-auth-proxy: 17.43% CPU (separate pod)
- Total: ~22% CPU, 87 MB memory

Both architectures have significant headroom for scaling.

---

## Lessons Learned

### What Went Right

1. **Systematic investigation** - Component isolation helped identify CPU throttling
2. **Lightweight test backend** - hashicorp/http-echo provided accurate measurements
3. **Resource monitoring** - CPU metrics revealed the throttling issue
4. **Full benchmark validation** - 50,000 request tests confirmed the fix

### What Could Be Improved

1. **Resource limit validation** - Should test limits under realistic concurrent load before deployment
2. **Performance testing earlier** - Should occur during architecture design phase
3. **Documentation** - Resource limit recommendations should be clearly documented
4. **Monitoring/alerting** - CPU throttling should trigger alerts

---

## Recommendations

### Immediate Actions (Completed)

- ✅ Remove 50m CPU limit on kube-auth-proxy
- ✅ Use lightweight backend (hashicorp/http-echo) for testing
- ✅ Validate with full benchmark (50,000 requests)
- ✅ Document findings

### Production Deployment

1. **Resource Limits for kube-auth-proxy:**
   - Measured peak: 0.1743 cores (17.43%)
   - Recommended: `requests: 100m, limits: 500m`
   - **DO NOT use 50m limit** - causes severe throttling
   - Monitor CPU usage and adjust based on actual production load

2. **SLA Targets:**
   - **2.x:** P95 < 100ms, P50 < 75ms, 1,000+ req/s per replica
   - **3.x:** P95 < 200ms, P50 < 100ms, 600+ req/s per replica

3. **Capacity Planning:**
   - 3.x requires ~1.5x more replicas for same throughput as 2.x
   - Factor this into infrastructure planning

### Monitoring

1. **Track key metrics:**
   - kube-auth-proxy CPU usage (alert if sustained >50%)
   - P95/P99 latency for gateway endpoints
   - Success rate (should maintain 100%)

2. **Performance regression testing:**
   - Establish baseline benchmarks for each release
   - Automated load testing in CI/CD

---

## Conclusion

The historical 32-56x performance degradation in RHOAI 3.x was caused by **test configuration issues**, not architectural problems:

1. **50m CPU limit** on kube-auth-proxy caused severe throttling
2. **Non-lightweight backend** masked true authentication performance

After correcting both issues, **RHOAI 3.x delivers acceptable performance:**

- **1.5x slower P50 latency** (70ms vs 46ms) - reasonable architectural overhead
- **2.0x slower P95 latency** (110ms vs 55ms) - acceptable for enhanced security
- **100% success rate** - production-ready reliability
- **Both architectures perform well** - choice depends on requirements

**Status:** ✅ **RESOLVED** - Previous performance issues were due to configuration problems, not architectural defects. Current performance is acceptable.

### Performance Summary

| Configuration | P50 Latency | Status |
|---------------|-------------|--------|
| **Historical 3.x** (50m CPU limit + custom echo) | 1,588ms | ❌ Configuration issue |
| **Current 3.x** (no CPU limit + http-echo) | 70ms | ✅ Acceptable |
| **2.x baseline** | 46ms | ✅ Baseline |

**Bottom Line:** 3.x is production-ready with proper resource configuration. The 1.5-2.0x latency overhead is acceptable given the enhanced security and Gateway API benefits.

---

## Appendix: Test Data

### Current 2.x Benchmark (November 18, 2025)
```
Endpoint: https://echo-server-2x-opendatahub.apps.rosa.f3d4c3l4i5u4x1v.fcu6.p3.openshiftapps.com
Backend: hashicorp/http-echo
Requests: 10,000 per iteration × 5 iterations = 50,000 total
Concurrency: 50

Average Results:
  P50 Latency:   46.0ms
  P95 Latency:   55.4ms
  P99 Latency:   65.6ms
  Throughput:    1,032 req/s
  Success Rate:  100% (50,000/50,000)
```

### Current 3.x Benchmark (November 18, 2025 - No CPU Limit)
```
Endpoint: https://data-science-gateway.apps.rosa.f3d4c3l4i5u4x1v.fcu6.p3.openshiftapps.com/echo
Backend: hashicorp/http-echo
kube-auth-proxy: No CPU limit (previously 50m)
Requests: 10,000 per iteration × 5 iterations = 50,000 total
Concurrency: 50

Average Results:
  P50 Latency:   69.9ms
  P95 Latency:   110.1ms
  P99 Latency:   138.3ms
  Throughput:    668 req/s
  Success Rate:  100% (50,000/50,000)
```

### Historical 3.x Benchmark (November 17, 2025 - With 50m CPU Limit)
```
Endpoint: https://data-science-gateway.apps.rosa.f3d4c3l4i5u4x1v.fcu6.p3.openshiftapps.com/echo
Backend: hashicorp/http-echo
kube-auth-proxy: 50m CPU limit (THROTTLED)
Requests: 10,000 per iteration × 5 iterations = 50,000 total
Concurrency: 50

Average Results:
  P50 Latency:   1,620ms
  P95 Latency:   3,140ms
  P99 Latency:   3,970ms
  Throughput:    29 req/s
  Success Rate:  99.96% (49,980/50,000)
  Errors:        20 × 403 Forbidden
```

---

## References

- Overall comparison: `/perf-testing/overall-comparison.md`
- 2.x benchmark summary: `/perf-testing/2.x/benchmark-summary.md`
- 3.x benchmark summary: `/perf-testing/3.x/oauth/benchmark-summary.md`
- 2.x full results: `/perf-testing/2.x/oauth-2x.log`
- 3.x full results: `/perf-testing/3.x/oauth/oauth-3x.log`
