---
title: "feat(harness): WikiSkill Phase 3 - shorten ship SKILL.md into PURPOSE.md (eval-gate first)"
date: 2026-10-23
slug: wikiskill-phase-3-ship-purpose-md
branch: feat-one-shot-10551-ship-purpose-md
issue: 10551
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
gate_verdict: fail-stop
---

# feat(harness): WikiSkill Phase 3 - shorten ship SKILL.md into PURPOSE.md (eval-gate first)

## Enhancement Summary

**Deepened on:** 2026-10-23. **Evidence used:** a five-seat plan-review panel (DHH, Kieran, code
simplicity, architecture, spec-flow), CTO rulings T1 to T10 (T2 was ruled twice; the second
withdrew a proposed neutral-refactor mode), a learnings search, and the deepen halts run mechanically. A full
all-agent fan-out was not run: this plan edits only planning artifacts and its claims were each
re-derived from source by two independent seats.

Key improvements from review and deepen:

1. The "smallest change" shrank: no new gate flag and no neutral-refactor mode. Review then showed the
   `--target-task` flag is only a 0.5 floor on the candidate's own rate and the gate CLI passes no
   epsilon, so retention cases go in the corpus and the probes read `per_task` by script (T7).
2. A measurable discrimination bar replaced the undefined "bar", restated at review so every item has
   a reachable instrument (T2b, T7b).
3. The #10551 comment is self-contained, posted once with a dedupe marker, and cites draft PR #10947.
4. The wrong "hardcoded extract-block loop" claim was corrected: the third hardcoded place is the
   `expected_set` literal in `registry-completeness.test.sh`.

New considerations: the `ship` ceiling in `plugins/soleur/test/skill-body-budget.json` ratchets down
only, so M should lower it in the same PR; harness evidence is slice-only and M must say so and
attach a rationale-only-diff lint as well (T5, T8).

Halts run: 4.6 user-brand impact (pass), 4.7 observability (skip, pure docs), 4.8 PAT sweep (0 hits),
4.9 UI wireframe (skip), 4.10 encryption (skip, no store), 4.11 guard contract (skip, no guard in
this deliverable; the optional lint gets its Guard Contract in C's plan), 4.12 scope check (pass:
one unfenced section, three subsections, a `Recommendation:` line, no `unmapped` or `BLOCKED`).
Cited issue and PR numbers and the one cited rule id were verified live.

## Overview

Phase 3 of the WikiSkill work (issue #10551, `Ref` only, never `Closes`) asks for the rationale
prose of the largest skill files to move into a sibling PURPOSE.md, one skill per PR, starting with
`ship`. The brief puts a capability gate in front of any SKILL.md edit: `soleur:eval-harness` must be
able to compare a moved-rationale `ship` against its baseline today and show it behaves no worse. If
it cannot, the run stops after the capability finding, reports what is missing and the smallest
change that closes the gap, and does not shorten `ship`.

**Verdict: the gate fails. The harness cannot do this for `ship` today, so this run stops after the
finding.** `ship/SKILL.md` and `ship/PURPOSE.md` are not touched. In this plan the later work is
named the Capability PR (C) and the Move PR (M), so it is not confused with WikiSkill Phase 2
(#10550, off limits).

## Research Insights

### Premise Validation

- #10551 is open (`deferred-scope-out`, `priority/p3-low`) and is the tracker for this deferred
  capability. Its criterion, quoted: "Eligible once the eval harness (`soleur:eval-harness`) can show
  a moved-rationale skill behaves no worse than baseline."
- Stale citations in the brief: the brainstorm and spec were archived on 2026-09-18 (under
  `knowledge-base/project/brainstorms/archive/` and `knowledge-base/project/specs/archive/`, prefix
  `20260918-160549-`). The issue's "2,833 lines" is now 3,023 lines and 273,135 bytes.
- No ADR mentions `PURPOSE.md`; `git ls-files 'plugins/soleur/skills/*/PURPOSE.md'` returns 0 rows,
  so Move PR (M) introduces the convention. The governing ADR for the gate is ADR-069, which is scoped to classifier-skill
  edits (its Context names the `/go` routing table and the ticket-triage rubric), so gating a slice
  of a procedural skill extends its scope and C owns an amendment.
- Spec TR1 (archived spec) said procedural skills use "human-merged draft PR + deterministic lints +
  FR17's lagging gate", not the eval gate, while #10551 names the harness. They disagree. This run
  follows the issue and the brief: lint-only evidence is rejected (T3, T5) unless the operator
  explicitly accepts it for procedural skills.

### Property List and Cut List

Properties the ask buys: (1) a reviewer can see the shortened `ship` behaves no worse; (2) nothing
enforceable is lost; (3) rationale stays retrievable with provenance; (4) no net description words;
(5) one skill per PR with `Ref #10551`.

Mechanism check, grepped at the authority (`eval-gate.cjs`, `gated-skills.json`): the harness buys
property 1 only for four classifier blocks, not for `ship`. That is the gap. Property 2 is partly
bought by the 21 test files that cite `skills/ship/SKILL.md`
(`grep -rIl "skills/ship/SKILL.md" plugins/soleur/test`).

Cut: a whole-skill LLM-judge target over all of `ship` (about 70k tokens per call by a bytes-over-4
estimate, one Opus arm, $100 per month CI cap). B5 (#8290) is the cautionary precedent for instrument
validity, not for a whole-skill judge: it was a four-rule phrasing study that returned INCONCLUSIVE
after 648 calls, and its post-verdict audit found the scorer counted empty or truncated answers as
compliant, which is the lesson for C's discrimination bar.

### Value measured

`grep -c '\*\*Why' ship/SKILL.md` is 54 lines, 35,239 of 273,135 bytes (12.9 percent, about 8.8k
tokens per invocation by bytes over 4). The share depends on where a Why span is taken to end: 5.1
percent from the first `**Why` to end of line (about 3.5k tokens), 12.9 percent for whole lines,
16.1 percent to the next blank line (about 11k tokens). Measured at `origin/main` `6b8f7fcaf5` on
2026-10-23; main moves quickly, so M re-derives every count. The brainstorm framed Phase 3 as a token and clarity cleanup,
not a quality win.

### Capability probes (zero API, from `plugins/soleur/skills/eval-harness`)

| Probe | Result today |
|---|---|
| `node scripts/eval-gate.cjs --check ../ship/SKILL.md` | exit 0, `{"gated":false,"target":null,"block_id":null}` |
| `node scripts/eval-gate.cjs --dry-run --target ship --repeat 3` | exit 1, `no promptfoo resources for target "ship"` |
| control `--check ../incident/SKILL.md` | exit 0, `"gated":true`, target `incident-threshold` |
| control `--dry-run --target incident-threshold --repeat 3` | exit 0, `estimated_api_calls` 144 |

Structural findings behind them (read from source):

1. `gated-skills.json` has four entries, none `ship`; a gated source needs
   `<!-- eval-gate:block:<id>:start/end -->` sentinels and `ship/SKILL.md` has none.
2. Per-target wiring is hardcoded in three places: `TARGET_RESOURCES` in `scripts/eval-gate.cjs` (the
   gate itself), `TARGET_CONFIG` in `scripts/gen-skill-prompt.cjs`, and the `expected_set` literal in
   `test/registry-completeness.test.sh`. (`test/extract-block.test.sh` now derives its loop from the
   registry.) A registry row alone leaves `--check` green while the real gate dies on first use.
3. The instrument scores one closed-enum token per task. `ship` is a 3,023-line procedure whose
   behavior is tool calls; the README defers prose-output surfaces to a later LLM-judge assert.
4. The gate compares the current on-disk block with a candidate block, skill-arm only, so the
   "baseline" is the pre-edit text, the right comparator here. It is honest only if the sentinel slice
   contains the Why text that moves (ADR-069 projection precondition) and an LLM, not a script,
   applies the slice (2026-06-29 learning: grep the executor first; many `ship` gates are script- or
   hook-enforced and so are not gateable).
5. B5 (#8290, archived `b5-eval-results.md`) built a free-text instrument, ran 648 calls and returned
   INCONCLUSIVE. The README warns that half-covering a surface with a single-label harness "ships
   false confidence".

### Open Code-Review Overlap

None: the open `code-review` issues were searched (two-stage `gh --json` then `jq --arg`) for
`ship/SKILL.md`, `eval-gate.cjs`, `verdict.cjs`, `gated-skills.json` and `gen-skill-prompt.cjs`; no
body names any of them.

## Gate Finding

**Question:** can `soleur:eval-harness` compare a moved-rationale `ship` against baseline and show it
behaves no worse, today? **Answer: no.** Ruled by CTO agent, 2026-10-23 (`decision-challenges.md` T1).

### What is missing

| # | Missing piece | Evidence |
|---|---|---|
| 1 | One sentinel-wrapped slice of `ship/SKILL.md`: a closed-enum decision an LLM applies, with its Why paragraphs inside the span, and a `gated-skills.json` row | `--check` returns `gated:false` |
| 2 | A `ship-<decision>` target wired in all three hardcoded places (structural finding 2), plus enum, skill and baseline prompts, synthesized golden tasks and a promptfoo config | `--dry-run --target ship` exits 1 |
| 3 | Coverage of the rest of `ship`: the harness can only speak for the slice; the other moved paragraphs rest on the existing anchor tests, review and, per T5, a rationale-only-diff lint | single-label harness covers one decision |

### Smallest change

Ruled by CTO agent, 2026-10-23 (`decision-challenges.md` T2, re-ruled after plan review). Capability
PR (C) is: the sentinel wrap (a zero-text-change `ship/SKILL.md` edit, kept as its own small commit
so it can be rebased or reverted alone) and the `ship-<decision>` target, run with representative
retention cases in the new ship-decision corpus and run without `--append-on-accept`. Amended at
review (`decision-challenges.md` T7): `accept` needs no new logic, but C must not rely on an epsilon
passed through the CLI (`eval-gate.cjs` calls `computeVerdict` with empty options, so epsilon is fixed
at one task-equivalent) and must not use `--target-task` as the retention check (it decides on the
candidate's own rate on that task, a 0.5 floor, and never consults the baseline). C adds no flag to the
shared gate (it is also used by heal-skill and compound-capture), and builds no neutral-refactor mode.
The pooled `accept` cannot see a one-task regression, so probes and M assert on the `per_task` array,
parsed by a script. Medium effort, days. No qualifying closed-enum `ship` decision has been identified yet: finding one
is C's first step (many `ship` gates are script- or hook-enforced and fail the executor litmus), and
the days estimate assumes one exists.

**Claim limit.** The evidence may only say "rationale removal inside the wrapped slice did not
regress classification of decision X". It says nothing about the other roughly 50 Why paragraphs,
of which 14 sit in Phase 7 and the rest are spread over 23 other headings (24 distinct headings in all, counted with an
awk heading tally). Any that a script or hook enforces fail the executor litmus and cannot be in a
slice; M's plan must count how many that is rather than assume. Move PR (M) must label those "not
harness-evaluated". Whether that satisfies "attach the eval
comparison" is an evidence-bar question, ruled by the CTO agent, 2026-10-23 (`decision-challenges.md`
T5, extended by T8): slice-only harness evidence is necessary but not sufficient, and the Move PR
attaches the harness verdict AND a rationale-only-diff lint. M's moved paragraphs must sit inside the
wrapped span (a "no gated-block change" accept is no evidence), the lint must not pattern-match the
rationale marker, no assertion in the 21 citing test files is removed or relaxed, and rationale beside
a hard-stop or LLM-applied gate step stays in SKILL.md.

**Discrimination bar** (T2b as restated by T7b; the gate counts as able only when all hold, each
measured by running it through a reachable instrument): a degraded candidate returns `accept:false`
when the degradation is two or more task-equivalents (any lesser degradation shows as a `per_task`
drop); a rationale-removed candidate shows no task with a lower candidate rate than current, at repeat
5 or more with one re-run on a miss; a one-task flip is a per-task finding read by script, never via an
epsilon flag; the skill arm beats the control arm by at least 1/N from the harness's own per-arm
output (a missing readout is a C deliverable); the 0.5 floor and the trusted-corpus floor are never
cited as no-regression evidence; every decision-bearing rule in the slice maps to at least one corpus
case through a listing a test computes from the slice text, and the test fails on an empty mapping. No
corpus-size number is set because the code does not justify one.

### Alternatives considered

| Option | Verdict |
|---|---|
| Slice-bounded `ship-<decision>` target (chosen) | accepted: keeps the harness the gate |
| Whole-skill LLM-judge over all of `ship` | rejected: cost and the B5 precedent |
| Anchor tests plus a lint alone, no harness | rejected (T3, T5); flips only if the operator explicitly accepts lint-only evidence for procedural skills |
| Move now, guarded by existing tests only | rejected: violates the brief's stop instruction |

## Work in this run

The work phase does exactly these tasks and then stops. No `ship/SKILL.md` or `ship/PURPOSE.md` edit,
and no Capability PR (C) or Move PR (M) work.

1. **Re-run the probes** (Test Scenarios). Three outcomes: unchanged, continue. Control fails or
   errors (for example missing node modules): the negatives mean nothing, so post no comment and
   report the broken probe. A negative probe flipped (main moved): write a one-line "gate flipped"
   note in the PR body, post no "cannot" comment, and report it for re-planning.
2. **Post one comment on #10551** (a draft PR, #10947, already exists to cite). Start with the marker
   line `<!-- wikiskill-p3-gate:2026-10-23 -->` and skip the post if a comment with the marker exists.
   Retry once on failure; if it still fails, put the finding (the problem, the two missing pieces and the smallest closure) under `## Gate Finding` in the PR body
   and say the post failed. Never file a new issue as a fallback. Text (self-contained, no file
   links that archival will break):

   The text covers the two missing pieces, the slice-only limit, the smallest closure, the cost against
   saving, and the spec TR1 note. It was amended in place on 2026-10-23 per T10 (marker line kept
   byte-identical, count still 1) to add the T5, T7 and T8 conditions, the corrected figure range (T9)
   and the lossless TR1 and FR16 wording; the live comment on #10551 is the source of record.

3. **Verify the comment landed** right after posting: `gh issue view 10551 --json comments` contains
   the marker. No later check is needed.
4. **Commit the plan artifacts** (plan, `tasks.md`, `decision-challenges.md`). The PR title is
   `docs(kb): record eval-harness gate finding for ship PURPOSE.md (Ref #10551)`, not `feat(...)`, so
   no feature-title gate fires; no `plugins/` file changes, so no plugin semver label is expected. The
   body carries `Ref #10551`, no `Closes`/`Fixes`/`Resolves`. If the PR enters a merge queue it is never
   synced or pushed to afterwards; one `gh pr merge` per call; no secrets in argv.

## Follow-ups (not authorized in this run)

Tracked by #10551, which stays open; its body is unedited and it carries one comment, amended in place. These are pointers; the next planner re-derives
details from main, which moves quickly (`ship/SKILL.md` took 40 commits in 30 days).

- **Capability PR (C):** closes missing pieces 1 and 2. Owns: the ADR-069 amendment (required: ADR-069
  is scoped to classifier skills); a corpus of synthesized, discriminating cases; the discrimination bar
  above (`decision-challenges.md` T2b); an AC running `node scripts/eval-gate.cjs --dry-run --target <t>`
  (exit 0) and the registry-completeness test so the gate cannot ship dormant; a smoke run first
  (`--filter-first-n 1 --repeat 1 --no-cache`) with each row's output read, and the README
  thinking-budget warning heeded (a small `ANTHROPIC_MAX_TOKENS` returns empty text that a lexical
  scorer reads as compliant; #8290 needed 3000). A rationale-only-diff
  lint is required evidence for M (`decision-challenges.md` T5, T8), to be scoped and
  Guard-Contract'd in C's own plan. Binding for C (T8): the lint is non-circular (exemptions come from
  an explicit span-level delimiter pair plus a pointer left in SKILL.md, never from matching the
  rationale marker; the proof is reconstruction identity, re-splicing the PURPOSE.md sections at their
  pointers reproduces the base blob byte for byte, with `[id: ]` tokens and gate headings
  set-equal); it runs as a CI test under `plugins/soleur/test`; and the gate check requires a
  non-empty gated-block diff. Delimiter syntax, file layout and test wiring are left to C's planner.
- **Move PR (M):** only after C merges and the gate-flip checks pass against main. Moves Why
  paragraphs keyed by heading into `ship/PURPOSE.md`, keeps every step, fence, `[id: ]`, marker and
  `references/` link in SKILL.md, links PURPOSE.md once, edits no `description:`, lowers the `ship`
  ceiling in `plugins/soleur/test/skill-body-budget.json` (ratchets down only) in the same PR, reviews
  each moved paragraph clause by clause for scope-limiting conditions, and attaches the eval verdict
  (worded as slice-only evidence, with a non-empty gated-block diff and in-span versus out-of-span
  paragraph counts) while the lint runs as a CI test (T5, T8). M's PR body lists every Why paragraph as
  move or stay with a reason (rationale beside a hard-stop, never-skip or LLM-applied gate step stays),
  and removes or relaxes no assertion in the 21 citing test files (references may only be retargeted,
  per-file assertion count unchanged and listed). M's plan
  reconciles spec FR16, which also names learning citations moving to PURPOSE.md, with the brief's
  rationale/Why wording. One skill per PR, `Ref #10551`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "shorten the largest SKILL.md files by moving rationale into a sibling PURPOSE.md, starting with the `ship` skill only, one skill per PR" [brief] | Follow-ups, Move PR (M) | descoped this run - justification: the gate in ask 2 fails and ask 3 orders a stop |
| 2 | "confirm that soleur:eval-harness (plugins/soleur/skills/eval-harness, promptfoo skill-arm vs baseline-arm, gated-skills.json) can compare a moved-rationale skill against baseline and show it behaves no worse" [brief] | Capability probes, Gate Finding | mapped |
| 3 | "If the harness cannot do that for `ship` today, STOP after the capability finding and report exactly what is missing (and the smallest change that would close the gap) instead of shortening ship." [brief] | Gate Finding, Work in this run | mapped |
| 4 | "Do not file around it." [brief] | Work in this run, task 2 (no new issue, no fallback issue) | mapped |
| 5 | "move rationale/\"Why\" prose of plugins/soleur/skills/ship/SKILL.md into plugins/soleur/skills/ship/PURPOSE.md, keep all enforceable steps and rule IDs in SKILL.md, run the eval comparison and attach the result to the PR, and respect cq-skill-description-budget-headroom" [brief, if the gate passes] | Follow-ups, Move PR (M) | descoped this run - justification: conditional branch of a gate that failed |
| 6 | "the PR body uses `Ref #10551`, never Closes, until the sweeper closes it" [brief] | Work task 4, Acceptance Criteria | mapped |
| 7 | "Do not comment on, edit or close any other WikiSkills-related issue" [brief] | Work task 2, Acceptance Criteria | mapped |
| 8 | "Merge-queue PRs are never synced or pushed to. ... One `gh pr merge` per call. No secrets in argv." [brief] | Work task 4 | mapped |
| 9 | "Technical forks go to the CTO agent, not the operator." and "Persist every decision as a row of the `| Item | Class | Ruling |` table" [brief] | `decision-challenges.md` T1 to T10 (with T2b and T7b) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Capability probes and Gate Finding | asks 2 and 3 | asked |
| Work task 2, comment on #10551 | ask 3 ("report exactly what is missing") | inferred - justification: the report must outlive the session and #10551 is the open tracker; ruled by the CTO (T4) |
| Work task 4, docs-only PR | ask 6 | inferred - justification: the pipeline commits plan artifacts on this branch and the PR is the audit trail ship renders the rulings into |
| Follow-ups | asks 1, 3 and 5 | descoped as work, kept as pointers so the next planner starts from verified facts |
| `decision-challenges.md` | ask 9 | asked |

### Split Assessment

- Subsystems touched: 1 - `knowledge-base`
- Planned files: 3 | Estimated changed lines: about 400
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. C and M are separate later PRs by design.

## Files to Create

- `knowledge-base/project/plans/2026-10-23-feat-wikiskill-phase-3-ship-purpose-md-plan.md`
- `knowledge-base/project/specs/feat-one-shot-10551-ship-purpose-md/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-10551-ship-purpose-md/decision-challenges.md`

## Files to Edit

None. No `ship/SKILL.md`, no `ship/PURPOSE.md`, no eval-harness file.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing in this run (planning artifacts only). The
  risk sits in Move PR (M): a `ship` that silently lost an enforceable step would let a user's PR
  merge without a review, learning-capture or follow-through gate that blocks it today.
- **If this leaks, the user's workflow is exposed via:** no vector in this run. Rulings render into a
  public PR body, so they carry paths and counts only.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** carried forward from the brainstorm (the WikiSkill program
  edits the public plugin surface every install runs); a lower tier would under-weight Move PR (M),
  which this plan exists to gate. The simplicity reviewer argued for `none` for this docs-only run;
  not taken, because the threshold describes the program the plan constrains.

CPO sign-off: the CPO reviewed the brainstorm on 2026-09-18 (Domain Assessments, Product); this run
changes no product surface. `soleur:engineering:review:user-impact-reviewer` applies to M.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** the CTO ruled on the gate verdict, the smallest closure, where to record the gap, the evidence
bar for M and the run's next action (`decision-challenges.md` T1 to T10). The brainstorm CTO assessment is carried forward: Phase 3 is a token and
clarity cleanup, not a claimed quality win, and procedural skills have no train and validation split.
No other domain is relevant (internal harness tooling, no UI surface, no retained traces).

## Acceptance Criteria

### Pre-merge

- [ ] `git diff --name-only origin/main...HEAD` lists exactly the three files under Files to Create
  plus nothing outside `knowledge-base/project/plans/` and `knowledge-base/project/specs/`, checked
  after the commit (the files are untracked until then).
- [ ] `git diff --quiet origin/main...HEAD -- plugins/` exits 0 (no `ship/SKILL.md` or PURPOSE.md
  change, no harness change).
- [ ] `! grep -q '| operator' knowledge-base/project/specs/feat-one-shot-10551-ship-purpose-md/decision-challenges.md`
  and `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` exits 0.
- [ ] The PR body matches `Ref #10551` and does not match `(Closes|Fixes|Resolves) #`
  (`gh pr view --json body -q .body | grep -E 'Ref #10551'`, then the negative grep).
- [ ] `gh issue view 10551 --json comments -q '.comments[].body' | grep -c 'wikiskill-p3-gate:2026-10-23'`
  prints 1, or the PR body carries `## Gate Finding` with the post-failure note.
- [ ] No issue other than #10551 is commented on, edited or closed, and none tracking the harness gap
  is created. (Review, compound and ship may still file their own mandated issues.)
- [ ] `npx markdownlint-cli2` is clean on the plan and `tasks.md`.

## Test Scenarios

Re-runnable, zero-API, from `plugins/soleur/skills/eval-harness`:

1. `node scripts/eval-gate.cjs --check ../ship/SKILL.md; echo rc=$?` prints `"gated":false` and `rc=0`.
2. `node scripts/eval-gate.cjs --dry-run --target ship --repeat 3; echo rc=$?` prints
   `no promptfoo resources for target "ship"` and `rc=1`.
3. Control: `node scripts/eval-gate.cjs --dry-run --target incident-threshold --repeat 3; echo rc=$?`
   exits 0 and prints a positive `estimated_api_calls`. Do not pin the number: it moves with the
   corpus. A negative probe without this control cannot tell a missing target from a broken probe.

## Sharp Edges

- `--check` green is not a working gate; the AC for C must run `--dry-run --target <t>` and the
  registry-completeness test.
- A sentinel slice that excludes the Why text makes the comparison vacuous; a slice whose outcome a
  script computes makes it meaningless. Check the executor first.
- Ship Phase 6 renders `decision-challenges.md` and files an issue only for `operator (...)` rows;
  this plan has none, so ship files none and the existing decision-challenge issue stays untouched.
  The one operator-class question (whether and when to fund C, a priority call) is raised in the run's
  closing message, not filed.
- Ship archives the plan and specs in the PR, so no artifact should cite their live paths; the
  comment text above is self-contained for that reason.
- A plan whose `## User-Brand Impact` is empty or omits the threshold fails deepen-plan Phase 4.6;
  this one fills it.
