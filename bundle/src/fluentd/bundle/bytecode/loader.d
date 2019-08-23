module fluentd.bundle.bytecode.loader;

import std.array: Appender, appender;
import std.exception: enforce;
import std.range.primitives: empty;
import std.typecons: Rebindable, Tuple, rebindable, tuple;
import std.utf: validateUTF = validate;

import fluentd.bundle.bytecode.defs;
import fluentd.bundle.bytecode.parser;
import fluentd.bundle.compiled_bundle;
import fluentd.bundle.errors: isErrorHandler;
import fluentd.bundle.function_;

private:

// Until there is a proper type in `fluentd.bundle.errors`.
struct err { alias BundleError = void*; @disable this(); }

void _validateDataSection(immutable(ubyte)[ ] data) pure @safe {
    validateUTF(cast(string)data);
}

Tuple!(immutable(NamedArgument)[ ], size_t) _readNamedArgs(immutable(ubyte)[ ] init, size_t i)
pure @safe {
    import std.array: uninitializedArray;
    import std.conv: emplace;

    const argsLength = readU32(init, i);
    i += 4;
    auto args = (() @trusted => uninitializedArray!(NamedArgument[ ])(argsLength))();
    foreach (argIndex; 0 .. argsLength) {
        const argName = readIdentifier(init, i);
        enforce(!argName.empty, "Empty argument's name");
        i += argName.length;

        size_t len = void;
        switch (readU8(init, i++)) {
        case 0x00: // double
            emplace(&args[argIndex], argName, Value(readF64(init, i)));
            i += 8;
            continue;

        case 0x01: // string (<= 255)
            len = readU8(init, i);
            i++;
            break;

        case 0x02: // string (<= 65535)
            len = readU16(init, i);
            i += 2;
            break;

        case 0x03: // string
            len = readU32(init, i);
            i += 4;
            break;

        default:
            throw new Exception("Unknown type of a named argument");
        }
        enforce(init.length - i >= len, "Named argument's value abruptly ended");
        string argValue = cast(string)init[i .. i + len];
        validateUTF(argValue);
        i += len;
        emplace(&args[argIndex], argName, Value(argValue));
    }
    return tuple((() @trusted => cast(immutable)args)(), i);
}

Tuple!(Function[ ], Rebindable!(immutable uint[string]), size_t) _readFuncs(
    immutable(ubyte)[ ] init,
    size_t i,
    const FunctionTable fTable,
    Appender!(err.BundleError[ ]) errors,
) pure @safe
out (result) {
    import std.algorithm.searching;

    assert(result[0].length == result[1].length);
    assert(result[0].all!q{a !is null}, "Haven't initialized some function");
}
do {
    import std.array: uninitializedArray;

    const funcsLength = readU32(init, i);
    enforce(funcsLength < 1u << 31, "Too many functions");
    i += 4;
    auto funcs = (() @trusted => uninitializedArray!(Function[ ])(funcsLength))();
    uint[string] info;
    foreach (funcIndex; 0 .. funcsLength) {
        const funcName = readFunction(init, i);
        enforce(!funcName.empty, "Empty function name");
        i += funcName.length;
        const isPure = readU8(init, i++);
        enforce(isPure <= 0x01, "Unknown function type");
        enforce(funcName !in info, "Duplicate function name");
        info[funcName] = funcIndex << 1 | isPure;
        if (const entry = funcName in fTable.functions)
            if (!(isPure && entry.purity == Purity.impure)) {
                funcs[funcIndex] = entry.f;
                continue;
            } else // Attempting to supply an impure function where a pure one is expected.
                errors ~= null;
        else // Unknown function.
            errors ~= null;
        funcs[funcIndex] = defaultUnknownFunction; // Always throws.
    }
    return tuple(funcs, rebindable((() @trusted => cast(immutable)info.rehash())()), i);
}

Tuple!(immutable(string)[ ], size_t) _readVars(immutable(ubyte)[ ] init, size_t i) pure @safe {
    import std.array: uninitializedArray;

    const varsLength = readU32(init, i);
    i += 4;
    auto vars = (() @trusted => uninitializedArray!(string[ ])(varsLength))();
    foreach (ref var; vars) {
        const varName = readIdentifier(init, i);
        enforce(!varName.empty, "Empty variable name");
        i += varName.length;
        enforce(readU8(init, i++) == 0x00, "Invalid variable name terminator");
        var = varName;
    }
    return tuple((() @trusted => cast(immutable)vars)(), i);
}

void _processInitSection(
    immutable(ubyte)[ ] init,
    const FunctionTable fTable,
    Appender!(err.BundleError[ ]) errors,
) pure @safe {
    assert(false, "Not implemented");
}

CompiledBundle* _loadBytecode(
    immutable(ubyte)[ ] bytecode,
    Locale* locale,
    const FunctionTable fTable,
    Appender!(err.BundleError[ ]) errors,
) pure @safe
out (result) {
    assert(result !is null);
}
do {
    static if (size_t.max != uint.max)
        enforce(bytecode.length <= uint.max, "Bytecode size must be less than 4 GB");
    enforce(readU32(bytecode, 0) == bytecodeVersion, "Wrong bytecode version");
    const dataSectionAddr = readU32(bytecode, 4);
    const initSectionAddr = readU32(bytecode, 8);
    enforce(dataSectionAddr >= 12 && initSectionAddr >= dataSectionAddr, "Wrong section address");
    _validateDataSection(bytecode[dataSectionAddr .. initSectionAddr]);
    return new CompiledBundle;
}

public CompiledBundle* loadBytecode(EH)(
    immutable(ubyte)[ ] bytecode,
    Locale* locale,
    const FunctionTable fTable,
    scope EH onError,
) if (isErrorHandler!EH)
in {
    assert(locale !is null, "Locale must not be `null`");
    assert(onError !is null, "Error handler must not be `null`");
}
do {
    auto app = appender!(err.BundleError[ ]);
    CompiledBundle* result;
    try
        result = _loadBytecode(bytecode, locale, fTable, app);
    catch (Exception e) {
        debug (FluentD_BytecodeLoaderErrors) {
            import std.stdio;

            try
                writeln("fluentd bytecode error: ", e.msg);
            catch (Exception) { }
        }
        return null;
    }

    foreach (ref e; app.data)
        onError(e);
    return result;
}
