import { describe, test, expect } from "bun:test";
import { mkdtempSync, writeFileSync, rmSync, mkdirSync } from "node:fs";
import { resolve, join } from "node:path";
import { tmpdir } from "node:os";
import {
  parseRules,
  scanFile,
  disabledRulesInFile,
  computeExitCode,
  expandPaths,
  DEFAULT_PATH_RE_SOURCE,
  RULES_FILE,
  REPO_ROOT,
} from "../../skills/frontend-anti-slop/scripts/tier1-scan";
import type { Finding } from "../../skills/frontend-anti-slop/scripts/tier1-scan";
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

  // 6. PURE-BW-BASE — calibrated 2026-05-21 (issue #4270 v1.1 tightening):
  // initial regex matched bg-black/bg-white anywhere in a className, producing
  // 6/6 FP on the prod tree (all hits were buttons, not root wrappers). The
  // tightened regex requires <html|body|main> elements OR co-occurrence with
  // a root-layout class (min-h-screen|min-h-dvh|h-screen) so a button's
  // bg-white never trips it but a page wrapper does.
  test("PURE-BW-BASE POSITIVE: html element with bg-black", () => {
    withFile(
      "layout.tsx",
      `<html className="bg-black text-white"><body>{children}</body></html>`,
      (abs) => {
        const findings = scanFile(abs, [ruleById("PURE-BW-BASE")]);
        expect(findings).toHaveLength(1);
      },
    );
  });

  test("PURE-BW-BASE POSITIVE: full-screen div wrapper with bg-black", () => {
    withFile(
      "page.tsx",
      `<div className="min-h-screen bg-black"><Hero /></div>`,
      (abs) => {
        const findings = scanFile(abs, [ruleById("PURE-BW-BASE")]);
        expect(findings).toHaveLength(1);
      },
    );
  });

  test("PURE-BW-BASE NEGATIVE: button with bg-white (the original FP class)", () => {
    withFile(
      "login.tsx",
      `<button className="w-full rounded-lg bg-white px-4 py-3 text-sm font-medium text-black hover:bg-neutral-200">Sign in</button>`,
      (abs) => {
        const findings = scanFile(abs, [ruleById("PURE-BW-BASE")]);
        expect(findings).toHaveLength(0);
      },
    );
  });

  test("PURE-BW-BASE NEGATIVE: icon with bg-white (no layout-class proximity)", () => {
    withFile(
      "icon.tsx",
      `<div className="h-8 w-8 rounded-full bg-white p-2"><Icon /></div>`,
      (abs) => {
        const findings = scanFile(abs, [ruleById("PURE-BW-BASE")]);
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
  // Calibration fixture: a dedicated test-only file at
  // `plugins/soleur/test/fixtures/frontend-anti-slop/calibration-baseline.tsx`
  // that deliberately contains a Tier 1 anti-pattern (`transition-all`).
  //
  // Originally pinned to a production file (gold-button.tsx in the plan,
  // then setting-up-state.tsx in PR #4265). Draining production findings
  // per the calibration window (#4270) removes the rule-keying token from
  // production code and invalidates the baseline. Decoupling via a dedicated
  // fixture lets the scanner's self-test stay green while findings drain.
  // See `knowledge-base/project/learnings/best-practices/2026-05-21-calibration-fixture-probe-and-markdown-table-pipe-escapes.md`.

  test("scanner emits ≥ 1 anti-slop finding on the calibration baseline file", () => {
    const repoRoot = resolve(import.meta.dir, "../../../..");
    const calibFile = resolve(
      repoRoot,
      "plugins/soleur/test/fixtures/frontend-anti-slop/calibration-baseline.tsx",
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
  test("parseRules produces exactly 18 Tier 1 rules (binding from plan)", () => {
    expect(RULES).toHaveLength(18);
  });

  test("every parsed rule compiles a valid RegExp", () => {
    for (const r of RULES) {
      expect(r.pattern).toBeInstanceOf(RegExp);
      expect(r.severity).toMatch(/^(critical|high|medium|low)$/);
    }
  });
});

describe("frontend-anti-slop tier1-scan: file-filter scope", () => {
  // Scope was widened to include `.njk` so the Eleventy marketing site
  // (plugins/soleur/docs/) is audited alongside the Next.js platform.
  // These tests lock the scope so a future refactor of `expandPaths` /
  // `listFilesRecursive` can't silently drop `.njk` and break the docs-site
  // audit path. See the SKILL.md "Scope" table and review/SKILL.md
  // "Anti-slop Scanner Hook" trigger regex — both share this same file-
  // extension set.

  test("scanFile on a .njk fixture is well-defined (rule fires when pattern matches)", () => {
    withFile(
      "landing.njk",
      `<a class="bg-clip-text text-transparent bg-gradient-to-r from-purple-500 to-blue-500">Try it</a>`,
      (abs) => {
        const findings = scanFile(abs, [ruleById("GRADIENT-TEXT")]);
        expect(findings).toHaveLength(1);
        expect(findings[0].selector).toMatch(/\.njk#GRADIENT-TEXT$/);
      },
    );
  });

  test("scanFile on a .njk fixture with no slop returns 0 (rule set tolerates non-Tailwind markup)", () => {
    withFile(
      "blog-post.njk",
      `{% extends "base.njk" %}\n{% block content %}<article class="prose">{{ body | safe }}</article>{% endblock %}`,
      (abs) => {
        const findings = scanFile(abs, RULES);
        expect(findings).toHaveLength(0);
      },
    );
  });
});

describe("frontend-anti-slop tier1-scan: brand rules (pos + neg fixtures)", () => {
  // All fixtures are SYNTHESISED inline (cq-test-fixtures-synthesized-only) —
  // never copied from app code. They mirror the incident shapes the plan cites
  // (Tailwind arbitrary `[#hex]`, inline `background: #hex`) without importing
  // any real production string.

  // BRAND-RAW-HEX (brand/high)
  test("BRAND-RAW-HEX POSITIVE: Tailwind arbitrary [#hex] flags high+brand", () => {
    withFile(
      "card.tsx",
      `<div className="bg-[#2563eb]/10 text-[#2563eb]">notice</div>`,
      (abs) => {
        const findings = scanFile(abs, [ruleById("BRAND-RAW-HEX")]);
        expect(findings).toHaveLength(1);
        expect(findings[0].selector).toMatch(/#BRAND-RAW-HEX$/);
        expect(findings[0].category).toBe("anti-slop"); // schema-safe emit
        expect(findings[0].severity).toBe("high");
        // the originating rule carries the brand discriminator
        expect(ruleById("BRAND-RAW-HEX").category).toBe("brand");
      },
    );
  });

  test("BRAND-RAW-HEX POSITIVE: inline style background: #hex flags", () => {
    withFile(
      "banner.tsx",
      `<span style={{ background: "#2563eb" }} />\n<style>{\`.x{background: #2563eb;}\`}</style>`,
      (abs) => {
        const findings = scanFile(abs, [ruleById("BRAND-RAW-HEX")]);
        expect(findings).toHaveLength(1);
        expect(findings[0].severity).toBe("high");
      },
    );
  });

  test("BRAND-RAW-HEX POSITIVE: SVG fill=\"#hex\" prop flags", () => {
    withFile(
      "icon.tsx",
      `<svg><path fill="#2563eb" /><circle stroke="#abc" /></svg>`,
      (abs) => {
        const findings = scanFile(abs, [ruleById("BRAND-RAW-HEX")]);
        expect(findings).toHaveLength(1);
        expect(findings[0].severity).toBe("high");
      },
    );
  });

  test("BRAND-RAW-HEX POSITIVE: React camelCase inline style flags", () => {
    withFile(
      "card.tsx",
      `<div style={{ backgroundColor: "#2563eb" }} />`,
      (abs) => {
        const findings = scanFile(abs, [ruleById("BRAND-RAW-HEX")]);
        expect(findings).toHaveLength(1);
        expect(findings[0].severity).toBe("high");
      },
    );
  });

  test("BRAND-RAW-HEX NEGATIVE: wired token / theme class yields 0", () => {
    withFile(
      "card.tsx",
      [
        `<div className="bg-soleur-accent-gold-fg text-forge-ink">ok</div>`,
        `<div style={{ color: "var(--soleur-accent)" }} />`,
        `const ACCENT = "#C9A962"; // bare assignment, not [#..] nor prop: #..`,
      ].join("\n"),
      (abs) => {
        const findings = scanFile(abs, [ruleById("BRAND-RAW-HEX")]);
        expect(findings).toHaveLength(0);
      },
    );
  });

  // BRAND-WHITE-ON-GOLD (brand/high)
  test("BRAND-WHITE-ON-GOLD POSITIVE: white text on gold surface flags high", () => {
    withFile(
      "cta.tsx",
      `<button className="bg-soleur-gold text-white">Buy</button>`,
      (abs) => {
        const findings = scanFile(abs, [ruleById("BRAND-WHITE-ON-GOLD")]);
        expect(findings).toHaveLength(1);
        expect(findings[0].severity).toBe("high");
        expect(ruleById("BRAND-WHITE-ON-GOLD").category).toBe("brand");
      },
    );
  });

  test("BRAND-WHITE-ON-GOLD NEGATIVE: forge-ink on gold passes", () => {
    withFile(
      "cta.tsx",
      `<button className="bg-soleur-gold text-forge-ink">Buy</button>`,
      (abs) => {
        const findings = scanFile(abs, [ruleById("BRAND-WHITE-ON-GOLD")]);
        expect(findings).toHaveLength(0);
      },
    );
  });

  test("BRAND-WHITE-ON-GOLD does NOT fire on the blue-incident text-white (isolated from BRAND-RAW-HEX)", () => {
    withFile(
      "banner.tsx",
      `<button className="bg-[#2563eb] text-white">Invite</button>`,
      (abs) => {
        const findings = scanFile(abs, [ruleById("BRAND-WHITE-ON-GOLD")]);
        expect(findings).toHaveLength(0);
      },
    );
  });

  // BRAND-NONZERO-CORNER (brand/medium)
  test("BRAND-NONZERO-CORNER POSITIVE: rounded-lg and border-radius: 8 flag medium", () => {
    withFile(
      "cta.tsx",
      `<button className="rounded-lg">x</button>\n<style>{\`.y{border-radius: 8px;}\`}</style>`,
      (abs) => {
        const findings = scanFile(abs, [ruleById("BRAND-NONZERO-CORNER")]);
        expect(findings).toHaveLength(1);
        expect(findings[0].severity).toBe("medium");
        expect(ruleById("BRAND-NONZERO-CORNER").category).toBe("brand");
      },
    );
  });

  test("BRAND-NONZERO-CORNER POSITIVE: fractional border-radius: 0.5rem flags", () => {
    withFile(
      "cta.tsx",
      `<style>{\`.z{border-radius: 0.5rem;}\`}</style>`,
      (abs) => {
        const findings = scanFile(abs, [ruleById("BRAND-NONZERO-CORNER")]);
        expect(findings).toHaveLength(1);
        expect(findings[0].severity).toBe("medium");
      },
    );
  });

  test("BRAND-NONZERO-CORNER NEGATIVE: rounded-none / border-radius: 0 passes", () => {
    withFile(
      "cta.tsx",
      `<button className="rounded-none">x</button>\n<style>{\`.y{border-radius: 0;}\`}</style>`,
      (abs) => {
        const findings = scanFile(abs, [ruleById("BRAND-NONZERO-CORNER")]);
        expect(findings).toHaveLength(0);
      },
    );
  });

  // Pipe-escape / compile round-trip — the 3 brand patterns embed `|`
  // alternations that MUST survive parseRules' `(?<!\\)\|` split + `\|`→`|`
  // unescape, or the row mis-splits and the regex compiles wrong.
  test("brand rule patterns round-trip the intended alternation (no \\| mis-split)", () => {
    expect(ruleById("BRAND-RAW-HEX").pattern.source).toContain(
      "(?:background|color|border|fill|stroke)",
    );
    expect(ruleById("BRAND-WHITE-ON-GOLD").pattern.source).toContain(
      "(?:gold|gradient|accent",
    );
    expect(ruleById("BRAND-NONZERO-CORNER").pattern.source).toContain(
      "border-radius",
    );
    // every brand rule compiled to a real RegExp
    for (const id of [
      "BRAND-RAW-HEX",
      "BRAND-WHITE-ON-GOLD",
      "BRAND-NONZERO-CORNER",
    ]) {
      expect(ruleById(id).pattern).toBeInstanceOf(RegExp);
    }
  });
});

describe("frontend-anti-slop tier1-scan: computeExitCode (blocking gate)", () => {
  function findingFor(ruleId: string, severity: Finding["severity"]): Finding {
    return {
      route: "",
      selector: `apps/web-platform/x.tsx#${ruleId}`,
      category: "anti-slop",
      severity,
      title: "t",
      description: "d",
      fix_hint: "f",
      screenshot_ref: "/tmp/anti-slop/no-screenshot.png",
      line: 1,
    };
  }

  test("brand+high finding → exit 1", () => {
    const findings = [findingFor("BRAND-RAW-HEX", "high")];
    expect(computeExitCode(findings, RULES)).toBe(1);
  });

  test("anti-slop-only findings → exit 0", () => {
    const findings = [
      findingFor("GRADIENT-TEXT", "high"),
      findingFor("TRANSITION-ALL", "low"),
    ];
    expect(computeExitCode(findings, RULES)).toBe(0);
  });

  test("brand-medium-only (BRAND-NONZERO-CORNER) → exit 0", () => {
    const findings = [findingFor("BRAND-NONZERO-CORNER", "medium")];
    expect(computeExitCode(findings, RULES)).toBe(0);
  });

  test("empty findings → exit 0", () => {
    expect(computeExitCode([], RULES)).toBe(0);
  });

  test("mixed: one brand+high among advisory → exit 1", () => {
    const findings = [
      findingFor("TRANSITION-ALL", "low"),
      findingFor("BRAND-WHITE-ON-GOLD", "high"),
      findingFor("BRAND-NONZERO-CORNER", "medium"),
    ];
    expect(computeExitCode(findings, RULES)).toBe(1);
  });

  test("brand+high finding whose file path contains '#' still blocks (no fail-open)", () => {
    // Regression: the rule id is the LAST '#'-segment of the selector. A
    // scanned path that itself contains '#' must NOT defeat the gate by
    // capturing a path fragment as the rule id.
    const finding: Finding = {
      route: "",
      selector: "apps/web-platform/app/we#ird/x.tsx#BRAND-RAW-HEX",
      category: "anti-slop",
      severity: "high",
      title: "t",
      description: "d",
      fix_hint: "f",
      screenshot_ref: "/tmp/anti-slop/no-screenshot.png",
      line: 1,
    };
    expect(computeExitCode([finding], RULES)).toBe(1);
  });

  test("selector with no '#' → non-blocking (exit 0, no throw)", () => {
    const finding: Finding = {
      route: "",
      selector: "apps/web-platform/app/x.tsx",
      category: "anti-slop",
      severity: "high",
      title: "t",
      description: "d",
      fix_hint: "f",
      screenshot_ref: "/tmp/anti-slop/no-screenshot.png",
      line: 1,
    };
    expect(computeExitCode([finding], RULES)).toBe(0);
  });
});

describe("frontend-anti-slop tier1-scan: path-scope regex (route-group + server)", () => {
  const RE = new RegExp(DEFAULT_PATH_RE_SOURCE);

  test("DEFAULT_PATH_RE_SOURCE matches route-group + dynamic-segment paths", () => {
    expect(
      RE.test("apps/web-platform/app/(public)/invite/[token]/page.tsx"),
    ).toBe(true);
    expect(
      RE.test("apps/web-platform/app/(public)/invite/[token]/invite-actions.tsx"),
    ).toBe(true);
  });

  test("DEFAULT_PATH_RE_SOURCE matches server-side .ts templates (scope extension)", () => {
    expect(RE.test("apps/web-platform/server/notifications.ts")).toBe(true);
    expect(RE.test("apps/web-platform/server/email/template.tsx")).toBe(true);
  });

  test("DEFAULT_PATH_RE_SOURCE still matches docs-site .njk/.css", () => {
    expect(RE.test("plugins/soleur/docs/index.njk")).toBe(true);
    expect(RE.test("plugins/soleur/docs/css/style.css")).toBe(true);
  });

  test("DEFAULT_PATH_RE_SOURCE rejects out-of-scope paths", () => {
    expect(RE.test("apps/web-platform/lib/feature-flags/server.ts")).toBe(false);
    expect(RE.test("packages/foo/bar.tsx")).toBe(false);
  });
});

describe("frontend-anti-slop tier1-scan: ReDoS line cap", () => {
  // BRAND-WHITE-ON-GOLD's `[^"\n]*` spans can backtrack O(n²) on a single long
  // line, and minified .css (one line, hundreds of KB) is in scope. scanFile
  // truncates each line to MAX_SCAN_LINE before matching, bounding the work.
  test("scanFile on a ~300KB single line completes quickly (line cap bounds work)", () => {
    withFile("minified.css", "gold ".repeat(60000), (abs) => {
      const start = Date.now();
      const findings = scanFile(abs, [ruleById("BRAND-WHITE-ON-GOLD")]);
      const elapsed = Date.now() - start;
      expect(Array.isArray(findings)).toBe(true);
      // The cap makes this bounded; an unbounded scan would hang. Generous
      // ceiling to avoid CI flakiness while still catching a regression to
      // pathological backtracking.
      expect(elapsed).toBeLessThan(2000);
    });
  });
});

describe("frontend-anti-slop tier1-scan: expandPaths scope post-filter", () => {
  // expandPaths must agree with DEFAULT_PATH_RE_SOURCE by construction — the
  // bare extension filter admits `.ts` anywhere, but only server/ `.ts` is in
  // scope. An out-of-scope api route.ts must be dropped even though it exists.
  test("out-of-scope app/api route.ts → [] (scope post-filter rejects)", () => {
    const result = expandPaths(["apps/web-platform/app/api/conversations/route.ts"]);
    expect(result).toEqual([]);
  });

  test("in-scope server/*.ts is admitted", () => {
    const result = expandPaths(["apps/web-platform/server/notifications.ts"]);
    expect(result).toContain(
      resolve(REPO_ROOT, "apps/web-platform/server/notifications.ts"),
    );
  });
});

describe("frontend-anti-slop tier1-scan: review/SKILL.md hook path parity", () => {
  // The review/SKILL.md anti-slop hook's shell-ERE path regex must stay in
  // lockstep with DEFAULT_PATH_RE_SOURCE (single source of truth). Assert the
  // hook block contains the same server alternation body.
  test("review/SKILL.md hook EXT_RE alternation body EQUALS DEFAULT_PATH_RE_SOURCE inner body", () => {
    const skillPath = resolve(
      import.meta.dir,
      "../../skills/review/SKILL.md",
    );
    const skill = readFileSync(skillPath, "utf8");

    // Extract the EXT_RE value from the SKILL.md hook block:
    //   EXT_RE='(...alternation...)$'
    const m = skill.match(/EXT_RE='([^']*)'/);
    expect(m).not.toBeNull();
    const extRe = m![1];

    // Strip the JS `^...$` anchors from DEFAULT_PATH_RE_SOURCE and the trailing
    // `$` from the shell EXT_RE, then compare the alternation bodies for
    // equality. A reorder or partial drop in either side fails this — not just
    // a dropped substring.
    const jsBody = DEFAULT_PATH_RE_SOURCE.replace(/^\^/, "").replace(/\$$/, "");
    const shellBody = extRe.replace(/\$$/, "");
    expect(shellBody).toBe(jsBody);
  });

  test("review/SKILL.md hook no longer uses grep -z (ugrep --decompress footgun)", () => {
    const skillPath = resolve(
      import.meta.dir,
      "../../skills/review/SKILL.md",
    );
    const skill = readFileSync(skillPath, "utf8");
    // The collector must use the NUL-safe `read -r -d ''` loop (newline-safe,
    // ugrep-proof) and must NOT use grep -z (ugrep `-z` is --decompress, the
    // #4635 false-clean) anywhere.
    expect(skill).not.toContain("grep -z");
    expect(skill).toContain("read -r -d ''");
  });
});
