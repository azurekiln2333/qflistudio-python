# Frontend Development Guidelines

`qfli_python` supplies a Python StudioProfile, tools, runner and startup handoff
to shared Flutter `qfli_studio_core`. Generic editor/navigation, stores, terminals,
theme and curriculum assets belong to that package.

## Guidelines Index

| Guide | Description | Status |
| --- | --- | --- |
| [Python Workflow](./python-workflow.md) | Project/file selection, Python tools and checks | Documented |
| [Standalone OHOS Policy](./python-offline-host.md) | Native offline refusals, local platform handlers and package evidence | Documented |
| [Native Startup](./native-startup.md) | Progress, deferred frame and platform handoff | Documented |
| [Content Code Import](./content-code-import.md) | Shared catalogs/imports and authored curriculum | Documented |
| [Directory Structure](./directory-structure.md) | Language app versus shared-core ownership | Documented |
| [Component Guidelines](./component-guidelines.md) | Typed widgets, Material layouts/action states | Documented |
| [Lifecycle Hooks](./hook-guidelines.md) | Listeners, async generations, disposal/frame hooks | Documented |
| [State Management](./state-management.md) | Shared notifiers, local state, readiness/execution | Documented |
| [Quality Guidelines](./quality-guidelines.md) | Analyzer, widget/file checks, native evidence | Documented |
| [Type Safety](./type-safety.md) | Null-safe Dart, payload guards and native ABI | Documented |

Status describes documentation. Release readiness still needs the current
task's actual tests, builds and device outcomes.

## Pre-Development Checklist

1. Read [Directory Structure](./directory-structure.md) and
   [Quality Guidelines](./quality-guidelines.md) for ownership and checks.
2. Read [Python Workflow](./python-workflow.md) for profile/tools/runner work.
3. Read [Component Guidelines](./component-guidelines.md),
   [Lifecycle Hooks](./hook-guidelines.md), [State Management](./state-management.md)
   and [Type Safety](./type-safety.md) for affected widget/async boundaries.
4. Read [Native Startup](./native-startup.md) for bootstrap/platform startup and
   [Content Code Import](./content-code-import.md) for catalogs/imports.
5. Read [Native Python Runtime](../backend/native-python-runtime.md) for native
   payload changes, plus the [shared thinking guides](../guides/index.md).
6. Confirm repository/cwd and ownership. Account for other workspaces using
   shared-core live files before changing them.

## Quality Check

Run focused checks, then `flutter test` and `flutter analyze`. Verify selection,
loading/empty/errors, operation lifetime, actual native payloads and 360x800 /
1200x800 tools layout. Native changes also need backend VM/build/device checks.
Distinguish app diagnostics from program output. Maintain English documentation
with concrete source/test references.
