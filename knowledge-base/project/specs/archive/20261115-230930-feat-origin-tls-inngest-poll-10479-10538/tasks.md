---
title: "Tasks: origin TLS cleanup and Inngest public-host poll (#10479, #10538)"
branch: feat-origin-tls-inngest-poll-10479-10538
plan: knowledge-base/project/plans/2026-11-13-feat-origin-tls-cleanup-and-inngest-public-poll-plan.md
lane: cross-domain
---

# Tasks

Single test files only, one at a time. No `test-all.sh`, no `run-registered-suites.sh`, no affected batteries.
Scratch under `/var/tmp/oneshot-10479/`. No SSH, no Doppler writes, no workflow dispatches, no host or Cloudflare
writes.

## 1. Setup and preconditions (read-only)

- [ ] 1.1 `git fetch origin main`; check PR #12733 (`gh pr view 12733 --json state,mergedAt`); rebase on `origin/main`
      once it has merged. Phase 4 (ledger) waits for it.
- [ ] 1.2 Re-run the merge-apply safety grep on `.github/workflows/apply-web-platform-infra.yml` (no
      `hcloud_server.inngest`, `hcloud_server_network.inngest`, `hcloud_volume_attachment.inngest_redis_luks` in the
      per-merge `-target` list); note the result for the PR body.
- [ ] 1.3 Read the live ruleset via `cloudflare-readonly.sh config-entrypoint` (expect 5 rules, version 7); stop if it
      differs from `seo-config-rules.tf`.

## 2. #10479 cleanup

- [ ] 2.1 RED: `apps/web-platform/test/seo-config-rules.test.ts` to the target shape (adopted rule by ref, strict,
      `http.host eq "app.soleur.ai"`, new description, exactly 3 rules, one strict rule, tombstones, probe-header
      absence).
- [ ] 2.2 GREEN: `seo-config-rules.tf` (adopted rule edit, delete CANARY and STRICT FLIP blocks, comments) and
      `variables.tf` (delete both variables).
- [ ] 2.3 Run Guard 1 mutation rows once each by hand; record row + result for the PR body.
- [ ] 2.4 `ssl-full-mitigation.test.sh`: all three app-rule exclusion sites (main selector, fallback, ssl-rule count).
- [ ] 2.5 `origin-tls-probe.sh`: delete the `--canary` branch and header text; `origin-tls-probe.test.sh` rows.
- [ ] 2.6 Regenerate `tests/scripts/fixtures/tfplan-origin-tls-cleanup.json` (offline real plan, provider 4.52.7;
      jq fallback disclosed); T65 comment; expect `0:2:0:2:1` and `0:2:0:2:0`; add the T65 row asserting `after.rules` length 3 and the dcb85b75
      rule `strict` on the new expression.
- [ ] 2.7 RED then GREEN: `plugins/soleur/test/cloudflare-readonly.test.sh` `TF_SSL` derivation; header B of
      `plugins/soleur/scripts/cloudflare-readonly.sh` (`enabled_ssl_rules is 2`, `ssl=strict`, `rule_count is 3`).
- [ ] 2.8 `.github/workflows/cf-lb-overlay.yml` staging-arm comment; stale-comment edits in `server/origin-tls.ts`,
      `infra/cloudflare-lb.tf`, `infra/lb-staging/main.tf`, `runbooks/cf-lb-a-record-gaplessness-verify.md`.
- [ ] 2.9 Run each touched suite once; commit with a line exactly `[ack-destroy]` in the message.

## 3. #10538 declared change

- [ ] 3.1 RED: Guard 4 of `exec-placement-forward.test.ts` rewritten (sdk_url = `SERVE_HOST + "/api/inngest"`, pin
      bound to the volume holder); Guard 2 rows run once each.
- [ ] 3.2 GREEN: `inngest-host.tf` `sdk_url` and comment (incl. the stale carrier-comment note);
      `inngest-userdata-budget.sh` stub literal.
- [ ] 3.3 Comment-only edits: `exec-placement.ts`, `execution-placement.ts`, `resolve-origin.ts`,
      `function-registry-count.test.ts`, `workspaces-luks-verify.yml`. Do not touch `inngest-bootstrap.sh` or
      `cloud-init-inngest.yml`.
- [ ] 3.4 Run the Phase 2.5 suites once each; budget script reports the same stored size.

## 4. Registry-empty alert

- [ ] 4.1 Live `SELECT count()` reads (predicate, positive control, population) via `scripts/betterstack-query.sh`.
- [ ] 4.2 `betterstack-logs-alerts.tf`: SQL local (two legs, negated positive-integer test, uptime floor), exploration,
      alert (900 / 300 / 7200, treat_as_zero, runbook metadata, incident_cause naming the stale-registry gap).
- [ ] 4.3 Two `-target=` lines in `apply-web-platform-infra.yml`.
- [ ] 4.4 Runbook rows: `betterstack-log-query.md` standing alarm; `inngest-server.md` "Registry-empty alert (#10538)".
- [ ] 4.5 Exploration count in `betterstack-send-failed-alert-mutation.test.sh`.
- [ ] 4.6 Create `apps/web-platform/test/infra/inngest-registry-empty-alert.test.sh` (Guard 3) + `infra-validation.yml`
      step and paths.
- [ ] 4.7 Run every suite from `git grep -ln 'logtail_exploration' -- apps/web-platform/test/infra apps/web-platform/infra/*.test.sh plugins/soleur scripts tests`
      once each; fix any moved census; add the alert to `plugins/soleur/scripts/inngest-alerts-push-probe.ts` `TARGETS`
      (+ its test); run `plugins/soleur/test/terraform-target-parity.test.ts`.
- [ ] 4.8 SQL copies the sibling's shape only: no `_alias` / `hcloud_volume` reference, no `detail = ''` branch.

## 5. Ledger (after #12733 is on main)

- [ ] 5.1 `connections[7]`: measured TLS, `cert_verification` on, no exception, `disclosed_as` the Privacy Policy
      anchor, new `enforced_at`, `does_not_defend`.
- [ ] 5.2 `connections[6]`: append the CLO sentence and the `reevaluate_when` clause, `tracking_issue` FU-1,
      `enforced_at` declared-vs-live note; `expires_on` untouched.
- [ ] 5.3 `python3 scripts/lint-encryption-posture.py --repo-root .` and `bash scripts/lint-encryption-posture.test.sh`.

## 6. Legal wording

- [ ] 6.1 Privacy Policy Section 11 bullet and DPD 8.1(c) with the CLO text; Added notes; Last Updated.
- [ ] 6.2 Identical edits in the two `plugins/soleur/docs/pages/legal/` mirrors.
- [ ] 6.3 Re-pin `apps/web-platform/lib/legal/legal-doc-shas.ts` in the same commit.
- [ ] 6.4 Article 30 register cells + `Superseded <merge date> (#10479)` under each 2026-10-29 #10479 marker.
- [ ] 6.5 DPA template §9 and Schedule 4 item 1; `domains.md` SSL Mode; `nfr-register.md` row; GDPR policy grep.
- [ ] 6.6 Absence greps after stripping notes; run the five legal gates one at a time.

## 7. ADRs and runbooks

- [ ] 7.1 ADR-321 item 13 (Cleanup) and the pointer in item 10.
- [ ] 7.2 ADR-100 Decision 1 amendment and Alternatives Considered; ADR-218 "Nth Logs alert" entry.
- [ ] 7.3 Simulate the rollback in a scratch detached worktree; then rewrite `origin-tls-strict-flip.md` (status,
      forward-PR rollback carrying the wording in the same diff, owner-only break-glass, cleanup record, recovery
      line, no `--canary`).
- [ ] 7.4 `origin-tls-canary.md` retired; `inngest-server.md` public-poll replace section and table-row fixes.
- [ ] 7.5 Run `plugins/soleur/test/c4-count-parity.test.sh` once (no C4 edit expected to be needed).

## 8. Follow-up issues (before ship)

- [ ] 8.1 FU-1 (sync-evidence probe field before the replace, owner replace, hop 1, row 6 + C4, legal carve-out kept,
      CLO owner record after 2026-11-20, stale carrier comment, and the measured exit condition that the private-URL
      poll stopped: v1.45.1 pings every stored app URL, so a stale `10.0.1.10:3000` app row would keep it alive) with `--body-file`, milestone "Post-MVP / Later",
      `Mandated-By: wg-when-deferring-a-capability-create-a`; point ledger row 6 `tracking_issue` at it.
- [ ] 8.2 FU-3 (port 80, Authenticated Origin Pulls, inert Doppler secrets) with the same conventions.
- [ ] 8.3 Conditional FU-4 only if the Playwright reading in 9.1 is unverified.

## 9. Pre-merge evidence and ship

- [ ] 9.1 Within 24 h before merge: Playwright snapshot of the LB pool page (web-1, web-2 healthy); per-host Better
      Stack counts; 20 `origin-tls-probe.sh --require-tls` runs; continuity reads (entrypoint `last_updated`
      2026-11-07T23:43:43Z, ssl-mode, pagerules, change-history attempt). Record under `## Pre-merge evidence readings
      (F3)` in `decision-challenges.md` and in the PR body.
- [ ] 9.2 `technical-ruling-gate.sh --branch feat-origin-tls-inngest-poll-10479-10538` passes.
- [ ] 9.3a Within about an hour before queueing: re-read `config-entrypoint` (rule_count 5, same version and
      last_updated as 1.3); a plan-only CI run, if any, shows exactly 2 nested deletes and no other destroy.
- [ ] 9.3 PR body: `Closes #10479`, `Closes #10538`, the safety grep, the Guard mutation results, GDPR policy "no
      change". Merge alone (no other `apps/web-platform/infra` PR in the batch).
- [ ] 9.4 Post-merge: read the push apply run (destroy guard acked, apply green, two alert resources created);
      re-measure via the wrapper and 20 probes; comment on #10479.
