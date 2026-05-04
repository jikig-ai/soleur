---
title: GitHub App callback URL drift — single client_id serves three callbacks
date: 2026-05-04
category: integration-issues
related_issues: [1784, 3183]
related_prs: [3181]
tags: [github-oauth, supabase, redirect_uri, oauth-probe, custom-domain]
---

# GitHub App callback URL drift — single client_id serves three callbacks

## Symptom

GitHub renders an error page during OAuth sign-in:

> The `redirect_uri` is not associated with this application.

User cannot complete sign-up or "Connect GitHub" from `/connect-repo`.
For founders auditing the product, this looks like a broken core flow at
the worst possible moment (the first 60 seconds).

## Root invariants

The investigation surfaced four invariants that are not obvious from
either GitHub's docs or the codebase:

1. **One client_id, two flows.** Both Flow A (Supabase-mediated SSO via
   `signInWithOAuth({provider:"github"})`) and Flow B (App-direct OAuth
   via `/api/auth/github-resolve/route.ts`) use the SAME GitHub App
   `Iv23li9p88M5ZxYv1b7V`. Supabase's GitHub provider is bound to our
   GitHub App, not a separate OAuth App. Therefore a single edit to the
   GitHub App's "Callback URL" textarea governs both flows.

2. **Three required callback URLs, not one.** The textarea must contain:
   - `https://app.soleur.ai/api/auth/github-resolve/callback` (Flow B)
   - `https://api.soleur.ai/auth/v1/callback` (Flow A custom-domain
     advertised state)
   - `https://ifsccnjhymdmidffkzhl.supabase.co/auth/v1/callback`
     (Flow A canonical, advertised during custom-domain re-provisioning)

   Per Supabase's own custom-domain docs:
   > "Add the custom domain Supabase Auth callback URL **in addition to**
   > the Supabase project URL."

   Losing the canonical entry breaks Flow A immediately whenever Supabase
   re-issues the custom-domain CNAME (cert renewal failure, edge cache
   flap, etc.). The window may be minutes; the user impact is total for
   that window.

3. **Body-grep is load-bearing — both healthy and failing states are
   HTTP 200.** `https://github.com/login/oauth/authorize?…` returns
   HTTP 200 whether the redirect_uri is registered (renders the login
   form) or unregistered (renders the error page). HTTP-code probes
   (which earlier OAuth probes used) cannot distinguish. The probe MUST
   grep response bodies for the literal substring
   `redirect_uri is not associated`. Adding `Application suspended`
   and a positive proof grep (`<form` OR `Authorize`) catches the
   adjacent failure modes (suspension, GitHub HTML rewording).

4. **GitHub App callback URLs are NOT REST-mutable.** `GET /app` returns
   `null` for the callback URL field. Mutation requires the dashboard UI
   (CSRF-protected) or the App-Manifest creation flow. Therefore
   automated remediation is impossible — the only durable defenses are
   (a) a probe that exercises GitHub's authorize endpoint and greps for
   the rejection string, and (b) a workflow gate that blocks closing
   the tracking issue without verbatim verification.

## Why the previous fix (#1784) recurred

#1784 had the same symptom and was closed via `/ship` Phase 7 Step 3.5
follow-through, but the closing comment was a "verified" assertion
without:

- Verbatim redirect_uri values (so future operators couldn't diff
  against the current state).
- A workflow run ID (so the closure couldn't be cross-referenced to a
  green probe).
- A textarea byte count (so silent whitespace/case drift would go
  undetected).

The gap let #1784 close while the underlying configuration (probably
the canonical `supabase.co` URL) was missing. The next custom-domain
flap re-broke it; that re-break was reported as #3183.

PR #3181 fixes the gate per `wg-when-fixing-a-workflow-gates-detection`
(retroactively apply the fixed gate to the case that exposed the gap).

## Hypotheses that were demoted by live evidence

The original plan led with `Flow B github-resolve callback URL missing`
(H_E). Live curl probes during deepen-plan showed that URL was
registered. The plan was re-prioritised to:

- **H_A** (already-fixed) and **H_B** (custom-domain dual-registration
  drift) as the leading hypotheses.
- H_E demoted to "matches symptom shape but not current state."

When live probes contradict a plan's leading hypothesis, the plan must
be re-prioritised before any operator action — not just acknowledged.
Operate-then-verify on a stale hypothesis ships either no fix or the
wrong fix.

## Anti-patterns documented

- **Rotating `GITHUB_CLIENT_SECRET` "to be safe."** Secret rotation does
  not affect callback URL registration. Rolling the secret is harmless
  but extends MTTR by reinforcing a wrong mental model.
- **Removing the canonical `supabase.co` URL "because we have a custom
  domain."** The custom-domain advertisement is not guaranteed under
  re-provisioning; the canonical URL is the durable fallback.
- **HTTP-code-only probes.** GitHub returns HTTP 200 in both healthy
  and failing states. The body grep is the only reliable signal.
- **Single-grep probes.** If GitHub rewords the error string ("redirect_uri"
  → "redirectUri"), a single-grep probe goes silent-pass. Augment with
  `Application suspended` (adjacent failure mode) and a positive proof
  grep (`<form` OR `Authorize`) so HTML rewording surfaces as drift
  rather than green.
- **Closing follow-through issues without verbatim verification.** The
  drift class is exactly the recurrence pattern between #1784 and
  #3183. The closure gate (verbatim URLs + run ID + byte count) is the
  only durable guard.

## Operator-facing artifacts

- `knowledge-base/engineering/ops/runbooks/github-app-callback-audit.md`
  — step-by-step audit procedure and rollback.
- `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md`
  — failure-mode-keyed triage for the new probe outputs.
- `apps/web-platform/test/oauth-probe-contract.test.ts` — load-bearing
  sentinel constants and required-paths assertions; refresh in lockstep
  with the workflow if GitHub rewords its error page.

## Refresh trigger

If the quarterly `skill-freshness` audit re-tests the probe against a
deliberately-broken redirect_uri and the response no longer contains
`redirect_uri is not associated`, GitHub has reworded the page. Update
both the workflow grep target AND the sentinel constants in the test
file in the same PR — the test gate prevents partial updates.
