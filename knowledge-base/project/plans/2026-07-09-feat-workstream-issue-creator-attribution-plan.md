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

## Enhancement Summary

**Deepened on:** 2026-07-09
**Passes:** precedent-diff (4.4), verify-negative (4.45), 4 review agents (Kieran / architecture-strategist / security-sentinel / spec-flow-analyzer), ux-design-lead wireframe (Phase 4.9).

### Load-bearing correction from review (VERIFIED P0 — see Research Reconciliation)
Kieran + spec-flow independently found that the feature description's premise ("the only issue-create path is `create_issue`") is FALSE for the operator's live surface: the Command Center Concierge (`soleur_go`, the default for all new conversations) files issues via `gh issue create` over Bash, NOT via `create_issue`/`createIssue`. **Part B was re-scoped accordingly** — a Phase-0 mechanism decision (recommended: wire `create_issue` into the cc MCP server, #3722), an end-to-end AC (not a unit-test proxy), and a recommendation to ship Part A independently while Part B lands as a follow-up. Persisted as a decision-challenge for operator sign-off (`specs/feat-…/decision-challenges.md`).

### Key precedent findings (fold into implementation)
1. **The marker mechanism is ALREADY an established Soleur convention — mirror it, don't invent.** Soleur issue-body markers use the `<!-- soleur:<verb> ... -->` HTML-comment family with a canonical parser: `parsePredicateYaml` (`apps/web-platform/server/inngest/functions/_predicate-validator.ts:206`, regex `/<!--\s*soleur:followthrough\s+([\s\S]*?)-->/`) and the sentinel `<!-- soleur:auto-close-stale-scope-out -->` (`cron-stale-deferred-scope-outs.ts:86`). Adopt `<!-- soleur:initiated-by <login> -->` as a sibling of this family and mirror the parser shape. This resolves the "least-hacky durable mechanism" choice decisively in favor of the HTML comment (the visible-trailer alternative is dropped).
2. **The Soleur bot identity is confirmed and testable:** login `soleur-ai[bot]`, bot user id **273333864** (`test/cla-evidence/allowlist.test.ts:45-46`, #5520). `isAllowlistBypass("soleur-ai[bot]", 273333864, …)` already encodes it. Consider narrowing `GhUser` to also carry `id: number` so `isSoleurBotLogin` can prefer the **numeric bot id** (durable across a slug rename) with the `<slug>[bot]` string as the fallback — more robust than a pure string compare. (deepen/work to decide; string-compare via `getAppSlug()` remains the minimum.)
3. **The initiator-login threading is clean — no new client plumbing.** agent-runner already holds a service client: `serviceClient: supabase()` (`agent-runner.ts:1734`). Resolve the login by mirroring the shipped repo-route call `resolveGithubLogin(serviceClient, user.id, userData?.github_username)` (`app/api/repo/setup/route.ts:147`) — the authoritative GoTrue identity with stored `github_username` as fallback. Extend the user `.select()` at `agent-runner.ts:1077` to include `github_username`.

✨ Add "created by" attribution to the Workstream board so each issue shows **who created it**, distinguishing human-created issues from Soleur-created ones — and, when Soleur/Concierge creates an issue on a user's behalf, attribute it back to the **initiating human**.

## Overview

Two additive, defensive slices on top of the Workstream↔GitHub-issues backing shipped in PR #5659:

- **PART A — Display the GitHub issue author (read path).** The GitHub author (`raw.user.login`) is already fetched by `github-read-tools.ts` but dropped before it reaches the board model. Thread it through `BoardIssueInput → WorkstreamIssue.creator`, detect the Soleur GitHub-App bot author (slug-derived, never hardcoded), and render a "Created by" row in the detail sheet + a small creator indicator on the card. Column/Status derivation (ADR-097) is untouched.
- **PART B — Attribute the human initiator for Soleur-created issues (write path).** GitHub records the author of a Concierge/Soleur-created issue as the installation bot (`soleur-ai[bot]`). Stamp the initiating human into the issue body at creation time via a durable, machine-parseable marker (`<!-- soleur:initiated-by <login> -->`); parse it on the read path so a bot-authored issue renders **"Soleur · initiated by \<you\>"** instead of just "Soleur". This is the operator's core want ("show that I'm the one that initially made it, even though it's Soleur that created the PR"). **CRITICAL re-scope (verified P0):** the operator's live Concierge does NOT file issues via the `create_issue` tool — it files via `gh issue create` over Bash. So stamping only at `create_issue`/`createIssue` fails for the exact motivating flow. Part B therefore requires a write-path mechanism decision (Phase 0) — the durable path wires `create_issue` into the Concierge's MCP toolset (promoting #3722) and redirects it off raw `gh`, so issue creation funnels through `createIssue` where the marker lives.

**Shipping strategy:** Part A is **self-contained and ships independently** — it already delivers the operator's "human vs Soleur" distinction (a Soleur-authored issue renders "Soleur"; a human one renders the human login) with zero write-path dependency. Part B (the "initiated by \<you\>" refinement) depends on the cc-runtime wiring decision and MAY split into a follow-up PR after Part A lands. The whole feature is additive and degrades gracefully: pre-existing/`gh`-created issues with no marker render plain "Soleur"; a missing/unresolvable author renders no creator chip. Mirrors the DEFENSIVE mapping convention in `lib/workstream.ts` (never throws).

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
| Write path: "the ONLY issue-create path is the `create_issue` agent tool" (feature-description premise) | **FALSE for the operator's live surface — verified.** Two runtimes exist: (A) legacy `startAgentSession` (agent-runner.ts:881) which builds `create_issue`→`createIssue` REST helper; (B) the Command Center **Concierge** (`soleur_go`), which ALL new conversations route to (`ws-handler.ts:1653` seeds `soleur_go_pending`; `:2255` breaks to `dispatchSoleurGoForConversation` BEFORE the legacy branch). Path B registers an **empty MCP allowlist** (`readCcMcpAllowlist()` returns `{}`, `cc-dispatcher.ts:291`; only narrate/summarize) — so `create_issue` is NOT in the Concierge toolset. Instead cc-dispatcher mints an installation token and **injects it as `GH_TOKEN`** (`cc-dispatcher.ts:110`) so the agent files issues via **`gh issue create` over Bash** — bypassing `createIssue` (TS) entirely. The `soleur-go-runner.ts:177-185` prompt directive to "file via the gated create_issue tool" is a **dangling reference to a tool the runner never wires**. | Part B is **re-scoped** (Kieran P1 + spec-flow P0, both verified). The live path files via `gh` CLI → stamping at `createIssue` alone would NEVER fire for the operator. See re-scoped Part B below: Phase 0 resolves the mechanism; the durable fix wires `create_issue` into the cc `soleur_platform` MCP server (promotes #3722) + redirects the Concierge off raw `gh`, funneling through `createIssue` where the marker is centralized. Part A ships independently. |
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

### Phase 0 — Resolve the Part B write-path mechanism (REQUIRED, gating; verified P0)
The live Concierge (Path B / `soleur_go`) files issues via `gh issue create` over Bash (GH_TOKEN-authed, `cc-dispatcher.ts:110`), NOT via `create_issue`. So Part B needs a mechanism decision before implementation. Confirm and choose:
1. **Confirm the live mechanism.** Verify (already established at plan time, re-confirm at /work) that a Concierge "file me a task" request results in a `gh issue create` Bash call, not a `create_issue` MCP call — check `cc-dispatcher.ts` MCP allowlist (`readCcMcpAllowlist` → `{}`) and the GH_TOKEN injection. Confirm the legacy `startAgentSession` path (which DOES build `create_issue`) is reachable for directed leader sessions and carries the operator's `userId`.
2. **Choose the write-path mechanism (recommended = A):**
   - **(A) Wire `create_issue` into the cc `soleur_platform` MCP server** (promote the #3722 Phase-2 hook that already conditionally builds the server for narrate/summarize) AND update the Concierge system prompt (`soleur-go-runner.ts:177-185`) to file via `create_issue` instead of raw `gh` (fix the dangling directive). Then issue creation funnels through `createIssue` (TS) → marker stamped centrally. This is the durable, agent-native path (also gives the operator the permission-gated affordance the prompt already promises). Cost: touches cc MCP wiring (#3722 territory) — may warrant its own PR.
   - **(B) Stamp at the `gh` boundary** — inject the marker into the Concierge's prompt directive so it appends `<!-- soleur:initiated-by <login> -->` to the `gh issue create --body`. Rejected as PRIMARY: model-composed `gh` commands are unreliable (spec-flow P0); acceptable only as an interim.
3. **Output:** the chosen mechanism + the definitive list of issue-creation sites that must thread `initiatorLogin`. If ANY runtime cannot resolve the operator's `userId`, Part B degrades to plain "Soleur" there (no throw).

**Given the scope of (A), the recommended delivery is: ship Part A now; land Part B (mechanism A) as a focused follow-up PR** once the cc-MCP `create_issue` wiring is scoped. The plan keeps both parts documented so the follow-up inherits this analysis.

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
   - `isSoleurBotLogin(login: string | null | undefined, botSlug: string | null | undefined): boolean` — true when `login` case-insensitively equals `` `${botSlug}[bot]` ``. **When `botSlug` is empty/unresolved → return `false`** (firm, per architecture P2.2): do NOT fall back to `login.endsWith("[bot]")`, which would misclassify `dependabot[bot]`/`renovate[bot]` as Soleur — the exact confusion this feature removes. `getAppSlug()` self-falls-back to `"soleur-ai"` internally and never throws (`github-app.ts:179-211`), so `botSlug` is only empty in the rare hard-fetch-rejection path; biasing to `false` there renders the author as a plain login, which is safe. (Confirmed real bot login: `soleur-ai[bot]`, id 273333864.)
   - `parseInitiatorLogin(body: string | null | undefined): string | null` — extract the initiator login from the machine marker (format defined in Phase 3). Anchored regex, single capture, returns the bare login (no `@`) or null.
   - `deriveCreator(authorLogin: string | null | undefined, body: string | null | undefined, botSlug: string | null | undefined): WorkstreamCreator | undefined` — returns undefined when `authorLogin` is falsy (graceful: no chip). Sets `isSoleur = isSoleurBotLogin(...)`, `initiatorLogin = isSoleur ? parseInitiatorLogin(body) : undefined`, and `display` = initials of (initiatorLogin ?? a "Soleur" label ?? authorLogin). Reuse the `login.slice(0,2).toUpperCase()` initials rule from `deriveUser`.
   - `appendInitiatorMarker(body: string | null | undefined, login: string | null | undefined): string` — the WRITE-side builder, **co-located in the leaf with the parser** so the emit/parse contract is single-sourced (architecture P1: split modules can silently drift → every Soleur issue renders un-attributed, the exact failure the feature removes). Server→lib is the correct dependency direction, so `github-tools.ts` importing this from the leaf preserves the leaf invariant. Behavior per Phase 3.4 (unconditional strip + last-wins). Export a single `INITIATED_BY_MARKER` format constant that BOTH the builder and `parseInitiatorLogin` consume, so the byte-for-byte contract cannot drift.
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
   **This is a sibling of the shipped `<!-- soleur:followthrough … -->` / `<!-- soleur:auto-close-stale-scope-out -->` marker family** — mirror `parsePredicateYaml`'s parser shape (`_predicate-validator.ts:206`). Rationale: (a) invisible in rendered GitHub markdown (no visual noise); (b) contains no `@mention` (no spurious GitHub notification to the initiator); (c) contains no close-keyword (`closes`/`fixes`) so it cannot trip GitHub autoclose — see learnings `2026-06-29-auto-closes-meta-content-…` and `2026-02-22-github-issue-auto-close-syntax`; (d) not a git trailer, so the contiguous-trailer-block constraint (`2026-05-16-git-trailer-parser-requires-contiguous-key-value-block`) does not apply — but the read-path regex MUST still be anchored and tolerant of trailing whitespace/newlines. `parseInitiatorLogin` matches `/<!--\s*soleur:initiated-by\s+([A-Za-z0-9](?:[A-Za-z0-9-]{0,38})?)\s*-->/` (GitHub login charset). **SPOOF DEFENSE (security):** a user- or agent-supplied `body` could already contain a fake `<!-- soleur:initiated-by someone-else -->`. Mitigate two ways: (i) `appendInitiatorMarker` STRIPS any pre-existing `soleur:initiated-by` marker from the incoming body before appending the trusted one (server controls the last write); (ii) `parseInitiatorLogin` matches the **LAST** occurrence (`match` over a global scan, take final). The spoof blast-radius is low (issue on the user's OWN repo) but the strip+last-wins makes the server-stamped value authoritative. The visible-trailer alternative is DROPPED (marker-family precedent + no @mention wins).
2. **Centralize stamping at the REST helper `createIssue` (`github-app.ts:1344`)** — add an ADDITIVE optional last param `initiatorLogin?: string | null`; internally `const finalBody = appendInitiatorMarker(body, initiatorLogin)` (imported from `@/lib/workstream` — server→lib, leaf-safe) before `JSON.stringify`. This is the single chokepoint EVERY `create_issue` tool variant (legacy + Concierge, per Phase 0) funnels through. **Reconciles the architecture reviewer's "don't modify `createIssue`" with Kieran's multi-runtime P1:** the param is additive and defaults to a no-op — non-attributed callers pass nothing and get an unchanged body (with the unconditional stray-marker strip still applied, Phase 3.4) — while it guarantees coverage that a single per-builder tool handler cannot (the Concierge runtime does not share `buildGithubTools`).
3. Add `initiatorLogin?: string | null` to `BuildGithubToolsOpts` (`github-tools.ts:25-32`); the `create_issue` handler (`github-tools.ts:110`) passes it as the new `createIssue(..., initiatorLogin)` arg. Repeat for any cc-path `create_issue` builder Phase 0 identifies.
4. **Idempotency + spoof defense (security P1 — REQUIRED):** `appendInitiatorMarker(body, login)` must **strip ALL pre-existing `soleur:initiated-by` markers UNCONDITIONALLY** — before the falsy-login early-return, not only when appending. This closes the degrade-path hole (login resolution fails → `login` falsy → a user/agent-smuggled fake marker in `body` would otherwise pass through unstripped and render "Soleur · initiated by \<attacker-chosen\>"). Order: `stripped = body.replace(/<!--\s*soleur:initiated-by[\s\S]*?-->/g, "")`; if `login` falsy → return `stripped`; else return `stripped + "\n\n" + marker`. `initiatorLogin` is baked into the tool closure from the session `userId` (never an LLM/tool arg), so the model cannot set the attribution directly — it can only smuggle via `body`, which the unconditional strip neutralizes. Unit-test: `(bodyWithFakeMarker, null) → marker removed`; `(bodyWithFakeMarker, "harry") → only the real trailing marker remains`.

### Phase 4 — Thread the initiating human's GitHub login into agent-runner
1. In agent-runner session setup, resolve the human login via the AUTHORITATIVE path (security P1 — REQUIRED). agent-runner holds a service client (`serviceClient: supabase()`, `agent-runner.ts:1734`), so mirror the shipped repo-route call `resolveGithubLogin(serviceClient, user.id, userData?.github_username)` (`app/api/repo/setup/route.ts:147`, `github-login.ts:41`): the GoTrue provider identity is authoritative and NOT user-mutable; stored `github_username` (migration `016`) is the fallback. Extend the user `.select("email")` at `agent-runner.ts:1077` to `.select("email, github_username")`. Pass the SERVICE client (not the tenant `sessionTenant`) — `auth.admin.getUserById` requires it. Do NOT read the login from `user_metadata` or any tool argument.
   - **Coverage caveat (spec-flow P1):** `users.github_username` is written ONLY by the GitHub-resolve OAuth callback (`app/api/auth/github-resolve/callback/route.ts:149`), NOT by installing the App to connect a repo. An email-signup user who connected a repo but never did GitHub-OAuth resolves to the GoTrue path only; if they have no GitHub identity, login is `null` → their Soleur-created issues render plain "Soleur" (unattributed). This is the DEFAULT for that user class, not an edge case — state it in the plan and cover it with the liveness signal below (distinguish "login unresolved" from "path not exercised").
2. Thread the resolved login into EVERY issue-creation builder Phase 0 identified: the `buildGithubTools({ … })` call (`agent-runner.ts:1656-1663`) as `initiatorLogin`, AND the Concierge/cc-path `create_issue` builder (`soleur-go-runner.ts`/`cc-dispatcher.ts` session setup — both have the operator `userId` and a service client in scope). Each runtime resolves the login the same way (step 1).
3. Defensive: if the login is unresolved (null), `initiatorLogin` is undefined → `appendInitiatorMarker` no-ops (but still strips stray markers) → the issue is created with no marker (renders as plain "Soleur"). No throw, no failed issue creation.

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
  what: "get-workstream-issues emits a NET-NEW structured info log creatorAttributionCoverage = {withCreator, withInitiator, total} per board read (this function has NO success-path log today — the instrumentation is added by this change, not pre-existing)"
  cadence: "per Workstream tab load (user-interactive)"
  alert_target: "none (informational — attribution is cosmetic, not a liveness-critical path)"
  configured_in: "apps/web-platform/server/workstream/get-workstream-issues.ts (new pino info line added by this PR)"
error_reporting:
  destination: "Sentry via the existing get-workstream-issues error boundary + reportSilentFallback for the getAppSlug() degrade"
  fail_loud: "getAppSlug() failure is a SILENT graceful degrade (author renders as human) — mirror via reportSilentFallback so the degrade is observable without breaking the board"
failure_modes:
  - mode: "getAppSlug() fails/times out → bot not detected, Soleur issues render as human author"
    detection: "reportSilentFallback op:'workstream-botslug-degrade' emitted from get-workstream-issues.ts"
    alert_route: "Sentry (informational; no page)"
  - mode: "resolveGithubLogin() returns null (email-signup user, no GitHub identity, no github_username) → issue created without initiator marker"
    detection: "structured log at the issue-creation site with attribution_status enum: 'stamped' | 'login-unresolved' | 'path-not-instrumented' — distinguishes the common null-login case from a wiring gap (spec-flow P1)"
    alert_route: "Sentry breadcrumb (informational)"
  - mode: "Concierge files via gh CLI on a path Part B did not instrument → no marker (the P0 this re-scope fixes)"
    detection: "the end-to-end AC + attribution_status='path-not-instrumented' if any uninstrumented site remains after Phase 0"
    alert_route: "Sentry (informational); caught pre-merge by the end-to-end AC"
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

### Part A — read path (ships independently)
- [ ] `WorkstreamIssue.creator?: WorkstreamCreator` exists and is distinct from `WorkstreamIssue.user` (assignee); grep confirms `deriveUser` is unchanged.
- [ ] `BoardIssueInput.authorLogin` is set by `toBoardInput` from `item.user.login`; `git grep -n "authorLogin" apps/web-platform/server/github-read-tools.ts` returns the assignment.
- [ ] `githubIssueToWorkstreamIssue` accepts an optional `botSlug` 2nd arg; ALL pre-existing call sites/tests compile without change (`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean).
- [ ] Bot detection is slug-derived via `getAppSlug()`; `isSoleurBotLogin` returns `false` on empty slug (no `endsWith("[bot]")` heuristic). `git grep -nE '"soleur[_-]?ai\[bot\]"|SOLEUR_BOT' apps/web-platform/lib apps/web-platform/server` returns nothing (no hardcoded bot login in the mapper/read path).
- [ ] New pure-mapper tests (isSoleurBotLogin, parseInitiatorLogin, deriveCreator, author-threading) pass: `cd apps/web-platform && ./node_modules/.bin/vitest run test/workstream-helpers.test.ts` green.
- [ ] Detail sheet renders "Created by" with the three label variants; card renders a distinct creator chip; both degrade to nothing when `creator` absent (component tests green). Render matches the committed wireframe `knowledge-base/product/design/workstream/creator-attribution.pen`.
- [ ] `lib/workstream.ts` imports nothing from `components/` or React (leaf invariant preserved).
- [ ] `git grep -n dangerouslySetInnerHTML apps/web-platform/components/workstream/issue-detail-sheet.tsx apps/web-platform/components/workstream/issue-card.tsx apps/web-platform/components/workstream/assignee-chip.tsx` returns nothing (login rendered as escaped text only).
- [ ] `deriveColumn` / ADR-097 board Status derivation is byte-unchanged (`git diff` on that region empty); ADR-044 active-workspace resolution in `get-workstream-issues.ts` remains the ONLY owner/repo/installation source (no new tenant-resolution code).
- [ ] ADR-103 (provisional) authored documenting the attribution decision; `.c4` files unedited (so no `model.likec4.json` regen needed).

### Part B — write path (with the Phase-0 mechanism; may be a follow-up PR)
- [ ] `appendInitiatorMarker` + `parseInitiatorLogin` + the `INITIATED_BY_MARKER` format constant all live in `lib/workstream.ts` (single-sourced emit/parse contract). `appendInitiatorMarker` strips ALL pre-existing `soleur:initiated-by` markers unconditionally (spoof defense); `parseInitiatorLogin` returns the LAST occurrence — unit tests cover `(fakeMarkerBody, null) → stripped` and `(fakeMarkerBody, "harry") → real marker wins`.
- [ ] `initiatorLogin` is derived from the session `userId` via `resolveGithubLogin(serviceClient, …)` (authoritative GoTrue identity) and is NEVER a tool/request argument.
- [ ] **END-TO-END (not a proxy):** driving the ACTUAL Concierge issue-creation path (per Phase-0 mechanism) for a user with a resolved login produces a GitHub issue whose body contains exactly one `<!-- soleur:initiated-by <login> -->` marker, and the Workstream read renders "Soleur · initiated by <login>". (An `appendInitiatorMarker` unit test ALONE is insufficient — it passed while the live path never called the handler.)
- [ ] `git grep -n "create_issue" apps/web-platform/server/soleur-go-runner.ts` — the dangling directive is either backed by a wired `create_issue` tool (mechanism A) or removed/updated to match the actual mechanism (no prompt referencing a tool the runtime does not provide).

## Domain Review

**Domains relevant:** Engineering (Product — advisory)

### Engineering
**Status:** reviewed (inline)
**Assessment:** Cross-cutting read+write change across `lib/workstream.ts` (pure leaf), `github-read-tools.ts`, `get-workstream-issues.ts`, `github-tools.ts`, `agent-runner.ts`, and two components. Risk is contained: all changes additive/optional; the leaf stays React-free; the write path is a single chokepoint; tenant resolution untouched. Key engineering decisions (marker format, bot-detection fallback, login-resolution path) are flagged for deepen-plan precedent-diff. No schema/migration/RLS surface.

### Product/UX Gate
**Tier:** blocking (mechanical UI-surface override — plan edits `components/workstream/*.tsx`)
**Decision:** reviewed; wireframe produced, headless async-review (pipeline — no pause)
**Agents invoked:** ux-design-lead
**Skipped specialists:** none
**Pencil available:** yes
**Wireframe (committed `.pen`):** `knowledge-base/product/design/workstream/creator-attribution.pen` (commit `e99fe26c6`) + high-res exports `screenshots/06-creator-attribution-issue-card.png`, `screenshots/07-creator-attribution-detail-sheet.png`. Wireframes ready for async operator review; the pipeline does not pause (headless arm).

#### Findings
The wireframe confirms the render design (Phase 5): (1) **card** — the NEW creator chip reuses the gray initials chip at **60% opacity** with a **leading person/bot glyph** and a `title="Created by …"` tooltip, disambiguating it from the assignee chip; human-created card shows `[👤 HA]`, Soleur-created shows `[🤖 Soleur]`. (2) **detail sheet** — a NEW "Created by" `Row` inserted directly after "User", rendering the operator's core want `🤖 Soleur · initiated by harry`, with the three label variants (`Soleur · initiated by <login>` / `Soleur` / human login). Both frames passed layout validation. Phase 5 implements exactly this.

## Open Code-Review Overlap

None — checked open `code-review` issues for the six target files; no open scope-out names `lib/workstream.ts`, `github-read-tools.ts`, `get-workstream-issues.ts`, `github-tools.ts`, `issue-detail-sheet.tsx`, or `issue-card.tsx`. (deepen-plan to re-run the `gh issue list --label code-review` grep against the finalized file list.)

## Files to Edit
- `apps/web-platform/lib/workstream.ts` — `WorkstreamCreator`, `WorkstreamIssue.creator`, `BoardIssueInput.authorLogin`, `isSoleurBotLogin`, `parseInitiatorLogin`, `deriveCreator`, widen `githubIssueToWorkstreamIssue`; (Phase 6) filter dimension.
- `apps/web-platform/server/github-read-tools.ts` — `toBoardInput` sets `authorLogin`.
- `apps/web-platform/server/workstream/get-workstream-issues.ts` — resolve `getAppSlug()`, pass `botSlug` to the mapper (defensive).
- `apps/web-platform/server/github-app.ts` — `createIssue` gains additive optional `initiatorLogin?`; applies `appendInitiatorMarker` (the centralized chokepoint).
- `apps/web-platform/server/github-tools.ts` — `initiatorLogin` in `BuildGithubToolsOpts`; `create_issue` handler passes it to `createIssue`.
- `apps/web-platform/server/agent-runner.ts` — extend user `.select("email, github_username")` (:1077); resolve login via `resolveGithubLogin(serviceClient, …)`; thread into `buildGithubTools` (:1656).
- `apps/web-platform/server/cc-dispatcher.ts` — (Part B, mechanism A) wire `create_issue` into the cc `soleur_platform` MCP server (promote #3722 hook) + thread `initiatorLogin`; `apps/web-platform/server/soleur-go-runner.ts` — fix the dangling `create_issue` prompt directive (:177-185) to match the wired tool. Exact sites per Phase 0.
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
- `parseInitiatorLogin` is a FREE (non-line-anchored) scan that returns the LAST `soleur:initiated-by` occurrence — honestly acknowledged: it can match a marker inside a fenced code block. This is acceptable because it only runs on `isSoleur` (bot-authored) bodies, which are Soleur-controlled, and `appendInitiatorMarker` unconditionally strips strays so the real trailing marker wins. Test the trailing-newline case AND the code-fence case to document the behavior. (Do NOT claim "anchored" in the code comment — match the honest behavior.)
- `isSoleurBotLogin` fallback (when `getAppSlug()` degrades) must bias toward false — a false-positive "human is the bot" mislabels a real user's issue as Soleur, the exact confusion the feature removes. deepen-plan to finalize the conservative fallback predicate.
- `appendInitiatorMarker` must not double-stamp; and the marker must NOT contain any `closes/fixes #N` text (would trip GitHub autoclose — learning `2026-06-29-auto-closes-meta-content-…`).
- Two gray initials chips on one card (assignee + creator) risk visual ambiguity — disambiguate via `title` + opacity (+ optional glyph), confirmed at implementation.
