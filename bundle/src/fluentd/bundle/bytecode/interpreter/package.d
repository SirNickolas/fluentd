module fluentd.bundle.bytecode.interpreter;

import fluentd.bundle.compiled_bundle: CompiledPattern;
import fluentd.bundle.errors: isErrorHandler;
import fluentd.bundle.value;

string format(EH)(CompiledPattern pattern, scope const Value[string] args, scope EH onError)
if (isErrorHandler!EH)
in {
    assert(onError !is null, "Error handler must not be `null`");
}
do {
    import std.traits: isUnsafe;
    import fluentd.bundle.bytecode.interpreter.vm: execute;

    static if (isUnsafe!({ onError(); }))
        () @system { }();
    return execute(pattern.bundle, pattern.address, args, () @trusted { onError(); });
}

string format(EH)(CompiledPattern pattern, scope EH onError) if (isErrorHandler!EH) {
    return format(pattern, null, onError);
}
