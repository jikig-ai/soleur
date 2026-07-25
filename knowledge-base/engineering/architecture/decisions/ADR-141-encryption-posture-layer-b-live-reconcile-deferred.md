---
title: Encryption-posture Layer B live reconcile is deferred until a host emitter gives the runner a real signal; the interim coverage guard lives in Layer A
status: adopting
date: 2026-07-24
related: [6902, 6588]
related_adrs: [ADR-140-encryption-posture-as-a-design-time-default, ADR-117, ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn, ADR-123, ADR-126]
blockers: [6894, 6895, 6897]
brand_survival_threshold: aggregate pattern
---

# ADR-141: Encryption-posture Layer B live reconcile is deferred; the interim coverage guard lives in Layer A

## Status

adopting

## Context

ADR-140 landed **Layer A** of the encryption-posture control: a design-time, hermetic
CI check (`scripts/lint-encryption-posture.py --repo-sweep`) that resolves every citation
in `scripts/encryption-posture-ledger.json` against real code. Issue #6902 asks for
**Layer B** — the *runtime* companion that reconciles the ledger's `live_verification:
available` rows against actual provider/host state, so a divergence between what the ledger
claims and what is live is detected out-of-band.

The measure-then-scope mandate required verifying measurable coverage **before** committing
to a design. Three facts, verified this session, determine the outcome:

1. **Coverage is 1 of 14 stores.** Exactly one store — `hcloud_volume.workspaces_luks` —
   carries `live_verification: available`; the other 13 are `unavailable:*`. Of the 6
   guest-LUKS `hcloud_volume` stores, only `workspaces_luks` is measurable (confirming the
   issue's "1 of 6").

2. **There is no runner-reachable live signal today (the load-bearing finding).**
   `lint-encryption-posture.py --json` emits the **committed ledger verbatim** and is
   **hermetic** (no network, no host, no SSH). So the ledger's `live_verification` field is
   a **static committed string, not a measured live signal**. The one measurable volume is
   `available` *because a HOST probe exists* (`apps/web-platform/infra/luks-monitor.sh`,
   daily: mount→mapper, `cryptsetup status`, `blkid` crypto_LUKS, Doppler escrow re-test,
   header UUID; Better Stack heartbeat + discriminating Sentry on drift) — the Hetzner API
   is blind to guest-side LUKS and SSH to the hosts is forbidden, so a CI-runner reconcile
   has **no independent signal** for guest-LUKS state. This is the **host-probe-vs-runner-
   reconcile distinction**: a signal a host emitter produces is not a signal a CI runner can
   reproduce; the runner can only observe the emitter's *liveness*, which
   `.github/workflows/scheduled-terraform-drift.yml`'s existing `heartbeat-live-reconcile`
   job already covers. Mirrors ADR-123 ("self-report, no self-converge") and ADR-126 ("cron
   liveness must assert the consumed artifact").

3. **A Layer B cron over `--json` would duplicate two existing detectors and add zero
   detection value.** `luks-monitor.sh` already deeply verifies the one measurable volume;
   `scheduled-terraform-drift.yml` already runs `terraform plan` store-inventory drift and
   carries a Sentry-cron-monitored live-reconcile job. A twice-daily job re-reading two
   static committed files (the ledger and its pinned constant) emits the identical verdict
   every run and, worse, degrades a **PR-time block** into an **hours-later email**. Building
   it now smuggles a design-time (Layer A) check into Layer B — a layering violation.

Provider-managed stores (R2/Supabase/Doppler/Better Stack) are **structurally never**
runner-live-reconcilable; #6896 (their attestation formalization) is CLOSED, yet those rows
correctly stay `unavailable` forever — so any future arm threshold must be phrased over
*runner-reconcilable* rows, never "all available."

## Decision

**Defer the Layer B live reconcile almost entirely** (the ADR-117 / #6901 measure-then-arm
pattern). Ship the durable decision (this ADR) plus a small, correctly-layered coverage
guard, and file a tracking issue for the armed reconcile:

1. **DEFER** the Layer B live-reconcile script, its cron job, and a dedicated
   `sentry_cron_monitor` — there is no runner-reachable live signal to reconcile today.
   When built (once a per-volume host emitter — #6894 / #6895 / #6897 — gives the runner a
   real signal), it **rides the existing `scheduled-terraform-drift.yml` job** (ADR-033
   single-substrate), NOT a new Inngest function or workflow.

2. **Add a Layer A live-coverage floor** to `scripts/lint-encryption-posture.py`: an
   optional top-level `live_coverage_floor` integer on the ledger. When `>= 1`, the sweep
   asserts the ledger retains at least that many stores whose `at_rest.live_verification ==
   "available"`. This blocks — at PR time, hermetically — the one coverage regression worth
   blocking: **zeroing out all live-measurable at-rest coverage**. It is a COUNT floor keyed
   on the ledger's own declared value, NOT an identity pin on `workspaces_luks`, so an honest
   individual re-ledgering (available → unavailable with a tracking issue) does not
   false-fail; only dropping below the floor does. The real ledger declares
   `live_coverage_floor: 1`; every synthesized fixture omits the field, so the floor no-ops
   for them and no existing test changes.

3. **Arm trigger.** Build the live reconcile only when an emitter (#6894 / #6895 / #6897)
   lands a runner-reachable signal for a store the runner cannot see today.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| **Full armed live reconcile now** (the issue's happy path) | 1 of 14 stores measurable; the one measurable row is host-probe-backed, not runner-reconcilable; `--json` is a static-file read. There is nothing live to reconcile from a CI runner. |
| **A disarmed cron skeleton over `--json`** | The `--json` read is a hermetic static-file (design-time) operation; a cron adds no detection value over a PR-time assertion and degrades PR-time blocking to hours-later email. This is the YAGNI finding all three deepen agents converged on. |
| **A new `cron-encryption-posture-reconcile.ts` Inngest fn + new `workflow_dispatch` workflow** | ADR-033 single-substrate: `scheduled-terraform-drift.yml` already IS that shape and carries a live-reconcile job. Ride it if/when the reconcile is built. |
| **A dedicated Sentry cron-monitor for the disarmed probe** | Moot with no cron; `sentry-monitor-iac-parity.test.ts` is workflow-step-granular and a monitor on a non-existent cron is inert. Lands with the armed reconcile. |
| **Coverage floor as a global `--repo-sweep` assertion (unconditional)** | Breaks the 7+ existing all-unavailable synthesized fixtures (TS-1/TS-5/TS-7/MB-12/…), which are 0-available by design; and provider-only ledgers legitimately have 0 available. Rejected. |
| **Coverage floor gated on the default-ledger path** (skip when `--ledger` overridden) | Not cleanly testable — exercising it requires placing a flipped ledger at the canonical path with `default_ledger=True`; copying to a temp forces `--ledger`, which disables the floor. Self-contradictory test strategy. Rejected. |
| **Coverage floor behind a new `--require-live-coverage` flag** | CI (#6901) runs bare `--repo-sweep`; the floor would never run by default unless the just-merged CI job is re-edited (scope creep into a shipped artifact). Rejected. |

The chosen mechanism (a ledger-intrinsic, data-declared `live_coverage_floor` integer) is
the CTO ruling: hermetic (reads a static committed integer, consistent with the
`--json`-is-static finding), leaves CI #6901's bare `--repo-sweep` unchanged, touches zero
fixtures, is single-cause testable, and is the literal expression of an `aggregate pattern`
invariant (a property of the store *set*, tunable to 2 when a second host-probe lands).

## Consequences

- Encryption-posture coverage cannot silently regress to zero live-measurable rows: a PR
  that drops the last `available` store without lowering `live_coverage_floor` fails the
  Layer A sweep, blocking merge. No new production runtime surface, cron, secret, or IaC is
  added.
- **Known weakness (honesty gate).** Unlike `check_positive_work_floor` — which derives its
  expected count from the `*.tf` scan so a deleted row cannot lower its own floor —
  `live_coverage_floor` is **self-declared and therefore gameable**: a commit that zeroes
  coverage can also lower the integer in the same diff and pass CI. This is acceptable for a
  measure-then-scope DEFER (the value change is visible in review), and the hardening —
  derive the required count from host-probe presence (scan for `luks-monitor.sh`-class
  probes and map to stores), mirroring the positive-work-floor's derive-from-code
  anti-gaming design — is recorded as the Layer B tracking issue's follow-up.
- The armed Layer B live reconcile remains available as scoped work the moment an emitter
  gives the runner a real signal; the tracking issue carries the recipe and the blockers
  (#6894 / #6895 / #6897).

## C4 impact

No `.c4` edit. No cron or monitor is added, so the `github -> sentry` relationship and its
edge counts in `model.c4` are unchanged; the ledger is a committed repo file, not a C4
container; the observed volumes are already modeled. When the deferred reconcile lands its
cron + monitor, THAT change updates the model.
