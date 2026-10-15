import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_python/main.dart';
import 'package:qfli_python/python_runner.dart';
import 'package:qfli_python/python_terminal.dart';
import 'package:qfli_python/python_tools_page.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/project_config.dart';
import 'package:qfli_studio_core/services/project_templates.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/terminal/shell/sandbox_shell_backend.dart';
import 'package:qfli_studio_core/terminal/shell/shell_backend.dart';

/// Offline storefront regression tests for the Python product.
///
/// Proves the two acceptance criteria the offline audit owns:
///   1. the Python profile exposes **no** reachable online surface, and
///   2. the local terminal and the Python tools page are genuinely reachable —
///      `python main.py` runs on the same embedded MicroPython backend as the
///      Run button, not through a second implementation or a fake.
///
/// The native bridge is stood in for with a MethodChannel mock, exactly as the
/// real `libqfli_py.so` ArkTS/Kotlin side answers. The runner is injected with
/// `transport: methodChannel` so the test never falls through to the Windows
/// FFI path (which would real-spawn/read and hang under the test clock). Real
/// file IO uses plain `test()` bodies or `tester.runAsync`, never the widget
/// fake clock.
const MethodChannel _nativeChannel = MethodChannel('qfli_py/native');

Map<String, Object?> _probe({bool available = true, String version = '1.24.1'}) =>
    {
      'available': available,
      'version': version,
      'detail': '',
      'runControl': true,
      'bytecode': true,
    };

Map<String, Object?> _outcome({
  int exitCode = 0,
  String output = '',
  String error = '',
}) => {
  'exitCode': exitCode,
  'output': output,
  'error': error,
  'truncated': false,
};

void installNative(Future<Object?> Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_nativeChannel, handler);
}

void clearNative() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_nativeChannel, null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StudioProfile? previousProfile;

  setUp(() {
    previousProfile = StudioProfile.current;
    StudioProfile.current = pythonProfile;
  });

  tearDown(() {
    StudioProfile.current = previousProfile;
    clearNative();
  });

  group('档位的离线策略', () {
    test('isOffline 打开，使 offlineOnly 自动为 true', () {
      expect(pythonProfile.isOffline, isTrue);
      // 共享内核在未显式传 offlineOnly 时按 isOffline 推导 —— 这是「所有本地
      // 语言 App 自动拿到离线待遇」的唯一开关，必须为 true。
      expect(pythonProfile.offlineOnly, isTrue);
    });

    test('只放行空项目与 Python 模板，不泄漏其他语言入口', () {
      expect(pythonProfile.filterTemplates(ProjectTemplate.values), [
        ProjectTemplate.empty,
        ProjectTemplate.python,
      ]);
    });
  });

  group('本地终端与 Python tools 可达', () {
    late Directory project;

    setUp(() {
      project = Directory.systemTemp.createTempSync('qfli_python_offline');
    });

    tearDown(() {
      if (project.existsSync()) project.deleteSync(recursive: true);
    });

    File write(String relative, String content) {
      final file = File(p.join(project.path, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
      return file;
    }

    /// The exact backend both terminal surfaces build: the standalone page
    /// (terminax_terminal_page.dart) and the editor pane (terminal_pane.dart)
    /// both construct it and set the profile's `terminalCommandDelegate`.
    ///
    /// The delegate is built here with an explicit `methodChannel` runner so
    /// the native mock installed by the test is the only backend consulted.
    SandboxShellBackend backend({String? startDirectory}) {
      const runner = PythonProgramRunner(
        transport: PythonNativeTransport.methodChannel,
      );
      return SandboxShellBackend(
        sandboxRoot: project.path,
        startDirectory: startDirectory ?? project.path,
        delegate: (shell, command) =>
            pythonTerminalDelegate(shell, command, runner: runner),
      );
    }

    /// Captured terminal output split by channel, plus the backend exit status.
    Future<({List<String> stdout, List<String> stderr, int? exitCode})> run(
      SandboxShellBackend shell,
      String command,
    ) async {
      final stdout = <String>[];
      final stderr = <String>[];
      final subscription = shell.output.listen((chunk) {
        final text = chunk.text.replaceAll('\r\n', '\n').trimRight();
        if (text.isEmpty) return;
        switch (chunk.kind) {
          case OutputKind.stdout:
            stdout.add(text);
          case OutputKind.stderr:
            stderr.add(text);
          case OutputKind.system:
          case OutputKind.control:
            break;
        }
      });
      await shell.execute(command);
      await subscription.cancel();
      return (stdout: stdout, stderr: stderr, exitCode: shell.lastExitCode);
    }

    test('档位注册了终端命令挂钩（两个终端都靠它）', () {
      expect(pythonProfile.terminalCommandDelegate, isNotNull);
    });

    test('python main.py 真的跑内嵌后端并回传输出与退出码', () async {
      write('main.py', 'print("hello from main")');
      final calls = <MethodCall>[];
      installNative((call) async {
        calls.add(call);
        switch (call.method) {
          case 'available':
            return _probe();
          case 'prepareRun':
            return 'offline-run';
          case 'run':
            final args = call.arguments as Map;
            expect(args['entryFile'], p.join(project.path, 'main.py'));
            expect(args['projectPath'], project.path);
            expect(args['source'], contains('hello from main'));
            return _outcome(output: 'hello from main\n');
        }
        fail('unexpected native call ${call.method}');
      });

      final output = await run(backend(), 'python main.py');

      expect(output.stdout.join('\n'), contains('hello from main'));
      expect(output.stderr, isEmpty);
      expect(output.exitCode, 0);
      // 走的是与运行按钮同一条探测→执行路径，不是第二套实现。
      expect(calls.map((call) => call.method), [
        'available',
        'prepareRun',
        'run',
      ]);
    });

    test('input.txt 按项目约定喂给解释器', () async {
      write('main.py', 'name = input()\nprint(name)');
      write('input.txt', '小明\n');
      String? seenStdin;
      installNative((call) async {
        if (call.method == 'available') return _probe();
        if (call.method == 'prepareRun') return 'offline-run';
        seenStdin = (call.arguments as Map)['stdin'] as String?;
        return _outcome(output: '小明\n');
      });

      final output = await run(backend(), 'python main.py');

      expect(seenStdin, '小明\n');
      expect(output.stdout.join('\n'), contains('小明'));
    });

    test('嵌套 src/main.py 仍以项目根取 input.txt（与运行按钮等价）', () async {
      // 项目根标记 `.qfli/project.json`，入口在 src/ 下，input.txt 在根目录。
      // 若以脚本目录当项目根，input.txt 就会读不到 —— 这条测试钉住项目根解析。
      await ProjectConfig.write(
        projectRoot: project.path,
        name: 'Demo',
        language: 'Python',
        type: 'python',
        entryFile: 'src/main.py',
      );
      write('src/main.py', 'print(input())');
      write('input.txt', 'root-level-input\n');
      Map<String, Object?>? seen;
      installNative((call) async {
        switch (call.method) {
          case 'available':
            return _probe();
          case 'prepareRun':
            return 'offline-run';
          case 'run':
            seen = Map<String, Object?>.from(call.arguments as Map);
            return _outcome(output: 'root-level-input\n');
        }
        fail('unexpected ${call.method}');
      });

      final shell = backend(startDirectory: p.join(project.path, 'src'));
      final output = await run(shell, 'python main.py');

      expect(seen, isNotNull);
      expect(seen!['projectPath'], project.path, reason: '项目根必须是含 .qfli 的目录');
      expect(seen!['entryFile'], p.join(project.path, 'src', 'main.py'));
      expect(seen!['stdin'], 'root-level-input\n');
      expect(output.stdout.join('\n'), contains('root-level-input'));
    });

    test('项目根解析不越出沙盒（不认领沙盒外项目的 .qfli）', () async {
      // 沙盒根是 outer/inner；`.qfli` 只存在于外层 outer。脚本在 inner 下，
      // 解析必须止步于沙盒根 inner，退回 cwd/脚本目录，绝不能采用 outer 的标记。
      final outer = Directory(p.join(project.path, 'outer'))..createSync();
      final inner = Directory(p.join(outer.path, 'inner'))..createSync();
      await ProjectConfig.write(
        projectRoot: outer.path,
        name: 'Outer',
        language: 'Python',
        type: 'python',
      );
      final script = File(p.join(inner.path, 'main.py'))
        ..writeAsStringSync('print(1)');

      expect(
        projectRootForScript(script.path, inner.path,
            workingDirectory: inner.path),
        inner.path,
        reason: '不得采用沙盒外的 .qfli',
      );
    });

    test('未标记项目根 + 嵌套脚本：以 cwd 为根读根 input.txt', () async {
      // 场景：用户把未标记的目录当项目（cd 进去后 python src/main.py）。
      // 与按钮语义一致：根 input.txt 在 cwd 下，而不是脚本所在的 src/。
      write('src/main.py', 'print(input())');
      write('input.txt', 'cwd-root-input\n');
      Map<String, Object?>? seen;
      installNative((call) async {
        switch (call.method) {
          case 'available':
            return _probe();
          case 'prepareRun':
            return 'offline-run';
          case 'run':
            seen = Map<String, Object?>.from(call.arguments as Map);
            return _outcome(output: 'cwd-root-input\n');
        }
        fail('unexpected ${call.method}');
      });

      // cwd = 项目根（未标记），脚本在 src/ 下。
      final output = await run(backend(), 'python src/main.py');

      expect(seen, isNotNull);
      expect(seen!['projectPath'], project.path, reason: '无标记时以 cwd 为根');
      expect(seen!['stdin'], 'cwd-root-input\n');
      expect(output.stdout.join('\n'), contains('cwd-root-input'));
      expect(output.exitCode, 0);
    });

    test('cd 到 src 后 cwd 即 src：此时根就是 src', () async {
      // 自然 cwd 语义：cd src; python main.py 时，input.txt 从 src 读。
      write('src/main.py', 'print(input())');
      write('src/input.txt', 'src-input\n');
      write('input.txt', 'root-input-should-not-be-used\n');
      Map<String, Object?>? seen;
      installNative((call) async {
        switch (call.method) {
          case 'available':
            return _probe();
          case 'prepareRun':
            return 'offline-run';
          case 'run':
            seen = Map<String, Object?>.from(call.arguments as Map);
            return _outcome(output: 'src-input\n');
        }
        fail('unexpected ${call.method}');
      });

      final shell = backend();
      final cd = await run(shell, 'cd src');
      expect(cd.exitCode, anyOf(isNull, 0));
      final output = await run(shell, 'python main.py');

      expect(seen!['projectPath'], p.join(project.path, 'src'));
      expect(seen!['stdin'], 'src-input\n');
      expect(output.stdout.join('\n'), contains('src-input'));
    });

    test('有 in-sandbox marker 时 marker 优先于 cwd', () async {
      // 项目根有 .qfli，cwd 却在子目录：仍以 marker 所在目录为根。
      await ProjectConfig.write(
        projectRoot: project.path,
        name: 'Marked',
        language: 'Python',
        type: 'python',
      );
      write('src/main.py', 'print(input())');
      write('input.txt', 'marked-root-input\n');
      Map<String, Object?>? seen;
      installNative((call) async {
        switch (call.method) {
          case 'available':
            return _probe();
          case 'prepareRun':
            return 'offline-run';
          case 'run':
            seen = Map<String, Object?>.from(call.arguments as Map);
            return _outcome(output: 'marked-root-input\n');
        }
        fail('unexpected ${call.method}');
      });

      // cwd = src（子目录），但 marker 在项目根。
      final output = await run(
        backend(startDirectory: p.join(project.path, 'src')),
        'python main.py',
      );

      expect(seen!['projectPath'], project.path, reason: 'marker 优先');
      expect(seen!['stdin'], 'marked-root-input\n');
      expect(output.stdout.join('\n'), contains('marked-root-input'));
    });

    test('脚本在子目录时按当前工作目录解析路径', () async {
      write('src/app.py', 'print("nested")');
      installNative((call) async {
        switch (call.method) {
          case 'available':
            return _probe();
          case 'prepareRun':
            return 'offline-run';
          case 'run':
            expect(
              (call.arguments as Map)['entryFile'],
              p.join(project.path, 'src', 'app.py'),
            );
            return _outcome(output: 'nested\n');
        }
        fail('unexpected ${call.method}');
      });

      final shell = backend(startDirectory: p.join(project.path, 'src'));
      final output = await run(shell, 'python app.py');

      expect(output.stdout.join('\n'), contains('nested'));
    });

    test('python3 / micropython 是同一后端', () async {
      write('main.py', 'print(1)');
      installNative((call) async {
        switch (call.method) {
          case 'available':
            return _probe();
          case 'prepareRun':
            return 'offline-run';
          case 'run':
            return _outcome(output: '1\n');
        }
        fail('unexpected ${call.method}');
      });

      for (final tool in ['python', 'python3', 'micropython']) {
        final output = await run(backend(), '$tool main.py');
        expect(output.stdout.join('\n'), contains('1'), reason: tool);
        expect(output.exitCode, 0, reason: tool);
        expect(output.stderr.join('\n'), isNot(contains('不支持该命令')));
      }
    });

    test('缺少脚本时给出可读提示，而不是假装支持 REPL', () async {
      final output = await run(backend(), 'python');
      expect(output.stdout, isEmpty);
      expect(output.stderr.join('\n'), contains('需要显式脚本路径'));
      expect(output.stderr.join('\n'), isNot(contains('不支持该命令')));
      expect(output.exitCode, kProgramNotRunExitCode);
    });

    test('额外脚本参数被明确拒绝，不静默丢弃（无 sys.argv 契约）', () async {
      write('main.py', 'import sys\nprint(sys.argv)');
      var nativeCalled = false;
      installNative((call) async {
        nativeCalled = true;
        return _probe();
      });

      final output = await run(backend(), 'python main.py extra --flag');
      final text = output.stderr.join('\n');

      expect(nativeCalled, isFalse, reason: '不该带着被丢弃的参数去执行');
      expect(output.stdout, isEmpty);
      expect(text, contains('暂不支持脚本参数'));
      expect(text, contains('extra --flag'));
      expect(text, contains('input.txt'));
      expect(output.exitCode, kProgramNotRunExitCode);
    });

    test('-m / -c 诚实提示，不假装运行', () async {
      var nativeCalled = false;
      installNative((call) async {
        nativeCalled = true;
        return _probe();
      });
      final shell = backend();
      final m = await run(shell, 'python -m http.server');
      expect(m.stderr.join('\n'), contains('暂不支持 -m'));
      expect(m.exitCode, kProgramNotRunExitCode);
      final c = await run(shell, 'python -c print(1)');
      expect(c.stderr.join('\n'), contains('暂不支持 -c'));
      expect(c.exitCode, kProgramNotRunExitCode);
      expect(nativeCalled, isFalse);
    });

    test('--version 显示真实探测到的 VM 版本', () async {
      // 注入真实的探测源（生产里由 runner 的公开 API 提供）。这里返回一个
      // 明确的版本串，断言终端原样显示它，而不是自己编一个。
      const runner = PythonProgramRunner(
        transport: PythonNativeTransport.methodChannel,
      );
      installNative((call) async {
        expect(call.method, isNot('run'));
        return _probe(version: '9.9.9 (probe)');
      });
      final shell = SandboxShellBackend(
        sandboxRoot: project.path,
        startDirectory: project.path,
        delegate: (backend, command) => pythonTerminalDelegate(
          backend,
          command,
          runner: runner,
          probeSource: () async => const PythonRuntimeInfo(
            available: true,
            version: '9.9.9 (probe)',
          ),
        ),
      );

      final output = await run(shell, 'python --version');
      expect(output.stdout.join('\n'), contains('MicroPython 9.9.9 (probe)'));
      expect(output.stderr, isEmpty);
      expect(output.exitCode, 0);
    });

    test('--version 后端不可用时给诚实诊断，不编造版本', () async {
      const runner = PythonProgramRunner(
        transport: PythonNativeTransport.methodChannel,
      );
      installNative((call) async => _probe());

      final shell = SandboxShellBackend(
        sandboxRoot: project.path,
        startDirectory: project.path,
        delegate: (backend, command) => pythonTerminalDelegate(
          backend,
          command,
          runner: runner,
          probeSource: () async => const PythonRuntimeInfo(
            available: false,
            detail: 'libqfli_py.so 没能加载。',
          ),
        ),
      );

      final output = await run(shell, 'python --version');
      expect(output.stdout, isEmpty);
      expect(output.stderr.join('\n'), contains('libqfli_py.so 没能加载'));
      expect(output.stderr.join('\n'), isNot(contains('9.9')));
      expect(output.exitCode, kProgramNotRunExitCode);
    });

    test('--version 默认走 runner.runtimeInfo（真实探测，不是本地常量）', () async {
      // 生产默认走 runner.runtimeInfo（同名公开 API）；这里用 methodChannel
      // runner + 真实 mock 证明它真的读到了通道返回值，而不是自己编一个。
      const runner = PythonProgramRunner(
        transport: PythonNativeTransport.methodChannel,
      );
      installNative((call) async => _probe(version: '3.4.5 (real)'));
      final shell = SandboxShellBackend(
        sandboxRoot: project.path,
        startDirectory: project.path,
        delegate: (backend, command) =>
            pythonTerminalDelegate(backend, command, runner: runner),
      );
      final output = await run(shell, 'python --version');
      expect(output.stdout.join('\n'), contains('MicroPython 3.4.5 (real)'),
          reason: '必须来自真实探测');
      expect(output.exitCode, 0);
    });

    test('--version 后端可报告空版本时为失败，不编造', () async {
      const runner = PythonProgramRunner(
        transport: PythonNativeTransport.methodChannel,
      );
      installNative((call) async => _probe(version: ''));
      final shell = SandboxShellBackend(
        sandboxRoot: project.path,
        startDirectory: project.path,
        delegate: (backend, command) => pythonTerminalDelegate(
          backend,
          command,
          runner: runner,
          probeSource: () async =>
              const PythonRuntimeInfo(available: true),
        ),
      );

      final output = await run(shell, 'python --version');
      expect(output.stdout, isEmpty);
      expect(output.stderr.join('\n'), contains('未报告 MicroPython 版本'));
      expect(output.exitCode, kProgramNotRunExitCode);
    });

    test('-V 与 --version 一致', () async {
      installNative((call) async => _probe(version: '1.2.3'));
      final shell = backend();
      final output = await run(shell, 'python -V');
      expect(output.stdout.join('\n'), contains('MicroPython 1.2.3'));
      expect(output.exitCode, 0);
    });

    test('找不到文件 / 越出沙盒 / 非 Python 文件都会明确报错', () async {
      write('notes.txt', 'x');
      final shell = backend();
      final missing = await run(shell, 'python missing.py');
      expect(missing.stderr.join('\n'), contains('找不到文件'));
      expect(missing.exitCode, kProgramNotRunExitCode);
      final nonPython = await run(shell, 'python notes.txt');
      expect(nonPython.stderr.join('\n'), contains('只能执行 .py / .mpy'));
      final escape = await run(shell, 'python ../../../escape.py');
      expect(escape.stderr.join('\n'), contains('不能越出沙盒目录'));
      expect(escape.exitCode, kProgramNotRunExitCode);
    });

    test('管道/重定向等 shell 语法交回沙盒，不被误读为参数', () async {
      write('main.py', 'print(1)');
      var nativeCalled = false;
      installNative((call) async {
        nativeCalled = true;
        return _probe();
      });

      final output = await run(backend(), 'python main.py | grep 1');

      expect(nativeCalled, isFalse, reason: '复合命令行不该被认领为 python 执行');
      expect(output.stderr.join('\n'), contains('管道'));
    });

    test('非本 App 的命令仍交回沙盒', () async {
      final output = await run(backend(), 'gcc main.c');
      expect(output.stderr.join('\n'), isNotEmpty);
    });

    test('后端不可用时终端如实报错，不静默换后端', () async {
      write('main.py', 'print(1)');
      installNative((call) async {
        if (call.method == 'available') {
          return {
            'available': false,
            'version': '',
            'detail': 'libqfli_py.so 没能加载。',
          };
        }
        fail('模块不可用时不该调用 ${call.method}');
      });

      final output = await run(backend(), 'python main.py');
      expect(output.stdout.join('\n'), contains('libqfli_py.so 没能加载'));
      expect(output.exitCode, kProgramNotRunExitCode);
    });

    testWidgets('Python tools 页面由档位提供且可构建', (tester) async {
      write('main.py', 'print(42)');
      final registry = File(p.join(project.path, 'projects.json'));
      registry.writeAsStringSync(
        jsonEncode({
          'projects': [
            Project.create(name: 'Demo', path: project.path).toJson(),
          ],
        }),
      );
      final store = ProjectStore(storageFile: registry);
      addTearDown(store.dispose);

      final builder = pythonProfile.toolsPageBuilder;
      expect(builder, isNotNull);

      await tester.runAsync(() async {
        await store.load();
        await tester.pumpWidget(MaterialApp(home: builder!(store)));
        // Bounded real-time polling: the page scans the project, which is real
        // IO that the fake clock cannot advance.
        for (var attempt = 0; attempt < 200; attempt++) {
          await tester.pump();
          if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();

      expect(find.byType(PythonToolsPage), findsOneWidget);
      expect(find.text('Python 工具'), findsOneWidget);
      // 项目里真实存在的 Python 文件被发现，工具可达。
      expect(find.text('main.py', skipOffstage: false), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    test('终端执行确实触达原生通道（不是纯本地桩）', () async {
      write('main.py', 'print("x")');
      var runSeen = false;
      installNative((call) async {
        switch (call.method) {
          case 'available':
            return _probe();
          case 'prepareRun':
            return 'offline-run';
          case 'run':
            runSeen = true;
            return _outcome(output: 'x\n');
        }
        return null;
      });

      await run(backend(), 'python main.py');
      expect(runSeen, isTrue);
    });
  });

  group('离线项目可见性（PythonToolsPage 排除云端）', () {
    testWidgets('PythonToolsPage 只列本地项目', (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'qfli_python_offline_projects',
      );
      addTearDown(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
      File(p.join(directory.path, 'main.py')).writeAsStringSync('print(1)');
      final cloudDirectory = Directory(p.join(directory.path, 'cloud'))
        ..createSync();
      final local = Project.create(name: 'Local', path: directory.path);
      final cloud = Project.create(
        name: 'Cloud',
        path: cloudDirectory.path,
        cloudId: 'c1',
      );
      final registry = File(p.join(directory.path, 'projects.json'));
      registry.writeAsStringSync(
        jsonEncode({
          'projects': [local.toJson(), cloud.toJson()],
        }),
      );
      final store = ProjectStore(storageFile: registry);
      addTearDown(store.dispose);

      await tester.runAsync(() async {
        await store.load();
        await tester.pumpWidget(
          MaterialApp(home: PythonToolsPage(store: store)),
        );
        for (var attempt = 0; attempt < 200; attempt++) {
          await tester.pump();
          if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();

      // 云端项目（哪怕是当前存档里的）不出现在工具页的项目下拉里。
      expect(find.text('Cloud', skipOffstage: false), findsNothing);
      expect(find.text('Local', skipOffstage: false), findsWidgets);
    });
  });
}
