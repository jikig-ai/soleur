---
title: "feat(infra): first-boot kernel currency for web hosts"
date: 2026-11-10
slug: feat-first-boot-kernel-currency-web-hosts
branch: feat-kernel-patch-web-hosts-12008
issue: 12008
closes: none
type: feat
priority: p1-high
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# feat(infra): first-boot kernel currency for web hosts

Ref #12008 (item 1, code half only). Public-repository rule (ADR-322): this file carries no kernel string,
vulnerability id, host address or exposure verdict. Per-host answers stay in the session.

**Scope status (2026-11-10):** the owner asked to retire web-1 and make every web host identical, Terraform-born
cattle (#9421), with a small dedicated bastion (approved, ~€4–5/month) and a private Hetzner load balancer for
Inngest (approved, ~€5–6/month). The CTO ruled that this cannot land in one PR (a merge cannot birth a host, and
deleting web-1's code while it runs would destroy it at merge, with users' uncommitted work on its disk). This PR
carries Part 1 (kernel currency at every birth) and Part 2a (make web hosts generic, no running host changed). The
later PRs are listed under "Part 2 — PR sequence".

## Overview

A web host born by create or replace boots the stock base image and installs four named packages, so it runs the
base image's kernel: a replace is a rebuild, not a kernel refresh. Part 1 makes the bounded apt step also install
the generic kernel meta package and, right after it, when the running kernel differs from the installed one, reboot
**once** and run the whole of runcmd again on the new kernel. Everything that matters (LUKS provisioning, the app
container, the egress-enforcement proof, `cloud_init_complete`, the readiness verdict) runs once, after the reboot,
exactly as today. The readiness verdict gains a kernel field and fails when the running kernel is not the installed
one. Web class only; `web_host_create` (30-min job) and `web_host_replace` (40-min job) share this cloud-init and the
boot trail, so every future web host birth pays the one reboot. Merging changes no running host.

Both web hosts serve users: the enabled Cloudflare load balancer for the app hostname pools both web origins
(`cloudflare-lb.tf`; live read 2026-11-10: both enabled, equal weight). A replace removes one serving origin for the
birth's duration.

Mechanism ruled by the CTO agent on 2026-11-10 after plan review (option C below).

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Reality (evidence) | Plan response |
|---|---|---|
| "cloud-init reboots once at the very end of first boot, before the host is graded healthy" (brainstorm, first CTO ruling) | The verdict is the last runcmd item; a `power_state` reboot runs after it, so it is never graded. A reboot at the end of runcmd with a post-reboot unit (second ruling) loses `/run` state the verdict reads (`/run/soleur/workspaces-luks-arm` → `luks_arm=none escrow=none`, a standing red under `scripts/lib/web2-luks-rows.sh`), lacks the inline ingest URL and Doppler token, and races the trail's 210 s grace (plan review, 5 of 7 reviewers). | Reboot **early**, right after `STAGE=apt_install`, before any Doppler, docker, `/mnt/data` or LUKS work, and re-run runcmd (CTO ruling C). Spec FR2/FR3 amended. |
| Rejected: `packages: [linux-image-generic]` + `package_reboot_if_required` | `cloud-init.yml` header + the `(#6090) Package install — MOVED here` comment: apt was deliberately moved out of the opaque config phase after a web host died there with no named stage (recreate 28819237402). | Not used; the kernel installs inside the instrumented runcmd apt block. |
| Brainstorm "anti-pooling: the replaceable host carries no serving weight" | Wrong: `cloudflare-lb.tf` pool `web_1` carries both web origins; the LB takes precedence over `dns.tf`'s app record; live pool read shows both enabled at weight 1. | Corrected in the brainstorm, the cadence runbook and the learning (commit `174d525558`). |
| "web-1 holds the only copy of users' repositories" (CTO, #9421 body) | Production `GIT_DATA_STORE_ENABLED=true`: objects/refs live on the git-data host and each agent turn replicates there; working trees live under `/var/lib/soleur/worktrees` (`workspace-resolver.ts` `WORKTREE_ROOT_DEFAULT`). | Part 2 research establishes exactly what is web-1-only. |
| "a sibling test (shape of `apt-bounded.test.sh`)" | `apt-bounded.test.sh` tests `lib/apt-bounded.sh`, which the web template does not use. Registration is a row in `apps/web-platform/infra/suite-shard-legs.tsv` (enforced by `.github/scripts/test/test-infra-suite-registration.sh`) plus a promotion entry in `scripts/guard-vacuity-floor.test.sh` for a new floor-bearing suite. | New suite `kernel-currency.test.sh`; registered both places. |
| "User-data size: measure headroom first" | `WEB_GZIP_BUDGET = 25_000` (`plugins/soleur/test/cloud-init-user-data-size.test.ts`), ~24,820 last measured → ~180 B headroom; the Hetzner cap is ~7.7 KB away. | The settle step must be **inline** (the baked bootstrap is not seeded at that point in runcmd). Keep it minimal; trim comments first; a budget raise is allowed with the measured number in the PR (CTO). |
| Spec acceptance: "the reader shows a changed kernel" | The running hosts report `kernel=unknown` because they predate the emitter (#12386); a newly born host enables `host-kernel-marker.timer` at birth. | Two independent reads after a birth: the verdict's `kernel=` field and the reader's kernel column. |

## Research Insights

**Premise validation (2026-11-10).** #12008 is open; owner comment 2026-11-10T18:03Z records that the distro now
ships the fixed generic kernel for 24.04 (re-evaluation trigger fired). #12503 is open and was narrowed today to
inngest, registry and git-data. #9421 (web-1 de-pet) is open, p3, last update 2026-10-03. PR #12497 (items 2–3) is
merged. Collision pre-check: the only open PR naming #12008 is this branch's draft PR #12613; two `test-all.sh`
processes owned by another worktree were running (unrelated). cloud-init writes a module's per-instance semaphore
before running it (Kieran, plan review), so runcmd does not re-run after a reboot unless its semaphore is removed.

**Property list (Phase 0.6b).**

- P1: A born web host reports ready only while running the kernel version the installed `linux-image-generic` points to.
- P2: A kernel-install failure, hang or unreadable target during first boot is a named fatal, never a silent continue.
- P3: At most one reboot per host birth; a second pass still mismatched is a named fatal, not a loop.
- P4: The reboot happens before any step that is not safe to run twice (Doppler fetch, docker, `/mnt/data`, LUKS
  provisioning), so provisioning, the egress proof and the verdict each run exactly once, on the new kernel.
- P5: Merging this change alters no running host.
- P6: Rendered web user_data stays under `WEB_GZIP_BUDGET` (or the budget is re-baselined with the measured number).
- P7: Both job budgets (create 30 min, replace 40 min) still cover the trail's worst case.

**Cut list.**

- End-of-runcmd reboot + post-reboot unit, marker-gated unit enablement, `kernel_reboot_no_readiness` terminal, latched
  grace, 1,560 s deadline → P1/P4 → cut (CTO ruling C): a host that never returns does not reach
  `cloud_init_complete`, which the trail already reports red at its deadline.
- `power_state` end-of-boot reboot → P1 → cut: fires after the verdict.
- `packages:` + `package_reboot_if_required` → P2 → cut: reverses #6090.
- `cloud-init clean`-style re-run → P4 → cut (CTO): re-runs users, SSH keys and `write_files`, regenerates host keys.
- `/var/run/reboot-required` as the trigger → P1 → cut: set by a postinst hook, not the version comparison P1 states.
- boot_id comparison, newest-`/boot/vmlinuz-*` comparison → P1 → cut: `uname -r` cannot change without a reboot; one
  target source (dpkg) is enough.
- Full `apt-get upgrade` / pinned version / baked snapshot image → P1 → cut (CTO, brainstorm).
- `linux-generic` (with headers) → P1 → cut: nothing on the host builds modules.

**Relevant files.**

- `apps/web-platform/infra/cloud-init.yml` — runcmd item 1 arms `set -e`, `_emit`, `on_err` (`trap - EXIT`, emits
  `soleur-hostscript-seed failed` with the live `$STAGE` at level fatal, `exit 1`) and `trap on_err EXIT`, then emits
  `runcmd_start`; then the hosts item, `networkctl reload`, the sshd restart, then the bounded apt block
  (`STAGE=apt_update`, `STAGE=apt_install`). The first non-idempotent item (`STAGE=fail2ban`, then `STAGE=doppler_dl`
  and `/etc/default/webhook-deploy`) follows the apt block. `workspaces-luks-provision.sh` runs much later.
- `apps/web-platform/infra/soleur-host-bootstrap.sh` — authors `soleur-fresh-boot-ready` (heredoc `FRESHREADYEOF`);
  `SOLEUR_FRESH_BOOT_WINDOW_SECONDS=900`.
- `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh` — `DEADLINE=SECONDS+960` (applies until
  `cloud_init_complete` is seen), `CC_GRACE=210`; a `fatal` stage exits 1; `complete_no_readiness` is a warning, exit 0.
- `apps/web-platform/infra/fresh-boot-ready.test.sh` — S0–S10, incl. S7/S8b (call site after vector-install, `|| true`).
- `plugins/soleur/test/cloud-init-user-data-size.test.ts` — `WEB_GZIP_BUDGET`.
- `.github/workflows/apply-web-platform-infra.yml` — `web_host_create` (`timeout-minutes: 30`), `web_host_replace`
  (`timeout-minutes: 40`); both call `fresh-host-boot-trail.sh`.
- `apps/web-platform/infra/cloudflare-lb.tf`, `dns.tf` — serving topology.
- `knowledge-base/engineering/operations/runbooks/web-host-replace.md` — `-f image_tag=`; the default reads web-1's
  tag, which predates this PR and is refused by `scripts/host-image-coherence-preflight.sh`.

**Learnings applied.**

- `knowledge-base/project/learnings/best-practices/2026-07-07-cloud-init-user-data-cap-is-measured-on-the-gzipped-render.md` — measure the render.
- `knowledge-base/project/learnings/2026-07-03-cloud-init-32kb-cap-bake-and-extract-not-compress.md` — prefer baking; the settle step cannot be baked (it runs before the bootstrap is seeded), so it stays minimal.
- `knowledge-base/engineering/architecture/decisions/ADR-257-inngest-host-provisioning-runs-in-a-latched-retrying-unit.md` — runcmd is once per instance; this plan is the one recorded exception.
- `knowledge-base/project/learnings/2026-04-19-cloud-init-packages-stage-silent-drop-audit.md` and the #6090 comments — install inside the bounded runcmd block, never `packages:`.
- `knowledge-base/project/learnings/bug-fixes/2026-07-13-warm-standby-cross-dc-and-replace-capacity-footgun.md` — check capacity before any replace.
- `knowledge-base/project/learnings/2026-11-10-a-failover-premise-must-be-checked-against-the-serving-topology.md` — read the live LB pool before any serving-weight claim.

**External research:** skipped — local cloud-init/dpkg mechanism with strong local precedent.

## Part 1 — Proposed Solution (kernel currency)

1. **Install.** The bounded apt install line in `cloud-init.yml` gains `linux-image-generic` inside the existing
   `timeout` + 2-attempt + `STAGE=apt_install` contract (P2). The retry gains `dpkg --configure -a` before attempt 2
   (as `lib/apt-bounded.sh` does): a kernel + initramfs + bootloader install cut by `timeout` leaves dpkg
   half-configured. The rehearsal records the install's wall time against the 300 s per-attempt bound.
2. **Settle (inline, the runcmd item right after `STAGE=apt_install`).** `STAGE=kernel_settle`. Read the target as the
   `linux-image-<ver>` token of `dpkg-query -W -f='${Depends}' linux-image-generic`, strip only the `linux-image-`
   prefix (keep the flavour suffix so it compares with `uname -r`).
   - Target empty or unreadable → `exit 1` (existing `on_err` emits the named fatal with `stage=kernel_settle`).
   - Target equals `uname -r` → continue (no reboot).
   - Mismatch and `/var/lib/soleur/kernel-settle` exists (second pass) → `exit 1` (named fatal; no reboot).
   - Mismatch, no marker → `[ -f /var/lib/cloud/instance/sem/config_scripts_user ] || exit 1` (semaphore guard: if
     cloud-init renames it, a named fatal, never a quiet host); `mkdir -p /var/lib/soleur` and write the marker;
     `_emit "soleur-cloud-init boot stage" kernel_reboot info`; `trap - EXIT`; remove the semaphore; reboot; `sleep 600`.
   On the second pass, runcmd re-runs from item 1 on the new kernel: the items before the settle step are idempotent
   (emit setup, the hosts deny, `networkctl reload`, the sshd restart, apt update/install), and the settle step
   continues on a match. `runcmd_start` and the apt stages are emitted twice; that is expected.
3. **Verdict proves currency.** `soleur-fresh-boot-ready` gains `kernel=` (the running kernel equals the installed
   target) and a not-ready reason `kernel` (`fresh_boot_not_ready_kernel` fatal). Zero user_data cost.
4. **Windows.** The trail's `DEADLINE` (960 s) and the host's `SOLEUR_FRESH_BOOT_WINDOW_SECONDS` (900) grow together by
   the measured reboot + re-run time (second apt update ~1 min, plus the reboot), as does the Better Stack
   absence-alert grace derived from the window. No new trail terminal: a host that never comes back does not reach
   `cloud_init_complete` and ends `timeout` (red); a second-pass mismatch is a `fatal` (red).

## Part 1 — Implementation Phases

**Phase 1 — RED tests (cq-write-failing-tests-before).**

- `apps/web-platform/infra/kernel-currency.test.sh` (new). Extract the settle item from `cloud-init.yml` and run it
  under `/bin/sh` with stubbed `dpkg-query`, `uname`, the reboot command, `_emit`, a temp `/var/lib/soleur` and a temp
  semaphore path. Behaviour cases: match → no reboot, exit 0, no marker; mismatch + no marker → marker written,
  `kernel_reboot` emitted, `trap - EXIT` before the semaphore removal, semaphore removed, exactly one reboot;
  mismatch + marker → no reboot, exit 1 with `STAGE=kernel_settle`; unreadable dpkg → exit 1, no reboot; semaphore
  absent → exit 1, no reboot. Structural rows: `linux-image-generic` on the bounded `apt-get install` line inside
  `STAGE=apt_install`; `dpkg --configure -a` in that retry; the settle item is the item immediately after the apt
  block; **idempotent allowlist** — every runcmd item before the settle item matches an allowlist (emit/trap setup,
  hosts deny, `networkctl reload`, sshd restart, apt update/install), so a new item there fails until added
  deliberately; no Doppler/docker/`/mnt/data`/`workspaces-luks-provision` reference before the settle item; the
  semaphore path appears exactly once in `cloud-init.yml`; no `power_state:` or `packages:` key; the marker lives
  under `/var/lib/soleur`. Instrument self-test + exact-count anti-vacuity floor (`$checked` incremented at the call
  site, `pass + fail == checked`, emitted via `printf` + `exit 1`).
- `apps/web-platform/infra/fresh-boot-ready.test.sh`: rows for the kernel predicate (match → ready; mismatch →
  not-ready `kernel`; empty target → not-ready `kernel`).
- Budget rows (in `kernel-currency.test.sh`): `DEADLINE` and `SOLEUR_FRESH_BOOT_WINDOW_SECONDS` moved together; the
  create path's worst case (pre-poll + `DEADLINE` + `CC_GRACE` + one iteration) stays under 30 min and the replace
  path's under 40 min, computed from the literals.
- Register: a row in `apps/web-platform/infra/suite-shard-legs.tsv` (+ `suite-durations.tsv` if the registration test
  requires it) and a promotion entry in `scripts/guard-vacuity-floor.test.sh` (do NOT raise `MAX_DEFERRED`).

**Phase 2 — GREEN.** Edit `cloud-init.yml` (apt token, retry repair, settle item), `soleur-host-bootstrap.sh`
(verdict kernel field; window constant and derivation), `scripts/fresh-host-boot-trail.sh` (`DEADLINE` and its cost
comment). Run `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` and print the measured render; trim
comments first; if still over, re-baseline `WEB_GZIP_BUDGET` with the measured number in the PR body. Re-run the
suites that pin the trail or the window (Files to Edit).

**Phase 3 — Docs + ADR.** New ADR via `soleur:architecture` (see Architecture Decision). Runbooks (ADR-322 wording):
`host-kernel-patch-cadence.md` (web: a birth now installs the archive's kernel and reboots once; two post-birth
reads; release-then-replace order) and `web-host-replace.md` (expect one reboot and a longer trail; choose
`-f image_tag=` as the release containing this PR, re-checked by `plan_only`; a red replace leaves a host that is NOT a
serving or failover target until re-replaced green; one row per new failure: `stage=kernel_settle` → code defect,
file an issue, do not re-dispatch; `timeout` after `kernel_reboot` → read Sentry host events, the Better Stack journal
and the Hetzner server status, then re-dispatch).

## Part 2 — identical web hosts, dedicated bastion, web-1 retirement (#9421)

**Inventory (research agent, 2026-11-10, file anchors verified by it).** 26 `terraform_data` resources pin web-1
(22 `server.tf`, 3 `workspaces-luks.tf`, 1 `ci-ssh-key.tf`). 23 are redundant at birth: web-2's path (baked
`host_script_files` + `soleur-host-bootstrap.sh` + `cloud-init.yml`) already delivers them, including the seccomp
profile (`--security-opt seccomp=` in `cloud-init.yml`, fail-closed presence test in the bootstrap) and the AppArmor
profile (`apparmor_parser -r`, `--security-opt apparmor=soleur-bwrap`); proven offline by parity tests only. 3 are
gaps: the two luks-monitor resources (web-1 is the `primary` profile; births are `standby`) and
`workspaces_boot_unlock_install` (the legacy volume, deleted with web-1). Hub roles found on web-1 or web-2: the
`ssh.` ingress jump to git-data (ADR-220), web-2 SSH provisioning via web-1 (`HostKeyAlias=web-1`), the `deploy.`
webhook, the Inngest SDK URL and `cutover-inngest.yml` at web-1's private IP, the tunnel connector (web-2), the
`registry.` tcp ingress, the CI SSH key install, git-data's SSH source allowlist, the jump in `git-data-cutover.yml`,
`WEB_HOST_PRIVATE_IPS` literals, the `dns.tf` apex record. Data only on web-1: the `workspaces_luks` volume
(pre-flip trees; never destroyed, detached and archived) and root-disk worktrees under `/var/lib/soleur/worktrees`
(users' uncommitted work; lost with the server).

**CTO ruling (2026-11-10, binding).**

- Bastion: `hcloud_server.bastion` in a new `bastion.tf` in the web-platform root (not a new root), `var.bastion_server_type`
  default cx23, hel1, amd64; its own small `bastion-cloud-init.yml` with the bounded apt step and Part 1's settle step
  (same test); no public inbound; egress only to Cloudflare, apt, Sentry, Doppler; nftables allowlist to git-data:22,
  each web host's :9000 and the registry endpoint (each further row needs a cited consumer); git-data's SSH source
  allowlist gains the bastion. Host key generated in Terraform (`tls_private_key` ed25519, delivered via cloud-config
  `ssh_keys`), so the pin exists before birth and survives a replace. Gated `bastion-host-create` /
  `bastion-host-replace` routes with an inverted plan gate; the per-merge apply halts on a bastion create.
- No SSH-delivered config to web hosts; config only via the baked image + cloud-init. A CI test fails if a
  `terraform_data` with a `connection` block targets any web key (after web-1 is gone).
- Deploys: one ingress hostname per web host (`deploy-<key>.`, `for_each` over `var.web_hosts`) through the bastion's
  connector to each host's :9000; CI posts to each; rebirth-on-release rejected.
- Inngest: a private Hetzner load balancer selecting web hosts by label, with a health check (ADR-100 Decision 1's
  "private VIP when active-active-N").
- New host is `web-3`, not a reused `web-1` key (avoids the refusal arms, the `moved` blocks and the same-host-name
  Sentry match class, #6969). Private IP hand-picked, validated unique and inside the subnet.
- Before destroy: pause new sessions, wait for zero live sessions, flush every dirty worktree to
  `refs/checkpoints/<conversationId>` on git-data (reuse `inflight-checkpoint.ts`; no `git stash`, no `git add -A`),
  then a read-only, non-SSH count of unflushed worktrees must read zero; the destroy gate refuses otherwise.
- ADR: one new ADR "Dedicated bastion; web hosts are identical cattle", with pointer amendments to ADR-220,
  ADR-100 Decision 1 and ADR-143 D2.
- Dissent: the bastion is a single point for the management plane (not user traffic), bounded by its replace route;
  egress-tokens directory creation at birth and any host-bound cron state are unverified (decided by the census in
  this PR); the 23 redundant provisioners are first proven live by web-3's birth, and the destroy PR must quote
  web-3's readiness row and probe results.

### Part 2a — in THIS PR (merging changes no running host)

1. `var.web_hosts` gains keyed fields: `lb_weight` (default 0; web-1 = 1, web-2 = today's `var.web2_lb_weight`
   value), `luks_monitor_profile` and `jump` (validated exactly one host each; both still web-1, so nothing changes).
   Validation: `private_ip` unique and inside the subnet.
2. `cloudflare-lb.tf`: pool origins become a `dynamic "origins"` block over `var.web_hosts`; weights reproduce today's
   live values exactly. `server.tf`: `web_tunnel_connector` reads a keyed field instead of `each.key == "web-2"`.
3. `WEB_HOST_PRIVATE_IPS` derived in HCL (`inngest-host.tf`); a parity test pins every workflow copy to the derived
   list.
4. `lb-weight-gate.sh`: the literal `web-2` soak precondition becomes "any key at weight 0" (with its tests).
5. A ratchet test counting the literal web-1 private IP and the string `"web-1"` outside an allowlist, with today's
   count as the ceiling; later PRs must drive it to zero.
6. A census (doc + test rows) of host-bound state: egress-tokens directory at birth, cron state, Better Stack
   heartbeat per host.
7. The new ADR (Part 1's and this one, or one ADR with two decisions; decided in work via `soleur:architecture`).

Acceptance for 2a: `terraform plan` on the web-platform root shows **no** change to any server, volume, attachment,
tunnel or LB pool (an origin reorder is a change: verify the dynamic block keeps today's order); the ratchet, parity,
gate and census tests pass.

### Part 2 — PR sequence after this one (owner acts in bold)

| PR | Content | Owner act |
|---|---|---|
| 2 | Bastion code, cloud-init, routes; git-data source allowlist | **`bastion-host-create`, `plan_only` then real run** |
| 3 | Management-plane retarget: `ssh.`, `registry.`, connector, CI key to the bastion; git-data workflows | **go on the merge** (changes the live tunnel); web-1 stays as the way back |
| 4 | Per-host `deploy-<key>.` hostnames; private LB for Inngest | **go on the merge** (cost approved 2026-11-10) |
| 5 | `web-3` entry | **`web-host-create` for web-3, then raise its weight** |
| 6 | Flush tooling + unflushed-worktree count | **pause new sessions; go on the flush; count must read zero** |
| 7 | Destroy route; delete web-1 code; ratchet reaches zero; volume detached and kept | **`Operator-reserved:` the destroy** |

Each later PR is planned in its own session from this plan; #9421 tracks the sequence.

## Files to Edit (Part 2a; anchors confirmed in work)

- `apps/web-platform/infra/variables.tf` (`var.web_hosts` fields + validations)
- `apps/web-platform/infra/cloudflare-lb.tf` (dynamic origins)
- `apps/web-platform/infra/server.tf` (`web_tunnel_connector`)
- `apps/web-platform/infra/inngest-host.tf` (derived IP list)
- `.github/workflows/apply-web-platform-infra.yml` and other workflows carrying `WEB_HOST_PRIVATE_IPS` (parity)
- `apps/web-platform/infra/lb-weight-gate.sh` + `lb-weight-gate.test.sh`
- new tests: ratchet, parity, census (registered like the Part 1 suite)
- `knowledge-base/engineering/architecture/decisions/` ADR-220, ADR-100, ADR-143 pointer amendments

## Files to Edit (Part 1)

- `apps/web-platform/infra/cloud-init.yml`
- `apps/web-platform/infra/soleur-host-bootstrap.sh`
- `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh`
- `apps/web-platform/infra/fresh-boot-ready.test.sh`
- `apps/web-platform/infra/suite-shard-legs.tsv` (+ `suite-durations.tsv` if required)
- `scripts/guard-vacuity-floor.test.sh`
- `plugins/soleur/test/cloud-init-user-data-size.test.ts` (only on a re-baseline)
- `.github/workflows/apply-web-platform-infra.yml` (only if a budget row shows a job limit is too short)
- `knowledge-base/engineering/architecture/decisions/ADR-263-guest-side-fresh-boot-luks-for-web-hosts.md` (dated forward-pointer addendum)
- `knowledge-base/engineering/operations/runbooks/host-kernel-patch-cadence.md`
- `knowledge-base/engineering/operations/runbooks/web-host-replace.md`
- `knowledge-base/project/specs/feat-kernel-patch-web-hosts-12008/spec.md` (FR2/FR3/TR4 to ruling C; Part 2 scope)
- Re-run, edit only if they pin a changed literal: `apps/web-platform/infra/cloud-init-web-zot-seed.test.sh`,
  `soleur-host-bootstrap-observability.test.sh`, `doppler-download-error-channel.test.sh` (+ `.mutation.py`),
  `tests/scripts/test-argv-bearer-sweep.sh`, `scripts/followthroughs/web-first-deploy-10585.test.sh`

## Files to Create (Part 1)

- `apps/web-platform/infra/kernel-currency.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-<next>-first-boot-kernel-currency-one-reboot-at-web-host-birth.md` (ordinal provisional; re-check at ship)

## Open Code-Review Overlap

None for Part 1 files (checked 2026-11-10). Part 2 files are re-checked when listed.

## User-Brand Impact

- **If this lands broken, the user experiences:** a born web host that reports ready while running the old kernel
  (false currency claim), or a birth that loops or half-builds while the other origin carries all traffic; a host
  wrongly marked ready joins the LB pool and serves users.
- **If this leaks, the user's data is exposed via:** a step that runs twice on the second pass and touches users'
  workspace volume or secrets (LUKS provisioning, Doppler fetch); the idempotent-allowlist row and the
  "settle before any Doppler/docker/LUKS item" row make that structurally impossible.
- **What this does not change (Part 1 alone):** web-1 is not refreshed until Part 2 re-births it. No PR body, runbook,
  commit or issue update may say "web hosts refreshed" until both web hosts are re-born green.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** a born host holds users' working trees and runs their agent sandboxes.

CPO sign-off: SIGN-OFF WITH CONDITIONS (plan review 2026-11-10, Part 1); conditions applied. Part 2 needs its own CPO
read (it changes a serving host). `soleur:engineering:review:user-impact-reviewer` runs at review.

## Observability

```yaml
liveness_signal:
  what: "Sentry boot stages from the born host: kernel_reboot (info) on the first pass, a second runcmd_start, then cloud_init_complete and fresh_boot_ready with kernel=1; Better Stack SOLEUR_FRESH_BOOT_READY line with kernel= field"
  cadence: "per host birth"
  alert_target: "the create/replace job's boot-trail step (red run on any fatal stage or timeout)"
  configured_in: "apps/web-platform/infra/cloud-init.yml (on_err + _emit), apps/web-platform/infra/soleur-host-bootstrap.sh (verdict), apps/web-platform/infra/scripts/fresh-host-boot-trail.sh (poll)"
error_reporting:
  destination: "Sentry via the runcmd _emit (DSN baked in user_data) and the verdict; Better Stack via the verdict"
  fail_loud: "boot-trail ::error:: + exit 1 on stage=kernel_settle, fresh_boot_not_ready_kernel or apt_install fatals, and on timeout (no cloud_init_complete)"
failure_modes:
  - mode: "kernel install hangs or fails"
    detection: "existing STAGE=apt_install named fatal"
    alert_route: "boot-trail red run"
  - mode: "target unreadable, semaphore missing, or still mismatched on the second pass"
    detection: "on_err fatal with stage=kernel_settle"
    alert_route: "boot-trail red run"
  - mode: "host does not come back from the reboot"
    detection: "kernel_reboot seen, no second runcmd_start / cloud_init_complete before DEADLINE → trail terminal timeout"
    alert_route: "boot-trail red run"
  - mode: "host runs but on a kernel other than the installed target"
    detection: "fresh_boot_not_ready_kernel fatal"
    alert_route: "boot-trail red run"
logs:
  where: "Sentry events, Better Stack via Vector, journald on the host"
  retention: "Better Stack plan retention; Sentry project retention"
discoverability_test:
  command: "bash apps/web-platform/infra/kernel-currency.test.sh"
  expected_output: "0 failed"
```

Alert route: the trail's red run is the route for these stages (CTO ruling); `sentry/issue-alerts.tf` is not edited
in Part 1. The shared-project 100-event page truncation predates this change and fails closed as a red timeout; it
is filed as its own issue at work time.

> **Amended 2026-11-11 (review):** the work did edit `sentry/issue-alerts.tf`: the readiness reason `kernel`
> (`fresh_boot_not_ready_kernel`) joined the existing boot-fatal alert's stage filter, so merging applies one
> in-place alert change through `apply-sentry-infra.yml`. The settle step's own fatals stay on the trail route.

## Infrastructure (IaC)

### Terraform changes

Part 1: none to `.tf` files. `cloud-init.yml` is a `templatefile()` source rendered into
`hcloud_server.web[*].user_data`; the web servers carry `lifecycle.ignore_changes = [user_data, ssh_keys, image,
placement_group_id]` (`apps/web-platform/infra/server.tf`), so the per-merge apply does not replace or update any
running server. Part 2's `.tf` changes are listed with Part 2.

> **Amended 2026-11-11 (review):** Part 1 also touched `sentry/issue-alerts.tf` (the alert filter above).
> Part 2a edits `.tf` files (`variables.tf`, `cloudflare-lb.tf`, `tunnel.tf`, `inngest-host.tf`, `server.tf`);
> those expressions evaluate to today's values, and the PR's plan adds no resource change of its own.

### Apply path

(b) `terraform apply -replace` through the owner-authorized `web-host-replace` route, after the release that bakes
the new `soleur-host-bootstrap.sh`, passing that tag explicitly (`-f image_tag=`). During a birth the other web
origin carries all traffic; capacity is checked before each replace.

### Host fan-out

No `terraform_data` SSH provisioner is added or changed in Part 1.

### Distinctness / drift safeguards

`scripts/host-image-coherence-preflight.sh` refuses a stale image tag before apply.

### Vendor-tier reality check

No vendor resource is created in Part 1.

## Encryption Posture

```yaml
at_rest:
  - store: "hcloud_volume.workspaces_luks (existing, unchanged by Part 1)"
    mechanism: luks
    evidence: "implied by device_binding — workspaces-luks-provision.sh crypttab entry; it runs once, after the settle reboot"
    defends_against: "a seized or RMA'd disk; a raw volume snapshot"
    does_not_defend: "an unlocked running host; a leaked Doppler token that can fetch the key"
    disclosed_as: "not-publicly-claimed"
    live_verification: "available: the readiness verdict's luks= field"
in_transit:
  - connection: "none new"
    enforced_at: "n/a"
    tls: "unchanged"
    cert_verification: on
    does_not_defend: "n/a"
    disclosed_as: "not-publicly-claimed"
```

## Guard Contract

### Guard 1 — kernel-currency readiness predicate

**Property.** A web host emits `fresh_boot_ready` only while `uname -r` equals the version the installed
`linux-image-generic` points to.

**Assembly.** The single chokepoint is `soleur-fresh-boot-ready` (heredoc `FRESHREADYEOF`); its one caller is the
final runcmd line. `fresh-boot-ready.test.sh` S1 counts exactly one authoring.

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the kernel comparison from the READY predicate | RED (mismatch case reports ready) |
| 2 | Treat an empty target as a match | RED (empty-target case reports ready) |
| 3 | Rename the heredoc delimiter so extraction returns empty | RED (S0 + anti-vacuity floor) |

Harness rows: removing one case trips the exact-count floor; a matching host must PASS as ready.

### Guard 2 — single settle reboot before any non-idempotent step

**Property.** At most one reboot per birth, and it happens before any runcmd item that is not safe to run twice.

**Assembly.** Only the settle item may reboot; its marker under `/var/lib/soleur` (root disk) is the state the second
pass reads; the semaphore path appears once; the idempotent allowlist covers every item before it.

| # | Mutation | Expected |
|---|---|---|
| 1 | Ignore the marker (always reboot on mismatch) | RED (marker-present case reboots) |
| 2 | Move the marker to `/run` | RED (structural: marker under `/var/lib/soleur`) |
| 3 | Move the settle item after the `STAGE=doppler_dl` item | RED (allowlist / ordering row) |
| 4 | Drop `trap - EXIT` before the reboot | RED (order row: false fatal on shutdown) |
| 5 | Drop the semaphore-exists guard | RED (semaphore-absent case reboots) |
| 6 | Add a `power_state:` or `packages:` key | RED (structural row) |

## Architecture Decision (ADR/C4)

### ADR

Create `ADR-<next>` "First-boot kernel currency with one reboot at web host birth (create and replace)" via
`soleur:architecture`. It records:

- the mechanism (option C) and the rejected A (end-of-runcmd + unit), B (`packages:` + `package_reboot_if_required`,
  reverses #6090) and `cloud-init clean`;
- the one approved exception to ADR-257's "runcmd runs once per instance" (semaphore removal, fail-closed guard);
- that a reboot inside birth, before the host serves, keeps ADR-263's 2026-10-08 rule ("a host is replaced, not
  rebooted");
- that the ADR-263 claim boundary of the 2026-10-11 / 2026-10-12 addenda ("reopen after a host restart is not
  graded") is unchanged: under C, LUKS is provisioned once, after the reboot, so no reopen happens at birth;
- residual: the semaphore path is a cloud-init internal (guarded; a rename is a red run, not a silent pass).

ADR-263 gains a dated forward-pointer addendum (its addenda are append-only). Part 2 may need its own ADR or an
ADR-263 amendment (decided with the Part 2 ruling). Ordinals provisional.

### C4 views

Part 1: no C4 impact. Part 2 is re-checked against `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`
and `plugins/soleur/test/c4-count-parity.test.sh`.

### Sequencing

The ADR describes the target state; the births that exercise it are owner-authorized acts after merge.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from the brainstorm)

### Engineering

**Status:** reviewed (Part 1)
**Assessment:** CTO ruled option C on 2026-11-10 after a seven-reviewer plan review (binding constraints are the
Phase 1 rows and Guard 2). CTO dissent: the semaphore path is a cloud-init internal (guarded, fails closed); a second
apt update adds ~1 min. Flip condition: proof that an item before `apt_install` cannot safely run twice.

### Product

**Status:** reviewed (Part 1)
**Assessment:** CPO SIGN-OFF WITH CONDITIONS (applied). No UI surface (Product/UX tier NONE).

### Legal

**Status:** reviewed
**Assessment:** no notification trigger; ADR-322 wording for PR/commits/issues.

## Operator acts after merge (each needs the owner's typed go naming the exact command)

1. `Operator-authorizes:` `web-host-replace` for web-2, `plan_only=true` first, then the real run, with
   `-f image_tag=` set to the release that contains this PR. The agent arms a watch on the run and reads the boot
   trail (expected order: `kernel_reboot`, second `runcmd_start`, `cloud_init_complete`, `fresh_boot_ready`).
2. (Agent, read-only) Reader run: kernel column for the new host, the verdict's `kernel=1`, and the live LB pool
   (new origin enabled and healthy).
3. Later PRs 2–7 (Part 2 — PR sequence) each carry their own owner acts; none is authorized by this PR.
4. inngest/registry/git-data stay on #12503.

## Scope Check

### Ask Mapping

<!-- lint-infra-ignore start -->
| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "When Ubuntu ships the noble kernel fix: patch and reboot web hosts through the immutable-redeploy path (`hr-prod-host-config-change-immutable-redeploy`), no in-place SSH." [issue #12008] | Part 1; Operator acts 1–3 | mapped |
| 2 | "Define a standing kernel patch + reboot cadence per host class" [issue #12008] | — | descoped — justification: shipped in PR #12497 |
| 3 | "Check public TCP exposure of the non-web hosts." [issue #12008] | — | descoped — justification: shipped in PR #12497 |
| 4 | "Evaluate Ubuntu 26.04 LTS ([kernel version elided per ADR-322], supported to 2031) as a separate migration" [issue #12008] | — | descoped — justification: split to #12615 (CTO ruling) |
| 5 | "Did we patch the docker images as well in addition to hosts?" [brief] | — | descoped — justification: answered in session; containers share the host kernel |
| 6 | "shall we reboot or treat the hosts as immutable and just destroy them and have new machines instead?" [brief] | Overview; ADR | mapped — hosts are destroyed and re-born; the one reboot is inside the new host's birth |
| 8 | "Shall we consider a small bastion server/host instead?" [brief] | Part 2 ruling, PR 2–3 | mapped (later PRs) |
| 7 | "we should take the opportunity to destroy web-1 abd have its replacement be a proper terraform based approach like web-2 so we are con,sistent in how we manage our infrastructure" + "web-2 already takes traffic. So do 2" [brief] | Part 2 | mapped (in research) |

<!-- lint-infra-ignore end -->

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `cloud-init.yml` | ask 1 | asked |
| `soleur-host-bootstrap.sh` | ask 1 | asked |
| `scripts/fresh-host-boot-trail.sh` | — | inferred — justification: the trail's deadline must cover the reboot (P7) |
| `kernel-currency.test.sh`, `fresh-boot-ready.test.sh`, registration | — | inferred — justification: cq-write-failing-tests-before; Guards 1–2 rot without them |
| `cloud-init-user-data-size.test.ts` | — | inferred — justification: enforcing budget gate (P6) |
| runbooks | ask 1 | asked |
| ADR + ADR-263 addendum | — | inferred — justification: records the ADR-257 exception |
| Part 2a (keyed `var.web_hosts`, dynamic LB origins, derived IP lists, generalized soak gate, ratchet, census) | ask 7 | asked |
| Bastion, private LB (later PRs) | "Shall we consider a small bastion server/host instead?" + approvals [brief] | asked |

### Split Assessment

- Subsystems touched: 4 — apps/web-platform, scripts, .github, knowledge-base (plugins/soleur only on a re-baseline)
- Planned files: ~25 | Estimated changed lines: ~650
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: this PR = Part 1 + Part 2a; PRs 2–7 follow (CTO ruling). The owner asked for one combined PR; the
  split was presented with the CTO's reasons (a merge cannot birth a host; deleting web-1 code while it runs destroys
  it at merge) and the owner accepted the bastion design built on it (2026-11-10).

## Acceptance Criteria (Part 2a)

- [x] `var.web_hosts` has `lb_weight`, `luks_monitor_profile`, `jump` with validations (exactly one primary profile, exactly one jump, unique in-subnet `private_ip`); today's values reproduce the current config.
- [x] LB pool origins come from a `dynamic` block over `var.web_hosts`; `web_tunnel_connector` reads a keyed field.
- [x] `WEB_HOST_PRIVATE_IPS` is derived in HCL and a parity test pins every workflow copy.
- [x] `lb-weight-gate.sh` no longer names `web-2` literally; its tests cover a third key.
- [x] Ratchet test for the web-1 private IP literal and `"web-1"` outside an allowlist, ceiling = today's count.
- [x] Host-bound-state census committed with test rows.
- [x] `terraform plan` (web-platform root) shows no change to servers, volumes, attachments, tunnel or LB pool; result quoted in the PR body.

## Acceptance Criteria (Part 1)

<!-- founder-stated check: see plan-founder-check.md -->

- [x] `linux-image-generic` is on the bounded `apt-get install` line inside `STAGE=apt_install`, and the retry runs `dpkg --configure -a` before attempt 2 (kernel-currency.test.sh structural rows).
- [x] The settle item is the runcmd item right after the apt block; every earlier item is on the idempotent allowlist; no Doppler/docker/`/mnt/data`/LUKS reference precedes it (structural rows).
- [x] The five settle behaviour cases pass (match; mismatch+no marker → one reboot after `trap - EXIT` and semaphore removal; mismatch+marker → fatal; unreadable → fatal; semaphore absent → fatal).
- [x] `soleur-fresh-boot-ready` reports not-ready `kernel` on mismatch or empty target and ready on match (fresh-boot-ready.test.sh rows).
- [x] `DEADLINE` and `SOLEUR_FRESH_BOOT_WINDOW_SECONDS` moved together; computed worst cases stay under the create (30 min) and replace (40 min) job limits (budget rows).
- [x] Rendered web user_data is under `WEB_GZIP_BUDGET`, or the budget is re-baselined with the measured number in the PR body.
- [x] All Guard Contract mutation rows (Guards 1–2) were driven RED once during work; results recorded in the PR body.
- [x] The new suite is registered (`suite-shard-legs.tsv` + `guard-vacuity-floor.test.sh` promotion) and CI runs it.
- [x] ADR + ADR-263 forward-pointer addendum created; runbooks updated; spec FR2/FR3/TR4 match ruling C; no kernel string, vulnerability id, host address or exposure verdict in any changed file, the PR body or commits (ADR-322).
- [x] `plugins/soleur/test/c4-count-parity.test.sh` green.

## Test Scenarios (Part 1)

- Given a host whose running kernel equals the target, when the settle item runs, then no reboot and runcmd continues (unit).
- Given a mismatch and no marker, when the settle item runs, then marker written, `kernel_reboot` emitted, `trap - EXIT`, semaphore removed, one reboot (unit, stubbed).
- Given a mismatch and the marker, when the settle item runs, then exit 1 with `STAGE=kernel_settle` and no reboot (unit).
- Given an unreadable target or a missing semaphore, when the settle item runs, then exit 1 and no reboot (unit).
- Given a new runcmd item inserted before the settle item, when the suite runs, then the allowlist row fails (structural).
- Given a matching kernel, when the verdict runs, then `kernel=1` and ready; given a mismatch, not-ready `kernel` (unit).

## Dependencies & Risks

- The semaphore path is a cloud-init internal; guarded (fatal if absent). The rehearsal (web-2) confirms runcmd
  re-runs on the second boot before web-1 is touched.
- The base image may ship a different kernel flavour meta; the target is read from `linux-image-generic`
  specifically and the verdict's predicate checks what actually booted.
- The replace must use an image tag that contains this PR's bootstrap; the coherence preflight refuses a stale one.
- During either birth, one origin carries all traffic: capacity check before each replace.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- The settle step must stay inline and minimal: it runs before the bootstrap is seeded, and user_data headroom is ~180 B.
- The reboot command returns before shutdown; the `sleep 600` keeps the script from continuing into non-idempotent items. Do not replace it with `exit 0`.
- `on_err` is armed by `trap on_err EXIT`; any `exit` in the settle step without `trap - EXIT` first emits a fatal. That is wanted for the fatal branches and wrong for the reboot branch.
