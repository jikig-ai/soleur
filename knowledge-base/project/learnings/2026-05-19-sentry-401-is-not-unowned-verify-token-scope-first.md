# Learning: a 401 from `/api/0/organizations/<slug>/` is NOT evidence of "unowned org" — verify token scope first

**Date:** 2026-05-19
**Category:** workflow-patterns / premise-validation
**Source:** brainstorm `2026-05-19-sentry-residency-reframe-3861-brainstorm.md`, parent issue #3861, PIR Phase 8 Gate 3b correction
**Brand-survival threshold:** single-user incident
**Related:** [[2026-05-15-sentry-dsn-cluster-substring-authoritative-residency]], [[2026-05-16-brainstorm-premise-cascade-and-playwright-handoff-discipline]]

## Problem

On 2026-05-16, during Phase A2 brainstorm prereq verification, an attempt to read `https://eu.sentry.io/api/0/organizations/jikigai/` using the runtime `SENTRY_AUTH_TOKEN` (held in Doppler `prd`) returned a 302→401 chain ("Invalid org token"). The probing brainstorm classified this as "org with that slug does not exist on this edge / no admin visibility = unowned destination," cascaded the classification through three brainstorm decisions, and committed to main:

- A PIR (`sentry-phantom-ingest-destination-unreachable-postmortem.md`) framed as "49-day phantom-ingest to unowned third-party Sentry org"
- An Article 30 register PA8 §(d) "Recipient-drift after-the-fact disclosure" block with named org ID, SQL count of affected users, and Art-33 deadline
- A 4-gate destination-controllability audit script motivated by the phantom-ingest narrative
- A 3-PR atomic-swap series to move runtime to a "freshly-provisioned EU jikigai-eu org"

On 2026-05-19, two Sentry support replies arrived and falsified the entire framing:

- **Billing:** Both `jikigai` and `jikigai-eu` orgs are on EU databases (URL routing front door, not separate clusters).
- **Forensics (Rodolfo):** Org `4511123328466944` is owned by `jean.deruelle@jikigai.com`; both orgs' audit logs show all actions by the operator's user. No third-party owner ever. <!-- # gitleaks:allow issue:#3861 substantive operator-attribution for §5(2) accountability — required to preserve the verbatim Sentry-support claim -->

The probable root cause of the original 401 was **token-scope mismatch** — the runtime `SENTRY_AUTH_TOKEN` had been minted with scope only for the `jikigai-eu` slug (the new org), not for `jikigai` (the original). The 401 was an auth-scope signal, not a "unowned org" signal. The Sentry region-router 302→401 is identical between "no admin visibility on a self-owned slug" and "the slug doesn't exist" — the HTTP response cannot distinguish them.

## Solution

When `/api/0/organizations/<slug>/` returns 401, run a 3-step probe BEFORE concluding "unowned":

```bash
# Step 1: existing token vs target slug
curl -sS -o /dev/null -w "%{http_code}\n" \
  -H "Authorization: Bearer $EXISTING_TOKEN" \
  https://sentry.io/api/0/organizations/<TARGET_SLUG>/

# Step 2: same token vs a known-controllable control slug
curl -sS -o /dev/null -w "%{http_code}\n" \
  -H "Authorization: Bearer $EXISTING_TOKEN" \
  https://sentry.io/api/0/organizations/<KNOWN_OWNED_SLUG>/

# Step 3: mint short-lived (≤10min) org:read token scoped ONLY to <TARGET_SLUG>
# in Sentry UI, label "probe-YYYY-MM-DD-revoke", run Step 1 again with new token,
# revoke in same session
curl -sS -o /dev/null -w "%{http_code}\n" \
  -H "Authorization: Bearer $PROBE_TOKEN" \
  https://sentry.io/api/0/organizations/<TARGET_SLUG>/
```

**Interpretation matrix:**

| Step 1 | Step 2 | Step 3 | Conclusion |
|---|---|---|---|
| 401 | 200 | 200 | Token-scope mismatch. Self-owned slug. Action: re-mint token with correct scope. |
| 401 | 200 | 401 | Slug genuinely not member-controllable. Investigate Sentry support / owner-history. |
| 401 | 401 | — | Token itself is invalid (expired, revoked, or wrong shape). Don't proceed; mint a fresh token first. |
| 200 | — | — | Pre-existing visibility; no investigation needed. |

**Important constraint:** do NOT mint a broader-scope token to verify — that widens credential blast radius. Use a slug-scoped ephemeral token revoked in the same session.

## Key Insight

**A 401 on a Sentry org slug endpoint is auth-scope evidence, not membership evidence.** Sentry's API auth model is per-org-scoped tokens — the same response shape ("401 Invalid org token" after a region-router 302) is produced both by "the slug doesn't exist on this edge" AND by "your token has no scope for this slug, even though you're the owner." The HTTP response cannot distinguish them. Distinguishing them requires a second probe with a slug-scoped token.

More generally: **before letting an inferred premise about a third-party vendor's organizational topology bound public-facing legal disclosure, define and run the disambiguating probe inline at brainstorm Phase 1.0.5 / 1.1, NOT as a post-merge T+14d follow-through gate.** The 2026-05-17 PR series committed an Article 30 §(5)(2) recipient-drift disclosure on the un-disambiguated inference; correcting that disclosure required two brainstorms, three merged PRs, two Sentry support tickets, and a 12-day calendar wait.

## Session Errors

None directly from this session — the original cascade happened in the 2026-05-15 / 2026-05-16 brainstorms, surfaced here for capture.

**Prevention (route to brainstorm SKILL.md Phase 1.0.5):** when a brainstorm's framing depends on a vendor-API 401/403/404 to bound a public-facing legal disclosure, the disambiguating probe must run BEFORE the disclosure language is authored. Add to brainstorm Phase 1.0.5 verification patterns: "401 from a vendor org-membership endpoint is not by itself evidence of 'unowned' or 'doesn't exist' — a scope-matched probe is required to disambiguate."

## Tags

category: workflow-patterns
module: brainstorm / premise-validation / sentry
