# Tasks — Workstream issue creator attribution

Derived from `knowledge-base/project/plans/2026-07-09-feat-workstream-issue-creator-attribution-plan.md`.
lane: cross-domain

> RE-SCOPE (deepen-plan, verified P0): the live Concierge files issues via `gh issue create` over Bash, NOT `create_issue`. Part A (read path) ships independently; Part B (write path) needs the Phase-0 mechanism decision and MAY be a follow-up PR. See plan + decision-challenges.md.
>
> **OPERATOR DECISION (2026-07-09, confirmed):** Ship **Part A only** in this PR (#6253) — Phases 1, 2, 5, 6, 7. **DEFER Part B** (Phases 0, 3, 4 — Concierge `create_issue` MCP rewire + initiator stamp, promotes #3722) to a focused follow-up PR. `ship` MUST file an `action-required` follow-up issue tracking Part B. The Phase-5 renderer builds all three "Created by" variants so the follow-up is write-path-only; the "· initiated by X" variant stays dormant (renders plain "Soleur") until Part B lands markers.

## Phase 0 — Resolve Part B write-path mechanism (gating, REQUIRED before Phase 3-4)
- [ ] 0.1 Confirm the live Concierge issue-creation mechanism (gh CLI over Bash vs a wired tool); check `cc-dispatcher.ts` MCP allowlist + GH_TOKEN injection.
- [ ] 0.2 Choose mechanism A (wire `create_issue` into cc `soleur_platform` MCP server, promote #3722, redirect prompt off raw `gh`) — recommended; or interim B (marker via prompt directive on gh --body).
- [ ] 0.3 Output the definitive list of issue-creation sites that must thread `initiatorLogin`; decide Part A-only PR vs combined.

## Phase 1 — Read-path pure model (lib/workstream.ts, tested first) [PART A]
- [x] 1.1 Add `WorkstreamCreator` interface + optional `creator?` field on `WorkstreamIssue` (additive, mirrors `domains?`).
- [x] 1.2 Add `authorLogin?: string | null` to `BoardIssueInput` (body already present).
- [x] 1.3 Implement pure `isSoleurBotLogin(login, botSlug)` — case-insensitive `<slug>[bot]`; conservative fallback (bias false).
- [x] 1.4 Implement pure `parseInitiatorLogin(body)` — anchored, whitespace-tolerant regex; null on missing/malformed.
- [x] 1.5 Implement pure `deriveCreator(authorLogin, body, botSlug)` — undefined on falsy author; sets isSoleur/initiatorLogin/display.
- [x] 1.6 Widen `githubIssueToWorkstreamIssue(input, botSlug?)`; set `creator` when derivable; keep leaf (no React/components import).
- [x] 1.7 Unit tests in `test/workstream-helpers.test.ts` for 1.3–1.6 (incl. back-compat: existing callers without authorLogin/botSlug).

## Phase 2 — Wire GitHub author through the read path
- [x] 2.1 `github-read-tools.ts` `toBoardInput`: set `authorLogin: item.user?.login ?? null`.
- [x] 2.2 `get-workstream-issues.ts`: resolve `getAppSlug()` once (defensive try/catch), pass `botSlug` to mapper; tenant resolution unchanged.
- [x] 2.3 Confirm SWR `{ issues }` shape unchanged; wiring/degrade tests in `test/server/workstream/get-workstream-issues.test.ts` + `test/server/github-read-tools.workstream.test.ts`.

## Phase 3 — Write-path initiator marker [PART B]
- [ ] 3.1 Put `appendInitiatorMarker` + `parseInitiatorLogin` + `INITIATED_BY_MARKER` const in `lib/workstream.ts` (single-sourced emit/parse). Marker `<!-- soleur:initiated-by <login> -->` (no @mention, no close-keyword).
- [ ] 3.2 `appendInitiatorMarker`: strip ALL stray markers UNCONDITIONALLY (before falsy-login return); append only when login present. Unit-test spoof cases.
- [ ] 3.3 Centralize stamping at `createIssue` REST helper (github-app.ts:1344) via additive optional `initiatorLogin?` (imports appendInitiatorMarker from leaf). Thread from every issue-creation site Phase 0 found (mechanism A: the wired cc `create_issue`).

## Phase 4 — Thread human login [PART B]
- [ ] 4.1 Resolve via `resolveGithubLogin(serviceClient, userId, github_username)` — SERVICE client, authoritative GoTrue path. Extend `.select("email, github_username")` (agent-runner.ts:1077) + equivalent in cc runtime.
- [ ] 4.2 Thread `initiatorLogin` into every builder (buildGithubTools @1656 + cc create_issue builder).
- [ ] 4.3 Defensive: null login → no marker, no throw; emit attribution_status enum. Note null-by-default for email-signup-no-GitHub-OAuth users.
- [ ] 4.4 END-TO-END test: drive the real Concierge path; assert created issue body carries exactly one marker and read renders "Soleur · initiated by <login>".

## Phase 5 — Render (reuse UserAvatar + Row primitives)
- [x] 5.1 Detail sheet: "Created by" `<Row>` with three label variants (Soleur · initiated by X / Soleur / human login).
- [x] 5.2 Card: distinct creator chip in the right chip cluster (title + opacity to disambiguate from assignee chip).
- [x] 5.3 Component tests: three variants render; absent creator renders nothing.

## Phase 6 — (optional) creator filter dimension — CUT
- [ ] 6.1 CUT (2026-07-09): adds material surface across 6 filter functions + UI for a nice-to-have the core want doesn't need. Deferred to the Part B follow-up if wanted.
- [ ] 6.2 CUT — see 6.1.

## Phase 7 — ADR + verification
- [x] 7.1 Author ADR-104 (provisional) via `/soleur:architecture`; "no C4 impact" with actor/system/edge citation; no `.c4` edit.
- [x] 7.2 tsc --noEmit clean; vitest node + component suites green; column/Status derivation byte-unchanged.
