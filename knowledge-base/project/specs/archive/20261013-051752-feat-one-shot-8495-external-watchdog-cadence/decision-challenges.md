# Decision challenges: feat-one-shot-8495-external-watchdog-cadence

These were recorded headlessly during plan and plan-review for #8495. All of them are Taste: the
operator's direction is unchanged, and the plan went with the default.

## 1. A runtime kill-switch flag for the watchdog dispatch clock (Taste, declined)

- **Source.** The CTO, in the devex-lens plan-review (F1).
- **Proposal.** Gate each tick on a Flagsmith runtime flag, `watchdog-dispatch-clock-enabled`,
  defaulting to on.
- **Plan's default.** No flag. An emergency stop is `gh workflow disable <file>`, which halts both
  the clock's dispatches (they return 422) and the GH fallback. A full removal is a revert.
- **Reasons for the default.**
  - A flag adds a new Flagsmith and Doppler object, plus a network read on every tick.
  - The clock only ever triggers an existing, idempotent watchdog. It has no destructive side
    effect of its own that would need finer-grained control.
- **Revisit if** someone needs to stop the clock while keeping the GH fallback running.

## 2. Move the restart budget to persisted state before the clock ships (Taste, declined)

- **Source.** The scoped advisor consult (plan Step 4.5).
- **Proposal.** Split the watchdog's 45-minute give-up window into a persisted last-restart
  timestamp or count, landing in its own PR, so that restart count no longer depends on run count.
- **Plan's default.** Keep the time-based window. It was the #6374-reviewed design, and it assumed
  a cadence of every 15 minutes.
- **Reasons for the default.**
  - After the cutover, the `restart-inngest-server.yml` dispatch cannot reach the dedicated host
    (10.0.1.40).
  - Duplicate runs are bounded, at about 5% of slots.
- **Revisit if** a post-merge incident shows more than about 4 restarts inside one give-up window.
