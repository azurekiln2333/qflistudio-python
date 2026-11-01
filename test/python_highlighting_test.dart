// Consumer integration: the python profile's real .py editor must produce token
// styling through the real engine, and must honour the existing
// syntax-highlighting setting.
//
// Every observation comes from a real interface. HighlightThemes.themeFor
// builds the CodeHighlightTheme, CodeEditor runs Highlight on it in an isolate,
// and the rendered paragraphs are read from the public
// CodeIndicatorValue.paragraphs. No fake renderer and no hardcoded spans.
//
// re_editor is declared in dev_dependencies and resolved through the app's local
// path override to the vendored 0.10.0 copy, so this direct import is legal and
// carries no lint suppression. Offline pub resolution and the lockfile entry
// are pending a fresh host grant.
import 'package:re_editor/re_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/editor/highlight_themes.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

/// Fixed fixture: one comment, one keyword, one string, one inline keyword.
const String _pythonSource =
    '# note\ndef greet(name):\n    text = "hello"\n    return text';

/// Line lengths of [_pythonSource], used to prove the line mapping is real.
const List<int> _lineLengths = <int>[6, 16, 18, 15];

/// Probes: line index plus in-line character offset, inside a real token.
const ({int line, int offset}) _commentProbe = (line: 0, offset: 2);
const ({int line, int offset}) _defProbe = (line: 1, offset: 1);
const ({int line, int offset}) _stringProbe = (line: 2, offset: 13);
const ({int line, int offset}) _returnProbe = (line: 3, offset: 6);

CodeLineEditingController _controller() =>
    CodeLineEditingController(codeLines: CodeLines.fromText(_pythonSource));

/// Assemble the real editor in EditorPage's order: resolve the theme first, then
/// build the CodeEditor. The returned theme is the one the editor actually uses.
Future<CodeHighlightTheme?> _pumpEditor(
  WidgetTester tester, {
  required CodeLineEditingController controller,
  required SettingsStore settings,
  String fileName = 'main.py',
}) async {
  CodeHighlightTheme? used;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            used = HighlightThemes.themeFor(
              context,
              fileName,
              null,
              settings: settings,
            );
            return CodeEditor(
              controller: controller,
              style: CodeEditorStyle(fontSize: 13, codeTheme: used),
              indicatorBuilder:
                  (context, editingController, chunkController, notifier) {
                    return DefaultCodeLineNumber(
                      controller: editingController,
                      notifier: notifier,
                    );
                  },
            );
          },
        ),
      ),
    ),
  );
  return used;
}

/// Read the rendered paragraphs the gutter carries publicly. Highlighting runs
/// in an isolate, so the caller needs real async.
CodeIndicatorValue? _indicator(WidgetTester tester) {
  final finder = find.byType(DefaultCodeLineNumber);
  if (finder.evaluate().isEmpty) {
    return null;
  }
  return tester.widget<DefaultCodeLineNumber>(finder).notifier.value;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done,
  String reason,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(reason);
    }
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 16)),
    );
  }
  await tester.pump();
}

/// Read the leaf span actually rendered at a line and character offset.
TextSpan? _spanAt(
  List<CodeLineRenderParagraph> paragraphs,
  ({int line, int offset}) probe,
) {
  final InlineSpan? span = paragraphs[probe.line].paragraph
      .getSpanForPosition(TextPosition(offset: probe.offset));
  return span is TextSpan ? span : null;
}

Color? _colorAt(
  List<CodeLineRenderParagraph> paragraphs,
  ({int line, int offset}) probe,
) => _spanAt(paragraphs, probe)?.style?.color;

void main() {
  testWidgets('python 配置的 .py 编辑器产出关键字、字符串与注释 token 样式', (
    tester,
  ) async {
    final settings = SettingsStore();
    addTearDown(settings.dispose);
    final controller = _controller();
    final theme = await _pumpEditor(
      tester,
      controller: controller,
      settings: settings,
    );

    expect(theme, isNotNull, reason: '.py must resolve to the python profile');
    expect(theme!.language, 'python');
    final keyword = theme.theme['keyword']!.color;
    final string = theme.theme['string']!.color;
    final comment = theme.theme['comment']!.color;
    expect({keyword, string, comment}, hasLength(3));

    await _pumpUntil(
      tester,
      () {
        final paragraphs = _indicator(tester)?.paragraphs;
        if (paragraphs == null || paragraphs.length != _lineLengths.length) {
          return false;
        }
        return _colorAt(paragraphs, _defProbe) == keyword &&
            _colorAt(paragraphs, _returnProbe) == keyword &&
            _colorAt(paragraphs, _stringProbe) == string &&
            _colorAt(paragraphs, _commentProbe) == comment;
      },
      'real highlighting did not produce token styling in time',
    );

    final paragraphs = _indicator(tester)!.paragraphs;
    for (var i = 0; i < _lineLengths.length; i++) {
      expect(
        paragraphs[i].length,
        _lineLengths[i],
        reason: 'line $i length must match the source',
      );
    }
    expect(_colorAt(paragraphs, _defProbe), keyword);
    expect(_colorAt(paragraphs, _returnProbe), keyword);
    expect(_colorAt(paragraphs, _stringProbe), string);
    expect(_colorAt(paragraphs, _commentProbe), comment);
    expect(_spanAt(paragraphs, _defProbe)!.text, 'def');
    expect(_spanAt(paragraphs, _stringProbe)!.text, '"hello"');
    expect(controller.text, _pythonSource);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('关闭语法高亮后编辑器不再产出 token 样式', (tester) async {
    final settings = SettingsStore();
    addTearDown(settings.dispose);
    await settings.setSyntaxHighlighting(false);
    final controller = _controller();
    final theme = await _pumpEditor(
      tester,
      controller: controller,
      settings: settings,
    );

    expect(theme, isNull, reason: 'the setting must suppress the theme');

    await _pumpUntil(
      tester,
      () {
        final paragraphs = _indicator(tester)?.paragraphs;
        return paragraphs != null && paragraphs.length == _lineLengths.length;
      },
      'the editor did not finish its first render with highlighting off',
    );
    // Give any late token styling a chance to appear before asserting absence.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pump();

    final paragraphs = _indicator(tester)!.paragraphs;
    final base = _colorAt(paragraphs, _defProbe);
    for (final probe in <({int line, int offset})>[
      _commentProbe,
      _defProbe,
      _stringProbe,
      _returnProbe,
    ]) {
      final span = _spanAt(paragraphs, probe);
      expect(span, isNotNull, reason: 'line ${probe.line} must render a span');
      expect(
        span!.style?.color,
        base,
        reason: 'line ${probe.line} must not carry its own token color',
      );
    }
    expect(controller.text, _pythonSource);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('重开 .py 编辑器后 token 样式保持不变', (tester) async {
    final settings = SettingsStore();
    addTearDown(settings.dispose);

    final first = _controller();
    final theme = await _pumpEditor(
      tester,
      controller: first,
      settings: settings,
    );
    final keyword = theme!.theme['keyword']!.color;
    final string = theme.theme['string']!.color;
    final comment = theme.theme['comment']!.color;
    await _pumpUntil(
      tester,
      () {
        final paragraphs = _indicator(tester)?.paragraphs;
        return paragraphs != null &&
            paragraphs.length == _lineLengths.length &&
            _colorAt(paragraphs, _defProbe) == keyword &&
            _colorAt(paragraphs, _stringProbe) == string &&
            _colorAt(paragraphs, _commentProbe) == comment;
      },
      'the first open did not produce token styling',
    );
    await tester.pumpWidget(const SizedBox());
    first.dispose();

    final second = _controller();
    await _pumpEditor(tester, controller: second, settings: settings);
    await _pumpUntil(
      tester,
      () {
        final paragraphs = _indicator(tester)?.paragraphs;
        return paragraphs != null &&
            paragraphs.length == _lineLengths.length &&
            _colorAt(paragraphs, _defProbe) == keyword &&
            _colorAt(paragraphs, _stringProbe) == string &&
            _colorAt(paragraphs, _commentProbe) == comment;
      },
      'token styling was lost after re-open',
    );
    final reopened = _indicator(tester)!.paragraphs;
    expect(_colorAt(reopened, _defProbe), keyword);
    expect(_colorAt(reopened, _returnProbe), keyword);
    expect(_colorAt(reopened, _stringProbe), string);
    expect(_colorAt(reopened, _commentProbe), comment);

    await tester.pumpWidget(const SizedBox());
    second.dispose();
  });
}
