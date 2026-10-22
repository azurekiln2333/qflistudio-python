"""Synchronous resource management; no async contexts or exception groups.

MIT; Qfli contributors.
"""


class closing:
    def __init__(self, thing):
        self.thing = thing
    def __enter__(self):
        return self.thing
    def __exit__(self, *exc):
        self.thing.close()


class nullcontext:
    def __init__(self, enter_result=None):
        self.enter_result = enter_result
    def __enter__(self):
        return self.enter_result
    def __exit__(self, *exc):
        return False


class suppress:
    def __init__(self, *exceptions):
        self.exceptions = exceptions
    def __enter__(self):
        return None
    def __exit__(self, exc_type, value, traceback):
        return exc_type is not None and issubclass(exc_type, self.exceptions)


class _GeneratorContextManager:
    def __init__(self, generator):
        self.generator = generator
    def __enter__(self):
        try:
            return next(self.generator)
        except StopIteration:
            raise RuntimeError("generator did not yield")
    def __exit__(self, exc_type, value, traceback):
        if exc_type is None:
            try:
                next(self.generator)
            except StopIteration:
                return False
            self.generator.close()
            raise RuntimeError("generator did not stop")
        if value is None:
            value = exc_type()
        try:
            self.generator.throw(value)
        except StopIteration as stopped:
            return stopped is not value
        except BaseException as raised:
            if raised is value:
                return False
            raise
        self.generator.close()
        raise RuntimeError("generator did not stop after throw")


def contextmanager(function):
    def enter(*args, **kwargs):
        return _GeneratorContextManager(function(*args, **kwargs))
    return enter


class ExitStack:
    def __init__(self):
        self.callbacks = []
    def __enter__(self):
        return self
    def push(self, exit):
        method = getattr(exit, "__exit__", None)
        self.callbacks.append(method if method is not None else exit)
        return exit
    def callback(self, function, *args, **kwargs):
        def exit(*exc):
            function(*args, **kwargs)
            return False
        self.callbacks.append(exit)
        return function
    def enter_context(self, context):
        result = context.__enter__()
        self.push(context)
        return result
    def pop_all(self):
        result = ExitStack()
        result.callbacks = self.callbacks
        self.callbacks = []
        return result
    def close(self):
        self.__exit__(None, None, None)
    def __exit__(self, exc_type, value, traceback):
        received = exc_type is not None
        suppressed = False
        pending = False
        while self.callbacks:
            callback = self.callbacks.pop()
            try:
                if callback(exc_type, value, traceback):
                    suppressed = True
                    pending = False
                    exc_type, value, traceback = None, None, None
            except BaseException as raised:
                exc_type, value, traceback = type(raised), raised, None
                pending = True
        if pending:
            raise value
        return received and suppressed
