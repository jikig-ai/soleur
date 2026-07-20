---
title: "fix(infra): retry the LUKS app canary to a deadline, point verify at /health, and make verify assert readyz + workspace inventory"
issue: 6807
type: bug
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-07-21
branch: feat-one-shot-6807-luks-canary-verify-probes
plan_review: applied (5 agents + strong-model consult, 2026-07-21)
---

# fix(infra): retry the LUKS app canary to a deadline, point verify at `/health`, and make verify assert readiness **and inventory**

🐛 Three probe defects that made a **successful** `/workspaces` LUKS cutover report failure, plus the readiness coverage gap that leaves the live cutover's most important property unverified.

> `lane:` — no `spec.md` exists for this branch, so no lane could be carried forward. Defaulted to `cross-domain` (TR2 fail-closed).

## Overview

The live cutover on web-1 (run `29782780158`, 2026-07-20 22:10–22:14 UTC) **succeeded at the infrastructure level**: `/mnt/data` is `crypto_LUKS` on `/dev/mapper/workspaces`, escrow ok, header readable, and the C1 differential gate was clean (`phase=gate total=8 ok=7 preexisting=1 copy_corruption=0 src_only=0 src_missing_on_dst=0`, every workspace `dst_rc=0`). No rollback fired, correctly, because `CANARY_OK=1` was set by the host canary.

**This plan changes probe code only. It does not re-run, roll back, or otherwise touch the cutover.**

- **A — wrong endpoint (verify workflow).** `.github/workflows/workspaces-luks-verify.yml:103` asserts `https://app.soleur.ai/api/health == 200`. `/api/health` has no route; it 307s to `/login`. Observed live as `app /api/health=307`. The workflow is **structurally incapable of ever passing**, disabling the runbook's §5 gate.
- **B — single-shot probe racing container boot.** `workspaces-cutover.sh:663` probes `/health` ~590 ms after `docker start` and dies on Cloudflare's instant `521`. `--max-time 20` does not help: a 521 is a *fast* response, not a hang. `:665`'s readyz probe has the same shape.
- **C — the coverage gap (highest priority).** `/health` returns 200 **unconditionally** and never touches `$MOUNT` (`workspaces-cutover.sh:652-660`; `server/readiness.ts` states the no-mount-coupling invariant). `app_canary` died before reaching readyz, so **nothing off-host currently answers whether the repointed volume is serving user data**.

The load-bearing insight, from [`2026-07-19-the-harness-broke-the-rule-it-enforced-and-the-canary-could-not-fail.md`](../learnings/2026-07-19-the-harness-broke-the-rule-it-enforced-and-the-canary-could-not-fail.md) Key Insight 2: **the `/api/health` → `/health` swap alone is the documented-insufficient fix.** That learning already ruled `/health` architecturally incapable of reflecting the repointed mount.

### What `readyz` actually proves — and what it does not

Plan-review caught this plan committing the *same* overclaim one hop later. `server/readiness.ts:81`:

```ts
const workspaces_populated = countWorkspaceDirsAt(root) > 0;
```

`workspaces_populated` is **"at least one directory exists"** — a floor, not an inventory. `isWorkspacesWritable` (`:54-60`) write+unlinks **one** probe file at the root. So a cutover that preserved 1 of 8 workspaces passes `readyz`, passes `app_canary`, and would have passed a naively-worded acceptance while seven users' sole-copy source code was gone.

This plan therefore asserts **two** things, and says plainly which is which:

| Assertion | Proves |
| --- | --- |
| `readyz ready=true` | The mount is present, writable, and non-empty — a **floor** |
| `workspace_count == expected` | The **inventory** survived — the property the operator actually cares about |

The count is obtained host-side (a directory count over the existing SSH bridge), **not** from `readyz` — no app-code change. The cutover additionally persists its C1 `total` so future runs have a machine-checkable expected value; for the current host the expected value is `8`, from run `29782780158`.

## Research Reconciliation — Brief vs. Codebase

| Claim | Reality (verified) | Plan response |
| --- | --- | --- |
| "the canary-endpoint correction (merged **2026-06**)" | Landed **2026-07-19**, commit `ca85c30bc` / PR #6701. One day before the cutover. | Correct provenance used throughout. The one-day gap is *why* the sweep was thin. |
| Verify breakage "breaks the soak drift check" | **False.** `scripts/followthroughs/workspaces-luks-soak-6604.sh:46-66` reads Sentry drift events + heartbeat + ADR status directly; it never invokes the verify workflow. | Impact scoped to the runbook §5 gate only. No soak-script changes. |
| `/api/health` asserted-as-200 in several places | Exactly **one live assertion**: `workspaces-luks-verify.yml:103`. `/api/health/team-membership` **is** a real route. Other hits are prose, fixtures, the existing gates' own patterns, and `postmerge/SKILL.md:103` (which *warns against* `/api/health`). | Fix the one assertion + the workflow's prose. Extend the existing gate to two files — **not** a repo-wide gate (see Alternatives). |
| `workspaces-luks-verify.test.sh` covers the verify workflow | **False, and a naming trap.** It covers `verify_byte_identity` (the C1 differential). | No new suite: `workspaces-luks-freeze.test.sh:25` already carries a `WORKFLOW=` var and does comment-stripped workflow greps (`:316-325`). Add `VERIFY_WF=` beside it. |
| `luks-monitor.test.sh` can host behavioral readyz cases | **False.** It is a pure static grep suite (`have() { grep -qE … }`), no harness import, no PATH stubs, never executes the script. | New Phase 4 creates the execution seam. Without it, AC "flag unset ⇒ never probes" degrades to a grep that passes on dead code. |
| The DRY win is "reuse the existing readyz reason codes in `luks-monitor.sh`" | **False.** `grep -n readyz luks-monitor.sh` → nothing. Those codes exist only at `workspaces-cutover.sh:668,670`. The naive design **copies**, yielding two readyz + two retry implementations. | Extract the probe + classification into `workspaces-luks-emit.sh` — already sourced by **both** scripts and already in **both** tar lists (`verify.yml:94`, `cutover.yml:446`). Zero new sync obligations. |
| The Sentry envelope can carry the readyz discriminator | **False.** `workspaces-luks-emit.sh:62-73` hardcodes ten tags; none is readiness. `emit_drift` sets only `WL_REASON`, so all eight LUKS fields emit `unknown`. | `workspaces-luks-emit.sh` joins Files to Edit: add `WL_READYZ_WRITABLE` / `WL_READYZ_POPULATED` / `WL_WORKSPACE_COUNT`. |
| The Better Stack heartbeat is this plan's liveness signal | **False today.** `luks-monitor.sh:116` logs `WARN: WORKSPACES_LUKS_HEARTBEAT_URL absent`. That is #6808, deliberately not folded in. | Observability states the heartbeat is **unfed pending #6808** and names what actually pages (`hr-verify-repo-capability-claim-before-assert`). |
| A daily unconditional readyz assert would defend the reboot hazard | **False.** `luks-monitor.service:5` carries `RequiresMountsFor=/mnt/data`. In the ADR-119:234-240 hazard `/mnt/data` is not mounted, so the unit **never executes ExecStart**. | This is the real argument for the flag — see Alternatives. The verify workflow runs the script as a **bare file** (`verify.yml:98`), with no unit and no `RequiresMountsFor`, so the operator-dispatched path is the *only* one that can reach the check in that hazard. |
| A ~90 s canary window is "well inside" `DEAD_MAN_MIN=30` | **Understated ~5×.** Two probes × 30 × (`--max-time 5` + 3 s) ≈ 480 s, and the timer is armed at `:2128` (freeze), not at the canary. | Phase 0 measures remaining budget from run `29782780158`; Phase 2 caps **combined** canary spend. |
| `sleep` is stubbable in the freeze harness | **False** — not stubbed. A retry loop would make the at-budget CI job sleep for real. | Phase 3 adds a recording no-op stub, reusing the repo's `MOCK_SLEEP_NOOP` idiom (`ci-deploy.test.sh:699`, broadening tracked in #6665). |
| `model.c4` is accurate about the volume | **Stale as of 2026-07-20.** `:186` says `PLAINTEXT AT REST as of 2026-07-17`; `:410` says `plaintext at rest — ADR-119 in progress`. This plan is the first artifact to know otherwise. | Phase 7 corrects both descriptions (C4 completeness mandate: fix descriptions the change falsifies). |

## Proposed Solution

### 1. One shared, classifying, bounded probe helper

Lives in `workspaces-luks-emit.sh` (already sourced by `luks-monitor.sh:31` and the cutover, already in both tars). Sourced by both consumers — **one** implementation, not three.

**Classification is inverted from the naive design: enumerate the STRUCTURAL set; everything else is retryable.** Failing safe on unknowns matters because this path is behind a CF Tunnel:

- **Structural — fail fast, no retry:** `307, 401, 403, 404, 405, 525, 526`.
- **Retryable — everything else**, notably `000, 500, 502, 503, 504, 521, 522, 523, 524, 530`. `530` (CF error 1033, "tunnel connector not connected") is the code this stack most likely emits during a restart window; classifying it structural would reintroduce Bug B in a new coat. `500` is reachable from the custom server mid-boot.

**Bounded by attempts, not wall clock** — deterministic under a stubbed no-op `sleep`. A `date +%s` deadline with a no-op sleep spins hot for the full deadline in CI.

```bash
# 30 × 3s ≈ 90s tolerance per probe; --max-time 5 ⇒ worst case 30×8 = 240s per probe,
# 480s for both. Remaining DEAD_MAN_MIN budget at the canary is measured in Phase 0;
# Phase 2 caps COMBINED canary spend against it.
CANARY_ATTEMPTS="${WORKSPACES_CANARY_ATTEMPTS:-30}"
CANARY_INTERVAL_S="${WORKSPACES_CANARY_INTERVAL_S:-3}"
# `:-` handles empty. The actual silent-disable hazard is =0 (a zero-iteration loop
# passes trivially), which `:-` does NOT catch — hence the floor:
[ "$CANARY_ATTEMPTS" -ge 1 ] 2>/dev/null || CANARY_ATTEMPTS=1
```

> The `:-` rule is scoped to these two **new** knobs. `workspaces-luks-harness.sh:283` deliberately uses the unset form `${READYZ_BODY-…}` so `READYZ_BODY=""` exercises the unreachable arm — do not "normalise" it.

**readyz gets the same three-way classification**, not a two-way one. The existing `case` maps every non-`ready:true` body to `readyz_not_ready` ("serving an EMPTY /workspaces"). Under retry, a persistent non-JSON body (a 500 HTML page, a proxy error) would burn the budget and then emit a **confidently wrong data-loss verdict**. Three arms: `ready:true` / retryable-not-ready / **structural-unparseable** (a distinct reason code, not `readyz_not_ready`).

### 2. De-conflate the verdicts — at the exit code, not the log line

`luks-monitor.sh`'s `emit_and_die` always `exit 1`, and the workflow's `::error::` hard-codes the at-rest framing. Folding readyz in makes `probe_rc` a **three-way** collapse (LUKS drift / readiness / SSH transport `255` — the last of which tells the operator to read a Sentry event that was never emitted). An echo does not fix this. Therefore:

- Distinct exit codes from `luks-monitor.sh`: `1` = LUKS drift, `2` = readiness, and a `255` transport arm in the workflow.
- Distinct Sentry `op` for readiness (`workspaces-readiness-drift`) so the DP-8 alert does not page **"at-rest encryption drift"** for a container-readiness blip.

### 3. Positive control — the assertion must prove it ran

The flag is delivered through a triple-nested quoting hazard (`verify.yml:99`). If it is dropped or mangled, `luks-monitor.sh` exits 0 having never probed readyz and the workflow prints **PASSED** — byte-for-byte the failure shape being fixed. So:

- Deliver the flag via the `.env` that is already `set -a`-sourced, sidestepping the quoting nest.
- `luks-monitor.sh` emits a **mandatory machine-checkable verdict line** on the readyz-asserted success path.
- The workflow greps for that line and **fails on its absence** (assert-presence, not assert-no-error).

### Alternatives considered

| Option | Verdict |
| --- | --- |
| **Shared helper in `workspaces-luks-emit.sh`; readyz assert in `luks-monitor.sh` behind default-OFF `LUKS_MONITOR_ASSERT_READYZ`, set by verify (chosen)** | Only option delivering real DRY. Flag default-OFF is right for a reason the first draft never gave: `luks-monitor.service:5`'s `RequiresMountsFor=/mnt/data` means the daily unit **cannot run** in the reboot hazard, so default-ON buys no coverage there — while the bare-file verify path can. |
| Default-ON in the daily monitor | Rejected. The strong-model consult argued default-OFF "buys zero continuous coverage of the empty-mount hazard" — sound reasoning from a false premise: `RequiresMountsFor` makes the unit inert in exactly that hazard. Would also extend time-to-page by ~90 s on a genuine outage. |
| New `workspaces-readyz-probe.sh` | Rejected: requires keeping **two** tar lists in sync — the precise sibling-drift class that caused this issue. `workspaces-luks-emit.sh` is already in both. |
| Inline retry in the workflow's remote `bash -c` | Rejected: untestable, and duplicates the helper. |
| Repo-wide `/api/health`-as-200 CI gate | **Cut.** Review ran the proposed scope: six live *legitimate* hits remain (the existing gates' own patterns, fixtures, and `postmerge/SKILL.md:103` which documents the fix). It would red-light its own artifacts, and "as-200" is a proximity property a token grep cannot express. Replaced by extending the existing `AC7` grep from `$CUTOVER` to `$CUTOVER $VERIFY_WF` — same real-world coverage, one line. |
| New `workspaces-luks-verify-workflow.test.sh` | **Cut.** `workspaces-luks-freeze.test.sh:25` already greps a workflow file. The YAML-parse requirement was mis-imported from `workspaces-luks-cutover-workflow.test.sh:9-16`, whose stated reason is `${{ }}` **operand inversion** — which does not transfer to a URL literal in a `run:` block. |

**Deferred, tracked:** whether the daily probe should assert readyz once the mount is present. Framed correctly (not on the false-page axis): it would defend the **steady-state** writable/populated case only — the reboot hazard is covered structurally by `chattr +i` + the `RequiresMountsFor` drop-in and detected by container-start failure → Better Stack apex uptime.

## User-Brand Impact

- **If this lands broken, the user experiences:** a future `/workspaces` LUKS cutover certified green while the container serves an empty or **partially-populated** `/workspaces` — users' checked-out repositories missing from the dashboard and every agent session. Per `model.c4:186` these worktrees are **sole-copy**: `refs/checkpoints/*` is pushed by no refspec and signup-provisioned workspaces have no git remote. There is no second copy. (That same line is stale on encryption state; Phase 7 corrects it.)
- **If this leaks, the user's data is exposed via:** the verify workflow echoing a raw `/internal/readyz` body, or a raw workspace listing, into a GitHub Actions log. Workspace **directory names** are user-identifying. The count must be echoed as an integer; no listing, no names. The cutover path already scrubs via `_vscrub`; `workspaces-luks-emit.sh:33`'s `_wl_scrub` is the equivalent on the monitor path.
- **Brand-survival threshold:** `single-user incident`

## Observability

```yaml
liveness_signal:
  what: "Operator-dispatched workspaces-luks-verify.yml run (workflow_dispatch). NOTE: luks-monitor.sh's Better Stack heartbeat push is UNFED today — WORKSPACES_LUKS_HEARTBEAT_URL is absent (luks-monitor.sh:116); that is #6808 and is deliberately NOT fixed here."
  cadence: "on demand (workflow_dispatch); the daily luks-monitor.timer runs the LUKS asserts but not readyz (flag default-OFF)"
  alert_target: "What actually pages today: Sentry issue alert on feature=workspaces-luks (op=workspaces-luks-drift for at-rest, op=workspaces-readiness-drift for readiness), plus the Better Stack apex uptime monitor on app.soleur.ai. NOT the luks-monitor heartbeat (unfed, #6808)."
  configured_in: "apps/web-platform/infra/sentry/issue-alerts.tf; apps/web-platform/infra/luks-monitor.timer"
error_reporting:
  destination: "Sentry via workspaces-luks-emit.sh; ::error:: annotations in the verify workflow"
  fail_loud: true
failure_modes:
  - mode: "app /health never returns 200 within the retry budget"
    detection: "app_canary emit_drift health_probe_deadline + die carrying last_code, attempts_used, elapsed_s, class=deadline. NOTE class=deadline covers no-route/DNS (curl 000) as well as slow boot, so the message names both."
    alert_route: "Sentry op=workspaces-luks-drift; dead-man timer still armed (disarm_dead_man runs after app_canary)"
  - mode: "app /health returns a STRUCTURAL code (307/401/403/404/405/525/526) — endpoint regression"
    detection: "emit_drift health_probe_structural + die on the FIRST attempt, carrying last_code (no retry burn)"
    alert_route: "Sentry op=workspaces-luks-drift; verify workflow ::error:: with the same fields"
  - mode: "/internal/readyz unreachable for the whole budget"
    detection: "emit_drift readyz_unreachable"
    alert_route: "Sentry op=workspaces-readiness-drift"
  - mode: "/internal/readyz reports ready=false — mount not writable or empty"
    detection: "emit_drift readyz_not_ready carrying WL_READYZ_WRITABLE + WL_READYZ_POPULATED, discriminating WHICH check failed"
    alert_route: "Sentry op=workspaces-readiness-drift; luks-monitor exit 2; workflow ::error:: names readiness, not at-rest drift"
  - mode: "/internal/readyz returns an unparseable body (proxy error page, truncated response)"
    detection: "emit_drift readyz_unparseable — a DISTINCT reason from readyz_not_ready, so a proxy fault is never reported as data loss"
    alert_route: "Sentry op=workspaces-readiness-drift"
  - mode: "workspace INVENTORY shrank (count < expected) — readyz says ready=true because >0 dirs exist"
    detection: "host-side integer directory count compared against persisted WORKSPACES_COUNT; emit_drift workspace_count_shortfall carrying WL_WORKSPACE_COUNT and the expected value (integers only, never names)"
    alert_route: "Sentry op=workspaces-readiness-drift; workflow fails"
  - mode: "the readyz assertion silently never ran (flag lost in the quoting nest)"
    detection: "the mandatory verdict line is ABSENT from the run log; the workflow greps for it and fails on absence (positive control)"
    alert_route: "verify workflow ::error::; AC checks for the line, not merely for the absence of an error"
  - mode: "SSH/tunnel transport failure (rc=255) misreported as at-rest drift"
    detection: "explicit rc==255 arm in the workflow emitting a transport-specific ::error:: that does NOT point at a nonexistent Sentry event"
    alert_route: "verify workflow ::error::"
logs:
  where: "GitHub Actions run log (workspaces-luks-verify.yml); journald under SyslogIdentifier=luks-monitor, shipped by Vector to Better Stack Logs source 2457081"
  retention: "Better Stack Logs retention for source 2457081; GitHub Actions default run-log retention"
discoverability_test:
  command: "gh workflow run workspaces-luks-verify.yml --ref feat-one-shot-6807-luks-canary-verify-probes && gh run watch $(gh run list --workflow=workspaces-luks-verify.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
  expected_output: "conclusion=success, with the run log containing 'luks-monitor probe rc=0', 'app /health=200', and the mandatory verdict line 'SOLEUR_WORKSPACES_READYZ ready=true writable=true populated=true workspace_count=8'"
```

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-119** (`status: adopting`) — no new ADR; this extends a recorded decision to a second surface.

1. §(a) (`:155-162`): record that the reasoning binds the **off-host verify** surface too, that both probes are retry-bounded because `docker start` returns before Node listens, and — the substantive addition — that **`readyz` proves a floor, not an inventory** (`countWorkspaceDirsAt > 0`), so certifying a cutover requires a separate count assertion.
2. `:237`: the narrative says "container healthy, `/api/health` 200". `/api/health` 307s; the accurate endpoint for that hazard is `/health`.

### C4 views

**No structural C4 change — but two descriptions this change falsifies must be corrected** (the completeness mandate covers description correctness, not only elements/edges).

Enumerated against all three model files:

- **External human actors:** `founder = actor "Founder / Operator"` (`model.c4:8`) — already modelled.
- **External systems:** `github` (`:230`), `cloudflare` (`:234`) — modelled; the readyz probe rides the existing `github -> tunnel` edge (`:407`).
- **Containers / data stores:** `platform.infra.hetzner` (`:180`), `workspacesVolume` (`:186`) — modelled, with `hetzner -> workspacesVolume` (`:410`) already carrying the bind-mount relationship.
- **Access relationships:** none changed. No ownership or tenancy move.

**Corrections owned by Phase 7:** `:186` (`PLAINTEXT AT REST as of 2026-07-17`) and `:410` (`plaintext at rest — ADR-119 in progress`) are stale — the cutover landed 2026-07-20. This plan is the first artifact to know. Re-run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after editing.

## Implementation Phases

Dependency-directed. **Phase 2 is a hard gate: it answers the ground-truth question before any hardening is built.**

### Phase 0 — Preconditions (verify, do not assume)

1. Baseline green: `workspaces-luks-freeze.test.sh`, `luks-monitor.test.sh`, `workspaces-luks-verify.test.sh`.
2. Confirm `git grep -n 'sleep' workspaces-luks-harness.sh` is empty, and that `workspaces-cutover.sh` contains no `sleep` today (so an always-on recording stub is safe there).
3. Record the `deploy-script-tests` baseline duration (`infra-validation.yml:298`, `timeout-minutes: 12`; `ci-deploy.sh` alone ≈ 407 s) **and** the verify job budget (`verify.yml:38`, `timeout-minutes: 15`).
4. **Measure remaining dead-man budget at the canary** from run `29782780158`: time from `arm_dead_man` (`:2128`) to the canary step (`:2260`). `DEAD_MAN_MIN=30`. This bounds Phase 2's combined canary cap.
5. Read the `CANARY_OK` state-reload path (`:2246`, `cleanup()` `:721`) — confirm a re-dispatch cannot suppress `rollback()` via a stale `CANARY_OK`.

### Phase 1 — Shared probe helper in `workspaces-luks-emit.sh`

Add the bounded, classifying HTTP probe + the readyz three-way classifier. Extend the Sentry envelope with `WL_READYZ_WRITABLE`, `WL_READYZ_POPULATED`, `WL_WORKSPACE_COUNT` (additive; existing callers emit `unknown`). Scrub every value through `_wl_scrub`. Header note: this file is the shared leaf helper for the feature, not solely the emitter.

### Phase 2 — Ground-truth gate (probe first, ship nothing else until it answers)

1. Minimal edit to `.github/workflows/workspaces-luks-verify.yml`: `/api/health` → `/health`; set `LUKS_MONITOR_ASSERT_READYZ=1` **via the sourced `.env`**; add the host-side workspace count; emit the mandatory verdict line.
2. Minimal readyz assert in `luks-monitor.sh` behind the flag, using the Phase 1 helper.
3. **Dispatch pre-merge:** `gh workflow run workspaces-luks-verify.yml --ref feat-one-shot-6807-luks-canary-verify-probes`. This is feasible because the workflow already exists on the default branch (verified: `gh workflow list` → ID `315308438`).
4. **Record the verdict in this plan.** Expected: `ready=true`, `workspace_count=8` (matching run `29782780158`'s `total=8`).
5. **STOP CONDITION:** if `ready=false`, or the count is `< 8`, halt. This is then a **data-recovery incident on sole-copy data**, not a monitoring project, and every remaining phase is built against the wrong problem. Escalate; do not proceed.

### Phase 3 — Freeze harness: recording `sleep` stub + sequenced curl codes

- Recording no-op `sleep` (model: `nic-wait-gate.test.sh:71-82`), reconciled with the repo's existing `MOCK_SLEEP_NOOP` idiom (`ci-deploy.test.sh:699`; broadening tracked in #6665) rather than inventing a parallel mechanism.
- `CURL_CODES` sequenced knob mirroring `MOUNTPOINT_RCS` (`:173-181`), **with a per-endpoint index**: the stub's single `case "$*"` serves both `/health` and `*readyz*`, so one shared counter would be advanced by readyz calls and silently desynchronise the `/health` sequence. Separate index per arm, with an inline comment saying why.
- Document saturation semantics inline (`CURL_CODES="521"` ⇒ *always* 521) — the timeout-arm tests depend on it entirely.
- `READYZ_BODIES` is **not** added: readyz routes through the same Phase 1 helper, so its loop behaviour is already proven by `CURL_CODES`, and the existing scalar covers `T22b`/`T22c`. One source-level assertion that readyz calls the helper replaces it.

### Phase 4 — Execution seam for `luks-monitor.sh`

`luks-monitor.test.sh` is static-only. Create the runnable seam (extend `workspaces-luks-harness.sh` to source and run `luks-monitor.sh` under stubbed `curl`/`doppler`/`findmnt`/`cryptsetup`/`blkid`/`mountpoint`). Without this, "flag unset ⇒ readyz never probed" degrades to a grep that passes on dead code.

Pin the **heartbeat ordering** explicitly: the readyz assert runs **before** the heartbeat push (`luks-monitor.sh:109-117`), so a `ready=false` host does not push a healthy beat. Comment the reason — the opposite placement makes the absence-based liveness signal report healthy while the invariant is false.

### Phase 5 — `app_canary` retry (Bug B)

1. Both probes use the Phase 1 helper. Pin the loop shape (does it sleep after the final attempt?) — the ACs derive from it.
2. Add `emit_drift health_probe_deadline` / `health_probe_structural` to the `/health` arms, which today call bare `die` and emit nothing.
3. Cap **combined** canary spend against the Phase 0.4 measurement.
4. **Do not move `app_canary` relative to `disarm_dead_man`** (`:2256-2269`, defended by comment).
5. Persist the C1 `total` (`persist_state WORKSPACES_COUNT`) so future verifies have a machine-checkable expected inventory.

### Phase 6 — Tests (in existing suites)

`workspaces-luks-freeze.test.sh`: add `VERIFY_WF=` beside `:25`. Cases:

- **T23a** waits and recovers: `CURL_CODES="521 521 200"` ⇒ `ran` ∧ `1 ≤ sleeps < bound`.
- **T23b** structural fail-fast: `CURL_CODES="307"` ⇒ `died`, **zero** sleeps. (Bug A regression guard.)
- **T23c** retryable-unknown fails safe: `CURL_CODES="530"` ⇒ retried, not fast-failed.
- **T23d** timeout arm runs the full bound (count per the Phase 5 loop shape).
- **T23e** seam-unset: knobs **unset** ⇒ a never-recovering probe uses exactly the production attempt count.
- **T23f** attempts floor: `WORKSPACES_CANARY_ATTEMPTS=0` ⇒ still probes ≥ 1 time (never a trivial pass).
- **T24** readyz unparseable body ⇒ `readyz_unparseable`, **not** `readyz_not_ready`.
- **T25** ordering: `app_canary` precedes `disarm_dead_man` (comment-stripped index).
- **AC7 widened**: pattern `/api/health` (bare — `app.soleur.ai` appears on only one of the six sites), over `$CUTOVER $VERIFY_WF`, **not** comment-stripped for the workflow (its own comments are in scope for the edit), `/api/health/team-membership` allowlisted.

`luks-monitor.test.sh` (on the Phase 4 seam): flag unset ⇒ readyz never probed; flag set + `ready:false` ⇒ exit **2** + `readyz_not_ready`; verdict line present on success; `WORKSPACES_LUKS_HEARTBEAT_URL` not written by the cutover channel into `/etc/default/luks-monitor` (flag-leak guard).

Assertion hygiene: no `cmd | grep -q` under `pipefail` (141 fails OPEN on negatives); strip `^[[:space:]]*#` before body-greps (this PR's own comments contain both literals); never `[[ cond ]] && cmd` standalone under `set -e`.

### Phase 7 — Docs, model, tracking

1. Runbook §5: `/health` 200 + `readyz ready=true` + `workspace_count`. Record the **2026-07-20** landing and that §5 was non-functional until this fix. Add a **verdict → operator action triage table** covering every discriminating outcome (LUKS drift / readiness / count shortfall / structural / transport 255 / AC-fails-in-ship), since `hr-no-ssh-fallback-in-runbooks` forbids the usual escape hatch.
2. ADR-119: both edits above.
3. `model.c4:186` + `:410` staleness corrections; re-run the two C4 tests.
4. `workspaces-luks-verify.yml` header: it claims **"MUTATES NOTHING"** (`:3`, `:7`, `:84`), but `isWorkspacesWritable` write+unlinks a probe file at the workspaces root. Reword to "opens no device; the readyz probe write+unlinks one 0-byte file at the workspaces root."
5. File the deferred daily-readyz issue with the **corrected** framing (steady-state only; the reboot hazard is structurally covered).
6. Consider renaming the incumbent `workspaces-luks-verify.test.sh` (it covers `verify_byte_identity`) — the naming collision will mislead again.

## Files to Edit

| File | Change |
| --- | --- |
| `apps/web-platform/infra/workspaces-luks-emit.sh` | Shared probe helper + classifier; 3 new envelope fields |
| `apps/web-platform/infra/workspaces-luks-harness.sh` | Recording `sleep` stub; `CURL_CODES` with per-endpoint index; `luks-monitor.sh` execution seam |
| `apps/web-platform/infra/workspaces-cutover.sh` | `app_canary` via the helper; `emit_drift` on `/health` arms; combined cap; persist `WORKSPACES_COUNT` |
| `apps/web-platform/infra/luks-monitor.sh` | Flag-gated readyz assert (before the heartbeat push); exit 2; mandatory verdict line |
| `apps/web-platform/infra/luks-monitor.test.sh` | Behavioral cases on the new seam |
| `apps/web-platform/infra/workspaces-luks-freeze.test.sh` | `VERIFY_WF=`; T23a–f, T24, T25; widened AC7 |
| `.github/workflows/workspaces-luks-verify.yml` | `/health` + retry; flag via `.env`; count; verdict-line positive control; rc 255 arm; prose at `:3,6,7,84,102,104,110,113,160` |
| `knowledge-base/engineering/architecture/decisions/ADR-119-…md` | §(a) amendment (incl. floor-vs-inventory); `:237` |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | `:186`, `:410` staleness |
| `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md` | §5 endpoints + count; 2026-07-20 landing; verdict→action triage table |

## Files to Create

None. (The proposed new test suite was cut — see Alternatives.)

## Open Code-Review Overlap

`None.` Queried `gh issue list --label code-review --state open --limit 200` and matched every planned path. Zero hits.

## Acceptance Criteria

### Ground-truth gate (Phase 2, pre-merge)

- [ ] **AC1** A pre-merge `--ref` dispatch of `workspaces-luks-verify.yml` concludes `success` against the current already-cut-over web-1, and the run log contains the mandatory verdict line with `ready=true` **and** `workspace_count=8` (matching run `29782780158`'s `total=8`). *This is the acceptance that closes the issue's open question.*

### Pre-merge

- [ ] **AC2** Retry recovers through the loop: `CURL_CODES="521 521 200"` ⇒ canary succeeds ∧ `1 ≤ sleeps < bound`.
- [ ] **AC3** Structural fail-fast: `CURL_CODES="307"` ⇒ `died` with **zero** sleeps.
- [ ] **AC4** Retryable-unknown fails safe: `CURL_CODES="530"` ⇒ retried to the bound, not fast-failed.
- [ ] **AC5** Timeout arm runs the full bound (count derived from the Phase 5 loop shape, stated there).
- [ ] **AC6** Seam-unset: with both knobs unset, a never-recovering probe uses exactly the production attempt count.
- [ ] **AC7** Attempts floor: `WORKSPACES_CANARY_ATTEMPTS=0` still probes ≥ 1 time.
- [ ] **AC8** readyz classification is three-way: an unparseable body yields `readyz_unparseable`, never `readyz_not_ready`.
- [ ] **AC9** `app_canary` still precedes `disarm_dead_man`.
- [ ] **AC10** Widened AC7 gate: bare `/api/health` over `$CUTOVER $VERIFY_WF` returns zero live assertions, with `/api/health/team-membership` allowlisted — and the six prose sites in the workflow are all corrected.
- [ ] **AC11** Positive control: with the flag deliberately unset, the workflow **fails** (absence of the verdict line), proving a lost flag cannot produce a green run.
- [ ] **AC12** De-conflation: `luks-monitor.sh` exits `2` on a readiness failure (vs `1` for LUKS drift), the workflow branches on it, and rc `255` produces a transport-specific error that does not reference a nonexistent Sentry event.
- [ ] **AC13** Envelope fields: a `readyz_not_ready` emission carries `WL_READYZ_WRITABLE` and `WL_READYZ_POPULATED`; a count shortfall carries `WL_WORKSPACE_COUNT`.
- [ ] **AC14** Flag unset ⇒ `luks-monitor.sh` never probes readyz (asserted on the Phase 4 execution seam, not by grep), and the cutover channel writes no `LUKS_MONITOR_ASSERT_READYZ` into `/etc/default/luks-monitor`.
- [ ] **AC15** Log hygiene: the workflow echoes the workspace count as an **integer only** — no directory listing, no names — and the readyz body is scrubbed before any echo.
- [ ] **AC16** Suites green: `workspaces-luks-freeze`, `luks-monitor`, `workspaces-luks-verify` test scripts, plus the two C4 tests. `deploy-script-tests` duration is within 60 s of the Phase 0.3 baseline.
- [ ] **AC17** Docs: ADR-119 §(a) records floor-vs-inventory and `:237` is corrected; `model.c4:186`/`:410` no longer claim plaintext-at-rest; runbook §5 carries the endpoints, the 2026-07-20 landing, the non-functional note, and the verdict→action triage table.
- [ ] **AC18** `WORKSPACES_LUKS_HEARTBEAT_URL` appears nowhere in the diff (`git diff | grep -c` = 0) — #6808 stays out.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** Infrastructure probe-code fix on an already-provisioned surface. No new servers, services, secrets, vendors, or persistent runtime processes — the Phase 2.8 IaC gate does not fire; the edited scripts are delivered by the existing cutover/verify SSH channels, which tar the repo copy each run. Principal risks — testability (`sleep`-stub), CI budget, and cross-file drift — are addressed by the shared helper and the execution seam. The architectural decision is an **amendment** to ADR-119.

### Product/UX Gate

Not applicable. Product not relevant, and the mechanical UI-surface override does not fire: no path in Files to Edit matches `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or any UI-surface glob. Tier: `NONE`.

### GDPR / Compliance (Phase 2.7)

Invoked by trigger **(b)** — `single-user incident` threshold — not by the canonical regex.

**Assessment (advisory only; not legal advice):** `/internal/readyz` returns booleans; no personal data, no special-category data, no new processing activity, no lawful-basis change, no Art. 30 trigger. **Two actionable findings, both folded in and now AC-bound (AC15):** (1) the verify workflow must not dump a raw readyz body into an Actions log — the error arm can carry a message; (2) the new workspace-count assertion must echo an **integer only**, because workspace directory names are user-identifying and a listing would be a materially worse exposure than the original readyz body. No Critical findings; no `compliance-posture.md` write required.

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| Retry loop spins hot in CI | Bounded by **attempts**, not wall clock; `sleep` stubbed. |
| New tests tip `deploy-script-tests` past 12 min | Sleeps stubbed; Phase 0.3 baseline; AC16 uses a **60 s delta**, not an unfalsifiable "within budget". |
| Retry masks a permanent origin break (521/530 are "origin/connector unreachable", not inherently transient) | Bounded budget; verdict names `last_code` + `class`, and `class=deadline` prose covers no-route as well as slow boot. |
| Combined canary spend (~480 s worst case) collides with the dead-man timer | Phase 0.4 measures actual remaining budget from run `29782780158`; Phase 5.3 caps combined spend against it. |
| Implementation drift between probes | **One** helper in `workspaces-luks-emit.sh`, already in both tars. The workflow's runner-side `/health` loop is the only separate copy — it cannot share on-host code, and the Risks claim is scoped to that truth rather than overclaiming "both are suite-asserted". |
| A lost flag yields a silent green | AC11's positive control: the verdict line is mandatory and its **absence** fails the run. |
| Verify dispatched during a cutover reports scary false verdicts | Pre-existing (`verify.yml:21` uses a separate concurrency group); readyz widens the window. Noted for the deferred issue; a shared group is the fix if it recurs. |

## Sharp Edges

1. **`readyz` proves a floor, not an inventory.** `workspaces_populated` is `countWorkspaceDirsAt(root) > 0`. Never let prose (plan, ADR, runbook, PR body) imply `ready=true` means all workspaces survived. The count assertion is what carries that claim.
2. **A wall-clock retry deadline plus a stubbed no-op `sleep` spins hot for the full deadline.** Bound by attempts. This is why the harness phase precedes the retry phase.
3. **The harness `curl` stub serves both endpoints through one `case "$*"`.** A single sequence index would be advanced by readyz calls and silently desynchronise the `/health` sequence — the test would still pass. Index per endpoint arm.
4. **A retry test that only asserts "eventually 200" passes identically against a probe that never waits.** Assert the recorded sleeps, not just the outcome.
5. **A test-only override seam is a coverage hole disguised as a convenience.** If every test sets the attempt knob, emptying the production default stays green. AC6 is the companion; do not drop it as redundant.
6. **`luks-monitor.service:5`'s `RequiresMountsFor=/mnt/data` makes the daily unit inert in the reboot hazard.** Any future argument for flipping the flag default-ON must engage this, or it will re-derive a wrong answer from a plausible premise — as the strong-model consult did.
7. **`/usr/local/bin/luks-monitor` on the live host is stale** until the next cutover-channel `install` (`workspaces-cutover.sh:2271`). The verify workflow deliberately tars and runs the **repo** copy — the only reason the flag takes effect immediately. Do not "simplify" it to call the installed binary.
8. **`workspaces-luks-verify.test.sh` does not test the verify workflow** — it covers `verify_byte_identity`. Consider renaming it.
9. **This PR's own comments contain both `/health` and `/api/health`.** Strip `^[[:space:]]*#` before counting greps — except for the workflow file, whose own comments are in scope for the prose edit.
10. **Do not fold in #6808.** AC18 pins it.

## References

- Issue **#6807**; issue **#6808** (do not fold in).
- PR **#6701** / commit `ca85c30bc` (2026-07-19) — the correction whose sweep missed this workflow.
- Runs `29782780158` (successful cutover) and `29783424497` (verify failing on `app /api/health=307`).
- `knowledge-base/project/learnings/2026-07-19-the-harness-broke-the-rule-it-enforced-and-the-canary-could-not-fail.md`
- `knowledge-base/project/learnings/2026-07-20-i-swept-by-file-when-the-unit-of-truth-was-the-claim.md`
- `knowledge-base/project/learnings/2026-07-21-i-marked-one-block-and-not-its-twin-in-the-file-whose-purpose-was-removing-that-defect.md`
- `knowledge-base/project/learnings/2026-07-17-test-only-override-seam-leaves-prod-default-untested.md`
- `knowledge-base/project/learnings/best-practices/2026-07-18-deploy-script-tests-at-budget-timeout-and-infra-pr-ci-gotchas.md`
- `knowledge-base/project/learnings/2026-07-03-container-deep-readiness-st-dev-inert-use-write-probe.md`
- `knowledge-base/project/learnings/2026-07-06-cloudflare-universal-ssl-wildcard-depth-breaks-two-level-proxied-probe.md`
- `apps/web-platform/infra/nic-wait-gate.test.sh:71-82,251-267`; `ci-deploy.test.sh:699` (`MOCK_SLEEP_NOOP`, broadening #6665).
- `apps/web-platform/server/readiness.ts:54-60,81` (the floor semantics); `luks-monitor.service:5`; `workspaces-luks-emit.sh:33,62-73`.
- ADR-119 §(a) `:155-162`, `:234-240`; ADR-068 (deep-readiness pre-pool gate).
