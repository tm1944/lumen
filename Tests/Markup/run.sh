#!/bin/sh
set -eu

fixture=$(mktemp -d "${TMPDIR:-/tmp}/lumen-markup.XXXXXXXX")
suite="local.lumen.test.${fixture##*/}"
cleanup() {
    defaults delete "$suite" >/dev/null 2>&1 || true
    rm -f "$fixture/plain.pdf" "$fixture/annotated.pdf"
    rmdir "$fixture"
}
trap cleanup EXIT
for kind in plain annotated; do
    "$1" write "$fixture/$kind.pdf" "$kind" "$suite"
    "$1" read "$fixture/$kind.pdf" "$kind" "$suite"
done
"$1" failures "$fixture/annotated.pdf" annotated "$suite"
