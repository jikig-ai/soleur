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
# `cq-assert-anchor-not-bare-token`). The invariant is arithmetic — stripped is far smaller
# than raw and lands under cap — so assert THAT, and assert the fail-closed arms by MUTATING
# a sandbox copy of zot-registry.tf and requiring a distinct exit code.
#
# ONE COPY. The strip expression is declared exactly once (zot-registry.tf) and EXTRACTED by
# both consumers. Test 5 pins that cardinality, so a future PR that restates the expression
# instead of extracting it fails here rather than silently re-opening the divergence.
#
# Sandbox needs only 3 files — the script reads $DIR/{zot-registry.tf,cloud-init-registry.yml}
# and nothing else — so this never copies the 5 MB infra tree.
set -uo pipefail

# /tmp is a machine-global 4 GiB tmpfs shared by parallel worktrees; a direct invocation of
# this suite (the inner loop while editing the script) would otherwise inherit it and become a
# function of another session's disk usage.
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$DIR/registry-userdata-budget.sh"
fails=0
checks=0
pass() { checks=$((checks + 1)); echo "[ok] $1"; }
fail() { checks=$((checks + 1)); fails=$((fails + 1)); echo "[FAIL] $1 — $2" >&2; }

command -v terraform >/dev/null 2>&1 || {
  echo "registry-userdata-budget.test: SKIP — terraform not on PATH" >&2
  exit 0
}

# --- 1-4: the real tree measures the STORED payload -------------------------------------
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
headroom=$(get headroom)

if [ -n "$stripped" ]; then
  pass "--json reports stripped_bytes (the render terraform actually stores)"
else
  fail "--json reports stripped_bytes" "key absent — the script is not applying local.registry_rationale_strip"
fi

# The strip removes ~51 kB of rationale prose from a ~74 kB template. Assert a LOOSE ratio
# (stripped < raw/2) rather than a byte figure, so ordinary prose churn does not red the gate
# while a strip that silently stops applying still trips it.
if [ -n "$raw" ] && [ -n "$stripped" ] && [ "$stripped" -lt $((raw / 2)) ]; then
  pass "strip is effective: stripped ($stripped B) < half of raw ($raw B)"
else
  fail "strip is effective" "raw=$raw stripped=$stripped — expected stripped < raw/2"
fi

# The plan's floor. Real headroom is ~23.4 kB; 20,000 B keeps a wide margin while still
# failing loudly if a future change eats the budget.
if [ -n "$headroom" ] && [ "$headroom" -ge 20000 ]; then
  pass "headroom ${headroom} B >= 20000 B floor (stored ${stored} B)"
else
  fail "headroom >= 20000 B floor" "headroom=$headroom stored=$stored"
fi

# --- 5: the strip expression is declared exactly once ------------------------------------
# Anchored on the ASSIGNMENT so a comment naming the local cannot satisfy it.
decls=$(grep -rcE '^[[:space:]]*registry_rationale_strip[[:space:]]*=' "$DIR"/*.tf 2>/dev/null | grep -vE ':0$' | wc -l | tr -d ' ')
if [ "$decls" = "1" ]; then
  pass "registry_rationale_strip is declared in exactly one .tf file"
else
  fail "registry_rationale_strip declared exactly once" "found assignments in $decls .tf files — a second copy re-opens the divergence #7299 was filed against"
fi

# --- 6-8: fail-closed arms (mutate a sandbox, require exit 2) ----------------------------
#
# OWNING TRAP (ADR-129). Nothing else removes these if the script dies between allocation and
# cleanup, and /tmp is a machine-global tmpfs shared by parallel worktrees — the count-shaped
# leak class that nothing currently reclaims.
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

# (a) strip assignment REMOVED -> unmeasurable, must exit 2 (never 0, never 1)
d=$(sandbox) || { fail "sandbox setup" "mktemp/cp failed"; echo "$checks checks, $fails failed"; exit 2; }
SANDBOXES+=("$d")
grep -vE '^[[:space:]]*registry_rationale_strip[[:space:]]*=' "$d/zot-registry.tf" > "$d/tf.new" && mv "$d/tf.new" "$d/zot-registry.tf"
if grep -qE '^[[:space:]]*registry_rationale_strip[[:space:]]*=' "$d/zot-registry.tf"; then
  fail "mutation landed (strip removed)" "assignment still present — the fail-closed arm below would be vacuous"
else
  pass "mutation landed (strip removed)"
  bash "$d/registry-userdata-budget.sh" --json >/dev/null 2>&1
  mrc=$?
  if [ "$mrc" -eq 2 ]; then
    pass "missing strip expression fails closed with exit 2"
  else
    fail "missing strip expression fails closed" "exit=$mrc (expected 2; 0 would silently measure the unstripped render again)"
  fi
fi
rm -rf "$d"

# (b) strip assignment DUPLICATED -> ambiguous, must exit 2
d=$(sandbox) || { fail "sandbox setup" "mktemp/cp failed"; echo "$checks checks, $fails failed"; exit 2; }
SANDBOXES+=("$d")
awk '{print} /^[[:space:]]*registry_rationale_strip[[:space:]]*=/ && !dup {print; dup=1}' \
  "$d/zot-registry.tf" > "$d/tf.new" && mv "$d/tf.new" "$d/zot-registry.tf"
dupes=$(grep -cE '^[[:space:]]*registry_rationale_strip[[:space:]]*=' "$d/zot-registry.tf")
if [ "$dupes" -ge 2 ]; then
  pass "mutation landed (strip duplicated, $dupes assignments)"
  bash "$d/registry-userdata-budget.sh" --json >/dev/null 2>&1
  mrc=$?
  if [ "$mrc" -eq 2 ]; then
    pass "duplicate strip expression fails closed with exit 2"
  else
    fail "duplicate strip expression fails closed" "exit=$mrc (expected 2; an ambiguous declaration must not be guessed at)"
  fi
else
  fail "mutation landed (strip duplicated)" "only $dupes assignments after mutation"
fi
rm -rf "$d"

# --- non-vacuity ------------------------------------------------------------------------
if [ "$checks" -lt 8 ]; then
  echo "[FAIL] suite ran only $checks checks — expected >= 8; a short run means an arm was skipped, not that it passed" >&2
  fails=$((fails + 1))
fi

echo "registry-userdata-budget.test: $checks checks, $fails failed"
[ "$fails" -eq 0 ] || exit 1
