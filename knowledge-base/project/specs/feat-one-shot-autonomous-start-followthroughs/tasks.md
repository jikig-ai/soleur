# Tasks: autonomous start for the date-gated and event-gated code-quality follow-ups

Plan: knowledge-base/project/plans/2026-10-27-chore-autonomous-start-followthroughs-plan.md
Rulings: knowledge-base/project/specs/feat-one-shot-autonomous-start-followthroughs/decision-challenges.md
Refs only (never a closing keyword): #9730, #10515, #11177, #10331 (closed 2026-10-20, stays closed).

## Phase 1: RED tests first

- 1.1 Write `scripts/watch-code-quality-reeval-9730.test.sh` (stub `gh` with real-flag whitelist and real stderr shapes; self-test; last line `finish || exit 1`; cases: before/after 2026-11-14, sentinel suppression, billing 401/403/404/200, GraphQL failure exit 3, closed tracker, dry-run, xtrace 78; the one allowlist census over lib, scripts and workflow).
- 1.2 Write `scripts/watch-lint-ratchet-reeval-10515.test.sh` (before/after 2027-01-18, seven searches with 0/1/25 hits, item 5/6 lines, hostile title rendered inert, dry-run, xtrace).
- 1.3 Write `scripts/watch-brand-hex-triggers-11177.test.sh` (fixture repo copying the real gate and libs; trigger-1 cases; trigger-2 cases incl. reused-worktree ordering, truncation, timeout/WARN exit 3, prefix-colliding sentinels, preflight, `--print-state`, `--dry-run`; workflow facet checks).
- 1.4 Confirm each suite fails for the right reason before any implementation.

## Phase 2: shared library

- 2.1 `scripts/lib/watch-notify-once.sh`: `wn_now`/`wn_reached`, `wn_read_issue`, `wn_sentinel_present`, `wn_post`, `wn_sanitize_title`, `wn_billing_month` (single jq aggregate), `wn_preflight`, `wn_notify_once_main`.

## Phase 3: scripts

- 3.1 `scripts/watch-code-quality-reeval-9730.sh` (gather: PR volume via chunked aliased GraphQL, billing; compose; `--dry-run`).
- 3.2 `scripts/watch-lint-ratchet-reeval-10515.sh`.
- 3.3 `scripts/watch-brand-hex-triggers-11177.sh` (spike re-confirmed first: gate runs from the main checkout against a `--no-checkout` worktree).
- 3.4 chmod +x; confirm `scripts/followthrough-exec-bit.test.sh` and shellcheck-style lints stay green.

## Phase 4: workflow

- 4.1 `.github/workflows/code-quality-followups-watch.yml`: cron `17 9 * * 1`, `workflow_dispatch` with `dry_run`, three jobs guarded by `github.ref == 'refs/heads/main'`, concurrency group, exact permissions, checkout depths, header with rationale and RETIREMENT list.

## Phase 5: registry

- 5.1 Append three `run_suite` lines last in the `want_scripts` block of `scripts/test-all.sh`.
- 5.2 Insert three rows alphabetically in `scripts/suite-durations.tsv` and `scripts/suite-shard-legs.tsv`; leave `generated-at` headers alone.
- 5.3 Run the shard-manifest suites.

## Phase 6: verify and ship

- 6.1 Live read-only `--dry-run` of each script from the worktree with operator auth; compare PR totals with an independent `gh api` count; confirm the billing product string; measure per-commit gate time and set the timeout.
- 6.2 Repo-global checks: `scripts/check-adr-ordinals.sh`; `plugins/soleur/test/boundary-prefix.test.sh`; `python3 -I scripts/ci-pr-affected-replay.py ratchet`; `bash .claude/hooks/grep-q-pipe-guard.test.sh`; `scripts/guard-vacuity-floor.test.sh`; `plugins/soleur/skills/verification-scaffold/test/manifest.test.sh`; `plugins/soleur/test/c4-count-parity.test.sh`.
- 6.3 `soleur:review`, then `soleur:ship` (PR body: Ref lines, decision-challenges rendering, trailing Claude Code line). If BEHIND with auto-merge armed, wait via Monitor; no manual re-sync.

## Phase 7: post-merge (`soleur:postmerge`)

- 7.1 `gh workflow list` shows the workflow; dispatch `dry_run=true` on main; read the three job logs; capture the Actions token's billing status.
- 7.2 Pointer comments on #9730 (with the measured billing status) and #10515; none on #11177; verify all three OPEN and #10331 CLOSED.
