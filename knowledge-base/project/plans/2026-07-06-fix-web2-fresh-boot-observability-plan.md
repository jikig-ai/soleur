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
- **Secondary hypothesis (H2):** `soleur-host-bootstrap.sh` fails at a late stage but its `emit_fail` DSN fetch (doppler) is unavailable at that instant → silent. Lower-probability (doppler worked moments earlier) but cheaply covered by the baked-DSN preference + per-stage breadcrumbs.
- **This PR does not choose between H1/H2** — it makes both observable. The single post-merge recreate reads the named stage and picks the layer for the follow-up fix (per `2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface.md`).

## Implementation Phases

### Phase 0 — Preconditions (no host writes)

0.1 **(B) cosign confirmation (code-read only).** Re-assert in the PR body: #6023 unmerged; `IMAGE_VERIFY_MODE` default `warn`; no `enforce` setter in repo; cosign verify absent from cloud-init; trusted root installed pre-sentinel (`soleur-host-bootstrap.sh:81`). No code change. (Covers tracker item B.)

0.2 **user_data byte-budget gate (hard).** cloud-init user_data is within ~1 KB of Hetzner's 32,768-byte cap (`server.tf:11`; learning `2026-07-03-cloud-init-32kb-cap-bake-and-extract-not-compress.md`). Before choosing the Phase 2 shape, render the rendered user_data and measure bytes with vs. without the added trap/breadcrumb text:
  - Render via `templatefile("cloud-init.yml", {...})` with placeholder vars and `wc -c` (or `terraform console` under `doppler run … --name-transformer tf-var`).
  - **Decision rule:** if the inline-trap shape (Phase 2, Option A) keeps rendered user_data **< 32,768 bytes**, use it. If it does not, fall back to the **baked-helper** shape (Phase 2, Option B: bake `soleur-boot-emit` into the host-scripts set → zero user_data cost; each block pays only a one-line `trap`). Record the measured before/after byte counts in the PR body.

0.3 Confirm `${sentry_dsn}` is already wired into the cloud-init `templatefile` call (`server.tf:138`) — it is; no Terraform variable plumbing needed for the cloud-init side.

### Phase 1 — `soleur-host-bootstrap.sh`: prefer baked DSN + per-stage breadcrumbs

*(Failing test first per `cq-write-failing-tests-before` — see Phase 4.)*

1.1 **Accept the baked DSN via env.** At the top, resolve a single `DSN` source preferring the env: `SOLEUR_SENTRY_DSN` (passed by cloud-init in Phase 2.1) falling back to the existing doppler fetch. Factor the DSN-resolve + Sentry-POST into one helper (`_sentry_emit <level> <json-tags>`), used by `emit_fail`, `ghcr_login_warn`, and the new breadcrumb emitter — so the DSN preference lives in one place.
  - `emit_fail` (lines 34-52) and `ghcr_login_warn` (lines 168-180) change from doppler-only to `${SOLEUR_SENTRY_DSN:-<doppler fetch>}`.
1.2 **Per-`STAGE` breadcrumb emits.** Add a `_breadcrumb()` that emits a `level:"info"`, `message:"soleur-host-bootstrap stage"` Sentry event with tags `{stage, host_id, region:"bootstrap"}` at each stage transition (`install/hooks/assert/reload/journald/ghcr_login`), and a terminal `stage:"bootstrap_complete"` breadcrumb **immediately before** `: > /run/soleur-hostscripts.ok` (line 199). This makes bootstrap completion (H1's precondition) explicit in Sentry.
1.3 **Fail-open invariant (load-bearing).** Every `_breadcrumb`/`_sentry_emit` call site MUST be `( set +e; ... ) || true` (mirror the existing `ghcr_login` subshell at line 159) so a curl/DNS hiccup can never trip the top-level `set -e` and brick the boot. `emit_fail` continues to `trap - EXIT` first. Add an AC + Sharp Edge for this.
1.4 Keep the emit body a **classification/enum only** (no raw stderr, no creds) — matches the existing scrubbing contract.

### Phase 2 — cloud-init downstream region: baked-DSN trap + breadcrumbs

2.1 **Pass the baked DSN into bootstrap** (tracker item A, `cloud-init.yml:412`): add `SOLEUR_SENTRY_DSN='${sentry_dsn}'` to the `WEBHOOK_DEPLOY_SECRET='...' sh "$SEED/soleur-host-bootstrap.sh" "$SEED"` invocation.

2.2 **Instrument the post-bootstrap region** (the load-bearing extension). The runcmd blocks from the volume mount (417) through the terminal `docker run` (580) currently have **no Sentry trap** except the seed block (359-381, disarmed at 411) and the cron-egress probe (596). Add whole-region coverage. Choose the shape by Phase 0.2:
  - **Option A (inline, preferred if under cap):** consolidate the cloudflared-install + webhook-install/service-enable commands (`cloud-init.yml:433-453`, currently bare `- command` lines) into `- |` block(s) carrying a `set -e` + an `on_err` EXIT trap that reuses the seed block's baked-`${sentry_dsn}` emit shape (359-381), with `STAGE` set per step (`cloudflared_apt`, `cloudflared_service`, `webhook_install`, `webhook_enable`) and an entry breadcrumb per stage. Extend the same trap idiom to the plugin-seed (492), inngest-bootstrap (523), and terminal app-run (555) blocks (`STAGE` = `plugin_seed`/`inngest_bootstrap`/`app_run`), reusing their existing `set -e`.
  - **Option B (baked helper, fallback if Option A blows the cap):** add a small baked `soleur-boot-emit` script to the host-scripts set (installed by `soleur-host-bootstrap.sh`, so it counts toward `host_scripts_content_hash` — zero user_data), reading the baked DSN from a root-only `/run/soleur-boot-dsn` written once by an early cloud-init line (`printf '%s' '${sentry_dsn}' > /run/soleur-boot-dsn`). Each downstream `- |` block then pays only `STAGE=x; trap 'rc=$?; [ "$rc" = 0 ] || soleur-boot-emit "$STAGE" fatal' EXIT` + an entry `soleur-boot-emit "$STAGE" info || true`.
  - **Behavioral-parity invariant (load-bearing):** consolidating bare `- command` lines into `set -e` `- |` blocks MUST preserve every existing tolerance (`mount ... || true` at 418, the `2>/dev/null || true` guards). Add an AC that the consolidated block reproduces each original command's exit tolerance.
  - **Fail-open invariant:** downstream breadcrumb entry calls are `|| true`; the `on_err`/trap fires only on a genuine `set -e` abort (correct — that is the death we want emitted).

2.3 **Discriminating fields (2.9.2 blind-surface requirement):** every fatal/breadcrumb carries `{stage, host_id, region ∈ {bootstrap, cloud-init}}` so **one** event names the exact stage and region where the boot died — no host-side-only inference.

### Phase 3 — recreate workflow: surface the named stage automatically

3.1 Extend the failure Sentry query at `apply-web-platform-infra.yml:1207` from the two literal fatal messages to also match the new downstream fatal message and the last breadcrumb, e.g. add `OR message:"soleur-cloud-init boot failed" OR message:"soleur-host-bootstrap stage"` (final wording to match the Phase 1/2 emit `message` strings — keep them in lockstep). Sort/most-recent so the run summary shows the *last-reached* stage.
3.2 Update the step's summary prose (1198-1201) to say it surfaces the *named boot stage* (not only `emit_fail`). This turns "read the named stage" into an artifact of the recreate run itself (manual `curl` recipe retained as a fallback in the operator runbook, below).

### Phase 4 — Tests (write first; `cq-write-failing-tests-before`)

New `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` (source-grep + behavioral where a POSIX-sh shape can be exercised), plus extend an existing cloud-init test. Assertions:
- `cloud-init.yml:412` passes `SOLEUR_SENTRY_DSN='${sentry_dsn}'` to the bootstrap invocation.
- `soleur-host-bootstrap.sh` `emit_fail` + `ghcr_login_warn` resolve DSN preferring `SOLEUR_SENTRY_DSN` before the doppler fetch.
- A `bootstrap_complete` breadcrumb is emitted before the `/run/soleur-hostscripts.ok` sentinel (grep line-ordering).
- Every breadcrumb/emit call site is `set +e`/`|| true`-guarded (grep: no unguarded `_sentry_emit`/`soleur-boot-emit` on a `set -e` line).
- Downstream cloud-init blocks (cloudflared/webhook + app-run) carry a baked-`${sentry_dsn}` trap and a `STAGE=` per step; consolidated blocks preserve the original `|| true` tolerances.
- `apply-web-platform-infra.yml` Sentry query includes the new stage message(s).
- Wire the new test into `.github/workflows/infra-validation.yml` (mirror line 160's `cloud-init-ghcr-seed-login.test.sh` invocation).

## Files to Edit

- `apps/web-platform/infra/soleur-host-bootstrap.sh` — DSN-prefer env, `_sentry_emit`/`_breadcrumb` helpers, per-stage + `bootstrap_complete` breadcrumbs, fail-open guards. *(Baked → part of `local.host_scripts_content_hash`; needs an image rebuild.)*
- `apps/web-platform/infra/cloud-init.yml` — line 412 `SOLEUR_SENTRY_DSN` pass; downstream region trap + breadcrumbs (Option A or B); (Option B only) early `/run/soleur-boot-dsn` write.
- `.github/workflows/apply-web-platform-infra.yml` — extend the failure Sentry query (1207) + summary prose to surface the named stage.
- `.github/workflows/infra-validation.yml` — run the new observability test.
- *(Option B only)* `apps/web-platform/infra/server.tf` `local.host_scripts_content_hash` list + the Dockerfile COPY set — add `soleur-boot-emit` in lockstep (`server.tf:12` "KEEP THIS LIST IN LOCKSTEP").

## Files to Create

- `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` — the Phase 4 gate.
- *(Option B only)* `apps/web-platform/infra/soleur-boot-emit` — baked POSIX emit helper.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` — no open scope-out names `cloud-init.yml`, `soleur-host-bootstrap.sh`, or `apply-web-platform-infra.yml`. Re-run the standalone-`jq --arg` check at Step 1.7.5 against the final file list before freezing.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (B):** PR body documents that #6023 is unmerged, `IMAGE_VERIFY_MODE` default is `warn` with no `enforce` setter in-repo, and cosign verify is absent from the fresh-boot path — no code change for B. `grep -rn 'IMAGE_VERIFY_MODE' apps/web-platform/infra .github` shows only the `:-warn` default + comparisons.
- [ ] **AC2:** `grep -n "SOLEUR_SENTRY_DSN='\${sentry_dsn}'" apps/web-platform/infra/cloud-init.yml` matches the bootstrap invocation line.
- [ ] **AC3:** `emit_fail` and `ghcr_login_warn` resolve DSN preferring `SOLEUR_SENTRY_DSN` before any `doppler secrets get` (test asserts the `${SOLEUR_SENTRY_DSN:-...}` shape at both sites).
- [ ] **AC4:** A `stage`-tagged breadcrumb is emitted at each `STAGE` transition and a `bootstrap_complete` breadcrumb appears **before** `/run/soleur-hostscripts.ok` (line-order grep).
- [ ] **AC5 (fail-open, load-bearing):** no emit/breadcrumb call site executes under `set -e` unguarded — every one is inside a `( set +e … ) || true` subshell (or `… || true`). Test greps for any bare `_sentry_emit`/`_breadcrumb`/`soleur-boot-emit` not `|| true`-guarded and on a non-`set +e` line → must return zero.
- [ ] **AC6:** the downstream cloud-init region (cloudflared install → webhook enable → app-run) carries a baked-`${sentry_dsn}` fatal trap with `{stage, host_id, region:"cloud-init"}`; consolidated blocks preserve every original `|| true` tolerance (behavioral-parity test).
- [ ] **AC7 (cap):** rendered user_data byte count recorded in PR body and **< 32,768**; if Option B was chosen, `local.host_scripts_content_hash` + Dockerfile COPY include `soleur-boot-emit` (lockstep grep).
- [ ] **AC8:** `apply-web-platform-infra.yml` failure Sentry query matches the new stage message(s) (grep the QUERY string).
- [ ] **AC9:** new test wired into `infra-validation.yml` and passes locally; `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` unaffected (no TS touched); all existing `apps/web-platform/infra/*.test.sh` still pass.
- [ ] **AC10:** PR uses `Ref #6090` (NOT `Closes`) — the boot failure is not fixed by this PR; #6090 stays open until `:9000` binds (ops-remediation-class per Sharp Edge).

### Post-merge (operator + verification)

- [ ] **AC11 [automatable] Image rebuild landed:** after merge, `web-platform-release.yml` rebuilds `${image_name}` with the new baked `soleur-host-bootstrap.sh` (and, Option B, `soleur-boot-emit`). Confirm the new release tag/digest is published before any recreate. *(A recreate before the rebuild would boot the OLD image → no new observability.)*
- [ ] **AC12 [automatable] Quiet-window precondition:** `gh run list --workflow web-platform-release.yml --status in_progress` returns **0** AND web-1 deploy-status `exit_code=0` (HMAC deploy-status probe) AND `app.soleur.ai/health` = 200. Script this as a single go/no-go check before dispatch.
- [ ] **AC13 [operator-ack — menu-ack dispatch] Recreate web-2:** `gh workflow run apply-web-platform-infra.yml -f apply_target=web-2-recreate -f reason='#6090 read named fresh-boot stage'`. `Automation: not feasible because` this is a prod-affecting dispatch gated by `hr-menu-option-ack-not-prod-write-auth` (operator ack required); the pre/post checks (AC12, AC14) are automated around it. NEVER `-replace` web-1.
- [ ] **AC14 [automated in-workflow + manual fallback] Read the named stage:** the recreate run's failure step (Phase 3) surfaces the last-reached `stage` in `$GITHUB_STEP_SUMMARY`. Manual fallback (EU region, `de.sentry.io`): `curl -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://de.sentry.io/api/0/projects/jikigai-eu/web-platform/issues/?query=host-bootstrap&statsPeriod=24h"` (secrets from `doppler … -p soleur -c prd_terraform --plain` via command substitution — never echo).
- [ ] **AC15 [verification]:** the recreate produced a Sentry event whose `stage`/`region` names where the boot died (or `bootstrap_complete` + a downstream `stage` fatal). This proves the probe fires on the affected surface (`2026-06-30-...`). Confirm `app.soleur.ai/health` = 200 unchanged before/after.
- [ ] **AC16 [follow-up]:** file/annotate the follow-up fix issue against the **named** stage; keep #6090 open until web-2 binds `:9000` and a fan-out reports `ok` (not `ok_peer_fanout_degraded`).

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
  - mode: "boot dies downstream of bootstrap (cloudflared apt/service, webhook install/enable, plugin-seed, inngest, app-run)"
    detection: "in-surface on_err Sentry fatal, tags {stage, host_id, region:cloud-init}, baked ${sentry_dsn}; last bootstrap breadcrumb = bootstrap_complete"
    alert_route: "Sentry + recreate summary"
  - mode: "emit path itself unavailable (Sentry egress + doppler both down)"
    detection: "Better Stack per-host absence probe (web-2.app.soleur.ai/health) -- host visibly absent"
    alert_route: "Better Stack page (#5933 Item 1)"
logs:
  where: "on-host cloud-init-output.log (SSH-only, not relied on); journald (persistent post-bootstrap). Off-host truth = Sentry + Better Stack."
  retention: "Sentry project default; Better Stack default"
discoverability_test:
  command: "gh run view <recreate-run-id> --log | grep -i 'fresh-host Sentry pointer'   # OR the AC14 de.sentry.io curl -- NO ssh"
  expected_output: "a Sentry event naming the last-reached stage/region for the boot"
```

## Infrastructure (IaC)

### Terraform changes
- No new Terraform resources or variables. `var.sentry_dsn` already exists (`variables.tf:206`) and is already passed into the cloud-init `templatefile` (`server.tf:138`). Editing `soleur-host-bootstrap.sh` changes `local.host_scripts_content_hash` (`server.tf:77`) — this is expected and *required*: the boot integrity check (`cloud-init.yml:405`) compares the pulled image's baked scripts against the Terraform-computed hash, so the image rebuild and the hash move together. (Option B additionally adds `soleur-boot-emit` to the hash list + Dockerfile COPY, in lockstep.) All `systemctl`/`apt-get`/`cloudflared` references in this plan are EXISTING cloud-init runcmd lines already routed through `templatefile()` + the baked bootstrap script — this plan adds no new manual provisioning, only Sentry breadcrumb/trap text around them.

### Apply path
- **cloud-init + baked-image rebuild → operator-gated `-replace` recreate (path c, scoped).** `soleur-host-bootstrap.sh` is baked into `${image_name}`, so it cannot be hot-patched; the change is live only after `web-platform-release.yml` rebuilds the image (AC11). The instrumented boot is then exercised by a **web-2-only** `terraform apply -replace='hcloud_server.web["web-2"]'` via `apply-web-platform-infra.yml -f apply_target=web-2-recreate` (AC13), operator-ack-gated, fail-closed destroy-guard, in a quiet window (AC12). **Expected blast-radius:** web-2 only (weight-0, non-serving); web-1 untouched; zero prod downtime.

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

1. **DSN preference:** with `SOLEUR_SENTRY_DSN` set, `emit_fail`/`ghcr_login_warn` use it and do **not** call `doppler secrets get` (behavioral, mockable via a stub `doppler` on PATH that fails if invoked).
2. **DSN fallback:** with `SOLEUR_SENTRY_DSN` empty, both fall back to the doppler fetch (existing behavior preserved).
3. **Breadcrumb ordering:** `bootstrap_complete` breadcrumb precedes the sentinel write.
4. **Fail-open:** a stubbed emit that exits non-zero does NOT abort the script (sentinel still written) — proves AC5.
5. **Behavioral parity:** consolidated cloud-init blocks reproduce each original command's exit tolerance (e.g., `mount` still `|| true`).
6. **Workflow query:** the recreate failure step's QUERY matches a synthetic event carrying the new `stage` message.
7. **Cap:** rendered user_data `< 32,768` bytes (Phase 0.2 measurement pinned in PR body).

## Sharp Edges

- **The emit must never brick the boot.** `soleur-host-bootstrap.sh` runs under `set -e`; an unguarded breadcrumb `curl` that exits non-zero would abort → no sentinel → `poweroff -f`. Every emit/breadcrumb is `( set +e … ) || true`. This is the single highest-risk aspect (AC5 + Test 4).
- **Consolidating bare `- command` cloud-init lines into `set -e` `- |` blocks silently changes exit semantics.** Preserve every existing `|| true`/`2>/dev/null || true` tolerance (AC6 + Test 5).
- **user_data is ~1 KB from the 32,768-byte cap.** Measure before/after (Phase 0.2). If inline traps blow the cap, use the baked-helper shape (Option B) — do not ship an untested cap-buster.
- **Editing a baked script changes `host_scripts_content_hash`; the recreate boot-verifies against it (`cloud-init.yml:405`).** This is correct *only if* the image is rebuilt from the same source before the recreate (AC11). A recreate before the rebuild boots the old image (old hash, old scripts) → no new observability and a possible hash mismatch abort. Sequence: merge → release/rebuild → recreate.
- **This PR does not close #6090.** It makes the failure observable; the actual stage fix is a follow-up. Use `Ref #6090`, not `Closes` (ops-remediation class — auto-close-at-merge would false-resolve).
- **Keep the emit `message` strings in lockstep across `soleur-host-bootstrap.sh`, `cloud-init.yml`, and the `apply-web-platform-infra.yml` query.** A query that doesn't match the emitted message silently shows "no event" (the exact blind spot this PR closes) — AC8 + Test 6.
- **EU Sentry region.** The manual read uses `de.sentry.io` / `jikigai-eu` (DSN host segment carries residency — learning `2026-05-15-sentry-dsn-cluster-substring-authoritative-residency.md`). The baked DSN's host segment already encodes this, so the on-host emit posts to the right region automatically.

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
