---
title: "Create-arm live-fire reading rule: tell a model decline from a server-gate refusal (Ref #10550)"
date: 2026-10-29
slug: feat-create-arm-verdict-telemetry
branch: feat-one-shot-10550-create-arm-verdict-telemetry
issue: 10550
lane: cross-domain
type: docs
---

## Enhancement Summary

**Deepened on:** 2026-10-29
**Sections enhanced:** 3 (Phase 1 invariant, reading table (now in the runbook), Acceptance Criteria widened)
**Passes run:** the always-on halts (4.6 user-brand present with threshold none and scope-out; 4.7 skipped, pure
knowledge-base Files-to-Edit; 4.8 PAT sweep clean; 4.9, 4.10, 4.11, 4.13 not triggered; 4.12 one unfenced
`## Scope Check`), a verify-the-negative sweep on the plan's negative claims against source, and a check that every
marker value the reading table names exists in `compound-promote-create.ts` / `compound-promote-create-arm.ts` /
`compound-promote-marker.ts`. No external-research or review-agent fan-out: the change is runbook prose over
existing closed tokens and the CTO ruling already covered every fork.

### Key improvements

1. The "a server gate never yields `no_action`" invariant was too strong. The post-call ledger/same-run backstop
   (a model create naming a pattern that was not offered) ends `no_action` with reason `other`. The invariant is
   restated precisely (`no-pattern-qualifies` is always the model's; `other` with `create_offered > 0` is the model's
   or the backstop; `ledger_suppressed` / `refusal_detail` are corroborating hints only, not a discriminator, per CTO T1a), and the runbook's reading table gains the matching row.
2. Added the `model-invalid/transport` row (call may not have reached the model), and review added the `schema` and `unknown-pattern`
   details and a catch-all row, so the table maps the `model-invalid` details and points at the class tables for the rest.
3. Verified every value in the table against source: classes (`CREATE_REFUSAL_CLASSES`), reasons
   (`CREATE_NO_ACTION_REASONS`), outcomes (`create_outcome` type) and details `nearest-not-top3`, `overlap`,
   `open-pr-nearest`, `max-tokens`, `empty`, `not-json`, `transport`.

### New considerations

- The CTO's ruling text ("a gate never produces `no_action`") needs the backstop qualification above; recorded as a
  refinement in decision-challenges.md (T1 note), not a reversal.
- AC2 is a manual-grep check; the CTO pin "no code file changes" excludes a drift-guard test. If the runbook
  vocabulary drifts later, the existing parity suite covers `create_detail` tokens only.

## Overview

The gated create arm of the compound-promote cron has been fired live four times without opening a draft PR.
The brief for this change said the outcome marker "cannot distinguish a model decline from a server-side gate
refusing a model-proposed create", and proposed stamping a model verdict and gate-refusal reasons on it.
Reading the source shows that premise is wrong for the marker as it stands, so the briefed fields are not
built. The CTO ruled (2026-10-29) that this PR is documentation only: it adds the missing live-fire reading
rule to the runbook, so the next live-fire row can be read without anyone re-deriving the mapping.

Ref #10550 only. The tracker stays open. The change alters no behaviour and does not claim that any PR will
open; whether a create is ever proposed is unmeasured until an operator-authorised live-fire clears.

## Research Insights

### Premise Validation (Phase 0.6)

- Issue #10550 is open. PR #11441
  (adds `create_offered`) merged 2026-10-28T22:33Z. PR #11474 is this branch's open draft. Collision pre-check
  reports only #11474 and no foreign runs.
- Stale premise found, and it changes the plan's shape. The brief states the marker cannot tell a model decline
  from a gate refusal. In source:
  - `checkCreate` (`apps/web-platform/server/compound-promote-create.ts`) returns `{kind:"no_action", reason}`
    on the model's own `no_action` answer, immediately after the schema parse and before slug, shape, PII,
    ledger, collision, prefer-patch and budget gates run.
  - Every gate returns `refuse(class, detail, numbers)`; the handler's `recordCreateRefusal`
    (`apps/web-platform/server/inngest/functions/cron-compound-promote.ts`) stamps it as
    `create_outcome=refused` plus `create_refusal_class`, `create_detail` and the allowlisted numbers
    (`create_top1`, `create_nearest_rank`, ...).
  - `no-pattern-qualifies` is a model-only value of `CREATE_NO_ACTION_REASONS`; the server's own `no_action`
    paths yield only `all-owned` or `other` (`selectOffered`, and the `suppressed` branch).
  - The arm makes ONE call with ONE verdict, so a "gate-refusal count" would only ever be 0 or 1.
  - Therefore live-fire 4 (`create_outcome=no_action`, `no-pattern-qualifies`, `create_offered=6`) was a model
    decline with no gate involved.
- ADR corpus check (Phase 0.6 item 4): ADR-300 (pattern wiki and PR-state proposal ledger) already records the
  `create_offered` addition and the "prompt, bar, evidence unchanged" bound; nothing in the corpus proposes a
  verdict/gate-reason marker, and this plan adds none.

### Property List and Cut List (Phase 0.6b)

Properties the ask is really after:

1. A reader of the next live-fire row can say, from the row alone, whether the model declined, a gate refused a
   model create, a pre-call path ended the run, or a PR opened.
2. A reader knows which marker values trigger which follow-up (and which trigger none), so a repeat decline does
   not restart the investigation.
3. No gate, prompt, bar, evidence, schema or marker-shape change ships before a measurement justifies it.

Mechanisms named by the ask, each against what is already on `origin/main`:

| Mechanism in the ask | Property it buys | Already covered by | Disposition |
|---|---|---|---|
| `create_model_verdict` marker field | 1 | `create_outcome` x `create_no_action_reason` x `create_offered` (derivable, grepped in `compound-promote-marker.ts` / `cron-compound-promote.ts`) | CUT |
| `create_gate_refusal` counts and reason slugs | 1 | `create_outcome=refused` + `create_refusal_class` + `create_detail` + `create_nearest_rank`/`create_top1`; one verdict per run so counts are 0 or 1 | CUT |
| Response-size field (alternative considered by the planner, ruled out by the CTO) | "instant vs deliberated" | a `no_action` is `z.strictObject({decision, reason_class})`, about 55 bytes regardless; `postAnthropicMessage` drops thinking blocks; only `output_tokens` on the cost row discriminates (not observed on the 2026-10-29T08:03Z run; cause not established, related incident #11049) | CUT (reopen only if that incident proves unfixable) |
| Changing the `nearest_skill` top-3 gate | none for run 4 (no gate ran) | the 2026-10-28 ruling: unmeasured, not a shown bias | CUT for this PR |
| Runbook reading rule (new) | 1, 2 | runbook lines already map each field; the follow-up rule is the gap | KEEP |

### Existing mechanisms and files read

- `apps/web-platform/server/compound-promote-create-arm.ts`: `runCreateProposeStep`, `selectOffered`,
  `proposeOffered` (the single model call, then `checkCreate`), `CreateStepVerdict = CreateVerdict & {offered?}`.
- `apps/web-platform/server/compound-promote-marker.ts`: `CompoundPromoteOutcome` create fields,
  `CREATE_MARKER_NUMBERS`, `CREATE_SENTRY_ONLY_NUMBERS`.
- Runbook `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md`, section "The gated
  new-skill create arm", subsection "Create-arm marker fields" (field table, lines about `create_outcome`,
  `create_no_action_reason`, `create_offered`) and `betterstack-log-query.md` (jq recipe already prints every
  create column, including `create_offered`).
- `apps/web-platform/test/server/compound-promote-runbook-parity.test.ts` (a REPO_WIDE suite): requires every
  code-emittable `create_detail` token to appear backticked in the runbook, and every token in the runbook's
  "`create_detail` values by class" table to be code-emittable. The new subsection must not add or alter rows
  of that table.
- Precedent for the shape of the previous change: PR #11441 touched the arm, marker, handler, four test files,
  ADR-300 and both runbooks; this one deliberately touches none of the code.

### Prior ruling (still binding) and the new ruling

The archived 2026-10-28 record (`knowledge-base/project/specs/archive/20261028-210516-feat-one-shot-10550-create-arm-no-qualify/decision-challenges.md`,
rows T1, T5, T6, T7) forbade changing the prompt, qualification bar, evidence, output schema, `OVERLAP_*` or the
`nearest_skill` gate, and named the follow-up (a per-pattern server top-3 list in the prompt, never a looser
gate). CTO 2026-10-29: that ruling holds in full for this PR. See
`knowledge-base/project/specs/feat-one-shot-10550-create-arm-verdict-telemetry/decision-challenges.md`.

### Institutional learnings applied

- `2026-10-11-a-marker-copied-into-seven-cells-copied-its-over-claim-seven-times.md` and
  `2026-09-18-a-census-cell-naming-two-markers-reports-the-union-as-each-member.md`: do not restate a marker
  claim in several cells. The new subsection is the single home of the reading rule; `betterstack-log-query.md`
  gets a pointer, not a copy.

## Open Code-Review Overlap

None. (Two-stage `gh issue list --label code-review` / `jq --arg` check against the files below returned no
open scope-out naming them.)

## Implementation Phases

### Phase 1 - Runbook reading rule (the only content change)

Edit `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md`: insert a new subsection
`### Reading a live-fire row (model decline or gate refusal)` between the last bullet of "Create-arm marker
fields" and `### Review checklist for a create draft`. It states, in this order:

1. The invariant, stated precisely: every server gate that refuses a model create returns `create_outcome=refused`
   with `create_refusal_class` and `create_detail`; `no_action` with `no-pattern-qualifies` is therefore always the
   model's own answer. One exception to say out loud: the ledger/same-run backstop, a post-call check on a model
   create naming a pattern that was not offered, ends `no_action` with reason `other`, so `other` with `create_offered > 0` is either the model's own
   `other` or that backstop. Nothing on the marker reliably separates them: the same-run branch leaves neither
   `ledger_suppressed` nor a `refusal_detail` entry, and the edit loop also increments both, so a raised
   `ledger_suppressed` can sit beside the model's own `other`. Read a zero or absent value as unknown, a non-zero one as a hint, never as
   the model's. The arm makes one call with one verdict, so there
   is nothing to count.
2. The reading table. The runbook subsection is its single home (values taken verbatim from
   `compound-promote-marker.ts`); this plan does not restate it, because a second copy drifts. It maps marker values to
   model decline, gate refusal, pre-call end or opened, splits `all-owned` from `other` on a spent call, and ends with a
   catch-all row for every other refused class.
3. What the marker cannot show: whether a decline was instant or deliberated. The only signal is `output_tokens` on
   the `SOLEUR_CLAUDE_COST` row for the run. State it as a dated observation tied to #11049 (the open
   claude-cost-capture-dark incident, which alerts on a missing `cost_usd`), not as a present-tense production claim;
   the fix is separate work, not part of this arm.
4. The brief's claim that the marker could not separate the two cases is deliberately not cited in the runbook: an
   operator document should not reference a work brief. The decision record carries it (T1).

Edit `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`: add one sentence after the
create-arm field paragraph pointing at that subsection. No new jq column (the recipe already prints every
create field).

### Phase 2 - Decision record

`knowledge-base/project/specs/feat-one-shot-10550-create-arm-verdict-telemetry/decision-challenges.md` carries
the CTO rows (already written by the planner): premise correction, change class, status of the 2026-10-28
ruling, reading rule, files, plus the two operator-owned items (enabling the arm on the weekly cron, and the next
live-fire), which this PR does not perform.

### Not in this PR

- Any change under `apps/web-platform/`, `plugins/`, `scripts/` or `.github/`.
- Firing `cron-compound-promote` or running `soleur:trigger-cron` (operator-held, one go-ahead per run).
- The claude-cost-capture-dark incident fix, and issues #8443, #11183, #10676, #11228, #10552, #10551, #8293.
- ADR changes: no architectural decision is made (see below).

## Files to Edit

- `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md`
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10550-create-arm-verdict-telemetry/decision-challenges.md` (planner)
- `knowledge-base/project/specs/feat-one-shot-10550-create-arm-verdict-telemetry/tasks.md` (planner)
- this plan

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "first take a CTO-agent ruling (technical fork, not a user question) on the right next step" [brief] | Research Insights, decision-challenges.md rows | mapped |
| 2 | "(a) measurement-only: stamp the model verdict and the server-gate refusal reason(s)" [brief] | Cut List rows 1-2 (CTO: redundant with existing marker fields) | descoped - justification: CTO ruled the fields duplicate `create_outcome`/`create_refusal_class`/`create_detail`; building them adds a marker key with no new information |
| 3 | "(b) changing the nearest_skill top-3 gate" [brief] | Cut List row 4; reading-rule follow-up row | descoped - justification: CTO ruled the 2026-10-28 bound holds; run 4 involved no gate |
| 4 | "Then plan the implementation per the ruling." [brief] | Phase 1, Phase 2 | mapped |
| 5 | "this ruling must say whether that still holds" [brief] | decision-challenges.md row "2026-10-28 bound" | mapped |
| 6 | "do not claim the change will open a PR" [brief] | Overview, PR wording AC | mapped |
| 7 | "PR body must say \"Ref #10550\"" [brief] | AC4 | mapped |
| 8 | "do NOT fire cron-compound-promote or run soleur:trigger-cron at all" [brief] | Not in this PR | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Runbook subsection | "so the next live-fire distinguishes model-decline from gate-refusal" | asked |
| betterstack-log-query.md pointer | "runbooks knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md and betterstack-log-query.md" | asked |
| decision-challenges.md | "Persist every decision as a row of the `\| Item \| Class \| Ruling \|` table" | asked |

### Split Assessment

- Subsystems touched: 1 - knowledge-base
- Planned files: 5 | Estimated changed lines: about 90
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing; at worst an operator reads a runbook table
  that mislabels a marker value and chases the wrong follow-up.
- **If this leaks, the user's data is exposed via:** no vector; the change is prose over closed marker tokens and
  adds no data, secret or model text.
- **Brand-survival threshold:** none
- **Threshold decision (challengeable):** docs-only change to an internal operator runbook for a manual-only,
  dark-launched arm; no code, data or credential surface moves.

threshold: none, reason: the diff touches only knowledge-base runbook prose and planning artifacts; no
production code, schema, auth or API path is changed.

## Architecture Decision (ADR/C4)

None. Detection test: would a competent engineer reading the ADRs and C4 be misled after this ships? No. ADR-300
already states the create arm's marker bounds and the "prompt, bar, evidence unchanged" constraint; the reading
rule adds nothing the ADR contradicts. C4 check: no actor, system, container or access relationship changes
(the arm, Better Stack, Sentry and the cost marker are untouched); `plugins/soleur/test/c4-count-parity.test.sh`
is unaffected because no count in `model.c4` moves.

## Observability

Skipped by the Phase 2.9 rule: the Files-to-Edit are all under `knowledge-base/`; no code-class path or new
infrastructure surface. The existing marker rows and the `create-refused` Sentry op are the observability
surface this runbook section teaches the reader to use.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected - an operator-runbook change over existing marker values. (Engineering was
consulted through the CTO ruling above, which is the technical-fork mechanism, not a domain leader review.)

## Acceptance Criteria

1. `git diff --name-only origin/main...HEAD | grep -v '^knowledge-base/'` prints nothing (the CTO pin: no code
   file changes, so the four server files and every marker key set are byte-identical).
2. The runbook has exactly one `### Reading a live-fire row` heading, and every marker value named in its table
   exists in the types: run
   `grep -o '`[a-z_0-9-]*`' <(awk '/^### Reading a live-fire row/{f=1;next}/^### /{f=0}f' knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md) | sort -u`
   and confirm each token is a `create_*` field, a marker key (`ledger_suppressed`, `refusal_detail`), a member of
   `CREATE_NO_ACTION_REASONS` or `CREATE_REFUSAL_CLASSES`, a `create_outcome` value, a `create_detail` token the code
   emits (the parity census list), a `class/detail` pair of tokens the code emits, or a named telemetry term (`SOLEUR_CLAUDE_COST`, `output_tokens`, `cost_usd`,
   `extra.cause`, `extra.threshold`, `OVERLAP_REFUSE_THRESHOLD`).
3. `cd apps/web-platform && npx vitest run test/server/compound-promote-runbook-parity.test.ts` passes
   unchanged (the "`create_detail` values by class" table has not been touched).
4. The PR body says "Ref #10550", never "Closes", states that this is documentation only with no behaviour change,
   and does not claim a PR will open (effect unmeasured until an operator-authorised live-fire clears).
5. `betterstack-log-query.md` gains one pointer sentence and no new jq column.
6. The cron was not fired and `soleur:trigger-cron` was not run (the session record shows no such call).

## Test Scenarios

Documentation change: no new code tests. Regression guards that must stay green are the existing runbook parity
suite (AC3) and the marker key-set suites (`cron-compound-promote-outcome-marker.test.ts`,
`cron-compound-promote-outcome-census.test.ts`), which this diff cannot affect (AC1).

## Sharp Edges

- The runbook parity test matches backticked `create_detail` tokens by exact string. A new prose mention such as
  `` `not-json` `` in the reading table is allowed (it is documentation, and the token is real); a backticked
  token that is NOT emitted by the code must not be placed in the existing values-by-class table.
- The reading table copies marker vocabulary. If a later PR renames a value in `compound-promote-marker.ts`,
  this subsection is a second place to update; keep it to one subsection so the sweep is one grep.
- Do not add a "model verdict" or "gate refusal" cell anywhere else in the runbook: the invariant is stated once.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6. This one declares threshold `none` with the scope-out reason.

## Ruling Record

Ruled by CTO agent, 2026-10-29: item 1 the briefed fields are redundant and not built; item 2 no code change in
this PR; item 3 the 2026-10-28 bound holds in full; item 4 the reading rule above; item 5 files as listed. Full
rows in the decision-challenges.md for this branch.
