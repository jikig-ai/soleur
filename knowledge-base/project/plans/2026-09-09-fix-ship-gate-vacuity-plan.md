---
title: "Two /ship Phase 5.5 gates returned a verdict without measuring"
date: 2026-09-09
status: complete
refs: [7426, 7278, 6813, 7801, 7987]
brand_survival_threshold: none
tags: [ship, gates, vacuity, measurement, hooks]
---

# Two `/ship` Phase 5.5 gates returned a verdict without measuring

Both were found while shipping PR #7987, by running the gates rather than reading them.
Neither is a new defect; both are the documented-but-unfixed half of an earlier repair.

## Problem

### A — the soak gate fires on the sentence that exempts it

`SOAK_RE` offers a bare `soak` alternative, so it matches any mention, including a
declaration that no soak exists. On PR #7987 the **only** match across the entire corpus
(PR body + linked plan) was the plan row:

```
| 2.9.1 Soak follow-through | **Skip.** No acceptance criterion is time-gated;
  nothing here closes on a soak. |
```

The gate blocked `gh pr ready` and demanded sweeper enrollment for two trackers that close
on no timer at all. `ship-soak-followthrough-gate.sh`'s CLOSES-extraction comment (anchor:
`**Why:** PR #7426`, ~137 lines below the file header) already records the
cause — *"the regex is negation-blind"* (PR #7426) — and that PR fixed only the
closing-target half beside it.

### B — the incident-PIR gate can scan an empty string and report "no signal"

`ship/SKILL.md` Phase 5.5 builds the gate's corpus as PR body + linked plan, resolving the
plan path **out of the PR body**. When the body cites no plan, `PLAN_TEXT` is the empty
string and the gate reports `no incident signal` having examined zero bytes of plan. PR
#7987 was in exactly that state: 19 KB of PR body containing no `knowledge-base/` path.
Adding the link and re-running flipped the verdict to `INCIDENT-SIGNAL: yes` — same commit,
same gate, opposite answer. The mandatory gate had been silently plan-blind (it still fired on body-only outage vocabulary; it could not see the plan, and did not say so) for every
PR whose body omits a plan link.

Both gates share the resolution shape, so B is present in the soak gate too.

## Approach

**A — strip negated soak vocabulary before matching.** Same strip-then-match shape
`ship-incident-pir-gate.sh` already uses for #6813, applied to the same class of problem.

Deleting the bare `soak` alternative was measured and rejected: 174 of 1905 tracked plans
match through it alone, and real declarations use prose forms the other alternatives miss
("across a soak window ≥ ~2h post-deploy").

The negation window stops at a clause boundary (`.` `|` `)` `—` `–` `;` `:`) so a negation
of something else cannot silence a real declaration beside it. The forcing case is real,
from the corpus:

```
- [ ] AC9: PR body uses **`Ref #5733`** (NOT `Closes`) — closure is gated on the
      post-deploy soak below.
```

`NOT` negates `Closes`; the sentence IS a soak declaration and must survive.

The unit is the LINE, not the sentence: the target shape is a markdown table row whose
label and disposition sit in adjacent cells, and splitting on `.` shreds ordinals like
`2.9.1` into fragments that re-match the bare token.

**B — make "I read no plan" a thing the gate says out loud**, in both gates, and move the
incident-PIR corpus construction out of SKILL.md prose and into the script that already
owns the regexes — the same argument `parse-form-a.awk` and `probe-verb-gate.sh` are
already split out for: a harness must execute the production runtime, not scrape it.

## Measurements

Ground truth for "declares a real soak" = plans carrying a `soleur:followthrough script=`
enrollment directive, anchored on the `<!-- ` HTML-comment opener (n=42). The looser "names a probe under `scripts/followthroughs/`"
set (n=91) is CONTAMINATED — a plan that fixes the sweeper names probes without declaring
a soak — and is not used.

| | before | after |
|---|---|---|
| plans firing (all 1905 tracked) | 275 | 209 |
| false positives removed | — | 66 (24%) |
| recall on the 42 clean positives | 36 | 36 |

Zero recall regression. Re-derive rather than trust these.

## Acceptance criteria

- [ ] **AC1** A corpus whose only soak vocabulary is negated produces no signal.
- [ ] **AC2** A negation of something else in the same sentence does NOT suppress a real
      declaration (`soaknegscoped`). AC1 and AC2 are a matched pair and ship together:
      AC1 alone also passes if the strip eats everything.
- [ ] **AC3** A third-party unenrolled tracker beside a real soak still DENIES — the fix
      narrows the gate, it does not disable it.
- [ ] **AC4** Recall over the clean positive set does not regress (36/42).
- [ ] **AC5** Both halves are mutation-verified: neutering the negation rule reds AC1;
      unscoping the window reds AC2.
- [ ] **AC6** Each gate emits a distinct note when it resolved no plan, so "scanned the
      body alone" is never again indistinguishable from "scanned everything".
- [ ] **AC7** The `gh` stub returns the PROJECTED `.body`, not the JSON envelope — the
      fidelity defect its own issue-view branch already documents.
- [ ] **AC9** The plan half of the corpus gets the SAME fenced-block strip as the PR
      body, so a quoted `Ref #N` illustration is not extracted as a live tracker. Matched
      pair: fenced ref allows, the same ref unfenced still denies.
- [ ] **AC8** The #7426 closing-target regression test stays non-vacuous: its fixture body
      carries a REAL soak, not the negated one that the fix would render signal-free.

## Observability

Both gates are operator-facing shell run on a developer machine; there is no runtime
surface. Their evidence is the sibling suites plus the corpus measurement above.

discoverability_test:
  command: bash .claude/hooks/ship-soak-followthrough-gate.test.sh
  expected_output: "18 passed, 0 failed"

## Soak follow-through enrollment

Not applicable — no acceptance criterion here is time-gated.
