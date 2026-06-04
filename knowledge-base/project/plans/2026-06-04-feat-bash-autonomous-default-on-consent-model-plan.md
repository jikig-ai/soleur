---
title: "feat: Concierge Autonomous mode ON by default + Scope-Grants relocation + default-ON consent model"
date: 2026-06-04
branch: feat-one-shot-bash-autonomous-default-on
type: feature
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
follow_up_to: "#4935"
---

# feat: Concierge Autonomous mode (bashAutonomous) ON by default + relocate toggle to Scope Grants + default-ON consent model

## Enhancement Summary

**Deepened on:** 2026-06-04
**Sections enhanced:** Observability (added), Precedent-Diff (added), GDPR/Compliance (added), Research Insights per phase.
**Gates cleared:** 4.6 User-Brand Impact (PASS), 4.7 Observability (added → PASS), 4.8 PAT-shaped variable (PASS, no matches), 4.9 UI-wireframe (`.pen` generated + committed → PASS).
**UX artifact:** `knowledge-base/product/design/settings/concierge-command-execution.pen` (frames A–D) generated via Pencil MCP and committed.

### Key Improvements
1. **`## Observability` section** with the 5-field schema — liveness via permission-decision logs (`autonomous-bypass` / new `autonomous-disclosure-hold` / `autonomous-disclosure-released`), Sentry via `reportSilentFallback`, non-SSH discoverability test.
2. **Precedent-diff** for the two new ack RPCs against migration 097 (`get/set_workspace_bash_autonomous`) — verbatim mirror of the member-read / owner-write / `SECURITY DEFINER` + `search_path = public, pg_temp` shape.
3. **GDPR/compliance note** — the no-backfill decision is the lawful-basis safeguard; the soft-gate disclosure is the consent record; CLO AUP/ToS update tracked as out-of-scope follow-up.

### New Considerations Discovered
- The default flip needs NO `handle_new_user` rewrite — the insert relies on the column DEFAULT (verified 091:165). This shrinks blast radius (no function re-derivation).
- Ack-read fail-closes to the **HOLD** direction (`?? null`), which is the OPPOSITE boolean from `resolve-bash-autonomous.ts`'s `?? false` — flagged as a Sharp Edge so the implementer doesn't copy the pattern blindly.

## Overview

Today the Concierge's **Autonomous mode** (`workspaces.bash_autonomous`) is OFF by default and is enabled via an opt-in risk **interstitial** living in **Settings → Privacy**. Merged PR #4935 made command-streaming + per-command card-suppression gated on `bashAutonomous` (so when autonomy is ON, commands stream into the bubble with no Approve/Deny cards). This follow-up flips the product posture:

1. **DEFAULT ON for NEW workspaces.** A forward migration flips `workspaces.bash_autonomous` column `DEFAULT false → true`. The workspace-creation insert path (`handle_new_user()`, migration 091:165) does NOT name `bash_autonomous`, so flipping the column default makes every new signup autonomous by construction. **Existing rows stored `false` stay `false`** — no bulk `UPDATE` backfill (silently enabling auto-execution on a workspace whose owner never consented is the GDPR/expectation risk). `resolve-bash-autonomous.ts` stays fail-closed.
2. **RELOCATE the toggle** out of `settings/privacy/page.tsx` into a new top-of-page section **"Concierge command execution"** on `settings/scope-grants/page.tsx` (owner-only, anchor `concierge-command-execution`). Privacy returns to GDPR/DSAR-only. No new settings nav tab.
3. **DEFAULT-ON CONSENT MODEL.** Retire the interstitial for the *default* state. **Soft-gate the FIRST auto-run per workspace** (owner-only): the first non-blocked Bash command that would auto-run under autonomy, when no ack exists, is **held** (not auto-approved) while a disclosure banner is surfaced; clicking **"Got it"** writes a per-workspace ack timestamp, after which the command proceeds and all subsequent auto-runs are friction-free. **Existing workspaces** (stored `false`, no ack) get a one-time opt-out-shaped prompt on the same first-auto-run path ("Keep autonomous on" sets `bash_autonomous=true` + ack; "Ask me each time" leaves `false` + ack). The **risk interstitial is KEPT only for a deliberate manual OFF→ON re-enable**. A **persistent state chip** ("Auto-run on" / "Approve each") sits in the Concierge header and deep-links to the Scope-Grants anchor.

The denylist (`BLOCKED_BASH_PATTERNS`) + secret redaction safety floor are unchanged — `curl/wget/nc/sh -c/eval/base64 -d//dev/tcp/sudo` stay authoritative even under autonomy.

> **All product decisions below are LOCKED by the CPO + ux-design-lead.** This plan implements them; it does not relitigate. CPO sign-off is required at plan time (frontmatter `requires_cpo_signoff: true`); `user-impact-reviewer` runs at review time.

## Premise Validation

- **PR #4935** — `gh pr view 4935 --json state` → **MERGED** ("feat(chat): stream Concierge Bash commands + output into the bubble; hide per-command approval cards"). Premise holds: streaming/card-suppression is already gated on `bashAutonomous`.
- **Migration 097** — `apps/web-platform/supabase/migrations/097_workspace_bash_autonomous.sql` exists; defines `workspaces.bash_autonomous boolean NOT NULL DEFAULT false` + `get_workspace_bash_autonomous` (member-checked read) + `set_workspace_bash_autonomous` (owner-only write), both `SECURITY DEFINER` `search_path = public, pg_temp`. Latest migration on disk is **098** (`098_workspace_logos.sql`), so the new migration is **099**.
- **`resolve-bash-autonomous.ts`** — already fail-closed (RPC error / null / `RuntimeAuthError` → `false`, mirrored to Sentry via `reportSilentFallback`). No change to its fail-closed contract; the soft-gate ack read is a *separate* read that must ALSO be fail-closed (ack-read failure ⇒ treat as not-yet-acked ⇒ hold, which is the safe direction).
- **Workspace-creation insert path** — `handle_new_user()` (canonical in `091_rename_organization_and_default_names.sql:165`): `INSERT INTO public.workspaces (id, organization_id, name) VALUES (NEW.id, v_org_id, 'My Workspace')` — does NOT name `bash_autonomous`. Flipping the column default to `true` makes new signups autonomous with no function rewrite. (There is no TS fallback in `server/auth/` that names `bash_autonomous`; `ls server/auth/` is empty — the trigger is the sole creation path.)
- **Cited surface files** — all exist and were read: `bash-autonomous-toggle.tsx`, `privacy/page.tsx` (toggle block at lines 96–110), `scope-grants/page.tsx`, `permission-callback.ts` (autonomous-bypass branch at `if (deps.bashAutonomous)` ~L406), `cc-dispatcher.ts` (resolves `bashAutonomous` at L1066–1086, threads at L1317; posture at L1899–2080), `status-indicator.tsx`, `delegation-banner.tsx`, `chat-surface.tsx` (header + `StatusIndicator` at L508), `settings-shell.tsx`, `app/api/workspace/bash-autonomous/route.ts`.
- **`/api/workspace/bash-autonomous` endpoint** — exists; per LOCKED DECISION #2 it is **untouched** (only the host route/page changes).

No stale premises. The plan shape is **implement-as-specified**, not investigate.

## Research Reconciliation — Spec vs. Codebase

| Spec/prompt claim | Codebase reality | Plan response |
|---|---|---|
| "new migration sets DEFAULT true AND the workspace-creation insert path writes true" | The insert path (`handle_new_user`) does NOT name the column — it relies on the column DEFAULT. | Migration 099 `ALTER COLUMN ... SET DEFAULT true` is **sufficient** to make creation write `true`. Plan adds an explicit assertion + comment; does NOT rewrite `handle_new_user` (re-`CREATE OR REPLACE`-ing it to name the column would be churn + risk to the rename logic in 091). |
| "store a per-workspace ack timestamp (`workspaces.autonomous_disclosure_ack_at` or a `workspace_settings` row — engineering's call)" | No `workspace_settings` table exists; `workspaces` already carries per-workspace authz columns + has the owner-only-write / member-read RPC pattern from 097. | **Add `workspaces.autonomous_disclosure_ack_at timestamptz` column** + two RPCs mirroring 097's shape: `get_workspace_autonomous_ack` (member read, NULL for non-member) and `set_workspace_autonomous_ack` (owner-only write, sets `now()` idempotently). Cheapest, consistent with the 097 precedent. |
| "interstitial (the `confirmOpen` branch in bash-autonomous-toggle.tsx)" | Confirmed: `confirmOpen` state + `alertdialog` block at L107–142; OFF is free (`persist(false)`), ON sets `confirmOpen`. | Keep the `confirmOpen` branch verbatim for OFF→ON re-enable; it already fires only on `!autonomous` toggle-on. No logic change needed there beyond copy. |
| "Privacy returns to GDPR/DSAR-only … remove the `isWorkspaceOwner && (...)` block ~lines 96-110 and now-unused imports" | Block is at L96–110; imports to remove: `BashAutonomousToggle`, `resolveBashAutonomous`, `resolveCurrentWorkspaceId`, and the membership query (L42–53). | Remove the section + the four import/derivation sites; verify `tsc` for unused-symbol regressions. |
| "persistent state chip … Pattern: status-indicator.tsx" + "Banner pattern: delegation-banner.tsx; render in chat-surface.tsx" | `StatusIndicator` mounts in `chat-surface.tsx` header at L508; `DelegationBanner` is a top-of-surface banner. Chip needs the live posture; client learns posture via the existing `setBashAutonomous` callback path (cc-dispatcher L1086) surfaced over WS. | New `AutoRunChip` mounts beside `StatusIndicator` (L508). New `AutonomousDisclosureBanner` mounts as a sibling banner after the header (near the `reconnecting` banner at L521). Soft-gate hold uses a new WS frame mirroring `review_gate` (`ws-zod-schemas.ts:276`, routed in `ws-handler.ts:1996`). |

## User-Brand Impact

**If this lands broken, the user experiences:** a brand-new workspace where the Concierge auto-runs a file-mutating command **before** the owner ever saw the disclosure (soft-gate failed to hold) — or, inversely, autonomy silently disabled so every command demands manual approval and the streamed-bubble UX from #4935 never appears.

**If this leaks, the user's workflow/data is exposed via:** an auto-executed non-blocked command that (through prompt-injection from a malicious repo file or issue) deletes/exfiltrates workspace files with no approval step. The blocklist + git backup + in-chat command visibility are the residual-risk floor; the soft-gate disclosure is the consent surface that makes that residual risk *informed*.

**Brand-survival threshold: single-user incident.** One workspace auto-executing a destructive command without the owner having consented is a brand-survival event. ⇒ `requires_cpo_signoff: true`; `user-impact-reviewer` at review.

## Sharp Edges

- The `## User-Brand Impact` section above is filled (not TBD) — deepen-plan Phase 4.6 will halt on an empty one.
- **Default flip is forward-only.** Migration 099 must `ALTER COLUMN bash_autonomous SET DEFAULT true` ONLY — **no `UPDATE public.workspaces SET bash_autonomous = true`**. A bulk UPDATE is the GDPR violation this plan exists to avoid. Add a CI/migration-test assertion that the 099 file contains no `UPDATE ... bash_autonomous` statement.
- **Ack-read must fail-closed in the HOLD direction.** `resolve-bash-autonomous.ts` fail-closes to `false` (not-autonomous = safe). The ack read fail-closes to `null` (not-acked ⇒ HOLD the first run = safe). Both safe directions, but they are *opposite booleans* — do not copy the `?? false` pattern blindly; the ack helper must `?? null` and the callsite must treat null as "hold".
- **`handle_new_user` is `CREATE OR REPLACE`d in BOTH 053 and 091.** Do NOT re-`CREATE OR REPLACE` it in 099 — flipping the column default is sufficient and avoids re-deriving the 091 rename logic. If a reviewer insists the insert "explicitly write true", prefer naming the column in the *next* time the function is legitimately edited, not here.
- **Soft-gate is owner-only.** The disclosure ack is an ownership-grade decision (mirrors 097's owner-only write). A non-owner member hitting the first auto-run on an un-acked workspace must NOT be able to ack. Engineering's call whether non-owner members fall back to the review-gate (safe) until an owner acks — recommend: non-owner ⇒ hold-and-review (treat as not-autonomous) rather than surfacing an ack button they can't use.
- **Chip posture source.** The chip must reflect the *server-resolved* posture (the same value `resolveBashAutonomous` produces for the active workspace), not a client guess. Reuse the `setBashAutonomous` callback path already wired in cc-dispatcher (L1086) → surface to the client over WS. A client-only optimistic posture risks showing "Auto-run on" while the server held the run.
- **Sharp 0px corners** (brand-guide.md:266): the new section card, banner, buttons, and chip use `rounded-none` / square. The existing toggle TRACK may stay pill-shaped (`rounded-full`) per LOCKED DECISION #5 — do NOT square the switch track.

## Implementation Phases

### Phase 0 — Preconditions (verify, no code)
- `ls apps/web-platform/supabase/migrations/ | tail` → confirm highest is 098; new file is **099**.
- Read 097 RPC bodies to mirror exact `SECURITY DEFINER` / `REVOKE` / `GRANT` / owner-check shape for the two new ack RPCs.
- `grep -n 'review_gate' apps/web-platform/lib/ws-zod-schemas.ts apps/web-platform/lib/types.ts apps/web-platform/server/ws-handler.ts` → confirm the frame + routing shape the disclosure hold will mirror.
- Confirm `apps/web-platform/server/auth/` has no `bash_autonomous` writer (it doesn't).

### Phase 1 — Migration 099 (DB): default flip + ack column + ack RPCs
**Files to create:**
- `apps/web-platform/supabase/migrations/099_bash_autonomous_default_on_and_ack.sql`
- `apps/web-platform/supabase/migrations/099_bash_autonomous_default_on_and_ack.down.sql`
- `apps/web-platform/supabase/verify/099_bash_autonomous_default_on_and_ack.sql` (mirror 097's verify shape — GRANT/REVOKE assertions for the two ack RPCs)

Migration body:
1. `ALTER TABLE public.workspaces ALTER COLUMN bash_autonomous SET DEFAULT true;` + updated `COMMENT` noting "new workspaces default ON; existing rows unchanged; consent via first-run soft-gate".
2. `ALTER TABLE public.workspaces ADD COLUMN IF NOT EXISTS autonomous_disclosure_ack_at timestamptz;` (nullable, no default — NULL = not yet acked).
3. `get_workspace_autonomous_ack(p_workspace_id uuid) RETURNS timestamptz` — member-checked (mirror `get_workspace_bash_autonomous`), NULL for non-member/unauth. `SECURITY DEFINER`, `SET search_path = public, pg_temp`, `REVOKE ALL FROM PUBLIC, anon, service_role; GRANT EXECUTE TO authenticated`.
4. `set_workspace_autonomous_ack(p_workspace_id uuid) RETURNS timestamptz` — owner-only (mirror `set_workspace_bash_autonomous`), idempotent (`COALESCE` existing ack or set `now()`), scoped by `(p_workspace_id, auth.uid())`. May also accept an optional `p_keep_autonomous boolean DEFAULT NULL` so the existing-workspace opt-out prompt's "Keep autonomous on" can set `bash_autonomous=true` + ack in one owner-checked call (engineering's call; alternatively reuse the existing `set_workspace_bash_autonomous` for the flip + this RPC for the ack — two calls).
- **No `UPDATE ... bash_autonomous` anywhere in 099.**
- Down migration drops the two RPCs, drops the column, and `ALTER COLUMN bash_autonomous SET DEFAULT false`.

#### Research Insights — Precedent-Diff (Phase 4.4)

The two ack RPCs MUST be a verbatim structural mirror of migration 097's `get_workspace_bash_autonomous` / `set_workspace_bash_autonomous` (the established codebase form for member-read / owner-write per-workspace authz values). Confirmed precedent:

- **Read** (`get_workspace_autonomous_ack`): `LANGUAGE plpgsql`, `SECURITY DEFINER`, `SET search_path = public, pg_temp` (`cq-pg-security-definer-search-path-pin-pg-temp`); gate on `IF NOT public.is_workspace_member(p_workspace_id, auth.uid()) THEN RETURN NULL`; `SELECT autonomous_disclosure_ack_at INTO v_value ... WHERE id = p_workspace_id`; `REVOKE ALL ... FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ... TO authenticated`. NULL for non-member is the deny path — server `resolveAutonomousAck` treats NULL as fail-closed (HOLD).
- **Write** (`set_workspace_autonomous_ack`): owner-only via the R8 composite-key `EXISTS (SELECT 1 FROM workspace_members WHERE workspace_id = p_workspace_id AND user_id = auth.uid() AND role = 'owner')` check, `RAISE EXCEPTION` on non-owner (authz violation, surfaced + mirrored), idempotent `UPDATE ... SET autonomous_disclosure_ack_at = COALESCE(autonomous_disclosure_ack_at, now())`. Same REVOKE/GRANT.
- **Divergence from precedent (intentional):** the write RPC may take an optional `p_keep_autonomous boolean DEFAULT NULL` so the existing-workspace "Keep autonomous on" branch sets `bash_autonomous = true` + ack in one owner-checked statement. If adopted, the owner-check must wrap BOTH writes (it already does — single function body). Alternatively keep the two RPCs orthogonal and have the client call `set_workspace_bash_autonomous(.., true)` then `set_workspace_autonomous_ack(..)` — two owner-checked calls, no new param. Engineering's call; document whichever in the migration comment.

#### Research Insights — GDPR / Compliance (Phase 2.7)

This plan touches a regulated-data surface (Supabase migration + an authz-relevant consent column on a code-executing surface) at `single-user incident` threshold, so the gate applies:

- **Lawful basis / expectation safeguard:** the no-backfill decision (existing `false` rows stay `false`) is the load-bearing control — it prevents silently enabling auto-execution on a workspace whose owner never consented. The forward default flip applies only to NEW workspaces created after the consent model ships, and even those are soft-gated on first auto-run. Do NOT add a bulk `UPDATE` "for consistency" — it would convert this from opt-out-shaped to silent-enable.
- **Consent record:** `autonomous_disclosure_ack_at` is the per-workspace timestamp evidencing the owner saw + acknowledged the residual-risk disclosure before the first auto-run. This is the auditable consent artifact.
- **CLO follow-up (out of scope, tracked):** the AUP/ToS must reference autonomous command execution + residual-risk before EXTERNAL beta (Phase 4). Beta prerequisite, NOT a blocker for this PR — file a tracking issue (label verified via `gh label list`).
- No Article 9 special-category data; no new external-API processing of operator data introduced here.

### Phase 2 — Server read helper for ack (fail-closed null)
**Files to create:**
- `apps/web-platform/server/resolve-autonomous-ack.ts` — `resolveAutonomousAck(userId, workspaceId?)` mirroring `resolve-bash-autonomous.ts` but returning `timestamptz | null`; **fail-closed to `null`** (= not acked = hold). Mirror Sentry `reportSilentFallback` on RPC error.
- `apps/web-platform/server/set-autonomous-ack.ts` — `setAutonomousAck(userId, { keepAutonomous? })` mirroring `set-bash-autonomous.ts` (owner-deny → throw a typed error the route maps to 403).

### Phase 3 — Soft-gate enforcement in the auto-approve path (server)
**Files to edit:**
- `apps/web-platform/server/permission-callback.ts` — `CanUseToolDeps` gains `autonomousAckAt?: number | null` (and an `isOwner?: boolean` if not already derivable from ctx). In the `if (deps.bashAutonomous)` branch (~L406): when `deps.bashAutonomous && deps.autonomousAckAt == null` (and owner), **do NOT `allow()`** — emit a new disclosure-hold frame (mirroring the `review_gate` emit a few lines below at the gate path) and BLOCK that single command until the owner acks. On ack-resolve, proceed (`allow`). For an **existing un-acked workspace** (`bashAutonomous === false && autonomousAckAt == null`), the existing review-gate already fires (since `bashAutonomous` is false) — the one-time opt-out prompt is surfaced *alongside* that gate (client decides "Keep autonomous on" vs "Ask me each time"); both write the ack. Non-owner on an un-acked autonomous workspace ⇒ fall through to review-gate (treat as not-autonomous) — do not surface an ack button they can't use.
- `apps/web-platform/server/cc-dispatcher.ts` — alongside `resolveBashAutonomous(args.userId)` (L1072) add `resolveAutonomousAck(args.userId)` to the `Promise.all` (L1066), thread `autonomousAckAt` into `createCanUseTool` deps (L1317) and into the posture path (L1899–2080) so the chip + streaming posture agree with the gate decision. Reuse/extend the `setBashAutonomous` callback (L1086) to also carry ack state to the client for the chip.
- `apps/web-platform/server/ws-handler.ts` — add a `*_response` case (mirror `review_gate_response` at L1996) to route the "Got it" / "Keep autonomous on" / "Ask me each time" ack back to the held command + call `setAutonomousAck`. Register/resolve the held gate via a registry mirroring `_ccBashGates` (cc-dispatcher) or reuse it.

### Phase 4 — WS frame + zod schema + types for the disclosure hold
**Files to edit:**
- `apps/web-platform/lib/ws-zod-schemas.ts` — add `autonomous_disclosure` (server→client) + `autonomous_disclosure_response` (client→server) schemas mirroring `review_gate` / `review_gate_response` (L217/276).
- `apps/web-platform/lib/types.ts` — add the two union members (mirror L257/320). **Run `tsc --noEmit` after the union edit; every TS2322 "not assignable to never" is an exhaustiveness rail to widen** (per `cq-union-widening-grep-three-patterns`; do not hardcode a site count).
- `apps/web-platform/lib/chat-state-machine.ts` — reducer case for the disclosure frame (mirror `command_stream` / `review_gate` handling at L287/835); also a posture field so the chip can read "auto-run on / approve each".
- `apps/web-platform/lib/ws-client.ts` — handle the new server→client frame (mirror `command_stream` at L666).

### Phase 5 — Relocate the toggle: Scope Grants in, Privacy out
**Files to edit:**
- `apps/web-platform/app/(dashboard)/dashboard/settings/scope-grants/page.tsx` — add a NEW top-of-page `<section id="concierge-command-execution" aria-labelledby=...>` ABOVE the per-action-class grant list (before the `ACTION_CLASSES_BY_CATEGORY` map at L127), titled **"Concierge command execution"**, owner-only. Reuse this page's existing user + owner-resolution pattern — note: scope-grants resolves `user` (L40) but does **NOT** currently resolve workspace-owner; add the same membership query the Privacy page used (workspace_members role === 'owner', cookie-scoped RLS client) + `resolveBashAutonomous(user.id)` to seed the toggle. Render `<BashAutonomousToggle initialAutonomous={...} isOwner={...} />`. Use `rounded-none` square section card per brand.
- `apps/web-platform/app/(dashboard)/dashboard/settings/privacy/page.tsx` — **remove** the `isWorkspaceOwner && (...)` section (L96–110), the imports `BashAutonomousToggle` / `resolveBashAutonomous` / `resolveCurrentWorkspaceId` (L17–19), the `autonomous` + `activeWorkspaceId` + `membership` + `isWorkspaceOwner` derivations (L42–53). Privacy returns to DSAR/GDPR-only. Verify `tsc` for newly-unused symbols.
- **Do NOT touch** `STATIC_SETTINGS_TABS` in `settings-shell.tsx` (no new tab).
- **Do NOT touch** `app/api/workspace/bash-autonomous/route.ts` (endpoint unchanged).

### Phase 6 — Toggle copy + interstitial scope
**Files to edit:**
- `apps/web-platform/components/settings/bash-autonomous-toggle.tsx` — helper copy "Off by default" → "On by default" (L84–86); update the `confirmOpen` interstitial copy to founder-legible residual-risk language; the interstitial now fires ONLY on deliberate manual OFF→ON re-enable (already the case — `confirmOpen` only sets on `!autonomous` → on; OFF stays free). No structural change to the OFF→ON gate logic. Square corners on the dialog/buttons (`rounded-none`), leave the switch track pill.

### Phase 7 — Persistent state chip + disclosure banner (client)
**Files to create:**
- `apps/web-platform/components/chat/auto-run-chip.tsx` — "Auto-run on" (ON) / "Approve each" (OFF), click → `router.push('/dashboard/settings/scope-grants#concierge-command-execution')`. Pattern: `status-indicator.tsx`. Square corners.
- `apps/web-platform/components/chat/autonomous-disclosure-banner.tsx` — renders the LOCKED banner copy (below), "Got it" button writes the ack and releases the held command; for existing-workspace opt-out shows "Keep autonomous on" + "Ask me each time". Pattern: `delegation-banner.tsx`. Square corners.

**Files to edit:**
- `apps/web-platform/components/chat/chat-surface.tsx` — mount `<AutoRunChip posture={...} />` beside `<StatusIndicator>` in the header (L508); mount `<AutonomousDisclosureBanner>` as a sibling banner after the header (near the `reconnecting` banner, L521) when a disclosure-hold frame is active.

### Phase 8 — Tests
- **Migration test** (`apps/web-platform/test/supabase-migrations/099-*.test.ts`, follow runner globbing — vitest `test/**`): assert column DEFAULT flipped to `true`, ack column added, both RPCs have correct GRANT/REVOKE, **assert no `UPDATE ... bash_autonomous` in the 099 SQL**, existing-row default-preservation (insert a pre-099-shaped row → bash_autonomous stays as written).
- **Server unit** (`test/server/`): `resolveAutonomousAck` fail-closed to null; permission-callback soft-gate holds when `bashAutonomous && ack==null` (owner), allows when `bashAutonomous && ack!=null`, falls through to review-gate for non-owner. Use deterministic direct-invocation (no LLM in the assertion path).
- **Component** (place under `test/components/settings/` and `test/components/chat/` — vitest `test/**/*.test.tsx` jsdom; co-located component tests are NOT collected): toggle copy "On by default"; chip label + deep-link href; banner "Got it" calls the ack handler.
- Run the package's actual runner (`vitest`, not `bun test` — `bunfig.toml` ignores tests). Confirm test paths match `vitest.config.ts` `include:` globs before prescribing.

## LOCKED COPY (verbatim)

- Toggle helper: "Off by default" → **"On by default"**.
- Banner / disclosure copy:
  > "Soleur runs commands automatically to get work done. It always blocks clearly dangerous commands (curl, wget, sudo, …) and hides your secrets — but no blocklist is perfect. A command that looks safe could still change or delete files in this workspace. Your work is backed up in git, and you can watch every command run in the chat. Only connect repos and accounts you trust."

## Files to Edit
- `apps/web-platform/app/(dashboard)/dashboard/settings/privacy/page.tsx`
- `apps/web-platform/app/(dashboard)/dashboard/settings/scope-grants/page.tsx`
- `apps/web-platform/components/settings/bash-autonomous-toggle.tsx`
- `apps/web-platform/server/permission-callback.ts`
- `apps/web-platform/server/cc-dispatcher.ts`
- `apps/web-platform/server/ws-handler.ts`
- `apps/web-platform/lib/ws-zod-schemas.ts`
- `apps/web-platform/lib/types.ts`
- `apps/web-platform/lib/chat-state-machine.ts`
- `apps/web-platform/lib/ws-client.ts`
- `apps/web-platform/components/chat/chat-surface.tsx`

## Files to Create
- `apps/web-platform/supabase/migrations/099_bash_autonomous_default_on_and_ack.sql`
- `apps/web-platform/supabase/migrations/099_bash_autonomous_default_on_and_ack.down.sql`
- `apps/web-platform/supabase/verify/099_bash_autonomous_default_on_and_ack.sql`
- `apps/web-platform/server/resolve-autonomous-ack.ts`
- `apps/web-platform/server/set-autonomous-ack.ts`
- `apps/web-platform/components/chat/auto-run-chip.tsx`
- `apps/web-platform/components/chat/autonomous-disclosure-banner.tsx`
- `knowledge-base/product/design/settings/concierge-command-execution.pen` (UX wireframe — see UX gate)
- Test files under `apps/web-platform/test/supabase-migrations/`, `test/server/`, `test/components/settings/`, `test/components/chat/`

## Acceptance Criteria

### Pre-merge (PR)
- [x] Migration 099 sets `workspaces.bash_autonomous` column DEFAULT to `true`; migration test asserts the new default AND asserts **zero** `UPDATE ... bash_autonomous` statements in the 099 SQL (no backfill).
- [x] A row inserted by the existing `handle_new_user` shape (no `bash_autonomous` named) lands `bash_autonomous = true` post-099. *(default-flip + no function rewrite; verified by migration-shape test; runtime row-insert asserted at CI migrate apply)*
- [x] An existing row stored `false` remains `false` after 099 applies. *(forward-only `SET DEFAULT`; no `UPDATE` — asserted by the GDPR sentinel test)*
- [x] `autonomous_disclosure_ack_at` column + `get_workspace_autonomous_ack` (member read, NULL non-member) + `set_workspace_autonomous_ack` (owner-only) exist with 097-equivalent GRANT/REVOKE; verify SQL passes. *(verify/099 mirrors verify/097)*
- [x] `resolveAutonomousAck` returns `null` on RPC error / non-member / `RuntimeAuthError` (fail-closed to HOLD direction), mirrored to Sentry.
- [x] `resolve-bash-autonomous.ts` fail-closed contract unchanged (still `?? false`).
- [x] permission-callback: `bashAutonomous && ackAt == null && owner` ⇒ command HELD (not `allow`), disclosure frame emitted; `bashAutonomous && ackAt != null` ⇒ `allow` (friction-free); non-owner on un-acked autonomous ⇒ review-gate fallback.
- [x] Blocklist still authoritative under autonomy (sudo/curl/etc. denied before the autonomous branch) — existing test still green.
- [x] Toggle section removed from `privacy/page.tsx`; Privacy renders DSAR/GDPR only; no unused-import `tsc` errors.
- [x] Toggle section present on `scope-grants/page.tsx` as a top section `id="concierge-command-execution"`, ABOVE the grant list, owner-only.
- [x] `STATIC_SETTINGS_TABS` unchanged; `app/api/workspace/bash-autonomous/route.ts` unchanged.
- [x] Toggle helper copy reads "On by default"; OFF→ON re-enable still shows the risk interstitial; turning OFF is free.
- [x] `AutoRunChip` renders "Auto-run on" / "Approve each" reflecting server-resolved posture; click navigates to `/dashboard/settings/scope-grants#concierge-command-execution`.
- [x] `AutonomousDisclosureBanner` renders the LOCKED copy verbatim; "Got it" writes the ack and releases the held command; existing-workspace opt-out offers "Keep autonomous on" / "Ask me each time".
- [x] New surfaces use sharp 0px corners (`rounded-none`); switch track may stay pill.
- [x] `.pen` wireframe committed at `knowledge-base/product/design/settings/concierge-command-execution.pen` with frames A–D (see UX gate).
- [x] `tsc --noEmit` clean; vitest suites green via the package's actual runner.

### Post-merge (operator)
- [ ] Migration 099 applied to prod via the existing `web-platform-release.yml#migrate` job (PR merge IS the apply trigger; no separate operator step). Verify post-deploy via Supabase MCP read-only: column default = `true`, two ack RPCs present.

## Out of Scope (flag, don't build — deferral tracking required)
- **CLO follow-up:** AUP/ToS must reference autonomous command execution + residual-risk before EXTERNAL beta (Phase 4). Beta prerequisite, NOT a blocker for this PR. → File a tracking issue (label per `gh label list` verification; closest existing: `domain/legal` or `compliance/*`) with re-eval criterion "before external beta".
- **GitHub-issue-creation 403** (workspace-runtime token-path misdiagnosis) — separate PR. Do not touch here.

## UX Gate (BLOCKING — REQUIRED `.pen`)
Per LOCKED DECISION #6, this is a UI feature creating new user-facing surfaces (banner, chip, relocated section, interstitial) ⇒ Product/UX Gate is **BLOCKING**. `ux-design-lead` must GENERATE + commit `knowledge-base/product/design/settings/concierge-command-execution.pen` with frames:
- **(A)** relocated Scope-Grants "Concierge command execution" section incl. the OFF→ON reconfirm dialog.
- **(B)** first-run soft-gate disclosure banner.
- **(C)** persistent auto-run state chip.
- **(D)** terminal-style auto-run command bubble for context — benign command `$ npm run build`, redacted token rendered as `••••••••` (NO realistic secret patterns — avoids push-protection).
Threshold = single-user incident ⇒ `requires_cpo_signoff: true`; `user-impact-reviewer` at review. `ux-design-lead` is non-skippable (committed `.pen` or hard-block).

## Observability

```yaml
liveness_signal:
  what: "permission-callback Bash decision logs — `autonomous-bypass` (friction-free auto-run), the new `autonomous-disclosure-hold` (first-run held), and `autonomous-disclosure-released` (ack written, command proceeds). Each emits via logPermissionDecision + a `{ sec: true }` structured log line (permission-callback.ts pattern at L195/212)."
  cadence: "per Bash tool invocation under the Concierge (event-driven, not polled)"
  alert_target: "structured logs in the web-platform container (queryable by `decision:autonomous-disclosure-hold` / `autonomous-bypass`); no paging alert — these are expected-path signals, not faults"
  configured_in: "apps/web-platform/server/permission-callback.ts (Bash branch ~L406) + apps/web-platform/server/permission-log.ts"
error_reporting:
  destination: "Sentry via reportSilentFallback (observability.ts:183) for ack-read RPC faults; warnSilentFallback for non-fatal degradations. The new resolve-autonomous-ack.ts mirrors resolve-bash-autonomous.ts's reportSilentFallback call on RPC error / RuntimeAuthError."
  fail_loud: true
failure_modes:
  - mode: "ack-read RPC fails → resolveAutonomousAck returns null (fail-closed HOLD)"
    detection: "Sentry event feature=resolve-autonomous-ack op=rpc-read; permission log shows autonomous-disclosure-hold despite an existing ack"
    alert_route: "Sentry (reportSilentFallback mirror); command is safely held (first-run disclosure re-shown) — no auto-execute on a read fault"
  - mode: "default flip did NOT apply (new workspace lands bash_autonomous=false)"
    detection: "post-deploy Supabase MCP read: `SELECT column_default FROM information_schema.columns WHERE table_name='workspaces' AND column_name='bash_autonomous'` ≠ 'true'"
    alert_route: "post-merge operator verify step (Supabase MCP, read-only); migration-test failure pre-merge"
  - mode: "soft-gate auto-allows on un-acked autonomous workspace (HOLD bypassed — brand-survival)"
    detection: "permission log shows `autonomous-bypass` for a workspace whose `autonomous_disclosure_ack_at IS NULL`; covered pre-merge by the permission-callback unit test asserting HOLD when ack==null"
    alert_route: "pre-merge test gate (deterministic, no LLM in assertion path); Sentry breadcrumb if it ever fires in prod"
  - mode: "disclosure-hold frame never released (held command stuck after ack)"
    detection: "client AutonomousDisclosureBanner remains mounted; ws-handler ack-response case logs no resolve; gate registry (mirrors _ccBashGates) drains on conversation close"
    alert_route: "structured log `op:resolve-autonomous-disclosure`; conversation-close cleanup path releases held gates (mirrors cleanupCcBashGatesForConversation)"
logs:
  where: "web-platform container structured logs (pino) for permission decisions + gate lifecycle; Sentry for ack-read faults; permission-log.ts sec-tagged lines"
  retention: "container log retention (per existing web-platform logging config); Sentry per project retention"
discoverability_test:
  command: "grep -nE 'autonomous-disclosure-hold|autonomous-disclosure-released|autonomous-bypass' apps/web-platform/server/permission-callback.ts && ./node_modules/.bin/vitest run apps/web-platform/test/server/permission-callback-autonomous-softgate.test.ts"
  expected_output: "grep prints the three decision-log call sites; vitest reports the soft-gate suite green (HOLD when ack==null, ALLOW when ack!=null, review-gate fallback for non-owner). NO ssh."
```

## Domain Review
*(populated by Phase 2.5 domain sweep — Product BLOCKING; Engineering, Legal/Compliance relevant given regulated-data column + auto-execution consent surface.)*
