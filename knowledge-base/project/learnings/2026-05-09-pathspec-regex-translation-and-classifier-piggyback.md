---
date: 2026-05-09
category: best-practices
module: skill-classifier-design
tags: [preflight, review, regex, pathspec, classifier, security, multi-agent-review]
related-pr: 3492
---

# Learning: pathspec→regex translation drift and classifier-piggyback threat model

## Problem

PR #3492 introduced two skill-internal classifiers as a token-cost optimization:

1. A preflight Phase 0 cache of `git diff --name-only origin/main...HEAD` so each path-gated check could `grep -E '<predicate>' .git/preflight-diff-files.txt` instead of re-running diff.
2. A review Change Classification Gate extension with a new `deletion-dominated` sub-class (≥80% deleted files AND ≥80% deleted lines).

Two distinct review-time failures hit on first commit:

- **Pathspec→regex translation drift (Check 1).** The plan prescribed translating git pathspec `*/supabase/migrations/*.sql` → regex `/supabase/migrations/[^/]+\.sql$`. The translation under-matches: git pathspecs use fnmatch with `FNM_PATHNAME=0`, so `*` crosses `/`. The original pathspec matched top-level `supabase/migrations/X.sql` AND any-depth-nested `apps/X/supabase/migrations/sub/Y.sql`; the regex matched neither (the leading `/` rejected top-level; `[^/]+` rejected nested). Three review agents independently flagged this with empirical fixture tests.
- **Classifier piggyback bypass (deletion-dominated).** The original predicate routed to 2 agents (git-history-analyzer + security-sentinel) on any diff with ≥80% deletions across files AND lines. A 1000-line cleanup PR carrying a 50-line backdoor `.ts` file scores 95/95 and bypasses pattern-recognition / code-quality / architecture / data-integrity / performance / agent-native review. The plan documented the line-and-file-percentage logic in Risks #4 as "savings are minimal anyway for tiny PRs" but did not run a "what is the worst-case piggyback?" threat-model pass per class.

Both issues passed the plan's own self-checks: the pathspec verification recipe used a test fixture that excluded the divergent shapes; the classifier was reasoned about by file-shape analysis on PR #3488 (which had no new source code) without enumerating an attacker-shaped diff.

## Solution

**Pathspec→regex (preflight Check 1):** widened the regex to `(^|/)supabase/migrations/.*\.sql$`. `(^|/)` accepts both top-level and any-depth ancestor; `.*` matches any depth under the migrations directory. Verification at edit time now requires fixture inputs covering all three shapes (top-level, single-app, nested-under-migrations).

**Classifier piggyback (review):** added an explicit `$has_source` empty guard to the `deletion-dominated` predicate, mirroring the same guard already present on `lockfile-only`. A deletion-dominated PR with new source code now falls through to `code` (8 agents). Net effect on PR #3488-class diffs is preserved (no new source files in the precedent); attacker-shaped diffs are routed to the full 8-agent path.

Verification: `bun test plugins/soleur/test/components.test.ts` → 1013/0; `bash scripts/test-all.sh` → 26/26 suites; review re-run shows the original three-agent agreement on the regex resolves cleanly.

## Key Insight

Two general-purpose patterns:

1. **Pathspec ≠ regex.** `git diff -- '<glob>'` uses pathspec semantics (fnmatch with PATHNAME off; `*` crosses `/`); `grep -E '<re>'` uses POSIX ERE (`/` is a literal character). When swapping the diff source for a cached path-set, ANY pathspec→regex translation must be verified empirically with fixture inputs covering: (a) top-level path, (b) single-ancestor path, (c) deep-nested path, (d) edge-of-pathspec-matching (e.g., zero-length `*`). The verification recipe `git diff -- '<glob>' > A && grep -E '<re>' cache > B && diff -u A B` is necessary but not sufficient — the test repo MUST contain inputs that disagree under bad translations.

2. **Classifiers introduce a new attack surface.** When a routing predicate downgrades the number of agents that inspect a diff, the predicate becomes a security boundary. Every new classifier needs a "what's the worst-case piggyback?" threat-model question per class: what shape of diff scores high on this predicate while smuggling a malicious change the skipped agents would have caught? Cheap defense: borrow the strongest exclusion guard from a sibling class (here, `lockfile-only`'s `$has_source` empty) and apply it to the new class.

The unifying principle: **a translation-style optimization or a routing-style optimization is both behavior-preserving in the no-diff case AND a new gap in the with-diff case.** Multi-agent review is the only routine layer that catches these — single-agent plans systematically miss the negative-space cases.

## Prevention

- **Plan template (pathspec→regex):** when a plan prescribes a regex translation of a git pathspec, the verification step must enumerate ≥3 fixture inputs covering top-level, ancestor, and deep-nested forms. The "diff -u" recipe alone is insufficient — the implementer needs the divergent fixtures to know what to feed into it. Consider adding a Sharp Edge to `deepen-plan` Phase 4 prescribing this fixture-shape requirement.
- **Plan template (classifier predicates):** when a plan introduces a new routing predicate that reduces review-agent count, deepen-plan should require an explicit "Threat Model" subsection per class enumerating: (a) what shape scores high on this predicate, (b) what malicious payload could ride on that shape, (c) which agent on the full path would catch it, (d) how the predicate excludes that case.
- **Multi-agent review on classifier additions:** the `lockfile-only` sub-class was authored at the same time as `deletion-dominated`; the symmetric `$has_source` guard was present on one but not the other. A pre-commit grep (`diff <(grep -A2 lockfile-only) <(grep -A2 deletion-dominated)`) on classifier blocks would surface asymmetric guards mechanically.
- **Component-test feedback on link form:** `components.test.ts` already flags backtick-wrapped reference links; the agent compliance checklist in `plugins/soleur/AGENTS.md` documents the canonical form `[filename.md](./references/filename.md)`. No further enforcement needed — the test is the gate.

## Session Errors

1. **Components-test failure on backtick-wrapped reference link.** Used `[\`references/work-lockfile-bumps.md\`](./references/work-lockfile-bumps.md)` initially; gate flagged. **Recovery:** changed to `[work-lockfile-bumps.md](./references/work-lockfile-bumps.md)`. **Prevention:** discoverable via test; the existing `bun test plugins/soleur/test/components.test.ts` gate is sufficient — no additional rule needed.
2. **Pathspec→regex under-match in Check 1.** Plan prescribed `/supabase/migrations/[^/]+\.sql$`; missed top-level and nested cases. **Recovery:** widened to `(^|/)supabase/migrations/.*\.sql$`. **Prevention:** above — fixture-shape requirement in plan/deepen-plan for pathspec→regex translations.
3. **Unbalanced markdown bold in new bullet.** `**lead.... **Why:**` left lead-clause bold open. **Recovery:** closed with `.**` after lead clause matching neighbor pattern. **Prevention:** when appending to an existing bullet list, copy the lead-clause format from the nearest sibling; visual review on first pass.
4. **`deletion-dominated` source-bypass piggyback.** Original predicate let new `.ts` files ride along. **Recovery:** added `$has_source` empty guard mirroring `lockfile-only`. **Prevention:** above — threat-model subsection per classifier class.
5. **Tail-of-stream artifact in test output.** `tail -3` mid-stream showed false 25/26. **Recovery:** completed run was 26/26. **Prevention:** for background commands, read full output via the notification, not mid-stream tails.
6. **`sleep 25` chained before grep blocked.** Harness rejected per long-leading-sleep rule. **Recovery:** re-ran without sleep. **Prevention:** harness already enforces; one-off operator error.

## Related

- Source PR: #3492 (this PR — three-change pipeline optimization for one-shot)
- Precedent PR: #3488 (Dependabot dual-lockfile bump that motivated the optimization; routes to `deletion-dominated` post-fix because it has no new source files)
- AGENTS.md `cq-write-failing-tests-before` carve-out for infrastructure-only changes (this PR qualified)
- Plan: `knowledge-base/project/plans/2026-05-09-perf-one-shot-pipeline-token-cost-optimizations-plan.md`
