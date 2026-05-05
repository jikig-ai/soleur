// canUseTool callback factory — extracted from the inline closure that
// previously lived in `agent-runner.ts`. Extraction lets unit tests
// exercise the 7 allow branches + deny-by-default without booting an
// entire SDK session (see #2335).
//
// The SDK's permission chain has 5 steps (hooks → deny rules →
// permission mode → allow rules → canUseTool). This factory implements
// step 5; the earlier layers are configured elsewhere (PreToolUse hook,
// settingSources: [], allowedTools, sandbox deny list).
//
// Allow-path contract: SDK v0.2.80 rejected bare `{ behavior: "allow" }`
// with `ZodError: invalid_union`. The `allow(toolInput)` helper
// unconditionally echoes the input as `updatedInput` — behaviorally a
// no-op, satisfies both permissive and strict variants of the schema.
// See learning 2026-04-15-sdk-v0.2.80-zoderror-allow-shape.md.
//
// DI boundary: pure/deterministic helpers (tool-tier lookup, path
// checks, review-gate parsing) are imported directly — injecting them
// would expand the test-context surface without buying any seam the
// caller actually uses. Only genuinely stateful collaborators
// (WS client, DB status updater, offline-notification, review gate
// resolver) are injected via `CanUseToolDeps`.

import { randomUUID } from "crypto";
import type {
  CanUseTool,
  PermissionResult,
} from "@anthropic-ai/claude-agent-sdk";

import { createChildLogger } from "./logger";
import { logPermissionDecision } from "./permission-log";
import {
  extractReviewGateInput,
  buildReviewGateResponse,
  type AgentSession,
} from "./review-gate";
import { getToolTier, buildGateMessage, type ToolTier } from "./tool-tiers";
import {
  isFileTool,
  isSafeTool,
  extractToolPath,
  UNVERIFIED_PARAM_TOOLS,
} from "./tool-path-checker";
import { isPathInWorkspace } from "./sandbox";
import type { NotificationPayload } from "./notifications";
import type { WSMessage } from "@/lib/types";
import {
  type BashApprovalCache,
  deriveBashCommandPrefix,
} from "./permission-callback-bash-batch";
import { warnSilentFallback } from "./observability";

const log = createChildLogger("permission");

// Exported so the inline-closure deletion assertion (negative-space
// delegation test) does not give false positives — see
// canusertool-decisions.test.ts.
export function allow(toolInput: Record<string, unknown>): Extract<PermissionResult, { behavior: "allow" }> {
  return { behavior: "allow" as const, updatedInput: toolInput };
}

// Bash pre-gate blocklist. Applied BEFORE the review-gate under the
// untrusted-user threat model introduced by the cc-soleur-go runner
// (Stage 2.11 of plan 2026-04-23-feat-cc-route-via-soleur-go-plan.md).
// The plugin surface brings `Bash` into scope; this regex catches the
// high-severity foot-guns callers have used to pivot into network or
// privilege escalation — curl/wget/nc pipelines, shell-interpreter
// re-entry, eval-style evaluation, base64-decoded payloads, Linux
// /dev/tcp back-channels, and sudo. A match denies outright; no user
// gate is offered, because legitimate workflow prompts never need these.
//
// Word-boundary anchors (`\b`) keep false positives down (e.g., a file
// named `evalent.ts` or a command mentioning "sudoku" should not match).
// Case-insensitive because shell commands are.
//
// Interpreter-flag arms (`node|python|python3|ruby|perl|deno|bun -e/-c`,
// `deno eval`) catch the same payload-execution surface as `sh -c` but
// via language interpreters that the soleur plugin sometimes legitimately
// invokes (`node script.ts`, `python -m pytest`). Plain interpreter
// invocations remain allowed; only the inline-eval flags `-e`/`-c` (and
// `deno eval`) are blocked outright. A previously-granted `node` or
// `python` batch grant cannot launder these.
export const BLOCKED_BASH_PATTERNS =
  /\b(?:curl|wget|ncat|nc|eval|sudo)\b|(?:sh|bash|node|python|python3|ruby|perl|deno|bun)\s+-(?:e|c)\b|deno\s+eval\b|base64\s+-d|\/dev\/tcp/i;

export function isBashCommandBlocked(command: string): boolean {
  if (typeof command !== "string" || command.length === 0) return false;
  return BLOCKED_BASH_PATTERNS.test(command);
}

// Safe-Bash allowlist (plan: 2026-04-29-fix-command-center-qa-permissions).
//
// Auto-approves read-only file/git/cwd inspection commands BEFORE the
// review-gate. Every entry is a LEADING-TOKEN regex against the trimmed
// command — substring matches do NOT count, so `pwd && curl evil` cannot
// match the `pwd` entry.
//
// The regex contract is two-stage:
//   1. SHELL_METACHAR_DENYLIST rejects ANY raw command containing one of
//      `;`, `&`, `&&`, `|`, `||`, backtick, `$(`, `${`, `>`, `>>`, `<`,
//      `<<`, newline, carriage return. Single-regex check on the raw
//      string (not after splitting) so escape-sneak attempts (`pwd\;ls`)
//      cannot launder through. Backslash itself is rejected to seal the
//      escape-sneak surface.
//   2. SAFE_BASH_PATTERNS matches the trimmed command. Each per-tool
//      pattern uses a narrow path/identifier arg shape — no shell
//      metacharacters allowed in args either.
//
// `find` and `grep` are intentionally OMITTED — both accept `-exec` and
// could shell out. `find` is also redundant with the SDK's `Glob` tool
// which is auto-allowed via FILE_TOOLS.
//
// `printenv` is intentionally OMITTED — without an arg it dumps the
// entire env (BYOK key, service tokens). Even with an arg, the env may
// hold secrets the agent never needs to read; users who want a single
// var should let the agent ask for it via the review-gate.
//
// `$` is in the metachar denylist so `echo "$VAR"` (which bash expands
// inside double quotes) is rejected. U+2028 / U+2029 are included to
// match the project's Unicode line-separator hardening pattern. The
// full C0 range (`\x00-\x1f`) plus DEL (`\x7f`) is rejected to seal
// log-injection / null-byte truncation surfaces \u2014 `\n` (`\x0a`) and
// `\r` (`\x0d`) fall inside that range and are therefore double-covered.
const SHELL_METACHAR_DENYLIST = /[;&|`<>$\\\x00-\x1f\x7f\u2028\u2029]/;
// Path-traversal denylist (#3252). Matches `..` only as a parent-dir segment
// \u2014 preceded by start-of-string, slash, or whitespace AND followed by
// end-of-string, slash, or whitespace. Filenames containing `..` (such as
// `..baz`, `my..backup.txt`, `...gitignore`, `....file`) are NOT matched.
//
// **DO NOT REMOVE** this denylist without auditing every PATH_TOKEN-using
// regex above for `..` acceptance. The `cd` regex (and other PATH_TOKEN
// args like `cat <path>`) accepts `../foo` as a path arg by token shape;
// this denylist is the only thing that rejects parent-dir traversal at
// the canUseTool boundary. extractToolPath/isPathInWorkspace does NOT
// apply to Bash (Bash uses `command`, not `file_path`/`path`), so the
// workspace-relative invariant is enforced here.
const PATH_TRAVERSAL_DENYLIST = /(?:^|[\s/])\.\.(?:$|[\s/])/;
// Belt-and-suspenders: a 4096-char input cap before regex matching keeps
// pathological-length inputs from amplifying any backtracking cost.
const SAFE_BASH_MAX_INPUT_LENGTH = 4096;

// Path/identifier arg shape: word chars, slash, dot, tilde, plus, colon,
// equals, hyphen, at-sign. No shell-special chars, no spaces inside a
// single token.
const PATH_TOKEN = String.raw`[\w./~+:=@-]+`;

// Quoted-or-bareword token for `echo` — accepts `"hello world"`,
// `'foo bar'`, or path-shape barewords. The metachar denylist already
// rejects `$`/backtick at the raw-string level, so quoted strings here
// cannot contain expansion sigils.
const ECHO_TOKEN = String.raw`(?:"[^"\\]*"|'[^'\\]*'|[\w./~+:=@-]+)`;

export const SAFE_BASH_PATTERNS: readonly RegExp[] = [
  // No-arg / fixed-form commands
  /^pwd\s*$/,
  /^whoami\s*$/,
  /^id\s*$/,
  /^date\s*$/,
  /^hostname\s*$/,
  // cd — optional single path arg. No flags (cd -, cd --, cd -P all
  // rejected via the negative lookahead). The `..` arg shape is
  // structurally accepted by PATH_TOKEN here but PATH_TRAVERSAL_DENYLIST
  // in isBashCommandSafe rejects it before this pattern runs; see TS6
  // for the regression pin.
  new RegExp(String.raw`^cd(?:\s+(?!-)${PATH_TOKEN})?\s*$`),
  // ls — optional flags + optional path args
  new RegExp(String.raw`^ls(?:\s+-[a-zA-Z]+)*(?:\s+${PATH_TOKEN})*\s*$`),
  // Single-arg path-taking commands
  new RegExp(String.raw`^cat\s+${PATH_TOKEN}\s*$`),
  new RegExp(String.raw`^head(?:\s+-n\s+\d+)?\s+${PATH_TOKEN}\s*$`),
  new RegExp(String.raw`^tail(?:\s+-n\s+\d+)?\s+${PATH_TOKEN}\s*$`),
  new RegExp(String.raw`^wc(?:\s+-[a-zA-Z]+)?\s+${PATH_TOKEN}\s*$`),
  new RegExp(String.raw`^file\s+${PATH_TOKEN}\s*$`),
  new RegExp(String.raw`^stat\s+${PATH_TOKEN}\s*$`),
  new RegExp(String.raw`^which\s+${PATH_TOKEN}\s*$`),
  // uname with optional flags
  /^uname(?:\s+-[a-zA-Z]+)*\s*$/,
  // git read-only verbs
  /^git\s+status\s*$/,
  new RegExp(
    String.raw`^git\s+log(?:\s+(?:-[a-zA-Z]+|--[a-zA-Z][\w-]*(?:=[\w./~+:=@-]+)?|-n\s+\d+|\d+|${PATH_TOKEN}))*\s*$`,
  ),
  new RegExp(
    String.raw`^git\s+diff(?:\s+(?:-[a-zA-Z]+|--[a-zA-Z][\w-]*(?:=[\w./~+:=@-]+)?|${PATH_TOKEN}))*\s*$`,
  ),
  new RegExp(
    String.raw`^git\s+show(?:\s+(?:-[a-zA-Z]+|--[a-zA-Z][\w-]*(?:=[\w./~+:=@-]+)?|${PATH_TOKEN}))*\s*$`,
  ),
  new RegExp(
    String.raw`^git\s+branch(?:\s+(?:-[a-zA-Z]+|--[a-zA-Z][\w-]*|${PATH_TOKEN}))*\s*$`,
  ),
  new RegExp(
    String.raw`^git\s+rev-parse(?:\s+(?:-[a-zA-Z]+|--[a-zA-Z][\w-]*|${PATH_TOKEN}))*\s*$`,
  ),
  // git config --get only (no --set, no --unset, no --add)
  new RegExp(String.raw`^git\s+config\s+--get(?:\s+[\w.-]+)?\s*$`),
  // echo — quoted strings or barewords
  new RegExp(String.raw`^echo(?:\s+${ECHO_TOKEN})*\s*$`),
];

// Single source of truth for the safe-bash verb list. Used by the
// per-pattern regexes above (informationally — each regex hardcodes its
// own leading verb) AND by SAFE_BASH_NEAR_MISS_PREFIX below (derived).
// When adding a new safe verb, append it here AND add a per-tool regex
// to SAFE_BASH_PATTERNS — the near-miss prefix updates automatically.
const SAFE_BASH_VERBS = [
  "pwd", "whoami", "id", "date", "hostname",
  "cd", "ls", "cat", "head", "tail", "wc",
  "file", "stat", "which", "uname", "git", "echo",
] as const;

// Near-miss prefix detection (#3252). Matches commands whose leading
// token starts with a known safe-bash allowlist verb but extends past
// it (lsof vs ls, cdrecord vs cd, pwdx vs pwd, catatonic vs cat).
// Used only for telemetry — the rejection path is the same either way
// (review-gate). When this fires, on-call sees drift before someone
// widens the allowlist into a confused-deputy escape.
//
// Surface intentionally includes lsblk/lsattr/lscpu/lsmod/lspci/lsusb/
// etc. — these ARE near-misses to `ls`, and the drift signal is correct.
// Operators monitoring `safe-bash-near-miss` should expect such tokens
// in normal exploration noise (see plan §Risks R5).
const SAFE_BASH_NEAR_MISS_PREFIX = new RegExp(
  String.raw`^(?:${SAFE_BASH_VERBS.join("|")})\w`,
);

// Per-(canUseTool ctx) dedupe + budget for near-miss telemetry. Keyed
// via WeakMap so the state is GC'd when the conversation ends. Caps
// emitted events per-ctx at NEAR_MISS_PER_CTX_BUDGET to bound Sentry
// flood under prompt-injected loops emitting unique near-miss tokens
// (plan §R3). leadingToken is sliced to NEAR_MISS_LEADING_TOKEN_MAX
// chars to bound PII surface in glued-no-space commands.
const NEAR_MISS_PER_CTX_BUDGET = 32;
const NEAR_MISS_LEADING_TOKEN_MAX = 32;
type NearMissState = { seen: Set<string>; emitted: number };
const NEAR_MISS_STATE = new WeakMap<CanUseToolContext, NearMissState>();

/**
 * Returns true iff `command` is a single, read-only file/git/cwd
 * inspection command safe to auto-approve without a user gate.
 *
 * Rejects:
 *   - non-string / empty input (defensive),
 *   - any command containing shell metacharacters (compound, redirect,
 *     subshell, expansion, escape),
 *   - any command whose leading token is not in SAFE_BASH_PATTERNS,
 *   - any command whose argument shape doesn't match the tight per-tool
 *     pattern.
 *
 * The check runs AFTER `isBashCommandBlocked` in the canUseTool flow so
 * the blocklist is authoritative when both could match.
 */
export function isBashCommandSafe(command: unknown): boolean {
  if (typeof command !== "string" || command.length === 0) return false;
  if (command.length > SAFE_BASH_MAX_INPUT_LENGTH) return false;
  // Stage 1: raw-string metacharacter denylist. Run BEFORE trim so
  // leading/trailing newlines (for example) are caught.
  if (SHELL_METACHAR_DENYLIST.test(command)) return false;
  // Stage 1b: parent-dir traversal denylist (#3252). Run BEFORE the
  // per-pattern allowlist so PATH_TOKEN-shape regexes (cd <path>,
  // cat <path>, ls <path>) cannot accept `../` arg shapes. Filenames
  // starting with `..` (e.g. `..baz`) are not matched — see the regex
  // definition. Bash uses `command`, not `file_path`/`path`, so the
  // canUseTool's isFileTool→isPathInWorkspace defense does NOT fire
  // for Bash invocations. This denylist is the canUseTool-boundary
  // check; the bubblewrap sandbox is the OS-syscall-boundary check.
  if (PATH_TRAVERSAL_DENYLIST.test(command)) return false;
  const trimmed = command.trim();
  if (trimmed.length === 0) return false;
  // Stage 2: leading-token allowlist match against trimmed string.
  for (const pattern of SAFE_BASH_PATTERNS) {
    if (pattern.test(trimmed)) return true;
  }
  return false;
}

// Safe UX-flow tools surfaced by the soleur plugin that carry no path
// args and no command execution. Kept separate from `SAFE_TOOLS` in
// `tool-path-checker.ts` so the existing `canusertool-decisions`
// negative-space tests remain stable.
const SOLEUR_GO_SAFE_UX_TOOLS = new Set<string>([
  "ExitPlanMode",
]);

/**
 * Stateful collaborators the callback depends on. Pure helpers
 * (tool-tier, path checks, review-gate parsing) are imported directly
 * at the top of this module — not injected — because they carry no
 * session state and their unit tests live in their own modules.
 */
export interface CanUseToolDeps {
  abortableReviewGate: (
    session: AgentSession,
    gateId: string,
    signal: AbortSignal,
    timeoutMs: number | undefined,
    options: string[],
  ) => Promise<string>;
  sendToClient: (userId: string, payload: WSMessage) => boolean;
  notifyOfflineUser: (
    userId: string,
    payload: NotificationPayload,
  ) => Promise<void>;
  updateConversationStatus: (
    conversationId: string,
    status: string,
  ) => Promise<void>;
  /**
   * Optional per-(userId, conversationId) Bash command-prefix
   * batched-approval cache (#2921). When wired, the Bash review-gate
   * checks the cache BEFORE issuing a gate (cache hit → auto-approve)
   * and offers `Approve all <prefix>` as a third option that calls
   * `cache.grant(prefix)` on selection. Legacy runner does NOT wire
   * this — preserves the 2-option Bash gate for trusted-prompt domain
   * leaders.
   */
  bashApprovalCache?: BashApprovalCache;
}

export interface CanUseToolContext {
  userId: string;
  conversationId: string;
  leaderId: string | undefined;
  workspacePath: string;
  /** Registered platform tool names (full `mcp__soleur_platform__*`). Allowlist. */
  platformToolNames: readonly string[];
  /** Plugin MCP server names from plugin.json. Allowlist for `mcp__plugin_soleur_<server>__*`. */
  pluginMcpServerNames: readonly string[];
  repoOwner: string;
  repoName: string;
  session: AgentSession;
  controllerSignal: AbortSignal;
  deps: CanUseToolDeps;
}

export function createCanUseTool(ctx: CanUseToolContext): CanUseTool {
  const { deps } = ctx;
  return async (toolName, toolInput, options): Promise<PermissionResult> => {
    const subagentCtx = options.agentID ? ` [subagent=${options.agentID}]` : "";

    // Defense-in-depth: catch any file tool that bypasses PreToolUse hooks.
    // Hooks are the primary enforcement (layer 1); this is layer 2. See #891.
    if (isFileTool(toolName)) {
      const filePath = extractToolPath(toolInput);
      if (filePath && !isPathInWorkspace(filePath, ctx.workspacePath)) {
        logPermissionDecision(
          "canUseTool-file-tool",
          toolName,
          "deny",
          "outside workspace",
        );
        return {
          behavior: "deny" as const,
          message: `Access denied: outside workspace${subagentCtx}`,
        };
      }
      if (
        !filePath &&
        (UNVERIFIED_PARAM_TOOLS as readonly string[]).includes(toolName) &&
        Object.keys(toolInput).length > 0
      ) {
        log.warn(
          { sec: true, toolName, inputKeys: Object.keys(toolInput) },
          "Tool invoked without recognized path parameter; SDK may have changed parameter names (see #891)",
        );
      }
      logPermissionDecision("canUseTool-file-tool", toolName, "allow");
      return allow(toolInput);
    }

    // Review gates: intercept AskUserQuestion
    if (toolName === "AskUserQuestion") {
      const gateId = randomUUID();
      const gate = extractReviewGateInput(toolInput);

      if (gate.isNewSchema) {
        const questions = toolInput.questions as unknown[];
        if (Array.isArray(questions) && questions.length > 1) {
          log.warn(
            { questionCount: questions.length },
            "AskUserQuestion received multiple questions; only the first is surfaced",
          );
        }
      }

      // Parse step progress from header (e.g., "Step 2 of 6: Configure DNS")
      const stepMatch = gate.header?.match(/^Step (\d+) of (\d+): .+$/);
      const stepProgress = stepMatch
        ? { current: Number(stepMatch[1]), total: Number(stepMatch[2]) }
        : undefined;

      const gateDelivered = deps.sendToClient(ctx.userId, {
        type: "review_gate",
        gateId,
        question: gate.question,
        header: gate.header,
        options: gate.options,
        descriptions: Object.keys(gate.descriptions).length > 0
          ? gate.descriptions
          : undefined,
        stepProgress,
      });

      if (!gateDelivered) {
        deps.notifyOfflineUser(ctx.userId, {
          type: "review_gate",
          conversationId: ctx.conversationId,
          agentName: ctx.leaderId ?? "Agent",
          question: gate.question,
        }).catch((err) =>
          log.error({ userId: ctx.userId, err }, "Offline notification failed"),
        );
      }

      await deps.updateConversationStatus(ctx.conversationId, "waiting_for_user");

      const selection = await deps.abortableReviewGate(
        ctx.session,
        gateId,
        ctx.controllerSignal,
        undefined,
        gate.options,
      );

      await deps.updateConversationStatus(ctx.conversationId, "active");

      logPermissionDecision(
        "canUseTool-review-gate",
        toolName,
        "allow",
        selection,
      );
      return {
        behavior: "allow" as const,
        updatedInput: buildReviewGateResponse(toolInput, selection),
      };
    }

    // ExitPlanMode: plan-preview-acknowledgment tool surfaced by the
    // soleur plugin. No filesystem path, no command execution — purely
    // a UX signal that the planning phase is complete. Stage 2.11.
    if (toolName === "ExitPlanMode" || SOLEUR_GO_SAFE_UX_TOOLS.has(toolName)) {
      logPermissionDecision("canUseTool-soleur-go-ux", toolName, "allow");
      return allow(toolInput);
    }

    // Bash: NEVER auto-approve. Stage 2.11 of plan
    // 2026-04-23-feat-cc-route-via-soleur-go-plan.md. The soleur plugin
    // brings Bash into scope under an untrusted-user threat model. Two
    // layers apply in order:
    //   (1) BLOCKED_BASH_PATTERNS regex — reject high-severity patterns
    //       (curl|wget|nc|sh -c|eval|base64 -d|/dev/tcp|sudo) outright.
    //   (2) Review-gate with a command preview — user must explicitly
    //       Approve before the command runs.
    if (toolName === "Bash") {
      const command = toolInput.command;
      if (typeof command !== "string" || command.length === 0) {
        logPermissionDecision(
          "canUseTool-bash",
          toolName,
          "deny",
          "missing or empty command",
        );
        return {
          behavior: "deny" as const,
          message: "Bash invocation missing a command argument",
        };
      }
      if (isBashCommandBlocked(command)) {
        log.info(
          {
            sec: true,
            tool: toolName,
            decision: "deny-blocked-pattern",
            repo: `${ctx.repoOwner}/${ctx.repoName}`,
          },
          "Bash command matched BLOCKED_BASH_PATTERNS — denied",
        );
        logPermissionDecision(
          "canUseTool-bash",
          toolName,
          "deny",
          "BLOCKED_BASH_PATTERNS match",
        );
        return {
          behavior: "deny" as const,
          message:
            "This Bash command matches a blocked pattern (curl/wget/nc/sh -c/eval/base64 -d/sudo or similar) and is not permitted.",
        };
      }

      // Safe-Bash allowlist (plan: 2026-04-29). Auto-approve read-only
      // file/git/cwd inspection commands BEFORE the cache and the
      // review-gate. Faster than a cache hit (regex vs. Map lookup is
      // wash, but no cache wear) and removes nuisance prompts for
      // `pwd`/`ls`/`cat`/`git status` etc. that were forcing modal
      // interrupts in Command Center. The blocklist already ran above,
      // so curl/wget/nc/sudo/etc. cannot reach this branch.
      if (isBashCommandSafe(command)) {
        log.info(
          {
            sec: true,
            tool: toolName,
            decision: "auto-approved-safe-bash",
            repo: `${ctx.repoOwner}/${ctx.repoName}`,
          },
          "Bash command auto-approved via safe-bash allowlist",
        );
        logPermissionDecision(
          "canUseTool-bash",
          toolName,
          "allow",
          "safe-bash-allowlist",
        );
        return allow(toolInput);
      }

      // Near-miss telemetry hook (#3252). Step 3.5 of the Bash-branch
      // ordering: AFTER the safe-bash allowlist missed, BEFORE the
      // batched-approval cache lookup. Placement is load-bearing —
      // earlier would emit on blocklist-denied commands (sudo/curl);
      // moving past the cache check would silence drift signal once a
      // batched grant short-circuits subsequent identical invocations.
      // PII + flood guards: leadingToken is sliced to ≤32 chars and
      // deduped per-ctx with a 32-event-per-ctx budget cap.
      const trimmedCmd = command.trim();
      if (SAFE_BASH_NEAR_MISS_PREFIX.test(trimmedCmd)) {
        const leadingToken = trimmedCmd
          .split(/\s+/)[0]
          .slice(0, NEAR_MISS_LEADING_TOKEN_MAX);
        let nearMissState = NEAR_MISS_STATE.get(ctx);
        if (!nearMissState) {
          nearMissState = { seen: new Set(), emitted: 0 };
          NEAR_MISS_STATE.set(ctx, nearMissState);
        }
        if (
          nearMissState.emitted < NEAR_MISS_PER_CTX_BUDGET &&
          !nearMissState.seen.has(leadingToken)
        ) {
          nearMissState.seen.add(leadingToken);
          nearMissState.emitted += 1;
          warnSilentFallback(null, {
            feature: "cc-permissions",
            op: "safe-bash-near-miss",
            extra: { leadingToken },
          });
        }
      }

      // #2921 batched-approval cache: pre-gate check (synchronous Map
      // lookup; no AbortSignal needed for cache hit). Blocklist already
      // ran above — curl/wget/nc/sh -c/eval/base64 -d/sudo cannot be
      // batched because they were denied before reaching this branch.
      if (deps.bashApprovalCache?.allow(command)) {
        log.info(
          {
            sec: true,
            tool: toolName,
            decision: "auto-approved-batch",
            repo: `${ctx.repoOwner}/${ctx.repoName}`,
          },
          "Bash command auto-approved via batch grant",
        );
        logPermissionDecision(
          "canUseTool-bash",
          toolName,
          "allow",
          "batch grant",
        );
        return allow(toolInput);
      }

      // Derive the prefix the user can grant in the gate. When the
      // cache dep is wired, augment the gate options array with
      // `Approve all <prefix>` so the user can collapse the modal cliff.
      const cachePrefix = deps.bashApprovalCache
        ? deriveBashCommandPrefix(command)
        : "";
      const gateOptions =
        deps.bashApprovalCache && cachePrefix
          ? ["Approve", `Approve all \`${cachePrefix}\``, "Reject"]
          : ["Approve", "Reject"];

      const gateId = randomUUID();
      const preview = command.length > 200 ? `${command.slice(0, 200)}…` : command;
      const question = `Run Bash command?\n\n\`${preview}\``;

      const gateDelivered = deps.sendToClient(ctx.userId, {
        type: "review_gate",
        gateId,
        question,
        options: gateOptions,
      });
      if (!gateDelivered) {
        deps.notifyOfflineUser(ctx.userId, {
          type: "review_gate",
          conversationId: ctx.conversationId,
          agentName: ctx.leaderId ?? "Agent",
          question,
        }).catch((err) =>
          log.error(
            { userId: ctx.userId, err },
            "Offline notification failed (bash gate)",
          ),
        );
      }

      await deps.updateConversationStatus(ctx.conversationId, "waiting_for_user");

      const selection = await deps.abortableReviewGate(
        ctx.session,
        gateId,
        options.signal,
        undefined,
        gateOptions,
      );

      await deps.updateConversationStatus(ctx.conversationId, "active");

      // Selection can be "Approve", "Approve all `<prefix>`", or "Reject".
      const approveAllOption =
        deps.bashApprovalCache && cachePrefix
          ? `Approve all \`${cachePrefix}\``
          : null;
      const isBatchedApprove =
        approveAllOption !== null && selection === approveAllOption;
      const isApprove = selection === "Approve" || isBatchedApprove;

      if (!isApprove) {
        logPermissionDecision(
          "canUseTool-bash",
          toolName,
          "deny",
          "user rejected",
        );
        return {
          behavior: "deny" as const,
          message: "User rejected the Bash command",
        };
      }

      if (isBatchedApprove && deps.bashApprovalCache && cachePrefix) {
        // Grant the prefix so subsequent matching commands hit the
        // cache (auto-approve, zero gate). 60-min TTL + revoke on
        // conversation cleanup.
        deps.bashApprovalCache.grant(cachePrefix);
        log.info(
          {
            sec: true,
            tool: toolName,
            decision: "user-approved-batch",
            prefix: cachePrefix,
            repo: `${ctx.repoOwner}/${ctx.repoName}`,
          },
          "Bash command approved via batch grant",
        );
      } else {
        log.info(
          {
            sec: true,
            tool: toolName,
            decision: "user-approved",
            repo: `${ctx.repoOwner}/${ctx.repoName}`,
          },
          "Bash command approved via review-gate",
        );
      }
      logPermissionDecision(
        "canUseTool-bash",
        toolName,
        "allow",
        isBatchedApprove ? "user approved (batch)" : "user approved",
      );
      return allow(toolInput);
    }

    // Agent tool: spawns subagents under the same SDK sandbox. Explicit
    // allow (replaces prior SAFE_TOOLS auto-allow) for auditability. See #910.
    if (toolName === "Agent") {
      if (subagentCtx) {
        log.info(
          { sec: true, agentId: options.agentID },
          "Agent tool invoked by subagent",
        );
      }
      logPermissionDecision("canUseTool-agent", toolName, "allow");
      return allow(toolInput);
    }

    // Safe SDK tools (no filesystem-path inputs). See tool-path-checker.ts.
    if (isSafeTool(toolName)) {
      logPermissionDecision("canUseTool-safe", toolName, "allow");
      return allow(toolInput);
    }

    // Tiered gating for in-process MCP server tools (#1926). Scoped to
    // `platformToolNames` (not blanket mcp__ prefix) so future MCP servers
    // never auto-allow without explicit review.
    if (ctx.platformToolNames.includes(toolName)) {
      const tier: ToolTier = getToolTier(toolName);

      if (tier === "blocked") {
        log.info(
          {
            sec: true,
            tool: toolName,
            tier,
            decision: "deny",
            repo: `${ctx.repoOwner}/${ctx.repoName}`,
          },
          "Platform tool blocked",
        );
        logPermissionDecision(
          "canUseTool-platform-blocked",
          toolName,
          "deny",
          "blocked tier",
        );
        return {
          behavior: "deny" as const,
          message: "This action is not allowed from cloud agents",
        };
      }

      if (tier === "gated") {
        const gateId = randomUUID();
        const question = buildGateMessage(toolName, toolInput);

        const toolGateDelivered = deps.sendToClient(ctx.userId, {
          type: "review_gate",
          gateId,
          question,
          options: ["Approve", "Reject"],
        });

        if (!toolGateDelivered) {
          deps.notifyOfflineUser(ctx.userId, {
            type: "review_gate",
            conversationId: ctx.conversationId,
            agentName: ctx.leaderId ?? "Agent",
            question,
          }).catch((err) =>
            log.error(
              { userId: ctx.userId, err },
              "Offline notification failed (tool gate)",
            ),
          );
        }

        await deps.updateConversationStatus(ctx.conversationId, "waiting_for_user");

        const selection = await deps.abortableReviewGate(
          ctx.session,
          gateId,
          options.signal,
          undefined,
          ["Approve", "Reject"],
        );

        await deps.updateConversationStatus(ctx.conversationId, "active");

        const decision = selection === "Approve" ? "approved" : "rejected";
        log.info(
          {
            sec: true,
            tool: toolName,
            tier,
            decision,
            repo: `${ctx.repoOwner}/${ctx.repoName}`,
          },
          "Platform tool gated",
        );

        if (selection !== "Approve") {
          logPermissionDecision(
            "canUseTool-platform-gated",
            toolName,
            "deny",
            "user rejected",
          );
          return {
            behavior: "deny" as const,
            message: "User rejected the action",
          };
        }

        logPermissionDecision(
          "canUseTool-platform-gated",
          toolName,
          "allow",
          "user approved",
        );
        return allow(toolInput);
      }

      // auto-approve: read-only tools pass through
      log.info(
        {
          sec: true,
          tool: toolName,
          tier,
          decision: "auto-approved",
          repo: `${ctx.repoOwner}/${ctx.repoName}`,
        },
        "Platform tool auto-approved",
      );
      logPermissionDecision("canUseTool-platform-auto", toolName, "allow");
      return allow(toolInput);
    }

    // Plugin MCP tools — allow only when the server is registered in
    // plugin.json. Explicit server-name matching (not blanket mcp__ prefix).
    // See learning: 2026-04-06-mcp-tool-canusertool-scope-allowlist.md
    if (
      toolName.startsWith("mcp__plugin_soleur_") &&
      ctx.pluginMcpServerNames.some((server) =>
        toolName.startsWith(`mcp__plugin_soleur_${server}__`),
      )
    ) {
      log.info(
        { sec: true, toolName, agentId: options.agentID },
        "Plugin MCP tool invoked",
      );
      logPermissionDecision("canUseTool-plugin-mcp", toolName, "allow");
      return allow(toolInput);
    }

    // Deny-by-default: block unrecognized tools
    logPermissionDecision(
      "canUseTool-deny-default",
      toolName,
      "deny",
      "unrecognized tool",
    );
    return {
      behavior: "deny" as const,
      message: "Tool not permitted in this environment",
    };
  };
}
