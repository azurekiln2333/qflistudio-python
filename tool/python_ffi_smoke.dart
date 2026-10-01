import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:qfli_python/python_ffi.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length > 1) {
    throw ArgumentError('Usage: dart run tool/python_ffi_smoke.dart [library]');
  }
  final backend = PythonFfiBackend(
    libraryPath: arguments.isEmpty ? null : p.absolute(arguments.single),
  );
  final probe = await backend.probe();
  if (probe['available'] != true) throw StateError('${probe['detail']}');
  stdout.writeln('MicroPython ${probe['version']}');
  final project = Directory.systemTemp.createTempSync(
    'qfli_py_ffi_\u4e2d\u6587_',
  );
  final outside = Directory('${project.path}_outside')..createSync();
  final entry = p.join(project.path, 'src', 'main_\u4e2d\u6587.py');
  Directory(p.dirname(entry)).createSync(recursive: true);
  var passed = 0;

  Future<Map<String, Object?>> run(
    String source, {
    String stdin = '',
    bool compileOnly = false,
    String? projectRoot,
    String? entryPath,
  }) => backend.run(
    source: source,
    stdin: stdin,
    heapKb: 8192,
    projectPath: projectRoot ?? project.path,
    entryFile: entryPath ?? entry,
    compileOnly: compileOnly,
  );

  void check(
    String name,
    Map<String, Object?> result, {
    int exitCode = 0,
    String? output,
    String? errorContains,
    bool truncated = false,
  }) {
    if (result['exitCode'] != exitCode ||
        (output != null && result['output'] != output) ||
        (errorContains == null
            ? result['error'] != null
            : !(result['error'] is String &&
                  (result['error'] as String).contains(errorContains))) ||
        result['truncated'] != truncated) {
      throw StateError('$name: $result');
    }
    passed++;
    stdout.writeln('PASS $name');
  }

  try {
    check('execution', await run('print(42)'), output: '42\n');
    check('script expressions are silent', await run('42'), output: '');
    check(
      'UTF-8 source and output',
      await run('print("\u4f60\u597d")'),
      output: '\u4f60\u597d\n',
    );
    check(
      'finite standard input',
      await run('import sys\nprint(repr(sys.stdin.read()))'),
      output: "''\n",
    );
    check(
      'input buffer',
      await run(
        'import sys\nprint(input())\nprint(repr(sys.stdin.read()))',
        stdin: 'Ada\ntail',
      ),
      output: 'Ada\n\'tail\'\n',
    );
    check(
      'stdin EOF',
      await run('input()'),
      exitCode: 1,
      errorContains: 'EOFError',
    );
    check(
      'stderr routing',
      await run('import sys\nprint("out")\nsys.stderr.write("err")'),
      output: 'out\n',
      errorContains: 'err',
    );

    const module = 'helper_\u4e2d\u6587';
    final helper = File(p.join(project.path, 'src', '$module.py'))
      ..writeAsStringSync('value = 7\n');
    check(
      'imports and project file IO through a Unicode root',
      await run(
        'helper = __import__(${jsonEncode(module)})\n'
        'with open("ffi-result.txt", "w") as f:\n'
        '    f.write(str(helper.value))\n'
        'with open("ffi-result.txt") as f:\n'
        '    print(f.read())\n',
      ),
      output: '7\n',
    );
    if (File(p.join(project.path, 'ffi-result.txt')).readAsStringSync() !=
        '7') {
      throw StateError('Native project file was not written correctly.');
    }
    helper.writeAsStringSync('value = 8\n');
    check(
      'module state resets',
      await run(
        'helper = __import__(${jsonEncode(module)})\nprint(helper.value)',
      ),
      output: '8\n',
    );
    const unicodeFile = 'ffi_\u6570\u636e.txt';
    check(
      'UTF-8 text filenames and explicit text mode',
      await run(
        'with open(${jsonEncode(unicodeFile)}, "wt") as f:\n'
        '    f.write("\u4f60\u597d")\n'
        'with open(${jsonEncode(unicodeFile)}, "rt") as f:\n'
        '    print(f.read())\n',
      ),
      output: '\u4f60\u597d\n',
    );
    if (File(p.join(project.path, unicodeFile)).readAsStringSync() !=
        '\u4f60\u597d') {
      throw StateError('Native UTF-8 text file was not written correctly.');
    }
    check(
      'binary file modes',
      await run(
        'with open("ffi-binary.dat", "wb") as f:\n'
        '    f.write(b"\\x00\\xffA\\n")\n'
        'with open("ffi-binary.dat", "rb") as f:\n'
        '    data = f.read()\n'
        '    print(len(data), data[0], data[1], data[2], data[3])\n',
      ),
      output: '4 0 255 65 10\n',
    );
    final bytes = File(
      p.join(project.path, 'ffi-binary.dat'),
    ).readAsBytesSync();
    if (bytes.length != 4 ||
        bytes[0] != 0 ||
        bytes[1] != 255 ||
        bytes[2] != 65 ||
        bytes[3] != 10) {
      throw StateError('Native binary file was not written correctly.');
    }
    check(
      'parent directory escape is rejected',
      await run('open("../qfli-ffi-escape.txt", "w")'),
      exitCode: 1,
      errorContains: 'Errno 13',
    );
    final outsideFile = p.join(outside.path, 'escape.txt');
    check(
      'sibling path prefix is rejected',
      await run('open(${jsonEncode(outsideFile)}, "w")'),
      exitCode: 1,
      errorContains: 'Errno 13',
    );
    if (File(outsideFile).existsSync()) {
      throw StateError('Native open escaped the project directory.');
    }
    if (Platform.isWindows) {
      final mixedRoot = project.path.toUpperCase().replaceAll('\\', '/');
      final mixedEntry = '$mixedRoot\\src/${p.basename(entry).toUpperCase()}';
      check(
        'case-insensitive root with mixed path separators',
        await run(
          'print(open(${jsonEncode(unicodeFile)}).read())',
          projectRoot: mixedRoot,
          entryPath: mixedEntry,
        ),
        output: '\u4f60\u597d\n',
      );
      check(
        'backslash parent escape is rejected',
        await run('open("..\\\\qfli-ffi-escape.txt", "w")'),
        exitCode: 1,
        errorContains: 'Errno 13',
      );
    }
    check(
      'compile only',
      await run(
        'open("syntax-only.txt", "w").write("unexpected")',
        compileOnly: true,
      ),
      output: '',
    );
    if (File(p.join(project.path, 'syntax-only.txt')).existsSync()) {
      throw StateError('Compile-only mode executed Python code.');
    }
    check(
      'syntax errors',
      await run('def broken(:', compileOnly: true),
      exitCode: 1,
      errorContains: 'SyntaxError',
    );
    check(
      'runtime errors',
      await run('missing_name'),
      exitCode: 1,
      errorContains: 'NameError',
    );
    final traceback = await run('missing_name');
    if (!(traceback['error'] as String).contains(p.basename(entry))) {
      throw StateError('Native traceback lost the Unicode entry filename.');
    }
    passed++;
    stdout.writeln('PASS Unicode entry traceback');
    check(
      'explicit exit',
      await run('import sys\nsys.exit(3)'),
      exitCode: 3,
      output: '',
    );
    check(
      'exit integer overflow',
      await run('import sys\nsys.exit(1 << 100)'),
      exitCode: 1,
      errorContains: 'OverflowError',
    );
    check('recovery after error', await run('print(42)'), output: '42\n');
    check('globals setup', await run('shared_value = 42'), output: '');
    check(
      'globals reset',
      await run('print("shared_value" in globals())'),
      output: 'False\n',
    );
    check(
      'truncated output',
      await run('print("x" * 300000)'),
      truncated: true,
    );
    check(
      'truncated UTF-8 output decodes',
      await run('print("x" + "\u4e2d" * 100000)'),
      truncated: true,
    );
    final concurrent = await Future.wait([
      for (var index = 0; index < 8; index++) run('print($index)'),
    ]);
    for (var index = 0; index < concurrent.length; index++) {
      check('concurrent call $index', concurrent[index], output: '$index\n');
    }
    stdout.writeln('PASS $passed/$passed real native FFI cases');
  } finally {
    project.deleteSync(recursive: true);
    outside.deleteSync(recursive: true);
  }
}
