# Original Python content: generated assets and host VM

Checked on 2026-10-23 Asia/Shanghai. This closes the original host inventory
check only; installed OHOS execution and ordinary product UI remain open.

The authored original curriculum has 120 topic pairs and 186 independent
exercise answers. All are embedded-runtime programs with declared stdin/project
fixtures and exact output or appended behavioral assertions. No new expansion
was authored before the original installed-device gate.

During the exclusive global generation window159, the generator emitted the
three Python-containing assets. An independent Python snapshot comparison
verified all1700 foreign tutorial records and1700 foreign example records,
their order and stable document metadata were unchanged. The window was
released167; correction168 fixes only a prose count typo. Durable evidence:
`generation-originals-preservation.json`.

`export_inventory.dart --shipped` exported1158 representations: five forms of
each main and three forms of each answer. It reported zero missing/stale assets.
Inventory SHA256:
`f1d891de16360a587e205a945e0a015c90040a267a68e5b7acfd614fa8838ec4`.

Command:

```text
python tool/verify_python_content.py --inventory build/python-content-original-shipped.json --library build/verification/python-module-foundation.dll --report .trellis/tasks/10-22-python-content-ohos/research/python-content-originals-host.json
```

Actual result:1158 planned,1158 completed,1158 passed,0 failed,0 asset mismatches.
Every representation executed in a fresh subprocess/project using the preserved
foundation DLL SHA256
`2329ef7d374e35dd5159db0f3f056b094effc9a0372ad29fe704af472a6c309f`.
Host CPython only hosts ctypes and the verifier; it never executes curriculum
source. Exact stdout normalizes CRLF only. Each child has an8second deadline;
timeout kills and waits the child and the parent-owned temporary tree is cleaned.
The report intentionally records `deviceGatePassed:false`.

Core `python_content_test.dart` and `python_content_render_test.dart`:14/14
passed. They check standalone answer expectations, generated source identity,
all adapted main/fixture representations, example008 stdin retention, distinct
programs, pair identity and preservation of custom/edited saved examples.
These are structural/adapter tests and do not establish OHOS VM execution.

The content-audit worker owns the product harness and preparation. It must
import through the real shared CodeImportService and execute PythonProgramRunner
on installed OHOS. Current debugger/FFI changes also require a fresh final HAP;
the retained module-only HAP is useful immutable evidence for its captured
sources, not current product acceptance.
