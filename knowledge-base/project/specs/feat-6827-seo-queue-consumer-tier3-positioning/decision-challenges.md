# Decision Challenges — feat-6827 (plan-review, 2026-07-22)

Six-reviewer plan-review panel (DHH, Kieran, code-simplicity, architecture-strategist,
spec-flow-analyzer, CMO) on
`knowledge-base/project/plans/2026-07-22-feat-seo-queue-contract-and-competitor-claim-substantiation-plan.md`.
Both panels (simplification + correctness) fired on the same scope — the plan-review contract's
"prefer revise over proceed" signal. Operator adjudicated the User-Challenge items.

## User-Challenge decisions (operator-selected)

| # | Decision | Choice | Rationale |
|---|---|---|---|
| UC-1 | Keep FR6 (drain-delta detector)? | **Cut; keep the enrolled soak probe** | DHH + code-simplicity: ceremony for a ~1-row/fire queue; the soak probe already asserts the same `generated_date` delta. Architecture: FR6's workflow wiring self-cancels (green age verdict auto-closes the drain alert). |
| UC-2 | Keep FR8 (bind substantiation rule to `*vs-*` diffs)? | **Cut** | DHH + code-simplicity: restates a rule that already exists in `brand-guide.md` + `review/SKILL.md`, gates nothing. Spec-flow: its `*vs-*` trigger wouldn't even catch `content-strategy.md`/`business-validation.md`. Real gap (claim-keyed repo-wide enumeration) routed to a follow-up. |
| UC-3 | PR structure? | **Split** | Ship FR1/FR2/FR7 (low-risk factual corrections, ready) as PR #6830 now; re-plan FR3/FR4/FR5 with the reserved-token redesign as a follow-up PR. The pipeline change needs a mechanism revision before it is safe (see verified regression below). |

## Verified regression that forced the pipeline split (Mechanical — not optional)

The plan's FR3/FR4/FR5 as written would make the **live** `cron-content-generator` (2x/week) worse:

- **Decoy attractor (architecture HIGH-1, Kieran #5, DHH #1) — CONFIRMED by direct count.** Below
  `## Refresh Schedule` there are **11 rows** carrying `Stale`/`Create` with no `generated_date`
  (several with retired March-era figures), versus **0** intended-eligible rows in §2.1/§2.2 today.
  The plan's positive substring predicate (`Status contains Stale/Create AND no generated_date`)
  would make all 11 eligible — pointing the live cron at stale competitor claims, the exact
  2026-07-20 incident class. AC10 is scoped to §2.1/§2.2, so it goes green while the hazard stands.
- **Convergent fix (3 reviewers independently):** eligibility must be a **reserved token / typed
  field**, not the presence of an English word in a free-text `Status` cell. This is a mechanism
  redesign, deferred to the follow-up PR with the rest of FR3/FR4/FR5.

## Mechanical corrections folded into the (now docs-only) plan

- **FR1 undercount → repo-wide claim family.** 7 sites in the distribution twin (`:13,:25,:45,:53,
  :76,:98,:136`), plus `content-strategy.md:154` (8th, no blog twin — twin-diff blind) and
  `business-validation.md:84` (9th, outside `marketing/`). AC1 rewritten from
  `grep marketing/ "14\.6k"` to a repo-wide claim-family grep (`14\.6k|14,600|14600`) with a
  **named, asserted** exclusion set (`**/audits/**`, `**/archive/**`, `todos/`,
  `knowledge-base/project/{learnings,plans,brainstorms,specs}/`, `*-digest.md`) plus a per-class
  count assertion, and a positive assertion (`grep -c '74,000+' … = expected`). Directory-scoping
  the numerator was the same defect class as spelling-scoping it (spec-flow #1).
- **CMO copy fixes.** `:25` verb ("hit 14.6k" → "has passed 74,000", matching the blog twin's
  register, not "hit 74,000+"); correction disclosure goes in frontmatter / HTML comment, not post
  body copy (these lines are pasted to social); retrieval date `(verified 2026-07-20)` at the two
  long-form sites only.
- **Named carve-outs (leave, name in PR body):** `marketing/audits/*` (4 dated records),
  `support/community/2026-04-16-digest.md:77` (dated digest).

## Distinct findings routed to follow-ups (not this PR)

- **Pipeline redesign** (FR3/FR4/FR5 + reserved-token eligibility + decoy neutralization + STEP 5
  annotate-hop fix + block-scoped anchor test written RED first + ADR-133) → new issue, references
  #6827 (does not close it).
- **Battlecard `30,000+` sweep** — `sales/battlecards/tier-3-paperclip.md` carries a *different*
  stale star value (5 occurrences) woven into convergence-trigger narrative ("crossed in three
  weeks", "trigger fired at 30k", "next escalation 100k"). Correcting it reconciles trigger logic,
  not just a token → own issue.
- **Claim-keyed repo-wide substantiation enumeration** (the method-completeness gap FR8 couldn't
  close) → routed into existing #6838 (twin-drift gate).
- **STEP 5 annotate hop** (spec-flow #4): STEP 5 names no row/section, so under a positive
  predicate a misplaced annotation regenerates the same row every fire → carried into the pipeline
  redesign issue.

## Correction logged during /work (2026-07-22) — FR7 premise was wrong

The brainstorm/CMO premise "pricing, revenue-share, memory, data ownership NOT stated on
cofounder.co" came from a single **landing-page** WebFetch. During implementation the cited
subpages were checked: pricing + ownership-graduation are stated verbatim on `cofounder.co/pricing`,
and the three-tier / sleep-time-compute memory system on the cited GIC post. So nearly all
convergence claims ARE substantiated; only "no revenue share" remains an inference. Takeaway #7 was
written to the CORRECTED split, not the original premise. This is itself an instance of the issue's
own defect class — asserting a claim's status without checking every cited source — so it is carried
into the deferred #6850/#6827 positioning work as an explicit caution.
