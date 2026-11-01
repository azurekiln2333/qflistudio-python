"""Prepare a build-only entry for exhaustive installed-OHOS content acceptance.

Consumes an existing export_inventory.dart --shipped JSON. Does not generate
curriculum, build a HAP, execute acceptance, or access a device.
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


REQUIRED_ASSETS = {
    "assets/content/tutorials.json",
    "assets/content/examples.json",
    "assets/tutorials/python.json",
}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def dart_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=True).replace("$", r"\$")


def strings(value: object, label: str) -> dict[str, str]:
    if not isinstance(value, dict) or any(
        not isinstance(key, str) or not isinstance(item, str)
        for key, item in value.items()
    ):
        raise ValueError(f"Invalid {label} string map")
    return value


def contained_file(root: Path, name: str) -> Path:
    parts = name.split("/")
    if (
        "\\" in name
        or any(part in ("", ".", "..") for part in parts)
        or PurePosixPath(name).is_absolute()
        or ":" in name
    ):
        raise ValueError(f"Invalid project-relative path: {name}")
    path = (root / name).resolve()
    if root not in path.parents:
        raise ValueError(f"Path escapes source root: {name}")
    return path


def prepare(
    root: Path,
    inventory_path: Path,
    output: Path,
    native_library: Path | None = None,
    build_metadata: dict | None = None,
    *,
    core_root: Path | None = None,
) -> dict:
    root = root.resolve()
    core_root = (core_root or root.parent / "qfli_studio_core").resolve()
    output = output.resolve()
    build_root = root / "build"
    if build_root not in output.parents:
        raise ValueError("Generated content audit files must stay inside a subdirectory of ignored build/")
    inventory_path = inventory_path.resolve()
    inventory_bytes = inventory_path.read_bytes()
    inventory_json = inventory_bytes.decode("utf-8")
    inventory = json.loads(inventory_json)
    if not isinstance(inventory, dict) or inventory.get("schemaVersion") != 1:
        raise ValueError("Unsupported inventory schema")
    if inventory.get("assetMismatches") != []:
        raise ValueError("Inventory must have zero authored/shipped asset mismatches")
    assets = strings(inventory.get("assetDigests"), "assetDigests")
    if not REQUIRED_ASSETS.issubset(assets):
        raise ValueError("Inventory lacks the three shipped asset digests; export with --shipped")
    for name, expected in assets.items():
        if not name.startswith("assets/"):
            raise ValueError(f"Unexpected core asset: {name}")
        if digest(contained_file(core_root, name).read_bytes()) != expected:
            raise ValueError(f"Core asset drift since inventory export: {name}")
    units = inventory.get("units")
    if not isinstance(units, list) or not units:
        raise ValueError("Inventory must contain nonempty units")
    ids: set[str] = set()
    for index, unit in enumerate(units):
        if not isinstance(unit, dict):
            raise ValueError(f"Unit {index} must be an object")
        unit_id = unit.get("id")
        if not isinstance(unit_id, str) or not unit_id or unit_id in ids:
            raise ValueError(f"Missing/duplicate unit ID at row {index}")
        ids.add(unit_id)
        if type(unit.get("topic")) is not int or not isinstance(unit.get("kind"), str):
            raise ValueError(f"Missing topic/kind identity: {unit_id}")
        if unit.get("runtime") != "embedded":
            raise ValueError(f"Non-embedded unit: {unit_id}")
        if not isinstance(unit.get("code"), str) or not unit["code"].strip():
            raise ValueError(f"Missing executable code: {unit_id}")
        expected = unit.get("expectedOutput")
        if expected is not None and not isinstance(expected, str):
            raise ValueError(f"Invalid expected output: {unit_id}")
        validation = unit.get("validation")
        if unit.get("hasBehaviorCheck") is not True or not (
            isinstance(expected, str)
            or isinstance(validation, str) and validation.strip()
        ):
            raise ValueError(f"Missing behavioral expectation: {unit_id}")
        strings(unit.get("inputFixtures"), f"{unit_id} inputFixtures")

    bundled_assets = {
        path.relative_to(root).as_posix(): digest(path.read_bytes())
        for path in sorted((root / "assets/python_stdlib").rglob("*"))
        if path.is_file()
    }
    manifest_path = "assets/python_stdlib/manifest.json"
    if manifest_path not in bundled_assets:
        raise ValueError("Missing bundled Python module manifest")
    manifest = json.loads((root / manifest_path).read_bytes())
    for module in manifest["modules"]:
        for entry in module["files"]:
            name = "assets/python_stdlib/" + entry["path"]
            if digest(contained_file(root, name).read_bytes()) != entry["sha256"]:
                raise ValueError(f"Bundled module digest mismatch: {name}")
    evidence = {
        "evidenceKind": "declared-build-inputs; independently bind to the packaged HAP/SO",
        "inventorySource": str(inventory_path),
        "inventorySha256": digest(inventory_bytes),
        "unitCount": len(units),
        "uniqueUnitCount": len(ids),
        "assetDigests": assets,
        "bundledModuleAssetDigests": bundled_assets,
        "sourceDigests": {
            name: digest((root / name).read_bytes())
            for name in (
                "tool/python_content_ohos_audit.dart",
                "tool/prepare_python_content_audit.py",
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
            )
        },
        "coreImportSourceSha256": digest(
            (core_root / "lib/services/code_import_service.dart").read_bytes()
        ),
        "nativeLibrary": None,
        "buildMetadata": build_metadata or {},
    }
    captured_product, captured_core = collect_inputs(root, core_root)
    evidence["sourceDigests"].update(captured_product)
    evidence["coreSourceDigests"] = captured_core
    if native_library is not None:
        native_library = native_library.resolve()
        native_bytes = native_library.read_bytes()
        machine = int.from_bytes(native_bytes[18:20], "little")
        abi = {62: "x86_64", 183: "arm64-v8a"}.get(machine)
        if len(native_bytes) < 20 or native_bytes[:6] != b"\x7fELF\x02\x01" or abi is None:
            raise ValueError("Audit native library must be an ELF64 little-endian OHOS x86_64/arm64 SO")
        evidence["nativeLibrary"] = {
            "path": str(native_library),
            "sha256": digest(native_bytes),
            "bytes": len(native_bytes),
            "abi": abi,
            "evidenceKind": "declared-build-input; independently checked against HAP",
        }

    output.mkdir(parents=True, exist_ok=True)
    (output / "inventory.g.dart").write_text(
        "// Generated by tool/prepare_python_content_audit.py. Do not edit.\n"
        f"const pythonContentAuditInventory = {dart_string(inventory_json)};\n"
        f"const pythonContentAuditInventorySha256 = {dart_string(digest(inventory_bytes))};\n"
        "const pythonContentAuditAssetDigests = <String, String>{\n"
        + "".join(f"  {dart_string(name)}: {dart_string(value)},\n" for name, value in sorted(assets.items()))
        + "};\n"
        + f"const pythonContentAuditBuildEvidenceJson = {dart_string(json.dumps(evidence, sort_keys=True))};\n",
        encoding="utf-8",
        newline="\n",
    )
    harness = os.path.relpath(root / "tool/python_content_ohos_audit.dart", output).replace("\\", "/")
    (output / "main.dart").write_text(
        "// Generated audit-only entry; normal lib/main.dart remains untouched.\n"
        "import 'dart:convert';\n"
        f"import {dart_string(harness)};\n"
        "import 'inventory.g.dart';\n"
        "void main() => startPythonContentAudit(\n"
        "  inventoryJson: pythonContentAuditInventory,\n"
        "  inventorySha256: pythonContentAuditInventorySha256,\n"
        "  assetDigests: pythonContentAuditAssetDigests,\n"
        "  buildEvidence: jsonDecode(pythonContentAuditBuildEvidenceJson) as Map<String, dynamic>,\n"
        ");\n",
        encoding="utf-8",
        newline="\n",
    )
    (output / "inputs.json").write_text(
        json.dumps(evidence, indent=2) + "\n", encoding="utf-8", newline="\n"
    )
    return evidence


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", required=True, help="Existing --shipped inventory JSON")
    parser.add_argument("--output", default="build/python_content_audit")
    parser.add_argument("--native-library", help="Existing matching OHOS SO build input")
    parser.add_argument("--build-metadata", help="Optional JSON object with build/revision/target metadata")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent

    def project_path(value: str) -> Path:
        path = Path(value)
        return path if path.is_absolute() else root / path

    metadata = json.loads(project_path(args.build_metadata).read_bytes()) if args.build_metadata else {}
    if not isinstance(metadata, dict):
        parser.error("--build-metadata must contain a JSON object")
    evidence = prepare(
        root,
        project_path(args.inventory),
        project_path(args.output),
        project_path(args.native_library) if args.native_library else None,
        metadata,
    )
    print(json.dumps({
        "entry": str(project_path(args.output) / "main.dart"),
        "inventorySha256": evidence["inventorySha256"],
        "unitCount": evidence["unitCount"],
        "assetCount": len(evidence["assetDigests"]),
    }))


if __name__ == "__main__":
    main()
