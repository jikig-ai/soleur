---
title: "fix: op=verify cannot exhaust its scan window — narrow it and anchor it on a trustworthy instant"
type: fix
issue: 6178
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
cpo_signoff: "APPROVE WITH CONDITIONS (C1-C5) — all five satisfied in v2, see § Plan Review Consolidation"
branch: feat-one-shot-6178-verify-window-decouple
pr: 6933
date: 2026-07-24
revision: 2
---

# fix: `op=verify` cannot exhaust its scan window (#6178)

> Spec lacks valid `lane:` (no `spec.md` for this branch) — defaulted to `cross-domain` (TR2 fail-closed).
>
> **v2** after a 7-agent plan-review panel. v1's stated root cause was wrong, v1 named a
> nonexistent test file, v1's safety assertion could not fire, and v1's margin could not survive
> operator clock skew. See § Plan Review Consolidation.

## Overview

`op=verify` is the last open gate on the #6178 cutover and has never produced a verdict.

**Root cause (corrected in v2).** `inngest-doublefire-probe.sh` scans a window opened at
`cutover − 200d`. That window holds more runs than the ~18-page budget can exhaust
(`PREFLIGHT_DEADLINE_S=90` at ~5 s/page as shipped, `PAGE_SIZE=100`), and the probe is
**fail-loud on non-exhaustion** — `_pf_abort` exits 1 and emits *nothing*. So the run dies with
`reason=deadline` and no verdict.

**v1 blamed `STARTED_AT ASC` ordering. That was wrong**, and the tell was inside v1 itself: Phase
1.3 explicitly declined to change the ordering and no phase touched it. A diagnosis no phase acts
on is not a diagnosis. Because the abort emits nothing, a `DESC` scan that fails to exhaust the
window fails identically — ordering is not causally decisive. The operative variables are
**window width vs. budget**.

The fix is therefore narrow: make the scanned window small enough to exhaust, anchor it on an
instant that is actually trustworthy, and make the probe report its own scale so the next decision
is measured rather than extrapolated.

## Premise Validation (Phase 0.6)

| Premise | Method | Verdict |
|---|---|---|
| #6178 is OPEN | `gh issue view 6178` | **HOLDS** — OPEN, `closed_by: []` |
| The 2026-07-24 pagination fix is delivered and working | delivery run 30109885600 `files_written=15/15`; host sha256 `36fbef6c…1636f7` == `git show main:…`; markers `pages_timed_out=0 last_curl_exit=0` | **HOLDS** — every page succeeded. Not a transport defect. |
| Deadline lever is dead | SUM bound `DEADLINE + PAGE_MIN ≤ outer_curl` (120 s) caps `PREFLIGHT_DEADLINE_S` at 112 s → ~14 pages vs today's 12 | **HOLDS** |
| `CUTOVER_REGISTRY_BASELINE` is unreachable dead code | dereferenced twice, absent from the step `env:` | **HOLDS — and v1 undercounted.** `CUTOVER_QUIESCE_PROBES` is a *fourth* instance. Both deferred (below). |
| ADR-106 `## Decision` item 4's `2×max_cron_period` term is the function-discovery term | The missed-tick loop enumerates `[.runs[].functionID] \| unique`; a 182-day window guarantees even a quarterly cron appears | **HOLDS** — confirmed by architecture review |
| `op=verify` is read-only, no environment gate | `environment: ${{ (inputs.op == 'arm' \|\| inputs.op == 'rollback') && 'inngest-cutover' \|\| '' }}` → `''`; run 30117008226 executed without an approval hold | **HOLDS**. Note it shares `concurrency: deploy-inngest-restart`, so a dispatch may sit `queued`. |
| **`op=arm` run 30021969276 concluded `failure`, yet the host IS armed** | G5 wrote `INNGEST_CUTOVER_FLIP=armed`; the G6 poll timed out at 600 s. Better Stack shows `flag:"done" reason:"noop-done" exit_code:0` on `soleur-inngest-prd` | **CRITICAL** — no workflow-run timestamp is a sound arm anchor |
| The cutover was **not** a single forward pass | Seven `op=rearm` dispatches across 07-24 (10:46–15:54) | **HOLDS** — coexistence is not one interval; a single scalar cannot express it |
| web-2 exists (workflow comment asserts `CUTOVER_HOSTS` MUST include 10.0.1.11) | Hetzner API: one web host (`soleur-web-platform`, 10.0.1.10). `model.c4`: web-2 retired 2026-07-17 (#6538/#6463), `var.web_hosts` single-host | **STALE COMMENT** — web-2 does not exist; the DI-C3 caveat is moot |

### Phase 0 RESULT — measured 2026-07-24, run 30121678305 (the UNKNOWN is now known)

Method: set `CUTOVER_WINDOW_UNTIL = now + 199d` so today's `doublefire_from()` returns
`≈ now − 1d`; dispatch `op=doublefire-probe`. Variable deleted immediately after; repo variable
count re-verified at **0**.

| Quantity | Measured | Consequence |
|---|---|---|
| Runs in a **1-day** window | **728** | Density is the constraint, as diagnosed |
| Scan wall-clock | **34 s**, no deadline abort | A 1-day window **is** exhaustible — mechanism confirmed |
| Implied page rate | ~8 pages / 34 s ≈ **4.2 s/page** | Faster than the 7.7 s/page seen on the wide window |
| Implied 200-day total | ~**145,600** runs ≈ **1,456 pages** | v1's "~540 pages" extrapolation **understated it ~2.7×** |
| Affordable at 90 s | ~18 pages ≈ **~1,800 runs ≈ ~2.5 days** (the shipped divisor rounds 4.2 up to 5 for headroom) | The exhaustible window is **days, not weeks** |

**This falsifies the fallback width in this plan's own first draft of Phase 2.** A 7-day floor is
~5,100 runs ≈ 51 pages ≈ 214 s — **not exhaustible**. Safety (a wide floor so an operator anchor
can only widen) and liveness (a window narrow enough to finish) are in direct tension, and the
tension is resolved only by making the anchor *correct*, not merely bounded:

- The **FSM-derived anchor is load-bearing, not a nicety.** It is the only source that yields a
  window both correct and exhaustible (coexistence start ≈ 28 h ago ⇒ ~850 runs ≈ 9 pages ≈ 38 s).
- **There is no safe wide fallback.** If the anchor cannot be derived, the honest behavior is to
  **fail closed** — "anchor underivable, supply `CUTOVER_WINDOW_FROM`" — not to scan a window that
  provably cannot complete. A `now − 7d` floor would trade a deadline abort for a deadline abort.
- The **page-1 feasibility gate** (Phase 1.4) is what makes this safe to operate: it converts
  "too wide" into a ~2 s abort naming the latest viable anchor.

### Phase 0 SECOND DEFECT — the bucketing jq dies on a null `startedAt` (BLOCKS the fix)

The measurement run reported `728 run(s) in window; bucketing by …` and then **exited 5**. There is
no `exit 5` in the workflow — that is `jq`'s runtime-error code, propagated by `set -euo pipefail`.
Reproduced exactly:

```
$ echo '{"runs":[{"functionID":"a","startedAt":null}]}' \
    | jq -c '[ .runs[] | { fn: .functionID, bucket: ((.startedAt|fromdateiso8601)/1200|floor) } ]'
jq: error (at <stdin>:1): strptime/1 requires string inputs and arguments
jq_rc=5
```

The probe projects `{functionID, startedAt}` from **every** returned node. A run that is queued,
running, or cancelled-before-start carries `startedAt: null`, and `fromdateiso8601` throws on it.

**This is a second defect sitting directly behind the first, on the critical path.** Narrowing the
window alone would have moved the failure from `reason=deadline` to a `jq` crash — and AC-V4 would
have recorded "plan failed, the fix did not work." It has been invisible until now because the scan
had never once completed far enough to reach the bucketing step.

Required (added to Phase 2): make the bucketing null-safe in **both** the `op=verify` arm and the
`op=doublefire-probe` arm. A run with no `startedAt` has not fired and therefore cannot be a
double-fire, so `select(.startedAt != null)` is semantically right — but it **must not be silent**:
emit the dropped count as a `::notice::`, because silently discarding runs is exactly the
false-clean shape this gate exists to prevent. The same null-guard applies to the missed-tick
`OBSERVED` computation, which uses the identical expression.

### Phase 2 IMPLEMENTATION CORRECTION — "earliest relevant flip row" was the wrong predicate

Phase 2.5 as written says the FSM derivation anchors on the *"earliest relevant flip row"*. Measured
against production at implementation time, **that predicate would have produced a window narrower
than the coexistence region** — the unsafe direction, and precisely the vacuous clean verdict AC-V3
exists to reject.

`inngest-cutover-flip` runs on a **~30-second on-host timer** and re-emits
`flag:"done" reason:"noop-done"` on **every tick** — ~2,880 rows/day. Measured 2026-07-24: a
400-row query over a 5-day `--since` spanned only **four hours** and was **100% `noop-done`**. And
`betterstack-query.sh`'s `--limit` takes the **newest** N rows, so "earliest row returned" resolves
to a few hours ago regardless of how far back the query reaches.

The correct predicate is the earliest **transition** row — `reason` outside the `noop-*` family.
The emitter's vocabulary splits cleanly (`inngest-cutover-flip.sh` `emit_state`): transitions are
`flip-complete` / `flushed-resume-no-reflush` / `rolled-back` / `dbsize-nonzero` / `flushall-failed` /
`refuse-rearm-after-done`. Production holds exactly **one** (`done/flip-complete` @
`2026-07-24 10:20:51Z`) against thousands of heartbeats.

Two sharp edges the correction carries:

- **`noop-rolled-back` CONTAINS the substring `rolled-back`.** The reasons must be matched in their
  quoted form (`"reason":"rolled-back"`), or a bare grep re-admits the whole heartbeat firehose.
- **A full `--limit` page is a truncation signal**, and truncation biases the anchor *later*
  (narrower). The deriver refuses on a full page so the caller falls through to a **wider** source.

Fixed inline rather than routed as an architecture fork: the plan's *intent* — anchor on the instant
stamped by 10.0.1.40's clock — is preserved exactly; only its literal row-selection predicate was
wrong, because the plan's author did not know the emitter is a heartbeat. Recorded in ADR-146 § 1.

### Phase 0.5 DISPOSITION — `INNGEST_GQL_PAGE_SIZE=500` stays unmeasured, with the reason

Not measured, per this plan's own sanctioned alternative ("must be deferred with the number recorded
as unknown"). The doublefire hook plumbs only `from` and `function_ids`, so measuring it requires
threading a **new hook parameter** into `hooks.json.tmpl` and redeploying the host hook config — a
production infra deploy on the critical path.

It changes **no decision in this PR**: the fsm-anchored window fits comfortably at `PAGE_SIZE=100`
(the measured coexistence start is ~10.7 h before the measurement, ≈ 343 runs ≈ 4 pages ≈ 17 s; the
1-day floor is 728 runs ≈ 8 pages ≈ 34 s). It would only widen headroom — and headroom only matters
in the branch where the anchor is underivable, which this design **fails closed** on by choice.
Carried as ADR-146 § Deferred 4.

### UNKNOWN — resolved by Phase 0 above; kept for the record

The GraphQL query **already requests `totalCount`** and the script **never parses it** (the sole
occurrence of the token is inside the query string). The scan fetches its own scale on every page
and discards it. So the true run count in the window remains unmeasured; v1's "~540 pages"
was extrapolated from counting cron schedules in source, not measured.

The design does not depend on resolving it — a window that cannot be exhausted yields no verdict
at any count. But Phase 0 now **measures it before merging** and Phase 2 makes the probe
self-report, so no third iteration extrapolates.

## Plan Review Consolidation (v1 → v2)

Seven reviewers: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, CTO,
CPO. Findings applied:

**Corrections to v1 (all verified against the tree before applying):**

1. **Wrong test path.** v1 named `tests/scripts/infra/cutover-inngest-workflow.test.sh`. It does
   not exist. Real: `apps/web-platform/infra/cutover-inngest-workflow.test.sh`, registered at
   `.github/workflows/infra-validation.yml:656`. `scripts/lint-orphan-test-suites.sh` scans only
   `scripts/*.test.sh`, so the orphan would never have been caught — every new assertion would
   have been self-certified locally while CI stayed green.
2. **v1's fail-closed coverage assertion could not fire.** `DF_FROM = FROM − 2×CRON_PERIOD` with
   `CRON_PERIOD` validated `^[1-9][0-9]*$` always precedes `FROM`. It tested arithmetic. The
   **reachable** failure: `doublefire_from()` ends `|| true`, an empty `DF_FROM` builds `?from=`,
   and the probe falls back to its **own 365-day default** — silently restoring the exact bug.
3. **Second callsite.** `doublefire_from()` is called at `:292` (`op=doublefire-probe`, the
   pre-cutover dark-host detector) as well as `:1198`. v1 addressed only `op=verify`; narrowing
   would have dropped the dark-host arm from 200 d to 7 d — a false-clean on the plan's own harm.
4. **v1 introduced a fifth instance of the bug class it was fixing.** `DOUBLEFIRE_FALLBACK_DAYS`
   was unmapped in the step `env:`, and the proposed guard is `CUTOVER_*`-scoped so it would not
   have caught it.
5. **Clock-skew P0.** `DF_FROM` is computed on the GitHub runner from an operator-typed string;
   `startedAt` is stamped on 10.0.1.40. The 200-day window carried ~18 days of slack; v1's margin
   was 40 minutes at `cron_period_seconds=1200`. An operator typing Europe/Paris local time in July
   (UTC+2) lands `DF_FROM` 80 minutes late — 2× past the margin — and v1's assertion passes because
   both sides derive from the same wrong scalar.
6. **Four more vacuous ACs** beyond the one caught during authoring (AC9 monotone `exit 1` count;
   AC7 clause 1 — `CUTOVER_WINDOW_FROM` already appears 4×; AC8 — a preservation check that passes
   on an untouched ADR; AC3 — misses the `raise PREFLIGHT_DEADLINE_S` phrasing in the header).
   Every AC in v2 carries its **measured baseline inline**, on the model of v1's AC6.
7. **A guard scoped to `CUTOVER_*` false-positives forever** on `INNGEST_CUTOVER_FLIP` /
   `INNGEST_CUTOVER_QUIESCE` — substring artifacts that are **Doppler secret names** and must never
   enter the env block. Recorded in the deferred issue so the follow-up cannot get this wrong.

**Scope decision (operator-confirmed).** Registry-sourced missed-tick discovery is **cut to a
follow-up**. Rationale: it has zero effect on the double-fire verdict, the blocker is purely the
window, and the registry probe returns ids with **no trigger type**, so the advisory could not
distinguish cron from event-driven functions. The follow-up carries architecture's superior design
(§ Deferred work) rather than v1's weaker advisory-only scoping.

**Cross-review conflict adjudicated.** spec-flow and code-simplicity both proposed bounding the
window with `until=`. **Rejected** — architecture showed the post-repoint region (when the
dedicated host first had functions registered, and therefore first *could* double-fire) lies
*after* `CUTOVER_WINDOW_UNTIL`, as does every `op=rollback`-initiated interval. The open top is
load-bearing. v2 records it as an explicit invariant with a test.

**CPO conditions C1–C5** all satisfied: C1 (§ User-Brand Impact rewritten with the inheritance
rule and `cron-workspace-gc` as worst case), C2 (vacuous-clean + omission classes added), C3
(AC15 split), C4 (snapshot decision recorded, § Rollback artifact), C5 (Phases cut, `totalCount`
kept — CPO dissented from the engineering panel here and I agree: it prevents a third blind
iteration).

## Hypotheses (network-outage gate — fired on `timeout`)

`hr-ssh-diagnosis-verify-firewall` requires L3→L7 before any service-layer hypothesis. The trigger
word here is a wall-clock deadline in a shell script, not a network timeout, and the layers are
answered with measured artifacts:

| Layer | Artifact | Verdict |
|---|---|---|
| L3 firewall / L3 DNS / L4-L7 transport | `SOLEUR_INNGEST_PREFLIGHT_TIMEOUT … pages_timed_out=0 last_curl_exit=0` — **12/12 page round-trips completed** over the private net | **VERIFIED — all excluded** |
| L7 service (Inngest server) | answered every page; `op=verify-registry` completed in 1 page at ~0 ms | **VERIFIED — excluded** |
| Application — window width vs. budget, fail-loud on non-exhaustion | `from=2026-01-05T18:28:08Z`, `pages=12`, `reason=deadline`, `_pf_abort` emits nothing | **CONFIRMED — cause** |

## User-Brand Impact

**Severity inheritance.** This PR cannot cause a duplicate fire; it can only cause a **wrong
verdict**. The two wrong verdicts are asymmetric:

- **False DIRTY** → cutover stays blocked, founder time burned. Low, internal.
- **False CLEAN** → #6178 closes, the snapshot is released, the rollback decision is abandoned, and
  duplication ships silently. **Inherits the mechanism's full severity.** This is why the threshold
  is `single-user incident`.

**If this lands broken, the user experiences:** duplicated cron side effects across a 55-entry
manifest. The worst case is **not** a duplicate email — it is `cron-workspace-gc`, which
"sweeps `/workspaces` **DIRECTLY**" and removes aged directories on the shared volume holding live
user workspaces (`cron-workspace-gc.ts`, header comment). Two concurrent sweepers race the same
delete set: **data destruction, not noise.** Also `cron-action-required-sla` (fans out per open
issue; the worker holds close authority, ADR-138) and `cron-rule-prune` (double-appends a
retirement ledger, opens duplicate bot PRs). `cron-gh-pages-cert-reissue` would be the outage case
but is registered `[{ event: "cron/gh-pages-cert-reissue.manual-trigger" }]` — event-only, out of
scheduler reach, correctly excluded.

**Two failure classes specific to a false CLEAN** (added in v2):

- **Vacuous clean.** "Clean" can mean "no duplicates found" *or* "nothing was looked at" —
  and narrowing the window is precisely what makes the second reachable. The closure signal must
  be non-vacuous **by construction**, not by operator diligence. Enforced by AC-V3.
- **The omission half.** Exactly-once has two halves and a false clean blesses both. A dropped tick
  means a reminder that never fires, content that never publishes, a GHCR token that never rotates
  until deploys fail on expiry (#5542). For a pre-beta product, silent non-execution reads as "the
  product doesn't work" — at least as brand-damaging as a visible duplicate.

**If this leaks:** no new exposure. Probe output is `{functionID, startedAt}` — run UUIDs and
timestamps. AC-NOBODY purity and `_pf_scrub` DSN redaction are preserved unchanged.

**Scope honesty (v2 correction):** v1 claimed `op=verify` "is the only gate that would catch this."
That over-claims — the probe reads only 10.0.1.40's run history. It is not, and never was, a
detector for a second scheduler writing to its own backend. (The historical DI-C3 web-2 concern is
moot: web-2 was retired 2026-07-17 and `var.web_hosts` is single-host.)

**Brand-survival threshold:** `single-user incident`. `requires_cpo_signoff: true` — obtained,
APPROVE WITH CONDITIONS, all conditions satisfied.

## Rollback artifact (CPO C4)

Hetzner image **411798619** = `inngest-cutover-pre-20260723T153403Z`, labels
`purpose=inngest-cutover-pre`, `created_from: soleur-web-platform` (**the web host**), delete
protection off, ~24 GB.

**Retention:** held until #6178 closes per AC-V4. **What it is:** disk-state insurance, **not** an
executable rollback path for the dedicated-host cutover. It was taken by `op=backup` in the
runbook's *same-host* section; the dedicated-host section has no snapshot step. Runbook step 7
states that reverting to `--sqlite-dir` is data-safe only *before* a real reminder is armed against
Postgres — after that it is **forward-fix only**, because stale SQLite both misses reminders and
could double-fire ones Postgres recorded. **Consequence:** a red `op=verify` has no retreat, only a
forward fix. Delete trigger: AC-V4 satisfied (`exactly-once VERIFIED`, non-vacuous).

## Architecture Decision (ADR/C4)

### ADR — amendment + one new record

**Amend `ADR-106` `## Decision` item 4** (content anchor: the paragraph beginning *"Cost reduction
— completeness BY CONSTRUCTION"* through the `SEPARATE invariant` sentence):

- Restate the ⊇ invariant as `DF window ⊇ [CUTOVER_WINDOW_FROM, CUTOVER_WINDOW_UNTIL]`, which the
  new anchoring satisfies exactly.
- Record that the `2×max_cron_period` term **was** the function-discovery term (the missed-tick
  loop enumerates functions observed in the DF window), that discovery is deferred to the
  follow-up, and that **until then slow-cron missed-tick recall is reduced** — an explicit,
  recorded trade, not a silent one.
- Record the **open-topped invariant**: `DF_URL` must carry no `until`, because the post-repoint
  and post-rollback coexistence regions lie after `CUTOVER_WINDOW_UNTIL`.
- Record `timeField: STARTED_AT` as a **load-bearing coupling** (below).
- Re-anchor the stale `cutover-inngest.yml:704-743` cross-reference by content
  (`cq-cite-content-anchor-not-line-number`); that block now lives at ~`:1242-1282`.
- Note it does not disturb the `## Considered Options` "narrow the eventsV2 window" rejection,
  which concerns the *inventory* scan, not the *runs* scan.

**New `ADR-146` (`amends: ADR-106`)** — *Trust anchor for the cutover coexistence window*.
Moving the safety bound from an operator-typed repo variable to the Better Stack flip-FSM row is a
**source-of-truth change**, not a restatement: it introduces a new trust boundary and a new
failure mode (retention miss). ADR-106 is scoped to scan bounding + abandon-safety + markers;
grafting trust-anchor semantics into item 4 would make it canonical for two unrelated concerns.
Ordinal 143 is **provisional** — `/ship`'s ADR-Ordinal Collision Gate re-verifies against
`origin/main`, and a renumber must sweep this plan, `tasks.md`, and every AC naming the ordinal.

**ADR-100 needs no amendment.** Its Decision 7 fixes the filter shape and bucketing rule, not a
window width. Note for the record: ADR-100's status gate is a **7-day** Phase-4 soak, which a
`now`-relative fallback window discharges only if `op=verify` runs within 7 days of the cutover.
This PR does not claim to discharge it.

### C4 views

**No C4 impact.** Enumerated against all three model files. No external human actor, external
system, container, data store, or access relationship is added or changed. `inngest`,
`inngestPostgres`, `inngestRedis`, Better Stack (`model.c4`), and the `api -> inngest` private-net
edge are all already modeled; the change is *which time window an already-modeled internal probe
queries*. `grep -c 'doublefire\|cutover'` is 0 in `views.c4` and `spec.c4`; the 8 hits in
`model.c4` are descriptive prose this change does not falsify.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_INNGEST_PREFLIGHT_TIMEOUT / _DONE op=verify-doublefire ... total_count=<N|unknown> scanned=<M>  (anchor_source is workflow-side: a ::notice:: in the Actions run log, NOT a probe marker -- the probe never receives it)
  cadence: per op=verify / op=doublefire-probe dispatch (operator-triggered)
  alert_target: Better Stack Logs source 2457081 (journald -> Vector), via scripts/betterstack-query.sh
  configured_in: apps/web-platform/infra/inngest-doublefire-probe.sh (_pf_marker) + apps/web-platform/infra/vector.toml (already allowlists "inngest-doublefire-probe")

error_reporting:
  destination: GitHub Actions ::error:: annotation + SOLEUR_INNGEST_PREFLIGHT_* markers -> Better Stack
  fail_loud: true — every abort exits non-zero and refuses to emit a partial run set

failure_modes:
  - mode: window still not exhaustible
    detection: page-1 feasibility gate aborts in ~2s with total_count=<N> and a COMPUTED remediation naming the latest viable anchor
    alert_route: exit 1; the message carries the arithmetic, so the next narrowing is measured
  - mode: anchor unavailable or unparseable (empty/malformed DF_FROM)
    detection: fail-closed regex assertion on DF_FROM before the request is built
    alert_route: ::error:: + exit 1 — replaces the silent 365-day probe-default fallback
  - mode: anchor present but WRONG (operator clock skew / stale repo var)
    detection: min() floor — the operator value can only widen, never narrow below now-FALLBACK; and anchor_source= names which source won
    alert_route: bounded by construction; anchor_source in the marker makes a var-sourced anchor visible off-box
  - mode: Better Stack retention miss on the FSM row (or a failed/truncated derive query)
    detection: _flip_transition_dt returns non-zero and emits a per-branch ::warning:: naming the
      branch (query-failed / no-transition-row / truncated / dt-malformed); the caller falls through
      to CUTOVER_WINDOW_FROM (anchor_source=var) and then FAILS CLOSED -- never to a wide window
    alert_route: ::warning:: per branch, then ::error:: + exit 1 in the GitHub Actions run log

logs:
  where: journald on web-1 (tag inngest-doublefire-probe) -> Vector -> Better Stack source 2457081
  retention: existing Better Stack Logs retention; unchanged

discoverability_test:
  command: doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 1h --grep SOLEUR_INNGEST_PREFLIGHT --limit 20
  expected_output: a SOLEUR_INNGEST_PREFLIGHT_DONE op=verify-doublefire line carrying total_count= and scanned=; anchor_source= is read from the Actions run log
```

No `ssh`. Per §2.9.2 this is a partially blind surface; `total_count` + `anchor_source` are the
discriminating fields that separate "window too wide" from "budget too small" from "anchored on the
wrong instant" in a single event.

## Files to Edit

- `apps/web-platform/infra/inngest-doublefire-probe.sh` — parse `totalCount`; page-1 feasibility
  gate; corrected FATAL remediation strings; header-comment restatement.
- `apps/web-platform/infra/inngest-doublefire-probe.test.sh` *(CI: `infra-validation.yml:641`)*
- `.github/workflows/cutover-inngest.yml` — `doublefire_from()` rewrite (anchor derivation, min()
  floor, per-arm fallback); fail-closed DF_FROM assertion.
- `apps/web-platform/infra/cutover-inngest-workflow.test.sh` *(CI: `infra-validation.yml:656`)* —
  **corrected path**; add the `doublefire_from()` execution harness.
- `knowledge-base/engineering/architecture/decisions/ADR-106-inngest-cutover-preflight-scan-bounding-and-in-surface-marker.md`
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-146-trust-anchor-for-cutover-coexistence-window.md`

## Implementation Phases

### Phase 0 — Measure the unknown BEFORE writing code (no code change)

The window's true run count has never been measured. Measure it now, with zero code change:
temporarily set `CUTOVER_WINDOW_UNTIL` to `now + 200d`, which makes today's `doublefire_from()`
return ≈ `now` and shrinks the scan to minutes; dispatch `op=doublefire-probe`. A clean completion
confirms density is the constraint and yields the scale. Unset the variable immediately after.

Record the result in this plan. If the probe still deadlines on a minutes-wide window, the
diagnosis is wrong and **stop** — do not proceed to Phase 1.

Also measure the untested capacity lever: `INNGEST_GQL_PAGE_SIZE` is `100` and nobody has measured
s/page at 500. 7.7 s for 100 rows is likely per-request overhead, not row throughput. Note: the
hook template plumbs only `from` and `function_ids`, so this measurement needs the page-size env
threaded, or must be deferred with the number recorded as unknown.

### Phase 1 — Probe: `totalCount` + page-1 feasibility gate (contract change)

1.1 RED: assertions that the emitted object and the `_TIMEOUT` marker carry `total_count`; that an
abort **before page 1 parses** emits `total_count=unknown` (not an empty field or a `0` that reads
as "no runs"); that a `totalCount` exceeding the affordable budget aborts on page 1.

> The existing `make_page` helper hardcodes `totalCount:($edges|length)`, so `totalCount` can never
> exceed the page's edge count. Phase 1.1 requires a `make_page` signature change (explicit
> totalCount arg) touching its existing call sites — budgeted here, unbudgeted in v1.

1.2 GREEN: parse `.data.runs.totalCount` from page 1. Compute affordable runs from the measured
budget; if `totalCount` exceeds it, abort immediately with the numbers inline and a **computed**
remediation naming the latest viable anchor. This turns a 112 s failure into a ~2 s one and makes
the message self-correcting.

1.3 Correct the dead remediation strings. Widen the assertion to
`grep -cE '(increase|raise|bump) PREFLIGHT_DEADLINE_S' == 0` — v1's `increase`-only grep missed the
`raise PREFLIGHT_DEADLINE_S` phrasing in the header block. Update the header's RESIDUAL LIMITATION
and `window ⊇ …` paragraphs, which currently assert "the time WINDOW is NEVER narrowed" — after
this PR the code does the opposite, and a comment contradicting the code is how this bug class
recurred three times.

### Phase 2 — Workflow: anchor derivation + min() floor + fail-closed (the fix)

2.1 RED: execute-and-assert `doublefire_from()`. **Extract and run it** — do not grep. Precedent:
`call_build_request_body` + its `test_df_build_body_harness_is_live` self-check in
`inngest-doublefire-probe.test.sh`. Table: FSM-derived / var-set / var-malformed / all-unset ×
`CRON_PERIOD` 1200, 3600. Assert the emitted ISO string, not its presence.

2.2 GREEN: rewrite `doublefire_from()`:

```
anchor  = FSM-derived instant (earliest relevant flip row)   # anchor_source=fsm
        | CUTOVER_WINDOW_FROM                                 # anchor_source=var
        | (none)  -> FAIL CLOSED, do not scan                 # anchor_source=none
DF_FROM = min( bucket_floor(anchor) − 2×CRON_PERIOD , now − FALLBACK_DAYS )
FALLBACK_DAYS = 1        # NOT 7 — see Phase 0 RESULT
```

- **`min()` is the skew remediation**, bounding an operator anchor so it can only ever *widen*.
  **But Phase 0 measured that a wide floor is not exhaustible** (7 d ≈ 5,100 runs ≈ 214 s), so the
  floor is `1 d` and it is a *skew guard*, not a safety net. The real safety comes from the anchor
  being correct (FSM-derived) plus the page-1 gate catching any residual over-width.
- **No wide fallback on an underivable anchor.** If neither the FSM row nor `CUTOVER_WINDOW_FROM`
  yields an instant, **fail closed** with "anchor underivable — supply `CUTOVER_WINDOW_FROM`".
  Scanning `now − 7d` would trade a deadline abort for a deadline abort while *looking* safer.
- **`bucket_floor(anchor) = anchor_epoch / CRON_PERIOD * CRON_PERIOD`** — exact, self-documenting,
  and *is* the boundary the downstream `group_by([.fn, .bucket])` uses. Replaces v1's bare magic
  number; the additional `2×CRON_PERIOD` is retained as skew margin.
- **FSM derivation** reuses `confirm_flip_state()`, already defined in this step, already
  authenticated via `doppler run … betterstack-query.sh`, already parsing
  `"flag":"<state>"` from the `inngest-cutover-flip` emitter. Decisive property: that row is
  stamped on **10.0.1.40's journald — the same clock that stamps `startedAt`** — which collapses
  the skew class entirely. Constraints: extract **only** the `dt` field (the function's existing
  contract is "NEVER echoes a raw row"; add a purity test); on a retention miss fall through to the
  **widest** window, never a narrower one.
- **Per-arm fallback.** `op=doublefire-probe` (`:292`, the pre-cutover dark-host detector) keeps
  200 d; only `op=verify` narrows. Pass the fallback as `$1` rather than reading an ambient global.
- Read `${CUTOVER_CRON_PERIOD_SECONDS:-3600}` directly instead of the caller-local `CRON_PERIOD`,
  removing an implicit ordering contract on a function defined ~900 lines away.
- **No new env knob.** v1's `DOUBLEFIRE_FALLBACK_DAYS` is dropped; the fallback is a literal.

2.3 Fail-closed on the **reachable** failure: after `DF_FROM=$(doublefire_from …)`, abort unless it
matches `^[0-9]{4}-[0-9]{2}-[0-9]{2}T`. Drop v1's tautological comparison. Note `date -u -d ''`
**succeeds** (returns today's midnight), so a non-empty guard is required, not just `2>/dev/null`.

2.4 Assert the **open-topped invariant**: `DF_URL` carries no `until` parameter, with a comment
naming why (the post-repoint and post-rollback regions lie after `CUTOVER_WINDOW_UNTIL`).

### Phase 3 — Docs + deferred work

3.1 Amend ADR-106 item 4; author ADR-146 (§ Architecture Decision).
3.2 Runbook §2.6: the two windows, the anchor sources, and `cron_period_seconds=1200`.
3.3 File the deferred issues (§ Deferred work).

## Deferred work (tracking issues — FILED)

**Filed 2026-07-24.** Item 2 (the missed-tick defect) is filed **separately** as a bug because it
is a discovered defect whose failure mode is the exact harm this cutover prevents — burying a
possible-P1 in a consolidated tracker is how it gets missed. Items 1, 3 and the `PAGE_SIZE`
measurement are deferred *scope*, so they consolidate into one tracker.

| Item | Issue | Priority |
|---|---|---|
| Missed-tick emits a nonexistent command + re-fire lines for never-due crons | **#6939** | `p1-high`, Phase 4 |
| Registry-sourced discovery · `CUTOVER_*` env mapping · `PAGE_SIZE=500` measurement | **#6940** | `p2-medium`, Post-MVP |
| #6178 triage was stale (`p2-medium` / Post-MVP predates the cutover running in production) | fixed **inline** → `p1-high`, Phase 4 | — |

**Net issue flow: closing 0, filing 2, net +2.** This PR closes nothing by design — #6178 is gated
on AC-V4 and `Ref`, not `Closes`. #6939 could not be inlined (it needs per-function trigger type
from `inngest-registry-probe.sh`, a separate work-stream) and must not be consolidated (it is a
defect, not deferred scope). #6940 consolidates three deferrals that would otherwise have been
three issues.

### Item detail (as specified pre-filing)

1. **Registry-sourced missed-tick discovery** — operator-confirmed cut. Prescribed design
   (architecture, built on ADR-106's own `armed_reminders` precedent): after computing
   `registry_ids − observed`, issue a **second** doublefire-probe call scoped
   `function_ids=<zero-run set>` over a `2×max_cron_period` window. The `functionIDs` filter makes
   it cheap for exactly the reason the armed-reminders query is cheap, restoring full slow-cron
   recall *and* dissolving the amplification risk. Requires extending `inngest-registry-probe.sh`
   to emit trigger type (ids alone cannot distinguish cron from event-driven functions).
   **Re-eval trigger:** before the next cutover that uses missed-tick enumeration.
2. **Missed-tick emits a command that does not exist.** The loop emits
   `soleur:trigger-cron --function-id <UUID> --missed-tick <TS>`; the skill accepts
   `--event cron/<name>.manual-trigger` and there is no UUID→name mapping anywhere. The line is
   unrunnable, and the loop fires for any function with ≥1 run *anywhere* in the scan window — so
   post-cutover it emits re-fire lines for crons that were never due. Re-firing one causes the
   double-fire this cutover prevents. **Interim de-fang:** gate the per-bucket output behind a
   `workflow_dispatch` input defaulting **off**.
3. **`CUTOVER_REGISTRY_BASELINE` + `CUTOVER_QUIESCE_PROBES` env mapping + completeness guard.**
   Deferred *after* AC-V4 is green: mapping the baseline activates a dormant `exit 1` **upstream**
   of the doublefire check this PR exists to reach. Guard spec for the follow-up: anchor as
   `grep -oP '(?<![A-Za-z0-9_])CUTOVER_[A-Z_]+'` (an unanchored grep matches `CUTOVER_FLIP` /
   `CUTOVER_QUIESCE`, which are **Doppler secret names on `soleur-inngest/prd`** and must never
   enter the env block); make the test's `$WF` target overridable so "fails against `main`" is
   demonstrable.
4. **`#6178` triage is stale** — `priority/p2-medium` in `Post-MVP / Later` predates the cutover
   being executed in production. Correct the priority or milestone.

## Acceptance Criteria

Every criterion carries its **measured baseline on `main`**, so none can pass on the broken input.

### Pre-merge

- **AC1** Phase 0's measurement is recorded in this plan with the observed run count and s/page.
  *(Baseline: unmeasured.)*
- **AC2** `grep -cE '\.data\.runs\.totalCount' apps/web-platform/infra/inngest-doublefire-probe.sh`
  ≥ 1 — anchored on the **parse expression**, not the bare token, which appears once inside the
  query string. *(Baseline: bare `totalCount` = 1; parse expression = 0.)*
- **AC3** `grep -cE '(increase|raise|bump) PREFLIGHT_DEADLINE_S' apps/web-platform/infra/inngest-doublefire-probe.sh`
  == 0. *(Baseline: 3 — two FATAL strings plus the header's `raise` phrasing.)*
- **AC4** `bash apps/web-platform/infra/inngest-doublefire-probe.test.sh` passes, including the
  page-1 gate, `total_count=unknown` on a pre-page-1 abort, and the reshaped `make_page`.
- **AC5** `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` passes, including the
  **executed** `doublefire_from()` harness and its `harness_is_live` self-check.
- **AC6** The harness is non-vacuous: mutating `doublefire_from()` to return an empty string makes
  AC5 **fail**. Demonstrate in the PR body. *(A harness that cannot fail is not a harness — this is
  the v1 lesson generalized.)*
- **AC7** `doublefire_from()`'s **body** (extracted between its opening and closing brace, not the
  whole file) contains no `200 \* 86400` and no `200 days ago`. *(Baseline in body: 1 and 1;
  file-scoped greps are vacuous — `CUTOVER_WINDOW_FROM` alone already appears 4× in the file.)*
- **AC8** `DF_URL` carries no `until` parameter, asserted in the workflow test with the rationale
  comment present. *(Baseline: no assertion exists.)*
- **AC9** ADR-106 item 4 contains a positive discriminator —
  `grep -c 'function discovery' ADR-106-*.md` ≥ 1 — **and** the preservation check
  `grep -c 'SEPARATE invariant'` ≥ 1 still holds. *(Baselines: 0 and 1. v1 asserted only the
  preservation half, which passes on an untouched file.)*
- **AC10** `ADR-146-*.md` exists and `grep -c 'amends: ADR-106'` ≥ 1. *(Baseline: file absent.)*
- **AC11** PR body uses `Ref #6178`, not `Closes` — the probe is delivered *by* the merge, so the
  verifying run cannot precede it.

### Post-merge (automated — no operator steps)

- **AC-V1** Delivery: `apply-deploy-pipeline-fix` reports `files_written == files_total`, and the
  delivered sha256 for `/usr/local/bin/inngest-doublefire-probe.sh` matches
  `git show main:… | sha256sum`. *Automation: `gh run watch` on the merge-triggered run.*
  **AC-V2 must not dispatch until this passes** — the two workflows use different concurrency
  groups and nothing serializes them, so a premature dispatch would let the **old** probe answer
  and fail identically.
- **AC-V2** `gh workflow run cutover-inngest.yml -f op=verify -f cron_period_seconds=1200`.
  Read-only, no environment gate; may sit `queued` behind the shared `deploy-inngest-restart` group.

  > `cron_period_seconds=1200` is load-bearing: `cron-ghcr-token-minter` runs `*/20 * * * *`
  > (1200 s, live in `cron-manifest.ts`), so the 3600 default would collapse three legitimate runs
  > into one bucket and report a **phantom** double-fire.

- **AC-V3 (non-vacuity)** Enforced IN CODE since review: `op=verify` hard-fails when
  `total_count` is `0`/`unknown`/`absent` or `RUN_COUNT == 0`, and downgrades a clean result to
  `exactly-once VERIFIED (QUALIFIED)` when the population was scoped, the window was overridden, or
  the anchor was weaker than `fsm`. Operator check: the probe's **markers** (Better Stack) carry
  `total_count`/`scanned`; the **Actions run log** carries `anchor_source`. A `floor(fsm)` source is
  the normal shape within ~24 h of the cutover — confirm the floor covers the quiesce instant. A
  QUALIFIED verdict **does not** satisfy AC-V4.
- **AC-V4 (verdict, split from v1's conflated AC15)**

  | Outcome | Plan status | #6178 | Snapshot 411798619 |
  |---|---|---|---|
  | `reason=deadline` abort | **failed** — fix did not work | stays open | retained |
  | `DOUBLE-FIRE detected` | **succeeded** — the gate works and caught a real defect | **stays open**; open an incident, enumerate duplicated `functionID`s, assess side effects | retained |
  | `exactly-once VERIFIED`, AC-V3 satisfied | succeeded | **eligible to close** | eligible to delete |

  v1 accepted a detected double-fire as closure-satisfying. That is backwards: it is the opening of
  an incident, not the closing of an issue.

## Domain Review

**Domains relevant:** Engineering, Product.

**Engineering** — reviewed by the 5-agent panel (§ Plan Review Consolidation). **Product** — CPO,
APPROVE WITH CONDITIONS C1–C5, all satisfied.

**Product/UX Gate — Tier: NONE.** Mechanical UI-surface scan over `## Files to Edit` /
`## Files to Create`: no match for `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`,
or any UI-surface term. `.sh`, `.yml`, `.md` only.

**GDPR (2.7)** — canonical regex does not match; trigger (b) fires on the threshold. Evaluated
**inert**: the diff touches no personal data (run UUIDs, function UUIDs, ISO timestamps, one
integer count). AC-NOBODY purity and `_pf_scrub` preserved. The new FSM extraction reads **only**
a `dt` timestamp and is covered by a purity test.

**IaC (2.8)** — skipped, no new infrastructure. **Encryption posture (2.11)** — skipped, no
persistent store and no new cross-component connection.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Operator anchor wrong (clock skew, stale repo var) | `min()` floor — the operator value can only widen. `anchor_source=` in the marker makes a var-sourced anchor visible off-box. |
| FSM row unavailable (Better Stack retention) | Fall through to the **widest** window, never narrower; `::warning::` names `anchor_source=floor`. |
| Narrowed window still not exhaustible | Phase 0 measures before merging; page-1 gate aborts in ~2 s with computed remediation. |
| `DF_FROM` empty → silent 365-day probe default | Fail-closed regex assertion (Phase 2.3) — the reachable failure v1 left open. |
| Fallback stops covering as the cutover ages (window is open-topped, cost grows with wall-clock) | Recorded as a known property; FSM anchor is age-independent. Named in ADR-146. |
| Dark-host detector silently narrowed | Per-arm fallback: `op=doublefire-probe` keeps 200 d, asserted in the workflow test. |
| Guard/harness vacuous | AC6 requires demonstrating the harness **fails** on a mutated function. |

## Test Scenarios

1. Probe: `totalCount` over budget → page-1 abort with computed remediation.
2. Probe: abort before page 1 parses → `total_count=unknown`, never empty or `0`.
3. Probe: clean completion → `_DONE` marker with `total_count`.
4. Probe: transient-then-recover, and non-empty malformed body → unchanged fail-loud behavior.
5. `doublefire_from()` **executed**: FSM-derived / var-set / var-malformed / all-unset ×
   `CRON_PERIOD` ∈ {1200, 3600}; assert the exact ISO output.
6. `doublefire_from()`: operator anchor far in the future → `min()` clamps to the floor.
7. `doublefire_from()`: `op=doublefire-probe` arm resolves to the 200 d fallback, `op=verify` does not.
8. Empty/malformed `DF_FROM` → fail-closed abort, not a silent probe-default fallback.
9. `DF_URL` contains no `until`.
10. Harness self-check: a mutated `doublefire_from()` fails the suite.

## Alternatives Considered

| Alternative | Verdict |
|---|---|
| Flip ordering to `DESC` | **Rejected — and v1's rejection reasoning was wrong.** The correct refutation: `_pf_abort` emits nothing, so no sort order produces a verdict from a non-exhausting scan. |
| Raise `PREFLIGHT_DEADLINE_S` | **Rejected, measured.** SUM bound caps it at 112 s ≈ 14 pages vs today's 12. |
| Raise `INNGEST_GQL_PAGE_SIZE` | **Unmeasured — Phase 0 measures it.** Never considered in v1. Composable with narrowing if it pays. |
| Scope `INNGEST_DOUBLEFIRE_FUNCTION_IDS` | **Rejected as the primary lever** — fits budget only by dropping the high-frequency crons most at risk. Retained as a documented cost lever. |
| Bound the window with `until=` | **Rejected** — cuts out the highest-risk region (post-repoint, post-rollback) while looking like a symmetric tidy-up. Recorded as an invariant with a test. |
| Keep the operator-typed repo variable as the safety anchor | **Rejected** at this threshold — unvalidatable, never expires, and a single scalar cannot express seven re-arm intervals. |
| Close #6178 on healthy-cutover signals | **Rejected.** FSM `done`, 68/68 registry, single scheduler are real but are not an exactly-once proof. |

## Sharp Edges

- **A diagnosis no phase acts on is not a diagnosis.** v1 named ASC ordering as the confirmed cause
  while Phase 1.3 explicitly declined to change it. When the Hypotheses table and the phase list
  disagree, the phase list is telling the truth.
- **A guard that cannot fail on the known-broken input is not a guard** — and the same applies to
  test harnesses. Prove the failure, don't assume it (AC6).
- **Every AC must carry its measured baseline inline.** v1 caught one vacuous AC and then wrote
  four more. The systemic fix is `cq-assert-anchor-not-bare-token` applied to *every* AC.
- **The window is open-topped on purpose.** Passing `until=` looks like a free cost saving and
  removes the highest-risk region. Do not "tidy" it.
- **`timeField: STARTED_AT` is load-bearing.** It is what makes a straggler safe: the filter key and
  the bucket key are the same quantity, so bucket membership is monotone in the filter predicate.
  `RunsFilterV2` also offers `QUEUED_AT`, which is arguably more natural for tick semantics — flip
  it and a run queued pre-window but started in-window escapes the filter while its pair is
  bucketed by `startedAt`: asymmetric truncation, invisible pair.
- **`op=arm` can conclude `failure` while the host is armed** (G5 writes the flip, the G6 poll
  times out). Never anchor on a workflow-run timestamp; anchor on the FSM row.
- **`date -u -d ''` succeeds**, returning today's midnight. A non-empty guard is required —
  `2>/dev/null || echo ""` is not sufficient.
- **The probe fetched `totalCount` on every page and discarded it.** When a component fetches a
  datum and throws it away, the resulting "unknown" looks like an inherent limit rather than a
  one-line omission. Check what the query already asks for before declaring a quantity unmeasurable.
