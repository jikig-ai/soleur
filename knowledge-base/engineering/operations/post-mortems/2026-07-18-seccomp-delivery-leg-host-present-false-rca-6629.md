---
title: "RCA: seccomp delivery-leg — why seccomp_profile_host_present=false before the #6512 item-4 redeploy"
date: 2026-07-18
issue: 6629
type: rca
classification: infra-diagnosis-plus-hardening
adr: ADR-122
severity: P2 (latent — invisible unenforced sandbox after a fresh host comes up)
status: root cause CONFIRMED (code-level); fix shipped in the same PR
---

# RCA: seccomp delivery-leg — `seccomp_profile_host_present=false` on the web host before the #6512 item-4 redeploy

## TL;DR

The seccomp syscall profile (`/etc/docker/seccomp-profiles/soleur-bwrap.json`) and
the sibling AppArmor profile have **no boot-time delivery path**. Their only in-repo
writer is an SSH-provisioner (`terraform_data.docker_seccomp_config` /
`apparmor_bwrap_profile`); `cloud-init.yml` delivers **zero** seccomp content. So any
web host that comes up without a *successful SSH-leg apply* against it — a fresh
`hcloud_server.web["web-1"]` create, or the warm-standby **web-2** that by design
never receives the web-1 SSH provisioners at all — reports `host_present=false`.
This directly violates `hr-fresh-host-provisioning-reachable-from-terraform-apply`.

Two compounding defects were found while confirming it: (a) the fresh-host serving
container is started by cloud-init's own `docker run` (`cloud-init.yml:773`) with
**no `--security-opt seccomp` or `apparmor`**, so even a *present* profile is not
enforced on a fresh host; (b) the AppArmor trigger is hash-only (no `server_id`
fold-in), so it carries the exact fresh-host trap the seccomp block's own comment
warns about.

**#6628 build-gate determination: YES** — `host_present=false` is reachable OUTSIDE
an item-4 run. It is a VM-creation-time host property (no boot delivery), and there
are ≥3 non-merge, non-item-4 CI paths that leave the SSH provisioner unapplied with
a green job. The #6628 build trigger has fired.

## What #6512 did and did not fix

#6512 / PR #6622 (merged 2026-07-17) fixed the **reload leg** — a same-version
item-4 seccomp redeploy dying `image_pull_failed` when both registries failed — and
made an unenforced profile a standing alarm (`ci/seccomp-unenforced` issue +
`seccomp_remediation_failed` Sentry). It explicitly deferred the **delivery leg**:
*why was the profile FILE absent from the host in the first place?* This RCA answers
that.

## The incident datum (pulled, not reasoned)

**Correction to the issue's framing:** the cited apply run `29450562340` is on the
**Apply deploy-pipeline-fix** workflow (the ADR-079 item-4 redeploy), created
**2026-07-15T21:03:27Z** — the time (21:03) matches but the **date is 2026-07-15,
not 2026-07-16** as the issue title states. Conclusion: `failure`.

Baseline line captured from `gh run view 29450562340 --log`, step *"Redeploy to
load applied profile and assert loaded==committed (#5875 item 4)"*, at
**2026-07-15T21:04:37Z**:

```
Baseline: host_present=false host_sha256='<none>' loaded_matches_host=false
  (committed='7654ef34…bad73', tag='latest').
…
##[error]Redeploy FAILED: web-platform v0.214.7 terminal reason='image_pull_failed'
  exit_code=1. The applied seccomp profile was NOT loaded.
```

So `host_present=false` is a **real host-side read** (not a redeploy side-effect),
and the run then died on the reload-leg `image_pull_failed` that #6512 fixed. The
`/hooks/deploy-status` payload in that run also showed `services.inngest_*: inactive`
and `image:"_"` — a host in a degraded / non-primary state during a period of heavy
infra churn (web-2 relocation hel1→fsn1, tunnel de-pooling, inngest-bootstrap version
thrashing, zot registry resize).

## Root cause (CONFIRMED — code-level, independent of which host was probed)

`apps/web-platform/infra/cloud-init.yml` contains **zero** `seccomp` /
`soleur-bwrap.json` / `seccomp-profiles` references (`grep -nci = 0`). The **only**
in-repo writer of the profile is the SSH provisioner:

- `terraform_data.docker_seccomp_config` (`server.tf:1057-1114`) — `provisioner
  "file"` scp of `${path.module}/seccomp-bwrap.json` → `/etc/docker/seccomp-profiles/soleur-bwrap.json`,
  `triggers_replace = { seccomp_profile = sha256(file(...)), server_id = hcloud_server.web["web-1"].id }`.
- `terraform_data.apparmor_bwrap_profile` (`server.tf:1120-1143`) — same shape but
  `triggers_replace = sha256(file(...))` **hash-only, no `server_id`**.

Every sibling host-config follows a **dual-delivery** pattern (cloud-init `write_files`
at boot for fresh hosts + SSH provisioner for running hosts) — e.g. `daemon.json`,
journald drop-ins, the 16 host scripts baked into the image and extracted at boot
(`cloud-init.yml:135-140`, ADR-080 / #5921). **The seccomp + AppArmor profiles break
that pattern: a fresh host gets NOTHING at boot.** This is the defect and it violates
`hr-fresh-host-provisioning-reachable-from-terraform-apply`.

Two compounding findings:

1. **The fresh-host boot `docker run` is unenforced regardless of file presence
   (P0).** `cloud-init.yml:773` starts `soleur-web-platform` with `--tmpfs`, env-file,
   volume mounts, port bindings — but **no** `--security-opt seccomp=…` and **no**
   `--security-opt apparmor=…`. So even if the file existed, a fresh host would run
   the tenant sandbox unconfined. The real enforcement signal is
   `seccomp_profile_loaded_matches_host` (the running container's
   `.HostConfig.SecurityOpt`, `cat-deploy-state.sh:339-362`), **not** `host_present`.
   A "fix" that only makes the file appear turns an honest alarm green while the
   container stays unconfined — worse than the status quo.

2. **AppArmor is strictly more exposed (P1).** ci-deploy applies `--security-opt
   apparmor=soleur-bwrap` **unconditionally**, so `docker run` FAILS on a host that
   never kernel-loaded the profile; and the hash-only trigger (no `server_id`) carries
   the exact fresh-host trap the seccomp block's `server_id` fold-in was added to
   prevent (the 2026-06-04 #4927/#4928 precedent).

## Per-hypothesis verdict table (#6536 discipline — no CONFIRMED/REFUTED without the pulled discriminator)

| # | Hypothesis | Verdict | Discriminator datum (pulled) |
|---|---|---|---|
| H0 | The `/hooks/deploy-status` probe read the seccomp-less warm-standby **web-2**, not web-1 | **UNKNOWN (PLAUSIBLE)** | Which host answered at 21:04 is **not resolvable** from Better Stack at 3-day retention — both hosts ship as `host="soleur-web-platform"` with no web-1/web-2 tag, and the window is dominated by webhook/journald payloads. **CONFIRMED context:** `ssh.`/`deploy.` tunnel ingress used a `localhost:`-style service that "resolves on WHICHEVER replica answers" (coin-flip) until #6595 pinned it to web-1's private IP on **2026-07-17T14:44Z** — *after* the 2026-07-15 incident (git log `apps/web-platform/infra/tunnel.tf`). So a web-2 read was reachable. The degraded payload (inngest inactive, image_pull_failed) is consistent with a standby / mid-churn host. Not confirmable either way; **the root cause and fix are identical regardless** (image-bake gives web-2 the profile too). |
| H1 | Missing boot delivery on a **replaced web-1** | **UNKNOWN** | No web-1-isolable boot marker could be extracted from Better Stack in the window (retention + host-name collision). Structurally reachable — finding 1 (no boot delivery) is CONFIRMED. |
| H2 | `-target` pruning defeated the `server_id` guard | **PLAUSIBLE (structural)** | The `server_id` trigger + the workflow's two-apply `-target` split are CONFIRMED (`server.tf:1069`, `apply-web-platform-infra.yml:16-29,682-683`); the specific replacing-apply was not isolated, so not elevated to CONFIRMED. |
| H3 | SSH-apply leg silently skipped/failed (**non-merge, non-item-4**) | **CONFIRMED (structural)** | `apply-web-platform-infra.yml`: (a) `ssh_token_gate` (:620-636) sets `ssh_apply_skip=true` with only a `::warning::` if `CI_SSH_ACCESS_TOKEN_ID` is absent in Doppler `prd_terraform`; (b) the `[skip-web-platform-apply]` kill-switch (:156) gates the whole apply off; (c) any `workflow_dispatch` `apply_target` other than `manual-rerun` (:177) runs a mutually-exclusive job. `docker_seccomp_config` + `apparmor_bwrap_profile` are `-target`'d **only** in the SSH apply leg (:682-683). Each path leaves both provisioners unapplied with the job green. |
| H4 | File deleted / never delivered, no replacement | **UNKNOWN** | No in-window boot marker isolable; cannot confirm or refute. |
| H5 | Namespace-visibility artifact (probe read a path the running state doesn't reflect) | **REFUTED** | `cat-deploy-state.sh:330-332` reads `SECCOMP_PROFILE_HOST_PATH` (default the real host path) with a host-side `[[ -f "$host_path" ]]`; the deploy-status hook runs host-side, not in a container namespace. `false` means genuine host-side absence. |

**No self-contradiction:** no row reads CONFIRMED/REFUTED off a datum this document
also calls unavailable. H0/H1/H4's unavailable discriminators are recorded as UNKNOWN,
per the #6536 sharp edge (do not reason a verdict while its deciding datum is invisible).

## Non-merge-path determination (the #6628 build-gate) — **YES**

`host_present=false` **is** reachable outside an item-4 run. It is a property set at
VM-creation time (no boot-time delivery), and item-4 only *reads* it. Independent,
non-item-4, non-merge paths that produce it:

- **The warm-standby web-2** structurally lacks the file — it never receives the
  web-1-scoped SSH provisioners (`server.tf:104-105`). Any probe that reaches it reads
  `host_present=false` by design.
- **H3's three CI silent-skip paths** (token-gate skip / kill-switch / dispatch fork)
  leave a fresh or drifted web-1 without the file and the job green.

Therefore the **#6628 build trigger has fired**: a non-merge unenforcement path is
observed, and the standing 6h enforcement-drift watchdog (#6628 item 1) is now
licensed to be built. (It should track `seccomp_profile_loaded_matches_host`, not just
`host_present` — see finding 1.)

## The fix (shipped in this PR — licensed by the CONFIRMED code-level root cause)

1. **Boot-time delivery via image-bake + extraction** (NOT `write_files` — the
   16,615-B profile would red `cloud-init-user-data-size.test.ts`'s `WEB_GZIP_BUDGET`).
   `seccomp-bwrap.json` + `apparmor-soleur-bwrap.profile` are added to the Dockerfile
   `/opt/soleur/host-scripts/` COPY set and extracted at boot by the existing
   host-script extraction runcmd, folded into `host_scripts_content_hash`.
2. **Enforce at the fresh-host boot `docker run` + fail-closed.** Add `--security-opt
   seccomp=…` and `--security-opt apparmor=soleur-bwrap`; load the AppArmor profile
   (`apparmor_parser -r`) before the run; `poweroff -f` if the profile/apparmor state
   is absent at boot — a fresh host must never serve tenant agents unenforced.
3. **AppArmor `server_id` parity** — add `server_id` to
   `apparmor_bwrap_profile.triggers_replace`.
4. Track `seccomp_profile_loaded_matches_host` (enforcement), not just `host_present`.

Recorded in **ADR-122** (anchored to ADR-080 bake-and-extract; cross-references
ADR-079, which owns the reload/canary leg — deliberately NOT amended here).

## Layer citations

- Incident datum: `gh run view 29450562340 --log` (GitHub Actions).
- Host-identity attempt: Better Stack `soleur-inngest-vector-prd` via
  `scripts/betterstack-query.sh` (Doppler `prd_terraform`) — retention/host-name
  collision made the web-1/web-2 discriminator UNKNOWN (recorded honestly, not reasoned).
- Code facts: `server.tf`, `cloud-init.yml`, `cat-deploy-state.sh`,
  `apply-web-platform-infra.yml`, `tunnel.tf` at `origin/main` (SHA a989c247e).

## Follow-ups

- **#6628**: build trigger FIRED — comment posted; the standing 6h watchdog is licensed.
- The running host self-resolved to `host_present=true` after the window (per the #6512
  post-mortem); this fix takes effect on the **next** web-1 replacement (cloud-init runs
  at boot). No retro-fix of the running host is needed or attempted.
