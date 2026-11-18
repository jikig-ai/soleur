#!/usr/bin/env bash
# Fail-closed live preflight for every Inngest host boot that carries the public sdk_url (#12742 item 1; CTO rulings 4, 6
# and 10, 2026-11-17). It replaced the #10538 typed confirm token. Two jobs in .github/workflows/apply-web-platform-infra.yml
# call it as the step immediately after `Load infra credentials (tiered)` and before any terraform step:
#   inngest_host_replace (replace) and inngest_host (birth).
# Both boot hcloud_server.inngest from user_data whose --sdk-url is https://app.soleur.ai/api/inngest. That poll is only
# TLS end to end while Cloudflare reaches the origin in `strict` mode for app.soleur.ai, and the 2026-11-02 void terms
# forbid the public sdk_url while that hop is `flexible`. So the boot must not run unless a LIVE read says strict.
#
# The read is the read-only wrapper plugins/soleur/scripts/cloudflare-readonly.sh config-entrypoint, exec'd directly under
# `doppler run -p soleur -c prd_terraform` (the wrapper refuses to be wrapped in a shell). This script judges the wrapper's
# per-rule projection, never the wrapper's own dated-snapshot Records verdict, so an added rule re-keys the answer.
# PASS only when ALL hold:
#   - the wrapper's first line is `cloudflare-readonly: config-entrypoint ok`, followed by exactly one JSON line;
#   - the projection has the pinned shape (subcommand config-entrypoint, rules[] of {enabled bool, ssl null|string,
#     mentions_app_host bool});
#   - at least one ENABLED rule mentions app.soleur.ai with a non-null ssl, and the LAST such rule is ssl=strict;
#   - no ENABLED rule positioned after it carries ssl in {off, flexible, other} (CTO ruling 4: mentions_app_host is a
#     literal-substring figure, so a wildcard or `true` expression appended after the strict rule would override it for
#     app.soleur.ai undetected; `other` is an unrecognised mode and fails closed the same way).
# Every refusal prints one ::error:: line with a distinct bracketed tag and never a token, a rule ref, an id or a body.
#
# Usage: inngest-public-sdk-url-preflight.sh                    live read (needs DOPPLER_TOKEN; CI only)
#        inngest-public-sdk-url-preflight.sh --from-file <path> judge a captured wrapper output (test seam)
# Exit:  0 pass; 1 refused; 64 usage.
set -euo pipefail

refuse() { # $1 = tag, $2 = fixed message (never a value)
  printf '::error::[%s] public sdk_url boot refused (#12742): %s\n' "$1" "$2"
  exit 1
}

case "$-" in *x*) refuse xtrace "refusing to run under shell tracing (a live credential is in scope)" ;; esac

MODE="live"
INPUT=""
if [[ $# -eq 0 ]]; then
  :
elif [[ $# -eq 2 && "$1" == "--from-file" && -n "$2" ]]; then
  MODE="from-file"
  INPUT="$2"
else
  echo "::error::inngest-public-sdk-url-preflight.sh: usage: $0 [--from-file <path>]"
  exit 64
fi

command -v jq >/dev/null 2>&1 || refuse no-tool "jq is not installed"

if [[ "$MODE" == "from-file" ]]; then
  [[ -f "$INPUT" && -r "$INPUT" ]] || refuse no-input "the --from-file path is not a readable file"
  OUT="$(cat -- "$INPUT")"
  RC=0
else
  [[ -n "${DOPPLER_TOKEN:-}" ]] || refuse no-token "DOPPLER_TOKEN is empty, so the live Cloudflare read cannot run"
  command -v doppler >/dev/null 2>&1 || refuse no-tool "the doppler CLI is not installed"
  REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  WRAPPER="$REPO/plugins/soleur/scripts/cloudflare-readonly.sh"
  [[ -f "$WRAPPER" ]] || refuse no-wrapper "plugins/soleur/scripts/cloudflare-readonly.sh is missing from the checkout"
  # The wrapper's stderr carries only its own fixed, value-free diagnostics (its output contract), so it is not captured.
  RC=0
  OUT="$(timeout 90 doppler run -p soleur -c prd_terraform -- "$WRAPPER" config-entrypoint)" || RC=$?
fi

FIRST="${OUT%%$'\n'*}"
UNVERIFIED_RE='^cloudflare-readonly: config-entrypoint unverified - [a-z0-9 ()._:-]{1,80}$'
if [[ "$FIRST" =~ $UNVERIFIED_RE ]]; then
  # Value-free by the wrapper's contract and regex-checked here, so the reason may be printed.
  refuse wrapper-unverified "the live read did not verify (${FIRST#cloudflare-readonly: config-entrypoint unverified - })"
fi
[[ "$RC" -eq 0 ]] || refuse wrapper-rc "the Cloudflare read exited $RC without a verdict line"
[[ "$FIRST" == "cloudflare-readonly: config-entrypoint ok" ]] || refuse malformed "the read's first line is not the config-entrypoint ok line"

LINES="$(printf '%s\n' "$OUT" | grep -c '' || true)"
[[ "$LINES" == 2 ]] || refuse malformed "expected exactly one projection line after the ok line"
PROJ="${OUT#*$'\n'}"

JRC=0
VERDICT="$(jq -r '
  def shape_ok:
    type == "object" and .subcommand == "config-entrypoint" and (.rules | type) == "array"
    and all(.rules[]; type == "object" and (.enabled | type) == "boolean"
      and ((.ssl == null) or (.ssl | type) == "string") and (.mentions_app_host | type) == "boolean");
  if shape_ok | not then "shape"
  else
    [.rules | to_entries[] | select(.value.enabled)] as $en
    | [$en[] | select(.value.mentions_app_host and .value.ssl != null)] as $app
    | if ($app | length) == 0 then
        (if any(.rules[]; .mentions_app_host and .ssl != null and (.enabled | not)) then "all-disabled" else "no-match" end)
      elif $app[-1].value.ssl != "strict" then "last-not-strict"
      elif any($en[]; .key > $app[-1].key and (.value.ssl | IN("off", "flexible", "other"))) then "trailing-weak"
      else "pass \(.rules | length)"
      end
  end' <<<"$PROJ" 2>/dev/null)" || JRC=$?
[[ "$JRC" -eq 0 && -n "$VERDICT" ]] || refuse malformed "the projection line is not parseable JSON"

case "$VERDICT" in
  shape) refuse shape "the projection does not have the pinned config-entrypoint rule shape" ;;
  no-match) refuse no-match "no enabled config rule with an ssl setting mentions app.soleur.ai" ;;
  all-disabled) refuse all-disabled "every config rule with an ssl setting for app.soleur.ai is disabled" ;;
  last-not-strict) refuse last-not-strict "the last enabled app.soleur.ai ssl rule is not strict (Cloudflare to origin is not strict TLS)" ;;
  trailing-weak) refuse trailing-weak "an enabled rule after the strict app.soleur.ai rule sets ssl off, flexible or an unknown mode" ;;
  "pass "[0-9]*)
    echo "preflight passed: the last enabled app.soleur.ai ssl rule is strict and no weaker rule follows it (rules=${VERDICT#pass })" ;;
  *) refuse shape "unexpected verdict from the projection judge" ;;
esac
