# Tasks: Citation Verification

## Phase 1: Setup

- [x] 1.1 Read existing marketing agents for structure reference (`copywriter.md`, `cmo.md`, `seo-aeo-analyst.md`)
- [x] 1.2 Check cumulative agent description word count baseline (`shopt -s globstar && grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w`)
- [x] 1.3 Read content-writer `SKILL.md` current phase structure

## Phase 2: Core Implementation

- [x] 2.1 Create fact-checker agent (`plugins/soleur/agents/marketing/fact-checker.md`)
  - [x] 2.1.1 Write YAML frontmatter (`name: fact-checker`, `description` under 45 words with disambiguation, `model: inherit`)
  - [x] 2.1.2 Write verification protocol in agent body: claim extraction heuristics, WebFetch protocol, evidence requirements
  - [x] 2.1.3 Define structured output contract (Verification Report with Verified/Failed/Unsourced/Summary headings)
  - [x] 2.1.4 Include edge case handling: paywalled content, JS-rendered pages, HTTP errors, rate limiting
  - [x] 2.1.5 Verify cumulative description word count stays under 2,500
- [x] 2.2 Add Phase 2.5 to content-writer skill (`plugins/soleur/skills/content-writer/SKILL.md`)
  - [x] 2.2.1 Insert Phase 2.5: Citation Verification between Phase 2 and Phase 3 with `<validation_gate>` tags
  - [x] 2.2.2 Add Task tool invocation of fact-checker agent with draft content
  - [x] 2.2.3 Parse verification report and annotate draft with PASS/FAIL/UNSOURCED status markers
  - [x] 2.2.4 Update Phase 3 presentation to show verification summary before draft
  - [x] 2.2.5 Add re-verification trigger after Edit cycles
  - [x] 2.2.6 Add graceful degradation: warn if fact-checker unavailable, continue to Phase 3
  - [x] 2.2.7 Update the passive guideline at line 124 to reference Phase 2.5 enforcement
- [x] 2.3 Add constitution rule (`knowledge-base/overview/constitution.md`)
  - [x] 2.3.1 Add `## Content` section between `## Business` and `## Specs`
  - [x] 2.3.2 Add Always/Never/Prefer rules with enforcement annotation `[enforced: fact-checker agent via content-writer Phase 2.5]`

## Phase 3: Registration Updates

- [x] 3.1 Update CMO delegation table in `plugins/soleur/agents/marketing/cmo.md` -- add fact-checker row
- [x] 3.2 Update copywriter description in `plugins/soleur/agents/marketing/copywriter.md` -- add reverse disambiguation sentence
- [x] 3.3 ~~Update `plugins/soleur/README.md` agent count (61 -> 62)~~ Skipped: constitution says "never hardcode counts in feature branches; parallel worktrees each increment from stale baselines, causing drift" -- CI reconciles at merge time
- [x] 3.4 Update `plugins/soleur/AGENTS.md` CMO specialist count (11 -> 12 in domain leader table)

## Phase 4: Verification

- [x] 4.1 Verify agent description word count is under 2,500 (result: 2,499)
- [x] 4.2 Verify content-writer skill phase numbering is consistent (0, 1, 2, 2.5, 3, 4)
- [ ] 4.3 Run markdownlint on all modified files
- [ ] 4.4 Run compound (`skill: soleur:compound`)
