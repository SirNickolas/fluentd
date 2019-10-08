module fluentd.bundle.compiled_bundle;

import std.typecons: Rebindable;

import fluentd.bundle.errors: isErrorHandler;
import fluentd.bundle.function_: Function, NamedArgument;
import fluentd.bundle.locale;

import sumtype;

struct NoCompiledPattern { }

struct CompiledPattern {
nothrow pure @safe @nogc:
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
nothrow pure @safe @nogc:
    private {
        immutable(ubyte)[ ] _bytecode;
        Locale* _locale;
        Function[ ] _functions;
        Rebindable!(immutable CompiledMessage[string]) _messages;
        immutable(string)[ ] _variables;
        immutable(NamedArgument)[ ] _namedArguments;
        // TODO: More.
    }

    invariant {
        // assert(_locale !is null);
    }

    @property {
        immutable(ubyte)[ ] bytecode() const { return _bytecode; }
        inout(Locale)* locale() inout { return _locale; }
        immutable(CompiledMessage[string]) messages() const { return _messages; }
        package {
            const(Function)[ ] functions() const { return _functions; }
            immutable(string)[ ] variables() const { return _variables; }
            immutable(NamedArgument)[ ] namedArguments() const { return _namedArguments; }
        }
    }
}
