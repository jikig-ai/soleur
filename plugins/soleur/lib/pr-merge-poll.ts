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
 * BEHIND means auto-merge will not fire until head catches up to base.
 */
export function shouldResyncBeforePoll(mergeStateStatus: string): boolean {
  return mergeStateStatus === MERGE_STATE_BEHIND;
}

/** Harness-specific BEHIND resync instructions. */
export function behindSyncInstructions(harness: Harness): string {
  const script = "bash plugins/soleur/scripts/sync-pr-behind.sh";
  switch (harness) {
    case "grok":
      return [
        "**BEHIND resync (Grok Build)**",
        `- When \`gh pr view --jq '.mergeStateStatus'\` returns \`BEHIND\`, **STOP** CI-only polling.`,
        `- From the PR worktree: \`${script} <PR-number>\` (fetch → merge origin/main → push).`,
        `- Match AwaitShell \`pattern\`: \`BEHIND detected|auto-sync.*pushed|BEHIND resolved|BEHIND unchanged\`.`,
        `- Re-poll after push; do NOT ask the operator to update the branch.`,
      ].join("\n");

    case "claude":
      return [
        "**BEHIND resync (Claude Code)**",
        `- When mergeStateStatus is \`BEHIND\`, run ship Phase 7 auto-sync inside the Monitor loop, or \`${script} <PR-number>\` from the worktree.`,
        `- FORBIDDEN: heartbeating on pending checks while BEHIND — auto-merge is blocked.`,
      ].join("\n");

    default:
      return [
        "**BEHIND resync**",
        `- mergeStateStatus \`BEHIND\` → merge origin/main into the branch and push before continuing.`,
      ].join("\n");
  }
}