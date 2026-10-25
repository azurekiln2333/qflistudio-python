# QFLIPyFlow（qfli_python）

[簡體中文](README.md) | [繁體中文](README.zh-TW.md) | [English](README.en.md)

QFLIPyFlow 是一個 Python 整合開發環境。它面向手機與桌面。應用程式用內嵌的 MicroPython 引擎執行 Python 程式碼。應用程式完全離線。引擎不是 CPython。應用程式不提供 pip。

本儲存庫是獨立 Git 儲存庫。執行前請把 `qfli_studio_core` 檢出到相鄰目錄。

```text
checkout-parent/
  qfli_studio_core/
  qfli_python/
```

在本目錄執行 `flutter pub get`。再對目標裝置執行 `flutter run`。共享編輯器補丁由 `../qfli_studio_core/vendor/re_editor` 提供。

## 功能

- 專案與檔案選擇。基於真實的本機專案。
- 語法檢查。只編譯。不執行。不寫磁碟。
- 編譯為 `.mpy`。把位元組碼寫到進入點旁邊。
- 執行與停止。顯示真實的標準輸出、標準錯誤與結束碼。
- 編輯器診斷。分析未儲存的緩衝區。
- 模組目錄。列出內建模組與隨包模組。
- 本機套件管理。從本機原始碼安裝和刪除專案套件。
- 內建終端機。`python`、`python3` 與 `micropython` 指向同一個引擎。
- 除錯工作階段。原始碼已實作。驗證狀態見下文。

## 引擎

引擎是上游 MicroPython 1.24.1（commit `ecfdd5d`）。它自帶完整編譯器與位元組碼 VM。移植層只轉接檔案、標準串流、時鐘、鎖與生命週期。移植層沒有手寫解譯器。

```text
Dart → MethodChannel('qfli_py/native') → Kotlin/JNI 或 ArkTS/NAPI → libqfli_py.so → MicroPython
```

Windows、Linux、iOS 與 macOS 走本機 FFI 外掛。這些平台共用同一份 C 引擎。

## 平台與驗證狀態

| 平台 | 傳輸層 | 原始碼 | 驗證 |
| --- | --- | --- | --- |
| Android | Kotlin/JNI | 已實作 | 歷史主機與模擬器驗證 |
| 鴻蒙 OHOS | ArkTS/NAPI | 已實作 | 驗收未完成 |
| Windows | FFI | 已實作 | 歷史原生案例驗證 |
| Linux | FFI | 已實作 | 歷史 C ABI 驗證 |
| iOS 與 macOS | FFI | 已實作 | 未驗證 |

表內歷史驗證來自較早的建置。目前原始碼的最終套件尚未重跑。

Android 與鴻蒙共用 VM、專案匯入、檔案 I/O 與只編譯語法檢查。

Android：`libqfli_py.so` 涵蓋 `armeabi-v7a`、`arm64-v8a` 與 `x86_64`。ELF 段按 16 KiB 對齊。偵錯啟動執行 46 個真實 JNI 自檢。2026-10-01 的 x86_64 模擬器執行了一個多檔案專案。專案讀取了 `input.txt`，寫入了專案檔案，輸出 `ANDROID_PROJECT_OK android Ada:42`，結束碼 0。該批次的 release APK 也通過安裝後的執行與語法檢查。

鴻蒙：ArkTS/NAPI 轉接與共享 C 引擎已實作。10-22 的模組 HAP 已建置。該 HAP 早於目前 FFI。共享標準串流與結束碼修正已在主機 C VM 與 Android 上驗證。目前原始碼的最終 HAP 與裝置驗收尚未完成。

Windows 與 Linux：Windows FFI 冒煙測試通過 34/34 個真實原生案例。Linux C ABI 通過 65/65 個案例，涵蓋檔案效果與資源清理。Linux 的完整 Flutter 圖形介面尚未建置。

iOS 與 macOS：本機沒有 Apple 主機與 Xcode。原始碼整合、pod 建置與連結選項未驗證。

## 離線政策

應用程式宣告 `isOffline: true`。目前追蹤的 `ohos/entry/src/main/module.json5` 不申請 `ohos.permission.INTERNET`。鴻蒙 `EntryAbility.ets` 設 `OFFLINE_ONLY = true`。它拒絕 `openAgreement`、`openUrl` 與華為帳號 `login`。拒絕發生在建立遠端服務之前。本機啟動進度、文件選擇與文字分享仍然可用。

注意簽章產物與原始碼的差別。2026-10-15 的已簽章 HAP 曾包含 `ohos.permission.INTERNET`。該 HAP 早於離線政策修正。安裝新 HAP 後要重新檢查權限清單。

主機行為證據由 `node tool/test_python_offline_platform.cjs` 提供。該指令碼用平台替身呼叫真實 EntryAbility 處理器。它不是裝置驗收。

## 限制

- 引擎是 MicroPython。它不是 CPython。
- 不支援 pip、CPython C 擴充與完整標準函式庫。
- 標準輸入來自專案根目錄的 `input.txt`。沒有互動式標準輸入。
- 輸出在本次執行結束後傳回。無限迴圈會佔住執行通道。
- 取消在 VM 迴圈和受支援的睡眠中生效。阻塞式原生 I/O 不可中斷。
- 終端機只執行專案內的 `.py` 與 `.mpy` 指令碼。它拒絕 `-m`、`-c`、解譯器選項與多餘參數。它沒有互動式 REPL。
- `.mpy` 是位元組碼檔案。它不是獨立程式，也不是 CPython 的 `.pyc`。

## 隨包模組與內建模組

隨包提供 10 個模組：base64、bisect、contextlib、copy、csv、functools、itertools、statistics、string、textwrap。每個模組的來源、授權條款與 SHA256 摘要記錄在 `assets/python_stdlib/PROVENANCE.md` 和 `assets/python_stdlib/manifest.json`。

內建模組共 17 個：sys、math、cmath、json、random、time、re、binascii、heapq、array、collections、struct、io、errno、micropython、gc、builtins。

這些清單只描述已測試的範圍。清單不承諾 CPython 相容。

## 本機套件

本機套件操作只接受本機的 `.py`、目錄、`.zip` 與純原始碼 `.whl`。不支援下載、建置鉤子與原生擴充。安裝前逐檔案做編譯檢查。交易失敗會回復。檔案數上限 4096。單一檔案上限 2 MiB。原始碼總量上限 16 MiB。

## 除錯工作階段

原始碼提供 `PythonDebugger`。它使用真實 MicroPython 工作階段。它支援斷點、步入、步過、步出、進入時停止、呼叫堆疊與變數。它要求檔案已儲存。它不接受未儲存的原始碼快照。除錯來源必須是專案內的 `.py` 檔案。一般執行仍承擔追蹤開銷。目前效能驗證尚未完成。

除錯的裝置驗收尚未完成。

## 建置

Android：

```powershell
flutter build apk --debug
adb -s emulator-5556 install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5556 shell am start -n com.azurekiln.qfli.pyflow/.MainActivity
```

Android 需要 NDK `27.0.12077973`。應用程式在 `android/app/build.gradle.kts` 固定該版本。偵錯 APK 位於 `build/app/outputs/flutter-apk/app-debug.apk`。請用 `adb devices` 回報的真實裝置號替換範例號。

鴻蒙 HAP：

```powershell
flutter build hap --release --target-platform ohos-arm64
```

已簽章 HAP 為 `build/ohos/hap/entry-default-signed.hap`。`ohos/entry/build-profile.json5` 只編譯 `arm64-v8a`。打包排除 x86_64 與 32 位元 ARM 函式庫。

原生函式庫：

以下指令建置鴻蒙 `libqfli_py.so`。

```powershell
& .\native\build.ps1
```

指令碼尋找工具鏈。指令碼在缺少原始碼時取得固定的 MicroPython 1.24.1。指令碼編譯 `libqfli_py.so`。指令碼檢查動態相依。指令碼複製到 `ohos/entry/libs/`。

Windows 桌面：

```powershell
./native/desktop/build.ps1 -Compiler <gcc.exe> -CMake <cmake.exe> -Ninja <ninja.exe>
```

`native/desktop/build.ps1` 只建置 Windows DLL。

Linux 與 macOS：

```sh
sh native/desktop/build.sh
```

`native/desktop/build.sh` 呼叫 CMake 設定 `native/desktop`。建置目標為 `qfli_py_ffi`。`native/linux/CMakeLists.txt` 引用同一份 `native/desktop`。

## 測試與驗證指令

```powershell
flutter analyze --no-pub
flutter test --no-pub
dart --packages=.dart_tool/package_config.json tool/python_ffi_smoke.dart native/build/windows/qfli_py_ffi.dll
python tool/verify_python_modules.py
node tool/test_python_offline_platform.cjs
python native/tools/inspect_so.py
```

`sh native/tests/run_host.sh` 在 POSIX 環境執行主機 C 測試。主機結果不替代裝置驗收。

裝置自檢記錄：

```powershell
adb -s emulator-5556 logcat -d -s QfliPyNative
hdc shell hilog -z 5000 -T QfliPyNative
```

## 目錄

| 路徑 | 用途 |
| --- | --- |
| `lib/main.dart` | Python 設定檔、終端機鉤子與進入點 |
| `lib/app_startup.dart` | 啟動引導與首幀交接 |
| `lib/python_tools_page.dart` | 專案與檔案工具、操作狀態 |
| `lib/python_runner.dart` | 執行轉接與結果型別 |
| `lib/python_ffi.dart` | 原生繫結與工作 isolate |
| `lib/python_packages.dart` | 本機套件交易 |
| `lib/python_code_analyzer.dart` | 未儲存緩衝區的診斷 |
| `lib/python_debugger.dart` | 真實 MicroPython 除錯工作階段 |
| `native/` | 內嵌 MicroPython、移植層與平台轉接 |
| `assets/python_stdlib/` | 隨包模組與來源記錄 |
| `test/` | 設定檔、工具、啟動與原生邊界回歸 |

## 更多文件

- `native/README.md`：原生後端細節與維護注意。
- `native/PLATFORMS.md`：平台建置與實測證據。
- `native/lifecycle.md`：取消、位元組碼與所有權。
- `.trellis/spec/`：編碼契約與驗證指引。