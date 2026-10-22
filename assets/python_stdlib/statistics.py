"""Descriptive statistics for finite int/float data. MIT Qfli contributors.

No Decimal, Fraction, weights, KDE or NormalDist. Arithmetic uses VM floats.
"""

import math


class StatisticsError(ValueError):
    pass


def _data(data, minimum=1):
    values = list(data)
    if len(values) < minimum:
        raise StatisticsError("not enough data points")
    for value in values:
        if not isinstance(value, (int, float)):
            raise TypeError("only int and float data are supported")
        if not math.isfinite(value):
            raise StatisticsError("data must be finite")
    return values


def mean(data):
    values = _data(data)
    return sum(values) / len(values)


def fmean(data):
    return float(mean(data))


def median(data):
    values = sorted(_data(data))
    middle = len(values) // 2
    if len(values) % 2:
        return values[middle]
    return (values[middle - 1] + values[middle]) / 2


def median_low(data):
    values = sorted(_data(data))
    return values[(len(values) - 1) // 2]


def median_high(data):
    values = sorted(_data(data))
    return values[len(values) // 2]


def multimode(data):
    counts = {}
    order = []
    highest = 0
    for value in data:
        if value not in counts:
            order.append(value)
        count = counts.get(value, 0) + 1
        counts[value] = count
        highest = max(highest, count)
    return [value for value in order if counts[value] == highest]


def mode(data):
    values = multimode(data)
    if not values:
        raise StatisticsError("no mode for empty data")
    return values[0]


def pvariance(data, mu=None):
    values = _data(data)
    center = mean(values) if mu is None else mu
    return sum((value - center) ** 2 for value in values) / len(values)


def variance(data, xbar=None):
    values = _data(data, 2)
    center = mean(values) if xbar is None else xbar
    return sum((value - center) ** 2 for value in values) / (len(values) - 1)


def pstdev(data, mu=None):
    return math.sqrt(pvariance(data, mu))


def stdev(data, xbar=None):
    return math.sqrt(variance(data, xbar))


def geometric_mean(data):
    values = _data(data)
    if any(value <= 0 for value in values):
        raise StatisticsError("geometric mean requires positive data")
    return math.exp(sum(math.log(value) for value in values) / len(values))


def harmonic_mean(data):
    values = _data(data)
    if any(value < 0 for value in values):
        raise StatisticsError("harmonic mean requires non-negative data")
    if 0 in values:
        return 0
    return len(values) / sum(1 / value for value in values)
