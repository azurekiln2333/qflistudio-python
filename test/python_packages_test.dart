import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_python/python_packages.dart';
import 'package:qfli_python/python_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late Directory project;
  late Directory sources;
  late _Assets assets;
  late PythonPackageService service;
  late List<String> compiled;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('python-packages-');
    project = Directory(p.join(temporary.path, '项目'))..createSync();
    sources = Directory(p.join(temporary.path, 'sources'))..createSync();
    assets = _Assets({'useful.py': 'def add(a, b):\n    return a + b\n'});
    compiled = [];
    service = PythonPackageService(
      assets: assets,
      syntaxCheck: (source, path) async {
        compiled.add(path);
        return source.contains('syntax_error')
            ? 'SyntaxError: invalid syntax'
            : null;
      },
    );
  });

  tearDown(() {
    temporary.deleteSync(recursive: true);
  });

  File source(String name, String content) {
    final file = File(p.join(sources.path, name));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  File installed(String relative) =>
      File(p.join(project.path, 'lib', relative));

  Future<PythonPackageOperationResult> install(
    File file, {
    String? name,
    String? version,
  }) => service.install(
    projectPath: project.path,
    sourcePath: file.path,
    name: name,
    version: version,
  );

  test(
    'catalog distinguishes actual VM builtins and versioned bundled API scope',
    () async {
      final catalog = await service.moduleCatalog;
      final builtin = catalog.singleWhere((module) => module.name == 'json');
      final bundled = catalog.singleWhere((module) => module.name == 'useful');
      expect(builtin.origin, PythonModuleOrigin.builtIn);
      expect(builtin.apis, isEmpty);
      expect(bundled.origin, PythonModuleOrigin.bundled);
      expect(bundled.apis, ['add']);
      expect(bundled.license, 'MIT');
      expect(catalog.any((module) => module.name == 'pip'), isFalse);
    },
  );

  test(
    'prepares digest-checked assets on fresh and repeated runs without compiler',
    () async {
      final preparer = PythonPackageService(assets: assets);
      final first = await preparer.ensureBundledModules(project.path);
      expect(first.success, isTrue, reason: first.message);
      expect(
        File(p.join(first.directory, 'useful.py')).readAsStringSync(),
        contains('return a + b'),
      );
      final file = File(p.join(first.directory, 'useful.py'));
      final manifest = File(
        p.join(project.path, '.qfli/python/bundled/installed.json'),
      );
      final timestamp = DateTime.utc(2020, 1, 2);
      file.setLastModifiedSync(timestamp);
      manifest.setLastModifiedSync(timestamp);
      final second = await preparer.ensureBundledModules(project.path);
      expect(second.success, isTrue, reason: second.message);
      expect(second.directory, first.directory);
      expect(file.lastModifiedSync().toUtc(), timestamp);
      expect(manifest.lastModifiedSync().toUtc(), timestamp);
      expect(compiled, isEmpty);
      expect(_transactions(project), isEmpty);
    },
  );

  test(
    'asset corruption does not replace a previously prepared bundle',
    () async {
      final first = await service.ensureBundledModules(project.path);
      assets.content['useful.py'] = utf8.encode('changed bytes');
      final second = await service.ensureBundledModules(project.path);
      expect(second.success, isFalse);
      expect(
        File(p.join(first.directory, 'useful.py')).readAsStringSync(),
        contains('return a + b'),
      );
      expect(_transactions(project), isEmpty);
    },
  );

  test(
    'missing owned bundle files are repaired without changing other files',
    () async {
      final first = await service.ensureBundledModules(project.path);
      final file = File(p.join(first.directory, 'useful.py'))..deleteSync();
      final repaired = await service.ensureBundledModules(project.path);
      expect(repaired.success, isTrue, reason: repaired.message);
      expect(file.readAsStringSync(), contains('return a + b'));
      expect(_transactions(project), isEmpty);
    },
  );

  test(
    'bundle update preserves edited or unmanaged destination files',
    () async {
      final first = await service.ensureBundledModules(project.path);
      final file = File(p.join(first.directory, 'useful.py'))
        ..writeAsStringSync('# user edit\n');
      expect(
        (await service.ensureBundledModules(project.path)).success,
        isFalse,
      );
      expect(file.readAsStringSync(), '# user edit\n');
      File(
        p.join(project.path, '.qfli', 'python', 'bundled', 'installed.json'),
      ).deleteSync();
      expect(
        (await service.ensureBundledModules(project.path)).success,
        isFalse,
      );
      expect(file.readAsStringSync(), '# user edit\n');
    },
  );

  test(
    'rejects malformed manifests and unsafe bundle paths before writing',
    () async {
      assets.manifest['files'] = [
        {'path': '../escape.py', 'sha256': '0' * 64},
      ];
      final result = await service.ensureBundledModules(project.path);
      expect(result.success, isFalse);
      expect(project.listSync(), isEmpty);
      expect(File(p.join(temporary.path, 'escape.py')).existsSync(), isFalse);
    },
  );

  test('missing assets are honest preparation failures', () async {
    assets.content.clear();
    final result = await service.ensureBundledModules(project.path);
    expect(result.success, isFalse);
    expect(result.message, contains('missing asset'));
    expect(project.listSync(), isEmpty);
  });

  test(
    'local .py install/check/list/show/remove use actual owned files',
    () async {
      final file = source('hello.py', 'VALUE = 42\n');
      final checked = await service.check(
        projectPath: project.path,
        sourcePath: file.path,
      );
      expect(checked.compatible, isTrue, reason: checked.message);
      expect(project.listSync(), isEmpty, reason: 'check must not write files');
      expect(compiled.single, p.join(project.path, 'lib', 'hello.py'));
      final result = await install(file, version: '1.2.0');
      expect(result.success, isTrue, reason: result.message);
      expect(installed('hello.py').readAsStringSync(), 'VALUE = 42\n');
      final list = await service.listInstalled(projectPath: project.path);
      expect(list.single.name, 'hello');
      expect(list.single.version, '1.2.0');
      expect(list.single.files.keys, ['lib/hello.py']);
      expect(
        (await service.show(projectPath: project.path, name: 'hello'))?.source,
        file.path,
      );
      expect(
        await service.show(projectPath: project.path, name: 'missing'),
        isNull,
      );
      final removed = await service.remove(
        projectPath: project.path,
        name: 'hello',
      );
      expect(removed.success, isTrue, reason: removed.message);
      expect(installed('hello.py').existsSync(), isFalse);
      expect(await service.listInstalled(projectPath: project.path), isEmpty);
      expect(_transactions(project), isEmpty);
    },
  );

  test('cannot install without a VM syntax callback', () async {
    final file = source('hello.py', 'print(42)\n');
    final result = await PythonPackageService(
      assets: assets,
    ).install(projectPath: project.path, sourcePath: file.path);
    expect(result.success, isFalse);
    expect(result.message, contains('真实的 Python 语法检查'));
    expect(project.listSync(), isEmpty);
  });

  test(
    'a failed compiler with an empty diagnostic still rejects installation',
    () async {
      final rejecting = PythonPackageService(
        assets: assets,
        syntaxCheck: (_, _) async => '',
      );
      final result = await rejecting.install(
        projectPath: project.path,
        sourcePath: source('demo.py', 'A = 1\n').path,
      );
      expect(result.success, isFalse);
      expect(result.message, contains('原生语法检查未通过'));
      expect(project.listSync(), isEmpty);
    },
  );

  test(
    'empty and relative project paths never default to the working directory',
    () async {
      final file = source('demo.py', 'A = 1\n');
      for (final path in ['', '.']) {
        final result = await service.install(
          projectPath: path,
          sourcePath: file.path,
        );
        expect(result.success, isFalse);
        expect(result.message, contains('绝对路径'));
      }
      expect(
        (await service.install(
          projectPath: project.path,
          sourcePath: '',
        )).success,
        isFalse,
      );
      expect(project.listSync(), isEmpty);
    },
  );

  test(
    'directory packages retain init, submodules and local text resources',
    () async {
      source('demo/__init__.py', 'from .helper import VALUE\n');
      source('demo/helper.py', 'VALUE = 7\n');
      source('demo/data/table.csv', 'name,value\na,7\n');
      final result = await service.install(
        projectPath: project.path,
        sourcePath: p.join(sources.path, 'demo'),
      );
      expect(result.success, isTrue, reason: result.message);
      expect(installed('demo/helper.py').readAsStringSync(), 'VALUE = 7\n');
      expect(
        installed('demo/data/table.csv').readAsStringSync(),
        contains('a,7'),
      );
      expect(result.package!.files.length, 3);
    },
  );

  test('syntax failure retains an earlier version and its manifest', () async {
    final file = source('demo.py', 'VALUE = 1\n');
    expect((await install(file, version: '1')).success, isTrue);
    final manifest = File(
      p.join(project.path, '.qfli/python/packages.json'),
    ).readAsBytesSync();
    file.writeAsStringSync('syntax_error\n');
    final result = await install(file, version: '2');
    expect(result.success, isFalse);
    expect(installed('demo.py').readAsStringSync(), 'VALUE = 1\n');
    expect(
      File(
        p.join(project.path, '.qfli/python/packages.json'),
      ).readAsBytesSync(),
      manifest,
    );
    expect(_transactions(project), isEmpty);
  });

  test(
    'check rejects unavailable imports and unprovided bundled API names',
    () async {
      var file = source('demo.py', 'import socket\n');
      var result = await service.check(
        projectPath: project.path,
        sourcePath: file.path,
      );
      expect(result.compatible, isFalse);
      expect(result.issues.join(), contains('socket'));
      file = source('demo.py', 'from useful import missing\n');
      result = await service.check(
        projectPath: project.path,
        sourcePath: file.path,
      );
      expect(result.compatible, isFalse);
      expect(result.issues.join(), contains('missing'));
      source('demo.py', 'from useful import add\nimport json\n');
      result = await service.check(
        projectPath: project.path,
        sourcePath: file.path,
      );
      expect(result.compatible, isTrue, reason: result.message);
    },
  );

  test(
    'imports can resolve existing project modules without adopting their files',
    () async {
      File(p.join(project.path, 'helper.py')).writeAsStringSync('VALUE = 8\n');
      final result = await install(source('demo.py', 'import helper\n'));
      expect(result.success, isTrue, reason: result.message);
      expect(result.package!.files.keys, ['lib/demo.py']);
      await service.remove(projectPath: project.path, name: 'demo');
      expect(File(p.join(project.path, 'helper.py')).existsSync(), isTrue);
    },
  );

  test(
    'upgrade cannot depend on modules it removes from the old version',
    () async {
      var file = _zip(sources, 'distribution.zip', {
        'consumer.py': 'import retired\n',
        'retired.py': 'VALUE = 1\n',
      });
      expect((await install(file, version: '1')).success, isTrue);
      file = _zip(sources, 'distribution.zip', {
        'consumer.py': 'import retired\n',
      });
      final result = await install(file, version: '2');
      expect(result.success, isFalse);
      expect(result.issues.join(), contains('retired'));
      expect(installed('retired.py').readAsStringSync(), 'VALUE = 1\n');
      expect(
        (await service.show(
          projectPath: project.path,
          name: 'distribution',
        ))!.version,
        '1',
      );
    },
  );

  test('checks each direct import on semicolon-separated statements', () async {
    for (final text in [
      'import json; import socket\n',
      'VALUE = 1; from useful import missing\n',
    ]) {
      final result = await service.check(
        projectPath: project.path,
        sourcePath: source('consumer.py', text).path,
      );
      expect(result.compatible, isFalse, reason: text);
    }
    final result = await service.check(
      projectPath: project.path,
      sourcePath: source(
        'consumer.py',
        'TEXT = "; import socket"; import json # ; import ssl\n',
      ).path,
    );
    expect(result.compatible, isTrue, reason: result.message);
  });

  test(
    'upgrade cannot depend on a package whose initializer it removes',
    () async {
      var file = _zip(sources, 'distribution.zip', {
        'consumer.py': 'import retired\n',
        'retired/__init__.py': 'VALUE = 1\n',
      });
      expect((await install(file)).success, isTrue);
      file = _zip(sources, 'distribution.zip', {
        'consumer.py': 'import retired\n',
      });
      final result = await install(file);
      expect(result.success, isFalse);
      expect(result.issues.join(), contains('retired'));
      expect(installed('retired/__init__.py').existsSync(), isTrue);
    },
  );

  test(
    'upgrade retains access to a separate project-root dependency',
    () async {
      var file = _zip(sources, 'distribution.zip', {
        'consumer.py': 'import retired\n',
        'retired.py': 'VALUE = 1\n',
      });
      expect((await install(file)).success, isTrue);
      final rootDependency = File(p.join(project.path, 'retired.py'))
        ..writeAsStringSync('VALUE = 2\n');
      file = _zip(sources, 'distribution.zip', {
        'consumer.py': 'import retired\n',
      });
      final result = await install(file);
      expect(result.success, isTrue, reason: result.message);
      expect(installed('retired.py').existsSync(), isFalse);
      expect(rootDependency.readAsStringSync(), 'VALUE = 2\n');
    },
  );

  test(
    'project packages take precedence over bundled version and API metadata',
    () async {
      final file = source('useful.py', 'CUSTOM = 42\n');
      expect((await install(file, version: '2.0')).success, isTrue);
      source('consumer/main.py', 'from useful import CUSTOM\n');
      final metadata = source(
        'consumer/qfli-package.json',
        jsonEncode({
          'name': 'consumer',
          'requires': ['useful>=2.0'],
        }),
      );
      final result = await service.check(
        projectPath: project.path,
        sourcePath: metadata.parent.path,
      );
      expect(result.compatible, isTrue, reason: result.message);
    },
  );

  test(
    'imports inside string literals and comments are not dependencies',
    () async {
      final file = source(
        'docs.py',
        "\"\"\"Example:\nimport socket\nfrom os import path\n\"\"\"\n# import pip\nTEXT = 'import ssl'\nimport json\n",
      );
      final result = await service.check(
        projectPath: project.path,
        sourcePath: file.path,
      );
      expect(result.compatible, isTrue, reason: result.message);
    },
  );

  test('unmanaged files cannot be overwritten or adopted', () async {
    installed('demo.py').parent.createSync();
    installed('demo.py').writeAsStringSync('# mine\n');
    final result = await install(source('demo.py', 'VALUE = 1\n'));
    expect(result.success, isFalse);
    expect(installed('demo.py').readAsStringSync(), '# mine\n');
    expect(await service.listInstalled(projectPath: project.path), isEmpty);
  });

  test(
    'edited owned files block update and survive removal with unmanaged siblings',
    () async {
      source('demo/__init__.py', 'VALUE = 1\n');
      source('demo/helper.py', 'VALUE = 2\n');
      final path = p.join(sources.path, 'demo');
      expect(
        (await service.install(
          projectPath: project.path,
          sourcePath: path,
        )).success,
        isTrue,
      );
      installed('demo/helper.py').writeAsStringSync('# user edit\n');
      installed('demo/unmanaged.txt').writeAsStringSync('user file');
      source('demo/helper.py', 'VALUE = 3\n');
      expect(
        (await service.install(
          projectPath: project.path,
          sourcePath: path,
        )).success,
        isFalse,
      );
      final removed = await service.remove(
        projectPath: project.path,
        name: 'demo',
      );
      expect(removed.success, isTrue, reason: removed.message);
      expect(removed.preservedFiles, ['lib/demo/helper.py']);
      expect(installed('demo/__init__.py').existsSync(), isFalse);
      expect(installed('demo/helper.py').readAsStringSync(), '# user edit\n');
      expect(installed('demo/unmanaged.txt').readAsStringSync(), 'user file');
    },
  );

  test('update deletes only obsolete owned files', () async {
    source('demo/__init__.py', 'VALUE = 1\n');
    final obsolete = source('demo/old.py', 'VALUE = 2\n');
    final path = p.join(sources.path, 'demo');
    expect(
      (await service.install(
        projectPath: project.path,
        sourcePath: path,
      )).success,
      isTrue,
    );
    installed('demo/notes.txt').writeAsStringSync('keep');
    obsolete.deleteSync();
    source('demo/new.py', 'VALUE = 3\n');
    final result = await service.install(
      projectPath: project.path,
      sourcePath: path,
    );
    expect(result.success, isTrue, reason: result.message);
    expect(installed('demo/old.py').existsSync(), isFalse);
    expect(installed('demo/new.py').existsSync(), isTrue);
    expect(installed('demo/notes.txt').readAsStringSync(), 'keep');
  });

  test('one package cannot overwrite another package ownership', () async {
    final file = source('shared.py', 'VALUE = 1\n');
    expect((await install(file, name: 'first')).success, isTrue);
    final result = await install(file, name: 'second');
    expect(result.success, isFalse);
    expect(result.message, contains('first'));
    expect(
      (await service.listInstalled(projectPath: project.path)).single.name,
      'first',
    );
  });

  test(
    'separate projects get separate package installations and removal',
    () async {
      final other = Directory(p.join(temporary.path, 'other'))..createSync();
      final file = source('demo.py', 'VALUE = 9\n');
      expect((await install(file)).success, isTrue);
      expect(await service.listInstalled(projectPath: other.path), isEmpty);
      await service.install(projectPath: other.path, sourcePath: file.path);
      await service.remove(projectPath: project.path, name: 'demo');
      expect(
        File(p.join(other.path, 'lib/demo.py')).readAsStringSync(),
        'VALUE = 9\n',
      );
    },
  );

  test('cancellation during compilation leaves no files or manifest', () async {
    var cancelled = false;
    final cancelling = PythonPackageService(
      assets: assets,
      syntaxCheck: (_, _) async {
        cancelled = true;
        return null;
      },
    );
    final result = await cancelling.install(
      projectPath: project.path,
      sourcePath: source('demo.py', 'VALUE = 3\n').path,
      isCancelled: () => cancelled,
    );
    expect(result.success, isFalse);
    expect(project.listSync(), isEmpty);
  });

  test(
    'cancellation after publishing a file rolls back bytes and manifest',
    () async {
      final file = source('demo.py', 'VALUE = 1\n');
      expect((await install(file, version: '1')).success, isTrue);
      file.writeAsStringSync('VALUE = 2\n');
      final result = await service.install(
        projectPath: project.path,
        sourcePath: file.path,
        version: '2',
        isCancelled: () =>
            installed('demo.py').existsSync() &&
            installed('demo.py').readAsStringSync() == 'VALUE = 2\n',
      );
      expect(result.success, isFalse);
      expect(installed('demo.py').readAsStringSync(), 'VALUE = 1\n');
      expect(
        (await service.show(projectPath: project.path, name: 'demo'))!.version,
        '1',
      );
      expect(_transactions(project), isEmpty);
    },
  );

  test(
    'write/preflight failure cleans staging and preserves earlier package',
    () async {
      final file = source('demo.py', 'VALUE = 1\n');
      expect((await install(file)).success, isTrue);
      source('multi/other.py', 'VALUE = 4\n');
      source('multi/blocked/item.py', 'VALUE = 5\n');
      installed('blocked').writeAsStringSync('not a directory');
      final result = await service.install(
        projectPath: project.path,
        sourcePath: p.join(sources.path, 'multi'),
      );
      expect(result.success, isFalse);
      expect(installed('other.py').existsSync(), isFalse);
      expect(installed('demo.py').readAsStringSync(), 'VALUE = 1\n');
      expect(installed('blocked').readAsStringSync(), 'not a directory');
      expect(_transactions(project), isEmpty);
    },
  );

  test(
    'mid-commit write failure restores old bytes and ownership manifest',
    () async {
      var file = _zip(sources, 'multi.zip', {'first.py': 'VALUE = 1\n'});
      expect((await install(file)).success, isTrue);
      final manifest = File(
        p.join(project.path, '.qfli/python/packages.json'),
      ).readAsBytesSync();
      file = _zip(sources, 'multi.zip', {
        'first.py': 'VALUE = 2\n',
        'second.py': 'VALUE = 3\n',
      });
      final result = await service.install(
        projectPath: project.path,
        sourcePath: file.path,
        isCancelled: () {
          if (installed('first.py').readAsStringSync() == 'VALUE = 2\n' &&
              !Directory(installed('second.py').path).existsSync()) {
            Directory(installed('second.py').path).createSync();
          }
          return false;
        },
      );
      expect(result.success, isFalse);
      expect(installed('first.py').readAsStringSync(), 'VALUE = 1\n');
      expect(
        File(
          p.join(project.path, '.qfli/python/packages.json'),
        ).readAsBytesSync(),
        manifest,
      );
      expect(
        Directory(installed('second.py').path).existsSync(),
        isTrue,
        reason: 'preserve an external actor\'s directory',
      );
      expect(_transactions(project), isEmpty);
    },
  );

  test(
    'cancellation during uninstall restores previously removed files',
    () async {
      final file = _zip(sources, 'multi.zip', {
        'first.py': 'VALUE = 1\n',
        'second.py': 'VALUE = 2\n',
      });
      expect((await install(file)).success, isTrue);
      final result = await service.remove(
        projectPath: project.path,
        name: 'multi',
        isCancelled: () => !installed('first.py').existsSync(),
      );
      expect(result.success, isFalse);
      expect(installed('first.py').readAsStringSync(), 'VALUE = 1\n');
      expect(installed('second.py').readAsStringSync(), 'VALUE = 2\n');
      expect(
        (await service.listInstalled(projectPath: project.path)).single.name,
        'multi',
      );
      expect(_transactions(project), isEmpty);
    },
  );

  test('different service instances serialize same-project installs', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final first = PythonPackageService(
      assets: assets,
      syntaxCheck: (_, _) async {
        entered.complete();
        await release.future;
        return null;
      },
    );
    final one = first.install(
      projectPath: project.path,
      sourcePath: source('first.py', 'A = 1\n').path,
    );
    await entered.future;
    final two = service.install(
      projectPath: project.path,
      sourcePath: source('second.py', 'B = 2\n').path,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      compiled,
      isEmpty,
      reason: 'second install must await first transaction',
    );
    release.complete();
    expect((await one).success, isTrue);
    expect((await two).success, isTrue);
    expect(
      (await service.listInstalled(
        projectPath: project.path,
      )).map((item) => item.name),
      ['first', 'second'],
    );
  });

  test('dependency versions are checked locally with no resolver', () async {
    await install(source('dep.py', 'VALUE = 1\n'), version: '1.2.0');
    source('consumer/main.py', 'import dep\n');
    final metadata = source(
      'consumer/qfli-package.json',
      jsonEncode({
        'name': 'consumer',
        'requires': ['dep (>=1.0,<2.0)'],
      }),
    );
    var result = await service.check(
      projectPath: project.path,
      sourcePath: metadata.parent.path,
    );
    expect(result.compatible, isTrue, reason: result.message);
    metadata.writeAsStringSync(
      jsonEncode({
        'name': 'consumer',
        'requires': ['dep>=2.0'],
      }),
    );
    result = await service.check(
      projectPath: project.path,
      sourcePath: metadata.parent.path,
    );
    expect(result.compatible, isFalse);
    expect(result.issues.join(), contains('1.2.0'));
    metadata.writeAsStringSync(
      jsonEncode({
        'name': 'consumer',
        'requires': ['missing'],
      }),
    );
    result = await service.check(
      projectPath: project.path,
      sourcePath: metadata.parent.path,
    );
    expect(result.compatible, isFalse);
    expect(result.issues.join(), contains('不会联网下载'));
    metadata.writeAsStringSync(
      jsonEncode({
        'name': 'consumer',
        'requires': ['dep; python_version >= "3"'],
      }),
    );
    result = await service.check(
      projectPath: project.path,
      sourcePath: metadata.parent.path,
    );
    expect(result.compatible, isFalse);
    expect(result.issues.join(), contains('依赖条件'));
  });

  test('pure source zip installs a package and data', () async {
    final file = _zip(sources, 'zipped.zip', {
      'zipped/__init__.py': 'from .helper import VALUE\n',
      'zipped/helper.py': 'VALUE = 8\n',
      'zipped/data.json': '{"value":8}',
    });
    final result = await install(file);
    expect(result.success, isTrue, reason: result.message);
    expect(installed('zipped/helper.py').readAsStringSync(), 'VALUE = 8\n');
    expect(result.package!.files.length, 3);
  });

  test('wheel metadata accepts explicit pure Python sources only', () async {
    final file = _zip(sources, 'demo-1.0-py3-none-any.whl', _wheel());
    final result = await install(file);
    expect(result.success, isTrue, reason: result.message);
    expect(result.package!.name, 'demo');
    expect(result.package!.version, '1.0');
    expect(result.package!.files.keys, ['lib/demo.py']);
    expect(installed('demo-1.0.dist-info/METADATA').existsSync(), isFalse);
  });

  test(
    'rejects native wheel tags, dishonest metadata and CPython requirements',
    () async {
      for (final scenario in [
        ('demo-1.0-cp311-cp311-win_amd64.whl', _wheel()),
        ('demo-1.0-py3-none-any.whl', _wheel(purelib: 'false')),
        (
          'demo-1.0-py3-none-any.whl',
          _wheel(extraMetadata: 'Requires-Python: >=3.11\n'),
        ),
        (
          'demo-1.0-py3-none-any.whl',
          _wheel(extraMetadata: 'Requires-Dist: not-installed\n'),
        ),
        ('demo-1.0-py3-none-any.whl', {..._wheel(), 'demo.pyd': 'binary'}),
        (
          'demo-1.0-py3-none-any.whl',
          {
            ..._wheel(),
            'demo-1.0.dist-info/entry_points.txt': '[console_scripts]\n',
          },
        ),
      ]) {
        final file = _zip(sources, scenario.$1, scenario.$2);
        final result = await install(file);
        expect(
          result.success,
          isFalse,
          reason: '${scenario.$1}: ${result.message}',
        );
        expect(project.listSync(), isEmpty);
      }
    },
  );

  test(
    'rejects traversal, Windows path aliases, setup scripts and binary files',
    () async {
      for (final path in [
        '../outside.py',
        '/absolute.py',
        'C:/drive.py',
        'bad\\path.py',
        'data/../escape.py',
        'con.py',
        'trailing./x.py',
        'package/setup.py',
        'module.so',
        'module.mpy',
      ]) {
        final file = _zip(sources, 'bad.zip', {
          'good.py': 'VALUE = 1\n',
          path: 'VALUE = 2\n',
        });
        expect((await install(file)).success, isFalse, reason: path);
        expect(project.listSync(), isEmpty);
      }
    },
  );

  test('rejects case-colliding archive filenames', () async {
    final file = _zip(sources, 'duplicate.zip', {
      'demo.py': 'A = 1\n',
      'DEMO.py': 'A = 2\n',
    });
    expect((await install(file)).success, isFalse);
    expect(project.listSync(), isEmpty);
  });

  test(
    'rejects encrypted archives, CRC mismatches and oversized expanded files',
    () async {
      final encrypted = File(p.join(sources.path, 'encrypted.zip'))
        ..writeAsBytesSync(
          ZipEncoder(password: 'local-only').encode(
            Archive()..add(ArchiveFile.string('demo.py', 'VALUE = 1\n')),
          ),
        );
      expect((await install(encrypted)).success, isFalse);
      final corrupt = File(p.join(sources.path, 'corrupt.zip'));
      final bytes = ZipEncoder().encode(
        Archive()..add(
          ArchiveFile.noCompress('demo.py', 10, utf8.encode('VALUE = 1\n')),
        ),
      );
      final position = _findBytes(bytes, utf8.encode('VALUE = 1\n'));
      expect(position, isNonNegative);
      bytes[position + 8] = '2'.codeUnitAt(0);
      corrupt.writeAsBytesSync(bytes);
      final invalid = await install(corrupt);
      expect(invalid.success, isFalse);
      expect(invalid.message, contains('校验失败'));
      final oversized = _zip(sources, 'oversized.zip', {
        'demo.py': 'a' * (2 * 1024 * 1024 + 1),
      });
      expect((await install(oversized)).success, isFalse);
      expect(project.listSync(), isEmpty);
    },
  );

  test('rejects archive symlinks without extracting any entries', () async {
    final archive = Archive()
      ..add(ArchiveFile.string('good.py', 'A = 1\n'))
      ..add(ArchiveFile.string('linked.py', '../outside.py')..mode = 0xa1ff);
    final file = File(p.join(sources.path, 'symlink.zip'))
      ..writeAsBytesSync(ZipEncoder().encode(archive));
    final result = await install(file);
    expect(result.success, isFalse);
    expect(project.listSync(), isEmpty);
  });

  test(
    'bounds actual inflation when ZIP metadata understates its size',
    () async {
      final file = _zip(sources, 'understated.zip', {
        'demo.py': '#${'a' * (2 * 1024 * 1024)}\n',
      });
      final bytes = file.readAsBytesSync();
      final central = _findBytes(bytes, [0x50, 0x4b, 0x01, 0x02]);
      expect(central, isNonNegative);
      ByteData.sublistView(bytes).setUint32(central + 24, 8, Endian.little);
      file.writeAsBytesSync(bytes);
      final result = await install(file);
      expect(result.success, isFalse);
      expect(result.message, contains('展开内容超过声明大小'));
      expect(project.listSync(), isEmpty);
    },
  );

  test('corrupt package ownership manifest is never discarded', () async {
    final manifest = File(p.join(project.path, '.qfli/python/packages.json'));
    manifest.parent.createSync(recursive: true);
    manifest.writeAsStringSync('{invalid json');
    final result = await install(source('demo.py', 'A = 1\n'));
    expect(result.success, isFalse);
    expect(manifest.readAsStringSync(), '{invalid json');
    expect(installed('demo.py').existsSync(), isFalse);
  });

  test(
    'filesystem links cannot redirect package writes outside the project',
    () async {
      final outside = Directory(p.join(temporary.path, 'outside'))
        ..createSync();
      try {
        Link(p.join(project.path, 'lib')).createSync(outside.path);
      } on FileSystemException {
        markTestSkipped('Host does not permit creating filesystem symlinks.');
        return; // Windows hosts without symlink entitlement cannot exercise it.
      }
      final result = await install(source('demo.py', 'A = 1\n'));
      expect(result.success, isFalse);
      expect(outside.listSync(), isEmpty);
    },
  );

  final nativeDll = p.absolute('native/build/windows/qfli_py_ffi.dll');
  test(
    'real embedded compiler accepts source and rejects syntax without execution',
    () async {
      final runner = PythonProgramRunner(
        transport: PythonNativeTransport.ffi,
        libraryPath: nativeDll,
      );
      final real = PythonPackageService(
        assets: assets,
        syntaxCheck: (text, path) async {
          final result = await runner.checkSource(
            projectPath: project.path,
            entryFile: path,
            source: text,
          );
          return result.success ? null : result.error;
        },
      );
      final file = source(
        'native_demo.py',
        'open("must_not_exist.txt", "w").write("not executed")\nVALUE = 42\n',
      );
      var result = await real.install(
        projectPath: project.path,
        sourcePath: file.path,
      );
      expect(result.success, isTrue, reason: result.message);
      expect(
        File(p.join(project.path, 'must_not_exist.txt')).existsSync(),
        isFalse,
      );
      file.writeAsStringSync('def broken(:\n');
      result = await real.install(
        projectPath: project.path,
        sourcePath: file.path,
      );
      expect(result.success, isFalse);
      expect(result.message, contains('SyntaxError'));
      expect(
        installed('native_demo.py').readAsStringSync(),
        contains('VALUE = 42'),
      );
    },
    skip: !File(nativeDll).existsSync()
        ? 'Native host DLL is absent; VM gate remains open.'
        : false,
  );
}

Map<String, String> _wheel({
  String purelib = 'true',
  String extraMetadata = '',
}) => {
  'demo.py': 'VALUE = 42\n',
  'demo-1.0.dist-info/WHEEL':
      'Wheel-Version: 1.0\nRoot-Is-Purelib: $purelib\nTag: py3-none-any\n',
  'demo-1.0.dist-info/METADATA':
      'Metadata-Version: 2.1\nName: demo\nVersion: 1.0\n$extraMetadata',
};

File _zip(Directory directory, String name, Map<String, String> entries) {
  final archive = Archive();
  for (final entry in entries.entries) {
    archive.add(ArchiveFile.string(entry.key, entry.value));
  }
  final bytes = ZipEncoder().encode(archive);
  // ZipEncoder normalizes path separators. Retain hostile names explicitly so
  // this regression exercises the installer's metadata validation.
  for (final path in entries.keys.where((path) => path.contains('\\'))) {
    final normalized = utf8.encode(path.replaceAll('\\', '/'));
    final original = utf8.encode(path);
    for (var index = 0; index <= bytes.length - normalized.length; index++) {
      var matches = true;
      for (var offset = 0; offset < normalized.length; offset++) {
        if (bytes[index + offset] != normalized[offset]) matches = false;
      }
      if (matches) {
        bytes.setRange(index, index + original.length, original);
      }
    }
  }
  return File(p.join(directory.path, name))..writeAsBytesSync(bytes);
}

int _findBytes(List<int> bytes, List<int> search) {
  for (var index = 0; index <= bytes.length - search.length; index++) {
    var matches = true;
    for (var offset = 0; offset < search.length; offset++) {
      if (bytes[index + offset] != search[offset]) matches = false;
    }
    if (matches) return index;
  }
  return -1;
}

List<FileSystemEntity> _transactions(Directory project) => project
    .listSync(recursive: true, followLinks: false)
    .where(
      (entry) => p.basename(entry.path).startsWith('.package-transaction-'),
    )
    .toList();

class _Assets extends CachingAssetBundle {
  _Assets(Map<String, String> files) {
    final entries = [
      for (final file in files.entries)
        {
          'path': file.key,
          'sha256': sha256.convert(utf8.encode(file.value)).toString(),
        },
    ];
    manifest = {
      'formatVersion': 1,
      'bundleVersion': 'v1',
      'modules': [
        {
          'name': 'useful',
          'version': '1.0',
          'summary': 'Useful local functions',
          'apis': ['add'],
          'license': 'MIT',
          'source': 'test fixture',
          'files': entries,
        },
      ],
      'files': entries,
    };
    content = files.map((key, value) => MapEntry(key, utf8.encode(value)));
  }

  late Map<String, dynamic> manifest;
  late Map<String, List<int>> content;

  @override
  Future<ByteData> load(String key) async {
    const prefix = 'assets/python_stdlib/';
    if (key == '${prefix}manifest.json') {
      return ByteData.sublistView(
        Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
      );
    }
    final bytes = content[key.substring(prefix.length)];
    if (bytes == null) throw StateError('missing asset $key');
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      utf8.decode((await load(key)).buffer.asUint8List());
}
