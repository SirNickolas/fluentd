import std.json;
import stdf = std.file;

import ftl = fluentd.syntax;

private @safe:

immutable string[1] skippedTests = [
    // Currently, the whole `Message` turns into `Junk` if there is an error in its attribute.
    // Github issue #3.
    "reference/leading_dots",
];

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
    writef("Test `%s` failed.\n", testName);
failure:
    stdout.flush();
    return false;
}

int main() @system {
    import std.algorithm.searching: canFind;
    import std.range.primitives: empty;
    import std.stdio;
    import std.string: makeTransTable, translate;

    enum backslashToSlash = makeTransTable(`\`, "/");
    uint ok, failed, skipped;
    foreach (string fileName; stdf.dirEntries("fixtures", "*.ftl", stdf.SpanMode.breadth)) {
        const testName = fileName[9 .. $ - 4].translate(backslashToSlash);
        if (skippedTests[ ].canFind(testName))
            skipped++;
        else if (testAndReport(fileName, testName))
            ok++;
        else
            failed++;
    }

    if (skipped != skippedTests.length)
        writefln("%s tests were going to be skipped, but only %s were found.",
            skippedTests.length, skipped,
        );

    if (failed)
        writef("%s FAILURES, ", failed);
    writef("%s OK", ok);
    if (!skippedTests.empty)
        writef(", %s skipped", skipped);
    write(".\n");

    return !!failed;
}
