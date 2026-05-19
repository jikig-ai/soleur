---
title: Bare-repo-root grep produces ghost-absent files; subagent infra-substrate claims need first-party verification
date: 2026-05-19
category: workflow-patterns
tags: [brainstorm, premise-validation, worktree, subagent-verification, git-ls-files]
related_prs: ["#4066"]
related_issues: ["#3244"]
source_session: brainstorm — PR-H Daily Priorities multi-source
---

# Bare-repo-root `git ls-files` produces ghost-absent files; subagent infra-substrate claims need first-party verification

## Problem

Two distinct but adjacent premise-validation failures fired in one brainstorm session (PR-H, branch `feat-daily-priorities-multi-source`):

### Pattern 1 — Ghost-absent files from bare-repo-root grep

Before creating the feature worktree, I ran premise-validation greps from `/home/jean/git-repositories/jikig-ai/soleur` (the bare-repo root):

```bash
git ls-files | grep -E "rule-metrics-aggregate"  # returned nothing
git ls-files | grep -i metric                     # returned nothing
find . -maxdepth 5 -name "rule-metrics*" 2>/dev/null  # missed it too
```

Conclusion propagated into 3 subagent prompts (CTO, repo-research-analyst, learnings-researcher): "scripts/rule-metrics-aggregate.sh is referenced in SKILL.md but NOT tracked in git anywhere; rule-metrics.json does not exist."

This was **false**. All three subagents corrected it independently by running `git ls-files` (or equivalent) from inside the worktree, where:

- `scripts/rule-metrics-aggregate.sh` exists and is tracked.
- `scripts/lib/rule-metrics-constants.sh` exists.
- `tests/scripts/test-rule-metrics-aggregate.sh` exists.
- `.github/workflows/rule-metrics-aggregate.yml` exists (weekly bot-PR cron).
- `knowledge-base/project/rule-metrics.json` exists.

The bare-repo root in this project has a Git working tree initialized at `HEAD` (not a strict `--bare` clone), but `git ls-files` from `/home/jean/git-repositories/jikig-ai/soleur` did not surface these paths. Most likely cause: the bare-repo "checkout" is at a different ref than `main`'s `HEAD`, or the working tree index is out of date with main. The exact mechanism matters less than the operational consequence: **pre-spawn premise greps run from the bare-repo root produce false negatives that propagate into subagent prompts as load-bearing assertions**.

### Pattern 2 — Subagent infra-substrate claim taken at face value

CTO subagent returned a focused-refresh that included this line:

> Stripe webhook does NOT bridge to Inngest directly — it mutates DB and calls `onTierTransitionApplied`.

The claim was load-bearing for the GitHub-webhook architecture (the brainstorm planned to mirror the Stripe pattern). Had I incorporated this verbatim into the brainstorm document, the spec would have prescribed a worse-different architecture ("build the bridge from scratch because none exists") instead of the simpler "mirror lines 437-516 of stripe/route.ts."

Caught by reading `apps/web-platform/app/api/webhooks/stripe/route.ts:420-510` myself. The file contains an explicit `inngest.send({ id: "stripe-${event.id}", name: "finance.payment_failed", ... })` at line 491, gated by `SOLEUR_FR5_ENABLED === "true"` and `isGranted(supabase, founderId, "finance.payment_failed")` (the load-bearing safety primitive, not the env flag).

The brainstorm SKILL.md explicitly names this pattern at three places (Phase 1.1: "Cross-checking leader infra/substrate claims against repo-research," "Reconciling fast-returning leader recommendations with later-arriving research findings"). The guidance was followed and prevented a wrong spec — but the cost was a ~3 min sync to re-read the file. **A subagent with strong substrate-claim phrasing ("does not bridge", "is not wired", "no existing X") is a high-signal trigger to drop into first-party verification before letting the claim shape spec text.**

## Root cause

### Pattern 1

`git ls-files` behavior depends on the index state of the current working tree, not on the contents of any branch. When invoked from a bare-repo-root checkout that is not synchronized with `main`'s `HEAD`, files added to `main` after the bare root was last refreshed are absent from `git ls-files` output. The session-start hygiene step (`git show main:.mcp.json > .mcp.json`) does NOT refresh the index — only the one file.

The brainstorm SKILL.md's "Pre-research" hint ("Run the `find` from inside the worktree") was added for this exact reason (per `2026-05-15-brainstorm-leader-research-sequencing-and-prior-art-cwd.md`). The rule's spirit applies to **all premise-validation greps**, not just the `find` for prior artifacts. In this session, the rule was followed for the `find` step but violated for `git ls-files` and adjacent greps that ran 30 seconds earlier in the same Phase 0 block.

### Pattern 2

Subagents reason strategically. They will return well-formed prose even when their grep window missed the load-bearing 80-line block. Phrasing like "does not bridge", "is not wired", "already running", and "identical auth model" is a high-confidence assertion that is also a high-failure-rate assertion — these are the exact phrasings the brainstorm SKILL.md (added 2026-05-12, `2026-05-12-anticipatory-hook-bypass-and-leader-substrate-cross-check.md`) was written to interdict.

## Solution / Prevention

### Pattern 1

**Run all premise-validation greps from inside the worktree, after worktree creation.** Specifically:
- Move the `find knowledge-base/project/brainstorms ...` prior-artifact check (Phase 1.1) to fire AFTER worktree creation if running on `main`.
- Adopt the same rule for `git ls-files`, `grep -r`, and `find` invocations whose result will be passed to a subagent in a Phase 0.5 / Phase 1.1 spawn prompt.
- If the operator is fast enough to spawn agents before worktree creation, the agents must each verify the premise themselves — this is what saved this session. But the cheaper path is to delay all premise greps until the working tree is at `HEAD` of the feature branch.

### Pattern 2

**When a subagent returns "infra X does not exist / does not bridge / is not wired", treat it as a verification trigger, not a fact.** Cost: 30 seconds to read the cited file. Benefit: bounded — the worst case is the brainstorm doc carries an architectural premise that is exactly wrong. This brainstorm caught it at synthesis time; the catch could have happened later (at plan / spec-time / PR-review) at much higher cost.

The verification pattern is binary:
- Subagent says **"X does not exist"** → grep the codebase for the diagnostic symbol the subagent should have cited. If the symbol exists, the claim is wrong.
- Subagent says **"X already does Y, just use it"** → grep for the call site Y. If absent, the claim is wrong.

Both forms are already named in brainstorm SKILL.md Phase 1.1; this learning re-confirms them under fresh evidence.

## Session Errors

1. **Bare-repo-root `git ls-files` produced ghost-absent files** for `rule-metrics-aggregate`, `rule-metrics.json`, and adjacent paths — propagated into 3 subagent prompts. **Recovery:** All 3 subagents corrected the premise independently from the worktree. **Prevention:** Run premise greps from the worktree, not the bare-repo root. Brainstorm SKILL.md Phase 1.1 hint is currently scoped to `find` only; extend to `git ls-files` and `grep -r`.
2. **Subagent (CTO) returned an infra-substrate claim that was wrong** ("Stripe webhook does NOT bridge to Inngest"). **Recovery:** Read `webhooks/stripe/route.ts:420-510` directly; found `inngest.send` at line 491. **Prevention:** The "does not exist / is not wired" phrasing in any subagent response is a verification trigger. Cost is 30s; benefit is bounded by the spec error otherwise.
3. **AskUserQuestion 4-option cap hit** when asking signal taxonomy with 8 options. **Recovery:** Split into 2 questions (GitHub source, KB-drift source). **Prevention:** When a single question naturally has >4 options, plan the split BEFORE drafting the question rather than discovering the cap at tool-call time.
4. **Phase 0.25 roadmap freshness check skipped** with rationale "umbrella body has fresh status." Brainstorm SKILL.md says "topic is NOT a skip criterion" — by inverse, neither is fresh-adjacent-context. **Recovery:** None needed this session (#3244 body was fresh). **Prevention:** When a SKILL.md step says "not a skip criterion," do not invent alternative skip criteria. Run the cheap check.
5. **`wg-before-every-commit-run-compound-skill` ordering mismatch.** Brainstorm SKILL.md Phase 3.6 step 6 commits artifacts BEFORE compound (Phase 4). AGENTS.md hard rule says compound runs BEFORE every commit. **Recovery:** Compound ran after the commit; no concrete harm. **Prevention:** File an issue to reconcile the two — either AGENTS.md should carve out docs-only-artifact commits, or brainstorm SKILL.md should defer the commit to after Phase 4 compound runs.

## Key Insight

Premise validation is two-dimensional: **the right query** (mechanical disambiguator, sibling-issue check, cited-flag-symbol grep) AND **the right CWD** (worktree, not bare). The brainstorm SKILL.md spent many learnings building up the first dimension; this session shows the second dimension is independently load-bearing. A correct query from the wrong CWD produces false-negative evidence that propagates into subagent prompts and shapes architecture before any human can catch it.

The companion observation: subagents are not factual oracles, even when they cite file paths. They cite the files they grep'd, and their grep window is bounded by their prompt. A subagent that says "infra X is not wired" has, at best, shown that infra X was not visible in their grep window. The cost of independently verifying a load-bearing substrate claim is a single Read tool call.

## Tags

category: workflow-patterns
module: brainstorm
