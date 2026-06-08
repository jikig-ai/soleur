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
- [ ] 1.1 `ls supabase/migrations | tail` to confirm `101` is still next; write `101_workspace_debug_mode.sql` (+ `.down.sql`) cloning migration **097 (NOT 099)**: `debug_mode boolean NOT NULL DEFAULT false`; `get_workspace_debug_mode(p_workspace_id)` SECURITY DEFINER + member-checked + `SET search_path = public, pg_temp` + NULL→false; `set_workspace_debug_mode(p_workspace_id, p_value)` owner-only via the **inline `workspace_members … role='owner'` EXISTS check cloned verbatim from 097:84–92** (no `is_workspace_owner` helper exists); no UPDATE policy; no bulk write. `.down.sql` = 097's **3-statement** form (fns → column; no default-reset line).
- [ ] 1.1b `supabase/verify/101_workspace_debug_mode.sql` — clone `verify/097`'s `has_function_privilege` checks (anon≠EXECUTE, authenticated=EXECUTE) for both RPCs.
- [ ] 1.2 `lib/feature-flags/server.ts`: add `"debug-mode": "FLAG_DEBUG_MODE"` to RUNTIME_FLAGS (re-grep `:40`) + `isDebugModeAvailable(identity)` that **hard-gates `if (identity.role !== "dev") return false;` BEFORE `getRuntimeFlag`** (do NOT clone `isTeamWorkspaceInviteEnabled` verbatim — fail-open). Add `FLAG_DEBUG_MODE` to `.env.example`.
- [ ] 1.3 `server/resolve-debug-mode.ts` (clone `resolve-bash-autonomous.ts`, fail-closed false, Sentry-mirror); `server/set-debug-mode.ts` (clone `set-bash-autonomous.ts`, `p_value`); `app/api/workspace/debug-mode/route.ts` (clone `bash-autonomous/route.ts`).

## Phase 2 — WS frame contract
- [ ] 2.1 `lib/types.ts`: add flat `debug_event` to `WSMessage`: `{ type:"debug_event"; kind:"tool_use"|"reasoning"|"result"; label?:string; body:string }`.
- [ ] 2.2 `lib/ws-zod-schemas.ts`: `debug_event` schema (clone `:265`), delta/append semantics.
- [ ] 2.3 `lib/ws-known-types.ts`: register `debug_event` (compile-enforced).
- [ ] 2.4 `lib/chat-state-machine.ts`: add `debug_event` to the `StreamEvent` Extract allowlist (`:301`) AND a reducer case (clone `command_stream` at `:885`) → ChatMessage debug variant. **(silent-drop seam — P0-4)**

## Phase 3 — Server-side gated emit
- [ ] 3.0 `server/debug-probes.ts`: `DEBUG_REDACTION_PROBES` array = **superset of every shape `redaction-allowlist.ts` recognizes** (sk-ant-, OpenAI sk-, Stripe, AWS AKIA + secret-assign, Slack, JWT, generic *_TOKEN/_KEY/_SECRET/_PASSWORD/_PAT, conn-string, GitHub family, Authorization). Debug stream's OWN probe — `command_stream`'s shared probe untouched.
- [ ] 3.1 `server/debug-event.ts`: pure `buildDebugEvent(kind, label, rawValue)` — for `tool_use`, redact **per-string-leaf** (walk parsed object, `redactCommandForDisplay` each string value, THEN serialize); run `DEBUG_REDACTION_PROBES`; on trip DROP (tool_use → `body:"[input withheld]"` + `label: buildToolLabel(name,…)` — human label, NOT raw name; else null). `catch` logs only `{userId, conversationId, kind}`.
- [ ] 3.2 `server/cc-dispatcher.ts`: resolve `debugPosture`/`debugEligible` per-dispatch (mirror `resolveBashAutonomous` `:1270`/`:2283`); emit via `buildDebugEvent` from existing `onText`(→reasoning)/`onToolUse`(→tool_use, raw input object)/`onResult`(→result) callbacks when gated true; reuse `COMMAND_STREAM_*_CAP_BYTES`. (Shared `probeRedactionFallthrough` NOT modified.)
- [ ] 3.3 Verify ephemeral invariant: no `messages` insert / logger / Sentry references `debug_event`; add the standing CI grep gate.

## Phase 4 — Client render
- [ ] 4.1 `components/chat/debug-stream-panel.tsx`: collapsed/expanded/empty/streaming/redacted/withheld/disconnected states; member read-only view; empty-vs-unavailable heuristic; re-redact at render via `@/lib/safety`; no `@/server/*` imports.
- [ ] 4.2 `components/chat/chat-surface.tsx`: debug ChatMessage render case (`:629` switch, `:never` rail).
- [ ] 4.3 `components/settings/debug-mode-toggle.tsx`: clone `bash-autonomous-toggle.tsx`; visible only for `dev` cohort; owner-write.

## Phase 5 — Tests
- [ ] 5.1 `test/server/debug-event.test.ts`: gate (incl. Flagsmith-null + FLAG_DEBUG_MODE=1 + prd → false) / redaction+wire-bytes-invariant (JSON-embedded fixtures: `{"env":{"X_TOKEN":…}}`, `{"headers":{"Authorization":"Bearer …"}}`, generic no-sentinel, prose `sk-ant-`) / probe-superset coverage / ephemeral + catch-block-no-body (describe blocks); fixtures synthesized only.
- [ ] 5.2 `test/components/debug-stream-panel.test.tsx`: render re-redaction; toggle hidden non-`dev`; member read-only.
- [ ] 5.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean (exhaustiveness across WSMessage / StreamEvent / ws-known-types / render switch).

## Phase 6 — Gates
- [ ] 6.1 `soleur:gdpr-gate` on the diff; acknowledge any Critical.
- [ ] 6.2 `user-impact-reviewer` at PR review (single-user-incident threshold).
- [ ] 6.3 `soleur:preflight` Check 6 (sensitive paths: server/, supabase/, lib/safety).

## Post-merge (operator/automatable)
- [ ] P.1 Apply migration 101 via `web-platform-release.yml#migrate` (no SSH); verify column via Supabase MCP. Migration BEFORE the flag flip.
- [ ] P.2 `soleur:flag-set-role` to create/flip the `debug-mode` segment for the `dev` cohort.
