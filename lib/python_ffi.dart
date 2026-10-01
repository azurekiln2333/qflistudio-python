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
    );
typedef _FreeNative = Void Function(Pointer<_NativeResult>);
typedef _FreeDart = void Function(Pointer<_NativeResult>);
typedef _VersionNative = Pointer<Utf8> Function();
typedef _VersionDart = Pointer<Utf8> Function();

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
        return {'available': true, 'version': version, 'detail': ''};
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
  }) {
    for (final argument in {
      'source': source,
      'stdin': stdin,
      'projectPath': projectPath,
      'entryFile': entryFile,
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
    final path = libraryPath;
    return Isolate.run(
      () => _invokeNative(
        path,
        source,
        stdin,
        heapKb,
        projectPath,
        entryFile,
        compileOnly,
      ),
    );
  }
}

class _Bindings {
  _Bindings(DynamicLibrary library)
    : run = library.lookupFunction<_RunNative, _RunDart>('qfli_py_run_into'),
      free = library.lookupFunction<_FreeNative, _FreeDart>(
        'qfli_py_result_free',
      ),
      version = library.lookupFunction<_VersionNative, _VersionDart>(
        'qfli_py_version',
      );

  final _RunDart run;
  final _FreeDart free;
  final _VersionDart version;
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

Map<String, Object?> _invokeNative(
  String? libraryPath,
  String source,
  String stdin,
  int heapKb,
  String projectPath,
  String entryFile,
  bool compileOnly,
) {
  final bindings = _loadBindings(libraryPath);
  final result = calloc<_NativeResult>();
  final arguments = <Pointer<Utf8>>[];
  try {
    for (final value in [source, stdin, projectPath, entryFile]) {
      arguments.add(value.toNativeUtf8(allocator: calloc));
    }
    bindings.run(
      result,
      arguments[0],
      arguments[1],
      heapKb,
      arguments[2],
      arguments[3],
      compileOnly ? 1 : 0,
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
