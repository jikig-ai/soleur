# Feature map — apps/web-platform

User-POV inventory of every navigable route in `app/`. Consumers: `test-browser`, `qa`, `ux-audit`, `reproduce-bug` — navigate by feature (route → selectors → expected outcome → gotchas) instead of re-deriving file→route mappings at runtime. Auth and fixture detail for the audited subset lives in `plugins/soleur/skills/ux-audit/references/route-list.yaml`; this map cross-references it rather than re-encoding it.

**Update contract:** adding, renaming, or deleting an `app/**/page.tsx` requires an edit to this file (or to `## Deliberately unmapped`) in the SAME PR. `scripts/lint-feature-map-coverage.sh` checks both directions: a route with no entry reds, an entry with no route reds (tombstone), an entry missing the `- selectors:`/`- expects:` field bullets reds, a route classified in both sets reds, and a fenced code block anywhere in the file reds (a `## \`/route\`` line inside a fence would count as a real entry — the file documents fields with inline backticks). The check is advisory in CI today (`lint-bot-statuses` — absent from `scripts/required-checks.txt`). <!-- markdownlint-disable-line MD038 -->

**Entry conventions:** `entry` names how an agent reaches the route (nav link, direct URL, redirect). `selectors` prefer `data-testid` values, then `getByRole`/`getByText` anchors — the same vocabulary `e2e/nav-states-shell.e2e.ts` uses. `expects` is the user-POV outcome, not an implementation detail. `auth` is `anonymous` (no session) | `bot` (the ux-audit bot fixture: T&Cs accepted, billing active) | `admin` (operator role-gated). Dynamic segments stay literal (`[conversationId]`, `[...path]`, `[token]`) — the map documents the route shape, not a concrete id.

## `/`

- route: `/`
- entry: direct URL
- selectors: post-redirect anchors — `Sign in to Soleur` heading on `/login` (anonymous), `workspace-context-band` on `/dashboard` (authenticated)
- expects: anonymous → middleware 307 to `/login`; authenticated → server redirect to `/dashboard`
- auth: anonymous
- gotchas: not in `PUBLIC_PATHS`, so the middleware auth gate runs before `app/page.tsx`'s own `redirect("/dashboard")`; there is no landing page to screenshot

## `/login`

- route: `/login`
- entry: direct URL, or any auth-gated route while anonymous
- selectors: `Sign in to Soleur` heading, `placeholder="you@example.com"`, `data-testid="revoked-banner"` (conditional)
- expects: sign-in form renders; valid magic-link/GitHub sign-in lands on `/dashboard`
- auth: anonymous
- gotchas: `?erasure=pending` renders the account-deleted notice (`role="alert"`) above the form; the `dev` environment also mounts `DevSignInPanel`

## `/signup`

- route: `/signup`
- entry: direct URL or link from `/login`
- selectors: `Create your account` heading, `data-testid="tc-hint"`
- expects: signup form renders; completing signup lands on the T&C acceptance step (`/accept-terms`)
- auth: anonymous
- gotchas: the `tc-hint` element is the terms-acceptance affordance — do not look for a separate checkbox page before signup

## `/accept-terms`

- route: `/accept-terms`
- entry: redirect — middleware routes authenticated users with an unsigned/outdated T&C version here
- selectors: `Accept Terms & Conditions` heading, `data-testid="tc-version-update-banner"` (on version bumps)
- expects: terms page renders; accepting returns the user to their destination (`?next=` or `/dashboard`)
- auth: bot
- gotchas: `TC_EXEMPT_PATHS` keeps this route reachable without a signature; accepting writes the current `TC_VERSION` — re-runs need a user whose signature lags the current version

## `/dashboard`

- route: `/dashboard`
- entry: rail nav home, direct URL, or post-login landing
- selectors: `data-testid="workspace-context-band"`, `data-testid="conversations-rail"`, `data-testid="foundation-section-shimmer"`, `data-testid="disconnected-orphans-hint"`, `data-testid="first-run-attachment-label"`
- expects: dashboard shell renders — left rail with conversations, workspace identity band, and the first-run checklist/foundation sections
- auth: bot
- gotchas: the context band mounts twice (mobile top-bar + rail variant) — scope identity assertions to `[data-variant="rail"]` or they resolve to two elements

## `/dashboard/chat`

- route: `/dashboard/chat`
- entry: rail nav → chat, or direct URL
- selectors: `data-testid="chat-index-resume"`, `data-testid="conversations-rail"`
- expects: soft-redirects to `/dashboard/chat/new`; a resumable sticky conversation id resumes instead of redirecting
- auth: bot
- gotchas: index route only — a dead sticky id is cleared and replaced to `/new` (#4826 AC10), so asserting the bare URL after render is timing-sensitive; assert `chat-index-resume` state instead

## `/dashboard/chat/[conversationId]`

- route: `/dashboard/chat/[conversationId]`
- entry: click a row in `conversations-rail`, or direct URL with a real conversation id
- selectors: `data-testid="connection-banner"`, `data-testid="connection-resumed"`, `data-testid="connection-unrecoverable"`, `data-testid="routing-chip"`
- expects: `ChatSurface` renders the thread — message history, composer, connection state; `?context=<path>` preloads a KB context, `?mode=crm-lead` sets lead context
- auth: bot
- gotchas: a non-resumable or deleted id soft-replaces to `/new` rather than 404ing; the `context` query beats `mode` when both are present

## `/dashboard/inbox`

- route: `/dashboard/inbox`
- entry: rail nav → inbox, or direct URL
- selectors: `Inbox` heading, `aria-label="Archive email"`, `aria-label="Acknowledge email"`, `aria-label="Message Concierge"`
- expects: `InboxSurface` renders — inbound email list with archive/acknowledge actions and the concierge message box
- auth: bot
- gotchas: an unauthenticated hit redirects to `/login` server-side; list rows are keyed on real inbound email — empty-state copy appears when none seeded

## `/dashboard/inbox/email/[emailId]`

- route: `/dashboard/inbox/email/[emailId]`
- entry: click an email row in the inbox list
- selectors: email detail surface (subject/body thread), archive/acknowledge controls shared with the inbox list
- expects: single-email view renders for a live id; `notFound()` for an id outside the user's scope
- auth: bot
- gotchas: needs a seeded inbound email — with no fixture the only reachable state is the 404, not the detail surface

## `/dashboard/kb`

- route: `/dashboard/kb`
- entry: rail nav → Knowledge Base link, or direct URL
- selectors: `data-testid="kb-rail-tree"`, `data-testid="kb-tree-scrollport"`, `data-testid="kb-rail-resize-handle"`, `data-testid="kb-page-mobile-header"`
- expects: KB tree renders in the rail/sidebar; the page body itself is intentionally empty (tree lives in `layout.tsx`)
- auth: bot
- gotchas: `page.tsx` renders `<></>` — the real content is the layout sidebar, so assertions target the rail, not `main`; without a connected repo the tree shows the empty/deferred state (`kb_workspace_deferred` in route-list.yaml)

## `/dashboard/kb/[...path]`

- route: `/dashboard/kb/[...path]`
- entry: click a document node in `kb-rail-tree`, or direct URL with a KB-relative path
- selectors: `data-testid="kb-rail-tree"`, `data-testid="kb-content-download"`, `data-testid="kb-header-overflow-menu"`, `data-testid="kb-content-skeleton-row"`
- expects: document view renders the file's content in the workbench with download and overflow actions
- auth: bot
- gotchas: catch-all — any unmatched depth under `/dashboard/kb/` lands here; content loading shows `kb-content-skeleton-row` first, so assertions must wait for the real document

## `/dashboard/workstream`

- route: `/dashboard/workstream`
- entry: rail nav → workstream, or direct URL
- selectors: `aria-label="Workstream status"`, `aria-label="New issue"`, `placeholder="Issue title"`, `aria-label="Search issues"`
- expects: `WorkstreamBoard` renders — issue columns/cards with status, assignee, label, and milestone editing
- auth: bot
- gotchas: board state is repo- and milestone-dependent; an unauthenticated hit redirects to `/login` server-side

## `/dashboard/audit`

- route: `/dashboard/audit`
- entry: rail nav → audit, or direct URL
- selectors: `data-testid="audit-github-link"`
- expects: audit landing renders with the GitHub audit entry point
- auth: bot
- gotchas: the surface is a hub — the GitHub-app audit detail lives one level down at `/dashboard/audit/github`

## `/dashboard/audit/github`

- route: `/dashboard/audit/github`
- entry: `audit-github-link` from `/dashboard/audit`, or direct URL
- selectors: `data-testid="gh-audit-empty"`
- expects: GitHub audit surface renders — installation/repo audit state, or the `gh-audit-empty` empty state when nothing is connected
- auth: bot
- gotchas: without a connected GitHub installation the only reachable state is `gh-audit-empty` — do not assert populated audit rows without a fixture

## `/dashboard/billing`

- route: `/dashboard/billing`
- entry: direct URL only
- selectors: post-redirect anchors — `Settings` heading and `settings-rail-nav` on `/dashboard/settings`
- expects: redirects to `/dashboard/settings` (billing lives under settings)
- auth: bot
- gotchas: redirect route — no content of its own; keep the `/dashboard/settings` entry current or this route's expectation lies

## `/dashboard/releases`

- route: `/dashboard/releases`
- entry: rail nav → releases, or direct URL
- selectors: `Releases` heading, `data-testid="releases-skeleton"` (loading), `aria-label="Search releases"`, `aria-label="Filter by release type"`, `aria-label="Sort releases"`
- expects: `ReleasesSurface` renders — release list with search, type filter, and sort
- auth: bot
- gotchas: `releases-skeleton` is the loading state — wait for it to detach before asserting list content

## `/dashboard/routines`

- route: `/dashboard/routines`
- entry: rail nav → routines, or direct URL
- selectors: `data-testid="routine-detail-drawer"`, `data-testid="run-detail-panel"`, `data-testid="runs-filter-routine"`, `data-testid="runs-filter-trigger"`, `data-testid="confirm-run"`, `aria-label="Routine detail"`, `aria-label="Run protected routine"`
- expects: `RoutinesSurface` renders — routine list, per-routine detail drawer, run history with filters
- auth: bot
- gotchas: `cmd-routines-empty`/`cmd-routines-error` are the empty/error states; a protected routine asks confirmation before firing (`confirm-run`)

## `/dashboard/crm`

- route: `/dashboard/crm`
- entry: rail nav → crm, or direct URL
- selectors: `aria-label="CRM view"`, `aria-label="Loading contact"`, `aria-label="Loading funnel"`, `No contacts yet` empty heading
- expects: `CrmSurface` renders — contact/funnel view for beta-CRM, or the `No contacts yet` empty state
- auth: bot
- gotchas: `mode=crm-lead` on a chat route is the write path into this list — a contact created via chat surfaces here

## `/dashboard/admin/analytics`

- route: `/dashboard/admin/analytics`
- entry: direct URL (no nav link for non-admin users)
- selectors: `data-testid="analytics-loading"` (loading), analytics charts when the role gate passes
- expects: admin analytics renders for the operator role; non-admin users redirect to `/dashboard`, anonymous to `/login`
- auth: admin
- gotchas: role-gated — the ux-audit bot cannot reach it (route-list.yaml excludes it for exactly this reason); assert the redirect for a non-admin session, the surface only with an admin fixture

## `/dashboard/settings`

- route: `/dashboard/settings`
- entry: rail nav → settings, or direct URL
- selectors: `Settings` heading, `data-testid="settings-rail-nav"`, `aria-label="Settings"`, `data-testid="workspace-name"`, `data-testid="workspace-logo-settings"`, `data-testid="agent-engine-settings"`
- expects: `SettingsContent` renders — sections for workspace identity (logo, name), agent engine, API key, account, project, danger zone
- auth: bot
- gotchas: `settings-rail-nav` is the secondary-nav slot — subroutes share this shell; the workspace-logo control states (`workspace-logo-status-*`) are upload-transient

## `/dashboard/settings/billing`

- route: `/dashboard/settings/billing`
- entry: `settings-rail-nav` → billing
- selectors: `Billing` section heading, `data-testid="billing-escalation"`, `aria-label="Daily cap in dollars"`
- expects: billing settings render — plan/usage, daily cap control, escalation surface
- auth: bot
- gotchas: `/dashboard/billing` (no `settings/` prefix) is a redirect here — assert the settings URL, not the legacy one

## `/dashboard/settings/conversation-names`

- route: `/dashboard/settings/conversation-names`
- entry: `settings-rail-nav` → conversation names
- selectors: `ConversationNamesSettingsContent` surface, `Domain Leaders` heading, team-names provider controls
- expects: conversation-name settings render — the names the agent team is addressed by
- auth: bot
- gotchas: wraps `TeamNamesProvider` — edits propagate to the rail's leader names, so a rename here changes rail labels elsewhere

## `/dashboard/settings/privacy`

- route: `/dashboard/settings/privacy`
- entry: `settings-rail-nav` → privacy
- selectors: privacy section content — data-retention/export and erasure controls
- expects: privacy settings render — DSAR export and account-deletion affordances
- auth: bot
- gotchas: the delete-account flow hard-navigates to `/login?erasure=pending` (ADR-067) — verification of erasure state reads the login notice, not a settings banner

## `/dashboard/settings/scope-grants`

- route: `/dashboard/settings/scope-grants`
- entry: `settings-rail-nav` → scope grants
- selectors: scope-grant section content — per-scope grant/revoke controls
- expects: scope-grant settings render — OAuth/agent scope grants with revoke affordances
- auth: bot
- gotchas: revoking a grant has downstream agent effects (agent-runner scope checks) — assert the grant row state, not just the click

## `/dashboard/settings/services`

- route: `/dashboard/settings/services`
- entry: `settings-rail-nav` → services
- selectors: `Connected Services` heading, `ConnectedServicesContent` surface
- expects: connected-services settings render — GitHub/other service connection state
- auth: bot
- gotchas: `cmd-kb-reconnect` is the reconnect affordance when the repo link is broken — the same control the settings page's `needsReconnect` logic surfaces

## `/dashboard/settings/team`

- route: `/dashboard/settings/team`
- entry: `settings-rail-nav` → team
- selectors: `Team` heading, `Members` section heading, `Funded for Others` section
- expects: team settings render — workspace members list and invite affordances
- auth: bot
- gotchas: `notFound()` fires for users without the team surface's prerequisites — a solo-workspace bot may legitimately 404; check `route-list.yaml`'s coverage notes before asserting

## `/dashboard/settings/team-activity`

- route: `/dashboard/settings/team-activity`
- entry: `settings-rail-nav` → team activity
- selectors: `Team Activity` heading
- expects: team-activity feed renders — member actions/audit entries for the workspace
- auth: bot
- gotchas: activity is seeded only by prior member actions — an empty feed is a valid state, not a render failure

## Deliberately unmapped

Routes below are real `page.tsx` routes deliberately excluded from feature entries. Each exemption records its reason; the lint requires both the bullet and the reason, and treats a route in both sets as a contradiction.

- `/setup-key` — onboarding-only API-key step; transient funnel page, not a working surface (route-list.yaml excludes it for the same reason)
- `/connect-repo` — onboarding-only repo-connection step; transient funnel page, not a working surface
- `/internal/github-app-init` — internal GitHub App install/callback bootstrap (`internal/` is a literal segment, not a route group); redirects authenticated users onward and is not a user-navigable feature
- `/shared/[token]` — public share-link surface; requires a valid share token, so the only anonymous-reachable state without a fixture is the invalid-token path (route-list.yaml exclusion)
- `/invite/[token]` — invite-acceptance surface; requires a valid invite token, so the only reachable state without a fixture is the invalid-invite path
