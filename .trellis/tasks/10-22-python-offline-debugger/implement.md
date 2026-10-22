# Debugger execution plan

1. After parent review and native module batch release, start this child, read
   native lifecycle/FFI/platform specs and establish C's common debug contract.
2. In a scratch build, enable upstream tracing and prove actual line/call/return
   callbacks, source paths and frame data without changing ordinary runs.
3. Implement native session/event/pause control with worker-only VM access,
   bounded buffers, condition signaling and existing cancellation convergence.
4. Extend app FFI and platform bridges with optional capability discovery and
   async control/events; keep both ArkTS copies synchronized. Serialize builds.
5. Adapt to C's debugger UI/provider contract; show genuine state and supported
   stack/variable information. Do not reuse web-preview debugStream incorrectly.
6. Run real native breakpoint/step/continue/stop/error/import/reuse regressions,
   adapter tests, complete app analyzer/tests and OHOS dependency/HAP checks.
7. On the final installed OHOS app, verify actual pauses/steps/continue/stops
   and normal-run recovery. Record events and HAP/library/code hashes. Device
   absence keeps this open; no host-only completion claim.
8. Update capability/lifecycle specs, review explicit owned diffs and commit.

Rollback preserves legacy ABI and ordinary run behavior. Do not leave a paused
worker or dangling handle while rolling back; settle session control first.
