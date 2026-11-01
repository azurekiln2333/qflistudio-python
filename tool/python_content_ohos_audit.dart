/// Exhaustive shipped-content acceptance through the real import and runner APIs.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_python/python_runner.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/models/tutorial.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/code_import_service.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

const pythonContentAuditReportName = 'qfli-python-content-audit.json';

/// Audit-only entry point; it does not alter the normal application entry.
void startPythonContentAudit({
  required String inventoryJson,
  required String inventorySha256,
  required Map<String, String> assetDigests,
  Map<String, Object?> buildEvidence = const {},
}) {
  WidgetsFlutterBinding.ensureInitialized();
  final status = ValueNotifier('Python content acceptance is running…');
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: ValueListenableBuilder<String>(
          valueListenable: status,
          builder: (_, value, _) => Text(value),
        ),
      ),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      final storage = await AppPaths.storageDirectory().timeout(
        const Duration(seconds: 20),
      );
      if (storage == null) throw StateError('No writable AppPaths storage');
      final report = await runPythonContentAudit(
        storage: Directory(storage),
        inventoryJson: inventoryJson,
        inventorySha256: inventorySha256,
        assetDigests: assetDigests,
        buildEvidence: buildEvidence,
        onProgress: (stage) {
          status.value = 'Python content acceptance: $stage';
          debugPrint('QFLI_PYTHON_CONTENT_STAGE $stage');
        },
      );
      final summary = {
        for (final name in [
          'ok',
          'hostGatePassed',
          'deviceGatePassed',
          'planned',
          'completed',
          'passed',
          'failed',
          'unavailable',
          'timedOut',
          'reportFile',
        ])
          name: report[name],
        'reportSha256': _digest(
          await File(report['reportFile']! as String).readAsBytes(),
        ),
      };
      status.value = const JsonEncoder.withIndent('  ').convert(summary);
      debugPrint('QFLI_PYTHON_CONTENT_AUDIT ${jsonEncode(summary)}');
    } catch (error, stack) {
      final failure = {
        'ok': false,
        'deviceGatePassed': false,
        'error': '$error',
        'stack': '$stack',
      };
      status.value = jsonEncode(failure);
      debugPrint('QFLI_PYTHON_CONTENT_AUDIT ${jsonEncode(failure)}');
    }
  });
}

/// Every decoded inventory row receives a terminal result, including rows that
/// cannot be submitted after a failed prerequisite or an unsettled operation.
/// Declared build inputs need independent HAP/SO inspection; these are not hashes
/// of loaded memory. Only OHOS plus the method channel can satisfy the device gate.
Future<Map<String, Object?>> runPythonContentAudit({
  required Directory storage,
  required String inventoryJson,
  required String inventorySha256,
  required Map<String, String> assetDigests,
  Map<String, Object?> buildEvidence = const {},
  PythonProgramRunner? runner,
  AssetBundle? assets,
  Duration operationTimeout = const Duration(seconds: 90),
  Duration settleTimeout = const Duration(seconds: 15),
  void Function(String stage)? onProgress,
}) async {
  await storage.create(recursive: true);
  final reportFile = File(p.join(storage.path, pythonContentAuditReportName));
  final journalFile = File('${reportFile.path}l');
  await journalFile.writeAsString('', flush: true);
  final work = await storage.createTemp('qfli_python_content_audit_');
  final execution = runner ?? const PythonProgramRunner();
  final tracker = _PendingOperations(operationTimeout, settleTimeout);
  final rows = <Object?>[];
  final records = <Map<String, Object?>>[];
  final preflightErrors = <String>[];
  PythonRuntimeInfo? runtime;
  final report = <String, Object?>{
    'schemaVersion': 1,
    'kind': 'python-exhaustive-content-acceptance',
    'expectedBundleName': 'com.azurekiln.qfli.pyflow',
    'expectedOhosPullPath':
        '/data/app/el2/100/base/com.azurekiln.qfli.pyflow/files/$pythonContentAuditReportName',
    'startedAtUtc': _now(),
    'operatingSystem': Platform.operatingSystem,
    'operatingSystemVersion': Platform.operatingSystemVersion,
    'dartVersion': Platform.version,
    'reportFile': reportFile.path,
    'journalFile': journalFile.path,
    'journalFormat':
        'JSONL snapshots by row index; before/imported/after are durable',
    'workDirectory': work.path,
    'inventorySha256': inventorySha256,
    'actualInventorySha256': _digest(utf8.encode(inventoryJson)),
    'declaredAssetDigests': Map<String, String>.of(assetDigests),
    'declaredBuildInputs': buildEvidence,
    'outputComparison': {
      'mode': 'PythonProgramRunner line streams',
      'rawByteComparison': false,
      'limitations':
          'Runner removes one terminal LF and one terminal CR per line. '
          'A missing final LF cannot be distinguished. Spaces and additional '
          'blank lines are preserved; this is weaker than host raw stdout comparison.',
      'assertionOnlyUnits':
          'Null expectedOutput requires nonempty validation; actual output is recorded, '
          'while embedded assertions establish behavior.',
    },
    'cases': records,
    'preflightErrors': preflightErrors,
    'ok': false,
    'hostGatePassed': false,
    'deviceGatePassed': false,
    'status': 'running',
  };

  Future<void> persist(String stage, [Map<String, Object?>? row]) async {
    report['stage'] = stage;
    report['updatedAtUtc'] = _now();
    report['planned'] = rows.length;
    report['completed'] = records.where(_terminal).length;
    for (final entry in const {
      'passed': 'pass',
      'failed': 'fail',
      'unavailable': 'unavailable',
      'timedOut': 'timeout',
    }.entries) {
      report[entry.key] = records
          .where((r) => r['status'] == entry.value)
          .length;
    }
    report['omitted'] = rows.length - records.where(_terminal).length;
    final event = <String, Object?>{
      'stage': stage,
      'updatedAtUtc': report['updatedAtUtc'],
      'planned': report['planned'],
      'completed': report['completed'],
      'record': ?row,
    };
    await journalFile.writeAsString(
      '${jsonEncode(event)}\n',
      mode: FileMode.append,
      flush: true,
    );
    // Writing the growing full inventory thousands of times would write GBs
    // on device. The journal preserves each row; checkpoints stay small until
    // the final self-contained report includes every terminal result.
    final checkpoint = <String, Object?>{
      ...report,
      if (stage != 'finished') 'cases': <Object?>[],
      'caseResultsIn': stage == 'finished' ? 'cases' : journalFile.path,
    };
    await reportFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(checkpoint),
      flush: true,
    );
    onProgress?.call(stage);
  }

  try {
    final inventory = jsonDecode(inventoryJson);
    if (inventory is! Map || inventory['units'] is! List) {
      throw const FormatException('Inventory must contain a units array');
    }
    rows.addAll(inventory['units'] as List);
    for (var index = 0; index < rows.length; index++) {
      final raw = rows[index];
      records.add({
        'index': index,
        'inventoryRowSha256': _digest(utf8.encode(jsonEncode(raw))),
        'id': raw is Map ? raw['id'] : null,
        'topic': raw is Map ? raw['topic'] : null,
        'kind': raw is Map ? raw['kind'] : null,
        'sourceSha256': raw is Map && raw['code'] is String
            ? _digest(utf8.encode(raw['code'] as String))
            : null,
        'fixtureSha256': raw is Map
            ? _fixtureHashes(raw['inputFixtures'])
            : null,
        'expectedOutputSha256': raw is Map && raw['expectedOutput'] is String
            ? _digest(utf8.encode(raw['expectedOutput'] as String))
            : null,
        'hasBehaviorCheck': raw is Map ? raw['hasBehaviorCheck'] : null,
        'status': 'pending',
      });
    }
    await persist('preflight:before');
    try {
      _require(rows.isNotEmpty, 'Inventory contains no units');
      _require(inventory['schemaVersion'] == 1, 'Unsupported inventory schema');
      _require(
        report['actualInventorySha256'] == inventorySha256,
        'Inventory hash mismatch',
      );
      final mismatches = inventory['assetMismatches'];
      _require(mismatches is List, 'Missing assetMismatches inventory field');
      _require(
        (mismatches as List).isEmpty,
        'Authored/shipped asset mismatch: $mismatches',
      );
      final declaredAssets = _strings(
        inventory['assetDigests'],
        'assetDigests',
      );
      _require(
        mapEquals(declaredAssets, assetDigests),
        'Inventory asset digest map mismatch',
      );
      const requiredAssets = {
        'assets/content/tutorials.json',
        'assets/content/examples.json',
        'assets/tutorials/python.json',
      };
      _require(
        assetDigests.keys.toSet().containsAll(requiredAssets),
        'Missing shipped asset digests',
      );
      final verified = <String, String>{};
      report['verifiedPackagedAssets'] = verified;
      for (final asset in assetDigests.entries) {
        _require(
          asset.key.startsWith('assets/') &&
              !asset.key.contains('\\') &&
              asset.key
                  .split('/')
                  .every(
                    (part) => part.isNotEmpty && part != '.' && part != '..',
                  ),
          'Unexpected core asset path: ${asset.key}',
        );
        final key = 'packages/qfli_studio_core/${asset.key}';
        final data = await tracker.wait(
          (assets ?? rootBundle).load(key),
          'asset $key',
        );
        final actual = _digest(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        _require(
          actual == asset.value,
          'Packaged asset hash mismatch: $key; '
          'expected=${asset.value}; actual=$actual',
        );
        verified[key] = actual;
      }
      final bundled = buildEvidence['bundledModuleAssetDigests'];
      if (bundled != null) {
        final verifiedModules = <String, String>{};
        report['verifiedBundledModuleAssets'] = verifiedModules;
        for (final asset in _strings(
          bundled,
          'bundledModuleAssetDigests',
        ).entries) {
          _require(
            asset.key.startsWith('assets/python_stdlib/') &&
                !asset.key.contains('\\') &&
                asset.key
                    .split('/')
                    .every(
                      (part) => part.isNotEmpty && part != '.' && part != '..',
                    ),
            'Unexpected bundled module asset: ${asset.key}',
          );
          final data = await tracker.wait(
            (assets ?? rootBundle).load(asset.key),
            'bundled asset ${asset.key}',
          );
          final actual = _digest(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
          _require(
            actual == asset.value,
            'Bundled module asset hash mismatch: ${asset.key}; '
            'expected=${asset.value}; actual=$actual',
          );
          verifiedModules[asset.key] = actual;
        }
      }
      final activeRuntime = await tracker.wait(
        execution.runtimeInfo(),
        'runtime probe',
      );
      runtime = activeRuntime;
      report['runtime'] = {
        'available': activeRuntime.available,
        'version': activeRuntime.version,
        'detail': activeRuntime.detail,
        'transport': activeRuntime.transport,
        'supportsCancellation': activeRuntime.supportsCancellation,
      };
      _require(
        activeRuntime.available,
        'Embedded runtime unavailable: ${activeRuntime.detail}',
      );
      _require(
        activeRuntime.supportsCancellation,
        'Acceptance requires real Stop support',
      );
      _require(
        Platform.operatingSystem != 'ohos' ||
            activeRuntime.transport == 'methodChannel',
        'OHOS acceptance requires the actual methodChannel transport',
      );
    } catch (error) {
      preflightErrors.add('$error');
    }
    await persist('preflight:after');

    final ids = <String, int>{};
    for (final raw in rows.whereType<Map>()) {
      final id = raw['id'];
      if (id is String) ids.update(id, (count) => count + 1, ifAbsent: () => 1);
    }
    String? abortReason;
    for (var index = 0; index < rows.length; index++) {
      final record = records[index];
      record['status'] = 'running';
      record['startedAtUtc'] = _now();
      await persist('unit:$index:before', record);
      try {
        if (preflightErrors.isNotEmpty || abortReason != null) {
          record['status'] = 'unavailable';
          record['reason'] = abortReason ?? preflightErrors.join('; ');
          continue;
        }
        final unit = _Unit.parse(rows[index]);
        _require(ids[unit.id] == 1, 'Duplicate unit ID: ${unit.id}');
        record.addAll({
          'sourceSha256': _digest(utf8.encode(unit.code)),
          'fixtureSha256': {
            for (final fixture in unit.fixtures.entries)
              fixture.key: _digest(utf8.encode(fixture.value)),
          },
          'expectedOutputSha256': unit.expectedOutput == null
              ? null
              : _digest(utf8.encode(unit.expectedOutput!)),
          'expectedStdoutLines': unit.expectedOutput == null
              ? null
              : _runnerLines(unit.expectedOutput!),
          'expectedStderrLines': <String>[],
          'expectedExitCode': 0,
          'hasBehaviorCheck': true,
        });
        final project = await Directory(
          p.join(work.path, 'unit_$index'),
        ).create();
        record['projectPath'] = project.path;
        final imported = await tracker.wait(
          _importUnit(unit, project),
          'import ${unit.id}',
        );
        record['importedEntry'] = imported.entry.path;
        record['importedFileSha256'] = imported.digests;
        await persist('unit:$index:imported', record);
        final output = await _execute(
          tracker,
          execution,
          project,
          imported.entry,
        );
        record.addAll({
          'exitCode': output.exitCode,
          'stdout': output.stdout,
          'stderr': output.stderr,
          'nativeAndStreamsSettled': true,
        });
        final problems = <String>[
          if (output.exitCode != 0) 'Expected exit 0; got ${output.exitCode}',
          if (output.stderr.isNotEmpty) 'Unexpected stderr',
          if (unit.expectedOutput != null &&
              !listEquals(output.stdout, _runnerLines(unit.expectedOutput!)))
            'Exact runner stdout lines mismatch',
        ];
        record['problems'] = problems;
        record['status'] = output.exitCode == kProgramNotRunExitCode
            ? 'unavailable'
            : problems.isEmpty
            ? 'pass'
            : 'fail';
      } on TimeoutException catch (error) {
        record['status'] = 'timeout';
        record['reason'] = '$error';
        record['nativeAndStreamsSettled'] = tracker.pendingCount == 0;
        abortReason =
            'Further submissions aborted after timeout at row $index; '
            'pending underlying operations: ${tracker.pendingCount}';
      } catch (error, stack) {
        record['status'] = 'fail';
        record['reason'] = '$error';
        record['stack'] = '$stack';
      } finally {
        record['finishedAtUtc'] = _now();
        // Keep failure/timeout projects for diagnosis, even if Stop has settled.
        if (record['status'] == 'pass' && tracker.pendingCount == 0) {
          final path = record['projectPath'] as String?;
          if (path != null) {
            try {
              await Directory(path).delete(recursive: true);
              record['projectRemoved'] = true;
            } catch (error) {
              record['status'] = 'fail';
              record['reason'] = 'Project cleanup failed: $error';
            }
          }
        }
        await persist('unit:$index:after', record);
      }
    }
  } catch (error, stack) {
    report['error'] = '$error';
    report['stack'] = '$stack';
  } finally {
    await tracker.settle();
    for (final record in records.where((row) => !_terminal(row))) {
      record['status'] = 'unavailable';
      record['reason'] =
          'Audit interrupted before terminal result: ${report['error']}';
      record['finishedAtUtc'] = _now();
    }
    report['pendingOperations'] = tracker.pendingCount;
    report['cancellationErrors'] = List<String>.of(tracker.cancellationErrors);
    report['cleanupConfirmed'] = tracker.pendingCount == 0;
    final allPassed =
        rows.isNotEmpty &&
        records.length == rows.length &&
        records.every((row) => row['status'] == 'pass') &&
        preflightErrors.isEmpty &&
        report['error'] == null &&
        tracker.pendingCount == 0 &&
        tracker.cancellationErrors.isEmpty;
    if (allPassed || work.listSync().isEmpty && tracker.pendingCount == 0) {
      try {
        await work.delete(recursive: true);
        report['workDirectoryRemoved'] = true;
      } catch (error) {
        report['cleanupError'] = '$error';
        report['workDirectoryRemoved'] = false;
      }
    } else {
      report['workDirectoryRemoved'] = false;
      report['retentionReason'] = tracker.pendingCount > 0
          ? 'Underlying work has not settled; active project files are retained.'
          : 'Failed or timed out project files are retained for inspection.';
    }
    final ok = allPassed && report['cleanupError'] == null;
    report['ok'] = ok;
    report['hostGatePassed'] =
        ok && Platform.operatingSystem != 'ohos' && runtime?.transport == 'ffi';
    report['deviceGatePassed'] =
        ok &&
        Platform.operatingSystem == 'ohos' &&
        runtime?.transport == 'methodChannel';
    report['status'] = ok ? 'passed' : 'failed';
    report['finishedAtUtc'] = _now();
    await persist('finished');
  }
  return report;
}

class _Unit {
  _Unit(this.id, this.code, this.fixtures, this.expectedOutput);
  final String id;
  final String code;
  final Map<String, String> fixtures;
  final String? expectedOutput;

  factory _Unit.parse(Object? raw) {
    _require(raw is Map, 'Unit must be an object');
    final value = raw as Map;
    final id = value['id'];
    final code = value['code'];
    _require(id is String && id.isNotEmpty, 'Missing stable unit ID');
    _require(
      code is String && code.trim().isNotEmpty,
      'Missing executable source',
    );
    _require(
      value['kind'] is String && value['topic'] is int,
      'Missing kind/topic identity',
    );
    _require(value['runtime'] == 'embedded', 'Unit is not labeled embedded');
    final output = value['expectedOutput'];
    _require(output == null || output is String, 'Invalid expectedOutput');
    final validation = value['validation'];
    _require(
      value['hasBehaviorCheck'] == true &&
          (output is String ||
              validation is String && validation.trim().isNotEmpty),
      'Missing behavioral expectation',
    );
    return _Unit(
      id as String,
      code as String,
      _strings(value['inputFixtures'], 'inputFixtures'),
      output as String?,
    );
  }
}

class _ImportedUnit {
  _ImportedUnit(this.entry, this.digests);
  final File entry;
  final Map<String, String> digests;
}

Future<_ImportedUnit> _importUnit(_Unit unit, Directory directory) async {
  final example = ExampleCode(
    id: unit.id,
    type: 'python',
    language: 'Python',
    title: unit.id,
    summary: 'Exhaustive imported-content acceptance',
    code: unit.code,
    output: unit.expectedOutput ?? '',
    inputFixtures: unit.fixtures,
  );
  final project = Project.create(
    name: 'Python content audit',
    path: directory.path,
    language: 'Python',
    type: 'python',
  );
  final imported = await CodeImportService.importIntoProject(
    project: project,
    example: example,
    fileName: 'main.py',
  );
  _require(
    p.equals(imported.path, p.join(directory.path, 'src', 'main.py')),
    'Import did not select src/main.py: ${imported.path}',
  );
  final expectedFiles = CodeImportService.projectFiles(
    example: example,
    entryFile: 'src/main.py',
  );
  final actualDigests = <String, String>{};
  for (final file in expectedFiles.entries) {
    final bytes = await File(p.join(directory.path, file.key)).readAsBytes();
    final actual = _digest(bytes);
    _require(
      actual == _digest(utf8.encode(file.value)),
      'Imported file mismatch: ${file.key}',
    );
    actualDigests[file.key] = actual;
  }
  return _ImportedUnit(File(imported.path), actualDigests);
}

class _RunOutput {
  _RunOutput(this.exitCode, this.stdout, this.stderr);
  final int exitCode;
  final List<String> stdout;
  final List<String> stderr;
}

Future<_RunOutput> _execute(
  _PendingOperations tracker,
  PythonProgramRunner runner,
  Directory project,
  File entry,
) {
  ProgramRunResult? handle;
  var stopRequested = false;
  Future<void>? cancelling;
  Future<void> requestStop() {
    stopRequested = true;
    if (handle == null) return Future<void>.value();
    return cancelling ??= tracker.observeCancellation(() async {
      final stop = handle!.cancel;
      if (stop == null) {
        throw StateError('Run handle has no cancellation function');
      }
      await stop();
    });
  }

  final pending = () async {
    final result = await runner.run(
      projectPath: project.path,
      entryFile: entry.path,
    );
    handle = result;
    if (result == null) {
      throw StateError('Runner declined imported Python entry');
    }
    // Attach all observers together. A stream error must not release project
    // lifetime before the real exit future and the other stream have settled.
    final values = Future.wait<Object?>([
      result.exitCode,
      result.stdout.toList(),
      result.stderr.toList(),
    ]);
    if (stopRequested) unawaited(requestStop());
    final complete = await values;
    return _RunOutput(
      complete[0]! as int,
      complete[1]! as List<String>,
      complete[2]! as List<String>,
    );
  }();
  return tracker.wait(
    pending,
    'embedded ${p.basename(entry.path)}',
    onTimeout: requestStop,
  );
}

/// Completion observers survive deadlines. They never mutate reports or delete
/// files after return, and late handles still receive their requested Stop.
class _PendingOperations {
  _PendingOperations(this.deadline, this.settleDeadline);
  final Duration deadline;
  final Duration settleDeadline;
  final Set<Future<void>> _pending = {};
  final List<String> cancellationErrors = [];
  int get pendingCount => _pending.length;

  Future<T> _observe<T>(Future<T> operation) {
    final settled = Completer<void>();
    _pending.add(settled.future);
    return operation.whenComplete(() {
      _pending.remove(settled.future);
      settled.complete();
    });
  }

  Future<void> observeCancellation(Future<void> Function() stop) =>
      _observe(Future<void>.sync(stop)).catchError((Object error) {
        cancellationErrors.add('$error');
      });

  Future<T> wait<T>(
    Future<T> operation,
    String label, {
    Future<void> Function()? onTimeout,
  }) async {
    try {
      return await _observe(operation).timeout(deadline);
    } on TimeoutException {
      if (onTimeout != null) {
        try {
          await onTimeout().timeout(settleDeadline);
        } catch (error) {
          cancellationErrors.add('$error');
        }
      }
      await settle();
      throw TimeoutException(
        '$label exceeded deadline; pending work: $pendingCount',
        deadline,
      );
    }
  }

  Future<void> settle() async {
    final elapsed = Stopwatch()..start();
    while (_pending.isNotEmpty && elapsed.elapsed < settleDeadline) {
      try {
        await Future.wait(
          _pending.toList(),
        ).timeout(settleDeadline - elapsed.elapsed);
      } on TimeoutException {
        return;
      }
    }
  }
}

Map<String, String> _strings(Object? raw, String name) {
  _require(raw is Map, 'Missing/invalid $name map');
  final value = raw as Map;
  _require(
    value.keys.every((key) => key is String) &&
        value.values.every((item) => item is String),
    'Non-string $name entry',
  );
  return value.cast<String, String>();
}

Map<String, String>? _fixtureHashes(Object? raw) {
  if (raw is! Map ||
      raw.keys.any((key) => key is! String) ||
      raw.values.any((value) => value is! String)) {
    return null;
  }
  return {
    for (final entry in raw.entries)
      entry.key as String: _digest(utf8.encode(entry.value as String)),
  };
}

List<String> _runnerLines(String text) {
  final lines = text.split('\n');
  if (lines.last.isEmpty) lines.removeLast();
  return [
    for (final line in lines)
      line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
  ];
}

bool _terminal(Map<String, Object?> row) =>
    const {'pass', 'fail', 'unavailable', 'timeout'}.contains(row['status']);
void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

String _digest(List<int> bytes) => sha256.convert(bytes).toString();
String _now() => DateTime.now().toUtc().toIso8601String();
