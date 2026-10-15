# Tasks: CTO Standing Delegation and Production Envelope

Plan: `knowledge-base/project/plans/2026-10-15-feat-cto-standing-delegation-and-production-envelope-plan.md`
Branch: `feat-one-shot-cto-standing-delegation-envelope`. References only: `Ref #10333`, `Ref #9757` (never `Closes`).
Lane: cross-domain (no `spec.md` carries a lane, so the fail-closed default applies).

Order is test-first: in every phase write the suite and fixtures, show them RED, then write the script.

## Phase 0: Preconditions

- [ ] 0.1 (not run: needs a GitHub write; ADR-288 states the behaviour as an observation only) Probe `updated_at` behaviour on a throwaway comment on the PR (post, react, read, delete) and note the result for the ADR.
- [x] 0.2 Measure byte headroom: `ship/SKILL.md` vs ceiling 273955, `one-shot/SKILL.md` vs 52000 (`python3 scripts/lint-skill-body-budget.py --base origin/main`); draft the exact insertion text and count it with `wc -c` before touching either file.
- [x] 0.3 Measure `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1` and the rule line byte count (review-fix round: B_ALWAYS=44263 WARN, rule line 596 bytes).
- [x] 0.4 Confirm `pre-ask-technical-fork-gate.sh` payload shape with `__HI_RAW` for a two-question fixture.

## Phase 1: Format reference

- [x] 1.1 Write `plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md`:
  - [x] 1.1.1 delegation record v1 template (marker, blockquote of question plus answer >= 40 chars, `Confirmation:`, numbered Scope, Excluded as one fixed sentence (the ten-keyword check was replaced in the review-fix round), `Expiry:` ISO date, `Revoke:`).
  - [x] 1.1.2 `## Production Envelope` template and the `Gate:` v1 grammar (two kinds after the review-fix round: `pr-merged`, `no-inflight-run`).
  - [x] 1.1.3 plain-language epic-start confirmation, stall, re-confirm and execution-log wording.
  - [x] 1.1.4 boundaries and residuals (hook-gated forms still defer; shared identity is tamper-evidence only).
- [x] 1.2 Add the executable-template test: extract the templates, instantiate, expect `delegation-verify.sh` to return `valid`.

## Phase 2: delegation-verify.sh

- [x] 2.1 Write `plugins/soleur/scripts/delegation-verify.test.sh` with a PATH `gh` stub (rejects unknown argv), fixtures under `plugins/soleur/test/fixtures/standing-delegation/`, a row per reason token, harness rows H1/H2, mutation rows.
- [x] 2.2 Implement `verify`, `--audit`, `render`, `--self-check` (the last is deleted in the review-fix round) in `plugins/soleur/scripts/delegation-verify.sh`.
- [x] 2.3 Portability pass: no bare `timeout`, `date -d`, `stat -c`, `sed -i`; bash 3.2 and mawk safe.

## Phase 3: hold-gate-eval.sh

- [x] 3.1 Write `plugins/soleur/test/hold-gate-eval.test.sh` and fixtures (plans with holds, envelope section).
- [x] 3.2 Implement `plugins/soleur/skills/ship/scripts/hold-gate-eval.sh` (four kinds, fail closed, exit 0/1/2/3, shared gate-line parser; `command` and `run-green` are deferred in the review-fix round, CTO ruling R1).
- [x] 3.3 Write `plugins/soleur/skills/ship/references/operator-holds.md`; shrink `ship/SKILL.md` step 5 to a pointer within the +183 byte headroom.

## Phase 4: technical-ruling-gate.sh

- [x] 4.1 Add RED cases to `plugins/soleur/test/technical-ruling-gate.test.sh` (valid, invalid, unreadable, wrong class, two-row table, stray row, archive mode shape-only).
- [x] 4.2 Implement the delegation arm (`--audit`), new reasons, `TRG_EXEC_LOG delegation` rows.
- [x] 4.3 Update `technical-ruling-delegation.md` sections 1, 3, 6, 7 (canonical example row) and `decision-challenges-render.md`.

## Phase 5: pre-ask-technical-fork-gate.sh

- [x] 5.1 Add RED cases to `.claude/hooks/pre-ask-technical-fork-gate.test.sh` (cue, mixed spans, mixed case, timeout, missing verifier, two questions, label-only).
- [x] 5.2 Implement the arm (raw-payload span extraction, command-shaped spans only, 5 s cap, allow on any doubt, `emit_incident`). SUPERSEDED: the whole arm (5.1 and 5.2) was removed in the review-fix round by CTO ruling R2.

## Phase 6: pr-overlap-preflight.sh

- [x] 6.1 Write `plugins/soleur/test/pr-overlap-preflight.test.sh` (stub `gh`, jargon assertions, zero write calls, 100-file case, exits 0/10/11/12/13/2).
- [x] 6.2 Implement `plugins/soleur/skills/ship/scripts/pr-overlap-preflight.sh`.
- [x] 6.3 Write `plugins/soleur/skills/ship/references/pr-overlap.md`; wire one-shot Step 0a.5 (<= 1150 bytes) and ship at the start of Phase 6.45, before the archive move (moved from 6.5 in the review-fix round); do not touch review.

## Phase 7: cto.md and reference

- [x] 7.1 Rewrite the `cto.md` body (frontmatter byte-identical): interface selector, Rule, Own the epic.
- [x] 7.2 Test: each existing caller's spawn phrase selects the intended interface.
- [x] 7.3 Run `bun plugins/soleur/scripts/sync-grok-agent-compat.ts --check` and `sync-cursor-name-map.ts --check`; run the harness-parity census.

## Phase 8: go.md hold routing

- [x] 8.1 Write `plugins/soleur/test/go-hold-routing.test.sh` (tokens, outside markers, fail-closed and ask-once wording, block hash equals merge base).
- [x] 8.2 Add the paragraph outside the `go-routing` markers.

## Phase 9: Doctrine

- [x] 9.1 Amend `hr-menu-option-ack-not-prod-write-auth` (id and `[compliance-tier]` kept, one line, cap ~600 bytes).
- [x] 9.2 `python3 scripts/lint-rule-bodies.py --write`; append the ack row; run the four AGENTS lints against the merge base.

## Phase 10: ADR, C4, learning, finalize

- [x] 10.1 `soleur:architecture` ADR-288 plus `Amended by ADR-288` pointer in ADR-084.
- [x] 10.2 Edit `model.c4` (CTO component, plugin-side GitHub edge; the hook-side edge was dropped in the review-fix round, R2); run C4 syntax, render and count-parity tests.
- [x] 10.3 Write the compound learning.
- [x] 10.4 (shard manifest, ordinal re-probe, markdownlint, body-budget and guard-contract lints done; `--print-selection` and the bounded default run belong to the ship step) Finalize, in this order: regenerate shard manifest (`python3 scripts/regenerate-shard-manifest.py --incremental --write`), re-probe the ADR ordinal across every `origin/*` ref, markdownlint plan and tasks, `lint-skill-body-budget.py`, `lint-guard-contract.py`, `bash scripts/test-all.sh --print-selection` then the bounded default run.
- [x] 10.5 File three follow-up issues (production-change skill, delegated-act digest, receipt-checking hook).
- [ ] 10.6 PR body: `Ref #10333`, `Ref #9757`, `## Changelog`, `semver:minor`, the verifier verdicts, the three hold-probe outputs; leave the PR ready and unarmed until `## Operator Holds` discharge.

## Review-fix round (PR #10348, 2026-10-15)

Nine review seats reported on the pinned head; the contract and the four CTO rulings (R1 to R4, Ruled by CTO agent, 2026-10-15) are
recorded in `decision-challenges.md` (rows RF-R1 to RF-R4) and ADR-288. Other fix agents own the items without a checkbox; their
state is read from their commits, not from this file.

Dispositions by class:

- Technical rulings (CTO): R1 defer `Gate: command` and `Gate: run-green`; R2 remove the hook delegation arm; R3 enforce execution
  receipts in the ship gate; R4 keep the overlap preflight in this PR as a separate section and commit range.
- Verifier (agent F1a): closed command allowlist, scope binding, epic binding, envelope read from git HEAD, audit needs `--at`, render
  guards and secret refusal, fixed Excluded sentence, App-authored comments rejected, `--self-check` and `keywords` deleted.
- Gate and hold evaluator (agent F1b): no-delegation exit 3 first, receipt check, memoised verification, case-insensitive heading,
  in-flight statuses, `</dev/null` on every call.
- Overlap preflight (agent F2): collaborator-only stops, all-files duplicate rule, noise filter, run deadline, `--issue` dropped.
- Prose and routing (agent F3a): `${CLAUDE_PLUGIN_ROOT}` paths, selector cue anchoring, go Step 1.5 trigger, stop path.
- Docs (agent F3b, this file's owner):
  - [x] The amended rule's menu-ack sentence carries the exception ("outside a recorded delegation"); line is 596 bytes; new hash
        `4b86563d5be5ac98e1b377057a0ea34fd0761fd0087258bf9c4b5b4f6c5dd068` (superseded by the second round below).
  - [x] The ack row states the widening honestly, cites `fa06eef79a` and the 2026-04-19 learning, and asks for human review.
  - [x] The four AGENTS lints plus `lint-rule-bodies --check --base origin/main` pass.
  - [x] ADR-288: claims corrected (no "two independent keys", receipt scope, "no seam in the script", AP-020 and AP-024, 5 s cap
        removed), V1 to V5, R1 to R4, precedents, residuals, overlap preflight as its own section.
  - [x] Learning: the false merge-hook claim replaced by the verified `ship-kb-archive-gate.sh` behaviour.
  - [x] C4: hook-side edge and hooks-to-plugin verifier mention removed; plugin-to-github comment corrected; model re-rendered
        (churn back to 40 lines); freshness, count-parity and render tests pass.
  - [x] `decision-challenges.md`: rows RF-R1 to RF-R4 and RF-1 to RF-8; `technical-ruling-gate.sh --branch` passes.
  - [x] Plan: `## Observability` cites layer-7 artifacts per failure mode and reads a committed artifact; `## Operator Holds`
        states the exit-3 prose path and the second evaluation before arming.
  - [x] Shard weights of the five new suites set from measured seconds.
  - Not done here: `.gitattributes` already marks `model.likec4.json` as `linguist-generated=true` on main.

## Second review-fix round (PR #10348, fix SHA 111cc1b43a)

Two more seats reported (fix-round architecture and security). Items owned by other agents carry no checkbox.

- Docs (agent F3b, this file's owner):
  - [x] The amended rule names the closed command set (merge, ready, dispatch, revert-PR) instead of "merge/dispatch/revert only";
        the line is 599 bytes; new hash `62f7ef9a380a9cc426964de82361b71db4fdd0f02cea987c683630a6e694bf7c`; the ack row carries the new
        sha256 and the same closed set; the five AGENTS lints pass.
  - [x] ADR-288 and the learning: the CTO records the `ran <ISO>` row after each act, receipt enforcement fires only for rows
        carrying `ran`, and the receipt window rules are stated as the gate's contract.
  - [x] ADR-288, the learning and row T5: the routing trigger is an epic reference AND a `HOLDS:` list.
  - [x] `decision-challenges.md`: T1, T4, T5, C1 and R3 carry a supersession note; rows RF-9 to RF-11 added; the ruling gate passes.
  - [x] Plan: supersession banner, struck/annotated Gate grammar, `--audit`, `--issue`, Phase 5, Guard 3 and the FR3/FR5 boxes; tasks
        1.1.1 and 1.1.2 corrected.
  - [x] C4 and ADR: the plugin-to-github edge names the ship gate's receipt read; model re-rendered; the three C4 tests pass.
  - [x] Residuals recorded: self-asserted `ran` bound to a receipt window, a hold discharges when its condition is true whoever it is
        reserved to (mitigated by the `Operator-reserved:` grammar), and the verifier trust base with its flip condition.
- Not recorded as an ADR residual because another agent may still fix it: the grammar guards `Command:` only while Verification,
  Abort and Rollback text is not vetted (security N2/N1 of the fix round), and revocation falling back to an older delegation.
- Verifier, gate, hold evaluator, cto.md and go.md changes from these reports belong to their fix agents.

## Final fix batch (PR #10348, verification pass at 43cffd6705)

The verification pass found no P1. Items owned by other agents carry no checkbox.

- Docs (agent F3b):
  - [x] ADR-288 "What the ship gate checks": the CTO records the `ran` row (it replaces the plan-time row) and the exact receipt
        rules are listed, including the `ran` instant, unedited, person-authored and one-per-row.
  - [x] ADR-288: the pre-arming check sits at the start of Phase 6.45 and the residual is recorded; envelopes stay out of archived
        directories; the vehicle row reaches the PR body through the normal body update; "Revert only" removed from line 46.
  - [x] ADR-288 residuals: the `Operator-reserved:` removal path, the Verification, Abort and Rollback vetting limits, same-identity
        forgery, and that the verification pass found no P1.
  - [x] Plan, tasks 6.3 and session-state: stale Phase 6.5 and ask-hook text annotated; repo-relative script paths replaced by
        `${CLAUDE_PLUGIN_ROOT}`.
- Not done here (other owners or open): the vetting gaps in security V1 to V7 (denylist narrowing, comment markers inside code
  fences, unreadable hold markers, prefix spellings of `Operator-reserved:`, negation phrasing); the receipt-predates-act check
  (V8) is documented as a gate rule and must be confirmed in `technical-ruling-gate.sh`.
