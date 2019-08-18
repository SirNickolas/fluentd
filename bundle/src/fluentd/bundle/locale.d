module fluentd.bundle.locale;

struct Locale {
nothrow @safe @nogc:
    private {
        immutable(string)[ ] _languages;
        // TODO: Store `Intl` objects.
    }

    this(immutable(string)[ ] languages) pure {
        _languages = languages;
        // TODO: Create `Intl` objects.
    }

    @property immutable(string)[ ] languages() const pure {
        return _languages;
    }
}
