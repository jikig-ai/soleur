---
title: A token's probe endpoint must match its minting app — LinkedIn org tokens can never pass /v2/userinfo
date: 2026-09-29
category: engineering
tags: [linkedin, oauth, cron, probe, organizationalEntityAcls, openid, two-apps, fail-loud]
symptoms: [weekly cron files "expired" issue on a healthy org token, #7606 could never auto-close, bootstrap minted org token under the wrong app's generator URL]
module: apps/web-platform/server/inngest
component: cron-linkedin-token-check
problem_type: integration_issue
resolution_type: code_fix
root_cause: vendor_api_assumption
severity: medium
---

# Learning: Probe endpoint must match the token's minting app

## Problem

Soleur has TWO LinkedIn developer apps. The **Soleur** app (`clientId
78wtm2wu15iikn`) is OIDC-only (`openid`, `profile`, `w_member_social`,
`email`). The **Soleur Community** app (`clientId 78s808ujpe6lve`) carries the
Community Management API scopes (`w_organization_social`,
`rw_organization_admin`) — and does **not** offer `openid`.

`cron-linkedin-token-check` probed BOTH secrets against `/v2/userinfo`, which
requires `openid`. A Community-app org token — valid, installed, admin of two
orgs — returned `403 ACCESS_DENIED` there forever, so its action-required
issue (#7606) could never auto-close and every weekly run lied about its
state. The renewal bootstrap compounded it: one hardcoded generator URL meant
the org token got minted under the wrong app, producing a token that could
never satisfy the probe even on a perfect run.

## Solution

`TOKEN_PROBES` — a per-token-name table mapping each secret to the endpoint
its minting app can authorize (`checkToken` resolves by `tokenName`, never a
default):

- `LINKEDIN_ACCESS_TOKEN` → `GET /v2/userinfo`
- `LINKEDIN_ORG_ACCESS_TOKEN` → `GET /v2/organizationalEntityAcls?q=roleAssignee&role=ADMINISTRATOR&state=APPROVED`

A `403` on a *resolved* probe is actionable, not `unknown`: it files the same
per-token issue with an HTTP-code-aware body (`httpStatus` rides the result
for log disambiguation; the `expired` status and shared issue title stay
single-threaded so the auto-close lifecycle is one dedup key). A `tokenName`
absent from the table fails loud via `reportSilentFallback` + `unknown` —
never a default endpoint. `bootstrap.sh` parameterized `token_probe`/
`token_is_live`/`mint_or_reuse`/`persist_token` by endpoint and split the
generator URL per app; its tri-state probe now classes `401|403` as
`rejected <code>` (a `rejected` verdict for a network-shaped diagnosis was
the review panel's P1 — the message must name the measured cause, AP-021).

## Key Insight

A health probe is only as honest as the endpoint it assumes the credential
can reach. "The token failed userinfo" is two different claims — expired, or
not authorized for that endpoint — and they need different remedies. When a
vendor splits credentials across apps with disjoint scopes, the probe table
must key on which app minted the token, and the renewal runbook must name
that app's generator URL; a healthy token probing 403 forever is a silent
failure wearing a loud failure's clothes.

## Prevention

- Probe tables keyed on the credential's minting surface (env-var name here);
  fail loud on unconfigured names, never default to an endpoint.
- When a probe distinguishes `401` from `403`, carry the code into the issue
  body, the marker, and the log extras — a remediation that names the wrong
  cause sends the operator debugging the wrong thing (network vs scopes).
- Per-token parity anchors (test asserting each call site's own endpoint var,
  `[^|]`-bounded so the match cannot leak past `||`) keep a TS↔bash parallel
  declaration honest — the two surfaces cannot share a config.

## Session Errors

1. **Test-path off-by-one** — `BOOTSTRAP_SOURCE` resolved `apps/`-relative
   with one `..` short (ENOENT at collection). **Prevention:** assert repo-root
   resolution against a known sentinel (e.g., resolve to `package.json` and
   check the name) rather than counting `..` segments by eye.
2. **Vacuous regex anchor** — `[\s\S]*?\$LINKEDIN_ORG_ACLS` matched the
   soon-to-be-removed advisory block; tightened to `[^|]*` so the match cannot
   cross the `||` boundary. **Prevention:** bound multi-line regexes with a
   terminator that cannot appear between subject and anchor.
3. **Search mock over-match** — a blanket `GET /search/issues` mock returned
   the same issue for both tokens' title queries, double-closing 7606.
   **Prevention:** when the dedup key is in the query string, discriminate the
   mock on `args.q`.
4. **Anchor asserted URL-arg shape, source used table-entry shape** —
   `clientId=78…` vs `clientId: "78…"`. **Prevention:** write source anchors
   against the code's own literal form, then verify RED→GREEN by mutating the
   source, not by assuming the string.
5. **First commit blocked by still-RED bootstrap anchors** — TDD ordered the
   test file before `bootstrap.sh`; the pre-commit affected battery measured
   the live tree and refused. **Prevention:** commit test+impl per unit
   together, or accept a documented LEFTOVER-red window in the commit message.
6. **Repo-wide-containment drift** — reading `knowledge-base/` made the test
   file escape `apps/web-platform`; the suite must register in
   `repo-wide-suites.ts` or the containment guard fails. **Prevention:**
   containment guard names the file to add — register immediately, don't let
   the hook discover it.
7. **`git add -A` swept a scratch body file into a commit** — a root-level
   `.issue-*.md` staging file got committed, then removed in a follow-up.
   **Prevention:** write issue bodies under
   `knowledge-base/project/specs/<branch>/issue-body-<name>.md` (the existing
   convention) or outside the worktree; never `git add -A` when scratch files
   exist.
8. **`gh issue create` gate mechanics** — `--body-file` needs a literal
   absolute path (no `$PWD`, no `~`, no relative — it resolves against the
   hook's cwd, not yours), and the body must carry a `User-Impact:` +
   `Fix-Size:` pair, a `Mandated-By:` line, or a `meta/machinery` label.
   **Prevention:** write the body file first in a separate step inside the
   worktree, pass the literal path, include the justification lines up front.
9. **Edit tool emitted literal control bytes** into a regex char class.
   **Prevention:** always write `\xNN`/`\uNNNN` escapes, never literal control
   characters, and verify with `cat -v` after the edit.
10. **`test-all.sh` advisory-lock contention** — two sibling gate runs made
    the pre-commit battery take ~2h, including a ~60min lock wait, and a
    cross-file component flake (c4-code-panel F-A1, filed #9190).
    **Prevention:** none new — the contention banner + isolated re-run
    discriminator worked as designed; recorded as known-infra pain.
11. **Wrong-path `sed`** — `routine-metadata.ts` was addressed under
    `server/inngest/functions/`; it lives at `server/inngest/`.
    **Prevention:** resolve the path (glob) before editing from memory of a
    sibling file's location.
12. **Forwarded:** planning subagent had no Task/Skill spawn tool → fan-outs
    ran inline (disclosed in the plan). Review panel ran as `subagent_explore`
    seats pointed at each rubric file — same harness constraint, disclosed.

## References

- Issue: #9181; PR: #9183; follow-ups: #9188 (token-validators.ts same-class
  surface), #9190 (c4-code-panel contention flake), #9203 (octokit retry
  modernization gap).
- Live-verified 2026-09-28: org token → 200 on `organizationalEntityAcls`,
  200 on `/v2/me`, 403 on `/v2/userinfo`; administers org 129094054.
