void main() {
    import std.exception: enforce;
    import std.stdio;

    import fluentd.bundle.compiled_bundle: CompiledPattern, NoCompiledPattern;
    import fluentd.bundle.function_: createDefaultFunctionTable;
    import fluentd.bundle.locale: Locale;
    import fluentd.bundle.bytecode.loader: loadBytecode;
    import sumtype;

    import asm_.parser;
    import asm_.translator;

    import stdf = std.file;

    const asmBundle = parse(stdf.readText("source.asm"));
    immutable bytecode = translate(asmBundle);
    stdf.write("bytecode.bin", bytecode);

    immutable bundle = loadBytecode(
        bytecode,
        new immutable Locale(["en"]),
        createDefaultFunctionTable(),
        { stderr.write("A non-fatal error occurred while loading the bytecode.\n"); },
    );
    if (bundle is null) {
        stderr.write("Cannot load the bytecode.\n");
        return;
    }

    static void onError() {
        stderr.write("An error occurred while formatting a pattern.\n");
    }

    foreach (ref msg; bundle.getMessages()) {
        writeln(msg.name);
        msg.message.value.match!(
            (ref CompiledPattern pattern) {
                write("= «", /+pattern.format(&onError),+/ "»\n");
            },
            (NoCompiledPattern _) { },
        );
        foreach (ref attr; msg.message.getAttributes()) {
            write('.', attr.name, " = «", /+attr.pattern.format(&onError),+/ "»\n");
        }
    }
}
