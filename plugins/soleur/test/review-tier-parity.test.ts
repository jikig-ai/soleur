import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

// ---------------------------------------------------------------------------
// Guard 3 (ADR-267, #9399): three-way parity pin —
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

// Extract the tier rows of the `## Seat scaling` table — section-scoped, and
// collecting EVERY backticked first-column cell so an unrecognized fourth row
// reddens the set-equality assertion instead of being silently skipped.
function seatScalingTiers(src: string): string[] {
  const section = src.split(/^## /m).find((s) => s.startsWith("Seat scaling"))!;
  const tiers: string[] = [];
  for (const line of section.split("\n")) {
    const m = line.match(/^\|\s*`([^`]+)`/);
    if (m) tiers.push(m[1].replace(/\s*\(.*$/, ""));
  }
  return tiers;
}

function shellVar(name: string): string {
  const m = SCRIPT.match(new RegExp(`${name}='([^']+)'`));
  expect(m, `fix-round-seats.sh carries ${name}`).not.toBeNull();
  return m![1];
}

// Seat registry: agentType leaves in the workflow's DIMENSIONS, plus the
// deterministic/non-agent seats the workflow carries as `deterministic: true`
// dims, plus the SKILL-only seats (structural-enumeration's guard-shaped pass;
// code-simplicity-reviewer, which the ledger may legitimately name as a
// reporting seat even though it is not a spawned dimension).
function workflowSeats(): Set<string> {
  const seats = new Set<string>();
  for (const m of WORKFLOW.matchAll(/agentType:\s*'soleur:(?:[a-z-]+:)+([a-z-]+)'/g)) {
    seats.add(m[1]);
  }
  // Deterministic dims are derived from the workflow's own `deterministic: true`
  // markers, mapped to their emitted seat names — not restated as constants.
  for (const m of WORKFLOW.matchAll(/['"]?([a-z-]+)['"]?\s*:\s*\{[^}]*deterministic:\s*true/g)) {
    const dim = m[1];
    seats.add(dim === "semgrep" ? "semgrep-sast" : dim === "gdpr" ? "gdpr-gate" : dim);
  }
  for (const s of ["structural-enumeration", "code-simplicity-reviewer"]) seats.add(s);
  return seats;
}

describe("review-tier parity (ADR-267)", () => {
  test("the seat-scaling table's tier set is exactly the resolved enum", () => {
    expect(seatScalingTiers(REF).sort()).toEqual([...TIERS].sort());
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
    const noneRow = REF.split("\n").find((l) => l.startsWith("| `none`"))!;
    // Bare token, not the `+ ` spelling — the name must not appear in the row at all.
    expect(noneRow).not.toContain("user-impact-reviewer");
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
    const noneRow = REF.split("\n").find((l) => l.startsWith("| `none`"))!;
    // The row's FIRST {...} group is the gated set (the second is the floor).
    const gatedGroup = noneRow.match(/\{([^}]+)\}/)![1].split(",").map((s) => s.trim());
    const gateMap = WORKFLOW.match(/NONE_TIER_GATED\s*=\s*\{([^}]+)\}/);
    expect(gateMap, "workflow carries NONE_TIER_GATED").not.toBeNull();
    const gateKeys = [...gateMap![1].matchAll(/['"]?([a-z-]+)['"]?\s*:/g)].map((m) => m[1]);
    expect(gateKeys.sort()).toEqual(["agent-native", "data-integrity", "performance"]);
    expect([...gatedGroup].sort()).toEqual([...gateKeys].sort());
    // And the floor set the row declares is the never-shed remainder.
    const floorGroup = noneRow.match(/\}.*\{([^}]+)\}/s)![1].split(",").map((s) => s.trim());
    expect([...floorGroup].sort()).toEqual(
      ["architecture", "code-quality", "git-history", "pattern", "security"].sort(),
    );
  });

  test("deep review bypasses the none-tier gate (override beats every tier row)", () => {
    // Contract: the override "is unchanged and beats every row above". The
    // ternary's TRUE branch must be the unscaled class set — a neutered
    // `deepReview ? scaleAlwaysOn(x) : scaleAlwaysOn(y)` must not pass.
    const norm = WORKFLOW.replace(/\s+/g, " ");
    expect(norm).toMatch(/deepReview\s*\?\s*\(?\s*CLASS_DIMENSIONS[^:]*:\s*scaleAlwaysOn\(/);
  });

  test("script SENSITIVE_PATH_RE is byte-identical to the preflight canonical", () => {
    // Anchor on the Check 6 Step 6.1 section, not the first textual occurrence.
    const section = PREFLIGHT.split(/Step 6\.1/)[1];
    const canonical = section.match(/SENSITIVE_PATH_RE='([^']+)'/)![1];
    const copy = shellVar("SENSITIVE_PATH_RE");
    expect(copy).toBe(canonical);
  });

  test("script GDPR_PATH_RE is byte-identical to the gdpr-gate canonical regex", () => {
    // Anchored on the canonical section heading, not the first fenced block.
    const block = GDPR_SKILL.split(/^## Path globs \(canonical\)/m)[1];
    const canonical = block.match(/```\n(\^[^\n]+)\n```/)![1];
    const copy = shellVar("GDPR_PATH_RE");
    expect(copy).toBe(canonical);
  });

  test("workflow MECHANICAL_SURFACE_RE copies are byte-identical to the script's arms", () => {
    // A JS regex literal escapes `/` as `\/`; the script's ERE literals do not.
    const wf = (key: string) =>
      WORKFLOW.match(new RegExp(`${key}:\\s*/(.*?)/,\\s*\\n`))![1].replaceAll("\\/", "/");
    expect(wf("sensitivePath")).toBe(shellVar("SENSITIVE_PATH_RE"));
    expect(wf("gdprMatch")).toBe(shellVar("GDPR_PATH_RE"));
    expect(wf("agentNativeSurface")).toBe(shellVar("AGENT_SURFACE_RE"));
    expect(wf("perfSurface")).toBe(shellVar("PERF_RE"));
    // dataIntegritySurface is the union of the script's MIGRATION and PERSIST arms.
    const mig = shellVar("MIGRATION_RE").replace(/^\(|\)$/g, "");
    const per = shellVar("PERSIST_RE").replace(/^\(|\)$/g, "");
    expect(wf("dataIntegritySurface")).toBe(`(${mig}|${per})`);
  });

  test("script SEAT_REGISTRY resolves against the workflow registry", () => {
    const registry = workflowSeats();
    const scriptSeats = new Set(shellVar("SEAT_REGISTRY").split(/\s+/));
    for (const seat of scriptSeats) {
      expect(registry.has(seat), `SEAT_REGISTRY carries unregistered seat '${seat}'`).toBe(true);
    }
    // Reverse direction: a spawnable agent seat the script lacks would be
    // silently droppable by --finding-seats ("extend both, never one").
    const scriptOnly = ["structural-enumeration", "code-simplicity-reviewer", "shellcheck", "anti-slop", "gdpr-gate"];
    for (const seat of registry) {
      if (scriptOnly.includes(seat)) continue;
      expect(scriptSeats.has(seat), `workflow seat '${seat}' missing from SEAT_REGISTRY`).toBe(true);
    }
  });

  test("model.c4 review component no longer claims a fixed 8-seat panel", () => {
    const c4 = readFileSync(
      resolve(PLUGIN_ROOT, "../../knowledge-base/engineering/architecture/diagrams/model.c4"),
      "utf8",
    );
    const comp = c4.match(/review = component "review skill" \{[^}]+\}/s)!;
    expect(comp, "model.c4 review component block").not.toBeNull();
    expect(comp[0]).not.toContain("8 parallel reviewers");
    expect(comp[0]).toContain("risk tier");
  });
});
