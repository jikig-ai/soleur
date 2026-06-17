---
title: "Column-relocation reader sweeps must be multi-line-aware; an injected resolver's filter needs a DIRECT unit test (mocking it in every consumer is vacuous)"
date: 2026-06-17
category: best-practices
module: apps/web-platform
tags: [adr-044, reader-sweep, multi-line-grep, resolver-testing, mock-vacuity, review-catches]
issue: 5437
pr: 5482
---

# Learning: two verification gaps that ship green through a column-relocation cutover

## Problem

PR #5482 (ADR-044 PR-2b precondition) cut the GitHub-webhook founder reverse-lookup
and the session-sync write off `users.github_installation_id` onto a workspaces
solo-founder resolver. Two gaps survived implementation + the plan's own ACs and were
caught only at multi-agent review:

1. **The reader sweep missed a 4th stranded reader.** The plan's AC + R2 grep was
   `git grep -nE 'select\([^)]*github_installation_id'` — **single-line**. But
   `app/(dashboard)/dashboard/settings/page.tsx` had a MULTI-LINE select:
   ```ts
   .select(
     "repo_url, repo_status, repo_last_synced_at, github_installation_id",
   )
   ```
   The `select(` and the column are on different lines, so the `[^)]*` line-anchored
   pattern never matched. The PR's headline claim ("PR-2b's DROP is unblocked") was
   FALSE — dropping the column would have thrown on the settings render. This is the
   SAME failure the ADR itself documented for the webhook `.eq` lookup ("missed by the
   original `.select(…)` grep"), recurring one cutover later.

2. **A new injected resolver's load-bearing filter had ZERO direct test.** Every
   webhook test mocked `resolveSoloFounderForInstallation` wholesale
   (`vi.mock(...); mockResolveFounder.mockResolvedValue({kind:"ambiguous"})`), so the
   route's branch-handling was tested but the resolver's actual solo self-join +
   team-exclusion (`m.user_id === row.id`) + `>1`-counting filter — the brand-survival
   cross-tenant-misattribution defense — was never executed. Scenarios "3/4/11" asserted
   the resolver's verdict via the mock, not its logic. A regression dropping the
   `m.user_id===row.id` check (→ team-row misattribution) would have shipped green.

## Solution

1. **Run the column-relocation reader sweep with a MULTI-LINE-aware tool**, not a
   single-line `git grep`:
   ```bash
   rg -nU 'from\("users"\)[\s\S]{0,400}?github_installation_id' apps/web-platform/{app,server,lib} | grep -v github_username
   ```
   `rg -U` (multiline) catches the `.select(\n  "...col...",\n)` shape that
   `git grep -nE 'select\([^)]*col'` is structurally blind to. Treat the single-line
   grep as necessary-but-not-sufficient; the authoritative "all readers gone" check is
   the multiline sweep over a 400-char window from `from("users")`.

2. **A new resolver with non-trivial filtering MUST have a direct unit test that
   exercises the filter against realistic data-shaped input** — not just consumer tests
   that mock the resolver. Mock only the supabase chain (shaped as the real `!inner`
   embed returns: `{ id, workspace_members: [{user_id, role}] }`) and assert the
   resolver's OWN discriminated-union output across found / team-excluded / ambiguous /
   none / db-error. The whole point of a resolver that diverges from precedent (here:
   `>1`-ambiguous instead of `.maybeSingle()`) is the divergent logic; it is exactly
   what must be tested directly.

## Key Insight

When relocating a column across tables, the two cheapest-to-skip verifications are the
two that matter most: (a) the reader sweep is only as complete as its grep is
multi-line-aware, and (b) a new resolver fronting the relocated read is only as safe as
its DIRECT test — consumer tests that mock it prove the wiring, never the filter. Both
gaps pass `tsc` + the full unit suite + the plan's own line-anchored ACs; only an
orthogonal reviewer reading the actual files catches them. Multi-agent review earned its
keep here (settings reader: 1 agent; resolver-untested: 3 concurring agents).

## Session Errors

1. **Reader sweep missed multi-line select (settings/page.tsx)** — Recovery: migrated it
   to a workspaces read (mirroring repo/status route); re-ran a multiline `rg -U` sweep =
   0 live `users` readers. **Prevention:** this learning — use `rg -nU` for relocation
   sweeps; single-line `git grep` is blind to multi-line selects.
2. **New resolver untested (all consumers mock it)** — Recovery: added
   `test/server/resolve-founder-for-installation.test.ts` (faithful embed-shaped mock; 6
   cases incl. team-exclusion + >1-ambiguous; verified non-vacuous). **Prevention:** this
   learning — direct unit test for any injected resolver's filter.
3. **`founder-ambiguous` paging asserted (ADR R8) but not wired** — Recovery: added the
   `github_webhook_founder_ambiguous` Sentry issue-alert rule (mirroring the
   workspace-sync-health rule). **Prevention:** covered by `hr-observability-as-plan-quality-gate`
   (an asserted paging mitigation must have the alert rule in the same PR); the
   discoverability gate should grep the Sentry alert .tf for the asserted op tag.
4. **AC3b grep returned 7 not 0** — Recovery: confirmed all 7 hits are workspaces
   reads/tests/comments (the `.from("workspaces")` line precedes `.select(...)`), zero
   live `users` readers. **Prevention:** subsumed by item 1 (the substantive check is the
   multiline `users`-scoped sweep, not a column-name count).
5. **nav-states structural-UI gate env-blocked** — Recovery: attempted both
   `playwright install chromium-headless-shell` and `playwright install chromium`; both
   fail "Playwright does not support chromium on ubuntu26.04-x64". Delegated to CI's
   containerized e2e (authoritative, green on main); the change is a server-side
   data-source swap with no markup/CSS change. **Prevention:** env/OS limitation (this
   machine), not project debt; QA skill already documents the nav-states local-flake class.

## Tags
category: best-practices
module: apps/web-platform
