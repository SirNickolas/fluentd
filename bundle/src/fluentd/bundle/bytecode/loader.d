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

Tuple!(Rebindable!(immutable CompiledMessage[string]), size_t) _readMessages(
    immutable(ubyte)[ ] bytecode, size_t i, size_t codeSectionSize,
) pure @safe {
    CompiledMessage[string] result;
    CompiledMessage* cur;
    bool validMsg = true;
    while (true) {
        const name = readIdentifier(bytecode, i);
        if (name.empty)
            break;
        i += name.length;

        switch (readU8(bytecode, i++)) {
        case 0x00: // Message.
            enforce(validMsg, "Message with no value and no attributes");
            const addr = readU32(bytecode, i);
            enforce(addr < codeSectionSize, "Invalid message address");
            i += 4;
            enforce(name !in result, "Duplicate message");
            cur = &(result[name] = CompiledMessage(OptionalCompiledPattern(CompiledPattern(addr))));
            break;

        case 0x01: // Attribute.
            validMsg = true;
            const addr = readU32(bytecode, i);
            enforce(addr < codeSectionSize, "Invalid attribute address");
            i += 4;
            enforce(cur !is null, "Orphan attribute");
            enforce(name !in cur.attributes, "Duplicate attribute");
            cur.attributes[name] = CompiledPattern(addr);
            break;

        case 0x02: // Message without value.
            enforce(validMsg, "Message with no value and no attributes");
            validMsg = false;
            enforce(name !in result, "Duplicate message");
            cur = &(result[name] = CompiledMessage(OptionalCompiledPattern(NoCompiledPattern())));
            break;

        default:
            throw new Exception("Invalid message terminator");
        }
    }
    enforce(readU8(bytecode, i++) == 0x00, "Invalid message section terminator");
    enforce(validMsg, "Message with no value and no attributes");
    return tuple(rebindable((() @trusted => cast(immutable)result.rehash())()), i);
}

Tuple!(immutable(string)[ ], size_t) _readVars(immutable(ubyte)[ ] bytecode, size_t i) pure @safe {
    import std.algorithm.comparison: max;
    import std.array: uninitializedArray;

    const varsLength = readU32(bytecode, i);
    i += 4;
    // Each variable occupies at least 2 bytes.
    enforce(bytecode.length - i >= max(varsLength, varsLength << 1), "Too many variables");
    auto vars = (() @trusted => uninitializedArray!(string[ ])(varsLength))();
    foreach (ref var; vars) {
        const varName = readIdentifier(bytecode, i);
        enforce(!varName.empty, "Empty variable name");
        i += varName.length;

        enforce(readU8(bytecode, i++) == 0x00, "Invalid variable name terminator");
        var = varName;
    }
    return tuple((() @trusted => cast(immutable)vars)(), i);
}

Tuple!(immutable(NamedArgument)[ ], size_t) _readNamedArgs(immutable(ubyte)[ ] bytecode, size_t i)
pure @safe {
    import std.algorithm.comparison: max;
    import std.array: uninitializedArray;
    import std.conv: emplace;

    const argsLength = readU32(bytecode, i);
    i += 4;
    // Each argument occupies at least 3 bytes.
    enforce(bytecode.length - i >= max(argsLength, (argsLength << 1) + argsLength),
        "Too many named arguments",
    );
    auto args = (() @trusted => uninitializedArray!(NamedArgument[ ])(argsLength))();
    foreach (argIndex; 0 .. argsLength) {
        const argName = readIdentifier(bytecode, i);
        enforce(!argName.empty, "Empty argument's name");
        i += argName.length;

        size_t len = void;
        switch (readU8(bytecode, i++)) {
        case 0x00: // double
            emplace(&args[argIndex], argName, Value(readF64(bytecode, i)));
            i += 8;
            continue;

        case 0x01: // string (<= 255)
            len = readU8(bytecode, i);
            i++;
            break;

        case 0x02: // string (<= 65535)
            len = readU16(bytecode, i);
            i += 2;
            break;

        case 0x03: // string
            len = readU32(bytecode, i);
            i += 4;
            break;

        default:
            throw new Exception("Unknown type of a named argument");
        }
        enforce(bytecode.length - i >= len, "Named argument's value abruptly ended");
        string argValue = cast(string)bytecode[i .. i + len];
        validateUTF(argValue);
        i += len;
        emplace(&args[argIndex], argName, Value(argValue));
    }
    return tuple((() @trusted => cast(immutable)args)(), i);
}

Tuple!(immutable(Function)[ ], size_t) _readFuncs(
    immutable(ubyte)[ ] bytecode,
    size_t i,
    const FunctionTable fTable,
    Appender!(err.BundleError[ ]) errors,
) pure @safe
out (result) {
    import std.algorithm.searching;

    assert(result[0].all!q{a !is null}, "Haven't initialized some of the functions");
}
do {
    import std.algorithm.comparison: max;
    import std.array: uninitializedArray;

    const funcsLength = readU32(bytecode, i);
    i += 4;
    // Each function occupies at least 2 bytes.
    enforce(bytecode.length - i >= max(funcsLength, funcsLength << 1), "Too many functions");
    auto funcs = (() @trusted => uninitializedArray!(Function[ ])(funcsLength))();
    bool[string] seen;
    foreach (funcIndex; 0 .. funcsLength) {
        const funcName = readFunction(bytecode, i);
        enforce(!funcName.empty, "Empty function name");
        i += funcName.length;

        enforce(readU8(bytecode, i++) == 0x00, "Invalid function name terminator");
        enforce(funcName !in seen, "Duplicate function name");
        seen[funcName] = true;
        if (const entry = funcName in fTable.functions)
            funcs[funcIndex] = entry.f;
        else {
            // Unknown function.
            errors ~= null;
            funcs[funcIndex] = defaultUnknownFunction; // Always throws.
        }
    }
    return tuple((() @trusted => cast(immutable)funcs)(), i);
}

immutable(CompiledBundle)* _loadBytecode(
    immutable(ubyte)[ ] bytecode,
    immutable(Locale)* locale,
    const FunctionTable fTable,
    Appender!(err.BundleError[ ]) errors,
) pure @safe {
    if (readU32(bytecode, 0) != bytecodeVersion) {
        // It's an expected error, so we don't throw an exception for performance reasons.
        return null;
    }
    static if (size_t.max != uint.max)
        enforce(bytecode.length <= uint.max, "Bytecode size must be less than 4 GB");

    const codeSectionSize = readU32(bytecode, 4);
    enum codeSectionAddr = 8u;
    enforce(bytecode.length - codeSectionAddr > codeSectionSize, "Invalid code section size");
    const codeSectionEnd = codeSectionAddr + codeSectionSize;

    const dataSectionSize = readU32(bytecode, codeSectionEnd);
    const dataSectionAddr = codeSectionEnd + 4;
    enforce(bytecode.length - dataSectionAddr > dataSectionSize, "Invalid data section size");
    _validateDataSection(bytecode[dataSectionAddr .. dataSectionAddr + dataSectionSize]);

    immutable messages =
        _readMessages(bytecode, dataSectionAddr + dataSectionSize, codeSectionSize);
    immutable vars = _readVars(bytecode, messages[1]);
    immutable namedArgs = _readNamedArgs(bytecode, vars[1]);
    immutable funcs = _readFuncs(bytecode, namedArgs[1], fTable, errors);
    enforce(funcs[1] == bytecode.length, "Extra data at EOF");

    // TODO: Validate code section.

    return new immutable CompiledBundle(
        bytecode, locale, funcs[0], messages[0], vars[0], namedArgs[0],
    );
}

public immutable(CompiledBundle)* loadBytecode(EH)(
    immutable(ubyte)[ ] bytecode,
    immutable(Locale)* locale,
    const FunctionTable fTable,
    scope EH onError,
) if (isErrorHandler!EH)
in {
    assert(locale !is null, "Locale must not be `null`");
    assert(onError !is null, "Error handler must not be `null`");
}
do {
    auto app = appender!(err.BundleError[ ]);
    immutable(CompiledBundle)* result;
    try {
        result = _loadBytecode(bytecode, locale, fTable, app);
        if (result is null) {
            debug (FluentD_BytecodeLoaderErrors) {
                import std.stdio;

                try
                    stderr.write("fluentd bytecode error: Wrong bytecode version\n");
                catch (Exception) { }
            }
            return null;
        }
    } catch (Exception e) {
        debug (FluentD_BytecodeLoaderErrors) {
            import std.stdio;

            try
                stderr.writeln("fluentd bytecode error: ", e.msg);
            catch (Exception) { }
        }
        return null;
    }

    foreach (ref e; app.data)
        onError(/+e+/);
    return result;
}
