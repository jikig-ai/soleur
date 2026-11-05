/**
 * Registration of the approval-gated `github_push_branch` tool in the cc `soleur_platform` server (#11636, Ref #11635,
 * epic #9601; ADR-309 addendum 2026-11-05).
 *
 * The cc dispatcher gives the Concierge no way to push a branch from its sandbox. This module owns the ONE decision to
 * register the platform's push tool for a Query, and nothing else: it returns the built tool plus a machine `reason`, and
 * the dispatcher merges `tools` into its single server, appends `toolNames` to the `canUseTool` platform list and
 * `ccPushPromptAddendum(defaultBranch)` to the system prompt. Registration is DARK by construction. It needs ALL of:
 *
 *   1. a non-`support` persona (support never writes: ADR-113, #9558);
 *   2. a connected repo (owner + name) and a resolved installation;
 *   3. the workspace web-egress grant (`webEgressEntitled`, the grant boolean, never the forwarder handle: the push runs
 *      in the dispatch process, so a degraded forwarder is irrelevant);
 *   4. the `approval-queue` flag, read through `isApprovalQueueEnabled({userId, workspaceId})`, the SAME function and
 *      identity the gate uses; any throw, timeout or non-`true` value is OFF (this module never creates or flips the flag);
 *   5. the repo's default branch, looked up with a bounded request. A lookup failure means NOT registered, never a "main"
 *      fallback, so the tool can never be advertised while unable to protect the default branch.
 *
 * With any condition false the cc tool set, `platformToolNames` and the published registered set are byte-identical to a
 * build that never heard of this module. The checks run cheapest first: persona, repo and entitlement cost nothing, the flag
 * read is bounded (one read, `CC_PUSH_FLAG_TIMEOUT_MS`) and only reached when those held, and the default-branch lookup (a
 * network round trip) runs last, only when the flag is on. The dispatcher call site already resolves a repo, an installation
 * and a non-support persona before it calls here, so those three arms are defensive for any other caller.
 *
 * The tool is built with `requireGrant: true` and the SAME `ExecutionGrants` object the gate writes to, so a call that
 * reaches the handler without a gate-written grant carrying the approved commit is refused (see `github-tools.ts`).
 * Entitlement, repo and installation are captured at Query construction: registration policy, not per-call authorization.
 * Every push still needs a fresh Owner approval at the gate.
 *
 * `github-tools` is imported LAZILY, only after every precondition held: the heavy GitHub graph stays out of the dark path
 * and out of every other module that imports this one (the dispatcher, the census tests).
 */

import { isApprovalQueueEnabled, type ApprovalFlagIdentity } from "./approval/flag";
import type { ExecutionGrants } from "./approval/grants";
import type { BuildGithubPushBranchToolOpts } from "./github-tools";
import { infoSilentFallback, reportSilentFallback } from "./observability";
import {
  defaultFetchDefaultBranch,
  isSafeBranch,
  RESOLVE_TIMEOUT_MS,
  SAFE_SEGMENT_RE,
} from "./resolve-protected-branches";
import type { Persona } from "./workspace-mode";

/** The soleur_platform FQN of the tool. Kept equal to `GITHUB_PUSH_BRANCH_TOOL_FQN` in github-tools.ts by a test. */
const PUSH_FQN = "mcp__soleur_platform__github_push_branch";

/**
 * The approval-required tools a cc builder is wired for (grants-aware, registered ONLY through this module's registrar).
 * Exactly one. The census sweeps expect exactly this set and `assertCcApprovalSetWired` enforces it at runtime on every
 * registrar result; `readCcMcpAllowlist` does NOT exempt it (the env route refuses every approval-required name). A weakening
 * needs an edit here AND in the census.
 */
export const CC_GRANT_WIRED_APPROVAL_TOOLS = [PUSH_FQN] as const;

/**
 * Runtime guard on a registrar result, called by the dispatcher before it publishes the tools and names. Pure. Throws unless
 * every `toolNames` entry is a grant-wired approval tool, every built tool's name is that FQN's `soleur_platform` short name,
 * and the two arrays correspond one-to-one. A violation throws into the dispatcher's registration catch, which falls back to the
 * empty set and mirrors `cc-push-registration-failed`: a foreign name can never reach `canUseTool`'s platform list. Static
 * messages (no echo of a name).
 */
export function assertCcApprovalSetWired(tools: readonly { name: string }[], toolNames: readonly string[]): void {
  if (tools.length !== toolNames.length) {
    throw new Error("cc approval registration: tools and toolNames do not correspond one-to-one");
  }
  const wired: readonly string[] = CC_GRANT_WIRED_APPROVAL_TOOLS;
  const prefix = "mcp__soleur_platform__";
  toolNames.forEach((fqn, i) => {
    if (!wired.includes(fqn)) throw new Error("cc approval registration: a tool name is not grant-wired");
    if (`${prefix}${tools[i].name}` !== fqn) throw new Error("cc approval registration: a built tool does not match its registered name");
  });
}

/** Upper bound of the flag read: a never-settling seam cannot hang Query construction. */
export const CC_PUSH_FLAG_TIMEOUT_MS = 2_000;

/** Machine reasons: one per way the tool can be absent, so one Sentry event separates every cause of "the tool is missing". */
export type CcPushRegistrationReason =
  | "registered"
  | "support-persona"
  | "no-repo-or-installation"
  | "not-entitled"
  | "flag-off"
  | "flag-error"
  | "default-branch-unresolved"
  | "default-branch-unsafe";

export interface CcPushRegistration {
  registered: boolean;
  reason: CcPushRegistrationReason;
  /** The built SDK tool(s): exactly one when registered, empty otherwise. */
  tools: { name: string }[];
  /** The fully-qualified names to append to the `canUseTool` platform list: `[PUSH_FQN]` when registered, empty otherwise. */
  toolNames: string[];
  /** The validated (`isSafeBranch`) default branch the tool was closed over and the prompt names; `null` unless registered. */
  defaultBranch: string | null;
}

export interface ResolveCcGithubPushArgs {
  userId: string;
  /** The active workspace id captured once for this Query: the same id the gate binds. */
  workspaceId: string;
  persona: Persona;
  owner: string;
  repo: string;
  installationId: number | null;
  workspacePath: string;
  /** The workspace web-egress GRANT boolean (not the forwarder handle). */
  webEgressEntitled: boolean;
  /** The ONE per-Query grants object, shared with the gate deps. REQUIRED: a forgotten wiring is a compile error. */
  grants: ExecutionGrants;
  /** Test seam; defaults to the gate's own flag function. */
  isEnabled?: (identity: ApprovalFlagIdentity) => Promise<boolean>;
  /** Test seam; defaults to the GitHub API `default_branch` read with the installation token. */
  lookupDefaultBranch?: (installationId: number, owner: string, repo: string, signal: AbortSignal) => Promise<unknown>;
  /** Test seam; defaults to the real `buildGithubPushBranchTool` (lazy import). */
  buildTool?: (opts: BuildGithubPushBranchToolOpts) => { name: string };
}

/**
 * The system-prompt addendum, only added when the tool is registered (the no-tool prompt stays byte-identical). The
 * model-relayed text is the user's first signal that a push is waiting for the Owner or was refused; there is no automated
 * detector for model prose (stated in the ADR addendum), so each obligation is pinned by its own anchored phrase in a test.
 * `defaultBranch` is the registrar's validated value (never model or user text); anything unsafe throws into the dispatcher's
 * registration catch.
 */
export function ccPushPromptAddendum(defaultBranch: string): string {
  if (!isSafeBranch(defaultBranch)) throw new Error("cc push prompt addendum: unsafe default branch name");
  return (
    "## Pushing a branch\n" +
    "The `github_push_branch` tool is the only way to push a branch from this workspace; do not run `git push` in Bash. " +
    "It pushes the workspace HEAD commit after the workspace Owner approves it.\n" +
    `Push to a feature branch only. NEVER push to main, master or ${defaultBranch}: a refusal for a protected branch still spends the Owner's approval. ` +
    "Never set force.\n" +
    "Commit your work first, and do not change HEAD (no commit, checkout or reset) while an approval is pending: the Owner approves one specific commit.\n" +
    "If the result says the approval is pending or was denied, tell the user in plain words that nothing was pushed and why, " +
    "and follow the retry or no-retry instruction inside the result; do not paste the raw result.\n" +
    "Never claim a push happened unless the result says it was pushed."
  );
}

/** Run `fn` under a hard deadline; the timer is always cleared, and `onTimeout` runs when the deadline fires first. */
async function withDeadline<T>(fn: () => Promise<T>, ms: number, what: string, onTimeout?: () => void): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<never>((_resolve, reject) => {
    timer = setTimeout(() => {
      onTimeout?.();
      reject(new Error(`${what} timed out`));
    }, ms);
  });
  try {
    return await Promise.race([fn(), deadline]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

/**
 * The failure fields for a mirror: the class name and the HTTP status, NEVER the Error (null goes first): the pino mirror
 * captures a passed Error first and Sentry then drops the tagged second capture (#8629), and a GitHub API error's message embeds
 * `/repos/<owner>/<repo>`.
 */
function failureExtra(err: unknown): { errName?: string; status?: number } {
  const status = (err as { statusCode?: unknown; status?: unknown } | null)?.statusCode ?? (err as { status?: unknown } | null)?.status;
  return {
    errName: err instanceof Error ? err.name : undefined,
    ...(typeof status === "number" ? { status } : {}),
  };
}

/** The reasons that emit a Sentry outcome event: the registered case and the two failures a flag-on operator must see. */
const OUTCOME_EVENT_REASONS: ReadonlySet<CcPushRegistrationReason> = new Set([
  "registered",
  "flag-error",
  "default-branch-unresolved",
  "default-branch-unsafe",
]);

export async function resolveCcGithubPushRegistration(args: ResolveCcGithubPushArgs): Promise<CcPushRegistration> {
  const isEnabled = args.isEnabled ?? isApprovalQueueEnabled;
  const lookup = args.lookupDefaultBranch ?? defaultFetchDefaultBranch;
  // The owner and repo are interpolated into an API path: only the safe segment charset is accepted (the dispatcher's own
  // values come from a parsed repo URL; this keeps the guard with the sink).
  const hasRepo =
    Boolean(args.owner) && Boolean(args.repo) && SAFE_SEGMENT_RE.test(args.owner) && SAFE_SEGMENT_RE.test(args.repo);
  const hasInstallation = args.installationId !== null;
  let flagEnabled = false;
  let defaultBranchResolved = false;

  const done = (reason: CcPushRegistrationReason, tools: { name: string }[] = [], defaultBranch: string | null = null): CcPushRegistration => {
    const registered = reason === "registered";
    // Dark paths that are the NORMAL state (support persona, no repo, not entitled, flag off) stay silent: an event per cold
    // Query would be the dominant volume of this feature while it is dark. Sentry carries the registered case and the failures;
    // `reason` is a low-cardinality tag.
    if (OUTCOME_EVENT_REASONS.has(reason)) {
      infoSilentFallback(null, {
        feature: "cc-push-registration",
        tags: { reason },
        extra: {
          registered,
          reason,
          flagEnabled,
          entitled: args.webEgressEntitled,
          persona: args.persona,
          hasRepo,
          hasInstallation,
          defaultBranchResolved,
        },
        message: "cc github_push_branch registration outcome",
      });
    }
    return { registered, reason, tools, toolNames: registered ? [PUSH_FQN] : [], defaultBranch: registered ? defaultBranch : null };
  };

  // Cheapest first, the flag last among the cheap checks, the network lookup last of all.
  if (args.persona === "support") return done("support-persona");
  if (!hasRepo || !hasInstallation) return done("no-repo-or-installation");
  if (!args.webEgressEntitled) return done("not-entitled");

  try {
    const value: unknown = await withDeadline(
      () => isEnabled({ userId: args.userId, workspaceId: args.workspaceId }),
      CC_PUSH_FLAG_TIMEOUT_MS,
      "approval-queue flag read",
    );
    flagEnabled = value === true;
  } catch (err) {
    // Defensive net: the real seam swallows every read error and answers false. A future seam change must not turn a throw or
    // a hang into a registered tool. null first, never the Error (see `failureExtra`).
    reportSilentFallback(null, {
      feature: "cc-dispatcher",
      op: "cc-push-flag-resolve",
      extra: { userId: args.userId, ...failureExtra(err) },
      message: "approval-queue flag read failed for the cc push tool; github_push_branch not registered",
    });
    return done("flag-error");
  }
  if (!flagEnabled) return done("flag-off");

  let value: unknown;
  try {
    const ac = new AbortController();
    value = await withDeadline(
      () => lookup(args.installationId as number, args.owner, args.repo, ac.signal),
      RESOLVE_TIMEOUT_MS,
      "default-branch lookup",
      () => ac.abort(),
    );
  } catch (err) {
    // NEVER a "main" fallback here: a push tool advertised while unable to protect the default branch is the failure to avoid.
    reportSilentFallback(null, {
      feature: "cc-dispatcher",
      op: "cc-push-default-branch-resolve",
      extra: { userId: args.userId, ...failureExtra(err) },
      message: "default branch lookup failed for the cc push tool; github_push_branch not registered",
    });
    return done("default-branch-unresolved");
  }
  if (!isSafeBranch(value)) {
    // The lookup answered, but with a name that cannot be closed over safely (not the outage the other arm reports).
    reportSilentFallback(null, {
      feature: "cc-dispatcher",
      op: "cc-push-default-branch-unsafe",
      extra: { userId: args.userId, valueType: typeof value },
      message: "default branch lookup returned an unusable name for the cc push tool; github_push_branch not registered",
    });
    return done("default-branch-unsafe");
  }
  const defaultBranch: string = value;
  defaultBranchResolved = true;

  const buildTool = args.buildTool ?? (await import("./github-tools")).buildGithubPushBranchTool;
  const tool = buildTool({
    installationId: args.installationId as number,
    owner: args.owner,
    repo: args.repo,
    defaultBranch,
    workspacePath: args.workspacePath,
    grants: args.grants,
    requireGrant: true,
  });
  return done("registered", [tool], defaultBranch);
}
