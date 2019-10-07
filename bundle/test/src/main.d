void main() {
    import std.exception: enforce;
    import std.stdio;

    import fluentd.bundle.function_: createDefaultFunctionTable;
    import fluentd.bundle.locale: Locale;
    import fluentd.bundle.bytecode.loader: loadBytecode;

    import asm_.parser;
    import asm_.translator;

    import stdf = std.file;

    const bundle = parse(stdf.readText("source.asm"));
    immutable bytecode = translate(bundle);
    stdf.write("bytecode.bin", bytecode);
    auto compiled = loadBytecode(
        bytecode,
        new Locale(["en"]),
        createDefaultFunctionTable(),
        { stderr.write("An error occurred.\n"); },
    );
    if (compiled is null)
        stderr.write("Bytecode loading error.\n");
}
