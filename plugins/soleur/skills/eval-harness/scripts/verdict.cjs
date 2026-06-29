// verdict.cjs — PURE accept/reject computation for a gated classifier-skill edit.
//
// NO I/O, NO shell-out, NO LLM. The only deterministic seam in the gate: it consumes
// already-scored promptfoo results and decides whether a candidate block edit is safe
// to apply. The orchestrator (eval-gate.cjs) runs promptfoo and normalizes its JSON
// into the shape below; the verdict math lives here so it is unit-testable with zero
// API spend (AC2).
//
// Normalized results shape
// ------------------------
//   currentResults, candidateResults : Array<{ task_id: string, correct: boolean }>
//     One entry per model×repeat sample per corpus task. "current" = the block on disk
//     today; "candidate" = the edited block. The target task's samples are included in
//     these arrays (tagged with targetTask.task_id) and are SEPARATED OUT internally:
//       - corpus rate excludes the target task_id (avoids double-counting the row whose
//         pass we test independently);
//       - target_task_passes uses ONLY the candidate samples for targetTask.task_id.
//   targetTask : { task_id }  — the row whose candidate samples must pass.
//   opts : { epsilon?, targetThreshold? }
//     epsilon default = 1 / (number of distinct corpus task_ids)  [one-task-equivalent].
//     targetThreshold default = 0.5.
//
// Decision
// --------
//   current_rate       = pooled mean correctness over current corpus samples (ex-target)
//   candidate_rate     = pooled mean correctness over candidate corpus samples (ex-target)
//   corpus_regressed   = candidate_rate < current_rate - epsilon   (strict < ; boundary
//                        equality is NOT a regression — inclusive)
//   target_task_passes = pooled mean correctness of candidate target samples >= targetThreshold
//   accept             = !corpus_regressed && target_task_passes
//
// Fail-closed: malformed input throws (the orchestrator treats a throw as NOT accept).
"use strict";

function assertResults(results, name) {
  if (!Array.isArray(results)) {
    throw new TypeError(`computeVerdict: ${name} must be an array`);
  }
  for (const r of results) {
    if (!r || typeof r !== "object") {
      throw new TypeError(`computeVerdict: ${name} entry must be an object`);
    }
    if (typeof r.task_id !== "string" || r.task_id === "") {
      throw new TypeError(`computeVerdict: ${name} entry missing string task_id`);
    }
    if (typeof r.correct !== "boolean") {
      throw new TypeError(`computeVerdict: ${name} entry .correct must be a boolean`);
    }
  }
}

// poolRate(samples): mean correctness (1.0/0.0 per sample). null when empty.
function poolRate(samples) {
  if (samples.length === 0) return null;
  const correct = samples.reduce((acc, s) => acc + (s.correct ? 1 : 0), 0);
  return correct / samples.length;
}

function distinctTaskIds(results) {
  return [...new Set(results.map((r) => r.task_id))];
}

function computeVerdict(currentResults, candidateResults, targetTask, opts) {
  assertResults(currentResults, "currentResults");
  assertResults(candidateResults, "candidateResults");
  if (!targetTask || typeof targetTask.task_id !== "string" || targetTask.task_id === "") {
    throw new TypeError("computeVerdict: targetTask must have a string task_id");
  }
  const targetId = targetTask.task_id;
  const targetThreshold =
    opts && typeof opts.targetThreshold === "number" ? opts.targetThreshold : 0.5;

  const curCorpus = currentResults.filter((r) => r.task_id !== targetId);
  const candCorpus = candidateResults.filter((r) => r.task_id !== targetId);
  const candTarget = candidateResults.filter((r) => r.task_id === targetId);

  if (curCorpus.length === 0 || candCorpus.length === 0) {
    throw new Error("computeVerdict: no corpus samples (excluding the target task) to compare");
  }
  if (candTarget.length === 0) {
    throw new Error(
      `computeVerdict: no candidate samples for target task ${JSON.stringify(targetId)}`,
    );
  }

  // epsilon default = one-task-equivalent over the distinct corpus tasks.
  const corpusTaskCount = distinctTaskIds(curCorpus).length;
  const epsilon =
    opts && typeof opts.epsilon === "number" ? opts.epsilon : 1 / corpusTaskCount;

  const current_rate = poolRate(curCorpus);
  const candidate_rate = poolRate(candCorpus);
  const target_rate = poolRate(candTarget);

  const corpus_regressed = candidate_rate < current_rate - epsilon;
  const target_task_passes = target_rate >= targetThreshold;
  const accept = !corpus_regressed && target_task_passes;

  // per_task breakdown over the union of corpus + target task ids.
  const allIds = [...new Set([...distinctTaskIds(currentResults), ...distinctTaskIds(candidateResults)])];
  const per_task = allIds.map((task_id) => ({
    task_id,
    is_target: task_id === targetId,
    current_rate: poolRate(currentResults.filter((r) => r.task_id === task_id)),
    candidate_rate: poolRate(candidateResults.filter((r) => r.task_id === task_id)),
  }));

  return {
    accept,
    corpus_regressed,
    target_task_passes,
    current_rate,
    candidate_rate,
    target_rate,
    epsilon,
    target_threshold: targetThreshold,
    per_task,
  };
}

module.exports = { computeVerdict };
