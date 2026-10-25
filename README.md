# QFLIPyFlow（qfli_python）

[简体中文](README.md) | [繁體中文](README.zh-TW.md) | [English](README.en.md)

QFLIPyFlow 是一个 Python 集成开发环境。它面向手机与桌面。应用用内嵌的 MicroPython 引擎运行 Python 代码。应用完全离线。引擎不是 CPython。应用不提供 pip。

本仓库是独立 Git 仓库。运行前请把 `qfli_studio_core` 检出到相邻目录。

```text
checkout-parent/
  qfli_studio_core/
  qfli_python/
```

在本目录运行 `flutter pub get`。再对目标设备运行 `flutter run`。共享编辑器补丁由 `../qfli_studio_core/vendor/re_editor` 提供。

## 功能

- 项目与文件选择。基于真实的本地项目。
- 语法检查。只编译。不运行。不写磁盘。
- 编译为 `.mpy`。把字节码写到入口旁边。
- 运行与停止。显示真实的标准输出、标准错误与退出码。
- 编辑器诊断。分析未保存的缓冲区。
- 模块目录。列出内置模块与随包模块。
- 本地包管理。从本地源码安装和删除项目包。
- 内置终端。`python`、`python3` 与 `micropython` 指向同一个引擎。
- 调试会话。源码已实现。验证状态见下文。

## 引擎

引擎是上游 MicroPython 1.24.1（commit `ecfdd5d`）。它自带完整编译器与字节码 VM。移植层只适配文件、标准流、时钟、锁与生命周期。移植层没有手写解释器。

```text
Dart → MethodChannel('qfli_py/native') → Kotlin/JNI 或 ArkTS/NAPI → libqfli_py.so → MicroPython
```

Windows、Linux、iOS 与 macOS 走本地 FFI 插件。这些平台共用同一份 C 引擎。

## 平台与验证状态

| 平台 | 传输层 | 源码 | 验证 |
| --- | --- | --- | --- |
| Android | Kotlin/JNI | 已实现 | 历史主机与模拟器验证 |
| 鸿蒙 OHOS | ArkTS/NAPI | 已实现 | 验收未完成 |
| Windows | FFI | 已实现 | 历史原生用例验证 |
| Linux | FFI | 已实现 | 历史 C ABI 验证 |
| iOS 与 macOS | FFI | 已实现 | 未验证 |

表内历史验证来自较早的构建。当前源码的最终套件尚未重跑。

Android 与鸿蒙共用 VM、项目导入、文件 I/O 与只编译语法检查。

Android：`libqfli_py.so` 覆盖 `armeabi-v7a`、`arm64-v8a` 与 `x86_64`。ELF 段按 16 KiB 对齐。debug 启动运行 46 个真实 JNI 自检。2026-10-01 的 x86_64 模拟器运行了一个多文件项目。项目读取了 `input.txt`，写入了项目文件，输出 `ANDROID_PROJECT_OK android Ada:42`，退出码 0。该批次的 release APK 也通过安装后的运行与语法检查。

鸿蒙：ArkTS/NAPI 转接与共享 C 引擎已实现。10-22 的模块 HAP 已构建。该 HAP 早于当前 FFI。共享标准流与退出码修正已在主机 C VM 与 Android 上验证。当前源码的最终 HAP 与设备验收尚未完成。

Windows 与 Linux：Windows FFI 冒烟测试通过 34/34 个真实原生用例。Linux C ABI 通过 65/65 个用例，含文件效果与资源清理。Linux 的完整 Flutter 图形界面尚未构建。

iOS 与 macOS：本机没有 Apple 主机与 Xcode。源集成、pod 构建与链接选项未验证。

## 离线策略

应用声明 `isOffline: true`。当前跟踪的 `ohos/entry/src/main/module.json5` 不申请 `ohos.permission.INTERNET`。鸿蒙 `EntryAbility.ets` 设 `OFFLINE_ONLY = true`。它拒绝 `openAgreement`、`openUrl` 与华为账号 `login`。拒绝发生在建立远程服务之前。本机启动进度、文件选择与文字分享仍然可用。

注意签名产物与源码的差别。2026-10-15 的签名 HAP 曾包含 `ohos.permission.INTERNET`。该 HAP 早于离线政策修正。安装新 HAP 后要重新检查权限清单。

主机行为证据由 `node tool/test_python_offline_platform.cjs` 提供。该脚本用平台替身调用真实 EntryAbility 处理器。它不是设备验收。

## 限制

- 引擎是 MicroPython。它不是 CPython。
- 不支持 pip、CPython C 扩展与完整标准库。
- 标准输入来自项目根目录的 `input.txt`。没有交互式标准输入。
- 输出在本次运行结束后返回。无限循环会占住运行通道。
- 取消在 VM 循环和受支持的睡眠中生效。阻塞式原生 I/O 不可中断。
- 终端只运行项目内的 `.py` 与 `.mpy` 脚本。它拒绝 `-m`、`-c`、解译器选项与多余参数。它没有交互式 REPL。
- `.mpy` 是字节码文件。它不是独立程序，也不是 CPython 的 `.pyc`。

## 随包模块与内置模块

随包提供 10 个模块：base64、bisect、contextlib、copy、csv、functools、itertools、statistics、string、textwrap。每个模块的来源、许可证与 SHA256 摘要记录在 `assets/python_stdlib/PROVENANCE.md` 和 `assets/python_stdlib/manifest.json`。

内置模块共 17 个：sys、math、cmath、json、random、time、re、binascii、heapq、array、collections、struct、io、errno、micropython、gc、builtins。

这些清单只描述已测试的范围。清单不承诺 CPython 兼容。

## 本地包

本地包操作只接受本机的 `.py`、目录、`.zip` 与纯源码 `.whl`。不支持下载、构建钩子与原生扩展。安装前逐文件做编译检查。事务失败会回滚。文件数上限 4096。单文件上限 2 MiB。源码总量上限 16 MiB。

## 调试会话

源码提供 `PythonDebugger`。它使用真实 MicroPython 会话。它支持断点、步入、步过、步出、进入时停止、调用栈与变量。它要求文件已保存。它不接受未保存的源码快照。调试源必须是项目内的 `.py` 文件。普通运行仍承担跟踪开销。当前性能验证尚未完成。

调试的设备验收尚未完成。

## 构建

Android：

```powershell
flutter build apk --debug
adb -s emulator-5556 install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5556 shell am start -n com.azurekiln.qfli.pyflow/.MainActivity
```

Android 需要 NDK `27.0.12077973`。应用在 `android/app/build.gradle.kts` 固定该版本。debug APK 位于 `build/app/outputs/flutter-apk/app-debug.apk`。请用 `adb devices` 报告的真实设备号替换示例号。

鸿蒙 HAP：

```powershell
flutter build hap --release --target-platform ohos-arm64
```

签名 HAP 为 `build/ohos/hap/entry-default-signed.hap`。`ohos/entry/build-profile.json5` 只编译 `arm64-v8a`。打包排除 x86_64 与 32 位 ARM 库。

原生库：

以下命令构建鸿蒙 `libqfli_py.so`。

```powershell
& .\native\build.ps1
```

脚本查找工具链。脚本在缺少源码时拉取固定的 MicroPython 1.24.1。脚本编译 `libqfli_py.so`。脚本检查动态依赖。脚本拷入 `ohos/entry/libs/`。

Windows 桌面：

```powershell
./native/desktop/build.ps1 -Compiler <gcc.exe> -CMake <cmake.exe> -Ninja <ninja.exe>
```

`native/desktop/build.ps1` 只构建 Windows DLL。

Linux 与 macOS：

```sh
sh native/desktop/build.sh
```

`native/desktop/build.sh` 调用 CMake 配置 `native/desktop`。构建目标为 `qfli_py_ffi`。`native/linux/CMakeLists.txt` 引用同一份 `native/desktop`。

## 测试与验证命令

```powershell
flutter analyze --no-pub
flutter test --no-pub
dart --packages=.dart_tool/package_config.json tool/python_ffi_smoke.dart native/build/windows/qfli_py_ffi.dll
python tool/verify_python_modules.py
node tool/test_python_offline_platform.cjs
python native/tools/inspect_so.py
```

`sh native/tests/run_host.sh` 在 POSIX 环境运行主机 C 测试。主机结果不替代设备验收。

设备自检日志：

```powershell
adb -s emulator-5556 logcat -d -s QfliPyNative
hdc shell hilog -z 5000 -T QfliPyNative
```

## 目录

| 路径 | 作用 |
| --- | --- |
| `lib/main.dart` | Python 档位、终端挂钩与入口 |
| `lib/app_startup.dart` | 启动引导与首帧交接 |
| `lib/python_tools_page.dart` | 项目与文件工具、操作状态 |
| `lib/python_runner.dart` | 运行适配与结果类型 |
| `lib/python_ffi.dart` | 原生绑定与工作 isolate |
| `lib/python_packages.dart` | 本地包事务 |
| `lib/python_code_analyzer.dart` | 未保存缓冲区的诊断 |
| `lib/python_debugger.dart` | 真实 MicroPython 调试会话 |
| `native/` | 内嵌 MicroPython、移植层与平台转接 |
| `assets/python_stdlib/` | 随包模块与来源记录 |
| `test/` | 档位、工具、启动与原生边界回归 |

## 更多文档

- `native/README.md`：原生后端细节与维护注意。
- `native/PLATFORMS.md`：平台构建与实测证据。
- `native/lifecycle.md`：取消、字节码与所有权。
- `.trellis/spec/`：编码契约与验证指引。
