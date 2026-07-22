import { describe, test, expect } from "bun:test";
import { Glob } from "bun";
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
const GH_LIST_CMD = /\bgh (?:pr|issue) list\b[^`\n]*/g;

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
  ".claude/hooks/**/*.sh",
  ".openhands/hooks/**/*.sh",
  ".github/workflows/**/*.yml",
  ".github/workflows/**/*.yaml",
  ".github/actions/**/*.yml",
  ".github/actions/**/*.yaml",
  "knowledge-base/engineering/operations/runbooks/**/*.md",
];

type Surface = "md" | "sh" | "yaml";

function surfaceOf(path: string): Surface {
  if (path.endsWith(".sh")) return "sh";
  if (path.endsWith(".yml") || path.endsWith(".yaml")) return "yaml";
  return "md";
}

/** The repo-wide executable-surface corpus (deduped; *.test.sh excluded). */
function execSurfaceFiles(): { file: string; raw: string; surface: Surface }[] {
  const seen = new Set<string>();
  const out: { file: string; raw: string; surface: Surface }[] = [];
  for (const glob of EXEC_SURFACE_GLOBS) {
    for (const rel of new Glob(glob).scanSync(REPO_ROOT)) {
      // Test fixtures deliberately encode the broken form; never admit them,
      // even a future scripts/foo.test.sh landing under an included glob.
      if (rel.endsWith(".test.sh")) continue;
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

// Join explicit shell/YAML-block line continuations (a physical line ending in
// `\`) into ONE logical line, so a multi-line `gh … list` is captured whole —
// its --limit or jq drill routinely lives on a continuation line, and a
// line-bounded capture would both MISS that drill (false negative on the
// select-after-truncation class) and FALSE-POSITIVE on a correct probe whose
// --limit is one line down. This does NOT reintroduce the launder-by-neighbor
// bug (#6786): only backslash-continued lines are joined — they are
// unambiguously ONE command — and GH_LIST_CMD stays newline-bounded, so an
// UNcontinued neighbour on the next line is never swallowed.
function joinContinuations(raw: string): string[] {
  const out: string[] = [];
  let buf: string | null = null;
  for (const line of raw.split("\n")) {
    const cont = /\\\s*$/.test(line);
    const body = cont ? line.replace(/\\\s*$/, "") : line;
    buf = buf === null ? body : `${buf} ${body.replace(/^\s+/, "")}`;
    if (!cont) {
      out.push(buf);
      buf = null;
    }
  }
  if (buf !== null) out.push(buf);
  return out;
}

interface Probe {
  file: string;
  cmd: string;
  /** True when the command sits inside a fenced code block rather than an inline span. */
  fenced: boolean;
}

/** Every `gh pr|issue list` command carrying `--search`, one entry per command. */
export function extractSearchProbes(
  files: { file: string; raw: string; surface?: Surface }[],
): Probe[] {
  return files
    .flatMap(({ file, raw, surface = "md" }) => {
      const found: Probe[] = [];
      let fenced = false;
      for (const line of joinContinuations(raw)) {
        if (surface === "md" && /^\s*```/.test(line)) {
          fenced = !fenced;
          continue;
        }
        // Shell/YAML comment lines are the prose surface — they DESCRIBE a
        // command, they do not run it. Markdown has no comment convention here;
        // its prose-vs-command boundary is the fence/backtick handled above.
        if (surface !== "md" && /^\s*#/.test(line)) continue;
        for (const m of line.matchAll(GH_LIST_CMD)) {
          found.push({ file, cmd: m[0].trim(), fenced });
        }
      }
      return found;
    })
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
// boundary so it cannot match inside `--label`.
const HAS_LIMIT = /(?:^|\s)(?:-L|--limit)(?:[=\s]|$)/;
// A pure existence drill: reduce the result to "does ≥1 row exist?". Safe at the
// 30-row cap — if >30 rows match, ≥1 certainly does.
const EXISTENCE_DRILL = /\.\[0\]|\/\/\s*empty|first\s*\(/;
// A result-set narrowing that runs AFTER the search, so it operates on the
// already-truncated 30 rows: an exact-match select, or a count. When present,
// the existence drill is NOT truncation-safe — the row the decision needs can
// sit past row 30 and be evicted before the narrowing sees it (the
// content-publisher.sh select-after-search fail-open the #6793 deepen surfaced).
const POST_SEARCH_NARROWING = /select\s*\(|\blength\b/;
// A single issue's FORMALLY-linked PR set is bounded by domain semantics well
// under 30, so a `linked:issue #N` probe never needs an explicit cap (D2b). The
// `#` anchor keeps this from exempting an unrelated string containing
// "linked:issue". This is what keeps one-shot/SKILL.md:55 byte-identical.
const BOUNDED_LINKED_ISSUE = /linked:issue\s+#/;

/**
 * Search probes that neither cap the result set (`-L`/`--limit`) nor qualify for
 * a principled exemption — the #6793 silent-truncation defect class. Exemptions:
 *   (a) a pure existence drill with NO post-search narrowing, or
 *   (b) the bounded `linked:issue #N` query shape.
 */
export function findUnlimitedProbes(
  files: { file: string; raw: string; surface?: Surface }[],
): Probe[] {
  return extractSearchProbes(files).filter(({ cmd }) => {
    if (HAS_LIMIT.test(cmd)) return false;
    if (BOUNDED_LINKED_ISSUE.test(cmd)) return false;
    if (EXISTENCE_DRILL.test(cmd) && !POST_SEARCH_NARROWING.test(cmd)) return false;
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
