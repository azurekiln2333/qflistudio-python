"""Lazy iterable helpers adapted from micropython-lib 0.2.3.

tee has independent queues; infinite iterables require bounded consumption.
"""


def count(start=0, step=1):
    while True:
        yield start
        start += step


def cycle(iterable):
    saved = []
    for item in iterable:
        saved.append(item)
        yield item
    while saved:
        yield from saved


def repeat(item, times=None):
    if times is None:
        while True:
            yield item
    else:
        for _ in range(times):
            yield item


def chain(*iterables):
    for items in iterables:
        yield from items


def islice(iterable, *args):
    if not 1 <= len(args) <= 3:
        raise TypeError("islice expected 2 to 4 arguments")
    start = 0 if len(args) == 1 or args[0] is None else args[0]
    stop = args[0] if len(args) == 1 else args[1]
    step = 1 if len(args) < 3 or args[2] is None else args[2]
    if not isinstance(start, int) or start < 0:
        raise ValueError("start must be a non-negative integer")
    if stop is not None and (not isinstance(stop, int) or stop < 0):
        raise ValueError("stop must be a non-negative integer or None")
    if not isinstance(step, int) or step <= 0:
        raise ValueError("step must be a positive integer")
    it = iter(iterable)
    index = 0
    target = start
    while stop is None or index < max(start, stop):
        try:
            value = next(it)
        except StopIteration:
            return
        if index == target and (stop is None or index < stop):
            yield value
            target += step
        index += 1


def tee(iterable, n=2):
    if not isinstance(n, int):
        raise TypeError("n must be an integer")
    if n < 0:
        raise ValueError("n must be >= 0")
    source = iter(iterable)
    queues = [[] for _ in range(n)]
    def branch(queue):
        while True:
            if not queue:
                try:
                    value = next(source)
                except StopIteration:
                    return
                for other in queues:
                    other.append(value)
            yield queue.pop(0)
    return tuple(branch(queue) for queue in queues)


def starmap(function, iterable):
    for args in iterable:
        yield function(*args)


_missing = object()


def accumulate(iterable, func=None, *, initial=_missing):
    it = iter(iterable)
    if initial is _missing:
        try:
            total = next(it)
        except StopIteration:
            return
    else:
        total = initial
    yield total
    for item in it:
        total = total + item if func is None else func(total, item)
        yield total


def takewhile(predicate, iterable):
    for item in iterable:
        if not predicate(item):
            return
        yield item


def dropwhile(predicate, iterable):
    it = iter(iterable)
    for item in it:
        if not predicate(item):
            yield item
            break
    yield from it


def filterfalse(predicate, iterable):
    if predicate is None:
        predicate = bool
    for item in iterable:
        if not predicate(item):
            yield item


def compress(data, selectors):
    for item, selected in zip(data, selectors):
        if selected:
            yield item


def product(*iterables, repeat=1):
    if not isinstance(repeat, int):
        raise TypeError("repeat must be an integer")
    if repeat < 0:
        raise ValueError("repeat must be non-negative")
    pools = [tuple(x) for x in iterables] * repeat
    if any(not pool for pool in pools):
        return
    indices = [0] * len(pools)
    while True:
        yield tuple(pools[i][indices[i]] for i in range(len(pools)))
        for i in range(len(pools) - 1, -1, -1):
            indices[i] += 1
            if indices[i] < len(pools[i]):
                break
            indices[i] = 0
        else:
            return
