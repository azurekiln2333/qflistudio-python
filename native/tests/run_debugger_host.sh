#!/bin/sh
set -eu

native_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$native_dir"
mkdir -p build/host
gcc -std=gnu99 -O2 -fPIC -shared -DNDEBUG \
    -DMICROPY_GCREGS_SETJMP=1 -DMICROPY_NLR_SETJMP=1 \
    -I micropython_embed -I micropython_embed/port -I src \
    micropython_embed/py/*.c micropython_embed/extmod/*.c \
    micropython_embed/shared/runtime/gchelper_generic.c micropython_embed/shared/timeutils/*.c \
    src/qfli_py_platform.c src/qfli_py_reader.c src/qfli_py_hal.c \
    src/qfli_py_stdio.c src/qfli_py_file.c src/qfli_py_bridge.c \
    src/qfli_py_debug.c src/qfli_py_ffi.c \
    -lm -lpthread -o build/host/libqfli_py_debug_test.so
python3 tests/debugger.py build/host/libqfli_py_debug_test.so \
    --report ../build/reports/python-native-debugger-posix.json
