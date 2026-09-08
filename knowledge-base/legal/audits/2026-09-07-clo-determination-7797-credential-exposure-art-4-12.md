---
title: "CLO determination — Art. 4(12) assessment of the #7797 credential exposure"
type: clo-attestation
date: 2026-09-07
issue: 7797
pr: 7891
attestation-authority: clo
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
disposition: PROVISIONAL — no Art. 33 duty, no Art. 34 duty. The evidentiary limb was RUN 2026-09-08: integrity CLEAN, confidentiality INCONCLUSIVE. See the 2026-09-08 addendum.
disposition_history: "SIGNED-OFF PROVISIONAL 2026-09-07 on one open evidentiary limb -> limb RUN 2026-09-08 (#7797): integrity CLEAN, confidentiality INCONCLUSIVE, one instrument found not to exist -> still PROVISIONAL, verdict unchanged, sign-off stands as determined and signed. Annotation only; see the 2026-09-08 addendum."
signed_off_at: 2026-09-07
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; operator retains an optional veto)"
awareness_anchor: "2026-09-03T15:33:16Z"
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "not due — 72h from the awareness anchor computes to 2026-09-06T15:33:16Z, but no Art. 33 duty arose, so nothing fell due at that instant. A BREACH finding on the open limb starts a FRESH 72h from awareness of that finding."
open_limbs: "RUN 2026-09-08. Org audit log pulled: integrity/write limb CLEAN. The token last-used timestamp DOES NOT EXIST as an instrument (no such field on any Sentry surface for personal tokens), so the confidentiality/read limb is INCONCLUSIVE and cannot be closed by that route. Only vendor support remains."
tier_classification: "Tier 1 — an internal determination record. No public document is edited, no right is narrowed, no processing added. The mirror/SHA/heading gates are NOT engaged."
semver: "No TC_VERSION bump."
---

# CLO determination — #7797 credential exposure, Art. 4(12)

## Why this record exists separately from the post-mortem

`knowledge-base/engineering/operations/post-mortems/bash-x-credential-trace-exposure-postmortem.md`
records the incident. It is not the right home for the determination, for two
mechanical reasons:

1. `plugins/soleur/skills/incident/SKILL.md` instructs "Do NOT add a row when
   `art_33_triggered` is false." A breach-register row pointing at a PIR whose
   frontmatter reads `false` would put the register in direct contradiction with
   the skill that generates PIRs.
2. `scripts/lint-legal-registers.sh:7` carries exactly one out-of-producer path
   as a **single literal** (`OUT_OF_SCOPE_ROW`). A second post-mortem-hosted row
   would force widening that literal into a set — a change to a legal-register
   guard, shipped in the same PR as the determination it exempts. Wrong order of
   operations.

This file lands inside `audits/**`, needs no waiver and no gate change, and
matches the shape of four of the five existing register rows.

## The fact pattern

On 2026-09-03 at ~15:30Z the operator ran `apps/web-platform/infra/cutover-verify.sh`
under `bash -x` to debug a failing guard. Shell tracing echoes commands after
expansion, so two bearer tokens were rendered in cleartext into the agent session
transcript: `SENTRY_AUTH_TOKEN` and `BETTERSTACK_API_TOKEN_READONLY`, both from
Doppler `soleur/prd_terraform`. Detected on sight at 15:33:16Z — the awareness
anchor.

Values are deliberately not reproduced here, nor is any length or digest of
them. Recording a *use* timestamp (below) is a measurement of the token's use,
not of its value, and is permitted.

## Determination

### Limb 1 — a breach of security: SATISFIED

A credential was rendered in cleartext into a stream not intended to carry it.
The Art. 32(1)(b) confidentiality measure failed. This is conceded, not
contested, and the post-mortem previously did not concede it.

### Limb 2 — leading to unauthorised access or disclosure: NOT ESTABLISHED

The exposure channel was bounded to the operator's own session and the Anthropic
agent context, which Art. 30 register PA-8 §(g) already records as covered by the
existing Anthropic DPA. The value was not committed, not posted to an issue, and
not emitted in CI. No unauthorised recipient of the credential is established,
and therefore no unauthorised access to the personal data behind it.

### The reasoning the post-mortem previously gave is WITHDRAWN

The PIR read: *"Infrastructure credentials only; no personal data reached the
transcript, which is why Art. 33/34 are both `false`."* That answers the wrong
question. Art. 4(12) reaches "unauthorised **access to**" personal data, so the
test is what the credential **unlocks**, not what was rendered. The controller's
own register says as much about this exact credential:

- **PA-8 §(c)(i)** — Sentry error messages and stack traces "may incidentally
  include `user_id`, request paths, request headers".
- **PA-8 §(g)** (#5495) — the Sentry API read path surfaces event
  `message` / `breadcrumb` / `tag` / `user.*` values that the ingest-time
  key-name scrub (`sentry-scrub.ts`) does **not** remove, stated there in
  express contrast to the Better Stack plane.

So `data_categories_breached` is not empty by inspection, and the prior ground
does not support the conclusion. The conclusion nevertheless survives, on the
ground below.

### Governing rule — reachability is not the trigger

`knowledge-base/legal/statutory-response-catalog.md` §`breach-art33`,
first-response checklist step 4, states for exactly this fact pattern — a leaked
key whose actual use is unknown — that **"reachability alone does not start the
Art. 33 clock."** The same rule appears at
`knowledge-base/engineering/operations/runbooks/breach-access-log-investigation.md`
§When to run this, which adds that the investigation "is blocking: run it
**before** remediation, because remediation can destroy the evidence."

Reachability is the trigger for the investigation, not for the notification.

### Art. 33(1) risk assessment, recorded in the alternative

| Limb | Assessment |
|---|---|
| Type | Confidentiality of a **credential**; no confidentiality breach of the data itself established. Integrity also engaged — the token carries org read **and write**. |
| Nature / sensitivity | PA-8 §(c)(i) categories. No special categories systematically. |
| Ease of identification | **Mixed.** Helper-path and direct-capture identifiers are `userIdHash` (HMAC-SHA256 under a Doppler-held pepper not shared with the processor — Recital 26). Free-text `message` / `breadcrumb` content is not covered by a *key-name* scrub and can carry raw identifiers. Partial pseudonymisation only. |
| Severity | On confidentiality: operational telemetry on a small operator-adjacent population. **On integrity: PA-8 §(b)(ii) makes Sentry the canonical Art. 33 first-observed-at clock anchor, so an unauthorised write could corrupt the controller's own breach-evidence chain.** The post-mortem recorded this nowhere before today. |
| Volume | **Not measured.** The 2026-05-16 register row's figure of 10 operator-adjacent accounts belongs to a different window and is not reused here. |
| Special characteristics | Alpha-stage, operator-adjacent population; DE-resident ingest cluster. |
| Likelihood of receipt by an unauthorised party | **Low, and asserted rather than measured.** ~3-minute detection, no publication path engaged. But the Sentry token remains live at day 4, so this window has not closed. **This is the open limb.** |

**Result: unlikely to result in a risk to the rights and freedoms of natural
persons — conditional on the likelihood limb, which is open.**

### Art. 34 — assessed on its own facts

Art. 34 requires a **high** risk, a strictly higher bar, and it is not reached
even on the reach-based framing. Art. 34(3)(a) is squarely available on the
identifier path (HMAC under a pepper the processor does not hold). Small,
operator-adjacent population; no special categories.

This is **not** inferred from the Art. 33 conclusion — the breach register's own
maintenance note calls that inference out as a load-bearing error. If the open
limb resolves to BREACH, **Art. 34 is re-run, not inherited.**

## The two halves are asymmetric

Recording both credentials under a single finding would assert a closed window
over a credential that is still live, and would borrow one plane's scrub as
mitigation for the other, when PA-8 §(g) expressly **contrasts** them.

| | `BETTERSTACK_API_TOKEN_READONLY` | `SENTRY_AUTH_TOKEN` (`prd_terraform`) |
|---|---|---|
| Exposure window | **CLOSED** — leaked value revoked 2026-09-03T20:10Z (~4h40m) | **OPEN** — still live, re-verified 2026-09-07; ≥4 days |
| Capability | read-only | org read **and write** |
| Scrub posture | Vector 3-stage `pii_scrub` + `userIdHash` HMAC before egress — **but not uniformly**: the 2026-08-12 UPDATE (#7440 / ADR-184) records `soleur-registry` POSTs directly by `curl` on paths where those transforms do **not** run. The conclusion for this plane rests on a topology-dependent Art. 4(1) finding flagged as a re-evaluation trigger, **not** on the scrub | **None on the read path** (PA-8 §(g)) |
| Limb 2 | not established; window closed, compensating control in place | not established; **window open, no compensating control, investigation outstanding** |

Only the Sentry half carries the open limb. Nothing in the Better Stack
resolution is available as mitigation for it.

## The open limb — what must be measured, and in what order

The catalog and the runbook both make this **blocking and prior to remediation**.
It has not been run.

1. **Token last-used timestamp**, from `sentry.io/settings/account/api/auth-tokens/`
   under an authenticated session. `GET /api/0/api-tokens/` returning **403 under
   a bearer is expected** — Sentry blocks token-auth against the token-management
   surface; the reading is session-only. It is the same trip the rotation already
   requires, so the marginal cost is zero.
   - **Capture it BEFORE deleting the token.** Deletion destroys the datum.
   - Limits, stated: a single most-recent scalar, not a log; no IP; and the
     controller has its own uses on this token. **The 2026-09-07 liveness probe
     performed while preparing this determination has already overwritten the
     scalar with a controller use** — a real, self-inflicted degradation of the
     instrument, recorded here rather than elided. It can *refute* "no
     third-party use"; it can only weakly *support* it (ADR-197).
2. **Sentry Org Audit Log** — `GET /api/0/organizations/{org}/audit-logs/`,
   2026-09-03T15:30Z → present, pullable under the still-live token. The right
   instrument for the **write / integrity** limb; expressly **not** for the read
   limb, which it does not record.
3. **Vendor support** if (1)–(2) come back thin. Precedent: the 2026-05-16
   determination rests on Sentry confirming in writing which principal performed
   audit-log actions.

Honest expectation: **INCONCLUSIVE on confidentiality, capable of CLEAN on
integrity.** INCONCLUSIVE is a real verdict with its own escalation path, not a
softer CLEAN.

## Re-evaluation triggers

- The access investigation returns BREACH → re-run Art. 33 and Art. 34 from
  awareness of that finding.
- The access investigation returns CLEAN → this determination becomes final and
  `art_33_determination_status` drops "provisional".
- A first arms-length (non-operator-adjacent) user exists at the time of a future
  exposure → the volume and severity limbs change materially.
- External counsel re-review is reserved for these triggers, not for routine
  review. All output here is draft material.

## Addendum — 2026-09-08 (#7797): the open limb, run

Append-only. The body above stands as the determination made on 2026-09-07 on the
evidence then available. This section records what measurement returned, and
withdraws one statement made above.

### The instrument named in "The open limb" does not exist

Step 1 above requires capturing the token's **last-used timestamp**, "before
deleting the token", because "deletion destroys the datum". Measured against the
live product on 2026-09-08 under an authenticated session:

**No last-used field is exposed on any surface reachable to the controller.**
The token list shows Token / Created On / Scopes; the Edit view shows Name /
masked Token / Scopes; and `GET /api/0/api-tokens/` returns 200 under session
auth with the field set `application, dateCreated, expiresAt, id, name, scopes,
state, tokenLastCharacters` — no `dateLastUsed` or equivalent. The org-token
surface holds zero tokens, so it could not be tested and is evidence of no data
rather than of no field.

Scope of that finding, stated because an Art. 32 "reasonable steps to
investigate" question turns on exactly this distinction: it establishes that the
**controller could not gather** the datum, not that no such datum exists
vendor-side.

The 403-under-bearer observation recorded above was correct. The inference that a
session would therefore reveal the scalar was not — the session reveals the same
field set, and it does not include one.

**Withdrawn:** the statement that *"the 2026-09-07 liveness probe performed while
preparing this determination has already overwritten the scalar with a controller
use — a real, self-inflicted degradation of the instrument"*. There is no scalar
to overwrite, so no degradation occurred. That sentence was a self-criticism
entered into a signed record without verifying that its subject existed.

### Consequence for the ordering constraint

The requirement that the access investigation be *"blocking and prior to
remediation"* rests, for the confidentiality limb, on an instrument that
remediation would destroy. Since no such instrument exists, **the confidentiality
limb of that constraint could not have been satisfied**. The credential was live
2026-09-03T15:30Z → 2026-09-08T10:34Z, approximately **4 days 19 hours** — the
single figure of record, matching the post-mortem. An earlier draft of this
addendum said "four days nine hours", derived from nothing and ten hours adrift;
it is withdrawn. Not all of that delay is attributable to the phantom instrument:
rotation was also gated on an operator-cleared browser session, which is a real
gate.

The integrity limb's instrument — the org audit log — is unaffected by rotation
and could have been pulled at any time.

### Verdict on the limb

`GET /api/0/organizations/jikigai-eu/audit-logs/` under the session. Returned
page spans 2026-09-03T15:18:39Z → 2026-09-07T17:59:51Z; the oldest row precedes
the 15:30Z cutoff, so the incident window is covered with no pagination gap. 96
entries in-window, all attributable to the Terraform IaC proxy service user
performing detector/monitor/rule edits on our own resources from GitHub Actions
runner ranges. No unknown principal.

- **Integrity / write limb: CLEAN**, on full-window coverage and a single known actor.
- **Confidentiality / read limb: INCONCLUSIVE.** Unresolvable by the two
  instruments this determination named — audit logs do not record reads, and no
  last-used field is reachable. It is **unattempted, not impossible**: vendor
  support (step 3) has not been tried. Recorded risk: the action row ordered
  escalation *before* deletion, and the token was revoked first, which may have
  reduced what the vendor can still answer.

This is neither the BREACH path nor the CLEAN path. §Re-evaluation triggers
enumerates only those two and therefore has **no branch for the outcome that
occurred**; the third outcome was anticipated in §The open limb ("Honest
expectation: **INCONCLUSIVE on confidentiality, capable of CLEAN on
integrity**"). Append-only forbids editing the trigger list in place, so the gap
is recorded here rather than patched there. Accordingly,
`art_33_determination_status` **does not** drop "provisional". The Art. 33(1)
likelihood limb no longer rests on an assertion about writes — the audit log
answers that — but the read limb rests on the absence of an instrument rather
than on evidence of no access.

### Severity refinement

The Type and Capability rows above state the token carried "org read **and
write**". That was correct. The token in fact carried **admin** — `org:admin`,
`event:admin`, `project:admin`, `team:admin`, `org:integrations` — which reaches
member management, integrations and project deletion. This sharpens the integrity
limb the determination already engaged; it does not reverse it. The Art. 4(12)
severity assessment should be read against the admin scope set.

### The one route that could still close this limb

Step 3 of §The open limb — **vendor support** — is now the only instrument left,
and its trigger condition ("if (1)–(2) come back thin") is met. It is tracked at
**#7945** so that this record does not sit PROVISIONAL behind a step nothing
prompts anyone to take. Precedent for the ask is the 2026-05-16 determination,
where Sentry confirmed in writing which principal performed audit-log actions.

### Remediation

The leaked token (id `6680231`) was revoked 2026-09-08T10:34Z and replaced. Full
detail in the post-mortem's 2026-09-08 addendum — deliberately not restated here,
per this corpus's single-source rule.
