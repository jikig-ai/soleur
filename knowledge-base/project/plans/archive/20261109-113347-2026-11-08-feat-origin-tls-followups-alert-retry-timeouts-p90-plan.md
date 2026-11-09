---
title: "Origin TLS follow-ups: Sentry alert for feature:origin_tls, CI download retries, :80 slow-header ruling, /health p90 write-up"
date: 2026-11-08
slug: origin-tls-followups-alert-retry-timeouts-p90
branch: feat-one-shot-origin-tls-followups
issue: 10479
epic: 10205
type: feat
lane: cross-domain
closes: none
references: [10479, 10205]
pr: 12434
brand_survival_threshold: aggregate pattern
---

## Enhancement Summary

**Deepened on:** 2026-11-08
**Sections enhanced:** 7 (Research Reconciliation, Observability, Phase 1/2/3 test specs, Guard Contracts, Network-Outage Deep-Dive, Sharp Edges, ADR list)
**Agents used:** repo-research-analyst, learnings-researcher, functional-discovery, CTO (x2), code-simplicity-reviewer, architecture-strategist (plan review); observability-coverage-reviewer, test-design-reviewer, security-sentinel (deepen). Halts 4.6, 4.7, 4.8, 4.10, 4.11, 4.12 evaluated mechanically (all pass; 4.9 UI and 4.13 task-design not triggered; 4.55 downtime not triggered). The "run ALL agents" fan-out was scoped to the three reviewers whose lenses touch this change (observability, test design, security); the remaining review agents have no surface here (no UI, data model, migrations, performance path).

### Key Improvements
1. Plan review found that the alert would miss the events it exists for (`exit(1)` without a Sentry flush); CTO ruled a bounded `exitAfterFlush` in, with six test cases.
2. Seven gitleaks copies (not four) plus actionlint; behaviour arm and raw-count over-engineering cut; scanner hygiene rules added (exact-token match, comment stripping, `set -e` capture, POSIX awk).
3. Failure modes now cite observability layers (pino/vector/release); the Vector error-level forwarding caveat is closed against `vector.toml`.
4. Runbook spec: `/health` includes a Supabase round trip; candidate 4 and a Supabase-free control added; commands must reuse the stdin-config bearer pattern.

### New Considerations Discovered
- `--retry-all-errors` also retries a 404 (a removed release takes about 31 s to fail instead of failing at once): still loud.
- If the 2.25 s hard timer fires before the Sentry flush completes, only the Better Stack pino line survives: accepted residual, no alert covers it.
- Three more ADR-321 sentences go stale (container-start signals, decision 7 "alert is still deferred", R-A "unchanged in effect").

## Overview

Four follow-ups owed to the Cloudflare-to-origin TLS work (ADR-321, epic #10205, issue #10479), shipped as ONE PR that
references both issues (`Ref #10479`, `Ref #10205`) and closes neither (`closingIssuesReferences` must be `[]` before the PR
body is saved). The PR applies, dispatches and arms nothing.

1. **Sentry alert** for events tagged `feature:origin_tls`, as committed infra in the repo's existing Sentry-as-code root, plus a bounded Sentry flush before the REQUIRED-mode `exit(1)` paths so the events the rule exists for are actually sent (found in plan review; CTO ruled it in).
2. **CI download hardening**: `--fail --retry 5 --retry-all-errors` on the pinned gitleaks installs (seven copies, not four)
   and the actionlint install, with a scanning test.
3. **:80 slow-header cutoff**: set it explicitly (60 s header phase, 300 s whole request) on the plain server only, with tests.
4. **/health p90**: write the evidence and the exact isolation procedure into the strict-flip runbook; no server code.

All forks were ruled by the CTO agent on 2026-11-08; the rulings are rows in
`knowledge-base/project/specs/feat-one-shot-origin-tls-followups/decision-challenges.md` and are restated where they bind.

## Research Reconciliation - Spec vs. Codebase

| Brief claim | Reality (verified in the worktree at HEAD `3e3e721944`; `origin/main` = `4fba0d512e`) | Plan response |
|---|---|---|
| gitleaks bare `curl -sSLo` at ci.yml ~1915/~2045 and main-health-monitor.yml ~367/~461; "grep for any other copy" | Line drift only (ci.yml 1926/2056). **Three more copies**: `secret-scan.yml` twice (the folded `scan-install` member step and the step near line 533) and `.github/actions/bot-pr-with-synthetic-checks/action.yml` (different shape: `"${GITLEAKS_DIR}/gitleaks.tgz"`; its run body sets `set -eo pipefail`, verified in the deepen pass; the other six copies set `set -euo pipefail`). Total **7 gitleaks copies**. Same-class sibling: `ci.yml` actionlint install (~833). Out: `apply-web-platform-infra.yml` crane (2 sites) | Harden 7 + actionlint (CTO ruling); crane and the wider release-download class go to one tracking issue |
| "Follow the repo's existing Sentry-alert-as-code pattern if one exists" | It exists and is heavy: `apps/web-platform/infra/sentry/issue-alerts.tf` (55 `sentry_alert` blocks, plus `cron-monitor-failure` in `cron-monitor-alerts.tf` = 56 rules), `alert-reference.json` (gated by `scripts/sentry-alert-reference-gate.sh` in `plan_pr`), one `sentry-*-alert-op-contract.test.ts` per rule family, a README rule count tied to the `.tf` by two tests, unique `frequency_minutes` (Sentry POST-time dedup) | No mechanism fork; CTO ruled only the shape |
| ADR-321 item 11: "There is no committed Sentry alert rule ... belongs in a separate infra change" | True at HEAD; this PR is that change | Update the ADR sentence in the same PR |
| Test "that pins the flags in every copy" | `required-checks-canonical-parity.test.sh` Test 5 pins only the version/SHA declarations ("all 4 sites" in its title, "three install sites" in its header) and never reads the `curl` lines | Add a scanning arm; fix the stale site counts in the header |
| Token `CF_API_TOKEN_ANALYTICS_READ` "wrapper-bound" | `plugins/soleur/scripts/cloudflare-readonly.sh` is a closed, GET-only subcommand wrapper; Cloudflare GraphQL analytics is a POST endpoint | Runbook states the POST exception as a prerequisite of the wrapper change (separate tracking issue); not built here |
| (Plan review finding) the alert will page on the REQUIRED fatal events | `origin-tls.ts` calls `reportSilentFallback(null, ...)` then `exit(1)` (default `process.exit`) with no `Sentry.flush`; the SDK sends asynchronously and the pino error mirror is itself mirrored to Sentry, so the unexpected-close and startup-fatal events can be dropped before the page is sent | Fold a bounded `exitAfterFlush` into the default `exit` (CTO ruling, third row of `decision-challenges.md`); tests inject `exit`, so existing tests are unaffected |
| p90 candidates: redeploys, TLS CPU, new-connection handshakes | **A fourth candidate the brief omits**: `/health` awaits `checkSupabase()` (a PostgREST `users?select=id&limit=1` GET, 2 s abort) on EVERY request, so `/health` server-wait contains a database round trip whose variance is independent of TLS; and the apex "control" (`soleur.ai/`, a different origin) controls client network only | Runbook lists it as candidate 4 and designs the isolation around it |
| "Origin-tls listening restart pairs ... = 11" | The runbook table lists only the pairs through 00:15Z; the 11 are 01:05Z..16:17Z | Record the count and range; do not invent per-pair timestamps |

**Premise validation (Phase 0.6).** #10479 and #10205 are OPEN; PR #12410 is open and touches `ci.yml` (and not the gitleaks
steps); draft PR #12434 has `closingIssuesReferences: []`; the collision pre-check for #10479 and #10205 reports no open change
and no foreign gate process. ADR-321 item 11 R-A/R-B read in full; no ADR rejects any mechanism proposed here.

## Research Insights

**Property List (Phase 0.6b).**

- P1: a `feature:origin_tls` Sentry event reaches a human without anyone pulling it.
- P2: a transient GitHub release-CDN 5xx does not fail the gitleaks (or actionlint) install on the first attempt, and a
  persistent one fails at the download step rather than at the checksum step.
- P3: the :80 slow-header cutoff is a stated, tested number, not an inherited default behind a dead assignment.
- P4: the next person investigating the /health p90 starts from the evidence and an executable isolation procedure.
- P5: nothing in this PR changes production behaviour except through the merge-triggered paths named below.

**Cut List.** Second broad/narrow Sentry rule (P1 already met by one any-event rule); shared composite action for the seven
curl copies (P2 met by one-line flag additions); in-app `SOLEUR_HEALTH_TIMING` marker (P4 met by the runbook procedure; CTO
deferred, triggers recorded); lowering `requestTimeout` (P3 needs only the header phase); changing the :443 server (R-A pins it);
any `--retry-delay`/`--max-time` (owner named three flags).

**Value measurement (Phase 0.6c).** The retry saving is bounded, not asserted: curl's default backoff for `--retry 5` is
1+2+4+8+16 = 31 s, which rides out blips and NOT the 09:34Z-10:55Z (about 80 minute) outage. The PR text must not claim the
change would have prevented that outage; it removes first-attempt flakiness and turns a silent-bad-body into a loud download
failure. (Measured nowhere; stated from curl's documented schedule.)

**Local measurements taken while planning (Node 26.13.0; ADR-321 R-A measured 22.23.4 and 26.13.0).** With
`connectionsCheckingInterval: 100`: header-phase cutoff = min(`headersTimeout`, `requestTimeout`) (910 s + 2 s -> 408 at 2 s;
1 s + default 300 s -> 408 at 1 s); both properties are read live after construction; an idle keep-alive socket is NOT closed by
a small `headersTimeout` (1 s `headersTimeout`, 20 s `keepAliveTimeout`: second request after 3 s idle answered). Node defaults
60 s / 300 s / 30 s check interval, so a real cutoff is the timeout plus up to 30 s.

**CLI verification (CLI-verification gate).** `curl 8.23.0 --help all` lists `--fail`, `--retry`, `--retry-all-errors`,
`--retry-delay`, `--retry-max-time`. `ubuntu-24.04` ships curl 8.5.0 (`--retry-all-errors` since 7.71); the secret-scan jobs
run on `ubuntu-24.04`. Cloudflare GraphQL fields verified against the Cloudflare docs corpus: dataset
`httpRequestsAdaptiveGroups`, filter keys `datetime_geq`/`datetime_lt`/`clientRequestHTTPHost`/`requestSource`/
`edgeResponseStatus_geq`, dimensions `datetimeHour`/`clientRequestPath`/`clientRequestHTTPHost`, endpoint
`https://api.cloudflare.com/client/v4/graphql` with `Authorization: Bearer`. NOT verified (the runbook marks them UNVERIFIED):
the origin-duration quantile field names, the per-plan time-range cap.

**Institutional learnings applied.**
`2026-05-17-sentry-issue-alert-create-dedup-on-action-match-not-conditions.md` (distinct `frequency_minutes`);
`2026-11-07-a-routing-change-is-declared-until-the-apply-and-the-prose-must-say-so.md` (say "declared" until the apply ran);
`2026-07-15-sentry-event-frequency-threshold-unreachable-and-data-source-scope-403.md` (counts are per issue group, hence the
`event_frequency_count {1h, 0}` re-page shape); `2026-09-21-curl-retry-flags-turn-a-throttled-emit-into-success-and-my-stubs-were-looser-than-the-code.md`
(test real curl exit codes); `2026-11-07-a-pin-whose-harness-runs-only-arg-two-passes-vacuously.md` and
`2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md` (mutate-probe every new pin; floor on the
scan); `2026-07-28-a-ten-run-sample-said-unreachable-and-the-defect-was-live-at-two-percent.md` (n=30 is thin);
`2026-10-30-the-plan-said-the-audit-line-reaches-better-stack-and-the-shipper-drops-info.md` (Vector drops INFO: any stdout marker
must be `warn`); `cf-lb-a-record-gaplessness-verify.md` (runbook convention: UNVERIFIED lists); `decision-challenges.md` is
append-only (supersede with a new row).

**Open Code-Review Overlap.** One hit: #3593 "extract post-synthetic-checks child composite (deferred per ADR-027)" names
`.github/actions/bot-pr-with-synthetic-checks/action.yml`. **Acknowledge**: this PR adds three flags to one `curl` line in that
file and does not restructure it; the extraction is its own cycle.

**Functional overlap.** No community skill or agent covers any of the four items (functional-discovery run, 2026-11-08).

## Network-Outage Deep-Dive (deepen-plan Phase 4.5)

The trigger words (`timeout`, `502`/`503`/`504`, `handshake`) appear because the plan concerns CDN 5xx on CI downloads, Node
timeouts and TLS handshakes; it diagnoses no SSH or connectivity fault and proposes no sshd/fail2ban fix. The four layers anyway,
each with its artifact or an explicit "not verified":

| Layer | Status | Artifact |
|---|---|---|
| L3 firewall allow-list | verified from code, not from the live vendor API | `apps/web-platform/infra/firewall.tf`: ports 80 and 443 accept only the Cloudflare edge IPv4/IPv6 ranges. `hcloud firewall describe` was not run (no token in this session; read-only vendor read is the work-phase option if the claim is ever load-bearing, which it is not here: the :80 tightening changes no reachability) |
| L3 DNS / routing | not verified (not load-bearing) | `dig` is absent in this environment; resolution is implied by the L7 row below, which reached Cloudflare |
| L7 TLS / proxy | verified read-only, 2026-11-08 deepen pass | `curl -sI https://app.soleur.ai/health?l=<rand>` -> `HTTP/2 200`, `server: cloudflare`, `cf-ray: ...-CDG`, `x-origin-transport: TLSv1.3` (the app's own header naming the Cloudflare-to-origin protocol), `cache-control: no-store`; one-request timing `time_connect` 0.014 s, `time_appconnect` 0.041 s, `time_starttransfer` 0.203 s (a single sample, not evidence for the p90 question) |
| L7 application | measured locally | Node header-phase semantics and idle keep-alive behaviour measured in the planning pass (see "Local measurements"); the CDN-5xx behaviour of `curl --retry-all-errors` is documented curl behaviour, not re-measured here |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Sentry alert rule for `feature:origin_tls` (any event; `tags.phase:runtime` and `tags.reason:unexpected-close` are the interesting ones), as committed infra" | Phase 3, FR1 | mapped |
| 2 | "Add `--fail --retry 5 --retry-all-errors`; keep the sha256 check; add or extend a test that pins the flags in every copy" | Phase 1, FR2 | mapped |
| 3 | "Decide explicitly (CTO ruling ...) whether to set `requestTimeout`/`headersTimeout` on the :80 server ... and implement the ruling with a test; do not touch the :443 server's timeouts" | Phase 2, FR3 | mapped |
| 4 | "write up the evidence collected so far and the exact isolation procedure ... in knowledge-base/engineering/operations/runbooks/origin-tls-strict-flip.md, and let the CTO rule whether a cheap in-app timing marker ... is worth adding in this PR" | Phase 4, FR4 (marker ruled: no) | mapped |
| 5 | "the PR must not apply anything: no `terraform apply`, no dispatch" | AC-NOAPPLY, PR body | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Eight curl edits (7 gitleaks + actionlint) | "grep for any other copy" | asked (gitleaks copies); actionlint: inferred - justification: same CDN, same file, same outage, a one-line hunk, CTO ruled it in |
| New module `server/http-timeouts.ts` | "implement the ruling with a test" | asked; the module is the CTO's mechanism so the behaviour is testable without booting `index.ts` |
| ADR-321 amendment (item 12 + two sentence edits) | "(ADR-321 item 11, section \"What detects and what recovers a dead :443\"; today nothing pages on it)" | asked (the section is named); item 12 for the :80 and marker rulings: inferred - justification: the `wg-architecture-decision-is-a-plan-deliverable` rule makes the ADR write part of the change |
| `sentry-origin-tls-alert-op-contract.test.ts` | "Follow the repo's existing Sentry-alert-as-code pattern" | asked (every rule family has one) |
| `exitAfterFlush` in `origin-tls.ts` (about 12 lines + tests) | "as committed infra ... today nothing pages on it" | inferred - justification: without the flush the rule can miss the very events it targets; CTO ruled it in (`decision-challenges.md`) |
| Tracking issues for crane/release-download class and for the analytics token + wrapper subcommand | "No Cloudflare analytics token exists" | inferred - justification: deferral rule (a deferral without an issue is invisible) |

### Split Assessment

- Subsystems touched: 5 (`apps/web-platform/infra/sentry`, `apps/web-platform/server` + `test`, `.github`, `plugins/soleur/test`, `knowledge-base`)
- Planned files: 22 | Estimated changed lines: about 750 (the runbook section and the two test files dominate)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines -> the root count trips.
- Recommendation: **single PR** - the owner's brief fixes it ("ONE PR"); the items are independent, each hunk is small, and no item blocks another. Split boundary if review demands one: items 2 and 3 are independently mergeable.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-321 via `soleur:architecture` (no new ADR; this is mechanism reuse plus two bounded rulings):

- **Three more stale sentences found in plan review**: Consequences, "the signals are the Sentry warning at container start ..." (about line 104-108; a paging rule now exists, `cert_expiry` pages); decision 7's "so the alert is still deferred" (about line 195-197; contradicts the ruling); R-A's "`index.ts` is unchanged in effect from main (comment corrected)" (about line 275; historical, add "superseded by item 12"). Add one sentence that the REQUIRED fatals flush Sentry for up to 2 s before exiting and that the Better Stack log line is the second sink.
- **Item 11 R-B closing sentences** ("There is **no committed Sentry alert rule** ... it is not bundled here"): replace with the
  declared rule (`origin-tls-event`, any event, `frequency_minutes = 47`), stating it is DECLARED in this change and live only after
  `apply-sentry-infra.yml` has applied it on merge.
- **"Idle keep-alive is set above Cloudflare's reuse window" paragraph** (Consequences) and **R-A's "Pre-existing and out of scope"
  sentence**: correct them to the new truth: the plain :80 server's header phase is 60 s and its whole-request window 300 s, set
  explicitly (`server/http-timeouts.ts`); the :443 listener keeps Node's defaults.
- **New item 12 "Follow-up rulings (this PR)"**: `Ruled by CTO agent, 2026-11-08` for (a) the :80 timeouts, (b) deferral of the
  `/health` timing marker with its revival triggers, (c) the alert shape, (d) flush-before-exit. Cite the posted `decision-challenges.md` rows.

### C4 views

No C4 impact. Read all three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`. Checked against the
change: (a) external human actors: the founder as page recipient is already modeled (`sentry -> founder`, issue alerts to email);
(b) external systems: `sentry`, `cloudflare`, `github` (the applier), `betterstack` already exist with the edges this change
uses (`github -> sentry`, `webapp -> sentry`, `cloudflare -> webapp`); no new vendor or inbound webhook; (c) containers/data
stores: none added or touched; (d) actor-to-surface access relationships: unchanged. Derived cardinalities in edge prose:
`plugins/soleur/test/c4-count-parity.test.sh` passed 13/13 at plan time and does not derive an alert-rule count, so the 56 -> 57
rule change cannot move it (re-run it in the work phase to confirm).

### Sequencing

All ADR text is authored now describing the target state; the Sentry sentences use "declared" until the post-merge apply is read.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/sentry/issue-alerts.tf` gains one `sentry_alert` (label `origin_tls_event`, name `origin-tls-event`) in the
existing Sentry root; providers and pins unchanged (`versions.tf`); no new variable, no sensitive value, no new secret. Auth stays
the existing `SENTRY_AUTH_TOKEN` repository secret used by `apply-sentry-infra.yml`.

### Apply path

The root's own path, unchanged: `apply-sentry-infra.yml` runs plan-only on `pull_request` (no path filter on the trigger;
the plan job is gated by `detect-changes`) and applies on `push` to `main` for `apps/web-platform/infra/sentry/**`. **This PR
therefore applies nothing**; the rule goes live when the PR is merged, which is the owner's act and not part of this pipeline. The
PR body says so in one sentence. Blast radius: one new email-routed alert; no host, no edge, no downtime.

### Host fan-out

Not applicable: no `terraform_data` SSH provisioner and no host-resident file is added.

### Distinctness / drift safeguards

`lifecycle { ignore_changes = [environment] }` like the 53 fully-owned siblings; `frequency_minutes = 47` is unique in the root
(re-checked against `origin/main` at work time, because siblings take free values, see the README); the committed
`alert-reference.json` entry is held equal to the plan by `sentry-alert-reference-gate.sh` in `plan_pr`; the daily drift probe
reads that file.

### Vendor-tier reality check

The root already holds 56 rules on the current Sentry plan; the 57th adds one email action to the existing project issue-stream
detector (`data.sentry_project_issue_stream_monitor.web_platform`). No tier gate needed.

## Encryption Posture

Not applicable by the skip rule: the change introduces no persistent store and no new cross-component connection. The Sentry
provider calls and the alert email path already exist. The pre-existing plain :80 listener (retained until the bake passes,
tracked on #10479) is not altered in kind: only its slow-header bound changes, which tightens exposure.

## User-Brand Impact

**If this lands broken, the user experiences:** a wrongly tightened :80 header bound (for example a unit mistake in the new
constants) dropping legitimate requests with a 408 on the plain listener; the deploy canary (`GET /health`) and the Better Stack
`app`/`app_health` monitors catch a systemic break before it serves users. A broken alert rule would only mean a dead :443 pages
nobody (status quo today).

**If this leaks, the user's data is exposed via:** no vector. No data path, credential or personal field is added; the alert
carries tag names only, and the runbook is names/booleans/timestamps only.

**Brand-survival threshold:** aggregate pattern

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** four forks ruled on 2026-11-08 (rows in `decision-challenges.md`): one any-event rule at `frequency_minutes = 47`
with `cert_expiry` paging and no second rule; :80 `headersTimeout = 60_000` and `requestTimeout = 300_000` pinned via a new
import-safe module; no `/health` timing marker (a handler-side marker cannot see TLS setup cost, and `/health` includes a Supabase
round trip); harden seven gitleaks copies plus actionlint with exactly the three owner flags, crane out with a tracking issue.
Carried risks: a deploy restarting under REQUIRED with bad material pages once per 47 minutes per issue group until resolved
(intended; runbook says resolve, never archive); the REQUIRED fatal paths now flush Sentry for up to 2 s before exiting (ruled after plan review); the :80 change ships to production on merge and its real cutoff is the timeout
plus up to 30 s; strict-mode effect on user-facing latency stays unmeasured until the analytics token exists.

No other domain is affected (no UI, no copy, no pricing, no regulated-data surface, no legal-text change: the published TLS
wording is untouched). Product/UX gate: NONE (no file matches the UI-surface list). GDPR gate: not triggered (no schema,
auth, API route or personal-data processing; alert tags are enum values).

## Observability

```yaml
liveness_signal:
  what: >-
    Existing per-start warn line "origin-tls: listening ..." in Better Stack (per host_name) proves the :443 listener bound; the new
    Sentry rule origin-tls-event is the pager for any feature=origin_tls event (phase=runtime / reason=unexpected-close included)
  cadence: per container start (listening line); per event (rule, re-page throttled to 47 minutes per issue group)
  alert_target: email to issue_owners with ActiveMembers fallthrough (the root's convention)
  configured_in: apps/web-platform/infra/sentry/issue-alerts.tf (sentry_alert.origin_tls_event); emitter apps/web-platform/server/origin-tls.ts
error_reporting:
  destination: Sentry (reportSilentFallback / warnSilentFallback, feature=origin_tls) and the pino log mirrored to Better Stack
  fail_loud: the rule emails on first_seen, reappeared, regression and every event (event_frequency_count 1h/0); declared in this change, live after the merge-triggered apply
failure_modes:
  - mode: dead :443 listener after bind (unexpected close, or runtime listener error)
    detection: pino error line (layer 2, mirrored to Sentry; shipped by vector, level >= 40 passes app_container_warn_filter) plus Sentry event feature=origin_tls op=listen phase=runtime (reason=unexpected-close is fatal under REQUIRED, the container restarts); the event is flushed for up to 2 s before the exit
    alert_route: sentry_alert.origin_tls_event -> email (Sentry-side rule). Accepted residual - if the 2.25 s hard timer fires before the flush completes the page is lost and only the pino line in Better Stack remains, which no alert covers
  - mode: rejected or absent certificate at start (op=load / op=create)
    detection: pino error line (vector) and Sentry event; under REQUIRED the candidate container fails its health gate (release gate) and the old one keeps serving
    alert_route: sentry_alert.origin_tls_event -> email
  - mode: certificate under 90 days (op=cert_expiry, warning)
    detection: pino warn line (vector) and Sentry warning event once per start (silent today: about 5474 days left)
    alert_route: sentry_alert.origin_tls_event -> email
  - mode: dead :443 that raises no event (docker-proxy or iptables failure)
    detection: NOT detectable in-process (ADR-321 R-B); the Better Stack app/app_health monitors (vector -> Better Stack, a page after roughly 4 to 6 minutes of failures) and the https LB monitor remain the detectors
    alert_route: Better Stack monitors (unchanged, stated plainly in the ADR sentence)
  - mode: slow-header client dropped by the new 60 s bound on :80 (408 written by Node)
    detection: ACCEPTED GAP - no layer sees it (Node answers the 408 itself and raises no event); a systemic break shows in the release deploy canary (GET /health) and the Better Stack app monitor (vector); per-client drops are the intended behaviour; Cloudflare 408 counts need the analytics token (tracked)
    alert_route: none new (accepted in the CTO ruling)
logs:
  where: Better Stack (pino; apps/web-platform/infra/vector.toml app_container_warn_filter passes level >= 40, so error lines ship) and Sentry
  retention: vendor defaults, unchanged
discoverability_test:
  command: grep -c 'resource "sentry_alert" "origin_tls_event"' apps/web-platform/infra/sentry/issue-alerts.tf
  expected_output: 1
```

Live read after the merge-triggered apply (agent, read-only, not part of this PR): the runbook's existing Sentry check
(`feature:origin_tls`, GET only, token name `SENTRY_ISSUE_RO_TOKEN`) plus the `apply-sentry-infra.yml` post-apply liveness step.

## Files to Edit

- `.github/workflows/ci.yml` - three `curl` lines only (two gitleaks installs, one actionlint install); no other hunk (PR #12410 edits this file elsewhere).
- `.github/workflows/secret-scan.yml` - two gitleaks `curl` lines (the `scan-install` member step and the step near line 533).
- `.github/workflows/main-health-monitor.yml` - two gitleaks `curl` lines.
- `.github/actions/bot-pr-with-synthetic-checks/action.yml` - one gitleaks `curl` line.
- `plugins/soleur/test/required-checks-canonical-parity.test.sh` - new Test 10 (scanner), stale "three install sites" wording in the header and the comment above Test 5 corrected.
- `apps/web-platform/server/index.ts` - import + `applyPlainHttpTimeouts(server);` replacing the `server.headersTimeout = ...` line; rewrite the comment block above it; keep `server.keepAliveTimeout = ORIGIN_TLS_KEEPALIVE_TIMEOUT_MS;` byte-identical.
- `apps/web-platform/server/origin-tls.ts` - (a) export `EXIT_FLUSH_MS = 2_000` and `exitAfterFlush(code, deps?)` (bounded `Sentry.flush`, then exit; always exits on resolve, reject, sync throw or hang via a hard timer at `EXIT_FLUSH_MS + 250`; idempotent per process or per listener closure) and make the DEFAULT `exit` use it (line `params.exit ?? ...`); the injectable `params.exit` is unchanged; reuse the 2 s bound of `crash-handlers.ts` `FATAL_FLUSH_MS`; (b) correct the comment that says "the plain :80 server in index.ts also sets headersTimeout". NO timeout code: the :443 server still assigns neither timeout (R-A).
- `apps/web-platform/test/origin-tls.test.ts` - replace the exact-line regex pin on `server.headersTimeout = ORIGIN_TLS_KEEPALIVE_TIMEOUT_MS + 5_000;` with the wiring pin and rename that test (its title says "unchanged from main"); fix the stale comment near the :443 headersTimeout test (~line 452) that describes the plain server's assignment; leave the :443 pins untouched; add the `exitAfterFlush` cases (below).
- `apps/web-platform/infra/sentry/issue-alerts.tf` - one new `sentry_alert` block with its comment header.
- `apps/web-platform/infra/sentry/alert-reference.json` - one name-keyed entry (key-sorted, `detectorIds` `["1213799"]` like its 53 siblings).
- `apps/web-platform/infra/sentry/README.md` - "56 ... (56 alert rules total)" to 57/57; "54 are fully Terraform-owned (53 of the 55 ..." to 55 (54 of the 56); add `#10479` to the issue list; add a short "Origin TLS paging (#10479)" subsection (declared until applied; resolve, never archive).
- `knowledge-base/engineering/architecture/decisions/ADR-321-origin-tls-terminates-in-the-app-container-with-a-cloudflare-origin-ca-certificate.md` - the amendments under "Architecture Decision (ADR/C4)".
- `knowledge-base/engineering/operations/runbooks/origin-tls-strict-flip.md` - evidence + isolation procedure; the Sentry status row and check paragraph updated for the declared rule.

## Files to Create

- `apps/web-platform/server/http-timeouts.ts` - import-safe constants and `applyPlainHttpTimeouts`.
- `apps/web-platform/test/http-timeouts.test.ts` - behavioural test on a real `http.Server`.
- `apps/web-platform/test/sentry-origin-tls-alert-op-contract.test.ts` - op-contract test.
- Tracking issues (work phase, `gh issue create`, milestone from `knowledge-base/product/roadmap.md`): (a) release-download curl class beyond gitleaks/actionlint (crane in the apply workflow, about 24 bare curls) with `--connect-timeout`/`--max-time` noted; (b) `CF_API_TOKEN_ANALYTICS_READ` token + wrapper subcommand (POST exception) so the analytics query becomes runnable; link both from the runbook and the PR body.
- Spec artifacts: `knowledge-base/project/specs/feat-one-shot-origin-tls-followups/{decision-challenges.md,tasks.md}`.

Path-glob check: every path above was confirmed with `ls`/`git ls-files` at plan time except the three files marked Create; `.github/workflows/*.yml` and `.github/actions/*/action.yml` both match the scanner globs (one file each at least).

## Implementation Phases

Order is test-first per item (`cq-write-failing-tests-before`); items are independent, so a phase can be reverted alone. The ADR text for
all items is written once in Phase 5 to avoid conflicting edits.

### Phase 0 - Sync and re-measure (no edits)

- `git fetch origin main`; `git merge origin/main` if behind (hook-friendly: no stash). Re-grep the seven gitleaks copies
  (`/usr/bin/grep -a -rn 'releases/download/v${GITLEAKS_VERSION}' .github`) and the actionlint copy; abort and re-plan the hunks if
  #12410 or another PR moved them.
- Re-derive the free `frequency_minutes`: `/usr/bin/grep -a -h 'frequency_minutes *=' apps/web-platform/infra/sentry/*.tf | sed 's/ //g' | sort -t= -k2 -n -u`; take the lowest unused value at or above 47 and carry it through every artifact below (the plan says 47; the test derives the value from the `.tf`).
- Confirm the six items of "Local measurements" still hold on the repo-pinned Node (`.nvmrc` 22.23.4) if available, else record the Node used.

### Phase 1 - Item 2: curl hardening (Guard 1)

1. RED: add to `required-checks-canonical-parity.test.sh` a new **Test 10** (after the current last test; do NOT reuse the `(5b)` label, which Test 5 already uses): a scanner function `scan_curl_flags <file...>` that joins `\` continuation lines, finds logical `curl` commands whose URL contains `gitleaks/gitleaks/releases/download` or `rhysd/actionlint/releases/download`, and asserts the tokens `--fail`, `--retry 5` and `--retry-all-errors` are on the command. Scope: `.github/workflows/*.yml` and `.github/actions/*/action.yml`.
   - Floors: gitleaks copies found >= 7, actionlint >= 1, and scanner count == an independent raw count taken on NON-comment lines with the variable-form fragment (`/usr/bin/grep -a -E '^[^#]*releases/download/v\$\{(GITLEAKS|ACTIONLINT)_VERSION\}'`; the literal-version URL in the `secret-scan.yml` comment must not be counted), so a scanner that mis-joins cannot pass with zero.
   - In-suite mutation self-test: strip one flag from a temp copy of a real workflow, expect the scanner to FAIL it; plus a must-PASS variant with the flags in a different order.
   - Fix the stale wording only where it is stale: the header's "three install sites" (line ~21) and the comment above Test 5 (line ~257); Test 5's own title ("all 4 sites") is correct and stays.
   Bash hygiene (test-design review): the suite runs `set -euo pipefail`, so capture the scanner result with `out=$(scan_curl_flags ...) || rc=$?` and assert on it, otherwise a failing scan aborts the suite before any FAIL is counted; match tokens exactly (`(^|[[:space:]])--retry[[:space:]]+5([[:space:]]|$)`, so `--retry 50`, `--retry-all-errors` alone and `--fail-with-body` do not satisfy the other flags; state whether `-f`/`-fsSL` counts: it does NOT, the owner named `--fail`); drop whole-line `#` comments before joining; POSIX awk only (no `gensub`, `IGNORECASE`, `{n}` intervals: the runner may have mawk); pass a floor to `print_results`.
   Run it; it must FAIL on the 8 unhardened lines.
2. GREEN: change only the `curl` line in each of the eight places to `curl --fail --retry 5 --retry-all-errors -sSLo ...` (keep the `\` continuation and the URL line; keep `echo "${GITLEAKS_SHA256}  ..." | sha256sum -c -`).
3. Run `actionlint` (installed locally) over the four touched files and `bash plugins/soleur/test/required-checks-canonical-parity.test.sh`; run `scripts/lint-workflow-run-body-syntax.py` if it takes paths.

### Phase 2 - Item 3: :80 timeouts (Guard 3)

1. RED: `apps/web-platform/test/http-timeouts.test.ts` with `http.createServer({ connectionsCheckingInterval: 100 })`:
   (a) after `applyPlainHttpTimeouts(server, { headersMs: 500, requestMs: 2500 })` a client that never finishes its headers gets a 408 or close at about 0.5 s (< 2 s), not 2.5 s; (b) the helper throws when `headersMs > requestMs`; (c) source pins: `index.ts` (comments stripped) contains `applyPlainHttpTimeouts(server);` and no longer contains `server.headersTimeout =`; the exported defaults are 60_000 and 300_000. (The `origin-tls.ts` absence of both assignments is already pinned at `origin-tls.test.ts` lines ~459-462; do not duplicate it. The idle keep-alive behaviour is measured in ADR-321 R-A and re-tests Node, so it is not repeated.)
   Timing hygiene (test-design review): real timers, port 0, close client and server in `finally`; assert the cutoff lands in `[~400, ~1500]` ms (Node can be late by up to `connectionsCheckingInterval`), never exact equality; use `headersMs` far below `requestMs` (500 vs 2500) so swapping the assignments is caught; hardcode 60_000/300_000 independently in the constants test (not by importing the same values); comment why the 0.5 s wait is intentional.
   Update `origin-tls.test.ts`: replace the exact-line pin at ~line 760 for the 910 s assignment (keep the `keepAliveTimeout` pin) with the wiring pin; the :443 tests are unchanged.
2. GREEN: create `server/http-timeouts.ts` (no server imports; exports the two constants and `applyPlainHttpTimeouts(server, t = {headersMs, requestMs})` assigning both properties and throwing on `headersMs > requestMs`); wire it in `index.ts`; rewrite the `index.ts` comment to state the truth (header phase 60 s, request window 300 s, :443 keeps Node defaults for the same header value, real cutoff up to timeout + 30 s); correct the `origin-tls.ts` comment only.
3. Run `apps/web-platform/test/http-timeouts.test.ts`, `origin-tls.test.ts`, `server-index-boot-pin-line.test.ts` (it imports `index.ts` with mocks; its fake `createServer` returns a plain object, so the two property assignments need no change) and the web-platform typecheck (`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`, not the npm workspace script).

### Phase 3 - Item 1: Sentry rule (Guard 2)

0. RED then GREEN, first: `exitAfterFlush` in `origin-tls.ts` with cases in `origin-tls.test.ts` using fake deps: (1) order: `flush` (deferred) is called with 2000 and `exit` has not run; after resolving, `exit(1)` runs once, after `flush` (`invocationCallOrder`); (2) flush rejects -> `exit(1)` still runs; (3) flush throws synchronously -> `exit(1)` still runs; (4) flush never settles -> with fake timers, `exit(1)` runs after 2250 ms; (5) two calls -> one `exit`; (6) wiring: with `vi.mock("@sentry/nextjs")` and an explicit `process.exit` spy (vitest traps it), a REQUIRED start with absent material and NO injected `exit` calls `Sentry.flush` before the spy. The idempotence flag must not leak between tests (per-listener closure or an exported reset). `vi.mock("@sentry/nextjs")` automocks `flush` to return `undefined`: `exitAfterFlush` must tolerate a non-promise return and the case sets `flush.mockResolvedValue(undefined)`; use `vi.advanceTimersByTimeAsync(2250)` for the hang case and assert `exit` has NOT run at 2249 ms; in the wiring case assert the `process.exit` spy WAS called and that `flush`'s `invocationCallOrder` is lower than the spy's (otherwise vitest's trap makes it vacuous).
1. RED: `sentry-origin-tls-alert-op-contract.test.ts`, modelled on the approval-gate and legal-acceptance tests (comments stripped before any match; literals derived from source, never kept in the test): derive the `feature` literal from every `reportSilentFallback`/`warnSilentFallback` site in `origin-tls.ts` (all equal `origin_tls`; derived site count floor); assert the rule block exists; its ONLY `tagged_event` condition is `feature eq origin_tls` (no `op`, `phase`, `reason` filter, so a future op is covered by default); the four triggers (`first_seen_event`, `reappeared_event`, `regression_event`, `event_frequency_count {1h, 0}`); the action is `email` `issue_owners` + `ActiveMembers`; `frequency_minutes` distinct across ALL root `.tf` files (copy `assertFrequenciesDistinct`, with its own negative control); the `alert-reference.json` entry equals the `.tf`(the graceful-shutdown suppression of the `unexpected-close` report is already pinned by `origin-tls.test.ts` ~lines 665-682 and is not repeated).
2. GREEN: add the `sentry_alert` block (comment header explaining the any-event choice, the `cert_expiry` inclusion, the re-page triggers, the unique frequency, and "DECLARED until applied"); hand-write the `alert-reference.json` entry from the nearest sibling (`legal-acceptance-row-without-event` shape) and prove it is normalised: `jq -S . alert-reference.json | diff - alert-reference.json`; bump the README (counts, list, subsection).
3. Run the new test, `sentry-git-data-pin-fault-alert-op-contract.test.ts` (README census), `apps/web-platform/scripts/sentry-monitors-audit.test.sh` (T25 counts), `terraform fmt -check` on the root and `terraform validate` if `init` works without credentials (otherwise note it; CI `plan_pr` plus `sentry-alert-reference-gate.sh` is the authority for the projection).

### Phase 4 - Item 4: runbook write-up (docs only)

Edit `origin-tls-strict-flip.md` (details under "Runbook content" below). No server code. Mark every unverified claim UNVERIFIED and end the section with a "Still unverified (do NOT record as verified)" list.

### Phase 5 - ADR, tracking issues, verification

1. ADR-321 edits (via `soleur:architecture`); runbook status row and Sentry check paragraph updated to "declared, live after the merge-triggered apply".
2. File the two tracking issues; link them in the runbook and the PR body.
3. Full local verification: `bash plugins/soleur/test/c4-count-parity.test.sh`; `python3 scripts/lint-guard-contract.py <plan>`; markdown lint if the repo has it on `knowledge-base/**`; run the touched vitest files and the bash suite; `git diff --stat origin/main` stays inside the Files lists.
4. PR body: `Ref #10479`, `Ref #10205`, the "merge applies the Sentry rule" sentence, the Node-cutoff-plus-30 s caveat, the 31-second retry-budget honesty line, the decision-challenges rows. Before saving: `gh pr view 12434 --json closingIssuesReferences` must print `[]`. Do not mark ready, merge or dispatch anything.

## Runbook content (Phase 4 spec)

New section "/health p90 after the strict flip: evidence and isolation procedure" (placed after the existing "Latency and error samples"):

1. **Evidence table** extended with: 16:35Z 2026-11-08 two samples (0.218 / 0.359 and 0.193 / 0.318); the server-wait decomposition (ttfb minus pretransfer) for `app.soleur.ai/health` p50 0.154 / p90 0.285 versus the apex `soleur.ai/` p50 0.082 / p90 0.111, each n=30; restart pairs: 11 between 01:05Z and 16:17Z (count and range only); Better Stack: no handshake-failure or unexpected-close lines since 00:20Z; `origin-tls-probe.sh --require-tls` TLSv1.3.
2. **Reading the evidence honestly**: n=30 makes p90 roughly the third-slowest value, so run-to-run spread is large (the 16:35Z pair already differs by 0.04 s); p50 moved little (0.190 -> 0.193-0.225); the apex control shares only the client network, not the Node process, the Supabase leg or the Cloudflare-to-origin hop, so 0.154 vs 0.082 is not a TLS number; no pre-flip server-wait decomposition exists, so no before/after split of the 0.154.
3. **Candidates and what each predicts** (all UNVERIFIED): (1) redeploys: cold origin connection pool and cold Supabase leg right after a restart (the app warms the Supabase edge, #8978, which bounds but does not remove this) - predicts tail clusters after restarts; (2) TLS CPU in Node - predicts p50 and CPU correlation, unlikely at sub-millisecond per keep-alive request; (3) handshakes on new Cloudflare-to-origin connections: under `flexible` a new origin connection costs a TCP handshake, under `strict` it adds a TLS 1.3 handshake and certificate validation (about one more round trip between the Cloudflare colo and the origin) - predicts a step at 23:43Z that is stable across restarts and per-colo; (4) `/health` includes a PostgREST round trip on every request - predicts the tail follows Supabase latency and the same shape on any path that also calls it, regardless of TLS.
4. **Isolation procedure, read-only, in order**, each step with the expected discriminating outcome:
   - Step A (no token): interleaved A/B loop, n >= 100 per path over at least 10 minutes: `GET /health?l=<rand>` versus a Supabase-free same-origin control. Candidate control `/robots.txt?cb=<rand>` (served through Next, so it also passes the Next middleware: an imperfect control, UNVERIFIED that it makes no Supabase call); the control is valid only when `cf-cache-status` is not `HIT`. Record `time_connect`, `time_appconnect`, `time_pretransfer`, `time_starttransfer`, the `cf-ray` colo suffix and the status; stratify by colo. Report p50/p90/p99 per path. Interpretation table: control p90 also elevated vs its own earlier sample -> edge/connection effect (candidate 3); only `/health` elevated -> app-side/Supabase (candidate 4); neither differs from the baseline when re-run now -> small-sample noise.
   - Step B (no token): the Supabase leg alone from a client, same hours (`/rest/v1/` with the public anon key header from Doppler, names only; UNVERIFIED that the endpoint answers 200 for the anon key).
   - Step C (needs the token): the Cloudflare analytics GraphQL by hour: dataset `httpRequestsAdaptiveGroups`, filter `datetime_geq`/`datetime_lt` (slices of at most 24 h, UNVERIFIED cap), `clientRequestHTTPHost: "app.soleur.ai"`, `clientRequestPath: "/health"`, `requestSource: "eyeball"`, `orderBy: [datetimeHour_ASC]`, dimensions `datetimeHour`, quantiles of origin response duration. First run a schema discovery query and select the field names from its output (the exact quantile field names are UNVERIFIED): `{ __schema { types { name fields { name } } } }` filtered with `jq` to names containing `originResponse`. Windows: 2026-11-07T12:00Z to 23:43Z (pre) and 23:44Z to now (post), plus the same for a Supabase-free path; a step at 23:43Z in origin duration confirms candidate 3 or 2, no step with a tail that follows restarts confirms 1, and a `/health`-only step with a flat control confirms 4.
   - Token: a new `CF_API_TOKEN_ANALYTICS_READ` (Analytics:Read + Zone:Read), bound to a new subcommand of `plugins/soleur/scripts/cloudflare-readonly.sh`, no fallback to another token (CTO ruling). Prerequisite stated plainly: the wrapper is GET-only and GraphQL is POST, so the subcommand needs a documented read-only-POST exception; token creation and the subcommand are a separate change (tracking issue linked).
5. **Marker ruling** (no marker now) with the revival triggers: the Supabase-free control also regresses by more than 50 ms at p90; or a step change in Cloudflare origin duration aligned with the flip; or a user-facing latency complaint. If triggered: a `warn` line (Vector drops INFO) `SOLEUR_HEALTH_TIMING` with `total_ms`, `supabase_ms`, `tls`, `protocol`, emitted after the response, try/catch, only when `total_ms > 500` plus a 1-in-50 sample, at most 6 lines per minute; body and status unchanged (`health-keyword-monitor-contract.test.ts`).
6. **Status** line: unexplained; strict-mode effect on user-facing latency unmeasured; do not read "fine" into a flat p50.
7. Update the existing "Open checks" row for Sentry `feature:origin_tls` and the "Real 502/520 rate" row to point at the declared rule and the token tracking issue.

## Guard Contract

### Guard 1 - gitleaks/actionlint download flags scanner

**Property.** Every pinned release-download `curl` for gitleaks or actionlint in any workflow or composite action carries `--fail`, `--retry 5` and `--retry-all-errors`.

**Assembly.** The population is every `curl` logical command (continuation lines joined) in `.github/workflows/*.yml` and `.github/actions/*/action.yml` whose URL contains `gitleaks/gitleaks/releases/download` or `rhysd/actionlint/releases/download`; the chokepoint is the scanner function, which takes the file list as an argument so the self-test can feed it a mutated copy. Today that is 7 gitleaks plus 1 actionlint across 4 files; the count is derived by scanning and cross-checked against an independent raw count on non-comment lines with the variable-form URL fragment, never a hand-listed set. The crane sites (a different URL) are deliberately outside the population and tracked separately.

**Mutation matrix.**

| # | Edit (to the tree or the scanner) | Must go RED because |
|---|---|---|
| 1 | Remove `--retry-all-errors` from one gitleaks copy (any of the seven, including the `action.yml` shape) | token absent in that command |
| 2 | Add an eighth gitleaks copy WITHOUT the flags after a compliant first | the scanner checks every member, not the first |
| 3 | Break the scanner's dispatch (glob matches no file / URL regex matches nothing) | floors `>= 7` / `>= 1` and scanner-count == raw-count both fail; "0 checked" is never green |
| 4 | Put the flags in a comment or an `echo` line near the curl, not on it | the token must be inside the logical curl command |

**Harness rows.** Edit the suite: replace the scanner call with `true` -> the in-suite mutation self-test (row 1 on a temp copy) must FAIL. Must-PASS non-canonical input: flags in a different order with `-sSLo` before them.

**Anchor.** The stored value is the flag set, not a hash; weakening it needs a test edit in the same diff, which is visible in review of a required-checks parity test. No external anchor is claimed.

### Guard 2 - origin_tls alert op-contract

**Property.** Any Sentry event the app emits with `feature=origin_tls`, whatever its `op`, `phase` or `reason`, matches the committed rule, which re-pages on every event.

**Assembly.** The population is every `reportSilentFallback`/`warnSilentFallback` call site in `server/origin-tls.ts` (and any other server file that later emits `feature: "origin_tls"`); the chokepoint is the rule's filter list in `issue-alerts.tf`, mirrored by the `alert-reference.json` entry and the README count. The test derives the feature literal from the source at test time; the rule carries no `op`, `phase` or `reason` filter, so a new op is covered by default.

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|---|---|
| 1 | Add `{ tagged_event = { key = "op", ... } }` to the rule | narrower than the feature (the class this gate exists for) |
| 2 | Change the emitter's feature literal at ONE of the sites (`origin_tls` -> `origin-tls`) | the derived literal set has two members / a site no longer matches the rule |
| 3 | Remove `event_frequency_count {1h, 0}` | a repeat event would email once then stay silent while the issue is open |
| 4 | Give the rule the same `frequency_minutes` as another rule | Sentry POST-time dedup collision; distinctness across the whole root |
| 5 | Edit the `.tf` rule but not `alert-reference.json` (or vice versa) | the reference must equal the `.tf` |
| 6 | Rename the resource label so the block-extraction regex matches nothing | the non-empty-block assertion fails; "no block found" is never green |
| 7 | Make the default `exit` call `process.exit` directly again (no flush) | the wiring case in `origin-tls.test.ts` (flush before the exit spy) fails |

**Harness rows.** Edit the suite: weaken the filter assertion to `toBeTruthy` -> the suite's own negative control (a fixture `.tf` string with an `op` filter that the helper must flag) must go RED. Must-PASS non-canonical: a fixture rule with the triggers in a different order and an extra comment line must still pass.

**Anchor.** The README count and the reference entry are checked against the `.tf` in the same repo (consistency); `sentry-alert-reference-gate.sh` in `plan_pr` re-projects the reference from the real Terraform plan, which a diff cannot edit (integrity for the reference); the emitter literal is derived from source, so no stored copy exists to drift.

### Guard 3 - :80 slow-header bound

**Property.** The plain :80 server's slow-header cutoff is the explicit 60 s header phase inside a 300 s request window, applied through one helper that `index.ts` actually calls.

**Assembly.** The population is every code path that sets `headersTimeout` or `requestTimeout` on a server in `apps/web-platform/server/`: `index.ts` (the :80 server, via the helper) and `origin-tls.ts` (:443, must set none; already pinned by `origin-tls.test.ts`). The chokepoint is `applyPlainHttpTimeouts`; the behavioural test exercises it on a real `http.Server`, and a source pin (comments stripped) covers the wiring. Other server creators (`session-proxy.ts` has its own `https.createServer`) are out of the property by design and unchanged.

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|---|---|
| 1 | Remove the `applyPlainHttpTimeouts(server);` call in `index.ts` | the wiring pin fails (the helper alone proves nothing about the real server) |
| 2 | Swap the helper's assignments (`headersTimeout` gets the request value) | the observed cutoff is the long value, not the short one |
| 3 | Re-add `server.headersTimeout = ...` after the call in `index.ts` | the dead-assignment pin fails |
| 4 | Make `PLAIN_HTTP_HEADERS_TIMEOUT_MS` larger than the request window | the helper throws / the constants pin fails |

**Harness rows.** Edit the suite: replace the 408 assertion with a wait-only check -> the case must fail because the early close/408 never arrives; assert `connectionsCheckingInterval` is set in the fixture so the case cannot pass by timing out slowly. Must-PASS non-canonical: `{ headersMs: 700, requestMs: 700 }` (equal values) is permitted and must pass.

**Anchor.** The constants are pinned in the test and the ADR-321 item-12 sentence names 60 s / 300 s, so weakening both in one diff passes the constants pin; the behavioural case asserts the OBSERVED cutoff for injected values, and the ADR sentence is what reviewers read. No external anchor is claimed.

## Acceptance Criteria

- [ ] AC-CURL: all eight `curl` lines carry `--fail --retry 5 --retry-all-errors`; the sha256 checks are unchanged; the scanner arm passes and, with one flag removed in a temp copy, fails (`required-checks-canonical-parity.test.sh` header and titles state the real counts). Evidence: `required-checks-canonical-parity.test.sh` + `.github/workflows/ci.yml` hunks.
- [ ] AC-CIHUNKS: `git diff origin/main -- .github/workflows/ci.yml` shows exactly three changed lines (two gitleaks, one actionlint) and no other hunk.
- [ ] AC-RULE: `issue-alerts.tf` has `sentry_alert.origin_tls_event` (name `origin-tls-event`) with only the `feature eq origin_tls` filter, the four triggers, email `issue_owners`/`ActiveMembers`, a root-unique `frequency_minutes`; `alert-reference.json` has the matching key-sorted entry; README counts are 57/57 and 55-owned; `sentry-origin-tls-alert-op-contract.test.ts`, the README census test and `sentry-monitors-audit.test.sh` pass. Evidence: `apps/web-platform/infra/sentry/issue-alerts.tf` block + new test.
- [ ] AC-FLUSH: the default `exit` in `origin-tls.ts` flushes Sentry (bounded 2 s, hard timer 2.25 s) before `process.exit`; all six `exitAfterFlush` cases pass; existing tests that inject `exit` are unchanged.
- [ ] AC-TIMEOUTS: `server/http-timeouts.ts` exists; `index.ts` calls `applyPlainHttpTimeouts(server);`, keeps `server.keepAliveTimeout = ORIGIN_TLS_KEEPALIVE_TIMEOUT_MS;` and no longer assigns `server.headersTimeout`; `origin-tls.ts` has no TIMEOUT code change (the flush change is separate) and still assigns neither timeout; `http-timeouts.test.ts`, `origin-tls.test.ts` and `server-index-boot-pin-line.test.ts` pass; web-platform `./node_modules/.bin/tsc --noEmit` clean.
- [ ] AC-RUNBOOK: the runbook contains the evidence table, the four candidates with predictions, the interpretation table, Steps A-C, the token/POST-exception prerequisite, the marker ruling with revival triggers, and a "Still unverified" list; no secret value, no `ssh`, names/booleans/timestamps only.
- [ ] AC-ADR: ADR-321 carries the item-11 sentence replacement, the corrected keep-alive/R-A sentences, and item 12 with the three `Ruled by CTO agent, 2026-11-08` entries; wording says "declared" for the alert.
- [ ] AC-ISSUES: the two tracking issues exist and are linked from the runbook and the PR body.
- [ ] AC-NOAPPLY: no workflow was dispatched, no `terraform apply` ran, the PR is a draft; `git diff --stat origin/main` touches only the Files lists plus the artifacts the pipeline itself writes (this plan, `specs/feat-one-shot-origin-tls-followups/*`, learnings, archived KB copies at ship).
- [ ] AC-REFS: the PR body has `Ref #10479` and `Ref #10205` and no closing keyword for either; `gh pr view 12434 --json closingIssuesReferences` prints `[]` before the body is saved.
- [ ] AC-GUARDLINT: `python3 scripts/lint-guard-contract.py` passes on this plan; `c4-count-parity.test.sh` passes.

### Post-merge (agent, read-only; NOT done by this PR)

- After the merge-triggered `apply-sentry-infra.yml` run: confirm the rule exists and is enabled through the run's own post-apply liveness step or `scripts/sentry-alert-live-fidelity.sh`-style read; update the ADR/README word "declared" to "applied" in a follow-up only if the owner wants the wording changed.
- After the next web deploy: read the `origin-tls: listening` lines per host (runbook command) and check no new 408 pattern on :80 in the monitors.

## Test Scenarios

- Given a gitleaks install `curl` without `--retry-all-errors`, when the parity suite runs, then it fails naming the file and the missing flag.
- Given a local server answering 503 twice then 200, when `curl --fail --retry 5 --retry-all-errors` fetches it, then exit 0 with the good body; when bare `curl -sSLo` fetches it, then exit 0 with the error body.
- Given a client that stalls mid-header on the :80 server configured with injected short values, when the header bound passes, then it receives a 408/close well before the request bound.
- Given an idle keep-alive connection, when the idle time is shorter than `keepAliveTimeout` but longer than the header bound, then the next request on it is answered.
- Given a `listen` event with `reason=unexpected-close` and `phase=runtime`, when the rule is evaluated, then it matches by `feature` alone.
- Given a graceful shutdown (our own `close()`), then no `origin_tls` event is emitted (source guard).
- Given a new `op` added to `origin-tls.ts` later, then the rule still matches and the op-contract test needs no edit.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `aggregate pattern`.
- `alert-reference.json` is normally generated from the `plan_pr` plan artifact; a hand-written entry must equal the projection exactly (key-sorted, `detectorIds`). `plan_pr` is the authority; do not claim local equivalence beyond `jq -S` normalisation and the op-contract equality.
- `frequency_minutes` is root-wide and siblings take free values between plan and merge: re-check after every merge of `origin/main` (the README records a lost race, 38 -> 39).
- The new rule is DECLARED until `apply-sentry-infra.yml` runs on merge; never write "live" or "paging" in the ADR/runbook before the apply is read. Vendor-default Sentry workflows (not managed here) may also email on an `origin_tls` issue; the rule does not claim to be the only channel.
- `index.ts` starts a server and is imported only by `server-index-boot-pin-line.test.ts` with mocks; the new behavioural test imports `http-timeouts.ts`, never `index.ts`.
- The retry budget is about 31 s; do not write that the change would have survived the 80-minute outage. `--retry-all-errors` also retries a 404 or a certificate error, so a removed release now takes about 31 s to fail instead of failing at once: still loud, only slower. Optional hardening `--proto-redir =https` is NOT added (the owner named three flags).
- Do not touch the :443 server's timeouts; the R-A test forbids `headersTimeout =`/`requestTimeout =` in `origin-tls.ts` even in code added "for symmetry". The only `origin-tls.ts` code change is the flush-before-exit helper.
- `exitAfterFlush` delays the REQUIRED exit by up to about 2 s; `failClosed()` still returns immediately. The pino error mirror is itself mirrored to Sentry (`logger.ts` pino-mirror, per the CTO read), so Better Stack holds the record but does not send the page (verified in the deepen pass: `vector.toml` `app_container_warn_filter` passes `level >= 40`, so the pino error line ships to Better Stack).
- Runbook commands for Steps B and C must reuse the existing pattern in the runbook's Sentry check (`doppler run -p soleur -c <config> -- bash -c 'curl --disable --noproxy "*" ... --config - < <(printf "header = \"Authorization: Bearer %s\"\n" "$TOKEN")'`): the token or the `apikey` header is never in argv, response headers and the request config are never printed, and the schema-discovery `jq` prints field names only.
- A test (or the op-contract) should pin that no `origin_tls` emit site interpolates `err.message` into the event message (the `cert_expiry` path passes an `Error`; its message is static today).
- The runbook is read by agents: no `ssh`, no values, `UNVERIFIED` on every claim not measured here (`hr-no-ssh-fallback-in-runbooks`).
- `grep` is a shell function in this environment; use `/usr/bin/grep -a`.
