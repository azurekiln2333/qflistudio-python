import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/store/project_store.dart';

import 'python_runner.dart';

Widget buildPythonToolsPage(ProjectStore store) =>
    PythonToolsPage(store: store);

class PythonToolsPage extends StatefulWidget {
  const PythonToolsPage({super.key, required this.store});

  final ProjectStore store;

  @override
  State<PythonToolsPage> createState() => _PythonToolsPageState();
}

class _PythonToolsPageState extends State<PythonToolsPage> {
  static const _runner = PythonProgramRunner();

  String? _projectId;
  String? _entryFile;
  List<String> _files = const [];
  String _output = '';
  String _status = '';
  bool _loadingFiles = false;
  bool _working = false;
  int _fileLoadGeneration = 0;

  List<Project> get _projects => widget.store.projects
      .where(
        (project) => !project.isCloud && Directory(project.path).existsSync(),
      )
      .toList();

  Project? get _project {
    final projects = _projects;
    if (projects.isEmpty) return null;
    for (final project in projects) {
      if (project.id == _projectId) return project;
    }
    return projects.first;
  }

  String? get _selectedFile {
    if (_files.isEmpty) return null;
    return _files.contains(_entryFile) ? _entryFile : _files.first;
  }

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onProjectsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshFiles());
  }

  @override
  void dispose() {
    widget.store.removeListener(_onProjectsChanged);
    super.dispose();
  }

  void _onProjectsChanged() {
    if (mounted) _refreshFiles();
  }

  Future<void> _refreshFiles() async {
    final generation = ++_fileLoadGeneration;
    final project = _project;
    if (project == null) {
      setState(() {
        _projectId = null;
        _files = const [];
        _entryFile = null;
        _loadingFiles = false;
        _output = '';
        _status = '';
      });
      return;
    }
    final projectId = project.id;
    setState(() {
      if (_projectId != projectId) {
        _projectId = projectId;
        _files = const [];
        _entryFile = null;
        _output = '';
        _status = '';
      }
      _loadingFiles = true;
    });
    final files = <String>[];
    String? error;
    try {
      await for (final entity in Directory(
        project.path,
      ).list(recursive: true, followLinks: false)) {
        if (entity is File && p.extension(entity.path).toLowerCase() == '.py') {
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
    if (_working || _loadingFiles || project == null || file == null) return;
    setState(() {
      _working = true;
      _status = checkOnly ? '正在检查语法' : '正在运行';
      _output = '';
    });
    try {
      if (checkOnly) {
        final result = await _runner.checkSyntax(
          projectPath: project.path,
          entryFile: file,
        );
        if (!mounted) return;
        setState(() {
          _status = result.success ? '语法检查通过' : '语法检查失败';
          _output = result.error;
        });
      } else {
        final result = await _runner.run(
          projectPath: project.path,
          entryFile: file,
        );
        if (result == null) {
          if (mounted) setState(() => _status = '无法运行此文件');
          return;
        }
        final stdout = result.stdout.toList();
        final stderr = result.stderr.toList();
        final exitCode = await result.exitCode;
        final lines = [...await stdout, ...await stderr];
        if (!mounted) return;
        setState(() {
          _status = '运行结束 · 退出码 $exitCode';
          _output = lines.join('\n');
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = checkOnly ? '语法检查失败' : '运行失败';
          _output = '$error';
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = _project;
    final file = _selectedFile;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Python 工具')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (project == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('没有本地项目'),
                )
              else ...[
                DropdownButtonFormField<String>(
                  key: ValueKey(project.id),
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
                  onChanged: _working
                      ? null
                      : (id) {
                          setState(() {
                            _projectId = id;
                            _entryFile = null;
                            _files = const [];
                            _output = '';
                            _status = '';
                          });
                          _refreshFiles();
                        },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('${project.id}:${file ?? ''}'),
                        initialValue: file,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Python 文件',
                        ),
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
                        onChanged: _working || _loadingFiles
                            ? null
                            : (path) => setState(() => _entryFile = path),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '刷新文件',
                      onPressed: _working || _loadingFiles
                          ? null
                          : _refreshFiles,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                if (_loadingFiles)
                  const LinearProgressIndicator()
                else if (_files.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('项目中没有 .py 文件'),
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: file == null || _working || _loadingFiles
                          ? null
                          : () => _execute(checkOnly: true),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('检查语法'),
                    ),
                    FilledButton.icon(
                      onPressed: file == null || _working || _loadingFiles
                          ? null
                          : () => _execute(checkOnly: false),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('运行'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (_status.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _status,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                Container(
                  constraints: const BoxConstraints(minHeight: 180),
                  padding: const EdgeInsets.all(12),
                  color: scheme.surfaceContainerLowest,
                  child: SelectableText(
                    _output,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
