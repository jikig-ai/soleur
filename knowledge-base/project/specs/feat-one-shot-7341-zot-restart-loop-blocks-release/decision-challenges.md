# Decision Challenges — feat-one-shot-7341-zot-restart-loop-blocks-release

Persisted headless per ADR-084 / `plan-review` classifier routing. `ship` Phase 6 renders these into
the PR body and files an `action-required` issue. Each entry is surfaced, not silently applied.

---

## DC1 — Keep or delete ADR-189 (Taste; reviewers split)

**The split.** `dhh-rails-reviewer` argued to delete ADR-189 outright: *"'The timeout is N seconds' is
a value, not an architecture decision"*, and noted that deleting it also dissolves an AC, a risk row,
the ordinal Sharp Edge and part of a phase. The `cto` domain leader independently recommended
creating it (*"it is a production host-config change with a documented coupling to `gcDelay`, it
retires a standing misattribution to the CF tunnel, and it feeds directly into ADR-167's pending
re-open"*).

**Resolution taken in the plan: KEEP, narrowed.** One of DHH's two premises was falsified between the
review being dispatched and the finding landing — it argued the ADR's shape depended on a measurement
that had not happened, and the measurement had by then been performed. What the record carries is not
the number (which lives next to the setting in `cloud-init-registry.yml`) but three things a value
cannot: the tunnel's exoneration, the cross-subsystem `gcDelay` coupling, and the Arm C split-brain.
`code-simplicity-reviewer` independently converged on "keep, narrowed" — its finding was that
ADR-189's *message-honesty half* duplicates ADR-166, which the plan now cites rather than restates.

**Operator decision available:** delete ADR-189 and rely on Guard 3 alone. The plan is written so
that removal touches only the ADR section and AC set.

---

## DC2 — Re-targeting the work away from #7341 (scope; invited by the brief)

**What changed.** The work was handed as *"open P1 #7341 — `/var/lib/zot` is 100% full … zot is still
restarting ~4x/min"*. Live telemetry refutes both clauses for the current host (`pcent=12`;
`zot_restarts=0` with monotonic uptime across 48 h), and the measured cause is a zot HTTP deadline
that consumes no disk.

**Not treated as a challenge** because the brief explicitly asked for this determination (*"Decide
explicitly in the plan whether this PR closes #7341, partially addresses it, or files a distinct
issue"*). Recorded here for visibility rather than for adjudication: the plan files a distinct issue,
leaves #7341 open under its existing follow-through, and contributes the two refutations back as a
comment.

---

## DC3 — An acceptance criterion the panel wanted promoted, and the plan excludes (Mechanical)

`dhh-rails-reviewer` argued that *"the next `Web Platform Release` reaches `mirror_status=ok`"* **is**
the acceptance criterion and should be first. The plan excludes it.

**Basis, measured after that review was dispatched:** the failure rate is roughly **1 in 13** (12
consecutive successes, one failure, then a success at 21:54:00Z). Such an AC passes ~92% of the time
on a completely unfixed system. `kieran-rails-reviewer` and `spec-flow-analyzer` reached the same
exclusion by independent routes — the former on `cq-ac-must-not-depend-on-concurrent-sessions`, the
latter on the observation that merging this PR fires a release against the still-un-replaced host.

Classified Mechanical (a measurement decides it), so applied rather than surfaced. Logged because it
reverses an explicit reviewer recommendation.
