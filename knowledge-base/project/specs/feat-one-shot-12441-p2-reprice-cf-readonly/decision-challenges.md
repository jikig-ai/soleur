# Decision challenges: feat-one-shot-12441-p2-reprice-cf-readonly

Plan: `knowledge-base/project/plans/2026-11-15-chore-reprice-cloudflare-readonly-suite-weight-plan.md`

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Row-only PR from origin/main vs waiting for #12698 | technical | Ruled by CTO agent, 2026-11-15: open a row-only PR now from origin/main. #12698 is CONFLICTING with main, has auto-merge off and has had no update since 2026-11-13T16:48Z. Never edit or push to #12698. |
| Value and src of the re-priced row | technical | Ruled by CTO agent, 2026-11-15: use 155229 ms, src `measured`, byte-identical to #12698's line, so #12698's rebase hits no conflict on this row's value. Evidence: green merge_group runs 43325786672 / 43324336862 / 43315786965 measured 192026 / 186106 / 129838 ms; #12698's 5-run median is 155229. |
| Regenerate vs hand-edit one row | technical | Ruled by CTO agent, 2026-11-15: a single-row edit if `scripts/regenerate-shard-manifest.py` would rewrite other rows. At plan time, the generator was run on scratch copies (no committed writes). `--incremental` is a no-op for this row. The seed path (`--durations seed --write`) rewrites 140 floor rows, the headers and 45 manifest legs. So the condition holds and the change is a single-row edit. Consequences: no TSV header or provenance-comment change (provenance goes in the commit message and PR body), and the archived P.2 wording ("through the script", "`--incremental` re-prices it", "never hand-edited") is superseded; the `--incremental` premise is false per the generator docstring and the dry run (plan's Research Reconciliation table). |
| `--incremental --durations` header-refresh pass after the hand edit | technical | Ruled by CTO agent, 2026-11-15: do not run it - it changes 2 `suite-shard-legs.tsv` header lines (`default-weight-ms`, `generated-at`), which breaks "edit no other file", and the durations table is already in parity (plan-review devex panel). |
| New generator flag for single-row re-pricing | technical | Ruled by CTO agent, 2026-11-15: no feature issue - the two-step recipe (hand edit plus optional drift-gate check) suffices at today's frequency; revisit only if hand re-seats become frequent (plan-review devex panel). |
| Stale "never hand-edited" doctrine (runbook, ADR-242 amendment text, `scripts/test-all.sh` comments) | technical | Ruled by CTO agent, 2026-11-15: fix it in a docs follow-up, not in this row-only PR - keeps this PR to one row; filed as #12780 (meta/machinery, Post-MVP / Later) (plan-review devex panel). |
| Name the stale `# default-weight-ms=1272` header in Sharp Edges (the generator would now compute 1275; no gate reads the value) | taste | CTO panel suggested a one-line note; not applied (headless taste routing). Surface at ship: add the line if a reviewer flags the header. |
| Plan-review simplifications: drift-gate re-run removed from Gates, local gates cut 8 → 4 weight/shape readers, ACs merged 6 → 3, executable `Ref`-only checks, content anchor in place of line number | taste | Plan-text edits from the eng panel (DHH, Kieran, code-simplicity), auto-applied; no change to what ships. |
