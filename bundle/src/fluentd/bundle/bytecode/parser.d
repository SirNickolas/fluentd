module fluentd.bundle.bytecode.parser;

import std.bitmanip: Endian, peek;
import std.exception: enforce;

import fluentd.utils.lexing;

pure @safe:

/+
    Bytecode structure:

    [0x0 .. 0x4]: Bytecode version.
    [0x4 .. 0x8]: Data section address (X; X >= 0xC).
    [0x8 .. 0xC]: Init section address (Y; Y >= X).
    [0xC .. X]:   Code section.
    [X .. Y]:     Data section.
    [Y .. $]:     Init section.

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

alias readIdentifier = _readIdentifier!(isAlpha, isIdent);
alias readFunction   = _readIdentifier!(isUpper, isCallee);
