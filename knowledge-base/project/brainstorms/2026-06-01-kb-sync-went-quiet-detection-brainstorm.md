---
title: "KB sync went-quiet detection (time-based / push-correlation stale arm)"
date: 2026-06-01
issue: 4717
parent_issue: 4706
predecessor_issue: 4712
lane: cross-domain
brand_survival_threshold: single-user incident
status: complete
---

# Brainstorm — KB sync went-quiet detection (#4717)

## What We're Building

A third arm on the daily `cron-workspace-sync-health` scan that catches the
**went-quiet** class: a workspace that is `repo_status='ready'` **and**
`github_installation_id IS NOT NULL` whose webhook pushes have simply **stopped
arriving**. Because no push arrives, the reconcile handler never runs, so it
writes **zero** new `kb_sync_history` rows — its latest row stays `ok:true`
forever and the workspace looks perfectly healthy while its KB silently rots.

The two arms already shipped in #4712 cannot see this:
- **Arm 1 (NULL-install):** catches `ready ∧ github_installation_id IS NULL`
  (writes zero rows because it never matches the reconcile filter).
- **Arm 2 (failure-based):** catches `ready ∧ installed ∧ latest row ok:false`
  (a recorded failure).

Went-quiet is neither — it is `ready ∧ installed ∧ latest row ok:true ∧ no new
rows`. The detector flags it as: **`(repo's latest GitHub push) > (last ok:true
sync) + slack` AND `(now − last ok:true sync) > N days`**. The AND-clause is the
whole point — it suppresses the idle-repo false positive (a repo with no recent
commits legitimately has no syncs, so it never fires).

## Why This Approach

The independent "a push was attempted" signal **cannot** come from
`kb_sync_history` — that is exactly the record went-quiet erases. It must come
from outside: GitHub's own record of repo activity, read via the
installation token. Chosen call: **`GET /repos/{owner}/{repo}` → `pushed_at`**
(one field, one call, captures any-branch push) — *not* `GET /commits`
(paginated, returns bodies). `pushed_at` (any branch) is the safer correlation
for a p3: a default-branch-only read could false-negative on a feature-branch
pusher, and missing a real quiet is the safer error than crying wolf.

This satisfies the operator's **"All"** user-impact framing: it catches the
missed-freeze class (the parent #4706 incident — the founder's own KB froze ~5
weeks) **and** holds false-positive suppression as a hard requirement (the
reason NG3 deferred the naive time-only threshold in the first place).

### Approaches considered

- **A — GitHub commit-correlation (CHOSEN).** `pushed_at` vs `last ok:true` +
  time threshold. Authoritative push signal; structurally suppresses idle-repo
  false positives. ~1 API call / ready+installed workspace / day, ~0.1% of the
  5000/hr installation ceiling at current scale. Cost: a workspaces↔owner-history
  join and a multi-workspace-per-owner ambiguity (scoped out for MVP — see below).
- **B — Pure time-threshold (rejected).** Flag any latest `ok:true` older than N
  days, no GitHub query. Cheapest, but this *is* the design NG3 deferred — it
  fires on idle repos and re-introduces the alert-fatigue worst-case the operator
  flagged. Weakest signal.
- **C — Webhook-delivery health (rejected).** Query the GitHub App's
  `/app/hook/deliveries` to detect delivery failure at the root cause. Sharper at
  root-cause but app-level/coarser, heavier (JWT + pagination across all installs),
  and misses the delivered-but-matched-zero-workspaces silent path. Over-engineered
  for a p3.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Signal source | GitHub commit-correlation (Approach A) | Only option that satisfies the false-positive-suppression hard requirement |
| GitHub call | `GET /repos/{owner}/{repo}` → `pushed_at` (any branch) | One field, one call; any-branch is the safer (false-negative-leaning) error for p3 |
| owner/repo source | Parse from each `workspaces.repo_url` | `_cron-shared` `REPO_OWNER`/`REPO_NAME` are constants for Soleur's OWN repo — reusing them would probe the wrong repo |
| Token minting | Per-installation, dedupe by `github_installation_id` | Per-workspace minting would make token-mint the real cost |
| Join | `workspaces.github_installation_id` → owner via `workspace_members(role='owner')` → `users.kb_sync_history` | Mirrors the reconcile writer's owner attribution |
| Multi-workspace scope (MVP) | Evaluate **single-workspace owners only**; skip-and-count the rest in the heartbeat return | `kb_sync_history` has no `workspace_id`; `sha_after` is not a reliable discriminator. Honest known-limitation, not a silent gap |
| Output surface | Ops-only Sentry `reportSilentFallback` (op `went-quiet`, workspace UUID only) | Consistent with both sibling arms (FR8/NG2); a per-workspace GitHub issue = unbounded cardinality + leaks customer workspace IDs |
| Threshold N | **3 days**, env-overridable `KB_WENT_QUIET_MAX_GAP_DAYS` | Cadence + one-cycle slack; mirrors `community-monitor` `maxGapDays: 3`; the AND-clause carries the precision |
| Freshness slack | small constant (≥ a few minutes) | Absorbs reconcile latency so a just-synced push doesn't false-fire |
| Function placement | Extend `cron-workspace-sync-health.ts` in-place | Same "ready workspace, different failure mode" family as the failure-based arm; no new fn, no migration |
| ADR | None | No new service / data-model / tech choice |

## Open Questions

- **Any-branch vs default-branch `pushed_at`:** MVP uses any-branch `pushed_at`
  (safer false-negative-leaning error). Revisit only if a chatty non-default
  branch produces nuisance signal.
- **Multi-workspace owners:** out of scope for MVP. The correct fix is a
  `workspace_id` column on the `kb_sync_history` row (a schema change) — deferred
  (see deferred item below). Until then they are skipped-and-counted.

## Domain Assessments

**Assessed:** Engineering (CTO — focused refresh), Product (CPO — carry-forward), Legal (CLO — carry-forward)

### Engineering (CTO)

**Summary:** Extend the existing cron in-place (no new fn, no migration, ~hours of work). Use `GET /repos/{owner}/{repo}.pushed_at` parsed from each workspace's own `repo_url`; mint tokens per-installation. Scope MVP to single-workspace owners to eliminate the no-`workspace_id` mis-attribution class entirely; skip-and-count the rest. Keep ops-only Sentry. N=3 days env-overridable. All IO inside `step.run`; gate the GitHub calls in their own step so a token/API failure cannot poison the two existing arms; extend `ScanResult` with a `wentQuiet` array; heartbeat `ok` reflects scan-ran not findings-present. No ADR, no capability gaps.

### Product (CPO — carry-forward from #4712 spec)

**Summary:** Ops-only signal; no user-facing surface (NG2). The user-facing reconnect affordance shipped as item 1 in #4712 already covers the in-product remediation path; went-quiet detection is the loud-ops complement. Inherits `Brand-survival threshold: single-user incident` (the parent #4706 freeze was a single-user brand incident).

### Legal (CLO — carry-forward from #4712 spec)

**Summary:** No statutory clock / DPA trigger. Reading repo `pushed_at` via the installation token is already-authorized repo metadata access — no new PII surface. Sentry logging stays workspace-UUID-only (no repo name/path/owner handle), consistent with the failure-based arm.

## User-Brand Impact

- **Artifact:** a user's Knowledge Base (the synced repo content the user reads/acts on).
- **Vector (missed-freeze):** a went-quiet workspace is NOT caught → KB silently stale for weeks → user acts on outdated context. This is the parent-incident class (#4706, founder's KB froze ~5 weeks).
- **Vector (false-positive fatigue):** detector over-fires on idle repos → operator learns to ignore went-quiet alerts → a real freeze is buried in noise. Suppressed structurally by the GitHub-push AND-clause + single-workspace-owner scope.
- **Threshold:** `single-user incident` (operator selected "All" at Phase 0.1).

## Capability Gaps

None. Existing Inngest cron + Octokit + `reportSilentFallback` patterns cover this. Evidence: `git grep` confirmed `cron-workspace-sync-health.ts` already hosts two arms; `_cron-shared.ts` exports `mintInstallationToken`/`postSentryHeartbeat`; `workspace-reconcile-on-push.ts` lines 241-247 establish the owner-attribution join; migration `079_workspace_repo_ownership_schema.sql` confirms `workspaces.repo_url`/`repo_status`/`github_installation_id`.

## Session Notes

- Premise probe: #4712 (deferred-from) is CLOSED via PR #4716; #4706 (parent) MERGED; the worktree branched from the #4716 merge so both shipped arms are in-tree. Premise is ripe, not stale.
- **[Updated 2026-06-01 — plan-review pivot]** This brainstorm's design (workspace-centric scan, `workspace_members` join, single-workspace-owner MVP, `pushed_at` any-branch) was **revised at plan-review**. `users` already carries `repo_url` on the same row as `kb_sync_history` (mig 011), and arm 2 already scans `users`, so the implementation is **users-centric** (mirrors arm 2 → genuine mutual exclusivity, no join, no scope cut). The GitHub signal switched from repo `pushed_at` (any-branch → false-positive-prone) to the **default-branch HEAD commit date** (`GET /commits?per_page=1`). The single-workspace-owner concern dissolved; #4728 (per-workspace `workspace_id`) remains valid orthogonal future work. Authoritative design: the plan's `## Plan-Review Resolutions` table.
