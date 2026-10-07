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
- **Run the suites:** `bash apps/web-platform/infra/web-private-nic-guard.test.sh` (floor 169) and
  `bash apps/web-platform/infra/cron-egress-enforce-probe.test.sh` (floor 65); the ledger is
  `bash .claude/hooks/grep-q-pipe-guard.test.sh`.
- **Mutants, each applied to ONE site on a scratch copy and each killed by the named row** (reproduce by hand with the
  edit in the middle column; the row is the first red). NIC guard sites: 1 = trigger predicate, 2 = the same predicate
  inside the wait loop, 3 = IMDS expected-address, 4 = IMDS numeric check. Probe sites: 5 = container readiness
  `until`, 6 = DOCKER-USER jump check.

  | Mutant | Edit | Killed by |
  |---|---|---|
  | drop `w`, site 1 or 2 | `-cwF` to `-cF` | W-1 |
  | drop `F`, site 1 or 2 | `-cwF` to `-cw` | W-2 |
  | drop the closing `$`, site 3 | remove `$` before the closing quote | W-4 |
  | drop `x`, site 5 | `-cx` to `-c` | P2-2 |
  | remove `!`, site 6 | `if nft` | P-X1c |
  | empty pattern, site 6 | `grep -c ''` | P2-4 (empty chain) |
  | jump pattern shrunk to `jump`, `SOLEUR` or `SOLEUR-EGRESS` | shorten the literal | P2-4 lookalike chain (`goto SOLEUR-EGRESS` carries the name without a jump) |
  | site 2 always false / delete its `break` | `if false` / drop `break` | W-5 / W-5 (count 32, not 3) |
  | wait loop cut to one iteration | `seq 1 30` to `seq 1 1` | W-5b |
  | wait-loop bound shortened / lengthened | `seq 1 29`, `seq 1 2` / `seq 1 31` | W-5c / W-5d (32 calls either way) |
  | container-wait bound changed | `-ge 30` to `-ge 1`, `-ge 2`, `-ge 31` | P2-2 (exactly 30 `docker ps` polls) |
  | structure step moved after the behavioural probes | reorder the nft/systemctl block | P2-4 (no `docker exec` on the failing chain; a healthy-run control proves the logger sees `exec`) |
  | last-line-only or first-line-only reader before site 1 or 2 | `\| tail -1`, `\| head -1` | W-5 / W-7 (the address is mid-list, with a docker0 line after it) |
  | last-line-only or first-line-only reader at site 6, or the pattern shrunk to `SOLEUR-EGRESS` | `\| tail -1`, `\| head -1`, shorten the literal | the multi-line healthy stub, and the `goto SOLEUR-EGRESS` lookalike in P2-4 |
  | first-entry-only IMDS reader, site 3 | `\| head -1` | W-4b (expected address in the second entry) |
  | drop `>/dev/null`, any of sites 1-6 | remove the redirect | W-6 (sites 1-4), P2-6 (sites 5-6) |
  | site 4 `\|\|` to `&&`, or a never-matching pattern | edit the line | W-4 (`imds_nets=1`) |
  | `-1`-style readers (`head -1`, `tail -1`) in front of site 5 | insert a pipe stage | P2-3 (match is mid-list) |
  | trigger never matches (`"__none__"`) | change the pattern | W-7 (exactly two `ip` calls) |
  | append a pipe-fed early-exit `grep`, revert one site, leave `GATED_PROD_ROWS` at its pre-retirement 8 | three edits | the hook suite |

  Two review rounds each found survivors the author's own battery had missed. Round one: loop retry population of
  one, an unobserved trigger must-match arm, a one-member jump fixture, a last-line-only match. Round two: the loop and
  container-wait bounds (a bound is a number, so pin it from both sides), last-line-only readers at the trigger, the
  structure-step ordering (the row dropped as redundant was its only observer), and a first-entry-only IMDS reader.
  Every one was a fixture with one member on an axis the predicate quantifies over.
- **Real-tool check.** The stubs were also checked against the real tools: `ip -4 -o addr show` and `docker ps
  --format '{{.Names}}'` give the same exit status through `grep -cwF`/`grep -cx >/dev/null` as through `-q`
  (match 0, miss 1). `nft list chain` needs root and was not probed; it is the same text-stream shape.

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
