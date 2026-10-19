# Tasks — Fix waitlist signup (Buttondown authenticated v1 API)

Plan: `knowledge-base/project/plans/2026-06-09-fix-waitlist-buttondown-authenticated-api-plan.md`
Branch: `feat-one-shot-waitlist-buttondown-api`

## Phase 0 — Preconditions (verify, do not assume)

- [ ] 0.1 Read a real Buttondown v1 collision-400 body (Context7 schema or a sandbox call)
      to fix the exact duplicate-match predicate before editing. Do NOT copy `/already/i`.
- [ ] 0.2 Confirm `git grep -n "WAITLIST_USERNAME" apps/web-platform` shows only the
      define + embed-URL lines being removed (verified at plan time: zero other consumers).

## Phase 1 — Rewrite `subscribeToWaitlist` (`apps/web-platform/app/api/waitlist/waitlist.ts`)

- [ ] 1.1 Replace `BUTTONDOWN_EMBED_URL` with
      `BUTTONDOWN_SUBSCRIBE_URL = "https://api.buttondown.com/v1/subscribers"`.
- [ ] 1.2 Remove the now-dead `WAITLIST_USERNAME` constant + comment (same commit,
      `cq-ref-removal-sweep-cleanup-closures`).
- [ ] 1.3 Add `const WAITLIST_TIMEOUT_MS = 5_000;` (mirror `token-validators.ts:3`).
- [ ] 1.4 Read `process.env.BUTTONDOWN_API_KEY` at call time; if falsy, `log.warn` + throw
      (fail-closed → route maps to graceful 502, never a module-load crash).
- [ ] 1.5 POST JSON `{ email_address: email, tags: [WAITLIST_TAG] }` with headers
      `Authorization: Token ${apiKey}` + `content-type: application/json` and
      `signal: AbortSignal.timeout(WAITLIST_TIMEOUT_MS)`. **Do NOT send `type`** (preserve
      double opt-in).
- [ ] 1.6 Map: 200/201 → `{ok:true}`; 400-duplicate → `{ok:true}` (predicate from 0.1);
      other → `log.warn({status})` + throw. Never log/return the body or the key.
- [ ] 1.7 Update the function doc comment to describe the authenticated v1 API.

## Phase 2 — `.env.example` (`apps/web-platform/.env.example`)

- [ ] 2.1 Add `# --- Buttondown (waitlist) ---` section + `BUTTONDOWN_API_KEY=` with the
      "fails closed to a graceful 502" comment. No boot-schema edit (no env framework exists).

## Phase 3 — Tests (`apps/web-platform/test/api-waitlist-subscribe.test.ts`)

- [ ] 3.1 Update header comment; set/delete `process.env.BUTTONDOWN_API_KEY` in
      beforeEach/afterEach.
- [ ] 3.2 Success: mock 201; assert URL `api.buttondown.com/v1/subscribers`, header
      `Authorization: Token`, JSON body `{email_address, tags:["pricing-waitlist"]}`, NO `type` key.
- [ ] 3.3 Already-subscribed: mock v1 collision 400 body → 200 `{ok:true}`,
      `warnSilentFallback` not called.
- [ ] 3.4 Unexpected status (503) → 502 + `warnSilentFallback` (keep).
- [ ] 3.5 NEW timeout: mock rejection `name:"TimeoutError"` → 502 + `warnSilentFallback`.
- [ ] 3.6 NEW missing-key: `delete process.env.BUTTONDOWN_API_KEY` → 502, fetch NOT called.
- [ ] 3.7 Update the rate-limit test's mocked upstream 200 → 201.

## Phase 4 — Verify

- [ ] 4.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/api-waitlist-subscribe.test.ts` passes.
- [ ] 4.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [ ] 4.3 `git grep -n "embed-subscribe\|WAITLIST_USERNAME" apps/web-platform` returns 0.

## Phase 5 — Post-merge (operator)

- [ ] 5.1 After deploy, POST a valid email to prod `/api/waitlist` → 200 `{ok:true}`;
      subscriber appears under `pricing-waitlist` (pending double opt-in). `Ref` the issue;
      `gh issue close` only after prod verification.
