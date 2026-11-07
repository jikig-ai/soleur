# Tasks: feat-one-shot-10550-create-arm-reserve-slot

Plan: `knowledge-base/project/plans/2026-10-27-fix-create-arm-reserve-week-cap-slot-plan.md`
Issue: #10550 (`Ref` only, never `Closes`). Fire no cron. Touch no other PR or issue (operator-held `self-healing/auto`
drafts, #10551, #8293, #8443, #11183, #10676, #11228). Never `git stash`.

## Phase 1 - Failing tests first (RED)

- 1.1 In `apps/web-platform/test/server/inngest/cron-compound-promote-create-handler.test.ts` add `h.capLefts` and a pass-through `vi.mock` of `@/server/compound-promote-create-arm` that records `runCreateProposeStep` `capLeft`; reset it in `beforeEach`
- 1.2 Update the header bullet "CTO G2" to the reservation semantics
- 1.3 Rewrite the `the week cap (CTO G2)` describe (lines ~421-463):
  - 1.3.1 remaining=2 + allow_create, model returns 2 valid clusters (2nd cluster: SKILL.md target on a fixture skill, evidence `Ls(8,5)`, distinct rationale token + new `stubModel` branch; verify it opens a 2nd PR on the unfixed handler): prompt "up to 1", `clusters_proposed` 1, at most 1 `apply-and-pr-*`, `capLefts` `[1]`, create verdict not week-cap
  - 1.3.2 remaining=1 + allow_create: no cluster model call, `anthropic-cluster` step id still present, `no-qualifying-clusters` with create fields, `capLefts` `[1]`
  - 1.3.3 remaining=0: keep the saturated-cap case's assertions verbatim (`week-cap-reached`); make its title number-free (drop "#11230 and #11231 today")
  - 1.3.4 allow_create false (absent and explicit false), remaining=2, model returns 3: prompt "up to 2", `clusters_proposed` 2
  - 1.3.5 invariant over openPrs 0 and 1: arm never `week-cap`, every captured `capLeft >= 1`
  - 1.3.6 amend "arm still runs with the whole cap left" to `capLeft` 2
- 1.4 Run the file against the UNCHANGED handler; record that 1.3.1, 1.3.2 and 1.3.5 fail for the stated reason (paste the failing assertion lines into the PR body)

## Phase 2 - Handler and arm comment (GREEN)

- 2.1 `cron-compound-promote.ts`: add `editCap` after the `remaining <= 0` early return
- 2.2 First statement of the `anthropic-cluster` callback: `if (editCap === 0) return { clusters: [] as ProposedCluster[], truncated: false };` (step id unchanged)
- 2.3 Use `editCap` in the clustering prompt and the post-parse `.slice(0, editCap)`; update the two `remaining` comments
- 2.4 Rewrite the comment above the create arm / `capLeft` (arithmetic unchanged)
- 2.5 `compound-promote-create-arm.ts`: comment-only update above `fail("week-cap", "no-slot"`; confirm `git diff` shows comment lines only
- 2.6 Re-run the handler file; then patterns-handler, outcome-census, create-arm and create-parity suites (all unmodified and green)

## Phase 3 - Runbook, ADR clause, decision records

- 3.1 Runbook (i) class-table `week-cap` row (brief text)
- 3.2 Runbook (ii) reachability bullet
- 3.3 Runbook (iii) precondition bullet (replace the stale #11230/#11231 evidence-PR clause: both are CLOSED, the open drafts are #11290/#11291; word it generically; do not touch those PRs)
- 3.4 Runbook (iv) interim rule 2 split
- 3.5 Runbook (v) "Where the create outcome sits": drop the last-slot sentence and the stale "today: #11230 and #11231" parenthetical; `grep -c '#1123[01]'` on the runbook must print 0
- 3.6 Runbook line 254 ("at most 2") and the `create_detail` `week-cap` gloss (keep backticked `no-slot`)
- 3.7 ADR-092 line 318: append the reservation clause after the parity-pinned prefix
- 3.8 Verify both `decision-challenges.md` writes exist (branch ruling row; archived `G2 amended 2026-10-27` row)

## Phase 4 - Verification

- 4.1 `compound-promote-runbook-parity.test.ts` (repo-wide suite) green; `compound-promote-create-parity.test.ts` green
- 4.2 `tsc --noEmit` for `apps/web-platform`; markdownlint on touched markdown
- 4.3 `bash plugins/soleur/test/c4-count-parity.test.sh`
- 4.4 `git diff --stat` matches Files to Edit; no new key in `CREATE_ONLY_KEYS`

## Phase 5 - Ship

- 5.1 PR body: `Ref #10550`; "removes the structural cause of the observed week-cap refusal"; effect unmeasured until a live-fire clears; no "will open a PR"
- 5.2 Treat any red check as a finding until its first log line is read; one `gh pr merge` per call
- 5.3 After merge: `deploy-arm.sh find --wait`, served sha equals merge sha, `soleur:postmerge`; DONE only after "postmerge verification complete!"
