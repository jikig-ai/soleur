#!/usr/bin/env bash
# cf-token-scope — verify a Cloudflare API token's retained scope after a widen,
# and (with --target-entrypoint) confirm a newly-added scope is live.
#
# Deterministic, read-only probe. The widen itself is driven by Playwright MCP
# per the skill (SKILL.md) — this script never touches the browser and never
# mutates anything (no Doppler write, no infra apply).
#
# It runs the selected profile's retained-scope probe set — the ADR-130 set
# against CF_API_TOKEN_RULESETS by default, the CF_API_TOKEN ledger + LB
# readiness set with `--profile default-token` —
# and is fail-closed in three layers (per learning
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

# (#7797) Refuse to run under shell tracing. UNCONDITIONAL — deliberately NOT
# gated on a non-emptiness test of the credential variable, because
# CF_API_TOKEN_RULESETS is acquired by `doppler secrets get` BELOW this point, so a
# conditional arm would test an empty variable at guard time, open, and then trace
# the acquisition itself.
#
# STREAM CONTRACT: this script's stdout is a DATA channel — SKILL.md's probe-set
# contract documents `PASS: …` verdict lines a consumer reads. So the refusal is
# emitted as a `FAIL:` verdict in this module's own vocabulary: it cannot be
# mistaken for a PASS row, which a bare `[FATAL] …` line could be if the consumer
# only greps for verdicts. Stdout, not stderr, because agent runtimes surface
# stdout and swallow stderr (constitution.md > Code Style).
case "$-" in
  *x*)
    printf 'FAIL: refusing to run under xtrace — this script handles a live credential and -x would print it (see #7797). No probe was issued.\n'
    exit 78
    ;;
esac

# (#7873) `--disable` closes ~/.curlrc and `--noproxy '*'` closes the proxy vars,
# but neither touches the env that subverts TLS ITSELF. SSLKEYLOGFILE writes the
# session keys and the CA vars substitute the trust store, so a CURL_CA_BUNDLE
# MITM of the Cloudflare token works with every other guard fully intact.
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME \
      HOSTALIASES LOCALDOMAIN RES_OPTIONS

DOPPLER_PROJECT="soleur"
DOPPLER_CONFIG="prd_terraform"
ZONE_SECRET="CF_ZONE_ID"
ACCT_SECRET="CF_ACCOUNT_ID"
API="https://api.cloudflare.com/client/v4"

# Profile table (the ONLY token binding; plan 2026-10-28, rulings R1/R2/D1).
# rulesets = the ADR-130 retained-scope set against CF_API_TOKEN_RULESETS — the
# default, exactly today's behavior. default-token = the production default
# CF_API_TOKEN (the `cloudflare` provider alias) probed over its ledgered
# abilities plus two Load-Balancer readiness rows, so a scope widen of THAT
# token gets a deterministic retained-scope re-check too (the ruling's binding
# precondition). Profiles only — a raw --token-var knob would run one profile's
# URLs against another token's capabilities and is refused by design (SKILL.md).
PROFILES=(rulesets default-token)
PROFILE="rulesets"

profile_token_secret() {
  case "$1" in
    rulesets)      printf '%s' "CF_API_TOKEN_RULESETS" ;;
    default-token) printf '%s' "CF_API_TOKEN" ;;
    *)             printf '' ;;
  esac
}

# default-token probe rows: class|label|url-template|want_type|scheme.
# The $ZONE/$ACCT placeholders are printed VERBATIM by --dry-run and substituted
# after secret acquisition on the run path — print/run parity from ONE table
# (Guard 1 assembly). class=target rows are the two LB readiness probes (one
# per granted permission surface of the ruling; GETs attest the read half).
# Every row is trust404=0: the 403-on-missing verification stays exclusive to
# http_config_settings (ADR-130 #6746); LB endpoints fail closed on 404.
DT_ROWS=(
  "retained|accounts/<acct>/cfd_tunnel|$API/accounts/\$ACCT/cfd_tunnel?per_page=1|array|account"
  "retained|accounts/<acct>/access/apps|$API/accounts/\$ACCT/access/apps?per_page=1|array|account"
  "retained|zones/<zone>/dns_records|$API/zones/\$ZONE/dns_records?per_page=1|array|zone"
  "retained|accounts/<acct>/notification_policies|$API/accounts/\$ACCT/notification_policies?per_page=1|array|account"
  "target|accounts/<acct>/lb/pools|$API/accounts/\$ACCT/load_balancers/pools?per_page=1|array|account"
  "target|zones/<zone>/load_balancers|$API/zones/\$ZONE/load_balancers?per_page=1|array|zone"
)

LB_EXPECT=0
LB_OK=0
LB_NOTED=0
LB_MISSING=0
LB_TOTAL=0

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
  cf-token-scope.sh [--profile <rulesets|default-token>] [--target-entrypoint <phase>] [--expect-lb-scopes] [--dry-run]

Runs a retained-scope probe set for a NAMED PROFILE (read-only). Profiles only —
no raw token-var knob. The widen itself is driven via Playwright MCP — see SKILL.md.

  profiles:
    rulesets       (default) ADR-130 retained-scope set against CF_API_TOKEN_RULESETS
    default-token  CF_API_TOKEN ledger abilities (Tunnel, Access, DNS, Notifications)
                   + two Load-Balancer readiness rows (the #11181 widen precondition
                   and post-check)

Flags:
  --target-entrypoint <phase>  Also probe <phase> and assert the target scope is
                               present (rulesets profile; use after a widen; confirm
                               the 403->present transition against your baseline).
  --expect-lb-scopes           Assert mode (default-token profile): LB rows must be
                               authorized, else exit 3. Without it a baseline run
                               reports 403 LB rows as not-yet-widened, exit-neutral.
  --dry-run                    Print the selected profile's probe commands (token
                               unexpanded) and run nothing.
  -h, --help                   Show this help.

Exit codes:
  0  every retained scope authorized (and, per profile: the rulesets target if
     given; the default-token LB rows authorized, or 403-noted in baseline mode)
  2  usage error (including profile/flag mismatch), missing prerequisite binary,
     or absent Doppler secret
  3  probe failed — a scope was dropped, degraded, or denied (assert mode: an LB
     row still 403 or anomalous)
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
    --profile)
      if [[ -z "${2:-}" ]]; then
        echo "cf-token-scope: --profile requires a profile name" >&2
        exit 2
      fi
      known=0
      for p in "${PROFILES[@]}"; do
        [[ "$p" == "$2" ]] && known=1
      done
      if [[ "$known" == "0" ]]; then
        echo "cf-token-scope: unknown profile: $2" >&2
        usage >&2
        exit 2
      fi
      PROFILE="$2"; shift 2 ;;
    --expect-lb-scopes) LB_EXPECT=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "cf-token-scope: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# Cross-validation BEFORE any secret read or recipe print (Guard 1 assembly:
# usage errors never print recipes for a mispaired run and never cost a Doppler
# access; plan addendum 6 mirrors the existing arm shapes).
if [[ "$PROFILE" == "rulesets" && "$LB_EXPECT" == "1" ]]; then
  echo "cf-token-scope: --expect-lb-scopes is a default-token profile flag" >&2
  exit 2
fi
if [[ "$PROFILE" == "default-token" && -n "$TARGET" ]]; then
  echo "cf-token-scope: --target-entrypoint is a rulesets profile flag" >&2
  exit 2
fi

TOKEN_SECRET="$(profile_token_secret "$PROFILE")"
if [[ -z "$TOKEN_SECRET" ]]; then
  echo "cf-token-scope: profile '$PROFILE' resolves no token secret" >&2
  exit 2
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf '%s\n' "# dry-run — would read the token read-only and probe (nothing executed):"
  printf '%s\n' "TOK=\$(doppler secrets get $TOKEN_SECRET -p $DOPPLER_PROJECT -c $DOPPLER_CONFIG --plain)"
  printf '%s\n' "ZONE=\$(doppler secrets get $ZONE_SECRET -p $DOPPLER_PROJECT -c $DOPPLER_CONFIG --plain)"
  printf '%s\n' "ACCT=\$(doppler secrets get $ACCT_SECRET -p $DOPPLER_PROJECT -c $DOPPLER_CONFIG --plain)"
  # The token is passed from a private fd (never argv) — mirror that here so a
  # copy-pasted recipe does not leak the token to ps / /proc (security #6892).
  # The recipes also carry `--disable` literally first (it aborts ~/.curlrc
  # parsing, and later is too late) and `--noproxy '*'`, so a copy-pasted probe
  # teaches the confined form rather than the one this change removes (#7873).
  if [[ "$PROFILE" == "default-token" ]]; then
    for row in "${DT_ROWS[@]}"; do
      # shellcheck disable=SC2034  # class/want/scheme consumed on the run path of the SAME table
      IFS='|' read -r r_class r_label r_url r_want r_scheme <<<"$row"
      printf '%s\n' "curl --disable --noproxy '*' -sS --max-time 15 -H @<(printf 'Authorization: Bearer %s' \"\$TOK\") $r_url"
    done
    exit 0
  fi
  for p in "${ZONE_PHASES[@]}" ${TARGET:+"$TARGET"}; do
    printf '%s\n' "curl --disable --noproxy '*' -sS --max-time 15 -H @<(printf 'Authorization: Bearer %s' \"\$TOK\") $API/zones/\$ZONE/rulesets/phases/$p/entrypoint"
  done
  printf '%s\n' "curl --disable --noproxy '*' -sS --max-time 15 -H @<(printf 'Authorization: Bearer %s' \"\$TOK\") $API/accounts/\$ACCT/rulesets"
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

# Body-shape layer: a 200 is authorized ONLY with success==true AND .result of the
# type the endpoint's scheme returns — a zone .../entrypoint returns a single
# ruleset OBJECT; the account /rulesets list returns an ARRAY. A degraded 200
# ({"success":false,...} or {"success":true,"result":null}) fails either way (null
# is neither object nor array). $4 is the expected type (object|array); when it is
# omitted it derives from $2's scheme, so the rulesets call sites keep their exact
# today's semantics (plan addendum 10: want_type is an ADDED parameter, never a
# scheme replacement). CODE/BODY are published for classify_target (addendum 5);
# verdict semantics stay byte-identical.
authorized_body() {
  printf '%s' "$1" | jq -e --arg t "$2" '.success == true and (.result | type == $t)' >/dev/null 2>&1
}

ZONE_CONTROL_OK=0

# check <url> <scheme:zone|account> <trust404:0|1> [want_type:object|array] — probes
# one URL, sets VERDICT + CODE + BODY, returns 0 (pass: authorized / empty-404-under
# -control-when-trusted) or 1 (fail). The Authorization header is passed from a
# private fd so the token never lands in the process argv (readable via
# ps / /proc/<pid>/cmdline).
check() {
  local url="$1" scheme="$2" trust404="${3:-0}" want_type="${4:-}" resp
  [[ -n "$want_type" ]] || { want_type="object"; [[ "$scheme" == "account" ]] && want_type="array"; }
  CODE=""; BODY=""
  resp="$(curl --disable --noproxy '*' -sS --max-time 15 -w '\n%{http_code}' \
    -H @<(printf 'Authorization: Bearer %s' "$TOK") "$url" 2>/dev/null || true)"
  if [[ "$resp" != *$'\n'* ]]; then VERDICT="empty (no response)"; return 1; fi
  CODE="${resp##*$'\n'}"
  BODY="${resp%$'\n'*}"
  if [[ ! "$CODE" =~ ^[0-9]+$ ]]; then VERDICT="empty (non-numeric status)"; return 1; fi
  if [[ "$CODE" == "200" ]]; then
    if authorized_body "$BODY" "$want_type"; then VERDICT="authorized (200)"; return 0; fi
    VERDICT="degraded (200 body not success/$want_type)"; return 1
  fi
  # A 404 is trusted as "phase exists, empty" ONLY for an entrypoint whose
  # 403-on-missing semantics are verified (trust404=1) AND under an authorized
  # zone control. Every other 404 fails closed.
  if [[ "$CODE" == "404" ]]; then
    if [[ "$scheme" == "zone" && "$ZONE_CONTROL_OK" == "1" && "$trust404" == "1" ]]; then
      VERDICT="empty (404, verified phase exists)"; return 0
    fi
    VERDICT="denied (404, unverified — fail-closed)"; return 1
  fi
  VERDICT="denied ($CODE)"; return 1
}

report() { printf '  %-42s %s\n' "$1" "$2"; }

# classify_target <label> — the ONLY neutrality mint site (plan Guard 2 assembly).
# Called for default-token target rows only, after check() published
# VERDICT/CODE/BODY and the caller captured its status into CHECK_RC. Neutrality
# is a clean 403 in BASELINE mode only (addendum 2): degraded/wrong-shape/404/5xx
# never read as absent-scope, and LB_MISSING counts 403 only, so the still-absent
# wording is never asserted for a cause the probe did not establish. The function
# ends with an explicit return 0 (addendum 4): a trailing false [[ ]] test would
# otherwise abort the run mid-ledger under set -e. Retained-class rows never
# consult this — a retained 403 stays denied (403) + FAILED, whatever the profile.
classify_target() {
  local label="$1"
  if [[ "$CHECK_RC" == "0" ]]; then
    report "$label" "$VERDICT"; LB_OK=$((LB_OK + 1)); return 0
  fi
  if [[ "$CODE" == "403" && "$LB_EXPECT" == "0" ]]; then
    local err
    err="$(printf '%s' "$BODY" | jq -r '.errors[0].code // empty' 2>/dev/null || true)"
    report "$label" "not-yet-widened (403${err:+, err $err})"
    LB_NOTED=1
    return 0
  fi
  FAILED=1
  report "$label" "$VERDICT"
  if [[ "$LB_EXPECT" == "1" && "$CODE" == "403" ]]; then LB_MISSING=$((LB_MISSING + 1)); fi
  return 0
}

FAILED=0

echo "cf-token-scope: probing $TOKEN_SECRET retained scope (read-only)"

if [[ "$PROFILE" == "rulesets" ]]; then

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
# This rulesets path keeps its own handling; it never consults classify_target
# (plan addendum 8 — the target-class vocabulary is default-token-local).
TARGET_PRESENT=0
if [[ -n "$TARGET" ]]; then
  if check "$API/zones/$ZONE/rulesets/phases/$TARGET/entrypoint" zone "$(trust404_for "$TARGET")"; then
    TARGET_PRESENT=1
  else
    FAILED=1
  fi
  report "target: $TARGET" "$VERDICT"
fi

else

# default-token profile: retained ledger rows, then the two LB readiness rows —
# iterated from DT_ROWS, the SAME table --dry-run printed (print/run parity).
for row in "${DT_ROWS[@]}"; do
  IFS='|' read -r r_class r_label r_url r_want r_scheme <<<"$row"
  url="${r_url//\$ZONE/$ZONE}"
  url="${r_url//\$ACCT/$ACCT}"
  CHECK_RC=0
  check "$url" "$r_scheme" 0 "$r_want" || CHECK_RC=1
  if [[ "$r_class" == "retained" ]]; then
    [[ "$CHECK_RC" == "0" ]] || FAILED=1
    report "$r_label" "$VERDICT"
  else
    LB_TOTAL=$((LB_TOTAL + 1))
    classify_target "$r_label"
  fi
done

fi

echo
if [[ "$FAILED" -eq 0 ]]; then
  echo "PASS: no scope dropped"
  if [[ "$PROFILE" == "default-token" ]]; then
    # Assert mode green compares against the profile's OWN target-row count
    # (parameterized, never a hardcoded 2 — addendum 3; aggregate-floor rule D11).
    if [[ "$LB_EXPECT" == "1" && "$LB_TOTAL" -gt 0 && "$LB_OK" -eq "$LB_TOTAL" ]]; then
      echo "PASS: LB scopes present — confirm the 403->present transition against your pre-widen baseline"
    elif [[ "$LB_EXPECT" == "0" && "$LB_NOTED" == "1" ]]; then
      echo "NOTE: LB scope not-yet-widened — expected BEFORE the #11181 widen; re-run with --expect-lb-scopes after it"
    fi
  fi
  # "present", not "added": a single run cannot observe the 403->authorized
  # transition — the operator confirms that against the pre-widen baseline.
  [[ -n "$TARGET" && "$TARGET_PRESENT" == "1" ]] && \
    echo "PASS: target scope present ($TARGET) — confirm the 403->present transition against your pre-widen baseline"
  exit 0
fi

# The zone-control diagnostic names a probe the default-token profile never
# issues — gated to rulesets (addendum 9, pinned by the D-block lacks).
if [[ "$PROFILE" == "rulesets" && "$ZONE_CONTROL_OK" != "1" ]]; then
  echo "FAIL: zone control ($ZONE_CONTROL) is not authorized — the token is likely bad or missing its base scope, not a single dropped scope." >&2
fi
# The assert-mode blocking verdict rides STDOUT — the documented data channel
# (#7797 rationale; addendum 1). Only minted for a real 403 (addendum 2): a
# degraded/wrong-shape target row says so on its own row and never here.
if [[ "$PROFILE" == "default-token" && "$LB_EXPECT" == "1" && "$LB_MISSING" -gt 0 ]]; then
  echo "FAIL: LB scope still absent — the widen was not applied to CF_API_TOKEN"
fi
echo "FAIL: retained-scope probe failed — inspect the denied/degraded entrypoints above." >&2
exit 3
