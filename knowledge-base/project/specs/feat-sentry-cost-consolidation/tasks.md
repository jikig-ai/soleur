---
feature: feat-sentry-cost-consolidation
pr: 12844
plan: knowledge-base/project/plans/2026-11-17-feat-sentry-uptime-dedupe-observability-cost-cut-plan.md
lane: cross-domain
---

# Tasks: feat-sentry-cost-consolidation

Derived from the post-review plan. Rulings are in `decision-challenges.md`.

## Phase 1: Setup

- [ ] 1.1 Pre-flight read on `jikigai-eu.sentry.io` (plan Phase 0): 5 uptime detectors, 1422253
      mode 3 on `web-platform`, billing uptime usage 5, Better Stack 7 monitors. Paste into PR.
- [ ] 1.2 If 1422253 is not an import target, stop and switch to the D2 fallback.
- [ ] 1.3 Confirm ADR-328 is free on every `origin/*` ref.

## Phase 2: Tests first (RED)

- [ ] 2.1 W14 in `www-apex-canonicalizer.test.sh`: assert no `SENTRY_MONITORS=(` line and no
      marketing-host `sentry_uptime_monitor` URL; parse floor of at least 1 block.
- [ ] 2.2 Sibling `pronounceable_name` count `eq_case '6'` -> `'7'`.
- [ ] 2.3 Mutation suite: retarget `W-sentry-name`, add the `SENTRY_MONITORS` re-add row,
      `EXPECTED_ROWS` 28 -> 29.
- [ ] 2.4 `test-sentry-alert-live-fidelity.sh`: Guard 1 rows 1-7, 9 and H1-H2 with
      `SENTRY_FIXTURE_UPTIME`.
- [ ] 2.5 `test-sentry-alert-drift-workflow.sh`: W7 sets `SENTRY_FIXTURE_UPTIME`; Guard 1 row 8;
      rows for the `uptime_verdict` gates and both fixture pins.

## Phase 3: Core implementation

- [ ] 3.1 `sentry/uptime-monitors.tf`: `import` of `${var.sentry_org}/1422253` into
      `sentry_uptime_monitor.app`; the `.app` block (organization, project, name `soleur-app-reachability`,
      url `https://app.soleur.ai`, 60s, thresholds 3/1, environment production, 2xx,
      description, `lifecycle { ignore_changes = [project] }`); multi-line HCL; delete the 4 marketing blocks and the `moved` block; rewrite the header.
- [ ] 3.2 Commit with `[ack-destroy]` on its own line in the BODY.
- [ ] 3.3 Identity check of the Sentry plan: `update .app` with importing id, `delete` x4,
      nothing else deleted. Paste into PR.
- [ ] 3.4 `uptime-alerts.tf`: `betteruptime_monitor.soleur_changelog_deep` (soleur_apex keys);
      header, 526-list and www-redirect comments; ROUTING pointer line.
- [ ] 3.5 `apply-web-platform-infra.yml`: `-target=betteruptime_monitor.soleur_changelog_deep`.
- [ ] 3.6 `cutover-verify.sh`: delete the Sentry leg (array, 3 loops, Sentry probe branch,
      `CUT8_TOTAL` term); rewrite the comment. No `BETTERSTACK_MONITORS` append.
- [ ] 3.7 `sentry-alert-live-fidelity.sh`: uptime "unmanaged" section before the first
      rule-side exit; findings via `_finding` with scheme/host/path only; `SENTRY_UPTIME`
      marker; `uptime_verdict=fixture-clean` in fixture mode.
- [ ] 3.7a `scheduled-sentry-alert-drift.yml`: `uptime_verdict` output, unavailable filer and
      both closers gated on it, `SENTRY_FIXTURE_UPTIME: ""`, `UPTIME UNMANAGED` body bullet.
- [ ] 3.7b `apply-sentry-infra.yml`: `SENTRY_FIXTURE_UPTIME: ""` in the post-apply probe env.
- [ ] 3.8 `preflight-discoverability-test.test.ts`: `BASELINE_DECLARED_PROBES` 97 -> 98.
- [ ] 3.9 Comments and docs: `dns.tf`, `sentry/README.md`, `www-redirect-alarm.md`,
      `cloudflare-pages-cutover.md` (dated amendment).
- [ ] 3.10 ADR-328 via `soleur:architecture`; ADR-204 pointers; `model.c4` prose;
      regenerate `model.likec4.json`.
- [ ] 3.11 Ledgers: `expenses.md` Sentry (54.06 + note) and Better Stack (note);
      `cost-model.md` Sentry line, risk rows, review note.
- [ ] 3.12 `gh issue comment` on #12386 (routing + must-dos) and #7799 (ACME probe removed).

## Phase 4: Testing

- [ ] 4.1 Canonicalizer and mutation suites pass (AC5).
- [ ] 4.2 Fidelity and drift-workflow tests pass (AC6).
- [ ] 4.3 C4 tests pass (AC8); discoverability test passes (AC15).
- [ ] 4.4 Grep sweep prints nothing (AC7); resource counts per AC3.

## Phase 5: Post-merge (agent-run, same session)

- [ ] 5.1 Watch both apply workflows to completion with Monitor.
- [ ] 5.2 Read back 1422253 `mode: 1`, 4 marketing monitors gone, Better Stack changelog up.
- [ ] 5.3 Fidelity script prints `SENTRY_UPTIME uptime_verdict=clean unmanaged=0 live=1 declared=1`.
- [ ] 5.4 Fallback only if mode is still 3: `removed` + new monitor PR with `[ack-destroy]`
      (forget counts), expected red post-apply probe until the delete, 3 passing checks,
      GET/DELETE/GET of 1422253 (D3a).
- [ ] 5.5 Billing read pasted (informational).
- [ ] 5.6 Follow-up PR: `BETTERSTACK_MONITORS` append + baseline regeneration; auto-merge.
- [ ] 5.7 Tracking issue: post-merge ACs with cited output and the 2026-12-16 ledger re-read.
