---
title: "fix: make the GitHub Pages cert reissue diagnosable and validate its DNS-only window"
date: 2026-07-19
type: fix
issue: 6698
ref: 6657
app: web-platform
semver: patch
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: make the GitHub Pages cert reissue diagnosable and validate its DNS-only window

Ref #6698. Ref #6657. Conditionally amends ADR-125 (see Architecture Decision).

No spec.md exists for this branch — spec lacks valid `lane:`, defaulted to
`cross-domain` (TR2 fail-closed).

## Overview

`cron-gh-pages-cert-reissue` now completes its full toggle (the `pages:write` +
`administration:write` blocker was fixed by #6687/#6694, prod `v0.226.5`), but
the ACME cert still never reaches `issued`/`approved` inside the routine's
~14-minute DNS-only poll window. Two live fires ~2.5h apart on 2026-07-19 both
ended `bad_authz` with DNS correctly restored to `proxied=true`.

The failure could not be isolated because the routine is **observationally dark
on its success path**. A blind surface must emit a discriminating probe before an
Nth blind fix (`hr-observability-as-plan-quality-gate`; learning
`best-practices/2026-07-01-blind-surface-needs-structured-probe-before-nth-fix.md`).

**The single most important thing in this plan is Phase 0.1.** A read-only
Cloudflare API call may end the investigation before any code is written: the
apex and www both currently return AAAA records that **no Terraform file
declares**, and the routine's toggle set does not touch AAAA. If those are real
zone records rather than Cloudflare's synthetic proxy answer, they stay proxied
through the entire DNS-only window, Let's Encrypt prefers IPv6, and **the routine
can never succeed at any window length**. That would make the whole
window/propagation line of work premature.

Deliverables, in dependency order:

0. **Rule out the AAAA root cause** (read-only, plan-time, free).
1. **Telemetry** — `SOLEUR_CERT_REISSUE` pino-WARN step markers for every phase.
2. **Probe-only mode + DNS-propagation gate** — measure the DNS-only state
   *without* consuming a Let's Encrypt validation attempt.
3. **Follow-through sweeper reopen path** — a prematurely-closed `follow-through`
   issue is currently invisible to the sweeper forever.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #6698 / task brief) | Reality (verified 2026-07-19) | Plan response |
| --- | --- | --- |
| The sweeper's recovery predicate is a false positive; it must assert `.https_certificate.state` is issued/approved before closing | **Falsified.** `scripts/followthroughs/gh-pages-cert-reissue-6657.sh` has exactly one commit (`0c58e8b60`) and already gates on `case "$STATE" in issued\|approved) exit 0`; `bad_authz` exits 1 (FAIL). The predicate is correct. | Re-scope Deliverable 3 to the real defect (next row). |
| The sweeper auto-closed #6657 as COMPLETED on 2026-07-18T20:50Z | **Falsified.** The sweeper runs `cron: '0 18 * * *'` as `secrets.GITHUB_TOKEN` (closures appear as `github-actions[bot]`). #6657 was closed at `20:50:07Z` by **`deruelle`** — an operator-token agent session, ~18 min before its own post-merge status comment. The directive's `earliest=2026-07-25T00:00:00Z` had not elapsed, so the sweeper had never evaluated it. | Deliverable 3 targets the actual hole: `scripts/sweep-followthroughs.sh:290` lists `--state open` only, so any premature close (manual, agent, or `Closes #N`) is permanently invisible and can never be reopened. |
| PR #6676 auto-closed its tracker via `Closes #N` | **Falsified.** PR #6676's body uses `Ref #6657` correctly. | No change; the `Ref` convention held. |
| Add a mid-window assertion via `dig @1.1.1.1 soleur.ai` | **Falsified as an implementation.** `dig` is not installed — `apps/web-platform/Dockerfile:83-85` installs only `ca-certificates git bubblewrap socat qpdf jq`; zero matches for `dnsutils`/`bind-tools`/`dig`. | Use `node:dns/promises` `Resolver` + `setServers()`. The cron file already imports `node:dns/promises` (`gatherPreconditions`). Core Node, no dependency. No in-repo `Resolver`/`setServers` precedent — verify the exact API at Phase 0.2. |
| Ship "monitored stdout `SOLEUR_*` markers" | **Refined.** stdout is the correct transport, but `console.log` is not the convention and the injected Inngest ctx `logger` does not work at all (H-T). | Mirror `apps/web-platform/server/claude-cost-marker.ts:70` — module-scope pino at WARN with a top-level boolean discriminator. |
| Lengthening the DNS-only window exposes Hetzner origin IPs / bypasses the WAF | **Falsified.** The toggled records are `cloudflare_record.github_pages` (4× `185.199.x`, GitHub Pages **public anycast**) and `cloudflare_record.www` (CNAME → `jikig-ai.github.io`). The Hetzner origin sits behind `cloudflare_record.app` (`app.soleur.ai`), which the routine never touches. No origin disclosure, no WAF bypass to a private host. | Re-framed in `## User-Brand Impact`. The real cost is **worse and more public**: during DNS-only, apex/www serve GitHub's `bad_authz` cert, so every HTTPS visitor to the marketing site gets a TLS error. This is a stronger argument for keeping the window short. |
| The 14-min window is too short → lengthen `POLL_MAX_MS` | **Not supported by evidence, and premature.** Three hypotheses are live and the poll cannot distinguish them. | Keep the total DNS-only window at **15 min, unchanged**. Budget the propagation gate **out of** `POLL_MAX_MS`, not on top. Lengthening is only defensible against a *measured* propagation time. |
| Cert is `bad_authz`, expires 2026-08-16, `https_enforced` false | **Confirmed live.** `gh api /repos/jikig-ai/soleur/pages` → `{"cname":"soleur.ai","expires":"2026-08-16","https_enforced":false,"state":"bad_authz"}`. | Runway is real; sequence for diagnosis over speed. |

## Observability layer citation

Per `hr-observability-layer-citation`, the exact chain a marker traverses:

> pino (level ≥ 40) → container stdout → Docker `--log-driver journald`
> (`apps/web-platform/infra/cloud-init.yml:775`, `infra/ci-deploy.sh:2408,2641`)
> → host journal `CONTAINER_NAME=soleur-web-platform` → Vector
> `[sources.app_container_journald]` → `[transforms.app_container_warn_filter]`
> (keeps pino `level >= 40` **only**) → `[transforms.tag_journald]` (adds
> `source_kind=app_container`, `host_name`) → `[sinks.betterstack]` (HTTP POST,
> `BETTERSTACK_LOGS_TOKEN`) → Better Stack source `soleur-inngest-vector-prd`
> (id 2457081, team 520508) → read back via `scripts/betterstack-query.sh`
> (ClickHouse HTTP, `raw LIKE '%…%'`).

All verification pulls from that chain directly
(`hr-no-dashboard-eyeball-pull-data-yourself`); no step opens a dashboard and no
step uses SSH (`hr-no-ssh-fallback-in-runbooks`).

## Hypotheses

Per the Sharp Edge on hypothesis tables: **no verdict below reads CONFIRMED for
anything whose discriminator is currently invisible.** H-T is confirmed because
its discriminator (the SDK source and the Vector config) is readable in-repo. The
H-W family is UNKNOWN — that is precisely what this change exists to resolve.

### H-T (telemetry gap) — CONFIRMED, mechanism identified in-repo

Two independent causes stack, and **both** must be avoided:

- **H-T1 — the injected Inngest ctx `logger` is gated off.** `server/inngest/client.ts`
  constructs `new Inngest({...})` with **no** `logger` option, so inngest@3.54.2
  falls back to `DefaultLogger` wrapped in `ProxyLogger`. `ProxyLogger.info()`
  begins `if (!this.enabled) return;`, and `enabled` flips true only in
  `beforeExecution()`. Inngest re-runs the function body from the top on every
  HTTP request and memoizes completed steps, so any `logger.info` on a
  memoization/discovery pass is **silently swallowed**. `HandlerArgs["logger"]`
  (`_cron-shared.ts:183`) is only a structural type over that ctx value.
- **H-T2 — Vector drops pino INFO.** `[transforms.app_container_warn_filter]`
  keeps `level_int >= 40` only. Any pino `info` line never leaves the host.

This exactly explains the reported asymmetry: the failure path emitted an
`app_container` `reissue-terminal` row because `reportSilentFallback`
(`server/observability.ts:216`) mirrors through module-scope pino at **error**
(50) and never touches the ProxyLogger; the success path used the ctx `logger`
and vanished. The `initializing fn` line is not ours — it is the Go supervisor
via `[sources.inngest_journald]` (`include_units = ["inngest-server.service"]`),
a different pipeline entirely.

### H-W4 (undeclared AAAA) — UNKNOWN, highest prior, resolvable for free

Public resolution via `1.1.1.1` right now:

```
A    soleur.ai      188.114.96.2, 188.114.97.2      (Cloudflare)
AAAA soleur.ai      2a06:98c1:3120::2, 2a06:98c1:3121::2
AAAA www.soleur.ai  2a06:98c1:3120::2, 2a06:98c1:3121::2
```

`grep -c AAAA apps/web-platform/infra/dns.tf` → **0**. `cloudflare_record.github_pages`
declares only the 4 A-records; `listToggleRecords` queries `type=A` (apex) +
`type=CNAME` (www); `EXPECTED_TOGGLE_RECORDS = 5`. **Nothing in the routine
touches AAAA.**

Two possibilities with opposite implications:

1. **Synthetic.** Cloudflare serves both address families for a proxied A record.
   `proxied=false` removes it. Harmless.
2. **Real, unmanaged zone record.** It stays proxied through the entire DNS-only
   window. Let's Encrypt prefers AAAA and connects to it; a proxied CF IPv6
   answers successfully with the wrong content, and there is **no A-record
   fallback**. This alone explains `bad_authz` surviving both fires, and it also
   explains why the ACME preflight probe passes (it hits CF either way).

`2a06:98c1::/32` is Cloudflare space, which is consistent with **either** case —
so the observation does not discriminate. Only the CF API does.

**Discriminator (Phase 0.1, read-only, no fire):** `GET /zones/{id}/dns_records?type=AAAA`.

### H-W1 / H-W2 / H-W3 — UNKNOWN, only reachable after H-W4 is ruled out

- **H-W1 — public-DNS propagation lag.** The flip may not reach public resolvers
  before the cert poll begins. #6698 records public DNS returning `188.114.x`
  around the window. **Discriminator:** the propagation gate's per-attempt marker.
- **H-W2 — window too short.** 14 min may be less than GitHub needs.
  **Discriminator:** per-poll-tick markers showing the cert-state trajectory
  (flat `bad_authz` vs. advancing through intermediate states then timing out).
- **H-W3 — Let's Encrypt failed-validation rate limiting.** Repeated same-day
  attempts — including the earlier permission-403 fires, which still toggled the
  cname — may have tripped LE's failed-validation limit (5 per account per
  hostname per hour, compounding on repeated failure). If so **no window length
  helps**, and `GET /pages` returns the same string either way, so the poll
  cannot see it. **Discriminator:** cert stays `bad_authz` *while* the
  propagation gate proves the DNS-only state was correct — plus a multi-hour
  cooling-off before the remediation fire.

## User-Brand Impact

**If this lands broken, the user experiences:** `https://soleur.ai` — the public
marketing site and the operator's own brand surface — serving a browser TLS
interstitial. During the DNS-only window the apex and www serve **GitHub's
`bad_authz` certificate**, so every HTTPS visitor gets a full-page security
warning, and Cloudflare's Always-Use-HTTPS, WAF, and bot management are bypassed
on those hostnames. This is a user-visible outage that scales **linearly with
window length** — which is why this plan does not lengthen the window.

**If this leaks, the user's infrastructure is exposed via:** *no origin
disclosure occurs.* The toggled records are GitHub Pages public anycast
(`185.199.x`) and a CNAME to `jikig-ai.github.io`. The Hetzner origin sits behind
`cloudflare_record.app`, which this routine never touches. The residual exposure
is the loss of edge protections on the two public marketing hostnames for the
duration of the window.

**Brand-survival threshold:** single-user incident.

`requires_cpo_signoff: true` — CPO sign-off is required at plan time before
`/work` begins. `user-impact-reviewer` is invoked at review time per
`plugins/soleur/skills/review/SKILL.md`.

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-gh-pages-cert-reissue.ts`
  — marker emission per phase; probe-only mode; propagation gate; **restore
  fall-through restructure** (highest-risk edit, see Phase 2.3).
- `apps/web-platform/test/server/inngest/cron-gh-pages-cert-reissue.test.ts`
  — 610 lines today; extend. Matches vitest's node-project glob
  `test/**/*.test.ts` (`apps/web-platform/vitest.config.ts:44`) — confirmed.
- `scripts/sweep-followthroughs.sh` — bounded reopen path for closed issues.
- `knowledge-base/engineering/architecture/decisions/ADR-125-gh-pages-cert-reissue-cf-proxy-toggle.md`
  — conditional amendment (see Architecture Decision).

## Files to Create

- `apps/web-platform/server/cert-reissue-marker.ts` — dedicated pino-WARN marker
  module mirroring `claude-cost-marker.ts`, including its no-PII boundary comment.
- `apps/web-platform/test/server/cert-reissue-marker.test.ts` — marker shape +
  level assertions.

## Open Code-Review Overlap

None. Checked all 61 open `code-review` issues against every path above
(`cron-gh-pages-cert-reissue.ts`, `sweep-followthroughs.sh`,
`gh-pages-cert-reissue-6657.sh`, `scheduled-followthrough-sweeper.yml`) — zero
matches.

## Implementation Phases

### Phase 0 — Preconditions (no code; 0.1 gates everything)

**0.1 — BLOCKING: resolve H-W4 before writing any code.** Read-only:

```bash
doppler run -p soleur -c prd_terraform -- bash -c '
  curl -s -H "Authorization: Bearer $CF_API_TOKEN_DNS_EDIT" \
    "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?type=AAAA" \
  | jq "[.result[] | {name, content, proxied}]"'
```

- **Returns AAAA records for `soleur.ai` / `www.soleur.ai`** → H-W4 is the root
  cause. **Stop and re-scope.** The remedy is a Terraform ownership decision
  (declare-and-delete, or add AAAA to the toggle set) — a drift/IaC question, not
  an Inngest question — plus an ADR-125 amendment on toggle-set completeness.
  Telemetry (Phase 1) still ships; the propagation gate becomes secondary.
- **Returns none** → the AAAA is Cloudflare's synthetic proxy answer. H-W4 is
  refuted; proceed to Phases 1–3 as written. Record the output in the plan.

**0.2** Verify the exact `Resolver`/`setServers` API against the installed Node
(no in-repo precedent):
`node -e "const {Resolver}=require('node:dns/promises'); const r=new Resolver(); r.setServers(['1.1.1.1']); console.log(typeof r.resolve4, typeof r.resolve6)"`.
If `Resolver` is not on the promises export, fall back to `node:dns`'s `Resolver`.
Pin the verified form before coding.

**0.3** Re-read `apps/web-platform/infra/vector.toml`
`[transforms.app_container_warn_filter]` and confirm `level_int >= 40` is
unchanged on `origin/main`.

**0.4** Confirm the discriminator is unused: `git grep -c SOLEUR_CERT_REISSUE` → 0.

### Phase 1 — Telemetry

1.1 Create `server/cert-reissue-marker.ts`. Mirror `claude-cost-marker.ts`:
a dedicated `pino({ base: { component: "cert-reissue" } })` instance with **no**
`hooks.logMethod` Sentry mirror, emitting
`log.warn({ SOLEUR_CERT_REISSUE: true, ...m }, "cert reissue")` inside a
fail-open `try/catch`. The dedicated instance is load-bearing: `logger.ts`
installs a `hooks.logMethod` that mirrors every WARN+ into a Sentry breadcrumb,
and ~15 per-poll-tick WARNs per fire would evict genuine diagnostics from the
shared-scope ring buffer. Carry forward the `‼️ BOUNDARY` comment — this instance
has no `formatters.log` PII rename and no `redact` paths, so the marker interface
must carry no user id, email, or secret. This marker carries only phase, cert
state, record counts, resolver answers, booleans, and durations.

1.2 Define a closed `phase` union so every marker is greppable by phase and the
type is the enforcement surface:
`"preflight" | "pre-flip-dns" | "flip-dns-only" | "cname-put-null" | "cname-put-set" | "dns-propagation" | "poll" | "restore" | "terminal"`.

`pre-flip-dns` is required: **without a marker of the DNS state *before* the
flip, propagation-delay is indistinguishable from never-propagated.**

1.3 Include an `attempt` / `pollIndex` field on every marker. Without it, a
duplicate is ambiguous between a legitimate step retry and a replay artifact, and
the first fire is only half-diagnostic.

1.4 **Placement rules (correctness, not style):**

- **Inside a `step.run` callback** — memoized steps do not re-execute their
  callback, so the marker fires exactly once per real execution. A step *retry*
  re-emits, which is correct (each real attempt is a real event). This is the
  required placement for `pre-flip-dns`, `flip-dns-only`, both cname-PUT markers,
  `dns-propagation`, `poll`, and `restore`.
- **In the orchestrating body between steps** — re-executes on *every* resume.
  With `MAX_POLLS = 15` that is ~15 duplicate emissions with identical content.
  **Avoid.**
- `emitTerminal` via `emitAndReturn` is body-level but only reachable on the
  final pass, so it stays once-per-run. **Leave as is.**

1.5 The `poll-${i}` step currently returns only `deps.getPages()`. Emit the
observed cert state **inside that callback**; do not hoist the result to the body
to log it there (that would land in the duplicate-prone case).

1.6 Keep existing `emitTerminal` / `reportSilentFallback` behavior intact — the
marker is additive. The Sentry mirror and the `gh-pages-cert-reissue-failed`
issue-alert must keep firing on the same `feature` tag.

### Phase 2 — Probe-only mode + DNS-propagation gate

2.1 **Probe-only mode.** Add a `probeOnly` flag on the event payload, **defaulting
to probe-only for manual fires**. In this mode the routine flips DNS to DNS-only,
runs the propagation gate and the ACME probe, emits markers, and restores —
**skipping the cname toggle entirely.** This measures propagation without
consuming a Let's Encrypt validation attempt and without deepening any existing
rate-limit state. This is what makes the first post-deploy fire diagnostic rather
than another blind attempt.

2.2 **The gate.** Add `assertPublicDnsPropagated(deps)` to the injectable
`ReissueDeps` surface so it is testable without a network, like every other IO in
this file. It must return a structured verdict combining:

- **Resolver check** — `Resolver` with `setServers(["1.1.1.1","8.8.8.8"])`;
  `resolve4` must return only addresses in `185.199.0.0/16`.
- **AAAA check** — `resolve6` must yield `ENODATA`. This is the in-flight
  detector for H-W4.
- **ACME HTTP-01 shaped probe** — re-run the existing `probeAcme` shape
  (`GET http://soleur.ai/.well-known/acme-challenge/<random>`) **post-flip** and
  assert the response signature is GitHub's, not Cloudflare's. `gatherPreconditions`
  already runs this probe, but at *preflight* time while records are still
  proxied, so it hits CF and says nothing about the DNS-only state. Re-running it
  post-flip is nearly free and is the strongest available proxy for what LE will
  actually see. Resolver answers alone test two resolvers' caches, not LE's.

2.3 **Placement and the restore trap (highest-risk edit).** Insert the gate as
its own `step.run` between `toggle-reissue` and the poll loop, with a bounded
`step.sleep` retry loop using **fixed-count** step names (`dns-gate-${i}` /
`dns-gate-wait-${i}`) over a constant — never a while-loop with a wall-clock-derived
counter, which would produce non-deterministic step names across replays and is
the one way to break replay-safety here.

**The trap:** `restore-steady-state` is an unconditional *body* step reached only
by falling through. The existing early `return emitAndReturn(...)` paths
(`not_stuck`, `precondition_blocked`) are safe **only because they precede the
toggle**. If the gate fails and you follow that same pattern with an early
return, you **skip the restore step and leave the zone DNS-only** — and
`onFailure` runs only when the body throws or retries exhaust, **not** on a clean
early return. A clean early return after the toggle leaves the public site
serving a broken cert indefinitely.

Therefore the gate must (a) never throw, (b) return a discriminated result, and
(c) on failure fall **through** to `restore-steady-state`, with the new terminal
outcome emitted *after* restore. This requires restructuring the tail of
`runReissueSteps` so restore precedes **all** post-toggle terminal returns.
A test must assert `restore-steady-state` runs on the `dns_propagation_failed`
path.

2.4 Extend `ReissueOutcome` with `dns_propagation_failed`. It is **not** benign —
it must page. Per `cq-union-widening-grep-three-patterns`, sweep every consumer:
`BENIGN_OUTCOMES`, `emitTerminal`, the test suite, and any Sentry alert keyed on
`outcome`. Run `tsc --noEmit` and treat each `not assignable to never` as the
canonical enumeration of rails to widen.

2.5 **Do not lengthen the window.** The propagation budget comes **out of** the
existing `POLL_MAX_MS`; the total DNS-only window stays at **15 minutes**.
Lengthening is only defensible against a *measured* propagation time from a
probe-only fire, and even then 30 minutes is the ceiling for a public site
serving broken TLS; beyond that needs an operator-gated maintenance window.

2.6 Add a comment (or broadened assertion) at `EXPECTED_TOGGLE_RECORDS = 5`:
the count asserts the toggle set matches `dns.tf`, but provides **no** protection
against record *types* that were never in `dns.tf` — which is precisely how the
AAAA gap evaded it.

### Phase 3 — Follow-through sweeper reopen path

3.1 In `scripts/sweep-followthroughs.sh`, add a **separate, recency-bounded**
query for closed `follow-through` issues —
`--state closed --search "closed:>=<date>"` with its own `--limit`. Do **not**
widen the existing `--state open --limit 50` call to `--state all`; that would
silently starve the open set.

3.2 Fetch `stateReason` in the `--json` field list and **exclude
`NOT_PLANNED`** — wontfix closures are deliberate. Only `COMPLETED` closures are
candidates for "closed prematurely."

3.3 On script exit **1 (FAIL)**, `gh issue reopen` and comment with the output.
Exit **2 (TRANSIENT)** takes **no action** — and suppress the comment path too,
or a flaky verifier comments on closed issues forever. Exit **0 (PASS)** leaves
it closed.

3.4 Bound the loop: honor a `soleur:followthrough-nosweep` opt-out marker, or a
reopen counter that gives up after N. Otherwise a genuinely-FAIL issue that a
human keeps closing is reopened every sweep.

3.5 This is deliberately **actor-agnostic** — it catches a premature close from
the sweeper, a `Closes #N`, the operator, or an agent session, which is what
actually happened to #6657. A guard blocking only one actor would have missed it.

3.6 Reopen #6657, or record explicitly that #6698 supersedes it as the live
tracker, so the cert recovery is tracked by something that is actually open.

### Phase 4 — ADR-125 (conditional) and C4

4.1 **If Phase 0.1 finds real AAAA records**, amend ADR-125 `## Decision` and
`## Consequences`: its atomicity claim assumes the 5-record set is the whole
exposure surface, which would be false. **If Phase 0.1 finds none**, the
propagation gate and probe-only mode operate *inside* ADR-125/ADR-077 as written;
amend `## Decision` only to record the new step in the sequence and the
`dns_propagation_failed` outcome.

4.2 **C4 completeness check.** Read all three of
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` in
full — not a keyword grep — and enumerate this change's external actors and
systems: Let's Encrypt / ACME, GitHub Pages, Cloudflare DNS, the public recursive
resolvers (1.1.1.1 / 8.8.8.8), Better Stack. Confirm each is already modeled, or
add the element + `#external` tag + relationship edges + the `view … include`
line so it renders. Cite the enumeration; an unsupported "no C4 impact" is a
reject condition. Run `apps/web-platform/test/c4-code-syntax.test.ts` and
`c4-render.test.ts` after any `.c4` edit.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** Phase 0.1's CF AAAA query output is recorded verbatim in the PR body,
  with the branch taken (H-W4 confirmed → re-scope, or refuted → proceed).
- **AC2** The marker emits at `log.warn` (not `info`), asserted by a unit test
  capturing the pino level and requiring `level >= 40`.
- **AC3** No marker is emitted through the injected Inngest ctx `logger`: assert
  zero `logger.info(` additions in the `cron-gh-pages-cert-reissue.ts` diff.
- **AC4** Every `phase` union member has ≥ 1 emit site — asserted by driving
  `runReissueSteps` with a fake step + fake deps and comparing the observed phase
  set against the exported union (not a grep count).
- **AC5** Every marker carries an `attempt`/`pollIndex` field (type-level).
- **AC6** No marker is emitted from the orchestrating body except `emitTerminal`:
  assert emitted-marker counts from the fake step across a simulated multi-resume
  run stay once-per-real-execution.
- **AC7** The marker payload type contains no user id, email, or secret field
  (type-level assertion mirroring `claude-cost-marker.ts`'s boundary contract).
- **AC8** `assertPublicDnsPropagated` is reachable through `ReissueDeps` and is
  driven by fakes covering: all-`185.199.x` + ACME probe GitHub-shaped (pass);
  Cloudflare answers (retry); AAAA present (fail, H-W4); budget exhaustion
  (`dns_propagation_failed`).
- **AC9** **Restore fall-through:** a test asserts `restore-steady-state` runs on
  the `dns_propagation_failed` path, and that no post-toggle terminal return
  bypasses restore.
- **AC10** Step ordering: the gate never runs before the toggle nor after the
  poll — asserted from the fake step's recorded call sequence. Gate step names are
  fixed-count and identical across a simulated replay.
- **AC11** `probeOnly` mode performs the flip + gate + restore and makes **zero**
  `setPagesCname` calls — asserted against the fake deps.
- **AC12** `ReissueOutcome` widening swept: `tsc --noEmit` clean;
  `dns_propagation_failed` explicitly **not** in `BENIGN_OUTCOMES`.
- **AC13** The total maximum DNS-only window is asserted against the exported
  constants and **equals 15 minutes** (unchanged), matching ADR-125.
- **AC14** `scripts/sweep-followthroughs.sh`: reopens on exit 1; no action and no
  comment on exit 2; skips `NOT_PLANNED`; honors the reopen bound; the open-issue
  query's limit is unchanged. Asserted by the script's `.test.sh` harness (locate
  at /work; add one if absent).
- **AC15** `bash -n scripts/sweep-followthroughs.sh` clean. No change to
  `.github/workflows/scheduled-followthrough-sweeper.yml` is required (no new
  `secrets=`); if it does change, `actionlint` it.
- **AC16** Restore behavior unregressed: existing tests for `restoreState`
  fail-loud (`EXPECTED_TOGGLE_RECORDS`), the unconditional final restore step,
  and the `onFailure` handler all still pass.
- **AC17** ADR-125 amended per Phase 4.1; C4 enumeration recorded per Phase 4.2;
  `c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
- **AC18** PR body uses **`Ref #6698`**, not `Closes #6698` — the live
  remediation is post-merge, so an auto-close at merge would recreate exactly the
  false-resolved state this plan fixes.

### Post-merge (fully automated — no operator step)

- **AC19** Deploy lands and restarts the container (this also clears the
  `tokenCache` in `server/github-app.ts`, which otherwise serves a stale
  pre-grant token for ~45 min).
- **AC20** **Fire 1 — probe-only** (consumes no LE validation attempt):

  ```bash
  SECRET=$(doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET -p soleur -c prd --plain)
  curl -s -X POST https://app.soleur.ai/api/internal/trigger-cron \
    -H "Authorization: Bearer $SECRET" -H "Content-Type: application/json" \
    -d '{"event":"cron/gh-pages-cert-reissue.manual-trigger"}'
  ```

- **AC21** **Discoverability test (no SSH, no dashboard).** Within 20 min of the
  fire, markers for every phase are readable:

  ```bash
  doppler run -p soleur -c prd_terraform -- \
    bash scripts/betterstack-query.sh --since 30m --grep '"SOLEUR_CERT_REISSUE":true'
  ```

  Expected: ≥ 1 row per `phase` value, each carrying `source_kind=app_container`.
  **Field-isolate the discriminator** — grep the structured form
  `"SOLEUR_CERT_REISSUE":true`, never the bare token. `--grep` compiles to an
  unanchored `raw LIKE '%…%'` over a source every host multiplexes into, and
  inngest ships GitHub-webhook payloads (issue/PR bodies — including this plan and
  this tracker) to the same source, so a bare-substring grep self-contaminates.
  See `2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md`.

- **AC22** **Verdict rule (deterministic, from markers alone).**
  - `pre-flip-dns` shows CF answers and `dns-propagation` reaches all-`185.199.x`
    with `ENODATA` on AAAA and a GitHub-shaped ACME response → **H-W1 and H-W4
    refuted**; the DNS-only state is correct. Proceed to AC23.
  - `dns-propagation` never reaches `185.199.x` within budget → **H-W1 confirmed**;
    the gate did its job. Fix propagation (or budget) before any remediation fire.
  - AAAA observed → **H-W4 confirmed**; remediate the zone drift in Terraform.
    Do **not** fire remediation until it is gone.
- **AC23** **Fire 2 — remediation**, only after AC22's first branch, and only
  after a **multi-hour cooling-off** for H-W3 (LE failed-validation windows are
  hourly; the cert does not expire until 2026-08-16, so the wait is cheap
  insurance). Then watch up to ~15 min:
  `gh api /repos/jikig-ai/soleur/pages --jq '.https_certificate.state'` must reach
  `issued`/`approved`. If propagation is proven good and the cert still stays
  `bad_authz`, **H-W3 is the remaining hypothesis** — the next action is backoff,
  not a longer window.
- **AC24** After every fire, re-assert steady state: apex + www both
  `proxied=true`, `cname=soleur.ai`.
- **AC25** Only once the cert reaches `issued`/`approved`: restore
  `https_enforced` via `PUT /repos/jikig-ai/soleur/pages` with
  `{cname:"soleur.ai", https_enforced:true}` using a both-permissions token
  (GitHub rejects `true` while the cert is unissued).

## Observability

```yaml
liveness_signal:
  what: SOLEUR_CERT_REISSUE marker rows, one per phase per run, with attempt/pollIndex
  cadence: per manual-trigger fire (v1 is manual-trigger only)
  alert_target: existing gh-pages-cert-reissue-failed Sentry issue-alert on the `feature` tag
  configured_in: apps/web-platform/infra/vector.toml + apps/web-platform/infra/sentry/
error_reporting:
  destination: Sentry via reportSilentFallback (unchanged) + pino WARN marker to Better Stack
  fail_loud: true — every non-benign terminal mirrors to Sentry; dns_propagation_failed is explicitly NOT in BENIGN_OUTCOMES
failure_modes:
  - mode: undeclared AAAA in the live zone defeats validation (H-W4)
    detection: propagation gate requires ENODATA on resolve6 and names the AAAA
    alert_route: dns_propagation_failed terminal → Sentry
  - mode: DNS-only flip never propagates to public resolvers (H-W1)
    detection: pre-flip-dns + dns-propagation markers carry the observed resolver answers
    alert_route: dns_propagation_failed terminal → Sentry
  - mode: cert never validates despite correct DNS-only state (H-W2 / H-W3)
    detection: per-poll-tick markers carrying the observed cert-state trajectory
    alert_route: poll_timeout terminal → Sentry
  - mode: a post-toggle terminal return skips restore, leaving the public site on a broken cert
    detection: restore fall-through test (AC9) + existing restore-assert convergence re-read + onFailure
    alert_route: proxy_restore_failed → Sentry (unchanged)
  - mode: a follow-through tracker is prematurely closed while unrecovered
    detection: sweeper now evaluates recently-closed COMPLETED follow-through issues
    alert_route: automatic gh issue reopen + comment
logs:
  where: Better Stack source soleur-inngest-vector-prd (id 2457081), source_kind=app_container
  retention: ~40-min hot window via remote(_logs); older rows from the s3 archive via betterstack-query.sh's default UNION ALL
discoverability_test:
  command: doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 30m --grep '"SOLEUR_CERT_REISSUE":true'
  expected_output: at least one row per phase value, each carrying source_kind=app_container
```

### Soak Follow-Through Enrollment

The cert recovery is post-deploy and time-gated, so it must be enrolled rather
than remembered. The existing probe
`scripts/followthroughs/gh-pages-cert-reissue-6657.sh` already encodes the
correct predicate and needs **no change** — reuse it. Point the #6698 tracker's
`<!-- soleur:followthrough script=… earliest=… secrets=GH_TOKEN -->` directive at
it, label the tracker `follow-through`, and set `earliest` to deploy + the agreed
soak. No new `secrets=` are required, so
`.github/workflows/scheduled-followthrough-sweeper.yml` does not change.

## Infrastructure (IaC)

No new infrastructure **unless Phase 0.1 confirms H-W4**, in which case the AAAA
records become a Terraform ownership question (declare-and-delete, or add to the
toggle set) handled as drift remediation in `apps/web-platform/infra/dns.tf`
under the existing auto-applied root — and that work is scoped by Phase 0.1's
re-scope branch, not assumed here.

Otherwise this plan edits application code, a repo script, an ADR, and tests
against already-provisioned surfaces. No new server, secret, vendor, DNS record,
or persistent runtime process. The DNS records it manipulates are already
declared in `dns.tf`; the routine only transiently toggles their `proxied` flag
(the documented AP-019 / ADR-125 off-Terraform exception, unchanged).

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-125** (`status: accepted`); do not author a new one. The decision
(transient CF-proxy toggle to re-order the cert) stands. What changes is the step
sequence (probe-only mode, propagation gate), the `dns_propagation_failed`
outcome, and — **conditionally on Phase 0.1** — the toggle-set completeness
claim. No new ordinal is claimed, so there is no ADR-ordinal collision risk.

### C4 views

To be completed per Phase 4.2 with the full three-file enumeration. This plan
does **not** assert "no C4 impact": the propagation gate introduces public
recursive resolvers (1.1.1.1 / 8.8.8.8) as a new external dependency of the
remediation path, a candidate `#external` element if not already modeled.

### Sequencing

The ADR amendment ships in this PR, not a follow-up.

## Domain Review

**Domains relevant:** Engineering (CTO), Operations

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Folded throughout. The four material findings: (1) live AAAA
records exist on apex and www and are in no Terraform file — a likely root cause
that a free read-only CF call resolves, now Phase 0.1 and blocking; (2) the
security framing was wrong — the toggled records are GitHub public anycast, not
the Hetzner origin, and the real cost is a *public TLS outage* that argues for
keeping the window at 15 min rather than lengthening it; (3) a post-toggle early
return would skip `restore-steady-state` (and `onFailure` does not fire on a
clean return), leaving the public site on a broken cert — the tail of
`runReissueSteps` must be restructured so restore precedes all post-toggle
terminal returns; (4) as originally scoped the first fire would still not be
diagnostic, because three hypotheses are live and the poll distinguishes none —
hence probe-only mode. Marker placement inside `step.run` vs. the body is a
correctness question, not style. No new ADR required; ADR-125 amendment
conditional on (1).

### Operations

**Status:** reviewed
**Assessment:** The operational failure this plan fixes is not the cert but the
*closure of its tracker while unrecovered* — an automation-trust regression.
Phase 3's actor-agnostic reopen path is the durable fix; the existing sweeper
convention and secrets wiring are unchanged. The reopen path needs the four
bounds in Phase 3 (recency-bounded separate query, `NOT_PLANNED` exclusion,
TRANSIENT no-op including comments, reopen cap) or it becomes a flapping loop.

### Product/UX Gate

Not applicable. No file in `## Files to Edit` or `## Files to Create` matches a
UI surface (`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`), so
the mechanical UI-surface override does not fire and the semantic sweep is NONE.

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| **H-W4 is the real root cause and this plan fixes the wrong thing** | Phase 0.1 is blocking, free, and read-only; it runs before any code is written and has an explicit re-scope branch |
| **A post-toggle early return skips restore, leaving the public site on a broken cert** | Phase 2.3 restructures the tail so restore precedes all post-toggle terminal returns; AC9 asserts it on the `dns_propagation_failed` path |
| The first fire burns an LE validation attempt and deepens rate limiting | Probe-only mode (Phase 2.1) is the default for manual fires and makes zero `setPagesCname` calls (AC11); AC23 requires a multi-hour cooling-off before remediation |
| Body-level markers duplicate ~15× per run and obscure the timeline | Placement rules in Phase 1.4; AC6 asserts once-per-real-execution across a simulated multi-resume run |
| A duplicate marker is ambiguous between retry and replay | `attempt`/`pollIndex` on every marker (AC5) |
| Propagation-delay is indistinguishable from never-propagated | `pre-flip-dns` marker (Phase 1.2) captures the pre-flip baseline |
| Resolver answers test resolver caches, not what LE sees | Paired with a post-flip ACME HTTP-01 shaped probe (Phase 2.2) |
| Lengthening the window lengthens a public TLS outage | Window stays at 15 min; the gate's budget comes out of `POLL_MAX_MS` (Phase 2.5, AC13) |
| Non-deterministic gate step names break replay-safety | Fixed-count step names over a constant, never a wall-clock counter (Phase 2.3, AC10) |
| `Resolver`/`setServers` has no in-repo precedent | Phase 0.2 verifies the exact API against the installed Node before coding |
| The unanchored `--grep` self-contaminates from webhook-shipped issue bodies | AC21 field-isolates on `"SOLEUR_CERT_REISSUE":true` |
| The marker's dedicated pino instance has no PII redaction | AC7 type-level boundary assertion; payload is infra facts only |
| ~15 WARN markers/fire evict Sentry breadcrumbs | Dedicated pino instance with no `hooks.logMethod` mirror (Phase 1.1) |
| The sweeper reopen path flaps on a deliberately-closed issue | `NOT_PLANNED` exclusion + reopen cap / opt-out marker + TRANSIENT no-op (Phase 3.2–3.4, AC14) |

## Alternative Approaches Considered

| Alternative | Why not |
| --- | --- |
| Only lengthen `POLL_MAX_MS` | Directly lengthens a public TLS outage, discriminates no hypothesis, and is useless under H-W3 or H-W4. A poll that starts before propagation is wasted regardless of length |
| Fire remediation immediately post-deploy | Consumes an LE validation attempt and, if it fails, still cannot separate H-W1/H-W2/H-W3 — another blind attempt with better logs attached |
| Shell out to `dig @1.1.1.1` | `dig` is not installed in the image (verified); would throw at runtime |
| Resolver check alone, without the ACME probe | Tests two resolvers' caches, not what Let's Encrypt will see |
| Emit markers via `console.log` | Non-JSON lines do survive the Vector filter, but the repo convention is structured pino WARN with a boolean discriminator — greppable, typed, and already proven in `claude-cost-marker.ts` |
| Emit markers via the injected Inngest ctx `logger` | Two independent gates (ProxyLogger `enabled`, Vector level ≥ 40) must both hold, and neither is asserted by any test. This is the exact defect being fixed |
| Fix the sweeper's script predicate | The predicate is already correct — see Research Reconciliation |
| Block `gh issue close` on `follow-through` issues via a PreToolUse hook | Actor-specific and bypassable; the sweeper reopen path catches every actor. Worth adding later as defense-in-depth, not as the primary fix |
| Set the Inngest client's `logger` to the shared pino instance | Broader blast radius across every cron, and ProxyLogger gating (H-T1) would still swallow calls outside an executing step. Deferred to its own issue |

## Deferred / Tracking

Each needs a GitHub issue filed at /work time with re-evaluation criteria:

- A PreToolUse hook blocking `gh issue close` on `follow-through`-labelled issues
  whose verification script does not pass — defense-in-depth for Phase 3.
- Wiring the Inngest client's `logger` option to the shared pino instance so ctx
  `logger` calls are not silently swallowed fleet-wide — affects every cron.
- Broadening `EXPECTED_TOGGLE_RECORDS` from a count to a type-aware assertion, so
  a record *type* absent from `dns.tf` cannot evade the toggle set again
  (Phase 2.6 adds the comment; the assertion is the follow-up).
- v2 self-heal auto-invoke + drift/apply freeze-lock, already deferred by ADR-125
  (CTO ruling 2026-07-18) — unchanged by this plan, relisted for visibility.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. Fill it before requesting deepen-plan or `/work`.
- The ADR-125 amendment's shape is **conditional on Phase 0.1**. Do not write it
  before that query runs.
- Phase 0.1 is not a formality. If it returns AAAA records, Phases 2 and 4 change
  shape and the remediation fire must not run until the zone drift is fixed.
