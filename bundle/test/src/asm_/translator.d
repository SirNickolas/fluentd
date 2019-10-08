module asm_.translator;

import std.array: Appender;
import std.traits: isMutable, isUnsigned;

import fluentd.bundle.bytecode.defs;

import asm_.bundle;
import asm_.type_system: resolveInstr = resolve;

private pure @safe:

struct _Buffer(C: ubyte) {
nothrow pure:
    Appender!(C[ ]) app;

    inout(C)[ ] data() inout @nogc {
        return app.data;
    }

    void write(T: U, U)(U x) if (isUnsigned!U) {
        import std.bitmanip: Endian, append;

        append!(T, Endian.littleEndian)(app, x);
    }

    void write(T: const(char)[ ])(const(char)[ ] s) {
        app ~= cast(const(ubyte)[ ])s;
    }

    static if (isMutable!C)
    void overwrite(T: U, U)(U x, uint offset) @trusted if (isUnsigned!U) {
        import std.bitmanip: Endian, write;

        write!(T, Endian.littleEndian)(data, x, offset);
    }
}

_Buffer!C _createBuffer(C: ubyte)() nothrow {
    import std.array;

    return _Buffer!C(appender!(C[ ]));
}

struct _DataSection {
nothrow pure:
    _Buffer!(immutable ubyte) buffer;
    uint[string] aa;

    @disable this(this);

    uint add(const(char)[ ] s) {
        if (const p = s in aa)
            return *p;
        const offset = cast(uint)buffer.data.length;
        buffer.write!string(s);
        aa[cast(string)buffer.data[offset .. $]] = offset;
        return offset;
    }
}

struct _DelayedOffset {
    AsmLineNumber lineNumber;
    uint offsetToWrite;
}

struct _Translator {
pure:
    const(AsmBundle)* bundle;
    _Buffer!ubyte code;
    Appender!(immutable(uint)[ ]) codeOffsets; // Indexed with `AsmLineNumber`s.
    _DataSection data;
    _Buffer!(immutable ubyte) messages, functions;
    Appender!(immutable(_DelayedOffset)[ ]) delayedOffsets;

    uint getCodeOffset(AsmLineNumber n)
    in {
        assert(n != AsmLineNumber.init);
    }
    do {
        import std.exception: enforce;

        enforce(n < codeOffsets.data.length, "Invalid label");
        return codeOffsets.data[n];
    }

    AsmLineNumber resolveLabel(ref const AsmLabel label) {
        import std.exception: enforce;
        import std.range.primitives: empty;

        if (!label.public_) {
            const p = label.name in bundle.privateLabels;
            enforce(p !is null, "Unknown label: " ~ label.name);
            return *p;
        }
        const msgId = label.name in bundle.messageIds;
        enforce(msgId !is null, "Unknown label: @" ~ label.name);
        const msg = &bundle.messages[*msgId];
        if (label.attribute.empty) {
            enforce(msg.value != AsmLineNumber.init, "Unknown label: @" ~ label.name);
            return msg.value;
        }
        const p = label.attribute in msg.attributes;
        enforce(p !is null, "Unknown label: @" ~ label.name ~ '.' ~ label.attribute);
        return *p;
    }

    void translateMessages() {
        import std.algorithm.sorting: sort;
        import std.array: array;

        with (messages) {
            foreach (ref msg; bundle.messages) {
                write!string(msg.name);
                if (msg.value != AsmLineNumber.init) {
                    write!ubyte(0x00);
                    write!uint(getCodeOffset(msg.value));
                } else
                    write!ubyte(0x02);

                foreach (ref attr; msg.attributes.byKeyValue().array().sort!q{a.value < b.value}) {
                    write!string(attr.key);
                    write!ubyte(0x01);
                    write!uint(getCodeOffset(attr.value));
                }
            }
            write!ubyte(0x00);
        }
    }

    void translateFunctions() {
        with (functions) {
            write!uint(cast(uint)bundle.functions.length);
            foreach (f; bundle.functions) {
                write!string(f.name);
                write!ubyte(0x00);
            }
        }
    }

    void writeLabelReference(ref const AsmLabel label) {
        const resolved = resolveLabel(label);
        if (resolved < codeOffsets.data.length)
            code.write!uint(getCodeOffset(resolved));
        else {
            delayedOffsets ~= _DelayedOffset(resolved, cast(uint)code.data.length);
            code.write!uint(uint.max);
        }
    }

    void translateCodeLine(ref const AsmCodeLine line) {
        import sumtype;
        import isa = asm_.isa;

        const def = resolveInstr(line);
        codeOffsets ~= cast(uint)code.data.length;
        code.write!ubyte(def.opCode);
        foreach (i, arg; line.arguments)
            arg.match!(
                (string s) {
                    const offset = data.add(s);
                    assert(def.args[i] == isa.ArgumentType.string4);
                    code.write!uint(offset);
                    code.write!uint(cast(uint)s.length);
                },
                (double _) { assert(false, "Not implemented"); },
                (ref const AsmLabel label) {
                    assert(def.args[i] == isa.ArgumentType.codeOffset4);
                    writeLabelReference(label);
                },
            );
    }

    void translateCode() {
        foreach (ref line; bundle.code)
            translateCodeLine(line);
        foreach (ref delayed; delayedOffsets)
            code.overwrite!uint(getCodeOffset(delayed.lineNumber), delayed.offsetToWrite);
    }

    void translate() {
        translateFunctions();
        translateCode();
        translateMessages();
    }
}

public immutable(ubyte)[ ] translate(ref const AsmBundle bundle) {
    import std.array: appender;
    import std.bitmanip: nativeToLittleEndian;

    _Translator t = {
        bundle: (() @trusted => &bundle)(),
        code: _createBuffer!ubyte(),
        codeOffsets: appender!(immutable(uint)[ ]),
        data: _DataSection(_createBuffer!(immutable ubyte)),
        messages: _createBuffer!(immutable ubyte),
        functions: _createBuffer!(immutable ubyte),
        delayedOffsets: appender!(immutable(_DelayedOffset)[ ]),
    };
    t.translate();

    enum magic = nativeToLittleEndian(bytecodeVersion);
    immutable ubyte[8] unimplemented;
    return
        magic ~
        nativeToLittleEndian(cast(uint)t.code.data.length) ~
        t.code.data ~
        nativeToLittleEndian(cast(uint)t.data.buffer.data.length) ~
        t.data.buffer.data ~
        t.messages.data ~
        unimplemented ~
        t.functions.data;
}
