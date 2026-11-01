import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_python/python_runner.dart';
import 'package:qfli_studio_core/content/asset_content_repository.dart';
import 'package:qfli_studio_core/content/local_content_adapter.dart';
import 'package:qfli_studio_core/services/code_import_service.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

import '../tool/python_content_ohos_audit.dart';

const _coreAssets = [
  'assets/content/tutorials.json',
  'assets/content/examples.json',
  'assets/tutorials/python.json',
];

String _digest(List<int> bytes) => sha256.convert(bytes).toString();

Map<String, Object?> _unit(String id, {String output = 'ok\n'}) => {
  'id': id,
  'topic': 1,
  'kind': 'audit-regression',
  'code': 'print("ok")\n',
  'inputFixtures': <String, String>{},
  'expectedOutput': output,
  'hasBehaviorCheck': true,
  'runtime': 'embedded',
};

String _inventory(
  List<Object?> units,
  Map<String, String> digests, {
  List<String> mismatches = const [],
}) => jsonEncode({
  'schemaVersion': 1,
  'assetMismatches': mismatches,
  'assetDigests': digests,
  'units': units,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory storage;
  late _Assets assets;
  late Map<String, String> digests;
  setUp(() {
    storage = Directory.systemTemp.createTempSync('python_content_audit_');
    assets = _Assets({
      for (final key in _coreAssets)
        'packages/qfli_studio_core/$key': utf8.encode('{"asset":"$key"}'),
    });
    digests = {
      for (final key in _coreAssets)
        key: _digest(assets.bytes['packages/qfli_studio_core/$key']!),
    };
  });
  tearDown(() {
    CodeImportService.beforeProjectFileWriteForTesting = null;
    if (storage.existsSync()) storage.deleteSync(recursive: true);
  });

  Future<Map<String, Object?>> audit(
    List<Object?> units,
    PythonProgramRunner runner, {
    String? expectedHash,
    List<String> mismatches = const [],
    Duration operationTimeout = const Duration(milliseconds: 200),
  }) {
    final inventory = _inventory(units, digests, mismatches: mismatches);
    return runPythonContentAudit(
      storage: storage,
      inventoryJson: inventory,
      inventorySha256: expectedHash ?? _digest(utf8.encode(inventory)),
      assetDigests: digests,
      assets: assets,
      runner: runner,
      operationTimeout: operationTimeout,
      settleTimeout: const Duration(milliseconds: 25),
    );
  }

  List<Map> cases(Map report) => (report['cases'] as List).cast<Map>();

  void exhaustiveFailure(Map report, int count) {
    expect(report['ok'], isFalse);
    expect(report['hostGatePassed'], isFalse);
    expect(report['deviceGatePassed'], isFalse);
    expect(report['planned'], count);
    expect(report['completed'], count);
    expect(report['omitted'], 0);
    expect(
      cases(report).every(
        (row) => const {
          'pass',
          'fail',
          'timeout',
          'unavailable',
        }.contains(row['status']),
      ),
      isTrue,
    );
    final durable = jsonDecode(
      File(report['reportFile'] as String).readAsStringSync(),
    );
    expect(durable['cases'], report['cases']);
  }

  test(
    'inventory hash mismatch makes every row unavailable before native work',
    () async {
      final runner = _CompletedRunner();
      final report = await audit(
        [_unit('first'), _unit('second')],
        runner,
        expectedHash: 'bad',
      );
      exhaustiveFailure(report, 2);
      expect(
        report['preflightErrors'].toString(),
        contains('Inventory hash mismatch'),
      );
      expect(cases(report).map((row) => row['status']), [
        'unavailable',
        'unavailable',
      ]);
      expect(runner.runs, 0);
      expect(runner.probes, 0);
    },
  );

  test(
    'authored/shipped mismatch is never accepted as a passing program',
    () async {
      final runner = _CompletedRunner();
      final report = await audit(
        [_unit('first')],
        runner,
        mismatches: ['lesson code'],
      );
      exhaustiveFailure(report, 1);
      expect(report['preflightErrors'].toString(), contains('lesson code'));
      expect(runner.runs, 0);
    },
  );

  test(
    'missing packaged asset and digest drift produce complete reports',
    () async {
      for (final missing in [true, false]) {
        final runner = _CompletedRunner();
        final key = 'packages/qfli_studio_core/${_coreAssets.last}';
        if (missing) {
          assets.bytes.remove(key);
        } else {
          assets.bytes[key] = utf8.encode('changed after export');
        }
        final report = await audit([_unit('first'), _unit('second')], runner);
        exhaustiveFailure(report, 2);
        expect(runner.runs, 0);
        expect(
          assets.requested.every(
            (key) => key.startsWith('packages/qfli_studio_core/'),
          ),
          isTrue,
        );
        expect(
          report['preflightErrors'].toString(),
          contains(missing ? 'Missing asset' : 'hash mismatch'),
        );
      }
    },
  );

  test(
    'missing runtime writes unavailable terminal results for every row',
    () async {
      final runner = _CompletedRunner(available: false);
      final report = await audit([_unit('first'), _unit('second')], runner);
      exhaustiveFailure(report, 2);
      expect(runner.runs, 0);
      expect(
        report['preflightErrors'].toString(),
        contains('deliberately unavailable'),
      );
    },
  );

  test(
    'malformed rows, duplicate IDs and missing behavior are not submitted',
    () async {
      final runner = _CompletedRunner();
      final report = await audit([
        null,
        {..._unit('unchecked'), 'hasBehaviorCheck': false},
        {..._unit('assertion-lie'), 'expectedOutput': null, 'validation': ''},
        _unit('duplicate'),
        _unit('duplicate'),
      ], runner);
      exhaustiveFailure(report, 5);
      expect(report['failed'], 5);
      expect(runner.runs, 0);
    },
  );

  test('line comparison preserves spaces and additional blank lines', () async {
    final runner = _CompletedRunner(
      outputs: [
        [' value ', ''],
        ['value', ''],
        [' value ', '', ''],
      ],
    );
    final report = await audit([
      _unit('exact', output: ' value \n\n'),
      _unit('lost-spaces', output: ' value \n\n'),
      _unit('extra-blank', output: ' value \n\n'),
    ], runner);
    exhaustiveFailure(report, 3);
    expect(cases(report).map((row) => row['status']), ['pass', 'fail', 'fail']);
    expect((report['outputComparison'] as Map)['rawByteComparison'], isFalse);
    expect(
      (report['outputComparison'] as Map)['limitations'],
      contains('missing final LF'),
    );
    expect(cases(report).first['expectedStdoutLines'], [' value ', '']);
  });

  test(
    'incremental report exists before native submission and each row settles',
    () async {
      final observations = <String>[];
      final runner = _CompletedRunner(
        beforeRun: () {
          final durable = jsonDecode(
            File(
              p.join(storage.path, pythonContentAuditReportName),
            ).readAsStringSync(),
          );
          final events = File(
            durable['journalFile'] as String,
          ).readAsLinesSync().map((line) => jsonDecode(line) as Map);
          final event = events.last;
          final row = event['record'] as Map;
          observations.add('${event['stage']}:${durable['completed']}');
          expect(row['status'], 'running');
          expect(row['importedEntry'], endsWith('main.py'));
          expect(durable['caseResultsIn'], durable['journalFile']);
        },
      );
      final report = await audit([_unit('first'), _unit('second')], runner);
      expect(report['ok'], isTrue);
      expect(report['deviceGatePassed'], isFalse);
      expect(report['omitted'], 0);
      expect(observations, ['unit:0:imported:0', 'unit:1:imported:1']);
      expect(runner.projects.toSet(), hasLength(2));
      expect(report['workDirectoryRemoved'], isTrue);
    },
  );

  test(
    'deadline requests Stop, waits for actual exit, and aborts later submissions',
    () async {
      final runner = _PendingRunner(settleOnCancel: true);
      final report = await audit([_unit('deadline'), _unit('after')], runner);
      exhaustiveFailure(report, 2);
      expect(cases(report).map((row) => row['status']), [
        'timeout',
        'unavailable',
      ]);
      expect(runner.runs, 1);
      expect(runner.cancelCalls, 1);
      expect(runner.exit.isCompleted, isTrue);
      expect(runner.projectExistedAtCancel, isTrue);
      expect(report['pendingOperations'], 0);
      expect(report['cleanupConfirmed'], isTrue);
      expect(report['workDirectoryRemoved'], isFalse);
      expect(
        Directory(cases(report).first['projectPath'] as String).existsSync(),
        isTrue,
      );
    },
  );

  test(
    'unsettled native exit retains files and durable result after late completion',
    () async {
      final runner = _PendingRunner();
      final report = await audit([_unit('deadline'), _unit('after')], runner);
      exhaustiveFailure(report, 2);
      expect(report['pendingOperations'], 1);
      expect(report['cleanupConfirmed'], isFalse);
      expect(runner.runs, 1);
      final work = Directory(report['workDirectory'] as String);
      final durable = File(report['reportFile'] as String).readAsStringSync();
      runner.exit.complete(130);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(work.existsSync(), isTrue);
      expect(File(report['reportFile'] as String).readAsStringSync(), durable);
    },
  );

  test(
    'late run handle receives Stop while its project remains available',
    () async {
      final runner = _PendingRunner(delayHandle: true, settleOnCancel: true);
      final report = await audit([
        _unit('late-handle'),
        _unit('after'),
      ], runner);
      exhaustiveFailure(report, 2);
      expect(report['pendingOperations'], 1);
      expect(runner.cancelCalls, 0);
      final durable = File(report['reportFile'] as String).readAsStringSync();
      runner.deliverHandle();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(runner.cancelCalls, 1);
      expect(runner.exit.isCompleted, isTrue);
      expect(runner.projectExistedAtCancel, isTrue);
      expect(File(report['reportFile'] as String).readAsStringSync(), durable);
      expect(Directory(report['workDirectory'] as String).existsSync(), isTrue);
    },
  );

  test(
    'early stream error cannot release an unfinished native execution',
    () async {
      final runner = _PendingRunner(streamError: true, settleOnCancel: true);
      final report = await audit([_unit('stream-error')], runner);
      exhaustiveFailure(report, 1);
      expect(cases(report).single['status'], 'timeout');
      expect(runner.cancelCalls, 1);
      expect(runner.exit.isCompleted, isTrue);
      expect(report['pendingOperations'], 0);
    },
  );

  test(
    'late import completion retains files and never submits a native run',
    () async {
      final blockedWrite = Completer<void>();
      CodeImportService.beforeProjectFileWriteForTesting = (_) =>
          blockedWrite.future;
      final runner = _CompletedRunner();
      final report = await audit([
        _unit('late-import'),
        _unit('after'),
      ], runner);
      exhaustiveFailure(report, 2);
      expect(cases(report).first['status'], 'timeout');
      expect(report['pendingOperations'], 1);
      final before = jsonEncode(report);
      blockedWrite.complete();
      // Await real filesystem completion through a bounded poll, without another
      // audit operation taking ownership of the unfinished project.
      final entry = File(
        p.join(cases(report).first['projectPath'] as String, 'src', 'main.py'),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (!entry.existsSync() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(entry.readAsStringSync(), 'print("ok")\n');
      expect(runner.runs, 0);
      expect(jsonEncode(report), before);
    },
  );

  final library = p.absolute(
    Platform.environment['QFLI_PYTHON_TEST_LIBRARY'] ??
        p.join(
          'native',
          'build',
          Platform.operatingSystem,
          Platform.isWindows
              ? 'qfli_py_ffi.dll'
              : Platform.isMacOS
              ? 'libqfli_py_ffi.dylib'
              : 'libqfli_py_ffi.so',
        ),
  );
  test(
    'real adapter→import→embedded input008 and package117 preserve exact fixtures',
    () async {
      final examples = await LocalContentAdapter.loadExamples(
        repository: AssetContentRepository(),
        language: 'python',
        productKey: 'pyflow',
      );
      final input = examples.singleWhere(
        (example) => example.id == 'python-example-008',
      );
      final package = examples.singleWhere(
        (example) => example.id == 'python-example-117',
      );
      expect(input.inputFixtures, {'stdin': '17\n5\n'});
      expect(input.output, '22\n85\n');
      expect(
        package.inputFixtures.keys,
        containsAll(['pricing/__init__.py', 'pricing/totals.py']),
      );
      final actualDigests = <String, String>{};
      for (final key in _coreAssets) {
        final bytes = await rootBundle.load('packages/qfli_studio_core/$key');
        actualDigests[key] = _digest(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
      }
      final units = [
        for (final example in [input, package])
          {
            'id': '${example.id}:adapter-import',
            'topic': example == input ? 8 : 117,
            'kind': 'aggregate-example-through-adapter',
            'code': example.code,
            'inputFixtures': example.inputFixtures,
            'expectedOutput': example.output,
            'hasBehaviorCheck': true,
            'runtime': 'embedded',
          },
      ];
      final inventory = _inventory(units, actualDigests);
      final report = await runPythonContentAudit(
        storage: storage,
        inventoryJson: inventory,
        inventorySha256: _digest(utf8.encode(inventory)),
        assetDigests: actualDigests,
        runner: PythonProgramRunner(
          transport: PythonNativeTransport.ffi,
          libraryPath: library,
        ),
      );
      expect(report['ok'], isTrue, reason: jsonEncode(report));
      expect(report['hostGatePassed'], isTrue);
      expect(report['deviceGatePassed'], isFalse);
      expect(report['planned'], 2);
      expect(report['passed'], 2);
      expect(report['omitted'], 0);
      final imported = cases(report);
      expect(imported.first['stdout'], ['22', '85']);
      expect(
        (imported.first['importedFileSha256'] as Map)['input.txt'],
        _digest(utf8.encode('17\n5\n')),
      );
      expect(
        (imported.last['importedFileSha256'] as Map).keys,
        containsAll([
          'src/main.py',
          'pricing/__init__.py',
          'pricing/totals.py',
        ]),
      );
      expect((report['runtime'] as Map)['transport'], 'ffi');
    },
    skip: !File(library).existsSync(),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

class _Assets extends CachingAssetBundle {
  _Assets(this.bytes);
  final Map<String, List<int>> bytes;
  final requested = <String>[];
  @override
  Future<ByteData> load(String key) async {
    requested.add(key);
    final value = bytes[key];
    if (value == null) throw StateError('Missing asset: $key');
    return ByteData.sublistView(Uint8List.fromList(value));
  }
}

class _CompletedRunner extends PythonProgramRunner {
  _CompletedRunner({
    this.available = true,
    this.outputs = const [],
    this.beforeRun,
  });
  final bool available;
  final List<List<String>> outputs;
  final void Function()? beforeRun;
  final projects = <String>[];
  int probes = 0;
  int runs = 0;
  @override
  Future<PythonRuntimeInfo> runtimeInfo() async {
    probes++;
    return PythonRuntimeInfo(
      available: available,
      version: 'test-double',
      detail: 'deliberately unavailable',
      transport: 'ffi',
      supportsCancellation: true,
    );
  }

  @override
  Future<ProgramRunResult?> run({
    required String projectPath,
    required String entryFile,
  }) async {
    beforeRun?.call();
    projects.add(projectPath);
    final output = runs < outputs.length ? outputs[runs] : ['ok'];
    runs++;
    return ProgramRunResult(
      title: 'completed double',
      stdout: Stream.fromIterable(output),
      stderr: const Stream.empty(),
      exitCode: Future.value(0),
      cancel: () async {},
    );
  }
}

class _PendingRunner extends _CompletedRunner {
  _PendingRunner({
    this.settleOnCancel = false,
    this.delayHandle = false,
    this.streamError = false,
  });
  final bool settleOnCancel;
  final bool delayHandle;
  final bool streamError;
  final exit = Completer<int>();
  final _handle = Completer<ProgramRunResult?>();
  int cancelCalls = 0;
  bool projectExistedAtCancel = false;
  String? entry;
  ProgramRunResult _result() => ProgramRunResult(
    title: 'unfinished double',
    stdout: streamError
        ? Stream.error(StateError('deliberate stream failure'))
        : const Stream.empty(),
    stderr: const Stream.empty(),
    exitCode: exit.future,
    cancel: () async {
      cancelCalls++;
      projectExistedAtCancel = File(entry!).existsSync();
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
    entry = entryFile;
    return delayHandle ? _handle.future : _result();
  }
}
