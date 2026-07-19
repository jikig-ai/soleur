---
module: community-monitor
date: 2026-07-19
problem_type: test_failure
component: shell_script
symptoms:
  - "8/8 mutations RED while the central mechanism could be deleted with the suite green"
  - "github activity/contributors exited 126 'Argument list too long' on 10 commits"
  - "digest reported stars carried forward from a six-week-old run, labelled '(stale)'"
root_cause: incomplete_verification
severity: high
tags: [mutation-testing, vacuous-tests, fixture-shape, argv-limits, observability, scope-sweep]
synced_to: [compound-capture]
---

# A passing mutation battery still left the central mechanism untestable

## Problem

#6695 reported three GitHub collector failures. The fixes were mechanical. What
was not mechanical: a 10-agent review found **11 findings** past a green 36/36
regression suite, a passing 8-mutation battery, clean `shellcheck`/`tsc`/semgrep,
and a 186/186 full-suite run. **Three of the holes were in guards written to
prevent exactly those holes.**

The bug itself is a one-liner: jq `--argjson` puts the whole payload in a single
`execve` argument, and the binding limit is **`MAX_ARG_STRLEN` = 131,072 B PER
ARGUMENT** — not `ARG_MAX` (2 MB, the total argv+envp ceiling). Bisected:
131,071 passes, 131,072 fails. That is why it fired on **10 commits** and
recurred every run, and why a 2026-03-28 fix to one function in the same file
was never back-propagated: that learning attributed the limit to `ARG_MAX`, and
against a 2 MB ceiling the siblings look safe.

## Key Insight

**A mutation battery measures the mutations its author imagined.** A green
battery is evidence about *the mutations*, not about *the tests*.

Mine reported 8/8 RED. Meanwhile the fix's central mechanism — `($x | add // [])`,
which flattens `--paginate`'s one-array-per-page output — could be replaced with
`.[0] // []` at **all six sites** and the suite stayed **36 passed / 0 failed**.

The reason is a coverage axis nobody counts: **every fixture was a single JSON
array.** Under that shape `add // []` and `.[0] // []` are indistinguishable. The
suite had 36 assertions, parametric coverage across three commands and five
bindings, and a fixture-size precondition guard — and still could not see it.
Against a realistic two-page fixture (100 + 50): unmutated `150`, mutated `100`.
A silent 33 % undercount, reading as a quiet day — the same
plausible-wrong-number class the PR existed to eliminate.

**Fixture SHAPE diversity is a coverage axis distinct from assertion count,
parametricity, and mutation score.** Ask of any fixture set: *what shapes can the
producer emit that no fixture here has?* For a paginating API that is trivially
"more than one page", and nothing in an assertion count surfaces it.

## Solution

```bash
# Before — the whole body in ONE execve argument
issues=$(gh api "…" 2>&1)
jq -n --argjson issues "$issues" '{count: ($issues|length), …}'

# After — spooled, read through a file descriptor, uniformly dereferenced
printf '%s' "$issues" >"$issues_f"          # printf is a builtin: no execve
jq -n --slurpfile issues "$issues_f" \
  '($issues | add // []) as $iss | {count: ($iss|length), …}'
```

`--slurpfile` wraps file contents in an array, so a single-array body reads as
`[[…]]` and a paginated body as `[[…],[…]]`. `add // []` flattens both to one
array — the single uniform shape. The dangerous failure is the **partial**
unwrap (projection fixed, `length` left on the wrapper → `{"count":1,"items":[…all…]}`
at exit 0), which is why the suite asserts `count == (items|length)` at every
binding.

## The three self-inflicted verification failures

| Guard | How it was vacuous | Fix |
|---|---|---|
| Two honest-path fixtures for a fabrication detector | Both reason strings were **digit-free**, so the bare "contains a number?" check returned false on its own and the honest-failure exemption never ran. Deleting the exemption kept the suite green | Fixtures now carry realistic status codes (`HTTP 404`) |
| An ordering guard asserting a flag is applied after a `try` | `src.indexOf("} catch (err) {")` anchored on the **first of three** matches, in a different function — so `apply > catchStart` was trivially true regardless of placement | Scope the search from a preceding anchor: `indexOf(tok, afterIdx)` |
| A structural exclusion + a producer/consumer literal contract | Nothing asserted either; removing them left every suite green | Parity tests, each mutation-proven |

The generalizable move: **for every guard, name the mutation that satisfies it
while violating the property.** If you cannot, the guard may be pinning
placement rather than correctness.

## Two design lessons beyond testing

**A control whose output is provably ignored is speculative generality, not
defense in depth.** I built a fabrication detector (regex over the digest's
Repository Stats section) and cut it on review: it only fired when `repo-stats`
had failed — which *already* reds the monitor — so it could not change any
outcome. Its only yield was a second Sentry tag on an already-red run, bought
with a regex over LLM-authored markdown whose failure mode was silent
non-detection. Test: *can this control change what happens?* If no, it is
documentation with a maintenance cost.

**Paging and persistence must be separable decisions.** `heartbeatOk` gated both
the Sentry page and `safeCommitAndPr`. The obvious fix — lower it on a collector
failure — would have turned the monitor red **and discarded the honest digest**,
leaving the operator strictly less to act on than before. Worse, applying it as
the try's last statement meant a throw from a trailing step jumped to a catch
that deliberately keeps `heartbeatOk` true, so the page vanished on exactly the
compound-failure run. Correct placement: after persistence *and* after the catch.

## A sweep that under-reports its own output is worse than no sweep

The plan ran the right grep across every `--argjson` call site, transcribed
**6 of its hits into a table, silently dropped two**, and concluded *"Result: no
sibling shares the defect. The scope claim is now verified."* — one paragraph
after citing the learning whose thesis is *"X is unaffected" is a hypothesis, not
a fact*.

One of the dropped sites, `scripts/compound-promote.sh:186`, was **already
broken**: 1,073,302 B across 1,972 learning files, **8.2× the ceiling**. It could
not run at all.

A partial transcription is worse than skipping the sweep, because it produces a
*written* verification claim that the next reader will trust. **Count the grep's
hits and account for every one** — a table shorter than its own input is the
tell.

## Prevention

- Before trusting a fixture set: list the shapes the producer can emit, and
  confirm one fixture per shape. Multi-page/multi-record is the default miss.
- Before trusting a mutation battery: mutate something the battery does *not*
  cover — ideally the mechanism the change exists for.
- Before trusting an `indexOf`-based source guard: check whether the token
  occurs more than once in the file (`grep -c`), and scope from a preceding
  anchor if so.
- Before writing "scope verified": count the grep's hits; the table must account
  for all of them.
- After fixing one call site of an argv-size defect, grep every sibling binding
  and measure it against **131,072 B per argument** — not `getconf ARG_MAX`.

## Session Errors

**Forwarded from `session-state.md` (plan/deepen phase)**

1. **Halt gate 4.6 rejected the v2 plan draft** — it edited `apps/web-platform/server/…` (a sensitive path) while claiming none was touched. Recovery: added the required scope-out bullet. **Prevention:** derive the sensitive-path claim from the Files-to-Edit list mechanically, never assert it.
2. **v1's "-87 % undercount" was measured at `days=41`; production runs `days=1`.** It was the load-bearing argument for two scope items, both cut. **Prevention:** measure at the configuration that actually runs, and reconcile any measurement that contradicts a claim already written.
3. **v1's AC3 (`grep -c '2>&1' → 0`) was unachievable and mandated a regression** — it would have broken `cmd_discussions`' graceful path. **Prevention:** execute every AC at authoring time and record its expected value.
4. **v2's D7 wording was itself a leak** — "every tempfile uses `trap … EXIT`" leaks all but the last, since EXIT traps are global and singular. **Prevention:** verify prescriptive shell wording by running it.
5. **`/tmp` hit 100 % during planning** (9,470 leaked files, 1.9 GB, unrelated suite). **Prevention:** tracked as #6713.

**Work phase**

6. **Bash-tool CWD drift.** A throwaway `cd /tmp` probe left the shell at the **bare repo root**, so later greps read a *stale synced copy* of a worktree file and an applied Edit read as un-applied. **Prevention:** chain `cd <worktree-abs> && cmd` in every call; treat a surprising "the edit didn't apply" as a CWD hypothesis first.
7. **`cd apps/web-platform` persisted across calls**, causing two `FileNotFoundError`s on repo-relative paths. Same class as #6. **Prevention:** same.
8. **`str.replace(old, new, 1)` converted 1 of 2 identical call sites**, shipping a P1 (dead `check_cap`, bash arithmetic error on every `contributors` run). Six review agents converged on it. **Prevention:** for scripted substitutions, assert the expected **count**, not just that the anchor exists — asserted anchors are necessary but not sufficient.
9. **`PER_PAGE` referenced before declaration** — a fatal unbound variable under `set -u`. Caught by a follow-up grep. **Prevention:** after introducing a constant, grep that it is *declared*, not only referenced.
10. **`export export type`** — a scripted sub prefixed `export` onto an already-exported symbol. **Prevention:** `tsc` caught it immediately; no workflow change needed.
11. **Monitor `until` condition matched a per-suite marker.** `ALL TESTS PASSED` is printed by every sub-suite, so the monitor fired mid-run and reported the target suite absent. **Prevention:** anchor monitor conditions on a **terminal** marker (`RUNNER_EXIT=`, `N/N suites passed`), never one the run emits repeatedly.
12. **`&` combined with `run_in_background: true`** made the outer shell exit, truncating a test-all run at 789 lines with no terminal marker. **Prevention:** never add `&` when the harness already backgrounds the call.
13. **`/tmp` exhaustion aborted a full-suite run** and produced a misattributed failure in `lint-infra-no-human-steps` (which passes standalone). **Prevention:** #6713; and treat a failure in an untouched suite as environmental until reproduced standalone.
14. **Two vacuous fixtures** — see the table above. **Prevention:** mutation-test the exemption, not just the detector.
15. **Ordering guard anchored on the first of three matches** — see above. **Prevention:** `grep -c` the token before anchoring on it.
16. **The sibling sweep under-reported its own grep** by two sites, one already broken. **Prevention:** count hits; account for all.
17. **The plan's H3 "plausible 0" premise was false** — an exit-0 object error body makes jq hard-error (exit 5), so no fabricated zero was reachable. The guard was kept, its *rationale* corrected to diagnosability. **Prevention:** reproduce a claimed failure mode before building a control for it.
18. **The plan's D2 cap detection fired on every live run** — the `pulls` endpoint over-fetches a fixed page and filters client-side, so a full raw page is its steady state. **Prevention:** run a new warning against live data before shipping it; a detector that fires nightly trains the reader to ignore it.
19. **`gh issue create` denied for a missing `--milestone`.** Hook worked as designed; the body file had been written separately so nothing was lost. **Prevention:** already covered — write issue bodies with Write, never a heredoc in the same gated call.
20. **The sidecar contract and structural exclusion were initially unguarded** — removing either left every suite green. Caught by self-mutation. **Prevention:** mutation-test additions to shared constants, not just logic.
21. **A trailing `"$tmpfile"` argument survived** the switch to `jq -n --slurpfile`. **Prevention:** `bash -n` caught it; no workflow change needed.

## Related

- [`2026-03-28-gh-api-paginate-argument-list-too-long.md`](./integration-issues/2026-03-28-gh-api-paginate-argument-list-too-long.md) — **corrected by this work**; its `ARG_MAX` model is why the original fix was never back-propagated
- [`2026-06-18-sibling-script-shares-byte-identical-argv-accumulation-defect.md`](./bug-fixes/2026-06-18-sibling-script-shares-byte-identical-argv-accumulation-defect.md) — had the correct `MAX_ARG_STRLEN` model
- [`2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`](./2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md) — same thesis, three days earlier
- [`2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md`](./2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md) — a **sibling PR the same day**, independently
- **Three independent recurrences in four days, across three subsystems, is the signal.** Each was written up as a learning; none of them stopped the next. The disposition for a class that recurs this fast is a mechanical gate, not a fourth prose entry — the repo's own rule (`wg-when-a-workflow-gap-causes-a-mistake-fix`) says so. What a gate would assert is not obvious, though: "the battery is complete" is not decidable. The tractable sub-case is narrower and worth filing on its own: when a suite derives a set from a producer, assert the derived cardinality matches the producer's (the sibling learning's "two-producer count"), and when fixtures feed a paginating/multi-record producer, assert at least one fixture carries >1 record
- [`2026-05-04-vacuous-red-via-shared-fixture-and-toolchain-pinning.md`](./2026-05-04-vacuous-red-via-shared-fixture-and-toolchain-pinning.md) — fixture-driven vacuity
- #6713 (`/tmp` leak), #6714 (41-day digest gap), #6720 (sibling argv defect)
