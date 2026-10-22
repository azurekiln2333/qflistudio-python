# Python tools, analyzer and debug contracts: dispatch summary

This compact source is curated for context injection. Full read-only evidence,
source anchors and primary-documentation references are retained in
`python-tools-contracts.md`; read that file on demand for detailed implementation.
Date2026-10-22. Shared core is exclusively owned by C w1R:p1.

## Direct tools

Current `lib/python_tools_page.dart:15-28` adds a generic card which pushes a
second page. The attachment requests functional controls directly on Tools.
Extract a reusable body from PythonToolsPage, embed it without nested
Scaffold/AppBar in toolsTabBuilder, and retain the old wrapper for other callers.
Keep common tools and terminal access via exported metadata/widgets; ToolsGrid
has no inline-header slot and owns scrolling, so avoid nested free scrolling or
duplicating common implementations. C owns any common extension needed.

The current page uses real project discovery, generation guards and cancel
lifetime. Preserve initial dirty changes. Run/compile/stop source selection,
bytecode disablement, stdout/stderr distinction, actual exit and module/package
controls must remain usable at360x800 and1200x800, including large text/paths.
Current native program output is buffered; do not claim streaming without a
real transport extension.

## Unsaved-source analysis

`lib/python_runner.dart:113-141` reads saved text. Add an app-owned checkSource
entry which sends exact immutable text/path/project to the existing native
compile-only transport, no user-file writes, execution or import resolution.
An owned new unsaved buffer need not exist on disk. Saved checks delegate after
reading disk. Reuse native invocation/result validation rather than another
MethodChannel in widgets.

C froze `services/code_analysis.dart`, StudioProfile(codeAnalyzer: CodeAnalyzer?),
immutable request/document/result and diagnostic types. Normative contract:
`../qfli_studio_core/.trellis/tasks/10-22-offline-editor-analysis/design.md` and
`D:/MyNewProjects/qfli-core-release-sync.md`. Do not implement another API.
Paths are normalized absolute owned paths. Ranges are UTF-16 half-open offsets
into exact captured snapshots, CRLF preserved. nonnull unavailableReason means
analysis did not complete; empty diagnostics is reserved for genuine success.
C owns debounce, stale validation, underline/Problems/navigation UI.

Native SyntaxError has file/line precision only
(`native/micropython_embed/py/parse.c:1354-1356`, `py/obj.c:149`). Map that line
to the exact snapshot's full-line range; do not invent a token column or line1.
Support Windows drive/backslash/space/Unicode paths and LF/CRLF/CR. An invalid
or unlocated operational failure cannot be rendered as a precise diagnostic.
This compiler check does not prove broad semantic linting.

The native mutex serializes run/check (`bridge.c:388-393`). Introduce one
Python-owned execution coordinator shared across default runner instances,
terminal/tools/analyzer/debug. At most one analysis is in flight and only the
latest pending request survives; a user run returns busy promptly. Release run
busy state on actual native exit, not the early ProgramRunResult handle. Never
cancel a user run to analyze. If startup/native-origin calls bypass the Dart
coordinator, add native try-lock/busy analysis rather than relying on a timeout
which leaves obsolete native work queued.

## Genuine debugging and panels

Current ProgramRunner has run/stdout/stderr/exit/cancel only. WebPreviewSession
debugStream is for web preview, not a breakpoint debugger.
Upstream `MICROPY_PY_SYS_SETTRACE` defaults off (`py/mpconfig.h:1517-1518`).
`py/profile.c:229-244` exposes f_back/f_code/f_globals/f_lineno but no f_locals.
Real breakpoints/step/continue are feasible native work: enable tracing in a
scratch build, implement bounded session trace events and responsive worker
pause/control signaling, integrate async native/FFI/platform adapters, then
consume C's shared debug provider contract. No fabricated locals/watches/eval.
Stop during pause must wake and settle the session, release tokens and allow
the next normal run. Keep the ordinary run path and offline operation.

Problems consumes compile diagnostics; Output separates program streams and
application events; Debug Console consumes actual debugger events; Terminal
keeps real sandbox commands and interpreter. Ports/remote forwarding/network
tunnels are not added in offline products absent a real supported local use.

## Meaningful verification

Test exact unsaved-vs-saved source, owned nonexistent buffer, compile-only with
side-effect code, Unicode/CRLF/EOF ranges, missing/malformed backend, VM-busy,
stale responses and disposal recovery. Use actual native compiler tests as well
as adapter doubles. Tools tests use real temp files and async discovery. Debug
tests must genuinely pause/step/continue/stop and recover, not check labels.
Inspect/build final OHOS SO/HAP/parity then exercise final installed app. Current
hdc is Empty; host/widget/channel results do not close any device gate.
