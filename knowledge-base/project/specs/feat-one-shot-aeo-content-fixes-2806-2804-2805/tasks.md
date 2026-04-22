---
feature: feat-one-shot-aeo-content-fixes-2806-2804-2805
plan: knowledge-base/project/plans/2026-04-22-refactor-drain-agents-vision-homepage-aeo-content-fixes-plan.md
branch: feat-one-shot-aeo-content-fixes-2806-2804-2805
closes:
  - "2806"
  - "2804"
  - "2805"
---

# Tasks — Drain /agents/, /vision/, / homepage AEO+content fixes

## 1. Pre-flight (Setup)

1.1. Verify branch and worktree. `git branch --show-current` returns `feat-one-shot-aeo-content-fixes-2806-2804-2805`.

1.2. `grep -n "hero-def\b" plugins/soleur/docs/css/style.css` — expected no match. If no match, use bare `<p>` in agents.njk definition. If match, include `class="hero-def"`.

1.3. `grep -rn "Soleur AI Agents\|world's first\|GitHub Stars" plugins/soleur/ --include="*.njk" --include="*.js" --include="*.ts" --include="*.sh"` — snapshot the "before" hit count. Expected: 2 `agents.njk`, 1 `vision.njk`, 4 GitHub Stars occurrences (index + community).

1.4. Read `plugins/soleur/docs/css/style.css:460-495` to confirm `.landing-stat-value` and `.landing-stat-label` rule locations before CSS insertion.

## 2. Edits (in blast-radius order)

### 2.1. vision.njk — #2804 superlative removal

2.1.1. Read `plugins/soleur/docs/pages/vision.njk` lines 20-30.
2.1.2. Edit line 24: replace `the world's first` with `one of the first`. No other text changes.

### 2.2. index.njk — #2805 hero stats remediation

2.2.1. Read `plugins/soleur/docs/index.njk` lines 35-55.
2.2.2. Delete the 4th `<div class="landing-stat">` block (previously lines 49-54, the GitHub Stars tile).
2.2.3. Wrap AI Agents tile value (previously line 43) in `<a href="/agents/" data-last-verified="2026-04-22">{{ stats.agents }}</a>`.
2.2.4. Wrap AI Agents label in `<a href="/agents/">AI Agents</a>`.
2.2.5. Wrap Skills tile value (previously line 46) in `<a href="/skills/" data-last-verified="2026-04-22">{{ stats.skills }}</a>`.
2.2.6. Wrap Skills label in `<a href="/skills/">Skills</a>`.

### 2.3. style.css — CSS continuity for anchor-wrapped stats

2.3.1. Read `plugins/soleur/docs/css/style.css:485-495` to confirm insertion point (immediately after `.landing-stat-label` closing brace).
2.3.2. Insert the scoped rule block:

```css
  .landing-stat-value a,
  .landing-stat-label a {
    color: inherit;
    text-decoration: none;
  }
  .landing-stat-value a:hover,
  .landing-stat-label a:hover {
    text-decoration: underline;
  }
```

### 2.4. skills.njk — #2805 P0.X2g follow-through

2.4.1. Read `plugins/soleur/docs/pages/skills.njk:8-13`.
2.4.2. Edit line 11: wrap `{{ stats.skills }} workflow skills` in `<span data-last-verified="2026-04-22">…</span>`.

### 2.5. agents.njk — #2806 title + H1 + definition + freshness

2.5.1. Read `plugins/soleur/docs/pages/agents.njk:1-15`.
2.5.2. Edit frontmatter: replace `title: Soleur AI Agents` with:

```yaml
title: "65 AI Agents for Solo Founders"
seoTitle: "65 AI Agents for Solo Founders — Every Department | Soleur"
```

2.5.3. Edit line 10: replace `<h1>Soleur AI Agents</h1>` with `<h1>Your AI Organization: {{ stats.agents }} Specialists Across {{ stats.departments }} Departments</h1>`.

2.5.4. Insert new `<p>` between `<h1>` and the existing hero tagline `<p>` with R6 definition text:

```html
<p>An AI agent is a specialist that handles a specific business function — code review, brand strategy, legal compliance, financial planning. Soleur agents share one knowledge base, so decisions in marketing flow through to legal and operations without re-briefing. Your expertise sets direction. The agents execute.</p>
```

2.5.5. Edit the existing hero tagline `<p>`: wrap `{{ stats.agents }} AI agents` in `<span data-last-verified="2026-04-22">…</span>`. NO hyperlink.

## 3. Build + Validate

3.1. `cd plugins/soleur/docs && npm run docs:build` — must exit 0. `cd ../../../` back to repo root.

3.2. Run static drift-guard grep sweep (copy from plan §Test Scenarios §1). All expected counts must match.

3.3. `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site` — must exit 0.

3.4. `bash plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh _site` — must exit 0.

3.5. `bun test plugins/soleur/test/` — all green (no drift from edits; key test: `jsonld-escaping.test.ts`).

3.6. Optional visual smoke: `cd plugins/soleur/docs && npm run docs:dev`, verify `/`, `/agents/`, `/vision/`, `/skills/` render correctly at desktop + mobile breakpoints.

## 4. Commit + PR

4.1. `/soleur:compound` pre-commit.

4.2. `markdownlint-cli2 --fix` on `knowledge-base/project/plans/2026-04-22-refactor-drain-agents-vision-homepage-aeo-content-fixes-plan.md` and this tasks.md.

4.3. Single commit: `refactor(marketing): drain /agents/, /vision/, / AEO+content fixes (#2806 #2804 #2805)`.

4.4. `/ship` — draft PR with:

- Title: `refactor(marketing): drain /agents/, /vision/, / AEO+content fixes (#2806 #2804 #2805)`
- Label: `semver:patch`
- Body MUST include three separate `Closes #N` lines (see plan §Overview).
- Body MUST include Net-impact table (PR #2486 format).
- Body MUST include `## Changelog` section.

4.5. After merge to main: post-merge operator checks per plan §Acceptance Criteria §Post-merge. Verify live site renders correctly.

## 5. Follow-ups (out of scope; file as issues when this PR merges)

5.1. File `[P1](content): /vision/ plain-language TL;DR + Company-as-a-Service definition` for content-plan P0.X2c remaining components (R9 + R10). Milestone: same as parent #2803. Labels: `priority/p1-high`, `type/chore`, `domain/marketing`. Note: `Ref #2804` in body.
