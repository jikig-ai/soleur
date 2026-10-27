import { describe, expect, test } from "bun:test";
import { readFileSync } from "fs";
import { resolve } from "path";
import {
  LIVE_TOOL_NAMES,
  RAW_CALL_STEERING,
  REMOVED_TOOL_NAMES,
} from "../skills/pencil-setup/scripts/pencil-error-enrichment.mjs";
import * as saveGate from "../skills/pencil-setup/scripts/pencil-save-gate.mjs";

// #11156 / #11168 prose contract for the headless Pencil path. Fixed live tool set
// (CTO ruling 1): agents are told only about tools the adapter really serves, and the
// refusal / not-persisted marker contract the adapter emits (first line of the tool
// result) is the one the prose documents. Pure prose assertions; no engine, no adapter.
// Only plugin-tree prose is read here: a read of a knowledge-base path would make this
// suite a kb consumer (scripts/test-affected-kb-consumers ratchet); the constitution and
// ADR-304 wording is checked by grep in the review notes instead.

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const read = (rel: string) => readFileSync(resolve(REPO_ROOT, rel), "utf-8");

const AGENT_PATH = "plugins/soleur/agents/product/design/ux-design-lead.md";
const SKILL_PATH = "plugins/soleur/skills/pencil-setup/SKILL.md";
const BRAINSTORM_PATH = "plugins/soleur/skills/brainstorm/SKILL.md";
const PLAN_PATH = "plugins/soleur/skills/plan/SKILL.md";
const WORKSHOP_PATH = "plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md";
const agent = read(AGENT_PATH);
const skill = read(SKILL_PATH);
const workshop = read(WORKSHOP_PATH);

// SHARED TEXT CONTRACT: these sentences are written verbatim into the adapter / save-gate
// texts (FA1b) and into the prose (here). Quoted exactly; a reworded copy is a drift.
const REPLAY_SAFETY =
  "Before replaying, check whether the edit is already present (compare the node count open_document reports, or Get the nodes): this session's own interrupted save may already have written it.";
const ONLY_COPY =
  "If a retry is refused, the in-memory document is the only complete copy: read it out (get_editor_state, or Get/Print inside batch_design) or export it BEFORE calling open_document.";
const RESTORE_FIRST = "If the file is tracked, restore it from version control first.";
const STEERING =
  "Do not call Export or TakeScreenshot inside batch_design: use export_nodes and get_screenshot (raw calls skip the adapter's containment, overwrite list and unsaved-memory warning, and a relative path is resolved against the document's directory, so it can write next to the .pen).";

// Reason codes come from the save gate itself (REASON_CODES), so a new code without a prose
// row fails here. The two shared sentences are also compared with the gate's exports: a
// reworded copy on either side is a drift.
const ALL_CODES: string[] = [...saveGate.REASON_CODES];

const LIVE = new Set<string>(LIVE_TOOL_NAMES);
// `get_style` is a REPL command the adapter never exposes; it is not in the removed-stub
// table, so it stays an explicit extra.
const RETIRED = [...REMOVED_TOOL_NAMES, "get_style"];
const UNIVERSE = new Set<string>([...LIVE, ...RETIRED]);

// A line is on the Desktop/IDE branch when it says so.
const DESKTOP_IDE = /\b(Desktop|IDE)\b/;

// Every tool-name occurrence on a line: mcp__pencil__ names, backticked names (with or
// without a call paren), and BARE identifier words (fenced blocks, tables, plain prose).
// A bare word is only counted when it is an underscore identifier of the universe or a
// name that is not an ordinary English word (`save` needs backticks or mcp__ to count).
function toolTokens(line: string): string[] {
  const out: string[] = [];
  for (const m of line.matchAll(/mcp__pencil__([a-z_]+)/g)) out.push(m[1]);
  for (const m of line.matchAll(/`([a-z][a-z_]*)(?:\(|`)/g)) {
    if (UNIVERSE.has(m[1])) out.push(m[1]);
  }
  for (const m of line.matchAll(/(?<![A-Za-z0-9_`])([a-z]+(?:_[a-z]+)+)(?![A-Za-z0-9_])/g)) {
    if (UNIVERSE.has(m[1]) && !out.includes(m[1])) out.push(m[1]);
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
    expect(LIVE.size).toBe(8);
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

  test("the parser flags a retired tool on an unmarked line, backticked, bare, or in a fenced block", () => {
    expect(headlessOffenders("Call `batch_get` first.\nCall mcp__pencil__snapshot_layout now.")).toHaveLength(2);
    expect(headlessOffenders("```text\nget_style_guide_tags\n```")).toHaveLength(1);
    expect(headlessOffenders("| batch_get | removed |")).toHaveLength(1);
    expect(headlessOffenders("Desktop/IDE: call `batch_get` first.")).toEqual([]);
    expect(headlessOffenders("call batch_design and read_skill")).toEqual([]);
  });

  test("the retired census is the adapter's own table plus get_style", () => {
    expect(REMOVED_TOOL_NAMES).toHaveLength(9);
    for (const t of REMOVED_TOOL_NAMES) expect(LIVE.has(t)).toBe(false);
  });
});

// Reason-table rows: `| `reason=<code>` | meaning | recovery |`
function tableRow(text: string, code: string): string | undefined {
  return text.split("\n").find((l) => l.trim().startsWith("|") && l.includes(`\`reason=${code}\``));
}
const recovery = (row: string) => row.split("|").filter((c) => c.trim()).slice(-1)[0] ?? "";

describe("pencil-setup/SKILL.md", () => {
  test("registration uses PEN_CLI_KEY with a PENCIL_CLI_KEY fallback mention and @pen.dev/cli", () => {
    expect(skill).toContain("PEN_CLI_KEY");
    expect(skill).toContain("@pen.dev/cli");
    expect(skill).not.toContain("@pencil.dev/cli");
    expect(skill).toMatch(/PENCIL_CLI_KEY[^\n]*(fallback|deprecated)|(fallback|deprecated)[^\n]*PENCIL_CLI_KEY/i);
    expect(skill).toMatch(/Node >= 22\.19\.0/);
  });

  test("one explicit export of PEN_CLI_KEY from Doppler, and no `pen login` path (the adapter refuses without the key)", () => {
    expect(skill).toContain('export PEN_CLI_KEY="$(doppler secrets get PENCIL_CLI_KEY -p soleur -c dev --plain)"');
    expect(skill).not.toMatch(/pen login/);
  });

  test("keeps the silent-drop anchor", () => {
    expect(skill).toContain("ex-cq-pencil-mcp-silent-drop-diagnosis-checklist");
  });

  test("REFUSED save: reason table maps the six real refusal codes to a recovery step; `missing` is no longer a refusal", () => {
    for (const code of ["stale", "unknown-baseline", "refusal-pending", "empty", "unrecognized"]) {
      const row = tableRow(skill, code);
      expect(row, `table row for reason=${code}`).toBeDefined();
      expect((row ?? "").split("|").filter((c) => c.trim()).length).toBeGreaterThanOrEqual(3);
    }
    // the sixth code of the plan (`missing`) became the live-removal `recreated` NOTE
    expect(tableRow(skill, "missing")).toBeUndefined();
    expect(skill).toMatch(/recreated/);
    expect(skill).toMatch(/NOTE: [^\n]*had been removed from disk|had been removed from disk[^\n]*tell the user/);
  });

  test("every code in the save gate's list has a table row; every recovery that reloads names open_document, the two save codes name `save`", () => {
    for (const code of ALL_CODES) expect(tableRow(skill, code), `table row for reason=${code}`).toBeDefined();
    // save-incomplete stops the engine (the in-memory edit is gone): its recovery is a reload, not a retry
    for (const code of ["stale", "unknown-baseline", "refusal-pending", "empty", "unrecognized", "unconfirmed", "save-incomplete"]) {
      expect(recovery(tableRow(skill, code) ?? ""), `recovery for reason=${code}`).toMatch(/open_document/);
    }
    expect(recovery(tableRow(skill, "save-failed") ?? "")).toMatch(/`save`/);
    expect(recovery(tableRow(skill, "unrecognized") ?? "")).toMatch(/git|new path/i);
  });

  test("the save gate's reason-code list is the marker contract's eight codes, and its shared sentences equal the prose's", () => {
    expect([...saveGate.REFUSAL_REASON_CODES].sort()).toEqual(
      ["empty", "refusal-pending", "stale", "unknown-baseline", "unrecognized"],
    );
    expect([...saveGate.NOT_PERSISTED_REASON_CODES].sort()).toEqual(["save-failed", "save-incomplete", "unconfirmed"]);
    expect(saveGate.REPLAY_SAFETY_SENTENCE).toBe(REPLAY_SAFETY);
    expect(saveGate.ONLY_COPY_SENTENCE).toBe(ONLY_COPY);
    expect(RAW_CALL_STEERING).toBe(STEERING);
  });

  test("SHARED TEXT CONTRACT: replay-safety sentence on unconfirmed, save-incomplete and refusal-pending external-change", () => {
    for (const code of ["unconfirmed", "save-incomplete", "refusal-pending"]) {
      expect(recovery(tableRow(skill, code) ?? ""), `replay-safety for reason=${code}`).toContain(REPLAY_SAFETY);
    }
    // the stale and empty recoveries replay edits the session never wrote: no such sentence there
    expect(recovery(tableRow(skill, "stale") ?? "")).not.toContain(REPLAY_SAFETY);
  });

  test("SHARED TEXT CONTRACT: unknown-baseline cause=unconfirmed-save carries the replay-safety sentence, in the gate text and in the prose row", () => {
    expect(recovery(tableRow(skill, "unknown-baseline") ?? "")).toMatch(/For `cause=unconfirmed-save`: /);
    expect(recovery(tableRow(skill, "unknown-baseline") ?? "")).toContain(REPLAY_SAFETY);
    const text = saveGate.refusalMessage({ file: "a.pen", source: "save", code: "unknown-baseline", cause: "unconfirmed-save" });
    expect(text).toContain(REPLAY_SAFETY);
    expect(saveGate.refusalMessage({ file: "a.pen", source: "save", code: "unknown-baseline", cause: "capture-failed" })).not.toContain(REPLAY_SAFETY);
  });

  test("SHARED TEXT CONTRACT: only-copy sentence on save-failed and unrecognized; file-missing restores from version control first", () => {
    for (const code of ["save-failed", "unrecognized", "refusal-pending"]) {
      expect(recovery(tableRow(skill, code) ?? ""), `only-copy for reason=${code}`).toContain(ONLY_COPY);
    }
    expect(recovery(tableRow(skill, "refusal-pending") ?? "")).toContain(RESTORE_FIRST);
  });

  test("SHARED TEXT CONTRACT: the batch_design Export/TakeScreenshot steering sentence is in SKILL.md and ux-design-lead.md", () => {
    expect(skill).toContain(STEERING);
    expect(agent).toContain(STEERING);
  });

  test("the gate flag resets per code, in the same words as the agent's gate step", () => {
    expect(skill).toMatch(/gate flag[^\n]*per code|resets? per code/i);
    expect(skill).toMatch(/a clean `save` for `save-failed` only/);
    expect(skill).toMatch(/`unconfirmed` and `save-incomplete`/);
  });

  test("get_style is named as an engine command this adapter does not expose, with the brand-token / guide page alternative", () => {
    expect(skill).toMatch(/`get_style`[^\n]*does not expose[^\n]*(brand tokens|guide\/\*\.md)/);
  });

  test("probe recipe forms: Get/Print bounds, c.problems means clipping, Print(FindEmptySpace(...))", () => {
    expect(skill).toContain("Get(id,(n,c)=>Print(n.id+' '+c.bounds.width))");
    expect(skill).toMatch(/visitor runs for the node AND every descendant, the frame first/);
    expect(skill).toMatch(/c\.problems[^\n]*clipp/i);
    expect(skill).toContain("Print(FindEmptySpace({width:50,height:50}))");
  });

  test("--auto disclosure: ~1 GB engine, up to ~5 minutes cold, long timeout or background, failed install exits 2 and leaves the adapter unchanged", () => {
    expect(skill).toMatch(/~1 GB/);
    expect(skill).toMatch(/~5 minutes/);
    expect(skill).toMatch(/(long timeout|background)/);
    expect(skill).toMatch(/exits? 2[^\n]*adapter[^\n]*unchanged/);
  });

  test("refusal-pending names its four causes (failed-write reads the document out first, then open_document) and empty also covers an unreadable memory count", () => {
    const row = tableRow(skill, "refusal-pending") ?? "";
    for (const cause of ["external-change", "file-missing", "restart", "failed-write"]) expect(row).toContain(cause);
    expect(recovery(row)).toMatch(/For `failed-write`: read the in-memory document out FIRST, then `open_document` the file\./);
    // the failed-write cause text comes from the gate itself: the only-copy sentence, then open_document
    const text = saveGate.refusalMessage({ file: "a.pen", source: "save", code: "refusal-pending", restart: "failed-write" });
    expect(text).toContain(ONLY_COPY);
    expect(text.indexOf(ONLY_COPY)).toBeLessThan(text.indexOf("call open_document"));
    expect(tableRow(skill, "empty") ?? "").toMatch(/unreadable|cannot be read|unprobe/i);
  });

  test("reason=empty has two recoveries matching the adapter: empty document re-opens the file, unreadable count retries then opens a NEW path", () => {
    const rec = recovery(tableRow(skill, "empty") ?? "");
    expect(rec).toMatch(/Empty document: `open_document` the same file/);
    expect(rec).toMatch(/Unreadable count: retry the call; if it keeps failing, `open_document` a NEW file path/);
    // the adapter's own unreadable-count text (the source of the second sub-case)
    const text = saveGate.refusalMessage({ file: "a.pen", source: "save", code: "empty", diskCount: 3, memoryCount: null });
    expect(text).toContain("retry the call; if it keeps failing, open_document a new file path");
  });

  test("NOT PERSISTED: codes are documented with a recovery; save-failed never says to open_document", () => {
    expect(skill).toContain("NOT PERSISTED:");
    for (const code of ["save-failed", "unconfirmed", "save-incomplete"]) {
      const row = tableRow(skill, code);
      expect(row, `table row for reason=${code}`).toBeDefined();
      expect((row ?? "").split("|").filter((c) => c.trim()).length).toBeGreaterThanOrEqual(3);
    }
    expect(recovery(tableRow(skill, "save-failed") ?? "")).toMatch(/do NOT[^|]*open_document/);
    expect(recovery(tableRow(skill, "save-failed") ?? "")).toMatch(/`save`/);
    expect(recovery(tableRow(skill, "unconfirmed") ?? "")).toMatch(/open_document/);
  });

  test("the marker is on line 1 of the TOOL RESULT (and mirrored on stderr), and a refusal pending or unsaved edit marks exports", () => {
    expect(skill).toMatch(/first line of (a refusal|the (tool )?result)[^\n]*\[reason=<code>\]/);
    expect(skill).toMatch(/adapter writes the same marker to its stderr/);
    expect(skill).toMatch(/prefixed `WARNING: rendered from unsaved memory, not the file on disk`/);
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

  test("triage never prints the registered environment (no `claude mcp get pencil` transcript dump) and names where adapter stderr lives and the ERROR line", () => {
    const i = skill.indexOf("**Silent-drop diagnosis**");
    const section = skill.slice(i);
    // a name-only check may pipe the output through grep -o; a bare command is the leak
    expect(section).not.toMatch(/`claude mcp get pencil`/);
    for (const line of skill.split("\n")) {
      if (/claude mcp get pencil/.test(line)) expect(line, "name-only filter required").toMatch(/grep -o[E]? /);
    }
    expect(section).toMatch(/\[pencil-adapter\] ERROR:/);
    expect(section).toMatch(/Node[^.]*key[^.]*import|Node, key|names? Node/i);
    expect(skill).toMatch(/stderr[^\n]*(claude mcp list|mcp-logs|logs?|Claude Code)/i);
  });

  test("registration: --pencil-binary=<abs> argv flag replaces the PENCIL_BINARY env var, which alone is ignored", () => {
    expect(skill).toContain("--pencil-binary=");
    expect(skill).toMatch(/PENCIL_BINARY[^\n]*(ignored|WARN)/);
    expect(skill).not.toMatch(/PENCIL_BINARY[^\n]*(is trusted|honoured when set)/);
  });

  test("argv exposure sentence names the transient `claude mcp add` process, not the adapter argv", () => {
    expect(skill).toMatch(/transient `claude mcp add`/);
    expect(skill).not.toMatch(/visible in the process arguments of the registered command/);
  });

  test("existing-registration branch re-registers on a Node-floor or key-name mismatch; drift --auto installs the engine too", () => {
    const i = skill.indexOf("## Step 1");
    const step1 = skill.slice(i, skill.indexOf("## Step 2"));
    expect(step1).toMatch(/PREFERRED_NODE/);
    expect(step1).toMatch(/PENCIL_CLI_KEY/);
    expect(step1).toMatch(/re-?register/i);
    expect(skill).toMatch(/--auto[^\n]*(installs?|also installs?)[^\n]*engine|engine[^\n]*--auto/i);
  });

  test("re-registration snippet: key loaded and checked BEFORE `claude mcp remove`; user-scope-only Node probe; --pencil-binary preserved; narrow trigger", () => {
    const step1 = skill.slice(skill.indexOf("## Step 1"), skill.indexOf("## Step 2"));
    const load = step1.indexOf("doppler secrets get PENCIL_CLI_KEY");
    const remove = step1.indexOf("claude mcp remove pencil");
    expect(load).toBeGreaterThan(-1);
    expect(remove).toBeGreaterThan(load);
    expect(step1.slice(load, remove)).toMatch(/-n "\$PEN_CLI_KEY"|-z "\$PEN_CLI_KEY"/);
    // a project-scoped entry's command is never executed
    expect(step1).toMatch(/Scope: User/);
    expect(step1).toMatch(/never execute[^\n]*(project|\.mcp\.json)|(project|\.mcp\.json)[^\n]*never (run|execute)/i);
    // the registered --pencil-binary= flag survives the re-registration, but is extracted ONLY inside the
    // user-scope branch (a project-scoped .mcp.json flag must never reach the trusted user registration)
    const code = step1.split("\n").map((l) => l.replace(/^\s*#.*$/, "").replace(/\s+#.*$/, "")).join("\n");
    const branch = code.indexOf('if [[ "$scope" == "Scope: User" ]]; then');
    const elseAt = code.indexOf("\n  else\n", branch);
    const extract = code.search(/^\s*pencil_binary_flag=\$\(.*grep -oE -- '--pencil-binary=\[\^ \]\+'/m);
    expect(branch).toBeGreaterThan(-1);
    expect(extract, "flag extraction present").toBeGreaterThan(-1);
    expect(extract).toBeGreaterThan(branch);
    expect(extract).toBeLessThan(elseAt);
    // exactly one extraction, and the empty initialiser precedes the branch
    expect(code.match(/pencil_binary_flag=\$\(/g)).toHaveLength(1);
    expect(code.indexOf('pencil_binary_flag=""')).toBeLessThan(branch);
    // not for a Node PATH difference, not for a working deprecated key name
    expect(step1).not.toMatch(/"\$registered_node" != "\$PREFERRED_NODE"/);
    expect(step1).toMatch(/below 22\.19|node_status[^\n]*old/);
    // the outdated note is only for a headless preferred mode
    expect(step1).toMatch(/PREFERRED_MODE" == "headless_cli" && "\$needs_rereg" == "true"|"\$PREFERRED_MODE" == "headless_cli"[^\n]*needs_rereg/);
  });

  test("load fidelity: open_document fails when fewer top-level nodes load than the file holds (any drop)", () => {
    expect(skill).toMatch(/fewer top-level node/i);
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
    expect(section).toMatch(/commit an empty placeholder/i);
  });

  test("states the one-writer rule with the Desktop caveat, the read auto-save note and the snapshot note", () => {
    expect(skill).toMatch(/one writer per file/i);
    expect(skill).toMatch(/Pencil Desktop[^\n]*(writer|same file)|(writer|same file)[^\n]*Pencil Desktop/i);
    expect(skill).toMatch(/batch_design[^\n]*auto-save|auto-save[^\n]*batch_design/i);
    expect(skill).toMatch(/copy the `\.pen` aside first/);
  });

  test("a read through batch_design is refused under either marker", () => {
    expect(skill).toMatch(/Reads through `batch_design` also auto-save[^\n]*(NOT PERSISTED|REFUSED)[^\n]*(NOT PERSISTED|REFUSED)/);
  });
});

describe("ux-design-lead.md", () => {
  test("headless guidance goes through read_skill and snapshot_layout is not used headless", () => {
    expect(agent).toContain("read_skill");
    expect(headlessOffenders(agent)).toEqual([]);
  });

  test("post-save hard gate: node -e with sha256, size, children, changed hash, both markers", () => {
    expect(agent).toContain("# pre-edit-sha256");
    expect(agent).toContain("# post-save-gate");
    const gate = agent.slice(agent.indexOf("# post-save-gate"));
    expect(gate).toMatch(/sha256/);
    expect(gate).toMatch(/128/);
    expect(gate).toMatch(/children/);
    expect(agent).toMatch(/REFUSED save:/);
    expect(agent).toMatch(/NOT PERSISTED:/);
  });

  test("the gate flag means an UNRESOLVED unpersisted state, reset by open_document plus a clean replay", () => {
    const i = agent.indexOf("**Post-save verification (HARD GATE).**");
    expect(i).toBeGreaterThan(-1);
    const step = agent.slice(i, agent.indexOf("\n3. **Export", i));
    expect(step).toMatch(/unresolved/i);
    expect(step).toMatch(/reset[^.]*0|back to `?0/i);
    expect(step).toMatch(/open_document/);
    expect(step).toMatch(/replay/i);
    expect(step).toMatch(/REFUSED save:[^.]*NOT PERSISTED:|NOT PERSISTED:[^.]*REFUSED save:/);
  });

  test("gate reset rule is code-aware: open_document + replay for seven reload codes, a clean `save` for save-failed only, a retry or a new path for an unreadable empty count", () => {
    const i = agent.indexOf("**Post-save verification (HARD GATE).**");
    const step = agent.slice(i, agent.indexOf("\n3. **Export", i));
    // the seven reload codes named together, in the gate's order, then the one save code
    expect(step).toMatch(
      /for `stale`, `unknown-baseline`, `refusal-pending`, `empty` \([^)]*\), `unrecognized`, `unconfirmed` and `save-incomplete`/,
    );
    expect(step).toMatch(/`unconfirmed` and `save-incomplete`[^;]*; a clean `save`[^;]*for `save-failed` only/);
    expect(step).toMatch(/only when the recovery named for the code has completed/);
    // empty has two sub-cases: an unreadable count retries or opens a NEW path (it never re-opens the same file)
    expect(step).toMatch(/`empty` with an unreadable in-memory count, a retried call[^;]*NEW file path/);
    // the gate's failure text itself is code-aware
    const gate = agent.slice(agent.indexOf("# post-save-gate"), agent.indexOf("```", agent.indexOf("# post-save-gate")));
    expect(gate).toMatch(/save-failed/);
    expect(gate).toMatch(/open_document/);
  });

  test("after a recovery open_document, step 4 (PRE_SHA) is re-run before the gate; an open that could not record a baseline means a new path", () => {
    expect(agent).toMatch(/If it is NOT present and a replay is needed, re-run this step 4 right after the reload and before replaying: `PRE_SHA` must describe the file as the recovery reloaded it/);
    // the other branch keeps the ORIGINAL hash: re-running step 4 after the edit is already on disk would hide it
    expect(agent).toMatch(/If it IS already present[^.]*KEEP the original `PRE_SHA` and skip the replay: re-running step 4 would fold the edit into `PRE_SHA`/);
    expect(agent).toMatch(/warns that it could not record a baseline for the file, stop and use a new path/);
  });

  test("SHARED TEXT CONTRACT: the replay step checks whether the edit is already present", () => {
    expect(agent).toContain(REPLAY_SAFETY);
  });

  test("the agent-reported residual (ruling 5): REFUSED is agent-reported and a skipped replay is undetectable from the file", () => {
    expect(agent).toMatch(/agent-reported/i);
    expect(agent).toMatch(/skipped replay[^.]*(undetectable|cannot be detected|not detectable)[^.]*unless[^.]*(step 4|PRE_SHA)[^.]*re-run[^.]*recovery that needed a replay/i);
  });

  test("step 3.2 commits the first marker line verbatim into the wireframe summary for a recovered session", () => {
    expect(agent).toMatch(/first (marker )?line[^\n]*(REFUSED save:|marker)[^\n]*(summary|commit)|REFUSED save:[^\n]*first (marker )?line[^\n]*(summary|commit)/i);
    expect(agent).toMatch(/recovered/i);
  });

  test("relays the Node floor message, runs check_deps.sh when tools are missing, and does not claim Node is guaranteed", () => {
    expect(agent).toMatch(/required 22\.19\.0\)[^\n]*relay that message to the user verbatim/);
    expect(agent).toMatch(/first run `bash "\$\{CLAUDE_PLUGIN_ROOT\}\/skills\/pencil-setup\/scripts\/check_deps\.sh"`[^\n]*relay its printed output to the user verbatim/);
    expect(agent).not.toMatch(/Node 22\.19 is guaranteed/);
  });

  test("export naming: {nodeId}.{format} for png/jpeg/webp, pdf combines into export.pdf, no rename", () => {
    expect(agent).toMatch(/does not rename|no longer renames/i);
    expect(agent).toContain("{nodeId}.{format}");
    expect(agent).toContain("export.pdf");
  });

  test("the pre-open snapshot uses node, not GNU stat/sha256sum", () => {
    expect(agent).not.toMatch(/stat -c/);
    expect(agent).not.toMatch(/sha256sum/);
  });

  test("style-guide step does not promise loadable archetypes; layout audit uses Get/Print and c.problems", () => {
    expect(agent).not.toMatch(/index of guides and style archetypes/);
    expect(agent).toMatch(/cannot be loaded headless/i);
    expect(agent).toContain("Get(id,(n,c)=>Print(n.id+' '+c.bounds.width))");
    expect(agent).toMatch(/visitor runs for the node AND every descendant, the frame first/);
    expect(agent).toMatch(/`c\.problems` visitor for a node's clipping/);
    expect(agent).not.toMatch(/c\.problems[^\n]*layout problems/);
  });

  test("the open guard needs a tracked file, and a load that drops nodes is a refused open", () => {
    expect(agent).toMatch(/commit an empty placeholder first/i);
    expect(agent).toMatch(/fewer top-level node/i);
  });

  test("the explicit save tool refusal does not echo operations", () => {
    expect(agent).toMatch(/explicit `save`[^\n]*(does not|never) echo/i);
  });

  test("keeps the Desktop/IDE wording for style-guide and guidelines tools", () => {
    expect(agent).toMatch(/Desktop\/IDE/);
  });
});

describe("other pencil prose pointers", () => {
  const files = [BRAINSTORM_PATH, PLAN_PATH, WORKSHOP_PATH];
  for (const f of files) {
    test(`${f} does not name the retired package, the retired key name or a pen login path`, () => {
      const t = read(f);
      expect(t).not.toContain("@pencil.dev/cli");
      expect(t).not.toContain("PENCIL_CLI_KEY");
      expect(t).not.toMatch(/pen login/);
    });
  }

  test("brainstorm-brand-workshop case pattern matches @pen.dev/cli", () => {
    expect(read(WORKSHOP_PATH)).toContain("*@pen.dev/cli*");
  });

  test("brand workshop gates its first commit on a node check of size and children, not GNU stat", () => {
    expect(workshop).not.toMatch(/stat -c/);
    expect(workshop).toMatch(/node -e/);
    expect(workshop).toMatch(/children/);
    expect(workshop).toMatch(/post-save-gate/);
  });

  test("brainstorm and plan point at pencil-setup/SKILL.md", () => {
    expect(read(BRAINSTORM_PATH)).toContain("pencil-setup/SKILL.md");
    expect(read(PLAN_PATH)).toContain("pencil-setup/SKILL.md");
  });
});
