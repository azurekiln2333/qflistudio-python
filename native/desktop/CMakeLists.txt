cmake_minimum_required(VERSION 3.15)
project(qfli_python_ffi LANGUAGES C)

get_filename_component(QFLI_PY_NATIVE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
set(QFLI_PY_EMBED_DIR "${QFLI_PY_NATIVE_DIR}/micropython_embed")

# Read the tracked package; desktop builds must not regenerate shared headers.
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

add_library(qfli_py_ffi SHARED
    ${QFLI_PY_EMBED_SOURCES}
    "${QFLI_PY_NATIVE_DIR}/src/qfli_py_hal.c"
    "${QFLI_PY_NATIVE_DIR}/src/qfli_py_stdio.c"
    "${QFLI_PY_NATIVE_DIR}/src/qfli_py_file.c"
    "${QFLI_PY_NATIVE_DIR}/src/qfli_py_bridge.c"
    "${QFLI_PY_NATIVE_DIR}/src/qfli_py_platform.c"
    "${QFLI_PY_NATIVE_DIR}/src/qfli_py_reader.c"
    "${QFLI_PY_NATIVE_DIR}/src/qfli_py_ffi.c")
target_include_directories(qfli_py_ffi PRIVATE
    "${QFLI_PY_EMBED_DIR}"
    "${QFLI_PY_EMBED_DIR}/port"
    "${QFLI_PY_NATIVE_DIR}/src")
target_compile_definitions(qfli_py_ffi PRIVATE NDEBUG)
if(NOT WIN32)
    target_compile_definitions(qfli_py_ffi PRIVATE
        MICROPY_GCREGS_SETJMP=1 MICROPY_NLR_SETJMP=1)
endif()

set_target_properties(qfli_py_ffi PROPERTIES
    OUTPUT_NAME "qfli_py_ffi"
    C_STANDARD 99
    C_STANDARD_REQUIRED YES
    POSITION_INDEPENDENT_CODE YES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")

foreach(QFLI_PY_CONFIGURATION Debug Release Profile RelWithDebInfo MinSizeRel)
    string(TOUPPER "${QFLI_PY_CONFIGURATION}" QFLI_PY_CONFIGURATION_UPPER)
    set_target_properties(qfli_py_ffi PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY_${QFLI_PY_CONFIGURATION_UPPER} "${CMAKE_CURRENT_BINARY_DIR}"
        LIBRARY_OUTPUT_DIRECTORY_${QFLI_PY_CONFIGURATION_UPPER} "${CMAKE_CURRENT_BINARY_DIR}")
endforeach()

if(WIN32)
    set_target_properties(qfli_py_ffi PROPERTIES PREFIX "")
    target_compile_definitions(qfli_py_ffi PRIVATE _WIN32_WINNT=0x0601)
endif()

if(MSVC)
    if(MSVC_VERSION LESS 1928)
        message(FATAL_ERROR "MicroPython requires MSVC 19.28 or later with C11 support")
    endif()
    set_target_properties(qfli_py_ffi PROPERTIES
        C_STANDARD 11
        MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")
    target_compile_definitions(qfli_py_ffi PRIVATE
        _CRT_SECURE_NO_WARNINGS _CRT_NONSTDC_NO_WARNINGS)
    target_compile_options(qfli_py_ffi PRIVATE /W3 /utf-8)
else()
    target_compile_options(qfli_py_ffi PRIVATE
        -Wall -Wno-unused-parameter -Wno-error=format-security)
    if(MINGW)
        target_link_options(qfli_py_ffi PRIVATE -static-libgcc)
    endif()
endif()

if(NOT WIN32)
    find_package(Threads REQUIRED)
    target_link_libraries(qfli_py_ffi PRIVATE Threads::Threads m)
endif()
