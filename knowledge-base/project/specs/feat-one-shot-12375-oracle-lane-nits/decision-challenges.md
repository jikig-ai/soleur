# Decision Challenges — feat-one-shot-12375-oracle-lane-nits (#12375)

Pipeline-mode plan; no Task/Agent tool available, so the CTO Rule interface was
emulated inline by the planner with repo-verified evidence (each ruling cites
`file:line`). Operator-class rows surface at ship time.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| T1 — item 2 fix shape: retitle-only vs surgical lock-conjunct mutant | technical | Ruled by CTO agent, 2026-11-09: retitle the `kill_guard O-ARM` row to name arm-presence AND add a surgical conjunct mutant sed-dropping ` && [ "$locked" = false ]` from `GUARD:O-ARM` on `$PRISTINE`, driven by `row_lock` - verified at HEAD: driver arm `ci-oracle-lane.sh:384`, `kill_guard` whole-line replacement (test:1514/:1552) proves arm-presence only; the conjunct-drop is non-vacuous (`row_lock` asserts `active=false` at :949-951; `row_switch` never sets `ORACLE_LANE_LOCKED`); sibling precedent verbatim at `ci-pr-selection.test.sh:1455`; retitle-only leaves the conjunct-deletion gap the issue names unproven. Dissent: the detection capability already exists (`row_lock` would red such an edit if run), so (b) proves coverage rather than creates it — but proving detection is the entire purpose of a mutation battery |
| T2 — item 4 `cmp -s` pin: annotate vs drop | technical | Ruled by CTO agent, 2026-11-09: annotate the `cmp -s "$PRISTINE" "$UNLOCKED"` pin as intentional blast-radius coverage; keep it - verified at HEAD (pin at test:1060-1061): `LOCK_RE` (:243) feeds both `_lockn` (:1058-1059) and the sed recipe (:245) so it is redundant as a lock check, but it is the only check that reds when the recipe over-deletes (`_lockn` counts only `LOCK_RE` matches; :1062 asserts absence only), and `$UNLOCKED` is the `row_switch` control operand (:1046) and mutation base for three mutants (:1548/:1549/:1552). Dissent: the covered failure shape (a recipe edit that over-deletes while `LOCK_RE` still matches zero) is unlikely — belt-and-suspenders more than load-bearing; a reasonable first deletion if battery culture slims down |
| O1 — fold-in of two unlisted stale-comment sites (c4-likec4-version-pin.test.ts:262-264, ci-draft-light.test.sh:99) | operator (scope) | Folded into the plan as inferred items with justification — identical defect class found by the mandated repo-wide `ORACLE_LANE_LOCKED` sentinel sweep (`hr-write-boundary-sentinel-sweep-all-write-sites`); one comment line each; leaving them preserves the exact false-confidence signal the issue names. Surfaced here so the scope extension beyond the issue's two named ci.yml sites is visible at PR time |

## Sign-offs (non-table record — the gate's shape accepts only CTO/CLO rulings)

None — `brand_survival_threshold: none` (internal CI/test files; no user data, auth, or production surface). No sensitive-path diff per the canonical `SENSITIVE_PATH_RE`.

## BLOCKED rows

None — every ask mapped and every inferred item carries a justification in
`## Scope Check` → `### Plan-Item Provenance`.
