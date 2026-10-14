# Decision challenges — #7004 (headless; surfaced for operator decision)

Recorded per ADR-084. These are **Taste / User-Challenge** class — they touch the operator's stated
scope and must not be applied silently. `ship` renders these into the PR body and files an
`action-required` issue.

---

## UC-1 — #7004's acceptance criterion 2 cannot be met as written, and should be amended

**The issue says:** *"A dry run against a real /tmp carrying the leak reclaims the leak and reports
ZERO non-leak candidates."*

**What the plan delivers:** the ZERO-non-leak-candidates half is met and measured (19,957
non-candidates, 0 false positives). The *"reclaims the leak"* half is met only for leaks of the
**declared** shape. The 20,700 entries in `/tmp` today predate the ownership declaration and are
structurally unreachable — reclaiming them needs exactly the age/size heuristic #6991 measured and
removed for deleting ~1,500 pieces of authored work.

**Why this is not evasion:** the backlog is verifiably self-draining — mtimes span a rolling 8-day
window, **zero** entries survive the 10d `tmpfiles.d` age, and `/tmp` is tmpfs so a reboot clears it.
The complaint resolves passively within ≤10 days.

**Decision needed:** amend #7004's AC2 to *"reclaims leaks of the declared shape within one cron
interval; the pre-existing backlog is bounded by tmpfiles.d + reboot and is explicitly out of
scope"*, so the PR does not close an issue against a criterion it does not meet. Renegotiating an
operator-stated AC inside a plan footnote is the failure mode this entry exists to prevent.

---

## UC-2 — Three PRs instead of one

Both review panels converged independently. **PR 0** = alarm rebaseline (~40 lines; the guard alarms
every 5 min *today*, independent of the reaper, so this has the highest immediate operator value and
ships first and alone). **PR 1** = allocator + Reaper 3 + one runner + ADR. **PR 2+** = adoption tail.

**Safety motivation:** PR 2 carries ~25 `env -i` allowlist edits, each an independent judgement call
against the plan's highest-consequence rule (a root is scratch-only). Reviewing those in the same
sitting as a destructive reaper is how the pressure-tier failure returns.

**Cost:** #7004 is not fully closed by PR 1. Reclamation ships; broad adoption follows.

---

## UC-3 — Day one, the operator sees only one thing

After PR 0 + PR 1 the visible delta is **the every-five-minutes alarm going quiet**. The 677 MB of
legacy `/tmp` is reclaimed by the next reboot, not by these PRs, and the reclamation benefit is
measured at day 7 by the soak probe. The plan states this in the Overview rather than burying it.

**Decision needed:** confirm that an invisible-on-day-one fix is acceptable, or ask for the backlog
to be cleared by a reviewed one-shot (which would require re-opening the heuristic question).

---

## UC-4 — The runner migration may not reach the RAM problem

Both runners **already** export `TMPDIR=/var/tmp`. So entries landing in `/tmp` — the RAM-backed
mount this issue is about — come from paths that do **not** inherit: the Claude Code Bash sandbox
(documented unrelocatable by any settings/env lever), directly-invoked scripts, hooks, `env -i`, and
hardcoded literals. Migrating the runners converts **`/var/tmp`** leaks (which cost disk) into
self-reaping roots.

**Decision needed:** PR 2 must first attribute `/tmp` growth to named producers and state what
fraction the mechanism can reach. If the answer is small, the Claude Code sandbox — not the test
runners — is the real target, and that may warrant its own issue.
