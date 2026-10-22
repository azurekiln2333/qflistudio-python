import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_python/python_runner.dart';
import 'package:qfli_python/python_tools_page.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/store/project_store.dart';

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
    store.dispose();
    directory.deleteSync(recursive: true);
  });

  for (final size in [const Size(360, 800), const Size(1200, 800)]) {
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
      expect(find.text('before\nKeyboardInterrupt'), findsOneWidget);
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
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() completed) async {
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!completed() && DateTime.now().isBefore(deadline)) {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
  await tester.pump();
  expect(
    completed(),
    isTrue,
    reason: 'Timed out waiting for real asset/file I/O.',
  );
}
