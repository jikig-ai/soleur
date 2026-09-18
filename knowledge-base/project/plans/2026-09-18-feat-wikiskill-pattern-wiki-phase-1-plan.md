---
title: "fix(harness): make the compound-promote proposer observable, and close the allowlist bypass"
date: 2026-09-18
slug: feat-wikiskill-pattern-wiki-phase-1
branch: feat-wikiskill-skill-evolution
issue: 8281
closes: 8274
lane: cross-domain
type: fix
domain: engineering
priority: p2-medium
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
spec: knowledge-base/project/specs/feat-wikiskill-skill-evolution/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-09-18-wikiskill-skill-evolution-brainstorm.md
source: https://arxiv.org/abs/2608.27454 (CC BY 4.0)
scope_decision: "Operator chose 'diagnose first' at plan review (2026-09-18) — pattern layer deferred to a gated follow-up"
---

## Overview

Two fixes to Soleur's weekly self-improvement proposer, `cron-compound-promote`:

1. **Make its outcome observable.** All seven terminal paths currently return a `status` string that
   is emitted nowhere, so ten weeks of zero output are undiagnosable.
2. **Close #8274.** Its diff allowlist inspects `+++ b/` headers while `git apply` resolves paths
   differently, so the allowlist passes vacuously on several diff shapes — including one that
   deletes `AGENTS.rules.md`.

**The WikiSkill pattern layer is deliberately NOT in this plan.** A seven-reviewer panel converged
on the same objection: four of the seven terminal statuses (`disabled`, `deduped`,
`week-cap-reached`, `empty-corpus`) would mean a pattern layer fixes nothing, and the layer's whole
value rests on a hypothesis — "the 516k-token corpus dump is why it opens nothing" — that a single
telemetry read settles. `cron-compound-promote` is already on the manual-trigger allowlist, so that
read is **minutes away, not a week**. The layer is deferred to a follow-up gated on the measured
cause. See `## Deferred`.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited | Probe | Result |
|---|---|---|
| #8281 | `gh issue view` | OPEN — parent |
| #8274 | `gh issue view` | OPEN — **closed by this plan** |
| #6037 / #6038 / #6102 | `gh issue view` | #6037 CLOSED; #6038/#6102 OPEN and untouched here |
| Mechanism vs ADR corpus | grep `decisions/` | #5292's rejected merge/archive pass is the nearest prior art — now irrelevant to this scope, carried into the deferred issue |

### Value-Proposition Measurement (Phase 0.6c)

The 2026-09-13 run made one Sonnet call with **516,512 input tokens / 7,623 output tokens**
(`SOLEUR_CLAUDE_COST`, `id: cron-compound-promote`, `capture_status: ok`) and opened nothing.
Command: `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1500h --grep cron-compound-promote`.
**This plan does not claim that saving** — it makes the cause knowable. Whether the prompt size is
even the problem is the question this plan answers.

### Verified code facts

- **7 terminal returns** (`cron-compound-promote.ts:424-837`): `disabled` (:469), `deduped` (:496),
  `week-cap-reached` (:514), `empty-corpus` (:569), `anthropic-truncated`|`no-qualifying-clusters`
  (:642), `completed` (:821), `error` (:837). Each returns a `status` **emitted nowhere**.
- **`git apply` strips one leading component by default** — measured: `+++ x/target.txt` rewrote
  `target.txt`; `+++ w/evil.yml` created `evil.yml`. The `+++ b/` filter (:672-680) sees neither, so
  `badPath` is `undefined` and the allowlist passes.
- **`--numstat` alone is an insufficient fix** — measured: for
  `rename from AGENTS.rules.md / rename to plugins/soleur/skills/x/STOLEN.md`, `--numstat -z`
  reports **only the destination** (fully allowlisted) while the apply **deletes `AGENTS.rules.md`**.
  `--summary` reports `rename AGENTS.rules.md => …`. The fix needs both.
- **Better Stack transit requires WARN+**; precedent `claude-cost-marker.ts` ("Emit one
  `SOLEUR_CLAUDE_COST` **WARN** marker") — and it calls `log.warn`, not `logger.warn`.
- **`MARKER_RE` does not apply** — it gates plugin/CLI stdout markers
  (`git-lock-marker-telemetry.ts`), a different surface from this server-side emit.
- **`cron-compound-promote` is manually triggerable today.** `MANUAL_TRIGGER_EVENTS` is *derived*
  from `EXPECTED_CRON_FUNCTIONS` (`manual-trigger-allowlist.ts`), and `cron-compound-promote` is in
  that manifest (`cron-manifest.ts:40`) → `cron/compound-promote.manual-trigger` is allowlisted.
  No code change needed to fire it.
- **`logger` auto-mirrors WARN+ to Sentry** (`logger.ts:123-125`) — so a WARN marker on the
  `completed` path also files a weekly Sentry event. Accepted deliberately (see Risks).
- **Runtime uses Octokit, not `gh`** — the handler's header states the gh CLI is absent at runtime.
- **Tests:** `test/server/inngest/cron-compound-promote{,-graymatter}.test.ts`; runner is vitest
  (`cd apps/web-platform && ./node_modules/.bin/vitest run <path>`).

### What the panel cut, and why it is not here

`code-simplicity-reviewer`, asked per-mechanism, found ~40% of the original surface mapped to no
property: a separate marker module (inline it), six threaded refusal counters (one `string[]`), a
derived index artifact (glob + frontmatter at read time is strictly cheaper), a `Content-Digest`
ledger column (`Cluster-Hash` is **already** a column and already the documented search key), and a
tag-normalization pass (scaffolding for a backfill that is now deferred). All cut.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| FR1/FR2 outcome telemetry + streak alert | Marker: none exists. Streak: **zero-output runs append no ledger row**, so a ledger-sourced streak counts a record that cannot exist | Ship the marker; **defer** the streak/alert until a marker baseline exists |
| FR3 `#8274` via `--numstat` | Correct direction, insufficient mechanism (rename bypass, measured) | `--summary` + `--numstat`, sources included |
| FR4-FR10 pattern layer, index, ledger reader | Value depends on the cause this plan measures | **Deferred** to a gated follow-up |

## Open Code-Review Overlap

- **#8274** — **Fold in.** It is this plan's second deliverable; `closes: 8274`.
- **#2231** (`generate-kb-index.sh` perf) — **Acknowledge.** This plan no longer touches that script.
- **#3321** (CODEOWNERS for `learnings/`) — **Defer with a note.** Relevant only to the deferred
  pattern layer; the note belongs on the follow-up issue, recording that the learnings subtree is
  blinded by **two** gitleaks rules (`database-url-with-password` and `id = "private-key"`).
- **#3829** (new Sentry monitor type → `sentry-scrub.ts`) — **Acknowledge.** No monitor type added.

## User-Brand Impact

**If this lands broken, the user experiences:** the proposer keeps silently producing nothing while
the product claims it compounds — or, worse, the allowlist fix is incomplete and a model-authored
diff writes outside the two permitted paths, reaching `.github/workflows/` or deleting
`AGENTS.rules.md` in a repo the user trusts.

**If this leaks, the user's data is exposed via:** nothing new — this plan adds no data surface, no
new artifact and no new vendor. The marker carries counts and status strings only, by construction.

**Brand-survival threshold:** `single-user incident` (inherited; the allowlist is a security
control). `user-impact-reviewer` runs at review time.

## Implementation Steps

*(Internal steps, not release phases — the whole plan is one PR.)*

### Step 0 — Preconditions

0.1 Confirm `promotion-config.yml` still reads `enabled: true` (if it does not, that alone explains
ten weeks and the marker will say so on the first run).
0.2 Record the current `TARGET_ALLOW_RE` value and the two permitted target shapes.

### Step 1 — Outcome marker

1.1 Emit `SOLEUR_COMPOUND_PROMOTE_OUTCOME` at **WARN**, **inlined** in `cron-compound-promote.ts`
(no new module — one caller). Fields: `status`, `corpus_count`, `clusters_proposed`,
`clusters_opened`, `refusals` (a `string[]` appended at each existing refusal site),
`prompt_input_bytes`, and a bounded `refusal_detail` (≤20 `{cluster_hash, reason}` entries) so a
*recurring* refusal of the same cluster is distinguishable from a quiet corpus.
1.2 Call it on **all 7** terminal paths (:469, :496, :514, :569, :642, :821, :837).
1.3 **Guard 1** (below) — written before the emit.

### Step 2 — Close #8274

2.1 Derive the path set from **`git apply --summary` + `--numstat -z`**, including rename/copy
**source** paths. `--numstat` alone is insufficient (measured, above).
2.2 Check every derived path against `TARGET_ALLOW_RE`; refuse when the derived set is **empty**.
2.3 **Guard 2** (below) — mutation matrix written before the fix.

### Step 3 — Verify in-session, not in a week

3.1 After merge, fire the cron on demand: `/soleur:trigger-cron` with
`cron/compound-promote.manual-trigger` (already allowlisted — no code change).
3.2 Read the emitted marker from Better Stack and record the `status` + `refusals` on #8281. **This
is the deliverable** — the measured reason ten weeks produced nothing.
3.3 Open the deferred follow-up with that evidence attached.

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-compound-promote.ts` — marker on 7 paths;
  `--summary`+`--numstat` path derivation
- `apps/web-platform/test/server/inngest/cron-compound-promote.test.ts` — extend (Guard 4-style
  assertions live here, not in new files)
- `apps/web-platform/test/server/inngest/cron-compound-promote-allowlist.test.ts` — **new** (Guard 2)
- `apps/web-platform/test/server/inngest/cron-compound-promote-outcome-census.test.ts` — **new** (Guard 1)
- `scripts/followthroughs/compound-promote-outcome-8281.sh` — **new** (scheduled-path confirmation)

No `.tf`, no ADR, no new knowledge-base directory, no SKILL.md `description:` change.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** Every terminal path emits exactly one marker. Verify: the census test reports
  `unclassified == 0` **and** `classified >= 7` (a floor, not a pin).
- **AC2** The marker is emitted at **WARN**. Verify **in the census test** by asserting the emitted
  record's level — not by grepping a token (the precedent uses `log.warn`, and an absence-grep
  false-fails a legitimate `logger.info`).
- **AC3** A diff headed `+++ x/.github/workflows/foo.yml` is **refused**; likewise `w/`, `i/`, and a
  diff with no `+++` header.
- **AC4** A two-file diff, first path allowed and second forbidden, is **refused**.
- **AC4b** A diff renaming `AGENTS.rules.md` to an allowlisted `SKILL.md` path is **refused**, and
  `AGENTS.rules.md` still exists afterwards.
- **AC5** A legitimate two-file diff (`AGENTS.rules.md` + a `SKILL.md`) still **applies** — the
  must-PASS control that proves the guard is not refusing everything.
- **AC6** `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/` is green.
- **AC7** `git diff origin/main...HEAD --name-only` touches no file under
  `knowledge-base/project/learnings/` (this plan writes no learning and no pattern page).

### Post-merge (probe-verified, no operator step)

- **AC8** An on-demand run emits a marker whose `status` is one of the 7 known values, read back
  from Better Stack, and that value is recorded on #8281.
- **AC9** The next *scheduled* Sunday run also emits a marker — confirming the scheduled path, which
  an on-demand fire does not exercise. Enrolled below.

## Guard Contract

### Guard 1 — outcome-marker census

**Property.** Every terminal return of the handler emits exactly one outcome marker — all present
and future returns.
**Assembly.** Not the 7 known statuses (a snapshot). The chokepoint is the set of `return {`
statements in the handler body; the census buckets each as classified or **unclassified**, and any
unclassified member is RED. `MIN_CASES=7` is a floor.
**Mutation matrix.**

| # | Edit | Must |
|---|---|---|
| 1 | Add an 8th early return with no marker | RED — unclassified member |
| 2 | Delete the marker on `no-qualifying-clusters` | RED |
| 3 | Emit a `status` outside the known set | RED |
| 4 | *Dispatch row:* stub the return-scanner to yield `[]` | RED — "0 checked" must fail, not pass |

**Harness rows.** (a) Mutate the suite's assertion to `expect(true)` → an integrity check must RED.
(b) Must-PASS non-canonical: two returns sharing one marker helper still passes (the contract is one
marker per return, not one literal per return).
**Anchor.** The census derives its member set from the source file at test time, not from a
committed list, so no single diff can edit both the guard's expectation and the handler.

### Guard 2 — diff path derivation (#8274)

**Property.** No path outside `TARGET_ALLOW_RE` can be written **or deleted** by an applied diff.
**Assembly.** Every site turning proposal text into file writes — `applyDiffToWorkspace`
(:397-418); the guard greps for `"apply"` argv occurrences so a later-added second apply site is
caught rather than assumed absent.
**Mutation matrix.**

| # | Edit | Must |
|---|---|---|
| 1 | `+++ x/.github/workflows/foo.yml` (**measured to apply today**) | RED |
| 2 | Diff with no `+++` header at all | RED — empty derived set must refuse |
| 3 | Two-file diff, first allowed + second forbidden | RED — second-member row |
| 4 | **`rename from AGENTS.rules.md` → an allowlisted `SKILL.md`** (**measured**: `--numstat` reports only the destination; the apply deletes the source) | RED — rename/copy **source** must be checked |
| 5 | `copy from` variant of row 4 | RED |
| 6 | *Dispatch row:* stub the derivation to return `[]` | RED |

**Harness rows.** (a) At least one RED fixture written from scratch, not by editing the canonical.
(b) Must-PASS non-canonical: a legitimate two-file diff touching `AGENTS.rules.md` **and** a
`SKILL.md` applies (AC5).
**Anchor.** The path set comes from `git apply` itself, not a stored list — there is no value a
single diff can edit to weaken both the guard and what it guards.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_COMPOUND_PROMOTE_OUTCOME (WARN, exactly one per run) + existing Sentry cron heartbeat
  cadence: weekly (cron "0 0 * * 0"), plus on-demand via cron/compound-promote.manual-trigger
  alert_target: none added in this plan — a streak alert needs a marker baseline that does not yet exist
  configured_in: apps/web-platform/server/inngest/functions/cron-compound-promote.ts
error_reporting:
  destination: Sentry via reportSilentFallback (feature=cron-compound-promote); pino WARN+ to Better Stack
  fail_loud: true — a missing marker fails Guard 1 in CI
failure_modes:
  - mode: proposer produces zero output indefinitely (the state under investigation)
    detection: marker status + refusals[] + bounded refusal_detail
    alert_route: read on demand; a threshold alert is deferred until a baseline exists
  - mode: every cluster refused by one guard
    detection: refusal_detail shows the same cluster_hash recurring week over week
    alert_route: same marker
  - mode: allowlist bypass via prefix-variant or rename diff
    detection: Guard 2 mutation matrix rows 1-5
    alert_route: CI red
  - mode: the marker itself stops being emitted
    detection: Guard 1 census in CI
    alert_route: CI red
logs:
  where: Better Stack (soleur-inngest-vector-prd) via pino WARN+
  retention: source default
discoverability_test:
  command: >
    doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh
    --since 200h --grep SOLEUR_COMPOUND_PROMOTE_OUTCOME --limit 20
  expected_output: >
    at least one row whose decoded message carries status=<one of the 7 known values>
  credentials_required: >
    Better Stack ClickHouse read (Doppler prd_terraform, BETTERSTACK_QUERY_*) — the property is
    "the marker reached the log sink", and no unauthenticated probe can verify ingestion of a
    container-emitted WARN line. A local grep would verify code shape only, which is precisely the
    substitution that produced the unobservable loop.
```

### Soak Follow-Through Enrollment

AC9 is time-gated on the Sunday cron (AC8 is satisfied on demand, which does **not** exercise the
scheduled path):

- Script: `scripts/followthroughs/compound-promote-outcome-8281.sh` — exit 0 when a marker row
  exists whose timestamp falls after the merge **and** on a scheduled (not manually-triggered) run;
  exit 1 while still waiting.
- Directive on #8281 with the `follow-through` label:

```
<!-- soleur:followthrough
  script=scripts/followthroughs/compound-promote-outcome-8281.sh
  earliest=<merge date + 8 days>T00:00:00Z
  secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD
-->
```

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The allowlist fix is still incomplete for a diff shape nobody enumerated | Derivation comes from `git apply`'s own reporting rather than a hand-written parser; Guard 2 includes a dispatch row and a from-scratch RED fixture. Rows 1 and 4 are both **measured**, not imagined |
| A WARN marker on `completed` files a weekly Sentry event (`logger.ts:123-125` auto-mirrors WARN+) | Accepted: one event per week on a cron the operator is actively diagnosing. Revisit once the loop is healthy — noted in the deferred issue |
| The measured cause turns out to be trivial (`enabled: false`, dedup, week-cap) | That is a **success**: it costs one small PR instead of a pattern layer built on a wrong hypothesis. Step 0.1 checks the cheapest candidate first |
| `refusal_detail` leaks content into logs | It carries `cluster_hash` + a fixed reason enum only — no learning text, no paths |
| Deferring the pattern layer loses the analysis | Captured in full in the deferred issue with the panel's findings, not discarded |

## Non-Goals

- **NG1** No pattern layer, no index, no backfill — deferred (see below).
- **NG2** No ledger schema change. `Cluster-Hash` is already a column and already the search key.
- **NG3** No streak detector and no Sentry alert resource — both need a marker baseline first, and a
  ledger-sourced streak would count rows that zero-output runs never write.
- **NG4** No new skill, no `description:` change (budget is at 2,442/2,442).
- **NG5** No auto-merge; the proposer's output remains a human-reviewed draft PR.
- **NG6** No raw-trace layer (CLO P1).

## Deferred

Filed as a follow-up, gated — **not** abandoned. It carries the WikiSkill analysis, the panel's
findings, and this two-part entry gate (the CPO's, because "produces observable proposals" conflates
two different events):

- **(G-a)** four consecutive weekly runs with a readable `status`; **and**
- **(G-b)** ≥1 draft PR opened, **or** a recorded `no_action` whose cause is named and is *not*
  "unobservable".

Design constraints the follow-up inherits (each verified this session):

1. Place pattern pages at a **sibling top-level** `knowledge-base/project/patterns/` — the
   `learnings/` subtree is blinded by **two** gitleaks rules, and `PII_REGEX` filters the
   proposer's prompt input, never a write path.
2. **Exclude `patterns/` from all four corpus readers** (`cron-compound-promote.ts` `walkDir`,
   `kb-staleness-metric.sh`, `weakness-miner.sh`, `generate-kb-index.sh`) or the proposer cites its
   own prior output as evidence, the tag substrate feeds back into its own clustering key, and the
   Jaccard baseline breaks discontinuously.
3. The **ledger row must land independently of the proposal's fate** — today it is appended inside
   the per-cluster branch and committed with the diff, so a closed PR's row never reaches `main`.
4. Read prior outcomes via **Octokit**, not `gh` (absent at runtime), and define the failure path: a
   fail-closed ledger read would recreate the silent-zero-output bug this work exists to remove.
5. Suppression by "closed-unmerged" must not be permanent and unlogged — #5292 was closed by a
   polling bot, so closure does not imply rejection-on-merit. Add `ledger-suppressed` to the refusal
   set so a suppressed cluster is visible in the marker.
6. Pattern pages need a **close state**; without one, a fixed failure stays in the prompt forever.
7. A seeded start (~18 clusters already in `weakness-digest.md`) ships producer **and** consumer
   together; a full 2,309-file backfill does not.

## Test Scenarios

1. Handler returns `disabled` → one marker, `status=disabled`.
2. Handler returns `no-qualifying-clusters` → marker carries `clusters_proposed=0`.
3. Handler throws → marker `status=error` **and** `reportSilentFallback` fires.
4. `+++ x/.github/workflows/foo.yml` → refused, reason recorded.
5. Diff with no `+++` header → refused (empty derived set).
6. Two-file diff, second path forbidden → refused.
7. **Rename `AGENTS.rules.md` → allowlisted `SKILL.md`** → refused; source still exists.
8. `copy from AGENTS.rules.md` → refused.
9. Legitimate two-file diff (`AGENTS.rules.md` + `SKILL.md`) → **applies** (must-PASS control).
10. Same cluster refused on consecutive runs → `refusal_detail` shows the repeated `cluster_hash`.
11. Census with a stubbed empty return-set → RED.
