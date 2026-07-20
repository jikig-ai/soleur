# ADR-109: Workstream issue writes — close-not-delete + label-driven status + audited App-token write seam

- **Status:** accepted (v1 ships Create / title / label-driven status / close-reopen from the board + matching gated MCP tools; the org-board GraphQL Status mirror for intermediate columns is grant-gated future work)
- **Date:** 2026-07-10
- **Deciders:** Operator; drafted via `/soleur:go` → plan → this ADR. Domain: Engineering (CTO); Product/UX (CPO — write-integrity is non-negotiable at the single-user brand threshold).
- **Related:** ADR-044 (per-workspace installation resolution — owner/repo/installation never request input), ADR-097 (the Project v2 board is the canonical Status store for the dogfood org repo), ADR-104 (`<!-- soleur:initiated-by <login> -->` creator marker), ADR-067 (SWR data-cache vs Router-Cache reconcile), PR-H+1 #4098 (`createGitHubAppClient` audit seam / `audit_github_token_use`, Art. 30 PA-16). Closes #5677 (agent write parity). Feature: feat-workstream-issue-crud (#6304).

> **Ordinal.** Provisional at plan time; verified next-free against `origin/main` at author time (highest merged is ADR-108). Re-verify at ship — the collision window is the whole pipeline (see ADR-108's ordinal note); sweep the plan + tasks + ACs if renumbered.

## Context

The Workstream tab reads real GitHub issues (PR #5659) but every write was a fake, local-only optimistic stub that reset on reload: the New Issue dialog didn't persist, the drawer's status control didn't save, and the agent had read-only parity (`workstream_issues_list`) but could not create or advance issues (#5677). A founder using Soleur as their work surface had to drop to GitHub to manage work. Brand-survival threshold: single-user incident — a board that silently lies about persisted work, or a spoofable creator attribution / cross-tenant write, is the failure class.

Two seams already existed and are load-bearing: (1) `createGitHubAppClient(installationId, founderId)` (`server/github/app-client.ts`) returns an Octokit whose every `.rest.*` call writes one `audit_github_token_use` row via after/error hooks — the ONLY audited path; the older `createIssue` in `github-app.ts` uses a naked `generateInstallationToken()` that writes NO audit row. (2) `deriveColumn` (`lib/workstream.ts`) already derives a card's column from issue labels + state.

## Decision

**Route ALL Workstream issue writes through one shared server accessor (`server/workstream/mutate-workstream-issue.ts`) that uses the audited `createGitHubAppClient(installationId, founderId).rest.issues.*` seam, resolves owner/repo/installation only from the active workspace (ADR-044), and returns the canonical re-derived `WorkstreamIssue`. The HTTP routes AND the gated MCP tools call this ONE accessor.**

1. **Audited seam only.** Writes go through `createGitHubAppClient(installationId, userId)` so each call writes an `audit_github_token_use` row (`founderId` = session user id). No naked `generateInstallationToken()` write path is added. Writes are a higher-value PA-16 audit target than reads.

2. **Close-not-delete.** GitHub cannot truly delete an issue without irreversible admin GraphQL that destroys the number-keyed board. "Delete" = `rest.issues.update {state:"closed", state_reason}`; reopen = `{state:"open"}`. There is **no Cancelled column** — the board (`lib/workstream.ts`) folds every closed issue to `done`, so BOTH close reasons (completed / not_planned) land the card in Done; the reason is recorded on GitHub and shown in the drawer. Reopen leaves Done and lands in the column its surviving labels derive (else Backlog). (This corrects the spec's "Not planned → Cancelled".)

3. **Status = labels, via ONE atomic primitive.** `setIssueStatus(number, targetColumn, state_reason?)`: `done` → close (state); any non-terminal column → read-modify-write = GET current labels, then ONE atomic `rest.issues.setLabels` PUT of the full computed set `(currentLabels − STATUS_LABELS) + targetWriteLabel` (a closed issue is also reopened). No remove-then-add delta — a remove-2xx-then-add-fail would leave a wrong Backlog the rollback can't see. "Atomic" is the PUT; the surrounding RMW keeps a TOCTOU last-write-wins window, accepted at the single-user threshold.

4. **Single-sourced status-label vocabulary.** `STATUS_LABELS` (the removal set) + `STATUS_WRITE_LABEL` (canonical write-label per column) live next to `deriveColumn` in `lib/workstream.ts`. `STATUS_LABELS` MUST equal exactly the labels `deriveColumn`'s open branch reads; a test asserts write-set ≡ read-set so derive and write can never drift (mirrors the `INITIATED_BY_MARKER` single-source pattern).

5. **Server-resolved attribution, never request input.** owner/repo/installation resolve from the active workspace; `initiatorLogin` resolves server-side via `resolveGithubLogin` and `appendInitiatorMarker` strips any smuggled marker so the trusted stamp wins. A login/owner/repo in the request body is ignored.

6. **Agent-user parity.** Every UI write verb ships as a gated in-process MCP tool (`workstream_issue_create` / `_set_status` / `_update_title` / `_close`) delegating to the SAME accessor (tier `gated` in `tool-tiers.ts`; the host review gate is the founder-confirmation surface). No `gh` shell-out.

7. **Write-integrity (single-user threshold).** Optimistic UI commits only after GitHub's response; the client reconciles from the returned canonical issue by mutating the SWR board key (ADR-067 — not `router.refresh()` alone) and rolls back with a retryable surface on failure. Create is submit-disabled with a single-flight guard (no double-fire duplicate) + empty-title block (client + server 422). A 403 (read-only install) flips the board read-only with an honest hint (no retry loop); a 429 (secondary rate-limit) is a distinct slow-down state.

8. **Board-precedence drag-disable (dogfood only).** For `owner === SOLEUR_KANBAN_ORG` the Project board Status WINS over labels on read, and the label→board mirror workflow needs `organization_projects:write` (still ungranted) — so an intermediate label move would 403-fail-loud and snap back on next read. Intermediate-column moves are therefore disabled for the org repo **while the grant is absent** (gated on `SOLEUR_KANBAN_PROJECT_WRITABLE`, which lifts the disable automatically once granted), never as a permanent trigger gap. Close/reopen always work (state changes mirror). A user's OWN repo never reads the board → fully live.

## Accepted skew / limits

- **App vs board precedence skew (durable, survives the grant).** The app `deriveColumn` ranks `in-progress > ready/todo`; the board `recompute_issue` (`set-board-status.sh`) ranks `ready/todo > in-progress` and lets an open (draft) PR cross-reference override labels. An issue with competing signals can settle to a different board column than the app's optimistic label-derived column even after the grant. This is documented + accepted here (single-user, self-correcting on next board read) rather than reconciled in v1.
- **Optimistic concurrency (P1-4)** — last-write-wins on the setLabels RMW; acceptable at one operator + their agent. **Realtime agent-write→open-board push (P1-5)** — none in v1; the board reflects agent writes on next load/SWR revalidation.
- **Lost-ack create dedup (P0-1).** The client single-flight + submit-disable prevent the common double-fire duplicate; a true dropped-ack server-side dedup on the initiator marker is deferred.

## Rejected alternatives

- **(a) GraphQL `deleteIssue`** — rejected: irreversible, destroys the number-keyed board; Close covers the need.
- **(b) Naked `github-app.ts` write helpers on `generateInstallationToken()`** — rejected: unaudited (no `audit_github_token_use` row); writes are the higher-value PA-16 target.
- **(c) Direct Project v2 board Status GraphQL write from the web app** — rejected: blocked on the pending `organization_projects:write` grant; labels are canonical for a user's own repo and the `board-status-sync` webhook mirrors to the board.
- **(d) Remove-then-add label delta** — rejected: a half-fail leaves a wrong Backlog the rollback can't see; the single atomic `setLabels` PUT eliminates it.
- **(e) Accepting owner/repo/initiatorLogin from the request body** — rejected: cross-tenant write + attribution-spoof vector; all resolve server-side.
