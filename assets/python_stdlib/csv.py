"""Offline CSV reader/writer with quoted multiline fields and dict rows.

Supports excel/excel-tab and explicit format arguments. No dialect registry,
Sniffer or QUOTE_NONNUMERIC conversion. MIT; Qfli contributors.
"""

QUOTE_MINIMAL = 0
QUOTE_ALL = 1
QUOTE_NONE = 3


class Error(Exception):
    pass


def _format(dialect, delimiter, quotechar, escapechar, doublequote, quoting):
    if dialect not in ("excel", "excel-tab"):
        raise Error("supported dialects: excel, excel-tab")
    if delimiter is None:
        delimiter = "\t" if dialect == "excel-tab" else ","
    for value in (delimiter, quotechar, escapechar):
        if value is not None and (not isinstance(value, str) or len(value) != 1):
            raise TypeError("delimiter, quotechar and escapechar must be single characters")
    if delimiter in ("\r", "\n"):
        raise ValueError("newline cannot be a delimiter")
    if quoting not in (QUOTE_MINIMAL, QUOTE_ALL, QUOTE_NONE):
        raise ValueError("unsupported quoting mode")
    if quotechar is None and quoting != QUOTE_NONE:
        raise TypeError("quotechar required when quoting is enabled")
    return delimiter


class reader:
    def __init__(self, lines, dialect="excel", *, delimiter=None,
                 quotechar='"', escapechar=None, doublequote=True,
                 skipinitialspace=False, strict=False, quoting=QUOTE_MINIMAL):
        self.delimiter = _format(dialect, delimiter, quotechar, escapechar,
                                 doublequote, quoting)
        self.line_num = 0
        self.rows = self._read(iter(lines), quotechar, escapechar,
                               doublequote, skipinitialspace, strict, quoting)

    def __iter__(self):
        return self

    def __next__(self):
        return next(self.rows)

    def _read(self, lines, quote, escape, double, skip, strict, quoting):
        row = []
        field = ""
        started = False
        quoted = False
        after_quote = False
        escaped = False
        continued = False
        for line in lines:
            self.line_num += 1
            if not isinstance(line, str):
                raise Error("CSV input must yield strings")
            ended = False
            continued = False
            index = 0
            while index < len(line):
                char = line[index]
                index += 1
                if ended:
                    if char not in "\r\n":
                        raise Error("new-line character seen in unquoted field")
                    continue
                continued = False
                if escaped:
                    field += char
                    escaped = False
                    started = True
                    continued = char in "\r\n"
                    continue
                if after_quote and char != self.delimiter and char not in "\r\n":
                    if strict:
                        raise Error("delimiter expected after closing quote")
                    field += char
                    after_quote = False
                    started = True
                    continue
                if escape is not None and char == escape:
                    escaped = True
                    started = True
                    continue
                if quoted:
                    if char == quote:
                        if double and index < len(line) and line[index] == quote:
                            field += quote
                            index += 1
                        else:
                            quoted = False
                            after_quote = double
                    else:
                        field += char
                    continue
                if char == self.delimiter:
                    row.append(field)
                    field = ""
                    started = False
                    after_quote = False
                elif char in "\r\n":
                    if started or row:
                        row.append(field)
                    yield row
                    row, field, started, after_quote = [], "", False, False
                    ended = True
                elif not started and char == " " and skip:
                    continue
                elif not started and quote is not None and char == quote and quoting != QUOTE_NONE:
                    started = True
                    quoted = True
                else:
                    field += char
                    started = True
            if not quoted and not escaped and not ended and not continued:
                if started or row:
                    row.append(field)
                yield row
                row, field, started, after_quote = [], "", False, False
        if quoted or escaped or continued:
            if strict:
                raise Error("unexpected end of CSV data")
            if escaped:
                field += "\n"
            row.append(field)
            yield row


class writer:
    def __init__(self, file, dialect="excel", *, delimiter=None,
                 quotechar='"', escapechar=None, doublequote=True,
                 lineterminator="\r\n", quoting=QUOTE_MINIMAL):
        self.delimiter = _format(dialect, delimiter, quotechar, escapechar,
                                 doublequote, quoting)
        self.file, self.quote, self.escape = file, quotechar, escapechar
        self.double, self.ending, self.quoting = doublequote, lineterminator, quoting
        if not isinstance(lineterminator, str):
            raise TypeError("lineterminator must be a string")

    def writerow(self, row):
        fields = ["" if value is None else str(value) for value in row]
        output = []
        for field in fields:
            quote = self.quoting == QUOTE_ALL or (
                self.quoting == QUOTE_MINIMAL and (
                    len(fields) == 1 and not field or any(
                        c == self.delimiter or c in "\r\n" or (c == self.quote and self.double)
                        or c in self.ending for c in field)))
            result = ""
            for char in field:
                if self.escape is not None and char == self.escape:
                    result += self.escape + char
                elif char == self.quote and self.quoting != QUOTE_NONE:
                    if self.double:
                        result += char + char
                    elif self.escape is not None:
                        result += self.escape + char
                    else:
                        raise Error("escapechar required for quotes")
                elif self.quoting == QUOTE_NONE and (
                        char == self.delimiter or char == self.quote
                        or char in "\r\n" or char in self.ending):
                    if self.escape is None:
                        raise Error("escapechar required")
                    result += self.escape + char
                else:
                    result += char
            if quote:
                result = self.quote + result + self.quote
            elif len(fields) == 1 and not field and self.quoting == QUOTE_NONE:
                raise Error("single empty field must be quoted")
            output.append(result)
        return self.file.write(self.delimiter.join(output) + self.ending)

    def writerows(self, rows):
        for row in rows:
            self.writerow(row)


class DictReader:
    def __init__(self, lines, fieldnames=None, restkey=None, restval=None, **kwargs):
        self.reader = reader(lines, **kwargs)
        self.fieldnames = None if fieldnames is None else list(fieldnames)
        self.restkey, self.restval = restkey, restval

    def __iter__(self):
        return self

    def __next__(self):
        if self.fieldnames is None:
            self.fieldnames = next(self.reader)
        row = next(self.reader)
        while not row:
            row = next(self.reader)
        result = {name: self.restval for name in self.fieldnames}
        result.update(zip(self.fieldnames, row))
        if len(row) > len(self.fieldnames):
            result[self.restkey] = row[len(self.fieldnames):]
        return result


class DictWriter:
    def __init__(self, file, fieldnames, restval="", extrasaction="raise", **kwargs):
        if extrasaction.lower() not in ("raise", "ignore"):
            raise ValueError("extrasaction must be raise or ignore")
        self.fieldnames = list(fieldnames)
        self.restval, self.extrasaction = restval, extrasaction.lower()
        self.writer = writer(file, **kwargs)

    def writeheader(self):
        return self.writer.writerow(self.fieldnames)

    def writerow(self, row):
        if self.extrasaction == "raise" and any(key not in self.fieldnames for key in row):
            raise ValueError("dict contains fields not in fieldnames")
        return self.writer.writerow([row.get(key, self.restval) for key in self.fieldnames])

    def writerows(self, rows):
        for row in rows:
            self.writerow(row)
