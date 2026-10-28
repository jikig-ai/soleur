---
title: "fix(create-arm): drop ledger-owned patterns from the offered list before the single model call"
type: fix
date: 2026-10-28
slug: create-arm-prefilter-ledger-owned-patterns
branch: feat-one-shot-10550-create-arm-prefilter-owned
issue: 10550
lane: cross-domain
brand_survival_threshold: none
---

# fix(create-arm): drop ledger-owned patterns from the offered list before the single model call

## Enhancement Summary

**Deepened on:** 2026-10-28
**Sections enhanced:** Research Insights (deepen-pass verification), Phase 2 tests, Phase 3 docs, Guard Contract
**Reviewers used:** DHH, Kieran and code-simplicity plan reviewers (plan-review), then the deepen-plan halt gates run directly

### Key Improvements

1. Test specs made implementable against the real helpers (typed prompt read from the `post` mock; nonexistent `repoRoot` in T2 so
   the before-I/O ordering is actually pinned; T3 second half has the ledger own the same-run pattern so a ledger-first
   order goes RED).
2. The H2 RED reason corrected (only the prompt assertion is RED on unfixed source) and T4/handler-rename/ADR-tail/Guard
   Contract trimmed to what discriminates.
3. ADR parity hazard made explicit (no `STAGE_PHRASES` anchor in the tail; run the parity test after each ADR edit).

### New Considerations Discovered

- Edit-loop `ledger-suppressed` refusals are part of `sameRunHashes`, so `other` vs `all-owned` for those is decided by the
  same-run stage; the runbook must say so.
- A model may itself return `all-owned`; the runbook row must not describe `all-owned` as server-side only.

Ref #10550 (the issue stays open; this PR never closes it).

## Overview

The gated create arm of `cron-compound-promote` (WikiSkill Phase 2) makes ONE model call (no retry) over the
patterns it offers. Today `proposeInner` in `apps/web-platform/server/compound-promote-create-arm.ts` offers every
pattern except the hashes the edit loop recorded this run, and only AFTER the call does `checkCreate` (gate 5,
`isHashSuppressed`) apply the ledger. The model is never told which patterns a prior open, merged or recently closed
promotion PR already owns, so it can pick the one owned pattern; the gate then ends the run `no_action` / `other`
with every other pattern never evaluated.

Observed on the first live-fire after the slot reservation: manual fire 2026-10-28 09:38Z, run
`01M60XZRYG9ADVEWAY07HEQ5JK`, marker `create_arm=ran`, `create_outcome=no_action`,
`create_no_action_reason=other`, `ledger_suppressed=1` (a `refusal_detail` entry with cluster hash
`92ac0c4a7baa2996bbe32d2c7b540719178634fe0324a54c607f3fa86229f428`, reason `ledger-suppressed`), `patterns_open=7`,
`create_pr=null`. The slot reservation worked and the arm was reached; one pattern owned by open PR #11291 won the one
call and six were never evaluated.

This is a reachability defect with the same shape as the slot starvation fixed on 2026-10-27
(`2026-10-27-a-shared-cap-let-the-mandatory-loop-starve-the-gated-arm.md`): a fact that is known BEFORE the
decision (which hashes are owned) is applied only AFTER it.

The fix is the CTO-ruled minimal design (decision recorded in
`knowledge-base/project/specs/feat-one-shot-10550-create-arm-prefilter-owned/decision-challenges.md`):

1. In `proposeInner`, compute `runNow = new Date(a.runStartedAt)` BEFORE the filter and extend the `offered` filter to
   also drop every pattern for which `decideSuppression({ entries: a.ledgerEntries, hash, now: runNow })` is true (the
   same predicate and the same memoized clock the gate uses, moved ahead of the call).
2. Keep the post-call `isHashSuppressed` gate in `checkCreate` as a backstop for a model that names an unoffered
   pattern anyway (`checkCreate` still receives the FULL `a.patterns` list, so the backstop is unchanged).
3. If the offered list is empty BECAUSE of the ledger, return `{ kind: "no_action", reason: "all-owned" }`
   (`all-owned` is already in `CREATE_NO_ACTION_REASONS`; no marker change). The same-run empty case stays
   `{ kind: "no_action", reason: "other" }` (existing tests pin it).
4. Pre-filtered hashes do NOT increment `ledger_suppressed` (the runbook defines that counter as clusters dropped);
   no new marker field, refusal class or detail token.

Whether the model then picks one of the other six patterns, and whether the gates (prefer-patch, budget, collision)
accept it, is UNMEASURED until a live-fire clears. This PR removes the structural cause of the observed
`no_action`; it does not claim a PR will open.

## Research Insights

### Premise Validation (Phase 0.6)

- #10550 is OPEN (`gh issue view 10550`: state OPEN, no closing PR). Draft PR #11394 is this branch's own WIP PR; it is
  the only open change naming #10550 (collision pre-check hit, exit 10, benign: foreign `test-all.sh` processes belong to
  an unrelated worktree `feat-one-shot-8628-inngest-4-upgrade`).
- PR #11291 (`self-healing/auto-92ac0c4a...-2026-10-27`) is the open PR that owns the observed hash. It is the ledger
  fact, not a collaborator: leave it alone (no merge, close, comment, push).
- Cited code verified on this branch: `proposeInner` builds `offered` from `sameRun` only
  (`compound-promote-create-arm.ts` "const offered = a.patterns.filter"), the later `const runNow = new Date(a.runStartedAt)`
  sits after the model call, and `isHashSuppressed: (hash) => sameRun.has(hash) || decideSuppression(...)` is passed to
  `checkCreate` with the full `a.patterns`. `checkCreate` gate "ledger" returns `{ kind: "suppressed", clusterHash }`.
  `all-owned` is in `CREATE_NO_ACTION_REASONS` (`compound-promote-create.ts`) and in the handler's marker type already;
  the handler maps any `no_action` verdict to `create_outcome=no_action` plus `create_no_action_reason=<reason>`
  (`cron-compound-promote.ts` "if (proposed.kind === \"no_action\")"), so no handler or marker edit is needed.
- ADR-corpus check (mechanism: filter before the model call): ADR-092 create-arm amendment already records "a pattern the
  edit loop already recorded this run is not offered" as a Step A stage; this plan extends that stage rather than
  contradicting an ADR. Nothing in the ADR's Alternatives rejected a pre-filter.
- `decideSuppression` fails closed on an unusable clock (a NaN `runNow` suppresses any hash that has ANY entry); the
  pre-filter uses the same predicate and clock as the gate, so it drops exactly the set the gate would suppress, including
  on a garbled `runStartedAt`.

### Property List (Phase 0.6b)

1. A pattern whose cluster hash the ledger would suppress at the gate is never shown to the model.
2. A different, ledger-clean pattern can reach `create` when a ledger-owned one is among the offered candidates.
3. When the ledger leaves nothing offerable, the arm ends cleanly with no model call, no spend and the reason
   `all-owned`.
4. The same-run (edit loop) empty case, the scheduled path, the corpus path and the edit loop are unchanged.
5. A model that names an unoffered owned pattern is still suppressed, never created (the backstop).
6. The marker's counters keep their meaning: `ledger_suppressed` counts clusters dropped (edit-loop refusals and
   backstop hits), not pre-filtered offers.

### Cut List

- New marker field such as `offered_count` or `ledger_prefiltered` (-> property 6 / ruling: no new marker fields; the
  existing `patterns_open` plus `create_no_action_reason=all-owned` already give the operator the signal).
- A second model call or retry when the model names an owned pattern (-> property 2; covered by not offering it).
- Telling the model "these hashes are owned" in the prompt (-> property 1; omission from the list is stronger and cheaper
  than an instruction, and a threshold living only in a prompt is a request, not a constraint).
- Passing only `offered` to `checkCreate` (-> property 5; would turn a model naming an owned pattern into
  `model-invalid/unknown-pattern` and drop the backstop's `suppressed` verdict).
- A new `CREATE_STAGE_ORDER` stage id (-> property 1; the ledger drop lives inside the existing `same-run` stage, which
  keeps the ADR parity test and the condition-peeling test unchanged).

### Relevant institutional learnings

- `2026-10-27-a-shared-cap-let-the-mandatory-loop-starve-the-gated-arm.md`: same defect shape; its Key Insight (a test whose
  headline scenario ends in the refusal is a reachability bug written down) applies to the G4 ledger tests.
- `2026-10-26-a-create-arm-for-model-authored-public-files-needs-prompt-check-parity-and-a-refreshed-base.md`: the prompt
  and `checkCreate` must agree on the candidate set; this change makes them agree for the ledger fact.
- `2026-10-20-a-threshold-that-lives-only-in-a-prompt-is-a-request-not-a-constraint.md`: do not "tell" the model; remove
  the option.
- plan Sharp Edges: an Inngest step that keeps its return TYPE needs no shape-tolerant reader, and a "byte-identical"
  claim must list the inputs it touches (both stated in the Phase 1 safety notes below).

### Deepen-pass verification (2026-10-28)

Run directly (no agent fan-out: one 15-line function, one binding ruling; the plan-review panel of three already
fanned out). Commands and results:

- Halt gates 4.6 (User-Brand Impact present, threshold `none` with the sensitive-path scope-out bullet), 4.7 (all five
  Observability fields present; the probe verb is `grep`; no suite-shaped regex hit; `expected_output` is the literal
  `all-owned`), 4.8 (no PAT-shaped token), 4.11 (`python3 scripts/lint-guard-contract.py <plan>` exit 0), 4.12 (one
  unfenced `## Scope Check`, one `Recommendation:` line): all pass. 4.9, 4.10, 4.13 and 4.55 do not trigger (no UI file,
  no `.tf` / migration, no new autonomous task, no downtime-inducing operation).
- Cited rule ids: none are cited, so there is nothing to verify against `AGENTS.md`. Cited PRs and issues:
  `gh pr view 11291` OPEN with head `self-healing/auto-92ac0c4a...-2026-10-27` (the attribution "PR #11291 owns the
  observed hash" holds: the hash is in its branch name); `gh pr view 11394` OPEN, head is this branch (own WIP PR);
  #10552 CLOSED (do not touch). #10551, #8293, #8443, #11183, #10676, #11228 appear only in the do-not-touch list.
- Probe can fail: `grep -o 'reason: "all-owned"' apps/web-platform/server/compound-promote-create-arm.ts` exits 1 with no
  output on the unfixed source and prints the literal once the Phase 1 return is written exactly as
  `{ kind: "no_action", reason: "all-owned" }` (keep the single space after `reason:`).
- Claim "TTL edges, invalid clock and exact-hash matching are already covered": confirmed in
  `apps/web-platform/test/server/compound-promote-ledger.test.ts` ("closed EXACTLY 60 days ago", "an unusable clock (Invalid
  Date) fails closed ...", "the TTL constant is 60 days").
- Claim "no consumer treats `all-owned` specially": the only readers are the marker type, the handler passthrough
  (`createNoAction = proposed.reason`) and an enum-membership assertion in the outcome-marker test; the handler test that
  has the MODEL return `all-owned` already pins the passthrough.
- Hazard recorded from review: the handler's `record()` adds EVERY recorded hash (including the edit loop's own
  `ledger-suppressed` refusals) to `runHashes`, which becomes `sameRunHashes`; an offer emptied only by those hashes ends
  `other`, not `all-owned`. This is consistent with the ruling; the runbook text must say so (Phase 3).
- The file header comment of `compound-promote-create-arm.ts` lists the Step A chain "week-cap -> index-empty -> same-run
  -> clone-present -> ..."; the chain's stage ids are unchanged (the ledger drop lives inside `same-run`), so the
  header needs at most a one-word gloss, not a new stage.

### Research Reconciliation (brief vs codebase)

| Brief claim | Reality | Plan response |
|---|---|---|
| Handler tests "a pattern already proposed (ledger: an open PR carries its cluster hash) is SUPPRESSED" and "G4: a hash the LEDGER suppresses (a prior PR) is still recorded once and counted once" "expect a model that names a ledger-suppressed pattern to be backstopped: they need a model naming a different pattern, or an empty offer" | With the backstop retained and `checkCreate` still given the FULL list, those two tests (default `createReply` names the owned `CREATE_PATTERN_SLUG`) keep PASSING unchanged: the owned pattern is no longer offered, the model names it anyway, the backstop records it once and counts it once (confirmed by plan review against `cron-compound-promote.ts` `record()` / `!runHashes.has(...)`) | Retitle the first as the BACKSTOP test and add one assertion (the prompt does NOT contain the owned slug); leave the second UNTOUCHED (its title is still accurate); ADD the tests that exercise the new path (model names a different pattern -> opens; only owned pattern -> `all-owned`, no call, counter 0). Verify at work time that they still pass; if one does not, that is a finding, not a test to loosen |
| G4 arm tests ("G4: when EVERY pattern is owned by the edit loop this run ...", "G4: an owned pattern is NOT offered to the model ...") describe filter order | They cover the SAME-RUN filter (hashes from `sameRunHashes`), not the ledger | Leave them; add ledger siblings next to them. The same-run empty `other` assertion and the peel test stay byte-identical |
| ADR-092 "Step A gate list" | It is the paragraph `**Gates on the new path.**` and carries the pinned sentence "a pattern the edit loop already recorded this run is not offered (nothing offerable is a clean no-action)" | Amend with a dated tail section plus a short dated clause after the pinned phrase; keep the phrase exactly once (parity test counts occurrences over the whole tail) |
| The corpus count in `preflight-discoverability-test.test.ts` moves only if the plan declares `credentials_required` | `BASELINE_DECLARED_PROBES = 87` today; the G1 test counts plans whose `## Observability` block parses a non-empty `credentials_required` | This plan does NOT declare `credentials_required` (the discoverability probe is a local, unauthenticated `grep`), so the baseline stays 87 and no bump is needed |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Fix the create arm's pattern selection so a ledger-owned pattern cannot win the single model call." | Phase 1 (code) | mapped |
| 2 | "compute the run time (`runNow`) before the filter and extend the `offered` filter to also drop `decideSuppression({entries: a.ledgerEntries, hash: h, now: runNow})`" | Phase 1 | mapped |
| 3 | "Keep the post-call isHashSuppressed gate as a backstop." | Phase 1 (checkCreate untouched, full list) and test T5 | mapped |
| 4 | "If the offered list is empty BECAUSE of the ledger, return {kind:\"no_action\", reason:\"all-owned\"}" | Phase 1, tests T2, T3, H3 | mapped |
| 5 | "Leave the same-run empty case as `other`" | Phase 1 two-stage filter, existing G4 tests | mapped |
| 6 | "Do NOT increment ledger_suppressed for pre-filtered hashes" | Phase 1, handler tests H2, H3 | mapped |
| 7 | "Add a failing-first test: with one suppressed pattern among several, the model prompt must not offer the suppressed pattern's slug, and a different eligible pattern can reach create." | Phase 0 (T1 written and run red first), H2 | mapped |
| 8 | "Update tests and docs that describe filter order: G4 tests ... and handler tests ..." | Phase 2 | mapped |
| 9 | "Add a dated append-only amendment to ADR-092" | Phase 3 | mapped |
| 10 | "update the runbook ... \"Same-run collision\" bullet and the create_no_action_reason row" | Phase 3 | mapped |
| 11 | "Add a learning under knowledge-base/project/learnings/" | Phase 3 | mapped |
| 12 | "if the plan declares credentials_required, bump BASELINE_DECLARED_PROBES ... or avoid declaring it" | Observability section (not declared) and AC | mapped |
| 13 | "Leave open PR #11291 alone" | Non-goals, AC | mapped |
| 14 | "Record the design above as a `technical` row ... run technical-ruling-gate.sh --branch and fix to exit 0" | decision-challenges.md (done, gate exit 0) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Two-stage filter (same-run first, then ledger) so same-run-empty stays `other` | "Leave the same-run empty case as `other` (existing tests pin it)" | asked |
| A mixed case (same-run drops some, the ledger drops the rest) returns `all-owned` | "If the offered list is empty BECAUSE of the ledger" | asked (the ledger removed the last candidate; pinned by test T3) |
| Dated tail section in ADR-092 plus a short clause in the gate list | "dated append-only amendment to ADR-092 (Step A gate list around line 318 ...)" | asked |
| Handler tests retitled as backstop tests | "need a model naming a different pattern, or an empty offer" | asked (retitle is the minimal honest form because they still pass) |
| Guard Contract section | — | inferred — justification: the deliverable moves an admission gate ahead of the call, plan Phase 2.12 requires it |
| Memoized-step note | — | inferred — justification: plan Sharp Edge for Inngest step returns; one sentence, no work |

### Split Assessment

- Subsystems touched: 3 (apps/web-platform, knowledge-base/engineering, knowledge-base/project)
- Planned files: 7 | Estimated changed lines: about 350 (about 15 code, about 120 tests, about 215 docs and learning)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-092 (extension of an existing decision, no new ordinal): the create arm's Step A `same-run` stage now also
drops ledger-suppressed patterns before the single model call, with `all-owned` for an empty-because-of-ledger offer;
the post-call ledger gate becomes an explicit backstop. Delivered in Phase 3 as (a) a short dated clause appended after
the pinned phrase in the `**Gates on the new path.**` paragraph and (b) a new dated tail section
`## Amendment — create-arm ledger pre-filter (2026-10-28, #10550)`. Both avoid repeating any
`STAGE_PHRASES` anchor (the parity test slices the ADR from the create-only amendment heading to EOF and counts each
anchor exactly once), and the tail section must not contain the strings `the ledger (a pattern with an existing proposal`
or `a pattern the edit loop already recorded this run is not offered`.

### C4 views

No C4 change. Checked against all three model files (`knowledge-base/engineering/architecture/diagrams/model.c4`,
`views.c4`, `spec.c4`): external human actors (the reviewer of the draft PR) unchanged; external systems (Anthropic
messages edge, the GitHub search read that feeds the ledger at `model.c4` "cron-compound-promote reads bot-PR state
through Octokit search", the GitHub write path) unchanged, no new call or edge; no container or data store touched; no
actor-to-surface access relationship changes. The model-call count per run does not change (still at most one create
call), only which candidates it sees. At work time no `.c4` file is edited, so no derived cardinality moves.

### Sequencing

The ADR text describes the deployed state as soon as this PR merges; nothing is deferred.

## Implementation Phases

### Phase 0 - Failing-first test (RED)

Write T1 (below) in `apps/web-platform/test/server/compound-promote-create-arm.test.ts` first and run it against the
unchanged source: it must FAIL at `expect(prompt).not.toContain(PATTERN.slug)` (the owned slug is offered today). Capture
the first failure line in the work log. Then write H2 and H3 in the handler suite. H2 fails ONLY at its
`not.toContain(CREATE_PATTERN_SLUG)` prompt assertion (the stubbed model deterministically names `zz-page-three`, so on the
unfixed source the run still opens; H2 proves the owned pattern is absent from the prompt, it cannot reproduce "the model
picks the owned pattern"). H3 fails (a model call happens, reason `other`, counter 1).

### Phase 1 - Code (GREEN), `apps/web-platform/server/compound-promote-create-arm.ts`

In `proposeInner`, replace the block that builds `offered` (currently: `sameRun` set, filter, `other` on empty) with a
two-stage filter, and hoist `runNow`:

```ts
// A pattern the EDIT loop recorded this run owns the branch `self-healing/auto-<hash>-<date>`, and a pattern the LEDGER
// already owns (an open or merged promotion PR, or one closed inside the TTL) would be refused at gate 5: offering either
// spends the ONE model call on a pattern that cannot be created, and the model can pick it while every other pattern is
// never evaluated (#10550, run 01M60XZRYG9ADVEWAY07HEQ5JK). Both are dropped here, before the call. The same predicate and the
// same memoized clock as `isHashSuppressed` below, which stays as the backstop for a model that names an unoffered pattern.
const runNow = new Date(a.runStartedAt);
const sameRun = new Set(a.sameRunHashes ?? []);
const notSameRun = a.patterns.filter((p) => !sameRun.has(createClusterHash(p.evidence)));
if (notSameRun.length === 0) return { kind: "no_action", reason: "other" };
const offered = notSameRun.filter((p) => !decideSuppression({ entries: a.ledgerEntries, hash: createClusterHash(p.evidence), now: runNow }));
if (offered.length === 0) return { kind: "no_action", reason: "all-owned" };
```

and delete the later `const runNow = new Date(a.runStartedAt);` (before `checkCreate`), reusing the hoisted constant. Update
the `sameRunHashes` doc comment on `CreateProposeArgs` and the comment above the filter so they describe the ledger drop
and the backstop. Do not touch `checkCreate`, the handler, the marker, `CREATE_STAGE_ORDER` or `isHashSuppressed`.

Placement is deliberate: both empty returns stay before `existsSync`, the open-create lookup, the clone measurement and
the key check, so an all-owned run spends nothing and does no I/O (same as the existing same-run empty return). Also update
the stage-chain line in the file's header comment if it lists `same-run`.

Safety notes: the `create-propose` step keeps returning the same `CreateVerdict` union (`no_action` / `all-owned` is an
existing member the handler already reads), so a run memoized under the old code resumes safely and a replay is
deterministic because `runNow` derives from the memoized `runStartedAt`. With an EMPTY `ledgerEntries` list
`decideSuppression` is false for every hash, so `offered` equals the old value; the scheduled, corpus, non-`true` and
edit-loop paths never execute `proposeInner`.

### Phase 2 - Tests

`apps/web-platform/test/server/compound-promote-create-arm.test.ts` (inside `describe("Step A with a valid create proposal")`,
next to the G4 tests; `HASH = createClusterHash(PATTERN.evidence)`). Hoist ONE shared `OTHER` pattern const (the inline
`other` literal is already copied twice in the G4 tests; do not edit those two, just do not add a third-to-fifth copy):

- T1 (written first, RED): "G5: a ledger-owned pattern is NOT offered; another eligible pattern reaches create".
  `const a = createArgs({ patterns: [PATTERN, OTHER], ledgerEntries: [{ hash: HASH, state: "open" }] }, { pattern_slug: OTHER.slug })`;
  read the prompt as `(vi.mocked(a.post!).mock.calls[0][0] as { messages: Array<{ content: string }> }).messages[0].content`
  (the default `post` from `createArgs` has no declared parameter, so a bare `mock.calls[0][0]` fails `tsc`); assert the
  prompt contains `OTHER.slug` and does not contain `PATTERN.slug`; assert the verdict is `kind: "create"` with
  `clusterHash === createClusterHash(OTHER.evidence)`.
- T2: "G5: when the ledger owns EVERY pattern the arm ends no_action(all-owned) before any read, request or model call":
  `ledgerEntries` owns `HASH`, `patterns: [PATTERN]`, and a NONEXISTENT `repoRoot` (as the peel test does) so the result
  being `all-owned` rather than `persist/clone-missing` proves the return precedes `existsSync`; `toEqual({ kind: "no_action", reason: "all-owned" })`;
  `post` and `request` never called; `reportSilentFallback` not called.
- T3: mixed case pinned: `patterns: [PATTERN, OTHER]`, `sameRunHashes: [createClusterHash(OTHER.evidence)]`, ledger owns
  `HASH` -> `all-owned` (the ledger removed the last candidate); and a pattern owned by BOTH the same-run set AND the ledger
  (`patterns: [PATTERN]`, `sameRunHashes: [HASH]`, ledger owns `HASH`) -> still `other` (guards a ledger-first order; the
  existing same-run test has an empty ledger and cannot).
- T4: the clock. A `closed` entry whose `closed_at` is inside 60 days of `runStartedAt` filters the pattern, with
  `runStartedAt` set far from the wall clock (the `args()` default is within days of today and would not catch a
  `new Date()` mutation). TTL edges, an invalid clock and exact-hash matching are `decideSuppression`'s own contract and are
  already covered in `test/server/compound-promote-ledger.test.ts`; do not re-test them here.
- T5: backstop retained: `patterns: [PATTERN, OTHER]`, ledger owns `HASH`, model returns the default proposal naming
  `PATTERN.slug` -> `{ kind: "suppressed", clusterHash: HASH }` (the owned slug was not offered, the model named it anyway).
- The existing G4 tests (same-run `other`, prompt omits the owned slug, same-run backstop, unrelated hash) and the peel
  test stay byte-identical; do not edit them.

`apps/web-platform/test/server/inngest/cron-compound-promote-create-handler.test.ts` (the fixture has three pages:
`CREATE_PATTERN_SLUG`, `page-two` with the edit loop's evidence, `zz-page-three`):

- Retitle the test "a pattern already proposed (ledger: an open PR carries its cluster hash) is SUPPRESSED, not refused" to say
  it pins the BACKSTOP and add one assertion that the create prompt does not contain `CREATE_PATTERN_SLUG` (the owned slug is
  no longer offered) while the default reply that names it is still suppressed with `ledger_suppressed: 1`. Leave
  "G4: a hash the LEDGER suppresses (a prior PR) is still recorded once and counted once" UNTOUCHED (its title is still
  accurate and it still passes).
- H2: "the ledger owns the create pattern: it is not offered, a different pattern is, and it opens".
  `h.ledger.items` carries an open PR for `ENTRY_HASH`; `createReply = goodProposal({ pattern_slug: "zz-page-three" })`.
  Assert `createPrompts()` has length 1 and its prompt contains `zz-page-three` and not `CREATE_PATTERN_SLUG` (the only
  assertion that is RED on the unfixed source); `create_outcome: "opened"`, one create commit whose `branchName` contains
  the hash of `Ls(6, 7)`; `ledger_suppressed: 0`; `refusals` does not contain `ledger-suppressed`; `(r.last.refusal_detail ?? [])`
  has no entry for `ENTRY_HASH`.
- H3 (the only test that reads the operator-visible marker end to end; drop first if scope must shrink): "the ledger owns
  the ONLY pattern: no create model call, no_action(all-owned), counter 0". Remove `page-two` and `zz-page-three` with the
  same `git rm` + `reset --hard HEAD~1` fixture pattern the existing G4 "only pattern" test uses; assert `createPrompts()`
  length 0, `names` contains `create-propose` and not `create-persist`, `create_no_action_reason: "all-owned"`,
  `ledger_suppressed: 0`, `refusals` without `ledger-suppressed`, no `create_refusal_class`.

Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/compound-promote-create-arm.test.ts test/server/inngest/cron-compound-promote-create-handler.test.ts test/server/compound-promote-create-parity.test.ts test/server/compound-promote-runbook-parity.test.ts`
and `./node_modules/.bin/tsc --noEmit`.

### Phase 3 - Docs and learning

- ADR-092 (`knowledge-base/engineering/architecture/decisions/ADR-092-additive-only-auto-edit-boundary-and-hard-rule-body-weakening-gate.md`):
  in the `**Gates on the new path.**` paragraph, immediately after the pinned phrase's parenthetical
  "(nothing offerable is a clean no-action)", insert ", and, amended 2026-10-28 (#10550), nor is a pattern the ledger already
  owns (the same predicate and run clock as the ledger gate below; nothing offerable because of the ledger is a clean
  `all-owned` no-action)" (exact text chosen at work time; the pinned prefix is untouched). Append a SHORT tail section
  `## Amendment — create-arm ledger pre-filter (2026-10-28, #10550)` (dated, append-only; 5 to 8 lines): the decision (the
  ledger drop happens before the single call, two-stage so same-run-empty stays `other` and ledger-empty is `all-owned`;
  `checkCreate` keeps the full list so the ledger gate is a backstop), `ledger_suppressed` semantics (counts clusters
  dropped: edit-loop refusals and backstop hits, never pre-filtered offers), no marker change, and the residual (what the
  model does with the remaining patterns is unmeasured until a live-fire). The evidence (run id, counts) lives in the
  learning. Constraint: the tail must contain NO `STAGE_PHRASES` anchor from `compound-promote-create-parity.test.ts` (not
  only the two phrases named earlier: also `the API key`, `slug format`, `schema validation`, `the clone being present`,
  `one open create at a time`, `then ONE model call with no retry.` and the rest); run
  `compound-promote-create-parity.test.ts` after EACH ADR edit, not only at the end.
- Runbook `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md`: rewrite the "Same-run collision"
  bullet (2 to 3 sentences) to "Same-run collision and ledger pre-filter": both facts drop a pattern from the offered list
  before the one call; "same-run" is every hash the edit loop recorded (opened, attempted, OR refused, including the edit
  loop's own `ledger-suppressed` refusals), and an all-same-run offer ends `other`; an offer emptied by the ledger ends
  `all-owned`; neither increments `ledger_suppressed`; a model naming an unoffered pattern is the backstop (a ledger hit is
  recorded and counted once). Update the `create_no_action_reason` row: `all-owned` = every offerable pattern is owned by
  the ledger (server-side, no model call; a model may also return `all-owned` itself); `other` = the model declined with
  `other`, every pattern was owned by the edit loop this run, or the backstop caught a named owned pattern. Update the
  `create_outcome` row sentence "or the pattern is already proposed (`ledger-suppressed` in `refusals[]`,
  `ledger_suppressed` counted)" so it applies to a backstop hit only. The `ledger_suppressed` row is not edited (the bullet
  states it once).
- Learning `knowledge-base/project/learnings/2026-10-28-a-filter-that-runs-after-the-single-decision-cannot-protect-the-decision.md`
  (one short file): Problem (run `01M60XZRYG9ADVEWAY07HEQ5JK`), Solution, Key Insight (a gate placed after a one-shot
  decision is a backstop, not protection; apply every fact knowable before the decision to the candidate set before the call;
  test: with N candidates and one owned, assert the owned one is absent from the prompt and another can win). Add a
  Session Errors list only if the work phase has real ones.

## Files to Edit

- `apps/web-platform/server/compound-promote-create-arm.ts`
- `apps/web-platform/test/server/compound-promote-create-arm.test.ts`
- `apps/web-platform/test/server/inngest/cron-compound-promote-create-handler.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-092-additive-only-auto-edit-boundary-and-hard-rule-body-weakening-gate.md`
- `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md`

## Files to Create

- `knowledge-base/project/learnings/2026-10-28-a-filter-that-runs-after-the-single-decision-cannot-protect-the-decision.md`
- `knowledge-base/project/specs/feat-one-shot-10550-create-arm-prefilter-owned/tasks.md` (and the already-written
  `decision-challenges.md`)

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (200 issues) was searched for each planned code, test, ADR and
runbook path; no body names any of them.

## Guard Contract

### Guard 1 - create-arm offered-list ledger pre-filter

**Property.** No pattern whose cluster hash `decideSuppression` would suppress with the run's memoized clock is ever
included in the candidate list sent to the single create model call, and a run whose candidates are all ledger-owned makes
no model call.

**Assembly.** The candidate set is the single `offered` array in `proposeInner` that feeds `prepareCreate({ patterns: offered ... })`;
there is exactly one create model call site (`post(...)` in `proposeInner`) and exactly one list passed to it. The ledger
predicate has three consumers that must agree: the pre-filter (new), the `isHashSuppressed` backstop passed to
`checkCreate` (kept, full `a.patterns` list), and Step B's `isHashSuppressed: () => false` (consults nothing because Step A
already did; unchanged). The inputs are `a.ledgerEntries` and `a.runStartedAt` only. The assembly is the chokepoint
(`offered`), not a list of today's patterns: any new code path that builds a prompt from `a.patterns` instead of `offered`
would bypass it, which is why T1 asserts on the prompt the model actually receives.

**Mutation matrix.**

| # | Mutation (edit to the system under test) | Must go RED | Which test |
|---|---|---|---|
| 1 | Delete the ledger filter line (`offered = notSameRun`) | the owned slug is in the prompt | T1, H2 |
| 2 | Use `new Date()` instead of the hoisted `runNow` in the filter | a closed entry inside the TTL of `runStartedAt` is not filtered | T4 (`runStartedAt` far from the wall clock) |
| 3 | Pass `offered` instead of `a.patterns` to `checkCreate`, or remove the post-call ledger term | a model naming an unoffered owned pattern becomes `model-invalid`, or is created | T5 |
| 4 | Return `reason: "other"` for the ledger-empty case | wrong reason | T2, H3 |
| 5 | Increment the handler's `ledger_suppressed` for pre-filtered hashes | counter becomes 1 | H2, H3 |
| 6 | Run the ledger filter FIRST and the same-run empty check after | a pattern owned by both returns `all-owned` instead of `other` | T3 second half (ledger owns the same-run pattern) |
| 7 | Move the empty returns after `existsSync` / `findOpenCreatePr` | `persist/clone-missing` or a request appears instead of `all-owned` | T2 (nonexistent `repoRoot`, `request` never called) |

**Harness rows.** RED-first (Phase 0) proves T1 discriminates: it fails on the unfixed source at the
`not.toContain(PATTERN.slug)` line. Must-PASS inputs that are not the canonical: an empty ledger and an unrelated hash in
`ledgerEntries` (the existing unedited G4 tests, "an unrelated same-run hash does not suppress", and the scheduled-path
equivalence test).

**Anchor.** The tests assert behaviour, not a stored value; the ledger is read from GitHub by the handler outside this
commit, so no stored hash or count floor is involved.

## Observability

```yaml
liveness_signal:
  what: the create arm marker fields create_arm, create_outcome and create_no_action_reason on every manual patterns run with allow_create true (cron-compound-promote outcome marker)
  cadence: per manual allow_create run (operator-fired, dark-launched arm)
  alert_target: none new; the existing cron-compound-promote Sentry monitor and the create-refused Sentry op are unchanged
  configured_in: apps/web-platform/server/inngest/functions/cron-compound-promote.ts (emitOutcomeMarker) and apps/web-platform/server/compound-promote-marker.ts
error_reporting:
  destination: Sentry via reportSilentFallback (op create-refused, create-propose-internal); unchanged
  fail_loud: an unexpected throw inside proposeInner is mirrored by runCreateProposeStep and returned as model-invalid/internal; the ledger pre-filter itself is pure and cannot throw (decideSuppression handles an invalid clock by failing closed)
failure_modes:
  - mode: every offerable pattern is ledger-owned
    detection: marker create_no_action_reason=all-owned with create_outcome=no_action and no create model call (patterns_open > 0)
    alert_route: Better Stack log query per compound-promote-runbook.md; no page, the arm is operator-fired
  - mode: the model names an unoffered owned pattern (backstop)
    detection: marker ledger_suppressed=1 with refusal_detail reason ledger-suppressed; expected rare after this change
    alert_route: same runbook query
  - mode: the pre-filter leaves candidates but the model or a later gate declines all of them
    detection: create_outcome=no_action with reason other or no-pattern-qualifies, or create_outcome=refused with create_refusal_class; unchanged vocabulary
    alert_route: same runbook query
logs:
  where: Better Stack (cron-compound-promote outcome marker), Sentry for create-refused
  retention: per the existing Better Stack and Sentry retention; unchanged
discoverability_test:
  command: grep -o 'reason: "all-owned"' apps/web-platform/server/compound-promote-create-arm.ts
  expected_output: all-owned
```

The probe is a source-presence check, not a live read: it proves the all-owned return ships in the arm and prints nothing
today (it can fail). The live signal is the marker field named in `liveness_signal`, read through the Better Stack recipe in
the runbook, which needs production credentials; this plan deliberately does not declare that read as a probe (so
`BASELINE_DECLARED_PROBES` stays at 87), and the live read is part of the post-merge verification, not a preflight probe.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: an internal server-side candidate filter, tests and engineering docs. The binding
technical ruling is recorded (CTO agent, 2026-10-28) in `decision-challenges.md`. No user-facing surface, no copy, no
regulated data (GDPR gate not triggered: no schema, auth, API route or new processing activity).

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing. The create arm is dark-launched and manual-only; a
broken pre-filter could at worst make the arm end `no_action` (as it did on 2026-10-28) or offer a pattern the unchanged
gate then suppresses. No page, flow or message of an end user changes.

**If this leaks, the user's data is exposed via:** no exposure vector. The change reads only the patterns, the ledger
entries and the memoized run clock the arm already holds, and writes no new field to the marker, logs or Sentry.

**Brand-survival threshold:** none

threshold: none, reason: the diff is under `apps/web-platform/server/` (a sensitive path) but only REMOVES candidates from
the set offered to the model; every admission gate in `checkCreate`, the draft-PR-only commit, `mergeMode: "none"` and the
human reviewer are untouched, so the arm's own `single-user incident` controls in ADR-092 are unchanged and still run on
whatever the model names.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] T1 and H2/H3 were run RED against the unfixed source before Phase 1 (first failure lines in the work log) and are
      GREEN after.
- [ ] `proposeInner` filters same-run hashes first (empty -> `other`), then ledger-suppressed hashes via
      `decideSuppression` with the hoisted `runNow` (empty -> `all-owned`); both returns precede `existsSync`; the later
      duplicate `runNow` is gone; `checkCreate` and `isHashSuppressed` are textually unchanged.
- [ ] `ledger_suppressed` is 0 for a pre-filtered hash (H2, H3) and 1 for a backstop hit (retitled existing tests).
- [ ] The existing same-run G4 tests and the Step A peel test pass UNEDITED; the handler test "a hash the LEDGER suppresses (a prior PR) is still recorded once and
      counted once" is untouched.
- [ ] `compound-promote-create-parity.test.ts` and `compound-promote-runbook-parity.test.ts` pass; no `STAGE_PHRASES`
      anchor appears in the ADR tail section (run after each ADR edit).
- [ ] `tsc --noEmit` clean in `apps/web-platform`.
- [ ] ADR-092 carries the dated clause and the dated tail amendment; the runbook "Same-run collision" bullet and the
      `create_no_action_reason` row are updated; the learning exists.
- [ ] `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` exits 0.
- [ ] The plan declares no `credentials_required` in its Observability block, so `BASELINE_DECLARED_PROBES` stays 87:
      `cd plugins/soleur && bun test test/preflight-discoverability-test.test.ts -t G1` is green with the plan
      committed (verified at plan time: 1 pass).
- [ ] `npx markdownlint-cli2` clean on the plan, tasks.md, learning, ADR and runbook edits.
- [ ] PR body says `Ref #10550` (never `Closes`), states that the change removes the structural cause of the observed
      `no_action` (a ledger-owned pattern winning the one model call), and does NOT claim a PR will open (whether the model
      picks, and the gates accept, any of the other six patterns is unmeasured until a live-fire clears).
- [ ] No action on PR #11291 (no merge, close, comment, push); no comment on or closure of #10552, #10551, #8293; #8443,
      #11183, #10676, #11228 untouched.

### Post-merge (automated, agent-run)

- [ ] Deploy verified: `deploy-arm.sh find --wait`, then served, then `soleur:postmerge` prints
      "postmerge verification complete!".
- [ ] No cron is fired by this pipeline (a live-fire is a separate, operator-authorized act and is out of scope here).

## Test Scenarios

- With one ledger-owned pattern among two or more, the prompt omits its slug and a different pattern creates (T1, H2).
- Ledger owns the only pattern: no call, `all-owned`, counter 0 (T2, H3).
- Same-run owns everything: `other` (existing); same-run plus ledger together: `all-owned` (T3).
- Closed entry inside versus outside the 60-day TTL, clock from `runStartedAt` (T4).
- Model names an unoffered owned pattern: suppressed, never created, recorded once and counted once (T5, retitled
  handler tests).
- Empty ledger: identical to today (existing tests, unedited).

## Non-Goals

- No live-fire, no cron trigger, no operator step.
- No change to prompt wording, `checkCreate`, the marker schema, the handler, the edit loop, scheduled or corpus paths.
- No claim that a PR will open; the downstream gates (prefer-patch, budget, collision) on the six remaining patterns are
  unmeasured.
- No action on PR #11291 or any other PR.

## Risks

- A second-order defect behind this one (the model picks a remaining pattern and prefer-patch or budget refuses it) is
  possible and is exactly what the next live-fire measures; this PR does not hide or pre-empt it.
- Less trace of ledger ownership in the marker when a pre-filtered run proceeds (no `ledger-suppressed` entry); accepted by
  the ruling (`patterns_open` and `all-owned` remain). The runbook text states the changed meaning of
  `ledger_suppressed` for the create arm so the absence is not misread.
