import std.json;
import stdf = std.file;

import ftl = fluentd.syntax;

private @safe:

JSONValue parseJSONFile(string filename) @system {
    import std.mmfile;
    import std.typecons: scoped;

    auto mmf = scoped!MmFile(filename);
    return parseJSON(cast(const(char)[ ])(cast(MmFile)mmf)[ ]);
}

ftl.Resource parse(string source) nothrow pure {
    return ftl.parse(source).resource;
}

void test(string filename) @system
in {
    import std.algorithm.searching: endsWith;

    assert(filename.endsWith(".ftl"));
}
do {
    import std.stdio: File;

    // `stdf.readText` UTF-validates the file, and we don't want it to happen here.
    immutable rc = parse(cast(string)stdf.read(filename));
    immutable ourJSON = ftl.convertTo!JSONValue(rc);
    File(filename[0 .. $ - 3] ~ "out.json", "w").writeln(ourJSON.toPrettyString());

    const refJSON = parseJSONFile(filename[0 .. $ - 3] ~ "json");
    // TODO: Compare `ourJSON` against `refJSON`.
}

int main() @system {
    import std.stdio;

    int ret = 0;
    foreach (string filename; stdf.dirEntries("fixtures", "*.ftl", stdf.SpanMode.breadth))
        try
            test(filename);
        catch (Exception e) {
            writeln(e);
            ret = 1;
        }
    return ret;
}
