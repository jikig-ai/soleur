# Tasks — fix: vendor-drift machinery (#8180, #8181, #8182, #8183)

Plan: `knowledge-base/project/plans/2026-09-14-fix-vendor-drift-machinery-plan.md`
Branch: `feat-one-shot-8180-8181-8182-8183-vendor-drift-fixes`

## Pre-flight

- [x] T0. Re-check merge-base assumption (#8120 was OPEN at plan time, MERGED before review → rebased onto it and applied every post-#8120 port note). Re-check: `gh pr view 8120 --json state`.
  If MERGED, rebase and apply each FR's post-#8120 port note (per-bundle
  parameterization); if OPEN, implement against the single-bundle code as
  planned. Also `gh label create needs-human-review` if absent
  (runbook §2 contract; currently missing from the repo label set).

## FR-1 — #8180: route-pr re-vendor write

File: `apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts`

- [x] T1. Extend detect step: collect `driftedFiles` (`{liftedPath,
  upstreamPath, oldSha, newSha}`) by zip-pairing `lifted-files` and
  `upstream-files` parser output with a fail-loud length assert; fetch
  `newPinnedCommit` via `GET commits/{repoMeta.default_branch}`; switch the
  contents fetch `ref` from `"main"` to the resolved default branch; extend
  the detect result type.
- [x] T2. Implement the write loop INSIDE the existing
  `step.run("safe-commit-pr")` (same-step write+commit — replay safety per
  the 2026-06-14 learning): per drifted file, fetch `git/blobs/<oldSha>` and
  `git/blobs/<newSha>` (throw on 404), `git merge-file -L… -L… -L… --diff3`,
  `git hash-object --no-filters`, then `rewriteNoticeRecord` with
  assert-exactly-1-block/1-sub semantics.
- [x] T3. Bump top-level `pinned-commit` and `last-verified` (assert exactly
  one replacement each); conflict-marker scan (`^<<<<<<<`) →
  `needsHumanReview`.
- [x] T4. `safeCommitAndPr` call: `mergeMode` `"none"` on conflict else
  `"direct"`; `prLabels` += `needs-human-review` on conflict; prBody gains
  per-file merge status and the corrected `last-verified` sentence.
  **Capture the return value** — `status === "no-changes"` on this arm must
  be reported unhealthy via `reportSilentFallback` (the
  `pr-route-no-artifact` equivalent #8120 names; on main the return is
  currently discarded).

## FR-2 — #8181: blob→path→commit binding

File: `plugins/soleur/skills/gdpr-gate/scripts/vendor-pin-integrity.sh`

- [x] T5. Read `pinned-commit` via parser `field`, fail closed on
  empty/non-40-hex; replace the `git/blobs/<sha>` existence call in the
  `--verify-upstream` loop with
  `contents/<upstream-path>?ref=<pinned-commit>` + `--jq '.sha'` comparison
  against `upstream-blob-sha`; update the mode comment.

## FR-3 — #8182: dedup completeness

- [x] T6. On main shape: comment both `total_count` sites pinning the
  completeness semantics; add `fetchAllPages` helper (per
  get-workstream-issue-options.ts:31-44) ready for the post-#8120
  enumeration call sites, and apply it if #8120 has merged.

## FR-4 — #8183: issue metadata enrichment

- [x] T7. Capture `repoMetaSummary {fullName, archived, defaultBranch}` in
  the detect probe (absent on `unreachable`); render an "Upstream repository
  metadata" section in the issue body on all issue-route exits, with a
  probe-failed line for `unreachable`.

## Tests

- [x] T8. `apps/web-platform/test/server/inngest/cron-content-vendor-drift.test.ts`:
  multi-file batched-drift fixture → merged bytes + NOTICE bumps + PR
  created; replay-shape test (memoized detect, clean worktree → step
  re-writes before commit); conflict fixture → `mergeMode:"none"` +
  `needs-human-review` + markers; NOTICE-assert throw case; dedup
  `{total_count:1, items:[]}` suppression; issue-body metadata section incl.
  `unreachable` rendering.
- [x] T9. `plugins/soleur/test/vendor-pin-integrity.test.sh`: valid
  path/commit/blob passes; blob-elsewhere fails; correct path at wrong
  commit fails; missing path fails.
- [x] T10. `plugins/soleur/test/vendor-drift-workflow.test.sh`: keep
  architecture assertions green; add assertion that `--verify-upstream`
  issues the contents-endpoint call (not `git/blobs`).

## Verify

- [x] T11. `bun test apps/web-platform/test/server/inngest/cron-content-vendor-drift.test.ts`
  and `bash plugins/soleur/test/vendor-pin-integrity.test.sh` +
  `vendor-drift-workflow.test.sh` all green; Guard Contract mutation-matrix
  rows exercised.
