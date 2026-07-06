---
title: "fix(infra): extend baked-DSN Sentry observability across the full web-2 fresh-boot sequence"
tracker: "#6090"
related: ["#6076", "#6023", "#6060", "#6082", "#6005", "ADR-068", "ADR-080", "ADR-087"]
lane: single-domain   # web-platform infra only; no spec.md on branch (default rationale in Domain Review)
brand_survival_threshold: none
type: infra-observability
created: 2026-07-06
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- The systemctl / cloudflared / apt-get references in this plan quote EXISTING
     cloud-init.yml runcmd lines (already routed through Terraform templatefile +
     the baked bootstrap script). This plan introduces NO new manual provisioning:
     it only adds Sentry breadcrumb/trap text around those existing steps. Phase 2.8
     reviewed; see the ## Infrastructure (IaC) section. -->

# fix(infra): extend baked-DSN Sentry observability across the full web-2 fresh-boot sequence

🐛 **Tracker:** #6090 — *web-2 fresh boot dies silently after the seed-extract (before `:9000`) — extend baked-DSN observability + check #6023 cosign ENFORCE*

## Enhancement Summary

**Deepened on:** 2026-07-06 · **Reviewers:** architecture-strategist, observability-coverage-reviewer, spec-flow-analyzer, code-simplicity-reviewer (4 parallel) + learnings-researcher.

### Key improvements folded in (all P0/P1 caught before implementation)
1. **Readiness gates are load-bearing, not optional (spec-flow P0 F1 / architecture P1 Q2).** cloudflared + webhook are systemd services: their cloud-init service-enable step (cloud-init.yml:441, 453) returns 0 the instant the unit *launches*; the service can then fail to bind `:9000` **asynchronously, in a context with no trap and no emit**. Breadcrumbs/traps on the *enable command* are a no-op for the exact H1 symptom → the recreate returns all-green-and-still-broken, burning the one operator-gated cycle. Fix: bounded-timeout **readiness assertions** (service-active query + `:9000` bind check) that convert the async death into an emitted fatal. This also covers the "hang, no non-zero exit" hypothesis (H4/F3).
2. **The auto Sentry-read queries the WRONG data plane (spec-flow P0 F2 / architecture P1 Q3).** `apply-web-platform-infra.yml:1212` hits US `https://sentry.io/...`, but the project is EU-resident (`de.sentry.io`/`jikigai-eu`). Phase 3 must fix the endpoint **host**, not just the query string — otherwise the headline "one recreate auto-names the stage" deliverable returns empty.
3. **A new root-cause hypothesis (H3, architecture P1 Q2).** cloud-init may concatenate runcmd into one `/bin/sh`; a `set -e` leaked from the extraction block (line 354) could be aborting the bare cloudflared `apt-get` (437) with no active trap — a silent pre-`:9000` death matching the exact symptom. Phase 0 now empirically pins errexit scoping before any code (it may be the fix itself).
4. **Do NOT consolidate bare tolerant commands into `set -e` blocks (architecture P1 Q2 / simplicity).** Folding the cloudflared `apt`/webhook lines into a `set -e` + `exit 1` block *inverts* an implicitly-tolerated transient failure from survivable→fatal AND skips the terminal poweroff gate. Instrument via lightweight breadcrumbs as separate runcmd items + readiness gates; leave existing commands' exit disposition unchanged.
5. **One shared emit helper, written once — never per-block duplication (architecture P1 Q1).** Each cloud-init `- |` is an independent `/bin/sh`; duplicating the ~23-line `on_err` across ~4 blocks ≈ 3.6 KB blows the cap (baseline ~29.6 KB / ~3 KB headroom, `server.tf:56`). Default: an inline-written `soleur-boot-emit` helper (interpolating `${sentry_dsn}` once); bake it only if Phase 0 measures over the cap.
6. **Merge into existing cleanup traps, don't clobber them (architecture P1 Q5).** `plugin_seed`/`inngest` already own `trap cleanup EXIT`; add the emit as a composite `trap 'rc=$?; cleanup; [ $rc = 0 ] || emit …' EXIT`, never a second trap.
7. **Simplification (simplicity):** drop the 6 per-stage bootstrap breadcrumbs (existing `emit_fail` already tags `{stage}`) — keep only `bootstrap_complete`; drop the `_breadcrumb` wrapper (single caller); commit to the shared-helper shape instead of carrying Option A/B as co-equal.
8. **Coupling is already enforced (architecture P2 Q3):** `apps/web-platform/infra/scripts/web2-recreate-preflight.sh` fail-closes a stale-image recreate (hash mismatch → abort, no `-replace`). Cite it; relax the "operator must sequence" framing.

### New considerations discovered
- Message-string lockstep must be tested by **cross-file byte-equality** of the real emit literal vs the workflow query (not a synthetic event) — else a wording drift silently re-opens the blind spot (obs P1 #4 / spec-flow F6).
- FLOW 2 needs a **boot-succeeded branch**: surface the breadcrumb trail `if: always()` and add an AC to close #6090 when `:9000` binds (spec-flow F4).
- app-image pull (480), volume-mount (417-431), and the systemd-timer region (455-477) were uninstrumented gaps inside the claimed "whole-region" coverage (obs P1 #1/#2, P2 #5).

## Overview

web-2 has never completed a fresh boot. After a `web-2-recreate` (`terraform apply -replace='hcloud_server.web["web-2"]'`) the apply succeeds, but cloud-init dies **silently** before the deploy-status webhook (`:9000`, fronted by cloudflared) binds, so every deploy fan-out to web-2 reports `ok_peer_fanout_degraded`. Prod is unaffected — web-1 is the sole live origin at 200; web-2 is weight-0, non-serving.

The #6076 seed-pull fix (baked `${sentry_dsn}` in cloud-init's `on_err`) is confirmed working — Sentry shows no `stage=pull` fatal. The remaining failure is **after the seed-extract**, and it is invisible off-host because the code past the seed block either sources its Sentry DSN from `doppler secrets get` (a boot-stage that may itself be broken) **or has no Sentry emit at all**.

**This PR is a structured off-host observability probe, not the fix for the boot failure itself.** It makes the *last-reached fresh-boot stage* visible in Sentry so the named failing stage can be read after a single recreate — then a follow-up PR fixes that named stage. Per learnings `2026-07-01-blind-surface-needs-structured-probe-before-nth-fix.md` and `2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface.md`, shipping the discriminating-field probe **before** the next fix attempt is the load-bearing deliverable for a blind (no-SSH) surface.

Two work items from the tracker:

- **(B) cosign ENFORCE angle — resolved by code-read, NO code change.** #6023 (WARN→ENFORCE flip) is an **OPEN, unmerged issue**; the code default is still `IMAGE_VERIFY_MODE:-warn` (`ci-deploy.sh:54`) and nothing in the repo sets `enforce`. Moreover cosign verify runs **only** in `ci-deploy.sh` (the webhook deploy path), **never** in the fresh-boot cloud-init sequence. A fresh host *does* have the trusted root (`soleur-host-bootstrap.sh:81` installs `/etc/soleur/cosign-trusted-root.json` before the sentinel), so even after #6023 merges the deploy path is satisfied. **Conclusion: cosign ENFORCE is not on the fresh-boot critical path and is not the cause.** (Detail in Research Reconciliation.)
- **(A) Extend the baked-DSN observability into the post-seed fresh-boot sequence** — the real deliverable. Corrected scope below.

**Scope correction (load-bearing).** The tracker frames (A) as "in `soleur-host-bootstrap.sh` (install → webhook-enable)". But `soleur-host-bootstrap.sh` **ends at the `/run/soleur-hostscripts.ok` sentinel** (line 199) after `install → hooks → assert → reload → journald → ghcr_login`. The cloudflared install (`cloud-init.yml:433-441`), webhook binary install + service enable (`cloud-init.yml:444-453`), plugin-seed, inngest-bootstrap, and the terminal app `docker run` all run in **downstream cloud-init runcmd blocks that carry no Sentry trap at all**. "8/8 probes hit web-1, cloudflared never comes up, `:9000` never binds" points at that downstream region — which is *past* where `soleur-host-bootstrap.sh` finishes. Instrumenting only `soleur-host-bootstrap.sh` would, in the worst case, cost a full recreate cycle to learn "bootstrap completed; death is downstream," then need a second PR + image rebuild + recreate to instrument the downstream region. This plan therefore instruments the **whole post-seed sequence** in one PR so a single recreate names the exact stage regardless of region.

## Research Reconciliation — Spec vs. Codebase

| Tracker/issue claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "#6023 flipped cosign image-verify WARN→ENFORCE" | #6023 is **OPEN/unmerged** (`gh issue view 6023` → state OPEN, "WARN→ENFORCE flip ... follow-up to #6005"). `ci-deploy.sh:54` still `IMAGE_VERIFY_MODE:-warn`; repo-wide grep finds **no** site setting `enforce`. | (B) requires **no code change**; document that cosign ENFORCE is not live and not on the boot path. |
| "cosign hard-fails the fresh host at boot" | cosign verify lives **only** in `ci-deploy.sh` (`cosign_verify_image`, lines ~585-630, called at ~1033 on the deploy-webhook path). The fresh-boot cloud-init sequence has **no cosign call** — it `docker pull ${image_name}` (line 480) + `docker run` (line 580) directly. Trusted root *is* present on a fresh host (`soleur-host-bootstrap.sh:81`). | Confirm B is a dead end; proceed to (A). |
| "(A) is in `soleur-host-bootstrap.sh` (install → webhook-enable)" | `soleur-host-bootstrap.sh` ends at the sentinel (line 199); its stages are `install/hooks/assert/reload/journald/ghcr_login`. **webhook service-enable is `cloud-init.yml:453`, downstream of bootstrap.** | Instrument `soleur-host-bootstrap.sh` **and** the downstream cloud-init region (cloudflared → webhook → app-run). |
| "silent because `emit_fail`/`ghcr_login_warn` source DSN from doppler" | True for `soleur-host-bootstrap.sh` (lines 38-40, 169-170). **But** the downstream cloud-init blocks (cloudflared/webhook/plugin-seed/app-run) have **no emit at all** — the deeper blind spot. Doppler demonstrably works at boot (the seed `ghcr_login` at `cloud-init.yml:390` succeeded → seed pulled), so a *silent* death most likely means bootstrap **completed** and death is in the untrapped downstream region. | Fix bootstrap DSN preference (belt-and-suspenders) **and** add a baked-`${sentry_dsn}` trap + breadcrumbs to the downstream region (the load-bearing part). |
| ":9000 binds = warm standby" | `:9000` is the adnanh/webhook deploy-status listener fronted by cloudflared; the app container binds `:80`/`:3000` (`cloud-init.yml:590-591`). Both cloudflared (441) and webhook (453) come up downstream of bootstrap. | Breadcrumb stages cover `cloudflared_*` and `webhook_*`. |
| "read the named failing stage from Sentry" (manual) | The recreate workflow **already** auto-reads Sentry on failure (`apply-web-platform-infra.yml:1184-1217`), but its query (`1207`) matches only the two existing fatal messages. | Extend that query to include the new downstream fatal + last-breadcrumb, so the recreate run summary auto-names the stage. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing new — web-2 is weight-0, non-serving; web-1 remains the sole live origin at 200. The worst realistic regression is a *self-inflicted* one: an emit/breadcrumb call that is not fail-open could abort the fresh boot (no sentinel → `poweroff -f`). But web-2 already fails to boot today, so there is no serving-path regression to any user, and the change never touches web-1 (see below).

**If this leaks, the user's data is exposed via:** n/a — the only egress added is a Sentry event carrying `stage`/`failed_file`/`host_id`/`region` (a Hetzner instance-id and a stage enum — no secrets, no PII). The DSN is the already-semi-public `${sentry_dsn}` (already in the client bundle; `variables.tf:206`). Emit bodies are classifications, never raw stderr/creds (mirrors the existing `ghcr_login_warn` scrubbing).

**Brand-survival threshold:** none.
- `threshold: none, reason:` web-2 is a weight-0 non-serving standby; this change is best-effort observability only (every emit is `|| true`/`set +e`-guarded and MUST NOT poweroff the host), it never touches web-1 (cloud-init only exercises on the operator-gated web-2 recreate; web-1's running host is patched via the web-1-scoped `terraform_data` SSH provisioners, not cloud-init — `server.tf:98`), and it changes no serving behavior. (Required because the diff touches the sensitive `apps/web-platform/infra/` path.)

## Hypotheses

This is a fresh-boot connectivity symptom ("cloudflared never comes up", "`:9000` never binds"), so the L3→L7 discipline (`hr-ssh-diagnosis-verify-firewall`) is noted — but it **does not fire a firewall/sshd hypothesis** here:

- **No SSH hypothesis exists.** web-2 has **no** SSH path by design: `hcloud_server.web`'s `file`/`remote-exec` provisioners are web-1-scoped (`server.tf:98`), and diagnosis is off-host by rule (`hr-no-ssh-fallback-in-runbooks`). There is no sshd/fail2ban fix to propose, so the firewall-before-sshd ordering is inapplicable.
- **Primary hypothesis (H1):** `soleur-host-bootstrap.sh` **completes** (writes the sentinel) and the death is in the untrapped downstream cloud-init region — most likely the cloudflared install (`cloud-init.yml:433-441`) or the webhook service-enable (453). Supported by: doppler works at boot (seed `ghcr_login` succeeded), yet Sentry is *silent* → the failing region has no emit → it is downstream of bootstrap (which *does* emit via `emit_fail`).
- **Secondary hypothesis (H2):** `soleur-host-bootstrap.sh` fails at a late stage but its `emit_fail` DSN fetch (doppler) is unavailable at that instant → silent. Lower-probability (doppler worked moments earlier) but cheaply covered by the baked-DSN preference.
- **H3 (candidate ROOT CAUSE — architecture P1 Q2):** cloud-init concatenates runcmd entries; a `set -e` leaked from the extraction block (`cloud-init.yml:354`) could abort the bare cloudflared `apt-get` at 437 **with no active trap** (the extraction block disarms its own trap at 411) — a silent pre-`:9000` death matching the exact symptom. If Phase 0.4 confirms errexit leaks across runcmd items, this may be the fix itself (scope the `set -e`), independent of the observability work. **Falsify before assuming H1.**
- **H4 (async systemd-service death — spec-flow P0 F1):** the bootstrap AND the cloudflared/webhook enable commands all return 0; the service then fails to connect the tunnel / bind `:9000` **asynchronously**, in a systemd context no runcmd trap can see. This is the literal reading of "cloudflared never comes up." A command-level breadcrumb/trap is a **no-op** here — every stage reads green while `:9000` stays dead. **Only an active readiness assertion (bounded-timeout service-active + bind check) makes this observable** (Phase 2.4). This subsumes the "hang, no non-zero exit" case (Phase 4 F3): a bounded poll converts both a hang and an async failure into an emitted fatal.
- **This PR does not choose between H1-H4** — it makes all four observable in one recreate. H3 is checked first (cheap, code-read/dry-run) since it may resolve the boot without instrumentation; the readiness gates (H4) are the load-bearing detector for the async-service class. Per `2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface.md`, the probe must assert the invariant (`:9000` bound), not a proxy (stage reached).

### Network-Outage Deep-Dive (deepen-plan Phase 4.5)

Fired by the resource-shape trigger (the plan drives `terraform apply -replace` and `hcloud_server.web`'s file carries `provisioner "file"`/`remote-exec` blocks) **and** the "SSH" keyword in the Hypotheses. Layer status:

- **L3 firewall allow-list:** Not on the web-2 recreate path. The `file`/`remote-exec` provisioners at `server.tf:191-234` sit on a **`terraform_data` SSH bridge keyed to the existing web-1 host** (`server.tf:98` — "the 11 SSH provisioners below stay web-1-scoped"); `hcloud_server.web["web-2"]` itself is **cloud-init-only** (no provisioner), so `-replace='hcloud_server.web["web-2"]'` triggers no SSH handshake and no operator-egress-IP dependency. Verification artifact: the recreate workflow (`apply-web-platform-infra.yml`) reaches web-2 purely via the CF-proxied fan-out/deploy-status probe, not SSH.
- **L3 DNS/routing:** the deploy-status probe resolves `deploy.soleur.ai` (CF edge) — unchanged by this PR.
- **L7 TLS/proxy:** cloudflared tunnel fronting `:9000` — this is the *suspected failure surface* (H1), which is exactly what the new breadcrumbs make observable; no TLS/proxy config change is proposed here.
- **L7 application:** the webhook/deploy-status handler — downstream of the instrumented region.

No firewall/sshd/fail2ban fix is proposed (there is no SSH hypothesis for web-2), so the L3-before-L7 ordering is satisfied vacuously. Telemetry emitted (`hr-ssh-diagnosis-verify-firewall applied`).

## Implementation Phases

### Phase 0 — Preconditions (no host writes)

0.1 **(B) cosign confirmation (code-read only).** Re-assert in the PR body: #6023 unmerged; `IMAGE_VERIFY_MODE` default `warn`; no `enforce` setter in repo; cosign verify absent from cloud-init; trusted root installed pre-sentinel (`soleur-host-bootstrap.sh:81`). No code change. (Covers tracker item B.)

0.2 **user_data byte-budget gate (hard).** Rendered cloud-init user_data baseline is ~29.6 KB against Hetzner's 32,768-byte cap → ~3 KB headroom (`server.tf:56`; learning `2026-07-03-cloud-init-32kb-cap-bake-and-extract-not-compress.md`). Measure the delta the Phase 2 additions introduce:
  - Render via `templatefile("cloud-init.yml", {...})` with placeholder vars and `wc -c` (or `terraform console` under `doppler run … --name-transformer tf-var`).
  - **Shape decision (architecture P1 Q1 — do NOT duplicate the ~23-line `on_err` per block; that ≈3.6 KB blows the cap):** default to a **single shared `soleur-boot-emit` helper written once** in an early cloud-init `- |` block (`cat > /usr/local/bin/soleur-boot-emit <<'EOF' … EOF`, interpolating `${sentry_dsn}` once); each downstream block then pays only a one-line call. If the measured render still exceeds 32,768, fall back to **baking** `soleur-boot-emit` into the host-scripts set (zero user_data, but adds `host_scripts_content_hash` + Dockerfile COPY lockstep). Record measured before/after bytes + the chosen shape in the PR body.

0.3 Confirm `${sentry_dsn}` is already wired into the cloud-init `templatefile` call (`server.tf:138`) — it is; no Terraform variable plumbing needed for the cloud-init side.

0.4 **Empirically pin cloud-init errexit scoping (H3 — architecture P1 Q2, may be the fix itself).** Determine whether a `set -e` inside one runcmd entry leaks to subsequent entries: render `/var/lib/cloud/instance/scripts/runcmd` (cloud-init `--file cloud-init.yml single --name runcmd`, or a `cloud-init devel schema`/local dry-run), and inspect how the extraction block's `set -e` (line 354) interacts with the bare cloudflared `apt-get` (437). **If errexit leaks and no trap is active there, that is a candidate root cause** — a transient/non-zero at 437 aborts the boot silently. If confirmed, scope the leak (subshell the extraction block, or re-assert disposition) as part of THIS PR and note it prominently; the observability work still lands (it proves the fix). Pin the finding (leaks / does-not-leak) in the PR body.

0.5 Confirm the enforcing coupling gate: read `apps/web-platform/infra/scripts/web2-recreate-preflight.sh` — it recomputes the baked-scripts hash from the pinned `@sha256` image and **aborts (no `-replace`) on mismatch**, so a stale-image recreate cannot boot a hash mismatch. Cite it in the IaC section (relaxes the AC11/AC12 "operator must sequence" framing to "preflight fail-closes").

### Phase 1 — `soleur-host-bootstrap.sh`: prefer baked DSN + completion breadcrumb

*(Failing test first per `cq-write-failing-tests-before` — see Phase 4.)*

1.1 **Accept the baked DSN via env + single emit helper.** Resolve one `DSN` preferring `SOLEUR_SENTRY_DSN` (passed by cloud-init, Phase 2.1) then the existing doppler fetch. Factor DSN-resolve + Sentry-POST into one `_sentry_emit <level> <json-tags>` used by `emit_fail` (lines 34-52) and `ghcr_login_warn` (168-180). The `${SOLEUR_SENTRY_DSN:-<doppler fetch>}` preference lives in exactly one place.
1.2 **Completion breadcrumb only** (simplicity rec 2 — drop the 6 per-stage breadcrumbs; `emit_fail` already tags `{stage, failed_file}` on any bootstrap-stage failure, so per-stage info breadcrumbs are redundant). Emit ONE `stage:"bootstrap_complete"`, `region:"bootstrap"` breadcrumb **immediately before** `: > /run/soleur-hostscripts.ok` (line 199). This answers H1's only open question — "did bootstrap complete?" — and is what distinguishes H1 (died downstream) from H2 (died in bootstrap). Inline it as one guarded `_sentry_emit info …` call (no separate `_breadcrumb` wrapper — single caller).
1.3 **Fail-open invariant (load-bearing).** The `bootstrap_complete` call and any emit under `set -e` MUST be inside a `( set +e; … ) || true` subshell (mirror the existing `ghcr_login` subshell at line 159) so a curl/DNS hiccup can never trip `set -e` and brick the boot. `emit_fail` continues to `trap - EXIT` first.
1.4 Keep the emit body a **classification/enum only** (no raw stderr, no creds).

### Phase 2 — cloud-init post-bootstrap region: breadcrumbs + readiness gates

2.1 **Pass the baked DSN into bootstrap** (`cloud-init.yml:412`): add `SOLEUR_SENTRY_DSN='${sentry_dsn}'` to the bootstrap invocation env (item A).

2.2 **Shared emit helper, written once** (Phase 0.2 shape). Define `soleur-boot-emit <stage> <level>` once (inline-written or baked) — POSTs `{message, level, tags:{stage, host_id, region:"cloud-init"}}` to Sentry via the baked `${sentry_dsn}` (mirrors `emit_fail`'s DSN parse). All calls `|| true`. **No per-block `on_err` duplication.**

2.3 **Entry breadcrumbs WITHOUT changing exit disposition** (architecture P1 Q2 / simplicity). Insert a breadcrumb as a *separate* runcmd list-item before each region, and for bare currently-tolerated commands use `cmd || soleur-boot-emit <stage> warning` (continuation preserved) — **do NOT** wrap the existing bare `apt`/mount lines in `set -e`+`exit 1` (that inverts survivable→fatal and skips the terminal poweroff gate). Stages, closing the coverage gaps: `volume_mount` (417-431, obs P1 #1), `cloudflared` (433-441), `webhook` (444-453), `host_timers` (455-477, obs P2 #5), `app_image_pull` (480 — its OWN stage, NOT folded into `plugin_seed`, obs P1 #2), `plugin_seed` (492), `inngest_bootstrap` (523).

2.4 **Readiness gates (NEW — the load-bearing death-detector for H4/F3).** After the cloudflared enable step and after the webhook enable step, add a bounded-timeout `- |` block that actively asserts the service is up:
  - `cloudflared_ready`: poll `systemctl is-active --quiet cloudflared` (a read, not a state-change) up to N×interval; on timeout `soleur-boot-emit cloudflared_ready fatal` then `exit 1`.
  - `webhook_bound`: poll a `:9000` bind check (`curl -sf -o /dev/null http://localhost:9000/` or `ss -ltn 'sport = :9000' | grep -q :9000`) up to N×interval; on timeout `soleur-boot-emit webhook_bound fatal` then `exit 1`; success emits a `webhook_bound` info breadcrumb.
  These NEW blocks are legitimately `set -e`+`exit 1` (they add no tolerance inversion — a service that never binds SHOULD fail the boot), and they convert the async-service death (green enable, dead `:9000`) into a named emitted fatal. This is the single change that makes the one-recreate promise real.

2.5 **Composite trap merge, never a second trap** (architecture P1 Q5). `plugin_seed` (496 `trap cleanup EXIT` … 501) and `inngest` (528) already own an EXIT trap. Add the emit by **rewriting** their trap to `trap 'rc=$?; cleanup; [ "$rc" = 0 ] || soleur-boot-emit <stage> fatal' EXIT` — never `trap on_err EXIT` (which silently replaces `cleanup` and orphans the container). Strip any seed-specific `docker rm`/`image_ref` from the copied shape.

2.6 **app_run sub-stages + terminal breadcrumb** (obs P1 #3, spec-flow F8). In the terminal block (555-600): distinguish `doppler_download` (568) from `docker_run` (580) as sub-stages; emit a terminal `cloud_init_complete` breadcrumb **after** the egress probe (597) so "last-reached = app_run" is not the ceiling when the truth is a post-app-run hang. Document that the two `poweroff -f` paths (563, 599) race/kill a curl emit and therefore rely on **mode-3 Better Stack absence**, not the emit (do not claim trap coverage there).

2.7 **Discriminating fields (2.9.2):** every fatal/breadcrumb carries `{stage, host_id, region ∈ {bootstrap, cloud-init}}` so **one** event names the exact stage+region — no host-side inference.

### Phase 3 — recreate workflow: surface the named stage (correct data plane)

3.1 **Fix the Sentry endpoint host (spec-flow P0 F2 / architecture P1 Q3 — load-bearing).** `apply-web-platform-infra.yml:1212` queries US `https://sentry.io/...`; the project is EU-resident (`de.sentry.io`/`jikigai-eu`, per the DSN residency + AC14). An EU project queried at the US host returns empty → the auto-surface deliverable is dark. Point the workflow curl at the EU host (derive the region from the DSN/secret rather than hard-coding a literal), and add a test asserting the workflow endpoint host matches the emit DSN's residency segment.
3.2 **Extend the query string** (1207) to also match the new downstream fatal + the `bootstrap_complete`/`webhook_bound` breadcrumb messages — specify the exact canonical `message` literals (Phase 1/2) and keep them in lockstep. Sort most-recent so the summary shows the *last-reached* stage.
3.3 **Surface the breadcrumb trail `if: always()`, not only `if: failure()`** (spec-flow F4). On a *green* boot the operator must still see the probe fired (and that `:9000` bound), or "verify passed for unrelated reasons" is indistinguishable from "probe worked + boot fixed." Add an always-run summary line reading the breadcrumb trail.
3.4 Verify the `fresh-host Sentry pointer` literal actually lands in `gh run view --log` (it is written to `$GITHUB_STEP_SUMMARY`, 1198); if not, point the `discoverability_test` at the summary artifact instead (obs P2 #6).

### Phase 4 — Tests (write first; `cq-write-failing-tests-before`)

New `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` (source-grep + behavioral where a POSIX-sh shape can be exercised), wired into `.github/workflows/infra-validation.yml` (mirror line 160). Assertions:
- **AC2:** `cloud-init.yml:412` passes `SOLEUR_SENTRY_DSN='${sentry_dsn}'`.
- **AC3:** `emit_fail` + `ghcr_login_warn` resolve DSN preferring `SOLEUR_SENTRY_DSN` before doppler.
- **AC4:** `bootstrap_complete` breadcrumb precedes the sentinel (line-order grep).
- **AC5 (fixed shape):** every emit call sits inside a `( set +e … ) || true` subshell — assert the **structural enclosure**, NOT a per-line `|| true` (the subshell form has no per-line `|| true`; a per-line grep false-positives on every correct call — spec-flow F5).
- **AC6 (readiness gates):** `cloudflared_ready` + `webhook_bound` blocks exist, poll with a bounded timeout, emit a fatal on timeout, and the `webhook_bound` check targets `:9000`.
- **AC-parity:** bare tolerant commands (mount, cloudflared apt) retain continuation (no new `set -e`+`exit 1` around them); `plugin_seed`/`inngest` use a composite trap that still calls `cleanup`.
- **AC8 (lockstep, byte-equality):** extract the literal `"message":"…"` from each emit site and assert byte-equality against the substring in the workflow QUERY — not a synthetic event (spec-flow F6 / obs P1 #4).
- **AC-EU:** the workflow Sentry endpoint host matches the DSN residency segment (spec-flow F2).

## Files to Edit

- `apps/web-platform/infra/soleur-host-bootstrap.sh` — DSN-prefer env via one `_sentry_emit` helper, single `bootstrap_complete` breadcrumb before the sentinel, fail-open subshell guards. *(Baked → part of `local.host_scripts_content_hash`; needs an image rebuild.)*
- `apps/web-platform/infra/cloud-init.yml` — line 412 `SOLEUR_SENTRY_DSN` pass; shared `soleur-boot-emit` helper written once (inline default); entry breadcrumbs (no exit-disposition change on bare commands); **readiness-gate blocks** for `cloudflared_ready`/`webhook_bound`; composite-trap merge on plugin-seed/inngest; terminal `cloud_init_complete` breadcrumb; H3 errexit scope-fix if Phase 0.4 confirms the leak.
- `.github/workflows/apply-web-platform-infra.yml` — **fix the Sentry endpoint host to the EU data plane** (1212), extend the query (1207) to the new stage literals, surface the breadcrumb trail `if: always()`.
- `.github/workflows/infra-validation.yml` — run the new observability test.
- *(baked-helper fallback only, if Phase 0.2 measures over-cap)* `apps/web-platform/infra/server.tf` `local.host_scripts_content_hash` list + the Dockerfile COPY set — add `soleur-boot-emit` in lockstep (`server.tf:12` "KEEP THIS LIST IN LOCKSTEP").

## Files to Create

- `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` — the Phase 4 gate.
- *(baked-helper fallback only)* `apps/web-platform/infra/soleur-boot-emit` — POSIX emit helper (only if not inline-written).

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` — no open scope-out names `cloud-init.yml`, `soleur-host-bootstrap.sh`, or `apply-web-platform-infra.yml`. Re-run the standalone-`jq --arg` check at Step 1.7.5 against the final file list before freezing.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (B):** PR body documents #6023 unmerged, `IMAGE_VERIFY_MODE` default `warn` with no `enforce` setter, cosign verify absent from the fresh-boot path — no code change for B. `grep -rn 'IMAGE_VERIFY_MODE' apps/web-platform/infra .github` shows only the `:-warn` default + comparisons.
- [ ] **AC1b (H3):** Phase 0.4 errexit-scoping finding pinned in PR body (leaks / does-not-leak); if it leaks, the scope-fix is included and named.
- [ ] **AC2:** `grep -n "SOLEUR_SENTRY_DSN='\${sentry_dsn}'" apps/web-platform/infra/cloud-init.yml` matches the bootstrap invocation line.
- [ ] **AC3:** `emit_fail` and `ghcr_login_warn` resolve DSN preferring `SOLEUR_SENTRY_DSN` before any `doppler secrets get` (test asserts the `${SOLEUR_SENTRY_DSN:-...}` shape at both sites, via the shared `_sentry_emit`).
- [ ] **AC4:** a single `bootstrap_complete` breadcrumb appears **before** `/run/soleur-hostscripts.ok` (line-order grep).
- [ ] **AC5 (fail-open — structural enclosure, spec-flow F5):** every emit call sits inside a `( set +e … ) || true` subshell. Test asserts the **enclosure** (the emit line is bracketed by `( set +e` … `) || true`), NOT a per-line `|| true` — the subshell form deliberately has no per-line `|| true`, so a per-line grep would false-positive on every correct call.
- [ ] **AC6 (readiness gates, load-bearing):** `cloudflared_ready` and `webhook_bound` blocks exist, poll with a **bounded timeout**, `soleur-boot-emit <stage> fatal` + `exit 1` on timeout, and `webhook_bound` polls a real `:9000` bind check.
- [ ] **AC6b (no tolerance inversion):** bare currently-tolerated commands (mount 418, cloudflared apt 435-437) retain continuation — the test asserts they are NOT wrapped in a new `set -e`+`exit 1`; `plugin_seed`/`inngest` use a **composite** trap that still calls `cleanup`.
- [ ] **AC7 (cap):** rendered user_data byte count recorded in PR body and **< 32,768**; the shared `soleur-boot-emit` is written **once** (no per-block `on_err` duplication). If the baked fallback was used, `local.host_scripts_content_hash` + Dockerfile COPY include it (lockstep grep).
- [ ] **AC8 (lockstep, byte-equality — spec-flow F6):** the test extracts the literal `"message":"…"` from each emit site (`soleur-host-bootstrap.sh`, `cloud-init.yml`) and asserts byte-equality against the corresponding substring in `apply-web-platform-infra.yml`'s QUERY — a synthetic-event match is NOT sufficient.
- [ ] **AC8b (EU data plane — spec-flow F2, load-bearing):** the workflow Sentry endpoint host matches the DSN residency segment (EU `de.sentry.io`); a test asserts host↔DSN residency parity. The `if: always()` breadcrumb-trail surface is present.
- [ ] **AC9:** new test wired into `infra-validation.yml`; all existing `apps/web-platform/infra/*.test.sh` still pass. (No `tsc` — this diff touches only shell/yaml/workflow, no TS.)
- [ ] **AC10:** PR uses `Ref #6090` (NOT `Closes`) — the boot failure is not fixed by this PR; #6090 stays open until `:9000` binds (ops-remediation-class per Sharp Edge).

### Post-merge (operator + verification)

- [ ] **AC11 [automatable] Image rebuild landed:** after merge, `web-platform-release.yml` rebuilds `${image_name}` with the new baked `soleur-host-bootstrap.sh` (and the baked helper if that fallback was used). **`web2-recreate-preflight.sh` fail-closes a stale-image recreate** (hash mismatch → abort, no `-replace`), so this is a "don't waste a run" check, not a safety gate — confirm the new digest is published before dispatch.
- [ ] **AC12 [automatable] Quiet-window precondition:** `gh run list --workflow web-platform-release.yml --status in_progress` returns **0** AND web-1 deploy-status `exit_code=0` (HMAC deploy-status probe) AND `app.soleur.ai/health` = 200. Script as a single go/no-go before dispatch. (Weaker than the preflight hash gate by design — the preflight is the real guard.)
- [ ] **AC13 [operator-ack — menu-ack dispatch] Recreate web-2:** `gh workflow run apply-web-platform-infra.yml -f apply_target=web-2-recreate -f reason='#6090 read named fresh-boot stage'`. `Automation: not feasible because` this is a prod-affecting dispatch gated by `hr-menu-option-ack-not-prod-write-auth` (operator ack required); the pre/post checks (AC12, AC14) are automated around it. NEVER `-replace` web-1.
- [ ] **AC14 [automated in-workflow + manual fallback] Read the named stage:** the recreate run's failure step (Phase 3) surfaces the last-reached `stage` in `$GITHUB_STEP_SUMMARY`. Manual fallback (EU region, `de.sentry.io`): `curl -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://de.sentry.io/api/0/projects/jikigai-eu/web-platform/issues/?query=host-bootstrap&statsPeriod=24h"` (secrets from `doppler … -p soleur -c prd_terraform --plain` via command substitution — never echo).
- [ ] **AC15 [verification]:** the recreate produced a Sentry event whose `stage`/`region` names where the boot died (or `bootstrap_complete` + a downstream `stage`/`webhook_bound` fatal). This proves the probe fires on the affected surface (`2026-06-30-...`).
- [ ] **AC16 [branch on outcome — spec-flow F4]:**
  - **If web-2 died again:** file/annotate the follow-up fix issue against the **named** stage; keep #6090 open.
  - **If web-2 booted green** (`:9000` binds, fan-out reports `ok` not `ok_peer_fanout_degraded`, and the `if: always()` breadcrumb trail confirms the probe fired): the boot is fixed — **close #6090**, no follow-up. (Without the always-run breadcrumb surface, "verify passed" is indistinguishable from "probe never emitted"; AC8b makes the green branch trustworthy.)

## Observability

```yaml
liveness_signal:
  what: "per-STAGE Sentry breadcrumbs across the full fresh-boot sequence (bootstrap.sh install->ghcr_login->bootstrap_complete, then cloud-init cloudflared->webhook->app_run) + the existing Better Stack per-host absence probe (web-2.app.soleur.ai/health)"
  cadence: "once per fresh boot (web-2-recreate)"
  alert_target: "Sentry (web-platform project, EU/de.sentry.io) + recreate-workflow GITHUB_STEP_SUMMARY"
  configured_in: "soleur-host-bootstrap.sh, cloud-init.yml, apply-web-platform-infra.yml:1184-1217"
error_reporting:
  destination: "Sentry via baked ${sentry_dsn} POST to /api/<proj>/store/ (no doppler dependency on the primary path)"
  fail_loud: "recreate workflow verify step exits non-zero on ok_peer_fanout_degraded; the named stage is added to the run summary. The emit itself is fail-OPEN (|| true) so it can never brick the boot -- loudness is the workflow verify + Better Stack absence page, not the emit."
failure_modes:
  - mode: "bootstrap.sh stage fails (install/hooks/assert/reload/journald/ghcr_login)"
    detection: "in-surface emit_fail Sentry event, tags {stage, failed_file, host_id, region:bootstrap}, DSN preferring baked env"
    alert_route: "Sentry + recreate summary"
  - mode: "boot dies with a non-zero exit downstream of bootstrap (volume_mount, app_image_pull, plugin_seed, inngest, doppler_download, docker_run)"
    detection: "in-surface soleur-boot-emit fatal, tags {stage, host_id, region:cloud-init}, baked ${sentry_dsn}; bootstrap_complete breadcrumb present => death is downstream"
    alert_route: "Sentry + recreate summary"
  - mode: "ASYNC systemd-service death: enable command returns 0 but cloudflared/webhook never binds :9000 (H4 -- the primary symptom) OR a stage hangs with no non-zero exit"
    detection: "in-surface readiness-gate fatal (cloudflared_ready / webhook_bound) after a bounded-timeout service-active + :9000 bind poll -- a command-level trap CANNOT see this; the readiness assertion is the only detector"
    alert_route: "Sentry + recreate summary"
  - mode: "leaked set -e aborts a bare downstream command with no active trap (H3 candidate root cause)"
    detection: "Phase 0.4 dry-run pins errexit scoping; if confirmed, the fix scopes the leak AND the new breadcrumbs name the aborting stage on the next recreate"
    alert_route: "Sentry (named stage) + recreate summary"
  - mode: "terminal poweroff -f path fires (sentinel-incomplete 563 / egress-probe 599) -- races/kills a curl emit"
    detection: "NOT the in-surface emit (poweroff wins the race); relies on Better Stack per-host absence probe (web-2.app.soleur.ai/health)"
    alert_route: "Better Stack page (#5933 Item 1)"
  - mode: "emit path itself unavailable (Sentry egress + doppler both down)"
    detection: "Better Stack per-host absence probe (web-2.app.soleur.ai/health) -- host visibly absent"
    alert_route: "Better Stack page (#5933 Item 1)"
logs:
  where: "on-host cloud-init-output.log (SSH-only, not relied on); journald (persistent post-bootstrap). Off-host truth = Sentry + Better Stack."
  retention: "Sentry project default; Better Stack default"
discoverability_test:
  command: "gh run view <recreate-run-id> --log | grep -i 'fresh-host Sentry pointer'   # OR the AC14 de.sentry.io curl (off-host, no host login)"
  expected_output: "a Sentry event naming the last-reached stage/region for the boot"
```

## Infrastructure (IaC)

### Terraform changes
- No new Terraform resources or variables. `var.sentry_dsn` already exists (`variables.tf:206`) and is already passed into the cloud-init `templatefile` (`server.tf:138`). Editing `soleur-host-bootstrap.sh` changes `local.host_scripts_content_hash` (`server.tf:77`) — this is expected and *required*: the boot integrity check (`cloud-init.yml:405`) compares the pulled image's baked scripts against the Terraform-computed hash, so the image rebuild and the hash move together. (Option B additionally adds `soleur-boot-emit` to the hash list + Dockerfile COPY, in lockstep.) All `systemctl`/`apt-get`/`cloudflared` references in this plan are EXISTING cloud-init runcmd lines already routed through `templatefile()` + the baked bootstrap script — this plan adds no new manual provisioning, only Sentry breadcrumb/trap text around them.

### Apply path
- **cloud-init + baked-image rebuild → operator-gated `-replace` recreate (blue-green for web-2).** `soleur-host-bootstrap.sh` is baked into `${image_name}`, so it cannot be hot-patched; the change is live only after `web-platform-release.yml` rebuilds the image (AC11). `apps/web-platform/infra/scripts/web2-recreate-preflight.sh` recomputes the baked-scripts hash from the pinned `@sha256` and **aborts before `-replace` on mismatch** — a stale-image recreate can never boot a mismatch. The instrumented boot is then exercised by a **web-2-only** `terraform apply -replace='hcloud_server.web["web-2"]'` (AC13), operator-ack-gated, fail-closed destroy-guard, in a quiet window (AC12).
- **Downtime & cutover (deepen Phase 4.55 — does not trigger a HALT):** web-2 is weight-0, non-serving, so the recreate takes **no serving surface offline**; web-1 (the sole serving host) pins `lifecycle.ignore_changes=[user_data]` (`ci-ssh-key.tf:8`), so this cloud-init edit forces no web-1 change on a routine apply. The recreate is effectively blue-green for web-2 (fresh host born, old web-2 already non-serving). **Expected blast-radius:** web-2 only; web-1 untouched; zero prod downtime (learning `2026-07-02-zero-downtime-first-moved-block-statemv-and-blue-green-cutover.md`).

### Distinctness / drift safeguards
- web-1 carries `lifecycle.ignore_changes=[user_data]` (`ci-ssh-key.tf:8`), so this cloud-init edit does not force a web-1 change on a routine infra apply. The recreate is `-target`/`-replace`-scoped to `web["web-2"]`. No `dev`/`prd` collapse risk (single prd infra root). The baked `${sentry_dsn}` is semi-public; no secret lands in state that isn't already there.

### Vendor-tier reality check
- n/a — no new vendor resource; Sentry ingestion is on the existing project/DSN.

## Architecture Decision (ADR/C4)

**No new ADR; no C4 edit.** This extends the established #6076 baked-`${sentry_dsn}` boot-observability pattern (itself under ADR-080 bake-and-extract / ADR-087 host trust) to the rest of the boot sequence — a mechanical coverage extension, not a new decision, reversal, tenancy/ownership move, or trust-boundary change.

**C4 completeness check (read `model.c4` + `views.c4` + `spec.c4`):**
- **External human actors:** none new (the operator reading Sentry is pre-existing/implicit).
- **External systems:** the only external sink is **Sentry**, and the host→Sentry emit **already exists** (the #6076 seed `on_err`, `emit_fail`, and `ghcr_login_warn` all POST to Sentry today). This PR increases coverage on that pre-existing edge; it introduces no new external-system edge. `betterstack`, `ghcr`, `hetzner` are already modeled (`model.c4:168,244,248,324`). Whether Sentry warrants its own `#external` C4 element is a **pre-existing modeling question** (the emit edge predates this PR) — out of scope here; note as an optional follow-up, not a blocker.
- **Containers / data stores:** none new.
- **Access relationships:** none changed.
→ "No C4 impact" is supported by the enumeration above (checked against all three `.c4` files).

## Domain Review

**Domains relevant:** Engineering/infra (self-covered by the plan body).

No Product/UX surface (no `components/**`, `app/**/page.tsx`, or UI files in Files to Edit/Create — the mechanical UI-surface override does not fire → Product = NONE). No legal/finance/marketing/sales/support/ops implications — this is an infra observability change on a non-serving standby host. No spec.md exists on the branch, so `lane` is set directly to `single-domain` (the change is confined to one app's infra + its CI validation); recorded here for the tasks.md carry-forward.

## Test Scenarios

1. **DSN preference:** with `SOLEUR_SENTRY_DSN` set, `emit_fail`/`ghcr_login_warn` (via `_sentry_emit`) use it and do **not** call `doppler secrets get` (behavioral, stub `doppler` on PATH that fails if invoked).
2. **DSN fallback:** with `SOLEUR_SENTRY_DSN` empty, both fall back to the doppler fetch (existing behavior preserved).
3. **Breadcrumb ordering:** `bootstrap_complete` precedes the sentinel write.
4. **Fail-open (enclosure):** a stubbed emit that exits non-zero does NOT abort the script (sentinel still written); test asserts the `( set +e … ) || true` enclosure shape — AC5.
5. **Readiness gate:** the `webhook_bound` block polls `:9000` with a bounded timeout and emits a `webhook_bound` fatal on timeout; `cloudflared_ready` polls service-active. AC6.
6. **No tolerance inversion:** bare mount/cloudflared-apt lines retain continuation (no new `set -e`+`exit 1`); plugin_seed/inngest traps still call `cleanup`. AC6b.
7. **Lockstep byte-equality:** the emit `"message":"…"` literal in `cloud-init.yml`/`soleur-host-bootstrap.sh` is byte-identical to the substring in the workflow QUERY. AC8.
8. **EU endpoint:** the workflow Sentry endpoint host matches the DSN residency segment. AC8b.
9. **Cap:** rendered user_data `< 32,768` bytes; helper written once (Phase 0.2 measurement in PR body). AC7.

## Sharp Edges

- **Breadcrumbs/traps on the enable command CANNOT see an async systemd-service death (the primary symptom).** cloudflared/webhook enable returns 0 the instant the unit launches; the service can fail to bind `:9000` later with no trap. Only the **readiness gates** (Phase 2.4, bounded-timeout service-active + `:9000` bind poll) name that death. Ship them, or the recreate returns green-and-broken (spec-flow P0 F1).
- **The auto Sentry-read must query the EU data plane.** `apply-web-platform-infra.yml:1212` queries US `sentry.io`; the project is EU-resident (`de.sentry.io`/`jikigai-eu`, learning `2026-05-15-sentry-dsn-cluster-substring-authoritative-residency.md`). Fix the endpoint HOST, not just the query string, or the deliverable returns empty (spec-flow P0 F2 / architecture P1 Q3).
- **Do NOT consolidate bare tolerant cloud-init commands into `set -e`+`exit 1` blocks.** That inverts an implicitly-tolerated transient `apt`/mount failure from survivable→fatal AND skips the terminal poweroff gate — a diagnosis PR must change *nothing* about failure disposition. Instrument via separate breadcrumb runcmd items + `cmd || soleur-boot-emit` continuation (architecture P1 Q2). The readiness gates are the ONLY new `set -e`+`exit 1` blocks, and they add no inversion (a service that never binds *should* fail the boot).
- **Do NOT add a second EXIT trap to plugin_seed/inngest — merge into their existing `cleanup` trap.** A shell has one EXIT trap; `trap on_err EXIT` silently replaces `cleanup` and orphans the container. Use `trap 'rc=$?; cleanup; [ "$rc" = 0 ] || soleur-boot-emit …' EXIT` (architecture P1 Q5).
- **One shared emit helper written once — never duplicate the ~23-line `on_err` per block.** ~4 copies ≈ 3.6 KB blows the cap (baseline ~29.6 KB, `server.tf:56`). Phase 0.2 measures; bake only if inline-written still overflows (architecture P1 Q1).
- **The emit must never brick the boot.** Every emit sits in a `( set +e … ) || true` subshell — and AC5 asserts the *enclosure*, not a per-line `|| true` (which would false-positive on the correct subshell form). `emit_fail` does `trap - EXIT` first (spec-flow F5).
- **Lockstep is byte-equality, not "the query contains a stage word."** Test the real emit literal against the workflow QUERY substring across all three files; a synthetic-event test passes while the real string has drifted (spec-flow F6 / obs P1 #4).
- **`set -e` may already leak across runcmd items (H3).** Phase 0.4 pins it; a leaked errexit killing the bare cloudflared `apt` at 437 with no active trap could be the actual root cause — check before assuming H1.
- **Hash coupling is enforced by `web2-recreate-preflight.sh` (fail-closed), not operator discipline.** A stale-image recreate aborts before `-replace`. Sequence is still merge → rebuild → recreate, but a mistake wastes a run, it doesn't boot a mismatch (architecture P2 Q3).
- **Early-exit in a downstream readiness gate bypasses the app-run `poweroff -f` gates (563/599).** Intended: no container starts → nothing to poweroff → host stays absent → Better Stack pages (architecture P2 Q4). Do not claim in-surface emit coverage for the poweroff paths (obs P1 #3).
- **This PR does not close #6090** (unless the recreate boots green per AC16). Use `Ref #6090`, not `Closes` (ops-remediation class).

## Alternatives Considered

| Alternative | Why not |
|---|---|
| Instrument only `soleur-host-bootstrap.sh` (tracker's literal scope) | Would likely burn a full recreate cycle to learn "bootstrap completed; death is downstream," then need a 2nd PR+rebuild+recreate. The downstream cloud-init region is the suspected death site (H1). Instrument both in one PR. |
| SSH in and read `cloud-init-output.log` | Forbidden (`hr-no-ssh-fallback-in-runbooks`); web-2 has no SSH path (web-1-scoped provisioners). The whole point is off-host observability. |
| Wait for #6023 to merge and test cosign ENFORCE | B is a confirmed dead end — cosign is not on the boot path. Would waste a recreate. |
| Ship a cosign-ENFORCE fix as part of B | No code change is warranted; ENFORCE isn't live and doesn't run at boot. |
| Fix the boot in this PR (guess the stage) | Guessing the layer without the probe is exactly the anti-pattern `2026-06-30-...` warns against. Probe first, then fix the named stage. |

**Deferrals (tracking):**
- **#6060** (web-2-recreate verify hardening) and **#6082** (tolerate web-1's `:latest` in fan-out verify) are related but out of scope — #6082 is non-functional as-is (`ci-deploy.sh:924` hard-rejects non-`vX.Y.Z`); leave as-is, referenced only.
- Optional Sentry-as-C4-element modeling (pre-existing gap) — note in PR body; do not block.
