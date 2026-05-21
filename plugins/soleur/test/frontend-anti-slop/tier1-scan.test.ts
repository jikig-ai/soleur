import { describe, test, expect } from "bun:test";
import { mkdtempSync, writeFileSync, rmSync, mkdirSync } from "node:fs";
import { resolve, join } from "node:path";
import { tmpdir } from "node:os";
import {
  parseRules,
  scanFile,
  disabledRulesInFile,
  RULES_FILE,
} from "../../skills/frontend-anti-slop/scripts/tier1-scan";
import { readFileSync } from "node:fs";

// tier1-scan.test.ts — frontend-anti-slop v1 scanner.
// 5 representative Tier 1 rules × positive + negative = 10 fixtures (per
// plan §"Test Strategy"; per-rule exhaustive coverage deferred to v1.5).
// Plus a calibration baseline against a real project file.

const RULES = parseRules(readFileSync(RULES_FILE, "utf8"));

function ruleById(id: string) {
  const r = RULES.find((r) => r.id === id);
  if (!r) throw new Error(`fixture references unknown rule ${id}`);
  return r;
}

function withFile(
  filename: string,
  content: string,
  body: (absPath: string) => void,
): void {
  const dir = mkdtempSync(join(tmpdir(), "anti-slop-fixture-"));
  const abs = join(dir, filename);
  // make sure nested dirs exist if filename contains slashes
  if (filename.includes("/")) {
    mkdirSync(join(dir, filename.split("/").slice(0, -1).join("/")), {
      recursive: true,
    });
  }
  writeFileSync(abs, content, "utf8");
  try {
    body(abs);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

describe("frontend-anti-slop tier1-scan: 5 rules × pos + neg fixtures", () => {
  // 1. GRADIENT-TEXT (high)
  test("GRADIENT-TEXT POSITIVE: triad present", () => {
    withFile(
      "page.tsx",
      `<h1 className="bg-clip-text text-transparent bg-gradient-to-r from-purple-500 to-pink-500">Hi</h1>`,
      (abs) => {
        const findings = scanFile(abs, [ruleById("GRADIENT-TEXT")]);
        expect(findings).toHaveLength(1);
        expect(findings[0].selector).toMatch(/#GRADIENT-TEXT$/);
        expect(findings[0].category).toBe("anti-slop");
        expect(findings[0].severity).toBe("high");
      },
    );
  });

  test("GRADIENT-TEXT NEGATIVE: solid ink headline", () => {
    withFile(
      "page.tsx",
      `<h1 className="text-5xl font-display tracking-tight">Hi</h1>`,
      (abs) => {
        const findings = scanFile(abs, [ruleById("GRADIENT-TEXT")]);
        expect(findings).toHaveLength(0);
      },
    );
  });

  // 2. GENERIC-DISPLAY-FONT (medium)
  test("GENERIC-DISPLAY-FONT POSITIVE: Inter import", () => {
    withFile(
      "layout.tsx",
      `import { Inter } from "next/font/google";\nconst inter = Inter({ subsets: ["latin"] });`,
      (abs) => {
        const findings = scanFile(abs, [ruleById("GENERIC-DISPLAY-FONT")]);
        expect(findings).toHaveLength(1);
      },
    );
  });

  test("GENERIC-DISPLAY-FONT NEGATIVE: distinctive face", () => {
    withFile(
      "layout.tsx",
      `import { Fraunces } from "next/font/google";\nconst f = Fraunces({ subsets: ["latin"] });`,
      (abs) => {
        const findings = scanFile(abs, [ruleById("GENERIC-DISPLAY-FONT")]);
        expect(findings).toHaveLength(0);
      },
    );
  });

  // 3. TRANSITION-ALL (low)
  test("TRANSITION-ALL POSITIVE: literal transition-all", () => {
    withFile(
      "btn.tsx",
      `<button className="transition-all duration-200 hover:opacity-90">x</button>`,
      (abs) => {
        const findings = scanFile(abs, [ruleById("TRANSITION-ALL")]);
        expect(findings).toHaveLength(1);
      },
    );
  });

  test("TRANSITION-ALL NEGATIVE: named property transition", () => {
    withFile(
      "btn.tsx",
      `<button className="transition-opacity duration-200 hover:opacity-90">x</button>`,
      (abs) => {
        const findings = scanFile(abs, [ruleById("TRANSITION-ALL")]);
        expect(findings).toHaveLength(0);
      },
    );
  });

  // 4. UNIFORM-HOVER-SCALE (low, ≥ 4 in same file)
  test("UNIFORM-HOVER-SCALE POSITIVE: 4 occurrences fire", () => {
    withFile(
      "cards.tsx",
      [
        `<a className="hover:scale-105">a</a>`,
        `<a className="hover:scale-105">b</a>`,
        `<a className="hover:scale-105">c</a>`,
        `<a className="hover:scale-105">d</a>`,
      ].join("\n"),
      (abs) => {
        const findings = scanFile(abs, [ruleById("UNIFORM-HOVER-SCALE")]);
        expect(findings).toHaveLength(1);
      },
    );
  });

  test("UNIFORM-HOVER-SCALE NEGATIVE: 3 occurrences below threshold", () => {
    withFile(
      "cards.tsx",
      [
        `<a className="hover:scale-105">a</a>`,
        `<a className="hover:scale-105">b</a>`,
        `<a className="hover:scale-105">c</a>`,
      ].join("\n"),
      (abs) => {
        const findings = scanFile(abs, [ruleById("UNIFORM-HOVER-SCALE")]);
        expect(findings).toHaveLength(0);
      },
    );
  });

  // 5. PLACEHOLDER-NAMES (low)
  test("PLACEHOLDER-NAMES POSITIVE: Jane Doe testimonial", () => {
    withFile(
      "testimonial.tsx",
      `<blockquote>"Soleur is great." — Jane Doe, CEO of Acme</blockquote>`,
      (abs) => {
        const findings = scanFile(abs, [ruleById("PLACEHOLDER-NAMES")]);
        expect(findings).toHaveLength(1);
      },
    );
  });

  test("PLACEHOLDER-NAMES NEGATIVE: real customer name", () => {
    withFile(
      "testimonial.tsx",
      `<blockquote>"Soleur is great." — Sarah Chen, CEO of Linear</blockquote>`,
      (abs) => {
        const findings = scanFile(abs, [ruleById("PLACEHOLDER-NAMES")]);
        expect(findings).toHaveLength(0);
      },
    );
  });
});

describe("frontend-anti-slop tier1-scan: per-file disable comment", () => {
  test("anti-slop:disable suppresses the named rule", () => {
    withFile(
      "intentional-gradient.tsx",
      `<!-- anti-slop:disable GRADIENT-TEXT reason="brand-mandated marketing hero gradient" -->\n<h1 className="bg-clip-text text-transparent bg-gradient-to-r from-purple-500 to-pink-500">Hi</h1>`,
      (abs) => {
        const findings = scanFile(abs, [ruleById("GRADIENT-TEXT")]);
        expect(findings).toHaveLength(0);
      },
    );
  });

  test("disabledRulesInFile parses multiple disable comments", () => {
    const src = `
      <!-- anti-slop:disable GRADIENT-TEXT reason="x" -->
      <!-- anti-slop:disable TRANSITION-ALL reason="y" -->
    `;
    const set = disabledRulesInFile(src);
    expect(set.has("GRADIENT-TEXT")).toBe(true);
    expect(set.has("TRANSITION-ALL")).toBe(true);
  });
});

describe("frontend-anti-slop tier1-scan: calibration baseline", () => {
  // Calibration fixture: setting-up-state.tsx uses `transition-all` at line 29
  // (intentional, designer-chosen — but exactly the pattern the gate flags).
  // The original plan §Phase 0.5 named gold-button.tsx; that file uses inline
  // `style={{ background: GOLD_GRADIENT }}` which no Tier 1 rule catches.
  // Swapping to setting-up-state.tsx preserves the spec AC4 contract ("real
  // project file produces ≥ 1 finding") with a fixture the rule set actually
  // exercises. Documented in /work Phase 0 deviation log.

  test("scanner emits ≥ 1 anti-slop finding on the calibration baseline file", () => {
    const repoRoot = resolve(import.meta.dir, "../../../..");
    const calibFile = resolve(
      repoRoot,
      "apps/web-platform/components/connect-repo/setting-up-state.tsx",
    );
    // Precondition: the calibration fixture must still contain a pattern
    // the rule set actually fires on. If a future refactor strips
    // `transition-all` from this file the calibration intent is lost — fail
    // fast here with a diagnostic that points at the fixture, not the
    // scanner. Update by either restoring the pattern OR picking a new
    // fixture and updating both this precondition + plan §"Calibration".
    const content = readFileSync(calibFile, "utf8");
    expect(
      content,
      `calibration fixture ${calibFile} no longer contains the \`transition-all\` token the TRANSITION-ALL rule keys on — refactor invalidated the calibration baseline. Either restore the pattern or pick a new fixture (and update the plan).`,
    ).toContain("transition-all");

    const findings = scanFile(calibFile, RULES);
    expect(findings.length).toBeGreaterThanOrEqual(1);
    expect(findings.every((f) => f.category === "anti-slop")).toBe(true);
    for (const f of findings) {
      // selector encodes as `<file>#<RULE-ID>` per the plan's Option (a) overload.
      expect(f.selector).toMatch(/.+#[A-Z][A-Z0-9-]*$/);
    }
  });
});

describe("frontend-anti-slop tier1-scan: rule parsing", () => {
  test("parseRules produces exactly 15 Tier 1 rules (binding from plan)", () => {
    expect(RULES).toHaveLength(15);
  });

  test("every parsed rule compiles a valid RegExp", () => {
    for (const r of RULES) {
      expect(r.pattern).toBeInstanceOf(RegExp);
      expect(r.severity).toMatch(/^(critical|high|medium|low)$/);
    }
  });
});
