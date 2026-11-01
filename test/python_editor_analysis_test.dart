import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_python/main.dart' show pythonProfile;
import 'package:qfli_studio_core/editor/editor_analysis_controller.dart';
import 'package:qfli_studio_core/editor/editor_controller.dart';
import 'package:qfli_studio_core/editor/editor_problems_bar.dart';
import 'package:qfli_studio_core/models/project.dart';

void main() {
  for (final width in [360.0, 1200.0]) {
    testWidgets('native unsaved diagnostics reach Problems at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = Directory.systemTemp.createTempSync('python_editor_native_');
      final source = File(p.join(root.path, 'main.py'));
      const saved = 'print("saved")\r\n';
      source.writeAsStringSync(saved);
      final editor = EditorController(
        project: Project.create(
          name: 'Python unsaved',
          path: root.path,
          type: 'python',
          language: 'Python',
        ),
      );
      EditorAnalysisController? analysis;
      addTearDown(() {
        analysis?.dispose();
        editor.dispose();
        root.deleteSync(recursive: true);
      });
      expect(await tester.runAsync(() => editor.openPath(source.path)), isNull);
      final file = editor.current!;
      file.controller.text = '# 😀 unsaved\r\nif True print(1)\r\n';
      final controller = EditorAnalysisController(
        editor: editor,
        analyzer: pythonProfile.codeAnalyzer,
      );
      analysis = controller;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Scaffold(
              body: EditorProblemsPanel(analysis: controller, onClose: () {}),
            ),
          ),
        ),
      );
      await _checked(tester, controller);
      expect(controller.unavailableReason, isNull);
      expect(controller.problems, hasLength(1));
      final problem = controller.problems.single;
      expect(problem.source, 'MicroPython');
      expect(controller.location(problem), 'main.py:2:1');
      expect(file.diagnostics!.problems, [problem]);
      expect(find.textContaining('SyntaxError:'), findsOneWidget);
      await tester.tap(find.byType(ListTile));
      await tester.pump();
      expect(file.controller.selection.baseIndex, 1);
      expect(file.controller.selection.baseOffset, 0);
      expect(file.controller.selection.extentOffset, 'if True print(1)'.length);

      file.controller.text =
          'open("must-not-execute.txt", "w").write("bad")\r\n'
          'import absent_module\r\ninput()\r\n';
      await _checked(tester, controller);
      expect(controller.checked, isTrue);
      expect(controller.problems, isEmpty);
      expect(file.diagnostics!.problems, isEmpty);
      expect(find.text('本地检查未发现问题'), findsOneWidget);
      expect(source.readAsStringSync(), saved);
      expect(
        File(p.join(root.path, 'must-not-execute.txt')).existsSync(),
        isFalse,
      );
      expect(file.dirty, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

Future<void> _checked(
  WidgetTester tester,
  EditorAnalysisController analysis,
) async {
  await tester.pump(const Duration(milliseconds: 310));
  for (var attempt = 0; attempt < 200 && analysis.pending; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(analysis.pending, isFalse, reason: 'Native analysis did not settle');
}
