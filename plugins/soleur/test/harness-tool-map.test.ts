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
  parseToolsTable,
  readToolsTable,
  usesTool,
} from "../lib/harness-tool-map";

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
    // A renamed heading makes `parseToolsTable` return ∅, and every coverage
    // question below would then be vacuously true. This is the floor that turns
    // that into a RED.
    expect(
      { codex: codex.size, devin: devin.size },
      "one of the ## Tools tables parsed to nothing — the heading was renamed or the " +
        "table shape changed, and every coverage assertion below would pass vacuously",
    ).toEqual({ codex: codex.size, devin: devin.size });
    expect(codex.size).toBeGreaterThanOrEqual(8);
    expect(devin.size).toBeGreaterThanOrEqual(8);
  });

  test("the corpus is the agent-read population, floored per source", () => {
    // Per-source floors, not one union figure (#8318 plan review): a union total
    // cannot name WHICH source went empty, and it tolerates a large partial loss.
    // Measured 2026-09-23: skills 102, commands 3, codex 3, devin 3, references 115,
    // agents 67 — 107 population docs (after 4 path exclusions) + 67 agents = 174
    // before the references widening, 289 after.
    expect(lsFiles(":(glob)plugins/soleur/skills/*/SKILL.md")).toBeGreaterThanOrEqual(99);
    expect(lsFiles(":(glob)plugins/soleur/commands/*.md")).toBeGreaterThanOrEqual(2);
    expect(lsFiles(":(glob)plugins/soleur/skills/*/references/**/*.md")).toBeGreaterThanOrEqual(110);
    expect(discoverAgentPaths().length).toBeGreaterThanOrEqual(65);
    expect(docs.length).toBeGreaterThanOrEqual(280);
  });

  test("every used Claude tool name is translated by BOTH tables", () => {
    const problems: string[] = [];
    for (const tool of CLAUDE_CODE_TOOLS) {
      const user = docs.find((d) => usesTool(d.text, tool));
      if (!user) continue;
      const missing: string[] = [];
      if (!codex.has(tool)) missing.push("plugins/soleur/codex/INSTRUCTIONS.md");
      if (!devin.has(tool)) missing.push("plugins/soleur/devin/INSTRUCTIONS.md");
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
    expect(used.filter((t) => !codex.has(t) || !devin.has(t))).toEqual([]);
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
    expect([...parsed].sort()).toEqual(["Glob", "Grep", "Read", "Skill", "Workflow"]);
    expect(parsed.has("SendMessage")).toBe(false);
    // A renamed heading yields ∅ — the state the floor above exists to catch.
    expect(parseToolsTable(fixture.replace("## Tools", "## Tool mapping")).size).toBe(0);
  });
});
