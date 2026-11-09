#!/usr/bin/env node
// Egress injector spike (#12517): the outcome floor (Guard 3) and the verdict, shared by the suite and print-verdict.sh.
//
// Input: the raw results JSON `{ verdict?, records: [{criterion, verdict, observation?, reason?}, ...] }`.
//   GO            criteria 1-9 all pass, each backed by a positive observation
//   NO-GO         every criterion 1-9 has a measured verdict and at least one fails (exit 0, CTO R3)
//   INCONCLUSIVE  any criterion missing or unmeasurable, an unknown id or verdict value, a pass with no observation,
//                 or a stored top-level verdict that disagrees with the records (exit 1)
// The floor counts DISTINCT criterion ids, never lines. A measured failure of criterion 2 or 5 is F1 evidence
// (flip fact F1 holds) even when the overall verdict is INCONCLUSIVE.
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

export const CRITERIA = [1, 2, 3, 4, 5, 6, 7, 8, 9];
const F1_CRITERIA = new Set([2, 5]);
const RANK = { pass: 0, unmeasurable: 1, fail: 2 };

export function computeVerdict(results) {
  const records = Array.isArray(results?.records) ? results.records : [];
  const harness = [];
  const best = new Map(); // criterion -> { verdict, reason }
  for (const r of records) {
    const id = r?.criterion;
    if (!CRITERIA.includes(id)) {
      harness.push(`unknown-criterion:${String(id)}`);
      continue;
    }
    let v = r.verdict;
    let reason = r.reason;
    if (!(v in RANK)) {
      harness.push(`unknown-verdict:${id}`);
      v = "unmeasurable";
      reason = reason ?? "unknown-verdict-value";
    }
    if (v === "pass" && !(typeof r.observation === "string" && r.observation.trim() !== "")) {
      v = "unmeasurable";
      reason = "no-positive-observation";
    }
    if (v === "unmeasurable" && !reason) reason = "unrecorded";
    const prior = best.get(id);
    if (!prior || RANK[v] > RANK[prior.verdict]) best.set(id, { verdict: v, reason });
  }

  const missing = CRITERIA.filter((c) => !best.has(c));
  const unmeasurable = CRITERIA.filter((c) => best.get(c)?.verdict === "unmeasurable").map((c) => ({ criterion: c, reason: best.get(c).reason }));
  const failed = CRITERIA.filter((c) => best.get(c)?.verdict === "fail");
  const f1Holds = failed.some((c) => F1_CRITERIA.has(c));

  let verdict;
  if (missing.length || unmeasurable.length || harness.length) verdict = "INCONCLUSIVE";
  else verdict = failed.length ? "NO-GO" : "GO";

  const stored = results?.verdict;
  if (stored !== undefined && stored !== verdict) {
    harness.push(`stored-verdict-mismatch:${String(stored)}`);
    verdict = "INCONCLUSIVE";
  }
  return { verdict, exitCode: verdict === "INCONCLUSIVE" ? 1 : 0, missing, unmeasurable, failed, f1Holds, harness };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const file = process.argv[2];
  let v;
  try {
    v = computeVerdict(JSON.parse(readFileSync(file, "utf8")));
  } catch (err) {
    console.log("verdict=INCONCLUSIVE");
    console.error(`verdict.mjs: cannot read ${file}: ${err?.message ?? err}`);
    process.exit(1);
  }
  console.log(`verdict=${v.verdict}`);
  if (v.missing.length) console.error(`missing criteria: ${v.missing.join(",")}`);
  for (const u of v.unmeasurable) console.error(`unmeasurable criterion ${u.criterion}: ${u.reason}`);
  if (v.failed.length) console.error(`failed criteria: ${v.failed.join(",")}${v.f1Holds ? " (F1 holds)" : ""}`);
  for (const h of v.harness) console.error(`harness: ${h}`);
  process.exit(v.exitCode);
}
