"""Copy containers and explicit user protocols, without pickle/reducers.

MIT; Qfli contributors.
"""


class Error(Exception):
    pass


_function_types = (type(lambda: None), type(len), type([].append))


def _atomic(value):
    return isinstance(value, (int, float, complex, bool, str, bytes,
                              type(None), type, range) + _function_types)


def copy(value):
    cls = type(value)
    if _atomic(value) or cls is tuple:
        return value
    if cls in (list, dict, set, bytearray):
        return cls(value)
    hook = getattr(value, "__copy__", None)
    if hook is not None:
        return hook()
    raise Error("unsupported object; implement __copy__")


def deepcopy(value, memo=None):
    if memo is None:
        memo = {}
    identity = id(value)
    if identity in memo:
        return memo[identity]
    if _atomic(value):
        return value
    cls = type(value)
    if cls is list:
        result = []
        memo[identity] = result
        result.extend(deepcopy(item, memo) for item in value)
    elif cls is dict:
        result = {}
        memo[identity] = result
        for key, item in value.items():
            result[deepcopy(key, memo)] = deepcopy(item, memo)
    elif cls is tuple:
        items = [deepcopy(item, memo) for item in value]
        if identity in memo:
            return memo[identity]
        result = tuple(items)
    elif cls is set:
        result = set()
        memo[identity] = result
        for item in value:
            result.add(deepcopy(item, memo))
    elif cls is bytearray:
        result = bytearray(value)
    else:
        hook = getattr(value, "__deepcopy__", None)
        if hook is None:
            raise Error("unsupported object; implement __deepcopy__")
        result = hook(memo)
    memo[identity] = result
    return result
