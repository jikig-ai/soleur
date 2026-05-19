---
title: "Sentry token-scope probe — halt + divergence note (NOT the plan-prescribed probe report)"
date: 2026-05-19
parent_issue: 3861
related_issues: [3962, 3849]
related_pr: 4044
related_plan: knowledge-base/project/plans/2026-05-19-feat-sentry-residency-reframe-pr1-plan.md
gate: 3b
status: halt
verdict: theories-falsified-pending-triad-respawn
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
| T3 | Current best: "Personal Token, user-membership boundary — the runtime token's token-holder identity (the user / service-account it authenticates as) is recognized by Sentry but is not a member of the `jikigai` org" | **NOT YET TESTED** | Consistent with STEP1=403 + STEP2=200 + STEP3=200 + zero `jikigai-eu` Org Auth Tokens. Verification path: hit `https://sentry.io/api/0/` or `/api/0/me/` with the runtime token to surface its identity. Or read `https://jikigai.sentry.io/settings/members/` and compare against jean.deruelle's known membership. |

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

## References

- Plan (now requires revision): [`knowledge-base/project/plans/2026-05-19-feat-sentry-residency-reframe-pr1-plan.md`](../../project/plans/2026-05-19-feat-sentry-residency-reframe-pr1-plan.md)
- Brainstorm: [`knowledge-base/project/brainstorms/2026-05-19-sentry-residency-reframe-3861-brainstorm.md`](../../project/brainstorms/2026-05-19-sentry-residency-reframe-3861-brainstorm.md)
- Spec: [`knowledge-base/project/specs/feat-sentry-residency-reframe-3861/spec.md`](../../project/specs/feat-sentry-residency-reframe-3861/spec.md)
- Token-scope learning (still applicable to the broader corrective work): [`knowledge-base/project/learnings/2026-05-19-sentry-401-is-not-unowned-verify-token-scope-first.md`](../../project/learnings/2026-05-19-sentry-401-is-not-unowned-verify-token-scope-first.md)
- URL-routing learning: [`knowledge-base/project/learnings/2026-05-19-sentry-url-routing-three-orthogonal-dimensions.md`](../../project/learnings/2026-05-19-sentry-url-routing-three-orthogonal-dimensions.md)
- AGENTS rules invoked: `hr-menu-option-ack-not-prod-write-auth` (Phase 1.3 ACK gate), `hr-never-paste-secrets-via-bang-prefix` (operator-only card-detail handling), `hr-exhaust-all-automated-options-before` (Playwright-driven mint vs operator handoff), `hr-mcp-tools-playwright-etc-resolve-paths` (screenshots resolved to bare-repo root then relocated to worktree).
