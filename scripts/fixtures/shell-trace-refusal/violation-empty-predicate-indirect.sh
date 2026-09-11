#!/usr/bin/env bash
# A file whose only literal credential name was deleted in the same edit that emptied the
# predicate: the referenced set is EMPTY, so a check placed after the `not referenced`
# return never sees `[ -n "" ]`. In scope via the indirect read. Must be REPORTED (#7946 Guard 2).
set -uo pipefail
case "$-" in
  *x*)
    if [ -n "" ]; then
      printf '[FATAL] refusing to trace with the credential set (#7797)\n' >&2
      exit 78
    fi
    ;;
esac

hdr="$(doppler secrets get SOME_NAME -p soleur -c prd --plain)"
curl --disable --noproxy '*' -sS -H "Authorization: Bearer ${hdr}" https://example.invalid/ || true
