---
title: "Concierge answers every request with the raw Claude CLI login line"
date: 2026-10-25
incident_pr: 10976
incident_window: "onset unknown (a month-old conversation shows the same text) → ongoing; verified 2026-10-24"
recovery_at: "TBD"
suspected_change: "unknown; PR #10976 ships a diagnostic only, not a fix"
brand_survival_threshold: single-user incident
status: open
triggers: []
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

In production the Concierge answers every request with the Claude CLI line "Not logged in · Please run /login" and runs no command. It happens under both authentication modes, with a freshly validated Anthropic key, and with the `agent-sandbox-unix-deny` flag both OFF and ON. The cause is not known. Nothing reached Sentry or Better Stack for the reply, so it could not be read from telemetry; PR #10976 adds that telemetry and does not fix the incident.

## Status

ongoing — mirrors the `status: open` frontmatter above. Root cause not established; the fix is tracked on #11086.

## Symptom

On app.soleur.ai, in a workspace with a connected repository and a new conversation routed to cc-soleur-go, the Concierge replies with the raw CLI line for every request and runs no command. Settings show the key as validated and `GET /api/byok/effective-status` reports an effective key. A conversation a month old shows the same text, so the onset predates 2026-09-24.

## Incident Timeline

- **Start time (detected):** 2026-10-24 (exact time not recorded; onset earlier)
- **End time (recovered):** TBD
- **Duration (MTTR):** TBD (status not resolved)

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-10-24 | Operator enabled the `agent-sandbox-unix-deny` flag (tracked on #10548); the Concierge answered with the raw login line. |
| agent-with-ack | 2026-10-24 | Probed both authentication modes and a freshly validated key in the operator's signed-in session: same reply every time. |
| human | 2026-10-24 | Operator rolled the flag back (OFF in dev and prd); the reply persisted, so the flag is not the cause. |
| agent | 2026-10-25 | Built and reviewed the diagnostic (PR #10976, 22 review seats), filed #11085 and #11086. |

## Participants and Systems Involved

Operator (single founder); Claude Code agent. Systems: the cc-soleur-go and legacy agent runners, the Claude Agent SDK and its bundled CLI, BYOK key leasing, Sentry.

## Detection (+ MTTD)

- **How detected:** manual — found while enabling a flag for #10548, not by monitoring.
- **MTTD (mean time to detect):** Unknown (external/manual report)

## Triggered by

system — not caused by a user action; the trigger is unknown.

## Root-cause hypothesis (triage)

Triage-time competing hypotheses; the post-resolution final root cause lives in the 5-Whys section below. None is established. PR #10976's ten tags are built to separate the first three in one event.

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| The agent environment built for the CLI has no usable credential (`auth_env_present=false`) | none yet | the key is validated and an effective key is reported | untested |
| The credential is in the options but the CLI process resolves none (spawn, env hand-off, sandbox, outer wrap) | the reply persists with the flag OFF and ON | none yet | untested |
| The CLI sees a credential and the API refuses it (invalid, revoked, account state) | none yet | the key was freshly validated | untested |
| Web-container egress drops to AWS addresses and Flagsmith `getIdentityFlags` failures cause it | the same time window in Sentry (AWS addresses; WEB-PLATFORM-2K is older noise since 2026-06-10) | co-occurrence only; `has_egress` is a build-time flag and cannot confirm or refute it | hypothesis, not a finding |

## Resolution

Not resolved. Telemetry for the reply ships with PR #10976; the root-cause fix and a friendly user-facing error are tracked on #11086.

## Recovery verification

TBD — recovery is verified when the first real event's tag tuple is read (recorded on #10455), the cause is fixed, and a new conversation answers a request without the raw login line.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

TBD — filled in when the root cause is established (#11086).

## Versions of Components

- **Version(s) that triggered the outage:** TBD (unknown; SDK 0.3.284 is the pinned version at the time of writing)
- **Version(s) that restored the service:** N/A — not yet restored

## Impact details

### Services Impacted

The Concierge (cc-soleur-go) and the legacy agent runner in the web platform: every agent request in the affected accounts.

### Customer Impact (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE, not by surface. This is the canonical "Customer Impact"; do NOT add a second free-text Customer Impact block.

- Prospect: not affected (no agent session).
- Authenticated app user: the Concierge is unusable (every request gets the raw CLI line); the number of affected accounts is unknown, verified on the operator's account.
- Legal-document signer: not affected.
- Admin via Access: not affected.
- Billing customer: BYOK customers who pay for a working Concierge have no recovery path (#11086).
- OAuth installation owner: not affected.

### Revenue Impact

Unknown / N/A

### Team Impact

Unknown / N/A

## Lessons Learned

### Where we got lucky

No personal-data exposure is known: the reply is a client-side CLI message and the diagnostic carries only closed-enum tags.

### What went well

The flag was rolled back as soon as it was shown not to be the cause; the diagnostic was built to a no-secrets, closed-enum contract and reviewed by 22 seats.

### What went wrong

There was no telemetry for the CLI's auth-failure reply at all, so the incident was only discoverable by using the product, and its onset cannot be dated.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur (save logs, add tests, set up alerts, automation, documentation, code sweeps, PRs).

**Each row MUST cite a filed GitHub issue number.** A bare bullet or a `TBD`/`(none)` placeholder is not allowed — file the issue first (`gh issue create`, cross-referencing the source PR in the body), then record its number here. An item with no `#NNNN` is shelf-ware that rots the moment the session ends; the `/ship` Incident-PIR gate blocks merge on any item that lacks an issue reference. If there are genuinely zero follow-ups, write exactly `No action items — incident fully resolved in the source PR with no residual work.` as a line of its own, with no emphasis — the permitted no-item form is plain so that the markdown linter (MD049, emphasis-style) cannot restyle it; the `/ship` gate accepts the plain line (and the underscore/asterisk-wrapped spellings shipped before this template changed).

| Issue | Action | Status |
|---|---|---|
| #11086 | Root cause of the raw login reply, and a friendly user-facing error that keeps the matcher on the raw text | open |
| #11085 | Downgrade then remove the temporary agent-auth-failure alert (fallback review 2026-11-30) | open |
| #10455 | Umbrella: record the first real event's tag tuple and read the cause from it | open |

## Addendum — 2026-10-29 (#11085: first events recorded, diagnostic downgraded)

- **Detection now works; the cause is still open.** The diagnostic recorded its first two real events on 2026-10-27 (09:01Z and 16:27Z) with one tuple: `runner=cc-soleur-go`, `credential_scheme=oauth_token`, `auth_env_present=true`, `auth_mode=api-key`, `cli_key_source=none`, `match_kind=not_logged_in`, decoded and recorded on #10455 on 2026-10-29. The OAuth token was in the options handed to the SDK and the CLI still saw no credential; the cause stays with #11086.
- **A detection gap found while downgrading.** The diagnostic rule was downgraded so its own action resolves to no recipient (a `NoOne` fallthrough; the provider rejects a rule with no action). Review found that Sentry's vendor-default workflow "Send a notification for high priority issues" (id 566201, not managed by Terraform) can still email active members for this issue, which is `level=error`, priority `high`. Whether anyone was emailed for the 2026-10-27 events, and by which path, was not established. The delivery claim for the incident's alerting path is therefore "this rule's own action", not "nobody".
- **Timing.** The downgrade change was committed at 08:36Z on 2026-10-29, before the 48-hour window on #11085 ended (09:01Z), but it takes effect only when the merge is applied.

## Addendum — 2026-10-29 (#11086: mechanism reproduced, friendly error shipped)

- **Mechanism (reproduced locally, operator row not read).** The bundled Claude CLI (SDK 0.3.284, CLI 2.1.284 and 2.1.293, run with a scrubbed environment and synthesized fake values only) does not use a subscription-token value that starts `sk-` but is not shaped `sk-ant-oat<NN>-<non-space>`, or that is blank, or that carries an embedded space or tab. It replies with exactly the not-logged-in line and reports `apiKeySource` `none`. Only the blank value is answered with no API request at all; the other dropped values still produce an unauthenticated request whose 401 the CLI renders as the same line. The first real tuple (`credential_scheme=oauth_token`, `auth_env_present=true`, `cli_key_source=none`, `match_kind=not_logged_in`) is what this produces. The server stored the operator's subscription token with no validation and handed it to the CLI unchanged.
- **Why both authentication modes failed.** The lease prefers the operator-only `anthropic_oauth` row whenever the operator OAuth path is enabled, whatever the conversation's persisted `authMode` binding says. A validated API key was irrelevant while that row existed. The `auth_mode=api-key` against `credential_scheme=oauth_token` mismatch in the tuple is by design and was not the cause.
- **What is NOT established.** Which stored shape the operator's row has (an API key pasted through the Subscription-token toggle, or a wrapped `claude setup-token` copy with an embedded space) was not read, because it is a secret. Both are in the dropped class. The "Cloud gateway" wording is the `claude auth status` text renderer, not a stream reply, so the matcher needed no change.
- **Fixes.** The write boundary now rejects a value that is not shaped like a subscription token (400, no echo of the value). The lease refuses a stored value of a measured dropped class with a new fail-closed cause, `oauth_unusable`, with no fallback to the API-key row, and reports one Sentry event carrying only the closed shape class. A contract test against the bundled binary re-derives the table on every SDK bump. Both runners now show server-authored copy chosen from the matcher's kind and the credential scheme instead of the raw CLI line, and send one `key_invalid` frame after `stream_end` so the card offers the Settings action. The matcher still runs on the raw message first.
- **Closure.** #11086 stays open until post-deploy evidence: the first operator-account Concierge turn after deploy either fires the lease event (its `shape_class` names the stored shape) or completes without the raw line. If a turn is sent, no event fires and the raw line still appears, the stored value is valid-shaped and this mechanism is wrong; reopen the investigation. The operator re-saving the token is their own action and tracked separately.
- **Known limits.** A conversation that already holds a failing Query keeps its old credential until the next dispatch, which builds a cold Query and re-leases (the Query is torn down at the next dispatch, not at the result, so a message queued during the failing turn is not dropped). Old persisted raw lines are not rewritten. The operator has no in-product way to remove a dead stored token (#11524), and the chat state after the recovery frame is unchanged from the existing `key_invalid` behavior (#11525).
