---
feature: chore-blog-source-available
issue: 5043
lane: single-domain
plan: knowledge-base/project/plans/2026-06-08-chore-blog-source-available-sweep-plan.md
---

# Tasks: Soleur-subject "open source" → "source-available (BSL 1.1)" in dated blog posts (#5043)

## Phase 0 — Preconditions

- [ ] 0.1 Confirm CWD = worktree, branch = `feat-chore-blog-source-available`.
- [ ] 0.2 `bun --version` (1.3.11). Note test cmd: `bun test plugins/soleur/test/marketing-content-drift.test.ts`.
- [ ] 0.3 RED baseline: `git grep -niE "soleur is (an )?open[- ]source" -- 'plugins/soleur/docs/blog/*.md'` → expect 6.
- [ ] 0.4 Capture AC2 competitor baseline counts (CrewAI 8, Paperclip 8, Spec Kit 1).

## Phase 1 — RED (test first)

- [ ] 1.1 Extend Test 2c in `plugins/soleur/test/marketing-content-drift.test.ts` with a Soleur-subject "open source" `OFFENDER` clause over the blog walk (mirror Test 2b shape).
- [ ] 1.2 Verify the candidate regex against the oracle sets: MUST match all 11 in-scope Soleur-subject lines; MUST NOT match `why-most-agentic-tools-plateau.md` L39, CrewAI L20/L74, Paperclip L26, the `Yes (MIT)` cell, or the bare `- open-source` frontmatter tag.
- [ ] 1.3 Run suite → Test 2c FAILS; confirm the offender list enumerates only Soleur-subject lines (no KEEP line present). If a KEEP line appears, tighten the regex before sweeping.

## Phase 2 — GREEN (sweep + comments)

For each file, Read before Edit; edit JSON-LD + its mirrored prose in the same pass.

- [ ] 2.1 `2026-03-16-soleur-vs-anthropic-cowork.md` — L25, L84 (cell), L88 (cell), L112, L135.
- [ ] 2.2 `2026-03-17-soleur-vs-notion-custom-agents.md` — L24, L91 (cell), L111, L129.
- [ ] 2.3 `2026-03-19-soleur-vs-cursor.md` — L72, L106, L142 (JSON-LD sync with L106).
- [ ] 2.4 `2026-03-26-soleur-vs-polsia.md` — L80, L122, L124, L157 (JSON-LD name), L160 (JSON-LD answer).
- [ ] 2.5 `2026-03-29-your-ai-team-works-from-your-actual-codebase.md` — L70.
- [ ] 2.6 `2026-03-31-soleur-vs-paperclip.md` — **FR2 separate**: L3 seoTitle, L5 description, L49, L84 (Soleur cell only), L129, L133 (Soleur clause only), L177 (JSON-LD, Soleur clause only). KEEP: L11 tag, L26, L131, L174. No "both open-source".
- [ ] 2.7 `2026-04-21-soleur-vs-devin.md` — L72, L74, L117 (Soleur cell/label only).
- [ ] 2.8 `2026-04-23-agents-that-use-apis-not-browsers.md` — L5 description, L14, L67.
- [ ] 2.9 `2026-05-05-soleur-vs-tanka.md` — L82, L115 (Soleur cell/label only).
- [ ] 2.10 `2026-05-07-soleur-vs-crewai.md` — L72 (heading rename, license-neutral), L76, L108 (Soleur cell only; keep `Yes (MIT)`), L127, L163 (JSON-LD sync with L127). KEEP: L20, L74.
- [ ] 2.11 `2026-05-12-company-as-a-service-platform.md` — L66.
- [ ] 2.12 Update deferral comments: Test 2b L160-161 + Test 2c L190 → "resolved (#5043)". Zero "deferred to #5043" remain.

## Phase 3 — Verify (AC gate)

- [ ] 3.1 `bun test plugins/soleur/test/marketing-content-drift.test.ts` → all green.
- [ ] 3.2 AC1: `git grep -niE "soleur is (an )?open[- ]source" -- 'plugins/soleur/docs/blog/*.md'` → 0.
- [ ] 3.3 AC1b/AC2: `git grep -niE "open[- ]source" -- 'plugins/soleur/docs/blog/*.md'` residual = only competitor/ecosystem + kept tag; CrewAI/Paperclip/Spec-Kit counts unchanged.
- [ ] 3.4 AC5: `git grep -ni "both open-source" 2026-03-31-soleur-vs-paperclip.md` → 0.
- [ ] 3.5 AC4: `npm run docs:build` exits 0; swept JSON-LD renders in `_site/` matching prose.
- [ ] 3.6 AC3b: `grep -n "deferred to #5043\|resolved (#5043)" plugins/soleur/test/marketing-content-drift.test.ts` shows resolved, zero deferred.
