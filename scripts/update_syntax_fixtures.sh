#!/usr/bin/env bash

set -euo pipefail
IFS=$'\t\n'
[ $# = 0 ] || exit 2
cd -- "$(dirname -- "$0")"/..

if cd fluent/; then
    echo 'Pulling from projectfluent/fluent...'
    git pull
    cd - >/dev/null
else
    echo 'Cloning from projectfluent/fluent...'
    git submodule update --init fluent
fi

echo 'Copying fixtures...'
exec cp fluent/test/fixtures/*.{ftl,json} syntax/test/fixtures/reference/
