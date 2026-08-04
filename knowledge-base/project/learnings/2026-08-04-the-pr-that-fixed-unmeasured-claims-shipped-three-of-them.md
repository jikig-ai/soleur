---
module: CI / release pipeline
date: 2026-08-04
problem_type: logic_error
component: github_actions_workflow
symptoms:
  - "always() added to seven issue-filing steps, and the alarm still could not file on FIRE"
  - "a new telemetry read killed the step between the failure and degraded(), reporting nothing"
  - "an auto-close fired on a checker that had written no outputs at all"
  - "a self-run mutation battery reported 24/24 killed while 8 mutants survived"
root_cause: guard_verified_the_wrong_property
severity: critical
tags: [github-actions, set-e, pipefail, mutation-testing, vacuous-tests, fail-open, adr-166]
issue: 7242
synced_to: [review, work]
---

# The PR that fixed "messages naming unmeasured causes" shipped three of them

## Problem

#7242: every `Web Platform Release` from 17:11 UTC on 2026-08-03 failed at the zot-mirror
bridge, and the error told the operator to rotate a credential that a step **in the same
job, six minutes earlier** had verified live. The measured cause was `zot` crash-looping at
~4 restarts/min. This was the third iteration of one defect class on one code path;
iterations one and two were each "fixed" by rewriting the sentence, and each re-drifted.

The fix was structural: derive a four-valued verdict from the detector's measured JSON,
branch every message on it, and add a lint so the class cannot recur.

**Then the fix committed the class three more times, and a 261/261 green suite saw none of
them.** All three were found by the multi-agent review panel.

## Root cause

### 1. The headline fix was inert

```yaml
# scheduled-zot-restart-loop.yml — no `shell:` key, so Actions runs this under
# `bash --noprofile --norc -eo pipefail {0}`
run: |
  set -uo pipefail                                   # does NOT clear -e
  out="$(bash scripts/zot-restart-loop-alarm.sh 2>&1)"; rc=$?   # ABORTS HERE on rc!=0
  ...
  { echo "exit_code=${rc}"; ... } >> "$GITHUB_OUTPUT"           # never reached
```

A FIRE is `rc=1` **by design**. So on precisely the verdict the alarm exists to report, the
step died before writing any output, and all seven `if:` conditions compared against unset.
Adding `always()` removed the implicit `success()` lock and left this one — the alarm was
dark either way.

The identical bug is documented *and fixed* in `reusable-release.yml` by the same PR. It was
applied there and missed in the file the PR was about.

### 2. The new telemetry read could silence the failure it explains

```bash
RESTART_SUMMARY="$(grep -oE 'zot_restarts=[0-9]+' "$bs_log" | ... )"
```

`grep` exits 1 on no match → `pipefail` promotes it → `-e` kills the step, **between** "the
bridge failed" and `degraded()`. No `::error::`, no `mirror_status`, no `mirror_reason` —
the #6416 silent-mirror defect, re-entered by the block whose own comment promises it never
goes silent. A zero-row response is not exotic: it is the PRODUCER-SILENT state this repo
alarms on.

### 3. `null == '0'` is true

GitHub Actions `==` is **loose**: when operand types differ, both cast to Number. An unset
output is `null`, which casts to `0`. So `always() && steps.alarm.outputs.exit_code == '0'`
fires on a checker that measured *nothing*, and that step **auto-closes the live issue** with
a fabricated all-clear. Adding `always()` is what made it reachable.

### Why the suite saw none of it

The retry harness executed the extracted `run:` block with a bare `bash` — no `-e`, no
`pipefail` — while its header claimed to run the real block "verbatim". **Every `set -e`
abort was structurally invisible to it.** A harness that runs the SUT under different shell
flags than CI is not a weaker test; it is a coverage lie.

## Solution

- `rc=0; out="$(...)" || rc=$?` — the capture that actually captures.
- `|| true` on every grep/mktemp in the telemetry read, with the reasoning written at the
  site, plus boot-scoping (an unscoped min→max across a reboot *fabricates* a climb).
- Every numeric-literal arm paired with its non-numeric verdict; `always()` → `!cancelled()`
  (always() is also true on cancellation, and two of these steps close issues).
- The harness now runs the block under `bash --noprofile --norc -eo pipefail`, and T19/T20
  drive the zero-row and failed-query cases end-to-end.

## Key insight

**A self-run mutation battery measures the mutations its author imagined.** Mine reported
24/24 killed. Pointed at the axes it never touched, `test-design-reviewer` found eight
survivors, three of them live fail-opens. The axes batteries reliably miss:

| Axis | What survived |
|---|---|
| **Dispatch** | Neuter the assert helpers → `0 passed, 0 failed`, **rc 0**. Two suites had no floor; `test-all.sh` reads only the exit code. |
| **Population growth** | The guard walked **2 of 71** workflows and said "certified". Adding a third alarm carrying *both* defects stayed 15/15 green. |
| **Fixture direction** | Every fixture held `live:1, probes:2`, so "did the detector actually probe?" was never sampled — and `probes:0` graded `live`. |

And the deepest one: **`live` was derived from the ABSENCE of bad news.** Every arm above it
tested for the absence of a negative, which is exactly what a run that probed nothing
produces. `{"live":0,"dead":0,"unverifiable":0,"probes":0}` at rc=0 rendered *"Cloudflare
Access ADMITTED them"* about a measurement that never happened. Positive evidence must be
required, not inferred from silence.

Two corollaries worth keeping:

- **A guard cannot see the directory its own subject moved into.** The lint written because
  "prose is not an enforcement mechanism" did not scan `scripts/` — where this PR moved the
  canonical message text. Census 0 read as "enforced". Widening it immediately surfaced 11
  pre-existing violations across six other alarms.
- **Two hard errors must be distinguishable.** A missing baseline and a zero-file walk both
  exited 2 until a keeper fixture separated them; and a regression test coupled to a live
  ratchet baseline silently *inverted* when the baseline moved from 0 to 1 — it merely
  equalled it, so "a regression fails" passed when nothing regressed.

## Prevention

- For any `run:` block with no `shell:` key, assume `-e` is ON. `X="$(cmd)"; rc=$?` is an
  abort, not a capture.
- Run extracted-block harnesses under `bash --noprofile --norc -eo pipefail`.
- Treat an arriving mutation battery as evidence about its author, and audit its **axes**,
  not its count. `N` mutations of one shape is one mutation.
- Give every suite an assertion-count floor, **derived from a green run**, never guessed.
- Ask of every guard: *where does its population come from, and does it grow silently?*

## Session Errors

34 items were enumerated in the Phase 0.5 inventory (13 forwarded from
`session-state.md`). The classes that recurred:

- **Asserting instead of measuring** — ADR-166's `Extends:` cited four **fabricated
  filenames**; `session-state.md` claimed "every load site is guarded" when one of four was
  not; five ticked tasks asserted things that had not happened; the runbook restated "seven
  configs" as if measured. **Prevention:** every citation is a claim — resolve it against
  disk before writing it.
- **Vacuous assertions** — T9 anchored on the helper's *filename*, which the could-not-load
  fallback also prints, so it passed whether or not the helper loaded. **Prevention:** anchor
  on a literal only the real thing emits, then mutate to confirm it reds.
- **Floors guessed, not derived** — `MIN_ASSERTIONS=55` against an actual 54 (self-inflicted
  red); `MIN_FILES=40` broke the fixture seam and made two hard-error causes
  indistinguishable. **Prevention:** derive floors from a green run and give test seams an
  override.
- **Edited under a running exit gate — twice**, and briefly mutated a workflow while it ran,
  forcing a relaunch. **Prevention:** `git status --porcelain` must be empty before launch,
  and if an edit cannot wait, kill the run rather than reinterpreting its output.
- **Directive written to an issue COMMENT** when the sweeper reads `.body`
  (`sweep-followthroughs.sh`). **Prevention:** check the consumer's read path before writing
  to a surface it does not parse.
- **A mutation battery timed out mid-run**, leaving `RECENT_BOOT_S=99999999` in the tree.
  **Prevention:** size batteries under the harness timeout and restore from a pristine
  backup in a separate call.
- **A fixture's explanatory prose IS the haystack.** Both new fixtures for the PIR-gate fix
  opened by describing what they pinned — "contains no *outage*, no *went down*, no *failed in
  production*" — and thereby contained every one of those tokens. The positive fixture passed
  with the new alternation deleted; the negative one signalled outright. Baseline green,
  mutation green, both for the same self-inflicted reason. **Prevention:** for a
  scanner/matcher fixture, the file is input, not documentation — put the rationale in the test
  case and mutate in BOTH directions, because a fixture that matches for the wrong reason is
  invisible to a one-direction battery.
- **Accepting a gate's PASS without checking what it measured.** `net-issue-flow.sh` reported
  `Filing: 0` on a PR that filed two issues, because it counts issues whose *body* cites the PR
  and neither did. The honest state was `+1`, i.e. BLOCKED. Taking the green would have been
  the exact defect this PR exists to remove, committed against my own ship gate. **Prevention:**
  when a gate reports a count you can independently name, name it first and reconcile — a gate
  that passes because it looked at the wrong set is worse than one that fails.

## Postscript: the filing that DISSENT correctly rejected

Compound's triage proposed filing a repo-wide lint for this shell-semantics class, on a
`cross-cutting-refactor` scope-out. The CONCUR gate DISSENTed, and it was right on evidence I
had not gathered: I sized the population as **71 files**, which is the number *scanned*, not
the number *violating*.

Measuring properly — and then re-verifying the reviewer's own list rather than accepting it —
the live population is **2**, not 71 and not the 5 the reviewer estimated:

| Site | Verdict |
|---|---|
| `build-inngest-bootstrap-image.yml` (x2) | **TRUE** — `set -euo pipefail` active; a grep miss aborts *before* the author's own `if [[ -z ]]` ERROR message |
| `scheduled-terraform-drift.yml` | FALSE — sits in the `else` of `if [[ -z "$survivors" ]]`, so `grep -c .` always matches ≥1 |
| `scheduled-supabase-advisor-scan.yml` | FALSE — explicitly bracketed by `set +e` / `set -e` |
| `web-platform-release.yml` | FALSE — that block sets `set +e`/`set -e` and **no `pipefail`**, so `tail` exits 0 |

Two one-line fixes closed the whole live population, in a file the lint would have needed a
`.highwater` ratchet to carry. **The lesson is the same one the PR is about, applied to my own
scoping: I asserted a population instead of measuring it, and the number I quoted was a count
of the wrong set.** A ratchet sized for 71 hypothetical violations against a real population
of 2 is the "speculative generality" the cost-of-filing gate exists to catch.

Net issue flow for the PR stayed at **+1**.

## Related

- ADR-166 — a CI message may only name a cause the job measured (this PR)
- `knowledge-base/project/learnings/2026-08-03-my-battery-measured-one-axis-and-every-fixture-i-checked-my-work-with-was-broken.md`
- `knowledge-base/project/learnings/2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`
- #6416 (silent mirror), #6288 (zot crash-loop class), #7247, #7248
