#!/usr/bin/env bash
# Deterministic unit test for the PURE verdict engine (scripts/verdict.cjs).
# ZERO live API — every input is a recorded normalized-results fixture.
#
# Normalized results shape (the seam the orchestrator wires compound/heal-skill to):
#   currentResults, candidateResults : Array<{ task_id: string, correct: boolean }>
#     — one entry per model×repeat sample per corpus task.
#   targetTask : { task_id }  — the row whose candidate samples must pass (>= 0.5).
#   opts : { epsilon?, targetThreshold=0.5 }  — epsilon default = 1/(#distinct corpus task_ids).
#
# Cases (AC2): (a) accept, (b) reject-corpus-regress, (c) reject-target-fail,
#              (d) epsilon-boundary (inclusive == not-regressed).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$HERE/.." && pwd)"
VERDICT="$SKILL_DIR/scripts/verdict.cjs"
export SKILL_DIR

node -e "$(cat <<'EOF'
const assert = require("node:assert");
const path = require("node:path");
const { computeVerdict } = require(path.join(process.env.SKILL_DIR, "scripts", "verdict.cjs"));

let fails = 0;
function check(label, fn) {
  try { fn(); console.log("ok   [" + label + "]"); }
  catch (e) { console.log("FAIL [" + label + "]: " + e.message); fails++; }
}

// Helper: N samples of a task with `c` correct, rest incorrect.
function samples(task_id, total, correct) {
  const out = [];
  for (let i = 0; i < total; i++) out.push({ task_id, correct: i < correct });
  return out;
}

const TARGET = { task_id: "T" };

// --- (a) accept: corpus flat (0.75 -> 0.75), target passes (1.0). epsilon = 1/4 = 0.25
check("accept: improve target, corpus flat", () => {
  const corpusCur = [...samples("t1",1,1), ...samples("t2",1,1), ...samples("t3",1,1), ...samples("t4",1,0)];
  const corpusCand = [...samples("t1",1,1), ...samples("t2",1,1), ...samples("t3",1,1), ...samples("t4",1,0)];
  const cur = [...corpusCur, ...samples("T",3,1)];
  const cand = [...corpusCand, ...samples("T",3,3)];
  const v = computeVerdict(cur, cand, TARGET, {});
  assert.strictEqual(v.epsilon, 0.25, "epsilon default = 1/4");
  assert.strictEqual(v.corpus_regressed, false);
  assert.strictEqual(v.target_task_passes, true);
  assert.strictEqual(v.accept, true);
  assert.ok(Array.isArray(v.per_task));
});

// --- (b) reject: corpus regresses beyond epsilon (1.0 -> 0.25), target passes
check("reject: corpus regresses beyond epsilon", () => {
  const cur = [...samples("t1",1,1), ...samples("t2",1,1), ...samples("t3",1,1), ...samples("t4",1,1), ...samples("T",1,1)];
  const cand = [...samples("t1",1,1), ...samples("t2",1,0), ...samples("t3",1,0), ...samples("t4",1,0), ...samples("T",1,1)];
  const v = computeVerdict(cur, cand, TARGET, {});
  assert.strictEqual(v.corpus_regressed, true);
  assert.strictEqual(v.accept, false);
});

// --- (c) reject: target task fails (<0.5), corpus flat
check("reject: target task fails (<0.5)", () => {
  const corpus = [...samples("t1",1,1), ...samples("t2",1,1), ...samples("t3",1,1), ...samples("t4",1,0)];
  const cur = [...corpus, ...samples("T",3,2)];
  const cand = [...corpus, ...samples("T",3,1)]; // 1/3 = 0.333 < 0.5
  const v = computeVerdict(cur, cand, TARGET, {});
  assert.strictEqual(v.corpus_regressed, false);
  assert.strictEqual(v.target_task_passes, false);
  assert.strictEqual(v.accept, false);
});

// --- (d) epsilon-boundary: candidate exactly at current_rate - epsilon => NOT regressed
check("epsilon-boundary inclusive == not regressed", () => {
  // current corpus rate = 1.0, epsilon = 0.25, candidate corpus = 0.75 exactly.
  const cur = [...samples("t1",1,1), ...samples("t2",1,1), ...samples("t3",1,1), ...samples("t4",1,1), ...samples("T",1,1)];
  const cand = [...samples("t1",1,1), ...samples("t2",1,1), ...samples("t3",1,1), ...samples("t4",1,0), ...samples("T",1,1)];
  const v = computeVerdict(cur, cand, TARGET, {});
  assert.strictEqual(v.current_rate, 1.0);
  assert.strictEqual(v.candidate_rate, 0.75);
  assert.strictEqual(v.corpus_regressed, false, "boundary is inclusive: == is not a regression");
  assert.strictEqual(v.accept, true);
});

// --- (e) reject: corpus below the absolute trust floor (both arms degraded) ---
// current corpus rate = 0.25 (< MIN_TRUSTED_CORPUS_RATE 0.5); candidate flat at 0.25 so
// there is no *relative* regression, and the target passes — but the baseline is too
// degraded to trust, so accept must be forced false.
check("reject: corpus below trust floor (both arms degraded)", () => {
  const corpus = [...samples("t1",1,1), ...samples("t2",1,0), ...samples("t3",1,0), ...samples("t4",1,0)]; // 0.25
  const cur = [...corpus, ...samples("T",3,3)];
  const cand = [...corpus, ...samples("T",3,3)];
  const v = computeVerdict(cur, cand, TARGET, {});
  assert.strictEqual(v.current_rate, 0.25);
  assert.strictEqual(v.corpus_regressed, false, "flat corpus is not a relative regression");
  assert.strictEqual(v.target_task_passes, true);
  assert.strictEqual(v.corpus_untrustworthy, true);
  assert.strictEqual(v.min_trusted_corpus_rate, 0.5);
  assert.strictEqual(v.accept, false, "untrustworthy baseline forces accept=false");
});

// --- malformed input throws (fail-closed) ---
check("throws on non-array currentResults", () => {
  assert.throws(() => computeVerdict(null, [], TARGET, {}));
});
check("throws on entry missing correct boolean", () => {
  assert.throws(() => computeVerdict([{ task_id: "t1" }], [{ task_id: "t1", correct: true }], TARGET, {}));
});
check("throws on missing targetTask.task_id", () => {
  const ok = [...samples("t1",1,1), ...samples("T",1,1)];
  assert.throws(() => computeVerdict(ok, ok, {}, {}));
});
check("throws when target has no candidate samples", () => {
  const cur = [...samples("t1",1,1), ...samples("T",1,1)];
  const cand = [...samples("t1",1,1)]; // no T
  assert.throws(() => computeVerdict(cur, cand, TARGET, {}));
});

if (fails > 0) { console.log("verdict: " + fails + " assertion(s) failed"); process.exit(1); }
console.log("verdict: all assertions passed");
EOF
)"
