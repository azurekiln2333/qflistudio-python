import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_python/python_debugger.dart';
import 'package:qfli_python/python_runner.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

import '../tool/python_debugger_ohos_audit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory storage;
  setUp(() {
    storage = Directory.systemTemp.createTempSync('python_debugger_audit_test_');
  });
  tearDown(() {
    if (storage.existsSync()) storage.deleteSync(recursive: true);
  });
  final suiteHash = sha256.convert(utf8.encode('test audit identity')).toString();
  final assetBytes = utf8.encode('{"audit":true}');
  final assetDigests = {'assets/python_stdlib/manifest.json': sha256.convert(assetBytes).toString()};

  Future<Map<String, Object?>> audit(StudioDebugger debugger, {
    PythonProgramRunner? runner,
    String? suite,
    AssetBundle? assets,
  }) => runPythonDebuggerAudit(
    storage: storage,
    suiteSha256: suite ?? suiteHash,
    assetDigests: assetDigests,
    buildEvidence: {'suiteSha256': suiteHash},
    debugger: debugger,
    runner: runner ?? _ProbeRunner(),
    assets: assets ?? _AuditAssets(assetBytes),
    operationTimeout: const Duration(milliseconds: 55),
    settleTimeout: const Duration(milliseconds: 25),
  );

  test('unavailable runtime journals all cases without submitting debug code', () async {
    final debugger = _ControlledDebugger();
    final report = await audit(debugger, runner: _ProbeRunner(available: false));
    expect(debugger.launches, 0);
    expect(report['ok'], isFalse);
    expect(report['hostGatePassed'], isFalse);
    expect(report['deviceGatePassed'], isFalse);
    expect(report['unavailable'], 7);
    expect(report['cleanupConfirmed'], isTrue);
    expect(report['workDirectoryRemoved'], isTrue);
    final durable = jsonDecode(File(report['reportFile']! as String).readAsStringSync()) as Map;
    expect(durable['error'], contains('deliberately unavailable'));
    expect(File(report['journalFile']! as String).readAsLinesSync(), isNotEmpty);
  });

  test('changed suite identity is rejected before runtime probing', () async {
    final debugger = _ControlledDebugger();
    final runner = _ProbeRunner();
    final report = await audit(debugger, runner: runner, suite: 'bad hash');
    expect(report['error'], contains('suite identity'));
    expect(runner.probes, 0);
    expect(debugger.launches, 0);
  });

  test('packaged asset drift is rejected before launching a worker', () async {
    final debugger = _ControlledDebugger();
    final report = await audit(debugger, assets: _AuditAssets(utf8.encode('changed')));
    expect(report['error'], contains('Packaged asset hash mismatch'));
    expect(debugger.launches, 0);
    expect(report['deviceGatePassed'], isFalse);
  });

  test('launch arriving after deadline is disposed and active files stay retained', () async {
    final debugger = _ControlledDebugger();
    final report = await audit(debugger);
    expect(debugger.launches, 1);
    expect(report['cleanupConfirmed'], isFalse);
    expect(report['pendingOperations'], isNotEmpty);
    expect((report['cases']! as List).first['status'], 'timeout');
    final work = Directory(report['workDirectory']! as String);
    expect(work.existsSync(), isTrue);
    final reportFile = File(report['reportFile']! as String);
    final durable = reportFile.readAsStringSync();
    final snapshotsBefore = jsonEncode(report['snapshots']);
    final late = _Session(debugger.request!, settleOnDispose: true);
    debugger.result.complete(late);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(late.disposeCalls, 1);
    expect(late.doneCompleter.isCompleted, isTrue);
    expect(work.existsSync(), isTrue);
    expect(reportFile.readAsStringSync(), durable,
      reason: 'Late cleanup must not rewrite previously returned device evidence');
    expect(jsonEncode(report['snapshots']), snapshotsBefore,
      reason: 'Late cleanup must not mutate the already-returned snapshots');
  });

  test('pending Stop or dispose never releases active project files', () async {
    final debugger = _ControlledDebugger(autoSession: true, settleOnDispose: false);
    final report = await audit(debugger);
    final session = debugger.session!;
    expect(session.commandCalls, 1);
    expect(session.disposeCalls, 1);
    expect(session.doneCompleter.isCompleted, isFalse);
    expect(report['cleanupConfirmed'], isFalse);
    expect(report['workDirectoryRemoved'], isFalse);
    expect(report['pendingOperations'], isNotEmpty);
    expect(report['deviceGatePassed'], isFalse);
    expect(Directory(report['workDirectory']! as String).existsSync(), isTrue);
    await session.complete();
  });

  test('failed pause can clean up only after actual session exit and stream close', () async {
    final debugger = _ControlledDebugger(autoSession: true,
      settleOnDispose: true, paused: false);
    final report = await audit(debugger);
    expect(debugger.session!.doneCompleter.isCompleted, isTrue);
    expect(report['cleanupConfirmed'], isTrue);
    expect(report['workDirectoryRemoved'], isTrue);
    expect(report['ok'], isFalse);
    expect(report['deviceGatePassed'], isFalse);
    final summary = (report['sessions']! as List).single as Map;
    expect(summary['doneObserved'], isTrue);
    expect(summary['updatesClosed'], isTrue);
    expect(summary['disposed'], isTrue);
  });

  test('stale-token rejection is bounded and retains files until settlement', () async {
    final debugger = _ScenarioDebugger(_Fault.staleHang);
    final report = await audit(debugger);
    final first = (report['cases']! as List).first as Map;
    expect(first['status'], 'timeout');
    expect(report['cleanupConfirmed'], isFalse);
    expect(report['workDirectoryRemoved'], isFalse);
    expect(report['pendingOperations'], isNotEmpty);
    expect(report['deviceGatePassed'], isFalse);
    expect(Directory(report['workDirectory']! as String).existsSync(), isTrue);
    expect((debugger.sessions.single as _StepSession).disposeCalls, 1);
  });

  test('failed phase with exit 0 is not accepted as a successful run', () async {
    final debugger = _ScenarioDebugger(_Fault.failedExit0);
    final report = await audit(debugger, runner: _ScriptedRunner());
    final first = (report['cases']! as List).first as Map;
    expect(first['status'], 'fail');
    expect('${first['error']}', contains('Unexpected debug phase failed'));
    expect(report['deviceGatePassed'], isFalse);
  });

  test('early stream error is observed before delayed exit and fails the case', () async {
    final debugger = _ScenarioDebugger(_Fault.earlyDrainError);
    final report = await audit(debugger, runner: _ScriptedRunner(earlyDrain: true));
    final first = (report['cases']! as List).first as Map;
    expect(first['status'], 'fail');
    expect('${first['error']}', contains('stdout'));
    expect(report['deviceGatePassed'], isFalse);
  });

  test('failed phase with exit 130 is not accepted as a cooperative Stop', () async {
    final debugger = _ScenarioDebugger(_Fault.stopFailed130);
    final report = await audit(debugger, runner: _ScriptedRunner());
    final stopCase = (report['cases']! as List).cast<Map>().firstWhere(
      (item) => item['name'] == 'stop-while-paused');
    expect(stopCase['status'], 'fail');
    expect('${stopCase['error']}', contains('Unexpected debug phase failed'));
    expect(report['deviceGatePassed'], isFalse);
  });

  test('stalled update cancellation is bounded and keeps the work directory', () async {
    final debugger = _ControlledDebugger(autoSession: true,
      settleOnDispose: true, paused: false, stalledCancel: true);
    final report = await audit(debugger);
    expect(report['cleanupConfirmed'], isFalse);
    expect(report['workDirectoryRemoved'], isFalse);
    expect(report['pendingOperations'], isNotEmpty);
    expect((report['cleanupErrors']! as List).any(
      (item) => '$item'.contains('cancellation')), isTrue);
    expect(report['deviceGatePassed'], isFalse);
    expect(Directory(report['workDirectory']! as String).existsSync(), isTrue);
  });

  final library = p.absolute('native/build', Platform.operatingSystem,
    Platform.isWindows ? 'qfli_py_ffi.dll' : 'libqfli_py_ffi.so');
  test('production embedded debugger audit leaves OHOS gate separate on host', () async {
    final harness = File('tool/python_debugger_ohos_audit.dart').readAsBytesSync();
    final actualSuite = sha256.convert(harness).toString();
    final digests = <String, String>{};
    for (final file in Directory('assets/python_stdlib').listSync(recursive: true).whereType<File>()) {
      digests[file.path.replaceAll('\\', '/')] = sha256.convert(file.readAsBytesSync()).toString();
    }
    final report = await runPythonDebuggerAudit(
      storage: storage, suiteSha256: actualSuite,
      assetDigests: digests, buildEvidence: {'suiteSha256': actualSuite},
    );
    expect(report['ok'], isTrue, reason: '${report['error']}\n${report['cases']}\n${report['sessions']}');
    expect(report['hostGatePassed'], isTrue);
    expect(report['deviceGatePassed'], isFalse);
    expect(report['providersOverridden'], isFalse);
    expect(report['passed'], 7);
    expect(report['cleanupConfirmed'], isTrue);
    expect(report['pendingOperations'], isEmpty);
    expect(report['verifiedPackagedAssets'], digests);
    final cases = report['cases']! as List;
    expect(cases.every((item) => (item as Map)['normalRecovery'] != null), isTrue);
    expect((report['snapshots']! as List).any((item) => (item as Map)['pauseGeneration'] != null), isTrue);
  }, skip: !(Platform.isWindows || Platform.isLinux) || !File(library).existsSync(),
    timeout: const Timeout(Duration(minutes: 3)));
}

class _AuditAssets extends CachingAssetBundle {
  _AuditAssets(this.bytes);
  final List<int> bytes;
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(Uint8List.fromList(bytes));
}

class _ProbeRunner extends PythonProgramRunner {
  _ProbeRunner({this.available = true});
  final bool available;
  int probes = 0;
  @override
  Future<PythonRuntimeInfo> runtimeInfo() async {
    probes++;
    return PythonRuntimeInfo(available: available,
      detail: available ? 'test double' : 'deliberately unavailable',
      transport: 'ffi', supportsCancellation: available);
  }
}

class _ControlledDebugger implements StudioDebugger {
  _ControlledDebugger({this.autoSession = false,
    this.settleOnDispose = false, this.paused = true, this.stalledCancel = false});
  final bool autoSession, settleOnDispose, paused, stalledCancel;
  final result = Completer<DebugSession>();
  int launches = 0;
  DebugLaunchRequest? request;
  _Session? session;
  @override
  String get displayName => 'audit bookkeeping double';
  @override
  DebugCapabilities get capabilities => const PythonDebugger().capabilities;
  @override
  bool supportsLanguage(String language) => language == 'python';
  @override
  Future<DebugSession> launch(DebugLaunchRequest request) {
    launches++;
    this.request = request;
    if (autoSession) {
      session = _Session(request, settleOnDispose: settleOnDispose, paused: paused,
        stalledCancel: stalledCancel);
      return Future.value(session);
    }
    return result.future;
  }
}

class _Session implements DebugSession {
  _Session(DebugLaunchRequest request, {required this.settleOnDispose,
    bool paused = true, this.stalledCancel = false}) {
    _snapshot = DebugSnapshot(sessionId: id, revision: 1,
      phase: paused ? DebugPhase.paused : DebugPhase.running,
      pauseToken: paused ? DebugPauseToken(sessionId: id, generation: 1) : null,
      frames: paused ? [DebugFrame(id: '1:0', threadId: 'main', name: '<module>',
        location: DebugSourceLocation(filePath: request.entryFilePath, line: 1))] : []);
  }
  final bool settleOnDispose;
  final bool stalledCancel;
  final doneCompleter = Completer<void>();
  final commandCompleter = Completer<void>();
  final updatesController = StreamController<DebugSnapshot>.broadcast();
  late DebugSnapshot _snapshot;
  int disposeCalls = 0, commandCalls = 0;
  @override
  String get id => 'audit-test-session';
  @override
  DebugSnapshot get snapshot => _snapshot;
  @override
  Stream<DebugSnapshot> get updates => stalledCancel
      ? _StalledCancelStream(updatesController.stream)
      : updatesController.stream;
  @override
  Future<void> get done => doneCompleter.future;
  @override
  Future<void> command(DebugCommand command, {DebugPauseToken? pauseToken, String? threadId}) {
    commandCalls++;
    return commandCompleter.future;
  }
  @override
  Future<List<DebugBreakpointResult>> setBreakpoints(List<DebugBreakpoint> breakpoints) async => [];
  @override
  Future<void> stop() => done;
  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (settleOnDispose) await complete();
    await done;
  }
  Future<void> complete() async {
    if (!commandCompleter.isCompleted) commandCompleter.complete();
    if (!doneCompleter.isCompleted) {
      _snapshot = DebugSnapshot(sessionId: id, revision: _snapshot.revision + 1,
        phase: DebugPhase.terminated, exitCode: 130);
      updatesController.add(_snapshot);
      doneCompleter.complete();
    }
    await updatesController.close();
  }
}

/// A broadcast stream whose subscription cancellation never settles, so the
/// audit must bound final observation cleanup instead of hanging after the
/// durable report is written.
class _StalledCancelStream extends Stream<DebugSnapshot> {
  _StalledCancelStream(this._inner);
  final Stream<DebugSnapshot> _inner;
  @override
  bool get isBroadcast => true;
  @override
  StreamSubscription<DebugSnapshot> listen(
    void Function(DebugSnapshot event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _StalledSubscription(_inner.listen(onData,
    onError: onError, onDone: onDone, cancelOnError: cancelOnError));
}

class _StalledSubscription implements StreamSubscription<DebugSnapshot> {
  _StalledSubscription(this._inner);
  final StreamSubscription<DebugSnapshot> _inner;
  @override
  Future<void> cancel() => Completer<void>().future;
  @override
  void onData(void Function(DebugSnapshot data)? handleData) =>
      _inner.onData(handleData);
  @override
  void onError(Function? handleError) => _inner.onError(handleError);
  @override
  void onDone(void Function()? handleDone) => _inner.onDone(handleDone);
  @override
  void pause([Future<void>? resumeSignal]) => _inner.pause(resumeSignal);
  @override
  void resume() => _inner.resume();
  @override
  bool get isPaused => _inner.isPaused;
  @override
  Future<E> asFuture<E>([E? futureValue]) => _inner.asFuture<E>(futureValue);
}

enum _Fault { staleHang, failedExit0, earlyDrainError, stopFailed130 }

/// Routes each audit scenario to a scripted session double. Only the entries
/// reached before the injected fault are implemented.
class _ScenarioDebugger implements StudioDebugger {
  _ScenarioDebugger(this.fault);
  final _Fault fault;
  final sessions = <DebugSession>[];
  int launches = 0;
  @override
  String get displayName => 'audit fault double';
  @override
  DebugCapabilities get capabilities => const PythonDebugger().capabilities;
  @override
  bool supportsLanguage(String language) => language == 'python';
  @override
  Future<DebugSession> launch(DebugLaunchRequest request) async {
    launches++;
    final name = p.basename(request.entryFilePath);
    final parent = p.basename(p.dirname(request.entryFilePath));
    final DebugSession session;
    if (name == 'paused_stop.py') {
      session = _StopFailureSession(request);
    } else if (name == 'main.py' && parent == '子目录') {
      session = _UnicodeSession(request);
    } else if (name == 'main.py') {
      session = _StepSession(request, fault: fault);
    } else {
      throw StateError('Unexpected scripted audit entry: $name');
    }
    sessions.add(session);
    return session;
  }
}

class _StepSession implements DebugSession {
  _StepSession(DebugLaunchRequest request, {required this.fault})
      : _entry = File(request.entryFilePath).resolveSymbolicLinksSync(),
        _marker = p.join(request.projectPath, 'marker.txt'),
        _requested = request.breakpoints {
    _breakpoints = [
      for (final point in _requested)
        DebugBreakpointResult(requested: point,
          status: DebugBreakpointStatus.pending),
    ];
    _pauseAt(1, 1, [_moduleAt(1)]);
  }
  final _Fault fault;
  final String _entry, _marker;
  final List<DebugBreakpoint> _requested;
  final _updates = StreamController<DebugSnapshot>.broadcast();
  final _done = Completer<void>();
  late DebugSnapshot _snapshot;
  int _revision = 0, _generation = 0;
  List<DebugBreakpointResult> _breakpoints = const [];
  int disposeCalls = 0;

  @override
  String get id => 'step-session';
  @override
  DebugSnapshot get snapshot => _snapshot;
  @override
  Stream<DebugSnapshot> get updates => _updates.stream;
  @override
  Future<void> get done => _done.future;

  DebugFrame _moduleAt(int line, {List<DebugVariable> locals = const []}) =>
      DebugFrame(id: '$_generation:0', threadId: 'main', name: '<module>',
        location: DebugSourceLocation(filePath: _entry, line: line),
        locals: locals);

  DebugFrame _addFrame(int line, String b, {bool unbound = false}) =>
      DebugFrame(id: '$_generation:1', threadId: 'main', name: 'add',
        location: DebugSourceLocation(filePath: _entry, line: line),
        locals: [
          DebugVariable(name: 'a', type: 'int', value: '3'),
          DebugVariable(name: 'b', type: unbound ? 'unbound' : 'int',
            value: unbound ? '' : b),
        ]);

  void _pauseAt(int generation, int line, List<DebugFrame> frames,
      {List<DebugBreakpointResult>? breakpoints}) {
    _generation = generation;
    _breakpoints = breakpoints ?? _breakpoints;
    _snapshot = DebugSnapshot(
      sessionId: id, revision: ++_revision, phase: DebugPhase.paused,
      pauseToken: DebugPauseToken(sessionId: id, generation: generation),
      threads: [DebugThread(id: 'main', name: 'Python VM', isPaused: true)],
      frames: frames, breakpoints: _breakpoints);
    _updates.add(_snapshot);
  }

  @override
  Future<void> command(DebugCommand command,
      {DebugPauseToken? pauseToken, String? threadId}) {
    final generation = pauseToken?.generation;
    if (command == DebugCommand.resume && generation == 3) {
      if (fault == _Fault.staleHang) return Completer<void>().future;
      throw StateError('stale pause token rejected');
    }
    if (command == DebugCommand.stepOver && generation == 1) {
      _pauseAt(2, 4, [_moduleAt(4)]);
    } else if (command == DebugCommand.stepOver && generation == 2) {
      _pauseAt(3, 5, [_moduleAt(5)]);
    } else if (command == DebugCommand.stepInto && generation == 3) {
      _pauseAt(4, 2, [_addFrame(2, '', unbound: true), _moduleAt(5)]);
    } else if (command == DebugCommand.stepOver && generation == 4) {
      _pauseAt(5, 3, [_addFrame(3, '4'), _moduleAt(5)]);
    } else if (command == DebugCommand.stepOut && generation == 5) {
      _pauseAt(6, 6, [_moduleAt(6, locals: [
        DebugVariable(name: 'result', type: 'int', value: '4')])]);
    } else if (command == DebugCommand.resume && generation == 6) {
      _pauseAt(7, 7, [_moduleAt(7)], breakpoints: [
        for (final point in _requested)
          DebugBreakpointResult(requested: point,
            status: DebugBreakpointStatus.verified,
            actualLocation: DebugSourceLocation(filePath: _entry, line: 7)),
      ]);
    } else if (command == DebugCommand.resume && generation == 7) {
      File(_marker).writeAsStringSync('done');
      _finish();
    } else {
      throw StateError('Unexpected command ${command.name} at $generation');
    }
    return Future<void>.value();
  }

  void _finish() {
    final failed = fault == _Fault.failedExit0;
    _snapshot = DebugSnapshot(sessionId: id, revision: ++_revision,
      phase: failed ? DebugPhase.failed : DebugPhase.terminated,
      stdout: '4\n', exitCode: 0,
      message: failed ? 'operational debugger failure' : null);
    _updates.add(_snapshot);
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<List<DebugBreakpointResult>> setBreakpoints(
      List<DebugBreakpoint> breakpoints) async {
    _breakpoints = [
      for (final point in breakpoints)
        DebugBreakpointResult(requested: point,
          status: DebugBreakpointStatus.pending),
    ];
    return _breakpoints;
  }

  @override
  Future<void> stop() => done;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (!_done.isCompleted) _done.complete();
    await _done.future;
    if (!_updates.isClosed) await _updates.close();
  }
}

class _UnicodeSession implements DebugSession {
  _UnicodeSession(DebugLaunchRequest request)
      : _helper = File(request.breakpoints.single.filePath)
            .resolveSymbolicLinksSync() {
    _snapshot = DebugSnapshot(
      sessionId: id, revision: ++_revision, phase: DebugPhase.paused,
      pauseToken: DebugPauseToken(sessionId: id, generation: 1),
      threads: [DebugThread(id: 'main', name: 'Python VM', isPaused: true)],
      frames: [
        DebugFrame(id: '1:0', threadId: 'main', name: 'answer',
          location: DebugSourceLocation(filePath: _helper, line: 3),
          locals: [DebugVariable(name: 'a', type: 'int', value: '8'),
            DebugVariable(name: 'b', type: 'int', value: '9')]),
        DebugFrame(id: '1:1', threadId: 'main', name: '<module>',
          location: DebugSourceLocation(filePath: _helper, line: 1)),
      ],
      breakpoints: [DebugBreakpointResult(
        requested: DebugBreakpoint(filePath: _helper, line: 3),
        status: DebugBreakpointStatus.verified,
        actualLocation: DebugSourceLocation(filePath: _helper, line: 3))]);
    _updates.add(_snapshot);
  }
  final String _helper;
  final _updates = StreamController<DebugSnapshot>.broadcast();
  final _done = Completer<void>();
  late DebugSnapshot _snapshot;
  int _revision = 0;
  @override
  String get id => 'unicode-session';
  @override
  DebugSnapshot get snapshot => _snapshot;
  @override
  Stream<DebugSnapshot> get updates => _updates.stream;
  @override
  Future<void> get done => _done.future;
  @override
  Future<void> command(DebugCommand command,
      {DebugPauseToken? pauseToken, String? threadId}) {
    _snapshot = DebugSnapshot(sessionId: id, revision: ++_revision,
      phase: DebugPhase.terminated, exitCode: 0, stdout: '9\n');
    _updates.add(_snapshot);
    if (!_done.isCompleted) _done.complete();
    return Future<void>.value();
  }
  @override
  Future<List<DebugBreakpointResult>> setBreakpoints(
      List<DebugBreakpoint> breakpoints) async => [];
  @override
  Future<void> stop() => done;
  @override
  Future<void> dispose() async {
    if (!_done.isCompleted) _done.complete();
    await _done.future;
    if (!_updates.isClosed) await _updates.close();
  }
}

class _StopFailureSession implements DebugSession {
  _StopFailureSession(DebugLaunchRequest request)
      : _entry = File(request.entryFilePath).resolveSymbolicLinksSync() {
    _snapshot = DebugSnapshot(
      sessionId: id, revision: ++_revision, phase: DebugPhase.paused,
      pauseToken: DebugPauseToken(sessionId: id, generation: 1),
      threads: [DebugThread(id: 'main', name: 'Python VM', isPaused: true)],
      frames: [DebugFrame(id: '1:0', threadId: 'main', name: '<module>',
        location: DebugSourceLocation(filePath: _entry, line: 1))]);
    _updates.add(_snapshot);
  }
  final String _entry;
  final _updates = StreamController<DebugSnapshot>.broadcast();
  final _done = Completer<void>();
  late DebugSnapshot _snapshot;
  int _revision = 0;
  @override
  String get id => 'stop-failure-session';
  @override
  DebugSnapshot get snapshot => _snapshot;
  @override
  Stream<DebugSnapshot> get updates => _updates.stream;
  @override
  Future<void> get done => _done.future;
  @override
  Future<void> command(DebugCommand command,
      {DebugPauseToken? pauseToken, String? threadId}) => Future<void>.value();
  @override
  Future<List<DebugBreakpointResult>> setBreakpoints(
      List<DebugBreakpoint> breakpoints) async => [];
  @override
  Future<void> stop() {
    _snapshot = DebugSnapshot(sessionId: id, revision: ++_revision,
      phase: DebugPhase.failed, exitCode: 130,
      message: 'operational stop failure');
    _updates.add(_snapshot);
    if (!_done.isCompleted) _done.complete();
    return _done.future;
  }
  @override
  Future<void> dispose() async {
    if (!_done.isCompleted) _done.complete();
    await _done.future;
    if (!_updates.isClosed) await _updates.close();
  }
}

/// Deterministic runner: returns declared streams so pass-through scenarios can
/// reach `normalRun`, and can fail a stream before the delayed native exit.
class _ScriptedRunner extends PythonProgramRunner {
  _ScriptedRunner({this.earlyDrain = false});
  final bool earlyDrain;
  @override
  Future<PythonRuntimeInfo> runtimeInfo() async => const PythonRuntimeInfo(
    available: true, detail: 'scripted runner double', transport: 'ffi',
    supportsCancellation: true);
  @override
  Future<PythonSyntaxResult> checkSource({required String projectPath,
      required String entryFile, required String source}) async =>
      const PythonSyntaxResult.unavailable('scripted runner: VM busy');
  @override
  Future<ProgramRunResult?> run({required String projectPath,
      required String entryFile}) async {
    final name = p.basename(entryFile);
    final out = StreamController<String>();
    final err = StreamController<String>();
    final exit = Completer<int>();
    if (earlyDrain && name == 'main.py') {
      scheduleMicrotask(() {
        out.addError(StateError('early stdout drain failure'));
        out.close();
        err.close();
      });
      Future<void>.delayed(const Duration(milliseconds: 20), () => exit.complete(0));
    } else {
      if (name == 'main.py') {
        File(p.join(projectPath, 'marker.txt')).writeAsStringSync('done');
      }
      final recovery = name == 'recovery.py';
      scheduleMicrotask(() {
        if (recovery) {
          out.add('QFLI_DEBUG_RECOVERY');
          err.add('QFLI_RECOVERY_STDERR');
        } else {
          out.add('4');
        }
        out.close();
        err.close();
      });
      exit.complete(0);
    }
    return ProgramRunResult(title: 'python $name', stdout: out.stream,
      stderr: err.stream, exitCode: exit.future);
  }
}
