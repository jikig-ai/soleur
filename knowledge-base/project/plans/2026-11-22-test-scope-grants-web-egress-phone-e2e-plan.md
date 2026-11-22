---
title: "test: phone-width e2e for the Scope Grants web-egress disclosures"
type: chore
date: 2026-11-22
slug: test-scope-grants-web-egress-phone-e2e
branch: feat-one-shot-12605-scope-grants-phone-e2e
issue: 12605
closes: 12605
priority: p3
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# test: phone-width e2e for the Scope Grants web-egress disclosures

## Overview

Prove at 390x844 that a workspace Owner can read the push and `gh` disclosures on Settings > Scope Grants and reach the
enable dialog's confirm button, by extending the offline e2e Supabase mock with only the reads this page lacks and adding
one Playwright spec.

## Research Insights

### Premise Validation

- #12605 is open with no closing PR. The only open change naming it is this branch's draft PR #13017 (`collision-precheck.sh`: `foreign=none`).
- #12937 (Web Platform Release blocked at the registry bridge) is open, so the brief's `release_failed` branch is live.
- PR #12567 merged 2026-11-10 and owed this check. PR #12704 merged 2026-11-18 and added the mock's `workspace_members` branch.
- **Stale in the issue:** "the mock has no `workspace_members` / workspace handlers". `mock-supabase.ts` has both, but they answer only `HELD_E2E_USERS`, and the membership row has no `role`, so the page's `membership?.role === "owner"` is false for every mock user.
- **Missing from the issue:** a `web_egress` row is not enough. `resolveWebEgress` reads through `getFreshTenantClient`, whose mint path the mock does not serve, so the read fails closed to `false` whatever the row says.
- No ADR rejects extending the offline mock. ADR-049 and ADR-064 mention it only as context.

### The exact gap (measured)

A throwaway probe ran the real Next dev server, Chromium and Supabase SDK against a scratch front for the repo mock. Nothing from it is committed. This handler set rendered both states with no page errors. `user_session_state` and the `workspaces` row do not change the rendered copy, because a 404 also ends in "unknown". They stay so that the fixture's null org is what produces that state and the `web_egress` row is what the RPC returns (ruling F7).

| Request | Needed because |
|---|---|
| `GET /auth/v1/user` | the fixture's own identity (today any unknown `sub` becomes the non-UUID `MOCK_USER`) |
| `GET /auth/v1/admin/users/<id>` | mint step 1, `resolveFounderEmail` |
| `POST /rest/v1/runtime_mint_intent` | mint step 2, the intent upsert |
| `POST /auth/v1/admin/generate_link` | mint step 3, must return `hashed_token` |
| `POST /auth/v1/verify` | mint step 4, session JWT with a UUID `jti` and numeric `exp` |
| `GET /rest/v1/user_session_state` | `readWorkspaceIdFromDb`; a null pointer drops the card state |
| `GET /rest/v1/workspace_members` | the `role: "owner"` row |
| `POST /rest/v1/rpc/is_jti_denied` | the mint's deny probe; a 404 fails open today, so a future fail-closed change would otherwise turn this spec red for an unrelated reason |
| `GET /rest/v1/workspaces` | `organization_id` and `name` for the collection state; holds `web_egress` |
| `POST /rest/v1/rpc/get_workspace_web_egress` | returns the row's `web_egress` to the toggle |

Measured at 390x844 on the unmodified page: rightmost descendant of each surface 333 px or less; the disclosures are separate `<p>`s; confirm button at x=172 y=422 w=144 h=56, topmost at its center, Playwright trial click passes.

### Two measured traps

1. **The issue's document-level overflow check cannot fail on this route.** `SettingsShell` wraps content in `overflow-x-hidden`. A 700 px child injected into the callout left `document.documentElement.scrollWidth` at 390 while the clipping ancestor reported 770.
2. **Element rects miss text overflow.** The page already clips one string: the `<code>` in `components/scope-grants/scope-grant-row.tsx` holding `external.brand_critical.bluesky_reply_soleur_handle` runs past its 268 px box, so the clipping ancestor reports `scrollWidth` 428 against `clientWidth` 390. A scan of element rects found zero offenders. Only a text-aware measure sees it.

### Repo conventions and learnings applied

- `playwright.config.ts` routes `**/nav-states-*.e2e.ts` to the `authenticated` project, so that filename needs no config change. Any other name would run against the wrong server.
- No test pins the mock's exports. `test/eslint-config.test.ts` pins lint counts (`BASELINE_BY_RULE`), so the spec must add no lint warnings.
- A new e2e file carries a `pyramid-justified:` marker (`test-design-reviewer`); `2026-10-09-a-pyramid-marker-covers-a-files-tests-not-its-dominant-signal.md` requires it to hold for each `test()`.
- `2026-04-10-e2e-authenticated-dashboard-tests-mock-supabase.md`: `page.route` cannot reach server-side reads, so values must come from the mock server.
- `2026-06-29-playwright-tohaveclass-auto-retries-poll-swap-is-noop.md`: a pre-hydration click is a silent no-op; retry the click with `toPass`, as `openDisconnect` does in `settings-kb-sync-held.e2e.ts`.
- `2026-06-02-visual-regression-gate-must-assert-content-not-band-box.md` and `2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`: assert content before layout, and prove each check can go red.
- `2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md`: the mock does not enforce grants, so this spec proves rendering only, not tenant access.
- Community registries: partial overlap only (generic Playwright generators); nothing covers this page or mock. Nothing installed.

### Property List

1. The mock answers the page's membership read with an Owner row.
2. The mock holds a workspace row with `web_egress` true and one with false, and the page reads each through the real resolver.
3. At 390x844 the ON block, enable dialog and callout do not overflow horizontally.
4. On each surface, each disclosure is its own paragraph.
5. The dialog's confirm button is in the viewport after `scrollIntoViewIfNeeded()`.

### Cut List

- Handlers for `scope_grants`, `template_authorizations`, `get_egress_audit_summary` → property 2 → the 404 already renders the empty state.
- A handler for `get_workspace_bash_autonomous` → property 2 → a 404 resolves to `false`, the value both fixtures need.
- A `/api/workspace/web-egress` write handler → no property → the spec never confirms the dialog.
- `playwright.config.ts` and `global-setup.ts` edits → no property → the `nav-states-*` glob routes the spec, and it builds its storage state inline as `settings-kb-sync-held.e2e.ts` does.
- `/auth/v1/token` refresh for the new fixtures → no property → the session lasts 24 hours.
- A new session helper → property 1 → `heldSessionFor(userId)` is already generic.
- A write-request recorder → no property → the spec never confirms the dialog and Supabase is the offline mock.
- Vertical clipping checks on disclosure paragraphs → no property → outside the issue's acceptance, and a reviewer reproduced a false green in them (ruling F8).

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Technical Rulings

Ruled by CTO agent, 2026-11-22. The table is mirrored in `knowledge-base/project/specs/feat-one-shot-12605-scope-grants-phone-e2e/decision-challenges.md`.

| Fork | Ruling | Rationale |
|---|---|---|
| F1. How fixtures reach `web_egress=true` | Answer the mint path in the mock for new UUID fixtures only | Runs the real read path with no production change; a resolver bypass would weaken a fail-closed security read |
| F2. Overflow assertion | Keep the literal check and add a per-surface text-rect and `scrollWidth` check | The literal check cannot fail inside the clipping shell |
| F3. Clipped action-class id | Leave it out of this PR and track it in #13018 | The brief limits this PR to the mock and one spec, and the defect is live for phone users |
| F4. Dialog copy variant | `organization_id` null on both fixtures, so the longest "unknown" copy renders | It is a superset of the other copy, so it is the layout worst case |
| F5. Rejected approaches | Do not reuse held fixtures, do not copy `expectNoHorizontalScroll`, do not measure before proving state | Each lets the spec pass without proving the phone layout |
| F6. How the ON state is reached (plan-review challenge) | Keep the mint path; do not click to ON against a stub | The issue names the `web_egress` true row and the click path would leave it unread, so dropping it is the operator's scope call |
| F7. `user_session_state` branch | Keep the pointer and return the RPC value from the fixture's row after the `sub` and `p_workspace_id` checks, else `null` | Both row fields become load-bearing and the page does not render through a simulated read failure |
| F8. Vertical clipping checks | Delete them and record the Non-Goal | They are outside the acceptance, and today's surfaces carry no vertical clip |

## Proposed Solution

Two files, no production code.

### Files to Edit

- `apps/web-platform/e2e/mock-supabase.ts`: add the `EGRESS_E2E_USERS` fixtures, their workspace rows, `notFound`, `withJsonBody`, and the ten request branches in "The exact gap".

### Files to Create

- `apps/web-platform/e2e/nav-states-scope-grants-web-egress.e2e.ts`: the 390x844 spec.

### Mock design

- Two synthesized fixtures, ids `00000000-0000-4000-8000-0000000012c1` (`web_egress: true`) and `...12c2` (`false`), each with a fixed UUID `jti` (`...12d1`, `...12d2`). Sessions come from the existing `heldSessionFor(userId)`, so emails stay on `example.com`.
- Each fixture owns a solo workspace whose id is the user id. One table holds its row: `{ organization_id: null, name, web_egress }`. `user_session_state` returns that id as `current_workspace_id`.
- `mintMockJwt` gains an optional `jti` argument. Existing tokens stay byte-identical because the claim is added only when the argument is passed.
- Every new branch answers only for a fixture id. Anything else reaches the existing 404, so no other spec changes behaviour.
- Add `notFound()`, used by both the catch-all and the new branches. It returns early if headers were sent, and prints one stderr line per distinct method and pathname (`[mock-supabase] unhandled POST /auth/v1/...`). The mock runs in the Playwright runner, so that line reaches the CI log, while the dev server's stdout does not.
- Add `withJsonBody(req, res, handler)`: `void readBody(req).then((raw) => handler(JSON.parse(raw || "{}"))).catch(() => notFound())`. A handler declines by calling `notFound()`. Every body branch is written `return withJsonBody(...)`, because a missing synchronous `return` lets the catch-all write first and the late write throws `ERR_HTTP_HEADERS_SENT`.
- Where the bearer `sub` or the URL identifies the fixture, gate on it synchronously and fall through for anything else, so only fixture requests go async.
- `get_workspace_web_egress` picks the fixture by the bearer's `sub` and returns its row's `web_egress` only when `p_workspace_id` is its own workspace, else `null`, matching the real RPC's answer to a non-member.
- `is_jti_denied` returns `false` for the two fixture `jti` values and sends anything else to `notFound()`.
- `workspace_members` returns `{ user_id, workspace_id, role: "owner", workspaces: { organization_id: null } }`, and `[]` when a `workspace_id` filter names another workspace.

### Spec design

Two tests, each with `test.setTimeout(180_000)` for a cold compile and a `pyramid-justified:` header covering both: real-Chromium layout measurement from real server state, which jsdom cannot do.

Each test proves state before it measures:

1. Sign in as the fixture with inline storage state and stub the shell routes. Collect `pageerror` events.
2. Open `/dashboard/settings/scope-grants` at 390x844 with the transient-abort retry from `settings-kb-sync-held.e2e.ts`.
3. Assert the switch's `aria-checked` and that it is enabled. The ON assertion carries a diagnostic message, because any mock fault otherwise reads only as `"false"`:

   ```ts
   await expect(toggle, "web_egress read fell closed to OFF. Check [mock-supabase] unhandled lines, then compare the mock's egress branches with mintFounderJwt in lib/supabase/tenant.ts.").toHaveAttribute("aria-checked", "true");
   ```

4. Wait for hydration. The OFF test proves it with the click retry. The ON test polls `toggle.evaluate((el) => Object.keys(el).some((k) => k.startsWith("__reactProps$")))`.
5. Assert the render count of each disclosure, then hide `nextjs-portal`, which floats over content on the dev server only.
6. Run the surface and paragraph checks on each surface.
7. End by asserting no "Something went wrong" heading and an empty `pageerror` list, as `settings-kb-sync-held.e2e.ts` does.

```ts
// The shell's overflow-x-hidden makes the document check unable to fail, so each surface is also measured.
// Range rects include text nodes, which element rects miss.
async function expectFitsPhone(page: Page, surface: Locator): Promise<void> {
  await expect(surface).toBeVisible(); // Fail fast: the config sets no actionTimeout.
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
  const m = await surface.evaluate((el) => {
    const range = document.createRange();
    range.selectNodeContents(el);
    const rects = [...range.getClientRects()].filter((r) => r.width > 0);
    return {
      count: rects.length,
      left: Math.min(...rects.map((r) => r.left)),
      right: Math.max(...rects.map((r) => r.right)),
      scrollWidth: el.scrollWidth,
      clientWidth: el.clientWidth,
    };
  });
  expect(m.count).toBeGreaterThan(0);
  expect(m.left).toBeGreaterThanOrEqual(0);
  expect(m.right).toBeLessThanOrEqual(390);
  expect(m.scrollWidth).toBeLessThanOrEqual(m.clientWidth);
}
```

The render count also sees a disclosure added in another tag or outside the section, and ignores the RSC `<script>` payload:

```ts
await expect(page.getByText(PUSH_DISCLOSURE, { exact: true })).toHaveCount(n);
await expect(page.getByText(GH_DISCLOSURE, { exact: true })).toHaveCount(n);
```

`n` is 2 when ON, 1 when OFF with the dialog closed, and 2 when OFF with the dialog open.

Surface locators are anchored on the imported constant, so a wording change elsewhere cannot stall the spec, and none needs a production `data-testid`:

```ts
const section = page.locator("#agent-web-access");
const push = section.locator("p", { hasText: PUSH_DISCLOSURE });
const onBlock = push.first().locator("xpath=.."); // ON test only
const callout = push.last().locator("xpath=..");
const dialog = section.getByRole("alertdialog");
const toggle = section.getByRole("switch");
```

The paragraph check reads `surface.locator("p").allTextContents()`, trims each, and requires exactly one entry equal to `PUSH_DISCLOSURE` and exactly one equal to `GH_DISCLOSURE`, imported from `lib/web-egress-disclosure.ts`.

The dialog opens with the `toPass` click retry. The confirm button then takes `scrollIntoViewIfNeeded()`, `toBeInViewport({ ratio: 1 })` and `click({ trial: true })`. The trial click proves nothing covers it and fires no handler. The spec never performs a real confirm.

All of these assertions ran in the probe against the real page and passed. In the same probe, a 120-character unbroken token drove the surface check red on each surface.

## Implementation Phases

1. **RED.** Add the fixture constants to the mock, then write the spec. Run it: both tests fail on the state assertions, because no handler serves the fixtures yet.
2. **GREEN.** Add the request branches. POST a non-JSON body and a non-fixture body to each body branch and expect the catch-all's 404 both times. Run the spec and the existing `settings-kb-sync-held` and `nav-states-inbox-legal` specs.
3. **Mutation pass.** Commit, then apply each row of the Guard Contract as a temporary edit, confirm the expected result, and restore with `git restore`. Run every row from `apps/web-platform` on a fresh server with `CI=1 npx playwright test e2e/nav-states-scope-grants-web-egress.e2e.ts --project=authenticated --retries=0`: `CI=1` makes an occupied port a hard error instead of reusing another worktree's server, and a reused server would also keep its cached tenant client for 150 seconds. Do not use `git stash`. Record each row's mutation, expected result and observed result in `knowledge-base/project/specs/feat-one-shot-12605-scope-grants-phone-e2e/mutation-results.md` and commit it.
4. **Ship.** CI is the test gate. After merge, follow the release branch in the Acceptance Criteria.

## Non-Goals

- Fixing the clipped action-class id in `scope-grant-row.tsx`, or adding an all-ancestors overflow check, which is red until that fix lands. Tracked in #13018.
- Auditing `expectNoHorizontalScroll` in `settings-kb-sync-held.e2e.ts`. Recorded in #13018.
- Testing the `collection === true` dialog copy. It needs a new env var on the shared e2e server, and its text is contained in the "unknown" copy this spec renders.
- Proving tenant access. The mock does not enforce grants or RLS.
- Vertical clipping (ruling F8). The spec would not catch a future `line-clamp` or `max-h` wrapper on a disclosure. The confirm button's `scrollIntoViewIfNeeded()` check has the same blind spot, because that call also scrolls `overflow: hidden` containers a phone user cannot scroll.
- Any change to the approval-queue flag, production data, `docs/` or legal documents.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly, because only test code changes. A false-green spec would let a future change hide the push or `gh` disclosure from a workspace Owner on a phone before they turn on Agent web access.
- **If this leaks, the user's data is exposed via:** no vector. The fixtures are synthesized, the mock binds only to the local e2e run, and no production code or credential is touched.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** no shipped behaviour changes, so one failure cannot reach a user.
- `threshold: none, reason: the diff touches only the offline Playwright mock and one spec, neither of which is bundled into or executed by the production app.`

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** The CTO agent ruled on eight forks (see Technical Rulings), required the state-before-measure order and the fixture separation, and reviewed the plan for failure diagnosis.

The other seven domains were assessed against their questions and are not relevant: no copy, legal text, pricing, vendor, sales, finance or support surface changes. The Files lists match no UI-surface glob, so the Product/UX gate does not fire.

## Open Code-Review Overlap

None. No open `code-review` issue names `e2e/mock-supabase.ts`, `nav-states-` or `scope-grant-row`.

## Guard Contract

### Guard 1 — Scope Grants phone-width disclosure spec

**Property.** At 390x844, for every surface that renders the web-egress disclosures from real server state, all text stays within the viewport, the surface does not overflow, each disclosure is exactly one paragraph, and the dialog's confirm button is fully in the viewport and unobstructed.

**Assembly.** The disclosure constants have three render sites: the ON block and enable dialog in `components/settings/web-egress-toggle.tsx`, and the callout in `app/(dashboard)/dashboard/settings/scope-grants/page.tsx`. Every surface flows through `expectFitsPhone` and the paragraph check in the spec. To catch a fourth render site on this page, each test asserts `getByText(<constant>, { exact: true })` has the expected count for both constants: 2 when ON, 1 when OFF with the dialog closed, and 2 when OFF with the dialog open. A render on another route is outside this guard. The state reaches the page only through the mint path and `get_workspace_web_egress`, which reads the fixture's workspace row.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Merge `PUSH_DISCLOSURE` and `GH_DISCLOSURE` into one `<p>` in the dialog | RED |
| 2 | Dispatch: delete the mock's `/auth/v1/verify` branch, so the mint fails and the read falls closed to OFF | RED on the ON test's `aria-checked`, never a pass on an absent block |
| 3 | Second member: add `whitespace-nowrap` to `GH_DISCLOSURE` in the callout only, with the ON block compliant | RED, while the document check alone still reads 390 |
| 4 | Add `whitespace-nowrap` to the ON block's `PUSH_DISCLOSURE` paragraph | RED |
| 5 | Return `role: "member"` from the fixture's membership row | RED on the enabled-switch assertion |
| 6 | Render `GH_DISCLOSURE` in an extra `<p>` inside `#agent-web-access` | RED on the render count |
| 7 | Render `PUSH_DISCLOSURE` in a `<span>` outside `#agent-web-access` | RED on the render count |
| 8 | Position the confirm button off-screen with `fixed -top-24` | RED on `toBeInViewport` |
| 9 | Cover the confirm button with a `fixed inset-0 z-50` element | RED on the trial click |
| 10 | Flip the ON fixture's workspace row to `web_egress: false` | RED on `aria-checked` |
| 11 | Harness: change the Range filter to `r.width < 0`, so no rect is measured | RED on `count > 0` |
| 12 | Must pass: append a short extra `<p>` with unrelated text to the callout | GREEN, because the check does not pin the paragraph total |

**Anchor.** No stored value is compared. Expected disclosure copy is imported from the module the components render, so a disclosure wording change cannot break this spec; the unit suite pins that wording. The confirm button's label is a literal, and a change to it fails fast on `toBeVisible`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | [issue #12605] "The mock serves an Owner membership and a workspace row with `web_egress` true and false." | Mock design; `mock-supabase.ts` | mapped |
| 2 | [issue #12605] "A `nav-states-*` (or settings) e2e at 390x844 asserts the three checks above for the ON block, the dialog and the callout." | Spec design; new spec file | mapped |
| 3 | [brief] "no production writes" | Non-Goals; the spec never confirms the dialog and runs only against the offline mock | mapped |
| 4 | [brief] "don't touch the approval-queue flag" | Non-Goals; `playwright.config.ts` is not edited | mapped |
| 5 | [brief] "no edits under docs/ or legal docs" | Non-Goals; Files lists | mapped |
| 6 | [brief] "never ask the operator technical questions (route technical forks to soleur:engineering:cto)" | Technical Rulings | mapped |
| 7 | [brief] "CI is the test gate" | Implementation Phase 4; Acceptance Criteria | mapped |
| 8 | [brief] "if postmerge returns a release_failed verdict for this PR, comment on #12937 and do not emit DONE" | Post-merge Acceptance Criteria | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `e2e/mock-supabase.ts` fixtures and handlers | ask 1 | asked |
| Mint-path branches in the mock | — | inferred — justification: `resolveWebEgress` reads through the tenant mint, so ask 1's `web_egress` true cannot render without them (measured) |
| `e2e/nav-states-scope-grants-web-egress.e2e.ts` | ask 2 | asked |
| Per-surface text-rect check | — | inferred — justification: ask 2's document check cannot fail inside the clipping shell (measured), so the spec would otherwise pin nothing |
| Disclosure render count (`getByText` exact) | — | inferred — justification: one line per constant keeps the spec honest if a fourth surface renders a disclosure it does not measure |
| `notFound` stderr line and `aria-checked` message | — | inferred — justification: a mock fault otherwise reads only as `"false"`, because the server's cause never reaches the CI log |
| Follow-up issue #13018 | — | inferred — justification: `wg-when-an-audit-identifies-pre-existing` requires tracking the defect the probe found |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform`
- Planned files: 2 | Estimated changed lines: 200
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge

- [ ] `apps/web-platform/e2e/mock-supabase.ts` serves an Owner membership and workspace rows with `web_egress` true and false, for the two new fixture ids only.
- [ ] `apps/web-platform/e2e/nav-states-scope-grants-web-egress.e2e.ts` carries a `pyramid-justified:` marker and runs in the `authenticated` project at 390x844.
- [ ] The ON test asserts `aria-checked="true"` before measuring, then passes the document check, `expectFitsPhone` and the paragraph check for the ON block and callout.
- [ ] The OFF test asserts `aria-checked="false"` and an enabled switch, opens the dialog, then passes the same checks for the dialog and callout.
- [ ] The confirm button passes `scrollIntoViewIfNeeded()`, `toBeInViewport({ ratio: 1 })` and `click({ trial: true })`.
- [ ] Neither test performs a real confirm, and each ends with no page error and no "Something went wrong" heading.
- [ ] `knowledge-base/project/specs/feat-one-shot-12605-scope-grants-phone-e2e/mutation-results.md` has one row per Guard Contract mutation with its observed result, and `soleur:ship` copies that table into the final PR body.
- [ ] `git diff --name-only origin/main...HEAD` lists no file under `docs/`, no legal document and no production source. `playwright.config.ts` and `FLAG_APPROVAL_QUEUE` are unchanged.
- [ ] The CI `e2e` check is green, including the existing `settings-kb-sync-held` and `nav-states-inbox-legal` specs.
- [ ] The PR body uses `Closes #12605` and links #13018.

### Post-merge

- [ ] This merge triggers Web Platform Release, because its path filter includes `apps/web-platform/**`. Run `soleur:postmerge`, then read the deploy arm directly, because postmerge skips Phase 3.7 for this diff and its report would not print `release_failed`: run `bash plugins/soleur/scripts/deploy-arm.sh find --wait 25 <full-merge-sha>` and branch on its line:
  - **`MATCH=exact DEPLOY=blocked`:** get the job id with `gh run view <ARM> --json jobs --jq '.jobs[] | select(.name=="resolve-target") | .databaseId'`, then read `gh api repos/jikig-ai/soleur/check-runs/<id>/annotations --jq '.[].message'`. If it contains `[skip_reason=release_failed]`, comment on #12937 with the run link and do not emit DONE.
  - **`MATCH=descendant`:** do not attribute a failure to this PR or comment on #12937. Run `deploy-arm.sh served <full-merge-sha>` and report `CONTAINS` or `NOT_CONTAINED`. Do not emit DONE on `NOT_CONTAINED`.
  - **`ARM=none`, or rc 2 or 3:** report could-not-measure and do not emit DONE.

## Test Scenarios

All are `e2e` layer: jsdom cannot measure layout, and the unit suite already pins the text.

- Given an Owner with `web_egress` true, when the page opens at 390x844, then the switch is on and the ON block and callout fit, with each disclosure in its own paragraph.
- Given an Owner with `web_egress` false, when they tap the switch, then the dialog opens, it and the callout fit, and the confirm button is fully in the viewport and unobstructed.
- Given the mint path fails, when the page opens, then the ON test fails on `aria-checked` instead of passing on an absent block.
- Given a surface gains an unbreakable long string, when the spec runs, then `expectFitsPhone` fails although the document's `scrollWidth` stays 390.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- Running the dev server with a non-standard `NEXT_DIST_DIR` rewrites `apps/web-platform/tsconfig.json`. Use the standard Playwright config, and never commit that change.
- Do not import `expectNoHorizontalScroll` from the held-files spec. It reads only the document's width.
- Locally, `reuseExistingServer` adopts whatever already holds port 3100, including another worktree's server. Use the `CI=1` command in Phase 3 for any result you record.
- A POST branch that has awaited its body cannot fall through to the catch-all. Use `withJsonBody` with a synchronous `return`, so a throw cannot hang the request until the 180-second test timeout.

## References

- Issue #12605, follow-up #13018, release blocker #12937, draft PR #13017
- PR #12567 (owed this check), PR #12704 (added the mock's workspace branches)
