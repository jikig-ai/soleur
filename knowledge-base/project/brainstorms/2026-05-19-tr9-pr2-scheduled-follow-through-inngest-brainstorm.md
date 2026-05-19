---
lane: cross-domain
brand_survival_threshold: single-user incident
parent_epic: "#3244"
parent_pr_merged: "#3985 (PR-1, scheduled-daily-triage, 2026-05-18)"
umbrella_issue: "#3948"
type: carry-forward
---

# TR9 PR-2 — `scheduled-follow-through` → Inngest cron (Brainstorm)

**Date:** 2026-05-19
**Worktree:** `.worktrees/feat-cron-follow-through-monitor-tr9`
**Branch:** `feat-cron-follow-through-monitor-tr9`
**Draft PR:** [#4062](https://github.com/jikig-ai/soleur/pull/4062)
**Umbrella:** [#3948](https://github.com/jikig-ai/soleur/issues/3948) — TR9 group-(c) agent-loop crons → Inngest
**Direct predecessor:** PR-1 [#3985](https://github.com/jikig-ai/soleur/pull/3985) — MERGED 2026-05-18

## Why this is a carry-forward, not a fresh brainstorm

PR-1 [#3985] landed the full TR9 substrate stack on `scheduled-daily-triage` with explicit CPO + CLO + CTO triad sign-off. ADR-033 (`Inngest cron functions invoke claude-code via child_process.spawn`) is `accepted`. The 6 substrate invariants I1–I6 are documented and enforced by tests on main (`cron-no-byok-lease-sweep.test.ts`, `cron-daily-triage.test.ts`, `byok-audit-writer-sweep.test.ts`).

`scheduled-follow-through.yml` is the **direct structural peer** of `scheduled-daily-triage.yml`: same 1-job-with-LLM topology, same `anthropics/claude-code-action@v1.0.101` invocation shape, same comment-writer + label-mutator side-effect class, same CLO bucket ii. The substrate transfers 1:1. This brainstorm is therefore a focused capture of the PR-2-specific deltas; no architectural decisions are re-litigated.

**Re-evaluation criteria for re-spawning a full brainstorm (per Phase 0.5 step 4 contract):**
1. If PR-2 review surfaces a substrate invariant violation not anticipated by ADR-033, escalate to triad re-spawn.
2. If the workflow-specific deltas below imply a NEW substrate primitive (e.g., business-day math, label-mutator subtleties), surface as a Capability Gap and re-evaluate before PR-3.
3. If the user-impact-reviewer at PR-review gate (load-bearing gate per `hr-weigh-every-decision-against-target-user-impact`) finds an under-thresholded failure mode, re-frame and re-spawn CPO+CLO.

## User-Brand Impact (inherited, re-audited)

**Threshold:** `single-user incident` (inherited from parent epic #3244).

**Audit deltas for this workflow specifically (not in PR-1):**
- **Auto-close on predicate pass.** The agent CAN close issues unilaterally when http-200/dns-txt/dns-a passes. PR-1 (`daily-triage`) is label-only, never closes. PR-2's auto-close behavior is the load-bearing user-trust surface — a false-positive predicate (e.g., a redirect-to-error page that returns 200) closes a real follow-through silently. **Mitigation carries the existing GHA prompt's `Sharp Edges` invariants verbatim** + adds idempotent search-before-close (gh issue view → check for prior "Verified:" comment) so an Inngest replay does not double-close-and-comment.
- **@-mention escalation.** Agent @-mentions `author.login` on SLA exceeded. A label-spam injection from an issue body that re-routes the @-mention is the failure mode. Mitigation: prompt already treats issue body as untrusted; tools narrowed to gh-CLI verbs (see deltas §3 below) prevents `curl` to attacker URLs.
- **30-business-day max polling auto-close.** Agent closes after 30 business days. This is a hard ceiling that pre-existed in GHA; preserved in PR-2 1:1.

## What We're Building

A single Inngest cron function `apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts` that replaces `.github/workflows/scheduled-follow-through.yml`, with the GHA YAML deleted in the same commit (I-13 contract from PR-1).

## PR-2-specific deltas vs PR-1

| Dimension | PR-1 (`daily-triage`) | PR-2 (`follow-through`) | Source of delta |
|---|---|---|---|
| GHA file | `.github/workflows/scheduled-daily-triage.yml` (156 lines, deleted) | `.github/workflows/scheduled-follow-through.yml` (145 lines, deleted in same commit) | Workflow inventory |
| Inngest file | `apps/web-platform/server/inngest/functions/cron-daily-triage.ts` | `apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts` | TR9 `cron-*.ts` convention |
| Inngest fn id | `cron-daily-triage` | `cron-follow-through-monitor` | TR9 `cron-*` convention |
| Sentry monitor slug | `scheduled-daily-triage` (continuity from PR-F) | `scheduled-follow-through` (continuity) | `cron-monitors.tf` keep-existing rule |
| Cron schedule | `0 4 * * *` (daily 04:00 UTC) | `0 9 * * 1-5` (weekdays 09:00 UTC) | GHA → Inngest cron syntax (Inngest supports same syntax; weekday DOW range verified at plan time) |
| Max turns | `80` | `30` | Existing GHA `--max-turns 30`; reflects narrower per-issue scope |
| AbortSignal timeout | 60 min (`MAX_TURN_DURATION_MS`) | 15 min | GHA `timeout-minutes: 15`; preserves 0.5 min/turn ratio for 30-turn budget (still above the 0.75/turn Architecture-F2 floor would prescribe, but task is fundamentally smaller — predicate execution dominates LLM-bound time) |
| `--allowedTools` | `Bash(gh issue list:*),Bash(gh issue view:*),Bash(gh issue edit:*),Bash(gh issue comment:*),Read,Glob,Grep` | `Bash(gh issue list:*),Bash(gh issue view:*),Bash(gh issue edit:*),Bash(gh issue comment:*),Bash(gh issue close:*),Bash(gh label create:*),Bash(curl:*),Bash(dig:*),Read,Glob,Grep` | Predicate execution needs http (`curl`), DNS (`dig`); state-machine needs `close` + `label create` verbs |
| Predicate side-effects | None (label-only) | `curl` for `http-200`, `dig` for `dns-txt` / `dns-a` | Workflow semantics |
| Idempotency guard | "search before add Automated Triage comment" | (a) "search before re-Verified-and-close" (auto-close idempotent on replay); (b) "search for prior `needs-attention` label before add" | Workflow semantics + Inngest replay risk |
| Preflight job | (none) | DROP the GHA `preflight` job that calls `./.github/actions/anthropic-preflight`. Inngest worker uses Doppler `ANTHROPIC_API_KEY` directly; spend cap is enforced upstream by the budget guard in `claude-eval` step's `reportSilentFallback` shape | PR-1 also dropped preflight; precedent |
| Tests | `cron-daily-triage.test.ts` | `cron-follow-through-monitor.test.ts` (mirror structure) + extend `byok-audit-writer-sweep.test.ts` + `cron-no-byok-lease-sweep.test.ts` to include the new file | PR-1 test pattern |
| `cron_run_ledger` row | `cron-daily-triage` | `cron-follow-through-monitor` | First-step jitter guard reads/writes this row name |
| `actor: "platform"` invariant | applies (`cron-*.ts` forbidden to import `runWithByokLease`) | applies 1:1 | I6 |

## Substrate primitives reused verbatim from PR-1

(No re-litigation; reuse 1:1 per ADR-033.)

- **I1 — claude binary spawned INSIDE `step.run`.** Same `resolveClaudeBin()` helper, lazy resolution, ESM `createRequire` shape.
- **I2 — Operator `ANTHROPIC_API_KEY` only; never founder BYOK.** Enforced by `cron-no-byok-lease-sweep.test.ts` (extend pattern: add file to import-sentinel allowlist).
- **I3 — AbortSignal aborts at `MAX_TURN_DURATION_MS` (15 min for this workflow), with SIGTERM→SIGKILL escalation at `KILL_ESCALATION_MS=5_000`.** Same merged abort handler shape (single listener, `exited` flag gates SIGKILL not `child.killed`).
- **I4 — `claude` binary via `@anthropic-ai/claude-code` npm dep.** No cloud-init pin; ships through deploy pipeline.
- **I5 — Deterministic `step.run` return shape `{ok, exitCode, signal, abortedByTimeout, durationMs}`.** stdout not captured into memoization payload.
- **I6 — Event payloads carry `actor: "platform"`** (this function emits none, same as PR-1; carry-forward).
- **Sentry heartbeat at end-of-`step.run`** — single POST with `?status=ok|error`. Env-component regex validation (`SENTRY_DOMAIN_RE`, `SENTRY_PROJECT_RE`, `SENTRY_PUBLIC_KEY_RE`) reused verbatim. Slug `scheduled-follow-through` (continuity).
- **Spawn-env allowlist `buildSpawnEnv()`** — same `PATH`/`HOME`/`NODE_ENV`/`ANTHROPIC_API_KEY`/`GH_TOKEN` allowlist. Closes secret-exfil blast radius.
- **Concurrency config** — `concurrency: [{scope: "fn", limit: 1}, {scope: "account", key: '"cron-platform"', limit: 1}]`. Same 1-at-a-time semantics as PR-1's `concurrency.group: schedule-follow-through, cancel-in-progress: false`.
- **Retries** — `retries: 1` (PR-1 default).
- **Manual-trigger event** — register `{event: "cron/follow-through-monitor.manual-trigger"}` alongside the cron trigger (Spec-flow AC37 carry-forward).

## Key Decisions

1. **Carry-forward over fresh brainstorm.** PR-1 triad sign-off + ADR-033 + 6 invariants apply 1:1; PR-2 deltas are workflow-specific, not architectural. (Operator-confirmed 2026-05-19.)
2. **Target = `scheduled-follow-through.yml`, NOT `scheduled-followthrough-sweeper.yml`.** Original user input named the sweeper; sweeper is pure-shell (no LLM) so PR-1 substrate doesn't fit. Reclassify sweeper to group (a)/(b) infra-cron — leave on GHA, drop from #3948 umbrella checkbox list at PR-2 merge. (Operator-confirmed 2026-05-19.)
3. **`--allowedTools` widening with predicate verbs.** `Bash(curl:*),Bash(dig:*),Bash(gh issue close:*),Bash(gh label create:*)` added. Bash allowlist narrowing remains load-bearing per PR-1 review pattern (prompt-injection blast-radius cap).
4. **15-min timeout, 30-turn budget.** Mirrors GHA. Below PR-1's 60-min/80-turn but above the 0.75 min/turn Architecture F2 floor only if interpreted as "time per active LLM turn" not "wallclock"; predicate execution (curl, dig) dominates wallclock per turn so the ratio is non-comparable. Plan-time to verify against real prior-run wallclock from `gh run list --workflow scheduled-follow-through.yml --limit 20`.
5. **Sentry slug = `scheduled-follow-through`** (continuity, not `cron-follow-through-monitor` — same naming-vs-resource-id split as PR-1).
6. **Idempotency guard widened.** PR-1 had one idempotency check (search-before-add triage comment). PR-2 needs three: (a) search-before-add `Verified:` comment when auto-closing; (b) search-before-add `SLA exceeded` comment + `needs-attention` label; (c) search-before-add `Maximum polling` comment when closing on 30-day max. All three guard against Inngest replay → double-comment-and-close.

## Capability Gaps

None new vs PR-1. All capability gaps from PR-1's brainstorm (`claude` binary on Hetzner, `cron_run_ledger` table, Inngest scaffolder skill) are now `accepted` (binary deployed, table exists, skill remains the Productize Candidate).

## Domain Assessments

**Assessed:** Engineering, Product, Legal (carry-forward from PR-1 triad sign-off, no fresh spawn).

### Engineering (CTO) — carry-forward

ADR-033 invariants I1–I6 apply 1:1. Substrate primitives reused verbatim. The only engineering-class risk is the `--allowedTools` widening — adding `curl` and `dig` to the agent's Bash allowlist creates a SSRF-like surface IF the prompt is jailbroken to call `curl` against an attacker-supplied URL outside the predicate. Existing prompt-Sharp-Edges cover "treat issue body as untrusted"; the prompt's HTTPS-and-non-RFC1918 guard prevents the worst-case localhost/private-net SSRF. Acceptance: ship the widening, rely on the existing prompt's URL guard.

### Product (CPO) — carry-forward

Sequencing unchanged: TR9 PR-2 ships before PR-G #3947. Bucket ii (comment-writer + label-mutator) confirmed. No new re-evaluation criteria. The sweeper reclassification is a positive scope reduction.

### Legal (CLO) — carry-forward

Self-hosted Inngest avoids new sub-processor cycle (carry-forward from PR-1 K19). The follow-through workflow touches founder-PII-adjacent data (issue author login, @-mentions). Article 30 audit reused from PR-1 — same data classes, same actors. `hr-autonomous-loop-skill-api-budget-disclosure` is NO-OP for platform-loop crons (carry-forward). No key rotation required at migration.

## Productize Candidate

`/soleur:migrate-cron-to-inngest <workflow-name>` skill (filed at PR-1 brainstorm close). PR-2 is the second data point — if PR-2 lands with <50 lines of net-new code vs PR-1's primitives, the skill payoff becomes concrete. Re-evaluate after PR-2 merge: file the skill issue OR defer to PR-3.

## Deferred to follow-up issues

- **`scheduled-followthrough-sweeper` reclassification** to group (a)/(b) infra-cron. File a tracking issue or update #3948 checkbox list to remove it. Recommendation: update umbrella body at PR-2 merge.
- **Remaining 9 child migrations** under #3948 (still: `bug-fixer`, `strategy-review`, `roadmap-review`, `community-monitor`, `ux-audit`, `legal-audit`, `competitive-analysis`, `compound-promote`, `agent-native-audit`).

## References

- **Direct predecessor:** PR-1 [#3985](https://github.com/jikig-ai/soleur/pull/3985) — MERGED 2026-05-18.
- **PR-1 brainstorm:** `knowledge-base/project/brainstorms/2026-05-18-tr9-agent-loop-crons-inngest-migration-brainstorm.md`.
- **ADR-033:** `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md` — `accepted`.
- **PR-1 source files reused as templates:**
  - `apps/web-platform/server/inngest/functions/cron-daily-triage.ts` (371 lines)
  - `apps/web-platform/test/server/inngest/cron-daily-triage.test.ts` (261 lines)
  - `apps/web-platform/test/server/cron-no-byok-lease-sweep.test.ts` (91 lines)
- **Sentinel test extension target:** `apps/web-platform/test/server/byok-audit-writer-sweep.test.ts` (cron-* import allowlist).
- **Sentry monitor IaC:** `apps/web-platform/infra/sentry/cron-monitors.tf` — verify slug `scheduled-follow-through` continuity at plan time.
- **Carry-forward learnings:**
  - `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md`
  - `2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md`
  - `2026-05-18-claude-code-action-claude-args-vs-direct-cli-form-drift.md`
  - `2026-05-18-brainstorm-verify-issue-body-enumerations-against-live-state.md` (caught the sweeper-vs-monitor name collision at Phase 1.0.5)
