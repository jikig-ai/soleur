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

/**
 * The stdout-only read rule, as one instruction bullet. Every `behindSyncInstructions()` arm and every `pollInstructions()` arm
 * in harness.ts carries it (pr-merge-poll.test.ts iterates the `Harness` union).
 */
export const GH_STDOUT_ONLY_READ =
  "Read `gh` stdout only; send stderr to a file, never `2>&1`: gh 2.106.0 (measured 2026-11-25) prints a `hint:` block on stderr, rc 0, for `gh pr view` of an open PR, `gh run view` of an in-progress PR run and `gh api …/pulls/<N>`, so a merged capture's first line is not the state.";

/** Longest stderr line a `fetch-error:` carries — the fence's `gh_err_line` cut, `${e:0:200}`. */
export const GH_ERR_LINE_MAX = 200;

const POLL_STATE_LINE = /^(OPEN|MERGED|CLOSED) [A-Z_]+$/;

/**
 * The poll read, as a pure function: stdout is the answer, stderr is only the diagnostic (#12697).
 *
 * gh 2.106.0 (measured 2026-11-25) prints an 8-line `hint: … gh event listen …` block on STDERR, with rc 0, before stdout,
 * for `gh pr view` of an OPEN PR (a merged PR prints none), `gh run view` of an in-progress pull_request run, and
 * `gh api repos/O/R/pulls/<N>` (every sub-path, any PR state). No documented env var or config key turns it off (8 env vars
 * and 5 config keys tried). A `2>&1` capture's first line is then that hint, and every OPEN branch of the poll misreads it.
 *
 * Portable spec only: nothing calls this at runtime. The executing copy is the ship Phase 7 fence (and the merge-pr mirror),
 * whose `gh_err_line <rc>` is the SAME rule as the rc != 0 arm here, in the same order: drop every byte outside printable
 * ASCII, tab and newline (`LC_ALL=C tr -cd '[:print:]\t\n'`), THEN take the first line that is non-empty and starts with
 * neither `hint:` nor whitespace, cut to {@link GH_ERR_LINE_MAX}; `rc=<rc>` when there is none. pr-merge-poll.test.ts runs
 * the fence's own `gh_err_line`, extracted verbatim from ship/SKILL.md, against this function over one table.
 *
 * - `rc !== 0` → always `fetch-error: <that line>` or `fetch-error: rc=<rc>`, even when stdout looks like a valid state.
 * - `rc === 0` → the trimmed stdout when it is exactly one `^(OPEN|MERGED|CLOSED) [A-Z_]+$` line (the {@link PR_VIEW_POLL_JQ}
 *   shape), else `null`, so a merged stream is refused instead of misread. stderr is ignored.
 */
export function parsePrPollRead(r: { rc: number; stdout: string; stderr: string }): string | null {
  if (r.rc !== 0) {
    for (const raw of r.stderr.split("\n")) {
      const line = raw.replace(/[^\x20-\x7E\t]/g, ""); // strip FIRST, as the fence's `tr` runs before its `grep`
      if (line === "" || line.startsWith("hint:") || /^\s/.test(line)) continue;
      return `fetch-error: ${line.slice(0, GH_ERR_LINE_MAX)}`;
    }
    return `fetch-error: rc=${r.rc}`;
  }
  const out = r.stdout.trim();
  return POLL_STATE_LINE.test(out) ? out : null;
}

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
        `- Exit 11 is a no-op: \`kind=noop\` is GitHub state lag. \`kind=queued\` means the PR is IN the merge queue and nothing was pushed (a push dequeues it): it exits 0 here and 11 only with \`--step\` — keep polling for MERGED, never push, update-branch or --admin it; re-poll, then re-run. \`kind=queue_wait\` (an armed BEHIND PR on a merge-queue repo, nothing synced) is a wait, not a failure: exit 0 here and exit 14 only under a flagless \`--step\`. Exit 13 (\`kind=dequeued\`) means it left the queue unmerged (a failed merge_group run or a removal; auto-merge may still read armed) — follow the recovery on that line. Exit 12 (\`kind=wrong_branch\`) means this worktree is not the PR's branch — cd to it. Any other \`kind=\` line names its next action.`,
        `- Re-poll after push; do NOT ask the operator to update the branch.`,
        `- ${GH_STDOUT_ONLY_READ}`,
      ].join("\n");

    case "claude":
      return [
        "**BEHIND/DIRTY resync (Claude Code)**",
        `- When mergeStateStatus is \`BEHIND\` or \`DIRTY\`, the ship Phase 7 Monitor loop calls \`sync-pr-behind.sh <PR-number> --step\` once per attempt (the Phase 7 fence's call, never yours; the script refuses a flagless \`--step\` on an armed BEHIND PR of a merge-queue repo: \`kind=queue_wait\`, exit 14, nothing synced). Never write your own poll loop — use that one. The standalone entry is \`${script} <PR-number>\`: it refuses an armed PR on a merge-queue repo with \`kind=queue_wait\` (exit 0, a wait, not a failure); DIRTY auto-syncs only when locally clean.`,
        `- FORBIDDEN: heartbeating on pending checks while BEHIND or DIRTY — auto-merge is blocked — unless the script reported \`kind=queued\` (exit 11 with \`--step\`): a PR in the merge queue is not blocked, the queue merges it, so keep heartbeating and never sync it; likewise when \`main\` has a merge queue and the PR is armed (the Phase 7 poll prints \`[ship.phase7.queue_wait]\`) on a BEHIND reading (a conflicting DIRTY PR still syncs) — GitHub enqueues it, in force until \`[ship.phase7.queue_wait_expired]\`, a push line, MERGED, a dequeue or any poll exit; \`kind=dequeued\` (exit 13) stops the poll with the recovery.`,
        `- ${GH_STDOUT_ONLY_READ}`,
      ].join("\n");

    case "cursor":
      return [
        "**BEHIND/DIRTY resync (Cursor CLI)**",
        "- No wait primitive has been measured on the Cursor CLI.",
        "- This run cannot finish that gate.",
        "- Continue that merge on a harness that already has a wait, or stop.",
        "- Do not invent a wait. Do not hand the wait to the operator.",
        "- This stop does not make the plugin supported.",
        `- ${GH_STDOUT_ONLY_READ}`,
      ].join("\n");

    default:
      return [
        "**BEHIND/DIRTY resync**",
        `- Exception (first): when \`main\` has a merge queue and the PR is armed (the Phase 7 poll prints \`[ship.phase7.queue_wait]\`) the PR is waiting for GitHub to enqueue it — keep polling; never merge origin/main into it, resync-push, update-branch or --admin it (a fix commit for a red check is fine) until \`[ship.phase7.queue_wait_expired]\`, a push line, MERGED, a dequeue or any poll exit. This holds for a BEHIND reading only (a conflicting DIRTY PR still needs its sync). The script itself answers \`kind=queue_wait\` (exit 0, nothing synced) for that PR: a wait, not a failure.`,
        `- Otherwise, mergeStateStatus \`BEHIND\` or \`DIRTY\` → run \`${script} <PR-number>\` from the PR worktree (fetch → merge origin/main → push; DIRTY only when the local merge is clean; it refuses an armed BEHIND PR on a merge-queue repo with \`kind=queue_wait\`, so never hand-merge instead). Use the Phase 7 loop; never write your own poll loop — on a harness without a Monitor tool, run that block itself inside the waiting subagent or shell.`,
        `- ${GH_STDOUT_ONLY_READ}`,
      ].join("\n");
  }
}