---
feature: competitor-claim figure corrections + Cofounder takeaway substantiation (docs-only PR)
issue: 6827
branch: feat-6827-seo-queue-consumer-tier3-positioning
pr: 6830
plan: knowledge-base/project/plans/2026-07-22-feat-seo-queue-contract-and-competitor-claim-substantiation-plan.md
decision_challenges: knowledge-base/project/specs/feat-6827-seo-queue-consumer-tier3-positioning/decision-challenges.md
lane: cross-domain
brand_survival_threshold: single-user incident
date: 2026-07-22
---

# Tasks — Competitor-Claim Figure Corrections (docs-only)

**Scope narrowed by plan-review (2026-07-22).** This PR ships only the low-risk factual
corrections (FR1/FR2 + FR7). The pipeline mechanism (FR3/FR4/FR5) was split to **#6850** after
six reviewers found the planned substring predicate would make the live cron worse (decoy
attractor — see `decision-challenges.md`). FR6 and FR8 were cut. The battlecard `30,000+`
correction is **#6851**. All are `Ref #6827`, which stays open.

**No product code, no cron edits, no test changes** — this is a documentation/marketing-copy diff.

## Phase 0 — Baseline

- [ ] **0.1** Re-run the repo-wide claim-family sweep and confirm the write-site inventory below is
      still complete (a parallel edit could have moved a site):
      `grep -rniE '14\.6k|14,600|14600' --include='*.md' --include='*.njk' knowledge-base plugins apps`
- [ ] **0.2** Note the blog twin's canonical register verbatim
      (`plugins/soleur/docs/blog/2026-03-31-soleur-vs-paperclip.md:15,17`): "has passed 74,000
      GitHub stars", "above 74,000 (verified against the GitHub API for `paperclipai/paperclip`)".
      Match this wording; do NOT invent a new phrasing.

## Phase 1 — FR1 + FR2: correction sweep (claim-family-first)

**Method: grep the claim, not the twin.** The twin-diff method is structurally blind to sites
1.3 and 1.4 (no blog twin), which is the failure class this cycle exists to close.

- [ ] **1.1** Correct all **seven** stale figures in
      `knowledge-base/marketing/distribution-content/2026-04-15-soleur-vs-paperclip.md`
      (`:13`, `:25`, `:45`, `:53`, `:76`, `:98`, `:136`) to the `74,000+` soft-floor form.
      `:53` is the `14,600+` comma form.
- [ ] **1.2** **(CMO H1)** `:25` reads "Paperclip **hit** 14.6k GitHub stars" — a bare token swap
      to "hit 74,000+" is unidiomatic (reads as a milestone crossed at exactly the floor). Change
      the verb to match the blog twin's register: "**has passed** 74,000 GitHub stars". The other
      six sites are appositive/parenthetical and take the token swap cleanly.
- [ ] **1.3** Preserve each sentence's surrounding clause — do not re-point a dependent clause onto
      the new figure. A 5x scale change can invalidate the argument built around it; re-read each
      site and confirm no sentence now over/under-claims (CMO confirmed framing survives — verify).
- [ ] **1.4** **(CMO H2)** The dated correction disclosure does NOT go in post body copy (every
      line under a `##` here is pasted to Discord/X/Bluesky/LinkedIn). Put it in **frontmatter**
      (add a `corrections:` key) or an HTML comment **above the first `##`**:
      `Updated 2026-07-22: Paperclip star count 14,600+ → 74,000+ (GitHub API, paperclipai/paperclip).`
- [ ] **1.5** **(CMO M2)** Add `(verified 2026-07-20)` substantiation at the two long-form sites
      only (`:53`, `:76`); do NOT add citation apparatus to the short social fragments.
- [ ] **1.6** Correct `knowledge-base/marketing/content-strategy.md:154`
      (`Paperclip (14.6k GitHub stars, MIT-licensed)` → `74,000+`) and bump its `last_updated` /
      `last_reviewed`. Live weekly-reviewed CMO doc, **no blog twin**.
- [ ] **1.7** Correct `knowledge-base/product/business-validation.md:84`
      ("14.6k GitHub stars in 10 days" → the soft-floor form; drop or re-verify the "in 10 days"
      framing, which the blog twin abandoned). **Numeric-claim correction only — no positioning
      edit** (NG2 boundary; spec-flow guard).

## Phase 2 — FR7: substantiate Cofounder takeaway #7

- [ ] **2.1** Rewrite `knowledge-base/product/competitive-intelligence.md` Tier-3 takeaway #7 (`:120`)
      splitting **verified** (HITL approval gates — "nothing ships without your approval"; 11-domain
      breadth — both confirmed live 2026-07-22) from **unsubstantiated** (pricing, revenue-share,
      memory architecture, data ownership / "graduation" — none stated on cofounder.co), with the
      literal tag `Retrieved 2026-07-22 from cofounder.co`.
- [ ] **2.2** Keep the `$8.7M seed / USV` funding claim (verifiable third-party signal — Built In
      NYC / Forbes / TradedVC, Dec 2025; cite it). This affects **NG2 scoping only** — do NOT
      rewrite any published comparison page.
- [ ] **2.3** Add a one-line pointer to the corrected takeaway from the Tier-3 table row so the
      next positioning cycle starts from the substantiated version.

## Phase 3 — Verification + PR

- [ ] **3.1** **AC1 (repo-wide, named carve-outs)** — the claim family returns zero OUTSIDE the
      asserted exclusion set:
      `grep -rniE '14\.6k|14,600|14600' --include='*.md' --include='*.njk' knowledge-base plugins apps`
      then subtract the named carve-outs below. No survivor outside them.
- [ ] **3.2** **AC1b (carve-outs are deliberate, not misses)** — assert each named survivor class:
      - `knowledge-base/marketing/audits/*` → 4 (dated point-in-time records)
      - `knowledge-base/support/community/2026-04-16-digest.md` → 1 (dated digest)
      - `knowledge-base/sales/battlecards/tier-3-paperclip.md` → the `30,000+` variant, **routed to
        #6851** (different value + trigger narrative; not this PR)
      - `**/archive/**`, `knowledge-base/project/{learnings,plans,brainstorms,specs}/` → own records
- [ ] **3.3** **AC-positive** — the correction actually landed:
      `grep -c '74,000+' knowledge-base/marketing/distribution-content/2026-04-15-soleur-vs-paperclip.md`
      = 7 (or 6 + the reworded `:25`); `= 1` in `content-strategy.md`; `= 1` in `business-validation.md`.
- [ ] **3.4** **AC7** — takeaway #7 contains both a "verified"/"unsubstantiated" split and the
      literal `Retrieved 2026-07-22`.
- [ ] **3.5** Markdown-lint / build-safety: confirm no table column-count drift in edited tables
      (`business-validation.md:84`, `content-strategy.md`), and no broken frontmatter.
- [ ] **3.6** PR body: the FR2 sweep result table (every file checked, divergence or not),
      **both named carve-out sets**, the three follow-ups (#6850 pipeline, #6851 battlecard, #6838
      twin-drift-gate absorbing the claim-keyed-enumeration gap), and **`Ref #6827`** (NOT `Closes`
      — #6827 stays open for the two deferred checklist items). Note the already-distributed social
      posts are deliberately left (CMO: 3 months old, ephemeral, point at the now-correct blog URL).

## Out of scope (do not touch)

Pipeline FR3/FR4/FR5 (#6850), FR6, FR8, the `soleur-vs-cofounder` page (NG1), any published-page
Tier-3 rewrite (NG2), the 7 content-row drains (NG3), dark-cron liveness (#4375/NG4), the
non-affiliation disclaimer (#6837/NG5), `product-roadmap validate` (NG6), one-issue-per-page (NG7),
the battlecard (#6851), and ADR-133 (moves to #6850 with the pipeline change).
