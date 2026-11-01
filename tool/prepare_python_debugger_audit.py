"""Prepare a build-only entry for installed-OHOS debugger acceptance.

This consumes an existing matching OHOS SO. It never builds, installs, launches,
or changes a device. Declared inputs still require independent signed-HAP binding.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath

try:
    from .python_audit_inputs import collect_inputs
except ImportError:
    from python_audit_inputs import collect_inputs


SOURCE_FILES = (
    "tool/python_debugger_ohos_audit.dart",
    "tool/prepare_python_debugger_audit.py",
    "lib/python_debugger.dart",
    "lib/python_debugger_ffi.dart",
    "lib/python_runner.dart",
    "lib/python_runtime_activity.dart",
    "lib/python_ffi.dart",
    "lib/python_native_library.dart",
    "lib/python_packages.dart",
    "lib/python_module_catalog.dart",
    "native/ohos/QfliPyNative.ets",
    "ohos/entry/src/main/ets/plugins/QfliPyNative.ets",
    "ohos/entry/src/main/ets/entryability/EntryAbility.ets",
    "ohos/entry/src/main/ets/pages/Index.ets",
    "ohos/entry/src/main/module.json5",
    "native/src/qfli_py_debug.c",
    "native/src/qfli_py_debug.h",
    "native/src/qfli_py_bridge.c",
    "native/src/qfli_py_bridge.h",
    "native/src/qfli_py_platform.c",
    "native/src/qfli_py_platform.h",
    "native/port/mpconfigport.h",
    "native/port/qfli_debug_metadata.h",
    "native/tools/debug_overlay.py",
    "native/tools/build_embed.py",
    "native/CMakeLists.txt",
    "native/micropython_embed/py/vm.c",
    "native/micropython_embed/py/emitglue.h",
)
CORE_FILES = (
    "lib/services/debug_session.dart",
    "lib/services/studio_profile.dart",
    "lib/services/code_analysis.dart",
    "lib/services/app_paths.dart",
    "lib/services/file_encoding.dart",
)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def dart_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=True).replace("$", r"\$")


def contained_file(root: Path, name: str) -> Path:
    if (
        "\\" in name
        or ":" in name
        or PurePosixPath(name).is_absolute()
        or any(part in ("", ".", "..") for part in name.split("/"))
    ):
        raise ValueError(f"Invalid source-relative path: {name}")
    path = (root / name).resolve()
    if root not in path.parents or not path.is_file():
        raise ValueError(f"Missing or escaping source file: {name}")
    return path


def prepare(
    root: Path,
    output: Path,
    native_library: Path,
    *,
    core_root: Path | None = None,
    build_metadata: dict | None = None,
) -> dict:
    root = root.resolve()
    output = output.resolve()
    core_root = (core_root or root.parent / "qfli_studio_core").resolve()
    if root / "build" not in output.parents:
        raise ValueError("Generated debugger audit files must stay in a subdirectory of ignored build/")
    native_library = native_library.resolve()
    native = native_library.read_bytes()
    machine = int.from_bytes(native[18:20], "little")
    abi = {62: "x86_64", 183: "arm64-v8a"}.get(machine)
    if len(native) < 20 or native[:6] != b"\x7fELF\x02\x01" or abi is None:
        raise ValueError("Audit native library must be ELF64 little-endian OHOS x86_64/arm64 SO")
    # The real packaged loader must resolve these exports. Presence here only
    # rejects a definitely old library; it does not prove a working debugger.
    for symbol in (
        b"qfli_py_debug_capabilities\0",
        b"qfli_py_debug_create\0",
        b"qfli_py_debug_execute_into\0",
        b"qfli_py_debug_poll_json\0",
        b"qfli_py_debug_command\0",
    ):
        if symbol not in native:
            raise ValueError(f"SO lacks required debugger export: {symbol[:-1].decode()}")
    assets_root = root / "assets/python_stdlib"
    manifest = json.loads((assets_root / "manifest.json").read_bytes())
    for module in manifest["modules"]:
        for entry in module["files"]:
            path = contained_file(root, "assets/python_stdlib/" + entry["path"])
            if digest(path.read_bytes()) != entry["sha256"]:
                raise ValueError(f"Bundled module digest mismatch: {entry['path']}")
    assets = {
        path.relative_to(root).as_posix(): digest(path.read_bytes())
        for path in sorted(assets_root.rglob("*"))
        if path.is_file()
    }
    sources = {name: digest(contained_file(root, name).read_bytes()) for name in SOURCE_FILES}
    core_sources = {name: digest(contained_file(core_root, name).read_bytes()) for name in CORE_FILES}
    captured_product, captured_core = collect_inputs(root, core_root)
    sources.update(captured_product)
    core_sources.update(captured_core)
    if sources["native/ohos/QfliPyNative.ets"] != sources["ohos/entry/src/main/ets/plugins/QfliPyNative.ets"]:
        raise ValueError("OHOS native channel source copies differ")
    suite_source = "tool/python_debugger_ohos_audit.dart"
    evidence = {
        "schemaVersion": 1,
        "evidenceKind": "declared-build-inputs; independently bind to the signed HAP and packaged SO",
        "suiteSource": suite_source,
        "suiteSha256": sources[suite_source],
        "sourceDigests": sources,
        "coreSourceDigests": core_sources,
        "assetDigests": assets,
        "buildMetadata": build_metadata or {},
        "nativeLibrary": {
            "path": str(native_library),
            "sha256": digest(native),
            "bytes": len(native),
            "abi": abi,
            "evidenceKind": "declared-build-input; independently checked against HAP",
        },
    }
    output.mkdir(parents=True, exist_ok=True)
    (output / "suite.g.dart").write_text(
        "// Generated by tool/prepare_python_debugger_audit.py. Do not edit.\n"
        f"const pythonDebuggerAuditSuiteSha256 = {dart_string(evidence['suiteSha256'])};\n"
        "const pythonDebuggerAuditAssetDigests = <String, String>{\n"
        + "".join(f"  {dart_string(name)}: {dart_string(value)},\n" for name, value in sorted(assets.items()))
        + "};\n"
        + f"const pythonDebuggerAuditBuildEvidenceJson = {dart_string(json.dumps(evidence, sort_keys=True))};\n",
        encoding="utf-8", newline="\n",
    )
    harness = os.path.relpath(root / suite_source, output).replace("\\", "/")
    (output / "main.dart").write_text(
        "// Generated audit-only entry; normal lib/main.dart remains untouched.\n"
        "import 'dart:convert';\n"
        f"import {dart_string(harness)};\n"
        "import 'suite.g.dart';\n"
        "void main() => startPythonDebuggerAudit(\n"
        "  suiteSha256: pythonDebuggerAuditSuiteSha256,\n"
        "  assetDigests: pythonDebuggerAuditAssetDigests,\n"
        "  buildEvidence: jsonDecode(pythonDebuggerAuditBuildEvidenceJson) as Map<String, dynamic>,\n"
        ");\n",
        encoding="utf-8", newline="\n",
    )
    (output / "inputs.json").write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8", newline="\n")
    return evidence


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="build/python_debugger_audit")
    parser.add_argument("--native-library", required=True, help="Existing matching OHOS SO")
    parser.add_argument("--build-metadata", help="Optional JSON object with build/revision/target identity")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent

    def project_path(value: str) -> Path:
        path = Path(value)
        return path if path.is_absolute() else root / path

    metadata = json.loads(project_path(args.build_metadata).read_bytes()) if args.build_metadata else {}
    if not isinstance(metadata, dict):
        parser.error("--build-metadata must contain a JSON object")
    evidence = prepare(root, project_path(args.output), project_path(args.native_library), build_metadata=metadata)
    print(json.dumps({"entry": str(project_path(args.output) / "main.dart"), "suiteSha256": evidence["suiteSha256"], "assetCount": len(evidence["assetDigests"]), "abi": evidence["nativeLibrary"]["abi"]}))


if __name__ == "__main__":
    main()
