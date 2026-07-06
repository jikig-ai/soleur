# Tasks — fix(telemetry): rule-incident aggregation locality (#6042)

lane: single-domain
Plan: `knowledge-base/project/plans/2026-07-06-fix-rule-incidents-ci-telemetry-locality-plan.md`

Scope: ship Phases 1-3 (aggregator no-op, compound authoritative write, drop CI schedule). Cross-worktree read-merge + `first_observed` obsolescence are DEFERRED to a follow-up issue (see plan `## Deferred to follow-up`).

## Phase 1 — Aggregator: no-op on zero DATA lines

- [ ] 1.1 In `scripts/rule-metrics-aggregate.sh`, initialize `valid_lines=0` and `drops_total=0` at top level BEFORE the `if [[ -s "$INCIDENTS_MERGED" ]]` block (`:~108`) — prevents an unbound-variable abort under `set -euo pipefail` on the empty/absent path.
- [ ] 1.2 Add a no-op guard keyed on `valid_lines == 0` that gates only the file WRITE (`:339`), leaving Stage A/B/C build (`:197-300`) and the `--dry-run` print (`:314`) intact. Emit a stderr skip line; on `drops_total>0` also echo the drop breakdown.
- [ ] 1.3 Confirm rotation (`:368`, already `-s`-gated) is unreachable on empty input.
- [ ] 1.4 Add tests to `scripts/rule-metrics-aggregate.test.sh`: (a) empty log, (b) absent file, (c) sentinel-only log — each exits 0, writes nothing, leaves a pre-existing committed file byte-identical, no unbound-var abort; (d) `--dry-run` still prints JSON on empty input.

## Phase 2 — compound: authoritative local write

- [ ] 2.1 In `plugins/soleur/skills/compound/SKILL.md` Phase 1.5 Step 8, run `scripts/rule-metrics-aggregate.sh` for real (writes `rule-metrics.json`), then stage conditionally: `git diff --quiet -- <OUT> || git add <OUT>`. Add one stderr line noting whether it staged.
- [ ] 2.2 Remove/supersede the `--dry-run` hint prose so there is no dead reference; keep the redaction-safe framing (no `command_snippet` committed).

## Phase 3 — CI cron: drop the schedule

- [ ] 3.1 Remove the `schedule:` trigger from `.github/workflows/rule-metrics-aggregate.yml`; keep `workflow_dispatch`.
- [ ] 3.2 Update the workflow header comment to the local-producer model; cite ADR-091.
- [ ] 3.3 Confirm `bot-pr-with-synthetic-checks` no-ops on an empty diff (no empty PR on a manual fresh-checkout dispatch).

## Phase 4 — ADR + docs

- [ ] 4.1 Write `knowledge-base/engineering/architecture/decisions/ADR-091-rule-metrics-local-producer.md` (provisional ordinal) with `## Decision`, `## Alternatives Considered` (A/C rejected), the ADR-3 supersession note, the ADR-054 divergence note.
- [ ] 4.2 Add a one-line back-pointer `> ADR-3 superseded by ADR-091 (#6042)` to `knowledge-base/project/plans/2026-04-14-feat-rule-utility-scoring-plan.md`.
- [ ] 4.3 At ship: re-verify the ADR-091 ordinal against `origin/main`; if renumbered, sweep this plan + tasks.md + ACs in one edit.

## Phase 5 — Verify + defer

- [ ] 5.1 `bash scripts/rule-metrics-aggregate.test.sh` green; no regression in drop-sentinel counts / `orphan_rule_ids`; `SCHEMA_VERSION` still 1.
- [ ] 5.2 File the single follow-up issue (cross-worktree read-merge + `first_observed`) per plan `## Deferred to follow-up`, milestone `Post-MVP / Later`, `Ref #6042`.
- [ ] 5.3 PR body uses `Ref #6042` (not `Closes`); close #6042 post-merge after AC7 (real-data proof) is observed once.
