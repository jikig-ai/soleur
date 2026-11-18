#!/usr/bin/env bash
# Fail-closed live preflight for every Inngest host boot that carries the public sdk_url (#12742 item 1; CTO rulings 4, 6
# and 10, 2026-11-17, and review-round rulings R1, R2, R3, 2026-11-18). It replaced the #10538 typed confirm token. Two jobs in
# .github/workflows/apply-web-platform-infra.yml call it as the step immediately after `Load infra credentials (tiered)` and
# before any terraform step: inngest_host_replace (replace; its step first checks the REPLACE-INNGEST-HOST typo-guard, R5) and
# inngest_host (birth).
# Both boot hcloud_server.inngest from user_data whose --sdk-url is https://app.soleur.ai/api/inngest. That poll is only
# TLS end to end while Cloudflare reaches the origin in `strict` mode for app.soleur.ai, and the 2026-11-02 void terms
# forbid the public sdk_url while that hop is `flexible`. So the boot must not run unless a LIVE read says strict.
#
# The read is the read-only wrapper plugins/soleur/scripts/cloudflare-readonly.sh config-entrypoint, exec'd directly as
#   timeout 90 doppler run --preserve-env --only-secrets CF_ZONE_ID,CF_API_TOKEN_RULESETS,DOPPLER_PROJECT,DOPPLER_CONFIG \
#     -p soleur -c prd_terraform -- <wrapper> config-entrypoint
# The wrapper must not be wrapped in a shell (its header forbids it; it has no runtime check, so this line is the guard).
# --only-secrets keeps any other prd_terraform key (a planted BASH_ENV, LD_PRELOAD, ...) out of the wrapper's own bash;
# --preserve-env keeps the Tier-B loader's exports ahead of a same-named Doppler value (ADR-241 D6).
# This script judges the wrapper's per-rule projection, never the wrapper's own dated-snapshot Records verdict, so an
# added rule re-keys the answer. Cloudflare config rules are non-terminating and the LAST match wins. PASS only when ALL hold:
#   - the wrapper's first line is `cloudflare-readonly: config-entrypoint ok`, followed by exactly one JSON value on one line;
#   - the projection has the pinned shape (subcommand config-entrypoint, a string id, rules[] of {enabled bool,
#     ssl null|string, mentions_app_host bool, host_literal_only bool});
#   - the projection id is RULESET_ID below, the entrypoint ruleset that apps/web-platform/infra/seo-config-rules.tf imports
#     (a forged zone or token cannot return it) [ruleset-id];
#   - let L be the LAST enabled rule that mentions app.soleur.ai with a non-null ssl: L exists [no-match / all-disabled],
#     L.ssl is strict [last-not-strict], and L is host_literal_only, i.e. its whole expression is exactly
#     `(http.host eq "<h>")` or `(http.host in {"<h1>" ...})`, so it covers every request to the host (a negated or
#     path-narrowed rule does not) [strict-not-host-wide];
#   - every ENABLED rule after L with a non-null ssl is host_literal_only AND does not mention app.soleur.ai, so it cannot
#     match app.soleur.ai and override L (mentions_app_host alone is a literal-substring figure: a wildcard or `true`
#     expression defeats it) [trailing-weak]. Rules before L are overridden by L for every app.soleur.ai request.
# RESIDUALS (not checked here): legacy Page Rules are not read; Cloudflare docs state "Rules take precedence over Page Rules",
# so an SSL page rule cannot override L (documentation, not a live read). The zone ssl setting is not read; it is what L's
# set_config overrides for app.soleur.ai. host_literal_only matches the expression text byte for byte, so if Cloudflare
# normalises the stored text (spacing, quoting) the shape check fails closed ([strict-not-host-wide]), never open.
# Every refusal prints one ::error:: line with a distinct bracketed tag and never a token, a rule ref, an id or a body.
#
# Usage: inngest-public-sdk-url-preflight.sh                    live read (needs DOPPLER_TOKEN; CI only)
#        inngest-public-sdk-url-preflight.sh --from-file <path> judge a captured wrapper output (test seam)
# Exit:  0 pass; 1 refused; 64 usage.
set -euo pipefail
export LC_ALL=C

# The config-settings entrypoint ruleset id from the import block in apps/web-platform/infra/seo-config-rules.tf (B10 pins
# the two equal). A Cloudflare ruleset id, not a secret; it is compared, never printed.
RULESET_ID="a21ac79d368f425a95c895c43a090d57"

refuse() { # $1 = tag, $2 = fixed message (never a value)
  printf '::error::[%s] public sdk_url boot refused (#12742): %s\n' "$1" "$2"
  exit 1
}

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

# Live mode holds DOPPLER_TOKEN: refuse tracing before any line expands it.
if [[ "$MODE" == "live" ]]; then
  case "$-" in *x*) refuse xtrace "refusing to run under shell tracing (a live credential is in scope)" ;; esac
fi

[[ -x /usr/bin/jq ]] || refuse no-tool "/usr/bin/jq is not installed"

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
  OUT="$(timeout 90 doppler run --preserve-env --only-secrets CF_ZONE_ID,CF_API_TOKEN_RULESETS,DOPPLER_PROJECT,DOPPLER_CONFIG -p soleur -c prd_terraform -- "$WRAPPER" config-entrypoint)" || RC=$?
fi

FIRST="${OUT%%$'\n'*}"
UNVERIFIED_RE='^cloudflare-readonly: config-entrypoint unverified - [A-Za-z0-9 ()._:-]{1,80}$'
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
# shellcheck disable=SC2016  # $rid, $en and $app are jq variables, not shell expansions
VERDICT="$(/usr/bin/env -i /usr/bin/jq -s -r --arg rid "$RULESET_ID" '
  def shape_ok:
    type == "object" and .subcommand == "config-entrypoint" and (.id | type) == "string" and (.rules | type) == "array"
    and all(.rules[]; type == "object" and (.enabled | type) == "boolean"
      and ((.ssl == null) or (.ssl | type) == "string") and (.mentions_app_host | type) == "boolean"
      and (.host_literal_only | type) == "boolean");
  if length != 1 then "multi"
  else .[0]
  | if shape_ok | not then "shape"
    elif .id != $rid then "ruleset-id"
    else
      [.rules | to_entries[] | select(.value.enabled)] as $en
      | [$en[] | select(.value.mentions_app_host and .value.ssl != null)] as $app
      | if ($app | length) == 0 then
          (if any(.rules[]; .mentions_app_host and .ssl != null and (.enabled | not)) then "all-disabled" else "no-match" end)
        elif $app[-1].value.ssl != "strict" then "last-not-strict"
        elif ($app[-1].value.host_literal_only | not) then "strict-not-host-wide"
        elif any($en[]; .key > $app[-1].key and .value.ssl != null
            and ((.value.host_literal_only and (.value.mentions_app_host | not)) | not)) then "trailing-weak"
        else "pass \(.rules | length)"
        end
    end
  end' <<<"$PROJ" 2>/dev/null)" || JRC=$?
[[ "$JRC" -eq 0 && -n "$VERDICT" ]] || refuse malformed "the projection line is not parseable JSON"

PASS_RE='^pass [0-9]+$'
case "$VERDICT" in
  multi) refuse malformed "the projection line holds more than one JSON value" ;;
  shape) refuse shape "the projection does not have the pinned config-entrypoint rule shape" ;;
  ruleset-id) refuse ruleset-id "the projection is not the seo-config-rules.tf entrypoint ruleset (wrong zone or token)" ;;
  no-match) refuse no-match "no enabled config rule with an ssl setting mentions app.soleur.ai" ;;
  all-disabled) refuse all-disabled "every config rule with an ssl setting for app.soleur.ai is disabled" ;;
  last-not-strict) refuse last-not-strict "the last enabled app.soleur.ai ssl rule is not strict (Cloudflare to origin is not strict TLS)" ;;
  strict-not-host-wide) refuse strict-not-host-wide "the last enabled app.soleur.ai ssl rule is not exactly a host-literal expression, so it may not cover every request" ;;
  trailing-weak) refuse trailing-weak "an enabled ssl rule after the strict app.soleur.ai rule is not a host-literal rule for other hosts, so it may override it" ;;
  *)
    [[ "$VERDICT" =~ $PASS_RE ]] || refuse shape "unexpected verdict from the projection judge"
    echo "preflight passed: the last enabled app.soleur.ai ssl rule is strict and host-wide, and no later ssl rule can match the host (rules=${VERDICT#pass })" ;;
esac
