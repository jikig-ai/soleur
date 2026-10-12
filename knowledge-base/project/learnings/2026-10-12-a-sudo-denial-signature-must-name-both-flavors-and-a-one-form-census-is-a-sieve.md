# Learning: a sudo-denial signature must name both flavors, and a one-form census is a sieve

Issue: #10045 | PR: #10063 | spec: `knowledge-base/project/specs/feat-one-shot-10045-kdeny-least-priv/`

## Problem

Three convergent review-panel findings on a least-privilege sudoers grant for the
`deploy` user (`kdeny` kernel-stream read):

1. **The fallback was dead on GNU-sudo hosts.** The reader discriminated "grant
   absent" from "tool failure" by matching `^sudo:`-prefixed output. The fleet's
   recorded denial body — `sudo: deploy : command not allowed` — is the sudo-rs
   shape, but GNU sudo denies with an unprefixed `Sorry, user … is not allowed to
   execute …` body. On a GNU host the grant-less path would emit `j=error` — the
   new failure class the plan explicitly forbade — and the suite had stayed green
   because the mock pinned `sudo: a password is required`, a third (auth-required)
   subclass that also happened to carry `sudo:`.

2. **"No other journalctl grant exists" was proven only against one grant syntax.**
   The Guard-1 census counted `Cmnd_Alias … = … journalctl` lines. A direct
   `deploy ALL=… journalctl` grant, a space-less `Alias=…`, a command appended to
   the grant line, or an `@include` pulling a second file all evaded it — every
   evasion is valid sudoers.

3. **A captured-stream strip shipped with no fixture.** `grep -v '^sudo:'` (added
   so an accepted run's `sudo: unable to resolve host` warning can't count as a
   journal line) could be deleted with the whole suite green; and `grep -F`-style
   per-line exclusions let a second read smuggled onto the compliant line evade
   the source census.

## Solution

- Denial signature now requires three things together: `rc≠0`, ≥1 recognized
  denial phrase (`Sorry,`/`command not allowed`/`password is required`/`not
  allowed to execute`/`may not run`/`is not in the sudoers file`), and every
  non-blank line `sudo:`- or `Sorry,`-prefixed. The phrase requirement kills the
  warning-masquerade edge (accepted run + warning + silent tool failure would
  otherwise read as denial).
- Mock pins both **recorded** bodies (`MOCK_SUDO_DENY=rs` = the fleet-observed
  sudo-rs emission from the 2026-05-20 learning; `=gnu` = the sibling suite's
  `Sorry,` model); unknown values exit 70, so a stale `=1` fails loud.
- Guard-1 now asserts totality by **token mention** (comment-stripped
  `grep -cF journalctl == 1` over the whole file), anchored `grep -qxF` grant
  lines on both surfaces, and a whitespace-tolerant `[@#]include` absence.
- Source census rewritten strip-first: erase the pinned literal per-occurrence,
  then any *remaining* `journalctl`/`dmesg` token must be a conforming rung —
  smuggle and suffix fixtures pin the two shapes that survived before.
- `MOCK_SUDO_WARN=1` fixtures prove the strip (empty stays `empty`) and the
  phrase requirement (warning + silent failure → `j=error`, no fallback).
- `CI_DEPLOY_ASSERT_FLOOR` ratcheted to the measured 618 with a ledger line —
  the prior floor was stale by the whole new battery.

## Key Insight

- **Fixture fidelity is the silent failure shape of a negative contract.** A
  fallback that fires only on denial shape A is invisible to a suite whose mock
  only emits shape A — the green run proves the mechanism, not the fleet.
  Provenance-pinned fixtures (cite the recorded emission AND the sibling model)
  are the only honest arm.
- **A negative assertion ("no other grant") proven by enumerating one positive
  form is a sieve.** Census the token, anchor the whole line, and ban the
  indirection (`include`) that outsources the set.
- **Every line that changes a classifier needs a fixture that fails without it.**
  The strip, the phrase gate, the suffix residual — each was load-bearing and
  each stayed green when deleted until a fixture pinned it. Single-rule fixtures
  ("deleting any one ban leaves exactly one unflagged row") are the discipline
  that keeps that honest.

## Session Errors

1. **Agent 2 (tests) killed by free-model rate limit mid-flight** — Recovery:
   kept the partial well-formed edits, finished Tier-C sequentially — Prevention:
   none (pipeline already handles; transient).
2. **All 8 review seats died at spawn on the same rate limit** — Recovery: waited
   out the reset, resumed in batches, full 8/8 coverage — Prevention: none
   (transient; the retry-before-fallback discipline is already the rule).
3. **`git stash list` hook-blocked in worktree** — Recovery: ran the command
   without the stash probe — Prevention: hard rule already exists and the hook
   caught it; recorded for the incident ledger.
4. **`nvim` spawned mid-rebase by `$EDITOR`, hung the non-TTY shell** — Recovery:
   killed the editor, redid `rebase --continue` with `GIT_EDITOR=true` —
   Prevention: pass `GIT_EDITOR=true` on all rebase/merge `--continue` calls in
   non-interactive shells.
5. **`sed 's/[][.*^$\\/]/\\&/g'` regex-escape broke at runtime** (GNU sed rejects
   `^` inside that class position) — Recovery: switched to brute
   `s/[^[:alnum:] ]/\\&/g` (BRE-benign constraint recorded in comment) —
   Prevention: the suite caught it instantly; fixture-run before commit.
6. **`git merge-tree`/`gh pr view` reported PR CONFLICTING mid-panel** —
   Recovery: rebased onto new `origin/main`, resolved, force-pushed, re-verified
   mergeable before spawning seats — Prevention: the pre-panel mergeability gate
   already exists and fired correctly.
7. **Stale `CI_DEPLOY_ASSERT_FLOOR` and unfixtured strip found by the fix-round
   seats** — Recovery: ratcheted floor to measured 618; added MOCK_SUDO_WARN +
   D10k6/k7 — Prevention: the ratchet convention is now the ledger comment; the
   "fixture for every load-bearing line" principle is this document's insight 3.

## Tags

category: bug-fix
module: apps/web-platform/infra (ci-deploy.sh, cloud-init.yml, server.tf, sudoers)
severity: P1-cluster (dead fallback + census totality gap)
