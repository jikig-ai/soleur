# Learning: a reaper whose trigger isn't installed is a no-op — verify the scheduler exists before counting on the mechanism

## Problem

Designing session-temp reclamation for `/tmp` + `/var/tmp` (#7004 arc), the
existing machinery looked complete on paper: `scripts/tmpfs-guard.sh` runs every
5 minutes from a user cron and reaps stale scratch entries.

Measured on the operator host (2026-09-24): **the guard has never run.**
`crontab` is not installed on this host (Arch/Omarchy — systemd, no cronie),
there is no `~/.local/state/soleur/` state dir, and no installer script exists
in the repo — the cron entry was always operator-managed. The only reclamation
that actually ran was the session-start `cleanup-merged` sweep (22 stale dirs).

Companion finding: the #7004 plan's "legacy backlog self-drains" premise was
scoped to the tmpfs (10d aging + wiped on reboot). The same plan extended to
`/var/tmp` — disk-backed, 30d aging, ~4 GB/day production against 46G free —
breaks silently: the drain that was verified for one mount does not exist at
the same rate on the other. **A premise verified for one base must be
re-derived per base.**

## Solution

For the brainstorm/spec this produced:

- Reaper trigger = session-start `cleanup-merged` (plugin-shipped, demonstrably
  runs on every host) as primary; tmpfs-guard cron retained where installed;
  optional `systemd --user` timer added for cron-less hosts (spec FR8).
- Backlog purge promoted from deferred to prerequisite for `/var/tmp` —
  operator-invoked, quarantine-mediated.
- Verification habit: for any mechanism invoked by a scheduler, check the
  trigger exists (`crontab -l`, `systemctl --user list-timers`, the mechanism's
  own heartbeat/state dir) before treating it as live. The heartbeat file
  (`~/.local/state/soleur/tmpfs-guard-last-run`) is the ground truth — its
  absence *is* the measurement.

## Key Insight

A mechanism is two claims: the code and the trigger that runs it. The repo can
prove the first; only the host proves the second. When a fix's blast radius
depends on "X runs every N minutes," measure the trigger, not the script —
`crontab` missing is a one-command check that a month of careful reaper design
never caught because every prior session assumed the cron it documented.

Same shape as "an alarm channel nobody reads" — the artifact exists, the
delivery path doesn't. Existence of the producer is insufficient; measure the
delivery.

## Session Errors

1. `ls /var/spool/cron` permission failure — one-off environment.
   **Prevention:** none needed; fall back probes (`crontab -l`, heartbeat dir)
   answered the same question.
2. Recursive `grep -r` at repo root descended into ~100 stale worktrees
   (`.claude/worktrees/`, `.worktrees/`) — slow and noisy.
   **Prevention:** prefer `git grep <pat> HEAD -- <paths>` or `--exclude-dir`
   for repo-source searches; reserve filesystem `grep -r` for bounded dirs.
3. `du -sm /var/tmp/*` exceeded the output timeout mid-enumeration — one-off
   scale issue on a 45k-entry directory.
   **Prevention:** sample subsets (`head -N`, per-prefix globs) for sizing on
   dirs with unknown cardinality.

## Tags

category: workflow-patterns
module: tmpfs-guard, worktree-manager, session-start
