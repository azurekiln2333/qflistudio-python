import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/pages/tools_grid.dart';
import 'package:qfli_studio_core/services/picker_service.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/widgets/tool_widgets.dart';

import 'python_packages.dart';
import 'python_runner.dart';

Widget buildPythonToolsPage(ProjectStore store) =>
    PythonToolsPage(store: store);

Widget buildPythonToolsTab(ProjectStore store, VoidCallback onOpenTerminal) =>
    PythonToolsBody(store: store, onOpenTerminal: onOpenTerminal);

/// Compatibility entry for callers opening a separate tools route.
class PythonToolsPage extends StatelessWidget {
  const PythonToolsPage({
    super.key,
    required this.store,
    this.runner = const PythonProgramRunner(),
    this.packageService,
  });

  final ProjectStore store;
  final PythonProgramRunner runner;
  final PythonPackageService? packageService;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Python 工具')),
    body: PythonToolsBody(
      store: store,
      runner: runner,
      packageService: packageService,
    ),
  );
}

/// One scroll body shared by the root Tools tab and the legacy route.
class PythonToolsBody extends StatefulWidget {
  const PythonToolsBody({
    super.key,
    required this.store,
    this.runner = const PythonProgramRunner(),
    this.packageService,
    this.onOpenTerminal,
  });

  final ProjectStore store;
  final PythonProgramRunner runner;
  final PythonPackageService? packageService;
  final VoidCallback? onOpenTerminal;

  @override
  State<PythonToolsBody> createState() => _PythonToolsBodyState();
}

class _PythonToolsBodyState extends State<PythonToolsBody> {
  // ExpansionTile stores a bool. Keep it out of a shell's scroll-offset bucket;
  // editable text also owns scroll positions below each expanded section.
  final _pageStorage = PageStorageBucket();
  final _sourcePath = TextEditingController();
  final _packageName = TextEditingController();
  final _packageVersion = TextEditingController();
  final _pickedSources = <Directory>[];
  String? _projectId;
  String? _projectPath;
  String? _entryFile;
  List<String> _files = const [];
  String _output = '';
  String _stderr = '';
  String _status = '';
  bool _loadingFiles = false;
  bool _working = false;
  int _fileLoadGeneration = 0;
  int _operationGeneration = 0;
  Future<void> Function()? _cancelRun;
  bool _runtimeLoading = false;
  int _runtimeGeneration = 0;
  PythonRuntimeInfo? _runtime;
  List<PythonModuleInfo>? _modules;
  String _runtimeError = '';
  bool _packagesExpanded = false;
  bool _packagesLoading = false;
  int _packagesGeneration = 0;
  List<PythonInstalledPackage> _packages = const [];
  String _packageStatus = '';
  String _packageOutput = '';
  _PackageCancellation? _packageOperation;
  bool _picking = false;

  bool get _busy => _working || _packageOperation != null || _picking;

  List<Project> get _projects => widget.store.projects
      .where(
        (project) => !project.isCloud && Directory(project.path).existsSync(),
      )
      .toList();

  Project? get _project {
    final projects = _projects;
    if (projects.isEmpty) return null;
    return projects.where((item) => item.id == _projectId).firstOrNull ??
        projects.first;
  }

  String? get _selectedFile => _files.isEmpty
      ? null
      : (_files.contains(_entryFile) ? _entryFile : _files.first);

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onProjectsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshFiles();
    });
  }

  @override
  void didUpdateWidget(covariant PythonToolsBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onProjectsChanged);
      widget.store.addListener(_onProjectsChanged);
      _adoptProject(null);
      _refreshFiles();
    }
  }

  @override
  void dispose() {
    _invalidateOperation();
    widget.store.removeListener(_onProjectsChanged);
    _sourcePath.dispose();
    _packageName.dispose();
    _packageVersion.dispose();
    for (final directory in _pickedSources) {
      _discardPickedSource(directory);
    }
    super.dispose();
  }

  static void _discardPickedSource(Directory directory) {
    try {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    } on FileSystemException {
      // A temporary picker copy can be reclaimed by the OS later.
    }
  }

  static Future<void> _cancelQuietly(Future<void> Function() cancel) async {
    try {
      await cancel();
    } catch (_) {
      // A former page/project must not be updated by late cancellation.
    }
  }

  void _invalidateOperation() {
    _operationGeneration++;
    _packageOperation?.cancelled = true;
    _packageOperation = null;
    final cancel = _cancelRun;
    _cancelRun = null;
    if (cancel != null) unawaited(_cancelQuietly(cancel));
    _working = false;
    _picking = false;
  }

  void _adoptProject(Project? project) {
    if (_projectId == project?.id && _projectPath == project?.path) return;
    _invalidateOperation();
    _packagesGeneration++;
    _projectId = project?.id;
    _projectPath = project?.path;
    _entryFile = null;
    _files = const [];
    _output = '';
    _stderr = '';
    _status = '';
    _packages = const [];
    _packagesLoading = false;
    _packageStatus = '';
    _packageOutput = '';
    _sourcePath.clear();
    _packageName.clear();
    _packageVersion.clear();
  }

  bool _current(int generation, Project project) =>
      mounted &&
      generation == _operationGeneration &&
      _projectId == project.id &&
      _projectPath == project.path;

  void _onProjectsChanged() {
    if (mounted) _refreshFiles();
  }

  Future<void> _refreshFiles() async {
    final generation = ++_fileLoadGeneration;
    final project = _project;
    setState(() {
      _adoptProject(project);
      _loadingFiles = project != null;
    });
    if (project == null) return;
    if (_packagesExpanded) unawaited(_refreshPackages(project));
    final files = <String>[];
    String? error;
    try {
      await for (final entity in Directory(
        project.path,
      ).list(recursive: true, followLinks: false)) {
        if (entity is File &&
            {'.py', '.mpy'}.contains(p.extension(entity.path).toLowerCase()) &&
            !p
                .split(p.relative(entity.path, from: project.path))
                .contains('.qfli')) {
          files.add(entity.path);
        }
      }
      files.sort(
        (a, b) => p
            .relative(a, from: project.path)
            .compareTo(p.relative(b, from: project.path)),
      );
    } on FileSystemException catch (exception) {
      error = exception.message;
    }
    if (!mounted || generation != _fileLoadGeneration) return;
    setState(() {
      _files = files;
      _entryFile = _selectedFile;
      _loadingFiles = false;
      if (error != null) _status = error;
    });
  }

  Future<void> _execute({required bool checkOnly}) async {
    final project = _project;
    final file = _selectedFile;
    if (_busy || _loadingFiles || project == null || file == null) return;
    final generation = ++_operationGeneration;
    final runner = widget.runner;
    setState(() {
      _working = true;
      _status = checkOnly ? '正在检查语法' : '正在运行';
      _output = '';
      _stderr = '';
    });
    try {
      if (checkOnly) {
        final result = await runner.checkSyntax(
          projectPath: project.path,
          entryFile: file,
        );
        if (!_current(generation, project)) return;
        setState(() {
          _status = result.success ? '语法检查通过' : '语法检查失败';
          _stderr = result.error;
        });
      } else {
        final result = await runner.run(
          projectPath: project.path,
          entryFile: file,
        );
        if (result == null) {
          if (_current(generation, project)) {
            setState(() => _status = '无法运行此文件');
          }
          return;
        }
        // Also stop an early handle arriving after a project switch/disposal.
        if (_current(generation, project)) {
          setState(() => _cancelRun = result.cancel);
        } else if (result.cancel != null) {
          await _cancelQuietly(result.cancel!);
        }
        final stdout = result.stdout.toList();
        final stderr = result.stderr.toList();
        final exitCode = await result.exitCode;
        final output = await stdout;
        final errors = await stderr;
        if (!_current(generation, project)) return;
        setState(() {
          _status = '运行结束 · 退出码 $exitCode';
          _output = output.join('\n');
          _stderr = errors.join('\n');
        });
      }
    } catch (error) {
      if (_current(generation, project)) {
        setState(() {
          _status = checkOnly ? '语法检查失败' : '运行失败';
          _stderr = '$error';
        });
      }
    } finally {
      if (_current(generation, project)) {
        setState(() {
          _working = false;
          _cancelRun = null;
        });
      }
    }
  }

  Future<void> _compile() async {
    final project = _project;
    final file = _selectedFile;
    if (_busy || _loadingFiles || project == null || file == null) return;
    final generation = ++_operationGeneration;
    setState(() {
      _working = true;
      _status = '正在编译';
      _output = '';
      _stderr = '';
    });
    try {
      final result = await widget.runner.compile(
        projectPath: project.path,
        entryFile: file,
      );
      if (!_current(generation, project)) return;
      setState(() {
        _status = result.success ? '编译完成' : '编译失败';
        _output = result.success
            ? p.relative(result.artifactPath, from: project.path)
            : '';
        _stderr = result.success ? '' : result.error;
      });
      if (result.success) await _refreshFiles();
    } catch (error) {
      if (_current(generation, project)) {
        setState(() {
          _status = '编译失败';
          _stderr = '$error';
        });
      }
    } finally {
      if (_current(generation, project)) setState(() => _working = false);
    }
  }

  Future<void> _stop() async {
    final cancel = _cancelRun;
    final project = _project;
    final generation = _operationGeneration;
    if (cancel == null || project == null) return;
    setState(() {
      _cancelRun = null;
      _status = '正在停止';
    });
    try {
      await cancel();
    } catch (error) {
      // Native exit can settle while the stop request is still in flight.
      // Its late failure must not revive a completed run's cancel handle.
      if (_current(generation, project) && _working) {
        setState(() {
          _cancelRun = cancel;
          _stderr = '$error';
        });
      }
    }
  }

  PythonPackageService _service(Project project) {
    final runner = widget.runner;
    return widget.packageService ??
        PythonPackageService(
          syntaxCheck: (source, absoluteFilePath) async {
            final result = await runner.checkSource(
              projectPath: project.path,
              entryFile: absoluteFilePath,
              source: source,
            );
            return result.success ? null : result.error;
          },
        );
  }

  Future<void> _loadRuntime() async {
    if (_runtimeLoading) return;
    final generation = ++_runtimeGeneration;
    setState(() {
      _runtimeLoading = true;
      _runtimeError = '';
    });
    try {
      final runtime = await widget.runner.runtimeInfo();
      final modules =
          await (widget.packageService ?? PythonPackageService()).moduleCatalog;
      if (!mounted || generation != _runtimeGeneration) return;
      setState(() {
        _runtime = runtime;
        _modules = modules;
      });
    } catch (error) {
      if (mounted && generation == _runtimeGeneration) {
        setState(() => _runtimeError = '$error');
      }
    } finally {
      if (mounted && generation == _runtimeGeneration) {
        setState(() => _runtimeLoading = false);
      }
    }
  }

  Future<void> _refreshPackages(Project project) async {
    final generation = ++_packagesGeneration;
    setState(() => _packagesLoading = true);
    try {
      final packages = await _service(
        project,
      ).listInstalled(projectPath: project.path);
      if (!mounted ||
          generation != _packagesGeneration ||
          _projectPath != project.path) {
        return;
      }
      setState(() => _packages = packages);
    } catch (error) {
      if (mounted &&
          generation == _packagesGeneration &&
          _projectPath == project.path) {
        setState(() {
          _packageStatus = '无法读取已安装包';
          _packageOutput = '$error';
        });
      }
    } finally {
      if (mounted && generation == _packagesGeneration) {
        setState(() => _packagesLoading = false);
      }
    }
  }

  Future<void> _pickPackage({required bool folder}) async {
    final project = _project;
    if (_busy || project == null) return;
    final generation = ++_operationGeneration;
    setState(() => _picking = true);
    try {
      final document = await PickerService.pickDocument(
        folder: folder,
        extensions: folder ? const [] : const ['py', 'zip', 'whl'],
      );
      if (!_current(generation, project) || document == null) return;
      var path = document.path;
      if (!document.isLocalFile) {
        if (folder || document.uri == null) {
          throw const FileSystemException('请选择已导入应用沙盒的目录，或直接输入本地目录路径。');
        }
        final name = p.basename((document.name ?? '').replaceAll('\\', '/'));
        if (name.isEmpty ||
            !{
              '.py',
              '.zip',
              '.whl',
            }.contains(p.extension(name).toLowerCase())) {
          throw const FormatException('选择的文件缺少有效的 .py、.zip 或 .whl 文件名。');
        }
        final bytes = await PickerService.readUri(document.uri!);
        if (!_current(generation, project)) return;
        if (bytes.length > 16 * 1024 * 1024) {
          throw const FormatException('本地包超过 16 MiB 限制。');
        }
        final temporary = await Directory.systemTemp.createTemp(
          'qfli_python_import_',
        );
        if (!_current(generation, project)) {
          _discardPickedSource(temporary);
          return;
        }
        _pickedSources.add(temporary);
        path = p.join(temporary.path, name);
        await File(path).writeAsBytes(bytes, flush: true);
      }
      if (!_current(generation, project)) return;
      setState(() {
        _sourcePath.text = path!;
        _packageStatus = '已选择本地${folder ? '目录' : '文件'}';
        _packageOutput = '';
      });
    } catch (error) {
      if (_current(generation, project)) {
        setState(() {
          _packageStatus = '无法选择本地包';
          _packageOutput = '$error';
        });
      }
    } finally {
      if (_current(generation, project)) setState(() => _picking = false);
    }
  }

  Future<void> _packageAction(String action, {String? name}) async {
    final project = _project;
    if (_busy || project == null) return;
    final generation = ++_operationGeneration;
    final cancellation = _PackageCancellation();
    final service = _service(project);
    final sourcePath = _sourcePath.text.trim();
    final packageName = _packageName.text.trim();
    final version = _packageVersion.text.trim();
    setState(() {
      _packageOperation = cancellation;
      _packageStatus = switch (action) {
        'check' => '正在检查本地包',
        'install' => '正在安装本地包',
        'remove' => '正在移除本地包',
        _ => '正在读取包详情',
      };
      _packageOutput = '';
    });
    try {
      if (action == 'check') {
        final result = await service.check(
          projectPath: project.path,
          sourcePath: sourcePath,
          name: packageName.isEmpty ? null : packageName,
          version: version.isEmpty ? null : version,
          isCancelled: () => cancellation.cancelled,
        );
        if (!_current(generation, project)) return;
        setState(() {
          _packageStatus = result.compatible ? '兼容性检查通过' : '兼容性检查未通过';
          _packageOutput = [
            result.message,
            if (result.name.isNotEmpty) '${result.name} ${result.version}',
            ...result.files,
          ].join('\n');
        });
      } else if (action == 'show') {
        final item = await service.show(projectPath: project.path, name: name!);
        if (!_current(generation, project)) return;
        setState(() {
          _packageStatus = item == null ? '当前项目没有安装此包' : '包详情 · ${item.name}';
          _packageOutput = item == null
              ? ''
              : [
                  '${item.name} ${item.version}',
                  '来源：${item.source}',
                  '安装时间：${item.installedAt.toLocal()}',
                  for (final entry in item.files.entries)
                    '${entry.key}\nSHA256 ${entry.value}',
                ].join('\n');
        });
      } else {
        final result = action == 'install'
            ? await service.install(
                projectPath: project.path,
                sourcePath: sourcePath,
                name: packageName.isEmpty ? null : packageName,
                version: version.isEmpty ? null : version,
                isCancelled: () => cancellation.cancelled,
              )
            : await service.remove(
                projectPath: project.path,
                name: name!,
                isCancelled: () => cancellation.cancelled,
              );
        if (!_current(generation, project)) return;
        setState(() {
          _packageStatus = result.success
              ? (action == 'install' ? '本地包安装完成' : '本地包移除完成')
              : '本地包操作未完成';
          _packageOutput = [
            result.message,
            if (result.preservedFiles.isNotEmpty) '保留的已修改文件：',
            ...result.preservedFiles,
          ].join('\n');
        });
        await _refreshPackages(project);
        if (_current(generation, project) && result.success) {
          await _refreshFiles();
        }
      }
    } catch (error) {
      if (_current(generation, project)) {
        setState(() {
          _packageStatus = '本地包操作未完成';
          _packageOutput = '$error';
        });
      }
    } finally {
      if (_current(generation, project)) {
        setState(() => _packageOperation = null);
      }
    }
  }

  Widget _outputBox(String text, {required String label}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 6),
        SelectableText(
          text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
      ],
    ),
  );

  Widget _projectControls(Project project) {
    final file = _selectedFile;
    final canExecute = file != null && !_busy && !_loadingFiles;
    final canSource = canExecute && p.extension(file).toLowerCase() == '.py';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('project:${project.id}:${project.path}'),
          initialValue: project.id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '项目'),
          items: [
            for (final item in _projects)
              DropdownMenuItem(
                value: item.id,
                child: Text(item.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _busy
              ? null
              : (id) {
                  setState(
                    () => _adoptProject(
                      _projects.where((item) => item.id == id).firstOrNull,
                    ),
                  );
                  _refreshFiles();
                },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('file:${project.id}:${file ?? ''}'),
                initialValue: file,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Python 文件'),
                items: [
                  for (final path in _files)
                    DropdownMenuItem(
                      value: path,
                      child: Text(
                        p.relative(path, from: project.path),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _busy || _loadingFiles
                    ? null
                    : (path) => setState(() => _entryFile = path),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '刷新文件',
              onPressed: _busy || _loadingFiles ? null : _refreshFiles,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_loadingFiles)
          const LinearProgressIndicator()
        else if (_files.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('项目中没有 Python 文件'),
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: canSource ? () => _execute(checkOnly: true) : null,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('检查语法'),
            ),
            IconButton.filledTonal(
              tooltip: '编译',
              onPressed: canSource ? _compile : null,
              icon: const Icon(Icons.build_outlined),
            ),
            IconButton.filledTonal(
              tooltip: '停止运行',
              onPressed: _cancelRun == null ? null : _stop,
              icon: const Icon(Icons.stop),
            ),
            FilledButton.icon(
              onPressed: canExecute ? () => _execute(checkOnly: false) : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('运行'),
            ),
          ],
        ),
        if (_status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_status, style: Theme.of(context).textTheme.titleSmall),
          ),
        if (_output.isNotEmpty) _outputBox(_output, label: '标准输出 / 编译产物'),
        if (_stderr.isNotEmpty) _outputBox(_stderr, label: '标准错误 / 诊断'),
      ],
    );
  }

  Widget _runtimeControls() => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: const Text('运行时与模块'),
    subtitle: const Text('查看内嵌解释器和离线模块的支持范围'),
    onExpansionChanged: (expanded) {
      if (expanded && _modules == null) _loadRuntime();
    },
    children: [
      if (_runtimeLoading) const LinearProgressIndicator(),
      if (_runtime != null)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            _runtime!.available ? '运行时可用 · ${_runtime!.version}' : '运行时不可用',
          ),
          subtitle: Text(
            _runtime!.available
                ? '传输：${_runtime!.transport} · 编译产物：${_runtime!.supportsArtifacts ? '支持' : '不支持'} · 停止：${_runtime!.supportsCancellation ? '支持' : '不支持'}'
                : _runtime!.detail,
          ),
        ),
      if (_runtimeError.isNotEmpty) _outputBox(_runtimeError, label: '读取失败'),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _runtimeLoading ? null : _loadRuntime,
          icon: const Icon(Icons.refresh),
          label: const Text('刷新运行时与模块'),
        ),
      ),
      for (final module in _modules ?? <PythonModuleInfo>[])
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(module.name),
          subtitle: Text(
            '${module.origin == PythonModuleOrigin.builtIn ? '内嵌' : '随应用提供'} · ${module.version} · ${module.summary}',
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  [
                    module.apis.isEmpty
                        ? 'API 以当前 MicroPython 实际支持为准。'
                        : '支持的 API：${module.apis.join(', ')}',
                    if (module.license.isNotEmpty) '许可：${module.license}',
                    if (module.source.isNotEmpty) '来源：${module.source}',
                  ].join('\n'),
                ),
              ),
            ),
          ],
        ),
    ],
  );

  Widget _packageControls(Project project) => ExpansionTile(
    key: ValueKey('packages:${project.id}:${project.path}'),
    initiallyExpanded: _packagesExpanded,
    tilePadding: EdgeInsets.zero,
    title: const Text('本地源码包'),
    subtitle: const Text('检查、安装和移除当前项目的离线纯 Python 包'),
    onExpansionChanged: (expanded) {
      _packagesExpanded = expanded;
      if (expanded) _refreshPackages(project);
    },
    children: [
      const Text(
        '支持源码文件、目录及兼容的 .zip / .whl。先检查当前 VM 语法和直接依赖；第三方 API 仍需运行验证。安装位置：当前项目 lib/。',
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('python-package-source'),
        controller: _sourcePath,
        enabled: !_busy,
        maxLines: 3,
        minLines: 1,
        decoration: const InputDecoration(
          labelText: '本地文件或目录路径',
          hintText: '输入应用可读取的绝对路径',
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _pickPackage(folder: false),
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('选择包文件'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _pickPackage(folder: true),
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('选择本地目录'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _packageName,
        enabled: !_busy,
        decoration: const InputDecoration(labelText: '包名（可选，默认从本地内容推断）'),
      ),
      TextField(
        controller: _packageVersion,
        enabled: !_busy,
        decoration: const InputDecoration(labelText: '版本（可选）'),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.tonalIcon(
            onPressed: _busy ? null : () => _packageAction('check'),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('检查兼容性'),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : () => _packageAction('install'),
            icon: const Icon(Icons.download_done),
            label: const Text('安装到项目'),
          ),
          OutlinedButton.icon(
            onPressed: _packageOperation == null || _packageOperation!.cancelled
                ? null
                : () {
                    setState(() {
                      _packageOperation!.cancelled = true;
                      _packageStatus = '正在取消本地包操作';
                    });
                  },
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('取消包操作'),
          ),
        ],
      ),
      if (_packageOperation != null || _picking)
        const LinearProgressIndicator(),
      if (_packageStatus.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(_packageStatus),
          ),
        ),
      if (_packageOutput.isNotEmpty) _outputBox(_packageOutput, label: '本地包结果'),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _busy || _packagesLoading
              ? null
              : () => _refreshPackages(project),
          icon: const Icon(Icons.refresh),
          label: const Text('刷新已安装包'),
        ),
      ),
      if (_packagesLoading)
        const LinearProgressIndicator()
      else if (_packages.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('当前项目没有已安装的本地包'),
        ),
      for (final item in _packages)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${item.name} ${item.version} · ${item.files.length} 个文件'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _packageAction('show', name: item.name),
                    child: Text('详情 ${item.name}'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _packageAction('remove', name: item.name),
                    child: Text('移除 ${item.name}'),
                  ),
                ],
              ),
            ],
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final project = _project;
    return PageStorage(
      bucket: _pageStorage,
      child: CustomScrollView(
        key: const ValueKey<String>('python-tools-scroll'),
        slivers: [
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ToolsSectionHeading(
                        icon: Icons.code,
                        title: 'Python',
                      ),
                      if (widget.onOpenTerminal != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: widget.onOpenTerminal,
                            icon: const Icon(Icons.terminal),
                            label: const Text('终端'),
                          ),
                        ),
                      const SizedBox(height: 16),
                      if (project == null)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('没有本地项目'),
                        )
                      else
                        _projectControls(project),
                      const SizedBox(height: 16),
                      _runtimeControls(),
                      if (project != null) _packageControls(project),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (widget.onOpenTerminal != null) ...[
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
              sliver: SliverToBoxAdapter(
                child: ToolsSectionHeading(
                  icon: Icons.build_outlined,
                  title: '通用',
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: ToolsGridSliver(tools: commonTools),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverToBoxAdapter(child: Text('通用工具均在本机离线计算，不会上传任何内容。')),
            ),
          ],
        ],
      ),
    );
  }
}

class _PackageCancellation {
  bool cancelled = false;
}
