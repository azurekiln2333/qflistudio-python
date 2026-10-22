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

static void check_at(const char *name, const char *source, const char *input,
    int code, const char *output, const char *error, int compile_only,
    const char *project_dir, const char *entry_file)
{
    QfliPyRunResult result = qfli_py_run(source, input, 0, project_dir, entry_file, compile_only);
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

static void check(const char *name, const char *source, const char *input,
    int code, const char *output, const char *error, int compile_only)
{
    check_at(name, source, input, code, output, error, compile_only, project, entry);
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

static void make_directory(const char *relative)
{
    char path[512];
    snprintf(path, sizeof(path), "%s/%s", project, relative);
    if (mkdir(path, 0700) != 0) { perror(path); exit(1); }
}

static void remove_file(const char *relative)
{
    char path[512];
    snprintf(path, sizeof(path), "%s/%s", project, relative);
    if (unlink(path) != 0) { perror(path); exit(1); }
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
    check("stdin-eof", "input()", "", 1, "", "EOFError", 0);
    check("stdin-empty-line", "print(repr(input()))", "\n", 0, "''\n", NULL, 0);
    check("stdin-final-line", "print(input())\ninput()", "Ada", 1, "Ada\n", "EOFError", 0);
    check("stdin-read-all", "import sys\nprint(repr(sys.stdin.read()))", "Ada\nLin\n",
        0, "'Ada\\nLin\\n'\n", NULL, 0);
    check("stdin-readline-eof", "import sys\nprint(repr(sys.stdin.readline()), repr(sys.stdin.readline()), repr(sys.stdin.readline()))",
        "Ada\nLin", 0, "'Ada\\n' 'Lin' ''\n", NULL, 0);
    check("stdin-shared-cursor", "import sys\nprint(sys.stdin.read(2), input(), repr(sys.stdin.read()))",
        "Ada\nLin\n", 0, "Ad a 'Lin\\n'\n", NULL, 0);
    check("stdin-buffer-shared-cursor", "import sys\nprint(sys.stdin.buffer.read(1), sys.stdin.read(), sys.stdin.buffer.read())",
        "Ada", 0, "b'A' da b''\n", NULL, 0);
    check("stdin-readinto", "import sys\ndata = bytearray(5)\nprint(sys.stdin.buffer.readinto(data), list(data), repr(sys.stdin.buffer.read()))",
        "Ada", 0, "3 [65, 100, 97, 0, 0] b''\n", NULL, 0);
    check("stderr-stream", "import sys\nsys.stdout.write('out\\n')\nsys.stderr.write('err\\n')\nsys.stdout.flush()\nsys.stderr.flush()",
        "", 0, "out\n", "err\n", 0);
    check("binary-stdio", "import sys\nsys.stdout.buffer.write(b'out\\n')\nsys.stderr.buffer.write(b'err\\n')\nsys.stdout.buffer.flush()\nsys.stderr.buffer.flush()",
        "", 0, "out\n", "err\n", 0);
    check("stdout-read-error", "import sys\nsys.stdout.read(1)", "", 1, "", "EPERM", 0);
    check("stdio-error-recovery", "print(input())", "recovered\n", 0, "recovered\n", NULL, 0);
    check("exit", "import sys\nsys.exit(7)", "", 7, "", NULL, 0);
    check("exit-overflow", "import sys\nsys.exit(1 << 200)", "", 1, "", "OverflowError", 0);
    check("exit-overflow-recovery", "print('recovered')", "", 0, "recovered\n", NULL, 0);
    check("builtin-module", "import math\nprint(math.sqrt(81))", "", 0, "9.0\n", NULL, 0);
    check("sibling-import", "import helper\nprint(helper.answer)", "", 0, "42\n", NULL, 0);
    write_file("helper.py", "answer = 43\n");
    check("fresh-import", "import helper\nprint(helper.answer)", "", 0, "43\n", NULL, 0);
    check("package-import", "from samplepkg import answer\nprint(answer)", "", 0, "84\n", NULL, 0);
    check("absent-package-directories", "import helper\nprint(helper.answer)\ntry:\n import absent_package\nexcept ImportError:\n print('missing')",
        "", 0, "43\nmissing\n", NULL, 0);

    const char *directories[] = {"lib", "lib/localpkg", "lib/localpkg/nested",
        ".qfli", ".qfli/python", ".qfli/python/bundled", ".qfli/python/bundled/v1",
        ".qfli/python/bundled/v1/bundlepkg", "src", "src/\xe5\xad\xa6\xe7\x94\x9f\xf0\x9f\x9a\x80"};
    for (size_t i = 0; i < sizeof(directories) / sizeof(directories[0]); ++i)
        make_directory(directories[i]);
    write_file("lib/localpkg/__init__.py", "from .nested.api import total\n");
    write_file("lib/localpkg/nested/__init__.py", "");
    write_file("lib/localpkg/nested/api.py", "def total(values):\n return sum(values) * 2\n");
    write_file(".qfli/python/bundled/v1/bundlepkg/__init__.py", "from .values import answer\n");
    write_file(".qfli/python/bundled/v1/bundlepkg/values.py", "answer = 17\n");
    write_file("rank.py", "value = 'project'\n");
    write_file("lib/rank.py", "value = 'local'\n");
    write_file(".qfli/python/bundled/v1/rank.py", "value = 'bundled'\n");
    write_file("src/\xe5\xad\xa6\xe7\x94\x9f\xf0\x9f\x9a\x80/rank.py", "value = 'entry'\n");
    char nested_entry[512];
    snprintf(nested_entry, sizeof(nested_entry), "%s/src/\xe5\xad\xa6\xe7\x94\x9f\xf0\x9f\x9a\x80/main.py", project);
    check_at("local-package-submodules", "from localpkg import total\nprint(total([3, 4, 5]))",
        "", 0, "24\n", NULL, 0, project, nested_entry);
    check_at("bundled-package-submodules", "from bundlepkg import answer\nprint(answer)",
        "", 0, "17\n", NULL, 0, project, nested_entry);
    check_at("entry-import-precedence", "import rank\nprint(rank.value)",
        "", 0, "entry\n", NULL, 0, project, nested_entry);
    char normalized_entry[512];
    snprintf(normalized_entry, sizeof(normalized_entry), "%s/src/\xe5\xad\xa6\xe7\x94\x9f\xf0\x9f\x9a\x80/../\xe5\xad\xa6\xe7\x94\x9f\xf0\x9f\x9a\x80/main.py", project);
    char normalized_project[512];
    snprintf(normalized_project, sizeof(normalized_project), "%s/./", project);
    check_at("normalized-import-directories", "import rank, localpkg, bundlepkg\nprint(rank.value, localpkg.total([2, 3]), bundlepkg.answer)",
        "", 0, "entry 10 17\n", NULL, 0, normalized_project, normalized_entry);
    remove_file("src/\xe5\xad\xa6\xe7\x94\x9f\xf0\x9f\x9a\x80/rank.py");
    check_at("project-import-precedence", "import rank\nprint(rank.value)",
        "", 0, "project\n", NULL, 0, project, nested_entry);
    remove_file("rank.py");
    check_at("local-import-precedence", "import rank\nprint(rank.value)",
        "", 0, "local\n", NULL, 0, project, nested_entry);
    remove_file("lib/rank.py");
    check_at("bundled-import-fallback", "import rank\nprint(rank.value)",
        "", 0, "bundled\n", NULL, 0, project, nested_entry);
    write_file("lib/localpkg/nested/api.py", "def total(values):\n return sum(values) * 3\n");
    check_at("fresh-local-package-submodule", "from localpkg import total\nprint(total([3, 4, 5]))",
        "", 0, "36\n", NULL, 0, project, nested_entry);
    remove_file("lib/localpkg/nested/api.py");
    check_at("removed-local-package-submodule", "from localpkg import total",
        "", 1, "", "ImportError", 0, project, nested_entry);
    write_file("lib/localpkg/nested/api.py", "def total(values):\n return sum(values) * 2\n");
    check_at("local-package-import-recovery", "from localpkg import total\nprint(total([3, 4, 5]))",
        "", 0, "24\n", NULL, 0, project, nested_entry);
    char oversized_path[4097];
    memset(oversized_path, 'x', sizeof(oversized_path) - 1);
    oversized_path[sizeof(oversized_path) - 1] = '\0';
    check_at("overlong-import-project", "print('must not run')", "", 1, "", "OSError", 0,
        oversized_path, entry);
    check_at("overlong-import-entry", "print('must not run')", "", 1, "", "OSError", 0,
        project, oversized_path);
    check("import-path-error-recovery", "from localpkg import total\nprint(total([20, 1]))",
        "", 0, "42\n", NULL, 0);

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

    write_file("lib/import_file.py", "handle = open('lines.txt')\nvalue = handle.readline().strip()\n");
    write_file("lib/import_error.py", "handle = open('lines.txt')\nraise ValueError('import failed')\n");
    before = fd_count();
    for (int i = 0; i < 10; ++i)
    {
        check("imported-unclosed-file", "import import_file\nprint(import_file.value)",
            "", 0, "first\n", NULL, 0);
        check("imported-unclosed-file-error", "import import_error", "", 1, "", "ValueError: import failed", 0);
    }
    ++total;
    if (fd_count() == before) ++passed;
    else fprintf(stderr, "FAIL file descriptors leaked across imported modules\n");

    const char *files[] = {"helper.py", "samplepkg/__init__.py", "samplepkg/value.py",
        "notes.txt", "raw.bin", "lines.txt", "new.txt", "outside-link",
        "lib/localpkg/__init__.py", "lib/localpkg/nested/__init__.py", "lib/localpkg/nested/api.py",
        ".qfli/python/bundled/v1/bundlepkg/__init__.py", ".qfli/python/bundled/v1/bundlepkg/values.py",
        ".qfli/python/bundled/v1/rank.py", "lib/import_file.py", "lib/import_error.py"};
    for (size_t i = 0; i < sizeof(files) / sizeof(files[0]); ++i)
    {
        char path[512];
        snprintf(path, sizeof(path), "%s/%s", project, files[i]);
        unlink(path);
    }
    for (size_t i = sizeof(directories) / sizeof(directories[0]); i > 0; --i)
    {
        char path[512];
        snprintf(path, sizeof(path), "%s/%s", project, directories[i - 1]);
        rmdir(path);
    }
    rmdir(package);
    rmdir(project);
    printf("Native host smoke: %d/%d passed\n", passed, total);
    return passed == total ? 0 : 1;
}
