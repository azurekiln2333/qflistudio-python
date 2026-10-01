#include "qfli_py_bridge.h"
#include <stddef.h>

QFLI_PY_API void qfli_py_run_into(QfliPyRunResult *result,
    const char *source, const char *stdin_text, int heap_kb,
    const char *project_dir, const char *entry_file, int compile_only)
{
    if (result != NULL)
        *result = qfli_py_run(source, stdin_text, heap_kb, project_dir, entry_file, compile_only);
}
