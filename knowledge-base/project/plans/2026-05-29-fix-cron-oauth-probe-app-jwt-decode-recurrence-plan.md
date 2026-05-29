<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
---
title: "fix: cron-oauth-probe App-JWT 'could not be decoded' — root-cause the post-#4569 recurrence"
date: 2026-05-29
type: fix
branch: feat-one-shot-cron-oauth-probe-app-jwt-decode
lane: cross-domain
classification: ops-remediation
brand_survival_threshold: aggregate pattern
status: draft
related_issues: [3183]
related_prs: [4569, 4568, 4565, 4513, 4498]
sentry_issue: 00bdfdf1543c472e91552d45565f1e74
prior_sentry_issues: [4e6a3003d19d47809616d521df3c795b, f3ad8fecf42645f691d67813a4f36cec, 122537945]
---

# fix: cron-oauth-probe App-JWT "could not be decoded" — root-cause the post-#4569 recurrence

🐛 **Recurring production error, 6 prior fixes, all disproven by today's recurrence.**

## Enhancement Summary

**Deepened on:** 2026-05-29
**Gates passed:** 4.6 User-Brand Impact (threshold `aggregate pattern`, valid) ·
4.7 Observability (5/5 fields, no SSH in discoverability_test) · 4.8 PAT-shaped halt (no match) ·
4.4 precedent-diff (hand-rolled `createAppJwt` at `github-app.ts:119-152` is the H4 oracle/target) ·
4.4 scheduled-work (cron-oauth-probe is already an Inngest fn — no new job, gate N/A).

**Live-verification (this pass):** PRs #4569/#4568/#4565/#4513/#4498 all confirmed MERGED;
SHAs `9da77d86`+`db87c27d` confirmed ancestors of `main`; all cited rule IDs active in AGENTS.md;
2 KB citations resolve.

### Key improvements over the v1 plan

1. **Disproof of the latest fix is now SHA-grounded:** `git merge-base --is-ancestor 9da77d86 db87c27d` = true, and `app-private-key.ts` exists at the deployed SHA — the PKCS#8 fix (#4569, merged 08:22 UTC, deployed by 12:31 UTC) is provably live in the release the 14:00 UTC error fired on. The recurrence is not a deploy-lag artifact.
2. **H1 strengthened by SDK source:** `@octokit/app` accepts `appId: number | string` and never validates it (`types.d.ts:3-4,22-24`); a client-id / whitespace App ID is silently signed into `iss`. The `readAppId()` numeric guard is the only pre-GitHub catch point.
3. **H4 fix-shape constraint surfaced:** the `@octokit/app` constructor has no explicit-JWT option, so "route through the immune signer" requires a `createAppAuth`/`authStrategy` override — not a trivial hand-off.
4. **H3 infra root pinned** to `inngest.tf` + `cloud-init.yml` (no existing time-sync config), removing the "TBD root" hand-wave.

### New considerations discovered

- The Node crypto path (`lib/crypto-node.js`) auto-converts PKCS#1→PKCS#8, confirming format is not the operative bug — narrows the live hypothesis set to credential-content (H1/H2), clock (H3), or DER-extraction (H4).
- Evidence-first is structurally enforced: the decisive `#4568` breadcrumb (`ghStatus`/`ghBody`/`clockSkewMs`) is already attached to issue `00bdfdf1` — Phase 1 reads it before any code/secret change, which is the discipline the prior 6 fixes lacked.

## Overview

The `cron-oauth-probe` Inngest function throws
`HttpError: A JSON web token could not be decoded - https://docs.github.com/rest`
when `createProbeOctokit()` mints the GitHub App JWT (`op: create-probe-octokit:app-jwt`,
`feature: cron-oauth-probe`). New Sentry issue `00bdfdf1543c472e91552d45565f1e74`
fired **2026-05-29 16:00:14 CEST (14:00 UTC)** on release
`web-platform@0.101.100+db87c27df1085fb0de30c566…`.

**This plan does NOT ship a 7th blind patch.** Six prior fixes each guessed a
mechanism and patched it; today's recurrence empirically disproves the two most
recent theories. The correct next move is **evidence-first triage**: the data to
identify the real cause is *already captured in this Sentry event* (the `#4568`
diagnostics breadcrumb), and the runbook explicitly instructs us to read it
before re-patching. The deliverable is: (1) pull and interpret that evidence,
(2) apply the one targeted fix the evidence points to, (3) harden the probe so
the NEXT recurrence is self-diagnosing without another investigation cycle.

### Why this is not "just re-run the runbook"

The runbook's `probe_app_jwt_decode` section currently asserts the bug is fixed
by `normalizeAppPrivateKey()` (#4569). That assertion is now **false** — see
Research Reconciliation. Part of this plan corrects the runbook so the next
operator is not misdirected back to the PKCS#8 dead end.

## Research Reconciliation — Spec vs. Codebase

| Claim (from prior fixes / runbook) | Reality (verified this session) | Plan response |
| --- | --- | --- |
| #4569: root cause is CRLF / escaped-`\n` / PKCS#1 line endings corrupting `getDERfromPEM().slice(1,-1)`; fixed by `normalizeAppPrivateKey()` | **DISPROVEN.** `9da77d86` (#4569) is a confirmed ancestor of the deployed release SHA `db87c27d` (`git merge-base --is-ancestor` = true; `app-private-key.ts` exists at `db87c27d`). #4569 merged 08:22 UTC, deployed by 12:31 UTC; the error STILL fired at 14:00 UTC. A clean LF-only PKCS#8 PEM is being handed to `new App()` and GitHub still rejects the JWT. | Stop patching the signing/format path. Treat line-ending theory as closed. Correct the runbook's "Fix shipped" claim to "insufficient — see #00bdfdf1". |
| #4498 / #4513 / #8153a / #4565: root cause is transient 401 (JWT replication delay / clock-skew / `exp` at 600s ceiling); fixed by retry-on-401 + exp margin | **NOT THIS PATH.** The probe error is `"could not be decoded"`, not a 401 token-mint failure. `probe-octokit.ts` retry predicate is `status === 401` ONLY — a decode rejection is a different status and is captured-and-rethrown immediately. The 600s-exp learning (`2026-05-28-…`) explicitly scopes the `@octokit/app` path as "already safe; out of scope" (octokit uses `exp = now + 570`). | Retry-on-401 is irrelevant to a decode error. Do not widen retries. |
| `github-app.ts` (hand-rolled `createSign`) is "immune" to this error | True and **load-bearing**: it signs the SAME `GITHUB_APP_ID` (`iss`) with the SAME `GITHUB_APP_PRIVATE_KEY`, but via `crypto.createSign("RSA-SHA256")` — NO `getDERfromPEM`/`atob` DER round-trip, NO `iss` numeric-type coercion by the library. If the hand-rolled path is healthy while the octokit path fails on identical credentials, the divergence is in how `universal-github-app-jwt@2.2.2` consumes the key/appId, OR the credential is subtly wrong in a way only the strict path rejects. | Make the immune path the diagnostic oracle (Phase 1) and, if credentials are sound, the fix is to route the probe through it (Phase 3 Option C). |
| Runbook says read `#4568` breadcrumb evidence if it recurs post-#4569 | **Correct and not yet done.** `extractGitHubErrorDiag()` (`probe-octokit.ts:58`) attaches `ghStatus`, `ghRequestId`, `ghBody`, `clockSkewMs` to the `warnSilentFallback` on every failure. This new event `00bdfdf1` carries that evidence. | Phase 1 pulls it via the Sentry API — this is the single most decisive step and gates which fix ships. |

## User-Brand Impact

**If this lands broken, the user experiences:** no *direct* user-facing breakage —
the probe is platform-owned synthetic traffic. But the **operator blind spot is
the real harm**: while `createProbeOctokit()` throws, the probe cannot file /
comment on / close its `[ci/auth-broken]` tracking issue, so a *real* prod OAuth
outage (a user genuinely unable to sign in / connect GitHub) can go unsurfaced.
The probe's job is to catch the user-facing auth failures in `oauth-probe-failure.md`;
a probe that can't authenticate to GitHub is a silently-blind smoke detector.

**If this leaks, the user's data is exposed via:** N/A — no user data flows through
this path; diagnostics are scrubbed of key material by design (`extractGitHubErrorDiag`
reads only `err.status` / response headers / public error JSON, never the JWT or PEM).

**Brand-survival threshold:** aggregate pattern — a single missed probe run is
tolerable; a *sustained* blind window (this has recurred for days across 6 fixes)
that hides a concurrent real auth outage is the aggregate failure mode that erodes
trust. `threshold: aggregate pattern, reason: synthetic-probe self-auth failure has no direct single-user data/UX impact; harm is cumulative operator-blindness during the blind window.`

## Research Insights (deepen-plan — verified against installed source)

All claims below were verified this session against the worktree's `node_modules`
and infra files (not from memory).

**`new App({ appId })` accepts a string and never validates it — strengthens H1.**
`@octokit/app@16.1.2` types (`node_modules/@octokit/app/dist-types/types.d.ts:3-4,22-24`):
```ts
export type Options = { appId?: number | string; privateKey?: string; ... };
export type ConstructorOptions<…> = … & { appId: number | string; privateKey: string };
```
`@octokit/auth-app` mirrors this (`types.d.ts:18,104`: `appId: number | string`).
So a client-id-shaped (`Iv23…`) or whitespace-laden `GITHUB_APP_ID` is **silently
accepted at construction** and flows into the JWT as `iss: id` verbatim
(`universal-github-app-jwt@2.2.2/index.js`: `iss: id`, no validation). There is no
construction-time error — GitHub is the only validator, and it returns the opaque
"could not be decoded". This is why a `readAppId()` numeric guard (Phase 2 H1/H2)
is load-bearing: it's the *only* place a malformed App ID can be caught before
GitHub.

**The Node crypto path is what actually runs (not WebCrypto-in-browser).**
`universal-github-app-jwt`'s `#crypto` import map resolves to `lib/crypto-node.js`
on Node (`package.json` imports: `"#crypto": { "node": "./lib/crypto-node.js" }`).
`convertPrivateKey` there auto-converts PKCS#1→PKCS#8 via `createPrivateKey().export()`
— confirming #4569's own comment that *format* is not the operative bug. But the
final DER extraction (`getDERfromPEM` in `utils.js`: `.split("\n").slice(1,-1).join("")`
+ `atob`) runs regardless of platform and is the H4 risk surface.

**Diag extractor is key-material-free (verify-the-negative pass confirms).**
`extractGitHubErrorDiag` (`probe-octokit.ts:58-89`) reads only `err.status`,
`err.response.headers.{date,x-github-request-id}`, and `err.response.data` — grep
for `privateKey|appId|jwt|pem|sign` in that function returns zero. The
User-Brand-Impact "no key leak" claim holds.

**H4 fix shape constraint.** `@octokit/app`'s constructor takes only
`{ appId, privateKey }` — there is NO explicit-JWT injection option. So the H4
"route through the immune signer" fix is NOT a one-line JWT hand-off; it requires
either (a) a custom `authStrategy`/`createAppAuth` override that signs via
`crypto.createSign`, or (b) constructing the installation Octokit from a manually
minted JWT + `@octokit/auth-app`'s `createAppAuth`. terraform-architect is not
involved here; this is a code-design decision for the H4 branch only — flag for
plan-review if H4 is selected.

**H3 infra root pinned.** The Inngest worker VM IaC is
`apps/web-platform/infra/inngest.tf` (`hcloud_server`, self-hosted per ADR-030)
with first-boot config in `apps/web-platform/infra/cloud-init.yml` (`runcmd:` at
line 290). There is currently **no** `chrony`/`systemd-timesyncd` config in
cloud-init (grep returned only the `runcmd:` anchor) — so H3's fix is a genuine
addition, not a repair. The H3 Terraform-changes section now names these files
exactly.

## Hypotheses (ranked; Phase 1 evidence selects the winner)

The error string `"A JSON web token could not be decoded"` is GitHub's response
for a JWT it received and **could not validate as a well-formed, correctly-signed
App token**. With the PEM now provably clean (post-#4569), the live causes are:

- **H1 — `GITHUB_APP_ID` (`iss`) is wrong or malformed.** `universal-github-app-jwt`
  sets `iss: id` verbatim (`index.js`) and does NOT validate it. Likely drift
  shapes: (a) Doppler `prd` `GITHUB_APP_ID` set to the **client_id** (`Iv1…` /
  `Iv23…`) instead of the **numeric App ID**; (b) trailing whitespace / `\n` on the
  value (`new App({ appId })` coerces to string — a non-numeric `iss` yields a JWT
  GitHub "cannot decode"); (c) the App ID belongs to a *different* App than the
  private key. **GitHub returns this exact opaque error for a bad `iss`.** Strongest
  candidate because it explains why the hand-rolled path's *401* and the octokit
  path's *decode* errors differ in shape — and why #4569 (key-only) didn't help.
- **H2 — Private key ↔ App ID mismatch (key belongs to a different/old App).** A
  re-minted or rotated App key whose public half no longer matches the App that
  `GITHUB_APP_ID` names → signature verification fails → "could not be decoded".
  `normalizeAppPrivateKey()` produces a *structurally* valid PKCS#8 but cannot fix
  a *semantically wrong* key.
- **H3 — Clock skew so large it survives octokit's `now-30` backdate.** `clockSkewMs`
  in the breadcrumb settles this in one read. The Hetzner Inngest VM clock drifting
  could push `iat` far enough into the future that even octokit's margin fails.
  Lower probability (octokit backdates 30s; the hand-rolled path backdates 60s and
  is healthy) but cheap to rule out.
- **H4 — `getDERfromPEM` still mis-extracts despite normalization.** `atob(pemB64)`
  on the normalized PEM's joined body — if `normalizeAppPrivateKey`'s output has any
  unexpected wrapping. Low probability (it's the documented-correct PKCS#8 shape) but
  the breadcrumb's absence of `ghStatus` (a pre-request signing throw) vs presence of
  `ghStatus: 401` (a GitHub-side rejection) distinguishes H4 from H1/H2.

**Decision rule (Phase 1):** `ghStatus: 401` + `ghBody` containing "could not be
decoded" → H1/H2 (GitHub rejected a sent JWT). No `ghStatus` (error thrown before
HTTP) → H4. `clockSkewMs` large positive → H3.

## Implementation Phases

### Phase 0 — Preconditions (read-only, no prod writes)

- [ ] Confirm the recurrence is post-fix (already verified; re-assert at /work time):
      `git merge-base --is-ancestor 9da77d86 db87c27d && echo "fix deployed, still failing"`.
- [ ] Re-read `probe-octokit.ts` `extractGitHubErrorDiag` (lines 58-89) and the
      `captureAndRethrow` breadcrumb shape (lines 136-144) so the Phase 1 Sentry
      query targets the right `extra.*` keys.

### Phase 1 — Pull the #4568 diagnostic evidence (the decisive step)

> Per `hr-no-dashboard-eyeball-pull-data-yourself`: query the API, do not
> eyeball the Sentry UI. This is read-only — no prod mutation.

- [ ] Fetch the latest event for issue `00bdfdf1543c472e91552d45565f1e74` and read
      the `create-probe-octokit:app-jwt` breadcrumb `extra`:

      ```bash
      export SENTRY_API_HOST="${SENTRY_API_HOST:-de.sentry.io}"
      SENTRY_AUTH_TOKEN=$(doppler secrets get SENTRY_AUTH_TOKEN -p soleur -c prd --plain)
      curl -s --max-time 10 -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
        "https://${SENTRY_API_HOST}/api/0/issues/00bdfdf1543c472e91552d45565f1e74/events/latest/" \
        | jq '{
            release: .release,
            ghStatus: (.context.extra.ghStatus // .contexts.extra.ghStatus),
            ghBody:   (.context.extra.ghBody   // .contexts.extra.ghBody),
            ghRequestId: (.context.extra.ghRequestId // .contexts.extra.ghRequestId),
            clockSkewMs: (.context.extra.clockSkewMs // .contexts.extra.clockSkewMs),
            attempts: (.context.extra.attempts // .contexts.extra.attempts)
          }'
      ```
      <!-- verified: 2026-05-29 source: Sentry issues events API (de.sentry.io); endpoint shape per existing runbook recipes lines 444-447, 577-579 -->
      *(If `extra` is nested differently in the payload, fall back to `jq '.. | .extra? // empty'`.)*

- [ ] Apply the **Decision rule** above. Record the verdict (H1/H2/H3/H4) in the PR body.

- [ ] **Verify `GITHUB_APP_ID` shape WITHOUT printing it** (covers H1; non-SSH):

      ```bash
      doppler secrets get GITHUB_APP_ID -p soleur -c prd --plain \
        | node -e 'const s=require("fs").readFileSync(0,"utf8"); const t=s.trim();
          console.log(JSON.stringify({len:s.length, trimmedLen:t.length, numeric:/^[0-9]+$/.test(t), looksLikeClientId:/^Iv\d/.test(t), hasWhitespace:s!==t}))'
      # Expect: {len: N, trimmedLen: N, numeric: true, looksLikeClientId: false, hasWhitespace: false}
      # numeric:false OR looksLikeClientId:true OR hasWhitespace:true ⇒ H1 confirmed.
      ```

- [ ] **Verify the key↔App binding by asking GitHub** (covers H1 + H2; the immune
      hand-rolled path is the oracle). Mint a JWT via the *immune* path locally and
      call `GET /app` — if it returns the app, the credentials are sound and the bug
      is octokit-path-specific (H4); if it 401/decode-fails, the credential is wrong
      (H1/H2):

      ```bash
      doppler run -p soleur -c prd -- node --input-type=module -e '
        import crypto from "node:crypto";
        const id = process.env.GITHUB_APP_ID.trim();
        const pem = crypto.createPrivateKey(process.env.GITHUB_APP_PRIVATE_KEY.replace(/\\n/g,"\n"))
          .export({type:"pkcs8",format:"pem"}).toString();
        const now = Math.floor(Date.now()/1e3);
        const b64 = o => Buffer.from(JSON.stringify(o)).toString("base64url");
        const si = b64({alg:"RS256",typ:"JWT"})+"."+b64({iss:id,iat:now-60,exp:now+540});
        const s = crypto.createSign("RSA-SHA256"); s.update(si); s.end();
        const jwt = si+"."+s.sign(pem).toString("base64url");
        const r = await fetch("https://api.github.com/app",{headers:{Authorization:`Bearer ${jwt}`,Accept:"application/vnd.github+json"}});
        console.log("GET /app via hand-rolled path:", r.status, JSON.stringify(await r.json()).slice(0,200));
      '
      # 200 + {"id":<num>,...} ⇒ credentials sound, bug is octokit-path-specific (H4).
      # 401/"could not be decoded" ⇒ credential is wrong (H1/H2) — fix is in Doppler, not code.
      ```
      <!-- verified: 2026-05-29 source: GitHub REST GET /app docs.github.com/rest/apps/apps#get-the-authenticated-app -->

### Phase 2 — Apply the targeted fix the evidence selects

Exactly ONE of the following ships, chosen by Phase 1. Do NOT ship more than one.

- **If H1/H2 (credential drift) — the fix is operator-driven, in Doppler, not code:**
  - [ ] Re-set the correct numeric `GITHUB_APP_ID` (and/or re-mint a PKCS#8 App key
        that matches it) in Doppler `prd`. This is a prod-secret write → gated per
        `hr-menu-option-ack-not-prod-write-auth` (explicit operator ack required).
        `Automation: not feasible because` re-minting a GitHub App private key is a
        CAPTCHA/consent-gated action on github.com/settings/apps with no REST mutation
        path; the value cannot be machine-generated. Doppler write itself is a prod-secret
        auth boundary requiring explicit ack.
  - [ ] **Code hardening (ships regardless):** add an `iss` shape guard to
        `normalizeAppPrivateKey`'s sibling — a `readAppId()` in `app-private-key.ts`
        (or `probe-octokit.ts`) that `.trim()`s and asserts `/^[0-9]+$/`, throwing a
        *loud, specific* error (`GITHUB_APP_ID is non-numeric ('Iv…'?) — likely the
        client_id, not the App ID`) BEFORE handing it to `new App()`. Route both
        `createProbeOctokit` and `createAppJwtOctokit` (and the founder-facing
        `createGitHubAppClient` in `app-client.ts`, for parity with #4569's review
        widening) through it. This converts the opaque "could not be decoded" into a
        self-explaining startup error — closing the re-investigation loop for good.

- **If H3 (clock skew) — the fix is infra (NTP on the Hetzner Inngest VM), routed via IaC:**
  - [ ] Per Phase 2.8 (reviewed; this is genuinely infra, not an SSH one-off): the
        Inngest VM's `chrony`/`systemd-timesyncd` config lives in cloud-init /
        bootstrap under the VM's Terraform root (`apps/web-platform/infra/…`). Add/repair
        the time-sync unit in cloud-init + an idempotent bootstrap script for the
        already-running host; document the apply path. **invoke terraform-architect at
        deepen-plan** to specify the exact TF root + apply path IF H3 is selected.
  - [ ] Code hardening: surface `clockSkewMs` as a dedicated Sentry tag (not just
        `extra`) so skew is alertable.

- **If H4 (octokit-path DER extraction) — the fix is to bypass the brittle library path:**
  - [ ] Route `createProbeOctokit` / `createAppJwtOctokit` JWT minting through the
        **immune hand-rolled `createAppJwt()` shape** (`crypto.createSign`, no
        `getDERfromPEM`), wiring the resulting bearer into `@octokit/app` via its
        explicit-JWT auth strategy, OR construct the installation Octokit from a
        manually-minted JWT. This is the architecturally cleanest end-state because it
        unifies BOTH App-JWT paths on the one signing implementation GitHub has never
        rejected. (Precedent-diff against `github-app.ts:119-152` required at deepen-plan
        Phase 4.4.)

### Phase 3 — Correct the runbook (always ships)

- [ ] Update `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md`
      `probe_app_jwt_decode` section: the current "**Fix shipped (this class)**"
      paragraph asserting `normalizeAppPrivateKey()` resolved it is now false. Replace
      with: "#4569's PKCS#8 normalization was necessary but **insufficient** — issue
      `00bdfdf1` recurred on a release containing it (verified `git merge-base`). The
      operative cause was `<H-verdict>`. Read the `create-probe-octokit:app-jwt`
      breadcrumb `extra` FIRST (Phase 1 recipe) before touching the signing path."
- [ ] Append the Phase 1 Sentry-events + `GET /app` oracle recipes to the runbook so
      the next operator runs them in 2 minutes, not a multi-hour investigation.
- [ ] Bump `related_prs` / `related_issues` frontmatter.

### Phase 4 — Regression test

- [ ] Synthesized-fixture unit test for the new `iss` guard (H1/H2 path): a
      non-numeric / client-id-shaped / whitespace-laden `GITHUB_APP_ID` throws the
      specific guard error, a clean numeric one passes. (cq-test-fixtures-synthesized-only:
      generate a throwaway keypair in-test; never use a real key.)
- [ ] If H4 path chosen: a test asserting the unified mint produces a JWT whose
      header/`iss`/`exp` shape matches `github-app.ts` and verifies under the App's
      public key (round-trip, no network).

## Observability

```yaml
liveness_signal:
  what: cron-oauth-probe Sentry Cron monitor `scheduled-oauth-probe` ?status=ok heartbeat
  cadence: hourly (Inngest scheduled.timer)
  alert_target: Sentry missed-check-in alert (existing)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf
error_reporting:
  destination: Sentry (warnSilentFallback at probe-octokit.ts:137 emits a warning event with extractGitHubErrorDiag extra; terminal error via cron-oauth-probe.ts reportSilentFallback)
  fail_loud: true (new iss guard throws a specific, self-explaining error before new App(); replaces the opaque "could not be decoded")
failure_modes:
  - mode: GITHUB_APP_ID non-numeric / client_id / whitespace (H1)
    detection: new readAppId() guard throws at mint time; Phase 1 shape-check one-liner
    alert_route: Sentry error event feature:cron-oauth-probe op:create-probe-octokit:app-jwt
  - mode: key-to-AppID mismatch (H2)
    detection: GET /app via hand-rolled oracle returns non-200; ghStatus:401 in breadcrumb
    alert_route: same Sentry op tag plus ghBody breadcrumb
  - mode: clock skew (H3)
    detection: clockSkewMs in breadcrumb extra (promote to Sentry tag if H3)
    alert_route: Sentry (new tag) plus Better Stack inngest-heartbeat cross-check
logs:
  where: Sentry events (issue 00bdfdf1 plus successor) plus Inngest run timeline plus journalctl -u inngest-server.service on Hetzner VM (diagnosis only, not state)
  retention: Sentry project default (90d)
discoverability_test:
  command: 'curl -s -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://de.sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-oauth-probe/checkins/?limit=1" | jq -r ".[0].status"'
  expected_output: "ok"
```

## Acceptance Criteria

### Pre-merge (PR)

- [x] Phase 1 evidence pulled; the H2 verdict is recorded verbatim in the PR body
      (`ghStatus:401`, `clockSkewMs:345`, `attempts:3`, `release:db87c27d`; `GET /app` oracle = 401 even with trimmed App ID + normalized key).
- [x] Exactly one Phase 2 fix branch is applied (H1/H2 code hardening); no retry-widening
      and no PEM-format changes ship (verified via diff review — only the App-ID guard + runbook).
- [x] `readAppId()` rejects non-numeric / client-id / whitespace-only `GITHUB_APP_ID`
      with a specific error and strips surrounding whitespace, routed from all three
      `new App()` sites (`createProbeOctokit`, `createAppJwtOctokit`, `createGitHubAppClient`)
      AND the immune `github-app.ts getAppId()`; covered by a pure-string unit test (RED→GREEN).
- [x] Runbook `probe_app_jwt_decode` section no longer claims #4569 resolved the class
      ("necessary but insufficient — recurred on a release containing it"); Phase 1 evidence
      recipes (STEP 1-4) appended.
- [x] `tsc --noEmit` EXIT=0 + vitest (web-platform): 581 files, 7180 passed, 0 failed.

### Post-merge (operator)

- [ ] If H1/H2: corrected `GITHUB_APP_ID` / re-minted key written to Doppler `prd`
      (explicit ack; `hr-menu-option-ack-not-prod-write-auth`).
- [ ] If H3: time-sync IaC applied to the Hetzner Inngest VM (Phase 2.8 apply path).
- [ ] `inngest send cron/oauth-probe.manual-trigger`, then confirm recovery via the
      checkins API (`discoverability_test` command returns `ok`).
- [ ] Issue (file one if none exists) closed via `gh issue close` AFTER recovery is
      confirmed — PR body uses `Ref #N`, not `Closes #N` (ops-remediation: the fix
      executes post-merge; auto-close would falsely resolve before recovery).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Filled above.
- **Do NOT ship a 7th format/retry patch.** The two dominant prior theories (PKCS#8/CRLF
  and retry-on-401) are empirically disproven by this post-#4569 recurrence. If the
  Phase 1 breadcrumb is somehow empty/missing, the correct move is to *add the missing
  diagnostic* and wait one cycle — not to guess a mechanism. Re-guessing is what produced
  6 failed fixes.
- The two App-JWT paths share `GITHUB_APP_ID` and `GITHUB_APP_PRIVATE_KEY` but diverge
  in HOW they consume them (`createSign` vs `getDERfromPEM`/`atob`; library `iss` coercion).
  Any fix must name WHICH consumption difference it targets — "fix the JWT" is not a target.
- `GET /app` is the cheapest credential oracle: it asks GitHub to validate the exact
  (appId, key) pair. Use it before mutating any secret — re-rotating a *correct* secret
  extends MTTR (same anti-pattern the runbook warns against for `GITHUB_CLIENT_SECRET`).
- Verify the Sentry events-API `jq` path against the live payload before trusting a
  null result — `extra` may be under `.contexts.extra` vs `.context.extra` depending on
  the event schema; a false-null reads as "no diagnostics" when they're present.

## Alternative Approaches Considered

| Approach | Why not (now) |
| --- | --- |
| Widen retry-on-401 further | Disproven: the error is a decode rejection, not a 401; the retry predicate doesn't even fire on it. |
| Re-touch PEM normalization | Disproven: #4569 is deployed and the error recurred on that release. |
| Rotate `GITHUB_APP_PRIVATE_KEY` blindly | Cargo-cult; if the key is correct this extends MTTR. Gate on the `GET /app` oracle first. |
| Migrate probe off `@octokit/app` entirely (H4 fix) onto the hand-rolled signer | Strong end-state (unifies both paths on the never-rejected signer) but only justified if Phase 1 confirms credentials are sound and the bug is library-path-specific. Held behind the evidence gate to avoid over-building. |

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)

**Status:** carry-forward (pipeline mode — invoked at deepen-plan)
**Assessment:** Infrastructure/auth-plumbing change with no user-facing surface.
Key CTO probes for deepen-plan: (1) does the H4 unified-signer path mirror a
predicate that already exists in `github-app.ts`? (precedent-diff Phase 4.4); (2)
the `iss` guard is a new gate on a load-bearing credential read — confirm it
throws loud rather than silently coercing. No Product/UX implications (synthetic
platform traffic). GDPR: diagnostics are key-material-free by construction
(`extractGitHubErrorDiag` reads only public error JSON + headers) — no regulated
surface; gate skipped.

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
Phase 2.8 reviewed. Conditional on the Phase 1 verdict:

- **H1/H2/H4:** pure code + Doppler-secret change against already-provisioned
  surfaces → no NEW infrastructure resource is created. The Doppler `prd`
  `GITHUB_APP_ID` write (H1/H2) is a secret-value mutation on an existing managed
  secret, gated by explicit operator ack (`hr-menu-option-ack-not-prod-write-auth`);
  re-minting the GitHub App key is a CAPTCHA/consent-gated github.com action with no
  REST mutation path (`Automation: not feasible`). These sections are N/A for the
  Terraform-resource sense.

### Terraform changes (H3 branch only)

- Files (pinned at deepen-plan): `apps/web-platform/infra/inngest.tf` (the
  `hcloud_server` worker VM, self-hosted per ADR-030) + `apps/web-platform/infra/cloud-init.yml`
  (`runcmd:` block at line 290) — add `chrony` install/enable to `runcmd` (or a
  `systemd-timesyncd` drop-in) + an idempotent `inngest-timesync-bootstrap.sh` for the
  already-running host. Verified: no time-sync config currently exists in cloud-init
  (grep for `chrony|timesync|ntp` returned only the `runcmd:` anchor).
- Providers: existing `hetznercloud/hcloud` provider (no new provider).
- Sensitive vars: none new.

### Apply path (H3 branch only)

- cloud-init + idempotent bootstrap script (default for existing infra): the VM is
  already provisioned, so a `time-sync-bootstrap.sh` applies `chrony` to the running
  host without re-provisioning; cloud-init carries it for future re-provisions.
  Expected downtime: none.

### Distinctness / drift safeguards (H3 branch only)

- `dev != prd`: time-sync is host-level, not env-scoped; no cross-env coupling.
- No secret values land in state.

### Vendor-tier reality check

- N/A — `chrony`/NTP is OS-level, no vendor tier gate.

## Cross-references

- PR #4569 — PKCS#8 normalization (`normalizeAppPrivateKey`); necessary but insufficient (this plan's premise).
- PR #4568 — the `extractGitHubErrorDiag` breadcrumb this plan reads.
- PR #4565 / #4513 / #4498 — retry-on-401 / exp-margin (wrong failure class for the decode error).
- `knowledge-base/project/learnings/bug-fixes/2026-05-28-github-app-jwt-exp-at-600s-ceiling-causes-intermittent-401.md` — scopes the octokit path as "already safe" for the 401 class; the call-graph Session Error there generalizes.
- `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` — `probe_app_jwt_decode` section (corrected by Phase 3).
- `apps/web-platform/server/github-app.ts:119-152` — the immune hand-rolled `createAppJwt()` (diagnostic oracle + H4 fix target).
