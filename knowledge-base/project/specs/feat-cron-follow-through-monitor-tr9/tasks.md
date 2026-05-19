# Tasks: TR9 PR-2 — `cron-follow-through-monitor`

Derived from `knowledge-base/project/plans/2026-05-19-feat-tr9-pr2-migrate-scheduled-follow-through-to-inngest-cron-plan.md` (v2, post-review).

**Atomicity contract:** Tasks 2.1, 2.5, 2.6 (cron file + route.ts registration + GHA YAML deletion) MUST land in a SINGLE commit. Task 4.1 (Terraform resource) may land in the same commit OR a follow-on. Task 6.1 (umbrella body update) is post-merge GitHub API call, not a commit.

## Phase 0: Preconditions

- [x] 0.1 Verify `claude` binary resolves via `createRequire` (plan §Phase 0.1 — 3-line bun probe).
- [x] 0.3 Verify no existing `sentry_cron_monitor.scheduled_follow_through` in Terraform state (plan §Phase 0.3 — `terraform plan` grep, expect 0 hits).
- [x] 0.4 Verify Sentry `croniter` parses weekday DOW correctly (plan §Phase 0.4 — two `gh api` reads against `getsentry/sentry` + `jianyuan/sentry`; halt on failure).

## Phase 1: Cron function file

- [x] 1.1 Create `apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts`:
  - [x] 1.1.1 File header with ADR-033 invariants I1–I6 + NAME NOTE + CLI form note + MAX_TURN_DURATION_MS rationale + dual SSRF defense note + §Pattern Boundaries DO-NOT-COPY block + account-scope keying note.
  - [x] 1.1.2 `resolveClaudeBin()` helper (copy verbatim from PR-1).
  - [x] 1.1.3 `MAX_TURN_DURATION_MS = 15 * 60 * 1000`; `KILL_ESCALATION_MS = 5_000`; `SENTRY_MONITOR_SLUG = "scheduled-follow-through"`.
  - [x] 1.1.4 `CLAUDE_CODE_FLAGS` array with `--max-turns 30` + extended `--allowedTools` allowlist (gh-CLI + close + label-create + curl + dig + Read/Glob/Grep).
  - [x] 1.1.5 `FOLLOW_THROUGH_PROMPT = String.raw\`...\`` inlined verbatim from `.github/workflows/scheduled-follow-through.yml:73-145` with Guards A/B/C + 2 new Sharp Edges directives (close-keyword forbidden; @-mention from API JSON + silence-followthrough opt-out).
  - [x] 1.1.6 `buildSpawnEnv()` allowlist (copy verbatim from PR-1).
  - [x] 1.1.7 `cronFollowThroughMonitorHandler` with three `step.run` steps: ensure-labels (creates `follow-through` + `needs-attention` + `silence-followthrough` labels with `|| true`); claude-eval (spawn + abort + SIGTERM→SIGKILL escalation); sentry-heartbeat (single POST with env-component validation, slug `scheduled-follow-through`).
  - [x] 1.1.8 `cronFollowThroughMonitor` Inngest registration with `id`, dual concurrency (`fn` + `account` cron-platform), `retries: 1`, dual trigger array.

## Phase 2: Inngest route registration (SAME commit as 1.1)

- [x] 2.1 Edit `apps/web-platform/app/api/inngest/route.ts`: add import + extend `functions` array.

## Phase 3: Vitest unit tests

- [x] 3.1 Create `apps/web-platform/test/server/inngest/cron-follow-through-monitor.test.ts` mirroring `cron-daily-triage.test.ts`:
  - [x] 3.1.1 T1 — Happy path (spawn exits 0; heartbeat status=ok).
  - [x] 3.1.2 T2 — Spawn error (ENOENT; reportSilentFallback; heartbeat status=error).
  - [x] 3.1.3 T3 — AbortSignal at 15 min (NOT 60 min); SIGTERM→SIGKILL escalation at +5s.
  - [x] 3.1.4 T4 — Sentry env missing (silent skip; no fetch).
  - [x] 3.1.5 T5 — Manual-trigger event path.

## Phase 4: Sentry monitor IaC

- [x] 4.1 Add `sentry_cron_monitor.scheduled_follow_through` resource in `apps/web-platform/infra/sentry/cron-monitors.tf` (insert after line 110, before `scheduled_realtime_probe`).

## Phase 5: GHA YAML deletion (SAME commit as 1.1 + 2.1)

- [x] 5.1 `git rm .github/workflows/scheduled-follow-through.yml`.

## Phase 6: Post-merge automation

- [ ] 6.1 Update umbrella #3948 body: check `scheduled-follow-through` checkbox; reclassify `scheduled-followthrough-sweeper` line with strikethrough + reclassification note.
- [x] 6.2 Amend ADR-033 with `[Refined 2026-05-19 post PR-2 plan review]` paragraph documenting account-scope `"cron-platform"` global slot decision + max manual-trigger latency upper bound.
- [ ] 6.3 Operator manual-trigger verification: `inngest send cron/follow-through-monitor.manual-trigger` within ~5 min of deploy completion. Confirm Sentry heartbeat `status=ok` (via `mcp__sentry__get_monitor` or `gh api`); confirm Inngest worker registered the function.

## Phase 7: Pre-merge verification

- [x] 7.1 `bun --cwd apps/web-platform run typecheck` clean.
- [x] 7.2 `bun --cwd apps/web-platform run test:ci` passes. Output MUST show `cron-no-byok-lease-sweep.test.ts` sweep enumerating BOTH `cron-daily-triage.ts` AND `cron-follow-through-monitor.ts` files (auto-extension via glob).
- [x] 7.3 `cd apps/web-platform/infra && terraform fmt -check && terraform validate` clean.
- [x] 7.4 Verify AC8 per-pattern grep passes against the new file:
  ```bash
  diff=$(git diff main -- apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts | grep '^+' | grep -v '^+++')
  for pat in 'Only request HTTPS' '\b127\.0\.0\.0/8\b' '\b10\.0\.0\.0/8\b' '\b172\.16\.0\.0/12\b' '\b192\.168\.0\.0/16\b' '\b169\.254\.0\.0/16\b' 'NEVER include the substring' 'silence-followthrough' 'author\.login'; do
    count=$(printf '%s\n' "$diff" | grep -cE "$pat") || true
    [ "$count" -ge 1 ] || { echo "AC8 FAIL: $pat"; exit 1; }
  done
  ```
- [x] 7.5 Verify AC12 single-commit atomicity via SHA equality:
  ```bash
  add_fn=$(git log -1 --diff-filter=A --format=%H -- apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts)
  mod_route=$(git log -1 --format=%H -- apps/web-platform/app/api/inngest/route.ts)
  del_yaml=$(git log -1 --diff-filter=D --format=%H -- .github/workflows/scheduled-follow-through.yml)
  [ "$add_fn" = "$mod_route" ] && [ "$add_fn" = "$del_yaml" ]
  ```
- [ ] 7.6 Update PR #4062 body: `Closes #4063` + `Refs #3948` + `Refs #4068` (SSRF deferral).

## Phase 8: Ship-time chores (compound)

- [ ] 8.1 Write a learning at `knowledge-base/project/learnings/<topic>.md` capturing: (a) the dual SSRF defense-in-depth model for LLM Bash allowlists with `curl`/`dig`; (b) Set.has() deferral rationale (linked to #4068); (c) auto-close keyword markdown-blindness interaction with comment-writer agents. Becomes binding-precedent for any future cron-* migration that needs network verbs. (Compound capture via `/soleur:compound` after merge.)
