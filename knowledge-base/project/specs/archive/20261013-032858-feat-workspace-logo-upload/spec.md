---
feature: workspace-logo-upload
issue: 4916
branch: feat-workspace-logo-upload
pr: 4930
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
created: 2026-06-04
brainstorm: knowledge-base/project/brainstorms/2026-06-04-workspace-logo-upload-brainstorm.md
---

# Spec: Workspace Logo Upload

## Problem Statement

Workspaces currently display a name-initial **monogram** in the dashboard chrome
(shipped in #4915 / PR #4911 as the fallback). Users cannot set a custom workspace
logo. This is the deferred upload slice — a pure upgrade over the live monogram,
not a fix.

## Goals

- Let a workspace **owner** upload a custom logo (PNG/WebP, square, ≤1MB).
- Render the logo at the workspace identity tile, falling back cleanly to the
  monogram when no logo is set or the image fails to load.
- Store logos in a **private** Supabase bucket with workspace-grain isolation,
  served via short-lived server-minted signed URLs.
- Validate uploads server-side via `sharp` decode-and-re-encode (strips EXIF +
  neutralizes polyglot payloads).
- Keep the change brand-safe at the `single-user incident` threshold.

## Non-Goals (v1)

- SVG or JPG support (raster PNG/WebP only — SVG dropped for XSS safety).
- Logo rendering anywhere except the identity tile (no context band, no favicon).
- Animated logos, dark/light or per-theme variants, crop/resize tooling.
- Public-URL serving (private bucket + signed URL only).
- Paste-a-URL logo (considered as a thinner slice; not chosen).

## Functional Requirements

- **FR1** — Owner can upload a logo from Settings → Workspace (control beside
  Rename, in the existing Workspace settings pane). Wireframe: screenshot 25.
- **FR2** — Accept PNG and WebP only; reject SVG, JPG, non-square, and >1MB with an
  explicit inline error (never a silent no-op). Wireframe: screenshot 26.
- **FR3** — Show optimistic preview + progress during upload, then confirmation.
  Wireframe: screenshot 27.
- **FR4** — Owner can remove the logo, reverting to the monogram.
- **FR5** — Identity tile renders the logo when present; on `onError` or no logo,
  falls back to the monogram (visually identical to the no-logo state). Wireframe:
  screenshot 28.
- **FR6** — Logo image arrives with chrome data in one round-trip (no separate
  client fetch).

## Technical Requirements

- **TR1** — New migration: `ALTER TABLE public.workspaces ADD COLUMN IF NOT EXISTS
  logo_url text` (nullable); a private `workspace-logos` bucket with
  `file_size_limit` and `allowed_mime_types ARRAY['image/png','image/webp']`;
  `storage.objects` RLS cloned from migration **068** with the **F3 write-split**
  (widened SELECT via `is_workspace_member`, owner-only INSERT/UPDATE/DELETE).
  Include `.down.sql` and a migration test (mirror the 068 test, **add a
  cross-tenant overwrite-denial case**).
- **TR2** — Server upload route only (never client SDK write — `logo_url` would
  otherwise inherit the permissive workspaces UPDATE policy → column-takeover).
  Route: resolve **active** `workspace_id` server-side; `sharp` decode + re-encode +
  square/size validation; **assert storage-path `workspace_id` == resolved row**
  before write; path `workspace-logos/<workspace_id>/logo.<ext>`.
- **TR3** — Signed-URL mint folded into `server/org-memberships-resolver.ts`; add
  `logoSignedUrl` to `OrgMembershipSummary`; thread into `WorkspaceIdentityTile`.
- **TR4** — Add the Supabase Storage signed-URL origin to `img-src` in
  `lib/security-headers.ts` (else CSP blocks the `<img>`).
- **TR5** — `Sentry.captureMessage` on: (a) upload rejection, (b) DB-persist failure
  after a successful storage write (orphan handling), (c) render `onError`. The
  legitimate no-logo monogram path stays silent.
- **TR6** — Use `file.stream()` (not `file.arrayBuffer()`) on the upload route to
  avoid triple memory copy (learnings).

## Legal Requirements (CLO — mandatory, PR-time attested)

- **LR1** — Lockstep 3-doc update: Privacy Policy + Data-Protection-Disclosure +
  GDPR Policy / Article-30 register (new processing activity, retention =
  workspace lifetime, eu-west-1, no new sub-processor).
- **LR2** — Wire `workspace-logos` into the **DSAR export archiver**
  (`server/dsar-export.ts`) and the **workspace-deletion cascade** — NOT the
  per-user `account-delete` purge (workspace-grain, shared property).
- **LR3** — One-line Acceptable-Use-Policy scope extension naming the workspace-logo
  surface alongside chat-attachments (recommended).

## Acceptance Criteria

- I upload a square PNG/WebP and my workspace tile + switcher row show it.
- A wrong-type (SVG/JPG), oversized, or non-square file is rejected with a clear
  message; nothing changes silently.
- A broken/expired logo URL falls back to the monogram — never a broken-image glyph.
- I can remove the logo and return to the monogram.
- One workspace cannot read or overwrite another workspace's logo (migration test).
- Privacy Policy / DPD / Art-30 / DSAR export / deletion cascade reflect the new bucket.

## Open Questions

See brainstorm "Open Questions": signed-URL TTL, square-crop-vs-reject, orphaned-object
cleanup strategy, CSP origin specifics.
