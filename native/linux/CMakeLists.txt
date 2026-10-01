cmake_minimum_required(VERSION 3.15)
project(qfli_python_native LANGUAGES C)

add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../desktop"
    "${CMAKE_CURRENT_BINARY_DIR}/engine")

set(qfli_python_native_bundled_libraries
    $<TARGET_FILE:qfli_py_ffi>
    PARENT_SCOPE)
