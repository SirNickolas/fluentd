module fluentd.bundle.errors;

import std.traits: isDelegate, isFunctionPointer;

import sumtype;

// TODO: Define errors.

// TODO: Error handler should take an error object, obviously.
enum isErrorHandler(F) =
    (isDelegate!F || isFunctionPointer!F) && __traits(compiles, F.init());
