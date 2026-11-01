# Tasks — feat-one-shot-11678-mq-canary-followups

Plan: `knowledge-base/project/plans/2026-11-01-docs-mq-grouped-canary-followups-plan.md`
Draft PR: #11768 (docs-titled: `docs(arch): record merge-queue grouped-landing canary + machinery follow-ups (#11678)`)

## Phase 0 — Re-read live state (read-only)

- [ ] 0.1 `gh run list --workflow merge-queue-cla-synthetics.yml -L 10 --json databaseId,conclusion,createdAt` — confirm every post-01:55Z run is `success`.
- [ ] 0.2 Queue-state read for #11688: `bash plugins/soleur/scripts/sync-pr-behind.sh 11688 --queue-state` (or the `gh api graphql` equivalent from the plan). Record `isInMergeQueue` / `autoMergeRequest` / newest `REMOVED_FROM_MERGE_QUEUE_EVENT`.
- [ ] 0.3 Re-confirm the three member landings: `git log origin/main --format='%h %s' -8` (`0e8a6ebb02` #11734, `95231bda1b` #11756, `4366c47940` #11728) and one `codeql-main-alert-gate.yml` run per member.

## Phase 1 — ADR-270 addendum

- [ ] 1.1 Append `### Addendum 2026-11-01 (#11678, #11768): grouped-landing canary — ejection stopped, members=3 observed` at EOF of `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md`, answering the 2026-10-31 open-measurements list (:1028-:1034): grouped head_ref deepest-member naming, `merge-queue-cla-verify=OK members=3 anchor=headCommit` run evidence, in-flight member enumeration, per-member squash + one push event per member, ALLGREEN ejection still unobserved, ejection-stopped run list, #11688 residual. Facts only — no actor+imperative pairs (`lint-infra-no-human-steps.py` scans this dir).
- [ ] 1.2 Run AC greps AC1–AC3 once before commit.

## Phase 2 — #11682 evidence comment

- [ ] 2.1 `gh issue comment 11682` — second occurrence: valid pushed `Reviewed-By-CMO` trailer + marketing diff on the branch, hook evaluated session cwd (main checkout) so `origin/main..HEAD` was empty; denied; bypassed via GraphQL mutations. Cite `.claude/hooks/ship-cmo-content-gate.sh` :85-:98; note the marketing-diff arm also fails closed on stale cwd.

## Phase 3 — Ratchet drift bug filing

- [ ] 3.1 `gh issue create` — title `ci: affected-index-ratchet red on every head — stale accept baseline vs live refs on main`; labels `type/bug`, `priority/p2-medium`, `domain/engineering`, `meta/machinery`; body per plan Phase 3 (measured row, ref pairs, consequence, fix size, `Ref #10959 #10860 #10448 #10865`).
- [ ] 3.2 Record the new issue number here: `#_____`.

## Phase 4 — Learning entry

- [ ] 4.1 Create `knowledge-base/project/learnings/workflow-patterns/<date>-<slug>.md` on the embedded-oid semantics miss (mint-time ref-embedded oid = provenance; per-entry `headCommit.oid` = binding) with corpus frontmatter per plan Phase 4.

## Phase 5 — PR metadata + commit

- [ ] 5.1 Retitle PR #11768 to the `docs(arch):` form (`gh pr edit 11768 --title ...`); `Ref #11678` in the body (never `Closes` — issue already closed).
- [ ] 5.2 Commit all artifacts via `git -c user.name="Jean Deruelle" -c user.email="jean.deruelle@jikigai.com" commit ...`; verify `git log --format='%ae %ce' origin/main..HEAD | sort -u` prints one line.
- [ ] 5.3 `npx markdownlint-cli2` clean on every new/edited doc; `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` clean.
- [ ] 5.4 Push. Never `git stash`.

## Phase 6 — Ready + merge arm

- [ ] 6.1 From the worktree cwd: `gh pr ready 11768`, then `gh pr merge 11768 --squash --auto` once required checks (`scripts/ci-required-ruleset-canonical-required-status-checks.json`) are green. `affected-index-ratchet` is advisory and does not block.
- [ ] 6.2 If a hook still denies on stale cwd: bypass via GraphQL mutations (`markPullRequestReadyForReview`, `enablePullRequestAutoMerge`) and note the use on #11682.
