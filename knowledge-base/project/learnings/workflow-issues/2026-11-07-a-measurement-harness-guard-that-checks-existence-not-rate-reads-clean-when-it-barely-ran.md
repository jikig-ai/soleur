# Learning: a measurement harness's guards must check rate and coverage, not existence

## Problem

#12013 / PR #12310 measured per-site cost of the three replay arms (concurrent runs, a timestamp hook) to decide
whether a `--rows` rebalance was worth landing. The verdict was `NO-REBALANCE` (the table failed split-half
stability on arms b and c; nominal-best re-splits lost 366-376 s on the worst paired combination), so the
deliverable became the table, the decision and the ADR-242 amendment. The risk was never the arithmetic; it was
that every guard around the readings could pass while measuring nothing:

- the in-run sampler that sights foreign test runs counted as "alive" if it wrote ONE tick (`-s .sampler-ticks`),
  so a sampler that died after 15 s of a 25-minute reading left a CLEAN verdict;
- the foreign-run detector matched the runner's OWN private clone (cwd under `$O`) and flagged every reading
  DISTURBED;
- the what-if's validation passed when its per-rep file was missing, truncated, or held a different arm map, and
  its "material in ANY rep" rule was pinned by no fixture (swapping `any` for `all`, or for rep 1 only, stayed
  72/72 green);
- the table builder parsed stamps with `Decimal`, which accepts `NaN`/`Infinity`, so a corrupt stamp failed by
  crashing or by producing non-finite costs instead of a refusal;
- two readings ran concurrently because a wrong-pid chain launched r3 while r2 was live; r2's own guard said
  CLEAN.

## Solution

- Liveness is a RATE: require `ticks >= elapsed/15 - 2`, not `-s file`.
- A foreign-run scan must exclude the harness's own working tree by path, and have a test with the harness's
  own process in view.
- An exclusive `flock` in the runner plus a cross-rep time-overlap refusal in the table builder (the second
  catches what the first cannot: readings taken by different invocations).
- Validation fails CLOSED on every shape of "I cannot see the thing I am validating": missing file, zero rows,
  rows that do not cover exactly the table's sites/arms/reps, `?` labels, non-finite times.
- Each fail-closed branch gets a fixture that reds on its removal, and each selftest has an absolute assertion
  floor (`MIN_CHECKS`) that is raised in the same edit that adds a check.
- The verdict (`GATE: NO-REBALANCE`) is reproducible by anyone: raw guards/stamps are committed, the table
  rebuilds with `cmp`, and the ADR amendment names the sentences it supersedes instead of editing them.

## Key Insight

A guard that asserts the instrument EXISTS (a file is non-empty, a process was seen once, a column is present)
certifies a reading that barely ran. Assert the instrument's RATE and COVERAGE against the thing it was meant to
cover (ticks per second of run, rows per site, reps per arm). Then pin each such assertion with a fixture whose
only difference is the property, because a mutant that survives 72/72 means the property is documented, not
checked. A fresh-eyes verification seat found four of these AFTER a review panel and a fix round had both passed,
so a fix round on measurement tooling should end with a verifier that is told to grade the fix commit as its
own change.

## Session Errors

1. **Reading r3 launched concurrently with r2 through a wrong-pid chain; both disturbed, r2's guard said CLEAN** — Recovery: exclusive flock in the runner, cross-rep overlap refusal in the table builder, r1-r3 recorded as disturbed and unused — Prevention: a harness that takes timing readings must serialise itself (lock) AND the consumer must refuse overlapping reps; done in `site_cost_run.sh` / `site_cost_table.py`.
2. **Killing the validation script left its run alive (orphan burning the host)** — Recovery: process-tree kill, clean relaunch; runner now has an exit trap that kills descendants on INT/TERM/HUP/QUIT — Prevention: any runner that spawns long arms installs a trap before the first spawn; proven by a kill test (TERM left no arm, lock free).
3. **Hook denials: `pgrep -f`, `ps | awk` with a pattern, `git stash list`** — Recovery: `source plugins/soleur/scripts/lib/proc.sh; list_runs <name>` — Prevention: already hook-enforced; use `list_runs` first.
4. **Unquoted heredoc containing backticks executed `bash scripts/test-all.sh` in the worktree** — Recovery: TaskStop, verified no leftover process and no tracked change, redid the patch via the Write tool — Prevention: for text that contains backticks or `$(`, use the Write tool or a quoted heredoc (`<<'EOF'`); never an unquoted heredoc.
5. **`sites_of` missed 2 sites and mislabelled a no-row call from a later statement; 84 rows were unlabelled; two wrong labels (sites 213/352) from a trailing `# comment`** — Recovery: scan from the call line to the first line ending in a row token and stop at the next call; regex allows a trailing comment; `check()` rejects `?` labels — Prevention: an extractor that maps source to ordinals needs a fixture per call shape and an `--check` that rejects unlabelled output.
6. **Patch quoting error (`suite\'s`) broke a generated-file edit** — Recovery: edited the patch file — Prevention: one-off; apply multi-line text edits with a script file, not an inline quoted string.
7. **Review defects: fail-open stability checks, a stale "r1/r2" label, overstated claims, sampler holding the lock after a kill, own-subshell false positive** — Recovery: fixed in review round 1 and 2 — Prevention: see Key Insight (rate and coverage, with a mutant-killing fixture).
8. **Verification seat found four more (finite stamps, per-rep coverage, union-materiality fixture, sampler tick-rate) and two ADR claims wrong (control2's last suite; approval gap 293 s not 294)** — Recovery: fixed in a third commit — Prevention: after a fix round, run one seat told to grade the fix diff as its own change and to re-derive every figure the prose adds.
9. **`site_cost_whatif.py --check` invoked without its table argument (rc 2, usage text)** — Recovery: passed the path — Prevention: one-off; read the usage line before invoking.
10. **A `nohup bash validate.sh &` started from a tool shell died silently (empty log, no process), and a Monitor waited on a log that could never fill** — Recovery: re-ran under the tool's own background mode and watched for the run's final line — Prevention: never arm a watch on a detached process you did not first see alive (`list_runs`); start long jobs with the tool's background mode.
11. **Stop hook fired on a closing line promising a next action** — Recovery: did the independent steps (correction comments, commit), then ended with a `Paused:` line naming the one pending event — Prevention: when a wait is real, name it in one `Paused:` sentence; do not end on a plan.
12. **Merge conflict with main in ADR-242 (both branches appended a dated amendment at the file end) and one transient `remote rejected` push** — Recovery: kept both amendments in date order; the push succeeded on retry — Prevention: fetch and run `git merge-tree --write-tree origin/main HEAD` before the final push, since ADR amendments appended at EOF collide whenever two PRs amend the same ADR.

## Tags

category: workflow-issues
module: test-gate measurement (knowledge-base/project/specs/feat-one-shot-12013-site-cost-measurement)
