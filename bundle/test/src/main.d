void main() {
    import std.stdio;
    import asm_.grammar;

    write(Assembly("\t\t   \n\t.extern FUNC-A [pure]; a\r\n.extern FUNC-B[ impure ] \r.extern FUNC-C[pure]\n\n.extern FUNC-D [impure]\n\t hello :\n@msg.attr:\n\nret -0 , @msg.attr , \"string\""));
}
