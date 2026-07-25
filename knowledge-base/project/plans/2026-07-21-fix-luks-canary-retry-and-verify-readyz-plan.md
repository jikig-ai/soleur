---
title: "fix(infra): retry the LUKS app canary to a deadline, point verify at /health, and make verify assert readiness + workspace inventory"
issue: 6807
type: bug
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-07-21
branch: feat-one-shot-6807-luks-canary-verify-probes
plan_review: applied (5 agents + strong-model consult)
deepened: applied (4 agents + mechanical gates 4.4-4.9)
---

# fix(infra): retry the LUKS app canary to a deadline, point verify at `/health`, and make verify assert readiness **and inventory**

🐛 Three probe defects that made a **successful** `/workspaces` LUKS cutover report failure, plus the readiness coverage gap that leaves the live cutover's most important property unverified.

## Enhancement Summary

**Deepened:** 2026-07-21 · **Passes:** plan-review (Kieran, architecture-strategist, spec-flow, code-simplicity, strong-model consult) + deepen (test-design, observability-coverage, user-impact, mechanical sweep) + gates 4.4–4.9.

### Key improvements from review

1. **`readyz` proves a floor, not an inventory** (`countWorkspaceDirsAt(root) > 0`). The first draft repeated — one hop later — the exact overclaim it was written to fix. A separate **inventory count** assertion now carries that claim.
2. **The inventory assertion was itself an echo, not an assertion.** Moved **host-side into `luks-monitor.sh`**, which simultaneously binds the value, fails closed on a missing baseline, keeps SSH stderr off the runner, and makes `emit_drift` reachable (it is a host-side function the workflow cannot call).
3. **Distinct Sentry `op` reverted.** `workspaces-luks-drift` is the *sole paging op* of nine under this feature; a new op would page nobody and would be invisible to the wipe gate.
4. **`luks-monitor.sh` has no sourced-detection guard**, so the planned execution seam was impossible as written. Adding the guard is now an explicit task.
5. **Dead-man divergent-copy hazard surfaced**: `CANARY_OK=1` is set *before* `app_canary`, so a canary failure neither rolls back nor disarms — and this plan's retry extends that window by up to ~480 s.

### New considerations discovered

- Counter parity: the host-side count must replicate `session-metrics.ts`'s four exclusions or an inflated count certifies a real shrink green.
- A 403 from a loopback-gate regression is valid JSON and would land in the "serving an EMPTY /workspaces" arm — a confidently-wrong data-loss verdict.
- `_vscrub`/`_wl_scrub` are log-injection sanitizers, **not** redactors; the first draft credited them with a property they lack.

## Overview

The live cutover on web-1 (run `29782780158`, 2026-07-20 22:10–22:14 UTC) **succeeded at the infrastructure level**: `/mnt/data` is `crypto_LUKS` on `/dev/mapper/workspaces`, escrow ok, header readable, C1 differential clean (`phase=gate total=8 ok=7 preexisting=1 copy_corruption=0 src_only=0 src_missing_on_dst=0`, every workspace `dst_rc=0`). No rollback fired, correctly, because `CANARY_OK=1` was set by the host canary.

**This plan changes probe code only. It does not re-run, roll back, or otherwise touch the cutover.**

- **A — wrong endpoint.** `.github/workflows/workspaces-luks-verify.yml:103` asserts `https://app.soleur.ai/api/health == 200`. `/api/health` has no route; it 307s to `/login`. Observed live as `app /api/health=307`. The workflow is **structurally incapable of ever passing**, disabling the runbook's §5 gate.
- **B — single-shot probe racing container boot.** `workspaces-cutover.sh:663` probes `/health` ~590 ms after `docker start` and dies on Cloudflare's instant `521`. `--max-time 20` does not help: a 521 is a *fast* response, not a hang. `:665`'s readyz probe has the same shape.
- **C — the coverage gap (highest priority).** `/health` returns 200 **unconditionally** and never touches `$MOUNT` (`workspaces-cutover.sh:652-660`). `app_canary` died before reaching readyz, so **nothing off-host currently answers whether the repointed volume is serving user data**.

Per [`2026-07-19-the-harness-broke-the-rule-it-enforced-and-the-canary-could-not-fail.md`](../learnings/2026-07-19-the-harness-broke-the-rule-it-enforced-and-the-canary-could-not-fail.md) Key Insight 2: **the `/api/health` → `/health` swap alone is the documented-insufficient fix.**

### What `readyz` proves — and what it does not

`server/readiness.ts:81`:

```ts
const workspaces_populated = countWorkspaceDirsAt(root) > 0;
```

A **floor**, not an inventory. `isWorkspacesWritable` (`:54-60`) write+unlinks **one** probe file at the root. A cutover preserving 1 of 8 workspaces returns `ready=true`.

| Assertion | Proves | Where it runs |
| --- | --- | --- |
| `readyz ready=true` | Mount present, writable, non-empty — a **floor** | container, via host loopback |
| `workspace_count == expected` | The **inventory** survived | **host-side, inside `luks-monitor.sh`** |

The count runs host-side (not runner-side, not from `readyz`) so that it binds a value, fails closed without a baseline, keeps stderr off the runner, and can reach `emit_drift`. No app-code change.

## Research Reconciliation — Brief vs. Codebase

| Claim | Reality (verified) | Plan response |
| --- | --- | --- |
| "the canary-endpoint correction (merged **2026-06**)" | Landed **2026-07-19**, commit `ca85c30bc` / PR #6701 — one day before the cutover. | Correct provenance used. The one-day gap is *why* the sweep was thin. |
| Verify breakage "breaks the soak drift check" | **False.** `workspaces-luks-soak-6604.sh:50` reads Sentry drift events + heartbeat + ADR status directly; never invokes verify. | Impact scoped to the runbook §5 gate. No soak changes. |
| `/api/health` asserted-as-200 in several places | Exactly **one live assertion** (`workspaces-luks-verify.yml:103`). `/api/health/team-membership` is a real route. Other hits are prose, fixtures, the existing gates' own patterns, and `postmerge/SKILL.md:103` (which *warns against* it). | Fix the one assertion + the workflow prose. Extend the existing in-suite gate to two files — **not** a repo-wide gate. |
| `workspaces-luks-verify.test.sh` covers the verify workflow | **False, a naming trap** — it covers `verify_byte_identity`. | No new suite: `workspaces-luks-freeze.test.sh:25` already carries `WORKFLOW=` and greps a workflow (`:316-325`). Add `VERIFY_WF=`. |
| `luks-monitor.test.sh` can host behavioral cases | **False** — pure static grep suite; never executes the script. | Phase 4 builds the seam. |
| `luks-monitor.sh` can be `source`d for testing | **False** — it has **no sourced-detection guard** (unlike `workspaces-cutover.sh:1896`); its main body runs from `:64`. | Phase 4 adds the guard, mirroring the cutover's proven pattern. |
| The DRY win is "reuse the existing readyz reason codes in `luks-monitor.sh`" | **False.** `grep -n readyz luks-monitor.sh` → nothing; those codes exist only at `workspaces-cutover.sh:668,670`. | Extract into `workspaces-luks-emit.sh` — already sourced by both and in **both** tar lists (`verify.yml:94`, `cutover.yml:446`). |
| The Sentry envelope can carry readyz/probe discriminators | **False.** `workspaces-luks-emit.sh:62-73` hardcodes ten tags **and hardcodes the `op` value in the printf body**. | Envelope gains readiness + probe fields (Phase 1). The `op` stays `workspaces-luks-drift` — see Alternatives. |
| A distinct `op=workspaces-readiness-drift` improves paging | **False — it is a net regression.** `issue-alerts.tf:1704-1740` is the only alert for this feature and uses `filter_match="all"` on `op EQUAL workspaces-luks-drift`. Nine ops are emitted; **drift is the sole paging one.** A new op pages nobody and is invisible to the wipe gate (`soak:50`). | Reverted. De-conflation moves to exit code + `::error::` text. |
| `WORKSPACES_COUNT` gives verify an expected inventory | **False today** — `grep -rn WORKSPACES_COUNT apps/web-platform/infra/` returns **zero**. Phase 5 persists it on *future* cutovers; the cutover already ran. | Phase 2 **seeds** `WORKSPACES_COUNT=8` on the host, and the comparison **fails closed** when absent. |
| A shell directory count matches `readyz`'s notion of a workspace | **False.** `session-metrics.ts:19-41` excludes `.orphaned-*`, `.cron`, `lost+found`, and non-directories. | The host-side count replicates all four exclusions, with a parity AC. |
| A ~90 s canary window is "well inside" `DEAD_MAN_MIN=30` | **Understated ~5×** (≈480 s for both probes), and the timer arms at `:2128`, not at the canary. | Phase 0 measures the real remaining budget; Phase 5 caps combined spend, AC-bound. |
| `_vscrub` mitigates workspace-name exposure | **False.** `workspaces-cutover.sh:198` is `tr -d '\r\n' \| tr -cd '[:print:]'` — a log-**injection** sanitizer, not a redactor. `emit_verify_diff:206,213` already echoes full workspace paths to the run log and Better Stack. | User-Brand Impact corrected; the pre-existing path is scoped out explicitly, not miscredited. |
| `sleep` is stubbable in the freeze harness | **False** — not stubbed. | Phase 3 adds a **recording** stub (records the argument, per `nic-wait-gate.test.sh:71-82`). |
| `model.c4` is accurate about the volume | **Stale.** `:186` says `PLAINTEXT AT REST as of 2026-07-17`; `:410` says `plaintext at rest — ADR-119 in progress`. Cutover landed 2026-07-20. | Phase 7 corrects both. |
| The runbook's heartbeat claims are true | **False.** §5 says "pushes a Better Stack heartbeat; a missed push pages" and Failure-signals names `betteruptime_heartbeat.workspaces_luks`. `luks-monitor.sh:116` logs the URL absent (#6808). | Phase 7 strikes/annotates both. |

## Proposed Solution

### 1. One shared, classifying, bounded probe helper

Lives in `workspaces-luks-emit.sh` (already sourced by `luks-monitor.sh:31` and the cutover; already in both tars). **One** implementation.

**Classification is inverted: enumerate the STRUCTURAL set; everything else is retryable.** Failing safe on unknowns matters because this path is behind a CF Tunnel.

- **Structural — fail fast:** `307, 401, 403, 404, 405, 525, 526`.
- **Retryable — everything else**, notably `000, 500, 502, 503, 504, 521, 522, 523, 524, 530`. `530` (CF 1033, "tunnel connector not connected") is the code this stack most likely emits during a restart window; classifying it structural would reintroduce Bug B in a new coat.

**Bounded by attempts, not wall clock** — deterministic under a stubbed no-op `sleep`.

```bash
# 30 × 3s ≈ 90s per probe; --max-time 5 ⇒ ≤240s per probe, ≤480s for both.
# Phase 0.4 measures actual remaining DEAD_MAN_MIN budget; Phase 5.3 caps combined spend.
CANARY_ATTEMPTS="${WORKSPACES_CANARY_ATTEMPTS:-30}"
CANARY_INTERVAL_S="${WORKSPACES_CANARY_INTERVAL_S:-3}"
# `:-` handles empty. The real silent-disable hazard is =0 (a zero-iteration loop passes
# trivially) or a non-numeric value — neither of which `:-` catches. Hence the floor:
[ "$CANARY_ATTEMPTS" -ge 1 ] 2>/dev/null || CANARY_ATTEMPTS=1
```

> Scope note: the `:-` rule applies to these two **production** knobs only. The harness's test knobs use the unset form `${X-default}` (`workspaces-luks-harness.sh:283`) deliberately, so an empty value exercises a distinct arm rather than silently becoming the happy path.

**The readyz classifier checks HTTP status BEFORE body shape.** Body-only classification is unsafe: a loopback-gate regression returns `403 {"error":"forbidden"}` — valid JSON, not `ready:true` — which would land in the not-ready arm and page *"the container is serving an EMPTY /workspaces"* (`workspaces-cutover.sh:670`), a confidently-wrong data-loss verdict. Four arms, one reason code each:

| Arm | Reason code |
| --- | --- |
| `200` + `"ready":true` | *(success)* |
| `200` + `"ready":false` | `readyz_not_ready` |
| `200` + unparseable body | `readyz_unparseable` |
| `403/404/405` (gate/route regression) | `readyz_gate_regression` |
| no response at all | `readyz_unreachable` |

### 2. Inventory assertion — host-side, fail-closed, parity-pinned

Runs inside `luks-monitor.sh`, **not** in the workflow run block. Four reasons, each closing a review finding:

1. **Binds the value.** A runner-side echo plus a `grep` for the verdict line passes on `workspace_count=1` exactly as on `=8` unless the grep binds the integer. Host-side comparison removes the possibility.
2. **Fails closed without a baseline.** `WORKSPACES_COUNT` does not exist on the host today. A missing expected value must be a non-zero exit, never a skipped comparison.
3. **Keeps stderr off the runner.** A `Permission denied` or symlink error from the count command carries a user-identifying path; host-side it never crosses the SSH boundary.
4. **`emit_drift` is reachable.** It is a host-side shell function the workflow cannot call.

**Counter parity is load-bearing.** `session-metrics.ts:19-41` excludes `.orphaned-*`, `.cron`, `lost+found`, and non-directories. An unfiltered shell count inflates — 7 surviving workspaces plus `lost+found` and `.cron` reads as 9 ≥ 8, certifying a real shrink green. The host-side count replicates all four exclusions, with a cross-referencing comment on both sides and a fixture-based parity test.

### 3. De-conflate the verdicts — at the exit code, not the log line

`emit_and_die` always `exit 1`, and the workflow's `::error::` hard-codes the at-rest framing, making `probe_rc` a **three-way** collapse (LUKS drift / readiness / SSH transport `255` — the last telling the operator to read a Sentry event that was never emitted). An echo does not fix this:

- Exit codes from `luks-monitor.sh`: `1` = LUKS drift, `2` = readiness/inventory.
- A `255` transport arm in the workflow with its own message.
- Distinct `::error::` text per arm.

**Readiness stays on `op=workspaces-luks-drift`** — a deliberate reversal of the first draft. `issue-alerts.tf:1704-1740` is the only alert for this feature (`filter_match="all"`, `op EQUAL workspaces-luks-drift`); of nine emitted ops, **drift is the sole paging one**. A new op would page nobody and would be invisible to the wipe gate at `soak:50`. Fixing both would need a new alert rule *plus* a Sentry `op:[a,b]` IN-syntax change to the soak — a vendor-search contract to verify and a new two-site sync obligation, i.e. the sibling-drift class that caused this issue. `workspaces-luks-emit.sh:62-73` also **hardcodes** the op in its printf, so the first draft was structurally incapable of emitting a new value anyway. The mislabeling concern is met by `reason` + the new `WL_READYZ_*` fields, and keeping one op preserves the **fail-safe** property that a readiness failure blocks the wipe.

### 4. Positive control — the assertion must prove it ran

The flag is delivered through a triple-nested quoting hazard (`verify.yml:99`). If dropped, `luks-monitor.sh` exits 0 having never probed and the workflow prints **PASSED** — byte-for-byte the failure shape being fixed.

- Deliver the flag via the `.env` already `set -a`-sourced, sidestepping the quoting nest.
- `luks-monitor.sh` emits a **mandatory** verdict line on the asserted-success path.
- The workflow greps for it and **fails on its absence** (assert-presence, not assert-no-error).

### Alternatives considered

| Option | Verdict |
| --- | --- |
| **Shared helper in `workspaces-luks-emit.sh`; readyz + count in `luks-monitor.sh` behind default-OFF `LUKS_MONITOR_ASSERT_READYZ`, set by verify (chosen)** | Only option delivering real DRY. Default-OFF is right for a reason the first draft never gave: `luks-monitor.service:5`'s `RequiresMountsFor=/mnt/data` means the daily unit **cannot run** in the reboot hazard, so default-ON buys no coverage there — while the bare-file verify path can. |
| Default-ON in the daily monitor | Rejected. The strong-model consult argued default-OFF "buys zero continuous coverage" — sound reasoning from a false premise; `RequiresMountsFor` makes the unit inert in exactly that hazard. Also extends time-to-page ~90 s on a real outage. |
| Distinct Sentry `op` for readiness | Rejected on evidence — see §3. |
| Count assertion runner-side in the workflow | Rejected — unbound value, no fail-closed path, stderr leak, `emit_drift` unreachable. |
| New `workspaces-readyz-probe.sh` | Rejected: two tar lists to keep in sync — the drift class that caused this issue. |
| Repo-wide `/api/health`-as-200 CI gate | **Cut.** The proposed scope red-lights six *legitimate* hits including the existing gates' own patterns and `postmerge/SKILL.md:103`. Replaced by extending the in-suite gate to `$CUTOVER $VERIFY_WF`. |
| New `workspaces-luks-verify-workflow.test.sh` | **Cut.** `workspaces-luks-freeze.test.sh:25` already greps a workflow. The YAML-parse requirement was mis-imported from a suite whose stated reason is `${{ }}` operand inversion. |

**Deferred, tracked:** whether the daily probe should assert readyz once the mount is present — framed correctly (steady-state only; the reboot hazard is covered structurally by `chattr +i` + the `RequiresMountsFor` drop-in). If it is ever flipped ON, the soak query must also be revisited.

## User-Brand Impact

- **If this lands broken, the user experiences:** a future cutover certified green while the container serves an empty or **partially-populated** `/workspaces` — users' repositories missing from the dashboard and every agent session. Per `model.c4:186` these worktrees are **sole-copy**: `refs/checkpoints/*` is pushed by no refspec and signup-provisioned workspaces have no git remote.
- **Divergent-copy loss on dead-man remount.** `CANARY_OK=1` is set at `:2246` **before** `app_canary` at `:2260`, so a canary failure neither rolls back (`cleanup()`'s guard at `:721`) **nor** reaches `disarm_dead_man` at `:2269`. The armed timer then remounts the retained **plaintext** volume over `$MOUNT`. Every write committed to the LUKS volume between the flip and the timer firing becomes invisible, and subsequent writes land on the stale copy — two divergent copies of sole-copy data with no merge path. This plan's retry adds up to ~480 s into that window, which is why Phase 5.3's combined cap is AC-bound.
- **False-red on a healthy volume.** `isWorkspacesWritable` fails closed on ENOSPC/EROFS/EACCES/EIO, so a full disk or read-only remount yields `ready=false`. Without discrimination, Phase 2's STOP CONDITION would escalate a **capacity fault** to "data-recovery incident on sole-copy data" — a destructive operator response to a non-destructive problem.
- **If this leaks, the user's data is exposed via:** workspace **directory names**, which are user-identifying. Three channels: the workflow echo (bound to an integer by AC), SSH **stderr** inherited by the runner (redirected host-side), and the **pre-existing** `emit_verify_diff` path rows (`workspaces-cutover.sh:206,213`) which already emit full workspace paths to the run log and Better Stack. That third channel is **out of scope here and explicitly not fixed by this plan** — recording it because the first draft wrongly credited `_vscrub` with redacting it. `_vscrub`/`_wl_scrub` are log-**injection** sanitizers (`tr -d '\r\n' | tr -cd '[:print:]'`), not redactors.
- **Brand-survival threshold:** `single-user incident`

## Observability

```yaml
liveness_signal:
  what: "Operator-dispatched workspaces-luks-verify.yml run. NOTE: luks-monitor.sh's Better Stack heartbeat push is UNFED — WORKSPACES_LUKS_HEARTBEAT_URL is absent (luks-monitor.sh:116); that is #6808 and is deliberately NOT fixed here."
  cadence: "on demand (workflow_dispatch); the daily luks-monitor.timer runs the LUKS asserts but not readyz/inventory (flag default-OFF)"
  alert_target: "What actually pages today: the Sentry issue alert sentry_issue_alert.workspaces_luks_drift (feature=workspaces-luks AND op=workspaces-luks-drift, filter_match=all), plus the Better Stack apex uptime monitor betteruptime_monitor.app. NOT the luks-monitor heartbeat (unfed, #6808)."
  configured_in: "apps/web-platform/infra/sentry/issue-alerts.tf:1704-1740; apps/web-platform/infra/uptime-alerts.tf:93; apps/web-platform/infra/luks-monitor.timer"
error_reporting:
  destination: "Sentry via workspaces-luks-emit.sh (single op: workspaces-luks-drift; discriminated by WL_REASON + the new WL_* fields); ::error:: annotations in the verify workflow"
  fail_loud: true
failure_modes:
  - mode: "app /health never returns 200 within the retry budget"
    detection: "emit_drift health_probe_deadline, carrying WL_PROBE_LAST_CODE / WL_PROBE_ATTEMPTS / WL_PROBE_ELAPSED_S / WL_PROBE_CLASS (added to the envelope in Phase 1). class=deadline covers no-route/DNS (curl 000) as well as slow boot, and the message says so."
    alert_route: "Sentry op=workspaces-luks-drift; dead-man remains armed (disarm_dead_man runs after app_canary)"
  - mode: "app /health returns a STRUCTURAL code (307/401/403/404/405/525/526) — endpoint regression"
    detection: "emit_drift health_probe_structural on the FIRST attempt with WL_PROBE_LAST_CODE set (no retry burn)"
    alert_route: "Sentry op=workspaces-luks-drift; workflow ::error:: with the same fields"
  - mode: "/internal/readyz returns no response for the whole budget"
    detection: "emit_drift readyz_unreachable"
    alert_route: "Sentry op=workspaces-luks-drift; luks-monitor exit 2"
  - mode: "/internal/readyz 200 + ready=false — mount not writable or empty"
    detection: "emit_drift readyz_not_ready carrying WL_READYZ_WRITABLE + WL_READYZ_POPULATED, discriminating WHICH check failed; plus WL_READYZ_CAPACITY (df of the mount) so an ENOSPC/EROFS false-red is separable from data loss"
    alert_route: "Sentry op=workspaces-luks-drift; luks-monitor exit 2; runbook triage routes capacity vs data-recovery"
  - mode: "/internal/readyz 200 + unparseable body (proxy error page, truncated response)"
    detection: "emit_drift readyz_unparseable — a DISTINCT reason, so a proxy fault is never reported as data loss"
    alert_route: "Sentry op=workspaces-luks-drift"
  - mode: "/internal/readyz 403/404/405 — loopback-gate or route regression returning valid JSON"
    detection: "emit_drift readyz_gate_regression — status is classified BEFORE body shape, so a forbidden body never lands in the not-ready arm"
    alert_route: "Sentry op=workspaces-luks-drift"
  - mode: "workspace INVENTORY shrank (count < expected) — readyz says ready=true because >0 dirs exist"
    detection: "host-side count inside luks-monitor.sh, exclusions mirrored from session-metrics.ts, compared against the persisted WORKSPACES_COUNT; emit_drift workspace_count_shortfall carrying WL_WORKSPACE_COUNT + WL_WORKSPACE_COUNT_EXPECTED (integers only, never names)"
    alert_route: "Sentry op=workspaces-luks-drift; luks-monitor exit 2; workflow ::error::"
  - mode: "expected inventory baseline absent (WORKSPACES_COUNT unset on the host)"
    detection: "emit_drift workspace_count_baseline_missing — fail CLOSED; a missing operand must never be a skipped comparison"
    alert_route: "Sentry op=workspaces-luks-drift; luks-monitor exit 2"
  - mode: "the readyz/inventory assertion silently never ran (flag lost in the quoting nest)"
    detection: "the mandatory verdict line is ABSENT from the run log; the workflow greps for it and fails on absence (positive control)"
    alert_route: "verify workflow ::error::"
  - mode: "SSH/tunnel transport failure (rc=255) misreported as at-rest drift"
    detection: "explicit rc==255 arm emitting a transport-specific ::error:: that does NOT point at a nonexistent Sentry event"
    alert_route: "verify workflow ::error::"
logs:
  where: "GitHub Actions run log (workspaces-luks-verify.yml); journald under SyslogIdentifier=luks-monitor, shipped by Vector to Better Stack Logs source 2457081"
  retention: "Better Stack Logs retention for source 2457081; GitHub Actions default run-log retention"
discoverability_test:
  command: "gh workflow run workspaces-luks-verify.yml --ref feat-one-shot-6807-luks-canary-verify-probes && gh run watch $(gh run list --workflow=workspaces-luks-verify.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
  expected_output: "conclusion=success, run log containing 'luks-monitor probe rc=0', 'app /health=200', and the mandatory verdict line 'SOLEUR_WORKSPACES_READYZ ready=true writable=true populated=true workspace_count=8 expected=8'"
```

## Network-Outage Deep-Dive (Phase 4.5, keyword-triggered)

The gate fires on `ssh|timeout|503|504|unreachable`, but this plan is **not** an outage diagnosis — those tokens are HTTP status codes being *classified* by a retry loop, plus the verify workflow's existing, working CF Tunnel SSH bridge. Layer status:

| Layer | Status | Artifact |
| --- | --- | --- |
| L3 firewall allow-list | **Not applicable** — the GH runner's egress IP is deliberately *not* in `var.admin_ips`; reach is via the CF Tunnel bridge (`verify.yml:10-12`), not a firewall hole. | `.github/actions/cf-tunnel-ssh-bridge` |
| L3 DNS / routing | **Not applicable** — the probe dials the private IP `10.0.1.10`, redirected by a local iptables NAT rule to the cloudflared forward. No public resolution. | `verify.yml` `WEB_HOST_PRIVATE_IP` |
| L7 TLS / proxy | **In scope and handled** — the `/health` probe traverses the CF edge, which is exactly why `521`/`530` are classified retryable rather than structural. | Proposed Solution §1 |
| L7 application | **In scope and handled** — readyz status-before-body classification, plus the rc `255` transport arm so a bridge failure is never reported as at-rest drift. | Proposed Solution §1, §3 |

The one genuine L3 dependency is that the SSH bridge must work for Phase 2 to run at all; a bridge failure is explicitly distinguished by the `255` arm rather than being misread as a readiness failure.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-119** (`status: adopting`) — no new ADR; this extends a recorded decision to a second surface.

1. §(a) (`:155-162`): record that the reasoning binds the **off-host verify** surface; that both probes are retry-bounded because `docker start` returns before Node listens; and — the substantive addition — that **`readyz` proves a floor, not an inventory**, so certifying a cutover requires a separate count assertion.
2. `:237`: the narrative says "container healthy, `/api/health` 200"; `/api/health` 307s. Correct to `/health`.

### C4 views

**No structural change — two falsified descriptions must be corrected** (the completeness mandate covers description correctness, not only elements/edges). Enumerated against all three model files:

- **External human actors:** `founder = actor "Founder / Operator"` (`model.c4:8`) — modelled.
- **External systems:** `github` (`:230`), `cloudflare` (`:234`) — modelled; the probe rides the existing `github -> tunnel` edge (`:407`).
- **Containers / data stores:** `platform.infra.hetzner` (`:180`), `workspacesVolume` (`:186`) — modelled, with `hetzner -> workspacesVolume` (`:410`).
- **Access relationships:** none changed.

**Corrections (Phase 7):** `:186` (`PLAINTEXT AT REST as of 2026-07-17`) and `:410` (`plaintext at rest — ADR-119 in progress`) are stale; the cutover landed 2026-07-20. Re-run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Implementation Phases

Dependency-directed. **Phase 2 is a hard gate.** Test tasks are written **RED first** within each phase (`cq-write-failing-tests-before`), not deferred wholesale to the end.

### Phase 0 — Preconditions (verify, do not assume)

1. Baseline green: `workspaces-luks-freeze.test.sh`, `luks-monitor.test.sh`, `workspaces-luks-verify.test.sh`.
2. Confirm `git grep -n 'sleep' workspaces-luks-harness.sh` is empty and `workspaces-cutover.sh` has no `sleep` today.
3. Record baselines: `deploy-script-tests` duration (`infra-validation.yml:298`, 12 min; `ci-deploy.sh` ≈ 407 s) and the verify job budget (`verify.yml:38`, 15 min).
4. **Measure remaining dead-man budget at the canary** from run `29782780158`: elapsed from `arm_dead_man` (`:2128`) to the canary (`:2260`), against `DEAD_MAN_MIN=30`. Bounds Phase 5.3.
5. Read the `CANARY_OK` reload path (`:2246`, `cleanup()` `:721`); confirm a re-dispatch cannot suppress `rollback()` via stale state.

### Phase 1 — Shared probe helper (`workspaces-luks-emit.sh`)

1. Bounded, classifying HTTP probe (structural set enumerated; everything else retryable); attempts-bounded with the `-ge 1` floor.
2. readyz classifier: **status before body**, five arms per the table in §1.
3. Envelope fields (additive; existing callers emit `unknown`): `WL_READYZ_WRITABLE`, `WL_READYZ_POPULATED`, `WL_READYZ_CAPACITY`, `WL_WORKSPACE_COUNT`, `WL_WORKSPACE_COUNT_EXPECTED`, `WL_PROBE_LAST_CODE`, `WL_PROBE_ATTEMPTS`, `WL_PROBE_ELAPSED_S`, `WL_PROBE_CLASS`. Every value through `_wl_scrub`. **Do not** parameterize `op`.
4. Header note: this file is the shared leaf helper for the feature, not solely the emitter.

### Phase 2 — Ground-truth gate (probe first) 🚦

1. `workspaces-luks-verify.yml:103`: `/api/health` → `https://app.soleur.ai/health`, wrapped in the Phase 1 retry.
2. Set `LUKS_MONITOR_ASSERT_READYZ=1` **via the sourced `.env`** at `:99` — not through the quoting nest.
3. `luks-monitor.sh`: flag-gated readyz assert + **host-side inventory count** (exclusions mirrored from `session-metrics.ts:19-41`), comparison **fail-closed** when `WORKSPACES_COUNT` is absent, count command's stderr redirected host-side, mandatory verdict line emitted.
4. **Seed the baseline:** write `WORKSPACES_COUNT=8` to the host state file (the 2026-07-20 cutover predates `persist_state`, so no baseline exists).
5. **Dispatch pre-merge:** `gh workflow run workspaces-luks-verify.yml --ref feat-one-shot-6807-luks-canary-verify-probes` (feasible — workflow already on the default branch, ID `315308438`).
6. **Record the verdict in this plan.** Expected `ready=true`, `workspace_count=8`, `expected=8`.
7. **STOP CONDITION:** if `ready=false` with `WL_READYZ_WRITABLE=false` **and** `WL_READYZ_CAPACITY` shows a full/read-only mount → **capacity incident**, not data loss. If the count is `< 8` or `ready=false` on a healthy mount → **data-recovery incident on sole-copy data**; halt and escalate.

### Phase 3 — Freeze harness (`workspaces-luks-harness.sh`)

1. **Recording** no-op `sleep` stub that `rec "sleep $*"` — recording the *argument*, not just the call. This gives per-arm attribution **and** covers `WORKSPACES_CANARY_INTERVAL_S` for free (`has '^sleep 3'`).
2. `CURL_CODES` / `READYZ_BODIES` sequenced knobs mirroring `MOUNTPOINT_RCS` (`:173-181`), using the **`${X-default}` unset form** per the harness discipline at `:283` so an empty value does not silently become the happy path. **Separate index per endpoint arm** — the stub's single `case "$*"` serves both `/health` and `*readyz*`, so one shared counter would desynchronise the `/health` sequence silently.
3. Document saturation semantics inline (`CURL_CODES="521"` ⇒ *always* 521).
4. `READYZ_BODIES` is **retained** (reversing an earlier cut): the readyz classifier is now four-armed, and arm 2 (retryable-not-ready) would otherwise have no behavioural coverage — replacing a behavioural test with a source grep is the standard this plan rejects elsewhere.

### Phase 4 — Execution seam for `luks-monitor.sh`

1. **Add a sourced-detection guard** to `luks-monitor.sh`, mirroring `workspaces-cutover.sh:1896` (`BASH_SOURCE[0]` vs `$0`). Without it, `source luks-monitor.sh` runs the entire probe at `:64` and the harness's function stubs cannot take effect — the seam is impossible as first written. This is a SUT change; it is in Files to Edit.
2. Extend the harness to source and run `luks-monitor.sh` under stubbed `curl`/`doppler`/`findmnt`/`cryptsetup`/`blkid`/`mountpoint`.
3. Pin ordering: the readyz + inventory asserts run **before** the heartbeat push (`:109-117`), so a failing host does not push a healthy beat. Comment the reason.
4. Exit codes: `1` = LUKS drift, `2` = readiness/inventory.

### Phase 5 — `app_canary` retry (`workspaces-cutover.sh`)

1. Route both probes (`:663`, `:665`) through the Phase 1 helper. **Pin the loop shape** (whether it sleeps after the final attempt) — ACs derive from it.
2. Add `emit_drift health_probe_deadline` / `health_probe_structural` to the `/health` arms, which today call bare `die` and emit nothing.
3. Cap **combined** canary spend against the Phase 0.4 measurement, with a hard assertion that worst-case spend + measured pre-canary elapsed `< DEAD_MAN_MIN`.
4. **Do not move `app_canary` relative to `disarm_dead_man`** (`:2256-2269`).
5. `persist_state WORKSPACES_COUNT "$total"` at the C1 gate so future verifies have a baseline.

### Phase 6 — Tests (existing suites only)

`workspaces-luks-freeze.test.sh` — add `VERIFY_WF=` beside `:25`. Every case pins a **reason code** via `outF 'EMIT_DRIFT: <reason>'` (the stub already echoes, `harness:289`); `died()` alone cannot distinguish structural from deadline. Sleep assertions are **per-arm**, not a global total.

- **T23a** recovers through the loop: `CURL_CODES="521 521 200"` ⇒ `ran` ∧ exactly 2 `/health`-arm sleeps.
- **T23b** structural fail-fast: `CURL_CODES="307"` ⇒ `died` ∧ **zero** sleeps ∧ `health_probe_structural`.
- **T23c** retryable-unknown fails safe: `CURL_CODES="530"` ⇒ `died` ∧ sleeps == full bound ∧ `health_probe_deadline` (distinguishes it from T23b, which the earlier draft did not).
- **T23d** seam-unset: knobs **unset**, `run_case` sealed against inherited env, ⇒ never-recovering probe sleeps exactly the **literal** production count (hardcode `30`; deriving it from source is circular).
- **T23e** interval seam: sleep args are all exactly `3` under unset knobs.
- **T23f** floor: `WORKSPACES_CANARY_ATTEMPTS=0` **and** `=abc` each still probe ≥ 1 time.
- **T24** readyz arms: `READYZ_BODIES` recovering ⇒ `ran`; saturating `ready:false` ⇒ `readyz_not_ready`; unparseable ⇒ `readyz_unparseable`; `403` ⇒ `readyz_gate_regression`.
- **T25** ordering: `app_canary` precedes `disarm_dead_man` (comment-stripped index).
- **Suite gate widened** (the existing `AC7` gate in that file — distinct from this plan's AC numbering): bare `/api/health` pattern over `$CUTOVER $VERIFY_WF`, **not** comment-stripped for the workflow, `/api/health/team-membership` allowlisted.

`luks-monitor.test.sh` on the Phase 4 seam:

- Flag unset ⇒ readyz never probed **and** `ran` (a bare negative passes if the seam aborted early at `not_mounted`).
- Flag set ⇒ readyz **is** probed (paired positive control).
- Count parity fixture containing `lost+found`, `.cron`, `.orphaned-x`, and a stray regular file ⇒ host count equals `countWorkspaceDirsAt`'s result.
- Missing `WORKSPACES_COUNT` ⇒ non-zero exit + `workspace_count_baseline_missing` (fail-closed).
- Count `< expected` ⇒ exit 2 + `workspace_count_shortfall`.
- Verdict line present on the success path; flag-leak guard (the cutover channel writes no `LUKS_MONITOR_ASSERT_READYZ` into `/etc/default/luks-monitor`).

Hygiene: no `cmd | grep -q` under `pipefail` (141 fails **OPEN** on negatives); strip `^[[:space:]]*#` before body-greps; never `[[ cond ]] && cmd` standalone under `set -e`.

### Phase 7 — Docs, model, tracking

1. Runbook §5: `/health` 200 + `readyz ready=true` + `workspace_count`; record the **2026-07-20** landing and that §5 was non-functional until this fix.
2. Runbook: **verdict → operator action triage table** covering LUKS drift / readiness / **capacity (ENOSPC/EROFS)** / count shortfall / baseline missing / structural / gate regression / transport 255 / AC-fails-during-ship. Capacity must route to "capacity incident", never "data-recovery".
3. Runbook: strike the false heartbeat claims — §5's *"pushes a Better Stack heartbeat; a missed push pages"* and the Failure-signals `betteruptime_heartbeat.workspaces_luks` bullet — marking both `UNFED pending #6808`.
4. ADR-119 §(a) amendment (incl. floor-vs-inventory) and `:237`.
5. `model.c4:186` + `:410` staleness; re-run the two C4 tests.
6. `workspaces-luks-verify.yml` header (`:3`, `:7`, `:84`): reword "MUTATES NOTHING" — `isWorkspacesWritable` write+unlinks a probe file at the workspaces root.
7. Workflow prose sweep: `:6`, `:102`, `:104`, `:110`, `:113`, `:160`; add the rc `255` transport arm.
8. File the deferred daily-readyz issue with the corrected framing.
9. Consider renaming `workspaces-luks-verify.test.sh` (it covers `verify_byte_identity`).

## Files to Edit

| File | Change |
| --- | --- |
| `apps/web-platform/infra/workspaces-luks-emit.sh` | Shared probe helper + 4-arm readyz classifier; 9 new envelope fields |
| `apps/web-platform/infra/workspaces-luks-harness.sh` | Recording `sleep` stub; `CURL_CODES`/`READYZ_BODIES` with per-endpoint index; `luks-monitor.sh` seam |
| `apps/web-platform/infra/workspaces-cutover.sh` | `app_canary` via the helper; `emit_drift` on `/health` arms; combined cap; persist `WORKSPACES_COUNT` |
| `apps/web-platform/infra/luks-monitor.sh` | **Sourced-detection guard**; flag-gated readyz + host-side inventory count; exit 2; verdict line |
| `apps/web-platform/infra/luks-monitor.test.sh` | Behavioral cases on the new seam |
| `apps/web-platform/infra/workspaces-luks-freeze.test.sh` | `VERIFY_WF=`; T23a–f, T24, T25; widened suite gate |
| `.github/workflows/workspaces-luks-verify.yml` | `/health` + retry; flag via `.env`; verdict-line positive control; rc 255 arm; prose `:3,6,7,84,102,104,110,113,160` |
| `knowledge-base/engineering/architecture/decisions/ADR-119-…md` | §(a) amendment; `:237` |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | `:186`, `:410` staleness |
| `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md` | §5 endpoints + count; landing date; triage table; strike false heartbeat claims |

## Files to Create

None.

## Open Code-Review Overlap

`None.` Queried `gh issue list --label code-review --state open --limit 200`; matched every planned path. Zero hits.

## Acceptance Criteria

### Ground-truth gate (Phase 2, pre-merge)

- [ ] **AC1** A pre-merge `--ref` dispatch concludes `success` against the current web-1, with the verdict line showing `ready=true`, `workspace_count=8`, `expected=8`. *This closes the issue's open question.*

### Pre-merge

- [ ] **AC2** `CURL_CODES="521 521 200"` ⇒ canary succeeds ∧ exactly 2 `/health`-arm sleeps.
- [ ] **AC3** `CURL_CODES="307"` ⇒ `died`, **zero** sleeps, reason `health_probe_structural`.
- [ ] **AC4** `CURL_CODES="530"` ⇒ `died`, sleeps == full bound, reason `health_probe_deadline` (distinct from AC3).
- [ ] **AC5** Seam-unset: knobs unset (env sealed) ⇒ exactly the literal production attempt count; every sleep arg is `3`.
- [ ] **AC6** Floor: `WORKSPACES_CANARY_ATTEMPTS=0` and `=abc` each still probe ≥ 1 time.
- [ ] **AC7** readyz four-arm classification, each with its own reason code: not-ready / unparseable / **403 gate regression** / unreachable. A 403 never yields `readyz_not_ready`.
- [ ] **AC8** `app_canary` precedes `disarm_dead_man`; and worst-case combined canary spend + measured pre-canary elapsed `< DEAD_MAN_MIN`.
- [ ] **AC9** Inventory parity: on a fixture with `lost+found`, `.cron`, `.orphaned-x`, and a stray file, the host-side count equals `countWorkspaceDirsAt`'s result.
- [ ] **AC10** Fail-closed baseline: `WORKSPACES_COUNT` absent ⇒ non-zero exit + `workspace_count_baseline_missing`. Count `< expected` ⇒ exit 2 + `workspace_count_shortfall`.
- [ ] **AC11** Suite gate widened: bare `/api/health` over `$CUTOVER $VERIFY_WF` returns zero live assertions (`/api/health/team-membership` allowlisted), and all six workflow prose sites are corrected.
- [ ] **AC12** Positive control: with the flag deliberately unset, a second `--ref` dispatch **fails** on the absence of the verdict line (the shell suite cannot execute YAML, so this is dispatch-verified).
- [ ] **AC13** De-conflation: `luks-monitor.sh` exits `2` on readiness/inventory vs `1` on LUKS drift; the workflow branches on it; rc `255` yields a transport-specific error that references no nonexistent Sentry event.
- [ ] **AC14** Envelope: a `readyz_not_ready` emission carries `WL_READYZ_WRITABLE`/`WL_READYZ_POPULATED`/`WL_READYZ_CAPACITY`; a shortfall carries `WL_WORKSPACE_COUNT`/`_EXPECTED`; a `/health` failure carries `WL_PROBE_LAST_CODE`/`_ATTEMPTS`/`_ELAPSED_S`/`_CLASS`. The emitted `op` remains `workspaces-luks-drift`.
- [ ] **AC15** Flag unset ⇒ `luks-monitor.sh` never probes readyz **and** `ran` (paired with a flag-set positive); the cutover channel writes no `LUKS_MONITOR_ASSERT_READYZ` into `/etc/default/luks-monitor`.
- [ ] **AC16** Log hygiene: no user-path substring appears anywhere in the run log **including stderr**; the count crosses the SSH boundary as an integer only.
- [ ] **AC17** Suites green (`workspaces-luks-freeze`, `luks-monitor`, `workspaces-luks-verify`, both C4 tests); `deploy-script-tests` duration within 60 s of the Phase 0.3 baseline.
- [ ] **AC18** Docs: ADR-119 §(a) records floor-vs-inventory and `:237` corrected; `model.c4:186`/`:410` no longer claim plaintext-at-rest; runbook §5 carries endpoints, landing date, non-functional note, triage table (with capacity routed away from data-recovery), and both false heartbeat claims struck.
- [ ] **AC19** `WORKSPACES_LUKS_HEARTBEAT_URL` appears nowhere in the diff — #6808 stays out.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** Probe-code fix on an already-provisioned surface. No new servers, services, secrets, vendors, or persistent processes — Phase 2.8 IaC gate does not fire; the edited scripts ship via the existing cutover/verify SSH channels, which tar the repo copy each run. Principal risks — testability (the `sleep` stub and the missing sourced-guard), CI budget, cross-file drift, and the dead-man window — are addressed by the shared helper, the execution seam, and the AC-bound combined cap. The architectural decision is an **amendment** to ADR-119.

### Product/UX Gate

Not applicable. Product not relevant; the mechanical UI-surface override does not fire — no path in Files to Edit matches any UI-surface glob. Tier: `NONE`.

### GDPR / Compliance (Phase 2.7)

Invoked by trigger **(b)** — `single-user incident` threshold — not by the canonical regex.

**Assessment (advisory only; not legal advice):** `/internal/readyz` returns booleans; no personal data, no special-category data, no new processing activity, no lawful-basis change, no Art. 30 trigger. **Three findings, all folded in:** (1) no raw readyz body into an Actions log; (2) the count crosses as an **integer only** — workspace directory names are user-identifying (AC16); (3) SSH **stderr** is a distinct leak channel that an "echo" constraint does not cover — the count now runs host-side with stderr redirected. Separately recorded, **not** fixed here: the pre-existing `emit_verify_diff` path rows already emit full workspace paths to the run log and Better Stack. No Critical findings.

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| Retry loop spins hot in CI | Attempts-bounded, not wall-clock; `sleep` stubbed. |
| New tests tip `deploy-script-tests` past 12 min | Sleeps stubbed; Phase 0.3 baseline; AC17 uses a **60 s delta**, not an unfalsifiable "within budget". |
| Retry masks a permanent origin break (521/530 are "unreachable", not inherently transient) | Bounded budget; verdict names `WL_PROBE_LAST_CODE` + `_CLASS`; `class=deadline` prose covers no-route explicitly. |
| Dead-man fires mid-canary → divergent sole-copy data | Phase 0.4 measures real remaining budget; Phase 5.3 caps combined spend; AC8 asserts the inequality. |
| Implementation drift between probes | **One** helper in `workspaces-luks-emit.sh`, already in both tars. The workflow's runner-side `/health` loop is the only separate copy — it cannot share on-host code, and it is grep-asserted only; the Risks claim is scoped to that truth rather than overclaiming behavioural coverage. |
| A lost flag yields a silent green | AC12's dispatch-verified positive control. |
| A counting bug triggers a destructive operator response | AC9 parity fixture; Phase 7.2 triage table routes capacity faults away from "data-recovery". |
| Verify dispatched during a cutover reports scary false verdicts | Pre-existing (`verify.yml:21` separate concurrency group); readyz widens the window. Noted for the deferred issue. |

### Precedent diff — retry/backoff shape (gate 4.4)

Six retry loops exist in `apps/web-platform/infra/*.sh`. The proposed helper is measured against them:

| Property | Repo precedent | This plan | Verdict |
| --- | --- | --- | --- |
| Bound | **Attempts, in all six loops — zero wall-clock exceptions** (`ci-deploy.sh:1826,1907,1950,2452,1426`; `soleur-host-bootstrap.sh:392`) | Attempts | **Full match** |
| Attempt logging | `(attempt N/M)` in the dominant shape (`ci-deploy.sh:1846,1850,1855,1911,1914,1956,1960`) | `(attempt N/M)` | **Full match** |
| Failure classification | **Minority.** Four of six retry blindly on any non-200 (incl. the deploy canary at `:2452-2533`, which treats 307 and 521 identically). Only `_ghcr_pull_or_recover` (`:1426-1488`) classifies — three-way auth/transient/terminal. | Structural-vs-retryable HTTP classification | **Deliberate upgrade** — modelled on the one sophisticated precedent, diverging from the four blind loops. Justified: the blind shape is precisely what makes the current canary abort a good cutover on a 521, and what would make a re-introduced `/api/health` 307 burn the full budget. |
| Sleep schedule | Fixed interval in five; graduated (`PULL_TRANSIENT_RETRY_SLEEPS="2 4"`) in `_ghcr_pull_or_recover` | Fixed interval | Match with the dominant shape; graduated backoff not adopted (a fixed 3 s over 30 attempts covers container boot without a long tail). |

No precedent exists for a *classifying* readyz body probe — that arm is novel and is flagged for reviewer scrutiny.

## Sharp Edges

1. **`readyz` proves a floor, not an inventory** (`countWorkspaceDirsAt(root) > 0`). Never let prose imply `ready=true` means all workspaces survived — the count assertion carries that claim.
2. **An inventory *echo* is not an inventory *assertion*.** A verdict line plus a prefix grep passes on `workspace_count=1` exactly as on `=8`. The comparison must bind the value, and it must fail closed when the baseline is missing.
3. **The host-side count must replicate `session-metrics.ts`'s four exclusions** (`.orphaned-*`, `.cron`, `lost+found`, non-directories). An unfiltered count inflates and can certify a real shrink green.
4. **A 403 readyz body is valid JSON.** Classify HTTP status *before* body shape, or a loopback-gate regression pages a sole-copy data-loss verdict.
5. **A wall-clock retry deadline plus a stubbed no-op `sleep` spins hot for the full deadline.** Bound by attempts.
6. **The harness `curl` stub serves both endpoints through one `case "$*"`** — and so does the sleep recorder. A shared index *or* a shared counter lets readyz retries satisfy a `/health` assertion. Index and assert per-arm.
7. **A test-only override seam is a coverage hole disguised as a convenience.** Both knobs need seam-unset companions; recording the sleep *argument* covers the interval one for free.
8. **`luks-monitor.sh` has no sourced-detection guard** (unlike `workspaces-cutover.sh:1896`). Sourcing it runs the whole probe. The guard is a prerequisite for the test seam, not an optional tidy-up.
9. **`luks-monitor.service:5`'s `RequiresMountsFor=/mnt/data` makes the daily unit inert in the reboot hazard.** Any future argument for flipping the flag ON must engage this, or it will re-derive a wrong answer from a plausible premise — as the strong-model consult did.
10. **`workspaces-luks-drift` is the sole paging op of nine.** Introducing a new op moves a signal from "pages the operator and blocks the wipe" to "pages nobody". Verify `issue-alerts.tf` and `soak:50` before adding one.
11. **`_vscrub`/`_wl_scrub` are log-injection sanitizers, not redactors.** Do not cite them as a name-redaction control.
12. **`/usr/local/bin/luks-monitor` on the live host is stale** until the next cutover-channel `install` (`:2271`). Verify deliberately tars the **repo** copy — the only reason the flag takes effect immediately.
13. **`workspaces-luks-verify.test.sh` does not test the verify workflow** — it covers `verify_byte_identity`.
14. **This PR's own comments contain both `/health` and `/api/health`.** Strip `^[[:space:]]*#` before counting greps — except for the workflow file, whose comments are in scope for the prose edit.
15. **Do not fold in #6808.** AC19 pins it.

## References

- Issue **#6807**; issue **#6808** (do not fold in).
- PR **#6701** / commit `ca85c30bc` (2026-07-19) — the correction whose sweep missed this workflow.
- Runs `29782780158` (successful cutover) and `29783424497` (verify failing on `app /api/health=307`).
- Learnings: `2026-07-19-the-harness-broke-the-rule-it-enforced-and-the-canary-could-not-fail.md`; `2026-07-20-i-swept-by-file-when-the-unit-of-truth-was-the-claim.md`; `2026-07-21-i-marked-one-block-and-not-its-twin-in-the-file-whose-purpose-was-removing-that-defect.md`; `2026-07-17-test-only-override-seam-leaves-prod-default-untested.md`; `best-practices/2026-07-18-deploy-script-tests-at-budget-timeout-and-infra-pr-ci-gotchas.md`; `2026-07-03-container-deep-readiness-st-dev-inert-use-write-probe.md`; `2026-07-06-cloudflare-universal-ssl-wildcard-depth-breaks-two-level-proxied-probe.md`.
- Precedents: `nic-wait-gate.test.sh:71-82,251-267` (recording sleep stub + triple assertion); `ci-deploy.test.sh:699` (`MOCK_SLEEP_NOOP`, broadening #6665); `workspaces-cutover.sh:1896` (sourced-detection guard); `workspaces-luks-harness.sh:173-181` (`MOUNTPOINT_RCS` sequenced knob).
- Code: `server/readiness.ts:54-60,81,112-117`; `server/session-metrics.ts:19-41`; `luks-monitor.service:5`; `workspaces-luks-emit.sh:33,62-73`; `sentry/issue-alerts.tf:1704-1740`; `uptime-alerts.tf:93`; `scripts/followthroughs/workspaces-luks-soak-6604.sh:50`.
- ADR-119 §(a) `:155-162`, `:234-240`; ADR-068 (deep-readiness pre-pool gate).
