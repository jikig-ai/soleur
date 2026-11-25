# Tasks — feat-one-shot-13056-cname-flatten-settings

Plan: `knowledge-base/project/plans/2026-11-25-fix-cf-migrate-gate-cname-flatten-default-plan.md`
Issue: #13056 (epic #12931). PR: #13057 (draft).

Hard boundaries: dispatch no `cf-account-migrate.yml` run. Print no token value. Use no SSH and make no
Cloudflare writes. Change nothing in `dns.tf`, `cf-account-migrate-job.sh` or `cfam_norm_shape`.

## 1. Setup

- 1.1 Read `tests/scripts/lib/cf-account-migrate-gate.sh` (`cfam_live_diff` and the IMPORT-NORMALIZE header paragraph) and `tests/scripts/test-cf-account-migrate-gate.sh` (the `lrow` L-rows, the `D1`–`D4` rows, the `gm_lost` definition and the anti-vacuity floor).
- 1.2 Record the baseline. `bash tests/scripts/test-cf-account-migrate-gate.sh` prints `344 passed, 0 failed`.

## 2. RED (tests first)

- 2.0 Give `norm_admits` an optional `[<live>]` argument and `lrow` an optional `[<address>]` argument, as in plan Phase 1 items 1 and 2.
- 2.1 Relabel `L11` to `L11: a non-CNAME record's live settings flatten_cname=false differ`. Leave its tokens and filter as they are.
- 2.2 Insert the plan's Phase 1 block, verbatim, immediately before `# Anti-vacuity floor, reported outside pass()/fail() (ADR-193).`. The block holds F5-cname, L11a–L11g, D5, D6 (mixed read), M-flatten-guard and M-flatten-after.
- 2.3 Raise the floor from 344 to 356, changing both the `-lt` and the message.
- 2.4 Run the suite. It must fail exactly `L11a`, `L11b`, `D5`, `D6`, `M-flatten-guard` and `M-flatten-after`, ending `350 passed, 6 failed` (AC2).

## 3. GREEN

- 3.1 Replace the one-line `settings` clause in `cfam_live_diff` with the three-line `if … elif … else "settings" end` form from the plan's Phase 2a. Keep the `elif` on one line ending in `then empty`.
- 3.2 Append the four-line header sentence (CTO ruling 2026-11-25, #13056) to the IMPORT-NORMALIZE paragraph.
- 3.3 Run the suite. It must print `356 passed, 0 failed` (AC1) and leave L11, L12, L13, G1-7 and G1-8b green (AC3).
- 3.4 Run the `cfam_norm_shape` byte-identity diff (AC4) and shellcheck with no new findings (AC6).

## 4. Docs

- 4.1 Runbook `### Step 2`. Add one prose sentence after `Every other diff is still refused.` and rewrite the Meaning cell of the `settings:only-flatten-false` row (plan Phase 3a).
- 4.2 ADR-329 fourth-exception bullet. Add the CNAME carve-out to the `settings` sentence (plan Phase 3b).
- 4.3 Run `test-cf-account-migration-runbook.sh` and `test-cf-account-migration-scope.sh` (AC5), then `lint-infra-no-human-steps.py --changed --base origin/main` (AC7b). Confirm AC7 with its row-level and `tr`-joined grep commands.

## 5. Hand-off

- 5.1 Check AC4 (the diff touches only the four files plus pipeline artifacts) and AC8 (no migrate run on this branch).
- 5.2 Leave AC9, the post-merge `redirects-dns` re-rehearsal, to the parent session. Do not dispatch it.
