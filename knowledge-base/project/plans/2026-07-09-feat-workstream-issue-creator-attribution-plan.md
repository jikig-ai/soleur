---
title: "feat: Workstream issue creator attribution (GitHub author + human initiator of Soleur-created issues)"
type: feat
date: 2026-07-09
branch: feat-one-shot-workstream-issue-creator-attribution
lane: cross-domain
brand_survival_threshold: none
adr: ADR-103 (provisional)
related:
  - PR #5659 (Workstream tab reads real GitHub issues — merged)
  - ADR-097 (GitHub Project v2 board canonical issue Status)
  - ADR-044 (Workspace repo ownership + founder/authorship resolution)
---

# feat: Workstream issue creator attribution

✨ Add "created by" attribution to the Workstream board so each issue shows **who created it**, distinguishing human-created issues from Soleur-created ones — and, when Soleur/Concierge creates an issue on a user's behalf, attribute it back to the **initiating human**.

## Overview

Two additive, defensive slices on top of the Workstream↔GitHub-issues backing shipped in PR #5659:

- **PART A — Display the GitHub issue author (read path).** The GitHub author (`raw.user.login`) is already fetched by `github-read-tools.ts` but dropped before it reaches the board model. Thread it through `BoardIssueInput → WorkstreamIssue.creator`, detect the Soleur GitHub-App bot author (slug-derived, never hardcoded), and render a "Created by" row in the detail sheet + a small creator indicator on the card. Column/Status derivation (ADR-097) is untouched.
- **PART B — Attribute the human initiator for Soleur-created issues (write path).** GitHub records the author of a Concierge/Soleur-created issue as the installation bot (`<slug>[bot]`). Stamp the initiating human into the issue body at creation time via a durable, machine-parseable marker; parse it on the read path so a bot-authored issue renders **"Soleur · initiated by \<you\>"** instead of just "Soleur". This is the operator's core want ("show that I'm the one that initially made it, even though it's Soleur that created the PR").

The whole feature is additive and degrades gracefully: pre-existing issues with no marker just show the GitHub author; a missing/unresolvable author renders no creator chip. Mirrors the existing DEFENSIVE mapping convention in `lib/workstream.ts` (never throws on missing fields).

### Motivation (operator, verbatim)
> "on the workstream, add who created the issue — if it is a user or just a Soleur issue that it created. E.g. I created a task to optimize static pages; I'd like the workstream to show that I'm the one that initially made it, even though it's Soleur that created the PR."

Operator explicitly chose the FULLER scope: display the GitHub author AND stamp/attribute the human initiator for Soleur-created issues (not just show the bot).

## Research Reconciliation — Spec vs. Codebase

All premise claims in the feature description were verified against `origin`-state code. Every cited artifact exists; the write-path chokepoint was NOT where the description guessed.

| Spec claim | Reality (verified) | Plan response |
| --- | --- | --- |
| `github-read-tools.ts` narrows author `IssueSummary.user = raw.user.login (~L143)` | Confirmed: `GhIssueResponse.user: GhUser {login}` (`github-read-tools.ts:87`, `GhUser` L72). But the board mapper is `toBoardInput()` (`github-read-tools.ts:320-332`), which maps 9 fields and **drops `item.user.login`**. There is no `IssueSummary` type in the board path. | Add `authorLogin` to `BoardIssueInput`; set it in `toBoardInput`. |
| `WorkstreamIssue.user` is the ASSIGNEE, not the creator | Confirmed: `deriveUser(assignees)` → first assignee (`lib/workstream.ts:342-346`). No creator/author field exists on `WorkstreamIssue` (`lib/workstream.ts:47-69`) or `BoardIssueInput` (`239-257`). | Add a NEW distinct `creator?` field; never conflate with `user`. |
| Body needed to parse initiator marker "just not threaded" | Confirmed BETTER than expected: `BoardIssueInput.body: string \| null` **is already threaded** (`toBoardInput` maps `item.body ?? null`). | PART B read-path parse needs NO new threading — parse `input.body`. |
| Write path: "search `workstream-tools.ts`, github-*write*, agent-runner issue-create tools" | The Workstream tool set is **READ-ONLY** (`workstream-tools.ts:6-7` header: "WRITE tools … are deferred"). The ONLY issue-create write path is the agent tool `create_issue` (`github-tools.ts:100-112`) → REST helper `createIssue` (`github-app.ts:1344-1389`, hand-rolled `POST /repos/{owner}/{repo}/issues`, not octokit). | Stamp the marker in the `create_issue` tool handler (`github-tools.ts:110`), the single chokepoint. |
| Soleur bot login — "find the real identity, do NOT hardcode" | The bot login is **slug-derived**: `getAppSlug()` (`github-app.ts:174-212`) resolves via `GET /app`; fallback env `NEXT_PUBLIC_GITHUB_APP_SLUG` defaulting to `"soleur-ai"`. Installation-token authorship attributes to `<slug>[bot]` → `soleur-ai[bot]` under default. NO `SOLEUR_BOT` constant, no hardcoded `[bot]` string anywhere. | Bot detection takes the slug as a parameter resolved server-side via `getAppSlug()`; the pure `lib/workstream.ts` helper stays a leaf. |
| Initiating human identity in the tool context | `create_issue`'s build opts (`BuildGithubToolsOpts`, `github-tools.ts:25-32`) carry NO user identity (no userId, login, or email). The session `userId` IS in agent-runner scope; the user row is loaded selecting only `email` (`agent-runner.ts:1074-1079`). The login resolver `resolveGithubLogin()` (`github-login.ts:41-75`) exists but agent-runner does not yet call it. | Resolve the login in agent-runner session setup; thread it into `BuildGithubToolsOpts`. |
| New Issue dialog creates optimistic local `SOLAA-N` cards; Concierge field disabled | Confirmed: `newIssueId()` → `SOLAA-N<seq>` (`new-issue-dialog.tsx:16-20`); `CONCIERGE_ONLINE = false` gate (`concierge-flag.ts`). Live creation path is the Concierge agent tool. | Focus initiator-stamping on `create_issue`; leave the local dialog untouched. |
| Feature relates to PR #5659 (merged), ADR-097 | Confirmed: PR #5659 MERGED 2026-06-26; ADR-097 status `adopting`. | Keep column/Status derivation untouched. |

**Premise Validation:** All cited GitHub refs resolve (PR #5659 merged). All cited file/symbol paths exist on-branch. The proposed *mechanism* (body marker for initiator) was grepped against the ADR corpus and the learnings — no ADR rejects a body-marker attribution; ADR-044's founder/authorship-resolution amendments resolve authorship for *webhook events* (a different surface) and set no policy against an issue-body initiator marker. No stale premises.

## User-Brand Impact

**If this lands broken, the user experiences:** a Workstream card/detail sheet showing the wrong or missing "Created by" attribution — e.g. their own human-initiated task rendered as an anonymous "Soleur" issue, or a bot-authored issue with no initiator. Cosmetic/attribution only; no data loss, no broken flow, board Status unaffected.

**If this leaks, the user's data is exposed via:** the only new persisted datum is the initiating human's **GitHub login** written into an issue body on **the user's own connected repo** (visible to that repo's collaborators, who already see the issue). No cross-tenant read/write, no new PII class, no credential. The initiator login is written only for issues Soleur creates for that same user.

**Brand-survival threshold:** none — reason: attribution writes a public GitHub login into an issue on the user's own connected repo; no cross-tenant, credential, money, or new-PII exposure. (Sensitive-path scope-out: the write path edits `apps/web-platform/server/*` but touches no schema/migration/auth/RLS surface — `threshold: none, reason: additive attribution marker in issue body on the user's own repo; no regulated-data or cross-tenant surface`.)

## Implementation Phases

Phases are ordered by dependency direction (contract before consumer). Everything is a single atomic PR; per-phase ordering matters for TDD.

### Phase 1 — Read-path pure model (`lib/workstream.ts`) — the leaf, tested first
1. Add `WorkstreamCreator` shape and a `creator?` field to `WorkstreamIssue` (kept optional + additive so every existing constructor stays valid, mirroring the `domains?` convention at `lib/workstream.ts:60-65`):
   ```ts
   export interface WorkstreamCreator {
     /** Raw GitHub author login, e.g. "octocat" or "soleur-ai[bot]". */
     login: string;
     /** True when the author is the Soleur GitHub-App bot. */
     isSoleur: boolean;
     /** Human initiator login parsed from the issue-body marker (PART B),
      *  present only for Soleur-authored issues that carry the marker. */
     initiatorLogin?: string;
     /** Display chip (initials) — the human author, the Soleur bot, or the
      *  initiator when known. Reuses the existing WorkstreamUser shape. */
     display: WorkstreamUser;
   }
   ```
2. Add `authorLogin?: string | null` to `BoardIssueInput` (`lib/workstream.ts:239-257`). NOTE: `body` is already present — the initiator parse needs no new field.
3. Add three PURE helpers (all defensive — never throw, null/false on missing/malformed input):
   - `isSoleurBotLogin(login: string | null | undefined, botSlug: string | null | undefined): boolean` — true when `login` case-insensitively equals `` `${botSlug}[bot]` ``. Defensive fallback: when `botSlug` is empty/unresolved, fall back to a conservative `login.endsWith("[bot]")` only if additionally the login stem matches a known-app shape — prefer returning `false` over a false-positive human-as-bot. (deepen-plan to finalize the fallback predicate.)
   - `parseInitiatorLogin(body: string | null | undefined): string | null` — extract the initiator login from the machine marker (format defined in Phase 3). Anchored regex, single capture, returns the bare login (no `@`) or null.
   - `deriveCreator(authorLogin: string | null | undefined, body: string | null | undefined, botSlug: string | null | undefined): WorkstreamCreator | undefined` — returns undefined when `authorLogin` is falsy (graceful: no chip). Sets `isSoleur = isSoleurBotLogin(...)`, `initiatorLogin = isSoleur ? parseInitiatorLogin(body) : undefined`, and `display` = initials of (initiatorLogin ?? a "Soleur" label ?? authorLogin). Reuse the `login.slice(0,2).toUpperCase()` initials rule from `deriveUser`.
4. Thread into `githubIssueToWorkstreamIssue` — widen its signature to accept the bot slug so it stays a pure leaf (no server import):
   ```ts
   export function githubIssueToWorkstreamIssue(
     input: BoardIssueInput,
     botSlug?: string | null,   // NEW, optional → back-compatible with all existing callers/tests
   ): WorkstreamIssue { … const creator = deriveCreator(input.authorLogin, input.body, botSlug);
       return { …, ...(creator ? { creator } : {}) }; }
   ```
   Keep `lib/workstream.ts` a React-free, `components/`-free leaf (matches its header contract, `lib/workstream.ts:1-13`).

### Phase 2 — Wire the author from the GitHub read payload (`github-read-tools.ts` + `get-workstream-issues.ts`)
1. `toBoardInput` (`github-read-tools.ts:320-332`): add `authorLogin: item.user?.login ?? null`. (`item.user` is `GhUser` — already narrowed at `github-read-tools.ts:87`.)
2. `server/workstream/get-workstream-issues.ts`: resolve the bot slug once per request via `getAppSlug()` (from `server/github-app.ts`) and pass it as the 2nd arg to `githubIssueToWorkstreamIssue(input, botSlug)`. Wrap in a defensive try/catch: on `getAppSlug()` failure, pass `undefined` → the issue simply renders the raw author as a human (no throw). The ADR-044 active-workspace resolution (membership-checked installation-token chain) stays the ONLY source of owner/repo/installation — NO change to tenant resolution.
3. Confirm the SWR response shape `{ issues: WorkstreamIssue[] }` (`workstream-board.tsx:45`) is unchanged — the new `creator` field flows through transparently, no route-shape change.

### Phase 3 — Write-path: stamp the initiator marker (`create_issue` chokepoint)
1. **Marker format (durable, machine-parseable, side-effect-free).** Append, as the LAST line of the issue body, an HTML comment:
   ```
   <!-- soleur:initiated-by <login> -->
   ```
   Rationale: (a) invisible in rendered GitHub markdown (no visual noise); (b) contains no `@mention` (no spurious GitHub notification to the initiator); (c) contains no close-keyword (`closes`/`fixes`) so it cannot trip GitHub autoclose — see learnings `2026-06-29-auto-closes-meta-content-…` and `2026-02-22-github-issue-auto-close-syntax`; (d) not a git trailer, so the contiguous-trailer-block constraint (`2026-05-16-git-trailer-parser-requires-contiguous-key-value-block`) does not apply — but the read-path regex MUST still be anchored and tolerant of trailing whitespace/newlines. `parseInitiatorLogin` matches `/<!--\s*soleur:initiated-by\s+([A-Za-z0-9](?:[A-Za-z0-9-]{0,38})?)\s*-->/` (GitHub login charset). **Alternative for deepen-plan/advisor to weigh:** a visible `Initiated by @<login> via Soleur` trailer (nicer for humans reading on GitHub, but creates an @mention notification). Default = HTML comment.
2. Add `initiatorLogin?: string | null` to `BuildGithubToolsOpts` (`github-tools.ts:25-32`).
3. In the `create_issue` tool handler (`github-tools.ts:110`), compose the body: `const body = appendInitiatorMarker(args.body, initiatorLogin);` where `appendInitiatorMarker` is a small pure helper (co-located, unit-tested) that returns `args.body` unchanged when `initiatorLogin` is falsy (graceful degrade) and otherwise appends `\n\n<marker>`. Pass the composed body to `createIssue(...)`. Do NOT modify `createIssue` in `github-app.ts` (it is reused by non-attributed callers).
4. **Idempotency/robustness:** `appendInitiatorMarker` must not double-stamp if the body already contains a marker (strip-then-append or no-op). deepen-plan to confirm.

### Phase 4 — Thread the initiating human's GitHub login into agent-runner
1. In agent-runner session setup, resolve the human login. Two options (deepen-plan to pick, precedent-diff against existing `resolveGithubLogin` callers in `app/api/repo/*`):
   - (a) Extend the user `.select()` at `agent-runner.ts:1077` to include `github_username`, and call `resolveGithubLogin(service, userId, user.github_username)` (`github-login.ts:41`) — the GoTrue-identity path is authoritative, stored `github_username` (migration `016`) is the fallback.
   - (b) If the service/admin client for the GoTrue path is not readily in scope, pass the stored `github_username` directly (weaker but simpler; login may be stale).
2. Thread the resolved login into the `buildGithubTools({ … })` call (`agent-runner.ts:1656-1663`) as `initiatorLogin`.
3. Defensive: if the login is unresolved (null), `initiatorLogin` is undefined → `appendInitiatorMarker` no-ops → the issue is created with no marker (renders as plain "Soleur"). No throw, no failed issue creation.

### Phase 5 — Render (components) — reuse existing chip/row primitives, ZERO new visual vocabulary
1. **Detail sheet** (`issue-detail-sheet.tsx`): add a `<Row label="Created by">` (via the local `Row` helper at `238-245`) immediately after the "User" row (`185-194`), mirroring its conditional pattern. Render `<UserAvatar user={issue.creator.display} />` + a label:
   - `creator.isSoleur && creator.initiatorLogin` → `"Soleur · initiated by <initiatorLogin>"`
   - `creator.isSoleur` (no initiator) → `"Soleur"`
   - human author → `creator.login`
2. **Card** (`issue-card.tsx`): append a small creator chip in the right-hand `gap-1` chip cluster (`46-49`), after the assignee `UserAvatar`. Reuse `<UserAvatar user={issue.creator.display} className="opacity-70" />` with a `title="Created by …"` to visually distinguish it from the assignee chip (both are gray initials chips — the `title` + opacity disambiguates; deepen-plan/UX to confirm the exact affordance, e.g. a leading glyph for the Soleur bot). No GitHub avatar-image dependency — the existing convention is initials-only chips (`assignee-chip.tsx`).
3. Import `WorkstreamCreator`/`WorkstreamIssue` from `@/lib/workstream` (existing import site); no new component files.

### Phase 6 — (nice-to-have, only if it fits cleanly) creator filter dimension
Add a `creators: Set<string>` dimension to `WorkstreamFilters` (`lib/workstream.ts:416-427`), `emptyFilters`, `matchesFilters` (`442-466`), `hasActiveFilters`, `FilterOptions` + `deriveFilterOptions` (`517-549`), and a `Dropdown`/`CheckRow` block in `filter-bar.tsx` mirroring the Domain block (`213-227`). The board threads `filterOptions`/`filters`/`onChange` generically — no `workstream-board.tsx` change beyond the type. **Cut this phase if it adds material surface;** the core want (Parts A+B) does not depend on it.

## Architecture Decision (ADR/C4)

This introduces a new cross-cutting **identity/attribution convention** (a machine-parseable issue-body initiator marker) and a **bot-identity detection** rule — an architectural decision, so the ADR is a deliverable of THIS plan, not a follow-up.

### ADR
- **Create ADR-103 (provisional ordinal)** via `/soleur:architecture`: "Workstream issue creator attribution — surface the GitHub author, detect the Soleur GitHub-App bot (slug-derived), and attribute the human initiator of bot-created issues via a durable issue-body marker." Decision records: (1) the `creator` field is derived from `raw.user.login`, distinct from the assignee; (2) bot detection is slug-derived (`getAppSlug()` + `[bot]`), never a hardcoded login; (3) the initiator marker format (`<!-- soleur:initiated-by <login> -->`) and its stamping chokepoint (`create_issue` tool). Alternatives to record: visible trailer vs HTML comment; metadata label vs body marker. Ordinal is provisional — `/ship` re-verifies against `origin/main`.

### C4 views
Checked all three model files — `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` — for the feature's external actors/systems/relationships:
- **External human actor (issue initiator):** the only human actor near issue creation is `founder = actor "Founder / Operator"` (`model.c4:8`, a workspace Owner). No dedicated "issue initiator" actor exists; ADR-044's precedent models issue authorship/initiator resolution in ADR **prose, not `.c4`** (every ADR-044 amendment carries a verbatim "C4 edge note: no `.c4` edit — below the model's granularity").
- **External system (Soleur GitHub-App bot):** NOT a distinct C4 element — ADR-044 states verbatim (L646) "GitHub App (installation-token clone) is subsumed by the `github` external system — no new vendor." The relevant edge already exists: `api -> github "Workstream tab: reads connected-repo issues (REST) + Project v2 board Status (GraphQL)…"` (`model.c4:361`).
- **Data store / access relationship:** no new store; the attribution datum lives in the GitHub issue body (already reached by the existing `api -> github` edge). No actor↔surface access relationship changes.

**Conclusion: no `.c4` edit required** — the human-initiator↔bot-authorship attribution follows the established ADR-044/097 precedent (prose in ADR-103, no C4 element/relationship additions). This "no C4 impact" is supported by the enumeration above (initiator actor = existing `founder`; Soleur bot = subsumed in `github`; edge = existing `api -> github`), not an unsupported "None". If a future decision promotes a first-class "Soleur GitHub-App bot" C4 element, that is a separate net-new decision requiring a `.c4` edit + `model.likec4.json` regen (pre-commit `c4-model-regenerate` hook; else `c4-model-freshness` test fails).

### Sequencing
The ADR describes the target state and ships in THIS PR's lifecycle (status `accepted` — the mechanism is live at merge, no soak gate).

## Observability

```yaml
liveness_signal:
  what: "get-workstream-issues request emits a structured field creatorAttributionCoverage = {withCreator, withInitiator, total} per board read"
  cadence: "per Workstream tab load (user-interactive)"
  alert_target: "none (informational — attribution is cosmetic, not a liveness-critical path)"
  configured_in: "apps/web-platform/server/workstream/get-workstream-issues.ts (existing structured log for the board read)"
error_reporting:
  destination: "Sentry via the existing get-workstream-issues error boundary + reportSilentFallback for the getAppSlug() degrade"
  fail_loud: "getAppSlug() failure is a SILENT graceful degrade (author renders as human) — mirror via reportSilentFallback so the degrade is observable without breaking the board"
failure_modes:
  - mode: "getAppSlug() fails/times out → bot not detected, Soleur issues render as human author"
    detection: "reportSilentFallback op:'workstream-botslug-degrade' emitted from get-workstream-issues.ts"
    alert_route: "Sentry (informational; no page)"
  - mode: "resolveGithubLogin() returns null in agent-runner → issue created without initiator marker"
    detection: "structured log line from the create_issue path noting marker-skipped=true with reason"
    alert_route: "Sentry breadcrumb (informational)"
  - mode: "marker present but malformed → parseInitiatorLogin returns null, renders plain 'Soleur'"
    detection: "unit-test coverage of parseInitiatorLogin malformed cases; runtime is a silent graceful degrade by design"
    alert_route: "none (expected graceful path)"
logs:
  where: "Sentry (server) + pino structured logs from get-workstream-issues + create_issue handler"
  retention: "existing Sentry/log retention — no new store"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/workstream-helpers.test.ts test/server/workstream/get-workstream-issues.test.ts"
  expected_output: "green — asserts creator threading, bot detection, and initiator-marker parse; NO ssh required"
```

## Test Scenarios

Add node-unit tests for the new PURE mappers alongside the existing `lib/workstream` tests. The vitest node project collects `test/**/*.test.ts` + `lib/**/*.test.ts` (`apps/web-platform/vitest.config.ts:44`); existing pure-mapper tests live in `apps/web-platform/test/workstream-helpers.test.ts` — extend that file (do NOT co-locate under `components/`, which vitest never collects).

- **`isSoleurBotLogin`**: `("soleur-ai[bot]", "soleur-ai") → true`; case-insensitive variant → true; `("octocat", "soleur-ai") → false`; `("soleur-ai[bot]", null) → conservative` (per finalized fallback); `(null, "soleur-ai") → false`.
- **`parseInitiatorLogin`**: valid marker → login; marker with surrounding whitespace/trailing newline → login; no marker → null; malformed (`@`-prefixed, spaces) → null; body `null` → null.
- **`deriveCreator`**: human author → `{login, isSoleur:false, initiatorLogin:undefined}`; bot author + valid marker → `{isSoleur:true, initiatorLogin:'harry'}`; bot author no marker → `{isSoleur:true, initiatorLogin:undefined}`; falsy authorLogin → undefined.
- **`githubIssueToWorkstreamIssue`** author threading: input with `authorLogin` + `botSlug` → `creator` set; input WITHOUT `authorLogin` (existing callers) → no `creator` (back-compat, no throw); `botSlug` omitted → treats author as human.
- **`appendInitiatorMarker`** (write-path helper): login present → body + marker; login falsy → body unchanged; body already has a marker → no double-stamp.
- **Server wiring** (`test/server/workstream/get-workstream-issues.test.ts`, `test/server/github-read-tools.workstream.test.ts`): `authorLogin` flows from `toBoardInput`; `getAppSlug()` failure degrades gracefully (author rendered as human, no throw).
- **Component** (`test/components/workstream/issue-detail-sheet.test.tsx`, `issue-card.test.tsx`): "Created by" row/chip renders the three label variants; absent `creator` renders nothing.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `WorkstreamIssue.creator?: WorkstreamCreator` exists and is distinct from `WorkstreamIssue.user` (assignee); grep confirms `deriveUser` is unchanged.
- [ ] `BoardIssueInput.authorLogin` is set by `toBoardInput` from `item.user.login`; `git grep -n "authorLogin" apps/web-platform/server/github-read-tools.ts` returns the assignment.
- [ ] `githubIssueToWorkstreamIssue` accepts an optional `botSlug` 2nd arg; ALL pre-existing call sites/tests compile without change (`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean).
- [ ] `create_issue` stamps `<!-- soleur:initiated-by <login> -->` when an initiator login is threaded; omits it (unchanged body) when not — asserted by `appendInitiatorMarker` unit tests.
- [ ] Bot detection is slug-derived via `getAppSlug()` — `git grep -nE '"soleur\[bot\]"|SOLEUR_BOT' apps/web-platform` returns nothing (no hardcoded bot login).
- [ ] New pure-mapper tests (isSoleurBotLogin, parseInitiatorLogin, deriveCreator, author-threading, appendInitiatorMarker) pass: `cd apps/web-platform && ./node_modules/.bin/vitest run test/workstream-helpers.test.ts` green.
- [ ] Detail sheet renders "Created by" with the three label variants; card renders a distinct creator chip; both degrade to nothing when `creator` absent (component tests green).
- [ ] `lib/workstream.ts` imports nothing from `components/` or React (leaf invariant preserved).
- [ ] ADR-103 (provisional) authored; "no C4 impact" conclusion cites the actor/system/edge enumeration; `.c4` files unedited (so no `model.likec4.json` regen needed).
- [ ] Column/Status derivation (`deriveColumn`, ADR-097 board preference) is byte-unchanged — `git diff` on that region is empty.
- [ ] ADR-044 active-workspace resolution in `get-workstream-issues.ts` is the ONLY owner/repo/installation source (no new tenant-resolution code).

## Domain Review

**Domains relevant:** Engineering (Product — advisory)

### Engineering
**Status:** reviewed (inline)
**Assessment:** Cross-cutting read+write change across `lib/workstream.ts` (pure leaf), `github-read-tools.ts`, `get-workstream-issues.ts`, `github-tools.ts`, `agent-runner.ts`, and two components. Risk is contained: all changes additive/optional; the leaf stays React-free; the write path is a single chokepoint; tenant resolution untouched. Key engineering decisions (marker format, bot-detection fallback, login-resolution path) are flagged for deepen-plan precedent-diff. No schema/migration/RLS surface.

### Product/UX Gate
**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** ux-design-lead (reason: the render change reuses the EXISTING `UserAvatar` chip and `Row` primitives verbatim — it introduces NO new visual component, layout, or interactive surface, only a new data binding into existing components; per the ADVISORY definition "modifies existing components without adding new interactive surfaces". No `.pen` warranted because zero new visual vocabulary is introduced.)
**Pencil available:** N/A (no new UI surface — verbatim primitive reuse)

#### Findings
The card already renders a gray `UserAvatar` initials chip for the assignee; the creator chip is the same primitive. The only UX nuance is disambiguating two gray chips on a dense card — addressed via `title` + reduced opacity (and optionally a leading glyph for the Soleur bot), to be confirmed at implementation. Detail-sheet "Created by" row uses the existing `Row` helper.

## Open Code-Review Overlap

None — checked open `code-review` issues for the six target files; no open scope-out names `lib/workstream.ts`, `github-read-tools.ts`, `get-workstream-issues.ts`, `github-tools.ts`, `issue-detail-sheet.tsx`, or `issue-card.tsx`. (deepen-plan to re-run the `gh issue list --label code-review` grep against the finalized file list.)

## Files to Edit
- `apps/web-platform/lib/workstream.ts` — `WorkstreamCreator`, `WorkstreamIssue.creator`, `BoardIssueInput.authorLogin`, `isSoleurBotLogin`, `parseInitiatorLogin`, `deriveCreator`, widen `githubIssueToWorkstreamIssue`; (Phase 6) filter dimension.
- `apps/web-platform/server/github-read-tools.ts` — `toBoardInput` sets `authorLogin`.
- `apps/web-platform/server/workstream/get-workstream-issues.ts` — resolve `getAppSlug()`, pass `botSlug` to the mapper (defensive).
- `apps/web-platform/server/github-tools.ts` — `initiatorLogin` in `BuildGithubToolsOpts`; `appendInitiatorMarker` in the `create_issue` handler.
- `apps/web-platform/server/agent-runner.ts` — resolve human login (`resolveGithubLogin`/`github_username`), thread into `buildGithubTools`.
- `apps/web-platform/components/workstream/issue-detail-sheet.tsx` — "Created by" row.
- `apps/web-platform/components/workstream/issue-card.tsx` — creator chip.
- `apps/web-platform/components/workstream/filter-bar.tsx` — (Phase 6, optional) creator filter block.
- `apps/web-platform/test/workstream-helpers.test.ts` — new pure-mapper tests.
- `apps/web-platform/test/server/workstream/get-workstream-issues.test.ts`, `apps/web-platform/test/server/github-read-tools.workstream.test.ts` — wiring/degrade tests.
- `apps/web-platform/test/components/workstream/issue-detail-sheet.test.tsx`, `issue-card.test.tsx` — render tests.

## Files to Create
- `knowledge-base/engineering/architecture/decisions/ADR-103-*.md` — the attribution ADR (ordinal provisional).

## Non-Goals / Deferred
- Persisting the New Issue dialog's optimistic `SOLAA-N` cards or enabling the disabled "Create with Concierge" field (out of scope; gated by `CONCIERGE_ONLINE`, PR #5659).
- A first-class "Soleur GitHub-App bot" C4 element (net-new decision; not required here).
- Real GitHub avatar images (existing convention is initials-only chips; introducing image loading is a separate change).
- Backfilling initiator markers onto issues Soleur created BEFORE this ships (they render as plain "Soleur" — graceful).

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This section is filled with `threshold: none` + reason.
- `parseInitiatorLogin` must be anchored + whitespace-tolerant (the marker is the last line, may have a trailing newline). Test the trailing-newline case explicitly.
- `isSoleurBotLogin` fallback (when `getAppSlug()` degrades) must bias toward false — a false-positive "human is the bot" mislabels a real user's issue as Soleur, the exact confusion the feature removes. deepen-plan to finalize the conservative fallback predicate.
- `appendInitiatorMarker` must not double-stamp; and the marker must NOT contain any `closes/fixes #N` text (would trip GitHub autoclose — learning `2026-06-29-auto-closes-meta-content-…`).
- Two gray initials chips on one card (assignee + creator) risk visual ambiguity — disambiguate via `title` + opacity (+ optional glyph), confirmed at implementation.
