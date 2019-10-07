module fluentd.bundle.function_;

import std.typecons: Flag, Yes;

public import fluentd.bundle.conflicts;
public import fluentd.bundle.locale;
public import fluentd.bundle.value;
import fluentd.bundle.errors: isErrorHandler;

struct NamedArgument {
    string name;
    Value value;
}

// `Locale*` is always non-`null`; named arguments are sorted by their name.
alias Function =
    Value delegate(immutable(Locale)*, scope const(Value)[ ], scope const(NamedArgument)[ ]) @safe;

struct FunctionTable {
    struct Entry {
        Function f;
        Flag!q{allowCTFE} allowCTFE;
    }

    private Entry[string] _aa;

    this(Entry[string] aa) nothrow pure @safe @nogc
    in {
        import fluentd.utils.lexing: isCallee;

        foreach (ref kv; aa.byKeyValue()) {
            assert(isCallee(kv.key), "Invalid function name");
            assert(kv.value.f !is null, "Function must not be `null`");
        }
    }
    do {
        _aa = aa;
    }

    @property const(Entry[string]) functions() const nothrow pure @safe @nogc {
        return _aa;
    }

    void add(EH)(
        string name,
        Flag!q{allowCTFE} allowCTFE,
        Function f,
        scope EH onError,
        ConflictResolutionStrategy strategy = ConflictResolutionStrategy.redefine,
    ) if (isErrorHandler!EH)
    in {
        import fluentd.utils.lexing: isCallee;

        assert(isCallee(name), "Invalid function name");
        assert(f !is null, "Function must not be `null`");
        assert(onError !is null, "Error handler must not be `null`");
    }
    do {
        _register!(() => Entry(f, allowCTFE))(_aa, name, _ConflictInfo!EH(onError, strategy));
    }
}

alias defaultUnknownFunction = delegate Value(
    immutable(Locale)* locale,
    scope const(Value)[ ] positional,
    scope const(NamedArgument)[ ] named,
) pure @safe {
    throw new Exception("Unknown function");
};

alias defaultNumberFunction = delegate Value(
    immutable(Locale)* locale,
    scope const(Value)[ ] positional,
    scope const(NamedArgument)[ ] named,
) @safe {
    import std.conv: to;
    import std.exception: enforce;
    import std.range.primitives: empty;
    import sumtype;

    enforce(positional.length == 1, "A single positional argument is expected");
    // TODO: Check named arguments.
    // https://projectfluent.org/fluent/guide/functions.html
    enforce(named.empty, "Named arguments are not implemented yet");

    return Value(positional[0].match!(to!double).to!string());
};

alias defaultDatetimeFunction = delegate Value(
    immutable(Locale)* locale,
    scope const(Value)[ ] positional,
    scope const(NamedArgument)[ ] named,
) @safe {
    import std.conv: to;
    import std.exception: enforce;
    import std.range.primitives: empty;
    import sumtype;

    enforce(positional.length == 1, "A single positional argument is expected");
    // TODO: Check named arguments.
    // https://projectfluent.org/fluent/guide/functions.html
    enforce(named.empty, "Named arguments are not implemented yet");

    return Value(positional[0].match!(to!string));
};

FunctionTable createDefaultFunctionTable(Flag!q{allowCTFE} allowCTFE = Yes.allowCTFE)
nothrow pure @safe {
    return FunctionTable([
        "NUMBER":   FunctionTable.Entry(defaultNumberFunction, allowCTFE),
        "DATETIME": FunctionTable.Entry(defaultDatetimeFunction, allowCTFE),
    ]);
}
