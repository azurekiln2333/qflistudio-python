#!/usr/bin/env python3
"""Real embedded-VM debugger tests, controlled from a second native thread.

Usage: python native/tests/debugger.py <DLL-or-shared-library> [--report file]
No Python execution or debugger operation is mocked.
"""

from __future__ import annotations

import argparse
import ctypes as C
import hashlib
import json
import pathlib
import tempfile
import threading
import time
import unittest


class NativeResult(C.Structure):
    _fields_ = [("exit_code", C.c_int), ("output", C.c_void_p),
                ("error", C.c_void_p), ("truncated", C.c_int)]


class Native:
    def __init__(self, path: pathlib.Path):
        self.path = path.resolve()
        self.lib = C.CDLL(str(self.path))
        definitions = {
            "debug_capabilities": ([], C.c_uint32),
            "debug_create": ([C.c_char_p, C.c_char_p, C.c_int], C.c_void_p),
            "debug_retain": ([C.c_void_p], None),
            "debug_release": ([C.c_void_p], None),
            "debug_set_breakpoints": ([C.c_void_p, C.POINTER(C.c_char_p), C.POINTER(C.c_uint32), C.c_size_t], C.c_int),
            "debug_execute_into": ([C.POINTER(NativeResult), C.c_char_p, C.c_char_p, C.c_int, C.c_void_p], None),
            "debug_command": ([C.c_void_p, C.c_uint64, C.c_int], C.c_int),
            "debug_poll_json": ([C.c_void_p, C.c_size_t], C.c_void_p),
            "debug_json_free": ([C.c_void_p], None),
            "result_free": ([C.POINTER(NativeResult)], None),
            "execute_into": ([C.POINTER(NativeResult), C.c_char_p, C.c_char_p, C.c_int,
                              C.c_char_p, C.c_char_p, C.c_int, C.c_void_p, C.c_char_p, C.c_char_p], None),
        }
        for name, (arguments, returns) in definitions.items():
            function = getattr(self.lib, "qfli_py_" + name)
            function.argtypes = arguments
            function.restype = returns
            setattr(self, name, function)

    def result(self, result: NativeResult):
        value = (result.exit_code,
                 C.string_at(result.output).decode("utf-8") if result.output else "",
                 C.string_at(result.error).decode("utf-8") if result.error else None,
                 bool(result.truncated))
        self.result_free(C.byref(result))
        return value

    def run(self, source: str, root: pathlib.Path, entry: pathlib.Path,
            *, compile_only=False, artifact=None, bytecode=None):
        result = NativeResult()
        self.execute_into(C.byref(result), source.encode(), b"", 8192,
                          str(root).encode(), str(entry).encode(), compile_only, None,
                          str(artifact).encode() if artifact else None,
                          str(bytecode).encode() if bytecode else None)
        return self.result(result)


class DebugRun:
    def __init__(self, native: Native, root: pathlib.Path, source: str,
                 *, filename="main.py", entry=True, breakpoints=(), start=True):
        self.native = native
        self.root = root
        self.entry = root / filename
        self.entry.parent.mkdir(parents=True, exist_ok=True)
        self.entry.write_text(source, encoding="utf-8")
        self.source = source
        self.pointer = native.debug_create(str(root).encode(), str(self.entry).encode(), entry)
        if not self.pointer:
            raise AssertionError("Native debug_create rejected valid project")
        self.raw_result = NativeResult()
        self.result = None
        self.events = []
        self.pending = []
        self.status = None
        self.worker = threading.Thread(target=self._run, daemon=True)
        if breakpoints:
            status = self.breakpoints(breakpoints)
            if status:
                raise AssertionError(f"Native rejected valid breakpoints: {status}")
        if start:
            self.worker.start()

    def _run(self):
        self.native.debug_execute_into(C.byref(self.raw_result), self.source.encode(), b"", 8192, self.pointer)
        self.result = self.native.result(self.raw_result)

    def breakpoints(self, pairs):
        paths = [str(path).encode() for path, _ in pairs]
        return self.native.debug_set_breakpoints(self.pointer,
            (C.c_char_p * len(paths))(*paths),
            (C.c_uint32 * len(paths))(*(line for _, line in pairs)), len(paths))

    def poll(self, limit=0):
        pointer = self.native.debug_poll_json(self.pointer, limit)
        if not pointer:
            raise AssertionError("Native poll failed")
        try:
            data = json.loads(C.string_at(pointer))
        finally:
            self.native.debug_json_free(pointer)
        self.events.extend(data["events"])
        self.pending.extend(data["events"])
        self.status = data
        return data

    def event(self, state, timeout=4):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for index, item in enumerate(self.pending):
                if item["state"] == state:
                    del self.pending[index]
                    return item
            self.poll()
            if self.result is not None and state != "terminated":
                raise AssertionError(f"Program exited before {state}: {self.result}; {self.events}")
            time.sleep(.002)
        raise AssertionError(f"No {state} event: {self.events}")

    def command(self, pause, command):
        return self.native.debug_command(self.pointer, pause["pauseGeneration"], command)

    def finish(self, timeout=4):
        self.worker.join(timeout)
        if self.worker.is_alive():
            self.native.debug_command(self.pointer, 0, 5)
            self.worker.join(2)
            raise AssertionError("Debug worker did not settle")
        self.poll()
        return self.result

    def close(self):
        if self.pointer is None:
            return
        if self.worker.is_alive():
            self.native.debug_command(self.pointer, 0, 5)
            self.worker.join(3)
            if self.worker.is_alive():
                raise AssertionError("Native worker leaked on cleanup")
        self.native.debug_release(self.pointer)
        self.pointer = None


NATIVE: Native


class DebuggerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="qfli-debug-")
        self.root = pathlib.Path(self.directory.name).resolve()
        self.runs = []

    def tearDown(self):
        for run in reversed(self.runs):
            run.close()
        self.directory.cleanup()

    def debug(self, source, **options):
        run = DebugRun(NATIVE, self.root, source, **options)
        self.runs.append(run)
        return run

    @staticmethod
    def variables(frame):
        return {item["name"]: item for item in frame["variables"]}

    def test_capabilities_and_actual_pause_before_file_effect(self):
        self.assertEqual(NATIVE.debug_capabilities(), 31)
        entry = self.root / "main.py"
        run = self.debug("x=1\nwith open('marker.txt','w') as f:\n    f.write('done')\nprint(x)\n",
                         entry=False, breakpoints=[(entry, 2)])
        pause = run.event("paused")
        self.assertEqual(pause["reason"], "breakpoint")
        self.assertEqual(pause["line"], 2)
        self.assertFalse((self.root / "marker.txt").exists())
        time.sleep(.03)
        self.assertTrue(run.worker.is_alive())
        self.assertEqual(run.command(pause, 1), 0)
        self.assertEqual(run.finish()[:3], (0, "1\n", None))
        self.assertEqual((self.root / "marker.txt").read_text(), "done")
        terminal = run.event("terminated")
        self.assertEqual(terminal["exitCode"], 0)
        self.assertEqual([e["sequence"] for e in run.events], sorted(set(e["sequence"] for e in run.events)))

    def test_named_locals_unbound_deleted_and_changed_after_step(self):
        source = "def f(a):\n    b=a+1\n    del b\n    c=a*2\n    return c\nprint(f(4))\n"
        run = self.debug(source, entry=False, breakpoints=[(self.root / "main.py", 2)])
        pause = run.event("paused")
        self.assertEqual([f["name"] for f in pause["frames"]], ["f", "<module>"])
        values = self.variables(pause["frames"][0])
        self.assertEqual(values["a"]["value"], "4")
        self.assertTrue(values["b"]["unbound"])
        self.assertTrue(values["c"]["unbound"])
        self.assertEqual(run.command(pause, 2), 0)
        pause = run.event("paused")
        self.assertEqual(pause["line"], 3)
        self.assertEqual(self.variables(pause["frames"][0])["b"]["value"], "5")
        self.assertEqual(run.command(pause, 2), 0)
        pause = run.event("paused")
        self.assertEqual(pause["line"], 4)
        self.assertTrue(self.variables(pause["frames"][0])["b"]["unbound"])
        run.command(pause, 1)
        self.assertEqual(run.finish()[:2], (0, "8\n"))

    def test_module_globals_with_heap_string_names_are_not_silently_missing(self):
        source = "name='dynamic'+'_'+'global'\nglobals()[name]=7\nprint(dynamic_global)\n"
        run = self.debug(source, entry=False, breakpoints=[(self.root / "main.py", 3)])
        pause = run.event("paused")
        self.assertEqual(self.variables(pause["frames"][0])["dynamic_global"]["value"], "7")
        run.command(pause, 1)
        self.assertEqual(run.finish()[:2], (0, "7\n"))

    def test_closure_cell_free_arguments_and_shadowed_globals(self):
        source = ("shared=99\ndef outer(a):\n    shared=a+2\n    def inner(b):\n"
                  "        local=shared+b\n        return local\n    return inner(3)\nprint(outer(4))\n")
        run = self.debug(source, entry=False, breakpoints=[(self.root / "main.py", 6)])
        pause = run.event("paused")
        self.assertEqual([f["name"] for f in pause["frames"]], ["inner", "outer", "<module>"])
        values = self.variables(pause["frames"][0])
        self.assertEqual({k: values[k]["value"] for k in ("b", "shared", "local")},
                         {"b": "3", "shared": "6", "local": "9"})
        self.assertEqual(self.variables(pause["frames"][1])["shared"]["value"], "6")
        self.assertEqual(self.variables(pause["frames"][2])["shared"]["value"], "99")
        run.command(pause, 1)
        self.assertEqual(run.finish()[:2], (0, "9\n"))

    def test_step_into_over_and_out_use_real_frames(self):
        source = ("def inner(x):\n    y=x+1\n    return y\ndef outer():\n"
                  "    a=inner(2)\n    b=inner(a)\n    return b\nvalue=outer()\nprint(value)\n")
        run = self.debug(source, entry=False, breakpoints=[(self.root / "main.py", 5)])
        pause = run.event("paused")
        self.assertEqual(run.command(pause, 3), 0)
        pause = run.event("paused")
        self.assertEqual((pause["line"], pause["frames"][0]["name"]), (6, "outer"))
        self.assertEqual(self.variables(pause["frames"][0])["a"]["value"], "3")
        self.assertEqual(run.command(pause, 2), 0)
        pause = run.event("paused")
        self.assertEqual((pause["line"], pause["frames"][0]["name"]), (2, "inner"))
        self.assertEqual(run.command(pause, 4), 0)
        pause = run.event("paused")
        self.assertEqual((pause["line"], pause["frames"][0]["name"]), (7, "outer"))
        self.assertEqual(self.variables(pause["frames"][0])["b"]["value"], "4")
        run.command(pause, 1)
        self.assertEqual(run.finish()[:2], (0, "4\n"))

    def test_step_over_return_does_not_step_into_same_line_sibling(self):
        source = "def f(x):\n    return x+1\nvalue=f(1)+f(2)\nprint(value)\n"
        run = self.debug(source, entry=False, breakpoints=[(self.root / "main.py", 2)])
        pause = run.event("paused")
        # Remove the breakpoint so the second call can be skipped by step-over.
        self.assertEqual(run.breakpoints([]), 0)
        run.command(pause, 3)
        pause = run.event("paused")
        self.assertEqual((pause["line"], pause["frames"][0]["name"]), (4, "<module>"))
        run.command(pause, 1)
        self.assertEqual(run.finish()[:2], (0, "5\n"))

    def test_repeated_loop_breakpoint_and_stale_generation(self):
        run = self.debug("for n in (0,1):\n    marker=n\n    print(n)\n", entry=False,
                         breakpoints=[(self.root / "main.py", 3)])
        first = run.event("paused")
        self.assertEqual(self.variables(first["frames"][0])["n"]["value"], "0")
        self.assertEqual(run.command(first, 1), 0)
        second = run.event("paused")
        self.assertGreater(second["pauseGeneration"], first["pauseGeneration"])
        self.assertEqual(run.command(first, 1), 3)
        self.assertTrue(run.worker.is_alive())
        self.assertEqual(self.variables(second["frames"][0])["n"]["value"], "1")
        self.assertEqual(run.breakpoints([]), 0)
        run.command(second, 1)
        self.assertEqual(run.finish()[:2], (0, "0\n1\n"))

    def test_stop_paused_and_ordinary_recovery(self):
        run = self.debug("print('must not print')\n")
        pause = run.event("paused")
        self.assertEqual(run.command(pause, 5), 0)
        self.assertEqual(run.finish()[:3], (130, "", "KeyboardInterrupt\n"))
        self.assertEqual(run.event("terminated")["reason"], "stopped")
        self.assertEqual(run.command(pause, 1), 2)
        self.assertEqual(NATIVE.run("print(42)\n", self.root, run.entry)[:3], (0, "42\n", None))

    def test_stop_same_line_infinite_loop(self):
        run = self.debug("while True: pass\n", entry=False)
        run.event("running")
        time.sleep(.02)
        self.assertEqual(NATIVE.debug_command(run.pointer, 0, 5), 0)
        self.assertEqual(run.finish()[0], 130)

    def test_stop_while_sleeping(self):
        run = self.debug("import time\ntime.sleep(30)\n", entry=False)
        run.event("running")
        time.sleep(.03)
        start = time.monotonic()
        NATIVE.debug_command(run.pointer, 0, 5)
        self.assertEqual(run.finish()[0], 130)
        self.assertLess(time.monotonic() - start, 1)

    def test_stop_before_start_duplicate_start_and_final_drain(self):
        run = self.debug("print('never')\n", entry=False, start=False)
        self.assertEqual(NATIVE.debug_command(run.pointer, 0, 5), 0)
        run.worker.start()
        run.worker.join(2)
        self.assertEqual(run.result[0], 130)
        # No poll was needed for final native state to survive worker exit.
        self.assertEqual(run.event("terminated")["exitCode"], 130)
        second = NativeResult()
        NATIVE.debug_execute_into(C.byref(second), b"print('duplicate')", b"", 8192, run.pointer)
        result = NATIVE.result(second)
        self.assertEqual(result[0], 1)
        self.assertIn("already executed", result[2])
        self.assertEqual(run.poll()["events"], [])

    def test_last_owner_release_while_paused_stops_worker(self):
        run = self.debug("print('never')\n")
        run.event("paused")
        NATIVE.debug_release(run.pointer)
        run.pointer = None
        run.worker.join(2)
        self.assertFalse(run.worker.is_alive())
        self.assertEqual(run.result[0], 130)
        self.assertEqual(NATIVE.run("print('ok')\n", self.root, run.entry)[1], "ok\n")

    def test_runtime_and_compile_errors_settle_and_recover(self):
        for source, error in [("if True print(3)\n", "SyntaxError"), ("print(1/0)\n", "ZeroDivisionError")]:
            run = self.debug(source, entry=False)
            self.assertEqual(run.finish()[0], 1)
            self.assertIn(error, run.result[2])
            self.assertEqual(run.event("terminated")["reason"], "error")
        self.assertEqual(NATIVE.run("print('recovered')\n", self.root, self.root / "main.py")[1], "recovered\n")

    def test_error_diagnostic_user_formatting_does_not_reenter_debugger(self):
        source = "class Message:\n    def __str__(self):\n        return 'diagnostic'\nraise ValueError(Message())\n"
        run = self.debug(source, entry=False, breakpoints=[(self.root / "main.py", 3)])
        self.assertEqual(run.finish()[0], 1)
        self.assertIn("ValueError: diagnostic", run.result[2])
        self.assertFalse(any(e["state"] == "paused" for e in run.events))

    def test_import_unicode_path_and_reject_outside_missing_or_bundled(self):
        helper = self.root / "模块.py"
        helper.write_text("def value():\n    answer=7\n    return answer\n", encoding="utf-8")
        # Unicode filename import uses __import__, without assuming Unicode identifiers.
        source = "helper=__import__('模块')\nprint(helper.value())\n"
        run = self.debug(source, filename="子目录/main.py", entry=False, breakpoints=[(helper, 3)])
        pause = run.event("paused")
        self.assertEqual(pathlib.Path(pause["file"]), helper)
        self.assertEqual(self.variables(pause["frames"][0])["answer"]["value"], "7")
        with tempfile.TemporaryDirectory() as outside:
            other = pathlib.Path(outside) / "main.py"
            other.write_text("print(8)")
            self.assertEqual(run.breakpoints([(other, 1)]), 1)
        self.assertEqual(run.breakpoints([(self.root / "missing.py", 1)]), 1)
        bundled = self.root / ".qfli/python/bundled/v1/synthetic.py"
        bundled.parent.mkdir(parents=True)
        bundled.write_text("x=1\n")
        self.assertEqual(run.breakpoints([(bundled, 1)]), 1)
        run.command(pause, 1)
        self.assertEqual(run.finish()[:2], (0, "7\n"))

    def test_blank_breakpoint_never_relocated_and_dynamic_replacement(self):
        run = self.debug("# comment\n\nx=1\nprint(x)\n", entry=False,
                         breakpoints=[(self.root / "main.py", 2)])
        self.assertEqual(run.finish()[:2], (0, "1\n"))
        self.assertFalse(any(e["state"] == "paused" for e in run.events))
        second = self.debug("x=1\nx+=1\nprint(x)\n")
        pause = second.event("paused")
        self.assertEqual(second.breakpoints([(second.entry, 3)]), 0)
        second.command(pause, 1)
        pause = second.event("paused")
        self.assertEqual(pause["line"], 3)
        second.command(pause, 1)
        self.assertEqual(second.finish()[1], "2\n")

    def test_snapshot_does_not_call_user_methods_and_is_bounded(self):
        source = ("counter=0\nclass Hostile:\n"
                  "    def __repr__(self):\n        global counter\n        counter+=1\n        return 'bad'\n"
                  "    def __str__(self):\n        return self.__repr__()\n"
                  "    @property\n    def property(self):\n        return self.__repr__()\n"
                  "    def __iter__(self):\n        return self.__repr__()\n"
                  "    def __eq__(self,other):\n        return self.__repr__()\n"
                  "    def __hash__(self):\n        return 42\n"
                  "hostile=Hostile()\nitems=[hostile]\nitems.append(items)\n"
                  "mapping={hostile:hostile}\nlarge='中'*10000\n"
                  "assert counter==0\nprint(counter)\n")
        line = source.splitlines().index("assert counter==0") + 1
        run = self.debug(source, entry=False, breakpoints=[(self.root / "main.py", line)])
        pause = run.event("paused")
        variables = self.variables(pause["frames"][0])
        self.assertEqual(variables["counter"]["value"], "0")
        self.assertEqual(variables["hostile"]["value"], "<Hostile>")
        self.assertTrue(variables["items"]["children"][1]["cycle"])
        self.assertTrue(variables["large"]["truncated"])
        self.assertLess(len(variables["large"]["value"].encode()), 257)
        self.assertEqual(variables["mapping"]["children"][0]["key"]["value"], "<Hostile>")
        run.command(pause, 1)
        self.assertEqual(run.finish()[:2], (0, "0\n"))

    def test_class_scope_unavailable_and_generator_real_locals(self):
        source = "class A:\n    value=2\ndef gen(x):\n    y=x+1\n    yield y\n    y+=1\n    yield y\nprint(list(gen(4)))\n"
        run = self.debug(source, entry=False, breakpoints=[(self.root / "main.py", 2), (self.root / "main.py", 7)])
        pause = run.event("paused")
        self.assertFalse(pause["frames"][0]["localsAvailable"])
        self.assertEqual(pause["frames"][0]["localsReason"], "class-namespace-unavailable")
        run.command(pause, 1)
        pause = run.event("paused")
        self.assertEqual(pause["frames"][0]["name"], "gen")
        self.assertEqual(self.variables(pause["frames"][0])["y"]["value"], "6")
        # Upstream emits a genuine repeat line event when a yielded generator
        # resumes. Removing the breakpoint also proves atomic live replacement.
        self.assertEqual(run.breakpoints([]), 0)
        run.command(pause, 1)
        self.assertEqual(run.finish()[:2], (0, "[5, 6]\n"))

    def test_mpy_import_with_deleted_source_does_not_fabricate_source_pause(self):
        helper = self.root / "compiled.py"
        helper_source = "def answer(x):\n    local=x+2\n    return local\n"
        helper.write_text(helper_source)
        artifact = self.root / "compiled.mpy"
        result = NATIVE.run(helper_source, self.root, helper, compile_only=True, artifact=artifact)
        self.assertEqual(result[0], 0, result)
        # Keep its source for breakpoint file identity, but import .mpy by
        # temporarily naming source elsewhere after installing configuration.
        run = self.debug("import compiled\nprint(compiled.answer(3))\n", entry=False, start=False,
                         breakpoints=[(helper, 3)])
        saved = helper.with_suffix(".source")
        helper.rename(saved)
        run.worker.start()
        # A deleted source has no accepted canonical identity, so it must not
        # fabricate a source pause. Its bytecode remains executable.
        self.assertEqual(run.finish()[:2], (0, "5\n"))
        self.assertFalse(any(e["state"] == "paused" for e in run.events))

    def test_mpy_import_with_available_source_has_no_fabricated_named_locals(self):
        original = self.root / "sources/helper.py"
        original.parent.mkdir()
        source = "def answer(x):\n    local=x+2\n    return local\n"
        original.write_text(source)
        artifact = self.root / "compiled.mpy"
        result = NATIVE.run(source, self.root, original, compile_only=True, artifact=artifact)
        self.assertEqual(result[0], 0, result)
        # Import finds only compiled.mpy at the root; its real source filename
        # remains the separate existing sources/helper.py from compilation.
        run = self.debug("import compiled\nprint(compiled.answer(3))\n", entry=False,
                         breakpoints=[(original, 3)])
        pause = run.event("paused")
        self.assertEqual(pathlib.Path(pause["file"]), original)
        self.assertFalse(pause["frames"][0]["localsAvailable"])
        self.assertEqual(pause["frames"][0]["localsReason"], "no-source-metadata")
        self.assertEqual(pause["frames"][0]["variables"], [])
        run.command(pause, 1)
        self.assertEqual(run.finish()[:2], (0, "5\n"))

    def test_stop_queued_behind_another_vm_never_executes_entry(self):
        entry = self.root / "normal.py"
        entry.write_text("import time\ntime.sleep_ms(150)\n")
        normal_result = []
        worker = threading.Thread(target=lambda: normal_result.append(
            NATIVE.run(entry.read_text(), self.root, entry)))
        worker.start()
        time.sleep(.03)
        run = self.debug("open('should-not-exist','w').write('bad')\n", entry=False)
        run.event("running")
        NATIVE.debug_command(run.pointer, 0, 5)
        self.assertTrue(worker.is_alive())
        self.assertEqual(run.finish()[0], 130)
        worker.join(2)
        self.assertFalse(worker.is_alive())
        self.assertEqual(normal_result[0][0], 0)
        self.assertFalse((self.root / "should-not-exist").exists())

    def test_primitive_values_and_container_bounds(self):
        source = ("def values(*args,**kwargs):\n"
                  "    integer=1234567\n"
                  "    truth=True\n    nothing=None\n"
                  "    decimal=1.25\n    raw=b'\\x00\\xff'\n"
                  "    seq=list(range(100))\n    return integer\nvalues(3,name='ok')\n")
        run = self.debug(source, entry=False, breakpoints=[(self.root / "main.py", 8)])
        pause = run.event("paused")
        values = self.variables(pause["frames"][0])
        self.assertEqual(values["integer"]["value"], "1234567")
        self.assertEqual(values["truth"]["value"], "True")
        self.assertEqual(values["nothing"]["value"], "None")
        self.assertEqual(values["decimal"]["value"], "1.25")
        self.assertEqual(values["raw"]["value"], "00ff")
        self.assertTrue(values["seq"]["truncated"])
        self.assertEqual(len(values["seq"]["children"]), 4)
        self.assertEqual(values["args"]["children"][0]["value"], "3")
        self.assertEqual(values["kwargs"]["children"][0]["item"]["value"], "ok")
        run.command(pause, 1)
        self.assertEqual(run.finish()[0], 0)

    def test_comprehension_frame_has_real_metadata(self):
        source = "values=[x*2 for x in (1,2)]\nprint(values)\n"
        run = self.debug(source, entry=False, breakpoints=[(self.root / "main.py", 1)])
        first = run.event("paused")
        run.command(first, 1)
        pause = run.event("paused")
        self.assertEqual(pause["frames"][0]["name"], "<listcomp>")
        self.assertTrue(pause["frames"][0]["localsAvailable"])
        self.assertIn("x", self.variables(pause["frames"][0]))
        run.breakpoints([])
        run.command(pause, 1)
        self.assertEqual(run.finish()[:2], (0, "[2, 4]\n"))

    def test_upstream_loop_guard_line_is_reported_without_invented_values(self):
        source = "for n in range(2):\n    print(n)\n"
        run = self.debug(source, entry=False, breakpoints=[(self.root / "main.py", 2)])
        pause = run.event("paused")
        # The upstream monotonic line table labels the optimized range entry
        # guard with its final body line. That event is genuine, but n is not
        # bound yet. We expose the actual state rather than a guessed 0.
        self.assertEqual(pause["line"], 2)
        self.assertNotIn("n", self.variables(pause["frames"][0]))
        run.breakpoints([])
        run.command(pause, 1)
        self.assertEqual(run.finish()[:2], (0, "0\n1\n"))

    def test_argument_bounds_and_extra_owner_reference(self):
        run = self.debug("print('ok')\n")
        pause = run.event("paused")
        self.assertEqual(NATIVE.debug_command(run.pointer, pause["pauseGeneration"], 6), 1)
        self.assertEqual(NATIVE.debug_set_breakpoints(run.pointer, None, None, 129), 1)
        self.assertEqual(NATIVE.debug_set_breakpoints(run.pointer,
            (C.c_char_p * 1)(str(run.entry).encode()), (C.c_uint32 * 1)(1), 129), 4)
        self.assertFalse(NATIVE.debug_poll_json(run.pointer, 100))
        NATIVE.debug_retain(run.pointer)
        NATIVE.debug_release(run.pointer)
        self.assertTrue(run.worker.is_alive())
        run.command(pause, 1)
        self.assertEqual(run.finish()[:2], (0, "ok\n"))

    def test_small_poll_preserves_pause_until_sufficient_buffer(self):
        source = "\n".join(f"value{i}='x'*200" for i in range(20)) + "\nprint('ok')\n"
        run = self.debug(source, entry=False, breakpoints=[(self.root / "main.py", 21)])
        deadline = time.monotonic() + 3
        required = None
        while time.monotonic() < deadline:
            envelope = run.poll(1024)
            if envelope.get("requiredBytes"):
                required = envelope["requiredBytes"]
                self.assertEqual(NATIVE.debug_command(run.pointer, envelope["pauseGeneration"], 1), 3)
                break
            time.sleep(.002)
        self.assertIsNotNone(required)
        self.assertGreater(required, 1024)
        pause = run.event("paused")
        self.assertEqual(pause["line"], 21)
        run.command(pause, 1)
        self.assertEqual(run.finish()[0], 0)

    def test_user_trace_replacement_is_reported_and_normal_settrace_works(self):
        run = self.debug("import sys\nsys.settrace(None)\nprint('trace disabled')\n", entry=False)
        self.assertEqual(run.finish()[:2], (0, "trace disabled\n"))
        self.assertTrue(run.event("terminated")["traceDisabled"])
        source = ("import sys\nevents=[]\ndef trace(frame,event,arg):\n"
                  "    events.append(event)\n    return trace\ndef f():\n    return 4\n"
                  "sys.settrace(trace)\nf()\nsys.settrace(None)\nprint('call' in events,'line' in events)\n")
        result = NATIVE.run(source, self.root, run.entry)
        self.assertEqual(result[:3], (0, "True True\n", None))

    def test_ordinary_trace_disable_does_not_retrace_resumed_generator(self):
        # The generator body is lines 7-8 and no module statement lives there, so
        # a lineno in that range can only come from the generator frame. Events
        # recorded after `pivot` are the ones raised once tracing was disabled.
        source = ("import sys\nevents=[]\n"
                  "def trace(frame,event,arg):\n    events.append((event,frame.f_lineno))\n    return trace\n"
                  "def gen():\n    yield 1\n    yield 2\n"
                  "g=gen()\nsys.settrace(trace)\nnext(g)\nsys.settrace(None)\n"
                  "pivot=len(events)\nnext(g)\nlate=0\n"
                  "for event,line in events[pivot:]:\n    if line >= 7 and line <= 8:\n        late+=1\n"
                  "print(pivot>0,late)\n")
        entry = self.root / "main.py"
        entry.write_text(source, encoding="utf-8")
        result = NATIVE.run(source, self.root, entry)
        self.assertEqual(result[:3], (0, "True 0\n", None), result)

    def test_debugger_trace_disable_suppresses_resumed_generator_pause(self):
        source = ("import sys\ndef gen():\n    yield 1\n    yield 2\n"
                  "g=gen()\nnext(g)\nsys.settrace(None)\nnext(g)\nprint('done')\n")
        entry = self.root / "main.py"
        # Control: a breakpoint on the first suspension point still pauses, so the
        # missing pause below cannot pass for generators that never pause at all.
        control = self.debug(source, entry=False, breakpoints=[(entry, 3)])
        pause = control.event("paused")
        self.assertEqual((pause["reason"], pause["line"]), ("breakpoint", 3))
        self.assertEqual(pause["frames"][0]["name"], "gen")
        self.assertEqual(control.command(pause, 1), 0)
        self.assertEqual(control.finish()[:2], (0, "done\n"))
        self.assertTrue(control.event("terminated")["traceDisabled"])
        # Subject: the resume after sys.settrace(None) must not keep using the
        # frame callback captured while tracing was still enabled.
        subject = self.debug(source, entry=False, breakpoints=[(entry, 4)])
        self.assertEqual(subject.finish()[:2], (0, "done\n"))
        self.assertEqual([e for e in subject.events if e["state"] == "paused"], [])
        self.assertTrue(subject.event("terminated")["traceDisabled"])

    def test_non_debug_nested_calls_do_not_allocate_trace_frames(self):
        source = ("import gc\ndef f(x):\n    return x+1\ngc.collect()\ngc.disable()\n"
                  "before=gc.mem_alloc()\nfor i in range(2000):\n    f(i)\n"
                  "after=gc.mem_alloc()\ngc.enable()\nprint(after-before)\n")
        result = NATIVE.run(source, self.root, self.root / "main.py")
        self.assertEqual(result[0], 0, result)
        self.assertLess(int(result[1]), 1024, result)


class RecordingResult(unittest.TextTestResult):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.passed = []

    def addSuccess(self, test):
        super().addSuccess(test)
        self.passed.append(test.id())


def main():
    global NATIVE
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("library", type=pathlib.Path)
    parser.add_argument("--report", type=pathlib.Path)
    args = parser.parse_args()
    NATIVE = Native(args.library)
    start = time.monotonic()
    result = unittest.TextTestRunner(verbosity=2, resultclass=RecordingResult).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(DebuggerTests))
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps({
            "schema": 1, "library": str(NATIVE.path),
            "sha256": hashlib.sha256(NATIVE.path.read_bytes()).hexdigest(),
            "kind": "real-native-controller-thread", "device": False,
            "tests": result.testsRun, "passed": result.passed,
            "failures": [(test.id(), trace) for test, trace in result.failures],
            "errors": [(test.id(), trace) for test, trace in result.errors],
            "elapsedSeconds": round(time.monotonic() - start, 3),
        }, indent=2) + "\n", encoding="utf-8")
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
