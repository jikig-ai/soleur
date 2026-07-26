#!/usr/bin/env bash
# Test: apps/web-platform/infra/run-registered-suites.sh
#
# Pins the runner's OWN logic — derivation from the workflow, the fail-closed
# zero-guard, and the orphan scan — via `--list`, so none of it requires the
# ~25-minute full run. The runner exists because a green test-all was mistaken
# for infra coverage (#6730); a runner whose own correctness were merely
# asserted would reproduce that defect one level up.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1
SUT="apps/web-platform/infra/run-registered-suites.sh"
WF=".github/workflows/infra-validation.yml"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── T1: the script exists and is executable ───────────────────────────────────
if [[ -x "$SUT" ]]; then ok "T1: $SUT exists and is executable"
else no "T1: $SUT missing or not executable"; fi

# ── T2: --list derives the real registered set and runs NOTHING ───────────────
# Bound the runtime: if --list ever started executing suites this would blow the
# timeout rather than quietly taking 25 minutes.
OUT="$(timeout 60 bash "$SUT" --list 2>&1)"; rc=$?
if (( rc == 0 )); then ok "T2a: --list exits 0"
else no "T2a: --list exited $rc (60s timeout = it executed suites instead of listing)"; fi

# Count ONLY the derived section — the orphan report below it also prints
# two-space-indented suite paths, so a whole-output grep double-counts (it read
# 79 = 70 derived + 9 orphans on the first run of this test).
DERIVED=$(printf '%s\n' "$OUT" \
  | awk '/^Derived [0-9]+ registered infra suite/{f=1;next} /^$/{f=0} f' \
  | grep -cE '^  apps/web-platform/infra/[A-Za-z0-9._-]+\.test\.sh$')
EXPECTED=$(grep -oE 'run: bash apps/web-platform/infra/[A-Za-z0-9._-]+\.test\.sh' "$WF" \
  | sed 's/run: bash //' | sort -u | wc -l)
# The header's own count must agree with the lines it introduces — otherwise a
# future edit could print a plausible header over a truncated list.
HEADER_N=$(printf '%s\n' "$OUT" | sed -nE 's/^Derived ([0-9]+) registered infra suite.*/\1/p')
# Equality against the workflow, not a hardcoded count: the whole point of
# deriving is that runner and CI cannot drift, so the test asserts the identity
# rather than a number that would need editing every time a suite is added.
if (( DERIVED > 0 )) && (( DERIVED == EXPECTED )); then
  ok "T2b: --list derives exactly the workflow's registered set ($DERIVED)"
else
  no "T2b: --list derived $DERIVED, workflow registers $EXPECTED"
fi

if [[ "$HEADER_N" == "$DERIVED" ]]; then
  ok "T2d: the header count matches the list it introduces ($HEADER_N)"
else
  no "T2d: header says $HEADER_N but $DERIVED suites are listed"
fi

if printf '%s\n' "$OUT" | grep -qE '^(PASS|RED) '; then
  no "T2c: --list executed suites (found PASS/RED lines)"
else
  ok "T2c: --list executed nothing"
fi

# ── T3: zero-derivation is FATAL, not a silent green ──────────────────────────
# The defect this guards: a workflow whose 'run: bash …' shape changed derives
# zero suites, and an unguarded runner prints "0 passed, 0 failed" and exits 0 —
# a false green that looks exactly like success.
printf 'jobs:\n  noop:\n    steps:\n      - run: echo nothing here\n' > "$TMP/empty.yml"
OUT_ZERO="$(INFRA_WF="$TMP/empty.yml" bash "$SUT" --list 2>&1)"; rc_zero=$?
if (( rc_zero == 2 )); then ok "T3a: zero-derivation exits 2"
else no "T3a: zero-derivation exited $rc_zero, expected 2"; fi

if printf '%s\n' "$OUT_ZERO" | grep -q 'derived ZERO suites'; then
  ok "T3b: zero-derivation names the cause"
else
  no "T3b: zero-derivation did not explain itself: $OUT_ZERO"
fi

if printf '%s\n' "$OUT_ZERO" | grep -qE '0 (passed|failed)'; then
  no "T3c: zero-derivation printed a pass/fail summary (reads as success)"
else
  ok "T3c: zero-derivation prints no pass/fail summary"
fi

# ── T4: a missing workflow is FATAL, not an empty run ─────────────────────────
rc_missing=0
INFRA_WF="$TMP/does-not-exist.yml" bash "$SUT" --list >/dev/null 2>&1 || rc_missing=$?
if (( rc_missing == 2 )); then ok "T4: missing workflow exits 2"
else no "T4: missing workflow exited $rc_missing, expected 2"; fi

# ── T5: the orphan scan reports suites nothing references ─────────────────────
# Asserted against a freshly-created orphan rather than a hardcoded filename, so
# the test does not go red the moment someone legitimately registers or deletes
# one of today's orphans.
ORPHAN="apps/web-platform/infra/zzz-run-registered-suites-fixture.test.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$ORPHAN"
git add -N "$ORPHAN" >/dev/null 2>&1   # git ls-files must see it
OUT_ORPH="$(timeout 60 bash "$SUT" --list 2>&1)"
git rm -q --cached "$ORPHAN" >/dev/null 2>&1 || true
rm -f "$ORPHAN"

if printf '%s\n' "$OUT_ORPH" | grep -qF "zzz-run-registered-suites-fixture.test.sh"; then
  ok "T5a: orphan scan reports an unreferenced suite"
else
  no "T5a: orphan scan missed a suite nothing references"
fi

if printf '%s\n' "$OUT_ORPH" | grep -q 'referenced by NO workflow or script'; then
  ok "T5b: orphan scan explains what the list means"
else
  no "T5b: orphan scan printed no explanation"
fi

echo ""
echo "=== run-registered-suites: ${pass} passed, ${fail} failed ==="
(( fail == 0 ))
