---
title: "fix(observability): restore drift-guard issue trail (issues:write), clear members:read drift, harden realtime monitor"
type: fix
date: 2026-05-28
issue: 4189
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
related_issues: [4189, 4179, 4173, 4115, 4121, 4235, 4211, 3187, 3060, 3236]
related_prs: [4546, 4226, 4174]
---

# fix(observability): restore drift-guard issue trail + clear members:read drift + harden realtime monitor

## Enhancement Summary

**Deepened on:** 2026-05-28
**Sections enhanced:** Hypothesis Verification, Acceptance Criteria (AC4, AC14), Precedent-Diff, Research Insights
**Verification passes run:** deepen gates 4.6/4.7/4.8 (all PASS); cited-line audit; PR/issue live-check; parity-test-scope audit; manifest-diff direction audit; precedent-diff (scheduled-work pattern); verify-the-negative pass.

### Key Improvements (caught at deepen-pass)

1. **AC4 op-name drift caught.** Plan v1 said "preserve `op: handleIssue`" for BOTH crons; verified `cron-oauth-probe.ts:637` actually uses `op: "handleTrackingIssue"`. AC4 corrected to preserve each cron's own op string.
2. **`.status` lost through `redactedError` caught (verify-the-negative).** The drift-guard wraps `err` via `redactedError(err)` (`:139-148`) which returns a fresh `Error` WITHOUT `.status` when the message matches the leak regex. The 403 discriminator MUST read `err.status` from the ORIGINAL error before the wrap, else the discriminator silently never fires. AC4 now pins this ordering.
3. **AC14 Sentry-API field name de-fabricated.** Removed the unverified `.config.checkin_margin` jq path (no Sentry token loaded this session); /work must confirm the exact key against one live response. The TF attribute `checkin_margin_minutes` is verified; the API JSON key is not.
4. **Cited lines + citations all live-verified.** Every `file:line` in Hypothesis Verification re-grepped (drift-guard catch :801-811, oauth catch :635-641, POST /issues :591/:510, `op?` :109, manifest `issues:read` :23, realtime monitor :157-167). #4189 confirmed OPEN with the exact "[ci/auth-broken] GitHub App drift-guard fired" title; #4179/#4235 closed; #4546/#4226 merged.

### New Considerations Discovered

- **Broader beneficiary set confirmed live.** `cron-stale-deferred-scope-outs.ts:296` and `cron-community-monitor.ts:49` ALSO write issues via `createProbeOctokit()` and 403 under `issues:read` — the `issues:write` grant fixes all four crons at once (the plan already notes this; deepen-pass confirmed it empirically via grep). `cron-nag-4216-readiness.ts` uses a raw-token Octokit, so it is unaffected.
- **Parity test scope audited:** the test value-checks only `administration === "write"` (`:101`); `issues` is checked as a KEY only (`:56`). Bumping `issues`→write is safe; dropping `members` requires the `EXPECTED_PERMISSION_KEYS` edit (AC3). No hidden value-assertion on `issues` or `members`.

### Precedent-Diff (Phase 4.4)

- **Scheduled-work pattern:** No new scheduled job is introduced — this fix edits existing crons (Inngest, ADR-033-canonical) and an existing GHA-fired probe; the `cron-monitors.tf` edit is a field change on an existing resource. The scheduled-work pattern check does not fire.
- **Sentry-monitor field precedent:** `checkin_margin_minutes = 180` already used by `scheduled_terraform_drift` (:53) and `scheduled_gh_pages_cert_state` uses 240 (:230) for GHA-fired daily monitors. Raising the realtime probe to 1440 is consistent with the "GHA-fired daily cadence absorbs scheduler jitter" precedent the file already documents (header :17-22, :220-222) — just sized larger because GitHub dropped a WHOLE run (24h), not jitter.

🐛 Three coupled cron-monitor observability fixes surfaced by the 2026-05-28
Better Stack/Sentry alerts. Fixes 1 and 2 both mutate the GitHub App permission
manifest and share one operator re-consent gate, so they ship as ONE PR. Fix 3
is an independent one-line Terraform widen and could split, but is folded into
the same PR for atomic operator-action accounting (one re-consent click covers
1+2; fix 3 needs no operator action).

## Overview

Since the GitHub-App drift-guard was migrated from a GitHub Actions workflow to
an Inngest cron (PR #4235, merged 2026-05-22), the hourly cron posts `error`
Sentry heartbeats but has filed/commented **zero** GitHub issues — the last
comment on the open drift-guard tracking issue (#4189) was 2026-05-22 21:16 UTC,
the final pre-migration GHA run. Root cause (verified below): the migrated cron
writes issues via `createProbeOctokit()` (installation-scoped App token), and the
App manifest at `apps/web-platform/infra/github-app-manifest.json` declares
`"issues": "read"`. Every `POST /repos/{owner}/{repo}/issues` and `POST .../comments`
returns 403 and is caught by `reportSilentFallback` — which DOES mirror to Sentry
(`cq-silent-fallback-must-mirror-to-sentry` is satisfied at `level: "error"`), but
the operator-facing GitHub-issue trail went dark.

Fix 1: bump `issues: read → write` in the manifest so the drift-guard (and the
sibling crons that share the same blind spot) can file/comment again; loudness is
already satisfied (Sentry error mirror) but is upgraded with an explicit
`op: "issue_write_403"` discriminator and a runbook note so the operator gets an
actionable signal even before the re-consent completes.

Fix 2: drop `members: read` from the manifest — it is unused by any code (Soleur's
team/workspace features read Supabase `workspace_members`, not GitHub org membership;
see Research Reconciliation). Dropping it clears the `installation_permission_drift`
(`missing_perms {"members":"read"}`) that has kept #4189 open since 2026-05-20 with
zero operator action.

Fix 3: widen `sentry_cron_monitor.scheduled_realtime_probe`'s grace so a dropped
GitHub-scheduler run stops paging — the 2026-05-28 "missed check-in" fired because
GitHub dropped the 05-26 scheduled run entirely (a known GitHub Actions scheduler
reliability gap), not because the probe is broken.

## Hypothesis Verification (done at plan-write time)

| Hypothesis | Verification | Verdict |
|---|---|---|
| Manifest declares `issues: read` | `github-app-manifest.json:23` = `"issues": "read"` | CONFIRMED |
| Drift-guard writes issues via installation-scoped App token | `cron-github-app-drift-guard.ts:770` `createProbeOctokit()` → `:591` `POST /repos/{owner}/{repo}/issues`, `:580/:610` `POST .../comments` | CONFIRMED |
| 403 is swallowed | `cron-github-app-drift-guard.ts:800-811` try/catch → `reportSilentFallback(...)` | CONFIRMED (Sentry error mirror exists; GitHub trail does not) |
| `reportSilentFallback` mirrors to Sentry (cq-silent-fallback satisfied) | `server/observability.ts:188-198` `Sentry.captureException` / `captureMessage` at `level: "error"` | CONFIRMED — rule already satisfied; signal quality is the gap, not the mirror |
| cron-oauth-probe.ts shares the blind spot | `cron-oauth-probe.ts:625` `createProbeOctokit()` → `:510` `POST /issues`, `:499/:528` `POST .../comments`, swallowed at `:635` | CONFIRMED — same root cause |
| Other migrated crons also affected | `cron-stale-deferred-scope-outs.ts:296` + `cron-community-monitor.ts:49` both use `createProbeOctokit()` for issue comment/create/close | CONFIRMED — broader beneficiary set; same root cause; one manifest grant fixes all |
| `members:read` is used by code | `rg` for `/orgs/.../members`, `/memberships`, `/teams` across `server/`, `app/`, `lib/` → ZERO hits; workspace features use Supabase `workspace_members` (learning 2026-05-28-github-app-installation-org-level-sibling-lookup.md) | NOT USED → safe to drop |
| `members:read` added deliberately | `git log -S '"members"' github-app-manifest.json` → single commit 2cf58af0 (#4121, manifest creation); no rationale in #4115 spec/brainstorm | Speculative inclusion; unexamined |
| Live install ID drifted (122213433 → 130018654) | runbook Step 2.1 names `122213433`; alert + #4179 plan name `130018654`/`122213433` — App reinstalled; missing `members:read` on the current install is the open #4189 drift | CONFIRMED |
| Realtime probe is GHA-fired (scheduler-dependent), not Inngest | `.github/workflows/scheduled-realtime-probe.yml` `on.schedule: 0 7 * * *` | CONFIRMED — GitHub-scheduler drift is the false-alarm source |
| cron-monitor TF auto-applies on merge | `apply-sentry-infra.yml:39` triggers on `cron-monitors.tf` push; `:182` targets `scheduled_realtime_probe` | CONFIRMED — fix 3 needs NO operator step |

> Inngest/Sentry live run-data was NOT directly queried in this planning session
> (no Sentry/Inngest MCP loaded). The code-path proof above is dispositive: a
> `POST /issues` with an `issues: read`-scoped installation token returns 403 by
> GitHub's documented permission model, and the catch swallows it to Sentry only.
> The /work phase SHOULD confirm with one Sentry checkins-API query (see
> Observability → discoverability_test) before and after the re-consent.

## Research Reconciliation — Spec vs. Codebase

| Feature-description claim | Codebase reality | Plan response |
|---|---|---|
| `cq-silent-fallback-must-mirror-to-sentry` requires the fallback to mirror to Sentry; "confirm it does" | `reportSilentFallback` already mirrors at `level: "error"` (observability.ts:188-198). The rule is SATISFIED. | Do NOT add a redundant mirror. Upgrade SIGNAL QUALITY: discriminate the 403 with `op: "issue_write_403"` so the operator can alert-route on it, and document it in the runbook. The fix to "reach a GitHub issue again" is the `issues:write` grant, not more Sentry noise. |
| grant `issues:write` "if genuinely required" | Required: 4+ crons (`cron-github-app-drift-guard`, `cron-oauth-probe`, `cron-stale-deferred-scope-outs`, `cron-community-monitor`) write issues via the installation token | Grant `issues:write`. |
| `members:read` may be "genuinely required by recent team/workspace features" | Workspace features read Supabase `workspace_members` (app DB), NOT GitHub `/orgs/{org}/members`. Zero code hits. GitHub installations are org-level (learning 2026-05-28). | DROP `members:read`. This clears #4189's drift WITHOUT an operator gate for that key. |
| widen realtime monitor `checkin_margin` | `scheduled_realtime_probe` is already at `checkin_margin_minutes = 180`; GitHub dropped a whole 24h run (05-26), so 180 min is insufficient | Widen `checkin_margin_minutes` 180 → 1440 (24h) so a single dropped scheduled run does not page. (Alternative considered: raise `failure_issue_threshold`; see Alternatives.) |
| "All numeric PR/issue references are date-anchored CONTEXT, not work targets" | Acknowledged | #4189 is the issue this fix CLOSES (the members:read drift it tracks is resolved by fix 2); all other numbers are provenance only. |

No remaining gap callouts.

## User-Brand Impact

**If this lands broken, the user experiences:** the drift-guard remains
issue-trail-dark — a real GitHub-App identity drift (App swap/suspend, key
rotation, callback-URL drift) would page Sentry but file no actionable GitHub
issue, extending the operator's awareness gap against the GDPR Art. 33 72h clock.
For fix 2, if `members:read` were actually load-bearing (it is not — verified),
dropping it would 403 an org-membership read path; none exists. For fix 1, if the
manifest declares `issues:write` but the operator never re-consents, the drift-guard
correctly files `installation_permission_drift` for `issues` on the next tick —
loud, not silent (this is the designed behavior, not a regression).

**If this leaks, the user's data is exposed via:** N/A. The manifest declares App
permission scopes (public to the App). No user data surface. The existing
PEM/JWT leak tripwire (`assertNoLeak`) already covers every new emission path; no
new emission path is added.

**Brand-survival threshold:** `single-user incident`. The drift-guard is the
standing detection primitive for the App backing OAuth sign-in; one user's broken
sign-in caused by an undetected App drift IS the brand-end signal. CPO sign-off
required at plan time (carry-forward from #4179 / #3187 — this fix RESTORES the
exact issue-trail capability those features shipped; no new product decision).
`user-impact-reviewer` invoked at PR-review time per
`plugins/soleur/skills/review/SKILL.md`.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — `issues: read → write` in manifest.** `apps/web-platform/infra/github-app-manifest.json` `default_permissions.issues == "write"`. Verified by `jq -r '.default_permissions.issues' apps/web-platform/infra/github-app-manifest.json` returns `write`.
- [x] **AC2 — `members:read` dropped from manifest.** `jq -r '.default_permissions | has("members")' apps/web-platform/infra/github-app-manifest.json` returns `false`.
- [x] **AC3 — Parity test key-set updated.** `apps/web-platform/test/github-app-manifest-parity.test.ts` `EXPECTED_PERMISSION_KEYS` no longer contains `"members"` (the test asserts an EXACT key-set match at `:148-156`; leaving `members` in the list fails the test once it is dropped from the manifest). The rationale comment at `:43-50` is updated to record: `issues` bumped read→write (restores cron issue-filing per #4189), `members` dropped (unused; cleared #4189 drift). Verified by `./node_modules/.bin/vitest run apps/web-platform/test/github-app-manifest-parity.test.ts` green.
- [x] **AC4 — 403 discriminator added to both crons.** In `cron-github-app-drift-guard.ts` issue-handling catch (`:801-811`, `op: "handleIssue"` at `:803`), set `op: "issue_write_403"` when the caught error has `status === 403`, else preserve `op: "handleIssue"`. Mirror in `cron-oauth-probe.ts` issue-handling catch (`:635-641`) — NOTE its existing op is `op: "handleTrackingIssue"` (verified at `:637`), NOT `handleIssue`; preserve `handleTrackingIssue` for non-403. The `message` string MUST be preserved verbatim in BOTH (`"GitHub tracking-issue file/comment/close failed"` at `:804`/`:638`) per the helper-migration dashboard-message rule (`2026-05-13-helper-migration-must-preserve-operator-dashboard-message-strings.md`). The 403 status is read off the ORIGINAL octokit error (`(err as { status?: number }).status === 403`); the drift-guard wraps via `redactedError(err)` before `reportSilentFallback`, and `redactedError` returns a fresh `Error` WITHOUT the `.status` property when the message matches the leak regex — so compute the `op` from the original `err.status` BEFORE the `redactedError` call, not after. Verified by `rg -n 'issue_write_403' apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts apps/web-platform/server/inngest/functions/cron-oauth-probe.ts` returns ≥2.
- [x] **AC5 — Realtime monitor grace widened.** `apps/web-platform/infra/sentry/cron-monitors.tf` `sentry_cron_monitor.scheduled_realtime_probe.checkin_margin_minutes == 1440` with an inline comment citing GitHub-scheduler drop-a-run drift (05-26 2026-05) as the rationale. Verified by `grep -A6 'resource "sentry_cron_monitor" "scheduled_realtime_probe"' apps/web-platform/infra/sentry/cron-monitors.tf | grep -c 'checkin_margin_minutes  = 1440'` returns 1.
- [x] **AC6 — Regression test: 403 issue-write is surfaced, not silent.** New vitest case in `apps/web-platform/test/server/inngest/cron-github-app-drift-guard.test.ts` (and a mirror in `cron-oauth-probe.test.ts`): mock the `POST /repos/{owner}/{repo}/issues` route to throw `{ status: 403 }`; assert `reportSilentFallback` is called with `op: "issue_write_403"` AND the Sentry heartbeat still posts `?status=error` (the drift result, not the issue-write failure, drives the heartbeat). Verified by `./node_modules/.bin/vitest run apps/web-platform/test/server/inngest/cron-github-app-drift-guard.test.ts apps/web-platform/test/server/inngest/cron-oauth-probe.test.ts` green.
- [x] **AC7 — All existing drift-guard + oauth-probe + parity tests pass unchanged in behavior.** `./node_modules/.bin/vitest run apps/web-platform/test/server/inngest/cron-github-app-drift-guard.test.ts apps/web-platform/test/server/inngest/cron-oauth-probe.test.ts apps/web-platform/test/github-app-manifest-parity.test.ts` all green. (Note the bunfig.toml `pathIgnorePatterns = ["**"]` blocks `bun test`; use vitest.)
- [x] **AC8 — Runbook Step 2.1 updated for the new install ID + issues:write.** `knowledge-base/engineering/ops/runbooks/github-app-provisioning.md` Step 2.1 install URL updated to the current installation `130018654` (was `122213433`), and a note added that this PR's `issues:write` widen requires one re-consent click that ALSO clears the dropped-`members:read` drift. Verified by `grep -c '130018654' knowledge-base/engineering/ops/runbooks/github-app-provisioning.md` returns ≥1.
- [x] **AC9 — `Ref #4189` in PR body (NOT `Closes`).** #4189 is closed by the POST-MERGE re-consent + drift-guard green tick, not by merge — use `Ref #4189` per `wg-use-closes-n-in-pr-body-not-title-to` extended for the ops-remediation class. The post-merge step (AC11) closes it. Verified by `gh pr view --json body --jq .body | grep -c 'Ref #4189'` returns 1.
- [x] **AC10 — No new infra surface.** Net new file count = 0; net new Terraform resource count = 0 (existing resource field-edit only); net new secret count = 0. Verified by `git diff --name-status origin/main -- apps/web-platform/infra/`.

### Post-merge (operator)

- [ ] **AC11 — Re-consent the App installation (single UI click).** Navigate to `https://github.com/organizations/jikig-ai/settings/installations/130018654`, click **Review request** → **Accept new permissions** (the banner appears because the manifest now declares `issues:write` above the live grant). This single click grants `issues:write`; because `members:read` was DROPPED from the manifest (not added), no `members` re-grant is needed and that drift clears automatically. **Automation: not feasible — GitHub has no API for installation-permission re-consent (vendor-authorization-scope class, operator-only canonical list case b). This is the ONE genuine operator gate.** Verify the grant via `gh api /orgs/jikig-ai/installations --jq '.installations[] | select(.app_slug=="soleur-ai") | .permissions.issues'` returns `write` and `... | .permissions | has("members")` returns `false`.
- [ ] **AC12 — Force drift-guard re-check + verify green.** `inngest send cron/github-app-drift-guard.manual-trigger --data '{}'`, then after ~30s verify via Sentry checkins API (no dashboard eyeball per `hr-no-dashboard-eyeball-pull-data-yourself`): `curl -s -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://de.sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-github-app-drift-guard/checkins/?limit=1" | jq -r '.[0].status'` returns `ok`. **Automation: feasible** — `/soleur:ship` Phase 6 post-merge handles `inngest send` + API verify; bake inline.
- [ ] **AC13 — Confirm issue trail restored + close #4189.** After AC12 green, `gh issue list --state open --label ci/auth-broken --search 'in:title "GitHub App drift-guard"'` returns empty (drift-guard auto-closed any stale issue). Then `gh issue close 4189 --comment "members:read drift cleared by dropping the unused scope; issues:write granted to restore the drift-guard issue trail. Verified green via manual-trigger + Sentry checkins API."`. **Automation: feasible** — `gh` CLI scriptable; bake into ship Phase 6.
- [ ] **AC14 — Realtime monitor auto-applied.** The merge to `main` touching `cron-monitors.tf` triggers `apply-sentry-infra.yml` (`scheduled_realtime_probe` is in the `-target=` list at `apply-sentry-infra.yml:182`); verify the apply run succeeded: `gh run list --workflow apply-sentry-infra.yml --limit 1 --json conclusion --jq '.[0].conclusion'` returns `"success"`. Then read the live monitor back via the Sentry API: `curl -s -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://de.sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-realtime-probe/" | jq '.config'` and confirm the grace field reflects 1440 minutes. **NOTE (deepen-pass): the Sentry API JSON field name for the grace window was NOT verified live in this planning session (no Sentry MCP/token loaded). The Terraform attribute is `checkin_margin_minutes`; the Sentry monitor-API config key is likely `checkin_margin` (in minutes) per the jianyuan/sentry provider, but /work MUST confirm the exact `jq` path against one live response before pinning it in a script — do not fabricate `.config.checkin_margin`.** **Automation: feasible** — fully automated apply path; no operator action.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO) — carry-forward; Product (CPO) — carry-forward + plan-time sign-off

### Engineering (CTO)

**Status:** carry-forward from #4179 / #3187 + learning 2026-05-20-three-plane-drift + learning 2026-05-28-org-level-sibling-lookup.
**Assessment:** Build now. Pure manifest + observability + Terraform field edit. No new script, no new workflow, no new secret, no new TF resource. `issues:write` is required by 4+ migrated crons that share the `createProbeOctokit()` issue-writer path; `members:read` is provably unused (Supabase `workspace_members` is the membership source of truth — installations are org-level). The re-consent gate is identical to the existing #4179 mechanism. Reuses the leak tripwire, issue-filing flow, Sentry heartbeat, and auto-close-stale logic unchanged.

### Legal (CLO)

**Status:** carry-forward (drift-guard is a GDPR Art. 33 / Policy §299 compliance control).
**Assessment:** GO. RESTORES an existing compliance control's operator-facing signal; narrows App scope (drops an unused permission — strictly reduces data-access surface). No new data category, vendor, or lawful basis question.

### Product/UX Gate

**Tier:** none. **Decision:** auto-accepted (pipeline). **Agents invoked:** none (no UI). **Skipped specialists:** none. **Pencil available:** N/A.

#### CPO sign-off (plan-time, required by `single-user incident` threshold)

**Status:** required per `requires_cpo_signoff: true`. **Carry-forward:** the drift-guard's product framing (one user's broken sign-in = brand-end) is already CPO-signed at #3187/#4179. This fix restores the issue-trail capability those features shipped — confirmatory, not re-design. Invoke CPO domain leader only if scope expands beyond the manifest/observability/TF edits described here.

## GDPR / Compliance Gate

**Skip silently.** No schema, migration, auth flow (code), API route, or `.sql`
file. The manifest declares the App's own permission scopes (public to the App).
Trigger (a) no LLM/external-API on operator data (the crons read GitHub's own
App metadata). Trigger (b) `single-user incident` declared, but the data category
is the App's permission scope, not user data — drives CPO sign-off, not GDPR
processing-activity treatment. Triggers (c)/(d) do not fire (extends existing
crons; no new artifact distribution).

## Infrastructure (IaC)

The realtime-monitor change IS Terraform, but it is a field-edit on an EXISTING
resource auto-applied by `apply-sentry-infra.yml` on merge (resource is already
in the `-target=` list at `apply-sentry-infra.yml:182`). No new resource, no new
root, no new backend, no operator `terraform apply`. The manifest edits are JSON
inventory, not provisioning. No new server/service/secret/vendor/cron.

### Apply path

cloud-init + idempotent: N/A. The Sentry cron-monitor field-edit auto-applies via
the existing push-to-main pipeline (kill-switch `[skip-sentry-apply]` available;
destroy-guard requires `[ack-destroy]` — a field-edit produces an in-place update,
0 destroys, so no ack needed). Expected blast radius: one in-place
`sentry_cron_monitor` update; zero downtime.

### Distinctness / drift safeguards

The manifest re-consent (AC11) is the only operator gate and is unavoidable for
`issues:write` regardless of `members:read`. The drift-guard itself is the standing
verification that manifest == live grant after re-consent.

## Observability

```yaml
liveness_signal:
  what: "Sentry cron monitors scheduled-github-app-drift-guard + scheduled-oauth-probe (hourly) + scheduled-realtime-probe (daily)"
  cadence: "hourly (drift-guard, oauth-probe cron 0 * * * *); daily 07:00 UTC (realtime-probe)"
  alert_target: "Sentry cron monitor + auto-filed GitHub issue (restored by issues:write) + ops email via Resend"
  configured_in: "apps/web-platform/infra/sentry/cron-monitors.tf (monitors); cron-github-app-drift-guard.ts:839-846 + cron-oauth-probe.ts:663-670 (heartbeat post)"
error_reporting:
  destination: "Sentry web-platform project; GitHub issue on jikig-ai/soleur (ci/auth-broken | ci/guard-broken); pino stdout -> Better Stack"
  fail_loud: "drift result drives Sentry ?status=error heartbeat; issue-write 403 now mirrored to Sentry at level=error with op=issue_write_403 (discriminable in dashboard); after re-consent the GitHub-issue trail is restored as the primary operator surface"
failure_modes:
  - mode: "issue_write_403 (App token lacks issues:write before re-consent)"
    detection: "catch in issue-handling step: err.status === 403 -> reportSilentFallback op=issue_write_403"
    alert_route: "Sentry level=error tag feature=cron-github-app-drift-guard|cron-oauth-probe op=issue_write_403"
  - mode: "installation_permission_drift members:read (the open #4189 drift)"
    detection: "diffGithubAppManifest(manifest, install.permissions) -> permission_drift; resolved by dropping members from manifest"
    alert_route: "ci/auth-broken GitHub issue + Sentry ?status=error (clears post-merge, no re-consent needed for the drop)"
  - mode: "realtime-probe missed check-in (GitHub scheduler dropped a run)"
    detection: "Sentry missed-checkin algorithm vs schedule + checkin_margin"
    alert_route: "Sentry issue (now suppressed within a 1440-min grace so single dropped GHA run does not page)"
logs:
  where: "Sentry events; auto-filed GitHub issue bodies link the Sentry monitor URL; pino -> container stdout -> Better Stack"
  retention: "Sentry events 30d; GitHub issues until closed; Better Stack per plan."
discoverability_test:
  command: "curl -s -H \"Authorization: Bearer $SENTRY_AUTH_TOKEN\" \"https://de.sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-github-app-drift-guard/checkins/?limit=1\" | jq -r '.[0].status'"
  expected_output: "ok (after AC11 re-consent + AC12 manual-trigger); the GitHub issue trail is restored when gh issue list --label ci/auth-broken returns the auto-filed-then-auto-closed issue"
```

## Test Scenarios

### Acceptance (RED targets)

- **AT1 (AC6).** Given the drift-guard detects a drift AND `POST /issues` throws `{status:403}`, when the handler runs, then `reportSilentFallback` is called with `op: "issue_write_403"` AND the Sentry heartbeat still posts `?status=error`. (Pre-fix: `op: "handleIssue"`, no 403 discriminator.)
- **AT2 (AC6 mirror).** Same as AT1 for `cron-oauth-probe.ts` issue-handling catch.
- **AT3 (AC3).** Given the manifest drops `members` and bumps `issues` to write, the parity test's `EXPECTED_PERMISSION_KEYS` (no `members`) matches the manifest key-set exactly.

### Regression

- **RT1.** All existing `cron-github-app-drift-guard.test.ts` cases pass (happy-path, every failure-mode `?status=error` mapping, fork-PR fallback, retry self-heal).
- **RT2.** All existing `cron-oauth-probe.test.ts` cases pass.
- **RT3.** `github-app-manifest-parity.test.ts` exact-key-set test passes with the updated `EXPECTED_PERMISSION_KEYS`.

### Edge

- **EC1.** After re-consent but BEFORE the next drift-guard tick, the manifest declares `issues:write` and the live grant has it — `diffGithubAppManifest` returns `ok`; no `installation_permission_drift`.
- **EC2.** If the operator never re-consents, the drift-guard files `installation_permission_drift` for `issues` (loud, correct) on the next tick — this is the designed fail-loud behavior, not a regression.

## Files to Edit

- `apps/web-platform/infra/github-app-manifest.json` — `issues: read → write`; drop `members: read`.
- `apps/web-platform/test/github-app-manifest-parity.test.ts` — remove `"members"` from `EXPECTED_PERMISSION_KEYS` (`:51-63`); update rationale comment (`:43-50`).
- `apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts` — add `op: "issue_write_403"` discriminator for `err.status === 403` in the issue-handling catch (`:800-811`); preserve `message` verbatim.
- `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts` — same 403 discriminator in the issue-handling catch (`:633-641`).
- `apps/web-platform/infra/sentry/cron-monitors.tf` — `scheduled_realtime_probe.checkin_margin_minutes` 180 → 1440 + rationale comment.
- `apps/web-platform/test/server/inngest/cron-github-app-drift-guard.test.ts` — add the AC6 403-surfaced regression case.
- `apps/web-platform/test/server/inngest/cron-oauth-probe.test.ts` — add the AC6 mirror case.
- `knowledge-base/engineering/ops/runbooks/github-app-provisioning.md` — Step 2.1 install ID 122213433 → 130018654 + issues:write re-consent note.

## Files to Create

None.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned zero issues
touching any of the planned files (`cron-github-app-drift-guard.ts`,
`cron-oauth-probe.ts`, `github-app-manifest.json`, `cron-monitors.tf`,
`scheduled-realtime-probe.yml`) at plan-write time.

## Alternative Approaches Considered

| Approach | Decision | Rationale |
|---|---|---|
| Keep `members:read`, force re-consent for it | Rejected | Unused scope; re-consenting an unused permission widens App access for no benefit. Dropping it clears the drift with no operator action for that key. |
| Fix loudness by adding a SECOND Sentry mirror | Rejected | `reportSilentFallback` already mirrors at `level: error` (cq-silent-fallback satisfied). A second mirror is noise. The real fix is the `issues:write` grant; the discriminator (`op: issue_write_403`) is the minimal signal-quality upgrade. |
| Bypass the App and file issues via a PAT/`GH_TOKEN` | Rejected | Violates `hr-github-app-auth-not-pat`. The App-token path is correct; it just needs the scope. |
| Raise `failure_issue_threshold` instead of `checkin_margin` for realtime probe | Considered, secondary | `checkin_margin = 1440` tolerates a dropped run within the same day window; raising `failure_issue_threshold` to 2 would tolerate two consecutive misses but delays detection of a genuine probe break by a full day. Margin-widen is the more precise lever for scheduler-drop drift. Could combine if 1440 proves insufficient. |
| Split fix 3 into its own PR | Considered | Could split (independent TF edit), but bundling keeps one atomic operator-action ledger (re-consent covers 1+2; 3 needs none). No coupling cost. |

## Risks

- **R1 (low).** First post-merge drift-guard tick BEFORE re-consent files an `installation_permission_drift` for `issues` (manifest declares write, live has read). This is correct fail-loud behavior; the re-consent (AC11) clears it within the hour. Mitigation: run AC11→AC12 promptly post-merge (ship Phase 6).
- **R2 (low).** The 1440-min realtime grace means a GENUINE realtime regression is detected up to ~24h later via the missed-checkin path. Mitigation: the probe's OWN failure path (5x SUBSCRIBED check → `ci/realtime-broken` issue) still fires within the run when GitHub DOES run the job; the widened margin only affects the missed-RUN (scheduler-drop) detection, which is the false-alarm source, not the real-break source.
- **R3 (low).** Other crons (`cron-stale-deferred-scope-outs`, `cron-community-monitor`) silently benefit from `issues:write` — verify none REGRESS on the new scope (they currently 403-and-swallow; granting write only enables their intended writes). No behavior to break.

## References

- `apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts` (issue-handling :760-812)
- `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts` (issue-handling :620-642)
- `apps/web-platform/server/github/probe-octokit.ts` (`createProbeOctokit`)
- `apps/web-platform/server/observability.ts:164-203` (`reportSilentFallback` — Sentry error mirror)
- `apps/web-platform/server/github/manifest-diff.ts` (`diffGithubAppManifest`)
- `apps/web-platform/infra/github-app-manifest.json`
- `apps/web-platform/test/github-app-manifest-parity.test.ts:51-63,148-156`
- `apps/web-platform/infra/sentry/cron-monitors.tf:157-167` (`scheduled_realtime_probe`)
- `.github/workflows/apply-sentry-infra.yml:182` (auto-apply target)
- `.github/workflows/scheduled-realtime-probe.yml` (GHA-fired, scheduler-dependent)
- `knowledge-base/engineering/ops/runbooks/github-app-provisioning.md` (Step 2.1 re-consent)
- `knowledge-base/engineering/ops/runbooks/github-app-drift.md` (triage)
- `knowledge-base/project/learnings/2026-05-28-github-app-installation-org-level-sibling-lookup.md` (installations are org-level; workspace membership is Supabase)
- `knowledge-base/project/learnings/2026-05-20-github-app-installation-grant-vs-manifest-three-plane-drift.md`
- `knowledge-base/project/plans/2026-05-20-feat-drift-guard-installation-grant-diff-4179-plan.md`

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled.)
- The parity test asserts an EXACT permission KEY-SET (`:148-156`), not scope values — bumping `issues` read→write does NOT break it, but FORGETTING to remove `members` from `EXPECTED_PERMISSION_KEYS` WILL. Both edits land in the same commit.
- `bun test` is blocked for web-platform (`apps/web-platform/bunfig.toml` `pathIgnorePatterns = ["**"]`). All AC verification commands use `./node_modules/.bin/vitest run <path>` from `apps/web-platform`.
- The realtime monitor field-edit auto-applies via `apply-sentry-infra.yml` on push to main — do NOT prescribe a manual `terraform apply`. A field-edit is an in-place update (0 destroys), so no `[ack-destroy]` is needed.
- `members:read` re-grant is NOT needed because the manifest DROPS it (lower than live = no banner). Only `issues:write` (manifest declares above live) raises the re-consent banner. One click covers it.
