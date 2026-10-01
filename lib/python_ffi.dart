import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

final class _NativeResult extends Struct {
  @Int32()
  external int exitCode;

  external Pointer<Utf8> output;
  external Pointer<Utf8> error;

  @Int32()
  external int truncated;
}

typedef _RunNative =
    Void Function(
      Pointer<_NativeResult>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Int32,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Int32,
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );
typedef _RunDart =
    void Function(
      Pointer<_NativeResult>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      int,
      Pointer<Utf8>,
      Pointer<Utf8>,
      int,
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );
typedef _FreeNative = Void Function(Pointer<_NativeResult>);
typedef _FreeDart = void Function(Pointer<_NativeResult>);
typedef _VersionNative = Pointer<Utf8> Function();
typedef _VersionDart = Pointer<Utf8> Function();
typedef _CreateNative = Pointer<Void> Function();
typedef _CreateDart = Pointer<Void> Function();
typedef _TokenNative = Void Function(Pointer<Void>);
typedef _TokenDart = void Function(Pointer<Void>);

class PythonFfiExecution {
  const PythonFfiExecution._(this.result, this.cancel);

  final Future<Map<String, Object?>> result;
  final Future<void> Function() cancel;
}

class PythonFfiException implements Exception {
  const PythonFfiException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// Loads the bundled C MicroPython VM and executes it off the UI isolate.
class PythonFfiBackend {
  const PythonFfiBackend({this.libraryPath});

  final String? libraryPath;

  Future<Map<String, Object?>> probe() {
    final path = libraryPath;
    return Isolate.run(() {
      try {
        final bindings = _loadBindings(path);
        final version = _decode(bindings.version());
        if (version.isEmpty) {
          throw const PythonFfiException(
            'QFLI_PY_MODULE_MISSING',
            'The bundled MicroPython runtime returned no version.',
          );
        }
        return {
          'available': true,
          'version': version,
          'detail': '',
          'runControl': true,
          'bytecode': true,
        };
      } on PythonFfiException catch (error) {
        return {'available': false, 'version': '', 'detail': error.message};
      }
    });
  }

  Future<Map<String, Object?>> run({
    required String source,
    required String stdin,
    required int heapKb,
    required String projectPath,
    required String entryFile,
    bool compileOnly = false,
    String artifactOutput = '',
    String bytecodeFile = '',
  }) {
    _validate(
      source,
      stdin,
      heapKb,
      projectPath,
      entryFile,
      artifactOutput,
      bytecodeFile,
    );
    try {
      return start(
        source: source,
        stdin: stdin,
        heapKb: heapKb,
        projectPath: projectPath,
        entryFile: entryFile,
        compileOnly: compileOnly,
        artifactOutput: artifactOutput,
        bytecodeFile: bytecodeFile,
      ).result;
    } on PythonFfiException catch (error) {
      return Future.error(error);
    }
  }

  PythonFfiExecution start({
    required String source,
    required String stdin,
    required int heapKb,
    required String projectPath,
    required String entryFile,
    bool compileOnly = false,
    String artifactOutput = '',
    String bytecodeFile = '',
  }) {
    _validate(
      source,
      stdin,
      heapKb,
      projectPath,
      entryFile,
      artifactOutput,
      bytecodeFile,
    );
    final bindings = _loadBindings(libraryPath);
    final token = bindings.create();
    if (token == nullptr) {
      throw const PythonFfiException(
        'QFLI_PY_NATIVE_ERROR',
        'Unable to allocate cancellation token.',
      );
    }
    var finished = false;
    final future =
        _startWorker(
          _NativeRequest(
            libraryPath,
            source,
            stdin,
            heapKb,
            projectPath,
            entryFile,
            compileOnly,
            token.address,
            artifactOutput,
            bytecodeFile,
          ),
        ).whenComplete(() {
          finished = true;
          bindings.freeToken(token);
        });
    return PythonFfiExecution._(future, () async {
      if (!finished) bindings.cancel(token);
    });
  }

  static void _validate(
    String source,
    String stdin,
    int heapKb,
    String projectPath,
    String entryFile,
    String artifactOutput,
    String bytecodeFile,
  ) {
    for (final argument in {
      'source': source,
      'stdin': stdin,
      'projectPath': projectPath,
      'entryFile': entryFile,
      'artifactOutput': artifactOutput,
      'bytecodeFile': bytecodeFile,
    }.entries) {
      if (argument.value.contains('\u0000')) {
        throw PythonFfiException(
          'INVALID_ARGUMENT',
          '${argument.key} must not contain NUL.',
        );
      }
    }
    if (heapKb < 0 || heapKb > 0x7fffffff) {
      throw const PythonFfiException(
        'INVALID_ARGUMENT',
        'heapKb must fit a nonnegative 32-bit integer.',
      );
    }
  }
}

class _NativeRequest {
  const _NativeRequest(
    this.path,
    this.source,
    this.stdin,
    this.heapKb,
    this.projectPath,
    this.entryFile,
    this.compileOnly,
    this.tokenAddress,
    this.artifactOutput,
    this.bytecodeFile,
  );
  final String? path;
  final String source,
      stdin,
      projectPath,
      entryFile,
      artifactOutput,
      bytecodeFile;
  final int heapKb, tokenAddress;
  final bool compileOnly;
}

Future<Map<String, Object?>> _startWorker(_NativeRequest request) =>
    Isolate.run(() => _invokeNative(request));

class _Bindings {
  _Bindings(DynamicLibrary library)
    : run = library.lookupFunction<_RunNative, _RunDart>(
        'qfli_py_execute_into',
      ),
      create = library.lookupFunction<_CreateNative, _CreateDart>(
        'qfli_py_cancel_create',
      ),
      cancel = library.lookupFunction<_TokenNative, _TokenDart>(
        'qfli_py_cancel_request',
      ),
      freeToken = library.lookupFunction<_TokenNative, _TokenDart>(
        'qfli_py_cancel_free',
      ),
      free = library.lookupFunction<_FreeNative, _FreeDart>(
        'qfli_py_result_free',
      ),
      version = library.lookupFunction<_VersionNative, _VersionDart>(
        'qfli_py_version',
      );

  final _RunDart run;
  final _FreeDart free;
  final _VersionDart version;
  final _CreateDart create;
  final _TokenDart cancel, freeToken;
}

_Bindings _loadBindings(String? libraryPath) {
  try {
    return _Bindings(_openLibrary(libraryPath));
  } catch (error) {
    throw PythonFfiException(
      'QFLI_PY_MODULE_MISSING',
      'The bundled MicroPython runtime could not be loaded: $error',
    );
  }
}

DynamicLibrary _openLibrary(String? explicitPath) {
  if (explicitPath != null) return DynamicLibrary.open(explicitPath);
  if (Platform.isIOS || Platform.isMacOS) return DynamicLibrary.process();
  if (!Platform.isWindows && !Platform.isLinux) {
    throw UnsupportedError('No MicroPython FFI library for this platform.');
  }
  final name = Platform.isWindows ? 'qfli_py_ffi.dll' : 'libqfli_py_ffi.so';
  final executableDirectory = File(Platform.resolvedExecutable).parent.path;
  final candidates = [
    p.join(executableDirectory, name),
    p.join(executableDirectory, 'lib', name),
    p.join(
      Directory.current.path,
      'native',
      'build',
      Platform.isWindows ? 'windows' : 'linux',
      name,
    ),
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return DynamicLibrary.open(path);
  }
  return DynamicLibrary.open(name);
}

Map<String, Object?> _invokeNative(_NativeRequest request) {
  final bindings = _loadBindings(request.path);
  final result = calloc<_NativeResult>();
  final arguments = <Pointer<Utf8>>[];
  try {
    for (final value in [
      request.source,
      request.stdin,
      request.projectPath,
      request.entryFile,
      request.artifactOutput,
      request.bytecodeFile,
    ]) {
      arguments.add(value.toNativeUtf8(allocator: calloc));
    }
    bindings.run(
      result,
      arguments[0],
      arguments[1],
      request.heapKb,
      arguments[2],
      arguments[3],
      request.compileOnly ? 1 : 0,
      Pointer<Void>.fromAddress(request.tokenAddress),
      arguments[4],
      arguments[5],
    );
    return {
      'exitCode': result.ref.exitCode,
      'output': _decode(result.ref.output),
      'error': result.ref.error == nullptr ? null : _decode(result.ref.error),
      'truncated': result.ref.truncated != 0,
    };
  } finally {
    // The engine owns output/error; the caller owns the struct and arguments.
    try {
      bindings.free(result);
    } finally {
      calloc.free(result);
      for (final argument in arguments) {
        calloc.free(argument);
      }
    }
  }
}

String _decode(Pointer<Utf8> value) => value == nullptr
    ? ''
    : utf8.decode(
        value.cast<Uint8>().asTypedList(value.length),
        allowMalformed: true,
      );
