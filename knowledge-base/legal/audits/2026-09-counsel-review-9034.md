---
title: "Counsel review audit — #8978 / PR #9034 (Art. 15+20 self-serve export re-authentication check time-bounded: dated technical-behavior entries on all three published notices + Eleventy mirrors + compliance-posture annotation)"
type: counsel-review
date: 2026-09-28
issue: 8978
pr: 9034
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
signed_off_at: 2026-09-28
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "DISCHARGED subject to ONE in-PR narrowing (C1, below) that the lead applies before merge — or discharges by code. Seven artifacts in scope: the three canonical notices (privacy-policy.md, gdpr-policy.md, data-protection-disclosure.md), their three Eleventy mirrors, and the compliance-posture.md annotation. Every amended sentence was verified against the shipped code (dsar-reauth.ts, request-auth.ts, the reauth route and the three export routes that consume it), not against the PR description. All but one claim holds: the dated entries' and the amended sentences' phrasing 'the re-authentication check is time-bounded … rather than waiting without a deadline' over-covers — `supabase.auth.signInWithPassword` inside the same step remains an unbounded remote leg, so a stall on the password-verification call itself still waits without a deadline. That is the #4353/#4558 prose-falsifiable-by-grep class in miniature; the correction narrows a statement and changes no conclusion. Everything else holds: lawful bases (Art. 6(1)(c) fulfilment; Art. 6(1)(f) telemetry) untouched, no new category, recipient, sub-processor, transfer, retention, or right; the new Sentry timeout breadcrumbs carry an op name only and sit inside the disclosed §(m)/Sentry-row envelope; 'retryable error' is literally true (the timeout lands on not_found/401 BEFORE consumeReauthEvent, so the reauth event is not burned). No Art. 33 and no Art. 34 duty arises."
blocking_findings: []
required_before_merge_DISCHARGED:
  - "C1 — The published claim 'the re-authentication check is time-bounded … rather than waiting without a deadline' over-covers: `signInWithPassword` in the same user-facing step is still awaited unboundedly (reauth route.ts). Narrow the sentence and the dated-entry phrasing in all six published files (exact text under §Conditions), OR bound `signInWithPassword` in the same 10s race — under the code-discharge path the sentence becomes literally true and no text change is required."
optional_precision_notes:
  - "O1 — The bound is env-tunable (`SOLEUR_AUTH_GETUSER_TIMEOUT_MS`, default 10_000ms). The published text deliberately carries no figure, so the claim stays true at other sane values; a pathological override would falsify it in operation. Engineering knob; not conditioned."
  - "O2 — The posture annotation's second clause uses the same loose 'reauth check' shorthand as the published prose, but its first clause is precise ('getActiveSessionId's auth verify + session read are now 10s-race bounded'), so the internal record is accurate as written. No change."
  - "O3 — The Art. 30 register carries no dated TOM marker for the bounded remote legs on the DSAR surface. No PA cell's substance changed (categories, purposes, recipients, retention identical), so a marker is recommended, not required."
  - "O4 — `boundedAuthGetUser`/`boundedAuthGetSession` collapse a REJECTING auth call to the same null arm as a timeout, so a genuine IdP outage (fast reject) now surfaces the `*_bounded_timeout` breadcrumb without an elapsed 10s. Fail-closed either way; the breadcrumb is op-name telemetry only. Consistent, not conditioned."
attests:
  - "docs/legal/privacy-policy.md — the September 28, 2026 dated entry and the amended 'Self-serve (Articles 15 + 20)' sentence, subject to C1"
  - "docs/legal/gdpr-policy.md — the September 28, 2026 dated entry and the amended 'Data-subject-rights fulfilment' bullet sentence, subject to C1"
  - "docs/legal/data-protection-disclosure.md — the September 28, 2026 dated entry and the amended §2.3(l) sentences (including the 'bound governs the identity-verification step only' qualifier), subject to C1"
  - "plugins/soleur/docs/pages/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md — mirror parity (identical amended sentences; 'Last Updated September 28, 2026' hero lines), carrying C1 transitively"
  - "knowledge-base/legal/compliance-posture.md — the 2026-09-28 annotation and last_updated bump (precise; unconditionally accurate)"
does_not_attest:
  - "The engineering change itself — boundedAuthGetUser/boundedAuthGetSession correctness, the wider #8978 middleware/RPC bounding sweep, the watchdog/test-all changes, the postmortem, the learnings entries, and the #8978 soak followthrough script (technical controls and engineering records; counsel attests the legal records' statements about them, not their correctness)"
art_33_triggered: false
art_34_triggered: false
re_evaluation_triggers: "(1) If C1 is discharged by text, the replacement wording must keep the bound scoped to the session-verification legs; any broader phrasing re-opens this review. (2) If any remote leg inside the reauth step is bounded or unbounded differently than at audit (including signInWithPassword), the published sentence and this attestation are re-read against the new shape. (3) Any change to what the export packages, retains, discloses, or whom it serves is a fresh legal-doc change outside this audit. (4) Standing external-counsel triggers: first arm's-length (non-Jikigai-affiliate) user exercising the Art. 15/20 channel, any affected subject outside the EEA, any regulated-industry tenant."
---

# Counsel review audit — #8978 / PR #9034 (time-bounded DSAR re-authentication)

This file is the evidence for the ship Phase 5.5 Counsel-Review CLO-Attestation Gate on PR #9034
(issue #8978). The gate fired on the `docs/legal/` + Eleventy-mirror + `knowledge-base/legal/` edits
this PR carries — the lockstep amendment for the re-authentication bound. The brand-survival
threshold is `single-user incident`. The CLO agent is the v1 attestation authority; the operator
holds an optional veto.

## Scope and limit check

- **Legal diff is exactly the stated surface.** `git diff origin/main...HEAD -- docs/legal
  plugins/soleur/docs/pages/legal knowledge-base/legal` touches 7 files: the three canonical
  notices (a dated `**Last Updated:** September 28, 2026` entry demoting the prior entry to
  `Previous:`, plus one added sentence each — two in the DPD, which also gains the scoping
  qualifier), the three mirrors (identical sentences + `Last Updated September 28, 2026` hero
  lines), and `compliance-posture.md` (`last_updated` bump + dated annotation). No other legal
  file moved.
- **Prose verified against code, not the PR description.** Sources of truth read in full:
  `apps/web-platform/server/request-auth.ts` (`boundedAuthGetUser`, `boundedAuthGetSession`,
  `authGetUserTimeoutMs` → `SOLEUR_AUTH_GETUSER_TIMEOUT_MS` default 10_000ms, Promise.race +
  `clearTimeout`, timeout → `null` + Sentry breadcrumb), `apps/web-platform/server/dsar-reauth.ts`
  (`getActiveSessionId` now calls both bounded helpers; timeout/throw →
  `ReauthEventInvalid("not_found")`), `app/(dashboard)/dashboard/settings/privacy/reauth/route.ts`
  (both helpers; null → 401 `Unauthorized`), and the consumers `app/api/account/export/route.ts`,
  `[jobId]/route.ts`, `[jobId]/download/route.ts` (`not_found` → 401; `session_mismatch` → 403).
- **No `[DRAFT — pending` markers** in the legal diff. Citations in the posture annotation are by
  symbol name (`getActiveSessionId`), not line number. Production untouched — reads only.

## Per-artifact verdict

| # | Artifact | Verdict | Verified against |
|---|---|---|---|
| P1 | `docs/legal/privacy-policy.md` — dated entry + amended Self-serve sentence | **APPROVED WITH C1.** Form of the dated entry correct (`Last Updated`/`Previous:` chain preserved, ref PR #9034, "no change to the substance" accurate). The amended sentence is true of every bounded leg — **but see F1**: `signInWithPassword` inside the same step is unbounded. | route.ts, dsar-reauth.ts, request-auth.ts |
| P2 | `docs/legal/gdpr-policy.md` — dated entry + amended fulfilment bullet | **APPROVED WITH C1.** Lawful-basis recital unchanged and correct (Art. 6(1)(c) for bundle + audit row). Same over-breadth in the trailing sentence → C1. | gdpr-policy.md diff, request-auth.ts |
| P3 | `docs/legal/data-protection-disclosure.md` — dated entry + §2.3(l) two sentences | **APPROVED WITH C1.** The second sentence ("The bound governs the identity-verification step only; bundle scope, retention, and delivery are unchanged") is exactly right and is the correct mitigation — but the first sentence still claims "the re-authentication check is time-bounded" for a step that retains an unbounded remote call → C1. | §2.3(l) diff, route.ts:95 |
| P4 | Eleventy mirrors (3 files) | **APPROVED, carrying C1.** Amended sentences byte-identical to canonical; hero `Last Updated` lines updated; the extra mirror-only hunk is the hero line, correctly absent from canonical md. | mirror diff, canonical diff |
| P5 | `knowledge-base/legal/compliance-posture.md` — `last_updated` + 2026-09-28 annotation | **APPROVED.** The precise clause names exactly the bounded legs (`getActiveSessionId`'s auth verify + session read, 10s-race); "no change to what the export packages, retains, or discloses" verified true; "No Art. 33/34 trigger" correct. (O2.) | posture diff, dsar-reauth.ts |
| P6 | Lockstep convention | **APPROVED.** Dated entry + demoted Previous + amended body sentence + mirror parity + posture annotation — all four elements present on all three notices. | full legal diff |
| P7 | Legal substance | **APPROVED.** No new category, recipient, sub-processor, transfer, retention, basis, or right. The only new emission is op-name Sentry breadcrumbs (`auth.getuser.bounded_timeout`, `auth.getsession.bounded_timeout`, `session-jwt-email.session_timeout`) — no identifier, inside disclosed §(m)/Sentry-row envelope. Consent not engaged; Art. 6(1)(f) untouched. | request-auth.ts breadcrumb bodies, DPD §(m), processor table |

## Findings

- **F1 (C1, in-PR): the published bound claim over-covers one remote leg.** The notices say "the
  re-authentication check is time-bounded: if the identity provider responds unusually slowly the
  flow returns a retryable error rather than waiting without a deadline." Verified true for every
  session-resolution leg: `boundedAuthGetUser`/`boundedAuthGetSession` race
  `supabase.auth.getUser()`/`getSession()` against a 10s timer in both the reauth POST route and
  `getActiveSessionId` (consumed by the export enqueue, reissue and download routes), and a timeout
  resolves `null` → `not_found`/401. **But `supabase.auth.signInWithPassword` — the
  password-verification call inside that same user-facing step (reauth route.ts) — is still awaited
  unboundedly**, and nothing else wraps it (no `maxDuration`, no client fetch timeout). A stall on
  that leg still waits without a deadline, so the sentence as written is falsifiable by grep on a
  published notice — the #4353/#4558 class. The fix narrows the claim to the bounded legs; the
  internal posture annotation already scopes it correctly ("getActiveSessionId's auth verify +
  session read"). Ruled a correction, not a block: the claim is directionally true for the
  incident-observed stall class (#8978 getUser/getSession/token-refresh), the residual is one call
  on one step, and no conclusion (basis, category, right) depends on it.
- **F2: "retryable" is literally true.** In `requireFreshReauth`, `getActiveSessionId` runs BEFORE
  `consumeReauthEvent`, so a bounded-leg timeout throws `not_found` without burning the single-use
  reauth event — the user retries with the same event or re-enters the password (route 401), and the
  email fallback stands for persistent failure.
- **F3: no substance change.** Bundle contents, 7-day signed-URL delivery, audit-row shape and
  24-month retention, sub-processors (Supabase Storage, Resend, Sentry), and every lawful basis are
  byte-identical pre/post. The only new data flow is three op-name-only Sentry breadcrumbs —
  inside the disclosed operational-telemetry envelope (DPD §(m); Sentry processor row).
- **F4: Art. 33/34 not engaged.** No confidentiality/integrity loss; this is an availability
  improvement on a data-subject-rights channel — it *narrows* the window in which an Art. 15/20
  request can stall.
- **F5: lockstep form correct.** All four convention elements on all three notices; mirror parity;
  dated posture annotation. `generated-date` frontmatter untouched (per convention it tracks the
  generation run, not amendment history).

## Conditions

**C1 — apply before merge (text path).** In all six published files, narrow the amended sentence:

> The re-authentication check is time-bounded: if the identity provider responds unusually slowly the flow returns a retryable error rather than waiting without a deadline.

to:

> The session-verification legs of the re-authentication check are time-bounded: if the identity provider responds unusually slowly while the session is being verified, the flow returns a retryable error rather than waiting without a deadline on those steps.

and likewise narrow the dated-entry clause in each file's amendment history:

> The password re-authentication check on the Article 15 + 20 self-serve data-export flow is now bounded: on an unusually slow authentication provider the check returns a retryable error rather than leaving the request without a deadline.

to:

> The password re-authentication check on the Article 15 + 20 self-serve data-export flow now bounds its session-verification legs: on an unusually slow authentication provider the flow returns a retryable error on those steps rather than leaving the request without a deadline.

**Code-discharge alternative (the #8043 precedent):** wrap `supabase.auth.signInWithPassword` in the
same 10s race (or a `boundedAuthSignIn` sibling) so the timeout lands on the route's existing 401
arm. Then the original sentences are literally true as written and no text change is required; the
audit is re-read as fully discharged on the amended tree.

O1–O4 are non-blocking.

## Verification commands (re-runnable from the worktree)

- `git diff origin/main...HEAD --stat -- docs/legal plugins/soleur/docs/pages/legal knowledge-base/legal` → 7 files, 17+/16-.
- `grep -n 'signInWithPassword\|boundedAuth' "apps/web-platform/app/(dashboard)/dashboard/settings/privacy/reauth/route.ts"` → bounded helpers at the getUser/getSession lines; **unbounded** `signInWithPassword` at the password-verify line (the C1 fact).
- `grep -n 'SOLEUR_AUTH_GETUSER_TIMEOUT_MS\|Promise.race\|bounded_timeout' apps/web-platform/server/request-auth.ts` → the 10s race, env knob, and both timeout breadcrumbs.
- `grep -n 'boundedAuthGetUser\|boundedAuthGetSession\|not_found' apps/web-platform/server/dsar-reauth.ts` → bounded legs + the not_found arms in `getActiveSessionId`.
- `grep -c 're-authentication check is time-bounded' docs/legal/*.md plugins/soleur/docs/pages/legal/*.md | grep -c ':1'` → 6 (one amended sentence per published file; `time-bounded` alone also matches two pre-existing unrelated gdpr-policy.md lines).
- `grep -rn 'is now bounded' docs/legal plugins/soleur/docs/pages/legal | wc -l` → 6 (the dated-entry clause per published file).
- After C1 text-path: `grep -rn 'session-verification legs' docs/legal plugins/soleur/docs/pages/legal | wc -l` → ≥6, and `grep -rn 'is now bounded' docs/legal plugins/soleur/docs/pages/legal | wc -l` → 0.

---

## Post-audit discharge note (2026-09-28, same PR)

**C1 discharged by CODE, not text.** `supabase.auth.signInWithPassword` in
`app/(dashboard)/dashboard/settings/privacy/reauth/route.ts` is now wrapped in
the same 10-second `Promise.race` (env `SOLEUR_AUTH_GETUSER_TIMEOUT_MS`), its
timeout and throw arms collapsing onto the route's existing 401
"Password verification failed" response — fail-closed, and the single-use
reauth event is still not burned on a timed-out attempt (issue happens only on
success). The published "re-authentication check is time-bounded" sentence is
now literally true across the whole step, so the six published files stand
unmodified. Re-verification: `grep -n 'Promise.race\|bounded_timeout' "apps/web-platform/app/(dashboard)/dashboard/settings/privacy/reauth/route.ts"`.
