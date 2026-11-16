#!/usr/bin/env bash
# Cross-compile one ABI on a Linux host with an already verified native SDK.
set -euo pipefail

: "${OHOS_SDK_NATIVE:?Set OHOS_SDK_NATIVE to the extracted native SDK}"
: "${QFLI_OHOS_ABI:?Set QFLI_OHOS_ABI to arm64-v8a or x86_64}"
case "$QFLI_OHOS_ABI" in
  arm64-v8a|x86_64) ;;
  *) printf 'Unsupported OHOS ABI: %s\n' "$QFLI_OHOS_ABI" >&2; exit 2 ;;
esac

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"
build_directory="$repo_root/native/build/ci-ohos-$QFLI_OHOS_ABI"
artifact_directory="$repo_root/native/build/ci-artifacts/ohos-$QFLI_OHOS_ABI"
toolchain="$OHOS_SDK_NATIVE/build/cmake/ohos.toolchain.cmake"
python_executable=$(command -v python3)
cmake_executable=$(command -v cmake)
ninja_executable=$(command -v ninja)
manifest="$build_directory/native-build-evidence.json"
library="$build_directory/libqfli_py.so"
mkdir -p "$build_directory" "$artifact_directory"

configure=(
  "$cmake_executable" -S "$repo_root/native" -B "$build_directory" -G Ninja
  "-DCMAKE_TOOLCHAIN_FILE=$toolchain"
  "-DOHOS_ARCH=$QFLI_OHOS_ABI"
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
  "-DCMAKE_MAKE_PROGRAM=$ninja_executable"
  "-DQFLI_PY_PYTHON=$python_executable"
)
"${configure[@]}" 2>&1 | tee "$build_directory/configure.log"
# Reproduce the maintained Windows script's fresh-input provenance sequence.
"$cmake_executable" --build "$build_directory" --target qfli_py_regen \
  2>&1 | tee "$build_directory/regenerate.log"
"${configure[@]}" 2>&1 | tee "$build_directory/reconfigure.log"
"$python_executable" tool/python_native_provenance.py capture \
  --build-directory "$build_directory" --abi "$QFLI_OHOS_ABI" \
  --build-type Release --manifest "$manifest" --python "$python_executable" \
  --tool "$cmake_executable" --tool "$ninja_executable" --tool "$toolchain"
"$cmake_executable" --build "$build_directory" --clean-first --target qfli_py \
  --parallel 2 2>&1 | tee "$build_directory/build.log"
"$python_executable" native/tools/check_so_deps.py "$library" \
  2>&1 | tee "$artifact_directory/dependencies.txt"
"$python_executable" tool/python_native_provenance.py finish \
  --manifest "$manifest" --library "$library"
"$python_executable" tool/python_native_provenance.py verify \
  --manifest "$manifest" --library "$library"

# Complete and stage each ABI before the next one regenerates shared headers.
cp -- "$library" "$artifact_directory/libqfli_py.so"
cp -- "$manifest" "$artifact_directory/native-build-evidence.json"
cp -- "$OHOS_SDK_NATIVE/oh-uni-package.json" "$artifact_directory/sdk-package.json"
{
  printf 'Target: OpenHarmony %s\nBuild type: Release\n' "$QFLI_OHOS_ABI"
  printf 'Commit: %s\n' "$(git rev-parse HEAD)"
  printf 'MicroPython commit: %s\n' "$(git -C native/third_party/micropython rev-parse HEAD)"
  printf 'Run: %s/%s/actions/runs/%s\n' "${GITHUB_SERVER_URL:-local}" \
    "${GITHUB_REPOSITORY:-local}" "${GITHUB_RUN_ID:-local}"
  printf 'SDK archive: %s\nSDK SHA256: %s\n' "${SDK_URL:-externally-provided}" \
    "${SDK_SHA256:-not-recorded}"
  printf '%s\n' 'SDK metadata: sdk-package.json (OpenHarmony 6.1 API 23; not the local DevEco API 26 SDK).'
  printf '%s\n' 'Validation: cross-compiled; ELF ABI, dependencies and build provenance checked.'
  printf '%s\n' 'Runtime/device validation: not run. This artifact is a library, not a signed HAP.'
  printf '%s\n' 'Provenance paths describe the cloud runner and are not portable local verification inputs.'
  "$cmake_executable" --version
  "$python_executable" --version
  "$OHOS_SDK_NATIVE/llvm/bin/clang" --version
} > "$artifact_directory/BUILD_INFO.txt"
(
  cd "$artifact_directory"
  sha256sum libqfli_py.so native-build-evidence.json sdk-package.json \
    dependencies.txt BUILD_INFO.txt > SHA256SUMS
)
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    printf '### OpenHarmony %s\n\n' "$QFLI_OHOS_ABI"
    printf 'Artifact: `native-ohos-%s` (retained for 14 days).\n\n' "$QFLI_OHOS_ABI"
    printf 'Contains `libqfli_py.so`, checksums, SDK metadata and build evidence.\n\n'
    printf 'Cross-compilation and dependency checks passed; device execution was not tested.\n'
  } >> "$GITHUB_STEP_SUMMARY"
fi
