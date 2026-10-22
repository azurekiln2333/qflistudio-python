"""Base64/Base16 byte encodings, including strict validation and URL alphabet.

No Base32, Base85 or file-based legacy API. MIT; Qfli contributors.
"""

import binascii

_alphabet = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"


def _input(value, text=False):
    if text and isinstance(value, str):
        if any(ord(char) > 127 for char in value):
            raise ValueError("only ASCII input is supported")
        return value.encode()
    if not isinstance(value, (bytes, bytearray, memoryview)):
        raise TypeError("expected a bytes-like object")
    return bytes(value)


def _altchars(value):
    value = _input(value, True)
    if len(value) != 2:
        raise ValueError("altchars must contain exactly two bytes")
    return value


def b64encode(data, altchars=None):
    data = _input(data)
    alphabet = _alphabet if altchars is None else _alphabet[:62] + _altchars(altchars)
    output = bytearray()
    for index in range(0, len(data), 3):
        chunk = data[index:index + 3]
        value = chunk[0] << 16
        if len(chunk) > 1:
            value |= chunk[1] << 8
        if len(chunk) > 2:
            value |= chunk[2]
        output.append(alphabet[(value >> 18) & 63])
        output.append(alphabet[(value >> 12) & 63])
        output.append(alphabet[(value >> 6) & 63] if len(chunk) > 1 else 61)
        output.append(alphabet[value & 63] if len(chunk) > 2 else 61)
    return bytes(output)


def b64decode(data, altchars=None, validate=False):
    data = _input(data, True)
    if altchars is not None:
        alt = _altchars(altchars)
        data = bytes(43 if char == alt[0] else 47 if char == alt[1] else char for char in data)
    clean = bytearray()
    for char in data:
        if char in _alphabet or char == 61:
            clean.append(char)
        elif validate:
            raise ValueError("non-base64 digit found")
    data = bytes(clean)
    if not data:
        return b""
    pad = data.find(b"=")
    if pad >= 0:
        tail = data[pad:]
        if tail not in (b"=", b"==") or len(data) % 4 or pad % 4 not in (2, 3):
            raise ValueError("incorrect padding")
        if len(tail) != 4 - pad % 4:
            raise ValueError("incorrect padding")
        data = data[:pad]
    elif len(data) % 4:
        raise ValueError("incorrect padding")
    output = bytearray()
    bits = 0
    count = 0
    for char in data:
        bits = (bits << 6) | _alphabet.find(bytes([char]))
        count += 6
        if count >= 8:
            count -= 8
            output.append((bits >> count) & 255)
            bits &= (1 << count) - 1
    return bytes(output)


def standard_b64encode(data):
    return b64encode(data)


def standard_b64decode(data):
    return b64decode(data)


def urlsafe_b64encode(data):
    return b64encode(data, b"-_")


def urlsafe_b64decode(data):
    return b64decode(data, b"-_")


def b16encode(data):
    return binascii.hexlify(_input(data)).upper()


def b16decode(data, casefold=False):
    data = _input(data, True)
    if casefold:
        data = data.upper()
    if len(data) % 2 or any(char not in b"0123456789ABCDEF" for char in data):
        raise ValueError("invalid base16 data")
    return binascii.unhexlify(data)


def encodebytes(data):
    data = _input(data)
    return b"".join(b64encode(data[i:i + 57]) + b"\n" for i in range(0, len(data), 57))


def decodebytes(data):
    return b64decode(_input(data))
