#include "qfli_py_bridge.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int total;
static int passed;
static char project[256];
static char entry[320];

static void check(const char *name, const char *source, const char *input,
                  int code, const char *output, const char *error, int compile_only)
{
    QfliPyRunResult result = qfli_py_run(source, input, 0, project, entry, compile_only);
    int output_ok = output[0] == '\0' ? result.output[0] == '\0' : strstr(result.output, output) != NULL;
    int error_ok = error == NULL ? result.error == NULL :
        result.error != NULL && strstr(result.error, error) != NULL;
    ++total;
    if (result.exit_code == code && output_ok && error_ok && !result.truncated)
        ++passed;
    else
        fprintf(stderr, "FAIL %s: exit=%d stdout=%s stderr=%s\n", name,
            result.exit_code, result.output, result.error == NULL ? "" : result.error);
    qfli_py_result_free(&result);
}

static void write_file(const char *relative, const char *source)
{
    char path[512];
    snprintf(path, sizeof(path), "%s/%s", project, relative);
    FILE *file = fopen(path, "w");
    if (file == NULL) { perror(path); exit(1); }
    fputs(source, file);
    fclose(file);
}

static int fd_count(void)
{
    DIR *directory = opendir("/proc/self/fd");
    int count = 0;
    while (readdir(directory) != NULL) ++count;
    closedir(directory);
    return count;
}

int main(void)
{
    strcpy(project, "/tmp/qfli-python-smoke-XXXXXX");
    if (mkdtemp(project) == NULL) { perror("mkdtemp"); return 1; }
    snprintf(entry, sizeof(entry), "%s/main.py", project);
    char package[512];
    snprintf(package, sizeof(package), "%s/samplepkg", project);
    mkdir(package, 0700);
    write_file("helper.py", "answer = 42\n");
    write_file("samplepkg/__init__.py", "from .value import answer\n");
    write_file("samplepkg/value.py", "answer = 84\n");
    write_file("lines.txt", "first\nsecond\n");
    char link_path[512];
    snprintf(link_path, sizeof(link_path), "%s/outside-link", project);
    if (symlink("/etc/passwd", link_path) != 0) { perror("symlink"); return 1; }

    check("compile-run", "value = 42\nprint(value)", "", 0, "42\n", NULL, 0);
    check("script-no-expression-echo", "42\n'hello'", "", 0, "", NULL, 0);
    check("fresh-globals", "print(value)", "", 1, "", "NameError", 0);
    check("syntax-error", "def broken(:", "", 1, "", "SyntaxError", 0);
    check("runtime-error", "raise ValueError('bad')", "", 1, "", "ValueError: bad", 0);
    check("stdin", "print(input())", "Ada\n", 0, "Ada\n", NULL, 0);
    check("exit", "import sys\nsys.exit(7)", "", 7, "", NULL, 0);
    check("builtin-module", "import math\nprint(math.sqrt(81))", "", 0, "9.0\n", NULL, 0);
    check("sibling-import", "import helper\nprint(helper.answer)", "", 0, "42\n", NULL, 0);
    write_file("helper.py", "answer = 43\n");
    check("fresh-import", "import helper\nprint(helper.answer)", "", 0, "43\n", NULL, 0);
    check("package-import", "from samplepkg import answer\nprint(answer)", "", 0, "84\n", NULL, 0);
    check("text-file", "with open('notes.txt', 'w') as f:\n f.write('hello')\nwith open('notes.txt') as f:\n print(f.read())",
        "", 0, "hello\n", NULL, 0);
    check("append-file", "import io\nwith io.open('notes.txt', mode='a') as f:\n f.write('!')\nwith open('notes.txt') as f:\n print(f.read())",
        "", 0, "hello!\n", NULL, 0);
    check("binary-file", "with open('raw.bin', 'wb') as f:\n f.write(bytes([0, 255]))\nwith open('raw.bin', 'rb') as f:\n print(list(f.read()))",
        "", 0, "[0, 255]\n", NULL, 0);
    check("seek-file", "with open('notes.txt', 'r+') as f:\n f.seek(1)\n print(f.tell(), f.read(2))",
        "", 0, "1 el\n", NULL, 0);
    check("readlines", "with open('lines.txt') as f:\n print(f.readline().strip(), len(f.readlines()))",
        "", 0, "first 1\n", NULL, 0);
    check("file-iteration", "with open('lines.txt') as f:\n print([line.strip() for line in f])",
        "", 0, "['first', 'second']\n", NULL, 0);
    check("readinto", "with open('raw.bin', 'rb') as f:\n data = bytearray(2)\n print(f.readinto(data), list(data))",
        "", 0, "2 [0, 255]\n", NULL, 0);
    check("exclusive-create", "with open('new.txt', 'x+') as f:\n f.write('new')\n f.flush()\n f.seek(0)\n print(f.read())",
        "", 0, "new\n", NULL, 0);
    check("missing-file", "open('absent.txt')", "", 1, "", "ENOENT", 0);
    check("outside-project", "open('../outside.txt', 'w')", "", 1, "", "EACCES", 0);
    check("outside-symlink", "open('outside-link')", "", 1, "", "EACCES", 0);
    check("directory-file", "open('samplepkg')", "", 1, "", "EISDIR", 0);
    check("exclusive-file", "open('notes.txt', 'x')", "", 1, "", "EEXIST", 0);
    check("invalid-mode", "open('notes.txt', 'rw')", "", 1, "", "ValueError", 0);
    check("closed-file", "f = open('notes.txt')\nf.close()\nf.read()", "", 1, "", "EBADF", 0);
    check("compile-only", "open('must_not_exist.txt', 'w')\nprint('must not run')", "",
        0, "", NULL, 1);
    char side_effect[512];
    snprintf(side_effect, sizeof(side_effect), "%s/must_not_exist.txt", project);
    ++total;
    if (access(side_effect, F_OK) != 0) ++passed;
    else fprintf(stderr, "FAIL compile-only created a file\n");
    check("compile-only-error", "def broken(:", "", 1, "", "SyntaxError", 1);

    int before = fd_count();
    check("unclosed-file-error", "f = open('notes.txt')\nraise ValueError('bad')",
        "", 1, "", "ValueError: bad", 0);
    for (int i = 0; i < 20; ++i)
        check("unclosed-file", "open('notes.txt')", "", 0, "", NULL, 0);
    ++total;
    if (fd_count() == before) ++passed;
    else fprintf(stderr, "FAIL file descriptors leaked across runs\n");

    const char *files[] = {"helper.py", "samplepkg/__init__.py", "samplepkg/value.py",
        "notes.txt", "raw.bin", "lines.txt", "new.txt", "outside-link"};
    for (size_t i = 0; i < sizeof(files) / sizeof(files[0]); ++i)
    {
        char path[512];
        snprintf(path, sizeof(path), "%s/%s", project, files[i]);
        unlink(path);
    }
    rmdir(package);
    rmdir(project);
    printf("Native host smoke: %d/%d passed\n", passed, total);
    return passed == total ? 0 : 1;
}
