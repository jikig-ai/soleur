# Phase 0 findings — Resend inbound webhook 500s

All figures self-pulled 2026-08-02. No SSH; every probe is an API/CLI call.
Supersedes the plan's §Hypotheses where they conflict — the root cause below was
**observed on the host's own channel**, not inferred by elimination.

## Root cause (0.2) — OBSERVED, not inferred

`SOLEUR_INNGEST_BOOT_STAGE` phone-home markers from `soleur-inngest`, Better Stack:

| dt (UTC) | stage | detail |
| --- | --- | --- |
| 2026-07-30 15:13:56 | `runcmd-entered` / `sshd-restarted` | host booted |
| 2026-07-30 15:13:57 | `doppler-cli-installed` | OK |
| 2026-07-30 15:13:58 | `doppler-token-fetched` | OK |
| 2026-07-30 15:13:59 | **`ghcr-login-FAILED`** | — |
| 2026-07-30 15:14:00 | `pre-oci-pull` | `ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.24@sha256:REDACTED` |
| 2026-07-30 15:14:01 | **`oci-pull-rc-1`** | `Error response from daemon: error from registry: unauthorized` |

The boot sequence **stops there**. `inngest-bootstrap.sh` never ran, `inngest-server`
was never installed, nothing ever bound `:8288`.

**This is NOT the documented `cloud-init-inngest.yml:199` `status=203/EXEC` doppler-path
bug.** That fix (`ln -sf /usr/local/bin/doppler /usr/bin/doppler`, #6310) is present and
this host booted with it. The plan's H4 line item recorded the 203/EXEC match as the
likely mechanism and flagged the unit state as *inferred*; Phase 0.2 replaced the
inference with an observation and the mechanism is different.

### Why the credential was dead

- `GHCR_READ_TOKEN` (Doppler `soleur/prd_terraform`) is a classic `ghp_` PAT, user
  `deruelle`. It returns **HTTP 401 from `api.github.com/user`** — the token is fully
  dead (revoked or expired), not merely denied on one package.
- `GHCR_MINTER_DISABLED=true` in the same config, so nothing rotated it.
- ADR-088's replacement minter issues 1h `packages:read` App-installation tokens **on the
  Inngest substrate** → **bootstrap deadlock**: the minter that would repair the
  credential needed to boot Inngest runs on Inngest.
- The GitHub App (`jikig-ai`, installation `122213433`) *does* hold `packages: read`, and
  an installation token mints + exchanges against GHCR (HTTP 200) — but the manifest pull
  for `soleur-inngest-bootstrap:v1.1.24` is **HTTP 403**: the App installation is not on
  that private package's access list, and no REST endpoint was found to add it
  (UI-managed).

## Onset (0.5) — RECOVERED

**2026-07-30T15:14:01Z** (the failed pull), ~27 h before the 2026-07-31 18:23 UTC time
Resend reported. The Hetzner API shows `soleur-inngest` (10.0.1.40) `status=running`,
`created=2026-07-30T15:13:06Z` — i.e. the host was **replaced**, and the replacement never
booted Inngest. The plan had recorded `onset: UNKNOWN`.

## Split-brain (new finding, not in the plan)

`inngest-server.service` is **alive right now** — 1902 rows, last seen
2026-08-02 11:20:02Z — on the **old co-located** host. Meanwhile
`apps/web-platform/infra/ci-deploy.sh` hardcodes
`-e INNGEST_BASE_URL=http://10.0.1.40:8288` after `--env-file` (ADR-100 cutover step 2.4,
`b02870e1d` / #6348, 2026-07-24), overriding the Doppler value that still reads
`host.docker.internal:8288`.

So the system is **asymmetrically split**: the surviving co-located Inngest still drives
cron execution *into* the app, while every outbound `inngest.send()` is aimed at the dead
dedicated host. That is why the daily `SOLEUR-PROBE` emails were still being sent
throughout the outage while the webhook returned 500 — and it is the condition the plan's
task 4.6 anticipated ("H4 confirmed + a live co-located inngest").

## Why nobody was paged (0.0 / 0.4)

**0.0 — the watchdog is blind by construction.**
`.github/workflows/scheduled-inngest-health.yml` reported `success` every ~1–2 h straight
through the outage, and `restart-inngest-server.yml` has not been dispatched since
2026-07-23. Cause: `apps/web-platform/infra/inngest-inventory.sh:123` probes
`http://127.0.0.1:8288/v0/gql` — **loopback on the deploy/web host**. The ADR-100 cutover
moved the app's dependency to 10.0.1.40 but never re-pointed the watchdog, so it has been
certifying the *surviving co-located* Inngest. It cannot observe the failure it exists to
catch. This is the plan's "larger finding than anything else in this plan" branch.

**0.4 — detection DID fire; the response failed.** Sentry (org `jikigai-eu`):

| issue | count | first | last | status |
| --- | --- | --- | --- | --- |
| `Cron failure: cron-email-ingress-probe` (127593398) | **3** | 2026-07-31T06:15:24Z | 2026-08-02T06:20:17Z | unresolved |
| `Cron failure: scheduled-inngest-health` (134017444) | **1133** | 2026-07-19T12:00:00Z | 2026-08-02T11:30:00Z | unresolved |

The ingress probe caught it on the **first** run after onset and has failed once per day
since, still unresolved after 3 days. So this is a **response** failure, not a detection
gap — which per the plan's 0.4 branch means Phase 3's value is task **3.5** (an
operator-reaching channel), NOT 3.1/3.3 (more Sentry signal into a channel that already
produced no response).

The probable reason the signal was missed is alert fatigue: a **sibling monitor on the
same substrate has fired 1133 times since 2026-07-19** and sits unresolved, so a 3-event
issue is indistinguishable from background.

## Sentry blind spot (B9) — CONFIRMED, with a caveat that nearly inverted it

`op:inngest-send` returns **0 issues over 90 d** while Better Stack carries 106 dispatch
failures. The blind spot is real.

**Method note (`hr-no-dashboard-eyeball-pull-data-yourself` + "empty is not absence"):**
`SENTRY_API_TOKEN` returns `[]` for *every* endpoint including `/organizations/` — a
scope-less token whose empty results are indistinguishable from genuine absence. The
working credential is **`SENTRY_AUTH_TOKEN`**. Every figure above was re-derived with it,
and it demonstrably returns 40+ other issues over the same window, so the `op:inngest-send`
zero is a measured absence rather than an authentication artifact. Any future Sentry
assertion in this repo must use `SENTRY_AUTH_TOKEN`.

## Statutory reconciliation (1.0) — NO exposure

Enumerated **all 193** inbound emails Resend retains (`GET /emails/inbound`, 30-day
window, 2026-06-12 → 2026-08-02), filtered to the outage window
(≥ 2026-07-30T15:14:01Z) = **14 messages**, fetched each full body, and ran the
**production matcher** (`matchStatutoryMetadata` + `matchStatutoryBody` from
`apps/web-platform/lib/email-triage/statutory-rules.ts`) over subject + sender + body.

**Result: 0 statutory hits across all 14.** Composition: 10 Sentry alert mails
(`noreply@md.getsentry.com`), 3 `SOLEUR-PROBE` self-probes, 1 Sentry weekly report.

No DSAR (Art. 12(3)), no service of process, no regulator correspondence, and no inbound
processor breach notification (Art. 33) arrived during the window. **No statutory clock
was started and none was consumed.** The CLO's flagged exposure is real in principle but
**not realized** on this window's traffic.

## Answers to the brief's two explicit questions

- **Does the webhook need re-enabling?** **No.** Re-verified 2026-08-02 against the Resend
  API: webhook `e0b3ba09-7a13-4f59-ba95-1ef1222bbdf8` is `status: enabled`, endpoint
  `https://app.soleur.ai/api/webhooks/resend-inbound`, events `["email.received"]`. The
  auto-disable threat has not fired. Automation should still assert this post-fix rather
  than assume it.
- **Were inbound events lost?** **No mail was lost; triage delegation was.** The 14
  window messages are all present in Resend's retained record, and all 14 are
  machine-generated. What did not happen is the agent triage of them. Resend's 30-day
  window closes ~2026-08-29.

## Phase 0 exit gate (0.7)

**Satisfied.** First failing hop identified with an artifact: `ghcr-login-FAILED` →
`oci-pull-rc-1 unauthorized` at 2026-07-30T15:14:01Z, caused by a dead `ghp_` PAT with its
automated rotator disabled and its ADR-088 successor deadlocked behind the very service it
would restore. Remediation shape routed to the CTO agent as a binding architecture
decision (complete the ADR-100 cutover vs roll it back vs mirror the image internally),
per the `/work` architectural-fork hard gate.
