# Decision Challenges — feat-one-shot-11899-convention-suite-cleanup

Depth-1 subagent run (no spawn tool): technical rows that could not be resolved from evidence
are `pending - assumed: <default>`; the parent's technical-ruling gate batches them for the
CTO spawn after this run returns.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Item 8 — floor self-reference (`PRESENCE_ROWS`/`MUT_ROWS` decrement alongside row deletion stays green+FIRES): document-and-keep vs external per-suite constant table in the meta-guard | technical | pending - assumed: document-and-keep — the only anchor that breaks self-reference is a per-suite constant snapshot outside the file (~15× ongoing edit tax on every row-touching edit), which fails the CTO's "cheap invariant" bound; the plan ships a self-reference caveat comment at each floor window + relies on PROMOTED_FILES membership pin (floor deletion) + review (row-count drift) |
| Items 3–4 + SELF scope — issue-named subsets (5 fail>0, 4 step-pin, 2 SELF) vs family-wide census (12 fail>0, 8 step-pin, 5 SELF) | technical | pending - assumed: family-wide convergence — the issue's own frame is "family-wide … items shared with already-merged batch-1/batch-2 convention files"; fixing only the named subsets recreates the asymmetry the issue exists to remove. Scope Check records the extension as inferred-with-justification |
| `EXPECT_1` in ghcr/web-nic — "vestigial" in the issue, but both compares are live (`if [ "$SQL_1" = "$EXPECT_1" ]`) | taste | pending - assumed: keep the whole-string compare, rename `EXPECT_1` → `EXPECT_SQL` (drop the vestigial numbering); deleting a live check would be a coverage loss, not cleanup |
| Item 7 — `PROMOTED_FILES` stale-site marker vs consolidation | technical | resolved inline by evidence — consolidation to the single live site + `grep -c "^PROMOTED_FILES='" == 1` self-pin is strictly stronger than a marker (a marker still permits last-wins drift; the pin makes a second site red) |
| Item 1 — seam-check strengthening approach (CTO-ruling "decide concretely") | technical | resolved inline by evidence — fragment set {`MUT_`, `_SKIP`, `GUARD`, `BASH_ENV`, `SHELLOPTS`, `BASHOPTS`} over the comment-stripped whole-file view + enclosing-job `GITHUB_ENV`/`GITHUB_PATH`/`defaults:` ban; verified each fragment is absent from executable text today and that `validate:` carries no GITHUB_ENV writes; char-level obfuscation documented as residual |
| Census-vocabulary drift target (`_census_missing` et al.) | taste | pending - assumed: normalize to the donor (`egress-gw`) accumulator naming in files already touched; no standalone cosmetic churn |
| inngest-524 tasks.md "<3" stale reference | — | resolved — the reference lives in the archived batch-3 spec dir, a point-in-time artifact; not edited |

## Not Yet Specified candidates

None — every ask mapped in the plan's Scope Check.
