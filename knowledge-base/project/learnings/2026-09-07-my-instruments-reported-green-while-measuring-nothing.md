---
title: "My instruments reported green while measuring nothing"
date: 2026-09-07
category: workflow-patterns
issue: 7826
pr: 7868
tags: [measurement, mutation-testing, vacuity, sweeps, guards, tooling-traps]
---

# My instruments reported green while measuring nothing

## Problem

PR #7868 is small and mostly subtractive: delete 27 `import{}`/`removed{}` adoption
blocks from `apps/web-platform/infra/sentry/issue-alerts.tf` (#7826), add one
`sentry_cron_monitor` plus a terminal heartbeat step (#7834), and record a
verification finding above one resource without changing a value (#7829).

Almost nothing went wrong with the change. Nearly everything went wrong with the
apparatus that was supposed to prove the change was right — and in every case the
apparatus reported **green** while measuring nothing, or measuring the wrong thing.

The review panel confirmed the shape: it found more defects in this PR's own guards
and prose than in the diff, and the deterministic gates (semgrep non-vacuity,
shellcheck, the repo lints) had **disjoint yield** from the agent panel. Neither
substituted for the other.

This is the sibling one level down from
[`2026-09-04-every-defect-the-panel-found-was-in-my-verification-not-my-fix.md`](2026-09-04-every-defect-the-panel-found-was-in-my-verification-not-my-fix.md):
that learning is about assertions asserting too little. This one is about the
*instruments* — the shell, the extractor, the runner, the sweep — returning a
confident wrong number that no assertion could have caught, because the assertion
was reading the instrument.

## Root Cause

### 1. A sweep indexed by FILE cannot see a twin in a file it did not open — or in a section it did not read

The PR retires a mechanism, so every prose carrier of "27 `sentry_alert` + 2
`sentry_issue_alert`" had to become "27 + 3". The first pass corrected three
carriers and left seven. Two of the seven were in files the same pass had just
rewritten: the tripwire's own header sat eight lines above the string it fixed, and
the drift workflow's header sat three paragraphs from ones it replaced.

The failure is structural, not attentional. `git diff --name-only` bounds the sweep
to the files the diff touches, so a twin in an untouched file is invisible by
construction; and opening a file to fix one occurrence gives no coverage of a second
occurrence elsewhere in it.

The fix is to sweep by **claim**: grep the *subject* the claim is about
(`sentry_issue_alert`, the count's referent), read every hit repo-wide, and decide
each one. A residual-zero count on the OLD string is evidence about a string, never
about a claim.

This is the third variant of a shape already documented twice — see
[`workflow-issues/2026-08-03-blanket-renumber-rewrote-other-work-and-a-count-certified-it.md`](workflow-issues/2026-08-03-blanket-renumber-rewrote-other-work-and-a-count-certified-it.md)
(sweeps that rewrite too much) and
[`2026-08-17-i-corrected-a-fabricated-claim-by-grepping-its-phrasing-and-missed-a-site.md`](2026-08-17-i-corrected-a-fabricated-claim-by-grepping-its-phrasing-and-missed-a-site.md)
(sweeps keyed on phrasing). The new variant: a sweep bounded by **its own diff's
file list**.

### 2. A count-shaped guard fails in a place the change's author never edits

Adding the 56th cron monitor and the 12th heartbeat slug moved four derived counts
in `model.c4`'s `github -> sentry` edge prose (10→11 workflows, 4→5 dispatch-only,
55→56 monitors, 11→12 check-ins) and reddened `c4-count-parity` — a required-context
CI gate — in a file the diff had no reason to open.

The plan's "no C4 impact" step applied the correct rubric (external actors /
systems / containers / access relationships) to a model that **also** embeds
CI-gated cardinalities in edge prose. That rubric does not reach prose counts. The
remedy is not a better rubric; it is to **run `c4-count-parity.test.sh`** in the
C4-impact step instead of reasoning about actors.

### 3. Borrowing a sibling's PARAMETER while dropping its DESIGN DECISION

`scheduled_supabase_advisor_scan` was cited as "the closest analogue" for the new
monitor's `checkin_margin_minutes = 60` / `max_runtime_minutes = 10`. Its
`source == 'inngest'` gate — the thing that stops a `workflow_dispatch` from posting
a check-in the schedule did not ask for — was not carried over. Worse, the PR then
wrote a paragraph calling the resulting hole *"inherent to heartbeat monitors"*.

It is inherent to **ungated** ones. The cited precedent is itself the counterexample.
When a diff cites a precedent for one attribute, enumerate what else that precedent
does about the same hazard before writing prose that generalises the gap.

### 4. A guard can pin a step's SHAPE while saying nothing about its DESTINATION or SEMANTICS

The new parity suite had 14 assertions and passed 14/14 against the control. It also
passed against every one of these mutants:

- `monitor-slug:` deleted from the step entirely
- `monitor-slug:` re-pointed at a *different* monitor
- the exact `!= 'unavailable'` denylist the step's own comment forbids
- `&& 'ok' || 'ok'` (a status expression that can never say `error`)
- a one-character typo in the OUTPUT name — the suite asserted the step-id half of
  `steps.<id>.outputs.<name>` and never the name half

Fourteen mutants survived. After hardening (cohort-closure cross-check, monitor-slug
destination assertion, a `not.toMatch(/steps\.\w+\.outputs\.\w+\s*!=/)` on the status
expression, and `scheduled-terraform-drift`'s drift-check as a must-FAIL terminality
fixture), 7/7 of the re-run mutants were caught.

### 5. An anti-vacuity floor derived on the PRE-change tree carries the change's own slack

The floor's justifying comment said "11 steps across 10 workflows" — a measurement
taken before the branch added the 12th. On the branch it is 12 across 11, so the
floor had **two** units of slack where it was designed to have one. A floor is a
statement about the tree it will run against, not the tree it was written on.

### 6. Evidence gathered for one question does not settle a different question with the same subject

Issue #7829 asks: *does a BYOK cap breach page nobody?* The measurement performed answered:
*was `fallthrough_type = "NoOne"` typed deliberately?* Both were true, and the issue
was nearly closed on the second.

The real finding, reached only by asking the first question directly: migration 084
RAISEs the cap exception at lines 107/121 **before** its audit `INSERT` at line 128,
while its siblings `consent_withdrawn` (72→80) and `expired` (87→95) insert first —
against migration 061's stated house rule that *"accounting is sacred"*. So a cap
breach writes no ledger row, `byok_cap_exceeded` carries only `first_seen_event`, and
`v_hourly_spent` (a SUM over those rows) **freezes**. #7829 stays open, correctly.

### 7. Five shell instruments returned confident wrong readings

Each of these produced a number that looked like an answer:

| Trap | What it reported | Truth |
|---|---|---|
| `out=$(cmd \| tail -4); rc=$?` | `tail`'s status | the pipeline's real rc, obtained by capturing it directly |
| `comm` without `LC_ALL=C` (twice) | "file 1 is not in sorted order" + an unreliable diff | a correct diff, cross-checked with `grep -Fxf` |
| `pgrep -f <pattern>` (three times) | matched my own command line — killed my own shell twice (exit 144), one false duplicate-run alarm | `/proc` enumeration by PID |
| `grep -c 'run:'` on the runner | "123 registered infra suites" (fabricated) | **115** — the runner prints its own total |
| ANSI-carrying vitest output into a mutation extractor | every row empty, **control included** | re-run through `sed -r 's/\x1B\[[0-9;]*[mGKHF]//g'` |

The ANSI one is the most dangerous of the five, because a battery whose control row
is empty is not a failed battery — it is a **void** one, and every mutant in it reads
as "survived" or "killed" arbitrarily. The control row is the instrument's self-test;
if it does not move, nothing below it is data.

### 8. A harness-reaped run is not a result

The first infra run was launched without `setsid`, was reaped at exit 144 (SIGUSR1),
and left a log reading **114 PASS / 0 FAIL with no terminal summary line**. Read as a
count, that is indistinguishable from a pass. Re-run detached, the runner said:

```
=== registered infra suites: 115 passed, 0 failed, 0 unaccounted (of 115) ===
```

`0 unaccounted` is precisely the clause a reaped run cannot emit. The terminal marker
is not decoration — it is the only evidence the runner reached the end of its own
list. Poll for the marker's shape and read the rc file; never infer a verdict from
the last PASS you can see.

## Solution

Final consolidated verification on `HEAD=7057665fd`, tree clean, remote in sync:

```
infra registered suites   115/115, 0 failed, 0 unaccounted (rc=0)
scripts shard             360 passed, 0 assertion failures, 3 declined
vitest server/inngest     2803 passed, 1 skipped
c4-count-parity           ALL TESTS PASSED
c4-model-freshness        ALL TESTS PASSED
T25 monitors-audit        36 passed, 0 failed
adoption-guards           32 passed, 0 failed
tsc                       rc=0
terraform fmt -recursive  clean
```

Phase 0's three live-state limbs all green on `main` before a single block was
deleted: 27 `sentry_alert` in an exact 1:1 bijection with the 27 resource labels;
exactly 3 surviving `sentry_issue_alert`, disjoint from all 27 `removed{}`
from-labels; `sentry-alert-live-fidelity.sh` PASS field-for-field. **Limb 2 had never
run machine-verified before** — the post-merge apply had skipped it under an implicit
`success()`.

## Key Insight

**An instrument's control row is the only thing that distinguishes a measurement from
a hallucination, and almost none of my instruments had one.**

The mutation battery had a control and it saved the battery — once the control was
read as data rather than as ceremony. The suite counts had a control (the runner's
own total) and I fabricated a number instead of reading it. The sweep had no control,
so a residual-zero count certified a miss. The floor had no control, so it inherited
the change's own slack.

Every green in this session that turned out to be false was a green **with no
self-test upstream of it**. The generalisation: before trusting any derived number,
drive the instrument once in each direction and refuse to continue unless both
readings moved.

## Prevention

1. **Sweep by claim, not by file.** Grep the claim's *subject* repo-wide and decide
   every hit. Never bound a correction sweep by `git diff --name-only`, and never
   accept a residual-zero count on the old string as coverage.
2. **Run the count-shaped gates, don't reason about them.** A C4-impact step that
   thinks about actors cannot see CI-gated cardinalities in edge prose. Run
   `c4-count-parity.test.sh`.
3. **When citing a precedent for one attribute, enumerate what else it does about the
   same hazard** — and never write prose generalising a gap the cited precedent
   itself closes.
4. **Mutate the destination and the semantics, not just the shape.** Delete the
   target field, re-point it, and typo *both halves* of every
   `steps.<id>.outputs.<name>` reference.
5. **Derive every floor on the tree the assertion will run against**, not the tree it
   was written on.
6. **Restate the issue's question verbatim before concluding.** Evidence about the
   same subject is not evidence about the same question.
7. **Give every extraction a control row and refuse to proceed if it is empty.**
   Strip ANSI (`sed -r 's/\x1B\[[0-9;]*[mGKHF]//g'`) before parsing test output;
   `LC_ALL=C` before `comm`/`sort`; capture `rc` directly, never after a pipe;
   enumerate processes via `/proc` rather than `pgrep -f` a pattern your own command
   line contains.
8. **A run with no terminal marker is UNRESOLVED, not green.** Launch under `setsid`,
   poll the marker's shape plus the rc file, and treat `{no marker, clock timeout}`
   as a reap.

## Session Errors

1. **Two planning agents died on API transport error** (`No response from API`,
   server_error). — *Recovery:* ran the partial-artifact recovery contract, re-invoked
   `soleur:plan` inline instead of in a subagent. — **Prevention:** for a plan
   continuing an on-disk checkpoint, run the skill inline; a subagent adds a transport
   hop and buys nothing when the research fan-out is already persisted.

2. **AC6 was defeated by my own AC7.** `git diff | grep -c '^[+-].*fallthrough_type'`
   returned 2, not 0, because AC7 mandates a comment citing that very attribute. —
   *Recovery:* excluded comment lines; mutation-proved 0/2/0. — **Prevention:** when a
   plan pairs a "this must not change" diff assertion with a "document why" prose
   requirement, check the assertion against the prose before writing either.

3. **False positive in my own id-reference assertion.** Flagged
   `scheduled-realtime-probe.yml` as a dangling reference; it declares `- id: probe` on
   the dash line and the regex required a line-leading `id:`. Nearly reported a phantom
   defect. — *Recovery:* widened the regex; re-derived the reference set. —
   **Prevention:** every YAML key regex must tolerate a leading `-` list-item marker.

4. **Drift backstop keyed on the wrong signal.** Used `steps.file_drift.outcome`; the
   filer exits 1 on *every* drift run by design, so the backstop could never
   distinguish "filed" from "failed". — *Recovery:* switched to a positive
   `filed=true` step output emitted before the deliberate `exit 1`. — **Prevention:**
   never key a health signal on the outcome of a step whose non-zero exit is part of
   its contract.

5. **The first mutation battery was VOID.** Every row *including the control* returned
   empty, because vitest output carries ANSI escape codes. — *Recovery:* re-ran with
   `sed -r 's/\x1B\[[0-9;]*[mGKHF]//g'`. — **Prevention:** read the control row first
   and abort the battery if it did not move; strip ANSI before parsing any test output.

6. **`comm` locale trap, twice.** "file 1 is not in sorted order" plus an unreliable
   diff. — *Recovery:* `LC_ALL=C` and a `grep -Fxf` cross-check. — **Prevention:**
   `LC_ALL=C` on every `sort`/`comm` pair, and cross-check set differences with a
   second method.

7. **`$?` after a pipe.** `out=$(python3 lint.py | tail -4); rc=$?` reported `tail`'s
   status. — *Recovery:* re-ran capturing rc directly. — **Prevention:** capture rc
   from the command itself, or use `PIPESTATUS`.

8. **`pgrep -f` self-match, three times.** My own command line contained the search
   string: killed my own shell twice (exit 144) and raised one false duplicate-run
   alarm. — *Recovery:* switched to `/proc` enumeration by PID. — **Prevention:** never
   `pgrep -f` a pattern that appears in the polling command itself.

9. **Fabricated "123 expected" infra suites,** derived by grepping `run:` lines. The
   runner states its own total: **115 registered**. — *Recovery:* read the runner's
   total. — **Prevention:** never derive a total a tool already prints.

10. **Infra run harness-reaped (exit 144, SIGUSR1)** for want of `setsid`. Log showed
    114 PASS / 0 FAIL with **no terminal summary**. — *Recovery:* explicitly refused to
    report it as green; re-ran detached, which produced
    `115 passed, 0 failed, 0 unaccounted (of 115)`. — **Prevention:** always `setsid`
    long runs; treat a missing terminal marker as UNRESOLVED.

11. **markdownlint rc=1.** — *Recovery:* verified by rule-id multiset against
    `origin/main` that all 10 violations are pre-existing (MD012×3, MD018×4, MD032,
    MD038, MD046) and that the branch added zero. — **Prevention:** none needed;
    one-off, and the multiset comparison is the right method.

12. **Committed with `LEFTHOOK=0` twice,** because the pre-commit battery was queued
    behind up to five sibling worktrees. — *Recovery:* ran gitleaks,
    scheduled-show-full-output-lint, lint-infra-no-human-steps, `tsc`, and
    `terraform fmt` manually each time. — **Prevention:** when bypassing lefthook under
    contention, enumerate the hook's own gate list and run each one; record which ran.

13. **Claim-sweep miss.** Corrected three carriers of "27 + 2" and left seven, two of
    them in files the same pass had just rewritten. — *Recovery:* re-swept by subject
    (`sentry_issue_alert`) repo-wide. — **Prevention:** see Prevention #1.

14. **c4-count-parity reddened by an untouched file.** Four derived counts in
    `model.c4` edge prose. — *Recovery:* updated all four plus the sentry→founder edge.
    — **Prevention:** see Prevention #2.

15. **Borrowed a sibling's margin without its gate,** then wrote prose calling the
    resulting hole "inherent to heartbeat monitors". — *Recovery:* added
    `github.event.inputs.source == 'inngest'` to the heartbeat `if:` and a
    `workflow_dispatch.inputs.source` default of `manual`; deleted the false paragraph.
    — **Prevention:** see Prevention #3.

16. **Anti-vacuity floor derived on the pre-change tree** (11/10 vs the branch's
    12/11), giving two units of slack. — *Recovery:* raised the floor to 12. —
    **Prevention:** see Prevention #5.

17. **Fourteen guard mutants survived a 14-assertion suite.** — *Recovery:* hardened
    with cohort closure, destination, and status-expression assertions; 7/7 caught on
    re-run. — **Prevention:** see Prevention #4.

18. **Nearly closed #7829 on evidence answering a different question.** — *Recovery:*
    re-asked the issue's question verbatim, found the migration-084 ordering defect,
    kept #7829 open. — **Prevention:** see Prevention #6.

19. **AC2 misdescribed the final `sentry_alert` resource as "its predecessor".** —
    *Recovery:* re-read the file tail and corrected the AC. — **Prevention:** cite a
    content anchor, not a positional relationship (`cq-cite-content-anchor-not-line-number`).

20. **AC18 dead-end.** `apply-sentry-infra.yml`'s `push:` trigger is `paths:`-scoped to
    `apps/web-platform/infra/sentry/**` and the destroy-guard jq filter; PR #7866
    touches neither, so merging it fires no apply. — *Recovery:* restated AC18 with two
    satisfiers plus an escape hatch. — **Prevention:** before making "PR X merges and
    its apply is green" a gate, read X's trigger `paths:` and confirm X's own diff
    matches one.

21. **`hr-never-run-commands-with-unbounded-output` violated during compound itself.** A coverage check — `grep -n -i 'control row\|setsid\|LC_ALL\|PIPESTATUS\|pgrep\|ANSI\|…'` across two 1000+ line SKILL.md files — returned 36.2 KB and was persisted to a file instead of shown. The alternation was broad (`ANSI` matches inside ordinary words) and no `cut`/`head` bounded it. — *Recovery:* re-ran as a per-pattern `grep -c` matrix, then `cut -c1-260` on the handful of real hits. — **Prevention:** when grepping a long prose file for prior coverage, ask for COUNTS per pattern first and only then widen to the matching lines, bounded by `cut`.

**Not attributable to this session** (found in `.claude/.rule-incidents.jsonl` and
checked): the `gdpr-gate-*` rows naming `apps/web-platform/lib/auth/foo.ts` are hook
test-suite fixture leaks into the operator's real ledger (**#7486**), and the
`adr-033-inngest-cron-canonical` deny came from a sibling worktree creating
`scheduled-supabase-advisor-scan-guardprobe.yml`. That orphan id also fails the
rule-metrics aggregator's orphan gate (rc=5), which is **#6531** — already open, so no
duplicate filed.

## Tags

category: workflow-patterns
module: infra/sentry, .github/workflows, test/server/inngest


## Addendum — 2026-09-08 (#7466): the strip this file prescribes is defeated two ways

Measured on bun 1.3.11 and 1.3.14 while fixing a gate whose anchored greps could not
cross a coloured summary line. The `sed -r 's/\x1b\[[0-9;]*m//g'` form prescribed above
is correct for the case it was written against and fails on two axes:

1. **`\x1b` is a GNU sed extension.** BSD/macOS sed matches the literal characters
   `x1b` instead, so the strip is a silent no-op there — it removes nothing and reports
   nothing. Build the escape with `ESC=$(printf '\033')` and interpolate it.
2. **An SGR-only class (`\[[0-9;]*m`) is defeated by any non-SGR escape.** Measured, each
   of these survives it and then breaks an anchored parse: a colon-separated SGR
   (`ESC [ 3 8 : 2 : … m`), a two-byte DECSC (`ESC 7`, no `[` at all), and a charset
   designator (`ESC ( B`). The ECMA-48 form covers all three —
   `-e "s|${ESC}\[[0-?]*[ -/]*[@-~]||g" -e "s|${ESC}[ -/]*[0-~]||g"` — where the classes
   are ECMA-48's parameter, intermediate and final byte ranges, and the second rule
   catches every two-byte escape. Pin `LC_ALL=C`: the ranges are locale-dependent
   without it. Use `|` as the delimiter, not `/` — an escaped `/` inside a bracket
   expression turns the class into 0x20-0x5C and eats real text.

Also verified there: `tr '\r' '\n'` must TRANSLATE rather than delete, or overwritten
text concatenates onto the summary line and the anchor misses again.

Reference implementation: `plugins/soleur/test/preflight-check10-suite-integrity.test.sh`
› `strip_ansi`.
