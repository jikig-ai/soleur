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
import { getToolTier, buildGateMessage, buildOfflineGateMessage, type ToolTier } from "./tool-tiers";
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
import { redactCommandForDisplay } from "@/lib/safety/redaction-allowlist";
import { isSupportAllowedSkill } from "./support-directive";
import { denySupport } from "./support-escalation";
import { SUPPORT_AGENT_SESSION_HINT } from "@/lib/support-handoff";
import type { Persona } from "./workspace-mode";

// Write-class file tools denied (with escalation record) on support personas —
// the read-class file tools (Read/Glob/Grep/LS/NotebookRead) stay on the normal
// containment flow because kb-search's corpus path needs them. MultiEdit is
// schema-removed AND not a FILE_TOOLS member (deny-by-default covers it), but
// listing it here is harmless future-proofing if it ever joins the set.
const SUPPORT_WRITE_FILE_TOOLS = new Set<string>([
  "Write",
  "Edit",
  "MultiEdit",
  "NotebookEdit",
]);

// The support deny message that names the concrete next surface — one site
// owns the literal so the model-relayed prose, the rendered link, and the
// directive can never drift.
const SUPPORT_BASH_DENY_MESSAGE = `This chat is read-only app help — I can't run that command. For engineering work, ${SUPPORT_AGENT_SESSION_HINT}.`;

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

// Safe-Bash allowlist regex grammar + `isBashCommandSafe` live in
// `./safe-bash.ts`. Re-exported here so existing downstream consumers
// keep working without an import-path churn. The near-miss telemetry
// WeakMap stays in THIS file because it is keyed by `CanUseToolContext`,
// which is declared below — moving it out would force a cyclic import.
import {
  isBashCommandSafe,
  SAFE_BASH_PATTERNS,
  SAFE_BASH_NEAR_MISS_PREFIX,
} from "./safe-bash";
export { isBashCommandSafe, SAFE_BASH_PATTERNS };

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
    /**
     * P1 — gate kind. The first-run disclosure HOLD passes
     * `"autonomous_disclosure"` so the cc-dispatcher registers the gate under
     * that kind; the matching `autonomous_disclosure_response` is then the ONLY
     * frame that can release it. Omitted/`"review"` for every normal gate. A
     * cross-kind response frame is a no-op (see `resolveCcBashGate`).
     */
    gateKind?: "review" | "autonomous_disclosure",
  ) => Promise<string>;
  /**
   * feat-bash-autonomous-default-on — defense-in-depth consent re-check. The
   * disclosure-hold path calls this AFTER the gate resolves "proceed" to verify
   * the per-workspace ack was actually persisted before `allow()`. If the ack
   * is still null (e.g. a `review_gate_response` somehow released the gate
   * without writing the ack, or a transient ack-write fault), the command is
   * re-held/denied rather than allowed. Resolves the ISO ack timestamp or null.
   * Optional: when unwired (legacy runner / tests that don't exercise the hold)
   * the disclosure path is unreachable anyway (`bashAutonomous` false).
   */
  verifyAutonomousAck?: () => Promise<string | null>;
  /**
   * P1 — stale in-session ack snapshot fix. `autonomousAckAt` is frozen at
   * cold-start. After the owner acks the disclosure mid-dispatch, nothing
   * mutates that frozen value, so command #2 in the SAME conversation would
   * re-hold. When wired, this getter returns the LIVE in-session ack posture
   * (epoch ms | null) — flipped to non-null by the ws-handler on a successful
   * ack-release. The Bash branch consults this BEFORE the snapshot so a
   * post-ack command is friction-free. Unwired ⇒ falls back to the snapshot.
   */
  resolveAckPosture?: () => number | null;
  sendToClient: (userId: string, payload: WSMessage) => boolean;
  // #6802 (M4): returns whether the notification was delivered on at least one
  // channel. permission-callback's 3 call sites are fire-and-forget (they
  // dispatch tool/review_gate payloads, out of the statutory must-not-fail
  // fallback class) and ignore the return — but the injected-dependency type
  // wraps in Promise, so tsc rejects a `Promise<void>` slot for the widened fn.
  notifyOfflineUser: (
    userId: string,
    payload: NotificationPayload,
  ) => Promise<boolean>;
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
  /**
   * Issue B part 2 — per-workspace "autonomous / trusted" toggle. When true,
   * the Bash branch auto-approves every NON-BLOCKED command (skips the
   * review-gate). `isBashCommandBlocked` stays AUTHORITATIVE even under
   * autonomy: the toggle bypasses ONLY the review-gate, NEVER the blocklist
   * (sudo/curl/wget/nc/sh -c/eval/base64 -d//dev/tcp). Off (undefined/false)
   * preserves the existing review-gate behavior. Threaded from cc-dispatcher
   * via `resolveBashAutonomous` (fail-closed false), analogous to
   * `bashApprovalCache`. Default-deny: a missing dep is non-autonomous.
   */
  bashAutonomous?: boolean;
  /**
   * feat-bash-autonomous-default-on — per-workspace first-run consent ack
   * timestamp (epoch ms) or `null`/`undefined` = NOT yet acked. Resolved by
   * `resolveAutonomousAck` (fail-closed null = HOLD). When `bashAutonomous` is
   * true but this is null AND the caller is the workspace owner, the FIRST
   * non-blocked Bash command is HELD behind a one-time disclosure ack instead
   * of auto-running. After the owner acks (the held gate resolves) the command
   * proceeds and all subsequent auto-runs are friction-free.
   */
  autonomousAckAt?: number | null;
  /**
   * feat-bash-autonomous-default-on — whether the caller owns the active
   * workspace. The soft-gate disclosure ack is an ownership-grade decision
   * (mirrors 097's owner-only write). A non-owner hitting the first auto-run on
   * an un-acked workspace falls through to the review-gate (treated as
   * not-autonomous) rather than being shown an ack button they cannot use.
   */
  isOwner?: boolean;
  /**
   * #9556 — whether the dispatching workspace had a connected repo when the
   * dispatch resolved it (`repoUrl !== null` in cc-dispatcher — the SAME read
   * every dispatch already performs, so zero added DB reads). The closure-local
   * `deny()` wrapper below stamps it onto every support escalation record so
   * the route's `support_handoff` frame carries it and the rendered copy can
   * degrade honestly for repo-less users. Optional: dep-less contexts (unit
   * tests, any future runner that builds deps without the field) leave it
   * unwired — the record stores `undefined`, the emitted frame omits the
   * field, and the copy falls back to the legacy caveat arm. `undefined` also
   * occurs on a WIRED dep whose dispatch-time read resolved degraded (a
   * transient blip, not an honest "no repo" — see cc-dispatcher), so in
   * production the flag is {true, false, undefined}, not a bare boolean.
   * (The legacy `agent-runner.ts` construction is NOT such a producer: it
   * hard-pins `command_center` and never sets `persona`, so it cannot reach
   * a support deny at all.)
   */
  repoConnected?: boolean;
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
  /**
   * Dispatch persona (feat-wire-concierge-support-chat, ADR-113). `"support"`
   * scopes the Skill surface to `SUPPORT_SKILL_ALLOWLIST` (default-deny). Undefined
   * = the Command Center default (every Skill flows through `isSafeTool`). This is
   * defense-in-depth for a model that emits a non-loaded skill despite the SDK
   * `Options.skills` filter; the deny returns a user-relayable message (NOT a
   * silent removal — ADR-070 reconciliation). Accepts the full `Persona` union
   * ("command_center" | "support"); only `"support"` scopes the Skill surface.
   */
  persona?: Persona;
  deps: CanUseToolDeps;
}

export function createCanUseTool(ctx: CanUseToolContext): CanUseTool {
  const { deps } = ctx;
  // #9556 — one injection point for the deny→handoff flag: every support deny
  // path THAT ESCALATES calls `deny(`, which stamps the dispatch-resolved
  // repo-connected state onto the escalation record. (The deliberately
  // NON-escalating support denies below — `AskUserQuestion`,
  // `TodoWrite`/`ExitPlanMode` and the other UX-signal belts — bypass `deny(`;
  // recording an escalation for them would emit a spurious support_handoff
  // frame, the very thing their "no interactive surface" comments forbid.)
  // This mirrors denySupport's own contract ("every present and future
  // escalating support deny path gets record + telemetry for free") one level
  // up — a future deny site that calls `deny(` cannot forget the field.
  // The spread order makes deps.repoConnected authoritative even if a call site
  // passed its own; an unwired dep records `undefined` (the frame then omits
  // the field → legacy copy arm).
  const deny = (
    opts: Parameters<typeof denySupport>[0],
  ): ReturnType<typeof denySupport> =>
    denySupport({ ...opts, repoConnected: deps.repoConnected });
  return async (toolName, toolInput, options): Promise<PermissionResult> => {
    const subagentCtx = options.agentID ? ` [subagent=${options.agentID}]` : "";

    // Defense-in-depth: catch any file tool that bypasses PreToolUse hooks.
    // Hooks are the primary enforcement (layer 1); this is layer 2. See #891.
    if (isFileTool(toolName)) {
      // Support persona (#9539): write-class file tools are schema-removed via
      // SUPPORT_EXTRA_DISALLOWED_TOOLS; a model emitting one anyway is an
      // engineering attempt — deny + record rather than letting the sandbox
      // reject the write AFTER a `diff`/`notebook_edit` frame already went to
      // the WS sink. Read-class file tools flow through containment below.
      if (ctx.persona === "support" && SUPPORT_WRITE_FILE_TOOLS.has(toolName)) {
        return deny({
          conversationId: ctx.conversationId,
          toolName,
          source: "tool",
          message: `This chat is read-only app help — I can't edit or write files. For engineering work, ${SUPPORT_AGENT_SESSION_HINT}.`,
        });
      }
      const filePath = extractToolPath(toolInput);
      if (filePath && !isPathInWorkspace(filePath, ctx.workspacePath)) {
        if (ctx.persona === "support") {
          return deny({
            conversationId: ctx.conversationId,
            toolName,
            source: "tool",
            message: `This chat is read-only app help — that path is outside my reach. For engineering work, ${SUPPORT_AGENT_SESSION_HINT}.`,
            detail: "outside workspace",
          });
        }
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
      // Support persona (#9539): the gate below emits `review_gate` over
      // `deps.sendToClient` — the WS sink — which a support-panel user can
      // never answer (the SSE turn dies at the route cap while the gate
      // stalls for REVIEW_GATE_TIMEOUT_MS, then auto-allows with a
      // synthesized selection). Schema removal (`SUPPORT_EXTRA_DISALLOWED_
      // TOOLS`) is the primary lever; this belt covers a model emitting a
      // removed tool. NO escalation record — a clarifying question is not an
      // engineering attempt.
      if (ctx.persona === "support") {
        log.info(
          {
            sec: true,
            tool: toolName,
            decision: "deny-support-question",
            conversationId: ctx.conversationId,
          },
          "Support persona denied an interactive question (no gate surface)",
        );
        logPermissionDecision(
          "canUseTool-support-question",
          toolName,
          "deny",
          "no interactive surface",
        );
        return {
          behavior: "deny" as const,
          message:
            "This chat can't render interactive questions — ask the user directly in your reply text.",
        };
      }
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

    // Support persona (#9539): TodoWrite / ExitPlanMode are schema-removed
    // (SUPPORT_EXTRA_DISALLOWED_TOOLS) AND filtered from `allowedTools` for
    // support dispatches — either reaching here means a model emitted a
    // removed tool AND slipped the auto-approve filter, which is exactly the
    // case the AskUserQuestion belt hedges. Deny WITHOUT an escalation
    // record (a UX signal is not an engineering attempt).
    if (
      ctx.persona === "support" &&
      (toolName === "TodoWrite" ||
        toolName === "ExitPlanMode" ||
        SOLEUR_GO_SAFE_UX_TOOLS.has(toolName))
    ) {
      log.info(
        {
          sec: true,
          tool: toolName,
          decision: "deny-support-question",
          conversationId: ctx.conversationId,
        },
        "Support persona denied a UX-signal tool (no interactive surface)",
      );
      logPermissionDecision(
        "canUseTool-support-question",
        toolName,
        "deny",
        "no interactive surface",
      );
      return {
        behavior: "deny" as const,
        message:
          "This chat can't render interactive prompts — answer in plain text instead.",
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
        // Support persona: a blocklisted attempt is still a write attempt —
        // deny with the handoff message AND record the escalation so the
        // turn ends with the "Ask an agent" affordance rather than a bare
        // pattern-mismatch dead-end.
        if (ctx.persona === "support") {
          return deny({
            conversationId: ctx.conversationId,
            toolName,
            source: "bash",
            message: SUPPORT_BASH_DENY_MESSAGE,
            detail: "BLOCKED_BASH_PATTERNS match",
          });
        }
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

      // Support persona (#9539): a non-safe Bash command on a support turn
      // must never reach any interactive gate — every path below emits over
      // `deps.sendToClient`, the WS sink a support-panel user cannot answer:
      // the review-gate (stalls REVIEW_GATE_TIMEOUT_MS while the SSE turn
      // dies at the route cap), the autonomous-disclosure hold (a consent ack
      // granted on the WRONG surface), and — on an acked autonomous
      // workspace — the silent auto-allow itself (the command would EXECUTE
      // inside the read-only sandbox, still inside the WS-emit blast radius
      // of `notifyOfflineUser` + `waiting_for_user` writes). Deny here,
      // record the escalation, and let the route render the handoff
      // affordance at turn end.
      if (ctx.persona === "support") {
        return deny({
          conversationId: ctx.conversationId,
          toolName,
          source: "bash",
          message: SUPPORT_BASH_DENY_MESSAGE,
        });
      }

      // Issue B part 2 — autonomous/trusted bypass. Placed AFTER the
      // blocklist (deny, above) and AFTER isBashCommandSafe + near-miss
      // telemetry (so the drift signal still fires) but BEFORE the
      // batched-cache/review-gate. When the workspace is autonomous, every
      // command that survived the blocklist auto-approves with no gate. The
      // blocklist remains authoritative: sudo/curl/wget/nc/sh -c/eval/
      // base64 -d//dev/tcp were already denied above and never reach here.
      if (deps.bashAutonomous) {
        // feat-bash-autonomous-default-on — FIRST-RUN CONSENT SOFT-GATE.
        // A default-ON workspace whose owner has NOT yet acked the disclosure
        // must HOLD the first non-blocked command (not silently auto-run it).
        // Owner only: a non-owner on an un-acked autonomous workspace falls
        // through to the review-gate below (treat as not-autonomous — no ack
        // button they can't use). The blocklist already ran above, so this
        // hold only ever fires for a command that survived the denylist.
        // P1 — consult the LIVE in-session ack posture first (flipped non-null
        // by the ws-handler on a successful ack-release) so command #2 after an
        // ack does not re-hold on the frozen cold-start snapshot. Fall back to
        // the snapshot when the getter is unwired.
        const livePosture = deps.resolveAckPosture
          ? deps.resolveAckPosture()
          : deps.autonomousAckAt;
        const unAcked = livePosture == null;
        if (unAcked && deps.isOwner) {
          const gateId = randomUUID();
          log.info(
            {
              sec: true,
              tool: toolName,
              decision: "autonomous-disclosure-hold",
              repo: `${ctx.repoOwner}/${ctx.repoName}`,
            },
            "Bash command HELD for first-run autonomous disclosure ack",
          );
          // Decision-log enum is binary (allow|deny); a HOLD is logged as a
          // (provisional) deny until the owner acks. The structured `log.info`
          // line above carries the `autonomous-disclosure-hold` decision tag
          // for the liveness grep.
          logPermissionDecision(
            "canUseTool-bash",
            toolName,
            "deny",
            "autonomous-disclosure-hold",
          );
          // Emit the disclosure frame (mirrors the review_gate emit). For a
          // default-ON workspace this is the single "Got it" ack surface;
          // `existingWorkspace` is reserved for the stored-`false` opt-out path
          // which fires through the review-gate branch (bashAutonomous false).
          deps.sendToClient(ctx.userId, {
            type: "autonomous_disclosure",
            gateId,
            existingWorkspace: false,
          });
          await deps.updateConversationStatus(
            ctx.conversationId,
            "waiting_for_user",
          );
          // Await the owner's ack via the same gate bridge the review-gate uses
          // (registered in `_ccBashGates`; resolved by the
          // `autonomous_disclosure_response` ws-handler case). The selection
          // distinguishes "Got it" / "Keep autonomous on" (proceed) from
          // "Ask me each time" (decline this run).
          const selection = await deps.abortableReviewGate(
            ctx.session,
            gateId,
            options.signal,
            undefined,
            ["Got it"],
            // P1 — register the HOLD under the autonomous_disclosure kind so a
            // forged/cross `review_gate_response` cannot release it; only the
            // owner-checked `autonomous_disclosure_response` (which writes the
            // ack first) can.
            "autonomous_disclosure",
          );
          await deps.updateConversationStatus(ctx.conversationId, "active");

          if (selection === "Ask me each time") {
            logPermissionDecision(
              "canUseTool-bash",
              toolName,
              "deny",
              "autonomous-disclosure-declined",
            );
            return {
              behavior: "deny" as const,
              message: "User chose to approve each command; this run was held.",
            };
          }
          // P1 defense-in-depth — the gate resolved "proceed", but consent is
          // only honored when the ack was ACTUALLY persisted. Re-read it before
          // allowing: a release that did not write the ack (cross-frame attempt
          // that slipped the kind check, or a transient ack-write fault) must
          // re-HOLD/deny rather than auto-run the command without recorded
          // consent. Fail-closed: a null/throwing re-check denies.
          if (deps.verifyAutonomousAck) {
            let persistedAck: string | null = null;
            try {
              persistedAck = await deps.verifyAutonomousAck();
            } catch (err) {
              warnSilentFallback(err, {
                feature: "cc-permissions",
                op: "autonomous-ack-verify",
              });
              persistedAck = null;
            }
            if (persistedAck == null) {
              log.warn(
                {
                  sec: true,
                  tool: toolName,
                  decision: "autonomous-disclosure-ack-unverified",
                  repo: `${ctx.repoOwner}/${ctx.repoName}`,
                },
                "Disclosure gate released but ack not persisted; re-holding (deny)",
              );
              logPermissionDecision(
                "canUseTool-bash",
                toolName,
                "deny",
                "autonomous-disclosure-ack-unverified",
              );
              return {
                behavior: "deny" as const,
                message:
                  "Consent acknowledgement was not recorded; the command was held. Please try again.",
              };
            }
          }
          log.info(
            {
              sec: true,
              tool: toolName,
              decision: "autonomous-disclosure-released",
              repo: `${ctx.repoOwner}/${ctx.repoName}`,
            },
            "First-run autonomous disclosure acked; releasing held command",
          );
          logPermissionDecision(
            "canUseTool-bash",
            toolName,
            "allow",
            "autonomous-disclosure-released",
          );
          return allow(toolInput);
        }
        if (unAcked && !deps.isOwner) {
          // Non-owner on an un-acked autonomous workspace: fall through to the
          // review-gate below (do NOT auto-bypass, do NOT surface an ack the
          // member can't grant).
        } else {
          log.info(
            {
              sec: true,
              tool: toolName,
              decision: "autonomous-bypass",
              repo: `${ctx.repoOwner}/${ctx.repoName}`,
            },
            "Bash command auto-approved via workspace autonomous toggle",
          );
          logPermissionDecision(
            "canUseTool-bash",
            toolName,
            "allow",
            "autonomous-bypass",
          );
          return allow(toolInput);
        }
      }

      // feat-bash-autonomous-default-on — EXISTING-workspace opt-out (P3 wire).
      // A pre-consent-model workspace stored `bash_autonomous=false` with NO ack:
      // the owner has never seen the autonomous disclosure. On their FIRST
      // non-blocked command, HOLD it once and surface the opt-out
      // (`existingWorkspace:true`):
      //   - "Keep autonomous on" ⇒ the ws-handler flips the toggle ON + writes
      //     the ack; this run proceeds (allow, after the ack re-check).
      //   - "Ask me each time"   ⇒ the ws-handler writes the ack (leaves the
      //     toggle off); this run FALLS THROUGH to the normal review-gate below
      //     (manual approve), and future commands stay on the review-gate.
      // Owner-only: a non-owner falls straight to the review-gate (no ack button
      // they can't grant). Reuses the kind-tagged gate registry + the ack
      // re-check. The blocklist already ran above, so this only holds a command
      // that survived the denylist.
      {
        const livePosture = deps.resolveAckPosture
          ? deps.resolveAckPosture()
          : deps.autonomousAckAt;
        if (
          !deps.bashAutonomous &&
          livePosture == null &&
          deps.isOwner
        ) {
          const gateId = randomUUID();
          log.info(
            {
              sec: true,
              tool: toolName,
              decision: "autonomous-disclosure-hold",
              repo: `${ctx.repoOwner}/${ctx.repoName}`,
            },
            "Bash command HELD for existing-workspace autonomous opt-out",
          );
          logPermissionDecision(
            "canUseTool-bash",
            toolName,
            "deny",
            "autonomous-disclosure-hold",
          );
          deps.sendToClient(ctx.userId, {
            type: "autonomous_disclosure",
            gateId,
            existingWorkspace: true,
          });
          await deps.updateConversationStatus(
            ctx.conversationId,
            "waiting_for_user",
          );
          const selection = await deps.abortableReviewGate(
            ctx.session,
            gateId,
            options.signal,
            undefined,
            ["Keep autonomous on", "Ask me each time"],
            "autonomous_disclosure",
          );
          await deps.updateConversationStatus(ctx.conversationId, "active");

          if (selection === "Keep autonomous on") {
            // The ws-handler flipped the toggle + wrote the ack. Verify the ack
            // actually persisted (defense-in-depth) before allowing this run.
            if (deps.verifyAutonomousAck) {
              let persistedAck: string | null = null;
              try {
                persistedAck = await deps.verifyAutonomousAck();
              } catch (err) {
                warnSilentFallback(err, {
                  feature: "cc-permissions",
                  op: "autonomous-ack-verify-existing",
                });
                persistedAck = null;
              }
              if (persistedAck == null) {
                logPermissionDecision(
                  "canUseTool-bash",
                  toolName,
                  "deny",
                  "autonomous-disclosure-ack-unverified",
                );
                return {
                  behavior: "deny" as const,
                  message:
                    "Consent acknowledgement was not recorded; the command was held. Please try again.",
                };
              }
            }
            log.info(
              {
                sec: true,
                tool: toolName,
                decision: "autonomous-disclosure-released",
                repo: `${ctx.repoOwner}/${ctx.repoName}`,
              },
              "Existing-workspace opt-out: kept autonomous on; releasing command",
            );
            logPermissionDecision(
              "canUseTool-bash",
              toolName,
              "allow",
              "autonomous-disclosure-released",
            );
            return allow(toolInput);
          }
          // "Ask me each time" (or any non-keep selection): the ack is written
          // server-side; fall through to the review-gate below for THIS run.
          log.info(
            {
              sec: true,
              tool: toolName,
              decision: "autonomous-disclosure-opt-out",
              repo: `${ctx.repoOwner}/${ctx.repoName}`,
            },
            "Existing-workspace opt-out: ask-each-time; falling through to review-gate",
          );
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
      // FIX 1 (P1) — redact BEFORE building the preview. The raw command can
      // carry `ghs_…` / `GH_TOKEN=<value>` / `Authorization: …` verbatim; the
      // shared `question` flows to BOTH sendToClient(review_gate) AND
      // notifyOfflineUser, so an un-redacted preview leaks the credential on
      // both sinks (the screenshot leak). redactCommandForDisplay is the same
      // emit-boundary gate used by the command_stream path (TR4).
      const redactedCommand = redactCommandForDisplay(command);
      const preview =
        redactedCommand.length > 200
          ? `${redactedCommand.slice(0, 200)}…`
          : redactedCommand;
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
      // Support persona (#9539): `Agent` is schema-removed for support; an
      // emitted-despite-removal call is engineering fan-out on a read-only
      // turn — deny + record.
      if (ctx.persona === "support") {
        return deny({
          conversationId: ctx.conversationId,
          toolName,
          source: "tool",
          message: `This chat is read-only app help — I can't spawn engineering agents. For engineering work, ${SUPPORT_AGENT_SESSION_HINT}.`,
        });
      }
      if (subagentCtx) {
        log.info(
          { sec: true, agentId: options.agentID },
          "Agent tool invoked by subagent",
        );
      }
      logPermissionDecision("canUseTool-agent", toolName, "allow");
      return allow(toolInput);
    }

    // Support-persona Skill allowlist (feat-wire-concierge-support-chat, ADR-113).
    // Placed BEFORE the `isSafeTool` allow (which whitelists "Skill" wholesale) so
    // a support turn can only invoke a support-appropriate skill. Default-deny: a
    // Skill call is allowed only if the (bare↔FQN-normalized) name ∈
    // SUPPORT_SKILL_ALLOWLIST ({kb-search}); everything else denies with a clear,
    // model-relayable message (NOT a silent removal — ADR-070). Defense-in-depth
    // for the emit-a-non-loaded-skill case; the SDK `Options.skills` filter is the
    // primary lever. Non-support personas are unaffected (fall through to isSafeTool).
    if (ctx.persona === "support" && toolName === "Skill") {
      const requested =
        typeof (toolInput as { skill?: unknown }).skill === "string"
          ? ((toolInput as { skill: string }).skill)
          : "";
      if (isSupportAllowedSkill(requested)) {
        logPermissionDecision("canUseTool-support-skill", toolName, "allow", requested);
        return allow(toolInput);
      }
      return deny({
        conversationId: ctx.conversationId,
        toolName,
        source: "skill",
        message: `Support can only use app-help (knowledge-base search). For engineering work — building, fixing, or deploying — ${SUPPORT_AGENT_SESSION_HINT}.`,
        detail: requested || "(missing)",
      });
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
      // Support persona (#9539): a platform tool is repo-capable by
      // construction (its gated tier emits a `review_gate` on the WS sink;
      // its auto-approve tier executes unconditionally). For support
      // dispatches `platformToolNames` is empty — this belt is for a future
      // tool added to the list without a persona check.
      if (ctx.persona === "support") {
        return deny({
          conversationId: ctx.conversationId,
          toolName,
          source: "tool",
          message: `This chat is read-only app help — that integration isn't available here. For engineering work, ${SUPPORT_AGENT_SESSION_HINT}.`,
        });
      }
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
            question: buildOfflineGateMessage(toolName, toolInput),
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
    if (ctx.persona === "support") {
      return deny({
        conversationId: ctx.conversationId,
        toolName,
        source: "tool",
        message: `This chat is read-only app help — I can't do that here. For engineering work, ${SUPPORT_AGENT_SESSION_HINT}.`,
        detail: "unrecognized tool",
      });
    }
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
