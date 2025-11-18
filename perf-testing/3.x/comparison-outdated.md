# RHOAI 3.x Gateway: OAuth vs BYOIDC Performance Comparison

**Comparison Date:** October 22, 2025
**Purpose:** Compare OpenShift OAuth and BYOIDC (Keycloak) authentication performance for RHOAI 3.x Gateway

## Executive Summary

Both authentication methods demonstrate production-ready performance with similar latency and resource utilization. **BYOIDC showed 100% success rate and better consistency**, while OAuth had slightly better throughput but experienced one anomaly during testing.

| Metric | OpenShift OAuth | BYOIDC (Keycloak) | Winner |
|--------|-----------------|-------------------|--------|
| **Average P95 Latency** | 2.80s | 2.97s | OAuth (-6%) |
| **Average Throughput** | 18.42 req/s | 17.69 req/s | OAuth (+4%) |
| **Success Rate** | 99.77% | 100% | BYOIDC (+0.23%) |
| **Consistency** | 1 anomaly (iter 5) | No anomalies | BYOIDC |
| **P95 Variance** | ~75ms | ~30ms | BYOIDC |
| **kube-auth-proxy CPU** | 0.7% | 1% | OAuth (-0.3%) |

**Verdict:** Performance is **nearly equivalent**. Choose based on operational requirements rather than performance:
- **OAuth:** Slightly faster (6%), integrated with OpenShift
- **BYOIDC:** More reliable (100% success), portable to any OIDC provider

## Test Environment

### Common Configuration
- **Test Tool:** hey (HTTP load testing)
- **Requests per Iteration:** 10,000
- **Concurrency:** 50 concurrent connections
- **Iterations:** 5 (total 50,000 requests per test)
- **Backend:** echo-server with kube-rbac-proxy sidecar
- **Architecture:** Gateway → kube-auth-proxy → kube-rbac-proxy → echo-server

### Differences

| Aspect | OAuth Test | BYOIDC Test |
|--------|-----------|-------------|
| **Test Date** | October 15, 2025 | October 22, 2025 |
| **Cluster** | b9q3t4p8k3y8k9a.vzrg.p3 | t1g3t1j7h7c4e1e.6ing.p3 |
| **Auth Provider** | OpenShift OAuth | Keycloak (keycloak.tannerjc.net) |
| **Token Type** | OpenShift Bearer Token | JWT Bearer Token |
| **Token Source** | `oc whoami -t` | Keycloak password grant |

## Latency Comparison

### P95 Latency by Iteration

| Iteration | OAuth P95 | BYOIDC P95 | Difference | % Diff |
|-----------|-----------|------------|------------|--------|
| 1 | 2.7535s | 2.9939s | +0.2404s | +8.7% |
| 2 | 2.8263s | 2.9697s | +0.1434s | +5.1% |
| 3 | 2.8098s | 2.9851s | +0.1753s | +6.2% |
| 4 | 2.8191s | 2.9717s | +0.1526s | +5.4% |
| 5 | 2.8113s | 2.9716s | +0.1603s | +5.7% |
| **Average** | **2.8040s** | **2.9784s** | **+0.1744s** | **+6.2%** |

**Analysis:**
- BYOIDC is consistently ~170ms slower (6% increase)
- Both maintain stable latency across iterations
- Difference is **negligible** in context of ~3s total latency
- Likely due to JWT signature validation overhead

### P50 Latency by Iteration

| Iteration | OAuth P50 | BYOIDC P50 | Difference | % Diff |
|-----------|-----------|------------|------------|--------|
| 1 | 2.6060s | 2.8196s | +0.2136s | +8.2% |
| 2 | 2.6422s | 2.7748s | +0.1326s | +5.0% |
| 3 | 2.6427s | 2.8112s | +0.1685s | +6.4% |
| 4 | 2.6465s | 2.7875s | +0.1410s | +5.3% |
| 5 | 2.6380s | 2.7981s | +0.1601s | +6.1% |
| **Average** | **2.6351s** | **2.7982s** | **+0.1631s** | **+6.2%** |

**Analysis:**
- Similar ~6% difference at median latency
- Pattern consistent across all percentiles
- Suggests overhead is distributed, not just in tail latencies

### P99 Latency Comparison

| Iteration | OAuth P99 | BYOIDC P99 | Difference |
|-----------|-----------|------------|------------|
| 1 | 2.8299s | 3.1886s | +0.3587s |
| 2 | 3.2003s | 3.3887s | +0.1884s |
| 3 | 2.9317s | 3.0985s | +0.1668s |
| 4 | 3.4856s | 3.0951s | -0.3905s |
| 5 | **12.5513s** ⚠️ | 3.0620s | -9.4893s |

**Analysis:**
- OAuth iteration 5 had **severe P99 spike** (12.55s)
- BYOIDC maintained stable P99 (~3.1s) across all iterations
- **BYOIDC wins on tail latency consistency**

## Reliability Comparison

### Success Rates

| Test | Total Requests | Successful | Failed | Success Rate | Errors |
|------|----------------|------------|--------|--------------|--------|
| **OAuth** | 50,000 | 49,887 | 113 | 99.77% | 113 timeouts (iter 5) |
| **BYOIDC** | 50,000 | 50,000 | 0 | **100%** | None |

**Winner:** BYOIDC (100% success rate)

### Iteration 5 Anomaly (OAuth Only)

OAuth test experienced issues in iteration 5:
- **113 timeout errors:** "context deadline exceeded (Client.Timeout exceeded while awaiting headers)"
- **P99 latency spike:** 12.55 seconds (vs ~3s in other iterations)
- **Slowest request:** 17.76 seconds
- **Root cause:** Likely intermittent cluster resource contention or network issues

BYOIDC had **no such anomaly** - all iterations completed successfully.

## Throughput Comparison

| Test | Avg Throughput | Min | Max | Variance |
|------|----------------|-----|-----|----------|
| **OAuth** | 18.42 req/s | 16.66 | 19.08 | 2.42 req/s |
| **BYOIDC** | 17.69 req/s | 17.50 | 17.82 | 0.32 req/s |

**Analysis:**
- OAuth has **4% higher average throughput**
- BYOIDC has **much lower variance** (0.32 vs 2.42)
- OAuth variance heavily influenced by iteration 5 drop (16.66 req/s)
- **BYOIDC is more predictable** for capacity planning

## Resource Utilization Comparison

### kube-auth-proxy (Authentication Layer)

| Metric | OAuth | BYOIDC | Difference |
|--------|-------|--------|------------|
| **CPU (idle)** | 0.0004 cores | 0.0008 cores | +100% |
| **CPU (load)** | 0.007 cores (0.7%) | 0.010 cores (1%) | +43% |
| **Memory (idle)** | ~21 MB | ~21-22 MB | Negligible |
| **Memory (load)** | ~22 MB | ~22-23 MB | Negligible |

**Analysis:**
- BYOIDC uses slightly more CPU (0.3% more)
- Difference is **minimal** in absolute terms (0.003 cores)
- Likely due to JWT signature verification vs OAuth token validation
- Both are extremely efficient

### echo-server Pod (Backend + Authorization)

| Container | OAuth CPU | BYOIDC CPU | Difference |
|-----------|-----------|------------|------------|
| **echo-server** | 0.73 cores (73%) | 0.70 cores (70%) | -3% |
| **kube-rbac-proxy** | 0.011 cores (1.1%) | 0.012 cores (1.2%) | +9% |
| **Total** | 0.74 cores | 0.71 cores | -4% |

| Container | OAuth Memory | BYOIDC Memory | Difference |
|-----------|--------------|---------------|------------|
| **echo-server** | ~40 MB | ~39-40 MB | Negligible |
| **kube-rbac-proxy** | ~47-50 MB | ~44-47 MB | Negligible |
| **Total** | ~88-91 MB | ~87-88 MB | Negligible |

**Analysis:**
- Backend resource usage is **virtually identical**
- Minor differences likely due to cluster variations, not auth method
- Both configurations show significant headroom for scaling

## Performance Characteristics

### Latency Distribution

**OAuth:**
- Most requests cluster tightly around median (~2.6s)
- Larger tail with some requests >3s
- Iteration 5 had extreme outliers (>10s)

**BYOIDC:**
- Similar clustering around median (~2.8s)
- Tighter distribution overall
- No extreme outliers
- More predictable response times

### Consistency Analysis

**Coefficient of Variation (P95 latency):**
- OAuth: CV = 2.7% (excluding iter 5 anomaly)
- BYOIDC: CV = 0.9%

**BYOIDC is 3x more consistent** in P95 latency.

## Key Differences

### 1. Latency: OAuth Wins (+6%)

**OAuth is 170ms faster** on average (2.80s vs 2.97s P95)

**Possible reasons:**
- JWT signature validation overhead in BYOIDC
- Different cluster network conditions
- Testing on different dates/times

**Impact:** Negligible in context of ~3 second total latency

### 2. Reliability: BYOIDC Wins (100% vs 99.77%)

**BYOIDC had perfect success rate**, OAuth had 113 timeouts

**Possible reasons:**
- OAuth iteration 5 anomaly (cluster-specific issue)
- BYOIDC tested on different day with better cluster conditions
- Sample size too small to definitively conclude

**Impact:** Significant for production SLAs

### 3. Consistency: BYOIDC Wins (3x better)

**BYOIDC P95 variance: 30ms, OAuth: 75ms** (excluding anomaly)

**Possible reasons:**
- JWT validation is deterministic
- OAuth may have variable API call latency
- Cluster-specific factors

**Impact:** Better predictability for capacity planning

### 4. Throughput: OAuth Wins (+4%)

**OAuth: 18.42 req/s, BYOIDC: 17.69 req/s**

**Possible reasons:**
- Faster latency = higher throughput
- OAuth anomaly skews average down
- Cluster capacity differences

**Impact:** Minimal difference for production planning

### 5. Resource Usage: Virtually Identical

**kube-auth-proxy CPU:** 0.7% vs 1% (0.3% difference)
**Total pod resources:** Negligible differences

**Impact:** No meaningful difference for resource planning

## Recommendations

### Choose OpenShift OAuth if:
- ✅ You need **slightly better latency** (6% faster)
- ✅ You want **tighter OpenShift integration**
- ✅ You prefer **no external dependencies**
- ✅ Users already have OpenShift accounts
- ⚠️ You can tolerate **occasional anomalies** (iteration 5 pattern)

### Choose BYOIDC (Keycloak/External OIDC) if:
- ✅ You need **100% reliability** and consistency
- ✅ You want **portability** to any OIDC provider
- ✅ You need **external IdP integration** (corporate SSO, etc.)
- ✅ You prefer **standard OIDC compliance**
- ✅ **6% slower latency is acceptable** (~170ms)
- ⚠️ You can manage **external IdP dependency**

### Production Deployment Guidance

**For both approaches:**
1. **Set SLO at P95: ~3 seconds** (conservative estimate)
2. **Scale horizontally:** Both have CPU headroom for increased throughput
3. **Monitor iteration 5 pattern:** If OAuth timeouts repeat, investigate cluster issues
4. **Consider token caching:** May reduce latency for both approaches

**Performance is not the differentiator** - choose based on:
- Organizational requirements (external IdP vs OpenShift native)
- Operational complexity (managing external Keycloak vs OpenShift OAuth)
- Compliance requirements (OIDC standard vs OpenShift-specific)

## Conclusion

Both authentication methods provide **production-ready performance** with similar characteristics:

- **Latency:** OAuth 6% faster (negligible in absolute terms)
- **Reliability:** BYOIDC 100% success rate (more reliable)
- **Consistency:** BYOIDC 3x better variance (more predictable)
- **Resources:** Virtually identical (both very efficient)

**The choice between OAuth and BYOIDC should be driven by operational and organizational requirements, not performance.** Both will serve users well in production.

## Test Data Sources

- **OAuth Results:** `oauth/oauth-3x.log` and `oauth/oauth-3x-metrics.log` (Oct 15, 2025)
- **BYOIDC Results:** `oidc/oidc-3x.log` and `oidc/oidc-3x-metrics.log` (Oct 22, 2025)
- **OAuth Summary:** `oauth/benchmark-summary.md`
- **BYOIDC Summary:** `oidc/benchmark-summary.md`
