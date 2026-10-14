# Every defect was a guard that could not fail, and no instrument found more than two

**Date:** 2026-08-14
**PR:** #7538 (22 commits) — closes #7429, #7402, #7523; filed #7537, #7545, #7554; closed #6965 as verified-stale
**Category:** test-failures / workflow-patterns

## Problem

A PR whose entire subject is "make a terminated suite distinguishable from a failed one" shipped, at various points, **nine guards that could not fail**. Seven were written by this PR. Two were pre-existing and only became visible because the PR made them load-bearing.

The uncomfortable part is not the count. It is that the session applied every discipline the repo prescribes — RED-first, a 19-row mutation battery, a 17-row battery, three independent agent verifications, a 6-agent review panel — and each discipline was individually insufficient.

## The nine

| # | Guard | Why it could not fail | Found by |
| --- | --- | --- | --- |
| 1 | A6 tripwire | placed where a real signal and `exit 137` are byte-identical (`rc=$?` 137, `xargs` 0); the distinction exists only at the shim (125 vs 123) | plan review |
| 2 | `[[ -n "$name" ]]` in both classifiers | unreachable-as-decider: `kill -l 65` exits 1, so the preceding branch already rejects 193–255 | mutation |
| 3 | `lint-orphan-test-suites.sh` → `--print-suite-globs` | 900 s deadlock on the advisory lock its own PARENT holds (it runs as a registered suite inside `test-all.sh`) | running the gate |
| 4 | same invocation | inherited `TEST_GROUP` from the shard → ran the whole shard **recursively**; P0, reproduces in CI | running the gate |
| 5 | `T10d` (AC3) | asserted only `rc == 1`, and exit 1 is a bucket shared by `failed>0` and `UNACCOUNTED>0` — passed with the kill classifier fully neutered | **shellcheck** |
| 6 | `suite-exit-class-parity.test.sh` | asserted the three classifiers **agree**, never what they must agree **on** — collapsing all three to "never signal-shaped" passed 35/0 | mutation (resumed agent) |
| 7 | three suites' dispatch | rewriting `fail()` to increment `PASS` left each fully green; an assertion-count floor cannot see it either, because a rewritten `fail()` still counts | mutation (resumed agent) |
| 8 | producer floor `MIN_TRACKED_SUITES=250` | 92 slack: dropping all 43 `.claude/**` suites still enumerates 299, clears the floor, and prints `0 orphaned` | security review |
| 9 | disjointness | **asserted in prose**, enforced only inside the synthetic battery, never against the live repo — which carried five violations | CONCUR gate |

## Key insight 1 — three instruments, disjoint yields

No single technique found more than two:

- **Mutation** found #2, #6, #7.
- **Running the thing for real** found #3, #4 — both invisible standalone.
- **`shellcheck -S warning`, in seconds**, found #5 via an *unused variable*.
- **Review panel** found #8, #9.

A PR that runs only one of these ships the others' defects. The cheapest instrument found the highest-severity assertion defect, which is the opposite of the intuition that expensive panels catch what lints cannot.

## Key insight 2 — a guard's green run can be the concealment mechanism

#4 is the sharpest. The recursion did **not** reproduce standalone, because standalone leaves `TEST_GROUP` unset and the mutant then exits 2 in milliseconds. It only reproduces inside `test-all.sh`, which exports `TEST_GROUP=<shard>`.

So the suite's own passing run was the thing hiding it. A 17-row battery, three agent verifications and a hand re-drive of the highest-value row all missed it, and none of them was careless — they were all run in the environment where the defect is *absent by construction*.

> **Rule:** run every suite under the environment it ships into — `CI=1`, `SOLEUR_SUBAGENT=1`, `TEST_GROUP=<shard>` — and treat any PASS-count change between environments as a finding, not noise.

## Key insight 3 — agreement is not correctness

An N-way consistency check that asserts only *agreement* is a tautology in the accept direction: N uniformly-broken implementations satisfy it perfectly. It needs an expected-value column derived from the **spec**, never from any implementation's output.

Measured: `35 passed, 0 failed` with all three classifiers collapsed → `49 passed, 7 failed` after adding taxonomy-derived expectations.

## Key insight 4 — the instrument lies more often than the code

**Seven** measurements taken to check this work were wrong, and **every one failed in the reassuring direction**:

1. A mutation that did not land — reported the baseline, indistinguishable from a pass. (Caught by `assert count==1`.)
2. A sandbox copied to `/tmp` — failed with `fatal: not a git repository`, which read as "the mutant reddened." A red baseline voids every row.
3. `wc -l` on `--list` counted its own header line → a wrong 99 where 98 was right; nearly shipped into three artifacts.
4. `$?` evaluated after `$(basename …)` captured basename's exit, reporting a red suite as `rc=0`.
5. An expected-set written from memory (`tests`) rather than derived — the check reddened on its own first run.
6. `pgrep -f 'lint-orphan'` matched its own command line and killed the invoking shell (exit 144).
7. A freshly-filed issue whose re-evaluation trigger said 8 where it measured 12.

> **Rule:** run the unmutated control FIRST and require it GREEN; assert the mutation LANDED against a pristine copy; and give every measurement a known-positive and known-negative arm before reading its verdict.

## Key insight 5 — a correction must be swept by CLAIM, not by FILE

ADR-187's inlining rationale was falsifiable (a `$ROOT`-anchored source *would* survive the single-file `cp`; the binding constraint is the python single-file **mutator**). It was corrected in the ADR — and left standing in all three in-repo copies, **one commit later, inside a PR about stale claims**.

A file-indexed sweep is bounded by the diff's file list. The unit of truth is the proposition.

## Solution

Each guard was fixed at the layer where it could actually fail, and every fix was mutation-proven:

- A6 tripwire moved to the shim (125 vs 123).
- Name-guard: added rc **160/161** to the parity domain — where `kill -l 32/33` returns rc 0 with EMPTY output, so the guard decides **natively** on this shell. (The synthesized permissive-shell arm added earlier was reaching for a property this shell exhibits two values away.)
- Lock deadlock: `SOLEUR_DISABLE_SESSION_STATE=1` on a read-only metadata query. Battery: blocked → 15 s.
- Recursion: `env -u TEST_GROUP`, pinned by new row R1.
- `T10d`: split into dominance (`rc`) and detection (the breakdown line). The rc half was never wrong, only insufficient — replacing it would have lost a real check.
- Parity: expected-value column + accounting reconciling `RC_EXPECT` against `RC_DOMAIN`.
- Dispatch: ported `run-registered-suites.test.sh`'s positive control into the three suites lacking it.
- Producer: floor 250 → 320 **plus** a root-SET assertion — a count cannot see a narrowing that stays above it, nor a substitution at all.
- Disjointness: live assertion with a five-entry ack list; prose corrected to say what is true.

## Prevention

- **`shellcheck -S warning` before the panel, on every bash-only diff.** `SC2034` (unused variable) is a reliable tell for a captured-but-unasserted verdict.
- **Run each suite under `CI=1`, `SOLEUR_SUBAGENT=1`, and each `TEST_GROUP` value**; a PASS-count delta across environments is a finding.
- **For any N-way consistency check, add expected values from the spec.** Litmus: *can all N be wrong and still agree?*
- **Give every assertion helper a positive control** that calls `pass()` and `fail()` once and verifies both counters moved. An assertion-count floor does not cover this.
- **Prefer a SET assertion over a COUNT** for any all-members invariant. Slack in a floor is narrowing budget.
- **Sweep corrections by claim.** After correcting any rationale, `git grep` the OLD wording repo-wide.

## Session Errors

1. **Planning subagent died on an API session limit mid-correction.** Recovery: resumed from transcript against an unmodified checkpoint commit. Prevention: commit recovered artifacts BEFORE resuming, so corrections are reviewable as a diff.
2. **The plan's Phase A0 stated the opposite of the truth** — its probe grepped `cp .*TARGET|SUT=|mktemp -d`, which cannot match `cp "$SUT"`. Prevention: when a probe returns a negative, verify the pattern *can* match a known positive.
3. **Three premises were falsified before implementation** (npm propagates 137/143/130; #7402's orphan list was 5/7 stale after a security PR relocated the suites). Prevention: re-derive every issue-stated premise at work-start; issues age badly.
4. **Launched two concurrent full shards onto a box already running two.** Prevention: #7545.
5. **Wrapped a ~40-min gate in a 60-min Monitor**, whose timeout reaped it. Prevention: detach with `setsid nohup`, use a SHORT waiter.
6. **`cd ""` succeeded into `$HOME`**, making a `|| cd <absolute>` fallback unreachable → `rc=127`. Prevention: shell variables do not persist across Bash calls; use absolute paths, and never rely on `cd` failing.
7. **Counted PIDs as runs** — the exact error `tc_preamble` documents avoiding.
8. **Ended a turn on "continuing to /qa" without invoking it.** Prevention: a forward-looking sentence is not a handoff.
9. **Mis-claimed a scope-out criterion**; the CONCUR gate refused it and was right on every count.
10. Plus the seven broken measurements in Key insight 4.

## Tags

category: test-failures
module: test-all, lint-orphan-test-suites, run-registered-suites
