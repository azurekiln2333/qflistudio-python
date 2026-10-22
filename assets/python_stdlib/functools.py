"""Offline functional helpers adapted from micropython-lib 0.1.0.

No stub wraps/update_wrapper or wrapper introspection attributes.
"""

_missing = object()


def partial(func, *args, **kwargs):
    if not callable(func):
        raise TypeError("first argument must be callable")
    def call(*more_args, **more_kwargs):
        kw = kwargs.copy()
        kw.update(more_kwargs)
        return func(*(args + more_args), **kw)
    return call


def reduce(function, iterable, initializer=_missing):
    it = iter(iterable)
    if initializer is _missing:
        try:
            value = next(it)
        except StopIteration:
            raise TypeError("reduce() of empty iterable with no initial value")
    else:
        value = initializer
    for element in it:
        value = function(value, element)
    return value


def lru_cache(*args, maxsize=128, typed=False):
    if maxsize is not None:
        if not isinstance(maxsize, int):
            raise TypeError("maxsize must be an integer or None")
        maxsize = max(0, maxsize)
    def decorate(func):
        values = {}
        order = []
        def call(*inner_args, **inner_kwargs):
            keys = tuple(sorted(inner_kwargs.items()))
            key = (inner_args, keys)
            if typed:
                key += (tuple(type(x) for x in inner_args),
                        tuple(type(x[1]) for x in keys))
            if key in values:
                if maxsize:
                    order.remove(key)
                    order.append(key)
                return values[key]
            result = func(*inner_args, **inner_kwargs)
            # A recursive call can fill this key while the wrapped function runs.
            # Keep its existing cache/order entry instead of appending it twice.
            if maxsize != 0 and key not in values:
                if maxsize and len(order) >= maxsize:
                    del values[order.pop(0)]
                values[key] = result
                if maxsize:
                    order.append(key)
            return result
        return call
    if args:
        if len(args) != 1 or not callable(args[0]):
            raise TypeError("use @lru_cache or @lru_cache(maxsize=N)")
        return decorate(args[0])
    return decorate


def cache(func):
    return lru_cache(maxsize=None)(func)
