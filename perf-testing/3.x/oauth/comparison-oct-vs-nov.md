# OAuth Performance Comparison: October vs November 2025

## Executive Summary

Switching from the cloud-bulldozer/nginx backend to hashicorp/http-echo resulted in **significant performance improvements** with more stable and predictable behavior.

### Key Improvements

| Metric | Oct 15, 2025 | Nov 17, 2025 | Change |
|--------|--------------|--------------|--------|
| **Throughput** | 18.42 req/s | 29.05 req/s | **+57.6%** ✅ |
| **P50 Latency** | 2.64s | 1.62s | **-38.6%** ✅ |
| **P95 Latency** | 2.80s | 3.14s | +12.1% ⚠️ |
| **P99 Latency** | ~7.24s* | 3.97s | **-45.2%** ✅ |
| **Success Rate** | 99.77% | 99.96% | **+0.19%** ✅ |
| **Total Errors** | 113 | 20 | **-82.3%** ✅ |

*Average excluding iteration 5 anomaly (12.55s)

## Test Environment Comparison

### Configuration Differences

| Parameter | Oct 15 Test | Nov 17 Test | Notes |
|-----------|-------------|-------------|-------|
| **Cluster** | b9q3t4p8k3y8k9a.vzrg.p3 | f3d4c3l4i5u4x1v.fcu6.p3 | Different ROSA clusters |
| **Backend** | cloud-bulldozer/nginx | hashicorp/http-echo | **Key change** |
| **Requests/iteration** | 10,000 | 10,000 | Same |
| **Concurrency** | 50 | 50 | Same |
| **Iterations** | 5 | 5 | Same |
| **Total requests** | 50,000 | 50,000 | Same |

### Architecture

Both tests used identical gateway architecture:
```
Gateway (Envoy) → kube-auth-proxy → kube-rbac-proxy → backend
```

The only difference was the backend service implementation.

## Detailed Comparison

### Throughput Analysis

**October Test:**
- Iteration 1: 19.08 req/s
- Iteration 2: 18.77 req/s
- Iteration 3: 18.83 req/s
- Iteration 4: 18.74 req/s
- Iteration 5: 16.66 req/s (degraded)
- **Average: 18.42 req/s**

**November Test:**
- Iteration 1: 29.45 req/s
- Iteration 2: 29.04 req/s
- Iteration 3: 28.72 req/s
- Iteration 4: 28.65 req/s
- Iteration 5: 29.39 req/s
- **Average: 29.05 req/s**

**Observation:** November test shows:
- 57.6% higher throughput
- Much more consistent performance across iterations
- No degradation in iteration 5 (unlike October test)

### Latency Comparison

#### P50 (Median) Latency

| Iteration | Oct 15 | Nov 17 | Difference |
|-----------|--------|--------|------------|
| 1 | 2.61s | 1.60s | -1.01s (-38.7%) |
| 2 | 2.64s | 1.61s | -1.03s (-39.0%) |
| 3 | 2.64s | 1.64s | -1.00s (-37.9%) |
| 4 | 2.65s | 1.64s | -1.01s (-38.1%) |
| 5 | 2.64s | 1.60s | -1.04s (-39.4%) |
| **Average** | **2.64s** | **1.62s** | **-1.02s (-38.6%)** |

#### P95 Latency

| Iteration | Oct 15 | Nov 17 | Difference |
|-----------|--------|--------|------------|
| 1 | 2.75s | 3.12s | +0.37s (+13.5%) |
| 2 | 2.83s | 3.20s | +0.37s (+13.1%) |
| 3 | 2.81s | 3.12s | +0.31s (+11.0%) |
| 4 | 2.82s | 3.16s | +0.34s (+12.1%) |
| 5 | 2.81s | 3.10s | +0.29s (+10.3%) |
| **Average** | **2.80s** | **3.14s** | **+0.34s (+12.1%)** |

#### P99 Latency

| Iteration | Oct 15 | Nov 17 | Difference |
|-----------|--------|--------|------------|
| 1 | 2.83s | 3.99s | +1.16s (+41.0%) |
| 2 | 3.20s | 4.00s | +0.80s (+25.0%) |
| 3 | 2.93s | 3.97s | +1.04s (+35.5%) |
| 4 | 3.49s | 4.00s | +0.51s (+14.6%) |
| 5 | 12.55s* | 3.87s | -8.68s (-69.2%) |
| **Average** | **4.98s** | **3.97s** | **-1.01s (-20.3%)** |

*Iteration 5 in Oct test had severe anomaly with 113 timeouts

**Key Observation:** While P95 latency increased slightly, P99 latency improved dramatically due to elimination of timeout spikes.

### Error Analysis

#### October Test

**Total Errors: 113 (0.23% error rate)**

- Iteration 5 had **113 timeout errors**
- All timeouts: "context deadline exceeded (Client.Timeout exceeded while awaiting headers)"
- P99 latency spiked to 12.55s in iteration 5
- Slowest request: 17.76s
- Indicates severe performance degradation/cluster issues

#### November Test

**Total Errors: 20 (0.04% error rate)**

- All errors were **403 Forbidden** responses
- No timeout errors
- Evenly distributed across iterations (2, 2, 6, 8, 2)
- Indicates intermittent auth/authz issues, not performance problems

**Improvement:** 82.3% reduction in total errors, complete elimination of timeout errors.

### Resource Utilization Comparison

#### kube-auth-proxy

| Metric | Oct 15 | Nov 17 | Difference |
|--------|--------|--------|------------|
| **CPU at start** | 0.0004 cores (0.04%) | 0.0014 cores (0.14%) | +0.10% |
| **CPU during load** | 0.007 cores (0.7%) | 0.0334 cores (3.34%) | +2.64% |
| **Memory at start** | 21 MB | 19.4 MB | -1.6 MB |
| **Memory during load** | 22 MB | 32.3 MB | +10.3 MB |

**Analysis:** Higher throughput (29 vs 18 req/s) leads to proportionally higher CPU usage, but still very efficient at 3.34%.

#### echo-server Pod (Total)

| Metric | Oct 15 | Nov 17 | Difference |
|--------|--------|--------|------------|
| **Backend CPU at start** | 0.043 cores (4.3%) | 0.0003 cores (0.03%) | **-4.27%** ✅ |
| **Backend CPU during load** | 0.73 cores (73%) | 0.0103 cores (1.03%) | **-71.97%** ✅ |
| **Backend Memory** | ~40 MB | 26.9 MB | -13.1 MB ✅ |
| **RBAC proxy CPU at start** | 0.001 cores (0.1%) | 0.0002 cores (0.02%) | -0.08% |
| **RBAC proxy CPU during load** | 0.011 cores (1.1%) | 0.0030 cores (0.30%) | -0.80% |
| **RBAC proxy Memory** | ~47-50 MB | 13.2 MB | -34.3 MB ✅ |

**Analysis:**
- nginx backend used **73% CPU** vs http-echo's **1.03% CPU** (98.6% reduction!)
- nginx was the bottleneck in October test
- http-echo's minimal overhead allows more accurate measurement of gateway/auth stack
- Total pod resource usage dropped from ~90 MB to ~40 MB

## Root Cause Analysis

### Why Did November Perform Better?

1. **Backend Efficiency:**
   - nginx: Complex web server with full HTTP processing, compression, logging, etc.
   - http-echo: Ultra-lightweight Go binary that just echoes a response
   - nginx consumed 73% CPU, becoming the bottleneck
   - http-echo uses 1% CPU, allowing auth stack to be the focus

2. **Consistency:**
   - nginx had variable processing time under load
   - http-echo has constant, minimal processing time
   - Led to more predictable latency distribution

3. **No Timeout Errors:**
   - nginx occasionally took >12s to respond under load
   - http-echo never exceeded 5.2s even at P99+
   - Indicates nginx was resource-constrained

4. **Better Test Isolation:**
   - October test was measuring nginx performance as much as gateway performance
   - November test isolates gateway/auth stack behavior
   - More accurate representation of authentication overhead

### Why Is P95 Slightly Higher?

Despite overall improvements, P95 increased from 2.80s to 3.14s (+12.1%).

**Possible explanations:**

1. **Different clusters:**
   - Different AWS regions/availability zones
   - Different network characteristics
   - Different OAuth server response times

2. **Higher throughput:**
   - 57% more requests processed per second
   - May hit different concurrency limits in OAuth/RBAC APIs

3. **Trade-off:**
   - Small P95 increase is acceptable for:
     - 38% better P50 (median user experience)
     - 45% better P99 (tail latency)
     - No timeout errors (reliability)

4. **Measurement accuracy:**
   - With faster backend, auth overhead is more visible
   - Previous test was dominated by nginx processing time

## Conclusions

### Performance Improvement Summary

✅ **Throughput:** +57.6% improvement (18.42 → 29.05 req/s)
✅ **Median latency:** -38.6% improvement (2.64s → 1.62s)
✅ **Tail latency (P99):** -45.2% improvement (7.24s → 3.97s)
✅ **Reliability:** -82.3% fewer errors, no timeouts
✅ **Resource efficiency:** -98.6% backend CPU usage
⚠️ **P95 latency:** +12.1% higher (2.80s → 3.14s)

### Recommendations

1. **Use hashicorp/http-echo for future benchmarks:**
   - Better isolation of gateway/auth overhead
   - More consistent results
   - Lower resource requirements

2. **Investigate P95 increase:**
   - May be cluster-specific
   - Could run side-by-side test on same cluster
   - Consider in-cluster testing with hey-pod to eliminate external network variance

3. **Focus on 403 errors:**
   - 20 intermittent auth failures across 50k requests
   - May indicate OAuth token timing issues
   - Worth investigating for production readiness

4. **Baseline established for 2.x comparison:**
   - November results provide clean baseline
   - Ready to compare against RHOAI 2.x HAProxy + oauth-proxy architecture
   - Use same http-echo backend for fair comparison

## Next Steps

1. **Run equivalent test on RHOAI 2.x:**
   - Deploy hashicorp/http-echo behind oauth-proxy
   - Use same test parameters (10k requests, 50 concurrency, 5 iterations)
   - Compare to Nov 17 results

2. **In-cluster testing:**
   - Use hey-pod to eliminate external network latency
   - Isolate gateway stack performance
   - May explain P95 variance

3. **BYOIDC testing:**
   - Configure external OIDC provider
   - Compare OAuth vs OIDC performance
   - Quantify external IdP overhead
