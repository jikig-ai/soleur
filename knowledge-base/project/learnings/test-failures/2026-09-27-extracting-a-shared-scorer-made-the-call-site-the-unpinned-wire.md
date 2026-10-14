---
title: Extracting a shared scorer made the call site the unpinned wire
date: 2026-09-27
category: test-failures
module: apps/web-platform/infra mutation batteries
tags: [mutation-testing, shared-helper, guard-vacuity, pipefail, sigpipe]
issue: 8855
pr: 9033
---

# Learning: extracting a shared scorer made the call site the unpinned wire

## Problem

#8855 routed seven mutation-battery row scorers (five batteries plus zot-pull's `failed_on`) through one sourced
library, `apps/web-platform/infra/lib/mutation-scorer.sh`. The library got a thorough self-test, and the pipe guard
pinned the consumer files against piped scorer spellings. Plan review cut a "routing presence" check (does each
battery still call the lib?) on the grounds that such a regression "fails closed already".

Measured at review, it does not. With the ssl battery's call site replaced by `if false`, the source line
deleted, and row M1 given a needle the guard never prints, the battery reported `OK: 20/20` and the pipe guard
stayed green. Every red row scores KILLED with no attribution. The same wire was just as unpinned on `main`
with the old inline scorer. The extraction didn't create the gap; it moved it to a single named line and left
that line unpinned.

## Solution

- **A probe seam in the lib.** If `MUTATION_SCORER_PROBE` is set, `mutation_scorer_failed_on` prints
  `MUTATION_SCORER_PROBE_REACHED <caller>` and exits 86 on its first call. The seam can only turn a run red, never
  green, so an inherited value fails closed.
- **A derive-and-run suite, `mutation-scorer-consumers.test.sh`.** It runs `git grep` to find every file that
  sources the lib, runs each with the probe set, and requires exit 86 plus the marker. Each run stops at its
  first scorer call, so all six batteries finish in about 9 seconds, against roughly 5 minutes for full reruns.
  A consumer floor catches a battery that stopped sourcing the lib.
- **Guard hardening.** The guard now derives the lib's sourcing files and fails on any it does not pin. It runs
  `PATTERN_PIPED_SCORER` on the zot-pull pass as well. It counts DISTINCT pin members. It also uses one
  `scan_scorers()` that the non-vacuity probe drives directly, because testing the pattern strings in isolation
  cannot see a dropped pattern or a widened comment filter.
- **Lib self-test.** Every call runs in a subshell that prints `RAN` only when the lib *returned*. So abort
  rows prove the lib exited, which a `return 2` would fail. The instrument check also drives the two
  verdict-owning helpers, `want_rc` and `want_abort`, with inputs that must fail.

A 13-mutant battery against the review fixes killed all 13.

## Key Insight

When N inline copies become one shared helper, the helper's unit test covers the *endpoint* and the call site
becomes the *wire*. No mutation of the helper can reach the wire, so a green helper suite plus a green consumer
suite says nothing about whether the consumer calls the helper. The cheap pin is a **probe seam that can only
fail closed** plus a **suite that derives the consumer set and requires each consumer to reach the seam**. A
per-consumer "misroute" row across N differently shaped harnesses costs ~5x more and is still per-site.

Corollary: a plan-review cut justified by "this regression fails closed already" is an unmeasured claim.
Measure it with the one-line mutation it names before cutting the check.

## Session Errors

1. **The planning subagent's summary contradicted its own plan file.** It said ssl's scorer still piped into
   `grep -qF`; the plan (correctly) said all six named sites were `grep -cF`. — Recovery: re-grepped `origin/main`
   before `soleur:work`, recorded in session-state. — **Prevention:** existing rule (a Session Summary is a claim
   about a file; verify cited facts on disk).
2. **The plan carried three wrong facts.** It said 18 files where the true count was 13, and 7 spellings where
   there were 6. It also claimed the cut pins guarded regressions that "fail closed already", which was measured
   false. — Recovery: a review addendum in the plan. — **Prevention:** the new plan sharp edge (measure a
   cut's "already fails closed" rationale); existing rule for plan-quoted counts.
3. **The first AC7 mutator run broke on escaping.** It was an inline `python3 -c` inside bash, and `\$` did not
   survive the quoting. — Recovery: the mutators' `assert count == 1` refused to apply, so no false result was
   recorded; I rewrote them as a raw-string script file. — **Prevention:** existing rule (assert the anchor; put
   mutators in a file, not `-c`).
4. **A guard-edit script had no `open(p, "w")`, so it changed nothing.** — Recovery: `git diff --quiet` showed
   the file unchanged. — **Prevention:** existing rule (a scripted edit that lands nothing looks like one that
   landed; check the artifact).
5. **The new scan check caught a real fail-open on its first run.** `git grep --no-index` refused probe paths
   outside the repo, and `|| true` folded that error into "0 hits". — Recovery: `scan_scorers()` now uses
   `grep -Hn` and reports a read error as UNRESOLVED, which fails the run. — **Prevention:** fixed inline; the
   non-vacuity probe drives the scan itself.
6. **The consumer regex `"[^"]*/lib/mutation-scorer\.sh"` missed source lines with nested quotes
   (`"$(cd "$(dirname …)")"`).** — Recovery: I listed the derived set before the first run and widened the regex
   to `.*`. — **Prevention:** one-off; list a derived set before trusting it.
7. **SC2059: the fixture helper passed a variable as the `printf` format.** — Recovery: `printf '%b'`.
   — **Prevention:** one-off; shellcheck ran before commit.
8. **The affected gate queued behind 4–6 sibling full-gate runs.** The first run had to be killed before
   review fixes could land, and its relaunch waited more than 30 minutes. — Recovery: re-ran every battery
   directly as a non-substitute check while the gate queued. — **Prevention:** existing (FIFO queue, capacity
   probe).
9. **The git-history seat raised a false P1.** It claimed `grep -cF -- >/dev/null "$x"` was a syntax error;
   bash lifts a redirection out of any position in a simple command. — Recovery: dismissed against the green
   batteries on `main`. — **Prevention:** one-off; check a reviewer's shell-syntax claim against the running
   code.
10. **The stop hook fired twice on "I'll…" closing text while waiting on agents.** — Recovery: explicit
    `<stop>BLOCKED: …</stop>`. — **Prevention:** one-off.
11. **`echo "launched at $(cat sha)"` printed empty.** The `&` backgrounded the whole `&&` chain, including the
    write. — Recovery: re-read after launch. — **Prevention:** one-off.
12. **Plan review cut the consumer-wire pin, the review measured it as the P1, and CONCUR DISSENTed on
    deferring it.** — Recovery: the probe seam and consumer suite were fixed inline. — **Prevention:** the plan
    sharp edge routed below.

## Tags

category: test-failures
module: apps/web-platform/infra
