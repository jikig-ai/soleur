#!/usr/bin/env bash
#
# (#7299) Guard that registry-userdata-budget.sh measures what Terraform STORES.
#
# THE DEFECT THIS EXISTS TO CATCH. `zot-registry.tf` renders the registry host's user_data as
#   base64gzip(replace(templatefile(...), local.registry_rationale_strip, ""))
# but the budget script rendered `templatefile(...)` RAW — no strip. It therefore measured a
# payload no host is ever given: 36,404 B against a 32,768 B cap (a phantom -3,636 B breach)
# where the real stored artifact is ~9.4 kB. The script reported a hard-gate FAILURE on a
# registry that provisions fine, and #7299 was filed against it as an outage.
#
# WHY BEHAVIOURAL, NOT A BODY-GREP. A grep for `registry_rationale_strip` in the script would
# match this file's own prose AND the script's header comments (the false-match class in
# `cq-assert-anchor-not-bare-token`). The invariant is arithmetic, so assert THAT, and assert
# the fail-closed arms by MUTATING a sandbox copy and requiring a distinct exit code.
#
# ASSERT BOTH DIRECTIONS. The first revision of this suite asserted only CEILINGS (headroom
# >= floor, exit 0), which review proved blind in the fail-QUIET direction: mutating
# `stored_bytes=${#stored}` to `$(( ${#stored} / 8 ))` reported "9 checks, 0 failed" while
# claiming 31 kB of headroom. A measurement drifting toward "smaller and safer" is the one that
# strands the host, so every numeric arm here is bounded on BOTH sides.
#
# Sandbox needs only 3 files — the script reads $DIR/{zot-registry.tf,cloud-init-registry.yml}
# and nothing else — so this never copies the 5 MB infra tree.
set -uo pipefail

# /tmp is a machine-global 4 GiB tmpfs shared by parallel worktrees; a direct invocation of
# this suite (the inner loop while editing the script) would otherwise inherit it and become a
# function of another session's disk usage.
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/../../.." && pwd)"
SCRIPT="$DIR/registry-userdata-budget.sh"
TS_TEST="$REPO_ROOT/plugins/soleur/test/cloud-init-user-data-size.test.ts"

# EQUALITY, not a floor. A `checks < N` floor cannot distinguish "all arms passed" from "one
# arm's failure was swallowed" whenever a green run emits exactly N+1 — which is how the first
# revision shipped (floor 8, green run 9). Adding an arm must move this constant.
EXPECTED_CHECKS=16

fails=0
checks=0
pass() { checks=$((checks + 1)); echo "[ok] $1"; }
fail() { checks=$((checks + 1)); fails=$((fails + 1)); echo "[FAIL] $1 — $2" >&2; }

command -v terraform >/dev/null 2>&1 || {
  # Fail closed in CI, matching the script. A SKIP here would report success having asserted
  # nothing — and this suite's whole subject is a gate that did exactly that.
  if [ -n "${CI:-}" ]; then
    echo "registry-userdata-budget.test: terraform is REQUIRED in CI and is not on PATH" >&2
    exit 2
  fi
  echo "registry-userdata-budget.test: SKIP — terraform not on PATH (local dev)" >&2
  exit 0
}

# --- 1-7: the real tree measures the STORED payload -------------------------------------
json="$("$SCRIPT" --json 2>/dev/null)"
rc=$?

if [ "$rc" -eq 0 ]; then
  pass "budget script exits 0 on the committed tree"
else
  fail "budget script exits 0 on the committed tree" "exit=$rc (a strip-less render measures a payload terraform never stores)"
fi

get() { printf '%s' "$json" | grep -oE "\"$1\":-?[0-9]+" | grep -oE -- '-?[0-9]+$'; }
raw=$(get raw_bytes)
stripped=$(get stripped_bytes)
stored=$(get stored_bytes)
cap=$(get cap)
headroom=$(get headroom)

if [ -n "$stripped" ]; then
  pass "--json reports stripped_bytes (the render terraform actually stores)"
else
  fail "--json reports stripped_bytes" "key absent — the script is not applying local.registry_rationale_strip"
fi

# The strip removes ~50 kB of rationale prose from a ~75 kB render. A LOOSE ratio, so ordinary
# prose churn does not red the gate. It is safe to be loose here because the population is
# bimodal, not because the margin is large: the registry template's comments are overwhelmingly
# INDENTED, so any weakening of the leading-whitespace class collapses the strip almost entirely
# rather than shaving it (measured at review: dropping `[ \t]*` moved 74301 -> 73455, failing 3
# arms). A strip that half-works is not a reachable state here.
if [ -n "$raw" ] && [ -n "$stripped" ] && [ "$stripped" -lt $((raw / 2)) ]; then
  pass "strip is effective: stripped ($stripped B) < half of raw ($raw B)"
else
  fail "strip is effective" "raw=$raw stripped=$stripped — expected stripped < raw/2"
fi

ts_floor=$(grep -oE '^const REGISTRY_GZIP_FLOOR = [0-9_]+' "$TS_TEST" | grep -oE '[0-9_]+$' | tr -d '_')
ts_budget=$(grep -oE '^const REGISTRY_GZIP_BUDGET = [0-9_]+' "$TS_TEST" | grep -oE '[0-9_]+$' | tr -d '_')

# THE HEADROOM FLOOR IS DERIVED, NOT DECIDED HERE (#7444, CTO ruling).
#
# This arm used to read `headroom -ge 20000`. That literal was AC1 of the #7299 plan — a
# ONE-SHOT verification that the measurer fix had landed (that the corrected reading was ~23.4 kB
# rather than the phantom -3,636 B), transcribed verbatim into a standing regression arm where it
# silently became a permanent capacity ceiling nobody decided on. It rationed every future
# feature on this host to 3,360 B and blocked a correctness round at 11% over.
#
# Nothing else in the repo held that number: registry-userdata-budget.sh (the gate the operator
# actually runs before a destructive replace) fails only on `stored >= cap`; the recut runbook
# states the operational invariant as "headroom must be > 0, strictly"; the #7299 plan's own
# rejected-alternatives table records "production is 71% under cap"; and the sibling git-data host
# operates at 12,312 B headroom under a budget permitting 4,768 — 4x less conservative on the same
# 32,768 B ForceNew cap.
#
# The ONE number authored as a policy is in the TS oracle: REGISTRY_GZIP_BUDGET < HETZNER_CAP -
# 8_000, i.e. "preserve at least 8,000 B of real headroom". Largest measure-time-to-apply-time
# divergence ever observed on this class is 612 B, so 8,000 is ~13x the worst case.
#
# So this arm DERIVES its floor from that single owning constant and is deliberately redundant
# with the extracted cross-check below: its value is the message in the operator's unit, not an
# independent constraint. Change the budget in cloud-init-user-data-size.test.ts and both move.
if [ -z "$ts_budget" ] || [ -z "$ts_floor" ]; then
  # EXPLICIT, not arithmetic-by-accident: an empty $ts_budget inside $(( )) is 0, which would
  # demand headroom > cap and fail closed for a reason no message names.
  fail "headroom floor derived from the TS budget" "could not extract REGISTRY_GZIP_FLOOR/BUDGET from $TS_TEST — the oracle is unreadable, not satisfied"
elif [ -n "$headroom" ] && [ "$headroom" -ge "$(( cap - ts_budget ))" ]; then
  pass "headroom ${headroom} B >= $(( cap - ts_budget )) B floor derived from REGISTRY_GZIP_BUDGET=${ts_budget} (stored ${stored} B)"
else
  fail "headroom >= derived floor" "stored=$stored exceeds REGISTRY_GZIP_BUDGET=$ts_budget from plugins/soleur/test/cloud-init-user-data-size.test.ts, which is itself gated at HETZNER_CAP - 8000; headroom=$headroom floor=$(( cap - ts_budget ))"
fi

# THE OTHER SIDE OF THE SAME NUMBER. Without this, any mutation that under-reports the payload
# passes every arm above while reporting record headroom.
if [ -n "$stored" ] && [ "$stored" -gt 4000 ]; then
  pass "stored ${stored} B > 4000 B plausibility floor (a gutted payload cannot clear it)"
else
  fail "stored > 4000 B plausibility floor" "stored=$stored — implausibly small; the strip is eating real content or substitutions were lost"
fi

# The entire artifact defends ONE number. Until review, no arm read it: mutating `cap=32768` to
# `65536` left the suite fully green.
if [ "$cap" = "32768" ]; then
  pass "cap is Hetzner's 32768 B ForceNew limit"
else
  fail "cap is Hetzner's 32768 B limit" "got '$cap' — the gate is measuring against the wrong ceiling"
fi

# INDEPENDENT ORACLE (plan AC2). Every arm above compares numbers this script emits about a
# chain this script builds, so they are self-referential by construction. The TS test models the
# same payload with node zlib and pins its own bounds; requiring our byte-exact figure to fall
# inside them triangulates the two measurers against each other. Bounds are EXTRACTED, not
# restated, so they cannot drift.
if [ -z "$ts_floor" ] || [ -z "$ts_budget" ]; then
  fail "cross-check against cloud-init-user-data-size.test.ts bounds" "could not extract REGISTRY_GZIP_FLOOR/BUDGET — the oracle is unreadable, not satisfied"
elif [ -n "$stored" ] && [ "$stored" -gt "$ts_floor" ] && [ "$stored" -lt "$ts_budget" ]; then
  pass "stored ${stored} B agrees with the TS model's bounds (${ts_floor} < x < ${ts_budget})"
else
  fail "stored agrees with the TS model's bounds" "stored=$stored outside (${ts_floor}, ${ts_budget}) — the two measurers disagree about the same payload"
fi

# --- 8: the strip expression is declared exactly once, REPO-WIDE -------------------------
# Counts ASSIGNMENTS, not files, and walks the whole repo rather than one directory glob. The
# first revision did `grep -rcE ... "$DIR"/*.tf | grep -vE ':0$' | wc -l`, where the glob made
# `-r` inert (subdirectories like modules/ were never scanned) and the count was of FILES — so
# two assignments inside zot-registry.tf read as "exactly one".
decls=$(git -C "$REPO_ROOT" grep -chE '^[[:space:]]*registry_rationale_strip[[:space:]]*=' -- '*.tf' 2>/dev/null | paste -sd+ - | bc 2>/dev/null || echo 0)
if [ "$decls" = "1" ]; then
  pass "registry_rationale_strip is declared exactly once repo-wide (in .tf)"
else
  fail "registry_rationale_strip declared exactly once repo-wide" "found $decls assignments — a second copy re-opens the divergence #7299 was filed against"
fi

# --- 9-16: fail-closed arms (mutate a sandbox, require the named exit) -------------------
#
# OWNING TRAP (ADR-129). Nothing else removes these if the script dies between allocation and
# cleanup, and /tmp is a machine-global tmpfs shared by parallel worktrees.
#
# sandbox() is invoked as `d=$(sandbox)`, i.e. in a SUBSHELL, so an append INSIDE it would be
# discarded and the trap would own nothing. Its only contract is therefore stdout; the CALLER
# appends in parent scope. This is the shape lint-trap-tempfile-ownership names as the fix.
SANDBOXES=()
cleanup_sandboxes() {
  [ "${#SANDBOXES[@]}" -gt 0 ] && rm -rf "${SANDBOXES[@]}"
  return 0
}
trap cleanup_sandboxes EXIT INT TERM HUP

sandbox() {
  local d
  d=$(mktemp -d -t regbudget-test.XXXXXXXX) || return 1
  cp "$SCRIPT" "$DIR/zot-registry.tf" "$DIR/cloud-init-registry.yml" "$d/" || { rm -rf "$d"; return 1; }
  printf '%s' "$d"
}

# Each arm: mutate, ASSERT THE MUTATION LANDED (an edit that silently no-ops reports the
# baseline, which is indistinguishable from a pass), then require the specific exit code.
run_arm() {
  local label="$1" mutate="$2" want_rc="$3" verify="$4"
  local d
  d=$(sandbox) || { fail "sandbox setup ($label)" "mktemp/cp failed"; return; }
  SANDBOXES+=("$d")
  ( cd "$d" && eval "$mutate" ) >/dev/null 2>&1
  if ( cd "$d" && eval "$verify" ) >/dev/null 2>&1; then
    pass "mutation landed ($label)"
  else
    fail "mutation landed ($label)" "the sandbox edit did not apply — the arm below would be vacuous"
    return
  fi
  bash "$d/registry-userdata-budget.sh" --json >/dev/null 2>&1
  local got=$?
  if [ "$got" -eq "$want_rc" ]; then
    pass "$label fails closed with exit $want_rc"
  else
    fail "$label fails closed" "exit=$got (expected $want_rc)"
  fi
}

run_arm "missing strip declaration" \
  "grep -vE '^[[:space:]]*registry_rationale_strip[[:space:]]*=' zot-registry.tf > tf.new && mv tf.new zot-registry.tf" \
  2 \
  "! grep -qE '^[[:space:]]*registry_rationale_strip[[:space:]]*=' zot-registry.tf"

run_arm "duplicated strip declaration" \
  "awk '{print} /^[[:space:]]*registry_rationale_strip[[:space:]]*=/ && !d {print; d=1}' zot-registry.tf > tf.new && mv tf.new zot-registry.tf" \
  2 \
  "[ \"\$(grep -cE '^[[:space:]]*registry_rationale_strip[[:space:]]*=' zot-registry.tf)\" -ge 2 ]"

# THE ARM THE FIRST REVISION LACKED. Arms above mutate the DECLARATION; this one mutates the
# USAGE. Unwiring `replace(` leaves the local orphaned — terraform accepts that silently and
# `validate` stays green — while production reverts to storing the unstripped 36,404 B payload.
# A script that reads only the declaration reports 9,408 B and exit 0 on that tree.
run_arm "strip declared but NOT applied at user_data" \
  "sed -i 's/base64gzip(replace(templatefile(/base64gzip((templatefile(/' zot-registry.tf" \
  2 \
  "! grep -q 'base64gzip(replace(templatefile(' zot-registry.tf"

# A strip that eats EVERYTHING passes every shape gate (slash-delimited, (?m), has ^) and
# produces the best-looking report in the file: base64gzip("") is 40 chars, i.e. maximum
# headroom. The host would boot dark — #cloud-config stripped, LUKS locked, zot never started.
run_arm "over-broad strip eats the whole payload" \
  "sed -i 's|registry_rationale_strip = .*|registry_rationale_strip = \"/(?m)^.*\\\\n/\"|' zot-registry.tf" \
  2 \
  "grep -q 'registry_rationale_strip = \"/(?m)\\^\\.\\*' zot-registry.tf"

# --- non-vacuity ------------------------------------------------------------------------
if [ "$checks" -ne "$EXPECTED_CHECKS" ]; then
  echo "[FAIL] suite ran $checks checks, expected exactly $EXPECTED_CHECKS — an arm was skipped, added without moving EXPECTED_CHECKS, or had its failure swallowed" >&2
  fails=$((fails + 1))
fi

echo "registry-userdata-budget.test: $checks checks, $fails failed"
[ "$fails" -eq 0 ] || exit 1
