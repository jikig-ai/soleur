# ADR-122: Boot-time delivery + boot-enforcement for container-sandbox security controls

- **Status:** Adopting
- **Date:** 2026-07-18
- **Deciders:** Jean (operator), CPO sign-off (single-user-incident threshold), deepen-plan review (architecture-strategist, security-sentinel, network-outage L3→L7 deep-dive)
- **Relates to:** #6629 (this RCA + fix); `ADR-080-runtime-plugin-deploys-via-image-rebuild.md` (the image-bake + boot-extraction mechanism this ADR anchors to); `ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md` (owns the RELOAD/canary "applied ≠ loaded" leg — deliberately NOT amended here; this ADR is the DELIVERY leg); `hr-fresh-host-provisioning-reachable-from-terraform-apply`; #4927/#4928 (the fresh-host `terraform_data` silent-skip precedent); #6628 (the standing enforcement-drift watchdog this RCA's build-gate determination licenses)

## Context

The tenant-agent Bash sandbox on the web host is defended by two container
security controls: a **seccomp** syscall filter
(`/etc/docker/seccomp-profiles/soleur-bwrap.json`) and an **AppArmor** profile
(`soleur-bwrap`). `ci-deploy.sh` applies both to the serving container
unconditionally via `--security-opt seccomp=…` / `--security-opt
apparmor=soleur-bwrap` on every running-host deploy.

RCA #6629 found that **neither profile had any boot-time delivery path.** Their
only in-repo writers were the SSH provisioners `terraform_data.docker_seccomp_config`
and `terraform_data.apparmor_bwrap_profile` (`server.tf`), which reach RUNNING
hosts only. `cloud-init.yml` carried zero seccomp/apparmor content. Every sibling
host-config (daemon.json, journald, the 16 host scripts) follows a **dual-delivery**
invariant — cloud-init at boot for fresh hosts + SSH provisioner for running hosts —
but the two sandbox profiles broke it: a fresh host (a web-1 replacement, or the
web-2 warm standby that never receives the web-1-scoped provisioners at all) came up
with **neither** file. `cat-deploy-state.sh` then reported
`seccomp_profile_host_present=false`.

Two compounding defects surfaced while confirming the RCA:

1. The fresh-host serving container is started by cloud-init's **own** `docker run`
   (`cloud-init.yml:773`) with **no** `--security-opt` at all — so a fresh host ran
   the tenant sandbox unenforced *regardless of file presence*. The real enforcement
   signal is `seccomp_profile_loaded_matches_host`, not `host_present`.
2. `apparmor_bwrap_profile.triggers_replace` was **hash-only** (no `server_id`), so a
   host replacement never re-fired the SSH delivery — the exact fresh-host trap the
   seccomp block's `server_id` fold-in was added (per #4927/#4928) to prevent.

This violates `hr-fresh-host-provisioning-reachable-from-terraform-apply` and is a
`single-user incident`-threshold concern: the two layers are defense-in-depth against
a container escape on a shared multi-tenant host, so a realized escape is a
cross-tenant confidentiality breach.

## Decision

Security-control profiles for the container sandbox are delivered and enforced at
**boot time**, mirroring the running-host path:

1. **Delivery via image-bake + boot-extraction (ADR-080 mechanism), NOT
   `write_files`.** `seccomp-bwrap.json` (16,615 B) and
   `apparmor-soleur-bwrap.profile` are added to the Dockerfile
   `/opt/soleur/host-scripts/` COPY set, `.dockerignore` `!infra/` re-includes, and
   `local.host_script_files` — so they fold into the existing
   `host_scripts_content_hash` byte-for-byte boot-integrity verify (no separate
   drift-guard test) and add **zero** user_data bytes (a `write_files` bake of the
   16,615-B seccomp profile would red the `WEB_GZIP_BUDGET` cap —
   `cloud-init-user-data-size.test.ts`).
2. **Install + AppArmor-load in `soleur-host-bootstrap.sh`**, under the top-level
   `set -e` + `emit_fail` trap, BEFORE the terminal `docker run`.
3. **Enforce at the fresh-host boot `docker run`** — it passes both `--security-opt
   seccomp=…` and `--security-opt apparmor=soleur-bwrap`.
4. **Fail-closed if absent:** a profile install / AppArmor-load failure aborts
   bootstrap → the `/run/soleur-hostscripts.ok` sentinel is never written → the
   terminal `docker run` block `poweroff -f`s (existing gate, `cloud-init.yml:754`).
   A fresh host MUST NEVER serve tenant agents with the sandbox unenforced.
5. **`server_id` in BOTH `triggers_replace`** — `apparmor_bwrap_profile` gains the
   `server_id` fold-in it lacked, parity with `docker_seccomp_config`, so a host
   replacement re-fires the running-host SSH delivery too.

The SSH provisioners are RETAINED as running-host updaters. This ADR does **not**
amend ADR-079 (the reload/canary leg) — that leg is a distinct concern.

## Consequences

- A fresh web host (web-1 replacement or web-2 standby) now boots with both profiles
  present, AppArmor-loaded, and enforced — or it poweroffs. `host_present=false` on a
  serving host is no longer reachable via the boot path.
- `host_scripts_content_hash` now covers the two profiles; a stale/mis-built image
  aborts the boot loudly.
- **#6628 build-gate: FIRED.** RCA #6629 confirmed `host_present=false` is reachable
  outside an item-4 run (the web-2 standby + three CI SSH-leg silent-skip paths), so
  the standing 6h enforcement-drift watchdog (#6628 item 1) is now licensed. It should
  track `seccomp_profile_loaded_matches_host`, not just `host_present`.
- Blast radius on the running host: zero — `ignore_changes=[user_data]` means the
  running host is untouched; the change takes effect on the next fresh create.

## Alternatives rejected

- **`write_files`-bake the profiles into cloud-init user_data** — reds the
  `WEB_GZIP_BUDGET` cap (16,615-B seccomp profile ≫ ~200-B headroom). The daemon.json
  inline heredoc (~150 B) is a false precedent for a 16 KB file.
- **Make `--security-opt` conditional-on-file-presence in ci-deploy** — silently
  reproduces this exact invisible-gate incident. Unconditional + `docker run` erroring
  on a missing profile is the correct fail-closed posture.
- **Amend ADR-079** — wrong leg (that ADR owns reload/canary verification, not
  delivery).
