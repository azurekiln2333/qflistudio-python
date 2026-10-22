import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'python_module_catalog.dart';

export 'python_module_catalog.dart';

typedef PythonPackageSyntaxCheck =
    Future<String?> Function(String source, String absoluteFilePath);

class PythonInstalledPackage {
  PythonInstalledPackage({
    required this.name,
    required this.version,
    required this.source,
    required this.installedAt,
    required Map<String, String> files,
  }) : files = Map.unmodifiable(files);

  final String name;
  final String version;
  final String source;
  final DateTime installedAt;

  /// Project-relative paths and the digest of the installed bytes.
  final Map<String, String> files;

  Map<String, Object> _toJson() => {
    'name': name,
    'version': version,
    'source': source,
    'installedAt': installedAt.toUtc().toIso8601String(),
    'files': files,
  };
}

class PythonPackageCheckResult {
  const PythonPackageCheckResult({
    required this.compatible,
    required this.message,
    this.name = '',
    this.version = '',
    this.files = const [],
    this.issues = const [],
  });

  bool get success => compatible;
  final bool compatible;
  final String message;
  final String name;
  final String version;
  final List<String> files;
  final List<String> issues;
}

class PythonPackageOperationResult {
  const PythonPackageOperationResult({
    required this.success,
    required this.message,
    this.package,
    this.issues = const [],
    this.preservedFiles = const [],
  });

  final bool success;
  final String message;
  final PythonInstalledPackage? package;
  final List<String> issues;
  final List<String> preservedFiles;
}

class PythonBundlePreparationResult {
  const PythonBundlePreparationResult({
    required this.success,
    required this.message,
    this.directory = '',
    this.modules = const [],
    this.issues = const [],
  });

  final bool success;
  final String message;
  final String directory;
  final List<PythonModuleInfo> modules;
  final List<String> issues;
}

/// Offline source installation for the embedded VM. This is not pip: no
/// downloads, environment creation, build hooks or native extensions run here.
/// Source must compile in the app's actual VM via [syntaxCheck]. Static import
/// checking cannot promise that arbitrary CPython APIs work at runtime.
class PythonPackageService {
  PythonPackageService({AssetBundle? assets, this.syntaxCheck})
    : assets = assets ?? rootBundle;

  final AssetBundle assets;
  final PythonPackageSyntaxCheck? syntaxCheck;

  static const _assetRoot = 'assets/python_stdlib/';
  static const _packageManifest = '.qfli/python/packages.json';
  static const _bundleManifest = '.qfli/python/bundled/installed.json';
  static const _maxFiles = 4096;
  static const _maxFileBytes = 2 * 1024 * 1024;
  static const _maxTotalBytes = 16 * 1024 * 1024;
  static final Map<String, Future<void>> _projectLocks = {};
  static final _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
  static final _digest = RegExp(r'^[a-f0-9]{64}$');

  Future<List<PythonModuleInfo>> get moduleCatalog async => List.unmodifiable([
    ...pythonBuiltInModules,
    ...(await _loadBundle()).modules,
  ]);

  Future<PythonBundlePreparationResult> ensureBundledModules(
    String projectPath,
  ) async {
    try {
      return await _locked(projectPath, (root) async {
        final bundle = await _loadBundle();
        final previous = _readBundleOwnership(root);
        final files = <String, Uint8List>{};
        for (final entry in bundle.files.entries) {
          final data = await assets.load('$_assetRoot${entry.key}');
          final bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          if (_hash(bytes) != entry.value) {
            throw FormatException('内置模块校验失败：${entry.key}');
          }
          files['.qfli/python/bundled/${bundle.version}/${entry.key}'] = bytes;
        }
        _verifyOwnedTargets(root, files.keys, previous);
        final next = files.map((key, value) => MapEntry(key, _hash(value)));
        final obsolete = previous.keys.toSet().difference(files.keys.toSet());
        _verifyOwnedTargets(root, obsolete, previous);
        final alreadyPrepared =
            previous.length == next.length &&
            next.entries.every(
              (entry) =>
                  previous[entry.key] == entry.value &&
                  File(_safe(root, entry.key)).existsSync(),
            );
        if (!alreadyPrepared) {
          _commit(root, {
            for (final entry in files.entries)
              if (previous[entry.key] != next[entry.key] ||
                  !File(_safe(root, entry.key)).existsSync())
                entry.key: entry.value,
            _bundleManifest: _jsonBytes({
              'formatVersion': 1,
              'bundleVersion': bundle.version,
              'files': next,
            }),
          }, obsolete);
        }
        return PythonBundlePreparationResult(
          success: true,
          message: '已准备 ${bundle.modules.length} 个离线模块。',
          directory: p.join(root, '.qfli', 'python', 'bundled', bundle.version),
          modules: bundle.modules,
        );
      });
    } catch (error) {
      return PythonBundlePreparationResult(
        success: false,
        message: '无法准备离线模块：$error',
        issues: ['$error'],
      );
    }
  }

  Future<List<PythonInstalledPackage>> listInstalled({
    required String projectPath,
  }) => _locked(
    projectPath,
    (root) async => List.unmodifiable(_readPackages(root)),
  );

  Future<PythonInstalledPackage?> show({
    required String projectPath,
    required String name,
  }) async {
    final normalized = _name(name);
    for (final item in await listInstalled(projectPath: projectPath)) {
      if (item.name == normalized) return item;
    }
    return null;
  }

  Future<PythonPackageCheckResult> check({
    required String projectPath,
    required String sourcePath,
    String? name,
    String? version,
    bool Function()? isCancelled,
  }) async {
    try {
      return await _locked(projectPath, (root) async {
        final candidate = await _inspect(
          root,
          sourcePath,
          name,
          version,
          isCancelled,
        );
        return candidate.result;
      });
    } catch (error) {
      return PythonPackageCheckResult(
        compatible: false,
        message: '无法检查本地包：$error',
        issues: ['$error'],
      );
    }
  }

  Future<PythonPackageOperationResult> install({
    required String projectPath,
    required String sourcePath,
    String? name,
    String? version,
    bool Function()? isCancelled,
  }) async {
    try {
      return await _locked(projectPath, (root) async {
        final candidate = await _inspect(
          root,
          sourcePath,
          name,
          version,
          isCancelled,
        );
        if (!candidate.result.compatible) {
          return PythonPackageOperationResult(
            success: false,
            message: candidate.result.message,
            issues: candidate.result.issues,
          );
        }
        _cancel(isCancelled);
        final packages = _readPackages(root);
        final previous = packages.where((item) => item.name == candidate.name);
        final owned = previous.isEmpty
            ? <String, String>{}
            : previous.single.files;
        _verifyPackageConflicts(packages, candidate.name, candidate.files.keys);
        _verifyOwnedTargets(root, candidate.files.keys, owned);
        final obsolete = owned.keys.toSet().difference(
          candidate.files.keys.toSet(),
        );
        _verifyOwnedTargets(root, obsolete, owned);
        final installed = PythonInstalledPackage(
          name: candidate.name,
          version: candidate.version,
          source: p.normalize(p.absolute(sourcePath)),
          installedAt: DateTime.now().toUtc(),
          files: candidate.files.map(
            (key, value) => MapEntry(key, _hash(value)),
          ),
        );
        final updated = [
          ...packages.where((item) => item.name != installed.name),
          installed,
        ]..sort((a, b) => a.name.compareTo(b.name));
        _commit(
          root,
          {...candidate.files, _packageManifest: _encodePackages(updated)},
          obsolete,
          isCancelled: isCancelled,
        );
        return PythonPackageOperationResult(
          success: true,
          message: '已安装 ${installed.name} ${installed.version}（仅当前项目）。',
          package: installed,
        );
      });
    } catch (error) {
      return PythonPackageOperationResult(
        success: false,
        message: '未安装本地包：$error',
        issues: ['$error'],
      );
    }
  }

  Future<PythonPackageOperationResult> remove({
    required String projectPath,
    required String name,
    bool Function()? isCancelled,
  }) async {
    try {
      return await _locked(projectPath, (root) async {
        final normalized = _name(name);
        final packages = _readPackages(root);
        final matches = packages.where((item) => item.name == normalized);
        if (matches.isEmpty) {
          return const PythonPackageOperationResult(
            success: false,
            message: '当前项目没有安装此包。',
          );
        }
        final item = matches.single;
        final preserved = <String>[];
        final deletions = <String>{};
        for (final entry in item.files.entries) {
          final path = _safe(root, entry.key);
          final type = FileSystemEntity.typeSync(path, followLinks: false);
          if (type == FileSystemEntityType.notFound) continue;
          if (type == FileSystemEntityType.file &&
              _hash(File(path).readAsBytesSync()) == entry.value) {
            deletions.add(entry.key);
          } else {
            preserved.add(entry.key);
          }
        }
        _commit(
          root,
          {
            _packageManifest: _encodePackages(
              packages.where((entry) => entry.name != normalized).toList(),
            ),
          },
          deletions,
          isCancelled: isCancelled,
        );
        return PythonPackageOperationResult(
          success: true,
          message: preserved.isEmpty
              ? '已移除 $normalized。'
              : '已移除 $normalized 的归属记录；保留 ${preserved.length} 个修改过的文件。',
          package: item,
          preservedFiles: List.unmodifiable(preserved),
        );
      });
    } catch (error) {
      return PythonPackageOperationResult(
        success: false,
        message: '未移除本地包：$error',
        issues: ['$error'],
      );
    }
  }

  Future<_Candidate> _inspect(
    String root,
    String sourcePath,
    String? name,
    String? version,
    bool Function()? isCancelled,
  ) async {
    _cancel(isCancelled);
    if (syntaxCheck == null) {
      throw StateError('当前运行组件没有提供真实的 Python 语法检查，不能安装。');
    }
    final candidate = _readCandidate(sourcePath, name, version);
    final packages = _readPackages(root);
    final bundle = await _loadBundle();
    final issues = <String>[];
    _verifyPackageConflicts(packages, candidate.name, candidate.files.keys);
    final old = packages.where((item) => item.name == candidate.name);
    _verifyOwnedTargets(
      root,
      candidate.files.keys,
      old.isEmpty ? const {} : old.single.files,
    );
    final localModules = <String>{
      ..._moduleRoots(candidate.files.keys.map((path) => path.substring(4))),
      // Previous files are replaced by the candidate, so modules removed by
      // this update must not satisfy the new source's imports.
      ..._projectModules(
        root,
        excluded: old.isEmpty ? const {} : old.single.files.keys.toSet(),
      ),
    };
    final available = <String>{
      ...pythonBuiltInModules.map((item) => item.name),
      ...bundle.modules.map((item) => item.name),
      ...localModules,
    };
    final versions = <String, String>{
      for (final item in pythonBuiltInModules) item.name: item.version,
      for (final item in bundle.modules) _name(item.name): item.version,
      for (final item in packages) item.name: item.version,
    };
    for (final dependency in candidate.requires) {
      _checkDependency(dependency, versions, issues);
    }
    for (final file in candidate.files.entries) {
      _cancel(isCancelled);
      if (!file.key.endsWith('.py')) continue;
      final source = utf8.decode(file.value);
      final error = await syntaxCheck!(source, _safe(root, file.key));
      _cancel(isCancelled);
      if (error != null) {
        issues.add(
          '${file.key}：${error.trim().isEmpty ? '原生语法检查未通过。' : error}',
        );
      }
      _checkImports(
        source,
        file.key,
        available,
        bundle.modules
            .where((module) => !localModules.contains(module.name))
            .toList(),
        issues,
      );
    }
    candidate.result = PythonPackageCheckResult(
      compatible: issues.isEmpty,
      message: issues.isEmpty
          ? '本地源码已通过当前 VM 语法和直接依赖检查；第三方 API 仍需实际运行验证。'
          : '本地包不兼容：${issues.join('\n')}',
      name: candidate.name,
      version: candidate.version,
      files: List.unmodifiable(candidate.files.keys),
      issues: List.unmodifiable(issues),
    );
    return candidate;
  }

  _Candidate _readCandidate(String sourcePath, String? name, String? version) {
    if (sourcePath.trim().isEmpty) throw const FormatException('请选择明确的本地包路径。');
    final absolute = p.normalize(p.absolute(sourcePath));
    _noSourceLinks(absolute);
    final type = FileSystemEntity.typeSync(absolute, followLinks: false);
    final entries = <String, Uint8List>{};
    var inferredName = p.basenameWithoutExtension(absolute);
    var inferredVersion = 'local';
    final requires = <String>[];
    var wheel = false;
    if (type == FileSystemEntityType.directory) {
      inferredName = p.basename(absolute);
      final isPackage = File(p.join(absolute, '__init__.py')).existsSync();
      if (isPackage && !_identifier.hasMatch(inferredName)) {
        throw const FormatException('包目录名必须是有效的 Python 标识符。');
      }
      for (final entity in Directory(
        absolute,
      ).listSync(recursive: true, followLinks: false)) {
        final entityType = FileSystemEntity.typeSync(
          entity.path,
          followLinks: false,
        );
        if (entityType == FileSystemEntityType.link) {
          throw FormatException('本地包不能包含链接：${entity.path}');
        }
        if (entityType == FileSystemEntityType.directory) continue;
        if (entityType != FileSystemEntityType.file) {
          throw FormatException('不支持的文件类型：${entity.path}');
        }
        final relative = p
            .relative(entity.path, from: absolute)
            .replaceAll('\\', '/');
        final target = isPackage ? '$inferredName/$relative' : relative;
        final file = File(entity.path);
        if (file.lengthSync() > _maxFileBytes) {
          throw FormatException('包文件超过 2 MiB 限制：${entity.path}');
        }
        _addSource(entries, target, file.readAsBytesSync());
      }
    } else if (type == FileSystemEntityType.file) {
      final extension = p.extension(absolute).toLowerCase();
      if (File(absolute).lengthSync() > _maxTotalBytes) {
        throw const FormatException('本地包超过 16 MiB 限制。');
      }
      if (extension == '.py') {
        if (!_identifier.hasMatch(p.basenameWithoutExtension(absolute))) {
          throw const FormatException('模块文件名必须是有效的 Python 标识符。');
        }
        _addSource(
          entries,
          p.basename(absolute),
          File(absolute).readAsBytesSync(),
        );
      } else if (extension == '.zip' || extension == '.whl') {
        wheel = extension == '.whl';
        final archiveBytes = File(absolute).readAsBytesSync();
        final directory = ZipDirectory()..read(InputMemoryStream(archiveBytes));
        if (directory.numberOfThisDisk != 0 ||
            directory.diskWithTheStartOfTheCentralDirectory != 0 ||
            directory.totalCentralDirectoryEntries !=
                directory.fileHeaders.length ||
            directory.totalCentralDirectoryEntriesOnThisDisk !=
                directory.fileHeaders.length) {
          throw const FormatException('不支持分卷或目录不完整的 ZIP 归档。');
        }
        final seen = <String>{};
        var total = 0;
        for (final header in directory.fileHeaders) {
          final path = _relative(
            header.filename,
            directory: header.filename.endsWith('/'),
          );
          if (!seen.add(path.toLowerCase())) {
            throw FormatException('归档包含重复路径：$path');
          }
          if ((header.generalPurposeBitFlag & 1) != 0 ||
              !{0, 8}.contains(header.compressionMethod) ||
              header.file?.filename != header.filename ||
              (header.file!.flags & 1) != 0) {
            throw FormatException('不支持加密或此压缩格式：$path');
          }
          final type = (header.externalFileAttributes >> 16) & 0xf000;
          if (!{0, 0x8000, 0x4000}.contains(type)) {
            throw FormatException('归档不能包含链接或特殊文件：$path');
          }
          total += header.uncompressedSize;
          if (header.uncompressedSize > _maxFileBytes ||
              total > _maxTotalBytes ||
              seen.length > _maxFiles) {
            throw const FormatException('归档展开后的大小或文件数量超过限制。');
          }
        }
        final archive = ZipDecoder().decodeBytes(archiveBytes);
        for (final file in archive.files) {
          if (file.isSymbolicLink ||
              (file.mode & 0xf000) == 0xa000 ||
              !{0, 0x8000, 0x4000}.contains(file.mode & 0xf000)) {
            throw FormatException('归档不能包含链接或特殊文件：${file.name}');
          }
          if (file.isDirectory) continue;
          final bytes = _readArchiveSource(file);
          if (bytes.length != file.size || getCrc32(bytes) != file.crc32) {
            throw FormatException('归档内容校验失败：${file.name}');
          }
          _addSource(entries, file.name, bytes, metadata: wheel);
        }
        if (wheel) {
          final metadata = _wheelMetadata(p.basename(absolute), entries);
          inferredName = metadata.name;
          inferredVersion = metadata.version;
          requires.addAll(metadata.requires);
          entries.removeWhere(
            (key, _) => key.split('/').first.endsWith('.dist-info'),
          );
        }
      } else {
        throw const FormatException('只支持本地 .py、包目录、.zip 和纯 Python .whl。');
      }
    } else {
      throw const FormatException('本地包不存在或不是普通文件/目录。');
    }
    final metadataKeys = entries.keys
        .where(
          (key) =>
              key == 'qfli-package.json' ||
              key == '$inferredName/qfli-package.json',
        )
        .toList();
    if (metadataKeys.length > 1) throw const FormatException('本地包元数据重复。');
    if (metadataKeys.isNotEmpty) {
      if (wheel) throw const FormatException('wheel 不能同时包含 qfli-package.json。');
      final metadata = _object(
        jsonDecode(utf8.decode(entries.remove(metadataKeys.single)!)),
      );
      if (metadata['name'] != null) {
        inferredName = _string(metadata['name'], 'name');
      }
      if (metadata['version'] != null) {
        inferredVersion = _string(metadata['version'], 'version');
      }
      if (metadata['requires'] != null) {
        requires.addAll(_strings(metadata['requires'], 'requires'));
      }
    }
    if (entries.isEmpty || !entries.keys.any((key) => key.endsWith('.py'))) {
      throw const FormatException('本地包没有 Python 源码。');
    }
    final roots = _moduleRoots(entries.keys);
    if (roots.isEmpty) {
      throw const FormatException('本地包需要顶层 .py 模块或含 __init__.py 的包。');
    }
    return _Candidate(
      _name(name ?? inferredName),
      _version(version ?? inferredVersion),
      entries.map((key, value) => MapEntry('lib/$key', value)),
      requires,
    );
  }

  static Uint8List _readArchiveSource(ArchiveFile file) {
    // readBytes() inflates everything before checking the declared size. Feed
    // native zlib into a bounded sink so forged metadata cannot expand without
    // the per-file limit during decompression.
    final output = _ArchiveSourceSink(file.name, file.size);
    final input = file.rawContent?.getStream(decompress: false);
    if (input == null) return Uint8List(0);
    if (file.compression == CompressionType.deflate) {
      final decoder = ZLibCodec(
        raw: true,
      ).decoder.startChunkedConversion(output);
      while (!input.isEOS) {
        final size = input.length < 1024 ? input.length : 1024;
        decoder.add(input.readBytes(size).toUint8List());
      }
      decoder.close();
    } else {
      output.add(input.toUint8List());
    }
    return output.bytes.takeBytes();
  }

  static void _addSource(
    Map<String, Uint8List> entries,
    String path,
    List<int> bytes, {
    bool metadata = false,
  }) {
    path = _relative(path);
    if (entries.keys.any((key) => key.toLowerCase() == path.toLowerCase())) {
      throw FormatException('重复的包路径：$path');
    }
    final parts = path.split('/');
    if (parts.any((part) => part.startsWith('.') || part == '__pycache__') ||
        parts.any((part) => part.endsWith('.data'))) {
      throw FormatException('不支持的包路径：$path');
    }
    if (parts.last == 'setup.py') {
      throw const FormatException('不安装含 setup.py 的构建源码；请选择已整理的纯 Python 包。');
    }
    const textExtensions = {
      '.py',
      '.txt',
      '.md',
      '.rst',
      '.json',
      '.csv',
      '.toml',
      '.ini',
      '.cfg',
      '.yaml',
      '.yml',
    };
    final base = parts.last;
    final isMetadata = metadata && parts.first.endsWith('.dist-info');
    if (!textExtensions.contains(p.posix.extension(path).toLowerCase()) &&
        !{'LICENSE', 'COPYING', 'NOTICE'}.contains(base.toUpperCase()) &&
        !(isMetadata &&
            {
              'WHEEL',
              'METADATA',
              'RECORD',
              'INSTALLER',
              'REQUESTED',
              'entry_points.txt',
              'top_level.txt',
            }.contains(base))) {
      throw FormatException('不支持二进制、字节码或此数据文件：$path');
    }
    if (bytes.length > _maxFileBytes ||
        entries.length >= _maxFiles ||
        entries.values.fold<int>(
              bytes.length,
              (sum, value) => sum + value.length,
            ) >
            _maxTotalBytes) {
      throw const FormatException('本地包超过文件大小或数量限制。');
    }
    final text = utf8.decode(bytes);
    if (text.contains('\u0000')) throw FormatException('不支持含 NUL 的文件：$path');
    entries[path] = Uint8List.fromList(bytes);
  }

  static _WheelMetadata _wheelMetadata(
    String filename,
    Map<String, Uint8List> entries,
  ) {
    final parts = filename.substring(0, filename.length - 4).split('-');
    if ((parts.length != 5 && parts.length != 6) ||
        parts[parts.length - 2] != 'none' ||
        parts.last != 'any' ||
        !parts[parts.length - 3].split('.').contains('py3') ||
        !parts[parts.length - 3]
            .split('.')
            .every((tag) => tag == 'py3' || tag == 'py2')) {
      throw const FormatException(
        '只支持 py3-none-any（或 py2.py3-none-any）纯 Python wheel。',
      );
    }
    final metadataPaths = entries.keys
        .where((key) => key.endsWith('.dist-info/METADATA'))
        .toList();
    if (metadataPaths.length != 1) {
      throw const FormatException('wheel 缺少唯一的 METADATA。');
    }
    final prefix = metadataPaths.single.split('/').first;
    if (entries.keys.any(
      (key) => key.contains('.dist-info/') && key.split('/').first != prefix,
    )) {
      throw const FormatException('wheel 包含多个 dist-info 目录。');
    }
    final wheelBytes = entries['$prefix/WHEEL'];
    if (wheelBytes == null) throw const FormatException('wheel 缺少 WHEEL 元数据。');
    final wheel = _headers(utf8.decode(wheelBytes));
    if (wheel['Root-Is-Purelib']?.single.toLowerCase() != 'true' ||
        wheel['Wheel-Version']?.single != '1.0' ||
        wheel['Tag'] == null ||
        !wheel['Tag']!.every(
          (tag) => tag == 'py3-none-any' || tag == 'py2-none-any',
        ) ||
        !wheel['Tag']!.contains('py3-none-any')) {
      throw const FormatException('wheel 的版本、Purelib 或 Tag 不受支持。');
    }
    final metadata = _headers(utf8.decode(entries[metadataPaths.single]!));
    final name = _name(metadata['Name']?.single ?? '');
    final version = _version(metadata['Version']?.single ?? '');
    if (_name(parts.first) != name ||
        parts[1] != version ||
        prefix != '${parts[0]}-${parts[1]}.dist-info') {
      throw const FormatException('wheel 文件名与包元数据不一致。');
    }
    final python = metadata['Requires-Python']?.single;
    if (python != null &&
        !{
          '',
          '>=3',
          '>=3.0',
          '>=3.0.0',
          '<4',
          '>=3,<4',
          '>=3.0,<4',
        }.contains(python.replaceAll(' ', ''))) {
      throw FormatException('当前 VM 不能保证 CPython 版本约束：$python');
    }
    if (entries.containsKey('$prefix/entry_points.txt')) {
      throw const FormatException('不支持 wheel 的命令入口或安装脚本。');
    }
    return _WheelMetadata(name, version, metadata['Requires-Dist'] ?? const []);
  }

  static Map<String, List<String>> _headers(String text) {
    final values = <String, List<String>>{};
    for (final line in const LineSplitter().convert(text)) {
      if (line.isEmpty) break;
      if (line.startsWith(' ') || line.startsWith('\t')) {
        throw const FormatException('不支持折行的包元数据。');
      }
      final colon = line.indexOf(':');
      if (colon <= 0) throw const FormatException('包元数据格式错误。');
      values
          .putIfAbsent(line.substring(0, colon), () => [])
          .add(line.substring(colon + 1).trim());
    }
    return values;
  }

  static void _checkDependency(
    String dependency,
    Map<String, String> versions,
    List<String> issues,
  ) {
    final match = RegExp(
      r'^([A-Za-z0-9][A-Za-z0-9_.-]*)(?:\s*\(?\s*((?:[=!<>][^;\[\]]+))\)?)?$',
    ).firstMatch(dependency.trim());
    if (match == null ||
        dependency.contains(';') ||
        dependency.contains('[') ||
        dependency.contains('@')) {
      issues.add('不支持依赖条件/额外功能：$dependency');
      return;
    }
    final name = _name(match[1]!);
    final version = versions[name];
    if (version == null) {
      issues.add('缺少本地依赖：$dependency（不会联网下载）。');
      return;
    }
    final constraints = match[2]?.replaceAll(')', '').trim();
    if (constraints == null || constraints.isEmpty) return;
    for (final constraint in constraints.split(',')) {
      final comparison = RegExp(
        r'^(==|!=|>=|<=|>|<)\s*(\d+(?:\.\d+)*)$',
      ).firstMatch(constraint.trim());
      if (comparison == null || !RegExp(r'^\d+(?:\.\d+)*$').hasMatch(version)) {
        issues.add('无法验证本地依赖版本：$dependency');
        return;
      }
      final order = _compareVersions(version, comparison[2]!);
      final matches = switch (comparison[1]) {
        '==' => order == 0,
        '!=' => order != 0,
        '>=' => order >= 0,
        '<=' => order <= 0,
        '>' => order > 0,
        '<' => order < 0,
        _ => false,
      };
      if (!matches) {
        issues.add('本地依赖版本不满足 $dependency（已安装 $version）。');
        return;
      }
    }
  }

  static int _compareVersions(String a, String b) {
    final left = a.split('.').map(int.parse).toList();
    final right = b.split('.').map(int.parse).toList();
    for (var index = 0; index < left.length || index < right.length; index++) {
      final order = (index < left.length ? left[index] : 0).compareTo(
        index < right.length ? right[index] : 0,
      );
      if (order != 0) return order;
    }
    return 0;
  }

  static void _checkImports(
    String source,
    String path,
    Set<String> available,
    List<PythonModuleInfo> modules,
    List<String> issues,
  ) {
    // Deliberately conservative: direct imports only. This is an additional
    // compatibility check, never a replacement for the VM compiler or execution.
    final statements = _importText(source).replaceAll(';', '\n');
    for (final line in const LineSplitter().convert(statements)) {
      final import = RegExp(r'^\s*import\s+([^#;]+)').firstMatch(line);
      final from = RegExp(
        r'^\s*from\s+([A-Za-z_][\w.]*)\s+import\s+([^#;]+)',
      ).firstMatch(line);
      final names = import != null
          ? import[1]!
                .split(',')
                .map((part) => part.trim().split(RegExp(r'\s+')).first)
          : from != null
          ? [from[1]!]
          : const <String>[];
      for (final name in names) {
        final root = name.split('.').first;
        if (!available.contains(root)) issues.add('$path：缺少导入模块 $root。');
      }
      if (from == null) continue;
      final matches = modules.where((module) => module.name == from[1]);
      if (matches.isEmpty || matches.single.apis.isEmpty) continue;
      for (final name in from[2]!.split(',')) {
        final symbol = name.trim().split(RegExp(r'\s+')).first;
        if (_identifier.hasMatch(symbol) &&
            !matches.single.apis.contains(symbol)) {
          issues.add('$path：${from[1]} 未提供已验证的 API $symbol。');
        }
      }
    }
  }

  /// Remove comments and literal contents while retaining line boundaries.
  /// This avoids treating documentation and example strings as dependencies.
  static String _importText(String source) {
    final out = StringBuffer();
    String? quote;
    var triple = false;
    var comment = false;
    for (var index = 0; index < source.length; index++) {
      final char = source[index];
      if (char == '\n') {
        out.write('\n');
        comment = false;
        continue;
      }
      if (comment) {
        out.write(' ');
        continue;
      }
      if (quote != null) {
        if (char == '\\' && index + 1 < source.length) {
          out.write(source[index + 1] == '\n' ? ' \n' : '  ');
          index++;
        } else if (char == quote &&
            (!triple || source.startsWith(quote * 3, index))) {
          out.write(triple ? '   ' : ' ');
          if (triple) index += 2;
          quote = null;
        } else {
          out.write(' ');
        }
      } else if (char == '#') {
        comment = true;
        out.write(' ');
      } else if (char == '"' || char == "'") {
        quote = char;
        triple = source.startsWith(char * 3, index);
        out.write(triple ? '   ' : ' ');
        if (triple) index += 2;
      } else {
        out.write(char);
      }
    }
    return out.toString().replaceAll('\\\n', ' ');
  }

  static Set<String> _moduleRoots(Iterable<String> files) {
    final roots = <String>{};
    for (final path in files) {
      final parts = path.split('/');
      if (parts.length == 1 && path.endsWith('.py')) {
        final name = path.substring(0, path.length - 3);
        if (_identifier.hasMatch(name) && name != '__init__') roots.add(name);
      } else if (parts.length == 2 &&
          parts.last == '__init__.py' &&
          _identifier.hasMatch(parts.first)) {
        roots.add(parts.first);
      }
    }
    return roots;
  }

  static Set<String> _projectModules(
    String root, {
    Set<String> excluded = const {},
  }) {
    final files = <String>[];
    for (final directory in ['', 'lib']) {
      final path = directory.isEmpty ? root : _safe(root, directory);
      if (FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.directory) {
        continue;
      }
      for (final entity in Directory(path).listSync(followLinks: false)) {
        final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
        final name = p.basename(entity.path);
        final relative = directory.isEmpty ? name : '$directory/$name';
        if (type == FileSystemEntityType.file && !excluded.contains(relative)) {
          files.add(name);
        }
        if (type == FileSystemEntityType.directory) {
          final init = p.join(entity.path, '__init__.py');
          if (!excluded.contains('$relative/__init__.py') &&
              FileSystemEntity.typeSync(init, followLinks: false) ==
                  FileSystemEntityType.file) {
            files.add('$name/__init__.py');
          }
        }
      }
    }
    return _moduleRoots(files);
  }

  Future<_Bundle> _loadBundle() async {
    final data = _object(
      jsonDecode(await assets.loadString('${_assetRoot}manifest.json')),
    );
    if (data['formatVersion'] != 1) {
      throw const FormatException('不支持的内置模块清单版本。');
    }
    final version = _relative(_string(data['bundleVersion'], 'bundleVersion'));
    if (version.contains('/')) throw const FormatException('内置模块版本必须是单一目录名。');
    final files = _fileList(data['files']);
    final modules = <PythonModuleInfo>[];
    if (data['modules'] is! List) {
      throw const FormatException('内置模块缺少 modules。');
    }
    final seen = <String>{};
    for (final entry in data['modules'] as List) {
      final module = _object(entry);
      final name = _string(module['name'], 'name');
      if (!_identifier.hasMatch(name) || !seen.add(name)) {
        throw const FormatException('内置模块名无效或重复。');
      }
      final moduleFiles = _fileList(module['files']);
      if (moduleFiles.isEmpty ||
          !moduleFiles.entries.every((file) => files[file.key] == file.value)) {
        throw FormatException('内置模块文件清单不一致：$name');
      }
      modules.add(
        PythonModuleInfo(
          name: name,
          version: _string(module['version'], 'version'),
          summary: _string(module['summary'], 'summary'),
          origin: PythonModuleOrigin.bundled,
          apis: List.unmodifiable(_strings(module['apis'], 'apis')),
          license: _string(module['license'], 'license'),
          source: _string(module['source'], 'source'),
        ),
      );
    }
    return _Bundle(version, files, List.unmodifiable(modules));
  }

  static Map<String, String> _fileList(Object? value) {
    if (value is! List) throw const FormatException('缺少 files 清单。');
    final files = <String, String>{};
    for (final file in value) {
      final entry = _object(file);
      final path = _relative(_string(entry['path'], 'path'));
      final hash = _string(entry['sha256'], 'sha256');
      if (!_digest.hasMatch(hash) ||
          files.keys.any((key) => key.toLowerCase() == path.toLowerCase())) {
        throw FormatException('文件路径重复或摘要无效：$path');
      }
      files[path] = hash;
    }
    return files;
  }

  static List<PythonInstalledPackage> _readPackages(String root) {
    final path = _safe(root, _packageManifest);
    if (FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return [];
    }
    final data = _object(jsonDecode(File(path).readAsStringSync()));
    if (data['formatVersion'] != 1 || data['packages'] is! List) {
      throw const FormatException('本地包清单损坏或版本不受支持。');
    }
    final packages = <PythonInstalledPackage>[];
    final names = <String>{};
    final owned = <String>{};
    for (final item in data['packages'] as List) {
      final entry = _object(item);
      final name = _name(_string(entry['name'], 'name'));
      if (!names.add(name)) throw const FormatException('本地包清单重复。');
      final files = _ownedFiles(entry['files'], prefix: 'lib/');
      for (final file in files.keys) {
        if (!owned.add(file.toLowerCase())) {
          throw const FormatException('本地包文件归属重复。');
        }
      }
      packages.add(
        PythonInstalledPackage(
          name: name,
          version: _version(_string(entry['version'], 'version')),
          source: _string(entry['source'], 'source'),
          installedAt: DateTime.parse(
            _string(entry['installedAt'], 'installedAt'),
          ),
          files: files,
        ),
      );
    }
    return packages;
  }

  static Map<String, String> _readBundleOwnership(String root) {
    final path = _safe(root, _bundleManifest);
    if (FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return {};
    }
    final data = _object(jsonDecode(File(path).readAsStringSync()));
    if (data['formatVersion'] != 1) throw const FormatException('内置模块归属清单损坏。');
    return _ownedFiles(
      data['files'],
      prefix: '.qfli/python/bundled/',
      excluded: {_bundleManifest},
    );
  }

  static Map<String, String> _ownedFiles(
    Object? value, {
    required String prefix,
    Set<String> excluded = const {},
  }) {
    final data = _object(value);
    final files = <String, String>{};
    for (final entry in data.entries) {
      final path = _relative(entry.key);
      if (!path.startsWith(prefix) ||
          excluded.contains(path) ||
          entry.value is! String ||
          !_digest.hasMatch(entry.value as String) ||
          files.keys.any((key) => key.toLowerCase() == path.toLowerCase())) {
        throw const FormatException('文件归属清单含无效路径或摘要。');
      }
      files[path] = entry.value as String;
    }
    return files;
  }

  static Uint8List _encodePackages(List<PythonInstalledPackage> packages) =>
      _jsonBytes({
        'formatVersion': 1,
        'packages': packages.map((item) => item._toJson()).toList(),
      });

  static void _verifyPackageConflicts(
    List<PythonInstalledPackage> packages,
    String name,
    Iterable<String> files,
  ) {
    final targets = files.map((path) => path.toLowerCase()).toSet();
    for (final item in packages) {
      if (item.name == name) continue;
      for (final file in item.files.keys) {
        if (targets.contains(file.toLowerCase())) {
          throw FileSystemException('目标文件属于 ${item.name}', file);
        }
      }
    }
  }

  static void _verifyOwnedTargets(
    String root,
    Iterable<String> targets,
    Map<String, String> owned,
  ) {
    for (final relative in targets) {
      final path = _safe(root, relative);
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) continue;
      if (type != FileSystemEntityType.file || owned[relative] == null) {
        throw FileSystemException('保留未归属的文件或目录，不能覆盖', path);
      }
      if (_hash(File(path).readAsBytesSync()) != owned[relative]) {
        throw FileSystemException('保留用户修改过的文件，不能更新', path);
      }
    }
  }

  /// All files are staged first, then existing bytes are backed up by rename.
  /// No asynchronous gaps occur during commit/rollback. The manifest moves last.
  static void _commit(
    String root,
    Map<String, Uint8List> writes,
    Set<String> deletions, {
    bool Function()? isCancelled,
  }) {
    _cancel(isCancelled);
    final created = <String>[];
    String? staging;
    final backups = <String, String>{};
    final published = <String>[];
    var retainBackups = false;
    try {
      final state = _safe(root, '.qfli/python');
      _mkdir(root, state, created);
      staging = Directory(state).createTempSync('.package-transaction-').path;
      final staged = <String, String>{};
      var sequence = 0;
      for (final entry in writes.entries) {
        final path = p.join(staging, 'new-${sequence++}');
        File(path).writeAsBytesSync(entry.value, flush: true);
        staged[entry.key] = path;
      }
      _cancel(isCancelled);
      final targets = {...deletions, ...writes.keys};
      for (final relative in targets) {
        final path = _safe(root, relative);
        _mkdir(root, p.dirname(path), created);
        final type = FileSystemEntity.typeSync(path, followLinks: false);
        if (type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.file) {
          throw FileSystemException('事务目标不是普通文件', path);
        }
      }
      for (final relative in targets) {
        _cancel(isCancelled);
        final path = _safe(root, relative);
        if (File(path).existsSync()) {
          final backup = p.join(staging, 'old-${sequence++}');
          File(path).renameSync(backup);
          backups[relative] = backup;
        }
        if (staged.containsKey(relative)) {
          File(staged[relative]!).renameSync(path);
          published.add(relative);
        }
      }
      _cancel(isCancelled);
    } catch (original) {
      final failures = <String>[];
      for (final relative in published.reversed) {
        try {
          final path = _safe(root, relative);
          if (File(path).existsSync()) File(path).deleteSync();
        } catch (error) {
          failures.add('$relative: $error');
        }
      }
      for (final entry in backups.entries) {
        try {
          File(entry.value).renameSync(_safe(root, entry.key));
        } catch (error) {
          failures.add('${entry.key}: $error');
        }
      }
      if (failures.isNotEmpty) {
        // Keep recoverable original bytes if a filesystem failure also prevents
        // rollback. Never delete the only remaining copy in a finally block.
        retainBackups = true;
        throw FileSystemException(
          '事务失败（$original），部分回滚失败；原始备份保留于 $staging：${failures.join('; ')}',
          staging,
        );
      }
      rethrow;
    } finally {
      if (!retainBackups &&
          staging != null &&
          Directory(staging).existsSync()) {
        Directory(staging).deleteSync(recursive: true);
      }
      for (final path in created.reversed) {
        if (Directory(path).existsSync() &&
            Directory(path).listSync(followLinks: false).isEmpty) {
          Directory(path).deleteSync();
        }
      }
    }
  }

  static void _mkdir(String root, String directory, List<String> created) {
    if (p.equals(directory, root)) return;
    final relative = p.relative(directory, from: root).replaceAll('\\', '/');
    var current = root;
    for (final segment in _relative(relative).split('/')) {
      current = p.join(current, segment);
      final type = FileSystemEntity.typeSync(current, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        Directory(current).createSync();
        created.add(current);
      } else if (type != FileSystemEntityType.directory) {
        throw FileSystemException('父路径不是普通目录', current);
      }
    }
  }

  static Future<T> _locked<T>(
    String projectPath,
    Future<T> Function(String root) action,
  ) async {
    if (projectPath.trim().isEmpty || !p.isAbsolute(projectPath)) {
      throw const FormatException('项目路径必须是明确的绝对路径。');
    }
    final requested = p.normalize(p.absolute(projectPath));
    if (!Directory(requested).existsSync()) {
      throw FileSystemException('项目目录不存在', projectPath);
    }
    final root = Directory(requested).resolveSymbolicLinksSync();
    final key = Platform.isWindows ? root.toLowerCase() : root;
    final previous = _projectLocks[key] ?? Future<void>.value();
    final finished = Completer<void>();
    _projectLocks[key] = finished.future;
    await previous;
    try {
      if (Directory(requested).resolveSymbolicLinksSync() != root) {
        throw FileSystemException('项目目录在等待时改变', requested);
      }
      return await action(root);
    } finally {
      finished.complete();
      if (identical(_projectLocks[key], finished.future)) {
        _projectLocks.remove(key);
      }
    }
  }

  static String _safe(String root, String relative) {
    final parts = _relative(relative).split('/');
    var current = root;
    for (var index = 0; index < parts.length; index++) {
      current = p.join(current, parts[index]);
      final type = FileSystemEntity.typeSync(current, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw FileSystemException('项目路径不能经过链接', current);
      }
      if (index < parts.length - 1 &&
          type != FileSystemEntityType.directory &&
          type != FileSystemEntityType.notFound) {
        throw FileSystemException('项目父路径不是目录', current);
      }
    }
    if (!p.isWithin(root, current)) {
      throw FileSystemException('路径超出项目', current);
    }
    return current;
  }

  static void _noSourceLinks(String absolute) {
    var current = absolute;
    while (true) {
      if (FileSystemEntity.typeSync(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw FileSystemException('本地包路径不能经过链接', current);
      }
      final parent = p.dirname(current);
      if (parent == current) break;
      current = parent;
    }
  }

  static String _relative(String path, {bool directory = false}) {
    if (directory && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final parts = path.split('/');
    if (path.isEmpty ||
        path.contains('\\') ||
        path.contains(RegExp(r'[<>:"|?*]')) ||
        path.contains(RegExp(r'[\x00-\x1f]')) ||
        path.startsWith('/') ||
        parts.any(
          (part) =>
              part.isEmpty ||
              part == '.' ||
              part == '..' ||
              part.endsWith('.') ||
              part.endsWith(' ') ||
              RegExp(
                r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
                caseSensitive: false,
              ).hasMatch(part),
        )) {
      throw FormatException('不安全的相对路径：$path');
    }
    return path;
  }

  static String _name(String value) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$').hasMatch(value)) {
      throw const FormatException('包名无效。');
    }
    return value.toLowerCase().replaceAll(RegExp(r'[-_.]+'), '-');
  }

  static String _version(String value) {
    if (value.isEmpty ||
        value.length > 128 ||
        value.contains(RegExp(r'[\x00-\x20/\\]'))) {
      throw const FormatException('包版本无效。');
    }
    return value;
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('清单必须是 JSON 对象。');
    }
    return value;
  }

  static String _string(Object? value, String field) {
    if (value is! String || value.isEmpty) {
      throw FormatException('清单字段 $field 无效。');
    }
    return value;
  }

  static List<String> _strings(Object? value, String field) {
    if (value is! List || value.any((item) => item is! String)) {
      throw FormatException('清单字段 $field 必须是字符串列表。');
    }
    return value.cast<String>();
  }

  static String _hash(List<int> bytes) => sha256.convert(bytes).toString();
  static Uint8List _jsonBytes(Object value) => Uint8List.fromList(
    utf8.encode('${const JsonEncoder.withIndent('  ').convert(value)}\n'),
  );
  static void _cancel(bool Function()? callback) {
    if (callback?.call() ?? false) throw const _Cancelled();
  }
}

class _ArchiveSourceSink implements Sink<List<int>> {
  _ArchiveSourceSink(this.name, this.limit);

  final String name;
  final int limit;
  final bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> data) {
    if (bytes.length + data.length > limit) {
      throw FormatException('归档展开内容超过声明大小：$name');
    }
    bytes.add(data);
  }

  @override
  void close() {}
}

class _Candidate {
  _Candidate(this.name, this.version, this.files, this.requires);
  final String name;
  final String version;
  final Map<String, Uint8List> files;
  final List<String> requires;
  late PythonPackageCheckResult result;
}

class _Bundle {
  const _Bundle(this.version, this.files, this.modules);
  final String version;
  final Map<String, String> files;
  final List<PythonModuleInfo> modules;
}

class _WheelMetadata {
  const _WheelMetadata(this.name, this.version, this.requires);
  final String name;
  final String version;
  final List<String> requires;
}

class _Cancelled implements Exception {
  const _Cancelled();
  @override
  String toString() => '操作已取消，已保留原有文件。';
}
