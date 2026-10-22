# Direct tools and source analysis design

Extract a reusable PythonToolsBody from the existing page's operation state.
The root tools builder embeds that body without nested Scaffold/AppBar; the old
page wraps it for existing navigation callers. Keep common terminal/tools access
through supported shared extensions. Add module/package controls consuming the
single module service, not another installer. Operations retain captured project
and file identities, async generations, cancellation and disposal handling.

Add a source-based compile-only runner entry alongside the file-based method.
The source request carries exact text/project/entry path into existing channel
or FFI compilation without writing temporary user files, running imports or
executing code. Centralize result validation and busy state across run/check/
compile/debug so the single native VM cannot accumulate stale syntax checks.

Implement CodeAnalyzer against C's frozen `services/code_analysis.dart` and
StudioProfile hook. Select supported project-owned Python snapshots, preserve
exact CRLF/Unicode text and return real compiler failures. MicroPython's current
exception records a line, not a column; compute the corresponding snapshot line
as UTF-16 half-open offsets. Out-of-root/unresolved locations and unavailable
backends are explicit results. Native syntax checking is not broad semantic
linting or undefined-name analysis; do not claim checks the compiler did not do.

Tests cover both actual compile-only no-side-effect behavior and UI interaction;
mocked channel mapping alone cannot establish syntax correctness. C owns shared
debounce/stale-result rendering, while Python enforces single-flight/busy
behavior at its runtime boundary. Ordinary run behavior and the old page API
remain compatible. Debug widgets wait for the debugger child/common contract.
