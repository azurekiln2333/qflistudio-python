# Backend Development Guidelines

This app embeds MicroPython and adapts it to Flutter through native bridges or
FFI. Shared persistence belongs to adjacent `qfli_studio_core`. There is no
app-owned HTTP service or database.

## Guidelines Index

| Guide | Description | Status |
| --- | --- | --- |
| [Native Python Runtime](./native-python-runtime.md) | VM, I/O, lifetime, channel and verification | Documented |
| [Python FFI](./python-ffi.md) | Desktop/Apple packaging, C ownership, Windows reader | Documented |
| [Android Build](./android-build.md) | NDK, JVM budgets, APK and installed-runtime checks | Documented |
| [Directory Structure](./directory-structure.md) | Native, adapter, generated and shared ownership | Documented |
| [Local Persistence](./database-guidelines.md) | Shared JSON stores/project files; no ORM/migrations | Documented |
| [Error Handling](./error-handling.md) | Program failures, unavailable backends and cleanup | Documented |
| [Quality Guidelines](./quality-guidelines.md) | Real native evidence and review/commit boundaries | Documented |
| [Logging Guidelines](./logging-guidelines.md) | Program streams, platform tags and evidence | Documented |

Status describes documentation, not a claim that every target device passed
current release validation. Record actual outcomes in the task.

## Pre-Development Checklist

1. Read [Directory Structure](./directory-structure.md),
   [Error Handling](./error-handling.md) and [Quality Guidelines](./quality-guidelines.md).
2. Read [Native Python Runtime](./native-python-runtime.md) for C/C++, ArkTS,
   channel, cancellation, artifact or runner changes.
3. Read [Python FFI](./python-ffi.md) for bindings/desktop/Apple work and
   [Android Build](./android-build.md) for JNI/Gradle/package changes.
4. Read [Local Persistence](./database-guidelines.md) for shared file ownership
   and [Logging Guidelines](./logging-guidelines.md) for diagnostics.
5. Read [Python Workflow](../frontend/python-workflow.md) when UI is involved
   and the [shared thinking guides](../guides/index.md).
6. Confirm exact repository, worker ownership and mirrored paths. Coordinate
   shared-core changes with other consumers before editing.

## Quality Check

Run focused regressions, full Flutter analyzer/tests and applicable real native
checks. Packaging additionally requires dependency/ABI inspection and separate
installed-device evidence. Compare ArkTS hashes. Record unavailable hosts/devices;
a successful build does not close their runtime gates. Maintain English docs
with concrete source/test references.
