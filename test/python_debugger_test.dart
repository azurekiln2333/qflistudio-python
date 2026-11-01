import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_python/main.dart';
import 'package:qfli_python/python_debugger.dart';
import 'package:qfli_python/python_debugger_ffi.dart';
import 'package:qfli_python/python_packages.dart';
import 'package:qfli_python/python_runtime_activity.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

class _Packages extends PythonPackageService {
  Completer<void>? preparation;
  @override
  Future<PythonBundlePreparationResult> ensureBundledModules(
    String projectPath,
  ) async {
    await preparation?.future;
    return const PythonBundlePreparationResult(success: true, message: 'ready');
  }
}

class _Backend implements PythonDebugBackend {
  final handle = _Handle();
  int creates = 0;
  @override
  PythonDebugHandle create(String project, String entry, bool stopOnEntry) {
    creates++;
    handle.entry = entry;
    return handle;
  }
}

class _Handle implements PythonDebugHandle {
  final completion = Completer<PythonDebugResult>();
  late String entry;
  final events = <Map<String, Object?>>[];
  int sequence = 0, generation = 0, releases = 0, stops = 0;
  String state = 'created';
  Object? brokenPayload;
  bool rejectBreakpoints = false, exited = false, failRelease = false;
  int rejectedStops = 0;
  bool throwStop = false;
  List<String> files = [];
  List<int> lines = [];

  void event(String next, {String? reason, Map<String, Object?>? extra}) {
    state = next;
    events.add({
      'sequence': ++sequence,
      'kind': 'state',
      'state': state,
      'reason': reason ?? state,
      'pauseGeneration': generation,
      ...?extra,
    });
  }

  void pause({
    int line = 1,
    List<Map<String, Object?>>? variables,
    bool truncated = false,
  }) {
    generation++;
    event(
      'paused',
      reason: 'breakpoint',
      extra: {
        'file': entry,
        'line': line,
        'truncated': truncated,
        'frames': [
          {
            'id': '$generation:0',
            'file': entry,
            'line': line,
            'name': '<module>',
            'localsAvailable': true,
            'variables': variables ?? <Object?>[],
          },
        ],
      },
    );
  }

  @override
  Object? poll() {
    if (brokenPayload != null) return brokenPayload;
    final drained = [...events];
    events.clear();
    return {
      'schema': 1,
      'sessionId': '77',
      'state': state,
      'sequence': sequence,
      'pauseGeneration': generation,
      'droppedEvents': 0,
      'events': drained,
    };
  }

  @override
  void setBreakpoints(List<String> files, List<int> lines) {
    if (rejectBreakpoints) throw StateError('atomic rejection');
    this.files = files;
    this.lines = lines;
  }

  @override
  int command(int generation, int command) {
    if (command == 5) {
      stops++;
      if (throwStop) throw StateError('transient stop transport failure');
      if (rejectedStops > 0) {
        rejectedStops--;
        return 3;
      }
      return 0;
    }
    if (generation != this.generation || state != 'paused') return 3;
    event('running', reason: 'resumed');
    return 0;
  }

  @override
  Future<PythonDebugResult> execute(String source, String stdin, int heapKb) {
    event('running');
    return completion.future.whenComplete(() => exited = true);
  }

  void finish({
    int exit = 0,
    String output = '',
    String error = '',
    bool truncated = false,
  }) {
    event('terminated', extra: {'exitCode': exit, 'traceDisabled': false});
    completion.complete(PythonDebugResult(exit, output, error, truncated));
  }

  @override
  void release() {
    if (failRelease) throw StateError('release failure');
    expect(exited || !completion.isCompleted, isTrue);
    releases++;
  }
}

Future<void> _until(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(seconds: 3)) {
      fail('Timed out waiting for debugger state.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory project;
  late File entry;
  late _Backend backend;
  late _Packages packages;
  late PythonRuntimeActivity activity;
  late PythonDebugger debugger;
  final sessions = <DebugSession>[];

  setUp(() {
    project = Directory.systemTemp.createTempSync('python_debugger_adapter_');
    entry = File(p.join(project.path, 'main.py'))
      ..writeAsStringSync('x = 1\nprint(x)\n');
    backend = _Backend();
    packages = _Packages();
    activity = PythonRuntimeActivity();
    debugger = PythonDebugger(
      backend: backend,
      packageService: packages,
      runtimeActivity: activity,
    );
  });
  tearDown(() async {
    if (sessions.isNotEmpty && !backend.handle.completion.isCompleted) {
      backend.handle.finish(exit: 130);
    }
    for (final session in sessions) {
      await session.dispose();
    }
    sessions.clear();
    project.deleteSync(recursive: true);
  });

  DebugLaunchRequest request({
    List<CodeDocumentSnapshot> documents = const [],
    List<DebugBreakpoint> breakpoints = const [],
    String? file,
    String language = 'python',
  }) => DebugLaunchRequest(
    projectPath: project.path,
    entryFilePath: file ?? entry.path,
    language: language,
    documents: documents,
    breakpoints: breakpoints,
    stopOnEntry: true,
  );

  Future<DebugSession> launch({
    List<DebugBreakpoint> breakpoints = const [],
  }) async {
    final session = await debugger.launch(request(breakpoints: breakpoints));
    sessions.add(session);
    return session;
  }

  test('profile advertises only implemented Python debugger capabilities', () {
    expect(pythonProfile.debugger, isA<PythonDebugger>());
    expect(debugger.capabilities.supportsPause, isFalse);
    expect(debugger.capabilities.supportsDocumentSnapshots, isFalse);
    expect(debugger.capabilities.outputDelivery, DebugOutputDelivery.exitOnly);
    expect(debugger.capabilities.breakpointUpdate, DebugBreakpointUpdate.live);
    expect(debugger.supportsLanguage('Python'), isTrue);
    expect(debugger.supportsLanguage('dart'), isFalse);
  });

  test(
    'unsupported documents language and source paths fail before execution',
    () async {
      await expectLater(
        debugger.launch(
          request(
            documents: [
              CodeDocumentSnapshot(
                path: entry.path,
                text: 'print(42)',
                revision: 1,
              ),
            ],
          ),
        ),
        throwsUnsupportedError,
      );
      await expectLater(
        debugger.launch(request(language: 'c')),
        throwsArgumentError,
      );
      await expectLater(
        debugger.launch(request(file: 'main.py')),
        throwsArgumentError,
      );
      final foreign = File(
        p.join(project.parent.path, '${p.basename(project.path)}.py'),
      )..writeAsStringSync('pass');
      addTearDown(foreign.deleteSync);
      await expectLater(
        debugger.launch(request(file: foreign.path)),
        throwsArgumentError,
      );
      await expectLater(
        debugger.launch(request(file: p.join(project.path, 'missing.py'))),
        throwsA(isA<FileSystemException>()),
      );
      expect(backend.creates, 0);
      expect(activity.isBusy, isFalse);
    },
  );

  test(
    'debug lease is acquired before preparation and shared with normal work',
    () async {
      packages.preparation = Completer<void>();
      final pending = launch();
      expect(activity.operation, PythonRuntimeOperation.debug);
      expect(activity.tryAcquire(PythonRuntimeOperation.run), isNull);
      await expectLater(debugger.launch(request()), throwsStateError);
      packages.preparation!.complete();
      final session = await pending;
      backend.handle.finish();
      await session.done;
      expect(activity.isBusy, isFalse);
    },
  );

  test(
    'current pause generation controls steps and stale or foreign tokens cannot resume',
    () async {
      final session = await launch();
      backend.handle.pause();
      await _until(() => session.snapshot.phase == DebugPhase.paused);
      final token = session.snapshot.pauseToken!;
      await expectLater(
        session.command(DebugCommand.pause),
        throwsUnsupportedError,
      );
      await expectLater(
        session.command(
          DebugCommand.stepInto,
          pauseToken: token,
          threadId: 'foreign',
        ),
        throwsArgumentError,
      );
      await expectLater(
        session.command(
          DebugCommand.resume,
          pauseToken: DebugPauseToken(sessionId: 'other', generation: 1),
        ),
        throwsStateError,
      );
      await session.command(DebugCommand.stepInto, pauseToken: token);
      expect(session.snapshot.pauseToken, isNull);
      expect(session.snapshot.frames, isEmpty);
      await expectLater(
        session.command(DebugCommand.resume, pauseToken: token),
        throwsStateError,
      );
      backend.handle.pause(line: 2);
      await _until(() => session.snapshot.pauseToken?.generation == 2);
      await expectLater(
        session.command(DebugCommand.resume, pauseToken: token),
        throwsStateError,
      );
      await session.command(
        DebugCommand.resume,
        pauseToken: session.snapshot.pauseToken,
      );
      backend.handle.finish();
      await session.done;
    },
  );

  test(
    'accepted breakpoints remain pending until a real hit and invalid replacement is atomic',
    () async {
      final point = DebugBreakpoint(filePath: entry.path, line: 2);
      final session = await launch(breakpoints: [point]);
      expect(
        session.snapshot.breakpoints.single.status,
        DebugBreakpointStatus.pending,
      );
      await expectLater(
        session.setBreakpoints([point, point]),
        throwsArgumentError,
      );
      expect(backend.handle.lines, [2]);
      backend.handle.rejectBreakpoints = true;
      await expectLater(session.setBreakpoints([]), throwsStateError);
      expect(session.snapshot.breakpoints.single.requested.line, 2);
      backend.handle.rejectBreakpoints = false;
      backend.handle.pause(line: 2);
      await _until(() => session.snapshot.phase == DebugPhase.paused);
      expect(
        session.snapshot.breakpoints.single.status,
        DebugBreakpointStatus.verified,
      );
      expect(
        session.snapshot.breakpoints.single.actualLocation!.filePath,
        entry.resolveSymbolicLinksSync(),
      );
      await session.setBreakpoints([]);
      expect(session.snapshot.breakpoints, isEmpty);
    },
  );

  test(
    'stop and dispose await actual worker exit and cleanup even after a terminal event',
    () async {
      final session = await launch();
      backend.handle.pause();
      await _until(() => session.snapshot.phase == DebugPhase.paused);
      var completed = false;
      final stopping = session.stop().then((_) => completed = true);
      final disposing = session.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(session.snapshot.phase, DebugPhase.stopping);
      expect(completed, isFalse);
      expect(activity.isBusy, isTrue);
      expect(backend.handle.releases, 0);
      expect(backend.handle.stops, 1);
      backend.handle.event(
        'terminated',
        extra: {'exitCode': 130, 'traceDisabled': false},
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(completed, isFalse);
      expect(activity.isBusy, isTrue);
      backend.handle.finish(exit: 130);
      await stopping;
      await disposing;
      expect(session.snapshot.phase, DebugPhase.terminated);
      expect(session.snapshot.exitCode, 130);
      expect(backend.handle.releases, 1);
      expect(activity.isBusy, isFalse);
      await session.stop();
      await session.dispose();
      expect(backend.handle.stops, 1);
    },
  );

  test(
    'malformed events request stop and retain the lease until real settlement',
    () async {
      final session = await launch();
      backend.handle.brokenPayload = {'schema': 99, 'sessionId': '77'};
      await _until(() => session.snapshot.phase == DebugPhase.stopping);
      expect(activity.isBusy, isTrue);
      expect(backend.handle.releases, 0);
      backend.handle.finish(exit: 130);
      await session.done;
      expect(session.snapshot.phase, DebugPhase.failed);
      expect(session.snapshot.message, contains('schema'));
      expect(activity.isBusy, isFalse);
    },
  );

  test(
    'cleanup failure retains the lease and completion until an explicit retry succeeds',
    () async {
      final session = await launch();
      backend.handle.failRelease = true;
      var completed = false;
      unawaited(session.done.then((_) => completed = true));
      backend.handle.finish();
      await _until(() => session.snapshot.phase == DebugPhase.stopping);
      expect(session.snapshot.message, contains('cleanup failed'));
      expect(activity.isBusy, isTrue);
      expect(completed, isFalse);
      backend.handle.failRelease = false;
      await session.stop();
      expect(activity.isBusy, isFalse);
      expect(session.snapshot.phase, DebugPhase.failed);
      expect(backend.handle.releases, 1);
    },
  );

  test(
    'rejected Stop can be retried while the real paused worker remains owned',
    () async {
      final session = await launch();
      backend.handle.pause();
      await _until(() => session.snapshot.phase == DebugPhase.paused);
      backend.handle.rejectedStops = 1;
      final first = session.stop();
      expect(backend.handle.stops, 1);
      expect(activity.isBusy, isTrue);
      final second = session.stop();
      expect(backend.handle.stops, 2);
      backend.handle.finish(exit: 130);
      await first;
      await second;
      expect(activity.isBusy, isFalse);
      expect(backend.handle.releases, 1);
    },
  );

  test(
    'repeated dispose retries a throwing Stop while sharing actual cleanup',
    () async {
      final session = await launch();
      backend.handle.pause();
      await _until(() => session.snapshot.phase == DebugPhase.paused);
      backend.handle.throwStop = true;
      final first = session.dispose();
      expect(backend.handle.stops, 1);
      expect(session.snapshot.phase, DebugPhase.stopping);
      backend.handle.throwStop = false;
      final second = session.dispose();
      expect(backend.handle.stops, 2);
      backend.handle.finish(exit: 130);
      await first;
      await second;
      expect(backend.handle.releases, 1);
    },
  );

  test(
    'malformed event Stop rejection is retried without relying on disabled UI controls',
    () async {
      final session = await launch();
      backend.handle.rejectedStops = 1;
      backend.handle.brokenPayload = {'schema': 99, 'sessionId': '77'};
      await _until(() => backend.handle.stops == 2);
      expect(session.snapshot.phase, DebugPhase.stopping);
      expect(activity.isBusy, isTrue);
      backend.handle.finish(exit: 130);
      await session.done;
      expect(session.snapshot.message, contains('schema'));
      expect(activity.isBusy, isFalse);
    },
  );

  test(
    'repeated dispose retries failed release even with an earlier dispose pending',
    () async {
      final session = await launch();
      backend.handle.failRelease = true;
      final first = session.dispose();
      backend.handle.finish(exit: 130);
      await _until(
        () => session.snapshot.message?.contains('cleanup failed') == true,
      );
      expect(activity.isBusy, isTrue);
      backend.handle.failRelease = false;
      final second = session.dispose();
      await first;
      await second;
      expect(activity.isBusy, isFalse);
      expect(backend.handle.releases, 1);
    },
  );

  test(
    'full output snapshot preserves Unicode and explicitly exposes truncation',
    () async {
      final session = await launch();
      final snapshots = <DebugSnapshot>[];
      final subscription = session.updates.listen(snapshots.add);
      final stdout = '${'x' * 262143}😀tail';
      backend.handle.finish(
        output: stdout,
        error: 'warning\n',
        truncated: true,
      );
      await session.done;
      await Future<void>.delayed(Duration.zero);
      expect(session.snapshot.stdout, 'x' * 262143);
      expect(session.snapshot.stderr, 'warning\n');
      expect(session.snapshot.stdoutTruncated, isTrue);
      expect(session.snapshot.stderrTruncated, isTrue);
      for (var i = 1; i < snapshots.length; i++) {
        expect(snapshots[i].revision, greaterThan(snapshots[i - 1].revision));
      }
      await subscription.cancel();
    },
  );

  test(
    'bounded variables retain actual values and honest unavailable reasons',
    () async {
      final session = await launch();
      backend.handle.pause(
        variables: [
          {'name': 'text', 'type': 'str', 'value': 'a\u0000b'},
          {
            'name': 'later',
            'type': 'unbound',
            'value': '<unbound>',
            'unbound': true,
          },
          {'name': 'object', 'type': 'Widget', 'value': '<Widget>'},
          {
            'name': 'data',
            'type': 'dict',
            'value': '<dict>',
            'truncated': true,
            'children': [
              {
                'key': {'type': 'str', 'value': 'ok'},
                'item': {'type': 'int', 'value': '7'},
              },
            ],
          },
          {'name': '', 'type': 'int', 'value': '5'},
          {'name': 'key\u0000name', 'type': 'int', 'value': '6'},
        ],
      );
      await _until(
        () =>
            session.snapshot.phase != DebugPhase.starting &&
            session.snapshot.phase != DebugPhase.running,
      );
      expect(
        session.snapshot.phase,
        DebugPhase.paused,
        reason: session.snapshot.message,
      );
      final vars = session.snapshot.frames.single.locals;
      expect(vars[0].value, 'a\u0000b');
      expect(vars[1].unavailableReason, contains('not been assigned'));
      expect(vars[2].unavailableReason, contains('does not run user code'));
      expect(vars[3].children.single.children.last.value, '7');
      expect(vars[3].truncated, isTrue);
      expect(vars[4].name, isEmpty);
      expect(vars[4].value, '5');
      expect(vars[5].name, 'key\u0000name');
    },
  );

  test(
    'program error is terminal only after cleanup and preserves the actual exit',
    () async {
      final session = await launch();
      backend.handle.finish(
        exit: 7,
        output: 'before\n',
        error: 'ValueError: actual\n',
      );
      await session.done;
      expect(session.snapshot.phase, DebugPhase.failed);
      expect(session.snapshot.exitCode, 7);
      expect(session.snapshot.message, 'ValueError: actual\n');
      expect(session.snapshot.stdout, 'before\n');
      expect(backend.handle.releases, 1);
      expect(activity.isBusy, isFalse);
    },
  );
}
