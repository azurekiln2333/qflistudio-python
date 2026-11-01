import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/code_analysis.dart';

import 'python_runner.dart';

/// Compile-only diagnostics for the exact project-owned editor snapshots.
///
/// MicroPython reports file/line precision. Diagnostics cover that whole line;
/// this adapter does not infer token columns or check imported modules/names.
class PythonCodeAnalyzer implements CodeAnalyzer {
  const PythonCodeAnalyzer({this.runner = const PythonProgramRunner()});

  final PythonProgramRunner runner;

  @override
  Future<CodeAnalysisResult> analyze(CodeAnalysisRequest request) async {
    if (request.language.toLowerCase() != 'python') {
      return _unavailable('Python 编译器只能检查 Python 源码。');
    }
    if (!p.isAbsolute(request.projectPath) ||
        !p.isAbsolute(request.activeFilePath)) {
      return _unavailable('语法检查需要当前项目和文件的绝对路径。');
    }
    final root = p.normalize(request.projectPath);
    final active = p.normalize(request.activeFilePath);
    if (!p.isWithin(root, active) ||
        p.extension(active).toLowerCase() != '.py') {
      return _unavailable('当前文件不是项目内的 Python 源码。');
    }

    final snapshots = <String, CodeDocumentSnapshot>{};
    for (final snapshot in request.documents) {
      if (p.extension(snapshot.path).toLowerCase() != '.py') continue;
      final path = p.normalize(snapshot.path);
      if (!p.isAbsolute(snapshot.path) || !p.isWithin(root, path)) {
        return _unavailable('待检查的 Python 文本不属于当前项目。');
      }
      final previous = snapshots[path];
      if (previous != null &&
          (previous.text != snapshot.text ||
              previous.revision != snapshot.revision)) {
        return _unavailable('同一文件存在不一致的文本快照，请重新检查。');
      }
      snapshots[path] = snapshot;
    }
    final activeSnapshot = snapshots[active];
    if (activeSnapshot == null || activeSnapshot.revision != request.revision) {
      return _unavailable('当前文件的文本快照已失效，请重新检查。');
    }

    final diagnostics = <CodeDiagnostic>[];
    // Check active text first and never reread older disk copies of buffers.
    for (final path in [
      active,
      ...snapshots.keys.where((key) => key != active),
    ]) {
      final snapshot = snapshots[path]!;
      final result = await runner.checkSource(
        projectPath: root,
        entryFile: path,
        source: snapshot.text,
      );
      if (result.unavailableReason != null) {
        return _unavailable(result.unavailableReason!);
      }
      if (result.success) continue;
      final diagnostic = _diagnostic(path, snapshot.text, result.error);
      if (diagnostic == null) {
        return _unavailable(
          result.error.isEmpty ? 'Python 编译器未返回可定位的语法检查结果。' : result.error,
        );
      }
      diagnostics.add(diagnostic);
    }
    return CodeAnalysisResult(diagnostics: List.unmodifiable(diagnostics));
  }

  static CodeAnalysisResult _unavailable(String reason) =>
      CodeAnalysisResult(unavailableReason: reason);

  static CodeDiagnostic? _diagnostic(String path, String text, String error) {
    final exception = RegExp(
      r'^(SyntaxError|IndentationError):[^\r\n]*\r?$',
      multiLine: true,
    ).allMatches(error).lastOrNull;
    if (exception == null) return null;
    final locations = RegExp(
      r'^\s*File "(.+)", line ([0-9]+)(?:,.*)?\r?$',
      multiLine: true,
    ).allMatches(error);
    if (locations.isEmpty) return null;
    final location = locations.last;
    final reportedPath = location.group(1)!;
    if (!p.isAbsolute(reportedPath) ||
        !p.equals(p.normalize(reportedPath), path)) {
      return null;
    }
    final range = _lineRange(text, int.tryParse(location.group(2)!) ?? 0);
    if (range == null) return null;
    return CodeDiagnostic(
      filePath: path,
      startOffset: range.$1,
      endOffset: range.$2,
      message: exception.group(0)!.trim(),
      source: 'MicroPython',
      code: exception.group(1)!,
    );
  }

  /// String indices already count UTF-16 units, including surrogate pairs.
  static (int, int)? _lineRange(String text, int requestedLine) {
    if (requestedLine < 1) return null;
    var line = 1;
    var start = 0;
    for (var offset = 0; offset < text.length; offset++) {
      final unit = text.codeUnitAt(offset);
      if (unit != 10 && unit != 13) continue;
      if (line == requestedLine) return (start, offset);
      if (unit == 13 &&
          offset + 1 < text.length &&
          text.codeUnitAt(offset + 1) == 10) {
        offset++;
      }
      start = offset + 1;
      line++;
    }
    return line == requestedLine ? (start, text.length) : null;
  }
}
