---
title: "Decision challenges — feat-one-shot-12110-accept-anchor-repin"
date: 2026-11-05
branch: feat-one-shot-12110-accept-anchor-repin
issue: 12110
---

# Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Disposition of the 3 `new-pair` findings — uniform accept rows vs uniform narrow `glob:` edges vs per-suite-convention split (`plugins/soleur`→`glob:scripts/*sentry-issue.sh` edge, `tests/hooks/emissions`→4 accept rows) | technical | Ruled by CTO agent, 2026-11-05: split (arm c) — `"glob:scripts/*sentry-issue.sh"` joins `AFFECTED_PLUGINS_SOLEUR_PATHS` after `glob:scripts/*prod-version-drift-b9-probe.sh` carrying the sibling justification comment verbatim; `tests/hooks/emissions` pairs take 4 anchor-keyed accept rows per the suite's 10-row convention - sibling symmetry (`glob:scripts/*betterstack-query.sh` at test-affected-paths.sh:1306 already covers the same boundary lines) plus 26 commits/90d churn on a vendor block built to grow makes accept anchors self-re-staling; glob edges are reveal-free (never naming-walk nodes) and err toward over-selection, the safe direction for a selector. Dissent: uniform accept rows is the semantically purest arm — the glob is a sanctioned in-tree deviation, so the member must carry the justification comment verbatim. |
| Issue body's proposed mechanism ("re-pin the stale accept rows' anchor SHAs to the commits that last touched the referenced files, or regenerate the accept file") | technical | Ruled by CTO agent, 2026-11-05: descope the literal recipe (arm a); fix per the script's own remedies and document the divergence in the PR body - anchors are 12-hex sha256 prefixes over whitespace-collapsed live lines (a 40-hex git SHA fails the col-3 `^[0-9a-f]{12}$` validator at ci-pr-affected-replay.py:1521-1522 and would flood-parse-error every exemption), `stale-accept` is delete-only (:2056, --help :130-133), and `--print-baseline` writes nothing to disk so no regenerate path exists. Dissent: descoping an issue's stated mechanism is a scope divergence the author did not pre-approve — the PR body must record it explicitly. |
| Brand-survival threshold `none` on a CI-oracle repair | taste | assumed: `none` — diff is exemption rows / a declared edge inside repo-internal test-selection machinery; no user-facing artifact, no regulated-data surface. Challengeable per the plan's User-Brand Impact section. |
| Advisor consult + plan-review panel (soleur:plan Step 4.5, Plan Review stage) | technical | Ruled by CTO agent, 2026-11-05: accept the `Reviewed-Coverage: sequential-fallback` disclosure; no named reviewer panel gates ship (arm a) - the diff is ~17 lines of oracle data whose correctness gate is deterministic (ratchet exit=0 `live=0`), the one judgment fork is settled by ruling, and the ratchet being repaired is advisory (`continue-on-error: true`); orchestrator may still spawn `subagent_general` reviewers with report-only contracts where valuable. Dissent: sequential self-review has a blind spot on `false-positive:` reason-text quality — any row whose reason cannot be grounded in a `file:line` citation merits a second pair of eyes before ship. |

## Not Yet Specified candidates

- None. The fix is fully specified by the ratchet's own remedy classes.
