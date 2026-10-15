# Frontend Quality Guidelines

## 1. Scope / Trigger

Use before reviewing/committing Flutter profile, startup or tools changes.
`analysis_options.yaml` uses Flutter's recommended lints via `flutter_lints`;
direct package imports require direct pubspec dependencies.

## 2. Reference Checks

| File | Evidence |
| --- | --- |
| `test/python_app_test.dart` | Profile, paths, loader/results and exits |
| `test/python_tools_page_test.dart` | Real discovery, controls and phone/desktop layout |
| `test/startup_test.dart` | Deferred frame, progress, readiness and failure release |
| `test/python_ffi_test.dart` | Argument/loader checks and real-library integration |
| `test/python_lifecycle_test.dart` | Native interruption, recovery and artifacts |

## 3. Contracts

- Reuse shared Material UI, stores and profile extensions. Python changes must
  not expose unrelated language templates or offline network flows.
- Preserve actual files/paths, finite `input.txt`, streams, native exits and
  supported cancellation. A stub result is not a runtime.
- Check loading/error/empty/success states and duplicate-action prevention.
  Changes to async paths require disposal/selection-race review.
- Keep tools usable at 360x800 and 1200x800 with long paths, visible status,
  icon tooltips and selectable output.
- Discover real temporary files. Inject MethodChannel transport in channel
  tests on desktop; automatic desktop transport intentionally selects FFI.
- Await I/O through `tester.runAsync` with bounded polling. Pump initial loading
  before deciding scans finished. Reset views, profile, handlers and temporary
  resources during teardown.

## 4. Validation Matrix

| Scope | Verification |
| --- | --- |
| UI | Focused widget regression and complete analyzer/tests |
| Runner/channel | Actual payload fields and result mapping |
| Shared core | Owning core checks plus app checks |
| Native/platform | Backend VM/build/device gates plus Flutter checks |

## 5. Good / Base / Bad Cases

- Good: discover `src/main.py` from disk and exercise its tools control.
- Base: complete analyzer/tests pass after focused validation.
- Bad: claim installed VM correctness from canned mocks or weaken lint rules
  to conceal diagnostics.

## 6. Checks Required

Run `flutter analyze` and `flutter test` in the Python app. Use `--no-pub` when
dependencies are already resolved; avoid concurrent Pub in one package. Format
changed Dart and inspect owned diffs. Record partial scope/skips accurately.
Docs-only changes need content/link/diff verification instead of new
implementation-mirroring tests.

Stage explicit owned files and let the coordinator serialize Conventional
Commits when workers share a checkout. Do not include another worker's pending
product/platform changes.

## 7. Wrong vs Correct

Wrong: wait only on the fake clock for real `Directory.list` I/O.
Correct: use `tester.runAsync`, frame pumps and bounded polling, as
[tools tests](../../../test/python_tools_page_test.dart) do.
See [Python Workflow](./python-workflow.md) and
[Backend Quality](../backend/quality-guidelines.md) for remaining gates.
