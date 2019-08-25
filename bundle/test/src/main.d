void main() {
    import std.stdio;
    import asm_.grammar;
    import asm_.parser;

    enum source = "   \n.extern FUNC-A [pure]; a\r\n.extern FUNC-B[ impure ] \r.extern FUNC-C[pure]\n\n.extern FUNC-D [impure]\n hello :\n@msg.attr:\n\nret -0 , @msg.attr , \"string\"";
    write(Assembly(source));
    auto bundle = parse(source);
}
