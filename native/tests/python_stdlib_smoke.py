"""Portable behavior suite for Qfli's bundled subset (MicroPython 1.24.1).

Copy this and the bundle into an app project and run on the installed VM for
device evidence. Host ctypes execution alone does not prove OHOS behavior.
"""

_passed = 0


def _check(name, condition):
    global _passed
    if not condition:
        raise AssertionError(name)
    _passed += 1
    print("PASS", name)


def _equal(name, actual, expected):
    _check(name, actual == expected)


def _raises(name, kind, function, *args, **kwargs):
    try:
        function(*args, **kwargs)
    except kind:
        _check(name, True)
        return
    raise AssertionError(name + " did not raise " + str(kind))


def test_bisect():
    import bisect as b
    for function in (b.bisect, b.bisect_right):
        _equal("bisect.right.duplicates", function([1, 2, 2, 4], 2), 3)
        _equal("bisect.right.empty", function([], 2), 0)
        _raises("bisect.right.negative", ValueError, function, [], 2, -1)
    _equal("bisect.left.duplicates", b.bisect_left([1, 2, 2, 4], 2), 1)
    _equal("bisect.left.bounds", b.bisect_left([1, 2, 2, 4], 2, 2, 3), 2)
    _raises("bisect.left.negative", ValueError, b.bisect_left, [], 2, -1)
    for function in (b.insort, b.insort_right, b.insort_left):
        values = [1, 3]
        function(values, 2)
        _equal("bisect.insort.order", values, [1, 2, 3])
        function(values, 2)
        _equal("bisect.insort.duplicate", values, [1, 2, 2, 3])
        _raises("bisect.insort.negative", ValueError, function, values, 2, -1)


def test_itertools():
    import itertools as i
    _equal("itertools.count", list(i.islice(i.count(2, 3), 4)), [2, 5, 8, 11])
    _equal("itertools.cycle.generator", list(i.islice(i.cycle(iter([1, 2])), 5)), [1, 2, 1, 2, 1])
    _equal("itertools.cycle.empty", list(i.cycle([])), [])
    _equal("itertools.repeat.finite", list(i.repeat("x", 2)), ["x", "x"])
    _equal("itertools.repeat.infinite", list(i.islice(i.repeat(7), 2)), [7, 7])
    _equal("itertools.repeat.negative", list(i.repeat(1, -1)), [])
    _equal("itertools.chain", list(i.chain([], [1], (2, 3))), [1, 2, 3])
    _equal("itertools.chain.empty", list(i.chain()), [])
    _equal("itertools.islice.open", list(i.islice(range(5), 2, None, 2)), [2, 4])
    _equal("itertools.islice.short", list(i.islice([1], 5)), [1])
    _equal("itertools.islice.empty", list(i.islice([1, 2], 0)), [])
    _raises("itertools.islice.zero-step", ValueError, list, i.islice([1], 0, 1, 0))
    _raises("itertools.islice.negative", ValueError, list, i.islice([], -1))
    a, b = i.tee(iter([1, 2, 3]))
    _equal("itertools.tee.independent-first", [next(a), next(a), next(b)], [1, 2, 1])
    _equal("itertools.tee.independent-rest", [list(a), list(b)], [[3], [2, 3]])
    _equal("itertools.tee.zero", i.tee([1], 0), ())
    _raises("itertools.tee.negative", ValueError, i.tee, [], -1)
    _equal("itertools.starmap", list(i.starmap(pow, [(2, 3), (3, 2)])), [8, 9])
    _equal("itertools.starmap.empty", list(i.starmap(pow, [])), [])
    _raises("itertools.starmap.arity", TypeError, list, i.starmap(pow, [(1,)]))
    _equal("itertools.accumulate", list(i.accumulate([1, 2, 3])), [1, 3, 6])
    _equal("itertools.accumulate.initial", list(i.accumulate([2, 3], lambda a, b: a * b, initial=1)), [1, 2, 6])
    _equal("itertools.accumulate.empty", list(i.accumulate([])), [])
    _equal("itertools.takewhile", list(i.takewhile(lambda x: x < 3, [1, 2, 3, 1])), [1, 2])
    _equal("itertools.dropwhile", list(i.dropwhile(lambda x: x < 3, [1, 3, 2])), [3, 2])
    _equal("itertools.filterfalse", list(i.filterfalse(None, [0, 1, "", "x"])), [0, ""])
    _equal("itertools.compress", list(i.compress("ABC", [1, 0, 1, 1])), ["A", "C"])
    _equal("itertools.product", list(i.product("AB", [1, 2])), [("A", 1), ("A", 2), ("B", 1), ("B", 2)])
    _equal("itertools.product.zero", list(i.product("AB", repeat=0)), [()])
    _equal("itertools.product.empty", list(i.product([], [1])), [])
    _raises("itertools.product.negative", ValueError, list, i.product("A", repeat=-1))
    _equal("itertools.takewhile.empty", list(i.takewhile(bool, [])), [])
    _equal("itertools.dropwhile.all", list(i.dropwhile(bool, [1, 2])), [])
    _equal("itertools.filterfalse.empty", list(i.filterfalse(None, [])), [])
    _equal("itertools.compress.short", list(i.compress("ABC", [True])), ["A"])
    _equal("itertools.accumulate.none-initial", list(i.accumulate([2], lambda a, b: b, initial=None)), [None, 2])
    _raises("itertools.takewhile.bad-predicate", TypeError, list, i.takewhile(None, [1]))
    _raises("itertools.dropwhile.bad-predicate", TypeError, list, i.dropwhile(None, [1]))
    _raises("itertools.filterfalse.bad-predicate", TypeError, list, i.filterfalse(1, [1]))
    _raises("itertools.compress.noniterable", TypeError, list, i.compress(1, []))
    _raises("itertools.chain.noniterable", TypeError, list, i.chain(1))
    _raises("itertools.count.non-numeric-step", TypeError, list, i.islice(i.count(1, "x"), 2))
    _raises("itertools.repeat.bad-times", TypeError, list, i.repeat(1, "x"))
    _raises("itertools.product.bad-repeat", TypeError, list, i.product([1], repeat="x"))
    _raises("itertools.islice.arity", TypeError, list, i.islice([1]))
    _raises("itertools.islice.bad-stop", ValueError, list, i.islice([1], None, "x"))
    _raises("itertools.tee.bad-count", TypeError, i.tee, [], "x")
    _equal("itertools.product.repeat", list(i.product([0, 1], repeat=2)), [(0, 0), (0, 1), (1, 0), (1, 1)])


def test_functools():
    import functools as f
    def add(a, b=1):
        return a + b
    _equal("functools.partial", f.partial(add, 2, b=3)(), 5)
    _equal("functools.partial.override", f.partial(add, 2, b=3)(b=4), 6)
    _raises("functools.partial.noncallable", TypeError, f.partial, 1)
    _equal("functools.reduce", f.reduce(add, [1, 2, 3]), 6)
    _equal("functools.reduce.empty.initial", f.reduce(add, [], 10), 10)
    _equal("functools.reduce.explicit-none", f.reduce(lambda a, b: b, [], None), None)
    _raises("functools.reduce.empty", TypeError, f.reduce, add, [])
    calls = []
    @f.lru_cache(maxsize=2)
    def square(value):
        calls.append(value)
        return value * value
    _equal("functools.lru_cache.result", [square(2), square(2), square(3)], [4, 4, 9])
    square(4)
    square(2)
    _equal("functools.lru_cache.eviction", calls, [2, 3, 4, 2])
    _raises("functools.lru_cache.unhashable", TypeError, square, [])
    _raises("functools.lru_cache.invalid-size", TypeError, f.lru_cache, maxsize="x")
    calls = []
    @f.cache
    def identity(value):
        calls.append(value)
        return value
    _equal("functools.cache", [identity(1), identity(1)], [1, 1])
    _equal("functools.cache.hit", calls, [1])
    calls = []
    @f.lru_cache(maxsize=0)
    def uncached(value):
        calls.append(value)
        return value
    uncached(1)
    uncached(1)
    _equal("functools.lru_cache.zero", calls, [1, 1])
    calls = []
    @f.lru_cache(typed=True)
    def typed(value):
        calls.append(type(value))
        return value
    typed(1)
    typed(1.0)
    _equal("functools.lru_cache.typed", len(calls), 2)
    calls = []
    @f.cache
    def keywords(**kwargs):
        calls.append(1)
        return kwargs["a"] + kwargs["b"]
    _equal("functools.cache.keyword-result", keywords(a=1, b=2), 3)
    _equal("functools.cache.sorted-keywords", keywords(b=2, a=1), 3)
    _equal("functools.cache.sorted-hit", len(calls), 1)
    _raises("functools.cache.unhashable", TypeError, keywords, a=[], b=2)
    entering = []
    @f.lru_cache(maxsize=2)
    def recursive_key(value):
        if value == 1 and not entering:
            entering.append(True)
            recursive_key(value)
        return value * 2
    _equal("functools.lru_cache.reentrant", recursive_key(1), 2)
    _equal("functools.lru_cache.reentrant-eviction", [recursive_key(2), recursive_key(3), recursive_key(1)], [4, 6, 2])
    _equal("functools.lru_cache.reentrant-recovery", recursive_key(4), 8)


def test_copy():
    import copy as c
    source = {"x": [1]}
    shallow = c.copy(source)
    deep = c.deepcopy(source)
    _check("copy.shallow.identity", shallow is not source and shallow["x"] is source["x"])
    _check("copy.deep.identity", deep is not source and deep["x"] is not source["x"])
    source["x"].append(2)
    _equal("copy.deep.isolation", deep, {"x": [1]})
    cycle = []
    cycle.append(cycle)
    cloned = c.deepcopy(cycle)
    _check("copy.deep.cycle", cloned is not cycle and cloned[0] is cloned)
    shared = [1]
    cloned = c.deepcopy([shared, shared])
    _check("copy.deep.shared", cloned[0] is cloned[1] and cloned[0] is not shared)
    loop = []
    tup = (loop,)
    loop.append(tup)
    cloned = c.deepcopy(tup)
    _check("copy.deep.tuple-cycle", cloned[0][0] is cloned)
    _equal("copy.set", c.deepcopy({1, 2}), {1, 2})
    _equal("copy.bytearray", c.deepcopy(bytearray(b"ab")), bytearray(b"ab"))
    _equal("copy.atomic", c.copy(42), 42)
    class Item:
        def __copy__(self):
            return "shallow"
        def __deepcopy__(self, memo):
            return "deep"
    _equal("copy.protocol.shallow", c.copy(Item()), "shallow")
    _equal("copy.protocol.deep", c.deepcopy(Item()), "deep")
    class Unsupported:
        pass
    _raises("copy.unsupported.shallow", c.Error, c.copy, Unsupported())
    _raises("copy.unsupported.deep", c.Error, c.deepcopy, Unsupported())
    _check("copy.shallow.list", c.copy([1]) == [1])
    _equal("copy.shallow.set", c.copy({1}), {1})
    _equal("copy.shallow.bytearray", c.copy(bytearray(b"a")), bytearray(b"a"))
    _equal("copy.deep.empty", c.deepcopy([]), [])
    class Callable:
        def __call__(self):
            return 1
        def __copy__(self):
            return "copied-callable"
    _equal("copy.callable.protocol", c.copy(Callable()), "copied-callable")
    _check("copy.function", c.deepcopy(test_copy) is test_copy)


def test_contextlib():
    import contextlib as c
    closed = []
    class Resource:
        def close(self):
            closed.append(1)
    resource = Resource()
    with c.closing(resource) as value:
        _check("contextlib.closing.value", value is resource)
    _equal("contextlib.closing.closed", closed, [1])
    with c.nullcontext(42) as value:
        _equal("contextlib.nullcontext", value, 42)
    with c.suppress(ValueError):
        raise ValueError("expected")
    _check("contextlib.suppress.match", True)
    def mismatch():
        with c.suppress(ValueError):
            raise TypeError("expected")
    _raises("contextlib.suppress.propagates", TypeError, mismatch)
    events = []
    @c.contextmanager
    def managed():
        events.append("enter")
        try:
            yield 42
        finally:
            events.append("exit")
    with managed() as value:
        _equal("contextlib.contextmanager.value", value, 42)
    _equal("contextlib.contextmanager.cleanup", events, ["enter", "exit"])
    def exceptional():
        with managed():
            raise ValueError("expected")
    _raises("contextlib.contextmanager.propagates", ValueError, exceptional)
    _equal("contextlib.contextmanager.exception-cleanup", events[-2:], ["enter", "exit"])
    @c.contextmanager
    def suppressing():
        try:
            yield
        except ValueError:
            pass
    with suppressing():
        raise ValueError("suppressed")
    _check("contextlib.contextmanager.suppression", True)
    @c.contextmanager
    def no_yield():
        for _ in range(0):
            yield
    _raises("contextlib.contextmanager.missing-yield", RuntimeError, no_yield().__enter__)
    @c.contextmanager
    def two_yields():
        yield 1
        yield 2
    def double():
        with two_yields():
            pass
    _raises("contextlib.contextmanager.extra-yield", RuntimeError, double)
    events = []
    with c.ExitStack() as stack:
        stack.callback(events.append, 1)
        stack.callback(events.append, 2)
        _equal("contextlib.ExitStack.enter_context", stack.enter_context(c.nullcontext(7)), 7)
    _equal("contextlib.ExitStack.order", events, [2, 1])
    stack = c.ExitStack()
    stack.callback(events.append, 3)
    moved = stack.pop_all()
    stack.close()
    _equal("contextlib.ExitStack.pop_all.old-empty", events, [2, 1])
    moved.close()
    _equal("contextlib.ExitStack.pop_all.moved", events, [2, 1, 3])
    with c.ExitStack() as stack:
        stack.push(c.suppress(ValueError))
        raise ValueError("expected")
    _check("contextlib.ExitStack.suppresses", True)
    def callback_error():
        with c.ExitStack() as stack:
            stack.callback(events.append, 4)
            def fail():
                raise TypeError("callback")
            stack.callback(fail)
    _raises("contextlib.ExitStack.callback-error", TypeError, callback_error)
    _equal("contextlib.ExitStack.cleanup-after-error", events[-1], 4)
    closed = []
    def close_on_error():
        with c.closing(Resource()):
            raise ValueError("expected")
    _raises("contextlib.closing.error", ValueError, close_on_error)
    _equal("contextlib.closing.exception-cleanup", closed, [1])
    def null_error():
        with c.nullcontext():
            raise ValueError("expected")
    _raises("contextlib.nullcontext.propagates", ValueError, null_error)
    _raises("contextlib.closing.invalid-resource", AttributeError, c.closing(1).__exit__, None, None, None)
    _equal("contextlib.suppress.empty", c.suppress().__exit__(ValueError, ValueError(), None), False)
    events = []
    with c.ExitStack() as stack:
        stack.push(c.suppress(TypeError))
        def fail():
            raise TypeError("expected")
        stack.callback(fail)
    _check("contextlib.ExitStack.suppresses-callback-error", True)
    stack.close()
    _check("contextlib.ExitStack.repeated-close", True)


def test_statistics():
    import statistics as s
    _equal("statistics.mean", s.mean([1, 2, 6]), 3)
    _equal("statistics.fmean", s.fmean(iter([1, 2])), 1.5)
    _equal("statistics.median.odd", s.median([5, 1, 3]), 3)
    _equal("statistics.median.even", s.median([4, 1, 2, 3]), 2.5)
    _equal("statistics.median_low", s.median_low([4, 1, 2, 3]), 2)
    _equal("statistics.median_high", s.median_high([4, 1, 2, 3]), 3)
    _equal("statistics.mode.tie", s.mode(["b", "a", "a", "b"]), "b")
    _equal("statistics.multimode", s.multimode([1, 2, 2, 1, 3]), [1, 2])
    _equal("statistics.multimode.empty", s.multimode([]), [])
    _equal("statistics.pvariance", s.pvariance([1, 2, 3]), 2 / 3)
    _equal("statistics.variance", s.variance([1, 2, 3]), 1)
    _equal("statistics.stdev", s.stdev([1, 2, 3]), 1)
    _check("statistics.pstdev", abs(s.pstdev([1, 2, 3]) - (2 / 3) ** 0.5) < 1e-5)
    _check("statistics.geometric_mean", abs(s.geometric_mean([2, 8]) - 4) < 1e-5)
    _equal("statistics.harmonic_mean", s.harmonic_mean([2, 6]), 3)
    _equal("statistics.harmonic_mean.zero", s.harmonic_mean([0, 1]), 0)
    for function in (s.mean, s.fmean, s.median, s.median_low, s.median_high,
                     s.mode, s.pvariance, s.variance, s.stdev, s.pstdev,
                     s.geometric_mean, s.harmonic_mean):
        _raises("statistics.empty", s.StatisticsError, function, [])
    _raises("statistics.sample-too-short", s.StatisticsError, s.variance, [1])
    _raises("statistics.non-finite", s.StatisticsError, s.mean, [float("inf")])
    _raises("statistics.unsupported-type", TypeError, s.mean, ["1"])
    _raises("statistics.geometric-domain", s.StatisticsError, s.geometric_mean, [0, 1])
    _raises("statistics.harmonic-domain", s.StatisticsError, s.harmonic_mean, [-1, 0])
    for function in (s.mean, s.fmean, s.median, s.median_low, s.median_high,
                     s.pvariance, s.pstdev, s.geometric_mean, s.harmonic_mean):
        _equal("statistics.singleton", function([5]), 0 if function in (s.pvariance, s.pstdev) else 5)
    _equal("statistics.pvariance.mu", s.pvariance([1, 3], 2), 1)
    _equal("statistics.variance.xbar", s.variance([1, 3], 2), 2)
    _raises("statistics.mode.unhashable", TypeError, s.mode, [[]])
    _raises("statistics.multimode.unhashable", TypeError, s.multimode, [[]])


def test_string():
    import string as s
    _equal("string.ascii_lowercase", s.ascii_lowercase, "abcdefghijklmnopqrstuvwxyz")
    _equal("string.ascii_uppercase", s.ascii_uppercase, "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    _equal("string.ascii_letters", s.ascii_letters, s.ascii_lowercase + s.ascii_uppercase)
    _equal("string.digits", s.digits, "0123456789")
    _equal("string.hexdigits", s.hexdigits, "0123456789abcdefABCDEF")
    _equal("string.octdigits", s.octdigits, "01234567")
    _equal("string.whitespace", s.whitespace, " \t\n\r\v\f")
    _equal("string.punctuation", len(s.punctuation), 32)
    _equal("string.printable", len(s.printable), 100)
    _equal("string.translate", s.translate("abca", {97: 65, 98: None, 99: "see"}), "AseeA")
    _equal("string.translate.empty", s.translate("", {}), "")
    _raises("string.translate.invalid-codepoint", ValueError, s.translate, "a", {97: -1})


def test_textwrap():
    import textwrap as t
    _equal("textwrap.wrap", t.wrap("one two three", 7), ["one two", "three"])
    _equal("textwrap.fill", t.fill("one two three", 7), "one two\nthree")
    _equal("textwrap.empty", t.wrap(" \t\n", 3), [])
    _equal("textwrap.long-word", t.wrap("abcdef", 2), ["ab", "cd", "ef"])
    _equal("textwrap.keep-word", t.wrap("abcdef", 2, break_long_words=False), ["abcdef"])
    _equal("textwrap.hyphen", t.wrap("ab-cd", 3, break_long_words=False), ["ab-", "cd"])
    wrapper = t.TextWrapper(6, initial_indent=">", subsequent_indent="..")
    _equal("textwrap.TextWrapper.wrap", wrapper.wrap("one two three"), [">one", "..two", "..thre", "..e"])
    _equal("textwrap.TextWrapper.fill", wrapper.fill("one two"), ">one\n..two")
    _equal("textwrap.shorten", t.shorten("hello world again", 12), "hello [...]")
    _equal("textwrap.shorten.short", t.shorten(" a  b ", 8), "a b")
    _equal("textwrap.dedent", t.dedent("  a\n    b\n  \n"), "a\n  b\n\n")
    _equal("textwrap.dedent.mixed", t.dedent("\ta\n b"), "\ta\n b")
    _equal("textwrap.indent", t.indent("a\n\nb\n", "> "), "> a\n\n> b\n")
    _equal("textwrap.indent.predicate", t.indent("a\n\n", ">", lambda line: True), ">a\n>\n")
    _raises("textwrap.wrap.invalid-width", ValueError, t.wrap, "x", 0)
    _raises("textwrap.shorten.invalid-width", ValueError, t.shorten, "x", 0)
    _raises("textwrap.shorten.placeholder", ValueError, t.shorten, "long", 1)
    _equal("textwrap.dedent.blank", t.dedent("  \n \n"), "\n\n")
    _equal("textwrap.dedent.empty", t.dedent(""), "")
    _equal("textwrap.indent.empty", t.indent("", ">"), "")
    _equal("textwrap.wrap.no-hyphens", t.wrap("ab-cd", 3, break_long_words=False, break_on_hyphens=False), ["ab-cd"])
    _equal("textwrap.shorten.only-placeholder", t.shorten("longword word", 5, placeholder="..."), "...")
    _raises("textwrap.fill.invalid-width", ValueError, t.fill, "x", -1)
    _raises("textwrap.wrap.unsupported-option", TypeError, t.wrap, "x", expand_tabs=False)


def test_base64():
    import base64 as b
    vectors = [(b"", b""), (b"f", b"Zg=="), (b"fo", b"Zm8="),
               (b"foo", b"Zm9v"), (b"\x00\xff\xfb", b"AP/7")]
    for raw, encoded in vectors:
        _equal("base64.b64encode", b.b64encode(raw), encoded)
        _equal("base64.b64decode", b.b64decode(encoded), raw)
        _equal("base64.standard_b64encode", b.standard_b64encode(raw), encoded)
        _equal("base64.standard_b64decode", b.standard_b64decode(encoded), raw)
    _equal("base64.urlsafe_b64encode", b.urlsafe_b64encode(b"\xfb\xff"), b"-_8=")
    _equal("base64.urlsafe_b64decode", b.urlsafe_b64decode("-_8="), b"\xfb\xff")
    _equal("base64.b16encode", b.b16encode(b"\x00\xff"), b"00FF")
    _equal("base64.b16decode", b.b16decode("00FF"), b"\x00\xff")
    _equal("base64.b16decode.casefold", b.b16decode("ff", casefold=True), b"\xff")
    _equal("base64.encodebytes", b.encodebytes(b"a" * 58), b"YWFh" * 19 + b"\nYQ==\n")
    _equal("base64.decodebytes", b.decodebytes(b"Z m9v\n"), b"foo")
    _equal("base64.encodebytes.empty", b.encodebytes(b""), b"")
    _raises("base64.decode.strict", ValueError, b.b64decode, b"Z!g==", validate=True)
    _raises("base64.decode.padding", ValueError, b.b64decode, b"Zg=")
    _raises("base64.decode.trailing-data", ValueError, b.b64decode, b"Zg==AAAA", validate=True)
    _raises("base64.decode.unicode", ValueError, b.b64decode, "\u4e2d")
    _raises("base64.encode.text", TypeError, b.b64encode, "text")
    _raises("base64.altchars.invalid", ValueError, b.b64encode, b"a", b"-")
    _raises("base64.b16decode.lowercase", ValueError, b.b16decode, b"ff")
    _raises("base64.b16decode.odd", ValueError, b.b16decode, b"F")
    _equal("base64.b64encode.memoryview", b.b64encode(memoryview(b"foo")), b"Zm9v")
    _equal("base64.b64decode.bytearray", b.b64decode(bytearray(b"Zm9v")), b"foo")
    _equal("base64.b16encode.empty", b.b16encode(b""), b"")
    _equal("base64.b16decode.empty", b.b16decode(""), b"")
    _equal("base64.decodebytes.empty", b.decodebytes(b""), b"")
    for function in (b.b64encode, b.standard_b64encode, b.urlsafe_b64encode,
                     b.b16encode, b.encodebytes, b.decodebytes):
        _raises("base64.bytes-input-required", TypeError, function, 42)
    for function in (b.b64decode, b.standard_b64decode, b.urlsafe_b64decode,
                     b.b16decode):
        _raises("base64.decode-invalid-input", ValueError, function, b"x")
    _raises("base64.altchars.decode", ValueError, b.b64decode, b"AA==", b"x")


def test_csv():
    import csv as c
    import io
    _equal("csv.reader.basic", list(c.reader(["a,b\n", "1,2\n"])), [["a", "b"], ["1", "2"]])
    _equal("csv.reader.quoted", list(c.reader(['"a,b","c""d"\n'])), [["a,b", 'c"d']])
    _equal("csv.reader.multiline", list(c.reader(['"a\n', 'b",c\n'])), [["a\nb", "c"]])
    _equal("csv.reader.empty", list(c.reader(["\n", '""\n', "a,\n"])), [[], [""], ["a", ""]])
    _equal("csv.reader.custom", list(c.reader([" a; b"], delimiter=";", skipinitialspace=True)), [["a", "b"]])
    _equal("csv.reader.tab", list(c.reader(["a\tb"], dialect="excel-tab")), [["a", "b"]])
    _equal("csv.reader.escape", list(c.reader(["a\\,b,c"], escapechar="\\")), [["a,b", "c"]])
    for ending in ("\n", "\r"):
        _equal("csv.reader.escaped-newline-eof", list(c.reader(["a\\" + ending], escapechar="\\")), [["a" + ending]])
        _raises("csv.reader.strict-escaped-newline-eof", c.Error, list,
                c.reader(["a\\" + ending], escapechar="\\", strict=True))
    _equal("csv.reader.literal-after-quote", list(c.reader(['"a"\\x\n'], escapechar="\\")), [["a\\x"]])
    _raises("csv.reader.strict-after-quote-escape", c.Error, list,
            c.reader(['"a"\\x\n'], escapechar="\\", strict=True))
    _equal("csv.reader.no-double-quote-strict", list(c.reader(['"a"\\x\n'], escapechar="\\", doublequote=False, strict=True)), [["ax"]])
    _raises("csv.reader.unclosed", c.Error, list, c.reader(['"x'], strict=True))
    _raises("csv.reader.bad-quote", c.Error, list, c.reader(['"x"z'], strict=True))
    _raises("csv.reader.binary", c.Error, list, c.reader([b"a,b"]))
    _raises("csv.reader.invalid-delimiter", TypeError, c.reader, [], delimiter="xx")
    _raises("csv.reader.unsupported-dialect", c.Error, c.reader, [], dialect="unknown")
    _raises("csv.reader.unsupported-quoting", ValueError, c.reader, [], quoting=2)
    file = io.StringIO()
    writer = c.writer(file)
    writer.writerow(["a,b", 'c"d', None, 3])
    writer.writerows([[1, 2], ["x\ny", "z"]])
    _equal("csv.writer.rows", list(c.reader(io.StringIO(file.getvalue()))),
           [["a,b", 'c"d', "", "3"], ["1", "2"], ["x\ny", "z"]])
    file = io.StringIO()
    c.writer(file, quoting=c.QUOTE_ALL).writerow(["a", "b"])
    _equal("csv.writer.quote-all", file.getvalue(), '"a","b"\r\n')
    file = io.StringIO()
    c.writer(file, quoting=c.QUOTE_NONE, escapechar="\\").writerow(["a,b"])
    _equal("csv.writer.quote-none", file.getvalue(), "a\\,b\r\n")
    _raises("csv.writer.needs-escape", c.Error, c.writer(io.StringIO(), quoting=c.QUOTE_NONE).writerow, ["a,b"])
    _equal("csv.DictReader", list(c.DictReader(["a,b\n", "1\n", "2,3,4\n"], restkey="extra", restval="missing")),
           [{"a": "1", "b": "missing"}, {"a": "2", "b": "3", "extra": ["4"]}])
    file = io.StringIO()
    writer = c.DictWriter(file, ["a", "b"], restval="missing")
    writer.writeheader()
    writer.writerows([{"a": 1}, {"a": 2, "b": 3}])
    _equal("csv.DictWriter", list(c.reader(io.StringIO(file.getvalue()))),
           [["a", "b"], ["1", "missing"], ["2", "3"]])
    _raises("csv.DictWriter.extra-key", ValueError, writer.writerow, {"c": 3})
    _raises("csv.DictWriter.extrasaction", ValueError, c.DictWriter, io.StringIO(), [], extrasaction="bad")
    rows = c.reader(['"a\n', 'b",c\n'])
    _equal("csv.reader.line-count-row", next(rows), ["a\nb", "c"])
    _equal("csv.reader.line-count", rows.line_num, 2)
    file = io.StringIO()
    c.writer(file, doublequote=False, escapechar="\\").writerow(['a"b'])
    _equal("csv.writer.escape-quote", list(c.reader(io.StringIO(file.getvalue()), doublequote=False, escapechar="\\")), [['a"b']])
    _raises("csv.writer.quote-without-escape", c.Error, c.writer(io.StringIO(), doublequote=False).writerow, ['a"b'])
    _raises("csv.writer.empty-without-quote", c.Error, c.writer(io.StringIO(), quoting=c.QUOTE_NONE).writerow, [""])
    _raises("csv.writer.invalid-ending", TypeError, c.writer, io.StringIO(), lineterminator=1)
    _raises("csv.reader.quote-required", TypeError, c.reader, [], quotechar=None)
    _equal("csv.DictReader.explicit-columns", list(c.DictReader(["1,2"], fieldnames=["a", "b"])), [{"a": "1", "b": "2"}])
    file = io.StringIO()
    c.DictWriter(file, ["a"], extrasaction="ignore").writerow({"a": 1, "other": 2})
    _equal("csv.DictWriter.ignore-extra", file.getvalue(), "1\r\n")
    _equal("csv.reader.empty-input", list(c.reader([])), [])
    file = io.StringIO()
    c.writer(file, quoting=c.QUOTE_NONE, escapechar="\\").writerows([['  "\n\n'], [",", "\rbab"]])
    _equal("csv.writer.escaped-multiline", list(c.reader(io.StringIO(file.getvalue()), quoting=c.QUOTE_NONE, escapechar="\\")),
           [['  "\n\n'], [",", "\rbab"]])


def run():
    for test in (test_bisect, test_itertools, test_functools, test_copy,
                 test_contextlib, test_statistics, test_string, test_textwrap,
                 test_base64, test_csv):
        test()
    print("QFLI_STDLIB_PASS", _passed)


if __name__ == "__main__":
    run()
