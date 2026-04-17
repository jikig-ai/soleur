---
title: Fix analytics-track `path` prop PII leak
issue: 2462
spec: knowledge-base/project/specs/feat-fix-analytics-track-path-pii/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-04-17-analytics-track-path-pii-brainstorm.md
branch: fix-analytics-track-path-pii
status: ready-for-review
---

# Plan: Fix analytics-track `path` prop PII leak (#2462)

## Overview

Defense-in-depth hardening for `/api/analytics/track`. The allowlist already
restricts forwardable prop keys to `path`, but the value is only length-capped
to 200 chars — it can still carry literal PII (emails, UUID v4 tokens, long
numeric customer IDs) through to Plausible.

This PR ships two coordinated layers:

1. **Server-side PII scrub** inside `sanitizeProps` — replaces matched tokens
   in the `path` value with fixed placeholder sentinels
   (`[email]`, `[uuid]`, `[id]`) BEFORE the existing 200-char slice, and
   reports which patterns fired via a new `scrubbed: string[]` field on the
   return type so the route can log pattern names (never raw/scrubbed values).
2. **Client-side contract** — JSDoc block on `lib/analytics-client.ts#track`
   documenting that callers MUST pass normalized paths
   (`/users/[uid]/settings`, not `/users/alice@example.com/settings`). The
   scrubber is a safety net, not the happy path.

No new dependencies. Pure-function scrub (no I/O, no async). Byte-identical
output for paths that contain none of the three patterns (TR5).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| Tests live at `apps/web-platform/app/api/analytics/track/__tests__/sanitize.test.ts` (TR3, "verify at plan time") | Tests live at `apps/web-platform/test/api-analytics-track.test.ts` (top-level `test/` convention per `vitest.config.ts` projects config — `include: ["test/**/*.test.ts", "lib/**/*.test.ts"]`). No colocated `__tests__` dir exists in this app. | Add new pure-function tests at `apps/web-platform/test/sanitize-props.test.ts` (unit project), and add one integration assertion for scrub-at-the-route to the existing `apps/web-platform/test/api-analytics-track.test.ts`. |
| Spec hints route-level `log.debug({scrubbed}, ...)` already exists for `dropped` | Confirmed: `route.ts:73-76` already logs `dropped` at debug via `log.debug({ dropped }, "...")`. | Mirror the exact pattern for `scrubbed`. One extra `if (scrubbed.length > 0) log.debug(...)` line. |
| Spec calls scrub "only applies to `path` key" (FR5) | `ALLOWED_PROP_KEYS` is currently `Set(["path"])` — `path` is the only allowlisted key. | Scrub logic keys on the literal string `"path"` inside `sanitizeProps`. If a future PR adds a new allowlisted key, its security review decides whether the scrubber applies. |

## Open Code-Review Overlap

Checked open `deferred-scope-out` and `code-review` issues against planned file
paths (`app/api/analytics/track/sanitize.ts`, `route.ts`,
`lib/analytics-client.ts`, `test/api-analytics-track.test.ts`). Matches:

- **#2461** (refactor: shared `lib/log-sanitize.ts` helper) — touches
  `sanitize.ts` and `lib/auth/validate-origin.ts`. **Disposition: Acknowledge.**
  Concern is helper-extraction for the existing `sanitizeForLog` /
  `rejectCsrf` control-char dedup, not PII scrub. Orthogonal to this PR. The
  scope-out remains open.
- **#2391** (session supersession UX + rate-limit scaling note) — mentions
  `route.ts` only in PR #2347 context. **Disposition: Acknowledge.** Unrelated
  concern (ws-handler session semantics + rate-limit scaling docs).
- **#2387** (Sheet YAGNI + refs convergence + drain-response removal) — also
  a PR #2347 scope-out referencing `route.ts` incidentally. **Disposition:
  Acknowledge.** Unrelated (Sheet component + ref patterns in `kb-chat-sidebar`).
- **#2462** (this issue) — self-reference, not overlap.

No fold-ins. No deferrals to re-evaluate.

## Implementation Phases

### Phase 1 — RED tests (pure function)

**File:** `apps/web-platform/test/sanitize-props.test.ts` (NEW)

Spec §"Test Scenarios" lists 10 cases. Add one RED test per case, all in a
single `describe("sanitizeProps — path PII scrub")` block. Import the target:

```ts
import { sanitizeProps } from "@/app/api/analytics/track/sanitize";
```

Test shape (all three fields asserted per case, since the return type is
being extended):

```ts
test("email in path → [email] sentinel", () => {
  const out = sanitizeProps({ path: "/users/alice@example.com/settings" });
  expect(out.clean.path).toBe("/users/[email]/settings");
  expect(out.scrubbed).toEqual(["email"]);
  expect(out.dropped).toEqual([]);
});
```

Full case list (mirrored from spec §"Test Scenarios"):

| # | Input `path` | Expected `clean.path` | Expected `scrubbed` |
|---|---|---|---|
| 1 | `/users/alice@example.com/settings` | `/users/[email]/settings` | `["email"]` |
| 2 | `/u/550e8400-e29b-41d4-a716-446655440000/settings` | `/u/[uuid]/settings` | `["uuid"]` |
| 3 | `/billing/customer/123456/invoices` | `/billing/customer/[id]/invoices` | `["id"]` |
| 4 | `/blog/2026-04-17-foo` | `/blog/2026-04-17-foo` | `[]` |
| 5 | `/docs/v12.4.1/install` | `/docs/v12.4.1/install` | `[]` |
| 6 | `/?q=hello` | `/?q=hello` | `[]` |
| 7 | `/u/alice@example.com/550e8400-e29b-41d4-a716-446655440000` | `/u/[email]/[uuid]` | `["email","uuid"]` |
| 8 | `/kb/docs/getting-started` | `/kb/docs/getting-started` | `[]` |
| 9 | non-string `path` (number `42`) | passes through untouched | `[]` |
| 10 | 500-char path, no PII | first 200 chars preserved, scrubbed empty | `[]` |

Extra RED cases (locks in design decisions beyond the 10-case minimum):

- **Case 11 — uppercase UUID:** `/u/550E8400-E29B-41D4-A716-446655440000` →
  `/u/[uuid]` with `scrubbed: ["uuid"]`. Guards the case-insensitive flag on
  the UUID regex per FR2.
- **Case 12 — scrub runs BEFORE slice (FR4 assertion):** An input where the
  email starts at char 195 and extends past 200 chars must scrub the full
  email to `[email]` and NOT truncate mid-pattern. Example:
  `"/a".repeat(100) + "@example.com"` (length ~212 including the email
  tail). After scrub, the full email must be replaced with `[email]`, so the
  output length is `200 - ("<email-len>") + len("[email]")` approx. The
  assertion: `out.clean.path.includes("[email]")` AND
  `out.clean.path.length <= 200`. This pins the "scrub-before-slice" ordering.
- **Case 13 — scrubbed is unique-per-pattern even when the same pattern
  fires twice:** `/u/a@b.com/c@d.com` → `/u/[email]/[email]`, but
  `scrubbed === ["email"]` (NOT `["email","email"]`). Guards the
  uniqueness claim in the implementation summary.
- **Case 14 — order stability:** A path that fires email AND uuid AND id
  (`/u/a@b.com/550e8400-e29b-41d4-a716-446655440000/654321`) must produce
  `scrubbed: ["email","uuid","id"]` in that exact order (matches the scrub
  application order in FR4). Pins the array order so downstream operator
  dashboards can count pattern frequency deterministically.
- **Case 15 — dropped still works:** Non-allowlisted keys continue to land
  in `dropped` untouched by this change:
  `sanitizeProps({ path: "x", email: "a@b.com", fingerprint: "f" })` →
  `clean: { path: "x" }`, `dropped: ["email","fingerprint"]`,
  `scrubbed: []`.

**Why RED-first:** AGENTS.md `cq-write-failing-tests-before` — the plan has
Test Scenarios and Acceptance Criteria, so tests must fail before
implementation lands. In worktrees, run via
`cd apps/web-platform && ./node_modules/.bin/vitest run test/sanitize-props.test.ts`
per `cq-in-worktrees-run-vitest-via-node-node`. All cases must be RED
(current `sanitizeProps` returns `{ clean, dropped }` with no `scrubbed` key;
TypeScript will flag `out.scrubbed` as missing). This is the intended RED
signal.

**File:** `apps/web-platform/test/api-analytics-track.test.ts` (EDIT)

Add ONE new integration test locking in the route-level debug log wiring
(mirroring the existing `dropped` log pattern at `route.ts:74-76`):

```ts
test("T8: logs scrub pattern names at debug when path contains PII (never raw value)", async () => {
  mockFetch.mockResolvedValue(new Response("", { status: 202 }));
  const { POST } = await importRoute();
  const req = makeRequest("https://app.soleur.ai/api/analytics/track", {
    origin: "https://app.soleur.ai",
    body: {
      goal: "kb.chat.opened",
      props: { path: "/users/alice@example.com/settings" },
    },
  });
  await POST(req);

  // Forwarded payload is scrubbed.
  const [, init] = mockFetch.mock.calls[0];
  const payload = JSON.parse(String((init as RequestInit).body));
  expect(payload.props.path).toBe("/users/[email]/settings");

  // Debug log fires with pattern NAMES only — never the raw value.
  const scrubCall = logDebug.mock.calls.find(([, msg]) =>
    typeof msg === "string" && msg.includes("scrubbed"),
  );
  expect(scrubCall).toBeDefined();
  const [ctx] = scrubCall!;
  expect(ctx).toMatchObject({ scrubbed: ["email"] });
  // The raw value (pre-scrub) must never appear in ANY debug ctx field.
  const allDebugCtx = JSON.stringify(logDebug.mock.calls);
  expect(allDebugCtx).not.toContain("alice@example.com");
});
```

### Phase 2 — GREEN implementation

**File:** `apps/web-platform/app/api/analytics/track/sanitize.ts` (EDIT)

Extend `sanitizeProps` return type and add `scrubPath` helper. Final module:

```ts
// Allowlist-based prop sanitization + log sanitization for
// /api/analytics/track. Sibling module per cq-nextjs-route-files-http-only-exports.

const ALLOWED_PROP_KEYS = new Set<string>(["path"]);

const MAX_PROP_STRING_LEN = 200;
const MAX_DROPPED_KEYS_LOGGED = 20;

// Scrub patterns for the `path` prop. Order matters — email first (can
// contain @ which no other pattern touches), UUID v4 second (has strict
// hyphenated structure), then 6+ consecutive digits last. All patterns are
// global; UUID is case-insensitive.
// Scope per FR5: patterns apply ONLY when the prop key is "path". Adding a
// new allowlisted key requires a per-key security review that decides
// whether the scrubber applies.
const EMAIL_RE = /\S+@\S+\.\S+/g;
const UUID_V4_RE = /[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/gi;
const LONG_DIGIT_RUN_RE = /\d{6,}/g;

// Scrubs PII tokens from a path value. Returns the scrubbed string and the
// ordered list of pattern names that fired (unique). Pure function.
function scrubPath(value: string): { clean: string; scrubbed: string[] } {
  const fired: string[] = [];
  let out = value;
  if (EMAIL_RE.test(out)) {
    fired.push("email");
    out = out.replace(EMAIL_RE, "[email]");
  }
  if (UUID_V4_RE.test(out)) {
    fired.push("uuid");
    out = out.replace(UUID_V4_RE, "[uuid]");
  }
  if (LONG_DIGIT_RUN_RE.test(out)) {
    fired.push("id");
    out = out.replace(LONG_DIGIT_RUN_RE, "[id]");
  }
  return { clean: out, scrubbed: fired };
}

export function sanitizeProps(
  props: Record<string, unknown> | undefined,
): { clean: Record<string, unknown>; dropped: string[]; scrubbed: string[] } {
  if (!props) return { clean: {}, dropped: [], scrubbed: [] };
  const clean: Record<string, unknown> = {};
  const dropped: string[] = [];
  const scrubbedSet = new Set<string>();
  for (const [k, v] of Object.entries(props)) {
    if (!ALLOWED_PROP_KEYS.has(k)) {
      if (dropped.length < MAX_DROPPED_KEYS_LOGGED) dropped.push(k);
      continue;
    }
    if (k === "path" && typeof v === "string") {
      // Scrub FIRST (FR4) — emails can be >200 chars and truncation would
      // split a pattern mid-match, leaking a partial email.
      const { clean: scrubbedVal, scrubbed } = scrubPath(v);
      for (const name of scrubbed) scrubbedSet.add(name);
      clean[k] = scrubbedVal.slice(0, MAX_PROP_STRING_LEN);
    } else {
      clean[k] = typeof v === "string" ? v.slice(0, MAX_PROP_STRING_LEN) : v;
    }
  }
  // Preserve scrub-application order (email → uuid → id) in the returned
  // array. A Set iterator preserves insertion order in JS.
  return { clean, dropped, scrubbed: [...scrubbedSet] };
}

export function sanitizeForLog(s: string): string {
  return s.replace(/[\x00-\x1f\x7f\u2028\u2029]/g, "");
}
```

**Why a helper and not inline in the loop:** Keeps the loop body readable
(one key = one line of scrub logic), and the helper is unit-testable
independently if ever exported. The helper is NOT exported in this PR — only
`sanitizeProps` is the public API — to preserve the chokepoint contract.

**Why `const` regexes at module scope:** Avoids per-call compilation cost.
The `/g` flag with `.test()` is safe here because `.test()` advances
`lastIndex`, but we call `.test()` once followed by `.replace()` which
resets traversal — and we do this once per call, not in a loop over the same
regex. The pattern is guarded by the ordered-branch structure.

**Alternative considered and rejected:** A single "scan once, record all
matches, then replace" pass. Rejected because (a) the three patterns have
distinct replacement sentinels, (b) email scrubbing first simplifies the
case where an email contains a 6+ digit run (`alice123456@host.tld`) — the
entire email collapses to `[email]` before the digit-run scanner runs, so
the digits never get double-scrubbed to `[email][id]`. The ordered
sequential pass is simpler and correct.

**File:** `apps/web-platform/app/api/analytics/track/route.ts` (EDIT)

Update the destructuring at line 73 and add one debug log line mirroring the
existing `dropped` log (lines 74-76). Diff:

```diff
-  const { clean: safeProps, dropped } = sanitizeProps(parsed.props);
+  const { clean: safeProps, dropped, scrubbed } = sanitizeProps(parsed.props);
   if (dropped.length > 0) {
     log.debug({ dropped }, "analytics.track dropped non-allowlisted props");
   }
+  if (scrubbed.length > 0) {
+    log.debug({ scrubbed }, "analytics.track scrubbed PII from path");
+  }
```

**No Sentry mirror needed** for this log: the scrub action is not an error
and not a silent fallback — the request succeeds end-to-end (path forwarded
to Plausible in scrubbed form, 204 returned to the client). Per
`cq-silent-fallback-must-mirror-to-sentry`, the exempt list includes
"intentional pass-through" — scrubbing is an intentional transformation,
not a degraded condition. The debug log is an operator signal that a caller
is sending unnormalized paths; if this fires in production, the fix is on
the caller side (JSDoc contract), not a server-side error to surface in
Sentry dashboards.

**File:** `apps/web-platform/lib/analytics-client.ts` (EDIT)

Add JSDoc block on `track()` documenting the caller contract. Final file:

```ts
// Thin client for emitting analytics goals to /api/analytics/track, which
// forwards to Plausible. Fail-soft: analytics must never break user flows.
// See plan 5.1 + 5.2 for server route + provisioning.

/**
 * Emit an analytics goal to the server forwarder (Plausible).
 *
 * **Caller contract — `path` prop:** when `props.path` is set, callers MUST
 * pass a NORMALIZED path — dynamic segments replaced with stable placeholders
 * (Next.js-style):
 *
 * - `/users/[uid]/settings` — NOT `/users/alice@example.com/settings`
 * - `/kb/docs/[slug]` — NOT `/kb/docs/550e8400-e29b-41d4-a716-446655440000`
 * - `/billing/customer/[id]/invoices` — NOT `/billing/customer/123456/invoices`
 *
 * Why: the dashboard groups pageviews by `path`; un-normalized paths produce
 * a long tail of one-off rows and leak PII (emails, UUIDs, customer IDs) into
 * Plausible. The server has a defense-in-depth scrubber
 * (`app/api/analytics/track/sanitize.ts`) that replaces matched tokens with
 * fixed sentinels (`[email]`, `[uuid]`, `[id]`) — but the scrubber is a
 * safety net, not the happy path. Normalize at the call site.
 *
 * Fail-soft: never throws, never blocks the caller.
 *
 * @param goal   Plausible goal name (≤120 chars).
 * @param props  Optional props; only the `path` key is forwarded today
 *               (allowlist in `app/api/analytics/track/sanitize.ts`).
 */
export async function track(
  goal: string,
  props?: Record<string, unknown>,
): Promise<void> {
  if (typeof window === "undefined") return;
  try {
    await fetch("/api/analytics/track", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ goal, props }),
      keepalive: true,
    });
  } catch {
    // fail-soft
  }
}
```

No runtime code change to `track()`. JSDoc-only addition. The existing 3
call sites in `kb-chat-content.tsx:63, 93, 94` all pass `contextPath` which
is already a KB content path — none of the three scrub patterns fire in
normal operation.

### Phase 3 — verification

1. **Unit tests (sanitize-props.test.ts):** `cd apps/web-platform &&
   ./node_modules/.bin/vitest run test/sanitize-props.test.ts`. Expect all
   15 cases (10 from spec + 5 edge cases) GREEN.
2. **Integration tests (api-analytics-track.test.ts):** `cd apps/web-platform
   && ./node_modules/.bin/vitest run test/api-analytics-track.test.ts`.
   Expect all existing T1–T7 tests still GREEN plus new T8 GREEN.
3. **Full web-platform unit suite:** `cd apps/web-platform &&
   ./node_modules/.bin/vitest run`. Expect no regressions.
4. **Typecheck:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
   No type errors expected (return type of `sanitizeProps` widens additively;
   `route.ts` destructures the new field).
5. **Manual RegExp sanity:** Spec §"Acceptance Criteria" cases 4 and 5
   (`/blog/2026-04-17-foo` and `/docs/v12.4.1/install`) — verify via the test
   suite that max-4-digit runs (dates) and version numbers with dots pass
   through unchanged. These are the primary false-positive risk.

## Files to Edit

- `apps/web-platform/app/api/analytics/track/sanitize.ts` — add `scrubPath`
  helper, extend `sanitizeProps` return type with `scrubbed: string[]`, apply
  scrub to `path` key before 200-char slice.
- `apps/web-platform/app/api/analytics/track/route.ts` — destructure
  `scrubbed` from `sanitizeProps` result; add one-line debug log when
  `scrubbed.length > 0` (mirrors existing `dropped` log).
- `apps/web-platform/lib/analytics-client.ts` — add JSDoc block on `track()`
  documenting caller contract with `/users/[uid]/settings` example.
- `apps/web-platform/test/api-analytics-track.test.ts` — add T8 integration
  test asserting route-level debug log + scrubbed payload, with assertion
  that raw value never appears in debug context.

## Files to Create

- `apps/web-platform/test/sanitize-props.test.ts` — 15-case unit suite for
  `sanitizeProps` covering spec §"Test Scenarios" plus ordering / uniqueness
  edge cases.

## Acceptance Criteria

Mirrored from spec §"Acceptance Criteria" + brainstorm §"Acceptance Criteria":

- [ ] `sanitizeProps({ path: "/users/alice@example.com/settings" }).clean.path` →
      `/users/[email]/settings` AND `.scrubbed` equals `["email"]`.
- [ ] `sanitizeProps({ path: "/u/550e8400-e29b-41d4-a716-446655440000/settings" }).clean.path` →
      `/u/[uuid]/settings` AND `.scrubbed` equals `["uuid"]`.
- [ ] `sanitizeProps({ path: "/billing/customer/123456/invoices" }).clean.path` →
      `/billing/customer/[id]/invoices` AND `.scrubbed` equals `["id"]`.
- [ ] `sanitizeProps({ path: "/blog/2026-04-17-foo" }).clean.path` →
      `/blog/2026-04-17-foo` (date hyphens split runs to ≤4 digits).
- [ ] `sanitizeProps({ path: "/docs/v12.4.1/install" }).clean.path` →
      `/docs/v12.4.1/install` (version-number dots preserved).
- [ ] `sanitizeProps({ path: "/?q=hello" }).clean.path` → `/?q=hello` (query
      strings pass through unchanged; Plausible strips them anyway).
- [ ] Uppercase UUID scrubs: `/u/550E8400-E29B-41D4-A716-446655440000` →
      `/u/[uuid]`.
- [ ] Scrub runs BEFORE length-cap slice (email at char 195 scrubs to
      `[email]` without truncation mid-pattern).
- [ ] `scrubbed` array is unique-per-pattern (two emails → one `"email"`
      entry) and ordered `email → uuid → id`.
- [ ] Route-level `log.debug({ scrubbed }, ...)` fires when
      `scrubbed.length > 0`; raw/original path value never appears in any
      debug log field.
- [ ] JSDoc on `lib/analytics-client.ts#track` documents the caller contract
      with a `/users/[uid]/settings` example.
- [ ] Existing tests T1–T7 in `api-analytics-track.test.ts` continue to pass
      unchanged.
- [ ] New tests added RED-first (fail before implementation, pass after).
- [ ] `sanitizeProps({ path: "knowledge-base/x.md" })` produces byte-identical
      `clean.path` to pre-change behavior (TR5 regression guard).

## Test Scenarios

See `spec.md §"Test Scenarios"` for the 10-case table; Phase 1 extends with 5
additional ordering / uniqueness / regression cases (11–15). Full 15-case
list lives in Phase 1 above.

## Non-Goals / Out of Scope

- **Adding more allowlisted prop keys** — separate security review per key.
- **Scrubbing query strings** — Plausible strips them on its side; out of
  scope per spec.
- **Remediating already-collected PII in Plausible** — operator concern per
  spec; retention config lives outside this repo.
- **Modifying throttle, CSRF, or rate-limiting layers.**
- **Shared log-sanitize helper extraction (#2461)** — orthogonal concern,
  remains open for its own cycle.
- **Runtime change to `track()`** — JSDoc-only; callers already pass
  normalized paths in the 3 existing call sites.

## Domain Review

**Domains relevant:** Engineering (implicit — this is the current task's
topic; per `pdr-do-not-route-on-trivial-messages-yes` we do not re-route to
CTO during an engineering task whose core concern IS engineering).

Brainstorm carry-forward: the brainstorm's `## Domain Assessments` section
(lines 124-133) explicitly states:

> No domain leaders spawned. Rationale: this is an internal server-side
> security hardening fix with zero user-visible surface, no marketing or
> product implications, no change to legal/privacy posture (in fact,
> strictly improves it). The AGENTS.md rule
> `hr-new-skills-agents-or-user-facing` applies only to new user-facing
> capabilities; this change tightens an existing chokepoint without adding
> capability.

Plan skill Phase 2.5 carry-forward rule applies: no fresh domain assessment
needed. No new specialists recommended by name in the brainstorm.

### Product/UX Gate

**Tier:** none.

No user-facing surface — this is a server-side chokepoint hardening + a
client-library JSDoc. No new `components/**/*.tsx`, `app/**/page.tsx`, or
`app/**/layout.tsx` files. Mechanical escalation check: none of the files in
"Files to Create" / "Files to Edit" match the BLOCKING path patterns.

## PR Requirements

- **Title:** `fix(analytics-track): scrub PII from path prop (#2462)`
- **Body MUST include:** `Closes #2462` (per
  `wg-use-closes-n-in-pr-body-not-title-to`).
- **Labels:** `type/security`, `priority/p3-low` (both confirmed present via
  `gh label list` per `cq-gh-issue-label-verify-name`).
- **Milestone:** `Post-MVP / Later` (inherits from issue #2462).

## Risks & Sharp Edges

- **Regex `/g` + `.test()` + `.replace()` ordering:** `.test()` on a `/g`
  regex advances `lastIndex`, but `.replace()` with `/g` resets traversal
  internally. The pattern here is one-call-each per `scrubPath` invocation,
  so no reuse hazard. Guarded by the explicit unit tests (cases 11–13).
- **False-positive risk on UUID regex:** strict UUID v4 format
  (version nibble `4`, variant nibble `8|9|a|b`) makes accidental matches in
  real paths extremely unlikely. Version numbers like `v1.2.3` fail the
  regex (no hyphens, wrong length).
- **False-positive risk on 6+ digit run:** Covered by spec cases 4 and 5
  (dates and version numbers). A legitimate path slug containing 6+
  consecutive digits (e.g., `/docs/rfc-1234567`) WOULD get scrubbed to
  `/docs/rfc-[id]`. This is the intended trade-off per brainstorm §"Key
  Decisions": "A legitimate 6-digit-consecutive token in a path slug is
  exceptional." If a real caller ever hits this, the scrubber is visible in
  the dashboard (path aggregates to `/docs/rfc-[id]`) and can be addressed
  by narrowing the pattern — not a silent correctness failure.
- **No test for regex catastrophic backtracking:** All three patterns are
  linear in input size (no nested quantifiers, no `.*.*`). EMAIL regex uses
  `\S+` which is O(n); UUID regex is fixed-length; digit-run regex is simple
  `\d{6,}`. No ReDoS exposure.
- **Worktree vitest:** Run via `./node_modules/.bin/vitest` from
  `apps/web-platform/`, not `npx vitest` at repo root
  (`cq-in-worktrees-run-vitest-via-node-node`).

## Implementation Order (for soleur:work)

1. **RED — write tests.** Create `test/sanitize-props.test.ts` with all 15
   cases. Add T8 to `test/api-analytics-track.test.ts`. Run the new files
   only; expect compilation failure (missing `scrubbed` field) + assertion
   failures.
2. **GREEN — implement.** Edit `sanitize.ts` to extend return type and add
   `scrubPath` helper. Edit `route.ts` to destructure and log. Run tests
   again; expect all GREEN.
3. **Docs — JSDoc.** Edit `lib/analytics-client.ts` to add the JSDoc block
   on `track()`.
4. **Regression check.** Run full web-platform unit suite + typecheck.
5. **Commit + review + ship.** Standard pipeline. Per
   `rf-review-finding-default-fix-inline`, any review findings fix inline on
   this branch unless they hit a scope-out criterion.
