---
feature: content-service-automation
issue: "#1944"
date: 2026-04-21
plan: knowledge-base/project/plans/2026-04-21-content-service-automation-launch-plan.md
spec: knowledge-base/project/specs/feat-content-service-automation/spec.md
branch: feat-content-service-automation
worktree: .worktrees/feat-content-service-automation/
pr: "#2747"
---

# Tasks: Service-Automation Launch Content

Derived from the 2026-04-21 plan. Apply in order. Phase 5 is the pre-merge gate; Phase 6 is post-merge / operator.

## Phase 1 — Draft + fact-check loop

- [x] 1.1 Invoke `soleur:copywriter` with the plan's Phase 1 brief as context. Target two files in one turn:
  - `plugins/soleur/docs/blog/2026-04-23-agents-that-use-apis-not-browsers.md`
  - `knowledge-base/marketing/distribution-content/2026-04-23-agents-that-use-apis-not-browsers.md`
- [x] 1.2 Copywriter picks the inbound-link target (one of `06-why-most-agentic-tools-plateau.md` or `2026-04-17-repo-connection-launch.md`) and adds a one-line inbound link to the new post. (Picked `why-most-agentic-tools-plateau.md` — the actual file, no `06-` prefix in the blog dir.)
- [x] 1.3 Verify blog frontmatter has only `title`, `seoTitle`, `date`, `description`, `ogImage`, `tags` — no `layout`/`permalink`/`ogType`.
- [x] 1.4 Verify distribution frontmatter matches `2026-04-17-repo-connection-launch.md` format.
- [x] 1.5 Verify distribution has exactly 5 channel headings.
- [x] 1.6 Every X-thread tweet ≤ 280 chars (max observed: 277).
- [x] 1.7 Run Phase 3 lint/build gate on the drafts — passed (0 banned terms, 0 markdownlint errors, build writes `_site/blog/agents-that-use-apis-not-browsers/index.html`).
- [x] 1.8 Invoke Task `fact-checker` — report captured for PR body.
- [x] 1.9 Fact-check remediations applied: "30 new tests" → "20+ new tests"; "Sites API tier" → "Enterprise plan with a Sites API key". Slug-mismatch finding was a false positive (Eleventy strips date prefix from `page.fileSlug` — build output confirms).
- [x] 1.10 Verification Report saved for Phase 5 PR body.

## Phase 2 — Hero / OG image

- [x] 2.1 Attempted `soleur:gemini-imagegen` — free-tier quota exhausted (`limit: 0`) on both `gemini-3-pro-image` and `gemini-2.5-flash-image`. Fell back to Pillow geometric illustration per skill's documented fallback path.
- [x] 2.2 Rendered 1200×630 geometric scene (indigo agent glyph, glowing connection lines, 3 API endpoint icons — database, cloud, key) on dark navy.
- [x] 2.3 Saved to `plugins/soleur/docs/images/blog/og-agents-that-use-apis-not-browsers.png`.
- [x] 2.4 `file` reports `PNG image data, 1200 x 630, 8-bit/color RGB, non-interlaced`. Operator note: regenerate via paid Gemini quota before 2026-04-23 publish for higher fidelity.

## Phase 3 — Lint + build verification

- [x] 3.1 Banned-terms grep — zero hits.
- [x] 3.2 `npx markdownlint-cli2 --fix` on all three draft markdowns — `0 error(s)`.
- [x] 3.3 `npm run docs:build` — 72 files written, `_site/blog/agents-that-use-apis-not-browsers/index.html` present with valid `<meta property="og:image">`.

## Phase 4 — HN Show submission text

- [x] 4.1 Created `knowledge-base/marketing/distribution-content/2026-04-24-service-automation-hn-show.md` with correct frontmatter.
- [x] 4.2 Body: title 65 chars ("Show HN: Soleur — open-source agents that call APIs, not browsers"), 2-paragraph architecture intro with ADR-002 link, "What this is NOT" paragraph explicitly labeling the 80/15/5 split as design allocation / aspirational.
- [x] 4.3 Blog link at end with `utm_source=hn&utm_medium=community&utm_campaign=agents-that-use-apis-not-browsers`.
- [x] 4.4 `npx markdownlint-cli2 --fix` — `0 error(s)`.

## Phase 5 — Spec patch + ship

- [x] 5.1 Spec patch verified clean — no references to `apps/web-platform/content/blog/`, old Doppler build command, or fact-checker audit file path.
- [x] 5.2 Deliverables committed as two commits:
  - `79a3f273 docs(blog): add service-automation launch post + inbound pillar link`
  - `056f0282 docs(marketing): add service-automation distribution-content + HN Show cut`
- [ ] 5.3 Push; mark PR #2747 ready-for-review via `gh pr ready 2747`. (Handled by `/ship` in Phase 4 handoff.)
- [ ] 5.4 Update PR #2747 body: `Closes #1944`; reference `#1050 #1921`; paste the fact-checker `## Verification Report` verbatim. (Handled by `/ship`.)
- [ ] 5.5 Set semver label: `patch` (docs-only). (Handled by `/ship`.)

## Phase 6 — Schedule publish (post-merge, operator)

- [ ] 6.1 After PR #2747 merges, create a follow-up PR flipping `status: draft → scheduled` on both distribution-content files. Merge by 2026-04-22 EOD.
- [ ] 6.2 Snapshot Plausible's 7-day pre-launch traffic to `knowledge-base/marketing/analytics/2026-04-23-pre-launch-baseline.md`.
- [ ] 6.3 On 2026-04-23 verify `content-publisher.sh` cron publishes Discord / X / Bluesky / LinkedIn Personal / LinkedIn Company Page (check each surface visually).
- [ ] 6.4 Validate OG rendering on the live URL via `https://www.opengraph.xyz/url/https://soleur.ai/blog/agents-that-use-apis-not-browsers/` or equivalent. On failure, re-upload the PNG and purge Cloudflare cache.
- [ ] 6.5 On 2026-04-24 operator manually submits the HN Show from the day-2 file.
- [ ] 6.6 Run `Skill: soleur:campaign-calendar` to refresh the calendar view.
- [ ] 6.7 File one follow-up GitHub issue covering the IndieHackers + Reddit deferral (milestone `Post-MVP / Later`; re-evaluation criterion: "revisit when the project has a manual-post queue or the publisher files action-required issues for unknown channels").
- [ ] 6.8 Capture 72h retrospective via `/soleur:compound` to `knowledge-base/marketing/analytics/` with measured deltas vs. the pre-launch baseline.
