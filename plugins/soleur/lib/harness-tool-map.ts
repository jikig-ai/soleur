/**
 * Tool-map coverage — every Claude Code tool an agent-read doc names has a stated
 * Codex and Devin translation (#8318, ADR-240).
 *
 * WHY A TABLE AND NOT A BLOCKLIST. #8318's original proposal was a born-blocking
 * blocklist of "bare mechanism nouns" (`Skill tool`, `Task tool`, `subagent_type`).
 * That was rejected on the AP-025 / ADR-202 posture: a list of forbidden forms cannot
 * be proven complete. This gate is the inverse and is complete by construction — an
 * ALLOWLIST over a closed vocabulary, asking one question per name: does the doc
 * corpus use it, and if so, do BOTH adapter tables translate it?
 *
 * The tables are the translation authority the plugin already ships
 * (`codex/INSTRUCTIONS.md`, `devin/INSTRUCTIONS.md` §Tools). A Codex or Devin session
 * that meets `SendMessage` in a skill body has nothing else to resolve it with, which
 * is exactly the gap #8318 names: `SendMessage` is used in `review` and `work` and had
 * a row in neither table.
 *
 * WHAT THIS GATE DOES NOT DO. It does not forbid naming a Claude tool — plugin prose
 * legitimately says "Claude: Skill tool; Grok: …". It requires only that the name be
 * translatable. And it says nothing about whether the translation is CORRECT; that is
 * a human claim, measured per row where it was measured at all.
 */

import { readFileSync } from "fs";
import { resolve } from "path";
import { PLUGIN_ROOT } from "./agent-registry";

/**
 * The closed vocabulary.
 *
 * VERIFIED 2026-09-23 against https://code.claude.com/docs/en/tools.md. Names the
 * check rejected are recorded here rather than silently dropped, because a future
 * reader will otherwise re-add them from memory:
 *   - `BashOutput` — a return value of Bash, not a tool.
 *   - `KillShell`, `TodoRead`, `TeamCreate`, `TeamDelete` — not in the inventory.
 *   - `MultiEdit` — not a tool name; `Edit` covers it. (The Codex table still LISTS
 *     it in a cell, which is harmless: cells may name more than the vocabulary does.)
 *
 * `Task` is retained deliberately although the docs now inventory the spawn tool as
 * `Agent`: this repo's own adapter prose and routing contract say "Task tool with
 * `subagent_type`" throughout, both tables already carry the `Task / Agent /
 * spawn_subagent` row, and a Codex or Devin session meeting the word still needs the
 * translation. Dropping it would narrow the gate to make a green easier, which is the
 * one move this file exists to prevent.
 *
 * STALENESS IS AN ACCEPTED RISK, recorded in ADR-240: a derived `PascalCase tool`
 * detector was cut at plan review (it needs its own false-positive list). The
 * vocabulary is refreshed when Claude Code adds tools; this comment's date is the
 * last time that happened.
 */
export const CLAUDE_CODE_TOOLS: readonly string[] = [
  "Agent",
  "Artifact",
  "AskUserQuestion",
  "Bash",
  "CronCreate",
  "CronDelete",
  "CronList",
  "Edit",
  "EndConversation",
  "EnterPlanMode",
  "EnterWorktree",
  "ExitPlanMode",
  "ExitWorktree",
  "Glob",
  "Grep",
  "ListAgents",
  "ListMcpResourcesTool",
  "LSP",
  "Monitor",
  "NotebookEdit",
  "PowerShell",
  "PushNotification",
  "Read",
  "ReadMcpResourceTool",
  "RemoteTrigger",
  "ReportFindings",
  "ScheduleWakeup",
  "SendFeedback",
  "SendMessage",
  "SendUserFile",
  "ShareOnboardingGuide",
  "Skill",
  "SubagentHandback",
  "Task",
  "TaskCreate",
  "TaskGet",
  "TaskList",
  "TaskOutput",
  "TaskStop",
  "TaskUpdate",
  "TodoWrite",
  "ToolSearch",
  "WaitForMcpServers",
  "WebFetch",
  "WebSearch",
  "Workflow",
  "Write",
] as const;

export const CODEX_INSTRUCTIONS = resolve(PLUGIN_ROOT, "codex/INSTRUCTIONS.md");
export const DEVIN_INSTRUCTIONS = resolve(PLUGIN_ROOT, "devin/INSTRUCTIONS.md");

/**
 * The names a `## Tools` table's FIRST column translates.
 *
 * A cell is a `/`-separated list of Soleur-side instruction names, sometimes with a
 * trailing qualifier: `Skill \`soleur:<name>\`` → `Skill`, `Workflow scripts` →
 * `Workflow`, `Read / Glob / Grep` → three names. Splitting on `/` and keeping each
 * part's first word is the whole parse.
 *
 * Returns an EMPTY set when the heading is absent or the table is empty, and the
 * caller's floor is what turns that into a RED — a parser that returns ∅ on a renamed
 * heading would otherwise make every coverage question vacuously true.
 */
export function parseToolsTable(md: string): Map<string, string> {
  const out = new Map<string, string>();
  const lines = md.split("\n");
  const start = lines.findIndex((l) => /^##\s+Tools\s*$/.test(l));
  if (start === -1) return out;
  for (let i = start + 1; i < lines.length; i++) {
    const line = lines[i];
    if (/^##\s+/.test(line)) break;
    if (!line.startsWith("|")) continue;
    const cells = line.split("|");
    const first = cells[1];
    if (first === undefined) continue;
    const cell = first.trim();
    if (!cell || /^-+$/.test(cell) || cell === "Soleur instruction") continue;
    // The SECOND column is the translation, and it is the thing the property is
    // about. Reading only the first column made a row with a BLANK translation
    // pass: measured, emptying the `SendMessage / ListAgents` cell in both files
    // left the gate 5 pass / 0 fail, while a Codex session meeting `SendMessage`
    // still had nothing to resolve it with — the literal gap #8318 exists to
    // close, surviving inside the gate built to close it.
    const translation = (cells[2] ?? "").trim();
    for (const part of cell.split("/")) {
      const word = part.replace(/`/g, "").trim().split(/\s+/)[0];
      if (word) out.set(word, translation);
    }
  }
  return out;
}

/** A cell that names no mechanism — blank, or a placeholder standing in for one. */
export function isEmptyTranslation(cell: string | undefined): boolean {
  if (cell === undefined) return true;
  const t = cell.trim().replace(/`/g, "");
  return t === "" || /^(?:-+|n\/?a|tbd|todo|\?+|none)$/i.test(t);
}

export function readToolsTable(path: string): Map<string, string> {
  return parseToolsTable(readFileSync(path, "utf8"));
}

/**
 * Does this doc USE the tool, as opposed to merely containing the word?
 *
 * A bare `\bWord\b` is a WORD detector, and several tool names are ordinary
 * English: measured, `Artifact` matched `**Artifact:** the feature's named
 * surface` and `Workflow` matched `## Core Workflow`, while `Read`, `Write`,
 * `Task`, `Monitor` and `Agent` match prose everywhere. That forced rows into
 * two customer-facing adapter tables for tools no Soleur doc instructs, and made
 * the gate's own failure message name a use it had not measured (AP-021).
 *
 * The direction of that error was safe — over-strict never hides a real gap —
 * but the noise is permanent, so require a tool-SHAPED context instead: the name
 * in backticks (how this corpus cites a tool), or followed by the word "tool".
 */
export function usesTool(text: string, tool: string): boolean {
  return new RegExp(String.raw`(?:\`${tool}\`|\b${tool}\s+tool\b)`).test(text);
}
