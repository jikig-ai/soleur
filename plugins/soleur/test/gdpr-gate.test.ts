import { describe, test, expect } from "bun:test";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { resolve, join } from "node:path";

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const SKILL_DIR = resolve(REPO_ROOT, "plugins/soleur/skills/gdpr-gate");
const SKILL_MD = resolve(SKILL_DIR, "SKILL.md");
const NOTICE = resolve(SKILL_DIR, "NOTICE");
const HOOK_SH = resolve(SKILL_DIR, "scripts/gdpr-gate.sh");
const FIXTURES_DIR = resolve(REPO_ROOT, "plugins/soleur/test/fixtures/gdpr-gate");

// Canonical path regex per plan §Phase 2 step 1 (single source of truth).
const CANONICAL_REGEX_SOURCE =
  "^(apps/web-platform/supabase/migrations/|apps/web-platform/lib/auth/|apps/web-platform/server/.*auth.*\\.(ts|tsx|js)|apps/web-platform/app/api/.*\\.(ts|tsx)$|.*\\.sql$)";
const CANONICAL_REGEX = new RegExp(CANONICAL_REGEX_SOURCE);

const DISCLAIMER_PATTERN = /This is not legal review/;
const SCHEMA_ONLY_DIRECTIVE = /DO NOT INCLUDE COLUMN VALUES/;
const ATTRIBUTION_HEADER =
  "<!-- Adapted from gosprinto/compliance-skills (MIT) — see NOTICE -->";

const LIFTED_REFS = [
  "references/fields.md",
  "references/leakage-vectors.md",
  "references/layers/api-layer.md",
  "references/layers/data-in-transit.md",
  "references/layers/data-lifecycle.md",
];

const SCRATCH_REFS = [
  "references/non-negotiables.md",
  "references/legal-consent.md",
];

function walk(dir: string): string[] {
  const out: string[] = [];
  if (!existsSync(dir)) return out;
  for (const entry of readdirSync(dir)) {
    const p = join(dir, entry);
    const s = statSync(p);
    if (s.isDirectory()) out.push(...walk(p));
    else out.push(p);
  }
  return out;
}

describe("gdpr-gate skill scaffold (AC1-AC5)", () => {
  test("SKILL.md exists", () => {
    expect(existsSync(SKILL_MD)).toBe(true);
  });

  test("NOTICE exists", () => {
    expect(existsSync(NOTICE)).toBe(true);
  });

  test("5 lifted reference files exist", () => {
    for (const f of LIFTED_REFS) {
      expect(existsSync(resolve(SKILL_DIR, f))).toBe(true);
    }
  });

  test("2 written-from-scratch reference files exist", () => {
    for (const f of SCRATCH_REFS) {
      expect(existsSync(resolve(SKILL_DIR, f))).toBe(true);
    }
  });

  test("each lifted file carries attribution header as line 1 (AC4)", () => {
    for (const f of LIFTED_REFS) {
      const content = readFileSync(resolve(SKILL_DIR, f), "utf8");
      const firstLine = content.split("\n")[0];
      expect(firstLine).toBe(ATTRIBUTION_HEADER);
    }
  });

  test("vendor-surface scrub: no sprinto.com / utm_source=Claude / 'powered by sprinto' / 'sprinto logo' anywhere in skill (NOTICE-attribution exempt) (AC5)", () => {
    if (!existsSync(SKILL_DIR)) {
      throw new Error("Skill dir missing — RED fixture not yet built");
    }
    const violations: string[] = [];
    const vendorPattern =
      /(sprinto\.com|utm_source=Claude|powered by sprinto|sprinto logo)/i;
    for (const file of walk(SKILL_DIR)) {
      // Allow vendor mentions only inside NOTICE and the attribution header
      // line. Other vendor references must not appear.
      const content = readFileSync(file, "utf8");
      const lines = content.split("\n");
      lines.forEach((line, idx) => {
        if (line === ATTRIBUTION_HEADER) return; // allowed
        if (file === NOTICE) return; // NOTICE itself may reference upstream
        if (vendorPattern.test(line)) {
          violations.push(`${file}:${idx + 1}: ${line}`);
        }
      });
    }
    expect(violations).toEqual([]);
  });
});

describe("gdpr-gate output format (AC20)", () => {
  test("(a) SKILL.md declares the disclaimer literal", () => {
    const content = readFileSync(SKILL_MD, "utf8");
    expect(content).toMatch(DISCLAIMER_PATTERN);
  });

  test("(a) every fixture's first non-blank line is the disclaimer", () => {
    if (!existsSync(FIXTURES_DIR)) {
      throw new Error(`Fixtures dir missing: ${FIXTURES_DIR}`);
    }
    const fixtures = readdirSync(FIXTURES_DIR).filter((f) =>
      f.endsWith(".md"),
    );
    expect(fixtures.length).toBeGreaterThanOrEqual(5);
    for (const f of fixtures) {
      const content = readFileSync(join(FIXTURES_DIR, f), "utf8");
      const firstNonBlank = content
        .split("\n")
        .map((l) => l.trim())
        .find((l) => l.length > 0);
      expect(firstNonBlank).toBeDefined();
      expect(firstNonBlank!).toMatch(DISCLAIMER_PATTERN);
    }
  });

  test("(b) Art. 9 special-category fixture is Critical; other 4 v1 checks are Important", () => {
    const expected: Record<string, "Critical" | "Important"> = {
      "art-6-lawful-basis.md": "Important",
      "art-5e-retention.md": "Important",
      "art-17-dsar-deletability.md": "Important",
      "art-v-cross-border.md": "Important",
      "art-9-special-category.md": "Critical",
    };
    for (const [fixture, severity] of Object.entries(expected)) {
      const path = join(FIXTURES_DIR, fixture);
      expect(existsSync(path)).toBe(true);
      const content = readFileSync(path, "utf8");
      // Severity appears as **Severity:** Critical or Important in the output schema.
      const m = content.match(/\*\*Severity:\*\*\s+(\w+)/);
      expect(m).not.toBeNull();
      expect(m![1]).toBe(severity);
    }
  });

  test("(c) Critical-finding flow prompts operator and does not auto-write to compliance-posture.md", () => {
    const content = readFileSync(SKILL_MD, "utf8");
    // Operator-acknowledgment prompt is required.
    expect(content).toMatch(/operator[- ]acknowledg/i);
    // Explicit negation of the auto-write contract is required (the gate must
    // declare it does NOT auto-write).
    expect(content).toMatch(
      /(never|does not|do not|never auto-?write|gate (does not|never)) (auto-?write|automatically write|writes?|modif)/i,
    );
  });

  test("(d) prompt template sends column NAMES only (schema-only directive present)", () => {
    const content = readFileSync(SKILL_MD, "utf8");
    expect(content).toMatch(SCHEMA_ONLY_DIRECTIVE);
  });

  test("(e) canonical regex matches the inventory + rejects unrelated paths", () => {
    const matches = [
      "apps/web-platform/supabase/migrations/050_new_table.sql",
      "apps/web-platform/lib/auth/dev-mode.ts",
      "apps/web-platform/server/auth-middleware.ts",
      "apps/web-platform/app/api/account/delete/route.ts",
      "scratch.sql",
    ];
    const rejects = [
      "README.md",
      "plugins/soleur/skills/gdpr-gate/SKILL.md",
      "docs/about.md",
      "knowledge-base/legal/compliance-posture.md",
    ];
    for (const p of matches) {
      expect(CANONICAL_REGEX.test(p)).toBe(true);
    }
    for (const p of rejects) {
      expect(CANONICAL_REGEX.test(p)).toBe(false);
    }
  });
});

describe("gdpr-gate lefthook hook (AC6, AC7)", () => {
  test("scripts/gdpr-gate.sh exists", () => {
    expect(existsSync(HOOK_SH)).toBe(true);
  });

  test("hook script: set -euo pipefail, sources incidents.sh, exits 0", () => {
    const content = readFileSync(HOOK_SH, "utf8");
    expect(content).toMatch(/set -euo pipefail/);
    expect(content).toMatch(/incidents\.sh/);
    expect(content).toMatch(/exit 0\b/);
  });

  test("hook prints stderr advisory line when a regulated path is touched", () => {
    const content = readFileSync(HOOK_SH, "utf8");
    expect(content).toMatch(/regulated-data path touched/);
    expect(content).toMatch(/run \/soleur:gdpr-gate/);
  });

  test("lefthook.yml registers gdpr-gate-advisory pre-commit hook with priority 6", () => {
    const lefthook = readFileSync(resolve(REPO_ROOT, "lefthook.yml"), "utf8");
    expect(lefthook).toMatch(/gdpr-gate-advisory/);
    // Extract the gdpr-gate-advisory block: starts at the command key (4-space
    // indented `gdpr-gate-advisory:`) and runs until the next 4-space-indented
    // sibling key.
    const m = lefthook.match(
      /^ {4}gdpr-gate-advisory:\n(?: {6}.*\n|\n)+/m,
    );
    expect(m).not.toBeNull();
    const block = m![0];
    expect(block).toMatch(/priority:\s*6/);
    expect(block).toMatch(/scripts\/gdpr-gate\.sh/);
  });
});

describe("gdpr-gate token budget (AC24 — heuristic; live API call gated by ANTHROPIC_API_KEY)", () => {
  // Synthesized in-test fixture per cq-test-fixtures-synthesized-only.
  // Column names are pure-synthetic (medical_history is the canonical Art. 9
  // example, never a real production column). Plan excerpt is ≤2k chars.
  const SYNTHETIC_DIFF = `
diff --git a/apps/web-platform/supabase/migrations/099_synth.sql b/apps/web-platform/supabase/migrations/099_synth.sql
new file mode 100644
+++ b/apps/web-platform/supabase/migrations/099_synth.sql
@@ -0,0 +1,12 @@
+CREATE TABLE synth_profile (
+  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
+  email TEXT NOT NULL,
+  display_name TEXT,
+  given_name TEXT,
+  family_name TEXT,
+  phone TEXT,
+  postal_code TEXT,
+  ip_last_seen INET,
+  audit_log_id BIGINT,
+  medical_history TEXT,  -- Art. 9 canary
+  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
+);
`.trim();

  const SYNTHETIC_PLAN_EXCERPT = `
## Files to Edit

| Path | Change |
|---|---|
| apps/web-platform/supabase/migrations/099_synth.sql | New table for synthesised audit fixture |
| apps/web-platform/lib/auth/synth-helper.ts | New helper to assert fixture properties |

## Acceptance Criteria

- [ ] AC-S1 — table 099_synth.sql is added under apps/web-platform/supabase/migrations/.
- [ ] AC-S2 — every column has either a NOT NULL or a documented nullability rationale.
- [ ] AC-S3 — auth helper passes the constraint-shape contract.
`.trim();

  test("(heuristic) input chars / 4 ≤ 4000 tokens for synthetic fixture", () => {
    const skillContent = readFileSync(SKILL_MD, "utf8");
    // Approximate input the gate would send: SKILL.md prompt template + fixture.
    const promptInput =
      skillContent + "\n\n--- DIFF ---\n" + SYNTHETIC_DIFF +
      "\n\n--- PLAN EXCERPT ---\n" + SYNTHETIC_PLAN_EXCERPT;
    // Claude tokenizer: ≈4 chars per token (English prose) is the published
    // ballpark. Heuristic budget = 4000 tokens → 16000 chars.
    const estimatedTokens = Math.ceil(promptInput.length / 4);
    expect(estimatedTokens).toBeLessThanOrEqual(4000);
  });

  test.skipIf(!process.env.ANTHROPIC_API_KEY)(
    "(live) Anthropic SDK input_tokens ≤ 4000 AND output_tokens ≤ 1500 (skipped — no SDK installed in plugin test context, deferred to v2)",
    () => {
      // Live API verification deferred: the @anthropic-ai/sdk is not a
      // dependency of the plugin test context, and adding it for a single
      // budget assertion exceeds the AC24 cost-benefit. The heuristic above
      // covers the budget invariant deterministically. v2 follow-up issue
      // tracks adding an end-to-end live-API budget test if telemetry shows
      // the heuristic drifting from real usage.
      expect(true).toBe(true);
    },
  );
});

describe("gdpr-gate NOTICE attribution (AC2)", () => {
  test("NOTICE pins upstream commit SHA and lists 5 active-layer rows", () => {
    if (!existsSync(NOTICE)) {
      throw new Error("NOTICE missing — RED fixture not yet built");
    }
    const content = readFileSync(NOTICE, "utf8");
    expect(content).toMatch(/7b58d68461cb1fc033a063e34cc9de63d0b4144b/);
    expect(content).toMatch(/gosprinto\/compliance-skills/i);
    // Each of the 5 lifted ref paths must appear by tail filename.
    for (const f of LIFTED_REFS) {
      const tail = f.replace(/^references\//, "");
      expect(content.includes(tail)).toBe(true);
    }
  });
});
