# Decision Challenges — feat-one-shot-7352-fullsuite-gate-post-review

Surfaced by `plan-review` (6-agent panel) on 2026-08-11. ~~This session is headless, so per the
classifier routing these are **persisted, not auto-applied**.~~ **That classification was wrong —
the session is interactive.** UC1 and UC2 were put to the operator on 2026-08-12 and are now
**RESOLVED**; see `## Operator Decisions (2026-08-12)` in the plan, which is authoritative. UC3
remains open and non-blocking. `/ship` Phase 6 renders this file into the PR body and files the
residue as an `action-required` issue.

Mechanical findings were auto-applied to the plan and are not listed here.

## Resolutions (2026-08-12)

| Item | Operator decision | Effect |
|---|---|---|
| **UC1** | **Apply CPO's C1 conditional** — *not* narrow-to-§9, *not* accept-as-is | The four project-agnostic lines are relaxed **with** the conditional. The detection question CPO routed to CTO is **in scope for `/work`**, not deferred. See plan OD1 + AC11/AC12. |
| **UC2** | **Wait for #7441 to land + combined verification** — *not* the stated proceed-now default | Implementation/review/QA run now; the **merge** is held. PR stays draft. See plan OD2 + AC13 + the Pre-merge hold (H1-H4). |
| **UC3** | Not asked | Open, non-blocking. Carried to the PR body / `action-required` issue. |

---

## UC1 — Taste — The relaxation ships to users whose repo has neither backstop

**Raised by:** `cpo` (condition C1), plan-time sign-off.

**Finding.** The plan's entire safety case rests on two backstops that exist *only in Soleur's own
repo*: CI ruleset 14145388, and the `scripts/test-all.sh` script itself. But four of the lines in
`## Files to Edit` are **project-agnostic** and ship to every self-hosted plugin user:

- `work/SKILL.md:243` — "Place a final 'Run full test suite and lint' task at the end"
- `work/SKILL.md:337` — "Run full test suite after changes"
- `work/SKILL.md:668` — "Run the full test suite after each RED/GREEN/REFACTOR cycle"
- `work/SKILL.md:818` — `# Run full test suite (use project's test command)`

§9 itself is already Soleur-coupled (it hard-codes `scripts/test-all.sh` and
`apps/web-platform/infra/`), so §9 is *not* the user-facing surface — those four lines are. In a
user's repo the relaxation lands with **no compensating gate at any position**.

**Why this is live, not hypothetical.** `knowledge-base/product/validation/2026-08-06-alpha-onboarding-motion-start.md`
records alpha tester #1 onboarded 2026-08-06 **on the self-hosted CLI plugin**, currently inside
roadmap row 4.4's 2-week unassisted-usage measurement window.

**Proposed resolution (CPO's C1).** The four generic lines carry a conditional: *when the project has
no CI-enforced full-suite gate on the merge branch, the full battery stays at implementation exit.*
This preserves the entire speed win in Soleur's repo and loses nothing elsewhere.

**Why it is not auto-applied.** It changes what the deliverable does for external users — a
user-visible scope decision, which the routing classes as Taste. It also raises an unanswered
technical question (how does the pipeline *detect* whether a project has a CI-enforced full-suite
gate?) that CPO explicitly routed to CTO at `/work` spec time.

**Operator decision needed:** apply C1 as written / narrow the change to §9 only and leave the four
generic lines untouched / accept the relaxation for external users as-is.

---

## UC2 — User-Challenge — Sequencing against the live alpha window

**Raised by:** `cpo` (condition C6).

**Finding.** Two concurrent, mutually unreadable sessions are reshaping the same gate surface —
this plan and `feat-one-shot-test-pipeline-efficiency` (draft PR #7441) — and both would land inside
the alpha tester's unassisted-usage measurement window. Changing the pipeline the measurement
subject is running contaminates the measurement (#1442 usage tracking, #1443 exit interviews) and
adds a variable to any "the pipeline broke" report.

**Proposed resolution.** Land at most one of #7352 / #7441 per verification cycle, with a combined
verification between them, and record the merge date against #1442 so the usage-tracking data stays
interpretable.

**Why it is not auto-applied.** It changes the operator's stated sequencing intent (this issue was
handed to a one-shot pipeline to run now), which the routing classes as User-Challenge — never
auto-decided.

**The 5-line frame:**

1. **Operator's stated direction:** implement #7352 now, in this pipeline run.
2. **What the challenge is:** landing it mid-alpha-window contaminates an in-flight product
   measurement, and a sibling PR is reshaping the same surface concurrently.
3. **What changes if accepted:** this PR waits for #7441 to land and verify, or vice versa; merge
   date is recorded against #1442.
4. **What it costs to accept:** delay of one verification cycle.
5. **Default if no answer:** proceed as the operator directed — the plan already treats #7441 as a
   preferred predecessor rather than a hard blocker, and nothing in this plan's file set structurally
   collides with it.

---

## UC3 — Taste — Milestone placement

**Raised by:** `cpo` (condition C8).

**Finding.** #7352 is milestoned **Post-MVP / Later**, while the active phase is **Phase 4: Validate
+ Scale**. `knowledge-base/product/roadmap.md`'s own convention states internal-tooling issues live
in the Phase 4 milestone for sequencing. By the repo's own stated rule this issue is out of phase.

**Proposed resolution.** `gh issue edit 7352 --milestone 'Phase 4: Validate + Scale'`, or record in
the plan why it stays in Post-MVP.

**Why it is not auto-applied.** Milestone placement is roadmap scope, not an engineering
correctness fix. Non-blocking for implementation.

---

## Note — roadmap drift observed, not acted on

`roadmap.md`'s `## Current State` block is dated 2026-05-25 while its frontmatter says
`last_updated: 2026-08-06`. Live GitHub counts diverge substantially (Post-MVP / Later: roadmap says
710 open / 1283 closed; API returns 1024 / 1560 — ~44% drift). Out of scope here; flagged for the
next `/soleur:product-roadmap validate`.
