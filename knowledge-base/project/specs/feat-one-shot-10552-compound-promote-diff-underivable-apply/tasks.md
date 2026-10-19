# Tasks - fix(compound-promote): every weekly proposal refused diff-underivable-apply (#10552)

Plan: `knowledge-base/project/plans/2026-10-19-fix-compound-promote-diff-underivable-apply-plan.md`

Test-first throughout (`cq-write-failing-tests-before`). Read every census suite completely
before editing the handler.

## Phase 0 - RED

- 0.1 Add rows T1, T2, T4 to `apps/web-platform/test/server/inngest/cron-compound-promote-allowlist.test.ts`
  (anchor mid-file, append at EOF, SKILL.md path; each also asserts `git apply --cached` and
  `checkDiffPaths` accept the derived diff and the header is `diff --git a/<path> b/<path>`).
- 0.2 Add the refusal rows: T3 (no trailing newline), T5 (anchor absent), T6 (anchor duplicated),
  T7 (empty / blank / embedded-newline `new_lines`), T9 (CR in base), T10 (target absent),
  T11 (over 120,000 bytes, model not called), T12 (disallowed path, no `git show`, model not called).
- 0.3 Add T14 (M1, M2, M3 fixtures still `underivable-apply` through `checkDiffPaths`).
- 0.4 Add T15 (handler-level, two clusters, stubbed `post`): both clusters reach the apply step and
  no `diff-underivable-apply` is recorded. Add T16 (phase-2 API error propagates) and T17 (schema
  constants) to `cron-compound-promote.test.ts`.
- 0.5 Confirm each new row fails for an assertion reason (export stubs that throw, so RED is not an
  import error). Record the output.

## Phase 1 - GREEN, derivation

- 1.1 `buildAdditiveEditDiff` in `cron-compound-promote.ts`: base preconditions (trailing LF, no CR),
  `new_lines` validation, unique-anchor check, splice, `git diff --no-index --no-color --no-prefix --
  a/<path> b/<path>` via `spawnGitCapture` in a temp dir (exit 1 is success), additivity assertion
  (a `-` line maps to the retained `diff-underivable-apply` plus a `draft-edit-nonadditive` Sentry event).
- 1.2 Export `EDIT_REFUSAL_REASONS` (five members) and update the CO-MOVING ARTIFACTS comment block.

## Phase 2 - GREEN, model contract

- 2.1 Drop `proposed_diff_unified` and `byte_impact` from `CLUSTER_OUTPUT_SCHEMA`, the `Cluster` type and
  the phase-1 prompt line.
- 2.2 Add `EDIT_OUTPUT_SCHEMA` (`additionalProperties: false` at every object level) and
  `draftAdditiveEdit({ cluster, repoRoot, apiKey, runId, post })` with an injectable `post`; base text
  from `git show HEAD:<path>`; `TARGET_ALLOW_RE` before any git argv; `withTimeout` plus
  `postAnthropicMessage({ timeoutMs, markerSource: "cron-compound-promote", markerRunId })`; verify the
  marker `id` handling in `apps/web-platform/server/claude-cost-marker.ts` first.

## Phase 3 - GREEN, wiring

- 3.1 New `step.run("draft-edit-<hash8>")` before `apply-and-pr-<hash8>`; move the `target-path-refused`
  site into it unchanged; return only `{kind, diff}` or `{kind, reason}`.
- 3.2 Accumulate draft refusals with the existing destructured, outside-the-callback code; `continue`.
- 3.3 Extend the outcome-census reason attribution and the memoized-callback census to the new step.

## Phase 4 - follow-through probe

- 4.1 `scripts/followthroughs/compound-promote-draft-edit-10552.test.sh` first (P-1 to P-6), then
  `compound-promote-draft-edit-10552.sh` modelled on `compound-promote-outcome-8281.sh` (positive control,
  field-isolated decode, xtrace refusal, `FT10552_MERGE_FLOOR` required; exit 0 only on a draft PR or a
  downstream-gate refusal; all-`edit-*` or quiet week exits 2).
- 4.2 Bump `BASELINE_DECLARED_PROBES` 70 -> 71 in `plugins/soleur/test/preflight-discoverability-test.test.ts`
  with the PLACEMENT / TRUTH / NO SUBSTITUTE comment; re-measure against `origin/main` before merge.

## Phase 5 - docs and record

- 5.1 `betterstack-log-query.md`: five new refusal rows and the one-line join recipe.
- 5.2 `compound-promote-runbook.md`: two-step flow, new refusals, what an `edit-*` streak means.
- 5.3 ADR-092 dated Amendment via `soleur:architecture`; confirm C4 unchanged and run
  `bash plugins/soleur/test/c4-count-parity.test.sh`.
- 5.4 Compound learning (topic only; author picks the date): a model asked for line-numbered output over
  a file it was never shown fails in a different mode every week.

## Phase 6 - verify

- 6.1 `cd apps/web-platform && npx vitest run test/server/inngest/cron-compound-promote*.test.ts`.
- 6.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- 6.3 `bash scripts/followthroughs/compound-promote-draft-edit-10552.test.sh`,
  `python3 scripts/lint-guard-contract.py <plan>`, `npx markdownlint-cli2` on touched `.md`.

## Ship notes

- PR body `Ref #10552` (not `Closes`). Label #10552 `follow-through` and add the unfenced column-0
  directive with `earliest` after the 2026-10-25 scheduled run and the three `BETTERSTACK_QUERY_*`
  secrets (verify the sweeper workflow wires them).
- Deferral issues to create at ship: `apply_error_class` marker field (trigger: `diff-underivable-apply`
  appears on a server-derived diff). #8443 and #10551 are already tracked; do not close #8443.
- A manual `trigger-cron` run is optional and needs the operator's authorization for that exact action.
