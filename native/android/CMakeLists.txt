cmake_minimum_required(VERSION 3.22.1)
project(qfli_py_android C CXX)

set(CMAKE_C_STANDARD 99)
set(CMAKE_CXX_STANDARD 17)
get_filename_component(QFLI_PY_NATIVE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
set(QFLI_PY_EMBED_DIR "${QFLI_PY_NATIVE_DIR}/micropython_embed")

# The checked-in package is shared with OHOS; parallel ABI builds only read it.
file(GLOB QFLI_PY_EMBED_SOURCES CONFIGURE_DEPENDS
    "${QFLI_PY_EMBED_DIR}/*/*.c"
    "${QFLI_PY_EMBED_DIR}/*/*/*.c")
list(FILTER QFLI_PY_EMBED_SOURCES EXCLUDE REGEX "/lib/re1\\.5/")
list(FILTER QFLI_PY_EMBED_SOURCES EXCLUDE REGEX "/port/qfli_time_localtime\\.c$")
list(FILTER QFLI_PY_EMBED_SOURCES EXCLUDE REGEX "/shared/runtime/sys_stdio_mphal\\.c$")
list(LENGTH QFLI_PY_EMBED_SOURCES QFLI_PY_EMBED_COUNT)
if(QFLI_PY_EMBED_COUNT LESS 100)
    message(FATAL_ERROR "The tracked MicroPython embedding package is incomplete")
endif()

add_library(qfli_py SHARED
    ${QFLI_PY_EMBED_SOURCES}
    "${QFLI_PY_NATIVE_DIR}/src/qfli_py_hal.c"
    "${QFLI_PY_NATIVE_DIR}/src/qfli_py_stdio.c"
    "${QFLI_PY_NATIVE_DIR}/src/qfli_py_file.c"
    "${QFLI_PY_NATIVE_DIR}/src/qfli_py_bridge.c"
    "${QFLI_PY_NATIVE_DIR}/src/qfli_py_jni.cpp")
target_include_directories(qfli_py PRIVATE
    "${QFLI_PY_EMBED_DIR}"
    "${QFLI_PY_EMBED_DIR}/port"
    "${QFLI_PY_NATIVE_DIR}/src")
# Upstream's setjmp fallback captures roots consistently with NDK Clang on all ABIs.
target_compile_definitions(qfli_py PRIVATE NDEBUG MICROPY_GCREGS_SETJMP=1)
target_compile_options(qfli_py PRIVATE
    -Wall -Wno-unused-parameter -Wno-error=format-security)
target_link_options(qfli_py PRIVATE
    "-Wl,-z,max-page-size=16384" "-Wl,-z,common-page-size=16384")
target_link_libraries(qfli_py PRIVATE m)
