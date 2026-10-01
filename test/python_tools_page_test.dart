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
      await tester.pumpAndSettle();
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
