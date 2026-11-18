/**
 * #12714 agent lines (rulings W3, D29(4)-(8), V6 "agent consistency" in
 * knowledge-base/project/specs/feat-one-shot-12600-syncpush-owner-approval/decision-challenges.md), as amended by the #12704
 * extension review (review-ext-rulings.md: D39(d)/(e), D40(3), D41, D42, CPO V7, V9, V11).
 *
 * Builders shared by both runners: the cc dispatcher appends them in the query factory's `effectiveSystemPrompt` next to
 * `c4PromptAddendum` (D29(7)); the legacy runner appends them from `syncPull`'s `{ heldFiles, pullReason }` (D29(4), task
 * 11.3b). The builders read no database, file or git: the callers pass values they already hold. The one exception is
 * `readStoredKbSyncHeld`, THE reader of the stored columns through the member-checked RPC (the cc line, and the legacy
 * line's fallback when its fresh count is null, D41(e)); it takes the caller's tenant client.
 *
 * 1. The HELD line: how many changed code files are not on the repository's main branch yet (the display-only
 *    `workspaces.kb_sync_held_files` count), as of when (`kb_sync_held_checked_at`). The D29(6) content contract: the files
 *    are kept in the workspace and a disconnect deletes them (V7); they stay counted until merged into the main branch, and
 *    the count can lag behind a merge (V11); check `github_list_pull_requests` before pushing again; name both set-aside
 *    branch families and that a checkout comes first (D39(d)); an "as of" time, and no line when the count or the time is
 *    null (or the count is 0); a `git diff --name-only` command to list the files. The route clause comes from the SAME
 *    registration result the dispatcher used for the tool (never a second flag read, W3); the registered variant says who
 *    opens the pull request (D41(g)).
 * 2. The MERGE-BLOCKED line: the states that leave the workspace un-updatable on every session until the agent resolves them
 *    (D29(4), D41(a), D42): an unfinished merge, autostashed changes that did not re-apply, an untracked file in the update's
 *    way, and held code that conflicts with GitHub (persisted by the self-heal for cc).
 *
 * Wording agrees with `ccPushPromptAddendum`, the `github_push_branch` tool description and the cc baseline's
 * `GH_AUTH_STATUS_GUIDANCE_DIRECTIVE` (feature branch only, the Owner approves, never `git push` in Bash, HEAD must not move
 * while an approval is pending), and uses the Settings card's words "not on the repository's main branch yet"; no string here
 * says the files are missing from GitHub (V6, D23). A grep row in test/kb-sync-held-agent-line.test.ts pins the agreement.
 */

import { formatHeldCount, isRenderableHeldCount } from "@/lib/kb-sync-held-copy";
import { DeadlineExceededError, withDeadline, type CcPushRegistrationReason } from "./cc-github-push";
import { AUTOSTASH_PIN_PREFIX } from "./connected-repo-git";
import { RECOVERED_REF_PREFIX, STORE_TIP_REF_PREFIX } from "./kb-sync-held";
import type { KbPullHeldReason } from "./kb-sync-pull";
import { mirrorWarnWithDebounce } from "./observability";
import { isSafeBranch } from "./resolve-protected-branches";
import type { KbSyncPullBlocked } from "./workspace-repo-mirror";

/**
 * Which publish route the session has (W3, D29(5), D40(3)):
 * - `registered`: `github_push_branch` is in this session's tool list;
 * - `not-registered`: it is not, for a lasting reason (flag off, not entitled, no repo or installation, support persona);
 * - `transient`: whether it could be registered was not established this time (a flag read error or fallback, a degraded
 *   precondition read, a default-branch lookup failure, a registration that threw): "not available right now", never the
 *   no-route sentence on a blip (V6(3));
 * - `reconnect`: the installation no longer reaches the repo, so the GitHub connection must be renewed (D40(3)).
 */
export type HeldLineRoute = "registered" | "not-registered" | "transient" | "reconnect";

/** The runner the line is built for: who opens the pull request differs (D41(g)). */
export type HeldLineRunner = "cc" | "legacy";

/** Exhaustive (pattern P3-6): a reason added to the union fails the compile here instead of defaulting to "no route". */
const ROUTE_OF_REASON: Readonly<Record<CcPushRegistrationReason, HeldLineRoute>> = {
  registered: "registered",
  "support-persona": "not-registered",
  "no-repo-or-installation": "not-registered",
  "not-entitled": "not-registered",
  "flag-off": "not-registered",
  "flag-error": "transient",
  "precondition-error": "transient",
  "installation-unauthorized": "reconnect",
  "default-branch-unresolved": "transient",
  "default-branch-unsafe": "not-registered",
};

/**
 * Maps the dispatcher's push registration result to the held line's route. `"threw"` is the registration catch;
 * `undefined` is a dispatch that never attempted a registration and has no degraded read to report, which has no route.
 * Only `reason === "registered"` counts as registered: the boolean alone is not trusted.
 */
export function heldLineRouteFromRegistration(
  registration: { registered: boolean; reason: CcPushRegistrationReason } | "threw" | undefined,
): HeldLineRoute {
  if (registration === "threw") return "transient";
  if (registration === undefined) return "not-registered";
  const route = ROUTE_OF_REASON[registration.reason] ?? "not-registered";
  if (route === "registered" && !registration.registered) return "not-registered";
  return route;
}

export interface KbSyncHeldLineInput {
  /** `workspaces.kb_sync_held_files` (or the legacy runner's fresh count). Anything but an integer in 1..10000: no line. */
  heldFiles: number | null | undefined;
  /** `workspaces.kb_sync_held_checked_at`. Null, absent or unparseable: no line (D29(6)). */
  checkedAt: string | Date | null | undefined;
  route: HeldLineRoute;
  runner: HeldLineRunner;
  /**
   * How many of the files are only on a set-aside branch (`soleur/recovered-kb-sync-*` or `soleur-store-tip-*`,
   * `computeHeldFiles().onRecovered`). 0 drops the set-aside clause; > 0 states it; null or absent (the cc path, which reads
   * only the stored total) states it as a possibility.
   */
  onRecovered?: number | null;
  /** The registrar's validated default branch, when the runner has one; anything unsafe or absent uses `origin/HEAD`. */
  defaultBranch?: string | null;
}

function asOfUtc(checkedAt: string | Date | null | undefined): string | null {
  if (checkedAt === null || checkedAt === undefined) return null;
  const d = checkedAt instanceof Date ? checkedAt : new Date(checkedAt);
  const ms = d.getTime();
  if (!Number.isFinite(ms)) return null;
  // `YYYY-MM-DD HH:MM UTC`: minute precision is enough for "as of", and the ISO slice never carries a locale.
  return `${d.toISOString().slice(0, 16).replace("T", " ")} UTC`;
}

/** `origin/<branch>` for a validated branch name, else `origin/HEAD` (never model or user text in the prompt). */
function originRef(defaultBranch: string | null | undefined): string {
  return isSafeBranch(defaultBranch) ? `origin/${defaultBranch}` : "origin/HEAD";
}

/** The local branch names of the two set-aside families, from the ref prefixes the count reads (one source, RC-H). */
function setAsideBranches(): { recovered: string; storeTip: string } {
  const heads = "refs/heads/";
  return { recovered: RECOVERED_REF_PREFIX.slice(heads.length), storeTip: STORE_TIP_REF_PREFIX.slice(heads.length) };
}

/** The held-files line, or null when nothing is to be said (count null, 0 or out of range; time null or unparseable). */
export function buildKbSyncHeldAgentLine(input: KbSyncHeldLineInput): string | null {
  const n = input.heldFiles;
  if (!isRenderableHeldCount(n)) return null;
  const asOf = asOfUtc(input.checkedAt);
  if (asOf === null) return null;

  const one = n === 1;
  const them = one ? "it" : "them";
  const they = one ? "it" : "they";
  const files = one ? "1 changed code file in this workspace is" : `${formatHeldCount(n)} changed code files in this workspace are`;
  const base = originRef(input.defaultBranch);

  const lines: string[] = [
    "## Code changes not on the main branch yet",
    `As of ${asOf}, ${files} not on the repository's main branch yet (knowledge-base files are not counted). ` +
      (one
        ? "It is kept in this workspace; disconnecting the repository deletes the workspace, including this change. "
        : "They are kept in this workspace; disconnecting the repository deletes the workspace, including these changes. ") +
      `${one ? "It stays" : "They stay"} counted until ${they} ${one ? "is" : "are"} merged into the repository's main branch: ` +
      `pushing ${them} to another branch or opening a pull request does not clear the count. ` +
      "The count can lag behind a merge: if the user asks which files are still counted, or says " +
      `${they} ${one ? "was" : "were"} already merged, list ${them} with the command below before pushing anything again.`,
    `To list ${them}, run \`git diff --name-only ${base}...HEAD -- . ':(exclude)knowledge-base/'\` ` +
      `(\`${base}\` is as of the last update from GitHub, so the list can differ slightly from the count).`,
  ];

  const onRecovered = input.onRecovered;
  if (onRecovered !== 0) {
    const certain = typeof onRecovered === "number" && onRecovered > 0;
    const { recovered, storeTip } = setAsideBranches();
    lines.push(
      `Some of these changes ${certain ? "are" : "may be"} only on a local branch named \`${recovered}<time>\` or ` +
        `\`${storeTip}<id>\`, where an earlier sync or a workspace move set them aside; list those branches with ` +
        `\`git branch --list '${recovered}*' '${storeTip}*'\`. ` +
        "To publish work from such a branch, check that branch out first (never while a push approval is pending).",
    );
  }

  lines.push(
    `Before you push ${them} again, check with \`github_list_pull_requests\` (when it is in your tool list) whether a pull ` +
      `request for ${them} is already open, so the same work is not pushed twice.`,
  );

  switch (input.route) {
    case "registered":
      lines.push(
        `To publish ${them}, commit ${them} and push ${them} to a new feature branch with \`github_push_branch\` (the workspace ` +
          `Owner approves the push); ${they} ${one ? "stops" : "stop"} being counted only once a pull request for that branch is ` +
          "merged into the main branch on GitHub. " +
          (input.runner === "cc"
            ? "After the push, the user opens the pull request for that branch on GitHub."
            : "After the push, you can open the pull request with `create_pull_request`, which the workspace Owner approves."),
      );
      break;
    case "transient":
      lines.push(
        `Whether this session can push a branch could not be checked right now, so publishing ${them} is not available right ` +
          "now: do not run `git push`. If the user asks, say that it is not available right now and may work in a new session.",
      );
      break;
    case "reconnect":
      lines.push(
        `Publishing ${them} needs the GitHub connection to be renewed, so this session cannot push a branch: do not run ` +
          "`git push`. If the user asks, tell them to ask the workspace Owner to reconnect GitHub in Settings.",
      );
      break;
    case "not-registered":
      lines.push(
        `This session has no tool to push a branch, so you cannot publish ${them}: do not run \`git push\`. If the user asks, ` +
          "tell them that publishing code changes is not available for this workspace.",
      );
      break;
    default: {
      const never: never = input.route;
      throw new Error(`kb-sync held line: unhandled route ${String(never)}`);
    }
  }

  lines.push("Bring this up when it matters to what the user asks, in plain words.");
  return lines.join("\n");
}

/** The states only the agent can resolve, each with its own line (D29(4), D41(a), D42). */
export type KbSyncMergeBlockedReason =
  | "merge_conflict"
  | "unresolved_merge"
  | "autostash_conflict"
  | "untracked_collision"
  | "merge_conflict_precheck";

/** Every pull reason classified (pattern P3-5): a reason added to `KbPullHeldReason` fails the compile until it is placed. */
const MERGE_BLOCKED_OF_REASON: Readonly<Record<KbPullHeldReason, KbSyncMergeBlockedReason | null>> = {
  merge_conflict: "merge_conflict",
  unresolved_merge: "unresolved_merge",
  autostash_conflict: "autostash_conflict",
  untracked_collision: "untracked_collision",
  merge_conflict_precheck: "merge_conflict_precheck",
  remote_state: null,
  fetch_failed: null,
  isolated_refused: null,
  tip_mismatch: null,
  shallow_changed: null,
  walk_cap: null,
  handover_failed: null,
  handover_too_large: null,
  merge_refused: null,
  side_not_kb_only: null,
  side_pr_unknown: null,
  up_to_date: null,
  merged: null,
  non_default_branch: null,
  side_declined: null,
  side_pr_created: null,
  side_linked: null,
  side_conflict: null,
  // The next sync's status run decides (D36(b)); nothing for the agent to do.
  merge_unverified: null,
  pull_deadline: null,
  side_pr_create_failed: null,
  pull_unexpected: null,
};

const COMMIT_QUALIFIER = "(not while a push approval is pending)";
const DO_NOT_DISCARD =
  "Do not run `git merge --abort`, `git reset --hard` or `git checkout` over the conflicted files unless the user asks for " +
  "it: that discards work.";

function mergeBlockedLines(reason: KbSyncMergeBlockedReason, defaultBranch: string | null | undefined): string[] {
  const finishMerge =
    "Run `git status` to see the conflicted files, resolve each one with the user, then `git add` the resolved files and " +
    `run \`git commit\` to finish the merge ${COMMIT_QUALIFIER}.`;
  const everySession =
    "It stays that way, and the workspace is not updated, at the start of every session until the merge is finished. " +
    "You are the only one who can finish it.";
  switch (reason) {
    case "merge_conflict":
      return [
        "## Unfinished merge in this workspace",
        `Updating this workspace from GitHub stopped on merge conflicts, so the merge is not finished. ${everySession}`,
        finishMerge,
        DO_NOT_DISCARD,
      ];
    case "unresolved_merge":
      return [
        "## Unfinished merge in this workspace",
        "This workspace has an unfinished merge (a merge in progress or files with unresolved conflicts), so it was not " +
          `updated from GitHub. ${everySession}`,
        finishMerge,
        `Changes from an interrupted update may be saved under \`${AUTOSTASH_PIN_PREFIX}\`: list them with ` +
          `\`git for-each-ref ${AUTOSTASH_PIN_PREFIX}\` and restore one with \`git stash apply <ref>\`.`,
        DO_NOT_DISCARD,
      ];
    case "autostash_conflict":
      return [
        "## Uncommitted changes set aside in this workspace",
        "This workspace was updated from GitHub, but its uncommitted changes could not be re-applied cleanly after the " +
          "update. They are saved in `git stash` (see `git stash list`). You are the only one who can put them back.",
        "If files show conflict markers, resolve them with the user and `git add` them; otherwise run `git stash pop`. Drop " +
          "the stash entry (`git stash drop`) once the changes are back.",
        'Do not run `git commit` to "finish a merge": the update itself is complete.',
      ];
    case "untracked_collision":
      return [
        "## Workspace update held by an untracked file",
        "A local file that git does not track sits where GitHub now has a file, so this workspace is not updated from GitHub " +
          "until that file is moved. It stays that way at the start of every session until it is moved. You are the only one " +
          "who can move it.",
        `List the files GitHub adds or removes with \`git diff --name-status HEAD ${originRef(defaultBranch)}\`, then ask the ` +
          "user before you move or delete the local file in the way: it may hold their work.",
      ];
    case "merge_conflict_precheck":
      return [
        "## Workspace cannot be updated from GitHub",
        "This workspace cannot be updated from GitHub because its local code changes conflict with GitHub's changes, so it " +
          "stays as it is at the start of every session until the conflict is resolved by hand. You are the only one who can " +
          "resolve it.",
        `With the user, run \`git fetch origin\`, then \`git merge ${originRef(defaultBranch)}\`, resolve each conflicted file, ` +
          `then \`git add\` the resolved files and run \`git commit\` to finish the merge ${COMMIT_QUALIFIER}.`,
        DO_NOT_DISCARD,
      ];
    default: {
      const never: never = reason;
      throw new Error(`kb-sync merge-blocked line: unhandled reason ${String(never)}`);
    }
  }
}

/** The merge-blocked reason a pull reason maps to, or null (any other reason, none, or a value outside the union). */
export function kbSyncMergeBlockedReasonOf(reason: KbPullHeldReason | null | undefined): KbSyncMergeBlockedReason | null {
  if (typeof reason !== "string" || !Object.hasOwn(MERGE_BLOCKED_OF_REASON, reason)) return null;
  return MERGE_BLOCKED_OF_REASON[reason];
}

/** The line for a state only the agent can resolve; null for every other reason (or none). */
export function buildKbSyncMergeBlockedAgentLine(
  reason: KbPullHeldReason | null | undefined,
  defaultBranch?: string | null,
): string | null {
  const blocked = kbSyncMergeBlockedReasonOf(reason);
  return blocked === null ? null : mergeBlockedLines(blocked, defaultBranch).join("\n");
}

// ---------------------------------------------------------------------------------------------------------------------
// The stored columns (D29(3), D41(e), D42)
// ---------------------------------------------------------------------------------------------------------------------

/** Upper bound of the held-count RPC: a hung read must not hold Query construction or the legacy session start. */
export const KB_SYNC_HELD_READ_TIMEOUT_MS = 2_000;

export interface StoredKbSyncHeld {
  readonly heldFiles: number | null;
  readonly checkedAt: string | null;
  /** D42: the self-heal's persisted refusal (cc never runs `syncPull`, so nothing else names it). */
  readonly pullBlocked: KbSyncPullBlocked | null;
}

const PULL_BLOCKED_VALUES: ReadonlySet<string> = new Set<KbSyncPullBlocked>(["merge_conflict_precheck", "untracked_collision"]);

interface HeldRpcClient {
  rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: unknown; error: unknown }>;
}

/**
 * The held-files count, its "as of" time and the self-heal's refusal (D42), read through the member-checked SECURITY
 * DEFINER RPC `get_workspace_kb_sync_held` (migration 187; the `authenticated` SELECT grant excludes the columns, so no tenant
 * select may name them). Zero rows (a non-member) is null: no line. A missing third column (an RPC that predates D42) or an
 * unknown value reads as null (D33 fail-soft). Never throws: an error, a rejection or the deadline is null plus ONE
 * debounced WARNING per workspace (obs F7: display-only, not a page) with a closed `cause` tag (obs F10) and no Error object
 * (null first, #8629).
 */
export async function readStoredKbSyncHeld(
  tenant: HeldRpcClient,
  ctx: { readonly userId: string; readonly workspaceId: string; readonly runner: HeldLineRunner },
): Promise<StoredKbSyncHeld | null> {
  try {
    const data = await withDeadline(
      async () => {
        const { data, error } = await tenant.rpc("get_workspace_kb_sync_held", { p_workspace_id: ctx.workspaceId });
        if (error) throw Object.assign(new Error("rpc error"), { rpcCode: (error as { code?: unknown }).code, isRpcError: true });
        return data;
      },
      KB_SYNC_HELD_READ_TIMEOUT_MS,
      "get_workspace_kb_sync_held",
    );
    const row = (Array.isArray(data) ? data[0] : data) as
      | { kb_sync_held_files?: unknown; kb_sync_held_checked_at?: unknown; kb_sync_pull_blocked?: unknown }
      | null
      | undefined;
    if (!row || typeof row !== "object") return null;
    // The builder validates the count (an integer in 1..10000, D29(8)); only the types are narrowed here.
    const blocked = row.kb_sync_pull_blocked;
    return {
      heldFiles: typeof row.kb_sync_held_files === "number" ? row.kb_sync_held_files : null,
      checkedAt: typeof row.kb_sync_held_checked_at === "string" ? row.kb_sync_held_checked_at : null,
      pullBlocked: typeof blocked === "string" && PULL_BLOCKED_VALUES.has(blocked) ? (blocked as KbSyncPullBlocked) : null,
    };
  } catch (err) {
    const e = err as { rpcCode?: unknown; isRpcError?: unknown } | null;
    const cause = err instanceof DeadlineExceededError ? "timeout" : e?.isRpcError === true ? "rpc_error" : "rejected";
    const pgCode = typeof e?.rpcCode === "string" ? e.rpcCode : undefined;
    mirrorWarnWithDebounce(
      null,
      {
        feature: ctx.runner === "cc" ? "cc-dispatcher" : "agent-runner",
        op: "kb-sync-held-read",
        tags: { cause, ...(pgCode ? { pg_code: pgCode } : {}) },
        extra: { userId: ctx.userId, workspaceId: ctx.workspaceId, errName: err instanceof Error ? err.name : undefined },
        message: "get_workspace_kb_sync_held read failed; no held-files line",
      },
      ctx.workspaceId,
      "kb-sync-held-read",
    );
    return null;
  }
}

/** A coarse size bucket for the log line (obs F12): never the count itself. */
function heldBucket(n: number | null | undefined): string {
  if (!isRenderableHeldCount(n)) return "none";
  if (n === 1) return "1";
  if (n < 10) return "2-9";
  if (n < 100) return "10-99";
  if (n < 1000) return "100-999";
  return "1000+";
}

/**
 * obs F12: the fields of the ONE info line a runner logs when it appends a held or merge-blocked line, so a user report
 * ("the agent told me 12 files are held") can be matched to what was injected. A bucket, the route, the merge-blocked
 * reason and the runner; never a count, a path or a branch.
 */
export function heldAgentLineLogFields(a: {
  readonly heldLine: boolean;
  readonly heldFiles: number | null | undefined;
  readonly route: HeldLineRoute;
  readonly mergeBlocked: KbSyncMergeBlockedReason | null;
  readonly runner: HeldLineRunner;
}): { op: "kb-sync.held-agent-line"; bucket: string; route: HeldLineRoute | "none"; mergeBlocked: string; runner: HeldLineRunner } {
  return {
    op: "kb-sync.held-agent-line",
    bucket: a.heldLine ? heldBucket(a.heldFiles) : "none",
    route: a.heldLine ? a.route : "none",
    mergeBlocked: a.mergeBlocked ?? "none",
    runner: a.runner,
  };
}
