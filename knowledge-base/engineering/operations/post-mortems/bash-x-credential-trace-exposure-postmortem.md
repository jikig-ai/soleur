---
title: "Two live API tokens printed into an agent transcript by `bash -x`"
date: 2026-09-04
incident_pr: "#7797"
incident_window: "2026-09-03 ~15:30Z (single command); exposure persists while the credentials remain valid"
recovery_at: "n/a — not yet recovered; both credentials are still live"
suspected_change: "none — no change caused this; `bash -x` on a bearer-carrying script is the standing hazard"
brand_survival_threshold: aggregate pattern
status: ongoing
triggers:
  - operator ran a credential-carrying script under `bash -x` to debug a failing guard
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

> **Secret-leak PIR.** The exposed values are deliberately not reproduced in this
> document, in the source issue, or in any commit. They live only in the agent
> session transcript named below. Do not paste a credential into this file to
> "prove" the exposure — that would widen it.

# Incident Overview

While building `apps/web-platform/infra/cutover-verify.sh` for the ADR-194 apex
cutover, the script was run under `bash -x` to debug a failing guard. The script
authenticates with `curl -H "Authorization: Bearer $TOKEN"`. Shell tracing echoes
each command **after expansion**, so both bearer tokens were printed in full into
the agent session transcript.

Exposed, both from Doppler `soleur/prd_terraform`:

- `SENTRY_AUTH_TOKEN` — a `sntryu_`-prefixed Sentry user auth token
- `BETTERSTACK_API_TOKEN_READONLY` — a Better Stack API token

## Status

`ongoing` — the source of the *next* leak is closed, but **both credentials from
this one are still valid**. Rotation is a credential-entry gate (it requires an
authenticated Sentry session to mint a replacement) and is the operator's to
perform; it is tracked on #7797, which stays open for exactly that reason.

## Symptom

Two live third-party API tokens rendered in cleartext in a session transcript.
No service degradation, no user-visible symptom — this is an exposure incident,
not an availability one, which is precisely why nothing alarmed.

## Incident Timeline

- **Start time (detected):** 2026-09-03T15:33:16Z (issue #7797 filed)
- **End time (recovered):** not yet — credentials still live
- **Duration (MTTR):** open

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-09-03 ~15:30 | Ran `cutover-verify.sh` under `bash -x` to debug a failing guard; both bearer tokens printed into the transcript. |
| human | 2026-09-03T15:33Z | Detected on sight and filed #7797 as `priority/p0-critical` / `type/security`. |
| agent | 2026-09-03 | `cutover-verify.sh` given a self-refusal — the first script in the repo to carry one. |
| agent | 2026-09-04 | ADR-202 recorded; commit-time lint built; 22 further scripts remediated. |
| agent | 2026-09-04 | Review found the guard narrower than its own property in nine ways; all fixed. |
| human | pending | Rotate both credentials into Doppler `soleur/prd` and `soleur/prd_terraform`. |

## Participants and Systems Involved

Operator (detection, rotation), Claude Code (remediation), Sentry and Better
Stack (credential issuers), Doppler `soleur/prd_terraform` (credential store).

## Detection (+ MTTD)

- **How detected:** external/manual — the operator read the transcript. No
  monitoring system detected it, and none could have: the leak is a rendering of
  a legitimate value into a legitimate output stream.
- **MTTD:** ~3 minutes (immediate, on sight).

## Triggered by

user — a routine debugging reflex on a credential-carrying script.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| `bash -x` traces after expansion, so any bound secret is printed | Measured: `+ scalar=<value>` on a bare assignment | none | **confirmed** |
| The convention existed but had no enforcement | The rule sat as prose in ~8 places (`sentry-issue.sh`, two workflow anchors, a skill, `zot-inventory.sh`, several plans) with zero mechanical checks | none | **confirmed** |
| Argv hygiene alone would have prevented it | `curl --config -` keeps the token off argv | Refuted: the leak is at the **bind**, before any command; and a traced parent leaks a callee's argv regardless | rejected |

## Resolution

Not yet resolved. The *recurrence* path is closed (see below); the *exposure* is
not, and will not be until both tokens are rotated.

## Recovery verification

Pending. Recovery is verified when a Sentry API call using the old
`SENTRY_AUTH_TOKEN` returns 401 and the Doppler values in both `soleur/prd` and
`soleur/prd_terraform` are the replacements.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why were two live tokens in a transcript?** `bash -x` printed them.
2. **Why did `bash -x` print them?** Tracing echoes commands after expansion, so
   a secret leaks at the moment it is *bound*, before it reaches any command.
3. **Why was the script run under `bash -x`?** It is the natural next step when a
   token-carrying script misbehaves, and nothing in the loop warned about it.
4. **Why did nothing warn?** The prohibition existed only as prose, in ~8 places,
   none of them executable. Prose cannot see `bash -x`.
5. **Why was it only prose?** No one had chosen an enforcement mechanism for a
   hazard that is a property of *runtime state* rather than of committed text.
   ADR-202 is that missing criterion.

## Versions of Components

- **Version(s) that triggered the outage:** n/a — not a versioned regression.
- **Version(s) that restored the service:** n/a.

## Impact details

### Services Impacted

None degraded. The blast radius is the *capability* the two tokens confer:
Sentry org read/write via a user auth token, and Better Stack read-only API
access. No evidence of use by any third party.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: none.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

Infrastructure credentials only; no personal data reached the transcript, which
is why Art. 33/34 are both `false`.

### Revenue Impact

None.

### Team Impact

One P0 triage, one full remediation cycle, and an outstanding operator rotation.

## Lessons Learned

### Where we got lucky

The operator read the transcript and recognised the tokens on sight. Nothing
would have surfaced this otherwise — there is no detector for "a legitimate
value was rendered into a legitimate stream". Had the same command run inside a
GitHub Actions job whose output reaches a public issue comment, the exposure
would have been public rather than local, and probably unnoticed.

### What went well

Detection was immediate and the issue was filed with the right severity. The
first remediated script (`cutover-verify.sh`) was fixed the same day.

### What went wrong

The guard built to prevent recurrence shipped, twice, with the defect class it
exists to forbid — an assembly narrower than the property it enforces. A review
panel found nine such gaps, seven introduced by the fixing PR itself, all green
beforehand. Notably: the suite asserted the guard *existed* rather than that *no
credential value appears in the trace*, so a one-character revert in any of 22
production copies would have re-shipped this exact leak, lint-green.

Separately, the `tests/` path exclusion was exempting a live production CI gate
that binds a Cloudflare token and whose output is posted verbatim into a public
issue comment — a second, wider instance of the same class, found by the same
review.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #7797 | Rotate `SENTRY_AUTH_TOKEN` and `BETTERSTACK_API_TOKEN_READONLY` into Doppler `soleur/prd` and `soleur/prd_terraform`; verify the old Sentry token returns 401. Operator-only (credential-entry gate). | open |
| #7842 | Build the complements the lint cannot reach: the PreToolUse hook for uncommitted `bash -c` and the CI `run:`-body form lint. | open |
| #7843 | Sweep 61 scripts / 108 call sites from argv bearer tokens to `curl --config -`; a traced parent leaks a callee's argv even when the callee's own preamble is clean. | open |
