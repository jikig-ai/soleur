# Decision challenges — feat-one-shot-8807-grep-q-pipe-guard-or-fp

These are plan-time decisions that went against a reviewer's recommendation, or that narrowed the
brief's stated scope. They are recorded under ADR-084 so they can be audited outside this session.
`ship` renders this file into the PR body.

---

## DC-1 — Keep `&?` (`|&` coverage) in the pattern

**Classification:** Taste

**Challenge:** DHH and code-simplicity both recommended cutting `&?`. Their reasons: the repo has 0
lines that pipe `|&` into `grep -q`, and issue #8807 never asked for it.

**Decision:** Keep `&?`. The brief asked me to consider `a |& grep -q`. `|&` is `2>&1 |`, which has
the same SIGPIPE fail-open this guard exists to stop, and the old pattern missed it. The cost is 2
characters and 1 probe line, and it adds no new red checks.

**Reopen if:** the `&?` widening ever produces a false positive.

## DC-2 — Class coverage narrowed: the infra siblings are not edited in this PR

**Classification:** User-Challenge. The brief said "cover the class, not the instance".

**Challenge:** Two of the four copies of the regex live under `apps/web-platform/infra/`.

**Decision:**

- `sigpipe-triage-feasibility.sh` `SHAPE=` is left unchanged. Its normalisation step 5 already
  rewrites `||` to `__OR__`, so its real-site counts do not move under the anchor. Measured
  429 → 429 (Kieran).
- `workspaces-luks-verify-root-mtime.test.sh` `A3-nopipe` has 0 exposure today and is deferred to
  **#8869**. Any `apps/web-platform/infra/**` edit fires `apply-web-platform-infra.yml` on push to
  main (CTO, verified against its `paths:` filter). A one-token test regex should not queue a
  production apply on its own.
- AC5 is the census that shows only these two dispositioned lines remain.

**Reopen if:** `assert_mount_quiesced` gains a `|| grep -q` line, or the next PR that touches
`apps/web-platform/infra/` lands (fold #8869 in there).

## DC-3 — Probe does not run through `git grep` (engine parity declined)

**Classification:** Taste

**Challenge:** The plan-time advisor consult recommended counting probe hits with
`git grep --no-index` so the probe uses the same engine as the sweeps.

**Decision:** Declined, following DHH and code-simplicity. The sweeps pass `-E`, which overrides
`grep.patternType`. GNU `grep -E` and `git grep -E` agreed on every probe line (git 2.55.0). The
only failure this would catch is a hypothetical future switch to `-P`.

**Reopen if:** the sweeps ever change engine or flag (`-P`, `-G`).
