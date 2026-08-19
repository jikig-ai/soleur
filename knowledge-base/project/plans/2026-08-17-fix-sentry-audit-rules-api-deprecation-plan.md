---
title: "fix: migrate the Sentry audit off the deprecated alert-rules API family and make its failures name their own cause"
date: 2026-08-17
slug: fix-sentry-audit-rules-api-deprecation
branch: feat-one-shot-7590-sentry-rules-api-410
issue: 7590
closes: 7590
lane: cross-domain
type: bug
priority: p2-medium
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

## Overview

The Sentry Audit Gate goes red intermittently on PRs that change nothing in the audit
script. `fetch_rules()` in `apps/web-platform/scripts/sentry-monitors-audit.sh` reads an
endpoint family Sentry deprecated on 2026-05-14 and now serves with scheduled brownouts:
outside a brownout the endpoint answers 200, inside one it answers 410 with
`{"message":"This API no longer exists."}`. The script's only reaction is
`ERROR: rules response is not a JSON array`, which names neither the status nor the cause.

This plan repoints the rules fetch onto the replacement endpoints Sentry names in its own
response headers, adds a deprecation tripwire so the next deprecation announces itself months
before it bites, makes non-array responses self-diagnosing, and repairs a retry wrapper that
has never been able to retry any HTTP-level failure at all.

**Revised after a five-agent plan review** (dhh, kieran, code-simplicity,
architecture-strategist, spec-flow; cto pending). The review falsified two premises this plan
was built on and found a P0 in its central mechanism. The plan is now materially **smaller**:
one phase and several mechanisms were deleted outright rather than fixed. Corrections are
recorded in Research Reconciliation; scope challenges are in
`knowledge-base/project/specs/feat-one-shot-7590-sentry-rules-api-410/decision-challenges.md`.

Note: `lane:` could not be carried forward — no `spec.md` existed for this branch — so it is
defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-08-17
**Halt gates passed:** 4.6 (user-brand, threshold `aggregate pattern`), 4.7 (observability, 5/5
fields with children, `bash` verb allowlisted, no SSH), 4.8 (no PAT shapes), 4.11 (guard-contract
lint green, assembly structural). 4.9/4.10/4.55 did not trigger. **4.5 fired** and is answered in
the Network-Outage Deep-Dive.

### Key improvements from the deepen pass

1. **A credential-exfiltration hazard in the pagination work, caught by precedent.** Sentry's `Link`
   headers are absolute. Following them as given would send `SENTRY_IAC_AUTH_TOKEN` wherever the
   header points. `scripts/zot-inventory.sh` already documents this attack — measured against curl
   8.18.0 — and rejects non-rooted targets. The plan now extracts only the cursor and rebuilds the
   URL from `$api_host`, with T20b as the falsifying fixture.
2. **Two "novel" mechanisms turned out to have repo precedent.** The `CURL_RETRY_LAST_*` global-out
   contract is `http_get()`'s `HTTP_CODE`/`HTTP_BODY`/`HTTP_HDR` shape, adopted for a documented
   reason (a stdout return pushed callers into a subshell where a counter increment vanished while
   the suite stayed green). The `curl`-stub transport seam has three existing implementations. Both
   are now cited rather than reinvented.
3. **A truncation-poisons-the-verdict invariant**, borrowed from the same script's refusal to emit
   `outcome=ok` beside `enumeration_complete=false`. Plus a `MAX_PAGES` ceiling.
4. **A claim of mine was falsified.** I had written that the id manifest has "no live consumer"; the
   README runbook consumes it and T7 tests that coupling. Corrected — retirement is still right, but
   it is a three-part change.

### Prior corrections retained from plan review

The five-agent review falsified the "orphan test suite" premise (it is glob-registered and green at
14/14) and found the `-w`-inside-`curl_retry` P0. Both are recorded in Research Reconciliation.

## Research Reconciliation — Brief vs. Codebase & Live API

All rows measured against `jikigai-eu` / `web-platform` on 2026-08-17 with the Doppler `prd`
`SENTRY_IAC_AUTH_TOKEN` (the token CI actually uses).

| Claim | Measured reality | Plan response |
|---|---|---|
| `projects/{org}/{proj}/rules/` → "410 gone" | **HTTP 200**, 30 items, deprecation headers present. Also 200: `alert-rules/`, `combined-rules/` | Deprecated-and-brownout, not removed. Get-ahead-of-sunset work |
| Replacement for both branches is `workflows/` | Sentry names **two**: `rules/` → `workflows/`; `alert-rules/` **and** `combined-rules/` → `detectors/` | Map per endpoint (Decision 1) |
| "Both branches of `fetch_rules()` are dead" | The org branch returns **200 with `[]`**. It is also unreachable in production — all three callers set `SENTRY_PROJECT` | Both replacements are **org-scoped**, so the branch dissolves entirely (Decision 1) |
| Class A/B/C "cannot be computed at all" | They compute, and have been computing **wrong** for months | Correctness fix, not a port (Decision 2) |
| 410/scope/empty produce "byte-identical output" | The 410 **body** is already printed by the `head -c 500` at the shape check | Narrowed: what is missing is status, host, source, and the deprecation headers |
| Brownout is "~2 min every 2 hours" | Mechanism confirmed; **schedule not established**. 6 of 7 failures land ≤3 min past an hour boundary of *mixed parity*; one (10:34:35) fits no hourly model | Hypothesis H4 stays UNKNOWN; no retry is sized to it (Decision 3) |
| Token naming collision is "not the bug" | Confirmed: both names in Doppler `prd`, 64 chars each, **different values**; GitHub holds only `SENTRY_IAC_AUTH_TOKEN`, so no CI-side collision — only a reader trap | Document in PR body + script header |

### Corrections the plan review forced on my own earlier claims

| My claim (v1) | Verdict | Correction |
|---|---|---|
| "The unit suite is an orphan — registered in no runner" | **FALSE** | `scripts/test-all.sh` `SUITE_GLOBS` includes `apps/web-platform/scripts/*.test.sh`, which matches it. `lint-orphan-test-suites.sh` → `358 covered, 0 orphaned`; the suite runs green at `14 passed, 0 failed`. My `grep -c` for a literal path could not see **glob** registration. Phase 8, AC7 and the associated risk row are deleted; an explicit `run_suite` line would have **double-registered** the suite and turned the required `test` check red |
| "The four gates are unchanged by this plan and run before `fetch_rules()`" | **FALSE** | Gates 1–3 call `curl_retry` directly and Gate 4 consumes `gate1_body`. A `curl_retry` rewrite is squarely inside their blast radius. User-Brand Impact and Decision 3 corrected |
| Phase 1: "use `curl -D "$hdr_file" -w '%{http_code}'`" | **P0** | Measured: duplicate `-w` → **last wins**. Gates 2/3 already pass their own `-w`; Gate 1 and both fetches consume the **body**. Any wrapper-level `-w` either corrupts the body (`[...]200` → shape check fails on a healthy 200) or silently changes the gates' meaning. **`-D` only** — verified that `-D` yields the status line while the caller's `-w` survives intact |
| "Use the existing `SENTRY_FIXTURE_RULES` seam for the new tests" (from the brief) | **Impossible** | The seam is `cat "$SENTRY_FIXTURE_RULES"; return` — it short-circuits **before curl exists**, so a file fixture cannot express a status, a header, or a retry sequence. A transport-level seam is required first (Phase 1) |
| Risk: "registering the orphan suite surfaces pre-existing failures" | **Phantom** | Measured 14/14 green. Row deleted |

### The detection was already broken — measured, not inferred

Independent of the deprecation:

- The **Class B** narrow extraction selects entries where `key == "monitor.slug"`. Against the
  live `rules/` payload it returns **0 matches**. No rule in this org has ever carried that binding.
- **Class A** asks whether a monitor's slug appears anywhere in the rules payload. Measured:
  **0 of 55** slugs appear. So Class A flags every monitor, every run — corroborated by
  `knowledge-base/legal/audits/sentry-migration-audit-2026-05-15.md`, which lists **8 of 8**.
- The cause is deliberate: `apps/web-platform/infra/sentry/issue-alerts.tf`'s header states these
  are *"PROJECT-WIDE frequency alerts … bound to no monitor"*. Cron failures route via the
  `monitor_check_in_failure` issue, never a rule naming a slug.

The replacement schema exposes the binding the old one never did: 55 of the 62 detectors are
`type == "monitor_check_in_failure"`, each carrying `dataSources[].queryObj.slug`, an **exact
55/55 set match** to the live monitors, plus `workflowIds` for attached routing (measured: empty
for all 55; org-wide only 1 detector of 62 has any workflow).

### `curl_retry` cannot retry any HTTP failure — verified with a positive control

Loop body: `result=$(curl "$@" 2>/dev/null) && break`. Without `-f`, curl exits 0 for any
completed HTTP transaction, so it breaks on attempt 1 for 410, 401, 429, 500, 502 and 504 alike.

```
curl -s  ... /no-such-endpoint-xyz/   -> status=404 curl_exit=0
curl -sf ... /no-such-endpoint-xyz/   -> status=404 curl_exit=22
```

The exact loop shape replayed against a non-2xx printed `BROKE on attempt 1`. Its own comment
claims it absorbs "500/timeout"; the timeout half works, **the 500 half never has** — which
explains the unretried Gate 3 `504`, Gate 3 `208` and org-GET `500` in the gate's history.

### Identifier-space break, and why the manifest is now retired

`rules/` ids and `workflows/` ids are **disjoint** — 30 vs 30, zero overlap — while corresponding
1:1 by name (`596863 auth-per-user-loop` ↔ `566671 auth-per-user-loop`). Repointing the fetch would
silently change the report's `<!-- ids: -->` manifest out of the rule-ID space that
`sentry_issue_alert` resource addressing consumes. Name-based mapping is forbidden (duplicate names
are legal in Sentry).

The manifest's **only** consumer is the README's adoption runbook, which extracts it at
`apps/web-platform/infra/sentry/README.md` via
`ids=$(grep -oE '<!-- ids: \[(.*)\] -->' "$latest_audit" | …)` — and that coupling is itself
tested by T7 ("manifest survives README's extraction pipeline"). That runbook is stale by 25
resources: it says *"The 4 issue-alert rules already exist in Sentry"* while `issue-alerts.tf`
declares 29 and `apply-sentry-infra.yml` plans the full root.

*(Deepen correction: an earlier draft of this plan claimed the manifest had "no live consumer".
That was wrong — the consumer exists and is tested. Retirement is still the right call, but it is a
three-part change: the emission, the runbook, and T6/T7/T10.)*

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 7590` → `state: OPEN`, no closing PRs. Premise holds.
- Owning decision is **ADR-031 — Sentry alert and cron monitor configuration as IaC**
  (`status: accepted`, 12 amendments). Nothing in its Decision or Alternatives rejects endpoint
  migration; this is an amendment, not a new ADR.
- Upstream contract confirmed at source (`src/sentry/api/helpers/deprecation.py`): emits
  `X-Sentry-Deprecation-Date` / `X-Sentry-Replacement-Endpoint`, returns `HTTP_410_GONE` inside a
  brownout, gates on `now >= deprecation_date`. The window is driven by the **runtime options**
  `api.deprecation.brownout-cron` / `-duration` — values Sentry changes unilaterally.
- **No published sunset date.** The endpoints are past deprecation and removable at Sentry's
  discretion, which is why migration (not diagnostics alone) is the fix.
- The repo has already met this brownout and misread it: `apps/web-platform/infra/sentry/versions.tf`
  records that *"on 2026-07-17 Sentry briefly returned 410 'This API no longer exists' on the legacy
  issue-alert read endpoint"* and concludes *"the 410 was transient"*. It was a brownout. That is the
  second occurrence, and the strongest argument for the tripwire.

### Property List (Phase 0.6b)

1. A PR touching Sentry config gets a truthful verdict, regardless of when in the hour it runs.
2. When the audit fails, the CI log alone identifies the cause.
3. A future Sentry deprecation becomes visible *before* it starts returning 410.
4. Orphan classes report findings true of the org, not artifacts of a predicate that cannot match.
5. The four destination-controllability gates keep working exactly as today.
6. Regression coverage for the above executes in CI.

### Cut List (Phase 0.6b, extended by plan review)

| Mechanism | Property | Why cut |
|---|---|---|
| Brownout-sized retry | (1) | Window is a Sentry-owned option; the migrated endpoints carry no deprecation headers at all |
| Bespoke header-capture helper | (2)(3) | `curl -D` is the repo idiom; extend `curl_retry` |
| `-w '%{http_code}'` inside `curl_retry` | (2) | **P0** — collides with Gates 2/3 and corrupts Gate 1 + both fetches. `-D` alone carries the status |
| Phase 8 test-runner registration + AC7 | (6) | Premise false — already glob-registered; the edit would double-register and red the required check |
| `<!-- id_space: workflow -->` marker, README reconciliation, AC11 | none | Buys no listed property; the runbook it protects is stale by 25 resources |
| Class A per-slug `<details>` list | (4) | Duplicates the report's existing `## Monitors` table |
| Cursor-following on `workflows/` | (1) | Does not grow with monitors. Retained for `detectors/` and `monitors/`, which do |

### Relevant institutional learnings

- `knowledge-base/project/learnings/2026-05-17-sentry-eu-region-host-rewrites-slugs-with-eu-suffix.md`
  — org-scoped paths must use the org subdomain. Both new endpoints are org-scoped.
- `knowledge-base/project/learnings/integration-issues/2026-04-29-supabase-auth-probe-and-sentry-rule-api-quirks.md`
  — Sentry permits duplicate names; address by id. Forbids name-mapping workflow ids to rule ids.
- `knowledge-base/project/learnings/2026-03-14-curl-response-header-capture-pattern.md`
  — `curl -D "$tmpfile"` is the pattern when headers are load-bearing.
- `knowledge-base/project/learnings/2026-03-19-ci-squash-fallback-bypasses-merge-gates.md`
  — `do_A || do_B_unsafe` inverts the security model. On a 410, fail loudly.
- `knowledge-base/project/learnings/2026-06-12-detector-cron-must-route-its-own-self-failure-ops-and-register-new-sentry-alert-in-apply-target.md`
  — a detector whose failure is invisible recreates the gap it closes.
- `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`

### Verified facts about the callers

All three set `SENTRY_PROJECT` from a repo secret. Note `reusable-release.yml` checks only
`SENTRY_AUTH_TOKEN` presence, not `SENTRY_PROJECT` — so an empty secret there would silently flip
the org branch live in production (moot once the branch dissolves, Decision 1).

| Caller | Anchor | State half | Non-zero exit |
|---|---|---|---|
| `sentry-audit-gate.yml` | `run: bash apps/.../sentry-monitors-audit.sh` | none | Hard fail (blocks the PR check) |
| `apply-sentry-infra.yml` | `export SENTRY_STATE_REQUIRED=1` then the script | required + slugs file | Hard fail **before** the Terraform plan step |
| `reusable-release.yml` | `AUDIT_OUT_DIR="${RUNNER_TEMP}/sentry-audit" \` | none | `set +e` → `::warning::` → `exit 0`, and **the report is not uploaded** |

The PR gate has **no `upload-artifact` step** and leaves `AUDIT_OUT_DIR` unset, so the report is
written into a throwaway runner checkout and discarded. No reviewer has ever seen it on that path.
Nothing has been committed to `knowledge-base/legal/audits/` since 2026-05-17.

## Hypotheses

Verdicts from the gate's own failure logs (`gh run view --log-failed`), not from reasoning.

| # | Hypothesis | Verdict | Evidence |
|---|---|---|---|
| H1 | Deprecated rules endpoint 410s inside a brownout | **CONFIRMED** | 7 runs fail with `is not a JSON array` + `{"message":"This API no longer exists."}` (2026-07-17, 08-02, 08-13 ×3, 08-16 ×2) |
| H2 | CI secrets drifted from Doppler | **REFUTED** | Both tokens authenticate; org GET, project GET and the write probe all pass in the same runs whose rules fetch 410s |
| H3 | Transient Sentry 5xx on the gate probes | **CONFIRMED, separate cause** | Gate 3 `504` (08-06), Gate 3 `208` (05-26), org-GET `500` (05-26) — none retried |
| H4 | Brownout is `0 */2 * * *`, 120 s | **UNKNOWN** | 6/7 failures ≤3 min past an hour boundary of mixed parity (09, 11, 12, 20, 23); 10:34:35 fits no hourly model. The schedule is a Sentry runtime option we cannot read |
| H5 | Classes A/B are dark because the endpoint is dark | **REFUTED — wrong, not dark** | 0 `monitor.slug` matches and 0/55 slug appearances on a live 200 payload; 8/8 in the May report |

H4 stays UNKNOWN deliberately. Six of seven points fitting "just past the hour" is suggestive, not
decisive, and the deciding datum is not readable from here. Recording it CONFIRMED would license a
window-sized retry, which Decision 3 rejects on exactly that ground.

### Network-Outage Deep-Dive (deepen Phase 4.5)

The gate fired on `504` and `timeout` appearing in H3. Per `hr-ssh-diagnosis-verify-firewall` the
L3→L7 layers must be answered before any service-layer hypothesis is accepted. Answered below, with
the artifact for each — "obvious" is not a verification.

| Layer | Verified? | Artifact / reasoning |
|---|---|---|
| **L3 — firewall allow-list** | **N/A, structurally** | There is no host and no allowlist. The client is a GitHub-hosted runner (and, for the probes above, a workstation) calling a public vendor API over the internet; no egress IP is enrolled anywhere, so admin-IP drift — the #2681 failure this layer exists to catch — has no surface here |
| **L3 — DNS / routing** | **Ruled out by construction** | Five of six endpoints returned `HTTP/2 200` from `${SENTRY_API_HOST}` in the *same probe loop, same second, same token* as the deprecated ones. A resolution or routing fault cannot be endpoint-selective within one host |
| **L7 — TLS / proxy** | **Verified** | `curl -s -D -` returned `HTTP/2 200` with a valid chain to `${SENTRY_API_HOST}`; the `link:` pagination headers are Sentry-issued and well-formed. A CDN/edge fault does not synthesize `x-sentry-deprecation-date` with a correct per-endpoint replacement path |
| **L7 — application** | **This is the causal layer** | The vendor names the cause in its own response headers, and the mechanism is confirmed in upstream source (`src/sentry/api/helpers/deprecation.py`: `HTTP_410_GONE` inside a brownout window, gated on `now >= deprecation_date`) |

The discipline's point is to stop a service-layer fix being proposed while a lower layer is
unverified. Here the causal layer is established by an artifact the lower layers cannot produce — a
410 carrying an endpoint-specific `x-sentry-replacement-endpoint`, on one endpoint family, while its
siblings answer 200 on the same connection. That is stronger than any L3 probe could be.

H3's 504/500/208 observations are a **separate, genuinely transient vendor-side** class at the same
L7 boundary. They are not a connectivity fault either, and the plan's response to them is the
status-aware retry in Decision 3 — which today retries none of them.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — this is a CI gate. The felt
effect is a Sentry-touching PR that cannot merge on a correct diff, or a blocked Sentry IaC
deployment.

**If this leaks, the user's data is exposed via:** no new exposure path. The indirect vector is
Gate 4 (`audit_dsn_org_id_matches_token_org_id`), the control that detects runtime error telemetry
being shipped to a Sentry org outside our control. A gate that is red-by-default trains its audience
to ignore it.

**Correction from review:** v1 of this plan asserted the four gates "are unchanged by this plan and
run before `fetch_rules()`". That was **false** — Gates 1–3 call `curl_retry` and Gate 4 consumes
`gate1_body`, so the Phase 2 wrapper rewrite is inside their blast radius. This is why Decision 3
now pins the `-D`-only implementation and adds a stdout-contract AC.

**Brand-survival threshold:** `aggregate pattern` — a degraded accountability control over time,
not a single user's data in a single incident.

## Files to Edit

- `apps/web-platform/scripts/sentry-monitors-audit.sh` — transport seam, `curl_retry` rewrite,
  tripwire, fetch migration, diagnostic, orphan remap, manifest retirement, header corrections
  (including the now-false "joins the two on `monitor.slug` references" description and the
  token-naming trap).
- `apps/web-platform/scripts/sentry-monitors-audit.test.sh` — T15–T21 plus refixturing of the
  existing rules-shaped tests.
- `apps/web-platform/infra/sentry/README.md` — retire the stale first-time adoption runbook.
- `.github/workflows/reusable-release.yml` — its failure `::warning::` quotes an error string the
  script no longer emits and points at a `de.sentry.io` default corrected in May; after this plan it
  would be the only message a release-path reader sees.
- `.github/workflows/sentry-audit-gate.yml` — remove **both** false required-check claims (header
  line 1 and line 18).
- `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` — amendment, plus
  in-place correction of any deprecated-path references in the body.
- `scripts/lint-shell-capture-exit.baseline.txt` — only if new call sites add findings.

**Deliberately NOT edited:** `scripts/test-all.sh` (the suite is already glob-registered; an
explicit line would double-register and red the required `test` check).

## Files to Create

None.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --limit 200` returned 64 issues; none
reference any file above.

## Decisions

### Decision 1 — endpoint mapping, and the branch dissolves

`x-sentry-replacement-endpoint` names a different successor per endpoint:

| Current call | Live status | Replacement | Live status |
|---|---|---|---|
| `projects/{org}/{proj}/rules/` | 200 + deprecation headers | `organizations/{org}/workflows/` | 200, 30 rows, no deprecation headers |
| `organizations/{org}/alert-rules/` | 200 + headers, `[]` | `organizations/{org}/detectors/` | 200, 62 rows, no deprecation headers |

**Both replacements are org-scoped**, so `fetch_rules()`'s `SENTRY_PROJECT` branch has no reason to
exist. Collapse to two unconditional fetches, `fetch_workflows()` and `fetch_detectors()`. This
deletes, in cascade: the branch, the "which branch ran" diagnostic field, the two-branch AC anchors,
and the branch clause in Guard 2. `SENTRY_PROJECT` survives — it still feeds Gate 2, Gate 3 and the
report frontmatter.

**Consequence to fix:** the report frontmatter prints `- **Project filter:** web-platform`, which
after migration asserts a scope the fetch no longer applies. Correct it to name the actual scope.

**Pagination — cursor-following is mandatory, not an option.** Measured: `per_page` caps at 100,
`per_page=10` returns a `rel="next"; results="true"` cursor, and the script paginates nothing.
Volumes are workflows 30, monitors 55, detectors 62. `detectors/` grows **1:1 with cron monitors**
(55 of its 62 rows are `monitor_check_in_failure`), and monitors went 8 → 49 → 55 in two months.

A loud-failure-on-truncation arm would therefore, by ordinary growth, fail the audit *before* the
Terraform plan step on the deployment path — and `apply-sentry-infra.yml` is the only path that
deploys the Terraform fix. That is the same "the detector blocks its own cure" deadlock the script's
own state-half comment spends twenty lines warning about. So: **follow the cursor for `detectors/`
and `monitors/`** (the latter feeds Class D, the only class with teeth, where silent truncation fails
*open* on unreclaimable spend — #6589's exact failure). `workflows/` does not grow with monitors and
may keep the simple loud check. AC11 is single-valued accordingly — a disjunctive AC discriminates
nothing.

**Precedent (deepen Phase 4.4) — and a security hazard the plan had missed.** Link-header cursor
following is **not novel** here: `scripts/zot-inventory.sh` already implements it, hardened, and its
`link_next` header comments record why. Adopt its three properties rather than re-deriving them:

1. **Never follow the Link URL as given.** Sentry's `Link` headers are *absolute*
   (`https://sentry.io/api/0/organizations/…?&cursor=…`). `zot-inventory.sh` rejects any non-rooted
   target and any target containing `@`, with the attack documented in-file and **measured against
   curl 8.18.0**: a header of `Link: <@attacker.tld/…>; rel="next"` makes curl parse everything
   before the `@` as userinfo, resolving to `attacker.tld` — a real off-box request carrying
   production credentials, whose response then drives further requests. This audit sends
   `SENTRY_IAC_AUTH_TOKEN` on every call, so the same shape would exfiltrate it. **Extract only the
   `cursor` parameter and rebuild the URL from the already-validated `$api_host`** — never pass the
   header's URL to curl. (Its own note is worth heeding: the canary test could not catch this,
   because every fixture Link was relative, so the assertion able to falsify it was never exercised.
   T20's fixtures must include an absolute and an `@`-bearing Link.)
2. **A `MAX_PAGES` ceiling** (`zot-inventory.sh` defaults to 50 via `ZOT_INVENTORY_MAX_PAGES`), so a
   cursor loop cannot run unbounded against a misbehaving endpoint.
3. **A truncation counter that poisons the clean verdict.** `zot-inventory.sh` increments
   `LINK_UNFOLLOWED` on every refusal and `die`s rather than emit `outcome=ok` alongside
   `enumeration_complete=false` — *"a summary field that says clean beside a completeness field that
   says nothing was measured is the contradiction this marker exists to make impossible."* That is
   exactly the property Decision 2's extraction guard needs; carry the same shape so a partially
   enumerated org can never render the clean-state string.

**Partial-fetch posture must be declared.** The rules side now makes two calls where it made one. If
`detectors/` fails while `workflows/` succeeds, Classes A and B must be marked **not evaluated** and
the report must not emit the clean-state string. Collapsing "could not check" into "clean" in an
Article 30 artifact is the failure mode this whole plan exists to remove.

### Decision 2 — remap the orphan classes onto the binding that actually exists

The `monitor.slug` binding the old jq targeted **does not exist in this org and never did**. It did
not fail to survive the migration.

| Class | New predicate | Measured today |
|---|---|---|
| A — monitor without paired routing | `monitor_check_in_failure` detector whose `workflowIds` is empty | **55 of 55** |
| B — routing references a missing monitor | cron detector slug with no live monitor row | **0** (exact set match) |
| C — routing with no actions | workflow where `[.triggers.actions[]?] + [.actionFilters[]?.actions[]?]` is empty | **0** |

Class A at 55/55 is a true statement about the org, not a bug in the predicate. But 55 bullets every
run is noise, and the report already lists every slug in its `## Monitors` table. So: **emit a count
plus a machine-checked invariant**, not a list.

The invariant, not the literal, is the signal: `class_a_count == cron_detector_count`. A literal
baseline of 55 goes stale the moment monitor #56 lands, and cannot distinguish ordinary growth from a
real routing attachment (54) from an extraction failure (0). The invariant distinguishes all three.
It lives in the suite where something reads it — **not** as prose in ADR-031, which nothing reads.

**Fail-closed guard, carried from Class D.** Under the old predicate an auth/scope/endpoint
regression returning `[]` produced a loud artifact (all 55 flagged). Under the new one it produces
zero orphans, a clean report and exit 0 — a quiet, green, wrong answer. The script already contains
the correct pattern for this class, in Class D's `declared_slugs` check. Carry it: **zero cron
detectors while `monitors_json` is non-empty is an extraction failure**, not a clean org.

Whether to delete Class A entirely (dhh's recommendation, on strong measured grounds) is recorded as
**UC-2** in `decision-challenges.md` — it is a scope reduction the task brief did not request.

### Decision 3 — brownout behaviour: classify, do not ride out; and never touch stdout

No retry sized to the brownout window:

1. After migration the target endpoints carry **no** deprecation headers, so there is nothing to
   ride out. Property (1) is bought by the migration.
2. The window is a Sentry-side runtime option; H4 records we have not established its value.
3. A brownout 410 and a post-sunset 410 are byte-identical, so a retry that swallows the first
   necessarily masks the second.

Make `curl_retry` **status-aware**, which also repairs H3:

- Retry `429` and `5xx`. Never retry `410`/`404`/`401`/`403`.
- **Classify only — never exit.** v1 said "on 410, fail immediately", which contradicted the same
  decision's "always return the last attempt's output, exit 0" and was unimplementable anyway
  (`curl_retry` does not know which fetch called it). Every call site is `x=$(curl_retry …)` under
  `set -euo pipefail`, so a non-zero return aborts at the assignment — the exact cryptic-exit-28
  failure the existing comment block exists to prevent. The diagnostic belongs at the shape check.
- **Publish status and headers through exported shell variables**, e.g. `CURL_RETRY_LAST_STATUS` /
  `CURL_RETRY_LAST_HDR`, set by the wrapper and read by the shape check. Without this side channel
  the diagnostic has no contract to consume.

  **Precedent (deepen Phase 4.4):** this global-out shape is already canonical in the repo —
  `http_get()` in `scripts/zot-inventory.sh` sets `HTTP_CODE` / `HTTP_BODY` / `HTTP_HDR` for exactly
  this reason, and its sibling `link_next` documents the failure that forced it: returning the value
  on stdout pushed every call site into `$( )`, a subshell, where the counter increment was silently
  discarded — *"a truncated sweep emitted `enumeration_complete=true`"* while the suite stayed green.
  Mutating state in a function whose result is consumed via command substitution is the trap; the
  global-out contract is the repo's answer to it.

  Note the one place the precedent does **not** transfer: `http_get` uses `--output` and
  `--write-out` freely because *all* its callers share one contract (body to a file, status on
  stdout). `curl_retry`'s callers do not — Gates 2/3 read stdout as the status while Gate 1 and the
  fetches read it as the body — which is precisely why `-w`/`-o` are forbidden inside this wrapper
  and `-D` is the only safe capture.

**Capture with `-D` only. Never add `-w` or `-o` inside the wrapper.** Measured: duplicate `-w` →
last wins; and `curl_retry`'s stdout is polymorphic — Gates 2/3 pass their own
`-o /dev/null -w '%{http_code}'` and read stdout as the **status**, while Gate 1, `fetch_monitors`
and `fetch_rules` read it as the **body**. A wrapper `-w` after `"$@"` corrupts every body
(`[...]200` → the shape check fails on a healthy 200, firing the new diagnostic against a working
endpoint); before `"$@"` it is overridden and the wrapper classifies nothing. `-D` is
stdout-neutral: verified that `-D` yields the status line while the caller's `-w` still prints
`CALLER_W=200`. Parse the **last** `HTTP/` line (redirects emit several).

**Retry must be idempotency-aware.** Gate 3 is a non-idempotent `POST /releases/` with
`probe_ver` computed **once, outside** the wrapper, and its check is `!= "201"`. Sentry returns
**208** when the release already exists. So retrying a 5xx whose write landed server-side yields a
deterministic 208 and a false "token may lack project:releases scope" diagnosis — a failure mode
that *cannot* happen today, because the wrapper never retries. Restrict status-based retry to safe
methods and leave write probes on transport-only retry. (Accepting `201|208` is the alternative, but
the header records that branch was deliberately dropped, so re-adding it needs an explicit ADR note,
not a silent edit.)

### Decision 4 — retire the id manifest and its runbook

Rule ids and workflow ids are disjoint, so repointing the fetch would silently change the manifest's
meaning. But the manifest has no live consumer: first-time adoption is complete (29
`sentry_issue_alert` resources, full-root plan), and the README runbook is stale by 25 resources.

Retire it: drop the `<!-- ids: -->` emission, and replace the README's adoption section with two
sentences stating that first-time adoption is complete and that rule ids for any future adoption are
read from the Sentry API or the Terraform provider. This removes the marker, the reconciliation
phase, its AC, and existing tests T6/T7/T10 that only test the manifest. If the reviewer prefers to
keep the manifest as a diagnostic, keep the single `printf` and state its identifier space in the
report header — but do not build a marker/AC/README apparatus around a dead feed.

### Decision 5 — make the failure name its own cause, and give the tripwire a route

On any non-array payload, emit: HTTP status, resolved `api_host`, the full URL, which fetch, and —
when present — `x-sentry-deprecation-date` and `x-sentry-replacement-endpoint`. Keep the 500-byte
body head. Add a **verdict field** keyed on the classification `curl_retry` already computes, because
"5xx exhausted" and "410 deprecated" need different next actions (re-run vs migrate) and currently
render identically.

**The tripwire.** Any response carrying `x-sentry-deprecation-date` emits a warning naming endpoint,
date and replacement — *even on a 200*. This deprecation was announced in headers from 2026-05-14,
and `versions.tf` shows the repo met it on 2026-07-17 and wrote it off as transient. Nothing read the
headers.

**But a `::warning::` on a green check has exactly the signal strength that already failed.** The
gate job has `permissions: contents: read`, so it *cannot* file an issue; the release caller
downgrades everything to a warning on a green job; Better Stack is ruled out by this script's own
job-log-only constraint. So the tripwire needs an escalation ladder with a date, which it can compute
because the header carries one: warn while the deprecation date is distant, and **fail** once it is
within a defined window (or already past, as it is today for the endpoints we are leaving). Pin the
window in the ADR amendment, and state the escape hatch for the case where it fires on an endpoint
with no replacement yet.

### Decision 6 — required-check recommendation: still no, but for one reason fewer

**Recommendation: do NOT make `Sentry Audit Gate` required in this PR.**

v1 offered a compensating control that does not exist: "register the orphan suite so its 14 tests run
under the required `test` check". They already do. The recommendation is re-derived without it.

What survives, and is sufficient:
- The job calls the **live Sentry API**, and its own history holds three vendor-caused reds in three
  months (500, 504, timeout). Requiring it hands merge control to a vendor's uptime.
- It is absent from `scripts/required-checks.txt`, the canonical JSON, and
  `infra/github/ruleset-ci-required.tf` — while its header falsely claims required status in **two**
  places. Correct the claim; do not change the status.
- Adding it would be *permissible* under the #6049 auto-fabrication guard (the gate's trigger paths
  and `ALLOWED_PATHS` intersect emptily, same shape as `sentry-destroy-required`) — but permissible
  is not wise.

**Follow-up, specified rather than gestured at.** File during Phase 5 with title *"Split Sentry Audit
Gate into a hermetic gates job and an advisory live-API job"*, labels `type/chore` +
`domain/engineering`, body citing this plan and UC-3, and a first acceptance criterion:
*"`AUDIT_MODE=gates` exists and `apply-sentry-infra.yml` uses it."* Note the blocker the follow-up
must solve: the script's own header records that the 4 gates *"issue real HTTP calls that fixtures
cannot mock"*, so a "hermetic half" of today's workflow would assert nothing the gates cover. The
split has to come first.

The deeper structural recommendation — decoupling the fail-closed gating half from the advisory
reporting half via `AUDIT_MODE=gates` — is recorded as **UC-3**. It would reduce this PR's blast
radius on the deployment path to zero and dissolve the pagination, Gate-3-retry and partial-fetch
hazards rather than compensating for each.

## Implementation Phases

Tests precede implementation per `cq-write-failing-tests-before`.

### Phase 0 — preconditions (no code)

1. Probe all six endpoints through `doppler run --project soleur --config prd` using
   **`SENTRY_IAC_AUTH_TOKEN` specifically** (the token CI uses; Doppler `prd` also holds a different
   `SENTRY_AUTH_TOKEN`). Record status + headers in the PR body, naming the token. If `rules/`
   answers 410 at that moment, note it as a brownout observation, not a schedule.
2. Confirm `workflows/` and `detectors/` return arrays and carry **no** deprecation headers, and that
   `SENTRY_IAC_AUTH_TOKEN` can read both — they are new org-scoped surfaces and may need scopes the
   project-scoped path did not. If either has gained deprecation headers, stop and re-plan.
3. Baseline is already measured: `14 passed, 0 failed`. No step needed.

### Phase 1 — transport seam (must precede every test)

The `SENTRY_FIXTURE_*` seams `cat` a file and `return` **before curl runs**, so they cannot express a
status, a header or a retry sequence. Add a transport-level seam — `CURL_BIN="${CURL_BIN:-curl}"`
inside `curl_retry`, or a `curl` stub prepended to `PATH` (the suite already does
`env -i PATH="$PATH"`). Define its contract: how a test declares a status sequence, headers and body
per URL. Document it in the script header's "Test injection" block.

**Precedent (deepen Phase 4.4): not novel.** Several suites already stub `curl` this way — see
`apps/cla-evidence/scripts/upload-evidence.test.sh`,
`apps/cla-evidence/scripts/upload-bypass.test.sh`, and
`apps/web-platform/infra/doppler-download-error-channel.test.sh`. Read one before inventing a
contract and match the established shape rather than adding a fourth dialect.

The seam must let a single test express: a **status sequence** across attempts (for T18's
500-then-200 and 500-then-208), **response headers** written to the `-D` target (T16/T17/T20), and a
**body** on stdout — because those three are exactly what the file-fixture seam cannot reach.

### Phase 2 — `curl_retry`: `-D`-only capture, status classification, side-channel metadata

Per Decision 3. Retry `429`/`5xx` on safe methods only; never `410`/`404`/`401`/`403`; never exit;
never add `-w` or `-o`. Export status + header-file path for the shape check. Clean up the header
temp file on every path. Keep the bounded 3-attempt ceiling.

### Phase 3 — deprecation tripwire + escalation

Check captured headers for `x-sentry-deprecation-date`; warn per distinct endpoint, deduped across a
paginated fetch; escalate to failure inside the configured window per Decision 5.

### Phase 4 — fetch migration, pagination, diagnostic, orphan remap

Collapse the branch into `fetch_workflows()` + `fetch_detectors()`. Add cursor-following for
`detectors/` and `monitors/`. Add `SENTRY_FIXTURE_DETECTORS` — and make the detectors fetch **inherit
fixture mode**: when `SENTRY_FIXTURE_RULES`/`_MONITORS` is set and `_DETECTORS` is not, serve `[]`
rather than reaching the network, or the 13 existing tests (which set only MONITORS+RULES) start
making live calls and go red. Replace the bare shape-check error with the Decision 5 payload. Remap
A/B/C per Decision 2, including the fail-closed extraction guard and the not-evaluated states. Retire
the manifest per Decision 4. Correct the `Project filter:` frontmatter, the hardcoded clean-state
string (it enumerates the old class definitions verbatim), and the `## Alert Rules` heading. Verify
the `## Alert Rules` table renderer against the workflows shape — a `null` name column is a quiet
report regression.

### Phase 5 — docs, workflow corrections, follow-up issue

ADR-031 amendment (endpoint mapping and its header provenance; brownout-not-removal, citing the
2026-07-17 misread in `versions.tf`; the `curl_retry` defect and its repair; the tripwire and its
escalation window). Correct deprecated-path references in the ADR body in place, not only by
appending. Fix the script header's now-false *"joins the two on `monitor.slug` references"*
description and add the token-naming trap. Remove both required-check claims from
`sentry-audit-gate.yml`. Fix the stale `reusable-release.yml` warning text. File the Decision 6
follow-up.

## Guard Contract

### Guard 1 — deprecation tripwire

**Property.** Every Sentry response carrying an `x-sentry-deprecation-date` header produces a warning
naming that endpoint, regardless of status code or call site.

**Assembly.** The chokepoint is `curl_retry`. The guard attaches there, and asserts that **no Sentry
call bypasses it** — with the known-by-design bypasses (the region-probe loop and the Gate 3 cleanup
`DELETE`, both bare `curl`) enumerated as exempt with reasons. The enumeration is what is checked, not
a snapshot of today's call list.

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|---|---|
| 1 | Add a Sentry call site using bare `curl` instead of `curl_retry` | A call outside the chokepoint is unmonitored — the assembly assertion, not a member check |
| 2 | Add a **second** deprecated endpoint after a compliant first | Must warn for both; warning only for the first is the stop-at-first-member defect |
| 3 | Delete `-D` from `curl_retry` so no headers are captured | **Guard's own dispatch.** The tripwire can never fire; a run reporting "0 endpoints checked" must fail. This floor lives in the **suite**, not the script — a script-side non-zero here would add a fail-closed condition in front of the Terraform plan step that fires on any environmental header-capture quirk |
| 4 | Make the header match case-sensitive | `-D` preserves wire casing; `X-Sentry-Deprecation-Date` must still match |

**Harness rows.**
- Must-RED: delete the assertion body from the tripwire test, leaving its name and `echo` intact →
  the suite must fail, not pass a test asserting nothing.
- Must-PASS: deprecation headers on a **200** — a non-canonical input the contract permits — must warn
  and still exit 0.

### Guard 2 — payload shape + self-naming diagnostic

**Property.** Any payload that is not a JSON array aborts with a message containing the HTTP status,
resolved host, source URL and — when present — the deprecation headers.

**Assembly.** The shape-validation loop and every `fetch_*` feeding it. Structural: every payload
entering the loop must carry its status metadata, so adding a third payload without it is a failure,
not an untested addition.

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|---|---|
| 1 | Add the detectors payload to the loop without status metadata | **Second member after a compliant first** — the loop must quantify over every payload |
| 2 | Revert the diagnostic to the bare `is not a JSON array` string | The defect being fixed; a suite green here discriminates nothing |
| 3 | Print the status but drop the replacement-endpoint header | Partial diagnostics are the defect — the message must carry its own fix |
| 4 | Make the shape check accept an object | **Guard's own dispatch.** An accepting check never reaches the diagnostic, so the 410 fixture passes silently |

**Harness rows.**
- Must-RED: weaken the content assertion to `grep -q ERROR` — a predicate the *old* code also
  satisfies → the suite must fail, proving it discriminates fix from bug.
- Must-PASS: a valid empty array → exits 0 via the "no alert rules" branch, not the diagnostic.

### Guard 3 — retry classification and stdout neutrality

**Property.** `curl_retry` retries transient statuses on safe methods only, never retries permanent
ones, and leaves stdout byte-identical to bare `curl "$@"` for both call-site shapes.

**Assembly.** The classification branch, quantified over status classes **and** HTTP method — plus the
stdout contract at both shapes (body-returning: Gate 1, `fetch_*`; status-returning: Gates 2, 3).

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|---|---|
| 1 | Add `410` to the retry set | Masks a permanent removal as a flake |
| 2 | Remove `5xx` from the retry set | Regresses to today's behaviour, where H3's 500 and 504 were never retried |
| 3 | Set `max_attempts=1` so the loop never iterates | **Guard's own dispatch.** A retry wrapper that cannot retry must not report success |
| 4 | Add `-w '%{http_code}'` inside the wrapper | The P0 this plan exists to avoid — Gate 1's body becomes `{…}200` and both fetches fail their shape check on a healthy 200 |
| 5 | Enable status retry for the Gate 3 POST | A retried non-idempotent write returns 208 and Gate 3 hard-fails with a false scope diagnosis |

**Harness rows.**
- Must-RED: assert on attempt *count* rather than the retried/not-retried decision → the suite must
  fail, since a count is satisfiable by a wrapper retrying the wrong classes.
- Must-PASS: a `200` first response → zero retries, exit 0, stdout byte-identical to bare `curl`.

## Observability

```yaml
liveness_signal:
  what: "Sentry Audit Gate workflow conclusion on PRs touching the Sentry surface; audit report
         artifact uploaded per release by reusable-release.yml"
  cadence: "per matching PR (~50/month measured); per release"
  alert_target: "GitHub Actions check status + ::warning:: annotations"
  configured_in: ".github/workflows/sentry-audit-gate.yml, .github/workflows/reusable-release.yml"

error_reporting:
  destination: "GitHub Actions job log + check conclusion (observability layer 5 — CI). This script
                runs only on GHA runners; per the Class D marker comment, SOLEUR_* markers here are
                job-log only and are NOT shipped to Better Stack (vector.toml scopes every source to
                the Hetzner host SYSLOG_IDENTIFIER). The load-bearing signal is the non-zero exit."
  fail_loud: true

failure_modes:
  - mode: "Deprecated endpoint returns 410 (brownout or post-sunset)"
    detection: "curl_retry captures 410 + x-sentry-deprecation-date; diagnostic names status, host,
                URL, fetch and replacement endpoint, plus a verdict field"
    alert_route: "non-zero exit -> red check on the PR; on the release caller, ::warning:: only"
  - mode: "Endpoint newly deprecated but still serving 200"
    detection: "tripwire matches x-sentry-deprecation-date on a successful response"
    alert_route: "::warning:: while the date is distant; non-zero once inside the escalation window"
  - mode: "Transient Sentry 5xx/429 on a safe-method probe"
    detection: "curl_retry status classification; retried with backoff, exhaustion surfaces at the
                shape check with the final status and a re-run verdict"
    alert_route: "non-zero exit after retries exhausted"
  - mode: "Gate 3 write probe returns 208 after a retried 5xx"
    detection: "write probes excluded from status retry; a 208 can therefore only arise from a true
                pre-existing release, which the existing != 201 check reports"
    alert_route: "non-zero exit before the Terraform plan step"
  - mode: "Collection paginates beyond the first page"
    detection: "rel=\"next\"; results=\"true\" in the captured Link header"
    alert_route: "cursor followed for detectors/ and monitors/; loud non-zero for workflows/"
  - mode: "detectors/ fails while workflows/ succeeds"
    detection: "per-fetch status metadata; Classes A and B marked not-evaluated"
    alert_route: "report omits the clean-state string and names the unevaluated classes; exit code
                  per the posture declared in Decision 1"
  - mode: "Orphan extraction returns nothing against a non-empty org"
    detection: "zero cron detectors while monitors_json is non-empty -> extraction failure, modelled
                on Class D's declared_slugs guard"
    alert_route: "non-zero exit naming the extraction failure, never a clean report"
  - mode: "Article 30 evidence not attached to a release"
    detection: "reusable-release.yml uploads the report only on exit 0, so any new fail-closed
                condition silently drops the evidence asset"
    alert_route: "::warning:: in the release job — enumerated here because it is currently invisible"

logs:
  where: "GitHub Actions job logs; report markdown in knowledge-base/legal/audits/ (local runs) or
          the release asset (CI runs). NOTE: the PR gate uploads no artifact, so the report has no
          reader on that path."
  retention: "GHA default (90 days); release assets indefinitely"

discoverability_test:
  command: "bash apps/web-platform/scripts/sentry-monitors-audit.test.sh"
  expected_output: "final line reads 'Results: N passed, 0 failed' with N > 0, and the script
                    exits 0"
  credentials_required: "none — hermetic via the SENTRY_FIXTURE_* file seams and the Phase 1
                         transport seam; makes no network call"
```

Credentialed live probe, deliberately **not** the discoverability test:

```
doppler run --project soleur --config prd --command 'curl -s -D - -o /dev/null \
  -H "Authorization: Bearer $SENTRY_IAC_AUTH_TOKEN" \
  "https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/workflows/"'
```

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-031**. A new ordinal is not warranted: this changes which endpoints an already-decided
integration reads. Twelve amendments is a sign the ordinal is correctly scoped and actively
maintained. No new ordinal is claimed, so the collision risk does not apply.

The amendment records: the endpoint mapping and that it came from Sentry's own headers; that the
family serves brownouts rather than being removed, citing `versions.tf`'s 2026-07-17 "transient"
misread as the precedent; the Class A predicate change and the **invariant** that replaces the old
one; the `curl_retry` HTTP-status defect and its repair; the idempotency restriction on write probes;
and the tripwire with its escalation window. The amendment must **correct deprecated-path references
in the ADR body in place**, not only append.

Deliberately *not* in the ADR: the literal Class A count. A value expected to drift, pinned as prose
in a 605-line document, goes stale silently and nothing reads it. The invariant lives in the suite.

### C4 views

**No C4 impact.** From reading all three model files (`model.c4`, `views.c4`, `spec.c4`) and
enumerating:

- **External human actors:** unchanged. The paging edge from `sentry` is untouched.
- **External systems / vendors:** unchanged. `sentry` is already a `system` with `#external` and
  already appears in both views that carry it. No new vendor.
- **Containers / data stores:** unchanged. The audit is a CI script, not a modelled container.
- **Access relationships:** unchanged. The `github -> sentry` edge already covers CI as "both an
  emitter and the applier"; its technology string stays accurate — same channel, same token,
  different paths.

One model description is **corroborated, not falsified**: the paging edge notes a 30th UI-managed
rule, `Send a notification for high priority issues`. The live `workflows/` payload contains exactly
that entry with matching conditions and email action, so 30 = 29 IaC + 1 UI-managed holds under the
new endpoint. The model's counts (`55 cron monitors`, `11 from CI / 44 from webapp`) are parity-gated
by `plugins/soleur/test/c4-count-parity.test.sh` and will fail loudly rather than stale.

## Encryption Posture

**Skipped — detection did not fire.** No persistent store introduced (no `.tf`, no
`supabase/migrations/*.sql`, no `cloud-init*.yaml`, no `docker-compose*.yaml` in Files to Edit) and no
new cross-component connection. The change alters URL paths on an existing outbound HTTPS call.

## GDPR / Compliance

The canonical regulated-surface regex does not match, and none of triggers (a)–(d) fire.

Two compliance-adjacent notes for the reviewer, both surfaced by review rather than by the gate:

1. **Content.** The report is the Article 30 PA8 evidence artifact, and Decision 2 changes what its
   Orphans section asserts (Class A goes 8/8 → 55/55 under a different predicate). The change makes
   it *more* accurate, but the artifact must carry its own provenance — source endpoints and the
   orphan-predicate generation — so a future reader diffing the committed report series can see that
   the predicate changed rather than the org.
2. **Availability.** `reusable-release.yml` uploads the report **only if the script exits 0**. Every
   new fail-closed condition this plan adds therefore silently stops Article 30 evidence attaching to
   releases, downgraded to a warning in a green job. Enumerated in `failure_modes`; the reviewer
   should decide whether a missing evidence asset is acceptable or should be tracked.

## Infrastructure (IaC)

**Skipped — no new infrastructure.** Files to Edit are one shell script, one shell test, two
workflows, one README and one ADR. Decision 6 recommends *against* the one IaC change nearby (adding
the gate to `infra/github/ruleset-ci-required.tf`) and routes it to a follow-up issue.

## Acceptance Criteria

All criteria are verifiable pre-merge, in-session or in CI. This plan has no post-merge human steps.

1. `fetch_*` constructs no request to the deprecated paths. Verify against comment-stripped code, so
   the migration notes in the header cannot satisfy it:
   ```bash
   grep -vE '^[[:space:]]*#' apps/web-platform/scripts/sentry-monitors-audit.sh \
   | grep -E '"https://\$\{api_host\}/api/0/(projects/[^"]*/rules/|organizations/[^"]*/(alert-rules|combined-rules)/)"' \
   && { echo "AC1 FAIL"; exit 1; }; exit 0
   ```
   (`combined-rules/` is never called today; that clause is forward-defence and discriminates nothing.)
2. `organizations/${SENTRY_ORG}/workflows/` and `organizations/${SENTRY_ORG}/detectors/` are both
   requested unconditionally; no `SENTRY_PROJECT` branch remains in the fetch path.
3. `curl_retry` stdout is **byte-identical to bare `curl "$@"`** for both call-site shapes
   (body-returning and `-w`-status-returning), exercised through the Phase 1 transport seam. This is
   the AC that would have caught the `-w` P0.
4. Retry classification: 429/5xx retried on safe methods; 410/404/401/403 never retried; the Gate 3
   POST never status-retried. Verified by T18 plus a 500-then-208 case asserting Gate 3 still reports
   correctly.
5. A 410 fixture with both deprecation headers produces a diagnostic containing the status `410`, the
   host, the source URL, the deprecation date and the replacement endpoint. Assert on the
   replacement-endpoint substring — a content anchor, not a bare `ERROR` token.
6. Deprecation headers on a **200** emit a warning naming the endpoint and exit 0; inside the
   escalation window the same input exits non-zero.
7. Classes A/B/C compute from the new schema. A fixture with a known orphan yields exactly that
   orphan; one with none yields none. The structured-pass count is emitted into the report so
   "structured found it" is distinguishable from "fallback found it" — without which the
   structured-first property is unverifiable.
8. Class A is reported as a count plus the invariant `class_a_count == cron_detector_count`, asserted
   in the suite. No per-slug list.
9. Zero cron detectors while `monitors_json` is non-empty exits non-zero naming an extraction
   failure, and never emits the clean-state string.
10. A partial fetch (detectors fails, workflows succeeds) marks Classes A and B not-evaluated and
    suppresses the clean-state string.
11. Pagination: a `rel="next"; results="true"` fixture causes the cursor to be followed for
    `detectors/` and `monitors/`. Single-valued — no "or fail loudly" disjunction.
11a. **Link-header targets are never followed as given.** The cursor value is extracted and the URL
    rebuilt from the validated `$api_host`. Fixtures must include an absolute-URL Link and an
    `@`-bearing Link (`Link: <@attacker.tld/api/0/…>; rel="next"`); neither may produce a request to
    any host other than `$api_host`. Assert on the requested host recorded by the transport stub —
    not on the absence of an error, which a silently-followed redirect also satisfies.
11b. A `MAX_PAGES` ceiling bounds every cursor loop, and any refusal or ceiling-hit increments a
    truncation counter that **suppresses the clean-state string**. Modelled on
    `scripts/zot-inventory.sh`'s `LINK_UNFOLLOWED` + its refusal to emit `outcome=ok` beside
    `enumeration_complete=false`.
12. The existing suite still passes and the count is ≥ 14 plus the new tests, after refixturing the
    rules-shaped tests (T3/T5/T8/T9/T11/T12) that the schema change invalidates.
13. `bash scripts/lint-orphan-test-suites.sh` still reports `0 orphaned`, and
    `bash scripts/test-all.sh --print-suite-globs` still contains
    `apps/web-platform/scripts/*.test.sh` — the glob is the suite's registration, so narrowing it is
    the regression to guard. **No explicit `run_suite` line is added.**
14. The four gates are byte-identical. Mechanical form, anchored on full lines so the range cannot
    self-match (the naive range re-triggers inside `fetch_monitors` and yields 364 lines instead of 61):
    ```bash
    gate() { awk '$0 == "if [[ -z \"${SENTRY_FIXTURE_MONITORS:-}\" ]]; then" { inb=1 }
                  inb { print }
                  inb && $0 == "fi" { exit }' "$1"; }
    git show origin/main:apps/web-platform/scripts/sentry-monitors-audit.sh > /tmp/base.sh
    diff <(gate /tmp/base.sh) <(gate apps/web-platform/scripts/sentry-monitors-audit.sh)
    ```
15. `bash tests/scripts/test-sentry-monitors-audit-class-d.sh` still passes — all 13 tests.
16. The report carries its own provenance: source endpoints and the orphan-predicate generation. The
    `Project filter:` frontmatter, the hardcoded clean-state string and the `## Alert Rules` heading
    are all consistent with the new schema.
17. ADR-031 carries the amendment, and no deprecated-path reference remains uncorrected in its body.
18. Both false required-check claims removed. **AC amended at /work (#7590):** the planned
    form was `! grep -qiE 'required.?check' <workflow>`, a bare-token negative that cannot
    distinguish a line ASSERTING required status from prose explaining the job is NOT required
    — it false-fails on the correction itself, and on the verification recipe the corrected
    header now carries. Anchored on the assertion shape instead
    (`cq-assert-anchor-not-bare-token`):
    ```bash
    ! grep -qE 'required-check for|REQUIRED-CHECK on' .github/workflows/sentry-audit-gate.yml
    ```
    Those are the two literal claims that were present; a bare-token form is strictly weaker
    here, not stronger.
19. `reusable-release.yml`'s audit-failure warning no longer quotes an error string the script cannot
    emit and no longer references a `de.sentry.io` default.
20. The Decision 6 follow-up issue exists with the specified title, labels and first AC.
21. The PR body records the re-verified endpoint table (naming `SENTRY_IAC_AUTH_TOKEN`), the
    `SENTRY_IAC_AUTH_TOKEN` → `SENTRY_AUTH_TOKEN` env-rename trap, and Decision 6's recommendation.
22. `Closes #7590` appears in the PR body.

## Test Scenarios

Fixtures synthesized per `cq-test-fixtures-synthesized-only` — shaped from the observed schema,
invented org/project/slug values, low-entropy ids. No captured production payload.

| # | Test | Fixture | Asserts |
|---|---|---|---|
| T15 | Workflows+detectors payload yields correct orphans | 2 cron detectors, one with a `workflowIds` entry, one without | exactly the unrouted slug as Class A; the routed one absent |
| T16 | 410 + deprecation headers self-names | transport seam: 410, `{"message":"This API no longer exists."}`, both headers | output contains 410, host, URL, date, replacement — not the bare shape error |
| T17 | Deprecation headers on a 200 | 200, valid array, headers present | warning naming the endpoint; exit 0 |
| T18 | Retry classification + stdout neutrality | 500-then-200; 410-only; 500-then-208 on the POST | 5xx retried on safe methods; 410 not retried; POST not status-retried; stdout byte-identical to bare curl at both shapes |
| T19 | Class B against the detector binding | detector slug with no matching monitor | that slug as Class B; a generic tag value is not |
| T20 | Pagination followed, not truncated | Link header with `rel="next"; results="true"` | cursor followed for detectors/monitors; full set audited |
| T20b | Hostile Link target refused | absolute-URL Link, and `Link: <@attacker.tld/api/0/…>; rel="next"` | no request to any host but `$api_host` (assert the stub's recorded host); truncation counter incremented; clean-state string suppressed |
| T20c | `MAX_PAGES` ceiling | a fixture that always returns a `next` cursor | loop terminates at the ceiling; truncation counter set; no clean verdict |
| T21 | Extraction-failure guard | empty detectors, non-empty monitors | non-zero naming extraction failure; no clean-state string |

Plus the per-guard harness rows, which are tests of the *suite*.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The `curl_retry` rewrite breaks the four gates | AC3 (stdout byte-identity) + AC14 (gate block byte-identical) + Guard 3 mutations 4 and 5. `-D`-only is pinned in Decision 3 |
| Refixturing the 6 rules-shaped tests is unstated work | Now explicit in AC12 and Phase 4; the detectors fetch inherits fixture mode so the 13 existing tests stay hermetic |
| `workflows/`/`detectors/` may themselves be deprecated later | The tripwire warns on any future deprecation header; Phase 0 re-verifies both are clean before any code |
| Vendor 5xx lengthens the pre-plan step | Bounded: 3 attempts, 5 s + 10 s backoff, unchanged ceiling. Only the trigger widens, and write probes are excluded |
| The deployment path remains coupled to the reporting half | Compensating controls (idempotency-aware retry, mandatory cursor-following, declared partial-fetch posture) all land. The real fix is UC-3 |
| The tripwire becomes ignored noise | Escalation ladder with a date, not a perpetual warning. The gate job cannot file issues (`contents: read`), which is why escalation is to a failing exit |
| Article 30 evidence silently stops attaching to releases | Enumerated in `failure_modes`; flagged for reviewer decision in the GDPR note |

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Retry through the brownout window | Cannot distinguish brownout from sunset; sized to a Sentry-owned option; unnecessary once migrated |
| Repoint both branches at `workflows/` | Sentry names `detectors/` for `alert-rules/`. Would mis-map metric alerts |
| Keep the deprecated endpoints, improve diagnostics only | Leaves the intermittent red in place and stakes CI on a schedule we cannot read; no published sunset date |
| Map workflow ids → rule ids by name | Forbidden — duplicate names are legal and the script mandates match-by-id |
| Add an explicit `run_suite` line for the unit suite | Would double-register it and red the required `test` check via `lint-orphan-test-suites.sh` |
| Loud-fail on pagination instead of following the cursor | Deadlocks the deployment path by ordinary monitor growth — the detector blocks its own cure |
| Delete Class A entirely | Strong measured case (UC-2), but a scope reduction the task brief did not request; surfaced rather than applied |
| `AUDIT_MODE=gates` split in this PR | The right fix (UC-3), but a structural change to a gate the brief said not to regress; surfaced rather than applied |
| Make the gate required now | Decision 6 — hands merge control to a vendor's uptime |

## Domain Review

**Domains relevant:** engineering

The 8-domain sweep finds no user-facing surface, pricing/positioning implication, legal document
change, revenue or pipeline effect, or support-facing change. The Article 30 adjacency is handled in
the GDPR section rather than routed to legal: the DPA-evidence section is untouched and the change
improves the artifact's accuracy, though review surfaced two provenance/availability gaps now
recorded there.

### Product/UX Gate

Not applicable. The mechanical UI-surface override did not fire — Files to Edit/Create contain no
path matching the UI-surface term list or glob superset (one shell script, one shell test, two
workflows, one README, one ADR, one lint baseline). Product tier **NONE**.

**Agents invoked:** repo-research-analyst, learnings-researcher, dhh-rails-reviewer,
kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer
**Skipped specialists:** none
**Pending at time of writing:** cto (devex lens) — findings to be folded in on arrival
**Pencil available:** N/A (no UI surface)
