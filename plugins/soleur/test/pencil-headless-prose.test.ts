import { describe, expect, test } from "bun:test";
import { readFileSync } from "fs";
import { resolve } from "path";

// #11156 / #11168 prose contract for the headless Pencil path. Fixed live tool set
// (CTO ruling 1): agents are told only about tools the adapter really serves.
// Pure prose assertions; no engine, no adapter.

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const read = (rel: string) => readFileSync(resolve(REPO_ROOT, rel), "utf-8");

const AGENT_PATH = "plugins/soleur/agents/product/design/ux-design-lead.md";
const SKILL_PATH = "plugins/soleur/skills/pencil-setup/SKILL.md";
const agent = read(AGENT_PATH);
const skill = read(SKILL_PATH);

const LIVE = new Set([
  "open_document",
  "save",
  "batch_design",
  "get_screenshot",
  "export_nodes",
  "get_editor_state",
  "get_variables",
  "read_skill",
]);

// Every Pencil tool name the repo has ever told an agent about that is NOT live.
const RETIRED = [
  "batch_get",
  "snapshot_layout",
  "get_guidelines",
  "get_style_guide",
  "get_style_guide_tags",
  "find_empty_space_on_canvas",
  "search_all_unique_properties",
  "replace_all_matching_properties",
  "set_variables",
  "get_style",
];

const UNIVERSE = new Set([...LIVE, ...RETIRED]);

// A line is on the Desktop/IDE branch when it says so.
const DESKTOP_IDE = /\b(Desktop|IDE)\b/;

function toolTokens(line: string): string[] {
  const out: string[] = [];
  for (const m of line.matchAll(/mcp__pencil__([a-z_]+)/g)) out.push(m[1]);
  for (const m of line.matchAll(/`([a-z][a-z_]*)(?:\(|`)/g)) {
    if (UNIVERSE.has(m[1])) out.push(m[1]);
  }
  return out;
}

function headlessOffenders(text: string): string[] {
  const bad: string[] = [];
  text.split("\n").forEach((line, i) => {
    if (DESKTOP_IDE.test(line)) return;
    for (const t of toolTokens(line)) {
      if (!LIVE.has(t)) bad.push(`${i + 1}: ${t}`);
    }
  });
  return bad;
}

describe("headless-branch tool names are live tools", () => {
  test("ux-design-lead.md names only the 8 live tools off the Desktop/IDE branch", () => {
    expect(headlessOffenders(agent)).toEqual([]);
  });

  test("pencil-setup/SKILL.md names only the 8 live tools off the Desktop/IDE branch", () => {
    expect(headlessOffenders(skill)).toEqual([]);
  });

  test("the parser is not vacuous: it sees live tool tokens in both files", () => {
    const count = (t: string) => t.split("\n").flatMap(toolTokens).filter((x) => LIVE.has(x)).length;
    expect(count(agent)).toBeGreaterThan(3);
    expect(count(skill)).toBeGreaterThan(2);
  });

  test("the parser flags a retired tool on an unmarked line", () => {
    expect(headlessOffenders("Call `batch_get` first.\nCall mcp__pencil__snapshot_layout now.")).toHaveLength(2);
    expect(headlessOffenders("Desktop/IDE: call `batch_get` first.")).toEqual([]);
  });
});

describe("pencil-setup/SKILL.md", () => {
  test("registration uses PEN_CLI_KEY with a PENCIL_CLI_KEY fallback mention and @pen.dev/cli", () => {
    expect(skill).toContain("PEN_CLI_KEY");
    expect(skill).toContain("@pen.dev/cli");
    expect(skill).not.toContain("@pencil.dev/cli");
    expect(skill).toMatch(/PENCIL_CLI_KEY[^\n]*(fallback|deprecated)|(fallback|deprecated)[^\n]*PENCIL_CLI_KEY/i);
    expect(skill).toContain("22.19");
  });

  test("keeps the silent-drop anchor", () => {
    expect(skill).toContain("ex-cq-pencil-mcp-silent-drop-diagnosis-checklist");
  });

  test("REFUSED save: reason table maps every reason code to a recovery step", () => {
    for (const code of ["stale", "missing", "unknown-baseline", "refusal-pending", "empty", "unrecognized"]) {
      const row = skill.split("\n").find((l) => l.trim().startsWith("|") && l.includes(`\`reason=${code}\``));
      expect(row, `table row for reason=${code}`).toBeDefined();
      // a recovery column with real content
      expect((row ?? "").split("|").filter((c) => c.trim()).length).toBeGreaterThanOrEqual(3);
    }
  });

  test("first triage step is the tool result and stderr marker, with no ssh/docker exec/systemctl", () => {
    const i = skill.indexOf("**Silent-drop diagnosis**");
    expect(i).toBeGreaterThan(-1);
    const section = skill.slice(i, skill.indexOf("\n- **", i + 10) === -1 ? undefined : skill.indexOf("\n- **", i + 10));
    expect(section).toMatch(/\(a\)[^;]*(tool result)[^;]*(stderr)/i);
    const ri = skill.indexOf("REFUSED save: reasons");
    expect(ri).toBeGreaterThan(-1);
    const refused = skill.slice(ri);
    for (const banned of [/\bssh\b/, /docker exec/, /systemctl/]) {
      expect(skill).not.toMatch(banned);
      expect(refused).not.toMatch(banned);
    }
  });

  test("Save sentinel documents the stale rule, recovery, the unclosable window and the startup window", () => {
    const i = skill.indexOf("**Save sentinel**");
    expect(i).toBeGreaterThan(-1);
    const section = skill.slice(i, skill.indexOf("\n- **", i + 10));
    expect(section).toMatch(/changed on disk/i);
    expect(section).toMatch(/open_document/);
    expect(section).toMatch(/replay/i);
    expect(section).toMatch(/second writer/i);
    expect(section).toMatch(/startup/i);
    expect(section).toMatch(/one writer/i);
  });

  test("states the one-writer rule with the Desktop caveat, the read auto-save note and the snapshot note", () => {
    expect(skill).toMatch(/one writer per file/i);
    expect(skill).toMatch(/Pencil Desktop[^\n]*(writer|same file)|(writer|same file)[^\n]*Pencil Desktop/i);
    expect(skill).toMatch(/batch_design[^\n]*auto-save|auto-save[^\n]*batch_design/i);
    expect(skill).toMatch(/snapshot/i);
  });
});

describe("ux-design-lead.md", () => {
  test("headless guidance goes through read_skill and snapshot_layout is not used headless", () => {
    expect(agent).toContain("read_skill");
    expect(headlessOffenders(agent)).toEqual([]);
  });

  test("post-save hard gate: node -e with sha256, size, children, changed hash, REFUSED save:", () => {
    expect(agent).toContain("# pre-edit-sha256");
    expect(agent).toContain("# post-save-gate");
    const gate = agent.slice(agent.indexOf("# post-save-gate"));
    expect(gate).toMatch(/sha256/);
    expect(gate).toMatch(/128/);
    expect(gate).toMatch(/children/);
    expect(agent).toMatch(/REFUSED save:/);
  });

  test("step 3.2 commits the first REFUSED save: line verbatim into the wireframe summary", () => {
    expect(agent).toMatch(/first line[^\n]*REFUSED save:[^\n]*(summary|commit)|REFUSED save:[^\n]*first line[^\n]*(summary|commit)/i);
  });

  test("relays the Node floor message and says export no longer renames", () => {
    expect(agent).toMatch(/22\.19/);
    expect(agent).toMatch(/verbatim/);
    expect(agent).toMatch(/does not rename|no longer renames/i);
  });

  test("keeps the Desktop/IDE wording for style-guide and guidelines tools", () => {
    expect(agent).toMatch(/Desktop\/IDE/);
  });
});

describe("pointer edits in other prose", () => {
  const files = [
    "plugins/soleur/skills/brainstorm/SKILL.md",
    "plugins/soleur/skills/plan/SKILL.md",
    "plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md",
  ];
  for (const f of files) {
    test(`${f} no longer names @pencil.dev/cli or batch_get/snapshot_layout headless`, () => {
      const t = read(f);
      expect(t).not.toContain("@pencil.dev/cli");
      expect(t).not.toContain("PENCIL_CLI_KEY");
    });
  }

  test("brainstorm-brand-workshop case pattern matches @pen.dev/cli", () => {
    expect(read("plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md")).toContain("*@pen.dev/cli*");
  });

  test("brainstorm and plan point at pencil-setup/SKILL.md", () => {
    expect(read("plugins/soleur/skills/brainstorm/SKILL.md")).toContain("pencil-setup/SKILL.md");
    expect(read("plugins/soleur/skills/plan/SKILL.md")).toContain("pencil-setup/SKILL.md");
  });
});
