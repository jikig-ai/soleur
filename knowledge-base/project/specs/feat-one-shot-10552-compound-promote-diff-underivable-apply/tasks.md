# Tasks - fix(compound-promote): every weekly proposal refused diff-underivable-apply (#10552)

Plan: `knowledge-base/project/plans/2026-10-19-fix-compound-promote-diff-underivable-apply-plan.md`
(deepened 2026-10-19; the plan's Test Scenarios, Guard Contract and Approach are authoritative).

Test-first throughout (`cq-write-failing-tests-before`). Read every census suite completely
before editing the handler.

## Phase 0 - RED

- 0.1 Rows T1, T2, T4 in `apps/web-platform/test/server/inngest/cron-compound-promote-allowlist.test.ts`
  (anchor mid-file, append at EOF, SKILL.md and hyphenated-directory paths); each also asserts
  `git apply --cached` and `checkDiffPaths` accept the derived diff and the header is
  `diff --git a/<path> b/<path>`.
- 0.2 Refusal rows: T3, T5, T6, T7 (full charset / length / credential / `---` matrix), T8, T8b, T9,
  T10, T10b (infra fault throws), T11 (model not called), T12, T19, T20, T21, T22.
- 0.3 T14 (M1, M2, M3 fixtures still `underivable-apply` through `checkDiffPaths`).
- 0.4 T15 (handler-level, two clusters, stubbed `post`), T16, T17 in `cron-compound-promote.test.ts`.
- 0.5 Confirm each new row fails for an assertion reason (export stubs that throw, so RED is not an
  import error). Record the output.

## Phase 1 - GREEN, derivation

- 1.1 `buildAdditiveEditDiff` above the handler: pre-call git reads (`ls-tree` mode 100644,
  `cat-file -s`, `show HEAD:`), base preconditions (trailing LF, no CR), `TARGET_ALLOW_RE`
  re-assertion, `new_lines` validation (printable ASCII, caps, credential shape, `---`),
  target-specific shape (`AGENTS.rules.md` rule bullets with non-`hr-` unused ids; SKILL.md anchor
  after frontmatter and outside fences), unique-anchor check, splice, `git diff --no-index --no-color
  --no-prefix --no-ext-diff --no-textconv -- a/<path> b/<path>` via `spawnGitCapture` in a
  `mkdtemp(tmpdir())` dir (exit 1 is success), additivity assertion; never throws after the model
  has answered.
- 1.2 Export `EDIT_REFUSAL_REASONS` (seven members) and update the CO-MOVING ARTIFACTS comment block.

## Phase 2 - GREEN, model contract

- 2.1 Drop `proposed_diff_unified` and `byte_impact` from `CLUSTER_OUTPUT_SCHEMA`, the `Cluster` type and
  the phase-1 prompt; add the eligible-target list with sizes to the phase-1 prompt.
- 2.2 `EDIT_OUTPUT_SCHEMA` (`additionalProperties: false` at every object level) and
  `draftAdditiveEdit({ cluster, repoRoot, apiKey, runId, post })` with an injectable `post`;
  delimited data blocks; `Map` lookup for source learnings; `DRAFT_EDIT_TIMEOUT_MS` (120_000) and
  `DRAFT_EDIT_MAX_TOKENS` (4_096) passed to `postAnthropicMessage`; `markerSource:
  "cron-compound-promote"` with the run's `runId` UNCHANGED.

## Phase 3 - GREEN, wiring

- 3.1 `step.run("draft-edit-<hash8>")` before `apply-and-pr-<hash8>`, returning `DraftOutcome`
  (its own type); move `target-path-refused` into it AND keep the check in the apply step;
  `MAX_DIFF_BYTES` stays in the apply step.
- 3.2 One `record(hash, outcome)` helper in the handler body (outside every step callback) shared by
  draft and apply refusals; a refused draft skips the apply step; `edit-target-duplicate` for a
  repeated target.
- 3.3 Census: AST census over the seven edit reasons, a second Guard 3 window for the draft
  callback (forbid accumulator mutation inside it), allowlist-site count of two. Do not add edit
  reasons to `DiffPathVerdict`.

## Phase 4 - follow-through probe

- 4.1 `scripts/followthroughs/compound-promote-draft-edit-10552.test.sh` first (P-1 to P-10), then
  `compound-promote-draft-edit-10552.sh` modelled on `compound-promote-outcome-8281.sh`: positive
  control, field-isolated decode graded inside `jq`, xtrace refusal, `FT10552_DEPLOY_FLOOR`
  required (exit 3 if unset), PASS only from the class-P allowlist (stdout literal `PASS`), F
  class exits 1, N class exits 2, exit 5 after 35 days, only closed-enum reasons printed.
- 4.2 Bump `BASELINE_DECLARED_PROBES` 70 -> 71 in `plugins/soleur/test/preflight-discoverability-test.test.ts`
  with the PLACEMENT / TRUTH / NO SUBSTITUTE comment; re-measure against `origin/main` before merge.

## Phase 5 - docs and record

- 5.1 `betterstack-log-query.md`: seven new refusal rows and the one-line join recipe.
- 5.2 `compound-promote-runbook.md`: two-step flow, refusals, what an `edit-*` streak and
  `skill-conflict-guard` streak mean, `edit-derive-failed` vs `diff-underivable-apply`.
- 5.3 ADR-092 dated Amendment via `soleur:architecture` (rule-set vs line-level additivity,
  compensating controls, reconcile the deferred-C4 bullet); run `bash plugins/soleur/test/c4-count-parity.test.sh`.
- 5.4 Compound learning (topic only; author picks the date): a model asked for line-numbered output
  over a file it was never shown fails in a different mode every week.

## Phase 6 - verify

- 6.1 `cd apps/web-platform && npx vitest run test/server/inngest/cron-compound-promote*.test.ts`.
- 6.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- 6.3 `bash scripts/followthroughs/compound-promote-draft-edit-10552.test.sh`,
  `python3 scripts/lint-guard-contract.py <plan>`, `npx markdownlint-cli2` on touched `.md`.
- 6.4 Real-model evidence run of `draftAdditiveEdit` against five real targets with a dev key (or
  record "not run: no dev key"); put the anchor hit-rate and refusal causes in the PR body.

## Ship notes

- PR body `Ref #10552` (not `Closes`). Label #10552 `follow-through` and add the unfenced column-0
  directive: floor = deploy completion time of the merged change, `earliest` = one day after the first
  scheduled fire that follows the deploy, the three `BETTERSTACK_QUERY_*` secrets (already wired).
- Deferral issues to create at ship: `apply_error_class` marker field (trigger: `diff-underivable-apply`
  on a derived diff); move the skill-conflict open-PR check ahead of the draft step and reconsider
  the diff comment; validate `source_learnings` against the corpus at the phase-1 parse (pre-existing
  trailer / table-row forging). #8443 and #10551 are already tracked; do not close #8443.
- A manual `trigger-cron` run is optional and needs the operator's authorization for that exact action.
