import { describe, test, expect } from "bun:test";
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { resolve, join } from "node:path";
import { PLUGIN_ROOT } from "./helpers";

// Standing pin-allowlist gate (#3791, ADR-053).
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
// All three JS quote forms are matched for BOTH keys — a double-quoted or
// template-literal `model: "opus"` must not evade the gate (mutation-probe
// finding, 2026-06-10).
const ANY_QUOTE_MODEL = /\bmodel\s*:\s*(?:'([^']*)'|"([^"]*)"|`([^`]*)`)/g;

function extractPins(src: string): Array<{ label: string; model: string }> {
  const pins: Array<{ label: string; model: string }> = [];
  // Options objects are single-level here; match label and model within the
  // same braces (either order, possibly multi-line for the spread form).
  const optionsRe =
    /\{[^{}]*\blabel:\s*(?:'([^']*)'|"([^"]*)"|`([^`]*)`)[^{}]*\}/g;
  let m: RegExpExecArray | null;
  while ((m = optionsRe.exec(src)) !== null) {
    const label = m[1] ?? m[2] ?? m[3] ?? "";
    const modelMatch = m[0].match(/\bmodel\s*:\s*(?:'([^']*)'|"([^"]*)"|`([^`]*)`)/);
    if (modelMatch) {
      pins.push({ label, model: modelMatch[1] ?? modelMatch[2] ?? modelMatch[3] ?? "" });
    }
  }
  return pins;
}

// Every model literal in the file, regardless of surrounding shape — catches
// label-less pins that extractPins cannot attribute.
function allModelLiterals(src: string): string[] {
  const out: string[] = [];
  let m: RegExpExecArray | null;
  const re = new RegExp(ANY_QUOTE_MODEL.source, "g");
  while ((m = re.exec(src)) !== null) out.push(m[1] ?? m[2] ?? m[3] ?? "");
  return out;
}

describe("workflow model-pin allowlist (ADR-053)", () => {
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

      // Label-less evasion gate: every model literal in the file must be
      // attributable to an allowlisted (label, model) pin. A `model:` key in
      // an options object without a label (or outside one) is unattributable
      // and fails here (mutation-probe finding, 2026-06-10).
      const literals = allModelLiterals(src);
      expect(literals.length).toBe(Object.keys(expected).length);

      // Fail-closed sweep: count RAW `model :` keys regardless of value form.
      // A `model: someVar`, a pin inside a nested-brace options object, or any
      // shape the extractor cannot parse is a violation, not a skip — the raw
      // count must equal the allowlist size exactly (review finding
      // pin-allowlist-gate-fails-open, 2026-06-10).
      const rawModelKeys = (src.match(/\bmodel\s*:/g) ?? []).length;
      expect(rawModelKeys).toBe(Object.keys(expected).length);

      // Disclosure-string parity: each pin's label stem must appear in a
      // `tier pins:` log line as `<stem>→<model>` so the operator-facing
      // disclosure cannot drift from the actual pins (review finding
      // pin-disclosure-string-unverified, 2026-06-10).
      for (const [label, model] of Object.entries(expected)) {
        const stem = label.split(":")[0];
        expect(src).toContain(`${stem}→${model}`);
      }

      if (ZERO_PIN_FILES.includes(rel)) {
        expect(found.length).toBe(0);
        expect(rawModelKeys).toBe(0);
      }
    });
  }

  test("zero-pin exemption files exist on disk (guard is not vacuous)", () => {
    for (const rel of ZERO_PIN_FILES) {
      expect(scripts).toContain(rel);
    }
  });

  test("total pin count matches the adoption set", () => {
    // Sum pins found in PRODUCTION SOURCE (not the allowlist — summing the
    // allowlist against itself is tautological; review finding
    // self-referential-pin-count-test, 2026-06-10).
    const total = scripts.reduce(
      (n, rel) =>
        n + extractPins(readFileSync(join(SKILLS_DIR, rel), "utf-8")).length,
      0,
    );
    expect(total).toBe(12);
  });

  test("only sonnet/haiku are pinnable tiers (never opus/fable/inherit literals)", () => {
    for (const rel of scripts) {
      const src = readFileSync(join(SKILLS_DIR, rel), "utf-8");
      const bad = allModelLiterals(src).filter(
        (v) => v !== "sonnet" && v !== "haiku",
      );
      expect(bad).toEqual([]);
    }
  });
});
