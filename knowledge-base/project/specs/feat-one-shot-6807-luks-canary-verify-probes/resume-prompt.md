# Resume prompt — #6807 LUKS canary retry + verify readyz/inventory

Copy everything below the line into a fresh session.

---

Implement the full plan for #6807 — the probe defects that made a **successful** `/workspaces`
LUKS cutover report failure, plus the readyz coverage gap.

Plan:  `knowledge-base/project/plans/2026-07-21-fix-luks-canary-retry-and-verify-readyz-plan.md`
Tasks: `knowledge-base/project/specs/feat-one-shot-6807-luks-canary-verify-probes/tasks.md`
State: `knowledge-base/project/specs/feat-one-shot-6807-luks-canary-verify-probes/session-state.md`
Read all three before writing code. The plan is deep and its Sharp Edges are load-bearing.

## Where to work

Worktree `.worktrees/feat-one-shot-6807-luks-canary-verify-probes`, branch of the same name,
**draft PR #6809** already open. `cd` into the worktree first — the Bash tool's CWD drifts.
Two commits exist (init + session-state). Phase 0 is DONE and green; do not redo it.

## DO NOT re-run or roll back the cutover

The 2026-07-20 cutover **succeeded**. This is a probe-code fix only. There is no cutover to
re-dispatch and nothing to roll back. `ROLLBACK=1` right now would umount a healthy, live,
encrypted volume and destroy post-cutover user writes. The only workflow you dispatch is
`workspaces-luks-verify.yml` (read-only) — see Phase 2.9.

## State as of 2026-07-20 22:20 UTC

- **The cutover LANDED.** `/mnt/data` is `crypto_LUKS` on `/dev/mapper/workspaces`, escrow ok,
  header readable, `luks-monitor probe rc=0`. Confirmed by verify run `29783424497`.
- **C1 differential was clean**: `phase=gate total=8 ok=7 preexisting=1 src_only=0
  copy_corruption=0 probe_failed=0 unclassified=0 skipped=0 src_missing_on_dst=0`, every
  workspace `dst_rc=0`. The copy/verify path is proven — that is the thing the rehearsal
  could never establish.
- **No rollback fired, correctly.** `CANARY_OK=1` was set by the HOST canary (which passed),
  so `cleanup()` no-ops. Do not read "run failed" as "cutover failed".
- Prod: `app.soleur.ai/health` → `status=ok`, `build_sha=e567792fa60…` = head of `origin/main`.
- Cutover run `29782780158`; the two verify runs are `29783333844` (died on a transient
  Doppler-CLI `curl exit 35` — runner-side TLS flake, tells you nothing) and `29783424497`
  (reached the real assertion).

## The two defects

**A — `workspaces-luks-verify.yml:103` probes the wrong endpoint.** It asserts
`https://app.soleur.ai/api/health == 200`, but `/api/health` has no route, falls through
middleware and 307s to `/login`. Observed live: `app /api/health=307`. The workflow is
**structurally incapable of ever passing**. `/health` is correct (custom server,
`apps/web-platform/server/index.ts`, intercepts before Next routing).

**B — `workspaces-cutover.sh:663` `app_canary` is single-shot.** It fired ~590ms after
`docker start` and took Cloudflare's instant 521. `--max-time 20` does not help: the 521 is a
*fast* response, not a hang, so the budget is never consumed. Timeline: `docker start`
22:14:50.30 → container id .68 → `FATAL /health=521` .89. The app it declared dead is the app
that has served traffic ever since (`uptime=39` at 22:15:29).

## The trap that matters most — do not repeat it

`readyz ready=true` is a **floor, not an inventory**. `apps/web-platform/server/readiness.ts:81`:

```ts
const workspaces_populated = countWorkspaceDirsAt(root) > 0;
```

A cutover that preserved **1 of 8** sole-copy workspaces returns `ready=true`. My first
acceptance criterion said "verify passes ⇒ readyz ready=true" — which reproduces, one hop
later, the exact "green probe that cannot fail on the condition it names" bug this issue is
about. The plan therefore carries a **separate host-side inventory count**, exclusions mirrored
from `apps/web-platform/server/session-metrics.ts:19-41`, with a parity fixture. Keep it.

## Carry these corrections forward (each was asserted wrongly first, then measured)

1. The prior canary-endpoint fix landed **2026-07-19** (`ca85c30bc`, PR #6701) — one day before
   the cutover, which is *why* the sweep to the verify workflow was thin. Not "2026-06".
2. This does **not** break the soak drift check.
   `scripts/followthroughs/workspaces-luks-soak-6604.sh:46-48` reads Sentry, the heartbeat, and
   ADR-119 status directly and never invokes the verify workflow. The runbook §5 breakage is real;
   the soak claim was wrong.
3. `#6808` (unwired `WORKSPACES_LUKS_HEARTBEAT_URL`) **does** block the soak — the soak gates on
   heartbeat rows spanning ≥7d and none are being pushed, so the clock has not started. Keep it
   OUT of this PR (exit criterion E.2) but know it is the Phase 5 critical path.

## Phase 0 — already done, all green, do not redo

- Baseline suites `workspaces-luks-freeze`, `luks-monitor`, `workspaces-luks-verify`:
  **rc=0, 75 assertions.**
- `sleep` in `workspaces-luks-harness.sh` and non-comment `workspaces-cutover.sh`: **zero**
  (this is why plan task 3.1 must ADD a recording sleep stub — the seam does not exist).
- Budgets: verify `timeout-minutes: 15` (`workspaces-luks-verify.yml:38`); `deploy-script-tests`
  `timeout-minutes: 12` (`infra-validation.yml:298`).
- **Dead-man margin measured** (plan task 0.4): freeze/arm 22:11:49.09 → canary 22:14:50.31 =
  **181s**, against `DEAD_MAN_MIN=30` (1800s). Worst-case combined canary spend ~480s ⇒ 661s
  total, **~19 min margin**. Task 5.3's assertion has room.
- `grep -rn WORKSPACES_COUNT apps/web-platform/infra/` → **zero**. No baseline exists; task 2.8
  (seed `WORKSPACES_COUNT=8`) is required, not optional.

**New finding from that measurement:** `arm_dead_man` emits **no marker at all** — its timing had
to be inferred from the adjacent FREEZE banner. A host-local dead-man timer that is the
last-resort backstop during a freeze should emit arm/disarm events. Fold this into the Phase 1/5
emit work rather than filing it separately.

## Sequence

1. Re-verify Phase 0's numbers still hold if any time has passed (`git fetch origin main` first —
   main moves; a sibling landed the net-flow gate mid-session and needed a merge).
2. Phases 1 → 7 in order. **Phase 2 is a hard gate**: it dispatches
   `gh workflow run workspaces-luks-verify.yml --ref feat-one-shot-6807-luks-canary-verify-probes`
   (workflow ID `315308438`, already on the default branch, so `--ref` works pre-merge) and
   answers the ground-truth question — *is `/workspaces` actually populated?* Do not build the
   Phase 3-6 hardening against an unanswered Phase 2.
3. **Phase 2.11 STOP CONDITION.** `ready=false` + `WL_READYZ_WRITABLE=false` + capacity full/RO
   ⇒ **capacity incident**, not data loss. Count `< 8`, or `ready=false` on a healthy mount ⇒
   **data-recovery incident on sole-copy data**: halt and escalate to the operator immediately.
   Do not "fix" your way past a count shortfall.
4. Tests RED-first within each phase (`cq-write-failing-tests-before`), never deferred wholesale
   to Phase 6. Plan task 6.19 hygiene is not optional: no `cmd | grep -q` under `pipefail`
   (SIGPIPE 141 makes negatives fail **OPEN**), strip `^[[:space:]]*#` before body-greps, no
   standalone `[[ cond ]] && cmd` under `set -e`.
5. Full-suite exit gate before Phase 3 of `/work`: `bash scripts/test-all.sh` with an explicit
   `rc=$?` — note `test-all.sh` does **not** cover `apps/web-platform/infra/`, which gates via
   `.github/workflows/infra-validation.yml`, so register any new infra `.test.sh` there in the
   same commit or it silently never runs.
6. Ship: `Closes #6807` in the PR **body** (not title). Keep `WORKSPACES_LUKS_HEARTBEAT_URL` out
   of the diff.

## Open items — none block this work

- `#6808` — unwired heartbeat. Blocks the soak (and therefore Phase 5), not this PR.
- `#6754` — Phase 5 wipe gating on `skipped=0`. Note `skipped` was **1 → 0** between rehearsals
  because `scheduled-workspace-gc` swept a `soleur-cron-*` dir; `skipped=0` is transient, not
  stable, which is exactly the reshaping those correction comments call for.
- `#6766`, `#6774` — CI-gate gaps, unrelated.

## What "done" means

Merged PR closing #6807, with `workspaces-luks-verify.yml` passing against the **current,
already-cut-over** web-1, and its pass meaning the inventory count matched — not merely that a
200-always liveness probe returned 200.
