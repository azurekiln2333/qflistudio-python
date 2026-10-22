# Offline standalone language apps completeness

## Goal and source

Make the independent offline language applications useful, reliable mobile IDEs.
The complete user request is the attachment
`C:/Users/lichengyu/.codex/attachments/f25c5895-1de8-4941-b863-6bfa0b63cb3c/pasted-text-1.txt`.
This parent retains the complete request and cross-product evidence ledger.
Following the October 22 coordinator messages, this workspace implements Python;
C coordinator w1R:p1 integrates common core and other coordinators own their
products. Python completion alone cannot close the unified goal.

## Confirmed background

- App branch: `release/python-storefront-20261015`; initial HEAD `5674a30`.
  Existing icons, signing, native startup, tools registration and tests are dirty
  before this task. Preserve those edits and stage only reviewed owned changes.
- Shared core observed at `6441a5a`; it contains independently owned WIP.
  The explorer/history changes are not from this session or its researchers.
- Python engine is real MicroPython 1.24.1. Fresh host execution reports 116/120
  existing example passes. Examples 117-120 fail on missing sysconfig,
  dataclasses, os and threading. Tutorial code matches, but the no-input tutorial
  flow passes only115/120. Among186 exercise answers, ten fail standalone
  compilation; complete setup and semantic execution remain to be verified.
- The module probe finds 17 available modules among 42 tested names. `pip`,
  `mip` and many common stdlib modules are absent. A project `lib/` module is
  importable only after explicitly adding that directory to `sys.path`.
- Current Python tools expose a second-level "检查与运行" card, and syntax
  checking reads the saved file. The user requests direct tools and unsaved
  editor diagnostics. Sources and exact anchors are in `research/`.
- `hdc list targets` is currently empty. Host DLL execution, channel doubles,
  old reports and successful HAP packaging are not OHOS installed-runtime proof.

## Requirements and ownership

| ID | Observable requested outcome | Implementation owner |
| --- | --- | --- |
| R1 | Follow Trellis; use scoped collaborators; do not overwrite shared core or other workers. | Every coordinator; this parent records Python scope. |
| R2 | Check every existing tutorial/example and its runnable answer/project on the current OHOS runtime, fix failures and lost input/import fixtures, then expand content. | Each product; Python content child. |
| R3 | Add more than 100 substantive new examples, with no filler or untested code; Python target is 180 new paired topics, at least 300 pairs total. | Each product; Python content child. |
| R4 | Filter tutorial/example pages by language and show language circles near titles, including separate C/C++ choices. | C common-core owner. |
| R5 | Expose language-specific useful offline tools directly on the Tools tab; remove an unnecessary second-level feature-card menu. | Each product; Python tools child. |
| R6 | Diagnose actual unsaved editor source, underline reported locations and show navigable Problems with honest failure/unavailable state. | C owns common API/UI; each product owns analyzer. |
| R7 | Preserve explorer expansion across sidebar reopen; provide a persistent multi-project workspace with separate roots. | C common-core owner; explorer/history WIP attribution pending. |
| R8 | Deliver feasible genuine offline breakpoints/stepping and usable Problems, Output, Debug Console and Terminal; Ports appears only for a real supported local process use case. | C owns common surfaces/contracts; product runtime owners. |
| R9 | Check highlighting for all supported languages, including self-authored C/C++ headers and mixed-source imports. | C common/core and C runtime owners; Python verifies imports/highlighting integration. |
| R10 | Provide usable offline Python module management and common bundled modules; evaluate pip within the actual sandbox without adding online flows. | Python modules child. |
| R11 | Standalone apps stay offline. Network-dependent tools, package downloads, remote debugging, cloud and port-forwarding flows are excluded. | Every product; Python package/manifest audit. |
| R12 | Run relevant tests, preserve evidence and commit with Conventional Commits; attempt authorized non-force push and verify remote OIDs. | Each repository coordinator; this parent owns Python integration/release. |

## Python acceptance criteria

- [ ] P1 / R1: Four children have complete plans and curated context; file owners
  and dependencies are published in `qfli-core-release-sync`. C-owned common
  files are changed only by C; Python asset generation uses a serialized window.
- [ ] P2 / R2: A fresh exhaustive inventory includes shipped examples, all
  tutorial lesson code, exercise answers and referenced multi-file/input
  fixtures. Every runnable unit passes the actual embedded runtime. Invalid or
  incomplete teaching solutions are repaired, not hidden by runtime labels.
- [ ] P3 / R2: The same inventory and hashes run through the final installed
  OHOS HAP via real ArkTS/NAPI/VM, with zero failed, omitted or CPython-only
  units. Imported examples retain input and project fixtures and run normally.
- [ ] P4 / R3: After the existing-content OHOS baseline passes, add at least 180
  distinct substantive Python topic pairs. Final count is at least 300; all
  code and solutions pass host plus OHOS execution with exact expected results.
- [ ] P5 / R10: Common offline modules have documented API coverage, provenance
  and real execution tests. Users can inspect/install/check/remove compatible
  local packages for a selected project; installation neither downloads nor
  executes packaging scripts, crosses project roots or replaces unrelated files.
- [ ] P6 / R5: Syntax check, run, compile, stop, runtime/module inspection,
  local package operations and content audit are directly usable in the Tools
  tab at 360x800 and 1200x800, including loading/error/empty/busy states.
- [ ] P7 / R6: The shared CodeAnalyzer adapter checks exact unsaved snapshots
  without execution or user-file writes, reports genuine line ranges, handles
  CRLF/Unicode and rejects stale results or an occupied/unavailable VM honestly.
- [ ] P8 / R8: The native debugger actually pauses at project breakpoints,
  continues, steps and stops; event/session lifetimes and repeated-run recovery
  are tested. It integrates with the C-owned surfaces without fabricated values.
- [ ] P9 / R4,R7,R9: Python integration checks show correct filtering/badges,
  highlighting, retained explorer expansion and multi-root isolation after the
  common-core owner delivers them. Unverified common features stay open.
- [ ] P10 / R11: Package/tools/editor flows contain no network operation or
  download fallback. Inspect actual release permission/configuration and record
  the disposition of the current OHOS INTERNET permission.
- [ ] P11 / R12: App analyzer/tests, real native regressions, OHOS library
  dependency/ABI inspection, ArkTS parity and signed HAP pass. Record distinct
  host/build/device results, focused reviewed commits and actual push outcomes.

## Task map and dependencies

| Child | Deliverable | Explicit dependency |
| --- | --- | --- |
| `10-22-python-offline-modules` | Bundled module catalog, project-local offline packages, native import paths. | Current module/runtime probe; serial ownership of native import files. |
| `10-22-python-content-ohos` | Exhaustive baseline repairs, fixtures, OHOS audit harness, 180 new pairs. | Module APIs before module-dependent lessons; existing OHOS baseline before expansion; C content write window. |
| `10-22-python-offline-tools` | Direct Tools content, module/package controls, unsaved-source analyzer. | Module service and frozen C CodeAnalyzer API; no common-core implementation. |
| `10-22-python-offline-debugger` | Native trace-driven breakpoint/step/continue/stop with real events. | Module native batch committed before shared native files; C debug contract before UI hookup. |

This parent directly owns integration, evidence aggregation and Python commits.
The cross-product ledger is `research/unified-requirements-ledger.md`; remaining
product owners are retained even when their implementation is outside Python.

## Scope constraints and decisions

- Retain the actual MicroPython engine and platform adapters. CPython execution
  cannot substitute for embedded compatibility. Repair/replace the four
  external-only lessons with useful offline equivalents while preserving IDs.
- Use compatible local pure-Python sources/packages and a tested bundled subset.
  Do not advertise full pip/PyPI/CPython wheel or stdlib compatibility.
- Breakpoint debugging is in scope where the native trace facility permits it;
  logs and a Stop button alone do not satisfy that requirement.
- C owns shared editor/layout/schema files. Python-specific authored curriculum
  is a narrow requested allocation; aggregate JSON generation must be serialized.
- No account/cloud/download/remote debugger or forwarding features. No signing
  credential rotation, destructive device reset, force push or unrelated cleanup.
- Device availability is a validation prerequisite, not permission to shrink
  the requirement. Missing OHOS proof keeps the corresponding criteria open.

## Planning gate

No unresolved product decision is required: the user specified offline operation,
direct tools, all-sample correctness and collaborative ownership. Technical
risks and device prerequisites are recorded in design/implementation artifacts.
The final planning summary still requires review before `task.py start` under
the project workflow. No product code was changed during this planning phase.
The final convergence pass retains R1-R12, P1-P11, every child dependency and
all known runtime/fixture failures without reclassifying failures as completion.
