# Tasks — feat-one-shot-9513-9475-stall-m7

Plan: `knowledge-base/project/plans/2026-10-06-fix-stall-executor-alerts-drain-m7-plan.md`
Issues: #9513 (executor visibility + drain), #9475 (M7 flake)

## Phase 1 — Failing tests first (TDD)

- [ ] 1.1 Extend `apps/web-platform/test/server/inngest/cron-merge-queue-stall-dispatch.test.ts`
  - [ ] 1.1.1 Route the Octokit `requestSpy` by endpoint string: `GET /repos/{owner}/{repo}/actions/workflows/{workflow_id}/runs` returns a per-arm canned `workflow_runs` payload; `POST .../dispatches` keeps returning `{status: 204}`.
  - [ ] 1.1.2 New arms: newest `conclusion=failure` → `reportSilentFallback` once (run id/conclusion/url in `extra`, token redacted) + `ok:false` heartbeat + result `ok:true` + dispatch still POSTed; `in_progress` 20 min old → same loud path (`stuck`); `queued` 30 s old → `ok:true` (`pending`); empty `workflow_runs` → `ok:true` (`none`); GET throws → `unknown` → report + `ok:false`; replay fake → exactly one runs GET across three handler passes.
  - [ ] 1.1.3 Update existing arms for the added GET (call counts/order: check GET precedes dispatch POST).
- [ ] 1.2 Extend `plugins/soleur/test/merge-queue-stall-check.test.sh`
  - [ ] 1.2.1 `gh` stub gains `issue view` (serves `--json state` per number) and `issue close` (records closes).
  - [ ] 1.2.2 Drain behavioural arms (execute the real step body): merged target → closed; open target → kept; title without `PR #N pending` anchor → kept; `issue view` failure → kept; `issue list` failure → sanitized `::error::` + zero closes; enumeration at the `-L 50` bound → cap `::notice::`.
  - [ ] 1.2.3 Structural rows: drain step present with `if: always()`, no `continue-on-error`, no `${{ }}` in its `run:` body, `-L 50` bound, label-scoped list.
  - [ ] 1.2.4 Bump `EXPECTED_PASSES` to the new exact count.
- [ ] 1.3 Run both suites; confirm RED on the missing `check-previous-run` and drain steps.

## Phase 2 — Dispatcher check-previous-run (#9513 gap 1)

- [ ] 2.1 Edit `apps/web-platform/server/inngest/functions/cron-merge-queue-stall-dispatch.ts`
  - [ ] 2.1.1 Add the `check-previous-run` step after mint, before `dispatch-workflow`: `GET .../actions/workflows/{workflow_id}/runs` `per_page=5`, no event filter; verdict ∈ {ok, failed, stuck, pending, none, unknown}.
  - [ ] 2.1.2 `failed` = completed with conclusion in `failure|timed_out|cancelled|startup_failure|action_required|stale`; `stuck` = non-completed with `created_at` older than 11 min; `pending` = younger non-completed; `none` = empty list; `unknown` = Octokit error (never throws).
  - [ ] 2.1.3 `failed|stuck|unknown` → `reportSilentFallback` (run id, conclusion, html_url in `extra`; token redacted) + heartbeat `ok:false`; else heartbeat `ok: dispatch.ok`.
  - [ ] 2.1.4 Result gains `previousRun` field; `ok` remains the dispatch verdict.
  - [ ] 2.1.5 Update the header Liveness paragraph (green now means dispatched AND prior run not red/stuck).
- [ ] 2.2 Run the vitest suite → GREEN.

## Phase 3 — Drain step (#9513 gap 2)

- [ ] 3.1 Add `Drain stale stall issues` step to `.github/workflows/merge-queue-stall-check.yml`, `if: always()`, after the detect step:
  - [ ] 3.1.1 Label-scoped `gh issue list --state open -L 50 --label merge-queue-stall --json number,title`; list failure → sanitized `::error::` (`LC_ALL=C tr -cd '\40-\176' | head -c 300`) + skip.
  - [ ] 3.1.2 Standalone jq `capture("PR #(?<pr>[0-9]+) pending")` → `issue\tpr` pairs; cap-hit `::notice::` at the bound.
  - [ ] 3.1.3 Per pair: `gh issue view <pr> --json state`; close only when state is non-empty and ≠ `OPEN`; `gh issue close` failure → `|| true`.
  - [ ] 3.1.4 env via `env:` block (GH_TOKEN, GH_REPO, RUN_URL); no `${{ }}` inside the `run:` body.
- [ ] 3.2 Run `plugins/soleur/test/merge-queue-stall-check.test.sh` → GREEN at new floor.

## Phase 4 — M7 hardening (#9475)

- [ ] 4.1 In `scripts/test-all-runtime-ceiling.test.sh`: synthesize `bump360.sh` (writes 360), map `three_bump` to it, raise the arm's ceiling to 300; keep `declined_suites=2`.
- [ ] 4.2 Replace the M7 failure line with the self-describing dump: arm rc, bump file path + contents, bounded tail of the arm log.
- [ ] 4.3 Run `bash scripts/test-all-runtime-ceiling.test.sh` → all arms green.

## Phase 5 — Verification & ship inputs

- [ ] 5.1 `bash scripts/test-all.sh --affected` green.
- [ ] 5.2 PR body carries `Closes #9513` and `Closes #9475` on their own lines, plus the M7 reproduction summary (100 loaded iterations, two load shapes, zero failures).
