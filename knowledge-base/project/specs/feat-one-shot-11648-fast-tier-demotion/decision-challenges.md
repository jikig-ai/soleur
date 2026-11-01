# Decision Challenges — feat-one-shot-11648-fast-tier-demotion

Persisted per the headless ruling channel (technical-ruling-delegation.md / decision-principles.md). No Task/subagent tool exists in this harness, so CTO-ruling spawns were unavailable; technical items were ruled inline against the shipped doctrine and are recorded as such.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Demote all 8 labels vs. verify calm main-side first (issue's "Alternatively verify against a calm main-side run before demoting on contended PR-leg measurements") | technical | Ruled inline, 2026-11-01 (no Task spawn available): demote all 8 with declared edges; fresh-median re-derivation runs as Phase 0 *evidence* (AC2's either/or), not as a gate that keeps a confirmed >10 s label always-on. Rationale: the #11562 post-merge 8-run medians are canonical `merge_group` artifacts (the as-merged measurement path, not contended PR legs) and corroborate all 8 at 11.4–356.9 s — sustained, not noise; a calm-run re-check is still recorded under `receipts/` so any label reading ≤10 s lands the artifact arm instead. |
| `grep-q-pipe-guard.test.sh` edge shape: keep the existing PARTIAL declared array vs. extend with root-anchored `glob:*.<ext>` PJ_EXTS edges | technical | Ruled inline, 2026-11-01: extend with PJ_EXTS root-anchored globs. Rationale: the suite reads every tracked PJ_EXTS file (S4 PR5 `always_on` verdict was scope-honest: ">25% selection + ≤30 s"); the partial array under-selects — a `.sh` diff outside the named tables that introduces a `grep -q |` violation would decline the very suite that gates it. Over-selection is the safe direction; its resulting high select rate is the truthful classification and is documented in the demotion comment. |
| `lint-gh-argv-arg-live` edge shape | technical | Ruled inline, 2026-11-01: `glob:*.sh` + `.github/workflows/` + SUT. Rationale: the linter's scan scope is every `**/*.sh` + workflow yaml (its own docstring); lint-orphan's live-scanner census requires a DECLARED edge for a `-live` registration — derived edges are explicitly "not enough". |
| `token-drift-workflow-causes` kb reference disposition | technical | Ruled inline, 2026-11-01: covering edge `knowledge-base/engineering/operations/runbooks/` — the suite greps a real heading in `inngest-provision-rehearsal.md` (R4 arm), so it is a real read, not a citation; `test-all-group-affected`'s `P_IRREL` kb path is a synthetic `--paths` member (never read) → baseline `false-positive:` row iff the oracle flags it. |
| Floor re-pin values | technical | Ruled inline, 2026-11-01: `_MIN_ALWAYS_ON_DECLARED` 117→109 and f1 literal 117→109 (122 members − 8 demotions = 114; count−5 convention). Mechanical — the f1 fail text mandates moving both sites together. |
| `lane:` frontmatter value | technical | pending - assumed: `cross-domain`. No spec.md exists for this branch at plan time; the fail-closed default applies (TR2). Domain sweep found engineering-only implications, so the widened default costs nothing here. |
| Threshold / brand-survival | technical | Ruled inline, 2026-11-01: `none`. Repo-internal test-selection metadata; worst defect is a misclassified suite bounded by the CI full battery — no user artifact reachable. |

## Not Yet Specified candidates

None — no fog items surfaced; the two named out-of-scope items (#11647 arm-debt, #11729 ratchet watch) already carry tracking issues.
