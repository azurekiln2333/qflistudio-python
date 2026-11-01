/// App-owned debugger acceptance through the production shared session API.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_python/python_debugger.dart';
import 'package:qfli_python/python_runner.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

const pythonDebuggerAuditReportName = 'qfli-python-debugger-audit.json';

const _steps = 'def add(a):\n'
    '    b = a + 1\n'
    '    return b\n'
    'value = 3\n'
    'result = add(value)\n'
    'print(result)\n'
    'with open("marker.txt", "w") as file:\n'
    '    file.write("done")\n';
const _helper = 'def answer(a):\n    b = a + 1\n    return b\n';
const _inspection = 'count = 0\n'
    'class Box:\n'
    '    def __repr__(self):\n'
    '        global count\n'
    '        count += 1\n'
    '        return "bad"\n'
    'box = Box()\n'
    'data = [box, "中文", [1, 2, 3, 4, 5]]\n'
    'print(count)\n'
    'raise ValueError("actual")\n';
const _recovery = 'import sys\n'
    'print("QFLI_DEBUG_RECOVERY")\n'
    'sys.stderr.write("QFLI_RECOVERY_STDERR\\n")\n';

/// Alternate audit entry; normal lib/main.dart is never changed.
void startPythonDebuggerAudit({
  required String suiteSha256,
  required Map<String, String> assetDigests,
  required Map<String, Object?> buildEvidence,
}) {
  WidgetsFlutterBinding.ensureInitialized();
  final status = ValueNotifier('Python debugger acceptance is running…');
  runApp(Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: ValueListenableBuilder<String>(
      valueListenable: status,
      builder: (_, value, _) => Text(value),
    )),
  ));
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      final storage = await AppPaths.storageDirectory()
          .timeout(const Duration(seconds: 20));
      if (storage == null) throw StateError('No writable AppPaths storage');
      final report = await runPythonDebuggerAudit(
        storage: Directory(storage),
        suiteSha256: suiteSha256,
        assetDigests: assetDigests,
        buildEvidence: buildEvidence,
        onProgress: (stage) {
          status.value = 'Python debugger acceptance: $stage';
          debugPrint('QFLI_PYTHON_DEBUGGER_STAGE $stage');
        },
      );
      final summary = <String, Object?>{
        for (final name in ['ok', 'hostGatePassed', 'deviceGatePassed',
          'passed', 'failed', 'unavailable', 'reportFile', 'cleanupConfirmed'])
          name: report[name],
        'reportSha256': _digest(await File(report['reportFile']! as String).readAsBytes()),
      };
      status.value = const JsonEncoder.withIndent('  ').convert(summary);
      debugPrint('QFLI_PYTHON_DEBUGGER_AUDIT ${jsonEncode(summary)}');
    } catch (error, stack) {
      final failure = {'ok': false, 'deviceGatePassed': false,
        'error': '$error', 'stack': '$stack'};
      status.value = jsonEncode(failure);
      debugPrint('QFLI_PYTHON_DEBUGGER_AUDIT ${jsonEncode(failure)}');
    }
  });
}

/// Providers may be injected to test failure/timeout bookkeeping. Such runs can
/// never satisfy either runtime gate. Only the default production debugger and
/// runner, actual OHOS, completed cases and actual cleanup satisfy deviceGate.
/// Build inputs still need the separate signed-HAP/native-SO binding check.
Future<Map<String, Object?>> runPythonDebuggerAudit({
  required Directory storage,
  required String suiteSha256,
  required Map<String, String> assetDigests,
  required Map<String, Object?> buildEvidence,
  StudioDebugger? debugger,
  PythonProgramRunner? runner,
  AssetBundle? assets,
  Duration operationTimeout = const Duration(seconds: 15),
  Duration settleTimeout = const Duration(seconds: 15),
  void Function(String stage)? onProgress,
}) async {
  await storage.create(recursive: true);
  final file = File(p.join(storage.path, pythonDebuggerAuditReportName));
  final journal = File('${file.path}l');
  await journal.writeAsString('', flush: true);
  final work = await storage.createTemp('qfli_python_debugger_audit_');
  final project = await Directory(p.join(work.path, '调试 project')).create();
  final provider = debugger ?? const PythonDebugger();
  final execution = runner ?? const PythonProgramRunner();
  final bundle = assets ?? rootBundle;
  final tracker = _Pending(operationTimeout, settleTimeout);
  final cases = <Map<String, Object?>>[];
  final sessions = <_ObservedSession>[];
  final snapshots = <Map<String, Object?>>[];
  final fixtureDigests = <String, String>{};
  final providersOverridden = debugger != null || runner != null || assets != null;
  final report = <String, Object?>{
    'schemaVersion': 1,
    'kind': 'python-debugger-acceptance',
    'expectedBundleName': 'com.azurekiln.qfli.pyflow',
    'expectedOhosPullPath': '/data/app/el2/100/base/com.azurekiln.qfli.pyflow/files/$pythonDebuggerAuditReportName',
    'startedAtUtc': _now(),
    'operatingSystem': Platform.operatingSystem,
    'operatingSystemVersion': Platform.operatingSystemVersion,
    'dartVersion': Platform.version,
    'suiteSha256': suiteSha256,
    'declaredBuildInputs': buildEvidence,
    'requiresIndependentSignedHapBinding': true,
    'providersOverridden': providersOverridden,
    'debugTransport': 'production PythonDebugger packaged C ABI (FFI)',
    'recoveryTransport': 'production PythonProgramRunner automatic transport',
    'debugOutputComparison': 'exact retained stdout/stderr strings',
    'runnerOutputComparison': 'line streams; final LF not distinguishable',
    'reportFile': file.path,
    'journalFile': journal.path,
    'workDirectory': work.path,
    'fixtureSourceDigests': fixtureDigests,
    'cases': cases,
    'snapshots': snapshots,
    'ok': false,
    'hostGatePassed': false,
    'deviceGatePassed': false,
    'status': 'running',
  };
  var writes = Future<void>.value();
  bool journalOpen = true;
  // Once final evidence is frozen a late launch may still complete its actual
  // cleanup, but it must not mutate the already-returned report snapshots.
  bool evidenceFrozen = false;
  void append(Map<String, Object?> event) {
    if (!journalOpen) return;
    final text = '${jsonEncode({'atUtc': _now(), ...event})}\n';
    writes = writes.then((_) async {
      await journal.writeAsString(text, mode: FileMode.append, flush: true);
    });
  }
  Future<void> persist(String stage) async {
    report['stage'] = stage;
    report['updatedAtUtc'] = _now();
    report['passed'] = cases.where((c) => c['status'] == 'pass').length;
    report['failed'] = cases.where((c) => c['status'] == 'fail' || c['status'] == 'timeout').length;
    report['unavailable'] = cases.where((c) => c['status'] == 'unavailable').length;
    append({'stage': stage, 'caseResults': cases});
    await writes;
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(report), flush: true);
    onProgress?.call(stage);
  }

  Future<File> source(String name, String text) async {
    final entry = File(p.join(project.path, name));
    await entry.parent.create(recursive: true);
    await entry.writeAsString(text, flush: true);
    fixtureDigests[name.replaceAll('\\', '/')] = _digest(utf8.encode(text));
    return entry;
  }

  Future<_ObservedSession> launch(File entry, {
    bool entryPause = true,
    List<DebugBreakpoint> breakpoints = const [],
    List<CodeDocumentSnapshot> documents = const [],
  }) async {
    final pending = provider.launch(DebugLaunchRequest(
      projectPath: project.path,
      entryFilePath: entry.path,
      language: 'python',
      documents: documents,
      stopOnEntry: entryPause,
      breakpoints: breakpoints,
    )).then((session) {
      final observed = _ObservedSession(session, tracker, (snapshot) {
        if (evidenceFrozen) return;
        final record = _snapshot(snapshot);
        snapshots.add(record);
        append({'snapshot': record});
      });
      sessions.add(observed);
      if (tracker.closing) observed.requestDispose();
      if (evidenceFrozen) unawaited(observed.closeObservation());
      return observed;
    });
    return tracker.wait(pending, 'debug launch ${p.basename(entry.path)}');
  }

  Future<Map<String, Object?>> normalRun(File entry) async {
    ProgramRunResult? handle;
    var cancelRequested = false;
    Future<void> cancel() async {
      cancelRequested = true;
      await handle?.cancel?.call();
    }
    tracker.cancellations.add(cancel);
    final label = p.basename(entry.path);
    final pending = () async {
      handle = await execution.run(projectPath: project.path, entryFile: entry.path);
      if (handle == null) throw StateError('Normal runner declined recovery source');
      // Observe both drains before awaiting the native exit. A stream that
      // fails early must not become an unhandled zone error while the worker
      // runs, and both streams stay in cleanup evidence.
      final output = tracker.observe(
        handle!.stdout.toList(), 'runner $label stdout drain');
      final errors = tracker.observe(
        handle!.stderr.toList(), 'runner $label stderr drain');
      final actualExit = handle!.exitCode;
      tracker.observe(actualExit.then((_) {}), 'runner $label actual exit');
      if (cancelRequested || tracker.closing) {
        tracker.background(cancel(), 'late runner cancellation');
      }
      final exitCode = await actualExit;
      return {'exitCode': exitCode, 'stdout': await output, 'stderr': await errors};
    }();
    return tracker.wait(pending, 'normal runner $label');
  }

  Future<void> recovery(Map<String, Object?> record) async {
    final entry = await source('recovery.py', _recovery);
    final result = await normalRun(entry);
    record['normalRecovery'] = result;
    _require(result['exitCode'] == 0 &&
        listEquals(result['stdout']! as List<String>, ['QFLI_DEBUG_RECOVERY']) &&
        listEquals(result['stderr']! as List<String>, ['QFLI_RECOVERY_STDERR']),
      'Normal runner did not recover with separate exact streams: $result');
  }

  final scenarios = <(String, Future<void> Function(Map<String, Object?>))>[
    ('entry-steps-breakpoints-and-stale-token', (record) async {
      final entry = await source('main.py', _steps);
      final marker = File(p.join(project.path, 'marker.txt'));
      final session = await launch(entry, breakpoints: [DebugBreakpoint(filePath: entry.path, line: 7)]);
      var paused = await session.pause();
      _at(paused, entry, 1);
      _require(!marker.existsSync(), 'Entry pause occurred after the file side effect');
      await session.command(DebugCommand.stepOver, paused);
      paused = await session.pause(after: paused.pauseToken!.generation);
      _at(paused, entry, 4);
      await session.command(DebugCommand.stepOver, paused);
      paused = await session.pause(after: paused.pauseToken!.generation);
      _at(paused, entry, 5);
      final old = paused.pauseToken!;
      await session.command(DebugCommand.stepInto, paused);
      paused = await session.pause(after: old.generation);
      _at(paused, entry, 2);
      _require(paused.frames.first.name == 'add' && paused.frames.length == 2,
        'Step Into did not expose the actual callee and caller stack');
      _local(paused, 'a', '3');
      _require(_variables(paused)['b']?.type == 'unbound', 'Unassigned real local b is not unbound');
      final beforeReject = paused.revision;
      await _rejects(tracker, () => session.session.command(DebugCommand.resume, pauseToken: old), 'stale pause token');
      _require(session.session.snapshot.revision == beforeReject &&
        session.session.snapshot.pauseToken == paused.pauseToken,
        'Rejected stale command changed current execution');
      record['staleTokenRejected'] = true;
      final busy = await tracker.wait(execution.checkSource(
        projectPath: project.path, entryFile: entry.path, source: 'print(42)\n'), 'paused VM busy check');
      _require(!busy.success && busy.unavailableReason != null,
        'Paused debug session did not retain the shared runtime lease');
      record['pausedRuntimeLeaseRetained'] = true;
      await session.command(DebugCommand.stepOver, paused);
      paused = await session.pause(after: paused.pauseToken!.generation);
      _at(paused, entry, 3);
      _local(paused, 'b', '4');
      await session.command(DebugCommand.stepOut, paused);
      paused = await session.pause(after: paused.pauseToken!.generation);
      _at(paused, entry, 6);
      _local(paused, 'result', '4');
      await session.command(DebugCommand.resume, paused);
      paused = await session.pause(after: paused.pauseToken!.generation);
      _at(paused, entry, 7);
      _require(paused.breakpoints.single.status == DebugBreakpointStatus.verified &&
        paused.breakpoints.single.actualLocation?.line == 7,
        'Second breakpoint was not confirmed by actual execution');
      _require(!marker.existsSync() && paused.stdout.isEmpty,
        'Breakpoint passed the file effect or exit-only output appeared early');
      final replaced = await tracker.wait(session.session.setBreakpoints([
        DebugBreakpoint(filePath: entry.path, line: 1000)]), 'replace breakpoint');
      _require(replaced.single.status == DebugBreakpointStatus.pending,
        'Non-executed line was falsely verified');
      await tracker.wait(session.session.setBreakpoints([]), 'remove breakpoints');
      await session.command(DebugCommand.resume, paused);
      await session.finished(0, stdout: '4\n');
      _require(marker.readAsStringSync() == 'done', 'Continued program did not perform its real side effect');
      await session.dispose();
      await marker.delete();
      final normal = await normalRun(entry);
      record['sameProgramWithoutDebugger'] = normal;
      _require(normal['exitCode'] == 0 &&
        listEquals(normal['stdout']! as List<String>, ['4']) &&
        (normal['stderr']! as List<String>).isEmpty &&
        marker.readAsStringSync() == 'done',
        'Nondebug execution differs from the debugged program');
      await recovery(record);
    }),
    ('unicode-import-stack-and-locals', (record) async {
      final helper = await source('子目录/helper.py', _helper);
      final entry = await source('子目录/main.py', 'import helper\nprint(helper.answer(8))\n');
      final session = await launch(entry, entryPause: false,
        breakpoints: [DebugBreakpoint(filePath: helper.path, line: 3)]);
      final paused = await session.pause();
      _at(paused, helper, 3);
      _require(paused.frames.length >= 2 && paused.frames.first.name == 'answer',
        'Imported function stack is missing');
      _local(paused, 'a', '8');
      _local(paused, 'b', '9');
      _require(paused.breakpoints.single.status == DebugBreakpointStatus.verified,
        'Unicode imported breakpoint was not verified');
      await session.command(DebugCommand.resume, paused);
      await session.finished(0, stdout: '9\n');
      await session.dispose();
      await recovery(record);
    }),
    ('stop-while-paused', (record) async {
      final entry = await source('paused_stop.py', 'while True:\n    pass\n');
      final session = await launch(entry);
      await session.pause();
      await tracker.wait(session.session.stop(), 'Stop paused');
      await session.finished(130);
      await session.dispose();
      await recovery(record);
    }),
    ('stop-while-running', (record) async {
      final entry = await source('running_stop.py', 'while True: pass\n');
      final session = await launch(entry, entryPause: false);
      await session.running();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      _require(!session.session.snapshot.isTerminal, 'Infinite loop exited before Stop');
      await tracker.wait(session.session.stop(), 'Stop running');
      await session.finished(130);
      await session.dispose();
      await recovery(record);
    }),
    ('dispose-paused-session', (record) async {
      final entry = await source('disposed.py', 'while True:\n    pass\n');
      final session = await launch(entry);
      await session.pause();
      await session.dispose();
      await session.finished(130);
      _require(session.updatesClosed, 'Dispose completed without closing updates');
      await recovery(record);
    }),
    ('runtime-error-safe-bounded-inspection', (record) async {
      final entry = await source('inspection.py', _inspection);
      final session = await launch(entry, entryPause: false,
        breakpoints: [DebugBreakpoint(filePath: entry.path, line: 9)]);
      final paused = await session.pause();
      _at(paused, entry, 9);
      _local(paused, 'count', '0');
      final locals = _variables(paused);
      _require(locals['box']?.type == 'Box' && locals['box']?.unavailableReason != null,
        'Custom object was not reported as inspection unavailable');
      final data = locals['data']!;
      _require(data.children.length == 3 && data.children[1].value == '中文' &&
        data.children[2].children.length == 4 && data.children[2].truncated,
        'Real Unicode/container values or inspection bounds differ');
      await session.command(DebugCommand.resume, paused);
      await session.finished(1, stdout: '0\n', stderrContains: 'ValueError: actual',
        expectedPhase: DebugPhase.failed);
      _require(session.session.snapshot.phase == DebugPhase.failed,
        'Actual runtime exception was not exposed as failed');
      await session.dispose();
      await recovery(record);
    }),
    ('unsaved-document-rejected-before-side-effect', (record) async {
      final entry = await source('unsaved.py', 'open("unsaved-effect.txt", "w").write("bad")\n');
      await _rejects(tracker, () async {
        final unexpected = await launch(entry, documents: [CodeDocumentSnapshot(
          path: entry.path, text: 'print("unsaved")\n', revision: 1)]);
        await unexpected.dispose();
      }, 'unsupported unsaved document');
      _require(!File(p.join(project.path, 'unsaved-effect.txt')).existsSync(),
        'Rejected snapshot silently ran saved disk source');
      await recovery(record);
    }),
  ];

  bool prerequisites = false;
  Object? fatal;
  try {
    await persist('preflight');
    _require(RegExp(r'^[a-f0-9]{64}$').hasMatch(suiteSha256) &&
      buildEvidence['suiteSha256'] == suiteSha256,
      'Missing or mismatched declared audit suite identity');
    _require(provider.supportsLanguage('python'), 'Provider does not support Python');
    final capabilities = provider.capabilities;
    _require(capabilities.breakpointUpdate == DebugBreakpointUpdate.live &&
      capabilities.outputDelivery == DebugOutputDelivery.exitOnly &&
      capabilities.supportsStepInto && capabilities.supportsStepOver &&
      capabilities.supportsStepOut && capabilities.supportsStopOnEntry &&
      capabilities.supportsStackFrames && capabilities.supportsVariables &&
      !capabilities.supportsPause && !capabilities.supportsDocumentSnapshots,
      'Production Python debugger capabilities differ from this suite');
    final runtime = await tracker.wait(execution.runtimeInfo(), 'runtime probe');
    report['runtime'] = {'available': runtime.available, 'version': runtime.version,
      'detail': runtime.detail, 'transport': runtime.transport,
      'supportsCancellation': runtime.supportsCancellation};
    _require(runtime.available && runtime.supportsCancellation,
      'Embedded runtime unavailable or lacks Stop: ${runtime.detail}');
    if (Platform.operatingSystem == 'ohos') {
      _require(runtime.transport == 'methodChannel', 'OHOS recovery must use the product native channel');
    }
    _require(assetDigests.containsKey('assets/python_stdlib/manifest.json'),
      'Missing bundled-module manifest identity');
    final verified = <String, String>{};
    for (final entry in assetDigests.entries) {
      _require(entry.key.startsWith('assets/python_stdlib/') &&
        !entry.key.split('/').contains('..'), 'Unexpected bundled asset path');
      final data = await tracker.wait(bundle.load(entry.key), 'asset ${entry.key}');
      final actual = _digest(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      _require(actual == entry.value, 'Packaged asset hash mismatch: ${entry.key}');
      verified[entry.key] = actual;
    }
    report['verifiedPackagedAssets'] = verified;
    prerequisites = true;
    for (final (name, body) in scenarios) {
      final record = <String, Object?>{'name': name, 'status': 'running', 'startedAtUtc': _now()};
      cases.add(record);
      append({'case': record});
      await persist(name);
      try {
        await body(record);
        _require(sessions.every((session) => session.errors.isEmpty),
          'Session snapshot contract failed: ${sessions.expand((s) => s.errors).toList()}');
        record['status'] = 'pass';
      } catch (error, stack) {
        record['status'] = error is TimeoutException ? 'timeout' : 'fail';
        record['error'] = '$error';
        record['stack'] = '$stack';
        fatal = error;
      } finally {
        record['finishedAtUtc'] = _now();
        await persist(name);
      }
      if (fatal != null) break;
    }
  } catch (error, stack) {
    fatal = error;
    report['error'] = '$error';
    report['stack'] = '$stack';
  } finally {
    tracker.closing = true;
    for (final session in sessions) { session.requestDispose(); }
    for (final cancel in tracker.cancellations) {
      tracker.background(cancel(), 'runner cleanup cancellation');
    }
    await tracker.settle();
    // Bound and observe final stream cancellation before freezing evidence. A
    // stalled cancellation is cleanup evidence, not a successful close.
    await Future.wait([
      for (final session in sessions) session.closeObservation(),
    ]);
    await tracker.settle();
    final existing = cases.map((record) => record['name']).toSet();
    for (final (name, _) in scenarios) {
      if (!existing.contains(name)) cases.add({'name': name,
        'status': 'unavailable', 'error': prerequisites
          ? 'Not started after earlier case failure or unsettled execution'
          : 'Preflight failed; no debug program submitted'});
    }
    report['sessions'] = sessions.map((session) => session.summary()).toList();
    report['pendingOperations'] = tracker.pendingLabels;
    report['cleanupErrors'] = <String>[
      ...tracker.errors,
      ...sessions.expand((session) => session.errors),
    ];
    final cleanup = tracker.pendingLabels.isEmpty && tracker.errors.isEmpty &&
      sessions.every((session) => session.disposed && session.doneObserved &&
        session.updatesClosed && session.errors.isEmpty);
    report['cleanupConfirmed'] = cleanup;
    report['workDirectoryRemoved'] = false;
    if (cleanup) {
      try {
        await work.delete(recursive: true);
        report['workDirectoryRemoved'] = true;
      } catch (error) { report['directoryCleanupError'] = '$error'; }
    }
    final ok = fatal == null && prerequisites && cleanup &&
      report['workDirectoryRemoved'] == true &&
      cases.length == scenarios.length && cases.every((record) => record['status'] == 'pass');
    report['ok'] = ok;
    report['hostGatePassed'] = ok && !providersOverridden && Platform.operatingSystem != 'ohos';
    report['deviceGatePassed'] = ok && !providersOverridden &&
      Platform.operatingSystem == 'ohos' && buildEvidence['nativeLibrary'] is Map;
    report['status'] = ok ? 'passed' : 'failed';
    report['finishedAtUtc'] = _now();
    evidenceFrozen = true;
    await persist('finished');
    journalOpen = false;
  }
  return report;
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

/// Bound the rejection assertion with the shared operation deadline. A stalled
/// operation must not block the scenario past its finite deadlines; the
/// underlying future stays observed, so cleanup is not accepted and the work
/// directory is retained until actual settlement.
Future<void> _rejects(
  _Pending tracker,
  Future<void> Function() operation,
  String label,
) async {
  Object? rejected;
  try {
    await tracker.wait(operation(), '$label rejection');
  } on TimeoutException {
    rethrow;
  } catch (error) {
    rejected = error;
  }
  _require(rejected != null, 'Expected rejection: $label');
}

void _at(DebugSnapshot snapshot, File file, int line) {
  _require(snapshot.frames.isNotEmpty, 'Paused snapshot has no real stack');
  final actual = snapshot.frames.first.location;
  _require(actual != null && p.equals(actual.filePath, file.resolveSymbolicLinksSync()) &&
    actual.line == line && actual.column == null,
    'Wrong real line location: ${actual?.filePath}:${actual?.line}; expected ${file.path}:$line');
}

Map<String, DebugVariable> _variables(DebugSnapshot snapshot) => {
  for (final variable in snapshot.frames.first.locals) variable.name: variable,
};

void _local(DebugSnapshot snapshot, String name, String expected) {
  _require(snapshot.frames.first.localsUnavailableReason == null &&
    _variables(snapshot)[name]?.value == expected,
    'Real local $name differs from $expected');
}

Map<String, Object?> _snapshot(DebugSnapshot snapshot) => {
  'sessionId': snapshot.sessionId, 'revision': snapshot.revision,
  'phase': snapshot.phase.name,
  'pauseGeneration': snapshot.pauseToken?.generation,
  'frames': [for (final frame in snapshot.frames) {
    'id': frame.id, 'threadId': frame.threadId, 'name': frame.name,
    'filePath': frame.location?.filePath, 'line': frame.location?.line,
    'localsUnavailableReason': frame.localsUnavailableReason,
    'localsTruncated': frame.localsTruncated,
    'locals': frame.locals.map(_variable).toList(),
  }],
  'breakpoints': [for (final point in snapshot.breakpoints) {
    'filePath': point.requested.filePath, 'line': point.requested.line,
    'status': point.status.name, 'actualLine': point.actualLocation?.line,
    'reason': point.reason,
  }],
  'stdout': snapshot.stdout, 'stderr': snapshot.stderr, 'console': snapshot.console,
  'stdoutTruncated': snapshot.stdoutTruncated, 'stderrTruncated': snapshot.stderrTruncated,
  'consoleTruncated': snapshot.consoleTruncated, 'framesTruncated': snapshot.framesTruncated,
  'message': snapshot.message, 'exitCode': snapshot.exitCode,
};

Map<String, Object?> _variable(DebugVariable variable) => {
  'name': variable.name, 'type': variable.type, 'value': variable.value,
  'unavailableReason': variable.unavailableReason, 'truncated': variable.truncated,
  'children': variable.children.map(_variable).toList(),
};

class _ObservedSession {
  _ObservedSession(this.session, this.tracker, this.record) {
    tracker.observe(session.done.then((_) => doneObserved = true), 'session ${session.id} actual exit');
    subscription = session.updates.listen(observe,
      onError: (Object error) => errors.add('Update stream error: $error'),
      onDone: () => updatesClosed = true);
    observe(session.snapshot);
  }
  final DebugSession session;
  final _Pending tracker;
  final void Function(DebugSnapshot) record;
  final errors = <String>[];
  late StreamSubscription<DebugSnapshot> subscription;
  int revision = -1, count = 0;
  String? last;
  bool doneObserved = false, disposed = false, updatesClosed = false;
  Future<void>? disposing;
  Future<void>? _cancelObservation;

  void observe(DebugSnapshot snapshot) {
    final encoded = jsonEncode(_snapshot(snapshot));
    // Subscribe-then-read can observe the getter before an already queued event.
    if (snapshot.revision == revision && encoded == last) return;
    if (snapshot.sessionId != session.id || snapshot.revision <= revision) {
      errors.add('Session identity or snapshot revision changed out of order');
    }
    revision = snapshot.revision;
    last = encoded;
    if (snapshot.phase == DebugPhase.paused &&
      (snapshot.pauseToken?.sessionId != session.id || snapshot.frames.isEmpty)) {
      errors.add('Paused snapshot lacks a matching token and real frames');
    }
    if (snapshot.phase != DebugPhase.paused && (snapshot.pauseToken != null || snapshot.frames.isNotEmpty)) {
      errors.add('Consumed pause retained token/frames');
    }
    if (count++ < 256) { record(snapshot); }
    else if (count == 257) { errors.add('Audit snapshot limit exceeded'); }
  }

  Future<DebugSnapshot> pause({int after = 0}) async {
    final deadline = Stopwatch()..start();
    while (deadline.elapsed < tracker.deadline) {
      final current = session.snapshot;
      if (current.phase == DebugPhase.paused && current.pauseToken!.generation > after) return current;
      if (current.isTerminal) throw StateError('Terminated before pause: ${current.message} ${current.stderr}');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException('No real pause for session ${session.id}', tracker.deadline);
  }

  Future<void> running() async {
    final deadline = Stopwatch()..start();
    while (deadline.elapsed < tracker.deadline) {
      final current = session.snapshot;
      if (current.phase == DebugPhase.running) return;
      if (current.isTerminal || current.phase == DebugPhase.paused) {
        throw StateError('Expected running loop, got ${current.phase}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException('No running state for session ${session.id}', tracker.deadline);
  }

  Future<void> command(DebugCommand command, DebugSnapshot paused) =>
    tracker.wait(session.command(command, pauseToken: paused.pauseToken), 'dispatch ${command.name}');

  Future<void> finished(int exitCode, {
    String? stdout,
    String? stderrContains,
    DebugPhase expectedPhase = DebugPhase.terminated,
  }) async {
    await tracker.wait(session.done, 'actual debug exit');
    final snapshot = session.snapshot;
    _require(snapshot.phase == expectedPhase,
      'Unexpected debug phase ${snapshot.phase.name}; expected ${expectedPhase.name} '
      '(${snapshot.exitCode} ${snapshot.message})');
    _require(snapshot.isTerminal && snapshot.exitCode == exitCode,
      'Wrong actual debug exit: ${snapshot.phase} ${snapshot.exitCode} ${snapshot.message}');
    _require(stdout == null || snapshot.stdout == stdout, 'Exact debugger stdout mismatch: ${snapshot.stdout}');
    _require(stderrContains == null || snapshot.stderr.contains(stderrContains), 'Expected real exception missing: ${snapshot.stderr}');
    if (exitCode == 0) _require(snapshot.stderr.isEmpty, 'Unexpected debugger stderr: ${snapshot.stderr}');
    _require(!snapshot.stdoutTruncated && !snapshot.stderrTruncated && !snapshot.framesTruncated,
      'Unexpected debugger truncation in finite acceptance programs');
  }

  void requestDispose() {
    if (disposing != null) return;
    try {
      disposing = tracker.observe(session.dispose().then<void>((_) {
        disposed = true;
      }, onError: (Object error, StackTrace stack) {
        tracker.errors.add('Dispose ${session.id}: $error');
        Error.throwWithStackTrace(error, stack);
      }), 'dispose ${session.id}');
    } catch (error) { tracker.errors.add('Dispose ${session.id}: $error'); }
  }

  Future<void> dispose() {
    requestDispose();
    return tracker.wait(disposing ?? Future<void>.error(StateError('Dispose did not start')), 'dispose actual debug worker');
  }

  Future<void> closeObservation() => _cancelObservation ??= _closeObservation();

  Future<void> _closeObservation() async {
    try {
      final cancel = subscription.cancel().then<void>((_) {
        updatesClosed = true;
      }, onError: (Object error) {
        errors.add('Update stream cancellation error: $error');
      });
      await tracker.wait(cancel, 'close observation ${session.id}');
    } on TimeoutException catch (error) {
      errors.add('Update stream cancellation did not settle: $error');
    } catch (error) {
      errors.add('Update stream cancellation failed: $error');
    }
  }

  Map<String, Object?> summary() => {'id': session.id, 'doneObserved': doneObserved,
    'disposed': disposed, 'updatesClosed': updatesClosed, 'snapshotCount': count,
    'contractErrors': errors, 'finalSnapshot': _snapshot(session.snapshot)};
}

class _Pending {
  _Pending(this.deadline, this.settleDeadline);
  final Duration deadline, settleDeadline;
  final _pending = <Future<void>, String>{};
  final errors = <String>[];
  final cancellations = <Future<void> Function()>[];
  bool closing = false;
  List<String> get pendingLabels => _pending.values.toList();

  Future<T> observe<T>(Future<T> operation, String label) {
    final completion = Completer<void>();
    _pending[completion.future] = label;
    operation.then<void>((_) {
      _pending.remove(completion.future);
      completion.complete();
    }, onError: (Object error, StackTrace stack) {
      _pending.remove(completion.future);
      completion.complete();
    });
    return operation;
  }
  Future<T> wait<T>(Future<T> operation, String label) =>
    observe(operation, label).timeout(deadline, onTimeout: () {
      throw TimeoutException('$label exceeded deadline; actual operation remains observed', deadline);
    });
  void background(Future<void> operation, String label) {
    observe(operation, label).catchError((Object error) { errors.add('$label: $error'); });
  }
  Future<void> settle() async {
    final timer = Stopwatch()..start();
    while (_pending.isNotEmpty && timer.elapsed < settleDeadline) {
      final remaining = settleDeadline - timer.elapsed;
      try { await Future.wait(_pending.keys.toList()).timeout(remaining); }
      on TimeoutException { break; }
    }
  }
}

String _now() => DateTime.now().toUtc().toIso8601String();
String _digest(List<int> bytes) => sha256.convert(bytes).toString();
