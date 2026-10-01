import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

// ---------------------------------------------------------------------------
// Guard 3 (ADR-265, #9399): three-way parity pin —
//   references/risk-tier-and-fix-rounds.md  (the normative table)
//   workflows/review.workflow.js            (the gating that runs)
//   scripts/fix-round-seats.sh              (the path→seat map both use)
//
// The copy that runs must match the copy that is specified. Normalized-source
// comparisons, never presence greps (a comment can satisfy a bare token).
// ---------------------------------------------------------------------------

const PLUGIN_ROOT = resolve(import.meta.dir, "..");
const read = (p: string) => readFileSync(resolve(PLUGIN_ROOT, p), "utf8");

const REF = read("skills/review/references/risk-tier-and-fix-rounds.md");
const WORKFLOW = read("skills/review/workflows/review.workflow.js");
const SCRIPT = read("skills/review/scripts/fix-round-seats.sh");
const PREFLIGHT = read("skills/preflight/SKILL.md");
const GDPR_SKILL = read("skills/gdpr-gate/SKILL.md");

const TIERS = ["none", "single-user incident", "aggregate pattern"];

// Extract the tier rows of the seat-scaling table: `| \`<tier>\` ...`.
function tableTiers(src: string): string[] {
  const tiers: string[] = [];
  for (const line of src.split("\n")) {
    const m = line.match(/^\|\s*`([^`]+)`/);
    if (m && TIERS.some((t) => m[1] === t || m[1].startsWith(t + " "))) {
      tiers.push(m[1].replace(/\s*\(.*$/, ""));
    }
  }
  return tiers;
}

// Seat registry: agentType leaves in the workflow's DIMENSIONS, plus the
// deterministic/skill seats with no agentType and the SKILL-only seats.
function workflowSeats(): Set<string> {
  const seats = new Set<string>();
  for (const m of WORKFLOW.matchAll(/agentType:\s*'soleur:(?:[a-z-]+:)+([a-z-]+)'/g)) {
    seats.add(m[1]);
  }
  for (const s of ["shellcheck", "anti-slop", "gdpr-gate", "structural-enumeration"]) {
    seats.add(s);
  }
  return seats;
}

describe("review-tier parity (ADR-265)", () => {
  test("the reference table's tier set is exactly the resolved enum", () => {
    expect(tableTiers(REF).sort()).toEqual([...TIERS].sort());
  });

  test("workflow brandThreshold enum = 3 resolved tiers + the undeclared parse state", () => {
    const m = WORKFLOW.match(/brandThreshold:\s*\{[^}]*enum:\s*\[([^\]]+)\]/);
    expect(m, "workflow carries no brandThreshold enum").not.toBeNull();
    const vals = [...m![1].matchAll(/'([^']+)'/g)].map((x) => x[1]);
    expect(vals.sort()).toEqual([...TIERS, "undeclared"].sort());
  });

  test("workflow fires user-impact iff tier is single-user incident or aggregate pattern", () => {
    // The reference table's two elevated rows both carry `+ user-impact-reviewer`.
    // Anchor on table rows (`| \`<tier>\``) — plain `includes` would match the
    // enum bullets in the "Risk tier" section above the table.
    for (const t of ["single-user incident", "aggregate pattern"]) {
      const row = REF.split("\n").find((l) => l.startsWith(`| \`${t}\``));
      expect(row, `reference row for ${t}`).toContain("user-impact-reviewer");
    }
    const noneRow = REF.split("\n").find((l) => l.startsWith("| `none`"));
    expect(noneRow).not.toContain("+ user-impact-reviewer");
    // The workflow gates the seat on exactly those two values.
    const norm = WORKFLOW.replace(/\s+/g, " ");
    expect(norm).toMatch(
      /brandThreshold\s*===?\s*'single-user incident'\s*\|\|\s*\w+\.brandThreshold\s*===?\s*'aggregate pattern'[^;]*push\('user-impact'\)/,
    );
    // And never on the `none`/`undeclared` values.
    expect(norm).not.toMatch(/brandThreshold\s*===?\s*'none'[^;]*user-impact/);
    expect(norm).not.toMatch(/brandThreshold\s*===?\s*'undeclared'[^;]*user-impact/);
  });

  test("workflow SKEPTICS escalates iff aggregate pattern (table: SKEPTICS=3 row)", () => {
    const aggRow = REF.split("\n").find((l) => l.startsWith("| `aggregate pattern`"));
    expect(aggRow).toContain("SKEPTICS=3");
    for (const t of ["none", "single-user incident"]) {
      const row = REF.split("\n").find((l) => l.startsWith(`| \`${t}\``));
      expect(row).not.toContain("SKEPTICS=3");
    }
    const norm = WORKFLOW.replace(/\s+/g, " ");
    expect(norm).toMatch(/SKEPTICS\s*=\s*[^;]*'aggregate pattern'[^;]*\?\s*3\s*:\s*1/);
  });

  test("none-tier trigger-gates exactly {data-integrity, agent-native, performance}", () => {
    const noneRow = REF.split("\n").find((l) => l.startsWith("| `none`"));
    expect(noneRow).toContain("data-integrity");
    expect(noneRow).toContain("agent-native");
    expect(noneRow).toContain("performance");
    const norm = WORKFLOW.replace(/\s+/g, " ");
    // The workflow maps each gated dimension to its surface trigger.
    for (const dim of ["data-integrity", "agent-native", "performance"]) {
      expect(norm, `workflow gates ${dim} on a surface trigger`).toContain(dim);
    }
    expect(norm).toMatch(/dataIntegritySurface/);
    expect(norm).toMatch(/agentNativeSurface/);
    expect(norm).toMatch(/perfSurface/);
  });

  test("script SENSITIVE_PATH_RE is byte-identical to the preflight canonical", () => {
    const canonical = PREFLIGHT.match(/SENSITIVE_PATH_RE='([^']+)'/)![1];
    const copy = SCRIPT.match(/SENSITIVE_PATH_RE='([^']+)'/)![1];
    expect(copy).toBe(canonical);
  });

  test("script GDPR_PATH_RE is byte-identical to the gdpr-gate canonical regex", () => {
    // The heading is also referenced in-line at line ~46 — split on the real
    // heading (line start), not the first textual occurrence.
    const block = GDPR_SKILL.split(/^## Path globs \(canonical\)/m)[1];
    const canonical = block.match(/```\n(\^[^\n]+)\n```/)![1];
    const copy = SCRIPT.match(/GDPR_PATH_RE='([^']+)'/)![1];
    expect(copy).toBe(canonical);
  });

  test("script SEAT_REGISTRY and SEAT_ORDER resolve against the workflow registry", () => {
    const registry = workflowSeats();
    for (const varName of ["SEAT_REGISTRY", "SEAT_ORDER"]) {
      const m = SCRIPT.match(new RegExp(`${varName}='([^']+)'`))!;
      for (const seat of m[1].split(/\s+/)) {
        expect(registry.has(seat), `${varName} carries unregistered seat '${seat}'`).toBe(true);
      }
    }
    // Order covers exactly the registry — no dropped or extra seat.
    const order = SCRIPT.match(/SEAT_ORDER='([^']+)'/)![1].split(/\s+/);
    const reg = SCRIPT.match(/SEAT_REGISTRY='([^']+)'/)![1].split(/\s+/);
    expect([...order].sort()).toEqual([...reg].sort());
  });
});
