---
title: "RCA: seccomp delivery-leg — why host_present=false before the #6512 item-4 redeploy (2026-07-16)"
date: 2026-07-18
issue: 6629
type: rca
classification: infra-diagnosis-plus-hardening
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: ADR-122 (new — anchored to ADR-080 bake-and-extract; NOT ADR-079)
---

# RCA: seccomp delivery-leg — why `host_present=false` on web-1 before the #6512 item-4 redeploy

## Enhancement Summary (deepen-plan, 2026-07-18)

Deepened via architecture-strategist + security-sentinel + a network-outage L3→L7
deep-dive (single-user-incident triad). **Five load-bearing corrections** — the
probe-first Phase 1 was affirmed sound; the Phase-2 fix was materially wrong:

1. **NEW H0 (promote to checked-FIRST): the `/hooks/deploy-status` probe may have
   read the warm-standby web-2, not web-1.** web-2 by design receives NONE of the
   11 web-1-scoped SSH provisioners (`server.tf:104-105`), and tunnel ingress was a
   web-1/web-2 coin-flip until #6595 pinned it on **2026-07-17 — the day AFTER the
   2026-07-16 incident** (`tunnel.tf:69-72`). If the probe hit web-2,
   `host_present=false` is EXPECTED, not drift, and H1/H2 (web-1 replaced) are moot.
   Cheapest to confirm, most changes the fix — Phase 1 checks it first.
2. **P0 — the primary fix as written is a false-green.** The fresh-host serving
   container is started by cloud-init's OWN `docker run` (`cloud-init.yml:773-785`),
   which passes NEITHER `--security-opt seccomp` NOR `apparmor`. So a fresh host runs
   the tenant sandbox UNENFORCED regardless of whether the file exists. Baking the
   file flips `host_present=true` while the container stays unconfined. The real
   enforcement signal is `seccomp_profile_loaded_matches_host`
   (`cat-deploy-state.sh:339-362`), which the plan's ACs/Observability never tracked.
3. **P0 — `write_files` bake is a CI-hard-blocker.** `seccomp-bwrap.json` is 16,615 B
   (~3,489 B gzipped); the web user_data is ~22,256 B against a `WEB_GZIP_BUDGET =
   22,450` guard (`plugins/soleur/test/cloud-init-user-data-size.test.ts:99`) —
   ~200 B headroom, "comment-frozen" (`server.tf:155-158`). Correct delivery is the
   existing **image-bake + boot-extraction** path (Dockerfile `/opt/soleur/host-scripts/`
   at `:196-206` → extraction runcmd `cloud-init.yml:139-140` → `host_scripts_content_hash`),
   the #5921 / ADR-080 precedent the plan failed to cite.
4. **P1 — apparmor is HARD-required, not scoped out.** ci-deploy applies
   `--security-opt apparmor=soleur-bwrap` unconditionally, so `docker run` FAILS on a
   fresh host that never kernel-loaded the profile. Same boundary, strictly more
   exposed (hash-only trigger).
5. **ADR target is ADR-080 (bake-and-extract), not ADR-079 (reload/canary).** Prefer
   a new **ADR-122** anchored to ADR-080, cross-referencing ADR-079.

The revised fix (image-bake delivery + cloud-init `docker run` security-opts +
fail-closed-if-absent + apparmor parity + track `loaded_matches_host`) is folded
into Phases 1–2, Hypotheses, User-Brand Impact, Observability, ADR, and ACs below.

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
- **#5921 / ADR-080 (the applicable delivery precedent, NOT cited in plan v1)** —
  the 22 host bootstrap scripts + hooks.json were REMOVED from cloud-init `write_files`
  because they blew the 32,768-B Hetzner user_data cap; they are now image-baked into
  `/opt/soleur/host-scripts/` and extracted at boot with a combined-hash verify
  (`server.tf:124-128`, `cloud-init.yml:139-140`, `Dockerfile:196-206`). This is the
  exact mechanism the seccomp/apparmor profiles must use — and the reason the naive
  `write_files` bake is a CI-hard-blocker (`cloud-init-user-data-size.test.ts`).
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

**If this leaks, the user's workflow/data is exposed via:** the seccomp filter is a
defense-in-depth syscall gate; its absence (combined with the equally-exposed
AppArmor layer, finding 7) **materially lowers the bar for a container escape** on
a shared multi-tenant host — all tenants share the one `soleur-web-platform`
container with every workspace under a single `-v /mnt/data/workspaces:/workspaces`
mount (`cloud-init.yml:781`), so a realized escape (chained kernel/syscall exploit)
is a **cross-tenant confidentiality breach affecting every tenant on web-1**, not a
single user. Weaponization requires a chained exploit — this is a lowered-bar, not a
direct filesystem path.

**Brand-survival threshold:** single-user incident. Deliberately the STRICTEST enum
value (not `aggregate pattern`) precisely because the blast radius is cross-tenant —
a single realized escape is brand-ending, so max review rigor applies.
`requires_cpo_signoff: true` — CPO sign-off at plan time before `/work`;
`user-impact-reviewer` runs at review time (per `review/SKILL.md`).

## Hypotheses

The SSH-provisioner delivery path (`provisioner "file"` scp + `remote-exec` over
the CF-Tunnel SSH bridge) makes SSH a hard apply-time dependency, so the
L3→L7 network-outage checklist (`hr-ssh-diagnosis-verify-firewall`) applies to
any "the provisioner failed to run" branch. Unverified layers are listed FIRST,
in L3→L7 order, before the service-specific hypotheses.

**H0 — The `/hooks/deploy-status` PROBE read web-2, not web-1 (CHECK FIRST).**
web-2 is a warm standby that **by design receives NONE of the 11 web-1-scoped SSH
provisioners** (`server.tf:104-105`), so it structurally lacks the seccomp file —
`host_present=false` on web-2 is EXPECTED, not drift. Tunnel ingress
(`deploy.`/`ssh.`) was a **coin-flip across web-1/web-2** until #6595 pinned it to
web-1 on **2026-07-17 — the day AFTER the incident** (`tunnel.tf:69-72`, diff
`ssh://localhost:22`→`ssh://<web-1 private_ip>:22`). If the 21:03 probe was
answered by web-2, the entire "web-1 replaced" thesis (H1/H2) is MOOT and the fix
reframes (image-bake would give web-2 the profile too). This is the cheapest to
confirm and the most decisive. Discriminator: which host answered
`/hooks/deploy-status` at 21:03 (payload host_id/marker + the tunnel ingress
config state in the window). [unverified — Phase 1.0]

**H-net (L3 firewall).** The SSH apply leg reaches web-1 over the CF-Tunnel SSH
bridge (`.github/actions/cf-tunnel-ssh-bridge`), NOT a direct `:22` dial (the
GH-runner egress IP is not in `var.admin_ips`; `firewall.tf:5-13`). The bridge
NAT-redirects (`action.yml:208-213`) terraform's SSH client through
`cloudflared access tcp` → CF Access → tunnel ingress. Verification: inspect the
`29450562340`-adjacent run logs for the SSH-leg step — did the bridge connect, or
fail? Grep signatures: `cloudflared TCP forward did not open on 127.0.0.1:2222
within 15s` (CF-Access token expiry), `iptables NAT redirect … failed`, and in the
`=== /tmp/cloudflared.log (last 200 lines) ===` block: `Unauthorized`/`403`,
`websocket: bad handshake`, `context deadline exceeded`, `connection reset`,
`i/o timeout`. [unverified — Phase 1]

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

**H3 — SSH apply leg silently skipped / failed (STRONG; NON-item-4, merge-independent).**
The network deep-dive confirmed the SSH leg is a SEPARATE `terraform apply` that
runs AFTER the main 80-resource apply has already committed R2 state
(`apply-web-platform-infra.yml:508-515` before `:648-685`) — so a green main apply
HIDES a skipped/failed seccomp delivery. Three concrete silent-skip paths, each
leaving the job green with no operator-readable signal:
 (a) **token-gate skip** — `ssh_token_gate` (`:620-637`) sets `ssh_apply_skip=true`
 with only a `::warning::` if `CI_SSH_ACCESS_TOKEN_ID` is absent in Doppler
 `prd_terraform`; BOTH the bridge and the seccomp apply are then skipped. Grep:
 `first-bootstrap: CI_SSH_ACCESS_TOKEN_ID absent`.
 (b) **kill-switch** — `[skip-web-platform-apply]` gates the whole apply job off (`:147-161,:175-177`).
 (c) **dispatch selects a job with NO seccomp leg** — any `workflow_dispatch`
 `apply_target` other than `manual-rerun` (warm-standby / web-2-recreate / …) runs a
 mutually-exclusive job; `docker_seccomp_config` is `-target`'d ONLY in the `apply`
 job (`:682`). So a dispatch-driven apply since the seccomp change never delivers it.
Discriminator: the SSH-leg step's `skipped` vs `failure` vs `success` status +
the token-gate warning in the run(s). **These are non-merge, non-item-4 paths to
host_present=false — they directly feed the #6628 build-gate.** [unverified — Phase 1]

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

1.0. **H0 FIRST — which host answered the probe?** Establish whether the
`/hooks/deploy-status` reading at 21:03 came from web-1 or the seccomp-less web-2.
Pull the deploy-status payload's host identifier/marker for the window AND the
tunnel `ssh.`/`deploy.` ingress config state at that time (`tunnel.tf` history vs
#6595 merge at 2026-07-17). Verdict rule: probe answered by web-2 ⟹ `host_present=false`
is EXPECTED (web-2 has no SSH provisioners) and H1/H2 are REFUTED — the RCA
reframes to "the standby is structurally unenforced" (still a real gap the
image-bake fix closes); probe answered by web-1 ⟹ proceed to H1/H2/H3.

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

1.4. **Apply / drift run logs (WINDOW-DECISIVE for H2/H3).**
`gh run list --workflow=apply-web-platform-infra.yml` (+ `apply-deploy-pipeline-fix.yml`,
`scheduled-terraform-drift.yml`) across 2026-07-14…16. For each candidate apply:
did it replace web-1? What was its executed `-target` set? Did the SSH leg step
show `success` / `skipped` / `failure`? Grep the SSH-leg starter set (H3 + H-net
signatures: `CI_SSH_ACCESS_TOKEN_ID absent`, `cloudflared TCP forward did not
open`, cloudflared-log block errors). Verdict rule: an apply that replaced/targeted
web-1 without a successful SSH leg ⟹ H2/H3 confirmed; a token-gate/kill-switch/dispatch
skip ⟹ H3 confirmed (non-merge path).

1.5. **R2 terraform state read (CORROBORATING, not decisive).** Read
`apps/web-platform/infra/terraform.tfstate` from the R2 backend (AWS creds +
`--name-transformer tf-var` per the canonical triplet;
`terraform state show terraform_data.docker_seccomp_config`). Compare its recorded
`triggers.server_id` against live `hcloud_server.web["web-1"].id`. **Caveat: this
is a plan-time snapshot that may have self-healed after the window** (deploy-status
self-resolved false→true by 2026-07-17), so a MATCHING server_id does NOT prove the
file was present at 21:03. Treat as corroborating only; the window-decisive evidence
is 1.0 (which host) + 1.4 (executed apply) + 1.3 (boot markers).

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

### Phase 2 — Fix (ONLY if Phase 1 confirms an enforcement-delivery gap on the probed host)

> **REVISED per deepen-plan review.** `host_present=true` is NOT enforcement — the
> real signal is `seccomp_profile_loaded_matches_host` (the running container's
> `.HostConfig.SecurityOpt`, `cat-deploy-state.sh:339-362`). Two independent P0s
> reshape this phase: (i) the fresh-host serving container is started by cloud-init's
> OWN `docker run` (`cloud-init.yml:773-785`) with NO `--security-opt`, so it runs
> unenforced regardless of file presence; (ii) `write_files`-baking the 16,615-B
> profile reds `cloud-init-user-data-size.test.ts` (`WEB_GZIP_BUDGET=22,450`, ~200 B
> headroom). Fix = image-bake delivery + enforce at the boot `docker run` + fail-closed.

2.1. **Deliver the profile via image-bake + boot-extraction (NOT `write_files`).**
Add `seccomp-bwrap.json` (16,615 B) and `apparmor-soleur-bwrap.profile` (426 B) to
the Dockerfile `/opt/soleur/host-scripts/` COPY set (`apps/web-platform/Dockerfile:196-206`),
extracted at boot by the existing host-script extraction runcmd
(`cloud-init.yml:139-140`: `docker cp` → combined-hash verify → per-file install),
folding both into `host_scripts_content_hash` (`server.tf:126-128`). This respects
the 32,768-B / `WEB_GZIP_BUDGET` cap (the #5921 / ADR-080 precedent), reuses the
existing byte-for-byte boot-integrity hash (so NO separate drift-guard test — extend
the existing hash coverage), and gives a fresh host the file + apparmor profile at
boot independent of the SSH leg. Keep the SSH provisioners as running-host updaters.

2.2. **Enforce at the fresh-host boot `docker run` + fail-closed (P0 — closes the
residual window).** Add `--security-opt seccomp=/etc/docker/seccomp-profiles/soleur-bwrap.json`
AND `--security-opt apparmor=soleur-bwrap` to the cloud-init `docker run`
(`cloud-init.yml:773-785`), mirroring `ci-deploy.sh:2413-2414,2646-2647`. Load the
apparmor profile (`apparmor_parser -r`) + assert the userns sysctl in `runcmd`
BEFORE that `docker run` (intra-runcmd ordering; `write_files`/extraction precedes
`runcmd`). Fail-closed: if the profile or apparmor state is absent at boot,
`poweroff -f` (reuse the existing fail-closed idiom at `cloud-init.yml:754,793-796`)
— a fresh host must NEVER serve tenant agents unenforced.

2.3. **AppArmor parity — HARD-required (P1, not scoped out).** Add `server_id` to
`apparmor_bwrap_profile.triggers_replace` (`server.tf:1121`, currently hash-only),
deliver the profile via 2.1's image-bake, load it in 2.2's runcmd, and pass its
`--security-opt`. Rationale: ci-deploy applies `--security-opt apparmor=soleur-bwrap`
UNCONDITIONALLY, so `docker run` FAILS on a host that never kernel-loaded the
profile — fixing seccomp alone leaves an equivalent P0 on the sibling layer.

2.4. **Preserve ci-deploy's UNCONDITIONAL `--security-opt` (P2).** Do NOT make
seccomp application conditional-on-file-presence in `ci-deploy.sh` — unconditional
+ `docker run` erroring on a missing file is the correct fail-closed posture (a
conditional "fix" silently reproduces this exact invisible-gate incident). The
asymmetry to fix is the cloud-init boot run (2.2), not ci-deploy.

2.5. **Track `loaded_matches_host`, not just `host_present`, everywhere.** The RCA,
Observability, and ACs must assert the enforcement conjunct
(`seccomp_profile_loaded_matches_host`), so a present-but-unenforced host is not a
false-green. (Conditional on H2/H3) also make the SSH-apply leg FAIL LOUD (non-zero
+ Sentry) when the token-gate skip/leg-failure leaves the provisioners un-applied.

2.6. **Amend the ADR (see Architecture Decision section) + re-read the 3 `.c4` files.**

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
- [ ] IF a fix ships (Phase 2): `seccomp-bwrap.json` + `apparmor-soleur-bwrap.profile`
  are in the Dockerfile `/opt/soleur/host-scripts/` COPY set and folded into
  `host_scripts_content_hash` (grep `Dockerfile` + `server.tf`) — NOT added to
  cloud-init `write_files` (which would red the size test).
- [ ] IF a fix ships: the cloud-init `docker run` (`cloud-init.yml:773`) passes BOTH
  `--security-opt seccomp=…` and `--security-opt apparmor=soleur-bwrap`, with a
  fail-closed `poweroff -f` if the profile/apparmor state is absent at boot (grep).
- [ ] IF a fix ships: `apparmor_bwrap_profile.triggers_replace` includes `server_id`
  (grep `server.tf`).
- [ ] IF a fix ships: `plugins/soleur/test/cloud-init-user-data-size.test.ts` stays
  GREEN (the image-bake path adds NO user_data bytes — verify the rendered
  `base64gzip(templatefile(cloud-init.yml))` is unchanged in size).
- [ ] IF a fix ships: an AC asserts `seccomp_profile_loaded_matches_host` (the
  enforcement conjunct), not only `host_present` — a present-but-unenforced host
  must fail the gate.
- [ ] IF a fix ships: `terraform plan -replace=hcloud_server.web["web-1"]` (read-only,
  no apply) shows the new host's `user_data` carries the change and BOTH
  `docker_seccomp_config` + `apparmor_bwrap_profile` re-fire (confirms
  `ignore_changes=[user_data]` at `server.tf:266` does not pin stale user_data on a
  fresh create; server.tf:143 says only a fresh create applies user_data).
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean (if any TS
  touched); infra shell tests pass (`cat-deploy-state.test.sh`).
- [ ] `terraform validate` (or the CI infra-config gate) passes on the Dockerfile
  + cloud-init + server.tf changes.
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

### Image-bake + Terraform changes
- `apps/web-platform/Dockerfile` — add `seccomp-bwrap.json` + `apparmor-soleur-bwrap.profile`
  to the `/opt/soleur/host-scripts/` COPY set (image-bake, NOT user_data).
- `apps/web-platform/infra/cloud-init.yml` — extract the two profiles in the existing
  host-script extraction runcmd; add `--security-opt seccomp/apparmor` to the boot
  `docker run` + fail-closed poweroff; `apparmor_parser -r` before that run.
- `apps/web-platform/infra/server.tf` — `apparmor_bwrap_profile.triggers_replace`
  gains `server_id`; extend `host_scripts_content_hash` to cover the two profiles.
- Providers/pins unchanged; no new `TF_VAR_*`.

### Apply path
Image-bake takes effect on the next image build + fresh web-1 create (`ignore_changes=[user_data]`
means a running host is untouched; server.tf:143 — only a fresh create applies the
new user_data/image). The `server_id` trigger change re-fires `apparmor_bwrap_profile`
on the next SSH-leg apply that reaches web-1. No `-replace` of web-1 is prescribed by
this PR (operator-local + gated). Blast radius: zero on the running host.

### Distinctness / drift safeguards
`dev != prd`: N/A (single prod web host). Content integrity is enforced by the
existing `host_scripts_content_hash` byte-for-byte boot verify (NO separate
drift-guard test needed — extend the existing hash set). NO seccomp JSON is inlined
into user_data, so the 32,768-B / `WEB_GZIP_BUDGET=22,450` cap is unaffected. No new
secrets land in `terraform.tfstate` (the profiles are non-secret syscall allowlists).

### Vendor-tier reality check
N/A — no new vendor resource; hcloud + cloud-init only.

## Observability

```yaml
liveness_signal:
  what: seccomp_profile_loaded_matches_host (the ENFORCEMENT conjunct — running container .HostConfig.SecurityOpt vs host file) AND host_present + host_sha256, via /hooks/deploy-status. Tracking host_present alone is a false-green (present file != enforcing container).
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
**Prefer a new ADR-122 anchored to ADR-080, cross-referencing ADR-079.** Per
architecture review, the delivery leg belongs with **ADR-080** (the #5921
image-bake + boot-extract mechanism), NOT ADR-079 (which owns the reload/canary
"applied ≠ loaded" contract). ADR-122 "boot-time delivery + boot-enforcement for
container sandbox security controls" records: (a) security-control profiles
(seccomp, apparmor) are delivered via the image-bake+extraction path and folded
into `host_scripts_content_hash`; (b) the fresh-host boot `docker run` MUST pass
the `--security-opt` flags + fail-closed if absent; (c) both `terraform_data`
resources carry `server_id` in `triggers_replace`. ADR-122's provisional ordinal
is re-verified against `origin/main` at ship (collision gate). If reviewers prefer,
amend ADR-080 in place instead of a new ADR — but do NOT amend ADR-079 (wrong leg).

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
- `apps/web-platform/Dockerfile` (fix — add seccomp + apparmor profiles to the `/opt/soleur/host-scripts/` bake set) *(conditional on Phase 1)*
- `apps/web-platform/infra/cloud-init.yml` (fix — boot-extract the profiles; add `--security-opt` to the boot `docker run` + fail-closed; `apparmor_parser -r` in runcmd) *(conditional)*
- `apps/web-platform/infra/server.tf` (fix — apparmor `server_id` trigger; extend `host_scripts_content_hash` coverage) *(conditional)*
- `knowledge-base/engineering/architecture/decisions/ADR-122-*.md` (CREATE — anchored to ADR-080; NOT amend ADR-079) *(conditional)*
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
- **Do not duplicate the seccomp JSON anywhere.** Deliver via image-bake +
  boot-extraction; the single source is `seccomp-bwrap.json` covered by
  `host_scripts_content_hash`. No cloud-init copy, no `file()`/templatefile inline,
  no separate drift-guard test — a second copy is the `.json` content-carrier
  drift class.
- **apparmor is HARD-required, not the silent sibling.** ci-deploy applies
  `--security-opt apparmor=soleur-bwrap` unconditionally → `docker run` FAILS on a
  fresh host that never kernel-loaded it. Fix both layers in this PR (server_id +
  image-bake + `apparmor_parser -r` + the boot `--security-opt`).
- **`host_present=true` is NOT enforcement (false-green trap).** The fresh-host
  serving container is started by cloud-init's own `docker run` (`cloud-init.yml:773`)
  with no `--security-opt`, so it runs unenforced even when the file is on disk. The
  real signal is `seccomp_profile_loaded_matches_host`. A fix that only makes the file
  appear turns an honest alarm green while the container stays unconfined — worse than
  the status quo.
- **`write_files`-baking the profile is a CI-hard-blocker.** 16,615 B against ~200 B
  `WEB_GZIP_BUDGET` headroom reds `cloud-init-user-data-size.test.ts`. Use image-bake +
  boot-extraction (#5921/ADR-080); the `daemon.json` inline heredoc (~150 B) is a false
  precedent.
- **H0 before H1/H2 — confirm WHICH host was probed.** web-2 (warm standby) has NO
  SSH provisioners by design; the tunnel ingress was a coin-flip until #6595 pinned it
  the day after the incident. The whole fix license (H1/H2) hinges on establishing the
  probed host first.
- **A plan whose `## User-Brand Impact` is empty/placeholder fails deepen-plan
  Phase 4.6.** This one is filled at single-user-incident threshold.

## Test Scenarios

1. **Content integrity:** mutate `seccomp-bwrap.json` → the `host_scripts_content_hash`
   boot-verify changes, forcing re-extraction (no separate drift-guard test needed).
2. **Fresh-host simulation (read-only):** `terraform plan -replace=hcloud_server.web["web-1"]`
   (no apply) shows the new host's `user_data`/image carries the change and BOTH
   `docker_seccomp_config` + `apparmor_bwrap_profile` re-fire — the `server_id`-in-both
   invariant AND that `ignore_changes=[user_data]` does not pin stale user_data on create.
3. **Enforcement (not presence):** an AC/probe asserts `seccomp_profile_loaded_matches_host`
   AND `apparmor` opt on the running container — a present-but-unenforced host FAILS.
4. **RCA verdict integrity:** the per-hypothesis table has no CONFIRMED/REFUTED row
   contradicted by an "unavailable datum" statement elsewhere in the doc.
