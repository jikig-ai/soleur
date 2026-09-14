# Tasks — feat-one-shot-8010-post-birth-sweep

Derived from `knowledge-base/project/plans/2026-09-14-chore-git-data-post-birth-sweep-plan.md`. Ref #8010 (never `Closes`).

## Phase 0 — Guard (before the first edit)

- [ ] 0.1 Record the rung-2 gate verdict: `source tests/scripts/lib/git-data-birth-readiness-gate.sh && git_data_rung2_rehearsal_gate apps/web-platform/infra/cloud-init-git-data.yml apps/web-platform/infra/git-data-rung2-boot-evidence.env` → `RELEASED … sha256 5c50797be839…`.
- [ ] 0.2 Record the 13-path roster (`git_data_rung2_bound_files …`); none of it, nor the evidence file, may appear in any later `git diff --name-only`.

## Phase 1 — Item 15 (workflow behaviour)

- [ ] 1.1 `.github/workflows/apply-web-platform-infra.yml`, job `git_data_host_create`: add `id: apply` to `- name: Terraform apply (git-data birth)`.
- [ ] 1.2 Poll step `if:` → `${{ !cancelled() && (steps.apply.outcome == 'success' || steps.apply.outcome == 'failure') }}`; rewrite the two `if: always()` rationale comment lines above it.
- [ ] 1.3 Add `APPLY_OUTCOME: ${{ steps.apply.outcome }}` to the poll step env; replace the "The apply may be green while the host booted DARK" clause with the outcome-reading sentence; append `(apply outcome: ${APPLY_OUTCOME})` to the "boot signal received" line.
- [ ] 1.4 Add `APPLY_OUTCOME` env + one echo line to the `Dispatch summary` step.
- [ ] 1.5 `knowledge-base/engineering/operations/runbooks/git-data-birth.md` "After the birth" section: extend the poll sentence; keep the fragment `not a verdict on the host` on one physical line (AC9 pins it).
- [ ] 1.6 `actionlint -ignore 'SC2140' .github/workflows/apply-web-platform-infra.yml` exits 0 (SC2140 is a pre-existing baseline warning); `bun test plugins/soleur/test/terraform-target-parity.test.ts` (194/0); `bash tests/scripts/test-web-host-birth-gate.sh` (34/0).

## Phase 2 — Items 7 and 8 (operator-visible text)

- [ ] 2.1 `apply_target` input description: name only the environment approval as the hold; note the banner was cleared 2026-09-13 (PR #8128); keep the `prevent_self_review:false` sentence.
- [ ] 2.2 Job header comment: "The banner stays up until #7025 lands the evidence." → evidence landed (PR #8126, run 34768256297), banner cleared (PR #8128).
- [ ] 2.3 `tests/scripts/lib/git-data-birth-readiness-gate.sh` sentinel HOLD: reword "THEN clear the DO-NOT-DISPATCH banner…" keeping `git-data-birth.md` on its own line and `#6982`, `sentry_dsn`, `ADR-149`, `laptop` intact.
- [ ] 2.4 Rung-2 no-evidence HOLD: reword "What still holds it is the DO-NOT-DISPATCH banner…" (this gate IS the mechanical hold; the runbook carries the release record); keep the path.
- [ ] 2.5 `tests/scripts/test-git-data-birth-readiness-gate.sh`: rename the "names the runbook banner to clear" check label (needle stays `git-data-birth.md`); add one `r2check … 1 "git-data-birth.md" "$R2/ci.yml" "$R2/absent.env"`. No pin on fresh wording.
- [ ] 2.6 `bash tests/scripts/test-git-data-birth-readiness-gate.sh` → 150/0; `bash tests/scripts/test-git-data-rung2-evidence-capture.sh` still 80/0 (it sources the readiness lib).

## Phase 3 — Items 1, 12, 18

- [ ] 3.1 `scripts/followthroughs/git-data-rung2-evidence-capture.sh`: derive `_bs_s3` above the writer block (`${BS_TABLE_S3:-}`, else `${BS_TABLE%_logs}_s3` only when `BS_TABLE` ends in `_logs` — betterstack-query.sh's guard); add `printf '# TABLE: BS_TABLE=%s BS_TABLE_S3=%s\n' "$BS_TABLE" "$_bs_s3"` before the ARTIFACT 1 `# QUERY:` line.
- [ ] 3.2 `tests/scripts/test-git-data-rung2-evidence-capture.sh`: add the value pin `grep -q "^# TABLE: BS_TABLE=${BS_GIT_DATA_TABLE} BS_TABLE_S3=${BS_GIT_DATA_TABLE_S3}$" "$OUT"` (source `scripts/lib/betterstack-sources.sh`); suite → ≥ 81/0.
- [ ] 3.3 `scripts/encryption-posture-ledger.json` `hcloud_volume.rehearsal_luks`: `live_verification` → `"available"` (bare); append the evidence pointer sentence to `evidence`; floor stays 1.
- [ ] 3.4 `python3 scripts/lint-encryption-posture.py --repo-sweep` → PASS; `bash scripts/lint-encryption-posture.test.sh` green.
- [ ] 3.5 `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`: rewrite the "has never been born" comment (hermetic-suite reason); `bash apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` green.

## Phase 4 — Tier B (all) then Tier C (budget-gated)

- [ ] 4.1 Item 6: past-tense the five `apply-web-platform-infra.yml` banner comments; replace the five identical "#7025 stays open and the DO-NOT-DISPATCH banner stays up." fragments in `.github/workflows/git-data-rung2-rehearsal.yml`.
- [ ] 4.2 Item 9: rehearsal workflow header line.
- [ ] 4.3 Item 10: `git-data-rung2-rehearsal.md` "The hold lives in…" sentence.
- [ ] 4.4 Item 11: ADR-152 §Scope amendment sentence.
- [ ] 4.5 Item 13: `infra-validation.yml` rung-2 step comment (past tense); run `bash plugins/soleur/test/infra-validation-detect.test.sh` and `bash .github/scripts/test/run-all.sh`.
- [ ] 4.6 Measure once: `git diff --shortstat origin/main...HEAD -- . ':!knowledge-base/project/plans' ':!knowledge-base/project/specs' ':!knowledge-base/project/learnings'`; take items 3 → 4 → 2 while insertions + deletions ≤ 100; list any not taken for the #8010 comment.

## Phase 5 — Verification

- [ ] 5.1 `git fetch origin main`; AC1 (gate RELEASED, same sha256; roster ∩ diff = ∅).
- [ ] 5.2 AC2–AC14 per the plan; every suite at or above baseline.
- [ ] 5.3 `git merge-tree --write-tree origin/main HEAD` clean before review and before `gh pr ready`.

## Phase 6 — Ship deliverables

- [ ] 6.1 PR body `Ref #8010`; label `semver:patch`; squash merge; decision-challenges rendered by ship Phase 6.
- [ ] 6.2 Comment on #8010: taken / not-taken items with reasons (incl. variables.tf verified accurate; items 5, 14, 16, 17; the two unflipped ledger rows).
- [ ] 6.3 Postmerge: release run for the merge SHA exists, `deploy` job `success`, `/health` `build_sha` == merge SHA; state the redeploy landed. Dispatch `web-platform-release.yml` (bump_type=patch) ONLY if no run exists for the merge SHA. Merge-triggered infra apply run green.
