# Decision Challenges — feat-one-shot-6760-security-scan-dir-leak

Headless/pipeline planning run inside a Task-free subagent context (Devin
CLI). No agent-spawn capability: technical rulings are recorded
`pending - assumed` per the technical-ruling-delegation contract; `ship`
renders this table into the PR body and files `action-required` issues.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| #6760's core ask is already satisfied on `main` (startup age-reap shipped 2026-07-22 via PR #6828 / issue #6789; `run-scan.sh:215-224`). The pipeline's stated direction was "fix the leak"; plan re-scoped to close-out + residual hardening (docs, scratch-orphan sweep, stale-comment correction, issue close). | operator (scope) | Surfaced, not silently applied — recorded here for `ship` to render; the PR body cites the shipped mechanism as evidence. Operator may confirm close-out or request deeper redesign at review. |
| Retention floor value: shipped default is 10080 min (7 days), not the "N hours" the issue sketched — deliberate for GDPR Art. 32 evidence retention (override-artifact `findings_json` path form can lag the scan). Keep 7-day floor for both families vs. a shorter/separate `SKILL_SCAN_SCRATCH_REAP_MIN` seam for scratch. | technical | pending - assumed: reuse `_reap_min` for both families; scratch older than 7 days belongs to a dead scan by construction, and a second tunable buys a marginal bound. `SKILL_SCAN_META_REAP_MIN` remains the single override. |
| Extend the startup reap beyond the issue's named family (`skill-security-scan-*`) to the `skill-scan-*` scratch families (`skill-scan-input-*`, `skill-scan-results-*`, `skill-scan-XXXXXX` + `.code/.fm/.body/.req/.resp` siblings) — inferred scope, justified by the measured leak (45 input + 4 results artifacts on the #6726 incident date) and the same tmpfs harm class. | technical | pending - assumed: include; same producer, same property (bounded tmpfs footprint), same mechanism site, ~10 lines. Operator can cut it at review without losing the close-out. |
| Also sweep `skill-security-scan-*` under `${TMPDIR:-/tmp}` (the XDG-toggle crossover: meta dirs created under `/tmp` before `XDG_RUNTIME_DIR` was set are unreachable by the meta-base sweep once env flips). | technical | pending - assumed: include as one `-o` arm in the scratch sweep; consistent with the same age-floor policy for the durable family. |
| `! -path "$INPUT" ! -path "$results_dir"` own-scratch exclusions — needed because own-scratch is created *before* the reap (unlike `meta_dir`), and a pathological low floor (the test seam uses `0`) combined with ≥1-min category checks would reap live own-scratch mid-run. | technical | pending - assumed: include; defensive at near-zero cost, fails toward under-reaping (conservative direction for a leak guard). |
| Scoped advisor consult (Step 4.5) and multi-agent plan-review panel could not run — no Task-spawn capability in this context. Plan review executed inline against the eng-panel lenses (overengineering / correctness / YAGNI / spec-flow edges). | technical | pending - assumed: accepted; deepen-plan's own gate phases and CI review follow as the next review layers. |
