// Support-persona scoping constants (feat-wire-concierge-support-chat, Phase 3;
// ADR-113). Mirrors `routine-authoring-directive.ts`: a TRUSTED server-side
// system-prompt append, plus the tool/skill allowlist the dispatch path pins for
// `persona: "support"`.
//
// The support Concierge answers "how do I…" / navigation questions for end users
// from the curated product-help corpus. It is NOT the 95-skill engineering
// surface. Three enforcement layers (all wired on the support dispatch path):
//   1. SDK-native `Options.skills = SUPPORT_SKILLS_OPTION` — the PRIMARY lever
//      (sdk.d.ts:1867). Only kb-search is loaded into the main-session prompt;
//      every other skill is hidden from the model's context.
//   2. `createCanUseTool` default-deny — defense-in-depth for a model that emits
//      a non-loaded skill anyway: a `Skill` call for anything ∉ the allowlist
//      denies with a user-relayable message (NOT a silent removal — ADR-070).
//   3. `SUPPORT_EXTRA_DISALLOWED_TOOLS` in `disallowedTools` — hard-remove the
//      write/fan-out surface (Edit/Write/…/Task/Agent). Bash is KEPT because
//      kb-search shells out via the read-only safe-bash gate.
//
// The directive lives ONLY in the trusted system-prompt channel (server append),
// never in `context.content`. It MUST NOT contain any gate-bypass phrasing.

/**
 * The single support-allowed skill set. `help` is deliberately EXCLUDED — it
 * enumerates the full engineering command surface, which is not support-
 * appropriate. New plugin skills are safe-by-default because the gate is
 * default-deny (a skill is allowed only if it is IN this set).
 */
export const SUPPORT_SKILL_ALLOWLIST: ReadonlySet<string> = new Set(["kb-search"]);

/**
 * SDK-native `Options.skills` value for the support path (sdk.d.ts:1867 —
 * `skills?: string[] | 'all'`). When set, only these skills are loaded into the
 * main-session system prompt; unlisted skills are hidden from the model.
 * Derived from the allowlist so the two layers cannot drift.
 */
export const SUPPORT_SKILLS_OPTION: readonly string[] = Array.from(
  SUPPORT_SKILL_ALLOWLIST,
);

/**
 * Tools hard-removed from the model's context on the support path
 * (`disallowedTools`). Edit/Write/MultiEdit/NotebookEdit are removed because
 * under the support `cwd = getPluginPath()` a write to a path UNDER the plugin
 * root would pass workspace-containment and be allowed — the "read-only surface
 * that isn't" leak. Task/Agent are removed so a support chat cannot fan out into
 * engineering subagents. Bash is intentionally NOT here: `kb-search` shells out
 * (grep, kb-search-cache.sh) behind the existing read-only safe-bash gate, so
 * removing Bash would disable the only real support capability. WebSearch/
 * WebFetch are already in the canonical disallowed list.
 *
 * ADR-070 reconciliation: this silent `disallowedTools` removal is acceptable —
 * and NOT the additive-hint-only violation ADR-070 forbids — because Edit/Write/
 * Task/Agent are tools a support user NEVER legitimately needs, so their removal
 * breaks no valid flow.
 */
export const SUPPORT_EXTRA_DISALLOWED_TOOLS: readonly string[] = [
  "Edit",
  "Write",
  "MultiEdit",
  "NotebookEdit",
  "Task",
  "Agent",
];

/**
 * Normalize a model-controlled `.skill` field to its bare form for the allowlist
 * check. The field can arrive `soleur:`-prefixed; strip ONLY an anchored leading
 * `soleur:` (mirrors `context-queries-hook.ts` Gate #1 / `phase-surface-hook.ts`)
 * so `soleur:kb-search` does not false-deny the happy path, while a mid-string
 * occurrence (`x-soleur:kb-search`) is left intact.
 */
export function normalizeSkillName(skill: string): string {
  if (typeof skill !== "string" || skill.length === 0) return "";
  return skill.replace(/^soleur:/, "");
}

/**
 * Whether an invoked skill name (bare or FQN) is support-allowed. Used by the
 * `createCanUseTool` Skill branch when `persona === "support"`.
 */
export function isSupportAllowedSkill(skill: string): boolean {
  return SUPPORT_SKILL_ALLOWLIST.has(normalizeSkillName(skill));
}

export const SUPPORT_SYSTEM_DIRECTIVE = `## Soleur Support mode

You are **Soleur Support** — an in-app help assistant for an end user of the Soleur web app. Answer "how do I…" and "where is…" questions about using the app, grounded in the product-help knowledge base.

**Answer from the knowledge base.** Use the \`kb-search\` skill to find the relevant product-help article, then answer in plain language and link the user to the right place in the app. If \`kb-search\` returns nothing relevant, say so honestly and point the user to their **Knowledge Base** in the left sidebar — never invent an answer.

**Stay in scope.** You are app-help support only. You **never edit code, never run engineering workflows** (plan / work / ship / deploy / one-shot / review / drain), and **never touch a repository**. The only skill available to you is \`kb-search\`. If the user asks you to build, fix, deploy, or change something in their project, explain that this chat is for app help and point them to **"Ask an agent"** (the Command Center) for engineering work.

**Be honest.** You are an AI assistant and may be wrong. Do not claim to have taken an action you cannot take. Keep answers short and specific to the user's question.`;
