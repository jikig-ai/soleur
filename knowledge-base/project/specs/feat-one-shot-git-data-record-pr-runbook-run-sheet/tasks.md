# Tasks: git-data Record PR, real-flip run sheet (Ref #8211, #11704)

Plan: `knowledge-base/project/plans/2026-11-01-docs-git-data-record-pr-real-flip-run-sheet-plan.md`
Decisions: `knowledge-base/project/specs/feat-one-shot-git-data-record-pr-runbook-run-sheet/decision-challenges.md`

## Phase 0: read-only evidence (before any edit)

- [ ] 0.1 `git fetch origin main`; confirm nothing newer on `origin/main` touches the four edit sites of the runbook; re-read #8209 (newest comment date), #11704, #11433
- [ ] 0.2 Deploy state of `78de558634`: served sha via the deploy arm and `/health`; if not served, stop the ssh tick
- [ ] 0.3 Fresh Better Stack read of `git_data_ssh_client=` for both hosts, explicit `--since` covering the deploy; reduce to one row per host (host, UTC time, value); no secret on a command line
- [ ] 0.4 Recompute the hash-bound file list with `git_data_rung2_bound_files` into the scratchpad
- [ ] 0.5 Baseline the Phase 3 scoped tests on the unmodified tree

## Phase 1: runbook edits (one commit, Edit tool, content anchors)

- [ ] 1.1 E1: `#8209` bullet, dated OPEN status, three credentials named, no acceptance written, not workflow-enforced
- [ ] 1.2 E2: ssh-client box `[x]` only with a row per host and the served sha; otherwise leave `[ ]` and say why
- [ ] 1.3 E3: `### Real-flip run sheet (#8211)` after the "R3 first-session reading" paragraph and before `### The D6 rotate`; RF0 to RF9 with a `Kind` column; fold in the four CPO conditions; link the rehearsal R0 row instead of restating it; name no user-invoked skill; no SSH read
- [ ] 1.4 E4: one pointer line at the top of "Before the first `flip`: the rollback rehearsal"; one bullet in "After the real cutover (owned by #8211)"

## Phase 2: GitHub comments (after the push, so the PR link resolves)

- [ ] 2.1 One comment on #11704: acceptance narrows to items 1 to 4; item 5 deferred to the hash-bound payload batch (#11433, #10296, #9066 if the CLO requires); cite `issuecomment-6546561355`; `Ref #11704`
- [ ] 2.2 One cross-reference comment on #11433; `Ref #11433`
- [ ] 2.3 Record both comment URLs for the PR body

## Phase 3: verification, push, PR

- [ ] 3.1 `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`; `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch`
- [ ] 3.2 `bash scripts/markdown-lint.sh` on the runbook; heading-diff shows exactly one added heading
- [ ] 3.3 `bun test plugins/soleur/test/invocation-axis.test.ts`
- [ ] 3.4 `git-data-refs-assert.test.sh`, `git-data-cutover-access.test.sh`, `git-data-wipe-assert.test.sh`, `git-data-wipe-access.test.sh` (all under `apps/web-platform/infra/`), `tests/scripts/test-git-data-root-key-arm.sh`
- [ ] 3.5 AC1 recomputation: diff names vs the 20 bound files and the evidence env are disjoint
- [ ] 3.6 Secret scan before every push; commit with the `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` trailer
- [ ] 3.7 PR #11812 body: `Ref #8211`, `Ref #11704`, decision table, comment URLs, session URL, ends with the generated-with line; mark ready; wait for required checks green; do NOT arm auto-merge; do NOT merge
