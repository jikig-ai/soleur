#!/usr/bin/env bash
# lb-weight-gate.sh — the rebuilt ADR-068 §(c) / ADR-141 D3 anti-pooling gate (#6575 rebuild, #6459).
#
# PURE + FAIL-CLOSED + SHAPE-ONLY. Reads ONLY injected env (no Doppler/network calls — the
# Doppler-sourcing entry point ships with the deferred cutover orchestrator, its only caller).
#
# WHY THIS EXISTS. web-2 is an OUT-OF-BAND standby at serving-weight 0 (ADR-141 D2). A request
# routed to web-2 before the ADR-068 Phase-3 flip hits the empty /workspaces (the sole copy is
# web-1's volume) = the "workspace-gone" single-user incident. This gate fail-closes any attempt to
# pool web-2 into serving before the flip preconditions hold.
#
# THE #6575 DELETION FLAW, AND THE FIX (ADR-141 D3). The original gate REQUIRED web-2 in the
# SOLEUR_HOST_ROSTER as its FIRST assertion, so after web-2 retired (#6538) a *correct* config
# omitting web-2 could only ever FAIL — "a gate a correct configuration cannot pass is not a guard"
# — and it was deleted (2026-07-20, #6575). The fix is a POLARITY inversion via a serving-weight
# TOP-GUARD: the state a correct PRE-FLIP config is actually in (web-2 weight==0, NOT in the serving
# rotation) is the PASS branch, short-circuited FIRST, before any Condition A/B evaluation. The
# original Condition A (owner-side relay shape) + Condition B (git-data cut-over soak) are RETAINED
# verbatim but run ONLY when web-2 is actually being pooled (weight>0 OR in rotation) — exactly when
# the flip-authorization shape must hold. So a correct standby config PASSES, and an illegal
# pre-flip pooling FAILS: the definition of a real guard.
#
# SHAPE-ONLY. On the flip-authorization branch, success prints `requires_runtime_bind_probe=true` +
# a SHAPE-ONLY banner: it proves config-shape, NOT that any listener bound. The deferred orchestrator
# MUST satisfy a SEPARATE on-host runtime-bind probe (ADR-068 §(c)(3) /internal/readyz) before any
# weight flip. Exit 0 is NEVER weight-flip authorization by itself.
#
# The COMMITTED-CONFIG anti-pooling assertion (dns.tf app record stays web-1-only, the tunnel
# connector predicate excludes web-2, no cloudflare_load_balancer pools web-2 at weight>0) is
# Condition C in lb-weight-gate.test.sh — it is the CI-side regression guard over the tree, kept out
# of this env-driven runtime gate so the two never drift (ADR-141 D3 / CTO ruling 2b).
#
#   Top-guard (ADR-141 D3): SOLEUR_WEB2_SERVING_WEIGHT (explicit integer ≥0; absent/non-int/negative
#     → FAIL CLOSED) + SOLEUR_SERVING_ROTATION (present, comma-set; absent → FAIL CLOSED). PASS iff
#     weight==0 AND web-2 ∉ rotation. Otherwise → Conditions A + B.
#   Condition A (owner-side relay config-shape): SOLEUR_PROXY_BIND non-empty; SOLEUR_PROXY_PEER_
#     ALLOWLIST parses to non-empty set; SOLEUR_HOST_ROSTER JSON object with web-2 present, allowlist
#     ⊆ roster addrs (outbound dial), web-2 addr ∈ allowlist (inbound accept).
#   Condition B (cut-over config-shape): GIT_DATA_STORE_ENABLED=="true"; GIT_DATA_LUKS_CUTOVER_AT
#     AND WORKSPACES_LUKS_CUTOVER_AT (ADR-141 D3 coupling #2) each ISO-8601, parseable, ≥epoch, not
#     future, now-marker ≥ <soak>_SOAK_DAYS(3)*86400. The WORKSPACES_LUKS marker is what makes
#     deferring web-2's fresh-boot LUKS path to Phase-4 fail-CLOSED: a plaintext web-2 cannot be pooled.
set -euo pipefail

# --- Structured fail-closed exit ---------------------------------------------
fail() {
  # $1 = sub-condition id
  echo "gate_fail sub_condition=$1" >&2
  exit 1
}

# =============================================================================
# TOP-GUARD — web-2 serving-weight / rotation membership (ADR-141 D3 polarity fix)
# =============================================================================

# Weight: absent/empty → FAIL CLOSED (never default-0-PASS — a broken or renamed injection must not
# silently authorize standby, nor mask a real pooling; CTO ruling 2c.1). Only an explicit parsed
# integer ≥ 0 is accepted. The strict regex rejects "0.0"/"0x0"/"false"/" 0x" — anything non-integer.
WEIGHT="${SOLEUR_WEB2_SERVING_WEIGHT-}"
WEIGHT="${WEIGHT#"${WEIGHT%%[![:space:]]*}"}"   # ltrim
WEIGHT="${WEIGHT%"${WEIGHT##*[![:space:]]}"}"   # rtrim
[[ -n "$WEIGHT" ]] || fail "TOP_web2_weight_absent"
[[ "$WEIGHT" =~ ^-?[0-9]+$ ]] || fail "TOP_web2_weight_not_integer"
[[ "$WEIGHT" -ge 0 ]] || fail "TOP_web2_weight_negative"

# Rotation membership set: MUST be present (SET, even if the empty string = "no rotation"). An UNSET
# var → FAIL CLOSED (not assume-empty→PASS; CTO ruling 2c.2). `${VAR+set}` is non-empty iff VAR is
# set, so `-z` here is true ONLY when genuinely unset — distinct from an explicit empty "no rotation".
[[ -n "${SOLEUR_SERVING_ROTATION+set}" ]] || fail "TOP_serving_rotation_absent"
ROTATION_RAW="${SOLEUR_SERVING_ROTATION}"

# Parse the rotation set (comma-split, trim each, drop empties — parseProxyPeerAllowlist parity).
declare -A ROTATION_SET=()
parse_rotation() {
  local csv="${1-}" h
  local -a raw=()
  local IFS=','
  read -ra raw <<<"$csv"
  for h in "${raw[@]}"; do
    h="${h#"${h%%[![:space:]]*}"}"
    h="${h%"${h##*[![:space:]]}"}"
    [[ -n "$h" ]] && ROTATION_SET["$h"]=1
  done
  return 0   # force 0 so a trailing-empty token's `&&` does not abort under set -e
}
parse_rotation "$ROTATION_RAW"

web2_in_rotation=0
[[ -n "${ROTATION_SET[web-2]-}" ]] && web2_in_rotation=1

# The PASS branch that fixes the #6575 flaw: web-2 weight==0 AND not in the serving rotation is the
# correct OUT-OF-BAND STANDBY state — the state a correct pre-flip config is actually in. Short-
# circuit FIRST, before ANY Condition A/B evaluation, so a legitimately-absent flip-time roster/relay
# env can NEVER resurrect a can-only-fail path (CTO ruling 2b R5). A+B run only when pooling.
if [[ "$WEIGHT" -eq 0 && "$web2_in_rotation" -eq 0 ]]; then
  echo "web2_standby=true serving_weight=0 not_in_rotation"
  echo "SHAPE-ONLY — NOT weight-flip authorization"
  exit 0
fi

# ---- web-2 IS being pooled (weight>0 OR in the serving rotation). The flip-authorization shape
#      (Conditions A + B) MUST hold, else this is an illegal pre-flip pooling → workspace-gone. ----

# =============================================================================
# Condition A — owner-side relay config-shape
# =============================================================================

# A.1 — SOLEUR_PROXY_BIND non-empty (trimmed).
PROXY_BIND="${SOLEUR_PROXY_BIND-}"
PROXY_BIND="${PROXY_BIND#"${PROXY_BIND%%[![:space:]]*}"}"
PROXY_BIND="${PROXY_BIND%"${PROXY_BIND##*[![:space:]]}"}"
[[ -n "$PROXY_BIND" ]] || fail "A_proxy_bind_empty"

# PARITY POINTER: the roster/allowlist parsing below intentionally MIRRORS (and is stricter than)
# the two TypeScript loaders it gates for:
#   - allowlist  ← session-proxy.ts  `parseProxyPeerAllowlist` (split ",", trim, drop empties)
#   - roster     ← session-router.ts `loadHostRoster`          (JSON object, string values)
# Keep the three in sync: a change to either loader's parse contract must be reflected here. The
# DIRECTIONS differ — the allowlist is the INBOUND accept set, the roster the OUTBOUND dial map — so
# this gate asserts BOTH containment directions (see A.3 below).

# A.2 — SOLEUR_PROXY_PEER_ALLOWLIST → non-empty set, parseProxyPeerAllowlist parity.
declare -a ALLOWLIST=()
parse_allowlist() {
  local csv="${1-}" p
  local -a raw=()
  local IFS=','
  read -ra raw <<<"$csv"
  for p in "${raw[@]}"; do
    p="${p#"${p%%[![:space:]]*}"}"   # ltrim
    p="${p%"${p##*[![:space:]]}"}"   # rtrim
    [[ -n "$p" ]] && ALLOWLIST+=("$p")
  done
  # Force a 0 return: when the LAST token is empty the `[[ -n "$p" ]] &&` above evaluates false,
  # which would otherwise be the function's exit status and — under `set -e` — abort HERE, before
  # the explicit `A_peer_allowlist_empty` fail() could emit its structured sub_condition line.
  return 0
}
parse_allowlist "${SOLEUR_PROXY_PEER_ALLOWLIST-}"
[[ "${#ALLOWLIST[@]}" -gt 0 ]] || fail "A_peer_allowlist_empty"

# A.3 — SOLEUR_HOST_ROSTER: loadHostRoster parity PLUS the fail-closed checks the loader lacks
#       (the loader silently returns {} on any of these).
ROSTER_RAW="${SOLEUR_HOST_ROSTER-}"
ROSTER_RAW="${ROSTER_RAW#"${ROSTER_RAW%%[![:space:]]*}"}"
ROSTER_RAW="${ROSTER_RAW%"${ROSTER_RAW##*[![:space:]]}"}"
[[ -n "$ROSTER_RAW" ]] || fail "A_host_roster_empty"

jq -e . >/dev/null 2>&1 <<<"$ROSTER_RAW" || fail "A_host_roster_invalid_json"
jq -e 'type == "object"' >/dev/null 2>&1 <<<"$ROSTER_RAW" || fail "A_host_roster_not_object"
jq -e 'all(.[]; type == "string" and test("\\S"))' >/dev/null 2>&1 <<<"$ROSTER_RAW" \
  || fail "A_host_roster_bad_value"
jq -e 'all(keys_unsorted[]; test("\\S"))' >/dev/null 2>&1 <<<"$ROSTER_RAW" \
  || fail "A_host_roster_blank_key"

# Duplicate top-level key? jq/JSON.parse silently keep last-wins; the raw stream emits every
# occurrence, so a total-vs-unique key count mismatch flags a dup.
ROSTER_KEYS=$(jq -cn --stream 'inputs | select(length == 2 and (.[0] | length == 1)) | .[0][0]' \
  <<<"$ROSTER_RAW" 2>/dev/null || true)
key_total=$(printf '%s\n' "$ROSTER_KEYS" | grep -c . || true)
key_uniq=$(printf '%s\n' "$ROSTER_KEYS" | sort -u | grep -c . || true)
[[ "$key_total" -eq "$key_uniq" ]] || fail "A_host_roster_duplicate_key"

# web-2 specifically present as a roster host_id.
jq -e 'has("web-2")' >/dev/null 2>&1 <<<"$ROSTER_RAW" || fail "A_web2_not_in_roster"

# Allowlist peers ⊆ roster addresses (OUTBOUND-dial direction: every peer we accept must be reachable).
declare -A ROSTER_ADDRS=()
while IFS= read -r addr; do
  [[ -n "$addr" ]] && ROSTER_ADDRS["$addr"]=1
done < <(jq -r '.[]' <<<"$ROSTER_RAW")
for peer in "${ALLOWLIST[@]}"; do
  [[ -n "${ROSTER_ADDRS[$peer]-}" ]] || fail "A_allowlist_not_subset_of_roster"
done

# web-2's roster (dial) address ∈ allowlist (INBOUND accept) — the direction the subset check does
# NOT cover. roster={web-1,web-2}, allowlist={web-1 addr} PASSES the subset check yet web-1 would
# REJECT an inbound relay from web-2 (its addr ∉ allowlist) → post-flip mis-route → empty /workspaces.
declare -A ALLOWLIST_SET=()
for peer in "${ALLOWLIST[@]}"; do ALLOWLIST_SET["$peer"]=1; done
WEB2_ADDR=$(jq -r '.["web-2"]' <<<"$ROSTER_RAW")
[[ -n "${ALLOWLIST_SET[$WEB2_ADDR]-}" ]] || fail "A_web2_addr_not_in_allowlist"

# =============================================================================
# Condition B — git-data cut-over config-shape
# =============================================================================

# B.1 — feature flag on.
[[ "${GIT_DATA_STORE_ENABLED-}" == "true" ]] || fail "B_git_data_store_disabled"

# B.2 — soak-window days (default 3), positive integer.
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

# Pre-1970 marker → reject: a negative epoch is nonsensical for a cut-over that post-dates the
# git-data store, and `delta = now - negative` would make the soak trivially "elapsed".
[[ "$marker_epoch" -ge 0 ]] || fail "B_luks_cutover_marker_pre_epoch"

now_epoch=$(date -u +%s)
delta=$(( now_epoch - marker_epoch ))

# B.4 — future-dated marker → reject.
[[ "$delta" -ge 0 ]] || fail "B_luks_cutover_marker_future"

# B.5 — soak elapsed?
soak_secs=$(( SOAK_DAYS * 86400 ))
[[ "$delta" -ge "$soak_secs" ]] || fail "B_luks_soak_not_elapsed"

# --- B.6-B.10 — web-2 /workspaces LUKS-backed precondition (ADR-141 D3 coupling #2) -----------
# This is what makes deferring web-2's fresh-boot LUKS path (to the Phase-4 disposability-proof PR)
# FAIL-CLOSED rather than fail-open: a plaintext web-2 can NEVER be pooled, because this branch
# reddens unless web-2's /workspaces is asserted LUKS-backed. web-2's for_each volume is knowingly
# plaintext-but-empty pre-flip (workspaces-luks.tf) and holds no user data; the ONLY way user data
# reaches it is a flip, and a flip requires this marker. Same soak-marker shape as GIT_DATA_LUKS_
# CUTOVER_AT (the WORKSPACES_LUKS_CUTOVER_AT is a Doppler prd ISO-8601 key the Phase-4 fresh-boot
# LUKS cutover writes; absent/malformed/future/soak-not-elapsed = not satisfied = fail-closed today).
WS_SOAK_DAYS="${WORKSPACES_LUKS_SOAK_DAYS:-3}"
[[ "$WS_SOAK_DAYS" =~ ^[0-9]+$ ]] || fail "B_workspaces_luks_soak_days_invalid"
[[ "$WS_SOAK_DAYS" -gt 0 ]] || fail "B_workspaces_luks_soak_days_invalid"

WS_MARKER="${WORKSPACES_LUKS_CUTOVER_AT-}"
WS_MARKER="${WS_MARKER#"${WS_MARKER%%[![:space:]]*}"}"
WS_MARKER="${WS_MARKER%"${WS_MARKER##*[![:space:]]}"}"
[[ -n "$WS_MARKER" ]] || fail "B_workspaces_luks_marker_absent"
[[ "$WS_MARKER" =~ $ISO_RE ]] || fail "B_workspaces_luks_marker_unparseable"
ws_epoch=$(date -u -d "$WS_MARKER" +%s 2>/dev/null) || fail "B_workspaces_luks_marker_unparseable"
[[ "$ws_epoch" =~ ^-?[0-9]+$ ]] || fail "B_workspaces_luks_marker_unparseable"
[[ "$ws_epoch" -ge 0 ]] || fail "B_workspaces_luks_marker_pre_epoch"
ws_delta=$(( now_epoch - ws_epoch ))
[[ "$ws_delta" -ge 0 ]] || fail "B_workspaces_luks_marker_future"
[[ "$ws_delta" -ge $(( WS_SOAK_DAYS * 86400 )) ]] || fail "B_workspaces_luks_soak_not_elapsed"

# =============================================================================
# SUCCESS — pooling requested AND both flip-authorization conditions' shape holds. SHAPE-ONLY;
# NOT weight authorization (the orchestrator's separate on-host runtime-bind probe is still required).
# =============================================================================
echo "requires_runtime_bind_probe=true"
echo "SHAPE-ONLY — NOT weight-flip authorization"
exit 0
