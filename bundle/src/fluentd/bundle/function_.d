module fluentd.bundle.function_;

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
    Value delegate(Locale*, scope const(Value)[ ], scope const(NamedArgument)[ ]) @safe;

enum Purity: ubyte {
    impure,
    pure_,
    compileTime,
}

struct FunctionTable {
    struct Entry {
        Function f;
        Purity purity;
    }

    private Entry[string] _aa;

    this(Entry[string] aa) nothrow pure @safe @nogc
    in {
        // TODO: Check if AA's keys are valid function names.
    }
    do {
        _aa = aa;
    }

    @property const(Entry[string]) functions() const nothrow pure @safe @nogc {
        return _aa;
    }

    void add(EH)(
        string name,
        Purity purity,
        Function f,
        scope EH onError,
        ConflictResolutionStrategy strategy = ConflictResolutionStrategy.redefine,
    ) if (isErrorHandler!EH)
    in {
        // TODO: Check if `name` is a valid function name.
        assert(f !is null, "Function must not be `null`");
        assert(onError !is null, "Error handler must not be `null`");
    }
    do {
        _register!(() => Entry(f, purity))(_aa, name, _ConflictInfo!EH(onError, strategy));
    }
}

immutable defaultUnknownFunction = delegate Value(
    Locale* locale,
    scope const(Value)[ ] positional,
    scope const(NamedArgument)[ ] named,
) pure @safe {
    throw new Exception("Unknown function");
};

immutable defaultNumberFunction = delegate Value(
    Locale* locale,
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

immutable defaultDatetimeFunction = delegate Value(
    Locale* locale,
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

FunctionTable createDefaultFunctionTable(Purity purity = Purity.compileTime) nothrow pure @safe {
    return FunctionTable([
        "NUMBER":   FunctionTable.Entry(defaultNumberFunction, purity),
        "DATETIME": FunctionTable.Entry(defaultDatetimeFunction, purity),
    ]);
}
