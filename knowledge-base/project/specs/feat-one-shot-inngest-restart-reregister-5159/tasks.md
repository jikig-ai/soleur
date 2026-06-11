---
issue: 5159
branch: feat-one-shot-inngest-restart-reregister-5159
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-11-fix-inngest-restart-reregister-put-plan.md
date: 2026-06-11
---

# Tasks — inngest restart arm PUT /api/inngest re-registration

Derived from the finalized (post 5-agent-review) plan. Phase order is load-bearing: contract edits → tests → budget widening → docs → PIR.

## Phase 0 — Preconditions (verify, no code)

- [ ] 0.1 Confirm `/api/inngest` in `PUBLIC_PATHS` (`apps/web-platform/lib/routes.ts:16`) and `route.ts:84` still exports `PUT`.
- [ ] 0.2 Re-read #5145 drift-guard block (`ci-deploy.test.sh:2080–2151`); confirm current `DG_RIGHT=640s` (`DG_STOP=180`), `DG_LEFT=700s`, 60s slack.
- [ ] 0.3 Confirm bootstrap-context `:3000` reachability claim that scopes out the `inngest-bootstrap.sh:303` PUT (no window where neither path fires the PUT).

## Phase 1 — In-loop PUT in `verify_inngest_health` (RED→GREEN)

- [ ] 1.1 (RED) Add failing tests to `ci-deploy.test.sh`: in-loop wiring (PUT inside cron loop, before `/v1/functions` curl); PUT-fail tolerance (`MOCK_CURL_INNGEST_PUT_FAIL`); restart-fail-skip (`MOCK_SYSTEMCTL_FAIL` → PUT never invoked).
- [ ] 1.2 (GREEN) Add the in-loop PUT as the first statement inside the cron-plan loop in `apps/web-platform/infra/ci-deploy.sh` (after `:245` `for`, before the `/v1/functions` curl at `:246`): `curl -sf --max-time 10 -X PUT http://127.0.0.1:3000/api/inngest || true` with the ~5-line rationale comment. `--max-time 10` is fixed (NOT 5 — avoids the `VERIFY_FN_MAXTIME` pin collision, AC8b).

## Phase 2 — Test harness + budget correctness (RED→GREEN)

- [ ] 2.1 Add explicit `*":3000/api/inngest"*` mock case to the `curl` mock in `ci-deploy.test.sh` (before `esac`), honoring `MOCK_CURL_INNGEST_PUT_FAIL`.
- [ ] 2.2 Add PUT-count `==1` assertion, in-loop wiring assertion, restart-fail-skip assertion, coverage-honesty comment (mock proves wiring + tolerance, not efficacy).
- [ ] 2.3 **(BLOCKER)** Update the #5145 drift-guard formula (`ci-deploy.test.sh:2139`) to count the PUT `--max-time` by shape on the cron-loop term: `DG_RIGHT = DG_HEALTH×(DG_INTERVAL+5) + DG_CRON×(DG_INTERVAL+5+DG_PUT_MAXTIME) + DG_STOP + 60`. Extract `DG_PUT_MAXTIME` by shape (mirror `:2102–2108`); ADD the `DG_PUT_MAXTIME_COUNT` exactly-one check, integer-validate entry, count-check entry, and widen the FAIL message (`:2150`) — full 5-rule operand-extraction discipline. Update the comment block (`:2086–2094`).
- [ ] 2.4 **(BLOCKER)** Widen the client window in `.github/workflows/restart-inngest-server.yml:74–75`: `MAX_POLLS=240` (×5 = 1200s > server worst case ~1040s); update the inline arithmetic comment (`:69–74`) + file-level contract comment (`:5–7`) per the c2146e7a5/#5146 shape. ADD `timeout-minutes: 30` under `jobs.restart:` (none exists today; hygiene, not a correctness requirement). PUT stays `--max-time 10` (AC8b — do not lower without adding a `-X PUT` exclusion to the `:2068` pin grep).
- [ ] 2.5 Run `bash apps/web-platform/infra/ci-deploy.test.sh` — all green; confirm `VERIFY_FN_MAXTIME==2`, the drift guard PASSes WITH the PUT counted (`1200 > ~1040`), and the 5 existing restart-arm cases still pass.

## Phase 3 — Runbook + reason-taxonomy doc revisions

- [ ] 3.1 `cloud-scheduled-tasks.md`: remove the `docker restart soleur-web-platform` follow-up from the H9 automated-backstop (`:422`) and manual-fallback step 3 (`:429`); note the restart arm now self-registers (cite #5159); keep the no-SSH `/hooks/deploy-status` path primary.
- [ ] 3.2 `deploy-status-debugging.md:65`: revise the `inngest_health_failed` remediation — re-dispatch alone cannot recover; post-#5159 the in-loop PUT forces immediate resync.

## Phase 4 — PIR authoring

- [ ] 4.1 Author `knowledge-base/engineering/operations/post-mortems/inngest-restart-cron-deplan-2026-06-11-postmortem.md` from `plugins/soleur/skills/incident/templates/pir.md`: timeline (07:11→07:25, 09:04→09:15), root cause (re-sync asymmetry / push defeats poll), resolution (in-loop PUT + budget widening), `## Action Items & Follow-ups` with filed `#NNNN` issues (incl. the scoped-out bootstrap-path PUT) or the "No action items" sentence; frontmatter with `brand_survival_threshold` + GDPR Art. 33/34 fields.

## Phase 5 — Post-merge (operator, automated)

- [ ] 5.1 Merge with `Ref #5159` (not `Closes`) → `apply-deploy-pipeline-fix.yml` auto-applies `ci-deploy.sh`; the `restart-inngest-server.yml` window widening lands at merge. `/soleur:ship` Phase 5.5 covers the drift gate.
- [ ] 5.2 `gh workflow run restart-inngest-server.yml` → poll `/hooks/deploy-status` for `reason=success` (not `inngest_health_failed`) → confirm Sentry cron monitors (org `jikigai`) check in within the hour without a manual PUT → `gh issue close 5159`.

## Deferred (tracking issue required — create before PR ready)

- [ ] D.1 File a follow-up issue for the scoped-out `inngest-bootstrap.sh:303` post-restart PUT (re-eval criterion: if the deploy-inngest-arm in-loop PUT is observed racing the bootstrap restart; milestone "Post-MVP / Later"). Reference it in the PIR action-items table.
