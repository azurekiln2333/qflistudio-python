import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_python/python_runner.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

import '../tool/python_module_ohos_audit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory storage;
  setUp(
    () => storage = Directory.systemTemp.createTempSync('python_audit_test_'),
  );
  tearDown(() {
    if (storage.existsSync()) storage.deleteSync(recursive: true);
  });

  const source = 'print("suite")\n';
  final sourceHash = sha256.convert(utf8.encode(source)).toString();
  final assetBytes = utf8.encode('{"audit":true}');
  final assetDigests = {
    'assets/python_stdlib/manifest.json': sha256.convert(assetBytes).toString(),
  };

  Future<Map<String, Object?>> audit(_PendingRunner runner) =>
      runPythonModuleAudit(
        storage: storage,
        suiteSource: source,
        suiteSha256: sourceHash,
        assetDigests: assetDigests,
        assets: _AuditAssets(assetBytes),
        runner: runner,
        operationTimeout: const Duration(milliseconds: 50),
        settleTimeout: const Duration(milliseconds: 20),
      );

  test(
    'unavailable runtime writes failure without claiming either gate',
    () async {
      final report = await runPythonModuleAudit(
        storage: storage,
        suiteSource: source,
        suiteSha256: sourceHash,
        assetDigests: assetDigests,
        runner: const _UnavailableRunner(),
      );
      expect(report['ok'], isFalse);
      expect(report['deviceGatePassed'], isFalse);
      expect(report['hostGatePassed'], isFalse);
      expect(report['workDirectoryRemoved'], isTrue);
      final durable =
          jsonDecode(File(report['reportFile']! as String).readAsStringSync())
              as Map;
      expect(durable['error'], contains('deliberately unavailable'));
      expect(durable['status'], 'failed');
    },
  );

  test(
    'suite identity mismatch is rejected before program execution',
    () async {
      final runner = _PendingRunner();
      final report = await runPythonModuleAudit(
        storage: storage,
        suiteSource: source,
        suiteSha256: 'wrong-hash',
        assetDigests: assetDigests,
        runner: runner,
      );
      expect(report['ok'], isFalse);
      expect(report['error'], contains('Suite hash mismatch'));
      expect(runner.runs, 0);
      expect(report['workDirectoryRemoved'], isTrue);
    },
  );

  test('deadline cancels and waits for actual exit before cleanup', () async {
    final runner = _PendingRunner(settleOnCancel: true);
    final report = await audit(runner);
    expect(runner.cancelCalls, 1);
    expect(runner.exit.isCompleted, isTrue);
    expect(report['ok'], isFalse);
    expect(report['deviceGatePassed'], isFalse);
    expect(report['pendingOperations'], 0);
    expect(report['cleanupConfirmed'], isTrue);
    expect(report['workDirectoryRemoved'], isTrue);
    expect(Directory(report['workDirectory']! as String).existsSync(), isFalse);
  });

  test('unsettled native work retains its files after deadline', () async {
    final runner = _PendingRunner();
    final report = await audit(runner);
    expect(runner.cancelCalls, 1);
    expect(report['ok'], isFalse);
    expect(report['pendingOperations'], 1);
    expect(report['cleanupConfirmed'], isFalse);
    expect(report['workDirectoryRemoved'], isFalse);
    final work = Directory(report['workDirectory']! as String);
    expect(work.existsSync(), isTrue);
    final durableBefore = File(
      report['reportFile']! as String,
    ).readAsStringSync();
    runner.exit.complete(130);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(work.existsSync(), isTrue);
    expect(
      File(report['reportFile']! as String).readAsStringSync(),
      durableBefore,
    );
  });

  test(
    'handle arriving after deadline is cancelled without deleting active work',
    () async {
      final runner = _PendingRunner(delayHandle: true);
      final report = await audit(runner);
      expect(report['pendingOperations'], 1);
      expect(runner.cancelCalls, 0);
      final work = Directory(report['workDirectory']! as String);
      expect(work.existsSync(), isTrue);
      runner.deliverHandle();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(runner.cancelCalls, 1);
      expect(work.existsSync(), isTrue);
      runner.exit.complete(130);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    },
  );

  final library = p.absolute('native/build/windows/qfli_py_ffi.dll');
  test(
    'real embedded module and package acceptance keeps OHOS gate separate',
    () async {
      final portable = File(
        'native/tests/python_stdlib_smoke.py',
      ).readAsBytesSync();
      final digests = <String, String>{};
      for (final file in Directory(
        'assets/python_stdlib',
      ).listSync(recursive: true).whereType<File>()) {
        digests[file.path.replaceAll('\\', '/')] = sha256
            .convert(file.readAsBytesSync())
            .toString();
      }
      final report = await runPythonModuleAudit(
        storage: storage,
        suiteSource: utf8.decode(portable),
        suiteSha256: sha256.convert(portable).toString(),
        assetDigests: digests,
        runner: PythonProgramRunner(
          transport: PythonNativeTransport.ffi,
          libraryPath: library,
        ),
      );
      expect(
        report['ok'],
        isTrue,
        reason: '${report['error']}\n${report['cases']}',
      );
      expect(report['hostGatePassed'], isTrue);
      expect(report['deviceGatePassed'], isFalse);
      expect(
        (report['stdlib']! as Map)['assertions'],
        greaterThanOrEqualTo(300),
      );
      expect((report['stdlib']! as Map)['modules'], hasLength(10));
      expect(
        (report['cases']! as List).every((item) => (item as Map)['ok'] == true),
        isTrue,
      );
      expect(report['workDirectoryRemoved'], isTrue);
      expect(report['pendingOperations'], 0);
      expect(report['verifiedPackagedAssets'], digests);
    },
    skip: !Platform.isWindows || !File(library).existsSync(),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

class _AuditAssets extends CachingAssetBundle {
  _AuditAssets(this.bytes);
  final List<int> bytes;
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(bytes));
}

class _UnavailableRunner extends PythonProgramRunner {
  const _UnavailableRunner();
  @override
  Future<PythonRuntimeInfo> runtimeInfo() async => const PythonRuntimeInfo(
    available: false,
    detail: 'deliberately unavailable',
  );
}

class _PendingRunner extends PythonProgramRunner {
  _PendingRunner({this.settleOnCancel = false, this.delayHandle = false});
  final bool settleOnCancel;
  final bool delayHandle;
  final exit = Completer<int>();
  final _handle = Completer<ProgramRunResult?>();
  int cancelCalls = 0;
  int runs = 0;

  @override
  Future<PythonRuntimeInfo> runtimeInfo() async => const PythonRuntimeInfo(
    available: true,
    transport: 'ffi',
    supportsCancellation: true,
  );

  ProgramRunResult _result() => ProgramRunResult(
    title: 'pending native execution',
    stdout: const Stream.empty(),
    stderr: const Stream.empty(),
    exitCode: exit.future,
    cancel: () async {
      cancelCalls++;
      if (settleOnCancel && !exit.isCompleted) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        exit.complete(130);
      }
    },
  );

  void deliverHandle() => _handle.complete(_result());

  @override
  Future<ProgramRunResult?> run({
    required String projectPath,
    required String entryFile,
  }) async {
    runs++;
    return delayHandle ? _handle.future : _result();
  }
}
