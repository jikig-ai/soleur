---
title: "The sweep that retired false sentences wrote new ones — copied from my own issue comment"
date: 2026-09-14
category: workflow-issues
module: git-data-birth-route
tags: [prose-sweep, inherited-claims, encryption-ledger, github-actions, sigpipe, value-pin, git-data]
issues: [8171, 8010, 8178, 8152]
severity: P2
---

# The sweep that retired false sentences wrote new ones — copied from my own issue comment

## Problem

PR #8171 was a post-birth sweep of the git-data birth route: retire prose that said a DO-NOT-DISPATCH banner still held the route, gate the boot-signal poll on the apply outcome, record the Better Stack table pair in the rung-2 evidence, and flip a stale encryption-ledger row. Every suite was green. A five-seat review then found 19 findings, and the ones that mattered were **in the new text, not the code**:

- Three sentences I lifted verbatim from the **#8010 comment I had written hours earlier** were false against the run logs: run 34822248580's poll never printed "the apply may be green" (it hit the unreachable-instrument branch, `re-dispatch once the query path works`); run 34861860722 was the **host replace**, not the birth (34836141887); PR #8128 **merged 2026-09-14** — 2026-09-13 was its authoring date.
- The plan flipped `hcloud_volume.rehearsal_luks` to `live_verification: "available"`. The schema reserves `available` for a **standing** probe Layer B can reconcile; the rehearsal volume is torn down every run, the second observation was of a *sibling* store, and the evidence sentence described a presence-of-`yes` check the capture script does not perform (it refuses a `no`).
- The ≤100-line budget deferred item 6, which left three "the banner holds the route" sentences **45 lines** from text the PR had just changed to "the banner was cleared" — an intra-file contradiction on the operator dispatch dialog.
- The new `# TABLE:` value pin asserted the lib **constant**, so a SUT printing the constant instead of the live table stayed green; its floor carried 4 of slack inherited from `main`.
- The PR's only runtime change (poll `if:` + a Dispatch-summary verdict `case`) had **no test**, and the `case` fell through GREEN on an empty outcome (a renamed step id resolves to `''`).

## Solution

- Every inherited sentence re-derived against `gh run view`, the job's check-run annotations and `gh pr view --json mergedAt`, and corrected at every site (grep by subject, not phrasing).
- Ledger row reverted to `unavailable:` with the falsified premise corrected and both point-in-time observations recorded; sibling rows no longer say the host was never born.
- Item 6's workflow half and item 9 taken after all — prose the diff's own edits falsify is not deferrable by budget.
- Summary `case`: `-z` guard on both outcomes → `::error::` + `exit 1`; `success/*` catch-all; `failure/*` no-op; `*)` default. A new test in `terraform-target-parity.test.ts` pins the `id:`s, the enumerated `!cancelled() && (… == 'success' || … == 'failure')` predicate, and **executes the case under `bash -eo pipefail` across eleven outcome pairs**; mutation-proven (predicate→`always()` and dropping the `success/*` exit each red it).
- Capture script exports the hot/archive **pair** from the sources lib on the default path; two override arms make the pin follow the input; floors re-measured (84, and one `_FLOOR` variable for readiness).
- `git-data-luks.test.sh`: 17 `printf "$src" | grep -q` sites over a 76 KB render → herestrings, including a negative assert that failed **open** under the race (the pre-commit battery went 414/1 on A23 while the suite was 30/30 in isolation).
- Filed #8178: the in-job boot poll returned `rc=22` on 40/40 CI polls across both dispatches while the same query succeeds under Doppler `prd_terraform` — the verification ADR-149 item 4 depends on has never worked in CI.

## Key Insight

**A claim I wrote down is not more trustworthy because I wrote it — it is less, because nothing flags it as needing proof.** The corpus re-derives plan-quoted numbers and treats `session-state.md` decisions as intent; an issue comment authored earlier in the same session gets neither treatment, and it is exactly where a quick summary of a run becomes "fact" for the next artifact. On a PR whose entire purpose is retiring false sentences, the copy-paste path is the one that reintroduces them.

The second insight is about the **budget**: a line-count bound is a fine way to rank *independent* prose fixes, and a wrong way to defer prose that the diff's own edits have just contradicted — that residue is not "unfixed", it is newly false.

## Session Errors

1. **Three claims copied from my own #8010 comment were false against the logs.** Recovery: re-derived each from the run log, annotations and `mergedAt`; corrected every site. **Prevention:** treat a claim from an issue comment (including my own) as a precondition — cite the run log or API field that proves it, never the comment; routed into `work` SKILL.md in this PR.
2. **The ledger flip to `available` over-claimed the schema.** Recovery: reverted with an honest `unavailable:` reason. **Prevention:** before flipping any `live_verification`, read the schema's definition of the value and name the standing probe that satisfies it.
3. **A budget-cut sweep left an intra-file contradiction.** Recovery: took items 6/9 anyway. **Prevention:** after a prose edit, grep the same file for the claim's subject; anything the edit now contradicts is in scope regardless of the line budget.
4. **The value pin was symmetric with the SUT's constant; floor slack inherited from main.** Recovery: override arms + re-measured floor. **Prevention:** a value pin's expected value must not be the same constant the SUT reads; re-measure floors from `git show origin/main:<suite>` plus the delta.
5. **The only runtime change had no test; the verdict `case` failed open on an empty outcome.** Recovery: parity-test arms executing the case under bash. **Prevention:** a workflow `if:`/verdict change gets a test that executes the extracted block, in the same commit.
6. **`git-data-luks` A23 false-FAIL in the pre-commit battery (SIGPIPE, pipefail, 76 KB).** Recovery: all 17 sites → herestrings. **Prevention:** the documented class; grep a test file for `printf … | grep -q` over any variable holding a whole rendered file.
7. **`lefthook run pre-commit --commands` is not a flag in lefthook 2.1.6**; its exit 1 was read only after committing. Recovery: ran gitleaks, markdown-lint and the infra-steps lint directly — clean. **Prevention:** read the rc of a gate before the commit that depends on it.
8. **The CI boot poll has never read a row (40/40 rc=22).** Recovery: filed #8178. **Prevention:** a verification step must print the first stderr line of a failed probe; `2>/dev/null` on the only verifier hides the cause.
9. **The dispatch scratch worktree was reaped by a sibling session's `cleanup-merged`.** Recovery: worked from the merged feature worktree (read-only). **Prevention:** create scratch worktrees with `SOLEUR_SKILL_NAME` set so they carry a lease.
10. **`worktree-manager.sh create` run from inside a worktree nested the new one under it.** Recovery: `git worktree move`. **Prevention:** run worktree creation from the bare repo root.
11. **`git stash list` used as a harmless probe was hook-blocked.** One-off; the hook worked.
12. **A process-listing probe by full command line was blocked by the self-match hook — twice, the second time because the literal appeared inside a heredoc body.** One-off; use `proc.sh list_runs`, and write prose that quotes such commands with the Write tool rather than a shell heredoc.
13. **`TEST_GROUP` shards REFUSED rc=4 (sibling runs).** Recovery: enumerated and ran 45 consumer suites. **Prevention:** existing guidance.
14. **The first real git-data host died on a transient GitHub 504** at `gitdata_doppler_dl` with `curl --retry 3` (~7 s budget) on a once-per-instance step; re-birthed by `git-data-host-replace`. **Prevention:** minutes-scale retry budget — hash-bound, tracked as #8010 item 14.
15. **Round-2 commit ran a 2 h 10 m `bun-test` pre-commit battery** because a `.ts` test was staged. **Prevention:** batch `.ts` edits into one commit and run the touched suites first, so a single battery covers the final tree.
16. **The readiness floor edit missed the `-lt 149` literal on the first pass** (a string replace matched only the messages). Recovery: follow-up edit, then one `_FLOOR` variable. **Prevention:** a floor is one variable, never four literals.
17. **(#8152) `rc_update` default `${5:-\{\}}` emitted literal backslashes** → unparseable JSON, 6 rows red. Recovery: `local unknown="${5:-}"; [[ -n "$unknown" ]] || unknown='{}'`. **Prevention:** never put a brace literal inside `${var:-…}`.
18. **(#8152) CI P1b `fixture-relative-assert` red on the new `mk_plan_cfg` redirect** — basename consumer-grep cannot find corpus-wide scanners. Recovery: byte-identical `assert_fixture_dir`. **Prevention:** run the two fixture ratchets on any new `*.sh` under tests/.
19. **(#8152) BEHIND→CONFLICTING on generated `rule-metrics.json`.** Recovery: took main's copy. One-off; generated files resolve to main.

## Related

- `knowledge-base/project/learnings/2026-09-14-the-birth-gate-refused-the-real-birth-because-its-fixtures-never-showed-it-a-real-plan.md` — the #8152 half of this birth
- `knowledge-base/project/learnings/2026-07-20-i-swept-by-file-when-the-unit-of-truth-was-the-claim.md` — claim-indexed sweeps
- `knowledge-base/project/learnings/2026-08-06-i-shipped-two-unmeasured-causal-claims-inside-the-lint-that-forbids-them.md` — inherited framings
- `knowledge-base/project/learnings/test-failures/2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards.md` — the A23 class
