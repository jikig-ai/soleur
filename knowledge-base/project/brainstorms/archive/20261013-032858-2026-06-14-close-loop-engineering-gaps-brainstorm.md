---
date: 2026-06-14
topic: close-loop-engineering-gaps
status: complete
lane: cross-domain
brand_survival_threshold: single-user incident
branch: feat-close-loop-engineering-gaps
pr: 5257
issue: 5269
deferred_issues: [5270, 5271, 5272]
supersedes_intent: scaffold-only branch (init commit 34e851f65, draft PR #5257); original intent never committed
---

# Brainstorm: Close-Loop Engineering Gaps

## Context / How We Got Here

Resumed a **scaffold-only** branch `feat-close-loop-engineering-gaps` (single empty init
commit, zero diff vs main, placeholder draft PR #5257). The original session's intent was
never written to any committed artifact — the phrase "close-loop engineering gaps" appears
nowhere in the repo. This brainstorm **re-derives** the intent from the recent learnings
corpus (sessions dated 2026-06-09 → 2026-06-13, one written the same day the branch was
created) and then converges on scope.

**Disambiguation (load-bearing — see Session Errors #1):** Issue **#5212**
("close cross-domain *loop-engineering* gaps … to unlock 'fully cross-domain' v2 post") is a
NAME-similar but **distinct** topic — it is the *marketing* "loop-engineering positioning"
deferred work (wire business-domain agent crons + maker/checker verifier agents; child of
#5088, `domain/marketing`, P3). This brainstorm is **engineering-workflow-gate enforcement**
(repo hooks/CI/tests). The two share the word "loop" only. We did NOT co-locate under #5212.

## What We're Building

A **reusable enforcement harness** that converts prose AGENTS.md workflow gates into
**self-enforcing mechanisms** (hooks / CI / vitest), plus its first two gate instances.

The meta-problem (re-derived): many `wg-*` / `hr-*` rules exist as **prose** with **no
mechanical backstop**, so the same class of mistake recurs and is caught only at human review
or post-merge. The engineering feedback loop is *open* — corrections rely on a reviewer
re-catching each class every time.

**Why "more prose rules" is NOT the answer (resolved, not asked):** the prose lane is
budget-capped. Rule `wg-every-session-error-must-produce-either` records #2865 — *"4.7
rules/day consumed the 100→115 raise in 2 days."* The existing `wg-*` rules ARE the toothless
prose. Closing the loop means giving them teeth via mechanism, which consumes **zero rule
budget**.

### Scope (chosen: "Harness + Gaps 1 & 3")

1. **Reusable artifact/sweep-contract enforcement harness** — the close-loop primitive
   itself. Mirrors the existing 30+ paired `*.sh` + `*.test.sh` hook convention in
   `.claude/hooks/`. Future gates become *config instances*, not new harnesses.
2. **Gap 1 instance — artifact format-contract gate.** vitest validating required
   shape (frontmatter fields, exact headings, absolute URLs) on `status: scheduled|draft`
   blog + KB artifacts **regardless of authorship** — catches the hand-authored-bypass class
   at CI, not at publish time. Builds on shipped precedent
   `plugins/soleur/test/distribution-content-format.test.ts` (#5088).
3. **Gap 3 instance — sweep-completeness gate.** CI check over `git diff --name-only`:
   fail a PR that edits one member of a registered sibling-set and leaves a registered
   sibling untouched. Pure set-math (`edited-set ⊇ registered-group`). Directly fixes two
   recent session errors (2026-06-11 cross-file drift guards; 2026-06-13 error #6 — missed a
   3rd sibling test file). Aligns with `hr-write-boundary-sentinel-sweep-all-write-sites`.

## Why This Approach

- **Highest leverage.** One enforcement substrate; Gaps 3/4/6 later become config, not code
  (CPO's "harness seed" point). Building the *pattern* is itself the loop-closing act.
- **Zero rule-budget cost.** Both gates are mechanism, not new AGENTS.md prose.
- **Lowest novelty risk.** Both surfaces are proven in-repo: paired hook convention +
  `pr-quality-guards.yml` CI lane + the shipped `distribution-content-format.test.ts`.
- **Deterministic.** Both chosen gates are pure shape/set checks — no LLM judgment, so no
  false-positive friction that operators would route around.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Fix lane | New mechanisms (hooks/CI/tests), NOT new prose rules | Rule budget capped (#2865); prose rules already exist and lack teeth |
| Scope | Reusable harness + Gap 1 + Gap 3 | Operator choice; highest leverage; deterministic pair |
| Gap 1 surface | vitest CI format-contract (extends #5088 precedent) | Authorship-agnostic; catches bypass at CI not publish |
| Gap 3 surface | CI check on `git diff` (set-math) | Pure determinism; fixes 2 recent session errors |
| Gaps 2, 5, 6 | **Deferred** — LLM-judgment gates | A keyword grep false-positives (friction) or false-negatives (semantic miss); belong in agent prompts, not deterministic hooks |
| Gap 4 | **Deferred** — only partially deterministic | Detecting the label is easy; proving a Playwright attempt *happened* is evidence-bound. Strong user-impact (ties to standing "never defer operator actions" feedback) → re-eval after harness lands |
| Gap 7 | **Deferred** — too heterogeneous for one check | If pursued, scope to one slice ("Inngest workflow lacks heartbeat-on-final-attempt"), not the class |
| Tracking | New issue #5269 (NOT #5212); defers → #5270 (gaps 2/5/6), #5271 (gap 4), #5272 (gap 7) | #5212 is the marketing loop-engineering theme; distinct scope |

## Open Questions (for the plan, not blocking)

1. **How are sibling-sets declared for Gap 3?** Recommended default: an **explicit registry**
   (a committed config listing each group, e.g. the 3 cron-parity sentinel test files;
   `*-headless.test.sh`/`*.test.sh` pairs) — deterministic, zero false positives. Secondary:
   naming-convention auto-pairing. Avoid pure inference (false-positive risk).
2. **Where does the harness live** — `.claude/hooks/` (repo-session scope) vs
   `plugins/soleur/hooks/` (plugin scope) vs a CI-only vitest? Gap 1 is naturally CI/vitest;
   Gap 3 is naturally CI-on-diff. The "harness" may be a shared **test/CI helper module**
   rather than a PreToolUse hook. Resolve at plan time against the existing pair convention.
3. **Gap 1 artifact-class registry** — which file globs + which required-shape schema per
   class (blog frontmatter vs KB frontmatter vs plan/spec). Start with the classes that have
   documented bypass evidence; do not boil the ocean.

## User-Brand Impact

- **Artifact:** the artifact/sweep-contract enforcement harness and its Gap-1
  (format-contract) and Gap-3 (sweep-completeness) gate instances.
- **Vector:** a malformed shipped artifact (plan / brand-guide / blog) or an unguarded
  cross-file sweep slips a defect to prod or to the non-technical founder because the gate
  that should have caught it was never mechanically enforced.
- **Threshold:** single-user incident.

Tagged user-brand-critical (auto, per #5175). Plan inherits
`Brand-survival threshold: single-user incident`.

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO). Legal (CLO) intentionally NOT spawned — the
scope (deterministic repo-internal hooks/CI/tests for engineering-workflow gates) has no
data-subject, credential, vendor-terms, or regulated-data surface; a CLO pass would have
been a rubber stamp, which the brainstorm skill explicitly warns against. Marketing,
Operations, Sales, Finance, Support: not relevant (internal engineering tooling).

### Engineering (CTO)

**Summary:** Scored 7 candidates on recurrence × mechanizability × blast radius. Top
deterministic wins: Gap 3 (sweep-completeness, pure set-math over `git diff`) and Gap 1
(format-contract vitest, builds on shipped precedent). Gaps 2/5/6 are LLM-judgment traps —
keep them in agent prompts, not hooks. Gap 7 has highest blast radius (reaches prod cron) but
is too heterogeneous for one check. No architecture decision triggered (no new
service/data-model/boundary). Both picks consume zero rule budget.

### Product (CPO)

**Summary:** User-impact ranking puts Gap 1 first (malformed artifacts reach the founder) and
Gap 4 second (false "operator-only" asks to non-technical users — violates the standing
"never defer operator actions" feedback). Strategic point: build Gap 1 as a **reusable
harness** so Gaps 3/4/6 become config instances — the pattern-establishing first move that is
itself the loop-closing act. Defer Gaps 2/5 (thin recurrence) and Gap 7 (premature) with
re-eval issues.

## Session Errors

1. **NAME-vs-topic collision with #5212.** The branch/worktree name
   `feat-close-loop-engineering-gaps` is name-similar to issue #5212
   ("close cross-domain loop-engineering gaps …"), but #5212 is the *marketing*
   loop-engineering-positioning deferred work (agent crons + maker/checker verifiers for a v2
   blog post), NOT engineering-workflow-gate enforcement. **Recovery:** read #5212's body,
   confirmed scope divergence, filed a NEW tracking issue instead of co-locating.
   **Prevention:** name-relevance ≠ issue-relevance — read the candidate issue's body before
   reusing it as the tracker (existing `/soleur:go` worktree-plan-vs-issue-alignment sharp
   edge, now confirmed in the reverse direction: similar name, different topic).
