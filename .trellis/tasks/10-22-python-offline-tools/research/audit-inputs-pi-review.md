# Audit inputs verifier: PI independent review

Date: 2026-10-26. Reviewer: PI trellis-check (audit-inputs batch).
Scope: `tool/python_audit_inputs.py`, `test/python_audit_inputs_test.py`, and
consistency of the three `tool/prepare_python*_audit.py` consumers.

No real process control, Flutter, SDK, native build, HAP, signing or device
command ran. Every check below is a source read, a temporary-directory synthetic
Python test, or a read-only reconstruction against this checkout.

## Reviewed identities (after the local fixes)

| File | SHA256 |
| --- | --- |
| `tool/python_audit_inputs.py` | `f139c43e9457bdb851b69d80e4f6955a6aea3121c67cefc8fb3b396948d24d50` |
| `test/python_audit_inputs_test.py` | `2c57e3dbd8d6594685c5e6d095d11fcb8bc263aabb01bda8a7a3ac110ad83b76` |

The pre-fix behavior was observed before the edits; the two files are untracked
in this checkout, so no committed baseline hash exists.

## Commands actually run

```text
PYTHONPATH=. python test/python_audit_inputs_test.py
  Ran 8 tests, OK (was 6 before this review)
PYTHONPATH=. python <temp>/audit_inputs_matrix.py    # behavior matrix, temp dirs
PYTHONPATH=. python <temp>/consumers_probe.py        # consumer-shape reconstruction
PYTHONPATH=. python <temp>/verify_consumers.py       # verify_inputs on the three shapes
```

The `PYTHONPATH=.` prefix matches the existing `test/python_native_provenance_test.py`
convention. `python test/python_audit_inputs_test.py` alone fails with
`No module named 'tool'`, and `python -m unittest test.python_audit_inputs_test`
fails because the stdlib `test` package shadows the repository `test/`
directory. This is shared with the peer test, not new to this batch, but the
batch's own runner must set the repo root.

## Behavior matrix (temporary inert files, no process)

| Scenario | Result | Notes |
| --- | --- | --- |
| unchanging inventory + explicit extra | ACCEPT `(1, 1)` | explicit extra outside scan dirs is validated by digest |
| new file under a scanned tree (`lib/`) | REJECT | addition detected |
| new file under scanned `core` tree | REJECT | addition detected |
| declared input changed | REJECT | `Declared build input changed or disappeared` |
| declared input removed | REJECT | `disappeared`; this is the repaired gap |
| declared input outside scan dir, changed | REJECT | explicit native input covered |
| declared input outside scan dir, removed | REJECT | explicit native input covered |
| **new sibling file in a declared-only directory** | **ACCEPT** | see F3 |
| top-level evidence not a JSON object | REJECT (was `AttributeError`) | fixed to `ValueError` |
| declared name `../`, `..\\`, `C:/`, leading `/` | REJECT (was ACCEPT) | fixed |

## Findings

### F1 (fixed): non-object evidence raised `AttributeError`

`verify_inputs` called `value.get(label)` directly, so a list, string or `None`
evidence crashed with `AttributeError` instead of a clear rejection. Now
`if not isinstance(value, dict): raise ValueError("Build input evidence must be
a JSON object")`. New test `test_non_object_evidence_is_rejected`.

### F2 (fixed): escaping declared names were accepted

The removal/change loop built `source = base / name` with no containment guard.
A declared key such as `../outside.txt` whose digest matched an out-of-root file
was accepted. Added `relative_input_name`, mirroring the preparers'
`contained_file` guards: reject empty, `\`, `:`, and any empty/`.`/`..` segment.
New test `test_escaping_declared_names_are_rejected`.

### F3 (P2, documented limitation, not fixed): additions in declared-only directories

The contract in `audit-binding-repair-boundary.md` requires rejecting additions
"including explicit native inputs declared by a preparer outside the
automatically discovered directories". `collect_inputs` only scans
`lib`, `assets/python_stdlib`, `ohos/entry/src/main`, `native/ohos` plus a fixed
explicit name list. The debugger preparer declares 13 further native inputs
(`native/src/*`, `native/port/*`, `native/tools/*`, `native/CMakeLists.txt`,
`native/micropython_embed/*`) that are outside that scan. `verify_inputs` cannot
see a **new** file in those directories, because a flat declared digest map
carries no directory universe. Measured: adding `native/src/new.c` after
evidence generation is ACCEPT.

The literal addition requirement is not satisfiable without the preparer
recording its scan roots in the evidence. The note's stated repair target was
the removed-input gap, and that gap is closed for every declared input. A
heuristic directory scan is rejected here: deriving roots from declared paths
would force scanning `tool/` and the project root (because `pubspec.yaml`,
`tool/*.py` are declared), rejecting unrelated new files and breaking normal
development.

### F4 (consistency): merge vs replace across the three preparers

Reconstructed against this checkout (`collect_inputs` product = 103 files,
shared = 200 files):

| Consumer | Strategy | Declared-but-undiscovered names | Verdict |
| --- | --- | --- | --- |
| `prepare_python_content_audit.py` | merge (`update`) | 0 of 12 manual names | redundant but safe |
| `prepare_python_debugger_audit.py` | merge (`update`) | **13 of 28** native names | merge is required |
| `prepare_python_module_audit.py` | replace (`=`) | 0 of 11 manual names | lossless today |

All three shapes pass `verify_inputs` on the current checkout, and a debugger
native change is correctly rejected. The residual risk is structural, not
observable today:

- `prepare_python_module_audit.py` builds an 11-name `sourceDigests` dict and
  then overwrites it on the next statement. The dict is not fully dead: reading
  those files raises `FileNotFoundError` if one is missing, so it still acts as
  a required-file existence precheck that `collect_inputs` does not provide
  (`collect_inputs` silently skips missing explicit names). Copying the
  replace style into the debugger preparer would silently drop all 13 native
  inputs.
- `prepare_python_module_audit.py` hardcodes
  `root.parent / "qfli_studio_core"` and has no `core_root` parameter, while
  content and debugger accept `core_root`. The module preparer therefore cannot
  be exercised against a temporary core tree.

Recommendation (not applied, consumer files left untouched): extract one shared
`merge_explicit_inputs(product, explicit_names)` helper and one required-file
existence check used by all three, and give the module preparer the same
`core_root` parameter. Do not remove the module manual dict without replacing
its existence precheck.

### F5 (test coverage)

The suite now covers: unchanged inventory plus explicit extra; added product
source; added core source; changed product/core/extra source; removed
product/core/extra source; missing and empty inventory; non-object evidence;
escaping declared names. It does not and should not assert the F3 acceptance as
a passing contract. The returned counts are the current discovered counts
(`103, 200`), not the declared total; the extra explicit input in
`test_unchanged_inventory_and_explicit_extra_are_valid` is intentionally not
counted.

## Integration state

- The production gate still runs `python_audit_inputs.py --inputs` before and
  after the build (`tool/build_python_ohos_audit.ps1:400` and `:419`), so F1/F2
  harden the live gate.
- `Assert-AuditSources` in the builder remains the per-declared-file digest
  check and is unchanged; it does not detect additions or removals by itself.
- `tool/python_audit_inputs.py` is itself a declared product input, so this edit
  invalidates any `inputs.json` generated before it. Regenerating evidence is
  required, which is the intended self-binding behavior.

## Not run

- Any real Native HAP build, Flutter, SDK, signing, emulator or device action.
- The PowerShell builder synthetic test (`test/python_ohos_audit_build_test.ps1`);
  it does not call `verify_inputs` and was not part of this batch.
- No consumer file was modified; no commit or staging was performed.