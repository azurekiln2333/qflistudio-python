import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_python/python_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isWindows && !Platform.isLinux) return;
  final library =
      Platform.environment['QFLI_PY_TEST_LIBRARY'] ??
      p.join(
        Directory.current.path,
        'native',
        'build',
        Platform.operatingSystem,
        Platform.isWindows ? 'qfli_py_ffi.dll' : 'libqfli_py_ffi.so',
      );

  group(
    'real MicroPython project module imports',
    () {
      late Directory project;
      late PythonFfiBackend backend;
      late String entry;

      File write(String relative, String source) {
        final file = File(p.join(project.path, relative));
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(source);
        return file;
      }

      String canonical(String directory) =>
          Directory(directory).resolveSymbolicLinksSync().replaceAll('\\', '/');

      Future<Map<String, Object?>> run(
        String source, {
        String? projectPath,
        String? entryFile,
        bool compileOnly = false,
      }) => backend.run(
        source: source,
        stdin: '',
        heapKb: 8192,
        projectPath: projectPath ?? project.path,
        entryFile: entryFile ?? entry,
        compileOnly: compileOnly,
      );

      void expectSuccess(Map<String, Object?> result, String output) {
        expect(result['exitCode'], 0, reason: '${result['error']}');
        expect(result['output'], output);
        expect(result['error'], isNull);
        expect(result['truncated'], isFalse);
      }

      setUp(() {
        project = Directory.systemTemp.createTempSync('qfli_modules_模块🚀_');
        entry = p.join(project.path, 'main.py');
        backend = PythonFfiBackend(libraryPath: library);
      });
      tearDown(() => project.deleteSync(recursive: true));

      test(
        'fresh projects tolerate absent optional package directories',
        () async {
          write('helper.py', 'value = 42\n');
          expectSuccess(
            await run(
              'import helper\nprint(helper.value)\n'
              'try:\n import unavailable_package\n'
              "except ImportError:\n print('missing')\n",
            ),
            '42\nmissing\n',
          );
          expect(Directory(p.join(project.path, 'lib')).existsSync(), isFalse);
          expect(
            Directory(p.join(project.path, '.qfli')).existsSync(),
            isFalse,
          );
        },
      );

      test(
        'nested Unicode entry imports local and bundled subpackages',
        () async {
          entry = write('src/课程🚀/main.py', '').path;
          write('lib/calculator/__init__.py', 'from .values import doubled\n');
          write(
            'lib/calculator/values.py',
            'def doubled(values):\n return sum(values) * 2\n',
          );
          write(
            '.qfli/python/bundled/v1/bundlepkg/__init__.py',
            'from .nested.api import offset\n',
          );
          write('.qfli/python/bundled/v1/bundlepkg/nested/__init__.py', '');
          write(
            '.qfli/python/bundled/v1/bundlepkg/nested/api.py',
            'def offset(value):\n return value + 1\n',
          );
          expectSuccess(
            await run(
              'from calculator import doubled\n'
              'from bundlepkg import offset\n'
              'print(offset(doubled([3, 4, 5])))\n',
            ),
            '25\n',
          );
        },
      );

      test('entry, root and local packages precede bundled modules', () async {
        entry = write('src/nested/main.py', '').path;
        final candidates = [
          write('src/nested/rank.py', "value = 'entry'\n"),
          write('rank.py', "value = 'root'\n"),
          write('lib/rank.py', "value = 'local'\n"),
          write('.qfli/python/bundled/v1/rank.py', "value = 'bundle'\n"),
        ];
        for (final value in ['entry', 'root', 'local', 'bundle']) {
          expectSuccess(
            await run('import rank\nprint(rank.value)\n'),
            '$value\n',
          );
          candidates.removeAt(0).deleteSync();
        }
        final missing = await run('import rank\n');
        expect(missing['exitCode'], 1);
        expect(missing['error'], contains('ImportError'));
      });

      test(
        'existing directories normalize while source identity is retained',
        () async {
          entry = write('src/课程🚀/main.py', '').path;
          Directory(p.join(project.path, 'lib')).createSync();
          Directory(
            p.join(project.path, '.qfli/python/bundled/v1'),
          ).createSync(recursive: true);
          final sourceEntry = p.join(
            p.dirname(entry),
            '..',
            p.basename(p.dirname(entry)),
            'main.py',
          );
          final result = await run(
            'import json, sys\nprint(json.dumps(sys.path))\n'
            'print(__file__ == sys.argv[0])\n',
            projectPath: '${project.path}${p.separator}.${p.separator}',
            entryFile: sourceEntry,
          );
          expect(result['exitCode'], 0, reason: '${result['error']}');
          final lines = (result['output']! as String).trim().split('\n');
          expect(jsonDecode(lines[0]), [
            canonical(p.dirname(entry)),
            canonical(project.path),
            canonical(p.join(project.path, 'lib')),
            canonical(p.join(project.path, '.qfli/python/bundled/v1')),
          ]);
          expect(lines[1], 'True');
          expect(result['error'], isNull);
          final identity = await run(
            'print(__file__)\n',
            entryFile: sourceEntry,
          );
          expectSuccess(identity, '$sourceEntry\n');
        },
      );

      test(
        'package state and source changes are fresh on every invocation',
        () async {
          write('lib/mutable/__init__.py', 'from .values import items\n');
          final source = write('lib/mutable/values.py', 'items = [1]\n');
          expectSuccess(
            await run(
              'import mutable\nmutable.items.append(2)\nprint(mutable.items)',
            ),
            '[1, 2]\n',
          );
          expectSuccess(
            await run('import mutable\nprint(mutable.items)'),
            '[1]\n',
          );
          source.writeAsStringSync('items = [3, 4]\n');
          expectSuccess(
            await run('import mutable\nprint(mutable.items)'),
            '[3, 4]\n',
          );
          source.deleteSync();
          final missing = await run('import mutable');
          expect(missing['exitCode'], 1);
          expect(missing['error'], contains('ImportError'));
          source.writeAsStringSync('items = [42]\n');
          expectSuccess(
            await run('import mutable\nprint(mutable.items)'),
            '[42]\n',
          );
        },
      );

      test('one project cannot inherit another project module cache', () async {
        write('lib/project_value.py', 'value = 42\n');
        expectSuccess(
          await run('import project_value\nprint(project_value.value)'),
          '42\n',
        );
        final other = Directory.systemTemp.createTempSync(
          'qfli_other_modules_',
        );
        try {
          final result = await run(
            'import project_value',
            projectPath: other.path,
            entryFile: p.join(other.path, 'main.py'),
          );
          expect(result['exitCode'], 1);
          expect(result['error'], contains('ImportError'));
        } finally {
          other.deleteSync(recursive: true);
        }
        expectSuccess(
          await run('import project_value\nprint(project_value.value)'),
          '42\n',
        );
      });

      test(
        'compile-only does not execute imported package side effects',
        () async {
          write(
            'lib/side_effect.py',
            "open('must_not_exist', 'w').close()\nraise ValueError('executed')\n",
          );
          expectSuccess(
            await run('import side_effect\n', compileOnly: true),
            '',
          );
          expect(
            File(p.join(project.path, 'must_not_exist')).existsSync(),
            isFalse,
          );
        },
      );

      test(
        'overlong import paths fail before execution and allow recovery',
        () async {
          final oversized = List.filled(4096, 'x').join();
          for (final paths in [
            (project: oversized, entry: entry),
            (project: project.path, entry: oversized),
          ]) {
            final result = await run(
              "open('must_not_exist', 'w').close()",
              projectPath: paths.project,
              entryFile: paths.entry,
            );
            expect(result['exitCode'], 1);
            expect(result['error'], contains('OSError'));
            expect(
              File(p.join(project.path, 'must_not_exist')).existsSync(),
              isFalse,
            );
          }
          write('lib/recovered.py', 'value = 42\n');
          expectSuccess(
            await run('import recovered\nprint(recovered.value)'),
            '42\n',
          );
        },
      );

      test('import exceptions and cancellation close files and recover', () async {
        write('input_data.txt', '42\n');
        final imported = write(
          'lib/controlled.py',
          "handle = open('input_data.txt')\nraise ValueError('import failed')\n",
        );
        for (var i = 0; i < 5; i++) {
          final failure = await run('import controlled\n');
          expect(failure['exitCode'], 1);
          expect(failure['error'], contains('ValueError: import failed'));
        }
        imported.writeAsStringSync(
          "handle = open('input_data.txt')\n"
          "open('started', 'w').close()\nwhile True: pass\n",
        );
        final execution = backend.start(
          source: 'import controlled\n',
          stdin: '',
          heapKb: 8192,
          projectPath: project.path,
          entryFile: entry,
        );
        final started = File(p.join(project.path, 'started'));
        try {
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while (!started.existsSync()) {
            if (DateTime.now().isAfter(deadline)) {
              fail('Imported module did not reach its cancellation marker.');
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        } finally {
          await execution.cancel();
        }
        final stopped = await execution.result.timeout(
          const Duration(seconds: 3),
        );
        expect(stopped['exitCode'], 130);
        expect(stopped['error'], contains('KeyboardInterrupt'));
        imported.writeAsStringSync(
          "with open('input_data.txt') as handle:\n value = int(handle.read())\n",
        );
        expectSuccess(
          await run('import controlled\nprint(controlled.value)'),
          '42\n',
        );
        // Windows refuses deletion when a native file handle survives cleanup.
        File(p.join(project.path, 'input_data.txt')).deleteSync();
      });
    },
    skip: File(library).existsSync() ? false : 'Native library is unavailable.',
  );
}
