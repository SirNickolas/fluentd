# fluentd

Fluent is a localization system designed to unleash the expressive power
of the natural language.

This is an implementation of [Fluent][fluent] in the
[D Programming Language][dlang].

It is in early development state and definitely **not** suited for production (or
any other) use.

[fluent]: https://github.com/projectfluent/fluent
[dlang]:  https://dlang.org


## Future work

* Compile `Bundle`s to bytecode and interpret it on a VM. This will give
  the following advantages:
  1. Very much stuff in FTL can be inlined, so that most messages would become
     constants. It will help to reduce allocations (can share a single instance
     of an immutable string).
  2. One can cache the bytecode, avoiding costly parsing, optimizing, and code
     generation stages during program startup.
* Create D bindings to libIntl.
