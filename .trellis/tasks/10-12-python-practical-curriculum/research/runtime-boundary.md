# Embedded runtime boundary (MicroPython 1.24.1) — verified

Do **not** assume CPython. The bundled runtime is embedded MicroPython
`1.24.1 (ecfdd5d)`, ROM level `EXTRA_FEATURES`. Evidence below is from the real
shipped Windows FFI DLL (`native/build/windows/qfli_py_ffi.dll`) via
`qfli_py_run_into`, and from `native/port/mpconfigport.h`.

## Port configuration (authoritative)

From `native/port/mpconfigport.h`:

- `MICROPY_CONFIG_ROM_LEVEL_EXTRA_FEATURES`.
- `MICROPY_ENABLE_COMPILER=1`, `MICROPY_ENABLE_GC=1`,
  `MICROPY_PERSISTENT_CODE_LOAD/SAVE=1`.
- `MICROPY_PY_BUILTINS_EXECFILE=0` (no `exec` of files; `compile()` string OK).
- `MICROPY_VFS=0`, `MICROPY_READER_POSIX=1`, `MICROPY_PY_IO_FILEIO=0`,
  `MICROPY_PY_OS=0` (so no `os` module).
- Disabled on purpose: `hashlib`, `select`, `uctypes`, `asyncio`, `deflate`,
  `framebuf`, `platform`.
- `MICROPY_HELPER_REPL=0`, `MICROPY_PY_BUILTINS_INPUT=1`.
- `MICROPY_PY_TIME_GMTIME_LOCALTIME_MKTIME=1`.
- `MICROPY_FLOAT_IMPL_DOUBLE` (floats are CPython-compatible doubles).
- `sys.platform` = `win32`/`android`/`ohos`/`ios`/`darwin`/`linux`.

Both `native/port/mpconfigport.h` and `native/micropython_embed/port/mpconfigport.h`
are byte-identical duplicates; keep them in sync.

## Empirical probe: modules

Available (import succeeds): `math` (partial), `cmath`, `json`, `re` (partial),
`random`, `time` (partial), `heapq`, `collections`, `struct`, `binascii`, `io`,
`sys`, `gc`, `micropython`, `array`, `errno`, plus `u*` aliases
(`utime`, `ustruct`, `ubinascii`, `uheapq`, `ucollections`).

Unavailable (ImportError): `os`, `dataclasses`, `datetime`, `bisect`,
`contextlib`, `functools`, `itertools`, `enum`, `typing`, `abc`, `zlib`,
`socket`, `subprocess`, `threading`, `hashlib`, `select`, `uctypes`, `asyncio`,
`deflate`, `framebuf`.

Partial-module gotchas verified:

- `re`: `re.sub` and `re.compile` OK; `re.findall`, `re.match`, `re.search`
  raise `AttributeError`/`TypeError` (MicroPython `re` differs).
- `math`: `pi`, `sqrt`, `pow`, `floor` OK; `gcd` missing.
- `time`: `sleep_ms` OK; `time.time` missing; localtime/gmtime/mktime enabled.
- `gc.collect()` returns `None` (not int).
- `collections.deque` exists; constructor kwargs are narrower than CPython.

## Empirical probe: language features

Works: f-strings incl. format specs, walrus `:=` (also in comprehensions),
generators, decorators, context-manager classes, iterator protocol, `@property`,
`@staticmethod`/`@classmethod`, `super()`, `__slots__`, `try/except/finally`,
`divmod`, star tuple unpacking assignment (`a, *b = ...`), dict literals,
`sorted(key=...)`, `map`+`lambda`, `print(sep=, end=)`.

Fails (SyntaxError/ImportError): `match` statement, dict-merge unpack
(`{**a, 'b':2}`), `from typing import ...`, `dataclasses`, `abc`.

## Empirical probe: exit / IO semantics

| Program | exit | output | error |
|---|---|---|---|
| `print(42)` | 0 | `42\n` | — |
| `print('a'); sys.exit(0)` | 0 | `a\n` | — |
| `sys.exit(3)` | 3 | — | — |
| `sys.exit('boom')` | 1 | — | `boom` |
| `sys.exit()` | 0 | — | — |
| `1/0` | 1 | — | traceback (`ZeroDivisionError`) |
| `input()` with stdin `7 5` | 0 | `7 5\n` | — |
| `input()` with empty stdin | 1 | — | `EOFError` |
| `open('notes.txt','w')` then read | 0 | `hi\n` | — |
| `compile_only=1` on `print(1)` | 0 | (none) | — |

`sys.argv[0]` is the absolute entry path. `input()` and `sys.stdin` share one
finite buffer fed from the project's `input.txt`.

## Authoring rules derived from this boundary

1. Runnable samples use only the verified-available subset; every sample is
   executed against the real runtime and its `output` diffed before shipping.
2. CPython-only topics may be taught, but every such lesson must be explicitly
   labeled **"需要外部 CPython 环境"** and its runtime claim must be true. Do not
   claim the bundled runtime passed them.
3. Never present `match`, dict-merge, or `from typing import` as working.
4. Prefer the portable core (variables, control flow, functions, containers,
   classes, closures/decorators, generators, exceptions, files, recursion,
   algorithms, `json`/`math`/`random`/`heapq`/`collections`/`re` subset,
   `struct`/`binascii`).
5. Where a topic is core Python but the module is absent (`os`, `datetime`,
   `itertools`, `functools`, `contextlib`), teach the concept with a runnable
   pure-Python re-implementation plus a clearly-marked note on the CPython
   module.
