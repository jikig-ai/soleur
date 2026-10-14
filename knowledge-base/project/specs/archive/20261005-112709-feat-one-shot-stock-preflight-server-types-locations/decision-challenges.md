# Decision challenges — feat-one-shot-stock-preflight-server-types-locations

Persisted by plan-review (headless). Each item is a Taste or User-Challenge finding; the plan keeps the stated default, and the operator can redirect.

## 2026-10-05 plan-review

1. **Oversized relative to the fix (DHH, code-simplicity).** Proposal: collapse the verdict to a one-line `== [true]` comparison, drop exactly-one and the token enum, drop Guard 5, cut the plan ceremony; about 35% fewer lines. Plan default: KEEP the enum and the exactly-one clauses (each is one jq clause and gives the distinct messages the brief asks for), CUT Guard 5's harness rows, the name-shape guard, the junk-sibling clauses, the file-override seam and duplicate tests. Why: threshold is `single-user incident`; a wrong authorization strands a live host.
2. **Loopback python3 test vs a PATH `curl` shim for the `--fail-with-body` guard.** DHH and simplicity prefer the shim (no new dependency or flake surface). CTO, Kieran and SpecFlow want the real wire exchange. Plan default: loopback, trimmed to three cases, bounded readiness wait, composed traps, named failure if python3 is missing.
3. **Deny on a past `deprecation.unavailable_after` even when `available:true` (SpecFlow I5).** Plan default: do not read `deprecation` (the old gate never did; Hetzner folds it into `available`); a must-PASS fixture pins the decision. Revisit if that combination is ever observed.
4. **Commit the mutation battery (CTO).** Plan default: scratch-only with the table in the PR body, because a new suite needs registration in suite-durations.tsv, suite-shard-legs.tsv, test-affected-paths.sh and the orphan-suite lint. Residual risk (guards unprotected against later refactors beyond the suite cases and floor) is named in the PR body.
5. **Gate on `-w '%{http_code}'` 2xx-only rather than `--fail-with-body` (Kieran L2).** Plan default: `--fail-with-body` (a 3xx is not followed and fails the shape guards).
