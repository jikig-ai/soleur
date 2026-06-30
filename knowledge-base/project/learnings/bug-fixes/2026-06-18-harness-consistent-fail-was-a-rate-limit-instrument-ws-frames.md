# A Playwright harness's consistent FAIL / "browser keeps dying" was a server-side rate limit — instrument WS frames before blaming the browser

## Problem

The `live-verify` post-deploy harness (`apps/web-platform/scripts/live-verify/run.ts`) kept emitting
`RESULT: FAIL — send did not persist a conversation within budget` against prod, even after the
synthetic principal's onboarding/binding blocker (the un-onboarded → workspace_id NOT-NULL violation)
was fully fixed at the data layer. The dev host's system Chrome 149 also crashed intermittently under
Wayland (`Target page, context or browser has been closed`), so the working hypothesis was "the browser
keeps dying." That framing was wrong twice over.

## Investigation

1. **DB truth first** (`hr-no-dashboard-eyeball-pull-data-yourself`): signed in as the synthetic principal
   and queried its own rows via RLS. Found the org, `workspace_members` (owner), `user_session_state`
   binding, AND `workspaces.repo_url = ready` all present — every server-side precondition the harness
   depends on was healthy. Yet `conversations` count was 0. So the send genuinely wasn't materializing.
2. **Ruled out the usual browser-death causes**: `/dev/shm` was 16G/1% (not the classic "Target page
   closed" cause), no kernel OOM-kill in the window, and the #5511 Wayland flags
   (`--ozone-platform=x11 --disable-gpu`) were applied. A trivial headless launch worked.
3. **Instrumented the actual send** with a WS-frame trace — the decisive step. Reusing the harness's
   exported helpers, drove the real flow with `page.on("websocket")` + `ws.on("framereceived"/"framesent")`
   logging + per-step timing. The trace was unambiguous:

   ```
   +7.9s  WS→  {"type":"start_session"}
   +8.1s  WS←  {"type":"error","message":"Rate limited: too many conversations this hour.","errorCode":"rate_limited"}
   +8.1s  WS→  {"type":"chat","content":"…"}
   +8.2s  WS←  {"type":"error","message":"No active session. Send start_session first."}
   → no conversation persists → harness times out → FAIL
   ```

   The browser was healthy through the send. The server rejected `start_session` via the per-user
   rate limiter (`server/start-session-rate-limit.ts`: 10/user/hour, process-local), tripped by my own
   ~8 repeated debug runs against the same prod ws-handler process. A rate limit is *deterministic*,
   which is exactly why the FAIL was consistent (4/4), not flaky — the opposite of what "browser keeps
   dying" predicts.

## Root cause (two layers)

- **The FAIL:** the harness only polled the `conversations` table and never inspected WS frames, so a
  server-side send REJECTION (`rate_limited` / "No active session") was indistinguishable from a genuine
  rail regression — both surfaced as `FAIL`. Post report-only→blocking flip, a rate-limited run would
  FALSE-FAIL and block a legitimate deploy.
- **The browser death:** a *separate*, secondary symptom. Environmental, not a product/harness defect —
  the dev host launches a desktop-integrated system Chrome (a `systemd app-com.google.Chrome-*.scope`)
  on a memory-pressured Wayland desktop (swap 100% full). The #5511 flags fixed the GPU crash class; the
  residual instability is "interactive desktop is the wrong host for a headless harness," which is why CI
  (clean ubuntu-latest bundled chromium) is the authoritative runner.

## Solution

Subscribe to the app WS (`/ws`, NOT the Supabase realtime socket), parse only the `{type:"error"}` frame
(`parseWsErrorFrame` → `{errorCode,message}` only, never the raw payload — the auth frame carries a token),
and classify: `rate_limited` → `CANT-RUN:rate-limited`; "Send start_session first" → `CANT-RUN:session-rejected`.
`FAIL` is reserved for session-established-but-no-row (the rail-race class). The listener registers before
the first `page.goto` (start_session fires on WS-connect during hydration); the captured error short-circuits
the 30s poll so it wins over the timeout. No workflow change — `web-platform-release.yml` already routes
`CANT-RUN*` to report-only warning level.

## Key insight

When a browser-driven harness fails **consistently** (not flakily) while every server-side precondition
checks out, the bottleneck is almost certainly **server-side rejection of the action, not the browser**.
Flakiness ≈ environment; determinism ≈ logic/policy. Instrument the actual protocol frames
(`page.on("websocket")` framereceived/framesent, or `DEBUG=pw:browser` for process lifecycle) to localize
*where* the action is refused before attributing failure to browser instability. And classify environmental
rejections (rate limits, quota, auth-refused) as CANT-RUN, never as the regression-class FAIL a gate blocks on.

## Session Errors

- **First `/soleur:one-shot` invocation carried contextual `#N` citations (#5391/#5436/#5463).**
  Recovery: caught before worktree creation; scrubbed to date-anchored/descriptive prose and re-invoked.
  Prevention: already covered by the `/soleur:go` "Scrub closed `#N` contextual citations before invoking
  one-shot" sharp edge + `2026-05-25-one-shot-closed-issue-gate-fires-on-contextual-refs.md` — reinforced
  here: when authoring one-shot args yourself, only OPEN work-target issues belong in `#N` form.
- **`worktree-manager.sh remove` is not a subcommand.** Recovery: fell back to `git worktree remove` +
  `git branch -D`. Prevention: the script is cleanup-only by design (`create`/`cleanup-merged`); use raw
  git for single-worktree removal — one-off, no fix.
- **Standalone probe scripts in `/tmp` fail `@supabase/ssr` module resolution.** Recovery: ran them inside
  `apps/web-platform/`. Prevention: place ad-hoc probes in the app dir so its `node_modules` resolves — one-off.
- **(forwarded) deepen-plan Phase 4.7 SSH-reject regex matched a `# NO ssh` annotation in a command value.**
  Recovery: reworded to `# gh-CLI only, no remote shell`. Prevention: gate false-positive, self-resolved — one-off.

## Tags
category: bug-fixes
module: live-verify
