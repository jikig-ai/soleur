import { describe, test, expect } from "bun:test";
import { Glob } from "bun";
import { readFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { resolve } from "node:path";
import {
  discoverAgents,
  discoverCommands,
  discoverSkills,
  parseComponent,
  getComponentName,
  discoverSkillsIn,
  isUserInvocable,
  collidingNames,
  unackedDuplicates,
  normalizeSkillRoot,
  PLUGIN_ROOT,
} from "./helpers";

const VALID_MODELS = ["inherit", "haiku", "sonnet", "opus", "fable"];
const KEBAB_CASE = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const SKILL_DESCRIPTION_WORD_BUDGET = 2436; // lowered -7 for #10550 (WikiSkill Phase 2: five human-reviewed description trims on invoice, drain-prs, trigger-cron, reproduce-bug and docs-site free 30 words, 2436 -> 2406 measured through discoverSkills()/parseComponent(); the cap is LOWERED to the pre-trim measured total so the freed 30 words are a reserve for gated new-skill creation and total words never exceed 2436; 2443 -> 2436). Earlier history: // bumped +30 for #10404 (verification-scaffold skill description, 28 words measured through discoverSkills()/parseComponent(), +2 headroom, against a 2413/2413 zero-headroom baseline). Earlier history: // bumped +24 for #8880 (cohort-status skill description, 24 words measured through discoverSkills()/parseComponent(), against a 2389/2389 zero-headroom baseline). Earlier history: // see #618; bumped +50 for #2725, bumped +100 for #4341, bumped +34 for #4742 (trigger-cron skill description, 34 words, against a 1950/1950 zero-headroom baseline), bumped +25 for #5021 (feature-tweet skill description, 25 words, against a 1984/1984 zero-headroom baseline), bumped +32 for #5100 (model-launch-review skill description, 33 words, against a 2008/2009 one-word-headroom baseline), bumped +30 for #5085 (operator-digest skill description, 30 words, against a 2041/2041 zero-headroom baseline), bumped +126 for #5318 (flag-list/flag-delete/cron-list/cron-delete skill descriptions, 33+37+27+29 words, against a 2071/2071 zero-headroom baseline), bumped +25 for #5349 (harvest-debt skill description, 25 words, against a 2197/2197 zero-headroom baseline), bumped +28 for #5358 (eval-harness skill description, 28 words, against a 2222/2222 zero-headroom baseline), bumped +18 for #5755 (product-roadmap validate/next sub-command routing, against a 2250/2250 zero-headroom baseline), bumped +24 for #5765 (constraint-scaffold skill description, 24 words, against a 2268/2268 zero-headroom baseline), bumped +35 for #5810 (drain-prs skill description, 35 words, against a 2292/2292 zero-headroom baseline), bumped +39 for #6260 (invoice skill description, 39 words, against a 2327/2327 zero-headroom baseline), bumped +34 for #6755 (cf-token-scope skill description, 34 words, against a 2366/2366 zero-headroom baseline), bumped +42 for Devin entry-command skill descriptions (go 17 + sync 15 + help 10 words, against a 2400/2400 zero-headroom baseline), bumped +27 for #8287 (operator-rephrase skill description, 27 words measured through discoverSkills()/parseComponent(), against a 2442/2442 zero-headroom baseline), bumped +30 for #8287 (operator-bootstrap skill description, 30 words measured the same way, against a 2469/2469 zero-headroom baseline), bumped +62 for #8289 (kb-glossary 28 + questionnaire-generate 34 words measured through discoverSkills()/parseComponent(), against a 2499/2499 zero-headroom baseline), lowered -172 for #8290 (8 skills moved to disable-model-invocation; flag-create, flag-set-role, cron-list and cron-delete stay model-invocable per review; counted words are model-visible only, ADR-236; 2561 -> 2389 measured through discoverSkills()/parseComponent())
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
      // Count what the model sees (ADR-236): a user-invoked skill's description is absent from
      // the model's skill listing, so it spends none of this budget. Filter BEFORE summing.
      if (frontmatter["disable-model-invocation"] === true) continue;
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
// Every references/*.md is REACHABLE from its skill (#8302 review F4)
// ---------------------------------------------------------------------------
//
// The byte ratchet (scripts/lint-skill-body-budget.py) is one-sided: shrinking a
// SKILL.md never reds. Its own failure text prescribes "extract a block into
// references/ behind a load directive" -- and review measured that deleting the
// directive plan/SKILL.md carries for references/plan-sharp-edges.md (151 KB)
// reddened NOTHING: the extracted file became an orphan silently, which is
// ADR-151's "appears enforced, is absent" produced by the mechanism meant to
// contain prompt weight. Every future extraction inherits the gap unless
// something pins reachability. This does: each references/*.md must be named
// (by basename) from at least one other file in its skill directory.
describe("references/ files are reachable from their skill", () => {
  // Pre-existing orphan at the introduction of this guard, NOT created by it.
  // Only a legal-normalise fixture names it. Exact-count ledger: it may shrink
  // (delete or link the file) and never grow.
  const KNOWN_ORPHANS = new Set(["skill-security-scan/references/disclaimer.md"]);
  const skillsDir = resolve(PLUGIN_ROOT, "skills");
  const rows: Array<{ rel: string; linked: boolean }> = [];
  for (const skill of readdirSync(skillsDir)) {
    const refDir = resolve(skillsDir, skill, "references");
    if (!existsSync(refDir)) continue;
    for (const f of readdirSync(refDir)) {
      if (!f.endsWith(".md")) continue;
      const rel = `${skill}/references/${f}`;
      // Every other file in the skill dir, any extension, one level of
      // nesting (SKILL.md, sibling references, scripts, workflows).
      const haystack: string[] = [];
      const walk = (d: string, depth: number) => {
        for (const e of readdirSync(d, { withFileTypes: true })) {
          const full = resolve(d, e.name);
          if (e.isDirectory()) { if (depth < 2) walk(full, depth + 1); continue; }
          if (full === resolve(refDir, f)) continue;
          haystack.push(readFileSync(full, "utf-8"));
        }
      };
      walk(resolve(skillsDir, skill), 0);
      rows.push({ rel, linked: haystack.some((t) => t.includes(f)) });
    }
  }

  test("the census reached a non-trivial population", () => {
    // Non-vacuity: this guard is only evidence if it actually walked the
    // references it claims to. plan-sharp-edges.md is the file the guard was
    // written for and MUST be in the population.
    expect(rows.length).toBeGreaterThanOrEqual(20);
    expect(rows.map((r) => r.rel)).toContain("plan/references/plan-sharp-edges.md");
  });

  test("every references/*.md is named from its skill, except the pinned pre-existing orphans", () => {
    const orphans = rows.filter((r) => !r.linked).map((r) => r.rel).sort();
    expect(orphans).toEqual([...KNOWN_ORPHANS].sort());
  });
});

// ---------------------------------------------------------------------------
// Autonomous-loop skills must disclose API budget (#3819)
// ---------------------------------------------------------------------------

// Shared by the API-budget and pipeline-tally sentinels — one list, never two
// (#9403 review: a duplicated list silently diverges on the next loop skill).
const AUTONOMOUS_LOOP_SKILLS = [
  "test-fix-loop",
  "drain-labeled-backlog",
  "resolve-todo-parallel",
  "resolve-pr-parallel",
  "work",
  "one-shot",
  "eval-harness",
];

describe("Autonomous-loop API-budget disclosure", () => {

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
// Autonomous-loop skills must carry the pipeline-tally call-out (#9403)
// ---------------------------------------------------------------------------
// Prose-only bookkeeping has ~zero compliance — the tally only exists if every
// autonomous loop invokes the counter script. This sentinel pins the anchored
// call forms: each skill must `init`, `gate` (pre-expensive-step), and `incr`
// via scripts/pipeline-tally.sh. review/ship are instrumented alongside the
// loop list (review seats; ship ci_cycles + the ## Pipeline Tally render).

describe("Autonomous-loop pipeline-tally call-out (#9403)", () => {
  // review (seats) and ship (ci_cycles + render) are instrumented alongside the
  // loop list — the sentinel covers all nine skills.
  const TALLY_SKILLS = [...AUTONOMOUS_LOOP_SKILLS, "review", "ship"];

  // Loop until stable — a nested `<!-- <!-- --> -->` can splice neighbours into
  // a fresh comment (CodeQL incomplete-multi-character-sanitization); a
  // comment-only mention must NOT satisfy the call-form assertions below.
  const stripHtmlComments = (raw: string) => {
    let out = raw;
    let prev: string;
    do {
      prev = out;
      out = out.replace(/<!--[\s\S]*?-->/g, "");
    } while (out !== prev);
    return out;
  };

  // The qualified invocation is the contract — `pipeline-tally.sh` copied
  // bare resolves to `command not found`, and the fail-open design makes that
  // a SILENT skip. `[ \t]+` (not `\s+`) keeps the subcommand on the same line.
  const CALL_FORMS = [
    /scripts\/pipeline-tally\.sh"?[ \t]+init\b/, // init invocation
    /scripts\/pipeline-tally\.sh"?[ \t]+gate\b/, // gate before expensive steps
    /scripts\/pipeline-tally\.sh"?[ \t]+incr\b/, // incr <dim> call form
  ];

  for (const skillName of TALLY_SKILLS) {
    test(`${skillName} SKILL.md carries pipeline-tally init/gate/incr call forms`, () => {
      const raw = stripHtmlComments(
        readFileSync(
          resolve(PLUGIN_ROOT, "skills", skillName, "SKILL.md"),
          "utf-8",
        ),
      );
      for (const re of CALL_FORMS) {
        expect(
          re.test(raw),
          `${skillName} is missing tally call form ${re.source} — every autonomous loop must ` +
            `invoke scripts/pipeline-tally.sh (init at start, gate before expensive steps, ` +
            `incr per counted op). Removing or renaming the call defeats the running tally (#9403).`,
        ).toBe(true);
      }
    });
  }

  test("review SKILL.md counts seats via pipeline-tally incr", () => {
    const raw = stripHtmlComments(readFileSync(resolve(PLUGIN_ROOT, "skills", "review", "SKILL.md"), "utf-8"));
    expect(
      /scripts\/pipeline-tally\.sh"?[ \t]+incr[ \t]+seats/.test(raw),
      "review must `incr seats <N>` after spawning its panel (#9403)",
    ).toBe(true);
  });

  test("ship SKILL.md renders ## Pipeline Tally in BOTH PR-body templates", () => {
    // NOT comment-stripped: ship's own regex literals contain an unbalanced
    // `<!--` (gate-override grep patterns ~L2004), so the fixpoint strip eats
    // this entire section — a comment-strip here false-negatives the very
    // templates it checks. The `<tally>`-placeholder scope already excludes
    // prose mentions.
    const raw = readFileSync(resolve(PLUGIN_ROOT, "skills", "ship", "SKILL.md"), "utf-8");
    // `## Pipeline Tally` followed by the <tally> placeholder only exists
    // inside the two PR-body templates — a bare count can't distinguish
    // template headings from prose mentions (deleting BOTH templates once
    // left the count at 2 and the assert green on the property it names).
    const occurrences = (raw.match(/## Pipeline Tally\n\s*<tally>/g) || []).length;
    expect(
      occurrences === 2,
      `ship SKILL.md has ${occurrences} '## Pipeline Tally' template heading(s) — the ` +
        `\`gh pr edit\` AND \`gh pr create\` fallback templates must each render it (#9403 AC4)`,
    ).toBe(true);
    expect(
      raw.includes("SOLEUR_TALLY_ABSENT"),
      "ship must render SOLEUR_TALLY_ABSENT for an instrumented run that wrote no ledger",
    ).toBe(true);
    expect(
      raw.includes("SOLEUR_TALLY_CAP_IGNORED"),
      "ship must render SOLEUR_TALLY_CAP_IGNORED for a run that crossed a cap and shipped anyway",
    ).toBe(true);
  });

  test("instrumented workflows return a counts field (one-writer bridge)", () => {
    // Enumerate workflows under instrumented skills, not a hardcoded list —
    // a new *.workflow.js in a tally-instrumented skill joins this contract
    // automatically (un-instrumented skills' workflows legitimately carry none).
    const bridged = readdirSync(resolve(PLUGIN_ROOT, "skills"), { withFileTypes: true })
      .filter((d) => d.isDirectory() && TALLY_SKILLS.includes(d.name))
      .flatMap((d) =>
        existsSync(resolve(PLUGIN_ROOT, "skills", d.name, "workflows"))
          ? readdirSync(resolve(PLUGIN_ROOT, "skills", d.name, "workflows"))
              .filter((f) => f.endsWith(".workflow.js"))
              .map(() => d.name)
          : [],
      )
      .sort();
    expect(
      bridged.length > 0,
      "no *.workflow.js found under instrumented skills — the bridge contract lost its population",
    ).toBe(true);
    for (const name of bridged) {
      const wfPath = resolve(
        PLUGIN_ROOT,
        "skills",
        name,
        "workflows",
        `${name}.workflow.js`,
      );
      const raw = readFileSync(wfPath, "utf-8");
      expect(
        /counts:\s*\{/.test(raw),
        `${name}.workflow.js does not return counts:{…} — the invoking prose posts ` +
          `it via \`pipeline-tally.sh incr\`; without the field the workflow path tallies nothing (#9403)`,
      ).toBe(true);
    }
  });
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
// Technical-ruling delegation wiring (hr-technical-fork-is-not-an-operator-question)
// ---------------------------------------------------------------------------
// Consumers are DERIVED (every skill whose SKILL.md names the CTO agent must link the
// reference) plus the seven the brief names; the artifact's writers must link the
// taxonomy doc, which carries the Decision Classes schema. `go` is wired through its
// authority file commands/go.md (skills/go/SKILL.md is a harness shim that reads it).
describe("Technical-ruling delegation wiring", () => {
  const REF_REL = "skills/brainstorm-techniques/references/technical-ruling-delegation.md";
  const LINK_RE = /\]\([^)]*technical-ruling-delegation\.md\)/;
  const NAMED = ["one-shot", "plan", "work", "review", "ship", "brainstorm"];
  const read = (rel: string) => readFileSync(resolve(PLUGIN_ROOT, rel), "utf-8");
  const skillDirs = readdirSync(resolve(PLUGIN_ROOT, "skills"), { withFileTypes: true })
    .filter((d) => d.isDirectory() && existsSync(resolve(PLUGIN_ROOT, "skills", d.name, "SKILL.md")))
    .map((d) => d.name);
  const derived = skillDirs.filter((n) => read(`skills/${n}/SKILL.md`).includes("soleur:engineering:cto"));
  const consumers = Array.from(new Set([...NAMED, ...derived, "plan-review"]));

  test("the reference exists", () => {
    expect(existsSync(resolve(PLUGIN_ROOT, REF_REL)), `${REF_REL} is missing.`).toBe(true);
  });

  test("consumer set has a floor of 7 (a zero-file glob must not pass)", () => {
    // 6 named skills + go (commands/go.md) + plan-review => at least 8 distinct links asserted.
    expect(consumers.length).toBeGreaterThanOrEqual(7);
    expect(skillDirs.length).toBeGreaterThanOrEqual(50);
  });

  for (const name of consumers) {
    test(`${name} links technical-ruling-delegation.md`, () => {
      expect(
        LINK_RE.test(read(`skills/${name}/SKILL.md`)),
        `${name}/SKILL.md does not link technical-ruling-delegation.md via a markdown link.`,
      ).toBe(true);
    });
  }

  test("go links it through commands/go.md (the authority file)", () => {
    expect(LINK_RE.test(read("commands/go.md")), "commands/go.md lost the technical-ruling pointer.").toBe(true);
  });

  for (const name of ["plan", "plan-review", "work", "ship"]) {
    test(`${name} (an artifact writer) links decision-principles.md`, () => {
      expect(/\]\([^)]*decision-principles\.md\)/.test(read(`skills/${name}/SKILL.md`))).toBe(true);
    });
  }

  test("ship carries the Technical-Ruling Gate heading, names the script and links the render reference", () => {
    const raw = read("skills/ship/SKILL.md");
    expect(raw.includes("### Technical-Ruling Gate (mandatory)")).toBe(true);
    expect(raw.includes("scripts/technical-ruling-gate.sh")).toBe(true);
    expect(/\]\([^)]*decision-challenges-render\.md\)/.test(raw)).toBe(true);
    expect(existsSync(resolve(PLUGIN_ROOT, "skills/ship/references/decision-challenges-render.md"))).toBe(true);
  });

  test("the gate is invoked at all three call sites, through the plugin root, with each exit handled", () => {
    const GATE = 'skills/ship/scripts/technical-ruling-gate.sh';
    const oneShot = read("skills/one-shot/SKILL.md");
    const ship = read("skills/ship/SKILL.md");
    // one-shot: the plan-phase call, the plugin-root form, and all three exit codes named.
    const os = oneShot.slice(oneShot.indexOf("**Technical-ruling gate (before `work`)."));
    expect(os.startsWith("**Technical-ruling gate"), "one-shot lost its gate step").toBe(true);
    const osStep = os.slice(0, os.indexOf("\n"));
    expect(osStep.includes("${CLAUDE_PLUGIN_ROOT}/" + GATE) && osStep.includes("--branch")).toBe(true);
    for (const exit of ["**0**", "**1**", "**2**"]) expect(osStep.includes(exit), `one-shot gate step lost ${exit}`).toBe(true);
    // ship Phase 5.5 (--branch) and Phase 6 step 4.5 (--pr-body), both via the plugin root, never a repo-relative path.
    // window-assembly: gateSection — everything from the gate heading to the end of ship/SKILL.md, of which only the first 1200 bytes (the gate paragraph) are asserted on
    const gateSection = ship.slice(ship.indexOf("### Technical-Ruling Gate (mandatory)"));
    expect(gateSection.slice(0, 1200).includes("${CLAUDE_PLUGIN_ROOT}/" + GATE) && gateSection.slice(0, 1200).includes("--branch")).toBe(true);
    const step45 = ship.slice(ship.indexOf("4.5. **Technical-ruling body check"));
    expect(step45.slice(0, 700).includes("${CLAUDE_PLUGIN_ROOT}/" + GATE) && step45.slice(0, 700).includes("--pr-body")).toBe(true);
    // Exit handling is part of the contract, not just the invocation.
    expect(osStep.includes("**2** the gate could not measure"), "one-shot lost its exit-2 handling").toBe(true);
    expect(gateSection.slice(0, 1200).includes("2 unmeasured: fix"), "ship 5.5 lost its exit-2 handling").toBe(true);
    expect(step45.slice(0, 700).includes("gate-rc=") && step45.slice(0, 700).includes("never ready past it"), "ship step 4.5 lost its exit handling").toBe(true);
    const renderDoc = read("skills/ship/references/decision-challenges-render.md");
    expect(renderDoc.includes('echo "gate-rc=$rc"') && renderDoc.includes("else rc=2; fi"), "the --pr-body recipe lost its fetch-failure exit 2 or its rc print").toBe(true);
    for (const f of [oneShot, ship, renderDoc]) {
      expect(/bash\s+"?plugins\/soleur\/skills\/ship\/scripts\/technical-ruling-gate\.sh/.test(f), "a repo-relative gate path breaks end-user installs").toBe(false);
    }
  });

  test("the gate script exists and is executable", () => {
    const f = resolve(PLUGIN_ROOT, "skills/ship/scripts/technical-ruling-gate.sh");
    expect(existsSync(f)).toBe(true);
    expect((statSync(f).mode & 0o111) !== 0, "technical-ruling-gate.sh is not executable").toBe(true);
  });

  test("the rule body names the CTO agent and the one-shot inline copy carries the key tokens", () => {
    const rules = readFileSync(resolve(PLUGIN_ROOT, "../../AGENTS.rules.md"), "utf-8");
    const line = rules.split("\n").find((l) => l.includes("[id: hr-technical-fork-is-not-an-operator-question]")) ?? "";
    expect(line.includes("soleur:engineering:cto")).toBe(true);
    // A Task subagent reads prompt text only, so one-shot carries the one deliberate copy.
    const oneShot = read("skills/one-shot/SKILL.md");
    const start = oneShot.indexOf("TECHNICAL RULINGS (inline copy");
    expect(start, "one-shot lost its inline technical-rulings copy").toBeGreaterThan(-1);
    const copy = oneShot.slice(start, start + 1400);
    for (const token of ["soleur:engineering:cto", "Ruled by CTO agent", "surface it", "OPEN DECISION"]) {
      expect(copy.includes(token), `one-shot inline copy lost "${token}"`).toBe(true);
    }
  });

  test("a brief's own wording is the CTO trigger: the reference, the go Sharp Edge and the shim say so", () => {
    // Whitespace-normalized content anchors, not line numbers: a re-wrap must not break the pin. Every slice is bounded and a
    // missing anchor fails with its own message (indexOf -1 would otherwise slice from the last character).
    const flat = (rel: string) => read(rel).replace(/\s+/g, " ");
    const between = (text: string, from: string, to: string | null) => {
      const i = text.indexOf(from);
      expect(i, `anchor not found: ${from}`).toBeGreaterThan(-1);
      const j = to === null ? text.length : text.indexOf(to, i + from.length);
      expect(j, `end anchor not found: ${to}`).toBeGreaterThan(i);
      return text.slice(i, j);
    };
    const ref = flat(REF_REL);
    const override = between(ref, "## 5. Override clause", "## 6.");
    expect(override.includes("OPEN DECISION"), "reference section 5 lost the OPEN DECISION trigger").toBe(true);
    expect(override.includes('"ask the operator once, then act"'), "reference section 5 lost the quoted incident wording").toBe(true);
    const scope = between(ref, "- **scope**", "- **priority / schedule**");
    expect(scope.includes("the routing of an already-identified gap") && scope.includes("is technical and goes to the CTO"), "reference section 1 lost the scope-routing classification or its polarity").toBe(true);
    expect(scope.includes("assigning work to a named person stays the operator's"), "reference section 1 lost the assignment carve-out").toBe(true);
    const edge = between(flat("commands/go.md"), "A technical ruling is never the operator's to make", "**Why:**");
    expect(edge.includes("OPEN DECISION"), "the first go Sharp Edge lost the OPEN DECISION trigger").toBe(true);
    const shim = flat("skills/go/SKILL.md");
    expect(shim.includes("OPEN DECISION") && shim.includes("never a reason to ask") && shim.includes("technical-ruling-delegation.md"), "the go shim lost the trigger sentence, its polarity or its link").toBe(true);
  });
});

// Final-report wiring (#10499): the report list of review/work is a carrier of
// hr-technical-fork-is-not-an-operator-question. Presence pins, so the paragraphs cannot be
// trimmed away under the SKILL.md byte ceilings without a red test naming the file + anchor.
describe("Technical-ruling final-report wiring (#10499)", () => {
  // Fenced blocks and HTML comments are stripped first: an anchor moved into either is not live prose.
  const strip = (t: string) => t.replace(/```[\s\S]*?```|<!--[\s\S]*?-->/g, " ").replace(/\s+/g, " ");
  const flat = (rel: string) => strip(readFileSync(resolve(PLUGIN_ROOT, rel), "utf-8"));
  const hasAnchor = (text: string, anchor: string) => strip(text).includes(anchor);
  const REF = "skills/brainstorm-techniques/references/technical-ruling-delegation.md";
  const LINK81 = "technical-ruling-delegation.md) section 8.1; only `operator (<category>)` items stay";
  const PAIRS: Array<[string, string]> = [
    [REF, "## 8. Final-report check and seat dissent from a ruling"],
    [REF, "**8.1 Final-report decision check"],
    [REF, "**8.2 Seat dissent from a ruling"],
    ["skills/review/SKILL.md", "**Final-report decision check (before either template).** Class every decision"],
    ["skills/review/SKILL.md", LINK81],
    ["skills/review/SKILL.md", "**Seat dissent from a ruling.**"],
    ["skills/review/SKILL.md", "to uphold or amend, never to the operator"],
    ["skills/review/SKILL.md", "**Route to the domain agent for a BINDING ruling (a GATE before Step 3"],
    ["skills/work/SKILL.md", "**Final-report decision check.** Class every decision"],
    ["skills/work/SKILL.md", LINK81],
  ];

  test("the anchor table has a floor (an emptied table must not pass)", () => {
    expect(PAIRS.length).toBeGreaterThanOrEqual(10);
  });

  for (const [rel, anchor] of PAIRS) {
    test(`${rel} carries "${anchor}"`, () => {
      expect(hasAnchor(flat(rel), anchor), `${rel} lost the final-report wiring anchor "${anchor}".`).toBe(true);
    });
  }

  test("the seat-dissent paragraph sits at the spawn site, before the seat list", () => {
    const review = flat("skills/review/SKILL.md");
    const dissent = review.indexOf("**Seat dissent from a ruling.**");
    const seats = review.indexOf("#### Parallel Agents to review the PR:");
    expect(dissent, "review lost the seat-dissent paragraph").toBeGreaterThan(-1);
    expect(seats, "review lost the seat-list heading").toBeGreaterThan(-1);
    expect(dissent < seats, "the seat-dissent rule must precede the seat spawn (rulings are read before seats exist)").toBe(true);
  });

  test("the instrument self-test: the helper rejects an absent, fenced or commented anchor and accepts a re-flowed one", () => {
    const a = "**Final-report decision check";
    expect(hasAnchor("no wiring here", a)).toBe(false);
    expect(hasAnchor("```\n" + a + " (x)\n```", a)).toBe(false);
    expect(hasAnchor("<!-- " + a + " (x) -->", a)).toBe(false);
    expect(hasAnchor("**Final-report\n    decision   check (x)", a)).toBe(true);
  });
});

describe("operator-bootstrap predecessor wiring (#8287 R14/R32)", () => {
  // Loop until stable, not a single pass. A one-shot replace is incomplete
  // multi-character sanitization (CodeQL js/incomplete-multi-character-sanitization,
  // high): removing an inner `<!-- … -->` can splice its neighbours into a FRESH
  // `<!--`, so a crafted overlap survives the strip. That matters here and not
  // only in the abstract — this strip exists so a comment cannot satisfy the
  // assertions below, and the surviving-comment case is exactly the one that
  // would let a commented-out invocation certify the wiring as present.
  const stripHtmlComments = (raw: string) => {
    let out = raw;
    let prev: string;
    do {
      prev = out;
      out = out.replace(/<!--[\s\S]*?-->/g, "");
    } while (out !== prev);
    return out;
  };

  // The skill is only ever reached from ship's operator-step gate; an orphaned
  // skill is the failure R14 folded this assertion in to catch. HTML comments
  // are stripped BEFORE matching (a comment can carry the literal and would
  // otherwise satisfy a bare regex), and the match is anchored to the option-4
  // list item of the gate, not to any mention anywhere in the file.
  // The strip is the guard's own precondition, so it gets its own row. The
  // fixture is the overlap CodeQL named: a single-pass replace consumes the
  // INNER comment and splices the remainder into a fresh, live
  // `<!-- skill: soleur:operator-bootstrap -->` — the literal the assertion
  // below matches. Measured: one pass leaves it, the loop removes it.
  test("stripHtmlComments survives an overlapping comment that would re-form the invocation", () => {
    const evil = "<!<!-- x -->-- skill: soleur:operator-bootstrap -->";
    // The single-pass control is written with indexOf/slice, not a regex replace,
    // on purpose: CodeQL's js/incomplete-multi-character-sanitization matches the
    // replace shape and would flag the REPRODUCTION of the defect as the defect
    // (alert #221 did exactly that). Semantics are identical on this fixture —
    // remove the first `<!-- … -->` exactly once, which is what one pass of the
    // old strip did.
    const removeFirstComment = (input: string): string => {
      const open = input.indexOf("<!--");
      const close = open < 0 ? -1 : input.indexOf("-->", open + 4);
      return open < 0 || close < 0 ? input : input.slice(0, open) + input.slice(close + 3);
    };
    const singlePass = removeFirstComment(evil);
    expect(
      singlePass.includes("skill: soleur:operator-bootstrap"),
      "fixture no longer reproduces the single-pass defect — pick a new overlap or this row proves nothing",
    ).toBe(true);
    expect(
      stripHtmlComments(evil).includes("skill: soleur:operator-bootstrap"),
      "stripHtmlComments left a commented-out invocation intact — a comment can certify the wiring",
    ).toBe(false);
  });

  test("ship's operator-step gate offers option 4 as the Skill-tool invocation of soleur:operator-bootstrap", () => {
    const raw = stripHtmlComments(
      readFileSync(resolve(PLUGIN_ROOT, "skills", "ship", "SKILL.md"), "utf-8"),
    );
    const option4 = raw
      .split("\n")
      .find((line) => /^4\.\s+\*\*Generate a runnable script instead/.test(line));
    expect(
      option4,
      "ship/SKILL.md lost the gate's option-4 line (`4. **Generate a runnable script instead …`).",
    ).toBeDefined();
    expect(
      /skill:\s*soleur:operator-bootstrap(?![\w-])/.test(option4 ?? ""),
      "the option-4 line no longer carries `skill: soleur:operator-bootstrap` — the " +
        "hr-multi-step-post-merge-bootstrap-script artifact has no producer in the pipeline.",
    ).toBe(true);
  });

  // help.md renders skills by prefix family (R23), so the two skills reach the
  // menu through the `operator-*` family rule in EVERY harness block — checked
  // per block (split on the `### ` headings), because a total count of 3 is
  // satisfied by one block mentioning the family three times while another
  // dropped it.
  test("help.md carries the operator-* family in each harness block", () => {
    const raw = readFileSync(resolve(PLUGIN_ROOT, "commands", "help.md"), "utf-8");
    const blocks = raw.split(/^### /m).slice(1);
    const wanted = ["Claude Code", "Devin CLI", "Grok Build"];
    for (const name of wanted) {
      const block = blocks.find((b) => b.startsWith(name));
      expect(block, `help.md has no \`### ${name}\` harness block`).toBeDefined();
      expect(
        /operator-\*/.test(block ?? ""),
        `the \`### ${name}\` block of help.md does not name the operator-* family`,
      ).toBe(true);
    }
    for (const skillName of ["operator-bootstrap", "operator-rephrase"]) {
      expect(
        existsSync(resolve(PLUGIN_ROOT, "skills", skillName, "SKILL.md")),
        `${skillName} is missing — the operator-* family rule in help.md would render nothing for it.`,
      ).toBe(true);
    }
  });

  // Two Phase-6 body templates carry the Merge Danger block (gh pr edit and gh
  // pr create); which one runs depends only on whether a draft PR exists, so
  // an edit to one and not the other is a silent partial. Byte-identical after
  // the indentation the fenced block adds is removed.
  test("ship's two Merge Danger template blocks are byte-identical", () => {
    const raw = readFileSync(resolve(PLUGIN_ROOT, "skills", "ship", "SKILL.md"), "utf-8");
    const blocks: string[] = [];
    const re = /^[ \t]*## Merge Danger\n([\s\S]*?)\n[ \t]*## Changelog/gm;
    let m: RegExpExecArray | null;
    while ((m = re.exec(raw)) !== null) {
      blocks.push(m[1].split("\n").map((l) => l.replace(/^[ \t]+/, "")).join("\n"));
    }
    expect(blocks.length, "expected exactly two `## Merge Danger` template blocks").toBe(2);
    expect(blocks[0]).toBe(blocks[1]);
    for (const b of blocks) {
      expect(/^\*\*Undo:\*\*/m.test(b)).toBe(true);
      expect(/^\*\*Blast Radius:\*\*/m.test(b)).toBe(true);
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
// gh --search probes must pin --state explicitly (#6786) AND cap their result
// set with -L/--limit unless they are a pure existence drill or a bounded
// linked:issue shape (#6793). Both detectors guard the SAME silent-open class:
// a probe whose omitted filter (the appended default `--state open`, or the
// default 30-row cap) silently drops the records the decision depends on, so an
// empty/short result reads identically to "no match". #6793 widens the scan
// from plugins/soleur/skills/** to a repo-wide allowlist of EXECUTABLE-
// instruction surfaces and adds the -L/--limit truncation detector.
// ---------------------------------------------------------------------------

// Captures one `gh pr|issue list …` command, from the point the binary is named to
// the end of ITS OWN LINE (or the closing backtick of an inline span, whichever comes
// first). Two properties are load-bearing and were both learned the hard way:
//
//   1. The capture must NOT cross a newline. An earlier `[^`]*` form spanned lines, so
//      inside a ```fence the capture ran to the closing fence and swallowed every
//      following command — a `--state` belonging to a DIFFERENT command then satisfied
//      the check and laundered its stateless neighbour. That is the very fail-open
//      shape this lint exists to catch, reproduced inside the lint (#6786 review).
//   2. The match must be findable mid-line, not anchored at a span opener: probes are
//      frequently embedded in a shell assignment (`EXISTING=$(gh pr list …)`).
// `(?:\s|$)` after the subcommand, not `\b`: `gh issue list:` appears inside
// error-message text ("… gh issue list: <stderr>") and `gh api:` in prose —
// a colon after the subcommand marks a label, never an invocation. A real
// call always continues with a space or ends the statement.
const GH_LIST_CMD = /\bgh (?:pr|issue) list(?:[\s)"']|$)[^`\n]*/g;
// Sibling families for the #8593 enumeration detector: `gh search issues|prs`
// and `gh api` (list-endpoint discrimination below), captured with the same
// line/backtick bounds as GH_LIST_CMD so a neighbor's flags cannot launder.
const GH_SEARCH_CMD = /\bgh search (?:issues|prs)(?:[\s)"']|$)[^`\n]*/g;
const GH_API_CMD = /\bgh api(?:[\s)"']|$)[^`\n]*/g;

// An `is:`/`state:` qualifier inside the --search string. Mixing one of these with an
// explicit --state is the exact contradiction that produced #6786 (an appended open
// filter ANDed against `is:merged` matches nothing), so pin state in ONE place only.
const IN_QUERY_STATE = /--search\s+(["'])[^"']*(?:\bis:(?:merged|closed|open)\b|\bstate:)[^"']*\1/;

// The repo root, two levels above PLUGIN_ROOT (plugins/soleur). #6786 scanned
// only plugins/soleur/skills/**; #6793 widens to a repo-wide allowlist of files
// that carry EXECUTABLE INSTRUCTIONS an agent or CI actually runs `gh` from —
// chosen by "which surfaces run commands", not by where a grep found an
// offender (defect-class indexing, 2026-07-20 learning).
const REPO_ROOT = resolve(PLUGIN_ROOT, "../..");

// INCLUDE globs. Prose/record surfaces are excluded by OMISSION here:
// knowledge-base/project/** (learnings/plans/specs) and **/archive/** are never
// globbed; **/*.test.sh fixtures are filtered below; all .ts/.py are excluded by
// never being globbed (this also drops THIS file's own intentional broken-form
// fixtures — scanning .ts would false-positive on every one of them).
const EXEC_SURFACE_GLOBS = [
  "plugins/soleur/skills/**/*.md",
  "plugins/soleur/commands/**/*.md",
  "plugins/soleur/agents/**/*.md",
  "scripts/**/*.sh",
  "plugins/soleur/skills/**/scripts/*.sh",
  "apps/**/scripts/*.sh",
  "tools/**/*.sh",
  ".claude/hooks/**/*.sh",
  // Shipped plugin shell surfaces (#7409). Opportunistic, NOT a regression this
  // change creates: this lint targets the `gh pr|issue list --search` class, and
  // the file that moved into plugins/soleur/scripts/lib/ contains zero such
  // probes — measured, so nothing was lost by the move and nothing is gained
  // beyond closing a pre-existing gap in coverage of these two directories.
  "plugins/soleur/scripts/**/*.sh",
  "plugins/soleur/hooks/**/*.sh",
  ".github/workflows/**/*.yml",
  ".github/workflows/**/*.yaml",
  ".github/actions/**/*.yml",
  ".github/actions/**/*.yaml",
  // #8593 widened surfaces. `.github/scripts/` holds workflow-executed helpers
  // (build-inngest-bootstrap-image.yml et al. run these) — `*/test/` fixtures
  // deliberately encode probe shapes and stay out by path, same role as the
  // `*.test.sh` filter below. `apps/web-platform/server/inngest/functions/*.ts`
  // are cron-agent prompt files carrying executable `gh` instructions to
  // agents holding `Bash(gh issue list:*)` grants — scanned as TEXT (the
  // extractor works on raw lines; a "ts" surface strips `//` full-line
  // comments so comment prose cannot false-positive).
  ".github/scripts/**/*.sh",
  "apps/web-platform/server/inngest/functions/*.ts",
  "knowledge-base/engineering/operations/runbooks/**/*.md",
];

type Surface = "md" | "sh" | "yaml" | "ts";

function surfaceOf(path: string): Surface {
  if (path.endsWith(".sh")) return "sh";
  if (path.endsWith(".yml") || path.endsWith(".yaml")) return "yaml";
  if (path.endsWith(".ts")) return "ts";
  return "md";
}

/** The repo-wide executable-surface corpus (deduped; *.test.sh excluded). */
export function execSurfaceFiles(): { file: string; raw: string; surface: Surface }[] {
  const seen = new Set<string>();
  const out: { file: string; raw: string; surface: Surface }[] = [];
  for (const glob of EXEC_SURFACE_GLOBS) {
    // `dot: true` is load-bearing — Bun's Glob defaults to dot:false, which
    // silently skips EVERY dot-directory, so `.github/workflows`, `.github/
    // actions` and `.claude/hooks` (the highest-value CI +
    // hook surface this lint claims to cover) would match ZERO files and the
    // offender assertions would pass vacuously against an absent surface class.
    for (const rel of new Glob(glob).scanSync({ cwd: REPO_ROOT, dot: true })) {
      // Test fixtures deliberately encode the broken form; never admit them,
      // even a future scripts/foo.test.sh landing under an included glob. Same
      // role for `.github/scripts/test/` (17 test-*.sh fixtures named test-*,
      // not *.test.sh, so the `*.test.sh` filter above cannot see them — CTO
      // ruling: the `*/test/` path exclusion is load-bearing) and for any
      // `*.test.ts` that ever lands under the inngest functions glob.
      if (rel.endsWith(".test.sh") || rel.endsWith(".test.ts")) continue;
      // Scoped to the new .github/scripts glob: a `/test/` path segment there
      // is a fixture directory, not an executable surface.
      if (rel.startsWith(".github/scripts/") && rel.includes("/test/")) continue;
      if (seen.has(rel)) continue;
      seen.add(rel);
      out.push({
        file: rel,
        raw: readFileSync(resolve(REPO_ROOT, rel), "utf-8"),
        surface: surfaceOf(rel),
      });
    }
  }
  return out;
}

interface Probe {
  file: string;
  cmd: string;
  /** True when the command sits inside a fenced code block rather than an inline span. */
  fenced: boolean;
}

// Shell statement separators. A backslash-continued logical line can chain
// MULTIPLE commands with `&&`/`||`/`;`, and `GH_LIST_CMD` is greedy through
// everything but backtick/newline — so without splitting, two chained probes
// collapse into ONE capture and the SECOND command's --state/-L launders the
// FIRST (the #6786 launder class, reintroduced across a continuation). Split on
// these BUT NOT on a single `|` pipe: a `| jq 'select(…)'` drill is part of the
// SAME command and the narrowing/existence detectors must still see it.
const STATEMENT_SEP = /&&|\|\||;/;

interface GhStmt {
  file: string;
  stmt: string;
  fenced: boolean;
}

/**
 * Logical statements over each file's raw text: `\`-continued lines joined,
 * fence delimiters and comment lines split out, `&&`/`||`/`;` chains split.
 * Shared by every `gh` detector so a surface/comment rule lands once (#8593's
 * `//` handling in "ts" files protects BOTH the #6786/#6793 search probes and
 * the enumeration detector — they scan the same corpus).
 */
function ghStatements(
  files: { file: string; raw: string; surface?: Surface }[],
): GhStmt[] {
  return files.flatMap(({ file, raw, surface = "md" }) => {
    const stmts: GhStmt[] = [];
    let fenced = false;
    // A `\`-continued command accumulates here across physical lines, so a
    // multi-line `gh … list` is captured whole — its --limit / jq drill
    // routinely lives on a continuation line, and a line-bounded capture would
    // both MISS that drill (false negative on the select-after-truncation
    // class) and FALSE-POSITIVE on a correct probe whose --limit is one line
    // down. GH_LIST_CMD stays newline-bounded and we split on STATEMENT_SEP, so
    // an UNcontinued neighbour never launders (#6786).
    let buf: string | null = null;
    const flush = () => {
      if (buf === null) return;
      for (const stmt of buf.split(STATEMENT_SEP)) {
        stmts.push({ file, stmt, fenced });
      }
      buf = null;
    };
    for (const line of raw.split("\n")) {
      // Fence delimiters and shell/YAML comments are ALWAYS their own physical
      // line and never part of a command, so they terminate any pending
      // continuation and are handled BEFORE continuation-joining. This ordering
      // is load-bearing: joining a comment line that ends in `\` would
      // otherwise swallow the real probe on the next line into a comment that
      // is then skipped whole (a `.sh`/`.yaml` false negative).
      if (surface === "md" && /^\s*```/.test(line)) {
        flush();
        fenced = !fenced;
        continue;
      }
      if (surface !== "md" && /^\s*#/.test(line)) {
        flush();
        continue;
      }
      // #8593: the "ts" surface treats a full-line `//` comment like `#` —
      // flush + skip — or comment prose such as _cron-shared.ts's
      // `// gh issue list --search …` false-positives on every detector.
      if (surface === "ts" && /^\s*\/\//.test(line)) {
        flush();
        continue;
      }
      const cont = /\\\s*$/.test(line);
      const body = cont ? line.replace(/\\\s*$/, "") : line;
      buf = buf === null ? body : `${buf} ${body.replace(/^\s+/, "")}`;
      if (!cont) flush();
    }
    flush(); // trailing unterminated continuation
    return stmts;
  });
}

/** Every `gh pr|issue list` command carrying `--search`, one entry per command. */
export function extractSearchProbes(
  files: { file: string; raw: string; surface?: Surface }[],
): Probe[] {
  return ghStatements(files)
    .flatMap(({ file, stmt, fenced }) =>
      [...stmt.matchAll(GH_LIST_CMD)].map((m) => ({
        file,
        cmd: m[0].trim(),
        fenced,
      })),
    )
    .filter(({ cmd }) => /--search\b/.test(cmd));
}

/** Search probes that omit an explicit `--state` — the #6786 silent-open defect class. */
export function findStatelessProbes(
  files: { file: string; raw: string; surface?: Surface }[],
): Probe[] {
  return extractSearchProbes(files).filter(({ cmd }) => !/--state\b/.test(cmd));
}

/** Search probes that pin state in BOTH the query and a flag — #6786's literal shape. */
export function findContradictingStateProbes(
  files: { file: string; raw: string; surface?: Surface }[],
): Probe[] {
  return extractSearchProbes(files).filter(
    ({ cmd }) => /--state\b/.test(cmd) && IN_QUERY_STATE.test(cmd),
  );
}

// -- #6793 truncation detector -------------------------------------------------
// An explicit result cap. `-L N`, `-L=N`, or `--limit N`. Anchored on a leading
// boundary so it cannot match inside `--label`. Only the space/`=`-separated
// form is recognized — an attached `-L100` would NOT match and the probe would
// be flagged (fail-CLOSED: a false red-line forcing a reformat, never a silent
// pass), so the strict form is a safe authoring contract.
const HAS_LIMIT = /(?:^|\s)(?:-L|--limit)(?:[=\s]|$)/;
// A pure existence drill: reduce the result to "does ≥1 row exist?". Safe at the
// 30-row cap — if >30 rows match, ≥1 certainly does.
const EXISTENCE_DRILL = /\.\[0\](?![\s\S]*,)|\/\/\s*empty|first\s*\(/;
// A result-set operation that runs AFTER the search, so it operates on the
// already-truncated 30 rows and its result depends on the FULL match set: an
// exact-match select, a count, or a REORDER (sort/min/max/group). When present,
// a following existence drill is NOT truncation-safe — the row the decision
// needs (the exact match; the true min/max; the oldest) can sit past row 30 and
// be evicted before the operation sees it. `select(`/`length` were the #6793
// deepen's examples (content-publisher.sh select-after-search); the real
// invariant is "any post-search op whose answer depends on the whole set", so a
// `sort_by(.createdAt) | .[0]` extreme-picker is the same fail-open class.
const POST_SEARCH_NARROWING =
  /select\s*\(|\b(?:sort|min|max|group)_by\s*\(|\bsort\b|\blast\b|\blength\b/;
// A single issue's FORMALLY-linked PR set is bounded by domain semantics well
// under 30, so a `linked:issue #N` probe never needs an explicit cap (D2b). The
// `#` anchor keeps this from exempting an unrelated string containing
// "linked:issue". This is what keeps one-shot/SKILL.md:55 byte-identical.
const BOUNDED_LINKED_ISSUE = /linked:issue\s+#\S/;

/**
 * Search probes that neither cap the result set (`-L`/`--limit`) nor qualify for
 * a principled exemption — the #6793 silent-truncation defect class. Exemptions:
 *   (a) a pure existence drill with NO post-search narrowing, or
 *   (b) the bounded `linked:issue #N` query shape.
 */
// Quoted spans carry data, not flags: `-L`/`--limit`/`--paginate`/`-X` inside
// `--search`/`--jq`/`--field` strings must not launder a bound or a verb. Test
// bound/verb/exemption patterns on the dequoted command; patterns whose legit
// match lives inside a flag value (`linked:issue`, `.[0]`) keep the raw text.
const dequote = (cmd: string): string =>
  cmd.replace(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/g, '""');

export function findUnlimitedProbes(
  files: { file: string; raw: string; surface?: Surface }[],
): Probe[] {
  return extractSearchProbes(files).filter(({ cmd }) => {
    if (HAS_LIMIT.test(dequote(cmd))) return false;
    if (BOUNDED_LINKED_ISSUE.test(cmd)) return false;
    if (EXISTENCE_DRILL.test(cmd) && !POST_SEARCH_NARROWING.test(cmd)) return false;
    return true;
  });
}

// -- #8593 unbounded-enumeration detector ------------------------------------
// #6793's gate covers `gh pr|issue list … --search` probes only; the identical
// silent-30-row truncation via `gh issue list --label X` (no --search),
// `gh search issues|prs`, and non-paginated `gh api` list endpoints was
// invisible. This detector widens the ASSEMBLY, not the property: a `gh`
// capture whose output feeds enumeration or post-narrowing must carry a
// SUFFICIENT bound or a coded exemption.

interface EnumProbe extends Probe {
  /** Which `gh` family produced the capture. */
  kind: "list" | "search" | "api";
  /** The capture sits inside a `for <var> in $(…)` loop head — the output is
   * iterated even when no jq/pipe consumer names it (the
   * scheduled-inngest-health.yml close-enumeration shape). The match itself
   * starts at `gh`, so the loop head is read off the statement prefix. */
  forConsumed: boolean;
}

const FOR_CONSUMER = /\bfor\s+\w+\s+in\b/;

/** Every enumeration-candidate `gh` capture, one entry per command. */
export function extractEnumerations(
  files: { file: string; raw: string; surface?: Surface }[],
): EnumProbe[] {
  return ghStatements(files).flatMap(({ file, stmt, fenced }) => {
    const out: EnumProbe[] = [];
    const push = (kind: EnumProbe["kind"], m: RegExpMatchArray) =>
      out.push({
        file,
        cmd: m[0].trim(),
        fenced,
        kind,
        forConsumed: FOR_CONSUMER.test(stmt.slice(0, m.index ?? 0)),
      });
    for (const m of stmt.matchAll(GH_LIST_CMD)) push("list", m);
    for (const m of stmt.matchAll(GH_SEARCH_CMD)) push("search", m);
    for (const m of stmt.matchAll(GH_API_CMD)) push("api", m);
    return out;
  });
}

// A consumer whose answer depends on the FULL result set — iterating elements
// (`[]`), a `for`/`while`/`xargs` loop, a post-count (`wc`, `length`), a
// post-narrow (`grep`, `select(`, `map(`), or a reorder/extremum
// (`sort`, `*_by`, `last`). Anything the consumer sees only after the default
// page cap applied is a silent-truncation site. `| jq` is listed because a jq
// stage over a list capture is the same class even when its program names no
// narrowing op.
const ENUMERATION_CONSUMER =
  /\[\]|\|\s*(?:grep|wc|jq|xargs|sort|uniq|head|tail|while)\b|\bselect\s*\(|\bmap\s*\(|\b(?:sort|min|max|group)_by\s*\(|\bsort\b|\blast\b|\blength\b/;

// A `--head <branch>` probe is domain-bounded by headRefName cardinality —
// the same argument as `linked:issue #N` (CTO ruling 2026-11-01): covers
// .github/scripts/bump-inngest-bootstrap-pin.sh's two post-narrowing `--head`
// probes. Coded as a pattern so the judgment is enforced, not narrated.
const BOUNDED_HEAD = /--head\b/;

// A sufficient bound is `-L N`/`--limit N` with N >= 100, or `--paginate`.
// Bound PRESENCE is not sufficiency — `-L 1` greens the #6793 gate while an
// enumerating `.[].number` consumer still truncates (the issue's named shape).
// The operand must be separated by space or `=`: an attached `-L100` does not
// match and flags (fail-CLOSED, same authoring contract as HAS_LIMIT).
const LIMIT_OPERAND = /(?:^|\s)(?:-L|--limit)(?:\s+|\s*=\s*)(\d+)/g;

function sufficientBound(cmd: string): boolean {
  if (/--paginate\b/.test(cmd)) return true;
  for (const m of cmd.matchAll(LIMIT_OPERAND)) {
    if (parseInt(m[1], 10) >= 100) return true;
  }
  return false;
}

// A `gh api` WRITE is never an enumeration site: `-X`/`--method` with a
// mutating verb, the `graphql` endpoint, or a `--field` (`-f`) payload (which
// flips the request to POST). `-F`/`--raw-field` stays GET and is NOT here.
const GH_API_WRITE =
  /(?:^|\s)-X\s+(?:POST|PUT|PATCH|DELETE)\b|(?:^|\s)--method(?:\s*=\s*|\s+)(?:POST|PUT|PATCH|DELETE)\b|\bgh api\s+graphql\b|(?:^|\s)-f(?:[=\s]|$)|(?:^|\s)--field(?:[=\s]|$)/;
// An explicit GET verb wins over the `-f`/`--field` write arm: `gh api -X GET
// <endpoint> -f q=…` is a READ (dev-ledger-reconcile.yml:344 idiom) — without
// this short-circuit the `-f` arm exempts an unpaginated list read.
const GH_API_GET =
  /(?:^|\s)-X\s+GET\b|(?:^|\s)--method(?:\s*=\s*|\s+)GET\b/i;

// `gh api` flags that consume the NEXT token as their value, so the endpoint
// is the first remaining positional. Boolean flags (`--paginate`, `-i`, …)
// start with `-` and are skipped without consuming.
const API_FLAGS_WITH_VALUE = new Set([
  "-X", "--method", "-H", "--header", "-f", "--field", "-F", "--raw-field",
  "--jq", "-q", "--template", "--input", "--cache", "--hostname", "--preview",
]);

// An endpoint path segment that names ONE resource: a numeric id, a
// `$VAR`/`${VAR}` expansion, or a doc placeholder (`<id>`, `{id}`, `:param`) —
// docs and runbooks write all of these for the same item position. `^<` needs
// no closing `>`: runbook placeholders contain spaces (`<reboot job id>`),
// which split the token mid-placeholder.
const API_ID_SEGMENT = /^\d+$|^\$|^<|^\{|^:/;

// Endpoint roots that read ONE object, never a collection: `repos/o/r/pages`
// (the Pages config), `rate_limit`, `meta`, … — collection-SHAPED but not
// enumerable. A real sub-list under one (`pages/builds`) would mis-read as an
// item; none exists in the corpus — the residual is documented, not hidden.
const API_SINGLETON = new Set([
  "pages", "rate_limit", "meta", "zen", "octocat", "emojis", "feeds",
  "versions", "app", "gitignore", "license", "readme",
]);

// Collections whose second path segment names ONE resource BY NAME even as a
// literal (env names, content paths, `base...head` compares, branch/secret/
// variable names, commit SHAs) — `environments/web-platform-infra-apply` is an
// item read, not a collection, while `environments` alone lists. `git` is
// handled separately below (`git/trees/HEAD` is an item at depth 3, but
// `git/refs` at depth 2 genuinely lists).
const API_NAMED_CHILD = new Set([
  "environments", "contents", "compare", "branches", "tags", "commits",
  "secrets", "variables", "deployments", "hooks", "keys",
]);

// First-collection words used ONLY to tell `repos/<owner>/<repo>` literal
// pairs from `repos/<one-var>/…` when stripping the scope — a literal second
// segment that is NOT one of these is the repo name and goes with the owner.
// Incompleteness fails open (an exotic collection eaten as a repo name reads
// as an item); every entry the corpus exercises is pinned by the census.
const API_LIST_WORDS = new Set([
  "issues", "pulls", "comments", "commits", "branches", "tags", "releases",
  "milestones", "labels", "assignees", "reviewers", "reviews", "files",
  "actions", "workflows", "runs", "jobs", "artifacts", "caches",
  "check-runs", "check-suites", "statuses", "annotations", "rulesets", "rules",
  "contents", "environments", "pages", "code-scanning", "secret-scanning",
  "dependabot", "code-security", "security-advisories", "vulnerability-alerts",
  "automated-security-fixes", "private-vulnerability-reporting",
  "compare", "git", "keys", "hooks", "secrets", "variables", "deployments",
  "projects", "teams", "members", "installations", "events", "notifications",
  "subscribers", "stargazers", "forks", "contributors", "collaborators",
  "downloads", "topics", "languages", "invitations", "community", "license",
  "readme", "builds", "properties", "interaction-limits", "merges",
]);

// After the scope prefix is stripped, a LIST endpoint is a bare collection
// segment (`…/issues`, `…/milestones`, `search/issues`) or a chain of
// collection words (`actions/workflows/<file>.yml/runs`) that bottoms out at
// one — `…/<collection>/<id>` and everything under it (`pulls/<N>/files`,
// `issues/<N>/comments`, `commits/<sha>/pulls`, `environments/<name>`,
// `contents/<path>`) is a bounded item scope, not an enumeration (CTO ruling:
// the under-item collections stay must-PASS).
function apiPathIsList(segs: string[]): boolean {
  if (segs.length === 0) return false;
  if (API_SINGLETON.has(segs[0])) return false;
  if (segs[0] === "search") return true;
  if (segs.length === 1) return true;
  if (segs[0] === "git" && segs.length >= 3) return false;
  if (API_NAMED_CHILD.has(segs[0])) return false;
  if (API_ID_SEGMENT.test(segs[1])) return false;
  return apiPathIsList(segs.slice(1));
}

function apiEndpointIsList(cmd: string): boolean {
  const m = /\bgh\s+api\b(.*)$/.exec(cmd);
  if (!m) return false;
  const toks = m[1].match(/"[^"\n]*"|'[^'\n]*'|\S+/g) ?? [];
  let skipValue = false;
  let endpoint: string | null = null;
  for (const tok of toks) {
    if (skipValue) {
      skipValue = false;
      continue;
    }
    const bare = tok.replace(/^["']|["']$/g, "");
    if (API_FLAGS_WITH_VALUE.has(bare)) {
      skipValue = true;
      continue;
    }
    if (bare.startsWith("-")) continue;
    endpoint = bare;
    break;
  }
  // No positional endpoint (or graphql, excluded above by GH_API_WRITE anyway):
  // not a list read. A variable endpoint (`gh api "$PATH"`) parses as one
  // segment → list — fail-closed, it needs --paginate or a consumer-free call.
  if (endpoint === null) return false;
  const segs = endpoint.split("?")[0].split("/").filter(Boolean);
  if (segs[0] === "repos") {
    segs.shift();
    // The owner/repo occupies the next 1-2 segments: an id-shaped seg always
    // goes (`repos/$REPO/x` carries owner+name in ONE var; `repos/{owner}/{repo}`
    // and `repos/$O/$R` carry it in two). A literal pair goes too when the
    // second literal is not a collection word (`repos/jikig-ai/soleur`,
    // `repos/o/r`); a literal first seg followed by a collection word is a
    // combined literal scope (`repos/owner-name/issues` does not occur, but
    // failing closed here would eat a real collection).
    if (segs.length > 0 && API_ID_SEGMENT.test(segs[0])) segs.shift();
    else if (
      segs.length >= 2 &&
      !API_LIST_WORDS.has(segs[0]) &&
      !API_LIST_WORDS.has(segs[1])
    ) {
      segs.splice(0, 2);
    } else if (segs.length > 0 && !API_LIST_WORDS.has(segs[0])) {
      segs.shift();
    }
  } else if (
    segs.length >= 2 &&
    (segs[0] === "orgs" ||
      segs[0] === "users" ||
      segs[0] === "teams" ||
      segs[0] === "enterprises")
  ) {
    // A bare `gh api users`/`gh api orgs` IS a paginated list endpoint — only
    // strip the scope pair when a second segment exists; the bare root must
    // fall through to apiPathIsList (which returns true on length-1).
    segs.splice(0, 2);
  } else if (segs[0] === "user") {
    // `user` alone is a singleton (GET /user) — splice unconditionally so the
    // bare endpoint reduces to [] (item read); only `user/<child>` recurses.
    segs.splice(0, 1);
  }
  return apiPathIsList(segs);
}

// Documented per-site exemptions — the census's "documented exclusion with
// rationale" mechanism (#8593 AC5). A site lands here ONLY when the bound the
// gate would impose would change the site's semantics: a deliberate top-K
// query whose `--limit` IS the answer, a bound carried in a variable the
// static scan cannot read, or a teaching example of manual pagination. Every
// entry names the file, an anchored cmd substring, and the reason — never a
// bare path (a bare path would exempt every FUTURE enumeration in the file).
const DOCUMENTED_ENUMERATION_EXEMPTIONS: {
  file: string;
  cmdIncludes: string;
  reason: string;
}[] = [
  {
    file: "plugins/soleur/skills/product-roadmap/SKILL.md",
    cmdIncludes: '--search "no:milestone sort:created-asc" --limit 5',
    reason:
      "deliberate top-K: the query asks for the FIVE oldest unmilestoned " +
      "issues; `--limit 5` is the answer, not a truncation risk.",
  },
  {
    file: "scripts/preflight-required-check-bypass.sh",
    cmdIncludes: '-L "$MERGE_LIMIT"',
    reason:
      "the bound is a variable (MERGE_LIMIT=200 default, >= 100) — the static " +
      "scan cannot read it; a literal would fight the SOLEUR_BYPASS_MERGE_LIMIT " +
      "override. The site itself notes a capped list must not read as complete.",
  },
  {
    file: "knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md",
    cmdIncludes: "page=$p",
    reason:
      "a teaching example of MANUAL pagination (`for p in 1..6; page=$p`) — " +
      "the bound is the loop the runbook is documenting; --paginate would " +
      "rewrite the procedure it exists to teach.",
  },
];

/**
 * `gh` captures whose output feeds an enumeration/post-narrowing consumer and
 * carry neither a sufficient bound (`-L N`/`--limit N` with N ≥ 100, or
 * `--paginate`) nor a coded exemption — the #8593 silent-truncation class.
 * Exemptions: a pure existence drill with no post-search narrowing, the
 * bounded `linked:issue #N` query shape, `BOUNDED_HEAD` (`--head`), and the
 * documented per-site table above. `gh api` item reads (`…/issues/<N>`,
 * `pulls/<N>/files`) and writes are not enumeration sites and are filtered
 * before the consumer test.
 */
export function findUnboundedEnumerations(
  files: { file: string; raw: string; surface?: Surface }[],
): EnumProbe[] {
  return extractEnumerations(files).filter((p) => {
    // Write/verb/bound/head patterns are tested on the dequoted command — a
    // `-f 'q=-X POST'`, `--limit 100`, `--paginate` or `--head` inside a quoted
    // `--search`/`--jq`/`--field` string is data, not a flag (fix-round seat).
    const bareCmd = dequote(p.cmd);
    if (p.kind === "api") {
      if (GH_API_WRITE.test(bareCmd) && !GH_API_GET.test(bareCmd)) return false;
      if (!apiEndpointIsList(p.cmd)) return false;
    }
    if (!p.forConsumed && !ENUMERATION_CONSUMER.test(p.cmd)) return false;
    if (BOUNDED_LINKED_ISSUE.test(p.cmd)) return false;
    if (BOUNDED_HEAD.test(bareCmd)) return false;
    if (EXISTENCE_DRILL.test(p.cmd) && !POST_SEARCH_NARROWING.test(p.cmd)) return false;
    if (sufficientBound(bareCmd)) return false;
    if (
      DOCUMENTED_ENUMERATION_EXEMPTIONS.some(
        (e) => e.file === p.file && p.cmd.includes(e.cmdIncludes),
      )
    ) {
      return false;
    }
    return true;
  });
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

  test("detector accepts --state appearing before --search", () => {
    expect(
      findStatelessProbes([
        { file: "f", raw: '`gh issue list --state closed --search "topic"`' },
      ]),
    ).toHaveLength(0);
  });

  // The three classes below were unfixtured in the first cut of this lint and ALL of
  // them fail-opened. They are the guard's real discriminating power: the live corpus
  // is clean, so the corpus assertion below compares [] to [] and proves nothing.
  const FENCE = "```";

  test("detector flags a stateless probe inside a fenced block", () => {
    expect(
      findStatelessProbes([
        {
          file: "f",
          raw: `${FENCE}bash\ngh pr list --search "#1 in:body is:merged" --json number\n${FENCE}`,
        },
      ]),
    ).toHaveLength(1);
  });

  test("a later --state in the same fence does not launder a stateless probe", () => {
    expect(
      findStatelessProbes([
        {
          file: "f",
          raw:
            `${FENCE}bash\ngh pr list --search "#1 in:body is:merged" --json number\n` +
            `gh issue list --state open --label foo\n${FENCE}`,
        },
      ]),
    ).toHaveLength(1);
  });

  test("each command in a fence is evaluated independently", () => {
    expect(
      findStatelessProbes([
        {
          file: "f",
          raw:
            `${FENCE}bash\ngh pr list --search "a" --state merged\n` +
            `gh pr list --search "#1 in:body is:merged"\n${FENCE}`,
        },
      ]),
    ).toHaveLength(1);
  });

  test("detector flags a query/flag state contradiction", () => {
    expect(
      findContradictingStateProbes([
        { file: "f", raw: '`gh pr list --search "#1 in:body is:merged" --state open`' },
      ]),
    ).toHaveLength(1);
  });

  test("detector accepts state pinned in exactly one place", () => {
    expect(
      findContradictingStateProbes([
        { file: "f", raw: '`gh pr list --search "#1 in:body" --state merged`' },
      ]),
    ).toHaveLength(0);
  });

  // -- #6793 truncation-detector controls -------------------------------------
  // Synthesized negative controls (cq-test-fixtures-synthesized-only). These are
  // the truncation detector's discriminating power independent of the live
  // corpus, so the offender assertion below can never go vacuously green.

  test("unlimited detector flags an enumerating probe with no -L/--limit", () => {
    expect(
      findUnlimitedProbes([
        { file: "f", raw: '`gh pr list --search "topic" --state all --json number`' },
      ]),
    ).toHaveLength(1);
  });

  test("unlimited detector accepts a pure existence drill (no narrowing)", () => {
    expect(
      findUnlimitedProbes([
        {
          file: "f",
          raw: '`gh issue list --state all --search "t in:title" --json number --jq \'.[0].number // empty\'`',
        },
      ]),
    ).toHaveLength(0);
  });

  test("unlimited detector accepts an explicit -L and --limit 1", () => {
    expect(
      findUnlimitedProbes([
        { file: "f", raw: '`gh pr list --search "topic" --state all -L 100 --json number`' },
        { file: "g", raw: '`gh pr list --search "topic" --state all --limit 1 --json number`' },
      ]),
    ).toHaveLength(0);
  });

  // The D2-soundness fix: a `.[0]`/`// empty` drill is NOT truncation-safe when a
  // `select(` narrows AFTER the search — the exact row can sit past the 30-row
  // cap and be evicted before the select sees it (content-publisher.sh:785).
  test("unlimited detector flags a select-after-search probe even with a trailing .[0]", () => {
    expect(
      findUnlimitedProbes([
        {
          file: "f",
          raw: '`gh issue list --state open --search "in:title \\"$t\\"" --json number,title --jq "[.[] | select(.title == \\"$t\\")] | .[0].number // empty"`',
        },
      ]),
    ).toHaveLength(1);
  });

  test("unlimited detector exempts the bounded linked:issue #N shape but not an unbounded query", () => {
    expect(
      findUnlimitedProbes([
        {
          file: "f",
          raw: '`gh pr list --search "linked:issue #5" --state all --json number --jq \'.[] | .number\'`',
        },
      ]),
    ).toHaveLength(0);
    expect(
      findUnlimitedProbes([
        {
          file: "f",
          raw: '`gh pr list --search "author:me #5" --state all --json number --jq \'.[] | .number\'`',
        },
      ]),
    ).toHaveLength(1);
  });

  test("a backslash-continued probe is captured whole, so a continuation-line --limit exempts it", () => {
    // Line-bounded capture would false-positive here (line 1 has no -L); joining
    // the `\`-continuation sees the --limit on line 2.
    expect(
      findUnlimitedProbes([
        {
          file: "f.sh",
          surface: "sh",
          raw: 'EXISTING=$(gh issue list --state all --search "PR #1" \\\n  --limit 1 --json number --jq \'.[0].number // empty\')',
        },
      ]),
    ).toHaveLength(0);
  });

  test("a .sh/.yml comment line describing a probe is not treated as a command", () => {
    expect(
      findStatelessProbes([
        { file: "f.sh", surface: "sh", raw: '  # dedup via `gh issue list --search "x"`' },
      ]),
    ).toHaveLength(0);
    expect(
      findUnlimitedProbes([
        { file: "f.yml", surface: "yaml", raw: '  # gh issue list --search "x" enumerates' },
      ]),
    ).toHaveLength(0);
  });

  test("a chained `&&`/`;` command cannot launder an earlier stateless/limitless probe", () => {
    // Both commands share ONE backslash-continued logical line; without the
    // statement-split the greedy capture would swallow the second command's
    // --state/--limit and hide the first (the #6786 launder class).
    const raw =
      'X=$(gh issue list --search "label:x" --json number && \\\n' +
      '  gh pr list --search "label:y" --state all --limit 50 --json number)';
    expect(findStatelessProbes([{ file: "f.sh", surface: "sh", raw }])).toHaveLength(1);
    expect(findUnlimitedProbes([{ file: "f.sh", surface: "sh", raw }])).toHaveLength(1);
  });

  test("a comment line ending in `\\` does not swallow the real probe on the next line", () => {
    // A shell/YAML `#` comment does NOT honour line continuation; joining it
    // would hide the following command inside a skipped comment.
    const raw = '# see the dedup note \\\ngh issue list --search "x in:title" --json number';
    expect(findStatelessProbes([{ file: "f.sh", surface: "sh", raw }])).toHaveLength(1);
    expect(findUnlimitedProbes([{ file: "f.sh", surface: "sh", raw }])).toHaveLength(1);
  });

  test("unlimited detector flags a reorder-after-search extreme-picker (sort_by | .[0])", () => {
    // The exact row (oldest/min/max) can be evicted past the 30-row cap before
    // the reorder runs — same fail-open class as select-after-search.
    expect(
      findUnlimitedProbes([
        {
          file: "f",
          raw: '`gh issue list --state all --search "label:x" --json number,createdAt --jq \'sort_by(.createdAt) | .[0].number\'`',
        },
      ]),
    ).toHaveLength(1);
  });

  test("unlimited detector flags a count-after-search even with a trailing existence token", () => {
    // Pins the `length` alternative of POST_SEARCH_NARROWING: a `.[0]`/`// empty`
    // token must NOT exempt a completeness-consuming count.
    expect(
      findUnlimitedProbes([
        {
          file: "f",
          raw: '`gh issue list --state all --search "x" --json number --jq \'.[0].total // empty | length\'`',
        },
      ]),
    ).toHaveLength(1);
  });

  test("unlimited detector does NOT exempt a bare `linked:issue` without #N", () => {
    // Pins the `#` anchor: a bare `linked:issue` (every PR linked to ANY issue)
    // is unbounded and must be flagged.
    expect(
      findUnlimitedProbes([
        {
          file: "f",
          raw: '`gh pr list --state all --search "linked:issue in:title" --json number --jq \'.[].number\'`',
        },
      ]),
    ).toHaveLength(1);
  });

  test("unlimited detector still flags a --label-bearing enumerating probe", () => {
    // Pins that HAS_LIMIT does not match inside `--label` and wrongly exempt.
    expect(
      findUnlimitedProbes([
        {
          file: "f",
          raw: '`gh issue list --label foo --state all --search "x" --json number --jq \'.[].number\'`',
        },
      ]),
    ).toHaveLength(1);
  });

  test("unlimited detector exempts each existence-drill token independently", () => {
    // Pins the `first(` and standalone `// empty` alternatives of EXISTENCE_DRILL
    // (fail-closed, but each alternative gets its own control).
    expect(
      findUnlimitedProbes([
        { file: "a", raw: '`gh pr list --state all --search "x" --json number --jq \'first(.[]).number\'`' },
        { file: "b", raw: '`gh pr list --state all --search "x" --json number --jq \'.total // empty\'`' },
      ]),
    ).toHaveLength(0);
  });

  // `skills/**/*.md` under PLUGIN_ROOT — the #6786 plugin-local surface, kept for
  // the inline-vs-fenced class assertion and the "wider than SKILL.md" widening
  // pin. #6793's offender assertions run over the repo-wide `corpus` below.
  const files = [...new Glob("skills/**/*.md").scanSync(PLUGIN_ROOT)].map((f) => ({
    file: f,
    raw: readFileSync(resolve(PLUGIN_ROOT, f), "utf-8"),
  }));

  // The #6793 repo-wide executable-surface corpus (skills/commands/agents docs,
  // shell scripts, hooks, CI workflows, ops runbooks). All offender assertions
  // run over THIS, so a stateless/truncatable probe anywhere an agent or CI runs
  // `gh` — not just under plugins/soleur/skills — red-lines here.
  const corpus = execSurfaceFiles();

  // Each declared surface CLASS must be non-empty in the live corpus, so a
  // silent per-surface drop (the Bun `dot:false` default that skipped the entire
  // .github/.claude surface, or a future glob regression) red-lines
  // here instead of letting the offender assertions pass vacuously against an
  // absent class. The dot-directory anchor pins the CI + hook surface directly.
  test("every executable-surface class is represented in the corpus", () => {
    const has = {
      md: corpus.some((f) => f.surface === "md"),
      sh: corpus.some((f) => f.surface === "sh"),
      yaml: corpus.some((f) => f.surface === "yaml"),
      dotDir: corpus.some((f) => f.file.startsWith(".github/") || f.file.startsWith(".claude/")),
    };
    expect(
      has,
      `corpus surface coverage ${JSON.stringify(has)} across ${corpus.length} files — a false ` +
        "here means an entire surface class (markdown docs / shell scripts / CI+hook YAML / " +
        "dot-directories) is silently absent from the scan, so its offender checks are vacuous",
    ).toEqual({ md: true, sh: true, yaml: true, dotDir: true });
  });

  // Anti-vacuity. A bare `length > 0` floor is too weak: narrowing the regex so it can
  // no longer see fenced probes leaves the inline ones behind, keeps the population
  // non-empty, and silently blinds the guard to a whole structural class. Bound EACH
  // class instead, so losing either one red-lines here.
  test("both probe classes are represented in the corpus", () => {
    const probes = extractSearchProbes(files);
    const inline = probes.filter((p) => !p.fenced).length;
    const fenced = probes.filter((p) => p.fenced).length;
    expect(
      { inline: inline > 0, fenced: fenced > 0 },
      `extraction saw ${inline} inline and ${fenced} fenced probes across ${files.length} ` +
        "files — a zero in either class means the glob or the regex stopped seeing that " +
        "shape, so the offender checks below are vacuous for it",
    ).toEqual({ inline: true, fenced: true });
  });

  // Pins the WIDENING itself. Without this, narrowing the glob back to
  // `skills/*/SKILL.md` stays green (the corpus is clean either way) and silently
  // re-blinds the lint to the deeper `references/` probe that review caught.
  test("the scan is wider than skills/*/SKILL.md", () => {
    expect(
      files.length,
      `scanned ${files.length} markdown files vs ${discoverSkills().length} SKILL.md files — ` +
        "the glob must stay wider than SKILL.md-only; a stateless probe living in " +
        "skills/*/references/ is exactly the case that escaped the first cut of this lint",
    ).toBeGreaterThan(discoverSkills().length);
  });

  // Pins the #6793 repo-wide widening the same way: the executable-surface corpus
  // must stay strictly wider than the plugin-local markdown surface, so narrowing
  // the allowlist back to plugins/soleur/skills/** red-lines here instead of going
  // vacuously green (the offender checks would then miss scripts/hooks/CI/runbooks).
  test("the executable-surface corpus is wider than the plugin-local surface", () => {
    expect(
      corpus.length,
      `scanned ${corpus.length} executable-surface files vs ${files.length} plugin-local ` +
        "markdown files — the repo-wide allowlist must admit scripts, hooks, CI workflows, " +
        "and runbooks; narrowing it back to skills/** re-blinds the lint to those surfaces",
    ).toBeGreaterThan(files.length);
  });

  test("no executable-surface probe omits --state", () => {
    expect(
      findStatelessProbes(corpus).map((o) => `${o.file}: ${o.cmd.slice(0, 90)}`),
      "`gh pr list --search` defaults to --state open and appends that filter unless it " +
        "detects an in-query state qualifier, so a probe without an explicit --state " +
        "silently misses MERGED/CLOSED records and the gate fails open. See #6786.",
    ).toEqual([]);
  });

  test("no executable-surface probe pins state in both the query and a flag", () => {
    expect(
      findContradictingStateProbes(corpus).map((o) => `${o.file}: ${o.cmd.slice(0, 90)}`),
      "this probe pins state twice (an `is:`/`state:` qualifier inside --search AND an " +
        "explicit --state). That is #6786's literal shape: the two are ANDed, so a " +
        "disagreement matches nothing and reads as a clean result. Pin state in one place.",
    ).toEqual([]);
  });

  test("no executable-surface probe omits -L/--limit without a principled exemption", () => {
    expect(
      findUnlimitedProbes(corpus).map((o) => `${o.file}: ${o.cmd.slice(0, 90)}`),
      "`gh pr list --search` caps its result set at 30 rows unless `-L`/`--limit` is given, " +
        "so an enumerating or completeness-consuming probe silently truncates and the gate " +
        "fails open. Add a generous explicit `-L` (free per the perf note) unless the probe " +
        "is a pure existence drill with no post-search narrowing OR the bounded `linked:issue " +
        "#N` shape. See #6793.",
    ).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// #8593 — unbounded-`gh`-enumeration detector. #6793's gate covered only
// `gh pr|issue list … --search` probes on a subset of surfaces; the identical
// silent-30-row truncation via `gh issue list --label X` (no --search),
// `gh search issues|prs`, non-paginated `gh api` list endpoints, and the
// `.github/scripts/` + `apps/web-platform/server/inngest/functions/*.ts`
// surfaces was invisible to every detector. This block widens the assembly,
// not the property: an enumeration- or post-narrowing-consuming `gh` capture on
// an executable surface must carry a SUFFICIENT bound (`-L N`/`--limit N` with
// N >= 100, or `--paginate` for `gh api`) or a principled exemption.
// ---------------------------------------------------------------------------
describe("unbounded gh enumerations carry an explicit sufficient bound (#8593)", () => {
  // Synthesized negative controls (cq-test-fixtures-synthesized-only) — Guard 1
  // matrix rows 1-7. The live corpus is clean, so these are the detector's only
  // real discriminating power.
  test("flags `gh issue list --label x --jq '.[].number'` with no -L (the issue's fixture)", () => {
    expect(
      findUnboundedEnumerations([
        { file: "f.sh", surface: "sh", raw: 'X=$(gh issue list --label x --state open --json number --jq \'.[].number\')' },
      ]),
    ).toHaveLength(1);
  });

  test("flags `-L 1` + `.[].number` — bound PRESENCE is not sufficiency", () => {
    expect(
      findUnboundedEnumerations([
        { file: "f.sh", surface: "sh", raw: 'X=$(gh issue list --label x -L 1 --json number --jq \'.[].number\')' },
      ]),
    ).toHaveLength(1);
  });

  test("flags `gh search issues … --jq 'length'` with no --limit", () => {
    expect(
      findUnboundedEnumerations([
        { file: "f.yml", surface: "yaml", raw: 'N=$(gh search issues "sec: alert repo:o/r is:open" --json number --jq \'length\')' },
      ]),
    ).toHaveLength(1);
  });

  test("flags `gh search prs` enumerations the same way", () => {
    expect(
      findUnboundedEnumerations([
        { file: "f.yml", surface: "yaml", raw: 'N=$(gh search prs "repo:o/r is:open" --json number --jq \'.[].number\')' },
      ]),
    ).toHaveLength(1);
  });

  test("flags `gh api` plural list endpoints feeding post-narrowing without --paginate", () => {
    expect(
      findUnboundedEnumerations([
        { file: "f.yml", surface: "yaml", raw: 'A=$(gh api "repos/o/r/issues?state=open" --jq \'.[].number\')' },
        { file: "g.sh", surface: "sh", raw: 'R=$(gh api repos/o/r/rulesets --jq \'.[] | select(.enforcement=="active")\')' },
        { file: "h.sh", surface: "sh", raw: 'Q=$(gh api "search/issues?q=foo&per_page=30" --jq \'.items[] | .number\')' },
      ]),
    ).toHaveLength(3);
  });

  test("flags `gh issue list … | grep` post-narrowing (the grep -cxF dedupe shape)", () => {
    expect(
      findUnboundedEnumerations([
        {
          file: "f.yml",
          surface: "yaml",
          raw: 'match=$(gh issue list --label review-reminder --state open --json title --jq \'.[].title\' | grep -cxF "$expected_title")',
        },
      ]),
    ).toHaveLength(1);
  });

  test("a second unbounded probe is flagged while a compliant sibling is not (per-capture)", () => {
    expect(
      findUnboundedEnumerations([
        {
          file: "f.sh",
          surface: "sh",
          raw:
            'OK=$(gh issue list --label a --state open --limit 100 --json number --jq \'.[].number\')\n' +
            'BAD=$(gh issue list --label b --state open --json number --jq \'.[].number\')',
        },
      ]),
    ).toHaveLength(1);
  });

  // Must-PASS inputs (Guard 1 matrix row 8), each differing from the canonical
  // bound in one way — a too-narrow exemption re-introduces the defect class
  // this gate exists to close.
  test("passes a --paginate gh api enumeration", () => {
    expect(
      findUnboundedEnumerations([
        { file: "f.sh", surface: "sh", raw: 'A=$(gh api --paginate "repos/o/r/issues?state=open&per_page=100" --jq \'.[].number\')' },
      ]),
    ).toHaveLength(0);
  });

  test("passes an -L 100 enumeration and a --limit 200 one", () => {
    expect(
      findUnboundedEnumerations([
        { file: "f.sh", surface: "sh", raw: 'A=$(gh issue list --label x --state open -L 100 --json number --jq \'.[].number\')' },
        { file: "g.yml", surface: "yaml", raw: 'B=$(gh search issues "q" --limit 200 --json number --jq \'length\')' },
      ]),
    ).toHaveLength(0);
  });

  test("passes a pure `.[0]`/`// empty` existence drill with no bound", () => {
    expect(
      findUnboundedEnumerations([
        { file: "f.yml", surface: "yaml", raw: 'E=$(gh issue list --label x --state open --json number --jq \'.[0].number // empty\')' },
        { file: "g.sh", surface: "sh", raw: 'N=$(gh api "repos/o/r/commits?sha=x&per_page=1" --jq \'.[0].commit.committer.date // empty\')' },
      ]),
    ).toHaveLength(0);
  });

  test("passes the bounded `linked:issue #N` query shape", () => {
    expect(
      findUnboundedEnumerations([
        { file: "f", raw: '`gh pr list --search "linked:issue #5" --state all --json number --jq \'.[] | .number\'`' },
      ]),
    ).toHaveLength(0);
  });

  test("passes a `gh pr list --head <branch>` post-narrowing probe (BOUNDED_HEAD)", () => {
    // CTO ruling 2026-11-01: `--head <branch>` is domain-bounded by headRefName
    // cardinality, the same argument as `linked:issue #N` — covers
    // bump-inngest-bootstrap-pin.sh's two post-narrowing --head probes, coded
    // as a pattern exemption so the judgment is enforced, not narrated.
    expect(
      findUnboundedEnumerations([
        {
          file: "f.sh",
          surface: "sh",
          raw: 'PR_LIST=$(gh pr list --repo "$R" --head "$BRANCH" --state open --json number,author --jq \'.[] | select(.author.login == "app/bot") | .number\')',
        },
      ]),
    ).toHaveLength(0);
  });

  test("does NOT flag `gh api` single-resource item reads (…/<resource>/<N>)", () => {
    expect(
      findUnboundedEnumerations([
        { file: "f.sh", surface: "sh", raw: 'gh api "repos/$REPO/pulls/$PR_NUMBER" --jq .created_at' },
        { file: "g.sh", surface: "sh", raw: 'gh api repos/o/r/issues/123 --jq .title' },
      ]),
    ).toHaveLength(0);
  });

  test("does NOT flag `gh api` bounded under-item collections (pulls/<N>/files, issues/<N>/comments, commits/<sha>/pulls)", () => {
    expect(
      findUnboundedEnumerations([
        { file: "f.sh", surface: "sh", raw: 'gh api "repos/o/r/pulls/123/files" --jq \'.[].filename\'' },
        { file: "g.sh", surface: "sh", raw: 'gh api "repos/o/r/issues/$N/comments" --jq \'.[] | .body\'' },
        { file: "h.sh", surface: "sh", raw: 'prs=$(gh api "repos/o/r/commits/${SHA}/pulls" | jq \'.[] | select(.state=="open")\')' },
      ]),
    ).toHaveLength(0);
  });

  test("does NOT flag `gh api` writes (POST/PUT/DELETE, graphql, -f payload)", () => {
    expect(
      findUnboundedEnumerations([
        { file: "f.sh", surface: "sh", raw: 'gh api -X POST "repos/$R/issues/$N/comments" -f body="$b"' },
        { file: "g.sh", surface: "sh", raw: 'gh api --method DELETE "repos/$R/issues/comments/$ID"' },
        { file: "h.sh", surface: "sh", raw: 'gh api graphql -f query="$q"' },
        { file: "i.sh", surface: "sh", raw: 'gh api "repos/$R/issues" -f title="$t" -f body="$b" -f labels[]=x' },
      ]),
    ).toHaveLength(0);
  });

  test("a full-line `//` comment in a .ts surface is skipped like a `#` comment", () => {
    expect(
      findUnboundedEnumerations([
        {
          file: "f.ts",
          surface: "ts",
          raw:
            "// gh issue list --label x --state open --json number --jq '.[].number'\n" +
            "// and a second comment: gh api repos/o/r/issues --jq '.[].n'\n" +
            "const x = 1;",
        },
      ]),
    ).toHaveLength(0);
  });

  test("a .ts capture still flags a real enumeration instruction", () => {
    expect(
      findUnboundedEnumerations([
        {
          file: "f.ts",
          surface: "ts",
          raw: 'const PROMPT = `run: gh issue list --label x --state open --json number --jq \'.[].number\'`;',
        },
      ]),
    ).toHaveLength(1);
  });

  // forConsumed axis (test-design seat, PR #11782 — it was a mutation survivor
  // with no discriminating fixture): the close-enumeration `for n in $(gh …)`
  // shape IS the scheduled-inngest-health.yml arm this detector exists for.
  test("flags an unbounded `for n in $(gh issue list …)` close-enumeration loop", () => {
    expect(
      findUnboundedEnumerations([
        {
          file: "f.yml",
          surface: "yaml",
          raw: 'for n in $(gh issue list --repo "$R" --label x --state open --json number --jq \'.[].number\'); do gh issue close "$n"; done',
        },
      ]),
    ).toHaveLength(1);
  });

  test("passes the same for-loop with --limit 100 (the corpus convention)", () => {
    expect(
      findUnboundedEnumerations([
        {
          file: "f.yml",
          surface: "yaml",
          raw: 'for n in $(gh issue list --repo "$R" --label x --state open --limit 100 --json number --jq \'.[].number\'); do gh issue close "$n"; done',
        },
      ]),
    ).toHaveLength(0);
  });

  test("flags a zero-arg / paren-terminated capture the old \\b terminator dropped", () => {
    expect(
      findUnboundedEnumerations([
        { file: "f.sh", surface: "sh", raw: 'for n in $(gh issue list); do echo "$n"; done' },
      ]),
    ).toHaveLength(1);
  });

  test("flags `gh api -X GET <list> -f q=…` — explicit GET defeats the -f write arm", () => {
    expect(
      findUnboundedEnumerations([
        { file: "f.sh", surface: "sh", raw: 'A=$(gh api -X GET "repos/o/r/issues?state=open" -f per_page=30 --jq \'.[].number\')' },
      ]),
    ).toHaveLength(1);
  });

  test("flags bare `gh api users`/`gh api orgs` root collections", () => {
    expect(
      findUnboundedEnumerations([
        { file: "f.sh", surface: "sh", raw: 'U=$(gh api users --jq \'.[].login\')' },
      ]),
    ).toHaveLength(1);
  });

  test("a bound token inside a quoted --search string is data, not a bound", () => {
    expect(
      findUnboundedEnumerations([
        { file: "f.sh", surface: "sh", raw: 'X=$(gh issue list --search "fix --limit 100 regression" --json number --jq \'.[].number\')' },
      ]),
    ).toHaveLength(1);
  });

  test("`--head` inside a quoted --jq/--search arg does not exempt", () => {
    expect(
      findUnboundedEnumerations([
        { file: "f.sh", surface: "sh", raw: 'X=$(gh issue list --label x --json number --jq \'.[].number | "--head"\')' },
      ]),
    ).toHaveLength(1);
  });

  test("flags an OR-widened linked:issue search (`linked:issue # OR …` is not bounded)", () => {
    expect(
      findUnboundedEnumerations([
        { file: "f.sh", surface: "sh", raw: 'X=$(gh pr list --search "linked:issue # OR is:open" --json number --jq \'.[].number\')' },
      ]),
    ).toHaveLength(1);
  });

  test("flags a `.[0]` drill that ALSO reads a later row (`,`-separated jq)", () => {
    expect(
      findUnboundedEnumerations([
        { file: "f.sh", surface: "sh", raw: 'X=$(gh issue list --label x --json number | jq \'.[0].number, .[1].number\')' },
      ]),
    ).toHaveLength(1);
  });

  test("a write arm inside a --field value does not exempt (`-f 'q=-X POST'` is data)", () => {
    expect(
      findUnboundedEnumerations([
        { file: "f.sh", surface: "sh", raw: 'A=$(gh api -X GET "repos/o/r/issues?state=open" -f \'q=-X POST\' --jq \'.[].number\')' },
      ]),
    ).toHaveLength(1);
  });

  test("passes a bare `gh api user` item read", () => {
    expect(
      findUnboundedEnumerations([
        { file: "f.sh", surface: "sh", raw: 'gh api user --jq \'.login\'' },
      ]),
    ).toHaveLength(0);
  });

  // The #8593 widening pins, same idiom as the #6793 surface pins above: the
  // new surface classes and the new command families must each be non-empty in
  // the live corpus, or the corpus assertion below is vacuous for them.
  const corpus = execSurfaceFiles();

  test("the widened surface classes are represented in the corpus", () => {
    const has = {
      githubScripts: corpus.some((f) => f.file.startsWith(".github/scripts/") && f.surface === "sh"),
      inngestFns: corpus.some(
        (f) => f.file.startsWith("apps/web-platform/server/inngest/functions/") && f.surface === "ts",
      ),
    };
    expect(
      has,
      `corpus surface coverage ${JSON.stringify(has)} — a false means a widened surface class ` +
        "(.github/scripts/**.sh, inngest functions/*.ts) is silently absent from the scan, " +
        "so the enumeration offender check is vacuous for it",
    ).toEqual({ githubScripts: true, inngestFns: true });
  });

  test("every command family is represented in the corpus", () => {
    const enums = extractEnumerations(corpus);
    const families = {
      list: enums.some((p) => p.kind === "list"),
      search: enums.some((p) => p.kind === "search"),
      api: enums.some((p) => p.kind === "api"),
    };
    expect(
      families,
      `extraction saw ${JSON.stringify(families)} across ${corpus.length} files — a false ` +
        "means a command family (gh pr|issue list / gh search issues|prs / gh api list " +
        "endpoints) is regex-invisible, so the offender check is vacuous for it",
    ).toEqual({ list: true, search: true, api: true });
  });

  test("no executable-surface enumeration lacks a sufficient bound or a principled exemption", () => {
    expect(
      findUnboundedEnumerations(corpus).map((o) => `${o.file}: ${o.cmd.slice(0, 90)}`),
      "a `gh` enumeration that feeds `.[]`, `| grep`, `select(`, `map(`, `length` or a reorder " +
        "silently truncates at the default row cap unless it carries `-L N`/`--limit N` " +
        "(N >= 100) or `--paginate`, or qualifies for a coded exemption (pure existence " +
        "drill with no post-search narrowing, `linked:issue #N`, or `--head <branch>`). " +
        "See #8593 — every site this widened gate flags must be bounded or carry a " +
        "documented exclusion in the same diff.",
    ).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Plugin slash-name uniqueness
//
// No name is PRESENTED twice to a user for any harness this plugin ships to.
// "Presented" rather than "registered": a skill that is registered but not
// user-invocable is reachable by the model and absent from the `/` menu.
//
// Deliberately its own block, not folded into "Kebab-case filenames" — that one
// is about naming FORM, this is about namespace UNIQUENESS, and a failure filed
// under the wrong heading reads as contradicting itself.
// ---------------------------------------------------------------------------
describe("plugin slash-name uniqueness", () => {
  // Discovered by dirent scan, NOT by enumerating the three manifests that
  // exist today, so a future `.grok-plugin/plugin.json` is covered by
  // construction. Bun's Glob does not match dot-directories — a `.*-plugin`
  // glob returns [] and would report a clean sweep having looked at nothing.
  const manifestDirs = readdirSync(PLUGIN_ROOT, { withFileTypes: true })
    .filter((d) => d.isDirectory() && /^\..+-plugin$/.test(d.name))
    .map((d) => d.name)
    .sort();

  const commandNames = discoverCommands().map((c) => getComponentName(c, "command"));

  const rootsFor = (manifestDir: string) => {
    const manifestPath = resolve(PLUGIN_ROOT, manifestDir, "plugin.json");
    const manifest = JSON.parse(readFileSync(manifestPath, "utf-8")) as {
      skills?: string[];
    };
    // The `skills` key is ADDITIVE in Claude Code, never a replacement, so the
    // default scan is always a member. Duplicate spellings collapse inside
    // collidingNames().
    //
    // CAVEAT, harness-qualified per ADR-224 decision 1: this models EVERY
    // manifest as additive, and ADR-215 §Verification measured Codex as
    // replace-default (a single custom root HID the canonical skills). That is
    // harmless only because `.codex-plugin` declares `./skills` explicitly today.
    // If that declaration were ever dropped, this would inject a root Codex does
    // not scan, report the acked dupes, and go green over ADR-215's measured
    // failure mode. Codex's coverage is scripts/codex-plugin-smoke.mjs, not this
    // guard — but note what that script actually establishes: its "101 skills" is
    // `expectedSkills`, computed locally as the 98 SKILL.md directories plus an
    // unconditional push of three names already among the 98, BEFORE it contacts
    // Codex. Only `discoveredSkills` would prove two-root resolution, and nothing
    // in the repo captures it. Inferred from the manifest, not measured.
    const declared = Array.isArray(manifest.skills) ? manifest.skills : [];
    return ["skills", ...declared].map((root) => ({
      root,
      skills: discoverSkillsIn(root).map((p) => ({
        name: getComponentName(p, "skill"),
        userInvocable: isUserInvocable(p),
      })),
    }));
  };

  // Known, deliberate cross-root duplication, MEASURED rather than inferred:
  // `devin skills list` reports /soleur:go from BOTH `skills/go` and
  // `devin/skills/go`, each [user,model]. The Codex and Devin manifests declare
  // two roots and the three entry-point shims live in both.
  //
  // Collapsing it means DELETING the shared shims, and that is blocked on devin,
  // codex and grok, not on Claude Code dispatch.
  //
  // CORRECTED 2026-09-17 by measurement. This comment previously said
  // `plugins/soleur/skills/go/` is the only model-invocable `Skill(soleur:go)`
  // handle and that `commands/go.md` is user-typed only. Both are FALSE on Claude
  // Code: probed with all three shims deleted, `Skill(soleur:help)` still
  // succeeds and returns `commands/help.md`, because commands are
  // model-invocable and SHADOW the same-named skill. The correction is recorded
  // here rather than applied silently because the false version was the stated
  // reason #8236 was deferred — and because it survived in THIS carrier after
  // being retracted elsewhere in the same file, leaving the file asserting both.
  //
  // What actually blocks the deletion: `devin skills list` resolves these three
  // names from both roots, `.codex-plugin` declares `./skills`, and
  // `.grok/config.toml` loads this same tree. Claude Code happens to absorb the
  // deletion; devin, codex and grok do not.
  //
  // Ack'd BY NAME so a NEW cross-root duplicate — the class this clause exists
  // to catch — still reds; mutation row M6 proves that. Adding a name here is a
  // deliberate act, not a baseline regeneration.
  //
  // Retired by #8236, which deletes the shared shims once the dispatch
  // replacement lands. The issue number is inline so the ack is traceable to the
  // thing that ends it rather than outliving its reason silently.
  const ACKED_CROSS_ROOT_DUPES = new Set(["go", "help", "sync"]);

  // The roots Claude Code itself resolves: the default scan plus whatever the
  // Claude manifest declares (the key is ADDITIVE there). Clause (c) forbids
  // that key, so this is `["skills"]` today — derived, not assumed, so clause
  // (b) stays correct if clause (c) is ever relaxed.
  const claudeRoots = (() => {
    const m = JSON.parse(
      readFileSync(resolve(PLUGIN_ROOT, ".claude-plugin", "plugin.json"), "utf-8"),
    ) as { skills?: string[] };
    return [...new Set(["skills", ...(Array.isArray(m.skills) ? m.skills : [])])];
  })();

  test("discovers the manifests and components it is asserting over", () => {
    // A guard whose inputs came back empty reports a clean sweep having looked
    // at nothing, so each floor below is the emptiness this guard cannot
    // tolerate — not a count that ordinary growth has to keep up with.
    //
    // `commandNames` is the load-bearing one: if command discovery returned [],
    // clause (b) compares against an empty set and passes VACUOUSLY on every
    // skill in the tree.
    // Pinned, not floored: a cardinality floor cannot tell "one manifest" from
    // "all manifests", and narrowing the dirent regex to `.claude-plugin` (the
    // one manifest that structurally cannot fail clause (a)) would drop both
    // real rows while a >= 1 floor stayed green.
    expect(manifestDirs).toEqual([".antigravity-plugin", ".claude-plugin", ".codex-plugin", ".cursor-plugin", ".devin-plugin"]);

    // Identity, not just count: three WRONG stems satisfy a length floor, and
    // clause (b) would then compare against names no command has.
    expect(commandNames).toEqual(expect.arrayContaining(["go", "help", "sync"]));
    expect(commandNames.length).toBeGreaterThanOrEqual(3);

    // Swept over the OPERAND clause (b) consumes, not over the literal "skills".
    // Pointing claudeRoots at a nonexistent directory otherwise leaves clause (b)
    // scanning zero skills and comparing [] to [] while this floor still reports
    // a healthy corpus from a root clause (b) no longer reads.
    expect(claudeRoots.length).toBeGreaterThanOrEqual(1);
    for (const root of claudeRoots) {
      expect(discoverSkillsIn(root).length, `claude root '${root}' resolved no skills`).toBeGreaterThan(0);
    }

    // At least two manifests must reach clause (a)'s real assertion rather than
    // its single-root early return — otherwise emptying `manifest.skills` sends
    // every manifest down the escape hatch, which emits a PASSING expect().
    //
    // COUNT DISTINCT NORMALIZED ROOTS, NOT RAW DECLARATIONS. `rootsFor` returns
    // `["skills", ...declared]` verbatim, while `collidingNames()` collapses
    // spellings before it compares anything. A floor over the raw list therefore
    // measures a DIFFERENT operand than the assertion it backstops: a manifest
    // declaring `["./skills"]` yields `["skills", "./skills"]` — ONE directory —
    // and satisfies a `.length >= 2` floor as "multi-root" while clause (a) sees
    // a single root and takes the early return.
    //
    // Measured, not reasoned: with `declared` forced to `["./skills"]` and a real
    // `devin/skills/review/SKILL.md` added (mutation row M6, the row the matrix
    // calls its most important), the raw-length floor reported 1348 pass / 0 fail
    // while `.devin-plugin` still resolved `review` from two roots. That is the
    // "floor that does not read the operand the assertion consumes" shape — the
    // one this guard set exists to refuse — reproduced inside the guard itself.
    const distinctRoots = (d: string) =>
      new Set(rootsFor(d).map((r) => normalizeSkillRoot(r.root))).size;
    expect(
      manifestDirs.filter((d) => distinctRoots(d) >= 2).length,
      "no manifest reached the multi-root path; clause (a) asserted nothing",
    ).toBeGreaterThanOrEqual(2);
  });

  // The ack is pinned to its exact membership, not floored. Shrinking it is as
  // deliberate an act as growing it: a name removed here before #8236 actually
  // deletes the shim would red clause (a) with no reader able to tell whether
  // that was the intended retirement or an accident.
  test("the cross-root ack is exactly the three names #8236 retires", () => {
    expect([...ACKED_CROSS_ROOT_DUPES].sort()).toEqual(["go", "help", "sync"]);
  });

  // Clause (b) goes GREEN if these skills are DELETED — greener, in fact, since a
  // deleted skill cannot collide with a command stem. So without this, the guard
  // set's gradient points at removing the very files the PR exists to keep.
  //
  // CORRECTED 2026-09-17 by measurement. An earlier version of this comment said
  // `skills/go/` is the SOLE model-invocable `Skill(soleur:go)` handle and that
  // `commands/go.md` is user-typed only. Both are FALSE on Claude Code: probed
  // with all three shims deleted, `Skill(soleur:help)` still succeeds and returns
  // `commands/help.md`. Commands are model-invocable and SHADOW the same-named
  // skill, so the command supplies the handle and the skill is a fallback behind
  // it.
  //
  // What this still guards, and why it is not merely belt-and-braces: devin,
  // codex and grok DO resolve these paths. `devin skills list` reports
  // /soleur:go; `.codex-plugin` declares `./skills` AND `./codex/skills`;
  // `.grok/config.toml` loads this tree. Deleting them is a real change on those
  // three harnesses even though Claude Code absorbs it. Retired with #8236, which
  // owns that deletion.
  //
  // CORRECTED 2026-09-23 by measurement (#8390 bundle). An earlier version of
  // this comment said Devin "reports /soleur:go from BOTH roots". Measured on
  // Devin CLI 3000.11.1, `devin skills list` reports each of the 102 names
  // exactly ONCE — the double-listing was an earlier version's behaviour. Codex
  // 0.156.1 IS the harness that lists both roots (`go`/`help`/`sync` twice),
  // which is what this ack set exists for. The `harness-discovery` gate
  // (ADR-245) now measures the multiplicity of both on every CI run, so this
  // claim stops being a comment anybody has to trust.
  //
  // Derived from ACKED_CROSS_ROOT_DUPES rather than restated: two parallel
  // hardcoded lists drift under a partial #8236 retirement, and an empty literal
  // array here would silently delete every assertion below it.
  for (const name of [...ACKED_CROSS_ROOT_DUPES]) {
    test(`skills/${name}/ survives as a model-invocable dispatch handle`, () => {
      const rel = `skills/${name}/SKILL.md`;
      expect(
        existsSync(resolve(PLUGIN_ROOT, rel)),
        `${rel} is resolved by Codex, Devin and Grok (measured: devin skills ` +
          `list reports /soleur:${name} from this root). Claude Code absorbs its ` +
          `deletion because commands/${name}.md shadows it, but devin, codex and ` +
          `grok do not. Deletion is owned by #8236, not by an edit here.`,
      ).toBe(true);
      const fm = parseComponent(rel).frontmatter;
      expect(
        fm["disable-model-invocation"],
        `${rel} must stay MODEL-invocable. \`user-invocable: false\` hides it ` +
          `from the / menu and is correct; \`disable-model-invocation: true\` ` +
          `would hide it from the model, which is the dispatch regression.`,
      ).toBeUndefined();
      expect(fm["user-invocable"], `${rel} should stay hidden from the / menu`).toBe(false);
    });
  }

  // Skills that must stay MODEL-invocable although they read as operator tooling (#8290,
  // ADR-236). Their own set, not ACKED_CROSS_ROOT_DUPES: that set is pinned to go/help/sync and
  // also asserts `user-invocable: false`, which these do not carry.
  const MUST_STAY_INVOCABLE: Record<string, string> = {
    "trigger-cron":
      "an always-loaded rule (hr-no-dashboard-eyeball-pull-data-yourself) and the incident, " +
      "gdpr-gate and reproduce-bug skills direct the AGENT to fire crons itself",
    invoice:
      "a founder-facing capability (ADR-107); the web Command Center reaches skills only " +
      "through the model (prompt-injection-wrap.ts POSTAMBLE), so a user-invoked invoice is " +
      "unreachable on the web",
    "flag-list":
      "a read-only drift audit the agent must pull itself, and the blast-radius step " +
      "flag-delete calls before deleting",
    "flag-create":
      "plans prescribe it as an agent acceptance step (wg-plan-prescribed-skills-must-run-inline); " +
      "the agent runs create.sh --dry-run and hands the operator the printed write command, " +
      "which needs a typed yes at the operator's own terminal (ADR-249, #8486)",
    "flag-set-role":
      "plans prescribe it as an agent acceptance step; the agent runs flip.sh --dry-run and " +
      "hands off the printed write command, which needs a typed yes at a TTY (ADR-249, #8486)",
    "cron-list":
      "read-only, pulled by the agent itself like flag-list; soleur:schedule runs the same " +
      "steps in place, so a refusal only contradicts it",
    "cron-delete":
      "soleur:schedule runs the same delete step in place behind its confirm gate; a refusal " +
      "contradicts schedule/SKILL.md",
  };
  test("MUST_STAY_INVOCABLE is exactly the reviewed set", () => {
    expect(Object.keys(MUST_STAY_INVOCABLE).sort()).toEqual([
      "cron-delete",
      "cron-list",
      "flag-create",
      "flag-list",
      "flag-set-role",
      "invoice",
      "trigger-cron",
    ]);
  });
  for (const [name, reason] of Object.entries(MUST_STAY_INVOCABLE)) {
    test(`skills/${name}/ stays model-invocable (must-stay-invocable pin)`, () => {
      const fm = parseComponent(`skills/${name}/SKILL.md`).frontmatter;
      expect(
        fm["disable-model-invocation"],
        `skills/${name}/SKILL.md must stay MODEL-invocable: ${reason}. See ADR-236.`,
      ).toBeUndefined();
    });
  }

  for (const manifestDir of manifestDirs) {
    // Clause (a) — buys the skills-vs-skills class (two roots resolving one name).
    test(`${manifestDir}: no skill name is contributed by more than one root`, () => {
      // A manifest resolving a single root cannot contribute a name twice, so
      // asserting over it is structurally unable to fail. Declare that rather
      // than letting it read as coverage.
      if (rootsFor(manifestDir).length < 2) {
        expect(rootsFor(manifestDir).length).toBe(1);
        return;
      }
      const { duplicateSkillNames } = collidingNames({
        commandNames: [],
        skillRoots: rootsFor(manifestDir),
      });
      const unacked = unackedDuplicates(duplicateSkillNames, ACKED_CROSS_ROOT_DUPES);
      expect(
        unacked,
        `${manifestDir} resolves these skill names from more than one root: ` +
          `${unacked.join(", ")}. Two roots resolving one name is a loader ambiguity ` +
          `for every harness. Either remove the duplicate directory or, if the ` +
          `duplication is deliberate, add it to ACKED_CROSS_ROOT_DUPES with a reason.`,
      ).toEqual([]);
    });

  }

  // Clause (b) — buys the commands-vs-skills class this PR fixes.
  //
  // Scoped to the roots the CLAUDE manifest resolves, DERIVED rather than
  // restated: `commands/` shares a menu namespace only on Claude Code, and the
  // per-harness roots (`codex/skills/`, `devin/skills/`) are simply not in this
  // manifest, so their exemption falls out of the derivation instead of needing
  // a hand-picked string and a paragraph defending it. Those roots exist to
  // expose a canonical `commands/<name>.md` as a SKILL on a harness with no
  // command surface, so mirroring a command stem there is the intended design.
  test("user-invocable skills in Claude's roots are disjoint from command stems", () => {
    const { commandCollisions } = collidingNames({
      commandNames,
      skillRoots: claudeRoots.map((root) => ({
        root,
        skills: discoverSkillsIn(root).map((p) => ({
          name: getComponentName(p, "skill"),
          userInvocable: isUserInvocable(p),
        })),
      })),
    });
    expect(
      commandCollisions,
      `These names render TWICE in the Claude Code slash menu — once from ` +
        `plugins/soleur/commands/<name>.md and once from a user-invocable skill ` +
        `of the same name: ${commandCollisions.join(", ")}. Add ` +
        `\`user-invocable: false\` to the skill's frontmatter (it stays ` +
        `model-invocable and leaves the menu), or rename one side.`,
    ).toEqual([]);
  });

  // Clause (c) — stronger than (b) on purpose: it fails even on a NON-colliding
  // addition. Claude Code is the one harness whose default `skills/` scan shares
  // a namespace with `commands/`, and it has no denylist, so the only safe number
  // of additive roots there is zero.
  test(".claude-plugin/plugin.json declares no component-registering key", () => {
    const manifestPath = resolve(PLUGIN_ROOT, ".claude-plugin", "plugin.json");
    const manifest = JSON.parse(readFileSync(manifestPath, "utf-8")) as Record<string, unknown>;

    expect(
      "skills" in manifest,
      "Claude Code's `skills` key is ADDITIVE, so declaring a per-harness root " +
        "here re-creates the duplicate menu rows this guard exists to prevent. " +
        "Per-harness roots belong in .codex-plugin / .devin-plugin only.",
    ).toBe(false);

    // `commands`, `agents` and `workflows` REPLACE their default directory
    // (documented: "when the manifest specifies `commands`, the default
    // `commands/` directory is not scanned"). That is a sharper hazard than the
    // additive `skills` key and clause (b) cannot see it: declaring `commands`
    // stops the three canonical command rows rendering, while discoverCommands()
    // still reads them off disk — so clause (b) would assert against commands
    // that no longer exist, and because the three skills carry
    // `user-invocable: false`, /soleur:go|help|sync would vanish from the menu
    // ENTIRELY with this guard green.
    for (const key of ["commands", "agents", "workflows"]) {
      expect(
        key in manifest,
        `\`${key}\` REPLACES its default directory rather than adding to it, so ` +
          `declaring it here silently un-registers everything under ${key}/. If ` +
          `this is ever needed, the default must be listed explicitly ` +
          `(e.g. "${key}": ["./${key}/", "./extras/"]) and this guard updated.`,
      ).toBe(false);
    }
  });

  describe("harness documentation parity", () => {
    const harnesses: { id: string; label: string; tableHeader: string }[] = [
      { id: "claude", label: "Claude Code", tableHeader: "Claude Code" },
      { id: "codex", label: "Codex", tableHeader: "Codex" },
      { id: "devin", label: "Devin CLI", tableHeader: "Devin CLI" },
      { id: "grok", label: "Grok Build", tableHeader: "Grok Build" },
      { id: "opencode", label: "OpenCode", tableHeader: "OpenCode" },
      { id: "antigravity", label: "Google Antigravity CLI", tableHeader: "Google Antigravity" },
    ];

    test("README.md contains an installation section for every supported harness", () => {
      const repoRoot = resolve(PLUGIN_ROOT, "../..");
      const readmePath = resolve(repoRoot, "README.md");
      const readme = readFileSync(readmePath, "utf-8");

      for (const h of harnesses) {
        expect(
          readme.includes(h.label),
          `README.md is missing an installation section for harness '${h.id}' (${h.label}). ` +
            "When adding or modifying a harness in lib/harness.ts, update README.md.",
        ).toBe(true);
      }
    });

    test("getting-started.njk documents every supported harness in prose and comparison table", () => {
      const gettingStartedPath = resolve(PLUGIN_ROOT, "docs", "pages", "getting-started.njk");
      const content = readFileSync(gettingStartedPath, "utf-8");

      for (const h of harnesses) {
        expect(
          content.includes(h.label),
          `getting-started.njk is missing documentation for harness '${h.id}' (${h.label}).`,
        ).toBe(true);
        expect(
          content.includes(`<th>${h.tableHeader}</th>`),
          `getting-started.njk table is missing header column <th>${h.tableHeader}</th> for harness '${h.id}'.`,
        ).toBe(true);
      }
    });
  });
});
