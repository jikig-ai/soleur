---
title: "chore: retire the followthrough probes whose tracker issues are closed (G1 PR-4a)"
date: 2026-10-23
slug: retire-closed-followthrough-probes-g1-pr4a
branch: feat-one-shot-g1-pr4a-retire-closed-probes
issue: 9294
type: chore
lane: cross-domain
brand_survival_threshold: none
---

# chore: retire the followthrough probes whose tracker issues are closed (G1 PR-4a)

## Enhancement Summary

**Deepened on:** 2026-10-23
**Research agents used:** repo-research-analyst, learnings-researcher, functional-discovery (no overlap), CTO (rulings F1-F7), plan-review panel (DHH, Kieran, code-simplicity), deepen panel (architecture-strategist, security-sentinel, git-history-analyzer)

### Key improvements

1. Scope corrected from "five" probes to four probes plus one test (the fifth was already deleted by #10546); the open-tracker probes (#6178, #10548) stay.
2. Ratchet footprint widened from one TSV to the full set of guards that name the probes, each with its guard command and an ordering rule (`PJ_TRIPLES` re-pin only after the bearer-sweep edit).
3. Floors (`EXPECTED_TESTS`, `S4_GUARD_FLOOR`) are set from a row-label multiset diff and a `_bearer_ok` identity check, not from arithmetic.
4. Coverage thinning from deleting the HMAC dynamic rows is bounded: one parity E4 row and the 10548 facet audit are added, the rest is a tracked deferral.

### New considerations discovered

- A second closed tracker, #7296, carries a directive for the activation probe; inert like #7220's.
- The affected-audit ratchet job is advisory (`continue-on-error`), so its stale-row red is non-blocking but the row is still deleted.
- `cat-deploy-state.sh` is hash-bound into the deploy-pipeline trigger, so its stale comments cannot be fixed in this PR.
- `canary-status.yml`'s in-step comment is inside an extracted, executed step body: the rewrite must contain no dollar sign, backtick or `${{`.

Spec lacks a valid `lane:` (no spec.md exists for this one-shot branch), defaulted to `cross-domain` (fail-closed). The work is
single-domain engineering; the Domain Review below records the actual assessment.

## Overview

Part of the G1 chain (epic #9294, ADR-241 D10; task 5.2 of the archived `feat-g1-webhook-trio-tier-b-9294` tasks.md, finding 7 of
the archived plan). Four followthrough probes read the deploy-channel trio (`WEBHOOK_DEPLOY_SECRET`, `CF_ACCESS_CLIENT_ID`,
`CF_ACCESS_CLIENT_SECRET`) but belong to trackers that are already closed, so no sweep will ever run them. This PR deletes them,
their one test suite, and every ratchet row, registry entry and guard floor that still names them, so that the trio census
(`tests/scripts/test-trio-baseline-census.sh`) shrinks by exactly the 12 rows those probes own. The probes of the two OPEN trackers
(#6178, #10548) are not touched, and neither is anything on the W0 hard boundary (see below).

PR #10937 is a draft. It must not be armed for the merge queue until the operator confirms (recorded in `decision-challenges.md`).

## Research Reconciliation: spec vs. codebase

| Claim in the brief / archived plan | Reality (verified 2026-10-23) | Plan response |
|---|---|---|
| "Five followthrough probes belong to the closed trackers" | Four probe scripts + one test file remain. The fifth (the #5863 soak, `tenant-outer-wrap-soak-5863.sh` + `.test.sh`) was already deleted by #10546 (`cfec67d5e2`). | Delete exactly four scripts + `infra-config-activation-7220.test.sh`. CTO F1. |
| "The probes are ... names ending -5875, -7220 (two), -2640" | `canary-promotion-5875.sh`, `infra-config-activation-7220.sh`, `infra-config-fatal-channel-7220.sh`, `workspace-isolation-verdict-2640.sh`. | As listed in Files to Delete. |
| trio-baseline rows "~183-203" are the probe list | Rows 183-191 and 201-203 are the 12 probe rows. Rows 192-200 belong to `inngest-soak-6178.sh` (tier-a) and `sdk-bash-smoke-verdict-10548.sh` (sink) and STAY. | Delete the 12, keep the 9 between. Anchor by path, not by line. |
| `sdk-bash-smoke-verdict-10548.sh` sits among the "sink" rows tagged PR-4, so it is a probe to retire | Tracker #10548 is OPEN ("promote the deploy-time SDK Bash smoke to blocking after the soak") and its directive binds the trio. | Out of scope. Stays with PR-4 / task 5.3. |
| "Drop the trio reads from the sweeper and `github-app-key-status.sh` only where the deleted probes were the sole consumer" | The deleted probes were NOT the sole consumer in either: #6178 and #10548 directives still declare `secrets=WEBHOOK_DEPLOY_SECRET,CF_ACCESS_CLIENT_ID,CF_ACCESS_CLIENT_SECRET`, so the sweeper `env:` block keeps all three; `github-app-key-status.sh` is an independent #8609 discoverability probe that calls `/hooks/deploy-status` itself and has no relation to the deleted probes. | No trio read is removed from either file. The 6 baseline rows for them stay (PR-4). Only the sweeper's explanatory comment is reworded. CTO F1/F4. |
| "Plus their tracker directives" | Two closed bodies carry a directive: #7220 (`infra-config-fatal-channel-7220.sh`, closed 2026-08-05) and #7296 (`infra-config-activation-7220.sh`, closed 2026-08-06, label `follow-through`, found by the deepen architecture review); #5875, #2640, #5863 carry none. The sweeper lists open trackers, plus a closed-set reopen path limited to `follow-through` label + `COMPLETED` + closed within 14 days; both are far outside it and the others lack the label; no open `follow-through` issue's body names any of the four deleted scripts. A missing script only logs "script missing ... leaving issue open". | The directives are inert: no `gh issue edit` of #7220 or #7296. CTO F2. |
| "Update ... any census/ratchet rows so `test-trio-baseline-census.sh` stays green" | The ratchet footprint is much wider than the trio TSV: `test-all.sh`, shard/duration manifests (+ `.n` copies), `ci-pr-affected-audit.baseline.tsv`, `fixture-relative-assert.baseline.txt`, `grep-q-pipe-guard.test.sh` (exempt row + `PJ_TRIPLES` pin), and `test-argv-bearer-sweep.sh` (manifest, HM5 list, census, two floors, dead code). | Phase 2/3 below enumerate each, with its guard command. |

## Research Insights

**Premise Validation (Phase 0.6).** Checked with `gh issue view`: #5875 CLOSED 2026-07-02, #7220 CLOSED 2026-08-05 (label
`follow-through`), #2640 CLOSED 2026-10-09, #5863 CLOSED 2026-10-09, #6178 OPEN, #10548 OPEN, #9294 OPEN, #10937 OPEN (draft PR).
The #5863 probe file is absent on `HEAD` and `git log --diff-filter=D` shows it deleted in `cfec67d5e2` (#10546). ADR corpus: the
mechanism (delete retired probes, shrink the baseline) is ADR-241 D10's own plan; no ADR rejects it. Stale premises: the "five"
count, and the implied retirement of 10548's probe.

**Property List (Phase 0.6b).**
P1 After merge no tracked file under `scripts/followthroughs/` is a probe of a closed tracker whose only purpose was the trio read.
P2 `tests/scripts/trio-baseline.tsv` has no row for a file that no longer exists, and keeps every row of a file that still reads the trio.
P3 Every guard that counts, lists or floors the deleted files stays green, with each floor at the new realized count (no slack).
P4 Nothing on the W0 hard boundary changes, and no production, Terraform, workflow-dispatch or GitHub-issue write happens.
P5 No dangling pointer to a deleted script remains in a file this PR is permitted to touch.

**Cut List.**

- New absence test for the deleted names -> P1 -> already covered by `derive_population` (UNCLASSIFIED/STALE) in `test-argv-bearer-sweep.sh` and the census rule "a row whose consumer no longer names the family is RED" (grepped both).
- ADR-241 amendment line -> P2 -> deletions need no `@allow`/`Reclass`/`Re-date` line (census header; repo-research confirmed).
- `gh issue edit` of the #7220 body -> P1 -> inert directive (sweeper source read), and an out-of-diff write.
- Editing `cat-deploy-state.sh` comments -> P5 -> the file is hash-bound into the deploy-pipeline trigger (`server.tf` `host_script_files` + `filesha256`); even a comment edit fires a production deploy. Deferred to its next real edit.
- Retiring `inngest-soak-6178.sh` / `sdk-bash-smoke-verdict-10548.sh` -> out of the ask (tasks 5.3 / PR-4; open trackers).

**Learnings applied** (`knowledge-base/project/learnings/`): the followthrough convention's `RETIREMENT:` rule (re-census the unnumbered stem, disposition every hit) -> the Footprint table below; `2026-10-18-ratchet-guards-must-pin-the-scan-population-and-their-own-registrations` -> every registration edit is paired with the guard that sees it; `2026-10-05-registering-a-suite-is-itself-a-runner-edit` -> removing a `run_suite` line counts as a `G1-removal` runner edit, so `--affected` degrades to the full battery (expect a long CI run); `2026-07-17-derivation-sweep-must-be-repo-wide-and-rerun-at-merge` -> re-run the repo-wide grep after the rebase; `2026-06-05-followthrough-pr-body-prose-closes-keyword-autocloses-tracker` -> the PR body must contain no closing keyword (`Ref #9294`, never `Closes`); `2026-08-04-a-count-framed-ratchet-cannot-see-a-rename` -> verify floors by identity, not by count alone; `2026-09-23-a-pr-must-not-control-the-guard-that-judges-it` -> any floor lowered here carries a comment naming this PR and the removed probes (the #10546 style).

**Template.** PR #10546 (`cfec67d5e2`) deleted the #5863 probe pair and edited, row for row: `test-all.sh`, both shard/duration TSVs and their `.n` copies, the bearer-sweep manifest, `S4_GUARD_FLOOR` 77 -> 76, `fixture-relative-assert.baseline.txt`, `grep-q-pipe-guard.test.sh` (`PJ_TRIPLES`). It did not touch the trio baseline or the affected-audit baseline because that probe had no rows there; this PR does.

**Measured at plan time.**

- `bash tests/scripts/test-trio-baseline-census.sh` -> `585 passed, 0 failed` (pre-edit, green).
- `bash tests/scripts/test-argv-bearer-sweep.sh` -> `880 passed, 0 failed` in 4m46s; `EXPECTED_TESTS=880`, i.e. ZERO slack, so the floor MUST be lowered with the deleted rows; `S4_GUARD_FLOOR=76` counts `_bearer_ok` definitions and all four probes define exactly one (`grep -cE '^\s*_bearer_ok\(\) \{'` returned 1 for each), so the expected new value is 72 (verify by running, do not trust arithmetic).
- Repo-research recomputation of the `grep-q-pipe-guard` pin: `PJ_TRIPLES` 294 -> 287 (172 -> 171 pairs; 1 triple lost from the deleted `.test.sh`, 6 from `test-argv-bearer-sweep.sh`). Recompute with the documented command before committing.
- `scripts/ci-pr-affected-replay.py ratchet` and the affected-index job did not finish locally within 300 s; CI is the gate for that row.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "retire the five followthrough probes whose tracker issues are already closed, plus their tracker directives" [brief] | Files to Delete (four probes + one test; the fifth was deleted by #10546); directive handling per CTO F2 (inert, no issue edit) | mapped |
| 2 | "the only still-open tracker, #6178, keeps its probe scripts/followthroughs/inngest-soak-6178.sh: do NOT touch it" [brief] | HARD BOUNDARY section; AC1; the 6178 and 10548 rows stay in the trio baseline | mapped |
| 3 | "drop the trio reads from the sweeper (scheduled-followthrough-sweeper.yml) and github-app-key-status.sh only where the deleted probes were the sole consumer" [brief] | Research Reconciliation row (they were not the sole consumer: no read dropped); AC6 | mapped |
| 4 | "update tests/scripts/trio-baseline.tsv and any census/ratchet rows so tests/scripts/test-trio-baseline-census.sh stays green (shrink-only baseline)" [brief] | Files to Edit table; Phases 2-3; AC3-AC5 | mapped |
| 5 | "the diff must NOT touch ci-deploy.sh, the webhook secret, .github/workflows/git-data-cutover.yml, track.sh, the Tier-B loader or the bridge" [brief] | HARD BOUNDARY compliance section; AC1 | mapped |
| 6 | "No production write, terraform apply or workflow dispatch." [brief] | Does merging this alone mutate production?; no `gh issue edit` (CTO F2) | mapped |
| 7 | "Merge queue currently holds other PRs; this PR must not be armed" [brief] | Phase 5; the hold is recorded in decision-challenges.md | mapped |
| 8 | "Do not touch .mcp.json, git-data-gc.sh, .gc-cursor, .worktrees/feat-one-shot-10138-git-data-wipe-body, .worktrees/feat-git-data-cutover-resume-8211, or the worktree .worktrees/feat-feat-g1-pr2-terraform-fed-group. Do not edit AGENTS.rules.md or any legal document." [brief] | HARD BOUNDARY compliance section; AC1 | mapped |
| 9 | "Technical forks: spawn soleur:engineering:cto and record 'Ruled by CTO agent'" [brief] | decision-challenges.md rows F1-F6 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Delete the four probes and `infra-config-activation-7220.test.sh` | "retire the five followthrough probes whose tracker issues are already closed" (asks 1) | asked |
| Delete the 12 trio-baseline rows | "update tests/scripts/trio-baseline.tsv" (asks 4) | asked |
| `test-all.sh`, shard/duration manifests, affected-audit baseline, fixture-relative baseline, `grep-q-pipe-guard` row and pin | "any census/ratchet rows so tests/scripts/test-trio-baseline-census.sh stays green" (asks 4) | asked |
| `test-argv-bearer-sweep.sh` manifest, `HM5_FILES`, census pathspec | "any census/ratchet rows" (asks 4) | asked |
| `test-argv-bearer-sweep.sh` dead-code deletion (`probe_rows_hmac`, `dynamic)` arm, `hmx_sandbox`, three fixtures) and floor lowering | - | inferred - justification: the deleted probes were the only `dynamic` manifest rows, so the function exercises nothing, and the suite's floors sit at zero slack (880 passed against `EXPECTED_TESTS=880`), so leaving either unedited reds the suite (CTO F3) |
| Comment-pointer rewrites (sweeper env comment, `canary-status.yml`, two runbooks, one `.ts` comment) | - | inferred - justification: a pointer to a deleted script in a file this PR may legally touch is the dangling-reference class the followthrough convention's `RETIREMENT:` rule exists to prevent (CTO F4); reviewers dissent on the `.github` and `.ts` edits, recorded in decision-challenges.md |
| Phase 1 RED-first and the Phase 3 row-label diff | - | inferred - justification: the only steps proving the Footprint table is complete and that a floor is not copied from a run that also lost an unrelated row |
| "Does merging this alone mutate production?" and Rollback sections | "No production write, terraform apply or workflow dispatch." (asks 6) | asked |
| No edit of closed tracker bodies | "plus their tracker directives" (asks 1) | asked |
| HARD BOUNDARY compliance and AC1 | "the diff must NOT touch ci-deploy.sh" (asks 5) | asked |

### Split Assessment

- Subsystems touched: 6 - scripts, tests, plugins/soleur, .claude, .github, knowledge-base
- Planned files: 23 | Estimated changed lines: 1200 (about 1000 are the deleted probe files and about 120 the deleted bearer-sweep functions)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - two thresholds are exceeded but the diff is deletion-dominated and atomic: the floors and pins must move in the same commit as the deletions (a split leaves a guard red between the PRs), and the brief names this as one PR (PR-4a)

## HARD BOUNDARY compliance (CTO ruling 2026-10-23, W0 plaintext-wipe not concluded)

None of the deletions or edits requires touching `ci-deploy.sh`, the webhook secret, `.github/workflows/git-data-cutover.yml`,
`track.sh`, the Tier-B loader or the bridge. Verified by grep: none of them names a deleted probe by path (`ci-deploy.sh` has one comment saying "the canary-promotion follow-through", a phrase, left as-is). The diff also
leaves untouched `.mcp.json`, `git-data-gc.sh`, `.gc-cursor`, `AGENTS.rules.md`, every legal document, the worktrees
`feat-one-shot-10138-git-data-wipe-body`, `feat-git-data-cutover-resume-8211`, `feat-feat-g1-pr2-terraform-fed-group`, and
`apps/web-platform/infra/cat-deploy-state.sh` (production-deploy trigger; see Cut List). If implementation finds a deletion that
would require any of these, STOP and report instead of editing.

## Footprint (re-censused `git grep` over live code, excluding `knowledge-base/**/archive/**`)

### Files to Delete

| Path | Why |
|---|---|
| `scripts/followthroughs/canary-promotion-5875.sh` | tracker #5875 closed |
| `scripts/followthroughs/infra-config-activation-7220.sh` | tracker #7220 closed |
| `scripts/followthroughs/infra-config-activation-7220.test.sh` | its only suite |
| `scripts/followthroughs/infra-config-fatal-channel-7220.sh` | tracker #7220 closed |
| `scripts/followthroughs/workspace-isolation-verdict-2640.sh` | tracker #2640 closed |

### Files to Edit (guards that go RED on deletion; anchor by content, never by line number)

| File | Edit | Guard command |
|---|---|---|
| `tests/scripts/trio-baseline.tsv` | delete the 12 rows whose path column is one of the four deleted probes (all `sink`, tag `#9294:PR-4`) | `bash tests/scripts/test-trio-baseline-census.sh` |
| `scripts/test-all.sh` | delete the `#7220` comment block and `run_suite "scripts/infra-config-activation-7220" ...`; reword the comment of the NEXT suite (`#7341`), which says it is registered next to "the probe directly above" | `bash scripts/lint-orphan-test-suites.sh` |
| `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv`, and the `.n` copies | run `python3 scripts/regenerate-shard-manifest.py --incremental --write` (drops the unregistered `scripts/infra-config-activation-7220` row; the `generated-at` header change is expected, #10546 changed 6 lines per main TSV and 2 per `.n`) and confirm the only other diff is that row in all four files. Nothing guards the `.n` copies (no test reads `.tsv.n`; kept for parity with the #10546 precedent) | `bash plugins/soleur/test/scripts-shard-manifest.test.sh` (main TSVs only) |
| `scripts/ci-pr-affected-audit.baseline.tsv` | delete the `scripts/infra-config-activation-7220<TAB>scripts/betterstack-query.sh` row (shrink-only; `betterstack-query.sh` keeps 22 other suite rows in the same baseline, so affected-only coverage of it is unchanged) | CI advisory affected-index ratchet (S4 PR3a); CI-only, not verifiable locally |
| `plugins/soleur/test/fixture-relative-assert.baseline.txt` | delete by hand the single row `1<TAB>scripts/followthroughs/infra-config-activation-7220.test.sh`; leave the header prose alone (`ACK_TOTAL` is derived from the rows) | `bash plugins/soleur/test/fixture-relative-assert.test.sh` (use its `--write-baseline` only if row equality names more than that one row) |
| `.claude/hooks/grep-q-pipe-guard.test.sh` | delete the `exempt` row for `infra-config-activation-7220.test.sh \| python3` in Phase 2; re-pin `PJ_TRIPLES` only AFTER Phase 3 (6 of the 7 lost triples come from the `test-argv-bearer-sweep.sh` edit), with the recompute command in the file (expected 287) | `bash .claude/hooks/grep-q-pipe-guard.test.sh` |
| `tests/scripts/test-argv-bearer-sweep.sh` | (a) `HMAC_MANIFEST`: drop the 4 deleted rows (the surviving `inngest-soak-6178` row now owns the opening `HMAC_MANIFEST='`) and the header comment above it ("the four probes ... `dynamic` probes ... run under `probe_rows_hmac`"); (b) `HM5_FILES`: drop the 3 probe paths (`workspace-isolation-verdict-2640` was never in it); (c) the `hm_hmacflag` `git grep` pathspec and its two row labels ("the parity script or the four probes" -> the parity script and the inngest probe); (d) after `git grep -n 'probe_rows_hmac\|dynamic)\|hmx_sandbox'` shows no caller outside the function, delete `probe_rows_hmac`, the `dynamic)` arm, `hmx_sandbox()` with its comment (only `probe_rows_hmac` calls it) and the three fixture bodies it alone read (`canary_pass.json`, `workspace_isolation_pass.json`, `fatal_frame.json`; there is no `activation_frame` body); KEEP the `case` default (an unknown kind fails closed), `hmac-cf`, `hmx_refused`, `hm5_mut`, `PYBAD`, `BIGTOK`, `SHIM_MUTATE`, `bk_calls` (still used by the parity rows); (e) lower `S4_GUARD_FLOOR` and `EXPECTED_TESTS` to the realized counts of the LAST green run after (a)-(d) and (f), append this PR's delta to each floor's ledger comment in the existing style (`S4_GUARD_FLOOR`: the sentence that counts 76 definitions and names #10546's 77 -> 76; `EXPECTED_TESTS`: a new `880 -> N` line), naming #10937 and the four removed probes; (f) sweep the stale prose: the disjointness comment ("the four HMAC probes"), the stage comment above `HM5_FILES` ("parity script and the four followthrough probes"), the stage-done echo, the `hmx_refused` heading comment ("canary-promotion, fatal-channel and parity rows"); then `git grep -n 'four probes\|four HMAC\|four followthrough\|canary_pass\|workspace_isolation_pass\|fatal_frame\|probe_rows_hmac\|hmx_sandbox' tests/scripts/test-argv-bearer-sweep.sh` must print nothing; (g) BEFORE deleting `probe_rows_hmac`, add one row to the parity block copying the deleted `$name-E4` row: a 100,000-byte class-clean `CF_ACCESS_CLIENT_SECRET`, `SHIM_MODE=noread`, pipefail, run against `check-deploy-script-parity.sh`, asserting rc 0, a recorded call and no broken-pipe text (the one property no surviving HMAC-form script exercises; CTO F7); (h) add `scripts/followthroughs/sdk-bash-smoke-verdict-10548.sh` to `HM5_FILES` (a test-list edit, not an edit of the script; a scratch run of `hm5_audit` on it passed all facets) so its static facet audit and mutants run; the rows added by (g) and (h) are part of the realized count `EXPECTED_TESTS` is set to | `bash tests/scripts/test-argv-bearer-sweep.sh` (about 5 minutes; background job, output to a file, read `$?`) |
| `tests/scripts/test-infra-privileged-tier-census.sh`, `scripts/lint-orphan-test-suites.sh` | no edit expected (grep: no reference); run both as guards after the deletions (measured green pre-edit: 376 passed / rc 0) | `bash tests/scripts/test-infra-privileged-tier-census.sh`; `bash scripts/lint-orphan-test-suites.sh` |
| `scripts/guard-vacuity-floor.test.sh` | run it; edit `MIN_FIRING_SUITES` only if the deleted suite was in the firing population (`scripts/followthroughs/` is not in its COVERED/DEFERRED dirs, so expect no change) | `bash scripts/guard-vacuity-floor.test.sh` |

### Comment-only pointers to rewrite (Phase 4; wording: "retired by G1 PR-4a (#10937); history in git")

`.github/workflows/scheduled-followthrough-sweeper.yml` (change ONLY the env comment naming `canary-promotion-5875.sh`, and word its replacement so the three trio env lines keep a named owner: the open trackers #6178 and #10548 declare them; the three env lines stay),
`.github/workflows/canary-status.yml` (three comments: the header line saying the sweeper "only reads this after #5889's `earliest` window opens", the "Same authenticated GET as" header pointer, and the in-step pointer near the `Read /hooks/deploy-status` step; the replacement text MUST contain no dollar sign, backtick or `${{`, because that step body is executed and extracted by the `test-argv-bearer-sweep.sh` S3 rows, so run those rows after the edit; also expect an `infra-validation` run since `canary-probe-set.md` is one of its trigger paths), `knowledge-base/engineering/operations/runbooks/canary-probe-set.md` and `workspace-isolation-canary-probe.md` (both define the workspace-isolation promotion criteria through the retired probe - `consecutive_pass` of at least 5 over a span of at least 3 days; the rewrite MUST keep those criteria as prose and leave every heading and anchor unchanged),
`plugins/soleur/test/preflight-discoverability-test.test.ts` (one code comment; cut-able, see decision-challenges.md).

PR body note (not a code edit): after this PR the `workspace_isolation` field that `cat-deploy-state.sh` writes has no runtime reader (only `cat-deploy-state.test.sh` reads it); that is accepted as the dark-launch soak ledger of a closed tracker and the stale comments in `cat-deploy-state.sh` are the deferred follow-up.

### Left as-is, with disposition (CTO F4)

| Reference | Disposition |
|---|---|
| `apps/web-platform/infra/cat-deploy-state.sh` (3 comments) | LEAVE - hash-bound into the deploy-pipeline trigger; an edit fires a production deploy. Fold into its next real edit; ship files a follow-up issue |
| `scripts/followthroughs/inngest-soak-6178.sh` (comment about the canary probe), `sdk-bash-smoke-verdict-10548.sh` (comment about the workspace probe) | LEAVE - untouchable until PR-4 / task 5.3; dangling accepted |
| `apps/web-platform/infra/ci-deploy.sh` (one comment saying "the canary-promotion follow-through") | LEAVE - HARD BOUNDARY file; comment only |
| `apps/web-platform/infra/sandbox-canary-soak.test.sh` (one comment saying "the canary-promotion follow-through", no script path) | LEAVE - infra-dir comment, generic phrase that names no deleted path |
| `2026-08-04-infra-config-activation-silently-dead-postmortem.md`, `2026-10-12-fix-argv-bearer-sweep-...-plan.md` | LEAVE - historical records (ADR-079 names only the already-retired #5863 probe, not these four, and is not touched) |
| `scripts/followthroughs/*.test.sh` of other probes, `.gitleaksignore`, `CODEOWNERS`, ADR-241, `test-infra-privileged-tier-census.sh` | no reference to the four paths (grep + repo-research) |

## Open Code-Review Overlap

Two open `code-review` issues name `scripts/test-all.sh`: #8659 (33 suites replace test-helpers' composed EXIT trap) and #7942
(two mutation batteries named `*.mutation.sh` run in no gate). Disposition: Acknowledge both. Neither concerns the
`infra-config-activation-7220` registration this PR removes; fixing them needs their own cycle. They remain open.

## Implementation Phases

Work happens on this branch after the plan phase; the plan phase itself edits nothing outside `knowledge-base/project/{plans,specs}/`.

**Phase 0 - Preconditions.** `git fetch origin main && git rebase origin/main` (registries are conflict-prone); re-run `gh issue view` for #5875, #7220, #7296, #2640, #5863, #6178, #10548 and stop if any closed tracker was reopened or #6178/#10548 closed since 2026-10-23 (then re-scope). Re-census with the unnumbered stems: `git grep -n -i -E 'canary-promotion|infra-config-activation|infra-config-fatal-channel|workspace-isolation-verdict' -- . ':!knowledge-base/project'` must match the Footprint tables. Before the bearer-sweep edit, dump its row labels from one full run (`bash tests/scripts/test-argv-bearer-sweep.sh > <scratch>/before.txt 2>&1`, about 5 minutes) so the post-edit label diff can be checked.

**Phase 1 - RED first.** Delete the 5 files only. Run the cheap locally-runnable guards: trio census, `grep-q-pipe-guard`, `fixture-relative-assert`, `scripts-shard-manifest`, `lint-orphan-test-suites`. Each must go red for the reason the Footprint names (a guard that stays green names a missed registration or a vacuous guard - investigate). The bearer-sweep suite is NOT run here (its red state is predictable and it runs after Phase 3); the affected-audit baseline is CI-only.

**Phase 2 - Registries.** Edit the registration rows: trio baseline, `test-all.sh` (and the following suite's comment), shard/duration manifests via the generator, affected-audit baseline, fixture-relative baseline, and the `grep-q-pipe-guard` exempt row (NOT the `PJ_TRIPLES` pin yet).

**Phase 3 - Bearer-sweep suite and the pins that depend on it.** Apply the `test-argv-bearer-sweep.sh` edits (a)-(f) above; run once to green; diff the row labels against the Phase 0 dump as a MULTISET (`sort | uniq -c`, counts and the reworded `hm_hmacflag` / S4 pin labels normalized so they show as remove+add pairs) - the removed labels must be exactly each deleted probe's `$name` rows, its `hm5_audit` and `mutation ($base)` rows and its delegated row (a floor copied from a run that also lost an unrelated row would hide it), and removed minus added rows must equal 880 minus the new `EXPECTED_TESTS`; confirm `S4_GUARD_FLOOR` by identity, not arithmetic: `git grep -l '_bearer_ok() {'` before and after differs by exactly the four deleted paths; repeat the label diff against `origin/main` after the final rebase (zero slack lets a concurrent row on main mask a lost one); only then set `EXPECTED_TESTS` and `S4_GUARD_FLOOR` from that last green run. Then re-pin `PJ_TRIPLES` (expected 287) with the documented recompute command, compare the before/after triple LISTS (not only the count), and re-run `grep-q-pipe-guard`.

**Phase 4 - Comment pointers.** Rewrite the five comment-only pointers.

**Phase 5 - Verify.** All guard commands green; `git diff --name-only origin/main...HEAD` checked against the HARD BOUNDARY list; no closing keyword in the PR body; PR body names the `cat-deploy-state.sh` follow-up. The PR stays unarmed until the operator confirms (decision-challenges.md row).

## Acceptance Criteria

### Pre-merge

- [ ] AC1 `git diff --name-only origin/main...HEAD` (three-dot, so a sibling merge to main cannot move it) contains none of: `apps/web-platform/infra/ci-deploy.sh`, `.github/workflows/git-data-cutover.yml`, any `track.sh` (`.github/actions/dispatch-web-redeploy/track.sh`), the Tier-B loader (`.github/actions/infra-credentials/**`, `.github/actions/mint-infra-app-token/**`), the bridge (`.github/actions/cf-tunnel-ssh-bridge/**`, `.github/actions/cf-tunnel-registry-bridge/**`), `.mcp.json`, `git-data-gc.sh`, `.gc-cursor`, `AGENTS.rules.md`, any legal document, `apps/web-platform/infra/cat-deploy-state.sh`, `scripts/followthroughs/inngest-soak-6178*`, `scripts/followthroughs/sdk-bash-smoke-verdict-10548*`. The only paths outside the Footprint tables the diff may also contain are those the pipeline itself writes: this plan, `knowledge-base/project/specs/feat-one-shot-g1-pr4a-retire-closed-probes/` (tasks.md, decision-challenges.md, session-state.md) and the regenerated `knowledge-base/INDEX.md`.
- [ ] AC2 `git ls-files scripts/followthroughs | grep -E '(canary-promotion-5875|infra-config-(activation|fatal-channel)-7220|workspace-isolation-verdict-2640)'` prints nothing.
- [ ] AC3 `bash tests/scripts/test-trio-baseline-census.sh` ends `0 failed`, and `tests/scripts/trio-baseline.tsv` lost exactly 12 rows (`git diff --numstat origin/main...HEAD -- tests/scripts/trio-baseline.tsv` reports 0 added and 12 deleted lines), every deleted row's path is one of the four deleted probes, and the rows of `inngest-soak-6178.sh`, `sdk-bash-smoke-verdict-10548.sh`, the sweeper and `github-app-key-status.sh` are byte-unchanged.
- [ ] AC4 `bash tests/scripts/test-argv-bearer-sweep.sh` ends `N passed, 0 failed` with `EXPECTED_TESTS == N` and `S4_GUARD_FLOOR` equal to the realized `_bearer_ok` count; both carry a comment naming this PR and the four removed probes. `git grep -n 'probe_rows_hmac' -- tests scripts .github .claude plugins` prints nothing; the `case "$h_kind"` default arm still exists.
- [ ] AC5 `bash .claude/hooks/grep-q-pipe-guard.test.sh`, `bash plugins/soleur/test/fixture-relative-assert.test.sh`, `bash plugins/soleur/test/scripts-shard-manifest.test.sh`, `bash scripts/guard-vacuity-floor.test.sh`, `bash scripts/lint-orphan-test-suites.sh` all exit 0; the `PJ_TRIPLES` value equals the documented recompute command's output.
- [ ] AC6 The sweeper `env:` block still binds `WEBHOOK_DEPLOY_SECRET`, `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET` (`git diff origin/main -- .github/workflows/scheduled-followthrough-sweeper.yml` shows comment lines only), and `apps/web-platform/scripts/github-app-key-status.sh` is unmodified.
- [ ] AC7 `git grep -l -i -E 'canary-promotion|infra-config-activation|infra-config-fatal-channel|workspace-isolation-verdict' -- . ':!knowledge-base/project' | sort` (plans and specs excluded because they quote the names) is a subset of this allowlist and contains every MUST-REMAIN file. MUST remain (left as-is by ruling): `apps/web-platform/infra/ci-deploy.sh`, `apps/web-platform/infra/cat-deploy-state.sh`, `apps/web-platform/infra/sandbox-canary-soak.test.sh`, `scripts/followthroughs/inngest-soak-6178.sh`, `scripts/followthroughs/sdk-bash-smoke-verdict-10548.sh`, `knowledge-base/engineering/operations/post-mortems/2026-08-04-infra-config-activation-silently-dead-postmortem.md`. MAY remain (only if the rewritten text still names the retired probe by design): the two runbooks `canary-probe-set.md` and `workspace-isolation-canary-probe.md`. MUST be absent: `.claude/hooks/grep-q-pipe-guard.test.sh`, `.github/workflows/canary-status.yml`, `.github/workflows/scheduled-followthrough-sweeper.yml`, `plugins/soleur/test/preflight-discoverability-test.test.ts`, `tests/scripts/test-argv-bearer-sweep.sh`, `scripts/test-all.sh`, every TSV/baseline. Any other file is a missed site.
- [ ] AC8 PR body contains `Ref #9294` and no `Closes`/`Fixes`/`Resolves` keyword; it states: the fifth probe was already deleted by #10546, #10548's probe is deliberately retained, the `cat-deploy-state.sh` comment follow-up, and that the PR is NOT armed pending operator confirmation.
- [ ] AC9 CI green on the PR, including the advisory affected-index ratchet job (its baseline row is shrink-only and cannot be exercised locally), after a rebase onto the then-current `origin/main`.

### Post-merge (operator-independent)

- [ ] AC10 Comment on epic #9294 with the merged PR as evidence (#9294 carries no checklist item to tick; only after merge). No production, Terraform or workflow-dispatch step exists in this PR.

## Does merging this alone mutate production?

No. The diff edits no `apps/*/infra/**` file (no Terraform apply, no deploy-pipeline trigger, no host bytes) and no `variables.tf`.
Workflow edits are comment-only (`scheduled-followthrough-sweeper.yml`, `canary-status.yml`). The sweeper's next daily run
simply has four fewer scripts on disk, and none is referenced by an open tracker's directive. The PR body's first line states:
"Deletes four retired followthrough probes and their guard rows; comment-only workflow edits; no production, Terraform or
deploy-pipeline effect."

## Rollback

`git revert <merge-commit>` restores everything; the deletions, the 12 rows and both floors must revert together (a floor left above the realized count reds `test-argv-bearer-sweep.sh`). A revert resurrects probes whose trackers are closed and has no runtime effect.

## Verification note (replaces a mutation-scenario section)

The mutation proof is Phase 1 (each guard reddens when its registration is stale) plus AC4/AC5 (a wrongly lowered floor or pin reds) plus the Phase 3 row-label diff. The change adds no guard, so no Guard Contract entry is owed.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO agent ruled six forks on 2026-10-23 (see `knowledge-base/project/specs/feat-one-shot-g1-pr4a-retire-closed-probes/decision-challenges.md`): scope is four probes + one test; leave closed issue bodies; delete the dead HMAC dynamic machinery and lower the two floors to realized counts; rewrite only the harmless comment pointers; no ADR/C4/absence-test addition; rebase before arming and expect a full-battery CI run. No Product, Legal, Marketing, Finance, Sales, Support or Operations implication (no user-facing surface, no data, no vendor).

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing. The failure mode is internal: a red CI check on this PR, or (worse) a guard floor lowered to the wrong value that lets a later skipped test go unnoticed.
**If this leaks, the user's data is exposed via:** no data path changes; the diff deletes scripts that read a deploy-channel secret and adds no reader, no new secret binding, no log line.
**Brand-survival threshold:** none
threshold: none, reason: the diff is deletion plus comment-only edits to two workflows (`.github/workflows/**` matches the sensitive-path regex); it removes consumers of the deploy-channel trio and binds no secret, so no new exposure vector exists.

## Architecture Decision (ADR/C4)

Not applicable. The change implements D10/G1 already recorded in ADR-241 and makes no architectural decision (no substrate,
trust boundary, ownership or resolver change, no reversal of an ADR). C4 impact check: the actors/systems involved (CI sweeper,
deploy webhook endpoint, GitHub issues) are unchanged and already modeled; the deleted probes were short-lived verification
scripts below C4 granularity. `c4-count-parity` is unaffected (no cron monitor, workflow or heartbeat count changes). Reject
condition not triggered: nothing is deferred to a follow-up ADR.

## Non-Goals and Deferrals

- Retire `inngest-soak-6178.sh` / `sdk-bash-smoke-verdict-10548.sh`, the sweeper's trio env lines, `github-app-key-status.sh`'s trio reads -> tasks 5.3 / PR-4 of #9294 (already tracked in the epic).
- Fix the three `cat-deploy-state.sh` comments and the two comments in the untouchable probes -> follow-up issue filed by `ship` (re-evaluate: at `cat-deploy-state.sh`'s next real edit, and at PR-4). Milestone per `knowledge-base/product/roadmap.md`.
- Strike the #7220 and #7296 closed-body directives -> not planned (CTO F2).
- Coverage thinning in `test-argv-bearer-sweep.sh` after the HMAC dynamic rows go (rows B2zero, C, D, E5/E6, Mnohex ran against the deleted scripts only; the parity block keeps A, A2, B, B2key, E1, E1b, E2, Mbearer, the new E4 row and the static facet audit) -> one `deferred-scope-out` issue filed by `ship`, milestone "Post-MVP / Later" (the milestone epic #9294 carries), re-evaluation criterion: PR-4 / task 5.3 retires or rewrites `inngest-soak-6178.sh` and `sdk-bash-smoke-verdict-10548.sh`; the issue closes with it (CTO F7).
- Arm auto-merge -> operator confirmation required; not assumed.

## Observability, Encryption, GDPR, IaC, Guard gates (all skipped, with reasons)

- Observability (plan 2.9 / deepen 4.7): no Files-to-Edit path is in the code-class set (`apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, `plugins/*/scripts/`); the edits are under `scripts/`, `tests/`, `.claude/hooks/`, `plugins/soleur/test/`, `.github/workflows/` (comments) and `knowledge-base/`, and the change deletes consumers and adds no emitter, route or infrastructure surface.
- Encryption posture (2.11 / 4.10): no `.tf`, migration, cloud-init or compose file, and no new store or connection.
- GDPR (2.7): no regulated-data surface; the deleted probes read a deploy-status endpoint, not personal data.
- IaC routing (2.8): no new infrastructure; no operator provisioning step.
- Guard Contract (2.12 / 4.11): the change adds no guard; it lowers two existing floors, evidence for which is the Phase 3 row-label diff, so no `## Guard Contract` section is owed (the lint reports 0 contracts, 0 entries).
- UI wireframe (4.9): no UI-surface path.

## Sharp Edges

- The `## User-Brand Impact` section must stay filled with a concrete artifact, vector and threshold; an empty or unfinished one fails `deepen-plan` Phase 4.6.
- The baseline file is anchored by PATH, not row number: rows 192-200 (6178 and 10548) sit between the two deleted blocks and must survive.
- `EXPECTED_TESTS` has zero slack; never lower it by arithmetic - re-run the suite and copy the realized number.
- Do not pipe the long suites into `tail`/`head` (masks the exit code and SIGPIPE-kills); run in the background with the output redirected to a file and read `$?`.
- `scripts/test-all.sh` is a runner file: expect `--affected` to degrade to the full battery and a long CI run.
- Do not write a closing keyword in the PR body; do not arm the PR.
