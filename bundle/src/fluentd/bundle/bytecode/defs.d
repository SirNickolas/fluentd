module fluentd.bundle.bytecode.defs;

enum bytecodeVersion = 0u;

enum OpCode: ubyte {
    retData1, // 2*addr, 1*size
    retData2, // 2*addr, 2*size
    retData4, // 4*addr, 4*size
}
