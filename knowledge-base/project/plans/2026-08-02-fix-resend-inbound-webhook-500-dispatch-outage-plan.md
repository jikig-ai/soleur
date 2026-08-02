# fix: Resend inbound webhook 500s — the ingress is healthy, its dispatch target is not

---
lane: cross-domain
type: bug-fix
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: TBD (file at /work Phase 0)
branch: feat-one-shot-resend-inbound-webhook-500
date: 2026-08-02
---

> Spec lacks valid `lane:` (no `spec.md` exists for this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Overview

Resend reports `https://app.soleur.ai/api/webhooks/resend-inbound` returning 500 since
2026-07-31 18:23 UTC and threatens auto-disable. **The route is not broken.** Every
observed 500 is the route's ADR-055 Step-5 case-(1) *transient dispatch* path firing
correctly: `inngest.send()` fails with `ECONNREFUSED 10.0.1.40:8288`, the route releases
the dedup row and returns 500 so the svix retry is honoured.

The defect is that the ingress's liveness is **hard-coupled to the Inngest event API's
liveness**, and Resend's auto-disable converts a "retry later" contract into permanent
data loss. ADR-055 chose release+500 on the assumption that retries are free. Against a
vendor that disables failing endpoints, that assumption is false.

Measured, not inferred (all figures self-pulled 2026-08-02, see §Evidence):

| Fact | Value | Source |
| --- | --- | --- |
| Share of route WARN+ rows that are `ECONNREFUSED 10.0.1.40:8288` | **100 %** (321/321) | Better Stack |
| Distinct svix deliveries failed in retained window | **15** | Better Stack `uniqExact` |
| Fleet-wide connection-refused rows to `10.0.1.40:8288`, 2026-08-01 alone | **17 531** | Better Stack |
| Live endpoint response to an unsigned POST, 2026-08-02 | **401** `Missing svix headers` | direct probe |
| Resend webhook status | **`enabled`** (not yet auto-disabled) | Resend API |
| Sentry issues matching `op:inngest-send` | **0** | Sentry API |

The last row is the observability defect: the route's dominant failure mode produced
**106 dispatch-failure log rows in Better Stack and zero findable Sentry issues**. An
agent that queried Sentry by route or op would have concluded the endpoint was fine.

Scope: this plan restores dispatch, decouples ingress liveness from dispatch liveness,
and closes the Sentry blind spot. It does **not** attempt the Inngest HA work already
tracked in #6185.

## Evidence

All commands are reproducible; none requires SSH.

**B1 — every route failure is dispatch, nothing else.**

```
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
  "SELECT toDate(dt) AS d,
          countIf(raw LIKE '%ECONNREFUSED%')                    AS econnrefused,
          countIf(raw LIKE '%inngest.send failed%')             AS send_failed,
          countIf(raw LIKE '%SECRET unset%')                    AS secret_unset,
          countIf(raw LIKE '%signature verification failed%')   AS sigfail,
          countIf(raw LIKE '%dedup insert failed%')             AS dedup_fail,
          count() AS total
     FROM (SELECT dt, raw FROM remote($BS_TABLE)
           UNION ALL SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3))
    WHERE raw LIKE '%resend-inbound-webhook%'
    GROUP BY d ORDER BY d FORMAT JSONEachRow"
```

| date | econnrefused | send_failed | secret_unset | sigfail | dedup_fail | total |
| --- | --- | --- | --- | --- | --- | --- |
| 2026-07-30 | 33 | 11 | 0 | 0 | 0 | 33 |
| 2026-07-31 | 153 | 51 | 0 | 0 | 1 | 154 |
| 2026-08-01 | 108 | 36 | 0 | 0 | 0 | 108 |
| 2026-08-02 | 24 | 8 | 0 | 0 | 0 | 25 |

Three rows per failed delivery = two `sendInngestWithRetry` warn rows + one final error.
`send_failed` therefore counts deliveries that exhausted retries: **106**.

**B2 — the error string.**
`fetch failed: connect ECONNREFUSED 10.0.1.40:8288`, emitted with
`deliveryId: msg_3HH1EAHFdKuORChEU9Xtx3UbFbr` from `CONTAINER_NAME=soleur-web-platform`.

**B3 — distinct blast radius.** `uniqExact(extract(raw,'msg_[A-Za-z0-9]+'))` = **15**
distinct svix message ids across 321 rows, window `2026-07-30 16:14:50` →
`2026-08-02 10:51:01`.

**B4 — Better Stack retention floor.** The *entire* table's earliest row is
2026-07-30 (78 706 rows that day, 163 304 on 07-31). Retention is ≈3 days.
**Retention does NOT cover a pre-onset baseline before 2026-07-30**, so Better Stack
cannot establish when this began — only that it was already happening ~26 h *before*
the 18:23 UTC 07-31 time Resend reported.

**B5 — the live endpoint, probed directly.**

```
curl -sS -X POST https://app.soleur.ai/api/webhooks/resend-inbound \
  -H 'content-type: application/json' -d '{"type":"email.received"}' -w '%{http_code}'
→ 401 {"error":"Missing svix headers"}
```

In `route.ts` the `RESEND_INBOUND_WEBHOOK_SECRET` guard (`"Server misconfigured"`, 500)
is ordered **before** the svix-header check. A 401 is therefore positive proof the
secret is present and the module loaded — which also clears the `INNGEST_SIGNING_KEY` /
`INNGEST_EVENT_KEY` module-load throw in `server/inngest/client.ts`.

**B6 — Resend webhook state.**
`GET https://api.resend.com/webhooks` with `RESEND_RECEIVING_API_KEY` returns
`{"id":"e0b3ba09-…","status":"enabled","endpoint":"https://app.soleur.ai/api/webhooks/resend-inbound","events":["email.received"]}`.
(`RESEND_API_KEY` is send-restricted and 401s on this path — use the receiving key.)

**B7 — Inngest is running, somewhere.** `_SYSTEMD_UNIT=inngest-server.service` is
emitting `msg:"received event"` as recently as 2026-08-02 10:47, with
`_CMDLINE=/usr/local/bin/inngest start --host 0.0.0.0 --port 8288 …`, on
`_MACHINE_ID=3f07b65531ab48b9b02d013c6b08feba` (the same machine id as the
`soleur-web-platform` app-container rows). So an Inngest process is healthy and
listening — while the app's connect to `10.0.1.40:8288` is refused.

**B8 — an unresolved contradiction.** Doppler `soleur/prd` holds
`INNGEST_BASE_URL=http://host.docker.internal:8288`, and `ci-deploy.sh` runs the
container with `--add-host host.docker.internal:host-gateway`. Neither should resolve to
`10.0.1.40`. `inngest-host.tf` pins `inngest_private_ip = "10.0.1.40"` (the dedicated
cax11 host). **Why the running container connects to 10.0.1.40 is NOT established.**
This is Phase 0's job to measure. It is not a detail — it decides whether the fix is
"restart a service", "repoint a variable", or "open a firewall".

**B9 — the Sentry blind spot.**

| query | result |
| --- | --- |
| `op:inngest-send`, 90 d | **0 issues** |
| `feature:resend-inbound-webhook`, 90 d | 1 issue (`132313366`), **4 events**, last 2026-07-31T14:33 |
| free-text `resend-inbound-webhook` | **0 issues** |

Meanwhile the same window carries 106 dispatch failures in Better Stack. The nearest
Sentry issue is `128795570 TypeError: fetch failed`, **culprit `POST /api/webhooks/github`**,
737 events, `lastSeen 2026-08-02T10:45:45Z`; its latest event carries
`feature=pino-mirror`, `transaction=POST /api/webhooks/github`. So the Resend route's
dispatch failures are, at best, grouped under another route's title and stripped of
their `feature` tag by the pino→Sentry mirror.

**Mechanism not yet isolated — but there is a named leading candidate.**
`/api/0/issues/<id>/events/` returns `Invalid token` for all three available Sentry
tokens, so I could not enumerate the grouped issue's events to prove *grouping* versus
*drop*. What is established from code: `apps/web-platform/server/logger.ts` mirrors
error-level pino lines to Sentry tagged `feature: "pino-mirror"` (pinned by
`apps/web-platform/test/server/logger-sentry-mirror.test.ts`, which asserts
`tags: { feature: "pino-mirror" }`), and it captures only when an `err` field is
present.

The route therefore emits **two** Sentry events per dispatch failure from the same
`err`: the mirror (via `logger.error({ err, … })`) and its own
`Sentry.captureException(err, { tags: { op: "inngest-send" } })`. Both carry an
identical stacktrace. **Leading candidate: `@sentry/nextjs`'s default `Dedupe`
integration drops the second as a duplicate**, and the survivor is the mirror — which
has already overwritten `feature` and carries no `op`. That would explain `op:inngest-send`
→ 0 issues exactly.

Corroborating (code-read, 2026-08-02): `apps/web-platform/sentry.server.config.ts`
customises `integrations` with
`(defaults) => defaults.filter(i => i.name !== "OnUncaughtException" && i.name !== "OnUnhandledRejection")`
— it removes only the two global handlers, so **the default `Dedupe` integration is
retained**. The candidate is therefore consistent with the configuration as committed,
not merely with the SDK's generic defaults.

This nonetheless remains **UNVERIFIED**. Phase 0.5 measures it. Do not implement against
the candidate before the measurement — if the real mechanism is grouping rather than
dedupe, the fix is different, and `Dedupe` is load-bearing elsewhere so removing it is
not a free move.

**B10 — live Terraform drift already names the firewall that carries this path.**
Open issue **#7144** (`infra: drift detected in web-platform`, opened 2026-08-01 18:01
UTC, `plan -detailed-exitcode` = 2) reports `Plan: 37 to add, 2 to change, 6 to destroy`,
and among them:

```
# terraform_data.cron_egress_firewall is tainted, so must be replaced
# terraform_data.container_restart_monitor_install is tainted, so must be replaced
# hcloud_server.registry must be replaced
      ~ user_data = (sensitive value) # forces replacement
```

`apps/web-platform/infra/cron-egress-firewall.test.sh` documents that this is the
ruleset under which the web host is *"allowed to reach the dedicated host
10.0.1.40:8288"*. **Tainted means its last apply failed** — the egress ruleset is in an
unknown state, on the exact path that is now refusing. This materially raises H1 above
the other three. It is corroboration, **not** confirmation: #7144 does not show the
ruleset's *live* content, and Phase 0.2 must still read it.

**B10a — a cheap discriminator nobody has run.** `ECONNREFUSED` is a TCP **RST**, not a
timeout. A firewall in `REJECT` mode produces RST; a firewall in `DROP` mode, and a
host that is simply dark, typically produce a **timeout**. So the symptom's *shape*
already argues for "something actively refused the connection" over "the packet went
nowhere". Phase 0 must record RST-vs-timeout explicitly for each probe — it separates
H1(REJECT) from H3(dark host) in one observation, and no probe run so far has captured
it.

## Hypotheses

`hr-ssh-diagnosis-verify-firewall` / the network-outage checklist fires: the symptom is
`ECONNREFUSED` to a private-network address. Layers are listed **L3 → L7**; no
service-layer fix may be prescribed before the layers above it are measured.

| # | Layer | Hypothesis | Status |
| --- | --- | --- | --- |
| H1 | L3 firewall | The private-net firewall / `hcloud_firewall` rule permitting web-host → `10.0.1.40:8288` has drifted or was replaced. `cron-egress-firewall.test.sh` documents this exact allow. Related in-flight work: #6415/#6438 private-NIC convergence. | **UNVERIFIED** — probe: `hcloud firewall describe` for the inngest host + the applied `cron-egress-firewall` ruleset, diffed against the committed rule. |
| H2 | L3 routing / address | The container's `host.docker.internal` → `host-gateway` mapping, or a stale container env, resolves to `10.0.1.40` when Doppler says otherwise (B8). | **UNVERIFIED** — probe: read the *running container's* effective `INNGEST_BASE_URL` and the resolved address, without SSH, via the infra-config/deploy-status webhook surface. |
| H3 | L3 host liveness | The dedicated Inngest host (cax11, `10.0.1.40`) is dark or was never (re)provisioned; #6617 already asks "the dedicated inngest host may be DARK — needs on-host confirmation". | **UNVERIFIED** — probe: `hcloud server describe` + the host's own vector/heartbeat stream. Note `SOLEUR_INNGEST_SERVER_PROBE` rows **stopped after 2026-07-30** (5 rows on 07-30, 0 since) and the `inngest-heartbeat` marker channel last emitted 2026-07-30 15:11 — consistent with H3 but **not decisive**, because absence proves nothing here by that marker's own design. |
| H4 | L7 service | `inngest-server.service` on the dedicated host is not listening on `:8288` even though the host is up. | **UNVERIFIED, and must not be assumed** — B7 shows an inngest process healthy on the *web* host's machine id. Whether a second one exists on the dedicated host is exactly what H3's probe answers. |
| H5 | L7 application | The route, its secret, its Supabase dedup, or its module-load guards are at fault. | **REFUTED** — B1 (0 secret/signature rows, 1 dedup row in 4 days) and B5 (live 401, which is ordered after the secret guard). |
| H6 | change correlation | A deploy or merge landing just before 2026-07-31 18:23 UTC introduced this. | **REFUTED** — `route.ts` has exactly one commit in its history (`b00289339`, #5125), nothing in the window; and B1 shows identical failures at the retention floor 2026-07-30 16:14, ≥26 h *before* the reported onset. The reported time is when **Resend** decided to alert, not when the failure began. |

**Explicit non-conclusion.** H1–H4 are all UNVERIFIED. The true onset is **UNKNOWN**:
Better Stack retention (B4) starts after the failures were already in progress, and the
Sentry channel that would have longer retention is exactly the one that is blind (B9).
No verdict may be written into any of H1–H4 from reasoning about the others.

## Research Reconciliation — brief vs. codebase

| Brief claim | Reality | Plan response |
| --- | --- | --- |
| "failing as of 2026-07-31 18:23 UTC" | Failures already present ≥26 h earlier at the Better Stack retention floor; true onset unknowable from retained telemetry | Treat 18:23 as the *alert* time. Phase 0 attempts onset recovery from Inngest run history / Resend delivery log; if unavailable, record UNKNOWN rather than adopting the vendor's timestamp. |
| "a deploy-introduced regression is the leading hypothesis" | Refuted (H6) | Hypothesis table leads with L3 layers, not change correlation. |
| "verify the channel is instrumented (grep the vector allowlist)" | `vector.toml` **does** ship this route: `[sources.app_container_journald]` matches `CONTAINER_NAME=["soleur-web-platform"]`, and `app_container_warn_filter` keeps pino `level >= 40`. The route's `logger.error` is level 50 → shipped. There is **no `SOLEUR_*` allowlist** for the app container — that mechanism (`host_scripts_journald`, exact `SYSLOG_IDENTIFIER` match) is for host bash scripts only. | Do **not** add a `SOLEUR_*` marker to the app container — it would be a second, weaker copy of a channel that already works. The real gap is Sentry (B9). Phase 3 fixes that instead. |
| "ship the component's own error channel first if it is missing" | Better Stack channel: present and working. Sentry channel: present but **unfindable by route or op**. | In scope, reshaped: fix discoverability, not existence. |
| "the route returning 2xx for well-formed payloads" | Naively contradicts ADR-055, which mandates release+500 on transient dispatch failure so svix retries | Resolved by making the *claim durable* before answering 2xx (Phase 2), so 2xx is honest — the event is persisted, not dropped. This is an ADR-055 amendment, not a violation. |
| Learnings agent recommended `docker exec` / `ssh` diagnosis steps | Violates `hr-no-ssh-fallback-in-runbooks` | Rejected. Every probe in this plan is an API/CLI call from the operator's machine or CI. |

## User-Brand Impact

**If this lands broken, the user experiences:** statutory and operational mail sent to
the operator address (vendors, regulators, counsel — the `emailSender` actor in
`model.c4`) never appears in the operator inbox. There is no error surface for them: the
inbox is simply, silently, missing a letter from a regulator.

**If this leaks, the user's data is exposed via:** the durable outbox introduced in
Phase 2 persists Resend `email.received` **metadata** (svix id, resend email id,
message-id, sender, subject, attachment filenames) at rest in Postgres. Subject and
sender are personal data; an over-broad RLS policy or an un-pruned table widens the
Art. 30 PA-27 processing footprint beyond the 90-day `processed_resend_events` window.

**Brand-survival threshold:** `single-user incident`.

A single dropped regulator email is a brand-survival event for a compliance-adjacent
product. CPO sign-off is required at plan time (see §Domain Review);
`user-impact-reviewer` runs at review time.

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open --limit 200`, then matched issue
bodies against each planned path (`app/api/webhooks/resend-inbound/route.ts`,
`server/inngest`, `infra/inngest`, `vector.toml`, `webhook-dedup`).

**None.** No open `code-review` issue names any file this plan edits.

Adjacent open issues (not `code-review`-labelled, disposition recorded):

- **#6617** *the dedicated inngest host may be DARK — possible double-scheduler; needs
  on-host confirmation* — **Fold in.** This is the same question as H3/H4. Phase 0's
  probe answers it; `Ref #6617` in the PR body and close it only if the probe is
  decisive.
- **#6185** *Inngest failover HA (primary/standby pair) — deferred from #6178* —
  **Acknowledge.** Phase 2's outbox reduces the blast radius of Inngest downtime but is
  not HA. #6185 stays open; add a note that this plan raises its priority.
- **#4074** *extract Inngest event-publisher helper for webhook routes* — **Acknowledge.**
  Phase 2 touches both the Resend and GitHub dispatch paths' failure handling; the
  extraction is tempting but is a refactor with its own blast radius during a live
  incident. Note in #4074 that Phase 2 makes it cheaper.
- **#5697** *raise soleur-inngest-prd log retention to cover exposure-investigation
  window* — **Fold in as evidence.** B4 is a live instance of exactly this: 3-day
  retention made the onset unknowable. Comment the measurement on #5697.

## Files to Edit

- `apps/web-platform/app/api/webhooks/resend-inbound/route.ts` — Phase 2 dispatch-failure
  branch; Phase 3 Sentry fingerprint/tag.
- `apps/web-platform/server/inngest/send-with-retry.ts` — surface a typed
  "target unreachable" outcome distinct from a generic throw, so the route can
  discriminate *transient-and-buffered* from *unexpected*.
- `apps/web-platform/test/server/resend-inbound-route.test.ts` — failing-first regression
  tests (Phase 2 RED).
- `apps/web-platform/sentry.server.config.ts` — Phase 3, only if the probe shows the pino
  mirror is overwriting `feature`/dropping the explicit capture.
- `knowledge-base/engineering/architecture/decisions/ADR-055-resend-inbound-as-third-multi-source-ingress.md`
  — amend `## Decision` + `## Alternatives Considered` (Phase 2).
- `knowledge-base/engineering/architecture/diagrams/model.c4` and `views.c4` — see
  §Architecture Decision.
- `knowledge-base/legal/article-30-register.md` — PA-27 footprint change if the outbox
  lands (verify the next free PA ordinal with
  `grep "^## Processing Activity" knowledge-base/legal/article-30-register.md | tail`).

## Files to Create

- `apps/web-platform/supabase/migrations/136_resend_inbound_durable_claim.sql` —
  (**verified 2026-08-02**: highest existing is `135_statutory_repin_send.sql`, so 136
  is next-free. Also verified: the `processed_resend_events` 90-day pg_cron retention
  job lives in **migration 102** (`102_email_triage_items.sql`, jobname
  `processed_resend_events_retention`) — **not** migration 094, which ADR-055's
  Consequences section cites. Correct that stale citation while amending the ADR.)
  Ships a `.down.sql` sibling, matching 102/134/135.
  extends `processed_resend_events` with `payload jsonb, status, attempts, last_error`
  plus the retention change. **Read the two most recent sibling migrations first**: the
  Supabase runner wraps each file in a transaction, so `CREATE INDEX CONCURRENTLY`
  fails at deploy with SQLSTATE 25001.
- `apps/web-platform/server/email-triage/outbox-drain.ts` — the reconciler.
- `scripts/followthroughs/resend-inbound-2xx-soak-<issue>.sh` — see §2.9.1.

Migration ordinal is provisional; re-derive it against `origin/main` at /work time.

## Implementation Phases

### Phase 0 — Probe first. Ships alone, before any fix.

Non-negotiable per the plan skill's probe-first rule: H1–H4 are unverified and the
apparatus that would discriminate them does not exist yet. Do not write a fix in this
PR.

0.1 File the tracking issue; `Ref #6617`.
0.2 Answer H1: pull the applied firewall state for the inngest host and diff against
    the committed `cron-egress-firewall` rule.
0.3 Answer H3: `hcloud server describe` the dedicated host; correlate with the
    `SOLEUR_INNGEST_SERVER_PROBE` gap after 2026-07-30.
0.4 Answer H2/B8: read the **running container's** effective `INNGEST_BASE_URL` and its
    resolved peer address via the deploy-status / infra-config webhook surface
    (`deploy.soleur.ai/hooks/deploy-status`, HMAC + CF Access from Doppler
    `prd_terraform`). **No SSH.** If no existing surface returns it, that absence is
    itself a Phase 3 deliverable — do not fall back to SSH.
0.5 Answer B9's mechanism: determine whether the route's `captureException` is *grouped*
    into `128795570` or *dropped*. If no available token can list issue events, mint or
    request the scope as part of this phase — an unreadable Sentry is an observability
    defect, not an acceptable constraint.
0.6 Attempt onset recovery: Inngest run history and the Resend delivery log for the
    webhook id from B6. If neither yields a pre-2026-07-30 boundary, record the onset as
    **UNKNOWN** in the PR body. Do not adopt the vendor's alert time as the onset.

**Exit gate:** the causal chain **route → observed connect target → refusal** is
confirmed end-to-end, with an artifact for each link, pasted into the PR body.

Deliberately *not* "exactly one of H1–H4 is confirmed": H1–H3 are **not mutually
exclusive**, and the B8 contradiction makes a compound cause likely rather than
exceptional — a stale baked-in container env (H2) pointing at a host that was
deprovisioned (H3) behind a ruleset whose last apply failed (H1, per B10) is jointly
true and internally consistent. A single-winner gate would either stall or force a
premature pick and a wrong Phase 1 fix.

### Phase 1 — Restore dispatch

Shape is decided by Phase 0's verdict, so it is deliberately not pre-written here.
Whatever it is, it MUST be Terraform / IaC per `hr-all-infrastructure-provisioning-servers`
(see §Infrastructure), never an operator SSH step. Immediately after: re-run the B1
query and assert `send_failed = 0` in a fresh window.

### Phase 2 — Decouple ingress liveness from dispatch liveness (RED first)

**Shape decided at plan time (advisor consult, ADR-083 gate).** Two alternatives were
rejected; recording them here so /work does not re-litigate:

- *Rejected: a separate `resend_inbound_outbox` table.* It duplicates the dedup table's
  job — a second unique constraint on the same `svix_id`, plus a persist/release
  ordering race between two tables. **Chosen instead: extend `processed_resend_events`
  with `payload jsonb, status, attempts, last_error`. The dedup insert *is* the outbox
  insert** — one write, one unique key, and the release-the-dedup-row branch mostly
  disappears.
- *Rejected: persist only when `inngest.send()` fails.* That makes the reconciler
  incident-only code — it would run for the first time at the worst possible moment,
  never exercised by normal traffic. It also has a real duplicate-dispatch bug:
  `inngest.send()` can fail client-side (timeout) *after* the event server accepted the
  event, and the reconciler then re-sends. **Chosen instead: persist-then-200 is
  UNCONDITIONAL and the reconciler is the SOLE dispatcher.** Safe because the route
  already sends `id: resend-${svixId}` and Inngest natively dedups on event id, so any
  double-send is idempotent. The route no longer calls `inngest.send()` inline, so
  ingress latency drops rather than rises.

2.1 **RED.** Add failing tests to `resend-inbound-route.test.ts`:
    - well-formed `email.received` → **200**, row persisted with `status='pending'` and
      the full event payload, **no inline `inngest.send` call at all**;
    - the persist itself failing → **500** (fail loud: nowhere durable to put it, so we
      must keep the vendor's retry). This is the sole remaining 500 path;
    - duplicate `svix_id` → 200, no second row, no re-dispatch;
    - malformed body → still 400, nothing claimed, nothing persisted;
    - reconciler dispatches a pending row exactly once, marks it `sent`, and is
      idempotent under re-run;
    - reconciler with Inngest unreachable leaves the row `pending` and increments
      `attempts` without dropping it.
    Confirm all fail before writing the implementation.
2.2 Migration: extend `processed_resend_events` (`payload jsonb`, `status`, `attempts`,
    `last_error`), RLS-locked to the service role. Retention is a **legal** decision —
    see §Domain Review → Legal; do not default to the existing 90 days without that
    answer, because the table now holds sender + subject rather than an id alone.
2.3 Route: signature-verify → insert-with-payload → 200. Remove the inline dispatch.
2.4 `outbox-drain.ts` reconciler, scheduled, oldest-first, bounded attempt budget,
    dead-letter threshold that pages.
2.5 **Recover the already-exhausted deliveries.** 106 deliveries exhausted their retries
    and are NOT recovered by anything above; the plan would otherwise "not lose mail"
    only prospectively. After Phase 1 restores dispatch, re-drive those svix message ids
    via the Resend/svix redelivery API, falling back to a backfill from
    `GET https://api.resend.com/emails` (verified 200 with `RESEND_RECEIVING_API_KEY`)
    for any the vendor will no longer redeliver.
2.6 Amend ADR-055 (`## Decision` + `## Alternatives Considered`): the release+500
    contract held only while retries were free; a vendor that auto-disables makes
    ingress-liveness coupling a data-loss risk.

### Phase 3 — Make this diagnosable from Sentry

3.1 **Fix the pino→Sentry mirror first, not the fingerprint.** The measured defect
    (B9) is that the mirror rewrites `feature` to `pino-mirror` *before* grouping — a
    per-route fingerprint alone treats the symptom and leaves the tag unsearchable.
    Stop the mirror overwriting a `feature` the call site already set; add the
    route-distinct fingerprint only if 0.5 shows grouping is *also* collapsing distinct
    routes after the tag is preserved.
3.2 Add a regression test asserting the route's dispatch-failure capture carries
    `feature=resend-inbound-webhook` and `op=inngest-send` and a route-distinct
    fingerprint.
3.3 Add a Sentry alert on the outbox depth / drain-failure signal, wired in
    `apps/web-platform/infra/sentry/`.
3.4 Comment the B4 retention measurement onto #5697.

### Phase 4 — Post-merge live verification

Green CI is not proof. See §Acceptance Criteria → Post-merge.

## Acceptance Criteria

### Pre-merge (PR)

1. PR body contains Phase 0's measured verdict for H1–H4, with the artifact, and an
   explicit `onset: <timestamp|UNKNOWN>` line.
2. `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/resend-inbound-route.test.ts`
   passes, and the four Phase-2.1 tests are present. (Runner is vitest per
   `apps/web-platform/vitest.config.ts`; its `include:` globs collect `test/**/*.test.ts`,
   so the file must stay under `test/server/`. Do **not** use `npm run -w` — the repo
   root declares no `workspaces`.)
3. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
4. The route no longer dispatches inline, and the persist-failure 500 is the only
   remaining 500 — asserted by the Phase-2.1 tests, not by reading the diff. Anchor
   assertion, not a bare-token grep: the test named for the persist-failure case must
   assert `status === 500`, and the happy-path test must assert the Inngest send mock
   was **not** called.
5. ADR-055 amended in this PR, not deferred; `grep -c 'auto-disable' <ADR-055>` ≥ 1.
6. C4: `model.c4` + `views.c4` updated per §Architecture Decision, and
   `./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts`
   passes.
7. Migration contains no `CREATE INDEX CONCURRENTLY` (transaction-wrapped runner):
   `grep -ci 'concurrently' <migration>` == 0.
8. PR body uses `Ref #6617`, not `Closes` — the closure depends on a post-merge
   measurement.

### Post-merge (operator-free — all automated)

9. Live endpoint, signed-payload probe against `https://app.soleur.ai/api/webhooks/resend-inbound`
   returns **2xx** using a synthesized svix signature minted from
   `RESEND_INBOUND_WEBHOOK_SECRET`. Fixture is synthesized, never a real inbound email
   (`cq-test-fixtures-synthesized-only`).
10. Unsigned control probe still returns **401** — proves the 2xx above is not a
    blanket-accept regression.
11. B1 re-run over a window starting after deploy shows `send_failed = 0`.
12. Resend webhook still `status: enabled`:
    `curl -H "Authorization: Bearer $RESEND_RECEIVING_API_KEY" https://api.resend.com/webhooks`
    → `.data[] | select(.endpoint=="https://app.soleur.ai/api/webhooks/resend-inbound") | .status` == `enabled`.
    **If it has flipped to disabled, re-enabling it is part of this PR's post-merge
    automation via the same API — not an operator step.**
13. Sentry: a deliberately-triggered dispatch failure produces an issue findable by
    `op:inngest-send` — i.e. the B9 query returns ≥1 issue where it previously returned 0.
14. Pending backlog drained to zero, asserted by query, not by dashboard.
15. **Recovery of the 106 exhausted deliveries is accounted for, per message id**, with
    each classified as `redelivered` / `backfilled-from-/emails` / `unrecoverable
    (reason)`. A count alone is not sufficient — an aggregate that says "106 handled"
    can be true while a specific regulator's letter is in the unrecoverable bucket
    unnoticed. This list goes in the PR body and, if any row is `unrecoverable`, into an
    `action-required` issue.

## Answers to the brief's two explicit questions

**Does the webhook need re-enabling in Resend?** **No, as of 2026-08-02 ~11:00 UTC** —
B6 shows `status: enabled`. The threat is live but unrealised. AC12 re-checks at
post-merge and automates the re-enable if it has flipped; it is never handed to the
operator.

**Were inbound events lost?** **Yes — 106 deliveries have exhausted their retries and
are dropped as of now. They are recoverable, and Phase 2.5 recovers them.** No loss is
yet *permanent*. Reasoning, with its limits stated:

- 106 deliveries exhausted `sendInngestWithRetry` (B1). Every one of those returned 500
  to Resend. Whether Resend/svix has also exhausted *its* redelivery schedule for a
  given message is per-message and is Phase 0.6's question — but "the endpoint 500'd and
  the retry budget ran out" is exactly the loss condition, so this must not be reported
  as "nothing was lost".

- The route **releases** the dedup row on dispatch failure, so nothing is permanently
  claimed — a later successful retry processes normally.
- **15 distinct** svix deliveries failed in the retained window (B3). The true total is
  larger and **unknown**, bounded below by 15, because retention starts after the
  failures began (B4).
- The emails themselves are retained by Resend for 30 days (ADR-055 / PA-27), and
  `GET https://api.resend.com/emails` responds 200 with the receiving key — so content
  is recoverable well past this incident even if webhook deliveries are exhausted.
- **What is not established:** whether svix has already exhausted its retry schedule for
  the oldest of those 15. Phase 0.6 pulls the Resend delivery log to find out; if any
  delivery is exhausted, Phase 2's drain is extended with a one-off backfill from the
  Resend `/emails` list.

## Observability

```yaml
liveness_signal:
  what: successful svix-signed POST → 2xx, asserted by the existing daily
        cron-email-ingress-probe (ADR-055) which sends a tokenized SOLEUR-PROBE-<uuid>
        marker through the full chain
  cadence: daily
  alert_target: Sentry cron monitor (issue 127593398 is this monitor's failure channel;
                9 events since 2026-06-12 — it fires, and it is already red)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf
error_reporting:
  destination: Sentry (route captureException) + Better Stack (pino level>=40 via
               vector app_container_warn_filter)
  fail_loud: true — the outbox-write failure path retains release+500
failure_modes:
  - mode: Inngest event API unreachable
    detection: outbox depth > 0 for longer than one drain interval
    alert_route: Sentry alert added in Phase 3.3
  - mode: outbox write fails (dispatch AND buffer both down)
    detection: route returns 500 with op=outbox-write; Better Stack B1 query
    alert_route: Sentry, findable by op — this is the Phase 3.1 fix
  - mode: drain reconciler stalls
    detection: oldest outbox row age exceeds threshold
    alert_route: Sentry alert, Phase 3.3
  - mode: Resend disables the webhook
    detection: AC12 status query, run on schedule not just post-merge
    alert_route: action-required issue
logs:
  where: Better Stack (soleur_inngest_vector_prd_3 + s3 archive); Sentry issues
  retention: Better Stack ~3 days (MEASURED, B4 — not the assumed window; this is
             why the onset is unknowable and why #5697 matters)
discoverability_test:
  command: >
    doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh
    "SELECT countIf(raw LIKE '%inngest.send failed%') AS send_failed
       FROM (SELECT dt, raw FROM remote($BS_TABLE)
             UNION ALL SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3))
      WHERE raw LIKE '%resend-inbound-webhook%' AND dt >= '<deploy-time>'
      FORMAT JSONEachRow"
  expected_output: '{"send_failed":0}'
```

No `ssh` appears in any command above.

### 2.9.1 Soak follow-through enrollment

AC11 and AC14 are time-gated (dispatch must stay clean past a drain cycle), so this
plan enrols a follow-through rather than leaving closure to memory:

- script: `scripts/followthroughs/resend-inbound-2xx-soak-<issue>.sh` — exit 0 when
  `send_failed = 0` over a window pinned strictly after deploy AND outbox depth is 0.
  Mirror `scripts/followthroughs/reconcile-ff-only-sentry-4977.sh`.
- tracker directive: `<!-- soleur:followthrough script=… earliest=<deploy+3d> secrets=BETTERSTACK_QUERY_* -->`
  plus the `follow-through` label.
- wire any new `secrets=` into `.github/workflows/scheduled-followthrough-sweeper.yml`.

### 2.9.2 Affected-surface observability

The Inngest host is a blind execution surface (no SSH, and B8 shows we cannot currently
answer what address the container is dialling). Phase 0.4's probe must emit **structured
fields that discriminate all of H1–H4 in one event** — at minimum
`{configuredBaseUrl, resolvedPeer, connectOutcome, firewallVerdict, hostState}` — not a
single boolean. A probe that only reports "unreachable" reproduces the exact blindness
that made this take two days.

## Infrastructure (IaC)

Phase 1's remediation is infrastructure and therefore routes through Terraform.

### Terraform changes

Scope depends on Phase 0's verdict, and exactly one of:

- **H1 confirmed** → firewall rule in the inngest host's `hcloud_firewall` /
  `cron-egress-firewall` set.
- **H2 confirmed** → `INNGEST_BASE_URL` corrected at its Doppler/Terraform source, then
  redeployed. Note `hr-prod-host-config-change-immutable-redeploy`.
- **H3 confirmed** → `apps/web-platform/infra/inngest-host.tf`; a re-provision must go
  through `terraform apply`, honouring `hr-fresh-host-provisioning-reachable-from-terraform-apply`.
- **H4 confirmed** → the unit definition in `inngest.tf` + the idempotent bootstrap
  script, applied via the existing bootstrap path.

### Apply path

Default: cloud-init + idempotent bootstrap script (existing infra). `-replace` only if
Phase 0 shows the host cannot be repaired in place. **Blast-radius warning:** the
inngest host is excluded from `apply-web-platform-infra.yml`'s `-target=` set. A new
resource that references it can transitively drag it into a routine merge-apply. Any new
`for_each`/reference must be gated on the same existence predicate its siblings use, and
an AC must assert `terraform plan` shows **no create** of the excluded resource.

### Distinctness / drift safeguards

`dev != prd` (`hr-dev-prd-distinct-supabase-projects`). No new no-default TF variable is
introduced; if Phase 0 forces one, it must exist in Doppler `prd_terraform` **before**
merge, because Terraform resolves every root variable before `-target` pruning.

### Vendor-tier reality check

No new vendor resource. Better Stack retention (B4, ~3 days) is a *tier* constraint that
already bit this investigation — flag it on #5697 rather than silently absorbing it.

## Architecture Decision (ADR/C4)

Phase 2 reverses a recorded decision, so the ADR is a deliverable of this plan.

### ADR

Amend **ADR-055**. Its `## Decision` mandates release+500 on transient dispatch failure.
Phase 2 makes the ingress buffer durably and answer 2xx. Add to `## Alternatives
Considered`: "keep release+500 — rejected: a vendor that auto-disables a failing endpoint
converts deferred retry into permanent loss." Prefer amending ADR-055 over minting a new
ordinal; if a new ADR is required, treat the ordinal as provisional and re-verify against
`origin/main` at ship time, sweeping plan/tasks/ACs for the old number.

### C4 views

Enumerated against all three files (`model.c4` 593 lines, `views.c4` 62, `spec.c4` 54),
not a keyword grep:

- **External human actor** — `emailSender` "Inbound Correspondent" (model.c4:14):
  already modelled.
- **External system** — `resend` (model.c4:254) with edges
  `emailSender -> resend`, `resend -> webapp`, `resend -> api`: already modelled.
- **Containers touched** — `inngest`, `inngestPostgres`, `inngestRedis`,
  and the relationship `api -> inngest "Sends events; serves functions"
  { technology "HTTP private-net :8288" }` (model.c4:443): already modelled.
- **New data store** — the Phase-2 `resend_inbound_outbox` is a **new persistent store
  on the ingress path**. It is **NOT** modelled. Adding it (element + relationships
  `api -> outbox`, `outbox -> inngest` via the drain, + the `views.c4` include line so
  it renders) is an in-scope task.
- **Access relationship changed** — `api -> inngest` stops being synchronous-critical
  for ingress. Its description asserts a coupling this change falsifies; correcting that
  description is in scope.

So: **C4 impact is real, and concentrated on the new store plus one falsified
description.** Run the C4 validation suites after editing — a `view include` naming an
undefined element fails there, not at `tsc`.

### Sequencing

The ADR is authored in the Phase-2 PR describing the target state. It is not deferred.

## Encryption Posture

Detection fires: Phase 2 adds a Supabase migration and a persistent store.

```yaml
at_rest:
  - store: processed_resend_events, EXTENDED with payload/status/attempts/last_error
           (Supabase Postgres, main app project). Not a new table — the dedup claim
           becomes the durable claim (Phase 2 shape decision).
    mechanism: provider-managed volume encryption, inherited by the table it extends
    evidence: to be cited at /work from the same attestation the sibling tables'
              posture entry cites — NOT "the provider handles it"
    defends_against: offline disk/snapshot seizure of the database volume
    does_not_defend: a compromised service-role key, a mis-scoped RLS policy, or any
                     read by the application itself — the payload is plaintext to
                     anyone holding the service role
    disclosed_as: Art. 30 PA-27 (extend the existing Resend-inbound processing entry;
                  verify the next free PA ordinal before writing)
    live_verification: query the table's storage posture at /work; if the project's
                       posture cannot be evidenced, ledger it as an exception with a
                       tracking issue and expiry rather than asserting it
in_transit:
  - connection: api container → Supabase (outbox write/drain)
    tls: yes
    cert_verification: on
    does_not_defend: an attacker with the service-role key
    disclosed_as: PA-27
  - connection: api container → Inngest event API, private net :8288
    tls: no — plaintext HTTP over the Hetzner private network
    cert_verification: n/a
    does_not_defend: an attacker with a foothold on the 10.0.1.0/24 private network can
                     read event payloads, including inbound-email metadata
    disclosed_as: pre-existing posture of `api -> inngest` (ADR-030/ADR-100); this plan
                  does not change it, but Phase 2 increases what transits it
exception:
  - subject: api → inngest plaintext private-net transport
    justification: pre-existing; changing it is out of scope for a live-incident fix
    tracking_issue: file at /work (sibling of #6894, which ledgers the plaintext
                    inngest_redis volume)
    reevaluate_when: the #6185 Inngest HA work reshapes this path
    expires_on: set at /work, ≤ 180 days
```

## Domain Review

**Domains relevant:** Engineering, Legal, Product.

### Engineering (CTO)

**Status:** to be reviewed inline (Phase 2.5 spawn).
**Assessment focus:** the ADR-055 reversal; whether an outbox is the right primitive
versus fixing Inngest HA (#6185); the blast-radius rule on `-target`-excluded resources.

### Legal (CLO / GDPR gate)

**Status:** gate fires — the change adds a Supabase migration, an API route change, and
persists personal data (sender, subject) in a new store.
**Assessment focus:** PA-27 footprint extension, retention parity with the 90-day
`processed_resend_events` policy, and whether buffering email metadata for longer than
the current window needs a distinct lawful-basis note.

### Product (CPO)

**Tier:** NONE for the UX gate — no file in §Files to Edit or §Files to Create matches a
UI-surface path (no `components/**/*.tsx`, no `app/**/page.tsx`, no `app/**/layout.tsx`).
No wireframe is required.
**But CPO sign-off IS required** independently, because
`brand_survival_threshold: single-user incident` (§2.6 Step 3). That sign-off is about
the dropped-regulator-email blast radius, not about page design.

**Brainstorm-recommended specialists:** none — no brainstorm preceded this plan
(one-shot path).

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| Phase 2's 2xx silently drops mail if the outbox write is not genuinely durable | The failing-first test for "outbox write also fails → 500" is the guard. It is written RED before the implementation, and AC4 asserts the fallback survives. |
| Resend auto-disables mid-fix | Phase 0 and Phase 1 precede Phase 2 precisely so dispatch is restored before the larger change. AC12 automates the re-enable. |
| Phase 0 confirms two hypotheses at once | Exit gate blocks progress and requires a discriminating probe rather than a guess. |
| The outbox becomes a second, unmonitored queue | Phase 3.3 alerts on depth and drain-stall; AC14 asserts drain-to-zero. |
| A new TF reference drags the `-target`-excluded inngest host into a routine merge-apply | Existence-predicate gate + an AC asserting `terraform plan` shows no create. |
| Adopting the vendor's 18:23 timestamp as fact | H6 refutes it; the plan records onset as UNKNOWN unless Phase 0.6 recovers it. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- **An empty Sentry query here is the *known* failure mode, not evidence.** B9 measured
  0 issues for `op:inngest-send` against 106 real failures. Any future claim that this
  route "has no errors" must cite Better Stack, not Sentry, until Phase 3 lands.
- **Better Stack retention is ~3 days, not the assumed soak window** (B4). Any AC or
  probe asking for a longer baseline gets a silently short answer.
- `RESEND_API_KEY` is send-restricted and 401s on `/webhooks`. Webhook state requires
  `RESEND_RECEIVING_API_KEY`.
- `/api/0/issues/<id>/events/` returns `Invalid token` for all three Sentry tokens in
  Doppler. Plan for the scope, do not plan around it.
- The route's 401-before-500 ordering is load-bearing evidence: a 401 from an unsigned
  probe proves the secret is set. Do not weaken that ordering.
