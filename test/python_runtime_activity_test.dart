import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_python/python_code_analyzer.dart';
import 'package:qfli_python/python_packages.dart';
import 'package:qfli_python/python_runner.dart';
import 'package:qfli_python/python_runtime_activity.dart';
import 'package:qfli_studio_core/services/code_analysis.dart';

class _PendingPreparation extends PythonPackageService {
  final entered = Completer<void>();
  final result = Completer<PythonBundlePreparationResult>();

  @override
  Future<PythonBundlePreparationResult> ensureBundledModules(
    String projectPath,
  ) {
    entered.complete();
    return result.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('qfli_py/native');
  late Directory project;
  late String entry;

  setUp(() {
    project = Directory.systemTemp.createTempSync('python_runtime_activity_');
    entry = p.join(project.path, 'main.py');
    File(entry).writeAsStringSync('print(42)');
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    project.deleteSync(recursive: true);
  });

  CodeAnalysisRequest request() => CodeAnalysisRequest(
    projectPath: project.path,
    activeFilePath: entry,
    language: 'Python',
    revision: 1,
    documents: [
      CodeDocumentSnapshot(path: entry, text: 'print(1)', revision: 1),
    ],
  );

  test('a stale released lease cannot release a newer owner', () {
    final activity = PythonRuntimeActivity();
    final first = activity.tryAcquire(PythonRuntimeOperation.run)!;
    expect(activity.tryAcquire(PythonRuntimeOperation.analysis), isNull);
    first.release();
    final second = activity.tryAcquire(PythonRuntimeOperation.debug)!;
    first.release();
    expect(activity.operation, PythonRuntimeOperation.debug);
    second.release();
    expect(activity.isBusy, isFalse);
  });

  test(
    'default runners stay busy through late native exit and stop request',
    () async {
      final pending = Completer<Object?>();
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return switch (call.method) {
              'available' => {'available': true, 'runControl': true},
              'prepareRun' => 'late-native-exit',
              'run' => await pending.future,
              'cancel' => true,
              'checkSyntax' => {'exitCode': 0},
              _ => throw StateError('Unexpected ${call.method}'),
            };
          });
      const first = PythonProgramRunner(
        transport: PythonNativeTransport.methodChannel,
      );
      const second = PythonProgramRunner(
        transport: PythonNativeTransport.methodChannel,
      );
      final result = (await first.run(
        projectPath: project.path,
        entryFile: entry,
      ))!;
      final output = result.stdout.toList();
      final errors = result.stderr.toList();
      try {
        expect(
          PythonRuntimeActivity.shared.operation,
          PythonRuntimeOperation.run,
        );
        final busyAnalysis = await const PythonCodeAnalyzer(
          runner: second,
        ).analyze(request()).timeout(const Duration(seconds: 1));
        expect(busyAnalysis.unavailableReason, contains('正在运行'));
        final compile = await second.compile(
          projectPath: project.path,
          entryFile: entry,
        );
        expect(compile.success, isFalse);
        expect(compile.error, contains('正在运行'));
        final busyRun = (await second.run(
          projectPath: project.path,
          entryFile: entry,
        ))!;
        expect(await busyRun.exitCode, PythonProgramRunner.notRunExitCode);
        await busyRun.stdout.drain<void>();
        expect(await busyRun.stderr.toList(), [contains('正在运行')]);
        expect(calls, ['available', 'prepareRun', 'run']);
        await result.cancel!();
        expect(PythonRuntimeActivity.shared.isBusy, isTrue);
        expect(
          (await second.checkSource(
            projectPath: project.path,
            entryFile: entry,
            source: 'print(1)',
          )).unavailableReason,
          contains('正在运行'),
        );
      } finally {
        pending.complete({'exitCode': 130, 'error': 'KeyboardInterrupt'});
        await result.exitCode;
      }
      expect(await output, isEmpty);
      expect(await errors, ['KeyboardInterrupt']);
      expect(PythonRuntimeActivity.shared.isBusy, isFalse);
      expect(
        (await second.checkSource(
          projectPath: project.path,
          entryFile: entry,
          source: 'print(1)',
        )).success,
        isTrue,
      );
      expect(calls, [
        'available',
        'prepareRun',
        'run',
        'cancel',
        'available',
        'checkSyntax',
      ]);
    },
  );

  test(
    'analysis claims busy state before its async capability probe',
    () async {
      final activity = PythonRuntimeActivity();
      final started = Completer<void>();
      final probe = Completer<Object?>();
      var checks = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'available') {
              started.complete();
              return probe.future;
            }
            checks++;
            return {'exitCode': 0};
          });
      final first = PythonProgramRunner(
        transport: PythonNativeTransport.methodChannel,
        runtimeActivity: activity,
      );
      final second = PythonProgramRunner(
        transport: PythonNativeTransport.methodChannel,
        runtimeActivity: activity,
      );
      final pending = first.checkSource(
        projectPath: project.path,
        entryFile: entry,
        source: 'print(1)',
      );
      await started.future;
      try {
        final rejected = await second.checkSource(
          projectPath: project.path,
          entryFile: entry,
          source: 'print("stale")',
        );
        expect(rejected.unavailableReason, contains('正在检查'));
        expect(checks, 0);
      } finally {
        probe.complete({'available': true});
        expect((await pending).success, isTrue);
      }
      expect(checks, 1);
      expect(activity.isBusy, isFalse);
    },
  );

  test(
    'run owns the VM before its delayed probe and releases unavailable state',
    () async {
      final activity = PythonRuntimeActivity();
      final entered = Completer<void>();
      final probe = Completer<Object?>();
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls++;
            expect(call.method, 'available');
            entered.complete();
            return probe.future;
          });
      final runner = PythonProgramRunner(
        transport: PythonNativeTransport.methodChannel,
        runtimeActivity: activity,
      );
      final pending = runner.run(projectPath: project.path, entryFile: entry);
      await entered.future;
      try {
        expect(activity.operation, PythonRuntimeOperation.run);
        expect(
          (await runner.checkSource(
            projectPath: project.path,
            entryFile: entry,
            source: 'print(1)',
          )).unavailableReason,
          contains('正在运行'),
        );
        expect(calls, 1);
      } finally {
        probe.complete({'available': false, 'detail': 'probe failure'});
      }
      final result = (await pending)!;
      expect(await result.exitCode, PythonProgramRunner.notRunExitCode);
      expect(await result.stdout.toList(), [contains('probe failure')]);
      await result.stderr.drain<void>();
      expect(activity.isBusy, isFalse);
    },
  );

  test('bundle preparation retains lease and failure releases it', () async {
    final activity = PythonRuntimeActivity();
    final packages = _PendingPreparation();
    var executions = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'available') return {'available': true};
          executions++;
          return {'exitCode': 0};
        });
    final runner = PythonProgramRunner(
      transport: PythonNativeTransport.methodChannel,
      packageService: packages,
      runtimeActivity: activity,
    );
    final pending = runner.run(projectPath: project.path, entryFile: entry);
    await packages.entered.future;
    try {
      expect(activity.operation, PythonRuntimeOperation.run);
      expect(
        (await runner.checkSource(
          projectPath: project.path,
          entryFile: entry,
          source: 'print(1)',
        )).unavailableReason,
        contains('正在运行'),
      );
      expect(executions, 0);
    } finally {
      packages.result.complete(
        const PythonBundlePreparationResult(
          success: false,
          message: 'Edited bundle conflict',
        ),
      );
    }
    final result = (await pending)!;
    expect(await result.exitCode, PythonProgramRunner.notRunExitCode);
    await result.stdout.drain<void>();
    expect(await result.stderr.toList(), [contains('Edited bundle conflict')]);
    expect(activity.isBusy, isFalse);
    expect(
      (await runner.checkSource(
        projectPath: project.path,
        entryFile: entry,
        source: 'print(1)',
      )).success,
      isTrue,
    );
  });

  for (final fails in [true, false]) {
    test(
      'late ${fails ? 'throw' : 'malformed result'} releases runtime',
      () async {
        final activity = PythonRuntimeActivity();
        final pending = Completer<Object?>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'available') {
                return {'available': true, 'runControl': true};
              }
              if (call.method == 'prepareRun') return 'late-failure';
              return pending.future;
            });
        final runner = PythonProgramRunner(
          transport: PythonNativeTransport.methodChannel,
          runtimeActivity: activity,
        );
        final result = (await runner.run(
          projectPath: project.path,
          entryFile: entry,
        ))!;
        final output = result.stdout.toList();
        final errors = result.stderr.toList();
        if (fails) {
          pending.completeError(PlatformException(code: 'NATIVE_FAILED'));
        } else {
          pending.complete({'exitCode': 'bad'});
        }
        expect(await result.exitCode, PythonProgramRunner.notRunExitCode);
        expect(await output, isEmpty);
        expect(await errors, isNotEmpty);
        expect(activity.isBusy, isFalse);
      },
    );
  }

  final library = p.absolute('native/build/windows/qfli_py_ffi.dll');
  final nativeAvailable = Platform.isWindows && File(library).existsSync();
  test(
    'real running VM rejects analysis promptly then recovers after cancellation',
    () async {
      File(entry).writeAsStringSync(
        'open("started.txt", "w").close()\nwhile True: pass\n',
      );
      final runner = PythonProgramRunner(
        transport: PythonNativeTransport.ffi,
        libraryPath: library,
      );
      final analyzer = PythonCodeAnalyzer(
        runner: PythonProgramRunner(
          transport: PythonNativeTransport.ffi,
          libraryPath: library,
        ),
      );
      final result = (await runner.run(
        projectPath: project.path,
        entryFile: entry,
      ))!;
      final output = result.stdout.toList();
      final errors = result.stderr.toList();
      try {
        final started = File(p.join(project.path, 'started.txt'));
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (!started.existsSync()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Actual native run did not start');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        final busy = await analyzer
            .analyze(request())
            .timeout(const Duration(seconds: 1));
        expect(busy.unavailableReason, contains('正在运行'));
        expect(busy.diagnostics, isEmpty);
      } finally {
        await result.cancel!();
        expect(await result.exitCode.timeout(const Duration(seconds: 3)), 130);
      }
      expect(await output, isEmpty);
      expect(await errors, [contains('KeyboardInterrupt')]);
      final recovered = await analyzer
          .analyze(request())
          .timeout(const Duration(seconds: 3));
      expect(recovered.unavailableReason, isNull);
      expect(recovered.diagnostics, isEmpty);
      expect(File(entry).readAsStringSync(), contains('while True'));
    },
    skip: !nativeAvailable,
  );
}
