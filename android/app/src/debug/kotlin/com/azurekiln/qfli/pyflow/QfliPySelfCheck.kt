package com.azurekiln.qfli.pyflow

import android.content.Context
import android.util.Log
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

internal object QfliPySelfCheck {
    private const val TAG = "QfliPyNative"
    private val started = AtomicBoolean(false)

    private data class Case(
        val name: String,
        val source: String,
        val output: String = "",
        val exitCode: Int = 0,
        val error: String? = null,
        val stdin: String = "",
        val compileOnly: Boolean = false,
        val entryFile: String? = null,
        val prepare: (() -> Unit)? = null,
        val verify: (() -> Boolean)? = null,
    )

    fun start(context: Context) {
        if (!started.compareAndSet(false, true)) return
        QfliPyNative.executor.execute {
            try {
                check(QfliPyNative.availability()["available"] == true)
                Log.i(TAG, "Loaded MicroPython ${QfliPyNative.availability()["version"]}")
                val root = File.createTempFile("qfli_py_selfcheck_", "", context.cacheDir)
                check(root.delete() && root.mkdir())
                try {
                    runCases(root)
                } finally {
                    root.deleteRecursively()
                }
            } catch (error: Exception) {
                Log.e(TAG, "Native self-check failed", error)
            } catch (error: LinkageError) {
                Log.e(TAG, "Native library self-check failed", error)
            }
        }
    }

    private fun runCases(root: File) {
        val src = File(root, "src").also { check(it.mkdir()) }
        val pkg = File(src, "samplepkg").also { check(it.mkdir()) }
        val helper = File(src, "helper.py").also { it.writeText("answer = 42\n") }
        File(pkg, "__init__.py").writeText("from .value import answer\n")
        File(pkg, "value.py").writeText("answer = 84\n")
        val entry = File(src, "main.py").absolutePath
        val nonBmp = "\u4F60\u597D\uD83D\uDE80"
        val unicodeEntry = File(src, "main_\uD83D\uDE80.py").absolutePath
        val cases = listOf(
            Case("compile-run", "value = 42\nprint(value)", "42\n"),
            Case("fresh-globals", "print(value)", exitCode = 1, error = "NameError"),
            Case("script-expression", "42"),
            Case("syntax-error", "def broken(:\n    pass", exitCode = 1, error = "SyntaxError"),
            Case("runtime-error", "raise ValueError('bad')", exitCode = 1, error = "ValueError: bad"),
            Case("stdin", "print(input())", "Ada\n", stdin = "Ada\n"),
            Case("stdin-eof", "input()", exitCode = 1, error = "EOFError"),
            Case("stdin-read-all", "import sys\nprint(repr(sys.stdin.read()))", "'Ada\\nLin\\n'\n", stdin = "Ada\nLin\n"),
            Case("stdin-readline-eof", "import sys\nprint(repr(sys.stdin.readline()), repr(sys.stdin.readline()), repr(sys.stdin.readline()))", "'Ada\\n' 'Lin' ''\n", stdin = "Ada\nLin"),
            Case("stdin-shared-cursor", "import sys\nprint(sys.stdin.read(2), input(), repr(sys.stdin.read()))", "Ad a 'Lin\\n'\n", stdin = "Ada\nLin\n"),
            Case("stdin-buffer-shared-cursor", "import sys\nprint(sys.stdin.buffer.read(1), sys.stdin.read(), sys.stdin.buffer.read())", "b'A' da b''\n", stdin = "Ada"),
            Case("stdin-readinto", "import sys\ndata = bytearray(5)\nprint(sys.stdin.buffer.readinto(data), list(data), repr(sys.stdin.buffer.read()))", "3 [65, 100, 97, 0, 0] b''\n", stdin = "Ada"),
            Case("stderr-stream", "import sys\nsys.stdout.write('out\\n')\nsys.stderr.write('err\\n')\nsys.stdout.flush()\nsys.stderr.flush()", "out\n", error = "err\n"),
            Case("binary-stdio", "import sys\nsys.stdout.buffer.write(b'out\\n')\nsys.stderr.buffer.write(b'err\\n')\nsys.stdout.buffer.flush()\nsys.stderr.buffer.flush()", "out\n", error = "err\n"),
            Case("stdout-read-error", "import sys\nsys.stdout.read(1)", exitCode = 1, error = "EPERM"),
            Case("exit-code", "import sys\nsys.exit(7)", exitCode = 7),
            Case("exit-text", "import sys\nsys.exit('bye')", exitCode = 1, error = "bye"),
            Case("exit-overflow", "import sys\nsys.exit(1 << 200)", exitCode = 1, error = "OverflowError"),
            Case("upstream-module", "import math\nprint(math.sqrt(81))", "9.0\n"),
            Case("android-platform", "import sys\nprint(sys.platform)", "android\n"),
            Case(
                "project-paths",
                "import sys\nprint(sys.path[0], sys.path[1], sys.argv[0], __file__)",
                "${src.absolutePath} ${root.absolutePath} $entry $entry\n",
            ),
            Case("sibling-import", "import helper\nprint(helper.answer)", "42\n"),
            Case(
                "fresh-import", "import helper\nprint(helper.answer)", "99\n",
                prepare = { helper.writeText("answer = 99\n") },
            ),
            Case("package-import", "from samplepkg import answer\nprint(answer)", "84\n"),
            Case(
                "text-file",
                "with open('notes.txt', 'w') as f:\n    f.write('hello')\nwith open('notes.txt') as f:\n    print(f.read())",
                "hello\n", verify = { File(root, "notes.txt").readText() == "hello" },
            ),
            Case(
                "append-file",
                "import io\nwith io.open('notes.txt', mode='a') as f:\n    f.write('!')\nwith open('notes.txt') as f:\n    print(f.read())",
                "hello!\n", verify = { File(root, "notes.txt").readText() == "hello!" },
            ),
            Case(
                "binary-file",
                "with open('raw.bin', 'wb') as f:\n    f.write(bytes([0, 255]))\nwith open('raw.bin', 'rb') as f:\n    print(list(f.read()))",
                "[0, 255]\n", verify = { File(root, "raw.bin").readBytes().contentEquals(byteArrayOf(0, -1)) },
            ),
            Case("missing-file", "open('absent.txt')", exitCode = 1, error = "ENOENT"),
            Case("outside-project", "open('../outside.txt', 'w')", exitCode = 1, error = "EACCES"),
            Case(
                "compile-only", "print('must not run')\nopen('must-not-exist.txt', 'w')",
                compileOnly = true, verify = { !File(root, "must-not-exist.txt").exists() },
            ),
            Case("compile-only-import", "import absent_module", compileOnly = true),
            Case("compile-error", "def broken(:", exitCode = 1, error = "SyntaxError", compileOnly = true),
            Case("unicode-source-input-output", "print('$nonBmp')\nprint(input())", "$nonBmp\n$nonBmp\n", stdin = "$nonBmp\n"),
            Case("unicode-error", "raise ValueError('$nonBmp')", exitCode = 1, error = "ValueError: $nonBmp"),
            Case("unicode-entry-path", "print(__file__)", "$unicodeEntry\n", entryFile = unicodeEntry),
            Case(
                "gc-roots", "import gc\nvalues = [str(i) for i in range(50000)]\ngc.collect()\nprint(len(values), values[43210])",
                "50000 43210\n",
            ),
        )
        var passed = 0
        for (test in cases) {
            test.prepare?.invoke()
            val actual = QfliPyNative.run(
                source = test.source,
                stdin = test.stdin,
                projectPath = root.absolutePath,
                entryFile = test.entryFile ?: entry,
                compileOnly = test.compileOnly,
            )
            val errorOk = test.error?.let { actual.error?.contains(it) == true } ?: (actual.error == null)
            if (actual.exitCode == test.exitCode && actual.output == test.output &&
                errorOk && !actual.truncated && (test.verify?.invoke() ?: true)
            ) {
                passed++
                Log.i(TAG, "PASS ${test.name}")
            } else {
                Log.e(TAG, "FAIL ${test.name}: exit=${actual.exitCode}, output=${actual.output}, error=${actual.error}")
            }
        }
        Log.i(TAG, "Native self-check passed $passed/${cases.size}")
    }
}
