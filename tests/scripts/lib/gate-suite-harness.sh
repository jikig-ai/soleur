# shellcheck shell=bash
# Shared test-support harness for the tfplan-gate suites (#6997).
#
# WHY THIS FILE EXISTS. Nine gate suites now assert the same two properties about the
# shared fail-closed preamble: that a degraded plan ABORTS, and — the harder one — that
# the gate INVOKES the preamble rather than merely sourcing it. The second property is
# proved by a mutation: delete the assert line, and the plan must STILL be rejected while
# the preamble's own signature DISAPPEARS. That contract has four moving parts and every
# one of them can be got subtly wrong in a way that reports a pass. Written nine times it
# is nine chances at a vacuous arm; written once it is one.
#
# It also dedupes `mk_plan`, which was already copy-pasted across FOUR suites
# (test-plan-gate-preamble.sh, test-git-data-host-birth-gate.sh, test-web-host-birth-gate.sh,
# test-web-host-replace-gate.sh) and would have reached thirteen copies.
#
# This is the first test-support library under tests/scripts/lib/ — every other non-.jq
# file there is a production gate sourced by .github/workflows/apply-web-platform-infra.yml.
# It is SOURCED, never invoked, so it needs no scripts/test-all.sh registration; its
# coverage is the nine suites that source it.
#
# NO `if ! declare -F` RE-SOURCE GUARD. The gates carry one because a workflow step may
# source a gate and the preamble in either order. Nothing sources this file twice — the
# suites each source it exactly once, at the top — and a guard here would be cargo-culted
# ceremony that also suppresses the loud error a genuine double-source should produce.
#
# CONTRACT FOR THE SOURCING SUITE. Define these BEFORE sourcing:
#   pass <msg>                     — record a passing assertion
#   fail <msg> <rc> <out>          — record a failing assertion
#   TMP                            — a mktemp -d the suite owns and traps
# And for the mutation helpers only:
#   GATE                           — path to the gate file under test
#   PREAMBLE                       — path to tests/scripts/lib/plan-gate-preamble.sh
#
# Usage:
#   _SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${_SUITE_DIR}/lib/gate-suite-harness.sh"

# ── Fixture builders ──────────────────────────────────────────────────────────────

# mk_plan <file> <json-array-of-resource_changes>
#
# Byte-identical to the four copies it replaces.
mk_plan() {
  local f="$1" changes="$2"
  printf '{"format_version":"1.2","resource_changes":%s}\n' "$changes" > "$f"
}

# rc_entry <address> <type> <actions-json> [<before-json>]
#
# THE `before` PARAMETER EXISTS BECAUSE THE FOUR COPIES HAD DRIFTED, AND THE DRIFT IS
# SEMANTIC, NOT COSMETIC. test-web-host-replace-gate.sh emitted `"before":{}`; the other
# three emitted `"before":null`. In a terraform plan `before: null` means the resource
# does not exist yet (a CREATE) and `before: {}` means it pre-exists (an UPDATE/REPLACE),
# so the two build materially different plans.
#
# Resolved by parameterising rather than by picking whichever copy was open: `null` is the
# default because it is the majority form (3 of 4) AND because it is the correct one for
# the birth/create fixtures that dominate these suites, while a replace-shaped suite can
# ask for `{}` explicitly at the call site where the distinction is visible. Nothing in
# plan-gate-preamble.sh reads `.change.before` — the drift was invisible to the preamble
# and would have stayed invisible had one form simply been imposed on all callers.
rc_entry() {
  printf '{"address":%s,"type":%s,"change":{"actions":%s,"before":%s,"after":{}}}' \
    "$(printf '%s' "$1" | jq -R .)" "$(printf '%s' "$2" | jq -R .)" "$3" "${4:-null}"
}

# rc_noactions <address> <type> — an entry with NO .change.actions key at all (D4).
rc_noactions() {
  printf '{"address":%s,"type":%s,"change":{"before":null,"after":{}}}' \
    "$(printf '%s' "$1" | jq -R .)" "$(printf '%s' "$2" | jq -R .)"
}

# rc_empty_actions <address> <type> — D5: an entry whose actions array is EMPTY.
#
# This is the MEASURED hole. `[] | any(...)` is false so the out-of-scope and firewall
# selects skip it, and `[] | index("delete")` is null so the destroy select skips it — the
# entry is invisible to every arm at once. Measured on a real plan: a happy 18-address
# birth that also carried hcloud_server.web["web-1"] with "actions": [] and "after": null —
# a destroy of the singleton behind app.soleur.ai — scored destroys=0, out_of_scope=0 and
# PASSED. `"after":null` is part of the shape, not decoration: it is what a destroy looks
# like, and it is what makes this fixture a hidden destroy rather than a hidden no-op.
rc_empty_actions() {
  printf '{"address":%s,"type":%s,"change":{"actions":[],"before":{"id":9},"after":null}}' \
    "$(printf '%s' "$1" | jq -R .)" "$(printf '%s' "$2" | jq -R .)"
}

# rc_scalar_change <address> <type> — D6: `.change` is a SCALAR rather than an object.
#
# `.change.actions` on a number raises `Cannot index number with string "actions"`, jq
# exits 5, and `if jq -e '[...|select(bad)]|length > 0'` reads that error as "condition
# false" — so a negative-search classifiability check reports the plan CLASSIFIABLE. That
# is the shape the preamble's positive `all(...)` form exists to close.
rc_scalar_change() {
  printf '{"address":%s,"type":%s,"change":42}' \
    "$(printf '%s' "$1" | jq -R .)" "$(printf '%s' "$2" | jq -R .)"
}

# ── Anti-vacuity floor ────────────────────────────────────────────────────────────

# gate_assert_ran <observed-total> <floor>
#
# NOTHING ELSE ASSERTS THAT THE ASSERTIONS RAN, and every anti-vacuity mechanism in this
# file is defeated by the same move: not calling it. The `cmp -s` floors, the layered
# contract's unmutated control, the preamble-distinctive anchors — all of them live INSIDE
# helpers, so deleting the calls to those helpers silences every one at once while the
# suite still exits 0, because the only merge gate is `[[ "$fails" -eq 0 ]]` and CI reads
# only the exit code.
#
# Measured on this suite family: removing all five preamble arms from
# test-inngest-host-replace-gate.sh took it from 13 assertions to 8 and it still exited 0.
#
# A FLOOR, NOT EQUALITY. The count is developer-incremented, so `-eq` would turn every
# newly-added assertion into a spurious failure and train people to bump the number without
# reading it. Derive the floor from a green run and set it at or just below that.
# SUPERSEDED — ZERO CALLERS, DELIBERATELY (#7695 review F6).
# Every suite hand-rolls its own floor instead, which is the CORRECT choice for the reason ADR-193
# gives: a floor that calls the `fail()` one edit disarms is not a floor, and this helper reports
# through the harness's own pass/fail. Kept for the documented rationale below, but do not read the
# text that follows as live coverage — nothing in the repo invokes it.
gate_assert_ran() {
  local observed="$1" floor="$2"
  if [[ ! "$observed" =~ ^[0-9]+$ ]] || [[ ! "$floor" =~ ^[0-9]+$ ]]; then
    fail "ANTI-VACUITY: non-numeric assertion count (observed='${observed}' floor='${floor}')" "n/a" ""
    return
  fi
  if [[ "$observed" -lt "$floor" ]]; then
    fail "ANTI-VACUITY: only ${observed} assertions ran, floor is ${floor}. Arms were deleted, skipped, or the suite exited early — a suite that runs NO assertions exits 0 exactly like one that passes." "n/a" "observed=${observed} floor=${floor}"
  else
    pass "anti-vacuity floor: ${observed} assertions ran (floor ${floor})"
  fi
}

# ── Assertion ─────────────────────────────────────────────────────────────────────

# gate_check <name> <fn> <want_rc> <needle> <args…>
#
# The GENERAL form. `check()` had drifted into three incompatible signatures across the
# four suites — (name, fn, want_rc, needle, …), (name, want_rc, needle, plan), and a
# 5-argument variant carrying a for_each key — so there is no single `check` that can be
# imposed without rewriting call sites in suites this PR does not otherwise touch.
#
# Resolved by shipping the general form here and letting each suite keep a one-line
# wrapper that binds its own gate function, e.g.
#
#   check() { local n="$1"; shift; gate_check "$n" web_host_birth_gate "$@"; }
#
# The wrapper is the suite's existing signature; the contract lives once.
gate_check() {
  local name="$1" fn="$2" want_rc="$3" needle="$4"; shift 4
  local out rc=0
  # `|| rc=$?` rather than `; rc=$?`: these gates return 1 by design, and under a
  # suite running `set -e` a bare failing command substitution would kill the shell
  # mid-suite — silently, with no tally printed. Making it a tested command keeps the
  # harness usable from `set -euo pipefail` suites as well as `set -uo pipefail` ones.
  out="$("$fn" "$@" 2>&1)" || rc=$?
  if [[ "$rc" -eq "$want_rc" && "$out" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name (want rc=$want_rc containing '$needle')" "$rc" "$out"
  fi
}

# ── Mutation ──────────────────────────────────────────────────────────────────────
#
# THE ARMS ARE NOT INDEPENDENT, and pretending otherwise is how a mutation battery lies.
#
#   SOLE-GUARD  neuter it and the bad input is ACCEPTED (rc 0).
#   LAYERED     neuter it and the input is still REJECTED (rc 1), but this arm's own
#               signature disappears and a DIFFERENT arm's appears — proving both that
#               this arm owns the rejection and that removing it does not open the door.
#
# Both first require the mutation to change the file at all. `sed` exits 0 when it matches
# nothing, so without that floor a mutation aimed at a guard that does not exist emits a
# byte-identical copy, the bad input sails through the UN-neutered gate, and the battery
# reports the arm load-bearing for the weakest possible reason.

# gate_mutate_and_check <label> <sed-expr> <fn> <args…>
#
# SOLE-GUARD contract. Requires GATE and PREAMBLE.
gate_mutate_and_check() {
  local label="$1" sed_expr="$2" fn="$3"; shift 3
  local mutated out rc
  mutated="$TMP/mutated-gate.sh"
  sed "$sed_expr" "$GATE" > "$mutated"
  if cmp -s "$mutated" "$GATE"; then
    fail "$label — the mutation matched NOTHING in the gate (byte-identical copy); the guard is missing or the sed expression drifted. This check would have reported a vacuous pass." "n/a" "no textual change"
    return
  fi
  rc=0
  out="$(bash -c "source '$PREAMBLE'; source '$mutated'; $fn $(printf "'%s' " "$@")" 2>&1)" || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "$label (arm is load-bearing — neutering it lets the bad plan through)"
  else
    fail "$label — the arm did NOT change behavior when neutered; it may be dead code" "$rc" "$out"
  fi
}

# gate_mutate_layered <label> <sed-expr> <own-signature> <fallback-signature> <fn> <args…>
#
# LAYERED contract. Asserts four things after neutering: the file changed (non-vacuity),
# the input is STILL refused, this arm's signature is GONE, and the fallback arm's
# signature is present. Dropping any one turns this into a check that cannot fail.
#
# The unmutated control is what makes it honest: without it, an arm that never fired for
# this fixture would trivially satisfy "own signature absent".
#
# ANCHOR CHOICE IS LOAD-BEARING FOR THE PREAMBLE ARMS. `<own-signature>` must be text only
# the PREAMBLE can emit — "unclassifiable plan entry", or "Fail-closed: an unreadable plan
# is not evidence of a safe one". It must NOT be the gate's name: every gate prefixes its
# OWN pre-existing aborts with that name too, so a gate-name anchor cannot tell a preamble
# abort from a gate abort, and an arm built on it is a redness detector rather than a
# binding. Pass the gate name as part of the needle only IN ADDITION to distinctive text.
gate_mutate_layered() {
  local label="$1" sed_expr="$2" own="$3" fallback="$4" fn="$5"; shift 5
  local mutated base out rc
  mutated="$TMP/mutated-layered.sh"
  sed "$sed_expr" "$GATE" > "$mutated"
  if cmp -s "$mutated" "$GATE"; then
    fail "$label — the mutation matched NOTHING in the gate (byte-identical copy); the guard is missing or the sed expression drifted." "n/a" "no textual change"
    return
  fi
  base="$("$fn" "$@" 2>&1)" || true
  if [[ "$base" != *"$own"* ]]; then
    fail "$label — the unmutated gate did not reject this input via the '$own' arm; the fixture does not exercise it." "n/a" "$base"
    return
  fi
  rc=0
  out="$(bash -c "source '$PREAMBLE'; source '$mutated'; $fn $(printf "'%s' " "$@")" 2>&1)" || rc=$?
  if [[ "$rc" -eq 1 && "$out" != *"$own"* && "$out" == *"$fallback"* ]]; then
    pass "$label (layered — owns the rejection; neutering it hands off to '$fallback', never to PASS)"
  else
    fail "$label — layered contract broken (want rc=1, '$own' absent, '$fallback' present)" "$rc" "$out"
  fi
}

# ── gate_harness_selftest — drive the harness's OWN wrappers once each ────────────────
# Every suite that sources this file has an instrument self-test for its local `pass`/`fail`, and
# a wrapper self-test for whatever local `check()` it defines. NEITHER reaches the two wrappers
# DEFINED HERE. Measured on test-inngest-volume-recut-gate.sh: replacing `gate_check`'s body with a
# bare `pass "$name"` left the suite at 50 passed, 0 failed with the anti-vacuity floor healthy,
# and `gate_mutate_layered` the same — and this harness is sourced by 13 suites, so one edit here
# silences the degraded-shape and invoked-not-sourced batteries in all of them at once.
#
# Call it once, immediately after sourcing, BEFORE the first real arm. It drives each wrapper in
# the direction that must FAIL, then rolls the caller's counters back so the floor is unaffected.
# It does not use `pass`/`fail` to report its own result for the same reason ADR-193 gives: a floor
# must not be built out of the helper it backstops.
gate_harness_selftest() {
  # COUNTER NAMES ARE RESOLVED ONCE, BY PRESENCE, AND WRITTEN THROUGH INDIRECTION.
  #
  # The first cut read `${passes:-${pass_count:-0}}` and then restored ALL FOUR names
  # unconditionally. Two defects, both measured:
  #
  #   (a) The restore CREATED the name the chain reads first. In a pass_count/fail_count suite,
  #       call 1 left `fails` set, and `:-` fires only on unset-or-empty -- `0` is neither -- so
  #       call 2 bound to the stale `fails` instead of the live `fail_count`. Three real failures
  #       recorded between the calls were erased by the restore, and the diagnosis blamed
  #       gate_check(), which was working correctly.
  #   (b) A THIRD naming fell through to a literal `0`. tests/scripts/test-destroy-guard-counter-
  #       web-platform.sh -- the suite guarding the destroy filter -- names its counters
  #       `pass`/`fail`. Neither `passes` nor `pass_count` exists there, so `_f` bound to 0,
  #       gate_check incremented `fail`, the chain never read it, and the self-test printed
  #       "every gate_check assertion in this suite is decorative" against a HEALTHY gate_check.
  #       Anyone wiring this into that suite would have seen a red and most plausibly "fixed" the
  #       harness.
  #
  # `${x+set}` tests PRESENCE, not emptiness, so a legitimate 0 does not fall through. If no known
  # pair is defined the function refuses loudly rather than defaulting to 0 and inventing a verdict.
  #
  # REQUIRES `GATE` and `PREAMBLE` to be set (gate_mutate_layered reads them), so call this after
  # the suite has set them -- NOT merely after sourcing this file.
  local _n_p='' _n_f=''
  local _cand
  for _cand in passes pass_count pass; do
    if [[ -n "${!_cand+set}" ]]; then _n_p="$_cand"; break; fi
  done
  for _cand in fails fail_count fail; do
    if [[ -n "${!_cand+set}" ]]; then _n_f="$_cand"; break; fi
  done
  if [[ -z "$_n_p" || -z "$_n_f" ]]; then
    printf '  FAIL INSTRUMENT: gate_harness_selftest could not find this suite'"'"'s pass/fail counters (looked for passes/pass_count/pass and fails/fail_count/fail). Refusing to report a verdict it did not measure.\n' >&2
    return 1
  fi

  local _p="${!_n_p}" _f="${!_n_f}"
  local _ok_check=1 _ok_layered=1
  _ghs_never_aborts() { echo "gate_harness_selftest: this fixture always succeeds"; return 0; }

  # gate_check: demand an ABORT from a function that cannot abort. Must record a FAILURE.
  gate_check "SELFTEST (expected to fail)" _ghs_never_aborts 1 "reason=impossible" >/dev/null 2>&1 || true
  [[ "${!_n_f}" -eq $((_f + 1)) ]] || _ok_check=0

  # gate_mutate_layered: a sed expression that matches NOTHING, so its byte-identical-copy arm fires.
  #
  # ACKNOWLEDGED LIMIT: this drives only the FIRST of that wrapper's four checks. The layered
  # contract it backstops (rc==1 AND own-token absent AND fallback-token present) is not exercised,
  # so a neutering that preserves `cmp -s` and softens the final comparison would pass this. Driving
  # the full contract needs a real gate plus a landing mutation, which belongs in the calling suite's
  # own layered rows, not in a harness self-test. Recorded rather than left for a reader to assume
  # this covers more than it does.
  gate_mutate_layered "SELFTEST (expected to fail)" 's|__GHS_MATCHES_NOTHING_XYZZY__|:|' \
    "__ghs_own__" "__ghs_fallback__" _ghs_never_aborts >/dev/null 2>&1 || true
  [[ "${!_n_f}" -eq $((_f + 2)) ]] || _ok_layered=0

  # Restore ONLY the pair actually read, so a differently-named counter is never created or clobbered.
  # On FAILURE the fail counter is restored and then incremented by one, so the suite's own tally and
  # exit status carry the verdict — a self-test that only returns non-zero relies on every call site
  # remembering to act on it, and ten of the eleven call sites are one line written by a sweep.
  printf -v "$_n_p" '%s' "$_p"
  if [[ "$_ok_check" -ne 1 || "$_ok_layered" -ne 1 ]]; then
    printf -v "$_n_f" '%s' "$((_f + 1))"
  else
    printf -v "$_n_f" '%s' "$_f"
  fi
  unset -f _ghs_never_aborts

  if [[ "$_ok_check" -ne 1 ]]; then
    printf '  FAIL INSTRUMENT: gate_check() did not record a failure on a must-fail arm (watched counter: %s) -- every gate_check assertion in this suite is decorative.\n' "$_n_f" >&2
    return 1
  fi
  if [[ "$_ok_layered" -ne 1 ]]; then
    printf '  FAIL INSTRUMENT: gate_mutate_layered() did not record a failure on a mutation that cannot land (watched counter: %s) -- every layered assertion in this suite is decorative.\n' "$_n_f" >&2
    return 1
  fi
  printf '  ok   instrument: gate_check() and gate_mutate_layered() both discriminate (counters: %s/%s)\n' "$_n_p" "$_n_f"
  return 0
}
