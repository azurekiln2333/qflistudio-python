#!/bin/sh
set -eu

native_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
case "$(uname -s)" in
    Linux) platform=linux ;;
    Darwin) platform=macos ;;
    *) printf '%s\n' 'Use desktop/build.ps1 for Windows.' >&2; exit 1 ;;
esac

build_dir=${QFLI_PY_BUILD_DIR:-"$native_dir/build/$platform"}
cmake_bin=${QFLI_PY_CMAKE:-cmake}
if [ -n "${QFLI_PY_GENERATOR:-}" ]; then
    generator=$QFLI_PY_GENERATOR
elif command -v ninja >/dev/null 2>&1; then
    generator=Ninja
else
    generator='Unix Makefiles'
fi
"$cmake_bin" -S "$native_dir/desktop" -B "$build_dir" \
    -G "$generator" \
    "-DCMAKE_C_COMPILER=${CC:-cc}" \
    "-DCMAKE_BUILD_TYPE=${QFLI_PY_BUILD_TYPE:-Release}"
"$cmake_bin" --build "$build_dir" --target qfli_py_ffi --parallel "${QFLI_PY_JOBS:-2}"
