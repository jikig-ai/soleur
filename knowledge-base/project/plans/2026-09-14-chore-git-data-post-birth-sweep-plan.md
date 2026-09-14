---
title: "chore(git-data): post-birth sweep of the birth route — stale hold prose, poll gating, evidence provenance, ledger flip"
date: 2026-09-14
slug: chore-git-data-post-birth-sweep
branch: feat-one-shot-8010-post-birth-sweep
issue: 8010
closes: none
type: chore
lane: cross-domain
priority: p2-medium
domain: engineering
brand_survival_threshold: none
---

## Overview

The git-data host was born on 2026-09-14 (run 34861860722 `git-data-host-replace` re-birthed it after run 34836141887's host died on a transient HTTP 504 during the Doppler CLI download; `boot_complete` arrived at 15:27:24 UTC with all five booleans `yes`; the #6982 probe reads PASS). Before that, the rung-2 rehearsal (run 34768256297, evidence PR #8126) released `git_data_rung2_rehearsal_gate`, and the DO-NOT-DISPATCH banner at the top of `git-data-birth.md` was cleared on 2026-09-13 (PR #8128). A set of comments, dispatch-dialog text, gate HOLD messages, one workflow step condition and one ledger row still describe the pre-release world.

This plan lands the #8010 comment-thread sweep items that are **operator-visible or change workflow behaviour** first, then the pure-prose items only while the change stays inside a ≤100-line diff budget. It **does not close #8010** — that issue's body items 1–3 (bind the rehearsal run id, resolve the run, make `RUNG2_SENTRY_CROSSCHECK` load-bearing) stay open. The PR body carries `Ref #8010`, and a closing comment on #8010 records exactly which sweep items this PR took and which remain.

Two hard boundaries govern every edit: none of the 13 hash-bound birth inputs is touched (the rehearsal gate must print `RELEASED` with the same sha256 `5c50797be8392fe551a940ae04555c52a3f4409cf249ed11bb1280fec783d5b1` before and after), and `apps/web-platform/infra/git-data-rung2-boot-evidence.env` is never edited.

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality (measured 2026-09-14 on this branch) | Plan response |
|---|---|---|
| Item 12: flip `live_verification` to "the `available:` form the ledger's schema expects with that evidence pointer" | `scripts/lint-encryption-posture.py` `LIVE_VERIFICATION_RE = ^(available\|unavailable:.+)$` — `available` must be **bare**; an `available:<pointer>` value fails schema validation | Write `"live_verification": "available"` and carry the evidence pointer (run 34768256297 + the 2026-09-14 birth row) in the row's `evidence` string, which no regex constrains beyond the boilerplate check |
| `apps/web-platform/infra/variables.tf` git-data server-type description may still say something superseded by ADR-068 D-SIZE | The `git_data_server_type` description already cites "ADR-068 D-SIZE", restates the enforced-invariant framing verbatim, and names the cpx12/ccx13 rejections. Nothing in it is superseded | **Skip** variables.tf (verified accurate; stated in the #8010 comment) |
| (e) "The merge of this PR touching `apps/web-platform/infra/**` triggers the Web Platform Release deploy arm" | With variables.tf skipped and the evidence file untouchable, **no listed sweep item lives under `apps/web-platform/**`**. `web-platform-release.yml` fires on `apps/web-platform/**` / `plugins/soleur/**` and `reusable-release.yml`'s `check_changed` runs `git diff --name-only HEAD~1 -- apps/web-platform/ plugins/soleur/ …` — a merge that touches neither skips the release and the deploy | Take one additional post-birth stale-prose fix that is legitimately in class and lives under `apps/web-platform/infra/` but is NOT hash-bound: the `git-data-rung2-rehearsal.test.sh` comment "because the git-data host has never been born and `prd_git_data` holds nothing to read" (falsified by the birth). That makes the merge fire the release arm organically. Fallback if the deploy arm still does not fire: ship Phase 7 dispatches `gh workflow run web-platform-release.yml -f bump_type=patch` |
| (e) premise: the running container's env predates the three minted `GIT_*_SSH_PRIVATE_KEY` secrets | Confirmed: `doppler_secret.git_{transport,provision,remove}_ssh_private_key` are in the `git-data-host-create` `-target` set (minted by run 34836141887's apply, after 15:13 UTC); the live container is `build_sha 07baff179` from release run 34847849924 (deploy at ~13:20 UTC) and the only later release run (34856529350, 14:34 UTC, `ci:` commit) skipped release + deploy | The redeploy remains REQUIRED; ship Phase 7 verifies the deploy job and `/health` `build_sha` |
| Item 15: "gate it on the apply step's outcome; `if: steps.<apply-step-id>.outcome == 'success'` or equivalent" | The poll step's own comment records a deliberate design: "`if: always()` so a FAILED apply still reports what the host did or did not say — a partial birth is exactly when the boot evidence matters most." Run 34822248580's defect is the **skipped** apply, not the failed one | Use the "equivalent": `if: !cancelled() && (steps.apply.outcome == 'success' \|\| steps.apply.outcome == 'failure')` — excludes `skipped` (and a cancelled run, via the repo's `!cancelled()` idiom that the parity suite documents as the correct alternative to `always()`), preserves the partial-birth poll. The apply step currently has no `id:`; add `id: apply` |
| Item 8: `test-git-data-birth-readiness-gate.sh` "pins that the HOLD names `git-data-birth.md`" | Two pins on the sentinel HOLD: `check "the HOLD names the blocking issue" 1 "#6982"` and `check "the HOLD names the runbook banner to clear" 1 "git-data-birth.md"`. No pin on the rung-2 no-evidence HOLD text | Keep both substrings in the reworded HOLD; rename the second check's label and add one pin on the new wording |
| Item 3: "nine payloads" prose is stale → "13-file roster" | `git_data_rung2_bound_files` lists 13 inputs = 1 template + 3 module `.tf` + 9 `file()`-bound payloads. "the nine payloads" is an incomplete description of the hash's scope, not a wrong count of payloads | Tier C (prose); if taken, reword to "the template, the render module's three .tf files and the nine payloads (13 inputs)" |

## Research Insights

**Premise Validation (Phase 0.6).** #8010 is OPEN, title "git-data: git_data_rung2_rehearsal_gate checks assertion SHAPE, not that a rehearsal passed…", `closedByPullRequestsReferences` = 0 — the premise holds and the PR must not close it. The six thread comments (2026-09-11 04:03 triage, 2026-09-11 20:54 Guard-4 residual, 2026-09-13 16:32 Sentry data point, 2026-09-13 16:44 items 1–6, 2026-09-13 17:53 items 7–13, 2026-09-14 15:30 items 14–17) were read in full. Runs 34822248580 (failure, 08:20–08:34 UTC), 34836141887 (failure, 11:02–15:24 UTC) and 34861860722 (success, 15:23–15:27 UTC) resolve via `gh run view`. Every cited file path exists on this branch (`apply-web-platform-infra.yml`, `git-data-birth-readiness-gate.sh` + its test, `git-data-rung2-evidence-capture.sh`, `encryption-posture-ledger.json`, `lint-encryption-posture.py`, `git-data-birth.md`, `git-data-rung2-rehearsal.yml`, `git-data-rung2-rehearsal.md`, ADR-152, `infra-validation.yml`, `variables.tf`). Two brief claims were stale and are reconciled above (the `available:` schema form; the deploy-arm trigger). No ADR rejects any mechanism here: ADR-149 (birth checklist), ADR-152 (render-time comment strip) and ADR-068 D-SIZE were read at the cited anchors.

**Property List (Phase 0.6b).**

- P1. The Run-workflow dialog for `apply_target=git-data-host-create` describes the hold that exists today (environment approval), not the cleared banner.
- P2. Both readiness-gate HOLD messages, when they fire again (a future template edit re-HOLDs the rung-2 gate; a stripped emitter re-HOLDs the sentinel gate), tell the reader what to do without naming a banner that no longer exists, while still naming `git-data-birth.md` and `#6982`.
- P3. The birth job's boot-signal poll does not spend its 10-minute budget when no apply ran, and its "the apply may be green" wording is only printed when an apply actually ran.
- P4. A recorded `# QUERY:` in the evidence file can be re-run against the table it was actually asked of (`BS_TABLE` / `BS_TABLE_S3` recorded beside it).
- P5. The encryption-posture ledger does not assert "no rehearsal has been dispatched yet" after two dispatches observed `luks_mounted=yes`, and the lint's live-coverage floor still passes.
- P6. The merge redeploys the web-platform container so its env carries the three SSH private keys minted at the birth (ship Phase 7 verifies).
- P7. The 13 hash-bound inputs and the evidence file are byte-identical before and after (rung-2 gate: `RELEASED`, same sha256).

**Cut List (Phase 0.6b).** Item 14 (Doppler download retry budget — hash-bound; needs its own rehearsal), item 16 (replace-job poll — separate logic + test surface), item 5 (Sentry liveness window decoupling — a behaviour change tied to #8010 body item 3), item 17 (informational; nothing to edit) — all cut from this PR by the brief; recorded on the #8010 comment. `variables.tf` — verified accurate, cut. No mechanism the brief proposes is already covered by an existing repo mechanism: the `if:` gating has no equivalent today (`always()` is the current predicate), and no `# TABLE:` line exists in the evidence writer.

**Precedents.**

- Step gated on a sibling apply outcome: `.github/workflows/apply-deploy-pipeline-fix.yml` — `if: steps.repush_apply.outcome == 'success'` (two sites) and `REPUSH_APPLY_OUTCOME: ${{ steps.repush_apply.outcome }}` threaded into a summary step's env. `apply-web-platform-infra.yml` itself has no `steps.*.outcome` reference yet; its step-level `if:` predicates are not parsed by the parity suite's job-level predicate evaluator (`terraform-target-parity.test.ts`, "Evaluate a GitHub job-level `if:` expression" — `always()` is the only status function it models, and it reads job-level `if:` only).
- The evidence writer block (`git-data-rung2-evidence-capture.sh`, the `{ printf … } > "$OUT"` block that prints `# QUERY:` / `# QUERY_FATAL:` / `RUNG2_SENTRY_CROSSCHECK=`): `tests/scripts/test-git-data-rung2-evidence-capture.sh` asserts only that the output contains `QUERY` and each `RUNG2_*` key; nothing pins the order or set of comment lines. `BS_TABLE` is exported process-wide (`export BS_TABLE="${BS_TABLE:-$BS_GIT_DATA_TABLE}"`); `BS_TABLE_S3` is never set in the capture script — `scripts/betterstack-query.sh` derives it as `BS_TABLE_S3="${BS_TABLE%_logs}_s3"` unless explicitly set.
- Ledger: `live_coverage_floor: 1`; exactly one store is `available` today (`hcloud_volume.workspaces_luks`). `check_live_coverage_floor` counts bare `"available"` values. The `git-data-luks.test.sh`-style mapper check reads `device_binding.mapper` (`git-data`) against mount evidence and already passes for the rehearsal row.
- Runbook `git-data-birth.md` "After the birth — verify the host actually booted (#6982)": "The dispatch's own post-apply step polls for the boot signal and FAILS the job if it does not arrive, so a green run is now meaningful — but verify independently if that step warned that its credentials were missing." — one sentence to extend with the gating.

**Institutional learnings.**

- `knowledge-base/project/learnings/2026-09-14-the-birth-gate-refused-the-real-birth-because-its-fixtures-never-showed-it-a-real-plan.md` — Session Error 7 is item 15 verbatim: "gate the poll on the apply step's outcome".
- `knowledge-base/project/learnings/integration-issues/deploy-gate-docker-pushed-output-ci-20260330.md` — gate downstream steps on `steps.X.outcome == 'success'`, not on pre-computed outputs.
- `knowledge-base/project/learnings/2026-09-11-every-sentence-my-runbook-inherited-was-false-when-measured.md` — measure every prose claim at authoring time; this sweep is that discipline applied post-birth.
- `knowledge-base/project/learnings/2026-07-30-four-ways-a-green-guard-asserted-nothing-rung2-route.md` and `2026-07-29-every-guard-i-fixed-this-session-was-narrower-than-the-claim-it-carried.md` — why the 13 hash-bound inputs must not move: the evidence hash is the gate.
- `knowledge-base/project/learnings/2026-07-24-formalizing-a-provisional-provider-attestation-honest-close-and-citation-not-probe.md` — `available` is for an observed probe, `unavailable:<reason>` for a citation. Two observed `luks_mounted=yes` rows (rehearsal + birth) are observations, so `available` is now the honest value for the rehearsal row.
- `knowledge-base/project/learnings/2026-07-24-count-vs-floor-guard-single-value-fixtures-cannot-discriminate-operator.md` — the floor guard is count-based; raising `live_coverage_floor` is a separate decision, not taken here (see Decisions).

**Baselines measured on this branch (pre-edit).** `bun test plugins/soleur/test/terraform-target-parity.test.ts` → 194 pass / 0 fail. `bash tests/scripts/test-git-data-birth-readiness-gate.sh` → 149 passed / 0 failed. `bash tests/scripts/test-git-data-rung2-evidence-capture.sh` → 80 passed / 0 failed. `bash tests/scripts/test-web-host-birth-gate.sh` → 34 passed / 0 failed. `python3 scripts/lint-encryption-posture.py --repo-sweep` → `18 stores, 5 connections, 0 unledgered, 0 failing checks -> PASS`. `git_data_rung2_rehearsal_gate` → `RELEASED … sha256 5c50797be8392fe551a940ae04555c52a3f4409cf249ed11bb1280fec783d5b1 … provenance: PASS`.

**Plan-prose constraints.** `scripts/lint-infra-no-human-steps.py` and `.claude/hooks/iac-plan-write-guard.sh` reject a human-actor token near an infrastructure imperative in this directory; this plan names workflow steps and jobs rather than actors, and cites no shell that provisions anything.

## Scope tiers and the line budget

Budget metric (the AC uses exactly this): `git diff --shortstat origin/main...HEAD -- . ':!knowledge-base/project/plans' ':!knowledge-base/project/specs' ':!knowledge-base/project/learnings'` insertions + deletions **≤ 100**. Estimates below are diff lines (a modified line counts 2).

| Tier | Item | File | Est. | Take when |
|---|---|---|---|---|
| A | 7 | `.github/workflows/apply-web-platform-infra.yml` — `apply_target` description + "The banner stays up until #7025 lands the evidence." | ~6 | always |
| A | 8 | `tests/scripts/lib/git-data-birth-readiness-gate.sh` (both HOLDs) + `tests/scripts/test-git-data-birth-readiness-gate.sh` (pin) | ~14 | always |
| A | 15 | `.github/workflows/apply-web-platform-infra.yml` — `id: apply`, poll `if:`, comment, outcome in error text; `git-data-birth.md` one sentence | ~14 | always |
| A | 1 | `scripts/followthroughs/git-data-rung2-evidence-capture.sh` — `# TABLE:` line | ~2 | always |
| A | 12 | `scripts/encryption-posture-ledger.json` — rehearsal row `live_verification` + `evidence` | ~4 | always |
| A | 18 (new) | `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` — "has never been born" comment | ~4 | always (also what fires the deploy arm) |
| B | 6 | `apply-web-platform-infra.yml` job-header/second-interlock comments; `git-data-rung2-rehearsal.yml` five FAIL summaries (one identical sentence) | ~26 | always |
| B | 9, 10, 11, 13 | `git-data-rung2-rehearsal.yml` header; `git-data-rung2-rehearsal.md` L6; ADR-152 §Scope; `infra-validation.yml` step comment | ~9 | always |
| C | 3, 4 | "nine payloads" prose (capture script ×2, gate lib ×2, rehearsal runbook); stale "one result set" generator comment | ~12 | only if the single post-B measurement stays ≤ 100 |
| C | 2 | rehearsal runbook "After a PASS" re-run snippet | ~6 | same |
| — | 5, 14, 16, 17, variables.tf | excluded by the brief / verified accurate | 0 | never in this PR |

Expected: Tier A ≈ 50 (after the advisor's two summary lines), A+B ≈ 85, A+B+C ≈ 103. Take A and B unconditionally. Measure ONCE after B; take Tier C in the order 3 → 4 → 2 while the measured total stays ≤ 100 (item 2 is the likeliest to fall out). Whatever is not taken is named on the #8010 comment. The ≤100 figure is the brief's stated bound, not this plan's preference — a false sentence left in place by arithmetic is listed, not forgotten.

## Implementation Phases

### Phase 0 — Guard the hash-bound inputs (before any edit)

One invariant, checked before the first edit and again as AC1 after the last: `source tests/scripts/lib/git-data-birth-readiness-gate.sh && git_data_rung2_rehearsal_gate apps/web-platform/infra/cloud-init-git-data.yml apps/web-platform/infra/git-data-rung2-boot-evidence.env` prints `RELEASED … sha256 5c50797be839…`, and none of the 13 roster paths (`git_data_rung2_bound_files …`) nor the evidence file appears in `git diff --name-only`.

### Phase 1 — Tier A, workflow behaviour first (item 15)

File: `.github/workflows/apply-web-platform-infra.yml`, job `git_data_host_create`.

1. Add `id: apply` to the step `- name: Terraform apply (git-data birth)` (the only step in the job carrying an `id:` today is `plan`; no collision).
2. Change the poll step's predicate from `if: always()` to:

   ```yaml
   if: ${{ !cancelled() && (steps.apply.outcome == 'success' || steps.apply.outcome == 'failure') }}
   ```

   A bare `steps.apply.outcome == 'failure'` would never fire (the implicit `success()` is false after a failed apply), so a status function is required; `!cancelled()` rather than `always()` because `always()` would also spend the 10-minute poll on a cancelled run — the same waste class item 15 removes. The outcome clause excludes `skipped` (the gate refused before apply — run 34822248580's shape). `failure` is retained on purpose: the step's own comment records that a partial birth is when the boot evidence matters most. The `${{ }}` wrapper is required for an expression starting with `!`.
3. Rewrite the two comment lines above the step that currently read "`if: always()` so a FAILED apply still reports what the host did or did not say — a partial birth is exactly when the boot evidence matters most." to state the new predicate in prose (not the literal `if:` line — AC6 pins that line by exact match and must read exactly 1): runs after a green or a failed apply, never after a skipped one (measured on run 34822248580: a refused plan left this step polling for its full 10-minute budget and printing "the apply may be green" over a run where no apply happened).
4. Thread the measured outcome into the step's text: add `APPLY_OUTCOME: ${{ steps.apply.outcome }}` to the poll step's `env:`; REPLACE the clause "The apply may be green while the host booted DARK — that is precisely the state this interlock exists to catch." in the "No stage:boot_complete …" message with one that reads the variable and cannot contradict it, e.g. "The apply step's outcome was ${APPLY_OUTCOME}: on success this is the green-apply/dark-host state this interlock exists to catch; on failure it is a partial birth whose host never came up." Append `(apply outcome: ${APPLY_OUTCOME})` to the success-path line "boot signal received: …". The interesting combination is a FAILED apply whose host still emitted `boot_complete` (partial birth, host up): today that prints an unqualified success line. Also add `APPLY_OUTCOME` to the `Dispatch summary` step's `env:` and one `echo` line reporting it (the summary currently reads `job.status` only). Keep the rest of each sentence verbatim; the runbook's partial-birth decision tree still applies.
5. `knowledge-base/engineering/operations/runbooks/git-data-birth.md`, section "After the birth — verify the host actually booted (#6982)": extend the sentence "The dispatch's own post-apply step polls for the boot signal and FAILS the job if it does not arrive…" with "; the poll runs only after the apply step actually ran (green or failed) — a run refused at the gate skips it, so a skipped poll is not a verdict on the host". Keep the fragment `not a verdict on the host` on ONE physical line (the runbook hard-wraps at ~90 columns; AC9 pins that fragment).
6. Verify: `actionlint -ignore 'SC2140' .github/workflows/apply-web-platform-infra.yml` exits 0 (`SC2140` is a pre-existing shellcheck warning at an unrelated `run:` block near line 2246 that actionlint reports today; the un-ignored form exits 1 on the baseline and is not a signal about this diff), then `bun test plugins/soleur/test/terraform-target-parity.test.ts` (194/0) and `bash tests/scripts/test-web-host-birth-gate.sh` (34/0).

### Phase 2 — Tier A, operator-visible text (items 7, 8)

**Item 7 — `apply-web-platform-infra.yml`.**

1. In the `apply_target` input `description`, replace the two lines "What holds the route now is the runbook banner and the / environment approval -- and that approval reports prevent_self_review:false" with wording that names only the environment approval as the remaining hold, notes the banner was cleared 2026-09-13 (PR #8128), and keeps the `prevent_self_review:false` sentence intact.
2. In the `git_data_host_create` job header comment, replace the sentence "The banner stays up until #7025 lands the evidence." with "The evidence landed (PR #8126, run 34768256297) and the banner was cleared (PR #8128)."

**Item 8 — `tests/scripts/lib/git-data-birth-readiness-gate.sh`.**

3. Sentinel gate HOLD heredoc: replace "THEN clear the DO-NOT-DISPATCH banner at the top of / knowledge-base/engineering/operations/runbooks/git-data-birth.md." with a two-line instruction that keeps the path on its own line, e.g. "THEN re-read the release record at the top of / knowledge-base/engineering/operations/runbooks/git-data-birth.md (the DO-NOT-DISPATCH banner it replaced was cleared 2026-09-13)." The pinned substrings `#6982` (already elsewhere in the message) and `git-data-birth.md` remain.
4. Rung-2 gate no-evidence HOLD heredoc: replace "That was / the only MECHANICAL hold on this route. What still holds it is the DO-NOT-DISPATCH banner in / knowledge-base/engineering/operations/runbooks/git-data-birth.md — prose, in a different / file from this button. This gate exists so that hold is mechanical too." with wording that says this gate IS the mechanical hold now, and that `git-data-birth.md` carries the release record and the dispatch procedure. Keep the path.
5. `tests/scripts/test-git-data-birth-readiness-gate.sh`: rename `check "the HOLD names the runbook banner to clear" 1 "git-data-birth.md" "$TMP/no-emitter.yml"` to a label matching the new text (the substring pin stays `git-data-birth.md`; the helper is `check <name> <want_rc> <needle> <file>` and the sibling pins `#6982`, `sentry_dsn`, `ADR-149`, `laptop` on the same fixture must keep matching — keep the "Do NOT work around this by applying from a laptop" paragraph verbatim). Do NOT add a pin on the fresh wording (a positive pin on prose breaks on every future reword and serves no property — AC4 asserts the old phrase is gone and the path pin asserts the runbook is still named). Add exactly one stable pin: `r2check … 1 "git-data-birth.md" "$R2/ci.yml" "$R2/absent.env"` beside the existing `r2check "absent evidence => HOLD" 1 "no rung-2 boot evidence" …`, so the reworded rung-2 HOLD is pinned to the runbook PATH the same way the sentinel HOLD already is.
6. Verify: `bash tests/scripts/test-git-data-birth-readiness-gate.sh` → 150 passed / 0 failed; `bash tests/scripts/test-git-data-rung2-evidence-capture.sh` (the capture script sources the readiness lib) stays at 80/0. (`test-git-data-host-birth-gate.sh` sources `git-data-host-birth-gate.sh`, a different lib, and cannot regress from item 8.)

### Phase 3 — Tier A, evidence provenance and ledger (items 1, 12, 18)

**Item 1 — `scripts/followthroughs/git-data-rung2-evidence-capture.sh`.** In the evidence writer block, directly after the ARTIFACT 1 comment and before its `# QUERY:` line, add:

```bash
_bs_s3="${BS_TABLE_S3:-}"
[[ -z "$_bs_s3" && "$BS_TABLE" == *_logs ]] && _bs_s3="${BS_TABLE%_logs}_s3"
printf '# TABLE: BS_TABLE=%s BS_TABLE_S3=%s\n' "$BS_TABLE" "$_bs_s3"
```

(the `_bs_s3` assignment sits just above the `{ … } > "$OUT"` writer block, not inside it). The two-value form is the brief's (item 1 verbatim). The fallback reproduces `betterstack-query.sh`'s derivation INCLUDING its `_logs` guard (`if [[ "$BS_TABLE" == *_logs ]]; then BS_TABLE_S3="${BS_TABLE%_logs}_s3"; else BS_TABLE_S3=""; fi`) — a bare `${BS_TABLE%_logs}_s3` would record an `_s3` table that was never queried for a non-`_logs` table. It is a duplicated derivation, accepted because the evidence file must record the S3 table a re-run will hit without re-deriving it, and noted on the #8010 comment as the reason a future `betterstack-query.sh` change must touch this line too. `tests/scripts/test-git-data-rung2-evidence-capture.sh`: add one pin beside the existing "evidence records the queries that produced it" check that asserts the VALUE, not presence — `grep -q "^# TABLE: BS_TABLE=${BS_GIT_DATA_TABLE} BS_TABLE_S3=${BS_GIT_DATA_TABLE_S3}$" "$OUT"` with both names sourced from `scripts/lib/betterstack-sources.sh` (which declares `BS_GIT_DATA_TABLE` and `BS_GIT_DATA_TABLE_S3`) the way the capture script itself resolves them — so the pin also catches a drift between the derivation and the declared S3 name (a presence-only pin would not serve P4).

**Item 12 — `scripts/encryption-posture-ledger.json`, store `hcloud_volume.rehearsal_luks`.**

- `live_verification`: `"available"` (bare — the only form `LIVE_VERIFICATION_RE` accepts).
- `evidence`: append one sentence carrying the pointer: "Observed twice: rung-2 rehearsal run 34768256297 (2026-09-13, evidence PR #8126) and the production birth (`boot_complete` 2026-09-14T15:27:24Z, `luks_mounted=yes`, Better Stack table t520508_soleur_git_data_prd_logs, host_name soleur-git-data, run 34861860722) — the same rendered template's luksOpen stage on real hardware."
- `live_coverage_floor` stays `1` (see Decisions).
- Verify: `python3 scripts/lint-encryption-posture.py --repo-sweep` → PASS, and `bash scripts/lint-encryption-posture.test.sh` stays green.

**Item 18 (new) — `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`.** Rewrite the comment "Targeted at the TERRAFORM DECLARATION rather than at a live Doppler config, / because the git-data host has never been born and `prd_git_data` holds nothing to read." to give the reason that survives the birth: the suite is hermetic and must not read a live Doppler config. Run `bash apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` to confirm it stays green (comment-only). This is the one file under `apps/web-platform/**` in the PR and is what makes the merge fire the release deploy arm.

### Phase 4 — Tier B, then C, budget-gated prose

Take all of Tier B. Then measure once: `git diff --shortstat origin/main...HEAD -- . ':!knowledge-base/project/plans' ':!knowledge-base/project/specs' ':!knowledge-base/project/learnings'`; take Tier C items in order 3 → 4 → 2 only while insertions + deletions stay ≤ 100.

**Item 6.** `apply-web-platform-infra.yml`: the job-header lines "What holds the route today is the runbook's DO-NOT-DISPATCH banner / and the environment approval; the banner may be the only prose hold, and…", the "(2) The RUNG-2 REHEARSAL interlock HOLDS." line, the "which left the birth held by the runbook's DO-NOT-DISPATCH banner / alone" clause, the option-enum comment "Dispatch is still held by the runbook's DO-NOT-DISPATCH banner (rung-2 rehearsal / evidence, #7025)", and the second-interlock comment "only by the DO-NOT-DISPATCH banner in a runbook, i.e. by prose" — each restated in the past tense as history ("was held by…", "…HELD until the evidence landed"). `git-data-rung2-rehearsal.yml`: the five FAIL-path summary lines share the sentence "**#7025 stays open and the DO-NOT-DISPATCH banner stays up.**" — replace all five with "**A FAIL here releases nothing: the committed evidence keeps binding the last template that PASSED.**" (one `sed` over the identical fragment).

**Item 9.** `git-data-rung2-rehearsal.yml` header line "The DO-NOT-DISPATCH banner in git-data-birth.md stays up." → "The banner in git-data-birth.md was cleared 2026-09-13 once evidence for the current template merged; a later template edit re-HOLDs the gate, not the banner."

**Item 10.** `git-data-rung2-rehearsal.md` L6 "The hold lives in `git-data-birth.md` and in `git_data_rung2_rehearsal_gate`" → "The mechanical hold is `git_data_rung2_rehearsal_gate`; `git-data-birth.md` carries the release record".

**Item 11.** ADR-152 §Scope: "the DO-NOT-DISPATCH banner stays up" → "the DO-NOT-DISPATCH banner stayed up until the rung-2 evidence merged (cleared 2026-09-13, PR #8128)". An amendment sentence, not a rewrite of the decision.

**Item 13.** `infra-validation.yml` rung-2 step comment "Until #7025's rehearsal has / actually run, "no evidence" is the DESIGNED state" → past tense ("Before the first rehearsal ran…"); the step's behaviour is unchanged.

**Tier C items 3, 4, 2** as described in the tier table.

### Phase 5 — Verification

1. Run AC1 (the Phase 0 invariant, post-edit).
2. Suites: `bun test plugins/soleur/test/terraform-target-parity.test.ts` (194/0); `bash tests/scripts/test-git-data-birth-readiness-gate.sh`; `bash tests/scripts/test-git-data-rung2-evidence-capture.sh`; `bash tests/scripts/test-web-host-birth-gate.sh`; `bash tests/scripts/test-git-data-host-birth-gate.sh`; `python3 scripts/lint-encryption-posture.py --repo-sweep`; `bash scripts/lint-encryption-posture.test.sh`; if `infra-validation.yml` was touched: `bash plugins/soleur/test/infra-validation-detect.test.sh` and `bash .github/scripts/test/run-all.sh`. No new `*.sh` is added under `tests/` or `scripts/`, so the fixture-relative ratchets are not triggered (state this in the PR body).
3. Budget: AC2.
4. Rebase check `git merge-tree --write-tree origin/main HEAD` before review and again before `gh pr ready` (a ship step the brief mandates; not an AC).

### Phase 6 — Ship-phase deliverables (executed by `/soleur:ship`, recorded here so nothing is left implicit)

- PR body: `Ref #8010` (never `Closes #8010`); label `semver:patch`; squash merge.
- Comment on #8010 listing: taken (7, 8, 15, 1, 12, 18 + whichever of 6/9/10/11/13/3/4/2 landed) and not taken (5, 14, 16, 17, variables.tf verified accurate, and any Tier B/C item cut by the budget) with the one-line reason each.
- Phase 7 / postmerge — the redeploy is a first-class deliverable, not a side effect: (i) `gh run list --workflow web-platform-release.yml --commit <merge-sha> --json databaseId,status,conclusion` — a run must exist for the merge SHA (fired by the `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` path); (ii) `gh run view <id> --json jobs` — the `deploy` job concluded `success`; (iii) `curl -s https://app.soleur.ai/health | jq -r .build_sha` equals the merge SHA — or a descendant of it on `main` that a later merge deployed (`git merge-base --is-ancestor <merge-sha> <build_sha>`), which still proves the container was rebuilt after the keys were minted. The ship report states explicitly that the redeploy landed and why it was required (the container's env predated the three `GIT_*_SSH_PRIVATE_KEY` secrets minted at the birth). ONLY if no release run exists for the merge SHA after CI completes (path filter tightened, `check_changed` read false): dispatch `gh workflow run web-platform-release.yml -f bump_type=patch` and verify (ii)+(iii) on that run. Never dispatch when a run for the merge SHA already published: `reusable-release.yml`'s idempotency step keys on the NEXT computed tag, so a second dispatch publishes an extra patch release rather than no-op'ing. The merge also fires `apply-web-platform-infra.yml` on push (the workflow file and an `apps/web-platform/infra/` path changed) — expected outcome is a green no-change apply; a non-green run there is a ship-tail defect, not part of this sweep.

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml` — items 7, 15 (Tier A); 6 (Tier B)
- `tests/scripts/lib/git-data-birth-readiness-gate.sh` — item 8 (Tier A); 3 (Tier C)
- `tests/scripts/test-git-data-birth-readiness-gate.sh` — item 8 pin (Tier A)
- `scripts/followthroughs/git-data-rung2-evidence-capture.sh` — item 1 (Tier A); 3, 4 (Tier C)
- `tests/scripts/test-git-data-rung2-evidence-capture.sh` — item 1 pin (Tier A)
- `scripts/encryption-posture-ledger.json` — item 12 (Tier A)
- `knowledge-base/engineering/operations/runbooks/git-data-birth.md` — item 15 consistency (Tier A)
- `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` — item 18 (Tier A)
- `.github/workflows/git-data-rung2-rehearsal.yml` — items 6, 9 (Tier B)
- `knowledge-base/engineering/operations/runbooks/git-data-rung2-rehearsal.md` — item 10 (Tier B); 2, 3 (Tier C)
- `knowledge-base/engineering/architecture/decisions/ADR-152-strip-rationale-comments-from-git-data-injected-scripts-at-render-time.md` — item 11 (Tier B)
- `.github/workflows/infra-validation.yml` — item 13 (Tier B)

## Files to Create

None (no new test files, no new scripts — this keeps the P1b fixture ratchets out of scope).

## Files that MUST NOT change

`apps/web-platform/infra/cloud-init-git-data.yml`; `apps/web-platform/infra/modules/git-data-userdata/{main,outputs,variables}.tf`; `apps/web-platform/infra/git-data-{bootstrap,gc,pre-receive-placeholder,provision,remove,transport-wrapper}.sh`, `git-data-gc.service`, `git-data-gc-failure.service`, `git-data-gc.timer`; `apps/web-platform/infra/git-data-rung2-boot-evidence.env`; `apps/web-platform/infra/variables.tf` (verified accurate).

## Decisions

1. **Poll predicate keeps `failure`.** `always() && (steps.apply.outcome == 'success' || steps.apply.outcome == 'failure')` rather than `== 'success'` alone: the item-15 defect is the skipped apply; dropping the failed-apply poll would silently remove a designed partial-birth safeguard the step's own comment argues for. A future decision to drop it needs its own row, not a side-effect here.
2. **`available` is bare; the pointer lives in `evidence`.** Forced by `LIVE_VERIFICATION_RE`. The `git_data.baked_credentials_on_host` row's "the git-data host has never been born" and the production `hcloud_volume.git_data_luks` row's `unavailable:no per-volume host posture probe…` are NOT flipped: the first is a plaintext-exception row whose `reevaluate_when` ("BEFORE the git-data host is born") is now a posture decision for #7772, and the second asks for a recurring probe, which a once-per-boot `boot_complete` literal is not. Both are named on the #8010 comment.
3. **`live_coverage_floor` stays 1.** Raising it to 2 would pin coverage to a throwaway per-rehearsal volume; the floor's own docstring says it guards against zeroing coverage, not against re-ledgering one row. Left for the ledger's owner (#6897).
4. **Item 18 is the deploy-arm trigger; the redeploy is verified as a deliverable, not assumed from the path filter.** Item 18 is a genuine post-birth stale comment of the sweep's class; taking it makes the release arm fire without contriving a change. Because a directory-prefix pathspec is a coincidental trigger (a future `*.test.sh` exclusion would silently drop it), ship Phase 7 verifies the `deploy` job by merge SHA and dispatches the release only when no run exists for that SHA — a dispatch after a published run would mint an extra patch release (the idempotency step keys on the next tag).
5. **No issues filed.** Every deferred item already lives on #8010; the closing comment there is the tracking record (net-issue-flow NET = 0).

## User-Brand Impact

**If this lands broken, the user experiences:** nothing today — every edited surface is a comment, a dispatch-dialog description, a gate message that fires only on a future template edit, a ledger record marked `not-publicly-claimed`, or a poll predicate on a dispatch-only route that cannot re-fire while the host exists (a zero-server-create plan is refused by the birth gate). The one behavioural change (the poll predicate) is pinned by AC6 and a mutation row.

**If this leaks, the user's [data / workflow / money] is exposed via:** no vector — no secret, credential, or user data is read or written; the `# TABLE:` line records a table NAME, not a credential.

**Brand-survival threshold:** none

- threshold: none, reason: the diff touches sensitive-path files (`apply-web-platform-infra.yml`, `apps/web-platform/infra/`) but changes no runtime data path; its only behavioural change narrows when a verification step runs on a route that is inert while the host exists, and every hash-bound input the birth depends on is asserted byte-identical (AC1).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC0. `git fetch origin main` immediately before AC1/AC2 (`origin/main` moves several times an hour; a stale ref makes both counts measure the machine, not the diff).
- [ ] AC1. `source tests/scripts/lib/git-data-birth-readiness-gate.sh && git_data_rung2_rehearsal_gate apps/web-platform/infra/cloud-init-git-data.yml apps/web-platform/infra/git-data-rung2-boot-evidence.env` prints `RELEASED` with sha256 `5c50797be8392fe551a940ae04555c52a3f4409cf249ed11bb1280fec783d5b1` after all edits, and `git diff --name-only origin/main...HEAD | grep -cE 'cloud-init-git-data\.yml|modules/git-data-userdata/|git-data-rung2-boot-evidence\.env|infra/git-data-(bootstrap|gc|gc-failure|pre-receive-placeholder|provision|remove|transport-wrapper)\.(sh|service|timer)$'` prints `0`.
- [ ] AC2. `git diff --shortstat origin/main...HEAD -- . ':!knowledge-base/project/plans' ':!knowledge-base/project/specs' ':!knowledge-base/project/learnings'` reports insertions + deletions ≤ 100.
- [ ] AC3. `grep -c "What holds the route now is the runbook banner" .github/workflows/apply-web-platform-infra.yml` prints `0`, and `grep -c "The banner stays up until #7025" .github/workflows/apply-web-platform-infra.yml` prints `0` (item 7).
- [ ] AC4. `grep -c "THEN clear the DO-NOT-DISPATCH banner" tests/scripts/lib/git-data-birth-readiness-gate.sh` prints `0` and `grep -c "What still holds it is the DO-NOT-DISPATCH banner" tests/scripts/lib/git-data-birth-readiness-gate.sh` prints `0`; that both HOLDs still name the runbook is asserted by the suite pins in AC5, not by a file-wide count (the lib carries the path in two header comments, so a count is vacuous) (item 8).
- [ ] AC5. `bash tests/scripts/test-git-data-birth-readiness-gate.sh` ends `=== N passed, 0 failed ===` with N ≥ 150 (one new path pin on the rung-2 no-evidence HOLD).
- [ ] AC6. In `.github/workflows/apply-web-platform-infra.yml`, the `git_data_host_create` job block (`awk '/^  git_data_host_create:/{f=1} /^  ci_ssh_token_replace:/{f=0} f'`) contains exactly one `id: apply` line, and `grep -cF "if: ${{ !cancelled() && (steps.apply.outcome == 'success' || steps.apply.outcome == 'failure') }}" .github/workflows/apply-web-platform-infra.yml` prints `1`; the same job block contains `APPLY_OUTCOME: ${{ steps.apply.outcome }}` twice (poll step + Dispatch summary) (item 15).
- [ ] AC8. `bun test plugins/soleur/test/terraform-target-parity.test.ts` → 194 pass / 0 fail; `bash tests/scripts/test-web-host-birth-gate.sh` → 34 passed / 0 failed; `actionlint -ignore 'SC2140' .github/workflows/apply-web-platform-infra.yml` exits 0 (the unfiltered form exits 1 on the pre-edit baseline because of a pre-existing SC2140 at an unrelated step, so it cannot be the AC).
- [ ] AC9. `grep -c "not a verdict on the host" knowledge-base/engineering/operations/runbooks/git-data-birth.md` prints `1` (item 15 runbook consistency; short fragment so hard-wrapping cannot split it).
- [ ] AC10. `bash tests/scripts/test-git-data-rung2-evidence-capture.sh` ends `=== N passed, 0 failed ===` with N ≥ 81, the new case asserting the evidence's `# TABLE:` line carries the git-data table and its `_s3` sibling by value (item 1).
- [ ] AC11. `jq -r '.stores[] | select(.store=="hcloud_volume.rehearsal_luks") | .at_rest.live_verification' scripts/encryption-posture-ledger.json` prints `available`; `jq -r '.stores[] | select(.store=="hcloud_volume.rehearsal_luks") | .at_rest.evidence' scripts/encryption-posture-ledger.json | grep -c '34768256297'` prints `1`; `python3 scripts/lint-encryption-posture.py --repo-sweep` prints `… 0 failing checks -> PASS`; `bash scripts/lint-encryption-posture.test.sh` is green (item 12).
- [ ] AC12. `grep -c "has never been born" apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` prints `0` and `bash apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` is green (item 18).
- [ ] AC14. For every Tier B/C item taken, the phrase it replaces is absent from its file (`grep -c` = 0 for: "DO-NOT-DISPATCH banner stays up" in `git-data-rung2-rehearsal.yml` if item 6 was taken; "in git-data-birth.md stays up" in the same file's header line if item 9; "The hold lives in" in `git-data-rung2-rehearsal.md` if item 10; "stays up, and #6982 additionally" in ADR-152 if item 11 (the phrase is hard-wrapped across two lines; this fragment sits on one); "Until #7025's rehearsal has" in `infra-validation.yml` if item 13). Items not taken are listed on the #8010 comment.
- [ ] AC16. PR body contains `Ref #8010` and does not contain `Closes #8010`; label `semver:patch` present.

### Post-merge (ship Phase 7 / postmerge — automated)

- [ ] AC17. The `Web Platform Release` run for the merge commit has `deploy` job conclusion `success` (`gh run list --workflow web-platform-release.yml --commit <merge-sha> --json databaseId` then `gh run view <id> --json jobs`), and `curl -s https://app.soleur.ai/health | jq -r .build_sha` equals the merge commit SHA or a `main` descendant of it deployed later. The ship report states explicitly that the redeploy landed. If the run did not fire, `gh workflow run web-platform-release.yml -f bump_type=patch` is dispatched and the same two facts are verified on that run.
- [ ] AC18. The merge-triggered `apply-web-platform-infra.yml` push run concluded `success` (a no-change apply is the expected shape).
- [ ] AC19. #8010 carries a comment naming taken and not-taken sweep items; #8010 remains OPEN.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. The one record that looks compliance-adjacent (item 12, the encryption-posture ledger) changes an internal `live_verification` observation on a row whose `disclosed_as` stays `not-publicly-claimed`; no public disclosure, legal document, price, or customer-facing surface changes.

## Open Code-Review Overlap

- #7942 (Two mutation batteries in plugins/soleur/test/ are named *.mutation.sh and run in no gate) names `infra-validation.yml` — **Acknowledge**: a different concern (test-runner registration); this PR edits one comment in that file's rung-2 step, behaviour unchanged.
- #7098 (audit the 56 `run:` bodies whose `set` omits -e) names `git-data-rung2-rehearsal.test.sh` — **Acknowledge**: this PR changes one comment in that file; the `set -e` audit is untouched.

## Observability

```yaml
liveness_signal:
  what: the git_data_host_create poll step's own ::error:: / ::warning:: annotations and its "boot signal received" line; on a refused plan the step is now SKIPPED (visible as a skipped step in the run, not as a 10-minute poll)
  cadence: per dispatch of apply_target=git-data-host-create (dispatch-only route; inert while hcloud_server.git_data exists)
  alert_target: the run's annotations API + the existing Sentry git-data fatal rules (issue-alerts.tf) for a dark boot — unchanged by this PR
  configured_in: .github/workflows/apply-web-platform-infra.yml (git_data_host_create job)
error_reporting:
  destination: GitHub Actions annotations (::error::) on the poll step; Sentry WEB-PLATFORM git-data fatal rule for the host side (unchanged)
  fail_loud: yes — the poll still exits 1 on no signal / unreadable signal after a real apply; a skipped apply no longer produces a misleading "the apply may be green" error
failure_modes:
  - mode: poll predicate wrong (poll skipped after a successful apply)
    detection: AC6/AC7 grep pins the exact predicate; actionlint validates the expression
    alert_route: CI red on the PR (AC8); post-merge, the next real dispatch shows a skipped poll step
  - mode: HOLD message reworded so a suite pin no longer matches
    detection: tests/scripts/test-git-data-birth-readiness-gate.sh (AC5)
    alert_route: CI red on the PR
  - mode: ledger flip rejected by the lint (wrong live_verification form)
    detection: python3 scripts/lint-encryption-posture.py --repo-sweep (AC11)
    alert_route: CI red on the PR (infra-validation deploy-script-tests)
  - mode: hash-bound input accidentally edited (rung-2 gate re-HOLDs)
    detection: AC1 gate command + name-only diff grep
    alert_route: infra-validation "Rung-2 evidence freshness" step goes red on the PR
logs:
  where: GitHub Actions run logs for apply-web-platform-infra.yml; Better Stack table t520508_soleur_git_data_prd_logs for the host's boot_complete row (read-only, unchanged)
  retention: GitHub default (90 days); Better Stack per-source retention (unchanged)
discoverability_test:
  command: grep -cF "if: ${{ !cancelled() && (steps.apply.outcome == 'success' || steps.apply.outcome == 'failure') }}" .github/workflows/apply-web-platform-infra.yml
  expected_output: "1"
```

## Encryption Posture

No new store and no new connection. Item 12 re-ledgers an existing `guest-luks-volume` row (`hcloud_volume.rehearsal_luks`) from `unavailable:<reason>` to `available` on the strength of two observed `luks_mounted=yes` boot rows; `mechanism`, `defends_against`, `does_not_defend`, `disclosed_as` and `device_binding` are unchanged, and `lint-encryption-posture.py --repo-sweep` is the AC.

## Test Scenarios

1. Predicate mutation — revert the poll `if:` to `always()`, or swap `!cancelled()` for `always()`: the AC6 `grep -cF` reads 0 → red. Restore → 1.
2. Predicate mutation — drop `id: apply`: `actionlint -ignore 'SC2140'` reports the `steps.apply` reference as an undefined step id → non-zero (baseline with the ignore is 0, so the mutation is distinguishable).
3. HOLD mutation — remove `git-data-birth.md` from the sentinel HOLD: the readiness suite's `check … 1 "git-data-birth.md"` fails → red.
4. HOLD mutation — drop `git-data-birth.md` from the rung-2 no-evidence HOLD: the new `r2check` path pin fails → red (proves the pin was added, not just relabelled).
5. Writer mutation — delete the `# TABLE:` printf, or print `BS_TABLE_S3` from the wrong derivation (`${BS_TABLE}_s3`): the new value pin fails → red.
6. Ledger mutation — write `available:run 34768256297`: `lint-encryption-posture.py` fails `LIVE_VERIFICATION_RE` → red (this is the brief's original wording and the reason for the bare form).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6. It is filled above.
- `live_verification: "available:<anything>"` is a schema violation, not a stricter form — the brief's wording would have failed the lint. Bare `available` + pointer in `evidence` is the only valid shape.
- `git diff --shortstat` counts a modified line twice. The budget is deliberately on that metric; Tier B/C selection is measured, not estimated.
- The rehearsal workflow's five FAIL summaries are `echo … >> "$GITHUB_STEP_SUMMARY"` lines inside `run:` bodies; the replacement sentence must keep the `\`` escapes and the trailing `See \`${RUNBOOK}\`."` intact.
- `steps.apply.outcome` for a step whose `if:` was never evaluated because an earlier step failed is `skipped`; for a cancelled run it is `cancelled`. Both are excluded by the positive enumeration.
- Editing `.github/workflows/apply-web-platform-infra.yml` and `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` puts the merge on the `apply-web-platform-infra.yml` push trigger; a green no-change apply run is the expected post-merge shape (AC18).
- CI ships gawk, this workstation mawk: any awk in the ACs uses bracket expressions or plain regexes only (the AC6 awk does).

## Plan Review — findings applied (2026-09-14)

Eng panel (DHH, Kieran, code-simplicity) plus a scoped CTO advisor consult on item 15 and the redeploy path. Mechanical findings were auto-applied; the two direction challenges were persisted to `knowledge-base/project/specs/feat-one-shot-8010-post-birth-sweep/decision-challenges.md` for ship Phase 6.

- Applied (mechanical): `!cancelled()` replaces `always()` in the poll predicate (a bare outcome test never fires after a failed apply; `always()` would also poll after a cancel); `APPLY_OUTCOME` threaded into the success line and the Dispatch summary, and the "may be green" clause rewritten so it cannot contradict the printed outcome; tier machinery collapsed to "A+B always, one measurement, C in order 3 → 4 → 2 while ≤ 100"; AC6 pins the exact predicate line (`grep -cF … = 1`) instead of an occurrence count; AC7/AC13/AC15 and the "no issue filed" clause removed; the fresh-wording test pin dropped in favour of one stable path pin (`r2check … "git-data-birth.md" … absent.env`); the `# TABLE:` test pin asserts the VALUE against `BS_GIT_DATA_TABLE`/`BS_GIT_DATA_TABLE_S3`; the S3 fallback reproduces `betterstack-query.sh`'s `_logs` guard; `actionlint` invoked with `-ignore 'SC2140'` (pre-existing baseline warning); AC14 needles fixed for hard-wrapping (ADR-152) and regex-dot (`stays up.`); AC9 pins a one-line fragment; AC4's vacuous file-wide count removed; the false "host-birth-gate suite sources the same lib" claim corrected; `git fetch origin main` precedes the `origin/main`-relative ACs; AC17 accepts a deployed `main` descendant of the merge SHA.
- Persisted as User-Challenges (not applied): UC-1 the ≤100-line bound vs. leaving known-false prose (DHH); UC-2 organic path-trigger (item 18) vs. explicit release dispatch as the primary redeploy mechanism (CTO advisor, DHH, code-simplicity) — kept organic-with-verified-fallback because a dispatch after a published run mints an extra patch release (idempotency keys on the next tag).
