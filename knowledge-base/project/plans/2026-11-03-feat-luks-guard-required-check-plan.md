---
title: "feat: make Inngest sole-copy LUKS Guard 1 a merge-blocking check (epic #9927 item 10)"
date: 2026-11-03
slug: luks-guard-required-check
branch: feat-luks-guard-required-check-codeowners
issue: 9927
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-11-03-luks-guard-required-check-codeowners-brainstorm.md
spec: knowledge-base/project/specs/feat-luks-guard-required-check-codeowners/spec.md
draft_pr: 11998
---

# feat: make Inngest sole-copy LUKS Guard 1 a merge-blocking check

Ref #9927 (item 10). The epic stays open: use `Ref #9927` in the PR body, never `Closes`.

## Overview

Guard 1 (`apps/web-platform/infra/inngest-luks-sole-copy.test.sh`) pins the delete-protection, `prevent_destroy` and no-`ignore_changes` attributes of the six sole-copy Inngest LUKS addresses. It runs only in the path-filtered `deploy-script-tests` job of `infra-validation.yml`, so a red Guard 1 does not block a merge (ADR-282, "Enforcement posture"). This plan registers it in the `want_scripts` block of `scripts/test-all.sh`, which the required `test` aggregate already waits on through `test-scripts`. It does not touch `infra/github/ruleset-ci-required.tf`.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (checked 2026-11-03 in the worktree) | Plan response |
|---|---|---|
| Brief and first CTO ruling: Guard 1 is `inngest-redis-luks.test.sh` | Guard 1 is `inngest-luks-sole-copy.test.sh`; the other file is a separate suite | Every task names the correct file |
| Brainstorm: "if `lint-orphan-test-suites.sh` objects, use a thin wrapper" | It objects by design: the infra runner's glob (`run-registered-suites.sh`, surface 3) already covers every `apps/web-platform/infra/*.test.sh`, so an explicit `run_suite` makes it covered by two surfaces and the lint fails unless the path is in `DOUBLE_COVERED_ACK` (`scripts/lint-orphan-test-suites.sh`, the `DOUBLE_COVERED_ACK=(` array). Five entries exist as precedent, e.g. `scripts/lib/frontmatter-strip.test.sh` (explicit `run_suite` AND a glob) | Use the ACK path, not a wrapper. A wrapper adds a file whose only job is to exec another suite, which is one more vacuity vector for no gain |
| Brainstorm: PyYAML on the runner is unverified | Guard 1 uses `python3 -c 'import yaml'` (suite line ~754). At least five suites already in the `scripts/` glob (e.g. `scripts/ci-push-dedupe.test.sh`, `scripts/alarm-issue-filing-guard.test.sh`) import `yaml` and run in `test-scripts` | Treated as satisfied; AC4 measures it on the real runner anyway |
| Brainstorm: Guard 1 is ~40 s | Local run 89/89 in 39.7 s (CTO measurement). The infra runner's own manifests already record it: `apps/web-platform/infra/suite-shard-legs.tsv` (leg 4) and `suite-durations.tsv` (72000 ms). These are a different manifest from `scripts/suite-shard-legs.tsv` | Plan with 40-72 s; the CI figure is measured in AC4 and written into the ADR addendum |
| `test-all.sh` has one `want_scripts` region | It has two column-0 `if want_scripts; then` regions (around lines 5439 and 7149); the census line is in the first | The pin scopes to the region that contains the line, not "exactly one region" (architecture review, mechanical) |
| CODEOWNERS rows add protection | `*` already names `@deruelle`; the ruleset has no `require_code_owner_review` | Rows are routing text. The ADR addendum says so in those words |
| Collision pre-check | `collision-precheck.sh 9927`: no open PR names #9927. One foreign `test-all.sh` process in another worktree (`/tmp/s4-pr5b-trials`), unrelated to this change | No action; reported per the skill |

## Research Insights

- **Property List (Phase 0.6b).** P1: a red Guard 1 blocks merge. P2: the registration cannot be dropped or neutered in a diff without a second suite going red. P3: the repo's records do not call Guard 1 advisory once it is not. P4: no new required context (no ruleset change).
- **Cut List.** (1) Thin wrapper script: buys nothing the ACK entry does not, and adds a vacuity vector. (2) New CI step or new required context: `test-scripts` is already in `test`'s `needs` (`ci.yml`, the `test:` job) and is not path-filtered. (3) Executing the G2e sunset: deleting the independent anchor in the same diff that adds the new gate is the one-diff weakening G2e exists to prevent (CTO ruling); deferred.
- **Value measurement (0.6c).** No cost saving is claimed. The value claim is enforcement; its measure is AC1 (a mutated Guard 1 turns `test-scripts` red).
- **Shard.** `test-scripts` (`ci.yml`, `needs: [push-dedupe, draft-light]`, `ubuntu-latest`) always reports unless push-dedupe or draft-light elide it, the same conditions the other required legs have. The `test-scripts-heavy` leg is a one-suite-per-leg 60-minute carve-out and is the wrong home for a ~40 s suite.
- **Leg assignment.** `scripts/suite-shard-legs.tsv` (n=8) is regenerated with `python3 scripts/regenerate-shard-manifest.py --incremental --write`; untabled labels hash-fall-back, so a missing row is not a failure.
- **Premise validation.** #9927 is open. ADR-282 "Enforcement posture" records the gap and names this item. No ADR rejects the mechanism ("promote the suite into a required context, or add a thin required aggregator" is ADR-282's own wording).

## Open Code-Review Overlap

None checked against live issues beyond the scope of this plan; the work phase runs the two-stage `gh issue list --label code-review` query on the final Files lists before the first commit (task 5.1).

## User-Brand Impact

**If this lands broken, the user experiences:** nothing at the moment of merge. The failure is latent: a later diff weakens a sole-copy protection (delete protection off, `prevent_destroy` removed) and merges green, and the only copy of the Inngest scheduler's data volume is destroyed. Users see missed scheduled work they never get back.

**If this leaks, the user's workflow data is exposed via:** no new exposure vector. The change adds a test registration and records; it reads and writes no user data and no secrets.

**Brand-survival threshold:** single-user incident.

CPO sign-off: required by this threshold (`requires_cpo_signoff: true`). The brainstorm did not spawn the CPO (no product surface); the sign-off is requested in the plan-review step below and recorded here before `soleur:work` starts.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-282 with an addendum (no new ordinal): "Guard 1 promoted into the required `test` context" with the measured before/after, the statement that CODEOWNERS rows are a routing hint and not enforcement, the retained G2e anchor (SUNSET comment amended, not executed), and the residual that one diff can still edit the registration and the pin together. This is a deliverable of this plan.

### C4 views

No C4 impact. Checked against the model: no new external actor, no new external system or vendor, no new container or data store, and no change to an actor-to-surface access relationship; the change registers an existing test in an existing CI job. AC9 backs the conclusion with a green `plugins/soleur/test/c4-count-parity.test.sh` run (no workflow or monitor is added, so no derived count moves).

### Sequencing

Authored in this PR; nothing is postponed.

## Implementation Phases

### Phase 1 — Registration (tests first)

1.1 Write the failing pin first (Phase 2), then register the suite.
1.2 In `scripts/test-all.sh`, inside the `if want_scripts; then` region that holds the census registration (the line `run_suite "tests/scripts/infra-privileged-tier-census" ...`), add on its own line, with a comment citing #9927 and ADR-282:
`run_suite "apps/web-platform/infra/inngest-luks-sole-copy" bash apps/web-platform/infra/inngest-luks-sole-copy.test.sh`
1.3 In `scripts/lint-orphan-test-suites.sh`, add one `DOUBLE_COVERED_ACK` entry for `apps/web-platform/infra/inngest-luks-sole-copy.test.sh` with a reason that cites #9927 and states both surfaces are load-bearing (infra runner: the existing job; `test-scripts`: the required context). Check `scripts/lint-orphan-test-suites.test.sh` for any assertion that pins the ACK count at five and update it in the same commit.
1.4 Run `python3 scripts/regenerate-shard-manifest.py --incremental --write` and commit the TSV row it adds, or confirm the label hash-falls-back cleanly and leaves the TSV unchanged.
1.5 Run `scripts/lint-orphan-test-suites.sh`: it reds an UNCLASSIFIED `run_suite` registration (declared-edge classification in `test-affected-paths.sh`). If the new label needs an edge, add an `AFFECTED_APPS_WEB_PLATFORM_INFRA_INNGEST_LUKS_SOLE_COPY_PATHS`-style edge covering the six `.tf` addresses' files and the lexer, so an edit to a pinned file selects the suite under `--affected`.
1.6 Update the comment above `DOUBLE_COVERED_ACK` ("five suites ... fails on any SIXTH") to six. No test pins the count at five.

### Phase 2 — Deregistration pin (independent shard)

In `plugins/soleur/test/terraform-target-parity.test.ts` (runs in `test-bun`, a different required leg from the registration), add a G2f block next to G2e that reads `scripts/test-all.sh` and asserts: the label occurs exactly once in the whole file, that one line equals the exact registration command (after stripping a trailing comment), it sits inside the column-0 `if want_scripts; then` region that contains it (reuse the awk region reader at `scripts-shard-totality.test.sh` around lines 127-140; `test-all.sh` has two such regions), it has no enclosing INDENTED `if` (an `if false; then` nested in the region is RED), a trailing `|| true` or other control suffix is RED while a plain trailing comment is allowed, and the target `.test.sh` file exists. A neutered suite body (`exit 0`) is not G2f's job: cite the existing `guard-vacuity-floor.test.sh` PROMOTED_FILES check and add Guard 1 to it if absent. Also bump `TEST_FLOOR` and its comment ledger in the parity test to the new exact count (the file's own ratchet convention). Fail closed: zero regions, zero lines or two lines is RED, never "nothing checked, green". Amend the G2e SUNSET comment to say G2e may stay as the independent anchor after Guard 1 is required (execution is a follow-up, see Non-Goals).

### Phase 3 — Records

3.1 `.github/CODEOWNERS`: add `@deruelle` rows for `/plugins/soleur/test/terraform-target-parity.test.ts`, `/tests/scripts/test-infra-privileged-tier-census.sh`, `/tests/scripts/lib/hcl-effective-text.sh`, `/tests/scripts/lib/inngest-host-replace-gate.sh`, `/tests/scripts/test-inngest-host-replace-gate.sh`, with a header comment saying they are routing text (the ruleset has no `require_code_owner_review`).
3.2 ADR-282: addendum as above; also update the "Enforcement posture" sentences that say Guard 1 is advisory with a dated `Superseded` marker rather than an in-place rewrite. CPO conditions (plan sign-off, 2026-11-03): (a) the addendum states in one plain paragraph that the check is a regression check on Terraform text and does NOT prevent account-level loss, including an Admin or Member switching protection off or the account being compromised, so the sole copy has no recovery path until the owner decides on the off-project copy; (b) it links the owner-assigned, dated tracker for that decision, which already exists as item 1b of #9927 (re-evaluate by 2027-01-08), so no duplicate issue is filed; (c) no owner- or user-facing text calls the check "protected" or "guarded": use "regression-checked".
3.3 Guard 1's own header (`THIS SUITE IS ADVISORY until it is promoted to a required check (#9927)`): change to state it is required via `test-scripts`, keeping the ANCHOR paragraph's one-diff caveat.
3.4 Legal records, conditional on merge and citing the check by name (`test`, via `test-scripts`), with a dated `> **Superseded 2026-11-03 (#9927): ...**` marker under each superseded sentence: `knowledge-base/legal/article-30-register.md` TOM (13) (Inngest sole-copy store; "Guard 1 ... advisory until promoted") and `knowledge-base/legal/compliance-posture.md` (the row reading "Guard 1 is advisory until promoted"). Do not touch #8528 or any off-project-copy text. The published policies (`docs/legal`, `plugins/soleur/docs/pages/legal`) make no Guard 1 claim, so no mirror or SHA re-pin applies.

### Phase 4 — Verify on the real runner

Push the branch, let CI run, and read the `test-scripts` leg that carries the suite from the Actions API (`gh api` job steps, not the UI): record its wall time and that the label appears in the summary. Then run the mutation matrix below against a throwaway copy.

### Phase 5 — Housekeeping

5.1 Run the open code-review overlap query on the final file lists and record dispositions in this section.
5.2 PR body: `Ref #9927`, never `Closes`; list the legal amendments; state that the G2e sunset and the off-project copy decision are not in this PR.

## Files to Edit

- `scripts/test-all.sh`
- `scripts/lint-orphan-test-suites.sh`
- `scripts/test-affected-paths.sh` (only if the lint demands a declared edge)
- `scripts/guard-vacuity-floor.test.sh` (only if Guard 1 is missing from PROMOTED_FILES)
- `scripts/suite-shard-legs.tsv` (only if the incremental regen adds a row)
- `plugins/soleur/test/terraform-target-parity.test.ts`
- `apps/web-platform/infra/inngest-luks-sole-copy.test.sh` (header comment only)
- `.github/CODEOWNERS`
- `knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md`
- `knowledge-base/legal/article-30-register.md`
- `knowledge-base/legal/compliance-posture.md`

## Files to Create

None. (Plan, tasks and spec artifacts already exist under `knowledge-base/project/`.)

## Guard Contract

### Guard 1 — Guard 1 registration pin (G2f)

**Property.** Guard 1 executes inside the required `test` aggregate on every PR, so a red Guard 1 blocks merge, and one diff cannot remove that registration without another required suite going red.

**Assembly.** The property quantifies over every place the registration can be made inert: (a) the `run_suite` line in `scripts/test-all.sh`; (b) the `if want_scripts; then` region that contains it (a move into `want_infra`, `want_scripts_heavy` or a dead `if false` block silently stops it running in `test-scripts`); (c) the `DOUBLE_COVERED_ACK` entry (removal reds `lint-orphan-test-suites`, which runs in the same aggregate); (d) the `test-scripts` job's membership in `test`'s `needs` in `ci.yml`; (e) the suite file path. The chokepoint is `test-all.sh`'s `want_scripts` region; (d) is guarded by existing aggregator tests and is named here so it is not forgotten.

**Mutation matrix.**

| # | Mutation (must turn RED) | Expected red |
|---|---|---|
| M1 | Delete the `run_suite` line | G2f (`test-bun`) |
| M2 | Replace the command with `bash -c true` (stub) | G2f exact-line match |
| M3 | Move the line out of the `want_scripts` region into `want_scripts_heavy` | G2f region check |
| M4 | Keep the real line and add a second decoy line with the same label and `\|\| true` | G2f exactly-one-occurrence check |
| M5 | Remove the `DOUBLE_COVERED_ACK` entry | `lint-orphan-test-suites` |
| M6 | Pin's own dispatch: make the region regex match zero regions | G2f reports RED ("0 regions"), not green |

**Harness rows.** RED: edit the pin file so the assertion compares against a non-matching string and confirm G2f itself fails the suite (harness mutation). Must-PASS, not the canonical: the registration line with a different permitted trailing comment, and a registration with different spacing inside the region; the pin must stay green on both.

**Anchor.** The pin compares a stored expectation (the exact line) to the file that holds it; both can be edited in one diff, so this proves consistency, not integrity. What sits outside the commit: the pin runs in a different required leg than the registration, the CODEOWNERS rows route the edit to the owner, and the live proof is AC1 on the real runner. The ADR addendum records the residual in plain words.

## Acceptance Criteria

- [ ] AC1: On the PR, a deliberately broken copy of Guard 1's subject (for example `delete_protection = false` in a scratch copy of `inngest-redis-luks.tf` on a throwaway branch) turns the `test-scripts` leg red and therefore `test` red; evidence is the Actions API job conclusion, not a screenshot.
- [ ] AC2: `lint-orphan-test-suites.sh` exits 0 with the ACK entry and exits non-zero without it.
- [ ] AC3: Mutations M1-M6 each turn their named check red; the harness rows behave as stated; results are listed in the PR body.
- [ ] AC4: CI wall time of the Guard 1 step on `ubuntu-latest` is measured from the Actions API job steps and written into the ADR addendum next to the local 39.7 s figure; PyYAML presence is confirmed by the suite's H1d/H1e rows passing there.
- [ ] AC5: `infra/github/ruleset-ci-required.tf` is unchanged (`git diff origin/main -- infra/github` is empty).
- [ ] AC6: CODEOWNERS rows exist for the five files; the ADR addendum describes them as routing text.
- [ ] AC7: Article 30 TOM (13) and `compliance-posture.md` carry the dated `Superseded` markers, conditional wording, no change to #8528 text.
- [ ] AC8: The G2e SUNSET comment is amended, G2e itself is not deleted or weakened.
- [ ] AC9: `plugins/soleur/test/c4-count-parity.test.sh` is green.
- [ ] AC10: PR body uses `Ref #9927` and contains no `Closes`/`Fixes` for it.
- [ ] AC11 (CPO conditions): the ADR addendum carries the plain residual-risk paragraph, links #9927 item 1b as the dated owner decision, and `git diff origin/main` shows no added line calling the check "protected" or "guarded" in the ADR, the two legal records or the PR body.

## Domain Review

**Domains relevant:** Engineering, Legal

### Engineering

**Status:** reviewed
**Assessment:** CTO ruled shape, shard, flakiness, CODEOWNERS and G2e questions on 2026-11-03 (Ruled by CTO agent). Residual one-diff risk accepted and recorded.

### Legal

**Status:** reviewed
**Assessment:** CLO: no gate; two records need a conditional amendment on merge; published policies unaffected.

Product/UX Gate: not relevant (no UI surface).

## Non-Goals

- Executing the G2e sunset (follow-up after the new leg soaks green on `main`). Owner: the engineering owner of #9927; a tracked issue is filed at ship time with the re-evaluation criterion "two weeks green on `main` and the merge queue", and the issue states that G2e and G2f coexist until then.
- `require_code_owner_review`, ruleset changes, the off-project ciphertext copy, the A6 sentence, the host replace, closing #9927, item 8.

## Sharp Edges

- The registration is double-covered by design (infra runner glob and `test-all.sh`). That makes a single-surface de-registration a silent no-op for the orphan lint, which is exactly why the G2f pin exists; do not remove the pin as redundant.
- A path-filtered job cannot be a required context (it never reports on unrelated PRs); that is why the fix registers the suite in an always-reporting leg rather than making `deploy-script-tests` required.
- Do not describe the CODEOWNERS rows as protection anywhere.
