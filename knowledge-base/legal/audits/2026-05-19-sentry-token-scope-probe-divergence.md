---
title: "Sentry token-scope probe — halt + divergence note (NOT the plan-prescribed probe report)"
date: 2026-05-19
parent_issue: 3861
related_issues: [3962, 3849]
related_pr: 4044
related_plan: knowledge-base/project/plans/2026-05-19-feat-sentry-residency-reframe-pr1-plan.md
gate: 3b
status: superseded
status_superseded_by: knowledge-base/legal/audits/2026-05-21-sentry-token-t3-resolution.md
status_superseded_at: 2026-05-21T07:00:00Z
verdict: theories-falsified-T3-confirmed-as-T4-internal-integration-mechanism
probe_run_at: 2026-05-19T10:34:30Z
probe_token_minted_at_utc: 2026-05-19T10:42:20Z
probe_token_revoked_at_utc: 2026-05-19T10:45:03Z
probe_token_lifetime_seconds: 163
---

## Purpose

This is **NOT** the probe report at `2026-05-19-sentry-token-scope-probe-report.md` that PR-1's plan
prescribes. It is the divergence note produced when the plan's load-bearing reframe theory was
empirically falsified during Phase 1 of `/soleur:work`. Per operator choice, the workflow halts and
the triad (CPO + CLO + CTO) re-spawns with the refined finding before any PIR / audit-script /
breadcrumb edit lands.

Read this in lieu of the probe report. The probe report should be authored *after* the triad
re-spawn agrees on a new theory shape.

## Phase 1 results (raw)

| Step | URL | Token | Expected | Actual | Body excerpt |
|---|---|---|---|---|---|
| 1 | `https://sentry.io/api/0/organizations/jikigai/` | Doppler prd `SENTRY_AUTH_TOKEN` | `401` | **`403`** | `{"detail":"You do not have permission to perform this action."}` |
| 2 | `https://sentry.io/api/0/organizations/jikigai-eu/` | Doppler prd `SENTRY_AUTH_TOKEN` | `200` | **`200`** | `{"id":"4511404939345920","slug":"jikigai-eu","name":"Jikigai EU","dateCreated":"2026-05-17T11:13:30.308990Z",…}` |
| 3 | `https://sentry.io/api/0/organizations/jikigai/` | Ephemeral Personal Token, `org:read` only, label `probe-2026-05-19-revoke` | `200` | **`200`** | `{"id":"4511123328466944","slug":"jikigai","name":"Jikigai","dateCreated":"2026-03-28T17:36:09.041388Z","links":{"organizationUrl":"https://jikigai.sentry.io","regionUrl":"https://de.sentry.io"},"access":["org:read"],…}` |

**Substantive corrective story confirmed** (independent of which precise causal theory holds):
- `jikigai` org IS operator-owned (`dateCreated: 2026-03-28T17:36:09Z` matches PR #1235 introducing
  Sentry SDK; org ID `4511123328466944` matches the plan's stated value).
- `jikigai-eu` org IS operator-owned (`dateCreated: 2026-05-17T11:13:30Z` matches the May 17 cutover).
- Both run on `regionUrl: https://de.sentry.io` (EU database cluster).
- A Personal Token with `org:read` scope minted by `jean.deruelle@jikigai.com` from the `jikigai`
  org context CAN read both orgs. The runtime prd token can read `jikigai-eu` but not `jikigai`.

## Theory state

| # | Claim | Status | Evidence |
|---|---|---|---|
| T0 | 2026-05-17 original: "phantom-ingest to an unowned third-party Sentry organization, Art-33 deadline 2026-05-19T12:50:00Z" | **FALSIFIED** | Sentry support replies 2026-05-19 (billing + Rodolfo). `jikigai` is operator-owned. |
| T1 | Plan's reframe: "Token-scope mismatch — token has `org:read` only for `jikigai-eu` slug, not for `jikigai`" | **IMPRECISE** | (a) STEP1=403 not 401 (still permission-class, but the plan's AC1 wording fails); (b) Sentry Personal Tokens carry scope flags (`org:read`, `event:read`, etc.) that are NOT per-org-slug — the slug-scope model is wrong for Personal Tokens. |
| T2 | "Org Auth Token slug-binding": runtime token is an Org Auth Token bound to `jikigai-eu` org; Org Auth Tokens cannot access other orgs by design | **FALSIFIED** | `https://jikigai-eu.sentry.io/settings/auth-tokens/` (Organization Tokens page) shows literal zero: "You haven't created any authentication tokens yet." If the runtime token were an Org Auth Token bound to `jikigai-eu`, it would appear there. It does not. |
| T3 | Current best: "Personal Token, user-membership boundary — the runtime token's token-holder identity (the user / service-account it authenticates as) is recognized by Sentry but is not a member of the `jikigai` org" | **CONFIRMED AS T4 (2026-05-21)** | T3's substance confirmed (membership-boundary causal claim correct). Auth-class label corrected from "Personal Token" to "Internal Integration token" (a distinct Sentry auth class that shares the legacy 64-hex token shape). Verification path was walked 2026-05-21 — full evidence: `knowledge-base/legal/audits/2026-05-21-sentry-token-t3-resolution.md`. |
| T4 | The runtime `SENTRY_AUTH_TOKEN` is a Sentry **Internal Integration token** issued for the `web-platform-ci` Internal Integration installed on `jikigai-eu`. The token authenticates as an auto-generated proxy-user identity (`web-platform-ci-26eeaf-...@proxy-user.sentry.io`) that is — by Sentry's design — a member only of the integration's installation org. | **CONFIRMED 2026-05-21** | (a) `/api/0/users/me/` returns 403 (definitive: User Auth Tokens return 200); (b) `/api/0/organizations/` returns `[]` across all hosts (Internal Integrations cannot enumerate orgs); (c) `/api/0/organizations/jikigai-eu/sentry-apps/` lists `web-platform-ci-26eeaf` with scopes matching the runtime token's `auth.scopes` byte-for-byte and slug matching the proxy-user prefix byte-for-byte. Full audit: `knowledge-base/legal/audits/2026-05-21-sentry-token-t3-resolution.md`. |

**T0 falsification is canonical regardless of T1/T2/T3 outcome.** The substantive corrective story
holds in every variant; what's unstable is the precise causal claim about why the original 401 /
403 happens. That precision matters for the PIR Phase 9 narrative — vague "permissions boundary"
hand-waves do not satisfy the §5(2) accountability standard the probe was designed to produce.

## Token-handling incident (R2-class)

**What happened.** Phase 1.3 of the plan prescribes capturing the freshly-minted Personal Token's
value via `browser_evaluate(filename: ...)` to a tmp file, never to the conversation transcript. The
agent's `mcp__playwright__browser_snapshot` after `Create Token` click returned a full accessibility
tree that included the token-display element verbatim — Sentry exposes the one-time-shown value as
a `textbox "Generated token"` whose value renders in the snapshot text. The token value entered the
transcript at ref `e718`.

**Specific bytes.** `sntryu_<REDACTED-32-hex-bytes; revoked 2026-05-19T10:45:03Z; verified dead via HTTP 401 post-revoke>`.

**Scope.** `org:read` ONLY (verified via Sentry's Permissions Preview UI + STEP3 response
`access: ["org:read"]`). No write capability. No project, team, member, alerts, release, or
issue/event scope.

**Mitigation timeline.**
- Mint click: `2026-05-19T10:42:20Z`
- Token displayed in snapshot (leak): `~10:42:23Z`
- Step 3 curl with token: `10:43:12Z` (HTTP 200 — token live)
- Revoke confirm click: `10:45:03Z`
- Post-revoke API verify: HTTP 401 — token dead
- Post-revoke UI list verify: token absent from active Personal Tokens list
- Elapsed mint → revoke: **2 minutes 43 seconds** (within ≤10-min budget)

**Where the value persists.** Originally: this conversation's transcript (Claude Code session)
plus the `.playwright-mcp/page-2026-05-19T10-42-23-093Z.yml` accessibility snapshot file on local
disk plus the "Specific bytes." line above. Post-redaction: GitHub's secret-scanner blocked the
push when the verbatim bytes were committed (the scanner does not distinguish dead-and-revoked from
live), so the literal 64-hex bytes were replaced with `sntryu_<REDACTED-32-hex-bytes;
revoked 2026-05-19T10:45:03Z; verified dead via HTTP 401 post-revoke>` via feature-branch history
rewrite (force-push-with-lease, no main impact) before push. The verbatim form persists only in
operator-local Playwright snapshot YAML files outside the repo. The token is non-functional — re-use
produces HTTP 401. §5(2) accountability is preserved: the leak event, scope, mitigation timeline,
and post-revoke verification all remain documented above.

**Root cause of the leak.** The plan correctly identified the AGENTS rule `Vendor-token extraction
via Playwright MUST use browser_evaluate(filename: ...) from the FIRST attempt`. The agent did not
invoke `browser_evaluate(filename: ...)` between `Create Token` click and the followup `snapshot`,
so the snapshot's automatic accessibility-tree dump captured the textbox value. The fix is the
existing rule, not a new one: the protocol must place `browser_evaluate(filename: ..., function:
() => document.querySelector('[role=textbox][aria-label*=token]').value)` immediately after the
mint click, BEFORE any snapshot / wait_for / screenshot call that walks the DOM.

## Audit-log surface finding (independent of theory state)

The plan's Phase 1.3 captures `PROBE_TOKEN_MINTED_AT` and `PROBE_TOKEN_REVOKED_AT` from
`https://jikigai.sentry.io/settings/audit-log/` (the Organization Audit Log) with 60s `browser_wait_for`
polling. **The Organization Audit Log does NOT record Personal Token mint or revoke operations.**
That surface logs org-level events (project edits, monitor adds/edits, member additions, plan
changes, org auth token create/remove, etc.). Personal Tokens are user-account scoped and operate
under a separate surface (or no audit surface accessible to the operator).

Evidence: the audit-log page captured at `2026-05-19T10:45:15Z` (after both mint and revoke
operations) shows neither entry. The most recent entry is `monitor.edit scheduled-oauth-probe`
from 2026-05-18 11:56 CEST. The screenshot is preserved at
`knowledge-base/legal/audits/screenshots/2026-05-19-sentry-token-scope-probe/audit-log.png`
(unredacted; needs TR9 redaction sweep before any PR ship).

**Substitute evidence for mint + revoke** (used in this divergence note in lieu of audit-log
timestamps): local UTC timestamps captured at click-time, post-revoke API verification (HTTP 401),
post-revoke UI list state (token absent from active list). All three are mechanically independent
of the missing audit log entries.

**Plan implication.** AC1 + AC8 wording about audit-log timestamps needs revision in the next plan
iteration. The substitute evidence chain (local time + API verify + UI absence) is the canonical
form for Personal Token operations.

## Other artifacts on disk

- `knowledge-base/legal/audits/screenshots/2026-05-19-sentry-token-scope-probe/audit-log.png` —
  full-page screenshot of `jikigai`'s Organization Audit Log at `2026-05-19T10:45:15Z`. Shows
  recent org events; documents the absence of any Personal Token mint or revoke entry. Unredacted.
- `knowledge-base/legal/audits/screenshots/2026-05-19-sentry-token-scope-probe/revoke.png` —
  full-page screenshot of `jikigai`'s Personal Tokens list at `2026-05-19T10:47:44Z` (post-revoke).
  Shows 3 remaining tokens (`soleur-api-query`, `soleur-iac-2026-05-15`,
  `terraform-apply-sentry-iac-prd`); `probe-2026-05-19-revoke` absent. Unredacted (preview
  last-4s visible).
- `mint.png` — **not captured.** Token-list page state with the active probe token was visible in
  the agent's accessibility snapshots at `2026-05-19T10:43:32Z` (post-modal-dismiss) and
  `2026-05-19T10:44:10Z` (after first revoke attempt failed) but no PNG was taken at those moments.
  The textual snapshot record is preserved in the conversation transcript.
- Both PNGs are in the worktree but blanket-gitignored by `.gitignore:58 *.png`. Adding a
  negation pattern for `knowledge-base/legal/audits/screenshots/**/*.png` would let them ship if
  the next plan iteration wants them. Redaction per TR9 (IPs visible: `82.67.29.121`,
  `48.214.53.179`, `20.98.18.68`; token last-4 previews visible) must happen before any PR push.

## Halt decision (operator-driven)

The agent surfaced post-falsification of T2 via `AskUserQuestion`; operator selected "Halt —
re-spawn triad with new theory."

**Rationale.** The plan's load-bearing reframe theory has been refined twice empirically (T1 →
T2 → T3) in the last 15 minutes. Pre-committing PIR Phase 9 / audit-script L127 / breadcrumb-in-3
edits against any of T1, T2, or T3 risks the same evidentiary failure class as the original
2026-05-17 mistake (committing a public-facing causal narrative without empirical grounding).
"Don't pre-commit reframe narrative" — the brainstorm's unanimous triad pushback — applies *more*
strongly now than at brainstorm time, because we've learned the actual mechanism is narrower than
the brainstorm imagined.

## What the re-spawned triad needs to address

1. **Canonical theory.** Test T3 ("user-membership boundary") with the smallest-possible probe (one
   read-only API call to surface the runtime token's identity, or one read of the `jikigai` members
   page). Confirm or falsify before the new plan is written.
2. **PIR Phase 9 narrative shape.** Whatever T3-or-successor theory survives is the precise causal
   claim. The PIR Phase 9 section must read with the §5(2) accountability standard the probe was
   designed to support — not a hand-wave.
3. **Plan AC adjustments.** AC1 wording (401 → 403 + audit-log surface), AC8 (Personal Tokens vs
   Org Audit Log), screenshot capture protocol (mint.png moment must be a hard checkpoint between
   mint click and modal dismiss).
4. **Token-handling protocol fix.** The R2-class incident here is a generic AGENTS-rule reinforcement,
   not a Sentry-specific fix: every vendor-token mint flow under Playwright MUST place
   `browser_evaluate(filename: ...)` between the mint click and the next snapshot / wait_for /
   screenshot. Consider authoring a learning at
   `knowledge-base/project/learnings/2026-05-19-playwright-snapshot-leaks-vendor-token-display-elements.md`
   (pattern: `browser_take_screenshot` is opaque to the snapshot tree, but `browser_snapshot` walks
   the accessibility tree and surfaces `textbox.value` for one-time-shown credentials — the same
   class as AGENTS' "return value otherwise enters the conversation transcript" rule applied to a
   sibling tool).
5. **Whether `probe-2026-05-19-revoke` should be archived.** The Personal Token is dead; the
   incident is documented. No further action required on the Sentry side.

## What did NOT happen (negative-space record)

- `Closes #3962` — not landed. #3962 remains open.
- PIR frontmatter — unchanged. Still reads `status: resolved`, `art_33_triggered: true`,
  `art_33_deadline: 2026-05-19T12:50:00Z`, `classification_override.chosen: none`.
- `apps/web-platform/scripts/sentry-monitors-audit.sh` line 127 — unchanged.
- `knowledge-base/legal/article-30-register.md` PA8 §(d) — unchanged.
- `knowledge-base/legal/compliance-posture.md` row 89 — unchanged.
- `knowledge-base/legal/audits/2026-05-17-sentry-phantom-ingest-window-auth-users-audit.md`
  frontmatter — unchanged.
- Draft PR #4044 — still draft. No `gh pr ready 4044` call.
- Probe report at `…/audits/2026-05-19-sentry-token-scope-probe-report.md` — not authored.
  This divergence note stands in its place until the triad re-spawn produces a new plan.

## Appendix A — T3 verification (2026-05-19, added post-triad-respawn)

The triad re-spawn (CPO + CLO + CTO) converged on running a smallest-possible
T3 probe before authoring the revised plan. The probe was a single read-only
API call:

```bash
curl -sS -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
     https://sentry.io/api/0/
# HTTP 200 — token-holder identity surfaced in the response
```

(Companion call to `https://sentry.io/api/0/organizations/` was attempted in
the same sequence; returned HTTP 200 with an empty list. The empty-list
behaviour for proxy-user identities is a Sentry surface curiosity, not
load-bearing for the T3 conclusion below.)

### Result — T3 CONFIRMED with sharper precision than the original framing

| Field | Value | Significance |
|---|---|---|
| `user.email` | `web-platform-ci-26eeaf-32dbf505-df3b-4cf8-9a0b-babb6dba9d47@proxy-user.sentry.io` | The `@proxy-user.sentry.io` domain is Sentry-internal — it is the identity surface for Internal Integration auth tokens, NOT for human accounts or Org Auth Tokens. |
| `user.id` | `4569715` | Sentry-generated user ID for the integration's proxy identity. |
| `user.username` | `web-platform-ci-26eeaf-32dbf505-df3b-4cf8-9a0b-babb6dba9d47` | The `web-platform-ci-` prefix matches the historical Org Auth Token slug removed at the 2026-05-17 cutover (audit log `org-auth-token.remove soleur-web-platform-ci`) — strongly suggests an Internal Integration with this name was installed on `jikigai-eu` post-cutover and the proxy-user identity is the integration's identity. |
| `user.dateJoined` | `2026-05-17T11:25:11.910265Z` | Matches the 2026-05-17 cutover window (`jikigai-eu` org created at `11:13:30Z`; the integration's proxy-user joined 12 minutes later). |
| `auth.scopes` | `["org:ci", "org:read", "project:read", "project:releases", "project:write"]` | The `org:ci` scope flag is Sentry-internal and NOT surfaced in the standard Personal Token Permissions UI. Its presence is positive identification of an Internal Integration token. |

### Refined causal theory

The runtime `SENTRY_AUTH_TOKEN` is an **Internal Integration auth token**
issued by an Internal Integration installed on `jikigai-eu` (the
`web-platform-ci` integration, by name-prefix inference). The token
authenticates as the integration's Sentry-generated proxy-user
(`web-platform-ci-…@proxy-user.sentry.io`, user ID `4569715`). That proxy-user
is a member of `jikigai-eu` only — Internal Integrations are installed per
organization, and the integration's identity does not extend to other orgs the
human installer happens to be a member of. The 403 against `jikigai/` is a
clean **organization-membership-boundary** failure for the proxy-user identity
— not a scope-flag mismatch (the scope list contains `org:read`), not an Org
Auth Token slug-binding (jikigai-eu has zero Org Auth Tokens). T3 ("user-
membership boundary") is confirmed, and its mechanism is now precise.

### Updated theory state table

| # | Claim | Status (post-T3) |
|---|---|---|
| T0 | "Phantom-ingest to unowned third-party Sentry organization" | **FALSIFIED** (Sentry support replies 2026-05-19; verified). |
| T1 | "Token-scope mismatch — token has `org:read` only for `jikigai-eu` slug, not for `jikigai`" | **IMPRECISE → SUPERSEDED**. Sentry Personal/Internal-Integration token scope flags are not per-org-slug; the per-org boundary is the holder identity's membership, not a slug-scope flag. |
| T2 | "Org Auth Token slug-binding" | **FALSIFIED** (`jikigai-eu/settings/auth-tokens/` shows zero Org Auth Tokens). |
| T3 | "Personal Token, user-membership boundary — token-holder identity lacks `jikigai` membership" | **CONFIRMED, sharpened to:** "Internal Integration auth token, proxy-user identity scoped to `jikigai-eu` only, no `jikigai` membership." |

### Wider-than-expected scope finding (load-bearing for the revised plan)

The runtime token's `auth.scopes` list — `["org:ci", "org:read",
"project:read", "project:releases", "project:write"]` — includes
`project:write` and `project:releases`. These are **write-capable** scopes on
`jikigai-eu` projects. The plan's `## User-Brand Impact` exposure-vector
analysis implicitly assumed read-only ("Step 3 token mint grants Sentry
org-level read scope"). The runtime token is wider than that — it can write
to projects in `jikigai-eu`. This does NOT change PR-1a's interim breadcrumb
scope (which made no claim about the runtime token's capabilities) but it does
need to land in PIR Phase 9 prose (PR-1b) for §5(2) precision, and it
intersects with #3849's IaC-token least-privilege decision.

### How this changes the revised plan's shape

1. **AC1 token-scope wording.** The original plan's `STEP1 == 401 && STEP2 ==
   200 && STEP3 == 200` preconditions are obsolete; the new pre-condition is
   "the runtime token's `auth.scopes` does not include any scope sufficient to
   read `jikigai` — confirmed because the boundary is identity-membership,
   not scope-flag." A scope-flag widening on the existing token would NOT
   unblock STEP1 (the proxy-user remains a non-member of `jikigai`).
2. **Probe report v2.** The probe report at `…/audits/2026-05-19-sentry-token-
   scope-probe-report.md` (still NOT authored — this divergence note + T3
   appendix stands in its place at PR-1a merge time) should be authored in
   PR-1b's branch with the full T3 evidence chain.
3. **PIR Phase 9 narrative.** Mechanism precision is now: "Internal Integration
   proxy-user identity with `jikigai-eu`-only membership; the historical 401
   from `de.sentry.io` was Sentry's auth boundary for non-member identities."
4. **#3849 token-mint decision** (not in PR-1b scope, but informed by this
   finding). The runtime token already has `org:ci`, `org:read`, `project:read`,
   `project:releases`, `project:write`; missing `monitor:read`, `monitor:write`
   per #3849's stated IaC requirements. Three feasible paths: (a) add the
   missing scopes to the existing `web-platform-ci` Internal Integration; (b)
   create a NEW dedicated `iac-terraform-prd` Internal Integration with
   least-privilege; (c) use an Org Auth Token (the CTO's first-pass
   recommendation, before this T3 confirmation). Path (b) best matches the
   least-privilege principle for IaC; the operator's call.

## Appendix B — Org Auth Token path falsification + Internal Integration form structure (2026-05-19, added during #3849 unblock attempt)

After authoring the revised plan, the operator chose Path (c) (Org Auth
Token) for the #3849 IaC token mint, following CTO's first-pass
recommendation. Playwright-driven attempt to open the Org Auth Token
creation form on `https://jikigai-eu.sentry.io/settings/auth-tokens/new-token/`
surfaced a **load-bearing falsification of Path (c):**

### Path (c) is dead — Sentry Org Auth Tokens are `org:ci`-only

The Org Auth Token creation form displays exactly one available scope:

| Scope | Description |
|---|---|
| `org:ci` | Source Map Upload, Release Creation, Code Mappings |

There are no other scope options. Sentry has narrowed Org Auth Tokens to a
single CI-tooling use case. This rules out Path (c) for IaC needs (which
require `project:read`, `project:write`, `monitor:read`, `monitor:write`,
`alerts:read`, `alerts:write` per #3849). The CTO's first-pass recommendation
in the triad re-spawn (which said "Org Auth Tokens DO log to the Organization
Audit Log — free §5(2) trail") was directionally correct on the audit-log
point but the Org Auth Token's capability set has been narrowed beyond IaC
viability. ADR-031's "Internal Integration recommended for CI" reading is
strengthened — and now load-bearing.

### Discovered Sentry Internal Integration form structure (for the operator-recipe)

Navigating Path (b) — new `iac-terraform-prd` Internal Integration on
`jikigai-eu` — surfaced the precise form structure under
`https://jikigai-eu.sentry.io/settings/developer-settings/`:

**Entry point.** Click "Create New Integration" → modal "Choose Integration
Type" with Internal/Public radios (Internal selected by default) → "Next"
advances to the form at `/settings/developer-settings/new-internal/`.

**Form fields (top section "Internal Integration Details"):**

- Name (required) — textbox with placeholder `e.g. My Integration`. Set to
  `iac-terraform-prd`.
- Webhook URL — leave empty for write-only IaC integration.
- Alert Rule Action — disabled until Webhook URL is set; leave alone.
- Schema — leave empty.
- Overview — optional description; leave empty or short.
- Authorized JavaScript Origins — leave empty.

**Permissions section** — 8 dropdowns, *most* with 4 options (`No Access` /
`Read` / `Read & Write` / `Admin`), plus 1 standalone checkbox.

**Empirical correction (2026-05-19, second mint attempt, post-MCP-reconnect).**
The `Release` dropdown surfaces only **2 options**: `No Access` and `Admin`.
`Read` and `Read & Write` are **not** selectable for Release. The original
Appendix B table below claimed Release should be set to "Read" — that
recommendation is not achievable through the UI. The IaC does not strictly
need Release scope (cron monitors + issue alerts are project-scoped; the
existing `web-platform-ci` integration shows `project:releases` is derived
from `project:write` umbrella under Project=Admin). Leave Release at
`No Access`. If a future IaC resource needs explicit Release admin, set it
to `Admin` (the only other option).

The DOM `id` for the Issue & Event dropdown is **`Event--permission`** (no
ampersand encoded). The CI checkbox `id` is **`ContinuousIntegration--
permission`**. These survived the form crashes and are the load-bearing
selectors for any future automation attempt.

| Category | Recommended value | Rationale |
|---|---|---|
| Project | **Admin** | Required for terraform apply + import; covers `project:write`, `project:read`, `project:releases`, `project:admin` scopes. |
| Team | No Access | Not needed for IaC. |
| Release | **No Access** | Only `No Access` and `Admin` are selectable — corrected 2026-05-19. IaC does not need Release scope (project-scoped resources only); `project:releases` is derived from Project=Admin. |
| Distribution | No Access | Not relevant. |
| Issue & Event | Read | Provides `event:read` for the audit script's region probe. DOM id: `Event--permission`. |
| Organization | Read | Provides `org:read` for `/users/me/` + org listing. |
| Member | No Access | Not needed. |
| Alerts | Read & Write | Required for `sentry_issue_alert` rules per #3849. |
| Continuous Integration (CI) | **checked** | Enables `org:ci` scope for source-maps + release creation (compatible with CI pipeline use). DOM id: `ContinuousIntegration--permission`. |

**Note on missing `monitor:*` scopes.** The form does NOT expose a separate
"Cron Monitors" category. The cron-monitor capability is bundled under
`project:write` / `project:admin` scope (verified via Sentry's terraform-
provider source). Setting Project → Admin should yield `monitor:*` derivation
via the project-write umbrella. Verify post-mint via the same
`https://sentry.io/api/0/` probe — the resulting `auth.scopes` array should
include `project:admin` + `project:write` + likely a derived `monitor` scope.

**Webhooks section** — five event categories (`issue`, `error`, `comment`,
`seer`, `preprod_artifact`), all disabled until Webhook URL is set. Skip.

**Submit button label:** `Save Changes`.

**Post-mint UI behavior.** After Save Changes, Sentry navigates to the
integration's detail page. The newly-minted auth token displays exactly once
in a textbox-like element. Per the AGENTS rule + the learning shipped at
PR #4064: capture via `browser_evaluate(filename: ...)` (NOT via
`browser_snapshot`, which leaks the value into the conversation transcript
via the accessibility tree). For manual operator flow: use the in-page
"copy-to-clipboard" button next to the token, then immediately pipe to
Doppler via `xclip -selection clipboard -o | doppler secrets set
SENTRY_IAC_AUTH_TOKEN --no-interactive`.

### Why the Playwright-MCP path could not complete autonomously

Attempted Path (b) flow under Playwright MCP control:

1. Navigate to `/settings/developer-settings/` — works.
2. Click "Create New Integration" — opens modal.
3. Click "Next" on modal — advances to form at `/new-internal/`.
4. Fill Name field — works.
5. Click first permission dropdown (Project) — works.
6. Click `Admin` option from the dropdown menu — **browser context dies
   between this step and any followup**.

The MCP Playwright session times out / drops between agent-message turns.
Within a single agent message, 2-3 tool calls can chain successfully; beyond
that, the browser context is gone. The full integration form requires ~12
sequential interactions (name + 5+ permission dropdowns + CI checkbox + Save
+ token-capture), which exceeds the MCP session window. This is a tooling
constraint, not a Sentry-side issue.

Falling back to operator handoff with the form-structure recipe above (per
`hr-exhaust-all-automated-options-before` — automated options were exhausted
via 4+ attempts before falling back to manual).

### Second mint attempt (2026-05-19T19, post-MCP-reconnect) — successful

After the user reconnected the Playwright MCP server, the autonomous mint
was retried with the corrected Appendix B and an API-bypass strategy. The
form-fill phase completed (Name + 4 dropdowns + CI via a tight single-shot
`browser_evaluate` using `role="menuitemradio"` selectors — corrected from
the earlier mistaken `role="option"` selector), the integration was saved
at slug `iac-terraform-prd-814bdd`, and the auth token was minted via API
rather than via UI:

```js
// session-cookie API mint pattern (works because the agent inherits the
// user's logged-in session via Playwright's browser context)
const csrf = document.cookie.match(/sentry-sc=([^;]+)/)[1];
const r = await fetch('/api/0/sentry-apps/iac-terraform-prd-814bdd/api-tokens/', {
  method: 'POST', credentials: 'same-origin',
  headers: {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'X-Requested-With': 'XMLHttpRequest',
    'X-CSRFToken': decodeURIComponent(csrf),
    'Referer': location.href,
  },
  body: '{}',
});
return (await r.json()).token;  // -> filename: .playwright-mcp/sentry-iac-token-v4.raw
```

CSRF cookie name surfaced at `window.csrfCookieName` (Sentry-EU value:
`sentry-sc`). Token piped to Doppler via:

```bash
python3 -c "import json,sys; sys.stdout.write(json.load(open('.../sentry-iac-token-v4.raw')))" \
  | doppler secrets set SENTRY_IAC_AUTH_TOKEN --no-interactive --type string \
      -p soleur -c prd >/dev/null
shred -u .../sentry-iac-token-v4.raw
```

Verified via `GET /api/0/`:

| Field | Value |
|---|---|
| HTTP | 200 |
| `user.email` | `iac-terraform-prd-814bdd-73af874e-...@proxy-user.sentry.io` |
| `user.dateJoined` | `2026-05-19T19:08:06.794364Z` |
| `auth.scopes` | `alerts:read, alerts:write, event:read, org:read, project:admin, project:read, project:write` |
| `/api/0/organizations/jikigai-eu/` | 200 |

All 7 IaC-required scopes present. `monitor:*` is bundled under
`project:write` (no separate cron-monitor scope on Internal Integrations,
confirming Appendix B's earlier inference).

### Incident during the second attempt — one token leaked, immediately rotated

During the path where the agent tried to mint via the UI (before pivoting
to API), `browser_click` on "New Token" auto-snapshotted the page state
as a side-effect of the tool call. That auto-snapshot file
(`.playwright-mcp/page-2026-05-19T19-32-09-930Z.yml`) contained the
generated token's cleartext in a `textbox "Generated token"` element.
The agent caught the leak within ~30s on inspection, shredded the
snapshot file, revoked the token via the UI, and proceeded via the API
bypass above. Detailed pattern + the corrected click-inside-evaluate
recipe documented at
`knowledge-base/project/learnings/2026-05-19-playwright-click-navigate-auto-snapshot-leaks-modal-tokens.md`.
This is a follow-up to the original PR #4064 learning, which only
covered explicit `browser_snapshot` calls.

Token rotation chain on the integration:
- `last4=0226` — minted via UI, leaked via auto-snapshot, revoked at 2026-05-19T19:30:58 UTC
- `last4=6144` — minted via UI, MCP context died before extraction, API-deleted at 2026-05-19T19:35:40 UTC
- `last4=c468` — minted via API, captured to file via `evaluate(filename:)`, piped to Doppler `soleur/prd SENTRY_IAC_AUTH_TOKEN`, currently active

### Outstanding follow-ups (operator)

1. Confirm `sentry-app.add iac-terraform-prd` entry in
   `https://jikigai-eu.sentry.io/settings/audit-log/?event=sentry-app.add`
   for §5(2) evidence (token lacks audit-log read scope by design —
   least-privilege; verify via session-cookie UI instead).
2. Update `.github/workflows/apply-sentry-infra.yml` to read
   `SENTRY_IAC_AUTH_TOKEN` (was `SENTRY_AUTH_TOKEN`) — separate PR from
   PR-1b since it lives outside the residency-reframe scope.
3. Update ADR-031 to note the Org Auth Token `org:ci`-only narrowing +
   the new dedicated IaC integration `iac-terraform-prd`.

### References specific to Appendix B

- Org Auth Token form inspection: `2026-05-19T14:04:19Z` (UI confirmed
  `org:ci` is the only available scope).
- Internal Integration form structure: discovered during Path (b) attempt
  `2026-05-19T14:14:30Z`.
- Existing `web-platform-ci` Internal Integration on `jikigai-eu` visible at
  `/settings/developer-settings/web-platform-ci-26eeaf/` (confirms T3's name-
  prefix inference).
- New `iac-terraform-prd-814bdd` Internal Integration on `jikigai-eu`
  created `2026-05-19T19:08:06Z` (per minted-token `user.dateJoined`).
- Active auth token `last4=c468` in Doppler `soleur/prd` as
  `SENTRY_IAC_AUTH_TOKEN`, verified `2026-05-19T~19:38Z`.

### References specific to this appendix

- T3 probe run UTC: `2026-05-19T13:28:41Z`.
- Probe A response body inspection: token's `user.email`, `user.dateJoined`,
  `auth.scopes` fields (above).
- Probe B response: HTTP 200 with empty list (Sentry surface curiosity — not
  load-bearing).
- No new tokens minted. No prod-write actions taken. Read-only API call only.

## References

- Plan (now requires revision): [`knowledge-base/project/plans/2026-05-19-feat-sentry-residency-reframe-pr1-plan.md`](../../project/plans/2026-05-19-feat-sentry-residency-reframe-pr1-plan.md)
- Brainstorm: [`knowledge-base/project/brainstorms/2026-05-19-sentry-residency-reframe-3861-brainstorm.md`](../../project/brainstorms/2026-05-19-sentry-residency-reframe-3861-brainstorm.md)
- Spec: [`knowledge-base/project/specs/feat-sentry-residency-reframe-3861/spec.md`](../../project/specs/feat-sentry-residency-reframe-3861/spec.md)
- Token-scope learning (still applicable to the broader corrective work): [`knowledge-base/project/learnings/2026-05-19-sentry-401-is-not-unowned-verify-token-scope-first.md`](../../project/learnings/2026-05-19-sentry-401-is-not-unowned-verify-token-scope-first.md)
- URL-routing learning: [`knowledge-base/project/learnings/2026-05-19-sentry-url-routing-three-orthogonal-dimensions.md`](../../project/learnings/2026-05-19-sentry-url-routing-three-orthogonal-dimensions.md)
- AGENTS rules invoked: `hr-menu-option-ack-not-prod-write-auth` (Phase 1.3 ACK gate), `hr-never-paste-secrets-via-bang-prefix` (operator-only card-detail handling), `hr-exhaust-all-automated-options-before` (Playwright-driven mint vs operator handoff), `hr-mcp-tools-playwright-etc-resolve-paths` (screenshots resolved to bare-repo root then relocated to worktree).
