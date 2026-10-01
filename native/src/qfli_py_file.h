#ifndef QFLI_PY_FILE_H
#define QFLI_PY_FILE_H

#include "py/emitglue.h"

typedef struct qfli_py_file_node qfli_py_file_node_t;

void qfli_py_file_begin(const char *project_dir);
void qfli_py_file_end(void);
qfli_py_file_node_t *qfli_py_file_track(int fd);
void qfli_py_file_close(qfli_py_file_node_t *node);

void qfli_py_file_resolve(const char *name, int create, char *resolved);
void qfli_py_file_save_bytecode(mp_compiled_module_t *module, const char *name);


#endif
