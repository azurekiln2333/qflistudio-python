/*
 * ArkTS 接线：把 libqfli_py.so 的执行接口挂到 Flutter 的 MethodChannel 上。
 *
 * 为什么需要这一层：Flutter 的 Dart 代码不能直接调 NAPI，链路必须是
 *
 *   Dart → MethodChannel → ArkTS（本文件）→ libqfli_py.so → MicroPython
 *
 * ⚠️ 本文件有两份**逐字节相同**的副本。改任何一份都必须同步另一份，
 * 因为只有下面第二份在构建路径里——它漂了不会有任何编译错误或测试失败：
 *
 *   apps/qfli_python/native/ohos/QfliPyNative.ets                     ← 不在构建路径
 *   apps/qfli_python/ohos/entry/src/main/ets/plugins/QfliPyNative.ets ← 进构建的那份
 *
 * 为什么要留两份：native/ 不在构建路径上，所以那份不会被编译；而 ArkTS 的
 * import 是构建期解析的，`.so` 不在位整个 App 直接编不过，模板也就没法独立存在。
 *
 * 同步检查（两个哈希相等即通过）：
 *   Get-FileHash apps\qfli_python\native\ohos\QfliPyNative.ets,
 *     apps\qfli_python\ohos\entry\src\main\ets\plugins\QfliPyNative.ets -Algorithm SHA256
 *
 * 启用步骤（native/README.md 里有完整版）：
 *
 *   1. 把本文件复制到
 *        ohos/entry/src/main/ets/plugins/QfliPyNative.ets
 *   2. 在 EntryAbility.ets 的 configureFlutterEngine 里加一行：
 *        registerQfliPyNativeChannel(flutterEngine);
 *   3. 把 libqfli_py.so 放到 ohos/entry/libs/arm64-v8a/
 *      （用 native/build.ps1 会自动拷过去，**不需要**改 oh-package.json5）
 *
 * ⚠️ ArkTS 的 import 是**构建期**解析的：`.so` 不在位，整个 App 直接编不过。
 * 但反过来不成立——`.so` 在位、构建通过，**不代表运行时装得上**：只要它的
 * 动态依赖里有一个 HAP 里没有的库（典型是 libc++_shared.so），dlopen 就会
 * 失败，而这条 import 拿到的会是 undefined。所以下面所有对原生模块的调用
 * 都先判空，见 nativeModule 那段注释。
 */
import qfliPyNative from 'libqfli_py.so';
import {
  FlutterEngine,
  MethodChannel,
  MethodCall,
  MethodResult,
} from '@ohos/flutter_ohos';
import { hilog } from '@kit.PerformanceAnalysisKit';
import fs from '@ohos.file.fs';

/** 与 native/src/qfli_py_napi.cpp 的返回结构一一对应。 */
interface PyRunOutcome {
  exitCode: number;
  output: string;
  error: string | null;
  truncated: boolean;
}

/** 与 native/src/qfli_py_napi.cpp 导出的成员一一对应。 */
interface QfliPyModule {
  run(source: string, stdin: string, heapKb: number,
    projectPath: string, entryFile: string, compileOnly: boolean,
    token: number, artifactOutput: string,
    bytecodeFile: string): Promise<PyRunOutcome>;
  createCancel(): number;
  cancel(token: number): void;
  freeCancel(token: number): void;
  version(): string;
}

/** `available` 的返回结构：不只是一个 bool，还带「为什么不可用」。 */
interface PyProbeResult {
  available: boolean;
  version: string;
  detail: string;
  runControl?: boolean;
  bytecode?: boolean;
}

interface PySelfCheckCase {
  name: string;
  source: string;
  stdin: string;
  exitCode: number;
  output: string;
  error: string | null;
  projectPath?: string;
  entryFile?: string;
  compileOnly?: boolean;
}

/** 注册表里的一个运行会话：一个取消 token，对应一次已提交或待提交的执行。 */
interface PyRunSession {
  token: number;
  submitted: boolean;
}

/** Dart 侧 PythonProgramRunner 用的通道名。 */
const CHANNEL_NATIVE = 'qfli_py/native';

/** 与 native/src/qfli_py_bridge.c 的默认堆大小一致（8 MB）。 */
const DEFAULT_HEAP_KB = 8 * 1024;

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'QfliPyNative';

/**
 * 原生模块句柄。
 *
 * 刻意**不**直接写 `qfliPyNative.run(...)`。
 *
 * 当 libqfli_py.so 的 dlopen 失败时，ArkTS 的这个 import 拿到的是 undefined。
 * 此时裸调会抛 "Cannot read property run of undefined"——这条报错里没有一个字
 * 有用：看不出是哪个 .so、什么原因、怎么修。而 dlopen 失败最常见的原因是
 * 「.so 带了一个 HAP 里没有的动态依赖」（比如 libc++_shared.so），hilog 里其实
 * 写得很清楚，只是没人会想到去那里找。
 *
 * 所以先取出来判空，把「不可用」变成一条能读的诊断。
 */
const nativeModule = qfliPyNative as QfliPyModule | undefined;

/** 模块是否真的可用（不是「文件在不在」，是「dlopen 成没成功」）。 */
function nativeReady(): boolean {
  return nativeModule !== undefined && nativeModule !== null
    && typeof nativeModule.run === 'function';
}

/**
 * 模块是否具备受控执行能力（取消 + 异步 worker + 字节码）。
 *
 * 探的是**函数存在性**，不是写死 true。旧版 .so 只导出同步的
 * run(source, stdin, heapKb, projectPath, entryFile, compileOnly)，没有
 * createCancel/cancel/freeCancel；这时必须硬报 false，否则 Dart 侧会按
 * 「支持取消」去调 prepareRun，最后在真机上以含糊的错误收场。
 * 「装了一个旧的 .so」是会真实发生的（只更新了 ArkTS 没重编 .so）。
 */
function nativeRunControlReady(): boolean {
  return nativeReady()
    && typeof nativeModule?.createCancel === 'function'
    && typeof nativeModule?.cancel === 'function'
    && typeof nativeModule?.freeCancel === 'function';
}

/** 模块不可用时的说明。写给用户看，不是写给日志看。 */
const MODULE_MISSING_DETAIL =
  'Python 运行组件加载失败，请重新安装应用。';

/**
 * 把捕获到的任意值转成可读文本。
 *
 * 不能依赖 `instanceof Error`：跨 realm（比如测试用 vm 上下文、或 native
 * 回传的错误）时 `instanceof` 会是 false，结果把 "Error: xxx" 整个带前缀
 * 地回给用户，而不是干净的 message。用鸭子类型取 .message 更稳。
 */
function errorText(error: Object): string {
  if (error === null || error === undefined) {
    return 'unknown error';
  }
  const message = (error as Error).message;
  if (typeof message === 'string' && message.length > 0) {
    return message;
  }
  return `${error}`;
}

/** 取版本号，拿不到就返回空串（不影响可用性判断）。 */
function nativeVersion(): string {
  // 同 runNative：先把方法抠成局部变量，避免 ArkTS 在跨语句后
  // 丢掉 mod 的非空收窄（会报 `'mod' is possibly 'undefined'`）。
  const version = nativeModule?.version;
  if (typeof version !== 'function') {
    return '';
  }
  try {
    return version();
  } catch (e) {
    return '';
  }
}

/**
 * 提交一次原生执行，返回 Promise。
 *
 * token 为 0 表示这次执行不可取消（旧 .so 或自检用）；artifactOutput 只对
 * compileOnly 有意义（写 .mpy），bytecodeFile 只对执行有意义（读 .mpy）。
 * 真正的 VM 跑在 NAPI 的 worker 线程上，ArkTS 线程只等待 Promise。
 *
 * 这里是 **async** 函数，而且对原生返回值做 Promise 归一化，两个原因都是真机上
 * 会碰到的：
 *
 *   1. 新版 .so 的 run 返回 Promise；旧版 .so 的 run 是同步的、直接返回结果对象。
 *      如果直接声明成 `Promise<PyRunOutcome>` 再 `return run(...)`，类型在编译期
 *      被当成 Promise 而运行期拿到的是裸对象，调用方 `.then()` 会 TypeError，
 *      而且这次运行的结果永远回不到 Dart（channel 挂着不返回）。
 *   2. 旧版 .so 的同步 run 可能抛异常（比如原生 dlopen 后调用失败）。直接
 *      `return run(...)` 会让异常冒泡到通道 handler 外，同样不回 result。
 *
 * async 函数会自动把同步 throw 变成 rejected Promise；Promise.resolve 把裸对象
 * 归一成 resolved Promise。两条合起来，无论 .so 是哪一版都只有一个确定的形状。
 */
async function runNative(
  source: string,
  stdin: string,
  heapKb: number,
  projectPath: string = '',
  entryFile: string = '',
  compileOnly: boolean = false,
  token: number = 0,
  artifactOutput: string = '',
  bytecodeFile: string = '',
): Promise<PyRunOutcome> {
  // 注意：这里必须把 run 取成一个局部函数再调。
  // ArkTS 的流分析不会用 nativeModule 的初始化结果去收窄它的类型。
  const run = nativeModule?.run;
  if (typeof run !== 'function') {
    return {
      exitCode: -1,
      error: MODULE_MISSING_DETAIL,
      output: '',
      truncated: false,
    };
  }
  // Promise.resolve 同时吃「Promise」和「裸对象」；async 会把同步 throw 收成 reject。
  const outcome = await Promise.resolve(run(source, stdin, heapKb, projectPath,
    entryFile, compileOnly, token, artifactOutput, bytecodeFile));
  /*
   * 原生返回结构不对时**抛错**，不能伪造一个 exitCode=-1 的结果：那会让 Dart
   * 侧把它当成“程序真的跑了并退出 -1”，与本任务一直在防的「假成功/假结果」
   * 是同一类问题。抛出的异常由 handler 的 .catch 映射成 transport failure
   * （result.error），语义上就是“这次运行没能交给后端”。
   */
  if (outcome === undefined || outcome === null
    || typeof outcome.exitCode !== 'number') {
    throw new Error('原生运行时返回了意外的结果');
  }
  return outcome;
}

/**
 * 运行会话注册表。
 *
 * token 的所有权规则与 Android 的 RunSession 一致：
 *   - prepareRun 创建 token 并登记；
 *   - run 提交时把它交给本次执行（submitted=true）；
 *   - 执行完成（成功或异常）后立刻释放并移除，所以「完成后再 cancel」
 *     是安全的 no-op，不会去碰已经 free 掉的指针；
 *   - cancel 只置位原子标志，任何时候调用都不会干扰另一次执行。
 *
 * Dart 侧的一次运行 = prepareRun → run(runId) →（可选）cancel(runId)，
 * 与 Kotlin 侧完全同构。
 */
const sessions = new Map<string, PyRunSession>();
let nextRunId = 0;

function prepareRun(): string {
  // 必须检完整三项（create/cancel/free）才允许分配：只检 create 的话，
  // 一个缺 cancel/free 的残缺模块会在分配后无法释放（token 泄漏）或在
  // 提交时才失败，留下一个已登记的死会话。nativeRunControlReady() 就是
  // available 广告受控能力时用的同一判据，两处保持一致。
  if (!nativeRunControlReady()) {
    throw new Error('原生运行时不支持取消');
  }
  const create = nativeModule?.createCancel;
  if (typeof create !== 'function') {
    throw new Error('原生运行时不支持取消');
  }
  const token = create();
  if (token === 0) {
    throw new Error('无法分配取消 token');
  }
  const id = (++nextRunId).toString();
  sessions.set(id, { token, submitted: false });
  return id;
}

function cancelRun(id: string): boolean {
  const session = sessions.get(id);
  if (session === undefined) {
    // 已经结束的运行：晚到的取消是无害的 no-op。
    return false;
  }
  const cancel = nativeModule?.cancel;
  if (typeof cancel === 'function') {
    cancel(session.token);
  }
  return true;
}

function releaseRun(id: string): void {
  const session = sessions.get(id);
  if (session === undefined) {
    return;
  }
  sessions.delete(id);
  const free = nativeModule?.freeCancel;
  if (typeof free === 'function') {
    free(session.token);
  }
}

/**
 * 启动自检。
 *
 * 做两件事，都是为了让「后端到底通没通」在 hilog 里一眼可见，不必装完再点开
 * App 手点一次运行：
 *
 *   1. 报出 .so 的加载结果和 MicroPython 的真实版本号；
 *   2. 真跑一组 Python 编译、执行和隔离用例，把结果打出来。
 *
 * 第 2 步顺带把 VM 初始化掉（8MB GC 堆），第一次按运行的时候少一点等待。
 * 整个自检失败不影响 App 启动——出错只写日志。
 *
 * 排查时：hdc shell hilog -x | Select-String QfliPyNative
 */
async function selfCheck(): Promise<void> {
  if (!nativeReady()) {
    hilog.error(LOG_DOMAIN, LOG_TAG, 'libqfli_py.so 未加载：%{public}s',
      MODULE_MISSING_DETAIL);
    return;
  }

  try {
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'libqfli_py.so 已加载，MicroPython %{public}s，受控执行 %{public}s',
      nativeVersion(), nativeRunControlReady() ? '可用' : '不可用（旧 .so）');

    const projectPath = '/data/storage/el2/base/cache/qfli_py_selfcheck';
    const srcPath = `${projectPath}/src`;
    const packagePath = `${srcPath}/samplepkg`;
    if (!fs.accessSync(packagePath)) {
      fs.mkdirSync(packagePath, true);
    }
    const writeSource = (path: string, source: string): void => {
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, source);
      } finally {
        fs.closeSync(file.fd);
      }
    };
    writeSource(`${srcPath}/helper.py`, 'answer = 42\n');
    writeSource(`${packagePath}/__init__.py`, 'from .value import answer\n');
    writeSource(`${packagePath}/value.py`, 'answer = 84\n');

    const cases: PySelfCheckCase[] = [
      { name: 'compile-run', source: 'value = 42\nprint(value)', stdin: '',
        exitCode: 0, output: '42\n', error: null },
      { name: 'fresh-globals', source: 'print(value)', stdin: '',
        exitCode: 1, output: '', error: 'NameError' },
      { name: 'syntax-error', source: 'def broken(:\n    pass', stdin: '',
        exitCode: 1, output: '', error: 'SyntaxError' },
      { name: 'runtime-error', source: "raise ValueError('bad')", stdin: '',
        exitCode: 1, output: '', error: 'ValueError: bad' },
      { name: 'stdin', source: "print(input('name? '))", stdin: 'Ada\n',
        exitCode: 0, output: 'Ada\n', error: null },
      { name: 'exit-code', source: 'import sys\nsys.exit(7)', stdin: '',
        exitCode: 7, output: '', error: null },
      { name: 'upstream-module', source: 'import math\nprint(math.sqrt(81))', stdin: '',
        exitCode: 0, output: '9.0\n', error: null },
      { name: 'project-paths',
        source: 'import sys\nprint(sys.path[0], sys.path[1], sys.argv[0], __file__)',
        stdin: '', exitCode: 0,
        output: '/qfli/project/src /qfli/project /qfli/project/src/main.py /qfli/project/src/main.py\n',
        error: null, projectPath: '/qfli/project', entryFile: '/qfli/project/src/main.py' },
      { name: 'sibling-import', source: 'import helper\nprint(helper.answer)', stdin: '',
        exitCode: 0, output: '42\n', error: null,
        projectPath, entryFile: `${srcPath}/main.py` },
      { name: 'package-import', source: 'from samplepkg import answer\nprint(answer)', stdin: '',
        exitCode: 0, output: '84\n', error: null,
        projectPath, entryFile: `${srcPath}/main.py` },
      { name: 'text-file',
        source: "with open('notes.txt', 'w') as file:\n    file.write('hello')\nwith open('notes.txt') as file:\n    print(file.read())",
        stdin: '', exitCode: 0, output: 'hello\n', error: null,
        projectPath, entryFile: `${srcPath}/main.py` },
      { name: 'append-file',
        source: "import io\nwith io.open('notes.txt', mode='a') as file:\n    file.write('!')\nwith open('notes.txt') as file:\n    print(file.read())",
        stdin: '', exitCode: 0, output: 'hello!\n', error: null,
        projectPath, entryFile: `${srcPath}/main.py` },
      { name: 'binary-file',
        source: "with open('raw.bin', 'wb') as file:\n    file.write(bytes([0, 255]))\nwith open('raw.bin', 'rb') as file:\n    print(list(file.read()))",
        stdin: '', exitCode: 0, output: '[0, 255]\n', error: null,
        projectPath, entryFile: `${srcPath}/main.py` },
      { name: 'missing-file', source: "open('absent.txt')", stdin: '',
        exitCode: 1, output: '', error: 'ENOENT',
        projectPath, entryFile: `${srcPath}/main.py` },
      { name: 'outside-project', source: "open('../outside.txt', 'w')", stdin: '',
        exitCode: 1, output: '', error: 'EACCES',
        projectPath, entryFile: `${srcPath}/main.py` },
      { name: 'compile-only', source: "print('must not run')", stdin: '',
        exitCode: 0, output: '', error: null, compileOnly: true },
      { name: 'compile-error', source: 'def broken(:', stdin: '',
        exitCode: 1, output: '', error: 'SyntaxError', compileOnly: true },
    ];
    let passed = 0;
    for (const test of cases) {
      const actual = await runNative(test.source, test.stdin, 0,
        test.projectPath ?? '', test.entryFile ?? '', test.compileOnly ?? false);
      const outputOk = test.output === '' ? actual.output === '' : actual.output.includes(test.output);
      const errorOk = test.error === null ? actual.error === null
        : actual.error !== null && actual.error.includes(test.error);
      if (actual.exitCode === test.exitCode && outputOk && errorOk && !actual.truncated) {
        passed++;
      } else {
        hilog.error(LOG_DOMAIN, LOG_TAG,
          '原生自检失败 %{public}s exit=%{public}d stdout=%{public}s stderr=%{public}s',
          test.name, actual.exitCode, actual.output, actual.error ?? '');
      }
    }
    hilog.info(LOG_DOMAIN, LOG_TAG, '原生自检通过 %{public}d/%{public}d', passed, cases.length);

    // 受控执行自检：起一次无限循环，用 token 取消，必须拿到 130。
    // 这条只能在这里验——它同时覆盖「异步 worker 起来了」和「取消真的通了」。
    if (nativeRunControlReady()) {
      let id = '';
      try {
        id = prepareRun();
        const session = sessions.get(id);
        const running = runNative('while True: pass', '', 0, projectPath,
          `${srcPath}/main.py`, false, session?.token ?? 0);
        // 给 VM 一点时间真正开跑，再取消；不给的话可能取消在启动前生效，
        // 那测的就成了「预取消」而不是「运行中取消」。
        await new Promise<void>((resolve) => setTimeout(resolve, 300));
        cancelRun(id);
        const cancelled = await running;
        if (cancelled.exitCode === 130 && cancelled.error !== null
          && cancelled.error.includes('KeyboardInterrupt')) {
          hilog.info(LOG_DOMAIN, LOG_TAG, '取消自检通过：exit=130 KeyboardInterrupt');
        } else {
          hilog.error(LOG_DOMAIN, LOG_TAG,
            '取消自检失败 exit=%{public}d stderr=%{public}s',
            cancelled.exitCode, cancelled.error ?? '');
        }
      } catch (e) {
        const err = e as Error;
        hilog.error(LOG_DOMAIN, LOG_TAG, '取消自检异常：%{public}s', err.message);
      } finally {
        if (id !== '') {
          releaseRun(id);
        }
      }
    }

    // 字节码自检：编译出 .mpy，删掉源码，直接执行 .mpy。
    if (nativeRunControlReady()) {
      const artifact = `${srcPath}/main.mpy`;
      try {
        const compiled = await runNative(
          "print('mpy-ok')", '', 0, projectPath, `${srcPath}/main.py`,
          true, 0, artifact);
        if (compiled.exitCode !== 0) {
          hilog.error(LOG_DOMAIN, LOG_TAG,
            '编译自检失败 exit=%{public}d stderr=%{public}s',
            compiled.exitCode, compiled.error ?? '');
        } else if (!fs.accessSync(artifact)) {
          hilog.error(LOG_DOMAIN, LOG_TAG, '编译自检失败：未生成 .mpy');
        } else {
          const executed = await runNative('', '', 0, projectPath, artifact,
            false, 0, '', artifact);
          if (executed.exitCode === 0 && executed.output.includes('mpy-ok')) {
            hilog.info(LOG_DOMAIN, LOG_TAG, '字节码自检通过：%{public}s', executed.output);
          } else {
            hilog.error(LOG_DOMAIN, LOG_TAG,
              '字节码自检失败 exit=%{public}d stdout=%{public}s stderr=%{public}s',
              executed.exitCode, executed.output, executed.error ?? '');
          }
        }
      } catch (e) {
        const err = e as Error;
        hilog.error(LOG_DOMAIN, LOG_TAG, '字节码自检异常：%{public}s', err.message);
      }
    }

    // 参数校验自检：NUL 源码/输入/路径与非法 heapKb 必须在入队前被 NAPI 拒绝。
    // 这些是“看起来能跑、结果却是截断/错堆”的静默错误，真机上只有这里能统一验。
    if (nativeRunControlReady()) {
      const invalid: (string | number | boolean)[] = [];
      const expectRejected = async (label: string,
        attempt: () => Promise<PyRunOutcome>): Promise<void> => {
        let rejected = false;
        try {
          await attempt();
        } catch (e) {
          rejected = true;
        }
        if (rejected) {
          invalid.push(label);
        } else {
          hilog.error(LOG_DOMAIN, LOG_TAG, '参数校验自检失败：%{public}s 未被拒绝', label);
        }
      };
      await expectRejected('source-nul', () => runNative('print(1)\u0000print(2)', '',
        0, projectPath, `${srcPath}/main.py`));
      await expectRejected('stdin-nul', () => runNative('pass', 'a\u0000b',
        0, projectPath, `${srcPath}/main.py`));
      await expectRejected('entryfile-nul', () => runNative('pass', '',
        0, projectPath, `${srcPath}/main.py\u0000hidden`));
      await expectRejected('heap-negative', () => runNative('pass', '',
        -1, projectPath, `${srcPath}/main.py`));
      await expectRejected('heap-fraction', () => runNative('pass', '',
        0.5, projectPath, `${srcPath}/main.py`));
      await expectRejected('heap-overflow', () => runNative('pass', '',
        2147483648, projectPath, `${srcPath}/main.py`));
      // 校验失败不该污染后续执行：一次正常运球必须还能跑。
      const after = await runNative('print("valid-after")', '', 0, projectPath,
        `${srcPath}/main.py`);
      if (invalid.length === 6 && after.exitCode === 0
        && after.output.includes('valid-after')) {
        hilog.info(LOG_DOMAIN, LOG_TAG, '参数校验自检通过：6/6 拒绝且后续运行正常');
      } else {
        hilog.error(LOG_DOMAIN, LOG_TAG,
          '参数校验自检未全过 rejected=%{public}d exit=%{public}d',
          invalid.length, after.exitCode);
      }
    }
  } catch (e) {
    const err = e as Error;
    hilog.error(LOG_DOMAIN, LOG_TAG, '自检失败：%{public}s', err.message);
  }
}

/** 把原生执行后端注册到 Flutter 引擎上。 */
export function registerQfliPyNativeChannel(flutterEngine: FlutterEngine): void {
  selfCheck();

  const channel = new MethodChannel(
    flutterEngine.dartExecutor.getBinaryMessenger(),
    CHANNEL_NATIVE,
  );
  channel.setMethodCallHandler({
    onMethodCall(call: MethodCall, result: MethodResult): void {
      if (call.method === 'available') {
        // Dart 侧用它探测原生后端，并在不可用时把 detail 原样显示给用户。
        // 返回结构而不是裸 bool：只说「没有」没法排查，得说清楚「为什么没有」。
        const ready = nativeReady();
        const runControl = nativeRunControlReady();
        const probe: PyProbeResult = {
          available: ready,
          version: ready ? nativeVersion() : '',
          detail: ready ? '' : MODULE_MISSING_DETAIL,
          // 只有真的导出并接好了取消/字节码能力才报 true。旧 .so 仍然是
          // 可用的运行后端，只是要走旧的同步链路。
          runControl: runControl,
          bytecode: runControl,
        };
        result.success(probe);
        return;
      }
      if (call.method === 'prepareRun') {
        try {
          result.success(prepareRun());
        } catch (e) {
          result.error('QFLI_PY_NATIVE_ERROR', errorText(e as Object), null);
        }
        return;
      }
      if (call.method === 'cancel') {
        const runId = call.argument('runId') as string | undefined;
        result.success(runId !== undefined && runId !== null
          ? cancelRun(runId) : false);
        return;
      }
      if (call.method !== 'run' && call.method !== 'checkSyntax'
        && call.method !== 'compile') {
        result.notImplemented();
        return;
      }
      if (!nativeReady()) {
        // 通道在、模块没加载起来：这是一次**失败**，不是「这个构建里没有后端」。
        // 不能静默吞掉，否则用户看到的结果和设备真实行为对不上。
        result.error('QFLI_PY_MODULE_MISSING', MODULE_MISSING_DETAIL, null);
        return;
      }
      const source = (call.argument('source') as string) ?? '';
      const stdin = (call.argument('stdin') as string) ?? '';
      const heapKb = (call.argument('heapKb') as number) ?? DEFAULT_HEAP_KB;
      const projectPath = (call.argument('projectPath') as string) ?? '';
      const entryFile = (call.argument('entryFile') as string) ?? '';
      const compileOnly = call.method !== 'run';
      const artifactOutput = (call.argument('artifactOutput') as string) ?? '';
      const bytecodeFile = (call.argument('bytecodeFile') as string) ?? '';
      const runId = call.argument('runId') as string | undefined;

      // 取 token：有 runId 用登记过的那个，并在完成时释放；没有就用 0（不可取消）。
      let token = 0;
      let ownsSession = false;
      if (runId !== undefined && runId !== null) {
        const session = sessions.get(runId);
        if (session === undefined) {
          result.error('QFLI_PY_NATIVE_ERROR', '未知的 Python 运行句柄', null);
          return;
        }
        if (session.submitted) {
          result.error('QFLI_PY_NATIVE_ERROR', '这次 Python 运行已经提交过了', null);
          return;
        }
        session.submitted = true;
        token = session.token;
        ownsSession = true;
      }

      runNative(source, stdin, heapKb, projectPath, entryFile, compileOnly,
        token, artifactOutput, bytecodeFile)
        .then((outcome: PyRunOutcome) => {
          if (ownsSession) {
            releaseRun(runId as string);
          }
          // ArkTS 结构体带 nullable 字段；转成 Dart 侧期待的 Map。
          result.success({
            'exitCode': outcome.exitCode,
            'output': outcome.output,
            'error': outcome.error,
            'truncated': outcome.truncated,
          });
        })
        .catch((error: Object) => {
          if (ownsSession) {
            releaseRun(runId as string);
          }
          const detail = errorText(error);
          result.error('QFLI_PY_NATIVE_ERROR', detail, null);
        });
    },
  });
}
