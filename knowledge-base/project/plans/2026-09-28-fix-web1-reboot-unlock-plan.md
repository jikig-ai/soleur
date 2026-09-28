---
title: "fix(infra): make web-1 reboot-safe — fstab mapper pin, boot-time LUKS unlock, ADR-119 §(e) mount gate"
date: 2026-09-28
slug: fix-web1-reboot-unlock
branch: feat-one-shot-9123-web1-reboot-unlock
issue: 9123
closes: [9123]
refs: [6604, 6931, 9045, 8706, 8632, 9098, 8210]
type: bug
priority: p0
domain: [engineering, legal]
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- The Phase 2.8 review this ack asserts: every host-state change in this plan
     (unit installs, fstab/crypttab writes, chattr, daemon reloads) is content of
     Terraform `remote-exec`/`file` provisioners on a `terraform_data` resource —
     the IaC channel itself, not a human step. `systemctl …` and
     `/etc/systemd/system/…` strings below describe provisioner payload, which is
     what the guard's ack exists to distinguish. -->

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

web-1 (`soleur-web-platform`) cannot survive a reboot today. Three independent
defects compound into one outage class (#9123):

1. `/etc/fstab` on web-1 carries the **literal** device path
   `/dev/disk/by-id/scsi-0HC_Volume_*` — the unexpanded glob written by web-1's
   first boot on 2026-03-17, predating the #6604 by-id pin. systemd-fstab-generator
   does not expand globs, the line has no `nofail`, so `mnt-data.mount` waits on a
   device that can never appear and `local-fs.target` fails into emergency mode.
2. `/dev/mapper/workspaces` — the LUKS mapper the 2026-07-23 cutover made the live
   source of `/mnt/data` — is mounted today but absent from both `/etc/fstab` and
   `/etc/crypttab`. Nothing unlocks it at boot: no crypttab line, no key-fetch
   unit. (#6931 covers the *fresh-host* path only; web-1's live-host path is this
   work.)
3. The ADR-119 §(e) structural mount gate — `chattr +i` on the root-disk
   `/mnt/data` inode plus the `RequiresMountsFor` ordering — was never delivered to
   web-1. §(e) routed it through the cutover channel; no cutover tail ever ran to
   completion (the same gap that left the monitor units uninstalled for nine weeks
   until #8706 moved them to `terraform_data.luks_monitor_install`).

**The issue's act-at-once trigger has fired.** The post-merge apply-run forensic
print (run 36425473000, 2026-09-28T13:01Z) shows `reboot-required=yes` on web-1. An
unattended-upgrades reboot would take every user workspace offline until console
repair — a `single-user incident` threshold event the moment it happens.

**Why the coupled fix, not the one-liner** (from the issue, verified against the
repo): rewriting fstab to `/dev/mapper/workspaces … nofail` alone lets the boot
succeed with `/mnt/data` as a **bare root-disk directory** whenever the unlock is
absent — dockerd resurrects the app container over `--restart unless-stopped`,
users write into the unencrypted root disk. The fstab fix, the boot unlock, and the
fail-closed mount gate must land **together**.

**Delivery channel:** a new `terraform_data.workspaces_boot_unlock_install` in
`apps/web-platform/infra/workspaces-luks.tf`, riding the same CF-Tunnel-SSH apply
stage as `terraform_data.luks_monitor_install` (#8706), under the ADR-154 standing
web-1 in-place exception (cx33 unorderable in hel1-dc2 — a fresh probe is recorded
at implementation time). All verification is through apply-run state prints and
the daily `workspaces-luks-verify` workflow — no direct host login anywhere.

## Problem Statement / Motivation

If web-1 restarts for any reason — a deliberate restart, a Hetzner host event, or
unattended-upgrades under `reboot-required=yes` — the site very likely does not
come back. The measurable blast radius is total: `app.soleur.ai` is a hard-pinned
singleton A record to web-1 (no LB, web-2 is a weight-0 standby), so every user's
workspace and the serving app go offline together, with no automated recovery.

## Proposed Solution

Deliver the three coupled parts through **one** new Terraform-owned installer,
`terraform_data.workspaces_boot_unlock_install` (web-1 only, per ADR-119 §(d) —
a fresh host must not get these), modelled on the two existing precedents:

- **Boot unlock** — modelled on the `git-data-luks-reopen.{sh,service,timer,
  failure.service}` family (#8210) and `soleur-luks-structural-gate`'s crypttab
  line (`apps/web-platform/infra/soleur-host-bootstrap.sh`, stage
  `luks_structural_gate_author`). A phase-tagged reopen script fetches the key at
  boot via `doppler secrets get WORKSPACES_LUKS_KEY --plain --config
  prd_workspaces_luks` (the R9-pinned form — never `doppler run`/`download` on
  that config, the CWE-522 hole), pipes it to `cryptsetup luksOpen --key-file -`,
  and delegates the mount to PID 1 by starting the fstab-generated
  `mnt-data.mount` unit.
- **fstab repair** — an idempotent writer that replaces every non-comment
  `/mnt/data` line with exactly one
  `/dev/mapper/workspaces /mnt/data ext4 defaults,nofail 0 2` (the git-data
  fstab shape verbatim), keeping superseded lines as `#`-comments and refusing
  when the post-edit table does not carry exactly one `/mnt/data` entry naming
  the mapper.
- **§(e) structural gate** — the `docker.service.d/10-workspaces-luks-mount.conf`
  drop-in carrying `RequiresMountsFor=/mnt/data` plus
  `After=workspaces-luks-reopen.service` (docker queues behind the unlock ladder
  instead of racing the device timeout), and `chattr +i` on the **covered**
  root-disk `/mnt/data` inode via a non-recursive bind peek (`mount --bind /` to
  a scratch path → `chattr +i <peek>/mnt/data` → umount) — the mapper is mounted,
  so the plain `mountpoint -q`-guarded arm in the baked gate cannot reach that
  inode on web-1.

### crypttab option choice (design note for review)

The baked gate writes `workspaces /dev/disk/by-label/workspaces_luks none
luks,nofail`. For web-1 the recommended line is
`workspaces /dev/disk/by-id/scsi-0HC_Volume_<hcloud_volume.workspaces_luks.id>
none luks,noauto` — two deliberate divergences:

- `by-id` pin over `by-label`: consistent with the repo's volume pinning
  convention (#6604) and Terraform-interpolated; nothing in the cutover writes a
  `workspaces_luks` LUKS label, so the by-label spelling would not resolve on
  web-1 today.
- `noauto` over `nofail`: on web-1 the reopen unit owns the unlock, so the
  systemd-cryptsetup ask-password job should not be generated into boot ordering
  at all — under `nofail` it would sit in a bounded interactive-timeout window
  every boot and could race the reopen unit's `luksOpen`. The baked gate's
  `nofail` was written for a host whose unlock half is deferred (#6931); when
  #6931 lands, the baked line should be reconciled to the same shape.

## Technical Considerations

- **The `systemd-cryptsetup@workspaces` unit must not enter boot ordering.**
  With a `none` keyfile and no `noauto`, systemd asks for a passphrase
  interactively each boot — pointless on a headless host and a race against the
  reopen unit's `luksOpen`. `noauto` keeps crypttab as the declared mapping and
  the manual-recovery handle while the unit does the work.
- **Ordering is the load-bearing detail.** `RequiresMountsFor=/mnt/data` on
  `docker.service` pulls `mnt-data.mount` in; without
  `After=workspaces-luks-reopen.service` the mount's
  `dev-mapper-workspaces.device` wait can time out before the Doppler key fetch
  completes, failing docker (fail-closed for data, but an avoidable availability
  blip). The drop-in carries both directives.
- **`/etc/default/luks-monitor` line ownership is sacred.** The DSN writer
  (`luks_monitor_install`) and the token helper (`luks_monitor_token_install` via
  `luks-monitor-token-refresh.sh`) each own one line and refuse if any other
  line changed. The reopen unit reads `DOPPLER_TOKEN` through
  `EnvironmentFile=-/etc/default/luks-monitor` (read-only consumer — never
  writes it) and reads its device pin from a NEW
  `EnvironmentFile=-/etc/default/workspaces-luks-boot` written by this installer
  (0600 root; `WORKSPACES_LUKS_DEV=<by-id pin>` +
  `WORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks`). No third writer is added to
  the shared file.
- **The token is already on the host** — `terraform_data.luks_monitor_token_install`
  (#8632) delivered the `prd_workspaces_luks` read-only service token; the reopen
  unit consumes the same `DOPPLER_TOKEN=` line.
  `depends_on = [terraform_data.luks_monitor_token_install,
  terraform_data.luks_monitor_install]` orders after both in a shared apply.
- **Freeze-window refusal** — mirror `luks_monitor_install`'s exit-17 pattern:
  the fstab/crypttab writers refuse while `workspaces-luks-deadman.timer` reads
  `SubState=waiting` (a live cutover owns fstab during its repoint — two writers
  is a race).
- **No docker restart.** The drop-in is armed by `daemon-reload` only; it takes
  effect at the next `docker.service` start. The apply must never restart docker —
  that would bounce production to prove a point the state print already proves.
- **Success-path emit must NOT page.** `workspaces_luks_emit` hardcodes
  `op=workspaces-luks-drift`, and `sentry_alert.workspaces_luks_drift`
  (`apps/web-platform/infra/sentry/issue-alerts.tf`) pages on
  `event_frequency_count > 0` in 1h regardless of level — a success emit through
  it would page on every healthy reboot. Failure emits through it (fatal pages);
  success is a `logger -t workspaces-luks-reopen` journald line plus the unit's
  converge state.
- **Vector tag registration.** `SyslogIdentifier=workspaces-luks-reopen` is added
  to `vector.toml`'s `sources.host_scripts_journald` `include_matches` list —
  `terraform_data.journald_persistent` hashes vector.toml and re-delivers +
  reloads Vector in the same apply (the #6438 gap that kept probe FATALs dark).
- **Rotation coupling (#8632).** `doppler_service_token.workspaces_luks` rotates
  via `name`-change `-replace`; the token installer re-writes the
  `DOPPLER_TOKEN=` line on rotation. The reopen unit inherits the rotation for
  free through the shared env file — no extra coupling beyond `depends_on`.

### Attack Surface Enumeration (key-handling surface)

All paths the boot passphrase can touch:

- `doppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks`
  inside the reopen script — the R9-pinned form; the value is piped to
  `cryptsetup luksOpen --key-file -` on stdin, never argv (the pattern pinned by
  `workspaces-luks.tf` comments and `luks-monitor-token-refresh.sh`).
- Fallback hygiene: `secrets get` writes no on-disk cache (the ADR-198
  `--no-fallback` concern is a `doppler run` shape; `secrets get` leaves nothing
  under `$DOPPLER_CONFIG_DIR`).
- xtrace refusal at the top of the reopen script (exit 78), mirroring
  `git-data-luks-reopen.sh` and `luks-monitor.sh` (#7797).
- `UMask=0077`, `NoNewPrivileges=yes`, `LimitCORE=0`, `PrivateTmp=yes`,
  `RuntimeDirectory` + `RuntimeDirectoryPreserve=yes` on the unit — same shape
  as the git-data unit, measured on systemd 255/261.
- The env file is 0600 root and holds no passphrase — only the device pin and
  config name. `DOPPLER_TOKEN` stays in `/etc/default/luks-monitor`.
- Unchecked path, recorded: a `systemd-cryptsetup@workspaces.service` run
  outside the reopen unit still takes the interactive ask-password path —
  acceptable because it cannot produce a plaintext write (it can only reach
  what fstab names, and fstab names the mapper). `chattr +i` covers the
  residual.

## Hypotheses

Network-outage gate fired (feature description mentions SSH and emergency-mode
reachability). L3→L7 with verification artifacts:

1. **L3 firewall allowlist (the apply channel).** The installer's SSH leg rides
   the CF Tunnel SSH bridge (`.github/actions/cf-tunnel-ssh-bridge`), not a
   direct :22 dial — the GH runner egress IP is not in `var.admin_ips`.
   **Verified:** apply run 36425473000 (2026-09-28T13:01Z) ran
   `terraform_data.luks_monitor_install`'s SSH provisioners to completion and
   printed web-1's live `reboot-required=yes` — the channel is up at plan time.
2. **L3 DNS/routing + host identity.** `app.soleur.ai` is a direct CF-proxied A
   record to web-1's public IPv4 (no tunnel traversal); the bridge pins web-1's
   ECDSA host key from `apps/web-platform/infra/web-1-ssh-host-key.pub`
   (HostKeyAlias=web-1, ADR-237). **Verified:** the same apply run's state print
   proves both handshake and pin held.
3. **L7 TLS/proxy.** Not applicable to the defect (the outage shape is a boot
   that never reaches network); the verification path is apply-log and
   scheduled-workflow output, not an HTTPS symptom.
4. **L7 application layer.** `mnt-data.mount` failure semantics are the
   mechanism — measured fact, not hypothesis: `findmnt --fstab` prints the
   literal glob on web-1 today (issue's measured facts, run 36340195638).
   Post-delivery, the installer's own state print re-reads the same fields.

The L3 layers for the *outage itself* (web-1 unreachable post-reboot) are
verified by construction: the defect is a failed `local-fs.target`, measured in
fstab, not a transport fault — no firewall/sshd hypothesis is needed or pursued.

## Research Insights

**Premise Validation (Phase 0.6).** Cited refs verified: #9123 OPEN; #6604 OPEN
(the cutover — its tail warns not to reboot web-1, citing #9123); #6931 OPEN
(fresh-host boot unlock — explicitly not web-1's path); #9045 CLOSED by PR #9098
MERGED (the forensic print this plan's print contract extends);
`apps/web-platform/infra/cloud-init.yml` carries the #6604 by-id+`nofail` line
for fresh boots — web-1 predates it and cloud-init never re-runs
(`lifecycle{ignore_changes=[user_data]}`), so the live host needs the installer
channel, not the template; `cloud-init-git-data.yml`,
`soleur-host-bootstrap.sh` (`soleur-luks-structural-gate`),
`terraform_data.luks_monitor_install`, ADR-119, ADR-154, ADR-115, ADR-198 all
exist on `origin/main`. ADR-119's 2026-09-28 qualified note ("the fstab can name
the superseded plaintext volume" → measured false; the glob names nothing) is
already the corrected record — the proposed mechanism (Terraform-owned in-place
delivery) is the sanctioned channel, not a rejected alternative (ADR-154's
standing web-1 exception, re-examined and upheld in each of #8632/#8705/#8706/
#9045).

**Property List (Phase 0.6b).**

1. A web-1 reboot never wedges `local-fs.target` on a nonexistent `/mnt/data`
   device — fstab names a real device with `nofail`.
2. The LUKS mapper opens at boot with no console interaction — key fetched from
   Doppler at boot under the scoped token (ADR-198: never baked).
3. No code path can write user data to the root disk at `/mnt/data` while the
   mapper is absent — `RequiresMountsFor` ordering + immutable covered inode
   (ADR-119 §(e)).
4. All three parts land through the Terraform apply channel and are provable
   from its prints — no separate write channel, no host login for verification.

**Cut List.** None — every proposed mechanism maps to a property no existing
mechanism covers on web-1. Existing coverage is channel-shaped, not
property-shaped: `soleur-luks-structural-gate` buys (2-crypttab)+(3) but only
for *fresh* hosts (bake = dead code on web-1, ADR-119 §(e));
`git-data-luks-reopen.*` buys (2) on a different host/volume with a different
emitter; the shape ports, the artifact does not.
`terraform_data.luks_monitor_install` buys (4) and its forensic print already
reports the fstab/crypttab fields — it is the channel and the evidence
precedent, not the fix.

**Relevant file paths.**

- `apps/web-platform/infra/workspaces-luks.tf` —
  `terraform_data.luks_monitor_install` + `luks_monitor_token_install` (the
  delivery shape), `hcloud_volume.workspaces_luks` (the by-id pin source),
  `doppler_service_token.workspaces_luks` (the boot token).
- `apps/web-platform/infra/git-data-luks-reopen.sh` / `.service` /
  `-failure.service` / `.timer` — the reopen family to mirror (#8210; phase
  file, `RuntimeDirectoryPreserve`, `RestartMode=direct`,
  `RestartPreventExitStatus=3`, OnFailure reporter with `timeout 90` fallback
  arm).
- `apps/web-platform/infra/soleur-host-bootstrap.sh` —
  `soleur-luks-structural-gate` (crypttab + `chattr +i` + `RequiresMountsFor`
  drop-in, the fresh-host analogue).
- `apps/web-platform/infra/workspaces-luks-emit.sh` — `workspaces_luks_emit`
  (Sentry envelope; `op` hardcoded `workspaces-luks-drift` = the sole paging op).
- `apps/web-platform/infra/workspaces-cutover.sh` — the cutover owns fstab
  during a live run; the installer refuses while the dead-man is armed.
- `apps/web-platform/infra/luks-monitor-install.test.sh` — guard-suite shape
  (decode-and-execute behavioural arm, sha256-pinned public prints, mutation
  battery via env overrides).
- `apps/web-platform/infra/vector.toml` — `sources.host_scripts_journald`
  `include_matches.SYSLOG_IDENTIFIER` allowlist (`luks-monitor` present).
- `.github/workflows/apply-web-platform-infra.yml` — the `-target=` SSH apply
  list; `terraform-target-parity.test.ts` derives the covered set
  (`MIN_SSH_PROVISIONED=18` becomes 19).
- `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md`
  §4 — the "Boot-path re-canary (C15) — blocked on #9123" step flips to the
  post-fix reading.
- ADR-119 — §(e) needs a 2026-09-28 addendum recording the Terraform-channel
  delivery of the mount gate + boot unlock; ADR-154 gets a re-examination note
  with a fresh cx33 probe.

**Institutional learnings applied.**

- `2026-09-28-an-ssh-drop-without-a-pty-is-sigpipe-…` (issues [9045, 9123]):
  `$?` in an EXIT trap cannot see a signal death; guard suites must EXECUTE
  door semantics, not grep source — the new suite's behavioural arm runs the
  decoded bytes, not their shape.
- `2026-07-24-guest-luks-store-must-gate-consumer-on-mount-…`: gate the consumer
  on the mount (`RequiresMountsFor`, not a pre-run check) and pin fail-loud
  semantics (exit codes), never token presence.
- `2026-07-18-web-1-root-doppler-unit-needs-home-and-dedicated-token-…`: a root
  doppler unit needs `Environment=HOME=/root` and a readable token file; vector
  tags are file-only until `journald_persistent` re-delivers.
- `luks-monitor.test.sh` R9 guard: `doppler run|secrets download --config
  prd_workspaces_luks` is a RED — the pinned form is `secrets get --plain`.
- `2026-09-11-a-filer-with-no-honest-exit-…`: the population this guard set
  quantifies over is derived (the SSH-provisioned `terraform_data` set, the
  SYSLOG allowlist, the fstab/crypttab line shapes), never hand-kept lists.

**Related issues/PRs:** #6604 (cutover, OPEN), #6931 (fresh-host unlock, OPEN —
not this scope), #9045 CLOSED via #9098 (forensic print), #8706 (the installer
precedent), #8632 (token channel), #8210 (reopen-unit precedent), #6588/ADR-119
(the decision), ADR-115/ADR-198/ADR-154/ADR-237.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "crypttab entry modelled on cloud-init-git-data.yml" | git-data has **no** crypttab line — the reopen unit is the ADR-115-accepted equivalent; the crypttab line lives in `soleur-host-bootstrap.sh`'s structural gate | crypttab is declarative (`luks,noauto`), the unit owns the unlock; both land together |
| `chattr +i` "via a bind peek" | The baked gate's `if ! mountpoint -q` arm cannot reach the covered inode while the mapper is mounted; a non-recursive `mount --bind /` exposes it | Peek implemented as described; verified by `lsattr -d` inside the peek before umount and re-verified from the state print |
| ADR-119 2026-09-27 amendment: fstab entry "can be the superseded plaintext volume" | Measured false (run 36340195638): the literal glob names no device; PR #9098 corrected the record | Plan states the emergency-mode hazard, not the stale-volume hazard |
| "`nofail` and fail-closed are not in conflict" (ADR-119 §(e)) | True only once the gate is structural — the issue's own "obvious one-line fix is worse" argument | All three parts land atomically in one resource fire; the fstab writer refuses if the gate's pieces did not land |

## User-Brand Impact

- **If this lands broken, the user experiences:** the next web-1 restart —
  deliberate or unattended-upgrades — drops the site into emergency mode and
  every workspace stays offline until console repair; worst arm, the fstab lands
  without the unlock and user source code lands on the **plaintext root disk**
  while the app reports healthy.
- **If this leaks, the user's data is exposed via:** sole-copy workspace
  repositories written unencrypted to the root volume, defeating the published
  LUKS-at-rest claim; or a locked LUKS volume nothing can open (passphrase
  loss), which the escrow probe + `prd_workspaces_luks` key custody exist to
  prevent.
- **Brand-survival threshold:** `single-user incident` — one restart takes every
  user's workspace offline simultaneously.

CPO sign-off required at plan time before `soleur:work` begins (pipeline
context: recorded here; the review phase invokes
`soleur:engineering:review:user-impact-reviewer`).

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/workspaces-luks.tf` — new
  `resource "terraform_data" "workspaces_boot_unlock_install"`:
  - `depends_on = [terraform_data.luks_monitor_token_install,
    terraform_data.luks_monitor_install]` (token + probe channel first).
  - `triggers_replace` = sha256 over the four delivered files
    (`workspaces-luks-reopen.sh`, `.service`, `-failure.service`, `.timer`) plus
    the fstab/crypttab/gate writer locals — an edit to any delivered byte
    re-fires the installer (the file-hash precedent from
    `luks_monitor_install`, deliberately different from the token installer's
    token-hash-only trigger).
  - `connection`/`script_path`/`host_key` identical to the sibling (CF-bridge
    SSH, `/root/tf-boot-unlock-%RAND%.sh` so an uploaded script never lands in
    world-readable `/tmp`).
  - `lifecycle.precondition`: `hcloud_volume.workspaces_luks.id` must match
    `^[0-9]+$` (it is interpolated into a shell `printf` writing a root-owned
    file) — same shape as the DSN precondition.
  - Provisioners, in order: (1) read-only "before" print; (2) `file` deliveries
    (0755 script, 0644 units); (3) `/etc/default/workspaces-luks-boot` writer
    (0600, byte-count asserts); (4) crypttab writer (append-if-absent on
    `^workspaces[[:space:]]`); (5) fstab writer (backup → comment every
    existing non-comment `/mnt/data` line → append the mapper line → assert
    exactly one); (6) `docker.service.d` drop-in + `chattr +i` via bind peek;
    (7) daemon-reload + enable the units and the timer + one proof run of the
    reopen service (the mapper is open, so the run takes the `noop`-verified
    arm — exercising config/key/device/header/identity/target/mount phases
    end to end); (8) post-state print (`findmnt --fstab`, crypttab count, unit
    states, `lsattr -d` via a second peek, `systemd-analyze verify` on the
    units).
  - Freeze refusal (exit 17, same convention) at the head of every mutating
    step: refuse while `workspaces-luks-deadman.timer` is `SubState=waiting`.
- `apps/web-platform/infra/vector.toml` — add `"workspaces-luks-reopen"` to
  `sources.host_scripts_journald` `include_matches.SYSLOG_IDENTIFIER` (re-fired
  through `terraform_data.journald_persistent`, already in the SSH target set).
- `.github/workflows/apply-web-platform-infra.yml` — append
  `-target=terraform_data.workspaces_boot_unlock_install` to the
  SSH-provisioned apply list (after `luks_monitor_install`).
- New files under `apps/web-platform/infra/`: `workspaces-luks-reopen.sh`,
  `workspaces-luks-reopen.service`, `workspaces-luks-reopen-failure.service`,
  `workspaces-luks-reopen.timer`, `workspaces-boot-unlock.test.sh`.
- No new providers, no new variables, no new vendors. `MIN_SSH_PROVISIONED` in
  `plugins/soleur/test/terraform-target-parity.test.ts` is `>=` — no edit
  needed, and the union-coverage assertion now covers the new resource.

### Apply path

**(b) cloud-init + idempotent bootstrap (Terraform `terraform_data` SSH
provisioner)** — the established web-1 in-place channel under the ADR-154
exception. Expected downtime: **none** — every step is additive or rewrite-safe;
docker is never restarted; the only privileged mutation that could bite later
(the fstab rewrite) is verified in the same step it lands. Blast radius: one
resource fire on one host; a tainted fire re-delivers idempotently on the next
apply.

### Distinctness / drift safeguards

- web-1-only resource in `workspaces-luks.tf` (never `server.tf` — the parity
  sweep `web-host-provisioner-parity.test.sh` scans server.tf destinations and
  requires fresh-boot writers; web-1's unlock path is deliberately not the
  fresh-host path — #6931 owns that).
- `triggers_replace` hashing means a stale host drifts back into delivery on
  the next apply; nothing marks the host "done" permanently.
- A re-fired installer is idempotent: append-if-absent crypttab,
  rewrite-to-canonical fstab, `chattr +i` idempotent, unit enables idempotent.
- **ADR-154 re-examination is a plan task:** probe `GET /v1/datacenters`
  `.server_types.available` for `cx33` (id 115) at implementation time and
  record the result in the ADR-154 addendum + the apply evidence. If `cx33` is
  back in `hel1-dc2`, surface — the exception's expiry trigger has fired and
  the immutable-redeploy route must be re-weighed before this ships.

### Vendor-tier reality check

None — no new vendor resources; hcloud/doppler/betterstack/sentry resources are
unchanged. The new timer adds one Better Stack row family via journald→Vector
(an already-priced surface) and the failure emit reuses the existing Sentry
alert.

## Observability

```yaml
liveness_signal:
  what: "workspaces-luks-reopen.service converges active(exited) after each boot; failures page via workspaces_luks_emit into sentry_alert.workspaces_luks_drift; the daily luks-monitor.timer probe re-asserts mount/mapper identity"
  cadence: "per-boot (the unit) + bounded restart ladder (5 per 1h) + 15-min standing-retry tick while failed + daily at-rest probe"
  alert_target: "Sentry issue alert workspaces_luks_drift (email to issue_owners); journald → Vector → Better Stack source 2457081 under SYSLOG_IDENTIFIER=workspaces-luks-reopen"
  configured_in: "apps/web-platform/infra/workspaces-luks-reopen.service (+ -failure.service, .timer); apps/web-platform/infra/vector.toml; apps/web-platform/infra/sentry/issue-alerts.tf (existing alert)"

error_reporting:
  destination: "Sentry web-platform project via workspaces-luks-emit.sh (DSN from /etc/default/luks-monitor, the sole Sentry path on web-1); SOLEUR_WORKSPACES_LUKS_SEND_FAILED refusal rows when the channel itself is down"
  fail_loud: "an exhausted restart ladder emits one fatal envelope naming the failing phase (action=config|key|device|header|open|identity|target|mount|identity-mount|emit|unit); the apply itself goes red if any delivery or assert step exits non-zero"

failure_modes:
  - mode: "Doppler outage at boot → key fetch fails"
    detection: "restart ladder exhausts → -failure.service emits fatal action=key|unit; standing .timer re-attempts each 15min after the 1h start-limit window"
    alert_route: "sentry_alert.workspaces_luks_drift pages issue_owners"
  - mode: "mapper opens but mount identity wrong (stale fstab)"
    detection: "identity-mount phase dies → fatal emit; daily luks-monitor probe additionally asserts mount source"
    alert_route: "same Sentry alert + Better Stack row"
  - mode: "fstab/crypttab regression on the host"
    detection: "the installer's forensic/state prints on every apply re-read both fields; the target phase asserts exactly-one mapper fstab entry"
    alert_route: "apply run red + same Sentry alert"
  - mode: "docker resurrects the container while /mnt/data is not the mapper"
    detection: "structural — RequiresMountsFor holds docker.service, chattr +i makes the covered inode EPERM; there is no runtime detector because the write is prevented, not detected"
    alert_route: "prevention, not alerting — the verify arm is the apply-print peek plus the daily workspaces-luks-verify run"
  - mode: "host up, mapper closed LATER (post-boot luksClose or volume detach)"
    detection: "RESIDUAL (the same class git-data scope-outed): nothing re-attempts the reopen while the unit sits active(exited); the daily luks-monitor probe catches at next tick"
    alert_route: "daily probe fail → Sentry alert"

logs:
  where: "journald under SYSLOG_IDENTIFIER=workspaces-luks-reopen (Vector → Better Stack source 2457081); phase file + stderr log under RuntimeDirectory=workspaces-luks-reopen (host-local)"
  retention: "Better Stack per plan retention; journald per journald-soleur.conf persistent policy"

discoverability_test:
  command: "grep -c 'workspaces-luks-reopen' apps/web-platform/infra/vector.toml apps/web-platform/infra/workspaces-luks-reopen.service"
  expected_output: "1"
```

## Encryption Posture

```yaml
at_rest:
  - store: "hcloud_volume.workspaces_luks (the live /workspaces store; ledger row scripts/encryption-posture-ledger.json — no ledger change: this plan delivers the boot unlock for the EXISTING encrypted volume, not a new store)"
    mechanism: "luks"
    evidence: "apps/web-platform/infra/workspaces-cutover.sh cryptsetup luksFormat/luksOpen on MAPPER_NAME=workspaces; this plan adds the at-boot luksOpen path via workspaces-luks-reopen.sh"
    defends_against: "a seized/RMA'd disk; a raw volume snapshot; offline reads of the detached volume"
    does_not_defend: "a booted host (the mapper opens unattended by design — Doppler-delivered key); in-container compromise (the agent reads its own workspace); a leaked prd_workspaces_luks token (reads the inherited root set, measured — #6167)"
    disclosed_as: "docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md"
    live_verification: "available — workspaces-luks-verify daily + luks-monitor.timer"
in_transit:
  - connection: "web-1 → Doppler API (boot-time WORKSPACES_LUKS_KEY fetch)"
    enforced_at: "workspaces-luks-reopen.service ExecStart + workspaces-luks-reopen.sh (doppler CLI; TLS by the CLI's own transport; `secrets get` writes no on-disk fallback cache)"
    tls: "HTTPS, Doppler API"
    cert_verification: "on"
    does_not_defend: "a compromised Doppler project root (the scoped token reads the inherited root set — recorded, #6167)"
    disclosed_as: "not-publicly-claimed"
  - connection: "web-1 → Sentry store API (failure emit)"
    enforced_at: "apps/web-platform/infra/workspaces-luks-emit.sh direct curl"
    tls: "HTTPS"
    cert_verification: "on"
    does_not_defend: "n/a — telemetry, no user payload"
    disclosed_as: "not-publicly-claimed"
```

## Guard Contract

### Guard 1 — `workspaces-boot-unlock.test.sh` (the deliverable suite)

**Property.** A web-1 reboot converges to `mapper open + mapper mounted at
/mnt/data + app container gated on that mount`, and every failure class leaves a
named-phase fatal row — never a silent plaintext write.

**Assembly.** `terraform_data.workspaces_boot_unlock_install` in
`workspaces-luks.tf` (chokepoint: every web-1 in-place delivery flows through
the SSH `-target=` list in `apply-web-platform-infra.yml` — asserted by
`terraform-target-parity.test.ts` union coverage); the five delivered payloads
(`workspaces-luks-reopen.sh`, `.service`, `-failure.service`, `.timer`, and the
inline fstab/crypttab/gate writers); `vector.toml`'s SYSLOG_IDENTIFIER
allowlist; `/etc/default/luks-monitor` read-only consumption.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `nofail` from the written fstab line | RED |
| 2 | Remove the new resource's `-target=` line from the SSH apply | RED (target-parity) |
| 3 | Delete the `After=workspaces-luks-reopen.service` ordering from the docker drop-in | RED |
| 4 | Rewrite the key fetch to `doppler run --config prd_workspaces_luks` | RED (R9-class assert in the suite) |
| 5 | Replace the reopen script's `cryptsetup status` rc-4 open arm with an `isLuks`-style presence check that skips the backing-device identity assert | RED |
| 6 | Truncate the fstab writer so it appends a second `/mnt/data` line instead of asserting exactly-one | RED |
| 7 | Make the suite's own stub PATH fall through to the real `cryptsetup` (broken instrument — must score rc 2, never a catch) | instrument-fatal |

### Guard 2 — the §(e) structural mount gate (runtime control)

**Property.** While `/dev/mapper/workspaces` is not mounted at `/mnt/data`, no
container start and no implicit `mkdir` can put user data on the root disk —
the covered inode refuses mutation AND `docker.service` is ordered behind the
mount.

**Assembly.** `/etc/systemd/system/docker.service.d/10-workspaces-luks-mount.conf`
(`RequiresMountsFor` + `After=` — the chokepoint every `docker` start/resurrect
flows through), the `chattr +i` on the covered root-disk inode (the chokepoint
is the directory entry itself — survives even a bypassed unit file), and
`workspaces-luks-reopen.service` (the unlock path that satisfies the ordering).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `chattr -i` the peeked inode after delivery, then write through a re-run bind-peek probe of the covered path | RED (EPERM) |
| 2 | Remove `RequiresMountsFor` from the drop-in, leaving `After=` only | RED (ordering without the requirement is ordering only — a mount failure no longer gates docker) |
| 3 | Re-add a second `/mnt/data` fstab entry after the compliant line | RED (the fstab writer's exactly-one assert + the target phase both catch it) |
| 4 | Suite-side: neutralize the guard's own assert helper (the verify step always exits 0) | RED (dispatch-vacuity row — the suite reports 0 verified and fails) |

### Guard 3 — forensic/state print integrity (extends the #9045 contract)

**Property.** The apply log's boot-path facts (fstab `/mnt/data` fields, crypttab
`workspaces` count, unit states, `lsattr` peek result) are machine-readable,
guarded, and credential-free — the verification story cannot print secrets nor
fail the run on an absent value.

**Assembly.** The new `local.workspaces_boot_unlock_print` block (hashed into
`triggers_replace`), the `file`-provisioned unit set, and the shared deny list
inherited from `luks_monitor_forensic_print`'s shape (no raw fstab beyond the
exact-field select, no crypttab values, no journalctl, sha256-pinned).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Print a raw `/etc/crypttab` line instead of the `^workspaces` count | RED |
| 2 | Unguard a print command (drop `|| true`/`|| echo none`) so a missing binary fails the step | RED |
| 3 | Add a second member to the printed unit set and omit its enabled-state assert | RED |

## Architecture Decision (ADR/C4)

### ADR

Amend `knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md`
with a **2026-09-28 addendum**: §(e)'s delivery claim is superseded for the
mount gate too — the gate and the boot unlock reach web-1 through
`terraform_data.workspaces_boot_unlock_install`, not the cutover channel (the
#8706 precedent extended); the crypttab `noauto` divergence from the baked
`soleur-luks-structural-gate` is recorded with its rationale; the runbook's C15
step is unblocked. Also add a re-examination note to `ADR-154` (the standing
web-1 exception) recording the fresh `cx33` availability probe taken at
implementation time — the per-delivery pattern set by #8632/#8705/#8706/#9045.
No new ADR ordinal: this is the completion of an existing decision, not a new
one.

### C4 views

Enumeration per the completeness mandate — read of all three model files:

- (a) **External human actors:** none added — the point is that the boot unlock
  needs no human. (b) **External systems:** Doppler gains a new *runtime* read
  class on web-1 (every boot). The `doppler -> hetzner` edge already exists
  ("Injects the web-host boot credential") — its description gains the
  store-availability-of-every-boot clause, mirroring `gitDataStore -> doppler`'s
  #8210 wording. (c) **Containers/data-stores:** `workspacesVolume` and the
  `hetzner -> workspacesVolume` edge exist; the edge description gains the
  reopen/gate note (mounted by PID 1 via fstab after a Doppler-keyed luksOpen;
  covered-inode `chattr +i` + `RequiresMountsFor` are the §(e) gate).
  (d) **Relationships:** no new edges; no cardinality prose changes.
- Task: edit `model.c4` edge descriptions above; run
  `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`. No
  `views.c4`/`spec.c4` changes (no new elements).

### Sequencing

The ADR amendments land in the same PR (the decision is true at merge; the
*delivery* is verified post-apply — the addendum states exactly that, following
the #8706 addendum shape).

## Domain Review

**Domains relevant:** Engineering, Legal

### Engineering

**Status:** reviewed
**Assessment:** Infrastructure change touching the host boot path — the CTO
lens applied inline (no Task spawn available in this harness). Key engineering
concerns carried into the plan: ordering (`After=` on the reopen unit before
docker's `RequiresMountsFor` pull), the `noauto` crypttab divergence, the
two-writers byte-for-byte contract on `/etc/default/luks-monitor` (the reopen
unit reads, never writes), and the freeze-window refusal. Blast radius is
bounded to one host with no downtime expected during delivery.

### Legal

**Status:** reviewed
**Assessment:** The privacy/GDPR/data-protection documents assert LUKS at rest
in the present tense; this change makes the claim survive a restart. A restart
that dropped the mapper while docker served a bare root-disk dir would silently
break the at-rest claim — the §(e) gate is the compliance-relevant control. No
new processing of personal data; the `prd_workspaces_luks` token custody is
unchanged (ADR-119 §(f), #6167).

### Product/UX Gate

**Tier:** N/A — no UI surface. Mechanical scan of `## Files to Create`/`## Files
to Edit`: `.tf`, `.sh`, `.service`, `.timer`, `.test.sh`, `.toml`, `.yml`,
`.md` only — no `components/**`, `app/**/page.tsx`, `*.njk`, or flow artifacts.
**Decision:** skipped (no user-facing impact).
**Skipped specialists:** none.
**Pencil available:** N/A (no UI surface).

## Open Code-Review Overlap

- `#7098` (ci: audit `run:` bodies whose `set` omits `-e`) touches
  `apply-web-platform-infra.yml`. **Acknowledge:** this plan appends one
  `-target=` line inside an existing `run:` block — no new `run:` body, no
  `set` change. #7098's audit of that block is unaffected; noted so the audit
  sees the added line.

## Implementation Phases

### Phase 1 — Deliverables + installer resource

1.1. Add `apps/web-platform/infra/workspaces-luks-reopen.sh` — phase-tagged
 reopen script (`config → key → device → header → open → identity → target →
 mount → identity-mount → emit`), mirroring `git-data-luks-reopen.sh` with the
 workspaces substitutions: `MAPPER_NAME=workspaces`, `TARGET=/mnt/data`, key via
 `doppler secrets get WORKSPACES_LUKS_KEY --plain --config
 prd_workspaces_luks` (never `doppler run`/`download` on that config), emit via
 `workspaces_luks_emit` (sourced from `/usr/local/bin/workspaces-luks-emit.sh`)
 on failure only. Env seams `WORKSPACES_REOPEN_RUNDIR` /
 `WORKSPACES_REOPEN_DEVICE_WAIT` mirror the git-data test seams; operand guards
 on both (`assert_fixture_dir` shape).
1.2. Add `workspaces-luks-reopen.service` — `Type=oneshot`,
 `RemainAfterExit=yes`, `After`/`Wants=network-online.target`,
 `OnFailure=workspaces-luks-reopen-failure.service`, `Restart=on-failure` +
 `RestartMode=direct` + `RestartSec=60` + `StartLimitIntervalSec=1h` +
 `StartLimitBurst=5` + `RestartPreventExitStatus=3`, `Environment=HOME=/root`,
 `EnvironmentFile=-/etc/default/luks-monitor` +
 `EnvironmentFile=-/etc/default/workspaces-luks-boot`,
 `RuntimeDirectory=workspaces-luks-reopen` + `RuntimeDirectoryPreserve=yes`,
 `UMask=0077`, `NoNewPrivileges=yes`, `LimitCORE=0`, `PrivateTmp=yes`,
 `SyslogIdentifier=workspaces-luks-reopen`, `TimeoutStartSec=300`.
1.3. Add `workspaces-luks-reopen-failure.service` — the OnFailure reporter:
  reads `/run/workspaces-luks-reopen/action` + the unit's `Result`/
  `ExecMainStatus`/`ExecMainCode`/`NRestarts`, emits via `workspaces_luks_emit`
  with `WL_REASON=boot_unlock_failed:<phase>` and the discriminating `WL_*`
  fields populated from `systemctl show` + `findmnt` (doppler_reachable,
  mount_source, mapper_present). `timeout 90` wrapper like the git-data
  reporter; `PrivateTmp`, `LimitCORE=0`, `UMask=0077`, `Environment=HOME=/root`,
  same `EnvironmentFile` set.
1.4. Add `workspaces-luks-reopen.timer` — `OnUnitActiveSec=15min` +
 `OnBootSec=15min` + `RandomizedDelaySec=120`, no `Persistent=` (inert on
 non-OnCalendar — the git-data measurement), `WantedBy=timers.target`.
1.5. Add `terraform_data.workspaces_boot_unlock_install` to
 `workspaces-luks.tf` per the IaC section above, including
 `local.workspaces_boot_unlock_print` and the writer provisioners.
1.6. Add `-target=terraform_data.workspaces_boot_unlock_install` to the SSH
 apply in `apply-web-platform-infra.yml`.
1.7. Add `"workspaces-luks-reopen"` to `vector.toml`
 `sources.host_scripts_journald` `include_matches.SYSLOG_IDENTIFIER`.

### Phase 2 — The guard suite

2.1. `workspaces-boot-unlock.test.sh` — mirror `git-data-luks-reopen.test.sh` +
 `luks-monitor-install.test.sh`: STATIC arm (predicates over the script, the
 three units, the .tf block, the workflow `-target=` line, the vector.toml tag)
 + RUNTIME arm (stub-PATH execution: `cryptsetup`/`findmnt`/`mountpoint`/
 `systemctl`/`blockdev`/`realpath`/`doppler`/`workspaces_luks_emit` stubs
 append to a calls.log; order and phase-file rows) + reporter-body execution
 arm + a mutation battery mutating copies via `WBU_*` env overrides. Assert the
 exit-17 freeze refusal, the fstab exactly-one rule, the R9 key-fetch form, the
 `chattr`-via-peek ordering (peek → chattr → verify → umount, never `chattr`
 on the mounted path), and the success-path-not-paging property (emit is called
 only on failure; `noop` is silent).

### Phase 3 — Records and ledger

3.1. ADR-119 2026-09-28 addendum (mount gate + unlock delivered via
 terraform_data; crypttab `noauto` divergence; §(e) supersession).
3.2. ADR-154 re-examination note + fresh `cx33`/`hel1-dc2` probe recorded.
3.3. `workspaces-luks-cutover-6604.md` §4 rewrite: blocked-on-#9123 →
 delivered-by-#9123; the C15 proof itself is unchanged (one restart, then the
 read-only verify).
3.4. `workspaces-cutover.sh` stale `#9123` tail comment update (the "a restart
 currently takes the site down" note → post-fix wording).
3.5. `model.c4` edge-description updates (`doppler -> hetzner` every-boot
 clause; `hetzner -> workspacesVolume` gate note) + c4 tests.
3.6. Sweep `model.likec4.json`/`model.c4` for stale "via the cutover channel"
 §(e) wording — same sweep rule as a path rename.

### Phase 4 — Verification (apply-time, no host login)

4.1. `terraform plan` output + the installer's `before`/`after` prints land in
 the apply log: `findmnt --fstab -no SOURCE /mnt/data` ==
 `/dev/mapper/workspaces`, `crypttab-workspaces-lines=1`, units enabled,
 `lsattr -d` peek shows `i`, the proof run reports `noop` (all phases green on
 the live system).
4.2. A `workspaces-luks-verify` dispatch post-merge — the daily verifier's
 unchanged asserts re-confirm the live mount (delivery is mount-preserving).
4.3. The C15 restart proof is **out of scope for this PR** — it is the separate
 supervised step the runbook already names; this plan's job is making that
 restart survivable. (Recorded as a non-goal with the follow-through handle in
 Dependencies & Risks.)

## Files to Create

- `apps/web-platform/infra/workspaces-luks-reopen.sh`
- `apps/web-platform/infra/workspaces-luks-reopen.service`
- `apps/web-platform/infra/workspaces-luks-reopen-failure.service`
- `apps/web-platform/infra/workspaces-luks-reopen.timer`
- `apps/web-platform/infra/workspaces-boot-unlock.test.sh`

## Files to Edit

- `apps/web-platform/infra/workspaces-luks.tf` — new
  `terraform_data.workspaces_boot_unlock_install` +
  `local.workspaces_boot_unlock_print`
- `.github/workflows/apply-web-platform-infra.yml` — one `-target=` line
- `apps/web-platform/infra/vector.toml` — one allowlist entry
- `knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md` — 2026-09-28 addendum
- `knowledge-base/engineering/architecture/decisions/ADR-154-repair-the-credential-channel-not-the-host.md` — re-examination note
- `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md` — §4 unblock
- `apps/web-platform/infra/workspaces-cutover.sh` — stale `#9123` tail comment
- `knowledge-base/engineering/architecture/diagrams/model.c4` — two edge
  descriptions
- `knowledge-base/project/specs/feat-one-shot-9123-web1-reboot-unlock/tasks.md`
  (generated)

## Acceptance Criteria

- [ ] AC1 — `terraform_data.workspaces_boot_unlock_install` exists in
  `workspaces-luks.tf`, `depends_on` both monitor installers, `triggers_replace`
  covers every delivered payload and the writer locals, and appears in
  `apply-web-platform-infra.yml`'s SSH `-target=` list (target-parity green).
- [ ] AC2 — The fstab writer is idempotent and fail-closed: backups taken,
  every pre-existing non-comment `/mnt/data` line commented, exactly one
  `/dev/mapper/workspaces /mnt/data ext4 defaults,nofail 0 2` line results, and
  the step refuses (non-zero, distinct codes) when the post-edit table carries
  zero or two+ `/mnt/data` entries, when a live cutover freeze is armed, or when
  the mapper is not the live mount.
- [ ] AC3 — crypttab gains exactly one `^workspaces` line naming the by-id pin
  with `none` keyfile and `luks,noauto`, append-only-if-absent.
- [ ] AC4 — `workspaces-luks-reopen.{service,timer}` enabled; the proof run
  converges `active(exited)` on the live system (all phases pass, ACTION=noop)
  and prints into the apply log.
- [ ] AC5 — The failure path pages: an exhausted ladder triggers
  `-failure.service` once (RestartMode=direct), emitting `feature=
  workspaces-luks` + `op=workspaces-luks-drift` + `reason=boot_unlock_failed:*`
  via `workspaces_luks_emit`; success/`noop` emits nothing to Sentry.
- [ ] AC6 — `docker.service.d/10-workspaces-luks-mount.conf` carries both
  `RequiresMountsFor=/mnt/data` and `After=workspaces-luks-reopen.service`;
  `daemon-reload` ran; docker is never restarted by the installer.
- [ ] AC7 — `chattr +i` lands on the **covered** root-disk `/mnt/data` inode via
  non-recursive bind peek, verified by `lsattr -d` inside the peek and
  re-printed from the post-state step; the mounted mapper path is never
  chattr'd.
- [ ] AC8 — `workspaces-boot-unlock.test.sh` passes; its mutation battery drives
  every row of `## Guard Contract` RED on mutated copies (never the tracked
  file), the instrument self-test distinguishes rc 2 from a catch, and the
  suite is committed under `apps/web-platform/infra/` (auto-registered per
  ADR-252; added to `suite-shard-legs.tsv` if the hash-fallback would
  mis-shard).
- [ ] AC9 — The success path does not page: no emit path on ACTION=noop /
  reopened reaches `workspaces_luks_emit` (the sole paging op).
- [ ] AC10 — ADR-119 addendum + ADR-154 re-examination note (with a measured
  `cx33`/hel1-dc2 probe) committed; runbook §4 updated; the cutover tail's
  `#9123` comment no longer describes the pre-fix state.
- [ ] AC11 — Post-merge apply run prints the post-state: fstab mapper line
  (single), `crypttab-workspaces-lines=1`, reopen units enabled, peek `lsattr`
  shows `i`. (Verified from the run log, not the host.)

## Test Scenarios

- Given web-1's current fstab (literal glob line, no nofail), when the installer
  fires, then `/mnt/data` has exactly one fstab entry naming
  `/dev/mapper/workspaces` with `nofail`, and the glob line is preserved
  commented.
- Given the mapper open and mounted (today's live state), when the reopen
  service runs its proof start, then all phases pass and ACTION=noop.
- Given `workspaces-luks-deadman.timer` SubState=waiting (live freeze), when the
  installer fires, then every mutating step refuses with the distinct exit code
  and the resource taints for re-fire.
- Given a Doppler outage at boot (stubbed `secrets get` failure), when the unit
  ladder exhausts, then exactly one fatal emit reaches `workspaces_luks_emit`
  carrying the failing phase name, and the standing timer resumes retries after
  the start-limit window.
- Given fstab missing the mapper entry entirely, when the reopen script's target
  phase runs, then it dies `action=target` rather than mounting anywhere else.
- Given the mount already mounted (noop arm), when the emit phase is reached,
  then no Sentry envelope is sent (AC9 — success never pages).

## Success Metrics

- A post-merge apply run shows all AC11 print fields in their post-fix states.
- `workspaces-luks-verify` stays green on its next scheduled and dispatched
  runs.
- The `reboot-required=yes` flag on web-1 stops being a latent site-down
  trigger — the pending restart becomes a survivable event (the supervised C15
  proof itself remains a separate gated step).

## Dependencies & Risks

- **Risk — the Doppler read is now a store-availability dependency of every
  web-1 boot** (same trade #8210 accepted for git-data): a Doppler outage at
  boot leaves the mapper closed → `nofail` boot proceeds degraded, docker held
  by `RequiresMountsFor`, site down **but data-safe**, standing timer retries,
  alert pages. Residual: a multi-hour outage keeps the site down — accepted,
  recorded.
- **Risk — ADR-154 expiry.** If `cx33` returns in `hel1-dc2` before this ships,
  the in-place exception lapses and immutable redeploy must be re-weighed; the
  plan's own probe step records the answer at implementation time.
- **Risk — a mid-flight cutover.** The exit-17 refusal makes the installer and
  the cutover mutually exclusive writers of fstab/crypttab.
- **Follow-through:** the C15 supervised restart is the remaining proof;
  tracked by the runbook §4 edit (and #6931 remains the fresh-host sibling). If
  the plan's AC set is delivered but the restart never happens, the residual
  risk is an unproven boot path — the runbook names the gate state explicitly.
- **Dependency:** `doppler_service_token.workspaces_luks` must be live in
  `/etc/default/luks-monitor` (delivered 2026-09-24, #8632) — asserted by the
  proof run's `key` phase.
- **Pre-existing, out of scope:** `/dev/disk/by-label/workspaces_plain` (the
  dead-man rollback mount) and `workspaces_luks` label resolution — labels are
  written by no repo artifact observed; the crypttab line deliberately uses the
  by-id pin, and the dead-man's own fallback path is unchanged by this work.

## Non-Goals

- The supervised restart itself (C15 proof) — the runbook's separate gated step.
- #6931's fresh-host boot-unlock path (web-2/future hosts) — this is web-1-only.
- Rotating or re-scoping the `prd_workspaces_luks` token (#6167's audit scope).
- Changing the baked `soleur-luks-structural-gate` crypttab shape (the
  fresh-host divergence is recorded, not reconciled here — reconciles with
  #6931).
- Any app-code change; `docker.service` is never restarted by this delivery.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold
  fails deepen-plan Phase 4.6 — filled above.
- The fstab writer is the highest-severity step in the installer: it must be
  idempotent, it must comment (not delete) the superseded line, and it must
  refuse rather than leave zero or two `/mnt/data` entries — a mangled fstab on
  an unrebuildable host is worse than the bug it fixes.
- `chattr +i` applied to the *mounted* path marks the mapper's root inode, not
  the covered root-disk inode — the bind peek is not optional on web-1.
- `doppler run --config prd_workspaces_luks` in ANY new line is the CWE-522
  hole — the pinned form is `secrets get … --plain` (luks-monitor.test.sh R9).
- Emitting through `workspaces_luks_emit` on the success path pages on every
  healthy restart (`op` is hardcoded to the sole paging op) — success is
  journald-only.
- The reopen service must not use `RequiresMountsFor` itself (ordering-only
  `After=`, the #8706 measured shape); `RequiresMountsFor` belongs on
  `docker.service`, which is the consumer to gate.
- The proof run is safe BECAUSE the noop arm exists (mapper already open ⇒ no
  `luksOpen`, no mount) — but the script's `target`/`identity` asserts still
  run, making the proof real.

## References & Research

- Issue #9123 (measured facts: run 36340195638 forensic print; trigger fired:
  run 36425473000 `reboot-required=yes`).
- `apps/web-platform/infra/git-data-luks-reopen.{sh,service,failure.service,
  timer}` + `git-data-luks-reopen.test.sh` (#8210) — the reopen precedent.
- `apps/web-platform/infra/soleur-host-bootstrap.sh`
  `soleur-luks-structural-gate` — the fresh-host gate (crypttab + `chattr +i` +
  `RequiresMountsFor`).
- `apps/web-platform/infra/workspaces-luks.tf`
  `terraform_data.luks_monitor_install` + `luks_monitor_token_install`
  (#8706/#8632) — the delivery channel and forensic-print contract.
- ADR-119 §(e) + 2026-09-27/28 addenda; ADR-115 (reopen = crypttab/keyscript
  equivalent); ADR-198 (never bake the passphrase); ADR-154 (web-1 in-place
  exception); ADR-237 (bridge host-key pin); ADR-252 (suite auto-registration).
- `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md`
  §4 — the blocked C15 step this unblocks.
