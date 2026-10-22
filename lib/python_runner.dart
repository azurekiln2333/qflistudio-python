import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/file_encoding.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

import 'python_ffi.dart';
import 'python_packages.dart';

enum PythonNativeTransport { automatic, methodChannel, ffi }

/// 用内嵌的 MicroPython 执行项目里的 Python 代码。
///
/// 只有一个后端：**原生后端**（`libqfli_py.so`，内嵌 MicroPython）。
/// Android 使用 Kotlin/JNI，鸿蒙使用 ArkTS/NAPI，桌面与 Apple 平台使用 FFI。
/// 具体见 `native/README.md`。
///
/// 为什么没有「纯 Dart 解释器」兜底：MicroPython 是带完整编译器和字节码 VM 的
/// 真实现，语义跟 CPython 对得上；手写一个 Python 子集解释器既保证不了兼容性
/// （浮点、异常层次、生成器、f-string、迭代协议……每一项都是坑），又要长期维护。
/// 所以宁可明确报「这个构建里没有执行后端」，也不给一个「能跑一部分语法、
/// 细节上却跟真 Python 不一致」的东西——那对学习者是负价值。
///
/// 之所以是「解释」而不是「编译」：鸿蒙的普通应用被 SELinux 挡在 `exec` 之外，
/// 既调不动设备上的 python，也拉不起打包在 HAP 里的可执行文件（HNP 那条路要求
/// 应用具备生产力应用资格）。但沙箱从来不限制应用解释自己的数据，所以把源码
/// 交给进程内的 VM，是普通应用唯一走得通的路。
class PythonProgramRunner implements ProgramRunner {
  const PythonProgramRunner({
    this.heapKb = defaultHeapKb,
    this.transport = PythonNativeTransport.automatic,
    this.libraryPath,
    this.packageService,
  });

  final PythonNativeTransport transport;
  final String? libraryPath;
  final PythonPackageService? packageService;

  bool get _useFfi => switch (transport) {
    PythonNativeTransport.automatic =>
      Platform.isWindows ||
          Platform.isLinux ||
          Platform.isIOS ||
          Platform.isMacOS,
    PythonNativeTransport.methodChannel => false,
    PythonNativeTransport.ffi => true,
  };

  /// MicroPython 的 GC 堆大小（KB）。
  ///
  /// 与 `native/src/qfli_py_bridge.c` 的默认值保持一致。太小的话
  /// `[i * i for i in range(100000)]` 这种教学里很常见的写法会立刻 MemoryError；
  /// 太大则「无限往列表里塞」这类错误程序要等很久才撞上内存上限。
  final int heapKb;

  /// 默认 8 MB。
  static const int defaultHeapKb = 8 * 1024;

  /// 标准输入文件名（项目根目录下，存在即生效）。
  ///
  /// 解释器是「先算完再输出」的，没有交互式 stdin 的余地，所以约定用一个文件
  /// 把输入一次性喂进去。MicroPython 的 `input()` 会按行从这个缓冲区里消费。
  static const String stdinFileName = 'input.txt';

  /// 本后端接管的源码后缀。
  static const Set<String> _sourceExtensions = {'.py', '.mpy'};

  /// 与 `native/ohos/QfliPyNative.ets` 里的通道名一致。
  static const MethodChannel _channel = MethodChannel('qfli_py/native');

  Future<PythonCompilationResult> compile({
    required String projectPath,
    required String entryFile,
  }) async {
    if (p.extension(entryFile).toLowerCase() != '.py') {
      return const PythonCompilationResult(error: '请选择 Python 源码文件。');
    }
    final source = _readText(File(entryFile));
    if (source == null) return const PythonCompilationResult(error: '无法读取文件。');
    final probe = await _probeNative();
    if (!probe.available || !probe.supportsArtifacts) {
      return PythonCompilationResult(
        error: probe.detail.isEmpty ? '此运行组件不支持生成 .mpy 文件。' : probe.detail,
      );
    }
    final artifact = p.setExtension(entryFile, '.mpy');
    try {
      final raw = await _invokeNative('compile', {
        'source': source,
        'stdin': '',
        'heapKb': heapKb,
        'projectPath': projectPath,
        'entryFile': entryFile,
        'artifactOutput': artifact,
      });
      if (raw is! Map || raw['exitCode'] is! int) {
        return const PythonCompilationResult(error: '原生运行时返回了意外的结果。');
      }
      final success = raw['exitCode'] == 0;
      return PythonCompilationResult(
        success: success,
        artifactPath: success ? artifact : '',
        error: '${raw['error'] ?? ''}',
        version: probe.version,
      );
    } on MissingPluginException {
      return const PythonCompilationResult(error: 'Python 运行组件不可用。');
    } on PlatformException catch (error) {
      return PythonCompilationResult(error: error.message ?? error.code);
    }
  }

  Future<PythonSyntaxResult> checkSyntax({
    required String projectPath,
    required String entryFile,
  }) async {
    if (p.extension(entryFile).toLowerCase() != '.py') {
      return const PythonSyntaxResult(error: '请选择 Python 文件。');
    }
    final entry = File(entryFile);
    if (!entry.existsSync()) {
      return const PythonSyntaxResult(error: '文件不存在。');
    }
    final source = _readText(entry);
    if (source == null) {
      return const PythonSyntaxResult(error: '无法读取文件。');
    }
    return checkSource(
      projectPath: projectPath,
      entryFile: entryFile,
      source: source,
    );
  }

  /// Compiles the exact supplied buffer without saving it or executing imports.
  Future<PythonSyntaxResult> checkSource({
    required String projectPath,
    required String entryFile,
    required String source,
  }) async {
    final root = p.normalize(p.absolute(projectPath));
    final entry = p.normalize(p.absolute(entryFile));
    if (p.extension(entry).toLowerCase() != '.py') {
      return const PythonSyntaxResult(error: '请选择 Python 源码文件。');
    }
    if (!p.isWithin(root, entry)) {
      return const PythonSyntaxResult(error: '语法检查文件必须位于当前项目中。');
    }
    final probe = await _probeNative();
    if (!probe.available) {
      return PythonSyntaxResult(
        error: probe.detail.isEmpty ? 'Python 运行组件不可用。' : probe.detail,
      );
    }
    try {
      final raw = await _invokeNative('checkSyntax', {
        'source': source,
        'stdin': '',
        'heapKb': heapKb,
        'projectPath': projectPath,
        'entryFile': entryFile,
      });
      if (raw is! Map || raw['exitCode'] is! int) {
        return const PythonSyntaxResult(error: '原生运行时返回了意外的结果。');
      }
      final error = '${raw['error'] ?? ''}'.trim();
      return PythonSyntaxResult(
        success: raw['exitCode'] == 0 && error.isEmpty,
        error: error,
        version: probe.version,
      );
    } on MissingPluginException {
      return const PythonSyntaxResult(error: 'Python 运行组件不可用。');
    } on PlatformException catch (error) {
      return PythonSyntaxResult(error: error.message ?? error.code);
    }
  }

  /// App 自己写的诊断行的前缀。
  ///
  /// 存在的理由：终端面板里同时会显示**程序自己的输出**和**App 的诊断**，
  /// 两者混在一起时，「这行中文是谁说的」会让人困惑——尤其是后端没跑起来、
  /// 一行 Python 输出都没有的时候，满屏都是 App 的提示，看起来像 Python
  /// 在说中文。加上前缀之后，凡是带 `[qfli]` 的都是 App 说的，不带的就是
  /// 程序真实的 stdout/stderr。
  static const String _appPrefix = '[qfli] ';

  /// 「程序根本没跑起来」时用的退出码，直接沿用内核的约定。
  ///
  /// 刻意**不用 1**：终端面板会把非 0 一律渲染成「（运行结束，退出码 N）」，
  /// 用 1 的话「后端没打进 HAP」看起来就成了「程序自己跑完、报错退出 1」——
  /// 这是真机上真实误导过人的一次。原因和取舍写在
  /// `qfli_studio_core/services/studio_profile.dart` 的 [kProgramNotRunExitCode]。
  static const int notRunExitCode = kProgramNotRunExitCode;

  @override
  Future<ProgramRunResult?> run({
    required String projectPath,
    required String entryFile,
  }) async {
    // 不是本语言的文件交回内核（返回 null），内核会走自己的分流逻辑。
    if (!_sourceExtensions.contains(p.extension(entryFile).toLowerCase())) {
      return null;
    }

    final entry = File(entryFile);
    if (!entry.existsSync()) return null;

    final label = commandLabel(projectPath, entryFile);

    final isBytecode = p.extension(entryFile).toLowerCase() == '.mpy';
    final source = isBytecode ? '' : _readText(entry);
    if (source == null) {
      final display = p
          .relative(entryFile, from: projectPath)
          .replaceAll('\\', '/');
      return _failure(label, '$_appPrefix无法读取 $display（编码或权限问题）。');
    }

    // 探测原生后端。每次运行都问一遍而不是缓存：一次通道往返对「按一下运行」
    // 这个频率完全无所谓，而缓存会引入跨运行的可变状态，得不偿失。
    final probe = await _probeNative();
    if (!probe.available) {
      return _notWired(label, probe.detail);
    }
    if (isBytecode && !probe.supportsArtifacts) {
      return _failure(label, '$_appPrefix此运行组件不支持 .mpy 文件。');
    }

    try {
      final preparation = await (packageService ?? PythonPackageService())
          .ensureBundledModules(projectPath);
      if (!preparation.success) {
        return _failure(label, '$_appPrefix${preparation.message}');
      }
    } on Object catch (error) {
      return _failure(label, '$_appPrefix准备离线模块失败：$error');
    }

    if (_useFfi || probe.supportsCancellation || isBytecode) {
      return _runControlled(
        fileName: label,
        source: source,
        stdin: _readStdin(projectPath),
        projectPath: projectPath,
        entryFile: entryFile,
        bytecodeFile: isBytecode ? entryFile : '',
      );
    }
    return _runNative(
      fileName: label,
      source: source,
      stdin: _readStdin(projectPath),
      projectPath: projectPath,
      entryFile: entryFile,
    );
  }

  /// 终端里显示的调用行，形如 `python src/main.py`。
  ///
  /// 只是**展示**：它不是一条真去执行的 shell 命令，也不能被当成命令解析。
  /// 用命令风格是为了让编辑器终端里的运行记录和用户自己敲的命令看起来一致；
  /// 路径是项目相对路径，绝对路径在手机上太长，会把一行挤满。
  /// 入参是绝对路径且项目根目录已知时给出相对路径，否则退回首选的绝对路径。
  /// 含空格或非常规字符的路径用单引号包起来，保证它仍然是「一个可读的参数」，
  /// 而不是让人以为参数被切成了两段。
  static String commandLabel(String projectPath, String entryFile) {
    String display = entryFile;
    if (projectPath.isNotEmpty) {
      final relative = p.relative(entryFile, from: projectPath);
      // p.relative 在跨盘符/无法相对化时会原样返回绝对路径，这时保留绝对路径。
      if (!p.isAbsolute(relative)) display = relative;
    }
    display = display.replaceAll('\\', '/');
    if (display.contains(' ') || display.contains("'")) {
      display = "'${display.replaceAll("'", "'\\''")}'";
    }
    return 'python $display';
  }

  Future<ProgramRunResult> _runControlled({
    required String fileName,
    required String source,
    required String stdin,
    required String projectPath,
    required String entryFile,
    required String bytecodeFile,
  }) async {
    final Future<Object?> pending;
    final Future<void> Function() cancel;
    try {
      if (_useFfi) {
        final execution = PythonFfiBackend(libraryPath: libraryPath).start(
          source: source,
          stdin: stdin,
          heapKb: heapKb,
          projectPath: projectPath,
          entryFile: entryFile,
          bytecodeFile: bytecodeFile,
        );
        pending = execution.result;
        cancel = execution.cancel;
      } else {
        final runId = await _channel.invokeMethod<String>('prepareRun');
        if (runId == null || runId.isEmpty) {
          return _failure(fileName, '$_appPrefix无法创建原生运行句柄。');
        }
        var finished = false;
        pending = _channel
            .invokeMethod<Object?>('run', {
              'source': source,
              'stdin': stdin,
              'heapKb': heapKb,
              'projectPath': projectPath,
              'entryFile': entryFile,
              'runId': runId,
              if (bytecodeFile.isNotEmpty) 'bytecodeFile': bytecodeFile,
            })
            .whenComplete(() => finished = true);
        cancel = () async {
          if (!finished) {
            await _channel.invokeMethod<Object?>('cancel', {'runId': runId});
          }
        };
      }
    } on PythonFfiException catch (error) {
      return _failure(fileName, '$_appPrefix${error.message}');
    } on MissingPluginException {
      return _notWired(fileName, '');
    } on PlatformException catch (error) {
      return _failure(fileName, '$_appPrefix${error.message ?? error.code}');
    }
    final stdout = StreamController<String>();
    final stderr = StreamController<String>();
    final exit = Completer<int>();
    unawaited(_completeControlled(pending, stdout, stderr, exit));
    return ProgramRunResult(
      title: fileName,
      stdout: stdout.stream,
      stderr: stderr.stream,
      exitCode: exit.future,
      cancel: cancel,
    );
  }

  Future<void> _completeControlled(
    Future<Object?> pending,
    StreamController<String> stdout,
    StreamController<String> stderr,
    Completer<int> exit,
  ) async {
    try {
      final raw = await pending;
      if (raw is! Map || raw['exitCode'] is! int) {
        stderr.add('$_appPrefix原生运行时返回了意外的结果。');
        exit.complete(notRunExitCode);
      } else {
        _splitLines('${raw['output'] ?? ''}').forEach(stdout.add);
        final error = '${raw['error'] ?? ''}';
        if (error.isNotEmpty) _splitLines(error).forEach(stderr.add);
        if (raw['truncated'] == true) stderr.add('$_appPrefix输出过长，已被截断。');
        exit.complete(raw['exitCode'] as int);
      }
    } catch (error) {
      final detail = error is PythonFfiException
          ? error.message
          : error is PlatformException
          ? error.message ?? error.code
          : '$error';
      stderr.add('$_appPrefix原生运行时出错：$detail');
      exit.complete(notRunExitCode);
    } finally {
      unawaited(stdout.close());
      unawaited(stderr.close());
    }
  }

  /// 走原生 .so。
  Future<ProgramRunResult> _runNative({
    required String fileName,
    required String source,
    required String stdin,
    required String projectPath,
    required String entryFile,
  }) async {
    final Object? raw;
    try {
      raw = await _invokeNative('run', {
        'source': source,
        'stdin': stdin,
        'heapKb': heapKb,
        'projectPath': projectPath,
        'entryFile': entryFile,
      });
    } on MissingPluginException {
      // 设备上没打进 .so，通道根本不存在。
      return _notWired(fileName, '');
    } on PlatformException catch (error) {
      // 原生后端**存在但执行失败**：把错误显示出来，不静默换后端。
      // 悄悄退回别的执行路径会让用户看到的运行结果和设备的真实行为对不上，
      // 排查问题时会被误导。
      //
      // QFLI_PY_MODULE_MISSING 是 ArkTS 侧专门为「.so 装上了但 dlopen 失败」
      // 留的码，message 本身就是完整解释，不要再套一层「运行时出错」把它埋掉。
      final detail = error.message?.trim() ?? '';
      if (error.code == 'QFLI_PY_MODULE_MISSING' && detail.isNotEmpty) {
        return _failure(fileName, '$_appPrefix$detail');
      }
      return _failure(
        fileName,
        '$_appPrefix原生运行时出错：${detail.isEmpty ? error.code : detail}',
      );
    }

    if (raw is! Map || raw['exitCode'] is! int) {
      return _failure(fileName, '$_appPrefix原生运行时返回了意外的结果。');
    }

    final output = '${raw['output'] ?? ''}';
    final error = raw['error'];
    final truncated = raw['truncated'] == true;

    final stdout = StreamController<String>();
    final stderr = StreamController<String>();
    scheduleMicrotask(() {
      for (final line in _splitLines(output)) {
        stdout.add(line);
      }
      if (error != null && '$error'.trim().isNotEmpty) {
        for (final line in _splitLines('$error')) {
          stderr.add(line);
        }
      }
      if (truncated) {
        // 后面跟的是中文字符，Dart 标识符不含 CJK，花括号可以省；
        // 对比下面 _notWired 里的 '${_appPrefix}Python ...' —— 那里必须留，
        // 否则会被解析成 `_appPrefixPython` 这个变量名。
        stderr.add('$_appPrefix输出过长，已被截断。');
      }
      stdout.close();
      stderr.close();
    });

    return ProgramRunResult(
      title: fileName,
      stdout: stdout.stream,
      stderr: stderr.stream,
      exitCode: Future<int>.value(raw['exitCode'] as int),
    );
  }

  /// 问原生后端「你能不能跑」，并拿回不能跑的原因。
  ///
  /// 公开的运行时信息查询（命令行 `--version`、终端启动横幅这类只读探测用）。
  /// 它**不**读源码、**不**执行任何文件，只走一次 `available` 通道往返；
  /// 版本号来自 `.so` 里的上游 MicroPython 头文件，不是写死的常量。
  ///
  /// 复用自己的 [_probeNative]：其它调用方不要再复制一份探测逻辑，
  /// 否则通道协议变了就会同时出现两个不一致的真相。
  Future<PythonRuntimeInfo> runtimeInfo() async {
    final probe = await _probeNative();
    return PythonRuntimeInfo(
      available: probe.available,
      version: probe.version,
      detail: probe.detail,
      supportsCancellation: probe.supportsCancellation,
      supportsArtifacts: probe.supportsArtifacts,
      transport: _useFfi ? 'ffi' : 'methodChannel',
    );
  }

  /// 问原生后端「你能不能跑」，并拿回不能跑的原因。
  ///
  /// 返回值刻意不是 bool：只说「不可用」没法排查。ArkTS 侧会带上 detail，
  /// 讲清楚是「没打进 HAP」还是「打进去了但加载失败」，两者的修法完全不同。
  Future<_NativeProbe> _probeNative() async {
    try {
      final raw = await _invokeNative('available');
      if (raw is Map) {
        return _NativeProbe(
          available: raw['available'] == true,
          version: '${raw['version'] ?? ''}',
          detail: '${raw['detail'] ?? ''}',
          supportsCancellation: raw['runControl'] == true,
          supportsArtifacts: raw['bytecode'] == true,
        );
      }
      // 兼容只回 bool 的旧接线（两份 QfliPyNative.ets 副本没同步时会走到这里）。
      return _NativeProbe(available: raw == true);
    } on MissingPluginException {
      // 通道不存在 = 这个构建里没打进 .so。是常态，不是错误。
      return const _NativeProbe(available: false);
    } on PlatformException catch (error) {
      return _NativeProbe(
        available: false,
        detail: error.message ?? error.code,
      );
    }
  }

  Future<Object?> _invokeNative(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    if (!_useFfi) return _channel.invokeMethod<Object?>(method, arguments);
    final backend = PythonFfiBackend(libraryPath: libraryPath);
    try {
      if (method == 'available') return await backend.probe();
      return await backend.run(
        source: arguments!['source'] as String,
        stdin: arguments['stdin'] as String,
        heapKb: arguments['heapKb'] as int,
        projectPath: arguments['projectPath'] as String,
        entryFile: arguments['entryFile'] as String,
        compileOnly: method != 'run',
        artifactOutput: arguments['artifactOutput'] as String? ?? '',
        bytecodeFile: arguments['bytecodeFile'] as String? ?? '',
      );
    } on PythonFfiException catch (error) {
      throw PlatformException(code: error.code, message: error.message);
    }
  }

  /// 原生后端不可用时，给用户可执行的恢复建议。
  ProgramRunResult _notWired(String fileName, String detail) {
    final controller = StreamController<String>();
    scheduleMicrotask(() {
      if (detail.isNotEmpty) {
        controller.add('$_appPrefix$detail');
      } else {
        controller.add('${_appPrefix}Python 运行组件不可用，请重新安装应用。');
      }
      controller.close();
    });
    return ProgramRunResult(
      title: fileName,
      stdout: controller.stream,
      stderr: const Stream<String>.empty(),
      exitCode: Future<int>.value(notRunExitCode),
    );
  }

  /// 运行前的失败，包装成一次「立刻结束」的运行结果，让终端面板用统一的方式
  /// 显示，不必为它另开一条错误通道。
  ///
  /// 退出码一律用 [notRunExitCode]：走到这里的所有分支（源码读不出来、原生调用
  /// 抛异常、返回结构不认识）都意味着**程序没有产出结果**，用 1 会跟「程序自己
  /// 退出 1」撞车。
  ProgramRunResult _failure(String fileName, String message) {
    final controller = StreamController<String>();
    scheduleMicrotask(() {
      controller.add(message);
      controller.close();
    });
    return ProgramRunResult(
      title: fileName,
      stdout: const Stream<String>.empty(),
      stderr: controller.stream,
      exitCode: Future<int>.value(notRunExitCode),
    );
  }

  /// 读 [stdinFileName] 作为程序的标准输入。
  ///
  /// 整段原样传下去、**不**按行切：MicroPython 的 `input()` 会自己按行消费，
  /// 而 `sys.stdin.read()` 这种整体读的写法也才成立。
  String _readStdin(String projectPath) {
    final file = File(p.join(projectPath, stdinFileName));
    if (!file.existsSync()) return '';
    return _readText(file) ?? '';
  }

  /// 按内容猜编码读文本：中文注释/字符串在 GBK 下也不会读崩。
  /// 返回 null 表示读不到（文件不存在/无权限），空文件返回空串。
  String? _readText(File file) {
    final List<int> bytes;
    try {
      bytes = file.readAsBytesSync();
    } on FileSystemException {
      return null;
    } on UnsupportedError {
      // 个别平台的 dart:io 在读取特殊文件时会抛这个，按读不到处理。
      return null;
    }
    if (bytes.isEmpty) return '';
    try {
      return TextCodec.byName(TextCodec.detect(bytes)).decode(bytes);
    } on FormatException {
      // 编码猜错时退回宽松 UTF-8（不会抛），尽量把源码跑起来而不是直接报错。
      return TextCodec.utf8.decode(bytes);
    }
  }

  /// 按行切分并去掉行尾的 `\r`（Windows 下编辑过的源码不该把回车带进输出）。
  static List<String> _splitLines(String text) {
    final lines = text.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    return [
      for (final line in lines)
        line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
    ];
  }
}

class PythonSyntaxResult {
  const PythonSyntaxResult({
    this.success = false,
    this.error = '',
    this.version = '',
  });

  final bool success;
  final String error;
  final String version;
}

class PythonCompilationResult extends PythonSyntaxResult {
  const PythonCompilationResult({
    super.success,
    super.error,
    super.version,
    this.artifactPath = '',
  });
  final String artifactPath;
}

/// 一次性运行时信息（`--version` / 启动横幅这类只读探测用）。
///
/// 字段直接来自原生 `available` 的返回，不在这里加工：`available=false` 时的
/// [detail] 就是「没打进 HAP」或「打进去但 dlopen 失败」的原始原因。
class PythonRuntimeInfo {
  const PythonRuntimeInfo({
    required this.available,
    this.version = '',
    this.detail = '',
    this.supportsCancellation = false,
    this.supportsArtifacts = false,
    this.transport = '',
  });

  /// 原生执行模块是否可用。
  final bool available;

  /// MicroPython 版本，形如 `1.24.1 (ecfdd5d)`；拿不到时为空串。
  final String version;

  /// 不可用时的原因；可用时为空串。
  final String detail;

  /// 是否支持运行中取消（决定 Dart 侧走受控还是旧链路）。
  final bool supportsCancellation;

  /// 是否支持编译产物/字节码（`compile` 与 `.mpy` 执行的前提）。
  final bool supportsArtifacts;

  /// 实际走的传输：`ffi` 或 `methodChannel`。
  final String transport;
}

/// 原生后端的探测结果。
class _NativeProbe {
  const _NativeProbe({
    required this.available,
    this.version = '',
    this.detail = '',
    this.supportsCancellation = false,
    this.supportsArtifacts = false,
  });

  /// 模块是否真的可用（不是「文件在不在」，是「dlopen 成没成功」）。
  final bool available;

  /// MicroPython 版本，形如 `1.24.1 (ecfdd5d)`。拿不到时为空串。
  final String version;

  /// 不可用时的原因。可用时为空串。
  final String detail;
  final bool supportsCancellation;
  final bool supportsArtifacts;
}
