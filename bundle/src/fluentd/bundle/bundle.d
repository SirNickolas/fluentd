module fluentd.bundle.bundle;

import sumtype;

public import fluentd.bundle.conflicts;
import ast = fluentd.syntax.ast;
import err = fluentd.bundle.errors: isErrorHandler;

private:

// We need to rewrap `ast.Pattern` and `ast.OptionalPattern` to make them tail-const.
public struct Pattern {
    const(ast.PatternElement)[ ] elements;

    invariant {
        import std.range.primitives: empty;

        assert(!elements.empty, "Empty pattern");
    }
}

public alias OptionalPattern = SumType!(ast.NoPattern, Pattern);

OptionalPattern _convert(ref const ast.OptionalPattern op) nothrow pure @safe @nogc {
    return op.match!(
        (ast.NoPattern x) => OptionalPattern(x),
        (const ast.Pattern pattern) => OptionalPattern(Pattern(pattern.elements)),
    );
}

public struct Message {
    OptionalPattern value;
    Pattern[string] attributes;
}

Pattern[string] _convert(EH)(const(ast.Attribute)[ ] attrs, _ConflictInfo!EH info) {
    Pattern[string] result;
    foreach (ref attr; attrs)
        _register!(() => Pattern(attr.value.elements))(result, attr.id.name, info);
    return result;
}

Message _convert(EH)(ref const ast.Message msg, _ConflictInfo!EH info) {
    return Message(_convert(msg.value), _convert(msg.attributes, info));
}

Message _convert(EH)(ref const ast.Term term, _ConflictInfo!EH info) {
    return Message(
        OptionalPattern(Pattern(term.value.elements)),
        _convert(term.attributes, info),
    );
}

public struct Bundle {
    private Message[string] _messages, _terms;

    private @disable this(bool);

    @property const nothrow pure @safe @nogc {
        const(Message[string]) messages() { return _messages; }
        package const(Message[string]) terms() { return _terms; }
    }

    void add(EH)(
        const ast.Resource rc,
        scope EH onError,
        ConflictResolutionStrategy strategy = ConflictResolutionStrategy.redefine,
    ) if (isErrorHandler!EH)
    in {
        assert(onError !is null, "Error handler must not be `null`");
    }
    do {
        const info = _ConflictInfo!EH(onError, strategy);
        foreach (ref rcEntry; rc.body)
            rcEntry.match!(
                (const ast.Junk _) { },
                (ref const ast.Entry entry) => entry.match!(
                    (ref const ast.AnyComment _) { },
                    (ref const ast.Message msg) => _register!(() => _convert(msg, info))(
                        _messages, msg.id.name, info,
                    ),
                    (ref const ast.Term term) => _register!(() => _convert(term, info))(
                        _terms, term.id.name, info,
                    ),
                ),
            );
    }
}
