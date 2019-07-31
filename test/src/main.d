import std.stdio;
import stdf = std.file;

import ftl = fluentd.syntax.parser;

void main(string[ ] args) {
    writeln(ftl.parse(stdf.readText(args[1])));
}
