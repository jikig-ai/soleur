# Learning: fixture fields must match the wire shape, and jq's `//` swallows `false`

## Problem

Two defects surfaced in one fix-round on `scripts/followthroughs/inngest-cli-apply-window-7463.sh` (PR #11994), each invisible to a 74-arm green suite:

1. **`.databaseId` is not a REST field.** The probe read `[.databaseId, .created_at, .conclusion]` out of `gh api repos/…/actions/runs`, but the REST payload carries `id` (`databaseId` is the `gh run list --json` GraphQL name; verified live — `{"databaseId":null,"id":…}`). Every fixture used `databaseId`, so suite and probe agreed with each other and disagreed with the wire. On real data the null projection collapsed the TSV: dispatch side → jobs read on an ISO timestamp → permanent rc 3; health side → `hconcl` becomes `""` → **false NOT-YET forever** — the never-PASS class the fix-round was closing. Present since the probe's birth (`e7bf4793cb`), i.e. the probe could never have established a verdict on real data. (#7081 stub-fidelity class: the fake answers questions the API never asks.)
2. **`// []` swallows `false`.** jq's alternative operator treats `false` like `null`, so `(.workflow_runs // [])` and `(.jobs? // [])` parsed a `false`-typed member as measured-empty — bypassing the `type == "array"` counted-fault guard that had just been added. Contract says only absent/null is empty; `false` is drift.

## Solution

- Read `.id` in both list projections; re-key every fixture (`add_run`/`add_health` helpers and raw `printf` payloads) to `id` so the suite pins the real wire shape.
- Replace `// []` with an explicit `if . == null then empty elif type == "array" then .[] else error(...) end` predicate on all three read sites; new arms (`runsfalse`, `jobsfalse`, `healthfalse`, `runsobject`, `healthobject`, `runsabsent`, `runsnull`, `healthabsent`) pin every member of the absent/null/false/object matrix.
- Harden discriminating arms so the buggy path produces a **demonstrable false-PASS** (planted phantom jobs + health → rc 0), not merely rc≠expected — a pin that survives a weakened message assertion.

## Key Insight

A fixture that matches the *convenient* shape (`gh run list --json`'s `databaseId`) instead of the *wire* shape (REST `id`) certifies a probe against a contract the vendor never signed. Verify the projection field against the real API once (`gh api <path> --jq '.[0] | keys'`), and treat `//` as a false-swallowing coalesce — when absent/null/false have different verdicts, spell the predicate `== null`, never `//`.

## Session Errors

1. First `emit-review-trailer.sh --fix-round` emit omitted `--agents-ran/--agents-expected` → `Reviewed-Fix-Round: unknown`; recovered by `git reset --soft` on the unpushed empty commits and re-emitting with counts. **Prevention:** fix-round emits need seat counts just like panel emits — pass them on the first call.
2. Two `git commit` forms were hook-blocked (`$VAR` path; env mutation in the same command). **Prevention:** literal `git -C <abs-path>` and split add/commit calls — the worktree landmine protocol, already documented.

## Tags

category: test-failures
module: scripts/followthroughs
