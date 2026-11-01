#!/usr/bin/env python3
"""Deterministic source-overlay checks against the unmodified pinned vendor."""

import hashlib
from pathlib import Path
import sys
import unittest

NATIVE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(NATIVE / "tools"))
from debug_overlay import EXPECTED, apply_debug_overlay


class DebugOverlayTests(unittest.TestCase):
    def test_each_checked_overlay_reproduces_tracked_source(self):
        for name, digest in EXPECTED.items():
            with self.subTest(name=name):
                vendor = NATIVE / "third_party/micropython/py" / name
                before = vendor.read_bytes()
                self.assertEqual(hashlib.sha256(before.replace(b"\r\n", b"\n")).hexdigest(), digest)
                patched = apply_debug_overlay(name, before)
                self.assertEqual(patched, (NATIVE / "micropython_embed/py" / name).read_bytes().replace(b"\r\n", b"\n"))
                self.assertEqual(apply_debug_overlay(name, before), patched)
                self.assertEqual(vendor.read_bytes(), before)

    def test_unpinned_source_and_double_application_fail(self):
        for name in EXPECTED:
            with self.subTest(name=name):
                original = (NATIVE / "third_party/micropython/py" / name).read_bytes()
                with self.assertRaisesRegex(ValueError, "pinned MicroPython"):
                    apply_debug_overlay(name, original + b"\n")
                with self.assertRaisesRegex(ValueError, "pinned MicroPython"):
                    apply_debug_overlay(name, apply_debug_overlay(name, original))

    def test_windows_line_endings_do_not_change_overlay(self):
        for name in EXPECTED:
            with self.subTest(name=name):
                original = (NATIVE / "third_party/micropython/py" / name).read_bytes().replace(b"\r\n", b"\n")
                self.assertEqual(apply_debug_overlay(name, original),
                                 apply_debug_overlay(name, original.replace(b"\n", b"\r\n")))

    def test_unrelated_source_remains_byte_identical(self):
        original = b"/* unrelated */\r\n"
        self.assertEqual(apply_debug_overlay("obj.c", original), original)


if __name__ == "__main__":
    unittest.main(verbosity=2)
