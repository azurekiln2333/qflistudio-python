# Upstream package contract and the standalone offline boundary

Observed: 2026-10-26 Asia/Shanghai. This is source/documentation research, not
an import probe, native build, package installation or device result.

## Primary references

- MicroPython 1.24.0 package reference:
  `https://docs.micropython.org/en/v1.24.0/reference/packages.html`
- MicroPython 1.24.0 bytecode reference:
  `https://docs.micropython.org/en/v1.24.0/reference/mpyfiles.html`

The application embeds 1.24.1. These are the matching minor-version reference
pages; the actual 1.24.1 port configuration and execution remain authoritative.

## Upstream facts

MicroPython documents `mip` for micropython-lib packages rather than CPython's
`pip`/PyPI ecosystem. Its documented index and GitHub installation examples
fetch packages. Host-side `mpremote mip` is a separate deployment workflow.
The documentation also describes copying module files onto the filesystem and
making them discoverable through `sys.path`.

The bytecode reference describes compatibility constraints on `.mpy` format,
features and native architecture. It documents `sys.implementation._mpy` as
runtime compatibility information. A filename ending in `.mpy` alone is not
proof that another target can load it.

## Current repository contract

The parent R10/R11 and modules M3/M5 require local-only operations without
package downloads, setup/build scripts or a general CPython environment.
The implementation already uses this boundary:

- `lib/python_module_catalog.dart` records the 17 built-in module entries.
- `assets/python_stdlib/manifest.json` records ten bundled source modules.
- `lib/python_packages.dart` accepts local source files, directories and bounded
  archives. Pure wheel metadata must explicitly match its supported tags.
  `Requires-Dist` is parsed and checked locally, never fetched.
- The installer uses the actual VM compile callback before replacing owned
  package files. Static dependency checks do not prove all dynamic imports.
- `lib/python_tools_page.dart` exposes these project package operations directly.

The custom local wheel reader is an application feature; it is not upstream
`mip`, a working `pip`, or a promise of CPython library compatibility. No network
index, host mpremote deployment or package downloader belongs in the app.

## Verification consequence

Keep the local-source and bundled-module design. Do not add an online pip/mip
fallback to repair a missing import. Report incompatible dependencies/APIs
honestly. Existing host reports do not close the installed OHOS import gate.

The native lifecycle suite contains an incompatible-bytecode/recovery test in
`test/python_lifecycle_test.dart`. Current native regressions and both OHOS ABI
builds must verify the real port. A host-generated artifact cannot substitute
for target compatibility or installed-app execution.

## Retrieval evidence

Both official pages returned HTTP200 during this review. Cached HTML and
retrieval metadata are under ignored `build/upstream-reference-review/`.

| Reference | Bytes | SHA256 |
| --- | --- | --- |
| packages | 32514 | `196d9e6472f1945edeb478ebb79544b393a6df2485b3de993dbf90a937d5e070` |
| mpyfiles | 28056 | `04b60193f97cde91c4095d94d90b380e504af13f2a2995d8a0bfe12533de9275` |
