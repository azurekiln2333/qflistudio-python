import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Opens the same packaged VM used by the product's native run transport.
/// Mobile debug uses its exported C ABI; ordinary runs keep their channel path.
DynamicLibrary openPythonNativeLibrary(String? explicitPath) {
  if (explicitPath != null) return DynamicLibrary.open(explicitPath);
  if (Platform.isIOS || Platform.isMacOS) return DynamicLibrary.process();
  if (Platform.isAndroid || Platform.operatingSystem == 'ohos') {
    return DynamicLibrary.open('libqfli_py.so');
  }
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
