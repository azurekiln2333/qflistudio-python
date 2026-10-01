import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_python/python_ffi.dart';
import 'package:qfli_python/python_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('qfli_py/native');
  late Directory project;
  late String entry;
  setUp(() {
    project = Directory.systemTemp.createTempSync('qfli_python_lifecycle');
    entry = p.join(project.path, 'main.py');
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    project.deleteSync(recursive: true);
  });

  test(
    'channel returns a handle while run is pending and routes stop by id',
    () async {
      File(entry).writeAsStringSync('while True: pass');
      final pending = Completer<Object?>();
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            switch (call.method) {
              case 'available':
                return {'available': true, 'runControl': true};
              case 'prepareRun':
                return 'unique-run';
              case 'run':
                return pending.future;
              case 'cancel':
                expect((call.arguments as Map)['runId'], 'unique-run');
                pending.complete({
                  'exitCode': 130,
                  'output': 'before\n',
                  'error': 'KeyboardInterrupt\n',
                });
                return true;
            }
            return null;
          });
      const runner = PythonProgramRunner(
        transport: PythonNativeTransport.methodChannel,
      );
      final result = await runner
          .run(projectPath: project.path, entryFile: entry)
          .timeout(const Duration(seconds: 2));
      expect(pending.isCompleted, isFalse);
      await result!.cancel!();
      expect(await result.stdout.toList(), ['before']);
      expect(await result.stderr.toList(), ['KeyboardInterrupt']);
      expect(await result.exitCode, 130);
      await result.cancel!();
      expect(calls.where((call) => call.method == 'cancel').length, 1);
      expect(
        (calls.firstWhere((call) => call.method == 'run').arguments
            as Map)['runId'],
        'unique-run',
      );
    },
  );

  test(
    'pending native failure closes both streams and retains not-run status',
    () async {
      File(entry).writeAsStringSync('print(1)');
      final pending = Completer<Object?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'available') {
              return {'available': true, 'runControl': true};
            }
            if (call.method == 'prepareRun') return 'failure-run';
            return pending.future;
          });
      const runner = PythonProgramRunner(
        transport: PythonNativeTransport.methodChannel,
      );
      final result = await runner.run(
        projectPath: project.path,
        entryFile: entry,
      );
      pending.completeError(
        PlatformException(code: 'NATIVE_FAILURE', message: 'native detail'),
      );
      expect(await result!.stdout.toList(), isEmpty);
      expect(await result.stderr.toList(), [contains('native detail')]);
      expect(await result.exitCode, PythonProgramRunner.notRunExitCode);
    },
  );

  if (!Platform.isWindows && !Platform.isLinux) return;
  final library = p.join(
    Directory.current.path,
    'native',
    'build',
    Platform.operatingSystem,
    Platform.isWindows ? 'qfli_py_ffi.dll' : 'libqfli_py_ffi.so',
  );
  group(
    'real MicroPython lifecycle',
    () {
      late PythonFfiBackend backend;
      setUp(() => backend = PythonFfiBackend(libraryPath: library));

      PythonFfiExecution start(String source, {String bytecode = ''}) =>
          backend.start(
            source: source,
            stdin: '',
            heapKb: 8192,
            projectPath: project.path,
            entryFile: entry,
            bytecodeFile: bytecode,
          );

      Future<void> waitForFile(String name) async {
        final file = File(p.join(project.path, name));
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (!file.existsSync()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Native worker did not create $name');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      for (final code in ['while True: pass', 'import time\ntime.sleep(60)']) {
        test('stop executing $code and preserve prior output', () async {
          final execution = start(
            "print('before')\nopen('started', 'w').close()\n$code",
          );
          try {
            await waitForFile('started');
          } finally {
            await execution.cancel();
          }
          await execution.cancel();
          final result = await execution.result.timeout(
            const Duration(seconds: 3),
          );
          expect(result['exitCode'], 130);
          expect(result['output'], 'before\n');
          expect(result['error'], contains('KeyboardInterrupt'));
          await execution.cancel();
          final next = await start('print(42)').result;
          expect(next['exitCode'], 0);
          expect(next['output'], '42\n');
        });
      }

      test('pre-start cancellation prevents source side effects', () async {
        final execution = start("open('must-not-exist', 'w').close()");
        await execution.cancel();
        expect((await execution.result)['exitCode'], 130);
        expect(
          File(p.join(project.path, 'must-not-exist')).existsSync(),
          isFalse,
        );
      });

      test('queued cancellation cannot stop another run', () async {
        final first = start(
          "open('first-started', 'w').close()\nwhile True: pass",
        );
        PythonFfiExecution? second;
        try {
          await waitForFile('first-started');
          second = start("open('must-not-exist', 'w').close()");
          await second.cancel();
          var completed = false;
          unawaited(first.result.then((_) => completed = true));
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(completed, isFalse);
        } finally {
          await first.cancel();
        }
        expect((await first.result)['exitCode'], 130);
        expect((await second.result)['exitCode'], 130);
        expect(
          File(p.join(project.path, 'must-not-exist')).existsSync(),
          isFalse,
        );
      });

      test('runner exposes real stop before native completion', () async {
        File(entry).writeAsStringSync("print('before')\nwhile True: pass");
        final runner = PythonProgramRunner(libraryPath: library);
        final result = await runner
            .run(projectPath: project.path, entryFile: entry)
            .timeout(const Duration(seconds: 3));
        expect(result!.cancel, isNotNull);
        await result.cancel!();
        expect(await result.exitCode.timeout(const Duration(seconds: 3)), 130);
        await result.stdout.drain<void>();
        expect(await result.stderr.toList(), [contains('KeyboardInterrupt')]);
      });

      test(
        'upstream artifacts run after deleting entry and imported source',
        () async {
          final helper = File(p.join(project.path, 'helper.py'))
            ..writeAsStringSync('value = 7');
          File(entry).writeAsStringSync(
            'import helper, sys\n'
            'def twice(value):\n    return value * 2\n'
            'with open("result.txt", "w") as f:\n    f.write(input())\n'
            'print(twice(helper.value), open("result.txt").read())\n'
            'print(__file__, sys.argv[0])\n',
          );
          File(
            p.join(project.path, 'input.txt'),
          ).writeAsStringSync('\u4F60\u597D\u{1F680}\n');
          final runner = PythonProgramRunner(libraryPath: library);
          final helperCompilation = await runner.compile(
            projectPath: project.path,
            entryFile: helper.path,
          );
          expect(
            helperCompilation.success,
            isTrue,
            reason: helperCompilation.error,
          );
          final compilation = await runner.compile(
            projectPath: project.path,
            entryFile: entry,
          );
          expect(compilation.success, isTrue, reason: compilation.error);
          final artifact = File(compilation.artifactPath);
          expect(artifact.readAsBytesSync().take(3), [77, 6, 0]);
          expect(
            File(p.join(project.path, 'result.txt')).existsSync(),
            isFalse,
          );
          helper.deleteSync();
          File(entry).deleteSync();
          final result = await runner.run(
            projectPath: project.path,
            entryFile: artifact.path,
          );
          expect(await result!.stdout.toList(), [
            '14 \u4F60\u597D\u{1F680}',
            '${artifact.path} ${artifact.path}',
          ]);
          expect(await result.stderr.toList(), isEmpty);
          expect(await result.exitCode, 0);
        },
      );

      test('failed compilation retains previous artifact', () async {
        final source = File(entry)..writeAsStringSync('print(42)');
        final runner = PythonProgramRunner(libraryPath: library);
        final good = await runner.compile(
          projectPath: project.path,
          entryFile: entry,
        );
        expect(good.success, isTrue, reason: good.error);
        final artifact = File(good.artifactPath);
        final before = artifact.readAsBytesSync();
        source.writeAsStringSync('def broken(:');
        final bad = await runner.compile(
          projectPath: project.path,
          entryFile: entry,
        );
        expect(bad.success, isFalse);
        expect(bad.error, contains('SyntaxError'));
        expect(bad.artifactPath, isEmpty);
        expect(artifact.readAsBytesSync(), before);
      });

      test('invalid bytecode fails then a fresh source run succeeds', () async {
        final artifact = File(p.join(project.path, 'bad.mpy'))
          ..writeAsBytesSync([77, 5, 0, 31]);
        final result = await start('', bytecode: artifact.path).result;
        expect(result['exitCode'], 1);
        expect(result['error'], contains('incompatible .mpy file'));
        expect((await start('print(42)').result)['output'], '42\n');
      });

      test('artifact writing obeys project boundaries', () async {
        final outside = '${project.path}-outside.mpy';
        final result = await backend.run(
          source: 'print(42)',
          stdin: '',
          heapKb: 8192,
          projectPath: project.path,
          entryFile: entry,
          compileOnly: true,
          artifactOutput: outside,
        );
        expect(result['exitCode'], 1);
        expect(result['error'], contains('EACCES'));
        expect(File(outside).existsSync(), isFalse);
      });
    },
    skip: File(library).existsSync() ? false : 'Native library is unavailable.',
  );
}
