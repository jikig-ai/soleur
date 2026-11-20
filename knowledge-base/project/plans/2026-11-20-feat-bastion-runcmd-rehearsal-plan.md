---
title: "feat(infra): rehearse the bastion's first boot under real cloud-init in the pinned ubuntu:24.04 image, and fix the two boot faults it finds"
date: 2026-11-20
slug: feat-bastion-runcmd-rehearsal
branch: feat-one-shot-12941-bastion-runcmd-rehearsal
issue: 12941
closes: 12941
type: feat
priority: p1
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# Rehearse the bastion's first boot before the birth

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

PR body, first line: "Merging this alone mutates no production resource: `hcloud_server.bastion` is outside the per-merge apply (OPERATOR_APPLIED_EXCLUSIONS) and does not exist yet." Then `Closes #12941`, `Ref #12866`, `Ref #9421`. Never `Closes` for #9421 or #12008.

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
Phase 2.8 was reviewed by the terraform-architect agent on 2026-11-20 (see `## Infrastructure (IaC)`).
Every `systemctl` token in this plan is either a quoted line of the template under test or a probe
the suite runs inside its own throwaway container. No step touches a real host.

## Overview

The soleur-bastion (ADR-327 step 2a, merged in #12873 at 2026-11-19T23:19Z) has never booted.
Its only guards are static: `apps/web-platform/infra/bastion.test.sh` pins bytes (SETTLE, EGRESS,
EMITTER, HOSTKEY, BUDGET). Review of #12873 found two faults those pins could not see, and found them
only by reproducing the boot by hand. Both are fixed on main. Nothing stops the next one. The owner's
go on the real birth (`bastion-host-create`, `plan_only=false`) waits on this issue.

This plan adds `apps/web-platform/infra/bastion-runcmd-rehearsal.test.sh`. The suite renders the real
template through `terraform console`, seeds the render as NoCloud user-data, and boots it in the
pinned ubuntu:24.04 image. systemd runs as PID 1 and the real cloud-init runs every stage: bootcmd,
write_files, cc_ssh, apt_configure and runcmd. A stub Sentry on its own container records the boot
trail over https. Mutation and fault-injection rows prove each fault class turns the suite red at the
stage that names it.

A plan-time prototype of that suite (kept in
`knowledge-base/project/specs/feat-one-shot-12941-bastion-runcmd-rehearsal/prototype/`) has already
run against the template on main. It found two boot faults, both fixed by this plan:

- **FAULT-A (latent image-dependency, CTO Q10).** The nftables baseline names `meta skuid systemd-timesync`. The template never installs
  `systemd-timesyncd`. It relies on the Hetzner image shipping it. The public Ubuntu noble cloud
  image does ship it (manifest checked 2026-11-20); Hetzner's image manifest is not public, so the
  dependency is unverified rather than known-broken. When the user is absent, `nft -f`
  rejects the **whole** baseline ("Error: User does not exist"), `nftables.service` fails,
  `bastion-egress.service` fails with result `dependency`, and the boot dies at `egress_load` with an
  unfiltered host. Fix: install `systemd-timesyncd` in the bastion's apt_install step.
- **FAULT-B (live).** The `egress_load` fatal's `detail` field carries systemd boilerplate ("...Failed to
  start bastion-egress.service...") instead of the reason. `tail -c 180` over the last five journal
  lines keeps the last 180 bytes, which are systemd's lines, not the script's
  `[bastion-egress] FAIL: lookup failed for ...` line. An nft refusal sits in `nftables.service`'s
  journal, which the capture never reads. The template comment claims the reason reaches the
  detail; it does not. Fix: select the detail lines by content from both unit journals.

## Research Reconciliation — Spec vs. Codebase

| Claim in the issue or brief | Reality on main (64217f4300) | Plan response |
|---|---|---|
| `/etc/nftables.conf` is written before `apt-get install nftables` (dpkg conffile prompt, rc=100) | Fixed in #12873: the baseline is `/etc/soleur/bastion-nftables.conf`, installed to `/etc/nftables.conf` at `egress_load`, after apt. Prototype M1 reproduced the fault (rc=100, "end of file on stdin at conffile prompt") when the old path is restored. | Not re-fixed. Row M1 pins it. |
| cloud-init's apt_configure rewrites the https sources | Fixed in #12873: `apt: preserve_sources_list: true`. Prototype: with it, the https file survives; without it, cc_apt_configure rewrites `ubuntu.sources` to `http://`. | Not re-fixed. Row M2 pins it. |
| "register it in scripts/test-all.sh" | Presence under `apps/web-platform/infra/` is registration (ADR-252). `scripts/test-all.sh` reaches infra suites only through `run-registered-suites.sh` (one `run_suite` of the runner). No per-suite entry exists or is needed. | No `test-all.sh` edit. The suite stays in the runner's unsharded set, so `bash scripts/test-all.sh infra` runs it locally (CTO Q6c). |
| "the egress script under a netns" | A container has its own network namespace. The allowlist must be tested on a path that leaves through a non-loopback interface, because `oif "lo" accept` passes all local traffic. | The stub and decoy run in separate containers on a per-row docker network, so probes cross `eth0`. |
| "run its runcmd stages (apt ...)" | The verbatim apt_install line (`curl linux-image-generic nftables`, with recommends) downloads 895 MB across 159 packages in the pinned image, measured with `apt-get install -y --print-uris`. | Fixture dummy debs satisfy `linux-image-generic` (see Proposed Solution). The apt line runs byte-for-byte. |
| Kernel settle is covered | `kernel-currency.test.sh` executes the web copy only. The bastion copy is pinned byte-equal by SETTLE and never executed. | Row B2 executes the reboot branch under real cloud-init. |
| The bastion's https apt sources work | No production host uses them: `cloud-init.yml` (web) keeps http sources. The pinned image has no `ca-certificates`. | Prototype proved `apt-get update --error-on=any` over https to archive and security: rc 0. The fixture installs `ca-certificates` (the real image ships it), declared in IMAGE_ASSUMED. |
| The fixture image stands in for the Hetzner image | The public noble cloud-image manifest (664 packages) ships `systemd-timesyncd`, `systemd-resolved`, `nftables` 1.0.9-1ubuntu0.1, `ca-certificates`, `curl`, `openssh-server`, `iproute2`, cloud-init 26.1 and `linux-image-virtual` (not `-generic`). With `nftables` pre-installed, the M1 conffile prompt does not reproduce. | Two baselines (CTO Q10): minimal for every row, plus row B1-C on a cloud-faithful baseline vendored from that manifest. |
| "TOOLING DEPENDENCY" counts in the runner header | Prose only, no test reads it, already stale (126 suites recorded, 210 now). | Add this suite's line; the wider recount is not this PR's. |

## Research Insights

### Premise Validation

Checked 2026-11-20. #12941, #12866, #9421, #12879, #12942, #12937 and #12008 are all OPEN. #12873 is MERGED
(2026-11-19T23:19:00Z). Both faults named in #12941 are fixed on main (see Reconciliation). The
premise "nothing rehearses the boot" holds: no suite executes the bastion's runcmd, and no workflow
gates the birth on a suite. `bastion-host-create.yml`'s birth-readiness interlock greps three literals
(`fresh_boot_ready`, `fresh_boot_not_ready_`, `cloud_init_complete`). Collision pre-check: the only
open PR naming #12941 is this branch's draft #12995. The four foreign `test-all.sh` processes belong
to unrelated worktrees (#12937 zot bridge, #12527).

### Property List (Phase 0.6b)

- P1. The rendered apt stage completes on the pinned image with the rendered write_files already in
  place, so no write_files path collides with a package conffile.
- P2. cloud-init's own apt_configure, given the rendered user-data, leaves the https `ubuntu.sources`
  intact.
- P3. `egress_load` loads the baseline plus the allow set. Allowlisted hosts are reachable on tcp/443
  for root and `_apt` only; everything else is dropped. `apt_path` succeeds through the loaded chain.
- P4. A healthy boot sends the stage trail ending in `fresh_boot_ready` and no fatal, over https,
  through the loaded chain.
- P5. A stage failure sends `fresh_boot_not_ready_<stage>` with a detail that names the reason. This
  includes `egress_load`, whose fatal must flush the ruleset first to get out.
- P6. The kernel-settle reboot branch re-runs runcmd once on the second boot and reaches
  `fresh_boot_ready`.
- P7. sshd stays masked, and the private address check passes when 10.0.1.70 is present.
- P8. Every user the nft rules name exists on the host at `egress_load`, installed by the template
  or listed in `IMAGE_ASSUMED` (the declared image contract).
- P9. The suite is reachable from `scripts/test-all.sh` locally and from CI on every infra change.
- P10. A restart of `nftables.service` re-applies the allowlist (`PartOf=`), and the refresh unit
  re-runs cleanly, as the template's own comments claim.
- P11. The render also boots on an image that already carries the packages it installs (the public
  cloud image ships `nftables` and `systemd-timesyncd`).

### Cut List (Phase 0.6b)

- A static lint that maps each `meta skuid <user>` to an installing package → P8 → already covered
  at runtime by row FA (the fixture image is minimal, so a new uninstalled user reds the boot).
- A second render path or a hand-written fixture of the template → P1-P5 → the real templatefile
  render (`bastion.test.sh` `render()` shape) already produces the bytes the host boots.
- Real-DNS rehearsal of the 185.12.64.1/2 resolver rows → P3 → not reachable from a container. Names
  are pinned with `--add-host`; declared as a divergence (CTO Q8).
- Gating `bastion-host-create` on this suite → owned by #12942 (CTO Q9).
- Plan review cuts (CTO Q14, Q18): the F1-D boot → P5 → the offline must-RED fixture with the real
  boilerplate string; the vendored baseline file, its parser and drift check → P11 → an inline array;
  the cross-file static budget assertion → (no property) → a deadline derived from the suite's own
  constants.

### Relevant files

- `apps/web-platform/infra/bastion-cloud-init.yml` — runcmd items: `runcmd_early` (the `_emit`,
  `on_err` and `trap on_err EXIT` arm), the ADR-326 apt item (`STAGE=apt_install` line), the
  kernel-settle item (`S=/var/lib/cloud/instance/sem/config_scripts_user`), the post-settle item
  (`STAGE=egress_load` ... `fresh_boot_ready`).
- `apps/web-platform/infra/bastion-egress.sh` — `die()` writes `[bastion-egress] FAIL: <reason>`; the
  private-range refusal (`10.*|127.*|169.254.*|192.168.*|172.1[6-9].*`...) forbids a stub on the
  docker default bridge (172.17/16), hence the 198.18.0.0/15 per-row networks.
- `apps/web-platform/infra/bastion.test.sh` — `render()` (the `terraform console` templatefile call
  with the fixture DSN `https://pubkey123@o1.ingest.de.sentry.io/4242`); SETTLE (`lib/bastion-lint.py`
  `settle()` substitutes `<pkgs>` for the package list via `PKG.sub`, so adding a package does not
  break it, and it requires only `linux-image-generic`); EMITTER; BUDGET (raw render `wc -c`
  <= 32,768, not gzipped; the prototype's render is 18,802 bytes).
- `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` — the `UBUNTU_BASE` pin (line 77) and the
  verdict construction (`FAILURES` array, not a counter, #7565).
- `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh` — Tier B precedent: reads
  `UBUNTU_BASE` from the git-data suite, builds and `docker commit`s a content-hash-tagged image
  through `gd_apt_install_bounded`, runs `docker run -d --privileged --cgroupns=private --tmpfs /run
  --tmpfs /run/lock --tmpfs /tmp <img> /lib/systemd/systemd`.
- `apps/web-platform/infra/lib/apt-bounded.sh` — `gd_apt_state_arm`, `gd_apt_install_bounded`,
  `gd_apt_out_tail`, `gd_apt_state_summary`.
- `apps/web-platform/infra/run-registered-suites.sh` — `PRIVILEGED_WHY` (~line 419), the
  `SOLEUR_INFRA_SHARD` branch (~line 452), `_SUITE_BOUNDS` (default 360 s, ~line 667).
- `.github/scripts/test/test-infra-suite-registration.sh` — `FIXED_JOB` and the PRIVILEGED arm
  (~lines 383-399) with `mask_check`.
- `.github/workflows/infra-validation.yml` — `deploy-script-tests` (legs, `timeout-minutes: 20`,
  worst passing leg 14.98 min), `deploy-script-tests-fixed` (`timeout-minutes: 15`, 7.1-11.4 min),
  `deploy-script-tests-done` (`needs` + `entries=( ... )`), setup-terraform pin
  `hashicorp/setup-terraform@5e8dbf3c6d9deaf4193ca7a8fb23f2ac83bb6c85 # v4.0.0` with
  `terraform_wrapper: false`.
- `apps/web-platform/infra/apt-bounded.test.sh` — the `SPECS=(...)` consumer census (~line 674).
- `scripts/guard-vacuity-floor.test.sh` — the single canonical `PROMOTED_FILES=` line; the deferral
  ledger is 47/47 (`MAX_DEFERRED=47`), so a new floor-bearing infra suite must be promoted.
- `knowledge-base/engineering/architecture/decisions/ADR-327-dedicated-bastion-web-hosts-are-identical-cattle.md`
  (Addendum 2026-11-18); `knowledge-base/engineering/operations/runbooks/bastion-host.md` (names no
  suite today).

### Prototype measurements (2026-11-20, this host, docker 29.9.2, terraform 1.17.2)

| Run | Result | Wall |
|---|---|---|
| Fixture image build (pinned base + systemd, cloud-init 26.2-0ubuntu1~24.04.2, ca-certificates, iproute2, python3, openssl, curl, openssh-server, dummy kernel debs, shims) | ok | 42-73 s |
| Healthy boot | `cloud-init status: done`, trail runcmd_start → egress_load → cloud_init_complete → fresh_boot_ready, 0 fatals | 52 s |
| Post-boot probes | root→stub:443 OPEN; nobody→stub:443, root→stub:80, root→decoy:443 CLOSED; an nftables.service restart re-runs bastion-egress (PartOf), set re-present; refresh rc 0 | <10 s |
| M1 conffile | fatal `fresh_boot_not_ready_apt_install` | 70 s |
| M2 preserve removed | sources rewritten to http; fatal `fresh_boot_not_ready_apt_update` | 39 s |
| F1 unresolvable ingest host | fatal `fresh_boot_not_ready_egress_load` reaches the stub | 51 s |
| F1-M flush removed | no fatal reaches the stub; status error | 72 s |
| FAULT-A (no timesyncd) | fatal egress_load, detail "Dependency failed for bastion-egress.service ..." | 37 s |
| FAULT-B fix candidate, F1 | detail `[bastion-egress] FAIL: lookup failed for nx-ingest.invalid (cloud-init); ...` | 54 s |
| FAULT-B fix candidate, nft refusal | detail `/etc/nftables.conf:16:48-60: Error: User does not exist ...` | 57 s |

Notes from the prototype that shape the suite:
- runcmd runs under `/usr/bin/dash` with `PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin`, the
  real instance-id, and the `config_scripts_user` semaphore present. A `/usr/local/sbin` shim
  therefore shadows `uname` and `reboot` for runcmd without touching the template.
- `nftables.service` is disabled after the package installs; `egress_load` enables it.
- A healthy boot with a minimal image works only because the template now installs what its rules
  name. The fixture image deliberately omits `systemd-timesyncd`.
- In both FAULT-A runs the refusal surfaced through the `bastion-egress.service` start line (result
  `dependency`), not through the nftables.service enable line. The work phase records which line
  fires; the CTO ruling adds a capture to the enable line either way.
- archive.ubuntu.com resolved to Cloudflare addresses from this host (104.20.28.246,
  172.66.152.176). Neither is in a range `bastion-egress.sh` refuses.

### Institutional learnings applied

- `2026-08-16-i-pinned-the-arm-that-already-failed-loudly.md` (#7565): each row asserts a marker only
  the real property produces (M1: the conffile-prompt line in `/var/log/cloud-init-output.log`, not
  just an `apt_install` fatal); the verdict reads an append-only `FAILURES` array, not a counter sum.
- `2026-10-02-a-shared-apt-budget-...` (#9379): the fixture image build uses `gd_apt_install_bounded`
  under one shared budget; the template's own apt runs inside the boot and is bounded by a per-boot
  wall cap in the harness.
- ADR-188: a skip turns on corroboration from a distinct, earlier probe, never on a missing success
  marker alone.
- `2026-07-27-my-battery-was-green-because-it-only-tested-the-two-endpoints-not-the-wire.md`: the
  stub sits across a real network hop and the probes cross the loaded chain.
- `2026-10-11-a-fake-that-ignores-its-selectors-lets-every-selector-mutation-pass.md` and
  `workflow-patterns/2026-10-08-stub-fidelity-masked-format-jsoneachrow.md`: the stub honours method
  `POST`, path `/api/4242/store/`, the `X-Sentry-Auth` header with `sentry_key=pubkey123`, and records
  the raw body; anything else is recorded as a rejected request and answered 4xx.
- `2026-04-19-cloud-init-packages-stage-silent-drop-audit.md`: assert each installed package with
  `dpkg -s` after the boot.
- `2026-10-19-a-suite-that-nests-its-own-scratch-...`: keep the work dir short under `$TMPDIR`
  (`mktemp -d "$TMPDIR/brh.XXXXXX"`).
- `2026-10-04-a-new-suite-is-invisible-to-repo-ratchets-until-tracked-...`: `git add` the suite before
  running the ratchet lints.
- `2026-11-07-a-required-shard-on-its-timeout-edge-made-the-merge-queue-a-coin-flip.md`: the suite
  goes to its own job (CTO Q6b), not onto a leg near its ceiling.
- `best-practices/2026-07-14-cloud-init-templatefile-escaping-and-ci-deploy-payload-testing.md`:
  new shell lines in the template must not use `${...}` unescaped or a literal `%{`.

### Functional overlap

Community registries (3 of 3 answered) hold no suite that boots a rendered cloud-init template under
real cloud-init in a container. Nearest: authoring guides (cloud-init-coder, terraform-skill) and an
nftables configurator. Nothing installed.

### Technical rulings

Every technical fork was ruled by the CTO agent on 2026-11-20 and is persisted in
`knowledge-base/project/specs/feat-one-shot-12941-bastion-runcmd-rehearsal/decision-challenges.md`
(Q1-Q18, Q6b, Q6c). The IaC review (terraform-architect, 2026-11-20) is folded into
`## Infrastructure (IaC)`. The prototype's first image passed `--no-install-recommends` and its
`build.sh` later added `systemd-timesyncd systemd-resolved`; the second image (`boot-reboot-row.sh`)
purged `systemd-timesyncd` again. The suite's minimal image must match the plan, not the prototype
(Kieran review). The prototype measured on terraform 1.17.2; CI pins `TERRAFORM_VERSION` 1.10.5, so
the work phase renders with 1.10.5 once before trusting the bytes.

## Proposed Solution

### 1. The suite: `apps/web-platform/infra/bastion-runcmd-rehearsal.test.sh`

**Header.** Property, what a green run does and does not prove, and the divergence list (CTO Q8). Each
divergence names the rule or stage it leaves untested:

| Divergence | Leaves untested |
|---|---|
| Names pinned with `--add-host` | the resolver rows `ip daddr { 185.12.64.1, 185.12.64.2 } udp/tcp dport 53` and real DNS under the loaded chain |
| NoCloud datasource, no metadata service | the `meta skuid 0 ip daddr 169.254.169.254 tcp dport 80 accept` row and the Hetzner datasource |
| Fixture CA appended to a bind-mounted `/etc/ssl/certs/ca-certificates.crt` | the real Sentry certificate chain |
| Dummy `linux-image-generic` 999:0.0.0-1 and `linux-image-0.0.0-1-generic` | the real kernel install and its 895 MB download |
| `/usr/local/sbin/uname` and `/usr/local/sbin/reboot` shims | the real reboot and the real kernel string |
| Dummy `priv0` interface carrying 10.0.1.70/32 | the hot-attached Hetzner private NIC and networkd |
| cloud-init from the archive (version printed at run time) | whatever cloud-init the Hetzner image bakes |
| IMAGE_ASSUMED packages installed into the fixture | whether the Hetzner image really ships them |

`IMAGE_ASSUMED` is one named array in the suite that is BOTH the minimal fixture's install list and
the declared contract with the image (ADR-327 amendment): `ca-certificates curl openssh-server
iproute2`, plus the users `root`, `_apt` (from apt) and `systemd-network` (from systemd), which B1
asserts exist. `systemd-timesyncd` is deliberately **not** in it.

**Preconditions.** `docker`, `docker info`, `terraform`, `python3` with PyYAML, `ssh-keygen`,
`openssl`. Absent locally: one loud `SKIP (loud): bastion-runcmd-rehearsal: <tool> absent` line, exit
0. Absent under `CI`: FAIL with the literal token `BRH_TOOL_ABSENT:<tool>` and exit 1 (CTO Q7). The
pin is read from `git-data-runcmd-rehearsal.test.sh` with the provision-unit `sed` shape; an
unreadable pin is a FAIL.

**Fixtures (all synthesized per run, never committed).** An ed25519 host key (`ssh-keygen`), a CA and
a server certificate with SAN `o1.ingest.de.sentry.io` and `decoy.example` (`openssl`), the fixture
DSN from `bastion.test.sh`. Work dir `mktemp -d "${TMPDIR:-/var/tmp}/brh.XXXXXX"`. Exactly one
top-level `trap ... EXIT`, which removes every container and network the run created (names carry
`brh-$$-`). Evidence survives a failure (CTO devex review): on a non-zero exit, or with
`BRH_KEEP_TMP=1`, the work dir (renders, captures, each container's `cloud-init-output.log` and
`journalctl -b` copied out before removal) is kept and its path printed; the CI job uploads it with
an `if: failure()` upload-artifact step (the legs' shape, `infra-validation.yml` per-suite log
upload). Every FAIL line names the row, the last stage in the capture, the detail text, and the last
20 lines of that row's `cloud-init-output.log`.

**Render.** `render <template> <egress-sh> <out> [sentry_ingest_host]` reproduces `bastion.test.sh`
`render()` (same variable map, same DSN, `private_ip="10.0.1.70"`), plus the optional ingest-host
override used by F1. Mutated copies go through an exact single-occurrence `mutate` helper; a
mutation that does not land is a FAIL, never a pass, and prints `BRH_ANCHOR_MISS:<row> anchor=<string>`
followed by "update the anchor in bastion-runcmd-rehearsal.test.sh; the template is not at fault", so
an editor who rewords a template line can tell a stale anchor from a regression. A header comment in
`bastion-cloud-init.yml` names the suite, the fast subset command and where the anchors live.

**Local subsets (CTO devex review).** `BRH_STATIC_ONLY=1` runs only the offline predicate self-tests,
S0 and S1 (seconds). `BRH_ROWS=B1,F1` boots only the named rows and ends
`bastion-runcmd-rehearsal: PARTIAL (...)`, never `PASS`. Under `CI`, either variable is refused with
`BRH_SUBSET_REFUSED` and exit 1, so a partial run can never be read as proof.

**Static pre-arm (seconds, before any boot; CTO Q1).**
- S0: the render starts with `#cloud-config` and `cloud-init schema -c` accepts it. Run inside the
  fixture image (`docker run --rm`), so the host needs no cloud-init.
- S1: the runcmd items joined with newlines (cloud-init's `shellify` of string items) pass `dash -n`
  inside the fixture image. It keeps one must-RED control (a copy with one unbalanced `fi` fails
  `dash -n`), so it stays non-vacuous under the promoted vacuity floor (CTO Q18c).

**Fixture images.** Built once per run from `UBUNTU_BASE` through `gd_apt_install_bounded
--no-install-recommends` (Kieran review: noble's `systemd` Recommends `systemd-timesyncd` and
`systemd-resolved`, verified with `apt-cache depends systemd` in the pinned image, so without the flag
the "minimal" image would silently gain the NTP user and row FA could not fail). Packages: `systemd
systemd-sysv dbus cloud-init python3 openssl` plus `IMAGE_ASSUMED`. The dummy debs are built with
`dpkg-deb --build` and installed through the same helper as `./<name>.deb` paths (a bare `dpkg -i`
matches `apt-bounded.test.sh`'s RAW_RE and reds its A10 check). Then the shims, `rm -rf
/var/lib/apt/lists/* /etc/ssh/ssh_host_*`, and `docker commit` to a tag derived from
`sha256(UBUNTU_BASE + package list + recipe text + ISO week)`, reused when present (provision-unit
shape; the week term bounds how stale a cached image's packages can be, since CI never has a cache).
A pre-arm check on the minimal image asserts `dpkg -s systemd-timesyncd` fails and `getent passwd
systemd-timesync` is empty; if either holds, FA and the FAULT-A claim are void and the suite FAILs
with `BRH_BASELINE_NOT_MINIMAL`. The cloud-faithful image is one more layer on the minimal one:
`gd_apt_install_bounded --no-install-recommends` of the `CLOUD_IMAGE_PKGS` array (below).
- `/usr/local/sbin/uname`: for exactly `uname -r`, reads `/etc/brh/uname-mode` (bind-mounted
  read-only per row). `settled` prints `0.0.0-1-generic`. `reboot` prints `0.0.0-0-generic` until
  `/var/lib/soleur/kernel-settle` exists, then `0.0.0-1-generic`. Any other argv `exec /usr/bin/uname`.
- `/usr/local/sbin/reboot`: appends a line to `/var/lib/brh/reboot.log` and asks systemd to power
  off, so the container stops and the harness can `docker start` it as the second boot.
- Kernel strings are synthesized (`0.0.0-N-generic`, the `kernel-currency.test.sh` convention).

**Per-row topology.** A docker network `brh-$$-<row>` on subnet `198.18.<k>.0/24` (a distinct `k` per
row, so rows run in parallel). Containers: the stub at `.20` (python `ThreadingHTTPServer`, https on
443 with the fixture cert, http on 80, both logging to a mounted `capture.log`; a `stub.ready` file
when bound), the decoy at `.21` (same server, its own log; started on B1's network only, the one
row that probes it), and the bastion at `.10`:
`docker run -d --privileged --cgroupns=private --tmpfs /run --tmpfs /run/lock --tmpfs /tmp
--add-host archive.ubuntu.com:<ip> --add-host security.ubuntu.com:<ip>
--add-host o1.ingest.de.sentry.io:198.18.<k>.20 --add-host decoy.example:198.18.<k>.21
-v <seed>:/var/lib/cloud/seed/nocloud:ro -v <bundle>:/etc/ssl/certs/ca-certificates.crt:ro
-v <mode>:/etc/brh/uname-mode:ro <img> /lib/systemd/systemd`. The archive and security addresses
are resolved host-side once per run with `getent ahostsv4`, refusing any private answer. After the
container answers `docker exec true`, the harness adds `priv0` (dummy) with `10.0.1.70/32`, and
again after every `docker start`. Meta-data is `instance-id: i-brh-<row>`.

**Boot wait.** Poll `cloud-init status` until `done` or `error`, capped at 150 s per boot (CTO Q14:
about 2x the slowest single boot measured, 73 s; B2 gets 150 s per boot). On the cap, record the last
stage in the capture, copy the evidence out, `docker rm -f`, and classify per ADR-188.

**Archive probe (ADR-188 corroboration).** Before any boot, the harness runs `curl -sS -o /dev/null
-w '%{http_code}' --max-time 15` against
`https://archive.ubuntu.com/ubuntu/dists/noble/InRelease` and
`https://security.ubuntu.com/ubuntu/dists/noble-security/InRelease` and keeps the output.

**Rows.** Each row's assertions read the stub's `capture.log` (one JSON body per line), the
container's `/var/log/cloud-init-output.log`, `cloud-init status --long`, and `docker exec` probes.
The trail predicate parses **every** line and checks order, level and tags; it never stops at the
first match.

| Row | Render / fixture | Must hold |
|---|---|---|
| B1 healthy | real template, `settled` | status `done`, `errors: []`; trail contains `runcmd_start`, `egress_load`, `cloud_init_complete`, `fresh_boot_ready` in that order; zero `level=fatal` events in the whole capture; every event has `host_name=soleur-bastion` and `host_id=i-brh-B1`; `ubuntu.sources` has exactly the two https URIs and no other `*.sources`/`*.list`; `dpkg -s` reports `curl nftables systemd-timesyncd` installed; `/etc/nftables.conf` equals `/etc/soleur/bastion-nftables.conf`; `nftables`, `bastion-egress`, `bastion-egress.timer` active and enabled; `ssh.service` and `ssh.socket` masked |
| B1-E egress probes (on B1) | — | set `soleur_egress_allow` holds the pinned archive and security addresses and the stub address; root→stub:443 OPEN (positive control); `setpriv --reuid=nobody` →stub:443 CLOSED; root→stub:80 CLOSED; root→decoy:443 CLOSED. Liveness controls first: the stub's port 80 and the decoy's 443 answer from inside their own containers, so CLOSED means dropped, not down |
| B1-P PartOf and refresh (on B1) | — | after an nftables.service restart, `bastion-egress` is active and the set again holds the stub address; a start of `bastion-egress-refresh.service` exits 0 |
| B2 reboot branch | real template, `reboot` | `/var/lib/brh/reboot.log` has exactly one line; the container stopped; after `docker start`, status `done`; trail `runcmd_start`, `kernel_reboot`, `runcmd_start`, `egress_load`, `cloud_init_complete`, `fresh_boot_ready` in order; zero fatals (no `second_mismatch`, no `reboot_returned`); `/var/lib/soleur/kernel-settle` exists |
| M1 conffile | baseline path mutated to `/etc/nftables.conf` | fatal `fresh_boot_not_ready_apt_install`; `cloud-init-output.log` contains `conffile prompt`; no `egress_load` event |
| M2 preserve removed | `apt:\n  preserve_sources_list: true\n` deleted | `ubuntu.sources` URIs are `http://` after the boot; a fatal at `apt_update`, `apt_install` or `apt_path`; no `fresh_boot_ready` |
| F1 egress_load fatal | real template, `sentry_ingest_host=nx-ingest.invalid` | fatal `fresh_boot_not_ready_egress_load` reaches the stub (so the flush ran); its detail contains `lookup failed for nx-ingest.invalid` |
| F1-M flush removed | F1 render with the `nft flush ruleset` line deleted from `on_err` | status `error` (the boot died) and the capture holds no fatal event and ends at `egress_load` |
| B1-C cloud-faithful baseline | real template, `settled`, the cloud-faithful image (`nftables`, `systemd-timesyncd`, `systemd-resolved` already installed) | the B1 trail, zero fatals and the https sources hold, and `apt_install` succeeded with the packages already present |
| FA missing NTP user | apt_install list mutated to drop `systemd-timesyncd` (minimal image) | fatal `fresh_boot_not_ready_egress_load`; detail contains `User does not exist` (the nft `Error:` path of the FAULT-B capture) |

M2 accepts three fatal stages because the plan-time run died at `apt_update` where plain http to
the pinned Cloudflare address failed. On a network where http works it would die at `apt_path`
instead (port 80 is dropped). The decisive assertion is the http rewrite; the fatal proves the boot
did not go green. This widens the CTO Q5 ruling (apt_update or apt_install) by `apt_path`, for that
reason.

**Parallelism.** Build the images once (minimal, then the cloud-faithful layer), then run the rows in
three waves of up to three: [`B1` (which also carries B1-E and B1-P), `B2`, `M1`], [`M2`, `F1`,
`F1-M`], [`FA`, `B1-C`]. That is 9 boots (B2 boots twice). Each row owns its network, stub and
capture dir. Plan-time timing for the reboot row: 87 s for both boots.

**Cloud-faithful package set (CTO Q10, Q18b).** An inline array `CLOUD_IMAGE_PKGS=(apt
ca-certificates cloud-init curl iproute2 nftables openssh-server systemd systemd-resolved
systemd-timesyncd)` with a comment naming the manifest (`noble-server-cloudimg-amd64.manifest`), its
serial and the retrieval date (2026-11-20). These are the manifest's packages that the template
depends on or that own a user, unit or conffile it touches. The manifest is never fetched; a refresh
is a reviewed edit of the array and its comment.

**Budget (CTO Q14).** The suite derives its deadline from its own constants: build cap 180 s plus,
for each wave, its worst row's boot count times the per-boot cap (150 s): 180 + 300 + 150 + 150 =
780 s. Changing a wave or a cap moves the deadline with it; there is no cross-file read. The CI job's
`timeout-minutes: 18` carries a comment citing that derivation. `_SUITE_BOUNDS` (900 s) binds local
runs only, because the CI job runs the suite directly. Rows not finished at the deadline FAIL with
`BRH_DEADLINE:<row>`, or SKIP only under the ADR-188 corroboration below.

**Privileged containers (CTO Q13).** `--privileged` stays (Tier B precedent). Never `--network host`;
bind-mount only fixture files; pinned digest; one line `NOTICE: bastion-runcmd-rehearsal starts privileged systemd containers` before the first boot.

**Offline predicate self-tests (no docker; run first).** The trail, detail and fatal-scan predicates
run against synthesized capture files:
- must-PASS: a canonical healthy trail; a healthy trail with extra info events between the stages;
  the B2 trail with `kernel_reboot` and a repeated `runcmd_start`.
- must-RED: `fresh_boot_ready` followed by a later fatal; a trail missing `egress_load`;
  `fresh_boot_ready` before `egress_load`; a wrong `host_name`; an empty file; a detail with only
  systemd boilerplate (the prototype's real FAULT-A detail, `Dependency failed for
  bastion-egress.service ... Failed to start bastion-egress.service ...`, replaces the cut F1-D boot,
  CTO Q18a); a body posted to a wrong path; a body without `sentry_key=pubkey123`.

**Verdict and anti-vacuity (ADR-193).** `cases` moves at every assertion call site. `FAILURES=()` is
append-only and the verdict reads it. `SKIPPED_ASSERTIONS` is denominated in assertions. The floor is
`passes + fails + SKIPPED_ASSERTIONS >= MIN_CASES`, and `passes + fails + SKIPPED_ASSERTIONS == cases`,
both reported by `printf` + `exit 1`. A `ROWS_BOOTED` count must equal the row registry length unless
the shortfall is a counted ADR-188 skip. If every boot row skipped, the terminal line is
`bastion-runcmd-rehearsal: SKIP (...)`, never `PASS` (CTO Q7). Under `CI` the skip ceiling is 2 rows
and B1 may never skip; breaching either prints `BRH_SKIP_CEILING` and exits 1 (CTO Q17), so the
required aggregator cannot go green on a run that booted nothing. Terminal lines:
`bastion-runcmd-rehearsal: PASS (<n> assertions, 0 failed)`, `... FAIL (...)`, `... SKIP (...)`,
`... PARTIAL (...)` (subset runs only, never under CI).

**Decline classification (ADR-188, CTO Q7).** A boot row is SKIPPED (one column-0
`SKIP (loud): <row> ...` line carrying the archive-probe output) only when its fatal stage is
`apt_update` or `apt_install` AND the archive probe failed. M1's expected `apt_install` fatal never
qualifies, because M1 also requires the conffile marker. Any other missing evidence, including a
boot that hits the 150 s cap with the probe healthy, is a FAIL. The test-only override that pins
`archive.ubuntu.com` to an unrouted address (Test Scenario 4) is refused under `CI`.

### 2. Template fixes: `apps/web-platform/infra/bastion-cloud-init.yml`

- **FAULT-A.** The apt_install line gains `systemd-timesyncd`:
  `... apt-get install -y -o DPkg::Lock::Timeout=300 curl linux-image-generic nftables systemd-timesyncd; ...`.
  SETTLE's comparison is unaffected (package list substituted before comparison), but SETTLE row 5
  in `bastion.test.sh` mutates the literal anchor `'curl linux-image-generic nftables;'`, which no
  longer occurs: its anchor becomes `'curl linux-image-generic nftables systemd-timesyncd;'` →
  `'curl nftables systemd-timesyncd;'` in the same commit. The terraform-architect notes a
  conflict with `chrony`/`ntp` if the image carried either; row B1 proves the install on the pinned
  image, and the Hetzner ubuntu-24.04 image is not expected to ship either.
- **FAULT-B.** In the post-settle item, one helper selects the reason by content from both journals,
  and both unit lines capture on failure:

  ```sh
  _egress_why() {
    journalctl --sync 2>/dev/null || :
    W=$(journalctl -b -u nftables.service -u bastion-egress.service --no-pager -o cat 2>/dev/null | grep -E '^\[bastion-egress\] FAIL:|Error:' | tail -2 | tr '\n' ' ' | head -c 180)
    [ -n "$W" ] || W="why=no_reason_line nft=$(systemctl show -p Result --value nftables.service 2>/dev/null) egress=$(systemctl show -p Result --value bastion-egress.service 2>/dev/null)"
    printf '%s' "$W" > $D
  }
  systemctl enable --now nftables.service || { _egress_why; exit 1; }
  systemctl enable bastion-egress.service
  systemctl start bastion-egress.service || { _egress_why; exit 1; }
  ```

  The selection is the shape the prototype verified for both the lookup failure and the nft refusal.
  `journalctl --sync` closes the race where the script's stderr is not yet stored when `systemctl`
  returns, and `-b` keeps a line from the pre-reboot boot (the journal persists across the
  kernel-settle reboot) out of the selection (Kieran review). The no-match branch writes the two
  units' `Result` values instead of systemd boilerplate (CTO Q15). `W` is a new shell variable; it
  collides with nothing in runcmd (the work phase greps the joined runcmd for `W=` first). The
  comment above it is rewritten to say exactly what the code does. No `${` or `%{` appears in the new
  lines (templatefile escaping).
- Both edits land before the bastion exists, so no replace is needed. After birth, any template edit
  is a replace delivered by #12879.

### 3. Registration and CI (CTO Q6b, Q6c)

- `apps/web-platform/infra/run-registered-suites.sh`: a `DEDICATED_JOB_WHY` map (one entry, this suite
  → "real cloud-init boots, ~5 min; runs in the bastion-boot-rehearsal job (#12941)"). When
  `SOLEUR_INFRA_SHARD` is set, the shard branch drops these suites from every k/N execute set. When it
  is unset (local runs, `test-all.sh`), they run like any suite. `_SUITE_BOUNDS` gains
  `"apps/web-platform/infra/bastion-runcmd-rehearsal.test.sh=900"`. The TOOLING DEPENDENCY header
  gains one line for this suite.
  The suite is also left out of `--enumerate` (as PRIVILEGED suites are), so
  `regenerate-shard-manifest.py` never tables a leg row no leg runs. It is also left out when the
  main-health-monitor's `test-infra` leg runs the unsharded runner: that leg sets an explicit env marker
  (`SOLEUR_INFRA_SKIP_DEDICATED=1`) and the runner prints one loud line naming `bastion-boot-rehearsal`
  as the owner (CTO Q16; that leg already runs at its timeout ceiling).
- `.github/scripts/test/test-infra-suite-registration.sh`: today's PRIVILEGED arm parses every
  `^  [x.test.sh]="..."` line in the runner without scoping it to the `PRIVILEGED_WHY` block
  (simplicity review), so a `DEDICATED_JOB_WHY` entry would be read as PRIVILEGED and demand a
  `sudo bash` step. Scope that parse to its block, then generalize the arm to take a job name and
  reuse it for `DEDICATED_JOB_WHY` → job `bastion-boot-rehearsal`, invoked by `bash <rel>` with no
  `continue-on-error:` and no step-level `if:` (`mask_check`). Treat DEDICATED like PRIVILEGED in the
  manifest and durations checks (~lines 299, 344). Add the job to Arm 4's `for need in "$JOB"
  "$FIXED_JOB"` loop (~line 430). Assert that main-health-monitor's `test-infra` leg sets
  `SOLEUR_INFRA_SKIP_DEDICATED=1`.
- `apps/web-platform/infra/run-registered-suites.test.sh`: the shard arm (shard behavior lives
  there): `--list` under `SOLEUR_INFRA_SHARD=k/4` for k=1..4 never contains the suite, the unsharded
  `--list` does, and the monitor marker drops it. (`--enumerate` exits before the shard branch, so it
  cannot carry this check; Kieran review.)
- `.github/workflows/infra-validation.yml`: job `bastion-boot-rehearsal` — `needs: detect-changes`,
  `if: needs.detect-changes.outputs.pr_duplicate != 'true'`, `runs-on: ubuntu-24.04`,
  `permissions: contents: read`, `timeout-minutes: 18` (CTO Q14, with the derivation comment); steps: pinned checkout (same SHA as the legs),
  pinned setup-terraform with `terraform_wrapper: false` and `terraform_version: ${{ env.TERRAFORM_VERSION }}`,
  `docker info >/dev/null` assert, `bash apps/web-platform/infra/bastion-runcmd-rehearsal.test.sh`,
  and an `if: failure()` upload of the kept work dir (pinned `actions/upload-artifact`, same SHA as the
  legs).
  `deploy-script-tests-done` adds the job to `needs:` and `entries=( ... "bastion-boot-rehearsal:$BASTION_REHEARSAL_RESULT" )`
  with the matching env. No Hetzner, Doppler or Sentry credentials are bound in the job.
  The aggregator's `cancelled)` branch keeps the LAST non-self entry as `other_result`, so with three
  entries the supersession-vs-timeout ruling would depend on entry order (Kieran review): rewrite it to
  classify "all entries cancelled" (supersession) versus "any sibling concluded" (a timeout kill).
- `plugins/soleur/test/deploy-script-tests-aggregator-diagnosis.test.sh`: `run_body` exports only
  `MATRIX_RESULT` and `FIXED_RESULT`; add the third result, the new cancelled rows (all cancelled; one
  sibling concluded in each position), and the W wiring row for the new env.
  `.github/scripts/test/test-infra-suite-registration-mutations.sh` and
  `tests/scripts/test-main-duplicate-skip.sh` also read `deploy-script-tests-done`: re-run both; the
  new job carries the `pr_duplicate` conjunct the latter pins.
- `.github/workflows/main-health-monitor.yml`: the `test-infra` leg sets `SOLEUR_INFRA_SKIP_DEDICATED=1`.
- `apps/web-platform/infra/apt-bounded.test.sh`: one `SPECS` line for the suite. The declared-unmounted
  and mounted counts are derived from the suite's final text with the census's own grammar (boot, stub,
  decoy and static-check containers unmounted; each `gd_apt_install_bounded` image-build site mounted,
  which is two sites if the two images are built by separate `docker run`s), never hand-counted.
- `scripts/guard-vacuity-floor.test.sh`: add the suite to the canonical `PROMOTED_FILES=` line; its
  floor must score FIRES under the gate's floor mutation. `MAX_DEFERRED` is not raised.
- `apps/web-platform/infra/suite-shard-legs.tsv` / `suite-durations.tsv`: untouched, because the suite
  is out of `--enumerate`; `python3 scripts/regenerate-shard-manifest.py --group infra --incremental`
  (dry run) must report no change.

### 4. Records

- ADR-327: an addendum dated 2026-11-20 (#12941): step 2a needs a runtime first-boot rehearsal
  alongside the byte pins; the template installs every user its nft rules name; `IMAGE_ASSUMED` in the
  suite is the declared contract with the image; the minimal and cloud-faithful baselines and why both
  exist; the QEMU/KVM alternative and its reopening trigger (CTO Q11); the birth gate stays #12942's.
- `knowledge-base/engineering/operations/runbooks/bastion-host.md`: one paragraph naming the suite and
  the CI job as the pre-birth boot evidence, and the local command.
- A comment on #12942 stating that its gate should require `bastion-boot-rehearsal` green on the birth
  SHA (CTO Q9).

## Files to Create

- `apps/web-platform/infra/bastion-runcmd-rehearsal.test.sh`

## Files to Edit

- `apps/web-platform/infra/bastion-cloud-init.yml` — FAULT-A package, FAULT-B capture and comment.
- `apps/web-platform/infra/run-registered-suites.sh` — `DEDICATED_JOB_WHY`, shard exclusion, `_SUITE_BOUNDS`, header line.
- `.github/scripts/test/test-infra-suite-registration.sh` — scoped PRIVILEGED parse, the generalized job arm, manifest/durations treatment, Arm 4's `need` loop.
- `apps/web-platform/infra/run-registered-suites.test.sh` — the shard / unsharded / monitor-marker arm.
- `.github/workflows/infra-validation.yml` — job `bastion-boot-rehearsal` (with failure artifact), aggregator `needs`/`entries`/env and the `cancelled)` classification.
- `plugins/soleur/test/deploy-script-tests-aggregator-diagnosis.test.sh` — third result, cancelled rows, wiring row.
- `.github/workflows/main-health-monitor.yml` — `SOLEUR_INFRA_SKIP_DEDICATED=1` on the `test-infra` leg.
- `apps/web-platform/infra/apt-bounded.test.sh` — `SPECS` line.
- `scripts/guard-vacuity-floor.test.sh` — `PROMOTED_FILES` entry.
- `knowledge-base/engineering/architecture/decisions/ADR-327-dedicated-bastion-web-hosts-are-identical-cattle.md` — addendum.
- `knowledge-base/engineering/operations/runbooks/bastion-host.md` — pre-birth evidence paragraph.
- `apps/web-platform/infra/bastion.test.sh` — SETTLE row 5's anchor (FAULT-A). The pin census for the FAULT-B line (`grep -rn -F -e 'journalctl -u bastion-egress' -e 'tail -c 180'`) found no other pin of the bastion's lines; re-run it after the edit. `lib/bastion-lint.py` only if `bastion.test.sh` reds on the new bytes (fix the row, never the floor).

Not edited: `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh` (prefix-selected), the C4 model
(see Architecture Decision), `bastion.tf`, `suite-shard-legs.tsv` and `suite-durations.tsv` (the
suite is out of `--enumerate`).

## Open Code-Review Overlap

Three open `code-review` issues mention files this plan edits; none concerns the change.
- #8890 (deploy-script-tests K=4 matrix review, names `run-registered-suites.sh`): Acknowledge. It
  tracks matrix design follow-ups; this plan adds an exclusion kind and does not touch the matrix.
- #8487 (capability-gate corpus follow-ups, names `run-registered-suites.sh`): Acknowledge. Different
  concern (capability gates).
- #8881 (test-scripts K=6→K=7 rebalance, names `suite-shard-legs.tsv`): Acknowledge. The scripts-group
  manifest, not infra legs.

## Implementation Phases

1. **RED first (cq-write-failing-tests-before).** Write the suite against the template on main with
   the FAULT-B detail predicate and the FA row. Expected on main: B1 RED on the fixture without
   `systemd-timesyncd` (FAULT-A), F1 detail RED (FAULT-B). Record both outputs.
2. **Fix the template** (FAULT-A, FAULT-B). Re-run: all rows GREEN, the mutation rows RED where
   designed. Run `bastion.test.sh` and fix any row the new bytes trip.
3. **Registration and CI.** Runner map, registration arms, workflow job, aggregator, SPECS, PROMOTED.
   Run `bash .github/scripts/test/test-infra-suite-registration.sh`, `bash apps/web-platform/infra/apt-bounded.test.sh`,
   `bash scripts/guard-vacuity-floor.test.sh`, `bash apps/web-platform/infra/run-registered-suites.test.sh`
   and the ratchet lints (`lint-shell-capture-exit`, `fixture-relative-assert`, `fixture-dir-operand-assert`)
   after `git add` of the new suite. Grep for suites that pin `infra-validation.yml`'s job list or
   `deploy-script-tests-done`'s `needs` and update them.
4. **Records.** ADR-327 addendum, runbook paragraph, `c4-count-parity` run, comment on #12942.
5. **Measure.** Two full local runs (cold and warm image cache) and the first CI run; record wall
   times in the PR body against the 780 s deadline, the 900 s bound and the 18-min job timeout.

## Infrastructure (IaC)

### Terraform changes

None. `bastion.tf` is not edited. The template is consumed only by `hcloud_server.bastion.user_data`
through `templatefile`. No provider, variable or secret is added.

### Apply path

(a) cloud-init-only, not yet provisioned. `hcloud_server.bastion` is listed in
`tests/scripts/lib/bastion-resources.txt` and in `OPERATOR_APPLIED_EXCLUSIONS`, so the per-merge apply
never reaches it. Merging provisions nothing. The edited template takes effect at the first
reviewer-gated `bastion-host-create` dispatch, which must run from a main that contains this fix. Blast
radius at merge: zero cloud resources. After birth, `user_data` is not in `ignore_changes` (only
`ssh_keys` is) and the provider stores its hash, so any later template edit is a replace delivered
by #12879. `user_data` must not be added to `ignore_changes` to avoid that.

### Host fan-out

None. No `terraform_data` SSH provisioner is added or touched.

### Distinctness / drift safeguards

The new CI job binds no Hetzner, Doppler or Sentry credential and runs no `plan` or `apply`; it renders
locally through `terraform console` with fixture inputs only. No `import`, no `-target` of bastion
addresses outside `bastion-host-create`, no host steps. The `cx23` literal is not touched.

### Vendor-tier reality check

No vendor resource is created, so no tier gate applies.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-327 with an addendum (2026-11-20, #12941), not a new ADR: a runtime first-boot rehearsal is
required for step 2a alongside the byte pins; the template installs every user its nft rules name;
`IMAGE_ASSUMED` in the suite is the declared contract with the image; the birth gate is #12942's.
Alternatives recorded in the addendum: booting the real Ubuntu cloud image under QEMU/KVM with a
NoCloud seed, rejected for now (CTO Q11: still not Hetzner's image, ~600 MB per run, `/dev/kvm`
unverified on the runner class); it reopens on a fault the container provably cannot reproduce, or
on confirmed `/dev/kvm` on ubuntu-24.04 runners with a cached image.

### C4 views

No C4 impact. Checked at plan time across `model.c4`, `views.c4` and `spec.c4`: the bastion container
(`model.c4` `bastion = container "Bastion"`), its `github -> bastion` and `bastion -> sentry` edges, and
the `views.c4` include line. The change adds no actor, external system, container, store or
relationship, and falsifies no description ("NTP for systemd-timesync" and "tcp/443 to the apt
mirrors and Sentry ingest for root and _apt" stay true). The CI job is test infrastructure, not a
modeled element. The work phase reads all three files in full and backs this line with a green
`bash plugins/soleur/test/c4-count-parity.test.sh`.

### Sequencing

The addendum describes the state this PR ships; nothing is soak-gated.

## Encryption Posture

```yaml
at_rest: []   # no persistent store is introduced; the suite's fixture state lives in a per-run work dir removed by its EXIT trap
in_transit:
  - connection: soleur-bastion -> archive.ubuntu.com / security.ubuntu.com (apt)
    enforced_at: apps/web-platform/infra/bastion-cloud-init.yml write_files /etc/apt/sources.list.d/ubuntu.sources (URIs https://) + apt preserve_sources_list
    tls: https (apt's https method, system CA store)
    cert_verification: on
    does_not_defend: a compromised mirror signing key (apt's Signed-By keyring check is the separate integrity layer); traffic analysis of which packages are fetched
    disclosed_as: not-publicly-claimed
  - connection: soleur-bastion -> Sentry ingest (boot-stage events)
    enforced_at: apps/web-platform/infra/bastion-cloud-init.yml runcmd _emit (curl --proto =https --tlsv1.2, no -k)
    tls: https, TLS 1.2 minimum
    cert_verification: on
    does_not_defend: a leaked DSN being used to forge events; the event body is visible to Sentry
    disclosed_as: not-publicly-claimed
```

Neither connection is new; rows B1 and M2 assert that the apt connection stays https at boot.

## Observability

```yaml
liveness_signal:
  what: the bastion-boot-rehearsal job result in infra-validation.yml, rolled into deploy-script-tests-done; the suite's terminal line "bastion-runcmd-rehearsal: PASS|FAIL|SKIP"
  cadence: per pull_request and push touching apps/*/infra/** (the workflow's existing path filter)
  alert_target: the required deploy-script-tests-done check on the PR; notify-main-failure on main
  configured_in: .github/workflows/infra-validation.yml (job bastion-boot-rehearsal)
error_reporting:
  destination: on the real host, the Sentry project behind TF_VAR_sentry_dsn (prd_terraform SENTRY_DSN) via the runcmd _emit; in CI, the job log
  fail_loud: "fresh_boot_not_ready_<stage>" fatal events with a detail naming the reason (FAULT-B fix); the suite's "FAIL: <row> ..." lines
failure_modes:
  - mode: a template edit breaks a boot stage
    detection: rows B1/B2 go red with the stage name from the stub capture
    alert_route: the required check on the PR
  - mode: the egress_load fatal's detail stops naming the reason
    detection: rows F1 and FA (detail predicates) and the offline must-RED boilerplate fixture
    alert_route: the required check on the PR
  - mode: the rehearsal silently stops booting (all rows skipped, or zero rows run)
    detection: the ROWS_BOOTED identity and the ADR-193 floor; an all-skip run ends SKIP, never PASS
    alert_route: the required check on the PR; SKIP (loud) lines in the job log
  - mode: the suite drifts onto a matrix leg or off the dedicated job
    detection: the two test-infra-suite-registration.sh arms
    alert_route: the required check on the PR
logs:
  where: GitHub Actions log of the bastion-boot-rehearsal job; on the real host, journald and /var/log/cloud-init-output.log, read only through the Sentry boot trail
  retention: GitHub Actions default log retention for the repo
# Verified 2026-11-20: prints 0 on main and 1 on the prototype's fixed template (fixb.tpl).
discoverability_test:
  command: grep -c -F -e "-u nftables.service -u bastion-egress.service" apps/web-platform/infra/bastion-cloud-init.yml
  expected_output: "1"
```

## Task Design

```yaml
tasks:
  - task: bastion-boot-rehearsal (CI job in infra-validation.yml)
    trigger: pull_request and push on the workflow's existing apps/*/infra/** path filter, after detect-changes
    services: reads the repo checkout; pulls the pinned ubuntu image and the Ubuntu archive; writes nothing outside the runner
    next: deploy-script-tests-done aggregates its result
    human_reentry: re-run the job from the Actions UI or push a commit; it holds no state between runs
    dedupe: the image tag is content-derived, so a rebuild happens only when the base pin or recipe changes; detect-changes' pr_duplicate output skips duplicate push runs
    source_dedupe: not a ticket source
```

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. The bastion is an internal
  management host that serves no user. A broken suite either blocks infra PRs (a false red) or lets
  a boot fault through to the birth (a false green), where `bastion-host-create` powers the dark host
  off.
- **If this leaks, the user's data is exposed via:** no user data path. The suite uses synthesized
  keys, a fixture DSN and a per-run CA, and its CI job binds no credential.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the host carries no user data and nothing dials it in step
  2; the worst real outcome of a fault is a powered-off host and a delayed birth.
- `threshold: none, reason: the touched paths are a not-yet-born management host's first-boot template and its CI test; no user-facing service, credential or data flows through them.`

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** The CTO agent ruled Q1-Q9, Q6b and Q6c (decision-challenges.md). The terraform-architect
review confirmed apply path (a), zero blast radius at merge, the replace semantics after birth, the
templatefile escaping rules, and that BUDGET measures the raw render.

No other domain is touched: no UI surface, no user data, no vendor, no copy, no pricing.

## Guard Contract

### Guard 1 — bastion boot rehearsal

**Property.** The rendered bastion user-data, booted by real cloud-init in the pinned image, reaches
`fresh_boot_ready` with no fatal, and each named boot fault class makes it report
`fresh_boot_not_ready_<stage>` (or the named missing evidence) for the stage that owns the fault.

**Assembly.** One chokepoint in, one out. In: `render()` (terraform `templatefile` of
`bastion-cloud-init.yml` with `bastion-egress.sh` base64-embedded); every row, mutated or not, enters
the boot through it and the NoCloud seed. Out: the trail, detail and fatal-scan predicates over the
stub's `capture.log`, plus the post-boot `docker exec` probes; every row's verdict flows through
`fail()` into `FAILURES`. The row registry (one array) is what `ROWS_BOOTED` is compared against.

Rendered arms. The template has one interpolation that changes control flow: `sentry_dsn`. Every row
renders a non-empty DSN; F1 and F1-M also override `sentry_ingest_host`. The empty-DSN arm
(`bastion.tf`'s precondition admits `""`) is not booted: with it, `_emit` sends nothing and
`bastion-egress.sh` refuses an empty `SENTRY_INGEST_HOST`, so the boot dies at `egress_load` in
silence and `bastion-host-create`'s strict reader powers the host off. That arm is the birth
interlock's to refuse, recorded here so it is a stated exclusion, not a gap.

Boot paths covered. Every path that boots this payload boots a template that passed this job: the
birth (`bastion-host-create`), the future replace (#12879) and an untargeted local apply all consume
`main`, and `deploy-script-tests-done`, which now requires this job, gates every merge to `main` that
touches `apps/*/infra/**`. The aggregator is already a required check, so no ruleset or synthetic-check
change is needed.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Template: baseline written at `/etc/nftables.conf` (M1) | RED at `apt_install`, conffile marker present |
| 2 | Template: `preserve_sources_list` removed (M2) | RED: http sources, apt fatal |
| 3 | Template: `nft flush ruleset` removed from `on_err` (F1-M) | RED: no fatal reaches the stub |
| 4 | Template: FAULT-B capture reverted to the old `tail -c 180` | RED: F1's detail predicate (and its offline boilerplate fixture) |
| 5 | Template: `systemd-timesyncd` dropped from apt_install (FA) | RED: `User does not exist` |
| 6 | Suite: the row registry emptied, or `boot_row` returns before `docker run` (own dispatch) | RED: ROWS_BOOTED != registry, floor fails |
| 7 | Capture: a compliant `fresh_boot_ready` followed by a second event that is fatal (second member) | RED: the fatal scan reads every line |
| 8 | Order: `fresh_boot_ready` moved above `egress_load` in the template's post-settle item | RED: trail order |
| 9 | Suite: the minimal image gains `systemd-timesyncd` (e.g. `--no-install-recommends` dropped) | RED: `BRH_BASELINE_NOT_MINIMAL` |
| 10 | Suite: a `BRH_ROWS` subset run under `CI` | RED: `BRH_SUBSET_REFUSED` |

**Harness rows.**
- The stub stops writing `capture.log` → B1 RED (an empty capture is never a pass).
- The stub accepts any path or a missing `X-Sentry-Auth` → the offline self-test with a wrong-path
  body goes RED.
- The decoy is not started → B1-E's liveness control fails, so a CLOSED probe cannot pass vacuously.
- must-PASS, non-canonical: the B2 trail (extra `kernel_reboot`, repeated `runcmd_start`) and a
  healthy trail with interleaved info events both pass.

**Anchor.** The expected stage literals come from `bastion-host-create.yml`'s birth-readiness interlock
list and `fresh-host-boot-trail.sh`'s strict reader, not from the template the suite boots, so one
diff cannot rename a stage in the template and in the expectation. The pinned image comes from
`git-data-runcmd-rehearsal.test.sh`, which rule-audit.yml watches.

### Guard 2 — dedicated-job registration

**Property.** The rehearsal suite runs in job `bastion-boot-rehearsal` unmasked, never in a k/N matrix
leg, and always in the unsharded local runner.

**Assembly.** `DEDICATED_JOB_WHY` in `run-registered-suites.sh` (the single source), the runner's shard
branch, the workflow job's steps, and `deploy-script-tests-done`'s `needs` and `entries`. All four are
read by `test-infra-suite-registration.sh`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `bash apps/web-platform/infra/bastion-runcmd-rehearsal.test.sh` step from the job | RED |
| 2 | Add `continue-on-error: true` or a step `if:` to that step | RED |
| 3 | Drop the shard exclusion so the suite lands on leg k/4 | RED |
| 4 | Exclude it from the unsharded set too | RED |
| 5 | `DEDICATED_JOB_WHY` parses to zero entries while the map exists (own dispatch) | RED |
| 6 | Add a second `DEDICATED_JOB_WHY` entry with no invoking step, after a compliant first | RED |
| 7 | Remove the job from `deploy-script-tests-done`'s `needs` | RED |
| 8 | Drop `SOLEUR_INFRA_SKIP_DEDICATED=1` from main-health-monitor's `test-infra` leg | RED |

**Harness rows.** A fixture workflow whose step has the invocation only in a comment must RED; a
fixture with the invocation in a multi-line `run: |` block must PASS.

**Anchor.** The workflow file and the runner map are separate files; the arm reads both, so a single
edit to either alone reds it.

## Plan Review Revisions

Panel (2026-11-20): DHH, Kieran, code-simplicity, and the CTO agent on the devex lens. All findings
were technical; mechanical ones were applied, contested ones were ruled by the CTO (Q14-Q18 in
decision-challenges.md). No taste or user-challenge item arose.

- Applied (Kieran): `--no-install-recommends` plus a minimal-baseline check (`BRH_BASELINE_NOT_MINIMAL`);
  dummy debs installed through the apt helper (A10 RAW_RE); the PRIVILEGED parse scoped to its block;
  the shard check moved to `--list` (`--enumerate` exits before the shard branch); the suite kept out
  of `--enumerate`; the aggregator replay test and its `cancelled)` order dependence; Arm 4's `need`
  loop; the main-health-monitor consumer (ruled Q16); `journalctl --sync` and `-b`; the CI skip ceiling
  (ruled Q17); SPECS counts derived, not hand-counted; terraform 1.10.5 re-render; image tag week term.
- Applied (DHH, simplicity): F1-D cut (Q18a); the decoy only on B1's network; the baseline file
  replaced by an inline array (Q18b); IMAGE_ASSUMED merged with the fixture list; P8 restated; P10 and
  P11 added for B1-P and B1-C.
- Applied (CTO devex): evidence kept on failure plus the CI artifact; `BRH_ANCHOR_MISS`;
  `BRH_STATIC_ONLY` and `BRH_ROWS` (ending `PARTIAL`, refused under CI); the template header pointer;
  the line estimate revised.
- Ruled, not applied as proposed: DHH's single-source budget and simplicity's cut became the derived
  deadline (Q14); DHH's fixed-literal fallback became the structured `Result` line (Q15); S1 keeps its
  must-RED control (Q18c).

## Test Scenarios

1. Fresh clone, docker and terraform present: `bash apps/web-platform/infra/bastion-runcmd-rehearsal.test.sh`
   → `bastion-runcmd-rehearsal: PASS (<n> assertions, 0 failed)`, cold under 900 s.
2. The same on main before the template fix → B1 RED naming `egress_load` and `User does not exist`,
   F1 RED on the detail predicate.
3. docker absent locally → one `SKIP (loud)` line, exit 0; with `CI=true` → `BRH_TOOL_ABSENT:docker`,
   exit 1.
4. archive unreachable (an env override used only by the self-test pins `archive.ubuntu.com` to an
   unrouted 198.18.255.1) → apt-stage rows SKIP with the probe output; the run ends `SKIP`, never
   `PASS`.
5. `SOLEUR_INFRA_SHARD=2/4 bash apps/web-platform/infra/run-registered-suites.sh --list` omits the
   suite; the unsharded `--list` includes it.
6. `bash scripts/test-all.sh infra` on a branch touching `apps/web-platform/infra/` runs the suite.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "a suite modelled on git-data-runcmd-rehearsal.test.sh that renders the template and runs its runcmd stages (apt, the egress script under a netns, the trap/emit path with a stub Sentry) in the pinned image" [issue #12941] | Proposed Solution §1, Files to Create | mapped |
| 2 | "apt with the nftables conffile ordering" [brief] | rows B1, M1 | mapped |
| 3 | "cloud-init apt_configure https sources" [brief] | rows B1, M2 | mapped |
| 4 | "register it in scripts/test-all.sh" [brief] | §3 (runner unsharded set; no test-all.sh edit needed, ADR-252) | mapped |
| 5 | "fix any boot fault it finds in the template" [brief] | §2 FAULT-A, FAULT-B | mapped |
| 6 | "Use \"Ref #12866\" and \"Ref #9421\" (never Closes for #9421 or #12008); \"Closes #12941\" in the PR body" [brief] | PR body line under the title | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| The suite and its rows | "renders the template and runs its runcmd stages" | asked |
| Template fixes | "fix any boot fault it finds in the template" | asked |
| Runner unsharded registration | "register it in scripts/test-all.sh" | asked |
| Dedicated CI job, registration arms, aggregator wiring | — | inferred — justification: the suite must run in CI to block a boot fault, and a matrix leg cannot absorb ~5 min (CTO Q6b) |
| apt-bounded SPECS line, PROMOTED_FILES entry | — | inferred — justification: existing repo gates fail without them (repo research) |
| ADR-327 addendum, runbook paragraph, #12942 comment | — | inferred — justification: architecture decisions ship with the plan that makes them (wg-architecture-decision-is-a-plan-deliverable); CTO Q9 |

### Split Assessment

- Subsystems touched: 3 code roots — `apps/web-platform/infra/`, `.github/`, `scripts/` (plus docs in `knowledge-base/`)
- Planned files: 12 | Estimated changed lines: ~1,400-1,800 (the suite ~1,000-1,300; the CTO devex review notes the two sibling suites run 1,846 and 3,935 lines, so ~650 was low)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the line threshold trips on the suite alone. Splitting would ship either
  a suite that is red on main (FAULT-A, FAULT-B) or a template fix with nothing pinning it.

## Acceptance Criteria

- [ ] AC1. `apps/web-platform/infra/bastion-runcmd-rehearsal.test.sh` exists, is executable, reads
  `UBUNTU_BASE` from `git-data-runcmd-rehearsal.test.sh`, and ends with `PASS` on the fixed template
  (two local runs and the first CI run recorded in the PR body with wall times).
- [ ] AC2. On the template as merged in #12873 (pre-fix), the suite reports FAIL with B1 naming
  `egress_load` / `User does not exist` and F1 failing its detail predicate; the output is quoted in
  the PR body.
- [ ] AC3. Rows M1, M2, F1-M and FA each report their designed RED evidence inside a PASS run
  (their assertions are that the mutated boot fails in the named way).
- [ ] AC4. `bastion-cloud-init.yml` installs `systemd-timesyncd` in the apt_install line, and the
  `egress_load` capture selects `[bastion-egress] FAIL:` and nft `Error:` lines from both unit journals;
  `bash apps/web-platform/infra/bastion.test.sh` ends `bastion: PASS`.
- [ ] AC5. `SOLEUR_INFRA_SHARD=k/4` (k=1..4) execute sets never contain the suite; the unsharded set
  does; `bash .github/scripts/test/test-infra-suite-registration.sh` passes and its new arms go RED
  under Guard 2 rows 1-7 (run as mutations during work, recorded in the PR body).
- [ ] AC6. `infra-validation.yml` has job `bastion-boot-rehearsal` (`timeout-minutes: 18`, no
  credentials, unmasked invocation) and `deploy-script-tests-done` lists it in `needs` and `entries`.
- [ ] AC7. `apt-bounded.test.sh`, `guard-vacuity-floor.test.sh` (with `MAX_DEFERRED` unchanged),
  `run-registered-suites.test.sh`, `bash scripts/lint-orphan-test-suites.sh` (after `git add`) and the
  ratchet lints pass, each by its own CI invocation shape.
- [ ] AC7b. The suite's deadline is computed from its constants (180 + 300 + 150 + 150 = 780 s) and
  printed; the job's `timeout-minutes: 18` comment cites it.
- [ ] AC7c. `run-registered-suites.sh --list` under `SOLEUR_INFRA_SHARD=k/4` (k=1..4) and with
  `SOLEUR_INFRA_SKIP_DEDICATED=1` omits the suite, the plain unsharded `--list` includes it, and
  `--enumerate` omits it; `bash plugins/soleur/test/deploy-script-tests-aggregator-diagnosis.test.sh`,
  `bash .github/scripts/test/test-infra-suite-registration-mutations.sh` and
  `bash tests/scripts/test-main-duplicate-skip.sh` pass.
- [ ] AC8. Docker absent under `CI=true` prints `BRH_TOOL_ABSENT:docker` and exits 1; an all-skip run
  ends `SKIP`, never `PASS`; under `CI` more than 2 skipped rows, or a skipped B1, prints
  `BRH_SKIP_CEILING` and exits 1; `BRH_ROWS`/`BRH_STATIC_ONLY` and the archive-pin override are refused
  under `CI`.
- [ ] AC9. ADR-327 carries the 2026-11-20 addendum; `bastion-host.md` names the suite and job;
  `c4-count-parity.test.sh` passes; #12942 has the gate comment.
- [ ] AC10. PR body: `Closes #12941`, `Ref #12866`, `Ref #9421`; no `Closes` for #9421 or #12008.
