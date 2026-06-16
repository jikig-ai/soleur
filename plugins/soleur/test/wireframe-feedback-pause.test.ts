import { describe, expect, test } from "bun:test";
import { readFileSync } from "fs";
import { resolve } from "path";

// Test dir is plugins/soleur/test → repo root is three levels up.
const REPO_ROOT = resolve(import.meta.dir, "../../..");
const read = (rel: string) => readFileSync(resolve(REPO_ROOT, rel), "utf-8");

// feat-one-shot-pause-wireframe-feedback: after ux-design-lead generates wireframe
// screenshots and opens the folder (xdg-open), the INTERACTIVE workflow pauses via
// AskUserQuestion (Approve / Request changes) before continuing; headless/pipeline
// mode auto-proceeds and logs. These assert the END-STATE; they FAIL on pre-feature
// main (that is the RED).

const brainstorm = read("plugins/soleur/skills/brainstorm/SKILL.md");
const plan = read("plugins/soleur/skills/plan/SKILL.md");
const uxLead = read("plugins/soleur/agents/product/design/ux-design-lead.md");

// Extract the brainstorm wireframe-review gate block (Phase 3.55b through the next
// "### Phase" heading) so assertions are scoped to the gate, not the whole file.
function brainstormGate(): string {
  const start = brainstorm.indexOf("Phase 3.55b");
  expect(start).toBeGreaterThan(-1); // AC1: the gate block exists
  const rest = brainstorm.slice(start);
  const end = rest.search(/\n### Phase /);
  return end === -1 ? rest : rest.slice(0, end);
}

// Extract the plan wireframe-review gate block (step 4b through the next numbered
// "5." step or "**On ADVISORY:**").
function planGate(): string {
  const start = plan.indexOf("4b. **Wireframe review pause");
  expect(start).toBeGreaterThan(-1); // AC2: the gate block exists
  const rest = plan.slice(start);
  const end = rest.search(/\n5\. \*\*Content Review Gate|\n\*\*On ADVISORY:\*\*/);
  // The gate block must be bounded by the next step — fail loud rather than
  // silently slicing an arbitrary window if the surrounding structure changes.
  expect(end).toBeGreaterThan(-1);
  return rest.slice(0, end);
}

describe("AC1 — interactive pause exists (brainstorm Phase 3.55b)", () => {
  test("the gate block is an AskUserQuestion review gate with Approve + Request changes", () => {
    const gate = brainstormGate();
    expect(gate).toContain("AskUserQuestion");
    expect(gate.toLowerCase()).toContain("approve");
    expect(gate.toLowerCase()).toContain("request changes");
  });

  test("the gate names the wireframe review pause", () => {
    const gate = brainstormGate();
    expect(gate.toLowerCase()).toContain("wireframe review pause");
  });
});

describe("AC2 — interactive pause exists (plan Phase 2.5 step 4b)", () => {
  test("the gate block is an AskUserQuestion review gate with Approve + Request changes", () => {
    const gate = planGate();
    expect(gate).toContain("AskUserQuestion");
    expect(gate.toLowerCase()).toContain("approve");
    expect(gate.toLowerCase()).toContain("request changes");
  });

  test("the gate names the wireframe review pause", () => {
    const gate = planGate();
    expect(gate.toLowerCase()).toContain("wireframe review pause");
  });
});

describe("AC3 — headless suppression is explicit in BOTH gates", () => {
  test("brainstorm gate has a headless/pipeline no-pause arm", () => {
    const gate = brainstormGate().toLowerCase();
    expect(gate).toMatch(/headless|pipeline|no tty/);
    expect(gate).toMatch(/do not pause|auto-proceed|continue without|never pause/);
  });

  test("plan gate has a headless/pipeline no-pause arm", () => {
    const gate = planGate().toLowerCase();
    expect(gate).toMatch(/headless|pipeline|no tty|subagent/);
    expect(gate).toMatch(/do not pause|auto-proceed|continue without|never pause/);
  });
});

describe("AC4 — request-changes loop re-invokes the producer", () => {
  test("brainstorm gate re-invokes ux-design-lead and loops until approve", () => {
    const gate = brainstormGate();
    expect(gate).toMatch(/re-?invoke[\s\S]{0,80}ux-design-lead/i);
    expect(gate.toLowerCase()).toMatch(/loop until approv/);
  });

  test("plan gate re-invokes ux-design-lead and loops until approve", () => {
    const gate = planGate();
    expect(gate).toMatch(/re-?invoke[\s\S]{0,80}ux-design-lead/i);
    expect(gate.toLowerCase()).toMatch(/loop until approv/);
  });
});

describe("AC5 — subagent keeps xdg-open; body cross-references the orchestrator pause", () => {
  test("ux-design-lead still runs xdg-open", () => {
    expect((uxLead.match(/xdg-open/g) ?? []).length).toBeGreaterThanOrEqual(1);
  });

  test("ux-design-lead body cross-references the orchestrator pause location", () => {
    expect(uxLead).toMatch(/orchestrator/i);
    expect(uxLead).toMatch(/3\.55b|Phase 2\.5/);
  });
});
