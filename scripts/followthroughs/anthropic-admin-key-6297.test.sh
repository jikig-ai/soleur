#!/usr/bin/env bash
# Fixture tests for the #6297 follow-through probe.
#
# The load-bearing arm is CONTAMINATION: `betterstack-query.sh --grep` compiles
# to an unanchored `raw LIKE '%…%'`, and GitHub webhook payloads ship into the
# same Better Stack source from the same app container — so a probe that
# matched by substring could PASS on a webhook echo of the PR/issue body that
# merely QUOTES the marker, auto-closing #6297 while the key is still unminted.
# Test 5 asserts it does not, and Test 6 MUTATES the guard out to prove that
# arm is not vacuous.
set -uo pipefail

PROBE_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/anthropic-admin-key-6297.sh"
fails=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; fails=$((fails + 1)); }

# Build a sandbox git repo with a stubbed betterstack-query.sh that replays a
# fixture file, so the probe runs its real logic against synthetic rows.
# `mktemp -d` (not a name derived from this script) — parallel worktrees are
# this repo's documented workflow and a fixed name would collide.
make_sandbox() {
  local fixture="$1" probe="${2:-$PROBE_SRC}"
  local d
  d=$(mktemp -d -t ft6297.XXXXXXXX)
  git -C "$d" init -q 2>/dev/null
  mkdir -p "$d/scripts/followthroughs"
  cp "$probe" "$d/scripts/followthroughs/anthropic-admin-key-6297.sh"
  chmod +x "$d/scripts/followthroughs/anthropic-admin-key-6297.sh"
  cp "$fixture" "$d/rows.jsonl"
  cat > "$d/scripts/betterstack-query.sh" <<'STUB'
#!/usr/bin/env bash
cat "$(git rev-parse --show-toplevel)/rows.jsonl"
STUB
  chmod +x "$d/scripts/betterstack-query.sh"
  echo "$d"
}

# Wrap a bare pino log line into the JSONEachRow envelope the query emits
# (`raw` is a JSON *string*, so every inner quote is escaped on stdout).
envelope() { jq -c -n --arg raw "$1" '{dt:"2026-07-20 06:17:00", raw:$raw}'; }

run_probe() {
  local dir="$1"
  ( cd "$dir" && env \
      BETTERSTACK_QUERY_HOST=h \
      BETTERSTACK_QUERY_USERNAME=u \
      BETTERSTACK_QUERY_PASSWORD=p \
      bash scripts/followthroughs/anthropic-admin-key-6297.sh >/dev/null 2>&1 )
  echo $?
}

OK_ROW='{"level":40,"component":"claude-cost","SOLEUR_CLAUDE_COST_DAILY":true,"status":"ok","date":"2026-07-19","cost_usd":12.5}'
DARK_ROW='{"level":40,"component":"claude-cost","SOLEUR_CLAUDE_COST_DAILY":true,"status":"key-missing","date":"2026-07-19","days_since_first_dark":10}'
# A realistic webhook echo: the marker text appears ONLY as nested string
# content of a payload field. Top-level `component` is the webhook producer.
ECHO_ROW='{"level":30,"component":"inngest","msg":"github webhook","body":"Fix: the probe requires \"SOLEUR_CLAUDE_COST_DAILY\":true and \"component\":\"claude-cost\" with \"status\":\"ok\" to pass."}'
# The ADVERSARIAL echo: everything the PASS path reads is present and correct at
# TOP LEVEL except `component`. This isolates the component guard as the single
# discriminator, so the mutation in test 6 proves that guard specifically. The
# realistic fixture above cannot prove it — it is also rejected for lacking a
# top-level `status`, so it would pass the test even with the guard removed.
ECHO_ADVERSARIAL='{"level":30,"component":"inngest","SOLEUR_CLAUDE_COST_DAILY":true,"status":"ok","msg":"webhook echo of the PR body"}'

echo "== #6297 follow-through probe fixtures =="

# 1 — healthy report → PASS
f=$(mktemp -t ft.XXXXXXXX); envelope "$OK_ROW" > "$f"
d=$(make_sandbox "$f"); rc=$(run_probe "$d")
[[ "$rc" == "0" ]] && pass "healthy ok row → exit 0" || fail "healthy ok row → expected 0, got $rc"

# 2 — still un-minted → TRANSIENT (never PASS, never FAIL)
f=$(mktemp -t ft.XXXXXXXX); envelope "$DARK_ROW" > "$f"
d=$(make_sandbox "$f"); rc=$(run_probe "$d")
[[ "$rc" == "2" ]] && pass "key-missing only → exit 2" || fail "key-missing only → expected 2, got $rc"

# 3 — regression: worked, then stopped → FAIL (this is what makes the
#     sweeper's closed-set reopen path reachable rather than structurally inert)
f=$(mktemp -t ft.XXXXXXXX); { envelope "$OK_ROW"; envelope "$DARK_ROW"; } > "$f"
d=$(make_sandbox "$f"); rc=$(run_probe "$d")
[[ "$rc" == "1" ]] && pass "ok-then-key-missing → exit 1" || fail "ok-then-key-missing → expected 1, got $rc"

# 4 — producer silent → TRANSIENT (positive-liveness rule: zero rows is never PASS)
f=$(mktemp -t ft.XXXXXXXX); : > "$f"
d=$(make_sandbox "$f"); rc=$(run_probe "$d")
[[ "$rc" == "2" ]] && pass "zero producer rows → exit 2" || fail "zero rows → expected 2, got $rc"

# 5 — CONTAMINATION (P0): a webhook echo quoting every literal, including
#     "status":"ok", must NOT close the issue.
f=$(mktemp -t ft.XXXXXXXX); envelope "$ECHO_ROW" > "$f"
d=$(make_sandbox "$f"); rc=$(run_probe "$d")
[[ "$rc" == "2" ]] && pass "webhook echo quoting the marker → exit 2 (not closed)" \
  || fail "webhook echo → expected 2, got $rc (ECHO WOULD FALSE-CLOSE #6297)"

# 5b — adversarial echo: correct at top level in every field the PASS path
#      reads, except `component`. Only the structural guard rejects this.
f=$(mktemp -t ft.XXXXXXXX); envelope "$ECHO_ADVERSARIAL" > "$f"
d=$(make_sandbox "$f"); rc=$(run_probe "$d")
[[ "$rc" == "2" ]] && pass "adversarial echo (wrong component only) → exit 2" \
  || fail "adversarial echo → expected 2, got $rc (component guard not enforced)"

# 6 — MUTATION: prove 5b is non-vacuous. Strip the structural component guard;
#     the adversarial fixture must then wrongly PASS (exit 0). If it still
#     exits 2, the guard is not what is rejecting it and 5b proves nothing.
MUT=$(mktemp -t ft-mut.XXXXXXXX.sh)
sed 's/and .component == "claude-cost"//' "$PROBE_SRC" > "$MUT"
if ! grep -q 'select(.SOLEUR_CLAUDE_COST_DAILY == true )' "$MUT"; then
  fail "mutation did not apply — the jq selector text drifted; 5b is unproven"
else
  f=$(mktemp -t ft.XXXXXXXX); envelope "$ECHO_ADVERSARIAL" > "$f"
  d=$(make_sandbox "$f" "$MUT"); rc=$(run_probe "$d")
  [[ "$rc" == "0" ]] && pass "mutation makes the adversarial echo PASS (guard is load-bearing)" \
    || fail "mutation did NOT flip 5b (got $rc) — the component guard is vacuous"
fi

echo
if (( fails > 0 )); then echo "FAILED: $fails"; exit 1; fi
echo "All fixtures passed."
