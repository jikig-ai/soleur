---
title: Four session errors from the #12847 stretch, and two inherited claims found in triage
date: 2026-11-18
category: workflow-issues
module: git-worktree, ci, cron-containment
tags: [session-errors, cleanup-merged, gitignore, gh-cli, timeout, main-red, triage]
related: ["#9601", "#12824", "#12847", "#12913", "#12920", "#12905", "#12757"]
---

# Learning: four session errors from the #12847 stretch

## Problem

The #12824 work (PR #12847, merged 2026-11-18T15:54Z) under epic #9601 shipped and was verified. Along the way, four
process errors cost time. Errors 1 to 4 come from the operator's resume brief for that session, and error 4 was also
measured again in this session. Two more came up while triaging the issues filed in that stretch (5 and 6).

## Solution

The fixes are in the per-error Prevention lines below. The one code change is a `.gitignore` line for error 4, plus a
Sharp Edges bullet in `plugins/soleur/skills/git-worktree/SKILL.md`.

## Key Insight

`git status --porcelain` counts untracked files. Any tool that reads "non-empty status" as "uncommitted work" will
treat scratch files as work. Scratch must live outside the worktree, and generated links must be gitignored by a
pattern that matches links, not only directories.

## Session Errors (1-4) and triage findings (5-6)

1. **A headroom-floor test contradicted the create arm's design.** A test asserted a headroom floor as an invariant.
   The compound-promote create arm is built to refuse an offer that does not fit (`over-headroom`, as
   `compound-promote-create-arm.test.ts` and `compound-promote-create-persist.test.ts` assert), so it does not guarantee that floor. The test encoded a
   property the design does not have. (Source: the operator's brief. The test itself was not kept.)
   **Prevention:** before writing a test that asserts a floor or cap, find the code path that enforces it and quote it.
   If the design refuses rather than guarantees, test the refusal, not the floor.

2. **Duplicate repair work with #12913.** The three main-red ratchets that #12670 left (the skill-description word
   cap, the `fixture-relative-assert` baseline and the `c4-count-parity` agent count) were being repaired locally
   while #12913 was already fixing them on main (merged 2026-11-18T14:48Z). Fetching `origin/main` before the push
   would have shown it.
   **Prevention:** before repairing a red check on main, run `git fetch origin main && git log --oneline HEAD..origin/main`
   and `gh pr list --state all --search "<failing test or check name>"`. If a fix is landing, rebase onto it instead.

3. **`gh` CLI calls hung past the 120 s Bash tool timeout.** `gh` has no request-timeout flag or environment variable
   (`gh help environment`, `gh api --help`), so a stalled API request used up the whole tool budget, and the output was lost.
   **Prevention:** wrap every `gh` call in an agent shell with `timeout 60` (or `timeout 110` for `--log` and
   paginated calls, below the Bash tool's 120 s limit; or raise the tool's own timeout), and treat exit 124 as "not measured", never as "empty". This session did that and no call hung.

4. **`cleanup-merged` kept merged worktrees because of untracked files.** `worktree-manager.sh` skips a worktree when
   `git status --porcelain` prints anything, and that includes `??`. Measured 2026-11-18, four worktrees were kept as
   "has uncommitted changes":
   - `fix-12912-dry-render-headroom` (PR #12913, merged): `?? apps/web-platform/node_modules`, a **symlink** into a
     sibling worktree. `.gitignore` had `node_modules/`, and a pattern with a trailing slash matches directories only.
   - `feat-sentry-cost-consolidation` (PR #12844, merged): `?? .soleur-gate-logs/`, a scratch dir an agent chose.
   - `fix-doppler-config-inventory-refresh` (PR #11858, merged): `?? **RE-SCOPED` and `?? "§Deepen-Plan"`, files a
     mis-quoted shell line created.
   - `relay-write-token` (no PR): `?? knowledge-base/project/specs/relay-write-token-tmp/`.
   **Recovery:** added `node_modules` (no slash) to `.gitignore`. Verified in a scratch repo, with a control, that a
   symlink at `apps/web-platform/node_modules` shows as `??` when only `node_modules/` is present (root and nested), and
   is ignored once the bare root `node_modules` line is added. This covers worktrees checked out after this merges. The
   four worktrees already kept read their own `.gitignore` and stay kept until they are removed by hand.
   **Prevention:** write scratch to the session scratchpad, never inside a worktree (new Sharp Edges bullet in
   `git-worktree/SKILL.md`). A symlinked `node_modules` also ties the worktree to its sibling, so removing that sibling
   leaves a dangling link, and ignoring the link now hides it from `git status` even when it dangles. Prefer a real
   install (`npm ci --ignore-scripts`) or a link to the bare root, which is never reaped. Removing the worktree that
   holds the link deletes only the link, not its target. Whether `cleanup-merged` should treat known-ignorable `??` paths as clean is a design question.
   It is not changed here.

5. **An issue's fix direction carried an unverified premise (#12920).** It said the label should be created "through
   the Terraform-managed label set (labels are IaC here)". There is no `github_issue_label` resource on main. The real
   cause is that in `scheduled-marketplace-drift.yml` only the manifest-drift filing step runs `gh label create` and the delivery-canary filing step does
   not.
   **Recovery:** corrected in the triage comment on #12920.
   **Prevention:** for every "X is managed by Y" sentence in an issue, run the one grep that would refute it before
   routing on it.

6. **An issue stayed open after its fix shipped (#12905).** PR #12847 raised `tenant-integration` from 15 to 19
   minutes and cited #12905 with `Ref`, but the issue still said 15. Triage started from a stale premise. Since the
   raise, a main run passed in 959 s, which would have timed out at the old 900 s cap.
   **Prevention:** when a PR carries a partial fix for an issue it only `Ref`s, comment on that issue with what landed
   before merging.

## Tags

category: workflow-issues
module: git-worktree, ci, cron-containment
