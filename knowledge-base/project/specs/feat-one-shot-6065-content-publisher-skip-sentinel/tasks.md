---
title: "Tasks — fix #6065 content-publisher.sh skip sentinel"
plan: knowledge-base/project/plans/2026-07-05-fix-content-publisher-skip-sentinel-plan.md
issue: 6065
lane: single-domain
created: 2026-07-05
---

# Tasks — fix content-publisher.sh credential-skip sentinel (#6065)

Contract-before-consumer ordering. All tasks land in one atomic PR (`Closes #6065`).

## Phase 1 — Sentinel contract on `post_*` functions (`scripts/content-publisher.sh`)

- [ ] 1.1 Add convention comment above `post_discord`: `return 0 = posted; 1 = attempted+failed; 3 = skipped, not attempted`.
- [ ] 1.2 `post_discord :305` (no webhook) → `return 3`.
- [ ] 1.3 `post_x_thread :418` (no creds) → `return 3`; `:431` (no tweets) → `return 3`.
- [ ] 1.4 `post_linkedin :597` (no token) → `return 3`; `:604` (no content) → `return 3`.
- [ ] 1.5 `post_linkedin_company :627` (no org token, tracker-route — Decision D1) → `return 3`; `:632` (no org id) → `return 3`; `:637` (`LINKEDIN_ALLOW_POST!=true`) → `return 3`; `:644` (no content) → `return 3`.
- [ ] 1.6 `post_bluesky :688` (no creds) → `return 3`; `:693` (`BSKY_ALLOW_POST!=true`) → `return 3`; `:700` (no content) → `return 3`.
- [ ] 1.7 Confirm the 6 non-post `return 0` sites (`:117/:130/:218/:350/:540/:740`) are untouched.

## Phase 2 — Caller: capture exit code, count skips (`scripts/content-publisher.sh :839-900`)

- [ ] 2.1 Add `local file_skips=0` next to `file_failures`/`file_successes` (`:839-840`).
- [ ] 2.2 Rewrite `x` / `linkedin-personal` / `linkedin-company` / `bluesky` `case` arms to the set-e-safe form: `local rc=0; post_X "$file" || rc=$?; case "$rc" in 0) successes;; 3) skips;; *) failures;; esac`.
- [ ] 2.3 Fold sentinel into the Discord arm (keep content-guard + caller-side fallback issue on `*`); count empty-content Discord branch as `file_skips++`.
- [ ] 2.4 Unknown-channel arm (`:849-852`): `file_skips=$((file_skips + 1))` before `continue`.

## Phase 3 — Decision block (`scripts/content-publisher.sh :902-914`)

- [ ] 3.1 Keep `if file_successes>0` (flip published) and `elif file_failures>0` (`failures++`, exit 2) arms.
- [ ] 3.2 Add `elif file_skips>0` branch: leave `status: scheduled` (no `sed` flip); `create_dedup_issue` "Published nowhere -- all channels skipped for $CASE_NAME" with `action-required,content-publisher` labels; body enumerates `$channels`. Do NOT increment `failures` (Decision D2 — exit 0).
- [ ] 3.3 Confirm header "Exit codes" doc block (`:34-37`) stays `0/1/2` (return 3 never escapes `main()`).

## Phase 4 — Tests (`scripts/test-content-publisher-stale-alert.sh` → `scripts/test-content-publisher.sh`)

- [ ] 4.1 `git mv scripts/test-content-publisher-stale-alert.sh scripts/test-content-publisher.sh`; update header comment for broader scope.
- [ ] 4.2 Unit tests: each `post_*` skip precondition → rc 3 (per plan Phase 4 list), incl. Bluesky gate-off + empty-section, LinkedIn no-token + empty-section, X no-creds + empty-thread.
- [ ] 4.3 Unit regression: `post_discord` with webhook + stubbed `curl` 2xx → rc 0 (success not mislabelled skip).
- [ ] 4.4 Integration (stub `gh`/`create_dedup_issue` like the existing `curl` stub): bug-regression (all-skip → stays `scheduled` + "Published nowhere" issue + exit 0); success-dominates (success + skip → `published`); failure-preserved (rc 1 → exit 2, no nowhere issue).

## Phase 5 — CI wiring (`scripts/test-all.sh`)

- [ ] 5.1 Add `run_suite "scripts/content-publisher" bash scripts/test-content-publisher.sh` in the `want_scripts` block (before `:156` `fi`).

## Verification (Acceptance Criteria — see plan AC1-AC11)

- [ ] V1 `grep -cE '^\s*return 3' scripts/content-publisher.sh` == 11 (AC1).
- [ ] V2 `grep -c 'file_skips=$((file_skips + 1))' scripts/content-publisher.sh` >= 6 (AC3).
- [ ] V3 `grep -c '|| rc=$?' scripts/content-publisher.sh` >= 5 (AC4).
- [ ] V4 `bash -n` both scripts parse clean; `shellcheck` no new warnings if available (AC8).
- [ ] V5 `bash scripts/test-content-publisher.sh` exits 0 (AC7).
- [ ] V6 `TEST_GROUP=scripts bash scripts/test-all.sh` includes + passes `scripts/content-publisher` (AC9).
- [ ] V7 old filename gone + no dangling refs (AC10).
- [ ] V8 PR body uses `Closes #6065` (AC11).
