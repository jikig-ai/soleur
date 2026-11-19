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
 *   4. the `approval-queue` flag, read through `readApprovalQueueFlagDetailed({userId, workspaceId})`: the SAME snapshot and
 *      identity as the gate's `isApprovalQueueEnabled`, so the same value. It registers exactly when that value is `true`;
 *      a throw, a timeout or a non-`true` value is OFF (this module never creates or flips the flag). Only the reason of an
 *      OFF splits (D40(1)): `flag-off` when Flagsmith answered off, `flag-error` when the read failed or fell back;
 *   5. the repo's default branch, looked up with a bounded request. A lookup failure means NOT registered, never a "main"
 *      fallback, so the tool can never be advertised while unable to protect the default branch.
 *
 * With any condition false the cc tool set, `platformToolNames` and the published registered set are byte-identical to a
 * build that never heard of this module. The checks run cheapest first: persona, repo and entitlement cost nothing, the flag
 * read is bounded (one read, `CC_PUSH_FLAG_TIMEOUT_MS`) and only reached when those held, and the default-branch lookup (a
 * network round trip) runs last, only when the flag is on. The dispatcher call site already resolves a repo and an installation
 * before it calls here, so the `no-repo-or-installation` arm is defensive for any other caller. The persona arm is NOT: the
 * dispatcher passes `args.persona` through unchanged, so `support-persona` is a live guard and the SECOND of two that keep this
 * write tool off a support dispatch (ADR-113): for support the dispatcher also resolves no installation, so this registrar is
 * normally never reached. Do not remove the persona arm or reorder it behind the network lookup.
 *
 * Repo, installation, entitlement and flag are decided by ONE pure function, `ccPushPreconditionVerdict`, shared with the
 * Settings predicate below (D40(5), arch F9), so a precondition added to one cannot silently miss the other. A read the
 * dispatcher could not complete (`degradedReads`) is not a definite "off": it never registers, and its reason is the
 * transient `precondition-error` (D40(2)). A default-branch lookup answered 401/403/404 means the installation lost access:
 * `installation-unauthorized` (D40(3)), whose agent line asks for GitHub to be reconnected; a rate-limited 403 is the transient
 * `default-branch-unresolved` instead (P3-11).
 *
 * The tool is built with `requireGrant: true` and the SAME `ExecutionGrants` object the gate writes to, so a call that
 * reaches the handler without a gate-written grant carrying the approved commit is refused (see `github-tools.ts`).
 * Entitlement, repo and installation are captured at Query construction: registration policy, not per-call authorization.
 * Every push still needs a fresh Owner approval at the gate.
 *
 * `github-tools` is imported LAZILY, only after every precondition held: the heavy GitHub graph stays out of the dark path
 * and out of every other module that imports this one (the dispatcher, the census tests).
 *
 * It also exports `resolveCcGithubPushRoute` (#12714, D29(5)), the read-only answer the Settings held-files card needs:
 * would the user's next session get this tool? It checks the same conditions minus the default-branch lookup and never
 * builds or registers anything.
 */

import { readApprovalQueueFlagDetailed, type ApprovalFlagIdentity, type ApprovalFlagRead } from "./approval/flag";
import type { HeldRouteState } from "@/lib/kb-sync-held-copy";
import type { ExecutionGrants } from "./approval/grants";
import type { BuildGithubPushBranchToolOpts } from "./github-tools";
import { infoSilentFallback, mirrorWarnWithDebounce, reportSilentFallback } from "./observability";
import {
  defaultFetchDefaultBranch,
  isSafeBranch,
  RESOLVE_TIMEOUT_MS,
  SAFE_SEGMENT_RE,
} from "./resolve-protected-branches";
import type { Persona } from "./workspace-mode";
import { GITHUB_PUSH_BRANCH_TOOL } from "./approval/tools";

/** The soleur_platform FQN of the tool. Kept equal to `GITHUB_PUSH_BRANCH_TOOL_FQN` in github-tools.ts by a test. */
const PUSH_FQN = GITHUB_PUSH_BRANCH_TOOL;

/**
 * The approval-required tools a cc builder is wired for (grants-aware, registered ONLY through this module's registrar).
 * Exactly one. The census sweeps expect exactly this set and `assertCcApprovalSetWired` enforces it at runtime on every
 * registrar result; `readCcMcpAllowlist` does NOT exempt it (the env route refuses every approval-required name). A weakening
 * needs an edit here AND in the census.
 */
export const CC_GRANT_WIRED_APPROVAL_TOOLS = [PUSH_FQN] as const;

/**
 * Runtime guard on the approval-required tool set, called by the dispatcher TWICE: on the registrar result before it is published
 * (a violation throws into the registration catch, which falls back to the empty set and mirrors `cc-push-registration-failed`),
 * and again on the PUBLISHED `approvalTools` / `approvalToolNames` immediately before `createSdkMcpServer`, so a later writer of
 * either variable cannot bypass it. Pure. Throws unless every `toolNames` entry is a grant-wired approval tool, appears once,
 * every built tool's name is that FQN's `soleur_platform` short name, and the two arrays correspond one-to-one. A foreign name can
 * never reach `canUseTool`'s platform list. Static messages (no echo of a name).
 */
export function assertCcApprovalSetWired(tools: readonly { name: string }[], toolNames: readonly string[]): void {
  if (tools.length !== toolNames.length) {
    throw new Error("cc approval registration: tools and toolNames do not correspond one-to-one");
  }
  const wired: readonly string[] = CC_GRANT_WIRED_APPROVAL_TOOLS;
  const prefix = "mcp__soleur_platform__";
  if (new Set(toolNames).size !== toolNames.length) {
    throw new Error("cc approval registration: a tool name is registered more than once");
  }
  toolNames.forEach((fqn, i) => {
    if (!wired.includes(fqn)) throw new Error("cc approval registration: a tool name is not grant-wired");
    if (`${prefix}${tools[i].name}` !== fqn) throw new Error("cc approval registration: a built tool does not match its registered name");
  });
}

/** Upper bound of the flag read: a never-settling seam cannot hang Query construction. */
export const CC_PUSH_FLAG_TIMEOUT_MS = 2_000;

/**
 * Machine reasons: one per way the tool can be absent. The reason is returned to the caller; only `registered` emits the
 * `cc-push-registration` outcome event. Every failure reason is already reported once by its own op-tagged mirror
 * (`cc-push-flag-resolve`, the flag module's debounced read failure, the dispatcher's degraded-read mirrors,
 * `cc-push-default-branch-resolve`, `cc-push-default-branch-unsafe`), and the normal dark states are silent. Every consumer
 * maps this union through an exhaustive `Record`, so a new reason fails the compile (pattern P3-6).
 */
export type CcPushRegistrationReason =
  | "registered"
  | "support-persona"
  | "no-repo-or-installation"
  | "not-entitled"
  | "flag-off"
  | "flag-error"
  | "precondition-error"
  | "installation-unauthorized"
  | "default-branch-unresolved"
  | "default-branch-unsafe";

/** One precondition read: `true` holds, `false` is a definite "off", `"unknown"` is a read that failed, timed out or fell back. */
export type CcPushCheck = boolean | "unknown";

/** The reasons the shared precondition decision can give (the persona and the default-branch lookup are the registrar's own). */
export type CcPushPreconditionReason = Extract<
  CcPushRegistrationReason,
  "no-repo-or-installation" | "not-entitled" | "flag-off" | "flag-error" | "precondition-error"
>;

/**
 * D40(5), arch F9: THE precondition decision of the push tool, used by the registrar and by the Settings predicate. Pure.
 * A definite "off" wins over a read that could not be completed anywhere else (the off is lasting, the blip is not), in the
 * registrar's cheapest-first order; then a failed repo, installation or entitlement read is `precondition-error`, a failed
 * or fallen-back flag read `flag-error`. `null`: every given check holds (with `flag` absent, only the cheap ones were given;
 * the registrar then reads the flag).
 */
export function ccPushPreconditionVerdict(c: {
  readonly repo: CcPushCheck;
  readonly installation: CcPushCheck;
  readonly entitled: CcPushCheck;
  readonly flag?: CcPushCheck;
}): CcPushPreconditionReason | null {
  if (c.repo === false || c.installation === false) return "no-repo-or-installation";
  if (c.entitled === false) return "not-entitled";
  if (c.flag === false) return "flag-off";
  if (c.repo === "unknown" || c.installation === "unknown" || c.entitled === "unknown") return "precondition-error";
  if (c.flag === "unknown") return "flag-error";
  return null;
}

/** A seam answer that is not a well-formed `ApprovalFlagRead` is a failed read (fail closed), never a value. */
function asFlagRead(r: unknown): ApprovalFlagRead {
  if (r === "error") return "error";
  if (typeof r === "object" && r !== null) {
    const { value, fellBack } = r as { value?: unknown; fellBack?: unknown };
    if (typeof value === "boolean" && typeof fellBack === "boolean") return { value, fellBack };
  }
  return "error";
}

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
  /**
   * D40(2): the precondition reads the dispatcher could not complete (an RPC fault, a timeout, a degraded repo URL), so their
   * `false`/`null` above is not a definite "off". Absent or empty: every value above is definite.
   */
  degradedReads?: readonly ("repo" | "installation" | "entitlement")[];
  /** The ONE per-Query grants object, shared with the gate deps. REQUIRED: a forgotten wiring is a compile error. */
  grants: ExecutionGrants;
  /** Test seam; defaults to `readApprovalQueueFlagDetailed` (the gate's snapshot, plus whether Flagsmith answered). */
  readFlag?: (identity: ApprovalFlagIdentity) => Promise<ApprovalFlagRead>;
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

/** The rejection of `withDeadline` when the deadline fires first (its own class, so a caller can tag a timeout as one). */
export class DeadlineExceededError extends Error {
  override name = "DeadlineExceededError";
}

/**
 * Run `fn` under a hard deadline; the timer is always cleared, and `onTimeout` runs when the deadline fires first. The ONE
 * deadline helper of the cc push and held-line reads (simplicity F5): the dispatcher's held-count read uses it too.
 */
export async function withDeadline<T>(fn: () => Promise<T>, ms: number, what: string, onTimeout?: () => void): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<never>((_resolve, reject) => {
    timer = setTimeout(() => {
      onTimeout?.();
      reject(new DeadlineExceededError(`${what} timed out`));
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

/**
 * The reasons that emit a Sentry outcome event: only the registered case. A failure already produces ONE op-tagged error event
 * at its own arm (a second info event for the same occurrence would double the volume per cold Query while GitHub is degraded).
 * `registered` is the registrar's verdict: the dispatcher can still reject the result afterwards and report
 * `cc-push-registration-failed`, so the info event alone is not proof the tool was published.
 */
const OUTCOME_EVENT_REASONS: ReadonlySet<CcPushRegistrationReason> = new Set(["registered"]);

/** HTTP statuses of a default-branch lookup that mean the installation lost access to the repo (reconnect, D40(3)). */
const UNAUTHORIZED_LOOKUP_STATUSES: ReadonlySet<number> = new Set([401, 403, 404]);

/** GitHub's own words for a primary ("API rate limit exceeded") or secondary / abuse-detection limit (github-api.ts sniffs the same). */
const RATE_LIMIT_MESSAGE_RE = /rate limit|abuse detection/i;

/**
 * P3-11: a 403 that is GitHub throttling the installation (primary limit: `x-ratelimit-remaining: 0`; or a secondary /
 * abuse-detection limit), not lost access. It is transient, so it must never become the lasting "reconnect GitHub" answer.
 * github-api.ts's error keeps GitHub's `message` (its scrubbed form keeps the fixed phrase "rate limit") but not the headers, so
 * the message is the production signal; the header is read when the error carries one (an Octokit `RequestError` shape).
 */
function isRateLimitedLookupFailure(err: unknown): boolean {
  const e = err as { message?: unknown; response?: { headers?: Record<string, unknown> } } | null;
  const remaining = e?.response?.headers?.["x-ratelimit-remaining"];
  if (remaining === "0" || remaining === 0) return true;
  return typeof e?.message === "string" && RATE_LIMIT_MESSAGE_RE.test(e.message.slice(0, 2000));
}

export async function resolveCcGithubPushRegistration(args: ResolveCcGithubPushArgs): Promise<CcPushRegistration> {
  const readFlag = args.readFlag ?? readApprovalQueueFlagDetailed;
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
    // Only the registered case emits here (see OUTCOME_EVENT_REASONS): the normal dark states (support persona, no repo, not
    // entitled, flag off) stay silent, and each failure is reported once by its own op-tagged mirror. `reason` is a
    // low-cardinality tag.
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
  const degraded = new Set(args.degradedReads ?? []);
  const checkOf = (holds: boolean, read: "repo" | "installation" | "entitlement"): CcPushCheck =>
    holds ? true : degraded.has(read) ? "unknown" : false;
  const cheapChecks = {
    repo: checkOf(hasRepo, "repo"),
    installation: checkOf(hasInstallation, "installation"),
    entitled: checkOf(args.webEgressEntitled, "entitlement"),
  } as const;
  const cheap = ccPushPreconditionVerdict(cheapChecks);
  if (cheap !== null) return done(cheap);

  let flagRead: ApprovalFlagRead;
  try {
    flagRead = asFlagRead(
      await withDeadline(
        () => readFlag({ userId: args.userId, workspaceId: args.workspaceId }),
        CC_PUSH_FLAG_TIMEOUT_MS,
        "approval-queue flag read",
      ),
    );
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
  // Registers exactly on the gate's value (D40(1)): a fallen-back `true` (the env mirror) still registers; only an OFF's
  // reason looks at `fellBack`.
  const flagCheck: CcPushCheck = flagRead === "error" ? "unknown" : flagRead.value ? true : flagRead.fellBack ? "unknown" : false;
  flagEnabled = ccPushPreconditionVerdict({ ...cheapChecks, flag: flagCheck }) === null;
  if (flagCheck === "unknown") return done("flag-error");
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
    const extra = failureExtra(err);
    const rateLimited = extra.status === 403 && isRateLimitedLookupFailure(err);
    const unauthorized = !rateLimited && extra.status !== undefined && UNAUTHORIZED_LOOKUP_STATUSES.has(extra.status);
    reportSilentFallback(null, {
      feature: "cc-dispatcher",
      op: "cc-push-default-branch-resolve",
      tags: { cause: rateLimited ? "rate_limited" : unauthorized ? "unauthorized" : "unresolved" },
      extra: { userId: args.userId, ...extra },
      message: "default branch lookup failed for the cc push tool; github_push_branch not registered",
    });
    // D40(3): the installation no longer reaches the repo (revoked, suspended, or the repo moved out of its reach). Lasting
    // until the GitHub connection is renewed, so not the transient "try a new session" answer. A rate-limited 403 is the
    // transient answer (P3-11).
    return done(unauthorized ? "installation-unauthorized" : "default-branch-unresolved");
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


/**
 * #12714 (rulings W3, D29(5), V6(3)): the publish-route predicate for the Settings held-files card. Its answer is the
 * registrar's precondition decision (`ccPushPreconditionVerdict`, D40(5)) for the runner of the user's NEXT session:
 *   - a new session from `start_session` dispatches cc-soleur-go (D32); the legacy runner still starts for leader-routed
 *     sessions, and it registers the tool whenever a repo and an installation resolve, so the cc answer is the stricter one.
 *   - cc: the registrar's conditions without the default-branch lookup (a network round trip per Settings render, and the
 *     lookup decides only which branch the tool protects). The next session is a `command_center` one, so the registrar's
 *     support-persona arm does not apply here (simplicity F2: the predicate's copy of it was constant-folded dead code).
 *     The flag goes through `readApprovalQueueFlagDetailed({ userId, workspaceId })`, the gate's snapshot and identity; a
 *     fallen-back value (the env mirror) is "could not be checked" here even when it is on (D40(1)). This function never
 *     creates, sets or flips the flag.
 * `userId` is the VIEWER (the member's agent is the one that would push); `workspaceId` is the id the caller resolved once.
 *
 * Answers: `available`; `unavailable` when any condition is definitely false (a definite "off" wins over a blip elsewhere);
 * `unknown` when a read failed, missed its deadline or fell back and none was definitely false: the card shows the
 * transient copy, never the no-route sentence on a blip. Each read has its own deadline and they run in parallel, so the
 * whole check is bounded by `CC_PUSH_ROUTE_TIMEOUT_MS`. The entitlement and installation reads are the STRICT ones (a fault
 * is not "off"). Read-only. Named for what it returns (pattern P3-9): a tri-state, never a truthy `is*` boolean.
 */
export type CcGithubPushRouteAvailability = HeldRouteState;

/** Upper bound of each predicate read (the flag read keeps `CC_PUSH_FLAG_TIMEOUT_MS`, which is shorter). */
export const CC_PUSH_ROUTE_TIMEOUT_MS = 2_500;

/**
 * The member-checked installation RPC `resolveInstallationId` reads, WITHOUT its swallow: an RPC fault throws (it is not "no
 * installation"). True when the workspace has an installation the viewer may use. Shared by the predicate and the
 * dispatcher's degraded-read check (D40(2)).
 */
export async function readCcInstallationStrict(userId: string, workspaceId: string): Promise<boolean> {
  const { getFreshTenantClient } = await import("@/lib/supabase/tenant");
  const tenant = await getFreshTenantClient(userId);
  const { data, error } = await tenant.rpc("resolve_workspace_installation_id", { p_workspace_id: workspaceId });
  if (error) throw new Error("installation read failed");
  return typeof data === "number" || (typeof data === "string" && data !== "");
}

/** The predicate's mapping of the shared decision (exhaustive: a new reason fails the compile). */
const ROUTE_OF_PRECONDITION: Readonly<Record<CcPushPreconditionReason, CcGithubPushRouteAvailability>> = {
  "no-repo-or-installation": "unavailable",
  "not-entitled": "unavailable",
  "flag-off": "unavailable",
  "flag-error": "unknown",
  "precondition-error": "unknown",
};

export async function resolveCcGithubPushRoute(args: {
  userId: string;
  workspaceId: string;
  /** The caller's Sentry feature tag (the Settings page passes "settings"), so a search on the page's feature finds it. */
  feature: string;
}): Promise<CcGithubPushRouteAvailability> {
  const { userId, workspaceId, feature } = args;
  const failed: string[] = [];
  const settle = async (name: string, ms: number, read: () => Promise<boolean>): Promise<CcPushCheck> => {
    try {
      return await withDeadline(read, ms, name);
    } catch {
      failed.push(name);
      return "unknown";
    }
  };

  const [flag, entitled, installation] = await Promise.all([
    settle("flag", CC_PUSH_FLAG_TIMEOUT_MS, async () => {
      const read = asFlagRead(await readApprovalQueueFlagDetailed({ userId, workspaceId }));
      // A failed or fallen-back read is "could not be checked", even when the mirror says on (D40(1)).
      if (read === "error" || read.fellBack) throw new Error("flag read failed or fell back");
      return read.value;
    }),
    settle("entitlement", CC_PUSH_ROUTE_TIMEOUT_MS, async () => {
      const { resolveWebEgressStrict } = await import("./resolve-web-egress");
      return (await resolveWebEgressStrict(userId, workspaceId)) === true;
    }),
    settle("installation", CC_PUSH_ROUTE_TIMEOUT_MS, () => readCcInstallationStrict(userId, workspaceId)),
  ]);

  // The card renders only for a connected `ready` repo, so the repo check holds by the caller's gate.
  const verdict = ccPushPreconditionVerdict({ repo: true, installation, entitled, flag });
  const route = verdict === null ? "available" : ROUTE_OF_PRECONDITION[verdict];
  if (route === "unknown") {
    // One warning per window while a read keeps failing (debounced per workspace, obs F11): this runs on every Settings
    // render. `failed` is a tag, so it can be filtered.
    mirrorWarnWithDebounce(
      null,
      {
        feature,
        op: "cc-push-route-check",
        tags: { failed: [...failed].sort().join(",") },
        extra: { userId, workspaceId },
        message: "publish-route check could not be completed; the transient copy is shown",
      },
      workspaceId,
      "cc-push-route-check",
    );
  }
  return route;
}
