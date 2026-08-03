# Tasks — Resend inbound webhook 500s (dispatch outage)

Plan: `knowledge-base/project/plans/2026-08-02-fix-resend-inbound-webhook-500-dispatch-outage-plan.md`
Branch: `feat-one-shot-resend-inbound-webhook-500`
Lane: `cross-domain` (fail-closed default — no spec.md existed)
Threshold: `single-user incident` → CPO signed off APPROVE-WITH-CHANGES; `user-impact-reviewer`
+ `observability-coverage-reviewer` + `data-integrity-guardian` at review.

**Read the plan's §Evidence and §Hypotheses first.** Post-review the diagnosis is much
tighter than it started: **H2, H5, H6 are REFUTED from committed code; H1 is near-refuted
by the errno; H4 (inngest not bound on :8288) is near-confirmed.** Do not re-open them.

---

> **RECONCILED with the deepened plan 2026-08-02.** Read the plan's
> **§Deepen-Plan Revisions** before starting — it lists blocking open items (schema
> described three different ways, a dangling "Phase 0.6", recovery paths with two
> idempotency keys, ACs pointing at deleted code paths). Also read §Enhancement Summary.
> **Root cause is now measured:** `soleur-inngest` was re-created 2026-07-30T15:13:06Z
> and its inngest has never bound `:8288` since. H3 refuted, H4 confirmed, onset
> recovered.

## Phase 0 — Probe before fixing. NO merge, time-boxed ≤4 h.

- [x] 0.0 **RUN FIRST.** `gh run list --workflow=scheduled-inngest-health.yml` + `gh issue
      list` over 2026-07-28→now. This 15-min external watchdog auto-dispatches
      `restart-inngest-server.yml` and files P1 issues. Either it fired (→ response
      failure; reshapes Phase 3) or it did not (→ it cannot see "nothing bound on :8288",
      a bigger finding than this plan).
- [x] 0.0b ~~**Try the cheap fix before any IaC:** `restart-inngest-server.yml`~~ **STRUCK
      (CTO ruling, ADR-155 Alternative D).** It restarts the WEB host's already-healthy
      co-located unit, never touches 10.0.1.40, and then confirms success via the same
      loopback probe that was already reporting green. It would have returned success
      having fixed nothing — the monitoring blind spot wearing a different hat. Do not
      dispatch it for this failure mode.
- [x] 0.1 File the tracking issue (`type/incident`). `Ref #6617` (**blocking dependency**),
      `Ref #7144`, `Ref #5697`. Body carries §Evidence.
      → Filed as **#7228**. NOTE: `type/incident` does not exist in this repo (the taxonomy
      is `type/{bug,chore,feature,question,security}`), so it carries `type/bug` +
      `priority/p1-high` + `domain/engineering`. Minting a sixth type label is a governance
      call, not a side effect of this filing — raised rather than silently substituted.
- [x] 0.2 **The one real probe (H3/H4).** `hcloud server describe` the dedicated host +
      its boot phone-home (`inngest-boot-phone-home.sh`) / vector stream. Correlate with
      the `SOLEUR_INNGEST_SERVER_PROBE` gap after 2026-07-30. Prior art to check first:
      `cloud-init-inngest.yml`'s doppler `/usr/bin` vs `/usr/local/bin` `ExecStart`
      status=203/EXEC bug — "inngest never bound :8288".
- [ ] 0.3 **H1 confirmation only (~5 min), not a gate.** `hcloud firewall describe`;
      expect zero rules on `hcloud_firewall.inngest` by design.
- [x] 0.4 **Was the ingress-probe Sentry monitor RED across the window?** Decides whether
      Phase 3 is aimed correctly. Red → this is a *response* failure and 3.5 is the real
      fix. Not red → the probe misses its own dominant failure mode (bigger finding).
- [x] 0.5 Onset recovery (**non-blocking**): Inngest run history + Resend delivery log for
      webhook `e0b3ba09-7a13-4f59-ba95-1ef1222bbdf8`. Else write `onset: UNKNOWN`.
- [ ] 0.6 Record `errno` (RST vs timeout) for every probe — the cheapest L3-vs-L7
      discriminator, and the one the original diagnosis discarded.
- [x] 0.7 **Exit gate:** first failing hop identified with an artifact + a remediation
      written for it. NOT "exactly one hypothesis". Time-box ≤4 h, then proceed on the
      best-supported hypothesis with a stated rollback.

**Do NOT** probe the container env (answered by `ci-deploy.sh`) or mint a Sentry token
(answered by `server/logger.ts`; moves to Phase 3).

## Phase 1 — Restore dispatch + discharge the statutory clock

- [x] 1.0 **Statutory reconciliation — before or with the remediation, NOT behind Phase 2.**
      Review the Proton `ops@soleur.ai` keep-copy for `2026-07-30 16:14 UTC → restoration`
      against the four rules in `lib/email-triage/statutory-rules.ts` (`breach-art33`,
      `service-of-process`, `dsar-art15`, `regulator-contact`). **Also verify the keep-copy
      held**, reconciled against the 15 known svix ids. Record findings against DPIA
      residuals + PA-27 Active Items in `compliance-posture.md`.
- [ ] 1.1 Remediate per Phase 0, **via IaC**. **Name the path**: signed config-refresh
      bundle (`infra-config-install.sh` / `INNGEST_CONFIG_DIGEST`, ADR-136/128) is
      preferred; a cloud-init edit is a **host REPLACE** (no `ignore_changes=[user_data]`)
      and the replacement boots with no hcloud firewall until the next full apply.
- [ ] 1.2 AC: any new `.tf` resource is either in the exclusion set in
      `plugins/soleur/test/terraform-target-parity.test.ts` or in the per-merge `-target`
      list with a stated no-dependency-edge to any `hcloud_*.inngest`. (Do NOT re-assert
      "no create" — `host_creates` already HALTs and is not `[ack-destroy]`-bypassable.)
- [ ] 1.3 Re-run the plan's B1 query post-deploy; assert `send_failed = 0`.

## Phase 2 — Decouple ingress from dispatch (RED first)

Shape is settled: **single table** (extend `processed_resend_events`), **unconditional**
persist-then-200, reconciler as **sole** dispatcher. Do not re-litigate.

> **HARD GATE — do not deploy the route cutover until AC11 (`send_failed = 0` from live,
> Phase-1-restored dispatch) is green AND the drain trigger has been observed advancing a
> row.** Otherwise the 200 releases the svix retry into a dispatcher that cannot dispatch.

- [ ] 2.0 **Create the drain's TRIGGER** — `.github/workflows/scheduled-resend-outbox-drain.yml`,
      modelled on `scheduled-zot-restart-loop.yml`, carrying
      `gate-override: new-scheduled-cron-prefer-inngest`. **`outbox-drain.ts` is a module;
      without this nothing calls it.** This was the plan's largest hole.
- [ ] 2.0b Column names: **`email_received_at`, NOT `received_at`** (it already exists —
      reusing it makes the drain replay insert-time as receive-time and corrupts a
      statutory clock). Keep `attachments` jsonb with a key-set CHECK (don't drop
      `contentType`). `status text NOT NULL DEFAULT 'legacy'`, `attempts int NOT NULL
      DEFAULT 0` — nullable is the *unsafe* shape (CHECK passes on NULL).

- [ ] 2.1 **RED** in `apps/web-platform/test/server/resend-inbound-route.test.ts`:
      well-formed → 200 + row persisted + **Inngest send mock NOT called**; persist fails
      → **release + 500** (assert *both* — without the release the svix retry
      short-circuits as a duplicate and the fallback becomes a data-loss path); duplicate
      svix_id → 200, no second row; malformed → 400, nothing persisted; reconciler
      dispatches exactly once, idempotent; reconciler with Inngest down leaves `pending`
      and bumps `attempts`. **Confirm they fail first.**
- [ ] 2.2 Migration `136_resend_inbound_durable_claim.sql` **+ `136_*.down.sql`**.
      **TYPED columns**, not open `payload jsonb` (ADR-055's discard guarantee is
      schema-enforced). `last_error_code`, not `last_error` (PA-28 synthetic-error
      precedent — a raw error echoes sender/subject into a column the scrub cannot reach).
      RLS **enabled with zero policies** + REVOKE from anon/authenticated (mig 102 §7
      shape). No `CREATE INDEX CONCURRENTLY`. Copy 102's `WHEN undefined_table THEN RAISE
      WARNING` handler.
- [ ] 2.3 **Retention: delete-on-drain primary** (row deleted / identifying fields nulled
      in the same transaction that confirms dispatch); backstop **≤30 days, 7 preferred**.
      **NOT 90-day parity** — that figure is a vendor-redelivery horizon for a PII-free
      two-column table and does not transfer.
- [ ] 2.4 Route: verify → insert-with-payload → 200. Remove inline dispatch.
- [ ] 2.5 `server/email-triage/outbox-drain.ts`. **Drain-stall alarm must NOT ride the
      Inngest substrate** (every cron is Inngest-fired — it cannot run during the outage
      it guards): use a GHA `schedule:` poller or a missed-check-in cron monitor. Drain =
      external poller (`dsar_export_jobs` precedent); `pg_cron` for retention only, daily
      (per-minute re-opens the #5738 WAL problem).
- [ ] 2.6 **Backfill the untriaged window UNCONDITIONALLY.** Enumerate Resend `GET /emails`
      over `[onset|2026-07-30, deploy]`, diff against `email_triage_items` +
      `processed_resend_events`, replay the difference. Window closes ~**2026-08-29**.
- [ ] 2.7 Redrive the 106 exhausted deliveries; per-message-id disposition list.
      **HARD CONSTRAINT:** `GET /emails` returns body/html/attachments — any backfill MUST
      enter at the same fused-step boundary as a live delivery, **never through the
      durable claim**. Asserted by test.
- [ ] 2.8 Amend ADR-055: `## Decision` + `## Alternatives Considered`. State **both**
      clauses — the release+500 contract is being amended; parse-and-discard is **not**
      violated (the claim sits upstream of the body fetch). Correct its stale
      "migration 094" retention citation → **102**.

## Phase 3 — Diagnosability

- [ ] 3.1 **Contained** fix, in the route: explicit `fingerprint` on its own
      `captureException` + stop the double-capture (log `String(err)`, or wrap as
      `new Error(msg, { cause: err })`). **Do NOT edit `server/logger.ts`** — it changes
      every server error path and is pinned by `logger-sentry-mirror.test.ts`.
- [ ] 3.2 Regression test: capture carries `feature=resend-inbound-webhook`, `op=inngest-send`.
- [ ] 3.3 Drain-stall alert in a **realizable** shape — there is no `sentry_metric_alert`
      in the provider (ADR-031 amendment). Use `sentry_issue_alert` on an emitted event, or
      `sentry_cron_monitor` on a missed check-in.
- [ ] 3.4 Comment the measured ~3-day Better Stack retention onto #5697.
- [ ] 3.5 **Operator-reaching channel** (gated on 0.4): make `cron-email-ingress-probe` an
      `action-required` emitter (5 sibling crons already are) + a one-time issue for this
      window. **Wording:** "Agent triage of ops@soleur.ai was down from `<onset>` to
      `<fix>`. Your Proton mailbox has every original. N re-triaged; M could not be."
      **Never** "you may be missing mail" — false and alarming.
- [ ] 3.6 Update the stale runbook
      `knowledge-base/engineering/operations/runbooks/inbound-email-ingress-dead.md`
      (HOP D is a private-net egress hop post-ADR-100, not loopback) and the same stale
      comment in `server/inngest/send-with-retry.ts`.

## Phase 4 — C4, legal, follow-through

- [ ] 4.1 `model.c4`: the durable-claim store + correct the `api -> inngest` description
      this change falsifies. `views.c4`: add the include line so it renders.
- [ ] 4.2 `./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts`.
- [ ] 4.3 **Extend PA-27; do NOT mint PA-34.** Limbs (c)/(d)/(f)/(g) + **TOM (11)** (its
      "~25.5h" claim is falsified — the failure ran ≥26 h and Resend surfaced it, not us).
      Derive ordinals by **numeric sort**, never `| tail` (the register is not in ordinal
      order — PA-17 precedes PA-16).
- [ ] 4.4 Lockstep `docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md`
      + repin `lib/legal/legal-doc-shas.ts` + `compliance-posture.md`. Add the LIA
      necessity-limb addendum.
- [ ] 4.5 `DSAR_TABLE_EXCLUSIONS` entry in `server/dsar-export-allowlist.ts` with a written
      reason. `test/dsar-allowlist-completeness.test.ts` is **blind** here (no FK to users).
- [ ] 4.6 If Phase 0 confirms H4 + a live co-located inngest: open the second ADR —
      "Complete or roll back the ADR-100 dedicated-Inngest cutover".
- [ ] 4.7 Enrol the soak follow-through
      (`scripts/followthroughs/resend-inbound-2xx-soak-<issue>.sh`, directive
      `earliest=<deploy+3d>`, `follow-through` label, secrets wired into
      `scheduled-followthrough-sweeper.yml`).

## Phase 5 — Verify (green CI is NOT proof)

- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/resend-inbound-route.test.ts`
      (vitest — `bunfig.toml` blocks bun discovery; **not** `npm run -w`, the repo root
      declares no `workspaces`).
- [ ] 5.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 5.3 **LIVE endpoint:** signed synthesized payload → **2xx**; unsigned control →
      still **401**.
- [ ] 5.4 Resend webhook still `status: enabled`; if flipped, re-enable via API in
      automation — never an operator step.
- [ ] 5.5 Sentry `op:inngest-send` returns ≥1 issue (was 0).
- [ ] 5.6 Backlog drained to zero; per-message disposition list in the PR body; any
      `unrecoverable` row → `action-required` issue.

## Guardrails

- No SSH (`hr-no-ssh-fallback-in-runbooks`). Every probe is an API/CLI call.
- No operator steps (`hr-never-label-any-step-as-manual-without`).
- `Ref #N`, not `Closes #N` — closure depends on a post-merge measurement.
- Fixtures synthesized only (`cq-test-fixtures-synthesized-only`).
- The durable claim is **hardening**, not the incident fix. If H4 confirms, this outage
  is one host's boot bug — label it so, and keep #6185 (Inngest HA) as the load-bearing
  follow-up.
