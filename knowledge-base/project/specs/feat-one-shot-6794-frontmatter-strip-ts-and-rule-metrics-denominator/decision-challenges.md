# Decision Challenges — feat-one-shot-6794 (#6794)

Surfaced during deepen-plan (headless one-shot → persisted per ADR-084; `ship` renders these into the PR body + files an `action-required` issue for the operator). Each is a **User-Challenge**: the operator's stated direction (the #6794 issue body) is the default; these record where a reviewer disagreed.

## Challenge 1 — Inline the strip vs. import `strip.ts` in the cron

- **Operator's stated direction (#6794):** "Add `scripts/lib/frontmatter-strip/strip.ts` … Use it in `cron-compound-promote.ts`."
- **Reviewer challenge (code-simplicity-reviewer):** The cron body is webpack-compiled and importing a repo-root `.ts` crosses the app boundary — potentially requiring `experimental.externalDir: true` (a repo-wide build-config flag) — all to run a ~5-line `startsWith`/`split` function. The TS port uses the SAME mechanism as `strip.py` (near-zero drift surface), and the real guarantee is behavioral equality (the promoter-vs-`B_ALWAYS` invariant test), which holds for an inlined copy. Recommendation: keep `strip.ts` at the SPEC location for the shell/py/parity consumers, but INLINE the 5 lines in `cron-compound-promote.ts` with a `// contract: scripts/lib/frontmatter-strip/SPEC.md` comment, eliminating the cross-boundary import, R1, and any `next.config.ts` change.
- **Plan default:** follow #6794 literally — import `strip.ts` in the cron; enable `experimental.externalDir` only if `next build` requires it. The inline alternative is strictly cheaper/lower-risk and satisfies "add strip.ts" (it still exists + is parity-tested); the only thing it trades away is the literal word "use it IN the cron."
- **Decision needed from operator:** accept the import (default), or adopt the inline-with-contract-comment simplification.
