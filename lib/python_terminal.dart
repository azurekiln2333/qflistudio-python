import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/project_config.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/terminal/shell/command_parser.dart';
import 'package:qfli_studio_core/terminal/shell/sandbox_shell_backend.dart';

import 'python_runner.dart';

/// The Python interpreter names this App answers to in the terminal.
///
/// All three names route to the same embedded MicroPython backend, so they are
/// behaviourally identical; they exist so a user's muscle memory (`python` /
/// `python3`) and the explicit spelling (`micropython`) both work.
const Set<String> pythonTerminalCommands = {'python', 'python3', 'micropython'};

/// Supplies [PythonRuntimeInfo] from the real native backend.
///
/// Defaults to [PythonProgramRunner.runtimeInfo]. It exists as a seam so tests
/// can drive the terminal without a device; production never duplicates the
/// runner's probe plumbing.
typedef PythonRuntimeProbeSource = Future<PythonRuntimeInfo> Function();

/// Terminal hook for the Python toolchain.
///
/// Claims `python <script>` and routes it through the same embedded
/// MicroPython backend as the Run button, so stdout/stderr, exit status,
/// cancellation and the `input.txt` project convention are identical. There is
/// no second interpreter.
///
/// Deliberately conservative about what it claims, because a partial claim is a
/// lie:
///   * only [CommandSyntax.simple] lines (pipes, redirection, chaining and
///     globs need a real shell and fall back to the sandbox's honest message);
///   * `python --version` / `python3 -V` / `micropython -V` read the **real**
///     version from [probeSource]; an unavailable backend gets an honest
///     diagnostic, never a fabricated string;
///   * `-m module` / `-c code` and extra operands are refused with a clear
///     message instead of being silently ignored — this backend has no
///     `sys.argv`/module-runner contract, so dropping them would produce a
///     silently wrong run.
///
/// [runner] and [probeSource] default to the production backend; [probeSource]
/// defaults to [runner.runtimeInfo] so there is one probe implementation.
/// Returns false for anything it does not claim so the sandbox reports
/// honestly.
Future<bool> pythonTerminalDelegate(
  SandboxShellBackend backend,
  String command, {
  PythonProgramRunner runner = const PythonProgramRunner(),
  PythonRuntimeProbeSource? probeSource,
}) async {
  final probe = probeSource ?? runner.runtimeInfo;
  // The sandbox always classifies with a literal backslash (Windows path
  // separator), so tokenize the same way; otherwise `src\main.py` would be
  // cut apart as escape sequences.
  const policy = EscapePolicy.backslashLiteral;
  if (CommandParser.classify(command, escapePolicy: policy) !=
      CommandSyntax.simple) {
    return false;
  }
  final parsed = CommandParser.tokenize(command, escapePolicy: policy);
  if (!parsed.ok || parsed.tokens.isEmpty) return false;
  final tokens = parsed.tokens.map((token) => token.text).toList();
  final tool = tokens.first;
  if (!_isInterpreter(tool)) return false;

  final operands = tokens.sublist(1);

  // `python --version` / `-V` — the real embedded interpreter version.
  if (operands.length == 1 &&
      (operands.first == '--version' || operands.first == '-V')) {
    final version = await _versionResult(tool, probe);
    return _report(
      backend,
      title: '$tool ${operands.first}',
      stdout: version.success ? version.lines : const [],
      stderr: version.success ? const [] : version.lines,
    );
  }

  if (operands.isEmpty) {
    return _report(
      backend,
      title: tool,
      stderr: const [
        'python: 本终端需要显式脚本路径，例如 `python main.py`。'
            '（本版 Python 是打包好的本地解释器，不提供交互式 REPL。）',
      ],
    );
  }

  final first = operands.first;
  if (first == '-m' || first == '-c') {
    return _report(
      backend,
      title: tool,
      stderr: ['python: 暂不支持 $first；本终端只执行项目内的 .py / .mpy 脚本文件。'],
    );
  }
  if (first.startsWith('-')) {
    return _report(
      backend,
      title: tool,
      stderr: ['python: 暂不支持解释器选项 $first；请直接给出脚本路径。'],
    );
  }

  // Refuse extra operands rather than dropping them: the native backend has no
  // `sys.argv` contract, so `python main.py arg` would otherwise run as if the
  // argument were never passed — a silent, wrong result.
  if (operands.length > 1) {
    return _report(
      backend,
      title: tool,
      stderr: [
        'python: 暂不支持脚本参数（${operands.skip(1).join(' ')}）。'
            '本版运行器不向脚本传递 sys.argv，请把需要的输入写入 input.txt。',
      ],
    );
  }

  final String scriptPath;
  try {
    scriptPath = backend.resolveSandboxPath(first);
  } on SandboxEscapeException {
    return _report(
      backend,
      title: tool,
      stderr: ['python: 不能越出沙盒目录: $first'],
    );
  }
  if (!File(scriptPath).existsSync()) {
    return _report(
      backend,
      title: tool,
      stderr: ['python: 找不到文件: $first'],
    );
  }
  final extension = p.extension(scriptPath).toLowerCase();
  if (extension != '.py' && extension != '.mpy') {
    return _report(
      backend,
      title: tool,
      stderr: ['python: 只能执行 .py / .mpy 文件: $first'],
    );
  }

  final result = await runner.run(
    projectPath: projectRootForScript(
      scriptPath,
      backend.sandboxRoot,
      workingDirectory: backend.cwd,
    ),
    entryFile: scriptPath,
  );
  if (result == null) return false;
  await backend.runStreams(
    title: result.title,
    stdout: result.stdout,
    stderr: result.stderr,
    exitCode: result.exitCode,
    cancel: result.cancel,
  );
  return true;
}

bool _isInterpreter(String token) =>
    pythonTerminalCommands.contains(token) ||
    pythonTerminalCommands.contains(p.basenameWithoutExtension(token));

/// The project root that owns [scriptPath], confined to [sandboxRoot].
///
/// The Run button passes `widget.project.path`, so `input.txt` and root-relative
/// imports resolve against the project directory even when the entry file lives
/// in `src/`. Reconstruct the same root by walking up from the script to the
/// nearest directory carrying `.qfli/project.json` — the marker every registered
/// project writes.
///
/// The walk never leaves [sandboxRoot]: a `.qfli` belonging to an unrelated
/// project above the sandbox must not be adopted, or one project's terminal
/// would silently run against another project's root.
///
/// When no in-sandbox marker exists (an unmarked folder the user `cd`-ed into),
/// [workingDirectory] is the root — this matches ordinary Python semantics:
/// `cd project; python src/main.py` reads `input.txt` from `project/`, the
/// current directory, not from `src/`. [workingDirectory] is only adopted when
/// it lies inside [sandboxRoot]; otherwise the script's own directory is the
/// honest last resort.
String projectRootForScript(
  String scriptPath,
  String sandboxRoot, {
  String? workingDirectory,
}) {
  final scriptDirectory = p.dirname(scriptPath);
  final normalizedRoot = p.normalize(p.absolute(sandboxRoot));
  final normalizedScript = p.normalize(p.absolute(scriptDirectory));
  if (!p.equals(normalizedScript, normalizedRoot) &&
      !p.isWithin(normalizedRoot, normalizedScript)) {
    // The script is outside the sandbox root (should not happen for a resolved
    // sandbox path, but stay honest): use its own directory and stop.
    return scriptDirectory;
  }
  // No-marker fallback: the terminal's current directory, when it is inside
  // the sandbox. Resolved here so an unusable cwd cannot leak a path.
  final normalizedCwd = workingDirectory == null
      ? null
      : p.normalize(p.absolute(workingDirectory));
  final cwdFallback =
      normalizedCwd != null &&
          (p.equals(normalizedCwd, normalizedRoot) ||
              p.isWithin(normalizedRoot, normalizedCwd))
      ? normalizedCwd
      : scriptDirectory;
  var directory = normalizedScript;
  while (true) {
    if (ProjectConfig.read(directory) != null) return directory;
    if (p.equals(directory, normalizedRoot)) return cwdFallback;
    final parent = p.dirname(directory);
    if (parent == directory) return cwdFallback;
    directory = parent;
  }
}

/// Result of a `--version` probe: the line(s) to print and whether it succeeded.
///
/// Success prints on **stdout** and exits 0 (a diagnostic printed on stderr is
/// an error, and the shared terminal renders it as one); failure prints on
/// stderr and exits [kProgramNotRunExitCode].
typedef _VersionResult = ({List<String> lines, bool success});

/// `--version` output from the real backend, plus whether the probe succeeded.
Future<_VersionResult> _versionResult(
  String tool,
  PythonRuntimeProbeSource probeSource,
) async {
  final PythonRuntimeInfo probe;
  try {
    probe = await probeSource();
  } catch (error) {
    return (lines: ['$tool: 运行时探测失败：$error'], success: false);
  }
  if (!probe.available) {
    return (
      lines: [
        probe.detail.isEmpty
            ? '$tool: Python 运行组件不可用，请重新安装应用。'
            : '$tool: ${probe.detail}',
      ],
      success: false,
    );
  }
  if (probe.version.isEmpty) {
    // The backend loaded but reported no version — still not a successful
    // version answer, and no number may be invented.
    return (lines: ['$tool: 运行组件未报告 MicroPython 版本。'], success: false);
  }
  return (lines: ['MicroPython ${probe.version}'], success: true);
}

/// Emits one-shot output through the shared terminal channel.
///
/// [SandboxShellBackend.emitLine] is `@protected`, so a host delegate writes
/// only through [SandboxShellBackend.runStreams]. Passing explicit stdout and
/// stderr keeps the message on the real channel the terminal renders from, so a
/// success and a failure cannot be confused (only one of the two is non-empty),
/// and the exit status is derived from which one carries output.
Future<bool> _report(
  SandboxShellBackend backend, {
  required String title,
  List<String> stdout = const [],
  List<String> stderr = const [],
}) async {
  assert(
    (stdout.isEmpty || stderr.isEmpty),
    'a diagnostic belongs on exactly one channel',
  );
  return backend.runStreams(
    title: title,
    stdout: _stream(stdout),
    stderr: _stream(stderr),
    exitCode: Future<int>.value(
      stderr.isEmpty ? 0 : kProgramNotRunExitCode,
    ),
  ).then((_) => true);
}

Stream<String> _stream(List<String> lines) {
  final controller = StreamController<String>();
  for (final line in lines) {
    controller.add(line);
  }
  unawaited(controller.close());
  return controller.stream;
}
