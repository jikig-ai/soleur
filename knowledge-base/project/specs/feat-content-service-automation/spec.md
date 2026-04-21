---
feature: content-service-automation
issue: "#1944"
status: spec-complete
date: 2026-04-21
branch: feat-content-service-automation
brainstorm: knowledge-base/project/brainstorms/2026-04-21-content-service-automation-brainstorm.md
---

# Spec: Service Automation Launch Content

## Problem Statement

The service-automation feature shipped in PR #1921 (closes #1050) — 3 live automations, 2 guided playbooks, AES-256-GCM token storage — but has no public announcement. Phase 3 milestone passed its due date (2026-04-19) and the CMO content-opportunity gate filed issue #1944 with a prescribed brief (blog + X thread, architecture-decision angle). Brainstorm re-scoped to a founder-outcome hero angle, full 7-channel fan-out, fact-checked, with a day-2 HN Show submission.

## Goals

- Publish a single canonical blog post on `soleur.ai/blog/` by end-of-week (target Thu 2026-04-23).
- Fan out short-form content to 7 channels via `scripts/content-publisher.sh` on the same day.
- Submit architecture-angle Hacker News Show post on day-2 (Fri 2026-04-24).
- Drive a measurable CTA to `app.soleur.ai` (connect-repo surface).
- Verify every stat, quote, and URL through `soleur:marketing:fact-checker` before publish.
- Produce an OG/hero image via `soleur:gemini-imagegen` that reflects the agent-native framing.

## Non-Goals

- LinkedIn Personal architecture-angle short-form piece (deferred — HN Show covers the architecture audience).
- Video walkthrough / demo recording (deferred to a later content cycle).
- Paid promotion or influencer seeding.
- Reddit submission (untested channel per `learnings-researcher`; not in brand-guide defaults).
- Content edits to prior blog posts (lateral link-in only).
- Re-architecting the content-publisher pipeline.

## Functional Requirements

- **FR1** — Produce one blog markdown at `apps/web-platform/content/blog/2026-04-23-agents-that-use-apis-not-browsers.md` (exact filename to be confirmed against Eleventy slug convention during implementation).
  - Frontmatter: `title`, `description`, `date`, `tags` only (no `layout`, no `ogType` — inherited from `blog.json`).
  - Primary keyword "service automation" appears 8-12 times across ~3,000 words.
  - Includes a one-sentence, AI-extractable definition of *service automation* near first mention.
  - "Open source" appears in H1 or first paragraph.
  - Year 2026 in the title.
  - Lateral link to at least one of `06-why-most-agentic-tools-plateau.md`, `2026-04-17-repo-connection-launch.md`, or `2026-03-24-vibe-coding-vs-agentic-engineering.md`.
  - Primary CTA: *"Connect your repo at app.soleur.ai and let an agent provision your first service."*

- **FR2** — Produce one distribution-content file at `knowledge-base/marketing/distribution-content/2026-04-23-service-automation-launch.md`.
  - Frontmatter matches the schema used in `2026-03-29-pwa-installability-milestone.md` (`title`, `type: milestone-announcement`, `publish_date`, `channels`, `status`, `pr_reference: 1921`, `issue_reference: 1944`, `roadmap_item`).
  - Channel sections present: `## X/Twitter Thread`, `## Discord`, `## Bluesky`, `## LinkedIn Personal`, `## LinkedIn Company Page`, `## IndieHackers`.
  - UTM params on the blog link per channel (`utm_source=<channel>&utm_medium=social&utm_campaign=service-automation-2026-04`).

- **FR3** — Generate one hero image via `soleur:gemini-imagegen` and one OG-card variant. Save to `apps/web-platform/content/blog/images/2026-04-23-service-automation-hero.{png,webp}` and reference in the blog's `description` meta or frontmatter per Eleventy conventions.

- **FR4** — Run `soleur:marketing:fact-checker` against both the blog markdown and the distribution-content markdown before publish. Every numeric claim, quoted source, and external URL must resolve. Blocker gate — do not publish if any claim fails.

- **FR5** — Prepare a Hacker News Show submission (title + 2-paragraph intro) leaning on the architecture-decision angle. Save the submission text at `knowledge-base/marketing/distribution-content/2026-04-24-service-automation-hn-show.md` with frontmatter marking it day-2.

## Technical Requirements

- **TR1** — Grep-gate banned terms on every draft: `grep -niE 'plugin|ai-powered|synthetic labor|soloentrepreneur|\bjust\b|\bsimply\b'`. Empty output required before fact-check.

- **TR2** — Blog markdown passes `npx markdownlint-cli2 --fix` on the specific file path only (per rule `cq-markdownlint-fix-target-specific-paths`). Re-read after `replace_all` on any table.

- **TR3** — Soften the five claim-hazards identified in the brainstorm (tier split, SSRF, 2-4× cost, "server never touches tokens", ADR-002 on main). Fact-checker confirms the softened wording.

- **TR4** — All lines reference `app.soleur.ai` (not local install URL) for the primary CTA; community CTAs (Discord, GitHub star) are secondary.

- **TR5** — Eleventy build succeeds locally (`doppler run -p soleur -c dev -- npm run build` from `apps/web-platform/`) before PR marked ready-for-review.

## Acceptance Criteria

- Blog markdown committed at the FR1 path, passes Eleventy build with correct BlogPosting JSON-LD (no duplicate layout/ogType).
- Distribution-content markdown committed at the FR2 path, parseable by `scripts/content-publisher.sh --dry-run`.
- Hero image present and referenced; OG preview renders correctly (`curl` check on deployed URL after publish).
- Fact-checker report saved to `knowledge-base/marketing/audits/2026-04-23-service-automation-factcheck.md` with PASS verdict.
- HN Show submission text committed at the FR5 path, title ≤80 chars, 2-paragraph intro.
- PR body includes `Closes #1944` and references #1050 / #1921.
- Banned-terms grep returns empty on all three new files.

## Sequencing (implementation hints — HOW belongs in the plan)

1. Copywriter drafts blog post (FR1).
2. Copywriter drafts distribution-content (FR2).
3. Gemini-imagegen produces hero (FR3).
4. Banned-terms grep (TR1) + markdownlint-fix (TR2).
5. Fact-checker runs on both markdowns (FR4).
6. Soften flagged claims (TR3); re-run fact-checker.
7. HN Show submission text (FR5).
8. Eleventy build verify (TR5).
9. PR → review → ship → `content-publisher.sh` on publish_date → day-2 HN Show.
