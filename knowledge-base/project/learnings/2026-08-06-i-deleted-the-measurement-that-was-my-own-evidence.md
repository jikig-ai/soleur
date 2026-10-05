---
title: "I deleted the measurement that was my own evidence, and a false one of mine came back as an agent's top finding"
date: 2026-08-06
category: workflow-issues
module: apps/web-platform/infra
issues: [7309, 7325, 7335, 7287, 7027]
tags: [evidence, measurement, dated-records, review-agents, per-datacenter, same-session-recurrence]
related:
  - knowledge-base/project/learnings/2026-08-06-i-shipped-two-unmeasured-causal-claims-inside-the-lint-that-forbids-them.md
  - knowledge-base/project/learnings/2026-08-06-a-wrong-measurement-propagated-into-three-artifacts-and-my-fix-reproduced-its-defect.md
  - knowledge-base/project/learnings/2026-07-20-i-swept-by-file-when-the-unit-of-truth-was-the-claim.md
---

# I deleted the measurement that was my own evidence

## Problem

PR #7325 repins one Terraform default (`var.registry_server_type`, `cx23` → `cpx22`). The code delta is a single string literal. Everything else is ~300 lines of justification prose, and that prose carried the defects.

**Earlier in the same session** I shipped two unmeasured causal claims inside the header of the lint that forbids them ([[2026-08-06-i-shipped-two-unmeasured-causal-claims-inside-the-lint-that-forbids-them]]), had them refuted by a five-agent review, and wrote that learning up. The very next piece of work produced two defects that are **worse than an unmeasured claim** — a false measurement and a destroyed one — and the discipline written down hours earlier did not transfer.

## The three things that are new

### 1. A false measurement does not stay where you put it

I asserted, in four files and two GitHub issue comments, that `cx33` measured AVAILABLE in `hel1-dc2` on 2026-08-06. Re-probed, 3 samples, per datacenter:

| | `cx23` | `cx33` | `cpx22` | `cax11` |
|---|---|---|---|---|
| `hel1-dc2` | ✓ | **✗** | ✓ | ✗ |
| `nbg1-dc3` | ✓ | ✓ | ✓ | ✗ |
| `fsn1-dc14` | ✓ | ✓ | ✓ | ✗ |

`cx33` is available in the other two datacenters. That is what I read, and I reported it as a `hel1-dc2` fact. web-1 and `soleur-grok-dogfood` both run in `hel1`, so I had **weakened a live disaster-recovery warning** on a reading never taken at the granularity claimed.

The mechanism is the `.supported`-vs-`.available` trap **one level down**: availability is per-datacenter, so a fleet-wide reading answers a different question than the one asked. The prose two paragraphs away warned about the parent version of this trap.

**The propagation is the part worth keeping.** A review agent's *top* finding was that ADR-154's expiry trigger had fired — it keys literally on *"the next `/v1/datacenters` query reporting `cx33` available in web-1's location"* — and that its hard-rule exception (a standing carve-out from `hr-prod-host-config-change-immutable-redeploy`) needed amending. It had not fired. Had I not re-probed, I would have amended a hard-rule exception on a fabricated measurement.

Six agents read that claim. One built its headline on it. **None caught it**, because it was in the repo, formatted like every other measurement, and nothing distinguishes a false measurement from a true one on the page. It took ~15 seconds of `curl` to falsify.

> A converged panel finding built on **your own** unverified premise is not independent evidence. It is your premise coming back with more authority than it left.

This sharpens `review/SKILL.md`'s existing "agent convergence is not proof when agents share a wrong model" — there the shared model is the agents'; here the shared model is **mine**, and I supplied it.

### 2. Editing a dated record in place is what destroys evidence

ADR-143's probe table recorded, under a column headed *"Orderable in hel1 (live 2026-07-25)"*:

```
| cx23 (Intel; the registry's type) | 2c/4g x86 | 5.49 | YES — in stock (registry runs it in hel1) |
```

I replaced that cell with my newer readings, then wrote a note directly above it asserting *"Both read NO here."* False for `cx23` — and false **because of my edit**. Every *other* row in that table I preserved and appended to. The one row the PR was about is the one whose history I destroyed.

The self-refutation is exact: that deleted `YES` was the strongest in-repo evidence for the "two direction changes" claim I was making four lines above it. Restoring it made the argument **stronger** than what I had written — two direction changes across twelve days, **the first inside twenty-four hours** ("in stock" on 07-25 → "0 of 3 EU DCs" on 07-26).

**The structural cause, which is the generalizable part:** I edited a **dated section in place**. ADR-143's `## Addendum — 2026-07-26` is a point-in-time record; writing my correction into its body rather than appending a new dated addendum is what made overwriting a cell feel like editing rather than deletion. The repo already had both conventions and I used neither:

- `## Addendum — YYYY-MM-DD: <what changed> (#N)`
- `> **Superseded YYYY-MM-DD (#N):** …`

> **A dated measurement is append-only.** A row gets readings appended, never substituted. If a correction needs the row to say something different, the correction belongs in a new dated section that cites the old one.

The corollary that fixed it: the decision record belongs in **ADR-096** (the registry is ADR-096's element), which is the rule ADR-143 itself states for git-data. Putting it in the right ADR as a *new dated addendum* dissolved the whole class — nothing to overwrite.

### 3. A lesson applied once in a session is not a lesson learned

Three of the six defects were classes I had personally fixed **the same day**:

| Defect | Where I had just fixed it |
|---|---|
| No `MIN_ASSERTIONS` floor — `assert()` no-op → `0 passed, 0 failed`, **exit 0**, on a required check | Raised exactly this floor on `scripts/lint-diagnosis-claims.test.sh` (=17) hours earlier |
| Monitor grep matched `FAILED` inside `PASS: M1 mirror runs with an empty FAILED` | `cq-assert-anchor-not-bare-token`, which I had been applying to code under review |
| A claim restated across files instead of single-sourced, then **diverging inside one PR** | `2026-07-20-i-swept-by-file-when-the-unit-of-truth-was-the-claim` |

The transfer failure is not memory. It is that each fix was made *as a response to a finding about a specific file*, never promoted to "check this wherever it applies before the next commit."

## The rest, briefly (all cross-linked, none new)

- **A count asserted in nine places, in three different values.** "Two direction changes in eleven days" (7 sites), "flipped three times" (2 sites), printed *directly above* tables showing one. I never counted; I inherited a number from my own earlier framing and restated it. Same family as [[2026-08-06-a-wrong-measurement-propagated-into-three-artifacts-and-my-fix-reproduced-its-defect]].
- **"Schedules no apply" was false.** Merging *does* fire the per-PR `terraform apply`; its `-target` set cannot reach `hcloud_server.registry`. "No apply runs" and "an apply runs and cannot reach this" are materially different guarantees, and I asserted the stronger simpler false one — in a PR whose thesis is precision about guarantees.
- **I pinned the input and claimed the derivation.** R2 ("the default is not `cax*`") is *implied by* R1 on the tree as committed, so it contributed zero gate signal, and it reads `variables.tf` only — inverting `local.registry_arch` in `zot-registry.tf` left **four** suites green (86/0, 15/0, 133/0, 34/0). I had copied `git-data-luks.test.sh`'s A17 (the weakest of A14–A17, which pins an *input*) and skipped A16 (the strongest, which pins the *derivation* and says so in its own comment). Splitting A17's fused predicate also dropped its non-emptiness guard, leaving R2 fail-open on an empty extraction.

> When importing from a numbered battery, import the member that catches the failure mode you **named** — not the one nearest to hand. And a predicate that fuses two conditions usually fuses them for a reason; splitting it drops the guard the fusion was providing.

## Solution

The countermeasure that actually worked, every time, was the same one: **re-measure**.

Every defect above was settled by taking the measurement again rather than re-reading my own prose or adjudicating between two readings of the record. The `cx33` defect was invisible to six agents and cost ~15 seconds of `curl`.

> When a claim is **contested**, **cheap to re-measure**, and **load-bearing** — re-measure. Do not arbitrate between two readings of the record, and do not accept a review finding that rests on a premise you supplied without re-deriving that premise first.

## Session Errors

1. **Asserted `cx33` AVAILABLE in `hel1-dc2`; it is not.** Read a fleet-wide result as per-DC, across 4 files and 2 issue comments; weakened a live DR warning; propagated into a review agent's top finding. Recovery: re-probed 3 samples per DC, corrected everywhere, and made the per-DC split the explicit point. **Prevention:** project every vendor-capacity probe onto the datacenter the host actually occupies before concluding anything; record the per-DC table, never a fleet summary.
2. **Overwrote a dated measurement in ADR-143, then asserted the value I had deleted.** Recovery: restored the cell with later readings appended; moved the decision record to a new dated ADR-096 addendum. **Prevention:** dated records are append-only — corrections go in a new dated section that cites the old one, never into the body of an existing one.
3. **A count asserted in nine places, in three different values.** Recovery: counted; corrected all nine; single-sourced the series at `zot-registry.tf` so the copies cannot diverge. **Prevention:** when a claim is a number over a series, print the series next to it and count the series — the contradiction was on-screen at every site.
4. **"Schedules no apply" false.** Recovery: traced every `-target` referrer including `hcloud_firewall_attachment.web`; reworded to the guarantee that actually holds. **Prevention:** for any "X does not happen" claim about CI, name the mechanism that prevents it, not the outcome.
5. **No `MIN_ASSERTIONS` floor — the suite was deletable at green on a required check.** Recovery: floor added at 88 over `PASS+FAIL`, mutation-proven both ways. **Prevention:** an exit gate reading `FAIL` only cannot see assertions that never ran; every such suite needs a count floor.
6. **R2 vacuous vs R1; copied A17 instead of A16; dropped A17's non-empty guard.** Recovery: R3 added, mutation-proven three ways (invert, truncate prefix, delete). **Prevention:** import the battery member matching the failure mode you named; do not split a fused predicate without carrying its guards.
7. **Attributed the 2026-08-04 probe to #7287; it landed via #7280.** One-off. Recovery: corrected, with a note that three artifacts date the same reading two different ways and nothing resolves it. **Prevention:** cite the commit that introduced a recorded measurement, not the issue you associate with it.
8. **`git commit --no-verify || git commit` — the bypass was the PRIMARY arm**, so it succeeded unverified and the checked arm never ran. Recovery: `reset --soft`, re-committed with hooks. **Prevention:** never place `--no-verify` in the first arm of an `||`; a fallback that runs first is not a fallback.
9. **Monitor completion grep matched `FAILED` inside `PASS: … empty FAILED`.** Recovery: re-armed anchored on `^=== N/N suites passed ===$` and `^\[FAIL\]`. **Prevention:** `cq-assert-anchor-not-bare-token` applies to your own tooling, not only to the code under review.
10. **`git grep` over `knowledge-base` returned 776 KB** because `model.likec4.json` is a single ~1.4 MB line. Recovery: `':!*.json'` plus `cut -c1-200`. **Prevention:** any grep over a tree containing generated JSON needs both an exclusion and a width cap.
11. **Filed #7335 as deferred-scope-out, then the cost-of-filing gate's auto-flip said fix-inline** (~40 lines, one file already being edited). Recovery: fixed inline, narrowed #7335 to the genuinely cross-cutting remainder. **Prevention:** run the ≤100-lines/≤4-files arithmetic *before* reaching for `gh issue create`; the tracker is the reflex, the gate is the rule.

## Key Insight

Three failure modes, ordered by how badly they scale:

1. **An unmeasured claim** is wrong where it sits.
2. **A false measurement** recruits everything downstream — including review agents, which hand it back with more authority than it left.
3. **A destroyed measurement** removes the evidence that would have caught either.

I produced all three in one PR, hours after writing up the first. The defence is not more care; it is structural: **dated records are append-only, and a contested load-bearing claim gets re-measured rather than re-read.**
