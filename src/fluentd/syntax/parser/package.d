module fluentd.syntax.parser;

import std.array: Appender, appender;
import std.range.primitives: empty;

import fluentd.syntax.parser.common;
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

bool _isValidCallee(ast.Identifier id) nothrow @nogc {
    import std.algorithm.searching;
    import std.utf;

    return id.name.byCodeUnit().all!(c => _isCallee(c));
}

struct _Parser {
pure:
    ParserStream ps;
    Appender!(char[ ]) buffer;
    Appender!(ast.PatternElement[ ]) patternElements;
    Appender!(size_t[ ]) linePtrs; // Indices into `patternElements`.
    Appender!(ast.Attribute[ ]) attrs;
    Appender!(ast.InlineExpression[ ]) args;
    Appender!(ast.NamedArgument[ ]) kwargs;
    bool[string] seenKwargs;

    @property Span curSpan() const nothrow @nogc {
        return _byteAt(ps.pos);
    }

    void throw_(K)(K kind, Span span) const {
        throw new _ParserException(ParserError(span, ErrorKind(kind)));
    }

    void throw_(K)(K kind) const {
        throw_(kind, curSpan);
    }

    void expect(char c)() {
        if (!ps.skip(c)) {
            enum range = c == '\\' ? `\\` : c ~ "";
            throw_(err.ExpectedCharRange(range));
        }
    }

    ast.StringLiteral parseStringLiteral() {
        const s = ps.skipStringLiteral();
        if (s is null) // TODO: Differentiate errors.
            throw_(err.UnterminatedStringExpression());
        return ast.StringLiteral(s);
    }

    ast.NumberLiteral parseNumberLiteral() {
        const start = ps.pos;
        if (!ps.skipNumberLiteral())
            throw_(err.ExpectedCharRange("0-9"));
        return ast.NumberLiteral(ps.slice(start));
    }

    ast.Literal parseLiteral() {
        switch (ps.classifyInlineExpression()) with (InlineExpressionStart) {
        case stringLiteral:
            return ast.Literal(parseStringLiteral());
        case numberLiteral:
            return ast.Literal(parseNumberLiteral());
        default:
            throw_(err.ExpectedLiteral());
            assert(false);
        }
    }

    T parseIdentifier(T = ast.Identifier)() {
        const s = ps.skipIdentifier();
        if (s.empty)
            throw_(err.ExpectedCharRange("A-Za-z"));
        return T(s);
    }

    ast.VariableReference parseVariableReference()
    in {
        assert(ps.test('$'));
    }
    do {
        ps.skip();
        return ast.VariableReference(parseIdentifier());
    }

    ast.OptionalIdentifier parseAttributeAccessor() {
        if (!ps.skip('.'))
            return ast.OptionalIdentifier.init;
        return parseIdentifier!(ast.OptionalIdentifier);
    }

    ast.CallArguments parseArgumentList() {
        import sumtype;

        args.clear();
        kwargs.clear();
        // We don't hold pointers into the hash table, so it's safe to clear and reuse it.
        () @trusted { seenKwargs.clear(); }();

        do {
            ps.skipBlank();
            if (ps.skip(')'))
                return ast.CallArguments(args.data.dup, kwargs.data.dup);

            auto arg = parseInlineExpression();
            ps.skipBlank();
            if (ps.skip(':')) {
                // Named argument.
                ast.Identifier argName;
                // Argument's name is parsed as a message reference (without an attribute).
                if (arg.match!(
                    (ref ast.MessageReference mr) {
                        if (!mr.attribute.name.empty)
                            return true;
                        argName = mr.id;
                        return false;
                    },
                    (ref _) => true,
                ))
                    throw_(err.InvalidArgumentName());

                ps.skipBlank();
                const argValue = parseLiteral();
                // Check for duplicates.
                if (argName.name in seenKwargs)
                    throw_(err.DuplicatedNamedArgument(argName.name));
                seenKwargs[argName.name] = true;

                kwargs ~= ast.NamedArgument(argName, argValue);
                ps.skipBlank();
            } else {
                // Positional argument.
                if (!kwargs.data.empty)
                    throw_(err.PositionalArgumentFollowsNamed());
                args ~= arg;
            }
        } while (ps.skip(','));

        if (ps.skip(')'))
            return ast.CallArguments(args.data.dup, kwargs.data.dup);
        throw_(err.ExpectedCharRange(",)"));
        assert(false);
    }

    ast.OptionalCallArguments parseCallArguments() {
        ps.skipBlank();
        if (!ps.skip('('))
            return ast.OptionalCallArguments(ast.NoCallArguments());
        return ast.OptionalCallArguments(parseArgumentList());
    }

    ast.TermReference parseTermReference()
    in {
        assert(ps.test('-'));
    }
    do {
        ps.skip();
        return ast.TermReference(parseIdentifier(), parseAttributeAccessor(), parseCallArguments());
    }

    ast.InlineExpression parseMessageOrFunctionReference() {
        import sumtype;

        const id = ast.Identifier(ps.skipIdentifier());
        const attr = parseAttributeAccessor();
        if (!attr.name.empty)
            return ast.InlineExpression(ast.MessageReference(id, attr));
        return parseCallArguments().match!(
            (ast.NoCallArguments _) =>
                ast.InlineExpression(ast.MessageReference(id)),
            (ref ast.CallArguments ca) {
                if (!_isValidCallee(id))
                    throw_(err.ForbiddenCallee());
                return ast.InlineExpression(ast.FunctionReference(id, ca));
            },
        );
    }

    ast.InlineExpression parseInlineExpression() {
        final switch (ps.classifyInlineExpression()) with (InlineExpressionStart) {
        case stringLiteral:
            return ast.InlineExpression(parseStringLiteral());

        case numberLiteral:
            return ast.InlineExpression(parseNumberLiteral());

        case variableReference:
            return ast.InlineExpression(parseVariableReference());

        case termReference:
            return ast.InlineExpression(parseTermReference());

        case identifier:
            return parseMessageOrFunctionReference();

        case placeable:
            assert(ps.test('{'));
            ps.skip();
            return ast.InlineExpression(new ast.Expression(parsePlaceable()));

        case invalid:
            throw_(err.ExpectedInlineExpression());
            assert(false);
        }
    }

    ast.Variant[ ] parseVariantList() {
        assert(false, "Not implemented");
    }

    ast.Expression parsePlaceable()
    in {
        ps.assertLast!q{a == '{'};
    }
    do {
        import sumtype;

        ps.skipBlank();
        auto ie = parseInlineExpression();
        ps.skipBlank();
        scope(success) expect!'}'();
        if (!ps.skipArrow()) {
            ie.match!(
                (ref ast.TermReference tr) {
                    if (!tr.attribute.name.empty)
                        throw_(err.TermAttributeAsPlaceable());
                },
                (ref _) { },
            );
            return ast.Expression(ie);
        }

        auto variants = parseVariantList();
        ps.skipBlank();
        return ast.Expression(ast.SelectExpression(ie, variants));
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

            case unbalancedBrace:
                throw_(err.UnbalancedClosingBrace(), _byteAt(ByteOffset(ps.pos - 1)));
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
            throw_(err.UnbalancedClosingBrace(), _byteAt(ByteOffset(ps.pos - 1)));

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
                version (assert)
                    r++;
            }
            version (assert)
                assert(r == nextR, "Wrong number of iterations of the line parsing loop");
            else
                r = nextR;
        }

        // Append trailing text, stripping spaces from it.
        const content = processTrailingText(state, laggedText);
        if (!content.empty)
            result[w++] = ast.TextElement(content);

        return ast.Pattern(result[0 .. w].dup);
    }

    _NamedPattern parseNamedPattern() {
        const id = parseIdentifier();
        ps.skipBlankInline();
        expect!'='();
        ps.skipBlankInline();
        return _NamedPattern(id, parsePattern());
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
                throw_(err.MissingValue());
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
            throw_(E(m.pattern.id.name), Span(entryStart, ps.pos));
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
            throw_(err.ExpectedCharRange(" "));

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
        appender(minimallyInitializedArray!(ast.InlineExpression[ ])(7)),
        appender(minimallyInitializedArray!(ast.NamedArgument[ ])(15)),
    );
}

public ParserResult parse(string source) nothrow {
    import sumtype;

    auto entries = appender!(ast.ResourceEntry[ ]);
    auto errors = appender!(ParserError[ ]);

    auto p = _createParser(source);
    ast.OptionalComment lastComment;
    ast.ResourceEntry rcEntry;
    while (true) {
        const haveVSpace = p.ps.skipBlankBlock();
        if (p.ps.eof)
            break;
        {
            const entryStart = p.ps.pos;
            try
                rcEntry = p.parseEntry();
            catch (_ParserException e) {
                errors ~= e.err;
                p.ps.skipJunk();
                rcEntry = ast.Junk(p.ps.slice(entryStart));
            } catch (Exception e)
                assert(false, e.msg);
        }

        // Attach preceding comment to a message or term.
        lastComment.match!(
            (ref ast.Comment c) {
                if (haveVSpace || rcEntry.match!(
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

        // Append `rcEntry` to `entries` unless it is a `Comment`.
        if (rcEntry.match!(
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
            entries ~= rcEntry;
    }

    return ParserResult(ast.Resource(entries.data), errors.data);
}
