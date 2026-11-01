# Independent Python tools and diagnostics review

Date: 2026-10-22. Reviewer: repair_python_basics, separately assigned after the
content repair batch. No subagent was spawned for this review.

## Scope and conclusion

Reviewed the tools PRD/design/implementation plan, applicable frontend/native
contracts, lib/python_tools_page.dart, lib/python_code_analyzer.dart,
lib/python_runtime_activity.dart, the runner/main diffs and corresponding
tools/provider/activity/profile/editor integration tests. The frozen shared
CodeAnalyzer contract and scheduler were read to verify responsibility at the
boundary; no shared-core file was changed.

One confirmed tools lifetime defect was fixed and regression-tested. No
additional confirmed defect remains in the reviewed behavior. This is host
source/test review, not installed OHOS acceptance.

## Confirmed finding and fix

The tools _stop catch originally checked only the operation generation and
project identity. A stop request can remain pending while the native run exits.
_execute then publishes the completed result and clears _working/_cancelRun.
If cancellation subsequently rejects, the old catch restored the finished
run's cancel handle and replaced its diagnostic with the late stop error.
The Stop button became enabled despite the completed operation.

The catch now also requires _working. Its current-operation/project guard
still permits retry after cancellation failure during a running program, while
completion, replacement and disposal retain ownership of their final state.

The new widget regression, late stop failure preserves completed run, uses an
injected controlled runner so it can independently complete execution before
rejecting cancellation. Before the fix it failed because the late diagnostic
appeared. After the fix it passes and checks the final exit/output, absent late
error, disabled Stop and available Run.

Only lib/python_tools_page.dart and test/python_tools_page_test.dart were
changed by this review, plus this note. No runner, profile, analyzer, native,
content, shared-core or generated file was changed. No commit was created.

## Behaviors reviewed

- The root tab embeds PythonToolsBody directly, retains terminal/common offline
  tools through the public sliver API, and keeps the legacy page wrapper.
  Project/file labels and selectable output use actual state and real runner
  results; project identity is captured before asynchronous operations.
- File scans reject stale generations, do not follow directory links and omit
  internal .qfli scripts. Project replacement/disposal invalidates operations
  and requests cancellation, including a run handle arriving later.
- Package callbacks capture the selected project and invoke checkSource.
  Transactions retain cancellation through the existing service; late package
  and picker results cannot update a replacement project's state. URI copies
  have page ownership and cleanup; unsupported URI directories are explained.
- The analyzer consumes exact immutable open Python snapshots, checks the
  active snapshot first, rejects conflicting/foreign/stale identities and never
  saves source, imports modules or executes the user's program.
- checkSource rejects malformed/truncated/operational responses as unavailable.
  Genuine SyntaxError/IndentationError locations must match the current file
  and a real snapshot line. UTF-16 ranges include neither invented token
  columns nor newline characters; empty EOF insertion ranges are supported.
- Default runner instances share the same non-queuing app-isolate activity
  gate. Acquisition precedes asynchronous probing/bundle preparation. Controlled
  results retain their lease until the actual exit future settles, including
  after stop requests, late backend failure and malformed results.
- Shared scheduler ownership is consistent with provider behavior: revisions,
  all captured texts, project switches and disposal invalidate late results;
  timed-out work retains its single lane until real completion.
- pythonProfile registers the direct tools tab and real PythonCodeAnalyzer;
  program stderr and unavailable reasons remain distinct from clean checks.

## Evidence and limits

Reviewed existing tests cover narrow/wide direct controls, common tools and
terminal, actual FFI package install/import/run flows, compile/stop and stdout/
stderr, cancellation/retry/disposal, late handles, project replacement, runtime
catalogs, empty/large-text layouts, exact unsaved snapshots, Unicode/CRLF ranges,
multi-buffer diagnostics, malformed/unavailable responses and real VM busy
rejection/recovery. The real provider editor integration checks Problems
navigation and repair without disk writes or program side effects.

The coordinator reported its complete serial suite at 206/206 and full analysis
clean immediately before this review. Those results predate this narrow fix.
The reviewer intentionally did not repeat the full suite or execute/rebuild the
Windows DLL while the advanced content worker owned that verification window.

New review checks:

- flutter test --no-pub test/python_tools_page_test.dart --plain-name "late stop failure preserves completed run":
  red before the fix; 1/1 passed after the fix. This is an injected-runner UI
  lifetime test, not native execution evidence.
- flutter analyze --no-pub lib/python_tools_page.dart test/python_tools_page_test.dart:
  no issues.
- dart format on the two edited Dart files: applied.
- git diff --check on the tools/analyzer/activity/runner/main scope: clean.

The coordinator should include this extra regression in its next serial full
suite. Installed OHOS Tools/editor execution, stop, module/package operations,
ordinary document-picker/sandbox access and final signed-artifact consistency
remain separate open gates. Host FFI and channel doubles do not establish
ArkTS/NAPI/device behavior or close the parent offline IDE goal.
