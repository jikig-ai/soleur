#!/usr/bin/env bun
/**
 * Soleur's OpenCode plugin — the OpenCode peer of `hooks/hooks.json`.
 *
 * LOAD SHAPE (measured — measurement §6.6 arm A). OpenCode 2.0.32 requires a **default**
 * export carrying an `id` and a `setup` function. The V1 named-export form
 * (`export const Soleur = async (ctx) => ({ hooks })`) is rejected outright:
 *   `Plugin must export a default definition with an id and an effect or setup function.`
 * A plain object importing only `node:` builtins is enough to load (arms B/C), so this
 * module deliberately imports nothing from `@opencode/plugin` and carries no runtime
 * dependency. That is also why the pin task resolves to "nothing to pin": there is no vendor
 * package on the module's import graph (measurement §6.6, "Package identity").
 *
 * WHY THIS FILE IS NOT GENERATED. It holds dispatch logic that has to be unit-tested by
 * import, and a generator-owned template string cannot be imported. The generator therefore
 * treats it as a **source file** (`ADAPTER_SOURCE_FILES` in `scripts/sync-opencode-adapter.ts`):
 * it asserts the file exists, never emits it, and never deletes it. The installer copies it
 * into `<configdir>/plugins/` with the `__SOLEUR_PLUGIN_ROOT__` token resolved.
 *
 * WHERE THE GUARDS BIND, AND WHY NOT SOMEWHERE ELSE (measurement §12). The Bash guards bind at
 * `ctx.permission.hook("evaluate")`, whose event carries the tool as `action` and the command
 * as `resources[0]`, with a **mutable** `effect: allow | ask | deny`. Measured live:
 *
 *   - `effect = "deny"` + `message` ⇒ the tool ends `{status:"error", error:{type:
 *     "permission.rejected", message}}`, it never runs, and the model reads the message.
 *   - `effect = "ask"` + `message` ⇒ the tool stays `running` awaiting a decision. A real
 *     prompt, so a guard's `ask` is delivered as an `ask` and NOT downgraded to a refusal.
 *
 * `ctx.tool.hook("execute.before")` is deliberately **not** bound. It fires *before* the
 * permission hook, and its only refusal channel is a thrown error, so binding it would let a
 * `deny`-or-`ask` both collapse into a throw and preempt the real ask behind it. It is a fine
 * surface (a throw there was measured to block the call and reach the model) and simply the
 * wrong one for a two-valued guard.
 *
 * WHAT IT CANNOT DO (measurement §6.6). Every V2 hook surface communicates only by mutating
 * the event object it is handed, and `ctx.event.subscribe` is a one-way iterator with no
 * return channel. No hook can defer a stop, force a continuation, or veto a completion.
 * The completion marker is therefore observed, never enforced.
 */

import { spawnSync } from "node:child_process";
import { appendFileSync, existsSync, lstatSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";

/** Replaced in place by `install-opencode-adapter.ts` with the checkout path. */
const INSTALLED_ROOT = "__SOLEUR_PLUGIN_ROOT__";

/**
 * Where the guard scripts live.
 *
 * In an installed copy the installer has already replaced `INSTALLED_ROOT` with the checkout
 * path, and this module sits at `<configdir>/plugins/`, so only the token knows where the
 * checkout is. In an unresolved copy — the committed tree, a test run — the module still sits
 * at `<checkout>/opencode/`, so its own parent IS the checkout. The two are told apart by the
 * plugin identity file (`.claude-plugin/plugin.json`), which only a checkout carries — the
 * repo's established root-resolution marker (devin/INSTRUCTIONS.md §Detection). (A module that
 * landed at `<configdir>/plugins/` still carrying the literal token would resolve to the token
 * itself and every guard spawn would fail loudly, which is the desired failure.) The env
 * override exists so a test or a local run can point at a checkout explicitly.
 */
function resolvePluginRoot(): string {
  const override = process.env["SOLEUR_OPENCODE_PLUGIN_ROOT"];
  if (override !== undefined && override !== "") return override;
  const sibling = resolve(import.meta.dir, "..");
  return existsSync(join(sibling, ".claude-plugin", "plugin.json")) ? sibling : INSTALLED_ROOT;
}

export const PLUGIN_ROOT = resolvePluginRoot();

/**
 * OpenCode tool wire name → the Claude Code tool name the guard scripts decide on.
 *
 * `shell` is the measured wire name of the shell tool on 2.0.32 (§12.1): a live
 * `tool.execute.before` carried `tool="shell"` and a live `permission.evaluate` carried
 * `action="shell"`. `bash` is kept as well because the permission-key table in the V1 docs
 * names the key `bash`; if the wire name ever tracks that table, the mapping still holds.
 * An unmapped name passes through unchanged, and the guards decline a name that is not `Bash`.
 */
const CLAUDE_TOOL_NAME: Readonly<Record<string, string>> = {
  shell: "Bash",
  bash: "Bash",
  edit: "Edit",
  write: "Write",
  read: "Read",
  grep: "Grep",
  glob: "Glob",
  apply_patch: "Write",
  skill: "Skill",
  webfetch: "WebFetch",
  websearch: "WebSearch",
  question: "AskUserQuestion",
  task: "Task",
};

/**
 * Guards that decide a shell call, in `hooks.json` registration order. The first guard to
 * return a decision ends the walk, matching the Claude registrations, where an earlier hook's
 * `deny` is already final.
 */
export const BASH_GUARDS: readonly { id: string; script: string }[] = [
  { id: "browser-snapshot-credential-guard", script: "hooks/browser-snapshot-credential-guard.sh" },
  { id: "destructive-command-guard", script: "hooks/destructive-command-guard.sh" },
];

/** Wall-clock bound for one guard spawn. `hooks.json` registers the same guards at 10 s. */
const GUARD_TIMEOUT_MS = 12_000;

export interface ScriptRun {
  status: number | null;
  stdout: string;
  stderr: string;
}

export type ScriptRunner = (script: string, stdin: string, cwd: string) => ScriptRun;

/** Run a hook script the way the harness does: JSON envelope in on stdin, JSON out on stdout. */
export function runScript(script: string, stdin: string, cwd: string): ScriptRun {
  const result = spawnSync("bash", [script], {
    input: stdin,
    cwd,
    encoding: "utf8",
    timeout: GUARD_TIMEOUT_MS,
    maxBuffer: 4 * 1024 * 1024,
    env: { ...process.env, CLAUDE_PROJECT_DIR: cwd },
  });
  return {
    status: result.status,
    stdout: typeof result.stdout === "string" ? result.stdout : "",
    stderr: typeof result.stderr === "string" ? result.stderr : "",
  };
}

/** Last parseable JSON object in a stream — a script may print a diagnostic line first. */
function lastJsonObject(text: string): Record<string, unknown> | undefined {
  const whole = text.trim();
  if (whole !== "") {
    try {
      const parsed: unknown = JSON.parse(whole);
      if (parsed !== null && typeof parsed === "object" && !Array.isArray(parsed)) {
        return parsed as Record<string, unknown>;
      }
    } catch {
      // fall through to the line scan
    }
  }
  const lines = text.split("\n");
  for (let i = lines.length - 1; i >= 0; i -= 1) {
    const line = lines[i].trim();
    if (!line.startsWith("{")) continue;
    try {
      const parsed: unknown = JSON.parse(line);
      if (parsed !== null && typeof parsed === "object" && !Array.isArray(parsed)) {
        return parsed as Record<string, unknown>;
      }
    } catch {
      // keep scanning
    }
  }
  return undefined;
}

function objectField(source: Record<string, unknown> | undefined, key: string): Record<string, unknown> | undefined {
  const value = source?.[key];
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined;
}

export function claudeToolName(tool: string): string {
  return CLAUDE_TOOL_NAME[tool] ?? tool;
}

/**
 * The Claude PreToolUse envelope the guards parse. Returns `undefined` for any tool the guards
 * cannot decide, so no process is spawned for a call no guard would look at. `tool_input` is
 * passed through whole rather than pre-extracted: the destructive guard's documented behavior
 * on an absent or non-string `command` is to **ask**, and pre-extracting here would silently
 * turn that ask into an allow.
 */
export function guardEnvelope(tool: string, input: unknown, cwd: string): string | undefined {
  const name = claudeToolName(tool);
  if (name !== "Bash") return undefined;
  const toolInput = input !== null && typeof input === "object" && !Array.isArray(input) ? input : {};
  return JSON.stringify({ hook_event_name: "PreToolUse", tool_name: name, tool_input: toolInput, cwd });
}

export interface GuardDecision {
  guard: string;
  decision: "deny" | "ask";
  reason: string;
}

/** Read `hookSpecificOutput.permissionDecision` out of a guard's stdout. No decision → undefined. */
export function parseGuardOutput(stdout: string): { decision: "deny" | "ask"; reason: string } | undefined {
  const specific = objectField(lastJsonObject(stdout), "hookSpecificOutput");
  const decision = specific?.["permissionDecision"];
  if (decision !== "deny" && decision !== "ask") return undefined;
  const reason = specific?.["permissionDecisionReason"];
  return { decision, reason: typeof reason === "string" ? reason : "" };
}

/**
 * Run the Bash guards in order for a tool call; the first decision wins. `undefined` means
 * every guard declined and the call proceeds unchanged.
 */
export function decideBash(
  tool: string,
  input: unknown,
  cwd: string,
  runner: ScriptRunner = runScript,
  pluginRoot: string = PLUGIN_ROOT,
): GuardDecision | undefined {
  const envelope = guardEnvelope(tool, input, cwd);
  if (envelope === undefined) return undefined;
  for (const guard of BASH_GUARDS) {
    const parsed = parseGuardOutput(runner(join(pluginRoot, guard.script), envelope, cwd).stdout);
    if (parsed !== undefined) return { guard: guard.id, ...parsed };
  }
  return undefined;
}

/**
 * The command a `permission.evaluate` event describes.
 *
 * Measured shape (§12.2): a shell call arrives as `action: "shell"`,
 * `resources: ["echo hello-from-probe"]` — one string that IS the command. Joining rather than
 * indexing is deliberate: it cannot lose text if a shell call ever arrives with more than one
 * resource, and it is identical to indexing on the measured shape.
 */
export function permissionCommand(resources: readonly unknown[]): string {
  return resources.filter((resource): resource is string => typeof resource === "string").join("\n");
}

/**
 * Decide a `permission.evaluate` event. Non-shell actions cost nothing: the tool-name gate
 * inside `guardEnvelope` returns before any process is spawned.
 */
export function decidePermission(
  action: unknown,
  resources: readonly unknown[],
  cwd: string,
  runner: ScriptRunner = runScript,
  pluginRoot: string = PLUGIN_ROOT,
): GuardDecision | undefined {
  if (typeof action !== "string") return undefined;
  return decideBash(action, { command: permissionCommand(resources) }, cwd, runner, pluginRoot);
}

/**
 * The message the decision carries. The guard's own reason is already the operator-facing text
 * (`This command was NOT run. …` / `Stop and tell the person …`), so it is passed through whole
 * and only prefixed with which guard spoke — never rewritten, because the reason contains the
 * escalation instructions a person needs.
 */
export function decisionMessage(decision: GuardDecision): string {
  const head = `Soleur's ${decision.guard}:`;
  return decision.reason === "" ? head : `${head} ${decision.reason}`;
}

/** ADR-094: the corpus's frontmatter is stripped before injection. */
export function stripFrontmatter(text: string): string {
  return text.replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/, "");
}

/** A regular file that is not a symlink — the rules loader's prompt-injection defense, kept. */
function isRealFile(path: string): boolean {
  try {
    return lstatSync(path).isFile();
  } catch {
    return false;
  }
}

function additionalContext(stdout: string): string | undefined {
  const value = objectField(lastJsonObject(stdout), "hookSpecificOutput")?.["additionalContext"];
  return typeof value === "string" && value !== "" ? value : undefined;
}

/**
 * The rule corpus for a session, reuse-first.
 *
 * Where the repository carries the canonical loader (`.claude/hooks/session-rules-loader.sh` —
 * ADR-151's frontmatter strip, over-strip guard, symlink rejection, manifest and stamps), it is
 * invoked with a SessionStart envelope and its `additionalContext` is used verbatim. Otherwise
 * the corpus is read directly, keeping the two properties that must never be missing: a symlink
 * is refused, and frontmatter is stripped. Everything the loader adds on top of that (the
 * manifest, the tmpfs alarm block, the SOC 2 session-context snapshot) is not reproduced, and
 * the disposition ledger says so.
 */
export function rulesInjection(cwd: string, runner: ScriptRunner = runScript): string | undefined {
  const loader = join(cwd, ".claude", "hooks", "session-rules-loader.sh");
  if (isRealFile(loader)) {
    const envelope = JSON.stringify({ hook_event_name: "SessionStart", source: "startup", cwd });
    const injected = additionalContext(runner(loader, envelope, cwd).stdout);
    if (injected !== undefined) return injected;
  }
  const corpus = join(cwd, "AGENTS.rules.md");
  if (isRealFile(corpus)) return stripFrontmatter(readFileSync(corpus, "utf8"));
  return undefined;
}

/**
 * The post-compaction re-read directive. `compaction-state.sh` cannot be reused: it counts
 * `compact_boundary` records in a Claude Code transcript, which this harness has no equivalent
 * of. The directive is reproduced; the window bookkeeping is not (disposition: `downgraded`).
 */
export function compactionDirective(): string {
  return [
    "[soleur] A checkpoint summary has replaced part of this conversation.",
    "Re-read the rule corpus (`AGENTS.rules.md`, or the copy injected at session start) before",
    "continuing: a summary compresses rule bodies, and a rule you cannot quote is a rule you",
    "cannot follow.",
  ].join(" ");
}

/** Optional observation target. Unset means the completion observer writes nothing. */
const EVENT_LOG = process.env["SOLEUR_OPENCODE_EVENT_LOG"];

export interface PermissionEvaluateEvent {
  readonly action?: unknown;
  readonly resources?: readonly unknown[];
  readonly agent?: unknown;
  effect: "allow" | "ask" | "deny";
  message?: string;
}

export interface SetupContext {
  location?: { directory?: string };
  permission: {
    hook(
      name: "evaluate",
      handler: (event: PermissionEvaluateEvent) => Promise<void> | void,
    ): Promise<unknown>;
  };
  session: {
    hook(
      name: string,
      handler: (event: Record<string, unknown>) => Promise<void> | void,
      options?: { providerID?: string },
    ): Promise<unknown>;
  };
  event: { subscribe(options?: { signal?: AbortSignal }): AsyncIterable<{ type?: string; data?: unknown }> };
}

/** Session-scoped injection state: inject once, then again after a compaction. */
interface SessionState {
  injected: boolean;
  compacted: boolean;
}

/**
 * Build `setup`. The hooks are returned bound to injected collaborators so the unit tests can
 * drive them with a fake context and a fake script runner.
 */
export function createSetup(
  runner: ScriptRunner = runScript,
  pluginRoot: string = PLUGIN_ROOT,
  write: (line: string) => void = (line) => {
    if (EVENT_LOG !== undefined) appendFileSync(EVENT_LOG, `${line}\n`);
  },
): (ctx: SetupContext) => Promise<void> {
  const sessions = new Map<string, SessionState>();

  return async function setup(ctx: SetupContext): Promise<void> {
    const sessionCwd = ctx.location?.directory ?? process.cwd();

    // The only blocking surface bound here. `effect` is overwritten, never merged: the event
    // arrives with the permission ruleset's own verdict, and a guard's decision replaces it.
    await ctx.permission.hook("evaluate", (event) => {
      const decision = decidePermission(event.action, event.resources ?? [], sessionCwd, runner, pluginRoot);
      if (decision === undefined) return;
      event.effect = decision.decision;
      event.message = decisionMessage(decision);
    });

    await ctx.session.hook("context", (event) => {
      const cwd = typeof event["cwd"] === "string" ? event["cwd"] : sessionCwd;
      const sessionID = typeof event["sessionID"] === "string" ? event["sessionID"] : "unknown";
      const state = sessions.get(sessionID) ?? { injected: false, compacted: false };
      if (state.injected && !state.compacted) return;
      const system = event["system"];
      if (!Array.isArray(system)) return;
      // The compaction hook's own `system` reaches only the summarization call, so the re-read
      // directive has to ride the next real request — which is this one (measurement §12.3).
      if (state.compacted) system.push({ type: "text", text: compactionDirective() });
      const rules = rulesInjection(cwd, runner);
      if (rules !== undefined) system.push({ type: "text", text: rules });
      sessions.set(sessionID, { injected: true, compacted: false });
    });

    await ctx.session.hook("compaction", (event) => {
      const sessionID = typeof event["sessionID"] === "string" ? event["sessionID"] : "unknown";
      const state = sessions.get(sessionID) ?? { injected: false, compacted: false };
      sessions.set(sessionID, { ...state, compacted: true });
    });

    // Observation only, and it must stay that way: §6.6 measured no return channel, so an idle
    // signal can be noticed and acted on by nothing. Off unless SOLEUR_OPENCODE_EVENT_LOG names
    // a path.
    void (async () => {
      try {
        for await (const event of ctx.event.subscribe()) {
          const type = typeof event?.type === "string" ? event.type : "unknown";
          if (type.startsWith("session.")) write(`soleur-opencode\t${type}\tadvisory-completion-marker-not-enforceable`);
        }
      } catch (error) {
        write(`soleur-opencode\tevent-stream-error\t${String(error)}`);
      }
    })();
  };
}

/**
 * The module's default export — a static object, because the loader reads `id` and `setup` off
 * the default export directly.
 */
export default {
  id: "soleur",
  setup: createSetup(),
};
