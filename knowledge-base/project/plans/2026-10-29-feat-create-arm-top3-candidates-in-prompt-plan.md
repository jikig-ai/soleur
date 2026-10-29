---
title: "Create arm: show the model the server's per-pattern top-3 candidate skills (Ref #10550)"
date: 2026-10-29
slug: feat-create-arm-top3-candidates-in-prompt
branch: feat-one-shot-wikiskills-top3-candidates
issue: 10550
type: feat
lane: cross-domain
---

## Overview

Live-fire 6 of the gated create arm (2026-10-29T13:27Z, run `01M63XFR2HTYS2XZ0RP8VNW6K2`) ended `create_arm=ran`,
`create_outcome=refused`, `create_refusal_class=prefer-patch`, `create_detail=nearest-not-top3`,
`create_nearest_rank=34`, `create_top1=0.1`, `create_offered=6`, `patterns_open=7`. The model proposed a create and
named a nearest skill ranked 34th, outside the server's top three.

The cause is structural: the prompt tells the model "your nearest_skill must be among the server's top 3 matches"
but never shows that list, so the model picks by meaning and the gate checks by word overlap. The follow-up the
compound-promote runbook names for exactly this row (and the CTO ruled twice before) is to put the server's
per-pattern top-3 candidate skills into the create-arm prompt. It is not a loosening of the gate: the
`nearest-not-top3` check, `OVERLAP_TOP_K`, `OVERLAP_REFUSE_THRESHOLD` and their tests stay as they are.

Honest scope of the effect. The candidate lists are lexical and keyed on the PATTERN text, while the gate re-ranks
the skills on the PROPOSAL text the model writes afterwards (`proposalOverlapText`: slug, description,
when_to_use). A listed candidate can therefore still fall outside the top three. This change is expected to reduce
`nearest-not-top3` refusals, not eliminate them, and it does not claim a PR will open. Its effect is unmeasured until
an operator-authorised live-fire clears. A Sentry-only discriminator (`nearest_in_offered`) is added so that the next
live row can say whether the model ignored the list or the list did not survive the re-rank.

Ref #10550 only (the epic stays open; no comment, no close). Nothing in this PR fires `cron-compound-promote` or
`soleur:trigger-cron`.

## Research Reconciliation - Spec vs. Codebase

| Claim in the brief or runbook | Reality in the code | Plan response |
|---|---|---|
| "supply the server's per-pattern top-3 candidate skills in the create-arm prompt so the model can name a valid nearest skill" | The gate ranks `proposalOverlapText(p)` (the model's own output), not the pattern. A pattern-keyed list is a proxy and cannot guarantee a pass. | Ship the proxy as ruled (F1), say so in the prompt and the PR, add `nearest_in_offered` so the proxy's quality is measurable. |
| The runbook row says the follow-up is "not a loosening of the gate" | True: the change adds prompt text and one Sentry-only number; `checkCreate` still returns the same `refuse(...)` for the same inputs. | Existing gate tests (`compound-promote-create.test.ts` ~L984-1005) and the prompt anchor regex (~L1246) must pass unchanged. If either needs editing, stop and re-rule. |
| Arm test fixture `overlap: { ..., top3: [...] }` (`compound-promote-create-arm.test.ts` L675, L765) suggests a `top3` field exists | `CreateVerdict.overlap` is `{ top1Name, top1, nearestRank }`; `top3` appears only in two test fixtures, not in source. | Do not add a `top3` field to the verdict. The fixtures are inert extra properties; leave them. |

## Research Insights

### Premise Validation (Phase 0.6)

- Issue #10550 is OPEN (title "feat(harness): WikiSkill Phase 2 - gated new-skill creation (split from #8281)");
  PR #11521 is this branch's open draft. No other open PR names #10550; the collision pre-check reported only
  foreign `test-all.sh` processes in unrelated worktrees (no PR hit).
- Cited paths and symbols exist on this branch: `apps/web-platform/server/compound-promote-create.ts`
  (`OVERLAP_TOP_K`, `rankOverlap`, `proposalOverlapText`, `prepareCreate`, `checkCreate`),
  `compound-promote-create-arm.ts` (`proposeOffered` calls `prepareCreate` then `checkCreate`),
  `compound-promote-marker.ts` (`CREATE_MARKER_NUMBERS`, `CREATE_SENTRY_ONLY_NUMBERS`), the runbook row
  "`refused`, `prefer-patch`, `nearest-not-top3`".
- ADR corpus (Phase 0.6 item 4): ADR-092 carries a 2026-10-28 amendment "a ledger-owned pattern is not offered to the
  model" (pre-call prompt-input shaping) and ADR-300 rejects "tell the model which clusters were rejected" because
  PR-derived text in a prompt is an injection path. Candidate skill NAMES come from the repo's own skills (the same
  source as the skill list already in the prompt), not from PR text, so ADR-300's rejection does not apply. Neither
  ADR rejects a candidate list.
- Prior rulings still binding: the 2026-10-28 and 2026-10-29 records forbade touching the prompt, bar, evidence,
  schema, `OVERLAP_*` or the `nearest_skill` gate until a live `nearest-not-top3` row appeared; live-fire 6 is that
  row, and the named follow-up is this change.

### Measurements taken at plan time (read-only; no model call, no cron)

Command: a scratch script outside the repo that imports `countDescriptionWords`, `rankOverlap` and `prepareCreate`
from `apps/web-platform/server/compound-promote-create.ts` and reads `knowledge-base/project/patterns/*.md`
(run with `bun run <scratch>/probe.ts` from `apps/web-platform`).

- Population: 105 skills with a SKILL.md, 8 of them `disable-model-invocation` (hidden from the model); 7 open patterns.
- Current create prompt: 29,207 bytes for all 7 patterns. The ceiling counts only index + skill block (about 7.1k of
  the 12,000-token bound), leaving about 4.8k tokens of headroom. The new block adds well under 1 KB.
- Pattern-keyed top-3 (title + summary + tags; visible skills; scores in parentheses):
  verification-scaffolding-carries-the-defect: test-fix-loop (.106), verification-scaffold (.097), fix-issue (.091);
  mutation-score-is-not-predicate-correctness: cron-delete (.065), linear-fetch (.051), agent-native-audit (.051);
  failure-signal-never-reaches-a-human: test-browser (.088), flag-create (.056), test-fix-loop (.055);
  guard-pins-artifact-not-wiring: atdd-developer (.109), gemini-imagegen (.099), flag-list (.092);
  instrument-answers-instead-of-failing: operator-digest (.053), flag-list (.052), eval-harness (.048);
  early-exit-reader-under-pipefail: fix-issue (.071), kb-search (.057), operator-digest (.054);
  fixture-cannot-distinguish-the-cases-it-claims: test-fix-loop (.072), heal-skill (.059), operator-bootstrap (.052).
- Reading: every pattern gets three positive-score candidates, but scores are weak (0.05 to 0.11) and some are
  semantically odd (gemini-imagegen for a test-pinning pattern). That is why the CTO added the `no_action` escape
  hatch (F1): a model forced to name one of three poor candidates would write a wrong `nearest_skill` into the PR
  body. Adding evidence-slug words to the ranked text changed the lists only slightly and sometimes made them worse
  (F2).

### Property List and Cut List (Phase 0.6b)

Properties the ask is really after:

1. The model is shown, before it answers, the same skills the gate will accept as `nearest_skill`.
2. The gate is unchanged: `nearest-not-top3` still refuses a model that names a skill outside the server's top three.
3. The next live row can tell "the model ignored the list" from "the listed candidate did not survive the re-rank".
4. Everything the model is sent is counted by the input ceiling (refuse, never truncate).

| Mechanism considered | Property | Already covered by | Disposition |
|---|---|---|---|
| Accept the pattern-keyed candidates as valid `nearest_skill` too (OR in the gate) | 1 | nothing, and it is a loosening | CUT (forbidden by the brief) |
| Second corrective call with the real top-3 from the proposal text | 1 | the arm is one call, no retry (ADR-092) | CUT (CTO F1: option C; flip condition recorded) |
| Instruct the model to write in the candidates' vocabulary | 1 | nothing | CUT (CTO F1: option B pushes toward the 0.16 overlap refusal) |
| New marker field for candidate membership | 3 | Sentry `extra` already carries refusal `numbers` | CUT (CTO F4: Sentry-only number, marker shape unchanged) |
| Candidates keyed on evidence slugs | 1 | pattern title/summary/tags is what the model sees | CUT (CTO F2) |
| Pure function for the candidates, a fenced block, bullets, a Sentry-only number, runbook and ADR-092 paragraph | 1, 3, 4 | n/a | KEEP |

### Institutional learnings applied

- `2026-10-28-a-filter-that-runs-after-the-single-decision-cannot-protect-the-decision.md`: a gate placed after a
  one-shot decision rejects, it does not redirect; any fact known beforehand belongs in the input. Here the fact
  (the ranking) depends partly on the decision itself, which is why the list is a proxy and why the plan names the
  residual instead of claiming a fix.
- `2026-10-28-a-new-telemetry-field-is-read-through-its-reading-guide-and-the-guide-omitted-the-catch-arm.md`: the
  reading guide for `nearest_in_offered` must list every path that carries it and every path that does not (see the
  runbook task and AC9).
- `2026-10-29-a-marker-reading-rule-is-a-set-of-claims-and-the-premise-i-briefed-was-the-first-false-one.md`: verify
  each claim in the runbook row against source before writing it.

## Open Code-Review Overlap

None. (Two-stage `gh issue list --label code-review --state open` and a standalone `jq --arg path` check against
each file in Files to Edit returned no open scope-out naming them; recorded again at deepen time.)

## Architecture Decision (ADR/C4)

### ADR

No new ADR. Amend ADR-092 by ONE paragraph, "Amendment, 2026-10-29 (#10550): the prompt shows the server's per-pattern
top-3 candidate skills", placed after the 2026-10-28 amendment. It states: the prompt gains a fenced `create-candidates`
block of skill names the server ranks closest to each offered pattern; the gate is unchanged; the list is keyed on
pattern text while the gate ranks proposal text, so it reduces but does not remove `nearest-not-top3`; the block
carries repo skill names only, so ADR-300's rejected "tell the model which clusters were rejected" alternative does
not reopen; the effect on whether a create PR opens is unmeasured until a live-fire. No `CREATE_STAGE_ORDER` id
changes (the candidates are computed inside the `model` stage input), so the parity suite is unaffected.

### C4 views

No C4 impact. Checked against `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`: (a)
external human actors: none added (the operator reading the runbook is unchanged); (b) external systems: the
Anthropic API call, Better Stack and Sentry edges already exist and carry no new data class (skill names were
already in the prompt); (c) containers and stores touched: none new; the arm lives inside the existing web-platform
container (`model.c4` models the cron's GitHub edge, line 741, and nothing finer); (d) actor-to-surface access
relationships: none change. Counts: no derived cardinality in `model.c4` moves, confirmed by running
`bash plugins/soleur/test/c4-count-parity.test.sh` (AC12).

### Sequencing

The ADR paragraph describes the target state at merge; it lands in this PR, not a follow-up.

## Implementation Phases

Write the failing tests first (`cq-write-failing-tests-before`), then the code.

### Phase 1 - Tests first (RED)

All in `apps/web-platform/test/server/compound-promote-create.test.ts` unless noted; a new `describe` block
"create candidates: the prompt shows the gate's own ranking" placed after the `prepareCreate` describe.

1. Equality with the gate: for each fixture pattern, `createCandidates(page, SKILLS)` equals an INDEPENDENT recompute
   built from gate primitives only (`rankOverlap(patternOverlapText(page), SKILLS)`, drop skills whose
   `disableModelInvocation` is true, drop score 0, take `OVERLAP_TOP_K`). The test does not call the function under
   test to build its expectation.
2. A hidden top scorer is never listed: a pattern whose text equals a hidden skill's description ranks that skill
   first in the raw ranking and the candidate list excludes it.
3. IDF population: a synthetic fixture where ranking over visible-only skills orders two skills differently from
   ranking over all skills; the candidates follow the all-skills order (the gate's order).
4. Zero score yields no candidate; a pattern with two positive scores lists two (the must-PASS non-canonical input);
   a pattern with none gets no line in the block and the prompt carries the "no line, do not create from it" bullet.
5. Per-offered only: `prepareCreate` with two patterns lists two lines; with one, one line; the block never names a
   pattern that is not in `args.patterns`.
6. Fenced: the prompt contains `<<<BEGIN-${nonce}:create-candidates>>>` and its END marker, in this order: pattern
   index, candidates block, skill list.
7. Ceiling counts the block: on an over-ceiling fixture the refusal `numbers.bytes` equals the byte length of the
   pattern index + the candidates block + the skill block, each rebuilt independently; and a fixture that fits with
   the block omitted but overflows with it is refused.
8. Prompt rules: the existing anchored sentence regex (~L1246) still matches; new bullets are asserted in anchored
   sentences built from `OVERLAP_TOP_K` and `CREATE_NO_ACTION_REASONS` (the escape hatch names `no-pattern-qualifies`,
   asserted to be a member of the constant).
9. `nearest_in_offered`: on `nearest-not-top3`, value 1 when `nearest_skill` is in the named pattern's listed set,
   0 when it is a visible skill outside it; the fixture picks a listed candidate that the proposal text pushes below
   rank 3 (found programmatically, asserting the precondition). Absent on `overlap`, `nearest-missing`,
   `open-pr-nearest`, and absent when the pattern had no candidates. With two patterns, the membership check uses the
   pattern the model NAMED, not the first.
10. `compound-promote-marker-numbers.test.ts`: the census passes with `nearest_in_offered` in
    `CREATE_SENTRY_ONLY_NUMBERS`, and `CREATE_MARKER_NUMBERS` has no `nearest_in_offered` key (marker shape unchanged).

Run them and confirm they fail for the right reason (missing exports), before Phase 2.

### Phase 2 - Pure module (`compound-promote-create.ts`)

1. Add exported, with a doc comment each:
   - `patternOverlapText(p: { title; summary; tags })`: `title summary tags` joined with spaces (F2).
   - `hiddenSkillNames(skills)`: the set of `disableModelInvocation` names. ONE expression, used by `checkCreate`
     (replacing its inline `hidden` set) and by the candidates (F3).
   - `createCandidates(page, skills)`: `rankOverlap(patternOverlapText(page), skills)` over ALL skills, drop hidden,
     keep `score > 0`, first `OVERLAP_TOP_K` names.
2. `prepareCreate`: compute candidates for `args.patterns` (the offered set), render one line per pattern with at
   least one candidate, `<pattern_slug>: a, b, c`, into `fenceBlock(nonce, "create-candidates", lines)` (body `none`
   when no line), insert it after the pattern index and before the skill block, and include its bytes in
   `inputBytes` (F5). Keep every existing line verbatim, including "your nearest_skill must be among the server's top
   3 matches". Add three bullets next to the existing overlap bullet:
   - the block lists, per pattern, up to `OVERLAP_TOP_K` existing skills the server ranks closest by word overlap;
     set `nearest_skill` to one listed for the `pattern_slug` you chose; the server then ranks your own slug,
     description and when_to_use against every skill, so a listed skill can still fall outside the top
     `OVERLAP_TOP_K`;
   - a pattern with no line in the block has no near skill the server can name: do not create from it;
   - if none of the listed skills is a genuine nearest skill for the pattern, return no_action with reason_class
     `no-pattern-qualifies`.
3. `checkCreate`: in the `nearest-not-top3` branch only, compute `createCandidates(page, c.skills)`; when non-empty
   add `nearest_in_offered: includes(p.nearest_skill) ? 1 : 0` to the refusal `numbers`. The returned class, detail
   and the `nearest_rank` / `top1` values are unchanged.

### Phase 3 - Marker allowlist (`compound-promote-marker.ts`)

Add `"nearest_in_offered"` to `CREATE_SENTRY_ONLY_NUMBERS`. The marker shape (`CREATE_MARKER_NUMBERS`,
`CompoundPromoteOutcome`) does not change. Mention it in no other comment in the file (the discoverability probe
counts occurrences).

### Phase 4 - Runbook and ADR

1. `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md`, row "`refused`, `prefer-patch`,
   `nearest-not-top3`": replace the follow-up cell. New content: the prompt now supplies the server's per-pattern
   top-3 candidates (title, summary and tags ranked with the gate's own `rankOverlap`, hidden skills dropped, a zero
   score never listed); the lists are lexical and the gate re-ranks the proposal text, so a repeat is possible. Read
   the Sentry `create-refused` event's `extra.nearest_in_offered`: absent means no candidates were offered for that
   pattern (or the row predates this change); `0` means the model named a skill outside the list; `1` means the
   listed skill did not survive the re-rank, and `1` on a second live row opens a plan for a server-side single
   re-rank as its own PR with a fresh ruling. State that no PR-opening effect is claimed until a live-fire clears.
   Per the telemetry learning, list the paths that carry the number (only `nearest-not-top3`, only with candidates)
   and every path that does not.
2. In the field table near `create_top1` / `create_nearest_rank`, add one clause pointing at that row for the Sentry-only
   `nearest_in_offered` (single home; no second copy of the reading rule).
3. ADR-092: add the amendment paragraph from the Architecture section.

### Phase 5 - Verify (GREEN) and measure

1. `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/compound-promote-create.test.ts
   test/server/compound-promote-create-arm.test.ts test/server/compound-promote-create-parity.test.ts
   test/server/compound-promote-marker-numbers.test.ts test/server/compound-promote-runbook-parity.test.ts
   test/server/compound-promote-create-snapshot.test.ts test/server/compound-promote-create-gates.test.ts` and
   `./node_modules/.bin/tsc --noEmit` (the package's own runner and compiler, not `npm -w`); then the repo's
   markdownlint on the two edited docs.
2. Re-run the plan-time probe against the final code: every open real pattern still gets at least one candidate, and
   `prepareCreate` stays `ready` (record the byte count; expect about 29.5 KB).
3. `git diff origin/main...HEAD -- apps/web-platform/test/server/compound-promote-create.test.ts` shows no removed or
   altered line in the existing gate tests (~L984-1005) or the anchor regex (~L1246): additions only.

### Phase 6 - Ship, deploy, postmerge (pipeline stages, not this planning run)

PR body: "Ref #10550" (never "Closes"), says the change shows the server's candidates to the model, leaves the gate
unchanged, is expected to reduce but not remove `nearest-not-top3`, and claims no PR will open. Render
`decision-challenges.md`. After merge: verify the deploy (code change = merged PR, deploy verified, then
`soleur:postmerge`). The live-fire is an operator-held step (see Operator Holds) and is not run by any stage here.

## Operator Holds

- Live-fire of `cron-compound-promote` with `{"input":"patterns","allow_create":true}` after the deploy is verified:
  needs the operator's separate, explicit go-ahead naming the action; each go-ahead authorises exactly one run. Not
  performed by planning, work, ship or postmerge.

## Files to Edit

- `apps/web-platform/server/compound-promote-create.ts`
- `apps/web-platform/server/compound-promote-marker.ts`
- `apps/web-platform/test/server/compound-promote-create.test.ts`
- `apps/web-platform/test/server/compound-promote-marker-numbers.test.ts` (add the `CREATE_MARKER_NUMBERS` negative assertion)
- `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md`
- `knowledge-base/engineering/architecture/decisions/ADR-092-additive-only-auto-edit-boundary-and-hard-rule-body-weakening-gate.md`

Must NOT change: `compound-promote-create-arm.ts`, `compound-promote-patterns.ts` (`renderPatternIndex` is shared with
the patterns arm and stays byte-identical), `cron-compound-promote.ts`, `CREATE_MARKER_NUMBERS`, `OVERLAP_TOP_K`,
`OVERLAP_REFUSE_THRESHOLD`, `CREATE_OUTPUT_SCHEMA`.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-wikiskills-top3-candidates/decision-challenges.md` (written by the planner)
- `knowledge-base/project/specs/feat-one-shot-wikiskills-top3-candidates/tasks.md` (written by the planner)
- this plan

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "supply the server's per-pattern top-3 candidate skills in the create-arm prompt so the model can name a valid nearest skill" | Phase 2 items 1-2, Phase 1 tests 1-8 | mapped |
| 2 | "This is NOT a loosening of the gate; the nearest-not-top3 check must stay intact (and its tests must keep passing)" | Phase 2 item 3 (refusal unchanged), Phase 5 item 3, Files "Must NOT change" | mapped |
| 3 | "the PR body says \"Ref #10550\", never \"Closes\"" | Phase 6 | mapped |
| 4 | "Do NOT fire cron-compound-promote or any manual trigger" | Operator Holds | mapped |
| 5 | "Do not claim this fix will open a PR; its effect is unmeasured until a live-fire clears" | Overview, runbook task, Phase 6 | mapped |
| 6 | "Technical forks go to the soleur:engineering:cto agent" | decision-challenges.md F1-F6 | mapped |
| 7 | "Code change = merged PR, deploy verified, then postmerge." | Phase 6 | mapped |
| 8 | "Do not touch or comment on other issues" | Overview, Phase 6 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `createCandidates` + fenced block + bullets | "supply the server's per-pattern top-3 candidate skills in the create-arm prompt" | asked |
| `nearest_in_offered` Sentry-only number | - | inferred - justification: CTO F4 ruled it is the only way to tell "model ignored the list" from "list did not survive the re-rank", and the brief requires the effect to be measured before it is claimed |
| `no_action` escape hatch bullet | - | inferred - justification: CTO F1 ruled weak candidates (scores 0.05 to 0.11) would otherwise push the model to name a wrong `nearest_skill` into the PR body |
| ADR-092 amendment paragraph | - | inferred - justification: ADR-092 already carries a parallel 2026-10-28 amendment on pre-call prompt input; CTO F6 ruled a one-paragraph amendment |
| Runbook row update | "Per the compound-promote runbook (...the 'refused, prefer-patch, nearest-not-top3' row)" | asked |

### Split Assessment

- Subsystems touched: 2 - apps/web-platform, knowledge-base
- Planned files: 6 edited + 3 planning artifacts | Estimated changed lines: about 330 (tests about 220)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. The create arm is manual-only and dark; at
  worst a live-fire spends one model call that ends `refused` or `no_action`, or the prompt is refused by the input
  ceiling (`input-size`) before any call.
- **If this leaks, the user's data is exposed via:** no vector. The new block carries only repo skill names, already
  present in the prompt's skill list; no user data, secret or PR-derived text is added, and the number is Sentry-only.
- **Brand-survival threshold:** none
- **Threshold decision (challengeable):** an internal, manual-only arm with a human-reviewed draft PR as its only
  output; the change adds prompt text and one telemetry number and moves no data, credential or user-facing surface.

threshold: none, reason: the diff touches apps/web-platform/server only to add repo skill names to an internal
model prompt and one Sentry-only refusal number; no auth, schema, API route, credential or user data path changes.

## Guard Contract

### Guard 1 - Candidates shown equal the gate's own ranking

**Property.** For every offered pattern, the skills named in the `create-candidates` block are exactly the first
`OVERLAP_TOP_K` positive-score, model-visible skills that the gate's ranking function returns for that pattern's text,
and every byte the model is sent is counted by the input ceiling.

**Assembly.** Two call sites flow through ONE chokepoint: `prepareCreate` (renders the list) and `checkCreate`
(`nearest_in_offered` membership) both call `createCandidates`, which calls `rankOverlap` over `c.skills` / `args.skills`
(the full population, so IDF matches the gate) and `hiddenSkillNames` (the same expression `checkCreate`'s own
nearest-rank filter uses). The ceiling window is `inputBytes` in `prepareCreate`: pattern index + candidates block +
skill block. Members drift (patterns, skills); the structure is the shared helpers. Anything else that builds a list of
skill names for the prompt is a defect.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the hidden-skill filter inside `createCandidates` | RED (test 2: a hidden top scorer is listed) |
| 2 | Rank over visible-only skills instead of all skills (IDF population differs) | RED (test 3: order differs from the gate's) |
| 3 | `prepareCreate` renders no block, or an empty body for a pattern that has candidates (the guard's own dispatch) | RED (tests 4-6: a pattern with positive scores has a line) |
| 4 | Render a line only for the first offered pattern (stops at the first member) | RED (test 5: two patterns, two lines) |
| 5 | Measure `inputBytes` before the block is added | RED (test 7: bytes equal index + block + skill block; the fit-without/overflow-with fixture is not refused) |
| 6 | `nearest_in_offered` always 1, or computed from the first pattern instead of the named one | RED (test 9: both values and the two-pattern case) |
| 7 | List score-0 skills (alphabetical zero-score ties) | RED (test 4) |

**Harness rows.** Suite edit that must go RED: change test 1's expected list to include a hidden skill, or delete the
independent recompute and compare the function to itself - the harness self-check describe ("the instrument can
fail") gains a row asserting test 1 is not tautological (its expectation is built from `rankOverlap` and the fixture
flags, never from `createCandidates`). Must-PASS non-canonical input: a pattern with only two positive-score skills
lists exactly two and the prompt is still `ready`.

**Anchor.** No stored value is compared; both sides are computed at test time from the same fixtures. The independent
recompute uses gate primitives, so a change to `createCandidates` alone cannot make both sides move together.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_COMPOUND_PROMOTE_OUTCOME marker row (Better Stack) on every cron-compound-promote run, carrying create_arm, create_outcome, create_refusal_class, create_detail, create_offered
  cadence: per run (weekly cron plus operator-authorised manual triggers)
  alert_target: Better Stack log query in the compound-promote runbook, and the Sentry create-refused issue stream
  configured_in: apps/web-platform/server/compound-promote-marker.ts
error_reporting:
  destination: Sentry op create-refused (extra carries class, detail and the refusal numbers, now including nearest_in_offered)
  fail_loud: create_outcome=refused with create_refusal_class=prefer-patch and create_detail=nearest-not-top3 on the marker
failure_modes:
  - mode: listed candidates do not survive the proposal re-rank, so nearest-not-top3 repeats
    detection: Sentry create-refused extra.nearest_in_offered equals 1 on a nearest-not-top3 row
    alert_route: Sentry issue stream plus the runbook reading row (a second such row opens the single re-rank plan)
  - mode: the model ignores the list and names an unlisted skill
    detection: Sentry create-refused extra.nearest_in_offered equals 0
    alert_route: Sentry issue stream plus the runbook reading row
  - mode: the new block pushes the input over the ceiling
    detection: marker create_outcome=refused, create_refusal_class=input-size with create_tokens and create_max
    alert_route: Better Stack marker row, runbook input-size entry
  - mode: weak candidates push the model to decline every pattern
    detection: marker create_outcome=no_action with create_no_action_reason=no-pattern-qualifies and create_offered above 0
    alert_route: runbook reading table (a decline is the intended default; no code follow-up)
logs:
  where: Better Stack (marker row) and Sentry (create-refused event)
  retention: per the Better Stack and Sentry plans already in use; nothing new is stored
discoverability_test:
  command: grep -c nearest_in_offered apps/web-platform/server/compound-promote-marker.ts
  expected_output: "1"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected - an internal prompt-input and telemetry change to a manual-only engineering
arm. Engineering was consulted through the CTO ruling (decision-challenges.md F1-F6), which is the technical-fork
mechanism, not a domain-leader review. No UI surface, no legal, finance, marketing, sales or support effect.

## Acceptance Criteria

### Pre-merge (PR)

1. `git diff --name-only origin/main...HEAD` lists only the Files to Edit, the three planning artifacts, the pipeline-written
   `knowledge-base/INDEX.md` and `specs/feat-one-shot-wikiskills-top3-candidates/session-state.md` when present, and nothing
   under `.github/`, `plugins/`, `scripts/` or `apps/web-platform/server/inngest/`.
2. Gate intact: the existing gate tests (~L984-1005) and the prompt anchor regex (~L1246) of
   `compound-promote-create.test.ts` pass with no removed or altered line; `OVERLAP_TOP_K` is still 3 and
   `OVERLAP_REFUSE_THRESHOLD` is still 0.16 (their constant tests are unchanged).
3. `createCandidates` equals the independent recompute for every fixture pattern; a hidden skill is never listed; a
   zero score is never listed (tests 1-4).
4. The prompt contains one fenced `create-candidates` block between the pattern index and the skill list, one line per
   offered pattern that has a candidate, and nothing for a pattern that is not offered (tests 5-6).
5. The input ceiling counts the block: the refusal `numbers.bytes` equals index + block + skill block (test 7).
6. The three new bullets are present, built from `OVERLAP_TOP_K` and `CREATE_NO_ACTION_REASONS`, and the existing
   "your nearest_skill must be among the server's top 3 matches" sentence is byte-identical (test 8).
7. `nearest_in_offered` is 0 or 1 on `nearest-not-top3` with candidates, absent on every other refusal and when no
   candidate was offered; it is in `CREATE_SENTRY_ONLY_NUMBERS` and not in `CREATE_MARKER_NUMBERS`; the marker-numbers
   census passes (tests 9-10).
8. `renderPatternIndex` and `compound-promote-patterns.ts` are byte-identical to `origin/main`
   (`git diff origin/main -- apps/web-platform/server/compound-promote-patterns.ts` is empty).
9. The runbook row names the candidates, the residual risk, the three readings of `nearest_in_offered` (absent, 0, 1),
   the paths that carry it and the paths that do not, and claims no PR-opening effect; every backticked token in the
   edited row is a real field, enum member or detail token (runbook parity suite green).
10. ADR-092 gains exactly one amendment paragraph and the parity suite
    (`compound-promote-create-parity.test.ts`) stays green.
11. The vitest files in Phase 5 item 1, `npx tsc --noEmit` and markdownlint on the edited docs pass.
12. `bash plugins/soleur/test/c4-count-parity.test.sh` passes.
13. The PR body says "Ref #10550", never "Closes", does not say the change fixes `nearest-not-top3` or that a PR will
    open, and renders `decision-challenges.md`. No comment is posted to or on #10550 or any other issue.
14. The cron was not fired and `soleur:trigger-cron` was not run by any stage of this change.

### Post-merge (pipeline, not an operator step)

15. The deploy is verified for the merge commit (release workflow green, running image is the merge build), then
    `soleur:postmerge` runs. No live-fire is part of either; it stays an Operator Hold.

## Test Scenarios

Layers: all `unit` (pure functions and prompt rendering), plus the existing arm test as the `integration` check that
the model call is exactly `prepareCreate` over the offered patterns (it recomputes with `prepareCreate`, so it stays
green by construction and needs no edit).

- Given a pattern whose text matches a hidden skill best, when candidates are computed, then the hidden skill is
  absent and three visible skills are listed.
- Given a pattern with no overlapping stems, when `prepareCreate` renders, then the pattern has no line and the prompt
  says not to create from it.
- Given a model proposal that names a listed candidate which the proposal text ranks 5th, when `checkCreate` runs,
  then it refuses `prefer-patch/nearest-not-top3` with `nearest_in_offered: 1` (regression: the gate still refuses).
- Given a model proposal naming a visible skill outside the list at rank 4, then `nearest_in_offered: 0`.
- Given a proposal that overlaps at or above the threshold, then `overlap` refuses and carries no `nearest_in_offered`.
- Given 600 padded skills, when `prepareCreate` runs, then `input-size` with `numbers.bytes` including the block.

Browser / API verification: none (no UI, no external service call in tests).

## Sharp Edges

- The census test (`compound-promote-marker-numbers.test.ts`) reads number keys in `refuse(...)` calls; the new key
  must be in `CREATE_SENTRY_ONLY_NUMBERS` in the same commit or the census reddens.
- The discoverability probe counts occurrences of `nearest_in_offered` in `compound-promote-marker.ts`; keep exactly
  one (the array entry), no comment mention.
- `checkCreate` passes ALL open patterns to the context while the model is offered a subset; the membership check
  recomputes from the pattern the model NAMED (`page`), so it works for an unoffered pattern too. In that case the
  ledger backstop usually ends the run earlier; do not special-case it.
- Step B re-runs `checkCreate` on the refreshed clone, so a refusal there can carry a different `nearest_in_offered`
  from Step A's; this is telemetry on a refusal, not a gate input.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6. This one declares threshold `none` with the scope-out reason.
- Do not add the `top3` property seen in two arm-test fixtures to `CreateVerdict.overlap`; it is not a source field.
- `prepareCreate` is create-arm only; do not route the candidates through `renderPatternIndex` (the patterns arm shares
  it, and its prompt bytes must not move).

## Ruling Record

All technical forks (F1-F6) were ruled by the CTO agent on 2026-10-29; the full rows are in
`knowledge-base/project/specs/feat-one-shot-wikiskills-top3-candidates/decision-challenges.md`. The operator is asked
no technical question. The only operator-owned items are the post-deploy live-fire go-ahead and enabling the arm on
the weekly cron, neither of which this change performs.
