# Decision Challenges — feat-one-shot-5987-redaction-hardening

Headless-mode record of Taste / User-Challenge decisions from plan Step 4.5 (fable advisor) +
Plan Review (architecture-strategist, spec-flow-analyzer, code-simplicity-reviewer). `ship` Phase 6
renders these into the PR body and files an `action-required` issue for operator review. Both
challenges reduce scope vs the issue's literal wording; each is also security- or correctness-motivated,
so the plan applies the reviewer-converged direction and surfaces it here for reversal.

## UC1 — Drop offset-mapping "back to original"

- **Issue wording:** "NFKC-normalize + zero-width-strip BEFORE matching … (offset-mapped back to original)".
- **Reviewer-converged direction (applied):** use **whole-string** NFKC and report the
  normalized-string offset (`m.start()`) — **do not** map back to the original text.
- **Why the change:** (a) a per-codepoint offset map is a genuine **fail-open** — per-codepoint NFKC
  ≠ whole-string NFKC, so a decomposed/combining sequence folds to an ASCII secret only whole-string
  (spec-flow G2). (b) offset-to-original is a **reporting nicety** — the sentinel *halts*, never
  rewrites in place (unlike gstack), and no consumer parses the offset; the current bash script already
  prints match-length in the "offset" slot. (c) it removed ~15 lines of complexity + one Sharp Edge
  (code-simplicity cut #1, fable "collapse to one string").
- **Operator decision:** keep normalized-offset reporting (recommended), OR require true
  offset-to-original (would reintroduce per-codepoint mapping + the fail-open risk — not recommended).

## UC2 — Wire legal-generate only; defer legal-audit

- **Issue/spec wording:** "Apply to `incident`/`code-to-prd`/legal redaction **paths**" (plural).
- **Reviewer-converged direction (applied):** wire **legal-generate** (the real new-egress path,
  gated *before* inline presentation); **defer legal-audit** to a follow-up issue.
- **Why the change:** legal-audit findings quote **already-committed** documents (redacting the inline
  echo un-leaks nothing), and correct gating would require scanning *every* inline surface it emits
  (escalation H3, deadline banner, catalog pointer), not just the findings buffer (spec-flow G5) —
  disproportionate for a lower-value path (code-simplicity cut #2).
- **Operator decision:** accept legal-generate-only for this PR (recommended; follow-up bundles
  legal-audit + digest-scrub), OR require legal-audit gating inline now (must gate all emitted surfaces).
