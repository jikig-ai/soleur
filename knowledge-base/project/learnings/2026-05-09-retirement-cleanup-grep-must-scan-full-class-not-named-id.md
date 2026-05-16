---
date: 2026-05-09
category: best-practices
tags: [plan-skill, deepen-plan-skill, agents-md, rule-ids, multi-agent-review, verification-grep-scope]
issue: "#3489"
pr: "#3491"
synced_to: [plan]
---

# Learning: Retirement-cleanup plans must verify the full retired/fabricated class in edited files, not just the named target ID

## Problem

PR #3491 swept the retired AGENTS.md rule ID `cq-gh-issue-label-verify-name` from 4 active operator-facing files. The plan's AC4 prescribed two verification greps after the sweep:

```bash
grep -rEn "cq-gh-issue-label-verify-name" --include="*.md" plugins/ knowledge-base/engineering/   # zero hits
grep -E "(cq-ci-...|cq-workflow-...|hr-in-github-...|hr-github-...|cq-gh-issue-create-milestone-takes-title)" \
  knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md   # zero hits
```

Both greps passed locally. PR was about to ship. Multi-agent review (`pattern-recognition-specialist` and `code-quality-analyst` independently) then surfaced **5 additional retired/fabricated active citations** that the AC's named-ID greps missed:

| File | Line | Cited ID | Status |
|---|---|---|---|
| `drain-labeled-backlog/SKILL.md` | 40 | `hr-before-running-git-commands-on-a` | retired 2026-04-23 |
| `drain-labeled-backlog/SKILL.md` | 139 | `cq-gh-issue-create-milestone-takes-title` | retired 2026-04-23 |
| `cloud-scheduled-tasks.md` | 132 | `cq-doppler-service-tokens-are-per-config` | retired 2026-04-24 |
| `plan/SKILL.md` | 707 | `cq-when-a-plan-scopes-agent-native-parity` | fabricated (not in AGENTS.md, not retired) |
| `ux-audit/SKILL.md` | 140 | `hr-in-github-actions-run-blocks-never-use` | retired 2026-04-24 |

Three of these were in files the PR was already editing — they were sweep-misses, not pre-existing-unrelated.

## Root Cause

The plan's AC verification grep was **named-target-specific**, not **class-wide**. The plan author treated the issue's enumerated 5 retired IDs as the closed scope of the verification, missing that the same files contained other retired/fabricated IDs of the same class. Two compounding factors:

1. **The issue body was the plan's verification scope.** The issue at #3489 listed exactly 5 retired-ID citations the author had grepped for. The plan inherited that scope rather than widening to the file class.
2. **No part of the plan or deepen-plan skill prescribed a class-wide rule-ID audit on the edited files.** AC line 95's "plan-internal rule-ID self-check" did require active-citation verification for every `\b(hr|wg|cq|rf|pdr|cm)-` token *cited as active rationale*, but that check was scoped to "the **edited files** (after the sweep)" with no precondition that it run **before** the verification grep — and in practice the sweep author treated the named-ID grep as the verification, never running the broader audit.

Same root-cause class as `2026-05-09-llm-authored-plans-cite-fabricated-and-retired-rule-ids.md` — that learning was about plans **citing** retired/fabricated IDs; this learning is about retirement-cleanup plans **leaving** them in place because the verification scope was too narrow.

## Solution

Widen any retirement-cleanup AC's verification grep to scan the full class in the edited files, not just the named target IDs:

```bash
# (a) every retired ID from the registry, in every edited file
while IFS=' | ' read -r id _date _pr _bc; do
  hits=$(grep -En "\b${id}\b" <each edited file>)
  [[ -n "$hits" ]] && echo "RETIRED-CITATION: ${id}"
done < scripts/retired-rule-ids.txt

# (b) every rule-ID-shaped token in edited files; reject any not in active AGENTS.md
grep -oE '\b(hr|wg|cq|rf|pdr|cm)-[a-z0-9-]+\b' <each edited file> | sort -u | while read -r id; do
  grep -qE "\[id: ${id}\]" AGENTS.md || echo "FABRICATED-OR-RETIRED: ${id}"
done
```

PR #3491's recovery applied both fixes inline (commit `a9c19833`): all 5 missed citations replaced with inline rationale or pointer to canonical owner. Final verification across all 5 edited files for all 9 swept IDs returned 0 active-citation hits.

## Prevention

1. **Plan-skill / deepen-plan Sharp Edge:** When prescribing a retirement-cleanup AC, the verification grep MUST scan all retired IDs from `scripts/retired-rule-ids.txt` AND all rule-ID-shaped tokens unresolvable in active AGENTS.md, on the **full set of edited files**. Named-target-only greps return false-pass for the class.
2. **Multi-agent review is the load-bearing safety net here**, same as in #3486 — `pattern-recognition-specialist` and `code-quality-analyst` independently grep the broader class. The fix to plan/deepen-plan reduces but does not eliminate the need.
3. **Apply this learning to the canonical case that exposed it (PR #3491)**, per `wg-when-fixing-a-workflow-gates-detection`: this learning + the inline recovery on the 5 missed citations satisfies the retroactive-application requirement.

## Cross-references

- `knowledge-base/project/learnings/2026-05-09-llm-authored-plans-cite-fabricated-and-retired-rule-ids.md` — the prior-day companion: plans **citing** fabricated/retired IDs. This learning is the cleanup-direction corollary.
- `plugins/soleur/skills/deepen-plan/SKILL.md:557` — the AC line that codified rule-ID active-status verification (PR #3486). This learning generalizes its scope to retirement-cleanup ACs.
- PR #3486 — the canonical inline-fix pattern that #3489 was sweeping. The pattern itself was sound; only the AC's verification scope was narrow.

## Session Errors

- **Plan AC verification scope was named-ID-specific, not class-wide.** Recovery: multi-agent review's broader rule-ID grep surfaced the 5 misses; inline-fixed in commit `a9c19833`. Prevention: codify a class-wide retirement-cleanup grep recipe in `plan/SKILL.md` Sharp Edges (proposed below).
