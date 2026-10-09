/**
 * PR merge-state polling helpers — BEHIND detection and resync contract.
 *
 * Ship Phase 7 embeds the full poll loop; this module is the portable spec
 * Grok Build agents use when polling outside Monitor tool (ad-hoc CI watch,
 * PR babysit, post-merge verify prep).
 *
 * Failure mode (#6347 session): Grok polled `statusCheckRollup` pending/failed
 * but ignored `mergeStateStatus: BEHIND` — burned 17 ticks while main moved.
 */

import type { Harness } from "./harness";

/** GitHub `mergeStateStatus` values we act on during poll loops. */
export const MERGE_STATE_BEHIND = "BEHIND" as const;
export const MERGE_STATE_DIRTY = "DIRTY" as const;
export const MERGE_STATE_BLOCKED = "BLOCKED" as const;
export const MERGE_STATE_CLEAN = "CLEAN" as const;

export const MAX_BEHIND_SYNCS_DEFAULT = 6;

/** Sentinel for drift-guarded docs/scripts. */
export const PR_BEHIND_SYNC_SENTINEL = "pr-behind-sync-protocol";

/** `gh pr view` jq template — MUST include mergeStateStatus, not just checks. */
export const PR_VIEW_POLL_JQ =
  '"\\(.state) \\(.mergeStateStatus)"';

export function formatPrPollState(state: string, mergeStateStatus: string): string {
  return `${state} ${mergeStateStatus}`;
}

export function isBehindPollState(pollLine: string): boolean {
  return pollLine.includes(MERGE_STATE_BEHIND);
}

export function isTerminalPollState(pollLine: string): boolean {
  return /^(MERGED|CLOSED)\b/.test(pollLine.trim());
}

export function isDirtyPollState(pollLine: string): boolean {
  return pollLine.includes(MERGE_STATE_DIRTY);
}

/**
 * When true, stop CI-only polling and resync branch with origin/main first.
 * BEHIND: auto-merge will not fire until head catches up to base.
 * DIRTY: GitHub computed a conflict; locally-clean DIRTY (kb-index) still resyncs.
 */
export function shouldResyncBeforePoll(mergeStateStatus: string): boolean {
  return (
    mergeStateStatus === MERGE_STATE_BEHIND ||
    mergeStateStatus === MERGE_STATE_DIRTY
  );
}

/**
 * Harness-specific BEHIND/DIRTY resync instructions. The script discriminates:
 * DIRTY auto-syncs only when `git merge-tree` proves the local merge clean
 * (kb-index class); a real conflict exits 6 for manual resolution.
 */
export function behindSyncInstructions(harness: Harness): string {
  // ADR-179: the installed plugin root, never a repo-relative path (a customer
  // repo has no plugins/soleur/ tree).
  const script = 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-pr-behind.sh"';
  switch (harness) {
    case "grok":
      return [
        "**BEHIND/DIRTY resync (Grok Build)**",
        `- When \`gh pr view --jq '.mergeStateStatus'\` returns \`BEHIND\` or \`DIRTY\`, **STOP** CI-only polling.`,
        `- Exception (first): when \`main\` has a merge queue and the PR is armed (the Phase 7 poll prints \`[ship.phase7.queue_wait]\`) the PR is waiting for GitHub to enqueue it — keep polling; never run the sync script, update-branch or --admin it until \`[ship.phase7.queue_wait_expired]\`, a push line, MERGED, a dequeue or any poll exit. This holds for a BEHIND reading only (a conflicting DIRTY PR still needs its sync). The script itself answers \`kind=queue_wait\` (exit 0, nothing synced) for that PR: a wait, not a failure.`,
        `- Otherwise, from the PR worktree: \`${script} <PR-number>\` (fetch → merge origin/main → push). Use the Phase 7 loop; never write your own poll loop or wrap the script in one.`,
        `- \`DIRTY\` auto-syncs only when the local merge is clean; a real conflict exits for manual resolution.`,
        `- Match AwaitShell \`pattern\`: \`BEHIND detected|auto-sync.*pushed|BEHIND resolved|BEHIND unchanged|merge conflict|\\[pr-behind-sync\\] kind=|\\[ship\\.phase7\\.\`.`,
        `- Exit 11 is a no-op: \`kind=noop\` is GitHub state lag. \`kind=queued\` means the PR is IN the merge queue and nothing was pushed (a push dequeues it): it exits 0 here and 11 only with \`--step\` — keep polling for MERGED, never push, update-branch or --admin it; re-poll, then re-run. Exit 13 (\`kind=dequeued\`) means it left the queue unmerged (a failed merge_group run or a removal; auto-merge may still read armed) — follow the recovery on that line. Exit 12 (\`kind=wrong_branch\`) means this worktree is not the PR's branch — cd to it. Any other \`kind=\` line names its next action.`,
        `- Re-poll after push; do NOT ask the operator to update the branch.`,
      ].join("\n");

    case "claude":
      return [
        "**BEHIND/DIRTY resync (Claude Code)**",
        `- When mergeStateStatus is \`BEHIND\` or \`DIRTY\`, the ship Phase 7 Monitor loop calls \`sync-pr-behind.sh <PR-number> --step\` once per attempt (the Phase 7 fence's call, never yours; unguarded by design). Never write your own poll loop — use that one. The standalone entry is \`${script} <PR-number>\`: it refuses an armed PR on a merge-queue repo with \`kind=queue_wait\` (exit 0, a wait, not a failure); DIRTY auto-syncs only when locally clean.`,
        `- FORBIDDEN: heartbeating on pending checks while BEHIND or DIRTY — auto-merge is blocked — unless the script reported \`kind=queued\` (exit 11 with \`--step\`): a PR in the merge queue is not blocked, the queue merges it, so keep heartbeating and never sync it; likewise when \`main\` has a merge queue and the PR is armed (the Phase 7 poll prints \`[ship.phase7.queue_wait]\`) on a BEHIND reading (a conflicting DIRTY PR still syncs) — GitHub enqueues it, in force until \`[ship.phase7.queue_wait_expired]\`, a push line, MERGED, a dequeue or any poll exit; \`kind=dequeued\` (exit 13) stops the poll with the recovery.`,
      ].join("\n");

    case "cursor":
      return [
        "**BEHIND/DIRTY resync (Cursor CLI)**",
        "- No wait primitive has been measured on the Cursor CLI.",
        "- This run cannot finish that gate.",
        "- Continue that merge on a harness that already has a wait, or stop.",
        "- Do not invent a wait. Do not hand the wait to the operator.",
        "- This stop does not make the plugin supported.",
      ].join("\n");

    default:
      return [
        "**BEHIND/DIRTY resync**",
        `- Exception (first): when \`main\` has a merge queue and the PR is armed (the Phase 7 poll prints \`[ship.phase7.queue_wait]\`) the PR is waiting for GitHub to enqueue it — keep polling; never merge origin/main into it, resync-push, update-branch or --admin it (a fix commit for a red check is fine) until \`[ship.phase7.queue_wait_expired]\`, a push line, MERGED, a dequeue or any poll exit. This holds for a BEHIND reading only (a conflicting DIRTY PR still needs its sync). The script itself answers \`kind=queue_wait\` (exit 0, nothing synced) for that PR: a wait, not a failure.`,
        `- Otherwise, mergeStateStatus \`BEHIND\` or \`DIRTY\` → run \`${script} <PR-number>\` from the PR worktree (fetch → merge origin/main → push; DIRTY only when the local merge is clean; it refuses an armed BEHIND PR on a merge-queue repo with \`kind=queue_wait\`, so never hand-merge instead). Use the Phase 7 loop; never write your own poll loop — on a harness without a Monitor tool, run that block itself inside the waiting subagent or shell.`,
      ].join("\n");
  }
}