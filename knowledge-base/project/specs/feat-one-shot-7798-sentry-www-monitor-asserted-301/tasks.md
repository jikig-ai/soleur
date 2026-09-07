---
title: "Tasks — fix: sentry_uptime_monitor.soleur_www pages on its own asserted 301"
branch: feat-one-shot-7798-sentry-www-monitor-asserted-301
plan: knowledge-base/project/plans/2026-09-07-fix-sentry-www-monitor-asserted-301-plan.md
issue: 7798
lane: cross-domain
---

# Tasks

Derived from the finalized plan. Phase 0.1 **gates everything else** — do not
start Phase 1 until it returns a verdict.

## Phase 0 — Falsify the vendor claim, then the remaining preconditions

- [ ] **0.1 Transient falsification probe (GATING).** `POST` a temporary Better
      Stack monitor against `https://www.soleur.ai/` with `monitor_type
      "expected_status_code"`, `expected_status_codes [301]`, `follow_redirects
      false`, `confirmation_period 0`. Wait one `check_frequency` cycle. Read the
      monitor status **and its check's recorded response status**. `DELETE` it.
      Token: `BETTERSTACK_API_TOKEN` from Doppler `soleur/prd_terraform`.
  - [ ] 0.1a Record the measurement verbatim for the PR body.
  - [ ] 0.1b **If it CONFIRMS** (up against the live 301) → continue to 0.2.
  - [ ] 0.1c **If it REFUTES** → HALT. Do not ship the Sentry retarget alone.
        Re-scope to the cut scheduled-probe design, re-accepting its cost
        explicitly. Report the fork rather than improvising.
- [ ] 0.2 Re-pull live Sentry uptime state and incident `WEB-PLATFORM-11`.
- [ ] 0.3 Re-measure live Better Stack monitor **and** heartbeat counts; record
      the post-PR headroom figure the narrative will cite.
- [ ] 0.4 Re-derive the free ADR ordinal across every `origin/*` ref (not just
      `origin/main`).
- [ ] 0.5 Decide `fixtures/dns.tf.pr4a-baseline` edit-vs-carve-out on evidence:
      is it asserted against literally by any suite?
- [ ] 0.6 Confirm `hcl_block()` in `www-apex-canonicalizer.test.sh` extracts
      correctly from `uptime-alerts.tf` — the first call site outside the
      `dns.tf` / `cf-pages.tf` / `seo-bulk-redirects.tf` trio.
- [ ] 0.7 Run the web-platform destroy-guard and fixture-based suites BEFORE any
      change; record which carry resource-count assertions.

## Phase 1 — Guard first

- [ ] 1.1 Write the Guard 1 cases into
      `apps/web-platform/infra/www-apex-canonicalizer.test.sh` **before** the
      Terraform block exists, using the suite's own `strip_comments` /
      `hcl_block` / `attr` helpers.
- [ ] 1.2 Bump **both** `EXPECTED_CASES` arms (23 and 24) by the number of cases
      added — the floor is an exact cardinality and fails closed.
- [ ] 1.3 Confirm M3 reds against the absent resource.
- [ ] 1.4 Verify M1–M6 each red one at a time; verify H1 reds and H2 passes.
      Capture the 7-red / 1-pass tally for the PR body (AC7).

## Phase 2 — The Better Stack monitor and its allow-list line

- [ ] 2.1 Add `betteruptime_monitor.soleur_www_redirect` to
      `apps/web-platform/infra/uptime-alerts.tf` with the Phase 2 attribute
      table's exact values, including `pronounceable_name`,
      `confirmation_period = 1200`, and `policy_id` as the sibling ternary.
- [ ] 2.2 Comment each load-bearing attribute with *why* it is load-bearing;
      cite the runbook and ADR-204.
- [ ] 2.3 **Same commit:** append
      `-target=betteruptime_monitor.soleur_www_redirect` to the bridge-less
      stage of `.github/workflows/apply-web-platform-infra.yml`, beside the
      other `betteruptime_*` targets. The resource is inert without it.
- [ ] 2.4 Do **not** add the address to `OPERATOR_APPLIED_EXCLUSIONS` (AC5b).
- [ ] 2.5 Amend the "Why apex only (not www…)" header comment in
      `uptime-alerts.tf`, citing ADR-204 and both tracking issues.

## Phase 3 — Retarget and rename the Sentry monitor

- [ ] 3.1 Swap `assertion_json` to `local.uptime_assertion_2xx`.
- [ ] 3.2 Rename the resource to `sentry_uptime_monitor.soleur_www_reachability`
      and its `name` to `"soleur-ai-www-reachability"`.
- [ ] 3.3 **Add a `description`** to the renamed resource. The provider documents
      it as "used in the resulting issue", so it reaches the operator — write it
      for the alert reader: what it guards (www reachability), what it does not
      (the 301), which monitor does (`betteruptime_monitor.soleur_www_redirect` /
      `"soleur dot ai www redirect 301"`), and the runbook path. Follow the
      `soleur_acme_probe` precedent in the same file.
- [ ] 3.4 Rewrite the resource comment and the `WHY FOUR MONITORS` header bullet
      2 — state plainly what is and is not guarded now, in the voice the adjacent
      `soleur_acme_probe` comment uses.
- [ ] 3.5 Update `SENTRY_MONITORS` in `cutover-verify.sh` to the new name, plus
      its two surrounding comments and the stale CUT8 PASS message.

## Phase 4 — The deploy-docs bracket

- [ ] 4.1 Delete the `Pause soleur_www uptime monitor` step entirely.
- [ ] 4.2 Keep the probe step; delete its resume `PUT`, its `MONITOR_ID` env line,
      its now-unused Sentry credential env vars, and its `if: always()` guard.
      Rename the step to drop "then resume".
- [ ] 4.3 Verify no dangling references to removed step ids or outputs survive.

## Phase 5 — Script mode, docs, ADR, C4, issues

- [ ] 5.1 Add the `--check-www-redirect` mode to `cutover-verify.sh` (calls the
      existing `check_redirect`, returns before any credentialed path) and list
      it in `usage()`.
- [ ] 5.2 Write `knowledge-base/engineering/operations/runbooks/www-redirect-alarm.md`
      following the directory's `# Runbook:` + `**TL;DR:**` convention.
- [ ] 5.3 Write ADR-204 — vendor constraint, substrate move, the Better Stack
      scope amendment, and the explicit single-vendor note.
- [ ] 5.4 Correct the stale claims: `dns.tf` (two sites incl. Camp B),
      `www-apex-canonicalizer.test.sh` (two comments), `seo-aeo/SKILL.md`,
      `fixtures/dns.tf.pr4a-baseline` per 0.5, and **ADR-194's two false
      passages** (leaving its 526 passage alone).
- [ ] 5.5 Update `model.c4`'s `betterstack` element description.
- [ ] 5.6 File the residual-gap tracking issue and the
      unmanaged-`app.soleur.ai/health`-monitor tracking issue; link both from
      ADR-204 and the `uptime-alerts.tf` comment.
- [ ] 5.7 Run explicitly by name: `plugins/soleur/test/c4-count-parity.test.sh`,
      `c4-from-components.test.sh`, `c4-model-freshness.test.sh`,
      `terraform-target-parity.test.ts`, `npx -y likec4@1.50.0 validate .`,
      `actionlint` on both edited workflows.
- [ ] 5.8 Re-run the AC20 knowledge-base path check now that the created files
      exist.

## Phase 6 — Post-merge verification (pipeline-executed)

Poll via the `Monitor` tool with an until-loop — never a foreground `sleep`,
never a detached background poller.

- [ ] 6.1 Both applies green; the web-platform apply log shows the new `-target=`.
- [ ] 6.2 Sentry: `soleur-ai-www-reachability` at `uptimeStatus 1`, recent checks
      `success`, `WEB-PLATFORM-11` resolved.
- [ ] 6.3 Better Stack: `soleur_www_redirect` up **continuously past 1380 s**
      AND its latest check records a `301`. Both halves — inside the confirmation
      window a fully-failing monitor still reads `up`.
- [ ] 6.4 **If 6.2 or 6.3 fails:** execute containment — `paused = true` on the
      new monitor, revert the Sentry retarget, file `action-required`, re-open
      #7798. Do not leave a second permanently-red monitor mailing.
- [ ] 6.5 Only after 6.2 holds: re-capture
      `cutover-monitor-baseline.txt` via `--capture-monitor-baseline`.
