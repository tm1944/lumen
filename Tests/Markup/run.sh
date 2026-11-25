#!/bin/sh
set -eu

fixture=$(mktemp -d "${TMPDIR:-/tmp}/lumen-markup.XXXXXXXX")
suite="local.lumen.test.${fixture##*/}"
cleanup() {
    defaults delete "$suite" >/dev/null 2>&1 || true
    rm -f "$fixture/plain.pdf" "$fixture/annotated.pdf" "$fixture/appearance.pdf"
    rmdir "$fixture"
}
trap cleanup EXIT
for kind in plain annotated; do
    "$1" write "$fixture/$kind.pdf" "$kind" "$suite"
    "$1" read "$fixture/$kind.pdf" "$kind" "$suite"
done
"$1" failures "$fixture/annotated.pdf" annotated "$suite"
"$1" appearance "$fixture/appearance.pdf" plain "$suite"
"$1" reopen-dark "$fixture/appearance.pdf" plain "$suite"
"$1" warmth "$fixture/appearance.pdf" plain "$suite"
"$1" reopen-warm "$fixture/appearance.pdf" plain "$suite"
for appearance in original dark; do
    "$1" sunset "$fixture/appearance.pdf" "$appearance" "$suite"
    "$1" reopen-sunset "$fixture/appearance.pdf" "$appearance" "$suite"
done
