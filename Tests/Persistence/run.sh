#!/bin/sh
set -eu

# Folio stored its library and per-book state in this preferences domain.
plist=Lumen.app/Contents/Info.plist
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" = local.folio.reader
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$plist")" = Lumen
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")" = Lumen
test -x Lumen.app/Contents/MacOS/Lumen

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
