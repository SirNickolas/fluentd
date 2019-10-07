module fluentd.bundle.bytecode.parser;

import std.bitmanip: Endian, peek;
import std.exception: enforce;

import fluentd.utils.lexing;

pure @safe:

/+
    Bytecode structure:
        [u32] Bytecode version.
        [u32] Code section's size.
        [...] Code section.
        [u32] Data section's size.
        [...] Data section.
        [...] Export table.
        [u8]  (0x00) Zero terminator.
        [u32] Number of variables.
        [...] Variables table.
        [u32] Number of named arguments.
        [...] Named arguments table.
        [u32] Number of functions.
        [...] Functions table.

    Export table entry:
        [...] Identifier.
        [u8]  Entry type.
        |   (0x00) Message.
            [u32] Address in the code section.
        |   (0x01) Attribute of the previous message.
            [u32] Address in the code section.
        |   (0x02) Message without value.

    Variables table entry:
        [...] Identifier.
        [u8]  (0x00) Zero terminator.

    Named arguments table entry:
        [...] Identifier.
        [u8]  Type.
        |   (0x00) Number.
            [f64] Double.
        |   (0x01) Short string.
            [u8]  String length.
            [...] String.
        |   (0x02) Normal string.
            [u16] String length.
            [...] String.
        |   (0x03) Huge string.
            [u32] String length.
            [...] String.

    Functions table entry:
        [...] Identifier.
        [u8]  (0x00 | 0x01) Purity.

    Code section consists of (surprise) code for messages and non-inlined terms.
    Data section contains all strings used by the resource. It must be valid UTF-8.

    All numbers are stored in little-endian format.
+/

ubyte readU8(immutable(ubyte)[ ] data, size_t i)
in {
    assert(i <= data.length);
}
do {
    enforce(i < data.length, "Not enough space for U8");
    return data[i];
}

ushort readU16(immutable(ubyte)[ ] data, size_t i) @trusted
in {
    assert(i <= data.length);
}
do {
    enforce(data.length - i >= 2, "Not enough space for U16");
    return peek!(ushort, Endian.littleEndian)(data[i .. $]);
}

uint readU32(immutable(ubyte)[ ] data, size_t i) @trusted
in {
    assert(i <= data.length);
}
do {
    enforce(data.length - i >= 4, "Not enough space for U32");
    return peek!(uint, Endian.littleEndian)(data[i .. $]);
}

double readF64(immutable(ubyte)[ ] data, size_t i) @trusted
in {
    assert(i <= data.length);
}
do {
    enforce(data.length - i >= 8, "Not enough space for F64");
    return peek!(double, Endian.littleEndian)(data[i .. $]);
}

private string _readIdentifier(alias isValidFirstChar, alias isValidChar)(
    immutable(ubyte)[ ] data, size_t i,
) nothrow @nogc
in {
    assert(i <= data.length);
}
do {
    if (i == data.length || !isValidFirstChar(data[i]))
        return null;
    const start = i;
    while (++i < data.length && isValidChar(data[i])) { }
    return cast(string)data[start .. i];
}

alias readIdentifier = (data, i) => _readIdentifier!(isAlpha, isIdent)(data, i);
alias readFunction   = (data, i) => _readIdentifier!(isUpper, isCallee)(data, i);
