---
title: "A behavior-preserving grep conversion needs rows that observe discrimination — the happy path is satisfiable by an always-true grep"
date: 2026-10-07
category: test-failures
module: apps/web-platform/infra boot-path scripts + .claude/hooks/grep-q-pipe-guard.test.sh
issues: [9217]
---

# Characterization rows before a shell-form conversion

## Problem

Pass 2 of the `grep -q` sweep converted six pipe-fed predicates in `web-private-nic-guard.sh` (4) and
`cron-egress-enforce-probe.sh` (2) to `grep -c … >/dev/null`. Both owning suites were green before the change and
stayed green after it, which proved nothing: they exercised each site only on the happy path (canonical address,
canonical IMDS body, the container name on the first line). An always-true conversion, a dropped `-w`/`-F`/`-x`, a
forgotten `>/dev/null` and an inverted `!` all keep every pre-existing row green.

## What works

- **Write the rows against the UNCONVERTED script first and require green.** A behavior-preserving refactor cannot be
  driven RED by its own tests, so `cq-write-failing-tests-before` is met by rows that assert current behavior and then
  bite under hand-applied mutants (a mutant is the RED).
- **One row per way the weaker form gives a false positive:** a prefix near-miss for `-w` (`10.0.1.1` inside
  `10.0.1.10`), a lookalike for `-F` (`10a0b1c10`), a longer-tail address for a closing `$` anchor, near-miss names
  for `-x`, a missing jump for the structure predicate.
- **Observe the wait loop's success arm with a call-counting stub** and assert the EXACT call count (3, versus 32 when
  the `break` is deleted); the final `nic_ok` is identical either way.
- **Pin stdout cleanliness in the runs that reach each site.** Dropping `>/dev/null` prints a bare count on stdout;
  every other assertion is a substring match and cannot see it. The absent-start runs matter: the wait loop is only
  reached when the address is absent.
- Result on the real scripts: 18 hand-applied mutants (drop `w`/`F`/`x`, drop `!`, empty pattern, always-false wait,
  deleted `break`, dropped `>/dev/null` at each of the six sites, `||`→`&&`, never-matching pattern), none survived;
  the three ledger mutants went red in `grep-q-pipe-guard.test.sh`.

## Sharp edges

- **The six sites had no `pipefail`, so none misread a match today.** The sweep row counted a text shape, not a live
  misread. Say so in the PR body: this pays the deferral table to zero; it is not a flake fix.
- **Site 4 (`printf "$IMDS_NETS" | grep -c '^[0-9]+$'`) is an equivalent mutant of its own conversion:** the value is
  the output of `grep -c`, always numeric, so the fallback arm is unreachable from any stub. The only evidence for that
  conversion is the exit-status equivalence table (bash and dash, 8 inputs x 2 patterns, 32 rows, 0 differences).
- **A battery's "killed" is `rc != 0`, which a crash also satisfies.** Record the first failing ROW per mutant; a
  first filter that matched `FAIL` also matched the suite's own `ASSERT-FAILED` section heading and named the wrong row
  for the probe mutants until it was anchored on the `FAIL:` prefix.
- **A hook suite that scans the repo cannot run in a hand-extracted subtree.** The sandbox copy needed a commit and the
  files its fixture list names; the Guard 1 mutants were applied in the committed worktree with pristine copies and a
  clean-tree check instead.
