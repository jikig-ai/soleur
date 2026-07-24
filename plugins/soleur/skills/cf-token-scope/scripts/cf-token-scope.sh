#!/usr/bin/env bash
# cf-token-scope — verify a Cloudflare API token's retained scope after a widen,
# and (with --target-entrypoint) confirm a newly-added scope is live.
#
# Deterministic, read-only probe. The widen itself is driven by Playwright MCP
# per the skill (SKILL.md) — this script never touches the browser and never
# mutates anything (no Doppler write, no infra apply).
#
# It runs the ADR-130 retained-scope probe set against CF_API_TOKEN_RULESETS and
# is fail-closed in three layers (per learning
# 2026-07-23-live-api-fail-closed-guard-counts-degraded-200-as-empty-and-control-probe-must-cover-every-scheme):
#   1. status      — 403 / 000 / 5xx / empty / non-numeric = FAIL.
#   2. body-shape  — a 200 passes ONLY when the JSON body has success==true AND
#                    .result is an array. A degraded 200 (e.g.
#                    {"success":false,"result":null}) is a FAIL. Never key on
#                    `.result | length` — jq reads null as 0 and would pass.
#   3. per-scheme control — the four probes span two schemes: three zone phases
#                    and one account list. The account list is itself the
#                    account-scheme control (must be an authorized 200; an
#                    account 404 = FAIL). A zone 404 (ADR-130-endorsed "phase
#                    exists, empty") is trusted only when a known-granted zone
#                    control (http_request_dynamic_redirect) is authorized.
#
# The canonical four-probe set is a CANARY for the whole-list REPLACE failure
# mode (a dashboard "save" that replaces rather than appends drops every scope at
# once → all four catch it). It is NOT exhaustive per-permission coverage: Zone
# WAF (firewall_custom), Transform Rules (response_headers_transform), and
# account Filter Lists are unprobed, so a surgical single-permission drop can
# pass. See SKILL.md § Sharp Edges.

set -euo pipefail

DOPPLER_PROJECT="soleur"
DOPPLER_CONFIG="prd_terraform"
TOKEN_SECRET="CF_API_TOKEN_RULESETS"
ZONE_SECRET="CF_ZONE_ID"
ACCT_SECRET="CF_ACCOUNT_ID"
API="https://api.cloudflare.com/client/v4"

# The ADR-130 retained-scope zone phases. http_request_dynamic_redirect is the
# known-granted zone control (ADR-130 § Consequences: the 200 control probe).
ZONE_CONTROL="http_request_dynamic_redirect"
ZONE_PHASES=(http_config_settings http_request_dynamic_redirect http_request_cache_settings)

usage() {
  cat <<'EOF'
Usage:
  cf-token-scope.sh [--target-entrypoint <phase>] [--dry-run]

Runs the ADR-130 retained-scope probe set against CF_API_TOKEN_RULESETS
(read-only). The widen itself is driven via Playwright MCP — see SKILL.md.

Flags:
  --target-entrypoint <phase>  Also probe <phase> and additionally assert the
                               target scope is live (use after a widen to confirm
                               the new scope was added).
  --dry-run                    Print the probe commands (token unexpanded) and
                               run nothing.
  -h, --help                   Show this help.

Exit codes:
  0  every retained scope authorized (and the target, if given)
  2  missing prerequisite binary or Doppler secret
  3  probe failed — a scope was dropped, degraded, or denied
EOF
}

TARGET=""
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-entrypoint) TARGET="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "cf-token-scope: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf '%s\n' "# dry-run — would read the token read-only and probe (nothing executed):"
  printf '%s\n' "TOK=\$(doppler secrets get $TOKEN_SECRET -p $DOPPLER_PROJECT -c $DOPPLER_CONFIG --plain)"
  printf '%s\n' "ZONE=\$(doppler secrets get $ZONE_SECRET -p $DOPPLER_PROJECT -c $DOPPLER_CONFIG --plain)"
  printf '%s\n' "ACCT=\$(doppler secrets get $ACCT_SECRET -p $DOPPLER_PROJECT -c $DOPPLER_CONFIG --plain)"
  for p in "${ZONE_PHASES[@]}" ${TARGET:+"$TARGET"}; do
    printf '%s\n' "curl -sS --max-time 15 -H \"Authorization: Bearer \$TOK\" $API/zones/\$ZONE/rulesets/phases/$p/entrypoint"
  done
  printf '%s\n' "curl -sS --max-time 15 -H \"Authorization: Bearer \$TOK\" $API/accounts/\$ACCT/rulesets"
  exit 0
fi

# Prerequisites.
for bin in curl doppler jq; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "cf-token-scope: missing required binary: $bin" >&2
    exit 2
  }
done

get_secret() {
  local name="$1" val
  val="$(doppler secrets get "$name" -p "$DOPPLER_PROJECT" -c "$DOPPLER_CONFIG" --plain 2>/dev/null || true)"
  if [[ -z "$val" ]]; then
    echo "cf-token-scope: $name is empty or absent in Doppler $DOPPLER_PROJECT/$DOPPLER_CONFIG" >&2
    exit 2
  fi
  printf '%s' "$val"
}

TOK="$(get_secret "$TOKEN_SECRET")"
ZONE="$(get_secret "$ZONE_SECRET")"
ACCT="$(get_secret "$ACCT_SECRET")"
cleanup() { unset TOK ZONE ACCT; }
trap cleanup EXIT

# Body-shape layer: a 200 is authorized ONLY with success==true AND an array .result.
authorized_body() { printf '%s' "$1" | jq -e '.success == true and (.result | type == "array")' >/dev/null 2>&1; }

ZONE_CONTROL_OK=0

# check <url> <scheme:zone|account> — probes one URL, sets VERDICT, returns
# 0 (pass: authorized / empty-404-under-control) or 1 (fail).
# The Authorization header is passed from a private fd so the token never lands
# in the process argv (readable via ps / /proc/<pid>/cmdline).
check() {
  local url="$1" scheme="$2" resp code body
  resp="$(curl -sS --max-time 15 -w '\n%{http_code}' \
    -H @<(printf 'Authorization: Bearer %s' "$TOK") "$url" 2>/dev/null || true)"
  if [[ "$resp" != *$'\n'* ]]; then VERDICT="empty"; return 1; fi
  code="${resp##*$'\n'}"
  body="${resp%$'\n'*}"
  if [[ ! "$code" =~ ^[0-9]+$ ]]; then VERDICT="empty"; return 1; fi
  if [[ "$code" == "200" ]]; then
    if authorized_body "$body"; then VERDICT="authorized (200)"; return 0; fi
    VERDICT="degraded (200 body not success/array)"; return 1
  fi
  if [[ "$code" == "404" ]]; then
    if [[ "$scheme" == "zone" && "$ZONE_CONTROL_OK" == "1" ]]; then
      VERDICT="empty (404, phase exists)"; return 0
    fi
    VERDICT="denied (404)"; return 1
  fi
  VERDICT="denied ($code)"; return 1
}

report() { printf '  %-42s %s\n' "$1" "$2"; }

FAILED=0

echo "cf-token-scope: probing CF_API_TOKEN_RULESETS retained scope (read-only)"

# 1. Zone control first — every zone 404's trust depends on it.
if check "$API/zones/$ZONE/rulesets/phases/$ZONE_CONTROL/entrypoint" zone; then ZONE_CONTROL_OK=1; fi
report "$ZONE_CONTROL" "$VERDICT"
[[ "$ZONE_CONTROL_OK" == "1" ]] || FAILED=1

# 2. Remaining retained zone phases.
for p in "${ZONE_PHASES[@]}"; do
  [[ "$p" == "$ZONE_CONTROL" ]] && continue
  check "$API/zones/$ZONE/rulesets/phases/$p/entrypoint" zone || FAILED=1
  report "$p" "$VERDICT"
done

# 3. Account list — the account-scheme control (an account 404 is a FAIL).
check "$API/accounts/$ACCT/rulesets" account || FAILED=1
report "accounts/<acct>/rulesets" "$VERDICT"

# 4. Target entrypoint (the newly-widened scope), if given.
TARGET_OK=1
if [[ -n "$TARGET" ]]; then
  check "$API/zones/$ZONE/rulesets/phases/$TARGET/entrypoint" zone || { TARGET_OK=0; FAILED=1; }
  report "target: $TARGET" "$VERDICT"
fi

echo
if [[ "$FAILED" -eq 0 ]]; then
  echo "PASS: no scope dropped"
  [[ -n "$TARGET" ]] && echo "PASS: target scope added ($TARGET)"
  exit 0
fi

if [[ "$ZONE_CONTROL_OK" != "1" ]]; then
  echo "FAIL: zone control ($ZONE_CONTROL) is not authorized — the token is likely bad or missing its base scope, not a single dropped scope." >&2
fi
echo "FAIL: retained-scope probe failed — inspect the denied/degraded entrypoints above." >&2
exit 3
