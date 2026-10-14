---
title: "The correction PR published three new false statements, and its guard certified none of them"
date: 2026-08-20
issue: 7624
pr: 7664
category: workflow-patterns
tags: [legal-corpus, guards, mutation-testing, review, art-30, sweeps]
---

# The correction PR published three new false statements, and its guard certified none of them

## Problem

PR #7664 reconciled the published legal corpus to Art. 30 PA-7 after the register was
amended to record that the CLA evidence archive **is** a third-country transfer. The issue
said "roughly ten statements". Enumeration found **64 rows across 16 files**, because three
of the four defect classes carry no `weur` token at all.

The corpus corrections were factually sound — a seven-agent panel verified all 14
implementation claims against the Terraform, the workflows and the register. **Every
merge-blocker the panel found was introduced by the PR itself, and every one was the defect
class the PR existed to close.**

## The three false statements I published while correcting false statements

1. **A scoped truth republished as an unscoped falsehood.** The register says the timestamp
   payload *"egresses to the **TSA**"*. I published *"leaves the **bucket**"*. Dropping the
   scope made it false — the `.tsr` is committed to the public `cla-signatures` branch, which
   the same bullet said three sentences earlier.

2. **A claim about sibling documents that the PR did not make true.** The CLO's drafted limb-(3)
   sentence asserted "those notices now disclose … the transfer", naming the CLA preambles.
   Measured: `united states`, `cloudflare`, `third.countr` all returned **0** in all four CLA
   files. A false premise inside the Art. 6(1)(f) limb that establishes rights are not overridden.

3. **A contractual warranty created by removing a true one.** Removing `chat-attachments/*`
   from the DPA Schedule 2 R2 row was correct. Adding Cloudflare to the §11.2 Customer-Data
   transfer list in the same commit told every future counterparty their Customer Data goes to
   the US — in the PR that proved none reaches R2. Same class as the §11.1 defect being fixed,
   opposite direction.

## The unit of truth is the CLAIM, not the FILE

Twice in one session I indexed a sweep by file and missed a sibling inside the file I had
just edited:

- The plan named `apps/cla-evidence/infra/README.md:14` as row H2. I fixed line 14 and left
  lines 4 and 13 carrying the same two defects.
- My commit *titled* "sweep the four sites AC10's own pattern could not see" edited
  `cla-evidence.yml` **line 6** and missed the emitted contributor receipt at **line 217** —
  `"R2 Object Lock (Governance, 10yr)"`, posted to every CLA signatory's pull request. The
  most-read contributor surface in the system, in the file I had open.

**A residual-zero count is evidence about a string, never about a claim.** The plan's AC10
sweep was billed as the closure criterion and had four measurable blind spots: no bare
`EU region`, no `EU residency`, no bare `Object Lock`, no `chat-attachments`. Verified by
feeding each surviving string to the pattern itself.

## A guard can pin eleven historical phrasings and zero propositions

The anti-regression guard was green throughout. A reviewer rewrote §5.11 to republish all
three retracted claims in different words — *"located in Western Europe"*, *"None for this
archive"*, *"Ten years from object creation, after which records are erased"* — and the guard
reported **0 forbidden hits, REQUIRED satisfied, green**.

My own mutation battery reported 6 rows all caught. It was **two axes**: corpus content, and
array-length-to-zero. A battery on the axes I never touched found **13 survivors**:

| Mutation | Before |
|---|---|
| Delete the whole `test()` block | green, 13 passed, exit 0 |
| Keep both floors, empty both loop bodies | green 14/14 |
| Replace all 11 literals with garbage (length stays 11) | green 14/14 |
| Redirect 3 rows to a document that never carried the claim | green 14/14 |
| Strip **every** Chapter V sentence from both surfaces | green 14/14 |
| Hard-wrap one literal at its midpoint | green 14/14 |

The floor measured **cardinality, not reachability** — it could not tell 11 live sentinels
from 11 dead ones. The positive arm was vacuous outright: `"EU-US Data Privacy Framework"`
already occurred **7/6, 6/5 and 3/3 times in the false corpus**, via the Stripe, GitHub and
Cloudflare-CDN rows. And the reflow risk was not all-or-nothing — at `prose-wrap 80`, **6 of
11 sentinels survive and 5 die silently**, so the guard keeps reddening and keeps looking alive.

**Enumerate the AXES a battery edits, not the rows it reports.** N rows on one axis is one row.

## What fixed it

- **Whitespace-normalise the haystack** — closes the reflow partial-disarm.
- **Prove reachability against a committed fixture** of the pre-correction sentences. Not
  `origin/main`: that is the moving-ref trap — the assertion inverts the moment the PR merges
  and main carries the corrected text. A committed fixture is immutable and doubles as the
  record of what was published.
- **Anchor the positive arm on the PROPOSITION**, not an instrument token: each anchor names
  the importer's country or the retention posture, and each was verified to occur **zero**
  times on the pre-correction corpus.
- **`test.each`** so the test count is a function of the arrays.

Re-measured: **5 of the 6 previously-surviving mutations now RED**, control green both sides.
The sixth — emptying the callback bodies — survives, and is stated in the block rather than
implied: `guard-vacuity-floor.test.sh` derives its population from `*.test.sh`, so a
TypeScript body is outside it by construction. Tracked at #7669.

## Deferring is a decision, and mine were wrong three times

The CONCUR gate DISSENTed on all three of my scope-out filings. The pattern was consistent:
each identified a real defect, then reached for the **largest possible resolution** — a
corpus-wide re-reconciliation, a new Processing Activity, an infra overhaul — and scoped
*that* out, when the repo's own conventions supplied a small, correct, non-prejudging action:

- A **divergence note** in the register's own amendment style (~6 lines) for the
  Supabase/Cloudflare two-tests contradiction.
- A **recorded exclusion**, exactly as PA-7 §(d) already does for FreeTSA, for the unregistered
  LUKS-header bucket — correct under both answers to the open Art. 4(1) question.
- An **empty default** matching the two `r2_admin_*` siblings twelve lines below the broken
  variable.

## Two rulings I reversed on evidence

- **The CLO recommended bumping the CLA `**Version:**` line.** Those lines are already
  drifting (canonical body lines vs a single mirror hero `<p>`), so editing them trips the
  ratchet — the identical mechanical ground the *same review* used in Fork 5(a) to rule
  against bumping `Last Updated`. The recommendation collided with its own finding.
- **Test-design recommended proving sentinels against `origin/main`.** Documented moving-ref
  trap; used a committed fixture.

An agent's verdict and its reasoning are separable. So are a ruling and its premises.

## A fix that moves a failure has not fixed it

I reported that the `cf_admin_token` default would clear `plan (apps/cla-evidence/infra)`.
It did not. It cleared the *abort* and revealed the real blocker: `CF_API_TOKEN` is absent
from `prd_terraform` (probe: HTTP 403, error 9109). The original error was a **red herring** —
the provider authenticates with `cf_api_token`, not the variable the abort named. The fix is
still right (it removes a misleading error that would send the next person down the same dead
end) but the check still cannot pass. Filed #7675.

## Session Errors

- **`pgrep -f 'test-all.sh'` matched my own command line and killed my own shell (exit 144).**
  Recovery: verified siblings unharmed via `/proc/<pid>/cwd`. **Prevention:** the repo ships
  `plugins/soleur/scripts/lib/proc.sh` (`list_runs`, `kill_mine`) precisely because it resolves
  ownership and excludes self, ancestry and own process group. Use it; never hand-roll the match.
- **A `Monitor` reported completion instantly because `mktemp` CREATES the rc file**, so
  `[ -f "$RC" ]` was true from t=0. **Prevention:** gate on `[ -s "$RC" ]` (non-empty), and
  never use a path that the setup step itself creates as a completion sentinel.
- **Indexed two sweeps by file and missed siblings inside the edited file** (README:4/:13;
  `cla-evidence.yml:217`). **Prevention:** enumerate the CLAIM's paraphrases repo-wide and
  classify every hit; a per-file fix list cannot see what it did not open.
- **Dropped a scope qualifier from a register cell** ("to the TSA") and published a universal.
  **Prevention:** when copying a governing sentence into published prose, diff it against the
  source and treat every removed qualifier as a claim widening.
- **Applied a CLO-drafted sentence verbatim without checking its premise.** **Prevention:**
  drafted wording is authoritative for POSTURE, never for facts about sibling documents — grep
  the documents it asserts things about.
- **Created a false warranty by removing a true attribution** (§11.2). **Prevention:** after
  removing an entity from a list, re-read what the surviving entry now asserts.
- **Reported a 6-row mutation battery as comprehensive when it edited 2 axes.**
  **Prevention:** enumerate axes (SUT content / fixture shape / fixture direction / dispatch /
  member cardinality / harness), and state which were NOT edited.
- **Carried the plan's `194 of 638` into a code comment without re-deriving** (actual
  `199 of 642`). **Prevention:** the existing rule ("counts written into the artifact must be
  derived from the as-written file") applies to comments, not just assertions.
- **Built a mutation sandbox whose control was RED** (missing `knowledge-base/legal/`).
  Recovery: copied it, re-verified green before reading any row. **Prevention:** a red control
  voids every row — always run the unmutated control first.
- **Claimed a fix would clear a CI check when it only moved the failure.**
  **Prevention:** re-run the failing check, or state explicitly that the fix is partial.
- **Attempted three scope-outs the CONCUR gate correctly rejected.** **Prevention:** before
  filing, ask what the repo's own conventions offer at ~10 lines; the amendment-note and
  recorded-exclusion patterns existed in the file being edited.
- **`rm -rf` on a scratch dir denied by the workspace guard.** One-off; used `mktemp -d`.
- **A test scenario's predicted gate was wrong** (T7: `legal-doc-consistency` rc=0,
  `mirror-drift` rc=1). The property holds via a different gate. **Prevention:** verify which
  gate catches a scenario rather than asserting it.
- **Forwarded from the planning phase** (`session-state.md`): a wrong prescribed path; a
  Session Summary emitted before a spawned review agent returned (which then found a P0); an
  acceptance criterion that could never pass (`grep -c '^-'` matches the unified-diff header
  `--- a/<path>`); a row owned by no phase; a row count wrong twice; the plan file corrupted
  twice by `str.index` splices matching prose instead of headings. **Prevention:** the
  unsatisfiable-AC one is the sharpest — an AC whose cheapest field fix is to weaken the very
  assertion it guards is worse than no AC.

## Key Insight

**A correction PR is the highest-risk place for the defect class it is correcting.** The
author is holding the old wrong text in mind, writing replacement prose fast because it feels
like cleanup rather than authorship, and every gate is green because the gates compare hashes
and headings rather than truth. Five merge-blockers, all self-inflicted, all the same class,
past a green 343-suite battery and 71 green CI checks.

The corollary for review: **on a fix PR, review the NEW assertions before the new code** — and
when the deliverable is a guard, ask what implementation would satisfy every row, not whether
the rows pass.
