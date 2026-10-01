# 原生执行后端（内嵌 MicroPython）

Python 版 App 的执行后端。**引擎是上游 MicroPython 1.24.1（commit `ecfdd5d`），
不是手写的解释器。**

```
Dart → MethodChannel('qfli_py/native') → Kotlin/JNI 或 ArkTS/NAPI → libqfli_py.so → MicroPython
```

Windows/Linux 和 iOS/macOS 使用同一引擎的本地 FFI 插件。打包、调用路径和
实际验证结果见 [Native Python Platforms](PLATFORMS.md)。

## Android

Android 与鸿蒙使用同一份 C VM、bridge、HAL、标准流和项目文件接口。
`native/android/CMakeLists.txt` 从已跟踪的 `micropython_embed` 编译，JNI 是
独立平台适配，NDK 构建不会写回共享生成目录。

```powershell
flutter build apk --debug
adb -s emulator-5556 install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5556 shell am start -n com.azurekiln.qfli.pyflow/.MainActivity
adb -s emulator-5556 logcat -d -s QfliPyNative
```

- NDK 固定为 `27.0.12077973`，CMake 为 `3.22.1`，构建目标包括
  `armeabi-v7a`、`arm64-v8a` 和 `x86_64`，使用静态 C++ 和 16 KiB ELF 页对齐。
- Kotlin 注册相同的 `available/run/checkSyntax` 协议。编译和执行在一个
  1 MiB 栈的后台线程上串行运行，结果回到主线程。C 层仍保留 mutex。
- JNI 用 UTF-8 字节数组传递源码、输入、路径和输出，不使用 JNI modified UTF-8。
  非 BMP 字符可以往返；传入参数包含实际 NUL 时明确拒绝。
- debug 启动执行真实 JNI 自检，profile/release 使用空实现。
  `@Keep` 保留 JNI 所需的类名、方法名和结果构造函数。
- `input()`、`sys.stdin` 和 `sys.stdin.buffer` 消费同一段有限输入。
  `input()` 耗尽时抛 `EOFError`；标准流读取返回空文本或空字节。
  `sys.stderr` 进入结果的 `error` 字段，即使程序正常以 0 退出。
- 超出 VM 整数范围的 `sys.exit()` 返回退出码 1 和 `OverflowError`，下一次运行仍可继续。

2026-10-01 的 Android 17 x86_64 模拟器已从编辑器执行多文件项目，读取
`input.txt`，写入并读回项目文件，输出 `ANDROID_PROJECT_OK android Ada:42`
并以 0 退出。当前最终验证结果见任务记录。

最终 debug 自检 **36/36**，主机 C VM **65/65**，Flutter **25/25**，静态分析通过。
debug/release APK 和 x86_64 profile APK 均构建成功，release 安装后运行与语法检查
也通过。两个完整 APK 均通过 16 KiB ZIP 对齐检查，release 中全部 ELF 库满足
至少 16 KiB 的 LOAD 段对齐。发布签名仍使用项目现有的 debug key 配置。

## 为什么是 MicroPython

一开始的设想是「应用内纯 Dart Python 子集解释器」，写了一半被否掉了，理由是兼容性：
手写一个子集要自己扛浮点语义、异常层次、生成器、f-string、迭代协议、描述符、
`__slots__`……每一项都是坑，而且「能跑一部分语法、细节上却跟真 Python 不一致」
对学习者是负价值。

MicroPython 自带完整的编译器 + 字节码 VM，语义跟 CPython 对得上，官方也提供了
`ports/embed` 这条**专门给宿主项目内嵌**的路线。所以选它。

这也回答了「为什么不能 exec 一个 python」：鸿蒙的普通应用被 SELinux 挡在 `exec` 之外，
既调不动设备上的解释器，也拉不起打包进 HAP 的可执行文件（HNP 那条路要求应用具备
生产力应用资格）。但沙箱从来不限制应用解释自己的数据——把源码交给**进程内**的 VM，
是普通应用唯一走得通的路。

### 怎么确认跑的是真的 MicroPython

`libqfli_py.so` 导出 `version()`，返回的字符串直接取自 MicroPython 自己的头文件
（`py/mpconfig.h` 的 `MICROPY_VERSION_STRING` + `genhdr/mpversion.h` 的
`MICROPY_GIT_HASH`），不是我们写的常量。App 里两个地方能看到它：

- 运行面板的标题：`运行 main.py（MicroPython 1.24.1 (ecfdd5d)）`
- App 启动时的 hilog 自检（见下）

**不想信上面的说法就自己验**（不用装任何东西，Python 标准库就够）：

```powershell
python native\tools\inspect_so.py
```

它直接扫 `.so` 的字节，输出版本字符串、上游特征符号、动态依赖、未定义的 C++ 符号：

```
[2] 引擎身份（直接扫文件里的字符串，不是读配置）
    OK  版本号 1.24.1           命中 2 处
    OK  git hash ecfdd5d     命中 1 处
[3] 上游 MicroPython 特征符号
    OK  mp_hal_stdout_tx_strn
    OK  mp_execute_bytecode
    OK  nlr_push
...
结论：通过。依赖全是设备上一定有的系统库，引擎是上游 MicroPython。
```

`mp_execute_bytecode` / `nlr_push` 这些是 MicroPython 的字节码 VM 和异常展开器
自己的符号——手写的解释器不会有这些名字。

## 为什么需要 ArkTS 那一层

Flutter 的 Dart 代码不能直接调 NAPI，链路上必须有一个 ArkTS 环节。而 ArkTS 的
`import 'libqfli_py.so'` 是**构建期解析**的——`.so` 不在位，整个 App 直接编不过。

但反过来不成立：**编得过 ≠ 跑得起来**。见下面那节。

## ⚠️ 最大的一个坑：.so 的动态依赖

`.so` 是我们自己用 CMake 编的，**绕过了 hvigor 的 CMake 集成**。hvigor 只负责把
`ohos/entry/libs/<abi>/` 下的文件原样打进 HAP，它既不知道也不需要知道这个 `.so`
依赖了什么——**没有任何一步会去补齐它的依赖**。

所以只要链接时带上了一个非系统库，就会在真机上炸，而编译期一切正常：

```
W MUSL-LDSO: load libc++_shared.so failed, namespace=ndk no inherits, errno=2
W MUSL-LDSO: load libc++_shared.so failed, namespace=moduleNs_default, errno=2
W MUSL-LDSO: Error loading shared library libc++_shared.so:
             (needed by /data/storage/el1/bundle/libs/arm64/libqfli_py.so)
W MMG: [NMM:1439]key:default/qfli_py First: failed ... load module default/qfli_py failed
E ArkCompiler: [ecmascript] export objects of native so is undefined,
               so name is @app:com.azurekiln.qfli.pyflow/entry/qfli_py
```

最后一条的直接后果：ArkTS 里 `import qfliPyNative from 'libqfli_py.so'` 拿到
`undefined`，运行时报 **`Cannot read property run of undefined`**（退出码 1）。
从这条报错反推到「少了个 `.so`」非常费时间。

注意 `libc++_shared.so` **在设备上是存在的**（`/system/lib64/`），只是不在应用的
linker namespace 里，照样 errno=2。所以「设备上有这个库」不能作为依据。

**两道防线，现在都不会再漏：**

1. `CMakeLists.txt` 里 `target_link_libraries(qfli_py PUBLIC -static-libstdc++)`，
   等价于工具链的 `OHOS_STL=c++_static`（不能用 `-DOHOS_STL=c++_static` 代替：
   `ohos.toolchain.cmake` 里是 `set(OHOS_STL c++_shared)`，普通变量会盖住命令行
   传进来的同名缓存变量）。C++ 标准库静态链进来，`DT_NEEDED` 里就没有它了。
2. `tools/check_so_deps.py` 在**每次链接后**（CMake `POST_BUILD`）校验一遍
   `DT_NEEDED`，出现「HAP 里不会带的库」直接让构建失败。它用纯 Python 解析 ELF，
   不依赖 `llvm-readelf`。

## 目录

| 路径 | 作用 |
| --- | --- |
| `build.ps1` | **一键构建**：找工具链 → 配置 → 编译 → 校验依赖 → 拷进 `ohos/entry/libs/` |
| `CMakeLists.txt` | 构建 `libqfli_py.so`（两段式：先生成源码包，再编译） |
| `tools/build_embed.py` | 把 MicroPython 源码加工成自包含的 `micropython_embed/` 包 |
| `tools/check_so_deps.py` | 校验 `.so` 的动态依赖（纯 Python 解析 ELF，**构建期**守门） |
| `tools/inspect_so.py` | 事后复查：动态依赖 + 引擎身份 + 未定义 C++ 符号（**随时可跑**，见上） |
| `port/mpconfigport.h` | MicroPython 的 port 配置（特性档位、浮点、模块开关） |
| `port/mphalport.h` | port HAL 头：`input()` 的 `mp_hal_readline` 钩子 |
| `src/qfli_py_stdio.c` | 有限 stdin、分离 stdout/stderr 的标准流适配 |
| `src/qfli_py_jni.cpp` | Android JNI 接线，复用 C bridge |
| `android/CMakeLists.txt` | Android NDK 构建，复用共享源码 |
| `port/qstrdefsport.h` | port 自己的 qstr 定义（包括文件对象需要的名称） |
| `port/qfli_time_localtime.c` | `time.localtime()` 的 port 钩子（**不是独立编译单元**） |
| `src/qfli_py_bridge.h` / `.c` | VM 生命周期 + 执行一次 + `qfli_py_version()`（纯 C，无平台依赖） |
| `src/qfli_py_hal.h` / `.c` | 输出捕获与标准输入（含 `sys.stdout` 走的 `mp_hal_*`） |
| `src/qfli_py_file.h` / `.c` | 项目文件流、路径解析及每次运行后的文件描述符清理 |
| `tests/run_host.sh` / `smoke.c` | 使用相同 C 桥接与 MicroPython 源码的 Linux 主机测试 |
| `src/qfli_py_napi.cpp` | NAPI 外壳，把 `run()` / `version()` 暴露给 ArkTS |
| `ohos/QfliPyNative.ets` | ArkTS 接线模板（复制到 `ohos/entry/...` 才进构建） |
| `third_party/micropython/` | 上游源码（首次运行 `build.ps1` 自动拉取并核对版本） |
| `micropython_embed/` | 自包含源码包（由构建脚本再生成） |

## 构建 .so

```powershell
& .\native\build.ps1
```

它会自动找 DevEco Studio / NDK / 宿主 Python（DevEco 自带的那个），
在缺少上游源码时拉取固定的 MicroPython 1.24.1（`ecfdd5d`），然后：

1. 配置 CMake 到 `native/build/cmake-arm64-v8a/`
2. 编译 `libqfli_py.so`（第一次要编一百多个 MicroPython 源文件，约一两分钟）
3. 校验动态依赖
4. 拷到 `ohos/entry/libs/arm64-v8a/libqfli_py.so`

每一步的完整日志落在 `native/build/cmake-arm64-v8a/` 下的
`configure.log` / `build.log` / `check_so_deps.log`，失败时脚本会打印尾部。

常用参数：`-BuildType Debug`（带符号表，排查原生崩溃用）、`-Abi x86_64`（模拟器）、
`-Clean`（重建）、`-SkipCopy`（只编译）、`-DevEcoHome` / `-Python`（路径不对时手动指）。

### 为什么不用上游的 `make`

本机**没有 `make`**，所以不走上游 `ports/embed/embed.mk`；`py/mkrules.cmake` 也不行
（它用 `cat`/`sed`/`touch`/管道/重定向，Ninja 在 Windows 上交给 cmd.exe 执行，一个都没有）。
`tools/build_embed.py` 用 Python 把同一套规则重做了一遍，由 CMake 在**配置期**调用
（改了 `port/*.h` 或 `tools/*.py` 时会自动重跑），也可以手动跑 `qfli_py_regen` 目标。

> `NATIVERENDER_ROOT_PATH` 不传也没关系：CMake 会丢掉空项，而 `napi/native_api.h`
> 是从 `--sysroot` 里的 `<ndk>/sysroot/usr/include/napi/` 找到的。

## 启用（两步，第一步 build.ps1 已经做了）

```bash
# 1. libqfli_py.so 已经在 ohos/entry/libs/arm64-v8a/ 下（build.ps1 拷的）

# 2. ArkTS 接线（已经接好了；换机器/新克隆时按这个做）
#    cp native/ohos/QfliPyNative.ets ohos/entry/src/main/ets/plugins/QfliPyNative.ets
#    然后在 EntryAbility.ets 的 configureFlutterEngine 里加：
#      import { registerQfliPyNativeChannel } from '../plugins/QfliPyNative';
#      registerQfliPyNativeChannel(flutterEngine)
```

**不需要**改 `oh-package.json5`。`ohos/entry/libs/<abi>/` 就是模块的 native 库目录，
hvigor 会自动打包（实测 `libs/arm64-v8a/libqfli_py.so` 出现在 HAP 里）。
Flutter 插件拷 `libapp.so` 用的也是这个目录。

打包时注意 DevEco 里 **Open 的必须是 `ohos`**。

完整 App 构建还需要鸿蒙版 Flutter SDK、相邻目录中的 `qfli_studio_core`
（见 `pubspec.yaml` 的 path 依赖），以及本机有效的签名配置。这些不是原生
MicroPython 源码的一部分。仓库根目录运行 `flutter pub get` 后，从 `ohos` 打包：

```powershell
hvigorw.bat assembleHap --mode module -p product=default --no-daemon
```

产物为 `ohos/entry/build/default/outputs/default/entry-default-signed.hap`。

## 项目运行与文件操作

- 入口源码仍由 Dart 读取；模块导入使用上游 POSIX reader。
- `sys.path` 依次包含入口所在目录和项目根目录；`sys.argv[0]`、`__file__`
  与 traceback 使用真实入口路径。每次运行重新建立 VM 状态和模块缓存。
- `open(file, mode='r')` 与 `io.open` 使用项目根目录解析相对路径；支持
  `r/w/a/x`、`+`、文本和二进制模式、上下文管理器、文件迭代、
  `read/readline/readlines/readinto/write/seek/tell/flush/close`。
- `open` 的路径经过 `realpath` 检查。现有目标或新文件的父目录超出项目
  时返回 `EACCES`；不存在的读取目标返回 `ENOENT`；独占创建已存在文件
  返回 `EEXIST`；关闭后读写返回 `EBADF`。运行结束后关闭所有遗留描述符。
- 文件流不提供 CPython 的 `encoding/errors/newline` 参数。目录操作、
  `os`、网络和 CPython 扩展包不在当前端口能力内。
- 文件路径检查只适用于本端口的 `open`；模块导入沿用上游 POSIX reader，
  不构成对不可信 Python 代码的隔离环境。

工具页使用真实本地项目和 `.py` 文件列表，提供语法检查与运行。
`checkSyntax` 和 `run` 使用同一条原生链路，前者只调用上游解析器及编译器，
不执行字节码，也不导入模块或验证导入目标。脚本编译使用
`mp_compile(..., false)`，顶层表达式不会像 REPL 一样自动打印。

## 主机原生测试

Linux 环境需要 GCC、标准 C 库、pthread 和 `/proc/self/fd`：

```sh
sh native/tests/run_host.sh
```

Windows 可使用已安装的 WSL 发行版，例如本机：

```powershell
wsl.exe -d qfli-java-build --exec sh /mnt/d/MyNewProjects/qfli_python/native/tests/run_host.sh
```

脚本使用仓库中的 `micropython_embed` 和 C 桥接构建测试程序，不使用
Dart mock。覆盖模块刷新、文件流与路径失败、仅编译时没有文件副作用，
以及成功和异常运行后的描述符清理；主机通过不能替代设备打包验证。

## 怎么确认后端通了

App 启动时（`registerQfliPyNativeChannel` 里）会执行一组原生用例，写进 hilog：

```powershell
hdc shell hilog -z 5000 -T QfliPyNative
```

- 通了：能看到 `libqfli_py.so 已加载，MicroPython 1.24.1 (ecfdd5d)`，
  以及 `原生自检通过 17/17`。这些用例在真机上经过 ArkTS/NAPI 调用 C VM，
  覆盖编译执行、语法错误、运行异常、输入、退出码、内置模块、多次运行隔离、
  入口路径、真实 `.py` 模块和包导入、项目文本/二进制读写与追加、路径失败，
  以及仅编译的成功和错误。17/17 是当前构建的预期结果，设备验证状态见下。
- 没通：会看到 `libqfli_py.so 未加载：...`，里面写了原因和下一步
- 依赖又出问题：`hdc shell hilog -x | Select-String MUSL-LDSO`

## 实测过的证据（2026-09-20）

### 2026-09-20 修复版 `libqfli_py.so`（历史产物）

`tools/inspect_so.py` 的完整输出：

| 检查 | 结果 |
| --- | --- |
| 大小 | 2,494,776 字节（静态链进 libstdc++ 之后变大，属预期） |
| SHA256 | `7FC8B8426292F53C72CA849F1FB87B78BC6C011444C78D3D28C9647DFC74B632` |
| `DT_NEEDED` | 只有 `libace_napi.z.so` / `libhilog_ndk.z.so` / `libc.so`，**非系统库 0 个** |
| 未定义 C++ 符号 | **0 个**（`.dynsym` 里 `SHN_UNDEF` 且 `_Z` 开头的） |
| 引擎身份 | 文件里搜到 `1.24.1`、`ecfdd5d`、`MicroPython` |
| 上游符号 | `mp_hal_stdout_tx_strn` / `mp_lexer_new_from_str_len` / `mp_execute_bytecode` / `nlr_push` / `gc_alloc` 全在 |
| 我们的导出 | `qfli_py_run` / `qfli_py_result_free` / `qfli_py_version` / `RegisterQfliPyNativeModule` 全在 |
| 模块名 | 与 ArkTS 请求的一致：设备日志 `key:default/qfli_py` |
| 模块注册 | `.init_array` 里确有 `R_AARCH64_ABS64 → RegisterQfliPyNativeModule` |
| 构建 | `build.ps1` 一次跑通，`check_so_deps.py` 在 POST_BUILD 通过 |

### 上一版（有 `libc++_shared.so` 的那版，仅作对照）

| 检查 | 结果 |
| --- | --- |
| hvigor 构建 | `BUILD SUCCESSFUL`，`CompileArkTS` 通过 |
| 签名 | `SignHap` 完成，产出 `entry-default-signed.hap` |
| 打包 | HAP 里有 `libs/arm64-v8a/libqfli_py.so`（464 KB，被 `DoNativeStrip` 剥过符号表） |
| 安装 | 设备上 `/data/storage/el1/bundle/libs/arm64/libqfli_py.so` 在位 |
| **运行** | **失败**：`MUSL-LDSO` → `import` 拿到 `undefined` → `Cannot read property run of undefined` |

这两张表放在一起正好说明那节标题的意思：**编得过、签得出、装得上，全都不能保证跑得起来。**

> **装的时候认准 `entry-default-signed.hap`。** 同目录下还有一个
> `entry-default-unsigned.hap`（上一次未签名的残留），装它会报
> `code:9568320 error: no signature file`。

2026-09-30 的已安装版本先后通过 7/7、10/10、14/14 原生自检。
加入追加文件与语法检查后的版本生成了签名 HAP，最新版本的 17/17 尚未验证。
2026-10-01 曾编译鸿蒙 x86_64 原生库并打包 HAP，随后用户要求停止鸿蒙调试。
当前共享标准流与退出码修复由主机 C VM 和 Android 验证；尚未重新打包到鸿蒙 HAP。

## 已知限制

- **交互式 stdin 不支持。** 模型是「先跑完再输出」，`input()` 从一次性喂进去的
  缓冲区里按行取。约定：项目根目录放 `input.txt`。要做真交互得把执行改成
  可挂起/可恢复的状态机。
- **C VM 运行同步且没有中断接口。** Android 在后台线程执行。无限循环会阻塞当前执行；标准输入来自
  `input.txt`，输出在本次运行结束后返回。
- **引擎是 MicroPython，不是 CPython。** 支持项目 `.py` 模块和当前启用的
  内置模块，不提供 pip、CPython C 扩展或完整标准库。
- **终端结果是 NUL 结尾的 UTF-8 文本。** 标准流的 `.buffer` 可用，但任意二进制
  输出中的 NUL 无法完整往返；二进制数据应写入项目文件。
- **Android ABI** 为 `armeabi-v7a`、`arm64-v8a`、`x86_64`；当前鸿蒙分发仍以
  `arm64-v8a` 为主，`native/build.ps1 -Abi x86_64` 可编译模拟器原生库。

## 维护注意

改这几处时容易漏掉另一半，都是**会静默出错**或**报错指向别处**的类型：

1. **`EXTMOD_MODULES` 里加模块** → 三件事要同时成立：`.c` 进包、`.c` 进 qstr 扫描列表、
   `mpconfigport.h` 里对应的 `MICROPY_PY_XXX` 打开。缺了只会在运行时
   `ModuleNotFoundError`。`REQUIRED_MODULES` 会替你挡住常见的漏。
2. **`CMakeLists.txt` 的排除列表** → `lib/re1.5/*.c` 和 `port/qfli_time_localtime.c`
   是「只被文本包含、不单独编译」的文件，从 glob 里排除了。新增这类文件要一起加。
3. **`CMakeLists.txt` 的 `-static-libstdc++` 不能删。** 删掉就回到上面那个
   `libc++_shared.so` 的坑，而且只有真机才炸。`check_so_deps.py` 会挡住，
   但如果连它一起删了就没人管了。
4. **`native/ohos/QfliPyNative.ets` 和 `ohos/entry/src/main/ets/plugins/QfliPyNative.ets`
   是两份逐字节相同的副本**，改逻辑要一起改。前者不在构建路径里，**漂了不会有任何
   编译错误或测试失败**，所以只能靠哈希查：

   ```powershell
   Get-FileHash native\ohos\QfliPyNative.ets,
     ohos\entry\src\main\ets\plugins\QfliPyNative.ets -Algorithm SHA256
   ```

   两份必须一致（复制即可，不用手改）。通道协议（`available` 返回
   `{available, version, detail}`）两边不一致时，`python_runner.dart` 里有兼容分支
   兜底，但那只是兜底，不是可以不管。
5. **`python_runner.dart` 的 `heapKb`** 要和 `qfli_py_bridge.c` 的
   `QFLI_PY_DEFAULT_HEAP_KB` 保持一致。
6. **终端里 App 自己的诊断行都带 `[qfli] ` 前缀**（见 `python_runner.dart` 的
   `_appPrefix`）。不加前缀的话，后端没跑起来时满屏中文提示会被误认成
   「Python 输出是中文」。新增诊断行要沿用这个前缀。

生成器里写了几处**主动校验**（`_verify_modules` / `_verify_qstrs`），因为它们对应的
失败都是静默的。踩过的坑：`MICROPY_FLOAT_IMPL` 没设 → `import math` 直接不存在；
qstr 表丢了 95% → 生成的表里仍有 165 条静态 qstr，看起来「有内容」。
详见 `tools/build_embed.py` 和 `port/` 下各文件的注释。
