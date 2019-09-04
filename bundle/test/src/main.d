void main() {
    import asm_.parser;
    import asm_.translator;
    import stdf = std.file;

    const bundle = parse(stdf.readText("source.asm"));
    immutable bytecode = translate(bundle);
    stdf.write("bytecode.bin", bytecode);
}
