#!/usr/bin/env bash
# Deterministic unit test for the eval-gate.cjs orchestrator — NO API.
# Covers the three code paths that never call promptfoo:
#   --check     gated-source lookup (true/false)
#   --dry-run   skill-arm-only API-cost disclosure (no API call)
#   no-op       candidate block == current block => {accept:true, "no gated-block change"}
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$SKILL_DIR/../../../.." && pwd)"
GATE="$SKILL_DIR/scripts/eval-gate.cjs"
fails=0

pass() { echo "ok   [$1]"; }
fail() { echo "FAIL [$1]: $2"; fails=$((fails + 1)); }

jqget() { node -e 'const o=JSON.parse(require("fs").readFileSync(0,"utf8"));process.stdout.write(String(o[process.argv[1]]))' "$1"; }

cd "$REPO_ROOT"

# --- --check: a gated source returns gated:true + its target/block_id ---
out=$(node "$GATE" --check plugins/soleur/commands/go.md)
if [[ "$(echo "$out" | jqget gated)" == "true" && "$(echo "$out" | jqget target)" == "go-routing" && "$(echo "$out" | jqget block_id)" == "go-routing" ]]; then
  pass "--check gated source (go.md)"
else
  fail "--check gated source (go.md)" "got: $out"
fi

out=$(node "$GATE" --check plugins/soleur/agents/support/ticket-triage.md)
if [[ "$(echo "$out" | jqget gated)" == "true" && "$(echo "$out" | jqget target)" == "ticket-triage" ]]; then
  pass "--check gated source (ticket-triage.md)"
else
  fail "--check gated source (ticket-triage.md)" "got: $out"
fi

# --- --check: a non-gated file returns gated:false ---
out=$(node "$GATE" --check plugins/soleur/skills/eval-harness/README.md)
if [[ "$(echo "$out" | jqget gated)" == "false" ]]; then
  pass "--check non-gated file"
else
  fail "--check non-gated file" "got: $out"
fi

# --- --dry-run: prints estimate, dry_run:true, no API ---
out=$(node "$GATE" --dry-run --target go-routing --repeat 5)
if [[ "$(echo "$out" | jqget dry_run)" == "true" ]]; then
  calls=$(echo "$out" | jqget estimated_api_calls)
  # 2 (current+candidate) x 3 models x (8 corpus + 1 target) x 5 repeat = 270
  if [[ "$calls" == "270" ]]; then
    pass "--dry-run estimate (go-routing, repeat 5) = $calls"
  else
    fail "--dry-run estimate" "estimated_api_calls=$calls (want 270)"
  fi
else
  fail "--dry-run" "got: $out"
fi

# --- no-op: candidate-file is a DISTINCT copy with an unchanged block => accept, no API ---
# (must be a temp copy, not the live source — Fix 4 refuses an in-place candidate-file).
tmpcopy="$(mktemp --suffix=.md)"
trap 'rm -f "$tmpcopy"' EXIT
cp "$REPO_ROOT/plugins/soleur/commands/go.md" "$tmpcopy"
out=$(node "$GATE" --target go-routing --candidate-file "$tmpcopy")
if [[ "$(echo "$out" | jqget accept)" == "true" && "$(echo "$out" | jqget reason)" == "no gated-block change" ]]; then
  pass "no-op (unchanged block) accepts without API"
else
  fail "no-op (unchanged block)" "got: $out"
fi

# --- Fix 4: candidate-file == the live source file is refused (fail-closed) ---
out=$(node "$GATE" --target go-routing --candidate-file plugins/soleur/commands/go.md || true)
if [[ "$(echo "$out" | jqget accept)" == "false" && "$(echo "$out" | jqget error)" == *"must differ from the live source file"* ]]; then
  pass "candidate-file == live source is refused"
else
  fail "candidate-file == live source is refused" "got: $out"
fi

# --- --check: the two added gated sources resolve to their targets ---
out=$(node "$GATE" --check plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md)
if [[ "$(echo "$out" | jqget gated)" == "true" && "$(echo "$out" | jqget target)" == "lane-inference" && "$(echo "$out" | jqget block_id)" == "lane-inference" ]]; then
  pass "--check gated source (brainstorm-domain-config.md -> lane-inference)"
else
  fail "--check gated source (lane-inference)" "got: $out"
fi

out=$(node "$GATE" --check plugins/soleur/skills/incident/SKILL.md)
if [[ "$(echo "$out" | jqget gated)" == "true" && "$(echo "$out" | jqget target)" == "incident-threshold" ]]; then
  pass "--check gated source (incident/SKILL.md -> incident-threshold)"
else
  fail "--check gated source (incident-threshold)" "got: $out"
fi

# --- gate path: --dry-run resolves TARGET_RESOURCES for the new targets (no API). ---
# A missing TARGET_RESOURCES entry would die() here — so this is the load-bearing proof
# that the GATE (not just the measurement config) is actually wired for the new surfaces.
for t in lane-inference incident-threshold; do
  out=$(node "$GATE" --dry-run --target "$t" --repeat 5)
  calls=$(echo "$out" | jqget estimated_api_calls)
  # 2 (current+candidate) x 3 models x (7 corpus + 1 target) x 5 repeat = 240
  if [[ "$(echo "$out" | jqget dry_run)" == "true" && "$calls" == "240" ]]; then
    pass "--dry-run estimate ($t, repeat 5) = $calls"
  else
    fail "--dry-run ($t)" "got: $out"
  fi
done

# --- registry-coverage: every gated target is wired in BOTH per-target maps ---
# A target present in gated-skills.json but missing from TARGET_RESOURCES ships the gate
# DORMANT (--check says gated:true while --target/--dry-run die fail-closed). This guard
# makes that drift fail CI for any future target, not just these two.
if node -e '
  const reg = require(process.argv[1]);
  const { TARGET_CONFIG } = require(process.argv[2]);
  const { TARGET_RESOURCES } = require(process.argv[3]);
  const missing = [];
  for (const e of reg) {
    if (!TARGET_CONFIG[e.target]) missing.push(e.target + " (gen-skill-prompt TARGET_CONFIG)");
    if (!TARGET_RESOURCES[e.target]) missing.push(e.target + " (eval-gate TARGET_RESOURCES)");
  }
  if (missing.length) { process.stderr.write("uncovered targets: " + missing.join(", ") + "\n"); process.exit(1); }
' "$SKILL_DIR/gated-skills.json" "$SKILL_DIR/scripts/gen-skill-prompt.cjs" "$SKILL_DIR/scripts/eval-gate.cjs" 2>/tmp/eval-gate-coverage.err; then
  pass "registry-coverage: every target in TARGET_CONFIG and TARGET_RESOURCES"
else
  fail "registry-coverage" "$(cat /tmp/eval-gate-coverage.err)"
fi

if [[ "$fails" -gt 0 ]]; then
  echo "eval-gate: $fails assertion(s) failed"
  exit 1
fi
echo "eval-gate: all assertions passed"
