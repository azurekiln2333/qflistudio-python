# Current-source audit binding repair

Date: 2026-10-24. Python root owns this batch.

The existing audit builder verifies declared assets and the staged SO, but can
pair them with old native code or another audit's debug payload. Synchronous
external commands can also prevent profile restoration indefinitely. Independent
review is recorded in `ohos-builder-static-review.md`.

The behavior belongs in native build provenance, preparation and archive
verification. Root owns `tool/build_python_ohos_audit.ps1`, its synthetic test,
the three preparation scripts, new audit-input/provenance utilities and narrow
provenance hooks in `native/build.ps1`. The native worker owns the shared owned
process helper and its controls. The audit worker owns debugger-harness repairs
and a bounded verification runner. The adapter worker owns product workspace
acceptance tests. Shared core remains under C/main ownership.

Required changes are finite owned process execution, a source/toolchain/output
manifest emitted around the actual native build, complete current source input
hashes, a per-invocation nonce in the packaged debug kernel and an immutable HAP
snapshot held for signature verification. Synthetic failures must reject stale
sources, stale native evidence and a different audit entry. Source-only edits
and synthetic artifacts establish no native, HAP or device success. The frozen
host debugger DLL and historical HAP remain historical evidence.

No common editor writes, device actions or curriculum expansion belong to this
batch. No native/SDK/Flutter process may start without a new named host grant.

## 2026-10-26 input verification follow-up

Root owns `tool/python_audit_inputs.py` and the new synthetic
`test/python_audit_inputs_test.py`. The verifier must reject additions, changes
and removals across captured product/core sources, including explicit native
inputs declared by a preparer outside the automatically discovered directories.
The builder's existing per-declared-file check stays in place. This closes the
standalone verifier's removed-input gap without touching Pi-owned files.
Tests use temporary inert files; no compiler, SDK, Flutter or device process runs.
