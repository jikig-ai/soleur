---
title: Dedicated-host boot-armed push heartbeats require a mechanically-guarded non-SSH reprovision path
status: accepted
date: 2026-07-09
amends: none
supersedes: none
issue: 6242
related: [6238, 6246, 5274, 6178, 6122]
related_adrs: [ADR-096, ADR-100, ADR-068, ADR-082]
brand_survival_threshold: single-user incident
---

# ADR-103: Dedicated-host boot-armed push heartbeats require a mechanically-guarded non-SSH reprovision path

## Context

A dedicated Hetzner host behind a deny-all-public firewall (git-data, inngest, registry) cannot
be probed externally by Better Stack, so its liveness/health uses a **PUSH heartbeat**: something
pings a heartbeat URL on a cadence, and *absence of ping* alerts. The pinger is installed either
(a) **on the host itself by cloud-init** (the registry disk cron in
`cloud-init-registry.yml`, the inngest systemd timer from `cloud-init-inngest.yml`, and — since
#6537 — the registry *liveness* timer in `cloud-init-registry.yml`), or (b) by a separate
**web-host cron** over the private net (git-data — still an unshipped follow-up, #6548).

> **Amended (#6537):** registry *liveness* was listed under (b) as an unshipped follow-up. It is now
> class (a): armed by the registry's own cloud-init. Its class-(b) framing is what let it sit
> paused and unfed for 9 days — the manifest's own row restated it. See the ADR-117 block below.

For class (a) the heartbeat and its cron ship in the same PR, but **`terraform apply` creating the
heartbeat does NOT redeploy the host** — cloud-init runs only on host create/replace. If the host
has no non-SSH reprovision path, the newly-added cron is never installed and the heartbeat is a
guaranteed false-positive absence alert.

This is exactly what happened in **PR #6238** (`soleur-registry-disk-prd`): the disk-gated
heartbeat `betteruptime_heartbeat.registry_disk_prd` shipped in the same PR as the host cloud-init
cron that pings it, but the registry host had **no** non-SSH reprovision path, so the ping cron was
never armed and the orphaned heartbeat fired. It was fixed reactively — a human caught it *after*
the false-positive incident — by adding the `registry-host-replace` scoped-`-replace` dispatch
(ADR-096 amendment). Nothing mechanically prevented a future PR from re-introducing the class.

<!-- lint-infra-ignore start -->
Brand-survival threshold: `single-user incident` — a false-positive on a data-bearing host's
heartbeat erodes trust in the alert channel (alert fatigue → a real incident gets ignored), and the
absence of a reprovision path means a genuine host-config fix (a LUKS keyscript fix, a Vector wiring
change) has no sanctioned non-SSH remediation, forcing an operator-local `terraform apply -replace`
that violates `hr-prod-host-config-change-immutable-redeploy` / `hr-no-ssh-fallback-in-runbooks`.
This paragraph *describes* the anti-pattern the ADR prevents (the sanctioned path is the dispatch
job); the operator-local apply is precisely what must NOT happen.
<!-- lint-infra-ignore end -->

## Decision

**Every `betteruptime_heartbeat` whose arming/remediation depends on a dedicated Hetzner host's
boot-time provisioning (an on-host cloud-init cron OR a cloud-init-installed systemd timer) MUST
have that host's `<host>-host-replace` dispatch path** — a choice option in
`.github/workflows/apply-web-platform-infra.yml` plus a `-replace='hcloud_server.<host>'` line in
its scoped, destroy-guarded job.

The invariant is keyed on the **monitored host's remediation**, NOT the cron's file location, so it
correctly covers inngest's systemd timer and does not misclassify git-data's web-host ping.
Heartbeats whose arming is a web-host cron / app-container emit / an external probe are exempt —
their remediation is a web-host / container ci-deploy (which always exists) or an external probe,
never a dedicated-host reprovision.

**The path requirement is deliberately keyed on the arming CLASS, not the declared `paused` value.**
An earlier framing ("every *non-paused* boot-armed heartbeat MUST have a path") was tightened during
review (security-sentinel P3 + pattern-recognition F4): 4 of the 6 heartbeats carry
`lifecycle { ignore_changes = [paused] }`, which decouples the `.tf` `paused` value from the live
Better Stack state — the established pattern ships a boot-armed heartbeat `paused = true` and
UI-unpauses it after first deploy, and Terraform never reconciles the source value. Keying the path
requirement on source `paused` would therefore leave the exact #6238 hole open (a future
`paused = true` + `ignore_changes = [paused]` + UI-unpaused boot-armed heartbeat with no path). So a
dedicated-host-boot heartbeat requires the path **regardless of its source `paused` value**. This is
strictly stronger and stays green today (inngest is `paused = true` but HAS `inngest-host-replace`;
`registry_disk_prd` is `paused = false` and HAS `registry-host-replace`).

**The enforcement is a static-analysis CI test**, `plugins/soleur/test/heartbeat-reprovision-parity.test.ts`:
it parses every `betteruptime_heartbeat` block in `apps/web-platform/infra/*.tf`, reads each
block's declared `paused` value from source, and diffs against an in-test manifest that classifies
each heartbeat by arming mechanism (the codified, enforced form of the #6242 Audit Matrix). A new
heartbeat with no manifest entry fails the test; a `dedicated-host-boot && !paused` heartbeat whose
declared `<host>-host-replace` path is absent fails the test. This is the mechanical gate that
would have caught #6238.

> **Amended by [ADR-117](./ADR-117-executable-heartbeat-arming.md) (#6537, 2026-07-16).** The
> `arming` axis above is **prose**: it records which remediation class a heartbeat belongs to, but it
> never asserted that anything actually pings it. #6537 exploited exactly that gap — `registry_prd`
> sat classified `web-host-cron` with an exempt_reason citing a probe cron that was never written, so
> **this manifest restated the fiction** while the monitor sat paused and inert for 9 days.
>
> ADR-117 adds an executable `feeder` field alongside `arming`: every row is either FED (a file +
> pattern the test greps each run) or HONESTLY UNFED (`kind: "none"` + a tracking issue, and — the
> load-bearing half — an assertion that its URL secret still has zero consumers, so the day a feeder
> ships, CI reds and forces the row to reconcile). The manifest moved to
> `plugins/soleur/lib/heartbeat-manifest.ts`.
>
> Consequence for this ADR's own rule: `registry_prd` reclassifies to `dedicated-host-boot`, so the
> `replace_target` requirement now fires for it — correctly, since its feeder ships via cloud-init
> and therefore reaches the host only on a fresh boot.

The scoped `-replace` dispatch mechanism itself is the ADR-096 (registry) / ADR-100 (inngest)
pattern; ADR-103 does not invent it — it generalizes the ad-hoc registry fix into an enforced,
cross-host rule and mandates the reprovision path exist for the whole class.

git-data (#6242) is the third host to adopt the scoped `-replace` dispatch (`git-data-host-replace`).
Its heartbeat `git_data_prd` is web-host-cron armed and paused today, so the guard does not by
itself require the path; the path is justified independently by git-data's standing zero-non-SSH-
reprovision-capability gap on the fleet's most irreplaceable data store (ADR-068).

## Considered Options

- **A — Codify the invariant + a CI guard + add the missing git-data path (CHOSEN).** The guard is
  the mechanical enforcement; the ADR is the record; the git-data path closes the one host that
  lacked any reprovision path. Cheap (a static test, zero live infra), forward-looking.
- **B — Keep it ad-hoc per host.** Rejected — that IS what let #6238 happen. A human catching a
  false-positive after an incident is not a control.
- **C — Fold the invariant into ADR-100.** Rejected — ADR-100 is inngest-scoped; this invariant is
  cross-host, so it earns its own decision record.
- **D — Surface the invariant as an AGENTS.md `wg-*` gate for plan-time loading.** Deferred (not
  rejected): the always-loaded AGENTS budget is near cap. The CI guard is the enforcement; the ADR
  is the record. An AGENTS pointer can be added later if budget headroom permits.

## Consequences

**Easier:** the #6238 recurrence class is caught at CI (RED on the PR, blocks merge) instead of by a
post-incident human. Every dedicated host now has (or is mechanically required to have) a non-SSH
reprovision path, satisfying `hr-prod-host-config-change-immutable-redeploy` /
`hr-no-ssh-fallback-in-runbooks`.

**Harder / accepted:** authors adding a `betteruptime_heartbeat` must now classify it in the
manifest (arming + reprovision path or exempt reason) — a small, deliberate friction that is the
point of the gate. The `paused`-source-vs-manifest drift assertion means unpausing a boot-armed
heartbeat requires reconciling the manifest in the same PR.

## Alternatives Considered

See **Considered Options** above (A chosen; B "keep it ad-hoc per host" and C "fold into ADR-100"
rejected; D "AGENTS.md `wg-*` gate" deferred on budget).

## Diagram

**No C4 model edit.** All relevant elements are already modeled: the git-data / inngest / registry
hosts and their stores (`model.c4` `gitDataStore`, `inngest`, zot registry), Hetzner Cloud, Better
Stack (`model.c4` `betterstack` — already names "Apex + inngest/git-data heartbeats"), and GitHub
Actions (the dispatch runner). Adding a reprovision *dispatch workflow* + a static CI guard changes
no modeled edge (a CI operation on an existing host, not a new data-flow between elements). Verified
against all three `.c4` files; no model delta, so no `.c4` validation-test run is required.
