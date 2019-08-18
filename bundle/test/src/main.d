import fluentd.bundle.bundle;

void main() {
    import std.exception: enforce;
    import std.range.primitives: empty;
    import std.stdio;

    // import fluentd.bundle.compiled_bundle;
    import fluentd.bundle.function_;
    // import ast = fluentd.syntax.ast;

    auto funcs = createDefaultFunctionTable();
    funcs.add("IDENTITY", Purity.pure_, (locale, scope positional, scope named) pure @safe {
        enforce(named.empty, "No named arguments are allowed");
        enforce(positional.length == 1, "A single positional argument is required");
        return cast()positional[0];
    }, { writeln("An error occurred when adding a function."); });

    writeln(funcs.functions["IDENTITY"].f(new Locale, [Value("Hello World")], null));
}
