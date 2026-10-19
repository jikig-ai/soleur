---
title: "web-2 deploys aborted at plugin-mount seeding for 25 days (docker cp fchmodat2 EPERM on a foreign-uid tree) — and every release reported success"
date: 2026-10-19
incident_pr: 8743
incident_window: "2026-09-24 07:19:20Z — ongoing at write time (25 days and counting); still firing 2026-10-19T13:25Z (v0.344.11)"
recovery_at: "PENDING — the fix rides the existing infra-config delivery channel; recovery is proven by the first post-delivery web-2 deploy (`PLUGIN_SEED_PROBE` row + zero new fchmodat2 rows), graded by scripts/followthroughs/web2-plugin-seed-8743.sh"
suspected_change: "#8660 (fresh-boot zot-by-bake, merged 2026-09-24T03:22Z — touched cloud-init.yml + server.tf user_data): cloud-init seeds /mnt/data/plugins/soleur via a root-run docker cp, and Dockerfile's `chown -R 1001:1001 /opt/soleur` lands the tree uid-1001-owned on every fresh boot"
brand_survival_threshold: aggregate pattern
status: ongoing
triggers:
  - deploy-pipeline availability (every web-2 deploy aborts at the plugin-mount seed)
  - observability gap (the release workflow reported success on all ~25 days of failures — web-2's async exit-1 reached no channel)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — availability/deploy incident, no personal-data exposure"
# Classification rationale: availability-only and not user-realized. web-2 is the
# weight-0 standby — the load balancer never routed user traffic to it — so no
# request was served the stale build. The real losses were fleet redundancy (a
# web-1 replace would have left the app serving a 25-day-old build or nothing),
# the watchdog dispatch clock's per-host backup coverage, and the release gate's
# integrity. The threshold is `aggregate pattern` because the blast radius is the
# deploy pipeline's trustworthiness fleet-wide, not one user's data.
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

Every web-platform deploy delivered to web-2 (`soleur-web-2`, 10.0.1.11) via the
`/hooks/deploy-peer` fan-out has aborted since 2026-09-24 07:19 UTC, at
`ci-deploy.sh`'s plugin-mount seeding step: `docker cp soleur-plugin-seed:
/opt/soleur/plugin/. "$PLUGIN_MOUNT_DIR/"` fails with `fchmodat2 .claude-plugin:
operation not permitted`, and the script exits 1 with
`reason=plugin_seed_copy_failed`.

The release workflow reported `success` on every one of those deploys. Its
completion check polls web-1's `/hooks/deploy-status` (web-1 exits 0 — it
deploys fine), and its health check reads `app.soleur.ai/health` through the
load balancer, answered by web-1 (weight 1); web-2 (weight 0) is invisible to
the run result. The peer's async exit-1 was a 202-accepted spawn whose verdict
reached no channel — ADR-068 constraint (c)'s per-host verification was recorded
but never built.

## Status

ongoing — the fix (container-side seed + `peers` status merge + fail-closed
release peer gate) is in this PR; recovery is observed on the first post-delivery
web-2 deploy, graded by `scripts/followthroughs/web2-plugin-seed-8743.sh`.

## Symptom

- 16 `fchmodat2` Better Stack rows at filing time (2026-09-24), every one
  `host=soleur-web-2`; still firing through 2026-10-19T13:25Z (v0.344.11).
- web-2 stayed on the last pre-07:19 build for 25 days — including through
  ~100 subsequent releases that all reported green.
- web-2's watchdog dispatch clock (added by #8691, merged 09-24T14:31Z) ran
  only on web-1: web-2's deployed ci-deploy.sh was stale because the deploys
  that carry updates were the thing failing.
- `Deploy succeeded` / `INNGEST_HEALTH_CHECK` / `BWRAP_USERNS_SYSCTL_CHECK`
  rows: zero on web-2 in the window (the deploy never got past the seed).

## Incident Timeline

- **Start time (onset):** 2026-09-24 07:19:20Z (first fchmodat2 row)
- **Detected:** 2026-09-24 ~15:06Z (#8743 filed from post-merge verification of #8691)
- **End time (recovered):** pending (first post-fix deploy on web-2)
- **Duration (MTTR):** open at write time — 25 days and counting

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | pre-window | The `docker cp`-based plugin-mount seed lands in `ci-deploy.sh` — correct only while the mount tree is deploy-owned. |
| agent | 2026-09-23T18:31Z | #8600 merges (retire host GHCR read path). |
| agent | 2026-09-23T19:52–20:10Z | `web-host-replace` of web-2 runs dark (the #8651 tokenless-Doppler zot incident); web-2 left dark as evidence. |
| agent | 2026-09-24T03:22Z | #8660 merges — fresh-boot zot-by-bake; cloud-init.yml's runcmd seeds `/mnt/data/plugins/soleur` via root `docker cp`; the Dockerfile's `chown -R 1001:1001 /opt/soleur` makes the extracted tree uid-1001-owned; cloud-init's `chown -R deploy:deploy /mnt/data` runs BEFORE the seed so the 1001-ownership survives. |
| agent | 2026-09-24 early AM | web-2 boots from the #8660 template → its mount tree lands uid-1001-owned. |
| agent | 2026-09-24T07:19:20Z | First post-boot deploy reaches web-2 via fan-out; the deploy-uid `docker cp` hits `fchmodat2 .claude-plugin: EPERM` → `plugin_seed_copy_failed` → exit 1. ONSET. |
| agent | 2026-09-24 | Every subsequent release's web-2 leg aborts identically; every run reports success (LB /health + web-1 deploy-status are the only verdicts read). |
| agent | 2026-09-24T14:31Z | #8691 merges — watchdog dispatch clock runs on every deployed web host; web-2's copy stays stale (its deploys abort). |
| agent | 2026-09-24T15:06Z | #8743 filed (P1): the missing `SOLEUR_WATCHDOG_DISPATCH` rows on web-2 during #8691's post-merge verification were the tell — not the deploy failure itself. |
| agent | 2026-09-25 | web-2 replaced (per #9151); defect recurs — every fresh boot re-seeds a uid-1001 tree. |
| agent | 2026-09-29 | `terraform_data.deploy_pipeline_fix_web2` lands (apply run 36646627695) — the bastion delivery channel that now carries the fix. |
| agent | 2026-09-30 | web-2 replaced again (SSH key re-pinned, run 36743565651); defect recurs a second time. |
| agent | 2026-10-19T13:25Z | Still firing — v0.344.11's web-2 leg aborts at the seed, minutes before this plan was written. |
| agent | 2026-10-19 | Root cause confirmed repo-grounded (deploy uid 1000 vs uid-1001 tree); fix PR authored. |

## Participants and Systems Involved

`apps/web-platform/infra/ci-deploy.sh` (plugin-mount seed + `fan_out_to_peers`),
`apps/web-platform/infra/cat-deploy-state.sh` (`/hooks/deploy-status`),
`apps/web-platform/infra/cloud-init.yml` (root-run birth-time seed),
`apps/web-platform/Dockerfile` (`chown -R 1001:1001 /opt/soleur`, `USER soleur`
uid 1001), `webhook.service` (`User=deploy` uid 1000), `.github/workflows/
web-platform-release.yml` (deploy-verify steps), the Hetzner private net
(10.0.1.0/24, `:9000` HMAC fan-out), Better Stack (journald rows via Vector).

## Detection (+ MTTD)

- **How detected:** indirectly — the #8691 post-merge verification noticed
  `SOLEUR_WATCHDOG_DISPATCH` rows absent on web-2 (its watchdog clock runs from
  the deployed ci-deploy.sh, which was stale because deploys were aborting).
  #8743 was filed ~7h47m after onset. The deploy failure itself fired no alert.
- **MTTD (onset → filing):** ~7h47m — good.
- **MTTD (filing → fix):** 25 days and counting — the *detection gap that
  matters*. After #8743 was filed, nothing else ever fired: no alert on
  `plugin_seed_copy_failed`, no per-host deploy verdict in the release run, and
  the file-level `deploy-status` poll only ever read web-1. An open P1 issue
  was the only thing standing between the outage and silence — and the outage
  survived two full host replacements without anyone noticing it recur.

## Triggered by

system — a code change (#8660's cloud-init seed) interacted with a pre-existing
ownership assumption in `ci-deploy.sh` (the deploy-uid `docker cp` could only
ever seed a deploy-owned tree), on a path no host had exercised since #3045-era.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Mount ownership/mode — foreign-uid tree | `docker cp` untars client-side as the invoking uid (deploy, uid 1000); `fchmodat2` EPERM is exactly an ownership violation; cloud-init seeds as root; Dockerfile `chown -R 1001:1001` | — | CONFIRMED |
| Read-only or `nosuid` remount of `/mnt/data` | plausible mount-level cause | `nosuid` does not EPERM `fchmodat2`; a read-only mount would fail `find -delete` and the `.seed-complete` write differently; `PLUGIN_SEED_PROBE` now emits `findmnt` to adjudicate in-surface | REJECTED |
| Filesystem difference vs web-1 | candidate by symmetry | the immutable factor is ownership (web-1's tree is uid-1000, pre-seed), not the filesystem | REJECTED |

## Resolution

This PR, in three parts:

1. **Root cause** — `ci-deploy.sh` seeds the plugin mount container-side: one
   `docker run --rm -u 0 --entrypoint /bin/sh -v "$PLUGIN_MOUNT_DIR":
   /plugin-mount` that clears, `cp -a`s, and writes `.seed-complete` inside the
   image. Root-in-container can clear/copy a tree of ANY ownership, so a
   cloud-init-seeded uid-1001 tree can no longer wedge it — self-healing on the
   first deploy after delivery, no `-replace`, no SSH. The seed emits
   `PLUGIN_SEED_PROBE dst_owner=… marker=… findmnt=…` BEFORE mutating, so the
   discriminating ownership facts land in journald → Better Stack.
2. **Observability** — `write_state`/`final_write_state` persist
   `fanout_peers`; `cat-deploy-state.sh` merges a `peers` map into
   `/hooks/deploy-status` (each fan-out peer's own status JSON, private-net
   HMAC GET, bounded, error-slotted).
3. **The gate** — `web-platform-release.yml` gains `Verify peer deploy
   completion`: fail-closed on any expected peer not reporting
   `exit_code==0 && tag==v$VERSION` for the release.

## Recovery verification

Pending delivery. Graded post-merge by `scripts/followthroughs/web2-plugin-seed-8743.sh`
(Better Stack, no SSH): PASS requires (a) zero `fchmodat2` rows on
`host_name=soleur-web-2` at/after the first post-fix marker, (b) the host still
ships `ci-deploy`/`webhook` rows, and (c) a `PLUGIN_SEED_PROBE` /
Deploy-succeeded-class row exists for web-2. Plus `peers["10.0.1.11"].exit_code==0`
in the next release's `deploy` job.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did web-2 deploys abort?** `docker cp soleur-plugin-seed:…` returned
   `fchmodat2 .claude-plugin: EPERM`; the script aborted at
   `plugin_seed_copy_failed`.
2. **Why EPERM?** `docker cp` untars *client-side as the invoking uid*.
   `webhook.service` runs `ci-deploy.sh` as `User=deploy` (uid 1000), and
   uid 1000 cannot chmod or delete entries owned by uid 1001. (The pre-copy
   `find -mindepth 1 -delete` was silenced by `|| true`, so the foreign-uid
   entries survived to be re-chmod'd.)
3. **Why was the tree uid-1001?** `cloud-init.yml` seeds
   `/mnt/data/plugins/soleur` at boot as **root** via the same `docker cp`
   (root has no such constraint), and `Dockerfile`'s `RUN chown -R 1001:1001
   /opt/soleur` means the extracted tree lands uid-1001-owned. cloud-init's
   `chown -R deploy:deploy /mnt/data` runs BEFORE the seed item, so the
   1001-ownership survives untouched.
4. **Why was web-1 immune?** Its mount tree predates the cloud-init seed block
   and is deploy-owned (uid 1000). Only a *fresh-booted* host ever gets a
   root-seeded uid-1001 tree — so the defect recurred on web-2's 09-25 and
   09-30 replacements, and is systemic to every future web-host birth.
5. **Why did every release report success?** The `deploy` job's two verdicts
   never saw web-2: the deploy-status poll reads web-1's hook (web-1 deploys
   fine), and `/health` is LB-verified — answered by weight-1 web-1. The peer's
   202-accepted async deploy exited 1 into a channel nobody read (ADR-068 (c)
   recorded the peer-verification design but it was never built), and no alert
   watches `plugin_seed_copy_failed`/`fchmodat2` rows.

**Final root cause:** a client-side-untar `docker cp` run as uid 1000 against a
uid-1001-owned mount tree produced by cloud-init's root-run seed — compounded
by an observability gap that let a per-host deploy failure read as fleet
success for 25 days.

## Versions of Components

- **Version(s) that triggered the outage:** the onset deploys were
  web-`v0.291.x` — `v0.291.0` merged 2026-09-24T03:22Z riding #8660's
  fresh-boot work, and web-2's first post-boot deploy at 07:19Z hit the EPERM.
  (`v0.293.0`, merge `2426534dc6`, deploy run 36016449118, was the LAST
  attempted deploy before #8743 was filed — not the trigger.) The LATENT
  defect is the `docker cp` seed, made fatal by the 09-24 cloud-init seed.
- **Version(s) that restored the service:** this PR's `ci-deploy.sh` once
  delivered by `apply-deploy-pipeline-fix.yml` +
  `terraform_data.deploy_pipeline_fix_web2`, verified on the first post-delivery
  deploy.

## Impact details

### Services Impacted

- web-2's deploy path — completely dark for 25 days; every release's web-2 leg
  aborted at the seed.
- Fleet redundancy — the app ran single-origin (web-1 only) for 25 days; a
  web-1 outage or replace in that window had no standby.
- Watchdog dispatch coverage — #8691's per-host backup clock existed on web-1
  only.
- Deploy-verdict integrity — ~25 days of release runs reported success over a
  half-failed fleet.

### Customer Impact (by role)

- Prospect: none (web-2 is weight-0; the LB never routed to it).
- Authenticated app user: none realized — web-2's stale build served nobody.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

25 days of silent half-fleet degradation discovered only via a secondary
symptom (missing watchdog rows), plus this remediation. The stale web-2 also
meant every infra-config delivery assertion for web-2 was reporting against an
undeployable host.

## Lessons Learned

### Where we got lucky

- web-2 is weight-0: the stale build served no user traffic, and web-1 carried
  the fleet for 25 days without incident. Had web-2 been weight-1, ~50% of
  traffic would have hit a 25-day-old build — and had web-1 failed during the
  window, there was no warm standby.
- The watchdog-clock verification (#8691's post-merge check) happened to look
  at web-2's rows the morning after onset; without that tell the outage could
  have run indefinitely.

### What went well

- The 2026-09-24 filing was fast (~8h from onset) and correctly named the
  observability gap as a defect in its own right.
- Better Stack rows were sufficient for full no-SSH diagnosis — onset, host
  scope, and still-firing status were all measured off-box.

### What went wrong

- **Two uid assumptions met silently.** cloud-init's root-run seed and the
  Dockerfile's 1001 ownership were each correct alone; together they produced a
  tree the deploy-uid `docker cp` cannot touch. The pre-copy `find -delete ||
  true` silenced the deletion failure that would have shown it sooner.
- **The 202-accept was read as a verdict.** `deploy-peer` returns 202 on
  spawn-acceptance; the peer's async exit-1 went nowhere. ADR-068 constraint
  (c) recorded the fix shape ("private-net + peer-driven") months earlier and
  it was never built — a recorded-but-unimplemented design is indistinguishable
  from a decided one until it fails.
- **The release gate only ever verified one host.** Both verdicts the `deploy`
  job reads — web-1's state file and the LB's `/health` — are web-1 answers. A
  weight-0 host's failure has no path to the run result, by construction.
- **No alert on the abort signature.** `plugin_seed_copy_failed` / `fchmodat2`
  rows fired on every deploy for 25 days and paged nobody; the only thing that
  caught it was a human verifying a different feature's follow-through.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #10577 | Container-side `docker run -u 0` seed (root cause fix, self-healing); `PLUGIN_SEED_PROBE` in-surface emit; `fanout_peers`/`peers` status merge; fail-closed `Verify peer deploy completion` release step | this PR |
| #8743 | Soak-graded closure: `scripts/followthroughs/web2-plugin-seed-8743.sh` enrolled via directive (`earliest=<merge+2d>`) | open, enrolled |
| #10584 | Better Stack / Sentry alert on `plugin_seed_copy_failed` / deploy-peer abort signatures — the release gate catches failures only at release time; a fleet-level alert pages between releases | open |
| #10585 | `web-host-replace` verifies the replacement host's FIRST deploy — the defect recurred across two web-2 replacements (09-25, 09-30) unnoticed because nothing after boot checks the host's first deploy outcome | open |
