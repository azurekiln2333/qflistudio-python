import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/file_encoding.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

import 'python_debugger_ffi.dart';
import 'python_packages.dart';
import 'python_runner.dart';
import 'python_runtime_activity.dart';

/// Real MicroPython debug sessions. All execution remains inside the bundled VM.
final class PythonDebugger implements StudioDebugger {
  const PythonDebugger({
    this.backend,
    this.libraryPath,
    this.packageService,
    this.runtimeActivity,
    this.heapKb = PythonProgramRunner.defaultHeapKb,
  });

  final PythonDebugBackend? backend;
  final String? libraryPath;
  final PythonPackageService? packageService;
  final PythonRuntimeActivity? runtimeActivity;
  final int heapKb;

  @override
  String get displayName => 'Python';

  @override
  DebugCapabilities get capabilities => const DebugCapabilities(
    breakpointUpdate: DebugBreakpointUpdate.live,
    outputDelivery: DebugOutputDelivery.exitOnly,
    supportsStepInto: true,
    supportsStepOver: true,
    supportsStepOut: true,
    supportsStopOnEntry: true,
    supportsStackFrames: true,
    supportsVariables: true,
  );

  @override
  bool supportsLanguage(String language) => language.toLowerCase() == 'python';

  @override
  Future<DebugSession> launch(DebugLaunchRequest request) async {
    if (!supportsLanguage(request.language)) {
      throw ArgumentError('Python debugger requires the Python language.');
    }
    if (request.documents.isNotEmpty) {
      throw UnsupportedError('请先保存文件；Python 调试器尚不支持未保存的源码快照。');
    }
    if (heapKb < 0 || heapKb > 0x7fffffff) {
      throw ArgumentError.value(heapKb, 'heapKb');
    }
    _absolute(request.projectPath);
    final root = Directory(request.projectPath).resolveSymbolicLinksSync();
    final entry = _sourcePath(root, request.entryFilePath);
    final breakpoints = _validateBreakpoints(root, request.breakpoints);
    final activity = runtimeActivity ?? PythonRuntimeActivity.shared;
    final lease = activity.tryAcquire(PythonRuntimeOperation.debug);
    if (lease == null) throw StateError(activity.busyReason);
    PythonDebugHandle? handle;
    try {
      final preparation = await (packageService ?? PythonPackageService())
          .ensureBundledModules(root);
      if (!preparation.success) throw StateError(preparation.message);
      final source = _readText(File(entry));
      final input = File(p.join(root, PythonProgramRunner.stdinFileName));
      final stdin = input.existsSync() ? _readText(input) : '';
      // NUL must not silently truncate the program or its finite input at the ABI.
      if (source.contains('\u0000') || stdin.contains('\u0000')) {
        throw ArgumentError('Python source and input cannot contain NUL.');
      }
      handle = (backend ?? PythonDebugFfiBackend(libraryPath: libraryPath))
          .create(root, entry, request.stopOnEntry);
      final session = _PythonDebugSession(handle, lease, root, breakpoints);
      session._initialize();
      session._start(source, stdin, heapKb);
      return session;
    } catch (_) {
      handle?.release();
      lease.release();
      rethrow;
    }
  }
}

void _absolute(String path) {
  if (path.isEmpty || path.contains('\u0000') || !p.isAbsolute(path)) {
    throw ArgumentError('Debugger paths must be absolute and contain no NUL.');
  }
}

String _sourcePath(String root, String path) {
  _absolute(path);
  final resolved = File(path).resolveSymbolicLinksSync();
  if (!p.isWithin(root, resolved) ||
      p.isWithin(p.join(root, '.qfli', 'python', 'bundled'), resolved) ||
      p.extension(resolved).toLowerCase() != '.py' ||
      FileSystemEntity.typeSync(resolved) != FileSystemEntityType.file) {
    throw ArgumentError('Debugger source must be a project-local .py file.');
  }
  return resolved;
}

List<DebugBreakpoint> _validateBreakpoints(
  String root,
  List<DebugBreakpoint> requests,
) {
  if (requests.length > 128) {
    throw ArgumentError('At most 128 breakpoints are supported.');
  }
  final seen = <String>{};
  return [
    for (final point in requests)
      (() {
        if (point.line <= 0 || point.line > 0x7fffffff) {
          throw ArgumentError(
            'Breakpoint lines must be positive Int32 values.',
          );
        }
        final file = _sourcePath(root, point.filePath);
        final key =
            '${Platform.isWindows ? file.toLowerCase() : file}:${point.line}';
        if (!seen.add(key)) throw ArgumentError('Duplicate breakpoint: $key');
        return DebugBreakpoint(filePath: file, line: point.line);
      })(),
  ];
}

String _readText(File file) {
  final bytes = file.readAsBytesSync();
  return TextCodec.byName(TextCodec.detect(bytes)).decode(bytes);
}

/// Limits mirror the native schema: 16 frames, 64 locals/frame, four children
/// per built-in container, two container levels, 256 code units per value/name.
/// Retained text is bounded to 256 Ki stdout, 64 Ki stderr, 8 Ki diagnostics.
/// Native's combined output-truncated flag conservatively marks both streams.
final class _PythonDebugSession implements DebugSession {
  _PythonDebugSession(this._handle, this._lease, this._root, this._requested);

  final PythonDebugHandle _handle;
  final PythonRuntimeLease _lease;
  final String _root;
  List<DebugBreakpoint> _requested;
  final _updates = StreamController<DebugSnapshot>.broadcast();
  final _done = Completer<void>();
  late String _id;
  late DebugSnapshot _snapshot;
  int _revision = 0, _sequence = 0, _generation = 0, _dropped = 0;
  DebugPhase _phase = DebugPhase.starting;
  DebugPauseToken? _pause;
  List<DebugFrame> _frames = const [];
  List<DebugBreakpointResult> _breakpoints = const [];
  bool _framesTruncated = false, _consoleTruncated = false;
  bool _stdoutTruncated = false, _stderrTruncated = false;
  bool _stopRequested = false, _traceDisabled = false, _workerExited = false;
  bool _stopDispatched = false;
  String _stdout = '', _stderr = '', _console = '';
  String? _failure;
  int? _exitCode, _nativeExitCode;
  Timer? _timer;
  Timer? _stopRetry;
  Future<void>? _disposing;

  @override
  String get id => _id;
  @override
  DebugSnapshot get snapshot => _snapshot;
  @override
  Stream<DebugSnapshot> get updates => _updates.stream;
  @override
  Future<void> get done => _done.future;

  void _initialize() {
    final envelope = _map(_handle.poll());
    _id = 'python:${_string(envelope, 'sessionId', max: 64)}';
    _snapshot = DebugSnapshot(sessionId: _id, revision: 0, phase: _phase);
    _consume(envelope);
    _replaceBreakpoints(_requested);
  }

  void _start(String source, String stdin, int heapKb) {
    final execution = _handle.execute(source, stdin, heapKb);
    _timer = Timer.periodic(const Duration(milliseconds: 20), (_) => _poll());
    // The executor future proves actual native return and worker cleanup. A
    // terminal event alone is deliberately not enough to release the VM lease.
    unawaited(
      execution.then(
        (result) => _finish(result, null),
        onError: (Object error, StackTrace stack) => _finish(null, error),
      ),
    );
  }

  void _poll() {
    if (_done.isCompleted || _failure != null) return;
    try {
      _consume(_map(_handle.poll()));
    } catch (error) {
      _failure = _bounded('Python debugger event error: $error', 8192);
      _requestStop();
    }
  }

  void _consume(Map<Object?, Object?> envelope) {
    if (envelope['schema'] != 1 ||
        'python:${_string(envelope, 'sessionId', max: 64)}' != _id) {
      throw const FormatException(
        'Unexpected debugger schema or session identity.',
      );
    }
    _state(envelope);
    _integer(envelope, 'sequence');
    _integer(envelope, 'pauseGeneration');
    final dropped = _integer(envelope, 'droppedEvents');
    if (dropped < _dropped) {
      throw const FormatException('Debugger event count decreased.');
    }
    if (dropped > _dropped) {
      _dropped = dropped;
      _consoleTruncated = true;
      _log('Native debugger omitted $dropped events.');
      _publish();
    }
    final events = _list(envelope['events']);
    if (events.length > 16) {
      throw const FormatException('Too many debugger events.');
    }
    if (envelope.containsKey('requiredBytes')) {
      throw const FormatException(
        'Debugger event exceeds the maximum poll size.',
      );
    }
    for (final raw in events) {
      final event = _map(raw);
      final sequence = _integer(event, 'sequence', positive: true);
      if (sequence <= _sequence || event['kind'] != 'state') {
        throw const FormatException('Debugger events are out of order.');
      }
      _sequence = sequence;
      final state = _state(event);
      final reason = _string(event, 'reason', max: 256);
      final generation = _integer(event, 'pauseGeneration');
      if (generation < _generation) {
        throw const FormatException('Pause generation decreased.');
      }
      if (state == 'terminated') {
        _nativeExitCode = _signedInteger(event, 'exitCode');
        _traceDisabled = _boolean(event, 'traceDisabled');
        // Do not publish terminal before the native worker really returns.
        continue;
      }
      if (_stopRequested) continue;
      if (state == 'paused') {
        if (generation <= _generation) {
          throw const FormatException('Pause generation was reused.');
        }
        _generation = generation;
        final frames = _list(event['frames']);
        _framesTruncated = _boolean(event, 'truncated') || frames.length > 16;
        _frames = [
          for (final rawFrame in frames.take(16)) _frame(_map(rawFrame)),
        ];
        if (_frames.map((frame) => frame.id).toSet().length != _frames.length) {
          throw const FormatException('Duplicate debugger frame identity.');
        }
        _pause = DebugPauseToken(sessionId: id, generation: generation);
        _phase = DebugPhase.paused;
        final actual = _location(
          _string(event, 'file', max: 4096),
          _integer(event, 'line', positive: true),
        );
        if (actual == null) {
          throw const FormatException('Pause is outside project source.');
        }
        if (reason == 'breakpoint') {
          _breakpoints = [
            for (final result in _breakpoints)
              if (p.equals(result.requested.filePath, actual.filePath) &&
                  result.requested.line == actual.line)
                DebugBreakpointResult(
                  requested: result.requested,
                  status: DebugBreakpointStatus.verified,
                  actualLocation: actual,
                )
              else
                result,
          ];
        }
      } else {
        _phase = state == 'created' ? DebugPhase.starting : DebugPhase.running;
        _pause = null;
        _frames = const [];
        _framesTruncated = false;
      }
      _log(reason);
      _publish();
    }
  }

  DebugFrame _frame(Map<Object?, Object?> raw) {
    final frameId = _string(raw, 'id', max: 64);
    if (!frameId.startsWith('$_generation:')) {
      throw const FormatException('Frame belongs to a different pause.');
    }
    final variables = _list(raw['variables']);
    final available = _boolean(raw, 'localsAvailable');
    final name = _string(raw, 'name', max: 4096);
    if (name.length > 256) _framesTruncated = true;
    return DebugFrame(
      id: frameId,
      threadId: 'main',
      name: _bounded(name, 256),
      location: _location(
        _string(raw, 'file', max: 4096),
        _integer(raw, 'line'),
      ),
      locals: available
          ? [
              for (final variable in variables.take(64))
                _variable(_map(variable), null, 0),
            ]
          : const [],
      localsUnavailableReason: available
          ? null
          : _string(raw, 'localsReason', max: 256),
      localsTruncated: _optionalBool(raw, 'truncated') || variables.length > 64,
    );
  }

  DebugSourceLocation? _location(String file, int line) {
    if (line <= 0 || file.startsWith('<')) return null;
    try {
      final path = _sourcePath(
        _root,
        p.isAbsolute(file) ? file : p.join(_root, file),
      );
      return DebugSourceLocation(filePath: path, line: line);
    } on FileSystemException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  DebugVariable _variable(Map<Object?, Object?> raw, String? label, int depth) {
    final name = label ??
        _string(raw, 'name', max: 4096, allowEmpty: true, allowNul: true);
    final type = _string(raw, 'type', max: 4096);
    final value = _string(
      raw,
      'value',
      max: 4096,
      allowEmpty: true,
      allowNul: true,
    );
    final unbound = _optionalBool(raw, 'unbound');
    final cycle = _optionalBool(raw, 'cycle');
    var truncated =
        _optionalBool(raw, 'truncated') ||
        name.length > 256 ||
        type.length > 256 ||
        value.length > 256;
    final children = <DebugVariable>[];
    if (raw.containsKey('children')) {
      final entries = _list(raw['children']);
      if (depth >= 2) {
        truncated |= entries.isNotEmpty;
      } else {
        truncated |= entries.length > 4;
        for (var i = 0; i < entries.length && i < 4; i++) {
          final child = _map(entries[i]);
          if (type == 'dict') {
            children.add(
              DebugVariable(
                name: '[$i]',
                type: 'dict entry',
                value: '',
                children: [
                  _variable(_map(child['key']), 'key', depth + 1),
                  _variable(_map(child['item']), 'value', depth + 1),
                ],
              ),
            );
          } else if (type == 'list' || type == 'tuple') {
            children.add(_variable(child, '[$i]', depth + 1));
          } else {
            throw const FormatException(
              'Unsupported debugger container payload.',
            );
          }
        }
      }
    }
    const inspectedTypes = {
      'NoneType',
      'bool',
      'int',
      'float',
      'str',
      'bytes',
      'list',
      'tuple',
      'dict',
      'unbound',
      'bounded',
    };
    final reason = unbound
        ? 'The local has not been assigned yet.'
        : cycle
        ? 'Cyclic reference; children were not expanded.'
        : !inspectedTypes.contains(type)
        ? 'Object members are unavailable; inspection does not run user code.'
        : null;
    if (raw.containsKey('encoding') && raw['encoding'] != 'hex') {
      throw const FormatException('Unknown debugger value encoding.');
    }
    return DebugVariable(
      name: _bounded(name, 256),
      type: _bounded(type, 256),
      value: raw['encoding'] == 'hex'
          ? '0x${_bounded(value, 256)}'
          : _bounded(value, 256),
      children: children,
      unavailableReason: reason,
      truncated: truncated,
    );
  }

  void _log(String message) {
    final text = _console.isEmpty ? message : '$_console\n$message';
    _consoleTruncated |= text.length > 8192;
    _console = _bounded(text, 8192, tail: true);
  }

  void _publish() {
    _snapshot = DebugSnapshot(
      sessionId: id,
      revision: ++_revision,
      phase: _phase,
      pauseToken: _pause,
      threads: _phase == DebugPhase.terminated || _phase == DebugPhase.failed
          ? const []
          : [
              DebugThread(
                id: 'main',
                name: 'Python VM',
                isPaused: _phase == DebugPhase.paused,
              ),
            ],
      frames: _frames,
      breakpoints: _breakpoints,
      framesTruncated: _framesTruncated,
      stdout: _stdout,
      stderr: _stderr,
      console: _console,
      stdoutTruncated: _stdoutTruncated,
      stderrTruncated: _stderrTruncated,
      consoleTruncated: _consoleTruncated,
      message: _failure,
      exitCode: _exitCode,
    );
    _updates.add(_snapshot);
  }

  void _replaceBreakpoints(List<DebugBreakpoint> points) {
    _handle.setBreakpoints(
      [for (final point in points) point.filePath],
      [for (final point in points) point.line],
    );
    _requested = points;
    _breakpoints = [
      for (final point in points)
        DebugBreakpointResult(
          requested: point,
          status: DebugBreakpointStatus.pending,
        ),
    ];
    _publish();
  }

  @override
  Future<List<DebugBreakpointResult>> setBreakpoints(
    List<DebugBreakpoint> points,
  ) async {
    if (_stopRequested || _done.isCompleted) {
      throw StateError('Debugger is stopping or finished.');
    }
    _replaceBreakpoints(_validateBreakpoints(_root, points));
    return _snapshot.breakpoints;
  }

  @override
  Future<void> command(
    DebugCommand command, {
    DebugPauseToken? pauseToken,
    String? threadId,
  }) async {
    if (command == DebugCommand.pause) {
      throw UnsupportedError('Python does not support asynchronous Pause.');
    }
    if (threadId != null && threadId != 'main') {
      throw ArgumentError('Unknown Python debugger thread.');
    }
    if (_stopRequested ||
        _phase != DebugPhase.paused ||
        pauseToken == null ||
        pauseToken != _pause) {
      throw StateError(
        'Command requires the current observed Python pause token.',
      );
    }
    final nativeCommand = switch (command) {
      DebugCommand.resume => 1,
      DebugCommand.stepInto => 2,
      DebugCommand.stepOver => 3,
      DebugCommand.stepOut => 4,
      DebugCommand.pause => throw UnsupportedError('Pause is unavailable.'),
    };
    final status = _handle.command(pauseToken.generation, nativeCommand);
    if (status != 0) {
      throw StateError('Python debugger command was rejected ($status).');
    }
    _phase = DebugPhase.running;
    _pause = null;
    _frames = const [];
    _framesTruncated = false;
    _publish();
  }

  void _requestStop() {
    if (_stopDispatched || _workerExited || _done.isCompleted) return;
    _stopRetry?.cancel();
    _stopRequested = true;
    _phase = DebugPhase.stopping;
    _pause = null;
    _frames = const [];
    _framesTruncated = false;
    try {
      final status = _handle.command(0, 5);
      if (status == 0 || status == 2) {
        _stopDispatched = true;
      } else {
        _failure ??= 'Python stop request was rejected ($status).';
      }
    } catch (error) {
      _failure ??= _bounded('Python stop request failed: $error', 8192);
    }
    _publish();
    if (!_stopDispatched) {
      // The shared UI is already waiting for actual exit. Keep retrying a
      // transient control failure without holding up polling or native work.
      _stopRetry = Timer(const Duration(milliseconds: 200), _requestStop);
    }
  }

  @override
  Future<void> stop() {
    if (_workerExited && !_done.isCompleted) {
      _cleanupAndFinish();
      return done;
    }
    _requestStop();
    return done;
  }

  void _finish(PythonDebugResult? result, Object? error) {
    _workerExited = true;
    _timer?.cancel();
    _stopRetry?.cancel();
    if (_failure == null) {
      try {
        _consume(_map(_handle.poll()));
      } catch (pollError) {
        _failure = _bounded(
          'Python debugger final event error: $pollError',
          8192,
        );
      }
    }
    if (result != null) {
      _exitCode = result.exitCode;
      _stdout = _bounded(result.output, 262144);
      _stderr = _bounded(result.error, 65536);
      _stdoutTruncated = result.truncated || result.output.length > 262144;
      _stderrTruncated = result.truncated || result.error.length > 65536;
      if (_nativeExitCode != null && _nativeExitCode != result.exitCode) {
        _failure ??=
            'Python debugger exit event disagrees with the actual worker result.';
      }
      if (_traceDisabled) {
        _failure ??=
            'Python program disabled tracing; further debug stops were unavailable.';
      }
      if (result.exitCode != 0 && result.exitCode != 130) {
        _failure ??= _stderr.isEmpty
            ? 'Python exited with code ${result.exitCode}.'
            : _bounded(_stderr, 8192);
      }
    } else {
      _failure ??= _bounded('Python debugger worker failed: $error', 8192);
    }
    _cleanupAndFinish();
  }

  void _cleanupAndFinish() {
    if (_done.isCompleted) return;
    try {
      _handle.release();
    } catch (releaseError) {
      _failure ??= _bounded(
        'Python debugger cleanup failed: $releaseError',
        8192,
      );
      _phase = DebugPhase.stopping;
      _pause = null;
      _frames = const [];
      _framesTruncated = false;
      _publish();
      // A resource cleanup failure is not completion. Keep the runtime lease;
      // a later Stop/dispose may retry cleanup after the underlying cause clears.
      return;
    }
    _lease.release();
    _pause = null;
    _frames = const [];
    _framesTruncated = false;
    _phase = _failure == null ? DebugPhase.terminated : DebugPhase.failed;
    _publish();
    _done.complete();
  }

  @override
  Future<void> dispose() {
    // Each disposal request can retry failed cleanup even when an earlier
    // disposal is still awaiting done. They share the same stream close.
    final stopping = stop();
    return _disposing ??= () async {
      await stopping;
      await _updates.close();
    }();
  }
}

Map<Object?, Object?> _map(Object? value) {
  if (value is! Map) throw const FormatException('Expected a debugger object.');
  return value;
}

List<Object?> _list(Object? value) {
  if (value is! List) throw const FormatException('Expected a debugger list.');
  return value;
}

String _string(
  Map<Object?, Object?> value,
  String key, {
  required int max,
  bool allowEmpty = false,
  bool allowNul = false,
}) {
  final field = value[key];
  if (field is! String ||
      (!allowEmpty && field.isEmpty) ||
      field.length > max ||
      (!allowNul && field.contains('\u0000'))) {
    throw FormatException('Invalid debugger $key.');
  }
  return field;
}

int _integer(Map<Object?, Object?> value, String key, {bool positive = false}) {
  final field = _signedInteger(value, key);
  if (field < (positive ? 1 : 0)) {
    throw FormatException('Invalid debugger $key.');
  }
  return field;
}

int _signedInteger(Map<Object?, Object?> value, String key) {
  final field = value[key];
  if (field is! int) throw FormatException('Invalid debugger $key.');
  return field;
}

bool _boolean(Map<Object?, Object?> value, String key) {
  final field = value[key];
  if (field is! bool) throw FormatException('Invalid debugger $key.');
  return field;
}

bool _optionalBool(Map<Object?, Object?> value, String key) =>
    value.containsKey(key) ? _boolean(value, key) : false;

String _state(Map<Object?, Object?> value) {
  final state = value['state'];
  if (state is! String ||
      !const {'created', 'running', 'paused', 'terminated'}.contains(state)) {
    throw const FormatException('Invalid debugger state.');
  }
  return state;
}

String _bounded(String value, int limit, {bool tail = false}) {
  if (value.length <= limit) return value;
  var offset = tail ? value.length - limit : limit;
  // Keep UTF-16 surrogate pairs intact when enforcing retained-text bounds.
  if (offset > 0 &&
      offset < value.length &&
      value.codeUnitAt(offset) >= 0xdc00 &&
      value.codeUnitAt(offset) <= 0xdfff &&
      value.codeUnitAt(offset - 1) >= 0xd800 &&
      value.codeUnitAt(offset - 1) <= 0xdbff) {
    offset += tail ? 1 : -1;
  }
  return tail ? value.substring(offset) : value.substring(0, offset);
}
