module fluentd.bundle.locale;

struct Locale {
nothrow pure @safe @nogc:
    private {
        immutable(string)[ ] _languages;
        // TODO: Store `Intl` objects.
    }

    this(immutable(string)[ ] languages) inout {
        _languages = languages;
        // TODO: Create `Intl` objects.
    }

    @property immutable(string)[ ] languages() const {
        return _languages;
    }
}
