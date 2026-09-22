---
title: "fix(infra): converge the inngest host's late-attached private NIC before the zot pull"
date: 2026-09-22
slug: fix-inngest-private-nic-boot-race
branch: feat-one-shot-8539-inngest-nic-race
issue: 8539
closes: 8539
type: bug
priority: p1
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

# fix(infra): converge the inngest host's late-attached private NIC before the zot pull

## Overview

A replace of the dedicated Inngest host can boot before its private network attachment is
configured in the guest. The cloud-init zot login and bootstrap image pull then time out against
10.0.1.30, the GHCR fallback is unavailable, and the boot aborts with no scheduler running. This
plan picks the fix for that race after checking the two candidate shapes named on #8539.

## Research Insights

### Premise Validation (Phase 0.6)

- **#8539** is OPEN (p1, type/bug); nothing has closed it. **#6500** and **#6122** are OPEN and are
  referenced only with `Ref` (never a closing keyword). **#6415** and **#6400** are CLOSED (history
  only). **#6438** is OPEN and is the umbrella for "extend private-NIC convergence beyond the
  registry (git-data / inngest / web hosts, plus the off-host probe)" — this plan delivers the
  inngest first-boot slice of its item 2 and is `Ref #6438`, not a close.
- Cited artifacts exist on this branch (= `origin/main` at `ec68b3ec42`):
  `apps/web-platform/infra/network.tf:81-86` (`hcloud_server_network.inngest`),
  `inngest-host.tf:451-560` (`hcloud_server.inngest`, `public_net` enabled, no
  `ignore_changes=[user_data]`, the 32,768 B precondition), `cloud-init-inngest.yml:1204-1235`
  (the zot login item), `soleur-host-bootstrap.sh:563-638` (`soleur-wait-nic`, web host only).
- **Mechanism vs ADR corpus.** ADR-115 §Context 1 and §Alternatives ("Fix it in Terraform —
  Rejected") and `network.tf:9-13` both reject an inline `network {}` block because it "would
  force-replace the host". That reason does not transfer here (every inngest delivery IS a
  replace), so option (a) is not pre-rejected by the ADR. It is rejected below on a different,
  measured ground. ADR-115 §Alternatives also rejects "A netplan drop-in as the converge
  primitive" — for the **registry**, for reasons that are specific to a 5-minute cron re-applying
  netplan. The primitive chosen here is a different shape (one static networkd file that can
  only match a non-`eth0` virtio link, loaded by one reload, no periodic re-apply, no netplan
  apply), and the plan amends ADR-115 to record why.

### Measured facts that decide the option

1. **Option (a) does not close the race — the hcloud provider hot-attaches the inline block after
   the server is already booting.** `hetznercloud/terraform-provider-hcloud` **v1.63.0** (the
   version in `apps/web-platform/infra/.terraform.lock.hcl`), `internal/server/resource.go`
   `resourceServerCreate`: it calls `c.Server.Create(ctx, opts)` with no `opts.Networks`, waits
   for the create action and `NextActions` (the server is started), and only THEN loops
   `inlineAttachServerToNetwork(...)` (resource.go:475-484). The single exception is
   `onServerCreateWithoutPublicNet` (resource.go:436-440, 1447-1457): only when BOTH
   `ipv4_enabled` and `ipv6_enabled` are false is the server created with
   `StartAfterCreate=false` and powered on after the attach. `hcloud_server.inngest` needs public
   egress (apt, inngest CLI, Sentry/Better Stack; there is no NAT gateway,
   `inngest-host.tf:459-466`), and the provider schema has no `start_after_create` attribute
   (checked via `terraform providers schema -json` against v1.63.0). The inline block therefore
   shortens the gap by removing one resource-scheduling hop; it cannot order the attach before
   the guest's network stage.
2. **The "inline block force-replaces the host" claim is stale.** At v1.63.0 `network` is a
   non-`ForceNew` `TypeSet` and `resourceServerUpdate` handles `d.HasChange("network")` with an
   in-place `updateServerInlineNetworkAttachments` (resource.go:643-647). This is a comment fix in
   `network.tf` and ADR-115, not a behaviour change.
3. **A hot-attached private NIC does not become usable on this image without a reboot or an
   in-guest action, and a bounded wait alone cannot fix the race.** Evidence, three independent
   lines:
   - Production: #6400/#6122 — the registry host held its attach at the control plane and sat
     with no `10.0.1.30` for ~14 days until a soft reboot
     (`knowledge-base/project/learnings/2026-07-07-immutable-redeploy.md` §Sharp edge 2).
   - Production: 2026-09-22 — attach at 07:00:12Z, `zot-login-FAILED` at 07:00:46Z, the 180 s
     bounded pull failing at 07:01:49Z (Better Stack `SOLEUR_INNGEST_BOOT_STAGE` rows, queried
     this session); zot's own log saw no request from the host. The retry boot's `net-health` row
     at 07:14:58Z shows `nic=[10.0.1.40,]`, i.e. the good case.
   - Source: cloud-init's Hetzner datasource renders a private network as `type: dhcp` on the
     MAC-matched interface **only when it is in the metadata at render time**
     (`cloudinit/sources/DataSourceHetzner.py` `network_config`, added by canonical/cloud-init
     #6224, 2025-06-30). Hot-plug handling for Hetzner (#6445, 2025-09-11) runs through
     `cloud-init-hotplugd.service`, which is `After=cloud-init.target` — i.e. after
     `cloud-final.service`, which is where `runcmd` executes — and `tools/hook-hotplug` DROPS a
     udev event that arrives before `cloud-init-hotplugd.socket` is listening ("Not running
     hotplug, not ready yet"). So even on an image whose cloud-init has hotplug, the handler
     cannot run while runcmd is waiting for it: a wait inside runcmd deadlocks against the only
     automatic healer, then gives up.
   - Therefore: a bounded wait converts nothing on its own. The plan must pair the wait with an
     in-guest converge action.
4. **A reboot cannot be the fallback on this host.** runcmd is once-per-instance
   (`cloud-init-inngest.yml` comments at 86-90, 287-290, 431-440), so a rebooted host never
   re-runs the bootstrap pull and comes up with no scheduler — the same terminal state as today,
   plus a power-cycle. ADR-115's reboot grant is also registry-scoped by its own Status line.
5. **Telemetry check of the registry guard (90 days, hot + archive):** zero
   `SOLEUR_PRIVATE_NIC` rows with `converged_by != already`; five fresh registry boots
   (2026-08-16 .. 2026-09-22) all reported `nic_ok=true converged_by=already` at `uptime_s`
   48-74. So the race is intermittent (≈1 in 10 inngest boots observed), not systematic, and the
   registry guard's reboot arm has never fired in that window.
6. **user_data headroom:** `bash apps/web-platform/infra/inngest-userdata-budget.sh` →
   stored 14,964 B, cap 32,768 B, headroom 17,804 B (measured this session). A ~60-line helper
   costs well under 1.5 KB stored.
7. **L3 → L7 (network-outage checklist):** L3 firewall — Hetzner cloud firewalls filter only the
   public interface (`inngest-host.tf:606-614`); the inngest nftables table declares an `input`
   chain only (`inngest-host.tf:416-419`); identical rules served nine good boots and the retry,
   so a firewall cause is excluded by artifact, not assumption. L3 DNS/routing — the target is
   an IP literal (`10.0.1.30:5000`), no DNS; the missing element is the source host's own
   address/route on the private subnet (the NIC). L7 TLS — N/A (plain HTTP on the private net,
   ADR-096). L7 application — zot's shipped log shows no request from 10.0.1.40 in the window
   (supplied measurement), which is the "packet never reached the service" signal that points
   back to L3 on the source.

### Property List (Phase 0.6b)

- **P1** — On a fresh inngest boot, the bootstrap image pull runs only after the host's private
  address 10.0.1.40 is configured, whenever the network is attached at the control plane within
  the wait budget.
- **P2** — The NIC step never aborts the boot, never reboots the host, and never delays a boot
  whose NIC is already up by more than one probe.
- **P3** — Every fresh boot emits exactly one discriminating event saying which case occurred
  (already up / converged by the helper / never came up / could not measure), reachable without
  SSH.
- **P4** — The converge configuration can only ever apply to a non-`eth0` virtio link that no
  cloud-init-rendered file already claims; it never reconfigures `eth0` and never overrides the
  good case.
- **P5** — The expected address has exactly one definition (`local.inngest_private_ip`).

### Cut List (Phase 0.6b)

- Inline `network {}` block + state move (option a) → P1 → not bought: the provider attaches it
  post-boot (fact 1). Cut.
- Reboot fallback (issue's option 2 tail) → P1 → not bought: runcmd never re-runs (fact 4). Cut.
- Reusing the web host's `soleur-wait-nic` → P1/P3 → not reachable: it ships inside the
  bootstrap image, which is the thing the NIC is needed to pull. The inngest helper must live in
  user_data. Its contract (always exit 0, exactly one event, probe-fault arm, argument guard) is
  copied, not the file.
- New Better Stack/Sentry alarm for the new markers → P3 → already covered: a timeout is
  followed by the existing `oci-pull-ALL-LEGS-FAILED` marker and the scheduler-dark heartbeat
  path; the new event only has to be discoverable. No new alarm.
- A runtime-derived converge (IMDS MAC → a generated `/run` networkd file, gated on four live
  conditions) → P1 → bought more cheaply and more robustly by ONE static fallback file plus one
  reload (consult + CTO, see below). Cut; the four conditions survive only as event fields.
- Editing netplan (`/etc/netplan`) or running `netplan apply` → P1 → not needed, and it is the
  shape ADR-115 rejected for the registry (it can bounce the public interface). The static
  networkd file is persisted in `/etc/systemd/network/` instead (CTO R1), where it is inert
  whenever cloud-init renders the NIC itself.

### Relevant files

- `apps/web-platform/infra/cloud-init-inngest.yml` — runcmd zot login at :1220-1235; token staged
  at :531-534 (first runcmd item, so phone-home works before the new call); `soleur-boot-emit`
  write_files at :389-417; `inngest-boot-phone-home.sh` at :271-331; strip-sensitive comments.
- `apps/web-platform/infra/inngest-host.tf` — `local.inngest_private_ip` :53; templatefile var map
  :400-442; `local.inngest_rationale_strip` :278 (`/(?m)^[ \t]*#([ \t][^\n]*)?\n/` — deletes
  every line whose first non-blank characters are `#` + space/EOL; `#!/bin/sh` survives).
- Render sites that pass an explicit var map to `cloud-init-inngest.yml` (all must gain the new
  var or `templatefile` errors): exactly `inngest-host.tf`, `inngest-userdata-budget.sh:~186`
  and `inngest-boot-emitter.test.sh:227` (Kieran-verified). `.github/scripts/validate-infra-templates.sh`
  and `plugins/soleur/test/cloud-init-user-data-size.test.ts` derive their keys from the `.tf`
  and pick the new var up on their own. Re-enumerate at work time by anchoring on a key only the
  inngest map carries: `git grep -l 'web_host_private_ips *=' -- apps`. `zot_pull_token` is NOT a
  valid anchor, because the registry root and its tests carry it too.
- Harness precedent: `apps/web-platform/infra/nic-wait-gate.test.sh` (extracts a helper body,
  stubs PATH, asserts exactly-one-event and no `exit 1`/`reboot`).
- Structure guards that will see the new item: `cloud-init-inngest-bootstrap.test.sh` (Phase5
  zot-login ordering asserts ~:829-842, write_files asserts ~:1070), the mutation battery
  `cloud-init-inngest-zot-pull-mutation.test.sh`, and the size test.
- Test registration: `.github/workflows/infra-validation.yml` job steps (e.g. :1036, :1307);
  `apps/web-platform/infra/run-registered-suites.sh` derives from it;
  `scripts/lint-orphan-test-suites.sh` flags an unregistered `*.test.sh`.
- Consumers of inngest boot markers: `scripts/followthroughs/inngest-zot-boot-7462.sh` counts
  `oci-pull-ALL-LEGS-FAILED` / `inngest_ghcr_fallback`; `zot-soak-6122.sh` counts Sentry
  `stage:` events filtered on `host_name:soleur-inngest`. Neither parses a `private_nic_*` stage,
  so adding one cannot change their verdicts (verify with a grep at work time).

### Institutional learnings applied

- `2026-07-07-immutable-redeploy.md` §Sharp edge 2 — the attach can land after the network
  stage; unconfigured NIC reads as timeout + ping loss, not connection refused.
- `best-practices/2026-07-14-extracting-nonzero-returning-helper-into-command-sub-aborts-under-set-e.md` and
  the runcmd-is-one-`/bin/sh` note (`cloud-init-inngest.yml:1213-1219`) — the call site must be
  `… || true` and the helper must return 0 on every path.
- `best-practices/2026-07-14-cloud-init-templatefile-escaping-and-ci-deploy-payload-testing.md` —
  write the helper brace-free (no `${`), never write `%{` anywhere, render through terraform to
  test.
- `2026-07-19-my-own-mutation-battery-was-the-false-confidence.md` (the #6441 NIC gate) — mutate
  the loop bound, the probe flags (`grep -qwF` → `grep -qF`), the break condition and the
  corroboration predicate, not only the happy path.
- `best-practices/2026-07-01-blind-surface-needs-structured-probe-before-nth-fix.md` — a fresh
  cloud-init boot is a blind surface; the event must discriminate all competing hypotheses in
  one row.
- Learnings that do NOT transfer: "bake the helper into the image" (the image is what the NIC is
  needed to pull).

### Functional overlap

`soleur:engineering:discovery:functional-discovery` found only generic Hetzner/cloud-init
authoring skills (majestic-marketplace); none address this race. Nothing installed.

### Consult and domain-leader adjustments (applied)

The strong-model consult (Phase 4.5) and the CTO assessment (Phase 2.5) both changed the design,
and the plan below is the adjusted version:

- **Static fallback file, not a runtime-derived one.** The first draft wrote a `/run` networkd file
  built from the IMDS `mac_address`, gated on four runtime conditions (IP absent, IMDS lists it,
  MAC link present, `SETUP=unmanaged`). Any lag in one of them silently became a timeout. The
  adopted shape bakes ONE static file through `write_files` and reloads networkd once. networkd
  then configures a matching link the moment udev reports it, including an attach that lands after
  the wait window. The four values survive as event fields, not as a gate. This also removes every
  IMDS-derived byte from a root-written config file (CTO R4).
- **Persist it in `/etc/systemd/network/`, not `/run`** (CTO R1). A reboot does not re-run runcmd,
  and cloud-init's own re-render on reboot is not guaranteed on every cloud-init version. The file
  is inert whenever cloud-init renders its own `10-netplan-*` file for the NIC, because networkd
  uses the first match in lexical order.
- **Keep the private link from stealing routing or DNS** (CTO R2): `UseDNS=no`, `UseDomains=no`,
  `UseHostname=no`, and `RouteMetric=1024` so any gateway the private DHCP offers ranks below
  eth0's. `UseGateway=no` was NOT adopted: if Hetzner's private DHCP supplied the 10.0.0.0/16 path
  only through the router option, it would cut the very route the zot pull needs. Not measured, so
  the plan takes the choice that is safe either way.
- **Report the renderer** (CTO R3): if `networkctl` is missing, the event's `by=`/`links=` fields
  read `nonetworkctl`, so a boot where the fallback could not have worked says so.
- **Plan-review cuts (DHH, code-simplicity, Kieran):** event arms reduced from four to three
  (`private_nic_ok` carries `waited_s=` and `by=`). The metadata-service read and its
  encryption exception are dropped, because `links=none` vs `links=<if>:<state>` already
  separates "the attach never reached the guest" from "the fallback did not take the link". The
  argument guard is reduced to the empty-argument check. `by=` now appears on every ok boot, so
  the first ordinary replace boot verifies P4 (`by=10-netplan-*`) in production. The ADR amendment is
  kept short and links here. The C4 edit uses the `private_nic_*` family name instead of a stage
  list that would go stale.
- **Rehearsal and the once-only pull are named, not solved here** (consult 2, CTO "missing"):
  both are tracked in the follow-up issue this plan files (see Deferrals).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #8539 / arguments) | Reality | Plan response |
| --- | --- | --- |
| Option 1: an inline `network { network_id, ip }` block "so the NIC exists at first boot" | The pinned provider (v1.63.0) creates and starts the server, then attaches the inline network. Only a server with no public IPv4 and no IPv6 is created stopped. This host needs public egress. | Rejected. It closes nothing and ripples through the replace and shape gates plus the `-target` lists. |
| "ADR-114 recorded that the web host could not do this" | ADR-115 §Context 1 and `network.tf:9-13` say the inline block "would force-replace the host". That is false at v1.63.0, where `network` updates in place. For inngest the replace is irrelevant anyway. | Correct the comment and the ADR. The rejection rests on fact 1, not on the replace. |
| Option 2: "a bounded NIC wait … mirroring `soleur-wait-nic`" | A wait alone cannot converge anything. Hotplug runs after runcmd, and a late attach stayed unconfigured for 14 days on #6400. | Keep the wait, but pair it with a static networkd fallback that actually configures the link. |
| Option 2: "fail over to a reboot (the registry's guard pattern)" | runcmd is once-per-instance, so the pull would never re-run. | Rejected. No reboot. |
| "`hcloud_server_network` can only attach after the server exists, so Terraform cannot order it before boot" | True, and true of the inline block too (fact 1). | Carried forward as the core premise. |
| ADR-114 §4 (#6441): a NIC-less connector "begins serving the instant the attach lands … a converging state" | Contradicted by #6400 (14 days) and by the hotplug unit ordering. It is only true where something configures the late link. | Out of scope for the web host. Recorded on #6438 as a comment, and the static fallback file named there as the candidate remedy. |

## Hypotheses

Network-outage checklist order (L3 → L7). Every layer is verified from an artifact, not assumed.

1. **L3 firewall allow-list — excluded.** Hetzner cloud firewalls filter only the public
   interface (`inngest-host.tf:606-614`). The inngest nftables table has an `input` chain only, so
   egress to 10.0.1.30 is unrestricted (`inngest-host.tf:416-419`). The same rules served nine good
   boots and the 07:14Z retry. [verified: config + boot history]
2. **L3 DNS / routing — the source host had no private address/route.** No DNS is involved (IP
   literal). The failed boot's own markers show the 180 s pull timing out against `10.0.1.30:5000`,
   and zot saw no request. That is the "packet never left / never arrived" signature of a
   missing NIC configuration, not of a routing fault at the registry. [verified: Better Stack
   markers 07:00:46Z / 07:01:49Z; zot log supplied]
3. **L7 TLS — not applicable.** Plain HTTP on the private net (ADR-096 insecure-registry entry).
4. **L7 application (zot) — excluded.** zot was healthy (`ping_rc=0`), served 10.0.1.10/.11
   in the same window, and served the retry boot two seconds after its login. [verified: supplied
   zot log + 07:14:27Z `inngest_zot` marker]
5. **Leading hypothesis, NOT directly observed:** the private link was not configured in the
   guest. The failed boot shipped no interface list (its `net-health` diag runs after the pull and
   was never reached), so the guest-side state is inferred, not measured. Two sub-hypotheses fit
   and cannot be separated from the existing data: **H2** — the attach landed after cloud-init's
   network render (27 s after create); **H1** — a transient metadata read at render time returned
   no private network. The fix does not need to separate them. The static fallback matches the
   link whatever the render saw, so it covers both, and the new event records whether a private
   link reached the guest and each such link's networkd state so the next occurrence is discriminated from the host itself. A
   third shape ("the NIC is configured but the path to zot is broken") shows up as
   `private_nic_ok` followed by `zot-login-FAILED` on the same boot. That pair is
   distinguishable, and this plan does not claim to fix it.

## Options Evaluated

| Option | Closes the race? | Cost | Verdict |
| --- | --- | --- | --- |
| **(a)** Inline `network {}` on `hcloud_server.inngest` + drop `hcloud_server_network.inngest` | **No.** It is still a post-boot hot attach at v1.63.0 (public_net enabled). | Needs a `removed {}` block, because no `moved` exists across a resource type and a nested block. Also edits the `-target` lists at `apply-web-platform-infra.yml:1789,2094`, both gates (`tests/scripts/lib/inngest-host-{replace,shape}-gate.sh`), their tests, and `terraform-target-parity.test.ts:1445`. The provider docs also warn against mixing the two attach styles. | Rejected |
| **(b)** Bounded wait only, before the zot login | **No.** It converts nothing (fact 3). It only moves the failure 60-150 s later. | Low | Rejected as sufficient; kept as the reporting half |
| (b′) Wait + reboot fallback | **No.** A reboot skips runcmd, so there is no scheduler (fact 4). | Medium, plus self-reboot authority | Rejected |
| **(c) Static networkd fallback `.network` + one reload + bounded wait with one discriminating event** | **Yes**, for any attach that lands at the control plane before the wait expires. It also heals a later attach for the rest of the instance's life. | ~1 KB stored user_data; one new template var | **Chosen** |
| (d) Move the bootstrap pull into a retrying systemd unit | Makes a missed window recoverable without a replace. | Large: restructures the boot sequence, which has LUKS/cutover coupling | Deferred (follow-up issue) |
| (e) Create the server with no public net, attach, then add a primary IP | Would make the provider attach pre-boot | Changes ADR-100's egress model and firewall assumptions; a primary IP cannot be added to a stopped create through this provider | Rejected |

## Implementation Phases

### Phase 1 — Single-source the expected address into the template

1. `apps/web-platform/infra/inngest-host.tf`: add `inngest_private_ip = local.inngest_private_ip`
   to the `templatefile(...)` var map (next to `web_host_private_ips`, ~:424).
2. Add the same key, as the byte-identical literal `"10.0.1.40"`, to every other render site of
   `cloud-init-inngest.yml`: `inngest-userdata-budget.sh` (~:186, plus its bounds comment, "exact,
   not a bound") and `inngest-boot-emitter.test.sh:227`. Re-run
   `git grep -l 'web_host_private_ips *=' -- apps` first; that list is authoritative.
3. Replace the hardcoded `10.0.1.40` in the existing `net-health` diag
   (`cloud-init-inngest.yml:1673`, the only CODE-line copy; :1670 is a comment) with
   `${inngest_private_ip}`. That line already carries `%%{http_code}`; leave that escape
   untouched. Guard 1 row 5 and AC8 cover this swap. The template then carries one
   definition, not two.

### Phase 2 — The fallback networkd file (write_files)

Add one `write_files` entry to `cloud-init-inngest.yml`:

- **path** `/etc/systemd/network/99-soleur-private-fallback.network`, `root:root`, `0644`
- **content** (no `$`, no `%{`, no `#`-prefixed lines, so the strip regex and templatefile both
  leave it byte-identical):

  ```ini
  [Match]
  Driver=virtio_net
  Name=!eth0

  [Network]
  DHCP=ipv4
  LinkLocalAddressing=no
  IPv6AcceptRA=no

  [DHCPv4]
  UseDNS=no
  UseDomains=no
  UseHostname=no
  RouteMetric=1024
  ```

- Why each line: `Driver=virtio_net` excludes docker's `veth*` and bridges. `Name=!eth0` excludes the
  public NIC even on a boot where netplan's eth0 file were missing. The `99-` prefix means any
  cloud-init-rendered `10-netplan-*` file for the private NIC wins, so the good case is untouched.
  DHCP is what cloud-init's Hetzner datasource itself renders for a private network, so the
  address, routes and MTU come from the same source. The `[DHCPv4]` block is the CTO R2 guard.
- The rationale lives in YAML comments ABOVE the entry (stripped for free), never inside
  `content:`.
- CLI/semantics verified at plan time (`man systemd.network`, `man networkctl`, systemd man
  pages, 2026-09-22): `Name=` and `Driver=` take shell-style globs and "If the list is prefixed
  with a "!", the test is inverted" (both "Added in version 211"). `Driver=` reads udev
  `ID_NET_DRIVER`. `networkctl reload` ("Added in version 244"): "If a new, modified, or removed
  .network file is found, then all interfaces that matched the file are reconfigured". `[DHCPv4]
  RouteMetric=` "Defaults to 1024" (so the line pins networkd's own default against drift;
  netplan gives eth0's DHCP routes metric 100). `UseHostname=` defaults to true, hence the
  explicit `no`. Ubuntu 24.04 ships systemd 255, above every "Added in" version cited.
- **Good-case safety verified at source (systemd v255):** `manager_reload`
  (`src/network/networkd-manager.c:1080-1109`) calls `network_reload`, which keeps the SAME
  `Network` object for every file whose `stats_by_path` is unchanged
  (`networkd-network.c:612-630`). It then calls `link_reconfigure(link, force=false)`, which
  returns early when `link->network == network && !force` (`networkd-link.c:1238-1239`). So
  eth0 and a private NIC already configured by netplan's `10-netplan-*` are NOT touched by the
  reload. Only a link whose best match changes is configured, which means an unmanaged link that
  now matches the fallback.
- Verify during work whether the Hetzner `ubuntu-24.04` image ships `hc-utils`, whose udev hooks
  configure hot-plugged NICs. Check the image's package manifest or cloud-init docs; no host access
  is needed. If it does, the two production observations in fact 3 say its hook did not heal these
  boots. Either way, `by=none` in the new event is what would reveal it (Kieran P1-6).
- Verify during work: `Name=!eth0` negation and `Driver=` matching on systemd 255
  (`man systemd.network`, Ubuntu 24.04 `systemd` 255.4), and that Hetzner's hot-plugged private
  NIC reports `ID_NET_DRIVER=virtio_net`. The registry/web telemetry shows it named `enp7s0`
  (`SOLEUR_PRIVATE_NIC … enp7s0:10.0.1.30/32`), so it is a predictable-name virtio link. Record
  the man-page line in the PR body (CLI-verification gate).

### Phase 3 — The wait helper and the two runcmd calls

1. New `write_files` entry `/usr/local/bin/soleur-inngest-nic-wait` (`0755`), POSIX `sh`, written
   **brace-free** (no `${…}` anywhere, the `inngest-boot-phone-home.sh` precedent at :277-280), no
   `%{`, and no code line that begins with `# `. Contract, copied from `soleur-wait-nic`:
   - usage `soleur-inngest-nic-wait <expected-ip>`. It **always exits 0**, never calls
     `reboot`/`poweroff`/`shutdown`/`systemctl reboot`, and never writes network config (the
     static file is the only converge primitive).
   - **(0) argument guard**: an empty argument takes the probe-fault arm (`grep -qwF -- ""` matches
     every line, so an empty argument would otherwise report `ok` on zero evidence). No format
     check: the argument is a Terraform-rendered constant pinned by Guard 1 row 5.
   - **(1) probe resolution**: `ip` and `grep`. Either missing → probe_fault. `networkctl` is used
     only for reporting; if it is missing, the report fields read `nonetworkctl` (CTO R3: the
     event says the fallback cannot have been working).
   - **(2) poll**: `ip -4 -o addr show | grep -qwF -- "$EXPECTED"` at 2 s intervals, a POSIX
     counter (not `seq`), cap **75 iterations (150 s)**. Keep the `probe_ran` / exit-capture shape
     of `soleur-wait-nic` (a failing `ip` is not "absent").
   - **(3) classify, exactly one event**, both channels. The Better Stack marker goes through
     `inngest-boot-phone-home.sh <stage> "<fields>"` and Sentry through `soleur-boot-emit <stage>
     <level> "<detail>"`. `soleur-boot-emit:397` keeps only `A-Za-z0-9=.:_-` and deletes spaces,
     then cuts at 120 chars. So the helper builds ONE detail string from that charset, with
     fields joined by `.`, `boot=` FIRST so a cut can never drop the join key, and multiple links
     joined by `_`. It passes that same string to both channels. Guard 2 asserts the string is
     ≤120 chars and charset-clean in every scenario (Kieran P1-5). Three arms:
     - `private_nic_ok`: the address is present. `waited_s=` (0 means present at the first
       probe) and `by=` from the `Network File:` line of `networkctl status <if>`, where `<if>` is
       the interface that holds the address. `by=` is the Network File's BASENAME without
       `.network` (e.g. `10-netplan-enp7s0`, `99-soleur-private-fallback`), or `none` when
       networkd reports no file (something other than networkd configured it, e.g. an `hc-utils`
       udev hook), or `nonetworkctl`. It is NOT a two-way cloudinit/fallback label, because that
       would guess at the configurer (Kieran P1-6). Level is **warning** when `by=` is the
       fallback's basename, whatever `waited_s` is. The early reload usually heals a late link
       long before the wait's first probe, so `waited_s=0 by=99-soleur-private-fallback` is the
       COMMON shape of a healed race, and it must not be silent (ADR-115; Kieran P1-4). Otherwise
       the level is info. `by=` on EVERY ok boot is also the production check of P4: an ordinary
       boot must read a `10-netplan-*` basename.
     - `private_nic_timeout` (warning): never present. `links=`: each non-eth0 virtio link name,
       `:`, and its networkd SETUP state (e.g. `enp7s0:unmanaged`), or `links=none` when no such
       link exists in the guest. That field alone separates "the attach never reached the guest"
       (`none`) from "the link is there and the fallback did not take it" (`<if>:unmanaged`, or
       `:failed`, or `:configuring`). No metadata-service read is needed for that, so none is
       made (plan-review cut).
     - `private_nic_probe_fault` (warning): no measurement possible.
     - Every arm carries `waited_s=` and `boot=` (first 8 chars of
       `/proc/sys/kernel/random/boot_id`), a join key toward #6711's concern.
2. `runcmd`: add `- networkctl reload || true` **immediately after the first runcmd item** (the
   Better Stack token staging at :531-534). The reload is what makes networkd see a file that
   `write_files` created after networkd started. It must run as early as possible so a link that
   already appeared is configured before the zot login is reached.
3. `runcmd`: add `- /usr/local/bin/soleur-inngest-nic-wait ${inngest_private_ip} || true`
   **as the item immediately preceding the zot-login item** (:1220). The `|| true` matters:
   runcmd is ONE `/bin/sh`.
4. Nothing downstream changes. If the wait times out, the zot login and pull proceed as today and
   fail loudly (`zot-login-FAILED` → `oci-pull-ALL-LEGS-FAILED` → FATAL). The new event says why.

### Phase 4 — Tests (write the Guard Contract matrices first, then the code)

1. **New** `apps/web-platform/infra/inngest-nic-wait.test.sh`: render `cloud-init-inngest.yml`
   through `terraform console` with a stub var map **and `local.inngest_rationale_strip`
   applied**, exactly as `inngest-host.tf` does. It then extracts the helper and the `.network`
   file from the RENDERED `write_files` (python3 `yaml.safe_load`), so the test sees the stripped
   bytes Hetzner receives. Next it runs the helper under a stub `PATH` (`ip`, `networkctl`,
   `systemctl`, `curl`, `sleep`, `soleur-boot-emit`, `inngest-boot-phone-home.sh`, each logging
   its argv) with a test-root seam for `/proc` reads. Finally it executes the Test Scenarios below
   plus Guard 2's mutation rows against a copy.
2. **Extend** `cloud-init-inngest-bootstrap.test.sh`: Guard 1's shape/placement assertions
   (anchored on the call construct `^[[:space:]]*-[[:space:]]+/usr/local/bin/soleur-inngest-nic-wait `,
   not the bare token), and the write_files mode/owner asserts for both new entries.
3. **Extend** the mutation battery `cloud-init-inngest-zot-pull-mutation.test.sh` with Guard 1's
   rows (it already has the sandbox/landed-diff/harness-abort discipline).
4. **Register** the new suite in `.github/workflows/infra-validation.yml` next to
   `nic-wait-gate.test.sh` (:1036). `run-registered-suites.sh` derives from it, and
   `scripts/lint-orphan-test-suites.sh` must stay green.
5. Run `shellcheck -s sh` on the extracted helper inside the new suite (CTO test list).
6. Re-run `bash apps/web-platform/infra/inngest-userdata-budget.sh` and record the new stored
   size. Raise `INNGEST_GZIP_BUDGET` in the size test only if the model crosses it (current model
   ~10.5 KB against an 18,000 budget; not expected).

### Phase 5 — Architecture record, C4, runbook, comment fix

1. **ADR-115 amendment** `#### Amendment (2026-09-22, #8539): the inngest host converges a
   late-attached NIC with a static networkd fallback, not a reboot` (add `8539` to
   `amended_by`). Keep it short (about 15-20 lines) and link this plan for the evidence. It
   states the chosen primitive, why it differs from the rejected "netplan drop-in" row (no
   periodic re-apply, no `netplan apply`, eth0 excluded twice), and the corrected provider fact.
   Add three rows to §Alternatives: inline `network {}`, wait-only, and
   reboot-for-inngest. Status of the converge claim: **adopting**. It is proven by the first boot
   that emits `private_nic_ok by=99-soleur-private-fallback`, and until then it is a mechanism-level argument
   (see Risks). Keep Status's "registry only" line for the REBOOT primitive, and state that this
   primitive is separate.
2. **`network.tf:9-13`** comment: correct "an inline `network {}` block … WOULD force-replace the
   host" to what v1.63.0 does (in-place attach, and still a post-boot hot attach whenever public
   net is enabled). Comment-only; no plan diff.
3. **C4**: `knowledge-base/engineering/architecture/diagrams/model.c4:729` (`inngest -> sentry`)
   enumerates the boot stages it carries (`inngest_zot / inngest_ghcr_fallback`). Add the
   private-NIC boot outcome as the family name `private_nic_*`, not a list of arms. Check the Better Stack phone-home edge's stage list the same way. No new
   element or relationship (see Architecture Decision).
4. **Runbook** `knowledge-base/engineering/operations/runbooks/inngest-server.md`: a short "Reading
   the private-NIC boot event" subsection under the host-replace material. It covers the four
   stages, the SSH-free Better Stack query, and what each arm means for the next step (`timeout`
   with `links=none` means the attach never reached the guest. `timeout` with
   `links=enp7s0:unmanaged` means the fallback did not match. `ok by=99-soleur-private-fallback` (at any `waited_s`) means the race
   happened and was healed).

### Phase 6 — Delivery (post-merge, outside this pipeline)

The template change force-replaces the sole scheduler, so it is delivered by the
`inngest-host-replace` dispatch after merge, then the human-approved `op=resume`
(`INNGEST_CUTOVER_FLIP=done`). Both are orchestrator-owned and not part of `soleur:work`. The merge
apply's `-target` list prunes `hcloud_server.inngest`, so merging alone changes nothing on the host.
The `inngest-userdata-budget.sh` CI gate is what weighs the payload on the merge path (the
`lifecycle.precondition` only fires on the replace plan).

## Files to Edit

- `apps/web-platform/infra/cloud-init-inngest.yml`: two write_files entries, two runcmd items,
  `net-health` literal to var.
- `apps/web-platform/infra/inngest-host.tf`: one var-map key.
- `apps/web-platform/infra/network.tf`: comment only (:9-13).
- `apps/web-platform/infra/inngest-userdata-budget.sh`: stub var + bounds comment.
- `apps/web-platform/infra/inngest-boot-emitter.test.sh`: render var map (:227).
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`: Guard 1 asserts.
- `apps/web-platform/infra/cloud-init-inngest-zot-pull-mutation.test.sh`: Guard 1 mutation rows.
- `plugins/soleur/test/cloud-init-user-data-size.test.ts`: var map / budget only if needed.
- `.github/workflows/infra-validation.yml`: register the new suite.
- `knowledge-base/engineering/architecture/decisions/ADR-115-dedicated-host-private-nic-boot-convergence.md`:
  amendment + alternatives rows + frontmatter.
- `knowledge-base/engineering/architecture/diagrams/model.c4`: edge description(s).
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`: boot-event subsection.

## Files to Create

- `apps/web-platform/infra/inngest-nic-wait.test.sh`

## Open Code-Review Overlap

1 open scope-out touches these files: #7942 (two `*.mutation.sh` batteries in `plugins/soleur/test/`
run in no gate). It matches on `.github/workflows/infra-validation.yml`.

- **#7942 — Acknowledge.** It is about registering two plugin-test batteries. This plan registers a
  different infra suite in the same workflow. Folding it in would widen scope with no shared code.

## Deferrals (tracked)

- **Follow-up issue #8562 (filed with this plan):** "inngest boot: a missed first-boot pull is
  recoverable only by a host replace; move the bootstrap pull into a retrying unit, and add a
  forced-race rehearsal". It carries option (d), consult item 2, and the CTO "pull still runs
  once" finding. Re-evaluate on the next inngest boot that emits `private_nic_timeout`, or before
  any change that lengthens the replace window. Milestone per `knowledge-base/product/roadmap.md`.
- **#6438 comment (not a close):** the inngest first-boot slice of its item 2 lands here. The
  static-fallback-file shape is a candidate for the web hosts and registry. The ADR-114 §4
  "converging state" premise is contradicted by #6400 and by hotplug ordering.

## User-Brand Impact

**If this lands broken, the user experiences:** every scheduled and background job stops (crons,
reminders, agent follow-ups). That can happen if the fallback file captures the wrong link or the
wait mis-classifies, so that the next inngest host replace boots with no scheduler. It shows up as
missed reminders and stalled automations until a second replace plus `op=resume`, the same outage
shape as 2026-09-22 (~59 min). A wrong route on the private link could also make the host's
private-net traffic (zot, web-host SDK callbacks) flap.

**If this leaks, the user's data / workflow / money is exposed via:** no new exposure vector. The
helper reads only the host's own addresses and the link-local metadata endpoint, writes no
secret, and adds no credential to user_data. Event fields are link names, IP-free states and
counters. The only address in an event is the expected private IP.

**Brand-survival threshold:** aggregate pattern

Outage-shaped for every user at once, not a single user's breach. The same ADR-115 surface carries
`single-user incident` for its registry reboot primitive; this change adds no reboot and no
credential, so the lower threshold applies. No per-PR CPO sign-off.

## Observability

```yaml
liveness_signal:
  what: exactly one SOLEUR_INNGEST_BOOT_STAGE marker per fresh inngest boot among private_nic_ok / private_nic_timeout / private_nic_probe_fault, plus the matching Sentry stage event (host_name soleur-inngest)
  cadence: once per fresh boot (per host replace), emitted before the zot login
  alert_target: none new. A timeout is followed on the same boot by the existing oci-pull-ALL-LEGS-FAILED marker and the scheduler-dark heartbeat path (Better Stack inngest heartbeat), which already page. private_nic_ok by=99-soleur-private-fallback is a warning-level Sentry event, i.e. the advisory
  configured_in: apps/web-platform/infra/cloud-init-inngest.yml (helper + call site); emit helpers inngest-boot-phone-home.sh and soleur-boot-emit in the same file
error_reporting:
  destination: Better Stack Logs source 2457081 (phone-home POST) and Sentry (store API via soleur-boot-emit), both over public egress, which is independent of the private NIC under test
  fail_loud: yes. The helper never swallows the outcome. Every arm, including probe-fault, emits, and a Sentry non-delivery is reported by soleur-boot-emit's own sentry-emit-FAILED phone-home
failure_modes:
  - mode: attach never landed at the control plane within 150 s
    detection: private_nic_timeout links=none
    alert_route: existing oci-pull-ALL-LEGS-FAILED + inngest heartbeat
  - mode: attach landed, fallback file did not match or networkd did not act
    detection: private_nic_timeout links=<if>:unmanaged (or :failed / :configuring, or links=nonetworkctl)
    alert_route: existing oci-pull-ALL-LEGS-FAILED + inngest heartbeat; runbook row names the next step
  - mode: race happened and the fallback healed it (silent self-heal risk)
    detection: private_nic_ok by=99-soleur-private-fallback at warning level in Sentry (usually waited_s=0, because the early reload heals first)
    alert_route: Sentry warning (advisory, no page), counted by the runbook query
  - mode: probe missing (ip/grep) or bad argument
    detection: private_nic_probe_fault
    alert_route: Sentry warning; followed by the pull outcome markers
  - mode: helper crashed or never ran
    detection: absence of any private_nic_* marker on a boot that shows zot-login-* markers (both come from the same phone-home)
    alert_route: runbook query (absence is read against the zot-login marker of the same boot)
logs:
  where: Better Stack source 2457081 (SOLEUR_INNGEST_BOOT_STAGE rows) and Sentry (stage tag); on-box /var/log/cloud-init-output.log is a post-mortem breadcrumb only
  retention: Better Stack hot window plus s3 archive (queried by betterstack-query.sh); Sentry project retention
discoverability_test:
  command: bash scripts/betterstack-query.sh --since 72h --grep private_nic_ --limit 5
  expected_output: "private_nic_"
  credentials_required: "Better Stack ClickHouse read connection (BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD in Doppler soleur/prd_terraform) — a boot marker from a deny-all, no-SSH host exists only in the Logs warehouse; no unauthenticated endpoint exposes it"
```

The affected surface is a blind execution surface: a fresh cloud-init boot with no SSH. So the
detection above is emitted **from the surface itself**. The field set is built so one event
separates the competing hypotheses: attach-not-landed, fallback-did-not-match, networkd-absent,
healed, and could-not-measure (§2.9.2).

## Infrastructure (IaC)

### Terraform changes

- `inngest-host.tf`: one templatefile var (`inngest_private_ip = local.inngest_private_ip`). No new
  resource, provider, or sensitive variable. hcloud provider stays at 1.63.0.
- `network.tf`: comment only.

### Apply path

(c) replace. The user_data change force-replaces `hcloud_server.inngest` (ADR-100: no
`ignore_changes=[user_data]`), delivered post-merge through the gated `inngest-host-replace`
dispatch and `op=resume`. Blast radius: the existing cron-outage window of a host replace. The
Redis AOF volume survives as a separate resource. The merge apply does not touch the host.

### Distinctness / drift safeguards

- The expected IP has one definition (`local.inngest_private_ip`). The Guard 1 row pins that the
  call site uses the template var, not a literal.
- The `lifecycle.precondition` (32,768 B) and the `inngest-userdata-budget.sh` CI gate both weigh
  the new payload.
- The fallback file is inert when cloud-init renders the NIC itself (lexical precedence). It is
  therefore not a second source of truth for the good case.

### Vendor-tier reality check

No new vendor objects. The Hetzner private-network DHCP behavior is the only vendor dependency. It
is the same DHCP cloud-init already uses for this NIC.

## Encryption Posture

```yaml
at_rest:
  - store: /etc/systemd/network/99-soleur-private-fallback.network (inngest root disk, new)
    mechanism: plaintext-exception — a static, non-secret network match rule identical on every host; no key, token, address or identifier in it
    evidence: the Phase 2 content block; inngest-nic-wait.test.sh asserts the rendered content byte-for-byte
    defends_against: nothing (non-sensitive by construction)
    does_not_defend: a root-disk reader learns that the host DHCPs a virtio link (public knowledge from this repository)
    disclosed_as: this plan and the ADR-115 amendment
    live_verification: unavailable — a host-local file; its effect is reported by the private_nic_ok by=99-soleur-private-fallback event
in_transit:
  - connection: inngest host -> zot 10.0.1.30:5000 (unchanged; plain HTTP on the private net, ADR-096)
    tls: none (pre-existing, unchanged by this plan)
    cert_verification: off
    does_not_defend: an on-path attacker inside the private network. Image integrity is carried by the pinned sha256 digest, not the transport
    disclosed_as: ADR-096 insecure-registry allowlist entry; model.c4 zot edges
exception:
  - store: /etc/systemd/network/99-soleur-private-fallback.network
    justification: a static match rule with no secret or identifier; encrypting it buys nothing
    tracking_issue: "#6438"
    reevaluate_when: the file ever gains a runtime-derived value (MAC, address, token)
    expires_on: 2027-09-22
  - connection: inngest host -> zot (pre-existing)
    justification: pre-existing ADR-096 posture, unchanged; digest-pinned pulls
    tracking_issue: "#6122"
    reevaluate_when: zot gains TLS on the private net
    expires_on: 2027-09-22
```

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-115** (no new ADR; the ordinal question does not arise). The amendment extends the
ADR's decision to the inngest host with a different primitive: a static networkd fallback plus a
reporting wait, and explicitly **not** the reboot primitive. It also records the corrected
provider fact (inline `network {}` is a post-boot attach with public net, and updates in place)
and the hotplug ordering fact, and adds the three alternatives rows. Status line: the reboot grant
stays registry-only.

### C4 views

Read all three model files before editing (`model.c4`, `views.c4`, `spec.c4`; 824/104/54 lines).
The enumeration checked:

- external actors: none new (no human sends or receives data on this path);
- external systems: Hetzner (the metadata read and the private network) and Sentry / Better Stack
  (the event sinks) are already modelled;
- containers/stores: the inngest node and zot registry are already modelled; the fallback file is
  host configuration, not a store;
- access relationships: unchanged.

The owed edits are **description-level**: `model.c4:729` `inngest -> sentry` enumerates the boot
stages it carries and gains the four `private_nic_*` stages, and the phone-home edge to Better
Stack gets the same check. Run `apps/web-platform/test/c4-code-syntax.test.ts`,
`apps/web-platform/test/c4-render.test.ts`, and `bash plugins/soleur/test/c4-count-parity.test.sh`
(none of the edited descriptions carry a count, and the parity run proves it).

### Sequencing

Authored now. The converge claim is marked **adopting** until the first raced boot reports
`private_nic_ok by=99-soleur-private-fallback`.

## Guard Contract

### Guard 1 — The NIC fallback is present, reloaded, and gates the zot login

**Property.** Every rendered inngest user_data has three things. First, exactly one fallback
`.network` file whose match excludes eth0 and non-virtio links. Second, a `networkctl reload` that
runs before the NIC wait. Third, exactly one NIC-wait call, carrying the templated
`${inngest_private_ip}`, placed immediately before the zot login, which is the first private-net
use in runcmd.

**Assembly.** The chokepoint is the **rendered, stripped** user_data (`templatefile` +
`local.inngest_rationale_strip`). Every member reaches the host only through it. It has three
injection sites, all checked: (1) the `write_files` list (file path, mode, content); (2) the
`runcmd` item sequence, which cloud-init concatenates into one `/bin/sh`, so order is textual
order; (3) the var map in `inngest-host.tf` that binds `inngest_private_ip` to
`local.inngest_private_ip`. The "first private-net use" is derived by scanning runcmd items
for private-net ACTIONS only: `docker (login|pull)`, or `curl`/`nc`/`ping` against a `10.0.1.`
address other than the host's own (`10.0.1.40`), excluding the NIC-wait call line itself.
Config WRITES that merely name the endpoint (`ZOT_EP='…'` at :1141 writing `daemon.json`, the
creds bake at :1202) are not uses. Without these exclusions the unchanged file fails, which is
a plan-review P0 (Kieran P0-2, DHH #1). Those two writes are must-PASS rows.
**Which copy each row reads (Kieran P1-3):** the order, presence and derived-set rows (1-4, 6-9)
read the RENDERED + stripped user_data. Rows 5 (literal vs `${inngest_private_ip}`) and 10 (a
comment naming the token) are properties of the SOURCE file, which a render erases, so they read
`cloud-init-inngest.yml` raw, the way `cloud-init-inngest-bootstrap.test.sh` already does via
`INNGEST_CI_YML`. It is not assumed to be the zot login, so a future item
that touches the private net earlier also reds.

**Mutation matrix** (each must drive the guard RED):

| # | Mutation | Row type |
| --- | --- | --- |
| 1 | Move the NIC-wait call to after the zot-login item | order |
| 2 | Move `networkctl reload` to after the NIC-wait call | order (REORDER, not delete) |
| 3 | Delete the `networkctl reload` item | presence |
| 4 | Keep the compliant call and add a second NIC-wait call later in runcmd | second member |
| 5 | Replace `${inngest_private_ip}` at the call site with the literal `10.0.1.40` | single-source |
| 6 | Change `Driver=virtio_net` to `Type=ether`, or drop the `!` from `Name=!eth0` | match scope |
| 7 | Rename the file to `05-soleur-private-fallback.network` (sorts before netplan) | precedence |
| 8 | Insert a new runcmd item that curls `10.0.1.30` before the NIC-wait call | derived set |
| 9 | Render an empty runcmd (guard's own dispatch) | vacuity: "0 items checked" must fail |
| 10 | Add a YAML comment line naming `soleur-inngest-nic-wait` before the zot login and move the real call after it | token-vs-construct |

**Harness rows.** Suite edit that must RED: make the order comparison compare a line number to
itself. The battery's baseline check must catch that the guard no longer reds on row 1. Must-PASS
inputs that are not the canonical file: (i) the canonical file with two unrelated runcmd items
reordered ahead of the call and blank lines inserted; (ii) the fallback content with its
`[DHCPv4]` keys reordered; (iii) the unchanged config writes that name the endpoint before the call
(`ZOT_EP='…'` at :1141 and the creds bake at :1202). None of them is a private-net ACTION. All
three must stay green.

**Anchor.** No stored hash or count is compared. The guard derives everything from the rendered
template on each run, so nothing outside the commit needs to move.

### Guard 2 — The wait helper is fail-open, single-event, and exact

**Property.** For every probe and link state, the helper exits 0. It never calls
reboot/poweroff/shutdown and never writes network config. It emits exactly one `private_nic_*`
event on each channel, and emits `ready`/`late` only when the exact expected address (word-bounded)
is present.

**Assembly.** The chokepoint is the helper body **as extracted from the rendered user_data**, not
the source YAML. It runs under a stub `PATH` covering every external it calls (`ip`, `grep`
(real), `networkctl`, `systemctl`, `curl`, `sleep`, `soleur-boot-emit`,
`inngest-boot-phone-home.sh`). Every stub logs its argv, so "never calls X" is checked against the
full call log, not a single binary.

**Mutation matrix:**

| # | Mutation | Must RED on |
| --- | --- | --- |
| 1 | Timeout arm `exit 0` → `exit 1` | exit-code-0-everywhere scenario |
| 2 | `grep -qwF` → `grep -qF` | expected `10.0.1.4` vs host `10.0.1.40` must not be ready |
| 3 | Poll cap 75 → 750 | sleep-count ceiling in the never-present scenario |
| 4 | Remove the break-on-found | "present at poll 3" asserts exactly 3 sleeps |
| 5 | Keep the ready emit and add a second emit in the late arm | exactly-one-event per channel |
| 6 | Insert `reboot` (or `networkctl reconfigure`) in the timeout arm | forbidden-call log check |
| 7 | Remove the empty-argument guard | empty arg must yield probe_fault, never ok |
| 8 | Emit a fixed `by=` instead of the Network File basename | scenarios 1, 3 and 3b (three different basenames) |
| 9 | Treat a failing `ip` (rc≠0) as "absent" | ip-fails scenario must be probe_fault |
| 10 | Suite runs zero scenarios (own dispatch) | declared-scenario-count equality |

**Harness rows.** Suite edit that must RED: a `soleur-boot-emit` stub that records nothing (the
exactly-one-event assertion must then fail, not pass on 0 = 0). Must-PASS non-canonical inputs:
the expected address on an interface named `eth1` among docker/veth lines, and an `ip -o` output
with extra whitespace. Both must still classify correctly.

**Anchor.** Not applicable. Nothing stored is compared.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 `hcloud_server.inngest` is unchanged except for its `user_data`. `network.tf` gains
      only a comment edit, and no `hcloud_server_network`/`network {}` change exists in the diff
      (`git diff origin/main -- apps/web-platform/infra/network.tf | grep '^[+-][^+-]' | grep -v '^[+-][[:space:]]*#' | wc -l`
      → `0`; the `wc -l` form, because a bare `grep -v` exits 1 on the pass case). The only
      added line in `inngest-host.tf` is the var-map key
      (`git diff origin/main -- apps/web-platform/infra/inngest-host.tf | grep -c '^+[^+]'` → `1`).
- [ ] AC2 The rendered user_data (terraform `templatefile` + strip, through the new suite) contains
      `/etc/systemd/network/99-soleur-private-fallback.network` with exactly the Phase 2 content.
      It also contains one `networkctl reload` item and one NIC-wait call carrying `10.0.1.40`
      (rendered from `${inngest_private_ip}`) immediately before the zot login.
- [ ] AC3 `bash apps/web-platform/infra/inngest-nic-wait.test.sh` passes, runs the declared scenario
      count, and every Guard 2 mutation row reds against a mutated copy.
- [ ] AC4 `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` and
      `bash apps/web-platform/infra/cloud-init-inngest-zot-pull-mutation.test.sh` pass, with every
      Guard 1 row red on its mutation and both must-PASS inputs green.
- [ ] AC5 `bash apps/web-platform/infra/inngest-userdata-budget.sh` reports stored < 32,768 B
      (expected ≈ 15.5-16.5 KB; baseline 14,964 B), and the size test passes.
- [ ] AC6 The new suite is registered in `infra-validation.yml`, and
      `bash scripts/lint-orphan-test-suites.sh` is green.
- [ ] AC7 Every explicit inngest render map passes the new key: every file in
      `git grep -l 'web_host_private_ips *=' -- apps` is also in
      `git grep -l 'inngest_private_ip *=' -- apps`. `network.tf`/`server.tf` also match the
      latter; that is a superset, which is fine. `comm -23` of the two sorted lists prints nothing.
- [ ] AC8 `cloud-init-inngest.yml` contains no hardcoded `10.0.1.40` on a CODE line. Comments
      legitimately name it (for example the `#6178 diag` comment at :1670), so the check is scoped:
      `grep -v '^[[:space:]]*#' apps/web-platform/infra/cloud-init-inngest.yml | grep '10\.0\.1\.40' | wc -l`
      → `0` (the `wc -l` form, because `grep -c` exits 1 when it counts 0).
- [ ] AC9 ADR-115 carries the 2026-09-22 amendment, the three alternatives rows, and `8539` in
      `amended_by`. `network.tf:9-13` no longer claims the inline block force-replaces.
- [ ] AC10 The C4 tests and `plugins/soleur/test/c4-count-parity.test.sh` pass after the
      `model.c4` description edit.
- [ ] AC11 The runbook subsection exists and its query command is the same as the
      `discoverability_test.command`.
- [ ] AC12 PR body: `Closes #8539`. `Ref #6438`, `Ref #6500`, `Ref #6122`, with no closing
      keyword in any form next to 6500, 6122 or 6438. The body also states that delivery is the
      post-merge `inngest-host-replace` + human-approved `op=resume`.
- [x] AC13 The follow-up issue exists (#8562, filed at plan time) and the #6438 comment is posted (planning session). The PR body carries `Ref #8562`.

- [ ] AC14 The PR body's first line answers "does merging this alone change production?": **No.**
      The merge apply's `-target` allow-list contains no `hcloud_server.*`
      (`inngest-host.tf:507-511` records this), so the host changes only through the post-merge
      replace.

### Post-merge (orchestrator-owned, not a `soleur:work` gate)

- [ ] PM1 After the gated `inngest-host-replace` and the approved `op=resume`, the new boot emits
      exactly one `private_nic_*` marker, followed by `zot-login-ok` and `inngest_zot`. On an
      ordinary (un-raced) boot that marker must read `private_nic_ok … by=10-netplan-<if>`. This is the
      production check that the `99-` fallback leaves the good case alone (P4). A
      `by=99-soleur-private-fallback` on that boot is not a failure, but it means the race happened on delivery. A
      `by=none` means something other than networkd (e.g. an `hc-utils` hook) configured the NIC.
      That falsifies the plan's mechanism model and must be recorded on #8562.
      Checked with the `discoverability_test.command` below; no SSH.
      Automation: `bash scripts/betterstack-query.sh` under `doppler run -p soleur -c
      prd_terraform`. It is run by the orchestrator that dispatches the replace, not by a human.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Agrees with rejecting (a): at v1.63.0 the inline block is a post-boot attach with
public net, and it would ripple through the `-target`/gate/parity machinery for no gain. It also
agrees with correcting the stale `network.tf` comment. `networkctl reload` is low-risk for eth0,
since it reconfigures only links whose matching file changed, and netplan's file keeps eth0. The
risks it raised are all folded above: R1 persist in `/etc` (adopted), R2 keep DHCP from taking
the default route or DNS (adopted, via `RouteMetric` rather than `UseGateway=no`), R3 probe the
renderer (adopted), R4 validate runtime values (dissolved: the file has none). It also named two
out-of-scope items, the once-only runcmd pull and the other hosts. Both are tracked in the
follow-up issue and on #6438.

No Product/UX surface: infrastructure only, no UI file in either Files list. Product gate NONE.

## Test Scenarios

Run by `inngest-nic-wait.test.sh` against the helper extracted from the rendered template:

1. Address present at first probe, Network File = `10-netplan-enp7s0.network` →
   `private_nic_ok boot=….waited_s=0.by=10-netplan-enp7s0`, level info, 0 sleeps, exit 0.
2. Address appears at poll 3, Network File = netplan's → `waited_s=6`, exactly 3 sleeps, info.
3. Address appears at poll 5, Network File = `99-soleur-private-fallback.network` →
   `private_nic_ok … by=99-soleur-private-fallback`, level warning.
3b. Address present at the FIRST probe, Network File = the fallback → `waited_s=0.by=99-soleur-private-fallback`, level
   **warning** (the common shape of a healed race; Kieran P1-4).
3c. Address present, `networkctl status` shows no Network File → `by=none`, info.
4. Never present, link `enp7s0` SETUP `unmanaged` → `private_nic_timeout links=enp7s0:unmanaged`,
   exactly 75 sleeps, exit 0.
5. Never present, no non-eth0 virtio link → `private_nic_timeout links=none`.
6. `networkctl` missing from PATH, address present → `private_nic_ok … by=nonetworkctl`; address
   absent → `private_nic_timeout links=nonetworkctl`.
7. `ip` missing from PATH → `private_nic_probe_fault`, 0 sleeps.
8. `ip` present but always rc 1 → `private_nic_probe_fault` (not timeout).
9. Empty argument → `private_nic_probe_fault`, never ok.
10. Expected `10.0.1.4` while the host holds only `10.0.1.40` → not ok (word-bounded match).
11. Every scenario: exactly one event per channel, exit 0, and no reboot/poweroff/shutdown/
    `networkctl reload`/`networkctl reconfigure`/file write in the stub call log (the helper only
    reads; the reload is its own runcmd item).
    The emitted detail is ≤120 chars and uses only `A-Za-z0-9=.:_-`, with `boot=` first.
12. The `.network` content extracted from the render equals the Phase 2 block byte-for-byte.

## Risks and Sharp Edges

- **The converge mechanism is argued, not rehearsed.** No throwaway-host forced-race rehearsal
  runs in this pipeline, because creating hosts outside Terraform is not an allowed plan step. The
  failure mode is bounded: if networkd does not apply the fallback to the late link, the boot
  times out 150 s later and fails exactly as today, with a better event. The one new-risk
  direction is the fallback matching a link it should not. Rows 6-7 of Guard 1 pin the match
  scope and precedence against that.
- **The strip regex eats `#`-prefixed lines inside block scalars.** The helper must have no code
  line starting with `# ` (comments go above the YAML entry). The test extracts from the STRIPPED
  render for exactly this reason.
- **templatefile escaping.** The helper is brace-free and `%{`-free. Every `${…}` in the diff must
  be a real template var (`inngest_private_ip`) or an escaped `$${…}`. Grep the diff for `\${` and
  `%{` before commit.
- **runcmd is one `/bin/sh`.** Both new items end in `|| true`, and the helper never `exit`s
  non-zero.
- **Delivery couples to the scheduler outage window.** It is the same accepted cost as every inngest
  cloud-init change (ADR-100). Nothing in this pipeline dispatches it.
- **Cloud-init hotplug interplay.** On an image where cloud-init hotplug is active, the queued
  event runs after `cloud-init.target` and may render its own `10-netplan-*` file for the NIC and
  run `netplan apply`. Our file then yields by precedence. The `netplan apply` would be
  cloud-init's behaviour today regardless of this change.
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits
  the threshold will fail `deepen-plan` Phase 4.6. It is filled above.
