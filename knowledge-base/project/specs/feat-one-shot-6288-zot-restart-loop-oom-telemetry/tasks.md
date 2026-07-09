---
title: "Tasks — zot restart-loop OOM telemetry + memory remediation"
issue: 6288
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-09-fix-zot-restart-loop-oom-telemetry-plan.md
---

# Tasks — #6288 zot restart-loop OOM telemetry + memory remediation

Derived from the finalized (post-review) plan. Two slices, ONE PR, ONE immutable
`registry-host-replace` redeploy. Slice 1 (telemetry) is load-bearing regardless of Slice 2.

## Phase 0 — Preconditions (verify only, no prod write)

- [x] 0.1 Measure gzipped user_data headroom: `gzip -9 -c apps/web-platform/infra/cloud-init-registry.yml | base64 -w0 | wc -c` < 32768 (baseline 11,544).
- [x] 0.2 Record the exact `betterstack-query.sh --grep SOLEUR_ZOT_DISK` query on the default `$BS_TABLE` (already confirmed working — the plan's time-series was pulled with it).
- [x] 0.3 Confirm Hetzner swap state on the registry image (expect none; if present, `--memory-swap == --memory` is mandatory).
- [x] 0.4 ops-research: verify live Hetzner nbg1 pricing/stock for cx32 vs cpx31; feed verified € figures into the ledger row.

## Phase 1 — Slice 1: reporter telemetry (`cloud-init-registry.yml` `zot-disk-heartbeat.sh` `:148-184`)

- [x] 1.1 Add `mem_total_mb` (`MemTotal/1024`) + `mem_used_mb` (`(MemTotal−MemAvailable)/1024`) from `/proc/meminfo` (NOT `free`). `mem_total_mb` doubles as cx32-bump verification. *(User-Challenge on these two fields recorded in `decision-challenges.md` — retained per operator direction.)*
- [x] 1.2 Replace the standalone `:170` inspect with ONE inspect for all container fields: `docker inspect -f '{{.Id}} {{.RestartCount}} {{.State.Status}} {{.State.OOMKilled}} {{.State.ExitCode}}' zot` (adapted from `container-restart-monitor.sh:118-119`, NOT verbatim). Capture into one var, default whole to sentinels on empty. Emit `zot_restarts`, `state_status`, `oom_killed`, `exit_code`.
- [x] 1.2b Add `zot_anon_mb` from the container cgroup `memory.stat` `anon` (bytes → `/1048576`) at `$${CGROUP_ROOT}/system.slice/docker-$${ID}.scope/memory.stat` (cgroup **v2** — confirm on the cx32 image; Ubuntu 22.04+ defaults to v2). Define `CGROUP_ROOT` in the reporter as `$${CGROUP_ROOT:-/sys/fs/cgroup}` (never bare `${CGROUP_ROOT}`). Guard `|| =-1`.
- [x] 1.3 Add `oom_kills_5m` = `journalctl -k --since "5 min ago" 2>/dev/null | grep -ciE 'oom-kill|out of memory'` (`|| =0`).
- [x] 1.4 Add `zot_last_err` = `docker logs --tail 3 zot 2>&1 | tail -c 300 | tr '\n' ' '` (bounded 300 bytes, single-line; closes the non-OOM SSH dead-end).
- [x] 1.5 Add `boot_id` = `cat /proc/sys/kernel/random/boot_id` (disambiguates reused hostname across the replace).
- [x] 1.6 Append the 9 new fields to `LINE=` (`:171`), each `$${VAR}`-escaped (matches `$${USE:-}` `:159`).
- [x] 1.7 `registry-boot-guard.test.sh` (`:93` loop): assert each new field tied to the `LINE="SOLEUR_ZOT_DISK` string (not anywhere-in-file); add a per-new-var brace-escaping guard (`$${VAR}` present, `${VAR}` absent — scoped to new var names, NOT a blanket `${...}` grep).

## Phase 2 — Slice 2: remediation

- [x] 2.1 `docker run` (`:312-318`): add `--memory=7168m --memory-swap=7168m` from a named env-overridable const `ZOT_MEMORY_CAP` (mirrors ADR-062 `PROD_MEMORY_CAP:-4096m` at `ci-deploy.sh:112`; NO `--init` — that is a Node-container idiom, zot is a single Go process). Comment the headroom (8192 − ~1024 host overhead).
- [x] 2.2 `variables.tf:123`: `registry_server_type` default `cx23` → `cx32`; update the description (8 GB / #6288 memory rationale). amd64→amd64 (arch derivation unchanged).
- [x] 2.3 `expenses.md:20` (recurring-expense gate — BEFORE PR-ready): replace the stale `CAX11 (registry) / 4.32 / approved-not-billing` row with the cx32 row (plan Files-to-Edit text; ops-research € figures); bump frontmatter `last_updated`.
- [x] 2.x DEFERRED: `storage.dedupe=false` — NOT in this PR (undedupe-on-flip risk); revisit as a follow-up only if the soak still shows memory pressure.

## Phase 3 — Validation + follow-through

- [x] 3.1 PR body: include the runnable slope-based, `boot_id`-scoped, ≥2h soak decision rule (delta between rows) + the OOM decode table. Use `Ref #6288` (NOT `Closes`).
- [x] 3.2 Create `scripts/followthroughs/zot-restart-plateau-6288.sh` (exit 0 when the soak holds); add the `<!-- soleur:followthrough … secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->` directive + `follow-through` label to the #6288 tracker. (Sweeper already exports those secrets `:72-74` — no workflow edit.)
- [x] 3.3 Recurrence alarm: deepen-plan pins a concrete **Better Stack** alarm (NOT a `sentry_issue_alert`) OR splits it to a one-line follow-up issue. Do not ship hand-waved.

## Phase 4 — ADR / C4 (in-PR deliverables)

- [x] 4.1 Amend ADR-096: one factual host-sizing line in Consequences (`cax11`→`cx23`→`cx32` #6288). No new ADR; no ADR-062-adoption narration.
- [x] 4.2 Fix `model.c4:260` `zotRegistry` description (`cax11` → cx32 + memory-sizing note). Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 5 — Testing

- [x] 5.1 `bash apps/web-platform/infra/registry-boot-guard.test.sh` passes (all 9 fields + brace guard).
- [x] 5.2 Local reporter dry-run against a fake `/proc/meminfo` + stubbed `docker inspect`/`memory.stat`/`journalctl`; assert `LINE=` shape + sentinel guards + no single-brace leak.
- [x] 5.3 gzipped `cloud-init-registry.yml` < 32768.

## Phase 6 — Apply (post-merge, automatable)

- [ ] 6.1 `gh workflow run apply-web-platform-infra.yml -f apply_target=registry-host-replace -f reason='#6288 zot OOM telemetry + cx32 + memory cap'`; the `registry_host_replace_gate` confirms the scoped recreate (store volume preserved).
- [ ] 6.2 Verify private-net reachability post-replace (soft reboot if NIC-down/timeout).
- [ ] 6.3 Over the ≥2h soak (newest `boot_id`): confirm `zot_restarts` plateau + `zot_anon_mb` below cap + `exit_code≠137` + `oom_kills_5m=0` → follow-through auto-closes #6288. `mem_total_mb`≈8000 confirms the bump landed. Retroactive confirmation keyed on `zot_anon_mb`.
