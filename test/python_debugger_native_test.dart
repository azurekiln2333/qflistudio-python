import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_python/python_debugger.dart';
import 'package:qfli_python/python_packages.dart';
import 'package:qfli_python/python_runner.dart';
import 'package:qfli_python/python_runtime_activity.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

class _Packages extends PythonPackageService {
  @override
  Future<PythonBundlePreparationResult> ensureBundledModules(
    String projectPath,
  ) async => const PythonBundlePreparationResult(
    success: true,
    message: 'project-only test',
  );
}

Future<DebugSnapshot> _pause(DebugSession session, {int after = 0}) async {
  final watch = Stopwatch()..start();
  while (true) {
    final snapshot = session.snapshot;
    if (snapshot.phase == DebugPhase.paused &&
        snapshot.pauseToken!.generation > after) {
      return snapshot;
    }
    if (snapshot.isTerminal) {
      fail(
        'Debugger terminated before pause: ${snapshot.message}\n${snapshot.stderr}',
      );
    }
    if (watch.elapsed > const Duration(seconds: 5)) {
      fail('Timed out waiting for real VM pause: ${snapshot.phase}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Map<String, DebugVariable> _variables(DebugSnapshot snapshot) => {
  for (final variable in snapshot.frames.first.locals) variable.name: variable,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library =
      Platform.environment['QFLI_PY_DEBUG_TEST_LIBRARY'] ??
      p.join(
        Directory.current.path,
        'native',
        'build',
        Platform.operatingSystem,
        Platform.isWindows ? 'qfli_py_ffi.dll' : 'libqfli_py_ffi.so',
      );
  final supported =
      (Platform.isWindows || Platform.isLinux) && File(library).existsSync();
  late Directory project;
  late PythonRuntimeActivity activity;
  late PythonDebugger debugger;
  final sessions = <DebugSession>[];

  setUp(() {
    project = Directory.systemTemp.createTempSync('python_debugger_native_');
    activity = PythonRuntimeActivity();
    debugger = PythonDebugger(
      libraryPath: library,
      packageService: _Packages(),
      runtimeActivity: activity,
    );
  });
  tearDown(() async {
    for (final session in sessions) {
      await session.dispose().timeout(const Duration(seconds: 5));
    }
    sessions.clear();
    project.deleteSync(recursive: true);
  });

  Future<DebugSession> launch(
    String source, {
    String name = 'main.py',
    bool entryPause = true,
    List<DebugBreakpoint> breakpoints = const [],
  }) async {
    final file = File(p.join(project.path, name))
      ..parent.createSync(recursive: true);
    file.writeAsStringSync(source);
    final session = await debugger.launch(
      DebugLaunchRequest(
        projectPath: project.path,
        entryFilePath: file.path,
        language: 'python',
        documents: const [],
        stopOnEntry: entryPause,
        breakpoints: breakpoints,
      ),
    );
    sessions.add(session);
    return session;
  }

  test(
    'real VM entry steps into over out and verifies breakpoint before file effect',
    () async {
      final entry = p.join(project.path, 'main.py');
      final session = await launch(
        'def add(a):\n'
        '    b = a + 1\n'
        '    return b\n'
        'value = 3\n'
        'result = add(value)\n'
        'print(result)\n'
        'with open("marker.txt", "w") as file:\n'
        '    file.write("done")\n',
        breakpoints: [DebugBreakpoint(filePath: entry, line: 7)],
      );
      var paused = await _pause(session);
      expect(paused.frames.first.location!.line, 1);
      expect(File(p.join(project.path, 'marker.txt')).existsSync(), isFalse);
      await session.command(
        DebugCommand.stepOver,
        pauseToken: paused.pauseToken,
      );
      paused = await _pause(session, after: paused.pauseToken!.generation);
      expect(paused.frames.first.location!.line, 4);
      await session.command(
        DebugCommand.stepOver,
        pauseToken: paused.pauseToken,
      );
      paused = await _pause(session, after: paused.pauseToken!.generation);
      expect(paused.frames.first.location!.line, 5);
      final oldToken = paused.pauseToken!;
      await session.command(DebugCommand.stepInto, pauseToken: oldToken);
      paused = await _pause(session, after: oldToken.generation);
      expect(paused.frames.first.name, 'add');
      expect(paused.frames.first.location!.line, 2);
      expect(_variables(paused)['a']!.value, '3');
      expect(_variables(paused)['b']!.type, 'unbound');
      expect(paused.frames.length, 2);
      expect(activity.isBusy, isTrue);
      await expectLater(
        session.command(DebugCommand.resume, pauseToken: oldToken),
        throwsStateError,
      );
      await session.command(
        DebugCommand.stepOver,
        pauseToken: paused.pauseToken,
      );
      paused = await _pause(session, after: paused.pauseToken!.generation);
      expect(paused.frames.first.location!.line, 3);
      expect(_variables(paused)['b']!.value, '4');
      await session.command(
        DebugCommand.stepOut,
        pauseToken: paused.pauseToken,
      );
      paused = await _pause(session, after: paused.pauseToken!.generation);
      expect(paused.frames.first.name, '<module>');
      expect(paused.frames.first.location!.line, 6);
      expect(_variables(paused)['result']!.value, '4');
      await session.command(DebugCommand.resume, pauseToken: paused.pauseToken);
      paused = await _pause(session, after: paused.pauseToken!.generation);
      expect(paused.frames.first.location!.line, 7);
      expect(paused.breakpoints.single.status, DebugBreakpointStatus.verified);
      expect(File(p.join(project.path, 'marker.txt')).existsSync(), isFalse);
      expect(paused.stdout, isEmpty, reason: 'Output delivery is exit-only.');
      await session.setBreakpoints([]);
      await session.command(DebugCommand.resume, pauseToken: paused.pauseToken);
      await session.done.timeout(const Duration(seconds: 5));
      expect(
        session.snapshot.phase,
        DebugPhase.terminated,
        reason: session.snapshot.message,
      );
      expect(session.snapshot.exitCode, 0);
      expect(session.snapshot.stdout, '4\n');
      expect(
        File(p.join(project.path, 'marker.txt')).readAsStringSync(),
        'done',
      );
      expect(activity.isBusy, isFalse);
    },
    skip: supported
        ? false
        : 'Build the current native debugger library first.',
  );

  test(
    'real imported Unicode source gets canonical project breakpoint paths',
    () async {
      final dir = Directory(p.join(project.path, '子目录'))..createSync();
      final helper = File(p.join(dir.path, 'helper.py'))
        ..writeAsStringSync('def answer(a):\n    b = a + 1\n    return b\n');
      final session = await launch(
        'import helper\nprint(helper.answer(8))\n',
        name: '子目录/main.py',
        entryPause: false,
        breakpoints: [DebugBreakpoint(filePath: helper.path, line: 3)],
      );
      final paused = await _pause(session);
      expect(
        paused.frames.first.location!.filePath,
        helper.resolveSymbolicLinksSync(),
      );
      expect(paused.frames.first.location!.line, 3);
      expect(_variables(paused)['b']!.value, '9');
      expect(paused.breakpoints.single.status, DebugBreakpointStatus.verified);
      await session.command(DebugCommand.resume, pauseToken: paused.pauseToken);
      await session.done.timeout(const Duration(seconds: 5));
      expect(session.snapshot.stdout, '9\n');
      expect(session.snapshot.exitCode, 0);
    },
    skip: supported
        ? false
        : 'Build the current native debugger library first.',
  );

  test(
    'real stop from paused and running recovers for an ordinary native run',
    () async {
      var session = await launch('while True:\n    pass\n');
      await _pause(session);
      await session.stop().timeout(const Duration(seconds: 5));
      expect(session.snapshot.exitCode, 130);
      expect(activity.isBusy, isFalse);
      await session.dispose();
      session = await launch('while True: pass\n', entryPause: false);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await session.stop().timeout(const Duration(seconds: 5));
      expect(session.snapshot.exitCode, 130);
      expect(activity.isBusy, isFalse);
      final entry = File(p.join(project.path, 'recovery.py'))
        ..writeAsStringSync('print(42)\n');
      final result = await PythonProgramRunner(
        libraryPath: library,
        packageService: _Packages(),
        runtimeActivity: activity,
      ).run(projectPath: project.path, entryFile: entry.path);
      expect(await result!.stdout.toList(), ['42']);
      expect(await result.exitCode, 0);
    },
    skip: supported
        ? false
        : 'Build the current native debugger library first.',
  );

  test(
    'real runtime error and inspection do not call custom representation hooks',
    () async {
      final entry = p.join(project.path, 'main.py');
      final session = await launch(
        'count = 0\n'
        'class Box:\n'
        '    def __repr__(self):\n'
        '        global count\n'
        '        count += 1\n'
        '        return "bad"\n'
        'box = Box()\n'
        'data = [box, "中文", [1, 2, 3, 4, 5]]\n'
        'print(count)\n'
        'raise ValueError("actual")\n',
        entryPause: false,
        breakpoints: [DebugBreakpoint(filePath: entry, line: 9)],
      );
      final paused = await _pause(session);
      final variables = _variables(paused);
      expect(variables['count']!.value, '0');
      expect(variables['box']!.type, 'Box');
      expect(
        variables['box']!.unavailableReason,
        contains('does not run user code'),
      );
      expect(variables['data']!.children[1].value, '中文');
      expect(variables['data']!.children[2].children.length, 4);
      expect(variables['data']!.children[2].truncated, isTrue);
      await session.command(DebugCommand.resume, pauseToken: paused.pauseToken);
      await session.done.timeout(const Duration(seconds: 5));
      expect(session.snapshot.stdout, '0\n');
      expect(session.snapshot.exitCode, 1);
      expect(session.snapshot.phase, DebugPhase.failed);
      expect(session.snapshot.stderr, contains('ValueError: actual'));
      expect(activity.isBusy, isFalse);
    },
    skip: supported
        ? false
        : 'Build the current native debugger library first.',
  );
}
