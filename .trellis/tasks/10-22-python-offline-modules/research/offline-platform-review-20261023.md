# Native offline entry points and artifact drift

JSON's read-only family audit found that the preserved signed module audit HAP
still matches SHA256
`d1387df94ebe8cb74513a0f71253d8723a915cc7fd64af7b5c6d2f0c0b9cdaaf`,
but current `lib/python_ffi.dart` has changed. The HAP is intact and remains
captured-source evidence only. It does not validate the current FFI/debugger.
Rebuild the final package, bind every source/library/asset hash, then repeat
the complete installed-device gate. Do not overwrite the immutable old HAP.

The OHOS EntryAbility retained native handlers for Huawei account login, remote
AgreementReader and arbitrary external openUrl even though standalone UI hides
them. No automatic-start network traffic was established by the audit. Python
now declares a native OFFLINE_ONLY edition policy and immediately rejects
openAgreement/openUrl/login with OFFLINE_ONLY before accessing their arguments
or invoking platform providers. Existing startup/picker/local-sharing work is
preserved. Packaged absence of INTERNET remains an independent build check.

`node tool/test_python_offline_platform.cjs` passed on2026-10-23. It transpiles
the actual EntryAbility and executes its handlers with platform doubles. Engine
setup performs no remote request; five URL shapes (including localhost, local
files and invalid input) are denied through both remote methods, account login
is denied, and startup progress, local picker and local text sharing still work.
Each request completes once. This is behavioral host evidence, not ArkTS type
checking, packet capture, or installed OHOS acceptance.

The same regression rejects the historical unguarded EntryAbility and a source
variant with OFFLINE_ONLY=false; both exit1 on an unexpected browser invocation.
It also asserts zero argument reads for every refused request. An optional
source-path argument supports checking the exact staged platform file while
preserving unrelated working-tree changes.

The named global host-test queue and SQL device reservation122 are respected;
Python124 waits explicit device handoff. Final rebuild and native request/UI
verification remain open.
