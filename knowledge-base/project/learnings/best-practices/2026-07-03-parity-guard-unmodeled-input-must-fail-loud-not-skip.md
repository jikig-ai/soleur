---
title: "A parity/containment guard must FLAG unmodeled inputs (fail-loud), never silently skip them"
date: 2026-07-03
category: best-practices
tags: [testing, guards, fail-open, dockerignore, source-scan, multi-agent-review]
module: plugins/soleur/test
related:
  - 2026-06-12-source-scan-containment-gate-call-detection-and-fail-closed-lexing.md
  - 2026-03-20-dockerignore-nextjs-vs-bun-patterns.md
---

# Learning: a parity/containment guard must FLAG unmodeled inputs, never silently skip

## Problem

Built a generic pre-merge guard (`plugins/soleur/test/dockerfile-copy-dockerignore-parity.test.ts`)
for the recurring release-break class where a Dockerfile `COPY --from=builder` / builder `RUN .sh`
bakes/consumes a build-context path that `.dockerignore` strips with no `!`-re-include (the #5922 /
#5939 host-scripts break, the #5875/#5890 sandbox-canary precedents). The guard modeled `.dockerignore`
with a deliberate Set+prefix simplification (YAGNI — no full Docker patternmatcher) and, for any
exclusion pattern containing a glob metachar, did `if (hasGlob(pat)) continue;` — i.e. **silently
skipped** it. The header comment even claimed the model was "fail-loud-safe … never silently passes
a real strip."

Five orthogonal review agents (pattern-recognition, test-design, code-quality, security-sentinel,
architecture) independently converged: the "skip globs" line is **fail-OPEN**. A future baked path
shadowed only by a glob EXCLUDE (`*.md`, `assets/*`, `_plugin-vendored/**`) would never be added to
the excluded set, so the guard returns `[]` (clean) while the release build breaks — the exact class
the guard exists to prevent. The "fail-loud-safe" claim only ever reasoned about glob RE-INCLUDES,
not glob EXCLUDES. The RUN parser had the same shape of gap (missed `./x.sh` direct-exec and
`\`-continuation lines) — a "closes the class wholesale" claim the parser didn't back.

## Solution

Invert the default for anything the simplified model can't represent, in the direction that is safe
for THIS guard:

- **Glob EXCLUDES** are now matched by an **over-approximating** glob→regex (`**`→`.*`, `*`→`[^/]*`,
  `?`→`[^/]`) and **flagged** (loud), never skipped. Over-matching is safe: a false flag just asks
  the author to add a `!`-re-include; a silent skip ships a broken release.
- The RUN parser now joins `\`-continuations (mirroring the COPY parser), captures direct-exec
  `./x.sh`, and normalizes a leading `./` — so "every builder RUN .sh" is actually true.
- Added a **positive control** test (strip one real `!`-re-include from the model → assert the guard
  flags exactly that src) so the flagship zero-violation assertion cannot silently become vacuous.

The one residual model boundary (Docker's last-match-wins pattern ORDER) is now honestly documented
as a known limit rather than papered over by an overstated "never silently passes" claim.

## Key Insight

For a guard whose whole job is to CATCH a class, the safe failure direction is to **over-flag**, not
to skip. When you deliberately simplify the model (correct YAGNI), the simplification must be biased
toward false positives (loud, author fixes it), never false negatives (silent, ships broken). And a
guard's own doc-comment claim ("fail-safe", "closes the class wholesale", "never silently passes") is
a **testable assertion** — enumerate every input form the guard claims to cover and confirm the
parser/model actually covers it, or narrow the claim. This is the same fail-open shape as
[[2026-06-12-source-scan-containment-gate-call-detection-and-fail-closed-lexing]] (proxy-not-behavior,
regex-not-lexer, partial-surface), now with a fourth sibling: **unmodeled-pattern silently skipped**.

## Session Errors

1. **Parser double-match** — `RUN bash ./scripts/gen.sh` matched both the interpreter-prefixed and
   the direct-exec regex passes, so the parser returned the src twice and a `.toEqual([one])` test
   failed once. Recovery: dedup per statement via a `Set` before pushing. Prevention: when a single
   token can satisfy two alternative capture passes, dedup at the boundary that emits the list, not
   only at the downstream consumer (the guard already deduped globally, which hid the parser dup from
   the real-repo test). One-off.
2. **Overstated safety claim authored, caught at review** — the "fail-loud-safe / never silently
   passes" comment was written before the glob-EXCLUDE path was reasoned through. Recovery: multi-agent
   review flagged it; comment corrected to match actual behavior. Prevention: treat a guard's
   self-describing safety claim as an assertion to verify against each input class at write time — the
   review defect-class catalogue in `plugins/soleur/skills/review/SKILL.md` already covers this
   (source-scan gate fail-open), so no new rule; recurring-class awareness lives here.

## Tags
category: best-practices
module: plugins/soleur/test
