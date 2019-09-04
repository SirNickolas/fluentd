module asm_.type_system;

import fluentd.bundle.bytecode.defs;

import asm_.bundle;
import isa = asm_.isa;

pure @safe:

immutable(isa.InstructionDef)[ ] getOverloads(const(char)[ ] instr) {
    import std.exception: enforce;

    const p = instr in isa.overloads;
    enforce(p !is null, "Unknown instruction: " ~ instr);
    return *p;
}

bool isCompatible(ref const AsmInstructionArgument arg, isa.ArgumentType type) nothrow @nogc {
    import sumtype;
    import fluentd.utils.sumtype;

    return arg.match!(
        case_!(string, () => type == isa.ArgumentType.string4),
        case_!(double, () => false),
        case_!(AsmLabel, () => type == isa.ArgumentType.codeOffset4),
    );
}

immutable(isa.InstructionDef) resolve(
    immutable(isa.InstructionDef)[ ] overloads,
    ref const AsmCodeLine line,
) {
    import std.algorithm.searching: all, find;
    import std.exception: enforce;
    import std.range: empty, front, zip;

    const args = line.arguments;
    auto result = overloads.find!(overload =>
        overload.args.length == args.length && zip(args, overload.args).all!(
            t => isCompatible(t.expand)
        )
    );
    enforce(!result.empty, "No matching overload: " ~ line.instruction);
    return result.front;
}

immutable(isa.InstructionDef) resolve(ref const AsmCodeLine line) {
    return resolve(getOverloads(line.instruction), line);
}
