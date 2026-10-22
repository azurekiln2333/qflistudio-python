import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_python/python_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('qfli_py/native');
  const channelRunner = PythonProgramRunner(
    transport: PythonNativeTransport.methodChannel,
  );
  late Directory project;

  setUp(() {
    project = Directory.systemTemp.createTempSync('python_source_check_');
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    project.deleteSync(recursive: true);
  });

  test(
    'checks the exact unsaved buffer without creating the entry file',
    () async {
      final entry = p.join(project.path, 'new.py');
      const source = '# 😀\r\nprint("unsaved")\r\n';
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            methods.add(call.method);
            if (call.method == 'available') {
              return {'available': true, 'version': 'actual-test-backend'};
            }
            expect(call.method, 'checkSyntax');
            expect(call.arguments, {
              'source': source,
              'stdin': '',
              'heapKb': PythonProgramRunner.defaultHeapKb,
              'projectPath': project.path,
              'entryFile': entry,
            });
            return {'exitCode': 0, 'output': '', 'error': null};
          });

      final result = await channelRunner.checkSource(
        projectPath: project.path,
        entryFile: entry,
        source: source,
      );

      expect(result.success, isTrue);
      expect(result.version, 'actual-test-backend');
      expect(methods, ['available', 'checkSyntax']);
      expect(project.listSync(), isEmpty);
    },
  );

  test('saved syntax checking delegates the actual disk contents', () async {
    final entry = File(p.join(project.path, 'main.py'))
      ..writeAsStringSync('print("saved")\n');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'available') return {'available': true};
          expect((call.arguments as Map)['source'], entry.readAsStringSync());
          return {'exitCode': 0, 'error': ''};
        });
    expect(
      (await channelRunner.checkSyntax(
        projectPath: project.path,
        entryFile: entry.path,
      )).success,
      isTrue,
    );
  });

  test('refuses foreign paths and bytecode before invoking the VM', () async {
    var called = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          called = true;
          return {'available': true};
        });
    for (final path in [
      p.join(p.dirname(project.path), 'foreign.py'),
      p.join(project.path, 'main.mpy'),
    ]) {
      final result = await channelRunner.checkSource(
        projectPath: project.path,
        entryFile: path,
        source: 'print(1)',
      );
      expect(result.success, isFalse);
      expect(result.error, isNotEmpty);
    }
    expect(called, isFalse);
  });

  test('an invalid backend response cannot report clean syntax', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return call.method == 'available'
              ? {'available': true}
              : {'error': ''};
        });
    final result = await channelRunner.checkSource(
      projectPath: project.path,
      entryFile: p.join(project.path, 'main.py'),
      source: 'print(1)',
    );
    expect(result.success, isFalse);
    expect(result.error, isNotEmpty);
  });

  final library = p.absolute('native/build/windows/qfli_py_ffi.dll');
  final nativeAvailable = Platform.isWindows && File(library).existsSync();
  test(
    'real compiler checks unsaved source without running any side effect',
    () async {
      final entry = File(p.join(project.path, 'main.py'))
        ..writeAsStringSync('saved sentinel\n');
      final runner = PythonProgramRunner(
        transport: PythonNativeTransport.ffi,
        libraryPath: library,
      );
      final result = await runner.checkSource(
        projectPath: project.path,
        entryFile: entry.path,
        source:
            'open("side_effect.txt", "w").write("bad")\n'
            'print(input())\nimport module_that_does_not_exist\n',
      );
      expect(result.success, isTrue);
      expect(entry.readAsStringSync(), 'saved sentinel\n');
      expect(
        File(p.join(project.path, 'side_effect.txt')).existsSync(),
        isFalse,
      );
      expect(Directory(p.join(project.path, '.qfli')).existsSync(), isFalse);
    },
    skip: !nativeAvailable,
  );

  test(
    'real compiler diagnoses unsaved failure and recovers for valid text',
    () async {
      final runner = PythonProgramRunner(
        transport: PythonNativeTransport.ffi,
        libraryPath: library,
      );
      final entry = p.join(project.path, 'unsaved.py');
      final invalid = await runner.checkSource(
        projectPath: project.path,
        entryFile: entry,
        source: '# 😀\r\nif True\r\n    print(1)\r\n',
      );
      expect(invalid.success, isFalse);
      expect(invalid.error, contains('SyntaxError'));
      expect(invalid.error, contains('line 2'));
      expect(
        (await runner.checkSource(
          projectPath: project.path,
          entryFile: entry,
          source: 'print(42)\n',
        )).success,
        isTrue,
      );
      expect(File(entry).existsSync(), isFalse);
    },
    skip: !nativeAvailable,
  );
}
