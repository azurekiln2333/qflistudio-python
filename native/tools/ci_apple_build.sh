#!/usr/bin/env bash
# Native-only builds using the hosted Mac's existing Xcode SDKs.
set -euo pipefail

: "${QFLI_APPLE_TARGET:?Set QFLI_APPLE_TARGET to ios or macos}"
case "$QFLI_APPLE_TARGET" in
  ios|macos) ;;
  *) printf 'Unsupported Apple target: %s\n' "$QFLI_APPLE_TARGET" >&2; exit 2 ;;
esac
test "$(uname -s)" = Darwin
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"
build_root="$repo_root/native/build/ci-apple-$QFLI_APPLE_TARGET"
artifact_directory="$repo_root/native/build/ci-artifacts/apple-$QFLI_APPLE_TARGET"
mkdir -p "$build_root" "$artifact_directory"

build_library() {
  local label=$1 sdk=$2 system=$3 architectures=$4 minimum=$5 kind=$6
  cmake -S native/desktop -B "$build_root/$label" -G Ninja \
    "-DCMAKE_SYSTEM_NAME=$system" \
    "-DCMAKE_OSX_SYSROOT=$(xcrun --sdk "$sdk" --show-sdk-path)" \
    "-DCMAKE_OSX_ARCHITECTURES=$architectures" \
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=$minimum" \
    "-DCMAKE_C_COMPILER=$(xcrun --sdk "$sdk" --find clang)" \
    "-DQFLI_PY_LIBRARY_TYPE=$kind" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
  cmake --build "$build_root/$label" --target qfli_py_ffi --parallel 3
}

check_symbols() {
  local library=$1 architecture=$2 report=$3 symbol
  xcrun nm -arch "$architecture" -gU "$library" > "$report"
  for symbol in qfli_py_version qfli_py_run_into qfli_py_execute_into \
    qfli_py_result_free qfli_py_cancel_create qfli_py_cancel_request \
    qfli_py_cancel_free qfli_py_debug_capabilities qfli_py_debug_create \
    qfli_py_debug_retain qfli_py_debug_release qfli_py_debug_set_breakpoints \
    qfli_py_debug_execute_into qfli_py_debug_command qfli_py_debug_poll_json \
    qfli_py_debug_json_free; do
    grep -Eq "[[:space:]]_$symbol$" "$report" || {
      printf 'Missing export %s for %s\n' "$symbol" "$architecture" >&2
      return 1
    }
  done
}

check_platform() {
  local library=$1 architecture=$2 platform=$3 report=$4
  python3 - "$library" "$architecture" "$platform" "$report" <<'PY'
import json
import pathlib
import re
import subprocess
import sys

library, architecture, expected, report = sys.argv[1:]
output = subprocess.check_output(
    ['xcrun', 'otool', '-arch', architecture, '-l', library], text=True)
platforms = re.findall(r'\bcmd LC_BUILD_VERSION\s+cmdsize \d+\s+platform (\S+)', output)
names = {'1': 'MACOS', '2': 'IOS', '7': 'IOSSIMULATOR'}
actual = {names.get(value.upper(), value.upper()) for value in platforms}
legacy = re.findall(r'\bcmd (LC_VERSION_MIN_\w+)', output)
if actual != {expected} or legacy:
    raise SystemExit(
        f'Unexpected {architecture} platform: expected {expected}, got {sorted(actual)}, legacy={legacy}')
pathlib.Path(report).write_text(json.dumps({
    'architecture': architecture, 'platform': expected,
    'buildVersionCommands': len(platforms),
}, indent=2) + '\n')
print(f'PASS {architecture} Mach-O platform {expected}')
PY
}

if [[ "$QFLI_APPLE_TARGET" == ios ]]; then
  build_library device iphoneos iOS arm64 13.0 STATIC
  build_library simulator iphonesimulator iOS 'arm64;x86_64' 14.0 STATIC
  device_library="$build_root/device/libqfli_py_ffi.a"
  simulator_library="$build_root/simulator/libqfli_py_ffi.a"
  xcrun lipo "$device_library" -verify_arch arm64
  xcrun lipo "$simulator_library" -verify_arch arm64 x86_64
  check_symbols "$device_library" arm64 "$artifact_directory/ios-arm64-symbols.txt"
  check_symbols "$simulator_library" arm64 "$artifact_directory/simulator-arm64-symbols.txt"
  check_symbols "$simulator_library" x86_64 "$artifact_directory/simulator-x86_64-symbols.txt"
  check_platform "$device_library" arm64 IOS "$artifact_directory/ios-arm64-platform.json"
  check_platform "$simulator_library" arm64 IOSSIMULATOR "$artifact_directory/simulator-arm64-platform.json"
  check_platform "$simulator_library" x86_64 IOSSIMULATOR "$artifact_directory/simulator-x86_64-platform.json"
  mkdir -p "$build_root/Headers"
  cp native/src/qfli_py_bridge.h native/src/qfli_py_debug.h "$build_root/Headers/"
  xcodebuild -create-xcframework \
    -library "$device_library" -headers "$build_root/Headers" \
    -library "$simulator_library" -headers "$build_root/Headers" \
    -output "$artifact_directory/qfli_py_ffi.xcframework"
  python3 - "$artifact_directory" <<'PY'
import json
import pathlib
import plistlib
import sys

root = pathlib.Path(sys.argv[1])
framework = root / 'qfli_py_ffi.xcframework'
metadata = plistlib.loads((framework / 'Info.plist').read_bytes())
slices = metadata['AvailableLibraries']
actual = {(entry['SupportedPlatform'], entry.get('SupportedPlatformVariant', ''),
           tuple(sorted(entry['SupportedArchitectures']))) for entry in slices}
expected = {('ios', '', ('arm64',)), ('ios', 'simulator', ('arm64', 'x86_64'))}
if actual != expected or len(slices) != 2:
    raise SystemExit(f'Unexpected XCFramework slices: {actual}')
for entry in slices:
    directory = framework / entry['LibraryIdentifier']
    if not (directory / entry['LibraryPath']).is_file():
        raise SystemExit('XCFramework library is missing')
    for header in ('qfli_py_bridge.h', 'qfli_py_debug.h'):
        if not (directory / entry['HeadersPath'] / header).is_file():
            raise SystemExit(f'XCFramework header missing: {header}')
(root / 'xcframework-report.json').write_text(json.dumps(metadata, indent=2) + '\n')
print('PASS iOS XCFramework device and simulator slices')
PY
else
  build_library arm64 macosx Darwin arm64 11.0 SHARED
  build_library x86_64 macosx Darwin x86_64 10.15 SHARED
  library="$artifact_directory/libqfli_py_ffi.dylib"
  xcrun lipo -create "$build_root/arm64/libqfli_py_ffi.dylib" \
    "$build_root/x86_64/libqfli_py_ffi.dylib" -output "$library"
  xcrun lipo "$library" -verify_arch arm64 x86_64
  for architecture in arm64 x86_64; do
    check_symbols "$library" "$architecture" "$artifact_directory/$architecture-symbols.txt"
    check_platform "$library" "$architecture" MACOS "$artifact_directory/$architecture-platform.json"
    xcrun otool -arch "$architecture" -L "$library" \
      > "$artifact_directory/$architecture-dependencies.txt"
  done
  python3 - "$artifact_directory" <<'PY'
import pathlib
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
library = root / 'libqfli_py_ffi.dylib'
architectures = subprocess.check_output(['xcrun', 'lipo', '-archs', str(library)], text=True).split()
if set(architectures) != {'arm64', 'x86_64'}:
    raise SystemExit(f'Unexpected macOS architectures: {architectures}')
for architecture in architectures:
    lines = (root / f'{architecture}-dependencies.txt').read_text().splitlines()
    dependencies = [line.strip().split(' (', 1)[0] for line in lines if line.startswith('\t')]
    allowed = {'@rpath/libqfli_py_ffi.dylib', '/usr/lib/libSystem.B.dylib'}
    unexpected = set(dependencies) - allowed
    if not dependencies or unexpected:
        raise SystemExit(f'Unexpected {architecture} dependencies: {unexpected}')
print('PASS macOS universal architecture and system dependencies')
PY
  python3 native/tests/debugger.py "$library" \
    --report "$artifact_directory/debugger-report.json"
  cp native/src/qfli_py_bridge.h native/src/qfli_py_debug.h "$artifact_directory/"
fi

{
  printf 'target=%s\nbuild_type=Release\n' "$QFLI_APPLE_TARGET"
  printf 'commit=%s\n' "$(git rev-parse HEAD)"
  printf 'run=%s/%s/actions/runs/%s\n' "${GITHUB_SERVER_URL:-local}" \
    "${GITHUB_REPOSITORY:-local}" "${GITHUB_RUN_ID:-local}"
  printf 'runner_arch=%s\n' "$(uname -m)"
  printf '%s\n' 'Toolchain: preinstalled Xcode; no compiler or SDK source build.'
  if [[ "$QFLI_APPLE_TARGET" == ios ]]; then
    printf '%s\n' 'Deployment minimum: iOS device 13.0; iOS simulator 14.0.'
    printf '%s\n' 'Validation: static slices and exports inspected; iOS device/simulator execution not run.'
  else
    printf '%s\n' 'Deployment minimum: macOS arm64 11.0; macOS x86_64 10.15.'
    printf 'Validation: native debugger tests executed on %s only; both slices inspected.\n' "$(uname -m)"
  fi
  printf '%s\n' 'Artifacts are native libraries, not signed applications or Flutter package validation.'
  xcodebuild -version
  xcrun clang --version
  cmake --version
  python3 --version
  for sdk in macosx iphoneos iphonesimulator; do
    printf '%s SDK: ' "$sdk"
    xcrun --sdk "$sdk" --show-sdk-version
  done
} > "$artifact_directory/BUILD_INFO.txt"
cp LICENSE native/LICENSE-MicroPython "$artifact_directory/"
python3 - "$artifact_directory" <<'PY'
import hashlib
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
paths = sorted(path for path in root.rglob('*') if path.is_file() and path.name != 'SHA256SUMS')
lines = [f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(root).as_posix()}' for path in paths]
(root / 'SHA256SUMS').write_text('\n'.join(lines) + '\n', encoding='utf-8')
PY
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    printf '### Apple %s native library\n\n' "$QFLI_APPLE_TARGET"
    printf 'Download the native artifact below; retention is 14 days.\n\n'
    printf 'Includes checksums, architecture/export evidence and build information.\n'
  } >> "$GITHUB_STEP_SUMMARY"
fi
