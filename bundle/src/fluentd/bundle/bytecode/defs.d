module fluentd.bundle.bytecode.defs;

enum bytecodeVersion = 0u;

enum OpCode: ubyte {
    appData2, // 2*addr, 2*size
    appData4, // 4*addr, 4*size
    retData2, // 2*addr, 2*size
    retData4, // 4*addr, 4*size
    retBuffer,
    // call2, // 2*offset
    call4, // 4*offset
    // jmp1, // 1*offset
    // jmp2, // 2*offset
    jmp4, // 4*offset
}
