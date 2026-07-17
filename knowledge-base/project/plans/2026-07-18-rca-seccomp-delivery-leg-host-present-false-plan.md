---
title: "RCA: seccomp delivery-leg — why host_present=false before the #6512 item-4 redeploy (2026-07-16)"
date: 2026-07-18
issue: 6629
type: rca
classification: infra-diagnosis-plus-hardening
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: ADR-079 (amend — seccomp delivery contract)
---

# RCA: seccomp delivery-leg — why `host_present=false` on web-1 before the #6512 item-4 redeploy

## Overview

#6512 fixed the **reload leg** (a same-version item-4 seccomp redeploy dying
`image_pull_failed` when both registries failed) and made an unenforced profile a
standing alarm. It explicitly deferred the **delivery leg**: *why was the profile
FILE `/etc/docker/seccomp-profiles/soleur-bwrap.json` absent from web-1
(`seccomp_profile_host_present=false`) at 2026-07-16T21:03Z, BEFORE the item-4
redeploy (apply run `29450562340`)?*

This RCA answers that question by self-pulling the diagnosis (NO SSH —
`hr-no-dashboard-eyeball-pull-data-yourself`), then — if the root cause is an
in-repo provisioner/ordering defect — ships the fix, and finally makes the
**build-gate determination** the sibling deferred-enforcement tracker (#6628)
waits on: *is `host_present=false` reachable OUTSIDE an item-4 run?*

### In-repo evidence already gathered (grounds the hypotheses, does NOT close them)

All line numbers are `origin/main` at plan time (the issue cited `server.tf:1024-1056`;
the block is actually at **`apps/web-platform/infra/server.tf:1057-1114`** — drift noted).

1. **The seccomp profile has exactly ONE in-repo writer and NO boot-time
   delivery.** `terraform_data.docker_seccomp_config`
   (`server.tf:1057`) is the only resource that writes
   `/etc/docker/seccomp-profiles/soleur-bwrap.json`. A full scan of every
   `cloud-init*.yml` (`apps/web-platform/infra/cloud-init.yml` and siblings)
   returns **zero** `seccomp` / `soleur-bwrap.json` / `seccomp-profiles` hits.
   By contrast, `cloud-init.yml:441-444` bakes `/etc/docker/daemon.json` at
   first boot ("This is the ONLY daemon.json write for FRESH hosts; running
   hosts get it [via the SSH provisioner]"), and journald / SSH-hardening
   drop-ins are likewise `write_files`-baked. **Every sibling host-config
   follows a dual-delivery pattern (cloud-init at boot + SSH provisioner for
   running hosts); the seccomp profile breaks it — a fresh host gets NOTHING at
   boot.** This is the candidate in-repo defect.

2. **The file lives on the root disk, not `/mnt/data`.** `/etc/docker/...` is on
   the VM root filesystem. A reboot does NOT wipe it; only a **VM replacement**
   (new root disk) does. Therefore `host_present=false` on a host that was
   previously `true` implies **web-1's VM was (re)created and the provisioner
   has not re-run against the new instance** — OR the file was deleted — OR it
   was never delivered on that instance.

3. **`host_present` is a genuine host-side file check.**
   `apps/web-platform/infra/cat-deploy-state.sh:330` reads
   `SECCOMP_PROFILE_HOST_PATH` (default the real host path) and reports
   `seccomp_profile_host_present` + the raw `sha256sum` of the on-host file
   (`:367-368`), tolerating absence (`present=false, host_sha256=""`). The
   deploy-status hook is served host-side, so `false` means genuine absence on
   the host root fs — this **weakens** (does not yet eliminate) the issue's
   "provisioner wrote to a path the container's mount namespace does not see"
   hypothesis. /work MUST confirm the probe runs host-side, not in a container.

4. **web-1 is EXCLUDED from the merge-triggered auto-apply.**
   `.github/workflows/apply-web-platform-infra.yml` (header `:16-35`) splits the
   apply into (a) the main saved-`tfplan` apply over ~80 non-SSH resources —
   whose `-target=` list (`:298-393`) contains **no** `terraform_data.docker_seccomp_config`
   and **no** `hcloud_server.web` — and (b) a SEPARATE token-gated SSH apply,
   behind the CF-Tunnel SSH bridge, that reaches the 8 `terraform_data.*`
   siblings including `docker_seccomp_config`. `hcloud_server.web` is
   "managed by initial-apply + drift detector, not per-PR" (`:29-31`), and a
   `+ create` of a host **HALTs** the auto-apply (`host_creates` tripwire,
   `:421-460`). **The auto-apply never replaces web-1 and never births a host.**

5. **The drift detector is plan-only.** `.github/workflows/scheduled-terraform-drift.yml`
   runs `terraform plan -detailed-exitcode` (`:100`) and emails/files on exit 2
   — it **never applies**. So web-1 replacement is **operator-local /
   initial-apply only**; there is **no `web-1`-`-replace` `workflow_dispatch`
   option** (only web-2 / inngest / registry / git-data exist, `:96-105`).

6. **The `server_id` fold-in guards the hash-only trap only when the provisioner
   is IN an apply's scope.** `docker_seccomp_config.triggers_replace` is keyed on
   `{seccomp_profile = sha256(file(...)), server_id = hcloud_server.web["web-1"].id}`
   (`:1067-1070`), added precisely to avoid the fresh-host trap (comment
   `:1058-1066`, citing the 2026-06-04 #4927/#4928 cron silent-producer
   incident). But `-target` pruning defeats it: a host-replacement apply that
   does **not** co-target `docker_seccomp_config` leaves the new host with an
   absent file and a **stale recorded `server_id`** in state, until a later
   apply reconciles it. This is the SAME class as the ADR-114 `-target`-transitivity
   note in the same workflow (`:421-434`): a targeted host comes up
   partially-configured because a dependent resource was reachable but a
   sibling was not.

7. **apparmor is even more exposed.** `terraform_data.apparmor_bwrap_profile`
   (`server.tf:1120-1121`) has a **hash-only** `triggers_replace = sha256(file(...))`
   — no `server_id` fold-in at all, and no cloud-init counterpart. It carries
   the exact fresh-host trap `docker_seccomp_config`'s comment warns about. The
   AppArmor layer of the SAME sandbox boundary is silently exposed on every
   web-1 replacement. In scope as a sibling finding.

### Working thesis (a HYPOTHESIS to confirm by pull, NOT a verdict)

`host_present=false` at 21:03 on 2026-07-16 is most consistent with: **web-1's
VM was (re)created and the `docker_seccomp_config` SSH provisioner had not
(yet / at all) run against the new instance before item-4 observed the gap** —
made reachable by the missing boot-time delivery (finding 1) and, on a scoped
host-replacement path, by `-target` pruning defeating the `server_id` guard
(finding 6). Because item-4 only READS `host_present`, the false state is a
property of the HOST set at VM-creation time and is **independent of item-4** —
which, if confirmed, fires the #6628 build trigger.

**This thesis is NOT confirmed.** Per the #6536 sharp edge
(`2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md`):
a hypothesis may not read CONFIRMED/REFUTED while its deciding datum is
unpulled. The deciding datum here — *was web-1 actually replaced in the window,
by which apply, and did that apply's executed plan include `docker_seccomp_config`?*
— lives in Better Stack boot markers, `/hooks/deploy-status` history, the R2
terraform state, and the apply/drift run logs. Phase 1 pulls them; no fix or
verdict precedes Phase 1.

## Premise Validation

- **#6512 / PR #6622** (`gh issue view 6512`, `gh pr view 6622`): the reload-leg
  fix + alarm merged 2026-07-18 (`68c2ff458`). The delivery-leg was **explicitly
  deferred** by the issue itself ("filed rather than fixed inline") — premise
  HOLDS; this is the sanctioned follow-up, not a re-scope.
- **#6628** (sibling): "standing 6h seccomp-enforcement drift watchdog — build
  when a non-merge unenforcement path is observed." This RCA's non-merge-path
  determination is its explicit build trigger. Premise HOLDS.
- **`server.tf:1024-1056` (cited)**: STALE line numbers — the block is at
  `1057-1114` on `origin/main`. Corrected throughout (`cq-cite-content-anchor-not-line-number`).
- **ADR-079** exists (`ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md`)
  and owns the item-4 "applied ≠ loaded" closer. This RCA's fix AMENDS its
  delivery contract. Premise HOLDS.
- **run `29450562340`**: cited as the apply run for the item-4 redeploy on
  2026-07-16T21:03Z. NOT verified live at plan time (needs `gh run view`) — Phase 1 task.
- No proposed mechanism sits in a rejected-ADR-alternatives table (checked
  ADR-079 + the fresh-host-trap hard rule). Boot-time delivery is a gap, not a
  rejected alternative.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue/prior) | Reality on origin/main | Plan response |
| --- | --- | --- |
| Provisioner at `server.tf:1024-1056` | Block is `1057-1114`; apparmor `1120-1143` | Use corrected anchors; cite content not line. |
| `triggers_replace` "guards the fresh-host trap" | Guards it ONLY when provisioner is in-apply-scope; `-target` pruning + no boot delivery defeat it | Core hypothesis; fix closes the boot-delivery gap. |
| Candidate: "container's mount namespace does not see the path" | `host_present` is a host-side `test -f` in `cat-deploy-state.sh` | Downgrade this hypothesis; still verify the probe context in Phase 1. |
| Candidate: "apply reported success while file provisioner skipped on replaced VM" | Structurally reachable via `-target` pruning / SSH-leg failure; state records stale `server_id` | Primary hypothesis; Phase 1 checks state `server_id` vs live host id. |
| web-1 replaced by drift detector | Drift detector is plan-only; web-1 replace is operator-local only | Phase 1 identifies the actual operator-local/initial apply event. |

## Institutional Learnings (corroborating; NOT verdicts)

- `knowledge-base/project/learnings/2026-06-04-cron-silence-was-bwrap-userns-drift-not-turn-budget.md`
  — the #4927/#4928 precedent this exact block's `server_id` fold-in was added
  to prevent: hash-only `terraform_data` triggers silently skip on host
  replacement; assert reboot-critical kernel state via an enabled systemd unit,
  not a one-shot `sysctl -w`. **Same failure family — the seccomp file simply
  lacks the boot-delivery half the userns sysctl also needs.**
- `knowledge-base/project/learnings/best-practices/2026-05-20-hr-fresh-host-iac.md`
  — the canonical `hr-fresh-host-provisioning-reachable-from-terraform-apply`:
  any install done by a provisioner MUST ALSO be in `cloud-init.yml`. Directly
  licenses the Phase-2 primary fix; the seccomp write is the one that violates it.
- `knowledge-base/project/learnings/2026-06-10-terraform-remote-exec-gating-and-container-scoped-egress-allowlist.md`
  — Terraform joins `inline` into ONE script with NO implicit errexit; a failed
  `mkdir` followed by a passing later line marks the provisioner GREEN. The
  seccomp block DOES lead with `set -e` (`server.tf:1082,1094`) — but the `file`
  (scp) provisioner sits between two remote-execs; Phase 1/H3 must confirm the
  SSH-leg job actually surfaced any scp failure (a `file` provisioner failure IS
  gating, but a bridge disconnect mid-transfer may present as a later-step error).
- `knowledge-base/project/learnings/2026-04-06-terraform-data-connection-block-no-auto-replace.md`
  — `connection {}` changes never trigger `terraform_data` replacement; only
  `triggers_replace` does. Rules out a connection-block edit as the cause.
- `knowledge-base/project/learnings/2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md`
  + `knowledge-base/project/learnings/2026-06-10-betterstack-quota-diagnosis-host-metrics-dominate-generic-http-sink.md`
  — probe-first + pull-don't-eyeball. **Correction to a research suggestion:** the
  probe path is `/hooks/deploy-status` history + Better Stack API + R2 state —
  NOT `ssh web-1 ls` (violates NO-SSH + `hr-no-dashboard-eyeball`).

## User-Brand Impact

**If this lands broken, the user experiences:** a tenant agent whose Bash
sandbox runs with the **seccomp syscall filter unenforced** — the container
layer of the tenant-agent isolation boundary silently absent — after any web-1
VM replacement, invisibly (prod stays HTTP 307-healthy, exactly the #6512
invisible-gate shape).

**If this leaks, the user's workflow/data is exposed via:** a sandbox escape
surface widened by the missing seccomp filter (combined with the equally-exposed
AppArmor layer, finding 7) on a shared multi-tenant host — one tenant's agent
reaching another tenant's workspace under `/mnt/data/workspaces/`.

**Brand-survival threshold:** single-user incident. `requires_cpo_signoff: true`
— CPO sign-off required at plan time before `/work`; `user-impact-reviewer` runs
at review time (per `review/SKILL.md` conditional-agent block).

## Hypotheses

The SSH-provisioner delivery path (`provisioner "file"` scp + `remote-exec` over
the CF-Tunnel SSH bridge) makes SSH a hard apply-time dependency, so the
L3→L7 network-outage checklist (`hr-ssh-diagnosis-verify-firewall`) applies to
any "the provisioner failed to run" branch. Unverified layers are listed FIRST,
in L3→L7 order, before the service-specific hypotheses.

**H-net (L3 firewall).** The SSH apply leg reaches web-1 over the CF-Tunnel SSH
bridge (`.github/actions/cf-tunnel-ssh-bridge`), NOT a direct `:22` dial (the
GH-runner egress IP is not in `var.admin_ips`). Verification: inspect the
`29450562340`-adjacent `apply-web-platform-infra` run logs for the SSH-leg job —
did the bridge connect, or fail `connection reset` / `handshake` / `timeout`?
[unverified — Phase 1]

**H-net (L3 DNS/routing).** `deploy.soleur.ai` / `ssh.soleur.ai` tunnel ingress
was pinned to web-1 only at `5c43c062a` (#6595, 2026-07-17) — BEFORE that the
management plane was "a coin flip" across web-1/web-2. If the incident window
predates that pin, an SSH leg could have landed on web-2. Verification: correlate
the incident timestamp against the #6595 merge + the tunnel ingress config.
[unverified — Phase 1]

**H-net (L7 SSH service).** Was there an `sshd`/bridge-side rejection in the
window? Absence of any SSH-leg log entry for the run is itself strong evidence
the provisioner never executed. [unverified — Phase 1]

**H1 — Missing boot-time delivery on a replaced host (PRIMARY).** web-1's VM was
(re)created (operator-local/initial apply) and, because there is no cloud-init
seccomp write (finding 1), the new root disk had no profile file until the
`docker_seccomp_config` provisioner next ran. If the replacing apply did not
co-target the provisioner, or ran it before the file landed, `host_present=false`
persists across the window. Discriminator: Better Stack SOLEUR_* boot marker for
a web-1 (re)boot in the window + R2 state `docker_seccomp_config.triggers.server_id`
vs live `hcloud_server.web["web-1"].id`. [unverified — Phase 1]

**H2 — `-target` pruning defeated the `server_id` guard.** A scoped
host-replacement apply reached web-1 but pruned `docker_seccomp_config`, leaving
a stale recorded `server_id` and an absent file (finding 6, ADR-114 class).
Discriminator: the executed `-target` set of the replacing apply. [unverified — Phase 1]

**H3 — SSH apply leg silently failed / was skipped.** The token-gated SSH leg
errored (bridge/token/`connection reset`) while the main apply reported success,
so `docker_seccomp_config` never delivered (see H-net). Discriminator: SSH-leg
job status in the relevant run(s). [unverified — Phase 1]

**H4 — File deleted / never delivered (no replacement).** web-1 was NOT replaced;
the file was removed or never existed on that instance. Discriminator: absence of
any boot marker in the window (⟹ not a replacement) + host uptime. [unverified — Phase 1]

**H5 — Namespace-visibility artifact (DOWNGRADED).** The probe read a path the
running state doesn't reflect. Weakened by finding 3 (host-side `test -f`), but
Phase 1 confirms the probe's execution context before eliminating. [unverified — Phase 1]

## Implementation Phases

> **PROBE-FIRST (load-bearing, ships ALONE).** Phase 1 is the RCA and is
> committed as its own artifact BEFORE any fix. No hypothesis reads
> CONFIRMED/REFUTED until its discriminator datum is pulled (#6536 sharp edge).
> If Phase 1 REFUTES H1/H2 (root cause is not an in-repo provisioner/ordering
> defect), Phases 2–3 change shape accordingly and the fix may be a no-op.

### Phase 1 — Self-pull the diagnosis (NO SSH) → write the RCA verdict

All pulls use `hr-no-dashboard-eyeball-pull-data-yourself` mechanisms — read the
data, apply a deterministic verdict rule, cite the layer.

1.1. **Confirm the run + baseline.** `gh run view 29450562340 --log` (and its
job) → confirm it is the ADR-079 item-4 redeploy, capture the baseline line
(`host_present=false host_sha256='<none>'`) and its timestamp. Verdict rule:
baseline `host_present=false` present pre-redeploy ⟹ absence is real, not a
redeploy side-effect.

1.2. **`/hooks/deploy-status` history.** Read the deploy-status history around
2026-07-16T21:03Z (auth: HMAC + CF-Access via Doppler `prd_terraform`, read-only,
per the automation-feasibility catalog). Establish the `host_present` true→false
transition timestamp and the later false→true self-resolution. Verdict rule: the
true→false edge timestamp bounds the causal event; correlate with 1.3/1.4.
NOTE: use HISTORICAL data only — a fresh probe cannot observe the pre-fix state
(the mutation-payload-observability trap).

1.3. **Better Stack SOLEUR_* boot markers.** Query the Better Stack logs API
(token read-only from Doppler) for web-1 SOLEUR_* boot/terminal markers in
[last-known-true … 21:03]. Verdict rule: a boot marker in-window ⟹ web-1 was
(re)booted/replaced (H1/H2 live); NO marker ⟹ H4 (deletion/never-delivered) rises.

1.4. **Apply / drift run logs.** `gh run list --workflow=apply-web-platform-infra.yml`
(+ `apply-deploy-pipeline-fix.yml`, `scheduled-terraform-drift.yml`) across
2026-07-14…16. For each candidate apply: did it replace web-1? What was its
executed `-target` set? Did the SSH leg (docker_seccomp_config) run and succeed?
Verdict rule: an apply that replaced/targeted web-1 without co-running the SSH
leg ⟹ H2/H3 confirmed.

1.5. **R2 terraform state read (read-only).** Read
`apps/web-platform/infra/terraform.tfstate` from the R2 backend (AWS creds +
`--name-transformer tf-var` per the canonical triplet;
`terraform state show terraform_data.docker_seccomp_config`). Compare its
recorded `triggers.server_id` against live `hcloud_server.web["web-1"].id`.
Verdict rule: mismatch ⟹ the provisioner did not reconcile on the current host
(fresh-host trap realized) — decisive for H1/H2.

1.6. **Probe-context confirmation (eliminate H5).** Read `cat-deploy-state.sh`
seccomp block (`:326-368`) + how the deploy-status hook invokes it; confirm the
`test -f` runs against the host root fs, not a container namespace.

1.7. **Write the RCA.** Author
`knowledge-base/engineering/operations/post-mortems/2026-07-18-seccomp-delivery-leg-host-present-false-rca-6629.md`
with: the confirmed timeline, per-hypothesis verdict (CONFIRMED/REFUTED/UNKNOWN
with the discriminator datum cited for each), the root cause, and the explicit
**non-merge-path determination** (feeds #6628). If a discriminator datum is
genuinely unavailable (e.g., Better Stack retention lapsed), the verdict for that
hypothesis is **UNKNOWN** — never a reasoned CONFIRMED/REFUTED.

**Phase 1 commits alone.** If H1/H2 (in-repo defect) are REFUTED, STOP and
re-scope Phases 2–3 (the "fix" may reduce to documenting the operator apply
discipline). Do not carry a fix that the RCA did not license.

### Phase 2 — Fix (ONLY if Phase 1 confirms an in-repo provisioner/ordering defect)

2.1. **Bake the seccomp profile into cloud-init `write_files` (primary fix).**
Add `/etc/docker/seccomp-profiles/soleur-bwrap.json` to `cloud-init.yml`
`write_files:` (mirroring the `daemon.json` boot-write at `:441-444`), plus the
`bwrap-userns-sysctl.service` unit + `/etc/sysctl.d/99-bwrap-userns.conf` the
`docker_seccomp_config` provisioner installs (`server.tf:1092-1112`), so a FRESH
host has the file + sysctl at boot — closing the no-boot-delivery gap
structurally, independent of `-target` scope, SSH-leg health, or apply ordering.
Keep the SSH provisioner as the running-host updater (the dual-delivery pattern
every sibling already follows). Reconcile content drift via `file()` so the
cloud-init copy and `seccomp-bwrap.json` stay in lockstep (templatefile or a
build-time render + a drift-guard test — mirror how sibling configs avoid a
hand-copied divergence).

2.2. **Add `server_id` to `apparmor_bwrap_profile.triggers_replace` (finding 7).**
Fold `hcloud_server.web["web-1"].id` into the hash-only trigger so the AppArmor
layer re-provisions on host replacement like seccomp. Also bake the AppArmor
profile + `apparmor_parser -r` into cloud-init if Phase 1 shows the same
boot-gap applies (it does — no cloud-init apparmor write exists either).

2.3. **(Conditional on H2/H3) Co-delivery / SSH-leg observability.** If Phase 1
shows a host-replacement path pruned the provisioner OR the SSH leg failed
silently, add the missing signal: the SSH-apply leg must FAIL LOUD (non-zero,
Sentry mirror) when `docker_seccomp_config`/`apparmor_bwrap_profile` do not
apply, and any operator host-replacement runbook must co-target them (or the
cloud-init bake in 2.1 makes co-targeting unnecessary — prefer the structural fix).

### Phase 3 — Non-merge-path determination (the #6628 build-gate)

3.1. From the Phase-1 verdict, state explicitly in the RCA and on #6629/#6628:
**IS `host_present=false` reachable outside an item-4 run?** Expected (pending
confirmation): YES — it is a host property set at VM-creation, independent of
item-4, which only reads it. 3.2. If YES, comment on #6628 that the build trigger
has fired (a non-merge unenforcement path is observed) and the standing 6h
watchdog should be built. If NO (Phase 1 shows the only path is an item-4 run),
record that #6628 stays deferred with the confirmed reason.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] RCA post-mortem file exists at the Phase-1.7 path, non-empty, with a
  per-hypothesis verdict table each citing its discriminator datum (grep: every
  hypothesis row has one of `CONFIRMED|REFUTED|UNKNOWN` AND a cited artifact).
- [ ] No hypothesis reads `CONFIRMED`/`REFUTED` whose discriminator datum the RCA
  text also says was unavailable (the #6536 self-contradiction check).
- [ ] The RCA states the non-merge-path determination as an explicit YES/NO with
  the confirming datum.
- [ ] IF a fix ships (Phase 2): `apps/web-platform/infra/cloud-init.yml`
  `write_files:` contains a `/etc/docker/seccomp-profiles/soleur-bwrap.json`
  entry (grep) AND a drift-guard test asserts the baked content matches
  `seccomp-bwrap.json` byte-for-byte.
- [ ] IF a fix ships: `apparmor_bwrap_profile.triggers_replace` includes
  `server_id` (grep `server.tf`).
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean (if any TS
  touched); infra shell tests pass (`cat-deploy-state.test.sh` and any new
  drift-guard test).
- [ ] `terraform validate` (or the CI infra-config gate) passes on the cloud-init
  + server.tf changes.
- [ ] PR body uses `Ref #6629` (NOT `Closes` — see Sharp Edges: post-merge
  operator apply closes it).

### Post-merge (operator / automated)

- [ ] Merge to `apps/web-platform/infra/**` fires `apply-web-platform-infra.yml`;
  the cloud-init change takes effect on the NEXT web-1 replacement only (it does
  not retro-fix the running host — the running host already self-resolved to
  `host_present=true` per the #6512 postmortem). Automation: the merge IS the
  apply; no separate operator step.
- [ ] `gh issue close 6629` after the RCA + fix land. Comment on #6628 with the
  build-gate determination.

## Infrastructure (IaC)

### Terraform / cloud-init changes
- `apps/web-platform/infra/cloud-init.yml` — add seccomp profile (+ userns
  sysctl unit + drop-in) to `write_files:`/`runcmd:` (fresh-host delivery).
- `apps/web-platform/infra/server.tf` — `apparmor_bwrap_profile.triggers_replace`
  gains `server_id`; optionally bake apparmor into cloud-init too.
- Providers/pins: unchanged (hcloud provider already in root). No new `TF_VAR_*`.

### Apply path
Cloud-init-only for the boot-delivery half (takes effect on next web-1 (re)create).
The `server_id` trigger change re-fires `apparmor_bwrap_profile` on the next apply
that reaches web-1 (SSH leg). No `-replace` of web-1 is prescribed by this PR
(operator-local + gated). Blast radius: zero on the running host (cloud-init
`write_files` only executes at boot; the trigger change is a no-op until the next
host replacement or SSH-leg apply).

### Distinctness / drift safeguards
`dev != prd`: N/A (single prod web host). The cloud-init seccomp copy MUST stay
byte-identical to `seccomp-bwrap.json` — enforce via `file()`/templatefile render
+ a drift-guard test (do NOT hand-copy JSON). State-storage: no new secrets land
in `terraform.tfstate`.

### Vendor-tier reality check
N/A — no new vendor resource; hcloud + cloud-init only.

## Observability

```yaml
liveness_signal:
  what: seccomp_profile_host_present + seccomp_profile_host_sha256 via /hooks/deploy-status
  cadence: every deploy + the #6628 (to-build) 6h watchdog
  alert_target: ci/seccomp-unenforced GitHub issue + seccomp_remediation_failed Sentry (scripts/seccomp-unenforced-alert.sh, shipped by #6512)
  configured_in: apps/web-platform/infra/cat-deploy-state.sh + scripts/seccomp-unenforced-alert.sh
error_reporting:
  destination: Sentry (seccomp_remediation_failed) + a ci/seccomp-unenforced issue
  fail_loud: true — Phase 2.3 makes the SSH-apply leg fail non-zero + Sentry-mirror when docker_seccomp_config/apparmor_bwrap_profile do not apply
failure_modes:
  - mode: fresh host boots without seccomp file
    detection: /hooks/deploy-status host_present=false on the new host (host-side test -f)
    alert_route: ci/seccomp-unenforced issue (post-#6512) + the #6628 watchdog once built
  - mode: SSH-apply leg silently skips/fails the provisioner
    detection: apply-web-platform-infra SSH-leg job non-zero + Sentry (Phase 2.3)
    alert_route: red CI job → Sentry mirror (fail-loud, not a bare red job — the #6454 inert-gate lesson)
logs:
  where: Better Stack SOLEUR_* boot markers (web-1) + gh run logs (apply/drift)
  retention: Better Stack plan retention — Phase 1 must pull within window (historical-only)
discoverability_test:
  command: "curl -s -H '<CF-Access + HMAC>' https://deploy.soleur.ai/hooks/deploy-status | jq '.seccomp_profile_host_present'"
  expected_output: "true on an enforcing host; false is the alarm condition (NO ssh)"
```

## Architecture Decision (ADR/C4)

### ADR
**Amend ADR-079** (`ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md`):
add to its Decision that the seccomp (and AppArmor) profile delivery contract is
**dual-delivery — cloud-init at first boot AND the SSH provisioner for running
hosts** — so a fresh/replaced host is never a window of unenforcement. Record the
`server_id`-in-triggers requirement for both `terraform_data` resources in the
Alternatives/Consequences. (New-ADR ordinal ADR-122 is available if reviewers
prefer a standalone "boot-time delivery for security controls" ADR over an
amendment; default is amend.)

### C4 views
Reviewed all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`)
for external-actor / external-system / access-relationship impact: this change
alters the DELIVERY MECHANISM of an existing host-internal security control
(seccomp profile file on web-1) — it adds no external actor, no external system,
no new container/data-store, and no actor↔surface access-relationship. The
tenant-agent sandbox boundary already modeled is unchanged in shape; only its
delivery robustness improves. **No C4 impact** — verified against the enumerated
categories, not a keyword grep. (/work MUST re-open the three `.c4` files and
confirm no seccomp/sandbox element description is falsified before finalizing.)

### Sequencing
The RCA (Phase 1) ships first, alone. The delivery-contract amendment is authored
with the Phase 2 fix; if Phase 1 refutes the in-repo defect, the ADR amendment is
dropped.

## Domain Review

**Domains relevant:** Engineering (CTO). Infrastructure/security-control delivery
change — no product-UI, marketing, legal-regulated-data, finance, sales, support,
or ops-vendor surface. Product/UX Gate: NONE (no `components/**`, `app/**/page.tsx`,
or UI-surface file in Files to Edit — pure infra/docs). GDPR gate (2.7): SKIP — no
schema/migration/auth/API/`.sql` surface and none of the (a)-(d) expansions (the
seccomp profile guards syscalls, not personal data). CTO cross-cutting assessment
carried into Risks + Sharp Edges; the deepen-plan security-sentinel +
data-integrity-guardian + architecture-strategist triad (single-user-incident
threshold) runs next.

## Open Code-Review Overlap

None found at plan time (no open `code-review`-labelled issue names
`cloud-init.yml`, `server.tf`, `cat-deploy-state.sh`, or the seccomp paths).
/work re-runs the overlap query before freezing Files to Edit.

## Files to Edit

- `knowledge-base/engineering/operations/post-mortems/2026-07-18-seccomp-delivery-leg-host-present-false-rca-6629.md` (CREATE — the RCA)
- `apps/web-platform/infra/cloud-init.yml` (fix — boot-time seccomp delivery) *(conditional on Phase 1)*
- `apps/web-platform/infra/server.tf` (fix — apparmor `server_id` trigger) *(conditional on Phase 1)*
- `apps/web-platform/infra/*.test.sh` or a new drift-guard test (cloud-init seccomp == seccomp-bwrap.json) *(conditional)*
- `knowledge-base/engineering/architecture/decisions/ADR-079-*.md` (amend delivery contract) *(conditional)*
- `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` (re-read; edit only if a description is falsified — expected no-op)

## Sharp Edges

- **Probe-first is load-bearing and ships ALONE.** Do not let the attractive
  cloud-init fix jump ahead of Phase 1. The #6536 incident spent a full host
  replace on a defect that did not exist because a hypothesis was marked
  CONFIRMED from a dev-box capability probe while the discriminator was
  invisible. Every verdict cites its pulled datum or reads UNKNOWN.
- **The fix ships inside the mutation's own payload.** cloud-init `write_files`
  only runs at boot; the change takes effect on the NEXT web-1 replacement.
  Therefore NO AC may claim to observe a "pre-fix host_present=false" via a fresh
  probe — Phase 1 uses HISTORICAL deploy-status/Better Stack data only.
- **`Ref #6629`, not `Closes`.** Closure is the post-merge operator/automated
  step (`hr` ops-remediation class): the RCA + comment on #6628 gate the close.
- **Do not hand-copy the seccomp JSON into cloud-init.** Use `file()`/templatefile
  + a drift-guard test, or the copy silently rots vs `seccomp-bwrap.json` (the
  `.json` extension / content-carrier class of plan-paraphrase bugs).
- **apparmor is the silent sibling.** Fixing only seccomp leaves the AppArmor
  layer of the SAME boundary exposed on replacement (hash-only trigger, no boot
  write). Fold it in or explicitly scope it out with a tracking issue.
- **A plan whose `## User-Brand Impact` is empty/placeholder fails deepen-plan
  Phase 4.6.** This one is filled at single-user-incident threshold.

## Test Scenarios

1. **Drift-guard:** mutate `seccomp-bwrap.json` → the cloud-init drift-guard test
   FAILS (content diverged), proving the two copies are pinned.
2. **Fresh-host simulation (read-only):** confirm via the R2 state + a `terraform
   plan` (no apply) that a `-replace` of `hcloud_server.web["web-1"]` now shows
   `docker_seccomp_config` AND `apparmor_bwrap_profile` as `will be created`
   (both re-fire on replacement) — the `server_id`-in-both invariant.
3. **RCA verdict integrity:** the per-hypothesis table has no CONFIRMED/REFUTED
   row contradicted by an "unavailable datum" statement elsewhere in the doc.
