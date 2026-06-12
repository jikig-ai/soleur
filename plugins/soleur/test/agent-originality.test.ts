// Agent-originality CI gate.
//
// Re-implemented (methodology only) from
// msitarzewski/agency-agents/scripts/check-agent-originality.sh (MIT,
// Copyright (c) 2025 msitarzewski). The upstream tool flags new agents that
// substantially duplicate an existing one (find-replace "re-skins") via
// entity-neutralized 8-word shingle Jaccard similarity, and is written in
// python3. This is a clean Bun/TS re-implementation — no python3 dependency.
//
// Deviation from upstream: upstream neutralizes a large proper-noun table
// (country/platform names) because it is a multi-market localization library
// where a swapped market name is the canonical re-skin. Soleur is NOT such a
// library, so that entity table is intentionally dropped. Neutralization here
// is minimal (lowercase + collapse non-alphanumeric to whitespace); the value
// for Soleur is catching near-duplicate agent BODIES as the roster grows.
//
// Calibration (the load-bearing decision): over the current roster, the
// highest-scoring pair is `agent-finder` ↔ `functional-discovery` at ~41.66%
// — a legitimately-distinct pair (find-agents-for-a-stack-gap vs
// check-functional-overlap) that shares `/plan`-spawned community-registry
// scaffolding, NOT a re-skin. The next-highest pair is ~15.72%. A true
// find-replace re-skin scores ~90%+. So FAIL defaults to 50% (above the
// legitimate-overlap ceiling, well below a re-skin) and WARN to 30% (the one
// ~41.66% pair logs as the living calibration record). Both are env-overridable
// via AGENT_ORIGINALITY_FAIL / AGENT_ORIGINALITY_WARN.

import { describe, test, expect } from "bun:test";
import { discoverAgents, parseComponent, getComponentName } from "./helpers";

const SHINGLE_N = 8;
const FAIL = Number(process.env.AGENT_ORIGINALITY_FAIL ?? 50) / 100;
const WARN = Number(process.env.AGENT_ORIGINALITY_WARN ?? 30) / 100;

function neutralize(text: string): string {
  return text.toLowerCase().replace(/[^a-z0-9\s]+/g, " ");
}

function shingles(text: string, n = SHINGLE_N): Set<string> {
  const words = neutralize(text).split(/\s+/).filter(Boolean);
  const out = new Set<string>();
  for (let i = 0; i + n <= words.length; i++) {
    out.add(words.slice(i, i + n).join(" "));
  }
  return out;
}

function jaccard(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 || b.size === 0) return 0;
  let inter = 0;
  for (const s of a) if (b.has(s)) inter++;
  return inter / (a.size + b.size - inter);
}

describe("Agent originality", () => {
  const agents = discoverAgents();

  test("discovers agents", () => {
    expect(agents.length).toBeGreaterThan(0);
  });

  test("no agent body substantially duplicates another", () => {
    const entries = agents.map((path) => ({
      name: getComponentName(path, "agent"),
      shingles: shingles(parseComponent(path).body),
    }));

    let worst = { score: 0, a: "", b: "" };
    const offenders: string[] = [];

    for (let i = 0; i < entries.length; i++) {
      for (let j = i + 1; j < entries.length; j++) {
        const a = entries[i];
        const b = entries[j];
        // Skip degenerate bodies shorter than one shingle window (Jaccard
        // would be 0 anyway — nothing to compare).
        if (a.shingles.size === 0 || b.shingles.size === 0) continue;

        const score = jaccard(a.shingles, b.shingles);
        if (score > worst.score) worst = { score, a: a.name, b: b.name };

        if (score >= WARN) {
          // WARN is logged, not failed — this is the living calibration record.
          // eslint-disable-next-line no-console
          console.warn(
            `[agent-originality] ${(score * 100).toFixed(2)}% similar: ` +
              `${a.name} <-> ${b.name}` +
              (score >= FAIL ? "  (>= FAIL)" : "  (>= WARN)"),
          );
        }
        if (score >= FAIL) {
          offenders.push(
            `${a.name} <-> ${b.name} = ${(score * 100).toFixed(2)}%`,
          );
        }
      }
    }

    expect(
      offenders,
      `Agent bodies at/above FAIL=${(FAIL * 100).toFixed(0)}% similarity ` +
        `(likely re-skins; make the body genuinely distinct or justify a ` +
        `threshold change): ${offenders.join("; ") || "none"}. ` +
        `Worst pair: ${worst.a} <-> ${worst.b} = ${(worst.score * 100).toFixed(2)}%.`,
    ).toEqual([]);
  });
});
