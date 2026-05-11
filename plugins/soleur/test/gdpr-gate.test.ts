import { describe, test, expect } from "bun:test";
import {
  existsSync,
  readFileSync,
  readdirSync,
  statSync,
  mkdtempSync,
  writeFileSync,
} from "node:fs";
import { resolve, join } from "node:path";
import { tmpdir } from "node:os";
import { spawnSync } from "node:child_process";

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
const SOLEUR_AUTHORED_HEADER =
  "<!-- Soleur-authored — see NOTICE -->";

const LIFTED_REFS = [
  "references/fields.md",
  "references/leakage-vectors.md",
  "references/layers/api-layer.md",
  "references/layers/data-in-transit.md",
  "references/layers/data-lifecycle.md",
  "references/layers/auth-sessions.md",
  "references/layers/frontend.md",
  "references/layers/testing-seeding.md",
];

const SCRATCH_REFS = [
  "references/non-negotiables.md",
  "references/legal-consent.md",
];

// Soleur-authored layers (post-v2 promotion) — must carry the Soleur
// attribution header on line 1 and a layer-shape body.
const SOLEUR_AUTHORED_LAYERS = ["references/legal-consent.md"];

const LEGACY_ARCHIVE = "references/legacy/legal-consent-v1-prose.md";

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

  test("all lifted reference files exist", () => {
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

describe("gdpr-gate canonical-regex parity (single source of truth)", () => {
  test("hook script CANONICAL_REGEX matches the test's literal", () => {
    const hookContent = readFileSync(HOOK_SH, "utf8");
    // The bash regex literal is single-quoted: CANONICAL_REGEX='...'
    const m = hookContent.match(/^CANONICAL_REGEX='([^']+)'/m);
    expect(m).not.toBeNull();
    expect(m![1]).toBe(CANONICAL_REGEX_SOURCE);
  });

  test("SKILL.md documents the same regex literal", () => {
    const skillContent = readFileSync(SKILL_MD, "utf8");
    expect(skillContent).toContain(CANONICAL_REGEX_SOURCE);
  });

  test("repo-scan.sh awk extraction yields the same regex byte-for-byte (Architecture M1)", () => {
    // The repo-scan.sh walker extracts the canonical regex from SKILL.md at
    // runtime instead of redefining it. Run the SAME awk script repo-scan.sh
    // uses and assert the extraction matches the test's literal. If SKILL.md
    // prose drifts (heading rename, fence-shape change, regex reformat),
    // this test fails the same way the runtime walker would — and well
    // before any operator hits it via `--repo-scan`.
    const awkScript = `
      /^## Path globs \\(canonical\\)/ { found = 1; next }
      found && /^\`\`\`/ { in_block = !in_block; next }
      found && in_block && /^[[:space:]]*\\^/ { print; exit }
    `;
    const result = Bun.spawnSync(["awk", awkScript, SKILL_MD], {
      stdout: "pipe",
      stderr: "pipe",
    });
    const extracted = result.stdout.toString().trim();
    expect(extracted).toBe(CANONICAL_REGEX_SOURCE);
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

  // Extract only the sections of SKILL.md that flow into the runtime prompt.
  // Operator-only sections (`## --repo-scan mode`, `## Sharp edges`, etc.) are
  // operator docs, not model input — including them makes the heuristic
  // wildly over-conservative as SKILL.md grows with operator-facing prose.
  // Runtime prompt = disclaimer + canonical regex + FR4 check table + output
  // format + prompt template wrapper.
  function extractRuntimePromptSubset(skill: string): string {
    const sectionsToInclude = new Set([
      "Disclaimer (always first)",
      "Path globs (canonical)",
      "5 mandatory v1 checks (FR4)",
      "Output format",
      "Prompt template — what the gate sends to the model",
    ]);
    const out: string[] = [];
    let currentHeading: string | null = null;
    let include = false;
    for (const line of skill.split("\n")) {
      const m = line.match(/^##\s+(.+)$/);
      if (m) {
        currentHeading = m[1].trim();
        include = sectionsToInclude.has(currentHeading);
      }
      if (include) out.push(line);
    }
    return out.join("\n");
  }

  test("(heuristic) input chars / 4 ≤ 4000 tokens for synthetic fixture", () => {
    const skillContent = readFileSync(SKILL_MD, "utf8");
    // Approximate input the gate would send: runtime-relevant sections only +
    // synthetic diff + synthetic plan excerpt.
    const promptInput =
      extractRuntimePromptSubset(skillContent) +
      "\n\n--- DIFF ---\n" + SYNTHETIC_DIFF +
      "\n\n--- PLAN EXCERPT ---\n" + SYNTHETIC_PLAN_EXCERPT;
    // Claude tokenizer: ≈4 chars per token (English prose) is the published
    // ballpark. Heuristic budget = 4000 tokens → 16000 chars.
    const estimatedTokens = Math.ceil(promptInput.length / 4);
    expect(estimatedTokens).toBeLessThanOrEqual(4000);
  });

  // Live API verification deferred per AC24: the @anthropic-ai/sdk is not a
  // dependency of the plugin test context, and adding it for a single budget
  // assertion exceeds the cost-benefit. The heuristic above covers the budget
  // invariant deterministically. v2 follow-up issue tracks adding an end-to-end
  // live-API budget test if telemetry shows the heuristic drifting from real
  // usage. test.todo (no body) avoids the vacuous-skip-stub anti-pattern per
  // cq-write-failing-tests-before.
  test.todo(
    "(live) Anthropic SDK input_tokens ≤ 4000 AND output_tokens ≤ 1500 — v2 follow-up",
  );
});

describe("gdpr-gate runtime staleness banner (FR6, AC6a-d)", () => {
  // The hook prepends a staleness banner to STDOUT (not stderr) when the
  // NOTICE last-verified date is >30 days old, and additionally emits a
  // POSTURE_FAIL line at >90 days. Parser failure / NOTICE missing /
  // future-dated → days_stale=999 → banner fires. Gate exits 0 in all paths
  // (advisory contract preserved).
  //
  // STDOUT is load-bearing per AC6d: agent runtimes (Claude Code skill harness,
  // MCP servers) frequently swallow stderr.
  function makeNoticeAt(daysAgo: number): string {
    const date = new Date(Date.now() - daysAgo * 86_400_000);
    const iso = date.toISOString().slice(0, 10);
    const tmp = mkdtempSync(join(tmpdir(), "gdpr-gate-notice-"));
    const path = join(tmp, "NOTICE");
    writeFileSync(
      path,
      `---\nupstream: github.com/test/synth\npinned-commit: ${"0".repeat(40)}\nlast-verified: ${iso}\nregistry: knowledge-base/engineering/policies/content-vendoring.md\nlifted-files:\n  - path: references/dummy.md\n    upstream-path: pii/dummy.md\n    upstream-blob-sha: ${"0".repeat(40)}\n    local-blob-sha: ${"0".repeat(40)}\n    status: active\n---\n\n# NOTICE (test fixture)\n`,
    );
    return path;
  }

  function runHook(
    env: Record<string, string> = {},
    args: string[] = ["scratch.md"],
  ): { stdout: string; stderr: string; exitCode: number } {
    const result = spawnSync("bash", [HOOK_SH, ...args], {
      env: { ...process.env, ...env },
      encoding: "utf8",
    });
    return {
      stdout: result.stdout || "",
      stderr: result.stderr || "",
      exitCode: result.status ?? -1,
    };
  }

  test("(AC6a) >30d stale: banner appears on STDOUT, gate exits 0", () => {
    const notice = makeNoticeAt(35);
    const { stdout, exitCode } = runHook({ NOTICE_FILE: notice });
    expect(stdout).toMatch(/gdpr-gate rules \d+ days stale/);
    expect(exitCode).toBe(0);
  });

  test("(AC6b) >90d stale: banner + POSTURE_FAIL on STDOUT, gate exits 0", () => {
    const notice = makeNoticeAt(95);
    const { stdout, exitCode } = runHook({ NOTICE_FILE: notice });
    expect(stdout).toMatch(/gdpr-gate rules \d+ days stale/);
    expect(stdout).toMatch(/POSTURE_FAIL/);
    expect(exitCode).toBe(0);
  });

  test("(AC6c) NOTICE missing → days_stale=999, banner + POSTURE_FAIL fire, exit 0", () => {
    const { stdout, exitCode } = runHook({
      NOTICE_FILE: "/nonexistent/path/NOTICE",
    });
    expect(stdout).toMatch(/999 days stale/);
    expect(stdout).toMatch(/POSTURE_FAIL/);
    expect(exitCode).toBe(0);
  });

  test("(AC6c) NOTICE future-dated → days_stale=999, banner fires, exit 0", () => {
    const future = makeNoticeAt(-365);
    const { stdout, exitCode } = runHook({ NOTICE_FILE: future });
    expect(stdout).toMatch(/999 days stale/);
    expect(exitCode).toBe(0);
  });

  test("fresh NOTICE (today) → NO staleness banner, exit 0", () => {
    const fresh = makeNoticeAt(0);
    const { stdout, exitCode } = runHook({ NOTICE_FILE: fresh });
    expect(stdout).not.toMatch(/days stale/);
    expect(exitCode).toBe(0);
  });

  test("(AC6d) banner emits to STDOUT, not stderr — agent runtimes swallow stderr", () => {
    const notice = makeNoticeAt(35);
    const { stdout, stderr } = runHook({ NOTICE_FILE: notice });
    expect(stdout).toMatch(/days stale/);
    expect(stderr).not.toMatch(/days stale/);
  });

  test("staleness check independent of regulated-data regex match", () => {
    // Pass a non-regulated path; banner must still fire because the check
    // runs unconditionally on every hook invocation.
    const notice = makeNoticeAt(35);
    const { stdout, stderr } = runHook(
      { NOTICE_FILE: notice },
      ["docs/about.md"],
    );
    expect(stdout).toMatch(/days stale/);
    expect(stderr).not.toMatch(/regulated-data path touched/);
  });
});

describe("gdpr-gate NOTICE attribution (AC2, AC-LIFT-5)", () => {
  test("NOTICE pins upstream commit SHA and lists every lifted ref", () => {
    if (!existsSync(NOTICE)) {
      throw new Error("NOTICE missing — RED fixture not yet built");
    }
    const content = readFileSync(NOTICE, "utf8");
    expect(content).toMatch(/7b58d68461cb1fc033a063e34cc9de63d0b4144b/);
    expect(content).toMatch(/gosprinto\/compliance-skills/i);
    // Each lifted ref path must appear by tail filename.
    for (const f of LIFTED_REFS) {
      const tail = f.replace(/^references\//, "");
      expect(content.includes(tail)).toBe(true);
    }
  });

  // Comprehensive regex-metachar escape used when inserting trusted path
  // strings from LIFTED_REFS into a constructed RegExp. The full set of
  // ECMAScript regex metachars is escaped (not just `.`/`/`/`-`) so the
  // resulting regex is robust to any future LIFTED_REFS entry shape and
  // satisfies CodeQL's `js/incomplete-sanitization` rule (which warns when
  // a sanitizer is incomplete even if current inputs would happen to be
  // safe).
  const escapeRegExp = (s: string): string =>
    s.replace(/[.*+?^${}()|[\]\\/-]/g, "\\$&");

  test("each LIFTED_REFS entry has a 40-char hex blob SHA on the same row, and SHAs are unique (Kieran P3.1)", () => {
    const content = readFileSync(NOTICE, "utf8");
    const seen = new Map<string, string>();
    for (const f of LIFTED_REFS) {
      // Find the table row that mentions the file path. Soleur path appears
      // first in the row, then the upstream path, then the SHA cell. Anchor
      // on `^|` (start-of-row) to defend against future column reorders that
      // could otherwise let a non-row match (e.g. an inline backtick path
      // mention in prose) match the SHA cell.
      const re = new RegExp(
        `^\\|\\s*\\\`${escapeRegExp(f)}\\\`[^\\n]*?\\|\\s*\\\`([0-9a-f]{40})\\\`\\s*\\|`,
        "m",
      );
      const m = content.match(re);
      expect(m, `NOTICE row missing or malformed for ${f}`).not.toBeNull();
      const sha = m![1];
      expect(sha.length).toBe(40);
      expect(/^[0-9a-f]{40}$/.test(sha)).toBe(true);
      // Uniqueness — each lifted file gets its own blob SHA. A duplicate
      // signals an accidental copy-paste of v1 SHAs into v2 rows.
      const previous = seen.get(sha);
      expect(
        previous,
        `Duplicate blob SHA ${sha} between ${previous} and ${f}`,
      ).toBeUndefined();
      seen.set(sha, f);
    }
  });

  test("every NOTICE-listed lifted file exists on disk (Architecture M4)", () => {
    // Defends against a future rename/delete that updates the file but
    // leaves a phantom NOTICE row claiming attribution for a non-existent
    // path. Cheap fs-presence check; mirrors the legal-hygiene contract
    // that NOTICE accurately describes the lifted corpus.
    for (const f of LIFTED_REFS) {
      const abs = resolve(SKILL_DIR, f);
      expect(existsSync(abs), `LIFTED_REFS path missing on disk: ${f}`).toBe(
        true,
      );
    }
    // Symmetric: legacy archive must exist as long as NOTICE references it.
    if (readFileSync(NOTICE, "utf8").includes("legacy/legal-consent-v1-prose.md")) {
      expect(existsSync(resolve(SKILL_DIR, LEGACY_ARCHIVE))).toBe(true);
    }
  });
});

describe("gdpr-gate Soleur-authored layers (AC-PROMOTE-1)", () => {
  test("each Soleur-authored layer carries the Soleur-authored header on line 1", () => {
    for (const f of SOLEUR_AUTHORED_LAYERS) {
      const content = readFileSync(resolve(SKILL_DIR, f), "utf8");
      const firstLine = content.split("\n")[0];
      expect(firstLine).toBe(SOLEUR_AUTHORED_HEADER);
    }
  });

  test("legal-consent.md is layer-shaped (LC-01 marker + ## When This Layer Loads)", () => {
    const content = readFileSync(
      resolve(SKILL_DIR, "references/legal-consent.md"),
      "utf8",
    );
    expect(content).toContain("## When This Layer Loads");
    for (const id of ["LC-01", "LC-02", "LC-03", "LC-04", "LC-05"]) {
      expect(content).toContain(id);
    }
    // Each block must carry the canonical layer template fields.
    expect(content).toMatch(/What to grep:/);
    expect(content).toMatch(/Flag when:/);
    expect(content).toMatch(/Fix pattern:/);
    expect(content).toMatch(/Regulation:/);
  });
});

describe("gdpr-gate legacy archive (AC-PROMOTE-2)", () => {
  test("v1 prose-shaped legal-consent is archived under references/legacy/", () => {
    const path = resolve(SKILL_DIR, LEGACY_ARCHIVE);
    expect(existsSync(path)).toBe(true);
    const content = readFileSync(path, "utf8");
    // Provenance header on line 1 calls out the archived state and the
    // one-release-cycle removal contract.
    const firstLine = content.split("\n")[0];
    expect(firstLine).toMatch(/Archived v1 prose-shape/);
    expect(firstLine).toMatch(/v3/);
  });
});
