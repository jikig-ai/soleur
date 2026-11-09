# Decision Challenges — feat-one-shot-12375-oracle-lane-nits (#12375)

Pipeline-mode plan; no Task/Agent tool available, so the CTO Rule interface was
emulated inline by the planner with repo-verified evidence (each ruling cites
`file:line`). Operator-class rows surface at ship time.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| T1 — item 2 fix shape: retitle-only vs surgical lock-conjunct mutant | technical | Ruled by CTO-role (inline emulation — no Task tool in subagent context), 2026-11-09: add the surgical conjunct mutant AND retitle the existing row — sibling precedent `scripts/ci-pr-selection.test.sh:1455` carries the exact shape (sed-drops ` && [ "$locked" = false ]`, driven by `row_lock`); verified `row_switch` never sets `ORACLE_LANE_LOCKED` so only `row_lock` can kill a conjunct mutant; retitle-only leaves the conjunct unproven — the gap the issue names. Dissent: the wholesale `kill_guard O-ARM` row and the surgical row partially overlap — a conjunct-dropping mutant on the arm line arguably implies arm-presence; the marginal cost of keeping both is one `mutate` call |
| T2 — item 4 `cmp -s` pin: annotate vs drop | technical | Ruled by CTO-role (inline emulation — no Task tool in subagent context), 2026-11-09: annotate as intentional — `LOCK_RE` (test:243) drives both the `_lockn` count (:1059) and the `sed` recipe (:245) so the pin is redundant *as a lock check* today, but its residual property is real: it bounds the recipe's blast radius, and `$UNLOCKED` is the file `row_switch` (:1046) and two mutants (:1548-1552) are measured against — a recipe/`LOCK_RE` drift matching anything else reds `cmp` while `_lockn` stays green; cost of keeping is one comment line. Dissent: the residual property is thin — recipe drift is an unlikely shape and L1062's `grep -c` on `$UNLOCKED` already covers the plausible accidents; the honest case is one line of comment vs one line of check |
| O1 — fold-in of two unlisted stale-comment sites (c4-likec4-version-pin.test.ts:262-264, ci-draft-light.test.sh:99) | operator (scope) | Folded into the plan as inferred items with justification — identical defect class found by the mandated repo-wide `ORACLE_LANE_LOCKED` sentinel sweep (`hr-write-boundary-sentinel-sweep-all-write-sites`); one comment line each; leaving them preserves the exact false-confidence signal the issue names. Surfaced here so the scope extension beyond the issue's two named ci.yml sites is visible at PR time |

## Sign-offs (non-table record — the gate's shape accepts only CTO/CLO rulings)

None — `brand_survival_threshold: none` (internal CI/test files; no user data, auth, or production surface). No sensitive-path diff per the canonical `SENSITIVE_PATH_RE`.

## BLOCKED rows

None — every ask mapped and every inferred item carries a justification in
`## Scope Check` → `### Plan-Item Provenance`.
