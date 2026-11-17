/**
 * #12714 agent lines (rulings W3, D29(4)-(8), V6 "agent consistency" in
 * knowledge-base/project/specs/feat-one-shot-12600-syncpush-owner-approval/decision-challenges.md).
 *
 * Pure builders, shared by both runners: the cc dispatcher appends them in the query factory's `effectiveSystemPrompt` next
 * to `c4PromptAddendum` (D29(7)); the legacy runner appends them from `syncPull`'s `{ heldFiles, pullReason }` (D29(4),
 * task 11.3b). Nothing here reads a database, a file or git: the callers pass values they already hold.
 *
 * 1. The HELD line: how many changed code files are not on the repository's main branch yet (the display-only
 *    `workspaces.kb_sync_held_files` count), as of when (`kb_sync_held_checked_at`). The D29(6) content contract: the files
 *    stay counted until merged into the main branch; check `github_list_pull_requests` before pushing again; name the
 *    recovered branches and that a checkout comes first; an "as of" time, and no line when the count or the time is null
 *    (or the count is 0); a `git diff --name-only` command to list the files. The route clause comes from the SAME
 *    registration result the dispatcher used for the tool (never a second flag read, W3).
 * 2. The MERGE-BLOCKED line: `merge_conflict` / `unresolved_merge` leave the workspace un-updatable on every session until the
 *    merge is finished, and the agent is the only party that can finish it (D29(4)).
 *
 * Wording agrees with `ccPushPromptAddendum` and the `github_push_branch` tool description (feature branch only, the Owner
 * approves, never `git push` in Bash, HEAD must not move while an approval is pending), and uses the Settings card's words
 * "not on the repository's main branch yet"; no string here says the files are missing from GitHub (V6, D23). A grep row in
 * test/kb-sync-held-agent-line.test.ts pins the agreement.
 */

import type { CcPushRegistrationReason } from "./cc-github-push";
import { isSafeBranch } from "./resolve-protected-branches";

/** The upper bound of the stored count (migration 187's named check) and of what is ever rendered (D29(8)). */
export const KB_SYNC_HELD_MAX = 10_000;

/** D29(8): only an integer in 1..10000 is ever rendered; 0, null, a fraction or anything else renders nothing. */
export function isRenderableHeldCount(n: unknown): n is number {
  return typeof n === "number" && Number.isInteger(n) && n >= 1 && n <= KB_SYNC_HELD_MAX;
}

/**
 * Which publish route the session has (W3, D29(5)):
 * - `registered`: `github_push_branch` is in this session's tool list;
 * - `not-registered`: it is not, for a lasting reason (flag off, not entitled, no repo or installation, support persona);
 * - `transient`: whether it could be registered was not established this time (a flag read error, a default-branch lookup
 *   failure, a registration that threw): "not available right now", never the no-route sentence on a blip (V6(3)).
 */
export type HeldLineRoute = "registered" | "not-registered" | "transient";

const TRANSIENT_REGISTRATION_REASONS: ReadonlySet<CcPushRegistrationReason> = new Set(["flag-error", "default-branch-unresolved"]);

/**
 * Maps the dispatcher's push registration result to the held line's route. `"threw"` is the registration catch;
 * `undefined` is a dispatch that never attempted a registration (no repo or no installation), which has no route.
 * Only `reason === "registered"` counts as registered: the boolean alone is not trusted.
 */
export function heldLineRouteFromRegistration(
  registration: { registered: boolean; reason: CcPushRegistrationReason } | "threw" | undefined,
): HeldLineRoute {
  if (registration === "threw") return "transient";
  if (registration === undefined) return "not-registered";
  if (registration.reason === "registered" && registration.registered) return "registered";
  return TRANSIENT_REGISTRATION_REASONS.has(registration.reason) ? "transient" : "not-registered";
}

export interface KbSyncHeldLineInput {
  /** `workspaces.kb_sync_held_files` (or the legacy runner's fresh count). Anything but an integer in 1..10000: no line. */
  heldFiles: number | null | undefined;
  /** `workspaces.kb_sync_held_checked_at`. Null, absent or unparseable: no line (D29(6)). */
  checkedAt: string | Date | null | undefined;
  route: HeldLineRoute;
  /**
   * How many of the files are only on a `soleur/recovered-kb-sync-*` branch (`computeHeldFiles().onRecovered`). 0 drops the
   * recovered-branch clause; > 0 states it; null or absent (the cc path, which reads only the stored total) states it as a
   * possibility.
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

/** The held-files line, or null when nothing is to be said (count null, 0 or out of range; time null or unparseable). */
export function buildKbSyncHeldAgentLine(input: KbSyncHeldLineInput): string | null {
  const n = input.heldFiles;
  if (!isRenderableHeldCount(n)) return null;
  const asOf = asOfUtc(input.checkedAt);
  if (asOf === null) return null;

  const one = n === 1;
  const them = one ? "it" : "them";
  const they = one ? "it" : "they";
  const files = one ? "1 changed code file in this workspace is" : `${n} changed code files in this workspace are`;
  const base = isSafeBranch(input.defaultBranch) ? `origin/${input.defaultBranch}` : "origin/HEAD";

  const lines: string[] = [
    "## Code changes not on the main branch yet",
    `As of ${asOf}, ${files} not on the repository's main branch yet (knowledge-base files are not counted). ` +
      `Nothing is lost: ${they} ${one ? "stays" : "stay"} in this workspace. ` +
      `${one ? "It stays" : "They stay"} counted until ${they} ${one ? "is" : "are"} merged into the repository's main branch: ` +
      `pushing ${them} to another branch or opening a pull request does not clear the count.`,
    `To list ${them}, run \`git diff --name-only ${base}...HEAD -- . ':(exclude)knowledge-base/'\` ` +
      `(\`${base}\` is as of the last update from GitHub, so the list can differ slightly from the count).`,
  ];

  const onRecovered = input.onRecovered;
  if (onRecovered !== 0) {
    const certain = typeof onRecovered === "number" && onRecovered > 0;
    lines.push(
      `Some of these changes ${certain ? "are" : "may be"} only on a local branch named \`soleur/recovered-kb-sync-<time>\`, ` +
        "where an earlier sync set them aside; list those branches with `git branch --list 'soleur/recovered-kb-sync-*'`. " +
        "To publish work from such a branch, check that branch out first (never while a push approval is pending).",
    );
  }

  lines.push(
    `Before you push ${them} again, check with \`github_list_pull_requests\` (when it is in your tool list) whether a pull ` +
      `request for ${them} is already open, so the same work is not pushed twice.`,
  );

  if (input.route === "registered") {
    lines.push(
      `To publish ${them}, commit ${them} and push ${them} to a new feature branch with \`github_push_branch\` (the workspace ` +
        `Owner approves the push); ${they} ${one ? "stops" : "stop"} being counted only once a pull request for that branch is ` +
        "merged into the main branch on GitHub.",
    );
  } else if (input.route === "transient") {
    lines.push(
      `Whether this session can push a branch could not be checked right now, so publishing ${them} is not available right ` +
        "now: do not run `git push`. If the user asks, say that it is not available right now and may work in a new session.",
    );
  } else {
    lines.push(
      `This session has no tool to push a branch, so you cannot publish ${them}: do not run \`git push\`. If the user asks, ` +
        "tell them that publishing code changes is not available for this workspace.",
    );
  }

  lines.push("Bring this up when it matters to what the user asks, in plain words.");
  return lines.join("\n");
}

/** The two pull reasons that leave a merge only the agent can finish (D29(4)). */
export type KbSyncMergeBlockedReason = "merge_conflict" | "unresolved_merge";

const MERGE_BLOCKED_CAUSE: Readonly<Record<KbSyncMergeBlockedReason, string>> = {
  merge_conflict:
    "Updating this workspace from the repository's main branch stopped on merge conflicts, so the merge is not finished.",
  unresolved_merge:
    "This workspace has an unfinished merge (a merge in progress or files with unresolved conflicts), so it was not " +
    "updated from the repository's main branch.",
};

/** The merge-blocked line for `merge_conflict` / `unresolved_merge`; null for every other reason (or none). */
export function buildKbSyncMergeBlockedAgentLine(reason: unknown): string | null {
  if (reason !== "merge_conflict" && reason !== "unresolved_merge") return null;
  return [
    "## Unfinished merge in this workspace",
    `${MERGE_BLOCKED_CAUSE[reason]} It stays that way, and the workspace is not updated, at the start of every session ` +
      "until the merge is finished. You are the only one who can finish it.",
    "Run `git status` to see the conflicted files, resolve each one with the user, then `git add` the resolved files and " +
      "run `git commit` to finish the merge.",
    "Do not run `git merge --abort`, `git reset --hard` or `git checkout` over the conflicted files unless the user asks for " +
      "it: that discards work.",
  ].join("\n");
}
