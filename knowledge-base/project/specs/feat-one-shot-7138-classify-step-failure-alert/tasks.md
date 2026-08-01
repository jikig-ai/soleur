# Tasks — #7138 release-outcome: a failing classify step silenced every alert channel

Plan: `knowledge-base/project/plans/2026-08-01-fix-release-outcome-classifier-failure-alert-plan.md`
Evidence: `verification-evidence.md` · Decisions: `decision-challenges.md`
Branch: `feat-one-shot-7138-classify-step-failure-alert` · Closes: #7138

Status is recorded per item as **done**, **cut** (with the revision that cut it), or
**changed** (where implementation diverged from the plan and why). Nothing is marked done
that was not executed and observed.

## Phase 0 — Preconditions

- [x] T0.1 `command -v act` → **exit 1, absent.** Not used either way: it reimplements the
      expression evaluator, so a green `act` run proves act's semantics, not GitHub's.
- [x] T0.2 `actionlint` present at `~/.local/bin/actionlint`. Asserted **per-file** on the touched
      workflow, not repo-wide — `scripts/lint-workflows.sh` exits 0 on findings too,
      so a repo-wide "clean" claim is unfalsifiable (R38a).
- [x] T0.3 `python3 scripts/lint-workflow-step-env-refs.py` → baseline and post-change both
      `0 findings across 70 workflow file(s)` (the harness that briefly made it 71 is
      deleted — see R10).
- [x] T0.4 Read `.github/workflows/gdpr-gate-self-test.yml` — the self-bootstrapping
      `pull_request` + `paths:` precedent. Confirmed it declares **no** job-level
      `permissions`, so "copy its permissions conventions" copied nothing (R37).
- [x] T0.5 Required-check surface confirmed: `test` (ruleset `infra/github/`, repo root — NOT
      `apps/web-platform/infra/github/`, which does not exist; R29). Harness deliberately not
      added to any ruleset.
- [x] **T-R34 (added by review, P0)** — re-verified "the mirror pages nobody" against the
      **live** Sentry rules API before Phase 2 was written. **The premise is FALSE**: a 30th,
      un-codified rule routes it. See `verification-evidence.md` §4 and `decision-challenges.md`
      DC-1.

## Phase 1 — Mirror step

- [x] T1.1 `id: mirror` added; every test selector re-pointed from a name prefix to the id.
- [x] T1.2 One-line shared-predicate `if:`.
- [x] T1.3 Both `${FAILED}` → `${FAILED:-}`. **Reclassified**: measured as a *consistency*
      change, not a crash fix — the harness proved GitHub sets a declared-but-empty key
      (`FAILED_IS=SET value=''`), so `set -u` never fired (R2, confirmed by execution).
- [x] T1.4 One branch setting `LEAD` / `FAILED_LABEL` / `CLASSIFIER_TAG`, consumed at three
      call sites. **Changed from the plan**: keyed on `CLASSIFIER`, not `-z FAILED`, so the
      mirror and the email cannot tell different stories about one incident (R5).
- [x] T1.5 `classifier` added as its own tag key; `op: release-alert-undelivered` unchanged —
      a discriminator never goes in the key something routes on. Step still `exit 1`.
- [x] T1.6 The DO-NOT-add-`continue-on-error` comment, pinned by B1e.

## Phase 2 — Email step (shipped; separable and cut-able as a unit)

- [x] T2.1 `if:` replaced with the shared predicate.
- [x] T2.2 `CLASSIFIER` declared in the step's **own** `env:`, never inherited.
- [x] T2.3 Third headline branch. **Superseded at review**: R6's negative gate
      (`R_DEPLOY != 'failure'`) swept in `skipped`/`cancelled` and reassured on releases that
      never rolled out. Now gated positively on `== 'success'` — see Post-review below.
- [x] T2.4 `What stopped` list guarded — no empty `<ul></ul>` under a heading promising content.
- [x] T2.5 Subject prefix. **Changed** to `[RELEASE STATUS UNKNOWN]`, not
      `[RELEASE CHECK FAILED]`: the latter differs from `[RELEASE FAILED]` by one word
      mid-bracket and collapses under lock-screen truncation (R22).
- [x] **T-R1 (P0)** — the email's two bare `${FAILED}` guarded. The first sits *between* the
      successful `curl` and the `delivered=1` write.
- [x] **T-R4 (P0)** — the unconditional closing urgency line branched; it was false on the new
      branch, contradicting the email's own opening two paragraphs earlier. Asserted by B6c
      (and B3c for the sibling deploy-success branch, which review found still carried it).

## Phase 3 — Execution harness (issue AC2)

- [x] T3.1 `release-outcome-condition-harness.yml` created, `pull_request` + self-referencing
      `paths:`.
- [x] T3.2 **Changed to 3 arms (A/B/C), not 6** (R12): D and E duplicated A's and the shipped
      path; F re-tested `!cancelled()`, already pinned by B1b in the required check.
- [x] T3.3 Both shipped `if:` strings copied verbatim; verified byte-identical at merge time.
- [x] T3.4 `verdict` job asserts the truth table via the jobs API. **Changed**: added
      `GH_TOKEN`/`GH_REPO`/`GH_RUN_ID` (R9 — as planned it had no credentials), filtered out
      the implicit `Set up job`/`Complete job` steps, and replaced a heredoc whose quoted
      terminator cannot be indented with `printf '%b'`.
- [x] T3.5 Verdict asserts 3 arms were observed — an incomplete sweep must not read as green.
- [x] T3.6 All three runtime facts recorded, plus the one the plan omitted (R32/R37).
- [x] T3.7 `actionlint` and the env-ref linter clean with the harness present.
- [x] **R10 — harness DELETED before merge.** A permanent, deliberately-red, non-required
      check is the shape of the bug `bf4816455` fixed on main four commits earlier. The run is
      immutable evidence; the durable guard is B1a..B1f in the required `test` check.

## Phase 4 — Static assertions (issue AC3)

- [x] T4.1 Selector refactored to one id-keyed helper with an **exactly-one cardinality**
      precondition on every lookup (R7, P0).
- [x] T4.2 B1c — **changed** from a substring anchor to whole normalized-string equality
      (R8): an anchor on the `conclusion` phrase alone stays green if the
      `outputs.failed != ''` disjunct is deleted.
- [x] T4.3 B1d — same, for the email step.
- [x] T4.4 B1e — the `outcome` step declares no `continue-on-error`.
- [x] ~~T4.5 harness↔shipped byte-equality~~ — **cut with R10** (no permanent harness to
      compare against). `B1f` was later reused at review for the classify-step timeout.
- [x] ~~T4.6 B1g harness exists + `on: pull_request`~~ — **cut with R10**. This also retires
      R28's PyYAML `on:`→`True` trap, since nothing now parses a workflow's triggers.

## Phase 5 — Local execution + C4

- [x] T5.1 M1 (`FAILED=""`, the newly-reachable input) executed against the shipped mirror
      body. **M2 retained against R13**: R13 cut it as duplicating the shipped path, which the
      implementation makes untrue — the classifier discriminator turns this into a genuinely
      new two-way branch, and testing one arm would leave the other unexecuted. **M3 cut** as
      R13 directs: its blanket `sed` rewrites the branch test too, so the mutant dies before
      reaching the expansion it exists to guard.
- [x] **T-R26 (P0)** — curl stub extended to `-d|--data|--data-raw` **before** any mirror arm.
      The mirror posts with `--data`; unfixed, four assertions would have been vacuous.
      Proven load-bearing by mutation 9.
- [x] **T-R27 (P0)** — `run_mirror` env enumerates `GITHUB_STEP_SUMMARY`,
      `NEXT_PUBLIC_SENTRY_DSN`, `RUN_URL`, `GITHUB_SHA`, `PAYLOAD_CAPTURE`. Omitting the first
      aborts with the exact `unbound variable` string M1a asserts must be absent. Proven by
      mutation 10.
- [x] T5.2 Email third-branch arm (B6a–B6i at review, sweeping every `R_DEPLOY` value).
- [x] T5.3 `github -> resend` edge added. **Changed**: label trimmed to one clause and
      rewritten per R40a, and rescoped at review to characterise the EDGE (nine Resend emitters
      under `.github/`) rather than narrating its one notable caller.
- [x] T5.4 `github -> sentry` amended: the `paths:`-filter falsehood corrected (R40b) and the
      release-outcome store POST named. `sentry -> founder` stale counts corrected
      (21/22 → 29 IaC rules; `NoOne` 1 → **1**, not 2 — my first correction miscounted a
      comment, see Post-review) and the un-codified 30th rule recorded (R40c).

## Phase 6 — Verify

- [x] T6.1 `bash scripts/lint-workflow-step-env-refs.test.sh` → `All tests passed`, **69/69**
      after review (48/48 as first written).
- [x] ~~T6.2~~ — **cut with R14**, subsumed by T6.4 (test-all runs A13, which lints tree-wide).
- [x] T6.3 `actionlint` per-file on both workflows (see T0.2 for why not repo-wide).
- [x] T6.4 `bash scripts/test-all.sh` — the gate's own invocation.
- [x] T6.5 C4 validation. **Repointed per R38c**: `c4-code-syntax.test.ts` tests a
      syntax-highlighting tokenizer and `c4-render.test.ts` mocks `spawn`; **neither reads
      `model.c4`**, so the planned AC was vacuous. The real gate is
      `scripts/regenerate-c4-model.sh` (run: 65 elements, 124 relations, 67 views) backstopped
      by `c4-model-freshness.test.sh`.
- [x] T6.6 Mutation proof — round 1 was 10/10 RED and **was not sufficient**; round 2 adds
      11 mutations on the axes it could not express. Both recorded in
      `verification-evidence.md` §3.
- [x] T6.7 Harness run URL + observed jobs JSON captured.
- [x] ~~T6.8 harness `always()` mutation on a scratch branch~~ — **cut with R11** (three
      reviewers, independently): a scratch-branch push fires neither trigger, and the only
      workable form opens a throwaway PR that spends a **paid** `claude-code-review.yml` run.
      Arm C's recorded `skipped` already carries the discrimination — `always()` cannot
      produce that row.
- [x] ~~T6.9~~ — **cut with R14**: no stated pass criterion, and the string legitimately still
      appears in both `if:` and two `env:` blocks after the fix, so the check always passes.

## Phase 7 — Tracked scope-out + close-out

- [x] T7.1 Routing-gap issue filed as **#7142**. **Re-scoped** after T-R34: it no longer
      claims the event reaches nobody, but that the only rule routing it is UI-managed and
      absent from IaC — what ADR-031 and ADR-117 actually care about. Re-evaluation trigger
      de-circularised (R17) and dated **2026-11-01**.
- [x] T7.2 `decision-challenges.md` records the Phase-2 deviation **and** that its original
      justification was falsified.
- [x] **T-R16** — operator decision DC-2 defaulted to a tracking issue, filed as **#7143**.
      The three live sites are unchanged.
- [x] T7.3 PR body carries `Closes #7138`; #7136/#7137/#7095 are context only.
- [ ] T7.4 `/compound` — learning capture (runs at the compound step, not here).

## Not done, deliberately

- **CHANGELOG.md** — the plan listed it under Files to Edit. **No root `CHANGELOG.md` exists**
  in this repo; the changelog is generated from `plugins/soleur/docs/_data/changelog.js`. The
  plan was authoritative for intent, not for paths.
- **R31** (rename step id `outcome` → `classify`) — declined. It would retire B1e at the cost
  of churning five references plus every selector, in the same PR that is fixing an alerting
  outage. B1e closes the same hole explicitly and is CI-enforced.

## Post-review (8 agents; findings fixed inline)

- [x] **P1 — the third headline reassured on releases that never rolled out.** Gate was
      `R_DEPLOY != 'failure'`; `deploy` has five upstream `needs:`, so `skipped` is the
      dominant failed-release state. Now gated positively on `== 'success'`. Four agents
      reproduced it independently. B6h/B6i sweep every `R_DEPLOY` value.
- [x] **P1 — the harness fabricated its own environment.** `run_step`/`run_mirror` injected
      `CLASSIFIER`, so deleting either declaration reverted the fix at 48/48 green (#7136's
      class, new variable). Both now derive from the step's `env:`; B1a-email/B1a-mirror
      assert the declarations. Fixing it exposed a trailing-newline drop in the derivation
      itself — fixed at both ends.
- [x] **P1 — fixtures sampled one diagonal of a 2×2.** Added the (classifier died, list
      populated) cell on both sides (B6f/B6g, M3/M3a); the mirror now answers "did it die?"
      and "do we have the list?" with independent fields.
- [x] **P2 — no anti-vacuity floor.** Deleting B1c/B1d/B1e left the suite exiting 0.
      `MIN_ASSERTIONS` floor added (a floor, not equality).
- [x] **P2 — `RUN_HINT` branched on the headline** while the list it points at branched on
      `FAILED_HTML` → dangling "the red entry named above". Both now derive from the list.
- [x] **P2 — deploy-success branch reasserted "nothing reaches production"** two paragraphs
      after saying the code is live. Branched; pinned by B3c.
- [x] **P2 — classify hang was closable after all.** The only `timeout-minutes` was
      job-level, so a hang burned the budget and neither alert step was scheduled. Step-level
      timeout added; pinned by B1f.
- [x] **P2 — mirror Sentry `message` interpolated the job list**, minting a new issue group
      per failure set on a message-grouped event. Detail moved to `extra`/step summary.
- [x] **P2 — non-2xx email path never executed** (stub returned 200 unconditionally). Stub
      parameterised; B7/B7a/B8/B8a cover both directions of the `delivered` contract.
- [x] **P2 — my own `NoOne` correction was wrong.** `awk` matched the bare token inside a
      comment; actual is 28 `ActiveMembers` / 1 `NoOne`. Corrected in `model.c4`, evidence
      and here.
- [x] **P2 — DC-1 led with a non-sequitur.** "Only channel that fires regardless of which
      job failed" is about the JOB; both steps live in it. Struck.
- [x] **P2 — Sentry rule overstated.** New/Existing conditions are first-seen and
      escalated-to, so a repeat is silent on that route. Corrected everywhere; added to #7142.
- [x] **P2 — plan `## Observability` named a deleted harness** and assertions that do not
      ship. Reconciled to B1a..B1f + the immutable run URL.
- [x] **#7143 enumeration corrected** — a false-GREEN heartbeat variant (a dead probe checks
      in `ok`), a wrong detection criterion, and ~10 further sites. Filed as a comment.
- [ ] Deferred, contested-design: restore the harness `workflow_dispatch`-only + a
      harness↔shipped byte-equality assertion (architecture-strategist P1-1 vs plan R10,
      which two reviewers used to cut it). Not a correctness gap — B1c/B1d pin the strings;
      the trade is re-executability vs. a file that never fires unbidden.
