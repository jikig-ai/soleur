# Decision challenges — feat-one-shot-7997-sentry-curl-transport-confinement

Persisted per ADR-084 (headless arm). `/ship` renders these into the PR body and
files them as `action-required`. The operator's stated direction is the default;
each entry below is a challenge to it, not a change already applied.

---

## Challenge 1 — the region-discovery loop this issue asks us to preserve is measurably dead

**Your stated direction.** Issue #7997's done-when says
*"`sentry-monitors-audit.sh` region discovery still works — proven, not asserted."*
The plan honours that: the loop is kept, its behaviour is unchanged, and it is
proven hermetically with a stubbed `curl`.

**What we found while doing it.** Region discovery cannot succeed with any
credential this repository holds. Measured live against all four candidate hosts,
with **both** `SENTRY_AUTH_TOKEN` and `SENTRY_IAC_AUTH_TOKEN`:

| candidate | `/api/0/users/me/` |
|---|---|
| `jikigai-eu.sentry.io` | 403 |
| `eu.sentry.io` | 403 |
| `de.sentry.io` | 404 |
| `sentry.io` | 403 |

Both tokens return **200** on the org-scoped `/api/0/organizations/jikigai-eu/`.
The loop needs a 200 on `/users/me/`, which only a *personal* token returns; the
script's own header says so. And it is never reached anyway: all five callers set
`SENTRY_API_HOST`, and three of them (`sentry-audit-gate.yml`,
`scheduled-sentry-alert-drift.yml`, `reusable-release.yml`) hard-fail when it is
empty.

**Why it matters here.** The loop is the only reason `${SENTRY_ORG}` is
interpolated into a *hostname*, and therefore the only reason `SENTRY_ORG` needs a
shape guard at all. Keeping it also means its guard is exercised by stubs only,
permanently — nobody will ever observe it working live.

**What the reviewers said.** The CTO ruled **keep it**: deleting a documented
capability the issue's own done-when names is an operator-direction reversal that
does not belong inside a security fix, and the operator should rule on removal
with the measurement in front of them. The code-simplicity review ruled **delete
it**, and showed that most of the plan's remaining machinery — the four-member
array, the discovery test arms, two guard mutation rows and a follow-up issue —
exists only to keep it safe.

**What the plan does.** Follows the CTO: keeps the loop, and files
`Deferral 1` carrying this measurement so the decision is made deliberately.

**The question for you.** Delete the loop and require `SENTRY_API_HOST` (as
`scripts/sentry-alert-live-fidelity.sh` already does), or keep it? Deleting it
removes a credentialed call site rather than hardening one, and shrinks this PR
noticeably. Keeping it preserves a back-compat affordance for a personal token
nobody currently holds.

---

## Challenge 2 — the pin narrows the destination; it does not close it

**What the plan delivers.** After this PR, a compromised `SENTRY_API_HOST` or
`SENTRY_ORG` can no longer send the Sentry bearer to an arbitrary host. Measured
on `main` today, it can: the token reached
`https://attacker.tld/api/0/organizations/jikigai-eu/`.

**The residual, stated plainly.** The allowlist is *parameterised* —
`${SENTRY_ORG}.sentry.io` is a member — and Sentry org slugs are self-service. So
an attacker who can set `SENTRY_ORG` still reaches `<their-org>.sentry.io`, a host
whose contents they control, over TLS, carrying the bearer. This PR narrows the
exfil from *any host on the internet* to *any Sentry org subdomain*.

**Why the plan does not close it.** Closing it means adjudicating `$SENTRY_ORG`
against the org id that Gate 1 returns — a different mechanism, in a script whose
Gate 1 runs *after* the discovery probes. That is `Deferral 2`.

**The question for you.** Is the narrowed residual acceptable for now, or should
the org-id adjudication be folded into this PR before merge?
