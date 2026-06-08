---
title: "Shared documents return 'Document not found' for users provisioned after the ADR-044 relocation"
date: 2026-06-08
incident_pr: feat-fix-share-popup-copy-overflow
incident_window: "unknown start (ADR-044 read-path cutover) → 2026-06-08"
recovery_at: "2026-06-08 (fix merged)"
suspected_change: "ADR-044 users→workspaces relocation: the share CREATE path migrated to the workspace_id-keyed KB resolver, but the share READ path (/api/shared/[token]) and previewShare were never migrated."
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - feature-breakage
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `human` — Operator did this directly.

# Incident Overview

The KB document-sharing feature was broken for any account whose legacy
`users.workspace_path` / `users.workspace_status` columns were stale or empty —
the expected state for users provisioned after the ADR-044 `users → workspaces`
relocation. Such a user could generate a share link successfully, but opening
`/shared/<token>` returned **"Document not found."** The share *created* fine and
*read* as a 404.

## Status

resolved — fix re-points the read path to resolve the KB root from the share
row's `workspace_id` (matching the create path).

## Symptom

Visiting a freshly-generated share link rendered the public "Document not found —
This document may have been removed or the link is invalid" error page (HTTP 404),
even though the document existed and the share was active.

## Incident Timeline

| Actor | Time (UTC) | Action |
|---|---|---|
| human | (ADR-044 read-path cutover) | Create path migrated to `resolveActiveWorkspaceKbRoot`; read paths left reading legacy `users` columns. Latent breakage begins for post-relocation users. |
| human | 2026-06-07 | Founder, dogfooding, copies a share link and gets "Document not found"; reports it (with screenshots) alongside the Copy-button overflow. |
| agent | 2026-06-08 | Root cause traced to the unmigrated read path; fix + tests landed; multi-agent review (security/data-integrity/architecture/quality/test) APPROVED; merged. |

## Detection (+ MTTD)

- **How detected:** external/manual — the founder hit it while dogfooding the
  share feature. NOT caught by monitoring (the read path returned a clean 404,
  not a 5xx or Sentry error — it looked like a legitimate "no such document").
- **MTTD:** unknown (latent since the ADR-044 read-path cutover; surfaced only
  on first dogfood of a post-relocation account).

## Root Cause

ADR-044 relocated KB-root resolution from the per-user `users.workspace_path` /
`users.workspace_status` columns to a workspace-id-keyed layout
(`<WORKSPACES_ROOT>/<workspace_id>/knowledge-base`, via
`workspacePathForWorkspaceId`). The migration swept the **create** path
(`app/api/kb/share/route.ts` → `resolveActiveWorkspaceKbRoot`) but NOT the
**read** paths:

- `app/api/shared/[token]/route.ts` (`prepareSharedRequest`, feeds GET + HEAD)
- `server/kb-share.ts` (`previewShare`, also the `kb_share_preview` MCP tool)

Both kept resolving kbRoot + a `workspace_status !== "ready"` readiness gate from
the owner's legacy `users` row. For a post-relocation user those columns are
stale/empty, so the read 404'd either at the readiness gate or at the file-read
(`KbNotFoundError`) against the wrong/empty path. The create route's own comment
documented the exact divergence — but only the write side had been fixed.

## Resolution

Resolve the read-side kbRoot from the share row's stored `workspace_id` (NOT NULL
since migration 059) via `workspacePathForWorkspaceId`, byte-identical to the
create path; drop the stale owner-row readiness gate (a de-provisioned workspace
still 404s at the file-read step, and the `content_sha256` hash gate still guards
served bytes). Backward-compatible for existing share rows (N2 invariant:
`workspace_id == user_id` for solo users → same on-disk dir the legacy path
pointed at).

## GDPR / Data-Exposure Assessment

- **Art. 33 (breach notification):** not triggered. This was an
  **over-restrictive denial** (valid documents wrongly 404'd) — the *opposite* of
  a disclosure. No personal data was exposed; no cross-tenant read occurred
  (security-sentinel confirmed `workspace_id` is server-stored and not
  attacker-controllable).
- **Art. 34 (data-subject notification):** not triggered (no exposure).

## Follow-ups

- [x] Read-path resolution migrated to `workspace_id` (this PR).
- [x] Regression guard added that fails if resolution ever re-reads
  `workspace_path` (divergent-`workspace_id` test).
- [ ] Sweep remaining legacy `users.workspace_path`/`workspace_status` readers
  (owner/sync/agent/export paths) before the ADR-044 pre-decommission column drop
  — tracked by ADR-044's own drift gate, out of scope for this fix.

## Lessons (see also the learning file)

A relocation migration must sweep **every** consumer of the old source, not just
the most visible (write) path. A create-path-only migration leaves read paths
resolving against the stale source — green CI, passing create, silent 404 on read.
This is the read-side analogue of `hr-write-boundary-sentinel-sweep-all-write-sites`.
Full write-up:
`knowledge-base/project/learnings/bug-fixes/2026-06-08-migration-relocating-a-resolver-must-sweep-all-read-paths-not-just-create.md`.
