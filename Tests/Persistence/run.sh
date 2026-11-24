#!/bin/sh
set -eu

fixture=$(mktemp -d "${TMPDIR:-/tmp}/folio-persistence.XXXXXXXX")
suite="local.folio.test.${fixture##*/}"
cleanup() {
    defaults delete "$suite" >/dev/null 2>&1 || true
    rm -f "$fixture/Reading.pdf" "$fixture/Renamed.pdf"
    rmdir "$fixture"
}
trap cleanup EXIT
"$1" write "$fixture" "$suite"
"$1" read "$fixture" "$suite"
