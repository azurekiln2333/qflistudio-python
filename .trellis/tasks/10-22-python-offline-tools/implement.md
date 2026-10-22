# Tools and analyzer execution plan

1. After plan approval, start this child and refresh relevant initial tools/main
   diffs. Confirm C's exact shipped analysis API and module-service contract.
2. Refactor only the shared Python body needed for direct tools; retain behavior
   with existing controls/lifecycle tests, then add direct root-tab integration.
3. Add module/package controls and actual operation/status/output behavior.
4. Add source-based compile-only runner and centralized VM busy/single-flight
   coordination; write real no-side-effect and recovery regressions.
5. Add Python CodeAnalyzer mapping exact snapshots/lines to C's UTF-16 contract,
   then register the optional profile provider. Test unsaved disk mismatch,
   Unicode/CRLF, multi-buffer, unavailable/busy/stale and disposal paths.
6. Run focused app tests, full analyzer/tests, real native syntax suite, and
   narrow/wide Tools layouts. Verify actual editor Problems/underlines on OHOS
   after final HAP integration; missing device remains an open gate.
7. Update workflow spec, inspect owned staged changes and commit separately from
   unrelated existing startup/icon/signing work.

Core UI/type files remain C-owned. A local refactor must preserve run/compile/
stop output and cancellation behavior before new controls are added. Roll back
only this owned batch if direct root-tab integration regresses existing callers.
