---
title: "Two live API tokens printed into an agent transcript by `bash -x`"
date: 2026-09-04
incident_pr: "#7797"
incident_window: "2026-09-03 ~15:30Z (single command); Better Stack exposure ended 2026-09-03T20:10Z, Sentry exposure persists"
recovery_at: "partial — BETTERSTACK_API_TOKEN_READONLY rotated 2026-09-03T20:10Z; SENTRY_AUTH_TOKEN still live"
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

> **Superseded 2026-09-07 (#7797):** "both credentials are still valid" was
> **already false when this PIR was written**. `BETTERSTACK_API_TOKEN_READONLY`
> had been rotated on 2026-09-03T20:10Z — nineteen hours before — and the leaked
> value verified dead. Only `SENTRY_AUTH_TOKEN` remains live (re-verified
> 2026-09-07: `GET /api/0/organizations/` → 200). See the Addendum below.

## Symptom

Two live third-party API tokens rendered in cleartext in a session transcript.
No service degradation, no user-visible symptom — this is an exposure incident,
not an availability one, which is precisely why nothing alarmed.

## Incident Timeline

- **Start time (detected):** 2026-09-03T15:33:16Z (issue #7797 filed)
- **End time (recovered):** partial — Better Stack 2026-09-03T20:10Z; Sentry outstanding
- **Duration (MTTR):** open

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-09-03 ~15:30 | Ran `cutover-verify.sh` under `bash -x` to debug a failing guard; both bearer tokens printed into the transcript. |
| human | 2026-09-03T15:33Z | Detected on sight and filed #7797 as `priority/p0-critical` / `type/security`. |
| agent | 2026-09-03 | `cutover-verify.sh` given a self-refusal — the first script in the repo to carry one. |
| agent | 2026-09-03T20:10Z | **Better Stack half rotated and verified dead.** Replacement minted via Playwright dashboard automation, parity proved on all three consumer surfaces, written to Doppler `soleur/prd_terraform` over stdin, leaked token `63419` deleted; it then returned 401 on all three. Not operator-only after all. Recorded in [this comment](https://github.com/jikig-ai/soleur/issues/7797#issuecomment-3253440461) — the 401 is that comment's report, not a measurement this PIR can reproduce (the leaked value is deliberately unrecoverable). |
| agent | 2026-09-04 | ADR-202 recorded; commit-time lint built; 22 further scripts remediated. |
| agent | 2026-09-04 | Review found the guard narrower than its own property in nine ways; all fixed. |
| human | pending | Rotate `SENTRY_AUTH_TOKEN` — the remaining half, a genuine credential-entry gate. |

## Participants and Systems Involved

Operator (detection, and the pending Sentry rotation), Claude Code
(remediation, and the Better Stack rotation), Sentry and Better
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

Partially resolved. The *recurrence* path is closed (see below). The Better Stack
half of the *exposure* is closed — rotated 2026-09-03T20:10Z, leaked value revoked.
The Sentry half is open and will be until `SENTRY_AUTH_TOKEN` is rotated.

## Recovery verification

Better Stack: **done** — the leaked token returns 401 on all three consumer
surfaces (2026-09-03).

Sentry: pending. Recovery is verified when a Sentry API call using the old
`SENTRY_AUTH_TOKEN` returns 401 and the Doppler value in **`soleur/prd_terraform`**
is the replacement. Only that config is in scope: `BETTERSTACK_API_TOKEN_READONLY`
exists solely in `prd_terraform`, and while `SENTRY_AUTH_TOKEN` is present in both
`prd` and `prd_terraform` the two hold *different* tokens — verified by equality
comparison only, with no value, length or digest recorded. The leaked one is the
`prd_terraform` value, which is what #7797 records as the source. An earlier
revision of this section said "both `soleur/prd` and `soleur/prd_terraform`",
which would send the operator to rotate an uninvolved credential.

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

None degraded. The blast radius was the *capability* the two tokens confer:
Sentry org read/write via a user auth token, and Better Stack read-only API
access. The Better Stack half was retired on 2026-09-03; the Sentry capability
remains exposed. No evidence of use by any third party.

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
| #7797 | Rotate `SENTRY_AUTH_TOKEN` in Doppler `soleur/prd_terraform`; verify the old token returns 401. Operator-only (credential-entry gate — established by a Playwright attempt reaching the login form at `sentry.io/settings/account/api/auth-tokens/`, per `hr-never-label-any-step-as-manual-without`; an API 403 is explicitly NOT operator-only evidence and the #7797 thread already retracted that inference). Better Stack was already rotated 2026-09-03. | open |
| #7842 | Build the complements the lint cannot reach: the PreToolUse hook for uncommitted `bash -c` and the CI `run:`-body form lint. | open |
| #7843 | Sweep 61 scripts / 108 call sites from argv bearer tokens to `curl --config -`; a traced parent leaks a callee's argv even when the callee's own preamble is clean. | open |

## Addendum — 2026-09-07 (#7797)

**This PIR shipped with a false claim about its own subject.** It stated that
both exposed credentials were still valid. `BETTERSTACK_API_TOKEN_READONLY` had
already been rotated on **2026-09-03T20:10Z** — the leaked token
(`heartbeat-live-reconcile (read-only)`, id `63419`) deleted and reported
returning 401 on all three consumer surfaces, in a comment on #7797.

An earlier revision of this addendum said the rotation preceded this document by
"nineteen hours", derived from the `date: 2026-09-04` frontmatter. That is not
verifiable: the only in-repo timestamp for this file is its squash commit,
`2026-09-06T15:19:14Z` (`git log --diff-filter=A`), which is **67 hours** after
the rotation. Asserting an interval from a hand-written frontmatter date, inside
an addendum whose subject is restating unverified claims, was the same error one
level down. What is verifiable is the ORDER: the rotation happened first, and
this document contradicted it.

Doppler activity shows *a* `prd_terraform` secret updated at 20:07:19Z, three
minutes before that comment. It does not name the secret, so it is consistent
with the rotation rather than corroboration of it.

**Corrected state, re-measured 2026-09-07 (HTTP status only; no value printed):**

| Credential | State |
|---|---|
| `BETTERSTACK_API_TOKEN_READONLY` | rotated 2026-09-03; leaked value revoked (401) |
| `SENTRY_AUTH_TOKEN` (`prd_terraform`) | **still live** — `GET /api/0/organizations/` → 200 |

One credential remains exposed, not two.

**How the error happened, because it is the same one this incident is about.**
The claim was carried forward from the issue's *opening* body — written at
15:33Z on 2026-09-03, before the rotation — and never re-checked against the
thread that had already superseded it. Every later restatement (the PR body, the
post-merge verification comment, this PIR) inherited it, and each restatement
made it look better-established. That is precisely the failure mode recorded in
this PR's own learning file as *"a framing INHERITED from a sibling artifact,
pasted into a context whose premise you never re-checked"* — committed here
against the very issue that documents it. The operator caught it; no gate did.

**What would have caught it:** one `gh issue view 7797 --json comments` before
asserting a credential's liveness. A credential's state is not a property of the
issue that reported it — it is live infrastructure, and the only honest source is
a probe or the rotation record, never the opening description. The check is
cheaper than the correction sweep it prevents: correcting it took nine edits in
this file plus a retraction comment on #7797 and an edit to PR #7858's body —
and the first pass at those nine missed three of them.

**Also corrected by that record:** the remediation note assumed the Better Stack
half was an operator dashboard trip. It was not — an agent minted the
replacement via Playwright automation, proved old-vs-new parity on three
surfaces, wrote to Doppler over stdin, and deleted the old token. Only the Sentry
half is a genuine credential-entry gate, and the 2026-09-03 record proposes
retiring even that by migrating the ~8 `scripts/followthroughs/*.sh` consumers
off the *user* auth token onto an org-level Internal Integration (ADR-031's
`iac-terraform-prd` shape), which would make the next rotation agent-doable.
