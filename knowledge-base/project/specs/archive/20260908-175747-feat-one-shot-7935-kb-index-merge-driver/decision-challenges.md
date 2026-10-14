# Decision challenges — feat-one-shot-7935-kb-index-merge-driver

Recorded headless per ADR-084. `ship` renders these into the PR body and files them as an
`action-required` issue. The operator's stated direction is the default and was NOT overridden.

## UC-1 — "Do not commit the generated index at all"

**Stated direction (issue #7935 and the session brief).** Create a root `.gitattributes` registering a
merge driver for `knowledge-base/INDEX.md` that resolves conflicts by regenerating.

**The challenge.** Two independent reviewers (the plan-review architectural lens and the strong-model
consult) converged on the same alternative: `git rm --cached` the three generated files, add them to
`.gitignore`, drop the `&& git add knowledge-base/INDEX.md` from the existing lefthook stanza, and let
each checkout regenerate its own copy. That dissolves the merge surface entirely — no driver, no
`.gitattributes`, no local `git config` registration, no consistency guard, no ADR. The supporting
facts check out: `knowledge-base/INDEX.md` was touched 27 times in the last 30 days (measured), the
generator is a pure function of the tree and runs in 9.9 s, `plugins/soleur/skills/kb-search/SKILL.md`
already carries a graceful "Missing `INDEX.md` → note and continue with content grep only" path, no CI
workflow references the file, and `plugins/soleur/lib/kb-coverage.ts` already names it "the in-repo
warning for exactly this shape".

**What the challenge costs, which the reviewers did not price.** `git worktree add` does not copy
ignored files, so every one of the 37 linked worktrees (measured; the "~14" figure in the cited 2026-08-09 learning is stale) would start with no index at all, and the
regeneration would have to run from a `SessionStart` hook whose matcher fires on `startup|resume|clear|compact`
— a 9.9 s tax on every compaction. The KB browser at `apps/web-platform/app/(dashboard)/dashboard/kb/`
lists whatever the connected repo contains, so an untracked index simply stops appearing there
(degradation, not breakage). And un-tracking a 6,432-row file that five skills and agents grep is a
materially larger change than #7935 scopes, against an explicit "this PR is ONLY the merge driver"
instruction.

**Disposition.** The operator's direction stands; this PR ships the driver. The alternative is
recorded here rather than acted on, and it is a coherent candidate for its own issue if the operator
wants it. No issue is filed from this plan — #7935's net-issue-flow must stay Closing:1 / Filing:0 /
Net:-1.

**What was adopted from the challenge.** The reviewers' mechanical findings were folded into the plan
rather than argued with: the consistency guard is load-bearing (git cannot make an unregistered driver
loud — measured fact M1), so it became a regeneration diff rather than a structural lint; the lefthook
registration surface was cut because a `pre-commit` hook fires after the merge it was meant to arm and
is known to be bypassed in worktrees; and the bespoke `--flat` merge mode for the two facet files was
cut in favour of git's built-in `merge=union`.
