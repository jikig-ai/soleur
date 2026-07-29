---
module: cron-cohort
date: 2026-07-29
problem_type: logic_error
component: inngest_function
symptoms:
  - "seven cron producers keep a GREEN-with-no-artifact path after the reference producer was fixed"
  - "the dedup short-circuit returns GREEN before the liveness gate is ever reached"
  - "25 test failures that were a mid-refactor snapshot of my own dirty tree"
  - "TEST_ALL_EXIT=1 reported from a failed shell redirect, not a failed suite"
root_cause: incomplete_scope_sweep
severity: high
tags: [cron, fail-closed, mutation-testing, vacuous-test, exit-gate, grep-scoping, observability, adr-drift]
issues: [6750, 7046, 7047]
pr: 7032
synced_to: [work, review, one-shot]
---

# A per-producer fix left seven siblings live — and four signals that were not what they looked like

## Problem

This is the **third** entry in one defect lineage:

1. [[2026-07-20-the-fix-for-a-green-with-no-artifact-bug-shipped-green-with-no-artifact]] — `cron-community-monitor` posted GREEN for six days while committing nothing (#6714), and the *fix* for it shipped the same bug class (#6726).
2. [[2026-07-19-a-mutation-battery-that-passes-can-still-leave-the-central-mechanism-untestable]] — the battery guarding that area was green while the central mechanism could be deleted.
3. **This work** — the fix was correct, and it was applied to **one** producer. Seven siblings ran the identical shape untouched for another five weeks.

The measured silent windows for the untouched cohort were **15, 22, 46, and 75 days**.

## The part that does not port uniformly

The ADR-126 remedy has **two halves**, and the second one is the half that actually keeps the incident shape alive:

- **Half 1 — the liveness gate.** `livenessOk` falsified by an observed negative, then `if (!livenessOk) heartbeatOk = false;` placed *after* the persistence block.
- **Half 2 — the dedup short-circuit.** This is the one that matters. The short-circuit posts GREEN and **returns before `finalizeOutputAwareHeartbeat` is ever called**, so half 1 never runs on that path. Every acceptance criterion for half 1 can pass green while the dated incident shape stays live in all seven handlers.

Half 2 does **not** port by copy-paste. `digestCommittedOnDefaultBranch` is an *existence* probe against an exact path. It is sound for `cron-growth-audit` only, because a `<RUN_DATE>-content-audit.md` file cannot exist unless this run wrote it. For the other six the artifacts are **permanent files and directories** — the contents API returns 200 forever, so an existence probe is a guard that can never fail. Those six needed a new `artifactCommittedSince({ anchorRegex, sinceIso })` **freshness** probe against the cron's own `commitMessage:` anchor.

A guard whose probe always succeeds is indistinguishable from no guard, and it is the exact defect class the ADR exists to close. The suite now asserts that split **negatively**: exactly 1 caller of the existence probe, exactly 6 of the freshness probe, and no handler may pass a directory or permanent path to the existence probe.

`cron-roadmap-review` is the 8th caller of `digestIssueExistsForDate` but calls `safeCommitAndPr` zero times — genuinely EXEMPT, not an oversight, and now named as such in the PR body so it does not read as one.

## Session Errors

**S1 — Launched the `test-all.sh` exit gate against a dirty tree and kept editing under it.** Run 1's 25 failures were a mid-refactor snapshot of my own making; I began diagnosing them as real regressions.
**Prevention:** An exit gate only describes the tree you intend to ship. Confirm `git status --porcelain` is empty *before* launching, and make no edits while it is live — if an edit cannot wait, kill the run first. The result is otherwise unfalsifiable: you cannot tell a real failure from your own half-applied refactor.

**S2 — A Monitor exit condition matched an intermediate per-suite `Total:` line instead of the terminal `=== N/M suites passed ===` marker**, producing a false completion signal.
**Prevention:** For any multi-stage runner, the exit condition must match the **terminal** marker, never a per-stage line that merely looks summary-shaped. Pick the marker by reading the runner's last emitted line, not by guessing at a plausible-looking one.

**S3 — Concluded "no `existsSync` guard exists" from a truncated probe and promoted the claim into a commit message.** The guard exists and throws.
**Prevention:** Already covered by `hr-verify-repo-capability-claim-before-assert`. The compliance gap worth naming: the *mechanism* here was truncation. A negative existence claim derived from a `head`-ed or otherwise truncated probe is not a finding — it is an unfinished search — and it must never be promoted into a commit message, PR body, or subagent prompt.

**S4 — The mutation battery only covered the mutations I imagined.** `test-design-reviewer`, briefed to *"find what my battery missed; do not re-run my mutations,"* found 6 more. The highest-value one: the `PRODUCER_CLASS` assertion pinned a **constant** rather than a behaviour, so it could never have gone RED.
**Prevention:** Already covered by `cq-assert-anchor-not-bare-token` ("mutation-test every new assertion — if deleting the guard leaves tests green..."). The addition worth carrying: an adversarial review pass is a **distinct activity** from writing the battery, and its brief must forbid re-running the author's own mutations. A battery is a record of the author's imagination; only a second party bounds it.

**S5 — Redirected the `test-all.sh` log into a scratchpad directory that did not exist.** The redirect failed, the suite never ran, and the wrapper's `TEST_ALL_EXIT=1` read as a test failure rather than a shell error.
**Prevention:** Same class as S2 — the signal read was not the signal produced. `mkdir -p` the log destination in the same command that writes to it, and confirm the log file exists and carries the terminal marker before interpreting any exit code.

**S6 — Re-sprung two of the plan's *own documented* grep-scoping traps during the final AC walk.** An unescaped closing backtick in a `sed` range (it command-substituted, so the range ran 245 lines past the prompt body and swallowed a `<today>` code comment) and a cohort-of-7 assertion scoped over the roster of 8.
**Prevention:** The plan documented these traps correctly, in prose, and they recurred anyway — inside the same session that wrote them. **Prose traps do not prevent recurrence; executable ones do.** The AC walk is now a checked-in script beside the tasks file, so the next walk runs the greps rather than re-deriving them.

**F1 — Plan v1 ported only half the remedy** (see above). Every v1 acceptance criterion would have passed green while the incident shape stayed live.
**Prevention:** When a plan's ACs can all pass without the reported symptom being closed, the ACs are measuring the implementation rather than the defect. Ask of every remedy: *which code path returns before my new gate runs?*

**F2 — Four v1 acceptance criteria were unsatisfiable against `main`:** per-file `git grep -c` contaminated by prose, directory scope catching 9 and 12 files instead of the roster, and an "unbound" regex that also matched the bound form.
**Prevention:** Same root as S6, and the reason the AC script now exists. Every count-AC must be measured against the roster once, at authoring time, and the measured number recorded — an AC nobody has run is a guess.

**F3 — Two plan v1 claims were factually false** (that the change "carries only a colour"; that the ADR-029 residual is user ids).
**Prevention:** Covered by `hr-verify-repo-capability-claim-before-assert`. Both were caught by the review panel before commit — the panel is doing its job, which is the reason to keep it.

**F4 — Two reviewers drew false conclusions from `cron-artifact-age.sh` output** without noticing the worktree is a shallow clone (it reports NEVER/STALE for 9 of 9 regardless of production state).
**Prevention:** `git fetch --unshallow` is a hard prerequisite for any history-reading diagnostic in a worktree, and the tasks file now carries it as a blocking banner above the tasks that depend on it.

## Key Insight

**A fix applied to the producer that reported the incident is a fix to one sample of the cohort.** The unit of remediation is the *shape*, not the reporter. Before closing a defect that a single component surfaced, enumerate every component that shares the shape, and make the enumeration a test — here, a parity test that reads the class table out of `scripts/cron-artifact-age.sh` and asserts set-equality with the handlers' compiled class arms, so the shell table and the code cannot drift apart silently.

The second insight is about signals: **four separate times this session I acted on a signal that was not the one I thought I was reading** — a dirty-tree failure list, a non-terminal progress line, a truncated probe, and a failed redirect. None of the four was a subtle systems problem. Each was a case of accepting a plausible-looking artifact without confirming it was the artifact I asked for.

## Prevention

- Confirm a clean tree before launching an exit gate; make no edits while it is live.
- Match terminal markers, never intermediate ones; verify the log exists before reading an exit code.
- Never promote a negative existence claim from a truncated probe.
- Brief an adversarial reviewer to find what the battery missed, without re-running its mutations.
- Convert documented grep traps into a checked-in script — prose traps recur, including for their own author.

## Related

- [[2026-07-20-the-fix-for-a-green-with-no-artifact-bug-shipped-green-with-no-artifact]] — the reference implementation this widens (#6714 / #6726)
- [[2026-07-19-a-mutation-battery-that-passes-can-still-leave-the-central-mechanism-untestable]] — the vacuous-guard precedent
- `knowledge-base/engineering/architecture/decisions/ADR-126-cron-liveness-must-assert-the-consumed-artifact.md` — Amendment 2026-07-28 (#6750)
- Deferred: **#7046** (C4 `inngest -> github`/`-> doppler` re-attribution), **#7047** (the detector posts no check-in of its own — the reporter-is-the-subject problem one level up)
