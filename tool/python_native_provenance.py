"""Capture/finish/verify evidence around an actual configured native build.

native/build.ps1 calls capture after configure, then finish only after a
successful compiler and dependency check. No command here compiles or stages.

Identity has to cover the tools that actually ran and the SDK inputs the
configured rules consume. In the real OHOS configuration the CMake cache has no
``CMAKE_C_COMPILER``, ``CMAKE_CXX_COMPILER`` or ``CMAKE_SYSROOT`` entries: the
compilers, the linker/archiver and the implicit include/link directories live
in ``CMakeFiles/<version>/CMakeCCompiler.cmake`` and ``CMakeCXXCompiler.cmake``.
Those files are authoritative here, and every required tool role must resolve
to an existing executable. A generic "some tool identities exist" check is not
enough, because AR/RANLIB cache entries stay present when a compiler is swapped.

The SDK boundary is explicit: the compiler's implicit include directories
(every file, including the extensionless libc++ headers) and implicit link
directories (static/shared libraries). Header and static-library drift inside
that boundary is detected; anything outside it is not claimed.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re


SCHEMA_VERSION = 2

# Roles that must be identified before a compiled output may be adopted.
REQUIRED_TOOL_ROLES = ("cCompiler", "cxxCompiler", "linker", "ar", "ranlib", "python")

COMPILER_METADATA = {
    "cCompiler": "CMakeCCompiler.cmake",
    "cxxCompiler": "CMakeCXXCompiler.cmake",
}

ROLE_VARIABLES = {
    "cCompiler": ("CMAKE_C_COMPILER",),
    "cxxCompiler": ("CMAKE_CXX_COMPILER",),
    "linker": ("CMAKE_LINKER",),
    "ar": ("CMAKE_AR",),
    "ranlib": ("CMAKE_RANLIB",),
}

OHOS_TRIPLES = {
    "x86_64": "x86_64-linux-ohos",
    "arm64-v8a": "aarch64-linux-ohos",
    "armeabi-v7a": "arm-linux-ohos",
}

# Static libraries and shared objects (including versioned names) are linked
# inputs; .o/.syms/other artifacts in the same directories are not.
LIBRARY_FILE = re.compile(r"^lib[^/\\]*\.(?:a|so)(?:\.[0-9][^/\\]*)?$")

_CMAKE_SET = re.compile(r"^set\(\s*([A-Za-z0-9_]+)\s+\"?([^\"\n]*)\"?\s*\)\s*$")


def identity(path: Path) -> dict:
    result = hashlib.sha256()
    size = 0
    with path.open("rb") as stream:
        for data in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(data)
            size += len(data)
    return {"sha256": result.hexdigest(), "bytes": size}


def _cmake_variables(text: str) -> dict:
    values = {}
    for line in text.splitlines():
        match = _CMAKE_SET.match(line.strip())
        if match:
            values[match[1]] = match[2].strip()
    return values


def _cache_variables(text: str) -> dict:
    values = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith(("//", "#")) or "=" not in line:
            continue
        name, value = line.split("=", 1)
        values[name.split(":", 1)[0]] = value.strip()
    return values


def configured_variables(build: Path) -> dict:
    """Read the authoritative generated C/C++ compiler configuration."""
    variables = {}
    for role, name in COMPILER_METADATA.items():
        candidates = sorted(path for path in (build / "CMakeFiles").glob(f"*/{name}") if path.is_file())
        if not candidates:
            raise ValueError(f"Configured build omits CMake compiler metadata: {name}")
        if len(candidates) > 1:
            raise ValueError(
                f"Ambiguous CMake compiler metadata for {role}: "
                + ", ".join(str(path) for path in candidates)
            )
        variables.update(_cmake_variables(candidates[0].read_text(encoding="utf-8", errors="replace")))
    return variables


def resolve_roles(variables: dict, cache: dict) -> dict:
    """Map every required tool role to the configured executable."""
    roles = {}
    missing = []
    for role, names in ROLE_VARIABLES.items():
        value = ""
        for name in names:
            candidate = (variables.get(name) or cache.get(name) or "").strip()
            if candidate and not candidate.endswith("-NOTFOUND"):
                value = candidate
                break
        if not value:
            missing.append(role)
            continue
        path = Path(value)
        if not path.is_file():
            raise ValueError(f"Configured {role} is missing: {value}")
        roles[role] = path.resolve()
    if missing:
        raise ValueError(
            "Configured build does not identify required tool roles: " + ", ".join(missing)
        )
    return roles


def sdk_directories(variables: dict, cache: dict) -> tuple[list[Path], list[Path]]:
    """Resolve the include/link directories the configured rules actually use."""
    include_dirs = []
    link_dirs = []
    for name in ("CMAKE_C_IMPLICIT_INCLUDE_DIRECTORIES", "CMAKE_CXX_IMPLICIT_INCLUDE_DIRECTORIES"):
        include_dirs.extend(Path(item) for item in variables.get(name, "").split(";") if item.strip())
    for name in ("CMAKE_C_IMPLICIT_LINK_DIRECTORIES", "CMAKE_CXX_IMPLICIT_LINK_DIRECTORIES"):
        link_dirs.extend(Path(item) for item in variables.get(name, "").split(";") if item.strip())
    sysroot = cache.get("CMAKE_SYSROOT", "").strip()
    if sysroot:
        triple = OHOS_TRIPLES.get(cache.get("OHOS_ARCH", "").strip())
        if not triple:
            raise ValueError("Configured sysroot lacks an explicit supported OHOS architecture")
        include_dirs.append(Path(sysroot) / "usr/include")
        link_dirs.append(Path(sysroot) / "usr/lib" / triple)
    include_dirs = sorted({path.resolve() for path in include_dirs})
    link_dirs = sorted({path.resolve() for path in link_dirs})
    if not include_dirs or not link_dirs:
        raise ValueError(
            "Configured build exposes no compiler implicit include/link directories"
        )
    return include_dirs, link_dirs


def _files_under(directory: Path, libraries_only: bool) -> list[Path]:
    if not directory.is_dir():
        raise ValueError(f"Missing configured SDK input directory: {directory}")
    if libraries_only:
        return [path for path in directory.rglob("*") if path.is_file() and LIBRARY_FILE.match(path.name)]
    return [path for path in directory.rglob("*") if path.is_file()]


def sdk_identities(include_dirs: list[Path], link_dirs: list[Path]) -> dict:
    paths = []
    for directory in include_dirs:
        paths.extend(_files_under(directory, libraries_only=False))
    for directory in link_dirs:
        paths.extend(_files_under(directory, libraries_only=True))
    digests = {str(path): identity(path) for path in sorted(set(paths))}
    if not any(Path(name).suffix == "" and "libcxx" in name.replace("\\", "/") for name in digests):
        raise ValueError("SDK closure omits the extensionless libc++ headers")
    if not any(name.endswith(".a") for name in digests):
        raise ValueError("SDK closure omits the configured static libraries")
    return digests


def snapshot(root: Path, build: Path, tools: list[Path] = (), python: Path | None = None) -> dict:
    commands_path = build / "compile_commands.json"
    if not commands_path.is_file():
        raise ValueError(
            f"Configured build omits compilation commands: {commands_path} "
            "(reconfigure with -DCMAKE_EXPORT_COMPILE_COMMANDS=ON)"
        )
    paths = set()
    # Include both generator inputs and generated compilation inputs. Avoid
    # logs, output libraries, temporary provenance files and other ABI builds.
    for name in ("src", "port", "tools", "micropython_embed", "third_party/micropython"):
        for path in (root / "native" / name).rglob("*"):
            if path.is_file() and (path.suffix in (".c", ".h", ".cpp", ".S", ".s", ".py", ".cmake", ".mk") or path.name == "CMakeLists.txt"):
                paths.add(path)
    paths.update((root / "native/CMakeLists.txt", root / "native/build.ps1", root / "tool/python_native_provenance.py"))
    paths.update(build / name for name in ("compile_commands.json", "CMakeCache.txt", "build.ninja"))
    paths.update(path for path in (build / "CMakeFiles").rglob("*.cmake") if path.is_file())
    rules = build / "CMakeFiles/rules.ninja"
    if not rules.is_file():
        raise ValueError("Missing configured Ninja rules file")
    paths.add(rules)
    paths.update(path for path in (build / "embed").rglob("*") if path.is_file())

    cache = _cache_variables((build / "CMakeCache.txt").read_text(encoding="utf-8"))
    variables = configured_variables(build)
    roles = resolve_roles(variables, cache)
    if python is not None:
        python_path = Path(python).resolve()
        if not python_path.is_file():
            raise ValueError(f"Configured host Python is missing: {python}")
        roles["python"] = python_path

    tool_paths = set(roles.values())
    tool_paths.update(Path(path).resolve() for path in tools)
    toolchain = {str(path): identity(path) for path in sorted(tool_paths)}

    include_dirs, link_dirs = sdk_directories(variables, cache)
    sdk = sdk_identities(include_dirs, link_dirs)

    sources = {path.resolve().relative_to(root).as_posix(): identity(path) for path in sorted(paths)}
    commands = json.loads(commands_path.read_bytes())
    if not isinstance(commands, list) or not commands:
        raise ValueError("Missing configured compilation commands")
    for row in commands:
        source = Path(row["file"])
        if not source.is_absolute():
            source = Path(row["directory"]) / source
        name = source.resolve().relative_to(root).as_posix()
        if name not in sources:
            raise ValueError(f"Uncaptured compilation source: {name}")
    return {
        "sourceDigests": sources,
        "toolchainDigests": toolchain,
        "toolRoles": {role: str(path) for role, path in sorted(roles.items())},
        "sdkDigests": sdk,
        "sdkDirectories": {
            "include": [str(path) for path in include_dirs],
            "link": [str(path) for path in link_dirs],
        },
        "compileCommandCount": len(commands),
    }


def verify(root: Path, manifest: dict, library: Path) -> None:
    if manifest.get("schemaVersion") != SCHEMA_VERSION or manifest.get("kind") != "completed-python-native-build":
        raise ValueError("A completed native build provenance manifest is required")
    if manifest.get("buildExitCode") != 0 or manifest.get("dependencyCheckExitCode") != 0:
        raise ValueError("Native build/dependency validation did not succeed")
    if manifest.get("abi") not in OHOS_TRIPLES:
        raise ValueError("Unsupported native build ABI")
    sources = manifest.get("sourceDigests", {})
    for required in ("native/micropython_embed/py/vm.c", "native/micropython_embed/py/emitglue.h", "native/tools/debug_overlay.py"):
        if required not in sources:
            raise ValueError(f"Native provenance omits generated/runtime input: {required}")
    for name, expected in sources.items():
        path = (root / name).resolve()
        if not path.is_relative_to(root) or identity(path) != expected:
            raise ValueError(f"Native source/build input changed: {name}")

    roles = manifest.get("toolRoles") or {}
    missing = [role for role in REQUIRED_TOOL_ROLES if role not in roles]
    if missing:
        raise ValueError("Native provenance omits required tool roles: " + ", ".join(missing))
    toolchain = manifest.get("toolchainDigests") or {}
    if not toolchain:
        raise ValueError("Native provenance lacks toolchain identities")
    for role in REQUIRED_TOOL_ROLES:
        if roles[role] not in toolchain:
            raise ValueError(f"Native tool role is not fingerprinted: {role} -> {roles[role]}")
    for name, expected in toolchain.items():
        path = Path(name)
        if not path.is_absolute() or not path.is_file() or identity(path) != expected:
            raise ValueError(f"Native toolchain changed: {name}")

    sdk = manifest.get("sdkDigests") or {}
    if not sdk:
        raise ValueError("Native provenance lacks configured SDK inputs")
    if not any(Path(name).suffix == "" and "libcxx" in name.replace("\\", "/") for name in sdk):
        raise ValueError("Native provenance omits the extensionless libc++ headers")
    if not any(name.endswith(".a") for name in sdk):
        raise ValueError("Native provenance omits the configured static libraries")
    for name, expected in sdk.items():
        path = Path(name)
        if not path.is_absolute() or not path.is_file() or identity(path) != expected:
            raise ValueError(f"Native SDK input changed: {name}")

    build = Path(manifest["buildDirectory"]).resolve()
    build.relative_to(root / "native/build")
    current = snapshot(root, build, [Path(name) for name in toolchain], python=Path(roles["python"]))
    if any(manifest.get(key) != current[key] for key in current):
        raise ValueError("Native source/build input inventory changed since compilation")
    if identity(library) != manifest.get("output"):
        raise ValueError("Staged native library does not match completed native build")
    data = library.read_bytes()
    machine = {"x86_64": 62, "arm64-v8a": 183, "armeabi-v7a": 40}[manifest["abi"]]
    elf_class = 1 if manifest["abi"] == "armeabi-v7a" else 2
    if len(data) < 20 or data[:6] != b"\x7fELF" + bytes((elf_class, 1)) or int.from_bytes(data[18:20], "little") != machine:
        raise ValueError("Native build output ABI mismatch")


def save(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8", newline="\n")
    temporary.replace(path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("capture", "finish", "verify"))
    parser.add_argument("--build-directory", type=Path)
    parser.add_argument("--abi", choices=("x86_64", "arm64-v8a", "armeabi-v7a"))
    parser.add_argument("--build-type")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--library", type=Path)
    parser.add_argument("--python", type=Path, help="host Python 3 that generated the build inputs")
    parser.add_argument("--tool", type=Path, action="append", default=[])
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if args.action == "capture":
        if args.build_directory is None or args.abi is None or args.python is None:
            parser.error("capture requires --build-directory, --abi and --python")
        build = args.build_directory.resolve()
        build.relative_to(root / "native/build")
        value = snapshot(root, build, args.tool, python=args.python)
        value.update(schemaVersion=SCHEMA_VERSION, kind="pending-python-native-build", abi=args.abi,
                     buildType=args.build_type, buildDirectory=str(build), capturedAtUtc=datetime.now(timezone.utc).isoformat())
        save(args.manifest, value)
    else:
        value = json.loads(args.manifest.read_bytes())
        if args.library is None:
            parser.error("finish/verify requires --library")
        python = (value.get("toolRoles") or {}).get("python")
        if not python:
            raise ValueError("Native evidence omits the host Python identity")
        if args.action == "finish":
            current = snapshot(root, Path(value["buildDirectory"]), [Path(name) for name in value["toolchainDigests"]],
                               python=Path(python))
            if any(value[key] != current[key] for key in current):
                raise ValueError("Native compilation inputs changed after capture")
            value.update(kind="completed-python-native-build", buildExitCode=0, dependencyCheckExitCode=0,
                         output=identity(args.library), outputPath=str(args.library.resolve()),
                         finishedAtUtc=datetime.now(timezone.utc).isoformat())
            verify(root, value, args.library)
            save(args.manifest, value)
        else:
            verify(root, value, args.library)
    print(json.dumps({"action": args.action, "manifest": str(args.manifest), "ok": True}))


if __name__ == "__main__":
    main()
