---
title: "`|| true` on a paginated fetch is a silent false-skip, and advisory gating must survive a failed detector"
created: 2026-09-25
source: feat-one-shot-ci-path-gating / PR #8897 review
related: ["2026-09-25-matrix-k-cannot-split-an-atomic-suite"]
---

# Path-gating hazards: exit-status not emptiness; github-actions IS a dep ecosystem; detector failure must run gates

**Prevention:** when writing a fail-open detect that feeds `if:` gating:
(1) capture `gh api --paginate` output with `if ! x=$(…)` — NEVER `x=$(… || true)`:
pagination streams pages 1..N before a page can fail, so `|| true` evaluates
the regex on a TRUNCATED list (check-sweep-completeness.sh already documents
"GATE ON EXIT STATUS, NOT ON EMPTINESS" — the same class).
(2) `.github/workflows/*.yml` is itself a dependency surface (github-actions
ecosystem — `uses:` advisories like the tj-actions incident), so a manifest
detector for dependency-review must trigger on the whole workflows dir, not
its own file.
(3) A failed `detect` job makes `needs:`-dependent gated jobs SKIP — if the
design intent is "skip on proof, not uncertainty", each gated `if:` needs
`always() && needs.detect.result != 'success' ||` before the output check.

**Session errors this PR surfaced:** (a) new test-file pins asserted literal
regex shapes that didn't match the written alternation groups (grep -qF vs
regex-authored strings) — pin on the invariant substring, not the authored
literal; (b) single-quote grep patterns containing `\\\\` wrote a broken
line — validate the test file with `bash -n` immediately after generation;
(c) planner's empty `## Guard Contract` (headings without `### Guard` entries
or mutation matrices) fails `lint-guard-contract-live` in CI even though it
reads complete to a human — the last step of plan drafting must RUN
`python3 scripts/lint-guard-contract.py <plan>` before committing.
