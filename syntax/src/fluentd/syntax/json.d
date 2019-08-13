module fluentd.syntax.json;

template convertTo(JSON) {
    import std.traits: isAggregateType;

    import sumtype;

    import ast = fluentd.syntax.ast;

    nothrow pure @safe:

    // Pointers:

    JSON convertTo(T)(const(T)* ptr) {
        return ptr is null ? JSON.init : convertTo(*ptr);
    }

    // Arrays:

    JSON convertTo(T)(const(T)[ ] items) {
        import std.algorithm.iteration;
        import std.array;

        return JSON(items.map!convertTo().array());
    }

    // Sum types:

    JSON convertTo(T: SumType!Args, Args...)(const T value) {
        // Can drop the `else` branch when the fix for https://github.com/pbackus/sumtype/issues/28
        // is released.
        static if (is(T == SumType!Args))
            return value.match!convertTo();
        else
            return value.value.match!convertTo();
    }

    // Structs:

    JSON convertTo(T)(const T value) if (isAggregateType!T) {
        import std.algorithm.iteration: map;
        import std.array: join;
        import std.string: chomp, format;
        import std.traits: FieldNameTuple;

        return JSON(mixin(
            `["type":JSON(T.stringof)` ~ [FieldNameTuple!T].map!(
                field => `,"%s":convertTo(value.%s)`.format(field.chomp("_"), field)
            ).join() ~ ']'
        ));
    }

    // Primitive types:

    JSON convertTo(bool b) {
        return JSON(b);
    }

    JSON convertTo(string s) {
        return JSON(s);
    }

    // Special cases:

    JSON convertTo(const ast.OptionalIdentifier value) {
        import std.range.primitives: empty;

        return value.name.empty ? JSON.init : convertTo(ast.Identifier(value.name));
    }

    JSON convertTo(const ast.NoCallArguments _) {
        return JSON.init;
    }

    JSON convertTo(const ast.Pattern pattern) {
        import std.range.primitives: empty;

        return pattern.elements.empty ? JSON.init : JSON([
            "type": JSON("Pattern"),
            "elements": convertTo(pattern.elements),
        ]);
    }

    JSON convertTo(const ast.NoComment _) {
        return JSON.init;
    }
}

nothrow pure @safe unittest {
    import std.json;
    import fluentd.syntax.ast;

    // `Resource` causes instantiation of the whole template graph.
    assert(Resource.init.convertTo!JSONValue() == JSONValue([
        "type": JSONValue("Resource"),
        "body": JSONValue(JSONValue[ ].init),
    ]));
}