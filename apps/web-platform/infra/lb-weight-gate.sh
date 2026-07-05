#!/usr/bin/env bash
# lb-weight-gate.sh — the programmatic ADR-068 §(c) LB-weight gate.
#
# PURE + FAIL-CLOSED + SHAPE-ONLY. Reads ONLY injected env (no Doppler calls — the
# Doppler-sourcing entry point ships with the deferred cutover orchestrator, its only
# caller). Exits 0 ONLY if BOTH §(c) conditions' CONFIG-SHAPE holds; any missing / empty
# / malformed input exits non-zero with a structured `gate_fail sub_condition=…` line on
# stderr naming the failed sub-condition.
#
# On success it prints `requires_runtime_bind_probe=true` + a SHAPE-ONLY banner so a
# consumer that reads exit 0 as "safe to weight web-2" is contractually wrong: this proves
# config-shape in Doppler, NOT that any listener bound or the container env is live. The
# deferred orchestrator MUST satisfy a SEPARATE on-host runtime gate before any weight flip.
#
#   Condition A (owner-side relay config-shape):
#     - SOLEUR_PROXY_BIND non-empty
#     - SOLEUR_PROXY_PEER_ALLOWLIST parses (parseProxyPeerAllowlist parity: split ",",
#       trim, drop empties) to a NON-EMPTY set
#     - SOLEUR_HOST_ROSTER parses (loadHostRoster parity: JSON object, string values) AND
#       the gate's ADDED fail-closed checks the loader lacks (loader silently → {}):
#       reject non-object / invalid-JSON / duplicate-key / blank key / blank-or-non-string
#       value; web-2 must be a roster host_id; allowlist peers ⊆ roster addresses.
#
#   Condition B (git-data cut-over config-shape):
#     - GIT_DATA_STORE_ENABLED == "true"
#     - GIT_DATA_LUKS_CUTOVER_AT is an ISO-8601 instant with
#       now - GIT_DATA_LUKS_CUTOVER_AT >= GIT_DATA_LUKS_SOAK_DAYS (default 3, > 0) days.
#       Absent / garbage / future / soak-not-elapsed → non-zero (fail-closed).
set -euo pipefail

# --- Structured fail-closed exit ---------------------------------------------
fail() {
  # $1 = sub-condition id
  echo "gate_fail sub_condition=$1" >&2
  exit 1
}

# =============================================================================
# Condition A — owner-side relay config-shape
# =============================================================================

# A.1 — SOLEUR_PROXY_BIND non-empty (trimmed).
PROXY_BIND="${SOLEUR_PROXY_BIND-}"
PROXY_BIND="${PROXY_BIND#"${PROXY_BIND%%[![:space:]]*}"}"
PROXY_BIND="${PROXY_BIND%"${PROXY_BIND##*[![:space:]]}"}"
[[ -n "$PROXY_BIND" ]] || fail "A_proxy_bind_empty"

# PARITY POINTER: the roster/allowlist parsing below intentionally MIRRORS (and is
# stricter than) the two TypeScript loaders it gates for:
#   - allowlist  ← session-proxy.ts  `parseProxyPeerAllowlist` (split ",", trim, drop empties)
#   - roster     ← session-router.ts `loadHostRoster`          (JSON object, string values)
# Keep the three in sync: a change to either loader's parse contract must be reflected
# here. (A shared golden fixture is a larger follow-up; this pointer suffices for now.)
# Note the DIRECTIONS differ — the allowlist is the INBOUND accept set, the roster is the
# OUTBOUND dial map — so this gate asserts BOTH containment directions (see A.3 below).

# A.2 — SOLEUR_PROXY_PEER_ALLOWLIST → non-empty set, parseProxyPeerAllowlist parity
#       (split ",", trim each, drop empties).
declare -a ALLOWLIST=()
parse_allowlist() {
  local csv="${1-}" p
  local -a raw=()
  local IFS=','
  read -ra raw <<<"$csv"
  for p in "${raw[@]}"; do
    p="${p#"${p%%[![:space:]]*}"}"   # ltrim
    p="${p%"${p##*[![:space:]]}"}"   # rtrim (POSIX [:space:] includes the here-string newline)
    [[ -n "$p" ]] && ALLOWLIST+=("$p")
  done
  # Force a 0 return: when the LAST token is empty the `[[ -n "$p" ]] &&` above evaluates
  # false, which would otherwise be the function's exit status and — under `set -e` — abort
  # the script HERE, before the explicit `A_peer_allowlist_empty` fail() below could emit
  # its structured sub_condition line (rejecting for the wrong, unstructured reason).
  return 0
}
parse_allowlist "${SOLEUR_PROXY_PEER_ALLOWLIST-}"
[[ "${#ALLOWLIST[@]}" -gt 0 ]] || fail "A_peer_allowlist_empty"

# A.3 — SOLEUR_HOST_ROSTER: loadHostRoster parity PLUS the fail-closed checks the loader
#       lacks (loader silently returns {} on any of these).
ROSTER_RAW="${SOLEUR_HOST_ROSTER-}"
ROSTER_RAW="${ROSTER_RAW#"${ROSTER_RAW%%[![:space:]]*}"}"
ROSTER_RAW="${ROSTER_RAW%"${ROSTER_RAW##*[![:space:]]}"}"
[[ -n "$ROSTER_RAW" ]] || fail "A_host_roster_empty"

# Valid JSON?
jq -e . >/dev/null 2>&1 <<<"$ROSTER_RAW" || fail "A_host_roster_invalid_json"
# Object (not array / scalar / null)?
jq -e 'type == "object"' >/dev/null 2>&1 <<<"$ROSTER_RAW" || fail "A_host_roster_not_object"
# Every value a non-blank string?
jq -e 'all(.[]; type == "string" and test("\\S"))' >/dev/null 2>&1 <<<"$ROSTER_RAW" \
  || fail "A_host_roster_bad_value"
# Every key non-blank (no whitespace-only keys)?
jq -e 'all(keys_unsorted[]; test("\\S"))' >/dev/null 2>&1 <<<"$ROSTER_RAW" \
  || fail "A_host_roster_blank_key"

# Duplicate top-level key? JSON.parse (and jq) silently keep last-wins; the raw stream
# emits every occurrence, so a total-vs-unique key count mismatch flags a dup. Values are
# already proven non-blank strings (scalar leaves), so each key surfaces exactly once here.
ROSTER_KEYS=$(jq -cn --stream 'inputs | select(length == 2 and (.[0] | length == 1)) | .[0][0]' \
  <<<"$ROSTER_RAW" 2>/dev/null || true)
key_total=$(printf '%s\n' "$ROSTER_KEYS" | grep -c . || true)
key_uniq=$(printf '%s\n' "$ROSTER_KEYS" | sort -u | grep -c . || true)
[[ "$key_total" -eq "$key_uniq" ]] || fail "A_host_roster_duplicate_key"

# web-2 specifically present as a roster host_id.
jq -e 'has("web-2")' >/dev/null 2>&1 <<<"$ROSTER_RAW" || fail "A_web2_not_in_roster"

# Allowlist peers ⊆ roster addresses (the roster's values are the private-net addresses).
# This is the OUTBOUND-dial direction: every peer we accept must be a host we can reach.
declare -A ROSTER_ADDRS=()
while IFS= read -r addr; do
  [[ -n "$addr" ]] && ROSTER_ADDRS["$addr"]=1
done < <(jq -r '.[]' <<<"$ROSTER_RAW")
for peer in "${ALLOWLIST[@]}"; do
  [[ -n "${ROSTER_ADDRS[$peer]-}" ]] || fail "A_allowlist_not_subset_of_roster"
done

# web-2's roster (dial) address ⊆ allowlist (accept set) — the INBOUND direction the
# subset check above does NOT cover. The allowlist is what THIS owner accepts as an
# inbound relay peer (session-proxy.ts parseProxyPeerAllowlist); the roster is the
# outbound dial map (session-router.ts loadHostRoster). A config like
#   roster={web-1,web-2}, allowlist={web-1 addr}
# PASSES the subset check yet web-1 would REJECT an inbound relay from web-2 (its addr ∉
# allowlist) → post-weight-flip mis-route → web-2 serves an empty /workspaces →
# workspace-gone. So assert web-2's dial address is a MEMBER of the allowlist. (Only
# web-2's is required, not full set equality: extra roster hosts whose addresses are not
# yet in the allowlist are tolerated — see the positive-tolerance test.)
declare -A ALLOWLIST_SET=()
for peer in "${ALLOWLIST[@]}"; do ALLOWLIST_SET["$peer"]=1; done
WEB2_ADDR=$(jq -r '.["web-2"]' <<<"$ROSTER_RAW")
[[ -n "${ALLOWLIST_SET[$WEB2_ADDR]-}" ]] || fail "A_web2_addr_not_in_allowlist"

# =============================================================================
# Condition B — git-data cut-over config-shape
# =============================================================================

# B.1 — feature flag on.
[[ "${GIT_DATA_STORE_ENABLED-}" == "true" ]] || fail "B_git_data_store_disabled"

# B.2 — soak-window days (default 3), must be a positive integer.
SOAK_DAYS="${GIT_DATA_LUKS_SOAK_DAYS:-3}"
[[ "$SOAK_DAYS" =~ ^[0-9]+$ ]] || fail "B_luks_soak_days_invalid"
[[ "$SOAK_DAYS" -gt 0 ]] || fail "B_luks_soak_days_invalid"

# B.3 — LUKS-cutover soak marker: present, ISO-8601-shaped, parseable.
MARKER="${GIT_DATA_LUKS_CUTOVER_AT-}"
MARKER="${MARKER#"${MARKER%%[![:space:]]*}"}"
MARKER="${MARKER%"${MARKER##*[![:space:]]}"}"
[[ -n "$MARKER" ]] || fail "B_luks_cutover_marker_absent"

ISO_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}([T ][0-9]{2}:[0-9]{2}(:[0-9]{2})?(\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?)?$'
[[ "$MARKER" =~ $ISO_RE ]] || fail "B_luks_cutover_marker_unparseable"

marker_epoch=$(date -u -d "$MARKER" +%s 2>/dev/null) || fail "B_luks_cutover_marker_unparseable"
[[ "$marker_epoch" =~ ^-?[0-9]+$ ]] || fail "B_luks_cutover_marker_unparseable"

# Pre-1970 marker → reject. A negative epoch is nonsensical for a cut-over that post-dates
# the git-data store, and it would make `delta = now - negative` huge → soak trivially
# "elapsed". Reject before the soak math can be fooled.
[[ "$marker_epoch" -ge 0 ]] || fail "B_luks_cutover_marker_pre_epoch"

now_epoch=$(date -u +%s)
delta=$(( now_epoch - marker_epoch ))

# B.4 — future-dated marker → reject (a cut-over can't be in the future).
[[ "$delta" -ge 0 ]] || fail "B_luks_cutover_marker_future"

# B.5 — soak elapsed?
soak_secs=$(( SOAK_DAYS * 86400 ))
[[ "$delta" -ge "$soak_secs" ]] || fail "B_luks_soak_not_elapsed"

# =============================================================================
# SUCCESS — config-shape holds for BOTH conditions. This is NOT weight authorization.
# =============================================================================
echo "requires_runtime_bind_probe=true"
echo "SHAPE-ONLY — NOT weight-flip authorization"
exit 0
