import std.stdio;
import stdf = std.file;

import ftl = fluentd.syntax.parser;

void main(string[ ] args) {
    auto result = ftl.parse(stdf.readText(args[1]));
    writefln(
        "ParserResult(Resource([\n%(    %s,\n%|%)]), [\n%(    %s,\n%|%)])",
        result.resource.body,
        result.errors,
    );
}
