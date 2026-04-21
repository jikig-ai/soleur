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

- [ ] 1.1 Invoke `soleur:copywriter` with the plan's Phase 1 brief as context. Target two files in one turn:
  - `plugins/soleur/docs/blog/2026-04-23-agents-that-use-apis-not-browsers.md`
  - `knowledge-base/marketing/distribution-content/2026-04-23-agents-that-use-apis-not-browsers.md`
- [ ] 1.2 Copywriter picks the inbound-link target (one of `06-why-most-agentic-tools-plateau.md` or `2026-04-17-repo-connection-launch.md`) and adds a one-line inbound link to the new post.
- [ ] 1.3 Verify blog frontmatter has only `title`, `seoTitle`, `date`, `description`, `ogImage`, `tags` — no `layout`/`permalink`/`ogType`.
- [ ] 1.4 Verify distribution frontmatter matches `2026-04-17-repo-connection-launch.md` format: quoted `pr_reference: "#1921"`, quoted `issue_reference: "#1944"`, relative `blog_url: /blog/agents-that-use-apis-not-browsers/`.
- [ ] 1.5 Verify distribution has exactly 5 channel headings, all matching exact strings: `## Discord`, `## X/Twitter Thread`, `## Bluesky`, `## LinkedIn Personal`, `## LinkedIn Company Page`.
- [ ] 1.6 Every X-thread tweet is prefixed `**Tweet N**` and ≤ 280 chars. (`awk '/^\*\*Tweet/{getline; if (length > 280) print NR, length}'` returns nothing.)
- [ ] 1.7 Run Phase 3 lint/build gate (see tasks 3.1-3.3) on the drafts.
- [ ] 1.8 Invoke Task `fact-checker` (`subagent_type: fact-checker`) with both drafts as context. Capture the inline `## Verification Report`.
- [ ] 1.9 If any `FAIL` or `UNSOURCED` verdicts: re-invoke copywriter with the report; soften or cite; re-run 1.7 and 1.8. Loop until `PASS`.
- [ ] 1.10 Save the final `## Verification Report` verbatim for use in PR body (Phase 5).

## Phase 2 — Hero / OG image

- [ ] 2.1 Invoke `soleur:gemini-imagegen` with the plan's Phase 2 prompt, aspect ratio `16:9`, format `PNG` (force via `img.save(..., format="PNG")`).
- [ ] 2.2 Resize/crop to 1200×630 if needed (`img.thumbnail((1200, 630))` or equivalent).
- [ ] 2.3 Save to `plugins/soleur/docs/images/blog/og-agents-that-use-apis-not-browsers.png`.
- [ ] 2.4 Verify `file <path>` reports `PNG image data, 1200 x 630`. If it reports JPEG, regenerate with forced PNG.

## Phase 3 — Lint + build verification

- [ ] 3.1 Run banned-terms grep from worktree root on both drafts:

```bash
grep -niE 'plugin|ai-powered|synthetic labor|soloentrepreneur|\bjust\b|\bsimply\b' \
  plugins/soleur/docs/blog/2026-04-23-agents-that-use-apis-not-browsers.md \
  knowledge-base/marketing/distribution-content/2026-04-23-agents-that-use-apis-not-browsers.md
```

Expected: zero hits, OR every hit is inside a fenced code block citing a verified plugin file path (reviewer confirms each exception).

- [ ] 3.2 Run `npx markdownlint-cli2 --fix` on the two draft markdowns only; expect `0 error(s)`.
- [ ] 3.3 Run `npm run docs:build` from the worktree root. Expect success and `_site/blog/agents-that-use-apis-not-browsers/index.html` present with a valid `<meta property="og:image">`.

## Phase 4 — HN Show submission text

- [ ] 4.1 Create `knowledge-base/marketing/distribution-content/2026-04-24-service-automation-hn-show.md` with frontmatter `type: hn-show`, `publish_date: "2026-04-24"`, empty `channels:`, `status: draft`, `pr_reference: "#1921"`, `issue_reference: "#1944"`, relative `blog_url`.
- [ ] 4.2 Body: title ≤ 80 chars; 2-paragraph intro leaning on the architecture-decision angle; link `knowledge-base/engineering/architecture/decisions/ADR-002-three-tier-service-automation.md`; include a "What this is NOT" paragraph labeling the 80/15/5 split as aspirational/design allocation.
- [ ] 4.3 Blog link at end of body with `utm_source=hn&utm_medium=community&utm_campaign=agents-that-use-apis-not-browsers`.
- [ ] 4.4 Lint (`npx markdownlint-cli2 --fix`) on the HN Show file.

## Phase 5 — Spec patch + ship

- [ ] 5.1 The spec patch is already applied (see commit history on this branch). Verify no remaining references to `apps/web-platform/content/blog/`, `doppler run -p soleur -c dev -- npm run build`, or a fact-checker audit file path.
- [ ] 5.2 Commit deliverables as separate commits:
  - `docs(blog): add service-automation launch post + inbound pillar link`
  - `docs(marketing): add service-automation distribution-content + HN Show cut`
- [ ] 5.3 Push; mark PR #2747 ready-for-review via `gh pr ready 2747`.
- [ ] 5.4 Update PR #2747 body: `Closes #1944`; reference `#1050 #1921`; paste the fact-checker `## Verification Report` verbatim.
- [ ] 5.5 Set semver label: `patch` (docs-only).

## Phase 6 — Schedule publish (post-merge, operator)

- [ ] 6.1 After PR #2747 merges, create a follow-up PR flipping `status: draft → scheduled` on both distribution-content files. Merge by 2026-04-22 EOD.
- [ ] 6.2 Snapshot Plausible's 7-day pre-launch traffic to `knowledge-base/marketing/analytics/2026-04-23-pre-launch-baseline.md`.
- [ ] 6.3 On 2026-04-23 verify `content-publisher.sh` cron publishes Discord / X / Bluesky / LinkedIn Personal / LinkedIn Company Page (check each surface visually).
- [ ] 6.4 Validate OG rendering on the live URL via `https://www.opengraph.xyz/url/https://soleur.ai/blog/agents-that-use-apis-not-browsers/` or equivalent. On failure, re-upload the PNG and purge Cloudflare cache.
- [ ] 6.5 On 2026-04-24 operator manually submits the HN Show from the day-2 file.
- [ ] 6.6 Run `Skill: soleur:campaign-calendar` to refresh the calendar view.
- [ ] 6.7 File one follow-up GitHub issue covering the IndieHackers + Reddit deferral (milestone `Post-MVP / Later`; re-evaluation criterion: "revisit when the project has a manual-post queue or the publisher files action-required issues for unknown channels").
- [ ] 6.8 Capture 72h retrospective via `/soleur:compound` to `knowledge-base/marketing/analytics/` with measured deltas vs. the pre-launch baseline.
