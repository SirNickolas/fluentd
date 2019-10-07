module asm_.parser;

import std.exception: enforce;

import pegged.peg: ParseTree;

import asm_.bundle;

private:

AsmLabel _parseLabel(ref const ParseTree label) nothrow pure @safe @nogc {
    if (label.children[0].name != "Assembly.Public") {
        assert(label.children.length == 1);
        return AsmLabel(false, label.matches[0]);
    }
    assert(label.children.length <= 3);
    return AsmLabel(true, label.matches[1], label.matches.length >= 3 ? label.matches[2] : null);
}

string _unescape(string s) pure @safe {
    import std.algorithm.searching: find;
    import std.array: appender;
    import std.utf: byCodeUnit, validate;

    auto backslash = s.byCodeUnit().find('\\');
    if (backslash.empty)
        return s;

    auto result = appender(s[0 .. $ - backslash.length]);
    size_t lastPos = result.data.length;
    do {
        assert(backslash.length >= 2); // Enforced in the grammar.
        assert(backslash[0] == '\\');
        const backslashPos = s.length - backslash.length;
        result ~= s[lastPos .. backslashPos];
        lastPos = backslashPos + 2;
        const c = backslash[1];
        switch (c) {
            case '"', '\\': result ~= c; break;
            case 'n': result ~= '\n'; break;
            case 'r': result ~= '\r'; break;
            case 't': result ~= '\t'; break;
            default: throw new Exception(`Invalid escape sequence: \` ~ c);
        }
        backslash = backslash[2 .. $].find('\\');
    } while (!backslash.empty);
    result ~= s[lastPos .. $];
    validate(result.data);
    return result.data;
}

struct _Parser {
pure @safe:
    AsmBundle bundle;

    @property AsmLineNumber curCodeLine() const nothrow @nogc {
        return AsmLineNumber(bundle.code.length);
    }

    void visitExternLine(ref const ParseTree line) {
        assert(line.matches.length == 1);
        const name = line.matches[0];
        enforce(name !in bundle.functionIds, "Duplicate function: " ~ name);
        bundle.functionIds[name] = bundle.functions.length;
        bundle.functions ~= ExternDefinition(name);
    }

    void visitLabelLine(ref const ParseTree line) {
        import std.range.primitives: empty;

        assert(line.children.length == 1);
        assert(line.children[0].name == "Assembly.Label");
        const label = _parseLabel(line.children[0]);
        if (!label.public_) {
            enforce(label.name !in bundle.privateLabels, "Duplicate private label: " ~ label.name);
            bundle.privateLabels[label.name] = curCodeLine;
        } else if (const msgId = label.name in bundle.messageIds) {
            auto msg = &bundle.messages[*msgId];
            if (label.attribute.empty) {
                enforce(msg.value == AsmLineNumber.init, "Duplicate public label: @" ~ label.name);
                msg.value = curCodeLine;
            } else {
                enforce(label.attribute !in msg.attributes,
                    "Duplicate public attribute: @" ~ label.name ~ '.' ~ label.attribute,
                );
                msg.attributes[label.attribute] = curCodeLine;
            }
        } else {
            auto msg = AsmMessage(label.name);
            if (label.attribute.empty)
                msg.value = curCodeLine;
            else
                msg.attributes[label.attribute] = curCodeLine;
            bundle.messageIds[label.name] = bundle.messages.length;
            bundle.messages ~= msg;
        }
    }

    void visitCodeLine(ref const ParseTree line) {
        import std.algorithm.iteration: map;
        import std.array: array;
        import std.conv: to;

        bundle.code ~= AsmCodeLine(line.matches[0], line.children[1 .. $].map!((ref arg) {
            assert(arg.name == "Assembly.Argument");
            assert(arg.children.length == 1);
            const value = arg.children[0];
            final switch (value.name) {
            case "Assembly.Number":
                assert(value.matches.length == 1);
                return AsmInstructionArgument(value.matches[0].to!double());

            case "Assembly.String":
                assert(value.matches.length == 1);
                return AsmInstructionArgument(_unescape(value.matches[0]));

            case "Assembly.Label":
                return AsmInstructionArgument(_parseLabel(value));
            }
        }).array());
    }

    void visit(ref const ParseTree t) {
        import std.algorithm.iteration: each;
        import std.algorithm.searching: startsWith;
        import std.utf: byCodeUnit;

        switch (t.name) {
        case "Assembly.ExternLine":
            visitExternLine(t);
            break;

        case "Assembly.LabelLine":
            visitLabelLine(t);
            break;

        case "Assembly.CodeLine":
            visitCodeLine(t);
            break;

        default:
            assert(t.name.byCodeUnit().startsWith("Assembly.".byCodeUnit()), t.name);
            goto case;
        case "Assembly":
            t.children.each!(child => visit(child));
            break;
        }
    }
}

public AsmBundle parse(string source) {
    import asm_.grammar;

    _Parser p;
    const root = Assembly(source);
    p.visit(root);
    return p.bundle;
}
