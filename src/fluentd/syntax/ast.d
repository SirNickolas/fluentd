module fluentd.syntax.ast;

import std.meta: staticIndexOf;
import std.range.primitives: empty;

import sumtype;

@safe:

/+
    Expressions:
+/
struct TextElement {
    string content;

    invariant {
        assert(!content.empty, "Empty text");
    }
}

struct Identifier {
    string name;

    invariant {
        assert(!name.empty, "Empty identifier");
    }
}

struct OptionalIdentifier {
    string name;
}

struct StringLiteral {
    string value;
}

struct NumberLiteral {
    string value;

    invariant {
        assert(!value.empty, "Empty number literal");
    }
}

alias Literal = SumType!(StringLiteral, NumberLiteral);

struct NamedArgument {
    Identifier name;
    Literal value;
}

struct CallArguments {
    InlineExpression[ ] positional;
    NamedArgument[ ] named;
}

struct FunctionReference {
    Identifier id;
    CallArguments arguments;
}

struct MessageReference {
    Identifier id;
    OptionalIdentifier attribute;
}

struct TermReference {
    Identifier id;
    OptionalIdentifier attribute;
    CallArguments arguments;
}

struct VariableReference {
    Identifier id;
}

struct InlineExpression {
    SumType!(
        StringLiteral,
        NumberLiteral,
        FunctionReference,
        MessageReference,
        TermReference,
        VariableReference,
        Expression*,
    ) value;

    alias value this;

    invariant {
        value.match!(
            (const(Expression)* e) {
                assert(e !is null, "Null `Expression` as part of `InlineExpression`");
            },
            (_) { },
        );
    }

    this(T)(T x) nothrow pure @nogc if (staticIndexOf!(T, typeof(value).Types) >= 0) {
        value = x;
    }
}

alias VariantKey = SumType!(Identifier, NumberLiteral);

alias PatternElement = SumType!(TextElement, Expression);

struct Pattern {
    PatternElement[ ] elements;
}

struct Variant {
    VariantKey key;
    Pattern value;
    bool default_;

    invariant {
        assert(!value.elements.empty, "Empty variant");
    }
}

struct SelectExpression {
    InlineExpression selector;
    Variant[ ] variants;

    invariant {
        assert(!variants.empty, "Empty selection");
    }
}

/+
    DMD's support for recursive templates is quite restricted.
    For example, these declarations are sane, but, unfortunately, do not compile:

    struct A { }
    struct B { }
    alias C = SumType!(A, D*);
    alias D = SumType!(B, C);

    We have to manually break the template chain by defining a struct.
+/
struct Expression {
    SumType!(InlineExpression, SelectExpression) value;

    alias value this;

    this(T)(T x) nothrow pure @nogc if (staticIndexOf!(T, typeof(value).Types) >= 0) {
        value = x;
    }
}
/+
    End of expressions.
+/

struct NoComment { }

struct Comment {
    string content;
}

struct GroupComment {
    string content;
}

struct ResourceComment {
    string content;
}

alias OptionalComment = SumType!(NoComment, Comment);
alias AnyComment = SumType!(Comment, GroupComment, ResourceComment);

struct Attribute {
    Identifier id;
    Pattern value;

    invariant {
        assert(!value.elements.empty, "Empty attribute");
    }
}

struct Message {
    Identifier id;
    Pattern value;
    Attribute[ ] attributes;
    OptionalComment comment;

    invariant {
        assert(!value.elements.empty || !attributes.empty, "Empty message");
    }
}

struct Term {
    Identifier id;
    Pattern value;
    Attribute[ ] attributes;
    OptionalComment comment;

    invariant {
        assert(!value.elements.empty, "Empty term");
    }
}

alias Entry = SumType!(Message, Term, AnyComment);

struct Junk {
    string content;

    invariant {
        assert(!content.empty, "Empty junk");
    }
}

alias ResourceEntry = SumType!(Junk, Entry);

struct Resource {
    ResourceEntry[ ] body;
}
