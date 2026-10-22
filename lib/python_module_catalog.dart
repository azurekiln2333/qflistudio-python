/// Where an importable module comes from in the embedded interpreter.
enum PythonModuleOrigin { builtIn, bundled, project }

/// The supported surface of a module, rather than a claim of CPython parity.
class PythonModuleInfo {
  const PythonModuleInfo({
    required this.name,
    required this.version,
    required this.summary,
    required this.origin,
    this.apis = const [],
    this.license = '',
    this.source = '',
  });

  final String name;
  final String version;
  final String summary;
  final PythonModuleOrigin origin;
  final List<String> apis;
  final String license;
  final String source;
}

/// Importability was probed against the actual MicroPython 1.24.1 build.
/// An empty API list deliberately makes no additional compatibility promise.
const pythonBuiltInModules = <PythonModuleInfo>[
  PythonModuleInfo(
    name: 'sys',
    version: 'MicroPython 1.24.1',
    summary: '解释器信息和标准流',
    origin: PythonModuleOrigin.builtIn,
  ),
  PythonModuleInfo(
    name: 'math',
    version: 'MicroPython 1.24.1',
    summary: '实数数学函数',
    origin: PythonModuleOrigin.builtIn,
  ),
  PythonModuleInfo(
    name: 'cmath',
    version: 'MicroPython 1.24.1',
    summary: '复数数学函数',
    origin: PythonModuleOrigin.builtIn,
  ),
  PythonModuleInfo(
    name: 'json',
    version: 'MicroPython 1.24.1',
    summary: 'JSON 编解码',
    origin: PythonModuleOrigin.builtIn,
  ),
  PythonModuleInfo(
    name: 'random',
    version: 'MicroPython 1.24.1',
    summary: '伪随机数',
    origin: PythonModuleOrigin.builtIn,
  ),
  PythonModuleInfo(
    name: 'time',
    version: 'MicroPython 1.24.1',
    summary: '时间和延时',
    origin: PythonModuleOrigin.builtIn,
  ),
  PythonModuleInfo(
    name: 're',
    version: 'MicroPython 1.24.1',
    summary: 'MicroPython 正则表达式子集',
    origin: PythonModuleOrigin.builtIn,
  ),
  PythonModuleInfo(
    name: 'binascii',
    version: 'MicroPython 1.24.1',
    summary: '二进制文本转换',
    origin: PythonModuleOrigin.builtIn,
  ),
  PythonModuleInfo(
    name: 'heapq',
    version: 'MicroPython 1.24.1',
    summary: '最小堆',
    origin: PythonModuleOrigin.builtIn,
  ),
  PythonModuleInfo(
    name: 'array',
    version: 'MicroPython 1.24.1',
    summary: '紧凑数值数组',
    origin: PythonModuleOrigin.builtIn,
  ),
  PythonModuleInfo(
    name: 'collections',
    version: 'MicroPython 1.24.1',
    summary: 'MicroPython 集合类型',
    origin: PythonModuleOrigin.builtIn,
  ),
  PythonModuleInfo(
    name: 'struct',
    version: 'MicroPython 1.24.1',
    summary: '二进制数据布局',
    origin: PythonModuleOrigin.builtIn,
  ),
  PythonModuleInfo(
    name: 'io',
    version: 'MicroPython 1.24.1',
    summary: '内存流和项目文件',
    origin: PythonModuleOrigin.builtIn,
  ),
  PythonModuleInfo(
    name: 'errno',
    version: 'MicroPython 1.24.1',
    summary: '系统错误码',
    origin: PythonModuleOrigin.builtIn,
  ),
  PythonModuleInfo(
    name: 'micropython',
    version: 'MicroPython 1.24.1',
    summary: 'MicroPython 运行时接口',
    origin: PythonModuleOrigin.builtIn,
  ),
  PythonModuleInfo(
    name: 'gc',
    version: 'MicroPython 1.24.1',
    summary: '垃圾回收控制',
    origin: PythonModuleOrigin.builtIn,
  ),
  PythonModuleInfo(
    name: 'builtins',
    version: 'MicroPython 1.24.1',
    summary: '内置函数和类型',
    origin: PythonModuleOrigin.builtIn,
  ),
];
