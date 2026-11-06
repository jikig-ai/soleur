---
title: "fix: green the advisory affected-index-ratchet by accepting the 5 inngest follow-through mention pairs"
type: fix
date: 2026-10-31
slug: fix-affected-index-ratchet-accept-rows
branch: feat-one-shot-11694-ratchet-accept-rows
issue: 11694
closes: 11694
priority: medium
domain: ci
lane: single-domain
brand_survival_threshold: none
---

## Enhancement Summary

**Deepened on:** 2026-10-31
**Sections enhanced:** 3 (`## Observability` added; Gate Dispositions corrected; halt-gate evidence recorded)
**Research agents used:** none spawned — Devin CLI harness has no plugin subagents; all prescribed roles (per-section research, review agents, verify-the-negative, learnings filter) ran sequentially inline. `Reviewed-Coverage: sequential-fallback`

### Key Improvements

1. `## Observability` emitted — deepen-plan Phase 4.7 fires on any non-docs Files-to-Edit path (plan 2.9's narrower code-class trigger had let it skip); the section declares the ratchet job's own verdict line as the liveness signal with a sandbox-runnable `discoverability_test` (`grep` verb, <15 s, literal `expected_output: 7`, verified against a 0-row baseline).
2. Mention-not-edge evidence hardened: `ensure-doppler.sh` appears in `scripts/betterstack-query.sh` only inside the credentials-missing heredoc (`:109-110`, grep-verified — never executed); suite `scripts/betterstack-emitter-read` resolves to `lint-betterstack-emitter-read.test.sh` driving the lint as its guard under test (`scripts/test-all.sh:5946`).
3. Every prescribed verification command executed once before finalizing: `ratchet` reproduces `exit=1 reason=new-pair live=1515 baseline=1510` in this worktree; `audit --all-refs` confirms the complete 7-line boundary set; anchors re-derived sha256-locally match the CI job byte-for-byte.

### New Considerations Discovered

- `scripts/betterstack-emitter-read-live` is a separate always-on suite (`scripts/test-all.sh:5945`) that runs the real lint — the pair under fix belongs only to the fixture-driving test battery, so no edge should be declared for it.
- `decision-challenges.md` is machine-gated (`technical-ruling-gate.sh`): the technical row was rewritten to the `Ruled by CTO agent, <date>:` shape with the inline-execution disclosure, and the gate passes (2 rows examined).
- markdownlint `knowledge-base/project/` exclusion means the literal TABs in the plan's TSV fence are safe (MD010 would fire elsewhere).

## Overview

The advisory `affected-index-ratchet` job is red on `main` with `reason=new-pair live=1515 baseline=1510` (#11694). The five new pairs all resolve to mention-class boundary lines — usage-message text inside `scripts/betterstack-query.sh`'s credentials-missing heredoc and an allowlist-map key in `scripts/lint-betterstack-emitter-read.sh` — so the remedy is anchor-keyed accept rows in `scripts/ci-pr-affected-audit.accept.tsv`, not declared edges. `python3 -I scripts/ci-pr-affected-replay.py audit --all-refs` enumerates seven boundary lines across the five pairs; a local `ratchet` run must exit 0 after the rows land.

## Research Insights

**Coverage disclosure:** this plan ran on the Devin CLI harness where plugin subagents do not exist — every fan-out the skill prescribes (repo research, learnings research, functional-discovery, SpecFlow, domain leaders, plan-review panel, advisor consult) was executed sequentially inline by this process. `Reviewed-Coverage: sequential-fallback`; no independent review ran.

**Premise Validation (Phase 0.6).** Issue #11694 verified OPEN, no closing PRs. Cited trackers #10865 (soak) and #10859 (make-context-required, held) both OPEN — consistent with the "non-blocking but wanted now" framing. Every cited path exists in this worktree (all 8 files). The 5 pairs and their ref lines were reproduced in this worktree by `python3 -I scripts/ci-pr-affected-replay.py audit --all-refs` (exit 1, gap lines present), and all four distinct anchors re-derived locally match the CI job 124617199643 output byte-for-byte. Collision precheck: PR #11734 names #11694 but is this pipeline's own WIP draft on this branch — not a foreign collision (other worktrees' running `test-all.sh` processes noted, none on this issue). ADR corpus grep on the mechanism (`affected`, `ratchet`, `accept`) surfaces ADR-276 and the activation runbook `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` as the authority; the proposed remedy (accept rows) is the mechanism that runbook prescribes — nothing sits in a rejected-alternatives table.

**Property List (Phase 0.6b).** (a) `affected-index-ratchet` goes green on `main` again — the live `(suite, path)` gap set equals the committed baseline after exemptions. (b) No false edges are declared: suites that merely name a file must not gain `AFFECTED_<LABEL>_PATHS` coverage. (c) Exemptions are anchor-keyed so they go `stale` automatically when the citing line is edited (an existing property of the row format — no new machinery). **Cut List:** none — the ask proposes no new machinery; the accept file is the existing drain mechanism.

**The seven boundary lines (complete set, from `audit --all-refs` run 2026-10-31 in this worktree).**

| # | suite | path | ref line | anchor/ordinal |
|---|-------|------|----------|----------------|
| 1 | `scripts/betterstack-emitter-read` | `scripts/followthroughs/inngest-hostmetrics-trim-11602.sh` | `scripts/lint-betterstack-emitter-read.sh:140` | `6b94378af8e8/1` |
| 2 | `scripts/followthroughs/inngest-bs-token-restage-7596` | `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` | `scripts/betterstack-query.sh:104` | `a85eed92c105/1` |
| 3 | `scripts/followthroughs/inngest-bs-token-restage-7596` | `scripts/ensure-doppler.sh` | `scripts/betterstack-query.sh:109` | `1027621c5bba/1` |
| 4 | `scripts/followthroughs/inngest-bs-token-restage-7596` | `scripts/ensure-doppler.sh` | `scripts/betterstack-query.sh:110` | `7c59a1e49464/1` |
| 5 | `scripts/followthroughs/inngest-hostmetrics-trim-11602` | `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` | `scripts/betterstack-query.sh:104` | `a85eed92c105/1` |
| 6 | `scripts/followthroughs/inngest-hostmetrics-trim-11602` | `scripts/ensure-doppler.sh` | `scripts/betterstack-query.sh:109` | `1027621c5bba/1` |
| 7 | `scripts/followthroughs/inngest-hostmetrics-trim-11602` | `scripts/ensure-doppler.sh` | `scripts/betterstack-query.sh:110` | `7c59a1e49464/1` |

**Why mention, not edge — per-pair evidence.** Row 1: the boundary line is an ALLOW-table map entry in `lint-betterstack-emitter-read.sh` (`["scripts/followthroughs/inngest-hostmetrics-trim-11602.sh"]="field-scoped SQL ..."`); the suite reads the lint script as its SUT over git-init fixture trees and never opens or executes the named probe — identical disposition to the existing `inngest-luks-keeper-dark-11265.sh` row at `scripts/ci-pr-affected-audit.accept.tsv` (suite `scripts/betterstack-emitter-read`). Rows 2–7: each followthrough script sets `QUERY="$SCRIPT_DIR/../betterstack-query.sh"` (`inngest-bs-token-restage-7596.sh:137`, `inngest-hostmetrics-trim-11602.sh:88`); the audit's reach walks into `betterstack-query.sh` and finds the runbook and `ensure-doppler.sh` named only inside its credentials-missing usage-message heredoc (`:104`, `:109`, `:110`). Neither suite file names `ensure-doppler.sh` or `betterstack-log-query.md` itself (grep-verified), and `betterstack-query.sh` never executes `ensure-doppler.sh` — the lines are advisory message text. Same disposition as the existing `inngest-luks-keeper-dark-11265` rows (ensure-doppler.sh, anchors `1027621c5bba`/`7c59a1e49464`) and `tests/scripts/git-data-rung2-evidence-capture` rows (same three refs, reason kind `message:`).

**Relevant learnings.** `knowledge-base/project/learnings/test-failures/2026-10-30-audit-accept-rows-need-every-boundary-line-and-regen-pricing-can-break-committed-invariants.md` — the ratchet report's per-pair ref list is a subset; the complete boundary set comes from `audit --all-refs`, and a pair exempts only when EVERY boundary line has a row (`judge_rules`). Here the local `--all-refs` run confirms the CI report happened to print the complete sets, but the work-phase verification must still be `ratchet` exit 0, not "rows added". Same learning: the accept-row key is the first four columns — one reason per key. `knowledge-base/project/learnings/2026-10-26-a-ratchet-green-on-the-branch-tip-was-red-on-the-merged-tree.md` — branch-tip green does not guarantee merged-tree green; this branch carries no suite/edge changes so the risk is minimal, but the local ratchet must run against this worktree's tree, which is what the job does.

**Repo conventions.** Accept file is sorted by `(suite, path, anchor)` — verified `sorted: True` over 232 rows; new rows must be inserted in sorted position (rows 1 before the `inngest-luks-keeper` row of `scripts/betterstack-emitter-read`; rows 2–7 before the `scripts/followthroughs/inngest-luks-keeper-dark-11265` rows — `bs` < `hostmetrics` < `luks`, and `knowledge-base/…` < `scripts/…`, `1027…` < `7c59…` within a suite). Header comment: `#` lines and blank lines skipped. The accept file is a declared oracle input — the job will print `oracle-inputs-changed: scripts/ci-pr-affected-audit.accept.tsv`; that is an announcement, not a verdict. Baseline is shrink-only: never add a baseline line.

**Related issues/PRs:** #11694 (target), #10865 (soak tracker), #10859 (make the context required later), run 41228374961 / job 124617199643 (anchor source). Runbook `ci-pr-affected-activation.md` §ratchet table is the remedy authority.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — the worst case is the advisory `affected-index-ratchet` job staying red (or going red again), which is a CI signal on the engineering pipeline, not a product surface.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing — the diff appends seven exemption rows to a CI oracle file; no user data, workflow, or money path is reachable from it.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the only file touched is a CI audit-exemption table; a wrong row degrades one advisory CI check's accuracy (a false accept is a false negative on future pairs for that suite), which is an internal quality signal with no user-visible artifact.

*Scope-out override (only when `threshold: none` AND the diff touches a sensitive path flagged by preflight):* `threshold: none, reason: the only edited path is a repo-root CI data file (scripts/ci-pr-affected-audit.accept.tsv), outside every sensitive-path class`

## Observability

```yaml
liveness_signal:
  what:            # the `SOLEUR_PR_AFFECTED_RATCHET exit=<n> reason=<r>` verdict line printed by the affected-index-ratchet job — the check that consumes this file IS the signal
  cadence:         # once per pull_request / merge_group run of .github/workflows/ci.yml
  alert_target:    # GitHub Actions `::error title=affected-index-ratchet::exit=$rc reason=$reason` job annotation + red job conclusion (advisory today; #10859 makes it required)
  configured_in:   # .github/workflows/ci.yml job `affected-index-ratchet` (runs `python3 -I scripts/ci-pr-affected-replay.py ratchet`)

error_reporting:
  destination:     # the job's stdout block + $GITHUB_STEP_SUMMARY `### affected-index-ratchet` section (new-pair / stale-accept rows with cause + remedy lines)
  fail_loud:       # `##[error]exit=1 reason=new-pair` (or reason=stale-accept) in the job log; `::warning oracle-inputs-changed` annotates this very file's edit

failure_modes:
  - mode:          # new-pair — a suite names a tracked path with no declared edge and no accept row
    detection:     # ratchet prints `new-pair<TAB>suite<TAB>path<TAB>file:line` + `ref` lines and exits 1
    alert_route:   # job annotation; soak tracker #10865
  - mode:          # stale-accept — an accept row whose (anchor, ordinal) is no longer live (the citing line was edited); exactly what these 7 rows become when betterstack-query.sh's message or the lint allowlist line changes — the intended signal
    detection:     # ratchet prints `stale<TAB>suite<TAB>path<TAB>anchor/ordinal<TAB>anchor-not-live` and exits 1
    alert_route:   # job annotation; soak tracker #10865
  - mode:          # malformed accept file — wrong column count, non-12-hex anchor, duplicate row key
    detection:     # file-load ValueError → census-degraded exit 2
    alert_route:   # job annotation

logs:
  where:           # GitHub Actions job log + step summary for run 41228374961-class runs
  retention:       # GitHub Actions default (~90 days)

discoverability_test:
  command:         grep -c -e inngest-bs-token-restage-7596 -e inngest-hostmetrics-trim-11602 scripts/ci-pr-affected-audit.accept.tsv
  expected_output: 7
```

## Implementation Phases

### Phase 1 — Accept-row append (the whole fix)

1. In `scripts/ci-pr-affected-audit.accept.tsv`, insert the following seven rows **in sorted position** (the file is sorted by `suite`, `path`, `anchor` — verified over the 232 existing rows; keep it so):

   ```text
   scripts/betterstack-emitter-read	scripts/followthroughs/inngest-hostmetrics-trim-11602.sh	6b94378af8e8	1	false-positive: the suite reads scripts/lint-betterstack-emitter-read.sh as its guard under test; the cited line is an ALLOW-table map entry (a path key plus a reason string) that names the probe as data — the suite drives the guard over git-init fixture trees and never reads or executes scripts/followthroughs/inngest-hostmetrics-trim-11602.sh
   scripts/followthroughs/inngest-bs-token-restage-7596	knowledge-base/engineering/operations/runbooks/betterstack-log-query.md	a85eed92c105	1	false-positive: message: scripts/betterstack-query.sh:104: the credentials-missing message of betterstack-query.sh (the suite's $QUERY reader); the suite never reads the runbook through it
   scripts/followthroughs/inngest-bs-token-restage-7596	scripts/ensure-doppler.sh	1027621c5bba	1	false-positive: message: scripts/betterstack-query.sh:109: usage text inside the credentials-missing message; the suite never reads or runs the installer through it
   scripts/followthroughs/inngest-bs-token-restage-7596	scripts/ensure-doppler.sh	7c59a1e49464	1	false-positive: message: scripts/betterstack-query.sh:110: usage text inside the credentials-missing message; the suite never reads or runs the installer through it
   scripts/followthroughs/inngest-hostmetrics-trim-11602	knowledge-base/engineering/operations/runbooks/betterstack-log-query.md	a85eed92c105	1	false-positive: message: scripts/betterstack-query.sh:104: the credentials-missing message of betterstack-query.sh (the suite's $QUERY reader); the suite never reads the runbook through it
   scripts/followthroughs/inngest-hostmetrics-trim-11602	scripts/ensure-doppler.sh	1027621c5bba	1	false-positive: message: scripts/betterstack-query.sh:109: usage text inside the credentials-missing message; the suite never reads or runs the installer through it
   scripts/followthroughs/inngest-hostmetrics-trim-11602	scripts/ensure-doppler.sh	7c59a1e49464	1	false-positive: message: scripts/betterstack-query.sh:110: usage text inside the credentials-missing message; the suite never reads or runs the installer through it
   ```

   Field separator is a real TAB (five columns). Reason texts model on the existing `scripts/followthroughs/inngest-luks-keeper-dark-11265` rows (same `ensure-doppler.sh` anchors) and the `tests/scripts/git-data-rung2-evidence-capture` rows (same three refs, `message:` kind per the runbook's closed kind list).

   Insertion points:
   - Row 1 sorts immediately before the existing `scripts/betterstack-emitter-read` row for `scripts/followthroughs/inngest-luks-keeper-dark-11265.sh` (`hostmetrics` < `luks`).
   - Rows 2–7 sort immediately before the existing `scripts/followthroughs/inngest-luks-keeper-dark-11265` rows (`bs` < `hostmetrics` < `luks`; within a suite `knowledge-base/…` < `scripts/…`, and `1027621c5bba` < `7c59a1e49464`).

2. Re-verify the file stays sorted: the suite/path/anchor triple key sequence must remain non-decreasing.

3. Optional evidence step (cheap, strengthens the mention-not-edge claim): run `scripts/audit-suite-reads.sh record --mode check` for the two followthrough suites and confirm `ensure-doppler.sh` and `betterstack-log-query.md` are not in the opened set; grep both suite files for the basenames `ensure-doppler.sh` / `betterstack-log-query.md` and their parent directories as separate string literals (a computed-path construction reads the file without producing a boundary line — none found at plan time).

4. Run `python3 -I scripts/ci-pr-affected-replay.py ratchet` from the worktree root. Success = `SOLEUR_PR_AFFECTED_RATCHET exit=0`. If it instead reports `stale-accept` or residual `new-pair`, enumerate the live boundary set again with `audit --all-refs` and reconcile — never add a baseline line.

## Files to Edit

- `scripts/ci-pr-affected-audit.accept.tsv` — insert the seven rows above, in sorted position.

## Files to Create

- None.

## Gate Dispositions (evaluated at plan time)

- **Observability (Phase 2.9):** initially skipped under plan 2.9's code-class trigger (repo-root `scripts/` is outside `apps/*` and `plugins/*/scripts/`); deepen-plan 4.7's stricter trigger (any non-docs Files-to-Edit path) required the section — emitted above. The ratchet job itself is the observability surface for this check; `oracle-inputs-changed: scripts/ci-pr-affected-audit.accept.tsv` prints as an announcement on the next run, not a verdict.
- **GDPR (2.7), IaC (2.8), Soak enrollment (2.9.1), Task Design (2.9.3), ADR/C4 (2.10), Encryption Posture (2.11), Guard Contract (2.12):** all skipped — a data-row append to an existing exemption table creates no regulated surface, infrastructure, soak gate, autonomous task, architectural decision, store/connection, or new guard. The ratchet is an existing guard; this change feeds its input, not its machinery.
- **Skill description budget (1.8):** no SKILL.md `description:` edit is candidate — skipped.
- **Community discovery (1.5) / functional overlap (1.5b):** no uncovered stack (shell/Python CI data fix); no community tool can cover a repo-local exemption table — assessed inline under sequential-fallback, skipped.
- **Advisor consult (4.5):** skipped — trivially mechanical (single-file, no architecture choice).
- **SpecFlow (3):** assessed inline — the change is a data append with a mechanical verifier (`ratchet` exit 0); no conditional logic to drop edge cases on. Skipped.
- **Network-outage checklist (1.4):** no trigger patterns in the feature description — skipped.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (2026-10-31) has no body mentioning `scripts/ci-pr-affected-audit.accept.tsv` or `ci-pr-affected`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "declare the edge in AFFECTED_<LABEL>_PATHS only if the suite really reads or executes the file, otherwise add an anchor-keyed accept row to scripts/ci-pr-affected-audit.accept.tsv" | Phase 1 rows 1–7 (accept rows chosen; per-pair evidence in Research Insights) | mapped |
| 2 | "Model the accept rows on the existing `inngest-luks-keeper-dark-11265` rows already in that file" | Phase 1 step 1 reason strings | mapped |
| 3 | "Anchors for the accept rows are in GitHub Actions run 41228374961 job 124617199643" | Research Insights boundary-line table; anchors fetched and re-derived locally | mapped |
| 4 | "Closes #11694" | frontmatter `closes: 11694` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/ci-pr-affected-audit.accept.tsv` edit | "add an anchor-keyed accept row to scripts/ci-pr-affected-audit.accept.tsv" | asked |
| Local `ratchet` re-run verification | "reproduced with `python3 -I scripts/ci-pr-affected-replay.py ratchet`" | inferred — justification: the job's own verdict command is the only oracle that proves the exemption set covers every boundary line (2026-10-30 learning: report ref lists are subsets) |
| Optional read-recorder evidence step | — | inferred — justification: strengthens the mention-not-edge claim the runbook says no automated control checks (`scripts/audit-suite-reads.sh record --mode check` is the runbook's own evidence tool) |

### Split Assessment

- Subsystems touched: 1 — `scripts/`
- Planned files: 1 | Estimated changed lines: 7
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] `scripts/ci-pr-affected-audit.accept.tsv` gains exactly seven new rows covering all five new pairs and all seven boundary lines listed in the Research Insights table, each in `suite<TAB>path<TAB>anchor<TAB>ordinal<TAB>false-positive: <reason>` form with real TAB separators
- [ ] The file's `suite`-`path`-`anchor` key order remains sorted after insertion
- [ ] `python3 -I scripts/ci-pr-affected-replay.py ratchet` exits 0 in the worktree and prints `SOLEUR_PR_AFFECTED_RATCHET exit=0` (no `new-pair`, no `stale-accept`)
- [ ] No baseline line is added to `scripts/ci-pr-affected-audit.baseline.tsv`, and no `AFFECTED_<LABEL>_PATHS` entry is added in `scripts/lib/test-affected-paths.sh` (all five pairs are mentions, not reads)
- [ ] No accept row duplicates an existing `suite/path/anchor/ordinal` key (`duplicate accept row` would fail the file load)

## Test Scenarios

- Given the seven rows appended, when `python3 -I scripts/ci-pr-affected-replay.py ratchet` runs in the worktree, then it exits 0 and reports `accepted` covering the five pairs — `integration`
- Given a deliberately malformed copy of the file (one row's anchor edited), when `ratchet` runs against it locally, then the doctored row reports `stale`/`anchor-not-live` and exit is non-zero — `integration` (verification-only dry run; not committed)
- Given the sorted-order convention, when the insertion lands, then `python3 -c` over the file's non-comment lines confirms the (suite, path, anchor) triple sequence is non-decreasing — `unit`

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI/tooling data change. Mechanical UI-surface override did not fire (no UI-surface file in Files to Edit/Create).

## Context

- The job is advisory (`continue-on-error: true` in `.github/workflows/ci.yml`) and runs only on `pull_request`/`merge_group`; "red on main" means the latest `merge_group` conclusion is red. #10859 will make the context required later — fixing now keeps the soak in #10865 honest.
- The accept file is a declared oracle input; the next run will print `oracle-inputs-changed: scripts/ci-pr-affected-audit.accept.tsv` as a `::warning` — expected, per the runbook.
- Anchor definition (from `scripts/ci-pr-affected-replay.py` `--help`): first 12 hex of sha256 over `" ".join(line.split())` of the boundary line as written; ordinal numbers identical anchors over the canonical read order. All four distinct anchors were re-derived locally and match the CI job's ref lines exactly.
- The `cause:` line in the job output ("your change touched neither … main is already red for this pair") applies — main moved under the pairs via the inngest follow-through scripts landing; no suite change is needed.

## References

- Issue: #11694 (this fix), #10865 (soak tracker), #10859 (required-context flip)
- CI evidence: run 41228374961, job 124617199643 (`affected-index-ratchet`, 2026-10-31T18:30Z)
- Authority: `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` (ratchet remedy table, accept-row rubric); ADR-276
- Precedent rows: `scripts/ci-pr-affected-audit.accept.tsv` `inngest-luks-keeper-dark-11265` and `tests/scripts/git-data-rung2-evidence-capture` entries
- Learning: `knowledge-base/project/learnings/test-failures/2026-10-30-audit-accept-rows-need-every-boundary-line-and-regen-pricing-can-break-committed-invariants.md`
