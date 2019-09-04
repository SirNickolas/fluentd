module fluentd.bundle.compiled_bundle;

import std.typecons: Rebindable;

import fluentd.bundle.errors: isErrorHandler;
import fluentd.bundle.function_: Function, NamedArgument, Purity;
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
    private {
        immutable(ubyte)[ ] _bytecode;
        Locale* _locale;
        Function[ ] _functions;
        // The LSB is purity, the rest are index into `_functions`.
        Rebindable!(immutable uint[string]) _functionsInfo;
        Rebindable!(immutable CompiledMessage[string]) _messages;
        immutable(string)[ ] _variables;
        immutable(NamedArgument)[ ] _namedArguments;
        // TODO: More.
    }

    invariant {
        // assert(_locale !is null);
    }

    @property nothrow pure @safe @nogc {
        immutable(ubyte)[ ] bytecode() const { return _bytecode; }
        inout(Locale)* locale() inout { return _locale; }
        immutable(CompiledMessage[string]) messages() const { return _messages; }
        package {
            const(Function)[ ] functions() const { return _functions; }
            immutable(string)[ ] variables() const { return _variables; }
            immutable(NamedArgument)[ ] namedArguments() const { return _namedArguments; }
        }
    }

    void redefineFunction(EH)(string name, Purity purity, Function f, scope EH onError)
    if (isErrorHandler!EH)
    in {
        // TODO: Check if `name` is a valid function name.
        assert(f !is null, "Function must not be `null`");
        assert(onError !is null, "Error handler must not be `null`");
    }
    do {
        const p = name in _functionsInfo;
        if (p is null)
            return; // The bundle does not call this function.
        const info = *p;
        if (info & 0x1 && purity == Purity.impure) {
            // Attempting to redefine a pure function as an impure one.
            onError();
            return;
        }
        _functions[info >> 1] = f;
    }
}
