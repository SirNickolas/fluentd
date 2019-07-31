module fluentd.syntax.parser;

import std.array: Appender, appender;
import std.range.primitives: empty;

import fluentd.syntax.parser.span;
import fluentd.syntax.parser.stream;
import ast = fluentd.syntax.ast;
import err = fluentd.syntax.parser.errors: ErrorKind, ParserError;

private pure @safe:

public struct ParserResult {
    ast.Resource resource;
    ParserError[ ] errors;
}

class _ParserException: Exception {
    ParserError err;

    this(ParserError e) nothrow pure @nogc {
        super(null);
        err = e;
    }
}

struct _NamedPattern {
    ast.Identifier id;
    ast.Pattern value;
}

struct _MessageLike {
    _NamedPattern pattern;
    ast.Attribute[ ] attributes;
}

enum _PatternState: ubyte {
    haveNoText,
    haveText,
    mergingTexts,
}

T _unreachable(T = void)(const(char)[ ] msg) nothrow @nogc {
    assert(false, msg);
}

Span _byteAt(ByteOffset pos) nothrow @nogc {
    return Span(pos, ByteOffset(pos + 1));
}

S _stripTrailingSpaces(S: const(char)[ ])(S text) nothrow @nogc {
    import std.algorithm.mutation;
    import std.utf;

    return text.byCodeUnit().stripRight(' ').source;
}

struct _Parser {
pure:
    ParserStream ps;
    Appender!(char[ ]) buffer;
    Appender!(ast.PatternElement[ ]) patternElements;
    Appender!(size_t[ ]) linePtrs; // Indices into `patternElements`.
    Appender!(ast.Attribute[ ]) attrs;

    @property Span curSpan() const nothrow @nogc {
        return _byteAt(ps.pos);
    }

    void throw_(ErrorKind kind, Span span) const {
        throw new _ParserException(ParserError(span, kind));
    }

    void throw_(ErrorKind kind) const {
        throw_(kind, curSpan);
    }

    void expect(char c)() {
        if (!ps.skip(c)) {
            enum range = c == '\\' ? `\\` : c ~ "";
            throw_(ErrorKind(err.ExpectedCharRange(range)));
        }
    }

    ast.Expression parsePlaceable() {
        debug if (ps.skip('}')) // Allow `{}` in debug.
            return ast.Expression(ast.InlineExpression(ast.StringLiteral.init));
        assert(false, "Not implemented");
    }

    void appendInlineText(ByteOffset start, ByteOffset end) nothrow {
        patternElements ~= ast.PatternElement(
            // Cannot construct `TextElement` from an empty string (invariant violation).
            start != end ? ast.TextElement(ps.slice(start, end)) : ast.TextElement.init
        );
    }

    void parsePatternLine(ByteOffset inlineTextStart) {
        version (Posix)
            ubyte newlineLength = 1; // \n
        else
            ubyte newlineLength = 2; // \r\n
    loop:
        while (true)
            final switch (ps.skipInlineText()) with (TextElementTermination) {
            case placeableStart:
                appendInlineText(inlineTextStart, ByteOffset(ps.pos - 1));
                patternElements ~= ast.PatternElement(parsePlaceable());
                inlineTextStart = ps.pos;
                continue;
            case lf:
                version (Windows)
                    newlineLength = 1;
                break loop;
            case crlf:
                version (Posix)
                    newlineLength = 2;
                break loop;
            case eof:
                newlineLength = 0;
                break loop;
            case unpairedBrace:
                throw_(ErrorKind(err.UnpairedClosingBrace()), _byteAt(ByteOffset(ps.pos - 1)));
                assert(false);
            }

        appendInlineText(inlineTextStart, ByteOffset(ps.pos - newlineLength));
    }

    string processTrailingText(_PatternState state, string laggedText) nothrow {
        final switch (state) with (_PatternState) {
        case haveNoText:
            return null;
        case haveText:
            return _stripTrailingSpaces(laggedText);
        case mergingTexts:
            return _stripTrailingSpaces(buffer.data).idup;
        }
    }

    ast.Pattern parsePattern() {
        import std.algorithm.comparison: among, min;
        import sumtype;

        if (ps.skip('}'))
            throw_(ErrorKind(err.UnpairedClosingBrace()), _byteAt(ByteOffset(ps.pos - 1)));

        patternElements.clear();
        linePtrs.clear();

        // Parse the first line.
        parsePatternLine(ps.pos);
        linePtrs ~= patternElements.data.length;

        // Parse the rest of the pattern.
        size_t nonBlankLines = patternElements.data.length > 1 || patternElements.data[0].match!(
            (ref ast.TextElement te) => !te.content.empty,
            (ref _) => _unreachable!bool("The first line of a pattern does not start with text"),
        );
        size_t firstNonBlankLine = nonBlankLines - 1;
        size_t commonIndentation = size_t.max;
        while (true) {
            const lineStart = ps.pos;
            const indented = ps.skipBlankInline();
            if (!ps.skipLineEnd()) {
                // A non-blank line.
                if (ps.test!(among!('.', '[', '*', '}'))) {
                    ps.backtrack(lineStart);
                    break;
                } else if (!indented && !ps.test('{'))
                    break;
                commonIndentation = min(commonIndentation, ps.pos - lineStart);
                parsePatternLine(lineStart);

                // `+1` because we append after setting this variable.
                nonBlankLines = linePtrs.data.length + 1;
                if (firstNonBlankLine == size_t.max)
                    firstNonBlankLine = nonBlankLines - 1;
            } else if (ps.eof) // Blank lines are ignored, even if they are indented deeper.
                break;
            linePtrs ~= patternElements.data.length;
        }

        if (!nonBlankLines)
            return ast.Pattern.init;

        // Dedent, merge adjacent text elements, and remove empty ones.
        _PatternState state;
        string laggedText;
        buffer.clear();

        auto result = patternElements.data;
        size_t r = firstNonBlankLine ? linePtrs.data[firstNonBlankLine - 1] : 0;
        size_t w;
        // Iterate through parsed lines.
        foreach (lineNumber, nextR; linePtrs.data[firstNonBlankLine .. nonBlankLines]) {
            // Append a newline unless it's the first line.
            if (lineNumber)
                final switch (state) with (_PatternState) {
                case haveNoText:
                    state = haveText;
                    laggedText = "\n";
                    break;

                case haveText:
                    state = mergingTexts;
                    buffer.clear();
                    buffer ~= laggedText;
                    goto case;
                case mergingTexts:
                    buffer ~= '\n';
                    break;
                }

            // Process the line.
            bool atBOL = !!(firstNonBlankLine | lineNumber);
            foreach (ref pe; result[r .. nextR]) {
                pe.match!(
                    (ref ast.TextElement te) {
                        // Dedent unless it's the very first line (directly after `=` or `]`).
                        const content = atBOL ? te.content[commonIndentation .. $] : te.content;
                        atBOL = false;
                        if (content.empty)
                            return;
                        // Merge with previous text.
                        final switch (state) with (_PatternState) {
                        case haveNoText:
                            state = haveText;
                            laggedText = content;
                            break;

                        case haveText:
                            state = mergingTexts;
                            buffer.clear();
                            buffer ~= laggedText;
                            goto case;
                        case mergingTexts:
                            buffer ~= content;
                            break;
                        }
                    },
                    (ref ast.Expression e) {
                        assert(w <= r, "Not enough space for rewriting the pattern");
                        // Append merged text.
                        final switch (state) with (_PatternState) {
                        case haveNoText: break;
                        case haveText:
                            result[w++] = ast.TextElement(laggedText);
                            break;
                        case mergingTexts:
                            result[w++] = ast.TextElement(buffer.data.idup);
                            break;
                        }
                        state = _PatternState.haveNoText;

                        assert(w <= r, "Not enough space for rewriting the pattern");
                        result[w++] = pe;
                    },
                );
                r++;
            }
            assert(r == nextR, "Wrong number of iterations of the line parsing loop");
        }

        // Append trailing text, stripping spaces from it.
        const content = processTrailingText(state, laggedText);
        if (!content.empty)
            result[w++] = ast.TextElement(content);

        return ast.Pattern(result[0 .. w].dup);
    }

    _NamedPattern parseNamedPattern() {
        const id = ps.skipIdentifier();
        if (id.empty)
            throw_(ErrorKind(err.ExpectedCharRange("A-Za-z")));
        ps.skipBlankInline();
        expect!'='();
        ps.skipBlankInline();
        return _NamedPattern(ast.Identifier(id), parsePattern());
    }

    ast.Attribute[ ] parseAttributes() {
        attrs.clear();
        ByteOffset lineStart;
        while (true) {
            lineStart = ps.pos;
            ps.skipBlankInline();
            if (!ps.skip('.'))
                break;
            auto p = parseNamedPattern();
            if (p.value.elements.empty) // TODO: Report this error on the previous line.
                throw_(ErrorKind(err.MissingValue()));
            attrs ~= ast.Attribute(p.id, p.value);
        }
        ps.backtrack(lineStart);
        return attrs.data.dup;
    }

    _MessageLike parseMessageLike() {
        return _MessageLike(parseNamedPattern(), parseAttributes());
    }

    T parseMessageLike(T, alias validate, E)() {
        const entryStart = ps.pos;
        auto m = parseMessageLike();
        if (!validate(m))
            throw_(ErrorKind(E(m.pattern.id.name)), Span(entryStart, ps.pos));
        return T(m.pattern.id, m.pattern.value, m.attributes);
    }

    alias parseMessage = parseMessageLike!(
        ast.Message,
        (ref _MessageLike m) => !m.pattern.value.elements.empty || !m.attributes.empty,
        err.ExpectedMessageField,
    );

    ast.Term parseTerm()
    in {
        ps.assertLast!q{a == '-'};
    }
    do {
        return parseMessageLike!(
            ast.Term,
            (ref _MessageLike m) => !m.pattern.value.elements.empty,
            err.ExpectedTermField,
        );
    }

    ast.AnyComment parseComment()
    in {
        ps.assertLast!q{a == '#'};
    }
    do {
        const level = cast(ubyte)(ps.skipCommentSigil(2) + 1);
        string lastLine;
        if (ps.skip(' '))
            lastLine = ps.skipLine();
        else if (!ps.skipLineEnd())
            throw_(ErrorKind(err.ExpectedCharRange(" ")));

        buffer.clear();
        {
            ByteOffset lineStart;
            while (true) {
                lineStart = ps.pos;
                if (ps.skipCommentSigil(level) != level)
                    break; // A shorter comment (or not a comment at all).
                buffer ~= lastLine;
                if (ps.skip(' '))
                    lastLine = ps.skipLine();
                else {
                    lastLine = null;
                    if (!ps.skipLineEnd())
                        break; // Either a longer comment or a syntax error.
                }
                buffer ~= '\n';
            }
            ps.backtrack(lineStart);
        }
        if (!buffer.data.empty) {
            buffer ~= lastLine;
            lastLine = buffer.data.idup;
        }
        final switch (level) {
            case 1: return ast.AnyComment(ast.Comment(lastLine));
            case 2: return ast.AnyComment(ast.GroupComment(lastLine));
            case 3: return ast.AnyComment(ast.ResourceComment(lastLine));
        }
    }

    ast.Entry parseEntry() {
        if (ps.skip('#'))
            return ast.Entry(parseComment());
        else if (ps.skip('-'))
            return ast.Entry(parseTerm());
        else
            return ast.Entry(parseMessage());
    }
}

_Parser _createParser(string source) nothrow {
    import std.array;

    return _Parser(
        ParserStream(source),
        appender(uninitializedArray!(char[ ])(255)),
        appender(minimallyInitializedArray!(ast.PatternElement[ ])(15)),
        appender(uninitializedArray!(size_t[ ])(7)),
        appender(minimallyInitializedArray!(ast.Attribute[ ])(7)),
    );
}

public ParserResult parse(string source) nothrow {
    import sumtype;

    auto entries = appender!(ast.ResourceEntry[ ]);
    auto errors = appender!(ParserError[ ]);

    auto p = _createParser(source);
    ast.OptionalComment lastComment;
    ast.ResourceEntry rEntry;
    while (true) {
        p.ps.skipBlankBlock();
        if (p.ps.eof)
            break;
        {
            const entryStart = p.ps.pos;
            try
                rEntry = p.parseEntry();
            catch (_ParserException e) {
                errors ~= e.err;
                p.ps.skipJunk();
                rEntry = ast.Junk(p.ps.slice(entryStart));
            } catch (Exception e)
                assert(false, e.msg);
        }

        // Attach preceding comment to a message or term.
        // TODO: Do not attach if there are blank lines between them.
        lastComment.match!(
            (ref ast.Comment c) {
                if (rEntry.match!(
                    (ref ast.Entry entry) => entry.match!(
                        (ref msgOrTerm) {
                            msgOrTerm.comment = lastComment;
                            return false;
                        },
                        _ => true,
                    ),
                    _ => true,
                ))
                    entries ~= ast.ResourceEntry(ast.Entry(ast.AnyComment(c)));
                lastComment = ast.NoComment();
            },
            (ast.NoComment _) { },
        );

        // Append `rEntry` to `entries` unless it is a `Comment`.
        if (rEntry.match!(
            (ref ast.Entry entry) => entry.match!(
                (ref ast.AnyComment ac) => ac.match!(
                    (ref ast.Comment c) {
                        lastComment = c;
                        return false;
                    },
                    _ => true,
                ),
                _ => true,
            ),
            _ => true,
        ))
            entries ~= rEntry;
    }

    return ParserResult(ast.Resource(entries.data), errors.data);
}
