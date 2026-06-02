import { describe, expect, test } from "bun:test";
import { readFileSync } from "fs";
import { resolve } from "path";

// Test dir is plugins/soleur/test → repo root is three levels up.
const REPO_ROOT = resolve(import.meta.dir, "../../..");
const read = (rel: string) => readFileSync(resolve(REPO_ROOT, rel), "utf-8");

// feat-mandatory-ux-wireframes (#4819): wireframes non-skippable + stale-claim hardening.
// These assert the hardened END-STATE; they FAIL on pre-feature main (that is the RED).

describe("Feature A — mandatory .pen wireframes (no skip outcome)", () => {
  const brainstorm = read("plugins/soleur/skills/brainstorm/SKILL.md");
  const plan = read("plugins/soleur/skills/plan/SKILL.md");
  const work = read("plugins/soleur/skills/work/SKILL.md");

  test("brainstorm Phase 3.55 has no 'Phase 3.55: skipped' echo outcome", () => {
    expect(brainstorm).not.toContain("Phase 3.55: skipped");
  });

  test("brainstorm Phase 3.55 documents the auto-install-then-block terminal states", () => {
    expect(brainstorm).toContain("pencil-setup --auto");
    expect(brainstorm.toLowerCase()).toContain("hard-block");
  });

  test("plan Phase 2.5 no longer routes ux-design-lead self-stop into Skipped specialists", () => {
    // The old leak: "(agent self-stopped), write `Pencil available: no` ... add `ux-design-lead`
    // to `**Skipped specialists:**`". After hardening, the self-stop branch hard-blocks instead.
    expect(plan).not.toMatch(/agent self-stopped\),[\s\S]{0,200}Skipped specialists/);
  });

  test("plan Phase 2.5 has a mechanical UI-surface override forcing the gate", () => {
    // spec-flow P0-1: a UI feature must not slip the gate when the subjective sweep returns NONE.
    expect(plan).toMatch(/mechanical[\s\S]{0,80}(UI-surface|UI surface)[\s\S]{0,200}(BLOCKING|force)/i);
  });

  test("plan Phase 2.5 makes plan the sole producer on the one-shot path", () => {
    expect(plan).toMatch(/sole producer/i);
  });

  test("work Check-9 widened beyond .tsx/.jsx to the shared UI-surface term list", () => {
    // arch P1-2 / spec-flow P0-2: must catch .njk/.vue/.svelte/.astro surfaces too.
    expect(work).toMatch(/\.njk|\.svelte|\.vue|ui-surface-terms/);
  });
});

describe("Feature A — shared UI-surface term list (FR5)", () => {
  test("the shared term-list reference file exists", () => {
    const terms = read("plugins/soleur/skills/brainstorm/references/ui-surface-terms.md");
    expect(terms.length).toBeGreaterThan(0);
  });
});

describe("Feature A — deepen-plan wireframe halt is Phase 4.9 (4.8 already taken)", () => {
  const deepen = read("plugins/soleur/skills/deepen-plan/SKILL.md");

  test("exactly one '### 4.8.' survives (the existing PAT halt)", () => {
    const count = (deepen.match(/^### 4\.8\./gm) ?? []).length;
    expect(count).toBe(1);
  });

  test("the new wireframe halt is '### 4.9.'", () => {
    expect(deepen).toMatch(/^### 4\.9\. /m);
    expect(deepen).toContain("wg-ui-feature-requires-pen-wireframe");
  });
});

describe("Feature B — merged stale-claim hard rule + promoted wireframe gate", () => {
  const agentsIndex = read("AGENTS.md");
  const core = read("AGENTS.core.md");
  const docs = read("AGENTS.docs.md");

  test("the merged hard rule is present in the index and in AGENTS.core.md", () => {
    expect(agentsIndex).toContain("hr-verify-repo-capability-claim-before-assert");
    expect(core).toContain("hr-verify-repo-capability-claim-before-assert");
  });

  test("the hard rule covers BOTH own-output and subagent-prompt premises", () => {
    const idx = core.indexOf("hr-verify-repo-capability-claim-before-assert");
    const body = core.slice(Math.max(0, idx - 400), idx + 200);
    expect(body.toLowerCase()).toContain("subagent");
  });

  test("the promoted wireframe gate lives in AGENTS.docs.md (docs-only), pointer in index", () => {
    expect(agentsIndex).toContain("wg-ui-feature-requires-pen-wireframe");
    expect(docs).toContain("wg-ui-feature-requires-pen-wireframe");
  });

  test("the retired UX-gate id is NOT reintroduced as an active rule", () => {
    expect(core).not.toContain("wg-for-user-facing-pages-with-a-product-ux");
    expect(docs).not.toContain("wg-for-user-facing-pages-with-a-product-ux");
  });
});
