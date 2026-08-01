---
title: "fix(infra): the fix for #7095 merged and never reached the host — the delivery channel's own credential is dead"
issue: 7095
followup_issue: 7103
type: ops-remediation
classification: ops-only-prod-write
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-08-01
branch: feat-one-shot-7095-web1-immutable-redeploy
status: draft
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# The fix for #7095 merged and never reached the host

Every phase below ships through Terraform and existing GitHub Actions workflows. There are **zero**
human-run infrastructure steps: no shell on the host, no vendor-dashboard click, no credential typed
by hand. The `## Infrastructure (IaC)` section names the resources and the apply path.

## Overview

Production has not deployed since 2026-07-29. `app.soleur.ai/health` serves **v0.244.0**
(`build_sha=34654d7ab11b2c28ed08f559ac5af1ef59042cb3`, uptime 224372 s ≈ 62.3 h, pulled
2026-08-01T11:38Z) while `main` is at **v0.247.1**. Eight consecutive `Web Platform Release`
runs have failed at `reason=image_pull_failed`.

PR **#7097** (merged 2026-07-31, commit `3faa95fa8`) built the correct repair: a re-deliverable
sibling credential (`/etc/default/soleur-doppler-token`) plus three systemd drop-ins, wired into
the `infra-config` `FILE_MAP`. **It never reached the host.** Its own delivery apply
(run `30650564509`) destroyed both `terraform_data` resources and then failed to recreate them,
because the root-SSH leg it depends on could not open the Cloudflare Tunnel to `ssh.soleur.ai`.

The reason that leg is dark is the **same defect class as #7095 itself, one credential over**:
the `github-actions-ci-ssh` Cloudflare Access service token was rotated at source, and neither
Terraform state nor Doppler carries the post-rotation secret. Verified below: the secret in
Terraform state is **byte-identical** to the one in Doppler `prd_terraform`, and **both are
rejected** by Cloudflare Access.

This plan restores the delivery channel with Terraform, lets the already-merged #7097 payload land,
closes the structural hole that let the Access token go stale invisibly, and verifies the outcome by
pulling `/health` directly.

**This run closes #7095. It does not close #7103** — see [§Scope vs #7103](#scope-vs-7103).

---

## Research Reconciliation — Hypothesis vs. Live Evidence

Every row below was measured by this session on 2026-08-01 (`hr-no-dashboard-eyeball-pull-data-yourself`).
No row is inferred from a dashboard screenshot or a report.

| Claim under test | Reality (measured) | Plan response |
|---|---|---|
| Prod is stale at v0.244.0 while main is v0.247.1 | **CONFIRMED.** `curl https://app.soleur.ai/health` → `{"status":"ok","version":"0.244.0","build_sha":"34654d7ab…","uptime":224372}` | DoD re-pulls this endpoint as the sole acceptance signal. |
| web-1's Doppler token is **baked into the host** and a merged code change cannot rotate it | **CONFIRMED, three ways.** (a) `soleur-doppler-token.tmpl` renders `DOPPLER_TOKEN=${doppler_token}`; `cloud-init.yml` writes it once at first boot. (b) Better Stack, host `soleur-web-platform`, unit `webhook`: **55 × `Doppler Error: Invalid Auth token`**, 2026-07-31 09:51:53 → 2026-08-01 07:02:12. (c) The value **in Doppler** (`soleur/prd_terraform` `DOPPLER_TOKEN`, i.e. `var.doppler_token`) authenticates against `soleur/prd` → **HTTP 200**. | The Doppler-side value is **valid**. This is a *delivery* gap, not a *value* gap — **no token re-mint is needed for the host credential**. Deliver the existing value. |
| "the zot gate goes dark and the pull falls through to an unauthenticated GHCR fetch" | **CONFIRMED verbatim** by the host's own `ci-deploy` log triplet (Better Stack, host `soleur-web-platform`, 2026-08-01 07:01–07:02): `ZOT_GATE: ZOT_REGISTRY_URL unset — GHCR path (dark, pre-provisioning)` → `PRELUDE: GHCR_READ_{USER,TOKEN} not both present (baked file absent + doppler empty/unavailable) — skipping docker login` → `IMAGE_PULL_FAIL: ref=ghcr.io/jikig-ai/soleur-web-platform:v0.247.1 result=auth_denied recovery_stage=refetch_unavailable`. Identical triplet for v0.246.6 and v0.247.0. `zot_gate_and_login()` in `ci-deploy.sh` is **fail-open by contract** (`# … Fail-open: never aborts the deploy`). | No change to the fail-open contract in this PR (that is #7103 B1's `doppler_read_failed` terminal reason). Delivering the credential removes the trigger. |
| The host emits `dark, pre-provisioning` even though it is *not* pre-provisioning | **CONFIRMED — and it is itself evidence.** #7097 shipped the honest `cred_read_failed` message into the repo's `ci-deploy.sh`. The host still emits the old misleading string ⟹ **#7097's `ci-deploy.sh` never landed on the host.** | Used as an independent acceptance signal: after delivery, the host's message must change. |
| **"Per `hr-prod-host-config-change-immutable-redeploy` the repair is an immutable redeploy of web-1"** | **REFUTED as executable.** The rule's own stated precondition — *"`-replace` DESTROYS before it creates: a failed create (DC stock, cloud-init) strands the fleet with NO rollback — verify target-type stock in the target location first"* — **fails**. Hetzner API: `cx33` = `server_type id 115`; `available=false` **and** `available_for_migration=false` in **all 6** datacenters (`nbg1-dc3`, `hel1-dc2`, `fsn1-dc14`, `ash-dc1`, `hil-dc1`, `sin-dc1`). web-1 (`soleur-web-platform`) is a running `cx33`. | A `-replace` would take prod from *stale but serving* to *destroyed and unbootable*. **Rejected.** It also would **not** bypass the blocker — see next row. |
| An immutable redeploy would sidestep the credential problem | **REFUTED.** A fresh web-1 needs **16** `terraform_data` SSH installers to run (`root_authorized_keys`, `disk_monitor_install`, `resource_monitor_install`, `container_restart_monitor_install`, `private_nic_guard_install`, `zot_consumer_probe_install`, `git_data_probe_install`, `fail2ban_tuning`, `journald_persistent`, `cosign_trusted_root`, `registry_insecure_config`, `infra_config_handler_bootstrap`, `docker_seccomp_config`, `apparmor_bwrap_profile`, `orphan_reaper_install`, `cron_egress_firewall`) — **all through the same dark CF-Access channel**. | Restoring the channel is a **precondition of every remedy**, redeploy included. It is therefore Phase 1 regardless. |
| The delivery channel is dark because of a host-side SSH fault (sshd / fail2ban) | **REFUTED.** Better Stack shows **zero `sshd` events on `soleur-web-platform` since 2026-07-31 10:44:36** — the traffic never reaches the host. Vector is demonstrably still shipping (`web-zot-consumer-probe`, `web-git-data-probe`, `web-nic-guard`, `webhook` all current). | Diagnosis stays at the edge. No sshd/fail2ban work in scope. |
| The delivery channel is dark because the CF tunnel or web-1's private NIC is down | **REFUTED.** Tunnel `soleur-web-platform`: `status=healthy`, `4` connections. Ingress config (CF-managed): `ssh.soleur.ai → ssh://10.0.1.10:22` and `deploy.soleur.ai → http://10.0.1.10:9000` — **same host, same private NIC**, and `deploy.soleur.ai` reaches its origin (below). | Ruled out. |
| The delivery channel is dark because the CI Access **credential** is rejected | **CONFIRMED by a 3-probe control set.** (A) `GET https://ssh.soleur.ai/` with Doppler `CI_SSH_ACCESS_TOKEN_ID/_SECRET` → **403 Cloudflare Access**, `"You don't have permission to view this."` (B) same URL with a **deliberately bogus** secret → **identical** message (negative control). (C) `GET https://deploy.soleur.ai/hooks/deploy-status` with Doppler `CF_ACCESS_CLIENT_ID/_SECRET` → Access **admits**, origin answers `"Hook rules were not satisfied."` (positive control, known-granted). | The Doppler-held CI-SSH credential is indistinguishable from a bogus one. |
| The Doppler copy merely drifted from Terraform (a republish would fix it) | **REFUTED.** `terraform output -raw ci_ssh_access_service_token_client_secret` is **byte-identical** to Doppler `CI_SSH_ACCESS_TOKEN_SECRET` (both 64 chars), and the **state** value is also rejected by CF Access (403, same body). **Cloudflare has diverged from both.** | A republish cannot help. The token must be re-minted by Terraform via `-replace`. |
| Terraform would have detected this drift | **REFUTED, and irrelevant.** `terraform plan` cannot see it (Cloudflare never returns `client_secret` after create). But Terraform was never the intended detector — see the next two rows. | No Terraform-side change. |
| ~~`ci_ssh` has no Doppler propagation path because it is an `output`, not a `doppler_secret` — "the structural hole"~~ | **FALSIFIED by deepen review.** `apply-web-platform-infra.yml` already runs **`Sync CF Access CI-SSH service token to Doppler`** (with `apps/web-platform/infra/scripts/sync-ci-ssh-access-token.sh`), reading both `output`s and writing `CI_SSH_ACCESS_TOKEN_ID/_SECRET` to `prd_terraform` on **every** apply. `tunnel.tf`'s own comment says `.deploy` and `.ci_ssh` are **exempt** from the stale-value trap *because* they are `output`s — the opposite of what this plan originally claimed. An `output` + unconditional sync step is **strictly stronger** than a `doppler_secret` carrying `ignore_changes = [value]`, which suppresses the very rewrite a rotation needs. | **Phase 3 CUT in full.** See §Revision R1. |
| **Nothing would have caught this — there was no detector** | **FALSIFIED, decisively.** `scripts/check-cloudflare-token-drift.sh` already maps `CI_SSH_ACCESS_TOKEN → ssh.soleur.ai` and verifies the pair against Access (`200 ⇒ LIVE`, else `DEAD`). `.github/workflows/scheduled-terraform-drift.yml` runs it **twice daily** and emails ops on a DEAD verdict. Pulled from run `30686984837` (2026-08-01T06:03Z): `live entries: 10   dead entries: 1   unverifiable: 0` / `CI_SSH_ACCESS_TOKEN_ID/_SECRET (HTTP 403 from ssh.soleur.ai)  in  prd_terraform` / `token-drift verdict: dead (detector exit 1)`, and the step `Email notification (token drift — DEAD credential)` ran (`success`, while its `UNVERIFIABLE` and `could-not-run` siblings show `skipped`). The same verdict appears on runs `30653453432` (07-31 18:00) and `30608371251` (07-31 06:00). | **This is the actual root cause of the 3-day duration.** The detector was right, precise, and ignored. **Phase 4 reframed** from "build a probe" to "make the existing verdict *block* and *reach a human*". See §Revision R2. |
| The out-of-band rotation has no known actor | **ATTRIBUTED.** The #7065 commit message (`git show 11674a1ab`) states `.deploy` and `.ci_ssh` *"could be rotated out-of-band during the 2026-07-28 incident response"* — i.e. the operator rotated both by hand while fixing the earlier incident, and Doppler was updated for `.deploy` but not `.ci_ssh`. Not an unexplained security event. | Recorded so the ADR draws the right lesson (hand-rotation during incident response needs a propagation checklist), not a fictional one. |
| `.deploy`'s Terraform state value is safe to publish | **REFUTED — and this is the plan's most dangerous near-miss.** `.deploy` was rotated in the **same** out-of-band window, so state holds the **dead pre-rotation** secret while Doppler holds the **live** one (which is why probe (C) is admitted). The original Phase 3 would have `create`d a `doppler_secret` from **state → Doppler**, overwriting the live value with the dead one. `ignore_changes = [value]` does **not** suppress a create. That would have destroyed the last remaining write path to a host with 0/6 DC stock — the exact catastrophe §User-Brand Impact claims to prevent. | **Phase 3 CUT.** Recorded here permanently so no future plan re-proposes it. |
| L3 firewall / egress-IP drift is the cause (`hr-ssh-diagnosis-verify-firewall`) | **CHECKED FIRST, REFUTED.** Hetzner firewall `soleur-web-platform` (applied to servers `123931471`, `155786558`): `in tcp :22` from five `/32`s; `in tcp :443` and `:80` from the full Cloudflare IP ranges (incl. `188.114.96.0/20`, the range `ssh.soleur.ai` resolves into). The CI path is CF-tunnel over `:443` **from an allowed range**. This session's own egress `82.67.29.121` is correctly absent from the `:22` allowlist — direct SSH is not the path and is not expected to work. | L3 is **not** the blocker. Recorded to satisfy the hard rule's ordering requirement. |

### Why PR #7097 did not restore production

#7097 was **correct code with an unverified delivery precondition**.

Its plan (`knowledge-base/project/plans/2026-07-30-fix-web-host-doppler-token-revocation-broke-host-pull-leg-plan.md`,
§Apply path) chose *"(b) — the existing Terraform-driven, **no-SSH** infra-config push, applied on
merge."* That framing is **half-true and the missing half is fatal**:

- `terraform_data.deploy_pipeline_fix` is genuinely SSH-free — a single `local-exec` running
  `push-infra-config.sh`, which HMAC-POSTs to `https://deploy.soleur.ai/hooks/infra-config`.
- But it carries `depends_on = [terraform_data.apparmor_bwrap_profile, terraform_data.infra_config_handler_bootstrap]`,
  and `infra_config_handler_bootstrap` **is** a root-SSH resource (`connection { type = "ssh"; host = hcloud_server.web["web-1"].ipv4_address }`).
  It has to be: `infra-config-apply.sh` is *not itself in the `FILE_MAP`* (`server.tf` comment
  anchor `Delivered here (root SSH) because the webhook handler that depends on it cannot deliver it`),
  so the handler cannot self-update and the new `FILE_MAP` — the one that knows about
  `SOLEUR_DOPPLER_TOKEN_B64` — can only arrive over that leg.

The plan's own review caught the shape of this (*"the apply's own SSH dependency was unverified"*)
and answered it with **R34/Phase 0.2b: confirm the last green run of `apply-deploy-pipeline-fix.yml`**.
That is a *citation of a past success*, not a *probe of the present channel*. The last green run was
2026-07-30T16:30:44Z; by 2026-07-31T17:17 the channel was dead, and nothing re-checked.

The failure is recorded in run `30650564509`:

```
terraform_data.deploy_pipeline_fix: Destroying... [id=b123a651-…]
terraform_data.deploy_pipeline_fix: Destruction complete after 0s
terraform_data.infra_config_handler_bootstrap: Destroying... [id=4875c1cf-…]
terraform_data.infra_config_handler_bootstrap: Creating...
terraform_data.infra_config_handler_bootstrap: Provisioning with 'file'...
… Still creating… [4m50s elapsed]
Error: file provisioner error
  with terraform_data.infra_config_handler_bootstrap,
  on server.tf line 1251, in resource "terraform_data" "infra_config_handler_bootstrap":
timeout - last error: SSH authentication failed (root@***:22):
ssh: handshake failed: read tcp 10.1.0.116:49530->***:22: read: connection reset by peer
```

with the CI-side cloudflared logging, continuously from 17:24:35Z to 17:29:35Z:

```
ERR failed to connect to origin error="websocket: bad handshake" originURL=https://ssh.soleur.ai
```

Three consequences, all load-bearing for this plan:

1. **The payload never shipped.** `deploy_pipeline_fix` was destroyed *first* and never recreated,
   so `push-infra-config.sh` never ran. `/etc/default/soleur-doppler-token` does not exist on the host.
2. **State is now emptier than reality.** Both `terraform_data` resources are absent from state
   while the host still carries the *old* handler. Any recovery apply will create both.
3. **It is reproducible, not a flake.** `apply-web-platform-infra.yml` run `30688451196`
   (2026-08-01T06:48Z) failed identically — `file provisioner error` *and* `remote-exec provisioner error`,
   same `connection reset by peer`.

**So this must not become a third code patch.** The code on `main` is already right. The blocker is
one dead credential guarding the road the code travels on.

---

## Scope vs #7103

| Item | Owner | This run |
|---|---|---|
| Restore prod deploys; `/health` reports v0.247.x+ | **#7095** | **In scope — closes it** |
| Re-mint the `ci_ssh` CF Access token through Terraform `-replace` | **#7095** (new — the live blocker) | **In scope** |
| Convert `ci_ssh` + `deploy` Access tokens from TF `output`s to `doppler_secret` resources | **New, folded into #7095** | **In scope** — same defect class as #7095, and leaving it open re-arms the identical outage |
| Fail-fast Access probe in the SSH-bridge step, *before* Terraform destroys anything | **New, folded into #7095** | **In scope** — this is precisely the #7097 failure mode |
| B1 telemetry off the box (`vector.toml` allowlist + `SyslogIdentifier=` stamps, two-sided drift guard, terminal `doppler_read_failed` reason) | #7103 | **Out** |
| B2 continuous credential liveness (`SOLEUR_DEPLOY_CRED` in `web-zot-consumer-probe.sh`) | #7103 | **Out** |
| B3 staleness / consecutive-failure alerting on the Inngest substrate | #7103 | **Out** |
| B4 fleet-wide de-pinning of the 16 web-1-pinned installers; ship `vector.toml` to web-2 | #7103 | **Out** |
| B5 records (ADR-154, PIRs, `apply-deploy-pipeline-fix.yml` schedule, heartbeat-arming guard) | #7103 | **Out** — except the ADR this plan owns (below) |

**One new item is added to #7103's ledger by this incident** and must be filed as a comment on
#7103 during `/ship`: *the 16 SSH installers and the `apply-deploy-pipeline-fix.yml` bridge share a
single Access credential with no liveness probe and no auto-republish; B2's probe must therefore
cover the **CI-side** credential, not only the host-side one.*

---

## User-Brand Impact

**If this lands broken, the user experiences:** `app.soleur.ai` continues to serve v0.244.0 — three
minor versions of shipped work that the founder can see merged on GitHub and cannot see in his own
product. Every subsequent merge deepens the gap silently, because a red release run is not itself an
alerted condition. Worse, a botched Phase 1 could revoke the *working* `deploy` Access token as
collateral, taking the webhook channel down too and leaving **no** remote write path to web-1 on a
host that cannot be replaced (0/6 DC stock).

**If this leaks, the user's infrastructure is exposed via:** the freshly minted `ci_ssh` Access
service-token secret grants root shell on the production host through `ssh.soleur.ai`. It transits
Terraform state (R2, encrypted at rest), Doppler `prd_terraform`, and GitHub Actions runner memory.
A leak is full production compromise — application data, customer records, and the Doppler `prd`
config the host can read.

**Brand-survival threshold:** `single-user incident`

CPO sign-off is required before `/work` begins; `user-impact-reviewer` is invoked at review time.

---

## Hypotheses

Network-outage checklist fired (`connection reset`, `handshake`, `timeout`, `unreachable`, plus a
`provisioner "file"` + `connection { type = "ssh" }` block in the apply path). Diagnosis proceeded
**L3 → L7** per `hr-ssh-diagnosis-verify-firewall`, and the L3 result is recorded above before any
service-layer hypothesis was formed.

| # | Hypothesis | Verdict | Discriminator (already run) |
|---|---|---|---|
| H1 | Hetzner L3 firewall / egress-IP drift blocks :22 | **REFUTED** | `:443` open to all CF ranges; CI path is CF-tunnel, not direct :22 |
| H2 | DNS/routing for `ssh.soleur.ai` broken | **REFUTED** | Resolves to `188.114.97.2`/`188.114.96.2`; edge answers (403, not NXDOMAIN/timeout) |
| H3 | CF tunnel connector down / web-1 private NIC down | **REFUTED** | Tunnel `healthy`, 4 conns; `deploy.soleur.ai → http://10.0.1.10:9000` reaches origin on the same NIC |
| H4 | sshd down / fail2ban ban on web-1 | **REFUTED** | Zero `sshd` events since 2026-07-31 10:44:36 while vector ships everything else — traffic never arrives |
| H5 | Doppler's copy of the `ci_ssh` secret drifted from Terraform | **REFUTED** | state secret **==** Doppler secret, byte-identical |
| **H6** | **The `ci_ssh` Access token was rotated out of band; state *and* Doppler both hold the pre-rotation secret; Cloudflare has diverged from both** | **CONFIRMED** | 3-probe control set (bogus-secret negative control + `deploy` positive control) + state-vs-Doppler equality + state secret also 403s |
| H7 | web-1's baked Doppler token is revoked and has no re-delivery path | **CONFIRMED** | 55 × `Invalid Auth token` from the host; the same value in Doppler returns HTTP 200 |

**Residual uncertainty, recorded rather than papered over.** H6's probes are HTTP `GET`s against an
Access app whose ingress is `ssh://`. The negative and positive controls make credential rejection by
far the best-supported reading, but they do not *formally* exclude "this app denies plain HTTP GETs
regardless of token validity". Phase 1 therefore re-runs probe (A) **after** the re-mint as a gating
assertion: if the freshly minted secret still 403s, the H6 verdict was wrong and `/work` must stop and
re-diagnose rather than proceed to Phase 2. The probe that decides the plan is the same probe that
grades it.

---

## Implementation Phases

### Phase 0 — Preconditions (read-only, no writes)

0.1 Re-pull `https://app.soleur.ai/health`; record `version`, `build_sha`, `uptime`. If `version`
    is already ≥ `0.247.0`, **stop** — prod recovered by another path and this plan is stale.
0.2 Re-run the H6 control triad exactly as specified in Research Reconciliation. All three outcomes
    must reproduce. If probe (C) — the `deploy` positive control — now fails, **stop**: the webhook
    channel has also gone dark and the blast radius has changed.
0.3 Re-verify `cx33` stock via the Hetzner `/v1/datacenters` endpoint against `server_type id 115`.
    If it has become available in web-1's location, note it in the PR body as a newly-available
    option — but do **not** switch to a host `-replace`; the channel repair is still strictly smaller
    and still a precondition.
0.4 `terraform plan` (read-only, `-target` set of Phase 1) and confirm the plan shows exactly the
    intended replace plus the new `doppler_secret` creates, and **zero** `hcloud_server` creates or
    destroys. Attach the counts to the PR body.

### Phase 1 — Re-mint the `ci_ssh` Cloudflare Access service token (Terraform, no SSH)

The token resource already carries `lifecycle { create_before_destroy = true }`, added by
"fix(infra): make the CF Access service tokens rotatable" (apply run `30468079949`, 2026-07-29),
precisely so this operation is safe while the policy references it.

1.1 `terraform apply -replace=cloudflare_zero_trust_access_service_token.ci_ssh`, `-target`-scoped so
    the SSH-dependent graph is never touched: the token, plus
    `cloudflare_zero_trust_access_policy.ci_ssh_service_token` (its `include.service_token`
    references the token's `id`, which changes on replace), plus the four new `doppler_secret`
    resources from Phase 3. This leg needs **no SSH bridge** — it is Cloudflare + Doppler APIs only.

    **The seam already exists — use it, do not invent one.** `apply-web-platform-infra.yml` is
    already split into two applies (#4844): (a) `Terraform plan (allow-list, non-SSH resources only)`
    → `Terraform apply`, covering ~80 non-SSH resources from a saved `tfplan`; and (b) a separate
    token-gated `Terraform apply (SSH-provisioned resources, over the bridge)`. Leg (a) **already
    `-target`s `cloudflare_zero_trust_access_service_token.ci_ssh` and
    `cloudflare_zero_trust_access_policy.ci_ssh_service_token`** — verified by reading the
    allow-list. So Phase 1 rides leg (a), which by construction touches no SSH resource. Only the
    `-replace` flag and the four `doppler_secret` targets are new.
1.2 The `apply-web-platform-infra.yml` bridge step must be non-fatal (or skipped) for this `-target`
    set; today it starts cloudflared unconditionally. See Phase 4.
1.3 **Gating assertion.** Re-run probe (A) against `ssh.soleur.ai` with the *newly published* Doppler
    values. It MUST no longer return the Cloudflare Access denial body. If it does, **halt** — H6 was
    wrong (see Residual uncertainty) and no further phase may run.

**Blast-radius note:** the `-replace` must be scoped to `.ci_ssh` alone. The sibling
`cloudflare_zero_trust_access_service_token.deploy` is currently **working** and is the only remaining
remote write path to web-1. Replacing it in the same apply would, on any failure between destroy and
Doppler republish, leave the host with **no** reachable channel at all — on a host with 0/6 DC stock.
`deploy` gains a `doppler_secret` in Phase 3 but is **not** replaced.

### Phase 2 — Let the already-merged #7097 payload land

2.1 Re-dispatch `apply-deploy-pipeline-fix.yml`. Both `terraform_data.infra_config_handler_bootstrap`
    and `terraform_data.deploy_pipeline_fix` are absent from state, so both are created:
    the root-SSH leg lands the new `infra-config-apply.sh` (the `FILE_MAP` that knows
    `SOLEUR_DOPPLER_TOKEN_B64`), then the `local-exec` leg pushes the rendered
    `/etc/default/soleur-doppler-token`, the three `10-*-doppler-token.conf` drop-ins, and the
    post-#7097 `ci-deploy.sh`.
2.2 The workflow's existing "Verify infra-config apply succeeded" step (`infra-config-gate.sh`)
    performs the per-file sha256 content assert. It must pass on its own terms — **do not** re-run a
    content mismatch away; the gate is terminal by design (`CONTENT MISMATCH IS TERMINAL`).
2.3 No repo change to `ci-deploy.sh` or the `FILE_MAP` in this PR. The code on `main` is already
    correct; the only thing missing was arrival.

### ~~Phase 3 — Close the structural hole~~ — **CUT IN FULL (Revision R1)**

**Do not implement any of the following.** It is retained struck-through because three independent
reviews converged on it as the plan's most dangerous content, and a future planner who deletes it
outright will re-propose it.

Why it is cut:

1. **The hole it claims to close does not exist.** `ci_ssh` already has an auto-republish path — the
   `Sync CF Access CI-SSH service token to Doppler` step in `apply-web-platform-infra.yml` plus
   `apps/web-platform/infra/scripts/sync-ci-ssh-access-token.sh`, which write
   `CI_SSH_ACCESS_TOKEN_ID/_SECRET` on **every** apply. `tunnel.tf`'s own comment states `.deploy` and
   `.ci_ssh` are **exempt** from the stale-value trap *because* they are `output`s.
2. **It would have been a regression.** `doppler_secret` + `ignore_changes = [value]` suppresses the
   in-place `value` update that a rotation produces. `check-cloudflare-token-drift.sh`'s own header
   says so: *"Terraform can never propagate a rotated token."* So the "auto-republish" would work
   exactly once (on create) and silently freeze every rotation thereafter — **manufacturing this
   outage permanently.** Two writers on one key, the new one frozen.
3. **The `deploy` half would have taken production down.** `.deploy` was rotated in the *same*
   2026-07-28 out-of-band window, so Terraform state holds the **dead** secret while Doppler holds the
   **live** one. `value = …deploy.client_secret` on a `create` writes state → Doppler, and
   `ignore_changes` does **not** suppress a create. That publishes the dead secret over the working
   one and leaves **zero** remote write paths to a host with 0/6 DC stock. `tunnel.tf` further warns
   `client_secret` *"is populated ONLY at create and reads EMPTY on subsequent terraform refresh"* —
   so the written value might even be the empty string, which `doppler secrets get --plain` returns
   with **rc=0**, defeating the `||` fallback in `apply-deploy-pipeline-fix.yml`.

**Consequences of the cut:** `tunnel.tf` is no longer edited at all; AC2 and AC5c are deleted; Test
Scenario 6 is deleted; ADR propositions 2 and 3 are deleted; the `-target` allow-list append
(old Phase 3.4) is moot. **`## Files to Edit` shrinks to the two workflow files.**

**Deferred to #7103, with the evidence above attached:** `.deploy` is *also* stale in Terraform state.
That is a live landmine — any future untargeted apply that syncs outputs republishes a dead secret
over the working one. It needs its own PR that sequences **after** `ci_ssh` is restored, enumerates
all three holders (Doppler, the `secrets.CF_ACCESS_CLIENT_*` GitHub Actions repo secrets consumed by
`web-platform-release.yml`, and operator-env consumers), and updates them atomically.

<details>
<summary>Original Phase 3 text (do not implement)</summary>

### Phase 3 — Close the structural hole (the reason nobody saw this coming)

3.1 In `tunnel.tf`, convert `ci_ssh` and `deploy` client_id/client_secret from bare `output`s to
    `doppler_secret` resources targeting `soleur/prd_terraform`
    (`CI_SSH_ACCESS_TOKEN_ID`, `CI_SSH_ACCESS_TOKEN_SECRET`, `CF_ACCESS_CLIENT_ID`,
    `CF_ACCESS_CLIENT_SECRET`), mirroring the existing `registry_push` pair — which is already a
    `doppler_secret` and is the reason the registry push leg stayed healthy through the same window.
3.2 Adopt `registry_push`'s documented `lifecycle` discipline verbatim; do **not** invent a new shape.
    The existing comment block in `tunnel.tf` explains why `ignore_changes = [value]` is correct for a
    write-once credential and why `-replace` is the intended rotation verb.
3.3 The `output`s are retained (they are consumed elsewhere and removing them is out of scope), but a
    comment must record that the `doppler_secret` — not the `output` — is now the propagation path.
3.4 **Append all four new `doppler_secret` addresses to the `-target=` allow-list** in
    `apply-web-platform-infra.yml`'s non-SSH plan step (`Terraform plan (allow-list, non-SSH resources
    only)`). The workflow states this obligation in-line — *"`apps/web-platform/infra/*.tf`, append a
    matching `-target=<addr>`"* — and it is load-bearing: a resource absent from the allow-list is
    **never applied on merge**, so the auto-republish would exist in HCL and never run. This is the
    single most likely way Phase 3 ships as a no-op. Verify by counting `-target=` entries before and
    after, and by confirming each new address appears in the plan output at Phase 0.4.

</details>

### Phase 4 — Make the *existing* verdict block, and reach a human (Revision R2)

**Reframed.** The original Phase 4 proposed building a probe. A probe already exists, already runs,
already produced the right answer, and was ignored. Building a third one fixes nothing.

**What actually happened.** `scripts/check-cloudflare-token-drift.sh` runs twice daily via
`scheduled-terraform-drift.yml`. Run `30686984837` (2026-08-01T06:03Z) output, pulled verbatim:

```
  live entries: 10   dead entries: 1   unverifiable: 0
  CI_SSH_ACCESS_TOKEN_ID/_SECRET (HTTP 403 from ssh.soleur.ai)  in  prd_terraform
  Set the live value on the 'prd' ROOT config; branch configs inherit it.
token-drift verdict: dead (detector exit 1)
```

Same verdict on `30653453432` (07-31 18:00Z) and `30608371251` (07-31 06:00Z); the
`Email notification (token drift — DEAD credential)` step ran on all three. **The detector named the
exact credential, the exact symptom, and the exact remedy, three times, and production stayed down.**

So the gap is not detection. It is **(a)** the verdict blocks nothing, and **(b)** the notification
channel does not reach the operator in a form he acts on. Both fixes are small:

4.1 **Make the verdict block the channel it invalidates.** The `cf-tunnel-ssh-bridge` **composite
    action** (`.github/actions/cf-tunnel-ssh-bridge/action.yml`) is the single shared entry point —
    it has **six** callers (`apply-web-platform-infra.yml`, `apply-deploy-pipeline-fix.yml`,
    `git-data-cutover.yml`, `workspaces-luks-cutover.yml` ×2, `workspaces-luks-verify.yml`). Add one
    step inside the composite, after the forward opens and after its `::add-mask::` calls:

    ```
    bash scripts/check-cloudflare-token-drift.sh --only CI_SSH_ACCESS_TOKEN
    ```

    `--only` exists for exactly this ("must not spend a full fleet-wide sweep"); the script already
    returns the three-valued 0/1/2 this needs; `reusable-release.yml` is the copy-paste precedent.
    On exit 1, fail the action with terminal reason `ci_ssh_access_denied`. **One edit, six callers,
    no duplicated logic, no new test surface** — `scripts/check-cloudflare-token-drift.test.sh`
    already exists, already has an Access service-token arm, and is already registered in
    `scripts/test-all.sh`.

    This also resolves the plan's §Residual uncertainty: the script's own comment
    (*"The 200 here is EMPTY, and that is correct, not suspicious"*) confirms the bare-GET
    discriminator against an `ssh://`-ingress app is the intended check, so Phase 1.3's hedge
    becomes a firm gate.

4.2 **Escalate the DEAD verdict from email to an `action-required` GitHub issue.** Email demonstrably
    did not produce action across three fires and three days. `operator-digest` harvests
    `action-required`-labelled **issues**, not emails. In `scheduled-terraform-drift.yml`, add issue
    creation/update alongside the existing `notify-ops-email` on verdict `dead`, carrying the
    detector's own remedy line. This is the single highest-value change in the plan for preventing
    recurrence, and it is ~15 lines on an existing job.

4.3 **Do not weaken the existing presence gate.** `apply-web-platform-infra.yml`'s
    `Check CI-SSH token presence (gates the SSH apply)` correctly keeps its `absent → skip` arm for
    genuine first-bootstrap. The liveness check in 4.1 sits *after* it, inside the bridge — so the
    three outcomes become: absent → skip (bootstrap, green); present-but-dead → **fail** with a named
    reason; present-and-live → proceed.

4.4 The probe must never echo the credential: pass ID/secret via `env:`, never argv (`ps`-visible);
    no `-v`/`-i`/`--trace*`/`set -x`; `--max-redirs 0` (curl forwards custom `-H` across redirects);
    and if any result reaches a GitHub Actions annotation, emit **the enum and status code only**,
    never the response body.

<details>
<summary>Superseded Phase 4 text (do not implement — kept for the reasoning, not the plan)</summary>

### ~~Phase 4 — Upgrade the existing SSH gate from *presence* to *liveness*~~

The #7097 failure mode was: destroy two resources, then discover the channel is dead, then leave state
emptier than reality. That ordering is the defect — **and the gate that was supposed to prevent it
already exists and asserts the wrong thing.**

`apply-web-platform-infra.yml` already runs a step named
**`Check CI-SSH token presence (gates the SSH apply)`** immediately before
`CF Tunnel SSH bridge (gated)` and `Terraform apply (SSH-provisioned resources, over the bridge)`.
Its entire body is:

```bash
TOKEN_ID=$(doppler secrets get CI_SSH_ACCESS_TOKEN_ID --plain 2>/dev/null || true)
if [[ -z "$TOKEN_ID" ]]; then
  echo "ssh_apply_skip=true"  >> "$GITHUB_OUTPUT"   # first-bootstrap accommodation
else
  echo "ssh_apply_skip=false" >> "$GITHUB_OUTPUT"
fi
```

It reads the **ID** only, never the **secret**, and never asks Cloudflare whether the pair is
accepted. This is a **proxy-vs-invariant** defect: *config-secret presence* is asserted where
*credential validity* is meant. Today the gate is **green** — `CI_SSH_ACCESS_TOKEN_ID` is present and
even correct (it matches the live token's `client_id`) — while the credential is dead. That is
precisely why the workflow sailed past its own gate into the SSH apply and failed at
`connection reset by peer` instead of stopping with a named reason.

4.1 **Upgrade the gate to assert liveness**, not presence. After reading the ID *and secret*, issue the
    Access probe and branch on the result. The gate must become **three-way**, because collapsing the
    arms is what makes it silent:

    | Condition | Outcome | Rationale |
    |---|---|---|
    | ID/secret **absent** | `ssh_apply_skip=true` + warning (unchanged) | genuine first-bootstrap; the existing accommodation is correct |
    | Present but Access **denies** | **FAIL the job** with terminal reason `ci_ssh_access_denied` | a dead credential must never be silently deferred — silent deferral is how prod stayed dark for three days |
    | Present and Access **admits** | `ssh_apply_skip=false`, proceed | the invariant actually holds |

    Note the second row is a **new** outcome. Do not reuse the `skip` arm for it: `skip` keeps the job
    green, and a green job on a dead channel is the exact signal that failed the operator here.

4.2 The probe must distinguish **Access denial** from **origin unreachable**, because the remedies are
    opposite (re-mint the token vs. investigate the host). Use the response-body discriminator this
    session validated: an Access denial renders `You don't have permission to view this.`; an admitted
    request reaches the origin and renders something else entirely. Emit
    `ci_ssh_access_denied` vs `ci_ssh_origin_unreachable` accordingly.

4.3 **`apply-deploy-pipeline-fix.yml` has no such gate at all** — its `CF Tunnel SSH bridge` step is
    unconditional, which is why run `30650564509` destroyed both `terraform_data` resources and only
    then discovered the channel was dead. Add the same three-way gate there, positioned **before**
    `terraform plan`/`apply` — never after.

4.4 The probe must never echo the credential. Pass the ID/secret via `env:`, send them as request
    headers, and branch only on the HTTP status and response body. If any probe result reaches a
    GitHub Actions annotation (`::error::`), strip CR/LF from the interpolated value first
    (`${var//[$'\n\r']/}`) — annotations are line-oriented and a smuggled newline can forge a second
    annotation.

</details>

### Phase 4b — Restart the units that will not pick the credential up on their own (Revision R3)

`infra-config-apply.sh` runs `systemctl daemon-reload` and restarts **only** `webhook`.
`daemon-reload` does **not** cause a *running* unit to re-read its `EnvironmentFile`. Triaging the
five consumers of the delivered credential:

| Consumer | Picks it up? | Why |
|---|---|---|
| `ci-deploy.sh` | **yes, no restart needed** | it parses `/etc/default/soleur-doppler-token` itself at runtime and `export`s the keys |
| `inngest-heartbeat.service` | **yes** | it is crash-looping (`Restart=on-failure`), so it re-execs after `daemon-reload` and picks up its drop-in |
| `inngest-server.service` | **yes** | same crash-loop path (this is why #7097 added its drop-in) |
| `webhook` | **yes** | explicitly restarted by `infra-config-apply.sh` |
| **`vector.service`** | **NO** | it is alive *only* because it holds pre-revocation secrets in memory, so it never restarts and never loads its drop-in |

`vector` is the unit every post-apply assertion is read *through* — AC12 and AC13 both query Better
Stack, which vector ships. Leaving it inert means the credential lands and the telemetry that is
supposed to confirm it keeps running on borrowed, soon-to-expire state.

5.0 After Phase 2's delivery, `systemctl try-restart inngest-heartbeat.service vector.service`,
    **vector last** — restarting it blinks the very telemetry stream used to verify the outcome.
    Assert `systemctl show vector.service -p DropInPaths` contains the new drop-in path (AC16).

### Phase 5 — Prove production actually recovered

5.1 **Deploy the already-built image. This needs a named mechanism, and the obvious one is wrong.**
    `web-platform-release.yml` fires on `push: main` with `paths: apps/web-platform/**`. After
    Revision R1 this PR touches **only** `.github/workflows/**`, so **the merge does not trigger a
    release at all** — the original Phase 5.1 ("the merge is itself a release trigger") was false
    both before and after the cut, for opposite reasons. Nor does
    `apply-deploy-pipeline-fix.yml`'s `Redeploy to load applied profile` step help: it is
    conditional-by-construction and no-ops unless the container's loaded profile hash differs.
    There is **no web-platform equivalent of `deploy-inngest-image.yml`** (whose dispatch input is
    literally "Existing GHCR image tag to deploy"), so prod cannot be told to deploy the
    already-built `v0.247.1`.

    Choose one, and state the choice in the PR body:
    - **(a) Ship the recovery with `gh workflow run web-platform-release.yml -f bump_type=patch`.**
      Mints `v0.247.2` and rebuilds. Simplest; no new code. Note it *bypasses the CI gate by design*
      (documented escape hatch), so it must be dispatched only after CI is green on `main`.
    - **(b) Add `deploy-web-image.yml`**, modelled on `deploy-inngest-image.yml`, taking an existing
      tag. Strictly better long-term — an outage where the image is fine but the host cannot pull it
      is exactly the case that needs "redeploy this tag" — but it is new surface during an incident.

    **Recommended: (a) now, and file (b) as a follow-up issue.** The absence of (b) is itself a
    finding worth recording: for three days there was no way to ask production to re-pull an image
    that was sitting in the registry, already built and already signed.

5.2 Poll `https://app.soleur.ai/health` with the **Monitor** tool
    (`hr-monitor-not-run-in-background-for-polling` — never `run_in_background`) until AC14's full
    predicate holds, or a bounded deadline elapses.
5.3 Confirm via Better Stack that the host's `ci-deploy` log no longer emits
    `ZOT_GATE: … dark, pre-provisioning` and that `webhook` has stopped emitting
    `Doppler Error: Invalid Auth token` — asserted **per `ci-deploy` invocation**, not per wall-clock
    window (see AC12).
5.4 Re-run `scripts/check-cloudflare-token-drift.sh --only CI_SSH_ACCESS_TOKEN` and require
    `verdict: clean`. This closes the loop on the detector that was right all along.
5.4 `gh issue close 7095` **after** 5.2 passes — never at merge (`Ref #7095` in the PR body, not
    `Closes`, per the ops-remediation convention: the remediation runs post-merge).

---

## Execution Order (differs from phase numbering — read this before `/work`)

**Rewritten after Revision R1.** With Phase 3 cut, the `doppler_secret` dependency that originally
forced this ordering is gone, and the sequence simplifies. The existing per-apply sync step
(`Sync CF Access CI-SSH service token to Doppler`) publishes the freshly minted secret, so no new
resource has to exist first.

| Step | Action | Why here |
|---|---|---|
| 1 | **Merge the PR** (workflow + composite-action edits only) | After R1 the PR touches only `.github/**`, so it triggers **neither** `web-platform-release.yml` (paths: `apps/web-platform/**`) **nor** `apply-web-platform-infra.yml` (paths: `apps/web-platform/infra/**`). The merge is inert — deliberately, so nothing races the recovery. |
| 2 | **Phase 1** — dispatch the new `ci-ssh-token-replace` arm | Mints a fresh token; the existing sync step writes `CI_SSH_ACCESS_TOKEN_ID/_SECRET` to Doppler in the same run. This leg touches no SSH resource. |
| 3 | **Phase 1.3 / AC10** — assert Access **admits** the new credential (`verdict: clean`) | **Halt here on anything but a positive result.** A 502 or timeout is not a pass. |
| 4 | **Phase 2** — re-dispatch `apply-deploy-pipeline-fix.yml` | The channel is live; both `terraform_data` resources are absent from state, so both are created and the #7097 payload lands. |
| 5 | **Phase 4b** — `systemctl try-restart inngest-heartbeat.service vector.service` (vector last) | Otherwise the credential is on disk but inert for `vector`, the unit the verification telemetry flows through. |
| 6 | **Phase 5** — dispatch the release, then poll `/health` for AC14's full predicate | DoD. |

**Two sequencing notes that must not be lost:**

- **Step 1 being inert is a property to verify, not assume.** If `/work` finds itself editing anything
  under `apps/web-platform/**`, both auto-applies fire on merge and will race the recovery. Both
  workflows ship commit-message kill switches for exactly this — `[skip-web-platform-apply]` and
  `[skip-deploy-fix-apply]`. Use them if the surface grows.
- **Phase 1 is not reversible.** The `-replace` destroys the old `ci_ssh` secret and Cloudflare will
  not re-issue it. There is no "back out Phase 1". If Phase 2 then fails, the route forward is the
  one `apply-deploy-pipeline-fix.yml` already documents — an explicit
  `-replace=terraform_data.infra_config_handler_bootstrap` or a nonce bump in
  `push-infra-config.sh` — *"a plain `workflow_dispatch` re-run does NOT fix this"*.

---

## Downtime & Cutover

**Trigger assessment.** The infra-reboot class does **not** fire: no `hcloud_server` replace, no
`server_type`/`location` change, no volume or attachment change. The database-lock class does not fire:
no migration. The deploy/router class fires **narrowly** — the `-replace` briefly invalidates one
Cloudflare Access service token.

**Serving surfaces are untouched.** `app.soleur.ai` is served over `:443` through the tunnel and does
not authenticate against the `ci_ssh` Access application at all. It continues serving v0.244.0
uninterrupted throughout Phases 1–4, and is only *replaced* in Phase 5 by the normal container swap
the release pipeline already performs. No user-visible request is dropped by anything in this plan.

**The one surface that does go down, and for how long.** `ssh.soleur.ai` refuses the *old* credential
from the moment Cloudflare issues the new secret until the `doppler_secret` write completes — a
single apply step, seconds, entirely inside one job. `create_before_destroy = true` means the Access
policy references a live token throughout, so there is no window in which the application has *no*
token. This is a CI-only control-plane surface with no user traffic.

**Zero-downtime path, and why it is the default here.** The chosen shape *is* the zero-downtime one:
create-before-destroy on the token (never destroy-then-create), and a strictly `-target`ed apply on
leg (a) that cannot touch a serving resource. The rejected alternative — `-replace` of
`hcloud_server.web["web-1"]` — is the destroy-before-create shape, and with `cx33` stock at 0/6 it has
no create side at all. Blue-green is unavailable for the same reason: there is no second `cx33` to
green onto.

**Residual downtime accepted:** none on any user-serving surface. No maintenance window is required.

---

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** `terraform plan` for the Phase 1 `-target` set shows exactly `1 to replace`
  (`cloudflare_zero_trust_access_service_token.ci_ssh`), the dependent policy update, and the new
  `doppler_secret` creates — and **`0` `hcloud_server` creates and `0` destroys**. Paste the plan
  summary line and the per-resource action list into the PR body.
- ~~**AC2**~~ **DELETED (Revision R1)** — asserted the `doppler_secret` conversion that is now cut.
  Its inverse survives as AC17.
- **AC3** `cloudflare_zero_trust_access_service_token.deploy` is **not** in any `-replace` target in
  any workflow or runbook this PR touches. Verify by grepping the changed workflow files for
  `-replace` and enumerating every target.
- **AC4** The liveness gate exists in **both** `apply-deploy-pipeline-fix.yml` and
  `apply-web-platform-infra.yml`, and in each file it appears **before** that job's `CF Tunnel SSH
  bridge` step and before its first `terraform plan`/`apply`. Assert on **relative position**, not
  mere presence.
- **AC5** The gate is **three-way**, and the three arms are distinguishable in the job output:
  absent → `ssh_apply_skip=true` (bootstrap, job stays green); present-but-denied → **job fails**
  with terminal reason `ci_ssh_access_denied`; present-and-admitted → `ssh_apply_skip=false`.
  Assert that the denied arm **fails** rather than setting `ssh_apply_skip=true` — reusing the skip
  arm for a dead credential reintroduces the exact silence this plan exists to remove. A shell test
  drives all three fixture responses plus the `ci_ssh_origin_unreachable` discriminator.
- **AC5b** Positive evidence the gate works, captured from the merge run itself: the
  `apply-web-platform-infra.yml` run on the merge commit fails leg (b) with `ci_ssh_access_denied`
  **before** any `terraform_data` destroy appears in its log. Cite the run URL and quote the reason
  string in the PR body. (See §Execution Order step 2 — this red run is expected and is the AC.)
- ~~**AC5c**~~ **DELETED (Revision R1)** — the allow-list append is moot once Phase 3 is cut.
- **AC5d** The liveness check lives in the **shared composite action**
  `.github/actions/cf-tunnel-ssh-bridge`, not duplicated per workflow. Assert exactly one
  `check-cloudflare-token-drift.sh --only CI_SSH_ACCESS_TOKEN` invocation across
  `.github/`, and that all six bridge callers inherit it via `uses:`.
- **AC5e** `scheduled-terraform-drift.yml` creates or updates an `action-required`-labelled GitHub
  issue on verdict `dead`, carrying the detector's own remedy line. Assert the issue is created on a
  `dead` fixture — email alone is demonstrably insufficient (three fires, three days, no action).
- **AC6** No file under `apps/web-platform/infra/` other than `tunnel.tf` is modified. In particular
  `ci-deploy.sh`, `infra-config-apply.sh`, `server.tf` and the `FILE_MAP` are untouched:
  `git diff --name-only origin/main` must not list them. *(This AC is the guard against this becoming
  a third code patch.)*
- **AC7** Every CI gate that this PR's changed files trigger is run **by its own invocation**, not by
  a hand-enumerated reconstruction of its input set (`--changed --base origin/main` where the gate
  derives its inputs).
- **AC8** `## Observability`, `## Infrastructure (IaC)`, `## Encryption Posture`,
  `## User-Brand Impact` and `## Architecture Decision (ADR/C4)` sections are present and
  non-placeholder.
- **AC9** PR body uses **`Ref #7095`**, not `Closes #7095` (ops-remediation: the fix executes
  post-merge; auto-closing at merge would record a false resolution — the exact failure the 2026-07-29
  PIR already had to be corrected for).

### Post-merge (automated — no human-run step)

- **AC10** Phase 1 gating assertion passes **positively**: `GET https://ssh.soleur.ai/` with the newly
  published Doppler `CI_SSH_ACCESS_TOKEN_ID/_SECRET` is **admitted by Access** — i.e. `check-cloudflare-token-drift.sh --only CI_SSH_ACCESS_TOKEN` reports `LIVE` / `verdict: clean`.
  *Do not* assert "no longer returns the denial body": a 502, a timeout, or a DNS failure all satisfy
  that negative while the channel is still dead, and this is the plan's **halt gate** — a false green
  here authorizes every later phase on a wrong premise.
- **AC11** `apply-deploy-pipeline-fix.yml` completes green, and its `infra-config-gate.sh` content
  assert passes with every `FILE_MAP` dest reporting `ok` — including
  `/etc/default/soleur-doppler-token` and the three `10-*-doppler-token.conf` drop-ins.
  *(Note this proves bytes-on-disk, not credential-in-effect — AC16 covers that.)*
- **AC12** Better Stack, host `soleur-web-platform`: **zero** `Doppler Error: Invalid Auth token`
  events across **the next 3 `ci-deploy` invocations**, not across a wall-clock window. The events
  are ci-deploy-correlated, so any 30-minute window containing no deploy is guaranteed zero
  regardless of the fix — the original wall-clock form was vacuous, and its "55 events over 21 h"
  defence (~1.3 expected per 30 min) actually argues *against* itself.
- **AC13** Better Stack, asserted **positively** on the next `ci-deploy` run: it emits the post-#7097
  honest message (`ZOT_GATE: doppler read …` / a successful zot login), **and** emits neither
  `ZOT_GATE: … dark, pre-provisioning` nor `PRELUDE: GHCR_READ_{USER,TOKEN} not both present`.
  A pure-absence assertion is vacuously true when no `ci-deploy` runs.
- **AC14 (DoD)** `curl https://app.soleur.ai/health` returns `version` ≥ `0.247.0` **and**
  `uptime` < 900 **and** `supabase == "connected"`. The third clause is load-bearing: `health.ts`
  hardcodes `status: "ok"` unconditionally, so `status` proves nothing; `supabase` is the only field
  derived from a live query. A version-correct container that cannot reach the database passes the
  first two clauses and serves nobody. Verified by pulling the endpoint directly — **a green
  workflow run does not satisfy this AC.**
- **AC16** The delivered credential is **in effect**, not merely on disk:
  `systemctl show vector.service -p DropInPaths` contains the new drop-in path, and
  `systemctl show vector.service -p ExecMainStartTimestamp` is later than the Phase 2 apply. This is
  the assertion that distinguishes *delivered* from *active* (see Phase 4b).
- **AC17** No `doppler_secret` resource for any Cloudflare Access token was created. `terraform state
  list | grep -c 'doppler_secret.*access_token'` returns its pre-change value. This is the standing
  guard against Revision R1 being silently re-introduced.
- **AC15** `#7095` closed only after AC14; a comment recording the new #7103 ledger item
  (CI-side credential liveness) posted to #7103.

---

## Observability

```yaml
liveness_signal:
  what: "GET https://app.soleur.ai/health → {version, build_sha, uptime}"
  cadence: "on demand; Better Stack uptime monitor already polls this endpoint"
  alert_target: "Better Stack uptime monitor on /health (existing)"
  configured_in: "apps/web-platform/infra/ (betteruptime resources); endpoint served by the web container"

error_reporting:
  destination: "Sentry (web-platform project) for app errors; GitHub Actions job failure for the apply legs; Better Stack ingested journald for host-side ci-deploy/webhook lines"
  fail_loud: true  # Phase 4 converts the silent 5-minute SSH timeout into a named terminal reason

failure_modes:
  - mode: "ci_ssh Access token diverges from Terraform state again (out-of-band rotation)"
    detection: "Phase 4 pre-apply Access probe returns the denial body"
    alert_route: "GitHub Actions job fails fast with a named reason; run visible via `gh run view`"
  - mode: "Access admits but the tunnel origin (10.0.1.10:22) is unreachable"
    detection: "Phase 4 probe's origin-vs-denial discriminator selects the origin arm"
    alert_route: "distinct terminal reason in the job summary; readable without host access"
  - mode: "infra-config push delivers a stale or partial payload"
    detection: "infra-config-gate.sh per-file sha256 content assert (existing, terminal)"
    alert_route: "apply-deploy-pipeline-fix.yml job failure naming the diverging file"
  - mode: "host Doppler token dead again (the #7095 class recurs)"
    detection: "Better Stack query for `Doppler Error: Invalid Auth token` on host soleur-web-platform"
    alert_route: "covered today only by an on-demand query; the continuous probe is #7103 B2 — recorded, not closed here"
  - mode: "prod silently stale (release runs red, nobody paged)"
    detection: "none today"
    alert_route: "#7103 B3 — explicitly out of scope for this run and named as the residual risk"

logs:
  where: "Better Stack Telemetry (ClickHouse) via scripts/betterstack-query.sh, source soleur-inngest-vector-prd; GitHub Actions run logs via `gh run view`"
  retention: "~3 days hot+archive for Better Stack; 90 days for Actions logs"

discoverability_test:
  command: "curl -sS --max-time 20 https://app.soleur.ai/health && gh run list --workflow=apply-deploy-pipeline-fix.yml --limit 3 --json conclusion,createdAt && doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep ZOT_GATE --limit 20"
  expected_output: "health JSON with version >= 0.247.0 and uptime < 900; latest apply run conclusion=success; no ZOT_GATE dark lines"
```

The `discoverability_test.command` contains no remote-shell invocation. Every failure mode above is
reachable from a laptop with `curl`, `gh`, and the Better Stack query script.

---

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

Phase 2.8 reviewed. Every step is a Terraform resource or an existing GitHub Actions workflow
dispatch. No step in this plan requires a human to open a shell, a console, or a vendor dashboard.

### Terraform changes

**None (Revision R1).** No `.tf` file is edited. The only Terraform *action* is a `-replace` of an
existing resource, executed through a new dispatch arm on `apply-web-platform-infra.yml` whose
`-target` allow-list already contains the affected addresses.

- Resource re-minted: `cloudflare_zero_trust_access_service_token.ci_ssh` (existing,
  `create_before_destroy = true`). Its policy `cloudflare_zero_trust_access_policy.ci_ssh_service_token`
  updates in the same apply because it references the token's `id`.
- Sensitive value: the new `client_secret`. Source is the Cloudflare provider at mint time; sinks are
  `terraform.tfstate` (R2, encrypted at rest) and Doppler `prd_terraform` via the **existing**
  post-apply sync step. No new sink, no new exposure class.
- No new `TF_VAR_*` and no credential anyone mints by hand — the value is provider-minted
  (`hr-tf-variable-no-operator-mint-default` satisfied by construction).
- Note the detector's own remedy line names a subtlety worth carrying into `/work`:
  *"Set the live value on the 'prd' ROOT config; branch configs inherit it."* Confirm which config the
  sync step writes before assuming `prd_terraform` is the right sink for every consumer.

### Apply path

**Chosen: (c) — targeted `-replace` of a single Cloudflare API resource.** Not a host `-replace`.

- Phase 1: `terraform apply -replace=cloudflare_zero_trust_access_service_token.ci_ssh` with
  `-target` covering the token, its policy, and the four new `doppler_secret`s. Cloudflare + Doppler
  APIs only; **no SSH bridge required**.
- Phase 2: re-dispatch of the existing `apply-deploy-pipeline-fix.yml`, unchanged in mechanism.
- **Expected blast radius:** `ssh.soleur.ai` refuses the *old* credential for the interval between
  the new token's creation and the Doppler republish. `create_before_destroy` keeps that window small
  and keeps the policy referencing a live token throughout. Nothing user-facing is touched:
  `app.soleur.ai` continues serving v0.244.0 for the duration.
- **Explicitly rejected: `terraform apply -replace=hcloud_server.web["web-1"]`.** `cx33` is
  unavailable in 0/6 datacenters; `-replace` destroys before it creates; prod would be unbootable
  with no rollback. The prior plan reached the same conclusion independently
  (*"A host replace here is not a remediation, it is a second outage"*), and this session re-verified
  the stock against the live Hetzner API rather than inheriting the claim.

### Distinctness / drift safeguards

- The `-target` set must exclude every `terraform_data` with an SSH `connection` — all 16 of them —
  so Phase 1 cannot be blocked by the very channel it repairs.
- `lifecycle.ignore_changes = [value]` on the new `doppler_secret`s follows `registry_push`. This is
  a **deliberate trade**: it prevents Terraform fighting a legitimate out-of-band rotation, at the
  cost of not *detecting* one. Phase 4's pre-apply probe is what converts that blind spot into a
  fail-fast, and the ADR below must record the pairing so a future reader does not remove one and
  keep the other.
- Secret values land in `terraform.tfstate`; the R2 backend is the existing encrypted-at-rest bucket.

### Vendor-tier reality check

Cloudflare Zero Trust service tokens and Access policies are in use on the current plan (three tokens
and three applications exist today, enumerated live this session). No tier gate applies. Hetzner
`cx33` stock is a hard external constraint, verified live, and is the reason a host `-replace` is off
the table.

---

## Encryption Posture

```yaml
at_rest:
  - store: "Doppler soleur/prd_terraform (CI_SSH_ACCESS_TOKEN_*, CF_ACCESS_CLIENT_*)"
    mechanism: "Doppler-managed envelope encryption (AES-256), vendor-attested"
    evidence: "Doppler SOC 2 Type II report; values are returned only to an authenticated token, verified this session (a valid token returns 200 over TLS; a bogus token 401s)"
    defends_against: "at-rest disclosure of the Doppler datastore; unauthenticated API read"
    does_not_defend: "an attacker holding a valid Doppler service token — that token reads every secret in the config; nor exposure in GitHub Actions runner memory during an apply"
    disclosed_as: "sub-processor Doppler in the privacy/security overview"
    live_verification: "doppler secrets get <NAME> -p soleur -c prd_terraform --plain returns the value only with a valid token"
  - store: "Terraform state, R2 bucket soleur-terraform-state (key web-platform/terraform.tfstate)"
    mechanism: "Cloudflare R2 server-side encryption at rest; bucket access gated by scoped S3 credentials held only in Doppler prd_terraform"
    evidence: "backend configuration in apps/web-platform/infra/main.tf; this session read state only after injecting AWS_* from Doppler"
    defends_against: "at-rest disclosure of the bucket; anonymous or cross-account access"
    does_not_defend: "an actor holding the R2 access keys reads every secret in state in plaintext, including both Access token secrets and var.doppler_token"
    disclosed_as: "internal infrastructure; not a user-data store"
    live_verification: "terraform init + terraform output requires AWS_ACCESS_KEY_ID/SECRET from Doppler; without them the backend refuses"

in_transit:
  - connection: "GitHub Actions runner → Cloudflare API (token mint)"
    tls: "TLS 1.2+"
    cert_verification: "on"
    does_not_defend: "a compromised runner observes the minted secret in process memory"
    disclosed_as: "internal CI"
  - connection: "GitHub Actions runner → Doppler API (secret republish)"
    tls: "TLS 1.2+"
    cert_verification: "on"
    does_not_defend: "same runner-compromise caveat"
    disclosed_as: "internal CI"
  - connection: "CI cloudflared → Cloudflare edge → tunnel → web-1 10.0.1.10:22 (ssh.soleur.ai)"
    tls: "TLS to the edge; SSH transport encryption end-to-end inside the tunnel; Hetzner private network for the final hop"
    cert_verification: "on"
    does_not_defend: "an actor holding the ci_ssh Access service token reaches root shell — which is precisely the credential this plan re-mints; the tunnel authenticates the channel, not the person"
    disclosed_as: "internal infrastructure"

exception: none
```

No `plaintext-exception` and no `cert_verification: off` row, so no exception block is required.

---

## Architecture Decision (ADR/C4)

This plan makes a genuine architectural decision and therefore owns an ADR as a **deliverable, not a
follow-up** (`wg-architecture-decision-is-a-plan-deliverable`).

### ADR

**Create a new ADR.** The next free ordinal on disk is **ADR-154** (highest present: `ADR-153`).
The ordinal is **provisional** — `/ship`'s ADR-Ordinal Collision Gate re-verifies it against
`origin/main`; if it is renumbered, sweep this plan, `tasks.md` and every AC that names it in the
same edit (`grep -rn 'ADR-<old>' knowledge-base/project/{plans,specs}/`).

**Deliberate overlap with #7103 B5.** #7103's B5 already reserves "ADR-154 carrying the copy
invariant". That is the *same invariant* as item 2 below, reached from the other end of the same
credential chain. This plan therefore **claims ADR-154 and writes it to carry both** the host-side
(#7095) and CI-side (`ci_ssh`) statements of the invariant, which **removes** that bullet from
#7103 B5 rather than duplicating it. The `/ship` comment on #7103 must record the removal so B5's
remaining items are not blocked on an ADR that already exists.

The ADR states:

> **When the target server type has zero stock, `-replace` is not an available remedy, and the
> Terraform-driven config channel is the sanctioned path — but the channel's own credential must be
> probed before the apply mutates state.**

Plainly:

1. `hr-prod-host-config-change-immutable-redeploy` mandates immutable re-provision **and in the same
   breath requires verifying target-type stock first**. When stock is zero — measured, not assumed —
   the rule's precondition fails and `-replace` is not merely inadvisable but unavailable. The
   sanctioned fallback is the existing Terraform-driven `infra-config` channel (16 SSH
   `terraform_data` installers plus the `deploy_pipeline_fix` webhook push), which is version-
   controlled IaC — **not** the ad-hoc rescue edit the rule exists to forbid.
2. **A detector that fires into a channel nobody reads has not detected anything.**
   `check-cloudflare-token-drift.sh` named the dead credential, its symptom, and its remedy —
   twice daily, three times — and production stayed down for three days. The measured root cause of
   the *duration* (as distinct from the *outage*) is an **alert-response** gap, not a detection gap.
   Two corollaries: a verdict must **block** the operation it invalidates (hence the check inside the
   shared bridge action), and for a non-technical operator the delivery channel must be an
   `action-required` **issue** — the surface `operator-digest` actually harvests — not email.
3. **A destroy-then-provision apply must probe its transport before the destroy.** Run `30650564509`
   destroyed two resources and then discovered the channel was dead, leaving state emptier than
   reality. Ordering, not retry, is the fix.

~~4.~~ **Cut (Revision R1).** The draft asserted "a credential copied into a second holder must
inherit the original's re-delivery path" and "`ignore_changes = [value]` and a liveness probe are a
matched pair". Both were justifications for the `doppler_secret` conversion, and the first is
falsified by `tunnel.tf` itself: `.ci_ssh` and `.deploy` are `output`s **precisely so** they are
exempt from the stale-value trap, and `ci_ssh` already has a per-apply sync step. The second is
already documented at length in `check-cloudflare-token-drift.sh`'s header; restating it in an ADR is
duplication. #7103 B5's ADR-154 reservation therefore stands on its own — **this plan no longer
claims that ordinal for the copy invariant**, only for propositions 1–3 above.

Amend the existing ADR that records the deploy-pipeline apply path so it no longer describes the
merge-time push as "no-SSH": it is SSH-free only in its final hop and depends on a root-SSH bridge.

### C4 views

All three model files under `knowledge-base/engineering/architecture/diagrams/`
(`model.c4`, `views.c4`, `spec.c4`) must be **read in full** — not keyword-grepped — before either
editing or concluding "no impact". The enumeration this change requires:

- **External human actors:** none added. The founder/operator is already modelled.
- **External systems:** Cloudflare (Access + Tunnel), Doppler, Hetzner, GitHub Actions. Confirm each
  is present and `#external`-tagged; if the **Cloudflare Access** trust boundary is not modelled as a
  distinct element from the Cloudflare Tunnel, add it — this incident turned on the two being
  separable (the tunnel was healthy while Access denied).
- **Containers / data stores:** Terraform state (R2) and Doppler `prd_terraform` as credential
  stores. Confirm both are modelled; add the propagation edge
  `Cloudflare Access token → Doppler prd_terraform → CI runner` if absent.
- **Access relationships that change:** the CI runner's path to web-1 root shell now traverses an
  explicitly-probed Access gate. If an existing element description asserts the deploy-pipeline apply
  is "SSH-free", that description is falsified by this change and must be corrected.

Any element added must also gain its `view … include` line in `views.c4` so it renders, and
`apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` must pass — a `view include`
referencing an undefined element fails there, not at `tsc`.

A "no C4 impact" conclusion is a **reject condition** unless it cites this enumeration against all
three files.

---

## Domain Review

**Domains relevant:** Engineering (CTO), Operations (COO), Product (CPO)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The change is small, targeted and reversible; the architectural weight is in the ADR,
not the diff. The principal risk is scoping: an over-broad `-target`, or an accidental inclusion of
`cloudflare_zero_trust_access_service_token.deploy`, would remove the last working write path to a
host that cannot be replaced. AC1/AC3 exist specifically to gate that. The second risk is the plan
becoming a third code patch; AC6 gates that by asserting `ci-deploy.sh` and the `FILE_MAP` are
untouched.

### Operations (COO)

**Status:** reviewed
**Assessment:** No new vendor and no new recurring expense — the Cloudflare service tokens and Doppler
config already exist, so `wg-record-recurring-vendor-expense-before-ready` does not fire. The
operational posture materially improves: a credential class that could go stale invisibly gains an
auto-republish path and a fail-fast probe. The residual operational gap — nothing alerts on "prod is
N versions behind" — is real, is the reason this ran three days, and is explicitly assigned to
#7103 B3 rather than silently dropped.

### Product/UX Gate

Not applicable. `## Files to Edit` contains no path matching the UI-surface term list or glob
superset (`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`). The mechanical override
does not fire; the change is infrastructure only. **Tier: NONE.**

---

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200` (62 open) against every planned
file path.

- **#2197** (`refactor(billing): SubscriptionStatus type + hoist single-in…`) — matches on the literal
  substring `apps/web-platform/infra/server.tf` appearing in its body. **Acknowledge.** It is a
  billing-type refactor with no relationship to the tunnel credential path, and this PR does not
  modify `server.tf`. The scope-out remains open.

No other overlap. `tunnel.tf`, `apply-deploy-pipeline-fix.yml` and `apply-web-platform-infra.yml`
returned zero matches.

---

## Files to Edit

After Revision R1, **no Terraform file is edited at all.** The surface is three files:

- `.github/actions/cf-tunnel-ssh-bridge/action.yml` — one step invoking
  `scripts/check-cloudflare-token-drift.sh --only CI_SSH_ACCESS_TOKEN` after the forward opens and
  after the `::add-mask::` calls; fail with `ci_ssh_access_denied` on exit 1. **One edit, six
  callers** (`apply-web-platform-infra.yml`, `apply-deploy-pipeline-fix.yml`, `git-data-cutover.yml`,
  `workspaces-luks-cutover.yml` ×2, `workspaces-luks-verify.yml`) — the original plan named only two
  of the six and would have duplicated the logic into each.
- `.github/workflows/scheduled-terraform-drift.yml` — on verdict `dead`, create/update an
  `action-required` GitHub issue alongside the existing `notify-ops-email`.
- `.github/workflows/apply-web-platform-infra.yml` — add a `-replace` capability for
  `cloudflare_zero_trust_access_service_token.ci_ssh` so Phase 1 has an executable mechanism
  (see the P0 below). No other change: its existing `-target` allow-list already covers the token,
  the policy, and the ssh application, and its existing presence gate stays as-is.

**Open P0 for `/work` to resolve first:** *there is currently no workflow arm that can run an
arbitrary `terraform apply -replace=`.* `apply_target`'s enum is
`manual-rerun | inngest-host | inngest-host-replace | registry-host-replace | registry-region-migrate |
registry-luks-recut | git-data-host-replace | git-data-host-create | workspaces-luks-cutover |
workspaces-luks-recut | web-host-create | web-host-replace | entrypoint-audit` — none of them fits,
and the file notes the dispatch-input budget is near its 10-input cap. Phase 1 as originally written
was therefore an operator-local `terraform apply`, i.e. exactly the hand-run infra step this plan
claims not to contain. Add a narrow `ci-ssh-token-replace` arm (typo-guard `confirm` token, reusing
the existing non-SSH `-target` list plus `-replace`) rather than a general `-replace` input.

**Not edited, deliberately:** all of `apps/web-platform/infra/**` — including `tunnel.tf`,
`ci-deploy.sh`, `infra-config-apply.sh`, `server.tf`, `soleur-doppler-token.tmpl`, and the three
`10-*-doppler-token.conf` drop-ins. The infra code on `main` is already correct via #7097; it has
never arrived. AC6 asserts this.

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-<next>-<slug>.md` — the ADR above.
- A shell test covering the Phase 4 probe's two arms (denial vs. origin-unreachable), placed to match
  the existing infra test convention (`apps/web-platform/infra/*.test.sh`) and registered in the
  suite index so it is not an orphan suite.

**Not edited, deliberately:** `apps/web-platform/infra/ci-deploy.sh`,
`apps/web-platform/infra/infra-config-apply.sh`, `apps/web-platform/infra/server.tf`,
`apps/web-platform/infra/soleur-doppler-token.tmpl`, and the three `10-*-doppler-token.conf`
drop-ins. All are already correct on `main` via #7097. AC6 asserts this.

---

## Test Scenarios

1. **Access probe — denial arm.** Feed the probe a fixture response containing the Cloudflare Access
   denial body; assert it exits non-zero with the `access_denied` terminal reason and does not
   proceed to Terraform.
2. **Access probe — origin arm.** Feed it a fixture where Access admits but the origin errors; assert
   the distinct `origin_unreachable` reason. The two reasons must not collapse — their remedies are
   opposite.
3. **Access probe — success arm.** Admitted and origin responds; probe exits 0 and the job continues.
4. **Ordering.** Assert (by relative position in each workflow file, not by presence) that the probe
   precedes the first `terraform plan`/`apply` in its job.
5. **Target scoping.** Assert no `-replace` target in any changed workflow names
   `cloudflare_zero_trust_access_service_token.deploy`.
6. **`terraform validate`** on `apps/web-platform/infra/` after the `tunnel.tf` edit — config-phase
   schema errors fire before any plan and are invisible to `ignore_changes`.
7. **C4 render + syntax suites** (`apps/web-platform/test/c4-code-syntax.test.ts`,
   `c4-render.test.ts`) pass after the model edits.

---

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| **Immutable redeploy of web-1 (`-replace=hcloud_server.web["web-1"]`)** — the originally proposed remedy | `cx33` unavailable in **0/6** Hetzner DCs (`available=false` *and* `available_for_migration=false`, verified live). `-replace` destroys before it creates → prod unbootable, no rollback. Also does not bypass the blocker: a fresh host needs 16 SSH installers through the same dark channel. |
| **Republish the `ci_ssh` secret from Terraform state into Doppler** | Refuted by measurement: the state value is byte-identical to Doppler's, and the state value **also** 403s. Cloudflare diverged from both. |
| **Replace web-1 with a different server type (e.g. the `cpx` family web-2 uses)** | A real option for the *stock* constraint, but a capacity/architecture decision with its own migration surface, and it still requires the SSH channel to be alive first. Not a path to restoring prod today. **Defer — file a tracking issue.** |
| **A third code patch to `ci-deploy.sh` to make the GHCR fallback authenticate** | Treats the symptom at the wrong layer. The host cannot read *any* Doppler secret, so a smarter fallback would still have no credential. The code on `main` is already correct — it has never arrived. |
| **Make `infra-config-apply.sh` self-updating (add it to its own `FILE_MAP`)** | Would remove the SSH dependency for future payloads and is genuinely attractive, but it is a bootstrap-integrity change (the handler would rewrite the script currently executing) needing its own design and review. It cannot help *this* recovery, which needs the channel today. **Defer — file a tracking issue.** |
| **Hand-editing the credential on the host** | Forbidden by `hr-prod-host-config-change-immutable-redeploy` and `hr-no-ssh-fallback-in-runbooks`; the founder is non-technical; and the channel is dark for every actor, so it is not even available. |

Both deferrals must be filed as GitHub issues with re-evaluation criteria during `/ship`
(`wg-when-deferring-a-capability-create-a`).

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The `-replace` window leaves `ssh.soleur.ai` unusable if the apply fails between mint and republish | `create_before_destroy = true` is already set on the resource. The new `doppler_secret` writes in the same apply. The `deploy` token — a fully independent write path to the host — is untouched. |
| Over-broad `-target` drags an SSH-dependent resource into Phase 1, deadlocking the repair on itself | AC1 asserts the exact plan action list; the `-target` set is enumerated explicitly and excludes all 16 SSH `terraform_data` resources. |
| H6 is wrong and the re-mint does not restore access | Phase 1.3 is a **halt** gate, not a log line. `/work` stops and re-diagnoses rather than proceeding to Phase 2 on a false premise. |
| The infra-config content assert fails on a partially-stale host | The gate is terminal by design and must not be retried away. A mismatch names the diverging file; treat it as a finding, not flake. |
| Prod goes stale again with nobody paged | Genuinely **not closed** by this run. #7103 B3 owns it. Named here as the residual risk so the PR does not imply otherwise. |
| The ADR ordinal collides with a sibling PR | `/ship`'s ADR-Ordinal Collision Gate re-verifies against `origin/main`. On renumber, `grep -rn 'ADR-<old>'` across this plan, `tasks.md`, and every AC in the same edit. |

---

## Deepen-Plan Research Insights

**Deepened:** 2026-08-01. Agents: architecture-strategist, security-sentinel, spec-flow-analyzer,
git-history-analyzer, user-impact-reviewer, code-simplicity-reviewer, plus direct workflow reading.

### Attribution verification (git-history-analyzer — all 7 claims `confirms`, 0 contradictions)

| Claim | Result |
|---|---|
| PR #7097 merged 2026-07-31T17:17:05Z, merge commit `3faa95fa89dad71683530456739071a522d6a715` | confirmed |
| Runs `30650564509` (failure), `30688451196` (failure, 2026-08-01T06:48:27Z), `30649821431` (**success**, 2026-07-31T17:05:54Z), `30561787757` (success, 2026-07-30T16:30:44Z), `30468079949` ("make the CF Access service tokens rotatable", 2026-07-29T15:53:26Z) | all confirmed |
| `ci_ssh` carries `lifecycle { create_before_destroy = true }` | confirmed |
| `registry_push` has `doppler_secret` resources; `ci_ssh` + `deploy` are **only** `output`s | confirmed |
| `deploy_pipeline_fix` `depends_on` includes `infra_config_handler_bootstrap` | confirmed |
| Next free ADR ordinal on freshly-fetched `origin/main` is **ADR-154** (highest: ADR-153) | confirmed |
| All 11 cited AGENTS.md rule IDs exist as active `[id: …]` — no fabricated or retired citations | confirmed |

### The finding that reshaped Phase 4

The deepen pass read `apply-web-platform-infra.yml` directly rather than trusting the plan's own
description of it, and found that **the gate this plan proposed to add already exists and asserts the
wrong property**. `Check CI-SSH token presence (gates the SSH apply)` reads
`CI_SSH_ACCESS_TOKEN_ID` and branches on `-z`. It never reads the secret and never asks Cloudflare
anything. The gate is green **right now**, on a credential that Cloudflare rejects.

Two consequences:

1. Phase 4 changed from *"add a probe"* to *"upgrade an existing gate from presence to liveness"* —
   a materially smaller and better-targeted change, at the exact line where the failure passed through.
2. The gate's existing skip semantics (`ssh_apply_skip=true`, job stays green) are a *first-bootstrap*
   accommodation and are the **wrong** response to a dead credential. Hence the three-way split in
   Phase 4.1: silent deferral is how production stayed dark for three days.

This is the `proxy-vs-invariant` class the plan skill warns about — *config-secret presence vs value* —
caught here only because the workflow was read rather than paraphrased.

### The second finding: the seam already exists

`apply-web-platform-infra.yml` is already split into two applies (#4844): leg (a) non-SSH from a saved
`tfplan`, leg (b) SSH-provisioned resources behind the tunnel bridge. Leg (a)'s `-target=` allow-list
**already contains** `cloudflare_zero_trust_access_service_token.ci_ssh` and
`cloudflare_zero_trust_access_policy.ci_ssh_service_token`. Phase 1 therefore needs no new workflow
plumbing — it rides leg (a), which by construction touches no SSH resource. What it *does* need is
Phase 3.4: the four new `doppler_secret` addresses must be appended to that allow-list, or they are
never applied on merge and the whole auto-republish ships as a no-op.

### Revisions applied after review (R1–R5)

Five agents reviewed the draft. Three independently converged on the same P0, and it was the plan's
own centrepiece. The draft's diagnosis of *why prod was down* was correct and fully measured; its
diagnosis of *why nobody noticed* was wrong, and the remedy built on that wrong diagnosis would have
caused a second, worse outage.

| # | Revision | Trigger |
|---|---|---|
| **R1** | **Phase 3 cut in full.** The `output → doppler_secret` conversion is a regression, and its `.deploy` half would have published a **dead** secret over the **live** one, leaving zero write paths to an unreplaceable host. `ignore_changes = [value]` does not suppress a create. | architecture P0-1/P0-2, security C1/C2/C3, user-impact F1/F2/F3, simplicity Finding 2 |
| **R2** | **Phase 4 reframed** from "build a probe" to "make the existing verdict block and reach a human". `check-cloudflare-token-drift.sh` already detected this exact credential and emailed ops three times over three days. | architecture P0-3, simplicity Finding 0, user-impact F4 — then confirmed by pulling the run log |
| **R3** | **Phase 4b added.** `vector.service` never restarts, so the delivered credential would land **inert** for the one unit that ships the telemetry AC12/AC13 read through. | spec-flow P1-7 |
| **R4** | **Phase 5.1 rewritten.** No mechanism existed to deploy the already-built image; the merge no longer triggers a release at all after R1. | spec-flow P0-4 |
| **R5** | **ACs corrected:** AC10 negative → positive (a 502 satisfied the old form, and it is the halt gate); AC12/AC13 wall-clock → per-invocation (vacuous when no deploy runs); AC14 gains `supabase == "connected"` (`status:"ok"` is hardcoded); AC2/AC5c deleted; AC16/AC17/AC5d/AC5e added. | spec-flow P1-8, user-impact F6, architecture P2-11 |

**Claims the draft made that review falsified — recorded so they are not re-proposed:**

1. *"`ci_ssh` has no Doppler propagation path."* It has one, on every apply, and it is stronger than
   the proposed replacement.
2. *"This is the structural hole."* There was no structural hole. There was an **alert-response** gap.
3. *"The bridge starts cloudflared unconditionally."* True of `apply-deploy-pipeline-fix.yml`, false
   of `apply-web-platform-infra.yml`, which gates it on `ssh_apply_skip`.
4. *"The `-target` set is the load-bearing detail of this entire plan."* It already ships on `main`
   and has been applying for months.

**One draft hypothesis review raised that my own measurement refutes:** service-token *expiry* as an
alternative to out-of-band rotation. `github-actions-ci-ssh` shows
`expires_at = 2027-05-20T17:09:51Z` — ten months out. Expiry is ruled out; the #7065 commit message
attributes the rotation to 2026-07-28 incident response.

### The third finding: the phases do not execute in their authored order

Phase 1's auto-republish depends on Phase 3's resources being applied first. Left unstated, `/work`
would run Phase 1 first and mint a secret with nowhere to land. The `## Execution Order` section above
was added to make the real sequence explicit, including the counter-intuitive step 2 (an *expected*
red run that is itself the evidence Phase 4 works).

---

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6.** It is filled above.
- **The apply that fixes the channel must not depend on the channel.** Phase 1's `-target` set is the
  load-bearing detail of this entire plan. Verify it by reading the plan output, not by trusting the
  target list as written.
- **`terraform plan` cannot see this class of drift.** Cloudflare never returns `client_secret` after
  creation, so a clean plan is fully compatible with a credential that no longer authenticates. Never
  read a green plan as evidence that a write-once credential is live — probe it.
- **A citation of a past green run is not a probe of the present channel.** This is the precise
  mechanism by which #7097 failed: R34/Phase 0.2b asked for the last green run of
  `apply-deploy-pipeline-fix.yml` (2026-07-30T16:30:44Z) and the channel died the following day. Any
  precondition phrased as "confirm the last successful run" should be rewritten as "assert the thing
  works right now".
- **`websocket: bad handshake` in the cloudflared log is not by itself a failure signal.** Run
  `30649821431` **succeeded** while logging it twice at bridge startup. What discriminates is whether
  an SSH connection is subsequently *attempted* and reset. Do not build an alert on the string alone.
- **`hr-menu-option-ack-not-prod-write-auth`:** every destructive prod write in Phase 1 and Phase 2
  requires showing the exact command and obtaining explicit per-command go-ahead before running it.
  Plan approval is not write approval, and approval of Phase 1 does not extend to Phase 2.
- **Use `Ref #7095`, never `Closes #7095`.** The remediation executes post-merge; `Closes` would
  auto-close at merge and record a resolution that has not happened — the same false-resolved state
  the 2026-07-29 PIR had to be corrected for.
- **Do not delete or "clean up" `terraform_data.deploy_pipeline_fix` / `infra_config_handler_bootstrap`
  from state.** They are already absent following run `30650564509`; the host still carries the old
  handler. State and reality disagree, and the recovery apply is what reconciles them.
