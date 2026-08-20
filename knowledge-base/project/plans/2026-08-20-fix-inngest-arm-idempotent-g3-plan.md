---
title: "fix(inngest): make op=arm idempotent so G3 stops self-poisoning after the first arm"
date: 2026-08-20
slug: fix-inngest-arm-idempotent-g3
branch: feat-one-shot-7462-arm-idempotent-g3
issue: 7462
closes: 7462
lane: cross-domain
type: bug-fix
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

`op=arm` in `scripts/cutover-inngest.sh` cannot run a second time. Its G3 guard refuses whenever the
value it is about to write already equals the value in place, and after the first successful arm that
condition is permanently true — so every subsequent arm is refused regardless of the system's actual
readiness.

This plan makes the arm **idempotent**: when the target value is already in place, G3 records that
fact and the write is skipped rather than the run being aborted. Every other G3 assertion is
preserved. The decision itself is extracted into a pure function so it can be driven red by a test,
which the current suite cannot do.

No spec.md exists for this branch (entered via one-shot without a brainstorm) — lane defaulted to
`cross-domain` (TR2 fail-closed). The domain sweep in §Domain Review was run at that wider setting and
found Engineering the only relevant domain.

## Research Insights

### Premise Validation (Phase 0.6)

Every premise was verified directly against live state this session rather than inherited:

| Premise | Method | Verdict |
|---|---|---|
| #7462 is OPEN | `gh issue view 7462 --json state` | HOLDS — OPEN, `closed_by: []` |
| G3's refusal is present on `origin/main` | `git show origin/main:scripts/cutover-inngest.sh \| grep 'G3 REFUSING'` | HOLDS — line 1047 |
| `soleur-inngest/prd` holds the prod DSN | value-silent sha256 of both secrets | HOLDS — byte-identical, `7968f3d658c2` |
| The dark slot should hold the soleur-dev DSN | ADR-100 addendum 2026-07-15 | HOLDS — soleur-dev, ref `mlwiodleouzwniehynfz` |
| A prior `op=arm` wrote it | `doppler configs logs -p soleur-inngest -c prd` | HOLDS — 3 writes in 1s by `inngest-cutover-arm`, 2026-07-23T15:46Z |
| `op=rollback` has no inverse for the DSN write | read of the rollback arm | HOLDS — writes `INNGEST_CUTOVER_FLIP`, deletes `INNGEST_HEARTBEAT_URL`, nothing restores the DSN |
| Terraform does not manage the DSN | enumerated `doppler_secret` resources in `inngest-host.tf` | HOLDS — TF seeds only `INNGEST_SIGNING_KEY`, `INNGEST_EVENT_KEY`, `INNGEST_REDIS_PASSWORD` |
| G4 is the only writer of that secret | `grep -rn INNGEST_POSTGRES_URI` across the repo | HOLDS — exactly one secret-write site |
| The soleur-dev co-tenancy defences are still live | `ls` of `0002_dev_inngest_tables_lockdown.sql`, `apply-inngest-rls-dev.yml` | HOLDS — both present, not retired |

One premise from the originating brief was **falsified** and is corrected here: #7462's runbook says a
diagnostic boot brings the host up against a *non-prod* `INNGEST_POSTGRES_URI`. It does not — it holds
the prod DSN, and has since 2026-07-23.

A second inherited claim was falsified and does not affect this plan's shape, but is recorded so it
stops propagating: the "~9-minute Better Stack ingestion lag" is not real. Measured per-row lag
(ingest `dt` minus journald source time) is 0–2 seconds.

### Property List (Phase 0.6b)

What the ask is actually for, stated as observable outcomes:

1. A cutover that was rolled back can be armed again without hand-editing configuration.
2. `op=arm` never arms the dedicated host onto a non-prod Postgres.
3. A refusal message names the condition that actually holds.
4. A change to G3's decision logic is caught before it ships.

### Cut List (Phase 0.6b)

| Mechanism considered | Property it would buy | Why cut |
|---|---|---|
| Restore the soleur-dev DSN into `soleur-inngest/prd` | (1) | A prod-config write that unblocks one run and leaves the asymmetry intact — the next rollback re-poisons G3. Also re-creates the soleur-dev co-tenancy ADR-100 wants retired. |
| Give `op=rollback` a true inverse (restore the dark DSN) | (1) | Buys (1) only by reintroducing the co-tenancy, and needs the dark DSN held as a new reference secret. Larger, and (1) is fully bought by idempotence. |
| Command seam in `op=arm` + behavioural harness | (4) | A cheaper mechanism buys the same property: extracting the decision into a pure function makes it directly testable **without** altering the prod-credential path. |

### Guard-precedent grep (repo convention)

`apps/web-platform/infra/inngest-cutover-flip.sh` — the sibling script in this same subsystem —
already uses injectable seams (`CUTOVER_FLAG_SET_CMD`, `CUTOVER_REDIS_CLI_CMD`,
`CUTOVER_SYSTEMCTL_CMD`, `CUTOVER_REDIS_DBSIZE`). That is the established precedent for making this
family of script testable. This plan takes the strictly smaller variant of it — a pure decision
function with no command seam — because G3's logic needs no I/O to be exercised.

### Applicable institutional learnings

- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` — directly
  applicable. All 256 assertions in `cutover-inngest-workflow.test.sh` are source-greps against the
  script text; every one is satisfiable by a stub. The existing `assert "arm) G3 refuses when prod ==
  dark"` greps for `PG.*==.*PG_DARK`, which will still match after this change even though the branch
  taken is now the opposite one. That assertion cannot see this plan's edit at all.
- `2026-05-05-defense-relaxation-must-name-new-ceiling.md` — this change relaxes a guard on a path
  whose terminal step is a `FLUSHALL`. The threat-surface enumeration it demands is in
  §Risks & Mitigations and is the load-bearing analysis of this plan.
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` — the
  mutation matrix below is written from the design, before the guard is edited.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Codebase reality | Plan response |
|---|---|---|
| G4 is at "~line 1088" | Confirmed — the `INNGEST_POSTGRES_URI` write is at 1088 | Use as-is |
| G3's equality refusal is at "line 1046-1048" | Confirmed on `origin/main` at 1046–1048 | Use as-is |
| The test file "asserts on the G4 write line and G3's fail-closed strings" | Confirmed — lines 445–447, 477, 479, 508–509 | All five updated or extended |
| Diagnostic boot uses a non-prod DSN (#7462 runbook) | False — holds the prod DSN | Correct the runbook premise in the ADR amendment |

## Infrastructure (IaC)

Phase 2.8 reviewed; **not applicable**. This plan introduces no server, service, cron, vendor account,
DNS record, certificate, secret, firewall rule, or monitoring webhook. It changes decision logic inside
an existing, already-automated, environment-gated workflow. The `INNGEST_POSTGRES_URI` write it guards
is pre-existing automation inside that workflow — this plan does not add it, and does not add any step
performed by a person. No `.tf` file is touched.

## User-Brand Impact

**If this lands broken, the user experiences:** a cutover that arms onto the wrong Postgres, whose
next FSM step is `FLUSHALL` against the host Redis. The prod cron queue is wiped, and scheduled work
— inbound-email processing, digests, reconciliation — silently stops firing until someone notices the
absence of an event rather than the presence of an error.

**If this leaks, the user's data is exposed via:** no new exposure vector. The change moves no secret
value and adds no logging of one; `INNGEST_POSTGRES_URI` remains masked and is never echoed.

**Brand-survival threshold:** single-user incident

## Guard Contract

### Guard 1 — G3 arm-decision (`g3_decide`)

**Property.** `op=arm` writes the production Inngest Postgres DSN into `soleur-inngest/prd` and never
arms the dedicated host onto a Postgres that is not the production inngest project.

**Assembly.** The chokepoint is a single pure function, `g3_decide`, taking the value to be written
and the value currently in place, and returning exactly one of `refuse-empty-dark`, `refuse-txn-pooler`,
`refuse-not-session-pooler`, `refuse-not-prod-project`, `skip-already-current`, `write`. The `arm)`
case must contain **exactly one** call site, and the function must be the only place these predicates
are evaluated — a second inline evaluation anywhere in the case is itself a contract violation and is
asserted against. This is structural: it is the set of paths the decision can be reached by, not the
list of predicates as they happen to be written today.

**Mutation matrix** — each row MUST drive the guard red.

| # | Mutation | Expected |
|---|---|---|
| 1 | Invert the equality arm (`write` when equal, `skip` when differing) | RED |
| 2 | Delete the prod project-ref pin (`*pigsfuxruiopinouvjwy*`) | RED — this is the load-bearing check once equality no longer refuses |
| 3 | Delete the empty-`PG_DARK` fail-closed arm | RED |
| 4 | Stub `g3_decide` to always echo `write` | RED — **own-dispatch row**: a guard that evaluates nothing must not pass |
| 5 | Add a second input pair after a compliant first, where the second must refuse | RED — **second-member row**: a check that stops after the first evaluation must not pass |
| 6 | Accept `:6543` (drop the transaction-pooler rejection) | RED |

**Harness rows.**

| # | Edit to the SUITE (not the guard) | Expected |
|---|---|---|
| H1 | Delete the assertion body so the suite asserts nothing | RED — the suite must fail its own dispatch floor, not report success on zero checks |
| H2 | **must-PASS, non-canonical:** a `PG_DARK` that is a *different* prod-project `:5432` DSN (differs only in password) | PASS with `write` — the contract permits any prod-project value here; a guard that rejects everything must not look green |

## Observability

```yaml
liveness_signal:
  what: op=arm emits exactly one ::notice:: or ::error:: naming the G3 outcome token
  cadence: per dispatch (manual, environment-gated)
  alert_target: the workflow run's own annotation surface
  configured_in: scripts/cutover-inngest.sh arm) case
error_reporting:
  destination: GitHub Actions ::error:: annotation; job exits non-zero
  fail_loud: true — every refusal arm exits 1; no arm returns success on an unevaluated decision
failure_modes:
  - mode: G3 skips the write when the value is NOT already current
    detection: g3_decide unit rows 1 and 4 in the mutation matrix
    alert_route: CI — cutover-inngest-workflow.test.sh fails the build
  - mode: G3 arms onto a non-prod Postgres
    detection: g3_decide unit rows 2 and 6
    alert_route: CI — build fails
  - mode: G3 passes on an unreadable dark value
    detection: g3_decide unit row 3
    alert_route: CI — build fails
logs:
  where: GitHub Actions run log for cutover-inngest.yml (value-silent; no DSN reaches it)
  retention: GitHub default
discoverability_test:
  command: bash apps/web-platform/infra/cutover-inngest-workflow.test.sh
  expected_output: all assertions pass, with a non-zero assertion count reported
```

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-100** (`ADR-100-inngest-dedicated-single-host-singleton-control-plane.md`). Its 2026-07-15
addendum already states the consequence of this defect — *"no code path restores the dark DSN"* — but
frames the prod DSN in the dark slot as a transient condition that ends at cutover. After this change
that framing is wrong in a way that matters: the prod DSN in `soleur-inngest/prd` is the **documented
post-first-arm steady state**, and `op=arm` is idempotent over it. The amendment records:

- the arm is idempotent; a re-arm after a rollback is expected and supported;
- the equality of prod and dark values is a steady state, not drift to be corrected;
- the forward/reverse pair is deliberately asymmetric for this value, and why that is now safe
  (the flush hazard is held by the monotonic latch, not by G3);
- the falsified #7462 runbook premise about diagnostic boot.

No new ADR ordinal is claimed, so there is no ordinal-collision exposure.

### C4 views

No C4 impact. Checked against all three model files —
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` — for each category the
completeness mandate requires:

- **External human actors:** none added or changed. The change adds no correspondent, reviewer, or
  recipient; the approving reviewer on the `inngest-cutover` environment is an existing relationship.
- **External systems / vendors:** none added. Doppler, Supabase and the Inngest host are all already
  modelled; no new vendor edge.
- **Containers / data stores:** none added. The change writes no new store and moves no data; it only
  changes whether an existing write is performed.
- **Actor↔surface access relationships:** unchanged. No ownership, sharing, or permission boundary
  moves.

The change is confined to the decision logic of an existing control-plane script whose elements and
edges are already represented.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** A control-plane guard change on an irreversible prod path. The technical risk is
concentrated entirely in whether G3's equality check carries a safety role beyond the one it states;
that question is answered in §Risks & Mitigations against the FSM source rather than by reasoning.
No product, legal, marketing, finance, sales, support, or operations surface is touched — this changes
no user-facing behaviour, no data handling, and no vendor relationship.

Product is **not** relevant: the mechanical UI-surface override does not fire (no path in
`## Files to Edit` matches the UI-surface globs — the files are a shell script, a shell test, and two
markdown documents).

## Open Code-Review Overlap

None. All 64 open `code-review` issues were queried; none names `scripts/cutover-inngest.sh`,
`apps/web-platform/infra/cutover-inngest-workflow.test.sh`, or ADR-100.

## Implementation Phases

Phase order is load-bearing: the decision function's contract is established before any consumer or
test depends on it.

### Phase 1 — Extract the decision (contract first)

Add `g3_decide` to `scripts/cutover-inngest.sh` as a pure function above the `arm)` case. It takes the
prod value and the current dark value and echoes exactly one outcome token. It performs no I/O, reads
no globals, and echoes no input value. Ordering of predicates is preserved from the current G3 block:
empty-dark → `:6543` → `:5432` → prod project-ref → equality.

The only behavioural change is the equality arm: it returns `skip-already-current` instead of
refusing.

**An empty prod value is not `g3_decide`'s concern.** G2 already refuses when the value read from
`prd_terraform` is empty or unreadable, before G3 is reached. The function may assume a non-empty prod
value; the suite does not need a row for it, and adding one would assert a condition the caller has
already excluded.

**The empty-dark fail-closed arm is retained, but its original rationale is now obsolete and must not
be restated as if it still applied.** It was introduced because an empty dark value would make the
equality comparison false and *silently pass* — that specific failure cannot occur once the equality
arm no longer gates anything. The arm is kept on a different and still-valid ground: G1 has already
proven the config readable, so an empty read here is anomalous and most plausibly indicates a
token-scope or wrong-project fault. Refusing costs one dispatch; proceeding on an anomalous read is
how a surprise gets armed. The comment in the code must be rewritten to the new rationale rather than
left asserting the old one.

### Phase 2 — Drive it red (tests before the consumer is rewired)

Add a unit block to `apps/web-platform/infra/cutover-inngest-workflow.test.sh` that sources the script
with a guard so only the function is defined, then exercises `g3_decide` directly across the mutation
matrix and harness rows. This block must fail against the Phase 1 function if any matrix row is
reverted, and must include an explicit floor asserting a non-zero number of `g3_decide` evaluations
ran — so a suite that evaluates nothing cannot report success.

### Phase 3 — Rewire the consumer

Replace the inline G3 block in the `arm)` case with a single `g3_decide` call and a `case` over its
outcome. Each refusal arm keeps its existing message text except the equality arm, which is replaced.
The `skip-already-current` arm emits a `::notice::` and sets a flag that Phase 4 reads.

Retain `::add-mask::` on the dark value, and keep every existing value-silence property: no arm echoes
an input.

### Phase 4 — Skip the redundant write

Guard the G4 secret-write call for `INNGEST_POSTGRES_URI` on the Phase 3 flag so it is not executed
when the value is already current. The `INNGEST_HEARTBEAT_URL` write and the G5
`INNGEST_CUTOVER_FLIP=armed` write are **unchanged** and still execute — only the redundant DSN write
is skipped.

### Phase 5 — Correct the false message

Replace the equality-arm text. The current message asserts arming "would flip onto the DARK backend",
which is false in the state that triggers it — the value is prod. The replacement states that the
target value is already in place and the write is being skipped.

### Phase 6 — Amend ADR-100

Apply the amendment described in §Architecture Decision.

## Files to Edit

- `scripts/cutover-inngest.sh` — add `g3_decide`; rewire the `arm)` case; guard the G4 write; replace the equality message.
- `apps/web-platform/infra/cutover-inngest-workflow.test.sh` — update assertions at 447, 479, 508–509; add the `g3_decide` unit block and its evaluation floor.
- `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md` — amendment.
- `knowledge-base/project/specs/feat-one-shot-7462-arm-idempotent-g3/tasks.md` — task breakdown.

## Files to Create

None.

## Acceptance Criteria

### Pre-merge (PR)

1. `g3_decide` exists in `scripts/cutover-inngest.sh` and echoes exactly one of the six outcome tokens for every input pair.
2. The `arm)` case contains **exactly one** `g3_decide` call site — asserted by an anchored count, not a bare token grep.
3. No G3 predicate is evaluated inline in the `arm)` case outside `g3_decide`.
4. Every mutation-matrix row (1–6) drives the suite red when applied, verified by applying each and observing failure.
5. Harness row H1 drives the suite red; harness row H2 passes with outcome `write`.
6. The G4 write of `INNGEST_POSTGRES_URI` to `soleur-inngest/prd` is guarded so it does not run on `skip-already-current`.
7. The G5 `INNGEST_CUTOVER_FLIP=armed` write and the `INNGEST_HEARTBEAT_URL` write are reachable on the `skip-already-current` path — asserted, since skipping them would silently convert a successful arm into a no-op.
8. `::add-mask::` on the dark value is retained; the arm case echoes no input value (the existing AC-NOBODY assertion at line 423 still passes).
9. G1 and G3.5 are byte-unchanged — verified by diffing those regions against `origin/main`.
10. The G3.5-precedes-G4 ordering assertion (lines 507–509) still passes.
11. The equality-arm message no longer claims the arm "would flip onto the DARK backend".
12. ADR-100 carries the amendment, and its 2026-07-15 addendum no longer describes the prod-DSN-in-dark-slot state as drift.
13. `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` passes with a reported non-zero assertion count.
14. `bash scripts/lint-workflows.sh` passes.
15. The empty-dark arm's code comment states the retained rationale (anomalous read despite a G1-proven-readable config) and no longer asserts the obsolete one (that an empty value would silently pass the equality check).

### Post-merge

16. None. This change dispatches no cutover operation; re-attempting the cutover is a separate, environment-gated step outside this plan's scope.

## Test Scenarios

Every scenario drives `g3_decide` directly — no scenario depends on network, live credentials, or a
live host.

| # | `PG` (to write) | `PG_DARK` (in place) | Expected outcome |
|---|---|---|---|
| 1 | prod-ref `:5432` | empty | `refuse-empty-dark` |
| 2 | `:6543` prod-ref | prod-ref `:5432` | `refuse-txn-pooler` |
| 3 | prod-ref, no port | prod-ref `:5432` | `refuse-not-session-pooler` |
| 4 | dev-ref `:5432` | dev-ref `:5432` | `refuse-not-prod-project` |
| 5 | prod-ref `:5432` | **identical** | `skip-already-current` ← the state that blocked 2026-08-20 |
| 6 | prod-ref `:5432` | dev-ref `:5432` | `write` ← the documented first-arm transition |
| 7 | prod-ref `:5432` | different prod-ref `:5432` | `write` ← harness row H2, must-PASS non-canonical |

Scenario 4 is load-bearing: it proves the prod project-ref pin still refuses a non-prod value **after**
the equality check stops refusing. It is the row that distinguishes this change from a weakening.

All fixture DSNs are synthesized, never real (`cq-test-fixtures-synthesized-only`).

## Risks & Mitigations

### The defense-relaxation analysis

G3's equality refusal is a load-bearing guard on a path that ends in `FLUSHALL`. Every threat surface
it currently bounds, and what holds each one after the change:

| Threat surface the equality check could be bounding | Held after the change by | Evidence |
|---|---|---|
| Arming onto the **dark** (non-prod) backend | The positive prod project-ref pin on the value being written | The dark backend is a *distinct Supabase project* (ADR-100 addendum) and cannot contain `pigsfuxruiopinouvjwy`. The pin is evaluated before the equality arm and is unchanged. |
| A **second `FLUSHALL`** wiping a live prod queue on re-arm | The monotonic latch, **not** G3 | `inngest-cutover-flip.sh:488-492` records the latch **at the flush, not at completion**, "because it … queue on the next re-arm", and is fatal if unrecordable. A durability gate at `:463-467` refuses to flush when the latch cannot be durably recorded. `already_flushed` short-circuits at `:400`. |
| Flushing a queue that is **already on prod** | The FSM's `flushed` state | `:18-19, 33-34` — a resume at `flushed` never re-flushes (the #5450 trap). |
| Flushing a **non-empty** Redis | The `DBSIZE==0` assert | `:17` — `armed`/`flipping` with `DBSIZE!=0` sets terminal `aborted` and exits 1 (P0-3). A failed DBSIZE query returns a non-numeric sentinel so the assert fails loud (`:330-337`). |
| Re-arming over an **in-flight or completed** flip | G1 | Unchanged by this plan, and asserted byte-identical (AC9). |
| A `done` inherited by a **replacement host** | The done-owner marker | `:240-312` (#7228), unchanged. |
| Detecting that the write **changes nothing** | The new `skip-already-current` notice | The one role genuinely unique to the equality check. It is preserved as information rather than as an abort. |

**Conclusion.** The equality check's only unique role is staleness *reporting*. Every safety role it
appears to serve is held by a different, unchanged mechanism — and in the case of the flush hazard, by
a mechanism (#7228 P0-5) built specifically because G3 could not hold it. The relaxation introduces no
uncovered surface.

**Residual risk.** The prod project-ref pin becomes the sole guard against arming onto a non-prod
Postgres. That concentration is the reason mutation-matrix row 2 and test scenario 4 exist, and why
row 2 is called out as load-bearing rather than routine.

### Other risks

| Risk | Mitigation |
|---|---|
| The existing `assert "arm) G3 refuses when prod == dark"` greps `PG.*==.*PG_DARK` and will still match after the change, silently certifying the opposite behaviour | AC4 requires each matrix row to actually drive the suite red; the assertion is rewritten to target the outcome token, not the presence of a comparison |
| Skipping the G4 write also skips the heartbeat or flag writes, turning a successful arm into a no-op | AC7 asserts both remain reachable on the skip path |
| The extraction accidentally changes predicate order | Phase 1 preserves the order explicitly; scenarios 1–4 pin each refusal to its own token, so a reordering changes which token is returned and fails |
| Scope creep into `op=rollback`'s missing inverse | Explicitly out of scope; the asymmetry is documented in the ADR amendment as deliberate and safe rather than fixed here |

## Out of Scope

- Dispatching any cutover operation. This plan ships code only.
- Restoring the soleur-dev DSN to `soleur-inngest/prd`.
- Adding a DSN-restoring inverse to `op=rollback`.
- Retiring the soleur-dev co-tenancy defences (`0002_dev_inngest_tables_lockdown.sql`, `apply-inngest-rls-dev.yml`); they remain live and correct while the cutover has not held.
