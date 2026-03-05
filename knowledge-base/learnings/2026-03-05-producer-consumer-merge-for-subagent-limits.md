# Learning: Producer-consumer merge pattern for subagent limit compliance

## Problem
Compound skill's parallel fan-out declared 6 subagents (Context Analyzer, Solution Extractor, Related Docs Finder, Prevention Strategist, Category Classifier, Documentation Writer) but constitution.md caps parallel fan-out at max 5. Discovered during SpecFlow analysis for #397, tracked in #423.

## Solution
Merged Category Classifier into Documentation Writer. The classifier's 3 outputs (category, schema validation, filename) flowed exclusively to the writer -- a classic producer-consumer pair where the producer has exactly one consumer. The merged writer gained 3 extra bullets (7 total) without meaningful wall-clock time increase.

Key verification steps:
1. Confirmed compound-capture SKILL.md has zero references to parallel subagent names (no cascading impact)
2. Confirmed constitution.md uses generic language ("the pipeline's parallel subagent limit"), not hardcoded counts
3. Confirmed Phase 1.5 Deviation Analyst text becomes accurate post-fix (was aspirational with 6 agents)
4. Updated Success Output example from 6 to 5 check-mark lines

## Key Insight
When a parallel subagent's output feeds exclusively to one other subagent, merge the producer into the consumer rather than making it sequential or raising the limit. This preserves parallelism, reduces inter-agent data flow, and avoids weakening resource guardrails. Prior art: 3 documented cases in knowledge-base/learnings/ confirm "merge scope down" consistently outperforms "expand limits up."

## Tags
category: architecture
module: compound
