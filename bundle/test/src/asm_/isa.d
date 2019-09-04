module asm_.isa;

import std.traits: CommonType;

import fluentd.bundle.bytecode.defs;

enum ArgumentType: ubyte {
    // string2,
    string4,
    // codeOffset1,
    // codeOffset2,
    codeOffset4,
}

struct InstructionDef {
    OpCode opCode;
    immutable(ArgumentType)[ ] args;
}

private immutable CommonType!values[values.length] _array(values...) = [values];

private alias _args(string types) = _array!({
    import std.typecons;

    with (ArgumentType)
        return mixin(`tuple(` ~ types ~ ')');
}().expand);

immutable InstructionDef[ ][string] overloads;

shared static this() nothrow pure @safe {
    overloads = [
        "app": _array!(
            // InstructionDef(OpCode.appData2, _args!q{string2}[ ]),
            InstructionDef(OpCode.appData4, _args!q{string4}[ ]),
        )[ ],
        "ret": _array!(
            InstructionDef(OpCode.retBuffer, [ ]),
            // InstructionDef(OpCode.retData2, _args!q{string2}[ ]),
            InstructionDef(OpCode.retData4, _args!q{string4}[ ]),
        )[ ],
        "jmp": _array!(
            // InstructionDef(OpCode.jmp1, _args!q{codeOffset1}[ ]),
            // InstructionDef(OpCode.jmp2, _args!q{codeOffset2}[ ]),
            InstructionDef(OpCode.jmp4, _args!q{codeOffset4}[ ]),
        )[ ],
        "call": _array!(
            // InstructionDef(OpCode.call1, _args!q{codeOffset1}[ ]),
            // InstructionDef(OpCode.call2, _args!q{codeOffset2}[ ]),
            InstructionDef(OpCode.call4, _args!q{codeOffset4}[ ]),
        )[ ],
    ];
}
