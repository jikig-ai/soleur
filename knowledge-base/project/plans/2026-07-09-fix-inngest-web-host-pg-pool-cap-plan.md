<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- All host-config changes route through the immutable vinngest-v* tag -> build-inngest-bootstrap-image.yml -> ci-deploy.sh redeploy path (see ## Infrastructure (IaC)); the systemctl restart references describe that EXISTING reconcile mechanism, not a new manual/SSH step. The default_pool_size change routes through a gated Management-API PATCH workflow, not an operator dashboard. -->
---
title: "fix(inngest): bound web-host inngest total Postgres footprint (idle-conn cap + drain) — unblock cutover probe scans"
issue: 6258
branch: feat-one-shot-6258-inngest-pg-pool-cap
date: 2026-07-09
type: infra-bugfix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
refs: [6178, 6230, 5558, 5559, 5560, 5562, 5563, 5569]
---

# fix(inngest): web-host inngest Postgres pool ratchets to EMAXCONNSESSION — bound total footprint + drain idle conns 🐛

## Enhancement Summary

**Deepened on:** 2026-07-09 · **Reviews folded in:** framework-docs (pool flags), spec-flow-analyzer (12 findings), scoped strong-model advisor (fable), repo-research, learnings-researcher.

### Key improvements over the first draft
1. **Simpler, safer fix — conservative FIXED flag values (`OPEN=5 IDLE=2 SECS=30`) instead of measurement-gated values.** Correct for any pool count P ≤ 4; ships without blocking on a live prod measurement (which is now confirmatory, not determinative). (advisor)
2. **`default_pool_size` 30→15 revert (#5562) DECOUPLED and re-scoped out.** Its premise ("cap holds total under 15") is falsified by the per-pool model — lowering the upstream to 15 while inngest bursts to ~20 *worsens* exhaustion. Recorded as a User-Challenge (`decision-challenges.md` + follow-up issue). This removes the entire PATCH-workflow + sequencing-hazard surface spec-flow flagged as CRITICAL (C1/C2). (advisor + spec-flow C1/C2)
3. **op=execute pre-check hardened:** runs BEFORE the 2.0 registry probe; gates on readiness-baseline + burst-headroom (not the 80% alert line); fails closed on EMAXCONNSESSION / 401 / non-JSON / empty / curl-fail. (spec-flow C3/I7)
4. **Phase-1 verdict rule corrected** (H1/H2 labels were inverted) + host-blind caveat (web-1/web-2 aggregate inflates P; derive per-host). (spec-flow I4/I5)
5. **AC4 sweeps the stale operator-facing `cap (10)` prose** at `:220`/`:343` + the stale `:354` ref, not just `INNGEST_CLIENT_CAP`. (spec-flow I6)

### New considerations discovered
- The `inngest.tf:208-211` recorded decision ("cap 10 holds total under 15") is actively misleading and is corrected as an in-scope deliverable (Phase 4 / ADR-103).
- 4th durability parser `ci-deploy.sh:1851` enumerated (substring-robust; note-only). (spec-flow M11)
- Phase ordinals ≠ execution order for deploy/measure — `/work` follows AC ordering (AC11→AC12). (spec-flow M12)

## Overview

The self-hosted `inngest start` server co-located on the web hosts connects to its dedicated durable-backend Supabase project (**soleur-inngest-prd**, ref `pigsfuxruiopinouvjwy`) through the Supavisor **session** pooler (`:5432`). Under back-to-back paginated GraphQL scans (`op=inventory` / `op=verify` in `.github/workflows/cutover-inngest.yml`, which drive the inngest server's own Postgres-backed GQL API at `127.0.0.1:8288/v0/gql`), the server's Postgres connection footprint **ratchets to ~31 pinned idle connections and never releases them**, hitting `pool_size` and returning `FATAL: (EMAXCONNSESSION) max clients reached in session mode`. This makes the cutover's own safety gates (`op=execute` 2.1 capture, 2.2 quiesce, `op=verify`) unreliable **mid-flip** — exactly when they must be reliable to avoid silent reminder loss or an undetected double-fire.

The ExecStart today (`apps/web-platform/infra/inngest-bootstrap.sh:439`) carries **only** `--postgres-max-open-conns 10`. Research (framework-docs) confirms `inngest start` exposes **four** pool knobs, of which we currently set one:

| Flag | Default | Currently set? |
|---|---|---|
| `--postgres-max-open-conns` | 100 | ✅ `10` |
| `--postgres-max-idle-conns` | **10** | ❌ (default 10) |
| `--postgres-conn-max-idle-time` | 5 min | ❌ (default 5m) |
| `--postgres-conn-max-lifetime` | 30 min | ❌ (default 30m) |

**Root-cause model (to be confirmed empirically in Phase 1, not assumed).** The measured plateau (~31 idle ≈ **3 × 10 + 1**) is the signature of inngest opening **separate Postgres pools per subsystem** (queue / state / history / api), each independently honouring `--postgres-max-open-conns` **and** the default `--postgres-max-idle-conns 10`. Three pools × 10 idle-retained = 30 pinned idle. `--postgres-max-open-conns` therefore does **not** bound *total* connections — it bounds *per-pool* — so the #5558/#5559 "client cap 10 holds inngest under the pool" invariant recorded in `inngest.tf:208-211` is **false for total footprint**. The competing hypothesis is plain config-drift (the running host predates #5559 and carries no cap at all → default 100 → plateaus at `pool_size`). **Phase 1 reads the live ExecStart and re-measures the plateau to decide which** before any code lands — the two root causes prescribe different fixes and the decision is cheap (one Management-API read + a controlled scan).

The fix bounds **total** footprint with per-connection **idle drain** so pinned-idle connections release their Supavisor sessions: add `--postgres-max-idle-conns 2` + `--postgres-conn-max-idle-time 30` to the durable ExecStart, and lower `--postgres-max-open-conns` to **5** — values chosen **conservatively so they are safe for any plausible pool count** (even at P=4 subsystem pools, worst-case total = 4×5 = 20 < `pool_size` 30 − ~8 headroom; idle held ≤ 4×2 = 8). The fix is therefore **deployable immediately without gating on a live prod measurement** (Phase-1's measurement *confirms* P and the plateau; it does not *determine* the numbers). Alongside: reconcile the health-probe's `INNGEST_CLIENT_CAP` to the measured post-fix total and gate `op=execute` on a clean pool pre-check.

**Decoupled from this fix — `default_pool_size` stays 30 (User-Challenge to the issue's remediation #3).** Issue remediation #3 asks to revert `default_pool_size` 30 → 15 per the #5562 decision. That decision's premise — "the client cap holds inngest's *total* under 15" — is **falsified** by the per-pool footprint model this plan establishes: with per-subsystem pools, tightening the upstream pool to 15 while inngest's own worst-case burst can approach 20 makes EMAXCONNSESSION *more* likely, not less. The advisor consult (Step 4.5) and this plan converge: **keep `default_pool_size` at 30**, make the low client-side per-pool cap the sole lever, and re-scope #5562 as a separate decision (recorded in `decision-challenges.md` + a follow-up issue) rather than executing its now-void revert inside this bugfix. This removes the sequencing hazard and its prod-write blast radius from scope entirely.

**Why this is not "just restart it":** the standalone inngest restart (remediation step 1) drops the *pinned* pool immediately and is the correct pre-cutover readiness action, but it is **not** the fix — the pool re-ratchets on the next scan burst. The durable fix is the ExecStart cap+drain, delivered by the immutable `vinngest-v*` tag → `build-inngest-bootstrap-image.yml` → `ci-deploy.sh` redeploy path (`hr-prod-host-config-change-immutable-redeploy`; the bootstrap's reconcile-always unit-write + unconditional restart at `inngest-bootstrap.sh:314-320,470-481` makes an ExecStart-only change deploy-reliable even on a same-CLI-version redeploy).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / prior record) | Reality (verified this plan) | Plan response |
|---|---|---|
| "The real fix — client cap `--postgres-max-open-conns 10` — holds inngest's connection count well under the project default of 15" (`inngest.tf:208-211`) | The flag is live since #5559 (2026-06-18) yet the host bursts to ~31. `--postgres-max-open-conns` is **per-pool**, not total (empirical 31≈3×10+1). | The recorded decision is misleading → **correct `inngest.tf:201-232` + runbook** as an in-scope deliverable (Phase 4). Do NOT inherit "cap 10 = bounded total". |
| "restart web-host inngest → re-run inventory" is the fix (issue remediation #1) | Restart clears the *pinned* pool but the pool re-ratchets on the next scan burst. | Restart is Phase 1 **diagnostic + immediate readiness**, not the durable fix. Durable fix = Phase 2 ExecStart cap+drain. |
| `--postgres-max-open-conns` is the only pool knob | `inngest start` exposes 4 knobs; 3 are at defaults (idle-conns 10, idle-time 5m, lifetime 30m). | Add `--postgres-max-idle-conns` + `--postgres-conn-max-idle-time` (durable branch only). |
| default_pool_size still 30 (issue "config drift secondary"); #5562 decided 30→15 | Confirmed 30 live (not TF-managed — `inngest.tf:227-232`, no Supabase provider). #5562's premise ("cap holds total under 15") is falsified by the per-pool model. | **Keep 30; do not lower it** (User-Challenge to remediation #3). Re-scope #5562 to `decision-challenges.md` + a follow-up issue — outside this plan's scope. |
| Lowering default_pool_size to 15 is safe now | If inngest bursts to ~20 (per-subsystem), a 15-slot pool makes exhaustion *guaranteed*, not fixed. | The low client-side per-pool cap (`OPEN=5`) is the sole lever; the upstream pool stays 30 (ample headroom). |
| Durability sentinel unaffected by adding flags | `inngest-inventory.sh:163` / `ci-deploy.sh:1007` / `inngest-wiped-volume-verify.sh:99` use substring `== *'--postgres-max-open-conns'*` → robust to added sibling flags. **But** `inngest.test.sh:242` anchors `BACKEND_FLAGS='--postgres-max-open-conns` (flag must be FIRST). | Keep `--postgres-max-open-conns` as the **first** flag in `BACKEND_FLAGS`; append idle flags after (Sharp Edge). No parser change needed. |
| Cited refs (#5558/#5560/#5562/#6178/#6230) | Verified: #5558 CLOSED (PR #5559), #5560 CLOSED, #5562 CLOSED (PR #5563/#5569), #6178 OPEN (parent), #6230 OPEN (action-required). | Premise holds; no stale blocker. |

## User-Brand Impact

**If this lands broken, the user experiences:** a scheduled reminder that silently never fires (capture/quiesce ran against an EMAXCONNSESSION-degraded inngest during the cutover and dropped it) — or the same reminder firing **twice** (undetected double-fire because `op=verify`'s exactly-once check ran against an exhausted pool and returned an unreadable/partial result). Both are silent, per-user, and irreversible after the flip window.

**If this leaks, the user's data/workflow is exposed via:** N/A — this change touches only connection-pool sizing + cutover gating; it does not move, log, or expose user data. No new data surface. (The inngest backend already stores user-scheduled reminders; this change does not alter their handling.)

**Brand-survival threshold:** single-user incident — a single lost or double-fired reminder is a per-user brand hit, and the cutover-gate reliability this fix restores is the only thing standing between the flip and that outcome.

> `requires_cpo_signoff: true` — CPO sign-off required at plan time before `/work` begins (approach already framed by the issue; confirm CPO has reviewed). `user-impact-reviewer` will be invoked at review-time (handled by review/SKILL.md conditional-agent block).

## Hypotheses

Diagnosis-first, decided by production observability (`hr-no-dashboard-eyeball-pull-data-yourself`, `hr-observability-as-plan-quality-gate`; Sharp Edge "establish WHICH code path executes from production observability before prescribing the fix layer"):

- **H1 — per-subsystem pools (primary; empirical 31≈3×10+1).** `inngest start` opens P≈3 independent Postgres pools, each honouring `--postgres-max-open-conns` + default `--postgres-max-idle-conns 10`. Live ExecStart *has* `--postgres-max-open-conns 10`, yet plateau ≈ 3×that. → Fix = cap idle + set per-pool open so `P × open < pool_size − headroom`.
- **H2 — config drift.** Running host predates #5559 → no cap flag on the live ExecStart → default 100 → plateaus at `pool_size`. → Fix = redeploy current bootstrap (already carries the cap); then still add idle drain for safety.
- **Decisive read (Phase 1):** (a) read the **live** ExecStart (via `op=inventory` durability read / health-probe read — no SSH); if it lacks `--postgres-max-open-conns` → H2. (b) After the restart, fire a controlled burst of `op=inventory` scans and re-count inngest-attributable backends via the Management-API `pg_stat_activity` query (the exact filter `scheduled-inngest-health.yml:195` uses); plateau ÷ 10 ≈ P. A plateau of ~10 with the flag present refutes H1.

## Implementation Phases

### Phase 0 — Preconditions (no code)
- [ ] Verify inngest CLI pool flags against the **pinned** binary before prescribing values: extract the pinned `INNGEST_CLI_VERSION` (`inngest.tf` locals), then confirm `--postgres-max-idle-conns` / `--postgres-conn-max-idle-time` exist in `inngest start --help` for that version (framework-docs confirmed the flags but not the pinned version's spelling; `<tool> --help` is the gate, `hr-verify-repo-capability-claim-before-assert`). Pin the verification output (or `<!-- verified: 2026-07-09 source: <help output|docs URL> -->`) in the plan/spec. **If a flag is absent in the pinned version, the fix pivots to `--postgres-max-open-conns` per-pool lowering only + a CLI bump task.**
- [ ] **Determine P (pool count) deterministically from the pinned inngest Go source** — the decisive resolver for per-subsystem-vs-total, cheaper and more definitive than a live plateau (which conflates pool-count with load; framework-docs' own recommendation). Inspect the pinned version's driver package for `pgxpool.New(` / `sql.Open(` / `SetMaxOpenConns(` call sites (`pkg/driver/postgres`, `pkg/datastore/postgres` or equivalent): one shared pool vs. N per-subsystem instances. Record P + the source citation in the spec. This bounds the worst-case-total arithmetic that justifies the conservative flag values (does NOT block them — they are already safe for P≤4).
- [ ] Confirm `SUPABASE_ACCESS_TOKEN` (GH secret + Doppler `prd`) reaches the health-probe + cutover-gate workflows that read `pg_stat_activity` (already used by `scheduled-inngest-health.yml` + `scheduled-followthrough-sweeper.yml` → precedent exists). (No pooler PATCH in scope — see Phase 3 decoupling.)

### Phase 1 — Diagnostic + immediate readiness (automatable, no code)
- [ ] Trigger the standalone inngest restart via `gh workflow run restart-inngest-server.yml` (drops the pinned pool; remediation #1). It POSTs `restart inngest _ latest` to the deploy webhook and polls deploy-status — **no SSH, no operator dashboard**.
- [ ] Read the **live** ExecStart (no-SSH) to decide H1 vs H2: is `--postgres-max-open-conns 10` present on the running unit?
- [ ] Fire a controlled burst of `op=inventory` (≥6 scans) and re-measure inngest-attributable backends via the Management-API query; record the plateau. **CONFIRMATORY, not determinative** — the Phase-2 values are conservatively safe for any plausible P, so the fix does not block on this; it confirms P + feeds the `INNGEST_CLIENT_CAP` reconciliation. **Verdict rule (spec-flow-corrected):** plateau ≤ 12 with `--postgres-max-open-conns 10` present ⇒ **H1-refuted** (cap bounds total; P=1; bug not reproduced — still ship idle-drain as defense-in-depth); plateau ≈ integer×open (~30=3×10, ~20=2×10) ⇒ **H1 confirmed**, P=round(plateau/open); flag ABSENT ⇒ **H2 config-drift** (redeploy bounds it). **Dead-zone** (non-integer band ~15 / still climbing at scan 6) ⇒ do NOT guess P; extend to ≥12 scans, else fall back to the Phase-0 source-read count as authoritative. **Host-blind caveat (DI-C3, `cutover-inngest.yml:425-440`):** the filter aggregates web-1 + un-drained weight-0 web-2, so the plateau can inflate P — derive per-host P from a single-host worst-case; AC12 exercises BOTH hosts. Persist P + plateau + per-host attribution to the spec.

### Phase 2 — Durable fix: bound total + drain idle (code)
- [ ] `apps/web-platform/infra/inngest-bootstrap.sh:439` — durable-branch `BACKEND_FLAGS`. Keep `--postgres-max-open-conns` **first** (sentinel-first; `inngest.test.sh:242` anchor), append idle knobs:
  ```sh
  BACKEND_FLAGS='--postgres-max-open-conns <OPEN> --postgres-max-idle-conns <IDLE> --postgres-conn-max-idle-time <SECS>'
  ```
  **Conservative fixed values (deployable without gating on the live measurement): `OPEN=5`, `IDLE=2`, `SECS=30`.** Chosen so worst-case total is safe for any plausible pool count: even at P=4, `4×5 = 20 < pool_size 30 − ~8 headroom` (Supavisor warm + probe); pinned-idle held ≤ `4×2 = 8`; `SECS=30` closes idle conns fast so they release the Supavisor session. `OPEN=5` also keeps ≥5 conns per pool for throughput (alpha-internal < 10 events/sec — ample). If Phase-1/Phase-0 shows P > 4 (unlikely), lower `OPEN` accordingly before ship.
- [ ] Update the flag rationale comment block `inngest-bootstrap.sh:363-371` (currently claims "10 stays under 15") to record the per-pool/total distinction + why idle drain is the release lever + the sentinel-first ordering invariant.
- [ ] Confirm no durability-parser change needed (substring match survives added siblings) — `inngest-inventory.sh:163`, `ci-deploy.sh:1007`, `inngest-wiped-volume-verify.sh:99`. Add a note; do not edit unless a test proves otherwise.

### Phase 3 — Health-probe cap reconciliation + #5562 re-scope (no prod-write)
- [ ] `.github/workflows/scheduled-inngest-health.yml` — reconcile `INNGEST_CLIENT_CAP` (line 157) from `10` to the post-fix worst-case **total** footprint (`P × OPEN`, ≤ 20 at the conservative values), so `pool_pressure` (>80% of cap) neither false-fires (steady-state legitimately > 8) nor under-alerts. **AC4/spec-flow I6 — also sweep the STALE prose `10`:** the same file hardcodes the old cap in the operator-facing remediation message body (`:220` comment "client cap (10", `:343` `pool_pressure`/`pool_exhausted` message which says "client cap (10)" and cites the stale `inngest-bootstrap.sh:354` line ref). After reconciliation those still tell the operator the cap is 10 — update every `cap (10` occurrence + the stale `:354` ref.
- [ ] **#5562 `default_pool_size` 30→15 revert — DO NOT execute (User-Challenge to issue remediation #3).** The #5562 premise ("client cap holds inngest's *total* under 15") is falsified by the per-pool footprint model: with per-subsystem pools, tightening the upstream pool to 15 while inngest's worst-case burst approaches 20 makes EMAXCONNSESSION *more* likely. **Keep `default_pool_size` at 30.** Persist the challenge to `knowledge-base/project/specs/feat-one-shot-6258-inngest-pg-pool-cap/decision-challenges.md` (headless path → `ship` renders it into the PR body + files an `action-required` issue) and open a follow-up issue re-scoping #5562's premise. No PATCH workflow, no prod-write, no sequencing hazard in this plan's scope.

### Phase 4 — Cutover gate + decision-record correction (code/docs)
- [ ] `.github/workflows/cutover-inngest.yml` `op=execute` — gate the flip on a **clean pool pre-check** (remediation #4). **Placement:** run it FIRST, before the 2.0 registry probe (2.0 itself opens a GQL→Postgres connection that would otherwise be counted in the pre-check). **Threshold (spec-flow I7 — NOT the 80% alert line):** the pressure-alert threshold lets a pool sitting at 79% *pass* the gate, then capture+quiesce push it over the cap mid-flip — the exact failure the gate exists to prevent. Gate instead on a **readiness baseline with explicit burst headroom**: assert `inngest_backends + expected_burst_cost ≤ pool_size − Supavisor-warm`, where `expected_burst_cost` is the capture+quiesce connection draw. **Fail-closed on EVERY non-clean state (spec-flow C3):** (i) count ≥ readiness threshold, (ii) EMAXCONNSESSION in the body, (iii) 401/403/non-2xx, (iv) token-unset / curl rc≠0, (v) non-JSON / empty body → loud `::error::`, no flip (never a false `0==0` clean on an unparsed count).
- [ ] `apps/web-platform/infra/inngest.tf:201-232` — correct the #5558→#5562 decision block: record the per-pool footprint model, the idle-drain lever, and the **decoupled `default_pool_size` posture** (keep 30; the #5562 30→15 revert is superseded — its premise is falsified) — supersedes "client cap 10 holds under 15".
- [ ] `knowledge-base/engineering/operations/runbooks/inngest-server.md:102-144` — update the pool-pressure section: the cap-10 "already live / holds under 15" claim (line 133) → the new cap+drain flags + the new `INNGEST_CLIENT_CAP`.
- [ ] **Vector allowlist (learning #1):** if Phase 2/4 adds any NEW `logger -t <tag>` on a host script, add the tag to `apps/web-platform/infra/vector.toml` Source-4 `include_matches.SYSLOG_IDENTIFIER` + its drift-guard fixture. If no new tag (bootstrap logs via existing `LOG_TAG`), state "no new host tag" explicitly.

### Phase 5 — Deploy (immutable tag)
- [ ] Push a new `vinngest-vX.Y.Z` tag to trigger `build-inngest-bootstrap-image.yml` → publish the OCI image → deploy via `deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap vX.Y.Z` (`ci-deploy.sh` `case "inngest")`). **Tag push is in this PR's immediate follow-up, not deferred to the operator** (`hr-tagged-build-workflow-needs-initial-tag-push`; learning `2026-06-18-inngest-bootstrap-release-tag-then-dispatch-deploy.md` + `2026-05-19-inngest-substrate-five-bug-cascade.md` item 1).
- [ ] Post-deploy: re-run the Phase 1 controlled-burst measurement → confirm the plateau is now bounded (`op=inventory` completes clean, no EMAXCONNSESSION) — the real pre-cutover readiness signal.

### Phase 6 — Tests
- [ ] Extend `apps/web-platform/infra/inngest.test.sh` to assert the durable `BACKEND_FLAGS` carries all three flags with `--postgres-max-open-conns` still first (sentinel), and the SQLite branch still empty.
- [ ] Extend `cutover-inngest-workflow.test.sh` for the new op=execute pool pre-check gate (fail-closed on simulated pressure; pass on clean; unreadable-probe → fail-closed).
- [ ] Assert `inngest-wiped-volume-verify` + `inngest-inventory` durability detection still classify `durable` with the widened flag set (substring sentinel).

## Files to Edit
- `apps/web-platform/infra/inngest-bootstrap.sh` — durable `BACKEND_FLAGS` + comment block (Phase 2).
- `apps/web-platform/infra/inngest.tf` — decision-record correction (Phase 4).
- `.github/workflows/scheduled-inngest-health.yml` — `INNGEST_CLIENT_CAP` reconciliation (Phase 3).
- `.github/workflows/cutover-inngest.yml` — op=execute pool pre-check gate (Phase 4).
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — pool-pressure section (Phase 4).
- `apps/web-platform/infra/inngest.test.sh` — flag-shape assertion (Phase 6).
- `apps/web-platform/infra/cutover-inngest-workflow.test.sh` — gate test (Phase 6).
- `apps/web-platform/infra/vector.toml` — **conditional** (only if a new host `logger -t` tag is added).

## Files to Create
- `knowledge-base/engineering/architecture/decisions/ADR-103-inngest-postgres-footprint-per-pool-cap-and-idle-drain.md` — the footprint-model decision (see Architecture Decision section). Ordinal provisional.
- `knowledge-base/project/specs/feat-one-shot-6258-inngest-pg-pool-cap/decision-challenges.md` — the #5562 User-Challenge (keep `default_pool_size` at 30; revert premise falsified). `ship` renders it into the PR body + files an `action-required` follow-up issue.
- (NO `apply-inngest-pooler-config.yml` — the `default_pool_size` revert is out of scope; see Phase 3 / #5562 re-scope.)

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (62 open) returns zero bodies containing `inngest-bootstrap.sh`, `inngest.tf`, `cutover-inngest.yml`, `scheduled-inngest-health.yml`, or `inngest-inventory.sh`. Check ran 2026-07-09.

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/inngest.tf` — **comment/decision-record only** (no new resource, no config mutation): correct the stale #5558→#5562 decision block. `default_pool_size` stays 30 (the #5562 30→15 revert is re-scoped out — see Phase 3). No pooler PATCH; no `terraform apply`.
- No new `TF_VAR_*` and no new PAT: this plan reads `pg_stat_activity` via the **pre-existing** `SUPABASE_ACCESS_TOKEN` (Supabase Management-API account PAT — Supabase exposes no project-scoped/App-auth credential, so `hr-github-app-auth-not-pat` is N/A; that rule is GitHub-write-scoped). No new secret is introduced.

### Apply path
- **ExecStart cap+drain (Phase 2/5) — the ONLY infra change:** immutable redeploy — new `vinngest-v*` tag → OCI image → `ci-deploy.sh` extract + inngest-server unit reconcile-always restart. No SSH, no host mutation (`hr-prod-host-config-change-immutable-redeploy`). Blast radius: one unit restart per web host (de-plans crons until async re-arm; advisory — the standalone-restart workflow header notes this).
- **No prod-write / no pooler PATCH in scope.** `default_pool_size` stays 30 (#5562 revert re-scoped out).

### Distinctness / drift safeguards
- The inngest durable backend is a **separate** Supabase project from the app (`ifsccnjhymdmidffkzhl`) — this change touches only the ExecStart on `pigsfuxruiopinouvjwy`'s consumer (dev/prd inngest are the same singleton control-plane project per ADR-100; no dev twin — infra host). No pooler config is mutated, so no drift-vs-tfstate concern.

### Vendor-tier reality check
- N/A — no vendor config mutation. The only Management-API calls are read-only `pg_stat_activity` queries (existing pattern in `scheduled-inngest-health.yml`).

## Downtime & Cutover

Trigger: the durable fix rides the immutable-redeploy path, which restarts the `inngest-server` unit per web host (deploy class). Zero-downtime-first evaluation:

- **Offline-inducing op + surface:** the `inngest-server` unit restart on each web host (the existing bootstrap reconcile behavior). Surface: the loopback inngest server (127.0.0.1:8288) the app posts events to + serves functions from. The Concierge/web app itself is NOT restarted by this change (separate container).
- **Zero-downtime path (default):** the restart is **non-destructive to durability** — armed reminders live in self-hosted Redis (AOF on the persistent volume) + Postgres, both of which survive the restart (the #5450 durability design). The only transient is crons de-plan until they re-arm async (seconds), an already-accepted **advisory** for any inngest bootstrap change (`restart-inngest-server.yml` header). Web hosts are a **round-robin set** — the deploy applies per host, so a rolling restart (one host at a time) keeps the aggregate inngest serve path available; no simultaneous full-fleet outage. **No maintenance window required.**
- **Cutover interaction:** the op=execute flip (#6178) is a SEPARATE operation gated by this fix's new pool pre-check (Phase 4). This change does not itself perform the flip; it makes the flip's gates reliable. The flip's own downtime posture is owned by #6178, not this plan.
- **Residual downtime:** none beyond the seconds-scale cron re-plan already inherent to every inngest restart. No new offline window is introduced.

## Observability

```yaml
liveness_signal:
  what: inngest-server liveness + pool-utilization probe (existing)
  cadence: every 15 min (scheduled-inngest-health.yml)
  alert_target: Better Stack (betteruptime_heartbeat.inngest_prd) + Sentry error heartbeat + [ci/inngest-pool] GH issue
  configured_in: .github/workflows/scheduled-inngest-health.yml + apps/web-platform/infra/inngest.tf (betteruptime_heartbeat)
error_reporting:
  destination: Sentry (error heartbeat on missing/failed check-in) + GH issue [ci/inngest-pool] + Vector to Better Stack Logs (inngest-server journald)
  fail_loud: true (pool_exhausted/pool_pressure file a P1 issue; probe failure files pool_probe_unavailable — no silent pass)
failure_modes:
  - mode: pool_exhausted (EMAXCONNSESSION at the cap)
    detection: Management-API pg_stat_activity 5xx-body EMAXCONNSESSION check (scheduled-inngest-health.yml:209)
    alert_route: [ci/inngest-pool] issue + Sentry (NO auto-restart — restart worsens exhaustion)
  - mode: pool_pressure (inngest-attributable backends > 80% of INNGEST_CLIENT_CAP)
    detection: Management-API pg_stat_activity filtered count vs INNGEST_CLIENT_CAP (reconciled to post-fix total)
    alert_route: [ci/inngest-pool] issue + Sentry
  - mode: cutover pool pre-check fail (op=execute refuses to flip)
    detection: op=execute pool pre-check (new, Phase 4) — same Management-API filter
    alert_route: cutover-inngest.yml ::error:: (fail-closed; no flip)
logs:
  where: Vector to Better Stack Logs (inngest-server.service journald, arch-selected sink); GH Actions run logs (per-backend breakdown)
  retention: Better Stack Logs default retention
discoverability_test:
  command: 'curl -s --max-time 15 -X POST https://api.supabase.com/v1/projects/pigsfuxruiopinouvjwy/database/query -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -H "Content-Type: application/json" -d @pool-query.json (filtered pg_stat_activity client-backend count; no ssh)'
  expected_output: JSON rows; inngest-attributable backends (role postgres, minus Supavisor warm + probe) below the reconciled INNGEST_CLIENT_CAP — no EMAXCONNSESSION body
```

No new dark surface: the fix changes cap *semantics*, so the existing probe's `INNGEST_CLIENT_CAP` is reconciled (Phase 3) to keep the leading indicator accurate. The op=execute gate reuses the existing Management-API filter (no new emit path). No new `logger -t` tag expected; if one is added, the Vector allowlist edit is a Phase-4 deliverable (learning #1).

## Architecture Decision (ADR/C4)

Detection fires: the plan **reverses a recorded decision** — the #5558/#5559 "one client cap of 10 bounds inngest's total footprint" invariant (recorded in `inngest.tf:208-211` + runbook, not a formal ADR) is falsified by the per-pool footprint model. This is a cross-cutting invariant every consumer of the connection budget depends on (the health probe cap, the `default_pool_size` decision, the cutover gate).

### ADR
- **ADR-103 (provisional ordinal) — "Inngest self-hosted Postgres footprint: low per-pool cap + idle drain; keep `default_pool_size` at 30"** — new ADR (the prior decision was never an ADR; it lived in `inngest.tf` comments). Records: `--postgres-max-open-conns` is per-pool not total; worst-case total = P × open; the client-side low per-pool cap + idle drain (`--postgres-max-idle-conns` + `--postgres-conn-max-idle-time`) is the sole lever; **`default_pool_size` stays 30** — the #5562 30→15 revert is superseded because its premise ("cap holds total under 15") is falsified by the per-pool model (tightening upstream to 15 while inngest bursts to ~20 worsens exhaustion). `## Alternatives Considered`: (a) transaction pooler `:6543` — rejected, breaks inngest's sqlc prepared statements (verdict 0.5, `inngest-bootstrap.sh:346`); (b) client-open-cap-alone at 10 — rejected, per-pool so does not bound total; (c) `pg_terminate_backend` idle-sweep only — rejected as the sole fix (reactive, masks the leak); (d) revert `default_pool_size` to 15 per #5562 — rejected, premise falsified, worsens the failure. **Status: adopting** — flips to `accepted` after Phase 5 post-deploy confirms the bounded plateau. Ordinal provisional (`/ship` re-verifies against origin/main; ADR-102 is the current highest — ADR-103 is next-free).

### C4 views
Read all three model files (`model.c4`, `views.c4`, `spec.c4`). **No C4 impact** — enumeration checked and found already-modeled:
- External human actor: none (this is inngest↔its own DB, no human/correspondent edge).
- External system/vendor: none new — the inngest↔Postgres edge and the dedicated pooler are already modeled: `inngest` container (`model.c4:184`), `inngestPostgres` database with `technology "PostgreSQL — dedicated EU project, Supavisor session pooler :5432"` (`model.c4:188-190`). A connection-pool *sizing* change does not add/remove an element, edge, or `#external` boundary.
- Container/data-store touched: `inngestPostgres` (existing); no new store.
- Access relationship changed: none — the `postgres`-owner access path (ADR-030 I8) is unchanged; only the connection *count* discipline changes.
- Correctness: `inngestPostgres.description` ("Dedicated project isolates connection budget") remains accurate (this fix *restores* that isolation guarantee) — no falsified element description to fix.

### Sequencing
ADR-103 is authored now (`status: adopting`) with the conservative-values target state; it flips to `accepted` after Phase 5 post-deploy re-measurement confirms the bounded plateau. Authored in THIS feature, not postponed to a separate issue (`wg-architecture-decision-is-a-plan-deliverable`). The `default_pool_size` decision (keep 30, supersede #5562) is recorded here + in `decision-challenges.md` — no separate prod-write sequencing exists to gate.

## Domain Review

**Domains relevant:** none

No cross-domain (product/marketing/sales/finance/legal/ops/support) implications — infrastructure/tooling change. All Files-to-Edit are `.sh`/`.tf`/`.yml`/runbook infra surfaces; no UI-surface path (Product/UX Gate override does not fire). Engineering/architecture review is provided by the plan-review panel (DHH/Kieran/Simplicity, escalating to +architecture-strategist +spec-flow-analyzer at the single-user-incident threshold) and deepen-plan's data-integrity/security/architecture triad.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1** Durable `BACKEND_FLAGS` in `inngest-bootstrap.sh` carries `--postgres-max-open-conns 5 --postgres-max-idle-conns 2 --postgres-conn-max-idle-time 30` with `--postgres-max-open-conns` **first**; SQLite branch `BACKEND_FLAGS` still empty. Verify: `grep -E "^\s*BACKEND_FLAGS='--postgres-max-open-conns 5 --postgres-max-idle-conns 2 --postgres-conn-max-idle-time 30'" apps/web-platform/infra/inngest-bootstrap.sh` returns 1.
- [ ] **AC2** Arithmetic recorded in the spec: worst-case total `P × OPEN` stays under `pool_size 30 − ~8` headroom for all P ≤ 4 (`4×5 = 20`); pinned-idle `P × IDLE ≤ 8`; `OPEN=5 ≥ 5` throughput floor. If Phase-0/Phase-1 finds P > 4, `OPEN` is lowered before ship (per-item contributions shown; numeric self-consistency).
- [ ] **AC3** Durability sentinel intact: `inngest.test.sh`, `inngest-inventory.test.sh`, `inngest-wiped-volume-verify.test.sh` all pass and classify the widened flag set as `durable`.
- [ ] **AC4** `scheduled-inngest-health.yml` `INNGEST_CLIENT_CAP` (line 157) equals the post-fix worst-case total (≤ 20, per P), not 10; a comment cites the source. **AND the stale prose `10` is swept (spec-flow I6):** no operator-facing `cap (10` remains at `:220`/`:343`, and the stale `inngest-bootstrap.sh:354` line ref is corrected. Verify: `grep -cE "cap \(10|:354" .github/workflows/scheduled-inngest-health.yml` is 0 for the cap-value occurrences (the alert body no longer misreports 10).
- [ ] **AC5** `op=execute` in `cutover-inngest.yml` runs a pool pre-check before 2.1 capture and fails closed (`::error::`, non-zero) on every non-clean state (pressure, EMAXCONNSESSION, 401/403, non-JSON/empty/curl-fail); proceeds only on a parsed count below threshold. Covered by `cutover-inngest-workflow.test.sh` (5 cases, Test Scenario 3).
- [ ] **AC6** `inngest.tf:201-232` no longer asserts "client cap 10 holds inngest under 15"; it records the per-pool/total distinction + `default_pool_size` stays 30 (#5562 revert superseded). Verify: `grep -c 'holds inngest' apps/web-platform/infra/inngest.tf` is 0 (or the specific stale sentence is gone).
- [ ] **AC7** `ADR-103-*.md` exists with `status: adopting`, `## Decision`, `## Alternatives Considered` (≥3), and is referenced in the spec FRs. `knowledge-base/` citations resolve (Glob).
- [ ] **AC8** Runbook pool-pressure section updated (no stale cap-10 "already live / holds under 15"); new flags + reconciled cap documented.
- [ ] **AC9** All `bash <script>.test.sh` inngest suites + `apps/web-platform/infra/inngest.test.sh` green; `actionlint` clean on edited/new workflows; extracted `run:` shell `bash -c`-checked (composite/action files NOT `bash -n`'d — Sharp Edge).
- [ ] **AC10** `decision-challenges.md` exists recording the #5562 User-Challenge (keep `default_pool_size` 30; revert premise falsified); a follow-up issue is filed re-scoping #5562. No `apply-inngest-pooler-config.yml`, no pooler PATCH. Additionally enumerate the 4th durability parser (`ci-deploy.sh:1851`, the degraded-durability discriminator — spec-flow M11) and confirm it still classifies the widened flag set as `durable` (substring-robust; note-only).

### Post-merge (operator/agent-automated)
- [ ] **AC11** New `vinngest-vX.Y.Z` tag pushed → `build-inngest-bootstrap-image.yml` green → deployed via `deploy inngest … vX.Y.Z`. Automated in-session (`gh workflow run` / deploy webhook); NOT an operator dashboard step. `Automation: feasible` via the tag-driven dispatch path.
- [ ] **AC12** Post-deploy controlled-burst re-measurement, exercising **BOTH web hosts** under load (spec-flow I5 — not one LB-routed host): ≥6 `op=inventory` scans complete with **no EMAXCONNSESSION**, per-host plateau bounded (≤ P×5) well below `pool_size 30`. `Automation: feasible` via `gh workflow run cutover-inngest.yml` + Management-API read.
- [ ] **AC13** `default_pool_size` remains 30 (verify via Management-API GET); the #5562 revert is NOT executed. `decision-challenges.md` + the follow-up issue capture the re-scope. (No prod-write to reconcile.)
- [ ] **AC14** op=execute pool pre-check wired into the cutover (remediation #4); `#6258` closed via `gh issue close` after AC12 (post-merge, not auto-closed at merge — PR body uses `Ref #6258` since deploy/verify run post-merge).

## Test Scenarios
1. Bootstrap durable branch renders the 3-flag ExecStart with sentinel first; SQLite branch renders empty flags + `unset INNGEST_POSTGRES_URI`.
2. Durability parsers (`inngest-inventory.sh`, `ci-deploy.sh`, `inngest-wiped-volume-verify.sh`) classify `durable` on the widened flag set (substring sentinel).
3. op=execute pool pre-check — MUST fail-closed on every non-clean state (no path lets the flip proceed against a ratcheted pool): (a) clean pool below threshold → proceeds; (b) simulated pressure at/above threshold → fail-closed `::error::`; (c) EMAXCONNSESSION in the probe body → fail-closed; (d) Management-API 401/403 → fail-closed; (e) non-JSON / empty body / curl failure → fail-closed (never a false `0==0` "clean" on an unparsed count).
4. Post-deploy: controlled `op=inventory` burst on BOTH hosts → bounded per-host plateau (≤ P×5), no EMAXCONNSESSION (live, AC12).
5. `op=execute` pre-check runs BEFORE the 2.0 registry probe (so 2.0's own GQL→PG connection is not counted against the readiness threshold).

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder, or omits the threshold will fail `deepen-plan` Phase 4.6. This section is filled (threshold: single-user incident).
- **Sentinel-first ordering is load-bearing.** `inngest.test.sh:242` anchors `BACKEND_FLAGS='--postgres-max-open-conns`. Idle flags MUST be appended AFTER `--postgres-max-open-conns`, never before, or the durable-detection test regresses. The durability parsers use substring match (`== *'--postgres-max-open-conns'*`) and are robust to added siblings, but the test's `^…BACKEND_FLAGS='--postgres-max-open-conns` anchor is not.
- **Do NOT revert default_pool_size 30→15 (issue remediation #3 is a falsified premise).** With per-subsystem pools, a 15-slot upstream while inngest bursts to ~20 makes EMAXCONNSESSION *guaranteed*. Keep 30; the low client-side per-pool cap is the sole lever. The revert is re-scoped out (User-Challenge → `decision-challenges.md` + follow-up issue). This is the #6258 "most-capable-end-of-range" interaction.
- **Restart is not the fix.** The standalone inngest restart clears the pinned pool but it re-ratchets on the next scan burst; it is the Phase-1 diagnostic + readiness action, not the durable remediation.
- **Total-vs-per-subsystem pool architecture is doc-unconfirmed** — resolved by the Phase-0 source-read (authoritative) + Phase-1 live measurement (confirmatory). The flag values are chosen conservatively so the fix is correct for ANY P ≤ 4 and does not block on the measurement. If the pinned CLI lacks `--postgres-max-idle-conns`/`--postgres-conn-max-idle-time`, `--postgres-max-open-conns 5` alone still bounds worst-case total (4×5=20 < 30) — exhaustion is prevented even without the idle flags, though a **blocking** CLI-bump task should still land the idle-drain (Phase-0 gate; spec-flow I8).
- **op=execute pre-check must gate on readiness+burst-headroom, not the 80%-of-cap pressure line** — a pool at 79% passes the alert threshold but the capture+quiesce burst then pushes it over the cap mid-flip. Assert `count + burst_cost ≤ pool_size − Supavisor-warm`, and fail-closed on EMAXCONNSESSION / 401 / non-JSON / empty / curl-fail (spec-flow C3/I7).
- **New `logger -t` tags ride the Vector allowlist, not the shipper by default** (learning `2026-07-08-inngest-cutover-authoring-review-and-observability-allowlist.md`): any new host tag needs a `vector.toml` Source-4 `include_matches` entry + drift-guard fixture, else it is invisible.
- **Immutable redeploy needs the tag push in-PR** (`hr-tagged-build-workflow-needs-initial-tag-push`; learning `2026-05-19-inngest-substrate-five-bug-cascade.md` item 1) — the `vinngest-v*` tag is not an operator step.
- **No pooler PATCH in scope** — this plan makes zero prod-writes to Supabase config; the only Management-API calls are read-only `pg_stat_activity` queries. (The #5562 revert, if ever revived, would be the prod-write to gate — but its premise is falsified, so it is re-scoped out.)
- **Phase ordinals ≠ execution order for the deploy/measure steps** — Phase 5 (deploy) precedes the AC12 post-deploy measurement even though it is numbered after the Phase-2 code; `/work` must follow the AC ordering (AC11 deploy → AC12 measure), not raw phase numbers (spec-flow M12).

## Alternative Approaches Considered
| Approach | Verdict |
|---|---|
| Switch inngest to the transaction pooler `:6543` (returns conns per-query) | Rejected — breaks inngest's sqlc prepared statements (`inngest-bootstrap.sh:346`, verdict 0.5). |
| Rely solely on the runbook `pg_terminate_backend` idle-sweep | Rejected as the fix — reactive, masks the leak; keep as a documented emergency lever only. |
| Raise `default_pool_size` further (30→50) | Rejected — treats the symptom; the session pooler still pins idle conns. |
| Lower `default_pool_size` 30→15 (issue remediation #3 / #5562) | Rejected — premise falsified by the per-pool model; a 15-slot upstream while inngest bursts to ~20 *worsens* exhaustion. Keep 30 (User-Challenge; re-scoped to a follow-up). |
| Lower only `--postgres-max-open-conns` (no idle flags) | Partial — `OPEN=5` alone bounds worst-case *total* (prevents exhaustion), but the reported symptom is *pinned idle* conns; idle-conn cap + idle-time is the release lever, so ship both. |
| Defer numeric values to a live prod measurement | Rejected (advisor) — the measurement conflates pool-count with load and adds a gating dependency; conservative fixed values (`5/2/30`) are correct for any P ≤ 4 and ship immediately; the measurement is confirmatory. |
