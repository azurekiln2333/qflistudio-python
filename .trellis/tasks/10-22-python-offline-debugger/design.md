# Native trace debugger design

Use upstream trace support through explicit port configuration and a product
trace/control adapter. Keep legacy run/compile ABI and introduce optional debug
capabilities/session handles. Confirm required upstream compiler/frame options
and actual stack/locals support with a scratch native build before exposing a
capability. Do not patch Python syntax or simulate breakpoints with stdout.

The native execution worker owns the VM. A line/call/return trace hook publishes
bounded events with session ID, monotonic sequence, normalized project file and
actual line/stack; at a matching breakpoint or step condition it pauses on a
native condition variable. Continue/step/stop commands signal from another
thread without touching VM objects. Stop wakes paused waits and converges with
existing cancellation. Never block the ArkTS main thread or read VM state from
the control thread. Snapshot supported frame data inside the worker only.

FFI and NAPI/JNI adapters expose optional session controls/events using each
platform's asynchronous worker path. Teardown owns native handles until the
worker settles, makes late commands harmless and releases pause waits on error
or disposal. Runtime busy state is shared with tools/analyzer. Stream partial
debug events separately from program stdout/stderr and preserve exit status.

C owns common debugger/provider/panel types. Agree the public schema before UI
integration and adapt the Python session rather than adding a parallel core API.
Actual frame-local introspection is conditional on native support; breakpoint,
step, continue, stack and stop remain required even without unsupported watches.

Validate trace semantics using deterministic real programs and independent
control threads, then repeat through installed OHOS. Cover loops, nested calls,
imports, exceptions, pause cancellation, bounded events and reuse. If a platform
prerequisite is missing, keep the corresponding acceptance gate open rather than
substituting a log panel. Module/native changes land first to avoid shared files.
