# Brainstorm: Off-host private-net probe — the web-host "L3" consumer-perspective layer

**Date:** 2026-07-18
**Issues:** #6438 §1 (zot consumer probe) · #6548 (git-data consumer probe) · #6438 §3 (web-host NIC guard) · parent vehicle #5274 PR C
**Branch:** feat-off-host-l3-probe-6438 · **PR:** #6654 (draft)
**Lane:** cross-domain · **Brand-survival threshold:** single-user incident

---

## What We're Building

A **web-host private-net probe primitive** — one host-resident delivery substrate on the web hosts (`10.0.1.10` / `10.0.1.11`) that carries **three payloads** the issue tracker had filed separately, all blocked on the same missing vehicle (`#5274 PR C`):

1. **#6438 §1 — zot consumer probe (the "L3" ask).** A web host verifies it can actually reach the zot container registry at `10.0.1.30:5000` over the **private NIC** (a real `GET /v2/`, not localhost), then pings a heartbeat. Detects "the private net is broken from a *consumer's* perspective while the registry thinks its own NIC is fine" — a gap the shipped L1 (on-host NIC converger) + L2 (emit→alarm) + #6540 (registry self-ping) structurally **cannot** see.
2. **#6548 — git-data consumer probe.** Same shape, target `10.0.1.20`. `git_data_prd` heartbeat already exists `paused`, `feeder:{kind:"none", tracking_issue:6548}` in `heartbeat-manifest.ts:145`.
3. **#6438 §3 — web-host NIC self-convergence guard.** The L1-style on-host guard (ADR-115) delivered to the web hosts, which share the identical silent-14-day race (`model.c4:380`: a NIC-less web host falls back to GHCR and deploys keep working).

**Why bundle:** the expensive, risky part — host-resident delivery to running web hosts + honestly arming web-1 — is **identical** across all three. A one-off §1-only probe pays the full delivery cost for ⅓ the coverage. Operator chose "build the primitive once" (2026-07-18).

## Why This Approach

The issue framed §1 as "4 hard blockers + a no-green-AC gate." Research against live `main` collapsed that:

- **Blocker #2 (arming) is a solved pattern, not an open problem.** ADR-117 (executable heartbeat arming, #6537) + the worked example **#6540** established: build feeder → measure a real beat → arm via the Better Stack API. The issue's own "no-green-AC gate" ("an inert flag behind a passing test is #6400's own failure shape") is now **CI-enforced** by the `feeder` contract in `plugins/soleur/lib/heartbeat-manifest.ts`.
- **Blocker #4 (escalation) is not L3's.** It's owned by **#6549 item 1** (paid-tier webhook heartbeats, untouched). L3 inherits the fleet baseline (email-only) — every sibling infra beat is email-only, including the *more* critical registry self-ping.
- **Blockers #1 (delivery) and #3 (cadence) are real** and resolved below.
- **A new blocker surfaced (masking).** The reserved `ZOT_HEARTBEAT_URL` secret (`zot-registry.tf:508`) now points at #6540's *self-ping* monitor. Feeding an L3 beat into it gives OR-semantics that **mask** a consumer-only break. L3 needs its **own** heartbeat + secret.

The alternative mechanisms were weighed and set aside: a **fallback-usage alarm** (alarm on sustained GHCR-fallback ⇒ zot down) is closer to #6400's literal signature but is a different signal, not a consumer-perspective probe — a good complementary follow-up, not a substitute. **Defer-and-do-§3-only** (CPO's rec) was rejected in favor of the bundle because §3 needs the same delivery substrate anyway, making the marginal cost of adding §1 + #6548 small.

## Key Decisions

| # | Decision | Rationale / evidence |
|---|---|---|
| K1 | **Build the primitive once** — one delivery substrate on web hosts, three payloads (§1, #6548, §3). | Shared delivery cost; operator choice 2026-07-18. |
| K2 | **New heartbeat + new URL secret per consumer probe.** Do NOT reuse `ZOT_HEARTBEAT_URL`; repoint or delete the reserved `zot_heartbeat_url_prd`. | Masking trap — `ZOT_HEARTBEAT_URL = registry_prd.url` = #6540 self-ping (`zot-registry.tf` :508/:515). Shared beat = OR-masking. (CTO + platform-strategist, independently.) |
| K3 | **Per-(host,target) heartbeat cardinality**, not per-target. | Same masking logic one level up: if both web hosts feed one shared zot-consumer beat, web-2's healthy ping hides web-1's break. Honest per-host detection ⇒ up to 4 beats (web-1→zot, web-2→zot, web-1→git-data, web-2→git-data). Cardinality is an open sub-question (Q1). |
| K4 | **Host-resident systemd timer** (`OnUnitActiveSec=60s`, `AccuracySec=1s`), **own heartbeat `period≈180 / grace≈60`** — not the inherited `60/30`. | Off-host poll machinery (`deploy-status-fanout-verify.sh`) reaches web hosts only over the **public tunnel — no private-NIC route** to `10.0.1.30`, so it cannot host a consumer probe. Timer sidesteps the 60s cron floor + the ADR-103 parity-manifest perturbation; ~3 beats/period ⇒ one dropped round-trip won't flap. |
| K5 | **Dual delivery** — bake into image/cloud-init (covers web-2 + all rebuilds) **AND** out-of-band arm web-1 via the deploy fan-out / `ci-deploy.sh` re-seed channel, **measuring a real beat from web-1 before arming**. | `ignore_changes=[user_data]` (`server.tf:266`) ⇒ bake arms fresh-creates only; **web-1 is unrebuildable**. Bake alone ⇒ web-1 dark while the manifest reads GREEN = the exact #6537 inert-monitor failure. Precedent: `luks-monitor.timer` (`heartbeat-manifest.ts:128-142`). **Highest-risk decision.** |
| K6 | **Arming = replay #6540/ADR-117.** Create heartbeat `paused=true` + `ignore_changes=[paused]`; executable `feeder:{kind:"timer", evidence:{file, pattern}}` row per probe; one-time Better Stack API PATCH under the bounded arm-and-watch (pattern at `apply-web-platform-infra.yml:~1968`). | The no-green-AC gate is now the CI guard itself. `"external-probe"` Arming enum exists and is unused (`heartbeat-manifest.ts:15`) — candidate for the new rows (Q4). |
| K7 | **Probe health contract: status-code discrimination, never `curl -f`.** `curl -sS -o /dev/null -w '%{http_code}'` → `200|401` alive, `5xx` wedged, `000` unreachable. Reuse #6540's logic (`cloud-init-registry.yml:335-361`). | zot auth-gates `/v2/` ⇒ 401 IS healthy; `curl -f` exits 22 on ≥400 and the probe never fires (#6540's caught bug). git-data needs its own contract (Q2). |
| K8 | **Escalation: email-only, leave `betterstack_paid_tier=false`.** | Not L3's scope; gated on #6549 item 1. Finance/ops: a future paid-tier move is an `hr-record-recurring-vendor-expense` item (CLO flag). |
| K9 | **§3 = on-host NIC self-convergence guard (ADR-115 L1 pattern) delivered to web hosts** via the same substrate — a separate script, shared delivery path. | §3 is a *self*-guard, not a *consumer* probe; only the delivery is shared. |

## Open Questions (for `/plan`)

- **Q1 — Heartbeat cardinality.** Per-(host,target) = up to 4 beats (honest, no masking) vs per-target = 2 (cheaper, re-masks per-host breaks). Also: does §3's NIC guard emit its own beat or reuse an existing web-host signal? Resolve the beat topology before Terraform.
- **Q2 — git-data consumer health contract.** What does "reachable from a consumer" mean at `10.0.1.20` — git transport probe, an HTTP liveness endpoint, or a port check? (`git-data.tf:271` hints "curl `GIT_DATA_HEARTBEAT_URL` on success" but the *probe* target contract is unspecified.)
- **Q3 — Reserved `zot_heartbeat_url_prd` secret disposition.** Repoint to the new L3 heartbeat vs delete + mint fresh (CTO leaned repoint/delete; platform-strategist same). Reconcile the stale reservation comment (`zot-registry.tf:508`) in the same PR.
- **Q4 — Arming enum.** Use the unused `"external-probe"` for the new consumer rows, or keep `"web-host-cron"` (what `git_data_prd`/`registry_prd` use)?
- **Q5 — web-1 out-of-band arm mechanics.** `ci-deploy.sh` `docker create`→`docker cp` re-seed vs an SSH provisioner — pick the channel and its idempotence/verification (measured beat) proof.
- **Q6 — §3 reboot-on-mismatch interaction.** Does an ADR-115-style reboot-on-NIC-mismatch on a web host collide with the multi-host lease coordinator (ADR-068)? Web hosts are not single-active like the registry.
- **Q7 — Sequencing within the bundle.** Land delivery substrate + §3 (proven pattern) first, then the two consumer probes on the armed substrate? Or all in one PR? (CPO's inert-monitor caution argues for the substrate/§3 to prove the rail is read before the speculative consumer beats arm.)

## User-Brand Impact

- **Artifact:** the web-host private-net probe primitive (the L3 consumer probes + the §3 NIC guard on `10.0.1.10`/`.11`).
- **Vector:** a web host silently loses its private-NIC path to zot/git-data, falls back (GHCR / degraded), every health signal stays green, and the operator's deploys/data-access silently degrade for days — the #6400 shape, one host class over.
- **Threshold:** single-user incident.
- **Load-bearing risk (self-referential):** the probe primitive is *itself* a monitor that can go inert (web-1 dark behind a GREEN manifest, K5). The delivery honesty (measured beat from web-1) is the brand-critical acceptance criterion — a half-armed probe reads as coverage while providing none, which is worse than none (ADR-117).

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO), Legal (CLO), Engineering/Infra (platform-strategist). Marketing, Operations, Sales, Finance, Support — not relevant (internal infra; one finance/ops flag captured in K8).

### Engineering (CTO)
**Summary:** L3 is technically sound and closes a real residual gap over #6540 (consumer-side path breaks the self-ping can't observe). Caught the masking trap (K2). Blocker resolutions: bake-and-extract delivery, replay #6540/ADR-117 arming, systemd timer at 300/180-ish, inherit email-only. Small–medium build; no capability gaps.

### Engineering/Infra (platform-strategist)
**Summary:** Independently confirmed the masking trap and identified the **delivery trap as highest risk** (K5): the public-tunnel off-host poll can't reach the private NIC, and bake-only leaves web-1 dark behind a GREEN manifest. Delivery must be bake **+** out-of-band web-1 arm with a measured beat. Cadence: systemd timer with its own period; email-only.

### Product (CPO)
**Summary:** Dissented toward "defer L3, ship §3 first" — L3 closes a never-observed failure that didn't cause #6400, with HIGH inert-monitor risk. Reconciled into the bundle: §3 (proven pattern) is included and sequencing (Q7) can front-load it so the rail proves it's read before the speculative consumer beats arm.

### Legal (CLO)
**Summary:** No legal threshold — internal telemetry, existing sub-processor (Better Stack), no PII in the beat or the escalation webhook. A future paid-tier move is a finance/ops expense item, not legal.

## Premise Corrections (recorded for the plan/PR body)

- The issue cites **ADR-113** for private-NIC convergence; the real ADR is **ADR-115** (ADR-113 is an unrelated concierge ADR). Line numbers in the issue have drifted (`ignore_changes=[paused]` is at `zot-registry.tf:494/544`, not `:355`).
- **#6415 is CLOSED** — ADR-115's "#6415 stays open for [the off-host probe]" note is stale; the L3 tracker consolidated into **#6438 §1**.
- **#6540 (merged 2026-07-16)** armed the registry *self-ping* and explicitly leaves consumer-perspective reachability to #6438 §1 — the premise holds.

## Productize Candidate

None new — this *is* the reusable primitive (`#5274 PR C` vehicle). A follow-up **fallback-usage alarm** (sustained GHCR-fallback ⇒ zot down) is a candidate complementary signal, filed separately if the operator wants it.
