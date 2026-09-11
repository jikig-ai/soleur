---
title: "Two live API tokens printed into an agent transcript by `bash -x`"
date: 2026-09-04
incident_pr: "#7797"
incident_window: "2026-09-03 ~15:30Z (single command); Better Stack exposure ended 2026-09-03T20:10Z; Sentry exposure ended 2026-09-08T10:34Z (~4d19h)"
recovery_at: "complete — BETTERSTACK_API_TOKEN_READONLY rotated 2026-09-03T20:10Z; SENTRY_AUTH_TOKEN rotated and leaked token revoked 2026-09-08T10:34Z"
suspected_change: "none — no change caused this; `bash -x` on a bearer-carrying script is the standing hazard"
brand_survival_threshold: aggregate pattern
status: unresolved but ended
triggers:
  - operator ran a credential-carrying script under `bash -x` to debug a failing guard
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "not due — 72h from the 2026-09-03T15:33:16Z awareness anchor computes to 2026-09-06T15:33:16Z, but no Art. 33 duty arose, so nothing fell due at that instant. If the open evidentiary limb resolves to BREACH, a fresh 72h runs from awareness of THAT finding, not retroactively from this anchor."
art_33_determination: "knowledge-base/legal/audits/2026-09-07-clo-determination-7797-credential-exposure-art-4-12.md"
art_33_determination_status: "provisional — the evidentiary limb was RUN 2026-09-08: integrity/write CLEAN (audit log, full window coverage, single known actor); confidentiality/read INCONCLUSIVE (no last-used instrument exists on this surface, see addendum finding 1)"
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

Per-role impact is recorded below as **not established**, not as **nil**. The
distinction is the point of this section: no measurement has been taken that
could distinguish the two, and an earlier revision of this document asserted
"No evidence of use by any third party" without one — the same
claim-inherited-and-never-re-checked defect the Addendum corrects one level up.

- Prospect: no impact identified.
- Authenticated app user: **not established.** See the Art. 4(12) determination below.
- Legal-document signer: no impact identified.
- Admin via Access: no impact identified.
- Billing customer: no impact identified.
- OAuth installation owner: no impact identified.

### GDPR Art. 4(12) determination — supersedes the "no personal data reached the transcript" ground

**The prior ground is withdrawn.** This document previously read: *"Infrastructure
credentials only; no personal data reached the transcript, which is why
Art. 33/34 are both `false`."* That answers the wrong question. Art. 4(12)
reaches "unauthorised **access to** personal data", so the test is what an
exposed credential **unlocks**, not what was rendered into the stream. The
controller's own Art. 30 register says so about this exact credential: PA-8
§(g) records that the Sentry API read path surfaces event
**`message` / `breadcrumb` / `tag` / `user.*` values that the ingest-time
key-name scrub (`sentry-scrub.ts`) does NOT remove**, and PA-8 §(c)(i) records
that Sentry error messages and stack traces "may incidentally include
`user_id`, request paths, request headers". The conclusion below is unchanged;
the reasoning that reaches it is not.

**Limb 1 — breach of security: SATISFIED.** A credential was rendered in
cleartext into a stream not intended to carry it. The Art. 32(1)(b)
confidentiality measure failed. This is conceded, not contested.

**Limb 2 — leading to unauthorised access or disclosure: NOT ESTABLISHED.**
The exposure channel was bounded to the operator's own session and the
Anthropic agent context, which PA-8 §(g) already records as covered by the
existing Anthropic DPA. The value was not committed, not posted to an issue,
and not emitted in CI — the public-CI path named under §Where we got lucky is
the counterfactual that did not occur. No unauthorised recipient of the
credential is established, and therefore no unauthorised access to the personal
data behind it.

**Governing rule.** `knowledge-base/legal/statutory-response-catalog.md`
§`breach-art33`, first-response checklist step 4, states for exactly this fact
pattern — a leaked key whose actual use is unknown — that **"reachability alone
does not start the Art. 33 clock."** The same rule is stated in
`knowledge-base/engineering/operations/runbooks/breach-access-log-investigation.md`
§When to run this. Reachability is the trigger for the investigation, not for
the notification.

**Art. 33(1) risk assessment, recorded in the alternative.** Type: loss of
confidentiality of a *credential*; no confidentiality breach of the data itself
established; integrity also engaged, the token carrying org read **and write**.
Nature: PA-8 §(c)(i) categories; no special categories systematically. Ease of
identification: **mixed** — helper-path and direct-capture identifiers are
`userIdHash` (HMAC-SHA256 under a Doppler-held pepper not shared with the
processor, Recital 26), but free-text message and breadcrumb content is not
covered by a *key-name* scrub and can carry raw identifiers. Severity: on
confidentiality, operational telemetry on a small operator-adjacent population;
**on integrity, PA-8 §(b)(ii) makes Sentry the canonical Art. 33
first-observed-at clock anchor, so an unauthorised write could corrupt the
controller's own breach-evidence chain** — recorded here because this document
previously recorded it nowhere. Volume: **not measured**; the 2026-05-16
register row's figure of 10 operator-adjacent accounts belongs to a different
window and is not reused. Likelihood of receipt by an unauthorised party: low
— ~3-minute detection, no publication path engaged — but **asserted rather than
measured**, and the Sentry window has not closed.

**Determination: no Art. 33 notification duty, and no Art. 34 communication
duty. PROVISIONAL, on one named open limb.** Art. 34 is assessed on its own
facts and not inferred from Art. 33: it requires a **high** risk, a strictly
higher bar not reached, with Art. 34(3)(a) squarely available on the identifier
path. If the open limb resolves to BREACH, **Art. 34 is re-run, not inherited.**

**The open limb.** The catalog and the runbook both make the access
investigation **blocking and prior to remediation**; it has not been run. Until
it is, the risk limb rests on an assertion. Recorded, not elided — see
`knowledge-base/legal/breach-register.md`, which indexes this determination with
the limb marked open.

Canonical determination:
`knowledge-base/legal/audits/2026-09-07-clo-determination-7797-credential-exposure-art-4-12.md`.
All output is draft material; external counsel re-review is reserved for this
record's frontmatter re-evaluation triggers.

### Exposure recorded asymmetrically — the two halves are not one determination

Recording both credentials under a single finding would assert a closed window
over a credential that is still live, and would borrow one plane's scrub as
mitigation for the other, when PA-8 §(g) expressly **contrasts** them.

| | `BETTERSTACK_API_TOKEN_READONLY` | `SENTRY_AUTH_TOKEN` (`prd_terraform`) |
|---|---|---|
| Exposure window | **CLOSED** — leaked value revoked 2026-09-03T20:10Z (~4h40m) | **OPEN** — still live, re-verified 2026-09-07 (`GET /api/0/organizations/` → 200); ≥4 days |
| Capability | read-only | org read **and write** — confidentiality *and* Art. 32(1)(b) integrity |
| Scrub posture behind the token | Vector 3-stage `pii_scrub` + `userId` → `userIdHash` HMAC before egress (PA-8 §(c)(ii), §(g)) — **but not uniformly**: the 2026-08-12 UPDATE (#7440 / ADR-184) records that `soleur-registry` POSTs directly by `curl` on paths where those transforms do **not** run. That plane's conclusion rests on a topology-dependent Art. 4(1) finding flagged as a re-evaluation trigger, **not** on the scrub | **None on the read path.** PA-8 §(g) (#5495) records that this surface exposes `message`/`breadcrumb`/`tag`/`user.*` values the `sentry-scrub.ts` key-name scrub does NOT remove — stated there in express contrast to the Better Stack plane |
| Art. 4(12) limb 2 | not established; window closed and compensating control in place | not established; **window open, no compensating control, investigation outstanding** |

Only the Sentry half carries the open limb. Nothing in the Better Stack
resolution is available as mitigation for it.

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
| #7797 | **BLOCKING, and ordered.** (1) **Before deleting anything**, capture the `SENTRY_AUTH_TOKEN` **last-used timestamp** from `sentry.io/settings/account/api/auth-tokens/` under an authenticated session. `GET /api/0/api-tokens/` returning **403 under a bearer is expected** — Sentry blocks token-auth against the token-management surface; the reading is session-only, and it is the *same* trip the rotation already requires, so its marginal cost is zero. Deleting first destroys it. Capturing a *use* timestamp records no value, length or digest and is permitted by this document's header. Record that the 2026-09-07 liveness probe has **already overwritten** this scalar with a controller use, degrading the instrument. (2) Pull the **Sentry Org Audit Log** (`GET /api/0/organizations/{org}/audit-logs/`, 2026-09-03T15:30Z → present) under the still-live token — the right instrument for the **write/integrity** limb, and expressly **not** for the read limb, which it does not record. (3) Return one of the three verdicts in `runbooks/breach-access-log-investigation.md` §Step 4 — BREACH / CLEAN / **INCONCLUSIVE** — with the window requested, the window actually covered, per-source instrumentation status, and the verdict as one block per §Recording the outcome. (4) **Only then** rotate in Doppler `soleur/prd_terraform` and verify 401. Escalate to vendor support if (1)–(2) come back thin — precedent at the 2026-05-16 register row. Operator-only (credential-entry gate — established by a Playwright attempt reaching the login form, per `hr-never-label-any-step-as-manual-without`). Better Stack was already rotated 2026-09-03. | open |
| #7842 | Build the complements the lint cannot reach: the PreToolUse hook for uncommitted `bash -c` and the CI `run:`-body form lint. | open |
| #7843 | Sweep 61 scripts / 108 call sites from argv bearer tokens to `curl --config -`; a traced parent leaks a callee's argv even when the callee's own preamble is clean. | open |

> **Superseded 2026-09-08 (#7797):** the `#7797` row above is left as written
> and is **no longer the instruction to follow**. Step (1) — capture the
> last-used timestamp, and *"Record that the 2026-09-07 liveness probe has
> **already overwritten** this scalar"* — names a field that does not exist on
> any surface reachable to the controller, so it cannot be performed and the
> ordering it imposed on step (4) was not a real constraint. Step (2) was
> **done** 2026-09-08: integrity limb CLEAN. Step (3) returned **INCONCLUSIVE**
> on the read limb. Step (4) is **done**: revoked and replaced 2026-09-08T10:34Z.
> The escalation to vendor support, which the row places last, is now the only
> remaining instrument and is tracked at **#7945**. Full reasoning in the
> 2026-09-08 addendum below.

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
with the rotation rather than corroboration of it. Note that 20:10Z — propagated
through `recovery_at`, `incident_window`, the timeline and the Resolution
section — is the time the rotation was **reported**, not measured; the Doppler
write at 20:07:19Z is the nearest thing to an event time on record.

**Corrected state, re-measured 2026-09-07 (HTTP status only; no value printed):**

| Credential | State |
|---|---|
| `BETTERSTACK_API_TOKEN_READONLY` | rotated 2026-09-03; leaked value revoked (401) |
| `SENTRY_AUTH_TOKEN` (`prd_terraform`) | **still live** — `GET /api/0/organizations/` → 200 |

One credential remains exposed, not two.

**How the error happened, because it is the same one this incident is about.**
The literal ancestor is a **thread comment**, 2026-09-03T16:16:34Z: *"Both
tokens remain live until then."* True when written, superseded four hours later
by the 20:10Z rotation record in the same thread. So the mechanism is not "the
opening description was trusted over the thread" — an earlier revision of this
addendum said that, and it is wrong. It is narrower and harder to catch: an
in-thread claim was inherited and the **later** in-thread record that superseded
it was never re-read. Restatements followed in #7858's PR body and its
post-merge verification comment, each making it look better-established. (This
PIR is dated 2026-09-04 and so precedes the post-merge comment; an earlier
revision listed them as a single escalating sequence, which the timestamps do
not support.)

That failure mode is recorded by name in
`plugins/soleur/skills/compound/SKILL.md` — *"a framing INHERITED from a sibling
artifact, pasted into a context whose premise you never re-checked"* — whose
gate is to name the falsifying command for every causal claim a diff adds.
`plugins/soleur/skills/review/SKILL.md` names **a credential's liveness** as a
highest-yield target for that same check.

So the honest finding is **not** "no gate existed". Two did, correctly worded,
and neither ran on #7858. The one hard rule that is mechanically checkable here,
`hr-before-asserting-github-issue-status`, mandates `gh issue view --json state`
— issue STATE, not comments — so it would not have caught a liveness claim even
if it had fired. Widening it to cover credential-liveness assertions is the
follow-up this incident actually earns; a learning is not a fix.

**What would have caught it:** one `gh issue view 7797 --json comments` before
asserting a credential's liveness. A credential's state is not a property of the
issue that reported it — it is live infrastructure, and the only honest source is
a probe or the rotation record, never the opening description. The check is
cheaper than the correction sweep it prevents: correcting it took eleven edits
in this file, a retraction comment on #7797, and a correction banner on #7858's
merged PR body — and the first pass missed three of the in-file blocks, which a
review round then found.

**Also corrected by that record:** the remediation note assumed the Better Stack
half was an operator dashboard trip. It was not — an agent minted the
replacement via Playwright automation, proved old-vs-new parity on three
surfaces, wrote to Doppler over stdin, and deleted the old token. Only the Sentry
half is a genuine credential-entry gate, and the 2026-09-03 record proposes
retiring even that by migrating the 14 `scripts/followthroughs/*.sh` consumers (16 including test
files; only 3 declare the credential through a `secrets=` directive) —
re-measured here, since ~8 was inherited from the 2026-09-03 comment
off the *user* auth token onto an org-level Internal Integration (ADR-031's
`iac-terraform-prd` shape), which would make the next rotation agent-doable.

## Addendum — 2026-09-08 (#7797): remediation complete, and two corrections to this record

Append-only. Nothing above is rewritten; this section supersedes the parts it
names. Frontmatter state was updated in place, because a corrected body sitting
above a stale machine-readable field is the failure mode that rule exists to stop.

### Remediation — the Sentry half is closed

Executed by the agent under an operator-cleared browser session.

Stated precisely, because this document's whole subject is the difference between
a value existing and a value being rendered: **no credential value was rendered
into the agent transcript, placed in a process argument list, or committed.** A
plaintext copy of the *new* token did exist briefly — written by the browser to a
`chmod 600` file at the repository root (untracked; the enclosing checkout is
bare, so no `git add` path existed), piped to Doppler over stdin, then destroyed
with `shred -u -n 3`. The pre-revocation scan of the other Doppler configs
compared each value's **last four characters** against the `1f49` suffix Sentry
itself displays; the old secret was never re-read.

| Step | Result |
|---|---|
| Replacement minted | `terraform-apply-sentry-iac-prd-2026-09-08`, id `8741628`, `****083d` — HTTP 201, same 16 scopes |
| Replacement verified | `GET /organizations/jikigai-eu/` → HTTP 200 |
| Written to Doppler `soleur/prd_terraform` | piped over stdin (never in argv); trailing characters confirmed |
| Prod value verified | HTTP 200 |
| Leaked token `6680231` (`****1f49`) revoked | HTTP 204 |
| Revocation confirmed | account token list no longer contains it |
| Plaintext working copy | `shred -u -n 3` |

**Exposure window: 2026-09-03T15:30Z → 2026-09-08T10:34Z, ~4 days 19 hours.**

Deviation from the runbook, recorded rather than elided: the step "verify the old
value returns 401" could not be run as written, because Doppler was overwritten
before the old value was captured. The substitute is stronger — the token was
deleted server-side and is absent from the account list, so it cannot
authenticate at all — but the check as specified was skipped. Before revoking,
all seven Doppler configs in project `soleur` and every secret in
`prd_terraform` were scanned for the old value; none held it.

### Finding 1 — the blocking instrument does not exist. **This withdraws a self-criticism made above.**

The remediation sequence in the action row above is ordered around capturing the
token's **last-used timestamp** before deletion, "because deletion destroys the
datum". Measured 2026-09-08: **no last-used field is exposed on any surface
reachable to the controller.** Enumerated below rather than asserted globally —
this records what could be gathered, not proof that no such datum exists
vendor-side.

- Token list page columns: Token, Created On, Scopes. No last-used.
- Per-token Edit view: Name, masked Token, Scopes. Nothing else.
- `GET /api/0/api-tokens/` under **session** auth returns 200 (the documented 403
  is bearer-auth-only, which was correct) and its complete field set is
  `application, dateCreated, expiresAt, id, name, scopes, state,
  tokenLastCharacters`. No `dateLastUsed`/`lastUsed`/`last_used`.
- The org-token surface holds zero tokens, so it is not an alternative source.

Two consequences:

1. **The confidentiality limb of the ordering constraint was vacuous** — ordered
   around a field that does not exist. The integrity limb was not: the audit log
   is unaffected by rotation and could have been pulled at any time. Rotation was
   additionally gated on an operator-cleared browser session, which is a real
   gate, so the delay is not attributable to the phantom instrument alone.
2. **Withdrawn — this document's own action row, and the determination's.** The
   action row above says *"Record that the 2026-09-07 liveness probe has
   **already overwritten** this scalar with a controller use, degrading the
   instrument."* The determination puts it more strongly: *"The 2026-09-07
   liveness probe performed while preparing this determination has already
   overwritten the scalar with a controller use — a real, self-inflicted
   degradation of the instrument."* Both are withdrawn: there is no scalar, so
   nothing was overwritten and nothing was degraded. The self-criticism was
   written into a signed determination without anyone verifying that the field
   it named existed — the same defect class this document already records twice.

### Finding 2 — the scope class was understated (and my first write-up of this was itself wrong)

This record's capability row says the token carried "org read **and write**",
and the CLO determination says the same and engages the integrity limb on it.
**Both were right about writes.** The refinement is that the token actually
carried **admin**: `org:admin`, `event:admin`, `project:admin`, `team:admin`,
plus `org:integrations` — materially more than write, reaching member
management, integrations and project deletion.

Two corrections of my own belong here, both made while writing this addendum.

**(i)** The 2026-09-08 issue comment first asserted that both records
"characterise it as read-scoped". False, and written without reading the
capability rows above.

**(ii)** I then named `plugins/soleur/skills/postmerge/SKILL.md` as "the
genuinely false site" for calling `SENTRY_AUTH_TOKEN` read-only, and edited it to
add a fallback. **That was also wrong, and it was the more dangerous error.**
`SENTRY_AUTH_TOKEN` names **two different credentials** — a fact this document
already warns about at §Recovery verification. Measured 2026-09-08 against
`GET /organizations/<org>/issues/<id>/`:

| Doppler location | Result |
|---|---|
| `soleur/prd` — what the postmerge phase actually resolves | **403** |
| `soleur/prd_terraform` — the leaked personal token, org/project/team admin | **200** |

The skill's claim was **correct for the credential it reads**. I measured the
other one and generalised across the very boundary this document flags as one
that "would send the operator to rotate an uninvolved credential". The edit was
reverted; the skill now names the Doppler config in its claim and records both
measurements. Had it shipped, the phase would have 403'd in production.

That is three corrections of mine inside one incident, all the same shape:
asserting what a credential or a document does, instead of calling it or reading
it.

### Finding 3 — the access investigation was run

`GET /api/0/organizations/jikigai-eu/audit-logs/` under the session. The returned
page spans 2026-09-03T15:18:39Z → 2026-09-07T17:59:51Z; the oldest row **precedes
the 15:30Z incident cutoff**, so the window is covered with no pagination gap.

Pulled 2026-09-08, **before** revocation at 10:34Z. Window requested:
2026-09-03T15:30Z → present. Window actually returned: 2026-09-03T15:18:39Z →
2026-09-07T17:59:51Z, single page, no gap at the start (the oldest row precedes
the cutoff). The final ~16.5h of the exposure window simply contains no audit
entries rather than having been excluded.

96 entries in the window. Every one is the same actor — the Terraform IaC proxy
service user — performing `detector.edit/add`, `monitor.add`,
`uptime_monitor.edit` and `rule.create/edit` against our own resources, from
Azure ranges consistent with GitHub Actions runners. No unknown principal, no
unexpected event type.

- **Integrity / write limb: CLEAN.**
- **Confidentiality / read limb: INCONCLUSIVE.** Audit logs do not record reads,
  and finding 1 removes the instrument that was meant to address this. Only
  vendor support could resolve it further.

This is the outcome the determination predicted as its honest expectation — now
evidenced rather than anticipated. It is **not** the CLEAN path that would let
`art_33_determination_status` drop "provisional".

### Still open

The ADR-031 migration is undone — the org-token surface is empty, so this
credential class is still a personal token and the next rotation is still gated
at an interactive login. That remains the durable fix.

## Addendum — 2026-09-11 (#7946): the ADR-031 migration is done for every repo-side consumer

Append-only. Nothing above is rewritten; this section supersedes the parts it
names. Frontmatter is untouched: the `art_33_*` / `art_34_*` fields describe the
determination, which this addendum does not amend.

**Supersedes `### Still open` (2026-09-08 addendum).** The org-level migration
that section called "the durable fix" has shipped. Sixteen files under
`scripts/followthroughs/` (thirteen Sentry readers, one emitter that only refused
under xtrace, two `.test.sh` stubs) no longer name `SENTRY_AUTH_TOKEN`; the
readers consume `SENTRY_ACTIONS_RO_TOKEN`, the token of a dedicated Internal Integration
`actions-read-prd` on `jikigai-eu` with exactly `[event:read, org:read,
project:read]` (measured post-mint), stored as one GitHub repository secret and
deliberately not mirrored into Doppler — so no `doppler run` config can bind a
personal token under it by accident. `fresh-host-boot-trail.sh`, the last
repo-side reader of the personal value via Doppler, binds the same secret from
both provisioning jobs and makes no Doppler read at all. The next rotation is
agent-drivable per
`knowledge-base/engineering/operations/runbooks/sentry-actions-ro-token-rotation.md`,
with one honest handoff (the browser session's login + 2FA when it has expired;
the mint form itself has no human gate). The premise that "the org-token surface
is empty" conflated Organization Auth Tokens with Internal Integrations — the
org carries five of the latter; ADR-031's 2026-09-11 amendment records the
distinction and the class.

**Supersedes the 2026-09-07 addendum's ADR-031 sentence** ("off the *user* auth
token onto an org-level Internal Integration (ADR-031's `iac-terraform-prd`
shape), which would make the next rotation agent-doable"): the shape adopted is
a *dedicated read-only* integration, not the IaC token's — DC-3 on #7993 was
decided on a measurement (the cron check-in endpoint 403s under the
`inline-read-prd` scope set), and the alternative of binding the IaC token under
the new name was rejected for carrying `project:admin` / `alerts:write` on a
GET-only class. ADR-031 holds the record.

**Still open after this addendum, tracked.** The personal token's *value* under
the canonical name in Doppler `soleur/prd_terraform` is still live: it has no
repo-side reader via Doppler any more, but the Terraform provider, sentry-cli and
`next.config.ts` keep the name, and five workstation scripts bind it under
`doppler run -c prd_terraform`: `apps/web-platform/infra/cutover-verify.sh`,
`scripts/sentry-alert-live-fidelity.sh`, and under `apps/web-platform/scripts/`
`sentry-monitors-audit.sh`, `configure-sentry-alerts.sh` and
`assert-byok-rules-exist.sh`. Its replacement with the `iac-terraform-prd`
value and revocation is **#8090**. Separately, the sweeper's silent
missing-secret path (a directive naming an absent credential was skipped with
stderr only under a green run) and a pre-existing command injection in the same
loop (`secrets=a[$(cmd)]` was expanded before validation) were closed in the same
PR — both found while rewiring this credential, neither part of the original
incident.
