---
title: "fix: lead gate is the bounded default, collision pre-check at plan/review preflight"
type: fix
date: 2026-10-26
slug: 10333-bounded-gate-default
branch: feat-one-shot-10333-bounded-gate-default
issue: 10333
closes: 10333
lane: procedural
---

# fix: bounded-gate default + collision pre-check (#10333)

## Overview

Skills/hooks-only workflow fix. The review skill's suite-scope paragraph
presented `TEST_GROUP=affected bash scripts/test-all.sh` (the #8591 heuristic
selector) as the runner-side equivalent of the affected gate, and the lead read
it as the lead's gate: on an `apps/web-platform/infra/` diff it printed
`[affected] MODE=full` and ran nearly every suite for over an hour. The bounded
default (`bash scripts/test-all.sh` — bare resolves `--affected` locally)
selected 225/634 on the same diff and includes the suites that caught the
regressions. A "covered" claim was also asserted from memory, and two sessions
of the same operator converted the same file for the same issue (#10320/#10322)
with no preflight probe. Learning:
`knowledge-base/project/learnings/2026-10-15-i-claimed-every-covering-suite-had-run-and-the-bounded-gate-found-three-regressions-of-mine.md`.

## Proposed Solution

1. `plugins/soleur/scripts/collision-precheck.sh` (new): read-only pre-check —
   `gh pr list --state open --search "<N>"` for open PRs naming the issue, plus
   `lib/proc.sh list_runs <basename>` foreign rows; graduated exits 0/10/2/64
   and a `SOLEUR_COLLISION` machine line; a probe that could not run never
   reads as clear.
2. `plan/SKILL.md` Phase 0.6 gains item 6 (collision pre-check before research
   fans out); `review/SKILL.md` Step 1 task list gains the same bullet.
3. Lead-gate prescription: review's suite-scope paragraph, work's standing
   constraint and §9, and ship's Phase 4 name the bounded default
   `bash scripts/test-all.sh` (plugin-portable `affected-tests.sh`), previewed
   by `bash scripts/test-all.sh --print-selection` and reported with the
   `selected N of M`. `TEST_GROUP=affected` stays documented ONLY for spawned
   agents handed an explicit file list, with the infra-diff `MODE=full`
   caveat.
4. Coverage-assertion rule (work §9 + review): never write "all covering
   suites ran" without the printed selection AND the run's per-suite result
   list — compare the two. Ship-time check: none — no existing lint shape
   covers a prose claim cheaply.
5. `plugins/soleur/test/collision-precheck.test.sh` (new): gh/proc stub
   fixtures prove the pre-check reports an open PR naming the issue; wiring
   arms pin the lead gate as the bounded default, never `TEST_GROUP=affected`.

## Files to Edit

- `plugins/soleur/skills/review/SKILL.md` (suite-scope paragraph, Step 1
  bullet, byte-ceiling trims)
- `plugins/soleur/skills/work/SKILL.md` (standing constraint, §9, trims)
- `plugins/soleur/skills/ship/SKILL.md` (Phase 4 preview sentence)
- `plugins/soleur/skills/plan/SKILL.md` (Phase 0.6 item 6, trims)

## Files to Create

- `plugins/soleur/scripts/collision-precheck.sh`
- `plugins/soleur/test/collision-precheck.test.sh`
- `knowledge-base/project/plans/2026-10-26-fix-10333-bounded-gate-default-plan.md`

## Technical Considerations

`lint-skill-body-budget.py` ceilings are near-saturated (plan +14 B, review +23,
work +68, ship +154 at branch base), so every addition is offset by a trim of
stale boilerplate in the same file (documented in the diff; ceilings ratchet
down only). The new suite is auto-registered by `test-all.sh`'s
`plugins/soleur/test/*.test.sh` glob — no hand registration.

## Guard Contract

### Guard 1 — collision-precheck.sh reports every live hit and never reads clear unchecked

**Property.** Running `collision-precheck.sh <N>` reports (exit 10, machine
line, human line) every open PR naming `<N>` and every foreign proc.sh row; it
exits 0 only when both probes ran and found nothing, and 2 when a probe failed
with no hits — never a false "clear".

**Assembly.** Three chokepoints, all named: (1) the gh probe —
`gh pr list --state open --search "<N>" -L 100 --json number,url --jq` in the
script, the only place open PRs are enumerated; (2) the proc probe —
`lib/proc.sh list_runs` per basename, the only place foreign rows are read;
(3) the verdict ladder + `SOLEUR_COLLISION` machine line in the same file —
the only exit site.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Serve a `list.json` with one open PR naming the issue | RED — exit 10 + `prs=<n>` (fixture row proves it) |
| 2 | Serve a proc.sh row labelled `foreign` | RED — exit 10 + `foreign=<pid>` |
| 3 | Make `gh` exit non-zero with a clear proc half | RED — exit 2 + `prs=unchecked`, never `prs=none` |
| 4 | Drop `--search "<N>"` from the gh argv in the script | RED — the stub's argv pin `pr list --state open --search <N> -L 100` misses |
| 5 | Must-PASS: empty PR list and no foreign rows | PASS — exit 0, `prs=none foreign=none` |

**Anchor.** The gh stub applies the caller's real `--jq` over fixture JSON and
records argv/write/unknown logs; a query-shape or write-verb drift goes red in
the same suite. proc.sh's own classification is pinned by `proc.test.sh`.

### Guard 2 — the lead-gate prescription is the bounded default, not `TEST_GROUP=affected`

**Property.** In `review/SKILL.md` and `work/SKILL.md`, the span from `lead
runs the gate` to the backstops names `bash scripts/test-all.sh` +
`--print-selection` and does NOT name `TEST_GROUP=affected`; ship's Phase 4
names `--print-selection` and `selected N of M`.

**Assembly.** Two chokepoints: (1) the SKILL.md lead-gate spans, extracted by
the suite's awk per file (both stop tokens named); (2) the suite's
`collision-precheck.test.sh` wiring arms — the only place the spans are
asserted.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Revert review's lead prescription to `TEST_GROUP=affected bash scripts/test-all.sh` | RED — span contains the heuristic token |
| 2 | Delete `--print-selection` from work's lead span | RED — preview arm fails |
| 3 | Delete the `selected N of M` sentence from ship Phase 4 | RED — ship wiring arm fails |
| 4 | Must-PASS: `TEST_GROUP=affected` still named for spawned agents (fanout arm 8d) | PASS — the token survives outside the lead span |

## Implementation Phases

### Phase 1 — script + suite

1. Write `collision-precheck.sh` (done — bash -n + shellcheck clean, all four
   exit classes smoke-verified against stubs).
2. Write `collision-precheck.test.sh` (done — 35/35 green).

### Phase 2 — skills

1. review suite-scope paragraph + Step 1 bullet (done).
2. work standing-constraint + §9 (done).
3. ship Phase 4 preview sentence (done).
4. plan Phase 0.6 item 6 (done).
5. Per-file byte-neutral trims to satisfy `lint-skill-body-budget.py` (done —
   lint OK, 10 skills within ceilings).

### Phase 3 — verify

- `bash plugins/soleur/test/collision-precheck.test.sh` — 35/35.
- `python3 scripts/lint-skill-body-budget.py --base origin/main` — OK.
- `python3 scripts/lint-guard-contract.py <this plan>` — clean.
- `bash plugins/soleur/test/fanout-suite-scope.test.sh` — anchors preserved.
