import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'python_ffi.dart';
import 'python_native_library.dart';

/// The control surface is nonblocking and never takes the VM execution lock.
abstract interface class PythonDebugBackend {
  PythonDebugHandle create(String project, String entry, bool stopOnEntry);
}

abstract interface class PythonDebugHandle {
  Object? poll();
  void setBreakpoints(List<String> files, List<int> lines);
  int command(int generation, int command);
  Future<PythonDebugResult> execute(String source, String stdin, int heapKb);
  void release();
}

final class PythonDebugResult {
  const PythonDebugResult(
    this.exitCode,
    this.output,
    this.error,
    this.truncated,
  );

  final int exitCode;
  final String output, error;
  final bool truncated;
}

final class PythonDebugFfiBackend implements PythonDebugBackend {
  const PythonDebugFfiBackend({this.libraryPath});

  final String? libraryPath;

  @override
  PythonDebugHandle create(String project, String entry, bool stopOnEntry) {
    _validateStrings([project, entry]);
    final bindings = _load(libraryPath);
    if (bindings.capabilities() & 31 != 31) {
      throw const PythonFfiException(
        'QFLI_PY_DEBUG_UNAVAILABLE',
        'The bundled runtime does not provide the required debugger operations.',
      );
    }
    return using((arena) {
      final root = project.toNativeUtf8(allocator: arena);
      final file = entry.toNativeUtf8(allocator: arena);
      final pointer = bindings.create(root, file, stopOnEntry ? 1 : 0);
      if (pointer == nullptr) {
        throw const PythonFfiException(
          'QFLI_PY_DEBUG_CREATE',
          'Cannot create a debugger for these project/source paths.',
        );
      }
      return _FfiHandle(bindings, pointer, libraryPath);
    });
  }
}

final class _FfiHandle implements PythonDebugHandle {
  _FfiHandle(this._bindings, this._pointer, this._path);

  final _Bindings _bindings;
  final Pointer<Void> _pointer;
  final String? _path;
  bool _released = false, _started = false, _executing = false;

  void _checkLive() {
    if (_released) throw StateError('Debugger handle has been released.');
  }

  @override
  Object? poll() {
    _checkLive();
    final json = _bindings.poll(_pointer, 262144);
    if (json == nullptr) throw StateError('Cannot read debugger events.');
    try {
      return jsonDecode(json.toDartString());
    } finally {
      _bindings.freeJson(json);
    }
  }

  @override
  void setBreakpoints(List<String> files, List<int> lines) {
    _checkLive();
    if (files.length != lines.length ||
        files.length > 128 ||
        lines.any((line) => line <= 0 || line > 0x7fffffff)) {
      throw ArgumentError('Invalid debugger breakpoint set.');
    }
    _validateStrings(files);
    using((arena) {
      final paths = arena<Pointer<Utf8>>(files.isEmpty ? 1 : files.length);
      final positions = arena<Uint32>(lines.isEmpty ? 1 : lines.length);
      for (var i = 0; i < files.length; i++) {
        paths[i] = files[i].toNativeUtf8(allocator: arena);
        positions[i] = lines[i];
      }
      final status = _bindings.setBreakpoints(
        _pointer,
        paths,
        positions,
        files.length,
      );
      if (status != 0) {
        throw StateError('Breakpoint replacement failed ($status).');
      }
    });
  }

  @override
  int command(int generation, int command) {
    _checkLive();
    return _bindings.command(_pointer, generation, command);
  }

  @override
  Future<PythonDebugResult> execute(String source, String stdin, int heapKb) {
    _checkLive();
    if (_started) throw StateError('Debugger session has already started.');
    _validateStrings([source, stdin]);
    if (heapKb < 0 || heapKb > 0x7fffffff) {
      throw ArgumentError.value(
        heapKb,
        'heapKb',
        'Must fit a nonnegative Int32.',
      );
    }
    _started = true;
    _executing = true;
    final request = _Request(_path, _pointer.address, source, stdin, heapKb);
    return _startWorker(request).whenComplete(() => _executing = false);
  }

  @override
  void release() {
    if (_released) return;
    if (_executing) {
      throw StateError('Cannot release a running debugger worker.');
    }
    _released = true;
    _bindings.release(_pointer);
  }
}

void _validateStrings(List<String> values) {
  if (values.any((value) => value.contains('\u0000'))) {
    throw ArgumentError('Debugger arguments cannot contain NUL.');
  }
}

final class _Result extends Struct {
  @Int32()
  external int exitCode;
  external Pointer<Utf8> output;
  external Pointer<Utf8> error;
  @Int32()
  external int truncated;
}

final class _Bindings {
  _Bindings(DynamicLibrary library)
    : capabilities = library.lookupFunction<Uint32 Function(), int Function()>(
        'qfli_py_debug_capabilities',
      ),
      create = library
          .lookupFunction<
            Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>, Int32),
            Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>, int)
          >('qfli_py_debug_create'),
      release = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('qfli_py_debug_release'),
      setBreakpoints = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Pointer<Utf8>>,
              Pointer<Uint32>,
              Size,
            ),
            int Function(
              Pointer<Void>,
              Pointer<Pointer<Utf8>>,
              Pointer<Uint32>,
              int,
            )
          >('qfli_py_debug_set_breakpoints'),
      execute = library
          .lookupFunction<
            Void Function(
              Pointer<_Result>,
              Pointer<Utf8>,
              Pointer<Utf8>,
              Int32,
              Pointer<Void>,
            ),
            void Function(
              Pointer<_Result>,
              Pointer<Utf8>,
              Pointer<Utf8>,
              int,
              Pointer<Void>,
            )
          >('qfli_py_debug_execute_into'),
      command = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Uint64, Int32),
            int Function(Pointer<Void>, int, int)
          >('qfli_py_debug_command'),
      poll = library
          .lookupFunction<
            Pointer<Utf8> Function(Pointer<Void>, Size),
            Pointer<Utf8> Function(Pointer<Void>, int)
          >('qfli_py_debug_poll_json'),
      freeJson = library
          .lookupFunction<
            Void Function(Pointer<Utf8>),
            void Function(Pointer<Utf8>)
          >('qfli_py_debug_json_free'),
      freeResult = library
          .lookupFunction<
            Void Function(Pointer<_Result>),
            void Function(Pointer<_Result>)
          >('qfli_py_result_free');

  final int Function() capabilities;
  final Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>, int) create;
  final void Function(Pointer<Void>) release;
  final int Function(
    Pointer<Void>,
    Pointer<Pointer<Utf8>>,
    Pointer<Uint32>,
    int,
  )
  setBreakpoints;
  final void Function(
    Pointer<_Result>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    int,
    Pointer<Void>,
  )
  execute;
  final int Function(Pointer<Void>, int, int) command;
  final Pointer<Utf8> Function(Pointer<Void>, int) poll;
  final void Function(Pointer<Utf8>) freeJson;
  final void Function(Pointer<_Result>) freeResult;
}

_Bindings _load(String? path) {
  try {
    return _Bindings(openPythonNativeLibrary(path));
  } catch (error) {
    throw PythonFfiException(
      'QFLI_PY_DEBUG_UNAVAILABLE',
      'The bundled Python debugger could not be loaded: $error',
    );
  }
}

final class _Request {
  const _Request(this.path, this.address, this.source, this.stdin, this.heapKb);
  final String? path;
  final int address, heapKb;
  final String source, stdin;
}

Future<PythonDebugResult> _startWorker(_Request request) =>
    Isolate.run(() => _execute(request));

PythonDebugResult _execute(_Request request) {
  final bindings = _load(request.path);
  return using((arena) {
    final result = arena<_Result>();
    // Keep result_free safe even if allocating a later argument fails before
    // native execute initializes the result.
    result.ref.exitCode = 0;
    result.ref.output = nullptr;
    result.ref.error = nullptr;
    result.ref.truncated = 0;
    try {
      final source = request.source.toNativeUtf8(allocator: arena);
      final stdin = request.stdin.toNativeUtf8(allocator: arena);
      bindings.execute(
        result,
        source,
        stdin,
        request.heapKb,
        Pointer<Void>.fromAddress(request.address),
      );
      return PythonDebugResult(
        result.ref.exitCode,
        _decode(result.ref.output),
        _decode(result.ref.error),
        result.ref.truncated != 0,
      );
    } finally {
      bindings.freeResult(result);
    }
  });
}

String _decode(Pointer<Utf8> value) => value == nullptr
    ? ''
    : utf8.decode(
        value.cast<Uint8>().asTypedList(value.length),
        allowMalformed: true,
      );
