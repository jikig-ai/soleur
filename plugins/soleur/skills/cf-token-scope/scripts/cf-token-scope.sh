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
#   1. status      — 403 / 000 / 5xx / empty / no-newline / non-numeric = FAIL.
#   2. body-shape  — a 200 passes ONLY when the JSON body has success==true AND
#                    .result is an array. A degraded 200 (e.g.
#                    {"success":false,...} OR {"success":true,"result":null}) is a
#                    FAIL. Never key on `.result | length` — jq reads null as 0.
#   3. per-scheme control — the probes span two schemes: four zone phases and one
#                    account list. The account list is itself the account-scheme
#                    control (must be an authorized 200; an account 404 = FAIL). A
#                    zone 404 (ADR-130's "phase exists, empty") is trusted ONLY for
#                    http_config_settings — the one phase whose 403-on-missing was
#                    empirically verified — and only under an authorized zone
#                    control (http_request_dynamic_redirect). Every other phase's
#                    404 fails closed (a dropped scope that 404s must not pass).
#
# The probe set is a CANARY for the whole-list REPLACE failure mode (a dashboard
# "save" that replaces rather than appends drops every scope at once → every probe
# catches it). It is NOT exhaustive per-permission coverage: Zone WAF
# (firewall_custom) is now probed, but Transform Rules (response_headers_transform)
# and account Filter Lists are not, so a surgical single-permission drop of those
# can pass. The probe issues GET, so it attests READ reachability, not :Edit
# retention. See SKILL.md § Sharp Edges.

set -euo pipefail

DOPPLER_PROJECT="soleur"
DOPPLER_CONFIG="prd_terraform"
TOKEN_SECRET="CF_API_TOKEN_RULESETS"
ZONE_SECRET="CF_ZONE_ID"
ACCT_SECRET="CF_ACCOUNT_ID"
API="https://api.cloudflare.com/client/v4"

# The ADR-130 retained-scope zone phases. http_request_dynamic_redirect is the
# known-granted zone control (ADR-130 § Consequences: the 200 control probe).
# http_request_firewall_custom (Zone WAF:Edit) is added to the retained set
# because it is a hijack-class scope on the same token (ADR-130 axis 1).
ZONE_CONTROL="http_request_dynamic_redirect"
ZONE_PHASES=(http_config_settings http_request_dynamic_redirect http_request_cache_settings http_request_firewall_custom)

# 403-vs-404-on-missing-scope semantics are EMPIRICALLY VERIFIED (ADR-130 probe
# #6746) for ONLY http_config_settings: a missing scope there returns 403, never
# 404, so a 404 is unambiguously "phase exists, empty" and passes. For every other
# phase that fact is UNVERIFIED, so a 404 fails closed — a dropped scope that
# returned 404 instead of 403 must never read as green (user-impact P1, #6892).
trust404_for() { [[ "$1" == "http_config_settings" ]] && echo 1 || echo 0; }

usage() {
  cat <<'EOF'
Usage:
  cf-token-scope.sh [--target-entrypoint <phase>] [--dry-run]

Runs the ADR-130 retained-scope probe set against CF_API_TOKEN_RULESETS
(read-only). The widen itself is driven via Playwright MCP — see SKILL.md.

Flags:
  --target-entrypoint <phase>  Also probe <phase> and assert the target scope is
                               present (use after a widen; confirm the
                               403->present transition against your baseline).
  --dry-run                    Print the probe commands (token unexpanded) and
                               run nothing.
  -h, --help                   Show this help.

Exit codes:
  0  every retained scope authorized (and the target, if given)
  2  usage error, missing prerequisite binary, or absent Doppler secret
  3  probe failed — a scope was dropped, degraded, or denied
EOF
}

TARGET=""
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-entrypoint)
      if [[ -z "${2:-}" ]]; then
        echo "cf-token-scope: --target-entrypoint requires a phase name" >&2
        exit 2
      fi
      TARGET="$2"; shift 2 ;;
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
  # The token is passed from a private fd (never argv) — mirror that here so a
  # copy-pasted recipe does not leak the token to ps / /proc (security #6892).
  for p in "${ZONE_PHASES[@]}" ${TARGET:+"$TARGET"}; do
    printf '%s\n' "curl -sS --max-time 15 -H @<(printf 'Authorization: Bearer %s' \"\$TOK\") $API/zones/\$ZONE/rulesets/phases/$p/entrypoint"
  done
  printf '%s\n' "curl -sS --max-time 15 -H @<(printf 'Authorization: Bearer %s' \"\$TOK\") $API/accounts/\$ACCT/rulesets"
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
# shellcheck disable=SC2317  # invoked indirectly via the EXIT trap
cleanup() { unset TOK ZONE ACCT; }
trap cleanup EXIT

# Body-shape layer: a 200 is authorized ONLY with success==true AND an array .result.
authorized_body() { printf '%s' "$1" | jq -e '.success == true and (.result | type == "array")' >/dev/null 2>&1; }

ZONE_CONTROL_OK=0

# check <url> <scheme:zone|account> <trust404:0|1> — probes one URL, sets VERDICT,
# returns 0 (pass: authorized / empty-404-under-control-when-trusted) or 1 (fail).
# The Authorization header is passed from a private fd so the token never lands
# in the process argv (readable via ps / /proc/<pid>/cmdline).
check() {
  local url="$1" scheme="$2" trust404="${3:-0}" resp code body
  resp="$(curl -sS --max-time 15 -w '\n%{http_code}' \
    -H @<(printf 'Authorization: Bearer %s' "$TOK") "$url" 2>/dev/null || true)"
  if [[ "$resp" != *$'\n'* ]]; then VERDICT="empty (no response)"; return 1; fi
  code="${resp##*$'\n'}"
  body="${resp%$'\n'*}"
  if [[ ! "$code" =~ ^[0-9]+$ ]]; then VERDICT="empty (non-numeric status)"; return 1; fi
  if [[ "$code" == "200" ]]; then
    if authorized_body "$body"; then VERDICT="authorized (200)"; return 0; fi
    VERDICT="degraded (200 body not success/array)"; return 1
  fi
  # A 404 is trusted as "phase exists, empty" ONLY for an entrypoint whose
  # 403-on-missing semantics are verified (trust404=1) AND under an authorized
  # zone control. Every other 404 fails closed.
  if [[ "$code" == "404" ]]; then
    if [[ "$scheme" == "zone" && "$ZONE_CONTROL_OK" == "1" && "$trust404" == "1" ]]; then
      VERDICT="empty (404, verified phase exists)"; return 0
    fi
    VERDICT="denied (404, unverified — fail-closed)"; return 1
  fi
  VERDICT="denied ($code)"; return 1
}

report() { printf '  %-42s %s\n' "$1" "$2"; }

FAILED=0

echo "cf-token-scope: probing CF_API_TOKEN_RULESETS retained scope (read-only)"

# 1. Zone control first — every zone 404's trust depends on it. The control must
# be an authorized 200 (trust404=0: a control that only 404s proves nothing).
if check "$API/zones/$ZONE/rulesets/phases/$ZONE_CONTROL/entrypoint" zone 0; then ZONE_CONTROL_OK=1; fi
report "$ZONE_CONTROL" "$VERDICT"
[[ "$ZONE_CONTROL_OK" == "1" ]] || FAILED=1

# 2. Remaining retained zone phases (trust404 per the verified-phase rule).
for p in "${ZONE_PHASES[@]}"; do
  [[ "$p" == "$ZONE_CONTROL" ]] && continue
  check "$API/zones/$ZONE/rulesets/phases/$p/entrypoint" zone "$(trust404_for "$p")" || FAILED=1
  report "$p" "$VERDICT"
done

# 3. Account list — the account-scheme control (an account 404 is a FAIL).
check "$API/accounts/$ACCT/rulesets" account 0 || FAILED=1
report "accounts/<acct>/rulesets" "$VERDICT"

# 4. Target entrypoint (the newly-widened scope), if given. TARGET_PRESENT gates
# the success line so it cannot print unless the target probe actually passed.
TARGET_PRESENT=0
if [[ -n "$TARGET" ]]; then
  if check "$API/zones/$ZONE/rulesets/phases/$TARGET/entrypoint" zone "$(trust404_for "$TARGET")"; then
    TARGET_PRESENT=1
  else
    FAILED=1
  fi
  report "target: $TARGET" "$VERDICT"
fi

echo
if [[ "$FAILED" -eq 0 ]]; then
  echo "PASS: no scope dropped"
  # "present", not "added": a single run cannot observe the 403->authorized
  # transition — the operator confirms that against the pre-widen baseline.
  [[ -n "$TARGET" && "$TARGET_PRESENT" == "1" ]] && \
    echo "PASS: target scope present ($TARGET) — confirm the 403->present transition against your pre-widen baseline"
  exit 0
fi

if [[ "$ZONE_CONTROL_OK" != "1" ]]; then
  echo "FAIL: zone control ($ZONE_CONTROL) is not authorized — the token is likely bad or missing its base scope, not a single dropped scope." >&2
fi
echo "FAIL: retained-scope probe failed — inspect the denied/degraded entrypoints above." >&2
exit 3
