#!/usr/bin/env bash
# Detect Cloudflare API tokens that are DEAD or inconsistent across Doppler configs.
#
# WHY THIS EXISTS (2026-07-29 incident response)
# ----------------------------------------------
# Every `doppler_secret` that carries a Cloudflare token declares
# `lifecycle { ignore_changes = [value] }` (cf-cert-reissue-token.tf,
# tunnel.tf, zot-registry.tf). That rule is deliberate — it stops refresh-time
# churn — but it has a consequence nothing surfaces: **Terraform can never
# propagate a rotated token**. `terraform apply` reports `No changes` while the
# `prd` root config still holds the dead value, and every branch config that
# inherits from root serves it too.
#
# The failure is silent and delayed. Rotating a token in the Cloudflare
# dashboard and updating `prd_terraform` looks completely successful — the
# operator verifies the one config they edited, gets a green result, and moves
# on. The stale copies surface days later as an unrelated-looking 403 in cron,
# GHCR, or the LUKS workflow, with nothing pointing back at the rotation.
#
# Observed three times in a single session, each time only because the fan-out
# was checked by hand:
#   - REGISTRY_PUSH_ACCESS_TOKEN_*  — `prd` root stale after a Terraform replace
#   - CF_API_TOKEN_DNS_EDIT         — 5 of 7 configs stale after a dashboard roll
#   - CF_API_TOKEN_PURGE            — 6 of 7 configs stale after a dashboard roll
#
# This script makes that class fail loudly. It does NOT change the lifecycle
# rules: removing `ignore_changes` would trade a silent-staleness bug for a
# churn bug the comments say was hit before. Detection is the safer fix.
#
# USAGE
#   doppler run -p soleur -c prd_terraform -- bash scripts/check-cloudflare-token-drift.sh
#   bash scripts/check-cloudflare-token-drift.sh --json
#
# COVERAGE
#   CF_API_TOKEN*             Cloudflare API tokens (single value, Bearer-verified).
#   *ACCESS_TOKEN_ID/_SECRET  Cloudflare ACCESS SERVICE TOKENS (client-id/secret pair,
#                             verified against the Access-protected hostname). Added
#                             2026-07-30: this family is the FIRST case the header above
#                             cites, and the original enumeration regex could not match
#                             it, so the script reported a clean bill of health for a
#                             question it never asked.
#
# EXIT CODES
#   0  every token value resolves LIVE, and every enumerated token was verifiable
#   1  at least one DEAD token value found (rotation did not propagate), OR an Access
#      service token was enumerated that this script has no hostname mapping for and
#      therefore could not verify. Unverified never renders as LIVE.
#   2  preconditions missing (doppler CLI, curl, python3)

set -uo pipefail

PROJECT="${DOPPLER_PROJECT:-soleur}"
JSON_OUT=0
# --only <SUBSTRING> narrows the scan to keys containing SUBSTRING. It exists for the
# release preflight, which cares about exactly one credential (the registry-push Access
# token) and must not spend a full fleet-wide sweep — one curl per distinct value across
# every config — on the critical path of every release.
#
# It narrows the SCAN, never the enumeration source: keys still come from Doppler, so a
# newly-added token in the matched family is still picked up. A hardcoded key list is how
# CF_API_TOKEN_AUDIT was missed during the incident that motivated this script.
ONLY_MATCH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_OUT=1; shift ;;
    --only)
      # `shift 2` with $#==1 shifts NOTHING and returns non-zero. There is no `set -e`
      # here, so the failure is ignored and `while [[ $# -gt 0 ]]` spins forever with no
      # output — a silent hang, in a script three separate error messages tell an operator
      # to run by hand under incident pressure. Measured: still looping at 2001 iterations.
      # An empty value is rejected too: it would silently widen a scoped check back to a
      # full fleet sweep, which is the opposite of what the caller asked for.
      [[ $# -ge 2 && -n "${2:-}" ]] || { echo "ERROR: --only requires a non-empty value" >&2; exit 2; }
      ONLY_MATCH="$2"; shift 2 ;;
    *) shift ;;
  esac
done

for bin in doppler curl python3; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: $bin not on PATH" >&2; exit 2; }
done

# Enumerate configs from Doppler rather than hardcoding. A hardcoded list is
# exactly how CF_API_TOKEN_AUDIT was missed during the incident: it lived only
# in the dev* configs, which the audit sweep never looked at.
mapfile -t CONFIGS < <(doppler configs -p "$PROJECT" --json 2>/dev/null |
  python3 -c 'import json,sys; [print(c["name"]) for c in json.load(sys.stdin)]' 2>/dev/null)
if [[ ${#CONFIGS[@]} -eq 0 ]]; then
  echo "ERROR: could not enumerate Doppler configs for project '$PROJECT'" >&2
  exit 2
fi

# Enumerate token-shaped keys the same way — never a fixed list.
#
# TWO FAMILIES, because they authenticate completely differently:
#
#   CF_API_TOKEN*            — a Cloudflare API token. One value. Verified as a Bearer
#                              against /user/tokens/verify.
#   *ACCESS_TOKEN_ID/_SECRET — a Cloudflare ACCESS SERVICE TOKEN. A client-id/secret
#                              PAIR. It is not an API token and /user/tokens/verify
#                              cannot say anything about it; it is verified by presenting
#                              the pair to an Access-protected hostname.
#
# The second family was the coverage gap this script shipped with. Its own header cites
# REGISTRY_PUSH_ACCESS_TOKEN_* as the FIRST case that motivated it, and the enumeration
# regex `CF_API_TOKEN[A-Z0-9_]*` cannot match that key — the anchor is at the start, so
# no amount of trailing wildcard reaches a name that does not begin with CF_API_TOKEN.
# The script reported "0 dead" on a fleet where a REGISTRY_PUSH_ACCESS_TOKEN_* rotation
# had not propagated, which is worse than not running at all: it is a green light for a
# question it never asked.
declare -A KEYSET=()          # API tokens:            KEY -> 1
declare -A ACCESS_BASESET=()  # Access service tokens: BASE (no _ID/_SECRET) -> 1
declare -A ALL_ID_KEYS=()     # every *_ACCESS_TOKEN_ID name seen anywhere in the fleet
for cfg in "${CONFIGS[@]}"; do
  # ONE `--only-names` read per config, reused by both families. Two calls doubled the
  # Doppler request count for no benefit (measured: 26 of 53 calls on the release
  # preflight), and a second call is a second chance to silently return empty.
  #
  # The exit status is CAPTURED, not discarded. `2>/dev/null || true` on a read whose
  # emptiness decides the verdict is how a scope-denied token renders as a clean fleet.
  _names=""
  if ! _names="$(doppler secrets -p "$PROJECT" -c "$cfg" --only-names 2>/dev/null)"; then
    echo "ERROR: could not read secret names for config '$cfg' — refusing to report a verdict from a partial enumeration" >&2
    exit 2
  fi
  while read -r k; do
    [[ -z "$k" ]] && continue
    [[ -n "$ONLY_MATCH" && "$k" != *"$ONLY_MATCH"* ]] && continue
    KEYSET["$k"]=1
  done < <(printf '%s\n' "$_names" | grep -oE 'CF_API_TOKEN[A-Z0-9_]*' || true)
  # Record every key name this config carries, so the Access arm below can require that a
  # base's `_ID` half actually EXISTS somewhere in the fleet before treating it as a
  # Cloudflare Access service-token pair (see ACCESS_ID_SEEN).
  while read -r k; do
    [[ -n "$k" ]] && ALL_ID_KEYS["$k"]=1
  done < <(printf '%s\n' "$_names" | grep -oE '[A-Z0-9_]*ACCESS_TOKEN_ID' || true)
  while read -r k; do
    [[ -z "$k" ]] && continue
    [[ -n "$ONLY_MATCH" && "$k" != *"$ONLY_MATCH"* ]] && continue
    # Chained suffix strips, NOT an extglob `_@(ID|SECRET)` pattern: extglob is off by
    # default in a non-interactive shell, and an unmatched extglob silently strips
    # nothing, so the base names would keep their _ID/_SECRET suffix and the pair would
    # never be assembled. Each key ends in exactly one of the two, so chaining is exact.
    _base="${k%_ID}"; _base="${_base%_SECRET}"
    ACCESS_BASESET["$_base"]=1
  done < <(doppler secrets -p "$PROJECT" -c "$cfg" --only-names 2>/dev/null |
    grep -oE '[A-Z0-9_]*ACCESS_TOKEN_(ID|SECRET)' || true)
done

# ── NON-VACUITY GATE ────────────────────────────────────────────────────────
# `CONFIGS` emptiness was guarded; key emptiness was not, so every path that enumerated
# NOTHING fell through to `exit 0` — a clean bill of health for a question never asked.
# That is the exact defect this script's own header condemns, one level up, and it was
# reachable two ways: a typo'd/renamed `--only` filter, and a Doppler read the caller is
# not scoped for.
#
# It matters most at the two call sites wired in the same PR as this guard: the release
# preflight prints "verified live" on exit 0, and the twice-daily scheduled arm is the only
# continuous fleet-wide coverage there is.
if (( ${#KEYSET[@]} + ${#ACCESS_BASESET[@]} == 0 )); then
  {
    echo "ERROR: enumerated 0 token-shaped keys across ${#CONFIGS[@]} config(s)${ONLY_MATCH:+ under --only '$ONLY_MATCH'}."
    echo "       This is a COVERAGE GAP, not a clean bill of health — nothing was checked."
    echo "       Likely causes: the --only filter matches no key; or this Doppler token"
    echo "       cannot read secret names in the scanned configs."
  } >&2
  exit 2
fi

declare -A VERDICT=()   # token value -> LIVE|DEAD  (verify each distinct value once)
DEAD_ROWS=()
LIVE_N=0
DEAD_N=0

verify_value() {
  local v="$1"
  if [[ -z "${VERDICT[$v]:-}" ]]; then
    local ok
    ok=$(curl -s --max-time 20 -H "Authorization: Bearer $v" \
      "https://api.cloudflare.com/client/v4/user/tokens/verify" |
      python3 -c 'import json,sys
try: print("LIVE" if json.load(sys.stdin).get("success") else "DEAD")
except Exception: print("DEAD")' 2>/dev/null)
    VERDICT[$v]="${ok:-DEAD}"
  fi
  printf '%s' "${VERDICT[$v]}"
}

for key in $(printf '%s\n' "${!KEYSET[@]}" | sort); do
  for cfg in "${CONFIGS[@]}"; do
    val=$(doppler secrets get "$key" -p "$PROJECT" -c "$cfg" --plain 2>/dev/null)
    [[ -z "$val" ]] && continue
    state=$(verify_value "$val")
    if [[ "$state" == "DEAD" ]]; then
      DEAD_N=$((DEAD_N + 1)); DEAD_ROWS+=("$key|$cfg")
    else
      LIVE_N=$((LIVE_N + 1))
    fi
  done
done

# ── Cloudflare ACCESS SERVICE TOKENS ────────────────────────────────────────
#
# An Access service token is a client-id/secret PAIR, not an API token, so
# verify_value() above is the wrong instrument for it — /user/tokens/verify with a
# `Authorization: Bearer` header cannot say anything about a pair, and the 400/401 it
# returns would be read as DEAD for a perfectly live token. The pair is verified the way
# it is actually used: presented to an Access-protected hostname.
#
# 200 => LIVE, 403 => DEAD.
#
# The 200 here is EMPTY, and that is correct, not suspicious. registry.<domain> is a
# `tcp://` tunnel ingress consumable only via `cloudflared access tcp`, so a plain HTTPS
# GET is not the WebSocket upgrade that stream needs and nothing is proxied. Cloudflare
# answers on its own. The response therefore says exactly one thing — whether Access
# ACCEPTED the credentials — which is precisely the question this script asks, and
# nothing about whether the origin is healthy. Misreading that empty 200 as "Cloudflare
# is answering without a working origin" is what consumed the 2026-07-29 incident's
# diagnostic budget; it is called out here so the next reader of this code does not
# repeat it.
#
# HOSTNAME MAPPING: which hostname a given token is authorised for is not derivable from
# its Doppler key name, so it is mapped explicitly. An enumerated token with no mapping
# is reported UNVERIFIABLE and fails the run — never silently counted LIVE. That keeps
# the enumeration Doppler-derived (a new token cannot be missed) while refusing to
# guess: a green light this script has not earned is the exact failure it exists to end.
APP_DOMAIN_BASE="${APP_DOMAIN_BASE:-soleur.ai}"
access_hostname_for() {
  case "$1" in
    REGISTRY_PUSH_ACCESS_TOKEN) printf 'registry.%s' "$APP_DOMAIN_BASE" ;;
    CI_SSH_ACCESS_TOKEN)        printf 'ssh.%s' "$APP_DOMAIN_BASE" ;;
    *) printf '' ;;
  esac
}
# A one-line hint per unmapped base, so the report can say what to DO. Without this the
# remediation printed for an unverifiable row is the DEAD-token one ("set the live value
# on the prd ROOT config"), which is wrong twice over: nothing is stale, and no Doppler
# edit fixes a missing mapping.
access_config_hint() {
  printf 'no probe configured — add a hostname mapping for %s to access_hostname_for() in %s' \
    "$1" "$(basename "${BASH_SOURCE[0]}")"
}

UNVERIFIABLE_ROWS=()
declare -A PAIR_VERDICT=()   # "host|id|secret" -> LIVE|DEAD (verify each distinct pair once)

verify_access_pair() {
  local host="$1" id="$2" secret="$3" cache_key="$1|$2|$3"
  if [[ -z "${PAIR_VERDICT[$cache_key]:-}" ]]; then
    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
      -H "CF-Access-Client-Id: $id" \
      -H "CF-Access-Client-Secret: $secret" \
      "https://${host}/" 2>/dev/null || printf '000')
    # Fail CLOSED on anything that is not an explicit 200. A timeout, a DNS failure or a
    # 5xx means this script did not learn the token is good, and "did not learn" must
    # never render as LIVE — that is the shape of every silent-green bug in this area.
    case "$code" in
      200) PAIR_VERDICT[$cache_key]="LIVE" ;;
      *)   PAIR_VERDICT[$cache_key]="DEAD:${code}" ;;
    esac
  fi
  printf '%s' "${PAIR_VERDICT[$cache_key]}"
}

for base in $(printf '%s\n' "${!ACCESS_BASESET[@]}" | sort); do
  # A Cloudflare Access service token is a PAIR. If no `<base>_ID` exists anywhere in the
  # fleet, this base is not one — it is some other vendor's credential whose name merely
  # ends in _ACCESS_TOKEN_SECRET, and treating it as an Access pair invents a key that
  # does not exist.
  #
  # Measured against live Doppler before this guard: `X_ACCESS_TOKEN_SECRET` (an X/Twitter
  # OAuth 1.0a secret, present in 11 of 13 configs) produced base `X_ACCESS_TOKEN`, and the
  # reporting path below rendered a FABRICATED `X_ACCESS_TOKEN_ID/_SECRET` row — a
  # credential name that has never existed — inside an ops email whose entire job is naming
  # a real stale key. The scheduled arm would have sent that twice daily, forever.
  if [[ -z "${ALL_ID_KEYS[${base}_ID]:-}" ]]; then
    continue
  fi
  host=$(access_hostname_for "$base")
  if [[ -z "$host" ]]; then
    UNVERIFIABLE_ROWS+=("${base}_ID/_SECRET|$(access_config_hint "$base")")
    continue
  fi
  for cfg in "${CONFIGS[@]}"; do
    tid=$(doppler secrets get "${base}_ID" -p "$PROJECT" -c "$cfg" --plain 2>/dev/null)
    tsec=$(doppler secrets get "${base}_SECRET" -p "$PROJECT" -c "$cfg" --plain 2>/dev/null)
    # Both halves absent = this config simply does not carry the token. ONE half present
    # is a distinct and worse state — a half-propagated rotation, which authenticates as
    # nothing — so it is reported rather than skipped.
    if [[ -z "$tid" && -z "$tsec" ]]; then continue; fi
    if [[ -z "$tid" || -z "$tsec" ]]; then
      DEAD_N=$((DEAD_N + 1)); DEAD_ROWS+=("${base}_ID/_SECRET (only one half present)|$cfg")
      continue
    fi
    state=$(verify_access_pair "$host" "$tid" "$tsec")
    if [[ "$state" == LIVE ]]; then
      LIVE_N=$((LIVE_N + 1))
    else
      DEAD_N=$((DEAD_N + 1)); DEAD_ROWS+=("${base}_ID/_SECRET (HTTP ${state#DEAD:} from ${host})|$cfg")
    fi
  done
done

# An enumerated-but-unmappable token is a real gap in this script's coverage, so it stays
# loud and non-zero (see the exit at the foot of the file).
#
# It is NOT folded into DEAD_ROWS. "Unverified" and "rejected by Cloudflare" are different
# facts with different remedies, and merging them printed unverifiable rows under the
# heading "STALE — these configs hold a token value Cloudflare no longer accepts" followed
# by "set the live value on the prd ROOT config" — sending an operator to rotate a healthy
# credential. Reporting a cause nothing measured is the defect this PR exists to drain;
# the workflow got per-stage `mirror_reason` labels for exactly this reason, and the
# detector should not be the one place that still conflates them.
UNVERIFIABLE_N=${#UNVERIFIABLE_ROWS[@]}

if [[ "$JSON_OUT" -eq 1 ]]; then
  # `split("|", 1)` — maxsplit 1, so a diagnostic containing a pipe cannot shift fields.
  # Unverifiable rows get their own key rather than riding in "stale" with the diagnostic
  # sentence mis-rendered into the "config" field.
  python3 - "$LIVE_N" "$DEAD_N" "$UNVERIFIABLE_N" "${DEAD_ROWS[@]:-}" "--" "${UNVERIFIABLE_ROWS[@]:-}" <<'PY'
import json, sys
live, dead, unver = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
rest = sys.argv[4:]
sep = rest.index("--")
def rows(xs, second):
    out = []
    for r in xs:
        if not r:
            continue
        k, _, v = r.partition("|")
        out.append({"key": k, second: v})
    return out
print(json.dumps({
    "live": live, "dead": dead, "unverifiable": unver,
    "stale": rows(rest[:sep], "config"),
    "unverifiable_keys": rows(rest[sep + 1:], "reason"),
}, indent=2))
PY
else
  echo "Cloudflare token drift check — project '$PROJECT'"
  echo "  configs scanned: ${#CONFIGS[@]}   API-token keys: ${#KEYSET[@]}   Access service tokens: ${#ACCESS_BASESET[@]}"
  echo "  live entries: $LIVE_N   dead entries: $DEAD_N   unverifiable: $UNVERIFIABLE_N"
  if [[ "$DEAD_N" -gt 0 ]]; then
    echo
    echo "STALE — these configs hold a token value Cloudflare no longer accepts:"
    for r in "${DEAD_ROWS[@]}"; do echo "  ${r%%|*}  in  ${r##*|}"; done
    echo
    echo "A rotation did not propagate. Terraform will NOT fix this: the"
    echo "doppler_secret resources carry lifecycle.ignore_changes = [value], so"
    echo "'terraform apply' reports 'No changes' while the stale value persists."
    echo "Set the live value on the 'prd' ROOT config; branch configs inherit it."
  fi
  if [[ "$UNVERIFIABLE_N" -gt 0 ]]; then
    echo
    echo "UNVERIFIABLE — this script has no probe for these keys, so it drew NO conclusion."
    echo "Nothing below is known to be stale; nothing below is known to be live."
    for r in "${UNVERIFIABLE_ROWS[@]}"; do echo "  ${r%%|*}  —  ${r#*|}"; done
    echo
    echo "Fix the DETECTOR, not the credential: add a hostname mapping to"
    echo "access_hostname_for(). Do NOT rotate these tokens on the strength of this run."
  fi
fi

# Either condition is non-zero: a dead token is a live outage waiting, and an unverifiable
# one means this run cannot claim the fleet is clean.
[[ "$DEAD_N" -gt 0 || "$UNVERIFIABLE_N" -gt 0 ]] && exit 1
exit 0
