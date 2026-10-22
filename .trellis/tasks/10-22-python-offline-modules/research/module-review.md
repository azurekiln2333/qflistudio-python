# Module integration review and current evidence

Date: 2026-10-22. Scope: Python modules child only. No OHOS runtime acceptance
or umbrella completion is claimed by this report.

Independent `review_python_modules` reproduced CSV escaped-newline EOF loss,
incorrect strict escape handling after closing quotes, and recursive same-key
`lru_cache` order corruption. Its subsequent turns failed with account
concurrency errors before fixes. Root verified the cases against host stdlib,
fixed the module implementations, added ten portable regression assertions,
documented keyword-key differences and refreshed every manifest file digest.

Rebuilt Windows DLL SHA256:
`2329ef7d374e35dd5159db0f3f056b094effc9a0372ad29fe704af472a6c309f`.
The real automatic-path verifier passes 306 portable assertions, 128 binary
encoding vectors and 256 CSV scenarios, every source compile, import precedence,
package refresh and fresh-project module-state checks. Full report is preserved
as `python-stdlib-automatic.json` alongside this note. Legacy injected-path
evidence is a separate earlier report.

Actual runner integration tests pass install/import/update/remove, native syntax
failure retaining a working version, and edited-bundle failure preventing
program execution. Empty directories left by manifest-owned file removal may
still import as namespace packages; the regression checks missing owned API.

Both OHOS x86_64 and arm64-v8a libraries rebuild and pass dependency checks
(libace_napi.z.so, libhilog_ndk.z.so, libc.so only). Windows FFI smoke passes
34/34; ArkTS channel contract tests pass 20/20; native host suite previously
passed 100/100 against this C source. These remain host/build evidence.

The first complete app run had three widget failures from reusing cached asset
futures across fake async test zones. Clearing rootBundle between tests and
bounded runAsync asset/file pumping fixes all six tools-page tests. Initial
test edits were preserved. Complete app gates will be rerun on stable sources.

Installed OHOS module/package proof, final signed audit package and the other
approved children remain open. Device queue is Web, Lua, SQL, Python when ready,
Rust, with no Python device mutation or accepted slot yet.
