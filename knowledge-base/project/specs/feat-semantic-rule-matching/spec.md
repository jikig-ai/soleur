# Semantic Rule Matching for Rule Audit CI

**Feature:** feat-semantic-rule-matching
**Created:** 2026-03-30
**Status:** Draft
**GitHub Issue:** #1304

## Problem Statement

The rule audit CI (`scripts/rule-audit.sh`) detects rule budget overages and hook-enforced annotations but cannot detect paraphrased duplicate rules across governance layers. At 313 always-loaded rules (exceeding the 300 threshold), cross-layer duplication from rewording is increasingly likely but invisible to exact matching.

## Goals

1. Detect suspected duplicate rules across all governance layers using word-based similarity
2. Report findings in the existing bi-weekly rule audit issue
3. Suppress intentional duplicates (hook-enforced, skill-enforced annotations)
4. Maintain zero-dependency pure bash implementation

## Non-Goals

- Semantic/embedding-based similarity (deferred to v2 if Jaccard proves insufficient)
- Real-time detection at commit time (compound Phase 1.5 integration)
- Automated rule retirement or merge suggestions
- Threshold configuration via CLI flags

## Functional Requirements

| ID | Requirement |
|----|-------------|
| FR1 | Extract bullet-point rules (`^-`) from AGENTS.md, constitution.md, agents/**/*.md, and skills/*/SKILL.md |
| FR2 | Compute Jaccard word similarity between all rule pairs after stopword removal |
| FR3 | Flag pairs with Jaccard coefficient >= 0.6 as suspected duplicates |
| FR4 | Suppress pairs where either rule contains `[hook-enforced]` or `[skill-enforced]` annotations |
| FR5 | Add a "Suspected Duplicates" table to the issue body with source file, line number, score, and truncated text |
| FR6 | Report duplicate count in the summary statistics |

## Technical Requirements

| ID | Requirement |
|----|-------------|
| TR1 | Implement as Phase 2.5 in `scripts/rule-audit.sh` (between hook extraction and issue body generation) |
| TR2 | Pure bash/awk — no external dependencies |
| TR3 | Complete all pairwise comparisons in < 30 seconds for up to 500 rules |
| TR4 | Stopword list includes standard English words plus governance modals (must, should, always, never) |
| TR5 | Existing CI workflow (`rule-audit.yml`) requires no changes beyond timeout adjustment if needed |

## User Story

**As a** Soleur maintainer
**I want** the bi-weekly rule audit to flag rules that appear to say the same thing in different words
**So that** I can consolidate or retire redundant rules and keep the governance layers lean

**Acceptance criteria:**

- Phase 2.5 runs after hook extraction, before issue body generation
- Pairs above 0.6 Jaccard (after stopword removal) appear in a "Suspected Duplicates" table
- Pairs with `[hook-enforced]` or `[skill-enforced]` annotations are excluded
- The script remains pure bash with no new dependencies
- Dry run mode (no GH_TOKEN) shows the duplicates table in stdout

## Technical Design

### Jaccard Similarity

```text
jaccard(a, b) = |intersection(words_a, words_b)| / |union(words_a, words_b)|
```

- Tokenize by whitespace
- Lowercase all tokens
- Remove stopwords (English common words + governance modals)
- Compare word sets

### Stopword List

Standard English stopwords plus domain-specific modals:

```text
a an the is are was were be been being have has had do does did
will would shall should may might can could must to of in for on
at by with from as into through during before after above below
between out off over under again further then once here there when
where why how all both each few more most other some such no nor
not only own same so than too very and but or if it its this that
these those he she they them their what which who whom
always never
```

### File Scanning

```bash
# Extract rules from all governance layers
find "$REPO_ROOT" -path '*/agents/*.md' -o -path '*/skills/*/SKILL.md' | \
  xargs grep -Hn '^- ' >> "$ALL_RULES_FILE"
grep -Hn '^- ' "$AGENTS_MD" >> "$ALL_RULES_FILE"
grep -Hn '^- ' "$CONSTITUTION_MD" >> "$ALL_RULES_FILE"
```

### Suppression

Skip any pair where either rule matches `\[hook-enforced:` or `\[skill-enforced:`.

### Output Format

```markdown
## Suspected Duplicates

| Score | File A | Line | File B | Line | Rule A (truncated) | Rule B (truncated) |
|-------|--------|------|--------|------|--------------------|--------------------|
| 0.73  | AGENTS.md | 12 | constitution.md | 45 | Never commit directly... | Do not commit to main... |
```

## References

- [GitHub Issue #1304](https://github.com/jikig-ai/soleur/issues/1304)
- [Brainstorm Document](../../brainstorms/2026-03-30-semantic-rule-matching-brainstorm.md)
- [Parent Issue #451](https://github.com/jikig-ai/soleur/issues/451)
- [Archived Fuzzy Dedup Spec](../../specs/archive/20260210-122909-feat-fuzzy-dedup/spec.md)
