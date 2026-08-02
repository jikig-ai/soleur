# Tasks — Resend inbound webhook 500s (dispatch outage)

Plan: `knowledge-base/project/plans/2026-08-02-fix-resend-inbound-webhook-500-dispatch-outage-plan.md`
Branch: `feat-one-shot-resend-inbound-webhook-500`
Lane: `cross-domain` (fail-closed default — no spec.md existed)
Brand-survival threshold: `single-user incident` → CPO sign-off + `user-impact-reviewer` at review.

**Read the plan's §Evidence before starting.** The root cause is measured, not guessed:
every 500 is `inngest.send()` → `ECONNREFUSED 10.0.1.40:8288`. The route is healthy.

---

## Phase 0 — Probe first (SHIPS ALONE, no fix in this PR)

- [ ] 0.1 File the tracking issue. Body carries the plan's §Evidence table. `Ref #6617`,
      `Ref #7144`, `Ref #5697`. Label `type/incident`.
- [ ] 0.2 **H1 (L3 firewall).** Read the applied egress ruleset for web-host →
      `10.0.1.40:8288` and diff against the committed rule in
      `apps/web-platform/infra/cron-egress-firewall.test.sh`. Note #7144 reports
      `terraform_data.cron_egress_firewall` **tainted**.
- [ ] 0.3 **H3 (L3 host).** `hcloud server describe` the dedicated inngest host
      (`inngest_private_ip = "10.0.1.40"`, `apps/web-platform/infra/inngest-host.tf`).
      Correlate with `SOLEUR_INNGEST_SERVER_PROBE` rows stopping after 2026-07-30.
- [ ] 0.4 **H2 (L3 address).** Read the RUNNING container's effective `INNGEST_BASE_URL`
      and resolved peer via `deploy.soleur.ai/hooks/deploy-status` (HMAC + CF Access,
      Doppler `prd_terraform`). Resolves the B8 contradiction. **No SSH.** If no surface
      returns it, that gap is a Phase 3 deliverable — do not fall back to SSH.
- [ ] 0.5 **Record RST vs timeout** for every probe (B10a). This alone separates
      H1(REJECT) from H3(dark host).
- [ ] 0.6 **B9 mechanism.** Determine grouping vs `Dedupe`-drop. Leading candidate is the
      `Dedupe` integration (retained in `sentry.server.config.ts`) discarding the route's
      own capture in favour of the `pino-mirror` one. Mint/obtain the Sentry scope needed
      to list `/api/0/issues/<id>/events/` — an unreadable Sentry is a defect, not a
      constraint.
- [ ] 0.7 **Onset recovery.** Inngest run history + Resend delivery log for webhook
      `e0b3ba09-7a13-4f59-ba95-1ef1222bbdf8`. If no pre-2026-07-30 boundary is
      recoverable, write `onset: UNKNOWN`. Do NOT adopt the vendor's 18:23 alert time.
- [ ] 0.8 **Exit gate.** The chain route → observed connect target → refusal is confirmed
      end-to-end with an artifact per link. H1–H3 may be *jointly* true; do not force a
      single winner.

## Phase 1 — Restore dispatch

- [ ] 1.1 Implement the remediation indicated by Phase 0, **via Terraform / IaC**
      (`hr-all-infrastructure-provisioning-servers`). No operator SSH step.
- [ ] 1.2 If a new TF reference could pull the `-target`-excluded inngest host into a
      routine merge-apply, gate it on the same existence predicate its siblings use.
- [ ] 1.3 Assert `terraform plan` shows **no create** of the excluded resource.
- [ ] 1.4 Re-run the plan's B1 query over a post-deploy window; assert `send_failed = 0`.

## Phase 2 — Decouple ingress from dispatch (RED first, `cq-write-failing-tests-before`)

Shape is already decided in the plan — do not re-litigate. Persist-then-200 is
**unconditional**; the reconciler is the **sole** dispatcher; the store is the
**existing** `processed_resend_events`, extended.

- [ ] 2.1 **RED.** Add to `apps/web-platform/test/server/resend-inbound-route.test.ts`:
      well-formed → 200 + row persisted + **Inngest send mock NOT called**; persist
      fails → 500 (only remaining 500); duplicate svix_id → 200, no second row;
      malformed → 400, nothing persisted; reconciler dispatches exactly once and is
      idempotent; reconciler with Inngest down leaves `pending` and bumps `attempts`.
      **Confirm they fail first.**
- [ ] 2.2 Migration `136_resend_inbound_durable_claim.sql` + `.down.sql`. Extend
      `processed_resend_events` (`payload jsonb, status, attempts, last_error`),
      RLS-locked to the service role. **No `CREATE INDEX CONCURRENTLY`** (the runner
      wraps each file in a transaction → SQLSTATE 25001). Retention per the Legal answer,
      not a default copy of the existing 90 days.
- [ ] 2.3 Route: verify → insert-with-payload → 200. Remove inline dispatch.
- [ ] 2.4 `apps/web-platform/server/email-triage/outbox-drain.ts` — scheduled,
      oldest-first, bounded attempts, dead-letter threshold that pages.
- [ ] 2.5 **Recover the 106 exhausted deliveries.** Redrive via Resend/svix redelivery;
      fall back to backfill from `GET https://api.resend.com/emails`
      (`RESEND_RECEIVING_API_KEY` — the send-scoped `RESEND_API_KEY` 401s). Produce a
      per-message-id disposition list.
- [ ] 2.6 Amend ADR-055 `## Decision` + `## Alternatives Considered`. Also correct its
      stale "migration 094" retention citation → **102**.

## Phase 3 — Diagnosability

- [ ] 3.1 Fix the **pino→Sentry mirror overwriting `feature`** (the measured defect), not
      just the fingerprint. Add a route-distinct fingerprint only if 0.6 shows grouping
      also collapses routes after the tag is preserved.
- [ ] 3.2 Regression test: dispatch-failure capture carries `feature=resend-inbound-webhook`
      and `op=inngest-send`.
- [ ] 3.3 Sentry alert on pending-backlog depth + drain-stall, in
      `apps/web-platform/infra/sentry/`.
- [ ] 3.4 Comment the measured ~3-day Better Stack retention (plan B4) onto #5697.

## Phase 4 — C4, legal, follow-through

- [ ] 4.1 `model.c4`: the durable-claim store on the ingress path + correct the
      `api -> inngest "Sends events; serves functions"` description this change
      falsifies. `views.c4`: add the include line so it renders.
- [ ] 4.2 Run `./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts`.
- [ ] 4.3 Art. 30 register per the Legal answer (verify the next free PA ordinal with
      `grep "^## Processing Activity" knowledge-base/legal/article-30-register.md | tail`
      — do NOT assume PA-27 is free/correct).
- [ ] 4.4 Enrol the soak follow-through:
      `scripts/followthroughs/resend-inbound-2xx-soak-<issue>.sh`, tracker directive
      `<!-- soleur:followthrough script=… earliest=<deploy+3d> secrets=BETTERSTACK_QUERY_* -->`,
      `follow-through` label, and wire secrets into
      `.github/workflows/scheduled-followthrough-sweeper.yml`.

## Phase 5 — Verify (green CI is NOT proof)

- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/resend-inbound-route.test.ts`
      (vitest, not `bun test` — `bunfig.toml` blocks bun discovery; not `npm run -w` —
      the repo root declares no `workspaces`).
- [ ] 5.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 5.3 **Post-merge, against the LIVE endpoint:** signed synthesized payload → **2xx**;
      unsigned control → still **401**.
- [ ] 5.4 Resend webhook still `status: enabled`; if flipped, re-enable via the API in
      automation — never an operator step.
- [ ] 5.5 Sentry: `op:inngest-send` now returns ≥1 issue (was 0).
- [ ] 5.6 Pending backlog drained to zero; per-message disposition list for the 106 in the
      PR body, with any `unrecoverable` row escalated to an `action-required` issue.

## Guardrails

- No SSH anywhere (`hr-no-ssh-fallback-in-runbooks`). Every probe is an API/CLI call.
- No operator steps (`hr-never-label-any-step-as-manual-without`,
  `wg-block-pr-ready-on-undeferred-operator-steps`).
- `Ref #N`, not `Closes #N` — closure depends on a post-merge measurement.
- Test fixtures synthesized only; never a real inbound email
  (`cq-test-fixtures-synthesized-only`).
