---
title: "chore(inngest): stale ci/* bot-PR watchdog"
issue: 5138
branch: feat-stale-bot-pr-watchdog-5138
pr: 5200
lane: cross-domain
brand_survival_threshold: none
type: chore
created: 2026-06-12
---

# chore(inngest): stale `ci/*` bot-PR watchdog

## Overview

After #5111 / ADR-054, `safeCommitAndPr` is the sole write path for bot cron PRs. Pipelines on `mergeMode: "auto"` rely on GitHub's `enablePullRequestAutoMerge`, which **silently disarms on merge conflict** — the PR stays open with no Sentry signal and no comment. This is the only *invisible*-stale mode (the `direct` and `none` modes fail loudly).

This plan adds an **open-bot-PR age scan** to the existing `cron-cloud-task-heartbeat` Inngest function. Each daily run, after the existing task-silence check, it lists open PRs whose head branch matches `ci/*` or `self-healing/auto-*`, flags any older than 48h (excluding human-review-by-design compound-promote drafts), emits a Sentry warn, routes that warn to the operator via a `sentry_issue_alert`, and posts a best-effort comment on the owning cron's `scheduled-<name>` issue.

**Key design property — the age scan is merge-mode-agnostic.** It catches the *result* (an open `ci/*` PR past threshold) regardless of how the PR got stuck, so a single scan covers BOTH exposure cohorts without special-casing:
- the 7 dormant `mergeMode: "auto"` crons (zero exposure today; opens at Tier-2 restoration), AND
- the **live** `direct`-fallback window ADR-054 flagged — a `direct` pipeline whose immediate `PUT …/merge` fails falls back to *arming* auto-merge (Sentry op `safe-commit-direct-merge-fell-back`), entering the same silently-disarmable state right now.

The scan does NOT need to read the `safe-commit-direct-merge-fell-back` op; the resulting stuck PR is caught by branch-prefix + age alone.

**Decisions locked at plan time (operator-confirmed):**
1. **Architecture:** extend the existing `cronCloudTaskHeartbeatHandler` (reuse the minted installation token, daily `30 9 * * *` cadence, and existing Sentry-heartbeat liveness). No new cron, no new `EXPECTED_CRON_FUNCTIONS` entry, no new cron monitor, no `function-registry-count.test` churn. Bot-PR staleness is **orthogonal** to the existing task-silence `ok`/`silentCount` — it emits warns + comments only and never flips the heartbeat monitor (per `2026-06-01-best-effort-cron-monitor-liveness-not-success`: the monitor pages on liveness, not on found-work).
2. **Alert depth:** `warnSilentFallback(op: "stale-bot-pr")` + owning-issue comment + a new `sentry_issue_alert.stale_bot_pr` `.tf` rule routing the op to the operator via `notify_email { target_type = "IssueOwners" }` (the sibling-alert convention — satisfies `hr-no-dashboard-eyeball-pull-data-yourself` + the observability gate's `alert_target`).

**Re-evaluation gate satisfied:** #5138 gates Tier-2 restoration of the 7 PR-flow `auto` crons on this watchdog landing first. Merging this PR removes that gate.

## Research Reconciliation — Spec vs. Codebase

| Issue-body / framing claim | Reality (verified at plan time) | Plan response |
|---|---|---|
| "exposure window is currently zero" (all `auto` crons Tier-2 dormant) | **Incomplete.** ADR-054 Consequences: a live `direct` pipeline can fall back to arming auto-merge (`safe-commit-direct-merge-fell-back`), so there is a present-day exposure too. | Scan is merge-mode-agnostic → covers both cohorts. Documented in Overview; no code special-case needed. |
| "comment on the owning cron's scheduled issue" | Canonical pattern exists: `_cron-safe-commit.ts:291 commentOnScheduledIssue` resolves the most-recent OPEN issue carrying `config.scheduledIssueLabel` (`scheduled-<name>`), Sentry-only fallback (`safe-commit-comment-no-target`) when none exists (the 5 pure-TS `direct` crons usually have no labeled issue). | Reuse the exact shape. Derive `scheduled-<name>` from the head branch. |
| head branches `ci/*` / `self-healing/auto-*` | Confirmed. `_cron-safe-commit.ts:176-181 deriveBranchName` → `ci/<cronName minus 'cron-'>-<YYYY-MM-DD-HHMMSS>`; `branchName` override (compound-promote) → `self-healing/auto-<hash>-<date>`. | Scan globs match exactly. Cron name reverse-derivable by stripping `ci/` + trailing `-\d{4}-\d{2}-\d{2}-\d{6}`. |
| "EXCLUDE draft PRs labeled `self-healing/auto`" | compound-promote = `mergeMode: "none"` + `prDraft: true` + label `self-healing/auto` (ADR-054 "three merge modes" table). | Exclude `pr.draft === true && labels include "self-healing/auto"`. |
| extend the `cron-cloud-task-heartbeat` "family" | Single function `cron-cloud-task-heartbeat.ts` (334 LoC), clean step.run structure, reusable installation token. | Extend in place (Decision 1). |
| Sentry warn auto-alerts the operator? | No. `warnSilentFallback` → `Sentry.captureMessage(level:"warning")` (searchable issue only). `issue-alerts.tf` has per-`feature`/`op` `sentry_issue_alert` resources (import-only beta provider) for routing. | Add `sentry_issue_alert.stale_bot_pr` (Decision 2). |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing. The failure mode is operator-internal — stale bot PRs accumulate undetected, i.e. the exact observability gap #5138 closes stays open. No user artifact, flow, or data is involved.

**If this leaks, the user's data is exposed via:** N/A. The watchdog reads PR *metadata* (head ref, created_at, draft, labels, number) via the existing GitHub-App installation token and writes issue *comments*; it touches no user data, auth surface, payment surface, or regulated-data store.

**Brand-survival threshold:** none.
- `threshold: none, reason: internal operator-observability cron; touches apps/web-platform/server/inngest/ + apps/web-platform/infra/sentry/ only, no regulated-data/auth/user-data/payment surface, and no single user is reachable by any failure mode.` (Preflight Check 6 sensitive-path scope-out bullet.)

## Implementation Phases

### Phase 1 — Constants + pure helpers (test-first)

In `apps/web-platform/server/inngest/functions/cron-cloud-task-heartbeat.ts`:

- `const STALE_BOT_PR_THRESHOLD_MS = 48 * 60 * 60 * 1000;`
- `const BOT_PR_HEAD_PREFIXES = ["ci/", "self-healing/auto-"] as const;`
- `export const STALE_BOT_PR_WARN_OP = "stale-bot-pr";`

Exported pure helpers (exported so the unit test drives them directly — keep the LLM/IO out of the assertion path):

```ts
// "ci/content-publisher-2026-05-19-164226" -> "scheduled-content-publisher"
// Returns null for any head that does not reverse-derive a clean cron name
// (e.g. self-healing/auto-*, or a hand-renamed ci/ branch). A null label means
// "comment channel unknown" -> Sentry-only (the warn still fires).
export function scheduledLabelFromHead(headRef: string): string | null;

// stale = open, head matches a BOT_PR_HEAD_PREFIXES entry, created_at strictly
// older than STALE_BOT_PR_THRESHOLD_MS, AND NOT (draft && labels∋"self-healing/auto").
export function isStaleBotPr(pr: BotPrLite, nowMs: number): boolean;
```

- `scheduledLabelFromHead`: if `ci/` → strip prefix, strip trailing `/-\d{4}-\d{2}-\d{2}-\d{6}$/`, return `scheduled-${rest}` (rest non-empty); else (incl. `self-healing/auto-`) → `null`. The `$`-anchored timestamp strip correctly leaves digit/hyphen cron names intact (`ci/nag-4216-readiness-2026-…` → `scheduled-nag-4216-readiness`).
- `BotPrLite` = `{ number, head: { ref }, created_at, draft, labels: { name }[], html_url }` (the subset of the pulls payload used).

**Edge cases to encode in helpers (not deferred):**
- Threshold is **strictly greater than** 48h (`age > THRESHOLD`, not `>=`). Boundary tested at 47h59m (not stale) and 48h01m (stale).
- **Unparseable/absent `created_at`** → `isStaleBotPr` returns `false` (do NOT throw — mirror the existing `Number.isNaN(Date.parse(...))` guard at `cron-cloud-task-heartbeat.ts:162-165`; a malformed payload field must not dark the whole scan via the `stale-bot-pr-scan-failed` catch).
- A `ci/` branch whose suffix is not a timestamp → `scheduledLabelFromHead` returns `scheduled-<whole-rest>`, which likely has no open issue → Sentry-only fallback (acceptable; the warn still fires).

**Latent coupling note (Kieran P2-1):** the reverse-derivation assumes `cronName.replace("cron-","")` === `scheduledIssueLabel.replace("scheduled-","")`. This holds for all 12 current callers (each sets `scheduledIssueLabel` to its `SENTRY_MONITOR_SLUG` stem === branch stem). If a future cron's slug diverges from its name stem, the comment lands on no label → degrades gracefully to Sentry-only (`commentOnScheduledIssue` already handles the empty case). No guard needed; documented so a future diverging cron is understood, not surprising.

### Phase 2 — Scan step (`check-stale-bot-prs`)

New `step.run("check-stale-bot-prs", …)` AFTER the existing `check-task-silence` step, reusing `installationToken`. Returns `StaleBotPr[]` (`{ number, head, ageHours, scheduledLabel, htmlUrl }`).

- Paginate `GET /repos/{owner}/{repo}/pulls` with `state: "open"`, `sort: "created"`, `direction: "asc"`, `per_page: 100`, `headers: { "X-GitHub-Api-Version": "2022-11-28" }`. Precedent: `cron-bug-fixer.ts:225` (pulls list, `per_page:100`) and `_cron-safe-commit.ts:629`.
- **Efficient early-exit (this IS the scan bound — no page cap needed):** ascending-by-created means oldest first — once a returned PR's `created_at` is newer than `now - THRESHOLD`, no later PR can be stale → break out of pagination immediately. `created_at` is immutable, so the order is monotonic (a re-opened/updated PR does NOT re-sort; sort key is `created`, not `updated`). This reads exactly the PRs older than 48h (≈0 bot PRs in steady state) and stops. Add a one-line comment at the `break` stating the invariant (the loop silently terminates on the first non-stale PR; a future `updated_at`-based threshold would need a different bound).
- Manual page loop (no `@octokit/plugin-paginate-rest` — not a dependency; `@octokit/core` raw `request` per the file's existing pattern): increment `page`, terminate on `data.length < per_page` OR the early-exit above. **No `MAX_BOT_PR_PAGES` cap, no truncation warn** — the early-exit makes a 1000-stale-PR runaway unreachable in any realistic state (and that state would be a five-alarm repo emergency surfaced elsewhere long before this watchdog); guarding it is the YAGNI the plan-review panel cut.
- Wrap the whole scan in try/catch → `reportSilentFallback(op: "stale-bot-pr-scan-failed")` on API error and return `[]` (a scan failure must NOT throw the step into a retry that flips the heartbeat monitor; Sentry is the signal). This is the ONE real failure mode the cap was pretending to cover.
- Use `isStaleBotPr(pr, Date.now())` for the filter.

### Phase 3 — Handling step (`stale-bot-pr-handling`)

New `step.run("stale-bot-pr-handling", …)` after Phase 2, before the existing `sentry-heartbeat` step. For each `StaleBotPr`:

1. **Sentry warn (always):** `warnSilentFallback(null, { feature: "cron-cloud-task-heartbeat", op: STALE_BOT_PR_WARN_OP, message: "Bot PR open past staleness threshold", extra: { fn: "cron-cloud-task-heartbeat", pr_number, head_ref, age_hours, owning_cron, html_url } })`. Stable `message` (per-PR detail in `extra`) so Sentry groups one issue; the `.tf` alert filters on `op:stale-bot-pr` so grouping does not suppress routing.
2. **Owning-issue comment (best-effort, deduped):** if `scheduledLabel !== null`, resolve the most-recent OPEN `scheduled-<name>` issue (same `GET …/issues?labels=…&state=open&sort=created&direction=desc&per_page=1` shape as `commentOnScheduledIssue`). Before commenting, **dedup**: list that issue's recent comments and skip if one already carries the hidden marker `<!-- stale-bot-pr:<prNumber> -->` (prevents daily re-spam on a multi-day-stuck PR — kept because Soleur operators are non-technical and a daily nag-comment is net-negative noise; DHH plan-review dissented as YAGNI, simplicity-reviewer kept it as intrinsic to "comment"). Otherwise POST a comment whose body includes the marker, the PR link, age, and a one-line "auto-merge likely disarmed on conflict — rebase or close" plus a link to the runbook §"Stale bot PR". Comment/list failures → `reportSilentFallback(op: "stale-bot-pr-comment-failed")`, never throw.
3. If `scheduledLabel === null` OR no open labeled issue exists → Sentry-only (the warn from step 1 already covers it); no comment.

**Do NOT** touch the existing `ok`/`silentCount` computation — keep the heartbeat monitor semantics unchanged (`ok = silentCount === 0`, from task-silence only). **No `staleBotPrCount` return field** (cut at plan-review — it would be production-dead surface added only for a test to read; Scenarios 4/5/8 assert on the `warnSilentFallback`/comment-POST spies and the unchanged `ok`/`silentCount`, which already gate the behavior).

### Phase 4 — Sentry alert routing (IaC)

Add `resource "sentry_issue_alert" "stale_bot_pr"` to `apps/web-platform/infra/sentry/issue-alerts.tf` (filter `feature` = `cron-cloud-task-heartbeat` AND `op` = `stale-bot-pr`, `filter_match = "all"`, `notify_email { target_type = "IssueOwners", fallthrough_type = "ActiveMembers" }`, `frequency = 14`). See `## Infrastructure (IaC)`.

### Phase 5 — Runbook

Add a `## Stale bot PR` section to `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md`: what the `stale-bot-pr` warn / scheduled-issue comment means (auto-merge silently disarmed on conflict, or a `direct` pipeline that fell back and stalled), and the operator action (inspect the `ci/<name>-*` PR → rebase to resolve the conflict and let auto-merge re-fire, or close it). No-SSH; all steps via `gh`.

> **ADR-054 status note (1-line edit, not a phase — folded into Files to Edit):** append "Resolved by PR #&lt;this&gt; (#5138)" under ADR-054's `## Consequences` "Deferred: the stale-`ci/*` bot-PR watchdog (#5138)" bullet. Status update only; does not rewrite the decision.

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-cloud-task-heartbeat.ts` — constants, `scheduledLabelFromHead`, `isStaleBotPr`, `check-stale-bot-prs` step, `stale-bot-pr-handling` step (no return-shape change — `ok`/`silentCount` untouched).
- `knowledge-base/engineering/architecture/decisions/ADR-054-safe-commit-and-pr-sole-write-path-for-bot-cron-prs.md` — 1-line "Resolved by PR #&lt;this&gt; (#5138)" annotation under the deferred-watchdog Consequences bullet.
- `apps/web-platform/test/server/inngest/cron-cloud-task-heartbeat.test.ts` — extend (existing file is already collected by vitest's `test/**/*.test.ts` glob; do NOT create a new co-located test).
- `apps/web-platform/infra/sentry/issue-alerts.tf` — `sentry_issue_alert.stale_bot_pr`.
- `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` — `## Stale bot PR` section.

## Files to Create

None (extending existing surfaces).

## Test Scenarios

Extend `cron-cloud-task-heartbeat.test.ts` (vitest; run `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-cloud-task-heartbeat.test.ts`). The LLM is not in the path; all assertions drive the exported helpers / handler directly with mocked Octokit + spied observability.

1. **`scheduledLabelFromHead` mapping:** `ci/content-publisher-2026-05-19-164226` → `scheduled-content-publisher`; `ci/rule-prune-2026-06-01-093000` → `scheduled-rule-prune`; `self-healing/auto-abc123-2026-06-01` → `null`; `ci/manual-rename` (no ts suffix) → `scheduled-manual-rename`.
2. **`isStaleBotPr` threshold boundary** (use `vi.setSystemTime` for a fixed `nowMs`): 47h59m-old `ci/*` PR → false; 48h01m-old → true; non-bot head (`feature-foo`) at 100h → false. Also: a `ci/*` PR with a malformed/absent `created_at` → false (does not throw).
3. **Exclusion:** 72h-old `self-healing/auto-*` PR that is `draft && labels∋"self-healing/auto"` → false; same PR **non-draft** → true (the exclusion is draft-AND-label, not prefix alone).
4. **Warn emission:** a stale PR drives exactly one `warnSilentFallbackSpy` call with `op: "stale-bot-pr"` and `extra.pr_number`.
5. **Comment dedup:** when the owning issue already has a comment containing `<!-- stale-bot-pr:<n> -->`, no new comment POST is issued; when absent, one POST with the marker.
6. **No labeled issue → Sentry-only:** `scheduledLabel` resolves but `GET …/issues` returns `[]` → no comment POST, warn still fired (no throw).
7. **Scan API failure:** `octokitRequestSpy` rejects on the pulls list → `reportSilentFallbackSpy` called with `op: "stale-bot-pr-scan-failed"`, handler still returns, `ok` unaffected by bot-PR path.
8. **Heartbeat orthogonality:** a run with a stale bot PR but zero silent tasks returns `ok: true` / `silentCount: 0` (bot-PR staleness must not flip the monitor).
9. **Pagination early-exit:** mocked two pages where page 1 ends with a PR newer than threshold → page 2 is never requested (assert octokit call count). (No truncation-cap test — cap was cut.)
10. **Source-shape anchors** (readFileSync, matching existing style): file contains `STALE_BOT_PR_THRESHOLD_MS`, `op: "stale-bot-pr"` (or `STALE_BOT_PR_WARN_OP`), and the two new `step.run` ids.

## Open Code-Review Overlap

None — no open `code-review`-labeled issue references `cron-cloud-task-heartbeat.ts`, `issue-alerts.tf`, or the runbook (re-verify at /work via the Phase 1.7.5 query before freezing).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal infrastructure/observability change (Inngest cron + Sentry alert + runbook). No UI surface, no user-facing artifact, no legal/marketing/finance/sales/support/product implication.

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/sentry/issue-alerts.tf` — new `resource "sentry_issue_alert" "stale_bot_pr"`. Provider `jianyuan/sentry` (already pinned in `versions.tf`). No new providers, no new secrets/`TF_VAR_*`.
- Mirror an **apply-created** sibling with a real body — `kb_db_error` / `egress_blocked` (NOT the 4 import-only `auth_*` placeholder rules): `filter_match = "all"`, a `tagged_event` filter on `feature == cron-cloud-task-heartbeat` AND a second on `op == stale-bot-pr`. **Action (Kieran P1-1 — there is no email variable in the repo):** `actions_v2 = [{ notify_email = { target_type = "IssueOwners", fallthrough_type = "ActiveMembers" } }]`, exactly as every sibling alert routes (`issue-alerts.tf:59-66`); do NOT introduce a `var.operator_email` / `target_type = "Member"`.
- **Concrete `frequency` (Kieran P1-2):** the `action_match = "any"`-shaped taken set is `{5, 10, 11, 12, 13, 30}`. Use **`frequency = 14`** (free). Rationale: the provider/back-end dedups `sentry_issue_alert` on `hash(action_match + filter_match + frequency + actions_v2-shape)`, NOT on conditions (`2026-05-17-sentry-issue-alert-create-dedup-on-action-match-not-conditions`); a colliding frequency silently merges the POST. Put this in a `.tf` comment.

### Apply path
- (b) cloud-init + bootstrap is N/A; this is config on an existing live root. The new rule is **apply-created with a real body** (like `kb_db_error`), so `terraform validate` passes cleanly under `jianyuan/sentry 0.15.0-beta2` (the apply-created siblings already validate in the live file) — it does NOT need the import-only minimal-placeholder treatment. The provider deprecation *warning* at `issue-alerts.tf:16-39` is emitted but non-fatal to `validate`.
- `terraform-architect` (deepen-plan Phase 2.8 / 4.4) wires a scoped `-target=sentry_issue_alert.stale_bot_pr apply` into the existing `apply-sentry-infra.yml` so no manual `terraform apply` is prescribed (`hr-all-infrastructure-provisioning-servers`). Forbid expanding this into a workflow refactor — mirror the sibling, change two filter tags + frequency, stop.
- Expected blast radius: one new alert rule; zero change to existing monitors/alerts. No downtime.

### Distinctness / drift safeguards
- `dev != prd`: Sentry infra is prd-only (single Sentry org). No dev/prd split needed for this resource.
- Secret values: none added; the rule references existing notify targets. No new value lands in `terraform.tfstate`.

### Vendor-tier reality check
- `sentry_issue_alert` is available on the current paid Sentry tier (sibling alerts `auth_*`, `kb_db_error`, `byok_*` already exist on it). No tier gate needed.

## Observability

```yaml
liveness_signal:
  what: the watchdog rides the EXISTING cron-cloud-task-heartbeat run
  cadence: daily (30 9 * * *)
  alert_target: existing Sentry cron monitor (slug scheduled-cloud-task-heartbeat)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf (UNCHANGED — no new monitor; bot-PR staleness does not flip ok)
error_reporting:
  destination: Sentry via reportSilentFallback (op stale-bot-pr-scan-failed, op stale-bot-pr-comment-failed) + pino stdout mirror
  fail_loud: yes — scan/comment failures mirror to Sentry; they do NOT throw the step (no monitor flip) by design
failure_modes:
  - {mode: GitHub pulls list API error, detection: reportSilentFallback op stale-bot-pr-scan-failed, alert_route: Sentry issue (searchable)}
  - {mode: stale bot PR detected, detection: warnSilentFallback op stale-bot-pr, alert_route: sentry_issue_alert.stale_bot_pr notify_email IssueOwners -> operator}
  - {mode: owning-issue comment failed, detection: reportSilentFallback op stale-bot-pr-comment-failed, alert_route: Sentry issue (searchable)}
logs:
  where: container stdout -> Better Stack (pino mirror inside report/warnSilentFallback)
  retention: platform default (Better Stack)
discoverability_test:
  command: 'gh api "/repos/jikig-ai/soleur/pulls?state=open&per_page=100" --jq ''[.[] | select(.head.ref|startswith("ci/") or (.head.ref|startswith("self-healing/auto-")))] | length'''
  expected_output: integer count of open bot PRs (the watchdog''s input set); Sentry search "feature:cron-cloud-task-heartbeat op:stale-bot-pr" surfaces fired warns — both reachable with no ssh
```

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `scheduledLabelFromHead` + `isStaleBotPr` exported and unit-tested per Test Scenarios 1-3 (threshold strict-greater-than, draft-AND-label exclusion).
- [ ] Stale PR → exactly one `warnSilentFallback` with `op: "stale-bot-pr"` (Scenario 4).
- [ ] Owning-issue comment is deduped by the `<!-- stale-bot-pr:<n> -->` marker (Scenario 5) and falls back to Sentry-only when no labeled open issue exists (Scenario 6).
- [ ] Scan API failure → `reportSilentFallback` op `stale-bot-pr-scan-failed`, no throw, `ok` unaffected (Scenario 7).
- [ ] Heartbeat orthogonality: stale bot PR does NOT change `ok`/`silentCount` (Scenario 8).
- [ ] Pagination early-exits on first newer-than-threshold PR (Scenario 9).
- [ ] `sentry_issue_alert.stale_bot_pr` added with a distinct `frequency`; `cd apps/web-platform/infra/sentry && terraform validate` passes.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; `./node_modules/.bin/vitest run test/server/inngest/cron-cloud-task-heartbeat.test.ts` green.
- [ ] `function-registry-count.test.ts` unchanged (no new cron) — confirm it still passes.
- [ ] Runbook `## Stale bot PR` section added; ADR-054 resolved-annotation added.
- [ ] PR body uses `Closes #5138`.

### Post-merge (operator/automation)
- [ ] Sentry alert rule applied via the scoped `apply-sentry-infra.yml` path (no manual `terraform apply` — wired in Phase 4 / deepen-plan IaC).
- [ ] First daily run after merge: `gh` discoverability command returns a count; if any `ci/*` PR is currently >48h old, confirm a `stale-bot-pr` warn fired and the owning issue got one (deduped) comment.

## Risks & Mitigations

- **Listing all open PRs is expensive.** Mitigated by the ascending-created early-exit alone (scan stops at the first non-stale PR); bot PRs older than 48h are ~0 in steady state. The page cap + truncation warn were cut at plan-review as unreachable-state YAGNI.
- **Daily comment spam on the owning issue.** Mitigated by the `<!-- stale-bot-pr:<n> -->` dedup marker; Sentry dedups the warn by fingerprint.
- **False positives on legitimate long-lived bot PRs.** Only compound-promote uses `self-healing/auto-*` and it is draft+labeled → excluded. `ci/*` PRs are auto-merge/direct outputs that should never sit open >48h; one open >48h IS the signal.
- **Sentry alert silently merged at POST** (dedup-on-action-shape). Mitigated by the distinct-`frequency` requirement in `## Infrastructure (IaC)`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6 — this one is filled (threshold `none` + sensitive-path scope-out reason).
- Test path MUST stay in `apps/web-platform/test/**/*.test.ts` (vitest `include`); a co-located `*.test.ts` next to the cron is silently never run.
- Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (the repo root has no `workspaces` field; `npm run -w` aborts).
- `@octokit/core` raw `request` does not auto-paginate — the manual page loop is load-bearing; do not assume one `per_page:100` page covers all open PRs.
