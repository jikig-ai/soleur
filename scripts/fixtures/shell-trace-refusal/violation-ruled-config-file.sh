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

# Rule D: BOTH the credential AND the destination reach curl through a --config
# file, so the invocation line names neither. This is zot-inventory.sh's shape --
# the site #7873 is about -- and without _inline_config_file the destination limb
# is structurally unable to see INGEST_URL at all.
INGEST_URL="${FIXTURE_INGEST_URL:-https://example.invalid/}"

conf="$(mktemp)"
trap 'rm -f "$conf"' EXIT INT TERM HUP
chmod 600 "$conf"
{
  printf 'url = "%s"\n' "$INGEST_URL"
  printf 'header = "Authorization: Bearer %s"\n' "${SENTRY_AUTH_TOKEN}"
} > "$conf"

curl --disable --noproxy '*' --silent --request POST --config "$conf" || true
