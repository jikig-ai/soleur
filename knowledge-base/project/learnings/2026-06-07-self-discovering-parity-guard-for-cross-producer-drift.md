# Learning: self-discovering parity guard for cross-producer drift fixes (and its edited-vs-discovered count trap)

## Problem

A bug fix lands on ONE instance of a replicated pattern (PR #4989 fixed headless
`/soleur:*` skill resolution on `cron-content-generator.ts` by adding
`--plugin-dir plugins/soleur` + `Skill`/`Task` to `--allowedTools`). The SAME
latent gap exists across N sibling producers (#4993: 10 more cron/event
claude-eval producers). Fixing the siblings is mechanical — the harder problem is
making the gap **unable to silently re-open** when a future producer adds a
`/soleur:*` prompt without the flags. A static per-file test list rots: the next
producer is simply never added to it, and the suite stays green.

## Solution

Add ONE **self-discovering** parity guard rather than N per-file test blocks
(which is also the duplicate-coverage anti-pattern). The guard:

1. `readdirSync` the producers dir, filter to `^(cron|event)-.*\.ts$`.
2. Classify a file as skill-invoking when it BOTH spawns a claude eval
   (`src.includes("CLAUDE_CODE_FLAGS")`) AND has `/soleur:` in a **non-comment**
   (prompt) line. The two-predicate AND is what excludes the false positives:
   text-only emitters that print `/soleur:` into a generated issue/nag body
   (no `CLAUDE_CODE_FLAGS`) and flag-carrying eval producers that invoke no skill.
3. Assert `discovered === EXPECTED_SKILL_PRODUCERS` (belt-and-suspenders: a new
   skill producer must be added to the list AND given the flags, or the suite
   fails loud) with a non-vacuity guard (`discovered.length > 0`).
4. `it.each` over the set asserting each carries `--plugin-dir` + `Skill` + `Task`,
   with `--plugin-dir` before the `--` end-of-options marker.

Home it in the existing cross-producer source-shape test
(`cron-producer-output-wiring.test.ts`) — it already establishes the
`readFileSync` + discovered/listed-set convention.

**Comment-strip robustness (the dangerous-quiet direction):** strip ONLY `//`
line comments when computing the prompt body. Do NOT strip `*`/`/*`-prefixed
lines — a future prompt whose template-literal text starts with a markdown
bullet (`* Run /soleur:foo`) would be silently dropped, false-EXCLUDING the
producer so it ships unguarded with the test still green. Verify no flag-carrying
producer carries `/soleur:` inside a block comment before relying on this.

## Key Insight

**A self-discovering guard's EXPECTED count is "files DISCOVERED", not "files this
PR EDITS".** The plan authored the expected set as 10 (the siblings it edits), but
the discovery predicate inevitably re-matches the already-fixed precedent
(`cron-content-generator.ts`, fixed in #4989) — so the real count is 11. This is
a feature, not a bug: including the already-fixed item means the same guard now
also protects the original fix from regressing. Whenever you write a
self-discovering test against a pattern that a PRIOR PR already partially fixed,
the expected set MUST include the prior-PR items. Reconcile the plan's
"edited" count against the test's "discovered" count before trusting either.

## Session Errors

1. **Live isolated empirical probe infeasible** — no `ANTHROPIC_API_KEY` in env or
   Doppler `dev`, so the plan-prescribed `claude --print` with/without
   `--plugin-dir` probe could not run. **Recovery:** proceeded on the triple-confirmed
   mechanism (root-cause doc + contamination trace + the merged #4989 validation)
   with CI source-shape parity as the binding gate. **Prevention:** for fixes that
   are a verbatim repeat of an already-merged-and-validated pattern, a live probe is
   confirmatory, not load-bearing — gate on the deterministic source-shape test
   instead of blocking on an unavailable credential.
2. **Edit string-not-found** on `cron-campaign-calendar.ts` (omitted the `)` in
   `// options marker).`). **Recovery:** re-read the exact lines, retried.
   **Prevention:** one-off typo; read the exact anchor text rather than
   reconstructing it from a sibling file's near-identical comment.
3. **Plan "10" vs discovered "11" count divergence.** **Recovery:** used 11 in the
   test (correct) and corrected `session-state.md` inline during review.
   **Prevention:** the Key Insight above — reconcile edited-vs-discovered counts
   for any self-discovering guard built on top of a prior partial fix.

## Tags
category: best-practices
module: apps/web-platform/server/inngest/functions

## Related
- [[2026-06-07-headless-claude-print-plugin-skill-resolution-needs-plugin-dir]] — the root-cause fix this PR applied fleet-wide.
- #4993 (this fix) / #4987 / PR #4989 (content-generator, the pattern source).
