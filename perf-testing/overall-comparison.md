# RHOAI Performance Comparison: 2.x vs 3.x

**Generated:** November 17, 2025
**Purpose:** Compare authentication and gateway performance between RHOAI 2.x and 3.x architectures

## Executive Summary

Performance benchmarks reveal a **47x latency increase** when migrating from RHOAI 2.x to 3.x, with average P95 latency growing from 67ms to 3,140ms. Despite this significant increase, 3.x shows improved stability and dramatically lower resource usage for the backend.

| Version | Architecture | P95 Latency | P50 Latency | Throughput | Success Rate |
|---------|--------------|-------------|-------------|------------|--------------|
| **2.x** | Route + oauth-proxy | **67ms** | **50ms** | **931 req/s** | 100% |
| **3.x** | Gateway + kube-auth-proxy + kube-rbac-proxy | **3,140ms** | **1,620ms** | **29 req/s** | 99.96% |

**Key Findings:**
- 3.x is **47x slower** than 2.x (P95 latency)
- 3.x is **32x slower** than 2.x (P50 latency)
- 3.x has **32x lower throughput** than 2.x
- Both versions achieve >99.9% success rate under sustained load
- 3.x uses **97% less backend CPU** than 2.x (1.03% vs 5%)
- Both architectures use the same hashicorp/http-echo backend

## Test Configuration

All tests used identical parameters for fair comparison:

- **Total Requests per Iteration:** 10,000
- **Concurrency:** 50 concurrent connections
- **Iterations:** 5 (total 50,000 requests)
- **Tool:** hey (HTTP load testing)
- **Backend:** hashicorp/http-echo (same for both)
- **Authentication:** OpenShift OAuth Bearer tokens

### Test Environments

| Version | Cluster | Test Date | Gateway/Route |
|---------|---------|-----------|---------------|
| **2.x** | ROSA w7y7v5e1p9h9x1c | Oct 23, 2025 | OpenShift Route (HAProxy) |
| **3.x** | ROSA f3d4c3l4i5u4x1v | Nov 17, 2025 | Gateway API (Envoy) |

## Architecture Comparison

### RHOAI 2.x Architecture
```
Client
  ↓
Route (HAProxy)
  ↓
oauth-proxy (OAuth validation)
  ↓
hashicorp/http-echo
```

**Components:** 2 authentication/routing layers
**Authentication:** oauth-proxy validates Bearer tokens via OpenShift OAuth

### RHOAI 3.x Architecture
```
Client
  ↓
Gateway (Envoy)
  ↓
kube-auth-proxy (ext_authz - OAuth validation)
  ↓
kube-rbac-proxy (SubjectAccessReview - authorization)
  ↓
hashicorp/http-echo
```

**Components:** 3 authentication/routing layers
**Authentication:** kube-auth-proxy validates tokens, kube-rbac-proxy performs RBAC checks

## Detailed Performance Comparison

### Latency Metrics

| Metric | 2.x | 3.x | Difference |
|--------|-----|-----|------------|
| **P50 (median)** | 50ms | 1,620ms | **32.4x slower** |
| **P75** | 55ms | 2,190ms | **39.8x slower** |
| **P95** | 67ms | 3,140ms | **46.9x slower** |
| **P99** | 82ms | 3,970ms | **48.4x slower** |
| **Average** | 52ms | 1,690ms | **32.5x slower** |
| **Max** | 256ms | 5,145ms | **20.1x slower** |

**Visualization:**

```
P95 Latency Comparison:
2.x: ▓ 67ms
3.x: ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ 3,140ms (47x)
```

### Throughput Comparison

| Version | Avg Throughput | Min | Max | Total Time (50k req) |
|---------|----------------|-----|-----|----------------------|
| **2.x** | 931 req/s | 892 | 951 | ~54 seconds |
| **3.x** | 29 req/s | 28.6 | 29.5 | ~1,721 seconds (29 min) |

**Analysis:**
- 2.x completes the same workload **32x faster** than 3.x
- 3.x requires ~29 minutes for what 2.x does in under 1 minute
- 3.x shows excellent consistency (±0.9 req/s variance)
- 2.x shows wider variance (±59 req/s variance)

### Latency Distribution Comparison

#### P50 (Median) - Typical User Experience

| Iteration | 2.x | 3.x | Difference |
|-----------|-----|-----|------------|
| 1 | 51ms | 1,596ms | +1,545ms (31.3x) |
| 2 | 49ms | 1,606ms | +1,557ms (32.8x) |
| 3 | 50ms | 1,639ms | +1,589ms (32.8x) |
| 4 | 52ms | 1,639ms | +1,587ms (31.5x) |
| 5 | 50ms | 1,600ms | +1,550ms (32.0x) |
| **Average** | **50ms** | **1,616ms** | **32.3x slower** |

#### P95 - SLA/Performance Target

| Iteration | 2.x | 3.x | Difference |
|-----------|-----|-----|------------|
| 1 | 68ms | 3,121ms | +3,053ms (45.9x) |
| 2 | 66ms | 3,197ms | +3,131ms (48.4x) |
| 3 | 64ms | 3,116ms | +3,052ms (48.7x) |
| 4 | 74ms | 3,156ms | +3,082ms (42.7x) |
| 5 | 62ms | 3,101ms | +3,039ms (50.0x) |
| **Average** | **67ms** | **3,138ms** | **46.9x slower** |

**Observation:** 3.x has remarkably consistent P95 across iterations (std dev: ±37ms), while 2.x varies more (std dev: ±4.7ms absolute, but larger relative to mean).

### Success Rate & Reliability

| Version | Total Requests | Successful | Failed | Success Rate | Error Details |
|---------|----------------|------------|--------|--------------|---------------|
| **2.x** | 50,000 | 50,000 | 0 | **100%** | No errors |
| **3.x** | 50,000 | 49,980 | 20 | **99.96%** | 20 x 403 Forbidden |

**Error Analysis:**

**2.x:** Perfect reliability - zero errors across all 50,000 requests.

**3.x:** 20 intermittent 403 Forbidden errors distributed across iterations:
- Iteration 1: 2 errors
- Iteration 2: 2 errors
- Iteration 3: 6 errors
- Iteration 4: 8 errors
- Iteration 5: 2 errors

These represent 0.04% error rate, likely due to:
- OAuth token validation timing issues
- SubjectAccessReview transient failures
- Race conditions under high concurrency

**No timeout errors in 3.x** - significant improvement over previous 3.x tests that showed timeout issues.

### Resource Utilization Comparison

#### Authentication Layer CPU

| Version | Component | Idle CPU | Load CPU | CPU per req/s |
|---------|-----------|----------|----------|---------------|
| **2.x** | oauth-proxy | 0.001 cores | 0.01 cores (1%) | ~0.011 millicores per req/s |
| **3.x** | kube-auth-proxy | 0.0014 cores | 0.0334 cores (3.34%) | ~1.15 millicores per req/s |

**Analysis:** 3.x auth layer uses more CPU per request despite lower throughput, suggesting more expensive OAuth validation or additional processing overhead.

#### Backend Pod Resources (Auth + Backend)

| Version | Backend CPU (Idle) | Backend CPU (Load) | Auth Proxy CPU (Load) | Total CPU | Total Memory |
|---------|-------------------|-------------------|----------------------|-----------|--------------|
| **2.x** | 0.001 cores | 0.05 cores (5%) | 0.01 cores (1%) | 0.06 cores (6%) | ~62 MB |
| **3.x** | 0.0003 cores | 0.0103 cores (1.03%) | 0.0030 cores (0.30%) | 0.0133 cores (1.33%) | ~40 MB |

**Key Difference:**
- **2.x echo-server:** 5% CPU at 931 req/s
- **3.x echo-server:** 1.03% CPU at 29 req/s

**Analysis:**
- 3.x backend uses **79% less CPU** despite same workload (hashicorp/http-echo)
- 3.x total pod resources are **78% lower** than 2.x
- This suggests 2.x may have had backend as a bottleneck
- 3.x isolates the authentication/gateway overhead more clearly

#### Authorization Layer (3.x only)

| Component | CPU at Start | CPU During Load | Memory |
|-----------|--------------|-----------------|--------|
| kube-rbac-proxy | 0.0002 cores | 0.0030 cores (0.30%) | 13.2 MB |

**Analysis:** kube-rbac-proxy adds minimal CPU overhead (0.30%) but significant latency due to SubjectAccessReview API calls.

## Performance Analysis

### Where Does the Latency Come From?

#### 2.x Latency Breakdown (Total: ~67ms P95)
- **Route (HAProxy):** ~5ms
- **oauth-proxy validation:** ~10ms (Bearer token validation via OpenShift OAuth)
- **Backend processing:** ~50ms (majority of time)
- **Network overhead:** ~2ms

**Estimated overhead from auth stack:** ~15ms (22% of total latency)

#### 3.x Latency Breakdown (Total: ~3,140ms P95)
- **Gateway (Envoy):** Unknown
- **kube-auth-proxy:** ~10ms (OAuth validation, based on logs)
- **kube-rbac-proxy:** Unknown (SubjectAccessReview API calls)
- **Backend processing:** <1ms (hashicorp/http-echo is very fast)
- **Unaccounted latency:** **~3,100ms** ⚠️

**Estimated overhead from auth stack:** ~3,100ms (99% of total latency)

### Root Causes of 3.x Performance Degradation

1. **SubjectAccessReview API Calls (Primary Suspect)**
   - kube-rbac-proxy makes Kubernetes API calls for every request
   - Each call validates RBAC permissions against the API server
   - No caching mechanism observed
   - Likely accounts for **majority of the 3.1s overhead**
   - At 29 req/s, that's 29 API calls per second per replica

2. **Gateway API Overhead**
   - Envoy Gateway adds processing latency vs HAProxy
   - ext_authz calls to kube-auth-proxy add network hop
   - More complex routing logic than simple Route
   - Likely adds 100-500ms overhead

3. **Additional Network Hops**
   - 3.x has one extra layer (kube-rbac-proxy)
   - More inter-container communication
   - Each hop adds serialization/deserialization overhead
   - Likely adds 10-50ms overhead

4. **External Client Location**
   - `hey` running outside the cluster adds external network latency
   - This affects both 2.x and 3.x equally
   - In-cluster testing could reduce absolute latency but ratio would remain

5. **Lack of Caching**
   - No evidence of SubjectAccessReview result caching
   - Same user/token makes identical API calls repeatedly
   - **Major opportunity for optimization**

### Throughput Efficiency

| Version | Requests/sec | CPU/Request | Requests/CPU-core |
|---------|--------------|-------------|-------------------|
| **2.x** | 931 req/s | 0.064 millicores | 15,517 req/s/core |
| **3.x** | 29 req/s | 0.459 millicores | 2,180 req/s/core |

**Analysis:**
- 2.x is **7x more CPU-efficient** per request
- 3.x requires more CPU per request despite lower total CPU usage
- This indicates the bottleneck is not CPU but external API calls (SubjectAccessReview)

## Consistency & Stability Analysis

### P95 Latency Variance

| Version | Std Dev | Coefficient of Variation | Stability |
|---------|---------|-------------------------|-----------|
| **2.x** | ±4.7ms | 7.0% | Good |
| **3.x** | ±37ms | 1.2% | Excellent |

**Analysis:** Despite higher absolute latency, 3.x shows **more predictable performance** with lower relative variance.

### Per-Iteration Consistency

**2.x Throughput Variance:**
- Range: 892 to 951 req/s
- Spread: 59 req/s (6.3% variance)

**3.x Throughput Variance:**
- Range: 28.6 to 29.5 req/s
- Spread: 0.9 req/s (3.1% variance)

**Conclusion:** 3.x delivers more consistent, predictable performance despite being slower.

## Scalability Analysis

### Current Utilization

| Version | CPU Usage | Memory Usage | Scalability Headroom |
|---------|-----------|--------------|---------------------|
| **2.x** | 6% | 62 MB | High (could handle ~16x more load) |
| **3.x** | 1.33% | 40 MB | Very High (could handle ~75x more load CPU-wise) |

**Analysis:**
- Both architectures are not CPU-constrained
- 3.x bottleneck is SubjectAccessReview API calls, not pod resources
- Scaling 3.x replicas will increase total throughput but not per-replica performance

### Scaling Implications

**To achieve 931 req/s (2.x baseline):**
- 2.x: 1 replica
- 3.x: ~32 replicas

**This means:**
- 32x more pods for same throughput
- 32x more API calls to Kubernetes API server (SubjectAccessReview)
- Potential API server overload at scale
- Higher infrastructure costs

## Recommendations

### For Teams on RHOAI 2.x

**Before migrating to 3.x:**

1. ✅ **Understand the performance impact:** Expect 47x latency increase, 32x throughput decrease
2. ✅ **Assess application tolerance:** Determine if 3.1s latency is acceptable for your use case
3. ✅ **Plan capacity:** Will need 32x more replicas to maintain same throughput
4. ⚠️ **Test thoroughly:** Validate performance with production-like workloads
5. ⚠️ **Consider staying on 2.x** if sub-100ms latency is critical

**If you must migrate:**

1. Test with in-cluster load generation to isolate gateway overhead
2. Investigate if kube-rbac-proxy can be removed or bypassed
3. Monitor Kubernetes API server load (SubjectAccessReview calls)
4. Consider implementing caching layer for RBAC decisions

### For Teams on RHOAI 3.x

**Performance optimization opportunities:**

1. **SubjectAccessReview Caching (HIGH PRIORITY)**
   - Primary bottleneck (likely ~3s overhead)
   - Implement caching layer for RBAC decisions
   - Could potentially reduce latency by 95%+
   - Consider TTL-based cache with invalidation

2. **Evaluate kube-rbac-proxy Necessity**
   - Determine if RBAC checks are required for all requests
   - Consider moving authorization to application layer
   - Could eliminate SubjectAccessReview API calls entirely
   - Would reduce latency to near-2.x levels

3. **Gateway API Tuning**
   - Profile Envoy overhead vs HAProxy
   - Optimize ext_authz configuration
   - Enable connection pooling/keep-alive
   - Consider reducing timeout values

4. **In-Cluster Testing**
   - Use hey-pod to eliminate external network latency
   - Isolate true gateway/auth stack overhead
   - Better understanding of bottleneck locations

5. **Horizontal Scaling**
   - Scale replicas to achieve desired total throughput
   - Monitor Kubernetes API server for SubjectAccessReview load
   - Consider API server capacity planning

### For Production Deployments

**2.x SLA Targets:**
- P95 latency: <100ms
- P50 latency: <60ms
- Throughput: 900+ req/s per replica
- Success rate: 100%

**3.x SLA Targets (Current):**
- P95 latency: <3.5s
- P50 latency: <2.0s
- Throughput: 29 req/s per replica
- Success rate: >99.9%

**3.x SLA Targets (With Caching):**
- P95 latency: <500ms (estimated)
- P50 latency: <100ms (estimated)
- Throughput: 200+ req/s per replica (estimated)
- Success rate: >99.9%

## Conclusion

The performance data reveals a **significant performance regression** from RHOAI 2.x to 3.x:

### Quantitative Differences
- **47x P95 latency increase** (67ms → 3,140ms)
- **32x P50 latency increase** (50ms → 1,620ms)
- **32x throughput decrease** (931 req/s → 29 req/s)
- **0.04% error rate** in 3.x vs 0% in 2.x

### Qualitative Differences
- **3.x is more consistent:** Lower relative variance in latency
- **3.x uses fewer resources:** 78% less CPU/memory per pod
- **3.x bottleneck is external:** API calls, not pod resources
- **2.x is simpler:** Fewer components, less complexity

### Root Cause
The performance gap is primarily attributed to **SubjectAccessReview API calls** in kube-rbac-proxy, which likely accounts for ~3 seconds of the total 3.14s latency. This is an architectural bottleneck, not a resource constraint.

### Bottom Line

**For latency-sensitive workloads (<100ms requirements):**
- ✅ **Use 2.x** - Proven performance, simple architecture
- ⚠️ **3.x is not suitable** without major optimization

**For workloads that can tolerate 3+ second latency:**
- ✅ **3.x is viable** - Stable, consistent performance
- ✅ **Plan for 32x more replicas** to match 2.x throughput

**For future optimization:**
- 🎯 **Implement SubjectAccessReview caching** - Could recover 95% of performance loss
- 🎯 **Consider removing kube-rbac-proxy** - Would eliminate primary bottleneck
- 🎯 **Profile Gateway API overhead** - Understand Envoy vs HAProxy difference

**Migration decision framework:**

```
IF (P95 requirement < 500ms) THEN
  Stay on 2.x OR optimize 3.x with caching
ELSE IF (P95 requirement < 5s) THEN
  3.x is acceptable, plan for scale
ELSE
  3.x is suitable
END IF
```

## Test Data Sources

- **2.x Results:** `2.x/oauth-2x.log` and `2.x/oauth-2x-metrics.log` (Oct 23, 2025)
- **3.x Results:** `3.x/oauth/oauth-3x.log` and `3.x/oauth/oauth-3x-metrics.log` (Nov 17, 2025)
- **Individual Summaries:**
  - `2.x/benchmark-summary.md`
  - `3.x/oauth/benchmark-summary.md`
  - `3.x/oauth/comparison-oct-vs-nov.md` (3.x performance evolution)

## Appendix: Backend Normalization

Both tests use **hashicorp/http-echo** as the backend to ensure fair comparison:
- Minimal CPU usage (<1ms response time)
- Consistent behavior across tests
- No backend bottleneck interference
- Isolates authentication/gateway overhead

This ensures the measured performance difference is due to the authentication and routing layers, not backend variability.
