---
title: "fix(infra): web-2 fsn1 fresh-boot image-pull failure — diagnose via baked-DSN Sentry, fix the discriminated stage, restore log-shipping"
date: 2026-07-13
type: bug
status: draft
lane: cross-domain   # no spec.md for this branch — defaulted (TR2 fail-closed)
brand_survival_threshold: none
requires_cpo_signoff: false
issues: ["#6090", "#6178", "#6288", "#6389", "#5933"]
adrs_touched: ["ADR-096", "ADR-088", "ADR-068"]
---

# 🐛 fix(infra): web-2 fsn1 fresh-boot container image-pull failure

## Enhancement Summary

**Deepened on:** 2026-07-13
**Research inputs:** repo-research (infra boot-chain map, exact file:line), learnings-researcher (13 fresh-boot learnings), git-history (the #6090 arc + #6393 relocation), architecture-strategist review.

### Key improvements over the base plan
1. **Diagnose-then-fix structure grounded in the real pull path.** Confirmed the `until docker pull` loop (cloud-init.yml:513-528) is bounded to N=5 → `exit 1` at `stage=pull`, with a zot→GHCR atomic fallback — so the FATAL path requires BOTH registries to fail. The decisive evidence is the baked-DSN Sentry `stage`+`detail`; the plan pulls it in Phase 0 and branches the fix by a deterministic matrix (no blind fix).
2. **Root cause candidate localized (default Branch A):** the baked-vs-Doppler credential guard at cloud-init.yml:481,483 is **EMPTY-only** (grep-confirmed) — it does NOT re-fetch when a present-but-expired 1h ADR-088-minted token makes `docker login` FAIL. §1A extends the existing sibling idiom's guard predicate.
3. **Premise corrections (Research Reconciliation):** #6090 is CLOSED (recurrence via the #6393 `-replace`); the "Better Stack SOLEUR_* markers" the task named do NOT exist for weight-0 web-2 (Vector is gated off by `web_colocate_inngest=false`) → the boot channel is Sentry, and "ships logs" needs a real Vector-on-web-hosts fix; and hel1→fsn1 is provably NOT a DC-locality break.
4. **Gates satisfied:** Network-Outage Deep-Dive (4.5, L3→L7), Downtime & Cutover (4.55, zero-downtime by construction — web-2 serves zero traffic), User-Brand Impact (4.6, threshold none + sensitive-path scope-out), Observability 5-field schema (4.7, no-SSH discoverability), PAT-gate (4.8, reconciled false-positive on the App-minted read cred). All cited line-refs re-verified against the codebase.

### Architecture review folded (P1/P2)
- **P1-1 (must-fix):** Phase 0's Sentry query was pull-stage-scoped → a *post-pull* boot fatal (`webhook_bound`/`cloudflared_ready`/`plugin_seed`/poweroff gates) would return zero events and misroute to "Branch F (observability defect)". **Widened the query to all stages** + added **Branch G (pull OK, later fatal → re-scope, do NOT ship §1A)**.
- **P1-2:** Overview softened — pull-loop exhaustion is now the *suspected* death point (hypothesis), confirmed by Phase 0, not asserted.
- **P1-3/P1-4/P2-3:** Phase 2 scoped to **web-2 only** by default (web-1 = follow-up), delivery mechanism named (reuse inngest image-extraction, ungated), and the Vector install made **fail-open + sequenced after `:9000` bind** so observing the boot can't break it.
- **P2-1/P2-2:** de-anchored from Branch A — on a `-replace` the baked token is freshly minted (inside 1h TTL), so **Branch B (post-migration zot miss → GHCR fallback)** is the more probable real story; A and B are effectively one hypothesis. §1A line-ref corrected to `:484-490`.

### New considerations discovered
- If the Sentry read token is absent from Doppler, the boot channel is unreadable without SSH — that is itself a finding to escalate (observability gap), not a reason to ask the operator.

## Overview

The **web-2 warm-standby host** (fsn1, weight-0) fails its fresh boot before `:9000` binds, so the app container never serves. The task's reported symptom is an **image-pull** failure — the *suspected* death point is the `until docker pull` seed loop in `apps/web-platform/infra/cloud-init.yml` exhausting its 5 attempts and `exit 1`-ing the single-`/bin/sh` runcmd at `stage=pull`. **This is a hypothesis, not an established fact** — Phase 0 confirms the actual failing `stage` from telemetry before any fix is chosen (the boot has ~a dozen post-pull fatal stages too — `webhook_bound`, `cloudflared_ready`, `webhook_checksum`, `plugin_seed`, the two `poweroff -f` gates — any of which also prevents `:9000` from binding). web-2 provides **zero cross-DC failover coverage** while down (if web-1/hel1 fails, prod has no standby). Prod is unaffected today — web-1 is the sole live origin at LB weight 0-for-web-2.

This is the **recurring fresh-boot image-pull class** tracked by the now-CLOSED umbrella **#6090** (closed COMPLETED 2026-07-12) and its merged arc (#6076, #6092, #6116, #6119, #6125, #6131, #6136, #6161, #6363). web-2 was already wedged before the **hel1→fsn1 relocation (#6393, applied 2026-07-13 20:05 UTC)**; the relocation fixed the *capacity/apply-wedging* (a `-replace` during a hel1 stock outage could not re-place web-2) but the **boot itself still fails**. The relocation's `-replace` re-triggered the fresh boot, resurfacing the symptom.

**The pull path is engineered to survive hel1→fsn1** (verified against the codebase — see Research Reconciliation): GHCR is the primary/fallback registry over public egress (DC-agnostic), zot (`10.0.1.30:5000`, now in hel1) is an optional fail-open accelerator over the eu-central-zonal private net that spans fsn1, the GHCR read-credential is baked identically into both hosts, and host `docker pull`s are explicitly NOT filtered by the container (`DOCKER-USER`) egress allowlist. **So the root cause is NOT a DC-locality break.** It is named by the `tags.stage` + `detail` tag on the **baked-DSN Sentry fatal event** that the boot emits — the *only* no-SSH boot signal web-2 currently has.

This plan is therefore **diagnose-then-fix**, not fix-blind:

1. **Phase 0 (mandatory, in-session, no operator ask):** pull web-2's fresh-boot telemetry from the observability layer — the baked-DSN **Sentry** project `web-platform` (org `jikigai-eu`, eu.sentry.io) — read the fatal event's `tags.stage` + `detail`, cross-check the zot host's health, and produce a **decisive root-cause verdict** via a deterministic rule (per `hr-no-dashboard-eyeball-pull-data-yourself`).
2. **Phase 1+ (fix):** apply the **stage-specific** fix the verdict selects (a decision matrix below covers `ghcr_login`, `pull`, `verify`, `extract`, and the zot-OOM-forces-GHCR-fallback path), routed entirely through Terraform/cloud-init and applied via the existing no-SSH `web-2-recreate` dispatch.
3. **Cross-cutting deliverable ("ships logs"):** web-2 currently ships **nothing** to Better Stack — Vector (journald→Better Stack) is installed only inside the `web_colocate_inngest`-gated block (default `false`), so a weight-0 web host has no log pipeline at all. Install Vector on all web hosts so web-2's boot + app journald logs ship to Better Stack, giving a **second** no-SSH observability channel beyond the single baked Sentry DSN and satisfying the explicit success criterion "boots, serves, **and ships logs**."

**Success = web-2 completes a fresh boot, binds `:9000`, `web-platform-release`'s web-2 leg goes green, AND web-2's journald logs are queryable in Better Stack — restoring cross-DC failover coverage.**

## Research Reconciliation — Spec vs. Codebase

| Task premise | Codebase reality | Plan response |
|---|---|---|
| "Pull the actual boot telemetry from **Better Stack SOLEUR_* markers**" | web-2 ships **nothing** to Better Stack: Vector is installed only inside the `web_colocate_inngest`-gated runcmd (`cloud-init.yml:654`, default `false` `variables.tf:356-360`); `vector.toml` is hard-pinned `host_name="soleur-inngest-prd"` (`vector.toml:344,358`). The `SOLEUR_*` markers (`SOLEUR_ZOT_DISK` etc.) are the **zot host's** self-report channel, not web-2's. | Phase 0 pulls the **baked-DSN Sentry** emits (the real web-2 boot channel) + the zot-host `SOLEUR_ZOT_DISK`/heartbeat (registry-side). Log-shipping gap is fixed in this PR (Vector on web hosts) so the Better-Stack channel the task assumed actually exists next boot. |
| "registry **network/DNS from fsn1**" / cloud-init ordering are candidate root causes | Private net is `network_zone="eu-central"` spanning fsn1/hel1/nbg1 (`network.tf:24-34`); zot firewall allows intra-network by membership (`zot-registry.tf:310-315`); GHCR is public egress DC-agnostic; host pulls not in the `DOCKER-USER` allowlist (`cron-egress-allowlist.txt:72-74`). **No DC-locality break.** | Network hypotheses are kept in `## Hypotheses` in L3→L7 order per `hr-ssh-diagnosis-verify-firewall`, but ranked BELOW the Sentry-`stage` evidence, which is decisive. Do not "fix" a network layer without a Phase-0 signal pointing at it. |
| "recurring class … #6090" is OPEN | **#6090 is CLOSED/COMPLETED (2026-07-12).** Symptom recurred via the #6393 `-replace`. | This is a **fresh** occurrence of the closed class; file/reopen tracking per Acceptance Criteria — do not assume #6090's fixes are absent (they merged); assume a *new* stage is failing and let Phase 0 name it. |
| web-2 arch/tag mismatch for fsn1 | web-2 `server_type` defaults `cx33` = **amd64** (`variables.tf:82`); image is amd64 OCI; same tag as web-1 (`var.image_name`). No per-DC arch divergence. | Arch/tag hypothesis retained but ranked lowest; Phase 0 `pull_err` detail (`manifest unknown`/`no matching manifest`) would be the only signal that promotes it. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — web-2 is LB weight-0 and serves zero prod traffic; a broken fix leaves the status quo (web-2 still not a working standby). The *latent* cost is unchanged: continued **zero cross-DC failover coverage** — if web-1/hel1 fails, prod has no standby to absorb traffic.

**If this leaks, the user's data / workflow / money is exposed via:** no new exposure vector. The change touches only host bootstrap (image-pull credential handling + log shipping); it introduces no new user-data surface, no schema, no auth flow. Baked GHCR creds are already scoped read-only `read:packages` and already baked identically into both hosts (`server.tf:165-166`).

**Brand-survival threshold:** none

> `threshold: none, reason:` web-2 is weight-0 and serves zero production traffic; this change cannot regress any user-facing surface — its only blast radius is the resilience posture (failover coverage) of a non-serving standby. (Scope-out bullet required by preflight Check 6 because the diff touches sensitive infra paths.)

## Hypotheses

Ranked. The **decisive** evidence is the Phase-0 Sentry `tags.stage` + `detail`; the network layers below are the `hr-ssh-diagnosis-verify-firewall` L3→L7 discipline and MUST be verified before any service-layer conclusion **only if** Phase-0 telemetry does not already name the stage. Absence of a lower-layer signal is itself a signal (a `stage=pull` fatal with `pull_err: … i/o timeout` reaching `10.0.1.30` would promote L3; a `denied`/`401` promotes the credential hypothesis, not L3).

1. **[Sentry, decisive] `stage=ghcr_login` / `stage=pull` credential failure.** The baked GHCR minted token (ADR-088: 1h `packages:read` App installation token, rotated into `GHCR_READ_TOKEN` every 20 min) baked into web-2's user_data may be **expired-but-present** at boot. `cloud-init.yml:480-483` falls back to Doppler **only when the baked value is EMPTY**, not when it is present-but-expired → `docker login ghcr.io` fails silently (non-fatal subshell) → private-image `docker pull` → `denied` → 5 retries → `exit 1` at `stage=pull`. Detail signature: `ghcr_login_fail: … denied` or `pull_err: … denied/401`. **Most probable given the 1h token TTL + baked-vs-Doppler EMPTY-only fallback.**
2. **[Sentry + zot health] zot OOM-loop forces GHCR fallback, then (1) bites.** #6288 (OPEN) — zot restart-loops ~4/min (OOM on the store scan). If zot `/v2/` answers within the 3s probe (`cloud-init.yml:506`) but the specific manifest is missing (fresh hel1 volume post-migration is a disposable mirror re-filling from GHCR) OR zot dies mid-pull, REF flips to GHCR (emits `stage=app_ghcr_fallback` warning) — survivable UNLESS GHCR then fails per (1). Detail signature: an `app_ghcr_fallback` warning immediately preceding the `stage=pull` fatal.
3. **[Sentry] `stage=verify` stale/mis-built baked image.** If `var.image_name`'s baked `/opt/soleur/host-scripts/` content-hash ≠ `local.host_scripts_content_hash`, extract-then-verify `exit 1`s at `stage=verify`. The `web2-recreate-preflight.sh` gate (`scripts/web2-recreate-preflight.sh:87-99`) is designed to prevent exactly this before a `-replace`; a `stage=verify` fatal means the preflight was bypassed or the pinned digest drifted. Detail signature: `stage=verify`, no `detail` tail.
4. **[L3 firewall/egress] host cannot reach ghcr.io / 10.0.1.30 from fsn1.** Verification: `hcloud firewall describe` for web-2's firewall + confirm host egress is unrestricted (host pulls bypass `DOCKER-USER`). Expected: no block (host egress is open; the container firewall is not on this path). Promote ONLY on a `pull_err: … timeout/connection refused` reaching the registry IP.
5. **[L3 DNS/routing] fsn1 resolver cannot resolve ghcr.io.** Verification: the `stage=pull` `detail` would carry a `no such host`/`server misbehaving` tail. Promote only on that signal.
6. **[L7 arch/tag] amd64/tag mismatch.** Lowest — web-2 is amd64 cx33, same tag as web-1. Promote only on `manifest unknown`/`no matching manifest for linux/amd64`.

### Network-Outage Deep-Dive (deepen-plan Phase 4.5 — `hr-ssh-diagnosis-verify-firewall`)

Triggered by `timeout`/`firewall`/`unreachable`/`DNS` in the Hypotheses AND by the resource-shape trigger (`apply -replace` on `hcloud_server.web`, whose web-1 instances carry `provisioner "file"`/`remote-exec`+`connection{ssh}` blocks — though web-2's `-replace` is cloud-init-only, no SSH provisioner). L3→L7 verification status — **verified layers are decisive only via Phase-0 telemetry; do not "fix" a layer without a Sentry signal pointing at it**:

- **L3 firewall allow-list:** *not verified at plan time; verified in Phase 0 IF telemetry shows a timeout.* Artifact to capture at /work: `hcloud firewall describe` for web-2's firewall. Code evidence that it is NOT the cause: host `docker pull`s (GHCR public egress + zot on the private net) are explicitly excluded from the container `DOCKER-USER` allowlist (`cron-egress-allowlist.txt:72-74`), and the zot host allows intra-network by membership (`zot-registry.tf:310-315`). **Opt-out justification:** host egress is unrestricted by design; the container firewall is not on the host-pull path. Promote L3 ONLY on a `pull_err: … i/o timeout / connection refused` reaching the registry IP.
- **L3 DNS/routing:** *not verified at plan time.* fsn1↔hel1 private routing is intra-`eu-central`-zone (`network.tf:24-34`) so `10.0.1.11→10.0.1.30` is routable; ghcr.io is public. Promote ONLY on a `pull_err: … no such host / server misbehaving` tail.
- **L7 TLS/proxy:** N/A — the seed pull is plain-HTTP to zot on the private net and TLS to ghcr.io; no CDN/edge intermediary on the pull path.
- **L7 application:** the "journalctl for the client IP" analogue here is the **baked-DSN Sentry `stage` tag** (web-2 has no journald shipping pre-Phase-2). Absence of any Sentry boot event = Branch F (boot died pre-beacon / DSN empty), which is itself the L7 signal that the packet never reached the emitter.

**Ordering discipline:** the Sentry `stage`+`detail` is the L7 signal that tells you whether to even look at L3. A `stage=pull` fatal with `detail=… denied/401` is an application-credential failure, NOT a network layer — do not run the L3 checklist for it.

## Downtime & Cutover (deepen-plan Phase 4.55 — zero-downtime-first)

**Trigger:** infra reboot/replace class — the fix is applied via `terraform apply -replace=hcloud_server.web["web-2"]` (`apply-web-platform-infra.yml apply_target=web-2-recreate`).

**Offline-inducing operation + surface:** the `-replace` destroys and recreates web-2. **Surface affected: none that serves traffic.** web-2 is LB weight-0 and currently does NOT serve (it never booted). Destroying a non-serving host is **zero-downtime by construction** — there is no in-flight request to drop and no LB member to drain.

**Zero-downtime path (default, and already the design):** this IS the blue-green cutover pattern (`2026-07-02-zero-downtime-first-moved-block-statemv-and-blue-green-cutover.md`): a fresh web-2 is born into the fleet with no traffic; only when it boots green AND the ADR-068 §(c) `lb-weight-gate.sh` passes would its LB weight ever rise above 0 — and that weight-flip is **explicitly out of scope** for this plan (it restores the boot, not the traffic weight). web-1 (the sole live origin) is untouched by the web-2 `-replace` (scoped `-target`).

**web-1 is not touched by this plan (review P2-3).** Phase 2 is scoped to **web-2 only** by default, so there is no web-1 `-replace` risk in this PR at all — web-1 Vector log-shipping is an explicit follow-up issue. (Were web-1 ever brought in, the guard stands: it must ride web-1's infra-config/immutable-redeploy channel, never a `user_data` change / `-replace` = prod drop.) No bounded maintenance window is needed anywhere — the web-2 boot fix and the web-2 Vector add are both zero-downtime on a non-serving host.

## Implementation Phases

### Phase 0 — Pull the boot telemetry and produce a root-cause verdict (no SSH, no operator ask)

> This phase runs **in-session** at `/work` time. It reads prod telemetry read-only via Doppler-vended tokens; it does NOT ask the operator to fetch anything (`hr-no-dashboard-eyeball-pull-data-yourself`). It writes its verdict into the PR body + a `## Root-Cause Verdict` note so the fix branch chosen in Phase 1 is evidence-backed (`2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface.md`).

0.1 **Resolve the Sentry read token + project** (read-only):
```bash
export SENTRY_TOKEN=$(doppler secrets get SENTRY_IAC_AUTH_TOKEN --plain -p soleur -c prd_terraform 2>/dev/null \
  || doppler secrets get SENTRY_AUTH_TOKEN --plain -p soleur -c prd 2>/dev/null)
# org: jikigai-eu  project: web-platform  base: https://jikigai-eu.sentry.io/api/0/
```
(If neither token is present in Doppler, that itself is a finding — the boot channel is unreadable without SSH; record it and escalate the observability gap, do NOT fall back to asking the operator to open the dashboard.)

0.2 **Query web-2's fresh-boot events — ALL stages, not a pre-scoped enum** — since the #6393 apply (`2026-07-13T20:05:00Z`). **Do NOT filter to pull-stages only**: the symptom is "`:9000` never binds," which a *post-pull* fatal (`webhook_bound` `:599`, `cloudflared_ready` `:583`, `webhook_checksum` `:591`, `plugin_seed` `:645`, the `poweroff -f` gates `:728`/`:762`) also produces — those emit `stage` values outside the pull enum, so a pull-only filter returns zero events and would misroute to Branch F (see decision matrix). Query the whole window and read whichever `stage` actually appears:
```bash
curl -s -H "Authorization: Bearer $SENTRY_TOKEN" \
  "https://jikigai-eu.sentry.io/api/0/projects/jikigai-eu/web-platform/events/?query=$(python3 -c 'import urllib.parse;print(urllib.parse.quote("has:stage timestamp:>2026-07-13T20:05:00"))')&full=true" \
  | jq -r '.[] | {ts:.dateCreated, level:.tags[]?|select(.key=="level")|.value, stage:(.tags[]|select(.key=="stage")|.value), detail:(.tags[]?|select(.key=="detail")|.value), host:(.tags[]?|select(.key=="host_id")|.value), msg:.message}'
```
Capture the **latest fatal** event per boot and its `stage` + `detail`, AND whether any later `stage=cloud_init_complete` (`:767`) appears (a green boot). (If the Sentry API shape differs, verify the events endpoint against the org-subdomain base URL per `2026-05-17-sentry-eu-region-host-rewrites-slugs-with-eu-suffix.md` — the `-eu` org routes to the literal `eu` region.)

0.3 **Cross-check zot host health** (rule in/out Hypothesis 2): pull the zot host's `SOLEUR_ZOT_DISK` self-report + `/v2/` heartbeat state from Better Stack (the zot host DOES run its reporter) and confirm whether #6288's OOM-loop was active in the incident window. Read-only.

0.4 **Emit the verdict** using this deterministic rule (write to PR body + `## Root-Cause Verdict`):

| Observed `stage` (+ `detail`) | Verdict → Phase 1 branch |
|---|---|
| `ghcr_login` `ghcr_login_fail: … denied/401/expired` **or** `pull` `pull_err: … denied/401` | **Branch A** — baked GHCR token expired-but-present; harden fallback (§1A). |
| `ghcr_login` `ghcr_creds_missing user=n/token=n` | **Branch A′** — baked template vars empty; fix `var.ghcr_read_*` bake (§1A′). |
| `app_ghcr_fallback` warning then `pull` fatal | **Branch B** — zot forced fallback + Branch A; also file/verify #6288. |
| `pull` `pull_err: … timeout / connection refused / no route` to registry IP | **Branch C** — L3 network; run the L3→L7 checklist, fix firewall/routing (§1C). |
| `pull` `pull_err: … no such host / server misbehaving` | **Branch C′** — L3 DNS; fix resolver (§1C). |
| `verify` (no detail) | **Branch D** — stale baked image; re-pin known-good digest, re-run preflight (§1D). |
| `pull` `manifest unknown / no matching manifest` | **Branch E** — arch/tag; fix ref resolution (§1E). |
| **`pull` OK (or `cloud_init_complete` absent) but a POST-PULL fatal** — `stage=webhook_bound / cloudflared_ready / webhook_checksum / plugin_seed`, or a `poweroff -f` gate | **Branch G** — the pull succeeded; the boot dies LATER. This is NOT an image-pull fix — re-scope to the named post-pull stage (do not ship §1A). The task's "image-pull" framing was the hypothesis; telemetry overrides it. |
| **No events at all** in window | **Branch F** — baked DSN empty / boot died before the bootcmd beacon. Treat observability as the primary defect (§1F); use Hetzner rescue-console `cloud-init-output.log` ONLY as a last resort, documented. (Reached only after 0.2's all-stage query genuinely returns nothing — a pull-only filter false-routing here is the P1 the widened query fixes.) |

### Phase 1 — Apply the discriminated fix (the branch Phase 0 selected)

Only the selected branch's change ships. The code change is gated on the Phase-0 verdict — do NOT ship a blind fix. **Note (review P2-1/P2-2):** on a `-replace`, `user_data` is re-rendered at create time from the current `var.ghcr_read_token` (a ≤20-min-fresh ADR-088-minted token — `ignore_changes` suppresses in-place diffs, not create-time computation), so a *plain* recreate bakes a token well inside the 1h TTL. "Expired-but-present" (§1A) therefore requires **minter drift/outage**, and Branch A only bites when zot ALSO misses (the host logs into zot independently at `:497`; a zot hit pulls before any GHCR flip). The more probable real story is **Branch B** (post-migration fresh hel1 zot volume → manifest miss → GHCR fallback → then whatever GHCR returns) — A and B are effectively one combined hypothesis. Stay telemetry-first; do NOT pre-anchor on A. §1A is still the correct *durable* hardening for the credential path regardless.

- **§1A — Doppler re-fetch on baked-login FAILURE, not only EMPTY.** In `cloud-init.yml` `STAGE=ghcr_login` block — the EMPTY-only guards are at `:481,483` and the login attempt to harden is the `if/elif/else` at **`:484-490`**: change the logic so a Doppler re-fetch + `docker login` retry also fires when the baked login **fails** (expired/invalid token), not only when the baked value is EMPTY. Shape: attempt baked login; on non-success, unconditionally re-fetch `GHCR_READ_{USER,TOKEN}` from Doppler (existing timeout-45/3-retry idiom) and retry `docker login`; record the outcome in `/run/soleur-stage-detail`. Keep the subshell fail-open. This closes the "present-but-expired 1h minted token" hole for every future fresh boot on both hosts.
  - **Precedent-diff (deepen 4.4):** the existing idiom at `cloud-init.yml:481,483` is `[ -n "$GHCR_USER" ] || { until … doppler secrets get … }` — an **EMPTY-only** guard (confirmed by grep). The fix reuses that exact `until … timeout 45 … 3-retry` Doppler-fetch body but changes the **guard predicate** from "baked value empty" to "baked login failed OR empty" (attempt `docker login` with baked creds first; on non-zero exit, run the same fetch+retry). No novel pattern — it extends the sibling idiom already in this file, so the diff is a predicate change + a second `docker login` attempt, not new machinery.
- **§1A′ — baked template vars empty.** Trace `var.ghcr_read_user`/`var.ghcr_read_token` from `ghcr-read-credential.tf` → `server.tf:165-166` templatefile → the bake at `cloud-init.yml:416-418`; fix the empty-at-render path (likely a Doppler source drift at apply). Add an apply-time assertion that the baked vars are non-empty before a `web-2-recreate`.
- **§1B — zot forced fallback.** Ship §1A; additionally verify #6288's zot OOM remediation is live (the fallback path must reliably reach GHCR). No zot code change here unless Phase 0 shows zot itself is the fatal layer.
- **§1C — L3 network/DNS.** Only on a Phase-0 timeout/DNS signal: run the full L3→L7 checklist (`plan-network-outage-checklist.md`), diff `hcloud firewall describe` against the host, fix the routing/resolver layer, paste the artifact into `## Root-Cause Verdict`.
- **§1D — stale baked image.** Re-pin the `web-2-recreate` to a known-good digest via `resolve-web1-known-good-tag.sh` and re-assert `web2-recreate-preflight.sh` (baked host-scripts hash == `local.host_scripts_content_hash`) before the `-replace`. No cloud-init edit.
- **§1E — arch/tag.** Fix the effective-ref resolution / manifest selection in the seed block; verify the pinned digest is a multi-arch or amd64 manifest.
- **§1F — no telemetry.** Assert `var.sentry_dsn` bake is non-empty (the web2-recreate preflight already guards this — `variables.tf:252` note); this branch means that guard failed or the boot died pre-beacon → the real fix is making the boot observable (feeds Phase 2).

### Phase 2 — Restore web-2 log-shipping ("ships logs" success criterion + second no-SSH channel)

web-2 currently installs **no Vector**, so it ships nothing to Better Stack. **Scope this to web-2 only** (review P2-3): the success criterion is "*web-2* ships logs," and bundling all web hosts pulls prod web-1 into an image-pull boot bugfix. web-1 log-shipping is an explicit **follow-up issue**, not this PR.

- **Delivery mechanism (review P1-4 — name it, don't leave it to /work).** Today Vector's binary + `vector.toml` reach a host ONLY via the inngest-bootstrap image extraction (`cloud-init.yml:694`, `VECTOR_CLI_VERSION` from the image `Config.Env`); a non-inngest web host has no such path. Choose ONE and state it in the diff: (a) reuse the same image-extraction install but ungated by `web_colocate_inngest` (preferred — same binary source, no new download, no lockstep with a second delivery path), delivering a **web-host** `vector.toml` (`host_name` derived per-host `soleur-${host_id}`, not the pinned `soleur-inngest-prd`); or (b) a `write_files` + pinned-checksum download. Whichever — respect the **32 KB `user_data` cap** (bake bodies into `soleur-host-bootstrap.sh`, carry only the call-site inline).
- **Fail-open + sequenced AFTER bind (review P1-3 — load-bearing).** The web-host Vector install is a NEW runcmd surface on the very boot this PR is stabilizing. It MUST (i) run **after** `:9000` binds / `stage=cloud_init_complete` (`:767`), and (ii) be **fail-open** — a Vector install/enable failure emits a warning breadcrumb but NEVER `exit 1`s the runcmd (wrap in `( set +e … ) || true`, no `set -e` arm). Vector observing the boot must not be able to break the boot.
- Ship journald (`_SYSTEMD_UNIT` incl. `webhook.service`, the app container's journald log-driver output, the boot runcmd) to the existing Better Stack Logs source.

> Scope discipline: Phase 2 does NOT add per-host uptime monitors (removed deliberately, `uptime-alerts.tf:79-88`) or re-introduce the removed per-host absence detector (#5933 tracks that separately). web-2-only keeps the blast radius on the weight-0 host and removes the dual-path lockstep hazard. If Phase 0 selects Branch F (no telemetry), Phase 2 becomes the primary deliverable regardless.

### Phase 3 — Verify on a real fresh boot (no SSH)

Apply via the existing no-SSH dispatch and verify off-host:

1. Dispatch `apply-web-platform-infra.yml` `workflow_dispatch` with `apply_target=web-2-recreate` (scoped `-replace` of `hcloud_server.web["web-2"]`, re-runs first-boot cloud-init) after the PR merges. `web2-recreate-preflight.sh` gates the pinned digest.
2. Confirm from telemetry (NOT SSH): the baked-DSN Sentry emits reach `stage=cloud_init_complete` (info) with **no** `stage=pull/verify` fatal; the `web-platform-release` web-2 leg reports `ok_peer_fanout` (not `ok_peer_fanout_degraded`); and web-2's journald now appears in Better Stack (Phase 2).
3. Confirm the LB-weight gate remains 0 (this plan restores the standby's *boot*, not its traffic weight — the ADR-068 §(c) weight-flip is out of scope and gated separately by `lb-weight-gate.sh`).

## Files to Edit

- `apps/web-platform/infra/cloud-init.yml` — §1A/§1A′/§1E seed-block credential-fallback + ref-resolution hardening (branch-selected); Phase 2 web-host Vector install path. **Watch the 32,768-byte user_data cap** (`2026-07-03-cloud-init-32kb-cap-bake-and-extract-not-compress.md`): comments count; if the edit grows user_data, bake bodies into `soleur-host-bootstrap.sh` and carry only the call-site inline. **Watch col-0 `%{` templatefile directives** (`2026-07-11-col0-templatefile-directive-breaks-raw-yaml-parsers-sweep-all.md`): if adding a `%{ if ~}` guard, sweep ALL raw YAML parsers.
- `apps/web-platform/infra/vector.tf` — extend Vector install/config to web hosts (Phase 2).
- `apps/web-platform/infra/vector.toml` — parameterize `host_name` off the hard-pinned `soleur-inngest-prd` (Phase 2).
- `apps/web-platform/infra/variables.tf` — if Phase 2 needs a `web_ship_logs`-style toggle (default true) or per-host host_name plumbing; §1A′ apply-time non-empty assertion for `ghcr_read_*`.
- `apps/web-platform/infra/server.tf` — only if §1A′ requires the templatefile bake path change.
- **Tests to update in the same PR** (sibling guards — enumerate via `git grep`, do not trust this list): `cloud-init-ghcr-seed-login.test.sh`, `cloud-init-user-data-size.test.ts` (32KB cap), `journald-config.test.sh` + `cloud-init-inngest-bootstrap.test.sh` (raw-YAML parsers if a col-0 directive is added), any `vector`/`web-hosts-fanout-parity`/`registry-insecure-config` parity test the Vector change touches. Run `git grep -lnE 'safe_load|yaml\.load' -- '*.test.sh' '*.test.ts' '*.py'` and `git grep -ln 'vector' -- apps/web-platform/infra/*.test.*` before freezing the list.

## Files to Create

- `knowledge-base/project/learnings/2026-07-13-web-2-fsn1-fresh-boot-image-pull-<discriminated-cause>.md` — capture the Phase-0-verified root cause + the fallback-hardening fix (date/name at write time, not pinned).
- Possibly a small `scripts/followthroughs/` probe if an AC declares a post-deploy soak (see Observability §soak) — only if a soak criterion is adopted.

## Infrastructure (IaC)

### Terraform changes
- Files: `apps/web-platform/infra/{cloud-init.yml, vector.tf, vector.toml, variables.tf, server.tf}` — all inside the existing `apps/web-platform/infra/` Terraform root (R2 backend, already provisioned). No new root, no new provider.
- Sensitive vars: none new. Existing `TF_VAR_ghcr_read_user`/`TF_VAR_ghcr_read_token` (Doppler `soleur/prd`, minted by ADR-088 minter), `TF_VAR_sentry_dsn`, Better Stack source token — all already provisioned. Per `hr-tf-variable-no-operator-mint-default`, no new no-default operator-mint var is introduced (Phase 2 `host_name` is derived, not operator-minted).
- **PAT-gate reconciliation (deepen 4.8 / `hr-github-app-auth-not-pat`):** the deepen-plan Phase 4.8 grep mechanically matches the pre-existing `var.ghcr_read_token` (pattern `var.*_token`). This is a **false positive, not a violation**: `ghcr_read_token` is a read-only `packages:read` **GHCR pull** credential that is **already GitHub-App-installation-minted** by the control-plane minter (**ADR-088** — "control-plane installation token minter for private GHCR reads"), i.e. it IS the App-auth pattern `hr-github-app-auth-not-pat` mandates — not a static PAT and not for GitHub *writes*. This plan introduces no new PAT-shaped variable; it only references the existing App-minted read cred. No remediation needed.

### Apply path
- **(c) scoped `-replace`** — `apply-web-platform-infra.yml` `workflow_dispatch` `apply_target=web-2-recreate`. web-2 carries `ignore_changes=[user_data, ssh_keys, image, placement_group_id]` (`server.tf:204`), so an in-place update does NOT re-apply cloud-init; only a destroy+create picks up the fix. Blast radius: web-2 only (weight-0, zero prod traffic). `web2-recreate-preflight.sh` gates the pinned digest so the `-replace` cannot re-abort at `stage=verify`.
- The Vector-on-web-1 change (Phase 2) reaches the RUNNING web-1 via its existing infra-config redeploy path (web-1 has SSH provisioners); it must NOT force a web-1 `-replace` (that would drop prod). Verify web-1's Vector install rides the immutable-redeploy/infra-config channel, not a user_data change (web-1 carries `ignore_changes=[user_data]` too). If web-1 cannot receive Vector without a reboot, scope Phase 2 to web-2 only and file web-1 as a follow-up.

### Distinctness / drift safeguards
- `dev != prd`: infra is prd-only; no dev counterpart. The `web-2-recreate` is push-button, guarded by preflight + the R2 `web-1-swap` serializer (`apply-web-platform-infra.yml:441,661`) so it cannot race the release deploy.
- `lifecycle.ignore_changes` on web-2 is load-bearing (above); do not remove it.

### Vendor-tier reality check
- Better Stack Logs source already exists (used by the inngest host). Adding web-host sources consumes the existing plan's log volume — confirm the Better Stack tier headroom (ops-advisor ledger) before enabling on all hosts; if the free/current tier caps sources, gate Phase 2 behind a `web_ship_logs` bool (default true) and note the tier in the plan.

## Observability

```yaml
liveness_signal:
  what: baked-DSN Sentry emit `stage=cloud_init_complete` (info) on a fully-serving web-2 boot; absence of any `stage=pull/verify/ghcr_login` fatal in the boot window
  cadence: once per fresh boot (web-2-recreate); web-platform-release web-2 leg reports ok_peer_fanout per deploy
  alert_target: Sentry project web-platform (org jikigai-eu); the mirror-staleness fallback-rate alarm already pages on app_ghcr_fallback (#6278)
  configured_in: cloud-init.yml (baked _emit + soleur-boot-emit), sentry/*.tf
error_reporting:
  destination: Sentry (baked DSN) for pre-container boot stages; Better Stack Logs (NEW, Phase 2) for journald once Vector installs on web hosts
  fail_loud: yes — seed pull exit 1 fires the top-armed on_err trap → Sentry fatal with tags.stage + detail; runcmd aborts (no silent continue)
failure_modes:
  - mode: image-pull exhausts 5 retries (both zot + GHCR fail)
    detection: Sentry event tags.stage=pull + detail=pull_err tail (in-boot, baked DSN)  # affected-surface probe: emitted FROM the booting host, not host-side
    alert_route: Sentry web-platform project
  - mode: baked GHCR token expired-but-present -> login fail -> private-pull denied
    detection: Sentry tags.stage=ghcr_login detail=ghcr_login_fail:...denied  (discriminates cred-expiry vs missing vs network via the detail tag)
    alert_route: Sentry web-platform project
  - mode: zot miss/OOM forces GHCR fallback
    detection: Sentry warning tags.stage=app_ghcr_fallback (#6278 fallback-rate alarm) + zot SOLEUR_ZOT_DISK Better Stack self-report
    alert_route: soleur mirror-staleness fallback-rate alarm
  - mode: web-2 boots but ships no journald (pre-Phase-2 state)
    detection: web-2 host absent from Better Stack Logs sources  (Phase 2 closes this)
    alert_route: Better Stack Logs
logs:
  where: Sentry (boot stages, baked DSN, always); Better Stack Logs (journald, after Phase 2 Vector install); Hetzner rescue-console cloud-init-output.log (SSH/console-only, last resort)
  retention: Sentry per project retention; Better Stack per source retention
discoverability_test:
  command: curl -s -H "Authorization: Bearer $SENTRY_TOKEN" "https://jikigai-eu.sentry.io/api/0/projects/jikigai-eu/web-platform/events/?query=stage:cloud_init_complete&statsPeriod=24h" | jq 'length'   # NO ssh
  expected_output: ">=1 after a successful web-2-recreate (a green boot emits cloud_init_complete); 0 with a stage=pull/verify fatal present = still broken"
```

## Architecture Decision (ADR/C4)

- **### ADR — amend, do not create.** The image-pull fix is a **bug fix on existing decisions** (ADR-096 zot registry, ADR-088 GHCR minter), not a new architectural decision — no new ADR. The §1A credential-fallback hardening (Doppler re-fetch on baked-login *failure*, not only EMPTY) is a small robustness note to append to **ADR-088**'s consequences (the minted-token TTL vs baked-value staleness interaction). **Amend ADR-088** with a one-line note; do not file a new ordinal.
- **### C4 views — Container view edge added (Phase 2, web-2).** Phase 2 adds a **new edge**: `web-2 → Better Stack Logs` (journald via Vector). Today only the inngest host has this edge. External systems checked against all three `.c4` files: **GHCR** (external, already modeled as the registry edge), **zot registry** (internal container, modeled ADR-096), **Better Stack** (external log sink — currently only the inngest→Better Stack edge is modeled), **Sentry** (external, modeled). The web-host→Better Stack edge is NOT yet modeled → when Phase 2 ships, add the element edge + `view include` line in `views.c4` and run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`. If the C4 model already renders web hosts as a single generic "web host" element sharing the inngest edge semantics, a description touch-up may suffice — decide by reading the model, not a grep. **This is a work read-all-three-`.c4`-files task, not a grep.**
- **### Sequencing** — ADR-088 amendment ships with the §1A fix; the C4 edit ships with Phase 2. Both in THIS feature's lifecycle, not deferred.

## Domain Review

**Domains relevant:** Engineering (infra) only.

### Engineering / Infra

**Status:** reviewed (planner assessment; CTO/infra lens)
**Assessment:** Pure infrastructure bug fix + observability extension on an already-provisioned Terraform root. Concerns for plan-review's infra lens (platform-strategist / terraform-architect): (a) the `web-2-recreate` blast radius is correctly scoped to a weight-0 host; (b) Phase 2's web-1 Vector install MUST NOT force a web-1 `-replace` (drops prod) — flagged in the IaC section; (c) the credential-fallback change must stay fail-open (subshell) so it cannot itself abort the boot; (d) 32KB user_data cap + col-0 directive sweeps are live traps. No product/marketing/legal/finance/sales/support implications.

### Product/UX Gate

Not relevant — no user-facing surface (`## Files to Create`/`Edit` contain no `components/**`, `app/**/page.tsx`, or UI paths). NONE.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1 (Phase 0 verdict is evidence-backed).** The PR body `## Root-Cause Verdict` names the observed Sentry `tags.stage` + `detail` for web-2's fresh boot in the post-#6393 window, or explicitly records "no events" (Branch F). No fix branch ships without a verdict. Verify: `## Root-Cause Verdict` section present and cites a concrete `stage` value.
- [ ] **AC2 (fix matches verdict).** The cloud-init/vector diff corresponds to the branch the Phase-0 verdict selected (per the decision matrix). Verify: diff touches only the selected branch's lines; no blind multi-branch change.
- [ ] **AC3 (fail-open preserved).** The §1A credential re-fetch stays inside the `( set +e … ) || true` subshell — `grep -n` confirms the new `docker login` retry cannot `exit 1` the runcmd. A cred failure must still let the pull emit `stage=pull`.
- [ ] **AC4 (32KB cap).** `cloud-init-user-data-size.test.ts` passes — rendered web user_data < its pinned cap. Verify: run the test; paste the measured byte count.
- [ ] **AC5 (raw-YAML parser sweep).** If any col-0 `%{` directive was added, every parser from `git grep -lnE 'safe_load|yaml\.load' -- '*.test.sh' '*.test.ts' '*.py'` strips `^%{` before parsing and passes. If no directive added, record "no col-0 directive added".
- [ ] **AC6 (sibling guards).** `cloud-init-ghcr-seed-login.test.sh` and any Vector parity test updated + green.
- [ ] **AC7 (ADR-088 amended).** ADR-088 carries the one-line baked-token-staleness-vs-minter-TTL note; no new ADR ordinal created.
- [ ] **AC8 (typecheck/tests).** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; the touched infra `*.test.sh`/`*.test.ts` pass (run via the repo's actual runner — check `package.json scripts.test` / `bunfig.toml`, do NOT assume).
- [ ] **AC9 (issue linkage).** PR body uses `Ref #6090` / `Ref #6389` (NOT `Closes` — the boot is only proven fixed post-merge by the `web-2-recreate` apply; closure lives in the post-merge step per the ops-remediation `Ref`-not-`Closes` rule).

### Post-merge (operator/automated)
- [ ] **AC10 (green fresh boot).** After merge, dispatch `apply-web-platform-infra.yml` `apply_target=web-2-recreate`; the baked-DSN Sentry emits reach `stage=cloud_init_complete` with no `stage=pull/verify/ghcr_login` fatal. Verify via the Observability `discoverability_test` curl (no SSH). Automatable via `gh workflow run` + the Sentry API — NOT an operator dashboard eyeball.
- [ ] **AC11 (release leg green + failover restored).** `web-platform-release` web-2 leg reports `ok_peer_fanout` (not `_degraded`); web-2 binds `:9000`.
- [ ] **AC12 (ships logs).** web-2's journald appears as a Better Stack Logs source (Phase 2). Verify via the Better Stack API (no SSH).
- [ ] **AC13.** `gh issue close`/comment the reopened/new tracking issue only AFTER AC10–AC12 pass.

## Test Scenarios

- **Unit/config:** rendered user_data byte size (< cap); raw-YAML parse of the templated cloud-init (col-0 strip); ghcr-seed-login regression (`cloud-init-ghcr-seed-login.test.sh`); Vector web-host config parity + host_name derivation.
- **Behavioral (fail-open):** a synthesized empty/expired baked token must produce a Doppler re-fetch + `stage=pull` emit, never a runcmd abort in the login block (test against the extracted seed-block logic, LLM/network removed from the assertion path).
- **Integration (post-merge, real boot):** the `web-2-recreate` fresh boot reaches `cloud_init_complete`; asserted via Sentry API, not SSH.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/placeholder, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan sets `threshold: none` with the required sensitive-path scope-out reason.
- **Do NOT ship a blind fix.** The recurring nature (#6090 arc merged multiple stage-specific fixes) means the *previous* fixes are present; a new occurrence is a *new* stage. Phase 0's Sentry `stage` is decisive — shipping §1A without the verdict risks the #5716/#5584-class wrong-layer fix (fixed a path the surface never executes). See `2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface.md`.
- **Phase 2 web-1 Vector must not force a web-1 `-replace`** — that drops prod. Route it through web-1's infra-config/immutable-redeploy channel or scope Phase 2 to web-2 and defer web-1.
- **The baked-vs-Doppler EMPTY-only fallback is the suspected hole** (`cloud-init.yml:480-483`) — the fix must fire the Doppler re-fetch on baked-login *failure*, not only when the baked value is EMPTY. An expired-but-present token is the exact case the current code misses.
- **`web-2-recreate` preflight is load-bearing** — `web2-recreate-preflight.sh` must confirm the pinned digest's baked host-scripts hash == `local.host_scripts_content_hash`, else the `-replace` re-aborts at `stage=verify` (Branch D would then be a false positive).
- **Sentry EU org slug quirk:** the `jikigai-eu` org routes to the literal `eu` region; use the org-subdomain base URL for slug-scoped API paths (`2026-05-17-sentry-eu-region-host-rewrites-slugs-with-eu-suffix.md`). Verify the events endpoint shape before relying on the Phase-0 query.
- **32KB user_data cap + col-0 directive sweep** are the two live cloud-init traps (see Files to Edit).

## Open Code-Review Overlap

Checked planned files (`cloud-init.yml`, `vector.tf`, `vector.toml`, `variables.tf`, `server.tf`, `zot-registry.tf`) against 62 open `code-review` issues. Two `server.tf` substring matches — **#3216** (dpf-regex canary-bundle) and **#2197** (billing SubscriptionStatus) — are unrelated concerns (not web-host boot). **Disposition: Acknowledge** (different concern; both remain open, neither touches the seed-pull/Vector surfaces this plan edits). No fold-in.


## Root-Cause Verdict

**Branch A (deploy-path variant) — GHCR `auth_denied` on a stale baked read-credential; zot fallback cushion absent.** Evidence pulled in-session, no SSH, no operator ask (`hr-no-dashboard-eyeball-pull-data-yourself`).

| Signal | Source | Value |
|---|---|---|
| web-2 identity | Hetzner API | host_id `150638239` = `soleur-web-2`, fsn1, created 2026-07-13T20:06:32Z (#6393 `-replace`) |
| Boot progressed past pull | Sentry `WEB-PLATFORM-4S` (baked DSN) | `bootcmd_start`→`cloudflared_ready`→`webhook_bound` (info); **no fatal, no `pull`/`ghcr_login`/`verify` stage** |
| Actual failure | Release run `29282414740` deploy leg | `ci-deploy.sh exited 1 (reason=image_pull_failed, tag=v0.213.4)` — aggregate JSON = web-2 (fresh: 70G, vector+inngest inactive) |
| Terminal cause | Sentry `WEB-PLATFORM-59` | `image pull failed (auth_denied) ghcr.io/jikig-ai/soleur-web-platform:v0.213.4`, last 2026-07-13T20:39:22Z; deploy failed in 5 s (not a timeout) |
| No fallback cushion | Sentry `WEB-PLATFORM-57` | `zot gate degraded (probe_unreachable)` (#6288, OPEN) → `ZOT_ACTIVE=0` → direct GHCR path |
| Credential is VALID now | Live GHCR token exchange (Doppler `prd` cred) | bearer OK → manifest `v0.213.4` **HTTP 200** (anon → 401). Fix is re-fetch-on-failure, NOT credential rotation. |
| Code gap | `apps/web-platform/infra/ci-deploy.sh:639-644,650-654` | Doppler GHCR re-fetch fires only when baked `GHCR_READ_{USER,TOKEN}` is **EMPTY**; a baked `docker login` **failure** is non-fatal → present-but-stale baked token → anonymous/stale private pull → 401. Same EMPTY-only class also in `cloud-init.yml` seed login. |

**Fix (Phase 1 §1A):** in `ghcr_prelude_and_login` (proven site) — attempt baked `docker login`; on failure (or empty), re-fetch `GHCR_READ_{USER,TOKEN}` from Doppler (hardened `timeout 45`/3-retry idiom) and retry login; fail-open. Mirror the same predicate change in `cloud-init.yml`'s seed `ghcr_login` block (boot-path variant of the identical class). **Phase 2:** install Vector on web-2 (fail-open, sequenced after `:9000` bind) so its journald ships to Better Stack ("ships logs" criterion + second no-SSH channel).

**Excluded:** Branch C/C′ (network/DNS) — a 401 in 5 s with a live-valid credential is application-auth, not L3 (per the plan's ordering discipline, the Sentry stage/detail is decisive and points at auth, so the L3 checklist is not run). Branch D/E (stale image / arch) — the tag exists and pulls 200 with valid creds. Branch F — events were present (query the issues surface, not the tag-unindexed events endpoint). The operator's "cloud-init image-pull failed" was the hypothesis; telemetry overrides it — the boot's pull succeeded; the *deploy* pull failed on stale-baked-cred auth.
