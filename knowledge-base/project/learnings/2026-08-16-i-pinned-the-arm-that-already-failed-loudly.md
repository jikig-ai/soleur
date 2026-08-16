---
title: "I pinned the arm that already failed loudly, and left the one that goes silently green"
date: 2026-08-16
category: test-failures
module: apps/web-platform/infra
issue: 7565
pr: 7567
tags: [vacuous-guard, mutation-testing, supply-chain, dispatch-layer, review]
---

# I pinned the arm that already failed loudly, and left the one that goes silently green

## Problem

T5 in `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` is the git-data host's
supply-chain guard. It must prove that a wrong `DOPPLER_SHA256` aborts the doppler install chain
before `tar xzf` and `chmod +x /usr/local/bin/doppler` run as root on the host that stores users'
bare git repos. Both of its arms reported green with the checksum never evaluated.

The fix was straightforward and the fix was not the lesson. The lesson is what an 8-agent review
panel found in the *fix*: two structural holes and three false prose claims, all shipped in the
commit whose entire purpose was closing that defect class.

## Solution

### The bug

The primary arm asserted `rc == 1`, `"stage":"doppler_dl"`, `"level":"fatal"`, and the absence of
`CHMOD_RAN`. **All four are satisfied by the download failing.** With the release CDN unreachable
while apt still works, curl exits non-zero, `set -e` aborts into `on_err`, and `on_err` emits
exactly those markers and exits 1. Four green assertions, and the supply-chain property they are
named for was never evaluated.

No instrumentation was needed to fix it. `sha256sum -c -` writes its verdict to **stdout** — only
the `WARNING: 1 computed checksum did NOT match` summary goes to the stderr the shipped block
redirects into `$GIT_DATA_RUNCMD_DETAIL` inside the container — and `run_case` already captures
container stdout. The issue's own premise that the evidence "must be ADDED" was false, and the
`CURL_OK` marker it proposed is dominated by a strictly stronger signal later in the same chain.

The mutation arm's instrumentation was `;`-chained, so `chmod … ; echo CHMOD_RAN` printed the
marker after a failed curl, sha256sum, tar **and** chmod once the mutant stripped `set -e` — the
exact opposite of the reachability claim the arm exists to make.

### What review found in the fix

**1. A verdict that is a SUM is disarmed by one token.** `fail()` incremented a counter, `total =
passes + fails`, and the floor checked `total`. So `fail() { passes=$((passes + 1)); … }` — a
one-token bucket swap — disarmed every assertion in the file while the floor still saw its target,
accurate `FAIL:` text still printed, and the suite **exited 0**. Reproduced with three real
regressions injected: `47 passed, 0 failed`, `EXIT=0`.

The battery's own dispatch row could not see it, because it neutered `pass()` and `fail()`
*together* — so its RED was fully explained by the `pass()` half and said nothing about `fail()`.
The fix is an append-only ledger the verdict reads instead of a counter.

**2. The two arms are not interchangeable, and I pinned the wrong one.** I added a
mounted-artifact check to prove the instrumentation survived into the file the container actually
mounts. I put it on the **mutation** arm, whose `CHMOD_RAN` assertion is *positive*
(`if grep …; then pass; else fail`) and therefore already fails loudly on its own.

The **primary** arm's assertion is *negative* (`if grep …; then fail; else pass`). A marker lost
in transit makes it **pass vacuously** — the exact tautology class the PR existed to kill, on the
arm carrying the supply-chain property. Measured: strip the marker between `run_case`'s `cp`/`sed`
and the container, and the suite is `48 passed, 0 failed`, exit 0.

**3. An arm that never asserts its own premise is fail-open.** The mutation arm's whole story is
"a wrong digest was rejected and the chain continued anyway", and the `sed -i` making the digest
wrong had no landing assertion. A no-op sed meant the genuine checksum passed, the chain completed
legitimately, `CHMOD_RAN` printed, and the arm reported a cheerful pass having reproduced nothing.

### The three false claims I added

Each was written while holding the old bug in mind, and each is the defect class the PR closes:

- The anchor rationale claimed the old bare-token grep was "satisfied by the comment prose above
  it". **False** — the grep target is the *extracted block*, not the test source, and #7264
  extended ADR-152's strip to the template (measured: the rendered block has **zero** comment
  lines). The `;`-revert argument carries the point alone.
- The `docker run --rm` correction replaced a wrong number with another wrong number via a
  **self-polluting recipe**: `grep -c 'docker run --rm'` counts the comment that cites it, so it
  read 8 before the correction and 9 after. It is 6 source sites and 8 runtime invocations. The
  drift was never a miscount — it was **two measures sharing one number**, and neither the old
  text nor mine said which.
- The floor's leading itemisation is the **frozen 19-era baseline** that the #7204 stanza checks
  "19 pre-existing" against. I updated it to reflect the new assertion, making `20 + 14 = 34`
  against a stated 33 for anyone doing what that stanza explicitly invites ("check the sum rather
  than trust it").

## Key Insight

**Ask of a guard's every assertion whether its failure direction is loud or silent, and pin the
silent one.** A positive assertion (`if present then pass else fail`) self-reports when its
evidence disappears. A negative assertion (`if present then fail else pass`) reports *success*
when its evidence disappears — it cannot distinguish "the bad thing did not happen" from "the
detector is gone". Guard-hardening effort naturally flows to the arm you were just looking at,
which is usually the loud one, because that is the arm that has been failing at you.

**And a verdict computed as a sum has one-token vacuity.** Any `exit $(( counter > 0 ))` where the
counter is incremented by the same helper that reports failures can be silenced by redirecting the
increment. The floor does not help: it sums the same buckets. Make the verdict read something
append-only, so silencing it requires deleting evidence rather than moving a number.

**Corollary for the reviewer:** when a PR arrives carrying its own green mutation battery,
enumerate the **axes** it edits, not the count it reports. This battery ran 16 rows and had
essentially two axes; the panel found five it never touched — dispatch-half asymmetry, fixture
direction on the mutation arm, population growth by a *new* member (a second pinned binary yields
5/5 green with its checksum unevaluated), which-arm-was-pinned, and observation-grep anchoring.

## Prevention

- A review-driven fix ships **exactly as unpinned as the blind spot it closed** — nothing forces
  coverage for code written after the tests. Mutate each one back out on a scratch copy. Ours:
  the ledger, the primary pin, the premise assertion, and the path derivation each drive RED
  (`r1b`, `r2`/`r2b`, `r3`, `r4`), and one row (`r1`) is recorded as **proving nothing** because
  its description claimed an injected regression the mutation never made.
- Derive literals from the artifact under test. The tarball path is now read out of the extracted
  block rather than hard-coded, so a rename in the shipped cloud-init cannot red the guard with a
  false diagnosis.
- When a comment states a general rule, grep the same file for every other instance of that rule's
  precondition — the rule is usually right and its application usually incomplete.

## Session Errors

1. **CWD drift silently redirected relative paths.** An earlier `cd apps/web-platform/infra` made
   a later `grep apps/web-platform/infra/...` fail with `No such file or directory`.
   **Prevention:** chain `cd <worktree-abs> && <cmd>` in one call; never rely on ambient CWD.
2. **`local a="$1" b="$OUT/$a.log"` aborted under `set -u`** with `id: unbound variable`.
   **Prevention:** split `local` declarations when a later one references an earlier one.
3. **The H1 mutation was malformed** (unbalanced brace) and died with a bash syntax error, rc=2.
   Non-zero is not the floor firing — the run never reached `total=$((passes + fails))`.
   **Prevention:** assert the mutant is still a *working, weaker* program; `rc != 0` is not
   attribution.
4. **The plan's Guard-1 row 2 was falsified on execution.** It transplanted probe cell (d) — a
   *mutant-path* observation — onto the errexit-armed primary arm, where a blocked CDN aborts at
   curl before sha256sum runs, so `FAILED open or read` occurs **zero** times.
   **Prevention:** a probe cell's label names its configuration; check it matches the arm.
5. **A stale `origin/main` diffstat listed five files I never touched**, nearly read as a scope
   breach. **Prevention:** `git fetch origin main` then three-dot `origin/main...HEAD`.
6. **Three false prose claims shipped** (above). **Prevention:** for every causal or universal
   sentence the diff ADDS, name the falsifying command and run it before writing it.
7. **The dispatch vacuity and the wrong-arm pin** shipped in a PR about vacuity.
   **Prevention:** the review panel; recorded as skill routing below.
8. **Mutation row `r1` was mislabelled**, claiming an injected regression it never made.
   **Prevention:** a row that measures nothing looks exactly like a row that passed — state which.
9. **Forwarded from `session-state.md`:** the plan's first revision built a CDN-decline apparatus
   on an unprobed causal story (cut in full); `deepen-plan` halt 4.6 failed on first run; two
   enumerations offered as exhaustive were wrong; the plan panel did not spawn `spec-flow-analyzer`
   or `cto`.

## Recurring-vs-One-Off Triage

| Item | Recurring? | Disposition |
|---|---|---|
| Verdict-as-a-sum vacuity | recurring | **fix-now-inline** — done (append-only ledger) |
| Negative assertion left unpinned | recurring | **fix-now-inline** — done; routed to `review/SKILL.md` |
| Arm not asserting its own premise | recurring | **fix-now-inline** — done |
| Self-polluting `grep -c` in a comment that cites it | recurring | routed to `review/SKILL.md` |
| Frozen historical ledger edited as if current | recurring | labelled in-file so the next author cannot repeat it |
| CWD drift | recurring | already documented in `work/SKILL.md`; no new rule |
| `local` multi-assignment under `set -u` | one-off | noted only |
| Malformed mutation / mislabelled row | recurring | routed to `review/SKILL.md` (axes, not counts) |
| Stale `origin/main` diffstat | recurring | already documented; no new rule |

## Related

- `knowledge-base/project/specs/archive/20260816-203735-feat-one-shot-7565-t5-checksum-never-evaluated/mutation-transcript.md`
  — both batteries, including the rows that did not hold
- `knowledge-base/project/specs/archive/20260816-203735-feat-one-shot-7565-t5-checksum-never-evaluated/decision-challenges.md`
- #7291 / draft PR 7510 — the apt-keyed sibling; probes (e)/(f)/(g) contributed there
- #7570 — pre-existing `set -u` / unset-`CAPTURE` hazard in D1, tracked not fixed
