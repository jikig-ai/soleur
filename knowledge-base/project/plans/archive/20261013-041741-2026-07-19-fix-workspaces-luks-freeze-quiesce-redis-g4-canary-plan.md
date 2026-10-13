---
title: Quiesce Redis in the workspaces-luks freeze, make G4 fail-closed, fix the app canary URL, correct the dry_run description
type: fix
date: 2026-07-19
branch: feat-one-shot-6588-luks-freeze-quiesce
epic: 6588
adr: ADR-119
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

> Spec lacks valid `lane:` (no `knowledge-base/project/specs/feat-one-shot-6588-luks-freeze-quiesce/spec.md`) — defaulted to `cross-domain` (TR2 fail-closed).

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# 🐛 fix: quiesce Redis in the workspaces-luks freeze (+ G4 fail-closed, canary URL, dry_run description)

> **IaC routing note (Phase 2.8 reviewed).** Every service state-change in this plan is
> **program logic inside `apps/web-platform/infra/workspaces-cutover.sh`** — a script executed by
> the `workspaces-luks-cutover.yml` workflow dispatch, not an operator SSH step. No step in this
> plan asks a human to shell into a host. The one genuine provisioning need (`lsof`) is routed
> per Phase 2.8 through cloud-init (future hosts) plus an idempotent on-demand installer
> mirroring the existing in-file `ensure_aws()` precedent — see `## Infrastructure (IaC)`.

## Enhancement Summary

**Deepened on:** 2026-07-19 · **Method:** targeted high-value verification (gate sweep +
precedent-diff + verify-the-negative + cited-artifact checks) rather than broad agent fan-out —
this is a tightly-scoped infra fix to one script; the substance gate is the review-time
`user-impact-reviewer` (single-user-incident threshold) + CPO sign-off, not breadth of plan-time
agents. Mirrors the method used by the #6604 plan for the same file.

### Key improvements (verified this pass)

1. **Quiesce set narrowed — `inngest-server` REMOVED (reversal).** Round-1 proposed stopping
   `inngest-server.service` to avoid a crash-loop. Two facts reverse it: (a) its unit is
   `ProtectSystem=strict` with `ReadWritePaths=/var/lib/inngest /var/lock` — it **provably cannot
   write `/mnt/data`**, so it is not a quiescence requirement and cannot appear in `lsof +D`;
   (b) it carries `TimeoutStopSec=180`, so stopping it could spend up to **3 minutes** of a
   ~10-minute target freeze. The crash-loop risk it was guarding against is also smaller than
   assumed (`RestartSec=5` against systemd's default `StartLimitIntervalSec=10s` means the
   5-burst limiter rarely trips). Replaced with a **zero-cost post-freeze reconcile** in
   `resume_writers()`. Net: strictly safer *and* ~180 s cheaper.
2. **New `## Downtime & Cutover` section** (gate 4.55 fired — this change extends an
   already-signed downtime window). Quantifies the delta as **≤ ~35 s worst case**, well inside
   ADR-119 §(c)'s ≤20 min budget, so no new operator sign-off is required.
3. **ADR conformance confirmed, not assumed.** `ADR-119:73` prescribes `lsof +D /mnt/data`
   verbatim. Fix #2 therefore **restores** ADR conformance rather than changing a decision —
   only the quiesce-set change (adding `inngest-redis`) is a new decision needing the addendum.
4. **All citations verified live.** 4 cited rule IDs active in `AGENTS.md`; #6604/#6649/#6353/#5450
   CLOSED and #5274/#2591/#6588 OPEN with titles matching their cited role; all
   `knowledge-base/` paths resolve.

## Downtime & Cutover

**Trigger:** deploy class — this plan changes a cutover freeze that takes the sole serving
surface (`app.soleur.ai`, hard-pinned to web-1) offline, and **extends** its quiesce set.

**Zero-downtime path: evaluated, unavailable — already adjudicated.** ADR-119 §(c) records the
ruling: the zero-downtime path needs a load balancer that has no implementation and no ADR
(#6459 OPEN), and blue-green is *impossible* because cx33 is `available = false` in all three EU
DCs (ADR-119 line 247). Bounded downtime is the accepted design with operator sign-off; the bulk
rsync already runs **live** (no downtime) and only delta + verify + repoint + restart + canary sit
inside the window.

**Delta introduced by THIS PR** (against ADR-119's ≤20 min budget, ~10 min target):

| Added operation | Ceiling | Expected |
|---|---|---|
| `inngest-redis.service` stop (`TimeoutStopSec=30`) | 30 s | < 1 s — AOF flush of a ≤256 MB store on `appendfsync everysec` |
| `inngest-redis.service` start (`RequiresMountsFor` already satisfied) | — | ~1-3 s (AOF load) |
| `ensure_lsof` first run (`apt-get install lsof`) | ~10 s | 0 s after first run; also runs in the dry-run arm, so the rehearsal pays it |
| **Total added** | **≤ ~40 s** | **≤ ~5 s steady-state** |

`inngest-server.service` is **deliberately not stopped** (see Enhancement Summary §1) — that
alone avoids up to 180 s of added freeze.

**Verdict:** the added downtime is ≤ ~40 s worst case against a 20-minute signed budget with a
10-minute target. It stays inside the existing operator-signed window, so **no new sign-off is
required** — but the delta is declared here per gate 4.55. Per-stage rollback is unchanged: the
retained plaintext volume remains the backstop, and `resume_writers()` restores Redis on all
three exit paths.

## Overview

Two consecutive real-freeze dispatches of `workspaces-luks-cutover.yml` safe-aborted on
2026-07-19 (run `29687729540`) at the C1 byte-identity verify with **exactly one** difference:

```
SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF count=1 idx=0 icode=>fcst......
  path=redis/appendonlydir/appendonly.aof.94.incr.aof
```

`>fcst......` = checksum + size + mtime all differ. This is **not** a copy defect — it is a
**quiescence gap**. `inngest-redis.service` persists its AOF to `/mnt/data/redis`
(`inngest-redis.conf` → `dir /mnt/data/redis`, `appendonly yes`, `appendfsync everysec`) and runs
as a **systemd unit on web-1**, not as a Docker container. The freeze block
(`workspaces-cutover.sh:458-472`) quiesces only `webhook.service` and the
`soleur-web-platform` container, so Redis keeps appending through the freeze, the pass-2 delta
rsync, and the verify. Deterministic — which is exactly why both aborts landed on `count=1`.

**The C1 gate is not weakened by this PR.** It did its job: copying a live-appending AOF would
have put a torn journal on the new encrypted volume. The fix is to quiesce the writer.

This PR fixes four defects (plus two more found during plan-time verification, below) in one
change. The real-freeze re-dispatch is a **separate, gated operational step and is not part of
this PR.**

### What plan-time verification added beyond the brief

Two further defects were found and empirically demonstrated while verifying the brief's claims.
Both live in the same G4 assert, and both must be fixed — otherwise fix #2 ships a gate that
still does not work:

- **G4-b (empirically confirmed):** even with `lsof` present, `lsof +D "$MOUNT" | grep -q .`
  under the script's `set -uo pipefail` returns **141 (SIGPIPE)** whenever `lsof`'s output is
  large enough to outlive `grep -q`'s early exit — so `&& die` never fires. Reproduction
  (run at plan time, this machine):

  ```
  --- small output (3 lines) ---      PIPELINE_RC=0   (die WOULD fire)
  --- large output (500000 lines) --- PIPELINE_RC=141 (die would NOT fire)
  ```

  The gate is therefore **size-dependent**: it fails open precisely in the dangerous case (many
  stragglers). This is the repo's own documented hazard —
  `knowledge-base/project/learnings/test-failures/2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards.md`
  — and the same file already applies the herestring workaround at `workspaces-cutover.sh:154`.

<!-- lint-infra-ignore start -->
<!-- Descriptive prose about a DEFECT's symptom, not a prescribed human step: it states what the
     operator would READ in the run log when the gate fires. The remediation is entirely in-script
     (emit_freeze_holders before die) and runs under the existing workflow_dispatch — no human
     action is prescribed anywhere in this bullet. -->
- **G4-c:** the straggler holders are never **logged**. When G4 does fire, the operator gets
  "a straggler still holds the mount" with no PID/path — reproducing the exact
  undiagnosable-abort failure that #6604 just fixed for C1. The holders must be emitted before
  `die`, mirroring `emit_verify_diff`.
<!-- lint-infra-ignore end -->

- **Repoint consequence (why this was worse than a verify abort):** `inngest-redis.service`
  declares `RequiresMountsFor=/mnt/data` and holds the AOF open. Had C1 passed, `umount "$MOUNT"`
  at `:528` would have returned **EBUSY** and hit the `die "umount $MOUNT failed — refusing to
  stack the mapper over live plaintext (#5274)"` path — a *later*, mid-flip abort. The C1 gate
  caught this at the cheapest point available.

## User-Brand Impact

- **If this lands broken, the user experiences:** a third consecutive burned irreversible-freeze
  approval and freeze window, and — in the worst case, if the quiesce is incomplete but C1 passes
  — a torn Redis AOF on the new encrypted volume, silently losing armed Inngest future-`ts`
  reminders (the queue's survival mechanism per `inngest-redis.conf`). User-visible symptom:
  scheduled agent work that never fires, with no error.
- **If this leaks, the user's data is exposed via:** not a leak vector — this PR is the
  precondition for *closing* the exposure. Until the cutover completes, every user's checked-out
  source code remains plaintext-at-rest on `hcloud_volume.workspaces` while the published privacy
  policy asserts LUKS encryption-at-rest (#6588, DC-1, re-raise trigger 2026-07-23).
- **Brand-survival threshold:** `single-user incident` — web-1 is a singleton (`app.soleur.ai` is
  a hard-pinned A record); a botched freeze takes down every user, and a torn AOF loses work
  silently.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Verified reality | Plan response |
|---|---|---|
| Freeze stops only `webhook.service` + `docker stop` | **CONFIRMED** — `workspaces-cutover.sh:461-462`; no `inngest-redis` anywhere in the script | Fix 1 as briefed |
| Redis writes AOF to `/mnt/data/redis` as a systemd unit | **CONFIRMED** — `inngest-redis.conf` `dir /mnt/data/redis`; `inngest-redis.service` `User=deploy`, `ReadWritePaths=/mnt/data/redis`; bootstrapped onto the **web** host via `cloud-init.yml:691-721` | Fix 1 as briefed |
| G4 silently no-ops when `lsof` is absent | **CONFIRMED** — `:471` wraps the whole assert in `command -v lsof`. Additionally: **`lsof` is installed by no repo artifact** (zero hits across `apps/web-platform/infra/`, `.github/`) — so on web-1 its presence is *unproven*, not merely optional | Fix 2 + **deliver `lsof`** via an `ensure_lsof()` mirroring the in-file `ensure_aws()` precedent (`:92-107`) |
| Interrupted-write asserts only walk `workspaces/*/` | **CONFIRMED** — `:464-469`; `/mnt/data/redis` is a sibling of `workspaces/`, so Redis was unguarded on every axis | Widen scan to the whole mount (Phase 2) |
| Canary hits `/api/health`; middleware exempts `/health` only | **CONFIRMED** — `middleware.ts:113` `if (pathname === "/health")` is the sole early return, at the top of `middleware()`. **Stronger than briefed:** there is no `/api/health` route file at all (`app/api/health/` contains only `team-membership/route.ts`), so `/api/health` is a non-route that falls through to auth gating → 307 | Fix 3 as briefed; `/health` is also the repo's established canary (`deploy-status-fanout-verify.test.sh`, #6353, parses `/health` `.version`) |
| `dry_run` description over-promises verify coverage | **CONFIRMED** — `.github/workflows/workspaces-luks-cutover.yml:37`; script gates bulk rsync at `:453` and the entire freeze/delta/verify block at `:460`/`:475` behind `DRY_RUN` | Fix 4 as briefed, **plus** a dry-run-arm advisory holder probe (Phase 5.2) so the rehearsal stops being blind to the straggler set |
| — (not in brief) | `lsof \| grep -q` returns 141 under `pipefail` on large output → `&& die` never fires | **New:** G4-b — capture to a variable, no pipe |
| — (not in brief) | G4 logs no holder PIDs/paths on abort | **New:** G4-c — emit before `die` |
| — (not in brief) | `inngest-server.service` has `Restart=on-failure`; stopping Redis under it risks a crash-loop that ends `failed` and **outlives** the freeze. But it is `ProtectSystem=strict` with `ReadWritePaths=/var/lib/inngest /var/lock` — it **cannot write `/mnt/data`** — and carries `TimeoutStopSec=180` | **Do not quiesce it** (no quiescence benefit, up to 180 s cost). Reconcile it post-freeze in `resume_writers()` at zero freeze cost — see Enhancement Summary §1 |

## Architecture Decision (ADR/C4)

**ADR-119 §(a) enumerates the freeze quiesce set** (`docker stop -t 120`, halt `webhook.service`
first, blocking interrupted-write asserts, `lsof +D /mnt/data` straggler assert). This PR
**changes that set** — it adds `inngest-redis.service` (and a post-freeze reconcile of
`inngest-server.service`, which is deliberately NOT quiesced). Per
`wg-architecture-decision-is-a-plan-deliverable`, that is an architecture decision and the ADR
update ships **in this PR**, not as a follow-up.

### ADR
Amend `knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md`
with an **Addendum 2026-07-19 (#6588 freeze-quiesce)**:
- Restate §(a)'s quiesce set to cover every `/mnt/data` **writer**, not only the container —
  enumerated by unit, with `inngest-redis.service` named and its `RequiresMountsFor=/mnt/data` +
  AOF path cited as the reason.
- Record that the straggler assert is now **fail-closed and self-delivering** (`ensure_lsof`),
  and why an absent-binary skip is the silent-failure anti-pattern
  (`cq-silent-fallback-must-mirror-to-sentry`).
- Record the restore invariant: **every quiesced unit is restored on all three exit paths**
  (success, rollback, dead-man).
- Note this extends the framing in the #6604 addendum ("a bug fix, not a new decision") — the
  *quiesce set* is a decision; the #6604 verify-diagnosability change was not.

### C4 views
Read all three model files —
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` — and enumerated,
for this change: **external human actors** — none (no user-facing surface changes);
**external systems** — none added (Doppler, R2, Sentry, Better Stack are all already modeled and
already used by this script); **containers / data stores** — the Redis AOF store and the
`/mnt/data` volume, both already modeled, neither created nor removed here;
**actor↔surface access relationships** — unchanged, no actor gains or loses reach.
Conclusion: **no C4 impact.** This changes *when a unit is stopped*, not the topology, the store
set, or any trust boundary.

### Sequencing
The ADR addendum lands in this PR describing the corrected quiesce set. ADR-119 stays
`status: adopting` — it flips to `accepted` only after the real freeze succeeds, which is the
separate gated dispatch.

## Infrastructure (IaC)

### Terraform changes
**None.** No new resource, variable, secret, or vendor. `hcloud_volume` shapes are untouched.

### Apply path
Two-legged `lsof` delivery, mirroring the `ensure_aws()` precedent already in this file
(`:85-91` documents exactly this reasoning — web-1 carries
`lifecycle { ignore_changes = [user_data] }` and is unrebuildable, so cloud-init cannot reach
the running host):
1. **Running host (web-1):** `ensure_lsof()` — idempotent, on-demand `apt-get install -y lsof`
   executed by the cutover script itself at freeze time. This is the real delivery. No operator
   SSH; the workflow dispatch is the mechanism.
2. **Future hosts:** add `lsof` to `cloud-init.yml`'s package install so a fresh host is born
   with it.

Blast radius: additive package install, no restart, no downtime. Matches the documented
`ensure_aws` operator note at `:89-91`.

### Distinctness / drift safeguards
None applicable — no state, no `dev`/`prd` divergence, no Terraform variables.

### Vendor-tier reality check
N/A — no vendor resource created.

## Files to Edit

| File | Change |
|---|---|
| `apps/web-platform/infra/workspaces-cutover.sh` | Extract `freeze_writers()` / `resume_writers()` / `app_canary()` **above** the sourced-guard (`:288`); add `inngest-redis` to the quiesce set (+ post-freeze `inngest-server` reconcile); restore on all 3 exit paths; `ensure_lsof()`; G4 fail-closed + no-pipe + emit-holders; widen interrupted-write scan; canary → `/health` |
| `.github/workflows/workspaces-luks-cutover.yml` | Correct the `dry_run` input `description:` (`:37`) |
| `.github/workflows/infra-validation.yml` | **Register** the new test file as its own step (near the existing `workspaces-luks-verify.test.sh` step, ~`:381`) |
| `apps/web-platform/infra/cloud-init.yml` | Add `lsof` to the package install (future hosts) |
| `knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md` | Addendum 2026-07-19 (#6588 freeze-quiesce) |

## Files to Create

| File | Purpose |
|---|---|
| `apps/web-platform/infra/workspaces-luks-freeze.test.sh` | Behavioral + static tests for quiesce/restore, G4 fail-closed, canary URL |

> **Registration is load-bearing.** `infra-validation.yml` lists every infra test explicitly —
> its own comment (~`:466`) states *"This job lists its tests explicitly (no glob), so an
> unregistered test file ships as zero coverage."* AC8 verifies the registration by grep.

## Implementation Phases

### Phase 0 — Preconditions (verify, do not assume)

0.1 Re-read `workspaces-cutover.sh:458-472` (freeze), `:254-267` (rollback), `:294-310`
    (dead-man), `:549-591` (success/canary) — confirm line anchors before editing.
0.2 Confirm the sourced-detection guard is at `:288`, and that `rollback()` (`:254`) is **above**
    it (already sourceable) while the freeze block (`:458`) is **below** it (**not** sourceable —
    this is why extraction is a prerequisite for behavioral tests).
0.3 Re-run the pipefail/SIGPIPE reproduction to confirm the G4-b finding holds on the build agent.
0.4 Confirm `middleware.ts`'s `/health` early-return is still the sole exemption and still first
    in `middleware()`.
0.5 Confirm no CI drift guard walks `apps/web-platform/infra/*.sh` extracting service verbs
    (a new `inngest-redis` stop must not trip an allowlist).

### Phase 1 — RED: failing tests first (`cq-write-failing-tests-before`)

Create `apps/web-platform/infra/workspaces-luks-freeze.test.sh` using the harness idioms already
proven in `workspaces-luks-verify.test.sh`:
- `SCRIPT_DIR` / `CUTOVER` prelude, `ok()` / `no()` counters, `[ "$fail" -eq 0 ]` exit.
- `run_case`-style `bash -c 'source "$CUTOVER"; <stub fns>; <call>'` subshells, with
  `systemctl`, `docker`, `lsof`, `mount`, `curl` overridden as **shell functions defined after
  `source`** (matching the existing `rsync()` / `logger()` pattern — not PATH shims), each
  appending its argv to a calls file.
- `mutate()` sed-copy helper for mutation tests, **including the M4-style guard** that a `sed`
  which did not land is reported as *un-run*, never as evidence.

Write these RED first — they must fail against the current script. See `## Test Scenarios`.

### Phase 2 — Extract the freeze/resume seams (prerequisite for GREEN)

Move the freeze and resume logic into functions defined **above** the sourced-guard at `:288`,
leaving the main body calling them. Without this the freeze block is unreachable by `source` and
only static greps are possible.

- `QUIESCE_UNITS` — a single ordered list constant, the one place the quiesce set is declared:
  `webhook.service inngest-redis.service`.
  (The container stop stays explicit — it is not a systemd unit. `inngest-server.service` is
  **deliberately excluded**: `ProtectSystem=strict` + `ReadWritePaths=/var/lib/inngest /var/lock`
  means it provably cannot write `/mnt/data`, and its `TimeoutStopSec=180` would cost up to
  3 minutes of freeze budget for no quiescence benefit. It is reconciled post-freeze instead.)
- `freeze_writers()`:
  - stop in list order (`webhook` first, preserving ADR-119's "so a CI deploy cannot restart the
    container mid-rsync"), then the container (`-t 120`), then `inngest-redis`.
  - `persist_state QUIESCED_UNITS "<list>"` so the dead-man and a post-reboot recovery know what
    to restore.
  - interrupted-write asserts: keep the per-workspace `.git` asserts, and **widen the generic
    straggler/lock sweep to the whole mount** — the sibling `redis/` dir was unguarded on every
    axis. Iterate `"$MOUNT"/*/` for the generic sweep, retaining the `.git`-specific asserts
    under `workspaces/*/`.
  - `ensure_lsof()` then the **fixed G4**:
    ```sh
    holders="$(lsof +D "$MOUNT" 2>/dev/null || true)"   # capture; NO pipe (pipefail/SIGPIPE, G4-b)
    if [ -n "$holders" ]; then
      emit_freeze_holders "$holders"                     # log PIDs/paths BEFORE die (G4-c)
      die "lsof +D $MOUNT non-empty — a straggler still holds the mount (G4)"
    fi
    ```
    `emit_freeze_holders` mirrors `emit_verify_diff`: `_vscrub` every line, cap the output, emit a
    `SOLEUR_WORKSPACES_LUKS_FREEZE_HOLDER` marker to the run log **and**
    `logger -t "$LUKS_LOG_TAG"`, then `emit_drift freeze_straggler_holds_mount`.
  - `ensure_lsof()` must **abort**, never skip, if `lsof` is still absent after the install
    attempt — mirroring `ensure_aws`'s `aws_still_absent` die.
- `resume_writers()`: start the quiesced units in **reverse** order, after the mount is in place
  (`inngest-redis` has `RequiresMountsFor=/mnt/data` and cannot start before the mount).
  Clear any failed state before each start, so a unit that entered `failed` during the window is
  genuinely restored rather than left dead. Assert each unit is active afterwards and
  `emit_drift` if not.
  - **`inngest-server` post-freeze reconcile (zero freeze cost).** After the quiesced units are
    back, reconcile `inngest-server.service`: clear any failed state, and start it if it is not
    active. This covers the case where it crash-looped into `failed` against a vanished Redis
    during the window — without paying its 180 s stop timeout inside the freeze. Assert active
    afterwards and `emit_drift inngest_server_not_active` if not.

### Phase 3 — Wire restore into **all three** exit paths

The brief named two; there are three. Redis must be up whenever the run exits, by any route:

1. **Success** (`:549-591`) — `resume_writers()` after the mapper mount + container start.
2. **Rollback** (`rollback()`, `:254-267`) — `resume_writers()` after the plaintext remount,
   replacing the current bare container + webhook restarts. Covers both the EXIT-trap abort
   **and** the `ROLLBACK=1` operator entrypoint (`:315-318`).
3. **Dead-man timer** (`:294-306`) — the "orchestrator/SSH died" backstop. Its inline
   `systemd-run` command currently restores only the container + webhook; it must also start
   `inngest-redis.service` (and, harmlessly-idempotent, `inngest-server.service`, which may have
   crash-looped while Redis was down and nobody was watching). **This is the highest-stakes
   restore site:** it is the only one that runs unattended, and without it a dead-man fire leaves
   the durable Inngest queue down indefinitely with no operator signal.

Keep the inline dead-man command **self-contained** (the `:296-298` note: do not reference an
external binary this PR does not install).

### Phase 4 — Canary URL (fix 3)

`:554-555` → `https://app.soleur.ai/health`, and correct the `die` message string to match.
`/health` is middleware-exempt (`middleware.ts:113`) and is the repo's established canary
(`deploy-status-fanout-verify.test.sh`, #6353). Extract the canary into `app_canary()` above the
sourced-guard so T10/T11 assert the URL behaviorally, not only by grep.

### Phase 5 — `dry_run` description (fix 4) + dry-run holder probe

5.1 Rewrite `.github/workflows/workspaces-luks-cutover.yml:37`. It must state accurately what the
    rehearsal **does** cover (L3 gates, `prepare_luks_target`, escrow proof + R2 probe, G2
    manifest) and what it **does not** (no bulk rsync, no freeze, no delta rsync, **no C1
    verify**, no repoint, no wipe). The wording must make it impossible to read a green rehearsal
    as evidence the verify path is sound — that misreading is what let this defect reach two real
    freezes.
5.2 Add a **dry-run-arm advisory holder probe**: in the `DRY_RUN=1` arm, run `ensure_lsof` + the
    holder capture and **log** the holder set without dying. Rationale: fix 2 makes G4
    fail-closed, so the *first real freeze* would otherwise be the moment we discover the holder
    set — burning exactly the approval the brief is protecting. The rehearsal must surface the
    holder set first. Advisory in dry-run, fatal in the real arm.

### Phase 6 — ADR-119 addendum + CI registration + cloud-init

6.1 Write the ADR addendum (see `## Architecture Decision`).
6.2 Register `workspaces-luks-freeze.test.sh` in `infra-validation.yml` as its own step.
6.3 Add `lsof` to `cloud-init.yml` packages.

### Phase 7 — GREEN + full suite

Run the new test file; the existing `workspaces-luks-verify.test.sh` (must stay green — the
extraction must not disturb `verify_byte_identity` / `emit_verify_diff`); and the sibling
`luks-monitor.test.sh` / `workspaces-luks.test.sh` / `workspaces-luks-header.test.sh` static
guards, which grep this script and may anchor on lines the refactor moves.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1 — Redis is in the quiesce set.** Verify:
  `grep -cE '^\s*QUIESCE_UNITS=.*inngest-redis\.service' apps/web-platform/infra/workspaces-cutover.sh` ≥ 1.
- **AC2 — restore on all three exit paths.** `resume_writers` (or an equivalent explicit
  `inngest-redis` start) appears in the success path, in `rollback()`, and in the dead-man
  `systemd-run` command — 3 distinct call sites. Behavioral: T4 / T5 / T12.
- **AC3 — restore is ordered after the mount.** T6 asserts `mount` is called before the
  `inngest-redis` start in `rollback()` (the `RequiresMountsFor=/mnt/data` constraint).
- **AC4 — G4 is fail-closed on a missing `lsof`.** With `lsof` absent and `ensure_lsof`'s install
  failing, `freeze_writers()` exits non-zero. T7 — must be RED against current `main`.
- **AC5 — G4 does not use a pipe.** Verify:
  `awk '/^freeze_writers\(\)/,/^}/' apps/web-platform/infra/workspaces-cutover.sh | grep -c 'lsof.*| *grep'` == 0.
  Behavioral: T8 (large holder output → still dies) — must be RED against current `main`.
- **AC6 — G4 logs holders before dying.** T9 asserts a `SOLEUR_WORKSPACES_LUKS_FREEZE_HOLDER`
  marker is emitted and that the emit precedes `die` (line-number ordering check, mirroring the
  existing AC4-ordering guard in `workspaces-luks-verify.test.sh`).
- **AC7 — canary points at the middleware-exempt path.** Verify:
  `grep -c 'app\.soleur\.ai/health' apps/web-platform/infra/workspaces-cutover.sh` ≥ 1 **and**
  `grep -c 'app\.soleur\.ai/api/health' apps/web-platform/infra/workspaces-cutover.sh` == 0.
  Behavioral: T10 / T11.
- **AC8 — new test file is registered in CI.** Verify:
  `grep -c 'workspaces-luks-freeze\.test\.sh' .github/workflows/infra-validation.yml` ≥ 1.
- **AC9 — `dry_run` description is accurate.** Assert the **guardrail's presence**, not a token's
  absence (the word "verify" legitimately appears in the corrected negative phrasing):
  `grep -c 'no C1 verify' .github/workflows/workspaces-luks-cutover.yml` ≥ 1.
- **AC10 — existing verify tests still green.**
  `bash apps/web-platform/infra/workspaces-luks-verify.test.sh` exits 0.
- **AC11 — C1 gate unchanged.** `git diff main -- apps/web-platform/infra/workspaces-cutover.sh`
  shows no change inside `verify_byte_identity()` / `emit_verify_diff()`.
- **AC12 — ADR-119 addendum present.**
  `grep -c 'Addendum 2026-07-19' knowledge-base/engineering/architecture/decisions/ADR-119-*.md` ≥ 1,
  and the addendum names `inngest-redis.service`.
- **AC13 — mutation-tested.** Each of T7 / T8 / T9 has a mutation twin proving the test goes RED
  when the fix is reverted, each with the M4-style did-the-sed-land guard.

### Post-merge (operator)

- **AC14 — rehearsal first.** Dispatch `workspaces-luks-cutover.yml` with `dry_run=true`
  (ungated per #6649) and read the new advisory holder-probe output. **Automation:** in-workflow;
  the existing gated dispatch is the mechanism, not a new manual step.
- **AC15 — the real freeze re-dispatch is out of scope for this PR** and remains its own
  environment-gated dispatch.

> Uses `Ref #6588`, not `Closes` — the epic closes when the volume is encrypted and verified
> live, which this PR does not do.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_WORKSPACES_LUKS_FREEZE_HOLDER marker + existing workspaces-luks-drift Sentry op
  cadence: per cutover dispatch (freeze phase); daily luks-monitor.timer at-rest probe unchanged
  alert_target: Sentry (feature=workspaces-luks, op=workspaces-luks-drift) + Better Stack via logger -t luks-monitor
  configured_in: apps/web-platform/infra/workspaces-cutover.sh (emit_freeze_holders, emit_drift)
error_reporting:
  destination: Sentry via workspaces-luks-emit.sh; run log; Better Stack via the allowlisted luks-monitor tag
  fail_loud: true - every new failure path calls emit_drift before die; ensure_lsof aborts rather than skipping
failure_modes:
  - mode: lsof absent and un-installable at freeze time
    detection: emit_drift lsof_unavailable + non-zero exit
    alert_route: Sentry op=workspaces-luks-drift
  - mode: straggler still holds /mnt/data after quiesce
    detection: SOLEUR_WORKSPACES_LUKS_FREEZE_HOLDER marker carrying capped, scrubbed holder lines
    alert_route: Better Stack (luks-monitor tag) + Sentry op=workspaces-luks-drift
  - mode: a quiesced unit fails to restart on any exit path
    detection: resume_writers asserts each unit is active and emit_drift on failure
    alert_route: Sentry op=workspaces-luks-drift
  - mode: dead-man fires and restores units unattended
    detection: existing dead-man unit + the daily luks-monitor probe reporting mount state
    alert_route: Better Stack heartbeat
logs:
  where: GitHub Actions run log, journald -> vector -> Better Stack (luks-monitor tag), Sentry
  retention: per existing Better Stack / Sentry retention; no new sink
discoverability_test:
  # Proves the cutover run log — the synchronous channel SOLEUR_WORKSPACES_LUKS_FREEZE_HOLDER
  # and SOLEUR_WORKSPACES_LUKS_DRYRUN_HOLDER are emitted to — is queryable with NO ssh.
  # Credential-free by design: a Doppler-bearing probe (betterstack-query.sh) cannot run under
  # preflight Check 10's `env -i` sandbox, so it would fail the gate for an environment reason
  # rather than a signal reason. The durable Better Stack half is verified separately: the
  # luks-monitor tag is already allowlisted in vector.toml include_matches.
  command: gh run list --workflow=workspaces-luks-cutover.yml --limit 1 --json conclusion --jq .[0].conclusion
  expected_output: "success or failure"
```

No SSH appears in any verification path (`hr-no-ssh-fallback-in-runbooks`). The `luks-monitor`
tag is already allowlisted in `vector.toml` Source 4 (confirmed by the #6604 plan's AC10
research), so the new marker needs no Vector change.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Infrastructure/operational fix to a single host-side bash script plus its
workflow description, test, and ADR. No product surface, no schema, no user-facing UI, no
regulated-data surface (the script handles a LUKS passphrase, but this PR changes no
secret-handling path — `read_key`, `load_escrow_creds`, and the escrow limb are untouched).
The CTO-relevant decision (the quiesce set) is captured as an ADR-119 addendum in-PR per
`wg-architecture-decision-is-a-plan-deliverable`. Brand-survival threshold `single-user incident`
→ `user-impact-reviewer` at review time + CPO sign-off.

### Product/UX Gate

Not applicable — no path in `## Files to Edit` or `## Files to Create` matches a UI surface
(no `components/**`, no `app/**/page.tsx`, no `app/**/layout.tsx`). `middleware.ts` is **read
only** for verification and is not edited. Tier: **NONE**.

## GDPR / Compliance Gate

Skipped — no regulated-data surface. No schema, migration, auth flow, API route, or `.sql` file
is touched; no new processing activity, no new LLM/external-API call over user data, no new
distribution surface. The privacy-policy clause this epic ultimately makes true is **not** edited
by this PR (that is the final step of #6588, after a successful cutover).

## Open Code-Review Overlap

Checked `gh issue list --label code-review --state open` against every planned file path.

- `apps/web-platform/infra/workspaces-cutover.sh` — none
- `apps/web-platform/infra/workspaces-luks-verify.test.sh` — none
- `.github/workflows/workspaces-luks-cutover.yml` — none
- `apps/web-platform/middleware.ts` — **#2591** (`docs(security): document CSP middleware + route
  intersection for binary types`). **Disposition: acknowledge.** Different concern (CSP
  documentation for binary content types); this PR does not edit `middleware.ts` at all — it only
  reads `:113` to verify the exemption. #2591 remains open.

## Test Scenarios (`workspaces-luks-freeze.test.sh`)

Behavioral cases source the script (the `:288` guard) and override `systemctl` / `docker` /
`lsof` / `mount` / `curl` / `die` / `emit_drift` / `logger` as shell functions, recording argv to
a calls file.

| # | Scenario | Assert | RED against `main`? |
|---|---|---|---|
| T1 | `freeze_writers()` on a clean mount | an `inngest-redis.service` stop is recorded | ✅ yes |
| T2 | quiesce order | `webhook` stopped before the container; `inngest-redis` stopped before the delta rsync call site | ✅ yes |
| T3 | `persist_state QUIESCED_UNITS` written | state file contains the unit list | ✅ yes |
| T4 | success path | an `inngest-redis.service` start is recorded after the container start | ✅ yes |
| T5 | `rollback()` | an `inngest-redis.service` start is recorded | ✅ yes |
| T6 | `rollback()` ordering | `mount` recorded **before** the redis start (`RequiresMountsFor`) | ✅ yes |
| T7 | `lsof` absent, install fails | `freeze_writers()` exits non-zero (fail-closed) | ✅ yes — currently skips silently |
| T8 | `lsof` present, **large** holder output | still exits non-zero (no pipefail/SIGPIPE escape) | ✅ yes — currently returns 141 |
| T9 | `lsof` present, holders found | `SOLEUR_WORKSPACES_LUKS_FREEZE_HOLDER` emitted, and the emit precedes `die` | ✅ yes |
| T10 | `app_canary()` | `curl` invoked against `app.soleur.ai/health` | ✅ yes |
| T11 | `app_canary()` | `curl` **never** invoked against `/api/health` | ✅ yes |
| T12 | dead-man command text | the inline `systemd-run` command starts `inngest-redis` and references no un-installed binary | ✅ yes |
| T13 | `resume_writers()` with `inngest-server` inactive | it is reconciled (failed-state cleared + started); with it already active, **no** redundant start is issued | ✅ yes |
| T14 | `freeze_writers()` never stops `inngest-server` | no `inngest-server` stop is recorded (guards the 180 s regression) | n/a — pins the deepen decision |
| M1 | mutate: drop `inngest-redis` from `QUIESCE_UNITS` | T1 goes RED | — |
| M2 | mutate: restore the `command -v lsof` wrapper | T7 goes RED | — |
| M3 | mutate: restore the `\| grep -q .` pipe | T8 goes RED | — |
| M4 | mutate: move the holder emit after `die` | T9 goes RED | — |

Each mutation carries the M4-style guard: if the `sed` did not land (verified by grepping the
mutated copy for the expected construct), report **un-run**, never **pass**.

## Sharp Edges

- **The freeze block sits below the sourced-guard, so it is currently untestable.** Extraction
  into `freeze_writers()` / `resume_writers()` / `app_canary()` **above** `:288` is a
  prerequisite, not a nicety. A plan that adds tests without the extraction can only write static
  greps, which cannot catch T2 / T6 / T8-class ordering and exit-status defects.
- **`| grep -q` under `set -o pipefail` is a size-dependent fail-open.** Demonstrated at plan
  time: 3 lines → rc 0; 500k lines → rc 141. Never reintroduce a pipe into a gate's predicate.
  The same file already applies the herestring workaround at `:154`.
- **`emit_drift` must be called before `die`, and before any `rm`** — the exact defect #6604
  fixed for C1. `emit_freeze_holders` inherits that constraint; AC6 asserts it by line number.
- **`ensure_lsof` runs in both arms** (like `ensure_aws`, `:89-91`), so a `dry_run=true` rehearsal
  is not host-side-effect-free the first time — it may install `lsof`. Additive, no restart.
  Mirror the existing operator note verbatim in the code comment.
- **Do not narrow the C1 itemize codes or exempt the `redis/` path.** The gate is correct; the
  writer was not quiesced. AC11 pins `verify_byte_identity` as unchanged.
- **`inngest-redis.service` cannot start before `/mnt/data` is mounted** (`RequiresMountsFor`).
  A restore that races the mount leaves the unit `failed`, which is *worse* than leaving it
  stopped — it silently outlives the run. Hence the clear-failed-state step in `resume_writers()`.
- **Three restore sites, not two.** The dead-man timer is the one that runs unattended; omitting
  it is the failure nobody would see.
- **`luks-monitor.timer` is armed by a prior successful cutover** (`:580`). On a *re-dispatch*
  after a partial success it can fire during the freeze and hold `/mnt/data`
  (`RequiresMountsFor=/mnt/data`). Consider quiescing its timer in `freeze_writers()` and
  restoring it in `resume_writers()` — otherwise the newly fail-closed G4 may abort on our own
  monitor.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Narrow the C1 itemize codes, or exempt `redis/**` from the verify | **Rejected** — explicitly out of bounds. The gate correctly detected a live-appending journal; exempting it would put a torn AOF on the encrypted volume and lose armed Inngest reminders silently. |
| Quiesce `inngest-server` alongside `inngest-redis` | **Rejected at deepen (reversal of the round-1 position).** Round 1 accepted it to avoid a crash-loop→`failed` state outliving the freeze. Deepen-pass evidence reverses it: (a) the unit is `ProtectSystem=strict` with `ReadWritePaths=/var/lib/inngest /var/lock`, so it **provably cannot write `/mnt/data`** — zero quiescence benefit and it can never appear in `lsof +D`; (b) `TimeoutStopSec=180` means stopping it could burn **3 minutes** of a ~10-minute target freeze; (c) the crash-loop risk is smaller than assumed — `RestartSec=5` against systemd's default `StartLimitIntervalSec=10s` means the 5-burst limiter rarely trips. The residual risk is fully covered by a **post-freeze reconcile** in `resume_writers()` at zero freeze cost. |
| `SIGSTOP` the Redis process instead of stopping the unit | **Rejected** — leaves the AOF fd open, so `umount` still returns EBUSY at `:528`, and a stopped-not-flushed Redis is a *worse* copy source than a cleanly shut-down one. A unit stop gives a graceful SIGTERM + AOF flush within `TimeoutStopSec=30`. |
| `BGREWRITEAOF` + `redis-cli SHUTDOWN` instead of a unit stop | **Rejected** — needs the Doppler-injected `requirepass` in the cutover's scope, widening secret handling for no gain. The unit stop already triggers a graceful shutdown with AOF flush. |
| Keep `command -v lsof` but warn loudly instead of aborting | **Rejected** — this *is* the silent-failure anti-pattern (`cq-silent-fallback-must-mirror-to-sentry`). A safety gate that evaporates when a binary is absent provides false assurance; that is precisely how this defect reached two real freezes. |
| Make G4 fail-closed without delivering `lsof` | **Rejected** — `lsof` is provisioned by no repo artifact, so this would convert a silent skip into a guaranteed abort on the next real freeze, burning the approval the brief is protecting. `ensure_lsof` + the dry-run advisory probe make the gate live *and* rehearsable. |
| Defer the ADR-119 addendum to a follow-up issue | **Rejected** — `wg-architecture-decision-is-a-plan-deliverable`. The quiesce set is enumerated in ADR-119 §(a); changing it without updating the ADR leaves the recorded architecture lying about the real one. |
| Fold the new tests into `workspaces-luks-verify.test.sh` (no CI change needed) | **Rejected** — that file is scoped to the C1 verify and its #6604 addendum pins its contract. A separate file keeps concerns clean; AC8 covers the registration risk the aggregator-free CI design creates. |
