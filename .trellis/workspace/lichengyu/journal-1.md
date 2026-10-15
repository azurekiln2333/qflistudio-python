# Journal - lichengyu (Part 1)

> AI development session journal
> Started: 2026-09-30

---



## Session 1: Native Python file I/O and tools
<!-- trellis-session: v=2 fp=969b9c0cc57ce5af -->

**Date**: 2026-09-30
**Task**: Native Python file I/O and tools
**Branch**: `main`

### Summary

Added project file streams and compile-only tools using the upstream C MicroPython runtime; kept the task open for final device validation.

### Main Changes

- Project-root open/io.open, descriptor cleanup, compile-only MethodChannel and actual project/file tools UI.
- Fixed script REPL-expression echo and stale async file scans; updated tracked build documentation and local specs.

### Git Commits

| Hash | Message |
|------|---------|
| `8b1ab83` | feat(runtime): add project file I/O and Python tools |

### Testing

- [OK] Native host C VM 51/51; Flutter 25/25; analyze clean; ARM64 dependency scan and signed HAP build passed; ArkTS copies identical.

### Status

[OK] **Completed**

### Next Steps

- Reconnect the HarmonyOS device, install entry-default-signed.hap, launch EntryAbility and confirm the latest 17/17 QfliPyNative self-check. Latest prior device evidence remains 14/14.


## Session 2: Android APK build and emulator smoke
<!-- trellis-session: v=2 fp=5c56372b51429297 -->

**Date**: 2026-10-01
**Task**: Android APK build and emulator smoke
**Branch**: `main`

### Summary

Built and installed the debug APK on emulator-5556; verified home, Python tools, project creation and editor. Android Python execution remains unavailable.

### Main Changes

- Pinned complete Android NDK 27.0.12077973 and reduced JVM memory and worker budgets after an allocation crash.

### Git Commits

| Hash | Message |
|------|---------|
| `c318337` | fix(android): stabilize APK builds for emulator testing |

### Testing

- [OK] flutter build apk --debug passed; adb install and app launch passed; screenshots verified; application-specific error logcat empty.
- [OK] Created AndroidSmoke and clicked Run: unavailable Python MethodChannel produced exit code 127, so no Android Python execution was claimed.

### Status

[OK] **Completed**

### Next Steps

- Implement an Android JNI adapter for the existing C MicroPython engine when Android execution is in scope; final HarmonyOS 17/17 device check also remains pending.


## Session 3: Android shared C Python runtime
<!-- trellis-session: v=2 fp=aaa342fe2d872bd6 -->

**Date**: 2026-10-01
**Task**: Android shared C Python runtime
**Branch**: `main`

### Summary

Connected Android NDK/JNI to shared MicroPython; fixed finite standard streams and exit overflow; verified APK execution on emulator. HarmonyOS runtime debugging stopped at user's request.

### Main Changes

- Shared C stdio EOF/stderr and exit cleanup, Kotlin channel with standard UTF-8 JNI, all three ABI builds.

### Git Commits

| Hash | Message |
|------|---------|
| `be7d0c4` | fix(runtime): handle finite standard streams and exit overflow |
| `59daed7` | feat(android): execute Python with the shared native engine |

### Testing

- [OK] Host C VM 65/65; Android native JNI 36/36; Flutter 25/25; analyze clean; debug/release/profile APK builds; release editor execution and syntax checks; 16 KiB alignment checks.

### Status

[OK] **Completed**

### Next Steps

- Original HarmonyOS latest-HAP 17/17 gate remains pending; no further HarmonyOS execution in this session.


## Session 4: Android tutorial and example import verification
<!-- trellis-session: v=2 fp=5d43c53f764f5d82 -->

**Date**: 2026-10-01
**Task**: Android tutorial and example import verification
**Branch**: `main`

### Summary

Verified existing shared MD3 catalogs and detail actions: 55 shared content/import tests and 25 Python app tests pass; application-source analysis clean. Built and installed a fresh debug APK. Real Android custom-name imports to editor, new project and existing project open the correct file; native Python printed weighted=22 and 424242 with exit 0. Used isolated emulator-5560 after detecting another session on emulator-5556. Shared core source work belongs to the other session; unrelated HarmonyOS agreement changes were preserved.

### Git Commits

| Hash | Message |
|------|---------|
| `b400d70` | docs: record Android content import verification |

### Status

[OK] **Completed**


## Session 5: Native startup progress and first-frame handoff
<!-- trellis-session: v=2 fp=7f84392f53280bb5 -->

**Date**: 2026-10-01
**Task**: Native startup progress and first-frame handoff
**Branch**: `main`

### Summary

Implemented Android and HarmonyOS native progress, deferred Flutter until ready home, fixed system splash blank frames; Android 207 frames zero blanks and Python execution verified; signed HAP built without device launch.

### Main Changes

- Native progress and rendered first-frame handoff on Android/OHOS

### Git Commits

| Hash | Message |
|------|---------|
| `d022c8a` | feat(startup): keep native progress visible until Flutter home |

### Testing

- [OK] Flutter 33/33, analyze clean; signed APK/HAP build; 3 Android cold starts 207 frames zero blank, JNI36/36 and editor stdout424242 exit0

### Status

[OK] **Completed**

### Next Steps

- HarmonyOS visual verification requires lifting the standing device restriction; existing native runtime task remains separate.


## Session 6: Python release audit and device gate handoff
<!-- trellis-session: v=2 fp=b4dc4dbfde40bd0f -->

**Date**: 2026-10-15
**Task**: Python release audit and device gate handoff
**Branch**: `release/python-storefront-20261015`

### Summary

Completed Python terminal/native/offline/curriculum audit and final Android/OHOS builds; retained explicit device and production-signing gates.

### Main Changes

- Registered the real Python terminal delegate for both surfaces; added OHOS async controlled execution, bytecode, strict validation and lifetime cleanup.
- Verified 120 paired tutorials/examples, preserved non-Python/user data, completed concrete Trellis specs and archived bootstrap/curriculum/terminal tasks.
- Coordinated shared About identity fix in core 8b33443; preserved every other core owner and initial unrelated OHOS/configuration change.

### Git Commits

| Hash | Message |
|------|---------|
| `77f46d5` | feat(python): complete OHOS async execution and runtime controls |
| `7286cd9` | fix(terminal): connect offline Python commands in both terminal surfaces |
| `189d589` | fix(native): release failed OHOS work and reject incomplete controls |
| `0b5d833` | fix(ohos): replace scaffold metadata and document ABI packaging checks |
| `d615a1c` | docs(release): record final platform evidence and remaining device gates |

### Testing

- [OK] Final full Python tests 91/91 and analyzer clean after core8b33443; actual Windows FFI34, Linux C65, OHOS handler20, Android device JNI46; core About4.
- [OK] Final Android release build75.8s, no INTERNET, nine ELF and ZIP16KiB checks pass; final OHOS HAP104.6s, three current arm64 libraries, install successful.

### Status

**Implementation/build audit recorded; device acceptance remains pending.**

### Next Steps

- Unlock OHOS device192.168.68.207:46551 and validate fresh base17, cancellation, bytecode and argument6 self-checks; latest launch is10106102.
- Coordinate free Android foreground for standalone/editor run/compile/stop and final release installation/JNI usability; peer WebForge held last window, no competing launch performed.
- Configure and verify production store signing separately; existing Android and OHOS debug signing was preserved. Release/native tasks remain in progress.
