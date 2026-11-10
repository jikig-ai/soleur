# Mutation proofs and RED evidence: feat-one-shot-10432-web1-workspaces-protection-check

Plan: `knowledge-base/project/plans/2026-11-10-infra-web1-workspaces-volume-protection-check-plan.md`. Every mutation below
ran on a COPY (`SOLE_COPY_DRIFT_WF=<copy>` for the workflow, a scratch copy for the suite, the evaluator or a document);
the real files were never mutated, and each copy was diffed against a pristine backup.

## Phase 1a: green refactor against the unchanged workflow

`bash plugins/soleur/test/sole-copy-drift-check.test.sh` at e7024c5ed4 (the workflow unchanged): `=== Results: 195/195
passed, 0 failed ===`, rc 0, `FLOOR=195`, `TABLE_ROWS=126`.

## Phase 1b: RED

1. Against the unchanged workflow the suite stops at the extractor floor (rc 2): `FATAL: job 'sole-copy-protection-check'
   lacks the matrix rows: strategy.matrix.include must carry the entries inngest and web1 (extractor floor; got null)`.
2. Per-row evidence, against a scaffold-only copy (today's job plus `name:`, `fail-fast: false` and the two include rows;
   every step unchanged): `=== Results: 207/250 passed, 43 failed ===`. All 126 pre-existing table rows stayed green (H3
   counted 157 executed rows = 126 + 31 new). Every one of the 31 new W and C rows failed; its first failure line:

| Row | First failure line (scaffold-only copy) |
|---|---|
| WV1 | probe outputs: got 'verdict=could-not-read\|', want 'expected=true\|http=200\|live=true\|name=soleur-web-platform-data-luks\|tf_age_min=N\|v |
| WV2 | probe outputs: got 'verdict=could-not-read\|', want 'expected=true\|http=200\|live=false\|name=soleur-web-platform-data-luks\|tf_age_min=N\| |
| WV3 | probe outputs: got 'verdict=could-not-read\|', want 'expected=true\|http=200\|live=false\|name=soleur-web-platform-data-luks\|tf_age_min=N\| |
| WV3b | 89 min: got 'could-not-read', want 'lift-pending-apply' |
| WV4 | probe outputs: got 'verdict=could-not-read\|', want 'expected=false\|http=200\|live=false\|name=soleur-web-platform-data-luks\|tf_age_min=N\ |
| WV5 | probe outputs: got 'verdict=could-not-read\|', want 'expected=false\|http=200\|live=true\|name=soleur-web-platform-data-luks\|tf_age_min=N\| |
| WV6 | probe outputs: got 'verdict=could-not-read\|', want 'expected=true\|http=200\|name=soleur-web-platform-data-luks\|tf_age_min=N\|verdict=volu |
| WV8 | probe outputs: got 'verdict=could-not-read\|', want 'expected=true\|http=200\|name=soleur-web-platform-data-luks\|tf_age_min=N\|verdict=volu |
| WT1/soleur-alpha-store | probe outputs: got 'verdict=could-not-read\|', want 'expected=true\|http=200\|live=true\|name=soleur-alpha-store\|tf_age_min=N\|verdict=matc |
| WT1/zz9-other-name | probe outputs: got 'verdict=could-not-read\|', want 'expected=true\|http=200\|live=true\|name=zz9-other-name\|tf_age_min=N\|verdict=matches- |
| WT3 | probe outputs: got 'verdict=could-not-read\|', want 'tf_age_min=N\|verdict=could-not-read\|' |
| WR1 | probe outputs: got 'expected=true\|http=200\|live=true\|name=soleur-inngest-redis-store-luks\|verdict=matches-declared\|volume_id=106903269\ |
| WF1 | title: got 'infra: the Inngest store volume protection check could not read Hetzner (name-unreadable)', want 'infra: web-1 workspaces volume |
| WF3 | state: got 'open', want 'closed' |
| WF12/lifted-outside-terraform | the web-1 body names the Inngest volume |
| WF12/volume-not-found | the web-1 body names the Inngest volume |
| WF12/no-token | the web-1 body names the Inngest volume |
| WF12/could-not-read | the web-1 body names the Inngest volume |
| WX5 | vnf title: got 'infra: the Inngest store volume protection check could not read Hetzner (name-unreadable)', want 'infra: web-1 workspaces vo |
| WX7 | title 1: got 'infra: the Inngest store volume protection check could not read Hetzner (name-unreadable)', want 'infra: the web-1 workspaces  |
| WX9 | title: got 'infra: the Inngest store volume protection check could not read Hetzner (name-unreadable)', want 'infra: the web-1 workspaces vo |
| WX16 | the slug names entry:verdict: got '0', want '1' |
| C1 | commits read path: got 'gh api commits path=inngest-redis-luks', want 'gh api commits path=workspaces-luks' |
| C2 | commits read path: got 'gh api commits path=inngest-redis-luks', want 'gh api commits path=workspaces-luks' |
| C3 | commits read path: got 'gh api commits path=inngest-redis-luks', want 'gh api commits path=workspaces-luks' |
| C4 | commits read path: got 'gh api commits path=inngest-redis-luks', want 'gh api commits path=workspaces-luks' |
| C5 | commits read path: got 'gh api commits path=inngest-redis-luks', want 'gh api commits path=workspaces-luks' |
| C6 | commits read path: got 'gh api commits path=inngest-redis-luks', want 'gh api commits path=workspaces-luks' |
| C8 | commits read path: got 'gh api commits path=inngest-redis-luks', want 'gh api commits path=workspaces-luks' |
| C9 | every Inngest issue is untouched: got '5', want '6' |
| C10 | the could-not-perform filer succeeded without a checkout: got 'failure', want 'success' |

   For the C rows the first line is the shared commits-path invariant (the hard-coded Inngest path on the web-1 leg); each
   row also failed on its own assertion: C1 and C2 on the web-1 leg's probe outputs, C3 `web1: own file 3 h old, other file
   5 min old -> files: got 'could-not-read'`, C4/C5/C6 on their positive control (the web-1 leg's clean run could not close
   its own seeded issues), C8 on the web-1 leg's probe outputs. The other reds of that run are the expected pre-implementation
   ones: S1/S2 control (`id-placement`: the probe's literal pin), S2 "a pin literal in the probe" (did not land), S0b and
   H11a/H11b (the evaluator is not strict yet), N1b (three literals), N1c/N3/H14/H15 (the ADR-119 addendum and the runbook
   6604 read-back section do not exist yet), H3 (TABLE_ROWS not raised yet).
