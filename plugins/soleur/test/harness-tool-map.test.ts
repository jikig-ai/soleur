import { describe, test, expect } from "bun:test";
import { execFileSync } from "child_process";
import { readFileSync } from "fs";
import { resolve } from "path";
import { PLUGIN_ROOT, discoverAgentPaths } from "../lib/agent-registry";
import { REPO_ROOT, readPopulation } from "../lib/harness-parity";
import {
  CLAUDE_CODE_TOOLS,
  CODEX_INSTRUCTIONS,
  DEVIN_INSTRUCTIONS,
  isEmptyTranslation,
  parseToolsTable,
  readToolsTable,
  usesTool,
} from "../lib/harness-tool-map";
import {
  MIN_REGISTRY_AGENTS,
  MIN_TRACKED_COMMANDS,
  MIN_TRACKED_REFERENCES,
  MIN_TRACKED_SKILLS,
} from "./lib/population-floors";

// Guard 3 of the harness-parity hardening bundle (#8318, ADR-240).
//
// PROPERTY: every Claude Code tool name used in an agent-read doc has a row in BOTH
// the Codex and the Devin `## Tools` table.
//
// ANCHOR (what can move together, and what cannot). The vocabulary and the two tables
// live in this repo and one diff can edit all three, so the pin is consistency. The
// anchor OUTSIDE the diff is the Claude Code tools reference, cited with its retrieval
// date in `harness-tool-map.ts` — a name removed from the vocabulary is checkable
// against it.

const codex = readToolsTable(CODEX_INSTRUCTIONS);
const devin = readToolsTable(DEVIN_INSTRUCTIONS);

/**
 * The agent-read corpus: the census population (skills, commands, the Codex/Devin
 * shims and, since #8317, skill references) plus the agent bodies, using the same
 * exclusions `discoverAgentPaths()` applies.
 */
function corpus(): { path: string; text: string }[] {
  const docs = readPopulation().map((d) => ({ path: d.path, text: d.text }));
  // `discoverAgentPaths()` returns paths relative to PLUGIN_ROOT, not absolute.
  const agents = discoverAgentPaths().map((p) => ({
    path: `plugins/soleur/${p}`,
    text: readFileSync(resolve(PLUGIN_ROOT, p), "utf8"),
  }));
  return [...docs, ...agents];
}

function lsFiles(pathspec: string): number {
  return execFileSync("git", ["ls-files", "--full-name", "--", pathspec], {
    cwd: REPO_ROOT,
    encoding: "utf8",
    maxBuffer: 32 * 1024 * 1024,
  })
    .split("\n")
    .filter((l) => l.length > 0).length;
}

describe("harness tool-map coverage", () => {
  const docs = corpus();

  test("both tables parse to a non-empty vocabulary", () => {
    // The previous form here compared an object to ITSELF
    // (`toEqual({codex: codex.size, …})` against the same literal) under this
    // message — an assertion that cannot fail, carrying a load-bearing claim.
    // A dead assertion is worse than none: it reads as coverage. The two floors
    // below are what actually catch a renamed heading, so the message lives on
    // them. Measured 2026-09-23: codex 36, devin 35.
    expect(
      codex.size,
      "the Codex ## Tools table parsed to nothing — the heading was renamed or the " +
        "table shape changed, and every coverage assertion below would pass vacuously",
    ).toBeGreaterThanOrEqual(30);
    expect(devin.size, "the Devin ## Tools table parsed to nothing — same failure mode").toBeGreaterThanOrEqual(
      30,
    );
  });

  test("the corpus is the agent-read population, floored per source", () => {
    // Per-source floors, not one union figure (#8318 plan review): a union total
    // cannot name WHICH source went empty, and it tolerates a large partial loss.
    // Measured 2026-09-23: skills 102, commands 3, codex 3, devin 3, references 115,
    // agents 67 — 107 population docs (after 4 path exclusions) + 67 agents = 174
    // before the references widening, 289 after.
    // These floor the REPO. They are necessary and NOT sufficient: the corpus is
    // `docs`, and the two are only related if `corpus()` actually read the files.
    expect(lsFiles(":(glob)plugins/soleur/skills/*/SKILL.md")).toBeGreaterThanOrEqual(MIN_TRACKED_SKILLS);
    expect(lsFiles(":(glob)plugins/soleur/commands/*.md")).toBeGreaterThanOrEqual(MIN_TRACKED_COMMANDS);
    expect(lsFiles(":(glob)plugins/soleur/skills/*/references/**/*.md")).toBeGreaterThanOrEqual(
      MIN_TRACKED_REFERENCES,
    );
    expect(discoverAgentPaths().length).toBeGreaterThanOrEqual(MIN_REGISTRY_AGENTS);
    expect(docs.length).toBeGreaterThanOrEqual(280);

    // Floor the CORPUS per source, over `docs` itself. Without this, every
    // assertion above holds while `corpus()` returns 289 docs whose `text` is
    // `""` — measured: blanking both text expressions kept all four repo floors
    // and `docs.length >= 280` green, with zero tools "used" and `problems`
    // empty. Counting members is not reading them.
    const fromSkills = docs.filter((d) => /^plugins\/soleur\/skills\/[^/]+\/SKILL\.md$/.test(d.path));
    const fromRefs = docs.filter((d) => d.path.includes("/references/"));
    const fromAgents = docs.filter((d) => d.path.startsWith("plugins/soleur/agents/"));
    expect(fromSkills.length).toBeGreaterThanOrEqual(95);
    expect(fromRefs.length).toBeGreaterThanOrEqual(MIN_TRACKED_REFERENCES);
    expect(fromAgents.length).toBeGreaterThanOrEqual(MIN_REGISTRY_AGENTS);
    expect(docs.filter((d) => d.text.trim().length === 0)).toEqual([]);
  });

  test("the corpus actually NAMES tools — the coverage question is not vacuous", () => {
    // `problems === []` is satisfied perfectly by a corpus in which no tool is
    // ever detected, so the emptiness assertion below needs a companion that
    // proves detection still happens. Measured 2026-09-23: 19 of 47 vocabulary
    // names are used in tool-shaped context.
    const used = CLAUDE_CODE_TOOLS.filter((t) => docs.some((d) => usesTool(d.text, t)));
    expect(
      used.length,
      `only ${used.length} vocabulary names were detected in the corpus — usesTool or ` +
        `the corpus regressed, and the coverage assertion below is asserting nothing`,
    ).toBeGreaterThanOrEqual(15);
  });

  test("every used Claude tool name is translated by BOTH tables", () => {
    const problems: string[] = [];
    for (const tool of CLAUDE_CODE_TOOLS) {
      const user = docs.find((d) => usesTool(d.text, tool));
      if (!user) continue;
      // A row must carry a TRANSLATION, not merely the name. A present row with an
      // empty second cell resolves nothing for the session that meets the tool.
      const missing: string[] = [];
      if (!codex.has(tool) || isEmptyTranslation(codex.get(tool)))
        missing.push("plugins/soleur/codex/INSTRUCTIONS.md");
      if (!devin.has(tool) || isEmptyTranslation(devin.get(tool)))
        missing.push("plugins/soleur/devin/INSTRUCTIONS.md");
      if (missing.length === 0) continue;
      const lineIdx = user.text.split("\n").findIndex((l) => usesTool(l, tool));
      problems.push(
        `${tool} — used at ${user.path}:${lineIdx + 1}, missing a row in ${missing.join(" and ")}. ` +
          `Add:  | ${tool} | <the harness's equivalent, or "no equivalent; report the unsupported gate"> |`,
      );
    }
    expect(problems, problems.join("\n")).toEqual([]);
  });

  // Must-PASS non-canonical input. The Grok invoke block backfilled into all 102
  // skills (#8390) embeds the mechanism nouns `Skill tool`, `Task tool` and
  // `spawn_subagent`, so EVERY skill now names them. This fixture is the
  // post-backfill validation that the gate neither goes vacuous nor reds on them.
  test("a doc embedding the canonical Grok invoke block passes", () => {
    const canonical = readFileSync(
      resolve(REPO_ROOT, "plugins/soleur/skills/plan/SKILL.md"),
      "utf8",
    );
    const block = canonical
      .split("\n")
      .slice(
        canonical.split("\n").indexOf("<!-- grok-harness-invoke:start -->"),
        canonical.split("\n").indexOf("<!-- grok-harness-invoke:end -->") + 1,
      )
      .join("\n");
    expect(block).toContain("Skill tool");
    expect(block).toContain("Task tool");
    const used = CLAUDE_CODE_TOOLS.filter((t) => usesTool(block, t));
    expect(used.length).toBeGreaterThan(0);
    expect(
      used.filter(
        (t) =>
          !codex.has(t) ||
          !devin.has(t) ||
          isEmptyTranslation(codex.get(t)) ||
          isEmptyTranslation(devin.get(t)),
      ),
    ).toEqual([]);
  });

  test("the parser reads the first column, splits on / and drops qualifiers", () => {
    const fixture = [
      "## Tools",
      "",
      "| Soleur instruction | Harness execution |",
      "| --- | --- |",
      "| Read / Glob / Grep | read, grep, glob |",
      "| Skill `soleur:<name>` | slash command |",
      "| Workflow scripts | translate orchestration |",
      "",
      "## Next",
      "",
      "| SendMessage | a row AFTER the section must not be read |",
    ].join("\n");
    const parsed = parseToolsTable(fixture);
    expect([...parsed.keys()].sort()).toEqual(["Glob", "Grep", "Read", "Skill", "Workflow"]);
    expect(parsed.has("SendMessage")).toBe(false);
    // The translation travels with the name.
    expect(parsed.get("Skill")).toBe("slash command");
    expect(parsed.get("Read")).toBe("read, grep, glob");
    // And an emptied cell is not a translation.
    const blanked = fixture.replace("| Skill `soleur:<name>` | slash command |", "| Skill `soleur:<name>` |  |");
    expect(isEmptyTranslation(parseToolsTable(blanked).get("Skill"))).toBe(true);
    expect(isEmptyTranslation("n/a")).toBe(true);
    expect(isEmptyTranslation("TODO")).toBe(true);
    expect(isEmptyTranslation("`todo_write` tool")).toBe(false);
    // A renamed heading yields ∅ — the state the floor above exists to catch.
    expect(parseToolsTable(fixture.replace("## Tools", "## Tool mapping")).size).toBe(0);
  });
});
