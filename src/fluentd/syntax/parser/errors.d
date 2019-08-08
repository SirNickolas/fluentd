module fluentd.syntax.parser.errors;

import fluentd.syntax.parser.span;

private template _declareSumType(string name, Spec...) {
    import std.array: join;
    import std.meta: Stride;
    import std.range: iota;
    import sumtype;

    static assert(!(Spec.length & 0x1));

    static foreach (i; iota(0, Spec.length, 2))
        mixin(`struct ` ~ Spec[i] ~ `{` ~ Spec[i + 1] ~ `}`);

    mixin(`alias ` ~ name ~ `= SumType!(` ~ [Stride!(2, Spec)].join(',') ~ `);`);
}

mixin _declareSumType!(q{ErrorKind},
    q{ExpectedCharRange}, q{string range;},
    q{ExpectedMessageField}, q{string id;},
    q{ExpectedTermField}, q{string id;},
    q{MissingValue}, q{},
    q{UnbalancedClosingBrace}, q{},
    q{UnterminatedStringExpression}, q{},
    q{ExpectedInlineExpression}, q{},
    q{TermAttributeAsPlaceable}, q{},
    q{ForbiddenCallee}, q{},
    q{InvalidArgumentName}, q{},
    q{ExpectedLiteral}, q{},
    q{DuplicatedNamedArgument}, q{string name;},
    q{PositionalArgumentFollowsNamed}, q{},
);

struct ParserError {
    Span span;
    ErrorKind kind;
}
