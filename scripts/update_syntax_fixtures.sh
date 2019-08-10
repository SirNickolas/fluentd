#!/usr/bin/env bash

set -euo pipefail
IFS=$'\t\n'
[ $# = 0 ] || exit 2
cd -- "$(dirname -- "$0")"/..

if [ -n "$(find fluent/ -maxdepth 0 -empty)" ]; then
    echo 'Cloning from projectfluent/fluent...'
    git submodule update --init fluent
else
    echo 'Pulling from projectfluent/fluent...'
    cd fluent
    git checkout -q master
    git pull
    cd - >/dev/null
fi

echo 'Copying fixtures...'
exec cp fluent/test/fixtures/*.{ftl,json} syntax/test/fixtures/reference/
