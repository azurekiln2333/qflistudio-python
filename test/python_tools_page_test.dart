import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_python/main.dart';
import 'package:qfli_python/python_runner.dart';
import 'package:qfli_python/python_tools_page.dart';
import 'package:qfli_studio_core/app.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/pages/home_page.dart';
import 'package:qfli_studio_core/pages/offline_tool_pages.dart';
import 'package:qfli_studio_core/pages/quick_tools_page.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/app_restore_gate.dart';
import 'package:qfli_studio_core/services/picker_service.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/services/task_activity_service.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

void main() {
  const channel = MethodChannel('qfli_py/native');
  late Directory directory;
  late ProjectStore store;

  setUp(() async {
    // Asset futures belong to each widget test's async zone.
    rootBundle.clear();
    directory = Directory.systemTemp.createTempSync('qfli_python_tools');
    final source = File(p.join(directory.path, 'src', 'main.py'));
    source.parent.createSync(recursive: true);
    source.writeAsStringSync('print(42)');
    final project = Project.create(
      name: 'My Python Project',
      path: directory.path,
    );
    final registry = File(p.join(directory.path, 'registry.json'));
    registry.writeAsStringSync(
      jsonEncode({
        'projects': [project.toJson()],
      }),
    );
    store = ProjectStore(storageFile: registry);
    await store.load();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('qflistudio/platform'),
          null,
        );
    PickerService.forcePlatformChannel = false;
    store.dispose();
    directory.deleteSync(recursive: true);
  });

  for (final size in [const Size(360, 800), const Size(1200, 800)]) {
    testWidgets('tools tab exposes Python controls directly at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previousProfile = StudioProfile.current;
      StudioProfile.current = pythonProfile;
      addTearDown(() => StudioProfile.current = previousProfile);
      var terminalTaps = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: FunctionsTab(
            store: store,
            onOpenTerminal: () => terminalTaps++,
            onOpenContentTool: () => fail('Python must use its own tools tab'),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('专用'), findsNothing);
      expect(find.text('功能'), findsNothing);
      expect(find.text('Python'), findsOneWidget);
      await tester.tap(find.text('终端'));
      expect(terminalTaps, 1);

      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('检查与运行'), findsNothing);
      expect(find.byType(PythonToolsPage), findsNothing);
      expect(find.byType(PythonToolsBody), findsOneWidget);
      expect(
        tester.widget<PythonToolsBody>(find.byType(PythonToolsBody)).store,
        same(store),
      );
      expect(find.text('My Python Project'), findsOneWidget);
      expect(find.text('src${p.separator}main.py'), findsOneWidget);
      expect(find.text('检查语法'), findsOneWidget);
      expect(find.byTooltip('编译'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '运行'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text(Base64ToolPage.title),
        200,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(Base64ToolPage.title));
      await tester.pumpAndSettle();
      expect(find.byType(Base64ToolPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('compile and stop workflow at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<Object?>();
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            switch (call.method) {
              case 'available':
                return {
                  'available': true,
                  'runControl': true,
                  'bytecode': true,
                };
              case 'compile':
                File(
                  (call.arguments as Map)['artifactOutput'] as String,
                ).writeAsBytesSync([77, 6, 0, 31]);
                return {'exitCode': 0};
              case 'prepareRun':
                return 'tools-run';
              case 'run':
                return pending.future;
              case 'cancel':
                expect((call.arguments as Map)['runId'], 'tools-run');
                pending.complete({
                  'exitCode': 130,
                  'output': 'before\n',
                  'error': 'KeyboardInterrupt\n',
                });
                return true;
            }
            return null;
          });
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: PythonToolsPage(
              store: store,
              runner: const PythonProgramRunner(
                transport: PythonNativeTransport.methodChannel,
              ),
            ),
          ),
        );
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.pump();
          if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.tap(find.byTooltip('编译'));
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.pump();
          if (find.text('编译完成').evaluate().isNotEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('编译完成'), findsOneWidget);
      expect(
        File(p.join(directory.path, 'src', 'main.mpy')).existsSync(),
        isTrue,
      );
      await tester.tap(find.widgetWithText(FilledButton, '运行'));
      await _pumpUntil(tester, () => calls.any((call) => call.method == 'run'));
      expect(pending.isCompleted, isFalse);
      await tester.tap(find.byTooltip('停止运行'));
      await _pumpUntil(
        tester,
        () => find.text('运行结束 · 退出码 130').evaluate().isNotEmpty,
      );
      expect(find.text('运行结束 · 退出码 130'), findsOneWidget);
      expect(find.text('before'), findsOneWidget);
      expect(find.text('KeyboardInterrupt'), findsOneWidget);
      expect(find.text('标准输出 / 编译产物'), findsOneWidget);
      expect(find.text('标准错误 / 诊断'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(calls.map((call) => call.method), [
        'available',
        'compile',
        'available',
        'prepareRun',
        'run',
        'cancel',
      ]);
    });
    testWidgets('syntax workflow at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'available') {
              return {'available': true, 'version': '1.24.1', 'detail': ''};
            }
            return {
              'exitCode': 0,
              'error': null,
              'output': call.method == 'run' ? '42\n' : '',
              'truncated': false,
            };
          });

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: PythonToolsPage(
              store: store,
              runner: const PythonProgramRunner(
                transport: PythonNativeTransport.methodChannel,
              ),
            ),
          ),
        );
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.pump();
          if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('src${p.separator}main.py'), findsOneWidget);
      await tester.tap(find.text('检查语法'));
      await tester.pumpAndSettle();
      expect(find.text('语法检查通过'), findsOneWidget);
      expect(calls.map((call) => call.method), ['available', 'checkSyntax']);
      expect(
        (calls.last.arguments as Map)['entryFile'],
        p.join(directory.path, 'src', 'main.py'),
      );
      await tester.tap(find.widgetWithText(FilledButton, '运行'));
      await _pumpUntil(
        tester,
        () => find.text('运行结束 · 退出码 0').evaluate().isNotEmpty,
      );
      expect(find.text('运行结束 · 退出码 0'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(calls.map((call) => call.method), [
        'available',
        'checkSyntax',
        'available',
        'run',
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'real VM directory package check install show remove at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final sources = Directory(
          p.join(directory.path, 'z_sources', 'local_stats'),
        )..createSync(recursive: true);
        File(
          p.join(sources.path, '__init__.py'),
        ).writeAsStringSync('from .summary import describe\n');
        File(p.join(sources.path, 'summary.py')).writeAsStringSync(
          'import statistics\ndef describe(values):\n    return (len(values), statistics.mean(values))\n',
        );
        File(p.join(directory.path, 'src', 'main.py')).writeAsStringSync(
          'from local_stats import describe\nprint(describe([2, 4, 6]) == (3, 4))\n',
        );
        await _mountTools(tester, store);
        await _expandPackages(tester);
        await tester.enterText(
          find.byKey(const ValueKey('python-package-source')),
          sources.path,
        );
        await _tapVisible(tester, find.text('检查兼容性'));
        await _pumpUntil(
          tester,
          () => find.text('兼容性检查通过').evaluate().isNotEmpty,
        );
        expect(
          File(
            p.join(directory.path, 'lib', 'local_stats', '__init__.py'),
          ).existsSync(),
          isFalse,
        );
        await _tapVisible(tester, find.text('安装到项目'));
        await _pumpUntil(
          tester,
          () =>
              find.text('本地包安装完成').evaluate().isNotEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        expect(
          File(
            p.join(directory.path, 'lib', 'local_stats', '__init__.py'),
          ).readAsStringSync(),
          contains('describe'),
        );
        // Run the installed package and its bundled dependency in the actual VM.
        await _tapVisible(tester, find.widgetWithText(FilledButton, '运行'));
        await _pumpUntil(
          tester,
          () => find.text('运行结束 · 退出码 0').evaluate().isNotEmpty,
        );
        expect(find.text('True'), findsOneWidget);
        expect(find.text('标准错误 / 诊断'), findsNothing);
        await _tapVisible(tester, find.text('详情 local-stats'));
        await _pumpUntil(
          tester,
          () => find.text('包详情 · local-stats').evaluate().isNotEmpty,
        );
        expect(find.textContaining('SHA256'), findsOneWidget);
        final modified = File(
          p.join(directory.path, 'lib', 'local_stats', 'summary.py'),
        )..writeAsStringSync('# local change\n');
        await _tapVisible(tester, find.text('移除 local-stats'));
        await _pumpUntil(
          tester,
          () =>
              find.text('本地包移除完成').evaluate().isNotEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        expect(modified.readAsStringSync(), '# local change\n');
        expect(
          File(
            p.join(directory.path, 'lib', 'local_stats', '__init__.py'),
          ).existsSync(),
          isFalse,
        );
        expect(find.textContaining('保留的已修改文件：'), findsOneWidget);
        expect(find.text('当前项目没有已安装的本地包'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      skip: !File(
        p.join('native', 'build', 'windows', 'qfli_py_ffi.dll'),
      ).existsSync(),
    );
  }

  testWidgets(
    'real VM pure source wheel is imported through URI picker and cleaned on disposal',
    (tester) async {
      final archive = Archive()
        ..add(
          ArchiveFile.string(
            'wheelmath.py',
            'def squares(values):\n    return [value * value for value in values]\n',
          ),
        )
        ..add(
          ArchiveFile.string(
            'wheelmath-1.0.dist-info/WHEEL',
            'Wheel-Version: 1.0\nRoot-Is-Purelib: true\nTag: py3-none-any\n',
          ),
        )
        ..add(
          ArchiveFile.string(
            'wheelmath-1.0.dist-info/METADATA',
            'Metadata-Version: 2.1\nName: wheelmath\nVersion: 1.0\n',
          ),
        );
      final bytes = ZipEncoder().encode(archive);
      File(p.join(directory.path, 'src', 'main.py')).writeAsStringSync(
        'from wheelmath import squares\nprint(squares([2, 3, 4]))\n',
      );
      PickerService.forcePlatformChannel = true;
      final pickerCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('qflistudio/platform'),
            (call) async {
              pickerCalls.add(call);
              if (call.method == 'pickDocument') {
                return {
                  'uri': 'content://offline/wheelmath.whl',
                  'name': 'wheelmath-1.0-py3-none-any.whl',
                };
              }
              if (call.method == 'readUri') return bytes;
              return null;
            },
          );
      await _mountTools(tester, store);
      await _expandPackages(tester);
      await _tapVisible(tester, find.text('选择包文件'));
      await _pumpUntil(
        tester,
        () => find.text('已选择本地文件').evaluate().isNotEmpty,
      );
      final sourcePath = tester
          .widget<TextField>(
            find.byKey(const ValueKey('python-package-source')),
          )
          .controller!
          .text;
      expect(File(sourcePath).existsSync(), isTrue);
      expect(pickerCalls.map((call) => call.method), [
        'pickDocument',
        'readUri',
      ]);
      await _tapVisible(tester, find.text('安装到项目'));
      await _pumpUntil(
        tester,
        () =>
            find.text('本地包安装完成').evaluate().isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      expect(find.text('wheelmath 1.0 · 1 个文件'), findsOneWidget);
      await _tapVisible(tester, find.widgetWithText(FilledButton, '运行'));
      await _pumpUntil(
        tester,
        () => find.text('运行结束 · 退出码 0').evaluate().isNotEmpty,
      );
      expect(find.text('[4, 9, 16]'), findsOneWidget);
      expect(find.text('标准错误 / 诊断'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(File(sourcePath).existsSync(), isFalse);
      expect(tester.takeException(), isNull);
    },
    skip: !File(
      p.join('native', 'build', 'windows', 'qfli_py_ffi.dll'),
    ).existsSync(),
  );

  testWidgets('late stop failure preserves completed run', (tester) async {
    final runner = _LateStopRunner();
    await _mountTools(tester, store, runner: runner);
    final stop = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == '停止运行',
    );
    await tester.tap(find.widgetWithText(FilledButton, '运行'));
    await _pumpUntil(
      tester,
      () => tester.widget<IconButton>(stop).onPressed != null,
    );
    await tester.tap(stop);
    await _pumpUntil(tester, () => runner.cancelRequested);
    runner.finish();
    await _pumpUntil(
      tester,
      () => find.text('运行结束 · 退出码 0').evaluate().isNotEmpty,
    );
    runner.cancellation.completeError(
      PlatformException(code: 'LATE_STOP_FAILURE', message: 'late stop failed'),
    );
    await tester.pumpAndSettle();
    expect(find.text('运行结束 · 退出码 0'), findsOneWidget);
    expect(find.text('finished output'), findsOneWidget);
    expect(find.textContaining('late stop failed'), findsNothing);
    expect(tester.widget<IconButton>(stop).onPressed, isNull);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '运行'))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'package incompatibility and missing path retain real service errors without executing source',
    (tester) async {
      final source = File(
        p.join(directory.path, 'z_sources', 'unsupported.py'),
      );
      source.parent.createSync(recursive: true);
      source.writeAsStringSync(
        "import socket\nopen('not_executed.txt', 'w').write('wrong')\n",
      );
      final checked = <String>[];
      _channelCompiler(channel, onSource: checked.add);
      await _mountTools(
        tester,
        store,
        runner: const PythonProgramRunner(
          transport: PythonNativeTransport.methodChannel,
        ),
      );
      await _expandPackages(tester);
      await tester.enterText(
        find.byKey(const ValueKey('python-package-source')),
        source.path,
      );
      await _tapVisible(tester, find.text('检查兼容性'));
      await _pumpUntil(
        tester,
        () => find.text('兼容性检查未通过').evaluate().isNotEmpty,
      );
      expect(find.textContaining('socket'), findsOneWidget);
      expect(checked.single, source.readAsStringSync());
      expect(
        File(p.join(directory.path, 'not_executed.txt')).existsSync(),
        isFalse,
      );
      await _tapVisible(tester, find.text('安装到项目'));
      await _pumpUntil(
        tester,
        () =>
            find.text('本地包操作未完成').evaluate().isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      expect(
        File(
          p.join(directory.path, '.qfli', 'python', 'packages.json'),
        ).existsSync(),
        isFalse,
      );
      await tester.enterText(
        find.byKey(const ValueKey('python-package-source')),
        p.join(directory.path, 'missing.zip'),
      );
      await _tapVisible(tester, find.text('检查兼容性'));
      await _pumpUntil(
        tester,
        () => find.textContaining('不存在').evaluate().isNotEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'package cancel prevents duplicate work and rolls back before retry',
    (tester) async {
      final source = Directory(
        p.join(directory.path, 'z_sources', 'cancel_pack'),
      )..createSync(recursive: true);
      File(p.join(source.path, '__init__.py')).writeAsStringSync('VALUE = 1\n');
      File(p.join(source.path, 'helper.py')).writeAsStringSync('VALUE = 2\n');
      final pending = Completer<Object?>();
      var checks = 0;
      _channelCompiler(
        channel,
        onCheck: () {
          checks++;
          return checks == 1 ? pending.future : Future.value({'exitCode': 0});
        },
      );
      await _mountTools(
        tester,
        store,
        runner: const PythonProgramRunner(
          transport: PythonNativeTransport.methodChannel,
        ),
      );
      await _expandPackages(tester);
      await tester.enterText(
        find.byKey(const ValueKey('python-package-source')),
        source.path,
      );
      await _tapVisible(tester, find.text('安装到项目'));
      await _pumpUntil(tester, () => checks == 1);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '安装到项目'))
            .onPressed,
        isNull,
      );
      await _tapVisible(tester, find.text('取消包操作'));
      pending.complete({'exitCode': 0});
      await _pumpUntil(
        tester,
        () =>
            find.text('本地包操作未完成').evaluate().isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      expect(checks, 1);
      expect(find.textContaining('操作已取消'), findsOneWidget);
      expect(Directory(p.join(directory.path, 'lib')).existsSync(), isFalse);
      await _tapVisible(tester, find.text('安装到项目'));
      await _pumpUntil(
        tester,
        () =>
            find.text('本地包安装完成').evaluate().isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      expect(checks, 3);
      expect(
        File(
          p.join(directory.path, 'lib', 'cancel_pack', 'helper.py'),
        ).readAsStringSync(),
        'VALUE = 2\n',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disposing during a package check cancels installation without writes',
    (tester) async {
      final source = File(
        p.join(directory.path, 'z_sources', 'dispose_pack.py'),
      );
      source.parent.createSync(recursive: true);
      source.writeAsStringSync('VALUE = 3\n');
      final pending = Completer<Object?>();
      var checking = false;
      _channelCompiler(
        channel,
        onCheck: () {
          checking = true;
          return pending.future;
        },
      );
      await _mountTools(
        tester,
        store,
        runner: const PythonProgramRunner(
          transport: PythonNativeTransport.methodChannel,
        ),
      );
      await _expandPackages(tester);
      await tester.enterText(
        find.byKey(const ValueKey('python-package-source')),
        source.path,
      );
      await _tapVisible(tester, find.text('安装到项目'));
      await _pumpUntil(tester, () => checking);
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete({'exitCode': 0});
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(Directory(p.join(directory.path, 'lib')).existsSync(), isFalse);
      expect(
        File(
          p.join(directory.path, '.qfli', 'python', 'packages.json'),
        ).existsSync(),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'store replacement cancels a late run handle and rejects its output',
    (tester) async {
      final preparing = Completer<String>();
      final execution = Completer<Object?>();
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'available') {
              return {'available': true, 'runControl': true};
            }
            if (call.method == 'prepareRun') return preparing.future;
            if (call.method == 'run') return execution.future;
            if (call.method == 'cancel') {
              execution.complete({
                'exitCode': 130,
                'output': 'old project output',
              });
              return true;
            }
            return null;
          });
      await _mountTools(
        tester,
        store,
        runner: const PythonProgramRunner(
          transport: PythonNativeTransport.methodChannel,
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, '运行'));
      await _pumpUntil(
        tester,
        () => calls.any((call) => call.method == 'prepareRun'),
      );
      final replacementDirectory = Directory(
        p.join(directory.path, 'replacement'),
      )..createSync();
      File(
        p.join(replacementDirectory.path, 'new.py'),
      ).writeAsStringSync('print(7)\n');
      final replacement = Project.create(
        name: 'Replacement project',
        path: replacementDirectory.path,
      );
      await tester.runAsync(() async {
        File(p.join(directory.path, 'registry.json')).writeAsStringSync(
          jsonEncode({
            'projects': [replacement.toJson()],
          }),
        );
        await store.refresh();
      });
      await _pumpUntil(
        tester,
        () =>
            find.text('new.py').evaluate().isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      preparing.complete('late-tools-run');
      await _pumpUntil(
        tester,
        () => calls.any((call) => call.method == 'cancel'),
      );
      expect(find.text('Replacement project'), findsOneWidget);
      expect(find.text('old project output'), findsNothing);
      expect(find.text('运行结束 · 退出码 130'), findsNothing);
      expect(
        (calls.singleWhere((call) => call.method == 'cancel').arguments
            as Map)['runId'],
        'late-tools-run',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('runtime catalog reports availability and bundled API scope', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'available') return pending.future;
          return null;
        });
    await _mountTools(
      tester,
      store,
      runner: const PythonProgramRunner(
        transport: PythonNativeTransport.methodChannel,
      ),
    );
    await _tapVisible(tester, find.text('运行时与模块'));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    pending.complete({
      'available': false,
      'detail': 'embedded module unavailable',
    });
    await _pumpUntil(
      tester,
      () =>
          find.text('csv').evaluate().isNotEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty,
    );
    expect(find.text('运行时不可用'), findsOneWidget);
    expect(find.text('embedded module unavailable'), findsOneWidget);
    expect(find.text('pip'), findsNothing);
    await _tapVisible(tester, find.text('csv'));
    expect(find.textContaining('支持的 API：'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing during a runtime probe ignores its late response', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    var probing = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'available') {
            probing = true;
            return pending.future;
          }
          return null;
        });
    await _mountTools(
      tester,
      store,
      runner: const PythonProgramRunner(
        transport: PythonNativeTransport.methodChannel,
      ),
    );
    await _tapVisible(tester, find.text('运行时与模块'));
    await _pumpUntil(tester, () => probing);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete({'available': true, 'version': 'late-probe'});
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'project change cancels package inspection and keeps the new project clean',
    (tester) async {
      final source = File(
        p.join(directory.path, 'z_sources', 'project_pack.py'),
      );
      source.parent.createSync(recursive: true);
      source.writeAsStringSync('VALUE = 42\n');
      final pending = Completer<Object?>();
      var checking = false;
      _channelCompiler(
        channel,
        onCheck: () {
          checking = true;
          return pending.future;
        },
      );
      await _mountTools(
        tester,
        store,
        runner: const PythonProgramRunner(
          transport: PythonNativeTransport.methodChannel,
        ),
      );
      await _expandPackages(tester);
      await tester.enterText(
        find.byKey(const ValueKey('python-package-source')),
        source.path,
      );
      await _tapVisible(tester, find.text('安装到项目'));
      await _pumpUntil(tester, () => checking);
      final replacementDirectory = Directory(
        p.join(directory.path, 'new_project'),
      )..createSync();
      File(
        p.join(replacementDirectory.path, 'new.py'),
      ).writeAsStringSync('print(2)\n');
      final replacement = Project.create(
        name: 'New package project',
        path: replacementDirectory.path,
      );
      await tester.runAsync(() async {
        File(p.join(directory.path, 'registry.json')).writeAsStringSync(
          jsonEncode({
            'projects': [replacement.toJson()],
          }),
        );
        await store.refresh();
      });
      await _pumpUntil(
        tester,
        () =>
            find.text('new.py').evaluate().isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      pending.complete({'exitCode': 0});
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(find.text('本地包安装完成'), findsNothing);
      expect(find.text('本地包操作未完成'), findsNothing);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('python-package-source')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(Directory(p.join(directory.path, 'lib')).existsSync(), isFalse);
      expect(
        Directory(p.join(replacementDirectory.path, 'lib')).existsSync(),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(360, 800), const Size(1200, 800)]) {
    testWidgets(
      'empty states and large text long paths remain usable at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        File(p.join(directory.path, 'src', 'main.py')).deleteSync();
        final longFile = File(
          p.join(
            directory.path,
            'nested_folder_for_project',
            'another_folder_for_long_paths',
            '很长的_Python_项目文件名称_with_more_words.py',
          ),
        );
        longFile.parent.createSync(recursive: true);
        longFile.writeAsStringSync('print(42)\n');
        final longProject = Project.create(
          name: '很长的 Python 项目名称 ' * 8,
          path: directory.path,
        );
        await tester.runAsync(() async {
          File(p.join(directory.path, 'registry.json')).writeAsStringSync(
            jsonEncode({
              'projects': [longProject.toJson()],
            }),
          );
          await store.refresh();
        });
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.7)),
              child: child!,
            ),
            home: PythonToolsPage(store: store),
          ),
        );
        await _pumpUntil(
          tester,
          () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        await _expandPackages(tester);
        await tester.enterText(
          find.byKey(const ValueKey('python-package-source')),
          p.join(directory.path, '很长的本地目录路径' * 12, 'package.zip'),
        );
        await _tapVisible(tester, find.text('检查兼容性'));
        await _pumpUntil(
          tester,
          () => find.text('兼容性检查未通过').evaluate().isNotEmpty,
        );
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          longFile.deleteSync();
          await store.refresh();
        });
        await _pumpUntil(
          tester,
          () => find.text('项目中没有 Python 文件').evaluate().isNotEmpty,
        );
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '运行'))
              .onPressed,
          isNull,
        );
        await tester.runAsync(() async {
          File(
            p.join(directory.path, 'registry.json'),
          ).writeAsStringSync('{"projects": []}');
          await store.refresh();
        });
        await _pumpUntil(
          tester,
          () => find.text('没有本地项目').evaluate().isNotEmpty,
        );
        expect(find.text('本地源码包'), findsNothing);
        expect(find.text('运行时与模块'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'real Home opens the root Tools tab without pushing PythonToolsPage',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final previousProfile = StudioProfile.current;
      final previousRestore = AppRestoreGate.status.value;
      StudioProfile.current = pythonProfile;
      // A pending restore status would mount RestoreCompletePage instead of Home.
      AppRestoreGate.status.value = null;
      final auth = AuthStore(
        storageFile: File(p.join(directory.path, 'auth.json')),
      );
      final settings = SettingsStore(
        storageFile: File(p.join(directory.path, 'settings.json')),
      );
      addTearDown(() {
        StudioProfile.current = previousProfile;
        AppRestoreGate.status.value = previousRestore;
        auth.dispose();
        settings.dispose();
      });

      // Route the OS storage lookup into this test's temp directory before any
      // singleton resolves it, following the named-workspace fixture pattern.
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(pathChannel, (call) async {
        return switch (call.method) {
          'getApplicationSupportDirectory' ||
          'getApplicationDocumentsDirectory' => directory.path,
          'getTemporaryDirectory' => p.join(directory.path, 'tmp'),
          _ => throw MissingPluginException(call.method),
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(pathChannel, null));
      // Warm the shared caches inside the real async zone. Awaiting this directly
      // in the test's fake zone never completes, and without the routing above the
      // singleton falls back to machine storage instead of this temp directory.
      await tester.runAsync(() async {
        expect(await AppPaths.storageDirectory(), directory.path);
        await TaskActivityService.instance.initialize();
      });

      await tester.pumpWidget(
        QfliApp(store: store, auth: auth, settings: settings),
      );
      await _pumpUntil(
        tester,
        () => find.byType(HomePage).evaluate().isNotEmpty,
        frame: const Duration(milliseconds: 16),
      );
      // The real Home route is mounted; the legacy tools route was never pushed.
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.byType(PythonToolsPage), findsNothing);

      final navigation = find.byType(NavigationBar);
      expect(navigation, findsOneWidget);
      expect(tester.widget<NavigationBar>(navigation).selectedIndex, 0);

      // Enter the root Tools destination through the app's own navigation bar.
      await tester.tap(find.byType(NavigationDestination).at(1));
      await _pumpUntil(
        tester,
        () => tester.widget<NavigationBar>(navigation).selectedIndex == 1,
        frame: const Duration(milliseconds: 16),
      );
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.byType(PythonToolsBody), findsOneWidget);
      expect(find.byType(PythonToolsPage), findsNothing);

      // A selected index only proves the page animated in. The tab's file listing
      // is asynchronous, so wait for the real listing and for loading to finish
      // before asserting any control that depends on it.
      await _pumpUntil(
        tester,
        () =>
            find.text('src${p.separator}main.py').evaluate().isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
        frame: const Duration(milliseconds: 16),
      );

      // Controls live on the tab body itself, fed by the real temp project.
      expect(find.text('检查语法'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '运行'), findsOneWidget);
      expect(find.byTooltip('编译'), findsOneWidget);
      expect(find.text('src${p.separator}main.py'), findsOneWidget);

      // Concrete harmless state change: open the local package manager.
      await _expandPackages(tester);
      expect(
        find.byKey(const ValueKey('python-package-source')),
        findsOneWidget,
      );
      expect(find.text('当前项目没有已安装的本地包'), findsOneWidget);

      // Leaving and returning keeps the root tab; no page route was pushed.
      await tester.tap(find.byType(NavigationDestination).at(0));
      await _pumpUntil(
        tester,
        () => tester.widget<NavigationBar>(navigation).selectedIndex == 0,
        frame: const Duration(milliseconds: 16),
      );
      expect(find.byType(PythonToolsPage), findsNothing);
      await tester.tap(find.byType(NavigationDestination).at(1));
      await _pumpUntil(
        tester,
        () => tester.widget<NavigationBar>(navigation).selectedIndex == 1,
        frame: const Duration(milliseconds: 16),
      );
      expect(find.byType(PythonToolsBody), findsOneWidget);
      expect(find.byType(PythonToolsPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _LateStopRunner extends PythonProgramRunner {
  final cancellation = Completer<void>();
  final _exit = Completer<int>();
  final _stdout = StreamController<String>();
  final _stderr = StreamController<String>();
  bool cancelRequested = false;

  void finish() {
    _stdout.add('finished output');
    unawaited(_stdout.close());
    unawaited(_stderr.close());
    _exit.complete(0);
  }

  @override
  Future<ProgramRunResult?> run({
    required String projectPath,
    required String entryFile,
  }) async => ProgramRunResult(
    title: 'test run',
    stdout: _stdout.stream,
    stderr: _stderr.stream,
    exitCode: _exit.future,
    cancel: () {
      cancelRequested = true;
      return cancellation.future;
    },
  );
}

void _channelCompiler(
  MethodChannel channel, {
  void Function(String)? onSource,
  Future<Object?> Function()? onCheck,
}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'available') {
          return {'available': true, 'version': 'test-channel'};
        }
        if (call.method == 'checkSyntax') {
          onSource?.call((call.arguments as Map)['source'] as String);
          return onCheck == null ? {'exitCode': 0} : await onCheck();
        }
        return null;
      });
}

Future<void> _mountTools(
  WidgetTester tester,
  ProjectStore store, {
  PythonProgramRunner runner = const PythonProgramRunner(),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PythonToolsPage(store: store, runner: runner),
    ),
  );
  await _pumpUntil(
    tester,
    () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
  );
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  // Expanded content can be built before its animated viewport reaches it.
  // Advance just the bounded animation; pending progress indicators may remain.
  await tester.pump(const Duration(milliseconds: 350));
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _expandPackages(WidgetTester tester) async {
  await _tapVisible(tester, find.text('本地源码包'));
  await _pumpUntil(
    tester,
    () =>
        find.text('当前项目没有已安装的本地包').evaluate().isNotEmpty &&
        find.byType(LinearProgressIndicator).evaluate().isEmpty,
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() completed, {
  Duration? frame,
}) async {
  await tester.runAsync(() async {
    // Build the scheduled initial-loading frame before inspecting completion.
    // `frame` is null by default, which keeps every existing caller identical to
    // a bare pump(). Callers that must drive a real animation pass a duration,
    // because pump() alone advances the fake clock by zero and such an animation
    // can never progress.
    await tester.pump(frame);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!completed() && DateTime.now().isBefore(deadline)) {
      await tester.pump(frame);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
  await tester.pump(frame);
  expect(
    completed(),
    isTrue,
    reason: 'Timed out waiting for real asset/file I/O.',
  );
}
