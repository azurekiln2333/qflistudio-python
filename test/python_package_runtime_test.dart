import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_python/python_packages.dart';
import 'package:qfli_python/python_runner.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library = p.absolute('native/build/windows/qfli_py_ffi.dll');
  final nativeAvailable = Platform.isWindows && File(library).existsSync();

  group('actual package service to runner integration', () {
    late Directory project;
    late Directory sources;
    late PythonPackageService packages;
    late PythonProgramRunner runner;

    setUp(() {
      project = Directory.systemTemp.createTempSync('python_packages_课程_');
      sources = Directory.systemTemp.createTempSync('python_local_sources_');
      final compiler = PythonProgramRunner(
        transport: PythonNativeTransport.ffi,
        libraryPath: library,
      );
      packages = PythonPackageService(
        syntaxCheck: (source, file) async {
          final result = await compiler.checkSource(
            projectPath: project.path,
            entryFile: file,
            source: source,
          );
          return result.success
              ? null
              : result.error.isEmpty
              ? 'Embedded compiler rejected source.'
              : result.error;
        },
      );
      runner = PythonProgramRunner(
        transport: PythonNativeTransport.ffi,
        libraryPath: library,
        packageService: packages,
      );
    });

    tearDown(() {
      project.deleteSync(recursive: true);
      sources.deleteSync(recursive: true);
    });

    Future<({int exit, List<String> output, List<String> errors})> run(
      String source,
    ) async {
      final entry = File(p.join(project.path, 'src', 'main.py'));
      entry.parent.createSync(recursive: true);
      entry.writeAsStringSync(source);
      final ProgramRunResult result = (await runner.run(
        projectPath: project.path,
        entryFile: entry.path,
      ))!;
      final output = result.stdout.toList();
      final errors = result.stderr.toList();
      return (
        exit: await result.exitCode,
        output: await output,
        errors: await errors,
      );
    }

    test(
      'installs local subpackages and prepares real bundled assets',
      () async {
        final package = Directory(p.join(sources.path, 'calculator'))
          ..createSync();
        File(
          p.join(package.path, '__init__.py'),
        ).writeAsStringSync('from .values import summarize\n');
        File(p.join(package.path, 'values.py')).writeAsStringSync(
          'from statistics import mean\n'
          'from itertools import accumulate\n'
          'def summarize(values):\n'
          ' return mean(values), list(accumulate(values))\n',
        );
        final installed = await packages.install(
          projectPath: project.path,
          sourcePath: package.path,
          version: '1.0',
        );
        expect(installed.success, isTrue, reason: installed.message);
        expect(
          Directory(
            p.join(project.path, '.qfli/python/bundled/v1'),
          ).existsSync(),
          isFalse,
        );

        final result = await run(
          'from calculator import summarize\n'
          'from base64 import b64encode\n'
          'print(summarize([2, 4, 6]))\n'
          'print(b64encode(b"offline"))\n',
        );
        expect(result.exit, 0, reason: result.errors.join('\n'));
        expect(result.output, ['(4.0, [2, 6, 12])', "b'b2ZmbGluZQ=='"]);
        expect(result.errors, isEmpty);
        expect(
          File(
            p.join(project.path, '.qfli/python/bundled/v1/csv.py'),
          ).existsSync(),
          isTrue,
        );
        expect(
          (await packages.listInstalled(
            projectPath: project.path,
          )).single.version,
          '1.0',
        );

        File(p.join(package.path, 'values.py')).writeAsStringSync(
          'def summarize(values):\n return sum(values) * 2\n',
        );
        expect(
          (await packages.install(
            projectPath: project.path,
            sourcePath: package.path,
            version: '2.0',
          )).success,
          isTrue,
        );
        final updated = await run(
          'from calculator import summarize\nprint(summarize([2, 4, 6]))\n',
        );
        expect(updated.exit, 0, reason: updated.errors.join('\n'));
        expect(updated.output, ['24']);
        expect(
          (await packages.remove(
            projectPath: project.path,
            name: 'calculator',
          )).success,
          isTrue,
        );
        final removed = await run('from calculator import summarize\n');
        expect(removed.exit, 1);
        expect(removed.errors.join('\n'), contains('ImportError'));
        expect(
          (await run(
            'from statistics import mean\nprint(mean([2, 4]))\n',
          )).output,
          ['3.0'],
        );
      },
    );

    test(
      'native syntax rejection preserves an installed working version',
      () async {
        final source = File(p.join(sources.path, 'local_values.py'))
          ..writeAsStringSync('value = 42\n');
        expect(
          (await packages.install(
            projectPath: project.path,
            sourcePath: source.path,
          )).success,
          isTrue,
        );
        source.writeAsStringSync('if True\n value = 0\n');
        final rejected = await packages.install(
          projectPath: project.path,
          sourcePath: source.path,
        );
        expect(rejected.success, isFalse);
        expect(rejected.issues.join('\n'), contains('SyntaxError'));
        final result = await run(
          'import local_values\nprint(local_values.value)\n',
        );
        expect(result.exit, 0, reason: result.errors.join('\n'));
        expect(result.output, ['42']);
      },
    );

    test('bundle ownership conflict prevents user program execution', () async {
      final preparation = await packages.ensureBundledModules(project.path);
      expect(preparation.success, isTrue, reason: preparation.message);
      final bundled = File(p.join(preparation.directory, 'statistics.py'));
      bundled.writeAsStringSync('# user edited bundle\n');
      final result = await run('open("executed.txt", "w").write("bad")\n');
      expect(result.exit, PythonProgramRunner.notRunExitCode);
      expect(result.errors, isNotEmpty);
      expect(File(p.join(project.path, 'executed.txt')).existsSync(), isFalse);
      expect(bundled.readAsStringSync(), '# user edited bundle\n');
    });
  }, skip: !nativeAvailable);
}
