# Learning: Review agent rate-limit fallback requires inline review

## Problem

During one-shot pipeline execution for #1291, all 4 review subagents
(security-sentinel, architecture-strategist, code-simplicity-reviewer,
performance-oracle) hit API rate limits simultaneously and returned zero
output. The pipeline had no fallback — review would have been silently
skipped.

## Solution

Performed inline review in the main context when all subagents failed.
Analyzed the diff manually against security, architecture, performance,
and simplicity criteria. For a 2-file, 45-line diff this was efficient
and produced a complete review with no findings.

## Key Insight

When review subagents are rate-limited, the main agent must detect the
failure (all agents returned empty/error) and perform inline review
rather than treating "no findings" as "clean code." The `/review` skill
should document this fallback explicitly.

## Session Errors

1. **Context7 MCP quota exceeded** — Monthly limit hit during plan
   phase. Recovery: fell back to codebase analysis. Prevention: monitor
   Context7 usage; no skill change needed (external limit).
2. **Review subagents rate-limited** — All 4 agents returned "out of
   extra usage." Recovery: inline review in main context. Prevention:
   `/review` skill should document the inline fallback pattern.
3. **Dev server startup failed during QA** — `supabaseUrl is required`
   error with `doppler run -p soleur -c dev`. Recovery: QA skipped per
   graceful degradation. Prevention: verify Doppler dev config includes
   all required env vars for server startup.

## Tags

category: integration-issues
module: review-pipeline
