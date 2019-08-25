module asm_.bundle;

import std.range.primitives: empty;

import sumtype;

struct AsmLineNumber {
    size_t value = size_t.max;

    alias value this;
}

struct ExternDefinition {
    string name;
    bool pure_;

    invariant {
        assert(!name.empty);
    }
}

struct AsmMessage {
    string name;
    AsmLineNumber value;
    AsmLineNumber[string] attributes;

    invariant {
        assert(!name.empty);
    }
}

struct AsmLabel {
    bool public_;
    string name;
    string attribute;

    invariant {
        assert(!name.empty);
        assert(public_ || attribute.empty);
    }
}

alias AsmInstructionArgument = SumType!(string, double, AsmLabel);

struct AsmCodeLine {
    string instruction;
    AsmInstructionArgument[ ] arguments;

    invariant {
        assert(!instruction.empty);
    }
}

struct AsmBundle {
    ExternDefinition[ ] functions;
    AsmMessage[ ] messages;
    AsmCodeLine[ ] code;
    size_t[string] functionIds, messageIds;
    AsmLineNumber[string] privateLabels;
}
