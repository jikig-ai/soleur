// WikiSkill Phase 2 (#10550) -- parity of the create arm's server-side duplicates with the REAL tree.
//
// The create arm duplicates three things the repo's own tooling owns: the Cursor stub generator (bun-shaped,
// does not run in the runner image -- Phase 0, CTO G3), the Grok invoke block (single source plan/SKILL.md) and the
// description-budget counter (bun test components.test.ts). A duplicate that is not pinned drifts silently, so each
// is compared here against the thing it duplicates, over the real tree.
//
// PROPERTY (Guards 2 and 4): the server's description-word count equals the count components.test.ts computes; the
// rendered Cursor stub equals the generator's output and the rendered Grok block equals the pinned canonical, for
// every skill and for a new one.
//
// ASSEMBLY: the chokepoints are `countDescriptionWords`, `readBudgetCap`, `renderCursorSkillStub` and `readGrokBlock`.
// The per-skill loop below is the population; each loop asserts its own non-zero floor so "zero folders compared" is
// RED, not green.
//
// ANCHOR: `cursor-name-map --check`, `grok-harness-invoke.test.ts` and `components.test.ts` run in CI independently
// of this suite; this file only proves the duplicates agree with them.
//
// This suite reads the repository (plugins/, knowledge-base/), so it is registered in REPO_WIDE_SUITES.
import { describe, expect, it, vi } from "vitest";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: vi.fn(),
}));

import { parse as parseYaml } from "yaml";
import { MIN_TRACKED_SKILLS } from "../../../../plugins/soleur/test/lib/population-floors";
import {
  CREATE_DESCRIPTION_MAX_WORDS,
  CREATE_DESCRIPTION_MIN_WORDS,
  CREATE_INPUT_BYTES_PER_TOKEN,
  CREATE_INPUT_MAX_TOKENS,
  CREATE_PR_BODY_LINE,
  CREATE_STAGE_ORDER,
  OVERLAP_REFUSE_THRESHOLD,
  checkCreate,
  countDescriptionWords,
  createPathList,
  prepareCreate,
  proposalOverlapText,
  rankOverlap,
  readBudgetCap,
  readGrokBlock,
  renderCreateFiles,
  renderCursorSkillStub,
  type CreateContext,
  type SkillRecord,
} from "@/server/compound-promote-create";

const FIX = join(__dirname, "..", "fixtures", "compound-promote-create");
const REPO_ROOT = join(__dirname, "..", "..", "..", "..");
const PLUGIN_ROOT = join(REPO_ROOT, "plugins", "soleur");

// The generator is bun-shaped (`import.meta.dir`), which this app's tsc does not type, so it is loaded by path at
// runtime and typed structurally here. Vite resolves its bare `yaml` import through the vitest project root (Phase 0).
type Generator = { buildCursorNameMap(pluginRoot: string): { files: Map<string, string>; problems: string[] } };
const GENERATOR_PATH = join(PLUGIN_ROOT, "scripts", "sync-cursor-name-map.ts");
const { buildCursorNameMap } = (await import(/* @vite-ignore */ GENERATOR_PATH)) as Generator;

// ---------------------------------------------------------------------------------------------------------
// Guard 4: Cursor stub parity
// ---------------------------------------------------------------------------------------------------------

type StubArgs = { folder: string; description: string | null; disableModel: boolean };
type StubRender = (a: StubArgs) => string;

/** Independent frontmatter read (NOT the generator's private one): description null when absent or empty. */
function stubArgsFor(root: string, folder: string): StubArgs {
  const raw = readFileSync(join(root, "skills", folder, "SKILL.md"), "utf8");
  const m = raw.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  const fm = (m ? parseYaml(m[1]) : {}) as Record<string, unknown> | null;
  const d = fm?.description;
  return {
    folder,
    description: typeof d === "string" && d !== "" ? d : null,
    disableModel: fm?.["disable-model-invocation"] === true,
  };
}

/** Compare the renderer to the generator over every skill folder under `root`. Returns the problems and the population. */
function stubParity(root: string, render: StubRender): { problems: string[]; compared: number } {
  const built = buildCursorNameMap(root);
  const problems: string[] = [...built.problems.map((p) => `generator: ${p}`)];
  let compared = 0;
  for (const folder of readdirSync(join(root, "skills")).sort()) {
    if (!existsSync(join(root, "skills", folder, "SKILL.md"))) continue;
    const rel = `cursor/skills/${render(stubArgsFor(root, folder)).match(/^name: (.*)$/m)?.[1] ?? "?"}/SKILL.md`;
    const want = built.files.get(rel);
    const got = render(stubArgsFor(root, folder));
    compared += 1;
    if (want === undefined) problems.push(`no generator output for ${folder} (${rel})`);
    else if (want !== got) problems.push(`DRIFT ${folder}`);
  }
  return { problems, compared };
}

const real: StubRender = (a) => renderCursorSkillStub(a);

function syntheticPluginRoot(): string {
  const root = mkdtempSync(join(tmpdir(), "cp-create-parity-"));
  const w = (rel: string, body: string) => {
    const p = join(root, rel);
    mkdirSync(dirname(p), { recursive: true });
    writeFileSync(p, body);
  };
  // YAML escapes are written as TEXT (backslash-u), so no raw separator character appears in this source file.
  w("skills/alpha/SKILL.md", '---\nname: alpha\ndescription: "Quote \\" backslash \\\\ colon: tab\\t line\\u2028sep and  double  space"\n---\n\nBody\n');
  w("skills/go/SKILL.md", '---\nname: go\ndescription: "Routes."\n---\n\nBody\n');
  w("skills/help/SKILL.md", '---\nname: help\ndescription: "Lists."\n---\n\nBody\n');
  w("skills/plan/SKILL.md", '---\nname: plan\ndescription: "Plans."\n---\n\nBody\n');
  w("skills/mismatch/SKILL.md", '---\nname: some-other-name\ndescription: "Name differs from folder."\n---\n\nBody\n');
  w("skills/user-invoked/SKILL.md", '---\nname: user-invoked\ndescription: "Hidden."\ndisable-model-invocation: true\n---\n\nBody\n');
  w("skills/no-description/SKILL.md", "---\nname: no-description\n---\n\nBody\n");
  // The synthetic NEW skill the create arm would produce.
  w("skills/brand-new-skill/SKILL.md", `---\nname: brand-new-skill\ndescription: "${"This skill should be used when a brand new routine appears and needs a home."}"\n---\n\nBody\n`);
  w("agents/engineering/review/synthetic-reviewer.md", '---\nname: synthetic-reviewer\ndescription: "Reviews."\nmodel: inherit\n---\n\nBody\n');
  return root;
}

describe("Guard 4: the pure Cursor stub renderer equals the generator", () => {
  it("over EVERY real skill folder (population floor asserted)", () => {
    const { problems, compared } = stubParity(PLUGIN_ROOT, real);
    expect(problems).toEqual([]);
    expect(compared).toBeGreaterThanOrEqual(MIN_TRACKED_SKILLS);
    // And the parity population is the generator's own population (no folder silently skipped).
    const generated = [...buildCursorNameMap(PLUGIN_ROOT).files.keys()].filter((k) => k.startsWith("cursor/skills/")).length;
    expect(compared).toBe(generated);
  });

  it("over a synthetic tree incl. a NEW skill, escapes, bare/command/model-disabled special cases and a name that differs from the folder", () => {
    const root = syntheticPluginRoot();
    try {
      const { problems, compared } = stubParity(root, real);
      expect(problems).toEqual([]);
      expect(compared).toBe(8);
      const built = buildCursorNameMap(root);
      expect(built.files.has("cursor/skills/soleur-brand-new-skill/SKILL.md")).toBe(true);
      // must-PASS non-canonical (harness row): the stub is named by the FOLDER, not by the frontmatter name.
      expect(built.files.get("cursor/skills/soleur-mismatch/SKILL.md")).toContain("name: soleur-mismatch\n");
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it("mutation 1: changing ONE character of the header is detected", () => {
    const mutated: StubRender = (a) => renderCursorSkillStub(a).replace("do not call", "do nt call");
    expect(mutated({ folder: "x", description: "d", disableModel: false })).not.toBe(real({ folder: "x", description: "d", disableModel: false }));
    expect(stubParity(PLUGIN_ROOT, mutated).problems.length).toBeGreaterThan(0);
  });

  it("mutation 2 (own dispatch): a parity loop over zero folders cannot pass the population floor", () => {
    const empty = mkdtempSync(join(tmpdir(), "cp-create-parity-empty-"));
    try {
      mkdirSync(join(empty, "skills"), { recursive: true });
      mkdirSync(join(empty, "agents"), { recursive: true });
      const { compared } = stubParity(empty, real);
      expect(compared).toBe(0);
      expect(compared).toBeLessThan(MIN_TRACKED_SKILLS); // the floor in the real-tree test above is what turns this RED
    } finally {
      rmSync(empty, { recursive: true, force: true });
    }
  });

  it("mutation 3: a second skill whose description contains a character the renderer mishandles is detected", () => {
    const root = syntheticPluginRoot();
    try {
      // A renderer that quotes with JSON.stringify leaves U+2028 raw where the generator escapes it.
      const sloppy: StubRender = (a) =>
        a.description !== null && a.folder === "alpha"
          ? renderCursorSkillStub(a).replace(/^description: .*$/m, () => `description: ${JSON.stringify(a.description)}`)
          : renderCursorSkillStub(a);
      const alpha = stubArgsFor(root, "alpha");
      expect(sloppy(alpha)).not.toBe(renderCursorSkillStub(alpha)); // self-check: the mutation changed something
      expect(stubParity(root, sloppy).problems.length).toBeGreaterThan(0);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it("a differently worded NEW skill renders the same bytes the generator would write for it", () => {
    const root = syntheticPluginRoot();
    try {
      const args = stubArgsFor(root, "brand-new-skill");
      expect(renderCursorSkillStub(args)).toBe(buildCursorNameMap(root).files.get("cursor/skills/soleur-brand-new-skill/SKILL.md"));
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });
});

// ---------------------------------------------------------------------------------------------------------
// Guard 4: Grok block
// ---------------------------------------------------------------------------------------------------------

describe("Guard 4: the rendered Grok block equals the pinned canonical", () => {
  const grokTest = readFileSync(join(PLUGIN_ROOT, "test", "grok-harness-invoke.test.ts"), "utf8");
  const pin = /const CANONICAL_MD5 = "([0-9a-f]{32})";/.exec(grokTest)?.[1];
  const planMd = readFileSync(join(PLUGIN_ROOT, "skills", "plan", "SKILL.md"), "utf8");

  it("the md5 pin is read from grok-harness-invoke.test.ts (single source) and the block read from plan/SKILL.md matches it", () => {
    expect(pin, "the pin literal must be found in grok-harness-invoke.test.ts").toMatch(/^[0-9a-f]{32}$/);
    expect(createHash("md5").update(readGrokBlock(planMd)).digest("hex")).toBe(pin);
  });

  it("a rendered SKILL.md carries that exact block, once, before the first H1 and outside the frontmatter", () => {
    const grok = readGrokBlock(planMd);
    const template = readFileSync(join(PLUGIN_ROOT, "skills", "skill-creator", "templates", "purpose.md"), "utf8");
    const skills = JSON.parse(readFileSync(join(FIX, "skills.json"), "utf8")) as SkillRecord[];
    const ctx: CreateContext = {
      patterns: [
        {
          slug: "synthetic-retry-pattern", title: "t", summary: "s", status: "open", openedOn: "2026-10-01", tags: [],
          evidence: ["knowledge-base/project/learnings/a.md"], requiredReading: false,
        },
      ],
      skills, skillDirs: skills.map((s) => s.name), agentPaths: [], cursorDirs: [], commandNames: [], openPrPaths: [],
      budget: { total: 2402, cap: 2436 }, isHashSuppressed: () => false,
    };
    const v = checkCreate(JSON.parse(readFileSync(join(FIX, "proposal.json"), "utf8")), ctx);
    expect(v.kind).toBe("create");
    if (v.kind !== "create") return;
    const r = renderCreateFiles({ proposal: v.proposal, grokBlock: grok, purposeTemplate: template, date: "2026-10-26", evidenceCount: 1 });
    expect(r.kind).toBe("rendered");
    if (r.kind !== "rendered") return;
    const text = r.files.skillMd;
    expect(text.split("<!-- grok-harness-invoke:start -->").length - 1).toBe(1);
    expect(text).toContain(grok);
    const lines = text.split("\n");
    const close = lines.indexOf("---", 1);
    expect(lines.indexOf("<!-- grok-harness-invoke:start -->")).toBeGreaterThan(close);
    expect(lines.indexOf("<!-- grok-harness-invoke:start -->")).toBeLessThan(lines.findIndex((l) => l.startsWith("# ")));
  });
});

// ---------------------------------------------------------------------------------------------------------
// Guard 2: budget counter and cap
// ---------------------------------------------------------------------------------------------------------

describe("Guard 2: the server's word count equals the bun test's, over the real tree", () => {
  // The independent definition: the SAME helpers components.test.ts calls, run under bun.
  const BUN_SCRIPT = `
    import { discoverSkills, parseComponent } from ${JSON.stringify(join(PLUGIN_ROOT, "test", "helpers"))};
    let total = 0, disabled = 0, n = 0, includingDisabled = 0;
    for (const p of discoverSkills()) {
      n++;
      const { frontmatter } = parseComponent(p);
      const desc = String(frontmatter.description || "");
      includingDisabled += desc.split(/\\s+/).filter(Boolean).length;
      if (frontmatter["disable-model-invocation"] === true) { disabled++; continue; }
      total += desc.split(/\\s+/).filter(Boolean).length;
    }
    console.log(JSON.stringify({ total, disabled, n, includingDisabled }));
  `;
  const bunRun = (): { total: number; disabled: number; n: number; includingDisabled: number } => {
    const out = execFileSync("bun", ["-e", BUN_SCRIPT], { cwd: PLUGIN_ROOT, encoding: "utf8", timeout: 60_000 });
    return JSON.parse(out.trim().split("\n").pop() as string);
  };

  it("total, population and user-invoked count equal what discoverSkills()/parseComponent() compute under bun", () => {
    const bun = bunRun();
    const ours = countDescriptionWords(PLUGIN_ROOT);
    expect(ours.ok).toBe(true);
    if (!ours.ok) return;
    expect(ours.total).toBe(bun.total);
    expect(ours.skills).toBe(bun.n);
    expect(ours.disabled).toBe(bun.disabled);
    expect(ours.skills).toBeGreaterThanOrEqual(MIN_TRACKED_SKILLS);
    expect(ours.disabled).toBeGreaterThan(0);
  });

  it("mutation 1 is real on this tree: counting user-invoked skills would NOT agree (the whitespace-split mutation is owned by the fixture-tree test, since tab and newline descriptions make a real-tree comparison direction-dependent)", () => {
    const bun = bunRun();
    expect(bun.includingDisabled).not.toBe(bun.total);
  });

  it("the cap is the constant assignment in components.test.ts and the total is within it", () => {
    const src = readFileSync(join(PLUGIN_ROOT, "test", "components.test.ts"), "utf8");
    const cap = readBudgetCap(src);
    expect(cap).not.toBeNull();
    const first = /^const SKILL_DESCRIPTION_WORD_BUDGET = (\d+);/m.exec(src);
    expect(cap).toBe(Number(first?.[1]));
    const ours = countDescriptionWords(PLUGIN_ROOT);
    expect(ours.ok && ours.total <= (cap as number)).toBe(true);
  });
});

// ---------------------------------------------------------------------------------------------------------
// prefer-patch calibration against the REAL skill list + the input ceiling on the real corpus
// ---------------------------------------------------------------------------------------------------------

describe("overlap threshold holds on the REAL skill list", () => {
  const cal = JSON.parse(readFileSync(join(FIX, "calibration.json"), "utf8")) as {
    evidence: Array<{ id: string; target: string; slug: string; description: string; when_to_use: string[] }>;
    negatives: Array<{ id: string; slug: string; description: string; when_to_use: string[] }>;
  };
  const counted = countDescriptionWords(PLUGIN_ROOT);

  it("the threshold still separates the two populations on the real tree: every negative below it, every evidence fixture at or above it", () => {
    expect(counted.ok).toBe(true);
    if (!counted.ok) return;
    expect(cal.negatives.length).toBeGreaterThanOrEqual(4);
    const evidence = cal.evidence.map((e) => {
      const r = rankOverlap(proposalOverlapText(e), counted.records);
      expect(r[0].name, e.id).toBe(e.target);
      return r[0].score;
    });
    const negatives = cal.negatives.map((n) => ({ id: n.id, ...rankOverlap(proposalOverlapText(n), counted.records)[0] }));
    // No absolute margin: a new real skill on a neighbouring subject moves a negative's score, and that must not red an
    // unrelated PR unless it genuinely closes the gap between the two populations, which is what this asserts.
    const worst = negatives.reduce((a, b) => (b.score > a.score ? b : a));
    console.info(`OVERLAP real tree: worst negative ${worst.id}->${worst.name}:${worst.score.toFixed(3)}, weakest evidence ${Math.min(...evidence).toFixed(3)}, threshold ${OVERLAP_REFUSE_THRESHOLD}`);
    expect(worst.score, `negative ${worst.id} now overlaps ${worst.name}; re-calibrate the threshold`).toBeLessThan(OVERLAP_REFUSE_THRESHOLD);
    expect(Math.min(...evidence)).toBeGreaterThanOrEqual(OVERLAP_REFUSE_THRESHOLD);
  });

  it("the input ceiling holds on the real corpus under the documented bytes/4 bound (and the bound is stated)", () => {
    expect(counted.ok).toBe(true);
    if (!counted.ok) return;
    const dir = join(REPO_ROOT, "knowledge-base", "project", "patterns");
    // Upper bound of the rendered index: the whole page files (the index renders only slug, title, summary, tags, evidence).
    const pageBytes = readdirSync(dir)
      .filter((f) => f.endsWith(".md"))
      .reduce((n, f) => n + statSync(join(dir, f)).size, 0);
    const skills = counted.records.filter((s) => !s.disableModelInvocation);
    const listBytes = Buffer.byteLength(skills.map((s) => `- ${s.name}: ${s.description}`).join("\n"), "utf8");
    const bound = Math.ceil((pageBytes + listBytes) / CREATE_INPUT_BYTES_PER_TOKEN);
    // Record: printed so the PR body can cite the measured margin.
    console.info(`CREATE input bound: pages=${pageBytes}B list=${listBytes}B tokens<=${bound} (ceiling ${CREATE_INPUT_MAX_TOKENS}, bytes/${CREATE_INPUT_BYTES_PER_TOKEN})`);
    expect(bound).toBeLessThanOrEqual(CREATE_INPUT_MAX_TOKENS);
    // A single over-ceiling skill list is refused by the real gate (never truncated).
    const huge = Array.from({ length: 700 }, (_, i) => ({ name: `s${i}`, description: "This skill should be used when " + "x ".repeat(40), disableModelInvocation: false }));
    expect(prepareCreate({ patterns: [{ slug: "p", title: "t", summary: "s", status: "open", openedOn: "2026-10-01", tags: [], evidence: [], requiredReading: false }], skills: huge, nonce: "0".repeat(16) }).kind).toBe("refused");
  });
});

// ---------------------------------------------------------------------------------------------------------
// ADR-092 amendment wording pin (Guard 1 anchor)
// ---------------------------------------------------------------------------------------------------------

function stripFences(text: string): string {
  return text.replace(/^```[\s\S]*?^```[^\n]*\n?/gm, "");
}

describe("the ADR-092 create-only amendment is pinned to the exported constants (Guard 1 anchor)", () => {
  const adr = readFileSync(
    join(REPO_ROOT, "knowledge-base", "engineering", "architecture", "decisions", "ADR-092-additive-only-auto-edit-boundary-and-hard-rule-body-weakening-gate.md"),
    "utf8",
  );
  const start = adr.indexOf("## Amendment — create-only new-skill path");
  const amendment = start === -1 ? "" : stripFences(adr.slice(start)).replace(/\s+/g, " ");

  it("the amendment exists and is the tail of the ADR", () => {
    expect(start, "ADR-092 must carry the create-only amendment heading").toBeGreaterThan(-1);
    expect(amendment.length).toBeGreaterThan(1000);
  });

  it("names exactly the six paths the code derives (with <slug> for the slug)", () => {
    const paths = createPathList("zzz").map((p) => p.replaceAll("zzz", "<slug>"));
    expect(paths).toHaveLength(6);
    for (const p of paths) expect(amendment, p).toContain(p);
    expect(amendment).toContain("A seventh path");
  });

  it("states the numeric and verbatim contract the code enforces", () => {
    expect(amendment).toContain(`at most ${CREATE_DESCRIPTION_MAX_WORDS} words`);
    expect(amendment).toContain("top three");
    expect(amendment).toContain("`# skill-security-scan verdict: LOW-RISK`");
    expect(amendment).toContain("`SKILL_SECURITY_SCAN_OFFLINE=1`");
    expect(amendment).toContain(`\`${CREATE_PR_BODY_LINE}\``);
    expect(amendment).toContain("`create-refused`");
    expect(amendment).toContain("`allowedPaths: []`");
    expect(amendment).toContain("`mergeMode: \"none\"`");
    expect(amendment).toContain("the edit arm still never accepts status `A`");
    expect(amendment).toContain("only the synthetic `skill-security-scan PR gate` and `test` checks are excluded from the create PR");
    expect(amendment).toContain("every other synthetic check the helper posts remains synthetic");
  });

  // One ADR phrase per stage id of CREATE_STAGE_ORDER. The Record type makes a stage added to the list without a phrase a
  // compile error, and the key-set assertion below makes it a test failure; positions must ascend (the order is the claim).
  // This pins the ADR TEXT to the exported list; that the arm itself runs in this order is asserted by the arm tests.
  const STAGE_PHRASES = {
    stepA: {
      "week-cap": "Step A (`create-propose`), in order: the week cap (shared with the edit arm",
      "index-empty": "a non-empty pattern index",
      "clone-present": "the clone being present",
      "create-open": "one open create at a time",
      populations: "the budget and collision populations measured from the clone, including the open pull request path scan",
      "input-size": "the input-size ceiling (refuse, never truncate)",
      "api-key": "the API key",
      model: "then ONE model call with no retry.",
      "check-create": "After the call comes `checkCreate`, whose gates run in this order:",
    },
    checkCreate: {
      schema: "schema validation",
      "slug-format": "slug format",
      shape: "shape, instruction-risk and claim-word checks over every model string",
      pii: "the PII and credential screen over every model string",
      ledger: "the ledger (a pattern with an existing proposal",
      collision: "slug collision (skill, agent, command stem, Cursor stub directory",
      "prefer-patch": "prefer-patch (the model must name",
      budget: "the description budget (a readable cap and total, at least the minimum and at most 30 words, and within `cap - total`).",
    },
    stepB: {
      "branch-taken": "Step B (`create-persist`), in order: the branch-taken check, before the clone is touched",
      "token-set": "sets the installation token",
      "fetch-reset": "`git fetch --depth=1 origin main` and `git reset --hard FETCH_HEAD`",
      "token-strip": "strips the token from `remote.origin.url`",
      recheck: "re-runs `checkCreate` on the refreshed tree",
      render: "renders the three files",
      "rendered-gate": "runs the rendered-output gate",
      scan: "then `soleur:skill-security-scan` on BOTH files",
      "readme-sync": "the README sync (changed set exactly the two README paths)",
      "bytes-differ": "the bytes-differ check",
      "token-restore": "restores the token with `setOriginToken`",
      fetch: "fetches once more",
      "base-moved": "the base-moved check",
      commit: "and only then the commit.",
    },
  } as const satisfies { [K in keyof typeof CREATE_STAGE_ORDER]: Record<(typeof CREATE_STAGE_ORDER)[K][number], string> };

  it("the ADR lists every stage of CREATE_STAGE_ORDER, once each, in the order the list gives (Step A, checkCreate, Step B)", () => {
    for (const group of ["stepA", "checkCreate", "stepB"] as const) {
      expect(Object.keys(STAGE_PHRASES[group]), group).toEqual([...CREATE_STAGE_ORDER[group]]);
    }
    const phrases = [
      ...CREATE_STAGE_ORDER.stepA.map((id) => STAGE_PHRASES.stepA[id]),
      ...CREATE_STAGE_ORDER.checkCreate.map((id) => STAGE_PHRASES.checkCreate[id]),
      ...CREATE_STAGE_ORDER.stepB.map((id) => STAGE_PHRASES.stepB[id]),
    ];
    const at = phrases.map((o) => amendment.indexOf(o));
    expect(at.filter((i) => i < 0), `missing anchors: ${phrases.filter((_, i) => at[i] < 0).join(" | ")}`).toEqual([]);
    expect([...at].sort((x, y) => x - y)).toEqual(at);
    expect(new Set(at).size).toBe(at.length);
    for (const o of phrases) expect(amendment.split(o).length - 1, o).toBe(1);
  });

  it("states the stub check scope and the deadline scope the way the code behaves", () => {
    expect(amendment).toContain("the stub check is renderer self-consistency; parity with the real generator is CI `cursor-name-map --check`");
    expect(amendment).toContain("`deadline` covers the pre-commit phase only, not `safeCommitAndPr` and not the final cleanup");
  });

  it("harness: the pin can fail (reordering two stage phrases or dropping one is detected)", () => {
    const swapped = amendment.replace("the base-moved check", "XX").replace("the bytes-differ check", "the base-moved check").replace("XX", "the bytes-differ check");
    expect(swapped).not.toBe(amendment);
    expect(swapped.indexOf("the base-moved check")).toBeLessThan(swapped.indexOf("the bytes-differ check"));
    expect(amendment.indexOf("the bytes-differ check")).toBeLessThan(amendment.indexOf("the base-moved check"));
  });

  it("states the controls, the tripwire status of the denylist, the cap enforcement wording, the path function and the token and base-moved sequence", () => {
    expect(amendment).toContain("The controls are the DRAFT pull request, `mergeMode: \"none\"`, the LOW-RISK scan and the human reviewer of every draft");
    expect(amendment).toContain("the instruction-risk denylist is a tripwire, not a control");
    expect(amendment).toContain("a reviewer may add `disable-model-invocation: true` by hand before merge");
    expect(amendment).toContain("enforced by CI at the cap value until a human changes the cap");
    expect(amendment).not.toContain("never exceed 2436");
    expect(amendment).toContain("derived by one exported function, `createPathList(slug)`");
    expect(amendment).toContain("Step A runs with the installation token on disk but spawns no script");
    expect(amendment).toContain("stripped from `remote.origin.url` after the first authenticated fetch and before any script spawns");
    expect(amendment).toContain("restored (`setOriginToken`) only for the final fetch and the single `safeCommitAndPr` call");
    expect(amendment).toContain("returns `persist/base-moved` on any difference");
    expect(amendment).toContain("the server renders them from the validated pattern slug, the evidence count and the run date");
  });

  it("limits stated in the amendment's own words agree with the constants", () => {
    // The ADR states the minimum without a number; the constants must stay coherent with 'at most 30 words'.
    expect(CREATE_DESCRIPTION_MIN_WORDS).toBeLessThan(CREATE_DESCRIPTION_MAX_WORDS);
  });

  it("harness: weakening the pinned text is detected (the instrument can fail)", () => {
    const weakened = amendment.replace("A seventh path", "An extra path");
    expect(weakened).not.toBe(amendment);
    expect(weakened).not.toContain("A seventh path");
  });
});
