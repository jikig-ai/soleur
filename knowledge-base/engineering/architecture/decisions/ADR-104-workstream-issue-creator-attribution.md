# ADR-104: Workstream issue creator attribution (GitHub author + Soleur-bot detection + human-initiator marker)

- **Status:** accepted (Part A ships in this PR; Part B — the write-path
  initiator marker — lands as a follow-up, but the marker format + parser are
  decided here so the follow-up inherits the contract)
- **Date:** 2026-07-09
- **Deciders:** Operator; drafted via `/soleur:go` → plan → this ADR
- **Related:** ADR-097 (GitHub Project v2 board is the canonical issue-Status
  store), ADR-044 (workspace-repo ownership / installation-token chain +
  founder/authorship resolution), PR #5659 (Workstream tab reads real GitHub
  issues)

## Context

The Workstream tab (`/dashboard/workstream`, PR #5659) reads the connected
repo's issues and renders a kanban board. It shows the role assignee and an
optional assignee *person* (`WorkstreamIssue.user`), but **not who created the
issue**. The operator asked to see, per issue, whether it was created by a human
or by Soleur — and, for issues Soleur files on their behalf, to still see that
*they* initiated it ("show that I'm the one that initially made it, even though
it's Soleur that created the PR").

Two facts shaped the decision:

1. The GitHub issue **author** (`raw.user.login`) is already fetched by
   `github-read-tools.ts` but dropped by the board mapper (`toBoardInput`)
   before it reaches `lib/workstream.ts`. Surfacing it is a pure threading
   change — no new GitHub call.
2. When Soleur/Concierge creates an issue on a user's behalf, GitHub records the
   author as the **installation bot** (`soleur-ai[bot]`, slug-derived), never the
   human. So "who created it" from GitHub alone cannot attribute a Soleur-filed
   issue back to the initiating human — that requires stamping the initiator into
   the issue at creation time and parsing it back on read.

## Decision

1. **`creator` is a first-class, distinct field on `WorkstreamIssue`**, derived
   from the GitHub author login (`raw.user.login`). It is **never conflated with
   `user`** (the assignee person). Optional + additive: absent when the author
   login is unknown, so every pre-existing constructor stays valid.

2. **Soleur-bot detection is slug-derived, never a hardcoded login.** A login is
   the Soleur bot iff it case-insensitively equals `` `${slug}[bot]` `` where the
   slug comes from `getAppSlug()` (`GET /app`, env fallback `soleur-ai`). When the
   slug is unresolved the detector **biases to `false`** (renders the author as a
   plain human) — it deliberately does NOT fall back to a `login.endsWith("[bot]")`
   heuristic, which would misclassify `dependabot[bot]` / `renovate[bot]` as
   Soleur, the exact confusion this feature removes.

3. **The human initiator of a Soleur-created issue is attributed via a durable,
   machine-parseable issue-body marker** — a sibling of the shipped
   `<!-- soleur:<verb> … -->` HTML-comment family (`soleur:followthrough`,
   `soleur:auto-close-stale-scope-out`):

   ```
   <!-- soleur:initiated-by <login> -->
   ```

   Chosen over a visible trailer and over a GitHub label because: it is invisible
   in rendered markdown; carries no `@mention` (no spurious notification); carries
   no `closes`/`fixes` keyword (cannot trip GitHub autoclose); and mirrors an
   existing, tested parser shape. The write-side builder (`appendInitiatorMarker`)
   and the read-side parser (`parseInitiatorLogin`) are **single-sourced in the
   `lib/workstream.ts` leaf** off one `INITIATED_BY_MARKER` constant, so the
   byte-for-byte emit/parse contract cannot drift. The builder **unconditionally
   strips any pre-existing `soleur:initiated-by` marker** before appending the
   trusted one, and the parser takes the **last** occurrence — so a caller- or
   model-supplied fake marker can never win over the server-stamped value. The
   `initiatorLogin` is resolved from the session `userId` via
   `resolveGithubLogin` (authoritative GoTrue identity) and is **never** a tool or
   request argument.

4. **The write-path stamping chokepoint is the `createIssue` REST helper** (an
   additive optional `initiatorLogin?` param applying `appendInitiatorMarker`), so
   every issue-creation path funnels the marker through one place. **Re-scope
   (verified):** the operator's live Concierge (`soleur_go`) files issues via
   `gh issue create` over Bash, not via the `create_issue` tool, so Part B
   additionally requires wiring `create_issue` into the Concierge MCP toolset
   (promoting #3722) and redirecting the Concierge off raw `gh`. Part B therefore
   ships as a focused follow-up; Part A (this PR) delivers the human-vs-Soleur
   distinction independently.

## Consequences

- **Positive:** the board answers "who created this?" at a glance (a creator chip
  + a "Created by" detail row); the human-vs-Soleur distinction ships now with
  zero write-path dependency; the marker contract is decided and single-sourced,
  so the Part B follow-up is write-path-only. Fully additive and defensive — a
  missing author renders no chip, a bot slug that fails to resolve degrades to a
  plain author (mirrored to Sentry), and no board Status (ADR-097) derivation
  changes.
- **Negative / limits:** issues Soleur created **before** Part B ships have no
  marker and render plain "Soleur" (graceful, not backfilled). Email-signup users
  who connected a repo but never did GitHub-OAuth have no resolvable login, so
  their Soleur-created issues also render plain "Soleur" — this is the default for
  that user class, not an edge case. Part A observes attribution coverage via the
  read-side `creatorAttributionCoverage` log (`get-workstream-issues.ts`); the
  finer write-side `attribution_status` enum (`stamped | login-unresolved |
  path-not-instrumented`) that distinguishes this null-login case from a wiring
  gap lands with Part B.

## C4 impact

**No `.c4` edit required.** Following the ADR-044/097 precedent, issue authorship
and the Soleur bot are modelled in ADR prose, not as C4 elements:

- The only human actor near issue creation is the existing
  `founder = actor "Founder / Operator"` (`model.c4`); no dedicated "issue
  initiator" actor is introduced.
- The Soleur GitHub-App bot is **subsumed by the existing `github` external
  system** (ADR-044: "GitHub App (installation-token clone) is subsumed by the
  `github` external system — no new vendor").
- The attribution datum lives in the GitHub issue body, already reached by the
  existing `api -> github` edge. No store, actor, or relationship is added.

Promoting a first-class "Soleur GitHub-App bot" C4 element would be a separate
net-new decision requiring a `.c4` edit + `model.likec4.json` regeneration.

## Alternatives considered

- **Visible body trailer (`Initiated by @login`)** instead of an HTML comment —
  rejected: it renders as visible noise and the `@mention` fires a spurious
  GitHub notification. The HTML-comment marker family is the established Soleur
  convention.
- **A GitHub label (`initiated-by/<login>`)** — rejected: labels are a shared,
  low-cardinality namespace; per-user labels pollute it and are harder to keep
  authoritative than a server-stamped body marker.
- **`login.endsWith("[bot]")` bot heuristic** — rejected: misclassifies other
  bots (dependabot/renovate) as Soleur.
