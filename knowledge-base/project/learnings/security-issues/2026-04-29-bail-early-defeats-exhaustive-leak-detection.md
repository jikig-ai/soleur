---
date: 2026-04-29
category: security-issues
module: preflight
tags: [security-gates, traversal, bail-early, completeness]
related_pr: 3029
related_issue: 3010
---

# Learning: bail-early in security-gate traversal defeats exhaustive leak detection

## Problem

Preflight Check 5 traverses up to 20 Webpack chunks loaded by `/login` to find the inlined Supabase init JWT (issue #3010). The first draft of the rewrite included a perf-driven optimization:

```bash
# Bail-early once both signals present
if [[ -n "$jwt_chunk" && -n "$host_union" ]]; then break; fi
```

The intent was to keep median fetch count to 1–3 chunks (~150ms). It worked for the JWT discovery case.

But the eight-row decision matrix included a separate row:

> ≥1 placeholder host (`test.supabase.co`, `placeholder.supabase.co`, etc.) anywhere in any examined chunk → **FAIL** (Placeholder URL leaked into the bundle)

Code-quality review (PR #3029) caught the bug: bail-early stops the loop as soon as a JWT is found and at least one host is in `host_union`. If a placeholder host is in chunk 11 but the JWT and a canonical host are in chunks 5–6, the loop bails at chunk 6 and the placeholder leak is never examined.

The matrix row's wording "in any examined chunk" technically held — we only examined 6 chunks. But the security gate's purpose is exhaustive leak detection, not "examined-chunk leak detection." A placeholder leak in an un-examined chunk is exactly the failure class the gate exists to catch.

## Solution

Drop the early-break for security-critical multi-criterion traversal. Always traverse the full candidate list (cap = 20 in this case). Cost is bounded: 13 chunks against a CDN at ~50ms each = 600ms wall-clock. That's an acceptable preflight cost for an invariant-class security gate.

```bash
while IFS= read -r chunk_path; do
  # ... fetch + grep for host and JWT ...
done < /tmp/preflight-candidates.txt
# (no early-break)
```

If perf were genuinely critical, an alternative would gate the early-break on `host_union` containing ONLY canonical hosts so far — but that adds branching complexity for a 600ms savings on a CI-side gate. Simpler is better: full traversal, accept the cost.

## Key Insight

**Bail-early is a performance optimization. Performance optimizations are incompatible with multi-criterion completeness assertions.**

The pattern to watch for: a security or invariant gate that scans N candidates for multiple independent signal classes (good signal + bad signal), where finding "enough good signal" does NOT preclude "bad signal" elsewhere in the candidate set. Any bail-early that exits on a positive good-signal threshold silently weakens the bad-signal detection.

Specifically:
- Bail-early after first-match is safe when the gate's job is "find ONE thing."
- Bail-early after first-match is UNSAFE when the gate's job is "find any leak among N candidates" — you must traverse all N.

## Related

- PR #3029 — applied this fix; review-driven inline correction.
- Issue #3010 — original bug that motivated the rewrite (SKIP-on-chunking-change).
- `2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md` — the load-bearing SKIP-vs-FAIL invariant for security gates; this learning extends the same "fail-closed on partial observation" principle to traversal completeness.
- `2026-04-28-anon-key-test-fixture-leaked-into-prod-build.md` — Session Error #6 on log-injection; same Check 5 surface.

## Session Errors

- **Plan subagent wrote plan file to bare repo path, not worktree.** The plan/deepen-plan subagent invoked from one-shot wrote `2026-04-29-fix-preflight-check5-dynamic-chunk-discovery-plan.md` to `/home/jean/git-repositories/jikig-ai/soleur/knowledge-base/project/plans/` instead of the worktree's `knowledge-base/project/plans/`. The file ended up untracked outside the worktree's git index. **Recovery:** moved manually via `mv` before continuing. **Prevention:** the plan skill should resolve target paths against `git rev-parse --show-toplevel` (worktree root), not `pwd` or hardcoded relative paths. Track as separate workflow gap if it recurs.

- **No specs dir created by plan subagent.** one-shot's session-state.md write target was `knowledge-base/project/specs/feat-one-shot-3010-.../session-state.md`, but the dir didn't exist. one-shot's parser assumed plan creates it. **Recovery:** `mkdir -p` before write. **Prevention:** one-shot should `mkdir -p "$specs_dir"` before the session-state write, OR plan should always create the specs dir for the active feature branch even when not generating tasks.md.

## Prevention

For future security-gate skill edits or new security gates:

1. **Audit any bail-early loop against the gate's matrix.** Ask: "Does the matrix have a row about ANY chunk/candidate having a bad signal?" If yes, bail-early is unsafe.
2. **Prefer full traversal at CDN/CI latencies.** A 600ms-1s preflight cost is invisible compared to even a single false-negative leak.
3. **Make the trade-off explicit in prose.** If a future edit reintroduces bail-early for measured perf reasons, the SKILL.md must document which matrix rows the optimization weakens and why the trade-off is acceptable.

The full prevention pattern is captured in plugins/soleur/skills/preflight/SKILL.md Step 5.2 prose: "Always traverse the full candidate list — bail-early would skip chunks that may carry a placeholder-host leak (matrix row 6)."
