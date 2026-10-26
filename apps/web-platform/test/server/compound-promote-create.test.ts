// WikiSkill Phase 2 (#10550) -- the pure create-arm module (Phase 3, RED first).
//
// PROPERTY (Guard 1): no byte reaches `safeCommitAndPr` in the create arm unless every gate in the fixed
// order passed and the committed path set equals the closed six-path set. This file owns the PURE half:
// output schema, shape allowlist, claim words, PII/credential screens, slug, overlap ranking, budget
// counter, renderers and the `checkCreate` verdict union. The spawn-based half is in
// compound-promote-create-gates.test.ts and the real-tree parity half in compound-promote-create-parity.test.ts.
//
// ASSEMBLY: one chokepoint, `checkCreate()` for the model's structured output and `checkRenderedCreate()`
// for the rendered bytes. Members that must flow through it: every model string (description, every list
// item, the justification, purpose fields, slug, pattern slug, nearest skill), the rendered SKILL.md,
// PURPOSE.md and Cursor stub, and the path set.
//
// ANCHOR: the path set and every numeric limit are exported constants asserted here against literals AND
// against the ADR-092 amendment wording (stripped of fences); a diff weakening a gate must move the
// independently reviewed ADR text and the golden fixtures too. Residual: this proves consistency, the
// human-reviewed draft PR is the integrity anchor.
//
// Every "mutation row" below simulates the named mutation on the input (or on an injected collaborator) and
// asserts the gate goes RED; a row whose mutation helper silently returns the input unchanged is caught by
// the self-checks at the bottom.
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { createHash } from "node:crypto";
import { dirname, join } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: vi.fn(),
}));

import { CREDENTIAL_RE, PII_REGEX } from "@/server/inngest/functions/cron-compound-promote";
import {
  CREATE_DESCRIPTION_MAX_WORDS,
  CREATE_DESCRIPTION_MIN_WORDS,
  CREATE_FILE_MAX_BYTES,
  CREATE_FILE_MAX_LINES,
  CREATE_GATES,
  CREATE_INPUT_BYTES_PER_TOKEN,
  CREATE_INPUT_MAX_TOKENS,
  CREATE_LIST_MAX_ITEMS,
  CREATE_MAX_TOKENS,
  CREATE_MIN_SKILL_POPULATION,
  CREATE_NO_ACTION_REASONS,
  CREATE_OUTPUT_SCHEMA,
  CREATE_REFUSAL_CLASSES,
  OVERLAP_REFUSE_THRESHOLD,
  OVERLAP_TOP_K,
  PURPOSE_TEMPLATE_SLOTS,
  checkCreate,
  checkCreatePathSet,
  checkRenderedCreate,
  countDescriptionWords,
  countWords,
  createClusterHash,
  createPathList,
  parseCreateModelText,
  prepareCreate,
  proposalOverlapText,
  rankOverlap,
  readAgentPaths,
  readBudgetCap,
  readGrokBlock,
  renderCreateFiles,
  renderCursorSkillStub,
  renderPurposeMd,
  renderSkillMd,
  shapeProblem,
  type CreateContext,
  type SkillRecord,
} from "@/server/compound-promote-create";
import type { PatternPage } from "@/server/compound-promote-patterns";

const FIX = join(__dirname, "..", "fixtures", "compound-promote-create");
// Two levels above test/server is apps/web-platform; the repo root is four.
const REPO_ROOT = join(__dirname, "..", "..", "..", "..");
const PLUGIN_ROOT = join(REPO_ROOT, "plugins", "soleur");

function fixture(name: string): string {
  // A missing fixture must FAIL the suite, never skip it (harness row a).
  const p = join(FIX, name);
  expect(existsSync(p), `fixture ${name} must exist`).toBe(true);
  return readFileSync(p, "utf8");
}
const fixtureJson = <T>(name: string): T => JSON.parse(fixture(name)) as T;

const SKILLS: SkillRecord[] = fixtureJson<SkillRecord[]>("skills.json");
const PROPOSAL = fixtureJson<Record<string, unknown>>("proposal.json");
const CAL = fixtureJson<{
  evidence: Array<{ id: string; cluster_hash: string; target: string; slug: string; description: string; when_to_use: string[] }>;
  negatives: Array<{ id: string; slug: string; description: string; when_to_use: string[] }>;
}>("calibration.json");

const PATTERN: PatternPage = {
  slug: "synthetic-retry-pattern",
  title: "Synthetic retry pattern",
  summary: "Synthetic summary of a recurring retry mistake.",
  status: "open",
  openedOn: "2026-10-01",
  tags: ["retry"],
  evidence: [
    "knowledge-base/project/learnings/2026-10-01-synthetic-a.md",
    "knowledge-base/project/learnings/2026-10-02-synthetic-b.md",
    "knowledge-base/project/learnings/2026-10-03-synthetic-c.md",
    "knowledge-base/project/learnings/2026-10-04-synthetic-d.md",
    "knowledge-base/project/learnings/2026-10-05-synthetic-e.md",
  ],
  requiredReading: false,
};

function ctx(over: Partial<CreateContext> = {}): CreateContext {
  return {
    patterns: [PATTERN],
    skills: SKILLS,
    skillDirs: SKILLS.map((s) => s.name),
    agentPaths: ["engineering/review/synthetic-reviewer.md"],
    openPrPaths: [],
    budget: { total: 2402, cap: 2436 },
    isHashSuppressed: () => false,
    ...over,
  };
}

// The nearest skill follows the server's own ranking unless a test pins one explicitly, so a gate under test
// (budget, shape, ...) is never accidentally masked by the prefer-patch corroboration.
function proposal(over: Record<string, unknown> = {}): Record<string, unknown> {
  const merged: Record<string, unknown> = { ...structuredClone(PROPOSAL), ...over };
  if (!("nearest_skill" in over)) {
    merged.nearest_skill = rankOverlap(
      proposalOverlapText({
        slug: String(merged.slug),
        description: String(merged.description),
        when_to_use: merged.when_to_use as string[],
      }),
      SKILLS,
    )[0].name;
  }
  return merged;
}

function refusedClass(v: { kind: string }): string {
  return v.kind === "refused" ? (v as unknown as { class: string }).class : v.kind;
}

// ---------------------------------------------------------------------------------------------------------
describe("exported constants (each is read by prompt, check and trailer)", () => {
  it("pins the CTO-ruled values", () => {
    expect(CREATE_DESCRIPTION_MAX_WORDS).toBe(30);
    expect(CREATE_DESCRIPTION_MIN_WORDS).toBe(12);
    expect(CREATE_INPUT_MAX_TOKENS).toBe(12000);
    expect(CREATE_MAX_TOKENS).toBe(3000);
    expect(CREATE_FILE_MAX_LINES).toBe(60);
    expect(CREATE_FILE_MAX_BYTES).toBe(3072);
    expect(CREATE_LIST_MAX_ITEMS).toBe(6);
    expect(OVERLAP_TOP_K).toBe(3);
    expect(CREATE_INPUT_BYTES_PER_TOKEN).toBe(4);
  });

  it("closed vocabularies are exactly the plan's", () => {
    expect([...CREATE_REFUSAL_CLASSES]).toEqual([
      "week-cap", "create-open", "index-empty", "input-size", "model-invalid", "shape", "slug",
      "prefer-patch", "budget", "scan", "readme-sync", "stub-drift", "persist",
    ]);
    expect([...CREATE_NO_ACTION_REASONS]).toEqual(["no-pattern-qualifies", "all-owned", "other"]);
    expect([...CREATE_GATES]).toEqual([
      "schema", "slug-format", "shape", "pii", "ledger", "collision", "prefer-patch", "budget",
    ]);
  });

  it("the purpose slot set equals the template's closed slots", () => {
    expect([...PURPOSE_TEMPLATE_SLOTS].sort()).toEqual(
      ["SKILL_NAME", "ORIGIN", "PATTERNS_ADDRESSED", "NEAREST_SKILL", "PATCH_REJECTION_REASON", "MERGE_RETIRE_CANDIDATES", "EVOLUTION_HISTORY"].sort(),
    );
  });

  it("the output schema is closed and the structured-output root is an object", () => {
    expect(CREATE_OUTPUT_SCHEMA.type).toBe("object");
    expect(CREATE_OUTPUT_SCHEMA.additionalProperties).toBe(false);
    expect(CREATE_OUTPUT_SCHEMA.properties.purpose.additionalProperties).toBe(false);
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("the screens are the handler's own regexes, not re-derived", () => {
  it("PII_REGEX and CREDENTIAL_RE are imported (identity), so a change there moves this gate", async () => {
    const mod = await import("@/server/compound-promote-create");
    expect(mod.CREATE_SCREENS.pii).toBe(PII_REGEX);
    expect(mod.CREATE_SCREENS.credential).toBe(CREDENTIAL_RE);
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("shape allowlist (controls over model text are allowlists)", () => {
  const BAD: Array<[string, string, string]> = [
    ["backtick", "Use the `plan` skill first", "backtick"],
    ["fence", "Run ``` it ```", "backtick"],
    ["tilde fence", "Run ~~~ it ~~~", "markup"],
    ["markdown link", "See [here](./x) for more", "markup"],
    ["url", "Fetch https://example.invalid/x first", "url"],
    ["www", "Open www.example.invalid first", "url"],
    ["id token", "Cite [id: hr-x-y-z] now", "markup"],
    ["html", "Insert <b>bold</b> text", "markup"],
    ["comment", "Add <!-- hidden --> text", "markup"],
    ["template slot", "Insert {{SKILL_NAME}} here", "markup"],
    ["backslash", "Escape with a back\\slash", "markup"],
    ["dollar", "Run $(whoami) now", "markup"],
    ["mention", "Ping the owner at @someone now", "markup"],
    ["hr rule id", "Restate hr-never-do-this exactly", "rule-id"],
    ["wg rule id", "See wg-some-gate for context", "rule-id"],
    ["cq rule id", "See cq-some-rule for context", "rule-id"],
    ["rf rule id", "See rf-some-rule for context", "rule-id"],
    ["pdr rule id", "See pdr-some-rule for context", "rule-id"],
    ["cm rule id", "See cm-some-rule for context", "rule-id"],
    ["scripts path", "Call scripts/run.sh to start", "path-token"],
    ["references path", "Read references/notes.md first", "path-token"],
    ["assets path", "Copy assets/logo.png over", "path-token"],
    ["skills path", "Open skills/plan/SKILL.md next", "path-token"],
    ["soleur token", "Invoke soleur:plan before this", "soleur-token"],
    ["command form", "Then run /ship to finish", "command-form"],
    ["leading bullet", "- already a bullet", "leading-char"],
    ["leading heading", "# A heading", "leading-char"],
    ["non-ascii", "Café handling matters", "non-ascii"],
    ["zero width", "Zero​width joiner here", "non-ascii"],
    ["newline", "Two\nlines here", "non-ascii"],
    ["empty", "   ", "empty"],
  ];
  for (const [label, value, rule] of BAD) {
    it(`refuses ${label} (${rule})`, () => {
      expect(shapeProblem(value, "item")).toBe(rule);
    });
  }

  it("refuses a quote or backslash in the description only for the description kind", () => {
    expect(shapeProblem('This skill should be used when "quoted" text appears here', "description")).toBe("quote");
    expect(shapeProblem('Say "quoted" text here', "item")).toBeNull();
  });

  it("requires the third-person description prefix", () => {
    expect(shapeProblem("Use this skill when something happens in the world today", "description")).toBe("description-prefix");
  });

  for (const word of ["guarantee", "guarantees", "guaranteed", "compliant", "compliance", "certified", "secure", "your workspace"]) {
    it(`refuses the claim word "${word}" case-insensitively and word-bounded`, () => {
      expect(shapeProblem(`This is ${word.toUpperCase()} behaviour here`, "item")).toBe("claim-word");
      expect(shapeProblem(`Mixed ${word[0].toUpperCase()}${word.slice(1)} case here`, "item")).toBe("claim-word");
    });
  }

  it("does not refuse look-alikes that are not the claim words (word-bounded)", () => {
    expect(shapeProblem("Security review of inputs matters", "item")).toBeNull();
    expect(shapeProblem("Insecure defaults are a risk", "item")).toBeNull();
    expect(shapeProblem("A secured pipeline is not claimed", "item")).toBeNull();
  });

  it("enforces the per-kind length caps", () => {
    expect(shapeProblem("a".repeat(161), "item")).toBe("length");
    expect(shapeProblem("a".repeat(160), "item")).toBeNull();
    expect(shapeProblem("a".repeat(301), "field")).toBe("length");
  });

  it("accepts plain valid text", () => {
    expect(shapeProblem("Cap the attempt count and the total wait", "item")).toBeNull();
    expect(shapeProblem(String(PROPOSAL.description), "description")).toBeNull();
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("checkCreate: verdict union and gate order", () => {
  it("a clean proposal creates and records that EVERY gate ran, in order (guard 1 row 2: not zero gates)", () => {
    const v = checkCreate(PROPOSAL, ctx());
    expect(v.kind).toBe("create");
    if (v.kind !== "create") return;
    expect(v.gates).toEqual([...CREATE_GATES]);
    expect(v.clusterHash).toBe(createClusterHash(PATTERN.evidence));
    expect(v.words).toBe(countWords(String(PROPOSAL.description)));
    expect(v.headroom).toBe(34);
    expect(v.overlap.top3).toHaveLength(3);
  });

  it("harness row c: a differently worded valid proposal passes (a gate that rejects everything is detected)", () => {
    const v = checkCreate(
      proposal({
        slug: "csv-import-validation",
        description: "This skill should be used when importing spreadsheet rows needs column type checks, duplicate detection and a rejected-row report.",
        when_to_use: ["A bulk upload contains malformed rows"],
        steps: ["Check column types", "Detect duplicate keys", "Report rejected rows"],
        sharp_edges: ["Never silently drop a row"],
        merge_retire_candidates: [],
      }),
      ctx(),
    );
    expect(v.kind).toBe("create");
  });

  it("no_action is a clean, closed outcome", () => {
    for (const reason of CREATE_NO_ACTION_REASONS) {
      expect(checkCreate({ decision: "no_action", reason_class: reason }, ctx())).toEqual({ kind: "no_action", reason });
    }
  });

  it("model-invalid: unknown reason, extra key, missing key, wrong type, empty sections, non-object, unknown pattern", () => {
    const cases: unknown[] = [
      { decision: "no_action", reason_class: "because-i-said-so" },
      { decision: "no_action", reason_class: "other", extra: 1 },
      proposal({ extra_field: "x" }),
      (() => { const p = proposal(); delete p.steps; return p; })(),
      proposal({ steps: "not an array" }),
      proposal({ when_to_use: [] }),
      proposal({ steps: [] }),
      proposal({ sharp_edges: [] }),
      proposal({ steps: Array.from({ length: CREATE_LIST_MAX_ITEMS + 1 }, (_, i) => `Step number ${i}`) }),
      proposal({ purpose: { origin: "x" } }),
      proposal({ pattern_slug: "no-such-pattern" }),
      null,
      "a string",
      [],
    ];
    for (const raw of cases) expect(refusedClass(checkCreate(raw, ctx())), JSON.stringify(raw)).toBe("model-invalid");
  });

  it("parseCreateModelText: valid JSON passes through, anything else is undefined (never throws)", () => {
    expect(parseCreateModelText('{"decision":"no_action","reason_class":"other"}')).toEqual({ decision: "no_action", reason_class: "other" });
    expect(parseCreateModelText("not json")).toBeUndefined();
    expect(parseCreateModelText("")).toBeUndefined();
  });

  // Guard 1 mutation row 3: a second model string carries a claim word after a clean first item.
  it("guard 1 row 3: a claim word in the LAST item of every list, and in every scalar field, is refused", () => {
    const claim = "This is a guaranteed result";
    const lists = ["when_to_use", "steps", "sharp_edges", "merge_retire_candidates"] as const;
    for (const list of lists) {
      const base = (PROPOSAL[list] as string[]).length > 0 ? (PROPOSAL[list] as string[]) : ["Clean first item"];
      const v = checkCreate(proposal({ [list]: [...base, claim] }), ctx());
      expect(refusedClass(v), `${list}[last]`).toBe("shape");
      if (v.kind === "refused") expect(v.detail).toBe(`${list}[${base.length}]:claim-word`);
    }
    for (const field of ["patch_rejection_reason"] as const) {
      expect(refusedClass(checkCreate(proposal({ [field]: claim }), ctx()))).toBe("shape");
    }
    expect(refusedClass(checkCreate(proposal({ purpose: { origin: claim, patterns_addressed: "Clean text" } }), ctx()))).toBe("shape");
    expect(refusedClass(checkCreate(proposal({ purpose: { origin: "Clean text", patterns_addressed: claim } }), ctx()))).toBe("shape");
    expect(
      refusedClass(
        checkCreate(proposal({ description: "This skill should be used when outbound calls need a guaranteed retry policy with jitter and caps" }), ctx()),
      ),
    ).toBe("shape");
  });

  it("refusal details are closed tokens and never echo model text", () => {
    const secret = "UNIQUE-MODEL-TEXT-" + "z".repeat(10);
    const v = checkCreate(proposal({ steps: [`Step with a backtick \`${secret}\``] }), ctx());
    expect(v.kind).toBe("refused");
    if (v.kind !== "refused") return;
    expect(v.detail).not.toContain(secret);
    expect(v.detail).toMatch(/^[a-z_]+(\[\d+\])?:[a-z-]+$/);
  });

  it("PII and credential shapes in ANY string are refused (shape class), built by concatenation", () => {
    const ip = ["10", "20", "30", "40"].join(".");
    const gh = "ghp" + "_" + "A".repeat(24);
    const aws = "AKIA" + "B".repeat(16);
    const sk = "sk-ant-" + "c".repeat(24);
    for (const bad of [`Contact the host at ${ip} directly`, `The value ${gh} was pasted`, `The key ${aws} leaked`, `The token ${sk} leaked`]) {
      const v = checkCreate(proposal({ sharp_edges: ["Clean first item", bad] }), ctx());
      expect(v.kind, bad).toBe("refused");
      if (v.kind === "refused") {
        expect(v.class).toBe("shape");
        expect(v.detail).toMatch(/^sharp_edges\[1\]:(pii|credential)$/);
      }
    }
    // The same text in the purpose block.
    expect(refusedClass(checkCreate(proposal({ purpose: { origin: `Seen on ${ip}`, patterns_addressed: "Clean text" } }), ctx()))).toBe("shape");
  });

  it("guard 1 row 2: an empty collection of model strings cannot pass (the gate refuses, it does not vacuously accept)", () => {
    const v = checkCreate(
      { ...PROPOSAL, when_to_use: [], steps: [], sharp_edges: [] },
      ctx(),
    );
    expect(v.kind).toBe("refused");
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("slug validation and collision", () => {
  it("rejects malformed slugs (class slug)", () => {
    for (const slug of ["Ab", "ab", "-abc", "abc-", "a--b", "has space", "../etc", "a/b", "UPPER", "1start", "x".repeat(42), "slug_underscore"]) {
      expect(refusedClass(checkCreate(proposal({ slug }), ctx())), slug).toBe("slug");
    }
  });

  it("rejects a slug that collides with a skill dir, an agent leaf, a cursor name, a command stem or an open PR path", () => {
    expect(refusedClass(checkCreate(proposal({ slug: "kb-search" }), ctx()))).toBe("slug");
    // A skills directory that carries no SKILL.md still collides.
    expect(refusedClass(checkCreate(proposal({ slug: "flag-bootstrap" }), ctx({ skillDirs: [...SKILLS.map((s) => s.name), "flag-bootstrap"] })))).toBe("slug");
    expect(refusedClass(checkCreate(proposal({ slug: "synthetic-reviewer" }), ctx()))).toBe("slug");
    expect(refusedClass(checkCreate(proposal({ slug: "engineering-review-synthetic-reviewer" }), ctx()))).toBe("slug");
    for (const reserved of ["sync", "help", "version"]) {
      expect(refusedClass(checkCreate(proposal({ slug: reserved }), ctx())), reserved).toBe("slug");
    }
    expect(
      refusedClass(checkCreate(proposal(), ctx({ openPrPaths: ["plugins/soleur/skills/http-retry-backoff/SKILL.md"] }))),
    ).toBe("slug");
    expect(
      refusedClass(checkCreate(proposal(), ctx({ openPrPaths: ["plugins/soleur/cursor/skills/soleur-http-retry-backoff/SKILL.md"] }))),
    ).toBe("slug");
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("ledger: an already-proposed pattern hash is suppressed for create too", () => {
  it("returns suppressed with the hash and runs no later gate", () => {
    const seen: string[] = [];
    const v = checkCreate(
      proposal({ slug: "kb-search" }), // would otherwise be a slug refusal: ledger comes first
      ctx({ isHashSuppressed: (h) => { seen.push(h); return true; } }),
    );
    expect(v).toEqual({ kind: "suppressed", clusterHash: createClusterHash(PATTERN.evidence) });
    expect(seen).toEqual([createClusterHash(PATTERN.evidence)]);
  });

  it("hashes the SORTED evidence keys exactly as the handler's computeClusterHash does", () => {
    const sorted = [...PATTERN.evidence].sort().join("\n") + "\n";
    expect(createClusterHash(PATTERN.evidence)).toBe(createHash("sha256").update(sorted).digest("hex"));
    expect(createClusterHash([...PATTERN.evidence].reverse())).toBe(createClusterHash(PATTERN.evidence));
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("prefer-patch: overlap ranking and the calibrated threshold", () => {
  const score = (p: { slug: string; description: string; when_to_use: string[] }) =>
    rankOverlap(proposalOverlapText(p), SKILLS);

  it("calibration record (numbers printed so the PR can cite them)", () => {
    const rows = [
      ...CAL.evidence.map((e) => ({ id: e.id, kind: "evidence", expect: e.target, ranked: score(e) })),
      ...CAL.negatives.map((n) => ({ id: n.id, kind: "negative", expect: "-", ranked: score(n) })),
    ];
    const lines = rows.map((r) => `${r.kind} ${r.id} top1=${r.ranked[0].name}:${r.ranked[0].score.toFixed(4)} top2=${r.ranked[1].name}:${r.ranked[1].score.toFixed(4)}`);
    console.info(`OVERLAP calibration threshold=${OVERLAP_REFUSE_THRESHOLD}\n${lines.join("\n")}`);
    expect(rows).toHaveLength(6);
  });

  it("both evidence fixtures (git-worktree, pencil-setup) rank their target first and refuse with margin", () => {
    for (const e of CAL.evidence) {
      const ranked = score(e);
      expect(ranked[0].name, e.id).toBe(e.target);
      expect(ranked[0].score, e.id).toBeGreaterThanOrEqual(OVERLAP_REFUSE_THRESHOLD + 0.04);
      const v = checkCreate(
        proposal({ slug: e.slug, description: e.description, when_to_use: e.when_to_use, nearest_skill: e.target }),
        ctx(),
      );
      expect(v.kind, e.id).toBe("refused");
      if (v.kind === "refused") {
        expect(v.class).toBe("prefer-patch");
        expect(v.detail).toBe("overlap");
      }
    }
  });

  it("at least four synthetic negatives (no owner) pass the overlap gate with margin", () => {
    expect(CAL.negatives.length).toBeGreaterThanOrEqual(4);
    for (const n of CAL.negatives) {
      const top1 = score(n)[0].score;
      expect(top1, n.id).toBeLessThanOrEqual(OVERLAP_REFUSE_THRESHOLD - 0.04);
      const v = checkCreate(
        proposal({ slug: n.slug, description: n.description, when_to_use: n.when_to_use, nearest_skill: score(n)[0].name }),
        ctx(),
      );
      expect(v.kind, n.id).toBe("create");
    }
  });

  it("the nearest skill must exist and be in the server's top-3", () => {
    const missing = checkCreate(proposal({ nearest_skill: "no-such-skill" }), ctx());
    expect(missing.kind).toBe("refused");
    if (missing.kind === "refused") expect([missing.class, missing.detail]).toEqual(["prefer-patch", "nearest-missing"]);
    const e = CAL.negatives[0];
    const ranked = score(e);
    const farOne = ranked[ranked.length - 1].name; // the least-overlapping skill is not in the top 3
    const far = checkCreate(proposal({ slug: e.slug, description: e.description, when_to_use: e.when_to_use, nearest_skill: farOne }), ctx());
    expect(far.kind).toBe("refused");
    if (far.kind === "refused") expect([far.class, far.detail]).toEqual(["prefer-patch", "nearest-not-top3"]);
  });

  it("an open PR already touching the nearest skill refuses (a patch is in flight)", () => {
    const e = CAL.negatives[0];
    const nearest = score(e)[0].name;
    const v = checkCreate(
      proposal({ slug: e.slug, description: e.description, when_to_use: e.when_to_use, nearest_skill: nearest }),
      ctx({ openPrPaths: [`plugins/soleur/skills/${nearest}/SKILL.md`] }),
    );
    expect(v.kind).toBe("refused");
    if (v.kind === "refused") expect([v.class, v.detail]).toEqual(["prefer-patch", "open-pr-nearest"]);
  });

  it("an empty skill list fails closed", () => {
    expect(refusedClass(checkCreate(PROPOSAL, ctx({ skills: [], skillDirs: [] })))).toBe("prefer-patch");
  });

  it("ranking is deterministic, bounded and ties break by name", () => {
    const a = rankOverlap("alpha beta", [
      { name: "b-skill", description: "alpha beta", disableModelInvocation: false },
      { name: "a-skill", description: "alpha beta", disableModelInvocation: false },
    ]);
    expect(a.map((r) => r.name)).toEqual(["a-skill", "b-skill"]);
    for (const r of rankOverlap(proposalOverlapText(CAL.evidence[0]), SKILLS)) {
      expect(r.score).toBeGreaterThanOrEqual(0);
      expect(r.score).toBeLessThanOrEqual(1);
    }
    expect(rankOverlap("", SKILLS)[0].score).toBe(0);
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("budget gate (guard 2): cap - total, on a FIXTURE budget", () => {
  const words = (n: number) => `This skill should be used when ${Array.from({ length: n - 6 }, (_, i) => `word${String.fromCharCode(97 + (i % 26))}`).join(" ")}`;

  it("accepts a description of exactly cap - total words and refuses cap - total + 1", () => {
    // Use a clean negative as the carrier so the overlap gate passes, then rewrite its description length.
    const run = (n: number, headroom: number) =>
      checkCreate(proposal({ description: words(n) }), ctx({ budget: { total: 2436 - headroom, cap: 2436 } }));
    expect(run(15, 15).kind).toBe("create");
    const over = run(16, 15);
    expect(over.kind).toBe("refused");
    if (over.kind === "refused") {
      expect([over.class, over.detail]).toEqual(["budget", "over-headroom"]);
      expect(over.numbers).toEqual({ words: 16, total: 2421, cap: 2436, headroom: 15 });
    }
  });

  it("refuses 31 words and fewer than the minimum, whatever the headroom", () => {
    for (const n of [CREATE_DESCRIPTION_MAX_WORDS + 1, CREATE_DESCRIPTION_MIN_WORDS - 1]) {
      const v = checkCreate(proposal({ description: words(n) }), ctx({ budget: { total: 0, cap: 5000 } }));
      expect(v.kind, String(n)).toBe("refused");
      if (v.kind === "refused") expect([v.class, v.detail]).toEqual(["budget", "words-out-of-range"]);
    }
    expect(checkCreate(proposal({ description: words(CREATE_DESCRIPTION_MAX_WORDS) }), ctx({ budget: { total: 0, cap: 5000 } })).kind).toBe("create");
    expect(checkCreate(proposal({ description: words(CREATE_DESCRIPTION_MIN_WORDS) }), ctx({ budget: { total: 0, cap: 5000 } })).kind).toBe("create");
  });

  it("an unreadable cap or total refuses (fail closed), and a total above the cap has no headroom", () => {
    const v = checkCreate(PROPOSAL, ctx({ budget: null }));
    expect(v.kind).toBe("refused");
    if (v.kind === "refused") expect([v.class, v.detail]).toEqual(["budget", "unreadable"]);
    expect(refusedClass(checkCreate(PROPOSAL, ctx({ budget: { total: 2500, cap: 2436 } })))).toBe("budget");
    expect(refusedClass(checkCreate(PROPOSAL, ctx({ budget: { total: Number.NaN, cap: 2436 } })))).toBe("budget");
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("word counter and cap reader (guard 2 rows 1-5) on fixture trees", () => {
  let tree: string;
  const write = (root: string, name: string, body: string) => {
    const p = join(root, "skills", name, "SKILL.md");
    mkdirSync(dirname(p), { recursive: true });
    writeFileSync(p, body);
  };
  const skill = (name: string, desc: string, extra = "") => `---\nname: ${name}\ndescription: ${desc}\n${extra}---\n\nBody\n`;

  beforeAll(() => {
    tree = mkdtempSync(join(tmpdir(), "cp-create-tree-"));
  });
  afterAll(() => rmSync(tree, { recursive: true, force: true }));

  it("counts model-visible descriptions only (row 1: user-invoked skills are excluded)", () => {
    const root = mkdtempSync(join(tmpdir(), "cp-create-t1-"));
    write(root, "alpha", skill("alpha", '"one two three"'));
    write(root, "beta", skill("beta", '"four five"', "disable-model-invocation: true\n"));
    const r = countDescriptionWords(root, { minSkills: 1 });
    expect(r.ok).toBe(true);
    if (r.ok) expect([r.total, r.skills, r.disabled]).toEqual([3, 2, 1]);
    rmSync(root, { recursive: true, force: true });
  });

  it("row 2: a tree with zero skills is a refusal, not a clean 0", () => {
    const root = mkdtempSync(join(tmpdir(), "cp-create-t2-"));
    mkdirSync(join(root, "skills"), { recursive: true });
    const r = countDescriptionWords(root, { minSkills: 1 });
    expect(r.ok).toBe(false);
    const floor = countDescriptionWords(root);
    expect(floor.ok).toBe(false);
    expect(CREATE_MIN_SKILL_POPULATION).toBeGreaterThanOrEqual(50);
    rmSync(root, { recursive: true, force: true });
  });

  it("row 3: a malformed second skill after a compliant first refuses (fail closed), as do a missing frontmatter and a non-string description", () => {
    for (const [label, bad] of [
      ["unterminated yaml", "---\nname: bad\ndescription: \"unterminated\n---\n\nBody\n"],
      ["no frontmatter", "Body only\n"],
      ["description is a list", "---\nname: bad\ndescription:\n  - a\n  - b\n---\n\nBody\n"],
      ["description missing", "---\nname: bad\n---\n\nBody\n"],
    ] as const) {
      const root = mkdtempSync(join(tmpdir(), "cp-create-t3-"));
      write(root, "good", skill("good", '"one two"'));
      write(root, "zbad", bad);
      const r = countDescriptionWords(root, { minSkills: 1 });
      expect(r.ok, label).toBe(false);
      rmSync(root, { recursive: true, force: true });
    }
  });

  it("row 4: whitespace is split on /\\s+/ (double space and newline inside a block scalar are one separator)", () => {
    const root = mkdtempSync(join(tmpdir(), "cp-create-t4-"));
    write(root, "alpha", "---\nname: alpha\ndescription: >-\n  one  two\n  three\n---\n\nBody\n");
    const r = countDescriptionWords(root, { minSkills: 1 });
    expect(r.ok && r.total).toBe(3);
    // And the split(" ") mutation would not agree:
    expect("one  two three".split(" ").filter(Boolean).length).toBe(3);
    expect("one\ttwo\nthree".split(" ").filter(Boolean).length).not.toBe(countWords("one\ttwo\nthree"));
    rmSync(root, { recursive: true, force: true });
  });

  it("lists every skills directory (also one without SKILL.md) and returns the records for the overlap ranking", () => {
    const root = mkdtempSync(join(tmpdir(), "cp-create-t5-"));
    write(root, "alpha", skill("alpha", '"one two"'));
    mkdirSync(join(root, "skills", "no-skill-md"), { recursive: true });
    const r = countDescriptionWords(root, { minSkills: 1 });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.dirs).toEqual(["alpha", "no-skill-md"]);
      expect(r.records).toEqual([{ name: "alpha", description: "one two", disableModelInvocation: false }]);
    }
    rmSync(root, { recursive: true, force: true });
  });

  it("row 5: the cap is the constant assignment, never a digit run in the history comment", () => {
    const src = `// header 99999\nconst SKILL_DESCRIPTION_WORD_BUDGET = 2436; // lowered -7 for #10550 (2443 -> 2436). // bumped +30 for #10404 (2413)\nconst OTHER = 5;\n`;
    expect(readBudgetCap(src)).toBe(2436);
    expect(readBudgetCap("const SKILL_DESCRIPTION_WORD_BUDGET = abc;")).toBeNull();
    expect(readBudgetCap("// no constant here 2443")).toBeNull();
    expect(readBudgetCap("")).toBeNull();
    // Two assignments are ambiguous and fail closed; so does a commented-out second.
    expect(readBudgetCap("const SKILL_DESCRIPTION_WORD_BUDGET = 1;\nconst SKILL_DESCRIPTION_WORD_BUDGET = 2;")).toBeNull();
    expect(readBudgetCap("const SKILL_DESCRIPTION_WORD_BUDGET = 0;")).toBeNull();
  });

  it("reads agent paths recursively and ignores non-markdown files", () => {
    const root = mkdtempSync(join(tmpdir(), "cp-create-t6-"));
    mkdirSync(join(root, "agents", "a", "b"), { recursive: true });
    writeFileSync(join(root, "agents", "a", "b", "x.md"), "x");
    writeFileSync(join(root, "agents", "a", "notes.txt"), "x");
    expect(readAgentPaths(root)).toEqual(["a/b/x.md"]);
    expect(readAgentPaths(join(root, "nope"))).toEqual([]);
    rmSync(root, { recursive: true, force: true });
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("prepareCreate: input ceiling (refuse, never truncate) and the prompt", () => {
  const nonce = "0123456789abcdef";

  it("empty pattern index refuses index-empty", () => {
    const v = prepareCreate({ patterns: [], skills: SKILLS, nonce });
    expect(v).toMatchObject({ kind: "refused", class: "index-empty" });
  });

  it("lists model-visible skills only, fences untrusted data, and states every limit from the exported constants", () => {
    const v = prepareCreate({ patterns: [PATTERN], skills: SKILLS, nonce });
    expect(v.kind).toBe("ready");
    if (v.kind !== "ready") return;
    expect(v.prompt).toContain(`<<<BEGIN-${nonce}:skill-list>>>`);
    expect(v.prompt).toContain(`<<<BEGIN-${nonce}:pattern-index>>>`);
    expect(v.prompt).toContain("- git-worktree: ");
    expect(v.prompt).not.toContain("- go: "); // disable-model-invocation: not model-visible
    for (const n of [CREATE_DESCRIPTION_MAX_WORDS, CREATE_DESCRIPTION_MIN_WORDS, CREATE_LIST_MAX_ITEMS, CREATE_FILE_MAX_LINES, CREATE_FILE_MAX_BYTES]) {
      expect(v.prompt).toContain(String(n));
    }
    expect(v.prompt).toContain(OVERLAP_REFUSE_THRESHOLD.toFixed(2));
    for (const r of CREATE_NO_ACTION_REASONS) expect(v.prompt).toContain(r);
    expect(v.maxTokens).toBe(CREATE_MAX_TOKENS);
    expect(v.inputBytes).toBeGreaterThan(0);
    expect(v.inputTokensBound).toBe(Math.ceil(v.inputBytes / CREATE_INPUT_BYTES_PER_TOKEN));
  });

  it("refuses over the ceiling with numbers, and does not truncate", () => {
    const big: SkillRecord[] = Array.from({ length: 600 }, (_, i) => ({
      name: `skill-${i}`,
      description: "This skill should be used when " + "padding words ".repeat(20),
      disableModelInvocation: false,
    }));
    const v = prepareCreate({ patterns: [PATTERN], skills: big, nonce });
    expect(v.kind).toBe("refused");
    if (v.kind === "refused") {
      expect(v.class).toBe("input-size");
      expect(v.numbers?.max).toBe(CREATE_INPUT_MAX_TOKENS);
      expect(v.numbers?.tokens).toBeGreaterThan(CREATE_INPUT_MAX_TOKENS);
    }
  });

  it("exactly at the ceiling is accepted, one byte-token over is refused (boundary)", () => {
    // Find a skill-list size straddling the ceiling using the same measure the gate uses.
    const mk = (n: number): SkillRecord[] =>
      Array.from({ length: n }, (_, i) => ({ name: `s${i}`, description: "This skill should be used when x y z", disableModelInvocation: false }));
    let lo = 1;
    let hi = 5000;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      const r = prepareCreate({ patterns: [PATTERN], skills: mk(mid), nonce });
      if (r.kind === "ready") lo = mid;
      else hi = mid - 1;
    }
    const at = prepareCreate({ patterns: [PATTERN], skills: mk(lo), nonce });
    const over = prepareCreate({ patterns: [PATTERN], skills: mk(lo + 1), nonce });
    expect(at.kind).toBe("ready");
    expect(over.kind).toBe("refused");
    if (at.kind === "ready") expect(at.inputTokensBound).toBeLessThanOrEqual(CREATE_INPUT_MAX_TOKENS);
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("renderers: the server writes every byte", () => {
  const grok = readGrokBlock(readFileSync(join(PLUGIN_ROOT, "skills/plan/SKILL.md"), "utf8"));
  const template = readFileSync(join(PLUGIN_ROOT, "skills/skill-creator/templates/purpose.md"), "utf8");
  const parsed = () => {
    const v = checkCreate(PROPOSAL, ctx());
    if (v.kind !== "create") throw new Error("fixture proposal must create");
    return v.proposal;
  };
  const DATE = "2026-10-26";

  it("renders SKILL.md byte-for-byte equal to the golden (Grok block substituted from the canonical source)", () => {
    const golden = fixture("golden-SKILL.md").replace("@@GROK_BLOCK@@", grok.replace(/\n$/, ""));
    expect(renderSkillMd(parsed(), grok)).toBe(golden);
  });

  it("renders PURPOSE.md from the template byte-for-byte equal to the golden", () => {
    expect(renderPurposeMd(template, parsed(), { date: DATE })).toBe(fixture("golden-PURPOSE.md"));
  });

  it("renders the Cursor stub byte-for-byte equal to the golden", () => {
    const p = parsed();
    expect(renderCursorSkillStub({ folder: p.slug, description: p.description, disableModel: false })).toBe(fixture("golden-stub.md"));
  });

  it("the rendered SKILL.md has exactly name+description frontmatter, the three fixed headings, and ONE ./PURPOSE.md link", () => {
    const out = renderSkillMd(parsed(), grok);
    const fm = /^---\n([\s\S]*?)\n---\n/.exec(out)![1];
    expect(fm.split("\n").map((l) => l.split(":")[0])).toEqual(["name", "description"]);
    expect(out.match(/^## .*$/gm)).toEqual(["## When to use", "## Steps", "## Sharp edges"]);
    expect(out.match(/\]\(/g)).toHaveLength(1);
    expect(out.match(/\]\(\.\/PURPOSE\.md\)/g)).toHaveLength(1);
    expect(out.match(/<!-- grok-harness-invoke:start -->/g)).toHaveLength(1);
    // The Grok block sits before the first H1, outside the frontmatter.
    expect(out.indexOf("<!-- grok-harness-invoke:start -->")).toBeLessThan(out.indexOf("\n# "));
    expect(out.endsWith("\n")).toBe(true);
    expect(out.endsWith("\n\n")).toBe(false);
  });

  it("the rendered PURPOSE.md has NO markdown link (the single link lives in SKILL.md), the six headings and the fixed attribution", () => {
    const out = renderPurposeMd(template, parsed(), { date: DATE });
    expect(out).not.toMatch(/\]\(/);
    expect(out.match(/^## .*$/gm)).toEqual([
      "## Origin", "## Patterns addressed", "## Nearest existing skill and why not patched",
      "## Merge and retire candidates", "## Evolution history", "## Attribution",
    ]);
    expect(out).toContain("arXiv:2608.27454");
    expect(out).toContain("no endorsement by the authors or Google Research is implied");
    expect(out).not.toMatch(/\{\{|\}\}/);
  });

  it("an empty merge_retire_candidates renders a fixed 'None identified' bullet, not a blank section", () => {
    const p = { ...parsed(), merge_retire_candidates: [] };
    expect(renderPurposeMd(template, p, { date: DATE })).toContain("- None identified.");
  });

  it("the renderer reads the template as its single source: a changed slot set or a bad date is refused", () => {
    expect(() => renderPurposeMd(template.replace("{{EVOLUTION_HISTORY}}", "{{EVOLUTION_HISTORY}}\n\n{{EXTRA}}"), parsed(), { date: DATE })).toThrow(/slot/);
    expect(() => renderPurposeMd(template.replace("{{ORIGIN}}", ""), parsed(), { date: DATE })).toThrow(/slot/);
    expect(() => renderPurposeMd(template, parsed(), { date: "yesterday" })).toThrow(/date/);
  });

  it("model text containing a slot-looking token is never re-expanded (single pass), and is refused upstream anyway", () => {
    const p = { ...parsed(), purpose: { origin: "{{SKILL_NAME}}", patterns_addressed: "x" } };
    const out = renderPurposeMd(template, p, { date: DATE });
    expect(out).toContain("## Origin\n\n{{SKILL_NAME}}\n");
    expect(refusedClass(checkCreate(proposal({ purpose: { origin: "{{SKILL_NAME}}", patterns_addressed: "x" } }), ctx()))).toBe("shape");
  });

  it("readGrokBlock fails closed on a missing, reversed or duplicated block", () => {
    expect(() => readGrokBlock("no block here")).toThrow(/grok/i);
    expect(() => readGrokBlock("<!-- grok-harness-invoke:end -->\n<!-- grok-harness-invoke:start -->\n")).toThrow(/grok/i);
    expect(grok.startsWith("<!-- grok-harness-invoke:start -->\n")).toBe(true);
    expect(grok.endsWith("<!-- grok-harness-invoke:end -->\n")).toBe(true);
  });

  it("renderCreateFiles renders all three files and runs the rendered-output gate", () => {
    const r = renderCreateFiles({ proposal: parsed(), grokBlock: grok, purposeTemplate: template, date: DATE });
    expect(r.kind).toBe("rendered");
    if (r.kind === "rendered") {
      expect(r.files.skillMd.length).toBeLessThanOrEqual(CREATE_FILE_MAX_BYTES);
      expect(r.files.purposeMd.length).toBeLessThanOrEqual(CREATE_FILE_MAX_BYTES);
    }
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("checkRenderedCreate (guard 1 rows 5 and 2; PII/credential over the RENDERED bytes)", () => {
  const grok = readGrokBlock(readFileSync(join(PLUGIN_ROOT, "skills/plan/SKILL.md"), "utf8"));
  const template = readFileSync(join(PLUGIN_ROOT, "skills/skill-creator/templates/purpose.md"), "utf8");
  const v = checkCreate(PROPOSAL, ctx());
  if (v.kind !== "create") throw new Error("fixture proposal must create");
  const p = v.proposal;
  const good = () => ({
    skillMd: renderSkillMd(p, grok),
    purposeMd: renderPurposeMd(template, p, { date: "2026-10-26" }),
    stub: renderCursorSkillStub({ folder: p.slug, description: p.description, disableModel: false }),
  });
  const check = (files: ReturnType<typeof good>) => checkRenderedCreate(files, p, grok);

  it("accepts the clean render", () => {
    expect(check(good())).toEqual({ kind: "ok", filesChecked: 3 });
  });

  it("row 5: a fenced block rendered into PURPOSE.md after a clean SKILL.md is refused", () => {
    const f = good();
    const mutated = { ...f, purposeMd: f.purposeMd.replace("## Origin\n", "## Origin\n\n```sh\nrm -rf /\n```\n") };
    expect(mutated.purposeMd).not.toBe(f.purposeMd); // self-check: the mutation changed something
    expect(check(mutated)).toMatchObject({ kind: "refused", class: "shape" });
  });

  it("a backtick or fence in SKILL.md outside the fixed Grok block is refused; inside the block is fine", () => {
    const f = good();
    expect(check({ ...f, skillMd: f.skillMd.replace("## Steps\n", "## Steps\n\n```\nx\n```\n") })).toMatchObject({ kind: "refused" });
    expect(f.skillMd).toContain("`"); // the Grok block itself carries backticks and passes
  });

  it("a second link, a link in PURPOSE.md, a missing link or a duplicated Grok block are refused", () => {
    const f = good();
    expect(check({ ...f, skillMd: f.skillMd + "\nSee [other](./x.md)\n" })).toMatchObject({ kind: "refused" });
    expect(check({ ...f, skillMd: f.skillMd.replace("[PURPOSE.md](./PURPOSE.md)", "PURPOSE.md") })).toMatchObject({ kind: "refused" });
    expect(check({ ...f, purposeMd: f.purposeMd + "\n[x](./y)\n" })).toMatchObject({ kind: "refused" });
    expect(check({ ...f, skillMd: f.skillMd.replace("# Http Retry Backoff", grok + "\n# Http Retry Backoff") })).toMatchObject({ kind: "refused" });
  });

  it("frontmatter with an extra key or a wrong name or description is refused", () => {
    const f = good();
    expect(check({ ...f, skillMd: f.skillMd.replace("---\n\n", "model: sonnet\n---\n\n") })).toMatchObject({ kind: "refused" });
    expect(check({ ...f, skillMd: f.skillMd.replace("name: http-retry-backoff", "name: other-name") })).toMatchObject({ kind: "refused" });
    expect(check({ ...f, skillMd: f.skillMd.replace("exponential delay", "exponential waits") })).toMatchObject({ kind: "refused" });
  });

  it("PII and credential shapes in the RENDERED bytes are refused even if the model fields were clean", () => {
    const f = good();
    const gh = "ghp" + "_" + "Z".repeat(24);
    expect(check({ ...f, purposeMd: f.purposeMd + `\n${gh}\n` })).toMatchObject({ kind: "refused", class: "shape" });
    expect(check({ ...f, skillMd: f.skillMd + "\nhost 10.1.2.3\n" })).toMatchObject({ kind: "refused", class: "shape" });
  });

  it("size caps: more than 60 lines or 3 KB in either file is refused; the stub is exempt", () => {
    const f = good();
    expect(check({ ...f, skillMd: f.skillMd + "x\n".repeat(CREATE_FILE_MAX_LINES) })).toMatchObject({ kind: "refused", detail: "size:skill" });
    expect(check({ ...f, purposeMd: f.purposeMd + "y".repeat(CREATE_FILE_MAX_BYTES) })).toMatchObject({ kind: "refused", detail: "size:purpose" });
  });

  it("an empty rendered file is refused (guard 1 row 2: empty input must not be 'clean')", () => {
    const f = good();
    expect(check({ ...f, skillMd: "" })).toMatchObject({ kind: "refused" });
    expect(check({ ...f, purposeMd: "" })).toMatchObject({ kind: "refused" });
    expect(check({ ...f, stub: "" })).toMatchObject({ kind: "refused" });
  });

  it("a stub that is not what the renderer produces for this skill is refused (stub-drift)", () => {
    const f = good();
    expect(check({ ...f, stub: f.stub.replace("soleur-http-retry-backoff", "soleur-other") })).toMatchObject({ kind: "refused", class: "stub-drift" });
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("path set (guard 1 row 4): exactly six paths, status A only", () => {
  const slug = "http-retry-backoff";
  it("lists the six paths in the fixed order", () => {
    expect(createPathList(slug)).toEqual([
      "plugins/soleur/skills/http-retry-backoff/SKILL.md",
      "plugins/soleur/skills/http-retry-backoff/PURPOSE.md",
      "plugins/soleur/cursor/skills/soleur-http-retry-backoff/SKILL.md",
      "README.md",
      "plugins/soleur/README.md",
      "knowledge-base/project/learnings/promotion-log.md",
    ]);
  });

  it("refuses a seventh path, a scripts file, a missing path, a duplicate and an off-slug path", () => {
    const six = createPathList(slug);
    expect(checkCreatePathSet(slug, six)).toEqual({ ok: true });
    expect(checkCreatePathSet(slug, [...six].reverse())).toEqual({ ok: true }); // order-insensitive set equality
    for (const mutated of [
      [...six, "plugins/soleur/skills/http-retry-backoff/scripts/run.sh"],
      [...six, "extra.md"],
      six.slice(1),
      [...six.slice(1), six[1]],
      [...six.slice(1), "plugins/soleur/skills/other/SKILL.md"],
    ]) {
      expect(checkCreatePathSet(slug, mutated).ok).toBe(false);
    }
  });

  it("refuses a traversal slug when deriving paths", () => {
    expect(() => createPathList("../escape")).toThrow(/slug/);
    expect(() => createPathList("a/b")).toThrow(/slug/);
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("Cursor stub renderer (guard 4 helpers; the every-skill parity lives in the parity suite)", () => {
  it("mirrors the generator special cases: bare go/sync, command targets, model-disabled folders", () => {
    expect(renderCursorSkillStub({ folder: "go", description: "d", disableModel: false })).toContain("name: go\n");
    expect(renderCursorSkillStub({ folder: "go", description: "d", disableModel: false })).toContain("`commands/go.md`");
    expect(renderCursorSkillStub({ folder: "plan", description: "d", disableModel: false })).toContain("disable-model-invocation: true");
    expect(renderCursorSkillStub({ folder: "invoice", description: null, disableModel: false })).not.toContain("description:");
  });

  it("quotes the description as a YAML scalar (a colon and a quote stay inside)", () => {
    const out = renderCursorSkillStub({ folder: "x-y", description: 'a: b "c" \\ d', disableModel: false });
    expect(out).toContain('description: "a: b \\"c\\" \\\\ d"');
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("harness self-checks (the instrument can fail)", () => {
  it("row (b): every mutation helper used above changes its input", () => {
    const mutated = proposal({ steps: ["A `tick` here"] });
    expect(JSON.stringify(mutated)).not.toBe(JSON.stringify(PROPOSAL));
    expect(refusedClass(checkCreate(mutated, ctx()))).toBe("shape");
    expect(refusedClass(checkCreate(PROPOSAL, ctx()))).toBe("create");
  });

  it("row (a): a missing golden fixture fails (not skips)", () => {
    expect(() => fixture("golden-does-not-exist.md")).toThrow();
  });

  it("an empty ranking input cannot yield a passing top-1", () => {
    expect(rankOverlap("anything", [])).toEqual([]);
  });
});
