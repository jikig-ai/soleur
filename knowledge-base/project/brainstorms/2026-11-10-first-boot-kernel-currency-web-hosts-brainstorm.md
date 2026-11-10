---
date: 2026-11-10
topic: first-boot kernel currency for web hosts
issue: 12008
branch: feat-kernel-patch-web-hosts-12008
lane: cross-domain
brand_survival_threshold: single-user incident
---

# First-boot kernel currency for web hosts (#12008, item 1)

Public-repository rule (ADR-322): this document carries no kernel string, vulnerability id, host address or
exposure verdict. Per-host answers stay in the session.

## What We're Building

A replaced web host should come up on the archive's current generic kernel, not on the stock base image's kernel.
Today the web cloud-init runs a bounded `apt-get update` and installs four named packages only, so a replace is a
rebuild without a kernel refresh (the gap recorded in #12503 and in the cadence runbook).

The change: the bounded apt step in `apps/web-platform/infra/cloud-init.yml` also installs the generic kernel meta
package, and cloud-init reboots once at the very end of first boot, only when a reboot is required, before the host
is graded healthy. Web class only on this branch.

## Status of #12008's four items

| Item | Status |
|---|---|
| 1. Patch and reboot web hosts when the distro ships the fix | Trigger fired 2026-11-10 (owner comment). This branch carries the code half; the acts are owner-authorized. |
| 2. Standing cadence per host class | Shipped in PR #12497 (probe unarmed, #12504). |
| 3. Public TCP exposure of non-web hosts | Shipped in PR #12497 (declared-design check). |
| 4. Newer-LTS evaluation | Split out to its own deferred issue (CTO ruling); not part of this branch. |

## Why This Approach

Ruled by CTO agent, 2026-11-10 (binding technical ruling):

- **Kernel meta package, not a pinned version** — the meta package tracks the archive, so later fixes arrive without
  another edit. A pin goes stale on the next advisory.
- **Not a full upgrade** — a full upgrade also moves Docker/containerd and changes behaviour.
- **Not a baked image** — a new subsystem (snapshot lifecycle, new ADR); revisit only if first-boot time becomes a problem.
- **Reboot last** — runcmd runs once and `/run` is wiped on every boot, so a mid-runcmd reboot leaves a half-built host.
- **Web class only** — editing the registry cloud-init auto-replaces the registry host on merge with no reviewer gate;
  inngest and registry get their own owner-authorized PRs; git-data keeps its interlocked path.
- **Merging changes no running host** — the web servers set `ignore_changes = [user_data, ssh_keys, image, ...]`
  (`apps/web-platform/infra/server.tf`, verified), so only the next replace picks it up.

## Key Decisions

| Decision | Choice | Source |
|---|---|---|
| Kernel route on replace | Kernel meta package in the bounded apt step + end-of-boot conditional reboot | CTO ruling |
| Scope of this branch | Web cloud-init, a sibling test (shape of `apt-bounded.test.sh`), the user-data size guard, a runbook note | CTO ruling |
| #12503 | Narrowed to inngest, registry, git-data (not closed) | CTO ruling |
| Item 4 | Deferred to its own issue with the re-open criteria from the 2026-11-07 assessment | CTO ruling |
| New ADR | "First-boot kernel upgrade and reboot on host create" | CTO ruling |
| The host the replace path refuses | Owner decision, held (see Operator acts) | CTO ruling + owner-only category |
| Public wording | Routine host/kernel refresh; no vulnerability id, host or exposure verdict in issues, PRs, commits | CLO + ADR-322 |
| User communication | Direct notice ~24h before any serving outage, one-line "done" after; no public status page | CPO |
| Timeliness target | Replaceable hosts refreshed within 72h of the fix; decision on the non-replaceable host within 7 days (14 hard) | CLO |

## Operator acts (each needs the owner's typed go naming the exact command)

1. Merge this PR (per-merge infra apply; expected no-op for servers).
2. `web-host-replace` for the replaceable web host: `plan_only` first, then the real run.
3. (Agent, read-only) Reader run confirms that host's reset uptime and changed kernel.
4. `Operator-reserved:` the non-replaceable web host — whether to grant a one-off exception to the immutable-redeploy
   rule (in-place kernel install + one reboot, performed by the owner) or raise #9421's priority instead.
5. Later PRs + replaces for inngest, then registry; git-data via its own interlocked route.

**Correction to the CTO ruling's item 2 (verified, `server.tf` lifecycle comment):** committed config keeps the app
record on the refused host only and pools no LB weight on the replaceable one ("anti-pooling", ADR-068/ADR-143). So
"reboot while the other web host carries traffic" does not hold: a reboot of the refused host is a full app outage for
its duration. The CPO's 24h notice and a
maintenance page apply to act 4 if the owner chooses the exception.

## Open Questions

- Does cloud-init's end-of-boot reboot ever fire before the app container is up? `unverified` — needs a rehearsal on
  the replaceable host before any serving replace (CTO dissent).
- Does the non-replaceable host survive a reboot (volume by-id pins, provisioner-left state)?
  `unverified` (CTO dissent); only relevant if the owner picks the exception.
- The replaceable web host reports no reader rows (silent). Why is a plan-time question; the post-replace
  verification depends on its emitter.
- User-data byte budget: headroom under the 32,768-byte cap must be measured at plan time.
- Count of active web-app users before choosing a window (CPO; roadmap Current State is dated 2026-08-11).
- Maintenance page while the host is down: in scope for act 4 or a follow-up? (out of scope for this branch)

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering

**Summary:** CTO ruled the kernel meta package + end-of-boot conditional reboot, web class only, with item 4 split out
and #12503 narrowed. Verified: stock image on every host class, `ignore_changes` covers `user_data` on web servers.

### Product

**Summary:** Exposure outweighs minutes of planned downtime; patch within days at the lowest-usage hour with a direct
24h notice. Exclude a public status page and an in-app banner system. Gate "patched" on reading the new host's kernel.

### Legal

**Summary:** No Art. 33 notification (no exploitation evidence; fails the breach-register inclusion predicate). Art. 32
"state of the art" argues for 72h on replaceable hosts and a 7-day decision on the other. ADR-322 governs all public wording.

## User-Brand Impact

- **Artifact:** the web host replace path and the first-boot cloud-init kernel step (`apps/web-platform/infra/cloud-init.yml`).
- **Vector:** a replaced host reported as refreshed while still running the base image's kernel (silent false
  assurance), or a first-boot reboot that leaves a half-built host serving users' workspaces.
- **Threshold:** single-user incident.

## Capability Gaps

- No sanctioned refresh route for the web host the replace path refuses — evidence:
  `knowledge-base/engineering/operations/runbooks/web-host-replace.md` (refusal section); reboot workflow retired
  (`web-host-reboot.md`); permanent fix is #9421 (open, p3, last update 2026-10-03).
