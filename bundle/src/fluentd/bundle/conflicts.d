module fluentd.bundle.conflicts;

import fluentd.bundle.errors: isErrorHandler;

enum ConflictResolutionStrategy: ubyte {
    redefine,
    retain,
}

package struct _ConflictInfo(EH) if (isErrorHandler!EH) {
    EH handler;
    ConflictResolutionStrategy strategy;
}

package void _register(alias compute, C, EH)(
    ref typeof(compute())[immutable(C)[ ]] registry,
    const(C)[ ] key,
    _ConflictInfo!EH conflictInfo,
) if (isErrorHandler!EH) {
    if (auto p = key in registry) {
        conflictInfo.handler();
        if (conflictInfo.strategy == ConflictResolutionStrategy.redefine)
            *p = compute();
    } else
        registry[key] = compute();
}
