import { describe, test, expect } from "bun:test";
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { resolve, join } from "node:path";
import { PLUGIN_ROOT } from "./helpers";

// Standing pin-allowlist gate (#3791, ADR-051).
//
// The Model Selection Policy (plugins/soleur/AGENTS.md) allows workflow
// scripts to pin `opts.model` ONLY at mechanical steps. This test converts
// that prose policy into a CI-blocking invariant: the exact set of
// (workflow file, label, model) pins below is the allowlist. A future PR
// pinning a judgment step (review dimensions, verify/concur, synthesis,
// resolvers, one-shot, agent-native-audit scoring) fails here and must
// deliberately edit this allowlist — a clo-attestation-class change.
//
// Precedents for the drift-guard shape: trigger-cron-allowlist-parity,
// seo-aeo-drift-guard.

const SKILLS_DIR = resolve(PLUGIN_ROOT, "skills");

// label literal (as written in source, template-literal labels keep their
// `${...}` text) → pinned model. One entry per allowlisted call site.
const PIN_ALLOWLIST: Record<string, Record<string, string>> = {
  "review/workflows/review.workflow.js": {
    "classify": "sonnet",
    "file:${fid}": "haiku",
  },
  "plan-review/workflows/plan-review.workflow.js": {
    "detect-threshold": "sonnet",
  },
  "deepen-plan/workflows/deepen-plan.workflow.js": {
    "parse": "sonnet",
  },
  "resolve-parallel/workflows/resolve-parallel.workflow.js": {
    "analyze": "sonnet",
    "commit": "sonnet",
  },
  "resolve-todo-parallel/workflows/resolve-todo-parallel.workflow.js": {
    "analyze": "sonnet",
    "commit": "sonnet",
  },
  "resolve-pr-parallel/workflows/resolve-pr-parallel.workflow.js": {
    "fetch:round-${round}": "haiku",
    "commit:round-${round}": "sonnet",
  },
  "drain-labeled-backlog/workflows/drain-labeled-backlog.workflow.js": {
    "cluster": "sonnet",
    "report": "sonnet",
  },
};

// Files that MUST carry zero pins (never-downgrade exemptions with their own
// workflow script). agent-native-audit: the platform's sonnet→opus upgrade
// precedent for the identical scoring workload (cron-agent-native-audit.ts).
const ZERO_PIN_FILES = [
  "agent-native-audit/workflows/agent-native-audit.workflow.js",
];

function discoverWorkflowScripts(): string[] {
  const out: string[] = [];
  for (const skill of readdirSync(SKILLS_DIR)) {
    const wfDir = join(SKILLS_DIR, skill, "workflows");
    if (!existsSync(wfDir)) continue;
    for (const f of readdirSync(wfDir)) {
      if (f.endsWith(".workflow.js")) out.push(`${skill}/workflows/${f}`);
    }
  }
  return out.sort();
}

// Extract (label, model) pairs from every agent(...) options object that
// carries a `model:` key. Workflow scripts are single-spawn-per-options-object
// by construction; label and model co-occur inside one balanced `{...}`.
function extractPins(src: string): Array<{ label: string; model: string }> {
  const pins: Array<{ label: string; model: string }> = [];
  // Options objects are single-level here; match label and model within the
  // same braces (either order, possibly multi-line for the spread form).
  const optionsRe = /\{[^{}]*\blabel:\s*(?:'([^']*)'|`([^`]*)`)[^{}]*\}/g;
  let m: RegExpExecArray | null;
  while ((m = optionsRe.exec(src)) !== null) {
    const label = m[1] ?? m[2] ?? "";
    const modelMatch = m[0].match(/\bmodel:\s*'([^']*)'/);
    if (modelMatch) pins.push({ label, model: modelMatch[1] });
  }
  return pins;
}

describe("workflow model-pin allowlist (ADR-051)", () => {
  const scripts = discoverWorkflowScripts();

  test("discovers the workflow scripts", () => {
    // 8 at adoption; a new workflow script must be classified into the
    // allowlist (with pins) or implicitly zero-pin (judgment default).
    expect(scripts.length).toBeGreaterThanOrEqual(8);
  });

  for (const rel of scripts) {
    test(`${rel} pins match the allowlist exactly`, () => {
      const src = readFileSync(join(SKILLS_DIR, rel), "utf-8");
      const found = extractPins(src);
      const expected = PIN_ALLOWLIST[rel] ?? {};

      const foundMap: Record<string, string> = {};
      for (const p of found) foundMap[p.label] = p.model;

      // Exact-set equality: no missing pins, no extra pins, no tier drift.
      expect(foundMap).toEqual(expected);

      if (ZERO_PIN_FILES.includes(rel)) {
        expect(found.length).toBe(0);
        expect(src).not.toMatch(/\bmodel:\s*'/);
      }
    });
  }

  test("total pin count matches the adoption set", () => {
    const total = Object.values(PIN_ALLOWLIST).reduce(
      (n, pins) => n + Object.keys(pins).length,
      0,
    );
    expect(total).toBe(12);
  });

  test("only sonnet/haiku are pinnable tiers (never opus/fable/inherit literals)", () => {
    for (const rel of scripts) {
      const src = readFileSync(join(SKILLS_DIR, rel), "utf-8");
      const bad = src.match(/\bmodel:\s*'(?!sonnet'|haiku')[^']*'/);
      expect(bad).toBeNull();
    }
  });
});
