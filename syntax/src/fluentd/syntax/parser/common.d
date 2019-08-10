module fluentd.syntax.parser.common;

import std.algorithm.comparison: among;

package nothrow pure @safe @nogc:

bool _isUpper(char c) nothrow @nogc {
    return uint(c - 'A') < 26u;
}

bool _isAlpha(char c) {
    return uint((c | 0x20) - 'a') < 26u;
}

bool _isDigit(char c) {
    return uint(c - '0') < 10u;
}

bool _isHexDigit(char c) {
    return _isDigit(c) || uint((c | 0x20) - 'a') < 6u;
}

bool _isIdent(char c) {
    return _isAlpha(c) || _isDigit(c) || c.among!('-', '_');
}

bool _isCallee(char c) {
    return _isUpper(c) || _isDigit(c) || c.among!('-', '_');
}

bool _isEntryStart(char c) {
    return _isAlpha(c) || c.among!('-', '#');
}
