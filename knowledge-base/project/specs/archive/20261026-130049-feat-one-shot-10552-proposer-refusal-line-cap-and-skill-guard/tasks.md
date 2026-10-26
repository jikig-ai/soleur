# Tasks: fix(compound-promote) proposer refusals - line cap and skill-conflict guard

Plan: `knowledge-base/project/plans/2026-10-26-fix-compound-promote-proposer-refusal-line-cap-and-skill-guard-plan.md`
Ref #10552 (never Closes). Do not trigger the cron. Tests are written before the code they cover.

## Phase 1: Defect A - line cap

- 1.1 Write failing tests in `cron-compound-promote-draft-edit.test.ts`
  - 1.1.1 AGENTS boundary rows: 600 accepted, 601 `edit-invalid`/`too-long`; SKILL 1000 accepted, 1001 refused; 20 lines at each cap
  - 1.1.2 A 301-char line of two-byte characters is refused as `charset`
  - 1.1.3 Prompt assertion per target (hard cap from the constants, soft target 500)
  - 1.1.4 Pin test: `extractPerRuleCap(src)` helper (anchored, exactly-one, integer), used by the pin and by fixture rows (spacing/comment variant; f-string-only mention; zero/two matches fail loudly); path from `import.meta.url`, missing file is a hard failure
  - 1.1.5 Replace the existing `501`/`500` rows; remove the `skillConflictDiffBody` import and describe block
- 1.2 Implement in `cron-compound-promote.ts`
  - 1.2.1 Export `AGENTS_EDIT_LINE_MAX_CHARS = 600`, `SKILL_EDIT_LINE_MAX_CHARS = 1000` (comment: unpinned by design), `EDIT_LINE_TARGET_CHARS = 500`
  - 1.2.2 Inline per-target cap in the `too-long` arm of `newLinesCause`; prompt builder uses the same expression
  - 1.2.3 Rewrite the stale "skill-conflict comment" comment in `newLinesCause`; keep `RENDER_HAZARD_RE`

## Phase 2: Defect B - same-file skill-conflict guard

- 2.1 Write failing tests
  - 2.1.1 New `cron-compound-promote-skill-guard.test.ts`, table-driven; fake octokit records `(route, params)` (cases in the plan's Acceptance Criteria)
  - 2.1.2 Route-aware Octokit mock in `cron-compound-promote-draft-handler.test.ts` and `cron-compound-promote-patterns-handler.test.ts`; handler cases: different-file opens, same-file refuses (no POST, no Sentry for conflict), unverifiable (Sentry op), shared scan across two skill clusters, AGENTS-only run makes no pulls call
- 2.2 Implement
  - 2.2.1 Module-level `scanOpenPrSkillPaths({octokit, owner, repo, targets})` (two literal routes, 3 PR pages, 10 file pages, 150-request budget, `pr.user?.login`, skip `dependabot[bot]` only, fixed-string throw on non-array); `changed` records only paths equal to a requested target, first PR wins, first-reached bound reported
  - 2.2.2 `skillConflictVerdict` (`Object.hasOwn`, never `in`)
  - 2.2.3 Lazy `step.run("skill-conflict-scan")` assigned to a hoisted `let skillScan`, just before the apply step, only for a drafted skill cluster and only once; `targets` = kept proposals' skill target paths; no new `TARGET_ALLOW_RE.test(` in the handler, no second `Promise<ClusterOutcome>` opener
  - 2.2.4 Replace the apply-step guard block (conflict: warn with `fn`,`hash`,`pr`(integer),`target`; unverifiable: warn with `hash`,`bound` + `reportSilentFallback`); delete the comment POST and `skillConflictDiffBody`
- 2.3 Run `github-url.test.ts` and the outcome census (Guards 1, 1b, 1c, 3, 3b)

## Phase 3: co-moving probe and runbooks

- 3.1 Probe `nset` + header prose; P-6 loop entry; `MIN_CASES` to the new measured total
- 3.2 Runbook: `skill-conflict-guard` bullet rewrite, `-unverifiable` bullet (>1000 files / >150 requests note), `too-long` cap note
- 3.3 `betterstack-log-query.md` refusal enum list

## Phase 4: ADR and compliance record

- 4.1 ADR-092 in-place correction (600 / 1000 / 500 target, dated clause); ADR-300 residual bullet
- 4.2 DPIA memo: line-120 cell, Superseded markers (lines ~93, 157, 184, 197, 288), dated addendum, frontmatter pointer; conditional wording, not past tense
- 4.3 `compliance-posture.md` row 170 dated sentence; re-grep Art. 30 register for a stale claim

## Phase 5: verification

- 5.1 Run the suites and lints listed in the plan; `git grep` checks for removed symbols
- 5.2 PR body: `Ref #10552`, "effect unmeasured until #10552 clears", no claim a PR will open
- 5.3 Ship-time: factual note on #10676 (trigger fired 2026-10-26T09:47Z); do not delete the comment on #10812 (operator authorization, decision-challenges row C-1)
