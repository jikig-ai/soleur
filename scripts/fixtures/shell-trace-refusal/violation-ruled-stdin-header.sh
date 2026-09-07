#!/usr/bin/env bash
set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${SENTRY_AUTH_TOKEN:+x}" ]; then
      printf "[FATAL] refusing to trace with SENTRY_AUTH_TOKEN set (#7797)\n" >&2
      exit 78
    fi
    ;;
esac

# The credential is materialised into a 0600 file HERE...
hdr="$(mktemp)"
# ADR-129: a single owning trap, registered immediately after allocation, so the
# credential file cannot outlive this script on any exit path.
trap 'rm -f "$hdr"' EXIT INT TERM HUP
chmod 600 "$hdr"
printf 'Authorization: Bearer %s' "${SENTRY_AUTH_TOKEN}" > "$hdr"

# ...and reaches curl ONLY on stdin, far below. Nothing in or near the invocation
# names a credential, so `--header @-` is the ONLY thing that can classify this
# call as credentialed -- which is what makes the D4 mutation row discriminate.
# Missing --disable/--noproxy: Rule D must still report it.
curl -sS --header @- --url https://example.invalid/ < "$hdr" || true
