import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_python/python_ffi.dart';
import 'package:qfli_python/python_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory project;
  late String missingLibrary;

  setUp(() {
    project = Directory.systemTemp.createTempSync('qfli_py_ffi_test');
    missingLibrary = p.join(project.path, 'missing_micro_python_library');
  });

  tearDown(() => project.deleteSync(recursive: true));

  test('FFI probe retains the loader failure', () async {
    final probe = await PythonFfiBackend(libraryPath: missingLibrary).probe();
    expect(probe['available'], isFalse);
    expect(probe['version'], isEmpty);
    expect(probe['detail'], contains(missingLibrary));
  });

  test('FFI run reports a missing library as a native failure', () async {
    await expectLater(
      PythonFfiBackend(libraryPath: missingLibrary).run(
        source: 'print(42)',
        stdin: '',
        heapKb: 8192,
        projectPath: project.path,
        entryFile: p.join(project.path, 'main.py'),
      ),
      throwsA(
        isA<PythonFfiException>()
            .having((error) => error.code, 'code', 'QFLI_PY_MODULE_MISSING')
            .having(
              (error) => error.message,
              'message',
              contains(missingLibrary),
            ),
      ),
    );
  });

  for (final field in ['source', 'stdin', 'projectPath', 'entryFile']) {
    test('FFI rejects embedded NUL in $field before loading', () {
      final arguments = {
        'source': 'print(42)',
        'stdin': '',
        'projectPath': project.path,
        'entryFile': p.join(project.path, 'main.py'),
      };
      arguments[field] = '${arguments[field]}\u0000ignored';
      expect(
        () => PythonFfiBackend(libraryPath: missingLibrary).run(
          source: arguments['source']!,
          stdin: arguments['stdin']!,
          heapKb: 8192,
          projectPath: arguments['projectPath']!,
          entryFile: arguments['entryFile']!,
        ),
        throwsA(
          isA<PythonFfiException>()
              .having((error) => error.code, 'code', 'INVALID_ARGUMENT')
              .having((error) => error.message, 'message', contains(field)),
        ),
      );
    });
  }

  test('FFI rejects integer overflow before marshalling', () {
    expect(
      () => PythonFfiBackend(libraryPath: missingLibrary).run(
        source: 'print(42)',
        stdin: '',
        heapKb: 0x100000000,
        projectPath: project.path,
        entryFile: p.join(project.path, 'main.py'),
      ),
      throwsA(isA<PythonFfiException>()),
    );
  });

  test('runner retains the FFI failure and not-run exit status', () async {
    final entry = File(p.join(project.path, 'main.py'))
      ..writeAsStringSync('print(42)');
    final runner = PythonProgramRunner(
      transport: PythonNativeTransport.ffi,
      libraryPath: missingLibrary,
    );
    final result = await runner.run(
      projectPath: project.path,
      entryFile: entry.path,
    );
    expect(result, isNotNull);
    expect(await result!.exitCode, PythonProgramRunner.notRunExitCode);
    expect(await result.stdout.toList(), [contains(missingLibrary)]);
    final syntax = await runner.checkSyntax(
      projectPath: project.path,
      entryFile: entry.path,
    );
    expect(syntax.success, isFalse);
    expect(syntax.error, contains(missingLibrary));
  });

  if (Platform.isWindows ||
      Platform.isLinux ||
      Platform.isIOS ||
      Platform.isMacOS) {
    test('desktop and Apple default transport selects FFI', () async {
      const channel = MethodChannel('qfli_py/native');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            fail(
              'The default desktop transport must not use a platform channel.',
            );
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final entry = File(p.join(project.path, 'main.py'))
        ..writeAsStringSync('print(42)');
      final result = await PythonProgramRunner(
        libraryPath: missingLibrary,
      ).run(projectPath: project.path, entryFile: entry.path);
      expect(await result!.exitCode, PythonProgramRunner.notRunExitCode);
      expect(await result.stdout.toList(), [contains(missingLibrary)]);
    });
  }

  if (Platform.isWindows || Platform.isLinux) {
    final nativeLibrary = File(
      p.join(
        Directory.current.path,
        'native',
        'build',
        Platform.operatingSystem,
        Platform.isWindows ? 'qfli_py_ffi.dll' : 'libqfli_py_ffi.so',
      ),
    );
    test(
      'default runner compiles and runs a real multi-file native project',
      () async {
        final source = Directory(p.join(project.path, 'src'))..createSync();
        File(p.join(source.path, 'helper.py')).writeAsStringSync('value = 7');
        File(p.join(project.path, 'input.txt')).writeAsStringSync('Ada\n');
        final entry = File(p.join(source.path, 'main.py'))
          ..writeAsStringSync(
            'import helper, sys\n'
            'with open("runner-result.txt", "w") as output:\n'
            '    output.write(input() + "-" + str(helper.value))\n'
            'print(open("runner-result.txt").read())\n'
            'sys.stderr.write("runner-ok")\n',
          );
        const runner = PythonProgramRunner();
        final syntax = await runner.checkSyntax(
          projectPath: project.path,
          entryFile: entry.path,
        );
        expect(syntax.success, isTrue, reason: syntax.error);
        final artifact = File(p.join(project.path, 'runner-result.txt'));
        expect(artifact.existsSync(), isFalse);
        final result = await runner.run(
          projectPath: project.path,
          entryFile: entry.path,
        );
        expect(await result!.stdout.toList(), ['Ada-7']);
        expect(await result.stderr.toList(), ['runner-ok']);
        expect(await result.exitCode, 0);
        expect(artifact.readAsStringSync(), 'Ada-7');
      },
      skip: nativeLibrary.existsSync() ? false : 'Build the native C library first.',
    );
  }
}
