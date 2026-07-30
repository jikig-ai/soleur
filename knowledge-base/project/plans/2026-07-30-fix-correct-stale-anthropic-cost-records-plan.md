---
title: "fix: correct the stale Anthropic API cost records"
date: 2026-07-30
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
cpo_signoff_disposition: "satisfied-at-review — see note under User-Brand Impact"
branch: feat-one-shot-anthropic-cost-records-correction
pr: 7086
---

# fix: correct the stale Anthropic API cost records

> `lane:` — no `spec.md` exists for this branch (direct one-shot entry, no brainstorm),
> so `lane` is defaulted to `cross-domain` fail-closed per the plan skill's TR2 rule.

> ## ⚠️ CORRECTED AT REVIEW (8-agent panel, 2026-07-30) — read this before the body
>
> The body below was written pre-review and contains **two claims the panel falsified**. They
> are left in place as the point-in-time record; the corrections are authoritative.
>
> 1. **"No fleet-wide figure exists and none is derivable"** — FALSE. ADR-108 emits a per-run
>    `SOLEUR_CLAUDE_COST` marker on every substrate exit (`cost_usd`, `source: cron:<name>`),
>    queryable from Better Stack with **no** `ANTHROPIC_ADMIN_KEY`; the SQL is committed in
>    `betterstack-log-query.md`. Only the **org-total** is blocked on #6297. The plan confused
>    it with `SOLEUR_CLAUDE_COST_DAILY` (a different marker, 47 lines away in the same file) —
>    the exact defect class this plan exists to remove, reproduced inside the fix.
> 2. **"21 Inngest crons"** — a raw file count. The correct figure is **15** claude-spawning
>    crons; the other 6 hits are a shared module, an event handler, two one-shots, a
>    comment-only match, and a workspace-helper-only importer. Separately,
>    `cron-compound-promote` and `cron-weekly-release-digest` spend on the same key over HTTP
>    *without* the substrate, so substrate-membership over- and under-counts simultaneously.
>
> Two further corrections: **`fix-constraints-stage-a` IS metered** (active, wires
> `Capture API spend`; its agent step is gate-red-only, so it is a zero-yield meter, not a
> missing one), and the **threshold was raised to `single-user incident`** because
> `expenses.md` feeds the operator digest's run-rate and is therefore a user-facing surface.
>
> **Resulting design change:** the row is SPLIT — `cron-ux-audit` stays in Product COGS at
> its narrow `15.00`; the 14-cron fleet becomes a new **R&D** row booking `UNMEASURED`
> (not a guessed number), which makes every containing subtotal a floor.

## Overview

Two rows in `knowledge-base/operations/expenses.md` describe Anthropic API spend against
mechanisms that no longer exist, and a third artifact — the ledger those rows point at — has
never received a record. The result is that the repo's cost records cannot answer the
question they exist to answer, and the one time someone asked it ("which CI jobs can we cut
to reduce Anthropic spend?") the records pointed at the wrong surfaces entirely.

This plan corrects the records. It does **not** change any CI workflow, any cron, or any
metering code.

The correction is larger than "two stale filenames" because the research surfaced that the
dominant Anthropic API-credit consumer is a **fleet of 21 Inngest crons** that spawn the
`claude` binary on the prod host — and **no expense row names any of them**. The `$15/mo`
"ux-audit" row is a single-cron artifact of that fleet, still citing the GitHub Actions
workflow the cron replaced.

### What actually draws on the org API credit

| Surface | Draws org API credit? | Ledgered today? |
|---|---|---|
| 21 Inngest crons using `_cron-claude-eval-substrate` (spawn `claude` on prod, operator `ANTHROPIC_API_KEY`; `AUDIT_MODEL = claude-opus-5`, `EXECUTION_MODEL = SONNET_MODEL`) | **Yes — dominant** | **No** (only ux-audit, and mis-attributed to a deleted workflow) |
| `cron-anthropic-credit-probe` (hourly 1-token canary) | Yes, negligible | No |
| `ci.yml` → `plugin-root-propagation-gate`, `sandbox-canary-capture-gate` (real Claude turn in `node:22-slim`, path-triggered) | Yes, rare | No |
| `fix-constraints-stage-a.yml` agent step (`claude-sonnet-5`, `--max-turns 20`) | Yes, only when the constraint gate is red | No |
| `claude-code-review.yml`, `test-pretooluse-hooks.yml` | **No** — dormant (see Premise Validation) | **Yes** — these are the only two the ledger row names |
| Per-user product inference (`cc-dispatcher`, `agent-runner`) | **No** — BYOK, `cost-model.md:244` | N/A (`$0` by architecture) |
| Interactive Claude Code sessions | **No marginal API cost** — Max 20x seats, `cost-model.md:175` records these as deliberately un-ledgered | N/A |

The last two rows are load-bearing: this plan must **not** introduce a claim that per-user
inference or local Claude Code loops draw org API credit. `cost-model.md` already states the
opposite, deliberately, and it is correct.

## Premise Validation

Every premise in the invocation was re-verified against the live repo and the GitHub API.

| Premise | Verdict | Evidence |
|---|---|---|
| `.github/workflows/scheduled-ux-audit.yml` does not exist | **HELD** | `ls` → absent; deleted in `5d3a1e11a` "feat(ux-audit): cron-ux-audit Inngest handler + GHA workflow delete" |
| `claude-code-review.yml` is dormant | **HELD** | workflow `state = disabled_manually`; 0 runs since 2026-07-01 (40 lifetime) |
| `test-pretooluse-hooks.yml` is dormant | **HELD** | `workflow_dispatch`-only; 3 runs lifetime, 0 since 2026-07-01 |
| `api-spend-ledger.jsonl` is empty | **HELD** | 0 records; 0 `api-spend-*` artifacts repo-wide (`--paginate`) |
| `fix-constraints-stage-a` rarely spends | **HELD** | 417 runs since 2026-07-01; agent step skipped in 25/25 sampled |
| `cost-model.md` mirrors the stale rows | **HELD (line numbers adjusted)** | actual: `:158` (CI row), `:175` (CI provenance prose), `:199` (ux-audit row) |
| ADR-074 forbids touching the constraint-gate duplication | **HELD** | ADR-074 §Decision — stage A must re-run the gate in the untrusted `pull_request` context; prior design tripped 3 critical CodeQL `actions/untrusted-checkout-toctou` alerts |
| The product's agent path is org-funded | **STALE — REVERSED** | `cost-model.md:244` — per-user inference is `$0` via BYOK, a "load-bearing architectural commitment". `byok-resolver.ts` implements it. Do **not** ledger it as org spend. |
| The metering gap needs a new tracking issue | **STALE — ALREADY TRACKED** | **#5692 OPEN** "Pre-exhaustion Anthropic spend-vs-budget alert (Ref #5674)"; **#6297 OPEN** "Enable Anthropic Admin cost-report cron (mint `ANTHROPIC_ADMIN_KEY` + land IaC)" |
| This is a novel failure | **STALE** | `cron-anthropic-credit-probe.ts:1-6` documents the **2026-06-29** precedent: credit hit zero, every claude-eval cron received `Credit balance is too low` and "silently no-op'd with GREEN monitors". #5674 shipped the hourly canary and is **CLOSED**. |

**Consequence of the last two rows:** no new tracking issue should be filed for the alerting
or attribution capability. Both halves already have open trackers. Filing a third would
fragment them.

## Research Reconciliation — Spec vs. Codebase

| Invocation claim | Codebase reality | Plan response |
|---|---|---|
| "Correct the ux-audit row's mechanism" | ux-audit is 1 of **21** crons on the shared `_cron-claude-eval-substrate`, all drawing the same key | Widen the row's scope to the fleet; do **not** silently keep a one-cron row |
| "The spend originates server-side with a Doppler-sourced key" | Correct — but the authoritative per-model figure is **unobtainable**: the Admin Cost & Usage API requires a team org, this org is an individual account, so `ANTHROPIC_ADMIN_KEY` is un-mintable (#6297) | Amount must carry an explicit `estimate` marker pinned to #6297, not a confident number |
| "Determine whether the $15/mo figure still holds" | It cannot be verified from any source this repo can read — `cron-anthropic-cost-report` self-reports `key-missing` indefinitely | State that plainly; do not restate `$15` as if verified, and do not invent a fleet-wide number |
| "Record the metering gap" | Already recorded in code comments and two open issues | Link #5692 + #6297 from the records rather than re-deriving the gap |

## Files to Edit

- `knowledge-base/operations/expenses.md` — the two Anthropic API rows (currently lines 50, 51)
- `knowledge-base/finance/cost-model.md` — lines 158 (CI row), 175 (CI provenance prose), 199 (ux-audit row)
- `knowledge-base/engineering/operations/runbooks/api-spend-reconciliation.md` — its stated inputs are the two dormant workflows

## Files to Create

None.

## Open Code-Review Overlap

**None.** Checked all 60 open `code-review` issues against each planned file path
(`expenses.md`, `cost-model.md`, `api-spend-reconciliation.md`) — zero body matches.

## Implementation Phases

### Phase 1 — Correct the ux-audit row (`expenses.md`)

1.1 Rewrite the row so its mechanism names the `cron-ux-audit` Inngest handler on the prod
host, not `.github/workflows/scheduled-ux-audit.yml`. Cite the deleting commit `5d3a1e11a`
so the next reader can see why the old name was there.

1.2 Widen the row's scope to the claude-eval cron fleet, or add an adjacent row covering it.
The row title must stop implying ux-audit is the only Anthropic-drawing cron. Name the
substrate (`_cron-claude-eval-substrate`, 21 consumers) and the model tiers
(`AUDIT_MODEL = claude-opus-5`, `EXECUTION_MODEL = SONNET_MODEL`) since the tier is the cost driver.

1.3 Do **not** fabricate a fleet-wide amount. The `$15.00` figure was derived for ux-audit
alone under a mechanism that no longer exists. Carry it forward only as a last-known
ux-audit-scoped figure, explicitly labelled, and attach the file's existing estimate marker:

```
<!-- estimate verify_by=<date> owner=cfo source="Anthropic Console usage, or SOLEUR_CLAUDE_COST_DAILY once #6297 lands" -->
```

1.4 Delete the "Threshold warning at $15/run in workflow output" sentence outright — it
describes a workflow that does not exist, and no equivalent threshold check exists in the
cron path.

### Phase 2 — Correct the CI claude-code-action row (`expenses.md`)

2.1 Replace the two named sources with the surfaces that can actually spend:
`fix-constraints-stage-a.yml` (agent step, gate-red only) and the two `ci.yml` in-image
probes (`plugin-root-propagation-gate`, `sandbox-canary-capture-gate`).

2.2 Record that `claude-code-review.yml` is `disabled_manually` and `test-pretooluse-hooks.yml`
is dispatch-only, so the ledger's stated capture path produces nothing — and that
`api-spend-ledger.jsonl` is consequently empty.

2.3 Change the status from `accruing` to a value that is true. `accruing` asserts a
measurement in progress; nothing is being measured. The amount stays `0.00` (no evidence
supports any other number), but the status and note must not imply the `0.00` will be
replaced at "the first monthly reconciliation" — that reconciliation has no input.

2.4 Preserve the row's correct R&D-not-COGS classification and its Max-seat basis.

### Phase 3 — Reconcile `cost-model.md`

3.1 Line 199 (`Anthropic API (ux-audit cron)`) — align with the Phase 1 row.

3.2 Line 158 + the provenance prose at 175 — align with the Phase 2 row. The prose currently
says spend comes "from the two CI review jobs" and that the subtotal is "unchanged until the
first monthly reconciliation"; both must be corrected.

3.3 **Preserve unchanged:** the `$0 marginal` treatment of local Max-subscription loops
(`:175`) and the BYOK `$0` per-user inference commitment (`:244`). Both are correct. Add
nothing that contradicts them.

3.4 Record the metering gap where the document already documents its own provenance, linking
**#5692** (pre-exhaustion spend-vs-budget alert) and **#6297** (Admin cost-report attribution,
blocked on an un-mintable admin key pending a team-org conversion). Note that the org-total
figure is unobtainable until #6297 lands.

### Phase 4 — Annotate the reconciliation runbook

4.1 `api-spend-reconciliation.md` states its inputs are `api-spend-<run_id>` artifacts from
`claude-code-review.yml` + `test-pretooluse-hooks.yml`. Both are dormant, so the runbook
describes a procedure that will always find zero artifacts.

4.2 Add a dated status banner naming that fact and pointing at #6297 as the successor
mechanism. Do **not** delete the runbook — if the workflows are re-enabled it becomes correct
again, and its `gh`/`jq`-only, no-dashboard discipline is worth preserving.

### Phase 5 — Verification

5.1 Re-run every grep in the Acceptance Criteria.
5.2 Confirm no `.github/`, `apps/`, `plugins/`, or `scripts/` file is modified.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** *(scope corrected at /work — see note)* — no **live record** cites the deleted workflow:
  `grep -c 'scheduled-ux-audit\.yml' knowledge-base/operations/expenses.md knowledge-base/finance/cost-model.md knowledge-base/engineering/operations/runbooks/api-spend-reconciliation.md`
  returns **0** for all three.

  > **Why this AC was narrowed.** As originally written it asserted zero hits across all of
  > `knowledge-base/`, which returns **~40 files**. Every one is a point-in-time record —
  > historical plans, specs, brainstorms, and learnings that describe what was true when the
  > workflow existed, plus two `INDEX.md` entries that are merely the *titles* of those
  > documents. Rewriting them would falsify the historical record, and it is the documented
  > own-migration-artifact carve-out (`2026-06-03-path-rename-sweep-exclude-own-migration-artifacts.md`).
  > The defect this plan fixes is a **live claim about a current mechanism**, and exactly three
  > files made one. The AC now asserts that, which is the property that was actually broken.
- **AC2** — Neither `expenses.md` nor `cost-model.md` names `claude-code-review.yml` or `test-pretooluse-hooks.yml` as an *active* metered source. Verify by reading both rows in full; a mention that explicitly labels them dormant is permitted and expected.
- **AC3** — The ux-audit row names `cron-ux-audit` and the `_cron-claude-eval-substrate` fleet. `grep -c 'cron-ux-audit' knowledge-base/operations/expenses.md` ≥ 1.
- **AC4** — Any amount not derivable from a source this repo can read carries an `<!-- estimate verify_by=… owner=… source="…" -->` marker. Verify each Anthropic row either has the marker or a figure with cited provenance.
- **AC5** — Both open trackers are linked from the records: `grep -cE '#5692' knowledge-base/finance/cost-model.md` ≥ 1 **and** `grep -cE '#6297' knowledge-base/finance/cost-model.md` ≥ 1.
- **AC6** — The BYOK and Max-seat `$0` claims survive verbatim: `grep -c 'user-owned Anthropic API keys (Bring-Your-Own-Key)' knowledge-base/finance/cost-model.md` == 1 **and** `grep -c '\$0 marginal' knowledge-base/finance/cost-model.md` ≥ 1.
- **AC7** — `git diff --name-only origin/main...HEAD` lists **only** paths under `knowledge-base/`. Zero workflow, cron, or script files touched (enforces the ADR-074 out-of-scope boundary).
- **AC8** — `api-spend-reconciliation.md` carries a dated banner stating its inputs are dormant. `grep -ciE 'dormant|disabled|produces no artifacts' <file>` ≥ 1.
- **AC9** — No new GitHub issue is filed for the alerting/attribution capability (both halves are already tracked). Verify the PR body cites #5692 and #6297 rather than new numbers.
- **AC10** — No fabricated fleet-wide dollar figure appears. Every dollar amount in the edited rows is either the pre-existing last-known figure (explicitly scoped and labelled) or `0.00`.

### Post-merge (operator)

None. This plan changes only committed markdown; there is no deploy, no apply, and no
external state to reconcile.

> The one genuinely operator-only item in this problem space — converting the Anthropic org
> to a team organization so `ANTHROPIC_ADMIN_KEY` becomes mintable — is **already tracked by
> #6297** and is deliberately not re-stated here as a checklist item
> (`hr-ship-message-no-operator-checklist`).

## User-Brand Impact

**If this lands broken, the user experiences:** an expense ledger and cost model that keep
naming a deleted workflow and a dormant metering path, so the next spend question is answered
from fiction again — the concrete failure that produced "which CI jobs can we cut?" against a
CI surface that spends almost nothing.

**If this leaks, the user's data is exposed via:** nothing. The change is committed markdown
containing no credentials, no personal data, and no customer records. It names key
*variables* (`ANTHROPIC_API_KEY`, `ANTHROPIC_ADMIN_KEY`) but no key values.

> **CPO sign-off disposition (operator decision, 2026-07-30).** The plan skill stages CPO
> sign-off at PLAN time, but the threshold was `none` then — it was RAISED at review, by
> `user-impact-reviewer`, which the same skill designates as the review-phase mechanism for
> this threshold (the staging model deliberately does not re-invoke CPO at review). That agent
> ran, enumerated the failure modes, and its finding is what produced the split-row design and
> the R&D reclassification — both of which the operator then decided explicitly. Ship preflight
> Check 6 still mechanically verifies this section and the threshold value. A separate CPO
> spawn was therefore judged redundant rather than skipped. Recorded here so the next reader
> sees the reasoning, not an absence.

**Brand-survival threshold:** `single-user incident` *(raised at review — the original `none` rested on a factual error)*
**Reason:** the original reason claimed "no user-facing surface". That is wrong:
`plugins/soleur/skills/operator-digest/SKILL.md` READS `expenses.md` and sums the Recurring
table's Amount for `active` rows into the founder's weekly comprehension digest. A wrong
amount here propagates directly to a founder-facing artifact, and the failure it feeds has
already fired twice against this operator (2026-06-29 credit exhaustion, and the CI failure
that triggered this PR). That is one user, their money, their workflow — the definition of the
threshold. This is why the fleet row books `UNMEASURED` rather than a known-wrong number:
`unmetered` keeps it out of the digest's `active`-only allowlist, so the digest under-reports
rather than mis-reports.

## Domain Review

**Domains relevant:** Finance

> **Agent note (honest disclosure):** the operator's standing instruction for this session is
> not to spawn subagents unless explicitly requested, so the domain-leader Tasks and the
> `plan-review` panel were **not** spawned. The assessment below is the orchestrator's own,
> recorded as such rather than presented as a leader's finding. This is a deviation from the
> plan skill's default and is flagged here so a reviewer can weigh it.

### Finance

**Status:** reviewed (orchestrator assessment; `cfo` agent not spawned — see note)
**Assessment:** The change corrects two rows feeding the monthly-burn subtotal and the
break-even model. The amounts are deliberately **not** re-derived, because no readable source
supports a new figure — the Admin Cost & Usage API is unavailable to an individual account
(#6297). The financial risk of this plan is therefore *understatement*: the fleet-wide draw of
21 opus/sonnet crons is almost certainly above the `$15` ux-audit-era figure, and the corrected
records will say so in prose while carrying a figure that cannot yet be raised on evidence.
That is the honest state, and it is strictly better than the current state, which asserts a
mechanism that does not exist. The `verify_by` marker is what converts it from a silent
understatement into a tracked one.

### Product/UX Gate

Not applicable — no file in `## Files to Edit` matches any UI-surface term or glob; the
mechanical override does not fire. Product assessed **NONE**.

## Architecture Decision (ADR/C4)

**Not required.** This plan makes no architectural decision: no ownership/tenancy boundary
moves, no new substrate or integration pattern, no resolver/dispatch/trust-boundary change,
and no divergence from an existing ADR. It records facts about mechanisms that already
shipped.

**C4 completeness check.** Read all three of `model.c4`, `views.c4`, `spec.c4` before
concluding no impact. The enumeration for this change: external human actors — none added or
changed (no new correspondent, reviewer, or recipient); external systems — none added
(Anthropic is already the modelled LLM provider and this plan adds no new edge to it);
containers/data stores — none touched (markdown under `knowledge-base/` only); actor↔surface
access relationships — none changed. A competent engineer reading the existing ADRs + C4
would **not** be misled about the system after this plan ships, because the system does not
change.

> ADR-074 is *read and honoured* by this plan (as an out-of-scope boundary), not amended.

## Observability

**Skipped — pure-docs plan.** Every entry in `## Files to Edit` is markdown under
`knowledge-base/`; no file under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or
`plugins/*/scripts/` is touched, and no infrastructure surface is introduced. The Phase 2.9
gate skip condition applies.

## Encryption Posture

**Skipped.** No persistent data store and no new cross-component connection is introduced.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Widening the ux-audit row's scope changes a ledger row's identity, which downstream subtotals and the break-even model read | Keep the amount unchanged and change only scope + mechanism prose, so no subtotal moves. Any amount change would need evidence that does not exist yet (#6297). |
| The corrected records understate real burn (21 crons on opus-5 vs a one-cron `$15` figure) | Stated explicitly in the row and in Domain Review, with a `verify_by` marker. An honest tracked understatement beats a confident wrong mechanism. This is the residual risk this plan accepts and names. |
| A future reader deletes the reconciliation runbook because its inputs are dormant | Phase 4 annotates rather than deletes, and states the re-enable condition. |
| Scope creep into CI/cron changes | AC7 mechanically fails the PR if any non-`knowledge-base/` path is touched. |
| Contradicting the BYOK / Max-seat `$0` commitments while "adding missing spend surfaces" | AC6 asserts both claims survive verbatim; Phase 3.3 calls it out as preserve-unchanged. |

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Also wire `api-spend` capture to the surfaces that actually spend | That is a capability change, not a records correction, and it is already tracked by #6297 (whose Admin-API org-total supersedes per-run artifact capture). Doing it here would mix a records fix with a metering build. |
| File a new tracking issue for the metering gap | Both halves are already open (#5692, #6297). A third issue fragments the tracking — the exact `wg-defer-only-after-inline-triage` failure mode. |
| Delete the ux-audit row entirely (mechanism gone) | The spend did not stop; the mechanism moved. Deleting the row would remove a real cost line from the burn model. |
| Re-derive the amount from Better Stack `SOLEUR_CLAUDE_COST_DAILY` markers | ~~That marker only emits once `ANTHROPIC_ADMIN_KEY` exists; there is nothing to query.~~ **TRUE of `_DAILY`, but this row caused a FALSE generalization — corrected at review.** There are TWO markers, defined 47 lines apart in `claude-cost-marker.ts`: `SOLEUR_CLAUDE_COST_DAILY` (org-total, Admin-API, genuinely blocked on #6297) and **`SOLEUR_CLAUDE_COST` (per-run, emitted by the substrate on every exit with `cost_usd` + `source: cron:<name>`, needing NO admin key)**. This plan evaluated the first and wrote off the second, which hardened into the records asserting the fleet was unmeasurable — the exact defect class the plan exists to remove. The fleet IS derivable today; only the org-total is blocked. |
| Cut CI jobs to reduce spend (the original request) | Measured and rejected on evidence: CI is not the spender. Documented in the PR body so the question is not re-asked from the same wrong premise. |

## Test Scenarios

No browser or API flows — documentation-only change. Verification is the AC grep set in
Phase 5, run from the worktree root.
