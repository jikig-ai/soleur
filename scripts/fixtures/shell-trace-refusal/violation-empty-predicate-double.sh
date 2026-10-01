#!/usr/bin/env bash
# A single-credential file whose only `${VAR:+x}` limb was deleted during a rename,
# leaving `[ -n "" ]` -- a non-emptiness test of the empty string, which can never be
# true. The refusal reads as protection and never fires. Must be REPORTED (#7946 Guard 2).
set -uo pipefail
case "$-" in
  *x*)
    if [ -n "" ]; then
      printf '[FATAL] refusing to trace with the token set (#7797)\n' >&2
      exit 78
    fi
    ;;
esac

curl --disable --noproxy '*' -sS -H "Authorization: Bearer ${SENTRY_ACTIONS_RO_TOKEN}" https://example.invalid/ || true
