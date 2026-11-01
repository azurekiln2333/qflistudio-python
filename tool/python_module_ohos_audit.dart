/// Embedded module/package acceptance, shared by the generated OHOS entry and
/// host tests. Generate the entry with prepare_python_module_audit.py; the
/// portable Python behavior suite remains the only authored suite source.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_python/python_packages.dart';
import 'package:qfli_python/python_runner.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

const pythonModuleAuditReportName = 'qfli-python-module-audit.json';

void startPythonModuleAudit({
  required String suiteSource,
  required String suiteSha256,
  required Map<String, String> assetDigests,
  Map<String, Object?> buildEvidence = const {},
}) {
  WidgetsFlutterBinding.ensureInitialized();
  final status = ValueNotifier('Python module acceptance is running…');
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: ValueListenableBuilder<String>(
          valueListenable: status,
          builder: (_, value, _) => Text(value),
        ),
      ),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      final storage = await AppPaths.storageDirectory().timeout(
        const Duration(seconds: 20),
      );
      if (storage == null) throw StateError('No writable AppPaths storage');
      final report = await runPythonModuleAudit(
        storage: Directory(storage),
        suiteSource: suiteSource,
        suiteSha256: suiteSha256,
        assetDigests: assetDigests,
        buildEvidence: buildEvidence,
        onProgress: (stage) {
          status.value = 'Python module acceptance: $stage';
          debugPrint('QFLI_PYTHON_MODULE_STAGE $stage');
        },
      );
      final summary = {
        'ok': report['ok'],
        'hostGatePassed': report['hostGatePassed'],
        'deviceGatePassed': report['deviceGatePassed'],
        'operatingSystem': Platform.operatingSystem,
        'reportFile': report['reportFile'],
        'reportSha256': _digest(
          await File(report['reportFile']! as String).readAsBytes(),
        ),
      };
      status.value = const JsonEncoder.withIndent('  ').convert(summary);
      debugPrint('QFLI_PYTHON_MODULE_AUDIT ${jsonEncode(summary)}');
    } catch (error, stack) {
      final failure = {
        'ok': false,
        'deviceGatePassed': false,
        'error': '$error',
        'stack': '$stack',
      };
      status.value = jsonEncode(failure);
      debugPrint('QFLI_PYTHON_MODULE_AUDIT ${jsonEncode(failure)}');
    }
  });
}

/// Exercises actual services and the selected embedded transport. A host result
/// never satisfies [deviceGatePassed], even when every behavior passes.
/// Build hashes identify declared build inputs; the separate HAP inspector must
/// bind those inputs to the packaged SO. They are not a hash of loaded memory.
Future<Map<String, Object?>> runPythonModuleAudit({
  required Directory storage,
  required String suiteSource,
  required String suiteSha256,
  required Map<String, String> assetDigests,
  Map<String, Object?> buildEvidence = const {},
  PythonProgramRunner? runner,
  AssetBundle? assets,
  Duration operationTimeout = const Duration(seconds: 90),
  Duration settleTimeout = const Duration(seconds: 15),
  void Function(String stage)? onProgress,
}) async {
  await storage.create(recursive: true);
  final reportFile = File(p.join(storage.path, pythonModuleAuditReportName));
  final work = await storage.createTemp('qfli_python_module_audit_');
  final project = await Directory(p.join(work.path, '课程 project')).create();
  final sources = await Directory(p.join(work.path, 'sources')).create();
  final bundle = assets ?? rootBundle;
  final compiler = runner ?? const PythonProgramRunner();
  final tracker = _PendingOperations(operationTimeout, settleTimeout);
  final records = <Map<String, Object?>>[];
  final report = <String, Object?>{
    'schemaVersion': 1,
    'kind': 'python-module-package-acceptance',
    'expectedBundleName': 'com.azurekiln.qfli.pyflow',
    'expectedOhosPullPath':
        '/data/app/el2/100/base/com.azurekiln.qfli.pyflow/files/$pythonModuleAuditReportName',
    'startedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'operatingSystem': Platform.operatingSystem,
    'operatingSystemVersion': Platform.operatingSystemVersion,
    'dartVersion': Platform.version,
    'reportFile': reportFile.path,
    'workDirectory': work.path,
    'suiteSha256': suiteSha256,
    'declaredBuildInputs': buildEvidence,
    'cases': records,
    'ok': false,
    'hostGatePassed': false,
    'deviceGatePassed': false,
    'status': 'running',
  };

  Future<void> persist(String stage) async {
    report['stage'] = stage;
    report['updatedAtUtc'] = DateTime.now().toUtc().toIso8601String();
    await reportFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
    onProgress?.call(stage);
  }

  void require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  Future<void> scenario(String name, Future<void> Function() body) async {
    final record = <String, Object?>{'name': name, 'ok': false};
    records.add(record);
    await persist(name);
    try {
      await body();
      record['ok'] = true;
    } catch (error) {
      record['error'] = '$error';
      rethrow;
    } finally {
      await persist(name);
    }
  }

  late final PythonRuntimeInfo runtime;
  try {
    await scenario('runtime', () async {
      runtime = await tracker.wait(compiler.runtimeInfo(), 'runtime probe');
      report['runtime'] = {
        'available': runtime.available,
        'version': runtime.version,
        'detail': runtime.detail,
        'transport': runtime.transport,
        'supportsCancellation': runtime.supportsCancellation,
      };
      require(
        runtime.available,
        'Embedded runtime unavailable: ${runtime.detail}',
      );
      require(
        runtime.supportsCancellation,
        'Acceptance requires real Stop support',
      );
    });
    await scenario('suite-and-assets', () async {
      require(
        _digest(utf8.encode(suiteSource)) == suiteSha256,
        'Suite hash mismatch',
      );
      require(
        assetDigests.containsKey('assets/python_stdlib/manifest.json'),
        'Missing manifest digest',
      );
      final verified = <String, String>{};
      for (final entry in assetDigests.entries) {
        require(
          entry.key.startsWith('assets/python_stdlib/') &&
              !entry.key.contains('..'),
          'Unexpected asset path',
        );
        final data = await tracker.wait(
          bundle.load(entry.key),
          'asset ${entry.key}',
        );
        final actual = _digest(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        require(
          actual == entry.value,
          'Packaged asset hash mismatch: ${entry.key}',
        );
        verified[entry.key] = actual;
      }
      report['verifiedPackagedAssets'] = verified;
    });

    final packages = PythonPackageService(
      assets: bundle,
      syntaxCheck: (source, file) async {
        final result = await tracker.wait(
          compiler.checkSource(
            projectPath: project.path,
            entryFile: file,
            source: source,
          ),
          'embedded compile-only',
        );
        return result.success
            ? null
            : result.error.isEmpty
            ? 'Embedded compiler rejected source'
            : result.error;
      },
    );
    final execution = runner ?? PythonProgramRunner(packageService: packages);
    final runs = <Map<String, Object?>>[];
    report['runs'] = runs;
    Future<_RunOutput> run(
      String source, {
      Directory? root,
      String entryName = 'main.py',
    }) async {
      final selected = root ?? project;
      final entry = File(p.join(selected.path, 'src', entryName));
      await entry.parent.create(recursive: true);
      await entry.writeAsString(source, flush: true);
      final output = await _execute(tracker, execution, selected, entry);
      runs.add({
        'project': p.relative(selected.path, from: work.path),
        'entry': p.relative(entry.path, from: selected.path),
        'sourceSha256': _digest(utf8.encode(source)),
        'exitCode': output.exitCode,
        'stdout': output.stdout,
        'stderr': output.stderr,
      });
      return output;
    }

    Future<void> expectRun(String source, List<String> expected) async {
      final result = await run(source);
      require(
        result.exitCode == 0 &&
            result.stderr.isEmpty &&
            listEquals(result.stdout, expected),
        'Unexpected embedded result: ${result.exitCode} ${result.stdout} ${result.stderr}',
      );
    }

    await scenario('portable-stdlib-behavior', () async {
      final result = await run(suiteSource, entryName: 'stdlib_smoke.py');
      require(
        result.exitCode == 0 && result.stderr.isEmpty,
        'Stdlib suite failed: ${result.stderr}',
      );
      final markers = result.stdout
          .where((line) => RegExp(r'^QFLI_STDLIB_PASS \d+$').hasMatch(line))
          .toList();
      require(
        markers.length == 1,
        'Missing unambiguous stdlib completion marker',
      );
      final count = int.parse(markers.single.split(' ').last);
      require(
        count >= 250 &&
            result.stdout.where((line) => line.startsWith('PASS ')).length ==
                count,
        'Stdlib assertion count mismatch: $count',
      );
      final catalog = await tracker.wait(
        packages.moduleCatalog,
        'module catalog',
      );
      final bundled = catalog
          .where((module) => module.origin == PythonModuleOrigin.bundled)
          .toList();
      require(bundled.length >= 10, 'Fewer than ten bundled modules');
      report['stdlib'] = {
        'assertions': count,
        'modules': bundled.map((module) => module.name).toList(),
      };
    });
    await scenario('repeat-bundle-preserves-files', () async {
      final directory = Directory(
        p.join(project.path, '.qfli', 'python', 'bundled', 'v1'),
      );
      final before = <String, String>{};
      for (final file in directory.listSync().whereType<File>()) {
        before[file.path] =
            '${file.statSync().modified.microsecondsSinceEpoch}:${_digest(file.readAsBytesSync())}';
      }
      require(before.length >= 10, 'Missing prepared module files');
      await expectRun('print("QFLI_REPEAT_BUNDLE")\n', ['QFLI_REPEAT_BUNDLE']);
      require(
        before.entries.every((entry) {
          final file = File(entry.key);
          return file.existsSync() &&
              '${file.statSync().modified.microsecondsSinceEpoch}:${_digest(file.readAsBytesSync())}' ==
                  entry.value;
        }),
        'Repeat preparation rewrote module files',
      );
    });

    final package = await Directory(
      p.join(sources.path, 'audit_mathpack'),
    ).create();
    final initializer = File(p.join(package.path, '__init__.py'));
    final values = File(p.join(package.path, 'values.py'));
    final marker = File(p.join(project.path, 'audit_import_executed.txt'));
    await initializer.writeAsString(
      'open("audit_import_executed.txt", "w").write("executed")\nfrom .values import summarize\n',
    );
    await values.writeAsString(
      'from statistics import mean\nfrom itertools import accumulate\ndef summarize(values):\n return mean(values), list(accumulate(values))\n',
    );

    await scenario('package-check-and-install-no-execution', () async {
      final check = await tracker.wait(
        packages.check(
          projectPath: project.path,
          sourcePath: package.path,
          version: '1.0',
        ),
        'package check',
      );
      require(check.compatible, check.message);
      require(
        !marker.existsSync(),
        'Compile-only check executed package initializer',
      );
      require(
        (await packages.listInstalled(projectPath: project.path)).isEmpty,
        'Check installed a package',
      );
      final installed = await tracker.wait(
        packages.install(
          projectPath: project.path,
          sourcePath: package.path,
          version: '1.0',
        ),
        'package install',
      );
      require(installed.success, installed.message);
      require(
        !marker.existsSync(),
        'Installation executed package initializer',
      );
      final shown = await packages.show(
        projectPath: project.path,
        name: 'audit_mathpack',
      );
      require(
        shown != null && shown.version == '1.0' && shown.files.length == 2,
        'Package metadata mismatch',
      );
      require(
        shown!.files.entries.every(
          (entry) =>
              _digest(
                File(p.join(project.path, entry.key)).readAsBytesSync(),
              ) ==
              entry.value,
        ),
        'Installed package digest mismatch',
      );
      await expectRun(
        'from audit_mathpack import summarize\nprint(summarize([2, 4, 6]))\n',
        ['(4.0, [2, 6, 12])'],
      );
      require(
        marker.readAsStringSync() == 'executed',
        'Actual import did not execute initializer',
      );
      await marker.delete();
    });
    await scenario('package-project-boundary', () async {
      final other = await Directory(
        p.join(work.path, 'other project'),
      ).create();
      final missing = await run('import audit_mathpack\n', root: other);
      require(
        missing.exitCode == 1 &&
            missing.stderr.join('\n').contains('ImportError'),
        'Package leaked between projects',
      );
      require(
        (await packages.listInstalled(projectPath: other.path)).isEmpty,
        'Package registry leaked between projects',
      );
    });
    await scenario('package-update-and-vm-freshness', () async {
      await values.writeAsString(
        'def summarize(values):\n return sum(values) * 2\n',
      );
      final updated = await tracker.wait(
        packages.install(
          projectPath: project.path,
          sourcePath: package.path,
          version: '2.0',
        ),
        'package update',
      );
      require(updated.success, updated.message);
      require(!marker.existsSync(), 'Update executed package initializer');
      require(
        (await packages.show(
              projectPath: project.path,
              name: 'audit_mathpack',
            ))?.version ==
            '2.0',
        'Updated version missing',
      );
      await expectRun(
        'from audit_mathpack import summarize\nprint(summarize([2, 4, 6]))\n',
        ['24'],
      );
      await marker.delete();
    });
    await scenario('rejected-update-preserves-installed-version', () async {
      final installedFile = File(
        p.join(project.path, 'lib', 'audit_mathpack', 'values.py'),
      );
      final before = _digest(await installedFile.readAsBytes());
      await values.writeAsString('if True\n invalid = 0\n');
      final rejected = await tracker.wait(
        packages.install(
          projectPath: project.path,
          sourcePath: package.path,
          version: '3.0',
        ),
        'invalid package update',
      );
      require(
        !rejected.success && rejected.issues.join('\n').contains('SyntaxError'),
        'Invalid source was not rejected by embedded compiler',
      );
      require(
        _digest(await installedFile.readAsBytes()) == before,
        'Rejected update changed installed source',
      );
      require(
        (await packages.show(
              projectPath: project.path,
              name: 'audit_mathpack',
            ))?.version ==
            '2.0',
        'Rejected update changed installed version',
      );
      require(!marker.existsSync(), 'Rejected update executed package');
      await expectRun(
        'from audit_mathpack import summarize\nprint(summarize([2, 4, 6]))\n',
        ['24'],
      );
      await marker.delete();
      await values.writeAsString(
        'def summarize(values):\n return sum(values) * 2\n',
      );
    });
    await scenario('remove-and-import-recovery', () async {
      final removed = await tracker.wait(
        packages.remove(projectPath: project.path, name: 'audit_mathpack'),
        'package remove',
      );
      require(
        removed.success && removed.preservedFiles.isEmpty,
        removed.message,
      );
      require(
        !File(
          p.join(project.path, 'lib', 'audit_mathpack', '__init__.py'),
        ).existsSync(),
        'Uninstall left owned initializer',
      );
      require(
        (await packages.listInstalled(projectPath: project.path)).isEmpty,
        'Uninstall left package registration',
      );
      // Empty package directories may remain after owned files are removed;
      // MicroPython can import those as namespaces. The removed API must fail.
      final missing = await run('from audit_mathpack import summarize\n');
      require(
        missing.exitCode == 1 &&
            missing.stderr.join('\n').contains('ImportError'),
        'Removed package API still imports',
      );
      await expectRun('from statistics import mean\nprint(mean([2, 4]))\n', [
        '3.0',
      ]);
    });
    await scenario('unmanaged-conflict-and-cancellation', () async {
      final unmanaged = File(p.join(project.path, 'lib', 'audit_conflict.py'));
      await unmanaged.writeAsString('value = "user-owned"\n');
      final candidate = File(p.join(sources.path, 'audit_conflict.py'));
      await candidate.writeAsString('value = "replacement"\n');
      final conflict = await tracker.wait(
        packages.install(projectPath: project.path, sourcePath: candidate.path),
        'unmanaged conflict',
      );
      require(
        !conflict.success &&
            unmanaged.readAsStringSync() == 'value = "user-owned"\n',
        'Unmanaged conflict overwrote user source',
      );
      final cancelled = await tracker.wait(
        packages.install(
          projectPath: project.path,
          sourcePath: package.path,
          isCancelled: () => true,
        ),
        'cancelled install',
      );
      require(
        !cancelled.success &&
            (await packages.listInstalled(projectPath: project.path)).isEmpty,
        'Cancelled install changed package registry',
      );
      await unmanaged.delete();
    });
    await scenario('edited-owned-file-preserved', () async {
      final installed = await tracker.wait(
        packages.install(
          projectPath: project.path,
          sourcePath: package.path,
          version: '2.0',
        ),
        'reinstall for ownership check',
      );
      require(installed.success, installed.message);
      final edited = File(
        p.join(project.path, 'lib', 'audit_mathpack', 'values.py'),
      );
      await edited.writeAsString('def summarize(values):\n return 99\n');
      final conflict = await tracker.wait(
        packages.install(
          projectPath: project.path,
          sourcePath: package.path,
          version: '3.0',
        ),
        'edited file update conflict',
      );
      require(
        !conflict.success && edited.readAsStringSync().contains('return 99'),
        'Update overwrote edited owned source',
      );
      final removed = await tracker.wait(
        packages.remove(projectPath: project.path, name: 'audit_mathpack'),
        'edited package remove',
      );
      require(
        removed.success &&
            removed.preservedFiles.contains('lib/audit_mathpack/values.py'),
        'Uninstall failed to report preserved edited source',
      );
      require(
        edited.readAsStringSync().contains('return 99'),
        'Uninstall deleted edited source',
      );
      require(
        (await packages.listInstalled(projectPath: project.path)).isEmpty,
        'Edited uninstall left registration',
      );
    });
    await scenario('local-archive-and-unsupported-module', () async {
      final archive = Archive()
        ..addFile(ArchiveFile.string('audit_zip/__init__.py', 'value = 73\n'));
      final archiveFile = File(p.join(sources.path, 'audit_zip.zip'));
      await archiveFile.writeAsBytes(ZipEncoder().encode(archive));
      final installed = await tracker.wait(
        packages.install(
          projectPath: project.path,
          sourcePath: archiveFile.path,
        ),
        'local zip install',
      );
      require(installed.success, installed.message);
      await expectRun('import audit_zip\nprint(audit_zip.value)\n', ['73']);
      require(
        (await packages.remove(
          projectPath: project.path,
          name: 'audit_zip',
        )).success,
        'ZIP package removal failed',
      );
      final unsupported = File(p.join(sources.path, 'audit_unsupported.py'));
      await unsupported.writeAsString('import socket\n');
      final rejected = await tracker.wait(
        packages.check(projectPath: project.path, sourcePath: unsupported.path),
        'unsupported module check',
      );
      require(
        !rejected.compatible && rejected.issues.join('\n').contains('socket'),
        'Unsupported module was accepted',
      );
      require(
        !File(p.join(project.path, 'lib', 'audit_unsupported.py')).existsSync(),
        'Compatibility check installed unsupported source',
      );
    });
    await scenario('automatic-import-precedence', () async {
      final entry = File(p.join(project.path, 'src', 'audit_precedence.py'));
      final root = File(p.join(project.path, 'audit_precedence.py'));
      final local = File(p.join(project.path, 'lib', 'audit_precedence.py'));
      await entry.writeAsString('value = "entry"\n');
      await root.writeAsString('value = "root"\n');
      await local.writeAsString('value = "lib"\n');
      const source = 'import audit_precedence\nprint(audit_precedence.value)\n';
      await expectRun(source, ['entry']);
      await entry.delete();
      await expectRun(source, ['root']);
      await root.delete();
      await expectRun(source, ['lib']);
      final override = File(p.join(project.path, 'lib', 'csv.py'));
      await override.writeAsString('origin = "project-lib"\n');
      await expectRun('import csv\nprint(csv.origin)\n', ['project-lib']);
      await override.delete();
      await expectRun('import csv\nprint(list(csv.reader(["a,b"])))\n', [
        "[['a', 'b']]",
      ]);
    });
    report['ok'] = true;
    report['hostGatePassed'] = Platform.operatingSystem != 'ohos';
    report['deviceGatePassed'] =
        Platform.operatingSystem == 'ohos' &&
        runtime.transport == 'methodChannel';
    report['status'] = 'passed';
  } catch (error, stack) {
    report['status'] = 'failed';
    report['error'] = '$error';
    report['stack'] = '$stack';
  } finally {
    await tracker.settle();
    report['pendingOperations'] = tracker.pendingCount;
    report['cancellationErrors'] = tracker.cancellationErrors;
    report['cleanupConfirmed'] = tracker.pendingCount == 0;
    if (tracker.pendingCount == 0) {
      try {
        await work.delete(recursive: true);
        report['workDirectoryRemoved'] = true;
      } catch (error) {
        report['workDirectoryRemoved'] = false;
        report['cleanupError'] = '$error';
        report['ok'] = false;
        report['hostGatePassed'] = false;
        report['deviceGatePassed'] = false;
        report['status'] = 'failed';
      }
    } else {
      report['workDirectoryRemoved'] = false;
      report['ok'] = false;
      report['hostGatePassed'] = false;
      report['deviceGatePassed'] = false;
      report['status'] = 'failed';
      report['retentionReason'] =
          'Underlying work has not settled; directory retained to avoid deleting active files.';
    }
    report['finishedAtUtc'] = DateTime.now().toUtc().toIso8601String();
    await persist('complete');
  }
  return report;
}

String _digest(List<int> bytes) => sha256.convert(bytes).toString();

class _RunOutput {
  const _RunOutput(this.exitCode, this.stdout, this.stderr);
  final int exitCode;
  final List<String> stdout;
  final List<String> stderr;
}

Future<_RunOutput> _execute(
  _PendingOperations tracker,
  PythonProgramRunner runner,
  Directory project,
  File entry,
) {
  ProgramRunResult? handle;
  var stopRequested = false;
  Future<void> cancel() async {
    stopRequested = true;
    await handle?.cancel?.call();
  }

  final pending = () async {
    final result = await runner.run(
      projectPath: project.path,
      entryFile: entry.path,
    );
    handle = result;
    if (result == null) throw StateError('Runner declined the Python entry');
    final stdout = result.stdout.toList();
    final stderr = result.stderr.toList();
    if (stopRequested) {
      unawaited(
        cancel().catchError(
          (Object error) => tracker.cancellationErrors.add('$error'),
        ),
      );
    }
    final exit = await result.exitCode;
    return _RunOutput(exit, await stdout, await stderr);
  }();
  return tracker.wait(
    pending,
    'embedded ${p.basename(entry.path)}',
    onTimeout: cancel,
  );
}

class _PendingOperations {
  _PendingOperations(this.deadline, this.settleDeadline);
  final Duration deadline;
  final Duration settleDeadline;
  final Set<Future<void>> _pending = {};
  final List<String> cancellationErrors = [];
  int get pendingCount => _pending.length;

  Future<T> wait<T>(
    Future<T> operation,
    String label, {
    Future<void> Function()? onTimeout,
  }) async {
    final settled = Completer<void>();
    _pending.add(settled.future);
    final observed = operation.whenComplete(() {
      _pending.remove(settled.future);
      settled.complete();
    });
    try {
      return await observed.timeout(deadline);
    } on TimeoutException {
      if (onTimeout != null) {
        try {
          await onTimeout().timeout(settleDeadline);
        } catch (error) {
          cancellationErrors.add('$error');
        }
      }
      await settle();
      throw TimeoutException(
        '$label exceeded its deadline; pending work: $pendingCount',
        deadline,
      );
    }
  }

  Future<void> settle() async {
    if (_pending.isEmpty) return;
    try {
      await Future.wait(_pending.toList()).timeout(settleDeadline);
    } on TimeoutException {
      // Completion remains observed. The caller retains active work on disk.
    }
  }
}
