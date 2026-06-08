---
feature: feat-debug-mode-stream
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-08-feat-debug-mode-stream-plan.md
closes: [5045]
---

# Tasks: Debug Mode — Workspace-Scoped Harness Instruction Stream

Derived from the finalized (post-4-agent-review) plan. Re-grep every cited line number at
implementation time — anchors drift.

## Phase 1 — Toggle stack (storage + authz + control)
- [ ] 1.1 `ls supabase/migrations | tail` to confirm `101` is still next; write `101_workspace_debug_mode.sql` (+ `.down.sql`) cloning migration 097: `debug_mode boolean NOT NULL DEFAULT false`; `get_workspace_debug_mode(p_workspace_id)` SECURITY DEFINER + member-checked + `SET search_path = public, pg_temp` + NULL→false; `set_workspace_debug_mode(p_workspace_id, p_value)` owner-only; no UPDATE policy; no bulk write.
- [ ] 1.2 `lib/feature-flags/server.ts`: add `"debug-mode": "FLAG_DEBUG_MODE"` to RUNTIME_FLAGS (re-grep `:40`) + `isDebugModeAvailable(identity)` gating on `dev` role. Add `FLAG_DEBUG_MODE` to `.env.example`.
- [ ] 1.3 `server/resolve-debug-mode.ts` (clone `resolve-bash-autonomous.ts`, fail-closed false, Sentry-mirror); `server/set-debug-mode.ts` (clone `set-bash-autonomous.ts`, `p_value`); `app/api/workspace/debug-mode/route.ts` (clone `bash-autonomous/route.ts`).

## Phase 2 — WS frame contract
- [ ] 2.1 `lib/types.ts`: add flat `debug_event` to `WSMessage`: `{ type:"debug_event"; kind:"tool_use"|"reasoning"|"result"; label?:string; body:string }`.
- [ ] 2.2 `lib/ws-zod-schemas.ts`: `debug_event` schema (clone `:265`), delta/append semantics.
- [ ] 2.3 `lib/ws-known-types.ts`: register `debug_event` (compile-enforced).
- [ ] 2.4 `lib/chat-state-machine.ts`: add `debug_event` to the `StreamEvent` Extract allowlist (`:301`) AND a reducer case (clone `command_stream` at `:885`) → ChatMessage debug variant. **(silent-drop seam — P0-4)**

## Phase 3 — Server-side gated emit
- [ ] 3.1 `server/debug-event.ts`: pure `buildDebugEvent(kind, label, rawBody)` — redact via `redactCommandForDisplay`, call `probeRedactionFallthrough`; on probe trip DROP (tool_use → `[input withheld]` placeholder with tool name; else null).
- [ ] 3.2 `server/cc-dispatcher.ts`: widen `probeRedactionFallthrough` `field` type (`"tool_input"|"reasoning"`); resolve `debugPosture`/`debugEligible` per-dispatch (mirror `resolveBashAutonomous` `:1270`/`:2283`); emit from existing `onText`/`onToolUse`/`onResult` callbacks when gated true; reuse `COMMAND_STREAM_*_CAP_BYTES`.
- [ ] 3.3 Verify ephemeral invariant: no `messages` insert / logger / Sentry references `debug_event`; add the standing CI grep gate.

## Phase 4 — Client render
- [ ] 4.1 `components/chat/debug-stream-panel.tsx`: collapsed/expanded/empty/streaming/redacted/withheld/disconnected states; member read-only view; empty-vs-unavailable heuristic; re-redact at render via `@/lib/safety`; no `@/server/*` imports.
- [ ] 4.2 `components/chat/chat-surface.tsx`: debug ChatMessage render case (`:629` switch, `:never` rail).
- [ ] 4.3 `components/settings/debug-mode-toggle.tsx`: clone `bash-autonomous-toggle.tsx`; visible only for `dev` cohort; owner-write.

## Phase 5 — Tests
- [ ] 5.1 `test/server/debug-event.test.ts`: gate / redaction+wire-bytes-invariant / ephemeral (3 describe blocks); fixtures synthesized only.
- [ ] 5.2 `test/components/debug-stream-panel.test.tsx`: render re-redaction; toggle hidden non-`dev`; member read-only.
- [ ] 5.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean (exhaustiveness across WSMessage / StreamEvent / ws-known-types / render switch).

## Phase 6 — Gates
- [ ] 6.1 `soleur:gdpr-gate` on the diff; acknowledge any Critical.
- [ ] 6.2 `user-impact-reviewer` at PR review (single-user-incident threshold).
- [ ] 6.3 `soleur:preflight` Check 6 (sensitive paths: server/, supabase/, lib/safety).

## Post-merge (operator/automatable)
- [ ] P.1 Apply migration 101 via `web-platform-release.yml#migrate` (no SSH); verify column via Supabase MCP. Migration BEFORE the flag flip.
- [ ] P.2 `soleur:flag-set-role` to create/flip the `debug-mode` segment for the `dev` cohort.
