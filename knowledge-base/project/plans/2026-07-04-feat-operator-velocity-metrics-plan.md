---
title: "feat(wave1): operator velocity metrics in operator-digest"
date: 2026-07-04
type: feature
issue: 5986
epic: 5983
branch: feat-one-shot-5986-operator-velocity-metrics
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: planned
---

# ✨ feat(wave1): operator velocity metrics in operator-digest

## Enhancement Summary

**Deepened on:** 2026-07-04

**Grounding cycle applied before deepen:** spec-flow-analyzer (surfaced H1–H4, M1–M7,
R1–R2 design gaps), three plan-review agents (DHH, Kieran, code-simplicity), and a
scoped `fable` advisor consult — all findings applied into the plan below.

**Key improvements folded in from review:**

1. **Kieran #1 (blocker):** the per-contributor `author` refute is now **command-anchored**
   (greps the real `--json` field-list line, strips comments) so it catches `author`
   appended to the query without false-matching the guard-note prose — the whole-file
   refute would have failed GREEN.
2. **Simplicity #1 (safety):** run-rate status filter is now a **fail-safe allowlist**
   (`active`/`accruing`-with-actual only; unknown future statuses excluded), not a
   fragile denylist that silently sums a forgotten status.
3. **DHH + Simplicity:** dropped the exact `0.5×/1.5×` cadence multipliers — qualitative
   band, "when in doubt, typical"; no false precision on a fuzzy denominator.
4. **DHH + Fable:** the computed dollar anchor is downgraded to **coarse + suppress-on-
   ambiguity** (a mis-read annual row is a 12–24× error); the this-week diff-direction
   is the honest primary cost signal.
5. **Kieran #2/#3/#4:** added edge cases — <4-weeks history, 300-cap truncation, §2
   Read-failure fail-loud — to Phase 2 and Test Scenarios.
6. **Fable:** the deferred month-over-month is enriched with the state-block-in-issue-body
   mechanism (readable via the already-allowed `gh issue list --json body`), captured in
   the tracking issue; hedge-on-doubt remains the H1 safety floor.
7. Phase 4 dry-verify elevated to a **required behavioral gate (AC9)** — the real
   correctness check for an LLM-as-script skill whose static test verifies words, not behavior.

**Deepen-plan gate verifications (all pass):** User-Brand Impact present (threshold
`single-user incident`, valid); Observability section present (5 fields, no placeholder,
no `ssh` in `discoverability_test`) — note the mechanical trigger is actually a *skip*
(edits touch `plugins/*/skills` + `plugins/*/test`, not `plugins/*/scripts` or `apps/*`);
no PAT-shaped variables (4.8); no UI surface (4.9 skip); no network/SSH dependency (4.5
skip); no downtime/cutover class (4.55 skip). Precedent-diff gate (4.4) N/A — no SQL/
atomic-write/lock/RPC pattern; the relevant "precedent" is the skill's own read-failure
guardrail, which the plan already mirrors for the new metrics. Citations verified live:
#5986 OPEN, #5983 OPEN, #5984 CLOSED; ADR-057 present; all cited rule-IDs active; all
cited learning files exist.

---

Wave 1 / FR3 (T3-12) of the **gstack-capability-adoption** epic (#5983,
brainstorm `2026-07-04-gstack-capability-adoption-brainstorm.md`). Adapts gstack's
`retro` capability into Soleur's operator-legible frame and **resolves OQ3** — which
velocity metrics are legible for a single non-technical solo founder vs. noise.

## Overview

The `operator-digest` skill writes the operator's calm weekly comprehension digest
(what got built / what it cost / what broke / what needs you). It is an
**LLM-as-script** skill — the model *is* the synthesizer; there is no TS/bash
synthesizer to unit-test. It runs headless in `claude-code-action` in the private
`jikig-ai/operator-digest` repo against a public `soleur` checkout, with a
deliberately minimal tool allowlist and a deterministic scrub gate.

This feature adds **two aggregate, comparison-framed metrics** to the existing
digest — **shipping cadence** (folded into §1 "What your company built") and
**cost trend** (folded into §2 "Money & vendors"). No new section, no new data
source beyond a `Read` of the current ledger; the four-section contract and its
tests stay intact. The metrics are **company-aggregate only** — the AC's "no
per-contributor noise" is enforced *structurally* (the §1 query already omits
`author`; we add a guard note + test refute so a future edit cannot widen it).

The heart of the work is **framing discipline, not arithmetic**: at a
single-user-incident comprehension threshold, a mis-computed metric that alarms the
operator ("shipping collapsed!") is exactly the harm the digest exists to prevent.
So both metrics render as **qualitative bands + a hard-rounded anchor**, are
**suppressed to neutral/hedge on any read-integrity doubt**, and never emit raw
counts, percentages, or arrows as the signal.

## OQ3 Resolution (the headline deliverable)

**Question (brainstorm OQ3):** for a *single* non-technical operator, which velocity
metrics are legible (shipping cadence, cost trend) vs. noise (context-switching)?

**Resolution — LEGIBLE (ship these two):**

1. **Shipping cadence** — a qualitative band (clearly busier / about the same /
   clearly quieter) comparing *this week's meaningful merges* to **recent weeks
   (roughly the last month)**, defaulting to "about the same" whenever the
   comparison is doubtful. Legible because the **comparison** answers the owner's
   real question — *"are we still moving?"* — not the raw number. No exact ratio,
   no percentage: the synthesizer judges the band; when in doubt, "typical".
2. **Cost trend** — the primary signal is **this week's real cost changes** as a
   plain direction line ("up ~$Y — added Resend Pro" / "holding steady, nothing new
   to approve"), from the diff §2 already reads. A **coarse run-rate anchor**
   ("recurring spend is roughly $X a month, mostly hosting and tooling") is added
   *only when the ledger reads cleanly* — suppressed if any active row's billing
   cadence is ambiguous (a mis-read annual row is a 12–24× error, the exact alarm
   the digest exists to prevent). Answers *"what is this costing, and is it creeping up?"*

**Resolution — NOISE (explicitly excluded, with rationale):**

| Excluded metric | Why it is noise for a solo non-technical operator |
|---|---|
| Per-contributor / per-author velocity | One operator + autonomous agents; author breakdown is meaningless and re-imports gstack's *team* frame. **This is the AC's "no per-contributor noise."** |
| Context-switching metrics (gstack `retro` ships these) | Not a business-decision surface for a solo owner; pure engineering-process telemetry. |
| Raw counts / percentages / up-down arrows as the signal | Vanity metrics — violate the digest register ("every line states a business consequence"). |
| Engineering cycle-time / lead-time / DORA | Jargon; not owner-legible. |
| Lines-of-code / diff size | Not computable from PR metadata *and* noise (see M7). |
| Month-over-month reconstructed cost baseline | False precision given a ledger where nearly every row says "VERIFY on invoice"; and infeasible under the current allowlist (see Research Reconciliation). Deferred — tracking issue. |

This resolution is recorded here **and** carried into the epic spec's OQ3 entry
(Phase 5). It is a **product/scoping** decision, not a system-architecture one — no
ADR (see Architecture Decision gate).

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality | Plan response |
|---|---|---|
| "cost-trend metric" (FR3) implies a month-over-month cost *direction* | The digest allowlist is `Bash(git log:*)` **only** — no `git show` / `git cat-file`, so a prior ledger **snapshot** cannot be reconstructed to compute true month-over-month direction. Verified: `grep -o 'Bash([^)]*)' operator-digest.workflow.yml`. | Define cost trend WITHOUT snapshot reconstruction: current run-rate anchor (from `Read` of `expenses.md`, allowed) + this-week changes (from the existing `git log -p -- expenses.md` diff, already §2). **Do not widen the allowlist** (it is load-bearing least-privilege). Month-over-month reconstruction deferred (tracking issue). |
| "shipping cadence" implies a count over time | `gh pr list … --limit 300` is capped; reused as a multi-week baseline it silently truncates on a busy repo (→ false "busier"). The list also omits `author` (good — no per-contributor data by construction). | Baseline classified from the same `gh pr list` data with **cap-awareness**: never assert a definite band when the window is truncated or the read is suspect; default neutral. Keep `author` out of `--json` forever (guard note + test refute). |
| Digest "reads four sources" | Cost run-rate needs a **fifth read shape** — `Read` the current `expenses.md` body to sum active rows (today §2 only runs `git log -p`, which yields *changes*, not a *total*). `Read` is on the allowlist. | Add the `Read` as an in-section step of §2; it is not a new *source*, it is a second read of an existing source. Four-section contract unchanged. |

## User-Brand Impact

**If this lands broken, the user experiences:** a confident but wrong pace/spend
line in their weekly digest — e.g., a partial PR-list read renders "much quieter
than usual" when a busy week actually shipped, or a deferred-row diff renders "costs
went up ~$100" when nothing was actually charged. Either is a **comprehension
incident** — the exact false-read the digest exists to prevent.

**If this leaks, the user's money/workflow is exposed via:** the metrics emit only
**aggregate numbers** (a merge-count band, one rounded $ run-rate) — no per-row Notes,
no PII, no new data class. The existing scrub gate (secrets + foreign-email abort)
and §2's "amounts + vendor names only" rule already bound the leak surface; this
feature adds no new egress.

**Brand-survival threshold:** single-user incident.

`requires_cpo_signoff: true` — CPO sign-off required at plan time before `/work`
begins (covered by the brainstorm's CPO/CTO/CLO framing carry-forward for the epic;
confirm CPO has reviewed). `user-impact-reviewer` will be invoked at review time
(review skill's conditional-agent block).

## Implementation Phases

TDD throughout (`cq-write-failing-tests-before`): extend the static-contract test
RED, then edit the SKILL.md prose GREEN.

### Phase 0 — Preconditions (verify, do not assume)

- [ ] Confirm allowlist unchanged: `grep -o 'Bash([^)]*)' plugins/soleur/skills/operator-digest/assets/operator-digest.workflow.yml` shows no `git show`/`git cat-file` (drives the cost-trend design).
- [ ] Confirm the §1 `gh pr list` `--json` field list has no `author` (structural per-contributor prevention): `grep -n 'json title,labels,mergedAt' plugins/soleur/skills/operator-digest/SKILL.md`.
- [ ] Re-read the digest register + read-failure guardrail sections so the new prose reuses their exact framing.

### Phase 1 — RED: extend the contract test

Edit `plugins/soleur/test/operator-digest-skill.test.sh`. Add assertions (they FAIL against the current SKILL.md):

- [ ] **Cadence contract present** — SKILL.md instructs a shipping-cadence band folded into §1, compared to recent weeks, defaulting to typical on doubt (`assert` `cadence` + `recent weeks`/`typical`). Do NOT assert an exact multiplier (there is none — see the DHH/Simplicity reframe).
- [ ] **Cost-trend contract present** — §2 emits a this-week cost-change direction line + a coarse run-rate anchor (`assert` `run-rate` + `roughly \$`/`about \$`).
- [ ] **Read-integrity suppression** — the cadence band is suppressed on a §1 read failure / suspected silent undercount, and the run-rate anchor is suppressed on a §2 read failure or ambiguous billing cadence (`assert` prose tying both to the read-failure guardrail; extends "a failed read is NOT a quiet week").
- [ ] **Run-rate allowlist (fail-safe status filter)** — the run-rate counts ONLY `active` (and `accruing`-with-real-actual) rows; every other status is invisible (`assert` the allowlist phrasing, e.g. `only.*active` + `accruing`; do NOT enumerate a denylist).
- [ ] **No per-contributor (command-anchored refute — Kieran #1 fix).** The refute MUST anchor to the real §1 field-list line so it (a) catches an `author` field appended to the actual command and (b) does NOT false-match the guard-note prose. Use the command-anchored technique the existing `--search` guard uses (test lines 100–104): grep the `gh pr list … --json` command line(s), strip comment lines, and FAIL if `author` appears in the field list — e.g. match `--json[[:space:]]*[a-zA-Z,]*author`. Also `assert` a "company-aggregate only" guard line exists, worded so the substring `--json`→`author` does NOT appear in that order (phrase it "never add an `author` field to the §1 `--json` list").
- [ ] **No vanity output (assert guard)** — `assert` the skill forbids emitting raw counts/percentages/arrows as the metric and mandates consequence-framing.
- [ ] Run `bash plugins/soleur/test/operator-digest-skill.test.sh` → confirm the NEW assertions fail, the existing ones still pass. **Verify the command-anchored refute against BOTH the failing state (author appended) AND the GREEN guard-note prose — it must pass GREEN, not trip on the guard line.**

### Phase 2 — GREEN: enhance the SKILL.md prose

Edit `plugins/soleur/skills/operator-digest/SKILL.md`. All additions are prose (the model computes at runtime from the existing allowed tools).

- [ ] **§1 cadence fold-in.** Add a lead framing line to "What your company built":
  - Compare *this week's meaningful merges* (reuse the §1 `gh pr list` result already being read; **meaningful** = the same set §1 prose keeps, i.e. drop pure chore/dependency bumps — keeps the band consistent with the prose above it, per M1/M7) to **recent weeks (roughly the last month)** from the same `mergedAt` data, excluding the current week.
  - **Qualitative band, no arithmetic (DHH/Simplicity):** clearly quieter / about the same / clearly busier — the synthesizer judges it; **when in doubt, "about the same".** Do NOT pin exact multipliers or emit a percentage — precise ratios on a fuzzy "meaningful-merges" denominator are false rigor. Degrade gracefully: with fewer than a few weeks of history, default to "about the same" (or a plain "getting started" line), never a confident band (Kieran #2).
  - **Cap/undercount safety (H1/M2/M4):** if the §1 read failed (the existing warning fires), OR the PR list is truncated at the 300 cap across the comparison window, OR this-week reads suspiciously empty/near-zero — **do not emit a definite band**; render "about the same" or a one-line hedge. Never emit the *downward* "quieter" band off a doubtful read. Cadence is a merge-**count** comparison, never a code-size measure.
  - Render as a **consequence**, e.g. *"Your company shipped about as much as a normal week."* Never "velocity", "throughput", "cadence", a percentage, or an arrow in the output prose (R1).
- [ ] **§2 cost-trend fold-in.** Add a lead framing line to "Money & vendors":
  - **Direction (primary signal):** from the existing `git log -p -- expenses.md` window — real added/changed active costs this week ("up ~$Y — added Resend Pro") or "no cost changes — spend is holding steady." A row merely being *recorded* as a non-active status (`deferred`/`approved-not-billing`) in the diff is **not** an increase (H3).
  - **Coarse run-rate anchor (only when clean):** `Read` the current `expenses.md`; sum the **Recurring** table Amount counting **only** rows whose `status` is `active` (and `accruing` only when it carries a real actual). **Fail-safe allowlist (Simplicity #1):** every other status — `deferred`, `test-mode`, `free-tier`, `approved-not-billing`, one-time `credit`, and any *future/unknown* status — is invisible to the run-rate; an unrecognized status is excluded, never summed. Normalize known non-monthly rows (the `.ai` domain 2-year registration; annual-billed rows named "…/mo annual" in Notes) to a monthly figure. **Suppress the anchor entirely** if any counted row's billing cadence is ambiguous (a mis-read annual row is a 12–24× error — Fable/DHH). When clean, hard-round to a coarse figure: *"recurring spend is roughly $X a month, mostly hosting and tooling."* Emit **one aggregate figure only** — never a per-row Notes value (L2); read the **Recurring** table only (One-Time carries the `credit −29` and a registration `140.00` that must not enter run-rate — Kieran).
  - **Read-failure fail-loud (Kieran #4):** if the `Read` of `expenses.md` *errors* (distinct from an empty ledger), suppress the anchor behind the existing ⚠️ warning line — a failed read is NOT "spend holding steady."
  - **First-run branch:** empty ledger read → "first reading — no cost trend yet," mirroring the existing "(this is the first digest)" pattern (M6).
- [ ] **Guard notes.** Add a short "Velocity metrics (aggregate only)" note under Scope guardrails: company-aggregate only; **never add an `author` field to the §1 `gh pr list --json` list** (phrase it in exactly this word order so the test's guard-line assertion and the command-anchored refute do not collide — see Phase 1); both metrics suppressed to neutral on read doubt; consequence-framing only, no vanity vocabulary.
- [ ] Run the contract test → all GREEN.

### Phase 3 — Full-suite + docs

- [ ] `bash plugins/soleur/test/operator-digest-skill.test.sh` and the sibling digest tests (`operator-digest-workflow.test.sh`, `digest-scrub.test.sh`, `operator-digest-provision.test.sh`) — all green.
- [ ] `bun test plugins/soleur/test/components.test.ts` — the description is **unchanged** (metrics are content, not routing), so no word-budget bump. (Headroom checked: 2292/2327 = 35 words if a tweak were ever wanted; default: no change.)
- [ ] No README component-count change (no new/removed component).

### Phase 4 — Required dry-verify (the real correctness gate)

The static test verifies *words, not behavior* (DHH/Kieran) — for an LLM-as-script
skill the paper dry-verify is the genuine validation, so it is a **required pre-merge
step (AC9), not advisory.** Reason through synthetic weeks end-to-end against the
final SKILL.md prose and confirm each verdict:

- [ ] Normal week → "about the same"; deferred-row-in-diff → **no "cost up"** (H3).
- [ ] Genuinely-quiet week vs partial/failed §1 read → must **differ**: quiet → "quieter"; partial-read → "about the same"/hedge (never "quieter").
- [ ] 300-cap truncation across the comparison window → neutral band (not "busier").
- [ ] **Annual-row case (Fable):** a ledger with a mix of monthly, annual (`.ai` 2-yr, Plausible "/mo annual"), and deferred rows → the coarse anchor lands in the right ballpark; if any counted row's cadence is ambiguous, the anchor is **suppressed**, not guessed.
- [ ] §2 `expenses.md` read error → ⚠️ line, anchor suppressed (Kieran #4).

### Phase 5 — Record the OQ3 resolution

- [ ] Update the epic spec OQ3 entry (`knowledge-base/project/specs/feat-gstack-capability-adoption/spec.md`) to mark OQ3 **resolved** with a one-line pointer to this plan's resolution table. (Does NOT rewrite any deferral/strategy decision — records the answer only.)

## Files to Edit

- `plugins/soleur/skills/operator-digest/SKILL.md` — §1 cadence fold-in, §2 cost-trend fold-in, guard note. **Description frontmatter unchanged.**
- `plugins/soleur/test/operator-digest-skill.test.sh` — new contract assertions/refutes (Phase 1).
- `knowledge-base/project/specs/feat-gstack-capability-adoption/spec.md` — mark OQ3 resolved (Phase 5).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-5986-operator-velocity-metrics/tasks.md` — task breakdown (generated post-review).
- (Learnings file if warranted — created at `/compound` time, directory + topic only, no pinned date.)

## Acceptance Criteria

### Pre-merge (PR)

Note: AC1–AC6 are prose-presence checks — the honest mechanical ceiling for an
LLM-as-script skill (they guard against a silent prose-drop on a future edit); they
are NOT behavioral guarantees. The behavioral gate is AC9 (Phase 4 dry-verify).

- [ ] **AC1 — cadence in digest.** SKILL.md instructs a §1 shipping-cadence band vs recent weeks, consequence-framed, default-typical-on-doubt (no exact multiplier). Verify: cadence assertion passes.
- [ ] **AC2 — cost trend in digest.** SKILL.md §2 emits a this-week direction line + a coarse run-rate anchor (suppressed on doubt). Verify: cost-trend assertion passes.
- [ ] **AC3 — no per-contributor noise (the issue AC).** The §1 `--json` field list contains no `author`, and a guard line forbids adding it. Verify: the **command-anchored** refute passes (catches `author` appended to the real field list; does not false-match the guard prose — Kieran #1); guard-line assertion passes.
- [ ] **AC4 — read-integrity safe.** SKILL.md suppresses the cadence band (never the downward "quieter") on a §1 read failure/undercount AND suppresses the run-rate anchor on a §2 read failure or ambiguous billing cadence. Verify: read-integrity assertion passes.
- [ ] **AC5 — run-rate allowlist (fail-safe).** SKILL.md counts ONLY `active`/`accruing`-with-actual rows toward the run-rate; every other/unknown status is invisible. Verify: allowlist assertion passes (no denylist enumeration).
- [ ] **AC6 — no vanity output.** SKILL.md forbids raw counts/percentages/arrows as the metric and mandates business-consequence framing. Verify: vanity-guard assertion passes.
- [ ] **AC7 — no regression.** All existing `operator-digest-skill.test.sh` assertions (four sources, no `--search`, no `gh issue create`, four-section fallback, prior-week continuity) still pass; sibling digest tests green; `components.test.ts` green (no description change).
- [ ] **AC8 — OQ3 recorded.** The epic spec's OQ3 entry is marked resolved with a pointer to this plan.
- [ ] **AC9 — dry-verify (behavioral gate).** Phase 4's synthetic-week walkthroughs all produce the correct verdict — the load-bearing correctness check for a skill with no runtime unit test.

### Post-merge (operator)

- None. This is a prose-skill + test change; the workflow that runs it is already
  provisioned in the private repo. First live effect is the next scheduled Friday
  digest run. **Automation:** the digest fires on its existing cron — no operator step.

## Open Code-Review Overlap

None. Checked open `code-review`-labelled issues against `operator-digest/SKILL.md`,
`operator-digest-skill.test.sh`, and `operator-digest` — zero matches.

## Domain Review

**Domains relevant:** Product (carry-forward), Legal (carry-forward) — from the epic
brainstorm's `## Domain Assessments`.

### Product (CPO) — carry-forward

**Status:** reviewed (brainstorm carry-forward + this plan's OQ3 resolution).
**Assessment:** This IS a product-scoping decision (which metrics are legible for the
target user). The OQ3 resolution table is the product deliverable. `requires_cpo_signoff:
true` per the single-user-incident threshold — confirm CPO ack before `/work`.

### Legal (CLO) — carry-forward

**Status:** reviewed (brainstorm carry-forward).
**Assessment:** No new egress and no new data class. Cost figures were already emitted
by §2; the metric adds one *aggregate* figure, never per-row Notes. The scrub gate and
"amounts + vendor names only" rule are unchanged. CLO's "redaction precedes egress"
gate is satisfied vacuously (no egress increase).

### Product/UX Gate

**Tier:** none — no UI-surface file in Files to Edit (SKILL.md + `.test.sh` + spec
`.md`). The digest is delivered as a private GitHub issue, not a web UI page/flow.
The mechanical UI-surface override does not fire (no `components/**`, `app/**/page.tsx`,
etc. in the Files lists).

## Architecture Decision (ADR / C4)

**No architectural decision — no ADR, no C4 impact.**

- **Detection:** no data-model/ownership move, no new substrate/integration, no
  resolver/trust-boundary change, no reversal/extension of an existing ADR. This
  extends existing skill *content* within the boundary ADR-057 already established
  (operator-private two-repo privilege-separated digest, `status: accepted`).
- **C4 completeness check (grep-backed, not asserted from memory):** grepped all three
  model files (`model.c4`, `views.c4`, `spec.c4`) for `digest`/`operator-digest`/`expense`
  — the only "digest" hit is the unrelated cosign **image digest** (supply-chain),
  not this data flow. The digest's actors/systems/data flow are unchanged: it reads
  the **same** public-`soleur` sources (merged PRs, expenses ledger — sources 1 & 2,
  already the metric inputs) and writes the **same** private-repo issue. No new
  external human actor, external system/vendor, data store, or actor↔surface access
  relationship is introduced. **No `.c4` edit required.**

## Observability

Pure prose-skill + test change — no code under `apps/*/{server,src,infra}` or
`plugins/*/scripts/`, so the mechanical gate is a skip. Recorded lightly because the
digest is an operator-facing runtime surface at single-user-incident threshold:

```yaml
liveness_signal:    # the weekly Digest issue posts in jikig-ai/operator-digest; the existing "Last week: #N" continuity line makes a skipped week operator-visible. cadence: weekly (Fri 13:00 UTC cron). alert_target: operator (the digest reader). configured_in: operator-digest.workflow.yml
error_reporting:    # a source read failure renders the existing labelled ⚠️ warning line (fail-loud); this feature extends it to suppress the cadence band on doubt. fail_loud: yes
failure_modes:
  - mode: partial/silent-undercount PR read → false "quieter" cadence
    detection: neutral/hedge band on doubtful read (Phase 2 rule); no downward band off a suspect read
    alert_route: operator sees a hedge, never a false alarm
  - mode: deferred-row diff → false "cost up"
    detection: status filter excludes deferred/approved-not-billing (AC5)
    alert_route: n/a (suppressed at synthesis)
logs:               # claude-code-action run log in the private repo (show_full_output deliberately OFF)
discoverability_test:  # command: bash plugins/soleur/test/operator-digest-skill.test.sh  (NO ssh) / expected_output: "N passed, 0 failed"
```

## Infrastructure (IaC)

None — no new server, service, cron, vendor, DNS, cert, secret, or firewall rule.
The scheduled workflow and private repo are already provisioned (ADR-057). Pure
code/prose change against an already-provisioned surface — Phase 2.8 skip.

## GDPR / Compliance

No new regulated-data surface: no schema/migration/auth/API-route change, no new
LLM-on-operator-data processing activity beyond what the digest already does, no new
distribution surface. The metric emits aggregate figures only. Advisory gate (Phase
2.7) skipped — none of the (a)–(d) expansion triggers fire (no new external-API
processing of operator-derived data beyond the existing digest synthesis; no new
artifact-distribution surface; the digest already reads KB sources and is covered by
ADR-057's containment analysis).

## Test Scenarios

1. **Normal week** → cadence "about the same"; cost "holding steady" (+ coarse anchor if clean).
2. **Genuinely quiet week** (few real merges, read OK) → "quieter".
3. **Partial/failed §1 read** (non-zero exit OR silent-empty) → warning line + **no
   cadence band** (never "quieter"). Distinguishes false-quiet from true-quiet (H1/M2).
4. **Busy week** (clearly more than recent weeks, read complete) → "busier".
5. **300-cap truncation** across the comparison window → neutral band, not "busier" (Kieran #3/M4).
6. **Deferred row lands in the diff** (`$100` X API Basic recorded, still deferred) →
   **no "cost up"** (H3).
7. **Mixed monthly/annual/deferred ledger** → coarse anchor in the right ballpark;
   any ambiguous-cadence counted row → anchor **suppressed**, not guessed (Fable).
8. **§2 `expenses.md` read error** (not empty) → ⚠️ line, anchor suppressed (Kieran #4).
9. **Fewer than a few weeks of history** → cadence defaults to "about the same"/"getting started", no confident band (Kieran #2).
10. **First-ever run** → cost says "first reading — no cost trend yet" (M6).
11. **Regression** → four sections, fallbacks, no `--search`, no `gh issue create`,
    prior-week continuity all unchanged.

## Alternative Approaches Considered

| Approach | Verdict | Disposition |
|---|---|---|
| New "Pace & spend at a glance" §0 dashboard section | Rejected — a dashboard invites vanity metrics (the register forbids) and would break the four-section contract + tests. Fold-in is simpler and register-aligned. | — |
| Deterministic helper script under `scripts/` to compute cadence/run-rate | Rejected for now — adds a `plugins/*/scripts/` file + observability surface for marginal precision the register does not need (bands, not exact counts). The whole skill is already LLM-as-script. | — |
| Exact counts / percentages instead of qualitative bands | Rejected — exact merge counts *are* the vanity metric; exact `$X.XX` is false precision on a "VERIFY on invoice" ledger. Bands + rounded anchor are more honest and single-user-incident-safe. | — |
| True month-over-month cost direction via prior ledger snapshot (`git show`) | **Deferred** — `git show`/`git cat-file` not on the allowlist; widening least-privilege is out of scope. | **File tracking issue** (below). |
| Persist a machine-readable state block (prior anchor $, prior PR counts) in the digest **issue body**, read next run via the already-allowed `gh issue list --json body` (Fable) | **Deferred, not rejected** — this genuinely un-defers month-over-month cost direction AND makes baseline undercount *detectable* (live read ≪ persisted baseline → suppress) WITHOUT any allowlist change (the plaintext `digest.md` is `rm`'d post-post, but the private issue body persists and `gh issue list --json body` is already how the continuity line reads prior digests). Deferred because the other three reviewers converged on keeping Wave-1 minimal and the hedge-on-doubt rule is an adequate H1 *safety* floor (worst case: "typical" instead of "quieter" — a hedge, never a false alarm); the state block is a precision improvement, not a safety necessity. | **Fold into the tracking issue** as the recommended mechanism. |
| Per-contributor / human-vs-agent split | Rejected permanently — it is the AC's excluded "per-contributor noise"; also structurally impossible (query omits `author`). | — |

**Deferral tracking issue (file at `/work` or ship time):** title "operator-digest:
true month-over-month cost trend + undercount-resistant cadence baseline (persist a
state block in the digest issue body)", body = the two deferred rows above (the
`git show` non-option + Fable's `gh issue list --json body` state-block mechanism and
its baseline-divergence benefit), re-eval trigger = "if operators report the coarse
this-week direction is insufficient, or a silent-undercount false-cadence is observed",
milestone Post-MVP / Later, label `type/feature`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails
  `deepen-plan` Phase 4.6 — this section is filled.
- **Never add `author` (or any per-actor field) to the §1 `gh pr list --json` list.**
  It is the one edit that would silently re-introduce the per-contributor noise the AC
  forbids; the test refute guards it, but a reviewer should treat any `--json` widening
  on that line as a red flag.
- **Qualitative bands are alarm-shaped.** A silent PR-list undercount (exit-0-empty,
  the #3403 class the existing guardrail was written for) turns into a *confident wrong*
  "quieter than usual" unless the band is suppressed on read doubt. The exit-code
  guardrail alone does NOT catch silent undercount — the Phase 2 neutral-on-doubt rule
  is load-bearing, not polish.
- **The `git log` allowlist has no `git show`/`git cat-file`** — do not design any
  cost metric that needs a reconstructed prior snapshot; use current `Read` + the
  existing diff window.
- **Sum the ledger with an ALLOWLIST, never a denylist.** The Amount column mixes ≥7
  statuses; a denylist silently sums any *future* status it forgot to exclude — the
  exact "overstated run-rate / false cost-up" harm. Count ONLY `active`/`accruing`-with-actual;
  every other/unknown status is invisible (fail-safe). The `$100` deferred X API and
  `$5` approved-not-billing LB must never enter the run-rate.
- **A mis-read annual row is a 12–24× error** (`.ai` 2-yr registration, Plausible/Proton
  "/mo annual"). Suppress the whole anchor if any counted row's billing cadence is
  ambiguous rather than guessing monthly — the anchor is a *nice-to-have*; the this-week
  direction line is the load-bearing cost signal.
- **The static test verifies words, not behavior.** AC1–AC6 grep for prose presence
  (the honest ceiling for LLM-as-script); the real correctness gate is the Phase 4
  dry-verify (AC9). Do not treat a green contract test as proof a metric computes right.

## Research Insights

- **Repo facts (verified this session):** digest is LLM-as-script (SKILL.md is the only
  mechanically-testable surface — `operator-digest-skill.test.sh`); runs via
  `operator-digest.workflow.yml` with allowlist `Write,Read,Glob,Grep,Bash(date:*),
  Bash(ls:*),Bash(gh pr list:*),Bash(gh issue list:*),Bash(git log:*)` (no `git show`);
  scrub gate `digest-scrub.sh` aborts on secrets/foreign-email, WARNs on UUID/IPv4 —
  aggregate numbers + $ amounts pass clean; §1 query is `--json title,labels,mergedAt`
  (no `author` — per-contributor prevented by construction).
- **Premise validation:** #5986 OPEN, epic #5983, sibling #5984 CLOSED. Brainstorm
  current (2026-07-04). gstack `retro` is an external capability (not in-repo) —
  characterized from the brainstorm + AC; no in-repo source to grep. No stale premises.
- **Learnings applied:** `2026-06-12-gh-search-api-empty-cross-repo-under-in-action-app-token.md`
  (List API not Search — already baked in; reinforces the silent-undercount risk H1);
  `2026-06-11-verify-billing-model-before-scoping-cost-capture-feature.md` (only surface
  a cost as a business consequence — drives the status filter + "no false billing
  surprise"); `2026-07-01-domain-model-register-curation-citation-parser-and-grep-validation.md`
  (register prose must be grep-validated against the source body — drives reading actual
  active rows, not narrating from plan).
- **Spec-flow gaps folded in:** H1 (silent-undercount false alarm → neutral-on-doubt),
  H2/H3/H4 (cost baseline infeasible + status taxonomy + normalization → run-rate anchor
  + diff-direction, snapshot deferred), M1/M4/M7 (denominator/cap/count-not-size),
  M6 (first-run no-trend), R1/R2 (vanity + per-contributor guards).
- **Budget headroom:** `components.test.ts` word budget 2292/2327 = 35 words free;
  description **unchanged** so no bump needed.
