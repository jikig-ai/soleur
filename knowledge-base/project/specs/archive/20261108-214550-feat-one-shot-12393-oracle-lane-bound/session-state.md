# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-08-fix-oracle-index-check-manifest-bound-plan.md
- Status: complete

### Errors
- No nested subagent spawn capability: plan/deepen fan-outs ran inline; CTO ruling recorded `pending - assumed:` — parent session must convert via the technical-ruling gate.
- `gh pr diff 12377 -- <paths>` rejected path args; resolved via full-diff filter.

### Decisions
- Matrix-ize oracle-index-check into K=5 parallel legs via new committed scripts/ci-oracle-lane-legs.tsv (label<TAB>leg); serial 65.4min → worst leg ~19min vs 30-min bound.
- Separate legs file (not a manifest column): check_manifest() pins manifest at 2 fields; zero merge-order conflict with open PR #12377.
- Fail-closed run-block semantics + new check_legs() guard pinning legs≡manifest parity.
- #12274 verified already-fixed on origin/main — recommend close-not-Closes.
- Post-merge: `gh variable set CI_ORACLE_LANE --body on` + docs-only canary per runbooks/ci-oracle-lane.md §Activation.

### Components Invoked
- plan skill, deepen-plan skill (inline fallbacks), lint-guard-contract.py

## Operator Constraints

- constraint: shrink scripts/ci-oracle-lane-suites.txt serial runtime under timeout-minutes:30 (parallelize legs or cut mutation-matrix case cost ~11s each) or raise the bound with evidence
- constraint: then gh variable set CI_ORACLE_LANE --body on and re-run a docs-only canary per runbook section Activation
- cto_spawns=1 (batched 4 technical rows → all upheld as assumed; see decision-challenges.md)

## Pipeline Position (2026-11-08)

- Plan+deepen: complete (subagent, all fan-outs inline).
- Technical-ruling gate: PASS rc=0 — 4 technical rows Ruled by CTO agent (batched spawn, upheld); 2 operator rows settled.
- Implementation: committed 131f7c5fce — legs.tsv + ci.yml K=5 matrix + fail-closed run block + check_legs() sentinel + wiring (driver exclusion, AFFECTED edge set, CODEOWNERS, pr-fanout-ledger note, runbook, ADR-276 stage line, tasks.md).
- Sentinel: `bash scripts/ci-oracle-lane.test.sh` green — 4899/4899, 31/31 mutants.
- In flight: `test-all.sh --affected` gate (log /var/tmp/soleur-logs/affected-12393.log, rc file .rc).
- Next: soleur:review → resolve findings → soleur:qa → soleur:compound → soleur:ship → postmerge.
- Post-merge (runbook §Activation, operator-authorized): `gh variable set CI_ORACLE_LANE --body on`, docs-only canary PR, then comment on #12274 verified-fixed + recommend close. Rollback: `gh variable delete CI_ORACLE_LANE`.

## Affected Gate Disposition (2026-11-08)

`bash scripts/test-all.sh --affected` completed rc=1 with exactly 2 suite failures, both
confirmed environmental (not diff-caused):
- `plugins/soleur` redirect-tombstones census — local bare clone is SHALLOW
  (`git rev-parse --is-shallow-repository`=true; docs history truncated to 12 commits).
  The suite's own never-vacuous guard fails loudly by design.
- `apps/cla-evidence/test/ccla-add.test.sh` — 18 rows, all rc=4 (unresolved/env:
  live `gh` account resolution + instrument hashing; webplat toolchain-bound).
  Zero paths in this diff feed it.
Every oracle-manifest suite and the sentinel (4899/4899) are green.

## Review Disposition (2026-11-08)

5-seat panel (security, code-quality, architecture, history+conventions, test-design): no P1.
- P2 fixed inline: `assigned` grammar validation in run block (silent-skip class);
  ORACLE_LEG validator rewrite (per-field grammar on `${ORACLE_LEG:-}`, enumerated
  digits, /5 and 5/ holes closed); discriminating reason pins on all sandbox arms;
  ex_oracle_legs exclusion fixture.
- P3 batch fixed inline: manifest header "serially", ci.yml job comment, aggregator
  failure arm names oracle-index-check + R1k suite row, LEG-BAD-VALUE/LEG-BAD-FIELDS
  pins + mutants, LEG-BUDGET mechanised rebalance trigger (suite-durations join),
  DECLARED_MEMBERS +ci-oracle-review, permuted land-check, runbook omissions,
  legs.tsv regen line, GUARD4 header mapping.
- Scope-out: RATCHET_ORACLE parity (legs file in the advisory oracle-inputs notice
  set) deferred to #12375 — new-file touch + census pins, advisory-only.
- Sentinel after fixes: 4957/4957 rows green, 31/31 mutants killed.
