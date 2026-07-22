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

Ref #6698. Ref #6657. Amends ADR-125 (see Architecture Decision).

## Enhancement Summary

**Deepened on:** 2026-07-19
**Agents:** CTO, architecture-strategist, spec-flow-analyzer,
observability-coverage-reviewer, framework-docs-researcher (inngest 3.54.2),
best-practices-researcher (ACME/LE), learnings-researcher.

### Key improvements

1. **A likely root cause surfaced that the issue never named.** Apex and www both
   return AAAA records; `dns.tf` declares none and the routine touches none. Per
   RI-1, Let's Encrypt **prefers IPv6 with almost no IPv4 fallback**, so a proxied
   AAAA surviving the flip explains `bad_authz` at *any* window length. A free
   read-only Cloudflare call (Phase 0.1) now blocks all other work.
2. **The plan's own headline fix would not have worked.** `emitTerminal` routes
   benign outcomes through `logger.info` (`:694`), so `issued` — the success path
   the plan exists to illuminate — would have stayed dark. Phase 1.5 now mandates
   a marker emit inside `emitTerminal`, and AC3 asserts the invariant rather than
   a diff shape.
3. **The restore invariant was stated wrongly and would have caused a
   regression.** "Restore must precede all post-toggle returns" would have added a
   second restore to the already-safe `reissue_failed` path, where a throw would
   overwrite the diagnostic outcome. Corrected, and made *structural* (exactly one
   post-toggle return site) rather than test-enforced.
4. **Phase 3 would not have caught its own motivating case.** The `earliest` gate
   (`:178-185`) would have skipped #6657 before its soak elapsed. The closed-issue
   path now bypasses it, with a regression fixture in #6657's exact shape.
5. **The security framing was inverted.** The toggled records are GitHub public
   anycast, not the Hetzner origin — there is no origin disclosure. The real cost
   is a *public TLS outage* on the marketing site, which argues for keeping the
   window at 15 min rather than lengthening it.
6. **Probe-only mode** added so the first post-deploy fire is diagnostic and
   consumes no Let's Encrypt validation attempt (RI-4: limits are hourly and
   compounding).

### New considerations discovered

- The `pii_scrub_*` stages **delete** eight top-level key names; a marker field so
  named silently never ships (AC7).
- No `vector.toml` change is needed — Source 3 keys on `CONTAINER_NAME`, not the
  `SYSLOG_IDENTIFIER` allowlist (verified live).
- `REISSUE_ALLOWED_STATES` misses two documented failure states and contains one
  undocumented one (RI-3).
- **H-W2 and H-W3 remain non-separable** by anything this plan adds; recorded
  honestly in RI-7 and in `failure_modes` rather than overclaimed.
- A "CAA record is required" research claim was **rejected** — RFC 8659 makes an
  empty RRset permissive, and the existing check is correct (RI-5).

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
> (keeps pino `level >= 40` **only**) → `[transforms.pii_scrub_drop_userdata]`
> → `[transforms.pii_scrub_structured]` → `[transforms.pii_scrub_string]`
> → `[transforms.tag_journald]` (adds `source_kind=app_container`, `host_name`)
> → `[sinks.betterstack]` (HTTP POST, `BETTERSTACK_LOGS_TOKEN`) → Better Stack
> source `soleur-inngest-vector-prd` (id 2457081, team 520508) → read back via
> `scripts/betterstack-query.sh` (ClickHouse HTTP, `raw LIKE '%…%'`).

**Two consequences of the `pii_scrub_*` stages, both load-bearing:**

1. **`[transforms.pii_scrub_drop_userdata]` DELETES top-level keys** named
   `body`, `content`, `message`, `userMessage`, `prompt`, `chat_message`,
   `userInput`, `user_input` (`vector.toml:246-253`). A marker field with any of
   those names is **silently dropped before reaching Better Stack**. The marker
   interface must avoid all eight names — enforced by AC7.
2. **Source 3 keys on `CONTAINER_NAME`, not `SYSLOG_IDENTIFIER`**
   (`include_matches.CONTAINER_NAME = ["soleur-web-platform"]`). The exact-match
   `SYSLOG_IDENTIFIER` allowlist documented in
   `2026-07-08-inngest-cutover-authoring-review-and-observability-allowlist.md`
   applies **only to Source 4** (`host_scripts_journald`, for `logger -t <tag>`
   host scripts). A pino marker from the app container is captured by the
   emitting container's identity and is unfiltered by identifier, so **no
   `vector.toml` change is required** and none is listed in Files to Edit. This
   was verified live against a real `SOLEUR_CLAUDE_COST` row whose
   `SYSLOG_IDENTIFIER` is an ephemeral Docker container id present in no
   allowlist — and which ships anyway.

**Verified live:** Better Stack stores `message` as a *parsed JSON object*, so
the marker key is a genuine nested JSON key in the `raw` column serialized as
`"SOLEUR_CLAUDE_COST":true` (no space, no backslash escaping — the escaping seen
on stdout is the JSONEachRow envelope). Server-side `--grep` compiles to
`raw LIKE '%…%'` against that unescaped column (`betterstack-query.sh:179-186`),
so the plan's `--grep '"SOLEUR_CERT_REISSUE":true'` works as written. A
*client-side* post-filter over stdout would instead need the escaped form
`\"SOLEUR_CERT_REISSUE\":true` — relevant only if this ever becomes an
auto-closing follow-through probe.

All verification pulls from that chain directly
(`hr-no-dashboard-eyeball-pull-data-yourself`); no step opens a dashboard and no
step uses SSH (`hr-no-ssh-fallback-in-runbooks`).

## Hypotheses

Per the Sharp Edge on hypothesis tables: **no verdict below reads CONFIRMED for
anything whose discriminator is currently invisible.** The H-W family is UNKNOWN
— that is precisely what this change exists to resolve.

H-T is CONFIRMED, with one precision worth stating: the Vector config **is**
in-repo and was read directly, but the inngest SDK source is **not** — it is
gitignored `node_modules`, and the `ProxyLogger.enabled` gate was verified on
disk against pinned 3.54.2 (`middleware/logger.js:29,38,53`). More importantly,
**H-T2 alone is sufficient**: the Vector filter proves pino INFO cannot reach
Better Stack regardless of anything the SDK does. So the verdict does not depend
on the `node_modules` read and stays true across an inngest version bump.

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

## Research Insights — ACME / Let's Encrypt / GitHub Pages

*(deepen-plan Phase 4. Cited sources; claims verified live where checkable.)*

### RI-1 — Let's Encrypt prefers IPv6 and its IPv4 fallback is severely limited

This **elevates H-W4 from a cheap check to the leading hypothesis.** Per
[LE IPv6 Support](https://letsencrypt.org/docs/ipv6-support/) and
[Challenge Types](https://letsencrypt.org/docs/challenge-types/):

- LE **prefers AAAA** when both families exist.
- It retries over IPv4 **only** if the IPv6 connection fails at the *network*
  level (timeout/refused), and **only on the first request** of an HTTP-01
  validation. **Redirects get no retry.**
- Therefore an AAAA that *answers successfully with the wrong content* — exactly
  what a Cloudflare-proxied AAAA does, returning 200 from CF rather than GitHub —
  produces **no fallback at all**. Validation fails silently.

A proxied AAAA surviving the DNS-only flip is a complete and sufficient
explanation for `bad_authz` persisting across both fires **at any window length**.
**Phase 0.1 stays blocking.**

### RI-2 — the DNS-only window is structurally underbudgeted

- Cloudflare's TTL for proxied records is **fixed at 300 s**, non-editable
  ([CF TTL docs](https://developers.cloudflare.com/dns/manage-dns-records/reference/ttl/)).
  Expect **5–10 min** for recursive resolvers to reflect a proxy-status flip.
- GitHub documents HTTPS availability after a custom-domain change taking **up to
  1 hour** ([Securing Pages with HTTPS](https://docs.github.com/en/pages/getting-started-with-github-pages/securing-your-github-pages-site-with-https)),
  with no SLA for exiting `bad_authz`.

The current ~14-min window therefore spends **a third to two-thirds of itself on
propagation alone**, leaving ~4–9 min for a process documented to take up to an
hour.

**This is a genuine unresolved tension the plan must not paper over:**

| Position | Argument | Source |
| --- | --- | --- |
| **Short window (15 min)** | Availability — apex/www serve a `bad_authz` cert to real visitors for the entire window (see `## Downtime & Cutover`) | CTO assessment |
| **Long window (30–60 min)** | Success probability — GitHub/LE may simply need longer than 15 min *after* propagation completes | RI-2 sources |

**Disposition:** do **not** guess. Probe-only mode (Phase 2.1) measures actual
propagation time at zero validation cost, and that measurement is the input to
the window decision. Ceiling stays **30 min** absent an operator-gated
maintenance window; if measured propagation plus GitHub's observed issuance time
exceeds it, the honest answer is a scheduled maintenance window, not a silently
longer public degradation. Record the outcome in ADR-125.

### RI-3 — the reissue-eligible state allowlist is incomplete

`REISSUE_ALLOWED_STATES = ["bad_authz", "failed"]`
(`cron-gh-pages-cert-reissue.ts:71`). Per the
[Pages REST API docs](https://docs.github.com/en/rest/pages/pages?apiVersion=2022-11-28):

- **in-flight:** `new`, `authorization_created`, `authorization_pending`,
  `uploaded`, `destroy_pending`, `dns_changed`
- **success:** `authorized`, `issued`, `approved`
- **failure:** `errored`, `bad_authz`, `authorization_revoked`

Two gaps: `"failed"` is **not a documented state** (likely dead), while `errored`
and `authorization_revoked` are documented terminal failures the allowlist does
**not** cover — a cert stuck in either is silently declined as `not_stuck`.

**Plan response:** widen to `["bad_authz", "errored", "authorization_revoked"]`
(keeping `"failed"` defensively is acceptable if commented). This is a
**behavior change to the preflight gate**: it needs its own test and a mention in
ADR-125. Separately, treat `authorized` as **progress** in the poll markers — it
discriminates H-W2 ("advancing, just slow") from H-W3 ("flat — LE refusing"),
which no current signal does.

### RI-4 — Let's Encrypt failed-validation rate limits (H-W3)

Per [LE Rate Limits](https://letsencrypt.org/docs/rate-limits/): **5 authorization
failures per identifier per account per hour**, refilling at 1 per 12 min, with a
compounding daily cap; exceeding it pauses issuance until manually unpaused via
LE's self-service portal. Revocation does not reset limits. GitHub surfaces none
of this — the cert simply stays `bad_authz`, indistinguishable from other causes.

This confirms the sequencing: probe-only mode consumes **no** validation attempt,
and AC23's multi-hour cooling-off is the right mitigation. It also means every
blind remediation fire carries a real, compounding cost.

### RI-5 — a claim CONSIDERED AND REJECTED (do not "fix" this)

Research suggested "ensure a CAA record `0 issue \"letsencrypt.org\"` exists —
required for LE to issue." **Incorrect; must not be adopted.** Per RFC 8659 §1.1
an **empty** CAA RRset is permissive — any CA may issue. Verified live this
session: `resolveCaa("soleur.ai")` → `ENODATA`, same for www.

The existing `caaPermissive: inputs.caaCount === 0` check
(`cron-gh-pages-cert-reissue.ts:201`) is therefore **correct as written**.
Recorded here so a future reader does not "fix" correct code into a regression.

### RI-7 — H-W2 and H-W3 are NOT separable by anything this plan adds

An honest statement of the telemetry's limits, so the first fire is not
over-read:

- **H-W4** (AAAA via `resolve6` → `ENODATA`) and **H-W1** (gate never reaches
  `185.199.x`, read against the `pre-flip-dns` baseline) are **cleanly
  discriminated** by the new markers.
- **H-W2 vs H-W3 are not.** Probe-only runs no poll loop, so fire 1 produces
  *zero* H-W2/H-W3 evidence. And on a remediation fire, a flat `bad_authz`
  trajectory is the **identical observable** under both — the plan's own H-W3 text
  concedes `GET /pages` returns the same string either way. "Cert stays
  `bad_authz` while the gate proves DNS was correct, plus a cooling-off" is not a
  discriminator; it is H-W2's observation plus a remedy attempt.

**Cheapest real improvement (adopted in Phase 1.6):** capture the **entire**
`https_certificate` object — `state`, `description`, `domains`, `expires_at` —
plus `protected_domain_state` and `pending_domain_unverified_at` from the same
already-made `GET /pages` call. `description` is the only in-band field that has
ever carried Let's Encrypt-side detail, and an advancing-vs-flat `state`
trajectory is the only other signal available.

**Residual, stated plainly:** if `description` carries nothing useful, H-W2 and
H-W3 are separable only by elimination and by time (backing off and retrying
after an LE rate-limit window). The plan does not claim otherwise, and the
`## Observability` `failure_modes` block records H-W3 as **not detectable by any
declared layer**.

### RI-6 — Phase 0.2 resolved

`Resolver` / `setServers` / `resolve4` / `resolve6` are all available on the
installed Node — verified live this session. Use `node:dns`'s `Resolver` (or the
`node:dns/promises` equivalent if it exposes the same surface) with
`setServers(["1.1.1.1","8.8.8.8"])`. No dependency, no `dig`.

Also verified live: apex and www **both** currently return AAAA
(`2a06:98c1:312x::x`, Cloudflare space) alongside CF A-records — consistent with
*either* the synthetic-proxy case or a real unmanaged record, which is exactly
why Phase 0.1's CF API read is the only discriminator.

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

- **Brand-survival threshold:** single-user incident.

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

**0.2 — RESOLVED this session.** `Resolver` / `setServers` / `resolve4` /
`resolve6` all exist on the installed Node (see RI-6). No further check needed.

**0.3** Re-read `apps/web-platform/infra/vector.toml`
`[transforms.app_container_warn_filter]` and confirm `level_int >= 40` is
unchanged on `origin/main`. **Verified this session** — re-confirm only if the
branch has rebased.

**0.4** Confirm the discriminator is unused **in code**:
`git grep -c SOLEUR_CERT_REISSUE -- apps/ scripts/` → 0. **Scope to `apps/` and
`scripts/` is mandatory** — an unscoped grep already returns non-zero because
this plan and its `tasks.md` quote the literal, and would fail-closed at /work
for an entirely benign reason. (This is the same self-contamination class AC21
guards against on the Better Stack side.)

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

**Field-name constraint (load-bearing):** no marker field may be named `body`,
`content`, `message`, `userMessage`, `prompt`, `chat_message`, `userInput`, or
`user_input` — `[transforms.pii_scrub_drop_userdata]` **deletes** those top-level
keys (`vector.toml:246-253`) and the field would silently never reach Better
Stack. Enforced by AC7.

1.2 Define a closed `phase` union so every marker is greppable by phase and the
type is the enforcement surface:
`"preflight" | "pre-flip-dns" | "flip-dns-only" | "cname-put-null" | "cname-put-set" | "dns-propagation" | "poll" | "restore" | "terminal" | "onfailure-restore"`.

`pre-flip-dns` is required: **without a marker of the DNS state *before* the
flip, propagation-delay is indistinguishable from never-propagated.** It needs
its **own named step** (`capture-pre-flip-dns`) placed *before* `toggle-reissue`.
Emitting it inside `toggle-reissue` is wrong: a step retry would re-read the
"pre-flip" baseline *after* the first flip already happened, producing a
misleading baseline on exactly the retry path that most needs a true one. This
new step changes the sequence AC10 asserts — name it there too.

`onfailure-restore` is required because `cronGhPagesCertReissueOnFailure` is
**not** part of `runReissueSteps`. Without it a body throw reproduces the exact
asymmetry this plan exists to fix: Sentry-visible, marker-dark, and
indistinguishable from "telemetry broken." Emit from **both** branches of that
handler's try/catch.

1.3 **Correlation and attempt fields.** Every marker carries:

- `runId` — **required.** Without it, AC21's `--since 30m` window is satisfied by
  rows from any earlier fire and cannot attribute rows to *this* fire.
- `attempt` — Inngest's zero-indexed retry attempt.
- `pollIndex` — the poll/gate loop index where applicable.
- `probeOnly` — on **every** marker, not just the terminal one, so a row read out
  of context cannot be misread as remediation.

`runId` and `attempt` must be **threaded, not re-derived**: `HandlerArgs`
(`_cron-shared.ts:180+`) already declares `event?`, `attempt?`, `maxAttempts?`,
and `runId?`, but `ReissueHandlerArgs` currently destructures only
`{ step, logger }` and `runReissueSteps(step, deps, logger)` has no parameter to
receive them. Widen both signatures. Per learning
`2026-07-07-pin-spawned-eval-date-to-memoized-runstarted-via-sentinel-inject.md`,
a value a gate keys on must be injected from the parent's already-decided value,
never self-derived — a hardcoded `attempt: 0` would satisfy a type-level
assertion while carrying no information, so AC5 asserts the **value** propagates.

1.4 **Placement rules (correctness, not style)** — verified against pinned
inngest 3.54.2 (`components/execution/v1.js:956-984` memoization;
`:649` body re-execution; `:1113-1114` SHA1 step-id hashing):

- **Inside a `step.run` callback** — a memoized step does not re-execute its
  callback, so the marker fires exactly once per real execution. A step *retry*
  re-emits, which is correct (each real attempt is a real event). Required
  placement for `pre-flip-dns`, `flip-dns-only`, both cname-PUT markers,
  `dns-propagation`, `poll`, and `restore`.
- **In the orchestrating body between steps** — re-executes on **every** resume.
  Measured: with 15 `step.run`+`step.sleep` pairs a body-level statement executes
  **16 times**. **Avoid.** See
  `best-practices/2026-07-02-inngest-side-effect-outside-step-run-duplicates-on-replay.md`.
- Per `2026-06-12-inngest-cron-heartbeat-gate-on-final-attempt-and-step-memoization.md`:
  when gating, **skip the whole `step.run`, not just the side effect inside it** —
  a completed-but-empty step is memoized and replayed, so the gated logic never
  runs on a later attempt.

1.5 **`emitTerminal` MUST gain a marker emit — this is not optional.**
`emitTerminal` currently routes benign outcomes through `logger.info`
(`cron-gh-pages-cert-reissue.ts:694`), and `issued` / `not_stuck` are benign. Under
H-T1 + H-T2 both gates hold, so **without a marker inside `emitTerminal` the
`issued` terminal — the very success path the Overview calls "observationally
dark" — stays dark after this change.** Add the `terminal` marker emit inside
`emitTerminal`, alongside (not replacing) the existing `logger` / Sentry calls.
`emitTerminal` is body-level but reachable only on the final pass, so it remains
once-per-run.

1.6 The `poll-${i}` step currently returns only `deps.getPages()`. Emit the
observed cert state **inside that callback**; do not hoist the result to the body.
Capture the **entire `https_certificate` object** — `state`, `description`,
`domains`, `expires_at` — plus `protected_domain_state` and
`pending_domain_unverified_at` from the same already-made call. `description` is
the only in-band field that has ever carried Let's Encrypt-side detail, and it is
the **only** candidate signal for separating H-W2 from H-W3 (see RI-7).

1.7 **`restore` marker emits twice: on entry and on outcome.** `restoreState` is
fail-loud — it throws on a short read or a failed convergence assert. A marker
emitted only *after* it returns means a throwing restore emits **nothing**, and
"restore never attempted" becomes indistinguishable from "restore attempted and
failed." Emit on entry with the observed record state, and again on outcome,
including from a `catch` that rethrows.

1.8 Keep existing `reportSilentFallback` behavior intact — the marker is additive.
The Sentry mirror and the `gh-pages-cert-reissue-failed` issue-alert must keep
firing on the same `feature` tag.

### Phase 2 — Probe-only mode + DNS-propagation gate

2.1 **Probe-only mode.** Add a `probeOnly` flag read from the event payload. The
routine flips DNS to DNS-only, runs the propagation gate and the ACME probe,
emits markers, and restores — **skipping the cname toggle entirely**, so it
consumes no Let's Encrypt validation attempt and cannot deepen rate-limit state.

**Probe-only MUST also skip the poll loop entirely.** The poll exists to watch a
cert re-order that probe-only deliberately never triggers; running `MAX_POLLS`
would hold apex+www on GitHub's `bad_authz` cert for ~14 minutes for nothing —
the exact public-TLS cost `## User-Brand Impact` uses to refuse lengthening the
window. Probe-only restores as soon as the gate returns a verdict (~1–2 min).

**Default semantics — decided here, not at /work.** The function registers
exactly one trigger (`cron/gh-pages-cert-reissue.manual-trigger`,
`cron-gh-pages-cert-reissue.ts:835`) and v1 is manual-only, so "default for manual
fires" would mean **the sole entry point of a remediation routine no longer
remediates**. That is a footgun by construction. Decision: **absent `data`,
default to `probeOnly: true`** (safe default), and require an **explicit**
`{"probeOnly": false}` to remediate. The trigger route already supports this —
`app/api/internal/trigger-cron/route.ts:100-108` accepts an optional plain-object
`data` and forwards it as `callerData`. Both invocations are spelled out in
AC20/AC23; neither may be left implicit.

2.2 **Outcome and result plumbing for probe-only.** `ReissueOutcome` has no
probe-only member today, so a probe fire would fall out as either `poll_timeout`
(non-benign → a spurious page on a run that succeeded at its actual job) or
`issued`/`not_stuck` (silently reading as "remediated" — the exact false-resolved
state this plan exists to eliminate). Therefore:

- Add `probe_only_complete` to `ReissueOutcome` **and** to `BENIGN_OUTCOMES`.
- It must be unreachable when `probeOnly === false`; `issued` must be unreachable
  when `probeOnly === true`.
- Add `probeOnly: boolean` to `ReissueResult` so it lands in `emitTerminal`'s
  `extra` and therefore in both the Sentry payload and the `public.routine_runs`
  row written by `runLogMiddleware` (`server/inngest/client.ts:73`). **The
  `cq-union-widening-grep-three-patterns` sweep must include the run-log
  middleware and any dashboard keyed on it** — otherwise the operator-facing
  routine-run history shows a cert-reissue run that "completed" with no
  indication it was only a probe.

2.3 **The gate — mirror the file's existing gather/check split.** Do **not** put
policy behind a dep. `ReissueDeps` members are IO primitives returning raw
observations; policy lives in exported pure functions
(`gatherPreconditions()` → raw `PreconditionInputs`; `checkReissuePreconditions()`
→ verdict). Mirror that exactly:

- `gatherDnsPropagation(): Promise<DnsPropagationInputs>` on `ReissueDeps` —
  raw observations only.
- exported pure `checkDnsPropagated(inputs)` — the verdict.

This keeps AC8's four cases as **pure-function** tests rather than
fake-configuration tests. (A `(deps)`-taking `ReissueDeps` member would also be
self-referential; no other member takes `deps`.)

The raw inputs combine:

- **Resolver check** — `Resolver` with `setServers(["1.1.1.1","8.8.8.8"])`;
  `resolve4` answers, for the policy to require ⊆ `185.199.0.0/16`.
- **AAAA check** — `resolve6`; policy requires `ENODATA`. In-flight detector for
  H-W4, and load-bearing given RI-1 (LE prefers IPv6 with almost no fallback).
- **ACME HTTP-01 shaped probe** — re-run the existing `probeAcme` shape
  **post-flip** and record whether the response signature is GitHub's or
  Cloudflare's. `gatherPreconditions` already runs this probe, but at *preflight*
  while records are still proxied, so it measures the proxied path and says
  nothing about the DNS-only state. Resolver answers alone test two resolvers'
  caches, not LE's.

2.4 **Placement, naming, and the restore invariant (highest-risk edit).**
Insert the gate as its own `step.run` between `toggle-reissue` and the poll loop,
with a bounded `step.sleep` retry loop using **fixed-count** step names
(`dns-gate-${i}` / `dns-gate-wait-${i}`) over a constant. Verified safe against
inngest 3.54.2: step ids are SHA1-hashed and matched by hash, not position
(`components/execution/v1.js:1113-1114`, `:910/:925/:984`), so inserting steps
before the poll loop does **not** invalidate later steps' memoization. A
wall-clock-derived counter would produce non-deterministic ids and is the one way
to break this. Per
`best-practices/2026-06-30-adaptive-ci-poll-gate-wall-clock-ceiling-not-attempt-count.md`,
also carry an elapsed-time check **inside** the fixed-count loop so the count is
the upper bound while wall-clock is the real ceiling.

**The trap:** `restore-steady-state` is an unconditional *body* step reached only
by falling through, and `onFailure` fires **only** on a thrown error or exhausted
retries — never on a clean early `return` (verified:
`InngestFunction.d.ts:334-340`, `execution/v1.js:1014-1022`). A clean early return
after the toggle would skip restore and leave the public site on a broken cert
indefinitely.

**State the invariant correctly.** The earlier framing ("restore must precede all
post-toggle terminal returns") is wrong and would cause a real regression. The
existing `reissue_failed` return at `:414` is **already safe** — not because it
precedes the toggle, but because `toggle-reissue`'s own `catch` calls
`restoreState(deps)` in-step at `:404`. Adding a second body-level restore on
that path would be idempotent but harmful: if the second restore throws, the body
throws, `onFailure` fires, and the precise diagnostic `reissue_failed` outcome is
overwritten by `reissue_incomplete_restore_ok` / `proxy_restore_failed`.

The correct invariant: **every post-toggle exit is preceded by a restore —
either the in-step one at `:404` or the body step at `:449`.** Complete
enumeration of post-toggle exits: `!toggle.ok` (`:414`, in-step restore),
`PartialToggleError` (`:228` → caught `:402` → in-step restore), a `poll-${i}`
throw (`onFailure`), a `restore-steady-state` throw (`onFailure`), and the normal
fall-through (`:451`).

**Make it structural, not test-enforced.** A universal ("no post-toggle return
bypasses restore") cannot be proven by driving one path. Restructure
`runReissueSteps` so there is exactly **one** post-toggle return site, after
`restore-steady-state`, carrying the outcome in a local. Then the invariant holds
by construction and AC9 degrades from proof to regression test.

The gate itself must (a) never throw, (b) return a discriminated result, and
(c) on failure flow to that single return site.

2.5 Extend `ReissueOutcome` with `dns_propagation_failed`. It is **not** benign —
it must page. Sweep every consumer per `cq-union-widening-grep-three-patterns`:
`BENIGN_OUTCOMES`, `emitTerminal`, `runLogMiddleware`/`routine_runs`, the test
suite, and any Sentry alert keyed on `outcome`. Run `tsc --noEmit` and treat each
`not assignable to never` as the canonical enumeration of rails to widen.

2.6 **Do not lengthen the window in this PR.** The propagation budget comes **out
of** the existing `POLL_MAX_MS`; the total DNS-only window stays at **15 minutes**
(see RI-2 for the unresolved tension and why the measurement, not a guess, is the
input to any future change).

**Budget the whole window, not just the poll.** The real DNS-only wall clock is
`(MAX_POLLS-1) * POLL_INTERVAL_MS` (~14 min) **plus** `CNAME_SETTLE_MS` (45 s,
inside the toggle step, after the flip) **plus** the new gate budget. Today's code
already exceeds 15 min by that 45 s. Export a single derived constant for the
**sum** and assert against it (AC13) — asserting `POLL_MAX_MS` alone passes while
the true public-TLS-outage window overruns.

2.7 Extend `REISSUE_ALLOWED_STATES` per RI-3 (drop the undocumented `"failed"`,
add `errored` and `authorization_revoked`). This is a **behavior change to the
preflight gate**: it needs its own test and a line in ADR-125.

2.8 Add a comment (and, ideally, a broadened assertion) at
`EXPECTED_TOGGLE_RECORDS = 5`: the count asserts the toggle set matches `dns.tf`,
but provides **no** protection against record *types* that were never in `dns.tf`
— precisely how the AAAA gap evaded it. Compare the parallel drift class in
`2026-04-03-cloudflare-dns-at-symbol-causes-terraform-drift.md`.

2.9 **Document a pre-existing latent double-fire.** If `restoreState(deps)` inside
`toggle-reissue`'s `catch` throws, the whole step throws, `retries: 1` re-runs the
**entire** toggle+reissue unit, and a **second cname re-order** consumes a second
LE validation attempt. Nobody has counted these, and they are a live contributor
to H-W3. The new `cname-put-*` markers expose this going forward — say so
explicitly in the code comment so the next reader can count them.

### Phase 3 — Follow-through sweeper reopen path

3.1 In `scripts/sweep-followthroughs.sh`, add a **separate** query for closed
`follow-through` issues with its own `--limit`. Do **not** widen the existing
`--state open --limit 50` call to `--state all`; that would silently starve the
open set. Pin a single `--search 'label:follow-through state:closed closed:>=…'`
form (mixing `--search` with `--label`/`--state` is gh-version-sensitive — gh
folds them into search qualifiers) and verify it against the runner's pinned gh.

3.2 **The closed-issue path MUST bypass the `earliest` gate.** This is the fix
that makes Phase 3 work at all. `run_one` returns 0 early when
`now_epoch < earliest_epoch` (`scripts/sweep-followthroughs.sh:178-185`). #6657 was
closed 2026-07-18 carrying `earliest=2026-07-25`, so under any closed-recency
window shorter than ~7 days it would leave the query window **before its own
`earliest` elapsed** — evaluated zero times, reopened never. **The originally
proposed design would not have caught its own motivating case.**

The rationale is sound, not just expedient: `earliest` exists to prevent a
premature *close*. A **closed** follow-through is already asserting "verified,"
so its predicate should be evaluated immediately regardless of the soak clock.
Skip the gate for the closed set; keep it for the open set.

3.3 Fetch `stateReason` in the `--json` field list and **exclude `NOT_PLANNED`** —
wontfix closures are deliberate. Only `COMPLETED` closures are candidates.

3.4 **Verdict handling on the closed set:**

- exit **1 (FAIL)** → `gh issue reopen` + comment with the output.
- exit **2 (TRANSIENT)** → **no action and no comment.**
- exit **0 (PASS)** → **full no-op, comment included.** Note that `run_one`
  currently posts a comment *unconditionally* before the close decision
  (`sweep-followthroughs.sh:271-274`); reusing it as-is would post a fresh
  "recovered" comment on every correctly-closed issue **every day, forever**. The
  reopen cap in 3.5 bounds reopens, not comments — this needs its own guard.
- A non-zero `gh issue reopen` exit must emit `::error::` rather than being
  swallowed by the loop (it is the only failure surface for this path).

3.5 **Bound the loop statelessly.** The script is stateless and runs verification
under `env -i`, so an in-process counter does not survive. Two workable options —
pick one in implementation: (a) count prior sweeper-reopen comments via
`gh issue view --json comments` and give up at N; (b) honor a
`soleur:followthrough-nosweep` marker. Prefer (a) — (b) requires a human to apply
the label, which is an operator step.

3.6 **Do not turn every follow-through into a permanent daily monitor.** After the
sweeper closes an issue on PASS, the next run's closed query would pick it up
again (recently closed, `COMPLETED`, gate bypassed) and re-run the script daily
for the whole recency window. If the condition later regresses, it would reopen an
issue the sweeper itself correctly closed.

Reconciliation that preserves 3.7's actor-agnosticism: skip closures whose most
recent comment is **the sweeper's own PASS block**. That is *evidence*-based, not
*actor*-based — it still catches every premature close by any actor, while not
re-litigating a closure the sweeper itself justified.

3.7 The path is deliberately **actor-agnostic** — it catches a premature close
from the sweeper, a `Closes #N` in prose, the operator, or an agent session. Note
per `2026-06-05-followthrough-pr-body-prose-closes-keyword-autocloses-tracker.md`
that GitHub's keyword parser matches `closes #N` in *descriptive prose anywhere*
in a PR body, not just in a standalone trailer — so AC18's guard must scan the
whole body for closing-keyword adjacency, not merely avoid writing
`Closes #6698`.

3.8 **Decision (not deferred): reopen #6657.** It is the tracker carrying the
verified follow-through directive and the correct probe; #6698 tracks this
plan's work. Reopening #6657 also exercises the new path end-to-end.

3.9 Verify the sweeper changes live against real inputs before trusting them —
per `best-practices/2026-07-07-followthrough-and-shape-gate-silent-falseness.md`,
verification code is the highest-leverage place for a silent false-green because
nothing downstream verifies the verifier. Run against the **failing** input, not
just the passing one.

### Phase 4 — ADR-125 (conditional) and C4

4.1 **Commit to the branch-B amendment text now; do not leave the ADR shape
conditional.** The earlier conditional framing was incoherent: Phase 0.1's
branch A ("stop and re-scope") *voids this plan*, so an ADR amendment inside a
voided plan is vacuous. Branch A needs a **new** ADR on toggle-set completeness,
authored by whatever plan replaces this one — not an amendment here. This plan
therefore writes branch B in full.

**Branch B amendments to ADR-125 — all four are substantive:**

- `## Decision` step 3 currently reads "Poll (`step.sleep`): `GET /pages` up to
  ~15 min." Phase 2.6 takes the propagation budget **out of** `POLL_MAX_MS`,
  which **shortens the cert poll below what the ADR states.** This is a real edit
  to step 3, not merely "record the new step."
- `## Decision` gains the propagation-gate step and the corrected total-window
  budget (poll + `CNAME_SETTLE_MS` + gate).
- `## Decision` records the `REISSUE_ALLOWED_STATES` widening (RI-3).
- `## Consequences` must contemplate **probe-only**: it opens the same DNS-only
  window and incurs the same during-window blast radius **while by design not
  remediating**. The current Consequences bullet does not consider a mode that
  pays the cost without attempting the fix.

4.1b **The file docstring and ADR both assert an invariant this change breaks.**
`cron-gh-pages-cert-reissue.ts:17-19` states the poll's `step.sleep` is "the only
suspension point," and ADR-125 leans on that when rejecting `try…finally`. The
gate's `dns-gate-wait-${i}` sleeps make that literally false. The *reasoning*
still holds (there is still no `finally`), but both texts must be corrected —
otherwise the next reader trusts a comment that no longer describes the code.

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
- **AC3** **Invariant, not diff-shape:** no marker reaches Better Stack via the
  injected Inngest ctx `logger`. Assert that a run ending in each benign outcome
  (`issued`, `not_stuck`) emits a `terminal` marker through the marker module —
  the earlier "zero `logger.info(` additions" form was a proxy that passes while
  `emitTerminal`'s pre-existing `logger.info` (`:694`) leaves the success path
  dark, which is the plan's headline defect.
- **AC4** Every `phase` union member has ≥ 1 emit site — asserted by driving
  `runReissueSteps` (**and** `cronGhPagesCertReissueOnFailure` for
  `onfailure-restore`) with fakes and comparing the observed phase set against the
  exported union. Not a grep count.
- **AC5** **Value, not type:** `runId` and `attempt` propagate from `HandlerArgs`
  into every emitted marker. Drive the handler with a known `runId`/`attempt` and
  assert those exact values appear; a type-level check alone passes against a
  hardcoded `attempt: 0`.
- **AC6** No marker is emitted from the orchestrating body except the `terminal`
  one: assert emitted-marker counts from the fake step across a simulated
  multi-resume run stay once-per-real-execution. **Bound the assertion**
  (`<= MAX_POLLS`), do not pin an exact count, per
  `2026-06-29-review-rate-limit-fallback-and-wallclock-exact-assertion-flake.md`.
- **AC7** The marker payload type contains no user id, email, or secret field
  **and no field named** `body`, `content`, `message`, `userMessage`, `prompt`,
  `chat_message`, `userInput`, or `user_input` (each is deleted by
  `[transforms.pii_scrub_drop_userdata]` and would silently never ship).
- **AC8** `checkDnsPropagated` is a **pure exported function** covered by direct
  unit tests: all-`185.199.x` + GitHub-shaped ACME (pass); Cloudflare answers
  (retry); AAAA present (fail, H-W4); budget exhaustion (`dns_propagation_failed`).
- **AC8b** **No dead twin:** `buildLiveDeps` actually constructs a real
  `gatherDnsPropagation`. Assert the live deps object exposes it and that it is
  not a stub — otherwise a PR adding the type member, the gate step, and the
  fakes passes AC8/AC10/AC12 and `tsc` while the production path never runs the
  gate, which is exactly the "parallel/dead twin" the file's docstring forbids.
- **AC9** **Structural, then regression:** `runReissueSteps` has exactly **one**
  post-toggle return site, located after `restore-steady-state`. Assert
  structurally (single return) plus a regression test that
  `restore-steady-state` runs on the `dns_propagation_failed` path. Additionally
  assert the `reissue_failed` path still restores **in-step** at `:404` and does
  **not** gain a second body-level restore.
- **AC10** Step ordering across both modes: `capture-pre-flip-dns` →
  `toggle-reissue` → `dns-gate-*` → (remediation only) `poll-*` →
  `restore-steady-state`. Asserted from the fake step's recorded call sequence.
  Gate step names are fixed-count and identical across a simulated replay.
  "The toggle" here means the **DNS flip**, which occurs in both modes.
- **AC11** **Rescoped to the real invariant:** probe-only makes **zero calls to
  `reissueViaCnameToggle`** — i.e. no `setPagesCname(null)` and no settle sleep.
  Assert on the absence of the `null` argument, **not** on `setPagesCname` call
  count: `restoreState` legitimately calls `setPagesCname(PAGES_CNAME)` when
  `pages.cname !== PAGES_CNAME` (`:291-294`), so a call-count assertion is false
  in a reachable state and would pressure an implementer into making restore's
  cname re-assert conditional on `!probeOnly` — a direct regression of ADR-125's
  symmetric restore contract.
- **AC11b** Probe-only **aborts loudly in preflight** if the live cname is
  already wrong, rather than silently repairing it inside restore. Without this,
  a "probe-only" fire against the `cname:null` state left by a prior failed fire
  would issue a real `PUT /pages`, re-order the cert, and consume an LE
  validation attempt — the one thing probe-only exists to avoid.
- **AC11c** Probe-only runs **zero** `poll-${i}` steps.
- **AC12** Union widening swept: `tsc --noEmit` clean;
  `dns_propagation_failed` **not** in `BENIGN_OUTCOMES`; `probe_only_complete`
  **in** `BENIGN_OUTCOMES`; `probeOnly` present on `ReissueResult` and therefore
  in the `public.routine_runs` row written by `runLogMiddleware`.
- **AC13** **Sum, not a single constant.** Assert the exported total-window
  constant equals `(MAX_POLLS-1)*POLL_INTERVAL_MS + CNAME_SETTLE_MS + gate budget`
  and that the total is **≤ 15 minutes**, matching ADR-125. Asserting
  `POLL_MAX_MS` alone passes while the true public-TLS-outage window overruns —
  it already does today by `CNAME_SETTLE_MS` (45 s).
- **AC14** `scripts/sweep-followthroughs.sh`, asserted in the **existing**
  harness `scripts/sweep-followthroughs.test.sh`: reopens on exit 1; no action
  **and no comment** on exit 2; **no comment** on exit 0 for a closed issue;
  skips `NOT_PLANNED`; **bypasses the `earliest` gate for closed issues**; skips
  closures whose latest comment is the sweeper's own PASS block; honors the
  stateless reopen bound; emits `::error::` on a failed `gh issue reopen`; the
  open-issue query's limit is unchanged.
- **AC14b** A regression fixture reproduces **#6657's exact shape** — closed
  `COMPLETED`, `earliest` in the future, script exits 1 — and the sweeper
  reopens it. This is the case the original design would have missed.
- **AC15** `bash -n scripts/sweep-followthroughs.sh` clean. No change to
  `.github/workflows/scheduled-followthrough-sweeper.yml` is required (no new
  `secrets=`); if it does change, `actionlint` it.
- **AC16** Restore behavior unregressed: existing tests for `restoreState`
  fail-loud (`EXPECTED_TOGGLE_RECORDS`), the final restore step, and the
  `onFailure` handler all still pass.
- **AC16b** `REISSUE_ALLOWED_STATES` widening (RI-3) has its own test: `errored`
  and `authorization_revoked` are reissue-eligible; `issued`/`approved` and the
  in-flight states are still declined.
- **AC17** ADR-125 amended per Phase 4.1 (all four edits) and the "only
  suspension point" claim corrected in both the ADR and the file docstring per
  4.1b; C4 enumeration recorded per Phase 4.2; `c4-code-syntax.test.ts` +
  `c4-render.test.ts` pass.
- **AC18** PR body uses **`Ref #6698`**, and a scan of the **entire body** finds
  zero `<closing-keyword> #<n>` adjacencies in prose (GitHub's parser matches
  `closes #N` anywhere, not just in a trailer). The live remediation is
  post-merge, so an auto-close at merge would recreate exactly the false-resolved
  state this plan fixes.
- **AC18b** Phase 2.8's `EXPECTED_TOGGLE_RECORDS` comment is present (the only
  Phase-2 deliverable otherwise lacking an AC).

### Post-merge (fully automated — no operator step)

- **AC19** Deploy lands and the container restarts (this also clears the
  `tokenCache` in `server/github-app.ts`, which otherwise serves a stale
  pre-grant token for ~45 min). **Assert, don't observe:** `curl -s
  https://app.soleur.ai/health` reports a `build_sha` matching the merge commit.
- **AC20** **Fire 1 — probe-only** (consumes no LE validation attempt). `data` is
  omitted, which selects probe-only by the Phase 2.1 default; passing it
  explicitly is equally acceptable and clearer:

  ```bash
  SECRET=$(doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET -p soleur -c prd --plain)
  curl -s -X POST https://app.soleur.ai/api/internal/trigger-cron \
    -H "Authorization: Bearer $SECRET" -H "Content-Type: application/json" \
    -d '{"event":"cron/gh-pages-cert-reissue.manual-trigger","data":{"probeOnly":true}}'
  ```

- **AC21** **Discoverability test (no SSH, no dashboard).** Within 20 min of the
  fire, markers are readable:

  ```bash
  doppler run -p soleur -c prd_terraform -- \
    bash scripts/betterstack-query.sh --since 30m --grep '"SOLEUR_CERT_REISSUE":true'
  ```

  **Expected phase set is per-mode** — the earlier "≥ 1 row per phase value" was
  unsatisfiable against AC20, since probe-only never emits `cname-put-*` or
  `poll`:
  - **probe-only:** `preflight`, `pre-flip-dns`, `flip-dns-only`,
    `dns-propagation`, `restore`, `terminal`.
  - **remediation:** all of the above plus `cname-put-null`, `cname-put-set`,
    `poll` (and `onfailure-restore` only on a throw).

  **Attribute rows to this fire** by filtering on the marker's `runId`, not on the
  time window alone — a bare `--since 30m` also matches earlier fires.
  **Field-isolate the discriminator**: grep the structured form
  `"SOLEUR_CERT_REISSUE":true`, never the bare token, because `--grep` compiles to
  an unanchored `raw LIKE '%…%'` over a source every host multiplexes into, and
  inngest ships GitHub-webhook payloads (issue/PR bodies — including this plan)
  to the same source. Since the structured form is itself quoted in this plan and
  will appear in the PR body, **also scope on the producer**: inngest-shipped
  webhook rows carry `source_kind=journald`, never `app_container`, so add
  `source_kind":"app_container` as a second term. See
  `2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md`.

  **Timing:** the `remote(_logs)` hot window is ~40 min and older rows come from
  the s3 archive with its own ingestion lag; if a T+20min query returns nothing,
  re-run with a wider `--since` before concluding the markers are missing.

- **AC22** **Verdict rule (deterministic, from markers alone).** Branches are
  ordered; take the first that matches. Every reachable observation has a branch:
  1. **Zero markers** → telemetry or deploy problem, *not* a cert finding. Confirm
     AC19's `build_sha`, then confirm the run happened at all (Inngest run
     history / the `public.routine_runs` row). Do **not** proceed to AC23.
  2. **`terminal` marker with `not_stuck`** → the cert left `bad_authz` on its
     own; re-read `GET /pages` and stop. Not a failure.
  3. **`pre-flip-dns` does not show Cloudflare answers** → the zone was already
     DNS-only (a prior fire's restore failed, or a manual edit). Fix steady state
     first (`AC24`); this run's propagation reading is not meaningful.
  4. **AAAA observed at any point** → **H-W4 confirmed.** Remediate the zone drift
     in Terraform. Do **not** fire remediation until it is gone.
  5. **`dns-propagation` never reaches `185.199.x` within budget** → **H-W1
     confirmed**; the gate did its job. Concrete next step: compare the observed
     convergence time against the gate budget and Cloudflare's fixed 300 s proxied
     TTL (RI-2) — if propagation is simply slower than the budget, raise the gate
     budget *within* the 15-min total; if it never converges, investigate the
     zone rather than the budget.
  6. **Resolvers reach `185.199.x` but the ACME probe is not GitHub-shaped** →
     something still intercepts the challenge path (a redirect, a residual CF
     rule). This is the most informative single observation available; investigate
     the interception before any remediation fire.
  7. **All four propagation conditions hold** (CF pre-flip, `185.199.x`, AAAA
     `ENODATA`, GitHub-shaped ACME) → **H-W1 and H-W4 refuted.** Proceed to AC23.
- **AC23** **Fire 2 — remediation.** Only after AC22 branch 7, and only after a
  **multi-hour cooling-off** for H-W3 (LE failed-validation windows are hourly and
  compounding, per RI-4; the cert does not expire until 2026-08-16, so the wait is
  cheap insurance). The `probeOnly:false` payload is **required** — the default is
  probe-only:

  ```bash
  SECRET=$(doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET -p soleur -c prd --plain)
  curl -s -X POST https://app.soleur.ai/api/internal/trigger-cron \
    -H "Authorization: Bearer $SECRET" -H "Content-Type: application/json" \
    -d '{"event":"cron/gh-pages-cert-reissue.manual-trigger","data":{"probeOnly":false}}'
  ```

  Then watch up to ~15 min:
  `gh api /repos/jikig-ai/soleur/pages --jq '.https_certificate.state'` must reach
  `issued`/`approved`.

  **If propagation was proven good and the cert still stays `bad_authz`:** H-W2
  and H-W3 remain, and per RI-7 the poll markers may not separate them. Read the
  captured `https_certificate.description` and `protected_domain_state` from the
  poll markers first — that is the only in-band LE-side signal. If the trajectory
  is flat with no advancing state, treat H-W3 (rate limiting) as most likely and
  back off; do **not** simply lengthen the window.
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
  - mode: cert never validates though DNS-only state is correct — window too short (H-W2)
    detection: per-poll-tick markers carrying the full https_certificate object; an ADVANCING state trajectory (authorization_pending/authorized) distinguishes this from a flat one
    alert_route: poll_timeout terminal → Sentry
  - mode: Let's Encrypt failed-validation rate limiting (H-W3)
    detection: NOT DETECTABLE BY ANY DECLARED LAYER. GET /pages returns the same string either way and GitHub surfaces no LE rate-limit signal. Reachable only by ELIMINATION via the AC22 verdict rule once H-W1/H-W4 are refuted, plus a flat (non-advancing) state trajectory and whatever https_certificate.description carries. Recorded honestly rather than overclaimed — see RI-7.
    alert_route: poll_timeout terminal → Sentry (indistinguishable from H-W2 at the alert level)
  - mode: a post-toggle terminal return skips restore, leaving the public site on a broken cert
    detection: structural — exactly one post-toggle return site, after restore (AC9); plus the existing restore-assert convergence re-read and onFailure
    alert_route: proxy_restore_failed → Sentry (unchanged)
  - mode: a follow-through tracker is prematurely closed while unrecovered
    detection: sweeper evaluates recently-closed COMPLETED follow-through issues, bypassing the earliest gate for the closed set
    alert_route: scheduled-followthrough-sweeper.yml workflow run log (::error:: on a failed gh issue reopen) + the gh issue reopen itself + its comment
logs:
  where: Better Stack source soleur-inngest-vector-prd (id 2457081), source_kind=app_container
  retention: ~40-min hot window via remote(_logs); older rows from the s3 archive via betterstack-query.sh's default UNION ALL
discoverability_test:
  # Asserts the DELIVERY CHAIN this marker rides is live, authenticated and
  # queryable — the typo'd-hostname / unrunnable-command class this field exists
  # to catch. Deliberately NOT "the cert-reissue markers are present": that
  # cannot be true before the code is deployed, so making it the pre-merge
  # expectation would render the check unsatisfiable for every NEW observability
  # signal (verified: the marker-grep runs clean at rc=0 and returns empty,
  # which a presence-based expected_output reads as a broken command).
  command: doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 30m --limit 1 --grep 'soleur-web-platform'
  expected_output: at least one JSONEachRow row (proves app_container -> Vector -> Better Stack is live)
  # MARKER PRESENCE is the stronger assertion and is enforced post-deploy, not
  # by prose: scripts/followthroughs/cert-reissue-markers-6698.sh requires
  # >=3 distinct phases on source_kind=app_container rows, and is enrolled on
  # #6698 with the follow-through sweeper. It was live-verified in BOTH
  # directions before landing (FAIL on the markers-absent state; 86 rows found
  # against an existing discriminator, proving it can PASS).
  post_deploy_command: doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/cert-reissue-markers-6698.sh
  post_deploy_expected_output: "PASS: cert-reissue step markers are reaching Better Stack" 
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

## Downtime & Cutover

*(deepen-plan Phase 4.55 — the DNS-only flip degrades a live serving surface.)*

**Offline-inducing operation:** the transient flip of `cloudflare_record.github_pages`
(4× apex A) and `cloudflare_record.www` to `proxied=false`. **Surface affected:**
`soleur.ai` and `www.soleur.ai` — the public marketing/docs site.

**Nature of the degradation:** not a hard outage. The site keeps answering, but
during the window it answers from GitHub Pages directly with GitHub's
**`bad_authz` certificate**, so HTTPS visitors get a browser interstitial and the
Cloudflare edge (Always-Use-HTTPS, WAF, bot management, caching) is bypassed on
those two hostnames. `app.soleur.ai` — the actual product surface — is served by
`cloudflare_record.app` and is **untouched**.

**Zero-downtime path evaluated.** There is no blue-green or expand-contract
equivalent here: the ACME HTTP-01 validation *requires* Let's Encrypt to reach
GitHub's origin directly, which is precisely what proxying prevents. The
degradation is intrinsic to the remediation, not an artifact of how it is
sequenced. What the plan CAN do — and does — is minimize exposure:

- **Probe-only mode (Phase 2.1)** performs the flip, measures, and restores
  **without** re-ordering the cert. It is the default for manual fires, so the
  diagnostic pass costs one short window instead of a full remediation window.
- **The window is not lengthened** (Phase 2.5): total DNS-only time stays at
  **15 minutes**, with the propagation gate's budget drawn out of `POLL_MAX_MS`.
- **Restore is unconditional and now fall-through-guaranteed** (Phase 2.3):
  restore precedes every post-toggle terminal return, closing the path where a
  clean early return would have left the site degraded indefinitely.
- **Fail-loud restore** (`EXPECTED_TOGGLE_RECORDS`, the convergence re-read, and
  the `onFailure` handler) is preserved unchanged.

**Residual accepted:** up to 15 minutes of degraded TLS on two public marketing
hostnames per fire, bounded and self-reverting. **Rollback:** `restoreState` is
idempotent and re-asserts the Terraform-declared steady state; it can be
re-driven at any time.

**Per-stage verification:** `pre-flip-dns` marker (baseline) → `flip-dns-only`
marker → `dns-propagation` markers (observed resolver answers) → poll markers →
`restore` marker → steady-state re-assert (AC24).

## Network-Outage Deep-Dive

*(deepen-plan Phase 4.5 — triggered on `timeout`. Per `hr-ssh-diagnosis-verify-firewall`,
L3 must be verified before any service-layer hypothesis.)*

This plan's symptom is a validation failure across a network path, so the L3→L7
ordering applies directly — and it is the reason Phase 0.1 outranks everything.

| Layer | Question | Status |
| --- | --- | --- |
| **L3 — DNS / routing** | Does the apex resolve to GitHub's `185.199.x` during the DNS-only window, on public resolvers? | **NOT VERIFIED.** This is H-W1, and no telemetry has ever observed it. The propagation gate exists to answer it. |
| **L3 — DNS record completeness** | Is the toggle set (4 A + 1 CNAME) the *whole* address surface, or does an undeclared AAAA survive the flip? | **NOT VERIFIED — blocking.** This is H-W4. Resolved by Phase 0.1's read-only CF query. Live resolution currently returns AAAA on both apex and www; `dns.tf` declares none. |
| **L3 — firewall / egress** | Is any allowlist involved? | **N/A.** No SSH, no host firewall on this path. Validation traverses public internet to GitHub Pages anycast. |
| **L7 — TLS / proxy** | Does Cloudflare intercept the ACME challenge path? | **PARTIALLY VERIFIED.** `gatherPreconditions` probes `/.well-known/acme-challenge/...` and requires 404 (the carve-out), plus `always_use_https != "on"`. But it runs at *preflight*, while records are still proxied, so it measures the proxied path, not the DNS-only one. Phase 2.2 re-runs it post-flip — this is the gap being closed. |
| **L7 — application** | Does the Pages API accept the toggle? | **VERIFIED.** `PUT /pages` returns 2xx since #6687/#6694; no `reissue_failed` terminal on either live fire. |
| **L7 — upstream rate limit** | Is Let's Encrypt refusing to validate regardless of network state? | **NOT VERIFIED.** This is H-W3, and it is invisible to `GET /pages`. Mitigated by probe-only mode (which consumes no validation attempt) plus the multi-hour cooling-off in AC23. |

**Gap to close before implementation:** Phase 0.1 (L3 record completeness). It is
free, read-only, and may terminate the investigation. **No service-layer fix
— window length, poll cadence, backoff — may be tuned before L3 is verified.**

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
| The sweeper reopen path flaps on a deliberately-closed issue | `NOT_PLANNED` exclusion + stateless reopen cap + TRANSIENT/PASS no-op + skip closures whose latest comment is the sweeper's own PASS block (Phase 3.3–3.6, AC14) |
| **The success path stays dark anyway** — `emitTerminal` routes benign outcomes through `logger.info` (`:694`), so `issued`/`not_stuck` never ship | Phase 1.5 mandates a marker emit *inside* `emitTerminal`; AC3 asserts the invariant rather than the diff shape |
| **Probe-only silently re-orders the cert** via `restoreState`'s cname re-assert when a prior fire left `cname:null`, consuming an LE attempt | AC11b — probe-only aborts loudly in preflight on a wrong cname instead of repairing it in restore; AC11 rescoped to "zero `reissueViaCnameToggle` calls" so no one is pressured into making restore conditional |
| **The gate ships as a dead twin** — type member + fakes + `tsc` all green while `buildLiveDeps` never constructs it | AC8b asserts the live deps object exposes a real `gatherDnsPropagation` |
| **Phase 3 misses its own motivating case** — the `earliest` gate (`:178-185`) skips #6657 before its soak elapses | Phase 3.2 bypasses `earliest` for the closed set; AC14b is a regression fixture in #6657's exact shape |
| The operator cannot fire remediation — no invocation documented | AC23 spells out the `{"probeOnly":false}` payload; the route's `data` pass-through is verified (`trigger-cron/route.ts:100-108`) |
| Marker fields silently vanish in the PII scrub | AC7 forbids the eight deleted key names (`vector.toml:246-253`) |
| Markers cannot be attributed to a specific fire | `runId` on every marker (Phase 1.3); AC21 filters on it |
| `attempt` is a meaningless constant | Threaded from `HandlerArgs` (already declares `attempt`/`runId`); AC5 asserts the *value*, not the type |
| The `onFailure` path is marker-dark, reproducing the original asymmetry | `onfailure-restore` phase emitted from both branches of the handler's try/catch (Phase 1.2) |
| A throwing `restoreState` emits no restore marker at all | Phase 1.7 — emit on entry *and* on outcome, including from a rethrowing catch |
| `routine_runs` disagrees with the marker stream about what a run did | `probeOnly` on `ReissueResult` → `emitTerminal` extra → the `runLogMiddleware` row; the union sweep explicitly includes the middleware (Phase 2.2, AC12) |
| The docstring/ADR "only suspension point" invariant becomes false | Phase 4.1b corrects both texts |
| A toggle-step retry silently doubles LE validation attempts | Pre-existing; documented in Phase 2.9 and now countable via the `cname-put-*` markers |

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
