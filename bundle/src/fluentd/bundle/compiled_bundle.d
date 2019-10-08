module fluentd.bundle.compiled_bundle;

import std.typecons: Nullable, Rebindable;

import fluentd.bundle.function_: Function, NamedArgument;
import fluentd.bundle.locale;

import sumtype;

@safe:

package struct _CompiledMessage {
    private uint _value = uint.max;
    uint[string] attributes;
}

struct NoCompiledPattern { }

struct CompiledPattern {
nothrow pure @nogc:
    private {
        immutable(CompiledBundle)* _bundle;
        uint _address;
    }

    invariant {
        assert(_bundle !is null);
    }

    @disable this();

    private this(immutable(CompiledBundle)* bundle, uint address) {
        _bundle = bundle;
        _address = address;
    }

    @property immutable(CompiledBundle)* bundle() const { return _bundle; }
    package @property uint address() const { return _address; }
}

alias OptionalCompiledPattern = SumType!(NoCompiledPattern, CompiledPattern);

struct NoCompiledMessage { }

struct CompiledMessage {
nothrow pure:
    private {
        immutable(CompiledBundle)* _bundle;
        Nullable!(uint, uint.max) _value;
        Rebindable!(immutable uint[string]) _attributes;
    }

    invariant {
        assert(_bundle !is null);
    }

    @disable this();

    private this(immutable(CompiledBundle)* bundle, ref immutable _CompiledMessage data) @nogc {
        _bundle = bundle;
        _value = data._value;
        _attributes = data.attributes;
    }

    @property OptionalCompiledPattern value() const @nogc {
        return !_value.isNull ? (
            OptionalCompiledPattern(CompiledPattern(_bundle, _value.get))
        ) : OptionalCompiledPattern(NoCompiledPattern());
    }

    OptionalCompiledPattern getAttribute(const(char)[ ] name) const @nogc {
        if (const addr = name in _attributes)
            return OptionalCompiledPattern(CompiledPattern(_bundle, *addr));
        return OptionalCompiledPattern(NoCompiledPattern());
    }

    @property auto attributeNames() const @nogc {
        return _attributes.byKey();
    }

    auto getAttributes() const {
        import std.algorithm.iteration: map;
        import std.typecons: tuple;

        return _attributes.byKeyValue().map!(kv =>
            tuple!(q{name}, q{pattern})(kv.key, CompiledPattern(_bundle, kv.value))
        );
    }
}

alias OptionalCompiledMessage = SumType!(NoCompiledMessage, CompiledMessage);

struct CompiledBundle {
nothrow pure:
    private {
        immutable(ubyte)[ ] _bytecode;
        immutable(Locale)* _locale;
        immutable(Function)[ ] _functions;
        Rebindable!(immutable _CompiledMessage[string]) _messages;
        immutable(string)[ ] _variables;
        immutable(NamedArgument)[ ] _namedArguments;
    }

    invariant {
        assert(_locale !is null);
    }

    package this(
        immutable(ubyte)[ ] bytecode,
        immutable(Locale)* locale,
        immutable(Function)[ ] functions,
        Rebindable!(immutable _CompiledMessage[string]) messages,
        immutable(string)[ ] variables,
        immutable(NamedArgument)[ ] namedArguments,
    ) inout @nogc {
        _bytecode = bytecode;
        _locale = locale;
        _functions = functions;
        _messages = messages;
        _variables = variables;
        _namedArguments = namedArguments;
    }

    @property const @nogc {
        immutable(ubyte)[ ] bytecode() { return _bytecode; }
        immutable(Locale)* locale() { return _locale; }

        package {
            immutable(Function)[ ] functions() { return _functions; }
            immutable(string)[ ] variables() { return _variables; }
            immutable(NamedArgument)[ ] namedArguments() { return _namedArguments; }
        }
    }

    OptionalCompiledMessage getMessage(const(char)[ ] name) immutable @nogc {
        if (immutable data = name in _messages)
            return OptionalCompiledMessage(CompiledMessage(&this, *data));
        return OptionalCompiledMessage(NoCompiledMessage());
    }

    @property auto messageNames() const @nogc {
        return _messages.byKey();
    }

    auto getMessages() immutable {
        import std.algorithm.iteration: map;
        import std.typecons: tuple;

        return _messages.byKeyValue().map!(kv =>
            tuple!(q{name}, q{message})(kv.key, CompiledMessage(&this, kv.value))
        );
    }
}
