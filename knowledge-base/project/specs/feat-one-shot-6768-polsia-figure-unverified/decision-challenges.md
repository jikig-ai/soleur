# Decision Challenges — feat-one-shot-6768-polsia-figure-unverified

Persisted from `plan-review` (headless arm — no TTY, `/soleur:one-shot` pipeline, plan-file-path argument). `ship` Phase 6 renders this into the PR body and files an `action-required` issue.

Mechanical findings from the 7-agent panel were auto-applied into plan v2. The items below are **Taste** or **User-Challenge** and were NOT auto-applied — they are surfaced for the operator.

---

## UC-1 — Add a competitive-claims rule to `brand-guide.md` (User-Challenge: scope addition)

**Class:** User-Challenge — adds scope the operator did not request.
**Raised by:** CMO (priority 8, "the only compounding item here").

The CMO argues this is the second time a competitor figure has gone stale on a published surface (`seo-refresh-queue.md` records a 2026-06-02 revision of the same claim), and that every fix so far has been per-instance. Proposed two-line addition to `brand-guide.md`:

> Never assert a competitor's revenue, ARR, or customer count as fact in published copy. Cite funding rounds, headcount, or public pricing — verifiable signals. Vendor-reported metrics get explicit attribution or get omitted.

**Why not auto-applied:** the operator scoped #6768 to correcting two pages. Editing the brand guide changes a standing rule for all future copy — a durable policy decision, not a figure correction.

**Recommendation:** accept. It is two lines in a file already adjacent to this work, and it is the only change here that prevents recurrence rather than repairing an instance. Plan v2 leaves it out; say the word and it folds in.

---

## UC-2 — Fold the Tier-3 positioning refresh into this PR (User-Challenge: direction change)

**Class:** User-Challenge — argues the operator's stated scope should expand.
**Raised by:** CPO (5b) and CMO (10), independently.

Both comparison pages rest their rebuttal on "founder-in-the-loop + breadth + no-lock-in". `competitive-intelligence.md:120` holds that this contrast **no longer carries** at Tier 3 post-Cofounder ($8.7M USV seed, HITL gates, 8-department breadth, no rev-share — rated *Critical — closest product match*). Stamping the pages "Updated 2026-07-20" is an implicit claim the argument is current.

**Why not auto-applied:** it is a positioning revision across all Tier-3 pages, CMO-owned, and materially larger than the figure correction. Smuggling it into a fix PR is the wrong vehicle.

**Plan v2 response:** deferred, with the Domain Review → Product line softened so it no longer reads as a clean bill of health on the page thesis, plus a follow-up issue. **Recommendation: keep deferred.**

---

## T-1 — FAQ Q3/Q4 double-anchor on Polsia's capital (Taste)

**Class:** Taste — editorial sequencing judgment.
**Raised by:** CMO (5).

After the reframe, two of four FAQ entries on the Polsia page anchor on the competitor's capital: the new Q3 ("Polsia raised $30M at a $250M valuation…") and the existing Q4 ("Is Soleur's source-available model sustainable against a venture-backed competitor?", closing *"Sustainability comes from the depth of the moat, not the size of the funding round"*). An answer engine extracting "Soleur vs Polsia" may surface two answers that both open by amplifying the raise.

CMO's read is that the ordering already works in Soleur's favour (Q3 concedes, Q4 answers) but should be sequenced as a deliberate pair — re-angle Q3's opening clause to lead with the architecture question and let the round arrive as context.

**Not auto-applied:** copy-voice judgment with no single right answer. Plan v2 leaves both questions independently framed.

---

## T-2 — Re-weight the rebuttal toward lifecycle + git-native KB (Taste)

**Class:** Taste — messaging emphasis.
**Raised by:** CMO (1).

`competitive-intelligence.md` recommendation #2 says lead with the workflow lifecycle, not agent count. Plan v2 keeps the existing output-quality/trajectory/stakes argument unchanged. CMO argues the moat that actually survives a $30M round is the named-artifact lifecycle and the git-tracked, founder-readable KB, and the rebuttal should lean there.

**Not auto-applied:** rewriting the argument's emphasis exceeds a figure correction and is a judgment call about positioning.

*(The related CMO caution — do not import CI's "reviews describe Polsia output as basic" — WAS auto-applied to plan v2, since shipping an unverified disparaging claim is the same defect class this PR fixes.)*

---

## T-3 — Fold in the blog-body pricing refresh (Taste → resolved as Mechanical)

**Class:** Originally Taste; **reclassified Mechanical and auto-applied.**
**Raised by:** CPO (4), architecture-strategist (P1), CMO (A).

Recorded for transparency because v1 deferred it. Architecture-strategist showed the deferral was **incoherent**, not merely conservative: `distribution-content/soleur-vs-polsia.md` is *generated from* the blog post via `/soleur:social-distribute` (headless auto-Overwrite), so correcting pricing only in the derived file guarantees the next generation run re-derives `$29`. That makes it a correctness finding, not a taste one. Plan v2 fixes pricing upstream in Phase 2 and keeps the still-accurate 20% rev-share arithmetic.

---

## Panel disagreement resolved on evidence (no operator action)

**DHH** argued the queued social post needed a blocking `status:` flip or its own fast PR, calling "merge promptly" *"a hope with a deadline"*. **Architecture-strategist** then measured the slot math against the live corpus: the 28-day horizon has zero free Tue/Thu slots, `planPromotions` sorts filename-ascending placing this file last of 7 ready drafts, earliest publish **2026-09-08**. There is no publish race.

Measurement beat assumption — plan v2 keeps the no-block decision but **corrects the rationale**, and reassigns the real deadline to `cron-content-generator` (Tue 2026-07-21 10:00 UTC), which DHH's framing had missed entirely.

---

## DHH process observation (not a plan finding)

DHH noted that plan v1 spent ~180 lines satisfying gates that never fired — an Observability section to announce a skip, and an 11-line C4 enumeration arguing that "blog readers are not modeled entities". He recommends a template change letting non-code change-classes emit a one-line skip. Plan v2 collapses both to one line each. **The template issue itself is unfiled** — worth raising separately if docs-class plans keep paying this tax.
