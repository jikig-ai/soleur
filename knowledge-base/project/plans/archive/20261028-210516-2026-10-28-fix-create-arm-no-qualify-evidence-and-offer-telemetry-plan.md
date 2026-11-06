---
title: "fix(compound-promote): find out why the gated create arm declines every open pattern"
date: 2026-10-28
slug: create-arm-no-qualify-evidence-and-offer-telemetry
branch: feat-one-shot-10550-create-arm-no-qualify
issue: 10550
type: fix
priority: p3-low
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

## Overview

The gated create arm of the weekly self-improvement promoter returned a clean decline on its third manual
live-fire: the model was called over the open patterns and judged none worth a new skill. This plan separates
three candidate causes (the qualification bar, the evidence the model sees, the prompt) and decides what, if
anything, to change. The PR refers to #10550 and never closes it.

## Enhancement Summary

**Deepened on:** 2026-10-28
**Gates run:** User-Brand Impact (threshold `none` with the sensitive-path scope-out line), Observability (all five fields,
allowlisted verb, literal `expected_output`), PAT sweep (no hits), Scope Check (one live section, no unmapped ask), plus
not-applicable for UI wireframe, encryption posture, guard contract and task design.
**Agents used:** observability-coverage-reviewer, test-design-reviewer, architecture-strategist, security-sentinel,
learnings-researcher, plus the earlier DHH, Kieran, code-simplicity and CTO passes.

### Key improvements
1. The stamping design is now one `proposeInner` return of `{ verdict, offeredCount? }` unwrapped inside the step's own
   `try`, so a defect in the count cannot escape the memoized step and `week-cap`/`index-empty` provably carry no field.
2. Replay safety is concrete: the field is assigned outside the callback, range-guarded, covered by census Guard 3d, stripped
   before the persist step, and tested through the real step harness memo (the planned `vi.mock` seam could not inject).
3. "No behaviour change" is a measurement: a characterization test written against the pre-refactor code replaces the cut
   constant re-pins.
4. The probe is isolated from production telemetry and secrets (`-c ci`, `--only-secrets`, no `markerSource`), has fixed
   sample sizes with a stated detectable rate, and screens bodies with both the PII and credential patterns.
5. The discoverability probe is credential-free (`rg -l`), which avoids the repo-global `BASELINE_DECLARED_PROBES` bump.

### New considerations
- The test list was undercounted: twelve `toEqual` sites gain `offered` (including line 230) and census Guard 3d needs
  `createOffered =`; both are now in Files to Edit.
- ADR-300's "counts and closed enums only" sentence belongs to the ledger-reader contract, so the create marker gets its own
  one-line addendum.
- `create_offered` has two readings (model-seen vs candidate count); the definition and the runbook wording now say which
  verdicts mean which.

## Research Insights

### Premise Validation (Phase 0.6)

- #10550 is OPEN (labels include `deferred-scope-out`, `decision-challenge`), so the premise holds. The last
  tracker comment (2026-10-28T17:55Z) records the third live-fire and says "I have not checked whether the model saw
  all seven patterns, so that is unconfirmed" and "re-fire ... after a change to the qualification criteria".
- Collision pre-check hit one open PR naming #10550: #11441, which is this branch's own draft (no files, auto-created).
  Three foreign `test-all.sh` processes belong to an unrelated worktree (`feat-one-shot-autonomous-start-followthroughs`).
- Cited code exists on `origin/main` (`compound-promote-create-arm.ts` 919 lines, `compound-promote-create.ts`
  1115 lines, `compound-promote-patterns.ts` 355 lines); it is "tune a live arm", not "build".
- ADR corpus: ADR-092 (create-only amendment, 2026-10-26) and ADR-300 (addendum 2026-10-26) govern the arm. The line
  "the marker carries counts and closed enums only" is in ADR-300's ledger-reader contract (~line 46), scoped to that
  reader's own fields; the 2026-10-26 addendum says only that `kind` is a closed field. So the create arm's marker had no
  stated bound, and this plan adds a one-line dated ADR-300 addendum for `create_offered`. The statement that page bodies
  are never sent lives in a code comment (`compound-promote-patterns.ts` `renderPatternIndex`), not in an ADR. The
  2026-10-28 ledger pre-filter ruling chose "no new marker field"; this plan reverses that one ruling on purpose,
  because the field it declined is the one that now blocks the diagnosis (recorded in `decision-challenges.md`).
- Spec: no `knowledge-base/project/specs/feat-one-shot-10550-create-arm-no-qualify/spec.md` exists (one-shot path, no
  brainstorm), so `lane:` defaults to `cross-domain` (fail-closed).

### Better Stack outcome rows (pulled 2026-10-28, `SOLEUR_COMPOUND_PROMOTE_OUTCOME`, `create_requested=true`)

| dt (UTC) | run_id | status | patterns_open | ledger_suppressed | create_outcome | class / reason |
|---|---|---|---|---|---|---|
| 2026-10-27 09:30 | 01M5YB28JD20JKKH4HG04CX2Z4 | completed | 7 | 0 | refused | week-cap / no-slot (fixed #11297) |
| 2026-10-28 09:39 | 01M60XZRYG9ADVEWAY07HEQ5JK | no-qualifying-clusters | 7 | 1 | no_action | reason `other` (owned pattern won the one call; fixed #11394) |
| 2026-10-28 17:51 | 01M61T5RMQ57Q4MRYEC032VK9X | no-qualifying-clusters | 7 | 0 | no_action | reason `no-pattern-qualifies`, create_pr none |

### What the model is shown, per pattern (code reading, `renderPatternIndex` + `prepareCreate`)

- Sent: slug, title (<=120 chars), summary (<=200 chars, measured 146-186), tags, evidence KEYS (learning file paths).
- NOT sent: the page body (`## Root cause` / `## Fix`, 12.1 KB across the 7 pages), the first-10-line excerpts of the
  38 cited learnings (12.5 KB), `opened_on`, any age or recurrence signal. The edit loop's patterns call does send the
  excerpts; the create call does not.
- Skill side: one line per model-visible skill (96 skills, 18.5 KB): name and description only, so "a patch to the
  nearest skill would bury it" cannot be judged (no size, no section list).
- Input bound now ~6.4k tokens against the 12k refuse-never-truncate ceiling (F3). Adding bodies gives ~9.4k, adding
  excerpts ~9.5k, both ~12.5k (over). Measured by script from the repo tree on 2026-10-28 (scratch, not committed).
- `corpus_count=38` equals the 38 distinct evidence learnings across the 7 pages, so all 7 pages loaded with all
  their evidence; the loader did not drop anything.

### Did all seven reach the model? Derived: no, six

`proposeInner` offers `patterns - sameRunHashes - ledgerOwned`. Recomputing `sha256(sorted evidence keys + "\n")` for
the seven pages on main and comparing with the four bot PR hashes (#11230, #11231, #11290 closed; #11291 open) gives
exactly one match: `early-exit-reader-under-pipefail` = `92ac0c4a...` = open edit PR #11291. So the model was offered
six patterns. The edit loop was skipped (one free slot, `editCap=0`), so there were no same-run hashes. The marker
cannot show this: `ledger_suppressed` counts only the edit loop and the post-call backstop, the create pre-filter is
silent, and `create_no_action_reason=no-pattern-qualifies` only proves a call was spent (a no-call path emits
`all-owned` or `other`). So "all seven" was unconfirmable from telemetry; it is derived here, with the caveat that it
assumes the deployed clone equals main at the time (the patterns directory last changed in #10970).

### The prompt and the bar

- Prompt: "Prefer patching an existing skill ... Return no_action unless a pattern is mature, no existing skill owns
  it, AND a patch to the nearest skill would bury it." "Mature" is undefined; the three conjuncts are all required.
- Output: `no_action` carries only `reason_class` in {no-pattern-qualifies, all-owned, other}: one bit, so a decline
  cannot say immature, owned, better-patched or not skill-shaped.
- All seven patterns are verification-guard heuristics (pipefail early-exit readers, fixtures that cannot
  discriminate, mutation score is not predicate correctness, guards that pin the artifact not the wiring, instruments
  that answer instead of failing, failure signals that never reach a human, verification scaffolding carries the
  defect). They plausibly belong in existing review/work/test skills, so the decline may be right.
- Server-side bar, never exercised on real model output. Using the real `rankOverlap` over the real 104-skill
  population, synthetic natural proposals for the seven patterns score top-1 overlap 0.05-0.11, under the 0.16
  threshold, so that threshold would not refuse them. The `nearest_skill must be in the lexical top-3` gate is the
  likelier second hurdle: the lexical top-3 neighbours were semantically unrelated (pipefail pattern: dspy-ruby,
  legal-generate, agent-native-architecture).

### Property List (Phase 0.6b)

1. After a create-arm run, an operator can tell from Better Stack alone how many patterns were offered to the model.
2. After a create-arm run that declines, an operator can tell WHY it declined (class of reason per pattern), not only
   that it declined.
3. The model has the evidence a human would use to judge "mature" and "would a patch bury it".
4. The next live-fire is a measurement, not a re-roll: its result discriminates bar vs evidence vs prompt.

### Cut List (Phase 0.6b)

- Per-pattern verdicts from the model (CTO option B, first ruled in, then dropped after the token evidence) ->
  property 2 -> the existing `SOLEUR_CLAUDE_COST` row's `output_tokens` already separates an instant decline (30)
  from a deliberated one (1246); forcing deliberation would change the thing measured. Property 2 is served only
  coarsely (evidence-starved vs decline-correct) by probe arm 1; a per-pattern reason class is not pursued.
- Probe arm "explain why per pattern" (plan review) -> property 2 -> no decision-rule branch consumes it; cut.
- Second Anthropic call per run for explanations -> property 2 -> same as above.
- New Sentry op for the offered count -> property 1 -> the outcome marker already is the machine-readable row.
- Weekly-cron enablement of the create arm -> none of the four properties; out of scope (priority/scope, operator).
- Loosening `OVERLAP_REFUSE_THRESHOLD` -> none; no run has reached that gate.

### Token evidence from the cost marker (pulled 2026-10-28, `SOLEUR_CLAUDE_COST`, joined on run id)

The create call shares `markerSource` `cron-compound-promote` with the edit calls (`CREATE_FEATURE_NAME`), so each run's
calls are rows with the run id under source `cron:cron-compound-promote`.

| run | call | input_tokens | output_tokens | reading |
|---|---|---|---|---|
| 01M5YB28 (10-27) | edit cluster, 2 edit drafts | 18038, 7691, 9941 | 2429, 321, 360 | no create call (week-cap refusal before the call) |
| 01M60XZR (10-28 09:39) | create, 7 offered | 10993 | **1246** | a full create proposal (for the owned pattern; the post-call ledger gate suppressed it) |
| 01M61T5R (10-28 17:51) | create, 6 offered | 10481 | **30** | `{"decision":"no_action","reason_class":...}` and nothing else: an instant decline |

What this changes (CTO ruling, below): the same prompt and evidence CAN produce a create (run 2), so "the prompt and
evidence are structurally biased to decline whatever the pattern" is NOT shown. The input delta of 512 tokens between
runs 2 and 3 is about one pattern row, which corroborates "six offered" independently of the hash derivation. The
real tokenizer gives ~10.5k input tokens where the `bytes/4` proxy (the F3 ceiling) gives ~6.4k, so the 12k ceiling is
a proxy ceiling, not a real-token cap. The run-2 proposal content is not recoverable from telemetry, so the
`nearest_skill` top-3 gate has never seen a real model proposal.

### Technical rulings (CTO agent, 2026-10-28; full table in `decision-challenges.md`)

- Ship ONE behaviour-neutral change: a numeric `create_offered` marker field. No prompt, bar, evidence or schema change
  ships (E: no behaviour change). The per-pattern verdict schema (option B), page bodies (C), a mechanical maturity
  pre-filter (D) and any `nearest_skill` gate change are follow-ups gated on the probe, not in this PR.
- Run an offline probe during the work phase (read-only, scratchpad output, no cron) in three arms to decide whether
  any follow-up is warranted.

## Research Reconciliation: brief vs codebase

| Brief / tracker claim | Reality | Plan response |
|---|---|---|
| "the model was called over the remaining patterns and declined all" | True (cost row: 10481 in / 30 out), but "the remaining" is six, not seven: one pattern is owned by open edit PR #11291 | Report six; add `create_offered` so the next row states it |
| "Unconfirmed: whether the model saw all seven" | Answerable now: no, six (hash derivation plus the 512-token input delta) | Record as derived, and make it observable from the marker |
| "the bar, the evidence, or the prompt is why nothing qualifies" | Not separable from current telemetry; run 2 shows the model can create, run 3 shows it declined six abstract patterns in 30 tokens. The server-side bar has never been reached | Do not change the bar, evidence or prompt blind; measure first (probe), instrument (`create_offered`) |
| "The create arm never runs on the weekly cron" | True by design (`readRunOptions` returns `allowCreate:false` off manual) | Out of scope: enabling it is a scope/priority decision for the operator, not a technical fork |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing on any product surface. The change adds one number to a
  server log row for a manual, operator-fired maintenance run; the worst case is a wrong or missing `create_offered`
  value in Better Stack, which misleads the next diagnosis, or a typing/serialisation defect that fails the create
  step (a returned refusal, never a thrown error, and no PR opens).
- **If this leaks, the user's data is exposed via:** no new path. The field is an integer; it carries no model text,
  no pattern content and no identifier. The probe sends only repo-committed pattern pages and learning excerpts that
  the existing loader has already PII-screened, to the processor that the cron already uses.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the create arm as a whole carries the `single-user incident` threshold
  (model-authored public plugin files), but this PR does not touch what the arm authors, how it is gated or what it
  may open; it adds a count to the marker. A behaviour change (evidence, prompt, bar) would re-open the arm's
  threshold and is deliberately not in this PR.

`threshold: none, reason: the touched files (server/compound-promote-*.ts, the Inngest handler) are server-side
maintenance code, and the diff adds one integer marker field without changing any prompt, gate, input or output of the
create arm; no user-facing artifact or credential surface is involved.`

## Proposed Solution

One PR, in this order. The effect on whether a create PR ever opens is **unmeasured** and stays so until an
operator-authorised live-fire clears; nothing in this PR claims otherwise.

### Phase 0: offline probe (measurement, no product code; scratchpad only)

Purpose: decide whether any follow-up beyond `create_offered` is warranted, per the CTO decision rule. Constraints
(deepen-plan security review): no cron fired; nothing from the probe is committed or posted except counts and decisions.

1. Credential: only `doppler run -p soleur -c ci --only-secrets ANTHROPIC_API_KEY -- <script>`. `ci` is the spend-capped
   `soleur-ci-eval` workspace (precedent: `plugins/soleur/skills/eval-harness/README.md`, which forbids running a grid
   under any `prd*` config, #8505); `dev` has no key. NEVER `prd`, `prd_scheduled` or `prd_terraform`. The
   `--only-secrets` form keeps every Sentry, Better Stack, GitHub and Supabase secret out of the child environment. If `ci`
   fails (401, spend cap) or has no key, record "probe not run" and stop at Phase 1; the PR does not depend on the probe.
   No `set -x`. The key is never in argv or echoed.
2. Telemetry isolation: the probe passes NO `markerSource` and NO `markerRunId` to `postAnthropicMessage`. With a
   `markerSource` the helper emits a `SOLEUR_CLAUDE_COST` row under `cron:<name>`, which would pollute the very join the
   diagnosis uses, and a credit-exhaustion response calls `reportAnthropicCreditExhausted`. Cost is read from the
   response `usage`.
3. Arm 0 builds the real create prompt with `prepareCreate` over the real pattern pages (`loadOpenPatterns`) and the real
   skill population (`countDescriptionWords(...).records`), then calls `postAnthropicMessage` with `EXECUTION_MODEL` and
   `CREATE_OUTPUT_SCHEMA`. Arm 1 hand-assembles its prompt (the body addendum cannot go through `prepareCreate`
   unchanged), so it bypasses the 12k proxy ceiling on purpose; the probe output says so. `checkCreate` needs a full
   `CreateContext`: build it from the exported readers (`countDescriptionWords` for `skills`/`skillDirs`/budget total,
   `readBudgetCap`, `readAgentPaths`, `readCursorDirs`, `readCommandNames`) with `openPrPaths: []` and
   `isHashSuppressed: () => false`. Those two injected seams mean the production open-PR and ledger readers are NOT
   exercised; the probe output labels the result "prod readers not exercised" (a seam every test uses leaves the
   production default untested).
4. Arms and sample sizes, fixed BEFORE running (a count of "no create" is only evidence against a rate the count can
   detect):
   - Arm 0: the unmodified prompt over all 7 patterns, 2 calls. Expect the early-exit-reader create to reproduce; run
     `checkCreate` offline on every create. This is the first real-model test of the `nearest_skill` top-3 gate.
   - Arm 1: arm 0 plus the six non-owned patterns' `## Root cause` / `## Fix` bodies appended, 3 calls. Plan review cut
     the per-pattern "explain" arm: no decision-rule branch consumes it, and it forces the deliberation the CTO dropped
     option B to avoid. Bodies are read only for slugs the loader returned, via `lstat` (regular file, not a symlink),
     run through `parsePatternPage` with `PII_REGEX` AND `CREDENTIAL_RE` (the loader applies `PII_REGEX` only), dropped
     on any hit, and each wrapped in a nonce fence with `untrustedDataSentence`.
   - Three all-`no_action` calls rule out an arm-1 create rate above ~40% (0.6^3 = 0.22), not a rate of a few percent. The
     finding is worded "no create at this sample", never "cannot create".
5. Output handling: model text goes to a scratchpad file with mode 0600 and is deleted after the #10550 comment; the
   terminal gets only counts, decision kinds and `checkCreate` refusal classes, with control characters stripped.
6. Decision rule (CTO, adjusted for the cut arm): if any arm-1 call turns one of the six into a create that passes
   `checkCreate`, the finding is "evidence-starved" and an evidence-enrichment follow-up is warranted (C). If all arm-1
   calls stay `no_action`, the finding is "decline correct at this sample". If an arm-0 create fails
   `nearest-not-top3`, the `nearest_skill` candidate-list follow-up is warranted (the prompt tells the model its nearest
   skill must be in the server's top 3, a ranking it never sees). The result goes in ONE comment on #10550 (counts and
   decisions, no model-authored skill text; no closure). A follow-up issue is filed from the probe's actual output only
   when its rule fires, with a milestone from `knowledge-base/product/roadmap.md`; #10550 is the tracker until then.
   Arm 1 sends pattern bodies, a data class the production create call has never sent (the edit loop sends learning
   excerpts, not bodies), to the `ci` eval workspace; the content is committed text under the PII and credential screens
   above, and the CTO ruled no CLO review is needed. The `soleur-ci-eval` workspace's retention terms are not verified
   here; that is an accepted, stated residual.

### Phase 1: `create_offered` (failing tests first, `cq-write-failing-tests-before`)

Meaning (one definition, used in the code comment, the runbook, the recipe and the tests): `create_offered` is the number
of patterns left after the same-run and ledger filters, i.e. the candidates the arm would send. Whenever a model call was
made (a model `no_action`, a `suppressed` backstop hit, a post-call refusal, a `create`) it is exactly the number the
model saw. On a pre-call refusal (`create-open`, the `budget` and `slug` measurement refusals, `input-size`,
`no-api-key`, `persist/clone-missing`) it is the candidate count and no call was spent: read `create_refusal_class` and
`create_detail` for that. On a pre-call `no_action` (`all-owned`, `other`) it is `0`. So "a call was spent" is readable
from a `no_action` row alone (`create_offered > 0`), not from a refused row.

Steps, in order:

1. Consumer grep first (`hr-type-widening-cross-consumer-grep`). Measured at plan time: `CreateVerdict` is used by the
   arm (`runCreateProposeStep`, `proposeInner`, `CreateVerdictCreate`) and by the handler in exactly two places
   (`createNoAction`'s `Extract<...>` at ~1731 and `const proposed` at ~2217); `createMarker()` has three call sites
   (~2292, ~2763, ~2805) that gain the field with no further edit. Re-run before editing. Also run
   `grep -rln "SOLEUR_COMPOUND_PROMOTE_OUTCOME\|create_no_action_reason" apps/web-platform/test plugins/soleur/test scripts`
   and run every suite or script it names (a new field once moved a pin in a suite the affected-selector never picks);
   `scripts/lint-betterstack-emitter-read.sh` is one of them.
2. Characterization test FIRST, written and run green against the PRE-refactor code: with a fixed `nonce` and a stub
   `post`, capture the exact `post` arguments (prompt bytes, `outputConfig` schema, `maxTokens`, `timeoutMs`,
   `markerSource`) and the `checkCreate` context (`patterns` is the full `a.patterns`, not the offered subset;
   `isHashSuppressed` still the backstop), and pin the guard order week-cap, index-empty, same-run, ledger,
   clone-missing, create-open. It must stay byte-identical across the refactor. This replaces the cut golden-prompt and
   constant re-pins and is what makes "no behaviour change" a measurement, not a claim.
3. `compound-promote-create-arm.ts`. Name the stamped field `offeredCount` (number) and the filtered list `candidates`
   (array) so the two never share a name. Extract the pre-call filter into one pure helper `selectOffered(a)` returning
   `{ done: CreateVerdict }` (an empty offer: `other` or `all-owned`) or `{ candidates: PatternPage[] }`. `proposeInner`
   runs `week-cap` and `index-empty` first (unstamped), then `selectOffered`, then the existing body unchanged, and
   RETURNS `{ verdict, offeredCount? }` computed once (`0` on a `done`, `candidates.length` otherwise).
   `runCreateProposeStep` unwraps that INSIDE its existing `try` and returns `{ ...verdict, offered: offeredCount }`
   (only when `offeredCount` is defined); the `create-propose-internal` catch returns the bare refusal, so a throw in the
   count can never escape the memoized step. Define and export `CreateStepVerdict = CreateVerdict & { offered?: number }`
   in the arm file (the intersection distributes over the union, so `Extract<..., { kind: "create" }>` and
   `CreateVerdictCreate` stay valid). The stamp is a spread of the helper's return, never a bare `{ kind: "refused" ... }`
   literal, so the outcome census (Guard 1e/1f) and `compound-promote-marker-numbers.test.ts` (which only scans
   `fail(`/`refuse(` argument objects) stay green unedited. `compound-promote-create.ts` and
   `compound-promote-create-gates.ts` are not edited.
4. `cron-compound-promote.ts` `runCreateArm`: change `const proposed: CreateVerdict` to `CreateStepVerdict`; declare a
   hoisted `let createOffered: number | undefined` beside `createOutcome`; assign it IMMEDIATELY after
   `step.run("create-propose")` and before any branch, OUTSIDE the step callback (a memoized step skips its callback on
   replay), guarded by `Number.isInteger(x) && x >= 0 && x <= MAX_OFFERED` (`MAX_OFFERED` a small named constant above the
   pattern-page bound; an out-of-range or non-integer memo yields no key). Strip the field before the verdict reaches
   persist: `const { offered: _o, ...rest } = proposed` and pass `rest`, so `runCreatePersistStep` and `buildCreatePrBody`
   never see it. `createMarker` emits `create_offered` with one explicit spread beside `create_no_action_reason` (not via
   `CREATE_MARKER_NUMBERS`, which is for refusal `numbers`). A comment records why the silent drop is acceptable: the
   legacy memo case is expected, and a stamped value is always a non-negative integer (pinned by the tests).
5. `compound-promote-marker.ts`: add `create_offered?: number` to `CompoundPromoteOutcome` and its bullet in the field
   comment block ("a count, never text").
6. Census Guard 3d in `cron-compound-promote-outcome-census.test.ts`: add `"createOffered ="` to both the `MUTATED` list
   (~line 1286) and the non-vacuity loop (~line 1299), plus one mutation row (move the assignment into the
   `create-propose` callback and the guard reds), exactly like the existing `createOutcome =` row. Without it nothing
   fails if the assignment moves into the memoized callback and a replay silently loses the field.
7. Replay (a step that changes what it RETURNS must say how new code reads the OLD memo): the step output is memoized JSON
   that outlives the deploy, so `offered` is optional on read and the reader is shape-tolerant; a handler test seeds an
   old-shape memo through the existing step harness (`runLikeInngest(..., { memo })` in
   `test/helpers/inngest-step-harness.ts`; the `vi.mock` wrapper at lines ~104-113 only records `capLeft` and cannot
   inject) with `create-propose` memoized as `{ kind: "no_action", reason: "other" }` and asserts the run completes with a
   marker lacking the key. A stamped value is `0`, never `undefined` (a field set to `undefined` is dropped by the JSON
   round trip; a test pins that). Rollback is benign: old code reading a new memo ignores the extra field.
8. The prompt text, `CREATE_OUTPUT_SCHEMA`, `OVERLAP_*`, `CREATE_INPUT_MAX_TOKENS`, `renderPatternIndex` and the bar
   sentence are NOT edited.

`create_offered` is a Better Stack marker field only: the Sentry `create-refused` mirror runs before the stamp and does not
carry it, and no alert filters on it.

### Phase 2: docs

- `compound-promote-runbook.md` "Create-arm marker fields" table: add the `create_offered` row (the definition above;
  for a `no_action` row, `create_offered > 0` means a model call was spent, and the call's `output_tokens` on the
  `SOLEUR_CLAUDE_COST` row, joined on run id, separates an instant decline from a deliberated one; on a refused row it is
  the candidate count and the class says whether a call was spent). Correct the existing `create_no_action_reason` row
  (~line 368, "compare the row count against the edit drafts") and the "there is no call" sentences (~lines 399-400): say
  what now can be read.
- `betterstack-log-query.md`: add `create_offered` to the field sentence (~lines 716-727) and the recipe's column list
  (~lines 740-744), with the same qualification.
- ADR-300: one dated addendum line (2026-10-28) beside the 2026-10-26 one: "the create arm's marker also carries
  `create_offered`, an integer count of candidate patterns, and no text". The sentence the plan first leaned on ("the
  marker carries counts and closed enums only") is in the ledger-reader contract (~line 46), scoped to that reader's own
  fields, so the create arm's marker had no stated bound until this line.
- The tracker comment on #10550 after merge: the six-of-seven finding, the token evidence and the probe result (no
  closure, no claim about future PRs).

## Architecture Decision (ADR/C4)

No architectural decision: one integer marker field on an existing row; the ADR-300 addendum above records it. C4: all
three model files were read for this check (`model.c4`, `views.c4`, `spec.c4`). The actors and systems involved are
already modeled and no relationship or access path changes: the Inngest container (`platform.infra.inngest`, the cron
worker), the `anthropic` system, the `github` system, `betterstack` (log sink and query), `sentry`, and the founder/operator
who fires the manual trigger; `views.c4` already includes `anthropic`, `github`, `betterstack` and `sentry` in the
platform views. No new element, edge or `view include` is needed. The derived cardinalities embedded in edge prose
(workflow, monitor, heartbeat counts) do not move; confirm by running `plugins/soleur/test/c4-count-parity.test.sh` green in
Phase 1. (The behaviour-changing options that would need an ADR amendment, evidence bodies and a verdict vocabulary, are
not in this PR.)

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Ruled twice on 2026-10-28 (rows in `decision-challenges.md`). After the token evidence the CTO narrowed the
change to `create_offered` plus no behaviour change, narrowed the probe to three arms, retracted the "unsatisfiable
top-3 instruction biases the model" claim to "unmeasured", and corrected the F3 ceiling to a proxy, not a real-token
cap. No other domain is affected: no user-facing copy, spend decision or legal-register change. The probe's arm 1 sends
committed pattern bodies (PII and credential screened) to the spend-capped `ci` eval workspace, a data class the
production create call has never sent; the CTO ruled no CLO review is needed and the retention terms of that workspace
are an accepted, stated residual, so `soleur:gdpr-gate` is not invoked.

No Product/UX surface: no file under a UI path.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_COMPOUND_PROMOTE_OUTCOME marker row with create_offered (the candidate count; the number the model saw whenever a call was made) on every create-arm run whose verdict passes the offered stage; absent on a week-cap or index-empty refusal
  cadence: per manual create-arm run (the weekly cron never runs the arm)
  alert_target: the operator reading Better Stack after an operator-authorised live-fire; no pager (the arm is manual and dark); the run itself keeps the existing Sentry cron monitor heartbeat
  configured_in: apps/web-platform/server/inngest/functions/cron-compound-promote.ts createMarker, apps/web-platform/server/compound-promote-marker.ts
error_reporting:
  destination: Sentry web-platform via reportSilentFallback (op create-propose-internal for a defect inside the step; op create-refused tagged class for a refusal; neither carries create_offered)
  fail_loud: the step never throws; a defect returns a closed model-invalid/internal refusal and mirrors the Error to Sentry, and the count is then absent rather than wrong
failure_modes:
  - mode: create_offered absent, wrong or stamped on the wrong verdict on a run that reached the offered stage
    detection: layer 3 (pino WARN row on the dedicated marker logger, shipped by Vector to Better Stack) read by the runbook recipe after the next live-fire; pre-merge only, the AC1 and AC2 named mutation tests, the key-set pins and census Guard 3d in CI
    alert_route: no pager; the operator reads the row after the live-fire, and a red PR check pre-merge
logs:
  where: Better Stack (pino WARN, SOLEUR_COMPOUND_PROMOTE_OUTCOME and SOLEUR_CLAUDE_COST rows; layers 1, 2 and 5 do not apply because the marker bypasses the logger hook)
  retention: Better Stack source retention (the runbook queries use --since 30d)
discoverability_test:
  command: rg -l create_offered apps/web-platform/server
  expected_output: compound-promote-marker.ts
```

The declared command is the credential-free, sub-second probe that prints where the signal is defined and emitted. The
property that needs production data, that a live row carries the field, is checked after an operator-authorised
live-fire with `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 1d --grep
SOLEUR_COMPOUND_PROMOTE_OUTCOME --limit 20` (AC9). Declaring `credentials_required` for that query would move the
repo-global `BASELINE_DECLARED_PROBES` ratchet and make preflight skip the probe, so it is not declared (observability
review). Verified: Vector does not field-filter marker keys and the emitter spreads `...outcome`, so a new key is
queryable by the existing recipe's decode of `.raw|fromjson|.message`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Investigate why the gated create arm of cron-compound-promote judges none of the 7 open patterns worth a new skill" | Research Insights; Phase 0 probe | mapped |
| 2 | "determine whether the bar, the evidence, or the prompt is why nothing qualifies (and whether all 7 patterns reach the model)" | Research Insights (six of seven, token evidence); Phase 0 decision rule; Phase 1 `create_offered` | mapped |
| 3 | "pull Better Stack data yourself" | Research Insights (outcome rows, cost rows) | mapped |
| 4 | "If a code change is warranted, make it via the normal pipeline on a new branch" | Phase 1 and Phase 2 on this branch/PR | mapped |
| 5 | "Route any technical fork (threshold, evidence, prompt design) to the soleur:engineering:cto agent" | Technical rulings; `decision-challenges.md` | mapped |
| 6 | "Do not claim a fix \"will open a PR\"; say its effect is unmeasured until a live-fire clears." | Proposed Solution preamble; AC8 | mapped |
| 7 | "Do NOT fire the cron (no soleur:trigger-cron run) until the operator explicitly says so" | AC9; the stop point after merge | mapped |
| 8 | "Code-change deliverable: merged PR, deploy verified (new code served), then soleur:postmerge." | AC10 (ship phase) | mapped |
| 9 | "Leave other open issues alone; ... Do not start the separate low-priority bug or the semgrep-custom-rules lstat-then-read note." | Non-Goals | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `create_offered` marker field | "whether all 7 patterns reach the model" | asked |
| Offline probe (3 arms) | "determine whether the bar, the evidence, or the prompt is why nothing qualifies" | asked |
| Runbook and Better Stack recipe edits | "Outcome-row query: knowledge-base/engineering/operations/runbooks/betterstack-log-query.md" | asked |
| Tracker comment on #10550 with the finding | "Ref #10550" | asked |
| Follow-up issues (evidence enrichment; `nearest_skill` candidate list) | — | inferred — justification: not a plan deliverable; each is named by the CTO decision rule and is filed from the probe's output only when its rule fires, with #10550 as the tracker until then, so a deferral is never left without a tracking issue |

### Split Assessment

- Subsystems touched: 2 (`apps/web-platform/server` plus its tests, `knowledge-base/engineering/operations/runbooks`)
- Planned files: 12 (10 edited, 2 created) | Estimated changed lines: ~220
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Files to Edit

- `apps/web-platform/server/compound-promote-create-arm.ts` (`selectOffered`, `CreateStepVerdict`, `proposeInner` returns `{verdict, offeredCount?}`, `runCreateProposeStep` stamps inside its `try`)
- `apps/web-platform/server/compound-promote-marker.ts` (`create_offered?: number` and its comment bullet)
- `apps/web-platform/server/inngest/functions/cron-compound-promote.ts` (`runCreateArm` annotation, hoisted `createOffered`, strip before persist, `createMarker` spread)
- `apps/web-platform/test/server/compound-promote-create-arm.test.ts` (the characterization test; the `toEqual` sites at lines 230, 310, 357, 359, 412, 430, 454, 462, 464, 475, 488 and 497 gain `offered`, the `suppressed` rows 430, 488 and 497 with the real count; `not.toHaveProperty("offered")` on `week-cap`, `index-empty` and the `create-propose-internal` catch)
- `apps/web-platform/test/server/inngest/cron-compound-promote-create-handler.test.ts` (the exact opened-create key pin `createKeys(r.last).sort()` ~line 915 gains `create_offered`; `CREATE_ONLY_KEYS` ~line 327 gains it; the legacy-memo case via `runLikeInngest(..., { memo })`; the H3 pre-call rows ~695-712 pin `offered: 0` end to end)
- `apps/web-platform/test/server/inngest/cron-compound-promote-outcome-marker.test.ts` (`ALLOWED`: `create_offered: (v) => Number.isInteger(v) && v >= 0`; `CREATE_KEYS` ~line 479; emit `create_offered: 6` on the refused-create row ~line 490 and a `0` row so the validator actually runs; negative probes `-1`, `1.5`, `"6"`; assert it is not a value of `CREATE_MARKER_NUMBERS`)
- `apps/web-platform/test/server/inngest/cron-compound-promote-outcome-census.test.ts` (Guard 3d: `"createOffered ="` in `MUTATED` ~line 1286 and the non-vacuity loop ~line 1299, plus one mutation row)
- `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md` (new field row; correct the `create_no_action_reason` row ~line 368 and the "there is no call" sentences ~lines 399-400)
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` (field sentence ~lines 716-727 and the recipe column list ~lines 740-744)
- `knowledge-base/engineering/architecture/decisions/ADR-300-pattern-wiki-and-pr-state-proposal-ledger.md` (one dated addendum line)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10550-create-arm-no-qualify/decision-challenges.md`
- `knowledge-base/project/specs/feat-one-shot-10550-create-arm-no-qualify/tasks.md`

(All ten edit paths were verified to exist on the branch. The probe script lives in the session scratchpad and is
not a repo file. `compound-promote-create.ts` is deliberately NOT in this list.)

## Open Code-Review Overlap

None. Checked the seven code and runbook paths above against open `code-review` issues (two-stage `gh --json` then
`jq --arg`): no body names any of them.

## Non-Goals

- Changing the prompt, the "mature" bar sentence, the evidence the model sees, the output schema, `OVERLAP_REFUSE_THRESHOLD`,
  the `nearest_skill` top-3 gate or `CREATE_INPUT_MAX_TOKENS`. Each is a follow-up gated on the probe (CTO T1, T3, T4, T5).
- Enabling the create arm on the weekly cron (scope and priority: operator-only).
- Firing a live-fire. The next one needs an explicit operator go-ahead naming the action (one manual
  `cron-compound-promote` fire with `input:"patterns"`, `allow_create:true`), and each go-ahead authorizes one run.
- The separate low-priority bug, the semgrep-custom-rules lstat-then-read note, and the sibling Phase 1/Phase 3
  trackers (no comment, no closure).

## Acceptance Criteria

### Pre-merge (PR), mechanically checkable

- [ ] AC1. `create_offered` (defined in Phase 1) is stamped on every verdict that passes the offered stage: a model
  `no_action`, `suppressed`, `refused` (pre- and post-call) and `create`; it is `0` on the `all-owned` and `other`
  pre-call returns; it is absent (`expect(v).not.toHaveProperty("offered")`, because `toEqual` ignores undefined
  properties) on a `week-cap` or `index-empty` refusal and on the `create-propose-internal` catch. Fixture: four
  patterns, one claimed by the edit loop this run and one ledger-owned, so `patterns.length` = 4, `unclaimed.length` = 3
  and the offered count = 2 all differ; assert `offered: 2` on a model `no_action`, a `prefer-patch` refusal and a
  `create-open` refusal. Add the max-yield case (edit loop at `editCap=0` with one owned pattern): the arm still reaches
  the offer and the count excludes only the owned one. Mutations that must go red: `a.patterns.length`,
  `unclaimed.length`, stamping `week-cap`, `index-empty` or the catch; and a throw inside `selectOffered` yields a
  `model-invalid/internal` refusal, the Sentry `create-propose-internal` mirror and no `offered` key.
- [ ] AC2. The handler assigns `createOffered` right after `step.run("create-propose")`, before any branch and outside the
  callback (a structural assertion on the source order, plus census Guard 3d), so the marker carries `create_offered` on
  a model `no_action`, a post-call `refused`, a persist-step refusal and an `opened` create. It emits only for a finite
  integer in `[0, MAX_OFFERED]`: an old-shape memo seeded through `runLikeInngest(..., { memo })`, and bad values
  (`null`, `-1`, `1.5`, `"6"`, an object) all yield NO key; a JSON round trip of `offered: 0` keeps it; the persist input
  and the PR body never contain the `offered` key. Mutations: emit `offered ?? 0`; drop the integer guard; move the
  assignment into the callback.
- [ ] AC3. Pins updated, none loosened: the opened-create exact key pin and `CREATE_ONLY_KEYS` in the handler suite, the
  marker suite's `ALLOWED` map and `CREATE_KEYS` (with rows that actually emit the field), and the census Guard 3d lists,
  each as listed under Files to Edit.
- [ ] AC4. "No behaviour change" is measured: the characterization test (Phase 1 step 2) passes byte-identically before and
  after the refactor; `apps/web-platform/server/compound-promote-create.ts`, `compound-promote-create-gates.ts` and
  `compound-promote-patterns.ts` are not in the diff (`git diff --name-only origin/main` lists none); ONE new assertion pins
  that `prepareCreate(...).prompt` contains the bar sentence verbatim (the only prompt fact no suite pins today); the
  existing suites that pin `CREATE_INPUT_MAX_TOKENS` and `OVERLAP_REFUSE_THRESHOLD` stay green. Plan review cut the
  four-constant re-pin and the golden prompt test.
- [ ] AC5. The runbook has a `create_offered` row; the old "compare the row count against the edit drafts" sentence and
  the "there is no call" sentences are reconciled (negative grep for the old sentence); `betterstack-log-query.md` names
  `create_offered` in both the field sentence and the recipe's column list; the ADR-300 addendum line exists.
- [ ] AC6. From `apps/web-platform`: `./node_modules/.bin/tsc --noEmit` (the `-w` workspace form does not work in this
  repo) and the WHOLE `test/server/compound-promote-*` and `test/server/inngest/cron-compound-promote*` sets, not only the
  edited suites: ten suites read the arm or handler source as text (the outcome census with Guard 1e/1f, the allowlist
  suite, the screens import-boundary suite, the runbook-parity suite, `cron-safe-commit-parity`, `repo-wide-suites`), and
  they must stay green; from the repo root: `plugins/soleur/test/c4-count-parity.test.sh`, `scripts/lint-betterstack-emitter-read.sh`
  and every suite or script the Phase 1 step 1 grep names. Every check on the PR is green, and a red check is treated as
  a finding until understood.

### Ship-time checklist (self-attested; not CI-verifiable)

- [ ] AC7. The probe is not in the diff (no probe output or script in `git diff --stat`); the PR body says what it found
  in one sentence (or "probe not run"); it ran under `-c ci` only, with no `markerSource`, no `set -x`, model output only
  in a 0600 scratchpad file; PR readiness does not depend on its result. The finding is posted once on #10550 (no
  closure).
- [ ] AC8. The PR body says `Ref #10550` (never `Closes`), says this is measurement only, and says whether a future
  create-arm run opens a PR is unmeasured until an operator-authorised live-fire clears. It does not say a fix "will
  open a PR".

### Post-merge (operator-gated; this pipeline stops before the fire)

- [ ] AC9. No `soleur:trigger-cron` run is made by this pipeline. After deploy verification the pipeline stops and asks
  the operator for the go-ahead naming the action (one manual `cron-compound-promote` fire with `input:"patterns"`,
  `allow_create:true`); a go-ahead authorizes exactly one fire, read through the Better Stack recipe (`create_offered`,
  `create_outcome`, and the `SOLEUR_CLAUDE_COST` `output_tokens` on the same run id).
- [ ] AC10. Merged PR; deploy verified with new code served (`deploy-arm.sh find --wait`, served `build_sha` equals the
  merge SHA); then `soleur:postmerge` prints "postmerge verification complete!". `<promise>DONE</promise>` is emitted
  only after that line.

## Test Scenarios

- Given four patterns, one claimed by the edit loop and one ledger-owned, when the create step runs with a stub model that
  answers `no_action`, then the verdict is `no_action` with `offered: 2` and the marker carries `create_offered: 2`. (unit)
- Given every pattern owned by the ledger, then no model call is made, the verdict is `no_action`/`all-owned` and
  `create_offered` is `0`. (unit)
- Given every pattern claimed by the edit loop this run, then `no_action`/`other` with `create_offered: 0`. (unit)
- Given the edit loop at `editCap=0` and one owned pattern, then the arm is still reached and the count excludes only
  the owned one. (unit, handler)
- Given the model returns a create that `checkCreate` refuses (`prefer-patch`), then the refusal carries the offered count
  and the marker has both `create_refusal_class` and `create_offered`. (unit)
- Given a pre-call refusal (`create-open`), then the verdict carries the candidate count and the runbook wording says no
  call was spent. (unit)
- Given a `week-cap`, an `index-empty` and a thrown defect in `selectOffered`, then no `offered` key exists. (unit)
- Given an opened create and a persist-step refusal, then both marker rows carry `create_offered`, and the persist input
  never contains `offered`. (unit, handler)
- Given an old-shape memo, or a memo value of `null`, `-1`, `1.5`, `"6"` or an object, then the marker row has no
  `create_offered`; given `offered: 0`, a JSON round trip keeps it. (unit, handler)
- Given a scheduled row and a manual corpus row, then neither carries `create_offered` or any create key. (unit,
  existing key-set tests plus `CREATE_ONLY_KEYS`)
- Given the characterization fixture, then the `post` arguments and the `checkCreate` context are byte-identical before
  and after the refactor, and the guard order is pinned. (unit)
- Regression: the 2026-10-28 pre-filter tests (a different pattern reaches the outcome, not only the owned one being
  refused) stay green.
- Deterministic verification after the next authorised live-fire (consumed by `soleur:qa`, not run here):
  `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 1d --grep SOLEUR_COMPOUND_PROMOTE_OUTCOME --limit 20`
  expects a row with `create_offered`.

## Dependencies & Risks

- The Inngest step output is memoized, so the new field must be optional on read (AC2). A run in flight at deploy
  keeps the old shape.
- `create_offered` is derived from the same filter the model call uses; a future change to the filter that bypasses
  `offered` would make the count lie. `selectOffered` (one helper used by both the call and the count) is the structural
  control; the AC1 mutations are the backstop.
- The probe spends a few cents on the spend-capped `ci` eval key and writes only to a 0600 scratchpad file; model text is
  never printed in full, committed or posted. It emits no cost marker (no `markerSource`), so it cannot pollute the
  production `SOLEUR_CLAUDE_COST` join.
- Rollback: old code reading a new memo ignores the extra `offered` field, so a mid-run rollback is benign.
- Typing: `step.run` returns Inngest 4's `Jsonify<...>`; an optional number passes through it. `tsc --noEmit` (AC6) is
  the check.
- Risk of the CTO-ruled narrowing: if the probe shows the decline is a genuine judgement, this PR adds only an
  instrument and the investigation closes as "decline correct"; that is an acceptable outcome, not a failure.

## References

- Tracker #10550; PRs #11233 (arm), #11297 (slot reservation), #11394 (ledger pre-filter); learning
  `2026-10-28-a-filter-that-runs-after-the-single-decision-cannot-protect-the-decision.md`.
- Code: `apps/web-platform/server/compound-promote-create-arm.ts`, `compound-promote-create.ts` (`prepareCreate`,
  `checkCreate`), `compound-promote-patterns.ts` (`renderPatternIndex`), `inngest/functions/cron-compound-promote.ts`
  (`runCreateArm`, `createMarker`).
- Runbooks: `compound-promote-runbook.md` (create arm), `betterstack-log-query.md` (`SOLEUR_COMPOUND_PROMOTE_OUTCOME`).
