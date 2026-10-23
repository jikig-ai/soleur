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
 * `ctx.tool.hook("execute.before")` is bound **as a capture, never as a guard** (#10819). It fires
 * *before* the permission hook, and its only refusal channel is a thrown error, so a `deny`-or-`ask`
 * there would collapse into a throw and preempt the real ask behind it. What it *can* do without
 * deciding anything is publish `input.workdir`, the one value the permission event does not carry:
 * a `shell` call with `workdir=$HOME` was judged against the session directory, so `rm -rf *` was
 * allowed that the destructive guard **denies** in the directory the command asked for. The
 * permission hook consumes that capture by call key and passes it as the envelope `cwd`.
 *
 * INVARIANTS. (1) One predicate, `decidesBash`, answers "is this a call the Bash guards see" — and
 * the envelope, the capture and the consume all ask it; a second copy of that question is how a
 * wire-name change reopens the hole at one site only. (2) The capture runs for every Bash call,
 * including one with no workdir, so a lookup miss means "the tool hook did not fire" rather than
 * "no workdir". (3) A capture is never deleted on consume, so a second evaluation of the same call
 * cannot fall back to the session directory. (4) A degraded correlation is announced; a captured
 * workdir that cannot be used escalates to `ask` instead of judging somewhere the operator did not
 * ask about.
 *
 * WHAT IT CANNOT DO (measurement §6.6). Every V2 hook surface communicates only by mutating
 * the event object it is handed, and `ctx.event.subscribe` is a one-way iterator with no
 * return channel. No hook can defer a stop, force a continuation, or veto a completion.
 * The completion marker is therefore observed, never enforced.
 */

import { spawnSync } from "node:child_process";
import { appendFileSync, existsSync, lstatSync, readFileSync, realpathSync, statSync } from "node:fs";
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
 * landed at `<configdir>/plugins/` still carrying the literal token must not resolve to a
 * *relative* token: a planted `__SOLEUR_PLUGIN_ROOT__/hooks/` directory inside the session's own
 * working directory would then supply both guard scripts. It is anchored at `/` so that path
 * cannot exist, and `decideBash` turns the failed spawn into a deny naming the dead path.) The
 * env override exists so a test or a local run can point at a checkout explicitly.
 */
function resolvePluginRoot(): string {
  const override = process.env["SOLEUR_OPENCODE_PLUGIN_ROOT"];
  if (override !== undefined && override !== "") return override;
  const sibling = resolve(import.meta.dir, "..");
  return existsSync(join(sibling, ".claude-plugin", "plugin.json")) ? sibling : join("/", INSTALLED_ROOT);
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
  // The measured V2 spawn tool (§12.8): the same logical agent, named `subagent` on the wire.
  subagent: "Task",
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
  /**
   * The spawn error's code, when the process could not be started at all (`ENOENT`, `EACCES`,
   * `ENOTDIR`). `spawnSync` reports these as `status: null` with the reason only in `error`, so
   * discarding it makes an unenterable working directory indistinguishable from a moved checkout
   * and sends the operator to re-run an installer that will answer `ok`.
   */
  error?: string;
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
    ...(result.error === undefined ? {} : { error: result.error.code ?? result.error.message }),
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
 * Does a call with this wire name reach the Bash guards?
 *
 * One answer for three askers — the envelope constructor, the `execute.before` capture and the
 * `permission.evaluate` consume. Two copies of this question is the rot that would let the
 * measured wire name (`shell`) or its V1 spelling (`bash`) be handled at one site only, which is
 * silently the pre-fix behaviour: capture with no consume, or consume with no capture.
 */
export function decidesBash(tool: string): boolean {
  return claudeToolName(tool) === "Bash";
}

/**
 * The Claude PreToolUse envelope the guards parse. Returns `undefined` for any tool the guards
 * cannot decide, so no process is spawned for a call no guard would look at. `tool_input` is
 * passed through whole rather than pre-extracted: the destructive guard's documented behavior
 * on an absent or non-string `command` is to **ask**, and pre-extracting here would silently
 * turn that ask into an allow.
 */
export function guardEnvelope(tool: string, input: unknown, cwd: string): string | undefined {
  if (!decidesBash(tool)) return undefined;
  const name = claudeToolName(tool);
  const toolInput = input !== null && typeof input === "object" && !Array.isArray(input) ? input : {};
  return JSON.stringify({ hook_event_name: "PreToolUse", tool_name: name, tool_input: toolInput, cwd });
}

/**
 * What a `tool.execute.before` event said about the directory its command will start in.
 *
 * `absent` and `unusable` are deliberately different: the first is the normal case (no `workdir`
 * was supplied, so the session directory is correct), the second means the operator asked for a
 * directory this plugin cannot vouch for — and judging in the session directory instead is exactly
 * the hole #10819 reports, one order of magnitude rarer.
 */
export type WorkdirCapture =
  | { readonly kind: "absent" }
  | { readonly kind: "usable"; readonly path: string }
  | { readonly kind: "unusable"; readonly raw: string };

/**
 * Resolve the `workdir` a tool call carries. Total by construction: it never throws and never
 * returns a path it has not confirmed is a directory.
 *
 * A relative value is resolved against `baseDir` (the session directory) — measured, not assumed:
 * with the session moved to a worktree while the OpenCode process kept its launch cwd in the bare
 * checkout, `workdir: "plugins/soleur"` ran in the worktree. `realpathSync` then yields the physical
 * directory the shell's `chdir` reaches, so `path.resolve`'s lexical answer for a symlinked or
 * `..`-containing value cannot disagree with where the command actually runs.
 */
export function resolveWorkdir(input: unknown, baseDir: string): WorkdirCapture {
  if (input === null || typeof input !== "object" || Array.isArray(input)) return { kind: "absent" };
  const raw = (input as Record<string, unknown>)["workdir"];
  if (raw === undefined || raw === null) return { kind: "absent" };
  // A present but non-string value is a *shape* violation, not "no workdir was given": treating it
  // as absent would judge the call in the session directory without saying so, which is #10819's
  // silence one shape over. `null`/absent stay the normal case because a runtime may send either.
  if (typeof raw !== "string") return { kind: "unusable", raw: clip(String(raw)) };
  if (raw === "") return { kind: "absent" };
  try {
    // `resolve` already returns an absolute argument unchanged, and `statSync` throws for a missing
    // path, so neither `isAbsolute` nor `existsSync` earns a branch here.
    const absolute = resolve(baseDir, raw);
    if (!statSync(absolute).isDirectory()) return { kind: "unusable", raw: clip(raw) };
    return { kind: "usable", path: realpathSync(absolute) };
  } catch {
    return { kind: "unusable", raw: clip(raw) };
  }
}

/**
 * Clip wire-controlled text to a length an operator can read, after stripping what would forge a
 * record: `field()` removes the control characters, and the bound removes a megabyte of it.
 */
export function clip(value: string, max = 160): string {
  const flat = value.replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/g, "_");
  return flat.length > max ? `${flat.slice(0, max)}…` : flat;
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

/** The guard id a failed guard *run* is reported under — never a guard that examined and declined. */
export const GUARD_RUN_FAILURE = "guard-did-not-run";

/**
 * Run the Bash guards in order for a tool call; the first decision wins. `undefined` means
 * every guard **ran and declined**, and the call proceeds unchanged.
 *
 * A run that did not produce a decision is not the same event. Both guard scripts print a
 * decision or nothing and exit 0 in every path, so a non-zero status (missing or moved checkout,
 * an unresolved `__SOLEUR_PLUGIN_ROOT__` → 127, a spawn error, the 12 s timeout → `null`) means
 * the guard never spoke. That is a **deny**, with the dead path in the reason: the alternative is
 * a silent fail-open of the credential and destructive-command guards — a support failure dressed
 * as a feature, and the exact class this adapter's spec names as its load-bearing risk. Measured:
 * `decideBash("shell", {command:"rm -rf /"}, …)` returned `undefined` for a `{status:127}` runner
 * before this branch (10-seat review, 2026-10-19).
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
    const script = join(pluginRoot, guard.script);
    const run = runner(script, envelope, cwd);
    const parsed = parseGuardOutput(run.stdout);
    if (parsed !== undefined) return { guard: guard.id, ...parsed };
    if (run.status !== 0) {
      // A directory that cannot be entered and a guard that could not start share `status: null`, so
      // the error code decides which sentence the operator reads. Only a *directory* fault gets the
      // directory sentence: `ETIMEDOUT`/`ENOBUFS` are the guard's own limits, and `ENOENT` with an
      // existing cwd is a missing interpreter or script — telling that operator to create a
      // directory would send them to the wrong fix.
      if (run.error !== undefined && (run.error === "EACCES" || run.error === "ENOTDIR" || !existsSync(cwd))) {
        return {
          guard: GUARD_RUN_FAILURE,
          decision: "deny",
          reason: `the guard could not be started in \`${clip(cwd)}\` (${run.error}): ${script}. The working directory this call asked for is not enterable, so the command was NOT judged and NOT run. Create that directory and re-issue, or drop the \`workdir\` to be judged in the session directory.`,
        };
      }
      const how =
        run.status === null
          ? run.error === undefined
            ? "timed out or could not be spawned"
            : `could not be spawned (${run.error})`
          : `exited ${run.status}`;
      return {
        guard: GUARD_RUN_FAILURE,
        decision: "deny",
        reason: `the guard did not run (${how}): ${script}. The checkout the adapter points at may have moved or been removed — re-run \`bun "${INSTALLED_ROOT}/scripts/install-opencode-adapter.ts" --check\` from the plugin checkout. The command was NOT run, because an unrunnable guard cannot vouch for it.`,
      };
    }
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

/**
 * The default writer. A failed append is announced once and then shrugged off: an unwritable log
 * path (a parent directory that does not exist is the common shape of that mistake) must not make
 * `setup` reject, because a rejected setup leaves **no hook bound at all** — no guards, no capture,
 * nothing — to protect a diagnostic channel.
 */
const defaultWriter = (() => {
  let broken = false;
  return (line: string): void => {
    if (EVENT_LOG === undefined) return;
    try {
      appendFileSync(EVENT_LOG, `${line}\n`);
    } catch (error) {
      if (broken) return;
      broken = true;
      console.error(
        `[soleur] the event log \`${clip(String(EVENT_LOG))}\` is not writable (${clip(String(error))}); continuing without the durable record. The log's parent directory must exist.`,
      );
    }
  };
})();

export interface PermissionEvaluateEvent {
  readonly action?: unknown;
  readonly resources?: readonly unknown[];
  readonly agent?: unknown;
  /**
   * Where the decision came from. Measured (§12.2): a `shell` call carries
   * `{type: "tool", messageID, id}` and that `id` equals the `tool.execute.before` event's `id`,
   * which is the only channel through which the per-call `workdir` can reach this event.
   */
  readonly source?: { readonly type?: unknown; readonly id?: unknown; readonly messageID?: unknown };
  effect: "allow" | "ask" | "deny";
  message?: string;
}

/** A `tool.execute.before` event. Measured keys: `tool, sessionID, agent, messageID, id, input`. */
export interface ToolBeforeEvent {
  readonly tool?: unknown;
  readonly id?: unknown;
  readonly messageID?: unknown;
  readonly input?: unknown;
}

export interface SetupContext {
  location?: { directory?: string };
  permission: {
    hook(
      name: "evaluate",
      handler: (event: PermissionEvaluateEvent) => Promise<void> | void,
    ): Promise<unknown>;
  };
  /**
   * The capture surface (#10819). Optional because a runtime that does not offer it must still
   * load; absence, and a registration the runtime rejects, are both announced at setup rather than
   * ignored, because every decision then silently reverts to the session directory.
   */
  tool?: {
    hook(
      name: "execute.before",
      handler: (event: ToolBeforeEvent) => Promise<void> | void,
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
 * Cap on remembered sessions. A long-lived `opencode serve` sees one session per conversation and
 * no session-end event was measured to hook (§6.6), so the map is bounded here and the oldest
 * entry is evicted first — `Map` preserves insertion order, so this is a two-line LRU.
 */
const MAX_SESSIONS = 500;

/**
 * Cap on captured tool calls. One entry per Bash call, keyed by `(messageID, id)`; a long-lived
 * `opencode serve` never tells the plugin a call is finished, so the map is bounded here.
 *
 * Eviction is **silent**, unlike `remember`'s. A capture that is lost is announced where it could
 * change a verdict — at the decision, as `workdir-uncorrelated cause=no-capture` — so an eviction
 * notice would be a second report of the same fact, emitted for calls whose evaluation never
 * arrived at all (cancelled, auto-allowed by the ruleset). Loudness belongs at the decision.
 */
const MAX_CALLS = 500;

/**
 * The key a call is captured and consumed under.
 *
 * `id` alone was the obvious choice and the wrong one: the measured id (`call_00_s3uv…`) reads as a
 * per-message counter, and one plugin instance is shared by every session an `opencode serve`
 * process hosts. `messageID` is measured on both events, so the pair makes a colliding suffix
 * harmless. Both ids are **required**: defaulting a missing one to `""` would collapse the key back
 * to the bare counter and hand one call's workdir to another, so an absent id is uncorrelated
 * (loud, session directory) rather than correlated on half a key.
 */
function callKey(messageID: string, id: string): string {
  return `${messageID}\u0000${id}`;
}

/**
 * Build `setup`. The hooks are returned bound to injected collaborators so the unit tests can
 * drive them with a fake context and a fake script runner.
 */
export function createSetup(
  runner: ScriptRunner = runScript,
  pluginRoot: string = PLUGIN_ROOT,
  write: (line: string) => void = defaultWriter,
  report: (line: string) => void = (line) => console.error(line),
): (ctx: SetupContext) => Promise<void> {
  const sessions = new Map<string, SessionState>();
  const calls = new Map<string, WorkdirCapture>();

  /** Wire-controlled text before it goes into a TSV line: no C0/C1, no line/paragraph separators. */
  const field = (value: unknown): string => String(value).replace(/[\u0000-\u001f\u007f\u2028\u2029]/g, "_");

  /**
   * Announce a degraded correlation on both channels. The log file is off by default
   * (`SOLEUR_OPENCODE_EVENT_LOG` unset), so a log-only claim of loudness is false in the default
   * configuration; stderr visibility in the TUI is not measured, so neither channel alone is
   * enough. The sentence is for the operator, the TSV token for the record.
   */
  const announce = (token: string, detail: string, sentence: string): void => {
    report(`[soleur] ${sentence}`);
    // `detail` is fielded here as well as at the call sites: this is the single line assembler, so a
    // future caller that passes a raw path cannot break the column count.
    write(`soleur-opencode\t${token}\t${field(detail)}`);
  };

  /** Record a capture, keeping the map bounded. Write-once keys: no recency re-ordering. */
  const recordCall = (key: string, capture: WorkdirCapture): void => {
    calls.set(key, capture);
    while (calls.size > MAX_CALLS) {
      const oldest = calls.keys().next();
      if (oldest.done === true) break;
      calls.delete(oldest.value);
    }
  };

  /** Remember a session's state, keeping the map bounded and the most recent entry last. */
  const remember = (id: string, state: SessionState): void => {
    sessions.delete(id);
    sessions.set(id, state);
    while (sessions.size > MAX_SESSIONS) {
      const oldest = sessions.keys().next();
      if (oldest.done === true) break;
      sessions.delete(oldest.value);
    }
  };

  return async function setup(ctx: SetupContext): Promise<void> {
    const sessionCwd = ctx.location?.directory ?? process.cwd();

    /**
     * The one directory a `shell` decision is judged against, or the escalation to make instead.
     *
     * `ask` is returned only when a workdir **was** captured and cannot be used. Falling back to the
     * session directory there is defect #10819 applied to the one case where the operator
     * explicitly asked for a different directory — and `effect = "ask"` is a measured channel
     * (§12.2), so the plugin can say "I cannot check this" instead of guessing.
     */
    const decisionCwd = (
      event: PermissionEvaluateEvent,
    ): { kind: "decide"; cwd: string } | { kind: "unusable"; raw: string; message: string } => {
      const source = event.source;
      const id = source?.id;
      const idText = typeof id === "string" && id !== "" ? field(id) : "absent";
      // `source.type` is checked as well as the ids: a rule or config source whose id happened to
      // collide with a call id would otherwise apply a stale workdir and log success. A missing
      // message id is uncorrelatable rather than defaulted — with `""` on both sides a per-message
      // counter would collide across concurrent messages and hand call A's workdir to call B.
      const cause =
        source?.type !== "tool"
          ? "source-not-tool"
          : typeof id !== "string" || id === ""
            ? "id-absent"
            : typeof source.messageID !== "string"
              ? "message-id-absent"
              : undefined;
      if (cause !== undefined) {
        announce(
          "workdir-uncorrelated",
          `id=${idText}\tcause=${cause}`,
          `a shell call's permission event does not carry the ids the capture is keyed by (${cause}), so any per-call workdir cannot be correlated — this command is judged against the session directory instead. If this repeats, the runtime changed the event shape; check the OpenCode version.`,
        );
        return { kind: "decide", cwd: sessionCwd };
      }
      const capture = calls.get(callKey(source.messageID as string, id as string));
      if (capture === undefined) {
        announce(
          "workdir-uncorrelated",
          `id=${idText}\tcause=no-capture`,
          `the tool hook recorded nothing for shell call ${idText}, so any workdir it carried is unknown — this command is judged against the session directory instead. The tool hook did not fire; check the OpenCode version, then re-run \`install-opencode-adapter.ts --check\`.`,
        );
        return { kind: "decide", cwd: sessionCwd };
      }
      if (capture.kind === "absent") return { kind: "decide", cwd: sessionCwd };
      if (capture.kind === "usable") {
        write(`soleur-opencode\tworkdir-correlated\tcwd=${field(capture.path)}`);
        return { kind: "decide", cwd: capture.path };
      }
      announce(
        "workdir-unusable",
        `cwd=${field(capture.raw)}`,
        `this shell call asked to run in \`${capture.raw}\`, which is not a directory this plugin can use. The guards were run against the session directory instead and declined, so the command is not checked against the directory it asked for.`,
      );
      return {
        kind: "unusable",
        raw: capture.raw,
        message: `Soleur: this shell call asked for \`${capture.raw}\`, which is not a usable directory, so it could not be checked against the directory it asked for — the guards ran against the session directory and declined. Re-issue it without \`workdir\` to be checked here, or create that directory first.`,
      };
    };

    /** Deliver a guard decision onto the event, never relaxing an arriving `deny` into an `ask`. */
    const applyDecision = (event: PermissionEvaluateEvent, decision: GuardDecision | undefined): void => {
      if (decision === undefined) return;
      // Only `allow` arrivals were measured (§12.2); relaxing an unmeasured deny is the
      // silent-enforcement-loss direction.
      if (event.effect === "deny" && decision.decision === "ask") return;
      event.effect = decision.decision;
      event.message = decisionMessage(decision);
      // A guard that could not run is an operator-visible fault, so it is announced even when the
      // observation channel was never armed.
      if (decision.guard === GUARD_RUN_FAILURE) {
        report(`[soleur] ${decision.reason}`);
        write(`soleur-opencode\tguard-run-failure\teffect=deny\t${field(decision.reason)}`);
      }
    };

    await ctx.permission.hook("evaluate", (event) => {
      const action = event.action;
      // ONE predicate for both sides (#10819). A non-Bash action returns before the map is touched:
      // the measured `external_directory` event fires FIRST with the same call id, and consuming it
      // there would lose the workdir before the decision that needs it.
      if (typeof action !== "string" || !decidesBash(action)) return;
      const target = decisionCwd(event);
      if (target.kind === "decide") {
        applyDecision(event, decidePermission(action, event.resources ?? [], target.cwd, runner, pluginRoot));
        return;
      }
      // A captured workdir that cannot be used does NOT skip the guards: their cwd-independent
      // classes (a home wipe, an infra destroy, a credential-bearing snapshot, a forced push to the
      // default branch) are the ones that must survive, and running them costs one prompt at most.
      // Only when they decline does the unresolvable directory become the decision — and an
      // arriving `deny` is still never relaxed into that prompt.
      applyDecision(event, decidePermission(action, event.resources ?? [], sessionCwd, runner, pluginRoot));
      if (event.effect !== "allow") return;
      event.effect = "ask";
      event.message = target.message;
    });

    /**
     * Capture-only (#10819): publish `input.workdir` for the decision above. Bound **after** the
     * decision surface, so a runtime that rejects this registration cannot leave the guards
     * unbound; wrapped, because optional chaining covers an absent `tool` and not a rejecting
     * `hook()`. Never decides, never throws — a throw here would preempt the real ask behind it.
     */
    const capture = (event: ToolBeforeEvent): void => {
      try {
        const tool = event.tool;
        if (typeof tool !== "string" || !decidesBash(tool)) return;
        const id = event.id;
        const hasId = typeof id === "string" && id !== "";
        if (!hasId || typeof event.messageID !== "string") {
          announce(
            "workdir-uncapturable",
            `id=${hasId ? field(id) : "absent"}\treason=${hasId ? "message-id-absent" : "id-absent"}`,
            "a shell call reached the tool hook without the ids its permission event is keyed by, so its workdir cannot be published — the decision that follows is judged against the session directory. Check the OpenCode version.",
          );
          return;
        }
        recordCall(callKey(event.messageID, id), resolveWorkdir(event.input, sessionCwd));
      } catch (error) {
        // Containment for the "never throw" promise: with total helpers this is unreachable, and it
        // must stay that way rather than becoming the one path that preempts the real ask.
        announce(
          "workdir-capture-error",
          `reason=${field(String(error))}`,
          `the workdir capture failed (${clip(String(error))}); this shell call is judged against the session directory and the guards still run.`,
        );
      }
    };

    const noToolSurface = (reason: string): void => {
      announce(
        "no-tool-hook-surface",
        `workdir-unavailable\treason=${field(reason)}`,
        `this runtime offers no usable \`tool.execute.before\` surface (${clip(reason)}), so a shell call's \`workdir\` cannot be captured — every command is judged against the session directory, as before this fix. The permission guards remain bound.`,
      );
    };

    if (ctx.tool === undefined) {
      noToolSurface("the surface is absent");
    } else {
      try {
        await ctx.tool.hook("execute.before", capture);
      } catch (error) {
        noToolSurface(String(error));
      }
    }

    await ctx.session.hook("context", (event) => {
      const cwd = typeof event["cwd"] === "string" ? event["cwd"] : sessionCwd;
      const rawSessionID = event["sessionID"];
      const sessionID = typeof rawSessionID === "string" ? rawSessionID : undefined;
      // A missing or non-string id gets no shared bucket: one session's `injected` must never
      // silence another's. Such an event injects and is not memoized.
      const state =
        sessionID === undefined ? { injected: false, compacted: false } : (sessions.get(sessionID) ?? { injected: false, compacted: false });
      if (state.injected && !state.compacted) return;
      const system = event["system"];
      if (!Array.isArray(system)) {
        write(`soleur-opencode\tcontext\tno-system-array\tsession=${field(sessionID)}`);
        return;
      }
      // The compaction hook's own `system` reaches only the summarization call, so the re-read
      // directive has to ride the next real request — which is this one (measurement §12.3).
      if (state.compacted) system.push({ type: "text", text: compactionDirective() });
      const rules = rulesInjection(cwd, runner);
      if (rules !== undefined) system.push({ type: "text", text: rules });
      // One line per injection decision: whether the corpus landed must be answerable from the
      // log, so a hook that stops firing — or a corpus that moved — is visible rather than
      // indistinguishable from working.
      const outcome = rules === undefined ? "no-corpus" : `injected:${rules.length}`;
      write(`soleur-opencode\tcontext\t${outcome}\tsession=${field(sessionID)}\tcwd=${field(cwd)}`);
      if (sessionID !== undefined) remember(sessionID, { injected: true, compacted: false });
    });

    await ctx.session.hook("compaction", (event) => {
      const rawSessionID = event["sessionID"];
      if (typeof rawSessionID !== "string") {
        write(`soleur-opencode\tcompaction\tunkeyed\treread-not-armed`);
        return;
      }
      const state = sessions.get(rawSessionID) ?? { injected: false, compacted: false };
      remember(rawSessionID, { ...state, compacted: true });
      write(`soleur-opencode\tcompaction\treread-armed\tsession=${field(rawSessionID)}`);
    });

    // Observation only, and it must stay that way: §6.6 measured no return channel, so an idle
    // signal can be noticed and acted on by nothing. Off unless SOLEUR_OPENCODE_EVENT_LOG names
    // a path.
    void (async () => {
      try {
        for await (const event of ctx.event.subscribe()) {
          const type = typeof event?.type === "string" ? event.type : "unknown";
          if (type.startsWith("session.")) write(`soleur-opencode\t${field(type)}\tadvisory-completion-marker-not-enforceable`);
        }
      } catch (error) {
        write(`soleur-opencode\tevent-stream-error\t${field(String(error))}`);
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
