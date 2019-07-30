module fluentd.parser.stream;

import std.algorithm.comparison: among;
import std.functional: unaryFun;
import std.traits: ifTestable;

import fluentd.parser.span;

private nothrow pure @safe @nogc:

bool _isAlpha(char c) {
    return uint((c | 0x20) - 'a') < 26u;
}

bool _isDigit(char c) {
    return uint(c - '0') < 10u;
}

bool _isIdent(char c) {
    return _isAlpha(c) || _isDigit(c) || c.among!('-', '_');
}

bool _isEntryStart(char c) {
    return _isAlpha(c) || c.among!('-', '#');
}

public enum TextElementTermination: ubyte {
    placeableStart,
    lf,
    crlf,
    eof,
    unpairedBrace,
}

public struct ParserStream {
nothrow pure @nogc:
    private {
        string _source;
        ByteOffset _pos;
    }

    invariant {
        assert(_pos <= _source.length);
    }

    this(string source) {
        _source = source;
    }

    @property string source() const {
        return _source;
    }

    @property ByteOffset pos() const {
        return _pos;
    }

    @property bool eof() const {
        return _pos == _source.length;
    }

    void backtrack(ByteOffset point)
    in {
        assert(point <= _pos, "Cannot backtrack forwards");
    }
    do {
        _pos = point;
    }

    string slice(ByteOffset from) const {
        return _source[from .. _pos];
    }

    string slice(ByteOffset from, ByteOffset to) const {
        return _source[from .. to];
    }

    // DMD's optimizer is not as advanced as LDC's, so we need to give it a hint.
    private mixin template _fastAccess() {
        const s = _source;
        auto i = _pos;
    }

    void assertLast(alias pred)() const if (ifTestable!(typeof(unaryFun!pred('x')))) {
        assert(_pos && unaryFun!pred(_source[_pos - 1]), "Lookbehind failed");
    }

    bool test(char c) const {
        mixin _fastAccess;
        return i < s.length && s[i] == c;
    }

    bool test(alias pred)() const if (ifTestable!(typeof(unaryFun!pred('x')))) {
        mixin _fastAccess;
        return i < s.length && unaryFun!pred(s[i]);
    }

    bool skip(char c) {
        mixin _fastAccess;
        if (i == s.length || s[i] != c)
            return false;
        _pos = i + 1;
        return true;
    }

    bool skip(alias pred)() if (ifTestable!(typeof(unaryFun!pred('x')))) {
        mixin _fastAccess;
        if (i == s.length || !unaryFun!pred(s[i]))
            return false;
        _pos = i + 1;
        return true;
    }

    bool skipLineEnd() {
        mixin _fastAccess;
        if (i == s.length)
            return true;
        const cur = s[i];
        if (cur == '\n') {
            _pos = i + 1;
            return true;
        } else if (cur == '\r' && i + 1 < s.length && s[i + 1] == '\n') {
            _pos = i + 2;
            return true;
        }
        return false;
    }

    bool skipBlankInline() {
        mixin _fastAccess;
        if (i == s.length || s[i] != ' ')
            return false;
        scope(success) _pos = i;
        while (++i < s.length && s[i] == ' ') { }
        return true;
    }

    bool skipBlankBlock() {
        mixin _fastAccess;
        scope(success) _pos = i;
        bool found;
        while (true) {
            const lineStart = i;
            while (true) {
                if (i == s.length)
                    return true;
                if (s[i] != ' ') {
                    if ((s[i] != '\r' || ++i < s.length) && s[i] == '\n')
                        break;
                    i = lineStart;
                    return found;
                }
                i++;
            }
            found = true;
            i++; // \n
        }
    }

    void skipBlank() {
        mixin _fastAccess;
        scope(success) _pos = i;
        while (i < s.length) {
            if (!s[i].among!(' ', '\n')) {
                if (s[i] == '\r' && i + 1 < s.length && s[i + 1] == '\n') {
                    i += 2;
                    continue;
                }
                break;
            }
            i++;
        }
    }

    void skipJunk() {
        mixin _fastAccess;
        if (i == s.length)
            return;
        char c = s[i];
        if ((!i || s[i - 1] == '\n') && _isEntryStart(c))
            return;
        scope(success) _pos = i;
        do {
            while (true) {
                if (++i == s.length)
                    return;
                if (c == '\n')
                    break;
                c = s[i];
            }
            c = s[i];
        } while (!_isEntryStart(c));
    }

    ubyte skipCommentSigil(ubyte limit) {
        import std.algorithm.comparison: min;

        mixin _fastAccess;
        scope(success) _pos = i;
        const start = i;
        const end = min(s.length, i + limit);
        while (i < end && s[i] == '#')
            i++;
        assert(i - start <= limit, "Too many sigil characters consumed");
        return cast(ubyte)(i - start);
    }

    string skipLine() {
        mixin _fastAccess;
        scope(success) _pos = i;
        const start = i;
        while (i < s.length)
            if (s[i++] == '\n')
                return s[start .. i - (i >= 2 && s[i - 2] == '\r' ? 2 : 1)];
        return s[start .. $];
    }

    string skipIdentifier() {
        mixin _fastAccess;
        if (i == s.length || !_isAlpha(s[i]))
            return null;
        scope(success) _pos = i;
        const start = i;
        while (++i < s.length && _isIdent(s[i])) { }
        return s[start .. i];
    }

    TextElementTermination skipInlineText() {
        mixin _fastAccess;
        scope(success) _pos = i;
        while (i < s.length) {
            const c = s[i++];
            with (TextElementTermination)
                if (c == '\n')
                    return i >= 2 && s[i - 2] == '\r' ? crlf : lf;
                else if (c == '{')
                    return placeableStart;
                else if (c == '}')
                    return unpairedBrace;
        }
        return TextElementTermination.eof;
    }
}
