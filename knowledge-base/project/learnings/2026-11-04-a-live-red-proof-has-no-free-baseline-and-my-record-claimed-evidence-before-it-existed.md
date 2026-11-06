---
date: 2026-11-04
category: workflow-patterns
issue: 9927
pr: 12107
---

# A live red-proof has no free baseline, and my record claimed evidence before it existed

**What happened.** Resuming the sole-copy LUKS epic, the task was to show in CI that deleting `delete_protection = true` on `hcloud_volume.inngest_redis_luks` turns the required `test` aggregator red, and to record it in an ADR-282 addendum. The red-proof worked (run 41905817469: `test-scripts (3/8)` 45 passed / 44 failed of 89, the `VOL_DELETE_PROTECTION` case text; `test-scripts (1/8)` and the `test-bun` G2e pin also red). A six-seat review then found the record itself had outrun its evidence.

**Facts worth keeping.**
- A plain draft push cannot show the red: `CI_DRAFT_LIGHT=on` skips `test-scripts` on every draft `pull_request` push. Dispatch `ci.yml` on the branch instead (`workflow_dispatch` runs the full battery).
- There is no free green baseline on main: the push run on main skips `test-scripts` and `test`. A baseline needs its own dispatch on the unmutated base branch, and the shard queue made it a 40-minute wait.
- A throwaway PR that deletes protection on a sole-copy volume must target a disposable base cut from `origin/main`, never main. The "CI Required" ruleset has two bypass actors (an organization admin and a repository role, both `pull_request` mode), so a red `test` does not make a PR into main unmergeable, and a merge to main triggers the production apply. The base stops that, but a retarget (`gh pr edit --base main`) by anyone with write access re-opens it, so close the PR as soon as the evidence is recorded, not at the end of the pipeline.
- The single-line deletion turned three legs red (the new Guard 1 leg, a drift-check suite, the older G2e pin), so the older anchors and the new one each fire; the other G2e failures in the same run (mutation matrix, comment-stripper rows) are collateral of the already-deleted line, not extra evidence.

## Session Errors

1. **A PreToolUse hook blocked a heredoc whose ADR prose quoted the Doppler secret-write command** — Recovery: reworded to "the Doppler CLI secret-write verb". **Prevention:** when documenting a guarded command in prose, name it by role, not by its literal text; the hook scans the whole Bash call, heredoc included.
2. **`bc` is not installed, so a timing wrapper printed an empty elapsed value** — Recovery: re-timed with Python. **Prevention:** time with `python3 -c`/`time`, not `bc`.
3. **The planning subagent's `decision-challenges.md` failed the ruling gate** (class `operator (scope / production-mutating / money)`, placeholders where rulings go, reconciliation rows without the ruling shape) — Recovery: split the class row, one batched CTO spawn for the four technical rows. **Prevention:** already enforced; one-shot's technical-ruling gate caught it before `work`.
4. **I wrote "Ruled by CTO agent" on a row I decided myself** — caught by the fix-round seat. Recovery: relabelled the row `taste`, "Default applied by the lead, not a CTO ruling". **Prevention:** the `Ruled by CTO agent` label requires a spawn in the same session; if there is none, the row is a lead default.
5. **The plan assumed a green `test-scripts (3/8)` baseline on the same SHA from main's run** — main's push run skips the shards. Recovery: dispatched `ci.yml` on the unmutated base. **Prevention:** before promising a CI baseline, read `gh run view <main run> --json jobs` for the job in question; a skipped job is not a baseline.
6. **My addendum drafts stated things ahead of the evidence** (the baseline "is on #9927" while its run was in progress; the throwaway PR "closed at the end of the pipeline" while open; the ledger presented as exhaustive while omitting name-admission and log-row copies; a Superseded marker promising a CI wall time the text did not give). Recovery: rewrote the section so each claim names its scope and its state. **Prevention:** for every sentence a record adds, ask "is this already true, and over what set?"; write pending things as pending and state a ledger's exclusion rule.

## Key Insight

A record written in the same session as the act it records tends to describe the act as finished and the evidence as complete. The review's six seats converged on one cause: completeness and past-tense claims written before the baseline run, the cleanup and the exclusion rule existed. Write the state of each item as it is, and put the exclusion rule beside any "derived by grep" ledger.

## Tags
category: workflow-patterns
module: adr-282, ci, sole-copy-luks
