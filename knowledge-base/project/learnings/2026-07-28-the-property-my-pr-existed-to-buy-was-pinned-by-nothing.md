---
date: 2026-07-28
category: test-failures
module: apps/web-platform/infra
issue: 6665
pr: 7020
tags: [mutation-testing, guard-building-pr, adr-139, test-harness, vacuous-green, path-mock]
---

# The property my PR existed to buy was pinned by nothing, and the guard I added to make that safe could not guard it

## Problem

#6665 inverted a test harness's no-op `sleep` mock from opt-in to default, cutting the
CI step from ~407 s to ~23 s, and lowered the job ceiling 12 → 8 minutes in the same
PR. Local suite green (184/184), CI green three times, `shellcheck` clean, and the
one mutation I ran (production backoff `"2 4"` → `"9 9"`) went correctly RED.

Six review agents then found that **the central property was pinned by zero
assertions.** Adding one conjunct to the install condition —

```bash
if [[ "${MOCK_SLEEP_REAL:-}" != "1" ]] && [[ -n "${MOCK_SLEEP_LOG:-}" ]]; then …
```

— which is *literally the opt-in shape the PR set out to replace, and reads as an
ordinary "scope the mock to the tests that need it" cleanup — left the suite green
with a **byte-identical PASS name-set** at **9m17s**: all the way back to pre-PR wall
clock. Because the same PR removed the 12-minute ceiling that had been absorbing that
regression, it would have surfaced only as an intermittent `deploy-script-tests`
cancellation with no red test anywhere naming the cause.

## Key Insight

**The test closest to the mechanism is often the one immunized from it.** T-6525-8 is
the only test that touches the sleep mock, so it looks like the natural canary. It
sets `MOCK_SLEEP_LOG`, so under the mutation above it *keeps* its mock and stays
green — it is structurally incapable of being the canary. When asking "what pins this
property?", the answer is never "the test nearest to it"; it is "the test whose
fixture would change if the property flipped." Here nothing satisfied that, and the
fix was to assert the **factory** directly (default ON / opt-out suppresses /
recorder reinstates) with no runner and no wall clock.

## Solution

Four classes, all found post-implementation, all in code I wrote:

### 1. A guard-building PR fails open *in the guard*, and attributes itself wrongly

The PR added a ~500-invocation cap inside the mock and a comment naming two
properties the cap "backstops". It backstops **neither**:

- a real `seq 1 10` over the canary loop's 5 sleep sites yields ~40 invocations
  across the whole script — a *fraction* of the cap, so it never fires;
- a bypassed `sleep` never reaches the mock, so it cannot be counted by it.

The class the cap *does* guard went unnamed: `ci-deploy.sh` › the cron-drain
`while cron_in_flight` loop, which exits on `CRON_DRAIN_TIMEOUT` (default **4200**)
— a 70-minute 100%-CPU spin under a no-op `sleep`.

Ask of any guard: *name the input that reaches this guard and the input that
doesn't.* Both prose-only properties are now pinned by source assertions instead,
which is what ADR-139 asks for — the PR had cited ADR-139 *as* the earning while
leaving the residual unearned on a reachable surface, the case ADR-139 declines.

### 2. The correction carried its own false claim

The tripwire said `/bin/sleep`, `command sleep` and `exec sleep` all escape the PATH
mock. Measured:

```
sleep 0.01          -> MOCK-HIT
command sleep 0.01  -> MOCK-HIT
exec sleep 0.01     -> MOCK-HIT
env sleep 0.01      -> MOCK-HIT
/bin/sleep 0.01     -> escaped
```

`command` and `exec` bypass *functions and aliases*, not `PATH`. So the guard I wrote
banned two harmless forms while missing `/usr/local/bin/sleep`. Re-anchored on "any
absolute path ending in `/sleep`", with a both-directions control (3 absolute forms
caught, 4 harmless forms ignored).

### 3. `$(<file) 2>/dev/null` does not suppress

```bash
_n=$(<"$f") 2>/dev/null || _n=0        # prints "No such file or directory"
{ _n=$(<"$f"); } 2>/dev/null || _n=0   # silent
```

For a simple command that is **only assignments**, bash expands the right-hand side
*before* applying the redirection. The committed `cat` form it replaced was correct;
the "optimization" reintroduced noise into a `2>&1`-captured runner log. Two agents
found this independently.

### 4. A guard's diagnostic must survive the call site, not just be written

The cap wrote `MOCK_SLEEP_CAP_EXCEEDED` to its own stderr. But the runner merges the
deploy's stderr into the subshell's stdout, **18 call sites** close with
`>/dev/null 2>&1`, and `$MOCK_DIR` — holding the counter — is removed by the runner's
own `EXIT` trap. Zero residue. The cap fired and the operator saw a bare assertion
failure naming a different cause. Fixed with a marker file *outside* `$MOCK_DIR`,
reported adjacent to the results line.

## Prevention

- **For any PR whose thesis is "X now happens by default", write the assertion that
  fails when X stops happening — before anything else.** Assert the factory/switch
  directly, not a downstream effect. Litmus: *name the one-conjunct edit a reasonable
  engineer might make next; does a test go red?*
- **Run the mutation battery's CONTROL arm under the non-default mode too.** Here the
  control run under `MOCK_SLEEP_REAL=1` exposed that the new cap test had the *same*
  self-sufficiency gap the PR had just fixed in T-6525-8 — it red-failed for a missing
  mock rather than a real regression. No mutation could have found that; only the
  control, run in the mode nobody runs by default.
- **A red baseline voids the battery.** The first sandbox came back 179/186 (7
  environment artifacts from copying one directory out of the repo). Results were
  salvaged only by comparing **per-case verdicts** instead of totals.
- **`ABSENT` is not `PASS`.** The battery's own `verdict()` helper grepped the PASS
  text to classify FAIL lines, which do not share it — four real catches were reported
  as `ABSENT`. Verify the *instrument* before reading its output.

## Session Errors

1. **Plan claimed 17 `sleep` sites; the bare grep reads 16** — and blamed the
   `_sleeps` array declaration, which never matched at all (`_` is a word character,
   so there is no `\b` before `sleep`). Recovery: measured both. **Prevention:** derive
   a count by RUNNING the instrument, never by reading — the plan's own
   "verify-the-negative" pass had already "corrected" this number by reasoning.
2. **AC2 demanded an empty PASS-name-set diff, which Phase 1.2 made unsatisfiable**
   (a strengthened assertion necessarily renames its own PASS line). Recovery:
   restated as "no PASS added or removed". **Prevention:** when a phase adds or
   strengthens a test, re-read the ACs written before it existed.
3. **`$(<f) 2>/dev/null` reintroduced stderr noise** (§Solution 3). **Prevention:**
   brace assignment-only commands before redirecting.
4. **Claimed `command`/`exec sleep` escape a PATH mock** (§Solution 2).
   **Prevention:** a claim about shell resolution is a 4-line experiment; run it.
5. **Attributed the cap to two properties it cannot guard** (§Solution 1).
   **Prevention:** state, per guard, which inputs reach it and which do not.
6. **The default-install was pinned by nothing** (§Problem). **Prevention:** see
   Prevention bullet 1.
7. **The cap's diagnostic was unreachable** (§Solution 4). **Prevention:** trace a
   guard's message to the channel a human actually reads, through the call sites'
   redirections.
8. **T-6665-CAP shipped with the same self-sufficiency gap it was added to close.**
   **Prevention:** control arm under the non-default mode.
9. **The workflow comment cited runs that predated the ceiling it justified**, and
   silently excluded 3 failed runs (true pre-change max **615 s**, not 574 s).
   **Prevention:** a duration ceiling must hold for failing runs too — state the
   filter, and cite runs measured AT the value being justified.
10. **Two sibling sessions running the same suite produced false REDs** (`real2`
    canary, `real3` five zot tests). Recovery: three-way discrimination — `main`'s
    verbatim suite as a control (passed, incl. under CPU load), the opt-out path being
    byte-equivalent to `main`, and a clean re-run on a quiet machine (184/184,
    name-set identical). **Prevention:** already documented; the runner's own
    contention banner exists for this. One-off.
11. **First mutation battery ran against a stale pre-fix sandbox**; killed and re-run.
    **Prevention:** re-copy the sandbox after every edit round.
12. **Battery `verdict()` mislabelled FAIL as ABSENT** (§Prevention 4).
13. **CWD drift** — a persisted `cd apps/web-platform/infra` broke a later relative
    `cd`. **Prevention:** absolute paths or single-call `cd … && …`. Documented; one-off.
14. **`gh run rerun` returned HTTP 500** once; retried successfully. One-off.
15. Seven plan-drafting defects forwarded from `session-state.md`, all caught and
    fixed by the deepen-plan passes before `/work` (see that file).
16. **Sandbox baseline red (179/186)** nearly used as a mutation baseline
    (§Prevention 3).

## Tags

category: test-failures
module: apps/web-platform/infra
