import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_python/python_code_analyzer.dart';
import 'package:qfli_python/python_runner.dart';
import 'package:qfli_studio_core/services/code_analysis.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('qfli_py/native');
  const analyzer = PythonCodeAnalyzer(
    runner: PythonProgramRunner(transport: PythonNativeTransport.methodChannel),
  );
  late Directory project;
  late String entry;

  setUp(() {
    project = Directory.systemTemp.createTempSync('python_analyzer_课程_');
    entry = p.join(project.path, '未保存 "file".py');
    // Windows filenames cannot contain quotes; the parser's quoted-path case
    // is exercised with a POSIX-valid filename on other hosts.
    if (Platform.isWindows) entry = p.join(project.path, '未保存 file.py');
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    project.deleteSync(recursive: true);
  });

  CodeAnalysisRequest request(
    String text, {
    String? path,
    String language = 'Python',
    int revision = 7,
    int snapshotRevision = 7,
    List<CodeDocumentSnapshot> otherDocuments = const [],
  }) => CodeAnalysisRequest(
    projectPath: project.path,
    activeFilePath: path ?? entry,
    language: language,
    revision: revision,
    documents: [
      CodeDocumentSnapshot(
        path: path ?? entry,
        text: text,
        revision: snapshotRevision,
      ),
      ...otherDocuments,
    ],
  );

  void installResult(Object? result) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'available') {
            return {'available': true, 'version': 'test-native'};
          }
          return result;
        });
  }

  Map<String, Object?> syntaxError({
    String? file,
    int line = 2,
    String exception = 'SyntaxError: invalid syntax',
  }) => {
    'exitCode': 1,
    'output': '',
    'error':
        'Traceback (most recent call last):\n'
        '  File "${file ?? entry}", line $line\n$exception\n',
  };

  test(
    'checks all captured Python buffers active first without disk reads',
    () async {
      File(entry).writeAsStringSync('saved invalid : sentinel');
      final other = p.join(project.path, 'helper.py');
      final seen = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'available') return {'available': true};
            expect(call.method, 'checkSyntax');
            final arguments = call.arguments as Map;
            final path = arguments['entryFile'] as String;
            seen.add(path);
            expect(
              arguments['source'],
              path == entry ? 'print(42)\r\n' : '# 😀\r',
            );
            return {'exitCode': 0, 'error': ''};
          });
      final result = await analyzer.analyze(
        request(
          'print(42)\r\n',
          otherDocuments: [
            CodeDocumentSnapshot(path: other, text: '# 😀\r', revision: 2),
            CodeDocumentSnapshot(
              path: p.join(project.path, 'README.md'),
              text: 'Not Python',
              revision: 9,
            ),
          ],
        ),
      );
      expect(result.unavailableReason, isNull);
      expect(result.diagnostics, isEmpty);
      expect(seen, [entry, other]);
      expect(File(entry).readAsStringSync(), 'saved invalid : sentinel');
      expect(File(other).existsSync(), isFalse);
    },
  );

  for (final newline in ['\n', '\r\n', '\r']) {
    test('native line uses UTF-16 offsets with ${newline.codeUnits}', () async {
      final prefix = '# 😀 中文$newline';
      final text = '${prefix}if True$newline    print(1)$newline';
      installResult(syntaxError());
      final result = await analyzer.analyze(request(text));
      expect(result.unavailableReason, isNull);
      final diagnostic = result.diagnostics.single;
      expect(diagnostic.filePath, entry);
      expect(diagnostic.startOffset, prefix.length);
      expect(diagnostic.endOffset, prefix.length + 'if True'.length);
      expect(
        text.substring(diagnostic.startOffset, diagnostic.endOffset),
        'if True',
      );
      expect(diagnostic.source, 'MicroPython');
      expect(diagnostic.code, 'SyntaxError');
    });
  }

  test('reports indentation errors and empty EOF insertion ranges', () async {
    const text = '# 😀\r\n';
    installResult(
      syntaxError(exception: 'IndentationError: expected an indented block'),
    );
    final result = await analyzer.analyze(request(text));
    final diagnostic = result.diagnostics.single;
    expect(diagnostic.startOffset, text.length);
    expect(diagnostic.endOffset, text.length);
    expect(diagnostic.code, 'IndentationError');
  });

  test('retains diagnostics from another unsaved Python buffer', () async {
    final other = p.join(project.path, 'helper.py');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'available') return {'available': true};
          return (call.arguments as Map)['entryFile'] == entry
              ? {'exitCode': 0}
              : syntaxError(file: other, line: 1);
        });
    final result = await analyzer.analyze(
      request(
        'print(1)',
        otherDocuments: [
          CodeDocumentSnapshot(path: other, text: 'def broken(:', revision: 2),
        ],
      ),
    );
    expect(result.unavailableReason, isNull);
    expect(result.diagnostics.single.filePath, other);
    expect(result.diagnostics.single.endOffset, 'def broken(:'.length);
  });

  test(
    'rejects obsolete, foreign and non-Python requests before native work',
    () async {
      var called = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            called = true;
            return null;
          });
      final requests = [
        request('print(1)', snapshotRevision: 6),
        request('print(1)', language: 'Java'),
        request('print(1)', path: p.join(project.path, 'main.mpy')),
        request('print(1)', path: p.join(p.dirname(project.path), 'other.py')),
        request(
          'print(1)',
          otherDocuments: [
            CodeDocumentSnapshot(
              path: entry,
              text: 'different revision',
              revision: 5,
            ),
          ],
        ),
      ];
      for (final invalid in requests) {
        final result = await analyzer.analyze(invalid);
        expect(result.unavailableReason, isNotEmpty);
        expect(result.diagnostics, isEmpty);
      }
      expect(called, isFalse);
    },
  );

  for (final failure in [
    {'exitCode': 1, 'error': 'SyntaxError: no file/line'},
    {'exitCode': 1, 'error': 'MemoryError: out of memory'},
    {'exitCode': 130, 'error': 'KeyboardInterrupt'},
    {
      'exitCode': 130,
      'error': '  File "unresolved.py", line 1\nSyntaxError: interrupted check',
    },
    {'exitCode': 1, 'error': ''},
    {'exitCode': 0, 'error': 'operational warning'},
    {'exitCode': '0'},
    {
      'exitCode': 0,
      'error': {'malformed': true},
    },
    {'exitCode': 0, 'output': 'unexpected program execution'},
    {'exitCode': 0, 'truncated': true},
  ]) {
    test(
      'backend failure does not become clean diagnostics: $failure',
      () async {
        installResult(failure);
        final result = await analyzer.analyze(request('print(1)'));
        expect(result.unavailableReason, isNotEmpty);
        expect(result.diagnostics, isEmpty);
      },
    );
  }

  test(
    'foreign and impossible native locations have no fabricated range',
    () async {
      for (final result in [
        syntaxError(file: p.join(p.dirname(project.path), 'outside.py')),
        syntaxError(file: 'relative.py'),
        syntaxError(line: 0),
        syntaxError(line: 9999),
      ]) {
        installResult(result);
        final analysis = await analyzer.analyze(request('print(1)\n'));
        expect(analysis.unavailableReason, isNotEmpty);
        expect(analysis.diagnostics, isEmpty);
      }
    },
  );

  test('missing runtime is explicit and later availability recovers', () async {
    var available = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'available') {
            return {'available': available, 'detail': 'runtime missing'};
          }
          return {'exitCode': 0};
        });
    final missing = await analyzer.analyze(request('print(1)'));
    expect(missing.unavailableReason, 'runtime missing');
    available = true;
    expect(
      (await analyzer.analyze(request('print(1)'))).unavailableReason,
      isNull,
    );
  });

  final library = p.absolute('native/build/windows/qfli_py_ffi.dll');
  final nativeAvailable = Platform.isWindows && File(library).existsSync();
  test(
    'real compiler maps unsaved Unicode/CRLF syntax and has no side effects',
    () async {
      final real = PythonCodeAnalyzer(
        runner: PythonProgramRunner(
          transport: PythonNativeTransport.ffi,
          libraryPath: library,
        ),
      );
      final saved = File(entry)..writeAsStringSync('saved sentinel');
      const prefix = '# 😀 中文\r\n';
      final invalid = await real.analyze(
        request('${prefix}if True\r\n  pass\r\n'),
      );
      expect(invalid.unavailableReason, isNull);
      expect(invalid.diagnostics.single.startOffset, prefix.length);
      expect(
        invalid.diagnostics.single.endOffset,
        prefix.length + 'if True'.length,
      );
      final valid = await real.analyze(
        request(
          'open("side_effect.txt", "w").write("must not run")\r\n'
          'import absent_module\r\nprint(input())\r\n',
        ),
      );
      expect(valid.unavailableReason, isNull);
      expect(valid.diagnostics, isEmpty);
      expect(saved.readAsStringSync(), 'saved sentinel');
      expect(
        File(p.join(project.path, 'side_effect.txt')).existsSync(),
        isFalse,
      );
      expect(Directory(p.join(project.path, '.qfli')).existsSync(), isFalse);
    },
    skip: !nativeAvailable,
  );
}
