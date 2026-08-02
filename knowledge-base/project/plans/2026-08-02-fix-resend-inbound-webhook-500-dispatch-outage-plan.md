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

**B8 — the apparent contradiction, RESOLVED (CTO review, 2026-08-02).** Doppler
`soleur/prd` holds `INNGEST_BASE_URL=http://host.docker.internal:8288`, which looked
irreconcilable with an observed connect to `10.0.1.40`. It is not:
**`apps/web-platform/infra/ci-deploy.sh` hardcodes `-e INNGEST_BASE_URL=http://10.0.1.40:8288`
at both the canary and prod `docker run` sites, placed AFTER `--env-file "$ENV_FILE"`,
so it overrides whatever Doppler renders.** Landed in `b02870e1d` (#6348, 2026-07-24 —
the ADR-100 cutover step 2.4); `server/inngest/client.ts`'s header states the same
intent, and `test/server/inngest/cron-inngest-cron-watchdog.test.ts` greps `ci-deploy.sh`
for that exact literal as a parity guard.

**Dialing `10.0.1.40:8288` is correct behaviour, not a mystery.** Any "fix" that
repoints `INNGEST_BASE_URL` at its Doppler/Terraform source would undo the ADR-100
cutover and break that parity guard.

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

The route therefore emits **two** Sentry events per dispatch failure from the same `err`:
the mirror (via `logger.error({ err, … })`) and, immediately after, its own
`Sentry.captureException(err, { tags: { op: "inngest-send" } })`. Same `Error` instance,
same undici `TypeError: fetch failed` stack.

**Mechanism (CTO review): GROUPING, not a drop.** Two events, one default fingerprint →
one issue; the issue-level `feature` tag last-writes to `pino-mirror`. That is exactly
the shape B9 measured — issue `128795570`, culprit `POST /api/webhooks/github`,
`feature=pino-mirror`. My earlier `Dedupe`-drop candidate is superseded: it is not needed
to explain the observation, and grouping does.

**The fix must be contained, and the obvious file is the wrong one.** The mirror lives in
`apps/web-platform/server/logger.ts` (not `sentry.server.config.ts`) and is pinned by
`test/server/logger-sentry-mirror.test.ts`. Editing it changes **every server error path
in the app** — not a live-incident change. Contained alternative, two lines in the route:
set an explicit `fingerprint` on the route's own `captureException`, and stop the
double-capture by not handing the raw `Error` to `logger.error` (log `String(err)`), or
wrap as `new Error(msg, { cause: err })` so the stack is route-distinct.

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
10.0.1.40:8288"*. Tainted means its last apply failed. **This is worth applying, but it
is NOT this incident's cause — see B10a, which reverses the reading I first gave it.**

**B10a — the errno is decisive, and it points AWAY from the firewall.**
`ECONNREFUSED` is a TCP **RST**. **Every filtering layer on the web→inngest path DROPs,
and a drop yields `ETIMEDOUT`, never `ECONNREFUSED`:**

- `apps/web-platform/infra/cron-egress-nftables.sh` — default `counter drop`, and it
  carries an **explicit accept**:
  `ip daddr 10.0.1.40 tcp dport 8288 accept comment "soleur-egress: dedicated inngest host (#6178)"`,
  asserted post-apply by `cron-egress-postapply-assert.sh`.
- `apps/web-platform/infra/cloud-init-inngest.yml` (host-local, SEC-H2) —
  `tcp dport { 8288, 8289 } ip saddr { ${web_host_private_ips} } accept` then a `drop`.
  `web_host_private_ips = "10.0.1.10,10.0.1.11"`; web-1 is `.10`, so it is allowed.
- `hcloud_firewall.inngest` (`inngest-host.tf`) has **zero rules by design** — its header
  records that intra-`10.0.1.0/24` traffic needs no allow rule and a scoping rule would
  be a no-op (SEC-H1). **There is nothing there to drift.**

So `ECONNREFUSED` = **a reachable host with nothing bound on `:8288`**. That exact
failure has documented prior art *on this host*, in `cloud-init-inngest.yml`: *"every
unit died with systemd status=203/EXEC and inngest never bound :8288"* — the doppler
`/usr/bin` vs `/usr/local/bin` `ExecStart` mismatch. It fits B7 (a healthy inngest on the
**web** host's machine id — #6617's suspected double-scheduler) and the
`SOLEUR_INNGEST_SERVER_PROBE` rows stopping after 2026-07-30.

**Correction to my own first reading.** I initially cited B10 as raising H1. That was
wrong in direction: because every layer DROPs rather than REJECTs, the RST is evidence
*against* a filtering cause and *for* "nothing listening". Recording the reversal rather
than quietly editing it, because the tainted-firewall row is exactly the kind of
plausible-adjacent artifact that attracts a wrong verdict.

## Hypotheses

`hr-ssh-diagnosis-verify-firewall` / the network-outage checklist fires: the symptom is
`ECONNREFUSED` to a private-network address. Layers are listed **L3 → L7**; no
service-layer fix may be prescribed before the layers above it are measured.

| # | Layer | Hypothesis | Status |
| --- | --- | --- | --- |
| H1 | L3 firewall | A filtering layer between web-1 and `10.0.1.40:8288` drifted. | **NEAR-REFUTED** (B10a). Every layer on the path DROPs, not REJECTs, so none can produce the observed RST; `cron-egress-nftables.sh` carries an explicit accept for this exact destination, and `hcloud_firewall.inngest` has zero rules by design. Downgraded from a gate to a 5-minute `hcloud firewall describe` confirmation. #6415 is **CLOSED**; the live convergence work is #6438. |
| H2 | L3 routing / address | The container dials `10.0.1.40` when Doppler says `host.docker.internal`. | **REFUTED** (B8). `ci-deploy.sh` hardcodes `-e INNGEST_BASE_URL=http://10.0.1.40:8288` after `--env-file`, deliberately, per ADR-100 (#6348). Repointing it would undo the cutover and break a parity guard. **No remediation branch for H2.** |
| H3 | L3 host liveness | The dedicated Inngest host (cax11, `10.0.1.40`) is dark or was never re-provisioned. #6617 already asks exactly this. | **UNVERIFIED — this is the real probe.** `hcloud server describe` + the host's own boot phone-home (`inngest-boot-phone-home.sh`) / vector stream. Note the RST in B10a implies the host *is* reachable, which argues H3-dark is unlikely and H4 likely — but a describe is cheap and settles it. |
| H4 | L7 service | The host is up, but `inngest-server.service` is not bound on `:8288`. | **NEAR-CONFIRMED** — the only hypothesis consistent with an RST (B10a), and with documented prior art on this same host: `cloud-init-inngest.yml` records *"every unit died with systemd status=203/EXEC and inngest never bound :8288"* (doppler `/usr/bin` vs `/usr/local/bin` `ExecStart`). Corroborated by the `SOLEUR_INNGEST_SERVER_PROBE` gap after 2026-07-30 and by B7's healthy inngest on the **web** host (#6617's double-scheduler). |
| H5 | L7 application | The route, its secret, its dedup, or its module-load guards are at fault. | **REFUTED** — B1 (0 secret/signature rows, 1 dedup row in 4 days) and B5 (live 401, ordered *after* the secret guard). |
| H6 | change correlation | A deploy/merge just before 2026-07-31 18:23 UTC introduced this. | **REFUTED** — `route.ts` has one commit ever (`b00289339`, #5125), nothing in the window; B1 shows identical failures at the retention floor, ≥26 h before the reported time. That time is when **Resend** alerted, not when the failure began. |

**Where this leaves the diagnosis.** H2 and H5/H6 are refuted from committed code. H1 is
near-refuted by the errno. **H3/H4 is the live question, and it is one probe wide:** is
the host up with a dead unit (H4), or dark (H3)? Both have the same first remediation
step and differ only in blast radius (see §Infrastructure — H4's cloud-init path is a
host *replace*).

**The true onset remains UNKNOWN.** Better Stack retention (B4) begins after the failures
were already running, and the Sentry channel that would carry longer history is the one
that is blind (B9). Do not backfill a verdict onto the onset from the remediation.

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

**If this lands broken, the user experiences:** a letter from a regulator that reached
their mailbox and was **never surfaced for triage** — no `email_triage_items` row, no
statutory clock stated, no nav badge, no push. What is lost is the **delegation**, not
the correspondence: ADR-055's Sieve rule is **forward-and-keep**, so the Proton
`ops@soleur.ai` mailbox remains the durable original throughout (Phase 1.0 verifies this
actually held). Saying "you may be missing mail" would be both false and alarming.

**The precise failure vector is silence-shaped.** This feature's only liveness cue is
**positive-signal-only**: a nav badge and a `notifyOfflineUser` push that fire when a
triage row appears. During the outage no event fires, so there is no badge and no push —
and that is **indistinguishable from a genuinely quiet week**. `operator-digest` does not
read ingest health either, so a dead ingress renders as an empty inbox. The operator
cannot tell "nothing arrived" from "everything was dropped".

**This change introduces its own artifact.** Phase 2 makes the route answer **2xx**,
which permanently releases the svix retry. If the durable write succeeds but the drain
stalls or dead-letters, the mail is acknowledged-to-vendor, stranded in a table no user
surface reads, **with the vendor retry gone** — strictly worse than today's 500. The
write-failure path is tested (2.1) and keeps the 500; the **drain**-failure path must not
be engineer-facing only (Sentry alert 3.3), which is why 3.5 routes it to the operator.

**If this leaks, the user's data is exposed via:** the extended
`processed_resend_events` persists inbound **metadata** (resend email id, message-id,
sender, subject, attachment filenames). Sender and subject are personal data — subject
especially is content-bearing, which is why PA-27's statutory fast-path keys on it, and
PA-27 concedes Art. 9 data may arrive unsolicited on an open address. RLS enabled with
zero policies + REVOKE is the control; an over-broad policy, an un-pruned backstop, or a
raw `last_error` string echoing the request body each widen the PA-27 footprint.

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
  on-host confirmation* — **BLOCKING DEPENDENCY**, upgraded from "fold in" at CTO review.
  It asks the same host question as H3/H4 and its answer *gates Phase 1's shape* (and, if
  the double-scheduler is real, forces the ADR-100 fork). `Ref #6617`; close only if
  Phase 0 is decisive.
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
- **NOT** `apps/web-platform/sentry.server.config.ts` — the mirror is in
  `apps/web-platform/server/logger.ts`, pinned by
  `test/server/logger-sentry-mirror.test.ts`, and editing it changes every server error
  path in the app. Phase 3.1 uses the contained in-route fix instead.
- `apps/web-platform/server/inngest/send-with-retry.ts` — its comment still says
  "loopback to 127.0.0.1:8288", false since ADR-100.
- `knowledge-base/engineering/operations/runbooks/inbound-email-ingress-dead.md` — the
  existing L3→L7 no-SSH runbook for this exact chain. Its topology still says
  *"HOP D: inngest.send (127.0.0.1:8288, self-hosted, ADR-030) [loopback, NOT egress]"*
  and asserts the egress firewall cannot reach that hop. Post-ADR-100 that is **false**;
  HOP D is a private-net egress hop. Leaving it stale is how the next responder repeats
  this incident.
- `apps/web-platform/server/dsar-export-allowlist.ts` — the extended table needs an
  explicit `DSAR_TABLE_EXCLUSIONS` entry with a written reason. **`test/dsar-allowlist-completeness.test.ts`
  is structurally blind here**: it enforces classification only for tables with an FK to
  `public.users`/`auth.users`, and this table has none — so the lint passes while the gap
  is real.
- `docs/legal/privacy-policy.md`, `docs/legal/gdpr-policy.md`,
  `docs/legal/data-protection-disclosure.md` — lockstep per the #6781 precedent (which
  did this for a table carrying *no* PII; a new PII-at-rest surface cannot do less). The
  GDPR Policy is the one most often missed.
- `apps/web-platform/lib/legal/legal-doc-shas.ts` — repin `LEGAL_DOC_SHAS`, else
  `test/legal-doc-shas-guard.test.ts` fails.
- `knowledge-base/legal/compliance-posture.md` — lockstep comment + PA-27 Active Items.
- `knowledge-base/legal/legitimate-interest-assessments/2026-06-11-operator-inbox-triage-lia.md`
  — necessity-limb **addendum**. No re-run is triggered, but the LIA's necessity limb is
  premised on minimisation and would otherwise describe a system that no longer exists.
  The balancing actually *improves*: a dropped DSAR is worse for the involuntary data
  subject than a short-lived buffer. Say so.
- `knowledge-base/engineering/architecture/decisions/ADR-055-resend-inbound-as-third-multi-source-ingress.md`
  — amend `## Decision` + `## Alternatives Considered` (Phase 2).
- `knowledge-base/engineering/architecture/diagrams/model.c4` and `views.c4` — see
  §Architecture Decision.
- `knowledge-base/legal/article-30-register.md` — **extend PA-27, do NOT mint a new PA.**
  PA-27 is confirmed as the Resend-inbound entry, and the `statutory_repin_send`
  precedent (migration 135, #6781) folded a sub-table in with the explicit finding "NO
  new Article 30 Processing Activity". A separate PA would fragment one activity.
  Limbs (c) sub-table + no-body statement, (d) — the limb currently calls the Inngest
  event store "**the third PII surface**", which this change falsifies — (f) retention +
  Art. 17 path, (g) new TOM entry, and **(g) TOM (11)**, whose "pages within ~25.5h worst
  case" claim this incident falsified: the failure ran ≥26 h and was surfaced by
  **Resend**, not by our monitor. A control that fires and is never actioned is not an
  Art. 32 measure — restate it or fix the routing; leaving it overstated is worse under
  Art. 5(2).
  **Ordinal derivation:** do NOT use `… | tail` — the register is **not in ordinal
  order** (PA-17 precedes PA-16 in the file), so `tail` is right today only by luck. Use
  a numeric sort. (Next free is PA-34; it is not needed.)

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

### Phase 0 — Probe before fixing. Runs before the fix PR; produces NO merge.

Probe-*before-fix* is non-negotiable. Probe-*as-its-own-shipped-PR* is not, and is
dropped: steps 0.2–0.4 are **read-only** API/CLI calls that author nothing, so a
probe-only PR would buy a full CI+review+merge+deploy cycle whose only payload is
measurements pasted into a PR body — during a live incident. The ordering discipline the
rule exists to protect is fully preserved.

Phase 0 shrank after review resolved H2 and H1 from committed code:

0.1 File the tracking issue. `Ref #6617` — **it is a blocking dependency, not a
    fold-in**: it asks the same host question and its answer gates Phase 1's shape.
0.2 **H3/H4 — the one real probe.** `hcloud server describe` the dedicated host, plus
    its own boot phone-home (`inngest-boot-phone-home.sh`) / vector stream. Correlate
    with the `SOLEUR_INNGEST_SERVER_PROBE` gap after 2026-07-30.
0.3 **H1 — confirmation only, not a gate** (~5 min): `hcloud firewall describe`. Expect
    zero rules on `hcloud_firewall.inngest` by design.
0.4 **Was the ingress probe's monitor RED across the window?** Cheap, and it decides
    whether Phase 3 is even aimed correctly. Both branches are damning:
    - **Red** → detection worked, and
      `knowledge-base/engineering/operations/runbooks/inbound-email-ingress-dead.md`
      already exists with exactly this entry condition. Two days elapsed anyway → this is
      a **response** failure, and adding more Sentry signal (3.1/3.3) to a channel that
      already produced no response does not fix it. Phase 3 must then add an
      operator-reaching channel (3.5).
    - **Not red** → the designed end-to-end probe misses its own dominant failure mode,
      which is a larger finding than anything else in this plan.
0.5 Onset recovery, **non-blocking**: Inngest run history + the Resend delivery log for
    webhook `e0b3ba09-7a13-4f59-ba95-1ef1222bbdf8`. If no pre-2026-07-30 boundary is
    recoverable, write `onset: UNKNOWN`.

Dropped from Phase 0: the container-env read (H2 answered by `ci-deploy.sh`) and the
Sentry-grouping probe (answered by `server/logger.ts`; see B9 revision). **Minting a
Sentry token must not gate outage remediation** — that moves to Phase 3.

**Exit gate:** the **first failing hop on the dispatch path is identified with an
artifact, and a remediation is written for it.** Hard time-box **≤4 h**, after which
Phase 1 proceeds on the best-supported hypothesis with a stated rollback.

Deliberately *not* "exactly one of H1–H4 confirmed". That shape is unsatisfiable in the
most likely world — H3 and H4 are nested, and the probable truth is compound (host up +
`inngest-server.service` dead + a stale co-located inngest still running on web-1,
per #6617). It also has no time-box, which makes it a stop-the-world clause on a
brand-survival incident with a vendor auto-disable clock running. Gate on the remediable
fact, not on hypothesis identity.

### Phase 1 — Restore dispatch, and discharge the statutory clock

**1.0 — Statutory reconciliation of the outage window. Runs before or with the
remediation; it may NOT ride behind Phase 2.** PA-27's primary purpose is deterministic
detection and escalation of statutory-clock mail. For the whole outage window that
function did not run. Any DSAR (Art. 12(3), one calendar month), service of process,
regulator correspondence, or inbound **processor breach notification** (Art. 33, 72 h
from awareness) that arrived in the window was never escalated — and a 72-hour clock may
already be consumed. Phase 2's durable claim prevents recurrence; it does **not**
discharge a clock already running, and AC14 does not cover mail dropped before the
durable claim existed.

- Review the Proton `ops@soleur.ai` keep-copy for every message received from
  **2026-07-30 16:14 UTC** (the evidentiary floor, not the vendor's alert time) through
  dispatch restoration, against the four rules in
  `apps/web-platform/lib/email-triage/statutory-rules.ts` (`breach-art33`,
  `service-of-process`, `dsar-art15`, `regulator-contact`).
- **Also confirm the keep-copy actually held**, reconciled against at least the 15 known
  svix ids (B3). ADR-055's Sieve rule is forward-**and-keep**, so the original mail
  should be intact — but the plan currently verifies *Resend's* 30-day vendor retention,
  which is a vendor copy, not our record. Until the keep-copy is confirmed, "no data was
  lost" is an inference, not a finding, and Art. 4(12) includes accidental **loss** —
  an availability-only breach can still be notifiable.
- Any missed statutory item is recorded against the DPIA residuals and the PA-27 Active
  Items row in `knowledge-base/legal/compliance-posture.md`.

Shape of the remediation itself is decided by Phase 0's verdict, so it is deliberately
not pre-written here.
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

**Why the single-table shape is load-bearing, not just tidier.** Two tables would mean
two unrelated PostgREST writes with no transaction, and this interleaving:

> claim succeeds → process dies before the outbox insert → svix retries →
> `claimDelivery` hits 23505 → route returns `200 {duplicate: true}` →
> **permanent silent loss of that email.**

That window exists today, but today it is bounded by one `releaseDelivery` and fails
loudly. Two tables would widen it and make the outcome silent. With one table the hazard
**disappears by construction**, and a 23505 on redelivery unambiguously means "already
buffered" — which is correct to answer 200 to.

2.1 **RED.** Add failing tests to `resend-inbound-route.test.ts`:
    - well-formed `email.received` → **200**, row persisted with `status='pending'` and
      the typed event fields, **no inline `inngest.send` call at all**;
    - the persist itself failing → **release + 500**, asserted as *both*. The release is
      not optional: without it the svix retry short-circuits as a duplicate and the
      fail-closed fallback silently becomes a data-loss path. This is the sole remaining
      500;
    - duplicate `svix_id` → 200, no second row, no re-dispatch;
    - malformed body → still 400, nothing claimed, nothing persisted;
    - reconciler dispatches a pending row exactly once, marks it `sent`, and is
      idempotent under re-run;
    - reconciler with Inngest unreachable leaves the row `pending` and increments
      `attempts` without dropping it.
    Confirm all fail before writing the implementation.
2.2 Migration: extend `processed_resend_events`. **Columns are TYPED, not an open
    `payload jsonb`** — `resend_email_id`, `message_id`, `sender`, `subject`,
    `attachment_filenames`, `received_at`, `received_at_source`, `status`, `attempts`,
    `last_error_code`. Rationale is load-bearing, not stylistic: ADR-055's
    parse-and-discard guarantee is enforced by the **schema** ("no body column exists"),
    so an untyped jsonb would be the first store on this path where the discard reverts
    to behavioural. Mirror migration 102's `email_triage_items` shape. If jsonb is kept
    for any reason, it needs a CHECK pinning the permitted top-level key set and
    rejecting `body`/`html`/`text`.
    **`last_error_code`, not `last_error`** — a raw `inngest.send` error string can echo
    the request body (sender, subject) into a Postgres column that the observability
    scrub does not reach. Apply the PA-28 precedent: store a bounded code, or
    scrub-and-truncate at the write boundary.
    RLS **enabled with zero policies** + table REVOKE from `anon`/`authenticated`
    (migration 102 §7 shape) — not a hand-rolled "service role" policy.
    **Retention: delete-on-drain is the primary control** — the row's purpose is
    discharged the instant dispatch succeeds, so it is deleted (or its identifying
    fields nulled) in the same transaction that confirms dispatch. The calendar sweep is
    only a backstop for the failure tail, at **≤30 days (7 preferred)**, anchored to the
    Resend 30-day source window and the 72-hour shortest statutory clock. **Do NOT copy
    the dedup table's 90 days**: that figure is a vendor-redelivery horizon for a table
    holding `(svix_id, received_at)` and no PII, and its justification does not transfer
    to a table holding sender + subject. 90-day parity would also let a synthetic probe
    row outlive its own 7-day triage row by 83 days inside one processing activity.
2.3 Route: signature-verify → insert-with-payload → 200. Remove the inline dispatch.
2.4a **Substrate circularity — the drain must not sit on the thing that breaks.** Every
    cron here is Inngest-fired (`server/inngest/cron-manifest.ts`), so an Inngest-fired
    drain **cannot run during the exact outage the durable claim exists to survive**.
    Tolerable for *draining* (it catches up on recovery); **fatal for alerting**. The
    drain-stall signal MUST live off that substrate — a GHA `schedule:` poller (the
    `scheduled-*.yml` + `betterstack-query.sh` pattern already used for the zot
    restart-loop alarm), or a Sentry cron monitor keyed on *missed* check-ins.

2.4b **Cadence / WAL.** Payload volume is negligible (~100 deliveries/day × ~2 KB), but
    cadence is not: a per-minute `pg_cron` drain adds ~1,440 `cron.job_run_details`
    rows/day and re-opens #5738 (that table reached ~4.7 % of prod WAL; see
    `115_prune_cron_job_run_details.sql` and `123_tame_autovacuum_on_tiny_hot_tables.sql`,
    which records the dedup fix cutting WAL from ~12 GB/day to ~17 MB/day). Follow the
    `dsar_export_jobs` precedent (`041_dsar_export_jobs.sql`): external poller for the
    drain; `pg_cron` for retention **only**, daily — as migration 094's header requires
    ("ONCE daily at 04:00 UTC… NOT per-minute"). Copy 102's
    `WHEN undefined_table THEN RAISE WARNING` handler so pg_cron-less local/CI DBs do not
    abort.

2.4 `outbox-drain.ts` reconciler, oldest-first, bounded attempt budget,
    dead-letter threshold that pages.
2.5 **Recover the already-exhausted deliveries.** 106 deliveries exhausted their retries
    and are NOT recovered by anything above; the plan would otherwise "not lose mail"
    only prospectively. After Phase 1 restores dispatch, re-drive those svix message ids
    via the Resend/svix redelivery API.

2.5b **Backfill the untriaged window — UNCONDITIONALLY, not "if any delivery is
    exhausted".** AC14 covers only the *buffered* backlog, which by construction starts
    at deploy; everything dropped before the durable claim existed is covered by nothing.
    Enumerate Resend `GET /emails` over `[onset|2026-07-30, deploy]`, diff against
    `email_triage_items` + `processed_resend_events`, and replay the difference. This is
    fully recoverable inside the vendor's 30-day window — the oldest affected message
    (2026-07-30) expires ~**2026-08-29**, so there is real but finite headroom.

    **Hard constraint on the fallback (ADR-055 violation risk).**
    `GET https://api.resend.com/emails` returns **body, html and attachments** — the
    exact object ADR-055 confines to a single fused Inngest step that is never
    checkpointed. A backfill that writes that response into the durable claim, or
    checkpoints it as a step return, violates parse-and-discard outright, defeats
    migration 102's no-body-column guarantee, and re-opens the DPIA residual for Art. 9
    content in persisted data. **Any backfill MUST enter the pipeline at the same
    fused-step boundary as a live delivery, never through the durable claim.** This is
    an acceptance criterion, not a note.
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
3.3 Alert on drain stall. **"Depth > N" is not implementable as written** —
    `apps/web-platform/infra/sentry/` carries only `sentry_cron_monitor`,
    `sentry_issue_alert` and `sentry_uptime_monitor`; there is **no `sentry_metric_alert`**
    (its migration is explicitly deferred, `versions.tf` / ADR-031 amendment
    2026-07-17), and depth is a gauge. Pick a realizable shape: the drain emits a Sentry
    **event** on stall (→ `sentry_issue_alert`), or the drain check-ins as a cron (→
    `sentry_cron_monitor` firing on a **miss**). In-repo precedent for a DB-derived
    metric: `server/inngest/functions/cron-supabase-disk-io.ts` + migration
    `095_disk_io_pressure_signal.sql`. Per 2.4a the alarm must not ride the Inngest
    substrate.
3.4 Comment the B4 retention measurement onto #5697.
3.5 **Reach the operator, not just the engineer.** Gated on Phase 0.4: if the ingress
    probe's monitor was already RED and nobody acted, more Sentry signal fixes nothing.
    Make `cron-email-ingress-probe` an **`action-required` issue emitter** — the
    precedented path used by five sibling crons (`cron-supabase-disk-io`,
    `event-cf-token-expiry-check`, `cron-gh-pages-cert-state`,
    `cron-linkedin-token-check`, `cron-content-publisher`) — so `operator-digest` surfaces
    it in plain language. Plus a one-time issue for this incident's window.

    **Wording constraint (load-bearing).** The notice must say: *"Agent triage of
    ops@soleur.ai was down from `<onset|≥2026-07-30>` to `<fix>`. Your Proton mailbox has
    every original. N messages were re-triaged; M could not be."* It must **NOT** say
    "you may be missing mail" — that is false (forward-and-keep) and alarming.

    Deliberately **not** an in-app "ingest degraded" banner: routing through the
    issue/digest path keeps the Product/UX gate at Tier NONE, so no wireframe is required
    mid-incident. File the durable in-app ingest-health surface as a follow-up issue.

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
15. **Phase 1.0 statutory reconciliation is complete and recorded** — the Proton
    keep-copy reviewed for the window `2026-07-30 16:14 UTC → dispatch restoration`
    against the four rules in `lib/email-triage/statutory-rules.ts`, with the keep-copy's
    integrity reconciled against at least the 15 known svix ids. Any missed statutory
    item is recorded against the DPIA residuals and the PA-27 Active Items row.
16. **The untriaged window is fully accounted for** (Phase 2.5b): every inbound message
    in `[onset|2026-07-30, deploy]` is either re-triaged or explicitly unrecoverable.
17. **No backfill path writes a Resend `/emails` response into the durable claim or
    checkpoints it as a step return** — asserted by test. `GET /emails` returns body and
    attachments; routing it through the claim would violate ADR-055's parse-and-discard.
18. `DSAR_TABLE_EXCLUSIONS` entry present with a written reason. Note
    `test/dsar-allowlist-completeness.test.ts` cannot catch its absence here (no FK to
    users) — so this AC is the only gate.
19. Operator notification (3.5) exists and uses the mandated wording; it does **not**
    contain the string "missing mail".
20. **Recovery of the 106 exhausted deliveries is accounted for, per message id**, with
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

**Were inbound events lost?** **The triage delegation was lost; the correspondence
almost certainly was not — and nothing is yet permanently lost.** Precisely:

- **Lost:** triage. 106 deliveries exhausted `sendInngestWithRetry` (B1), each returning
  500 to Resend; ≥15 distinct emails (B3) produced no `email_triage_items` row, no
  statutory clock, no badge, no push. For a product whose value *is* the delegation,
  that is the real loss.
- **Not lost (pending verification):** the mail itself. ADR-055's Sieve rule is
  **forward-and-keep**, so the Proton `ops@soleur.ai` mailbox is the durable original
  throughout. Phase 1.0 verifies this actually held against the 15 known svix ids —
  until then it is a well-founded inference, not a finding, and the plan holds its legal
  conclusions to the same evidentiary bar as its technical ones.
- **Recoverable:** Resend retains content 30 days and `GET /emails` responds 200 with
  `RESEND_RECEIVING_API_KEY`. The oldest affected message (2026-07-30) expires
  **~2026-08-29** — real but finite headroom. Phase 2.5b backfills the window
  unconditionally.
- **Unknown:** the true count. 15 is a floor, not a measurement — retention (B4) starts
  after the failures began. Every statement of "~2 days" or "15 emails" is a lower bound.
- **The live legal exposure is a clock, not a byte.** A statutory item that arrived in
  the window sat unescalated: Art. 12(3) DSAR (one month), service of process, or an
  inbound processor breach notice whose Art. 33 72-hour clock may already be consumed.
  Phase 1.0 discharges this and it may not wait for Phase 2.

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

H2 has no branch (refuted). H1's branch is **not** a Hetzner firewall change:
`hcloud_firewall.inngest` has zero rules and a scoping rule is a documented no-op
(SEC-H1); port scoping is host-local nftables rendered into `cloud-init-inngest.yml`.
So the live branches are:

- **H3 (host dark)** → `apps/web-platform/infra/inngest-host.tf`; re-provision through
  `terraform apply` per `hr-fresh-host-provisioning-reachable-from-terraform-apply`.
- **H4 (unit not bound)** → the unit definition + bootstrap. **Name which of the two
  paths is used — they have very different blast radii:**
  1. **cloud-init edit = host REPLACE.** `hcloud_server.inngest` carries
     `lifecycle { ignore_changes = [ssh_keys] }` and, per its own comment, *deliberately
     NO* `ignore_changes = [user_data]`, "that force-replace is the intended
     replace-to-reprovision path". And `hcloud_firewall_attachment.inngest` warns the
     replacement **boots with no hcloud firewall until the next full/drift apply**.
  2. **Signed config-refresh bundle** (`infra-config-install.sh` / `INNGEST_CONFIG_DIGEST`,
     ADR-136/ADR-128) — the in-place path that avoids the replace.
  Prefer (2) unless Phase 0 shows the host cannot be repaired in place. The plan's
  earlier "existing bootstrap path" was ambiguous between these; that ambiguity is the
  defect.

### Apply path

**Blast-radius, correctly aimed.** The inngest host resources appear only in the
`inngest_host` dispatch job's target list in `.github/workflows/apply-web-platform-infra.yml`,
and `stripDispatchJobs()` in `plugins/soleur/test/terraform-target-parity.test.ts` strips
that job from the per-merge coverage anchor. `-target` **is** transitive, so the
mechanism is real — but the destructive outcomes are **already tripwired**: `host_creates
> 0` HALTs, explicitly naming `hcloud_server.inngest`, and is **not** bypassable by
`[ack-destroy]`; `reboot_updates` / `resource_deletes` / `nested_deletes` cover the rest
(`tests/scripts/lib/destroy-guard-filter-web-platform.jq`).

So an AC asserting "no create of the excluded resource" merely **restates a guard that
already exists**. The residual gap it should assert instead: a **pure in-place update**
to `hcloud_firewall.inngest` (adding a rule) is invisible to all four counters — not a
create, not a delete, not a nested removal, not a reboot-forcing update. That is exactly
H1's remediation shape, and the one thing that could silently ride a routine merge-apply.
**Restated AC:** any new `.tf` resource is either added to the exclusion set in
`terraform-target-parity.test.ts` or added to the per-merge `-target` list with an
explicit statement that it has no dependency edge to any `hcloud_*.inngest` resource.
That test already fails the build for a resource with neither — it is the real gate, and
it is stronger than the AC originally written here.

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

### A second decision the plan must not swallow

If Phase 0 confirms H4 **and** a live co-located inngest still running on web-1 (#6617's
double-scheduler, consistent with B7's shared machine id), then the choice between
*repair the dedicated host* and *roll `INNGEST_BASE_URL` back to the co-located server*
is a real architectural fork — with **ADR-100's cutover half-executed**. That is its own
record: `/soleur:architecture create 'Complete or roll back the ADR-100 dedicated-Inngest
cutover'`. Do not let a one-line remediation silently pick a side of it.

### Sequencing

The ADR is authored in the Phase-2 PR describing the target state. It is not deferred.

### Explicitly scoped out

Phase 2 covers the **webhook → Inngest dispatch** hop only. A run that dies after
`claim-insert` but before finalize still leaves an unfinalized stub, and both queries in
`apps/web-platform/server/inbox-sources.ts` filter those out
(`mail_class IS NULL AND statutory_class IS NULL`) — so that message stays invisible to
the operator. **This plan does not fix that class.** Naming it, rather than implying
"mail always appears" has been achieved.

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
    disclosed_as: pre-existing posture of `api -> inngest` (ADR-030/ADR-100). This plan
                  does NOT change it and does NOT increase what transits it — the drain
                  replays exactly the payload the original send would have carried.
                  (Corrects an earlier overstatement in this section.)
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

**Status:** reviewed. **Verdict: diagnosis sound, Phase 0 over-scoped, Phase 2 right
direction / wrong shape** — all applied above.
Findings folded in: H2 refuted from `ci-deploy.sh` (A1); H1 near-refuted and H4
near-confirmed from the errno (A2); B9 mechanism is grouping, derivable without a Sentry
token (A3); Phase 3.1's file was wrong and its blast radius large (A4); migration
citations + mandatory `.down.sql` + 102's `undefined_table` handler (A5); Phase 3.3 not
implementable — no `sentry_metric_alert` in the provider (A6); the stale
`inbound-email-ingress-dead.md` runbook and `send-with-retry.ts` comment (A7); the
claim-then-crash silent-loss window and the missing **release**+500 (C); drain substrate
circularity and the #5738 WAL cadence precedent (C); the `-target` AC restating an
existing guard, with the real residual being an in-place `hcloud_firewall.inngest` update
(E); H4's cloud-init path being a host **replace** (E); and the second ADR fork on
ADR-100 (F).
**Note:** the outbox is **hardening**, not the incident fix — if H4 confirms, this
incident is one host's boot bug. Label it that way. **#6185 (Inngest HA) remains the more
load-bearing fix** and the durable claim does not substitute for it.
**Review-time agents named:** `observability-coverage-reviewer` and
`data-integrity-guardian` (the latter specifically on the migration and the claim/release
interleaving).

### Legal (CLO / GDPR gate)

**Status:** reviewed. **Verdict: BLOCKED for Phase 2 merge** on seven items, all folded
in above. Summary: extend PA-27 (do not mint PA-34); **90-day parity is the wrong
retention anchor** — delete-on-drain primary, ≤30-day (7 preferred) backstop; typed
columns, not open `payload jsonb`, because ADR-055's discard guarantee is
**schema**-enforced; the Resend `/emails` backfill must never enter via the claim;
`last_error` is an unscrubbed PII sink (apply the PA-28 synthetic-error precedent); DSAR
exclusion entry with the completeness lint blind here; and PA-27 TOM (11)'s "~25.5h"
liveness claim is falsified by this incident and must be restated.
**Art. 33:** probably not notifiable — Art. 4(12) covers accidental *loss*, but
forward-and-keep means the originals are intact — **conditional on Phase 1.0 verifying
the keep-copy actually held.** ADR-055's parse-and-discard is **not** violated by the
durable claim as scoped (it sits upstream of the body fetch), but that is a *different
clause* from the release+500 one being amended; state both in the ADR edit.
**No LIA re-run, no DPIA re-screening triggered**; a necessity-limb addendum is required.

### Product (CPO)

**Tier:** NONE for the UX gate — no file in §Files to Edit or §Files to Create matches a
UI-surface path (no `components/**/*.tsx`, no `app/**/page.tsx`, no `app/**/layout.tsx`),
and 3.5 deliberately routes operator notice through the issue/digest path rather than a
new banner, keeping it NONE. No wireframe required.
**CPO sign-off: APPROVE-WITH-CHANGES** — all five blocking changes applied (C1 impact
framing incl. the Proton mitigant, the badge-absence vector, and the 2xx-acked-then-
stranded artifact; C2 Phase 0 produces no merge; C3 the probe-monitor question; C4 the
unconditional backfill; C5 the operator notification with its wording constraint).
Threshold `single-user incident` stands; `user-impact-reviewer` re-checks at review.
**Non-blocking follow-ups:** add a roadmap row for #5103 (the capability has none);
refresh `roadmap.md` `Current State` (stale — says 56/179, milestone API says 74/192);
file the in-app ingest-health surface as its own issue.

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
