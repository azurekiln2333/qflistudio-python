# Python offline modules and local packages

## Goal and background

Satisfy parent R10/R11 with useful, verified common modules and local package
management in the actual embedded interpreter. The fresh module probe in the
parent research reports 17/42 available modules, missing pip/mip, and no default
project-lib import path. Runtime remains MicroPython 1.24.1, not host CPython.

## Requirements

- M1: Show actual built-in/bundled/project packages, versions, origin and tested
  API scope. Missing modules have accurate explanations.
- M2: Bundle useful offline implementations for at least ten currently missing
  common modules. Candidate set includes bisect, csv, itertools, functools,
  statistics, copy, contextlib, textwrap, string, base64, datetime and unittest;
  choose upstream-compatible implementations with real API/edge-case tests,
  provenance and license. A stub import does not count as a module.
- M3: Support project-local compatible pure-Python `.py`, directory and archive
  packages. Install/list/show/check/remove must not need internet, run setup or
  build scripts, silently overwrite unmanaged files or affect another project.
  Reject native/unsupported binary wheels and incompatible source honestly.
- M4: Resolve entry/root/project `lib/`/bundled modules consistently on all
  app platforms; retain project file and lifecycle contracts.
- M5: Explain actual pip compatibility. There is no downloaded pip, PyPI flow,
  general CPython environment, virtualenv subprocess or fabricated pip success.

## Acceptance criteria

- [ ] Every claimed API has real VM positive/edge/error tests; at least ten
  missing modules become useful documented bundles and import on OHOS.
- [ ] Fresh installations and repeat runs resolve project packages automatically;
  imports do not persist between VM invocations and local precedence is tested.
- [ ] Local package transactions validate paths/files, preserve preexisting data
  on cancellation/compile/write failure, and remove only manifest-owned files.
- [ ] Package checks report unsupported dependencies/APIs without downloads.
- [ ] Python tests/analyzer, native import/resource regressions, OHOS build and
  installed-device module/package scenarios pass with current artifact hashes.

## Boundaries and dependencies

Own Python module assets/service/manifest, pubspec registration, import path
native changes and focused tests. C owns shared UI/types; the tools child owns
consumer widgets. Serialize native generated files before the debugger child.
No network/native extension installation or unrelated startup/signing edits.
