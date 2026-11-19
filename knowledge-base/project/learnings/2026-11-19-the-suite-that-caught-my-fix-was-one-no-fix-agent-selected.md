---
title: The suite that caught my fix was one no fix agent selected
date: 2026-11-19
category: test-failures
module: apply-web-platform-infra / inngest host replace
tags: [review-fix-round, test-selection, workflow-guards, url-redaction, pr-12876, issue-12742]
---

# Learning: the suite that caught my fix was one no fix agent selected

## Problem

PR #12876 (#12742 item 1) moved the `inngest-host-replace` typo-guard into its own workflow step,
placed before `Load infra credentials (tiered)`. The fix agent ran every suite in its brief and all
were green. CI leg 1/4 went red on a suite nobody had selected:
`apps/web-platform/infra/inngest-host-replace-preflight.test.sh` (the #10544 inherited-done
preflight guard). Its step-order predicate treated any step whose `run:` contained the bare token
`-replace` as a plan/apply step. The new step's error text, `inngest-host-replace requires
confirm=…`, matched, so a plan/apply step appeared to sit ahead of the preflight.

The suite had not been selected because selection followed the files the brief named. This suite
names none of them: it reads the workflow by job and step name.

## Solution

- Reworded the message so the immediate red cleared.
- Fixed the class in the guard. The predicate now reads terraform's FLAG form,
  `(?<![\w-])-replace(=|\s)`, not the word.
- Added two rows to that suite: m40 (a prose step naming the target stays green; it failed under the
  old predicate) and m41 (`-replace=` in any step ahead of the preflight is still red). Floors are
  now 50 assertions and 42 mutants.

## Key Insight

When a fix edits a workflow job, select suites by grepping for the **job and step names** and the
**workflow path** (`git grep -l '<job_id>\|<target-name>' -- '*.test.*' 'tests/scripts/test-*'`),
not by the lines changed. In this PR that grep returned 15 suites that no brief had listed. A
content-regex guard over a shared file is invoked by everything that file contains, including
prose.

Second insight from the same session: a reviewer's PROPOSED FIX is new code and needs the same
adversarial inputs as the defect it fixes. The verifier proposed
`^(?<s>([A-Za-z][A-Za-z0-9+.-]*:)?(//)?)` to strip userinfo from scheme-relative URLs. On `u:p@h`
the optional scheme group binds `u:` and the result is `u:h`, which leaks the username the
original regex already removed. The applied form, `^(?<s>(([A-Za-z][A-Za-z0-9+.-]*:)?//)?)`,
needs `//` after any scheme. It was checked on `//u:p@h/x`, `u:p@h`, `https://a@b@c/x?y#z`,
`https://u:pa?ss@host/x` and `mailto:u@h` before it went into the file.

## Session Errors

1. **`gh issue view --comments --json` flag conflict** (forwarded). Recovery: separate calls.
   **Prevention:** none needed; one-off CLI usage.
2. **The worktree commit guard blocked `git commit` twice** on a false "main/master" detection and
   an unresolvable `$(pwd)` (forwarded). Recovery: literal `git -C /abs/path`, with `git add` as its
   own call. **Prevention:** use absolute literal paths in git write commands inside worktrees.
3. **`lint-guard-contract.py` rejected a numbered-list Guard Contract** (forwarded). Recovery:
   markdown table rows. **Prevention:** write Guard Contract matrices as tables from the start.
4. **MD009 trailing space.** Recovery: stripped. **Prevention:** run markdownlint on touched `.md`
   files before committing.
5. **The private-IP ratchet went to 319, over its baseline of 318.** Recovery: a synthesized
   `10.0.9.9`. **Prevention:** already covered by the work skill's whole-repo-ratchet rule; never
   write the live private literal in a fixture.
6. **An apostrophe in a comment broke `inngest-host-state.sh`'s single-quoted python block.**
   Recovery: reworded. **Prevention:** no apostrophes inside a `python3 -c '…'` body; run
   `bash -n` and the suite after any edit there.
7. **The first 256 B cap on `sdk_app_url` would have pushed the row past logger's 1024 B limit.**
   Recovery: a 160 B cap, measured at the widest live field widths. **Prevention:** size any new
   row field against the measured widest row, not the typical one.
8. **MD038 on a `|` inside a code span in a table.** Recovery: escaped. **Prevention:** escape
   pipes in code spans inside tables.
9. **The hook blocked `git stash list` in the worktree (twice).** Recovery: other commands.
   **Prevention:** never type `git stash` in a worktree, even read-only.
10. **The fix agent's step-text token tripped a suite it never selected** (the subject of this
    learning). Recovery: rewording, then the predicate fixed as a class with rows m40/m41.
    **Prevention:** fix-round briefs include a suite-selection grep on the edited job and step names
    (routed to `review/references/risk-tier-and-fix-rounds.md`).
11. **The round-2 runbook rewording tripped `lint-infra-no-human-steps` (advisory) in CI.**
    Recovery: wrapped the owner-reserved break-glass prose in a `lint-infra-ignore` region.
    **Prevention:** run `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`
    locally after any runbook edit that names terraform or SSH.
12. **A reviewer's proposed regex fix would have leaked the username in `u:p@h`.** Recovery: a
    corrected regex, tested on the adversarial inputs first. **Prevention:** run a reviewer's
    proposed fix against the defect's adversarial inputs before applying it.
13. **The local affected gate refused with rc=4** because another worktree's full gate was in
    flight, so it measured nothing. Recovery: targeted suites plus CI as the gate. **Prevention:**
    already covered by the contention banner; never report a refused gate as a run.
14. **I swapped `inngest-bootstrap.sh` in the live worktree to measure user-data headroom**, then
    restored it and checked with `git diff --stat`. The verification seat also briefly copied a
    file into the worktree. **Prevention:** do comparative measurements in a
    `scripts/soleur-sandbox.sh` copy, never in the live tree.
15. **The sandbox mutation control was already red** (one fail: the recipe sweep needs a git tree),
    so the mutant was read as a delta (one extra fail). **Prevention:** give the sandbox a git tree
    (`git worktree`-free `git init` plus `add`) when the suite sweeps `git ls-files`, or name the
    pre-existing red in the report.
16. **The round-1 data-integrity seat ran about 12 hours and reported against a stale head.**
    Recovery: triaged against the current tree; one open item (the host-state `sdk_sync=error`
    NOTE) was fixed, the rest were already closed. **Prevention:** none beyond the existing rule
    never to fabricate a pending seat's result.
17. **`cloud-init-user-data-size.test.ts` "seam can only RAISE the floor" is red locally**
    (headroom 388 B against a hardcoded 400). The same value was measured with main's bootstrap.
    It is tracked in #12850. **Prevention:** check an issue search before attributing a red to the
    PR.

## Tags

category: test-failures
module: apply-web-platform-infra
