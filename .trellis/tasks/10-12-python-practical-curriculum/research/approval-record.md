# Approval record

## 2026-10-12 — user approved final plan and sibling scope

The user explicitly approved the final plan and the **minimal sibling
`qfli_studio_core` modification scope** and instructed implementation to start
directly. `task.py start` succeeded; task status = `in_progress`.

Approved scope (this task owns):

- `qfli_studio_core/tool/python_content/*` (authored content module, staged files)
- `qfli_studio_core/tool/generate_python_content.dart` (generator)
- `qfli_studio_core/tool/verify_python_content.dart` (real-runtime verifier)
- Python portions of `qfli_studio_core/assets/content/{tutorials,examples}.json`
- `qfli_studio_core/assets/tutorials/python.json`
- refresh-only change (if needed) in
  `qfli_studio_core/lib/services/example_code_store.dart`
- focused tests in `qfli_studio_core/test/`
- task research/verification records under this task dir

Constraints confirmed by the user:

- **Refresh-only**: keep all `_custom` user records; never delete by
  language/type. No cleanup/deletion flow.
- Other languages are being edited concurrently in the same shared core by other
  workers. **Do not overwrite or roll back their changes.** Only this task merges
  the Python asset segments. Every generation reads the live files and asserts
  non-Python records are byte-identical before and after; on concurrent change,
  re-read and merge. Never restore a whole file from a stale backup.
- Keep existing OHOS / icon / native-library dirty changes untouched.
- Do not commit, do not modify other languages or the native runtime, no
  full-disk scans.
- Embedded examples must actually run on the real MicroPython DLL; CPython-only
  lessons run separately in CPython and are never claimed as embedded.

Decision D1 (approve shared-core write) is recorded as approved above. D2 is
decided: refresh-only, preserve all user records.
