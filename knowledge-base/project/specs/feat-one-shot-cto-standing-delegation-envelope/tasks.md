# Tasks: CTO Standing Delegation and Production Envelope

Plan: `knowledge-base/project/plans/2026-10-15-feat-cto-standing-delegation-and-production-envelope-plan.md`
Branch: `feat-one-shot-cto-standing-delegation-envelope`. References only: `Ref #10333`, `Ref #9757` (never `Closes`).
Lane: cross-domain (no `spec.md` carries a lane, so the fail-closed default applies).

Order is test-first: in every phase write the suite and fixtures, show them RED, then write the script.

## Phase 0: Preconditions

- [ ] 0.1 Probe `updated_at` behaviour on a throwaway comment on the PR (post, react, read, delete) and note the result for the ADR.
- [x] 0.2 Measure byte headroom: `ship/SKILL.md` vs ceiling 273955, `one-shot/SKILL.md` vs 52000 (`python3 scripts/lint-skill-body-budget.py --base origin/main`); draft the exact insertion text and count it with `wc -c` before touching either file.
- [ ] 0.3 Measure `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1` and the rule line byte count.
- [x] 0.4 Confirm `pre-ask-technical-fork-gate.sh` payload shape with `__HI_RAW` for a two-question fixture.

## Phase 1: Format reference

- [x] 1.1 Write `plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md`:
  - [x] 1.1.1 delegation record v1 template (marker, blockquote of question plus answer >= 40 chars, `Confirmation:`, numbered Scope, Excluded with ten fixed anchor keywords, `Expiry:` ISO date, `Revoke:`).
  - [x] 1.1.2 `## Production Envelope` template and the `Gate:` v1 grammar (four kinds).
  - [x] 1.1.3 plain-language epic-start confirmation, stall, re-confirm and execution-log wording.
  - [x] 1.1.4 boundaries and residuals (hook-gated forms still defer; shared identity is tamper-evidence only).
- [x] 1.2 Add the executable-template test: extract the templates, instantiate, expect `delegation-verify.sh` to return `valid`.

## Phase 2: delegation-verify.sh

- [x] 2.1 Write `plugins/soleur/scripts/delegation-verify.test.sh` with a PATH `gh` stub (rejects unknown argv), fixtures under `plugins/soleur/test/fixtures/standing-delegation/`, a row per reason token, harness rows H1/H2, mutation rows.
- [x] 2.2 Implement `verify`, `--audit`, `render`, `--self-check` in `plugins/soleur/scripts/delegation-verify.sh`.
- [x] 2.3 Portability pass: no bare `timeout`, `date -d`, `stat -c`, `sed -i`; bash 3.2 and mawk safe.

## Phase 3: hold-gate-eval.sh

- [x] 3.1 Write `plugins/soleur/test/hold-gate-eval.test.sh` and fixtures (plans with holds, envelope section).
- [x] 3.2 Implement `plugins/soleur/skills/ship/scripts/hold-gate-eval.sh` (four kinds, fail closed, exit 0/1/2/3, shared gate-line parser).
- [x] 3.3 Write `plugins/soleur/skills/ship/references/operator-holds.md`; shrink `ship/SKILL.md` step 5 to a pointer within the +183 byte headroom.

## Phase 4: technical-ruling-gate.sh

- [x] 4.1 Add RED cases to `plugins/soleur/test/technical-ruling-gate.test.sh` (valid, invalid, unreadable, wrong class, two-row table, stray row, archive mode shape-only).
- [x] 4.2 Implement the delegation arm (`--audit`), new reasons, `TRG_EXEC_LOG delegation` rows.
- [x] 4.3 Update `technical-ruling-delegation.md` sections 1, 3, 6, 7 (canonical example row) and `decision-challenges-render.md`.

## Phase 5: pre-ask-technical-fork-gate.sh

- [x] 5.1 Add RED cases to `.claude/hooks/pre-ask-technical-fork-gate.test.sh` (cue, mixed spans, mixed case, timeout, missing verifier, two questions, label-only).
- [x] 5.2 Implement the arm (raw-payload span extraction, command-shaped spans only, 5 s cap, allow on any doubt, `emit_incident`).

## Phase 6: pr-overlap-preflight.sh

- 6.1 Write `plugins/soleur/test/pr-overlap-preflight.test.sh` (stub `gh`, jargon assertions, zero write calls, 100-file case, exits 0/10/11/12/13/2).
- 6.2 Implement `plugins/soleur/skills/ship/scripts/pr-overlap-preflight.sh`.
- 6.3 Write `plugins/soleur/skills/ship/references/pr-overlap.md`; wire one-shot Step 0a.5 (<= 1150 bytes) and ship Phase 6.5 before the `merge-main` lock block; do not touch review.

## Phase 7: cto.md and reference

- [x] 7.1 Rewrite the `cto.md` body (frontmatter byte-identical): interface selector, Rule, Own the epic.
- [x] 7.2 Test: each existing caller's spawn phrase selects the intended interface.
- [x] 7.3 Run `bun plugins/soleur/scripts/sync-grok-agent-compat.ts --check` and `sync-cursor-name-map.ts --check`; run the harness-parity census.

## Phase 8: go.md hold routing

- [x] 8.1 Write `plugins/soleur/test/go-hold-routing.test.sh` (tokens, outside markers, fail-closed and ask-once wording, block hash equals merge base).
- [x] 8.2 Add the paragraph outside the `go-routing` markers.

## Phase 9: Doctrine

- 9.1 Amend `hr-menu-option-ack-not-prod-write-auth` (id and `[compliance-tier]` kept, one line, cap ~600 bytes).
- 9.2 `python3 scripts/lint-rule-bodies.py --write`; append the ack row; run the four AGENTS lints against the merge base.

## Phase 10: ADR, C4, learning, finalize

- 10.1 `soleur:architecture` ADR-288 plus `Amended by ADR-288` pointer in ADR-084.
- 10.2 Edit `model.c4` (CTO component, plugin-side and hook-side GitHub edges); run C4 syntax, render and count-parity tests.
- 10.3 Write the compound learning.
- 10.4 Finalize, in this order: regenerate shard manifest (`python3 scripts/regenerate-shard-manifest.py --incremental --write`), re-probe the ADR ordinal across every `origin/*` ref, markdownlint plan and tasks, `lint-skill-body-budget.py`, `lint-guard-contract.py`, `bash scripts/test-all.sh --print-selection` then the bounded default run.
- 10.5 File three follow-up issues (production-change skill, delegated-act digest, receipt-checking hook).
- 10.6 PR body: `Ref #10333`, `Ref #9757`, `## Changelog`, `semver:minor`, the verifier verdicts, the three hold-probe outputs; leave the PR ready and unarmed until `## Operator Holds` discharge.
