// Lazy singletons + orchestration layer for the Command Center
// `/soleur:go` runner. ws-handler delegates here; this module owns the
// per-process PendingPromptRegistry, StartSessionRateLimiter, and
// SoleurGoRunner instances.
//
// `realSdkQueryFactory` binds the real-SDK `query()` from
// `@anthropic-ai/claude-agent-sdk` — this is the always-on production
// cc-soleur-go runner. Originally gated behind FLAG_CC_SOLEUR_GO=1; the
// flag was retired in #3270 once the soak window (ADR-022) confirmed the
// new path. See plan
// `2026-04-27-feat-stage-2-12-real-sdk-query-factory-binding-plan.md`.
//
// V2 follow-ups tracked in #2853 backlog (V2-13: tier-classify in-process
// MCP servers for cc-soleur-go path — referenced in factory body).

import { randomUUID } from "crypto";
import { existsSync } from "node:fs";
import path from "path";

import type { Query } from "@anthropic-ai/claude-agent-sdk";
import { query as sdkQuery, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import {
  buildC4ConciergeTools,
  EDIT_C4_DIAGRAM_TOOL,
} from "@/server/c4-concierge-tools";
import {
  getRuntimeFlag,
  isDebugModeAvailable,
  type Role,
} from "@/lib/feature-flags/server";
import { C4_VISUALIZER_FLAG } from "@/lib/c4-constants";

import { applyPrefillGuard } from "./agent-prefill-guard";

import type { WSMessage, Conversation, AttachmentRef } from "@/lib/types";
import { KeyInvalidError, STATUS_LABELS } from "@/lib/types";
import { persistAndDownloadAttachments } from "./attachment-pipeline";

/**
 * Runtime allowlist for `Conversation["status"]`. Mirrors the type union
 * `"active" | "waiting_for_user" | "completed" | "failed"` and is derived
 * from `STATUS_LABELS` so a future status added to the type and labels
 * map flows through automatically.
 */
const CONVERSATION_STATUS_VALUES = new Set(Object.keys(STATUS_LABELS));
import {
  createSoleurGoRunner,
  type SoleurGoRunner,
  type QueryFactory,
  type QueryFactoryArgs,
  type DispatchEvents,
  type WorkflowEnd,
} from "./soleur-go-runner";
import { readCcCostCaps } from "./cc-cost-caps";
import { checkpointInflightWorkForConversation } from "./inflight-checkpoint";
import {
  WORKFLOW_END_USER_MESSAGES,
  resolveWorktreeEnterFailedMessage,
} from "./cc-workflow-end-messages";
import { reprovisionWorkspaceOnDispatch } from "./cc-reprovision";
import type { ReprovisionOutcome } from "./ensure-workspace-repo";
import { persistTurnCost } from "./cost-writer";
import { PendingPromptRegistry } from "./pending-prompt-registry";
import {
  createStartSessionRateLimiter,
  type StartSessionRateLimiter,
} from "./start-session-rate-limit";
import {
  handleInteractivePromptResponse,
  pruneTombstonesFor,
  type HandleInteractivePromptResponseResult,
} from "./cc-interactive-prompt-response";
type InteractivePromptEvent = Extract<WSMessage, { type: "interactive_prompt" }>;
type InteractivePromptResponse = Extract<WSMessage, { type: "interactive_prompt_response" }>;
import {
  type ConversationRouting,
  type WorkflowName,
} from "./conversation-routing";
import {
  reportSilentFallback,
  warnSilentFallback,
  mirrorWithDebounce,
  mirrorP0Deduped,
  __resetMirrorDebounceForTests,
} from "./observability";
import { redactCommandForDisplay } from "../lib/safety/redaction-allowlist";
import { CC_ROUTER_TIER3_DENYLIST } from "./tool-tiers";
import { updateConversationFor } from "./conversation-writer";
import {
  getUserServiceTokens,
  patchWorkspacePermissions,
} from "./agent-runner";
// Issue A (Concierge gh-auth): mint a per-workspace GitHub App installation
// token and inject it as GH_TOKEN so the agent's `gh` calls authenticate
// without `gh auth login`. resolveInstallationId is the membership-checked
// per-workspace resolver (ADR-044) — NOT the soleur-monorepo-hardcoded
// `mintInstallationToken` from the crons. Per hr-github-app-auth-not-pat.
import { resolveInstallationId } from "./resolve-installation-id";
import { generateInstallationToken } from "./github-app";
import { resolveEffectiveInstallationId } from "./cc-effective-installation";
// Session-start self-heal: if the active workspace has a connected repo but no
// matching clone on disk, clone/repair it so the Concierge has a real git repo
// to work in (fixes the "No git repository found" blocker). Generic per-user.
import { getCurrentRepoUrl } from "./current-repo-url";
import {
  ensureWorkspaceRepoCloned,
  ensureWorkspaceDirExists,
} from "./ensure-workspace-repo";
// Issue B part 2 — per-workspace autonomous Bash toggle (fail-closed read).
import { resolveBashAutonomous } from "./resolve-bash-autonomous";
import { resolveDebugMode } from "./resolve-debug-mode";
import { emitDebugEvent } from "./debug-event";
// feat-bash-autonomous-default-on — first-run consent soft-gate inputs:
// the ack timestamp (fail-closed null = HOLD) + workspace-ownership (fail-closed
// not-owner = review-gate fallback).
import { resolveAutonomousAck } from "./resolve-autonomous-ack";
import { resolveIsWorkspaceOwner } from "./resolve-workspace-owner";
// PR-C §2.11 (#3244): BYOK lease wrap on realSdkQueryFactory — the
// plaintext API key fetch surface moves from `getUserApiKey(userId)`
// (which returns a bare string) to `lease.getApiKey()` inside
// `runWithByokLease`. Closes #3392 (cc-dispatcher BYOK item).
import {
  MissingByokKeyError,
  reportMissingByokKey,
} from "./byok-lease";
// BYOK Delegations PR-A (#4232): see note at agent-runner.ts.
import { resolveKeyOwnerThenLease } from "./byok-resolver";
import {
  getFreshTenantClient,
  RuntimeAuthError,
} from "@/lib/supabase/tenant";
import { tryEmitRevocationNotice } from "./revocation-emit";
import {
  fetchUserWorkspacePath,
  resolveConciergeDocumentContext,
  _resetWorkspacePathCacheForTests,
} from "./kb-document-resolver";
import type { DocumentExtractMeta } from "./kb-document-resolver";
import type { PdfExtractErrorClass } from "./pdf-text-extract";

// Re-export so existing call sites keep working.
export { resolveConciergeDocumentContext } from "./kb-document-resolver";
import { buildAgentQueryOptions } from "./agent-runner-query-options";
// In-sandbox raw-git credential path (plan item 1). `writeAskpassScriptTo`
// writes the fixed-body GIT_ASKPASS helper UNDER the user's `workspacePath`
// (the only verified sandbox-readable allowWrite dir); the token rides
// GIT_INSTALLATION_TOKEN env, never the script body. NEVER logged.
import { writeAskpassScriptTo } from "./git-auth";
import { buildToolProgressWSMessage, buildToolUseWSMessage } from "./tool-labels";
import {
  getBashApprovalCache,
  _resetBashApprovalCacheForTests,
} from "./permission-callback-bash-batch";
import {
  createCanUseTool,
  type CanUseToolDeps,
} from "./permission-callback";
import { abortableReviewGate, type AgentSession } from "./review-gate";
import { sendToClient as defaultSendToClient } from "./ws-handler";
import { notifyOfflineUser } from "./notifications";
import { createChildLogger } from "./logger";

const log = createChildLogger("cc-dispatcher");

// Floor lifetime for the minted GH_TOKEN (Issue A). A warm-cache token must
// outlast a long interactive agent turn so `gh` doesn't fail mid-conversation
// on an expired token. Mirrors the cron's TOKEN_MIN_LIFETIME_MS (~60 min).
const GH_TOKEN_MIN_LIFETIME_MS = 60 * 60 * 1000;

// Non-routable internal leader id reserved for cc-soleur-go path
// audit-log attribution. Used by `createCanUseTool` (R-AC14), the WS
// `stream`/`tool_use` events emitted from `dispatchSoleurGo`, and the
// `reportSilentFallback` extra in the sandbox-startup mirror branch.
//
// Source of truth lives in `@/lib/cc-router-id` so client-safe modules
// (leader-avatar.tsx, etc.) can import the same literal without dragging
// pino + supabase service client into the browser bundle.
export { CC_ROUTER_LEADER_ID } from "@/lib/cc-router-id";
import { CC_ROUTER_LEADER_ID } from "@/lib/cc-router-id";

// Sentry mirror debounce (`mirrorWithDebounce`) lives in `./observability`
// (#3369). Per-(userId, errorClass) 5-minute TTL prevents a misconfigured
// prod (1 QPS = 86k events/day per failure mode) from flooding Sentry.

/**
 * Read CC_MCP_ALLOWLIST and return the cc-router's mcpServers config (#2909).
 *
 * Phase 1 deny-by-default scaffolding (this PR): returns `{}` for empty /
 * unset / whitespace-only env. Throws plain Error if any short-name in the
 * env resolves to a member of `CC_ROUTER_TIER3_DENYLIST` (the 3 Plausible
 * tools — cross-tenant credentials by construction). Phase 1 does NOT yet
 * build a populated `soleur_platform` server even when valid non-denylist
 * names are present — promotion is Phase 2 (#3722).
 *
 * Denylist-check-first ordering is pinned: a mixed env value like
 * `"foo,plausible_create_site"` throws with the Plausible name in the
 * message regardless of position. Future unknown-name validation (Phase 2)
 * will fail-closed AFTER the denylist check.
 *
 * Exported for unit testability (`test/cc-mcp-tier-allowlist.test.ts`).
 *
 * @param env defaults to `process.env`; tests pass a synthetic record.
 */
export function readCcMcpAllowlist(
  env: Record<string, string | undefined> = process.env,
): Record<string, unknown> {
  const raw = env.CC_MCP_ALLOWLIST;
  if (raw === undefined || raw.trim() === "") return {};
  const names = raw
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
  for (const name of names) {
    const fqn = `mcp__soleur_platform__${name}`;
    if (CC_ROUTER_TIER3_DENYLIST.has(fqn)) {
      throw new Error(
        `CC_MCP_ALLOWLIST contains permanent Tier 3 denylist tool "${name}" — see CC_ROUTER_TIER3_DENYLIST in tool-tiers.ts`,
      );
    }
  }
  // Phase 1: even with valid non-denylist names present, return {} —
  // building the populated soleur_platform server lives in Phase 2 (#3722).
  return {};
}

/**
 * Return true when the cc-router iterator observes a `tool_use` block
 * referencing a `mcp__soleur_platform__*` tool that is NOT in the registered
 * platform-tool list (#2909 FR2 — Candidate B per Kieran SDK-source read).
 *
 * Background: when `mcpServers` is empty (Phase 1 default), the Claude
 * Agent SDK rejects unknown `mcp__soleur_platform__*` calls at
 * model-validation time and `canUseTool` is NEVER invoked. The SDK
 * returns a `tool_result` error to the model with no Sentry signal — a
 * silent-failure surface that violates `cq-silent-fallback-must-mirror-to-sentry`.
 * The router's SDK iterator hook (`onToolUse`) is the only observable
 * surface; this helper is the predicate.
 *
 * Exported for unit testability.
 */
export function shouldMirrorUnregisteredPlatformToolUse(
  toolName: string,
  registeredPlatformToolNames: readonly string[],
): boolean {
  if (!toolName.startsWith("mcp__soleur_platform__")) return false;
  return !registeredPlatformToolNames.includes(toolName);
}

/**
 * Registered platform tool names for the cc-router (#2909 FR2 + Phase 2 #3722
 * promotion hook). Phase 1: empty — `mcpServers === {}` via `readCcMcpAllowlist()`.
 * Phase 2: populated from `CC_MCP_ALLOWLIST` allowlist outcome. Module-level
 * constant so the iterator hook's `shouldMirrorUnregisteredPlatformToolUse`
 * predicate has a single named place to read, preventing drift between the
 * allowlist source and the mirror predicate at Phase 2 promotion time.
 */
const CC_REGISTERED_PLATFORM_TOOL_NAMES: readonly string[] = [];

// Validates a GitHub owner/repo segment before it is closed over into the
// edit_c4_diagram tool + system prompt — defense against a malformed/injected
// repoUrl (mirrors agent-runner.ts's GITHUB_NAME_RE).
const CC_GITHUB_NAME_RE = /^[a-zA-Z0-9._-]+$/;

// feat-one-shot-concierge-gh-403 — kills the model's FALSE-CONFIDENCE 403
// diagnosis. The Concierge runs `gh` inside the sandbox and, seeing a bare 403,
// used to invent "the installation lacks issues:write — file via the UI" and
// tell the user to re-consent. That is wrong: the org grant already exists; a
// 403 is almost always a wrong-installation token, which the platform heals
// server-side. This directive forbids the model from guessing a cause or
// dispensing GitHub-App-settings advice. Appended unconditionally to the
// Concierge system prompt (AC5 greps for the sentinel below).
const GH_403_PROMPT_DIRECTIVE =
  "## GitHub `gh` errors\n" +
  "If a `gh` command returns a 403 (Forbidden) or similar auth error, report " +
  "the LITERAL command output and HTTP status to the user verbatim. Do NOT " +
  "speculate about which permission or scope is missing, and do NOT tell the " +
  "user to change GitHub App permissions, approve new permissions, or " +
  "re-consent — the Soleur platform diagnoses and repairs installation/" +
  "permission issues server-side and will retry with the correct installation " +
  "automatically. State only what the error literally says.";

// #5041 follow-up — when no entitled GitHub token was minted for this
// dispatch, the sandbox network allowlist is empty and every gh/git network
// command dies at the proxy with a transport-shaped `Forbidden`. Without this
// addendum the unconditional directives above tell the agent it is
// authenticated and that the platform auto-heals 403s — both false in exactly
// this state — so it retries gh fruitlessly and relays a promise that will
// never be kept. Mirrors the capability-gated c4PromptAddendum pattern: tell
// the model about the capability it does NOT have.
const GH_NO_NETWORK_PROMPT_ADDENDUM =
  "## GitHub access unavailable in this session\n" +
  "No repository is connected to this workspace, so GitHub network access " +
  "is disabled for this session. Do NOT run `gh` or git network commands " +
  "(push/fetch/pull/ls-remote) — they will fail with a network error, and " +
  "the platform will not retry them. If the user asks for GitHub " +
  "operations, tell them to connect a repository first (Workspace settings " +
  "→ Connect repository).";

// feat-one-shot-concierge-workspace-repo-context — name the connected
// repository to the Concierge so it stops trying to infer owner/repo from a
// git origin remote. On a `.git`-less workspace `git config --get
// remote.origin.url` returns empty and the agent falsely concludes "no repo
// connected" and prompts the user — even though the workspace header plainly
// shows the connected repo. The server already resolves owner/repo from the
// active-workspace repo_url (ADR-044), so we surface it directly. Mirrors the
// leader path at agent-runner.ts:1429-1441 (lock-step the lead phrase "The
// connected repository is ${owner}/${repo}" so the two surfaces stay
// greppable together). PARITY: the static baseline counterpart is
// GH_AUTH_STATUS_GUIDANCE_DIRECTIVE in soleur-go-runner.ts — both tell the
// agent to pass `-R owner/repo` and never infer from a git remote; keep the
// two in lock-step.
//
// The `${owner}/${repo}` interpolation is safe because both are validated
// against CC_GITHUB_NAME_RE at the call site before assignment (see
// connectedOwner/connectedRepo resolution below) — no whitespace, backticks,
// `$`, `{`, newlines, or markdown fences can slip through. If that regex ever
// relaxes, this becomes a prompt-injection sink.
//
// Exported so the test suite can assert on the builder's OUTPUT directly
// (behavioral), not only on source-presence of the call site.
export function buildConnectedRepoContext(owner: string, repo: string): string {
  return (
    "## Connected repository\n" +
    `The connected repository is ${owner}/${repo}. For any repo gh operation, ` +
    `pass -R ${owner}/${repo} explicitly (for example: gh issue view 123 -R ` +
    `${owner}/${repo}). Use this value directly — do NOT try to infer the ` +
    "repository from a git remote or a .git directory; the workspace may not " +
    "contain one. The installation token resolves the repo server-side."
  );
}

// Max length cap for `block.name` before passing to Sentry/pino. Defense-in-
// depth against future model regressions that might emit pathologically long
// tool names; the SDK validation gate constrains names to the registered
// catalog today, so this is bounded but not impossible.
const MAX_TOOL_NAME_LEN_FOR_LOG = 128;

// feat-concierge-stream-commands — `command_stream` output caps (D4) + the
// UTF-8 byte-cap util. Definitions moved to `./command-stream-caps` so the
// debug-mode emit path can reuse them without a cc-dispatcher import cycle.
// Imported for internal use AND re-exported so every existing importer
// (tests, etc.) that pulls these from cc-dispatcher is unaffected.
import {
  COMMAND_STREAM_CHUNK_CAP_BYTES,
  COMMAND_STREAM_TOTAL_CAP_BYTES,
  COMMAND_STREAM_COMMAND_CAP_BYTES,
  COMMAND_STREAM_TRUNCATION_MARKER,
  capUtf8Bytes,
} from "./command-stream-caps";
export {
  COMMAND_STREAM_CHUNK_CAP_BYTES,
  COMMAND_STREAM_TOTAL_CAP_BYTES,
  COMMAND_STREAM_COMMAND_CAP_BYTES,
  COMMAND_STREAM_TRUNCATION_MARKER,
  capUtf8Bytes,
};

// Redaction-fallthrough probe markers (the four secret shapes the extended
// allowlist covers). If a redacted command/output STILL contains one of
// these substrings, redaction silently failed — a P0 credential-leak class
// surfaced to Sentry via `warnSilentFallback`
// (cq-silent-fallback-must-mirror-to-sentry). Synthesized prefixes only.
const REDACTION_FALLTHROUGH_PROBES = [
  /\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_-]{20,}/,
  /\bgithub_pat_[A-Za-z0-9]{22}_/,
  /Authorization\s*:\s*(?:Bearer|Basic|token)\s+\S/i,
  // Finding 3 — connection-string userinfo (`scheme://user:password@host`).
  // A surviving `user:pass@` after redaction means the new userinfo pattern
  // missed; page Sentry instead of silently leaking the password.
  /\b[a-z][a-z0-9+.\-]*:\/\/[^:@\s/]+:[^@\s/]+@/i,
];

/**
 * Belt-and-suspenders probe: after redaction, scan for any surviving secret
 * shape and mirror to Sentry (warn-tier, P0 credential class). Returns the
 * input unchanged — the probe is observational, the redaction is the gate.
 */
function probeRedactionFallthrough(
  redacted: string,
  ctx: { userId: string; conversationId: string; field: "command" | "output" },
): string {
  for (const probe of REDACTION_FALLTHROUGH_PROBES) {
    if (probe.test(redacted)) {
      warnSilentFallback(
        new Error("command-stream-redact-fallthrough"),
        {
          feature: "cc-dispatcher",
          op: "command-stream-redact-fallthrough",
          extra: {
            userId: ctx.userId,
            conversationId: ctx.conversationId,
            field: ctx.field,
          },
        },
      );
      break;
    }
  }
  return redacted;
}

/**
 * Sanitize a tool name for log emission (#2909 FR2): strip control chars +
 * Unicode line/paragraph separators (CWE-117 log injection defense-in-depth),
 * and length-cap. Pino's JSON serialization is the primary defense; this is
 * a belt-and-suspenders pass per the log-injection-unicode-line-separators
 * learning.
 */
function sanitizeToolNameForLog(name: string): string {
  return name
    .replace(/[\x00-\x1f\x7f\u2028\u2029]/g, "?")
    .slice(0, MAX_TOOL_NAME_LEN_FOR_LOG);
}

// Hoisted module-level sets (avoid per-call construction in
// `dispatchSoleurGo` / `handleInteractivePromptResponseCase`).
export type WorkflowEndStatus = WorkflowEnd["status"];
const TERMINAL_WORKFLOW_END_STATUSES: ReadonlySet<WorkflowEndStatus> = new Set<
  WorkflowEndStatus
>([
  "completed",
  "user_aborted",
  "idle_timeout",
  "plugin_load_failure",
  "internal_error",
  // #4440 follow-up to #4418 — JWT-deny is terminal: the session is
  // gone, retry is impossible without a fresh login. Routes to the
  // terminal `session_ended` WS event via the same branch as the
  // other terminal statuses below.
  "session_revoked",
]);

// #3603 W2 — statuses that trigger the assistant-text abort flush. Mirrors
// the legacy contract at `agent-runner.ts:2044-2055` (writes any non-completed
// terminal status as `status: "aborted"`). Co-located with
// `TERMINAL_WORKFLOW_END_STATUSES` so the file has one canonical
// exhaustiveness rail per status-set. The `_abortFlushExhaustive` rail below
// is the type-level proof that this set covers every non-`completed`
// variant — adding a new `WorkflowEnd` variant without listing it here is a
// TS error.
const ABORT_FLUSH_STATUSES: ReadonlySet<WorkflowEndStatus> = new Set<
  WorkflowEndStatus
>([
  "cost_ceiling",
  "runner_runaway",
  "user_aborted",
  "idle_timeout",
  "plugin_load_failure",
  "internal_error",
  // #4440 follow-up to #4418 — flush any partial assistant text as
  // `aborted` BEFORE the terminal session_ended emit. Matches the
  // semantic of every other non-completed terminal status.
  "session_revoked",
  // #5313 (deferred #5240 FR-half) — worktree-enter failure is a
  // non-completed terminal status; flush partial text before the terminal
  // emit like every sibling.
  "worktree_enter_failed",
]);

// Compile-time exhaustiveness rail for `ABORT_FLUSH_STATUSES`.
// `Exclude<WorkflowEndStatus, "completed">` is exactly the set of non-completed
// statuses; this type assignment forces the keys above to cover that set.
type AbortFlushStatus = Exclude<WorkflowEndStatus, "completed">;
const _abortFlushExhaustive: Record<AbortFlushStatus, true> = {
  cost_ceiling: true,
  runner_runaway: true,
  user_aborted: true,
  idle_timeout: true,
  plugin_load_failure: true,
  internal_error: true,
  session_revoked: true,
  worktree_enter_failed: true,
};
void _abortFlushExhaustive;

// #3642 F7 — Single source of truth for `op` slugs emitted via
// `reportSilentFallback` / `mirrorWithDebounce` / `mirrorP0Deduped` from
// this file. Hoisting these literals prevents drift between the production
// emit site and the test-suite assertions (e.g., an `op` rename in code
// would silently pass the test if the test still hard-codes the old
// literal). Test-file imports re-use this constant via the same module
// path. Registry of slugs is documented in `observability.ts:161-170`.
export const CC_OP_SLUGS = {
  saveAssistant: "save-assistant-message-failed",
  saveAssistantAborted: "save-assistant-message-aborted-failed",
  usageOrphanDropped: "usage_orphan_dropped",
  ccPersistUsageOn: "cc-persist-usage-on",
  persistUserMessage: "persist-user-message",
} as const;

// #3640 F2 — Discriminated `PersistMode` replaces the per-dispatch
// `AssistantPersistMode` string literal + `AssistantPersistOpts` interface
// pair. Module-scope so #3641 type-rail move is a no-op (the type already
// lives outside the `dispatchSoleurGo` closure). The `usage` field is
// keyed inside each variant so a future `aborted` variant can drop the
// `usage` field entirely without an `undefined`-vs-`null` ambiguity.
export type PersistMode =
  | { kind: "complete"; usage: { costUsd: number } | null }
  | { kind: "aborted"; usage: { costUsd: number } | null };

// #3639 F1 — Encapsulates the four mutable per-turn cells previously
// held as `let` bindings inside `dispatchSoleurGo` (the
// `latestAssistantText` accumulator, the `assistantTurnPersisted` abort
// flag, the `currentTurnIndex` counter, and the `pendingTurnUsage`
// cost-capture). One class owns reset-symmetry as a class invariant —
// `reset()` is the only path that clears all four; every mutator method
// is paired with the field it mutates so a future change that touches
// only 3 of 4 fields is caught at code-review time.
//
// Method contracts (call sites in `dispatchSoleurGo` events block):
// - `setText(text)` — `onText` writes the latest streamed text (REPLACE
//   semantic per chat-state-machine.ts:477 + W8). Named `setText` rather
//   than `appendText` since the semantic is a complete-replace, not an
//   append (review #3670 — naming clarity).
// - `captureUsage(turnIdx, costUsd)` — `onResult` stages cost telemetry
//   tagged with `turnIdx`. A stale `onResult` tagged against a previous
//   turn is dropped at consume time by `consumeMatchedUsage`.
// - `consumeForComplete()` — `onTextTurnEnd` happy path: snapshot text +
//   matched usage, clear both cells, bump turn index. Snapshot happens
//   SYNCHRONOUSLY before `saveAssistantMessage` yields the microtask so
//   a turn-N+1 `onResult` arriving on the same iterator yield cannot
//   overwrite turn N's snapshot. Returns `null` when the turn is already
//   aborted — the abort branch is the single authoritative writer once
//   `_aborted` flips true.
// - `consumeForAbort()` — `onWorkflowEnded` abort branch: returns text +
//   matched usage and marks the turn as persisted (so a late
//   `onTextTurnEnd` is a no-op) when text is present; returns
//   `{ kind: "orphan" }` when text is absent but usage was captured (W4
//   orphan); returns `{ kind: "none" }` when neither is present.
// - `currentTurnIndex()` — read of `_currentTurnIndex` for `onResult`
//   to tag `captureUsage` with the active turn.
// - `reset()` — test seam; clears all four fields. Reset-symmetry is a
//   class invariant (production never resets — per-`dispatchSoleurGo`
//   instances are GC'd at dispatch end). Kept for `__getStateForTests`-
//   style override paths and to document the "cells move together"
//   invariant in code rather than prose.
export class TurnPersistenceState {
  private _latestAssistantText = "";
  private _aborted = false;
  private _currentTurnIndex = 0;
  private _pendingTurnUsage: { turnIndex: number; costUsd: number } | null =
    null;

  /** `onText` — REPLACE the accumulator (W8 invariant). Named `setText`
   *  rather than `appendText` because the semantic is a complete-replace
   *  per chat-state-machine.ts:477 — review #3670 (naming clarity). */
  setText(text: string): void {
    this._latestAssistantText = text;
  }

  /** `onResult` — stage per-turn cost tagged with the active turn. */
  captureUsage(turnIdx: number, costUsd: number): void {
    this._pendingTurnUsage = { turnIndex: turnIdx, costUsd };
  }

  /** Active turn index (for `onResult` to tag `captureUsage`). */
  currentTurnIndex(): number {
    return this._currentTurnIndex;
  }

  /**
   * `onTextTurnEnd` happy path. Snapshots text + matched usage,
   * synchronously clears the accumulator + pendingUsage, and bumps the
   * turn index. Returns `null` when there's nothing to persist.
   */
  consumeForComplete(): { text: string; usage: { costUsd: number } | null } | null {
    if (this._aborted) return null;
    const turnSnapshot = this._currentTurnIndex;
    const turnUsage =
      this._pendingTurnUsage?.turnIndex === turnSnapshot
        ? this._pendingTurnUsage
        : null;
    const text = this._latestAssistantText;
    this._latestAssistantText = "";
    this._pendingTurnUsage = null;
    this._currentTurnIndex = turnSnapshot + 1;
    return {
      text,
      usage: turnUsage ? { costUsd: turnUsage.costUsd } : null,
    };
  }

  /**
   * `onWorkflowEnded` abort branch. Three outcomes:
   * - `{ kind: "text"; text; usage }` — text present, abort row should
   *   be written. Marks turn as persisted (suppresses late onTextTurnEnd).
   * - `{ kind: "orphan" }` — text absent but usage was captured (W4
   *   orphan). Caller fires `mirrorP0Deduped`. Clears pendingUsage.
   * - `{ kind: "none" }` — neither text nor usage; no-op.
   */
  consumeForAbort():
    | { kind: "text"; text: string; usage: { costUsd: number } | null }
    | { kind: "orphan" }
    | { kind: "none" } {
    if (this._latestAssistantText.length > 0) {
      const turnUsage =
        this._pendingTurnUsage?.turnIndex === this._currentTurnIndex
          ? this._pendingTurnUsage
          : null;
      const text = this._latestAssistantText;
      this._latestAssistantText = "";
      this._pendingTurnUsage = null;
      this._aborted = true;
      return {
        kind: "text",
        text,
        usage: turnUsage ? { costUsd: turnUsage.costUsd } : null,
      };
    }
    if (this._pendingTurnUsage) {
      this._pendingTurnUsage = null;
      return { kind: "orphan" };
    }
    return { kind: "none" };
  }

  /** Reset-symmetry invariant: clears ALL four fields. */
  reset(): void {
    this._latestAssistantText = "";
    this._aborted = false;
    this._currentTurnIndex = 0;
    this._pendingTurnUsage = null;
  }
}

// #3640 F4 — Build the `messages` INSERT row from a `PersistMode`. Module-
// scope helper keeps `saveAssistantMessage`'s body ≤ 20 LoC; pure function
// (no I/O), so the assistant-row schema can evolve in one place.
function buildRow(
  mode: PersistMode,
  text: string,
  conversationId: string,
  workspaceId: string,
): Record<string, unknown> {
  // #3603 W4 — gated single-read site for `CC_PERSIST_USAGE`. The hot-path
  // env read is intentional: enables runtime rollback flip without a
  // process restart, load-bearing for a GDPR-rollback scenario after PR-C.
  // Exact-match `"true"` only — any other truthy string keeps the flag
  // off (defense-in-depth against a half-set Doppler value). Default-off
  // at merge per AC9/AC11.
  const flagOn = process.env.CC_PERSIST_USAGE === "true";
  if (flagOn) _observeCcPersistUsageFirstTrue();
  const usageColumn =
    flagOn && mode.usage ? { cost_usd: mode.usage.costUsd } : null;

  const row: Record<string, unknown> = {
    id: randomUUID(),
    conversation_id: conversationId,
    // mig 059: messages.workspace_id NOT NULL + member-keyed INSERT RLS.
    // Derived from the parent conversation by the caller; see saveAssistantMessage.
    workspace_id: workspaceId,
    // mig 053: messages.template_id NOT NULL (no default) + CHECK
    // (^[a-z][a-z0-9_]*$). Interactive (non-template) messages use the
    // 'default_legacy' sentinel — same value the draft-card helper and the
    // 053 backfill use. Omitting it violates the NOT-NULL constraint (#4839).
    template_id: "default_legacy",
    role: "assistant",
    content: text,
    tool_calls: null,
    leader_id: CC_ROUTER_LEADER_ID,
    usage: usageColumn,
  };
  // Omit `status` for the normal completion path — migration 040's
  // DEFAULT of `'complete'` applies. Only the abort branch writes
  // `status: "aborted"` explicitly.
  switch (mode.kind) {
    case "complete":
      break;
    case "aborted":
      row.status = "aborted";
      break;
    default: {
      const _exhaustive: never = mode;
      void _exhaustive;
    }
  }
  return row;
}

// #3640 F4 — Mirror a `messages` INSERT failure through `mirrorWithDebounce`.
// The op-slug is picked by `mode.kind` so the `op` + `errorClass` (dedupe
// key) match — drift between them would silently split the Sentry stream.
function mirrorInsertError(
  error: unknown,
  mode: PersistMode,
  userId: string,
  conversationId: string,
  fullText: string,
): void {
  // Symmetric with `buildRow`'s exhaustiveness rail (review #3670): assign
  // to a `never`-typed local and use a sentinel return so the compile
  // error fires at the switch, not at the (never-reached) IIFE return.
  let opSlug: string;
  switch (mode.kind) {
    case "complete":
      opSlug = CC_OP_SLUGS.saveAssistant;
      break;
    case "aborted":
      opSlug = CC_OP_SLUGS.saveAssistantAborted;
      break;
    default: {
      const _exhaustive: never = mode;
      void _exhaustive;
      opSlug = CC_OP_SLUGS.saveAssistant; // unreachable; compile error if PersistMode gains a variant
    }
  }
  // Route through `mirrorWithDebounce` (per-(userId, errorClass) 5-min TTL)
  // — a misconfigured Supabase RLS for one user could otherwise emit one
  // Sentry event per assistant turn (10 turns/conv × 100 active convs =
  // 1000 events/hr).
  mirrorWithDebounce(
    error,
    {
      feature: "cc-dispatcher",
      op: opSlug,
      extra: { userId, conversationId, length: fullText.length },
    },
    userId,
    opSlug,
  );
}

// #3603 W1 — Write-boundary tenant-isolation sentinel.
//
// Post-PR-C, cc-dispatcher.ts writes via tenant-scoped clients
// (`getFreshTenantClient(userId)`). RLS on `messages` enforces the FK-join
// through `conversations.user_id`, but a bug routing user A's dispatch with
// user B's `conversation_id` could still produce a structurally-legal write
// (A's JWT, A-owned `conversation_id`) that misroutes payload. This helper
// is the single sentinel call site that every assistant-row write runs
// through.
//
// At HEAD the SDK callback shape (`DispatchEvents` in `soleur-go-runner.ts`)
// does NOT carry payload-derived `user_id` / `conversation_id`, so the
// dispatch closure is the only source of truth — the sentinel returns `true`
// unconditionally and is essentially a placeholder. Its load-bearing role is
// **forward**: when a future SDK callback exposes payload identifiers, the
// helper signature gains those params and a mismatch check + `mirrorP0Deduped`
// call goes inside this function — a single edit point.
//
// Returns `boolean` rather than throwing: the call sites are
// `void saveAssistantMessage(...)` (fire-and-forget at lines ~1129 and ~1163);
// throwing across the `void` boundary turns into an unhandled promise rejection.
// Halt is `if (!assertWriteScope(...)) return;`.
function assertWriteScope(
  dispatchUserId: string,
  dispatchConversationId: string,
): boolean {
  if (_assertWriteScopeOverride) {
    return _assertWriteScopeOverride(dispatchUserId, dispatchConversationId);
  }
  // Sentinel: no payload source exists today, so the dispatch closure
  // identity IS the write scope. Always-true.
  return true;
}

// Test seam — never use in production. The sentinel returns `true`
// unconditionally; tests force `false` via this hook to prove every
// assistant-row write call site runs through the helper. The exported
// setter/resetter functions (#3641 — relocated) live in the bottom-of-
// file test-seam block alongside `__resetDispatcherForTests` and
// `__setCcRunnerForTests` so all test-only exports cluster in one place.
let _assertWriteScopeOverride:
  | ((u: string, c: string) => boolean)
  | null = null;

// #3603 PR-A2 review H4 — `CC_PERSIST_USAGE=true` is the trigger for a new
// GDPR-regulated persisted category (Art. 13(3) prior-disclosure surface).
// Mirror the FIRST observation per process via `reportSilentFallback` so
// post-hoc Art. 33 evidence ("when did this process start writing
// messages.usage?") doesn't depend on Doppler audit-log correlation. The
// pino + Sentry payload from `reportSilentFallback` carries a server-side
// timestamp + `feature` tag; aggregation by `op: CC_OP_SLUGS.ccPersistUsageOn`
// gives the operator a per-process flip timeline.
let _ccPersistUsageFirstTrueObserved = false;
function _observeCcPersistUsageFirstTrue(): void {
  if (_ccPersistUsageFirstTrueObserved) return;
  _ccPersistUsageFirstTrueObserved = true;
  reportSilentFallback(null, {
    feature: "cc-dispatcher",
    op: CC_OP_SLUGS.ccPersistUsageOn,
    message:
      "CC_PERSIST_USAGE=true observed for first time in this process — messages.usage writes are now active",
    extra: {
      // Anchors the 72h Art. 33 clock to a server-side timestamp the
      // operator can correlate against Doppler change events.
      first_observed_at: new Date().toISOString(),
    },
  });
}

// Test seam — reset the once-observed flag so multiple unit tests can
// exercise the breadcrumb path without cross-test bleed. Never call from
// production code.
export function __resetCcPersistUsageObservationForTests(): void {
  _ccPersistUsageFirstTrueObserved = false;
}

type InteractivePromptResponseError =
  | "invalid_payload"
  | "invalid_response"
  | "kind_mismatch"
  | "already_consumed"
  | "not_found";
const MIRROR_INTERACTIVE_RESPONSE_ERRORS: ReadonlySet<
  InteractivePromptResponseError
> = new Set<InteractivePromptResponseError>([
  "invalid_payload",
  "invalid_response",
  "kind_mismatch",
]);

// ---------------------------------------------------------------------------
// Singletons
// ---------------------------------------------------------------------------

let _registry: PendingPromptRegistry | null = null;
let _reaperInterval: ReturnType<typeof setInterval> | null = null;
const REAPER_INTERVAL_MS = 5 * 60 * 1000;

/**
 * Tool-surface configuration for the cc-soleur-go router.
 *
 * Two SDK options govern tool surface, with DIFFERENT semantics
 * (sdk.d.ts:855-892):
 *   - `allowedTools`: AUTO-APPROVE list — pre-approves without canUseTool.
 *   - `disallowedTools`: HARD-BLOCK list — removes from model context entirely.
 *   - `tools`: closed allowlist of available built-ins (alternative to
 *     disallowedTools).
 *
 * The cc-router's primary job is to dispatch via the Skill tool to a routed
 * sub-skill; it never needs Edit or Write itself, so those stay hard-blocked.
 *
 * Bash routing (#3338 → #3344). Bash was originally hard-blocked alongside
 * Edit/Write because it triggered a `find . -name "*.pdf"` / `apt-get install
 * poppler-utils` modal cascade when the agent tried to summarize a large PDF
 * (review-gate modals popping in the end-user Concierge surface). Two
 * structural mitigations have since landed and made the hard-block over-broad:
 *
 *   - #3338 PDF Read 24 MB ceiling — large PDFs route through the gated
 *     directive instead of the inline-Read path that triggered the cascade.
 *   - #3430 page-count gate on the PDF soft-route — large PDFs are
 *     classified before the agent attempts inline read.
 *
 * Bash now routes through `canUseTool` and shares the legacy path's
 * `safe-bash` allowlist (`apps/web-platform/server/safe-bash.ts`). Read-only
 * KB-exploration verbs (`pwd`, `ls`, `cat`, `head`, `tail`, `wc`, `git
 * status/log/diff/show/branch/rev-parse`, `echo`, etc.) auto-approve with no
 * modal; verbs NOT in the allowlist (including `find`/`grep`/`rg`/`apt-get` —
 * intentionally omitted per the omission rationale at the top of
 * `safe-bash.ts` because they accept `-exec` and
 * could shell out) still route to `review_gate`. The structural mitigations
 * above prevent the cascade triggers, and the allowlist covers the verbs the
 * cc-router actually emits during KB exploration. See Closes #3344.
 *
 * The auto-approve list (`CC_PATH_ALLOWED_TOOLS`) is kept as a separate
 * concern: it eliminates a `canUseTool` round-trip for read-only tools
 * (Read, Glob, Grep, LS, NotebookRead, TodoWrite, ExitPlanMode) the cc-router
 * legitimately uses on its own. This is auto-approve, not restriction.
 *
 * Routed sub-skills load their own toolset via the soleur plugin and the
 * legacy domain-leader path (`agent-runner.ts startAgentSession`), so the
 * Edit/Write narrowing is scoped to the cc-router only — exploration within
 * routed workflows is unaffected.
 */
const CC_PATH_ALLOWED_TOOLS: readonly string[] = [
  "Read",
  "Glob",
  "Grep",
  "LS",
  "NotebookRead",
  "TodoWrite",
  "ExitPlanMode",
];

/**
 * Tools removed from the cc-router's surface entirely. Adds to the
 * canonical `[WebSearch, WebFetch]` shared with the legacy path.
 *
 * Bash was removed from this list in #3344 — see the routing rationale on
 * the doc-comment block above. Bash now routes through `canUseTool` and
 * shares the legacy path's `safe-bash` allowlist + review_gate fallback.
 */
const CC_PATH_DISALLOWED_TOOLS: readonly string[] = ["Edit", "Write"];

export function getPendingPromptRegistry(): PendingPromptRegistry {
  if (_registry) return _registry;
  _registry = new PendingPromptRegistry();
  // Schedule TTL reaper. Without this the registry's `reap()` would
  // never run in production (performance-oracle P1-B). Keyed by registry
  // instance so a test-time `__resetDispatcherForTests` clears the
  // interval too. `.unref()` keeps the timer from blocking graceful
  // shutdown.
  _reaperInterval = setInterval(() => {
    try {
      if (_registry) {
        _registry.reap();
        // After record TTL-expire, wholesale-clear the tombstone set.
        // Any consume-response arriving for a reaped key surfaces as
        // `not_found` (acceptable — the prompt genuinely aged out).
        pruneTombstonesFor(_registry);
      }
    } catch (err) {
      reportSilentFallback(err, {
        feature: "cc-dispatcher",
        op: "registryReaperInterval",
      });
    }
  }, REAPER_INTERVAL_MS);
  _reaperInterval.unref();
  return _registry;
}

let _rateLimiter: StartSessionRateLimiter | null = null;
export function getCcStartSessionRateLimiter(): StartSessionRateLimiter {
  if (!_rateLimiter) _rateLimiter = createStartSessionRateLimiter();
  return _rateLimiter;
}

// ---------------------------------------------------------------------------
// ccBashGates — Option A synthetic-AgentSession registry for the
// cc-soleur-go path's Bash review-gate.
//
// `permission-callback.ts createCanUseTool` requires an `AgentSession`
// (with `reviewGateResolvers: Map<gateId, {resolve, options}>`) and a
// `controllerSignal: AbortSignal`. The cc-soleur-go runner does NOT use
// `AgentSession` for its lifecycle (it tracks `activeQueries` itself).
// We synthesize a per-`query()` session inside `realSdkQueryFactory` and
// register it here so ws-handler `review_gate_response` can route Bash
// gate responses by routing kind without touching the legacy
// `activeSessions` Map in `agent-runner.ts`.
//
// Composite-key invariant (R8): mirrors `pending-prompt-registry.ts`
// `makePendingPromptKey` — `${userId}:${conversationId}:${gateId}`.
// Cross-user lookup MUST silently deny.
// ---------------------------------------------------------------------------

/**
 * Gate kind discriminator (P1 — consent-gate bypass via frame substitution).
 * The held first-run disclosure hold and the normal Bash review-gate share this
 * ONE registry keyed only by `gateId`. Without a kind discriminator, a
 * `review_gate_response` frame carrying a HELD disclosure `gateId` would release
 * the consent-gated command WITHOUT routing through the owner-checked
 * `setAutonomousAck` path (no ack written, no disclosure honored). `resolveCcBashGate`
 * refuses to resolve a gate whose `kind` ≠ the responder's `expectedKind`, so a
 * cross-kind frame cannot release the gate.
 */
export type CcBashGateKind = "review" | "autonomous_disclosure";

interface CcBashGateRecord {
  userId: string;
  conversationId: string;
  gateId: string;
  session: AgentSession;
  kind: CcBashGateKind;
}

const _ccBashGates = new Map<string, CcBashGateRecord>();

// ---------------------------------------------------------------------------
// P1 — per-conversation in-session autonomous-ack posture registry.
//
// `autonomousAckAt` is resolved ONCE at cold-start and frozen into `ccDeps`.
// After the owner acks the first-run disclosure mid-dispatch, nothing mutates
// that frozen value, so the NEXT command in the same conversation would re-hold.
// This registry exposes a mutable posture cell per (userId, conversationId):
//   - `ccDeps.resolveAckPosture` reads it (the live posture, not the snapshot).
//   - the ws-handler flips it non-null via `markConversationAcked` on a
//     successful ack-release, so command #2 is friction-free.
// Drained by `cleanupCcBashGatesForConversation` (conversation close/reap).
// ---------------------------------------------------------------------------
interface AutonomousAckPostureCell {
  get: () => number | null;
  set: (v: number | null) => void;
}
const _ccAutonomousAckPosture = new Map<string, AutonomousAckPostureCell>();

function makeAckPostureKey(userId: string, conversationId: string): string {
  return `${userId}:${conversationId}`;
}

/**
 * Register the per-conversation mutable ack-posture cell. Called from the
 * dispatch scope (per cold conversation). Idempotent overwrite — a warm-query
 * re-dispatch re-seeds the cell from its own snapshot.
 */
export function registerAutonomousAckPosture(
  userId: string,
  conversationId: string,
  cell: AutonomousAckPostureCell,
): void {
  _ccAutonomousAckPosture.set(makeAckPostureKey(userId, conversationId), cell);
}

/**
 * P1 — flip the in-session ack posture to non-null after a successful ack write.
 * Called by the ws-handler `autonomous_disclosure_response` case AFTER
 * `setAutonomousAck` resolves (and BEFORE/around the gate drain) so any held
 * (and any subsequent) command in the same conversation sees the workspace as
 * acked and does not re-hold. `ackAtMs` is the persisted ack epoch ms (parsed
 * from the RPC's returned timestamp; fail-closed to `Date.now()` when the
 * server returned a non-finite value but the write succeeded). No-op when no
 * cell is registered (e.g. the conversation already closed).
 */
export function markConversationAcked(
  userId: string,
  conversationId: string,
  ackAtMs: number,
): void {
  const cell = _ccAutonomousAckPosture.get(
    makeAckPostureKey(userId, conversationId),
  );
  cell?.set(ackAtMs);
}

function makeCcBashGateKey(
  userId: string,
  conversationId: string,
  gateId: string,
): string {
  return `${userId}:${conversationId}:${gateId}`;
}

/**
 * Register the synthetic AgentSession owning a Bash review-gate so
 * ws-handler `review_gate_response` can later resolve it via
 * `resolveCcBashGate`. Called from `realSdkQueryFactory`'s
 * `canUseTool` Bash branch (via the synthetic session bridge).
 */
export function registerCcBashGate(args: {
  userId: string;
  conversationId: string;
  gateId: string;
  session: AgentSession;
  /**
   * P1 — gate kind. The first-run disclosure HOLD registers
   * `"autonomous_disclosure"`; every other Bash review-gate registers
   * `"review"` (the default). A response frame can only resolve a gate of the
   * matching kind (`resolveCcBashGate`'s `expectedKind`), so a
   * `review_gate_response` cannot release a held consent gate.
   */
  kind?: CcBashGateKind;
}): void {
  const key = makeCcBashGateKey(args.userId, args.conversationId, args.gateId);
  _ccBashGates.set(key, {
    userId: args.userId,
    conversationId: args.conversationId,
    gateId: args.gateId,
    session: args.session,
    kind: args.kind ?? "review",
  });
}

/**
 * Resolve a pending Bash review-gate for the cc-soleur-go path. Returns
 * true on a successful single-use resolve; false on missing record OR
 * cross-user lookup (silent denial — never reveal that the record exists
 * but belongs to another user). Mirrors `resolveReviewGate` in
 * `agent-runner.ts` semantics, scoped to the cc path.
 */
export function resolveCcBashGate(args: {
  userId: string;
  conversationId: string;
  gateId: string;
  selection: string;
  /**
   * P1 — the gate kind the RESPONDER is authorized to resolve. A
   * `review_gate_response` passes `"review"` (the default); an
   * `autonomous_disclosure_response` passes `"autonomous_disclosure"`. The
   * resolve is a NO-OP (returns false, gate stays held) when the stored
   * record's kind ≠ this — so a cross-frame response cannot release the gate.
   */
  expectedKind?: CcBashGateKind;
}): boolean {
  const key = makeCcBashGateKey(args.userId, args.conversationId, args.gateId);
  const record = _ccBashGates.get(key);
  if (!record) return false;
  // R8: composite-key cross-user prompt collision — defense-in-depth.
  if (record.userId !== args.userId) return false;
  // P1: kind discriminator — refuse to release a gate whose kind differs from
  // the responder's expected kind. Defaults to "review" so legacy callers that
  // predate the discriminator stay correct for the (dominant) review-gate path.
  // A cross-kind response leaves the gate held (no resolver fired, no delete).
  const expectedKind = args.expectedKind ?? "review";
  if (record.kind !== expectedKind) return false;
  const entry = record.session.reviewGateResolvers.get(args.gateId);
  if (!entry) {
    _ccBashGates.delete(key);
    return false;
  }
  try {
    entry.resolve(args.selection);
  } catch (err) {
    reportSilentFallback(err, {
      feature: "cc-dispatcher",
      op: "resolveCcBashGate",
      extra: {
        userId: args.userId,
        conversationId: args.conversationId,
        gateId: args.gateId,
      },
    });
    return false;
  }
  record.session.reviewGateResolvers.delete(args.gateId);
  _ccBashGates.delete(key);
  return true;
}

/**
 * P2 — multi-hold, single ack. Two (or more) Bash commands can be HELD behind
 * the disclosure before the owner acks even once. Because the ack is
 * WORKSPACE-level (not per-command), a single successful ack releases ALL held
 * disclosure gates for that conversation, not just the clicked one. This resolves
 * every `kind:"autonomous_disclosure"` gate for (userId, conversationId) with the
 * owner's selection so each held command proceeds (combined with the in-session
 * posture flip, none of them re-hold). Returns the count released. Review gates
 * are untouched. Each resolve is single-use + composite-key scoped (R8).
 */
export function drainAutonomousDisclosureGates(args: {
  userId: string;
  conversationId: string;
  selection: string;
}): number {
  const prefix = `${args.userId}:${args.conversationId}:`;
  let released = 0;
  for (const key of Array.from(_ccBashGates.keys())) {
    if (!key.startsWith(prefix)) continue;
    const record = _ccBashGates.get(key);
    if (!record || record.kind !== "autonomous_disclosure") continue;
    const ok = resolveCcBashGate({
      userId: args.userId,
      conversationId: args.conversationId,
      gateId: record.gateId,
      selection: args.selection,
      expectedKind: "autonomous_disclosure",
    });
    if (ok) released += 1;
  }
  return released;
}

/**
 * Drain all ccBashGates entries for a conversation. Called from the
 * runner's close paths (`closeConversation`, `reapIdle`) so a Bash
 * gate that was awaiting resolution at conversation-close time does
 * not leak. Also called proactively when a conversation supersedes.
 */
export function cleanupCcBashGatesForConversation(
  userId: string,
  conversationId: string,
): void {
  const prefix = `${userId}:${conversationId}:`;
  for (const key of Array.from(_ccBashGates.keys())) {
    if (key.startsWith(prefix)) {
      const record = _ccBashGates.get(key);
      if (record) {
        // Abort awaiting resolvers so the canUseTool promise rejects
        // (rather than hanging until TTL).
        try {
          record.session.abort.abort(
            new Error("Conversation closed before Bash gate resolved"),
          );
        } catch {
          // best-effort
        }
      }
      _ccBashGates.delete(key);
    }
  }
  // Drain the per-(userId, conversationId) Bash batched-approval cache
  // (#2921). Without this, granted prefixes survive conversation
  // close/reap and could auto-approve on the NEXT conversation if the
  // ws layer reuses the same conversationId (it doesn't today, but
  // defense-in-depth: the cache lifetime should never exceed the
  // conversation lifetime).
  getBashApprovalCache(userId, conversationId).revoke();
  // P1 — drain the in-session ack-posture cell so it does not leak past the
  // conversation (and a reused conversationId can't inherit a prior ack).
  _ccAutonomousAckPosture.delete(makeAckPostureKey(userId, conversationId));
}

/**
 * #5356 — the runner's `onCloseQuery` close-side hook (fires from EVERY close
 * path BEFORE `activeQueries.delete`: `emitWorkflowEnded`, `reapIdle`,
 * `closeConversation`). Two responsibilities:
 *   1. ALWAYS drain `_ccBashGates` (+ batched-approval cache + ack posture) for
 *      the conversation — `reapIdle` / `closeConversation` close the Query
 *      WITHOUT firing `onWorkflowEnded`, so the dispatch-side cleanup would
 *      otherwise never run and the gate registry would leak.
 *   2. On a `disconnected` grace-abort ONLY, checkpoint the conversation's
 *      uncommitted working-tree changes — the cc-soleur-go (Concierge) parity
 *      with the legacy `agent-runner` disconnect branch (#5275/#5356). The
 *      helper is fire-and-forget and never throws, so the unconditional
 *      bash-gate drain above always completes regardless.
 */
export function handleCcCloseQuery({
  conversationId,
  userId,
  reason,
}: {
  conversationId: string;
  userId: string;
  reason?: "disconnected";
}): void {
  cleanupCcBashGatesForConversation(userId, conversationId);
  if (reason === "disconnected") {
    void checkpointInflightWorkForConversation(
      userId,
      conversationId,
      "cc-resolve-workspace-path",
    );
  }
}

// ---------------------------------------------------------------------------
// realSdkQueryFactory — Stage 2.12 binding (unconditional since #3270).
//
// Builds a real `Query` per cold conversation. Mirrors
// `agent-runner.ts startAgentSession` `query({ options })` shape with
// these omissions/changes:
//   - `mcpServers: {}` for V1 — V2-13 (#2909) tracks tier-classification
//     of in-process MCP servers (kb_share / conversations / github /
//     plausible) for the cc-soleur-go path before widening.
//   - `disallowedTools: ["WebSearch", "WebFetch"]` — parity with
//     legacy runner (R7).
//   - `leaderId: CC_ROUTER_LEADER_ID` — non-routable internal leader for
//     audit-log attribution.
//   - Synthetic `AgentSession` per Option A (Open Design Question in
//     plan §"Bash Review-Gate Bridge"); registered in `_ccBashGates`
//     so ws-handler `review_gate_response` can resolve via
//     `resolveCcBashGate`.
//
// Idempotency: `patchWorkspacePermissions` is safe to run on every
// cold-Query construction. The runner's queryFactory call site
// (`soleur-go-runner.ts createSoleurGoRunner.dispatch`) only invokes
// the factory once per cold conversation; reused dispatches skip.
// ---------------------------------------------------------------------------

// `fetchUserWorkspacePath` and `resolveConciergeDocumentContext` were
// extracted to `./kb-document-resolver` so this orchestration module no
// longer owns filesystem responsibilities alongside SDK Query construction,
// MCP wiring, BYOK token resolution, bash-approval, and rate-limiting. Both
// modules resolve the active-workspace path via the same exported helper
// (one source of truth; no value cache — the active workspace is mutable).

/**
 * Build a real SDK `Query` for one cold cc-soleur-go conversation. Async
 * because workspace path + BYOK key + service tokens are DB-resident.
 * Errors flow up to `soleur-go-runner.ts dispatch`'s `await
 * deps.queryFactory(...)` try/catch — KeyInvalidError there is mapped
 * to `errorCode: "key_invalid"` by `dispatchSoleurGo` (R10);
 * sandbox-startup substring is mirrored here under
 * `feature: "agent-sandbox"` for Sentry tag-filtering parity with the
 * legacy runner. All three DB fetches run in parallel.
 */
export const realSdkQueryFactory: QueryFactory = async (
  args: QueryFactoryArgs,
): Promise<Query> => {
  // PR-C §2.11 (#3244): wrap body in `runWithByokLease` so the plaintext
  // Anthropic key is zeroized on exit and captured-leak attempts throw
  // `ByokLeaseError{cause:"escape"}`. Mirrors agent-runner.ts's
  // startAgentSession pattern at :863 + sendUserMessage routing at
  // :2360. By the time this body returns the Query AsyncGenerator,
  // `sdkQuery({apiKey, ...})` below has already passed the key into the
  // SDK's internal state — the lease's finally-zeroize fires after the
  // SDK has captured what it needs.
  // Phase 3 (feat-team-workspace-multi-user): the args stay
  // `args.userId, args.userId`; the workspace the BYOK key is resolved
  // against is derived INSIDE resolveKeyOwnerThenLease via
  // resolveCurrentWorkspaceId (the caller's ACTIVE workspace — the shared
  // workspace an owner granted into, post Phase-4 invite flow), no longer
  // the oldest/solo workspace (#4767). For a solo caller the active
  // workspace IS their solo workspace, so solo behavior is unchanged.
  // Sentinel sweep site #3 (#4232 PR-A). callerUserId = args.userId
  // (server-derived per cc-dispatcher contract; provenance in PR body).
  // Invariant kept: callerUserId === workspaceContextUserId.
  return resolveKeyOwnerThenLease(
    args.userId,
    args.userId,
    async (lease): Promise<Query> => {
    // BYOK Delegations PR-A (#4232) closure-capture: publish the lease
    // context to the dispatcher before the lease scope closes. The
    // Query iterator is consumed by the runner ASYNC AFTER this factory
    // returns — by then `slot.alive = false` and `lease.delegationId`
    // is unreachable. The dispatcher's onResult callback reads from
    // the closure variable that the sink writes here.
    args.setDelegationContext?.(
      lease.delegationId !== undefined
        ? {
            delegationId: lease.delegationId,
            callerUserId: lease.workspaceContextUserId,
          }
        : undefined,
    );

    // Plan §2.11 canonical pattern (mirrors agent-runner.ts:2361):
    // hoist `await lease.getAgentCredential()` OUT of `Promise.all` so the
    // `AgentCredential | Promise<AgentCredential>` union does not surface
    // awkwardly through `Promise.all`'s array element inference.
    // `buildAgentQueryOptions.credential` consumes the unwrapped value.
    // Agent-SDK consumer: prefers the operator subscription oauth_token
    // when enabled+permitted; otherwise the api_key (feat-operator-cc-oauth).
    const credential = await lease.getAgentCredential();
    // installationId joins the existing Promise.all (it keys only off
    // args.userId via resolveInstallationId → resolveCurrentWorkspaceId), so
    // the resolve does not add a sequential await to cold-start dispatch.
    const [
      workspacePath,
      serviceTokens,
      installationId,
      bashAutonomous,
      autonomousAckAt,
      isWorkspaceOwner,
      repoUrl,
    ] =
      await Promise.all([
        fetchUserWorkspacePath(args.userId),
        getUserServiceTokens(args.userId),
        resolveInstallationId(args.userId),
        // Issue B part 2 — fail-closed false; bypasses the Bash review-gate
        // when the active workspace owner enabled the autonomous toggle.
        resolveBashAutonomous(args.userId),
        // feat-bash-autonomous-default-on — first-run consent ack (fail-closed
        // null = HOLD). When bashAutonomous && ack==null && owner, the first
        // non-blocked command is soft-gated behind the disclosure.
        resolveAutonomousAck(args.userId),
        // feat-bash-autonomous-default-on — ownership (fail-closed not-owner).
        // A non-owner on an un-acked autonomous workspace falls through to the
        // review-gate rather than seeing an ack they can't grant.
        resolveIsWorkspaceOwner(args.userId),
        // Per-user connected repo (normalized, membership-checked). Drives the
        // session-start ensure-repo self-heal below. null = not connected.
        getCurrentRepoUrl(args.userId),
      ]);
    // Normalize the ack to epoch-ms | null for the permission-callback deps
    // (the wire/db value is an ISO timestamptz string). P2 — fail-CLOSED on an
    // unparseable timestamp: `Date.parse` of garbage returns NaN, and the
    // permission-callback's `livePosture == null` check is FALSE for NaN, so a
    // malformed ack would be treated as ACKED and auto-run the first command
    // with NO disclosure. Coerce a non-finite parse back to null (= HOLD).
    const parsedAck =
      autonomousAckAt != null ? Date.parse(autonomousAckAt) : null;
    const autonomousAckAtMs =
      parsedAck != null && Number.isFinite(parsedAck) ? parsedAck : null;
    // P1 — mutable in-session ack posture cell. Seeded from the cold-start
    // snapshot; flipped non-null by the ws-handler (via `markConversationAcked`)
    // on a successful ack-release so command #2 in the same conversation does
    // not re-hold. `resolveAckPosture` (ccDeps) reads THIS cell, not the frozen
    // snapshot.
    let autonomousAckPosture: number | null = autonomousAckAtMs;
    registerAutonomousAckPosture(args.userId, args.conversationId, {
      get: () => autonomousAckPosture,
      set: (v) => {
        autonomousAckPosture = v;
      },
    });

    // feat-concierge-stream-commands — publish the streaming posture (D1)
    // to the dispatcher's command_stream emit gate. Same closure-capture
    // bridge as setDelegationContext: the factory resolved `bashAutonomous`
    // above; the dispatcher's `onToolResult` reads it from the closure cell
    // this writes. Card-suppression itself is enforced in permission-callback
    // via the same `bashAutonomous` dep; this only gates whether output
    // STREAMS (we never stream when the review-gate is the active surface).
    args.setBashAutonomous?.(bashAutonomous);

    // P1 chip — push the SERVER-resolved autonomous posture to the client so the
    // persistent chip reflects server truth (`bashAutonomous && acked`), NOT a
    // message-presence heuristic. A held (un-acked) disclosure is "Approve each";
    // only an acked autonomous workspace is "Auto-run on". Re-pushed by the
    // ws-handler on a successful in-session ack-release.
    defaultSendToClient(args.userId, {
      type: "autonomous_posture",
      autonomous: bashAutonomous && autonomousAckAtMs != null,
    });

    // Parse the connected repo's owner/repo ONCE from the server-resolved
    // repoUrl (never tool input). Reused by the installation self-heal below
    // and the C4 write-tool gate further down. CC_GITHUB_NAME_RE rejects any
    // path-shaping characters.
    let connectedOwner = "";
    let connectedRepo = "";
    if (repoUrl) {
      try {
        const parts = new URL(repoUrl).pathname.split("/").filter(Boolean);
        const o = parts[0];
        const r = parts[1]?.replace(/\.git$/, "");
        if (o && r && CC_GITHUB_NAME_RE.test(o) && CC_GITHUB_NAME_RE.test(r)) {
          connectedOwner = o;
          connectedRepo = r;
        }
      } catch {
        /* malformed repoUrl → no owner/repo (degrade silently, not security) */
      }
    }

    // feat-one-shot-concierge-gh-403 — installation self-heal. The stored
    // installation id (workspaces.github_installation_id, resolved above) can
    // be a CROSS-ACCOUNT personal install that READS the connected repo (so the
    // connect-time read probe passed) yet only holds `issues: read`. The
    // Concierge's `gh issue create` then 403s "Resource not accessible by
    // integration" — which the model misreads as a missing scope and (falsely)
    // tells the user to re-consent. The deterministic fix is SELECTION, not a
    // permission change: mint for the installation whose ACCOUNT OWNS the repo
    // (the org install, full grant incl. `issues: write`) — but ONLY when the
    // user is ENTITLED to it (findRepoOwnerInstallationForUser gates org-owned
    // installs on verified org membership, so an outside read-only collaborator
    // cannot escalate to the org's write grant).
    //
    // Entirely GitHub-App-JWT driven — NO Supabase service-role. The
    // dispatching user's GitHub login is derived from the STORED install's
    // account when that install is a personal (User-type) install: a personal
    // install's account login IS the user's GitHub username. That keeps
    // cc-dispatcher off the service-role allowlist (it was migrated to tenant
    // in PR-D and must stay off — re-introducing a service-role client here
    // would trip the service-role-allowlist gate). The in-memory override fixes THIS
    // dispatch; we deliberately do NOT persist (no revoked-column write, and no
    // solo-vs-active-workspace clobber risk) — the override re-applies on each
    // cold dispatch, which is bounded (cold-conversation factory). Best-effort:
    // any probe failure keeps the stored install and never blocks the chat.
    // Self-heal SELECTION extracted to `resolveEffectiveInstallationId`
    // (cc-effective-installation.ts) so the per-dispatch warm re-provision
    // (cc-reprovision.ts) selects the SAME promoted install as this cold factory
    // — otherwise the warm re-clone would use the raw (possibly 403-ing) stored
    // install and falsely report "workspace reclaimed — couldn't restore" for an
    // org repo a cold turn could recover (#5340 review finding). Best-effort:
    // returns the stored install on any probe failure, never widening access.
    const effectiveInstallationId = await resolveEffectiveInstallationId({
      userId: args.userId,
      installationId,
      repoUrl,
    });

    // Unconditional pre-sandbox workspace-dir guarantee (feat-one-shot-warm-
    // reprovision-ensure-dir-presandbox). The bwrap sandbox binds `cwd` to THIS
    // factory's own resolved `workspacePath` (the `:1315` `fetchUserWorkspacePath`
    // in the Promise.all above — NOT `args.workspacePath`, which is system-prompt-
    // only) at `query()` construction below, and requires the dir to EXIST. After
    // a reclaim it can be gone. The clone's mkdir (PR #5367) is CONDITIONAL — it
    // sits past `ensureWorkspaceRepoCloned`'s not-connected / `.git`-present early-
    // returns — so a reclaimed not-connected workspace would skip it and the
    // sandbox would `chdir` into a missing dir. Ensuring the dir here, before the
    // clone and before `buildAgentQueryOptions`, is the stronger precondition. On
    // failure it surfaces a retryable error (rides the `query()`-construction catch
    // below) rather than building a doomed sandbox.
    await ensureWorkspaceDirExists(workspacePath, {
      feature: "cc-dispatcher",
      userId: args.userId,
    });

    // Session-start self-heal (generic, per-user, idempotent, fail-soft): if the
    // workspace has a connected repo but no matching clone on disk, clone/repair
    // it so the agent has a real git repo to branch/commit/work in. Runs once per
    // cold conversation (the factory is per-cold-conversation). NEVER throws into
    // the conversation; clone failure mirrors to Sentry and degrades gracefully.
    //
    // Consumes `effectiveInstallationId` — the SELF-HEALED, entitled repo-owner
    // install computed just above — NOT the raw stored `installationId`. Cloning
    // with a stored cross-account/personal install (which may hold only
    // `issues: read` on the org repo) 403s on `git clone`, fails fail-soft, and
    // leaves the workspace `.git`-less, surfacing downstream as the opaque
    // "No Git Repository in Workspace" worktree error. The GH_TOKEN mint and the
    // C4 write tool already consume `effectiveInstallationId`; the clone now joins
    // them as the third consumer (feat-one-shot-concierge-gh-403 — the self-heal
    // selection now actually reaches the clone, which #5031 hardened but never
    // wired through). In every non-promotion branch `effectiveInstallationId ===
    // installationId`, so the clone uses exactly the stored install it did before
    // whenever the entitlement gate did not promote — the fix never widens access.
    await ensureWorkspaceRepoCloned({
      userId: args.userId,
      workspacePath,
      installationId: effectiveInstallationId,
      repoUrl,
    });

    // Issue A: mint a short-lived GitHub App installation token for the
    // connected repo and inject it as GH_TOKEN so the agent's `gh` calls
    // authenticate without an interactive `gh auth login` (the reported
    // symptom). resolveInstallationId returns null for no-connected-repo /
    // non-member — graceful degradation: no token means sandbox GitHub
    // egress stays closed (#5041 follow-up), so in-sandbox gh is
    // network-dead at the proxy (`Post "...": Forbidden`), not merely
    // unauthenticated. Mint failure is NON-FATAL: mirror to Sentry and
    // proceed without GH_TOKEN — never block a conversation on a gh-auth
    // mint. generateInstallationToken is token-cache-memoized per
    // installation id, so this is not a per-dispatch network round-trip on a
    // warm cache. Per hr-github-app-auth-not-pat this is an App installation
    // token, NEVER a PAT, and the value is NEVER logged. (Sentry
    // 512e253141294ac1a808b2ef03a21289 — cron-follow-through-monitor — is the
    // cron-side root cause this mirrors for the interactive path.)
    let ghToken: string | undefined;
    if (effectiveInstallationId !== null) {
      try {
        ghToken = await generateInstallationToken(effectiveInstallationId, {
          minRemainingMs: GH_TOKEN_MIN_LIFETIME_MS,
        });
      } catch (err) {
        reportSilentFallback(err, {
          feature: "cc-dispatcher",
          op: "mint-gh-token",
          extra: { userId: args.userId, hasInstallation: true },
          message:
            "GitHub App installation token mint failed; sandbox GitHub egress stays closed (gh network-dead at proxy)",
        });
      }
    }
    // Sandbox GitHub egress posture (#5041 follow-up): egress to
    // github.com/api.github.com is DERIVED from ghToken presence inside
    // buildAgentQueryOptions (both-or-nothing). Boolean only — NEVER the
    // token (AC6-class guard from #5041).
    log.info(
      { userId: args.userId, githubEgress: Boolean(ghToken) },
      "Concierge sandbox GitHub egress posture",
    );

  // --- C4 diagram write capability (flag-gated, per-user) -----------------
  // The Concierge's ONLY sanctioned repo write: edit_c4_diagram, scoped to the
  // diagrams dir by `writeC4Diagram`/`isC4DiagramPath`. owner/repo/installation
  // are CLOSED OVER here from the per-user active workspace (ADR-044) — never
  // tool input — so the agent cannot redirect the commit. Gated by the
  // c4-visualizer flag resolved against the dispatch user's real role (the
  // dev-cohort segment), fail-closed: any resolution error → no write tool.
  const c4McpServers = readCcMcpAllowlist();
  let c4ToolName: string | undefined;
  let c4PromptAddendum: string | undefined;
  {
    // Reuse the owner/repo parsed once above + the self-healed installation id
    // so the C4 write tool commits via the SAME repo-owner installation the
    // GH_TOKEN was minted for (feat-one-shot-concierge-gh-403).
    const owner = connectedOwner;
    const repo = connectedRepo;
    if (effectiveInstallationId !== null && owner && repo) {
      let c4Enabled = false;
      try {
        const tenant = await getFreshTenantClient(args.userId);
        const { data: roleRow } = await tenant
          .from("users")
          .select("role")
          .eq("id", args.userId)
          .single<{ role: unknown }>();
        const role: Role = roleRow?.role === "dev" ? "dev" : "prd";
        c4Enabled = await getRuntimeFlag(C4_VISUALIZER_FLAG, {
          userId: args.userId,
          role,
          orgId: null,
        });
      } catch (err) {
        reportSilentFallback(err, {
          feature: "cc-dispatcher",
          op: "c4-flag-resolve",
          extra: { userId: args.userId },
          message:
            "c4-visualizer flag resolve failed; Concierge diagram write disabled",
        });
      }
      if (c4Enabled) {
        const c4Server = createSdkMcpServer({
          name: "soleur_platform",
          version: "1.0.0",
          tools: buildC4ConciergeTools({
            userId: args.userId,
            installationId: effectiveInstallationId,
            owner,
            repo,
            workspacePath,
          }),
        });
        (c4McpServers as Record<string, unknown>).soleur_platform = c4Server;
        c4ToolName = `mcp__soleur_platform__${EDIT_C4_DIAGRAM_TOOL}`;
        c4PromptAddendum =
          "## C4 diagram editing\n" +
          "To edit a C4 architecture diagram, call the `edit_c4_diagram` tool " +
          "with `relativePath` (a `.c4` source or the `.md` view-embed page " +
          "directly under `engineering/architecture/diagrams/`) and `content` " +
          "(the FULL new file contents). It commits the source directly to the " +
          "repo and then re-renders the diagram. The tool response includes " +
          "`rerendered`: when true, the rendered diagram updated — tell the user " +
          "it updated; when false, the source was saved but the re-render failed, " +
          "so tell the user the diagram will refresh after the next re-render. Do " +
          "NOT paste DSL into chat for the user to apply.";
      }
    }
  }

  // Workspace-permissions patch and the #3250 prefill-guard probe both
  // depend on `workspacePath` but not on each other — parallelize so the
  // probe doesn't add latency to cold-start dispatch. See plan
  // §"Sharp Edges" and `agent-prefill-guard.ts` for the guard contract.
  const [, prefillGuardResult] = await Promise.all([
    patchWorkspacePermissions(workspacePath),
    applyPrefillGuard({
      resumeSessionId: args.resumeSessionId,
      workspacePath,
      userId: args.userId,
      conversationId: args.conversationId,
      feature: "cc-concierge",
      leaderId: CC_ROUTER_LEADER_ID,
    }),
  ]);
  const {
    safeResumeSessionId,
    contextResetNotice,
    reason: contextResetReason,
  } = prefillGuardResult;

  // #3269 — context-reset signal. The notice is appended to systemPrompt
  // for THIS SDK call only (single-turn; not persisted across turns).
  // The WS event is the user-side signal; emitted exactly once per guard
  // fire. SDK retries are internal to the returned Query AsyncGenerator
  // (sdk.d.ts:1678-1681) and re-enter `query()`, not the factory — so
  // `applyPrefillGuard` is naturally per-fire and a single emit suffices.
  if (contextResetReason) {
    defaultSendToClient(args.userId, {
      type: "context_reset",
      reason: contextResetReason,
      conversationId: args.conversationId,
    });
  }
  let effectiveSystemPrompt = contextResetNotice
    ? `${args.systemPrompt}\n\n${contextResetNotice}`
    : args.systemPrompt;
  // Only advertise edit_c4_diagram when it was actually registered above
  // (flag on + connected repo), mirroring agent-runner's capability-gated
  // prompt sections so the model isn't told about a tool it cannot call.
  if (c4PromptAddendum) {
    effectiveSystemPrompt += `\n\n${c4PromptAddendum}`;
  }
  // Always append the gh-403 honesty directive (feat-one-shot-concierge-gh-403)
  // — independent of repo/flag state, since any conversation can run `gh`.
  effectiveSystemPrompt += `\n\n${GH_403_PROMPT_DIRECTIVE}`;
  // No entitled token → sandbox egress closed → gh/git network-dead at the
  // proxy. Override the directive's "platform will retry automatically"
  // promise, which only holds when a token (and thus egress) exists.
  if (!ghToken) {
    effectiveSystemPrompt += `\n\n${GH_NO_NETWORK_PROMPT_ADDENDUM}`;
  }
  // feat-one-shot-concierge-workspace-repo-context — name the server-resolved
  // connected repo so the agent uses it for `-R owner/repo` instead of probing
  // a (possibly absent) git remote. Guarded ONLY on the CC_GITHUB_NAME_RE-
  // validated owner/repo truthiness — NOT a `.git` presence check, which is
  // the exact dependency the bug stems from. Fed only connectedOwner/
  // connectedRepo (validated above), never raw repoUrl or tool input.
  if (connectedOwner && connectedRepo) {
    effectiveSystemPrompt += `\n\n${buildConnectedRepoContext(connectedOwner, connectedRepo)}`;
  }

  // nosemgrep: path-join-resolve-traversal -- workspacePath is server-resolved (fetchUserWorkspacePath, ADR-044), never user-tainted input.
  const pluginPath = path.join(workspacePath, "plugins", "soleur");

  // Synthetic AgentSession — the only place in the cc path where an
  // AgentSession exists. Registered into `_ccBashGates` per Bash
  // review-gate (Option A). The controller is bound to the Query
  // lifetime; closeConversation/reapIdle abort it.
  const controller = new AbortController();
  const session: AgentSession = {
    abort: controller,
    reviewGateResolvers: new Map(),
    sessionId: null,
  };

  // In-sandbox raw-git credential path (plan item 1). `GH_TOKEN` (above)
  // authenticates the `gh` CLI; raw `git push`/`fetch`/`pull` in the bwrap
  // sandbox needs a GIT_ASKPASS helper the sandbox can read+exec. The only
  // verified sandbox-readable allowWrite dir is `workspacePath`
  // (`buildAgentSandboxConfig` allowWrite:[workspacePath] +
  // `createSandboxHook` realpath-containment); `$HOME`/`/tmp` bwrap-visibility
  // is unverifiable. We write the helper into the repo's `.git/` directory
  // (under `workspacePath`, so the SAME containment guarantees sandbox
  // readability) rather than the working-tree root, for two reasons:
  //   1. `.git/` is outside the working tree, so the agent's own
  //      `git add -A`/commit/push can NEVER stage the helper into the user's
  //      repo (the working-tree-litter vector — review user-impact P1 / arch P2).
  //   2. A FIXED filename means the helper is reused per workspace: no
  //      per-dispatch accumulation, no cleanup lifecycle to get wrong, and it
  //      is concurrency-safe because the body is byte-identical and token-free
  //      (reads GIT_INSTALLATION_TOKEN at runtime). This replaces the prior
  //      per-dispatch random-name + AbortController-cleanup design, whose
  //      cleanup never fired on the normal completion path (the synthetic
  //      controller is only aborted via `_ccBashGates`, which is populated
  //      solely when a Bash review-gate fires — review arch P1 / perf P2).
  // When `.git` is absent (clone degraded → no repo) we fall back to the
  // workspace root; there is no commit vector without a repo. Only when a
  // token was minted (connected, membership-checked repo) — graceful-
  // degradation parity with GH_TOKEN. The token rides GIT_INSTALLATION_TOKEN
  // env, NEVER the script body or a remote URL, and is NEVER logged
  // (hr-github-app-auth-not-pat).
  let gitAskpassScriptPath: string | undefined;
  if (ghToken) {
    // nosemgrep: path-join-resolve-traversal -- workspacePath is server-resolved (fetchUserWorkspacePath, ADR-044), never user-tainted input.
    const gitDir = path.join(workspacePath, ".git");
    const askpassDir = existsSync(gitDir) ? gitDir : workspacePath;
    gitAskpassScriptPath = writeAskpassScriptTo(askpassDir, ".soleur-askpass.sh");
  }

  const ccDeps: CanUseToolDeps = {
    abortableReviewGate: (
      ccSession,
      gateId,
      signal,
      timeoutMs,
      options,
      gateKind,
    ) => {
      // Register BEFORE awaiting the resolver so a synchronous
      // `resolveCcBashGate` from a concurrent ws frame cannot race. P1: thread
      // the gate kind so the held disclosure registers under
      // `"autonomous_disclosure"` and only the owner-checked
      // `autonomous_disclosure_response` (which writes the ack first) can
      // release it — a `review_gate_response` carrying the same gateId no-ops.
      registerCcBashGate({
        userId: args.userId,
        conversationId: args.conversationId,
        gateId,
        session: ccSession,
        kind: gateKind ?? "review",
      });
      return abortableReviewGate(ccSession, gateId, signal, timeoutMs, options);
    },
    sendToClient: defaultSendToClient,
    notifyOfflineUser,
    // Per-(userId, conversationId) Bash command-prefix batched-approval
    // cache (#2921). Wired only on the cc path; the legacy runner stays
    // at the 2-option Bash gate. Revoked from
    // `cleanupCcBashGatesForConversation` so a closed/reaped conversation
    // doesn't leak grants.
    bashApprovalCache: getBashApprovalCache(args.userId, args.conversationId),
    // Issue B part 2 — resolved above (fail-closed false). When true, the
    // Bash branch auto-approves non-BLOCKED commands (blocklist stays
    // authoritative).
    bashAutonomous,
    // feat-bash-autonomous-default-on — first-run consent soft-gate inputs.
    // When bashAutonomous && autonomousAckAt==null && isOwner, the first
    // non-blocked command is HELD behind the disclosure ack instead of
    // auto-running.
    autonomousAckAt: autonomousAckAtMs,
    isOwner: isWorkspaceOwner,
    // P1 stale-snapshot — read the LIVE in-session ack posture (flipped by the
    // ws-handler on a successful ack) so command #2 after an ack is friction-free
    // instead of re-holding on the frozen cold-start snapshot.
    resolveAckPosture: () => autonomousAckPosture,
    // P1 defense-in-depth — re-read the persisted ack after a disclosure-hold
    // releases, BEFORE allowing the held command. A release that did not
    // actually write the ack (cross-frame attempt, transient ack-write fault)
    // re-holds/denies. Fail-closed null = deny. Reads the same membership-checked
    // RPC as the cold-start resolve (active workspace, server-derived).
    verifyAutonomousAck: () => resolveAutonomousAck(args.userId),
    // Real conversation-status write — replaces the prior no-op (#2920).
    // Delegates to the typed wrapper which enforces the R8 composite-key
    // invariant (`.eq("id", convId).eq("user_id", args.userId)`) and
    // mirrors errors to Sentry via `reportSilentFallback` per
    // `cq-silent-fallback-must-mirror-to-sentry`.
    //
    // The closure shape `(convId, status) => Promise<void>` is preserved
    // so `permission-callback.ts`'s 6 deps-injected call sites get
    // transitive R8 coverage with zero churn at the deps interface.
    updateConversationStatus: async (convId: string, status: string) => {
      // Runtime guard: protect against deps-injected callers passing a
      // status literal not in Conversation["status"]. The wrapper would
      // otherwise hand an invalid enum to Postgres which rejects the write
      // — and the closure's `Promise<void>` shape would swallow the error.
      if (!CONVERSATION_STATUS_VALUES.has(status)) {
        reportSilentFallback(null, {
          feature: "cc-dispatcher",
          op: "updateConversationStatus",
          message: `invalid conversation status: ${status}`,
          extra: { userId: args.userId, conversationId: convId, status },
        });
        return;
      }
      // Pause/resume the runner's runaway wall-clock based on whether
      // the conversation is awaiting a user response. The status
      // transitions are the source of truth: `"waiting_for_user"` →
      // pause; `"active"` → resume. Other statuses (`"completed"`,
      // `"failed"`) leave the timer untouched (the runner closes via
      // `onWorkflowEnded`/`closeConversation`). The `_runner` is
      // guaranteed populated here because this closure only runs from
      // inside an SDK Query that the runner already constructed.
      if (_runner) {
        if (status === "waiting_for_user") {
          _runner.notifyAwaitingUser(convId, true);
        } else if (status === "active") {
          _runner.notifyAwaitingUser(convId, false);
        }
      }
      await updateConversationFor(
        args.userId,
        convId,
        {
          status: status as Conversation["status"],
          last_active: new Date().toISOString(),
        },
        {
          feature: "cc-dispatcher",
          op: "updateConversationStatus",
          extra: { status },
          // Status transitions drive permission-callback waiting_for_user
          // events; a 0-rows write would emit a prompt for a deleted/
          // archived row that the UI no longer shows.
          expectMatch: true,
        },
      );
    },
  };

  try {
    // Build SDK options through the shared `buildAgentQueryOptions`
    // helper (#2922). Drift between this cc path and the legacy
    // `agent-runner.ts startAgentSession` is guarded by
    // `agent-runner-query-options.test.ts`.
    //
    // V2-13 Phase 1 (#2909): `readCcMcpAllowlist()` reads CC_MCP_ALLOWLIST
    // and returns `{}` for empty/unset (current behavior preserved bit-for-bit),
    // throws on Tier 3 denylist short-names (3 Plausible tools — permanent,
    // shared service-token cross-tenant credentials). Promotion of non-denylist
    // tools is Phase 2 (#3722, blocked-by Stage 6 #2939).
    return sdkQuery({
      prompt: args.prompt,
      options: buildAgentQueryOptions({
        workspacePath,
        pluginPath,
        credential,
        serviceTokens,
        // Issue A — minted GH_TOKEN (or undefined when no repo connected).
        ghToken,
        // Plan item 1 — in-sandbox raw-git GIT_ASKPASS helper path (or
        // undefined when no token was minted). The askpass token IS `ghToken`
        // (threaded as gitInstallationToken inside buildAgentEnv).
        gitAskpassScriptPath,
        systemPrompt: effectiveSystemPrompt,
        resumeSessionId: safeResumeSessionId,
        // readCcMcpAllowlist() (Phase 1: {}) plus the flag-gated, single-tool
        // soleur_platform server (edit_c4_diagram) merged in above.
        mcpServers: c4McpServers,
        // #3338 — auto-approve the cc-router's read-only tool surface so they
        // don't pay a canUseTool round-trip per call. This is auto-approve,
        // not restriction — see CC_PATH_ALLOWED_TOOLS doc comment.
        allowedTools: [...CC_PATH_ALLOWED_TOOLS],
        // #3338 — HARD-BLOCK Edit/Write at the SDK level so the model
        // cannot emit them. Bash is intentionally NOT in this list — it is
        // sandbox-gated (permission-callback Bash gate / safe-bash /
        // autonomous bypass) and runs inside the SDK bwrap sandbox whose
        // network egress is token-derived (see buildAgentSandboxConfig).
        // Merged with the canonical [WebSearch, WebFetch] disallowed list.
        extraDisallowedTools: CC_PATH_DISALLOWED_TOOLS,
        // SubagentStart sanitizer override: cc strips control chars +
        // U+2028/U+2029 (per learning
        // 2026-04-17-log-injection-unicode-line-separators.md) and
        // tags `ccPath: true` for audit-log filtering.
        subagentStartPayloadOverride: {
          sanitizer: (v: unknown) =>
            String(v ?? "")
              .replace(/[\x00-\x1f\x7f\u2028\u2029]/g, " ")
              .slice(0, 200),
          extraLogFields: { ccPath: true },
          logMessage: "Subagent started (cc-soleur-go)",
        },
        canUseTool: createCanUseTool({
          userId: args.userId,
          conversationId: args.conversationId,
          // R-AC14: non-undefined leaderId so `logPermissionDecision`
          // attributes the cc path. `CC_ROUTER_LEADER_ID` is a
          // non-routable leader id reserved for this purpose.
          leaderId: CC_ROUTER_LEADER_ID,
          workspacePath,
          // Allow the flag-gated edit_c4_diagram through canUseTool (its tier
          // is auto-approve; writeC4Diagram enforces the diagrams-dir scope).
          platformToolNames: c4ToolName ? [c4ToolName] : [],
          pluginMcpServerNames: [],
          repoOwner: "",
          repoName: "",
          session,
          controllerSignal: controller.signal,
          deps: ccDeps,
        }),
      }),
    });
  } catch (err) {
    // No askpass cleanup needed here: the helper is a fixed-name, token-free
    // file reused per workspace (written into `.git/`), so a startup throw
    // leaves nothing to leak (item 1).
    // Mirror the "sandbox required but unavailable" branch in
    // agent-runner.ts startAgentSession's catch (feature:
    // "agent-sandbox", op: "sdk-startup"). Other inner throws bubble up
    // to the runner's own queryFactory catch (which mirrors under
    // `feature: "soleur-go-runner"`).
    const errMsg = err instanceof Error ? err.message : String(err);
    if (errMsg.includes("sandbox required but unavailable")) {
      mirrorWithDebounce(
        err,
        {
          feature: "agent-sandbox",
          op: "sdk-startup",
          extra: {
            userId: args.userId,
            conversationId: args.conversationId,
            leaderId: CC_ROUTER_LEADER_ID,
          },
        },
        args.userId,
        "agent-sandbox:sdk-startup",
      );
    }
    throw err;
  }
  }); // end runWithByokLease
};

let _runner: SoleurGoRunner | null = null;
let _runnerSendToClient:
  | ((userId: string, message: WSMessage) => boolean)
  | null = null;

/**
 * Obtain the process-wide SoleurGoRunner. First invocation wires it to
 * the given `sendToClient` (ws-handler's already-exported helper).
 * Subsequent invocations with a DIFFERENT sendToClient is an error:
 * the runner captures its WS-emit closure at first construction.
 */
/**
 * `true` when the cc-soleur-go runner already owns a live `Query` for the
 * given conversation (warm path). Callers use this to skip work that the
 * cold-Query construction already did — most importantly,
 * `resolveConciergeDocumentContext` reads the user's open document into
 * the system prompt at cold dispatch only; subsequent turns reuse the
 * baked prompt, so the per-turn `readFile` + workspace lookup is
 * pure-overhead. Returns `false` when no runner exists yet.
 */
export function hasActiveCcQuery(conversationId: string): boolean {
  if (!_runner) return false;
  return _runner.hasActiveQuery(conversationId);
}

/**
 * #5356 — signal the process-wide cc runner to close a conversation's live
 * `Query` from OUTSIDE a dispatch (the ws-handler disconnect grace timer).
 * Mirrors `hasActiveCcQuery`'s `_runner`-direct accessor shape so the caller
 * does not need to thread `sendToClient`. A no-op when no runner exists yet OR
 * the conversation has no live `activeQueries` entry (a legacy-path or already-
 * completed conversation — `closeConversation` itself no-ops on a missing
 * entry). `reason === "disconnected"` threads to the close hook and triggers
 * the in-flight checkpoint.
 */
export function closeCcConversation(
  conversationId: string,
  reason?: "disconnected",
): void {
  if (!_runner) return;
  _runner.closeConversation(conversationId, reason);
}

// #5371 — cadence for the in-process cc idle reaper. Kept a LOCAL literal
// (not exported, not a runtime knob): coupling it to agent-runner's
// module-private STUCK_ACTIVE_CHECK_INTERVAL_MS would entangle two
// unrelated reapers. ≤ DEFAULT_IDLE_REAP_MS (10min, in soleur-go-runner.ts)
// so an idle query is reaped within ~1 interval of crossing the window.
const CC_IDLE_REAPER_INTERVAL_MS = 300_000;

/**
 * #5371 — reap idle cc queries from OUTSIDE a dispatch (the boot-time
 * scheduler). Mirrors `closeCcConversation`'s `_runner`-guarded accessor
 * shape so the caller never forces runner creation (no `sendToClient`
 * closure needed). No-op → 0 when no runner exists yet.
 */
export function reapIdleCcQueries(): number {
  if (!_runner) return 0;
  return _runner.reapIdle();
}

/**
 * #5371 — drain EVERY active cc query on SIGTERM, aborting WITHOUT a
 * checkpoint (legacy `abortAllSessions` parity — the disconnect grace-abort
 * terminal, #5362, is what preserves uncommitted work; shutdown only stops
 * API spend + flips status cleanly). No-op → 0 when no runner exists yet.
 */
export function drainCcQueriesForShutdown(): number {
  if (!_runner) return 0;
  return _runner.closeAllForShutdown();
}

/**
 * #5371 — start the boot-time cc idle-reaper. Mirrors
 * `startStuckActiveReaper` (in agent-runner.ts): a `setInterval` returning
 * the timer, `unref()`'d before return so it never blocks shutdown. The
 * explicit `clearInterval` on SIGTERM is belt-and-suspenders on top of
 * `unref()`, not a replacement. The callback only ever calls the
 * null-guarded `reapIdleCcQueries()` — never `_runner.reapIdle()` directly.
 */
export function startCcIdleReaper(): NodeJS.Timeout {
  const timer = setInterval(() => {
    try {
      reapIdleCcQueries();
    } catch (err) {
      // reapIdle is synchronous in-memory Map iteration (no I/O), so this
      // catch is defensive per cq-silent-fallback-must-mirror-to-sentry —
      // not an expected-to-fire path.
      reportSilentFallback(err, { feature: "cc-idle-reaper", op: "reap" });
    }
  }, CC_IDLE_REAPER_INTERVAL_MS);
  timer.unref();
  return timer;
}

export function getSoleurGoRunner(
  sendToClient: (userId: string, message: WSMessage) => boolean,
): SoleurGoRunner {
  if (_runner) {
    if (_runnerSendToClient !== sendToClient) {
      reportSilentFallback(
        new Error(
          "getSoleurGoRunner: re-init with different sendToClient — the runner's WS-emit closure is captured at first call",
        ),
        { feature: "cc-dispatcher", op: "getSoleurGoRunner" },
      );
    }
    return _runner;
  }
  _runnerSendToClient = sendToClient;
  _runner = createSoleurGoRunner({
    queryFactory: realSdkQueryFactory,
    pendingPrompts: getPendingPromptRegistry(),
    emitInteractivePrompt: (userId, event) => {
      // Stage 2 emits the feature-local shape. Stage 3 extends WSMessage
      // with the full discriminated sub-union; until then, cast at the
      // wire boundary.
      sendToClient(userId, event as unknown as WSMessage);
    },
    // Drain `_ccBashGates` from EVERY internal close path, AND checkpoint
    // in-flight work on a `disconnected` grace-abort (#5356). Without the
    // drain, `runner.reapIdle()` / `runner.closeConversation()` close the
    // Query without firing `onWorkflowEnded`, so the dispatch-side cleanup is
    // never reached and the gate registry leaks. The runner fires this BEFORE
    // `activeQueries.delete`. See `handleCcCloseQuery`.
    onCloseQuery: handleCcCloseQuery,
    defaultCostCaps: readCcCostCaps(),
  });
  return _runner;
}

// ---------------------------------------------------------------------------
// Orchestration
// ---------------------------------------------------------------------------

export interface DispatchSoleurGoArgs {
  userId: string;
  conversationId: string;
  userMessage: string;
  currentRouting: ConversationRouting;
  sessionId?: string | null;
  sendToClient: (userId: string, message: WSMessage) => boolean;
  persistActiveWorkflow: (workflow: WorkflowName | null) => Promise<void>;
  /**
   * KB Concierge document context. The ws-handler resolves these from the
   * open KB document (start_session `pendingContext` for first turn,
   * `conversations.context_path` lookup for subsequent turns) and passes
   * them through. The runner threads them into `buildSoleurGoSystemPrompt`
   * which mirrors the legacy `agent-runner.ts` injection (PDFs get a
   * Read directive; text inlines content up to 50KB).
   */
  artifactPath?: string;
  documentKind?: "pdf" | "text";
  documentContent?: string;
  /**
   * 2026-05-06 follow-up to #3338. Set by `resolveConciergeDocumentContext`
   * when the in-process PDF extractor surfaced a typed failure class. The
   * runner emits `buildPdfUnreadableDirective` (content-grounded reply)
   * instead of `buildPdfGatedDirective` (apt-get-cascade-prone Read path).
   */
  documentExtractError?: PdfExtractErrorClass;
  /**
   * 2026-05-07 follow-up to #3429. Per-failure metadata. Currently only
   * `numPages` (interpolated by `buildPdfTooLongDirective` for the
   * page-count gate's "I see {N} pages" copy). Without plumbing through
   * here, the runner reads `?? 0` and the user sees "I see 0 pages" on
   * every triggering case. Caught by the user-impact-reviewer review of
   * PR #3430.
   */
  documentExtractMeta?: DocumentExtractMeta;
  /**
   * 2026-05-06 follow-up — Bug A1 fix. Resolved workspace path threaded
   * from the ws-handler through `runner.dispatch` →
   * `buildSoleurGoSystemPrompt` so PDF gated + text-too-large directives
   * can inject workspace-absolute Read paths. Required by the SDK Read
   * tool's `file_path` "absolute path" contract; passing relative paths
   * triggered the sandbox-deny path that produced the user-facing
   * "outside my workspace boundary" reply (#3376).
   */
  workspacePath?: string;
  /**
   * Attachment refs uploaded via the chat-input paperclip flow. When
   * non-empty, `dispatchSoleurGo` (a) inserts a `messages` row to
   * satisfy the `message_attachments.message_id` FK, (b) calls the
   * shared attachment-pipeline helper to persist metadata + download
   * files into `<workspace>/attachments/<convId>/`, and (c) augments
   * `userMessage` with the resulting `attachmentContext` text so the
   * agent can `Read` the on-disk paths. Mirrors the legacy
   * `agent-runner.ts:sendUserMessage` flow exactly. See #3254.
   */
  attachments?: AttachmentRef[];
  /**
   * #3266 — fire-and-forget hook that the dispatcher invokes after a
   * successful `persistCcSessionId` and after a `clearCcSessionId`. The
   * ws-handler uses it to mutate the in-process `ClientSession.sessionId`
   * cache so a subsequent chat-case warm-cache turn forwards the
   * just-persisted value (instead of the stale `null` seeded on
   * materialization). Without this, runner-reap-during-live-WS scenarios
   * use `args.sessionId = null` on the next cold-Query construction,
   * defeating the prefill guard's history-probe branch. Receives `null`
   * on the stale-clear path.
   */
  onSessionIdPersisted?: (sessionId: string | null) => void;
}

/**
 * #3266 — persist the SDK-emitted `session_id` back to
 * `conversations.session_id` so the next cold-Query construction (server
 * restart, idle reap, container restart) seeds `args.sessionId` and the
 * runner can `resume:` the SDK session. The write is fire-and-forget
 * because the user's current turn does NOT depend on it landing; failures
 * mirror to Sentry via `updateConversationFor` and the next turn's
 * in-memory `state.sessionId` covers the warm-Query case.
 */
async function persistCcSessionId(args: {
  userId: string;
  conversationId: string;
  sessionId: string;
}): Promise<void> {
  const { ok, error } = await updateConversationFor(
    args.userId,
    args.conversationId,
    { session_id: args.sessionId },
    {
      feature: "cc-dispatcher",
      op: "persist-session-id",
      expectMatch: true,
    },
  );
  if (!ok) {
    // updateConversationFor already mirrors to Sentry; log here only for
    // cross-debugging with legacy `agent-runner.ts` parity.
    log.error(
      { conversationId: args.conversationId, err: error },
      "cc-dispatcher: failed to persist session_id",
    );
  }
}

/**
 * #3266 R7 — clear a stale `conversations.session_id` after the SDK
 * rejects `resume:` for a non-KeyInvalidError reason (missing session
 * file, schema drift). Without this, the next cold-Query retries the
 * same bad session_id indefinitely. Mirrors the legacy
 * `agent-runner.ts` stale-clear behavior.
 */
async function clearCcSessionId(args: {
  userId: string;
  conversationId: string;
}): Promise<void> {
  // Default `expectMatch: false` — a concurrent close/archive race
  // (legitimate 0-rows outcome) is silent success here, matching legacy
  // `agent-runner.ts` stale-clear parity. The composite-key invariant
  // (`.eq("id", ...).eq("user_id", ...)`) is enforced inside the wrapper
  // regardless. Real DB errors still mirror to Sentry.
  const { ok, error } = await updateConversationFor(
    args.userId,
    args.conversationId,
    { session_id: null },
    {
      feature: "cc-dispatcher",
      op: "clear-stale-session-id",
    },
  );
  if (!ok) {
    log.error(
      { conversationId: args.conversationId, err: error },
      "cc-dispatcher: failed to clear stale session_id",
    );
  }
}

/**
 * One-liner ws-handler wiring for the soleur-go chat path. Builds the
 * runner events and forwards them to the WS client using the existing
 * `stream` / `tool_use` / `session_ended` WSMessage variants for
 * backwards compatibility (Stage 3 will add dedicated `workflow_*`
 * events).
 */
export async function dispatchSoleurGo(
  args: DispatchSoleurGoArgs,
): Promise<void> {
  const {
    userId,
    conversationId,
    userMessage: rawUserMessage,
    currentRouting,
    sessionId,
    sendToClient,
    persistActiveWorkflow,
    artifactPath,
    documentKind,
    documentContent,
    documentExtractError,
    documentExtractMeta,
    workspacePath: callerWorkspacePath,
    attachments,
    onSessionIdPersisted,
  } = args;

  // Verify conversation ownership AND bump `last_active` in a single
  // round-trip. `updateConversationFor` with `expectMatch: true` runs the
  // UPDATE scoped to (id, user_id) and returns `ok: false` when zero rows
  // matched — that's our 404 signal. Sentry mirroring on failure happens
  // inside the wrapper, so we only translate to the throw here. Routes
  // through the canonical wrapper per the R8 lint rule.
  const ownership = await updateConversationFor(
    userId,
    conversationId,
    { last_active: new Date().toISOString() },
    {
      feature: "cc-dispatcher",
      op: "verify-conversation-ownership",
      expectMatch: true,
    },
  );
  if (!ownership.ok) {
    throw new Error("Conversation not found");
  }

  // #3254 — persist a `messages` row for every cc turn so
  // `message_attachments.message_id` can be FK'd. The legacy single-leader
  // path has always done this in `agent-runner.ts:sendUserMessage`; the
  // cc path silently dropped attachments because no parent message existed.
  // The SDK's session-id resume mechanism still owns transcript replay
  // for the agent — these rows are for attachment metadata durability and
  // for `api-messages.ts` history hydration on tab reload.
  //
  // #3603 W1 — same write-boundary sentinel as `saveAssistantMessage`.
  // User-content rows carry PII; a misrouted dispatch persisting User A's
  // text into User B's conversation is the same Art. 33/34 surface as the
  // assistant row. Throws (rather than the assistant path's `return`)
  // because this insert is awaited and a halt here cleanly aborts the
  // dispatch via the existing user-INSERT-failure path below.
  if (!assertWriteScope(userId, conversationId)) {
    throw new Error(
      "cc-dispatcher: assertWriteScope halted user-message persistence",
    );
  }
  // PR-C §2.11 (#3244): tenant-scoped message INSERTs. Post-migration 059,
  // RLS on `messages` requires `workspace_id` to be a workspace the caller is
  // a member of (`messages_workspace_member_insert` WITH CHECK
  // `is_workspace_member(workspace_id, auth.uid())`); we derive `workspace_id`
  // from the parent conversation, which the caller's conversation-RLS already
  // gated on membership (the ownership probe above). The `assertWriteScope`
  // sentinel is the defense-in-depth layer. The implicit JWT mint is the auth
  // probe — see ws-handler `tenantFor` doc-comment.
  //
  // Wrap mint in try/catch so a transient RuntimeAuthError gets a
  // structured Sentry mirror before the throw bubbles into the outer
  // dispatch pipeline (the dispatch's existing user-INSERT-failure path
  // produces an unstructured generic error otherwise).
  let tenant: Awaited<ReturnType<typeof getFreshTenantClient>>;
  try {
    tenant = await getFreshTenantClient(userId);
  } catch (mintErr) {
    reportSilentFallback(mintErr, {
      feature: "cc-dispatcher",
      op: "tenant-mint.persistUserMessage",
      extra: { userId, conversationId },
    });
    throw mintErr;
  }

  // Read the parent conversation's `workspace_id` once via the already-minted
  // tenant client (no second mint — Kieran single-RTT). Threaded into BOTH the
  // user-row INSERT below and the assistant-row INSERT (via `buildRow`) so
  // every interactive `messages` write satisfies the mig-059 WITH CHECK. On
  // read failure, mirror to Sentry and throw — never proceed to a NULL
  // workspace_id INSERT (which would 500 under RLS).
  const { data: convWsRow, error: convWsErr } = await tenant
    .from("conversations")
    .select("workspace_id")
    .eq("id", conversationId)
    .single();
  if (convWsErr || !convWsRow) {
    reportSilentFallback(convWsErr ?? new Error("conversation workspace_id not found"), {
      feature: "cc-dispatcher",
      op: "persistUserMessage.workspaceRead",
      extra: { userId, conversationId },
    });
    throw new Error(
      `Failed to resolve conversation workspace_id: ${convWsErr?.message ?? "row absent"}`,
    );
  }
  const conversationWorkspaceId = convWsRow.workspace_id as string;

  const messageId = randomUUID();
  const { error: insertErr } = await tenant.from("messages").insert({
    id: messageId,
    conversation_id: conversationId,
    workspace_id: conversationWorkspaceId,
    // mig 053: messages.template_id NOT NULL (no default). Interactive
    // messages use the 'default_legacy' sentinel (see buildRow). #4839.
    template_id: "default_legacy",
    role: "user",
    content: rawUserMessage,
    tool_calls: null,
    leader_id: null,
  });
  if (insertErr) {
    reportSilentFallback(insertErr, {
      feature: "cc-dispatcher",
      op: CC_OP_SLUGS.persistUserMessage,
      extra: { userId, conversationId },
    });
    throw new Error(`Failed to save user message: ${insertErr.message}`);
  }

  // Persist attachment metadata + download files into the workspace.
  // Mirrors `agent-runner.ts:sendUserMessage` exactly via the shared
  // helper. On any per-file download failure, the helper omits that file
  // from the `attachmentContext` text — partial success is preferred over
  // a hard turn failure. Validation/INSERT errors propagate to the outer
  // dispatch catch, which mirrors via `mirrorWithDebounce` (no inner
  // try/catch — that would double-mirror and bypass the dispatch
  // debounce, flooding Sentry on a misconfigured Storage URL).
  // PR-D §3 (#3244 §4): tenant-scoped attachments. Reuse the `tenant` mint
  // from the persistUserMessage block above (same userId, same turn — minting
  // a second client would add an unnecessary RTT per Kieran P2-2). Storage
  // RLS in migration 019 (SELECT) + 045 (INSERT/UPDATE/DELETE) is now
  // load-bearing; the path-prefix check at attachment-pipeline.ts:83-86 is
  // defense-in-depth.
  let userMessage = rawUserMessage;
  if (attachments && attachments.length > 0) {
    const { attachmentContext } = await persistAndDownloadAttachments({
      supabase: tenant,
      userId,
      conversationId,
      messageId,
      attachments,
    });
    if (attachmentContext) {
      userMessage = `${rawUserMessage}\n\n${attachmentContext}`;
    }
  }

  const runner = getSoleurGoRunner(sendToClient);

  // Resolve workspace path in parallel with `runner.dispatch` so cold-start
  // LTFT (latency-to-first-token) does not pay an extra serial Supabase RTT.
  // The closure-shared `workspacePath` is filled by the `.then` below; in
  // production, `realSdkQueryFactory` independently resolves the same active
  // workspace before the SDK Query can emit any block, so by the time
  // `onToolUse` fires the value is set. `fetchUserWorkspacePath` resolves the
  // ACTIVE workspace (ADR-044) on each call — a single indexed
  // `user_session_state` read — so this `.then` is a cheap parallel resolve.
  // On failure, fall back to `undefined` — `buildToolLabel` still produces
  // the verbose label (just without the workspace-prefix scrub) and the
  // error is mirrored to Sentry per `cq-silent-fallback-must-mirror-to-sentry`.
  let workspacePath: string | undefined;
  void fetchUserWorkspacePath(userId)
    .then((wp) => {
      workspacePath = wp;
    })
    .catch((err) => {
      reportSilentFallback(err, {
        feature: "cc-dispatcher",
        op: "workspace-resolve",
        extra: { userId, conversationId },
      });
    });

  // #3639 F1 — Per-dispatch per-turn state cell. Wraps the four mutable
  // cells (text accumulator, abort flag, turn index, pending usage) so
  // reset-symmetry is a class invariant rather than four parallel
  // `let` declarations. Mirrors the REPLACE semantic at
  // `chat-state-machine.ts:477` (W8). See class doc-comment for the
  // method contract.
  const state = new TurnPersistenceState();

  // BYOK Delegations PR-A (#4232) closure-capture. The lease opens
  // inside realSdkQueryFactory and closes before onResult fires.
  // realSdkQueryFactory writes to this variable via the
  // `setDelegationContext` sink threaded through DispatchArgs →
  // QueryFactoryArgs; onResult reads it to route persistTurnCost
  // through the merged atomic RPC when a delegation is active.
  let leaseDelegationCtx:
    | { delegationId: string; callerUserId: string }
    | undefined;
  const setDelegationContext = (
    ctx: { delegationId: string; callerUserId: string } | undefined,
  ): void => {
    leaseDelegationCtx = ctx;
  };

  // feat-concierge-stream-commands — streaming-posture closure cell (D1),
  // published by `realSdkQueryFactory.setBashAutonomous` once it resolves
  // the owner-gated toggle. Read by `onToolResult` to gate command_stream
  // emission: we stream command/output ONLY in the autonomous posture
  // (where the review-gate is bypassed and no card surface exists). In the
  // non-autonomous posture the review-gate is the active surface and we
  // emit nothing (AC9). Fail-closed `false` until the factory publishes.
  let bashAutonomousPosture = false;
  const setBashAutonomous = (autonomous: boolean): void => {
    bashAutonomousPosture = autonomous;
  };

  // FIX 6 (Security P3-2) — warm-query posture. `setBashAutonomous` is also
  // published inside `realSdkQueryFactory`'s lease body, but that factory runs
  // ONLY on a COLD conversation; on warm-query reuse it is not re-invoked, so
  // `bashAutonomousPosture` would stay fail-closed `false` and streaming would
  // silently never fire for warm conversations. Re-resolve the owner-gated
  // toggle per-dispatch here (same fire-and-forget pattern as the
  // `fetchUserWorkspacePath` resolve below) so BOTH cold and warm turns publish
  // the posture. `resolveBashAutonomous` reads the ACTIVE workspace toggle (one
  // indexed read); on the cold path the factory re-publishes the same value
  // (idempotent overwrite). Resolves before any Bash `tool_use` can surface
  // (the SDK Query must first build + emit text/tool blocks). Failure →
  // fail-closed (leave `false`) and mirror to Sentry.
  void resolveBashAutonomous(userId)
    .then((autonomous) => {
      setBashAutonomous(autonomous);
    })
    .catch((err) => {
      reportSilentFallback(err, {
        feature: "cc-dispatcher",
        op: "bash-autonomous-resolve",
        extra: { userId, conversationId },
      });
    });

  // #5340 / #5240 design item #2 — deterministic workspace re-provision on
  // reconnect. After a sandbox/host reclaim the resolved workspace path can be a
  // fresh filesystem with no repo. The factory-internal self-heal
  // (`ensureWorkspaceRepoCloned` in `realSdkQueryFactory`) runs ONLY on a COLD conversation;
  // warm-query reconnect (the epic's headline scenario) never re-invokes the
  // factory. Re-provision per-dispatch here — same fire-and-forget pattern as the
  // `setBashAutonomous` warm-query resolve above — so BOTH cold and warm turns
  // recover AND publish the outcome the honest-message branch reads.
  //
  // `reprovisionOutcome` is the POST-recovery signal: `onWorkflowEnded` shows the
  // honest "workspace reclaimed" message ONLY when a `worktree_enter_failed` turn
  // is paired with `"failed"` here — the message is gated AFTER the recovery
  // (placement learning 2026-06-14-short-circuit-guard-must-sit-after-the-
  // recovery-it-gates.md), never before. Idempotent with the cold factory call
  // (`.git`-absent-gated). Fail-closed `undefined` → generic retryable message.
  let reprovisionOutcome: ReprovisionOutcome | undefined;
  void reprovisionWorkspaceOnDispatch(userId)
    .then((outcome) => {
      reprovisionOutcome = outcome;
    })
    .catch((err) => {
      // reprovisionWorkspaceOnDispatch is already fail-soft (returns "ok" on a
      // resolver error); this catch is belt-and-suspenders for an unexpected
      // synchronous throw and leaves the outcome unresolved (generic message).
      reportSilentFallback(err, {
        feature: "cc-dispatcher",
        op: "reprovision-on-dispatch-publish",
        extra: { userId, conversationId },
      });
    });

  // feat-debug-mode-stream — per-dispatch debug-stream gate. Two INDEPENDENT
  // conditions, BOTH required for any debug_event to emit (read as `let`
  // bindings, mirroring `bashAutonomousPosture`'s fire-and-forget resolve so
  // BOTH cold and warm turns publish the gate before any SDK block surfaces;
  // failure leaves the fail-closed `false`):
  //   (1) `debugPosture` — the ACTIVE workspace's `debug_mode` toggle is ON
  //       (`resolveDebugMode`, member-checked RPC, fail-closed false).
  //   (2) `debugEligible` — the dispatch user is in the `dev` cohort AND the
  //       `debug-mode` Flagsmith flag is on (`isDebugModeAvailable` hard-gates
  //       `role !== "dev"` BEFORE the flag — fail-CLOSED on a Flagsmith outage,
  //       P0-8). Role is read from the SAME `users.role` shape as the
  //       c4-visualizer gate above.
  // Per-dispatch resolution (not ClientSession-carried) also solves toggle
  // propagation for free: the NEXT turn re-resolves fresh (≤1-turn latency on
  // a mid-turn flip — AC6). The debug stream is a scoped exception to the
  // #2138 raw-tool-input invariant; the redaction + DROP-first gate lives
  // entirely in `server/debug-event.ts`, so the shared `probeRedactionFallthrough`
  // is untouched.
  let debugPosture = false;
  let debugEligible = false;
  void resolveDebugMode(userId)
    .then((enabled) => {
      debugPosture = enabled;
    })
    .catch((err) => {
      reportSilentFallback(err, {
        feature: "cc-dispatcher",
        op: "debug-mode-resolve",
        extra: { userId, conversationId },
      });
    });
  void (async () => {
    const debugTenant = await getFreshTenantClient(userId);
    const { data: roleRow } = await debugTenant
      .from("users")
      .select("role")
      .eq("id", userId)
      .single<{ role: unknown }>();
    const role: Role = roleRow?.role === "dev" ? "dev" : "prd";
    debugEligible = await isDebugModeAvailable({ userId, role, orgId: null });
  })().catch((err) => {
    reportSilentFallback(err, {
      feature: "cc-dispatcher",
      op: "debug-mode-eligibility",
      extra: { userId, conversationId },
    });
  });

  // Per-command total-output budget tracker (D4), keyed by `toolUseId`.
  // Bounds cumulative bytes across however many result blocks one command
  // produces. Entry created on first output chunk; the per-dispatch lifetime
  // matches the conversation turn (in-memory, GC'd with the closure).
  const commandOutputBytes = new Map<string, number>();

  // #3603 W4 — cc-path narrows the type-wide `Message.usage` shape to
  // cost-only on `'complete'` turns (Art. 5(1)(c) data-minimization). The
  // legacy agent-runner path emits the full `UsageSnapshot` (input_tokens,
  // output_tokens, cost_usd, completed_actions[]) on `'aborted'` turns —
  // see `Message.usage` doc-comment in `lib/types.ts`. `PersistMode` is
  // declared at module scope above (#3640 F2 + #3641 type-rail).
  async function saveAssistantMessage(
    mode: PersistMode,
    text: string,
  ): Promise<void> {
    // #3603 W1 — Cross-tenant write-boundary sentinel. Post-migration 059,
    // RLS on `messages` requires `workspace_id` to be a workspace the caller
    // is a member of (`messages_workspace_member_insert` WITH CHECK
    // `is_workspace_member(workspace_id, auth.uid())`); we derive it from the
    // parent conversation, which the caller's conversation-RLS already gated on
    // membership. This guard catches the residual case where the dispatch
    // closure's userId/conversationId disagree with a future SDK-payload-derived
    // identifier — RLS cannot, since the JWT is A's and the row's workspace_id
    // is A-member-gated. Returns `false` only via the test seam today (sentinel
    // placeholder); load-bearing call site for that future identifier
    // comparison. See `assertWriteScope` module-level doc.
    if (!assertWriteScope(userId, conversationId)) return;

    // Empty-drop contract (PR-A1): an empty-text turn produces no row.
    // The state-class's `consumeForComplete` / `consumeForAbort` callers
    // already short-circuit on empty text, but guard here defensively so a
    // future caller can't silently produce an empty assistant row.
    if (!text) return;

    const row = buildRow(mode, text, conversationId, conversationWorkspaceId);
    // PR-C §2.11 (#3244): tenant-scoped assistant-row INSERT. Reuses
    // the `tenant` minted at function entry (above the user-row INSERT) and
    // the `conversationWorkspaceId` read once there (mig 059 member-keyed RLS).
    const { error } = await tenant.from("messages").insert(row);
    if (error) {
      mirrorInsertError(error, mode, userId, conversationId, text);
    }
  }

  // #5214 — per-`toolUseId` debounce for the `tool_progress` forward. The SDK
  // emits heartbeats every few seconds; the client only needs one per 5s to
  // reset its 45s watchdog. Scoped to THIS dispatch (per-call cleanup model —
  // no module-level cache, so no eviction concern) and keyed by `toolUseId` so
  // separate tools don't share a window. Mirrors `agent-runner.ts:1864-1865`.
  const TOOL_PROGRESS_DEBOUNCE_MS = 5_000;
  const toolProgressLastSentAt = new Map<string, number>();

  const events: DispatchEvents = {
    onText: (text) => {
      // #3603 W8 — replace, not append. Mirrors chat-state-machine REPLACE
      // semantic so persisted content matches the UI's live render.
      // See `TurnPersistenceState.setText` for invariant + AC11 source.
      state.setText(text);
      sendToClient(userId, {
        type: "stream",
        content: text,
        partial: true,
        leaderId: CC_ROUTER_LEADER_ID,
      });
      // feat-debug-mode-stream — mirror assistant text into the debug stream as
      // a `reasoning` event (the Concierge path has no thinking/progress seam;
      // P0-2 maps "reasoning" → onText). Redacted-or-dropped + gated inside
      // `emitDebugEvent`; a prose secret that survives redaction drops the frame.
      emitDebugEvent({
        enabled: debugPosture && debugEligible,
        kind: "reasoning",
        rawValue: text,
        userId,
        conversationId,
        send: (frame) => sendToClient(userId, frame),
      });
    },
    onToolProgress: (block) => {
      // #5214 — forward the runner's mid-tool heartbeat to the client so the
      // client-side stuck-watchdog (STUCK_TIMEOUT_MS, 45s) is fed during a
      // long single-tool execution. Without this, a >90s tool flips the
      // cc_router bubble to a terminal `error` state. Mirrors the legacy
      // agent-runner forward (agent-runner.ts:1928-1946).
      //
      // Debounce per `toolUseId`: the first heartbeat for a tool always
      // forwards; subsequent heartbeats wait for the 5s window to elapse.
      const now = Date.now();
      const last = toolProgressLastSentAt.get(block.toolUseId);
      if (last === undefined || now - last >= TOOL_PROGRESS_DEBOUNCE_MS) {
        toolProgressLastSentAt.set(block.toolUseId, now);
        // `buildToolProgressWSMessage` pins the #2138 invariant: the raw SDK
        // tool name is routed through `buildToolLabel` (human label only) and
        // never placed on the wire. Shared with the `tool_use` forward shape.
        sendToClient(
          userId,
          buildToolProgressWSMessage({
            toolName: block.toolName,
            elapsedSeconds: block.elapsedSeconds,
            toolUseId: block.toolUseId,
            workspacePath,
            leaderId: CC_ROUTER_LEADER_ID,
          }),
        );
      }
      // NO debug-event emit for `tool_progress`: it is a heartbeat with no
      // displayable payload, and `debugEventSchema.kind` has no `tool_progress`
      // variant (ws-zod-schemas.ts). Parity with agent-runner, which also does
      // not mirror heartbeats to the debug panel. Do not "fix" this omission.
    },
    onToolUse: (block) => {
      // #2909 FR2 — silent-failure mirror for unregistered platform tools.
      // When `mcpServers === {}` (Phase 1 default), the Claude Agent SDK
      // rejects `mcp__soleur_platform__*` calls at model-validation time
      // and `canUseTool` is NEVER invoked. The model gets a `tool_result`
      // error with no Sentry signal — a silent-failure surface that violates
      // `cq-silent-fallback-must-mirror-to-sentry`. Mirror via
      // `mirrorWithDebounce` (per-(userId, errorClass) 5-min TTL) so a
      // misconfigured leader skill that loops on the same unregistered tool
      // cannot flood Sentry. Intrinsically scoped to cc-router because this
      // callback only fires from `dispatchSoleurGo` (legacy
      // `startAgentSession` is a separate path).
      if (shouldMirrorUnregisteredPlatformToolUse(block.name, CC_REGISTERED_PLATFORM_TOOL_NAMES)) {
        const safeToolName = sanitizeToolNameForLog(block.name);
        mirrorWithDebounce(
          null,
          {
            feature: "cc-mcp-tier",
            op: "unregistered-tool-invoked",
            message: `cc-router skill attempted unregistered platform tool ${safeToolName}`,
            extra: {
              toolName: safeToolName,
              toolUseId: block.toolUseId,
              userId,
              conversationId,
              leaderId: CC_ROUTER_LEADER_ID,
              mcpAllowlistConfigured: Boolean(process.env.CC_MCP_ALLOWLIST?.trim()),
            },
          },
          userId,
          "cc-mcp-tier:unregistered-tool",
        );
      }
      // `buildToolUseWSMessage` pins the #2138 invariant: the raw SDK tool
      // name is NOT placed on the wire (information-disclosure mitigation,
      // see PR #2115). Shared with `agent-runner.ts` so a future schema
      // change to `tool_use` flows through one edit, not two parallel ones.
      sendToClient(
        userId,
        buildToolUseWSMessage({
          name: block.name,
          input: block.input,
          workspacePath,
          leaderId: CC_ROUTER_LEADER_ID,
        }),
      );

      // feat-debug-mode-stream — mirror the tool-use into the debug stream as a
      // `tool_use` event carrying the RAW parsed input object. `buildDebugEvent`
      // redacts per-string-leaf + key-aware, then runs the DEBUG_REDACTION_PROBES
      // superset; on a probe trip it DROPs the input to a placeholder but keeps a
      // HUMAN label (`buildToolLabel(name, undefined, …)` — never the raw SDK
      // tool name, #2138/PR#2115). `block.name`/`block.input` are passed raw;
      // all redaction happens inside the gated emit helper.
      emitDebugEvent({
        enabled: debugPosture && debugEligible,
        kind: "tool_use",
        rawValue: block.input,
        toolName: block.name,
        workspacePath,
        userId,
        conversationId,
        send: (frame) => sendToClient(userId, frame),
      });

      // feat-concierge-stream-commands — emit the `command_stream`
      // `phase:"start"` carrying the REDACTED command, ONLY in the
      // autonomous posture (D1: the review-gate is bypassed, so the inline
      // terminal block is the user's only visible record). The redaction
      // runs at THIS emit boundary (TR4); render-time is belt-and-suspenders.
      // Emit failures mirror to Sentry (cq-silent-fallback-must-mirror).
      if (bashAutonomousPosture && block.name === "Bash") {
        const rawCommand =
          typeof block.input.command === "string" ? block.input.command : "";
        try {
          // FIX 4 — byte-cap the RAW command BEFORE redaction (mirrors the
          // output path); caps the wire payload + redaction back-tracking.
          const cappedCommand = capUtf8Bytes(
            rawCommand,
            COMMAND_STREAM_COMMAND_CAP_BYTES,
          );
          const redactedCommand = probeRedactionFallthrough(
            redactCommandForDisplay(
              cappedCommand.truncated
                ? `${cappedCommand.text}${COMMAND_STREAM_TRUNCATION_MARKER}`
                : cappedCommand.text,
            ),
            { userId, conversationId, field: "command" },
          );
          sendToClient(userId, {
            type: "command_stream",
            leaderId: CC_ROUTER_LEADER_ID,
            phase: "start",
            command: redactedCommand,
            // FIX 2 — correlate this block to its output/end frames.
            toolUseId: block.toolUseId,
          });
        } catch (err) {
          reportSilentFallback(err, {
            feature: "cc-dispatcher",
            op: "emitCommandStream",
            extra: { userId, conversationId, phase: "start" },
          });
        }
      }
    },
    onToolResult: (block) => {
      // feat-concierge-stream-commands — stream the Bash command's
      // (truncated, REDACTED) stdout/stderr into the cc_router bubble, then
      // close the block. Autonomous-only (D1). Both the per-chunk and the
      // per-command total caps (D4) apply; redaction is the emit-boundary
      // gate (TR4) with a fallthrough probe → Sentry. Emit failures mirror.
      if (!bashAutonomousPosture) return;
      try {
        // 1) Per-chunk cap on the RAW output (caps regex back-tracking too).
        const chunkCapped = capUtf8Bytes(
          block.output,
          COMMAND_STREAM_CHUNK_CAP_BYTES,
        );

        // 2) Per-command total budget. Subtract what's already been emitted
        //    for this toolUseId; if the budget is exhausted, mark truncated
        //    and emit nothing further beyond the marker (carried by `end`).
        const priorBytes = commandOutputBytes.get(block.toolUseId) ?? 0;
        const remaining = Math.max(0, COMMAND_STREAM_TOTAL_CAP_BYTES - priorBytes);
        const totalCapped = capUtf8Bytes(chunkCapped.text, remaining);
        const truncated = chunkCapped.truncated || totalCapped.truncated;

        const emittedBytes = Buffer.from(totalCapped.text, "utf8").length;
        commandOutputBytes.set(block.toolUseId, priorBytes + emittedBytes);

        // 3) Redact the (capped) output at the emit boundary + probe.
        const redactedOutput = probeRedactionFallthrough(
          redactCommandForDisplay(totalCapped.text),
          { userId, conversationId, field: "output" },
        );

        if (redactedOutput.length > 0 || truncated) {
          sendToClient(userId, {
            type: "command_stream",
            leaderId: CC_ROUTER_LEADER_ID,
            phase: "output",
            // FIX 2 — route this output to its originating block.
            toolUseId: block.toolUseId,
            output: truncated
              ? `${redactedOutput}${COMMAND_STREAM_TRUNCATION_MARKER}`
              : redactedOutput,
            truncated: truncated || undefined,
          });
        }

        // 4) Close the block.
        sendToClient(userId, {
          type: "command_stream",
          leaderId: CC_ROUTER_LEADER_ID,
          phase: "end",
          // FIX 2 — terminal marker carries the id for symmetry.
          toolUseId: block.toolUseId,
        });
        commandOutputBytes.delete(block.toolUseId);
      } catch (err) {
        reportSilentFallback(err, {
          feature: "cc-dispatcher",
          op: "emitCommandStream",
          extra: { userId, conversationId, phase: "output" },
        });
      }
    },
    onTextTurnEnd: () => {
      // #3603 W2 + W4 — `consumeForComplete` returns `null` if the turn was
      // already persisted via the abort path (silent no-op so a late
      // `onTextTurnEnd` cannot double-write or overwrite the aborted row).
      // Otherwise it snapshot-clear-bumps SYNCHRONOUSLY so a turn-N+1
      // `onResult` arriving on the same iterator yield cannot overwrite
      // turn N's snapshot.
      const consumed = state.consumeForComplete();
      if (consumed === null) return;
      // Fire-and-forget — user already saw the streamed text; helper mirrors on failure.
      void saveAssistantMessage(
        { kind: "complete", usage: consumed.usage },
        consumed.text,
      );
      // Per-turn boundary → terminal stream event for the cc_router bubble.
      // Without this, the client reducer keeps the bubble in
      // `state: "streaming"` (raw `whitespace-pre-wrap`), so markdown
      // (`**bold**`, `- ` bullets) renders as raw source. The
      // chat-state-machine `case "stream_end"` (chat-state-machine.ts:484-516)
      // already special-cases `cc_router` and transitions the bubble to
      // `state: "done"`, which engages MarkdownRenderer
      // (message-bubble.tsx:263).
      sendToClient(userId, {
        type: "stream_end",
        leaderId: CC_ROUTER_LEADER_ID,
      });
    },
    onWorkflowDetected: (_workflow) => {
      // Stage 3 emits a dedicated `workflow_started` WS event; for now
      // the sticky-workflow DB write in persistActiveWorkflow is the
      // single source of truth.
    },
    onWorkflowEnded: (end: WorkflowEnd) => {
      // #3603 W2 — flush partial assistant text as an `status: "aborted"` row
      // BEFORE the existing user-visible routing below. Mirrors the legacy
      // abort contract at `agent-runner.ts:2044-2055`. Skips on
      // `status: "completed"` because the normal `onTextTurnEnd` path
      // already wrote (or will write) the row. The `assistantTurnPersisted` flag
      // suppresses a late `onTextTurnEnd` arriving after this flush.
      // Use the typed `ABORT_FLUSH_STATUSES` set (exhaustively type-checked
      // via `_abortFlushExhaustive`) rather than a bare `!== "completed"` so
      // a future `WorkflowEnd` variant cannot silently route through abort
      // without a deliberate listing here.
      if (ABORT_FLUSH_STATUSES.has(end.status)) {
        const outcome = state.consumeForAbort();
        switch (outcome.kind) {
          case "text":
            // #3603 W4 text-present abort: state-class snapshot-clear-marks
            // SYNCHRONOUSLY so a late onTextTurnEnd cannot race the await.
            void saveAssistantMessage(
              { kind: "aborted", usage: outcome.usage },
              outcome.text,
            );
            break;
          case "orphan":
            // #3603 W4 orphan — usage captured but model produced ZERO text
            // (tool-only turn that then aborted). The empty-text path drops
            // the row (PR-A1 contract at `saveAssistantMessage` empty-drop);
            // P0-mirror the orphaned cost so operators can detect a runner
            // misconfiguration that strands cost telemetry. Dedup keyed on
            // `(userId, op, conversationId)` with 1h TTL.
            mirrorP0Deduped(new Error(CC_OP_SLUGS.usageOrphanDropped), {
              op: CC_OP_SLUGS.usageOrphanDropped,
              userId,
              conversationId,
            });
            break;
          case "none":
            break;
          default: {
            const _exhaustive: never = outcome;
            void _exhaustive;
          }
        }
      }
      // Architecture-F4: `session_ended` is terminal in `ws-client.ts`
      // (clears streams, disables input). Emitting it for RECOVERABLE
      // runner states (cost_ceiling, runner_runaway) would break
      // "user retries on next turn" UX. Stage 3 adds a dedicated
      // `workflow_ended` event; until then, route terminal statuses
      // to `session_ended` and recoverable statuses to a structured
      // error the client can surface without tearing down the
      // conversation.
      if (TERMINAL_WORKFLOW_END_STATUSES.has(end.status)) {
        sendToClient(userId, {
          type: "session_ended",
          reason: end.status,
        });
      } else if (end.status === "runner_runaway") {
        // Forward runaway diagnostics so an API client / agent can
        // distinguish idle-window from max-turn stalls and observe
        // which tool was last alive. Pino logs already capture this
        // server-side; the wire forwarding gives parity to consumers
        // without server log access. See #3225.
        sendToClient(userId, {
          type: "error",
          message: WORKFLOW_END_USER_MESSAGES[end.status],
          runnerRunawayReason: end.reason,
          runnerRunawayLastBlockKind: end.lastBlockKind,
          runnerRunawayLastBlockToolName: end.lastBlockToolName,
        });
      } else if (end.status === "worktree_enter_failed") {
        // #5340 / #5240 design item #2 — post-recovery-failure honest message.
        // `worktree_enter_failed` is NOT terminal (see
        // TERMINAL_WORKFLOW_END_STATUSES), so it routes HERE to a
        // `{ type: "error", message }` frame. When the per-dispatch
        // re-provision genuinely failed (`reprovisionOutcome === "failed"`),
        // surface the honest "workspace reclaimed" copy; otherwise the generic
        // retryable copy. The recovery already ran (factory `ensureWorkspaceRepoCloned` cold +
        // `reprovisionWorkspaceOnDispatch` cold/warm) — this branch sits AFTER
        // it (placement learning 2026-06-14-short-circuit-guard-must-sit-after-
        // the-recovery-it-gates.md), so the message never lies in the
        // recoverable case.
        sendToClient(userId, {
          type: "error",
          message: resolveWorktreeEnterFailedMessage(reprovisionOutcome),
        });
      } else {
        sendToClient(userId, {
          type: "error",
          message: WORKFLOW_END_USER_MESSAGES[end.status],
        });
      }
      // Note: `_ccBashGates` cleanup is now handled centrally by the
      // runner's `onCloseQuery` hook (wired in `getSoleurGoRunner`),
      // which fires from `emitWorkflowEnded`/`reapIdle`/
      // `closeConversation`. No direct call needed here.
    },
    onResult: (result) => {
      // #3603 W4 — capture per-turn cost telemetry for attachment to the
      // assistant row that `onTextTurnEnd` writes. `totalCostUsd` is a
      // per-turn delta (`soleur-go-runner.ts` `handleResultMessage` —
      // `delta = msg.total_cost_usd ?? 0`), not a cumulative running total,
      // so the value is safe to attach verbatim. The `turnIndex` tag pins
      // capture to the active turn so a stale callback arriving after the
      // bump cannot misattribute to a later row.
      state.captureUsage(state.currentTurnIndex(), result.totalCostUsd);

      // feat-debug-mode-stream — mirror the turn result (cost + usage summary)
      // into the debug stream as a `result` event. The payload is cost/usage
      // telemetry (no credential shapes), but still rides the gated
      // redact-or-drop helper for uniformity. `onResult` carries ONLY
      // {totalCostUsd, usage} — no message body.
      emitDebugEvent({
        enabled: debugPosture && debugEligible,
        kind: "result",
        rawValue: JSON.stringify({
          totalCostUsd: result.totalCostUsd,
          usage: result.usage,
        }),
        userId,
        conversationId,
        send: (frame) => sendToClient(userId, frame),
      });

      // Fire-and-forget per-turn cost write to the aggregation surface
      // (separate from messages.usage). Closes the cc-soleur-go path's
      // 60-90% under-count vs the Anthropic Console (#3626). The legacy
      // agent-runner.ts path uses the same helper. Turn termination must
      // not block on DB writes — `persistTurnCost` chains `.then()` for
      // error mirroring rather than awaiting; soleur-go-runner's onResult
      // try/catch covers the residual synchronous-throw surface.
      // Phase 3 (feat-team-workspace-multi-user) — workspaceId from
      // userId under N2 invariant; see agent-runner.ts:1884 comment.
      //
      // BYOK Delegations PR-A (#4232) closure-capture: read the
      // delegationContext that realSdkQueryFactory wrote inside its
      // lease body. The lease scope is closed by the time this
      // callback fires; the value here was captured before scope-close
      // via the `setDelegationContext` sink. Undefined under
      // flag-OFF / solo callers / resolver fall-through; routes the
      // audit through the merged atomic RPC under flag-ON +
      // delegated runs.
      persistTurnCost(
        userId,
        conversationId,
        CC_ROUTER_LEADER_ID,
        userId,
        result,
        leaseDelegationCtx,
      );
    },
    onSessionIdCaptured: (capturedSessionId) => {
      // #3266 — fire-and-forget DB persist + synchronous in-process cache
      // update. The cache update is load-bearing for the
      // runner-reap-but-WS-alive scenario: on the next chat-case turn the
      // ws-handler's warm-cache branch forwards `session.sessionId` to
      // `dispatchSoleurGo`, and a stale `null` would defeat the prefill
      // guard's history-probe activation. Fires synchronously BEFORE the
      // async DB write commits so the next turn can read the value even
      // if the user fires a follow-up before persistence lands.
      onSessionIdPersisted?.(capturedSessionId);
      void persistCcSessionId({
        userId,
        conversationId,
        sessionId: capturedSessionId,
      });
    },
  };

  try {
    await runner.dispatch({
      conversationId,
      userId,
      userMessage,
      currentRouting,
      events,
      persistActiveWorkflow,
      sessionId: sessionId ?? undefined,
      artifactPath,
      documentKind,
      documentContent,
      documentExtractError,
      documentExtractMeta,
      // BYOK Delegations PR-A (#4232) closure-capture: bridge the
      // lease body in realSdkQueryFactory to this dispatchSoleurGo
      // scope so onResult can read leaseDelegationCtx and route
      // persistTurnCost through the merged atomic RPC.
      setDelegationContext,
      // feat-concierge-stream-commands — bridge the streaming posture (D1)
      // from realSdkQueryFactory's lease body to this scope so the
      // command_stream emit gate (onToolUse/onToolResult) knows whether the
      // workspace is autonomous.
      setBashAutonomous,
      // 2026-05-06 Bug A1 fix — thread workspacePath through so the
      // runner builds the system prompt with workspace-absolute Read
      // instructions. Falls back to the locally-resolved value (set by
      // the `.then` above) when the caller didn't pre-resolve it.
      workspacePath: callerWorkspacePath ?? workspacePath,
    });
  } catch (err) {
    const errorClass =
      err instanceof KeyInvalidError
        ? "KeyInvalidError"
        : err instanceof Error
          ? err.constructor.name
          : "unknown";
    mirrorWithDebounce(
      err,
      {
        feature: "cc-dispatcher",
        op: "dispatch",
        extra: { conversationId, userId },
      },
      userId,
      `dispatch:${errorClass}`,
    );
    // R10 — KeyInvalidError surfaces with errorCode so the client can
    // prompt for a fresh BYOK key. Mirrors the KeyInvalidError →
    // errorCode: "key_invalid" branch in agent-runner.ts
    // handleSessionError. All other failures fall back to the generic
    // router-unavailable message without an errorCode.
    if (
      err instanceof RuntimeAuthError &&
      err.cause === "denied_jti"
    ) {
      // #4440 follow-up to #4418 — JWT-deny propagation. A persistUserMessage
      // mint or any other tenant-RPC inside the dispatch surfaced
      // `RuntimeAuthError("denied_jti")` before the runner emitted its
      // own WorkflowEnd. Synthesize a `session_revoked` WS frame so
      // agents/API consumers observing this turn receive the same
      // terminal discriminator the runner-level catch would have emitted
      // for a mid-stream throw.
      //
      // Routes through `tryEmitRevocationNotice` (server/revocation-emit.ts)
      // so the lookup+sanitize logic stays shared with agent-runner and
      // soleur-go-runner. Helper returns the looked-up status if a caller
      // needs the raw fields; this site only needs the emit side effect.
      await tryEmitRevocationNotice(userId, (frame) =>
        sendToClient(userId, frame),
      );
      // Pair with the terminal session_ended frame so the client
      // reducer clears streamState (`clear_streams` in ws-client.ts).
      // Disambiguator `conversationId` lets multi-tab clients route
      // this to the correct tab; matches the pre-existing
      // session_ended emit-site shape elsewhere in this dispatcher.
      sendToClient(userId, {
        type: "session_ended",
        reason: "session_revoked",
        conversationId,
      });
    } else if (err instanceof MissingByokKeyError) {
      // Phase 3.2 AC-D (Kieran N4): fail-closed when member has no BYOK
      // key. Info-level breadcrumb captures workspace context;
      // `byok_key_missing` errorCode tells the client to render the
      // configure-banner linking to /dashboard/settings/byok rather
      // than the key-invalid prompt.
      reportMissingByokKey(err);
      sendToClient(userId, {
        type: "error",
        message:
          "Configure your BYOK key to run agents in this workspace.",
        errorCode: "byok_key_missing",
      });
    } else if (err instanceof KeyInvalidError) {
      sendToClient(userId, {
        type: "error",
        message: "Your API key is invalid — set up a fresh key to continue.",
        errorCode: "key_invalid",
      });
    } else {
      // #3266 R7 — stale-resume cleanup. The dispatch was attempted with
      // a persisted session_id but the runner rejected for a reason
      // other than KeyInvalidError. Plan §R7 documents this trade-off:
      // the predicate is broad ("any non-KeyInvalidError"), which means
      // a transient backend error (network blip, BYOK fetch failure,
      // workspace patch failure) will also clear a legitimate session_id
      // and force a cold-start on the next turn. Acceptable cost: the
      // SDK rebuilds from the persisted `messages` rows on next dispatch
      // and the prefill guard's history-probe handles assistant-
      // terminated threads — at most one turn of degraded latency.
      // Narrowing to typed SDK error classes is tracked separately and
      // is out of scope for the activation PR. Fire-and-forget; the
      // user-facing generic-error message lands either way. Update the
      // in-process cache alongside the DB write so the next chat-case
      // warm-cache turn does not forward the now-stale value.
      if (sessionId) {
        onSessionIdPersisted?.(null);
        void clearCcSessionId({ userId, conversationId });
      }
      sendToClient(userId, {
        type: "error",
        message: "Dashboard router is unavailable — try again shortly.",
      });
    }
    // Belt-and-suspenders: drain ccBashGates here too. The runner's
    // onCloseQuery hook covers normal close paths, but a dispatch-time
    // throw before the runner takes ownership of the Query may leave
    // stranded entries (e.g. concurrent register from a prior turn).
    cleanupCcBashGatesForConversation(userId, conversationId);
  }
}

// ---------------------------------------------------------------------------
// Interactive-prompt response case
// ---------------------------------------------------------------------------

export function handleInteractivePromptResponseCase(args: {
  userId: string;
  payload: InteractivePromptResponse;
  sendToClient: (userId: string, message: WSMessage) => boolean;
}): HandleInteractivePromptResponseResult {
  const { userId, payload, sendToClient } = args;
  const registry = getPendingPromptRegistry();
  const runner = getSoleurGoRunner(sendToClient);

  const result = handleInteractivePromptResponse({
    registry,
    userId,
    payload,
    deliverToolResult: ({ conversationId, toolUseId, content }) => {
      runner.respondToToolUse({ conversationId, toolUseId, content });
    },
  });

  if (!result.ok) {
    // Per `cq-silent-fallback-must-mirror-to-sentry`: do NOT silently
    // drop. Emit structured WS error + mirror. Mirror only on server
    // bugs, not expected client states — `already_consumed` is a
    // benign retry after success (client already saw ok); mirroring
    // would amplify Sentry noise. `not_found` could be session
    // reset / container restart (also benign from server POV).
    if (
      MIRROR_INTERACTIVE_RESPONSE_ERRORS.has(
        result.error as InteractivePromptResponseError,
      )
    ) {
      reportSilentFallback(
        new Error(`interactive_prompt_response rejected: ${result.error}`),
        {
          feature: "cc-dispatcher",
          op: "interactive_prompt_response",
          extra: { userId, error: result.error },
        },
      );
    }
    sendToClient(userId, {
      type: "error",
      message: `Interactive prompt response rejected: ${result.error}`,
      errorCode: "interactive_prompt_rejected",
    });
  }

  return result;
}

// ---------------------------------------------------------------------------
// Test seams — exported for unit tests; do not call from production code.
// ---------------------------------------------------------------------------

/**
 * Inject a stub SoleurGoRunner so tests can drive `dispatchSoleurGo`
 * without booting the real factory + SDK subprocess. Pairs with
 * `__resetDispatcherForTests` (clears between tests).
 */
export function __setCcRunnerForTests(stub: SoleurGoRunner): void {
  _runner = stub;
  // Mark sendToClient sentinel so getSoleurGoRunner's identity check
  // does not warn when tests pass a fresh sendToClient mock.
  _runnerSendToClient = null;
}

// Exported for test cleanup only. Double-underscore + explicit suffix
// signals the contract: do not call from production code paths.
export function __resetDispatcherForTests(): void {
  if (_reaperInterval) {
    clearInterval(_reaperInterval);
    _reaperInterval = null;
  }
  _registry = null;
  _rateLimiter = null;
  _runner = null;
  _runnerSendToClient = null;
  _ccBashGates.clear();
  _ccAutonomousAckPosture.clear();
  __resetMirrorDebounceForTests();
  // The bash batched-approval cache lives in a sibling module
  // (`permission-callback-bash-batch.ts`) and is keyed by
  // `${userId}:${conversationId}`. Without draining it here, a granted
  // prefix in test A can survive into test B (cross-file leak via the
  // module-level Map). Mirrors the centralization Fix 6 of PR #2954.
  _resetBashApprovalCacheForTests();
  // Retained no-op: the workspace-path value cache was removed in the ADR-044
  // cutover (the active workspace is mutable per session). Kept in the central
  // reset so test files that call it keep compiling. See
  // `kb-document-resolver.ts` `_resetWorkspacePathCacheForTests`.
  _resetWorkspacePathCacheForTests();
}

/**
 * #3603 W1 invariant-7 — install a stub that lets tests force the
 * write-boundary sentinel to return `false` at specific call sites,
 * proving every assistant-row write runs through `assertWriteScope`.
 * #3641 — relocated from the inline declaration adjacent to
 * `assertWriteScope` to this bottom-of-file test-seam block so all
 * test-only exports cluster in one place.
 */
export function __setAssertWriteScopeForTests(
  fn: (u: string, c: string) => boolean,
): void {
  // Defense-in-depth (PR-A2 security review H3): refuse to install the
  // override outside a test environment. Without this guard a malicious /
  // accidentally-imported call site in a prod-bundle code path could neutralize
  // the sentinel for the process lifetime — module-singleton state with no
  // caller authentication. Vitest sets `NODE_ENV=test`; production sets `production`.
  if (process.env.NODE_ENV === "production") {
    throw new Error(
      "__setAssertWriteScopeForTests is not callable in production builds",
    );
  }
  _assertWriteScopeOverride = fn;
}

export function __resetAssertWriteScopeForTests(): void {
  // Defense-in-depth (review #3670): symmetric with the setter's
  // production-refusal guard. Today reset is harmless (null → null), but
  // the sentinel is anticipated to become load-bearing when SDK callbacks
  // expose payload identifiers — an unguarded resetter could then be
  // called from an accidental prod-bundle import path to neutralize an
  // installed override that does real cross-tenant comparison.
  if (process.env.NODE_ENV === "production") {
    throw new Error(
      "__resetAssertWriteScopeForTests is not callable in production builds",
    );
  }
  _assertWriteScopeOverride = null;
}
