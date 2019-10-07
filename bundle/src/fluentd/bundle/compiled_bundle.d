module fluentd.bundle.compiled_bundle;

import std.typecons: Rebindable;

import fluentd.bundle.errors: isErrorHandler;
import fluentd.bundle.function_: Function, NamedArgument;
import fluentd.bundle.locale;

import sumtype;

@safe:

struct NoCompiledPattern { }

struct CompiledPattern {
nothrow pure @nogc:
    private uint _address;

    package this(uint address) { _address = address; }

    package @property uint address() const { return _address; }
}

alias OptionalCompiledPattern = SumType!(NoCompiledPattern, CompiledPattern);

struct CompiledMessage {
    OptionalCompiledPattern value;
    CompiledPattern[string] attributes;
}

struct CompiledBundle {
nothrow pure @nogc:
    private {
        immutable(ubyte)[ ] _bytecode;
        immutable(Locale)* _locale;
        immutable(Function)[ ] _functions;
        Rebindable!(immutable CompiledMessage[string]) _messages;
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
        Rebindable!(immutable CompiledMessage[string]) messages,
        immutable(string)[ ] variables,
        immutable(NamedArgument)[ ] namedArguments,
    ) inout {
        _bytecode = bytecode;
        _locale = locale;
        _functions = functions;
        _messages = messages;
        _variables = variables;
        _namedArguments = namedArguments;
    }

    @property const {
        immutable(ubyte)[ ] bytecode() { return _bytecode; }
        immutable(Locale)* locale() { return _locale; }
        immutable(CompiledMessage[string]) messages() { return _messages; }

        package {
            immutable(Function)[ ] functions() { return _functions; }
            immutable(string)[ ] variables() { return _variables; }
            immutable(NamedArgument)[ ] namedArguments() { return _namedArguments; }
        }
    }
}
