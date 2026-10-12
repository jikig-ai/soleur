---
title: git-data host-originated liveness heartbeat — gate the beat on local checks, read the URL at runtime, arm only after a measured beat
status: accepted
date: 2026-10-10
supersedes: none
issue: 9438
related: [8211, 8093, 9943]
related_adrs: [ADR-103, ADR-117, ADR-149, ADR-198, ADR-239, ADR-260, ADR-280]
tags: [git-data, observability, heartbeat, better-stack, liveness, doppler, cutover]
brand_survival_threshold: single-user incident
---

# ADR-283: git-data host-originated liveness heartbeat

## Status

**Accepted (2026-10-12, record PR closing #9438).** The decision described a target state that is only true after the owner's host replace
and a measured first beat; both have happened. The host from replace run 38140050880 was armed with `arm-heartbeats.sh --arm-one` (#9980,
PR #10029): `outcome=armed`, `status=up` within 11 s, monitor 506836 (`period=60 grace=300`, read live for the first time by that run's
`--status`). The Slack half of the alert route is evidenced by Better Stack incident 1030432412 (`soleur-inngest-luks-wrong-volume-prd`, started
2026-10-11, after ADR-260), whose timeline records "Incident update posted to #error-found." with Slack permalinks, read from the Uptime
API. The ordinal was verified free against `origin/main` and every `origin/*` ref on 2026-10-10 and is re-verified at ship.

## Context

The git-data host holds every connected user's source code and serves the Art. 17 erasure path, and between boots it emitted no recurring
signal of its own (its last was `boot_complete`). The only recurring beat is fed by the web hosts: `web-git-data-probe.timer` opens a TCP
connection to port 22 and pings `betteruptime_heartbeat.git_data_prd` (ADR-103, #6548). That proves only that some web host can open a
connection; under Ubuntu 24.04 socket activation `ssh.socket` accepts it whether or not the service behind it works. A full disk, an exhausted
inode table, a closed or unmounted LUKS store, a failed security unit, or a dead web fleet are all invisible to it. The `flip` in
`git-data-cutover.yml` freezes writes on this host, so a host that is dark between boots must page before the flip (#9438).

## Decision

1. **A host-originated feeder, gated on local checks.** `git-data-liveness.timer` runs `git-data-liveness.sh` every 60 s. It pings a new,
   dedicated heartbeat (`soleur-git-data-host-prd`, period 60, grace 300) only when the loopback sshd answers with an `SSH-` banner, the store
   is mounted read-write from `/dev/mapper/git-data`, its root lists and one uncached block of the mapper reads, bytes and inodes are
   under 90 %, and `git-data-luks-reopen.service` and `git-data-nftables.service` are loaded and not failed. An unreadable measurement withholds the beat; it never reads as healthy. Absence of the ping is
   the alert. `git-data-gc.service` is deliberately not gating (the paging policy for it stays on #8093), and `/` usage is reported on every
   event but does not gate.
2. **A withheld ping says why.** Every state change, and a `state=ok` summary every 10 minutes while healthy, is emitted through the existing
   `git-data-emit` channel at level `info`, stage `liveness`. It is deliberately unrouted: the page is the heartbeat, the event only explains.
   The registry's post-mortem (a feeder that only gates cannot explain its own silence) is the design input.
3. **The URL is read at runtime, never baked.** The host reads `GIT_DATA_HOST_HEARTBEAT_URL` from the scoped read-only Doppler config it
   already holds a token for, through `doppler run --config "$GIT_DATA_DOPPLER_CONFIG"`, and caches it on tmpfs at `0600`. The cache has no TTL: while pings succeed the secret is not re-read, so a
   rotation takes effect on the first rejected ping or at the next boot, and a fetch that returns nothing falls back to the
   last-tried URL, reported as `ok:last_good`. It reaches curl on
   stdin through a process substitution with a shape guard (ADR-280's rule), never on an argument list. Because the URL is not in
   `user_data`, the rung-2 rehearsal render carries no production monitor, and a rehearsal host (whose scratch config lacks the secret) is
   structurally unable to ping it; the config name is compared by exact equality, never by prefix.
4. **Born paused, armed only after a measured beat.** The monitor and its masked Doppler secret ride the per-merge `-target` list and are
   refused by the birth route. The monitor ships paused with `ignore_changes = [paused]`, carries `arming_pending` in the heartbeat manifest,
   and is NOT in the per-merge arm list: the feeder reaches the host only through the owner-authorized replace, so an arm line would roll
   back and fail every merge until then (ADR-117). Arming is a separate, measured, owner-authorized step after a soak read.
5. **A hard flip precondition, re-read at flip time.** The cutover runbook records it, with a read-only verification, a 30-minute soak
   floor, a failure branch and a flip-time re-read (monitor `up` and a `state=ok` event under 15 minutes old and later than the current
   host's `boot_complete`), because the runbook requires a fresh replace immediately before the cutover and a box ticked once goes stale.
   Machine enforcement in the cutover workflow is deferred to #9943.
6. **The payload ships through the existing two-PR sequence.** The three payload files are hash-bound, so they ride the rung-2 two-PR
   sequence together with the one ready hash-bound item of #8093 (the stale pre-receive comments), and the replace the cutover already
   requires carries them: no second replace is added.

## Alternatives Considered

| Option | Verdict |
|---|---|
| Bake the URL into `user_data` (the registry's route) | Rejected. The rehearsal root renders the same module, so it would carry the production URL and ping the production monitor, or need a closed-allowlist divergence entry the rung-2 gate refuses for identity-class values. It also fixes rotation to a replace. |
| **Runtime read from `prd_git_data` under the baked scoped token** | **Chosen.** No new variable, rehearsal-safe by construction, same boundary as the LUKS reopen. |
| Logs-based dead-man alert | Rejected. Needs a periodic emit anyway (still a payload edit), is born armed (a false alert before the host carries the emitter), and depends on ingestion lag and log quota. The native heartbeat is absence-alerting by construction. |
| A log shipper on git-data | Rejected (ADR-198): structurally cannot reopen the quota breach, and the issue says no Vector. |
| Extend the web probe to check store health over SSH | Rejected. Not host-originated, needs a fourth forced-command key (the authorization-map gate pins exactly three), and dies with the web fleet. |
| Reuse the existing `git_data_prd` URL from the host | Rejected. A reused heartbeat URL masks the break the new probe is for: either feeder's beat hides the other's silence. |
| Arm in the per-merge arm step | Rejected. Every merge would unpause, wait out the deadline, roll back and fail until the owner replaces the host. |
| Pause and unpause the monitor around replaces | Rejected. A production write per replace, and each re-arm needs a new measured beat. An armed monitor pages about six minutes into a planned replace; the runbook says to announce it. |

## Consequences

- The arming tooling (`--status` and `--arm-one` in `arm-heartbeats.sh`) landed with #9980 (ADR-117's 2026-10-11 amendment),
  ahead of the owner's arm. It was a separate issue because the record PR closes #9438.
- One more recurring emitter on a host that already has two: the cost is about 4 KB of stored `user_data` (measured with
  `git-data-userdata-budget.sh`, recorded in the PR body) against the 32 KB cap.
- A known-benign `miss` on a healthy fresh host is a payload defect fixed forward through the two-PR sequence; the thresholds are hash-bound
  and there is no agent waiver.
- Between merge and replace there is a paused-yet-fed gap that the nightly `fed-but-paused` alarm is told to expect (`arming_pending`); it
  does not suppress `absent-live`.
- Until #9943 lands, the precondition is a runbook item with a re-read, not a workflow gate.
- A rehearsal host can never exercise the armed path (Doppler fetch, curl, ping): its scratch config lacks the secret by construction,
  and the suite drives the real script against fakes. A defect in the real ping path therefore first shows during the production soak,
  and fixing it costs another payload PR, rehearsal and replace.
- The URL also reaches the environment of the other `prd_git_data` consumers that run `doppler run` without `--only-secrets` (the gc
  unit and the bootstrap stages). Its ceiling is forging one "alive" ping, no code dumps an environment, and the claim above is therefore
  "never baked and never on an argument list", not "present nowhere else on the host".
- The checks read the mount table, `statfs`, the mount options and a directory listing; the store is never written (a probe write would
  move the mtime the cutover's quiescence check reads). `mountpoint` exits 32, not 1, for an existing directory that is not a mountpoint,
  and a unit that does not exist reads `inactive` with exit 0, so the feeder reads the load state too, and judges only `loaded` units by their
  active state. Every instrument runs under a 2 s cap, then a KILL one second later. The cap holds for a hang that dies on TERM or
  KILL; a process in uninterruptible sleep on a dead device survives both, the tick is then ended by `TimeoutStartSec=58` with nothing
  emitted, and the page, which is the heartbeat's absence, needs no event to fire. The first-entry listing of the store root is
  usually served from cache, which is why one uncached block of the mapper is read as well.
- The emitted event can flap: a changed code re-emits at once, so a value hovering at a threshold can emit every tick (at most 1440 a day).
  Accepted: the page is the heartbeat, and the event is unrouted.

## Credential rule applied to the new URL

The heartbeat URL passes the three-part test used for the baked ingest token (ADR-198): its ceiling is lower (it can only forge an "alive"
ping for one monitor, and reads or writes nothing else); it lives only in `prd_git_data` and on tmpfs at `0600`, and never in `user_data`,
`/proc/*/cmdline` or any emitted line; and it is single-purpose.
