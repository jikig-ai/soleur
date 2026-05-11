---
title: "Plan-review caught two latent plan-time traps: `git log -- A B` union vs. intersection, and cross-module field-existence assumptions"
date: 2026-05-11
category: best-practices
tags: [planning, git, verification, plan-review, single-user-incident]
related:
  - knowledge-base/project/plans/2026-05-11-feat-pdf-chapter-chunking-bundle-plan.md
  - knowledge-base/project/learnings/best-practices/2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md
  - knowledge-base/project/learnings/best-practices/2026-04-15-plan-skill-reconcile-spec-vs-codebase.md
issues: [3472, 3473, 3474]
pr: 3550
brand_survival_threshold: single-user incident
---

# Plan-review caught two latent plan-time traps

## Problem

During `/soleur:plan` for the PDF chapter-chunking Phase 3.B + S1/S2 spikes bundle (USER_BRAND_CRITICAL=true, threshold `single-user incident`), the 5-agent plan-review panel (DHH + Kieran + Code-Simplicity + Architecture-Strategist + Spec-Flow-Analyzer) surfaced two convergent P1 defects in the plan-as-written that would have shipped a broken safety invariant.

Both defects passed individual sub-section review because each subsection looked plausible in isolation. They only surfaced under a holistic review that mapped plan claims back to current codebase reality.

### Defect 1 — `git log --oneline -- A B` is a union filter, not an intersection filter

The plan's AC #18 (TR4 single-commit invariant — directive revival + dispatch wiring must land in the same commit per the `single-user incident` framing inherited from PR #3440's revert) prescribed:

```bash
git log --oneline -- apps/web-platform/server/soleur-go-runner.ts apps/web-platform/server/agent-runner.ts
```

with the claim "every commit on the branch that touches either runner ALSO touches the other in the same commit."

That is not what the command does. `git log -- A B` lists commits touching A **OR** B. A commit touching only `soleur-go-runner.ts` (directive added, dispatch forgotten) appears in the output indistinguishably from a paired commit. The verification command was decorative — it could not detect the exact failure mode TR4 was designed to catch.

Kieran reproduced the semantics live with three test commits (one touching A only, one touching B only, one touching both): all three appeared identical in the `--oneline` output. The verification command shipped a green checkmark while the gap was still open.

### Defect 2 — Plan prescribed reading a field on a cross-module shape that does not exist

The plan's KD-5 stale-context check (§3.2 step 1) and KD-4 buffer source (§3.2 step 3a) both referenced `state.chapterChunkedContext.fullPath` populated from `documentExtractMeta.path`. The plan also said `documentTitle` was "derived from the resolver's `documentExtractMeta` (already carries path; title parsed from filename or PDF metadata)."

The actual `DocumentExtractMeta` interface in `apps/web-platform/server/kb-document-resolver.ts` lines 39–43:

```ts
export interface DocumentExtractMeta {
  numPages?: number;
  chapters?: ChapterIndex[];
  fullExtractedText?: string;
}
```

No `path` field. No `title` field. The resolver knows the full path internally (line 174) but does not expose it. AC #13 (KD-5 stale-context) was unimplementable as written. KD-4 was unimplementable as written. Both would have surfaced at Phase 3.2 work-time as build errors or — worse if a hasty implementer widened `DocumentExtractMeta` without surfacing it in `Files to Edit` — as a cross-cutting interface change that escaped review.

## Root Cause

Both defects share a common root: **plan-time prose claims about external mechanisms (git, a TypeScript interface) were not verified against the actual mechanism before being frozen into ACs**. The plan author reached for "obvious" verification commands and "obvious" cross-module field reads without running either against the live system.

For Defect 1: the author knew git log lists commits touching files. The mental model collapsed "list of commits where both files appear in `git log -- A B`" with "list of commits where both files appear in `git show <sha> -- A B`" — they sound similar but the first is union, the second is per-commit intersection.

For Defect 2: the author paraphrased "the resolver carries chapter context" into "the resolver carries chapter context with path and title." `chapters` was real; the rest was filled in to make the dispatch ergonomic. The dispatcher already knows `contextPath` from upstream — the field-on-`documentExtractMeta` framing was a planning artifact, not a code-grounded need.

This is a generalization of the earlier `2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md` lesson ("`ls`/`Read` every path and grep every symbol the body names BEFORE writing the plan") — that learning covered plan paraphrases of issue-body file paths. This session extends the pattern to:

- **Per-file co-change-invariant verification commands** (Defect 1 class). A plan that prescribes a git command to enforce a co-change invariant must verify the command's actual semantics against the failure mode it is supposed to catch.
- **Cross-module field-existence claims** (Defect 2 class). A plan that prescribes reading a field on a shape defined in another module must `rg`-verify the field exists in the current shape.

Both classes ship a green checkmark while the gap is still open — the same failure mode that motivated the `cq-write-failing-tests-before` rule, applied at plan time rather than implementation time.

## Solution

Both defects were caught pre-merge by the plan-review panel and fixed inline in the plan before commit:

**Defect 1 fix.** Replaced AC #18's verification command with a per-commit walking shell script:

```bash
set -euo pipefail
FAIL=0
DIRECTIVE_MARKER='chapter-chunked'
DISPATCH_MARKER='pushStructuredUserMessage'
RUNNERS=(apps/web-platform/server/soleur-go-runner.ts apps/web-platform/server/agent-runner.ts)
for sha in $(git rev-list main..HEAD -- "${RUNNERS[@]}"); do
  diff=$(git show "$sha" -- "${RUNNERS[@]}")
  has_directive=0; has_dispatch=0
  echo "$diff" | grep -q "$DIRECTIVE_MARKER" && has_directive=1
  echo "$diff" | grep -q "$DISPATCH_MARKER" && has_dispatch=1
  if [[ $has_directive -ne $has_dispatch ]]; then
    echo "FAIL $sha — directive=$has_directive dispatch=$has_dispatch (must match)"
    FAIL=1
  fi
done
exit $FAIL
```

Plan recommends wiring this as a `pre-push` hook for the branch lifetime.

**Defect 2 fix.** Threaded `fullPath` and `documentTitle` through `state.chapterChunkedContext` at session creation from the upstream `args.contextPath` — cleaner than widening `DocumentExtractMeta`, which is used by `cc-dispatcher.ts` and both resolvers and would have been a cross-cutting interface change escaping the plan's stated `Files to Edit` list. Plan updated to source the field from the dispatcher's existing knowledge, not from the resolver result.

## Prevention

Two extensions to the plan skill's Sharp Edges (routed via compound's Route-Learning-to-Definition step):

1. **Per-file co-change-invariant verifications.** When a plan AC prescribes a command to enforce a co-change invariant (e.g., "files A and B must be touched in the same commit"), the command MUST be tested against the failure mode. `git log -- A B` is a union filter; for intersection semantics, walk commits with `git rev-list ... -- <paths>` and `git show <sha>` to inspect per-commit diffs. Verify by constructing three throwaway commits — one touching A only, one touching B only, one touching both — and confirming the command rejects the asymmetric two.

2. **Cross-module field-existence verification (extension of paraphrase-without-verification).** When a plan prescribes reading a field on a TypeScript interface, Postgres column, GraphQL type, or other shape defined in a sibling module, `rg "<field-name>" <defining-module>` BEFORE freezing the AC. If the field is not there, either name the interface-widening edit explicitly in `Files to Edit` or thread the value from a closer source. Most cross-module field assumptions trace back to "plan paraphrase added a field name that sounded plausible" — the cost of the rg is 2 seconds; the cost of catching it at implementation is a forced plan-rewrite mid-/work or a scope-leak interface change.

## Session Errors

1. **Defect 1 (`git log -- A B` union)** — AC #18 verification command did not work. **Recovery:** replaced with per-commit walking script. **Prevention:** plan skill Sharp Edge — test co-change-invariant commands against the failure mode they catch.
2. **Defect 2 (`documentExtractMeta.path` doesn't exist)** — AC #13 + KD-4 unimplementable. **Recovery:** thread `fullPath` from `args.contextPath` via state at session creation. **Prevention:** plan skill Sharp Edge — `rg` cross-module fields before freezing the AC.
3. **§3.4 helper-extraction deferred with an unmeasurable threshold** — caught by DHH P1 + Code-Simplicity #5 + Architecture P3.3. **Recovery:** decided "inline twice" at plan-finalize. **Prevention:** existing plan skill convention applies (decide-at-plan-time) — no new rule needed, but the byte-overlap-threshold-as-decision-criteria pattern is a smell.
4. **KD-5 internal contradiction (§3.2 step 1 vs AC #13 test 8)** — caught by Spec-flow F5. **Recovery:** clear-and-proceed-same-turn semantics. **Prevention:** existing convention covers (plan should cross-check AC test descriptions against §-section behavior) — no new rule.
5. **`readFile` ENOENT path not enumerated** — caught by Spec-flow F8. **Recovery:** try/catch + Sentry mirror + refund branch. **Prevention:** existing `cq-silent-fallback-must-mirror-to-sentry` covers the Sentry mirror; failure-mode enumeration for filesystem reads in dispatch flows is implicit but worth a one-line plan-skill nudge for the rare case.
6. **Extraction-failure missing Sentry mirror** — caught by Spec-flow F7 + Architecture P2.1. **Recovery:** `reportSilentFallback` added. **Prevention:** `cq-silent-fallback-must-mirror-to-sentry` already covers; this was a one-off application miss, not a new rule class.

Errors 3–6 do NOT warrant new AGENTS.md rules per the discoverability exit in `wg-every-session-error-must-produce-either` — each was caught by a clear review-time signal and existing rules cover the remediation. Errors 1 and 2 ARE rule-worthy because they ship under a green checkmark (silent failure mode); routed to plan skill Sharp Edges below.

## Key Insight

The 5-agent plan-review panel works **because** plan authors converge on plausible-sounding prose that survives subsection review. The defects in this session both passed the plan author's self-review (each sentence looked correct in isolation) and would have passed a 3-agent panel (DHH, Kieran, Simplicity alone wouldn't necessarily catch Defect 2's interface-existence claim — Architecture-Strategist did). The 5-agent panel exists specifically for `single-user incident` plans where the cost of latent defects shipping is unbounded.

The pattern compounding here: plan-time verification of external mechanisms (git semantics, cross-module field existence, third-party action behavior, vendor default behavior) is the highest-leverage check the plan skill can run. Every plan-time `rg`/`--help`/`gh api` invocation costs seconds; every missed verification costs a plan-rewrite at `/work` time, a multi-agent re-review, or a post-merge incident.
