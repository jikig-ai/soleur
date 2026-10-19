---
title: "fix(compound-promote): every weekly proposal refused diff-underivable-apply, zero PRs opened"
date: 2026-10-19
slug: fix-compound-promote-diff-underivable-apply
branch: feat-one-shot-10552-compound-promote-diff-underivable-apply
issue: 10552
closes: 10552
type: fix
lane: cross-domain
priority: P2
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
---

> Spec lacks valid `lane:` (no `spec.md` exists for this one-shot branch) - defaulted to
> `cross-domain` (fail-closed).

## Overview

The weekly `cron-compound-promote` run has proposed two clusters on every scheduled run since
2026-09-27 and opened no pull request. Every proposal is refused `diff-underivable-apply`, the
`git apply --cached` arm of `checkDiffPaths`. The loop has opened no draft PR since it was
enabled on 2026-07-06.

The cause is **not** a bug in `checkDiffPaths` and it is **not** one of the three "likely
candidates" in the brief (empty diff, markdown fence, headers with no hunk) taken alone. The
recorded rows show three *different* malformed-diff modes in three consecutive weeks, and the
prompt explains why: the model is asked for a line-numbered unified diff against a file it has
never been shown, with no format instruction. The fix removes the model from the diff-authoring
step entirely: the model proposes a structured additive insertion against the real file text, and
the server derives the unified diff itself, so everything downstream runs unchanged on a diff that
is valid by construction.

Technical design was ruled by the CTO agent (see `## Technical Rulings`); no operator question is
open.

## Attribution (evidence, pulled without operator involvement)

Source: Better Stack Logs source 2457081 via `doppler run -p soleur -c prd_terraform --
scripts/betterstack-query.sh` (hot window and archive arm), 2026-10-19. Two row families joined on
`cluster_hash`: the `SOLEUR_COMPOUND_PROMOTE_OUTCOME` marker (`refusal_detail[]`, shape fields) and
the pino `diff-path-refused` row that `reportSilentFallback` mirrors (carries git's first 200
characters of stderr as `detail`; this row, not the marker, is what discriminates the mode).

| Run (UTC) | Trigger | Shape (`header_pair` / `hunk` / `fenced`, `diff_len`) | git stderr (`detail`) | Mode |
|---|---|---|---|---|
| 2026-09-20 05:41 | manual | pre-#8428, no shape recorded | `No valid patches in input` | (unclassifiable) |
| 2026-09-24 01:27 | manual | true / **false** / false, 489 and 1095 | `No valid patches in input` | **M1** headers, no `@@` hunk |
| 2026-09-27 00:02 | cron | true / **false** / false, 586 and 1115 | `No valid patches in input` | **M1** |
| 2026-10-04 00:01 | cron | true / true / false, 944 and 939 | `corrupt patch at line 14` (both) | **M2** hunk header counts disagree with the body |
| 2026-10-11 00:01 | cron | true / true / false, 1034 and 803 | `No valid patches in input` | **M3** hunk present but not a parseable header |
| 2026-10-18 00:00 | cron | n/a | n/a | `no-qualifying-clusters` (`clusters_proposed: 0`) |

Local reproduction on git 2.56.0 (`git apply --cached` on a throwaway index; fixtures synthesized,
no production diff text exists to copy - the marker is shape-only by design):

| Input shape | git result | Maps to |
|---|---|---|
| `---`/`+++` then `+`/`-`/context lines, no `@@` | `No valid patches in input` | M1 |
| `@@ -3,5 +3,6 @@` count larger than the body | `corrupt patch at <stdin>:7` | M2 |
| `@@ -3,1 +3,1 @@` count smaller than the body | `corrupt patch at <stdin>:5` | M2 |
| `@@ section @@` (no `-N,M +N,M`) | `No valid patches in input` | M3 (passes the shape field's hunk-header regex, git rejects it) |
| `@@ 3,2 +3,3 @@` (no leading `-`) | `No valid patches in input` | M3 |
| well-formed hunk, wrong context line | `patch failed ... does not apply` | would be the NEXT failure (`git-apply-check-failed`) |
| blank line between `+++` and `@@` | `patch fragment without header` | a fourth shape, not observed |
| `git apply --recount` on M2 | applies (rc 0) | `--recount` repairs M2 only |

**Why a single-mode patch does not work.** The three modes are three different ways a model fails
to hand-write what it cannot see. The prompt (`cron-compound-promote.ts`, the `anthropic-cluster`
step) passes the first 10 lines of each of ~2,700 learnings and the *byte count* of the always-loaded
payload; it never passes `AGENTS.rules.md` or any `SKILL.md`, never states a diff format, and the
schema declares `proposed_diff_unified` as a bare `{ type: "string" }`. A hunk header needs real line
numbers and a hunk body needs real context lines, so even a mode-clean diff would fail the next
gate. A per-mode repair (`--recount` for M2, a header normaliser for M3, a hunk synthesiser for M1)
is a denylist over a string the model writes - the shape ADR-211 rejects - and it still cannot make
context lines match a file the model has not seen.

**Does the recorded shape discriminate?** It does not discriminate M2 from M3 (both are
`header_pair: true, hunk: true`); only git's stderr does, and that is deliberately not on the marker
(#8427 removed the free-text field). The brief says to add the missing field "rather than guessing".
The CTO ruling (F2) is that the field is **not** added: after this change none of M1-M3 can reach
`diff-underivable-apply` at all - they become unreachable, and the remaining failures are distinct
named refusals - so a git-stderr classifier would diagnose a class the fix removes. If
`diff-underivable-apply` ever fires on a server-derived diff, that is a server bug, goes to Sentry,
and the classifier is added then (recorded in `decision-challenges.md`).

## Premise Validation (Phase 0.6)

- **#10552**: open, no closing PR. **#8443**: open decision-challenge (read, left untouched).
  **#8428**: merged 2026-09-20 (its marker fields are what made this attribution possible).
- **Cited symbols on `origin/main`**: `checkDiffPaths`, `diffShape`, `ClusterOutcome`,
  `RefusalDetailEntry`, `emitOutcomeMarker` all present at the cited sites in
  `apps/web-platform/server/inngest/functions/cron-compound-promote.ts` and
  `apps/web-platform/server/compound-promote-marker.ts`. `scripts/betterstack-query.sh` present.
- **Stale premise in the brief**: "likely candidates: empty/whitespace diff, markdown-fenced diff,
  headers with no hunk". Measured: no recorded row is empty (`diff_len` 489-1115), none is fenced,
  and only M1 is "headers with no hunk". The brief's own fallback ("add the missing shape field")
  was evaluated and ruled out (above).
- **Brief premise "git's stderr is `No valid patches` identically for ... headers with no hunk"** -
  true, but incomplete: M2 emits `corrupt patch`, a different string, which the issue body did not
  anticipate.
- **ADR corpus (mechanism vs rejected alternatives)**: ADR-092 (additive-only auto-edit boundary),
  ADR-054 (`safeCommitAndPr` sole write path), ADR-108 (cost markers), ADR-211 (a denylist over
  model-written text is the rejected shape). No ADR rejects structured-edit / server-derived
  diffs; ADR-092 is *strengthened* by it (additive-only becomes structural).
- **Own capability claim**: "`git diff --no-index` yields apply-ready headers" was checked, not
  assumed, and the obvious form is wrong - see Research Insights (header trap).

## Property List and Cut List (Phase 0.6b)

**Properties the fix must buy**

1. A proposal that reaches `checkDiffPaths` is a diff git can parse and apply by construction.
2. A failure in the proposal path is attributable from one marker row, with no SSH and no second
   query, to a closed named reason - not to a catch-all.
3. ADR-092's additive-only property holds structurally, not only by the post-hoc shrink floor.
4. Every existing downstream gate (path allowlist, hard-rule removal, byte budget, shrink floor,
   `safeCommitAndPr`) is unchanged in meaning.
5. The next scheduled run is verifiable as fixed or as failing for a *named* new cause, without an
   operator-authorised production write.

**Cut list** (mechanism -> property -> what already covers it)

- `git apply --recount` / hunk-header normaliser -> property 1 -> covered by server-derived diffs;
  repairs one of three modes and leaves the context-mismatch failure.
- New `apply_error_class` marker field -> property 2 -> covered by the new named refusals (CTO F2).
- Collapsing `diff_*` into a `diff_kind` enum (#8443 UC-1) -> out of scope; operator-reserved
  telemetry-schema decision, #8443 stays open.
- Manual `trigger-cron` as a plan step -> property 5 -> covered by test-first + follow-through
  probe; a manual run is an operator-authorised production write (CTO F4).
- Restricting `target_path` to `AGENTS.rules.md` -> scope reduction, a product decision.
- Dry-run flag -> new code path for a verification the follow-through already provides.

## Technical Rulings

All four forks were delegated to `soleur:engineering:cto` (no AskUserQuestion). Full rows also in
`knowledge-base/project/specs/feat-one-shot-10552-compound-promote-diff-underivable-apply/decision-challenges.md`.

- **F1 fix design** - Ruled by CTO agent, 2026-10-19: Option B, two-step. Phase 1 keeps clustering
  and picks `tier` / `target_path` and drops `proposed_diff_unified` and `byte_impact` from its
  schema and prompt. Phase 2 is a per-cluster Anthropic call shown the target file (`git show
  HEAD:<path>`) that returns `{insert_after_line, new_lines}`; the server validates the anchor and
  derives the unified diff with git. `proposed_diff_unified` stays as a *server-derived* field so
  every downstream gate is byte-for-byte unchanged. Rejected: A (`--recount` + prompt; the SKILL.md
  target is not known before the call), C (restrict targets; scope cut), server-side "repair".
- **F2 observability** - Ruled by CTO agent, 2026-10-19: neither a git-stderr classifier nor
  #8443 UC-1; the marker field set is unchanged; #8443 untouched. Update the CO-MOVING ARTIFACTS set
  for the new reasons only.
- **F3 ADR/C4** - Ruled by CTO agent, 2026-10-19: amend ADR-092 with a dated Amendment paragraph
  (who authors the diff); no new ADR; no C4 change.
- **F4 verification** - Ruled by CTO agent, 2026-10-19: tests in a real throwaway git repo plus a
  post-merge follow-through probe keyed on the next scheduled run; no manual trigger in the plan.
- **Plan-time correction to F1 (measured, not a new fork).** The CTO sized the SKILL.md input at
  "at most about 104 KB". Measured: `plugins/soleur/skills/review/SKILL.md` is 475,873 bytes,
  `work` 359,121, `ship` 273,067; 4 of 104 exceed 120,000 bytes. The plan therefore adds a named
  `edit-target-too-large` refusal at 120,000 bytes (the cap is a plan parameter, not a new design
  fork). The largest files are already the subject of #10551 (shorten the largest SKILL.md files
  into PURPOSE.md); this plan acknowledges that overlap and does not widen into it.

## Research Insights

**Local research**

- `apps/web-platform/server/inngest/functions/cron-compound-promote.ts` - `anthropic-cluster` step
  builds the prompt; `CLUSTER_OUTPUT_SCHEMA`; `checkDiffPaths`; `applyDiffToWorkspace`
  (`--check` then real `git apply`); per-cluster `step.run("apply-and-pr-<hash8>")` returning a
  `ClusterOutcome`; `refusalDetail.push` outside the memoized callback (Guard 3 of the census suite
  pins this). `MAX_DIFF_BYTES = 16384`, `WEEK_CAP_DEFAULT = 2`, `PROPOSE_ALWAYS_LOADED_BUDGET =
  44000`, `MAX_ALWAYS_LOADED_BYTES = 46000`; `AGENTS.rules.md` is 39,160 bytes today.
- `apps/web-platform/server/compound-promote-marker.ts` - `RefusalDetailEntry` is
  `{cluster_hash, reason, diff_len?, diff_fenced?, diff_header_pair?, diff_hunk?}`; `reason` is a
  free `string` in the type, so new reasons need no marker change.
- `apps/web-platform/server/inngest/functions/_cron-shared.ts` `postAnthropicMessage` - takes
  `timeoutMs`, `outputConfig`, `markerSource`, `markerRunId`; emits one `cron:<markerSource>`
  `SOLEUR_CLAUDE_COST` marker per ok response.
- Test seams: `apps/web-platform/test/server/inngest/cron-compound-promote-allowlist.test.ts` (real
  throwaway git repos, `expect.hasAssertions()` floor), `...-outcome-census.test.ts` (AST/regex
  censuses: terminal returns, reason attribution of `checkDiffPaths`, Guard 3 replay safety),
  `...-outcome-marker.test.ts`. Baseline on this branch: 3 files, 78 tests, all pass.
- Follow-through precedent: `scripts/followthroughs/compound-promote-outcome-8281.sh` (+ `.test.sh`)
  already reads this exact marker with a positive control, field-isolated decode, and the exit
  vocabulary (0 PASS, 1 FAIL, 2 NOT YET, 3 CANNOT ESTABLISH, 78 xtrace refusal).
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` - refusal-enum table
  (the 6-row `diff-underivable-*` table) and the marker field list; the runbook is a co-moving
  artifact named in the source's comment block. `compound-promote-runbook.md` - operator runbook.
- Open code-review overlap: none (queried `--label code-review` for the five touched paths).

**Institutional learnings applied**

- `security-issues/2026-09-18-my-fix-for-the-allowlist-bypass-shipped-a-second-bypass.md` - authority is apply to a
  throwaway index and read `diff-index`, never a report format. The derived diff still goes through
  that authority unchanged.
- `security-issues/2026-09-20-my-sink-control-was-a-denylist-over-a-string-the-model-writes.md` - keep marker
  fields enumerated; the new reasons are a closed set chosen by our code.
- `2026-09-18-the-loop-was-not-failing-it-was-succeeding-at-nothing-and-said-ok.md` - a heartbeat
  proves liveness not work; the follow-through must not pass on silence.
- `2026-05-11-compound-promotion-loop-multi-agent-review-trust-models.md` - the workflow must
  re-derive every gating value itself; the server-derived diff is the same principle applied to
  the diff.
- `2026-10-12-the-guards-own-normalizer-is-attack-surface-treat-text-preprocessing-as-fail-open.md`
  - rejected "repair" preprocessing for exactly this reason.
- `2026-07-19-a-mutation-battery-that-passes-can-still-leave-the-central-mechanism-untestable.md`
  - the test battery needs a fixture per shape the fix introduces.
- No prior learning covers `corrupt patch` / `No valid patches` / hunk-count failure; a compound
  learning is a work-phase deliverable.

**Measured gotchas (for the implementer)**

1. **`git diff --no-index` header trap.** The obvious derivation - files at `a/<path>` and
   `b/<path>` in a temp dir, `git diff --no-index a/<path> b/<path>` - emits `diff --git
   a/a/<path> b/b/<path>`; `git apply` (default `-p1`) then reports `a/<path>: does not exist in
   index`. Measured on git 2.56.0. The working form is `git diff --no-index --no-color --no-prefix
   -- a/<path> b/<path>` run with the temp dir as cwd: it emits `diff --git a/<path> b/<path>`,
   `--- a/<path>`, `+++ b/<path>`, and `git apply --cached` accepts it. `git diff --no-index`
   exits 1 when the files differ - that is the success code, not an error. Run it through
   `spawnGitCapture` (strips every inherited `GIT_*` key, sets `GIT_CONFIG_NOSYSTEM` and
   `GIT_CONFIG_GLOBAL=/dev/null`).
2. **Phase-2 base text is `git show HEAD:<path>`**, not the working tree: `checkDiffPaths` applies
   against a throwaway index populated by `read-tree HEAD`, so HEAD is the base the derived diff
   must apply to. The target allowlist (`TARGET_ALLOW_RE`) must be checked **before** the path is
   put in any git argv.
3. **Cost markers.** `postAnthropicMessage` derives the marker `source` from `markerSource` and the
   `id` from `markerRunId`. Keep `markerSource: "cron-compound-promote"` (so per-cron spend sums
   are unchanged) and pass a distinct `markerRunId` per phase-2 call; verify against
   `apps/web-platform/server/claude-cost-marker.ts` and ADR-108 before relying on this.
4. **Inngest step state.** A `step.run` return value is persisted. The phase-2 step returns the
   derived diff (<= 16,384 bytes by the existing cap) or a closed refusal reason - never the target
   file text.
5. **In-flight runs across the deploy.** The `anthropic-cluster` step's memoized return changes
   shape (clusters no longer carry `proposed_diff_unified` / `byte_impact`). A run memoized under
   the old code that resumes on the new code reads only the fields both shapes share
   (`cluster_hash`, `tier`, `target_path`, `source_learnings`, `rationale`), then hits the new
   `draft-edit-<hash8>` step (a new id, so never memoized) - the new reader is tolerant by
   construction (unused fields are ignored by default). The run is weekly and minutes long, so
   the window is small and no dedicated test row is spent on it.
6. **Op-slug consumers.** `git grep` over `apps/web-platform/infra/sentry/` finds no alert that
   filters on the `target-path-refused` / `diff-path-refused` ops (the only hit is a comment in
   `cron-monitors.tf`), so relocating the `target-path-refused` emit site darks no monitor.

## Approach

### Contract

- `CLUSTER_OUTPUT_SCHEMA` (phase 1) loses `proposed_diff_unified` and `byte_impact` (the model
  cannot compute either). It keeps `cluster_hash`, `tier`, `target_path`, `source_learnings`,
  `rationale`. The prompt line naming `proposed_diff_unified` and `byte_impact` goes with them.
- New `EDIT_OUTPUT_SCHEMA` (phase 2), `additionalProperties: false`, required
  `insert_after_line` (string) and `new_lines` (array of string). `insert_after_line === ""` means
  "append at end of file".
- Phase 2 prompt carries: the cluster `rationale`, the source-learning summaries for **that
  cluster's** `source_learnings` only (taken from the already-collected corpus entries, not a new
  read), the full target text from `git show HEAD:<target_path>`, the current always-loaded byte
  headroom for `AGENTS.rules.md` targets, and the additive contract in words ("append new lines
  only; never restate, edit or delete an existing line; `insert_after_line` must be copied
  verbatim from the file and appear exactly once").
- `proposed_diff_unified` becomes a server-derived value with the same name and meaning, so
  `checkDiffPaths`, `diffRemovesHardRule`, the `MAX_DIFF_BYTES` check, the PII-redaction branch of
  the skill-conflict comment, `applyDiffToWorkspace`, the byte budget and the shrink floor read it
  unchanged.

### Server-side derivation (`buildAdditiveEditDiff`)

Pure except for one git call, exported for tests:

0. **Base preconditions.** The base must end with `\n` and contain no `\r`; otherwise
   `edit-target-unreadable`. Measured on this tree: all 105 allowlisted targets
   (`AGENTS.rules.md` and 104 `SKILL.md`) end with LF and none contains CR, so this refuses
   nothing today. It exists because the alternative is wrong, not merely rare: appending to a
   base with no trailing newline rewrites the last line (reproduced: `-two`, `\ No newline at
   end of file`, `+two`, `+three`), so the diff is not additive and step 5 would fire.
1. Validate `new_lines`: a non-empty array; every element a string with no `\n` or `\r`; at least
   one element non-blank. Else `edit-invalid` (empty, blank, wrong type, embedded newline, or a
   `max_tokens` stop).
2. Split the base on `\n`. `insert_after_line === ""` -> append at end of file; otherwise count
   exact-equal lines: 0 -> `edit-anchor-not-found`, >1 -> `edit-anchor-ambiguous`. (A text anchor
   rather than a returned line number is deliberate: it is self-verifying - a wrong copy refuses
   - whereas an off-by-one number lands in the wrong place silently.)
3. Splice the new lines after the anchor (or at the end).
4. Write base and new text to `<tmp>/a/<path>` and `<tmp>/b/<path>`, run the `--no-prefix` form
   above, clean the temp dir in `finally`. (Deriving the hunk by hand was considered and rejected:
   hand-computed hunk counts are the failure class this plan removes.)
5. **Assert additivity in code**: every content line of the derived diff after the first hunk
   header starts with `+` or a space, never `-`. Splicing inserts only, so a `-` line is a server
   bug, not a model fault: it is NOT mapped to an `edit-*` reason. The draft step returns the
   retained `diff-underivable-apply` refusal and mirrors a `draft-edit-nonadditive` event to
   Sentry. `diffRemovesHardRule` and the shrink floor stay as defence in depth.

### Handler wiring

Per cluster, a new `step.run("draft-edit-<hash8>")` runs **before** the existing
`apply-and-pr-<hash8>` step and returns `{ kind: "drafted", diff } | { kind: "refused", reason }`.
It owns the `TARGET_ALLOW_RE` check (the existing `target-path-refused` site moves into it, with
its logging and Sentry call unchanged, because the allowlist must precede any `git show`), the
size check, the model call (wrapped in `withTimeout` and `postAnthropicMessage({ timeoutMs })`),
and `buildAdditiveEditDiff`. A `refused` draft is accumulated by the same code that accumulates
`apply-and-pr` refusals (outside the memoized callback, destructured, never spread) and the loop
`continue`s. The apply step receives the derived diff and is otherwise unchanged. An Anthropic API
error is **not** swallowed: it throws exactly as phase 1 does (transient retry; a 400 credit
exhaustion lands the run as `status: "error"` with `error_class`, as on 2026-09-19).

### Closed reason set (new refusals)

Five: `edit-target-unreadable` (path absent at HEAD, `git show` failed, no trailing LF, or
contains CR), `edit-target-too-large` (> 120,000 bytes; about 30k tokens, comfortably inside the
model's context, and 4 of 104 SKILL.md files exceed it), `edit-invalid` (JSON/shape/empty/blank/
embedded newline/`max_tokens` stop), `edit-anchor-not-found`, `edit-anchor-ambiguous`.
`diff-underivable-apply` is retained for the residual case and is now a server-bug signal.

Known consequence, stated here rather than only in Sharp Edges: the largest and most-edited
skills (`review`, `work`, `ship`) are unreachable by this loop until #10551 shortens them; the
cron will name that refusal each time a cluster targets one.

Verified, not assumed: nothing downstream reads the model's `byte_impact` (`git grep` shows it
only in the schema, the `Cluster` type and the prompt line), so dropping it from the phase-1
schema changes no gate's meaning; the byte budget and shrink floor measure the applied tree.

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-compound-promote.ts` - phase-1 schema and
  prompt, `EDIT_OUTPUT_SCHEMA`, `EDIT_REFUSAL_REASONS`, `buildAdditiveEditDiff`,
  `draftAdditiveEdit` (injectable `post`), handler wiring, `Cluster` type split, comment block
  "CO-MOVING ARTIFACTS" updated for the new reasons, the `diffShape` comment's "reason this
  record exists" paragraph (it now records the residual case).
- `apps/web-platform/test/server/inngest/cron-compound-promote-allowlist.test.ts` - new rows (see
  Test Scenarios); keep every existing row (they exercise `checkDiffPaths` directly and still
  hold).
- `apps/web-platform/test/server/inngest/cron-compound-promote-outcome-census.test.ts` - read it
  fully first; extend the reason-attribution census to the new edit reasons and the Guard 3
  "every exit of the memoized callback returns ..." census to the new draft step.
- `apps/web-platform/test/server/inngest/cron-compound-promote.test.ts` - schema/constant rows
  (no `proposed_diff_unified` / `byte_impact` in the phase-1 schema; `EDIT_OUTPUT_SCHEMA` shape).
- `plugins/soleur/test/preflight-discoverability-test.test.ts` - bump `BASELINE_DECLARED_PROBES` 70 -> 71 with the PLACEMENT / TRUTH / NO SUBSTITUTE comment (this plan declares `credentials_required`; the G1 ratchet counts declaring plans repo-wide). Re-measure against `origin/main` immediately before merge: a sibling plan landing first moves the number.
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` - extend the refusal
  enum table with the five new reasons and one line naming the join used for this attribution
  (marker row to the `diff-path-refused` pino row on `cluster_hash`).
- `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md` - describe the
  two-step flow, the new refusals, and what an `edit-*` streak means.
- `knowledge-base/engineering/architecture/decisions/ADR-092-additive-only-auto-edit-boundary-and-hard-rule-body-weakening-gate.md`
  - dated Amendment (via `soleur:architecture`).

## Files to Create

- `scripts/followthroughs/compound-promote-draft-edit-10552.sh` and
  `scripts/followthroughs/compound-promote-draft-edit-10552.test.sh` - the verification probe and
  its suite (modelled on the 8281 pair).
- `knowledge-base/project/learnings/2026-10-19-<slug>.md` - work-phase compound learning: a model
  asked for line-numbered output over a file it was never shown fails in a different mode every
  week; fix the contract, not the mode.
- `knowledge-base/project/specs/feat-one-shot-10552-compound-promote-diff-underivable-apply/tasks.md`
  and `.../decision-challenges.md` (this planning phase).

No `.tf`, migration, workflow, or UI file is touched. Globs verified: every path above was
confirmed with `git ls-files` or is a new path under an existing directory.

## Implementation Phases (test-first)

**Phase 0 - RED.** Write the tests below and confirm each fails for the right reason before any
production edit: `buildAdditiveEditDiff` / `draftAdditiveEdit` do not exist (import failures are
not RED - add a `typeof` guard row or stub the export to throw so RED is an assertion failure, per
the "failure for the right reason" discipline). The handler-level RED is the regression for the
reported bug: with phase-1 stubbed to return a cluster and phase-2 stubbed to return a valid edit,
the cluster must reach the apply step and must not produce `diff-underivable-apply`.

**Phase 1 - GREEN, derivation.** `buildAdditiveEditDiff` and its closed reasons.

**Phase 2 - GREEN, model contract.** Phase-1 schema/prompt trim, `EDIT_OUTPUT_SCHEMA`,
`draftAdditiveEdit` with an injectable `post`.

**Phase 3 - GREEN, wiring.** `draft-edit-<hash8>` step, `target-path-refused` relocation, shared
accumulation, `continue` on refused.

**Phase 4 - probe.** The follow-through script and suite.

**Phase 5 - docs and record.** Runbook rows, ADR-092 Amendment, the compound learning, comment
blocks.

**Phase 6 - verify.** The four vitest files, `plugins/soleur/test/c4-count-parity.test.sh`, the
probe suite, `tsc --noEmit`, `python3 scripts/lint-guard-contract.py` on this plan, markdownlint on
touched `.md`.

At ship: open the PR with `Ref #10552` (not `Closes`: the acceptance criterion is verified by a
future scheduled run, so the follow-through closes the issue), label #10552 `follow-through`, and
add the unfenced column-0 directive to its body with `earliest=2026-10-26T00:30:00Z`
(the first `0 0 * * 0` fire after merge is 2026-10-25) and the three `BETTERSTACK_QUERY_*`
secrets, which `.github/workflows/scheduled-followthrough-sweeper.yml` already wires for the 8281
probe (verify, do not assume).

## Test Scenarios

Real throwaway git repos (the existing fixture pattern); every test asserts at least once.

| # | Scenario | Expected |
|---|---|---|
| T1 | Anchor in the middle of `AGENTS.rules.md`, two new lines | derived diff has `diff --git a/AGENTS.rules.md b/AGENTS.rules.md`, only `+` content lines; `checkDiffPaths` returns `ok: true, paths: ["AGENTS.rules.md"]` |
| T2 | `insert_after_line: ""` (append) on a file with a trailing newline | applies; additive only |
| T3 | Base with NO trailing newline | `edit-target-unreadable` (and a note in the row that appending would rewrite the last line) |
| T4 | Same on a `plugins/soleur/skills/alpha/SKILL.md` path | applies; header uses the full repo path (no `a/a/` doubling) |
| T5 | Anchor absent | `edit-anchor-not-found` |
| T6 | Anchor line occurs twice | `edit-anchor-ambiguous` |
| T7 | `new_lines: []`, `[""]`, `["   "]`, or an element containing `\n` | `edit-invalid` |
| T9 | Base containing `\r` | `edit-target-unreadable` |
| T10 | Target missing at HEAD | `edit-target-unreadable` |
| T11 | Base over 120,000 bytes | `edit-target-too-large`, and the model is NOT called |
| T12 | `TARGET_ALLOW_RE` violation | `target-path-refused`, no `git show`, model NOT called |
| T14 | Replays M1, M2, M3 fixtures through `checkDiffPaths` directly | still `underivable-apply` (pins that the guard is unchanged) |
| T15 | Handler-level: phase-1 stub + phase-2 stub | cluster reaches the apply step; marker `refusals` has no `diff-underivable-apply` |
| T16 | Phase-2 `post` throws an Anthropic API error | propagates (not a refusal) |
| T17 | Schema constants | phase-1 schema lacks `proposed_diff_unified` and `byte_impact`; `EDIT_OUTPUT_SCHEMA` has `additionalProperties: false` at every object level |
| T18 | Probe suite (`.test.sh`) | see Guard 2 |

## Guard Contract

### Guard 1 - additive derivation chokepoint

**Property.** No proposal reaches `checkDiffPaths` or `applyDiffToWorkspace` unless the server
derived its diff from the real HEAD text of an allowlisted target and that diff removes no existing
line.

**Assembly.** The members are not "the call sites that exist today" but every path by which a diff
string can reach the gates: (a) the `proposed_diff_unified` read in `checkDiffPaths`, the
`MAX_DIFF_BYTES` check, `diffRemovesHardRule`, the PII branch of the skill-conflict comment and
`applyDiffToWorkspace`; (b) the phase-1 `CLUSTER_OUTPUT_SCHEMA` and prompt, which must no longer
offer the model a diff field; (c) the `Cluster` TypeScript type; (d) any future caller. The
chokepoint is the single exported function `buildAdditiveEditDiff`: the handler must assign
`proposed_diff_unified` only from its return value, and the census below proves no other
assignment or schema property of that name exists.

**Mutation matrix**

| # | Edit | Must go RED in |
|---|---|---|
| M-1 | Re-add `proposed_diff_unified` to `CLUSTER_OUTPUT_SCHEMA` | T17 (schema census) |
| M-2 | Make the splice replace the anchor line instead of inserting after it | additivity assertion (unit row) and the T1 `checkDiffPaths` row |
| M-3 | Assign `proposed_diff_unified` from the model response in the handler | handler-level census (no assignment other than from the builder) |
| M-4 | Drop the `--no-prefix` flag | T1, T4 (header doubles to `a/a/...`, `checkDiffPaths` refuses) |
| M-5 | Skip the `TARGET_ALLOW_RE` check before `git show` | T12 |
| M-6 | Make the anchor check `>= 1` instead of `=== 1` | T6 |
| M-7 | After a compliant first cluster, a second cluster's draft is skipped, or a draft step returns without calling the builder | T15 with TWO clusters (must observe a derived diff for each, not an absence of refusals) |

**Harness rows.** (i) Delete every `expect` in the new rows -> the `expect.hasAssertions()` floor
reddens. (ii) Must-PASS non-canonical inputs: a SKILL.md target with a hyphenated directory
(`agent-browser`), an anchor on the first line, an anchor on the last line, and a base with a
trailing blank line - none is the canonical happy-path fixture, each differs in a way the contract
permits.

**Anchor.** The guard compares no stored value; there is no hash, manifest row or count floor to
weaken. It quantifies over the schema and the type, which the census reads from source.

### Guard 2 - the follow-through probe does not pass on silence

**Property.** The probe exits 0 only when a run after the fix shows a draft PR opened, or a
cluster that got PAST the draft step and was refused by a downstream gate (any named reason that
is neither `diff-underivable-apply` nor an `edit-*` model-side reason): the original defect - a
proposal that cannot reach the gates - is then demonstrably gone. A quiet week, a dark channel, a
repeat of the old refusal, or a week of only `edit-anchor-*` / `edit-invalid` / `edit-target-*`
refusals must never exit 0.

**Assembly.** Every terminal exit of the script and every row family it reads (positive-control
`SOLEUR_CLAUDE_COST`, the outcome marker); the grading is over decoded, field-isolated rows (`.fn`
and the boolean discriminator), never a substring of `raw`, because PR and issue bodies that quote
the marker name land in the same source (the 8281 probe documents this echo).

**Mutation matrix**

| # | Edit | Must go RED in |
|---|---|---|
| P-1 | Run window contains only `no-qualifying-clusters` rows | exit 2 (NOT YET), never 0 |
| P-2 | Every refusal is `diff-underivable-apply` | exit 1 (FAIL) |
| P-3 | `clusters_opened >= 1` | exit 0 |
| P-4 | Refusals are all `edit-*` (e.g. `edit-anchor-not-found`) | exit 2 (NOT YET) with the reasons printed - the new path never reached a gate, so nothing is proven |
| P-5 | Refusals include a downstream-gate reason (e.g. `diff-path-off-target`, `byte-budget-overflow`) and no `diff-underivable-*` | exit 0, reasons printed |
| P-6 | Merge floor unset or unparsable, or positive-control rows absent | exit 3 (CANNOT ESTABLISH), never 0 or 1; rows older than the floor are ignored |

**Harness rows.** Strip every assertion from the `.test.sh` -> a non-zero summary floor reddens it;
must-PASS non-canonical: a window with two runs (one downstream-gate refusal, one quiet) and a
manual-trigger row. P-5 and the positive-control / xtrace / floor machinery are inherited from the
8281 probe's construction (copied, not re-derived); only the verdicts above are new.

**Anchor.** The merge floor (`FT10552_MERGE_FLOOR`) is an input the PR author sets; a probe whose
window can be slid earlier by editing that one value would grade pre-fix rows. The floor is set to
the merge timestamp at ship and the suite asserts rows older than the floor are ignored.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_COMPOUND_PROMOTE_OUTCOME marker (status, clusters_proposed, clusters_opened, refusals[], refusal_detail[]) emitted on every terminal path, plus the Sentry cron monitor scheduled-compound-promote
  cadence: weekly, Sunday 00:00 UTC (cron "0 0 * * 0"), plus any manual-trigger run
  alert_target: Sentry monitor scheduled-compound-promote (liveness); the follow-through sweeper comment on #10552 (work)
  configured_in: apps/web-platform/server/inngest/functions/cron-compound-promote.ts (emitOutcomeMarker calls; SENTRY_MONITOR_SLUG) and apps/web-platform/server/compound-promote-marker.ts
error_reporting:
  destination: Sentry web-platform via reportSilentFallback (feature cron-compound-promote; ops draft-edit-refused, diff-path-refused, handler-top-level) and Better Stack Logs via the marker
  fail_loud: a refused cluster logs a warn row and mirrors to Sentry; the marker's refusals[] names the reason; status error carries error_class and error_message
failure_modes:
  - mode: phase-2 anchor does not match the real file (model copied a line inexactly)
    detection: marker refusals[] contains edit-anchor-not-found; Sentry op draft-edit-refused with the reason (layer 2 pino to Sentry breadcrumb mirror, layer 3 Vector to Better Stack)
    alert_route: follow-through probe prints the reasons; Sentry issue via reportSilentFallback
  - mode: anchor line occurs more than once
    detection: marker refusals[] contains edit-anchor-ambiguous (layer 3)
    alert_route: same as above
  - mode: target SKILL.md larger than the 120,000-byte cap
    detection: marker refusals[] contains edit-target-too-large (layer 3); resolves as #10551 shortens the largest SKILL.md files
    alert_route: follow-through probe output
  - mode: a derived diff still fails the apply arm (server bug)
    detection: marker refusals[] contains diff-underivable-apply AND Sentry event with the derived-diff flag (layer 2); the probe exits 1 on this
    alert_route: follow-through sweeper FAIL comment on #10552 plus Sentry
  - mode: Anthropic credit exhausted or API error in phase 2
    detection: run status error with error_class AnthropicApiError; credit exhaustion also fires reportAnthropicCreditExhausted (layer 1 sentry-correlation middleware tags the run)
    alert_route: existing credit-exhaustion route (#8505)
  - mode: quiet week masks a still-broken path
    detection: probe exits 2 NOT YET on no-qualifying-clusters; the tracker stays open
    alert_route: sweeper keeps the issue open and comments daily
logs:
  where: Better Stack Logs source 2457081 (pino WARN to Vector), queried with scripts/betterstack-query.sh under doppler run -p soleur -c prd_terraform
  retention: 90 days in Better Stack; Sentry per project retention
discoverability_test:
  command: bash scripts/followthroughs/compound-promote-draft-edit-10552.sh
  expected_output: PASS or NOT YET
  credentials_required: "doppler soleur/prd_terraform BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD - the warehouse that holds the marker rows has no unauthenticated read, so no credential-free probe verifies the same property"
```

Affected-surface note (Phase 2.9.2, cron worker): every `detection` above is emitted FROM the worker
(the marker and the `reportSilentFallback` mirror), and the five new reasons discriminate the
competing root causes (inexact copy, duplicate line, oversized file, unreadable target, malformed
or empty edit) in one event, which the single `diff-underivable-apply` string could not.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-092** (additive-only auto-edit boundary) with a dated Amendment: the model proposes an
insertion (`insert_after_line`, `new_lines`) against the real HEAD text; the server validates a
unique anchor and derives the unified diff with git; the derived diff is asserted additive in code;
new refusal members `edit-*`; `diffRemovesHardRule` retained as defence in depth. Written via
`soleur:architecture` in Phase 5. No new ADR (ADR-054 write path and ADR-108 cost attribution are
unchanged).

### C4 views

No C4 change. Read all three model files (`model.c4`, `views.c4`, `spec.c4`) and enumerated for
this feature: (a) external human actor - the operator/founder who reviews the draft PR, already
modelled; (b) external systems - `anthropic` (system, modelled; the cron's HTTP call is a second
call to the same system), `github` (modelled), `betterstack` and `sentry` (modelled), `inngest`
(container, modelled); (c) containers/data stores touched - none new (the clone is an ephemeral
directory inside the existing function); (d) actor-to-surface access relationships - unchanged.
Noted, pre-existing and not widened by this change: the generic `api -> anthropic` edge is
described only as the Admin-API cost report, so the cron's own message calls are not named on it.
`plugins/soleur/test/c4-count-parity.test.sh` is green at baseline (ALL TESTS PASSED) and is
re-run in Phase 6.

### Sequencing

The amendment describes the target state and ships in this PR; nothing is deferred to a follow-up
issue.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing. The surface is an internal
weekly self-edit cron that proposes draft PRs against the Soleur repository for the operator to
review; today's failure mode is already "zero PRs", and a regression of the new path lands as a
named refusal row, not a changed rule.

**If this leaks, the user's data is exposed via:** no user data is in the path. The cron reads the
Soleur repository's own learnings and rule files; phase 2 sends one additional public-repo file
(`AGENTS.rules.md` or one `SKILL.md`) per cluster to Anthropic, the same processor that already
receives the corpus summaries. The marker field set is unchanged, so Better Stack (no executed
Art. 28(3) instrument) receives no new field.

**Brand-survival threshold:** none

threshold: none, reason: the touched `apps/web-platform/server/` paths belong to an operator-facing self-healing cron whose outputs are draft PRs gated by human review and by the unchanged path allowlist, byte budget and shrink floor, and no user or tenant data flows through it.

GDPR gate (`soleur:gdpr-gate`) not invoked: no schema, migration, auth flow or API route is
touched; none of the Phase 2.7 (a)-(d) triggers fires (no operator-session-derived data; the
cron's input predates this change and the added input is public repository text; no new artifact
distribution surface). Art. 30 PA-8 is unchanged because the marker field set is unchanged.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** CTO ruled F1-F4 (see `## Technical Rulings`): two-step structured-edit design,
marker unchanged, ADR-092 amendment with no C4 change, follow-through-based verification. One
plan-time correction (SKILL.md sizes) is recorded above.

No UI surface, no user-facing copy, no pricing/legal/marketing implication: Product/UX Gate not
applicable (no `components/**`, `app/**/page.tsx` or `layout.tsx` path in the file lists).

## Open Code-Review Overlap

None. Queried open `code-review` issues for `cron-compound-promote.ts`,
`compound-promote-marker.ts`, `_cron-shared.ts`, `betterstack-log-query.md`, `ADR-092` and
`compound-promote-runbook.md`; no body references any of them.

## Scope Check

| Ask (from the brief) | Plan element |
|---|---|
| Attribute the cause from the recorded diff shape in Better Stack, no operator fetch | `## Attribution` (pulled via `scripts/betterstack-query.sh` under `doppler run -p soleur -c prd_terraform`) |
| Fix with a failing test first | Phase 0 RED, T1-T17 |
| If the shape cannot discriminate, add the missing shape field | Evaluated and ruled out by CTO F2: the shape cannot discriminate M2/M3 but the fix makes the distinction unnecessary; field not added, trigger recorded |
| #8443 is related context, do not close | Read; untouched; cut-listed |

Item provenance: every Files-to-Edit entry is `ask` (the fix and its test) or `required-by-ruling`
(runbook rows and ADR-092 amendment, F3; the probe, F4). Nothing is `inferred`. Split assessment:
one PR; the phases share one chokepoint and splitting phase 1 from phase 2 would ship a state in
which the model has no diff field and nothing derives one.

Deferrals (each needs a tracking issue created at ship, not left as prose): (1) `apply_error_class`
marker field - trigger: `diff-underivable-apply` appears on a server-derived diff; (2) #8443 UC-1
and UC-2 - already tracked by #8443, no new issue; (3) `edit-target-too-large` ceiling - tracked by
#10551.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1. A failing test existed first: the Phase-0 RED commit (or recorded output) shows T1/T15
  failing for an assertion reason before any production edit.
- [ ] AC2. `CLUSTER_OUTPUT_SCHEMA` contains neither `proposed_diff_unified` nor `byte_impact`, and
  the phase-1 prompt text mentions neither (`cron-compound-promote.ts`, `anthropic-cluster` step).
- [ ] AC3. `buildAdditiveEditDiff` is the only code that assigns `proposed_diff_unified`; its
  output for every successful splice (T1, T2, T4) passes `git apply --cached` and
  `checkDiffPaths` inside the same row.
- [ ] AC4. The derived diff header is `diff --git a/<path> b/<path>` (no `a/a/` doubling), and a
  row fails if `--no-prefix` is removed (M-4).
- [ ] AC5. The five `edit-*` reasons each have exactly one emit site and one behavioural row; the
  reason-attribution census covers them; `diff-underivable-apply` is retained and T14 still
  passes.
- [ ] AC6. The `draft-edit-<hash8>` step returns only `{kind, diff}` or `{kind, reason}`; no
  target-file text is in a step return value.
- [ ] AC7. `target-path-refused` still fires before any `git show`, and the model is not called on
  a disallowed path (T12) or an oversized base (T11).
- [ ] AC8. Anthropic API errors in phase 2 propagate (T16); they are not converted into refusals.
- [ ] AC9. The marker field set is unchanged: `git diff --quiet origin/main...HEAD -- apps/web-platform/server/compound-promote-marker.ts` exits 0 (merge-base form, so a sibling merge to main cannot redden it).
- [ ] AC10. The runbook refusal table lists the five new reasons; ADR-092 carries a dated
  Amendment; `plugins/soleur/test/c4-count-parity.test.sh` passes.
- [ ] AC11. `scripts/followthroughs/compound-promote-draft-edit-10552.test.sh` passes and covers
  P-1 through P-6; `python3 scripts/lint-guard-contract.py` passes on this plan (2 entries).
- [ ] AC12. The four vitest files pass, `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean (the root `package.json` declares no `workspaces`, so the `-w` form aborts), and the
  PR body says `Ref #10552`.

### Post-merge (automated, no operator step)

- [ ] AC13. #10552 carries the `follow-through` label and the unfenced column-0 directive
  (`script=scripts/followthroughs/compound-promote-draft-edit-10552.sh`, `earliest` after the
  2026-10-25 fire, the three `BETTERSTACK_QUERY_*` secrets). The sweeper closes it when the first
  post-merge run opens a draft PR, or refuses a cluster at a downstream gate (proof the proposal
  now reaches the gates). A quiet week, or a week of only model-side `edit-*` refusals, leaves it
  open (exit 2).

## Plan Review (2026-10-19)

Panel: DHH-style and code-simplicity (per mechanism) returned; the Kieran-style correctness seat
did not return before the pipeline moved on, so correctness is covered by the deepen-plan pass.
Applied (all Mechanical, one right answer): a base without a trailing newline cannot take an
additive append (reproduced: it rewrites the last line), so the base must end with LF and
contain no CR - the earlier "add a newline" branch and CRLF handling are gone; `edit-empty` and
`edit-schema-invalid` merged into `edit-invalid` (five reasons); a non-additive derived diff is a
server bug and maps to the retained `diff-underivable-apply`, not to a model-side reason; the
probe closes only on a draft PR or a downstream-gate refusal; test rows T13 and T19 and mutation
rows M-8 and P-7/P-8 folded or cut; `byte_impact` confirmed unread downstream. Kept
deliberately: the git-derived diff (hand-computing hunk counts is the failure class removed) and
the text anchor (self-verifying, unlike a line number). Not applied: shrinking the plan prose.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, placeholder-only or omits the threshold
  fails `deepen-plan` Phase 4.6; this one declares `none` with the sensitive-path scope-out line.
- The derived diff's header form is the whole ballgame: the un-flagged `git diff --no-index`
  produces `a/a/<path>`, which `checkDiffPaths` then refuses as `underivable-apply`, i.e. the fix
  would reproduce the original symptom with a different cause. M-4 and AC4 exist for this.
- Moving `target-path-refused` into the new step changes which callback holds that refusal; the
  census suites pin per-site counts and the replay-safety rule (no handler-scope mutation inside a
  memoized callback). Read both census files completely before editing the handler.
- The issue's acceptance criterion allows "records a named non-`diff-underivable` cause". Read
  literally, two weeks of `edit-anchor-not-found` would close #10552 with no PR ever opened and
  with the new path never having reached a gate. Plan review (two seats) tightened the probe: only
  a draft PR or a downstream-gate refusal closes; an all-`edit-*` week stays NOT YET and prints its
  reasons. A persistent `edit-*` streak is then a visible open tracker, not a silent closure.
- Do not weaken the 120,000-byte cap into "send an excerpt": the anchor must be copied from text
  the model saw in full, and an excerpt makes `edit-anchor-not-found` the dominant failure.
- The brief's three "likely candidates" are all wrong as stated; do not add a fence stripper, an
  empty-diff handler or a hunk synthesiser - they are the per-mode patches this plan rejects.
