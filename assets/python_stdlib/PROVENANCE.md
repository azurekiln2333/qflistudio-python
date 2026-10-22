# Qfli offline Python bundle v1

This is an explicit subset for the Qfli MicroPython 1.24.1 VM, not the CPython
standard library. All executable files and exact SHA256 digests are listed in
manifest.json. There are no runtime downloads, network clients, package build
scripts or binary extension loaders in this bundle.

## Pinned third-party source

Repository: https://github.com/micropython/micropython-lib
Commit: `90028be0829c6e988b5e239b28f39fb91b6b20e2` (2026-10-12).

| File | Upstream path and version | Changes |
| --- | --- | --- |
| bisect.py | python-stdlib/bisect/bisect.py, 0.5.0 | Unmodified. CPython-derived bisection implementation. |
| string.py | python-stdlib/string/string/__init__.py, 0.2.0 | Unmodified; flattened module, no templatelib dependency. |
| itertools.py | python-stdlib/itertools/itertools.py, 0.2.3 | Reworked slicing and independent tee cursors; added selection/product helpers; finite exhaustion and negative argument checks. |
| functools.py | python-stdlib/functools/functools.py, 0.1.0 | Removed dummy wraps/update_wrapper; fixed reduce's empty and explicit-None cases; deterministic cache keys, typed keys, zero capacity and eviction. |

The complete upstream license notice is retained in LICENSE-micropython-lib.txt,
including MIT and Python license terms. CPython-derived bisect uses Python-2.0;
the string/itertools/functools implementations use the repository MIT default.
Original module source and manifest are available at the pinned paths above;
do not replace the pin with a moving branch when updating provenance.

## Locally authored modules

csv.py, statistics.py, copy.py, contextlib.py, textwrap.py and base64.py are Qfli
implementations under LICENSE-qfli.txt (MIT). They are not copied CPython files.
The callable names follow familiar Python APIs while respecting the embedded
VM's capabilities. Behavioral tests are in native/tests/python_stdlib_smoke.py.

## Supported scope and differences

- bisect: left/right positions and insertions, aliases, lo/hi. No key parameter.
- string: ASCII classification constants and micropython-lib translate(string,
  mapping). No Template, Formatter, capwords or str.translate monkey patch.
- itertools: count, cycle, repeat, chain, islice, tee, starmap, accumulate,
  takewhile, dropwhile, filterfalse, compress, product. No chain.from_iterable,
  groupby, combinations, permutations or strict/batched interfaces. tee queues
  consume memory in proportion to the lag between consumers.
- functools: partial, reduce, lru_cache and cache. Decorated callables do not
  expose CPython metadata, cache_info or cache_clear. lru_cache accepts bare
  decoration or keyword maxsize/typed; positional integer maxsize is rejected.
  Keyword arguments are sorted for cache keys, so different keyword orders
  share one entry. Reentrant calls preserve a single entry per key.
- csv: reader/writer, DictReader/DictWriter; excel/excel-tab; explicit delimiter,
  quotechar, escapechar, doublequote, strict, skipinitialspace and basic quoting.
  QUOTE_MINIMAL/ALL/NONE are supported; QUOTE_NONNUMERIC, dialect registration
  and Sniffer are unsupported. Input must yield text lines; files opened with
  ordinary embedded open do not accept CPython's newline keyword. Use io.StringIO
  or plain text input and preserve quoted line breaks. Reader instances expose
  line_num; dictionary wrappers intentionally expose only the documented methods.
- statistics: mean/fmean, medians, mode/multimode, variances/deviations,
  geometric/harmonic means. Numerical data must be finite ints/floats; mode
  accepts hashable categories. No Decimal, Fraction, weights, KDE or NormalDist.
  Computations use VM float precision, not CPython exact rational accumulation.
- copy: built-in list/dict/tuple/set/bytearray and atomic types; shared and cyclic
  container references; explicit __copy__/__deepcopy__ hooks. No pickle/reducers
  or implicit arbitrary user-object reconstruction. Unsupported objects raise
  copy.Error. Hooks are responsible for memoizing their own recursive instances.
- contextlib: synchronous closing/nullcontext/suppress/contextmanager/ExitStack.
  Generator contexts are single-use. No async contexts, decorators, exception
  groups or redirected global streams. Exit callbacks get None traceback after
  a callback raises because this VM does not expose CPython traceback objects.
- textwrap: TextWrapper/wrap/fill collapse whitespace, handle indent, long-word
  and hyphen options; dedent, indent and shorten. No sentence heuristics, regex,
  max_lines, tab expansion options or full CPython whitespace fidelity. LF
  processing preserves CR inside existing CRLF nonblank lines. Tabs and spaces
  are distinct for dedent; wrapping measures characters, not terminal columns.
- base64: Base64/URL-safe/Base16, encodebytes/decodebytes. Bytes-like input and
  ASCII decode strings; malformed padding/strict nonalphabet input raise
  ValueError (the VM has no binascii.Error). No Base32/Base85 or legacy file API.
  Default decoding discards nonalphabet characters but rejects excess padding
  and data after padding, unlike CPython's permissive default in some cases.

## Verification

`python tool/verify_python_modules.py --library PATH` checks the manifest and
real automatic project bundle imports, compiles every source file with the
native compiler, runs positive/edge/error assertions and checks fresh VM module
state. Automatic mode also checks entry/root/lib/bundle precedence, project
package submodule refresh and cross-project import-state isolation. The verifier
runs 128 deterministic binary encoding vectors and 256 CSV formatting scenarios
inside the VM against host standard-library reference values; this is selected
API behavior evidence, not a full CPython compatibility claim.
`--explicit-path` is a separately labelled behavior-only mode for an old
DLL; it cannot prove automatic import integration. Reports include DLL,
manifest and suite SHA256 hashes. Run the portable suite on the installed OHOS
VM independently; host success never establishes an OHOS device pass.
