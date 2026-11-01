"""Input identities shared by the three Python acceptance preparers.

Hashing declares inputs. It never proves native compilation or device behavior.
"""
from __future__ import annotations

import hashlib
import argparse
import json
from pathlib import Path


def collect_inputs(root: Path, core: Path) -> tuple[dict[str, str], dict[str, str]]:
    def files(base: Path, directories: tuple[str, ...], names: tuple[str, ...]) -> dict[str, str]:
        paths = {base / name for name in names if (base / name).is_file()}
        for directory in directories:
            paths.update(path for path in (base / directory).rglob("*") if path.is_file())
        return {
            path.relative_to(base).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(paths)
        }

    product = files(root, ("lib", "assets/python_stdlib", "ohos/entry/src/main", "native/ohos"), (
        "pubspec.yaml", "pubspec.lock", ".dart_tool/package_config.json",
        "ohos/AppScope/app.json5", "ohos/hvigorfile.ts", "ohos/oh-package.json5",
        "ohos/oh-package-lock.json5", "ohos/entry/hvigorfile.ts", "ohos/entry/oh-package.json5",
        "tool/build_python_ohos_audit.ps1", "tool/python_owned_process.py",
        "tool/python_audit_inputs.py", "tool/python_native_provenance.py",
        "tool/prepare_python_module_audit.py", "tool/python_module_ohos_audit.dart",
        "tool/prepare_python_content_audit.py", "tool/python_content_ohos_audit.dart",
        "tool/prepare_python_debugger_audit.py", "tool/python_debugger_ohos_audit.dart",
    ))
    shared = files(core, ("lib", "vendor/re_editor/lib", "vendor/re_editor/assets"), (
        "pubspec.yaml", "pubspec.lock", "vendor/re_editor/pubspec.yaml",
    ))
    return product, shared


def relative_input_name(name: object) -> bool:
    """A declared input must be a non-escaping project-relative POSIX path.

    Mirrors the preparers' containment guards so verification never accepts a
    declared digest for a path outside the root it is supposed to cover.
    """
    if not isinstance(name, str) or not name:
        return False
    if "\\" in name or ":" in name:
        return False
    return not any(part in ("", ".", "..") for part in name.split("/"))


def verify_inputs(value: dict, root: Path, core: Path) -> tuple[int, int]:
    """Reject discovered additions and every declared input's change/removal."""
    if not isinstance(value, dict):
        raise ValueError("Build input evidence must be a JSON object")
    product, shared = collect_inputs(root, core)
    for label, base, actual in (
        ("sourceDigests", root, product),
        ("coreSourceDigests", core, shared),
    ):
        declared = value.get(label)
        if not isinstance(declared, dict) or not declared:
            raise ValueError(f"Missing build input inventory: {label}")
        if any(declared.get(name) != expected for name, expected in actual.items()):
            raise ValueError(f"Current build input inventory differs: {label}")
        for name, expected in declared.items():
            if not relative_input_name(name):
                raise ValueError(f"Invalid declared build input path: {label}/{name}")
            source = base / name
            if not source.is_file() or hashlib.sha256(source.read_bytes()).hexdigest() != expected:
                raise ValueError(f"Declared build input changed or disappeared: {label}/{name}")
    return len(product), len(shared)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inputs", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    value = json.loads(args.inputs.read_bytes())
    product_count, core_count = verify_inputs(value, root, root.parent / "qfli_studio_core")
    print(json.dumps({"currentInputsMatch": True, "productFiles": product_count, "coreFiles": core_count}))


if __name__ == "__main__":
    main()
