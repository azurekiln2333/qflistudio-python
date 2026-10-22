# Unified offline IDE: integration design

## Boundary and ownership

The gap is end-to-end offline usefulness: available editor/content surfaces can
present code which the embedded runtime cannot execute, while Python module
and tool flows do not fill those gaps. Generic UI stays in shared core, and
Python owns its interpreter port, app adapters, local module service and content.

Use `D:/MyNewProjects/qfli-core-release-sync.md` and the global Trellis channel
as the coordination surface. C coordinator w1R:p1 owns common content pages,
explorer/workspace, analysis/panels and highlighting. This session's researchers
write only distinct research files. Initial dirty Python/platform edits and the
unattributed core explorer/history batch are preserved.

## Data and runtime paths

1. Authored Python topic -> paired shipped tutorial/example -> import with
   explicit stdin/project fixtures -> selected editor file -> Python runner.
2. Runner prepares versioned bundled pure-Python modules inside the selected
   project; native sys.path searches entry directory, project root, project
   `lib/` and the project's prepared bundle directory in a documented order.
3. Local package service validates a user-selected local source/archive,
   stages files, compile-checks without executing setup/build scripts, and
   commits an install plus its owned-file manifest. No network resolver exists.
4. Editor immutable snapshots -> product CodeAnalyzer -> native compile-only
   path -> genuine location diagnostics -> shared Problems/underline UI.
5. Native trace hook -> session-owned bounded events and pause/resume commands
   -> product debugger adapter -> common debug UI. A run and a diagnostic
   compile cannot concurrently own the single native VM.
6. Exhaustive catalog audit materializes each unit's fixtures in an isolated
   project and invokes the actual runner on OHOS; expected stdout/exit/error
   and code/artifact hashes are saved with device, library and HAP provenance.

## Shared contracts

C froze `services/code_analysis.dart`, `StudioProfile(codeAnalyzer: CodeAnalyzer?)`
and immutable request/document/diagnostic/result types. Offsets are zero-based
UTF-16 half-open ranges into the exact unsaved snapshot, including CRLF.
The current native syntax exception has file/line precision only: underline
the validated source line and never invent token columns. Results distinguish
successful empty diagnostics from `unavailableReason`. Debounce, single flight,
revision checks and VM-busy handling prevent stale results or an infinite run
from accumulating diagnostic jobs. See C's authoritative analysis task design.

The debug provider contract is not yet delivered; C owns its public schema.
Python prepares native events without defining a competing shared interface.
Content fixture import crosses shared boundaries; request a narrow common-owner
change instead of patching adapter/model/import service concurrently.

## Content compatibility

Current 120 topic IDs are stable. Replace CPython-only lessons with compatible
teaching code and validate every exercise answer in an explicit setup/fixture
context; compile success alone cannot prove a runnable solution. The target is
180 new substantial pairs after the original content passes installed OHOS.
Topics use deterministic inputs/results and avoid assuming CPython stdlib,
networking, interactive stdin or host filesystem/process access. Preserve all
non-Python rows and every persisted custom/edited example.

## Verification and provenance

Evidence levels are separate: source inventory, actual host DLL execution,
channel behavior with doubles, fresh OHOS native build, packaged HAP inspection,
and installed OHOS runtime. Only the last closes device acceptance. A missing
target cannot be papered over with a host pass. Current hdc output is empty.
Record revisions and hashes to ensure regenerated assets/native SO are the
ones in the tested HAP. Whole-app import/run and offline UI checks supplement
the per-snippet audit.

## Compatibility and rollback

Keep legacy ABI entry points and the ordinary run path. New import paths are
project-local; bundles/installed packages have separate manifests and do not
replace user files silently. Keep debugger additions optional/capability-based.
Serialize native generator/build mutations and aggregate-asset generation.
Rollback reviewed owned commits or package transactions, preserving unrelated
WIP and user custom records. No reset/clean/data clear/credential changes.

## Risks retained in scope

- Importable pure Python can still depend on unsupported language/stdlib APIs;
  use explicit tested compatibility rather than claiming general wheel support.
- MicroPython trace support is compiled off, so a genuine debugger requires
  native work, async pause control and cleanup tests, not UI decoration.
- Missing input fixtures and exercise setup are product defects independent of
  the 116 passing host examples.
- Core API delivery and device availability constrain integration order.
  They do not remove requested deliverables or permit a completion claim.
