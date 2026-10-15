# Flutter Lifecycle and Async Hooks

## 1. Scope / Trigger

Use for listeners, post-frame initialization and asynchronous page work.
This app uses StatefulWidget lifecycle methods; it has no React hooks,
flutter_hooks, HTTP query cache or server-data hooks in its dependencies.

## 2. Existing Hooks

`_PythonToolsPageState.initState` registers a ProjectStore listener and schedules
the first scan with `addPostFrameCallback`. `dispose` removes the listener and
requests cancellation. `runWithAppStartup` uses `endOfFrame`,
`deferFirstFrame` and `allowFirstFrame` for native startup.

## 3. Contracts

- Pair listener registration with removal on disposal. Callbacks belong to the
  page; do not register another listener during each build.
- Check `mounted` before async state updates. `_refreshFiles` also checks
  `_fileLoadGeneration` so old scans cannot overwrite newer selection.
- Start initial scanning after first layout. Reset file selection and prior
  output on project change before awaiting the next scan.
- Retain the cancel callback. Dispose requests it; if a run handle arrives after
  disposal, request cancellation immediately.
- Use `finally` for operation-state cleanup and first-frame release. Bootstrap
  failure must still call `allowFirstFrame`.
- Use `unawaited` intentionally for progress/cleanup that cannot be awaited.
  Operations affecting state or visible failures still need observation.

## 4. Validation & Error Matrix

| Race / failure | Required outcome |
| --- | --- |
| Switch project during scan | Only newest generation applies |
| Dispose during scan | No late state update |
| Run handle arrives after disposal | Late handle canceled |
| Operation throws | Working state clears while mounted |
| Bootstrap throws after deferral | First frame still released |

## 5. Good / Base / Bad Cases

- Good: slow old discovery completes harmlessly after a newer scan.
- Base: tools schedule a scan after the first frame.
- Bad: retain listeners after disposal or release frames only on success.

## 6. Tests Required

Use `test/python_tools_page_test.dart` for operations and
`test/startup_test.dart` for startup success/failure. Directory I/O needs bounded
real-time polling inside `tester.runAsync` with frame pumps. Remove mocks in
teardown. Running-work changes require interruption/recovery coverage in
`test/python_lifecycle_test.dart`.

## 7. Wrong vs Correct

```dart
// Wrong: an old result modifies a newer selection or disposed page.
setState(() => _files = files);
// Correct: check both page and request lifetime.
if (!mounted || generation != _fileLoadGeneration) return;
setState(() => _files = files);
```

References: [page lifetime](../../../lib/python_tools_page.dart),
[startup lifetime](../../../lib/app_startup.dart).
