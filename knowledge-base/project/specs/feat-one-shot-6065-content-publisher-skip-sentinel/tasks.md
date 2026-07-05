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

- [x] 1.1 Add convention comment above `post_discord`: `return 0 = posted; 1 = attempted+failed; 3 = skipped, not attempted`.
- [x] 1.1b Declare a module-scope `SKIP_REASON` global near `DISCORD_LAST_ERROR`; set it (short reason string) at each skip site immediately before `return 3`.
- [x] 1.2 `post_discord :305` (no webhook) → `SKIP_REASON="no credentials"; return 3`.
- [x] 1.3 `post_x_thread :418` (no creds) → `return 3`; `:431` (no tweets → "empty thread") → `return 3`.
- [x] 1.4 `post_linkedin :597` (no token) → `return 3`; `:604` (empty section) → `return 3`.
- [x] 1.5 `post_linkedin_company :627` (no org token, tracker-route — Decision D1) → `return 3`; `:632` (no org id) → `return 3`; `:637` (`LINKEDIN_ALLOW_POST!=true`, gate off) → `return 3`; `:644` (empty section) → `return 3`.
- [x] 1.6 `post_bluesky :688` (no creds) → `return 3`; `:693` (`BSKY_ALLOW_POST!=true`, gate off) → `return 3`; `:700` (empty section) → `return 3`.
- [x] 1.7 Confirm the 6 non-post `return 0` sites (`:117/:130/:218/:350/:540/:740`) are untouched.

## Phase 2 — Caller: capture exit code, count skips + reasons (`scripts/content-publisher.sh :839-900`)

- [x] 2.1 Declare `local file_skips=0` and `local -a file_skip_reasons=()` next to `file_failures`/`file_successes` (`:839-840`).
- [x] 2.2 Add `tally_rc()` helper (above `main`): `case "$rc" in 0) successes;; 3) skips + file_skip_reasons+=("$channel: ${SKIP_REASON:-skipped}");; *) failures;; esac`. Relies on dynamic scope (loop is `done < <(...)`, not a pipeline) — precedent `sweep-followthroughs.sh:211-261`.
- [x] 2.3 Rewrite `x` / `linkedin-personal` / `linkedin-company` / `bluesky` arms to `local rc=0; post_X "$file" || rc=$?; tally_rc "$rc" "$channel"`. Never `local rc=$(…)`.
- [x] 2.4 Discord arm keeps an inline `case` (its `*` branch also creates the fallback issue); rc 3 → `file_skips++` + reason; empty-content Discord branch → `file_skips++` + `file_skip_reasons+=("$channel: empty section")`.
- [x] 2.5 Unknown-channel arm (`:849`): `file_skips++` + `file_skip_reasons+=("$channel: unknown channel")` before `continue`.
- [x] 2.6 **F1** — empty-token `continue` (`:846`): `[[ -z "$channel" ]] && { file_skips=$((file_skips+1)); file_skip_reasons+=("(empty channel token)"); continue; }` so `channels: ","` no longer falls through silently.

## Phase 3 — Decision block + nowhere-issue helper (`scripts/content-publisher.sh :902-914`)

- [x] 3.1 Add `create_nowhere_issue()` helper (house-style `create_*_issue`): body interpolates the joined `file_skip_reasons` ("- channel: reason" per line); title "[Content Publisher] Published nowhere -- all channels skipped for $case_name"; labels `action-required,content-publisher`. NO "see run logs" pointer (stderr is discarded by the spawn).
- [x] 3.2 Keep `if file_successes>0` (flip published) and `elif file_failures>0` (`failures++`, exit 2) arms.
- [x] 3.3 Add `elif file_skips>0` branch: leave `status: scheduled` (no `sed` flip); `reasons_joined=$(printf '- %s\n' "${file_skip_reasons[@]}")`; `create_nowhere_issue "$CASE_NAME" "$reasons_joined" || true`. Do NOT increment `failures` (Decision D2 — exit 0).
- [x] 3.4 Confirm header "Exit codes" doc block (`:34-37`) stays `0/1/2` (return 3 never escapes `main()`).

## Phase 4 — Tests (`scripts/test-content-publisher-stale-alert.sh` → `scripts/test-content-publisher.sh`)

- [x] 4.1 `git mv scripts/test-content-publisher-stale-alert.sh scripts/test-content-publisher.sh`; update header comment for broader scope.
- [x] 4.2 Unit tests: each `post_*` skip precondition → rc 3 (per plan Phase 4 list), incl. Bluesky gate-off + empty-section, LinkedIn no-token + empty-section, X no-creds + empty-thread.
- [x] 4.3 Unit regression: `post_discord` with webhook + stubbed `curl` 2xx → rc 0 (success not mislabelled skip).
- [x] 4.4 Integration (stub `gh`/`create_dedup_issue` like the existing `curl` stub): bug-regression (all-skip → stays `scheduled` + "Published nowhere" issue + exit 0); reason-discrimination (bluesky no-creds + linkedin-personal empty-section → issue body contains both `bluesky: no credentials` and `linkedin-personal: empty section`); success-dominates (success + skip → `published`); failure-wins-over-skip multi-channel (`discord` fail + `bluesky` skip → `0/1/1` → exit 2, Discord fallback, no nowhere issue); **F1** silent-gap (`channels: ","` → stays `scheduled` + nowhere issue created).

## Phase 5 — CI wiring (`scripts/test-all.sh`)

- [x] 5.1 Add `run_suite "scripts/content-publisher" bash scripts/test-content-publisher.sh` in the `want_scripts` block (before `:156` `fi`).

## Verification (Acceptance Criteria — see plan AC1-AC11)

- [x] V1 `grep -cE '^\s*return 3' scripts/content-publisher.sh` == 11 (AC1).
- [x] V2 `grep -q 'local file_skips=0'` + `grep -q 'file_skip_reasons'` present; correctness proven by V5 integration tests, not a literal-increment count (AC3, behavioral).
- [x] V2b Nowhere issue body carries per-channel reasons; `grep -c 'workflow run logs' scripts/content-publisher.sh` == 0 (AC4b).
- [x] V3 `grep -c '|| rc=$?' scripts/content-publisher.sh` >= 5; no `local rc=$(` form (AC4).
- [x] V4 `bash -n` both scripts parse clean; `shellcheck` no new warnings if available (AC8).
- [x] V5 `bash scripts/test-content-publisher.sh` exits 0 (AC7).
- [x] V6 `TEST_GROUP=scripts bash scripts/test-all.sh` includes + passes `scripts/content-publisher` (AC9).
- [x] V7 old filename gone + no dangling refs (AC10).
- [x] V8 PR body uses `Closes #6065` (AC11).
