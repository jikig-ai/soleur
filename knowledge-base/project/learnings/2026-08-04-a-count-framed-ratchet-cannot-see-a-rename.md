---
title: A count-framed ratchet cannot see a rename when the guarded quantity is a set
date: 2026-08-04
category: engineering
tags: [ratchet, drift-guard, terraform, for_each, doppler, mutation-testing, vacuity]
module: System
component: ci_cd
problem_type: logic_error
resolution_type: guard_added
root_cause: wrong_invariant
severity: high
---

# Learning: a count-framed ratchet cannot see a rename

## Problem

The token-drift coverage ratchet had four layers, and a config **rename** passed all four
while silently removing a config from the scan's reach.

Since #7234 the name lines in `apps/web-platform/infra/doppler-config-inventory.txt` are the
`for_each` key set for `doppler_service_token.token_drift`. So the scan's REACH is that set of
names. Every guard, however, bounded a **count**:

| Layer | What it asserts |
|---|---|
| F2 | `DOPPLER_CONFIGS_FLOOR >= 13` |
| F2b | floor `==` inventory count, and `<=` minimum + headroom |
| F3 | floor `==` deduped inventory name count |
| run-time | `(( 10#$cfg_floor < 13 ))` re-assertion in the workflow |

Swap `prd_cla` for `prd_cla_v2` and the count never moves. F2b's equality holds, F3 holds,
F5's derived list still has 13 names, the run-time assertion holds — and the scan reports a
clean `13/13` while one config goes permanently unread and a token is minted for a config that
does not exist.

## Key insight

**When a guard protects a resource, ask whether what matters is the CARDINALITY or the
IDENTITY of what it covers.** If reach is a set, a count-framed ratchet is structurally blind
to the whole permutation class, and no amount of tightening the counts fixes it — the counts
are measuring the wrong thing. Tightening them feels like progress because each individual
assertion gets stricter, which is what makes the gap durable.

## Solution

`F4b` in `plugins/soleur/test/token-drift-workflow-causes.test.sh` asserts the inventory's
name set is a **superset** of the same file's at the merge base. Pre-merge, no credential, no
network call.

Design points that mattered:

- **Baseline is the MERGE BASE, not `origin/main`'s tip.** Against the tip, every branch that
  has not rebased past a legitimate inventory GROWTH reds for a shrink it did not make.
  Against the merge base a stale branch compares to the tree it forked from, and CI — which
  builds the PR's merge commit — still gets merged-result-vs-main.
- **A deliberate retirement is an ack, not an exemption.** `INVENTORY_REMOVALS_ACK=()` is
  empty by default; naming a config there is an edit to a test whose only purpose is to stop
  that edit, the same discipline as `FLOOR_MINIMUM`. A stale entry is inert rather than an
  error, because making it an error would red main for everyone the moment the removal merged.
- **Fail closed on an unreachable baseline.** A ratchet that quietly disappears when its
  baseline cannot be resolved is the shape that lets the shrink through on exactly the runner
  where nobody is looking.

## Mutation results

Each re-verified against a pristine baseline:

| Mutation | Result |
|---|---|
| rename a config, count unchanged | F4b reds — the only failure |
| coordinated 13→12 shrink moving all three pinned literals together | F4b reds; **60/61** — every count-framed layer passes |
| delete the comparison loop | reds, via the loop's own accounting guard (see below) |
| baseline unreachable | reds — fail-closed, not skipped |
| retire a config via `INVENTORY_REMOVALS_ACK` | passes: 12 compared, 1 acked |

The 13→12 row is the proof that matters: it is the exact "lower every literal together"
manoeuvre the inventory header describes as undetectable, and F4b is the only layer that sees
it.

## The bypass the prose leaned on

Both the inventory header and ADR-164 named the apply's destroy guard as *the only layer that
fires above 13* and leaned on it. It does not hold: `destroy-guard-filter-web-platform.jq`
counts planned deletes **inside** the `[ack-destroy]`-bypassable `destroy_count` sum — and the
same file's own comments record why `host_creates` and `reboot_updates` were deliberately
placed OUTSIDE that sum. A PR carrying that ack for an unrelated reason waves the token
deletes through with it, and #7234's own merge commit is exactly such a PR. It also has no
`for_each` instance-delete case among its 40 tfplan fixtures.

**Generalisable:** when prose names a control as load-bearing, check whether that control sits
inside a bypass the same file documents. Here the bypass was written down, in the file being
cited, and nobody re-read it while citing the control.

## An anti-vacuity floor counts assertion CALLS, not BODIES

Deleting F4b's entire comparison loop left the suite reporting **61/61 and exit 0**. The floor
at the foot of the file counts `PASS + FAIL`, and a gutted control still calls `pass()`. So the
one mechanism guarding against deleted assertions cannot see a NEUTERED one.

Fix: the loop counts what it examined and reconciles that against the baseline name count, so a
body that stops iterating fails as loudly as one that finds a defect.

**Habit worth keeping: after writing any guard, delete its body and confirm the suite reds.**
Reading the guard is not sufficient — this one was written by someone who knew the vacuity
class and still shipped it.

## A review finding names a defect; it only PROPOSES a mechanism

"Pin the Doppler CLI via a `version:` input" was measured impossible. `DopplerHQ/cli-action` at
the pinned SHA declares **no inputs at all** (`action.yml` has no `inputs:` block) and on Linux
shells out to `cli.doppler.com/install.sh`, which installs latest. An unknown input is silently
ignored by Actions, so adopting the proposal would have bought a **false pin** — strictly worse
than the honest un-pinned state, because it reads as solved.

The measurement also re-framed the severity: the CONTROL is that a config-scoped token's read
FAILS on a wrong `-c`, which is server-side and version-independent. Only the cause LABEL
matches the CLI's message string. A reword degrades a mis-binding to
`token_drift_identify_unreachable` — less specific remedy, gate still fires. Diagnostic-quality
risk, not correctness.

**Rule: a review finding's defect is trustworthy; its proposed mechanism is a hypothesis.**

## `terraform -target` selects dependencies, never dependents

A bare `terraform apply -replace=<addr>` plans the WHOLE ROOT. The obvious correction — add
`-target=<the token>` — is *worse*: `github_actions_secret.doppler_token_drift_map` reads
`doppler_service_token.token_drift[*].key`, so it is a **dependent** and gets pruned from the
plan. That apply mints a new token, destroys the old one, and leaves the published map holding
the destroyed value; every consumer then authenticates with a revoked credential.

When `-target`ing a resource whose value is PUBLISHED somewhere, target the publisher too.

## Honest disclosure can trip the guard that forbids the thing disclosed

`lint-infra-no-human-steps` flagged the paragraph disclosing that rotation has no dispatch
route — correctly, on its own terms ("actor + terraform imperative co-occur"). The wrong
response is to reword until it passes: that hides the finding the paragraph exists to record.
The right one is the sanctioned `lint-infra-ignore` region, a tracking issue (#7263), and a
comment saying when to remove the region.

## Bash traps hit while writing the fix — all caught by RUNNING, not reading

- **A second `trap … EXIT` REPLACES the first.** Added one to a file whose own comments forbid
  exactly that (ADR-129 / lint-trap-tempfile-ownership rule (c)); it would have disarmed the
  owning trap and leaked its temp file. Fixed by reusing the already-owned file.
- **`$(( arr[key] ))` evaluates the subscript ARITHMETICALLY.** A string key resolves as an
  undefined variable to 0, so every lookup reads index 0. Symptom: the annotation printed
  `0 failed read(s)` beside `…mismatch=1`. Use `$(( ${arr[$key]} ))`.
- **Helper placement vs early-exit paths.** Declaring the accumulator after the
  unparseable-floor `exit 2` path made `emit_json` hit an unbound variable under `set -u`,
  failing a test that had nothing to do with the change.

## On resume, `session-state.md` `### Decisions` are INTENT — and can be falsified

Two entries in this feature's `session-state.md` were false by the time it was read:

- *"A service token ignores `-c`"* — Phase 0 measured that a config-scoped token **errors** on
  a wrong `-c`. That error is the binding control the whole scan rests on; the file recording
  the decision still carried the pre-measurement belief.
- *"leaving the destroy guard as the only above-13 layer"* — falsified by this session's F4b.

Its `sort -u` line citation (`:569`) had also drifted to `:992` (`cq-cite-content-anchor-not-line-number`).

## Cross-cutting: the frozen-baseline trap merged anyway

`infra-config-apply.test.sh` proves the #7220 fix by running the "pre-fix" handler obtained via
`git show origin/main:apps/web-platform/infra/infra-config-apply.sh`. #7221 merged that fix to
main, so the baseline now HAS the behaviour the assertions require it to lack. It surfaced
independently in CI (`deploy-script-tests`) and in the local exit gate's nested infra runner
(87 PASS, 1 RED) — filed as #7265.

This is exactly the class already documented in
`test-failures/2026-07-05-parity-baseline-must-not-be-git-show-main-of-the-replaced-file.md`,
and #5987 hit the identical shape and was caught at review. **The learning existed and did not
prevent it** — which is an argument for a mechanical check (grep for
`git show origin/main:<a path the diff also modifies>` in `*.test.sh`) rather than another
prose rule.

## Session Errors

1. **Shipped F4b with a neuterable body** — deleting the comparison loop left the suite at
   61/61 and exit 0. **Recovery:** added loop accounting reconciling examined-vs-baseline
   counts. **Prevention:** after writing any guard, delete its body and confirm the suite reds;
   an anti-vacuity floor cannot substitute for this.
2. **F4b's pass message overstated its own scope** — "all N config names survive" was false
   whenever a config was acked. **Recovery:** report compared and acked counts separately.
   **Prevention:** exercise the exemption path, not just the happy path; a pass line that
   overstates is the same defect class this PR spent its time correcting elsewhere.
3. **Introduced a second `trap … EXIT`** into a file forbidding it. **Recovery:** reused the
   already-owned temp file. **Prevention:** grep the file for an existing `trap … EXIT` before
   adding one; `trap` replaces, it does not append.
4. **`$(( _total + READ_CAUSE_COUNT[_c] ))`** made the cause name resolve to 0. **Recovery:**
   `${READ_CAUSE_COUNT[$_c]}`, expanded before the arithmetic. **Prevention:** run the code
   path and read its output — this was invisible to inspection and to a 91/91 suite.
5. **Accumulator declared after an early-exit path** → unbound variable under `set -u` on the
   unparseable-floor test (90/91). **Recovery:** hoisted above `emit_json`. **Prevention:**
   when adding state consumed by a function called on error paths, declare it above the
   earliest caller, not above the main-path caller.
6. **Own disclosure tripped `lint-infra-no-human-steps`**, reddening CI. **Recovery:**
   `lint-infra-ignore` region + #7263. **Prevention:** when documenting an automation gap in an
   infra-scoped file, expect the no-human-steps linter to fire and reach for the ignore region
   rather than softening the words.
7. **Literal em-dash in a `git commit -F -` heredoc** where the text needed to name the escape
   sequence, producing "em-dash as —". **Recovery:** amended via `--file`. **Prevention:** when
   a commit message is *about* an encoding, write the body to a file first.
8. **`session-state.md` `### Decisions` carried two falsified claims and a stale line
   citation.** **Recovery:** verified each against the live tree before relying on it.
   **Prevention:** the resume gate already says Decisions are intent — extend it to "and may
   have been falsified by a later measurement inside the same feature."
9. *(forwarded)* Scratch tmpfs filled to 100%; one bash call lost its output.
10. *(forwarded)* Three plan claims about real code were false, caught pre-ship.
11. *(forwarded)* The plan's consumer sweep undercounted twice.
