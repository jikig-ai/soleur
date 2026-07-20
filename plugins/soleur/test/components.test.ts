import { describe, test, expect } from "bun:test";
import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import {
  discoverAgents,
  discoverCommands,
  discoverSkills,
  parseComponent,
  getComponentName,
  PLUGIN_ROOT,
} from "./helpers";

const VALID_MODELS = ["inherit", "haiku", "sonnet", "opus", "fable"];
const KEBAB_CASE = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const SKILL_DESCRIPTION_WORD_BUDGET = 2366; // see #618; bumped +50 for #2725, bumped +100 for #4341, bumped +34 for #4742 (trigger-cron skill description, 34 words, against a 1950/1950 zero-headroom baseline), bumped +25 for #5021 (feature-tweet skill description, 25 words, against a 1984/1984 zero-headroom baseline), bumped +32 for #5100 (model-launch-review skill description, 33 words, against a 2008/2009 one-word-headroom baseline), bumped +30 for #5085 (operator-digest skill description, 30 words, against a 2041/2041 zero-headroom baseline), bumped +126 for #5318 (flag-list/flag-delete/cron-list/cron-delete skill descriptions, 33+37+27+29 words, against a 2071/2071 zero-headroom baseline), bumped +25 for #5349 (harvest-debt skill description, 25 words, against a 2197/2197 zero-headroom baseline), bumped +28 for #5358 (eval-harness skill description, 28 words, against a 2222/2222 zero-headroom baseline), bumped +18 for #5755 (product-roadmap validate/next sub-command routing, against a 2250/2250 zero-headroom baseline), bumped +24 for #5765 (constraint-scaffold skill description, 24 words, against a 2268/2268 zero-headroom baseline), bumped +35 for #5810 (drain-prs skill description, 35 words, against a 2292/2292 zero-headroom baseline), bumped +39 for #6260 (invoice skill description, 39 words, against a 2327/2327 zero-headroom baseline)
const SKILL_DESCRIPTION_CHAR_LIMIT = 1024;

// ---------------------------------------------------------------------------
// Agent Frontmatter
// ---------------------------------------------------------------------------

describe("Agent frontmatter", () => {
  const agents = discoverAgents();

  test("discovers agents", () => {
    expect(agents.length).toBeGreaterThan(0);
  });

  for (const agentPath of agents) {
    describe(agentPath, () => {
      const { frontmatter, body } = parseComponent(agentPath);

      test("has frontmatter", () => {
        expect(Object.keys(frontmatter).length).toBeGreaterThan(0);
      });

      test("has name field", () => {
        expect(frontmatter.name).toBeDefined();
        expect(String(frontmatter.name).length).toBeGreaterThan(0);
      });

      test("has description field", () => {
        expect(frontmatter.description).toBeDefined();
        expect(String(frontmatter.description).length).toBeGreaterThan(0);
      });

      test("has valid model field", () => {
        expect(frontmatter.model).toBeDefined();
        expect(VALID_MODELS).toContain(frontmatter.model);
      });

      test("description does not contain <example> block", () => {
        const desc = String(frontmatter.description);
        expect(desc).not.toContain("<example>");
      });

      test("has non-empty body", () => {
        expect(body.trim().length).toBeGreaterThan(0);
      });
    });
  }
});

// ---------------------------------------------------------------------------
// Command Frontmatter
// ---------------------------------------------------------------------------

describe("Command frontmatter", () => {
  const commands = discoverCommands();

  test("discovers commands", () => {
    expect(commands.length).toBeGreaterThan(0);
  });

  for (const cmdPath of commands) {
    describe(cmdPath, () => {
      const { frontmatter, body } = parseComponent(cmdPath);

      test("has frontmatter", () => {
        expect(Object.keys(frontmatter).length).toBeGreaterThan(0);
      });

      test("has name field", () => {
        expect(frontmatter.name).toBeDefined();
        expect(String(frontmatter.name).length).toBeGreaterThan(0);
      });

      test("has description field", () => {
        expect(frontmatter.description).toBeDefined();
        expect(String(frontmatter.description).length).toBeGreaterThan(0);
      });

      test("has argument-hint field", () => {
        expect("argument-hint" in frontmatter).toBe(true);
      });

      test("has non-empty body", () => {
        expect(body.trim().length).toBeGreaterThan(0);
      });
    });
  }
});

// ---------------------------------------------------------------------------
// Skill Frontmatter
// ---------------------------------------------------------------------------

describe("Skill frontmatter", () => {
  const skills = discoverSkills();

  test("discovers skills", () => {
    expect(skills.length).toBeGreaterThan(0);
  });

  for (const skillPath of skills) {
    describe(skillPath, () => {
      const { frontmatter, body } = parseComponent(skillPath);

      test("has frontmatter", () => {
        expect(Object.keys(frontmatter).length).toBeGreaterThan(0);
      });

      test("has name field", () => {
        expect(frontmatter.name).toBeDefined();
        expect(String(frontmatter.name).length).toBeGreaterThan(0);
      });

      test("has description field", () => {
        expect(frontmatter.description).toBeDefined();
        expect(String(frontmatter.description).length).toBeGreaterThan(0);
      });

      test("has non-empty body", () => {
        expect(body.trim().length).toBeGreaterThan(0);
      });
    });
  }
});

// ---------------------------------------------------------------------------
// Skill description budget (prevents context compaction skill loss, see #618)
// ---------------------------------------------------------------------------

describe("Skill description budget", () => {
  const skills = discoverSkills();

  test("cumulative description word count under budget", () => {
    const counts: { path: string; words: number }[] = [];
    let totalWords = 0;
    for (const skillPath of skills) {
      const { frontmatter } = parseComponent(skillPath);
      const desc = String(frontmatter.description || "");
      const words = desc.split(/\s+/).filter(Boolean).length;
      counts.push({ path: skillPath, words });
      totalWords += words;
    }
    if (totalWords > SKILL_DESCRIPTION_WORD_BUDGET) {
      const top5 = counts.sort((a, b) => b.words - a.words).slice(0, 5);
      const detail = top5.map((s) => `  ${s.path}: ${s.words} words`).join("\n");
      throw new Error(
        `Budget exceeded: ${totalWords}/${SKILL_DESCRIPTION_WORD_BUDGET} words.\nTop offenders:\n${detail}`,
      );
    }
  });

  for (const skillPath of skills) {
    test(`${skillPath} description under ${SKILL_DESCRIPTION_CHAR_LIMIT} chars`, () => {
      const { frontmatter } = parseComponent(skillPath);
      const desc = String(frontmatter.description || "");
      expect(desc.length).toBeLessThanOrEqual(SKILL_DESCRIPTION_CHAR_LIMIT);
    });
  }
});

// ---------------------------------------------------------------------------
// Convention: Third-person voice in skill descriptions
// ---------------------------------------------------------------------------

describe("Skill description voice", () => {
  const skills = discoverSkills();

  for (const skillPath of skills) {
    test(`${skillPath} starts with "This skill"`, () => {
      const { frontmatter } = parseComponent(skillPath);
      const desc = String(frontmatter.description || "");
      expect(desc.startsWith("This skill")).toBe(true);
    });
  }
});

// ---------------------------------------------------------------------------
// Convention: Kebab-case filenames
// ---------------------------------------------------------------------------

describe("Kebab-case filenames", () => {
  const agents = discoverAgents();
  const commands = discoverCommands();
  const skills = discoverSkills();

  for (const agentPath of agents) {
    const name = getComponentName(agentPath, "agent");
    test(`agent ${name} is kebab-case`, () => {
      expect(name).toMatch(KEBAB_CASE);
    });
  }

  for (const cmdPath of commands) {
    const name = getComponentName(cmdPath, "command");
    test(`command ${name} is kebab-case`, () => {
      expect(name).toMatch(KEBAB_CASE);
    });
  }

  for (const skillPath of skills) {
    const name = getComponentName(skillPath, "skill");
    test(`skill ${name} is kebab-case`, () => {
      expect(name).toMatch(KEBAB_CASE);
    });
  }
});

// ---------------------------------------------------------------------------
// Convention: No backtick references to references/, assets/, scripts/
// ---------------------------------------------------------------------------

describe("No backtick file references in skills", () => {
  const skills = discoverSkills();

  for (const skillPath of skills) {
    test(`${skillPath} uses markdown links, not backticks`, () => {
      const { body } = parseComponent(skillPath);
      const backtickRefs = body.match(/`(?:references|assets|scripts)\/[^`]+`/g);
      expect(backtickRefs).toBeNull();
    });
  }
});

// ---------------------------------------------------------------------------
// Autonomous-loop skills must disclose API budget (#3819)
// ---------------------------------------------------------------------------

describe("Autonomous-loop API-budget disclosure", () => {
  const AUTONOMOUS_LOOP_SKILLS = [
    "test-fix-loop",
    "drain-labeled-backlog",
    "resolve-todo-parallel",
    "resolve-pr-parallel",
    "work",
    "one-shot",
    "eval-harness",
  ];

  // Sentinel chosen for distinctiveness + verbatim across all 7 disclosures.
  // Tracks the BSL 1.1 disclaimer carried over from `goal-primitive.md`.
  const SENTINEL = "disclaims warranty for runtime cost";

  for (const skillName of AUTONOMOUS_LOOP_SKILLS) {
    test(`${skillName} carries API-budget <decision_gate> disclosure`, () => {
      const skillPath = resolve(PLUGIN_ROOT, "skills", skillName, "SKILL.md");
      const raw = readFileSync(skillPath, "utf-8");

      const gateBlocks = raw.match(/<decision_gate>[\s\S]*?<\/decision_gate>/g) ?? [];

      expect(
        gateBlocks.length,
        `${skillName} has no <decision_gate> block`,
      ).toBeGreaterThan(0);

      const hasDisclosure = gateBlocks.some((b) => b.includes(SENTINEL));
      expect(
        hasDisclosure,
        `${skillName} <decision_gate> blocks do not contain API-budget sentinel "${SENTINEL}". ` +
          `Each autonomous-loop skill must disclose the per-iteration cost model and Soleur/Anthropic billing split.`,
      ).toBe(true);
    });
  }
});

// ---------------------------------------------------------------------------
// Decision-principles taxonomy drift guard (#5984 / ADR-084)
// ---------------------------------------------------------------------------
// Orphan guard: the reference doc must exist and every consumer must link it
// (markdown-link form). Renaming/moving the doc without updating a consumer, or
// dropping the ship render/action-required wiring, fails here. No content-presence
// assertions — those pass by construction and false-fail on a good-faith reword.

describe("Decision-principles taxonomy wiring", () => {
  const DOC_REL = "skills/brainstorm-techniques/references/decision-principles.md";
  // Every consumer must reference the doc; markdown-link form only (backtick refs
  // are separately forbidden by "No backtick file references in skills").
  const CONSUMERS = ["brainstorm-techniques", "plan", "work", "ship", "plan-review"];
  const LINK_RE = /\]\([^)]*decision-principles\.md\)/;

  test("decision-principles.md exists", () => {
    expect(
      existsSync(resolve(PLUGIN_ROOT, DOC_REL)),
      `${DOC_REL} is missing — the ADR-084 taxonomy primitive.`,
    ).toBe(true);
  });

  for (const skillName of CONSUMERS) {
    test(`${skillName} links decision-principles.md`, () => {
      const raw = readFileSync(resolve(PLUGIN_ROOT, "skills", skillName, "SKILL.md"), "utf-8");
      expect(
        LINK_RE.test(raw),
        `${skillName}/SKILL.md does not link decision-principles.md via a markdown link — ` +
          `the taxonomy consumer wiring drifted.`,
      ).toBe(true);
    });
  }

  test("ship renders the challenge record + files the action-required issue", () => {
    const raw = readFileSync(resolve(PLUGIN_ROOT, "skills", "ship", "SKILL.md"), "utf-8");
    // The legible-surface wiring (ADR-084 §5): ship reads the artifact, renders it,
    // and opens the action-required + decision-challenge issue operator-digest harvests.
    for (const token of ["decision-challenges.md", "action-required", "decision-challenge"]) {
      expect(
        raw.includes(token),
        `ship/SKILL.md lost the "${token}" wiring — headless decision challenges would ` +
          `no longer reach the operator (regresses ADR-084's legible surface).`,
      ).toBe(true);
    }
  });
});

// ---------------------------------------------------------------------------
// invoice skill credential-boundary defense-in-depth (ADR-107 / #6260)
// ---------------------------------------------------------------------------
// Skill `allowed-tools` is pre-approval only, not a sandbox. The invoice skill's
// credential boundary (never read STRIPE_SECRET_KEY/.env/lib/stripe.ts) rests on
// two committed layers: `disallowed-tools` in the SKILL.md (per-turn tool removal)
// and a `Read` deny in .claude/settings.json (cross-turn). A future edit dropping
// either silently re-opens the exfiltration residual — this guard fails CI first.

describe("invoice skill credential boundary (ADR-107)", () => {
  test("invoice SKILL.md retains disallowed-tools Bash Read Write Edit", () => {
    const { frontmatter } = parseComponent(
      resolve(PLUGIN_ROOT, "skills", "invoice", "SKILL.md"),
    );
    // YAML parses `disallowed-tools: Bash Read Write Edit` as the scalar string;
    // a YAML-list form parses as an array — accept either shape.
    const raw = frontmatter["disallowed-tools"];
    const tokens = Array.isArray(raw)
      ? raw.map(String)
      : String(raw ?? "").split(/[\s,]+/).filter(Boolean);
    for (const t of ["Bash", "Read", "Write", "Edit"]) {
      expect(
        tokens.includes(t),
        `invoice/SKILL.md disallowed-tools must contain "${t}" (ADR-107 layer 2 — ` +
          `per-turn removal of the exfiltration tools). Got: ${JSON.stringify(raw)}`,
      ).toBe(true);
    }
  });

  test(".claude/settings.json retains the secret-file Read deny globs", () => {
    const settingsPath = resolve(PLUGIN_ROOT, "..", "..", ".claude", "settings.json");
    const settings = JSON.parse(readFileSync(settingsPath, "utf-8"));
    const deny: string[] = settings?.permissions?.deny ?? [];
    for (const glob of ["Read(**/.env)", "Read(**/.env.*)", "Read(**/lib/stripe.ts)"]) {
      expect(
        deny.includes(glob),
        `.claude/settings.json permissions.deny must contain "${glob}" (ADR-107 layer 3 — ` +
          `cross-turn Read deny protecting the product Stripe credential). Got: ${JSON.stringify(deny)}`,
      ).toBe(true);
    }
  });
});

// ---------------------------------------------------------------------------
// gh --search probes must pin --state explicitly (#6786)
// ---------------------------------------------------------------------------

// Captures a `gh pr|issue list ...` command from the point the binary is named
// to the end of its enclosing backtick span. The leading `[^`]*?` is load-bearing:
// probes are frequently embedded in a shell assignment (`EXISTING=$(gh pr list …)`),
// so anchoring the capture at the span's opening backtick would silently skip them.
const GH_LIST_CMD = /`[^`]*?(gh (?:pr|issue) list [^`]*)`/g;

/** Every `gh pr|issue list` command carrying `--search`, extracted from backtick spans. */
export function extractSearchProbes(
  files: { file: string; raw: string }[],
): { file: string; cmd: string }[] {
  return files.flatMap(({ file, raw }) =>
    [...raw.matchAll(GH_LIST_CMD)]
      .map((m) => ({ file, cmd: m[1] }))
      .filter(({ cmd }) => /--search\b/.test(cmd)),
  );
}

/** Search probes that omit an explicit `--state` — the #6786 silent-open defect class. */
export function findStatelessProbes(
  files: { file: string; raw: string }[],
): { file: string; cmd: string }[] {
  return extractSearchProbes(files).filter(({ cmd }) => !/--state\b/.test(cmd));
}

describe("collision-gate probes carry an explicit --state", () => {
  // Permanent negative controls — synthesized fixtures, no file I/O
  // (cq-test-fixtures-synthesized-only). These keep the detector honest even if
  // every real call site is compliant, so the gate can never go vacuously green.
  test("detector flags a stateless probe", () => {
    expect(
      findStatelessProbes([
        { file: "f", raw: '`gh pr list --search "#1 in:body is:merged" --json number`' },
      ]),
    ).toHaveLength(1);
  });

  test("detector accepts a state-explicit probe", () => {
    expect(
      findStatelessProbes([
        { file: "f", raw: '`gh pr list --search "#1 in:body" --state merged --json number`' },
      ]),
    ).toHaveLength(0);
  });

  test("detector sees a probe wrapped in a shell assignment", () => {
    expect(
      findStatelessProbes([
        { file: "f", raw: '`X=$(gh pr list --search "head:foo" --json url --jq \'.[0]\')`' },
      ]),
    ).toHaveLength(1);
  });

  test("detector ignores a --state flag that precedes --search", () => {
    expect(
      findStatelessProbes([
        { file: "f", raw: '`gh issue list --state closed --search "topic"`' },
      ]),
    ).toHaveLength(0);
  });

  const files = discoverSkills().map((f) => ({
    file: f,
    raw: readFileSync(resolve(PLUGIN_ROOT, f), "utf-8"),
  }));

  // Anti-vacuity: a broken glob or a drifted regex must red-line here rather than
  // emptying the population and turning the offender assertion green for free.
  test("probe population is non-empty", () => {
    expect(
      extractSearchProbes(files).length,
      "no `gh pr|issue list --search` commands found in skills/*/SKILL.md — " +
        "the glob or the extraction regex broke, so the offender check below is vacuous",
    ).toBeGreaterThan(0);
  });

  test("no skill probe omits --state", () => {
    expect(
      findStatelessProbes(files).map((o) => `${o.file}: ${o.cmd.slice(0, 70)}`),
      "`gh pr list --search` defaults to --state open and appends that filter unless it " +
        "detects an in-query state qualifier, so a probe without an explicit --state " +
        "silently misses MERGED PRs and the collision gate fails open. See #6786.",
    ).toEqual([]);
  });
});
