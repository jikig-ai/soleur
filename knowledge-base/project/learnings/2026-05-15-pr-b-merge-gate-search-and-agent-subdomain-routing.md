---
title: Multi-PR slicing gates — search-string fidelity and agent subdomain routing
date: 2026-05-15
issue: 2939
pr: 3779
category: best-practices
tags:
  - one-shot
  - review
  - multi-pr-series
  - agent-routing
  - gh-cli-search
---

# Multi-PR slicing gates — search-string fidelity and agent subdomain routing

## Problem

`/soleur:go` invoked the Stage 6 PR-C workflow with a prescribed `PR-B-merged` gate:

```
gh pr list --search "cc-soleur-go-routing" --state merged
```

PR-B's actual merge title was `feat(cc-soleur-go): Stage 6 PR-B — routing/cost/UX smoke + FR2.4/2.8 client wires (#2939)` — the slug `cc-soleur-go-routing` did not appear in the title. The gate returned zero matches and aborted the run with `Aborting: PR-B not found in merged state`. The user had to confirm PR-B had merged, and a broader re-search (`cc-soleur-go --state merged`) immediately surfaced it as #3778.

Separately, during the 11-agent review fan-out, ten agents launched successfully and one failed with `Agent type 'soleur:engineering:review:git-history-analyzer' not found`. The agent lives at `soleur:engineering:research:git-history-analyzer` — under the `research` subdomain because git archaeology is research, not review.

## Root cause

**Gate string fidelity.** Multi-PR slice plans hand-write per-slice gate strings derived from intuitive slug guesses (PR-B "is about routing" → "cc-soleur-go-routing"). The author writes the gate string before the PR title is final and never re-confirms. `gh pr list --search` is a full-text search across title + body but treats the search query as required-substring AND'd terms; a slug that doesn't literally appear anywhere yields zero matches even when the PR exists, is merged, and is the one the workflow needs.

**Agent subdomain routing.** The review skill SKILL.md prescribes 8 always-on review agents by name (e.g., `security-sentinel`, `pattern-recognition-specialist`). The orchestrator constructs the agent registration path from the skill's namespace + the agent's name. The naive construction is `soleur:engineering:review:<name>` — which works for 10/11 agents. `git-history-analyzer` is the exception: it's classified as a research agent (it does archaeology) even though it ships in the review fan-out. The available-agents list returned in the failure message includes the correct path; recovery is a one-line re-spawn.

## Solution

For both classes, the fix is **derive, don't guess**:

1. **PR-merge gates:** Either (a) use the umbrella issue's `closedByPullRequestsReferences` field as the canonical source, or (b) name the prior PR by number in the plan/spec (PR-A merged 2026-05-14 as #3743; PR-B merged 2026-05-15 as #3778) and gate on `gh pr view <N> --json state` returning `MERGED`, never on a free-text search. PR numbers are stable; intuitive slugs are not.

2. **Agent fan-out spawning:** Pre-validate the spawn paths against the available-agents list before issuing the parallel block. When constructing prompts dynamically, group agent names by their actual subdomain (`research/` vs `review/`), not by where they're used (`/soleur:review` uses agents from both subdomains).

The cheapest mitigation for class (1) — and what we should have done at /soleur:go gate time:

```bash
# Find PR-B by umbrella issue's closedByPullRequestsReferences (or merge history)
gh issue view 2939 --json closedByPullRequestsReferences \
  --jq '.closedByPullRequestsReferences[].number'
# Then gate per PR number:
gh pr view 3778 --json state,mergedAt
```

For class (2), the most durable fix is to teach `/soleur:review` to enumerate agents by registry-path-as-shipped, not by name + assumed subdomain. The available-agents list shown in the error is the authoritative source.

## Session errors

1. **Wrong agent namespace path on first review-batch spawn** — Recovery: re-spawn `git-history-analyzer` with `soleur:engineering:research:` prefix after the registry error surfaced the correct location. **Prevention:** when spawning >5 agents in parallel, dry-run-validate each subagent_type against the registry's available-agents list (printed in any prior failure) before issuing the parallel block. Alternative: review skill SKILL.md to enumerate the 11 fan-out agents by their *registry path*, not by their *role name*.

2. **Parallel bash `&&` chain cancelled by an expected-zero grep** — Recovery: split into separate Bash calls with explicit exit-code handling (`grep ... 2>&1; rc=$?; [ $rc -eq 1 ] && echo PASS`). **Prevention:** when building Phase 0 verification blocks containing greps that expect zero hits, never chain with `&&` — either use `|| true` per grep, or restructure as standalone Bash invocations with `rc=$?` handling. The harness's parallel-tool cascade cancellation makes any failure in the chain punish all siblings.

3. **Visual-QA rubric initial draft contained the literals it was supposed to redact** — Recovery: edit to rephrase ("the canonical mock-Supabase test identity per `mock-supabase.ts:MOCK_USER`") instead of inline literals. **Prevention:** when writing documentation about redaction/secret-handling/sentinel-guarding, run the guard against the draft itself before committing. The Phase 6.2.5 guard in the plan was the catch — could be hoisted to a pre-Write check in the work skill.

4. **PR-B verification false-negative at /soleur:go gate** — Recovery: ran a broader `gh pr list --search "cc-soleur-go"` and identified PR-B as #3778 by inspection. **Prevention:** see Solution §1 above — multi-PR slice gates must reference the prior PR by *number*, not by a hand-written slug.

## Tags
category: best-practices
module: workflow / orchestration / multi-pr-series
