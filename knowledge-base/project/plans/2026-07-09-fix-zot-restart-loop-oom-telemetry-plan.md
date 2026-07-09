---
title: "fix(infra): zot registry restart-loop — OOM telemetry + memory remediation"
issue: 6288
type: bug
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
created: 2026-07-09
branch: feat-one-shot-6288-zot-restart-loop-oom-telemetry
---

# 🐛 fix(infra): zot registry restart-loop — OOM telemetry + memory remediation (#6288)

## Overview

The zot OCI registry container on the dedicated Hetzner **cx23 (2 vCPU / 4 GB, amd64)** host restart-loops ~4/min. The disk-full was separately and definitively fixed by merged **PR #6284** (`pcent` 100→58 on the grown 60 GB volume). This is the **disk-independent residual** restart-loop: disk sits at 58–63% (NOT ENOSPC), yet `zot_restarts` climbs steadily.

**Live telemetry I pulled (`betterstack-query.sh --grep SOLEUR_ZOT_DISK`, 2026-07-09):**

| dt (UTC) | pcent | zot_restarts |
|---|---|---|
| 17:15 | 58 | 88 |
| 17:30 | 58 | 142 |
| 17:45 | 63 | 202 |
| 17:50 | 63 | 221 |
| 17:55 | 63 | 242 |
| 18:00 | 63 | 261 |

The **re-eval criterion is resolved**: restarts kept climbing at a steady ~4/min straight **through the ~17:53 first-gc window** (221 → 242 → 261 across 17:50/17:55/18:00), and `pcent` even rose 58→63 — the gc pass did **not** plateau the loop or reclaim store (plausibly the ~15-second crash cycle never lets a scan/gc complete). Per the issue's own rule ("still climbing past gc → host-undersizing → escalate the memory fix"), **both** slices are in scope, not just the telemetry enhancement.

The suspected cause is **OOM during zot's large-store (~35 GB) startup scan** on the 4 GB box. It is **unconfirmed** because the `SOLEUR_ZOT_DISK` reporter carries no memory / exit-reason field — that gap is exactly what Slice 1 closes. zot is **GHCR-fallback-covered** (post-merge zot-mirror push succeeded, `soleur-registry-disk-prd` heartbeat up, prod `/health` 200): this is reliability degradation, **not a live user-facing outage**.

Two slices, **one PR, one immutable host redeploy** (`registry-host-replace` dispatch):

- **Slice 1 (observability, unconditional / load-bearing regardless of Slice 2):** extend the `SOLEUR_ZOT_DISK` reporter so the next crash self-reports OOM vs non-OOM from Better Stack with **no SSH**.
- **Slice 2 (remediation, grounded in the pulled climbing-past-gc evidence):** apply the ADR-062 container-memory-cap pattern to zot and bump the host to **cx32 (4 vCPU / 8 GB, +~€2.1/mo)** for headroom above zot's scan working-set. *(A `storage.dedupe=false` lever was considered and **deferred**: the fable advisor consult flagged that flipping dedupe off on an existing deduped store triggers a background **undedupe rewrite** that inflates disk into the just-grown 60 GB headroom and storms I/O during the exact startup window being stabilized — it is a separately-measured follow-up, not part of this redeploy; see Alternatives.)*

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — the zot pull path has an **atomic GHCR fallback** (ADR-096); host cold-boots and CI zot-mirror pushes fall through to GHCR, and prod `/health` stays 200. A worse-sized `--memory` cap could make zot crash *deterministically* rather than intermittently, but the user-facing effect is still fully masked by GHCR.
- **If this leaks, the user's data is exposed via:** N/A — the registry stores OCI image blobs only (no PII, no user data, no schema/auth surface). The one new free-text field (`zot_last_err`, a bounded 300-byte tail of zot's own `info`-level log) carries container-runtime errors, not user data.
- **Brand-survival threshold:** `none`
- `threshold: none, reason:` the diff touches sensitive infra paths (`apps/web-platform/infra/*`), but the zot registry is GHCR-fallback-covered on every pull path (ADR-096) — a broken or mis-sized fix degrades registry *redundancy*, never a user-reachable surface, through the Phase-5 GHCR-retirement soak.

## Research Reconciliation — Premise vs. Codebase

| Premise (issue / feature description) | Reality (verified) | Plan response |
|---|---|---|
| Disk-full fixed by the merged 2026-07-09 volume-grow work | **PR #6284 MERGED 16:50 UTC**; #6247 is the (closed) tracking *issue*, not a PR | Premise holds; this is a separate PR (not bolted onto #6284). |
| Restarts may plateau after the 1h gc (~17:53) | **Did NOT plateau** — climbed 221→261 through the gc window; pcent rose 58→63 | Re-eval criterion MET → Slice 2 memory fix is in scope now, not deferred. |
| `docker run --name zot` has no `--memory` limit | Confirmed, `cloud-init-registry.yml:312-318` (no `--memory`/`--memory-swap`) | Slice 2 adds them, mirroring **ADR-062** (accepted precedent for the web-platform container). |
| Reporter has no memory / exit-reason field | Confirmed, `LINE=` at `cloud-init-registry.yml:171` (pcent/fs/resize/zot_restarts/ping_rc only) | Slice 1 adds mem + exit-reason fields. |
| `registry_server_type` = cx23 (small) | Confirmed, `variables.tf:123` (cx23 = 2 vCPU / **4 GB**, amd64) | Slice 2 bumps to cx32 (8 GB). ADR-096:32 & `model.c4:260` still name `cax11` (stale) — corrected in the ADR/C4 section. |
| OOM confirmable once the field lands | **Partly** — `.State.OOMKilled` alone is unreliable under cgroup v2 (ADR-062:30-33); `exit_code=137` is the primary tell; point-sampling at 4/min mostly catches `Status=running` (false-negative); host `mem_used` is page-cache-confounded (fable Change 1) | Reporter emits `state_status` + `exit_code` + a journald `oom_kills_5m` window backstop (not `oom_killed` alone) + `zot_anon_mb` (container anonymous RSS) as the confirmation signal (see Hypotheses). |
| Expense ledger reflects the registry host | **Ledger drift** — `expenses.md:20` still says `CAX11 (registry) / 4.32 / approved-not-billing`; live host is cx23 billing | Slice 2 corrects the row AND bumps for cx32 (recurring-expense gate). |

## Hypotheses — OOM decode table (the diagnostic core)

The reporter must let an operator decide OOM-vs-not from Better Stack alone. Point-sampling `docker inspect` on a 4/min crash loop mostly catches `Status=running` (exit fields stale) — so **loop DETECTION keys on `zot_restarts` delta (monotonic, reliable); the exit-reason fields are for CAUSE attribution only**, backed by a journald window counter that survives the sampling race.

| `exit_code` | `oom_killed` | `oom_kills_5m` | Interpretation |
|---|---|---|---|
| `137` | `false` | `>0` | **Host-level (kernel) OOM** — the current uncapped 4 GB hypothesis. |
| `137` | `true` | `>0` | **cgroup OOM** — Slice-2 `--memory` limit fired and *contained* it (host services + telemetry survive). |
| `0` (Status=running) | `false` | `0` | Caught mid-scan; exit fields not meaningful this sample — rely on `zot_restarts` slope + next sample. |
| `≠137` (exited/restarting) | `false` | `0` | **NOT OOM** → read `zot_last_err` (bounded log tail) — config/port-bind/storage-perm/panic. No SSH dead-end. |

**Retroactive confirmation (Slice 1+2 ship together) — key on `zot_anon_mb`, NOT host `mem_used_mb` (fable Change 1):** a ~35 GB store scan pins **page cache**, so host `mem_used_mb` sits near-total on cx32 regardless of whether zot's *anonymous* memory ever starved — using host `mem_used` to "confirm OOM" auto-confirms unconditionally (a rubber stamp). The confirmation signal is the zot **container's anonymous RSS** (`zot_anon_mb`, from the container cgroup `memory.stat` `anon`, which excludes reclaimable page cache): if it peaks **above ~3.5 GB** (near what the old 4 GB host physically had minus overhead), that confirms the 4 GB host starved zot. If `zot_anon_mb` peaks **well below** that, the OOM diagnosis was wrong → route to the `zot_last_err` (non-OOM) branch. Host `mem_used_mb`/`mem_total_mb` stay in the payload as host-pressure *context*, not the confirmation test.

## Implementation Phases

### Phase 0 — Preconditions (verify, no prod write)

0.1 Confirm gzipped user_data headroom after the reporter grows: `gzip -9 -c apps/web-platform/infra/cloud-init-registry.yml | base64 -w0 | wc -c` stays well under 32768 (ADR-080 cap). Baseline is 11,544 / 32,768 → ~21 KB headroom; the additions are a few lines, so ample.
0.2 Confirm the `SOLEUR_ZOT_DISK` rows land in the table `betterstack-query.sh` defaults to (they do — the Overview time-series was pulled with the default `$BS_TABLE`). Record the exact `--grep SOLEUR_ZOT_DISK` query used for the validation rule.
0.3 Confirm Hetzner **swap** state on the registry image (Hetzner cloud images typically have none). If swap exists, `--memory-swap == --memory` is required for a deterministic cgroup-OOM (else the container swaps instead of OOM-killing).
0.4 `ops-research` verifies live Hetzner nbg1 catalog pricing/stock for **cx32** vs cpx31 (satisfies the `variables.tf` "verify pricing before budget decisions" mandate).

### Phase 1 — Slice 1: reporter telemetry (load-bearing, unconditional)

Edit `zot-disk-heartbeat.sh` inside `cloud-init-registry.yml` (script body `:148-184`). Add fields to `LINE=` (`:171`), each guarded with the existing `[ -n … ] || =<sentinel>` pattern used by `ZOT_RESTARTS` (`:170`). templatefile escaping: any **brace** shell var must be doubled (`$${MEM_USED:-}`), matching `$${USE:-}` at `:159`; Go-template `{{.State.X}}` is safe.

1.1 **Host memory** from `/proc/meminfo` (NOT `free` — `procps` is not in the `packages:` list `:16-22`): `mem_total_mb = MemTotal/1024`, `mem_used_mb = (MemTotal − MemAvailable)/1024`. `mem_total_mb` self-verifies the cx32 bump landed on a no-SSH host (~8000 vs ~4000); `mem_used_mb` is host-pressure *context* only (see 1.2b — it is NOT the confirmation signal). **User-Challenge (kept):** the issue's proposed work explicitly names `mem_used_mb / mem_total_mb`, but three reviewers (fable, DHH, simplicity) recommend cutting them as page-cache-confounded / a re-emitted constant. Fields RETAINED (operator's stated direction is the default); the "cut them" recommendation is recorded in `decision-challenges.md` for `/ship` to surface as an `action-required` issue.
1.2 **Single** `docker inspect` for ALL container fields (folds in `RestartCount` so `zot_restarts` comes from the same call — replaces the separate inspect at `:170`, genuinely one inspect/tick), defaulted whole to sentinels on empty (mid-restart returns empty — same guard as `zot_restarts`). **Adapted from** `container-restart-monitor.sh:118-119` (whose template is `--format '{{.Id}} {{.RestartCount}} {{.State.OOMKilled}} {{.State.ExitCode}}'`; we add `.State.Status`), NOT verbatim: `docker inspect -f '{{.Id}} {{.RestartCount}} {{.State.Status}} {{.State.OOMKilled}} {{.State.ExitCode}}' zot`. Emit `zot_restarts`, `state_status`, `oom_killed`, `exit_code`; keep the container `Id` (`$${ID}`) for 1.2b.
1.2b **Container anonymous RSS** (the retroactive-confirmation signal, fable Change 1): `zot_anon_mb` = the container cgroup's true anonymous RSS from `memory.stat` `anon` (excludes reclaimable page cache), read at `$${CGROUP_ROOT}/system.slice/docker-$${ID}.scope/memory.stat` — mirroring how `container-restart-monitor.sh:129-132` reads `memory.events` from that exact path. Define `CGROUP_ROOT` in the reporter as `$${CGROUP_ROOT:-/sys/fs/cgroup}` (Kieran P2: a single-brace `${CGROUP_ROOT}` would fail `terraform plan` as a TF-var interpolation). `memory.stat` `anon` is in **bytes** → `/1048576` for `_mb`. Guard `|| =-1`.
1.3 **journald OOM window backstop** (survives the point-sampling race, P0-1): `oom_kills_5m = journalctl -k --since "5 min ago" 2>/dev/null | grep -ciE 'oom-kill|out of memory'` (bounded, `|| =0`; use the `"5 min ago"` form or an epoch anchor `@$((NOW-300))` per `container-restart-monitor.sh:129`, NOT the unverified `-5min` token — Kieran P2). Kernel OOM-killer entries persist for the window even when `inspect` catches `running`.
1.4 **Non-OOM branch escape** (P0-3, closes the `hr-no-ssh-fallback` dead-end): `zot_last_err = docker logs --tail 3 zot 2>&1 | tail -c 300 | tr '\n' ' '` (bounded 300 bytes; zot logs at `info`, `:128`, so secret-exposure risk is low; single-line for the log marker).
1.5 **Boot discriminator** (P1-2): `boot_id = cat /proc/sys/kernel/random/boot_id` — the immutable redeploy reuses the terraform hostname, so `boot_id` is what cleanly separates old-host from new-host events for the automated decision rule.
1.6 Update the structural test `registry-boot-guard.test.sh` (field loop `:93`): add `mem_used_mb= mem_total_mb= zot_anon_mb= state_status= oom_killed= exit_code= oom_kills_5m= zot_last_err= boot_id=` to the `for f in` list — but tie each assertion to the `LINE="SOLEUR_ZOT_DISK` string specifically (the existing `:93` form `grep -qF '${f}'` matches the token *anywhere* in `$CI` including comments → a field named only in a comment false-passes; Kieran P2). **Brace-leak guard (Kieran P1):** do NOT blanket-grep for `${...}` — the reporter legitimately contains TF interpolations `${disk_heartbeat_url}` (`:156`), `${betterstack_ingest_url}` (`:176`), `${zot_pull_user}`. Scope the guard to the NEW shell-var names only: for each (`MEM_USED`, `MEM_TOTAL`, `ZOT_ANON`, `CGROUP_ROOT`, `ID`, …) assert `$${<VAR>` present AND single-brace `${<VAR>` absent. (The test greps the RAW `$CI`, not a templatefile render — do not say "rendered".)

### Phase 2 — Slice 2: remediation (grounded in climbing-past-gc evidence)

2.1 **Container memory cap** (ADR-062 pattern, unconditional). Add to `docker run` (`:312-318`): `--memory <cap> --memory-swap <cap>` (NO `--init` — simplicity review: zot is a single Go process that handles SIGTERM as PID 1 and spawns no children, so ADR-062's Node-container `--init` zombie-reaping/signal-forwarding buys nothing here). **Sizing rule (P1-4):** `cap = new_host_RAM − documented_host_headroom`, NOT a guess at the scan working-set (a cap below the legit scan peak manufactures the very OOM it diagnoses — ADR-062 AC2). Registry host runs only zot + cron + doppler + sshd + OS (~0.7–1 GB overhead — lighter than ADR-062's 1.3 GB web host, which also runs inngest+vector). On an 8 GB cx32 → **`--memory=7168m --memory-swap=7168m`** (7 GB working room, well above the >~3.5 GB the 4 GB host evidently starves on). `--memory-swap == --memory` guarantees a deterministic cgroup-OOM (no swap-thrash masquerading as slowness). Cap value from a named env-overridable constant, mirroring ADR-062's `PROD_MEMORY_CAP` idiom.
2.2 **Host bump** cx23 → **cx32 (4 vCPU / 8 GB, amd64)**: `variables.tf:123` default `cx23` → `cx32`. amd64→amd64, so `local.registry_arch` and the Doppler-arch download/checksum are unchanged (no cloud-init image-arch churn — confirmed by COO).
2.3 **Expense ledger** (`expenses.md:20`, recurring-expense gate — update BEFORE PR-ready): replace the stale `CAX11 (registry) / 4.32 / approved-not-billing` row with the cx32 row (text in Files to Edit), correcting name/status/amount and recording the +~€2.1/mo delta; bump frontmatter `last_updated`. Swap in ops-research-verified € figures before ready.

*(Deferred from Slice 2: `storage.dedupe=false`. Fable Change 2 — flipping dedupe off on an existing deduped store triggers zot's background undedupe rewrite, risking disk re-inflation into the just-grown 60 GB headroom + an I/O storm during the startup window, and it shifts the working-set the 7168m cap + `zot_anon_mb` confirmation are sized against. cx32 + the cap are a sufficient remediation slice; dedupe is a separately-measured follow-up if the soak still shows memory pressure — see Alternatives.)*

### Phase 3 — Validation rule + follow-through (no SSH, no dashboard eyeball)

3.1 Write the **slope-based, boot_id-scoped, soak-gated decision rule** as a runnable `betterstack-query.sh` snippet in the PR body (delta between consecutive rows, never a single row):
- **FIXED:** across a soak window ≥ ~2h post-deploy (spans the full startup scan + first `gcInterval=1h` + `retention.delay=2h`), for the newest `boot_id`: `zot_restarts` delta ≈ 0 between events, `exit_code≠137`, `oom_kills_5m=0`, and `zot_anon_mb` peaks comfortably below `--memory`.
- **STILL BROKEN:** `zot_restarts` climbs monotonically, OR `exit_code=137` (any `oom_killed`), OR `oom_kills_5m>0`, OR `zot_anon_mb` pins near the cap → read the decode table + `zot_last_err`; escalate host size.
3.2 **Soak follow-through enrollment** (§2.9.1): create `scripts/followthroughs/zot-restart-plateau-6288.sh` (exit 0 when the soak holds) + the tracker `<!-- soleur:followthrough … -->` directive + `follow-through` label. **No sweeper secret edit needed** — `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` are already exported by `scheduled-followthrough-sweeper.yml:72-74`; the directive just declares `secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD` (the same creds `betterstack-query.sh` needs). Do NOT close #6288 on the immediate post-boot check.
3.3 **Recurrence alarm** (P1-3 — covers the restart-loop liveness gap the disk heartbeat structurally cannot, P2-5). NOTE: #6278's `zot_mirror_fallback_rate` is a *Sentry* issue-alert on CI/cloud-init events — a **different data source**; `SOLEUR_ZOT_DISK` lives in Better Stack Logs, so this is a **Better Stack** alarm (on `exit_code=137` seen, or `zot_restarts` climbing across N consecutive events), NOT a `sentry_issue_alert`. deepen-plan must either (a) pin the concrete Better Stack alarm resource + threshold, or (b) **split it to a one-line follow-up issue** with re-eval criteria (per `wg-when-deferring-a-capability`) — do NOT ship a hand-waved alarm (DHH + simplicity). Sits outside the numbered ACs.

### Phase 4 — Apply (post-merge, automatable dispatch)

4.1 The registry host is **excluded from the per-PR auto-apply `-target=` allow-list** (an `OPERATOR_APPLIED_EXCLUSION` per ADR-096:110 / the `.tf` comments — realized as the dispatch-only `registry_host_replace` job at `apply-web-platform-infra.yml:1649`, not a literal exclusion list in that file) — merging changes nothing on prod. Dispatch the existing guarded immutable-redeploy: `gh workflow run apply-web-platform-infra.yml -f apply_target=registry-host-replace -f reason='#6288 zot OOM telemetry + cx32 + memory cap'`. The `registry_host_replace_gate` verifies the plan is the exact scoped recreate (zot store volume preserved, private NIC re-created, deny-all firewall re-attached). This is automatable (`gh workflow run`), not an operator-manual step.
4.2 Post-replace, verify private-net reachability (a fresh Hetzner host can boot with the private NIC down — `2026-07-07-immutable-redeploy.md`; a soft reboot brings it up). The `registry-host-replace` job's `-target` set already includes `hcloud_server_network.registry` + `hcloud_firewall_attachment.registry`.

## Files to Edit

- `apps/web-platform/infra/cloud-init-registry.yml` — reporter fields (`:171` + script `:148-184`); `docker run` `--memory/--memory-swap` (`:312-318`). *(No `dedupe` change — deferred.)*
- `apps/web-platform/infra/variables.tf` — `registry_server_type` default `cx23` → `cx32` (`:123`); update its description (4 GB → 8 GB, #6288 memory rationale).
- `apps/web-platform/infra/registry-boot-guard.test.sh` — extend the `SOLEUR_ZOT_DISK` field loop (`:93`) with the 9 new fields; add the `${...}`-single-brace-leak negative assertion.
- `knowledge-base/operations/expenses.md` — replace row 20 with the cx32 row (text below); bump `last_updated`.
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` — amend for host-sizing evolution + ADR-062 cap adoption (see ADR/C4 section).
- `knowledge-base/engineering/architecture/diagrams/model.c4` — correct the `zotRegistry` description (`:260`, `cax11` → cx32 + memory-sizing note).

Ledger row text (Phase 2.3, swap € figures for ops-research-verified values before ready):
```
| Hetzner CX32 (registry) | Hetzner | hosting | 8.20 | active | 2026-08-01 | Dedicated amd64 host (`hcloud_server.registry`, cx32: 4 vCPU x86 / 8 GB RAM, nbg1) for the self-hosted zot registry + attached 60 GB `hcloud_volume` (`/var/lib/zot`). BUMPED cx23 (4 GB) → cx32 (8 GB) (#6288) to fix a zot restart-loop (~4/min) OOM-ing during the boot scan of the ~35 GB store on the 4 GB box (non-ENOSPC; SOLEUR_ZOT telemetry — restarts climbed past the gc window). ~€7.59/mo vs prior ~€5.49/mo = +~€2.1/mo; USD estimate at ~1.08 FX — VERIFY current Hetzner catalog (cx32 vs cpx31) via ops-research + next invoice. Immutable host replace (server_type change per hr-prod-host-config-change-immutable-redeploy); 60 GB volume persists (re-attached, no re-backfill). Corrects the prior row (stale cax11 / approved-not-billing; live host is cx23 in nbg1, billing since provision). DPA: existing Hetzner DPA. See #6288, #6122, ADR-096; disk-grow #6284 |
```

## Files to Create

- `scripts/followthroughs/zot-restart-plateau-6288.sh` — soak probe (exit 0 when `zot_restarts` plateaus + no OOM signal across the window, newest `boot_id`).

## Observability

```yaml
liveness_signal:
  what: "Better Stack heartbeat `soleur-registry-disk-prd` (absence-based, disk<85%) + the SOLEUR_ZOT_DISK structured self-report (enriched with mem/anon-RSS/OOM/exit fields this PR)"
  cadence: "5 min (cron) / heartbeat period 900s grace 600s"
  alert_target: "Better Stack (heartbeat) + the new zot_restarts-slope / exit_code=137 recurrence alarm (Phase 3.3) -> operator"
  configured_in: "apps/web-platform/infra/cloud-init-registry.yml:148-193 (reporter+cron); zot-registry.tf:378-396 (heartbeat)"
error_reporting:
  destination: "Better Stack Logs (isolated soleur-registry/prd source), grep marker SOLEUR_ZOT_DISK; recurrence alarm mirrors the #6278 sentry_issue_alert pattern"
  fail_loud: "zot_restarts climbing across events, OR exit_code=137, OR oom_kills_5m>0, OR zot_anon_mb near cap, OR zot_last_err non-empty on the non-OOM branch — all readable via betterstack-query.sh (no ssh)"
failure_modes:
  - mode: "zot OOM restart-loop (host-level, current)"
    detection: "in-surface: exit_code=137 + oom_killed=false + oom_kills_5m>0 + zot_anon_mb high in SOLEUR_ZOT_DISK; loop keyed on zot_restarts delta"
    alert_route: "Better Stack recurrence alarm -> operator; GHCR fallback covers serving meanwhile"
  - mode: "zot cgroup-OOM (post --memory cap, contained)"
    detection: "exit_code=137 + oom_killed=true + oom_kills_5m>0 (container-scoped; host services + telemetry survive)"
    alert_route: "same alarm; signals the cap fired and host is protected"
  - mode: "zot non-OOM crash (config/port/storage/panic)"
    detection: "state_status in {exited,restarting} + exit_code!=137 -> zot_last_err bounded log tail (no SSH)"
    alert_route: "operator reads zot_last_err from Better Stack; routes off the OOM hypothesis"
  - mode: "reporter itself dark (egress fail / token unset)"
    detection: "existing: retry-once then journald breadcrumb; ping_rc carried into next successful post"
    alert_route: "missing SOLEUR_ZOT_DISK rows in Better Stack -> heartbeat absence"
logs:
  where: "Better Stack Logs (SOLEUR_ZOT_DISK rows); zot container -> journald on-host (--log-driver journald); kernel OOM -> journalctl -k"
  retention: "Better Stack source retention (ClickHouse warehouse); on-host journald is ephemeral per host lifetime"
discoverability_test:
  command: "doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 3h --grep SOLEUR_ZOT_DISK"
  expected_output: "SOLEUR_ZOT_DISK rows (newest boot_id) with flat zot_restarts across events, exit_code=0/!=137, oom_kills_5m=0, zot_anon_mb well below the --memory cap"
```

**Affected-surface (§2.9.2):** the registry is a deny-all-ingress, no-SSH **blind surface**. Every `detection` above is an **in-surface** probe emitted FROM the host's own cron, and the field set (`exit_code` / `oom_killed` / `oom_kills_5m` / `state_status` / `zot_last_err` / `zot_anon_mb` / `mem_used_mb`↔`mem_total_mb` / `boot_id`) **discriminates all competing hypotheses in one event** (host-OOM vs cgroup-OOM vs non-OOM vs reporter-dark vs mid-scan-sample), and `zot_anon_mb` separates real anonymous-memory pressure from page-cache noise. Pre-existing masking noted (P2-5): the disk-liveness heartbeat stays GREEN during a crash loop (it fires only on disk<85%) — the new `zot_restarts`-slope alarm is what covers restart-loop liveness that disk-liveness structurally cannot.

**Soak follow-through (§2.9.1):** script `scripts/followthroughs/zot-restart-plateau-6288.sh`; directive `<!-- soleur:followthrough script=scripts/followthroughs/zot-restart-plateau-6288.sh earliest=<deploy+2h> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->` on the #6288 tracker + `follow-through` label; secrets already exported by `scheduled-followthrough-sweeper.yml:72-74` (no workflow edit).

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/variables.tf` — `registry_server_type` default `cx23`→`cx32` (no new variable; no new `TF_VAR_*`, no new secret).
- `apps/web-platform/infra/cloud-init-registry.yml` — rendered by `templatefile()` in `zot-registry.tf`; reporter fields + `docker run --memory/--memory-swap`. No new provider, no new sensitive var.
- No new Terraform root; no new Doppler secret (the reporter reuses the existing `BETTERSTACK_LOGS_TOKEN` in `soleur-registry/prd`; the 3-secret boot-isolation self-check `:298-303` is unchanged).

### Apply path
(b/c hybrid) **Immutable host replace** via the existing guarded `registry-host-replace` `workflow_dispatch` — the registry host is deliberately EXCLUDED from per-PR auto-apply, so nothing touches prod on merge. `gh workflow run apply-web-platform-infra.yml -f apply_target=registry-host-replace -f reason='#6288 …'`. server_type change is `ForceNew` -> the same `-replace` recreate. **Downtime/blast-radius:** registry briefly down during the replace; **GHCR atomic fallback covers all pulls** (non-release-blocking per #6276); the **60 GB zot store volume persists** (re-attached, no re-backfill) -> the new host scans the SAME ~35 GB store, which is the fix's validation surface.

### Distinctness / drift safeguards
- Registry is a **prd-only singleton** (no dev/prd split for this host). The `registry_host_replace_gate` (`tests/scripts/lib/registry-host-replace-gate.sh`, no `[ack-destroy]` bypass) fails-closed unless the plan is exactly the scoped recreate with the store volume preserved. `-replace` must `-target` the private NIC + firewall attachment (dependents, not dependencies — `2026-07-07-immutable-redeploy.md`); the `registry-host-replace` job already lists them.
- Fresh-host private-NIC-down verification post-replace (soft reboot if timeout vs refused).

### Vendor-tier reality check
Hetzner has no free-tier gate on server types. cx32 ≈ €7.59/mo (verify live catalog via ops-research); cpx31 is pricier with no store-and-serve benefit -> cx32 chosen.

## Architecture Decision (ADR/C4)

An architectural decision is touched (host-sizing extension of ADR-096 + adoption of the ADR-062 memory-cap pattern on a new container). Both are **extensions of accepted decisions**, not new/reversed ones — so the deliverable is a minimal amendment + a C4 description correction, in THIS PR (not a deferred issue).

### ADR
- **Amend ADR-096** — line 32's Decision names the host as `cax11` (ARM64) *only* (Kieran: not `cax11/cx23`), a size reality has already diverged from (live = cx23) and this PR bumps again to cx32. Add **one factual host-sizing line** to its Consequences: `cax11`(planned)→`cx23`(live, stock)→**`cx32`(#6288, 8 GB for zot large-store-scan memory headroom)**. Keep it to that one line — applying the already-accepted **ADR-062** memory-cap pattern to a new container needs no fresh decision narration (DHH + simplicity: the code + ACs document it). No new ADR — the self-hosted-zot architecture is unchanged.

### C4 views
Read all three model files (`model.c4`, `views.c4`, `spec.c4`). **No** new external actor / external system / data-store / access-relationship — the `zotRegistry` element (`model.c4:258`), the `hetzner→zotRegistry` edge (`:376`), and the view includes (`views.c4:14,36`) are all unchanged in structure. The only edit is a **description correctness fix**: `model.c4:260` says "dedicated Hetzner host (**cax11**, volume-backed)" — already stale (live is cx23), and cx32 after this PR. Update to the actual type + the memory-sizing note. No `views.c4 include` change (element already rendered). Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after the edit.

### Sequencing
The decision is true at deploy (Slice 2 applies the sizing + cap in the same redeploy). ADR amendment authored now describing the adopted state; not postponed.

## Domain Review

**Domains relevant:** Operations, Engineering (CTO carry-forward)

### Operations
**Status:** reviewed (COO)
**Assessment:** cx23→cx32 is +~€2.1/mo (cx32 ≈ €7.59/mo; cpx31 pricier, no benefit). Recurring-expense gate applies → `expenses.md:20` must be corrected + bumped BEFORE PR-ready (it currently stale-names the host `cax11`/`approved-not-billing`). Immutable replace is amd64→amd64 (no arch churn); GHCR-covered blast radius; volume persists. Delegations: **ops-research** (verify live cx32 pricing/stock), **ops-advisor** (apply the ledger row), **CTO** (owns the RAM-vs-cap design + the Terraform change).

### Engineering (CTO)
**Status:** carry-forward to plan-review CTO panel
**Assessment:** the RAM-bump vs `--memory` cap vs deferred `storage.dedupe=false` levers are a technical-design call the COO explicitly deferred to CTO. This PR ships two (cap = attribution+containment per ADR-062; cx32 = durable headroom); the fable advisor consult **deferred** dedupe (undedupe-on-flip risk during the startup window). Plan-review CTO/architecture-strategist to confirm the combination + the `--memory` value (7168m) + the deferral.

### Product/UX Gate
Not relevant — **Product NONE**. No `## Files to Edit`/`## Files to Create` path matches a UI-surface term/glob (all are `infra/*.{tf,yml,sh}`, `knowledge-base/*.md`, `*.c4`, `scripts/followthroughs/*.sh`). Infrastructure/observability change; no user-facing surface.

## Acceptance Criteria

### Pre-merge (PR)
1. Reporter (`cloud-init-registry.yml`) emits every new field in `SOLEUR_ZOT_DISK`: `mem_used_mb`, `mem_total_mb`, `zot_anon_mb`, `state_status`, `oom_killed`, `exit_code`, `oom_kills_5m`, `zot_last_err`, `boot_id` — each with a sentinel guard on empty/absent.
2. `mem_used_mb`/`mem_total_mb` come from `/proc/meminfo` (`MemTotal` / `MemTotal−MemAvailable`); `zot_anon_mb` from the container cgroup `memory.stat` `anon` (bytes → `/1048576`) via the `Id` from the single inspect; `CGROUP_ROOT` defined `$${CGROUP_ROOT:-/sys/fs/cgroup}` (no bare `${CGROUP_ROOT}`).
3. All container fields (`zot_restarts`, `state_status`, `oom_killed`, `exit_code`) are captured from ONE `docker inspect` and defaulted whole to sentinels on empty (mid-restart) — the pre-existing separate inspect at `:170` is folded in (no double inspect).
4. `oom_kills_5m` reads `journalctl -k --since -5min` (window backstop); `zot_last_err` is a bounded ≤300-byte single-line tail of `docker logs --tail 3 zot`.
5. `docker run` carries `--memory=<cap> --memory-swap=<cap>` (no `--init`) from a named env-overridable constant; `--memory-swap == --memory`; cap = `host_RAM − documented_headroom` (7168m on cx32), with the headroom named in a comment.
6. `variables.tf` default is `cx32`; its description states the 8 GB / #6288 memory rationale; arch derivation unchanged (amd64).
7. `registry-boot-guard.test.sh` asserts all 9 new reporter fields (each tied to the `LINE="SOLEUR_ZOT_DISK` string, not anywhere-in-file) AND a **per-new-var** brace-escaping guard (`$${VAR}` present, single-brace `${VAR}` absent — scoped to the new var names, NOT a blanket `${...}` grep that the legitimate `${disk_heartbeat_url}`/`${betterstack_ingest_url}` interpolations would trip); `bash apps/web-platform/infra/registry-boot-guard.test.sh` passes. (No `dedupe` assertion change — deferred.)
8. gzipped `cloud-init-registry.yml` render < 32768 bytes.
9. `expenses.md:20` corrected to the cx32 row (name/status/amount) with the +€2.1/mo delta and ops-research-verified figures; `follow-through` tracker + `scripts/followthroughs/zot-restart-plateau-6288.sh` created.
10. ADR-096 amended (host-sizing evolution + ADR-062 adoption); `model.c4:260` description corrected; `c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
11. PR body carries the runnable slope-based validation snippet + the OOM decode table. Use `Ref #6288` (NOT `Closes` — closure is post-soak, ops-remediation class).

### Post-merge (operator/automatable)
12. Dispatch `registry-host-replace` (`gh workflow run …`, automatable); the guard confirms the scoped recreate; verify private-net reachability post-replace.
13. Within the ≥2h soak (newest `boot_id`): `zot_restarts` delta ≈ 0, `exit_code≠137`, `oom_kills_5m=0`, `zot_anon_mb` well below the cap → the soak follow-through auto-closes #6288. If STILL climbing / `exit_code=137` / `oom_kills_5m>0` / `zot_anon_mb` near cap → read the decode table + `zot_last_err`; escalate host size or route off the OOM hypothesis. **Retroactive confirmation** keys on `zot_anon_mb` (NOT host `mem_used_mb`): a peak >~3.5 GB confirms the 4 GB host starved zot; well below flags the OOM diagnosis as wrong → non-OOM branch. `mem_total_mb` self-verifies the cx32 bump landed (reads ~8000 on a no-SSH host, not ~4000).

## Test Scenarios

- **Structural (CI, no host):** `registry-boot-guard.test.sh` asserts every new field literal and the no-single-brace-leak guard. c4 syntax/render tests pass.
- **Reporter logic (local shell):** render the templatefile output and dry-run the reporter against a fake `/proc/meminfo` + a stubbed `docker inspect`/`memory.stat`/`journalctl` to confirm sentinel guards and the `LINE=` shape; assert no `${...}` leaked.
- **Live (post-deploy, no SSH):** the Phase-3 `betterstack-query.sh` slope rule over the soak window; the follow-through probe exercises the same rule on schedule.

## Alternatives Considered

| Alternative | Verdict |
|---|---|
| Telemetry-only first, then a SECOND redeploy for the memory fix after observing OOM | Rejected as primary (fable-confirmed): two redeploys + an operator observe-loop between them drags a P1 and defers the fix; the re-eval criterion is **already objectively met** (climbing past gc from the pulled data), and Slice 1 telemetry ships in the SAME redeploy so it validates the concurrent fix (`zot_anon_mb` bounded, restarts plateau) or, if wrong, self-reports via the decode table. Documented as the fallback if plan-review prefers strict telemetry-first. |
| `--memory` cap on the CURRENT 4 GB host (no bump) | Rejected: host overhead (~1 GB) leaves ≤~3 GB for a scan that evidently needs >~3.5 GB → the cap would manufacture cgroup-OOM churn (ADR-062 AC2). No safe cap exists without more RAM. |
| `storage.dedupe=false` in this PR (~€0 working-set lever) | **Deferred** (fable Change 2): flipping dedupe off on an existing deduped store triggers zot's background **undedupe rewrite** — inflates disk into the just-grown 60 GB headroom, storms I/O during the exact startup window being stabilized, and shifts the working-set the 7168m cap + `zot_anon_mb` confirmation are sized against. cx32 + cap is a sufficient remediation slice; revisit dedupe as a separately-measured follow-up (verify zot's flip-behavior on a store copy first) only if the soak still shows memory pressure. |
| cpx31 (also 8 GB) instead of cx32 | Rejected: materially pricier (~€15/mo) with no store-and-serve benefit (COO). |
| Ship zot container logs to Better Stack continuously (full log pipeline) | Rejected as overkill: the bounded `zot_last_err` tail on the non-OOM branch closes the SSH dead-end without a new log pipeline. |
| Retroactive confirmation on host `mem_used_mb` | Rejected (fable Change 1): a 35 GB scan pins page cache, so host `mem_used` fills to near-total unconditionally — the confirmation would rubber-stamp the OOM hypothesis. Confirmation keys on `zot_anon_mb` (container anonymous RSS) instead. |

## Open Code-Review Overlap

None — checked open `code-review` issues against every planned file path (`cloud-init-registry.yml`, `zot-registry.tf`, `variables.tf`, `registry-boot-guard.test.sh`, `expenses.md`, `ADR-096`, `model.c4`); zero matches.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, is placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6 — this one declares `threshold: none` with the sensitive-path scope-out reason.
- **Host `mem_used` is a page-cache-confounded confirmation signal:** a large store scan pins page cache, so host used fills regardless of anonymous-memory pressure. Confirmation MUST key on the container's cgroup anonymous RSS (`zot_anon_mb`), not host `mem_used_mb`.
- **OOMKilled false-negative:** relying on `.State.OOMKilled` alone (or point-sampling a 4/min loop) mislabels the current host-OOM as "not OOM." Detection keys on `zot_restarts` delta + `exit_code=137` + the journald `oom_kills_5m` window, per the decode table.
- **`--memory` below scan peak self-manufactures the OOM** it diagnoses (ADR-062 AC2). Cap is sized off host RAM minus documented headroom, not a guessed working-set; `--memory-swap == --memory` (verify Hetzner swap = none, else the container swaps instead of OOM-killing).
- **`dedupe=false` is not free on an existing store:** flipping it triggers zot's undedupe rewrite (disk re-inflation + I/O storm). Deferred out of this redeploy for that reason.
- **templatefile escaping:** new brace shell vars must be `$${VAR}`-doubled (matches `:159`); a single-`$` `${...}` fails `terraform plan`. The negative test guard (AC7) catches a leak.
- **Reused hostname across replace:** without `boot_id`, old-host and new-host `SOLEUR_ZOT_DISK` events are indistinguishable → the automated rule filters to the newest `boot_id`.
- **`Ref #6288` not `Closes`:** this is an ops-remediation whose fix runs post-merge (dispatch + soak); `Closes` would auto-close before the soak proves plateau. Closure lives in the follow-through probe.
- **Do not close on the immediate post-boot check:** a fresh host reads `zot_restarts=0` before the scan/gc even happen — the decision rule is slope-over-a-≥2h-window, not a single row.
