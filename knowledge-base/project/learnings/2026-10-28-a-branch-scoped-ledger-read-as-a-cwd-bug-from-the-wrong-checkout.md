---
title: "A branch-scoped ledger read as a cwd bug — the shell was in the wrong checkout and the tally correctly read main's numbers"
date: 2026-10-28
category: workflow-patterns
tags: [worktree, pipeline-tally, emit-review-trailer, wrong-checkout, forensic-triage, shared-counters]
issue: 8628
pr: 11381
branch: feat-one-shot-8628-inngest-4-upgrade
---

# Learning: a second checkout shares your relative paths, and branch-scoped instruments read its truth correctly

## Problem

Triage for PR #11381's compound phase surfaced two observations that looked like a
cwd-dependency defect in shared machinery:

1. `emit-review-trailer.sh --fix-round --since 5ba9802499` failed with
   `--since 5ba9802499 is not an ancestor of HEAD` when invoked from an
   `apps/web-platform` cwd, then succeeded with identical args from the worktree root.
2. `pipeline-tally.sh show` printed `seats=57 fix_rounds=1` from the `apps/web-platform`
   cwd but `seats=25 fix_rounds=2` from the worktree root — a "different ledger per cwd".

## Investigation: verify the reader, then the script

`pipeline-tally.sh` resolves its ledger as
`<git-common-dir>/soleur-session-state/counters/<branch-slug>-<shorthash>` — branch name
from `git branch --show-current`, root from `_session_state_root()` →
`git rev-parse --git-common-dir`. Measured from both cwds in the worktree:

- `git rev-parse --git-dir`, `--git-common-dir`, `--show-toplevel`, and
  `git branch --show-current` return **identical absolute values** from the worktree
  root and from `apps/web-platform`. Nothing in the resolution is cwd-relative.
- Re-running `pipeline-tally.sh show` from both cwds prints the identical line
  (`seats=25 fix_rounds=2`).

So where did `seats=57 fix_rounds=1` come from? The counters dir is **shared across
every worktree and every branch of the repo by design** (anchored at
`--git-common-dir`, not at the worktree's own dir). Grepping it for the foreign
numbers found the match immediately: the ledger file `main-88d050` carries exactly
`seats=57 fix_rounds=1` — branch `main`'s own tally, accumulated by earlier pipeline
runs executed while the main checkout sat on `main`.

The subdir shell's git context was the **main repo checkout**
(`/data/git-repositories/jikig-ai/soleur/apps/web-platform`) — the same relative path
exists under both the worktree and the main checkout, so a `cd` to the sibling tree's
`apps/web-platform` looks identical in the prompt. A `GIT_DIR`/`GIT_WORK_TREE` env
leak produces the same confusion without the cwd ever leaving the worktree; both
shapes resolve "the git context is the other checkout".

The trailer failure is the same cause one level down: `--since 5ba9802499` (the
review-panel merge commit on the feature branch) is not an ancestor of the main
checkout's HEAD, so `git merge-base --is-ancestor` correctly refused — and the
`BRANCH == "main"` skip in the script never gets a chance to print, because the
`--fix-round` ancestor check runs first. Both "failures" were the instruments working
as designed against a different branch's truth.

## Solution

No script defect found — no issue filed. The fix was procedural: the second
invocation ran from the worktree root (right checkout), both instruments reported
the feature branch's real state (25 seats, 2 fix rounds), and the fix-round trailer
committed cleanly.

Diagnostic reflex this produces: before asserting a cwd-dependency bug in any
git-context consumer, run three commands that name which checkout's ground truth
you actually read:

```bash
git rev-parse --show-toplevel   # WHICH tree am I in
git branch --show-current       # WHOSE state am I reading
env | grep '^GIT_'              # is the context pinned by env, not cwd
```

A divergent read plus a coherent alternative value (57/1 is a *valid* tally, not
garbage) means "correct instrument, wrong checkout" far more often than "the script
derives state from cwd". The counters dir being shared repo-wide is what makes the
wrong read succeed silently — there is no error to trip on, only a stranger's true
numbers.

## Key Insight

**A branch-scoped instrument returning a different-but-coherent answer is not a
cwd bug until you have named the branch it read.** `hr-when-in-a-worktree-never-read-from-bare`
already covers reading the wrong checkout's *files*; this session is the same rule
applied to a checkout's *state* — the tally ledger, the ancestor graph, the session
locks all live at `--git-common-dir` keyed by branch, and a sibling checkout answers
them truthfully about itself. Verify the checkout before diagnosing the instrument.

## Session Errors

1. **E1 — ADR-243 amendment committed BEFORE the spike ran, asserting "S7 never
   ran".** The assertion was true when written; the spike commits landed later in the
   same PR and flipped it — a doc asserting evidence-state must be re-derived against
   the PR's later commits, not only against the moment it was written. Five review
   seats independently caught the false evidence state; fix rounds repaired it
   (commits `b04319b1f4`, `ffbe648624`). Recovery: amendment rewritten to the executed
   S-row verdicts; session-state's stale NOT-RUN line annotated superseded.
   **Prevention:** before shipping, re-read every evidence-state claim in committed
   docs (§Verification, amendments, spike records) against `git log` of the same PR —
   "did later commits land or contradict the evidence this doc asserts". Sibling
   class already documented:
   `learnings/2026-08-16-every-number-i-inherited-was-stale-and-the-panel-found-the-defect-class-inside-my-fix.md`
   (inherited claims), `learnings/2026-09-18-every-defect-was-in-my-verification-not-the-feature.md`
   §7 (assertion surfaces asserting delivery), `learnings/2026-09-08-the-guard-was-deleted-the-plan-still-cited-it-and-the-linter-validated-the-citation.md`
   (claim/referent drift). Not re-documented; this entry cross-refs instead.

2. **E2/E4 — Diagnosed a cwd-dependency bug that was a wrong checkout.** Recovery:
   the three-command checkout check above; the `main-88d050` ledger grep clinched it.
   **Prevention:** the checkout-naming reflex in Key Insight, routed into
   `review/SKILL.md`'s trailer call-out (the call site where it bit).

3. **E3 — `test-all --affected` crossed `TC_RUNTIME_CEILING_S` at 14670s/14400s**
   (365 pass / 7 fail / 317 declined-by-ceiling); the plan's "~15-25 min" estimate is
   ~10× stale. The decline is the ceiling working as designed; the capacity gap is
   the S4 affected-index program's reason to exist (`#9307`, `#9729`, `#10448`).
   Recovery: verdict recorded honestly as UNRESOLVED; CI carries the full battery.
   **Prevention:** none new — plan-phase battery estimates must quote the last
   measured wall-clock, not a remembered figure; tracked by the existing S4 issues.

4. **F1 — Bare `git` calls denied by the main-branch guard** (plan phase).
   Recovery: `git -C <abs-path>` per the guard's hint (commits `fa1c5128ef`,
   `a492b57d5a`). **Prevention:** already hook-enforced; the correct idiom landed.

5. **F2 — No nested agent-spawn tool inside the subagent harness** (plan phase;
   this compound phase likewise ran inline as the sanctioned fallback). Recovery:
   fan-outs ran as inline passes, disclosed as sequential — never claimed as
   independent review. **Prevention:** none needed; the disclosure discipline held.

6. **F3 — `webfetch` denied in background mode** (plan phase). Recovery: facts
   verified via `web_search` + direct npm tarball inspection of `inngest@4.26.0`.
   **Prevention:** none; the fallback produced stronger evidence than the denied
   tool would have.

7. **F4 — Plan premises corrected mid-flight** (no `bun.lock` — npm@11 only;
   stream-detach test path; self-hosted server pinned at v1.45.1 not v1.19.4).
   Recovery: premises re-derived from the repo and the installed tarball.
   **Prevention:** the inherited-claims learning in E1's cross-refs is the same
   class; no new rule.

8. **Spike harness could not complete in the first attempt** (build+tunnel
   harness under `/tmp/spike-v4/`). Recovery: harness stood up in a later phase;
   every S-row executed with S7 PASS. **Prevention:** none — one-off setup
   completion, honestly recorded as NOT-RUN until it ran (the honest record is
   what made E1's stale amendment detectable).

9. **Better Stack rejected the key-probe paging alert a second time** (`422`,
   `check_period 900` — commit `cd503b827f`). Recovery: raised to 3600 in the same
   commit. **Prevention:** recurring-but-environmental — the alert's allowed
   `check_period` set is a Better Stack-side constraint; when editing Better Stack
   alert resources, apply the probe once before relying on plan output.

## Related

- `knowledge-base/project/learnings/2026-08-16-every-number-i-inherited-was-stale-and-the-panel-found-the-defect-class-inside-my-fix.md`
- `knowledge-base/project/learnings/2026-09-18-every-defect-was-in-my-verification-not-the-feature.md`
- `knowledge-base/project/learnings/2026-09-08-the-guard-was-deleted-the-plan-still-cited-it-and-the-linter-validated-the-citation.md`
- Spec: `knowledge-base/project/specs/feat-one-shot-8628-inngest-4-upgrade/session-state.md`
  (Review Panel Ledger, Fix Round 1→2 sections)
