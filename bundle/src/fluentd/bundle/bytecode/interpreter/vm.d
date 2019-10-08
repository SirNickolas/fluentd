module fluentd.bundle.bytecode.interpreter.vm;

import std.array: Appender;

import fluentd.bundle.compiled_bundle: CompiledBundle;
import fluentd.bundle.value;

private @safe:

// Since application-defined functions may themselves format patterns, `execute` should
// be reenterable. We keep a thread-local stack of `_ExecutionFrame`s for that.
struct _ExecutionFrame {
    //
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

string _execute(
    scope ref _ExecutionFrame frame,
    immutable(CompiledBundle)* bundle,
    uint addr,
    scope const Value[string] args,
    scope void delegate() @safe onError,
) {
    assert(false, "Not implemented");
}

package string execute(
    immutable(CompiledBundle)* bundle,
    uint addr,
    scope const Value[string] args,
    scope void delegate() @safe onError,
) {
    auto stack = &_stack;
    const frameIndex = stack.size++;
    scope(exit) stack.size--;
    _ExecutionFrame* frame;
    auto frames = stack.frames.data;
    if (frameIndex != frames.length) {
        frame = &frames[frameIndex];
        // TODO: Init `frame`.
    } else {
        stack.frames ~= _ExecutionFrame();
        frame = &stack.frames.data[frameIndex];
    }
    return _execute(*frame, bundle, addr, args, onError);
}
