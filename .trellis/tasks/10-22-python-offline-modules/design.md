# Offline module and package design

Implement a Python-owned typed module catalog and local package service. Keep
module assets, upstream source/license and API verification together. Prepare
the versioned bundled source beneath `.qfli/python/bundled/` in the selected
project before execution, with digest-checked atomic replacement of owned
bundle files. Project-local user packages live under `lib/` with an install
manifest; package and bundle ownership are distinct. Avoid rewriting user code
to prepend sys.path, since that changes diagnostic and traceback locations.

Extend native sys.path initialization in `native/src/qfli_py_bridge.c` to include
entry directory, project root, project `lib/` and the prepared bundle root in a
documented order. Keep existing ABI and realpath-based project open behavior.
No general cross-project filesystem entitlement or networking is introduced.

The Dart service accepts only explicit local inputs. Inspect archive metadata,
reject traversal/links/unsupported binaries and conflicting ownership, stage
all files under the project, compile source without executing it, then commit
the file/manifest transaction. Failed commit restores previous owned content;
uninstall verifies ownership and preserves edited/unmanaged files. Dependencies
are local metadata and compatibility checks, never an online resolver.

Direct tools call this service; a clearly named local package command may share
the same service. Existing `python -m pip` rejection remains honest unless an
explicit supported local-only command is added and labeled with its actual
scope. Never call a custom package manager full pip.

Verification uses the real DLL and installed OHOS VM, including Unicode paths,
project precedence, packages with submodules, repeated runs, rollback and
incompatible API/dependency cases. Built-in module presence alone is not API
coverage. Build-time provenance fetching is separate from offline app behavior.
