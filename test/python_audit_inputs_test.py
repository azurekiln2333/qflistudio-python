"""Current-source inventory regressions using inert temporary files only."""
from __future__ import annotations

import copy
import hashlib
from pathlib import Path
import tempfile
import unittest

from tool.python_audit_inputs import collect_inputs, verify_inputs


class AuditInputsTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="python_audit_inputs_")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name) / "product"
        self.core = Path(temporary.name) / "core"
        self.product_source = self.write(self.root / "lib/runtime.dart", "product")
        self.core_source = self.write(self.core / "lib/editor.dart", "core")
        self.extra_source = self.write(self.root / "native/micropython_embed/py/vm.c", "native")
        product, core = collect_inputs(self.root, self.core)
        product[self.extra_source.relative_to(self.root).as_posix()] = hashlib.sha256(
            self.extra_source.read_bytes()).hexdigest()
        self.evidence = {"sourceDigests": product, "coreSourceDigests": core}

    @staticmethod
    def write(path, content):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return path

    def test_unchanged_inventory_and_explicit_extra_are_valid(self):
        self.assertEqual(verify_inputs(self.evidence, self.root, self.core), (1, 1))

    def test_new_product_source_is_rejected(self):
        self.write(self.root / "lib/new.dart", "new")
        with self.assertRaisesRegex(ValueError, "sourceDigests"):
            verify_inputs(self.evidence, self.root, self.core)

    def test_new_core_source_is_rejected(self):
        self.write(self.core / "lib/new.dart", "new")
        with self.assertRaisesRegex(ValueError, "coreSourceDigests"):
            verify_inputs(self.evidence, self.root, self.core)

    def test_changed_declared_sources_are_rejected(self):
        for path in (self.product_source, self.core_source, self.extra_source):
            with self.subTest(path=path.name):
                original = path.read_bytes()
                path.write_bytes(b"changed")
                with self.assertRaises(ValueError):
                    verify_inputs(self.evidence, self.root, self.core)
                path.write_bytes(original)

    def test_removed_declared_sources_are_rejected(self):
        for path in (self.product_source, self.core_source, self.extra_source):
            with self.subTest(path=path.name):
                original = path.read_bytes()
                path.unlink()
                with self.assertRaisesRegex(ValueError, "disappeared"):
                    verify_inputs(self.evidence, self.root, self.core)
                path.write_bytes(original)

    def test_missing_and_empty_inventory_are_rejected(self):
        for label in ("sourceDigests", "coreSourceDigests"):
            for replacement in (None, {}):
                with self.subTest(label=label, replacement=replacement):
                    evidence = copy.deepcopy(self.evidence)
                    evidence[label] = replacement
                    with self.assertRaisesRegex(ValueError, "Missing build input inventory"):
                        verify_inputs(evidence, self.root, self.core)

    def test_non_object_evidence_is_rejected(self):
        for replacement in (None, [], "evidence", 42):
            with self.subTest(replacement=replacement):
                with self.assertRaisesRegex(ValueError, "must be a JSON object"):
                    verify_inputs(replacement, self.root, self.core)

    def test_escaping_declared_names_are_rejected(self):
        outside = self.root.parent / "outside.txt"
        outside.write_text("outside", encoding="utf-8")
        outside_digest = hashlib.sha256(outside.read_bytes()).hexdigest()
        for name in (
            "../outside.txt",
            "a/../../outside.txt",
            str(outside),
            "..\\outside.txt",
            "C:/outside.txt",
            "/outside.txt",
        ):
            with self.subTest(name=name):
                evidence = copy.deepcopy(self.evidence)
                evidence["sourceDigests"][name] = outside_digest
                with self.assertRaisesRegex(ValueError, "Invalid declared build input path"):
                    verify_inputs(evidence, self.root, self.core)


if __name__ == "__main__":
    unittest.main()
