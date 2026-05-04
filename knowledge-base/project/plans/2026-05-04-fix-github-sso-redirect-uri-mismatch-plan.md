---
title: "fix: GitHub SSO redirect_uri not associated with this application"
type: bug
priority: P1
issue: 3183
classification: ops-only-prod-write
requires_cpo_signoff: true
created: 2026-05-04
deepened: 2026-05-04
branch: feat-one-shot-fix-github-sso-redirect-uri
worktree: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-fix-github-sso-redirect-uri
---

# fix: GitHub SSO — redirect_uri not associated with this application

## Enhancement Summary

**Deepened on:** 2026-05-04
**Sections enhanced:** Hypotheses (live-probe rebuilt), Background (GitHub matching rules, custom-domain dual-registration), Acceptance Criteria (probe scope expanded), Test Scenarios (login-page detection vs. error-page detection), Implementation Phases (Phase 1 reproduction widened beyond two flows), Risks (third-client-id, browser-cache, scope-mismatch).
**Research agents used:** Context7 + WebFetch on `docs.github.com/.../about-the-user-authorization-callback-url`, WebFetch on `docs.github.com/.../troubleshooting-authorization-request-errors`, WebFetch on `supabase.com/docs/.../auth-github` and `supabase.com/docs/guides/platform/custom-domains`, WebSearch on custom-domain dual-registration. Live curl probes against both Flow A and Flow B with the actual prod `client_id`. Cross-environment Doppler audit (`dev`/`ci`/`prd`/`prd_terraform`).

### Key Improvements

1. **H1 invalidated by live evidence.** The Flow B redirect_uri is currently accepted by GitHub (HTTP 200 + login form, NOT the error page). The original plan's leading hypothesis (github-resolve callback URL missing) is rejected as the current cause. Plan re-prioritised.
2. **GitHub host/path match rules captured.** `redirect_uri` host (excluding sub-domains) and port must match exactly; path must be a sub-directory of a registered callback URL. This bounds what classes of typo can trigger the error.
3. **Custom-domain dual-registration gotcha surfaced.** Supabase advertises the **custom domain** (`api.soleur.ai`) as the `redirect_uri` to OAuth providers when a custom domain is active. The GitHub OAuth App MUST have BOTH `https://api.soleur.ai/auth/v1/callback` AND `https://ifsccnjhymdmidffkzhl.supabase.co/auth/v1/callback` registered — losing the custom-domain entry breaks Flow A immediately.
4. **Single-client-id confirmation.** Both Flow A (Supabase-mediated) and Flow B (github-resolve) use the **same** `client_id = Iv23li9p88M5ZxYv1b7V` — the GitHub App `soleur-ai`. Supabase is configured against the GitHub App, not a separate OAuth App. So a single callback-URL change in the GitHub App settings affects both flows.
5. **Reproduction methodology widened.** Phase 1 cannot rely on the two-flow split alone — must also rule out (a) browser cache from a previous broken session, (b) preview-deploy or staging-env hitting a different `client_id`, (c) Supabase advertising a different `redirect_uri` because `redirectTo` is rejected by `uri_allow_list`, (d) GitHub returning the error from a hidden third path (e.g., installation-time setup_url).

### New Considerations Discovered

- **Detect login-form vs. error-page.** A working `redirect_uri` returns a login form (or consent page) — NOT the error page. The probe in Phase 4 must grep for `redirect_uri is not associated` in the response body, NOT just check HTTP code. Both states return HTTP 200.
- **`uri_allow_list` mismatch produces a Supabase-side rejection, not a GitHub-side rejection.** If the user's `redirectTo` (e.g., `${origin}/callback`) is not in Supabase's `uri_allow_list`, Supabase rejects before forwarding to GitHub — different symptom (Supabase error page, not GitHub error page). Worth checking but not the user's reported error.
- **Operator-paste typos.** A valid-looking but wrong callback URL (e.g., `https://app.soleur.ai/api/auth/github/callback` missing `-resolve`) survives all our gates. Phase 4 probe is the only catch.
- **GitHub's matching is permissive on path-prefix.** Registering `https://app.soleur.ai/` (just the host) would accept ANY path under it as `redirect_uri`. This is convenient but a security smell — the existing list should use full paths.

## Summary

User reports the GitHub OAuth flow on prod returns:

> The redirect_uri is not associated with this application.

The error originates from GitHub's authorize page when the `redirect_uri` query
parameter does not appear in the GitHub App's (or GitHub OAuth App's) registered
"Callback URL" list. We have **two** GitHub OAuth flows and the affected one is
not the Supabase-mediated login SSO — it is the **`/api/auth/github-resolve`**
username-discovery flow that uses our **GitHub App's** user-OAuth client
(`GITHUB_CLIENT_ID = Iv23li9p88M5ZxYv1b7V`).

This is a **configuration drift**, not a code bug. The fix is to (a) restore the
correct callback URL in the GitHub App settings, and (b) add guardrails so the
drift class is detected before user impact next time.

## User-Brand Impact

**If this lands broken, the user experiences:** A new sign-up (or email-only
user clicking "Connect GitHub" after sign-in) is bounced from GitHub to a
GitHub-rendered error page (`The redirect_uri is not associated with this
application`) with no path back into the product. Connect-repo onboarding is
unreachable for that user. For founders auditing the product, this looks like a
broken core flow at the worst possible moment (the first 60 seconds).
**Important:** This PR ships observability and gates — the user-reported #3183
symptom is fixed only after the post-merge operator audits the GitHub App
callback list (Phase 2). Merging without Phase 2 = #3183 still broken for new
sign-ups if the underlying drift was not already self-healed (current
hypothesis: H_A self-healed; verify post-merge regardless).

**If this leaks, the user's data is exposed via:** N/A for the current symptom
— GitHub blocks the flow before any token is issued. Adjacent risk: if the
operator-pasted callback URL is set to a typo or attacker-controlled host, the
auth code would be delivered to the wrong destination. The fix MUST verify the
exact byte-for-byte string and reject typos.

**New failure modes the diff itself introduces (mitigated below):**

1. **`verify-required-secrets.sh` fail-closed on GitHub format change.** If
   GitHub adds a new App tier with a non-`Iv23` prefix or extends the suffix
   length, the shape regex would block all prod releases — **strictly worse
   than the operator-paste class it catches**. Mitigated by demoting the shape
   check to `::warning::` (not `::error::`) and adding a documented
   `SOLEUR_SKIP_GITHUB_CLIENT_ID_SHAPE=1` override.
2. **`github_oauth_*_html_drift` false-positive page storm.** GitHub silently
   A/B-tests the authorize page (~1×/year). One reword would page ops every
   15 min until silenced — and a silenced probe re-exposes the original #3183
   class. Mitigated by tightening the positive-proof grep to GitHub-specific
   anchors (`name="authenticity_token"`, `Sign in to GitHub`, `Authorize <App>`)
   instead of generic `<form|Authorize`, AND by the existing tracking-issue
   dedup (one open issue at a time, not 96/day).
3. **Over-broad `/ship` Phase 7 callback-URL audit anchor regex blocks
   unrelated closures.** A docs follow-through that casually mentions
   "GitHub App" would otherwise hit the closure gate and stay open
   indefinitely. Mitigated by requiring co-occurrence of TWO sentinels
   (callback/redirect_uri AND GitHub-OAuth signal) before the gate fires.

**Brand-survival threshold:** `single-user incident`. Auth is the brand-truth
surface; one repro on a public Loom = "Soleur's auth is broken" → CPO sign-off
required at plan time, `user-impact-reviewer` invoked at review time.

## Background — two GitHub OAuth flows

There are two distinct GitHub OAuth code paths in this codebase. They use
**different** clients and **different** callback URLs. Diagnosing the correct
one is load-bearing — fixing the wrong flow leaves the user broken.

### Flow A — Supabase-mediated login SSO

- **Entry:** `apps/web-platform/components/auth/oauth-buttons.tsx:72` →
  `supabase.auth.signInWithOAuth({ provider: "github", options: { redirectTo: `${window.location.origin}/callback` } })`.
- **Effective redirect_uri sent to GitHub:** Supabase's own
  `https://<project-ref>.supabase.co/auth/v1/callback`
  (CNAME'd as `https://api.soleur.ai/auth/v1/callback`).
- **Configured at:** Supabase Dashboard → Authentication → Providers →
  GitHub → "Callback URL". This is set ONCE per Supabase project, against
  the GitHub OAuth App or GitHub App that is registered with Supabase.
- **`uri_allow_list` (Supabase):** `http://localhost:3000/**,https://app.soleur.ai/**`
  per `apps/web-platform/supabase/scripts/configure-auth.sh:41`. The
  user-facing `redirectTo` MUST match this allow-list (it does today).

### Flow B — `/api/auth/github-resolve` username discovery

- **Entry:** `apps/web-platform/app/api/auth/github-resolve/route.ts:15`.
  Used by email-only users on `/connect-repo` to discover their GitHub
  username without linking identities in Supabase.
- **Constructs redirect_uri itself:**
  `${NEXT_PUBLIC_APP_URL}/api/auth/github-resolve/callback`
  → `https://app.soleur.ai/api/auth/github-resolve/callback`
  (route.ts:41–46).
- **Client used:** `GITHUB_CLIENT_ID = Iv23li9p88M5ZxYv1b7V` (verified
  against Doppler `prd`). This is the GitHub App `soleur-ai`'s
  user-OAuth client (App ID `3261325`, account `jikig-ai`,
  client_id format `Iv23...`).
- **Configured at:** GitHub.com → Settings → Developer settings →
  GitHub Apps → "Soleur AI" → **Callback URL** field (multi-line,
  one per line). NOT mutable via REST API for GitHub Apps.

### Critical: BOTH flows use the SAME `client_id`

`Iv23li9p88M5ZxYv1b7V` is the GitHub App's user-OAuth client and is used
by both flows. Supabase's GitHub provider was bound to our GitHub App
(not a separate OAuth App), confirmed by the live probe: Supabase's
`/auth/v1/authorize?provider=github` 302 redirects to GitHub with
`client_id=Iv23li9p88M5ZxYv1b7V`. **Therefore the GitHub App's callback
URL list governs both flows** and must contain ALL of:

- `https://app.soleur.ai/api/auth/github-resolve/callback` — Flow B.
- `https://api.soleur.ai/auth/v1/callback` — Flow A advertised redirect_uri
  when Supabase custom domain is active.
- `https://ifsccnjhymdmidffkzhl.supabase.co/auth/v1/callback` — Flow A
  fallback when custom domain is briefly down or being re-provisioned. Per
  Supabase docs: "add the custom domain Supabase Auth callback URL **in
  addition to the Supabase project URL.**"

GitHub allows up to 10 callback URLs (one per line); we use ≤3.

### GitHub redirect_uri matching rules (from docs.github.com)

> "If provided, the redirect URL's host (excluding sub-domains) and port
> must exactly match the callback URL. Additionally, the redirect URL's
> path must reference a sub-directory of the callback URL."

Implications for plan:

- **Host exact match.** `app.soleur.ai` ≠ `app.staging.soleur.ai`. A
  preview deploy on a different host would fail.
- **Port exact match.** Production uses 443 (implicit). No issue.
- **Path is sub-directory.** Registering `https://app.soleur.ai/` accepts
  any path under it. We use full paths in the registered list (security
  best practice).
- **Scheme must match.** `http` ≠ `https`. No issue in prod.
- **Trailing slash.** Treated as different paths in OAuth strict-match
  semantics. Phase 2 verification step must compare byte-for-byte.

## Diagnosis — which flow is broken

The error string ("The redirect_uri is not associated with this application")
is GitHub's standard message for **either** flow. The deciding signal is
**which `redirect_uri` GitHub names back at the user**. The user report did not
include the URL, so Phase 1 is a Playwright reproduction that captures it.

### Live-probe state at deepen time (2026-05-04)

Both flows were probed live during deepen-plan. Both currently pass GitHub's
`redirect_uri` check:

```bash
# Flow B — github-resolve direct
curl --max-time 10 -L -s -w "HTTP=%{http_code} URL=%{url_effective}\n" \
  "https://github.com/login/oauth/authorize?client_id=Iv23li9p88M5ZxYv1b7V&\
redirect_uri=https%3A%2F%2Fapp.soleur.ai%2Fapi%2Fauth%2Fgithub-resolve%2Fcallback&\
state=plan-probe-deepen" -o /tmp/gh-resp.html
# Result: HTTP=200, lands on https://github.com/login (login form),
# zero matches for "redirect_uri is not associated" in body.

# Flow A — Supabase-mediated, follow Supabase's 302 to GitHub
curl --max-time 10 -L -s -w "HTTP=%{http_code} URL=%{url_effective}\n" \
  "https://api.soleur.ai/auth/v1/authorize?provider=github&\
redirect_to=https%3A%2F%2Fapp.soleur.ai%2Fcallback" -o /tmp/flow-a.html
# Result: HTTP=200, lands on https://github.com/login (login form),
# Supabase advertises redirect_uri=https://api.soleur.ai/auth/v1/callback,
# zero matches for "redirect_uri is not associated" in body.
```

**Implication:** at the moment the operator ran deepen-plan, both flows were
healthy at the GitHub-side redirect_uri check. The original H1 (Flow B
github-resolve callback URL missing) is **invalidated by this evidence**. The
user's report must be one of:

1. **A.** Already-fixed since the report — operator silently corrected the
   GitHub App config between report and deepen.
2. **B.** A different env/build path advertising a stale `client_id` or wrong
   `redirect_uri` (preview deploy, staging branch, browser cached an old
   build chunk).
3. **C.** A flow we have not enumerated — installation-time `setup_url`,
   GitHub App marketplace install, or OAuth scope mismatch surfacing the
   same error string.
4. **D.** Browser cache / state mismatch on a single user's session (e.g.,
   reused `state` param after the App's secrets were rotated).
5. **E.** Custom-domain CNAME flap caused Supabase to briefly advertise the
   `supabase.co` URL while the GitHub OAuth App had only the `api.soleur.ai`
   URL registered — narrow timing window.

Phase 1 reproduction MUST capture the failing URL verbatim from the user's
session before any operator action. Do NOT operate-then-verify. Phases 4–5
guardrails ship regardless because they are net-positive even if the cause
is already gone.

## Research Reconciliation — Spec vs. Codebase

| Claim                                                                 | Reality                                                                                  | Plan response                                                                  |
| --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| "Code bug — env var or route is wrong"                                | `route.ts:41` constructs `${appUrl}/api/auth/github-resolve/callback` from `NEXT_PUBLIC_APP_URL`. Doppler `prd.NEXT_PUBLIC_APP_URL = https://app.soleur.ai` (verified). Test `github-resolve.test.ts:188` asserts the exact format. Code is correct. | Phase 2 fix is config-only. Code phase is for guardrails (Phases 3–5).         |
| "GitHub App callback URL is mutable via REST API"                     | GitHub Apps' callback URL list is NOT exposed by `GET /app` (verified — returns `null`). It is mutable only via the GitHub UI or via the App-Manifest creation flow. | Phase 2 step is operator-driven via Playwright MCP up to the dashboard page; the operator clicks Save (CSRF-protected). |
| "Issue #1784 is fully resolved"                                       | Comment trail shows reopen + close cycle. The "Verified" comment came BEFORE the reopen comment that escalated. Issue closed without a second verification round. | Phase 5 retroactively fixes the workflow gate that allowed `/ship` Phase 7 verification to mark a still-broken setup as resolved. |
| "Need to update env var or rotate `GITHUB_CLIENT_ID`"                 | Verified `prd.GITHUB_CLIENT_ID = Iv23li9p88M5ZxYv1b7V`. JWT-authenticated `GET /app` returns the same `client_id`. They match. | No env change. Skip rotation.                                                  |
| "OAuth probe should have caught this"                                 | Probe (`scheduled-oauth-probe.yml`) only checks Supabase `/auth/v1/authorize`. It does not call `/api/auth/github-resolve`. | Phase 4 extends the probe to also probe Flow B — capture GitHub's response body and grep for the redirect-uri error string. |

## Hypotheses

Re-ranked after live-probe evidence at deepen time. Phase 1 reproduction
selects.

1. **H_A (post-deepen leading): Already-fixed since the report.** Operator
   corrected the GitHub App callback URL list between report and now. Phase 1
   probes the exact user-reported state. If we cannot reproduce, mark "fixed
   by intervening operator action" and ship Phases 4–5 guardrails only.
2. **H_B: Custom-domain dual-registration drift.** GitHub OAuth App has only
   ONE of `https://api.soleur.ai/auth/v1/callback` or
   `https://ifsccnjhymdmidffkzhl.supabase.co/auth/v1/callback` registered.
   When Supabase momentarily advertised the other one (e.g., during custom-
   domain re-provisioning), Flow A failed for one window. Documented gotcha
   in Supabase's own docs.
3. **H_C: A different env/client_id advertised the wrong redirect_uri.**
   A preview deploy or staging branch with no `GITHUB_CLIENT_ID` set falls
   into the route's "not configured" branch (`route.ts:36`) — which would
   produce a different symptom (`/connect-repo?resolve_error=1` redirect,
   not GitHub error page). So this is unlikely as the user-reported
   symptom but worth ruling out.
4. **H_D: Operator-paste typo in the GitHub App callback list.** A
   plausible-looking but wrong URL (e.g., missing path segment, http vs.
   https, trailing slash difference vs. exact-match rule). GitHub's host-
   exact + path-prefix matching catches all of these.
5. **H_E: Original H1 — Flow B github-resolve callback URL missing.**
   Demoted: live curl with the exact `redirect_uri` returns the login form,
   not the error page → URL IS currently registered. Direct precedent #1784
   matches the symptom but not the current state.
6. **H_F: Browser-cached error page.** User loaded the broken state once,
   browser cached the GitHub error response (or a stale CSRF token), and
   the user is hitting cache on retry. Test by opening incognito.
7. **H_G: Application suspended / OAuth scope mismatch surfacing as
   redirect_uri error.** GitHub's troubleshooting docs name three error
   classes: `Application suspended`, `Redirect URI mismatch`, `Access
   denied`. Suspended apps can manifest with adjacent error strings. Verify
   via `gh api /app` (already done at deepen — App is active).
8. **H_H: Custom domain CNAME drift.** `dig +short CNAME api.soleur.ai`
   currently → `ifsccnjhymdmidffkzhl.supabase.co.` Healthy. Ruled out.

## Open Code-Review Overlap

`#3039: review: add Sentry mirror + drift-guard coverage for signOut` —
matches `signInWithOAuth` substring in `oauth-buttons.tsx`. **Disposition:
Acknowledge.** #3039 covers `signOut` Sentry mirroring; this plan covers
`signInWithOAuth` redirect_uri drift. Different code paths, different
remediations. The scope-out remains open.

No other open `code-review` issues touch the affected files.

## Acceptance Criteria

### Pre-merge (PR)

- [x] Phase 1 reproduction run via curl probes (Playwright unnecessary
      — both flows currently pass at GitHub edge). Findings recorded
      verbatim in #3183 comment: HTTP 200 + form_count 1 + zero error
      matches across all 3 callback URLs at 2026-05-04T11:37:45Z.
- [x] Plan resolves to **H_A** (already-fixed) OR **H_B** (custom-domain
      dual-registration drift, self-healed). Page-source grep result
      attached to #3183 comment.
- [x] Phase 4 — `scheduled-oauth-probe.yml` extended with THREE probes
      (github-resolve, supabase-custom-domain, supabase-canonical). Each
      probe pins `curl --max-time 10`; asserts HTTP 200; greps
      `redirect_uri is not associated` (negative); greps `Application
      suspended` (negative); greps `<form` OR `Authorize` (positive
      proof). Probe-output sanitisation strips `\n\r\f\v` and
      U+2028/U+2029 from any value echoed to `::error::` / `::warning::`.
- [x] Phase 4 secret extension: `OAUTH_PROBE_GITHUB_CLIENT_ID` (renamed
      from plan's `GITHUB_CLIENT_ID_PROBE` — GitHub reserves `GITHUB_*`
      secret prefix) and `SUPABASE_PROJECT_REF` added as workflow
      secrets via `gh secret set`, sourced from Doppler `prd`. Doppler
      shape check in `apps/web-platform/scripts/verify-required-secrets.sh`
      extended with `^Iv23[A-Za-z0-9]{16}$` regex on `GITHUB_CLIENT_ID`.
- [ ] **NEW (deepen)**: A daily drift-guard captures `gh api /app` JSON
      with the JWT-authenticated GitHub App into a workflow log artifact.
      The probe asserts `client_id` matches the expected value byte-for-
      byte. Catches H_C-class drift (someone swaps the GitHub App).
      DEFERRED to follow-up #3187 (requires GitHub App JWT mint
      infrastructure not in current scope).
- [x] Phase 5 — `/ship` Phase 7 callback-URL audit anchor added:
      callback-URL-class follow-through issues MUST NOT be closeable
      until `gh issue comment` includes (a) verbatim `redirect_uri`
      value(s) verified, (b) a workflow run ID with `conclusion=success`,
      AND (c) the byte-count of the GitHub App's callback URL textarea
      (forensics for future drift). Workflow gate fix per
      `wg-when-fixing-a-workflow-gates-detection`.
- [x] No `NEXT_PUBLIC_APP_URL`, `GITHUB_CLIENT_ID`, or
      `GITHUB_CLIENT_SECRET` rotated. Confirmed safe: rotating the
      secret does not affect callback URL registration.
- [ ] PR body uses `Ref #<N>` (NOT `Closes #<N>`) per
      `wg-use-closes-n-in-pr-body-not-title-to` and the
      `ops-only-prod-write` extension. The actual issue closes after
      the post-merge operator step succeeds. ⏳ Set during `/ship`.
- [x] Negative-test regression: tests in
      `apps/web-platform/test/oauth-probe-contract.test.ts` (standalone
      file per work-skill guidance — github-resolve.test.ts mocks
      modules that interfere with workflow-yml reads) assert the probe
      pattern would catch a known-bad redirect_uri (load-bearing grep
      target on `redirect_uri is not associated` + adjacent sentinels).

### Post-merge (operator)

- [ ] **(H_B / H_D / H_E path — GitHub App callback drift)** Operator
      opens `https://github.com/organizations/jikig-ai/settings/apps/soleur-ai`,
      navigates to "Identifying and authorizing users → Callback URL",
      verifies (and adds if missing) ALL THREE entries — one per line:
      `https://app.soleur.ai/api/auth/github-resolve/callback`,
      `https://api.soleur.ai/auth/v1/callback`,
      `https://ifsccnjhymdmidffkzhl.supabase.co/auth/v1/callback`.
      Preserves existing localhost entries. Confirms "Request user
      authorization (OAuth) during installation" is checked. Playwright
      MCP automates up to the form-submit; operator clicks Update
      (CSRF-protected button).
- [ ] **(H_C path — env drift)** Operator audits Vercel/build env vars
      and `gh secret list` for any `GITHUB_CLIENT_ID` outside Doppler
      `prd`. Removes stray entries; rebuilds via
      `gh workflow run reusable-release.yml`.
- [ ] **(H_A path — already fixed)** Operator skips Phase 2; appends
      "intervening-fix verified — could not reproduce after dashboard
      audit" comment to the issue with the dashboard screenshot of all
      three callback URLs present.
- [ ] Manual probe: `gh workflow run scheduled-oauth-probe.yml` →
      green within 5 minutes. Conclusion captured.
- [ ] Playwright end-to-end probe of the actual user flow:
      sign in (existing test fixture), click "Connect GitHub" on
      `/connect-repo` → reaches `https://github.com/login/oauth/authorize`
      page (NOT the error page) → screenshot captured for PR comment.
- [ ] Issue (filed at Phase 0) closed via `gh issue close <N>` with the
      probe-run-ID and the Playwright screenshot URL in the closing
      comment.

## Test Scenarios

1. **Reproduce (Playwright MCP, prod):** sign in as a fixture user → land on
   `/connect-repo` (or whichever page exposes the GitHub button for that
   user's state) → click "Connect GitHub" → capture the URL bar at the
   GitHub error page → assert it contains `redirect_uri=` and capture the
   value.
2. **Code-path test (already exists):** `apps/web-platform/test/github-resolve.test.ts:180`
   asserts `redirect_uri = ${NEXT_PUBLIC_APP_URL}/api/auth/github-resolve/callback`.
   Re-run to confirm.
3. **Flow B probe (new, Phase 4):** From the workflow runner, perform a
   minimal request that exercises Flow B without needing a Supabase
   session. Two options — pick (a) unless it requires changing the
   route's auth gate:
   - (a) Probe the **GitHub side directly** by constructing the same URL
     the route would build (`https://github.com/login/oauth/authorize?client_id=Iv23li9p88M5ZxYv1b7V&redirect_uri=https%3A%2F%2Fapp.soleur.ai%2Fapi%2Fauth%2Fgithub-resolve%2Fcallback&state=probe`),
     `curl --max-time 10 -L -s` it, and grep the rendered HTML for
     `redirect_uri is not associated`. Fast, no session needed.
   - (b) If (a) is rejected because GitHub's HTML changes can break the
     grep, log a Sentry test-event from the route on a `?probe=1` query
     and assert via the Sentry API the next probe-event is absent.
     Slower but durable.
4. **Drift-guard (Phase 5):** Re-run the same probe immediately after
   the operator step — must flip from RED to GREEN within 1 minute.
5. **Negative test (regression coverage):** Add a test that constructs the
   redirect_uri using a fabricated `NEXT_PUBLIC_APP_URL=https://wrong.example`
   and asserts the probe correctly catches the GitHub error. Marks the
   probe's grep as load-bearing.

## Implementation Phases

### Phase 0 — File the tracking issue (5 min)

```bash
gh issue create \
  --title "P1: GitHub SSO — redirect_uri is not associated with this application" \
  --body-file - <<'EOF'
... (mirror the Summary + Background + first repro screenshot) ...
EOF
```

Label `priority/p1-high`, `type/bug`, `domain/engineering`. Capture issue
number into the plan frontmatter (`issue:`).

### Phase 1 — Reproduce + identify (15–30 min)

**Goal:** capture the failing URL **before** any operator action. Live curl
probes during deepen-plan show both flows currently pass. So Phase 1 must
distinguish "fixed by intervening operator action" from "still broken in
the user's session" before deciding fix branch.

Playwright MCP, in this order:

1. **Two-window reproduction.** Open Window A as **incognito** (fresh
   browser state). Open Window B as **the user's reported session** if the
   user can re-share their state, otherwise also incognito.
   - This rules out H_F (browser cache) by comparing the two.
2. `mcp__playwright__browser_navigate` → `https://app.soleur.ai/login`.
3. Sign in with the test fixture credentials. Doppler audit at deepen
   confirmed prod has working credentials; if `E2E_TEST_USER_*` is not in
   Doppler `prd`, create via Supabase admin API per
   `apps/web-platform/scripts/seed-qa-user.sh` (already exists) and capture
   the email/password into Doppler `prd` for future probes.
4. Reproduce both Flow A AND Flow B in BOTH windows:
   - Flow A: `/login` → click "Continue with GitHub" → capture URL.
   - Flow B: `/connect-repo` → click "Connect GitHub" → capture URL.
5. **Decision matrix:**
   | URL bar contains | Failing flow | Hypothesis |
   |---|---|---|
   | `client_id=Iv23li9p88M5ZxYv1b7V` AND `redirect_uri=...github-resolve/callback` AND error string in body | Flow B | H_E (Flow B callback missing) |
   | `redirect_uri=https%3A%2F%2Fapi.soleur.ai%2Fauth%2Fv1%2Fcallback` AND error string | Flow A custom-domain | H_B variant (api.soleur.ai not registered) |
   | `redirect_uri=https%3A%2F%2Fifsccnjhymdmidffkzhl.supabase.co%2Fauth%2Fv1%2Fcallback` AND error string | Flow A canonical | H_B variant (supabase.co not registered) |
   | `client_id` ≠ `Iv23li9p88M5ZxYv1b7V` | Wrong client_id served | H_C (env drift) |
   | Both windows reproduce identically | Server-side state | H_E or H_B |
   | Only the user's window reproduces, incognito does not | Session/cache | H_F |
   | Neither window reproduces | Already fixed | H_A |
6. **Page-source capture.** Run `mcp__playwright__browser_evaluate` to
   `document.documentElement.outerHTML` and grep for
   `redirect_uri is not associated`. The error string in the body — NOT
   the URL — is the load-bearing positive signal. Both healthy flows
   return HTTP 200 + login form; do NOT assert on HTTP code.
7. **Append all artifacts** to the tracking issue:
   - Window A vs. Window B URLs.
   - Page-source grep result.
   - Screenshot of the error page (or absence thereof).
   - User-Agent, timestamp, and the live `dig +short CNAME api.soleur.ai`
     output at reproduction time (rules out H_E/H_H racing).

### Phase 2 — Operator fix (5 min, dashboard click)

Both flows share the same GitHub App, so a SINGLE dashboard page is the
remediation surface for almost every failing-flow path. Phase 2 is
"audit the GitHub App callback URL list and ensure ALL THREE entries are
present, byte-for-byte":

`mcp__playwright__browser_navigate` →
`https://github.com/organizations/jikig-ai/settings/apps/soleur-ai`.
`mcp__playwright__browser_snapshot` to confirm the operator reached the
"Identifying and authorizing users" section. Read the current Callback
URL textarea contents via `mcp__playwright__browser_evaluate` (capture
verbatim into the issue for forensics). Required entries (one per line):

```text
https://app.soleur.ai/api/auth/github-resolve/callback
https://api.soleur.ai/auth/v1/callback
https://ifsccnjhymdmidffkzhl.supabase.co/auth/v1/callback
```

For local-dev convenience the list MAY also include
`http://localhost:3000/api/auth/github-resolve/callback` and
`http://localhost:54321/auth/v1/callback`. These are NOT required for
prod and are flagged by Phase 4 probe as "noise but not failure".

Operator paste-edits any missing entries. **Operator clicks Update**
(CSRF-protected button — Playwright cannot auto-submit per
`hr-menu-option-ack-not-prod-write-auth`). Display the diff (existing
list vs. proposed list) before requesting the click.

**(If Phase 1 selected H_C — env drift):** Skip the GitHub App. Open
`https://github.com/jikig-ai/soleur/settings/secrets/actions` and audit
the `GITHUB_CLIENT_ID` repo/env secret (none currently set per
`gh secret list` at deepen). Open Vercel/preview-deploy config (none
currently used per repo audit) and audit env vars. Most likely outcome:
no secret exists at the wrong layer — the user hit a stale build, force
a fresh build via `gh workflow run reusable-release.yml`.

**(If Phase 1 selected H_A — already fixed):** Skip Phase 2. Append
"intervening-fix" note to the issue and proceed directly to Phases 4–5
(guardrails + workflow gate fix).

### Phase 3 — Inline verification (5 min)

```bash
# Re-run the probe (will need Phase 4 extension first, OR run a one-shot probe)
curl --max-time 10 -L -s \
  "https://github.com/login/oauth/authorize?client_id=Iv23li9p88M5ZxYv1b7V&redirect_uri=https%3A%2F%2Fapp.soleur.ai%2Fapi%2Fauth%2Fgithub-resolve%2Fcallback&state=postfix-probe" \
  | grep -c "redirect_uri is not associated"
# Must return 0
```

Then re-run the Playwright reproduction from Phase 1 — must reach GitHub's
"Authorize Soleur AI" page (not the error page).

### Phase 4 — Probe extension (PR scope, 45–90 min)

Edit `.github/workflows/scheduled-oauth-probe.yml` to add a probe that
covers ALL THREE registered callback URLs. Implementation sketch (not
literal — the work-skill writes the final shell):

```bash
# Probe each registered redirect_uri against GitHub's authorize endpoint.
# Healthy state: HTTP 200 + body does NOT contain "redirect_uri is not
# associated". Both healthy and failing states return HTTP 200 — the body
# grep is load-bearing. Per docs.github.com/.../troubleshooting-authorization-request-errors.
probe_github_redirect_uri() {
  local label="$1" redirect_uri="$2"
  local url body http
  url="https://github.com/login/oauth/authorize?client_id=${GITHUB_CLIENT_ID_PROBE}&redirect_uri=$(jq -nr --arg u "$redirect_uri" '$u|@uri')&state=probe-${RANDOM}"
  # -L follows the GitHub `/login` redirect for unauthenticated requests;
  # the error page renders BEFORE the login form when redirect_uri is bad,
  # so -L is safe AND captures both code paths.
  body=$(curl --max-time 10 -L -s -w '\n%{http_code}' "$url" 2>/dev/null) || {
    record_failure "github_oauth_${label}_network" \
      "GET ${url} -> curl error (DNS, TLS, or connect)"
    return
  }
  http=$(printf '%s' "$body" | tail -1)
  body=$(printf '%s' "$body" | sed '$d')
  if [[ "$http" != "200" ]]; then
    record_failure "github_oauth_${label}_http" \
      "GET ${url} -> HTTP ${http}"
    return
  fi
  if grep -q "redirect_uri is not associated" <<<"$body"; then
    record_failure "github_oauth_${label}_unregistered" \
      "GitHub rejected redirect_uri=${redirect_uri} for client_id=${GITHUB_CLIENT_ID_PROBE}"
    return
  fi
  if grep -q "Application suspended" <<<"$body"; then
    record_failure "github_app_suspended" \
      "GitHub App ${GITHUB_CLIENT_ID_PROBE} is suspended"
    return
  fi
}

# Phase 4a — github-resolve callback (Flow B)
[[ -z "$fail_mode" ]] && probe_github_redirect_uri "github_resolve" \
  "https://${APP_HOST}/api/auth/github-resolve/callback"

# Phase 4b — Supabase custom-domain callback (Flow A primary)
[[ -z "$fail_mode" ]] && probe_github_redirect_uri "supabase_custom" \
  "https://${API_HOST}/auth/v1/callback"

# Phase 4c — Supabase canonical callback (Flow A fallback for custom-domain re-provisioning)
[[ -z "$fail_mode" ]] && probe_github_redirect_uri "supabase_canonical" \
  "https://${SUPABASE_PROJECT_REF}.supabase.co/auth/v1/callback"
```

`GITHUB_CLIENT_ID_PROBE` and `SUPABASE_PROJECT_REF` are added as workflow
secrets, sourced from Doppler `prd.GITHUB_CLIENT_ID` and (derived from)
Doppler `prd.NEXT_PUBLIC_SUPABASE_URL`. Per the AGENTS.md preflight
pattern, extend `apps/web-platform/scripts/verify-required-secrets.sh`
with shape assertions:

- `GITHUB_CLIENT_ID` matches `^Iv23[A-Za-z0-9]{16}$` (GitHub App user-OAuth
  client format).
- `NEXT_PUBLIC_SUPABASE_URL` resolves to a 20-char-rt`.supabase.co`
  hostname after CNAME deref (already enforced by
  `cq-pg-security-definer-search-path-pin-pg-temp` adjacent — extend the
  Doppler check, not just runtime).

**`dig` timeout pinning.** Per
`cq-when-a-plan-prescribes-dig-nslookup-curl-or-any-network-call-inside-a-ci-step`,
any `dig` calls added to derive the canonical ref MUST pin
`+time=3 +tries=2`. Current sketch uses Doppler-derived ref directly to
avoid `dig` entirely.

**Probe-output sanitisation.** Per
`cq-when-a-plan-prescribes-echoing-json-decoded-values`, GitHub's
`redirect_uri` value is echoed into `record_failure`'s annotation. Strip
CR/LF before emit:

```bash
redirect_uri_safe="${redirect_uri//[$'\n\r']/}"
```

### Phase 4 Research Insights

**Best Practices (from docs.github.com):**

- Probe ALL registered callback URLs, not only the one the failing flow
  uses. A registration drift on a sibling URL is invisible until it is
  the one advertised.
- Up to 10 callback URLs allowed — safe to register dev/local-host
  variants alongside prod.
- Both error and login-form responses are HTTP 200 — body grep is the
  only reliable failure signal.

**Performance Considerations:**

- Each probe is one HTTP round-trip + a body scan. With 3 URLs and
  `--max-time 10`, worst-case wall-clock is 30s per scheduled run.
- Probe runs every 15 min today → +90s/hr of GitHub-unauthenticated
  traffic. Below GitHub's unauthenticated rate limit (60 req/hr) but
  share the limit with `repo-research-analyst` etc. — recommend
  a `User-Agent: soleur-oauth-probe/1.0` header so GitHub can rate-
  limit us politely.

**Edge Cases:**

- **GitHub HTML rewording.** If GitHub rewords the error string, every
  probe goes silent-pass. Mitigate by also asserting that the response
  contains `<form` AND `client_id` (positive proof of the login form)
  OR `Authorize` (positive proof of the consent page). Drift surfaces
  as both-missing.
- **App-Manifest `client_id` rotation.** GitHub App user-OAuth client_ids
  do NOT rotate without explicit operator action. The shape regex above
  fails closed if a future operator paste accidentally writes an OAuth
  App `client_id` (`Ov23...` format).
- **Suspended app.** `Application suspended` page renders different
  HTML; explicit grep above catches it as a distinct failure mode.

**References:**

- [GitHub: About the user authorization callback URL](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/about-the-user-authorization-callback-url)
- [GitHub: Troubleshooting authorization request errors](https://docs.github.com/en/apps/oauth-apps/maintaining-oauth-apps/troubleshooting-authorization-request-errors)
- [Supabase: Custom Domains — OAuth callback dual-registration](https://supabase.com/docs/guides/platform/custom-domains)
- [Supabase: Login with GitHub](https://supabase.com/docs/guides/auth/social-login/auth-github)

### Phase 5 — Workflow gate fix (PR scope, 20 min)

Per `wg-when-fixing-a-workflow-gates-detection`, retroactively apply the
fix to the case that exposed the gap. The gap is `/ship` Phase 7 Step 3.5
("create follow-through verification issue") — it created #1784, but the
verification process that closed #1784 did not actually exercise the
flow. Two changes:

1. `plugins/soleur/skills/ship/SKILL.md` Phase 7 Step 3.5 — when filing
   the follow-through issue, the body MUST instruct: *"Close this issue
   only with a comment containing (a) the verbatim redirect_uri value
   verified, (b) a workflow run ID showing the relevant probe is green."*
2. Add a one-line check to the auto-close pathway that rejects close
   attempts on `follow-through: verify *callback URL*` issues that lack
   both fields.

### Phase 6 — Compound learning (5 min)

Capture `2026-05-04-github-app-callback-url-drift-recurring.md` under
`knowledge-base/project/learnings/integration-issues/`. Key insight:
"GitHub App callback URLs are not REST-mutable; the only durable guard is
a probe that exercises GitHub's `/login/oauth/authorize` endpoint and
greps for the rejection string."

## Files to Edit

- `.github/workflows/scheduled-oauth-probe.yml` — add three GitHub
  redirect_uri probes (github-resolve, supabase-custom, supabase-
  canonical) AND a daily `gh api /app` snapshot drift-guard.
- `apps/web-platform/scripts/verify-required-secrets.sh` — add shape
  check `^Iv23[A-Za-z0-9]{16}$` on `GITHUB_CLIENT_ID`.
- `plugins/soleur/skills/ship/SKILL.md` — Phase 7 Step 3.5 wording
  (verbatim verification + run-ID requirement).
- `apps/web-platform/test/github-resolve.test.ts` — add the negative-
  case regression test from Test Scenarios §5.
- `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` —
  extend with the new failure modes (`github_oauth_*_unregistered`,
  `github_app_suspended`, `github_oauth_*_http`).

## Files to Create

- `knowledge-base/project/learnings/integration-issues/2026-05-04-github-app-callback-url-three-entries.md`
  — compound entry per Phase 6 (single client_id serves all flows;
  custom-domain dual-registration; HTTP 200 for both healthy and
  failing states; body-grep is load-bearing).
- `knowledge-base/engineering/ops/runbooks/github-app-callback-audit.md`
  — operator-facing runbook: how to audit the three required
  callback URLs in the GitHub App dashboard, what each one serves,
  rollback if drift detected.

## Risks

1. **Operate-then-verify misdiagnosis.** Live deepen-time probes show
   both flows pass GitHub's redirect_uri check. If Phase 1 is skipped
   and the operator pre-emptively edits the GitHub App, the only signal
   is "before vs. after of an unchanged surface" — no learning, no proof
   the user's report was the GitHub App. Mitigation: Phase 1 is a hard
   prerequisite for Phase 2 with the decision matrix above.
2. **Probe false negative on GitHub HTML changes.** The probe greps
   `redirect_uri is not associated` from GitHub's HTML. If GitHub
   rewords the error (precedent: GitHub rewords ~1×/year), the probe
   goes silent-pass. Mitigation: the probe also asserts a positive
   match on `<form` AND `client_id` (login form) OR `Authorize`
   (consent page). Both-missing = drift, fail loud.
3. **Probe false positive on substring collision.** The string
   `redirect_uri is not associated` appearing in unrelated docs/footer
   would falsely trigger. Vanishingly unlikely for an unauthenticated
   GitHub login page; would surface immediately on first run.
4. **Operator-paste typo on the GitHub App form.** Pasting a wrong URL
   sends future user codes to the wrong host. Mitigation: Phase 3 curl
   probe runs immediately after the operator click; trailing-slash and
   case-sensitive comparison enforced; mismatch = probe stays red.
5. **Custom-domain re-provisioning races.** If Supabase ever re-issues
   the custom domain (CNAME flap, cert renewal failure), Supabase
   silently advertises the canonical `supabase.co` URL for the duration.
   If only `api.soleur.ai` is registered with GitHub, Flow A breaks for
   that window. Mitigation: register BOTH (Phase 2) AND probe BOTH
   (Phase 4). New risk surfaced by deepen-plan research.
6. **Closure-without-verification recurrence.** Issue #1784 was closed
   without a verified second remediation. The Phase 5 workflow gate fix
   is the only durable defense.
7. **Probe drift on schema-of-failure changes.** Future GitHub error
   message changes (e.g., "redirect_uri" → "redirectUri") would silently
   pass. Mitigation: Phase 6 learning file documents the exact match
   strings; quarterly skill-freshness audit re-tests the probe against
   a deliberately-broken URL (negative test from Test Scenarios §5).
8. **Browser cache on operator's verification.** Operator may verify
   "fixed" in their own browser while the user still sees cache. Phase 1
   incognito-window protocol mitigates; Phase 3 verifies via fresh curl
   from a CI runner (no shared cache).
9. **Single-client-id blast radius.** All flows depend on
   `Iv23li9p88M5ZxYv1b7V`. If the GitHub App is suspended, EVERY GitHub
   auth path breaks simultaneously — not just one flow. Phase 4 catches
   this with the explicit `Application suspended` grep.
10. **Secret rotation cascading to re-registration.** Rotating
    `GITHUB_CLIENT_SECRET` does NOT change the `client_id` and does NOT
    affect callback URL registration — safe to rotate independently.
    Documented in Phase 6 learning to prevent future
    cargo-cult re-registration.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. This plan's section is filled with concrete
  artifacts and threshold = `single-user incident`.
- Per `hr-menu-option-ack-not-prod-write-auth`: Phase 2's dashboard
  click is a destructive write against prod auth config. The operator
  MUST read the exact callback URL string before clicking Update. Show
  the URL in the menu prompt; menu-ack alone is NOT authorization.
- Per `hr-exhaust-all-automated-options-before`: Phase 2 cannot be
  fully automated (GitHub App callback list is dashboard-only). The
  Playwright MCP path navigates to the form and pre-fills, but the
  operator clicks Update.
- Per `wg-use-closes-n-in-pr-body-not-title-to` and the
  `ops-only-prod-write` extension: PR body uses `Ref #N`, NOT
  `Closes #N`. Issue closure is in the post-merge operator step.

## Domain Review

**Domains relevant:** Product (CPO sign-off required per
`hr-weigh-every-decision-against-target-user-impact`), Engineering (CTO
implicit — auth flow architecture).

### Engineering (CTO)

**Status:** carry-forward from prior #2979 + #1784 work.
**Assessment:** Two-flow split (Supabase-mediated vs. App-direct OAuth)
is intentional and documented. The architectural concern is the
recurrence pattern — same symptom in #1784 and now again. The fix
class is "configuration drift in a system whose config is not
infrastructure-as-code." Phase 4 + Phase 5 address that — probe + close
gate.

### Product (CPO)

**Tier:** advisory (no new UI; broken existing flow).
**Decision:** auto-accepted (pipeline; one-shot mode).
**Agents invoked:** none (deferred to deepen-plan if escalated).
**Skipped specialists:** ux-design-lead (no new UI), copywriter (no
copy change).
**Pencil available:** N/A.

#### Findings

CPO sign-off required at plan finalization per `requires_cpo_signoff:
true`. Concrete artifact: any failed sign-up that hits GitHub's error
page. Brand impact: auth is the brand-truth surface. CPO ack is the
single product-owner sign-off on the technical approach.

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-05-04-fix-github-sso-redirect-uri-mismatch-plan.md
Branch: feat-one-shot-fix-github-sso-redirect-uri.
Worktree: .worktrees/feat-one-shot-fix-github-sso-redirect-uri/.
Issue: TBD (file at start of /work).
Context: GitHub SSO returns redirect_uri-not-associated on prod. Single GitHub App `Iv23li9p88M5ZxYv1b7V` serves both Supabase-mediated SSO and github-resolve flows. Live deepen probes show both flows currently pass GitHub's redirect_uri check — leading hypothesis is H_A (already-fixed) or H_B (custom-domain dual-registration drift). Plan ships Phase 4 three-URL probe + Phase 5 workflow gate fix as guardrails regardless of cause.
```
