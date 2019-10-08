module fluentd.bundle.bytecode.interpreter.vm;

import std.array: Appender;
import std.bitmanip: Endian, peek;

import fluentd.bundle.compiled_bundle: CompiledBundle;
import fluentd.bundle.value;

private @safe:

// Since application-defined functions may themselves format patterns, `execute` should
// be reenterable. We keep a thread-local stack of `_ExecutionFrame`s for that.
struct _ExecutionFrame {
    Appender!(char[ ]) buffer;
}

struct _ExecutionStack {
    Appender!(_ExecutionFrame[ ]) frames;
    uint size;
}

_ExecutionStack _stack;

static this() nothrow {
    import std.array;

    _stack = _ExecutionStack(appender!(_ExecutionFrame[ ]));
}

ubyte _readU8(immutable(ubyte)[ ] data, size_t i) nothrow pure @nogc {
    return data[i];
}

ushort _readU16(immutable(ubyte)[ ] data, size_t i) nothrow pure @trusted @nogc {
    return peek!(ushort, Endian.littleEndian)(data[i .. $]);
}

uint _readU32(immutable(ubyte)[ ] data, size_t i) nothrow pure @trusted @nogc {
    return peek!(uint, Endian.littleEndian)(data[i .. $]);
}

double _readF64(immutable(ubyte)[ ] data, size_t i) nothrow pure @trusted @nogc {
    return peek!(double, Endian.littleEndian)(data[i .. $]);
}

mixin template _readSlice32() {
    const ptr = _readU16(codeSection, ip);
    const len = _readU16(codeSection, ip + 2);
}

mixin template _readSlice64() {
    const ptr = _readU32(codeSection, ip);
    const len = _readU32(codeSection, ip + 4);
}

mixin template _readDataSlice32() {
    mixin _readSlice32;
    const slice = cast(string)dataSection[ptr .. ptr + len];
}

mixin template _readDataSlice64() {
    mixin _readSlice64;
    const slice = cast(string)dataSection[ptr .. ptr + len];
}

string _execute(
    scope ref _ExecutionFrame frame,
    immutable(CompiledBundle)* bundle,
    uint ip,
    scope const Value[string] args,
    scope void delegate() @safe onError,
) {
    import fluentd.bundle.bytecode.defs;

    immutable codeSection = bundle.codeSection;
    immutable dataSection = bundle.dataSection;
    auto buffer = frame.buffer;
    while (true)
        final switch (cast(OpCode)codeSection[ip++]) {
        case OpCode.appData2:
            mixin _readDataSlice32 arg;
            ip += 4;
            buffer ~= arg.slice;
            break;

        case OpCode.appData4:
            mixin _readDataSlice64 arg;
            ip += 8;
            buffer ~= arg.slice;
            break;

        case OpCode.retData2:
            mixin _readDataSlice32 arg;
            return arg.slice;

        case OpCode.retData4:
            mixin _readDataSlice64 arg;
            return arg.slice;

        case OpCode.retBuffer:
            return buffer.data.idup;

        case OpCode.call4:
            assert(false, "Not implemented");

        case OpCode.jmp4:
            ip = _readU32(codeSection, ip);
            break;
        }
}

package string execute(
    immutable(CompiledBundle)* bundle,
    uint addr,
    scope const Value[string] args,
    scope void delegate() @safe onError,
) {
    import std.array: appender;

    auto stack = &_stack;
    const frameIndex = stack.size++;
    scope(exit) stack.size--;
    _ExecutionFrame* frame;
    auto frames = stack.frames.data;
    if (frameIndex != frames.length) {
        frame = &frames[frameIndex];
        frame.buffer.clear();
    } else {
        stack.frames ~= _ExecutionFrame(appender!(char[ ]));
        frame = &stack.frames.data[frameIndex];
    }
    return _execute(*frame, bundle, addr, args, onError);
}
