# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-17-fix-live-verify-cookie-auth-plan.md
- Status: complete

### Errors
- One blocked write: IaC Routing Gate (Phase 2.8) flagged AC8's "bootstrap/seeded out-of-band" framing; reviewed (no new infra — prod synthetic-principal bootstrap is pre-existing, owned by #5452/`bootstrap-live-verify.sh`, already terraform-routed), added `iac-routing-ack` opt-out and re-wrote. No other errors.

### Decisions
- Premise validated, NOT a guess-fix. #5485 OPEN; live MCP-browser repro (Phase 1) is the binding gate per the issue.
- Empty-jar / cookie-name / encoding divergences RULED OUT: `@supabase/ssr@0.6.1` source trace proved `signInWithPassword` flushes `setAll` synchronously (jar populated); live MCP fetch confirmed prod `NEXT_PUBLIC_SUPABASE_URL = https://api.soleur.ai` → name `sb-api-auth-token` matches; SSR reader accepts both `base64-` and raw-JSON.
- Primary suspect pinned to injection shape: `run.ts:255-264` discards SSR per-cookie `options` and forces `httpOnly: true`, whereas proven-working refs (`bot-signin.ts`, `e2e/global-setup.ts`) write `httpOnly: false`. Fix scoped to a testable `buildInjectedCookies` helper.
- Threshold `none`; no UI/schema/infra/GDPR surface (`run.ts` under `scripts/`).
- TDD + no-secret-echo preserved as ACs; new unit test under `test/live-verify/`.

### Components Invoked
- Skill: soleur:plan, soleur:deepen-plan
- Agent (Explore): live-verify auth-cookie terrain map
- Agent (general-purpose ×2): verify-the-negative + ssr setAll-timing source trace
- Playwright MCP browser: live prod recon
- Bash: premise validation, gate checks, commit/push
