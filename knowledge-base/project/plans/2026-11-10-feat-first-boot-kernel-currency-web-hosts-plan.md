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

# feat(infra): first-boot kernel currency for web hosts

Ref #12008 (item 1, code half only). Public-repository rule (ADR-322): this file carries no kernel string,
vulnerability id, host address or exposure verdict. Per-host answers stay in the session.

## Overview

A replaced web host boots the stock base image and installs four named packages, so it runs the base image's
kernel: a replace is a rebuild, not a kernel refresh. This plan makes a replaced web host install the generic
kernel meta package during its bounded apt step and, when the running kernel differs from it, reboot **once** and
emit its readiness verdict only **after** that reboot. The replace job's boot trail already polls for that verdict;
this plan lengthens its wait when the host announces the reboot and makes a missing verdict after a reboot fail the
run, so the reboot is graded, and the verdict itself proves the new kernel is running. Web class only. Merging changes
no running host.

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Reality (evidence) | Plan response |
|---|---|---|
| "cloud-init reboots once at the very end of first boot, before the host is graded healthy" (spec FR2/FR3, first CTO ruling) | The replace job's verdict is the LAST runcmd item (`cloud-init.yml`, the `soleur-fresh-boot-ready \|\| true` line); `fresh-host-boot-trail.sh` stops at that verdict. A cloud-init `power_state` reboot runs after runcmd, i.e. after the job is green, and is never observed. | Amended (CTO re-ruling, 2026-11-10): the reboot happens **before** the verdict; a one-shot post-reboot unit emits the verdict. FR2/FR3 are restated below. |
| "a sibling test (shape of `apt-bounded.test.sh`)" | `apt-bounded.test.sh` tests `lib/apt-bounded.sh`; the web template is not one of its consumers (0 matches for `cloud-init.yml`). The readiness surface is already pinned by `fresh-boot-ready.test.sh` (S1–S10). | New suite `kernel-currency.test.sh` borrows apt-bounded's instrument self-test + anti-vacuity counter; `fresh-boot-ready.test.sh` is extended for the new predicate. |
| "User-data size: measure headroom first" | `WEB_GZIP_BUDGET = 25_000` (`plugins/soleur/test/cloud-init-user-data-size.test.ts`), last measured ~24,820 CI → ~180 B headroom; Hetzner cap 32,768 is ~7.7 KB away. | All logic is baked into `soleur-host-bootstrap.sh` (0 user_data); the inline delta is one package token plus one changed call. No budget raise planned; if the measurement exceeds the budget, the work phase trims comments first, per that file's re-baseline convention. |
| "reboot survivability is not graded" (ADR-263 addendum) | `workspaces-luks-reopen.service` (WantedBy multi-user, key from Doppler, 15-min retry timer), crypttab `luks,noauto`, `/mnt/data` `nofail`, docker `RequiresMountsFor=/mnt/data`, app `--restart unless-stopped`, `cron-egress-firewall.service` enabled. The egress-enforcement proof (`cron-egress-enforce-probe.sh`) runs only in runcmd. | The post-reboot unit re-runs the enforcement proof (poweroff on failure, same as runcmd) and the readiness verdict checks volume+LUKS+kernel+boot_id, so the one reboot this plan adds is graded. |

## Research Insights

**Premise validation (2026-11-10).** #12008 is open; owner comment 2026-11-10T18:03Z records that the distro now
ships the fixed generic kernel for 24.04 (re-evaluation trigger fired). #12503 is open and was narrowed today to
inngest, registry and git-data. #9421 (refused-host de-pet) is open, p3, last update 2026-10-03. PR #12497 (items 2–3)
is merged. Collision pre-check: the only open PR naming #12008 is this branch's own draft PR #12613; two `test-all.sh`
processes owned by another worktree were running (unrelated). Live reader: kernel column `unknown` on every row
(emitter not yet rolled out, #12386), so post-replace kernel verification relies on this plan's readiness verdict
until #12386 lands.

**Property list (Phase 0.6b).**

- P1: A replaced web host is graded ready only while running the kernel version the generic meta package points to.
- P2: A kernel-install failure or hang during first boot is a named fatal, never a silent continue.
- P3: At most one reboot per host birth; a second mismatched boot is a named fatal, not a loop.
- P4: After the reboot, the host does not report ready unless the workspaces volume is mounted, LUKS is open and
  container egress enforcement is re-proven.
- P5: Merging this change alters no running host.
- P6: Rendered web user_data stays under `WEB_GZIP_BUDGET`.

**Cut list.**

- cloud-init `power_state` end-of-boot reboot → P1 → cut: it fires after the verdict and is never observed (replaced by the pre-verdict reboot).
- `/var/run/reboot-required` as the trigger → P1 → cut: depends on a package not verified on the image; the dpkg-query / `uname -r` comparison covers it.
- Full `apt-get upgrade` / pinned kernel version / baked snapshot image → P1 → cut (CTO): behaviour drift, staleness, new subsystem respectively.
- `linux-generic` (with headers) → P1 → cut: nothing on the host builds modules; `linux-image-generic` suffices.

**Relevant files.**

- `apps/web-platform/infra/cloud-init.yml` — bounded apt block (`STAGE=apt_install`, the `apt-get install -y ... curl fail2ban jq nftables` line), egress enforce probe + poweroff, `soleur-vector-install`, final `soleur-fresh-boot-ready || true`.
- `apps/web-platform/infra/soleur-host-bootstrap.sh` — authors `/usr/local/bin/soleur-fresh-boot-ready` (heredoc `FRESHREADYEOF`); baked into the app image and hash-pinned by user_data (`server.tf` `local.host_script_files`).
- `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh` — Sentry poll: `DEADLINE=SECONDS+960`, `CC_GRACE=210`, terminal `complete_no_readiness`.
- `apps/web-platform/infra/fresh-boot-ready.test.sh` — S7 (call site after vector-install), S8b (`|| true`).
- `plugins/soleur/test/cloud-init-user-data-size.test.ts` — `WEB_GZIP_BUDGET`.
- `.github/workflows/apply-web-platform-infra.yml` — the `web_host_replace` job, `timeout-minutes: 40`; its boot-trail step is `if: always()`. Trail terminals: a `fatal` boot stage exits 1 (job red); `complete_no_readiness` (marker seen, no verdict within `CC_GRACE`) is a `::warning::` and exits 0 — a missing verdict does NOT redden the run today.
- `knowledge-base/engineering/operations/runbooks/web-host-replace.md` — `-f image_tag=` (default reads the refused host's tag).

**Learnings applied.**

- `knowledge-base/project/learnings/best-practices/2026-07-07-cloud-init-user-data-cap-is-measured-on-the-gzipped-render.md` — measure the render, not the raw file.
- `knowledge-base/project/learnings/2026-07-03-cloud-init-32kb-cap-bake-and-extract-not-compress.md` — bake logic, do not inline it.
- `knowledge-base/engineering/architecture/decisions/ADR-257-inngest-host-provisioning-runs-in-a-latched-retrying-unit.md` — runcmd is once per instance; work that must survive a boot lives in a unit.
- `knowledge-base/project/learnings/2026-04-19-cloud-init-packages-stage-silent-drop-audit.md` — install inside the bounded, fail-closed runcmd block, never `packages:`.
- `knowledge-base/project/learnings/bug-fixes/2026-07-13-warm-standby-cross-dc-and-replace-capacity-footgun.md` — check capacity before any replace (operator act sequencing).
- `knowledge-base/project/learnings/2026-11-10-a-failover-premise-must-be-checked-against-the-serving-topology.md` — the replaceable web host carries no app serving weight.

**External research:** skipped — the mechanism is local cloud-init/systemd/dpkg; strong local precedent.

## Proposed Solution

1. **Install.** The bounded apt install line in `cloud-init.yml` gains `linux-image-generic`, inside the existing
   `timeout` + 2-attempt + `STAGE=apt_install` contract (P2).
2. **Decide (baked).** `soleur-host-bootstrap.sh` authors `/usr/local/bin/soleur-kernel-settle`. It reads the kernel
   version `linux-image-generic` depends on (`dpkg-query -W -f='${Depends}' linux-image-generic`, the
   `linux-image-<ver>` token) and compares it with `uname -r` and the newest `/boot/vmlinuz-*`.
   - Equal → exit 0 (the caller runs `soleur-fresh-boot-ready` as today).
   - Different and no pending marker → write `/var/lib/soleur/kernel-settle.pending` (target version + the current
     boot_id), install and enable `soleur-kernel-settle-ready.service`, emit boot stage `kernel_reboot`, then
     `systemctl reboot` and exit 1 so the caller skips the verdict.
   - Different and a pending marker exists (second boot still mismatched) → emit `kernel_settle_no_change` fatal and
     exit 0 so the verdict still runs and reports not-ready (P3).
   - Unreadable package/`/boot` state → emit `kernel_settle_unreadable` fatal and exit 0 (fail loud; the verdict's
     kernel predicate then fails, see 4).
3. **Post-reboot unit (baked).** `soleur-kernel-settle-ready.service`, `Type=oneshot`,
   `ConditionPathExists=/var/lib/soleur/kernel-settle.pending`,
   `After=network-online.target docker.service workspaces-luks-reopen.service`. It waits at most 300 s for
   `/mnt/data` mounted and the app container running (else emits `kernel_settle_wait_timeout` fatal and continues),
   re-runs `/usr/local/bin/cron-egress-enforce-probe.sh` with the runcmd semantics (`egress_enforce_probe` fatal +
   `poweroff -f` on failure), runs `soleur-fresh-boot-ready`, then removes the marker and disables itself.
4. **Verdict proves the patch.** `soleur-fresh-boot-ready` adds `kernel=` and, when the pending marker is present,
   requires `uname -r` = target version AND boot_id ≠ the saved one; otherwise `fresh_boot_not_ready_kernel` fatal.
   Without a marker the predicate is the same comparison (`uname -r` = target), so a host that needed no reboot
   still proves currency.
5. **Call site.** The last runcmd item becomes
   `BETTERSTACK_INGEST_URL='${betterstack_ingest_url}' soleur-kernel-settle && BETTERSTACK_INGEST_URL='${betterstack_ingest_url}' soleur-fresh-boot-ready || true`
   (or an equivalent single export; keep S7/S8b true). Still after `soleur-vector-install`.
6. **Grace and grading.** `fresh-host-boot-trail.sh`: on seeing `kernel_reboot` (run-anchored, host-attributed, same
   jq filters as the other stages), raise `CC_GRACE` to 600 s and the deadline to 1,560 s, and turn the no-verdict
   outcome into a new red terminal `kernel_reboot_no_readiness` (`::error::`, exit 1) instead of the
   `complete_no_readiness` warning. Reason: today's warning exists because a missing verdict may be a lost Sentry
   event; once the host announced a reboot, a missing verdict means the host may not have come back, which is the
   exact failure this change must grade. `kernel_settle_*` and `fresh_boot_not_ready_kernel` fatals take the existing
   `fatal` terminal (exit 1). Budget: worst case ≈ pre-poll (~2.6 min measured, script comment) + 1,560 s + one
   iteration (~50 s) ≈ 30 min against the job's 40-minute limit; the work phase updates the script's "40m (replace)"
   cost comment and, if the apply step's own time on a replace leaves < 5 min margin, raises the job limit in the
   same PR.

## Implementation Phases

**Phase 1 — RED tests (cq-write-failing-tests-before).**

- `apps/web-platform/infra/kernel-currency.test.sh` (new): extract the `soleur-kernel-settle` and unit heredocs from
  `soleur-host-bootstrap.sh` and run them with stubbed `dpkg-query`, `uname`, `/boot`, `systemctl`, `soleur-boot-emit`
  under a temp root. Cases: equal → exit 0, no marker, no reboot; different → marker written with boot_id, unit
  enabled, `kernel_reboot` emitted, `systemctl reboot` called once, exit 1; different + marker → no reboot,
  `kernel_settle_no_change` fatal, exit 0; unreadable dpkg → fatal, exit 0. Structural: `linux-image-generic` on the
  bounded `apt-get install` line inside `STAGE=apt_install`; `soleur-kernel-settle` call site precedes
  `soleur-fresh-boot-ready` on the final runcmd line, after `soleur-vector-install`; no `power_state:` key and no
  bare `reboot` in `cloud-init.yml`; unit has the `ConditionPathExists` and `After=` set; unit runs the enforce probe
  before the verdict and `poweroff -f` on probe failure. Instrument self-test + exact-count anti-vacuity floor
  (apt-bounded pattern).
- `apps/web-platform/infra/fresh-boot-ready.test.sh`: new rows for the kernel predicate (marker present: match +
  new boot_id → ready; same boot_id → not-ready `kernel`; mismatch → not-ready `kernel`; no marker + match → ready).
- Boot-trail grace test: a fixture event stream with `kernel_reboot` then a verdict arriving at 400 s after
  `cloud_init_complete` must end `fresh_boot_ready`; the same stream without `kernel_reboot` must end
  `complete_no_readiness` (exit 0); `kernel_reboot` with no verdict past 600 s must end `kernel_reboot_no_readiness`
  (exit 1); a `kernel_reboot` event from another host or before the run anchor must NOT extend the grace. Put it in the existing trail test if one exists (`git grep -l fresh-host-boot-trail -- '*.test.*'`),
  else in `kernel-currency.test.sh`.
- Register the new suite the way `apt-bounded.test.sh` is (#9379): a row in
  `apps/web-platform/infra/suite-shard-legs.tsv` (and `suite-durations.tsv` if the registration test requires it),
  enforced by `.github/scripts/test/test-infra-suite-registration.sh`; and, because it is a new floor-bearing suite
  in a deferred directory, a promotion entry in `scripts/guard-vacuity-floor.test.sh` (do NOT raise `MAX_DEFERRED`;
  the floor must be a per-row `$checked` counter with a `pass + fail == checked` conservation check emitted via
  `printf` + `exit 1`, plus the instrument self-test).

**Phase 2 — GREEN.** Edit `cloud-init.yml`, `soleur-host-bootstrap.sh`, `scripts/fresh-host-boot-trail.sh` per
Proposed Solution. Re-run `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` and print the measured
render; if over budget, trim comments in `cloud-init.yml` first.

**Phase 3 — Docs + ADR.** New ADR via `soleur:architecture` ("First-boot kernel currency with one graded reboot on web
host create"), amending the ADR-263 2026-10-08 addendum's "reopen after restart is not graded" for this one reboot.
Runbook updates (ADR-322 wording): `host-kernel-patch-cadence.md` (web: a replace now brings the archive's kernel;
verification is the readiness verdict until #12386; release-then-replace order) and `web-host-replace.md` (expect one
reboot; longer boot-trail window; pass `-f image_tag=` explicitly).

## Files to Edit

- `apps/web-platform/infra/cloud-init.yml`
- `apps/web-platform/infra/soleur-host-bootstrap.sh`
- `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh`
- `apps/web-platform/infra/fresh-boot-ready.test.sh`
- `plugins/soleur/test/cloud-init-user-data-size.test.ts` (only if the budget comment/re-baseline is needed)
- `knowledge-base/engineering/operations/runbooks/host-kernel-patch-cadence.md`
- `knowledge-base/engineering/operations/runbooks/web-host-replace.md`
- `apps/web-platform/infra/suite-shard-legs.tsv` (+ `suite-durations.tsv` if required)
- `scripts/guard-vacuity-floor.test.sh` (promotion entry for the new floor-bearing suite)

## Files to Create

- `apps/web-platform/infra/kernel-currency.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-<next>-first-boot-kernel-currency-graded-reboot.md` (ordinal provisional; re-check at ship)

## Open Code-Review Overlap

None (checked `cloud-init.yml`, `soleur-host-bootstrap.sh`, `fresh-host-boot-trail.sh`, `fresh-boot-ready.test.sh`,
`cloud-init-user-data-size.test.ts`, `host-kernel-patch-cadence.md` against open `code-review` issues, 2026-11-10).

## User-Brand Impact

- **If this lands broken, the user experiences:** a web host replace that reports ready while running the old kernel
  (false "patched"), or a replaced standby that reboots and comes back with the workspaces volume locked or egress
  enforcement unproven, so the next failover serves users from a host whose sandbox egress is not enforced.
- **If this leaks, the user's data is exposed via:** a host that serves repository workspaces with container egress
  enforcement not re-proven after the reboot (agent sandbox could reach non-allowlisted destinations).
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the replaced host holds users' workspace volume and runs their agent
  sandboxes; one bad reboot path exposes one user's data, which is the single-user tier, not aggregate.

CPO sign-off: the brainstorm triad (CPO, CLO, CTO) assessed this surface on 2026-11-10; the plan-review panel
re-checks the amended reboot design. `soleur:engineering:review:user-impact-reviewer` runs at review.

## Observability

```yaml
liveness_signal:
  what: "Sentry boot stages from the replaced host: kernel_reboot (info), then fresh_boot_ready (info) or fresh_boot_not_ready_kernel / kernel_settle_* (fatal); Better Stack SOLEUR_FRESH_BOOT_READY line with kernel= field"
  cadence: "per host birth"
  alert_target: "the replace job's boot-trail step (red run) + existing Sentry fatal issue alerts for soleur-cloud-init boot stages"
  configured_in: "apps/web-platform/infra/soleur-host-bootstrap.sh (emitters), apps/web-platform/infra/scripts/fresh-host-boot-trail.sh (poll), apps/web-platform/infra/sentry/issue-alerts.tf (alerts)"
error_reporting:
  destination: "Sentry (SOLEUR_SENTRY_DSN baked at birth) via soleur-boot-emit; Better Stack logs via soleur-fresh-boot-ready"
  fail_loud: "boot-trail ::error:: + exit 1 on any fatal stage (fresh_boot_not_ready_kernel, kernel_settle_no_change, kernel_settle_unreadable, kernel_settle_wait_timeout, egress_enforce_probe) or on terminal kernel_reboot_no_readiness"
failure_modes:
  - mode: "kernel package install hangs or fails"
    detection: "existing STAGE=apt_install named fatal (timeout + set -e)"
    alert_route: "boot-trail red run + Sentry fatal"
  - mode: "host reboots but the running kernel is still the old one"
    detection: "kernel_settle_no_change fatal + fresh_boot_not_ready_kernel"
    alert_route: "boot-trail red run + Sentry fatal"
  - mode: "host does not come back, or LUKS/volume/container not up within 300 s"
    detection: "kernel_settle_wait_timeout fatal, or no verdict within the extended grace after kernel_reboot (kernel_reboot_no_readiness, exit 1)"
    alert_route: "boot-trail red run"
  - mode: "egress enforcement not re-proven after reboot"
    detection: "egress_enforce_probe fatal + poweroff -f (same as runcmd)"
    alert_route: "boot-trail red run + Sentry fatal"
logs:
  where: "journald on the host (SyslogIdentifier soleur-kernel-settle / SOLEUR_FRESH_BOOT_READY), Better Stack via Vector, Sentry events"
  retention: "Better Stack plan retention; Sentry project retention"
discoverability_test:
  command: "bash apps/web-platform/infra/kernel-currency.test.sh"
  expected_output: "0 failed"
```

## Infrastructure (IaC)

### Terraform changes

None to `.tf` files. `cloud-init.yml` is a `templatefile()` source rendered into `hcloud_server.web[*].user_data`;
the web servers carry `lifecycle.ignore_changes = [user_data, ssh_keys, image, placement_group_id]`
(`apps/web-platform/infra/server.tf`), so the per-merge apply does not replace or update any running server.

### Apply path

(b) `terraform apply -replace` through the existing owner-authorized `web-host-replace` route, for the replaceable
web host only, after the release that bakes the new `soleur-host-bootstrap.sh` into the app image, passing that tag
explicitly (`-f image_tag=`). Expected: one extra reboot (~1–3 min) inside the boot-trail window; the replaceable
host carries no app serving weight, so no user-visible outage.

### Host fan-out

No `terraform_data` SSH provisioner is added or changed.

### Distinctness / drift safeguards

The baked-script hash in user_data fails a boot loudly on a stale image (existing gate), so a replace with an image
older than this PR aborts rather than running mismatched logic. The refused web host is untouched (`ignore_changes`).

### Vendor-tier reality check

No vendor resource is created.

## Encryption Posture

```yaml
at_rest:
  - store: "hcloud_volume.workspaces_luks (existing, unchanged)"
    mechanism: luks
    evidence: "implied by device_binding — workspaces-luks-provision.sh crypttab entry; unchanged by this plan"
    defends_against: "a seized or RMA'd disk; a raw volume snapshot"
    does_not_defend: "an unlocked running host; a leaked Doppler token that can fetch the key; code running inside the host after the post-reboot reopen"
    disclosed_as: "not-publicly-claimed"
    live_verification: "available: the readiness verdict's luks= field after the reboot"
in_transit:
  - connection: "none new (the reboot re-uses the existing Doppler key fetch of workspaces-luks-reopen.service)"
    enforced_at: "apps/web-platform/infra/workspaces-luks-reopen.sh (unchanged)"
    tls: "HTTPS to Doppler, unchanged"
    cert_verification: on
    does_not_defend: "a compromised Doppler account; a host already compromised before the reboot"
    disclosed_as: "not-publicly-claimed"
```

## Guard Contract

### Guard 1 — kernel-currency readiness predicate

**Property.** A web host emits `fresh_boot_ready` only while `uname -r` equals the kernel version the installed
`linux-image-generic` points to, and, after a settle reboot, only on a boot whose boot_id differs from the one
recorded before that reboot.

**Assembly.** The single chokepoint is the authored `soleur-fresh-boot-ready` helper (heredoc `FRESHREADYEOF` in
`soleur-host-bootstrap.sh`); its two callers are the final runcmd line in `cloud-init.yml` and
`soleur-kernel-settle-ready.service`. Both must reach the same helper; no second readiness emitter may exist
(`fresh-boot-ready.test.sh` S1 counts exactly one authoring).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the kernel comparison from the READY predicate | RED (mismatch case reports ready) |
| 2 | Make the suite's extraction of the helper body return empty (rename the heredoc delimiter) | RED (S0 + anti-vacuity floor) |
| 3 | Add a second `cat > /usr/local/bin/soleur-fresh-boot-ready` authoring after a compliant first | RED (S1 count) |
| 4 | Compare boot_id against the current boot instead of the saved one | RED (same-boot case reports ready) |
| 5 | Reorder: unit runs the verdict before the egress enforce probe | RED (unit order row) |

Harness rows: removing one behaviour case from the suite trips the exact-count floor (RED); a host with a matching
kernel and no marker (needed no reboot) must PASS as ready.

### Guard 2 — single-reboot loop guard

**Property.** `soleur-kernel-settle` calls `systemctl reboot` at most once per host birth.

**Assembly.** Only `soleur-kernel-settle` may reboot; the pending marker under `/var/lib/soleur` (root disk, survives
reboot) is the one state the decision reads. `cloud-init.yml` must carry no `power_state:` key and no other reboot.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Ignore the pending marker (always reboot on mismatch) | RED (marker-present case calls reboot) |
| 2 | Move the marker to `/run` | RED (structural row: marker path under `/var/lib/soleur`) |
| 3 | Add a `power_state:` block or a second `reboot` call after the compliant settle call | RED (structural row) |

### Guard 3 — boot-trail grading of the settle reboot

**Property.** When this run's host announced `kernel_reboot`, the replace run is green only if a `fresh_boot_ready`
verdict from that host follows; otherwise it is red.

**Assembly.** One chokepoint: the poll loop in `fresh-host-boot-trail.sh`, shared by the create and replace steps.
The `kernel_reboot` match must use the same `hostok` + `sincok` filters as the `cloud_init_complete` match.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Keep `complete_no_readiness` (exit 0) after `kernel_reboot` | RED (no-verdict-after-reboot case exits 0) |
| 2 | Drop `sincok` from the `kernel_reboot` match | RED (predecessor-event case extends grace) |
| 3 | Extend grace unconditionally (no `kernel_reboot` needed) | RED (no-reboot case ends after 600 s, not 210 s) |

Harness row: the no-reboot fixture must still end `complete_no_readiness` exit 0 (today's behaviour preserved).

## Architecture Decision (ADR/C4)

### ADR

Create `ADR-<next>` "First-boot kernel currency with one graded reboot on web host create" via `soleur:architecture`;
it amends the ADR-263 2026-10-08 addendum's claim boundary ("reopen after a host restart is not graded") for this
single settle reboot, which is now graded by the readiness verdict. Ordinal provisional.

### C4 views

No C4 impact. Checked: no new external actor (the host's existing Ubuntu archive egress is already the apt path), no
new external system (Doppler, Sentry, Better Stack already modeled as consumers of the web host), no container or data
store added, no access relationship changed. The work phase confirms by reading
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` and running
`plugins/soleur/test/c4-count-parity.test.sh` green.

### Sequencing

The ADR describes the target state; the replace that exercises it is an owner-authorized act after merge.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from the brainstorm's `## Domain Assessments`)

### Engineering

**Status:** reviewed
**Assessment:** CTO ruled the design (re-ruled 2026-11-10 for the pre-verdict graded reboot): `linux-image-generic`,
dpkg-query/`uname -r` predicate, marker under `/var/lib/soleur`, verdict proves kernel + new boot_id, 600 s / 1,560 s
grace on `kernel_reboot`, egress probe re-run, web class only.

### Product

**Status:** reviewed
**Assessment:** exposure outweighs minutes of downtime; gate "patched" on the new host's kernel reading. No UI surface
(Product/UX tier NONE). User notice applies only to an owner act on the refused host, not to this change.

### Legal

**Status:** reviewed
**Assessment:** no notification trigger; ADR-322 wording for PR/commits/issues; timeliness target for replaceable
hosts is the owner's operator act after merge.

## Operator acts after merge (each needs the owner's typed go naming the exact command)

1. `Operator-authorizes:` `web-host-replace` for the replaceable web host, `plan_only=true` first, then the real run,
   with `-f image_tag=` set to the release that contains this PR. The agent arms a watch on the run and reads the
   verdict from the run log.
2. (Agent, read-only) Reader run plus the boot-trail verdict: kernel predicate passed.
3. `Operator-reserved:` the refused web host — one-off immutability exception (owner performs) or raise #9421.
4. inngest/registry/git-data stay on #12503.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "When Ubuntu ships the noble kernel fix: patch and reboot web hosts through the immutable-redeploy path (`hr-prod-host-config-change-immutable-redeploy`), no in-place SSH." [issue #12008] | Proposed Solution 1–6; Operator acts 1–3 | mapped (code half here; acts after merge) |
| 2 | "Define a standing kernel patch + reboot cadence per host class" [issue #12008] | — | descoped — justification: shipped in PR #12497 |
| 3 | "Check public TCP exposure of the non-web hosts." [issue #12008] | — | descoped — justification: shipped in PR #12497 |
| 4 | "Evaluate Ubuntu 26.04 LTS (Linux 7.0, supported to 2031) as a separate migration" [issue #12008] | — | descoped — justification: split to #12615 (CTO ruling) |
| 5 | "Did we patch the docker images as well in addition to hosts?" [brief] | — | descoped — justification: answered in session; containers share the host kernel, no image change applies |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `cloud-init.yml` | ask 1 | asked |
| `soleur-host-bootstrap.sh` | ask 1 | asked |
| `scripts/fresh-host-boot-trail.sh` | — | inferred — justification: the replace job must observe the reboot or the verdict is never graded (P1, P4) |
| `kernel-currency.test.sh`, `fresh-boot-ready.test.sh`, test registration | — | inferred — justification: cq-write-failing-tests-before; the guard contracts rot without them |
| `cloud-init-user-data-size.test.ts` | — | inferred — justification: the 25,000 B budget is an enforcing gate on this file |
| runbooks (`host-kernel-patch-cadence.md`, `web-host-replace.md`) | ask 1 | asked |
| ADR | — | inferred — justification: wg-architecture-decision-is-a-plan-deliverable (amends ADR-263 addendum) |

### Split Assessment

- Subsystems touched: 3 — apps/web-platform, plugins/soleur, knowledge-base
- Planned files: 13 | Estimated changed lines: ~450
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

- [ ] `linux-image-generic` is on the bounded `apt-get install` line inside `STAGE=apt_install` in `cloud-init.yml` (kernel-currency.test.sh structural row).
- [ ] `soleur-host-bootstrap.sh` authors `soleur-kernel-settle` and `soleur-kernel-settle-ready.service`; the four behaviour cases in Phase 1 pass (kernel-currency.test.sh).
- [ ] `soleur-fresh-boot-ready` reports not-ready `kernel` on mismatch or same boot_id and ready on match + new boot_id or match without marker (fresh-boot-ready.test.sh new rows).
- [ ] The final runcmd line calls `soleur-kernel-settle` before `soleur-fresh-boot-ready`, after `soleur-vector-install`, ends `|| true`; `cloud-init.yml` has no `power_state:` key (S7, S8b, structural rows).
- [ ] `fresh-host-boot-trail.sh` extends grace to 600 s and deadline to 1,560 s after this host's in-window `kernel_reboot` only, and ends `kernel_reboot_no_readiness` (exit 1) when no verdict follows (grace test).
- [ ] Rendered web user_data stays under `WEB_GZIP_BUDGET` (`bun test plugins/soleur/test/cloud-init-user-data-size.test.ts`).
- [ ] All Guard Contract mutation rows (Guards 1–3) were driven RED once during work and the result recorded in the PR body.
- [ ] New suites are registered where `fresh-boot-ready.test.sh` is, and CI runs them.
- [ ] ADR created; runbooks updated; no kernel string, vulnerability id, host address or exposure verdict in any changed file, the PR body or commits (ADR-322).
- [ ] `plugins/soleur/test/c4-count-parity.test.sh` green.

## Test Scenarios

- Given a host whose running kernel equals the meta package's target, when runcmd ends, then no reboot, `fresh_boot_ready` with `kernel=1` (unit).
- Given a mismatch and no marker, when `soleur-kernel-settle` runs, then marker + unit written, `kernel_reboot` emitted, one `systemctl reboot`, verdict skipped (unit).
- Given the marker and a matching kernel on a new boot, when the unit runs, then enforce probe runs first, then `fresh_boot_ready`, marker removed (unit).
- Given the marker and a still-mismatched kernel, when `soleur-kernel-settle` runs again, then no reboot and `kernel_settle_no_change` fatal (unit).
- Given the enforce probe fails after reboot, when the unit runs, then `egress_enforce_probe` fatal and `poweroff -f` (unit, stubbed).
- Given a Sentry stream with `kernel_reboot` and a verdict 400 s after `cloud_init_complete`, when the trail runs, then terminal `fresh_boot_ready`; without `kernel_reboot`, terminal `complete_no_readiness` (unit, fixture).

## Dependencies & Risks

- Unverified until the first rehearsal: LUKS reopen on the first reboot (key fetched from Doppler); bounded by the 300 s wait + fatal (CTO dissent).
- The replace must use an image tag containing this PR's bootstrap; a stale tag aborts at the existing hash gate.
- The Hetzner image's installed kernel meta may be `linux-image-virtual`; installing `linux-image-generic` beside it is expected to coexist (both resolve to the generic flavor) — verified by the rehearsal's verdict, not assumed.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- Do not inline the settle logic into `cloud-init.yml`: ~180 B budget headroom.
- The readiness verdict is observability-only today (`|| true`); this plan adds a predicate, not a gate on runcmd.
