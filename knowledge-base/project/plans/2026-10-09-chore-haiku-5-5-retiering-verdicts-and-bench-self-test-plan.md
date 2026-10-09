---
title: "chore: Haiku 5.5 re-tiering verdicts (#9790), the four open design questions, and the bench self-test hardening"
date: 2026-10-09
slug: haiku-5-5-retiering-verdicts-and-bench-self-test
branch: feat-one-shot-haiku-5-5-retiering-bench-fix
issue: 9790
type: chore
lane: cross-domain
requires_cpo_signoff: false
---

## Enhancement Summary

**Deepened on:** 2026-10-09. **Mechanical gates run:** User-Brand Impact (present, `aggregate pattern`), Observability (5 fields, `grep` probe, literal `expected_output`), PAT-shaped variables (none), UI wireframe (no UI surface), Encryption Posture (skip stated), Guard Contract (`lint-guard-contract.py`: 2 entries, green), Scope Check (one live section, 14 asks mapped, 0 unmapped), citation checks (below).

### Key improvements

1. The reported `51/1` baseline was reproduced on a pre-#9753 copy and attributed to #8394's reader/mock mismatch; the current tree is 177/0, so the work is a regression guard and two environment-leak fixes, not a repair.
2. The re-tiering decision is made by a pre-registered spend gate on measured post-cutover numbers (all candidates fall below the line), with `claude-code-review.yml` found disabled since 2026-02-12.
3. The CLI 2.1.293 internal-model question is answered by measurement ($0.058): the `haiku` alias and the internal WebFetch summarizer both report `claude-haiku-5-5`.
4. Plan review cut four inferred mechanisms (N=60 probes, the global-env census, a Phase 3 protocol, a measurement script) and corrected a stale-window error that had made the best candidate look closer to the line than it is.
5. Deepen corrected the suite-registration wording to the real symbols (`ALWAYS_ON_SUITES` / `AFFECTED_*_PATHS`; there is no `CI_HEAVY_SUITES`).

### Verified in this pass

- `PAGES_OPERATOR` in `apps/web-platform/lib/failure-reason.ts` marks `leader_refused` and `leader_response_truncated` true, so the existing `spawn-agent-dead-letter` rule is the production trigger for both leader-loop questions.
- Neighbouring rules use `tagged_event ... match = "in"` with a comma list (`issue-alerts.tf` lines 324 and 768), so the `feature in domain-router,email-triage` filter has precedent.
- `reportSilentFallback(null, ...)` takes the `captureMessage` path with a constant message per site, so the two `no-text-block` mirrors are two Sentry issues and `event_frequency_count` (per issue) counts them correctly.
- Cited numbers resolved live: #9790 OPEN, #9785 / #9753 / #8394 / #9236 / #9804 MERGED, #8643 / #8800 / #6297 OPEN; commits `d0707d3fa3`, `73d5b13a9a`, `8729cc0dfa`, `d0f39fed6f` are ancestors of origin/main; the only rule id cited (`wg-when-tests-fail-and-are-confirmed-pre`) is active.

## Overview

The Haiku 5.5 support PR (#9785) merged on 2026-10-09 and left two follow-ups open. This plan finishes
both. The honest result of each is smaller than the brief assumes, and the plan says so with evidence.

**Part 1 — #9790, the eval-gated re-tiering.** The issue asks for one `eval-harness` arm per
candidate class and says a class with negligible measured spend "should be dropped rather than
evaluated". Spend is now measurable (the `SOLEUR_CLAUDE_COST` markers carry per-run `cost_usd`) and was
measured while planning (`specs/feat-one-shot-haiku-5-5-retiering-bench-fix/plan-time-evidence.md`).
Since 2026-10-01 the four crons cost about $1.6 to $9 a month each on Sonnet 5.5 (per-run cost fell
4-5x around 2026-09-30), `claude-code-review.yml` has been `disabled_manually` since 2026-02-12 so it
spends $0, and the seven `'standard'` workflow pins sit in opt-in `Workflow`-tool ports with no
metering and zero observed runs. A pre-registered spend gate (Gate 0) decides every candidate before
any eval arm exists, and the work phase re-runs it on its own date. If it still drops everything, no
arm is built, no pin moves, `PIN_ALLOWLIST` is untouched, and the deliverable is the per-class verdict
table in an ADR-053 addendum plus a short pointer for the day a class qualifies.

The four design questions are closed with evidence or an armed trigger: the claude-code CLI 2.1.293
internal small/fast model is **measured** (`claude-haiku-5-5`), leader-loop truncation and refusal
already page through the existing `spawn-agent-dead-letter` rule (decision rules and triggers are
recorded, no speculative code), and the `no-text-block` mirrors get a rate alert.

**Part 2 — the bench self-test.** `bash scripts/learning-retrieval-bench.sh --self-test` is **green
(177/0) on current origin/main**. The reported 51/1 reproduces exactly on the revision before #9753;
its root cause is a reader/mock mismatch from #8394, fixed incidentally by #9753. Nothing is a
"falsified Stage 2 experiment": Stage 2 is the live `kb-search` contract. The work is a regression
guard (nothing ran the self-test, so it stayed red 18 days) and an environment-hermeticity fix (two
caller-environment leaks, one making the self-test attempt live API calls). No tracking issue is
filed: the failure is not on main and the hardening is done inline.

## Research Reconciliation — Spec vs. Codebase

| Brief or issue claim | Reality (evidence) | Plan response |
|---|---|---|
| "`--self-test` reports 51/1 on origin/main" | origin/main `8729cc0dfa`: `PASS=177 FAIL=0`, rc 0, 3.6 s. `git show d0707d3fa3^:scripts/learning-retrieval-bench.sh` run as a copy: `PASS=51 FAIL=1 TOTAL=52`. The parent session's worktree base predates #9753 (its `TOTAL=52` and missing api-key rows prove it) | Do not "fix" a green test. Add the regression guard and hermeticity fix (Phase 4) |
| "if it is a leftover of a falsified Stage 2 paraphrase experiment, retire the broken stage" | Stage 2 is live: `kb-search/SKILL.md` documents it, `plugins/soleur/test/kb-search-lockstep.test.sh` pins the `stage-2-paraphrase-union-v1` token in both files, the Stage 2 row passes on main. The cause was a mock missing `"type":"text"` after #8394 changed the reader | Stage 2 is not retired |
| #9790 and ADR-053 row 6: `claude-code-review.yml` "fires per PR", an "unbounded per-PR spend surface" | `gh api repos/jikig-ai/soleur/actions/workflows`: `state: disabled_manually`, updated 2026-02-12; 40 runs ever, newest 2026-02-12; $0 spend | Verdict "dropped: disabled". Append a supersession note to ADR-053. Re-enabling is a separate decision |
| #9790: "the repo holds no measured monthly spend per candidate" | The markers (ADR-108, ADR-243) carry `cost_usd`; `scripts/betterstack-query.sh` reads them | Gate 0 runs on measured numbers; the recipe is recorded for re-runs |
| Cron spend "compounds" | Per-run cost fell 4-5x between 2026-09-29 and 2026-10-01 for all four crons (coincident with #9236; causation not established), so earlier windows overstate the regime | Gate 0 measures the post-cutover window only |
| `'standard'` pins are "mechanical on paper" and cost money | They live in opt-in `Workflow`-tool ports (`review/SKILL.md` "Dynamic-workflow alternative (opt-in)"); 0 workflow transcripts exist under `~/.claude/projects`; the token tee cannot see workflow spawns (ADR-053 finding 1), so nothing meters them | "Unmetered, therefore not eligible" (not "not worth it") plus a re-open trigger |
| Comment 2: the CLI bump "may retarget the CLI's internal small/fast model to Haiku 5.5. This was not verified" | Verified on 2.1.293 with the `soleur-ci-eval` key: the `haiku` alias resolves to `claude-haiku-5-5` and the internal WebFetch summarizer call reports `claude-haiku-5-5` in `modelUsage`; Bash-only runs emit no internal call (evidence file section 3, $0.058) | Copy the table into the addendum; no re-run |

## Research Insights

**Premise validation.** Checked: #9790 open (`priority/p3-low`, `type/chore`, milestone Post-MVP / Later),
no PR closes it; draft PR #9823 exists; #9785 merged (`73d5b13a9a`); `HAIKU_MODEL` is `claude-haiku-5-5`;
CLI pin `@anthropic-ai/claude-code` `2.1.293` in `apps/web-platform/package.json`; ADR-053's 2026-10-08
addendum lists these candidates; `plugins/soleur/skills/model-launch-review` exists. **Stale premises:**
the 51/1 baseline and the claude-code-review spend claim. ADR corpus check: ADR-053 (attestation),
ADR-110 (`cheap` maps to the `haiku` alias, `standard` to `sonnet`), ADR-243 (per-run budgets, burn
alert), ADR-244 (spend-limited `soleur-ci-eval` key), ADR-056 (CI spend ledger, empty). None rejects the
approach; ADR-053 requires each re-tier to be a separately attested change, which is why a class that
would move gets its own PR.

**Property List.**
1. Every #9790 candidate has a recorded verdict backed by a measurement.
2. No class moves without quality evidence against the Sonnet 5.5 control and a non-silent failure path.
3. The `PIN_ALLOWLIST` attestation rule is honoured.
4. Each design question ends in a recorded decision with a trigger or an artifact.
5. A caller's environment cannot change the bench self-test's verdict or make it spend.
6. A regression in the bench self-test is caught by CI within one PR.

**Cut List.**

| Mechanism proposed or implied | Property | Verdict |
|---|---|---|
| One `eval-harness` arm per candidate (built up front) | 1, 2 | Cut for classes failing Gate 0 (the issue's own drop rule). Kept as a short pointer (Phase 3) |
| N=60 Haiku probes for leader truncation and refusal | 4 | Cut (review): synthetic payloads say little about production, `leader_refused` and `leader_response_truncated` already page, and the issue says to decide with production data. Decision rules and triggers are recorded instead |
| A new Sonnet retry on a Haiku refusal | 4 | Cut: decided with the observed refusal rate (the page is the trigger) |
| `effort: "low"` plus `promptVersion` bump on the leader modules | 4 | Cut with the probes; the trigger is the `leader_response_truncated` page |
| Recording every `modelUsage` key in the cost marker | 4 | Cut: Bash-only crons emit no internal call (measured); the limit is recorded |
| Retiring or rewriting Stage 2 | 5 | Cut: live and green |
| A committed spend-measurement script | 1 | Cut: `betterstack-query.sh` plus a recorded `jq` recipe |
| Census of global env reads and a relative-PATH row in the bench guard | 5 | Cut (review): the zero-calls recorder catches a leak without a regex over bash |
| `LIVE_API=1` header line | 5 | Deleted: documentation only, never read (`grep` finds it only at lines 29 and 125) |

**Institutional learnings applied.** `2026-10-09-a-model-launch-is-a-pin-a-rate-card-and-a-token-budget-not-a-string-swap.md`;
`2026-09-24-my-test-stub-was-bypassed-by-env-and-my-harness-verified-the-first-definition.md` and
`2026-10-01-an-ambient-ci-variable-is-inherited-by-every-nested-runner-and-a-gate-on-it-needs-a-scrub.md`
(the hermeticity class); `2026-09-23-the-alert-i-was-told-paged-routed-to-nobody.md` (verify the route,
not the declaration); `2026-10-01-an-alert-guard-pinned-the-declaration-and-the-command-text-not-the-consumer.md`
(the contract test reads the emit sites).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing in the base plan (an ADR, a rate alert, a test and a measurement); worst case a founder's `domain-router` or email-summary degradation goes unpaged if the new alert is mis-tagged, which is today's state.
- **If this leaks, the user's workflow is exposed via:** the `soleur-ci-eval` key used by the plan-time and work-phase measurements (a $100/month-capped CI workspace, not production BYOK or operator keys); inputs are synthesized, so no founder content reaches any call.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** no founder-facing code path changes (the conditional leader `effort` edit was cut), so one user's breach cannot come from this diff; this PR edits no leader module, and any later change that touches `agent-on-spawn-requested` or a leader module must be planned as `single-user incident` (CPO sign-off before work starts), not flipped mid-implementation.

## Domain Review

**Domains relevant:** engineering, finance

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Proceed; the no-move verdict is the right size. Adopted: the new alert needs its `alert-reference.json` entry and the dead-letter contract-test pattern (two emit sites with different `feature` values, so an `in` clause); the bench suite needs a `scripts/suite-durations.tsv` row (10 s fast-tier cap, `scripts/test-all-fast-tier-budget.test.sh`) and a `scripts/lib/test-affected-paths.sh` edge, and must run hermetically; the cost marker keeps only the first `modelUsage` key (recorded, no source change); close or re-scope #9790 instead of leaving it open; define a re-open trigger; word the workflow-pin verdict "unmetered, not eligible".

### Finance (CFO)

**Status:** reviewed
**Assessment:** Reusing `claude_cost_daily_burn_usd = 25` as a monthly floor mixes units (it is a per-24h anomaly alarm). Adopted: a payback rule (12-month saving at least 3x the one-time cost of evaluating and moving a class, $10/month minimum), a post-cutover window, the null-marker rate and missing days reported per cron, and a conservative 0.65 saving factor (0.87 is the ceiling). The shared $100/month eval workspace can soft-skip at its cap, so a skipped arm is a non-result, never a pass.

Legal (CLO) not spawned: no `PIN_ALLOWLIST` entry changes. If Gate 0 ever sends a workflow pin to an eval, the CLO attestation becomes a prerequisite of that separate PR. Product/UX: no user-facing surface.

## Architecture Decision (ADR/C4)

### ADR
Amend ADR-053 with an append-only **Addendum — 2026-10-09 (#9790)** (Phase 5): Gate 0 method and
numbers, the per-class verdicts, the CLI internal-model table, the design-question dispositions, the
re-open triggers, and supersession blockquotes (existing convention) under the 2026-10-08 "Candidate,
not adopted" row for the "fires per PR" claim and the "tracked as #9790" sentence. No new ADR: no new
decision boundary, and the tiering policy is unchanged.

### C4 views
No C4 change. Checked against `model.c4` / `views.c4` / `spec.c4`: external systems `anthropic`,
`sentry`, `betterstack`, `doppler`, `github` and the edges `evalharness -> anthropic` (soleur-ci-eval,
ADR-244) and `github -> anthropic` already exist; there is no new actor, system, data store or access
relationship (an alert rule is a member of the modeled `sentry` system; the `sentry -> founder` edge
prose carries no alert count). `plugins/soleur/test/c4-count-parity.test.sh` passes 13/0 on this tree
and must pass after the change.

### Sequencing
All verdicts are measured now; the addendum is authored in final form in this PR.

## Infrastructure (IaC)

### Terraform changes
`apps/web-platform/infra/sentry/issue-alerts.tf`: one `sentry_alert` (`haiku-no-text-block-rate`) in the
existing root and provider pin; no new variables or secrets. Plus the `alert-reference.json` entry.

### Apply path
Existing: `apply-sentry-infra.yml` auto-applies `infra/sentry/**` on push to main, then
`sentry-alert-live-fidelity.sh` runs. No downtime; blast radius is one new email alert.

### Distinctness / drift safeguards
A new rule takes an unused `frequency_minutes` (`grep -h frequency_minutes apps/web-platform/infra/sentry/*.tf`).

### Vendor-tier reality check
`sentry_alert` rules are in use at the current tier (44 rules); no tier gate applies.

## Encryption Posture

Skipped by the gate's rule: no persistent store and no new cross-component connection (the measurement
calls `api.anthropic.com` over TLS as `evalharness -> anthropic` already does; the alert is a rule in an
existing Sentry project).

## Open Code-Review Overlap

One open code-review issue names a planned file: #8800 (`scripts/lib/test-affected-paths.sh`, census
sandbox shares inodes with the live repo). **Acknowledge:** a different concern; this plan adds one edge
block and does not touch the census sandbox. It stays open. No other planned file is named.

## Gate 0 — the pre-registered spend gate

Fixed before any eval exists so the result cannot choose its own threshold.

- **Population:** `cron-daily-triage`, `cron-follow-through-monitor`, `cron-campaign-calendar`,
  `cron-community-monitor`, `claude-code-review.yml`, and the seven `'standard'` pins (`classify`,
  `parse`, `analyze`, `commit`, `report`, `cluster`, `detect-threshold`).
- **Measure:** `S` = projected Sonnet 5.5 spend per 30 days over the **post-cutover window** (days after
  the last observed regime change; 2026-10-01 onward, 9 days at plan time, widening to a trailing 14
  days once available), paid markers only. Daily crons: window sum / window days x 30. Weekday and
  weekly crons: mean paid run x runs per 30 days. Report the null-cost marker count and missing days per
  cron, because null markers and out-of-credit days bias `S` downward, the unsafe direction for a
  "nothing qualifies" verdict. Recipe: evidence file section 2.
- **Saving:** `S x 0.65` (Haiku may need more turns and retries; the ceiling `S x 0.87` is the
  cache-read price ratio after tokenizer inflation and is shown once for sensitivity).
- **Threshold:** a class qualifies for evaluation iff its saving is at least **$12.50/month**: its
  12-month saving is at least 3x an assumed $50 one-time cost to evaluate and move one class (about $10
  of eval spend plus one implementer pipeline run; the $50 is an assumption, labelled as one in the
  addendum), and never below a $10/month minimum.
- **Unmetered or disabled:** not eligible (recorded as "unmetered" or "disabled", never "not worth it").
- **Plan-time result (2026-10-09, post-cutover):**

| Class | `S` (Sonnet 5.5, /mo) | Saving at 0.65 | At ceiling 0.87 | Null/zero markers | Qualifies |
|---|---:|---:|---:|---:|---|
| `cron-community-monitor` | $9.08 (13 runs) | $5.90 | $7.90 | 0 | No |
| `cron-daily-triage` | $5.36 (9 runs) | $3.48 | $4.66 | 0 | No |
| `cron-follow-through-monitor` | $3.10 (7 runs) | $2.01 | $2.69 | 0 | No |
| `cron-campaign-calendar` | $1.56 (1 run; 5-run all-regime mean gives $5.91) | $1.01 | $1.35 | 0 | No |
| `claude-code-review.yml` | $0 (disabled since 2026-02-12) | $0 | $0 | not applicable | Not eligible: disabled |
| `'standard'` pins x7 | unmetered (0 transcripts) | not applicable | not applicable | not applicable | Not eligible: unmetered |

  The only figure that reaches the line is the stale pre-cutover 14-day community-monitor window at the
  ceiling factor ($15.18), recorded in the evidence file as the reason the regime change matters.
- **Re-open trigger:** at each `model-launch-review`, whenever any class's post-cutover `S` reaches
  $19.23/month (= $12.50 / 0.65), when `claude-code-review.yml` is re-enabled, or when workflow metering
  exists.
- **Rule for the work phase:** re-run on the work date and apply the table mechanically. A class that
  qualifies then follows Phase 3; any other keeps its current model with the verdict recorded. No class
  moves without Phase 3 evidence.

## Implementation Phases

### Phase 1 — Gate 0 re-measurement and verdicts (no model spend)

1. Re-run the Better Stack pull and `jq` recipe (evidence file section 2) for the post-cutover window;
   fill the Gate 0 table (S, null/zero markers, missing days).
2. Re-check `gh api repos/jikig-ai/soleur/actions/workflows` for `claude-code-review.yml`. The
   workflow-pin verdict rests on ADR-053 finding 1 (nothing meters workflow spawns); the
   `find ~/.claude/projects -path "*subagents/workflows/*" -name "agent-*.jsonl" | wc -l` count is
   informational and machine-local, not a gate.
3. Apply the table. Record a verdict per class.

### Phase 2 — Design-question dispositions (no new probes)

Recorded in the ADR addendum:

1. **CLI internal model (comment 2):** the measured table (alias resolves to `claude-haiku-5-5`;
   internal WebFetch call reports `claude-haiku-5-5`; Bash-only runs emit no internal call). The cost
   marker's `model` is the first `modelUsage` key while `cost_usd` is the all-model total; the cron
   prompts are Bash-only so the cron cost shift cannot come from internal calls. No code change.
2. **Leader-loop effort (comment 1):** no change. The trigger is armed: a `leader_response_truncated`
   dead letter pages via `spawn-agent-dead-letter` (it is in `PAGED_DEAD_LETTER_REASONS`). Rule: on the
   first such page for a Haiku class, add `effort: "low"` to that `LeaderPromptModule`, bump
   `promptVersion`, and re-classify that change `single-user incident` (it touches the shared founder
   BYOK handler's input).
3. **Refusal and a Sonnet retry (comment 1):** no retry mechanism. `leader_refused` already pages on its
   first occurrence. Rule: decide a Sonnet 5.5 retry only if two or more `leader_refused` pages arrive
   for non-adversarial input within 30 days, using that observed rate.
4. **`no-text-block` mirrors (comment 1):** Phase 3.

### Phase 3 — Alert on the `no-text-block` mirrors (tests first)

1. Write `apps/web-platform/test/sentry-no-text-block-alert-op-contract.test.ts` first (RED), modelled on
   `sentry-spawn-dead-letter-alert-op-contract.test.ts`: derive emit sites by scanning `server/` for
   `op: "no-text-block"` (not a hard-coded list), assert each `(feature, op)` pair is matched by the
   alert's `tagged_event` conditions parsed from `issue-alerts.tf`, assert at least 2 sites were found,
   and assert the trigger is a rate (`event_frequency_count`, value at least 1), not a first-seen page.
2. Add `sentry_alert.haiku_no_text_block_rate` to `issue-alerts.tf`:
   `trigger_conditions = [{ event_frequency_count = { interval = "1h", value = 4 } }]`;
   `action_filters` with `tagged_event op eq no-text-block` and `tagged_event feature in
   domain-router,email-triage`; email to `issue_owners` with `ActiveMembers` fallthrough (the
   `spawn_agent_dead_letter` route); `frequency_minutes = 37` (taken today: 5, 10-36, 60-63, 120, 240, 1440-1442; re-check with `grep -h frequency_minutes` when editing); `lifecycle { ignore_changes =
   [environment] }`. `reportSilentFallback(null, ...)` takes the `captureMessage` path with a constant
   message per site, so each site is one Sentry issue and `event_frequency_count` (per issue) counts it
   correctly. The threshold is provisional: the emit sites shipped today and no baseline exists; the
   addendum records a recalibration step.
3. Add the `alert-reference.json` entry and update the README count by the procedure in
   `apps/web-platform/infra/sentry/README.md` (read it first). Run the contract test,
   `bash scripts/sentry-alert-reference-gate.sh` and `bash plugins/soleur/test/c4-count-parity.test.sh`.

### Phase 4 — Bench self-test: guard and hermeticity (tests first)

1. Write `scripts/learning-retrieval-bench.test.sh` first (RED against the unfixed script). It runs
   `bash scripts/learning-retrieval-bench.sh --self-test` **once**, as a subprocess under an explicitly
   constructed hostile environment (`env -i` plus an allowlist, no inherited `GIT_*`) that sets
   `NO_PARAPHRASE=1`, a synthetic key-shaped `ANTHROPIC_API_KEY` and `CURL_BIN` pointing at a recording
   stub the wrapper owns. One run is enough: the hostile environment is a superset of the clean one, and
   a measured self-test run costs 3.6 to 9.1 s on this host, so three runs would breach the 10 s
   fast-tier cap. Before the run the wrapper calls the recorder once itself and asserts it counted 1
   (positive control), then truncates it. It asserts `FAIL=0`, `TOTAL` at or above the bench's own `ST_MIN_ASSERTIONS`, the
   named rows `Stage 2 union-of-paraphrases recovers target` and `api-key: precondition` present, and
   that the recorder holds **zero** calls afterwards (Stage 2 and the key-guard rows override `CURL_BIN`
   locally with their own stubs, so any call reaching the global one is a leak).
2. Fix `scripts/learning-retrieval-bench.sh`: at the top of `self_test()` set `NO_PARAPHRASE=0`,
   `unset ANTHROPIC_API_KEY`, and point `CURL_BIN` at a fail-closed stub (records the call, exits
   non-zero) before the first fixture. Delete the `LIVE_API=1` lines (29 and 125).
3. Register the suite: measure its weight first. At or under the 10 s cap it is an always-on fast-tier
   suite (an `ALWAYS_ON_SUITES` entry in `scripts/lib/test-affected-paths.sh`); over it, it is
   edge-selected only (an `AFFECTED_*_PATHS` block and no `ALWAYS_ON_SUITES` entry; the budget lint
   `scripts/test-all-fast-tier-budget` pins the always-on set). Add the `scripts/suite-durations.tsv` row, the
   `scripts/lib/test-affected-paths.sh` `AFFECTED_*_PATHS` block (subject
   `scripts/learning-retrieval-bench.sh`); read the `scripts/test-all.sh` header and `scripts/test-all-fast-tier-budget.test.sh` first
   and confirm with `bash scripts/test-all.sh --print-selection --paths=scripts/learning-retrieval-bench.sh`.
4. No tracking issue: the failure is not on main (`wg-when-tests-fail-and-are-confirmed-pre` covers
   failures confirmed on main) and the hardening is inline.

### Phase 5 — ADR-053 addendum and issue disposition

1. Append the addendum (short bullets): Gate 0 method, assumptions and table; per-class verdicts; the CLI
   table; the Phase 2 dispositions and triggers; the alert; the re-open trigger; the supersession
   blockquotes. Quote cache-read rates, not headline rates (the ADR's own instruction).
2. PR body: `Closes #9790` **only if AC1 through AC7 are all delivered in this PR**, else `Ref #9790`
   with the undelivered items listed. State the stale-base finding, that no tracking issue was filed, and
   the measurement spend actually incurred.

### Phase 3b — Pointer for a class that qualifies (not planned work)

If Phase 1 finds a class at or above the line, it moves in its **own** PR (ADR-053: "a separate
clo-attestation-class model-bump PR"), carrying the CLO attestation; a workflow pin edits `PIN_ALLOWLIST`
in `plugins/soleur/test/workflow-model-pins.test.ts` in the same change; a cron adds a constant to
`model-tiers.ts` and pins it in `model-tiers.test.ts`. Its evidence: an `eval-harness` arm with Sonnet
5.5 control vs Haiku 5.5, the production prompt constant imported (never hand-copied), synthesized
fixtures (at least 12, at least 4 with embedded instructions), repeat 5, noise = the control's own SD
over repeats, pass iff the candidate mean is at least control mean minus `max(1 task, 2 x SD)` with zero
adversarial failures and no `max_tokens` or `refusal` stop; every failure mode of the class names its
production detector (or the same PR adds one); a capped, rate-limited or under-powered arm is "stays:
insufficient evidence", never a pass; at most $15 and `pipeline-tally.sh gate agent_rounds` before each
arm. This PR uses `Ref #9790` until that PR merges.

## Files to Edit

- `knowledge-base/engineering/architecture/decisions/ADR-053-per-call-model-tiering-for-workflow-subagent-spawns.md` (append addendum and supersession notes)
- `scripts/learning-retrieval-bench.sh` (self-test environment reset; delete `LIVE_API` lines)
- `apps/web-platform/infra/sentry/issue-alerts.tf` (one rule)
- `apps/web-platform/infra/sentry/alert-reference.json` (one entry)
- `apps/web-platform/infra/sentry/README.md` (rule count)
- `scripts/lib/test-affected-paths.sh` (suite edge)
- `scripts/suite-durations.tsv` (weight row)

## Files to Create

- `scripts/learning-retrieval-bench.test.sh`
- `apps/web-platform/test/sentry-no-text-block-alert-op-contract.test.ts`
- `knowledge-base/project/specs/feat-one-shot-haiku-5-5-retiering-bench-fix/plan-time-evidence.md` (created at plan time)
- `knowledge-base/project/specs/feat-one-shot-haiku-5-5-retiering-bench-fix/tasks.md` (created at plan time)
- `knowledge-base/project/specs/feat-one-shot-haiku-5-5-retiering-bench-fix/decision-challenges.md` (created at plan time)

Paths verified with `ls` / `git ls-files` against this worktree on 2026-10-09. The one glob used
(`~/.claude/projects/**/subagents/workflows/agent-*.jsonl`) is an observation, not an edit.

## Observability

```yaml
liveness_signal:
  what: "Sentry alert rule haiku-no-text-block-rate exists and is enabled; sentry-alert-live-fidelity.sh compares the live rule to alert-reference.json after every apply"
  cadence: "after every apply-sentry-infra.yml run and daily (existing live-fidelity job)"
  alert_target: "operator email via issue_owners with ActiveMembers fallthrough (same route as spawn-agent-dead-letter)"
  configured_in: "apps/web-platform/infra/sentry/issue-alerts.tf (haiku_no_text_block_rate)"
error_reporting:
  destination: "Sentry (reportSilentFallback message path, tags feature and op); Better Stack SOLEUR_CLAUDE_COST markers for spend"
  fail_loud: "yes: the alert pages on rate; a measurement that hits a cap or limit error is recorded as a non-result, never a pass"
failure_modes:
  - mode: "Alert filter drifts from the emit sites (renamed op or feature, a third emit site)"
    detection: "sentry-no-text-block-alert-op-contract.test.ts derives the sites by scan and fails the PR"
    alert_route: "CI red on the PR"
  - mode: "Systemic Haiku fall-back to the CPO leader (domain-router) or class-less email summaries"
    detection: "haiku-no-text-block-rate: five or more events of one issue in an hour"
    alert_route: "operator email (issue owners, ActiveMembers)"
  - mode: "Leader loop truncates or refuses on a Haiku class in production"
    detection: "existing spawn-agent-dead-letter rule pages leader_response_truncated and leader_refused"
    alert_route: "operator email, runbook spawn-dead-letter-triage.md"
  - mode: "A class starts to qualify because spend rose (regime reversal)"
    detection: "re-open trigger: post-cutover S reaches $19.23/month, checked at each model-launch-review with the recorded recipe"
    alert_route: "model-launch-review checklist; the daily $25 burn alert covers an anomaly"
  - mode: "Bench self-test regresses again unnoticed"
    detection: "scripts/learning-retrieval-bench.test.sh runs in test-all and CI"
    alert_route: "CI red on the PR"
logs:
  where: "Sentry project events; Better Stack source 2457081 via scripts/betterstack-query.sh (hot window plus archive arm)"
  retention: "Sentry and Better Stack vendor retention; the evidence file is committed"
discoverability_test:
  command: "grep -c 'name *= \"haiku-no-text-block-rate\"' apps/web-platform/infra/sentry/issue-alerts.tf"
  expected_output: "1"
```

## Test Scenarios

1. `NO_PARAPHRASE=1 bash scripts/learning-retrieval-bench.sh --self-test` reports `FAIL=0` (today: 173/4).
2. With a synthetic `ANTHROPIC_API_KEY` and a recording `CURL_BIN`, the self-test finishes in seconds and the recorder holds zero calls after a positive-control call counted 1 (today: killed at 45 s after 9 calls).
3. A mutated bench with the reset deleted turns scenario 1 or 2 RED (Guard 1).
4. Renaming `op: "no-text-block"` at one emit site, or adding a third site, turns the alert contract test RED (Guard 2).

## Guard Contract

### Guard 1 — Bench self-test verdict is independent of the caller's environment

**Property.** The self-test outcome depends only on repository contents, never on `NO_PARAPHRASE`, `ANTHROPIC_API_KEY`, `CURL_BIN` or another variable the script reads at global scope, and the self-test never reaches the global `CURL_BIN`.

**Assembly.** The chokepoints are (a) the global-scope environment reads in `scripts/learning-retrieval-bench.sh` (`NO_PARAPHRASE="${NO_PARAPHRASE:-0}"`, `CURL_BIN="${CURL_BIN:-curl}"`, the `ANTHROPIC_API_KEY` reads in `kbsearch_rank` and `anthropic_paraphrase`), (b) the `--no-paraphrase` flag that sets the same global, and (c) the single HTTP call site `"$CURL_BIN"` in `anthropic_paraphrase`, reached from `kbsearch_rank` (every fixture with fewer than five baseline hits) and from `self_test_api_key_guard`. Property (c) is enforced by a recorder on the global `CURL_BIN` that must stay empty, because Stage 2 and the key-guard rows override `CURL_BIN` with their own stubs; a fixture added later that leaks reaches the recorder without any list being updated.

**Mutation matrix.**

| # | Edit that MUST turn the wrapper RED | Targets |
|---|---|---|
| 1 | Delete the `NO_PARAPHRASE=0` reset (wrapper exports `NO_PARAPHRASE=1`) | the env leak itself (173/4 today) |
| 2 | Delete the `unset ANTHROPIC_API_KEY` / fail-closed `CURL_BIN` line (wrapper exports a key and a recording `CURL_BIN`) | live-call leak |
| 3 | Add a second fixture after Stage 2 that calls `kbsearch_rank` on a low-hit query through the global `CURL_BIN` | second member after a compliant first |
| 4 | Move the reset to after `self_test_flooding_pathology` | the window: only a recorder that observes during the earlier fixtures sees it |
| 5 | Short-circuit `self_test()` with `exit 0` before the cases | dispatch: TOTAL floor and named-row presence |

**Harness rows.** RED: replace the wrapper's summary parsing with `true` and confirm a mutated bench that prints `PASS=177 FAIL=0` without running cases is still caught by the named-row check; replace the recorder with `true` and confirm the positive control (one direct call must count 1) reds, so a dead recorder cannot read as "zero calls". Must-PASS non-canonical: an unrelated environment (`FOO=bar LC_ALL=C TZ=Asia/Tokyo`) added to the hostile one leaves the suite green.

**Anchor.** The stored value is the `ST_MIN_ASSERTIONS=177` floor, a count that survives any substitution keeping the count; it is paired with set identity (the named rows). A weakening that lowers the floor and deletes rows must also edit the wrapper's named-row list in the same diff, so this guard proves consistency, not integrity; no outside-the-commit anchor exists for this file and the plan does not claim one.

### Guard 2 — The alert filter matches the emit sites

**Property.** Every `reportSilentFallback` emit with `op: "no-text-block"` carries a `(feature, op)` pair matched by the alert's filter, and the alert is a rate rule, not a first-seen page.

**Assembly.** Three copies must agree: the emit sites (derived by scanning `apps/web-platform/server/` for `op: "no-text-block"`; today `domain-router.ts` and `email-triage/summarize.ts`, both through `noTextBlockExtra`), the `tagged_event` conditions in `issue-alerts.tf`, and the `alert-reference.json` entry (agreement with the `.tf` is enforced by the existing `sentry-alert-reference-gate.sh`, not re-implemented). The scan is by emit site, not by the `noTextBlockExtra` helper, because a new caller can emit without it.

**Mutation matrix.**

| # | Edit that MUST turn the contract RED | Targets |
|---|---|---|
| 1 | Rename `op` at one emit site | emit-vs-alert drift |
| 2 | Add a third emit site with a new `feature` and the same op, alert unchanged | second member after a compliant first |
| 3 | Point the scan at a wrong directory so it finds zero sites | dispatch: floor of at least 2 sites |
| 4 | Set the trigger to `first_seen_event` or `value = 0` | the rate-not-page property |

**Harness rows.** RED: remove the emit-site regex from the test and confirm the dispatch floor reds. Must-PASS non-canonical: an emit site that adds extra tags (`source`, `gitKind`) beyond `feature` and `op` still matches.

**Anchor.** The live Sentry project state after apply (`sentry-alert-live-fidelity.sh`, outside the commit) must equal the reference; a diff that edits both the `.tf` and the JSON cannot pass that check unless the live rule matches.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Issue #9790: the eval-gated re-tiering of triage/summarize-shaped crons, mechanical 'standard' workflow pins and claude-code-review.yml to Haiku 5.5" [brief] | Gate 0, Phase 1, Phase 3b, Phase 5 | mapped |
| 2 | "Read the issue body and ALL comments on it" [brief] | Research Reconciliation, Phase 2, Phase 3 | mapped |
| 3 | "Build the eval arms on the eval-harness skill (Sonnet 5.5 as control) with synthesized inputs only and the spend-limited soleur-ci-eval key" [brief] | Phase 3b protocol, built only for a class that passes Gate 0 | mapped — conditional by the issue's own drop rule |
| 4 | "move only the classes whose quality is within the control's noise and whose failure is not silent" [brief] | Phase 3b pass rule | mapped |
| 5 | "drop candidates whose measured spend is negligible" [brief, issue #9790] | Gate 0 | mapped |
| 6 | "record the per-class verdicts in an ADR-053 addendum" [brief] | Phase 5 | mapped |
| 7 | "Honour ADR-053's attestation rules (workflow-model-pins.test.ts PIN_ALLOWLIST)" [brief] | Phase 3b attestation clause; no allowlist edit otherwise | mapped |
| 8 | "leader-loop effort" [issue comment 1] | Phase 2 item 2 | mapped |
| 9 | "a Sonnet retry on a Haiku refusal" [issue comment 1] | Phase 2 item 3 | mapped |
| 10 | "alerting on no-text-block Sentry mirrors" [issue comment 1] | Phase 3 | mapped |
| 11 | "verifying which model the claude-code CLI 2.1.293 internal small/fast calls report" [issue comment 2] | Phase 2 item 1 (measured at plan time) | mapped |
| 12 | "find the root cause and fix it (or, if it is a leftover of a falsified Stage 2 paraphrase experiment, retire the broken stage cleanly), and make the self-test green" [brief] | Phase 4 (root cause found; already green on main; guard and hermeticity added) | mapped |
| 13 | "file a tracking issue for the bench failure only if the filing gate allows it, otherwise fix it inline and say so" [brief] | Phase 4 item 4 and Phase 5 item 2 | mapped |
| 14 | "Close #9790 via a Closes line in the PR body only when its acceptance work is actually done" [brief] | Acceptance Criteria closure rule, Phase 5 item 2 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Gate 0 spend gate | "drop candidates whose measured spend is negligible" | asked |
| Payback rule, 0.65 factor, null-marker reporting | — | inferred — justification: the issue says "negligible" with no number, and the CFO review showed the repo's $25 daily burn constant is the wrong unit; a stated threshold is what makes "negligible" checkable |
| Decision rules and triggers for leader effort and refusal retry | "leader-loop effort" and "a Sonnet retry on a Haiku refusal" | asked |
| New `haiku-no-text-block-rate` rule | "alerting on no-text-block Sentry mirrors" | asked |
| Alert contract test and `alert-reference.json` entry | — | inferred — justification: the root's `sentry-alert-reference-gate.sh` requires the entry and the dead-letter contract-test precedent rejects a rule whose filter is not pinned to its emit sites |
| `scripts/learning-retrieval-bench.test.sh` and suite registration | "make the self-test green" | inferred — justification: the self-test stayed red 18 days because nothing runs it; green only stays green if CI runs it |
| Self-test environment reset | "find the root cause and fix it" | inferred — justification: the investigation found two caller-environment leaks (one with live egress) in the function that failed |
| `LIVE_API` line deletion | "find the root cause and fix it" | inferred — justification: a documented knob that nothing reads misleads whoever tries to opt in |
| ADR-053 addendum and supersession notes | "record the per-class verdicts in an ADR-053 addendum" | asked |
| `plan-time-evidence.md` | "find the root cause with evidence" | asked |

### Split Assessment

- Subsystems touched: 3 — `scripts/`, `apps/web-platform/` (infra/sentry, test), `knowledge-base/`
- Planned files: 10 | Estimated changed lines: about 350
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. A qualifying class would move in its own separately attested PR (Phase 3b).

## Acceptance Criteria

**#9790 closure rule.** The PR body carries `Closes #9790` only when AC1 through AC7 are all delivered in this PR; otherwise it carries `Ref #9790` and lists the undelivered items. A qualifying class that moves is a separate PR, and this PR uses `Ref` until it merges.

- [ ] **AC1 (spend measured).** The ADR addendum holds the Gate 0 table (S, null/zero markers, missing days) for every candidate and names the command that produced it. Verify: `grep -c "Gate 0" knowledge-base/engineering/architecture/decisions/ADR-053-*.md` is at least 1.
- [ ] **AC2 (verdict per class).** Each of the four crons, `claude-code-review.yml` and the seven `'standard'` pins has a recorded verdict with its reason (below threshold, disabled, or unmetered).
- [ ] **AC3 (no unevidenced move).** `git diff $(git merge-base origin/main HEAD) --stat -- plugins/soleur/test/workflow-model-pins.test.ts apps/web-platform/server/inngest/model-tiers.ts` is empty, and `bun test plugins/soleur/test/workflow-model-pins.test.ts` passes.
- [ ] **AC4 (design questions).** The addendum records the CLI internal-model table and the leader-effort, refusal-retry and attribution-limit dispositions with their triggers.
- [ ] **AC5 (alert).** `grep -c 'name *= "haiku-no-text-block-rate"' apps/web-platform/infra/sentry/issue-alerts.tf` prints `1` and `alert-reference.json` carries the entry; the contract test, `bash scripts/sentry-alert-reference-gate.sh` and `bash plugins/soleur/test/c4-count-parity.test.sh` pass.
- [ ] **AC6 (bench).** The self-test is green in a clean environment, with `NO_PARAPHRASE=1` exported, and with a synthetic key plus recording `CURL_BIN` (zero recorded calls); `bash scripts/learning-retrieval-bench.test.sh` passes and each Guard 1 mutation turns it RED; `bash scripts/test-all.sh --print-selection --paths=scripts/learning-retrieval-bench.sh` selects the suite.
- [ ] **AC7 (disclosure and hygiene).** The PR body states the stale-base finding, that no tracking issue was filed, and the spend incurred; `git grep -n "sk-ant" -- knowledge-base/project/specs/feat-one-shot-haiku-5-5-retiering-bench-fix` is empty and no raw payload or marker file is committed.

## Non-Goals

- Re-enabling `claude-code-review.yml` (a product decision about a disabled advisory workflow).
- Migrating `pdf-chapter-router` or the two SDK-path scripts (tracked on #8643; its trigger is the SDK pin).
- Changing `EXECUTION_MODEL`, `AUDIT_MODEL` or any pin without Phase 3b evidence.
- N=60 synthetic leader probes, a Sonnet retry, or recording every `modelUsage` key (cut in review; triggers recorded).
- A committed spend-measurement tool (the recipe is enough until a second consumer exists).

## Risks and Sharp Edges

- **The threshold and the saving factor decide the outcome.** They are pre-registered with their basis, the only figure reaching the line is shown with why it is stale, and a re-open trigger exists, so the verdict can be re-run rather than argued.
- **The $50 one-time cost is an assumption**, labelled as such in the addendum.
- **Cost markers undercount** (null cost on timeouts, killed runs, out-of-credit days); Gate 0 reports the null/zero count so the reader can judge. The post-cutover window is only nine days at plan time; weekly crons have one to five runs, so their figures are weak and stated as such.
- **`Closes` lands before the alert is live.** The rule exists in Sentry only after the post-merge `apply-sentry-infra.yml` run; the PR-time gates (reference gate, contract test) prove the declaration and that workflow's `sentry-alert-live-fidelity.sh` proves the live rule, so a red apply is a new defect, not an undelivered AC.
- **Provisional alert threshold.** The emit sites shipped on 2026-10-09; five per hour per issue is a judgment and carries a recalibration step.
- **A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** It is filled above.
- **Fixtures and git.** The bench fixtures run `git init` and `commit`; the wrapper must construct its environment (no inherited `GIT_DIR`/`GIT_INDEX_FILE`), per `plugins/soleur/AGENTS.md` Test Fixture Conventions.
- **Do not print the key.** No `set -x` with the key set (the bench refuses with exit 78 for the same reason), no key on argv, none in committed output.
