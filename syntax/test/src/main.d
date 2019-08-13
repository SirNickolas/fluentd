import std.json;
import stdf = std.file;

import ftl = fluentd.syntax;

private @safe:

JSONValue parseJSONFile(string fileName) @system {
    import std.mmfile;
    import std.typecons: scoped;

    auto mmf = scoped!MmFile(fileName);
    return parseJSON(cast(const(char)[ ])(cast(MmFile)mmf)[ ]);
}

ftl.Resource parse(string source) nothrow pure {
    return ftl.parse(source).resource;
}

bool test(string fileName) @system
in {
    import std.algorithm.searching: endsWith;

    assert(fileName.endsWith(".ftl"));
}
do {
    import std.stdio: File;

    // `stdf.readText` UTF-validates the file, and we don't want it to happen here.
    immutable rc = parse(cast(string)stdf.read(fileName));
    immutable ourJSON = ftl.convertTo!JSONValue(rc);
    File(fileName[0 .. $ - 3] ~ "out.json", "w").writeln(ourJSON.toPrettyString());
    return ourJSON == parseJSONFile(fileName[0 .. $ - 3] ~ "json");
}

bool testAndReport(string fileName, string testName) @system {
    import std.path: baseName;
    import std.stdio;

    try
        if (test(fileName))
            return true;
    catch (Exception e) {
        write(e, "\n\n");
        goto failure;
    }
    writefln("Test `%s` failed.", testName);
failure:
    stdout.flush();
    return false;
}

int main() @system {
    import std.stdio;
    import std.string: makeTransTable, translate;

    uint ok, failed;
    foreach (string fileName; stdf.dirEntries("fixtures", "*.ftl", stdf.SpanMode.breadth))
        if (testAndReport(fileName, fileName[9 .. $ - 4].translate(makeTransTable(`\`, "/"))))
            ok++;
        else
            failed++;

    if (!failed) {
        writefln("%s OK.", ok);
        return 0;
    }

    writefln("%s FAILURES, %s OK.", failed, ok);
    return 1;
}
