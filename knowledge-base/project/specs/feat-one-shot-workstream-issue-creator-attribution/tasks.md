# Tasks — Workstream issue creator attribution

Derived from `knowledge-base/project/plans/2026-07-09-feat-workstream-issue-creator-attribution-plan.md`.
lane: cross-domain

## Phase 1 — Read-path pure model (lib/workstream.ts, tested first)
- [ ] 1.1 Add `WorkstreamCreator` interface + optional `creator?` field on `WorkstreamIssue` (additive, mirrors `domains?`).
- [ ] 1.2 Add `authorLogin?: string | null` to `BoardIssueInput` (body already present).
- [ ] 1.3 Implement pure `isSoleurBotLogin(login, botSlug)` — case-insensitive `<slug>[bot]`; conservative fallback (bias false).
- [ ] 1.4 Implement pure `parseInitiatorLogin(body)` — anchored, whitespace-tolerant regex; null on missing/malformed.
- [ ] 1.5 Implement pure `deriveCreator(authorLogin, body, botSlug)` — undefined on falsy author; sets isSoleur/initiatorLogin/display.
- [ ] 1.6 Widen `githubIssueToWorkstreamIssue(input, botSlug?)`; set `creator` when derivable; keep leaf (no React/components import).
- [ ] 1.7 Unit tests in `test/workstream-helpers.test.ts` for 1.3–1.6 (incl. back-compat: existing callers without authorLogin/botSlug).

## Phase 2 — Wire GitHub author through the read path
- [ ] 2.1 `github-read-tools.ts` `toBoardInput`: set `authorLogin: item.user?.login ?? null`.
- [ ] 2.2 `get-workstream-issues.ts`: resolve `getAppSlug()` once (defensive try/catch), pass `botSlug` to mapper; tenant resolution unchanged.
- [ ] 2.3 Confirm SWR `{ issues }` shape unchanged; wiring/degrade tests in `test/server/workstream/get-workstream-issues.test.ts` + `test/server/github-read-tools.workstream.test.ts`.

## Phase 3 — Write-path initiator marker
- [ ] 3.1 Finalize marker format `<!-- soleur:initiated-by <login> -->` (HTML comment; no @mention; no close-keyword).
- [ ] 3.2 Add `initiatorLogin?` to `BuildGithubToolsOpts`.
- [ ] 3.3 Implement + unit-test `appendInitiatorMarker(body, login)` (no-op on falsy login; no double-stamp); use in `create_issue` handler (github-tools.ts:110). Do NOT touch `createIssue` in github-app.ts.

## Phase 4 — Thread human login into agent-runner
- [ ] 4.1 Resolve login via `resolveGithubLogin` / `users.github_username` (precedent-diff vs app/api/repo/* callers).
- [ ] 4.2 Thread `initiatorLogin` into `buildGithubTools({...})` (agent-runner.ts:1656).
- [ ] 4.3 Defensive: null login → no marker, no throw.

## Phase 5 — Render (reuse UserAvatar + Row primitives)
- [ ] 5.1 Detail sheet: "Created by" `<Row>` with three label variants (Soleur · initiated by X / Soleur / human login).
- [ ] 5.2 Card: distinct creator chip in the right chip cluster (title + opacity to disambiguate from assignee chip).
- [ ] 5.3 Component tests: three variants render; absent creator renders nothing.

## Phase 6 — (optional) creator filter dimension
- [ ] 6.1 Add `creators` to WorkstreamFilters + emptyFilters + matchesFilters + hasActiveFilters + FilterOptions + deriveFilterOptions.
- [ ] 6.2 filter-bar.tsx creator Dropdown/CheckRow block (mirror Domain). Cut if it adds material surface.

## Phase 7 — ADR + verification
- [ ] 7.1 Author ADR-103 (provisional) via `/soleur:architecture`; "no C4 impact" with actor/system/edge citation; no `.c4` edit.
- [ ] 7.2 tsc --noEmit clean; vitest node + component suites green; column/Status derivation byte-unchanged.
