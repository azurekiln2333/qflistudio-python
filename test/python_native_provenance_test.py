"""Synthetic build provenance regressions; no compiler, SDK or native execution.

The fixture mirrors the real OHOS configuration: the CMake cache carries no
``CMAKE_C_COMPILER``/``CMAKE_CXX_COMPILER``/``CMAKE_SYSROOT`` entries, the
compilers and implicit include/link directories are only in the generated
``CMakeFiles/<version>/CMake*Compiler.cmake`` files, and the SDK lives outside
the project root. Every fixture file is inert metadata; nothing is executed.
"""
from __future__ import annotations

import copy
import json
from pathlib import Path
import tempfile
import unittest

from tool.python_native_provenance import identity, snapshot, verify


def _write(path: Path, content: str = "") -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content or f"synthetic input: {path.name}", encoding="utf-8")
    return path


class NativeProvenanceTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="python_native_evidence_")
        self.addCleanup(self.temporary.cleanup)
        base = Path(self.temporary.name).resolve()
        self.root = base / "project"
        self.build = self.root / "native/build/cmake-x86_64"
        self.metadata_dir = self.build / "CMakeFiles/3.28.2"
        self.metadata_dir.mkdir(parents=True)

        for name in ("native/micropython_embed/py/vm.c", "native/micropython_embed/py/emitglue.h",
                     "native/tools/debug_overlay.py", "native/CMakeLists.txt", "native/build.ps1",
                     "tool/python_native_provenance.py"):
            _write(self.root / name)
        # Deliberately no compiler/sysroot entries, matching the real cache.
        (self.build / "CMakeCache.txt").write_text(
            "# synthetic cache\nOHOS_ARCH:UNINITIALIZED=x86_64\n", encoding="utf-8")
        (self.build / "build.ninja").write_text("# synthetic build\ninclude CMakeFiles/rules.ninja\n", encoding="utf-8")
        (self.build / "CMakeFiles/rules.ninja").write_text("# synthetic rules\n", encoding="utf-8")
        (self.build / "compile_commands.json").write_text(json.dumps([{
            "file": str(self.root / "native/micropython_embed/py/vm.c"),
            "directory": str(self.build), "command": "synthetic compiler invocation",
        }]), encoding="utf-8")

        self.sdk = base / "sdk/native"
        self.clang = _write(self.sdk / "llvm/bin/clang.exe", "metadata fixture; never executable")
        self.clangxx = _write(self.sdk / "llvm/bin/clang++.exe", "metadata fixture; never executable")
        self.linker = _write(self.sdk / "llvm/bin/ld.lld.exe", "metadata fixture; never executable")
        self.archiver = _write(self.sdk / "llvm/bin/llvm-ar.exe", "metadata fixture; never executable")
        self.ranlib = _write(self.sdk / "llvm/bin/llvm-ranlib.exe", "metadata fixture; never executable")
        self.python = _write(self.sdk / "python/python.exe", "metadata fixture; never executable")

        # Extensionless libc++ headers are real inputs; .h alone is not enough.
        self.libcxx_header = _write(self.sdk / "llvm/include/libcxx-ohos/include/c++/v1/vector")
        self.libcxx_config = _write(self.sdk / "llvm/include/libcxx-ohos/include/c++/v1/__config")
        self.resource_header = _write(self.sdk / "llvm/lib/clang/15.0.4/include/stddef.h")
        self.builtins = _write(
            self.sdk / "llvm/lib/clang/15.0.4/lib/x86_64-linux-ohos/libclang_rt.builtins.a")
        self.static_library = _write(self.sdk / "llvm/lib/x86_64-linux-ohos/libc++_static.a")
        self.shared_library = _write(self.sdk / "llvm/lib/x86_64-linux-ohos/libc++_shared.so")
        self.sysroot_header = _write(self.sdk / "sysroot/usr/include/stdint.h")
        self.triple_header = _write(self.sdk / "sysroot/usr/include/x86_64-linux-ohos/stdio.h")
        self.sysroot_library = _write(self.sdk / "sysroot/usr/lib/x86_64-linux-ohos/libc.so")
        self.napi_library = _write(self.sdk / "sysroot/usr/lib/x86_64-linux-ohos/libace_napi.z.so")

        self.include_dirs = [
            self.sdk / "llvm/include/libcxx-ohos/include/c++/v1",
            self.sdk / "llvm/lib/clang/15.0.4/include",
            self.sdk / "sysroot/usr/include/x86_64-linux-ohos",
            self.sdk / "sysroot/usr/include",
        ]
        self.link_dirs = [
            self.sdk / "llvm/lib/clang/15.0.4/lib/x86_64-linux-ohos",
            self.sdk / "sysroot/usr/lib",
            self.sdk / "llvm/lib/x86_64-linux-ohos",
            self.sdk / "sysroot/usr/lib/x86_64-linux-ohos",
        ]
        self._write_compiler_metadata()

        self.library = self.build / "libqfli_py.so"
        self.library.write_bytes(b"\x7fELF\x02\x01" + bytes(12) + bytes((62, 0)))
        self.evidence = snapshot(self.root, self.build, python=self.python)
        self.evidence.update(schemaVersion=2, kind="completed-python-native-build", abi="x86_64",
                             buildExitCode=0, dependencyCheckExitCode=0,
                             buildDirectory=str(self.build), output=identity(self.library))

    def _cmake_value(self, value: Path) -> str:
        return str(value).replace("\\", "/")

    def _write_compiler_metadata(self) -> None:
        """Compiler paths live only here, as in the real configured build."""
        (self.metadata_dir / "CMakeCCompiler.cmake").write_text("\n".join([
            f'set(CMAKE_C_COMPILER "{self._cmake_value(self.clang)}")',
            'set(CMAKE_C_COMPILER_ID "Clang")',
            'set(CMAKE_C_COMPILER_VERSION "15.0.4")',
            f'set(CMAKE_AR "{self._cmake_value(self.archiver)}")',
            f'set(CMAKE_RANLIB "{self._cmake_value(self.ranlib)}")',
            f'set(CMAKE_LINKER "{self._cmake_value(self.linker)}")',
            'set(CMAKE_C_IMPLICIT_INCLUDE_DIRECTORIES "'
            + ";".join(self._cmake_value(path) for path in self.include_dirs[1:]) + '")',
            'set(CMAKE_C_IMPLICIT_LINK_DIRECTORIES "'
            + ";".join(self._cmake_value(path) for path in self.link_dirs) + '")',
            "",
        ]), encoding="utf-8")
        (self.metadata_dir / "CMakeCXXCompiler.cmake").write_text("\n".join([
            f'set(CMAKE_CXX_COMPILER "{self._cmake_value(self.clangxx)}")',
            'set(CMAKE_CXX_COMPILER_ID "Clang")',
            'set(CMAKE_CXX_COMPILER_VERSION "15.0.4")',
            f'set(CMAKE_AR "{self._cmake_value(self.archiver)}")',
            f'set(CMAKE_RANLIB "{self._cmake_value(self.ranlib)}")',
            f'set(CMAKE_LINKER "{self._cmake_value(self.linker)}")',
            'set(CMAKE_CXX_IMPLICIT_INCLUDE_DIRECTORIES "'
            + ";".join(self._cmake_value(path) for path in self.include_dirs) + '")',
            'set(CMAKE_CXX_IMPLICIT_LINK_DIRECTORIES "'
            + ";".join(self._cmake_value(path) for path in self.link_dirs) + '")',
            "",
        ]), encoding="utf-8")

    # --- accepted baseline -------------------------------------------------

    def test_stable_input_output_binding(self):
        verify(self.root, self.evidence, self.library)

    def test_compilers_come_from_generated_metadata_not_the_cache(self):
        cache = (self.build / "CMakeCache.txt").read_text(encoding="utf-8")
        self.assertNotIn("CMAKE_C_COMPILER", cache)
        self.assertNotIn("CMAKE_CXX_COMPILER", cache)
        self.assertNotIn("CMAKE_SYSROOT", cache)
        roles = self.evidence["toolRoles"]
        self.assertEqual(roles["cCompiler"], str(self.clang.resolve()))
        self.assertEqual(roles["cxxCompiler"], str(self.clangxx.resolve()))
        self.assertEqual(roles["linker"], str(self.linker.resolve()))
        self.assertEqual(roles["ar"], str(self.archiver.resolve()))
        self.assertEqual(roles["ranlib"], str(self.ranlib.resolve()))
        self.assertEqual(roles["python"], str(self.python.resolve()))
        for role in ("cCompiler", "cxxCompiler", "linker", "ar", "ranlib", "python"):
            self.assertIn(roles[role], self.evidence["toolchainDigests"])

    def test_extensionless_libcxx_and_static_libraries_are_fingerprinted(self):
        sdk = self.evidence["sdkDigests"]
        extensionless = [name for name in sdk if Path(name).suffix == "" and "libcxx" in name.replace("\\", "/")]
        self.assertIn(str(self.libcxx_header.resolve()), extensionless)
        self.assertIn(str(self.libcxx_config.resolve()), extensionless)
        self.assertIn(str(self.static_library.resolve()), sdk)
        self.assertIn(str(self.builtins.resolve()), sdk)
        self.assertIn(str(self.shared_library.resolve()), sdk)
        self.assertIn(str(self.napi_library.resolve()), sdk)
        self.assertIn(str(self.resource_header.resolve()), sdk)
        self.assertIn(str(self.triple_header.resolve()), sdk)
        self.assertEqual(len(self.evidence["sdkDirectories"]["include"]), len(self.include_dirs))
        self.assertEqual(self.evidence["compileCommandCount"], 1)

    def test_ninja_rules_are_fingerprinted(self):
        self.assertIn("native/build/cmake-x86_64/CMakeFiles/rules.ninja", self.evidence["sourceDigests"])

    # --- rejected build/adoption states ------------------------------------

    def test_pending_or_failed_build_cannot_be_adopted(self):
        for key, value in (("kind", "pending-python-native-build"), ("buildExitCode", 1),
                           ("dependencyCheckExitCode", 1), ("schemaVersion", 1)):
            with self.subTest(key=key):
                evidence = copy.deepcopy(self.evidence)
                evidence[key] = value
                with self.assertRaises(ValueError):
                    verify(self.root, evidence, self.library)

    def test_generated_vm_drift_is_rejected(self):
        (self.root / "native/micropython_embed/py/vm.c").write_text("new guard", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "input changed"):
            verify(self.root, self.evidence, self.library)

    def test_new_compilation_input_is_rejected(self):
        _write(self.root / "native/micropython_embed/py/new.c", "new input")
        with self.assertRaisesRegex(ValueError, "inventory changed"):
            verify(self.root, self.evidence, self.library)

    def test_included_ninja_rule_drift_is_rejected(self):
        (self.build / "CMakeFiles/rules.ninja").write_text("# changed rule bodies\n", encoding="utf-8")
        # rules.ninja is itself fingerprinted, so drift fails the direct digest
        # check before the broader inventory comparison runs.
        with self.assertRaisesRegex(ValueError, "input changed"):
            verify(self.root, self.evidence, self.library)

    def test_compiler_driver_change_is_rejected(self):
        self.clangxx.write_bytes(b"different compiler")
        with self.assertRaisesRegex(ValueError, "toolchain changed"):
            verify(self.root, self.evidence, self.library)

    def test_host_python_change_is_rejected(self):
        self.python.write_bytes(b"different interpreter")
        with self.assertRaisesRegex(ValueError, "toolchain changed"):
            verify(self.root, self.evidence, self.library)

    def test_extensionless_header_drift_is_rejected(self):
        self.libcxx_header.write_text("changed <vector>", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "SDK input changed"):
            verify(self.root, self.evidence, self.library)

    def test_static_library_drift_is_rejected(self):
        self.static_library.write_bytes(b"replaced archive")
        with self.assertRaisesRegex(ValueError, "SDK input changed"):
            verify(self.root, self.evidence, self.library)

    def test_removed_sdk_header_is_rejected(self):
        self.sysroot_header.unlink()
        with self.assertRaisesRegex(ValueError, "SDK input changed"):
            verify(self.root, self.evidence, self.library)

    def test_substituted_so_is_rejected(self):
        self.library.write_bytes(self.library.read_bytes() + b"old-library")
        with self.assertRaisesRegex(ValueError, "does not match completed"):
            verify(self.root, self.evidence, self.library)

    def test_wrong_abi_with_matching_digest_is_rejected(self):
        self.evidence["abi"] = "arm64-v8a"
        with self.assertRaisesRegex(ValueError, "ABI mismatch"):
            verify(self.root, self.evidence, self.library)

    # --- rejected capture states (metadata-only) ---------------------------

    def test_missing_compilation_commands_is_rejected(self):
        (self.build / "compile_commands.json").unlink()
        with self.assertRaisesRegex(ValueError, "omits compilation commands"):
            snapshot(self.root, self.build, python=self.python)

    def test_missing_compiler_metadata_is_rejected(self):
        (self.metadata_dir / "CMakeCXXCompiler.cmake").unlink()
        with self.assertRaisesRegex(ValueError, "compiler metadata"):
            snapshot(self.root, self.build, python=self.python)

    def test_ambiguous_compiler_metadata_is_rejected(self):
        other = self.build / "CMakeFiles/9.9.9"
        other.mkdir()
        (other / "CMakeCCompiler.cmake").write_text("set(CMAKE_C_COMPILER \"x\")\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Ambiguous"):
            snapshot(self.root, self.build, python=self.python)

    def test_missing_configured_compiler_is_rejected(self):
        self.clangxx.unlink()
        with self.assertRaisesRegex(ValueError, "cxxCompiler is missing"):
            snapshot(self.root, self.build, python=self.python)

    def test_missing_required_role_is_rejected(self):
        (self.metadata_dir / "CMakeCCompiler.cmake").write_text(
            f'set(CMAKE_AR "{self._cmake_value(self.archiver)}")\n', encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "required tool roles"):
            snapshot(self.root, self.build, python=self.python)

    def test_missing_host_python_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "host Python is missing"):
            snapshot(self.root, self.build, python=self.sdk / "python/absent.exe")

    def test_missing_sdk_directory_is_rejected(self):
        (self.metadata_dir / "CMakeCCompiler.cmake").write_text("\n".join([
            f'set(CMAKE_C_COMPILER "{self._cmake_value(self.clang)}")',
            f'set(CMAKE_AR "{self._cmake_value(self.archiver)}")',
            f'set(CMAKE_RANLIB "{self._cmake_value(self.ranlib)}")',
            f'set(CMAKE_LINKER "{self._cmake_value(self.linker)}")',
            'set(CMAKE_C_IMPLICIT_INCLUDE_DIRECTORIES "'
            + ";".join(self._cmake_value(path) for path in self.include_dirs[1:]) + '")',
            'set(CMAKE_C_IMPLICIT_LINK_DIRECTORIES "'
            + self._cmake_value(self.sdk / "llvm/lib/absent") + '")',
            "",
        ]), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Missing configured SDK input directory"):
            snapshot(self.root, self.build, python=self.python)

    def test_missing_ninja_rules_is_rejected(self):
        (self.build / "CMakeFiles/rules.ninja").unlink()
        with self.assertRaisesRegex(ValueError, "Ninja rules"):
            snapshot(self.root, self.build, python=self.python)

    def test_metadata_compiler_swap_is_rejected(self):
        text = (self.metadata_dir / "CMakeCCompiler.cmake").read_text(encoding="utf-8")
        (self.metadata_dir / "CMakeCCompiler.cmake").write_text(
            text.replace(self._cmake_value(self.clang), self._cmake_value(self.clangxx)), encoding="utf-8")
        with self.assertRaises(ValueError):
            verify(self.root, self.evidence, self.library)

    # --- rejected manifest shapes -----------------------------------------

    def test_manifest_without_required_role_is_rejected(self):
        self.evidence["toolRoles"].pop("ar")
        with self.assertRaisesRegex(ValueError, "required tool roles"):
            verify(self.root, self.evidence, self.library)

    def test_manifest_without_python_role_is_rejected(self):
        self.evidence["toolRoles"].pop("python")
        with self.assertRaisesRegex(ValueError, "required tool roles"):
            verify(self.root, self.evidence, self.library)

    def test_manifest_without_sdk_inputs_is_rejected(self):
        self.evidence.pop("sdkDigests")
        with self.assertRaisesRegex(ValueError, "lacks configured SDK inputs"):
            verify(self.root, self.evidence, self.library)

    def test_manifest_without_extensionless_libcxx_is_rejected(self):
        self.evidence["sdkDigests"] = {
            name: value for name, value in self.evidence["sdkDigests"].items()
            if not (Path(name).suffix == "" and "libcxx" in name.replace("\\", "/"))
        }
        with self.assertRaisesRegex(ValueError, "extensionless libc\\+\\+"):
            verify(self.root, self.evidence, self.library)

    def test_manifest_without_static_libraries_is_rejected(self):
        self.evidence["sdkDigests"] = {
            name: value for name, value in self.evidence["sdkDigests"].items()
            if not name.endswith(".a")
        }
        with self.assertRaisesRegex(ValueError, "configured static libraries"):
            verify(self.root, self.evidence, self.library)


if __name__ == "__main__":
    unittest.main()
