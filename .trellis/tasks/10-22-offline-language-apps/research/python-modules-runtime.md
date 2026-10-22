# Python module/runtime planning evidence

Date: 2026-10-22. Scope: read-only runtime probe and project-local research.
No product source, native library or shared-core file was changed.

## Actual module probe

`python-module-probe.json` records the real existing
`native/build/windows/qfli_py_ffi.dll`, version `1.24.1 (ecfdd5d)`.
Each module was imported in a fresh VM invocation using the app C ABI, not
CPython. Among 42 candidate names:

- Available: sys, math, cmath, json, random, time, re, binascii, heapq,
  array, collections, struct, io, errno, micropython, gc, builtins.
- Missing: os, pathlib, csv, itertools, functools, statistics, bisect, copy,
  contextlib, textwrap, dataclasses, decimal, fractions, datetime, typing,
  unittest, sysconfig, threading, pip, mip, socket, ssl, hashlib, zlib, asyncio.

Presence proves importability only; API coverage needs behavioral tests.
An actual `lib/audit_helper.py` containing VALUE=42 fails default import and
succeeds after explicit sys.path.append. This supports a native path fix rather
than adding source prefixes that would change diagnostics.

## Code contracts and expected implementation boundary

- `native/port/mpconfigport.h:49` selects EXTRA_FEATURES; `:98-99` disables
  os; `:118-124` explicitly disables several unsupported extension modules.
- `native/tools/build_embed.py:76-83` lists six selected extmod C modules.
  Frozen package integration is not currently in that generator.
- `native/src/qfli_py_bridge.c:221-236` creates entry-directory/project-root
  sys.path only. `:254-263` compiles source and conditionally executes it.
- `native/src/qfli_py_file.c:73-115` confines ordinary open/write to the real
  project root. The upstream import reader is a separate path; the runtime
  spec explicitly does not claim isolation for arbitrary hostile Python.
- `lib/python_terminal.dart:97-103` rejects -m/-c honestly; `:117-123`
  rejects extra script arguments rather than silently dropping them.

Implement app-owned bundled assets, a typed catalog/service, versioned
project-local preparation, a local package manifest/transaction and explicit
native sys.path additions. Keep the legacy ABI and current runtime identity.
The tools child consumes this service. Tests must cover useful API behavior,
package submodules, precedence, repeated VM invocations, failure recovery and
unmanaged-file preservation, followed by actual installed OHOS execution.

## pip and sandbox conclusion

The current engine does not contain pip or mip. Do not download or advertise
CPython pip as if it were part of this runtime. Provide explicit local pure
Python package import/install/check/remove with a tested compatibility scope;
network dependency resolution and native extension installation are excluded
by the user's offline requirement. A compatible pure-Python archive still
requires source/API verification and cannot be accepted solely by extension.

Primary version-matched reference fetched during planning:
`https://docs.micropython.org/en/v1.24.0/reference/packages.html` documents manual
package installation and frozen-package approaches. The pinned source's local
docs and runtime remain authoritative for what this custom build actually has.
An attempted pip official user-guide fetch returned HTTP403, so no fetched pip
documentation is used as evidence of engine compatibility. The package manager
design is based on the real engine/module/path probe above.

## Outstanding gates

No module implementation, package transaction or native rebuild was performed
in planning. `hdc list targets` returned Empty. The host probe cannot prove
OHOS execution, full stdlib support or security isolation.
