"""Plain text wrapping for the embedded VM. MIT; Qfli contributors.

wrap/fill collapse whitespace; supports width, initial/subsequent indentation
and long-word/hyphen breaking. No sentence heuristics, max_lines or regex.
dedent and indent preserve LF line endings (and CR in existing CRLF lines).
"""


class TextWrapper:
    def __init__(self, width=70, initial_indent="", subsequent_indent="",
                 break_long_words=True, break_on_hyphens=True):
        self.width = width
        self.initial_indent = initial_indent
        self.subsequent_indent = subsequent_indent
        self.break_long_words = break_long_words
        self.break_on_hyphens = break_on_hyphens

    def wrap(self, text):
        if not isinstance(self.width, int) or self.width <= 0:
            raise ValueError("width must be a positive integer")
        words = text.split()
        if not words:
            return []
        lines = []
        current = ""
        indent = self.initial_indent
        index = 0
        while index < len(words):
            word = words[index]
            available = self.width - len(indent) - len(current) - bool(current)
            if len(word) <= available:
                current += (" " if current else "") + word
                index += 1
                continue
            split = -1
            if self.break_on_hyphens and available > 0:
                split = word.rfind("-", 0, available)
            if split > 0:
                take = split + 1
            elif self.break_long_words and len(word) > max(1, self.width - len(indent)):
                take = max(1, available) if not current else max(0, available)
            else:
                take = 0
            if take:
                current += (" " if current else "") + word[:take]
                words[index] = word[take:]
            elif not current:
                current = word
                index += 1
            lines.append(indent + current)
            current = ""
            indent = self.subsequent_indent
        if current:
            lines.append(indent + current)
        return lines

    def fill(self, text):
        return "\n".join(self.wrap(text))


def wrap(text, width=70, **kwargs):
    return TextWrapper(width, **kwargs).wrap(text)


def fill(text, width=70, **kwargs):
    return TextWrapper(width, **kwargs).fill(text)


def shorten(text, width, *, placeholder=" [...]"):
    if not isinstance(width, int) or width <= 0:
        raise ValueError("width must be a positive integer")
    if len(placeholder.lstrip()) > width:
        raise ValueError("placeholder too large for width")
    words = text.split()
    collapsed = " ".join(words)
    if len(collapsed) <= width:
        return collapsed
    result = ""
    for word in words:
        candidate = result + (" " if result else "") + word
        if len(candidate) + len(placeholder) > width:
            break
        result = candidate
    return result + placeholder if result else placeholder.lstrip()


def dedent(text):
    lines = text.split("\n")
    margin = None
    for index, line in enumerate(lines):
        if not line.strip():
            lines[index] = ""
            continue
        indent = line[:len(line) - len(line.lstrip(" \t"))]
        if margin is None:
            margin = indent
        else:
            length = min(len(margin), len(indent))
            index = 0
            while index < length and margin[index] == indent[index]:
                index += 1
            margin = margin[:index]
    if margin:
        lines = [line[len(margin):] if line else line for line in lines]
    return "\n".join(lines)


def indent(text, prefix, predicate=None):
    lines = text.split("\n")
    for index in range(len(lines)):
        line = lines[index]
        if not line and index == len(lines) - 1:
            continue
        original = line + ("\n" if index < len(lines) - 1 else "")
        if (predicate(original) if predicate is not None else line.strip()):
            lines[index] = prefix + line
    return "\n".join(lines)
