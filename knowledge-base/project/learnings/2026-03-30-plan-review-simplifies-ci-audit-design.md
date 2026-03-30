# Learning: Plan review simplifies CI audit from 4 scripts to 1

## Problem

The initial plan for #451 (automated rule audit CI) designed a 4-script modular
system with JSON interchange, SHA256 fingerprint deduplication via GitHub labels,
and automated PR generation with Markdown file surgery. Three plan reviewers
(DHH, simplicity, Kieran) independently flagged this as over-engineered for a
bi-weekly cron job.

## Solution

Simplified to a single `scripts/rule-audit.sh` (~120 lines) that:

1. Counts rules with `grep -c '^- '`
2. Extracts `[hook-enforced]` annotations as migration candidates
3. Verifies hook scripts exist
4. Creates/updates a GitHub issue with title-based dedup

No automated PRs, no fingerprint labels, no JSON interchange between scripts.
Matched the existing `scheduled-cf-token-expiry-check.yml` pattern exactly.

## Key Insight

When a CI job runs bi-weekly and produces a report for human review, the entire
pipeline (count, detect, report, dedup) belongs in one script. Modular scripts
are valuable when pieces have independent consumers or independent testing value.
A pipeline with one consumer that always runs sequentially is premature
decomposition, not modularity.

The `[hook-enforced]` annotation is the only duplication signal that matters for
tier migration. Cross-tier phrase matching against agent descriptions and skill
instructions is fuzzy NLP in bash — high complexity, low signal. The annotation
was already designed as the machine-readable marker.

## Session Errors

- **Background agent output inaccessible** — Research agents ran in background
  but output files used internal IDs that didn't match expected paths. No
  workflow impact (direct file reads provided sufficient context). Prevention:
  When background agents aren't critical-path, don't block on their output —
  gather context directly in parallel.
- **SpecFlow agent path resolution** — Agent tried reading from bare repo root
  instead of worktree path. Prevention: When spawning agents for worktree work,
  verify the agent's working directory matches the worktree path.
- **False positive in hook-enforced extraction** — `grep '\[hook-enforced:'`
  matched a template line `[hook-enforced: <script> <guard>]` in constitution.md
  that describes the annotation format, not an actual rule. Prevention: When
  grepping for structured annotations, filter out template/placeholder patterns
  (angle brackets).

## Tags

category: ci-infrastructure
module: scripts/rule-audit
