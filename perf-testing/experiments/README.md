# Performance Experiments - Component Isolation

This directory contains controlled experiments to isolate performance bottlenecks by adding/removing components from the authentication stack.

## Experiment Matrix

| Experiment | Ingress | Auth Layer 1 | Auth Layer 2 | Backend | Purpose |
|------------|---------|--------------|--------------|---------|---------|
| **baseline-2x** | Route (HAProxy) | oauth-proxy | - | echo-server | 2.x baseline |
| **baseline-3x** | Gateway (Envoy) | kube-auth-proxy | kube-rbac-proxy | echo-server | 3.x baseline |
| **3x-no-rbac** | Gateway (Envoy) | kube-auth-proxy | - | echo-server | Isolate kube-rbac-proxy overhead |
| **2x-with-rbac** | Route (HAProxy) | oauth-proxy | kube-rbac-proxy | echo-server | Test if RBAC adds same overhead on 2.x |
| **gateway-direct** | Gateway (Envoy) | - | - | echo-server | Pure Gateway/Envoy overhead (no auth) |

## Test Configuration

All tests use:
- **Requests:** 1000
- **Concurrency:** 50
- **Backend:** hashicorp/http-echo (same for all)
- **Auth:** OpenShift OAuth Bearer tokens (where applicable)

## Running Tests

Each experiment directory contains:
- `deployment.yaml` - Kubernetes resources
- `test.sh` - Test execution script
- `results.log` - Test output (generated)

To run an experiment:
```bash
cd experiments/<experiment-name>
oc apply -f deployment.yaml
./test.sh
```

## Results Summary

| Experiment | P50 Latency | P95 Latency | Throughput | Notes |
|------------|-------------|-------------|------------|-------|
| baseline-2x | 47ms | 144ms | 914 req/s | ✅ Completed |
| baseline-3x | 1,588ms | 3,493ms | 29 req/s | ✅ Completed |
| 3x-no-rbac | 1,602ms | 3,562ms | 29 req/s | ✅ Completed - kube-rbac-proxy NOT the bottleneck |
| gateway-direct | 46.5ms | 141.8ms | 918.8 req/s | ✅ Completed - Gateway/Envoy is FAST |
| 2x-with-rbac | - | - | - | 🔄 Pending |

## Key Findings

### 🎯 BOTTLENECK IDENTIFIED: kube-auth-proxy

**The problem is definitively in kube-auth-proxy OAuth validation.**

| Component Stack | P50 Latency | Performance |
|-----------------|-------------|-------------|
| Gateway only (no auth) | 46.5ms | ✅ FAST |
| Gateway + kube-auth-proxy + kube-rbac-proxy | 1,588ms | ❌ 34x SLOWER |
| Gateway + kube-auth-proxy (no rbac) | 1,602ms | ❌ 34x SLOWER |

**Key observations:**
1. **Gateway/Envoy itself is fast**: 46.5ms P50 (nearly identical to 2.x HAProxy at 47ms)
2. **kube-rbac-proxy is NOT the problem**: Removing it changed P50 by only 14ms (1,588ms → 1,602ms)
3. **kube-auth-proxy adds ~1.54 seconds**: The OAuth/OIDC validation layer is the entire bottleneck
4. **Throughput drops 31x**: From 918 req/s (no auth) to 29 req/s (with kube-auth-proxy)

### Architecture Performance Breakdown

```
┌─────────────────────────────────────────────────────────┐
│ 2.x: Route → oauth-proxy → echo                        │
│ P50: 47ms | P95: 144ms | 914 req/s                     │
│ ✅ FAST                                                 │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ 3.x no-auth: Gateway → echo                            │
│ P50: 46.5ms | P95: 141.8ms | 918.8 req/s              │
│ ✅ FAST - Gateway performs identically to Route        │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ 3.x: Gateway → kube-auth-proxy → kube-rbac → echo     │
│ P50: 1,588ms | P95: 3,493ms | 29 req/s                │
│ ❌ SLOW - kube-auth-proxy adds 1.54 seconds            │
└─────────────────────────────────────────────────────────┘
```

### Next Steps

1. **Investigate kube-auth-proxy implementation**:
   - OAuth token validation logic
   - Connection pooling to OAuth server
   - Caching strategy for validated tokens
   - ext_authz protocol implementation

2. **Profile kube-auth-proxy**:
   - Add detailed logging/metrics
   - Measure time spent in OAuth API calls
   - Check for synchronous blocking operations

3. **Compare to oauth-proxy**:
   - Why is oauth-proxy fast (~40ms) vs kube-auth-proxy slow (~1,540ms)?
   - Both validate OAuth tokens, but 38x performance difference
