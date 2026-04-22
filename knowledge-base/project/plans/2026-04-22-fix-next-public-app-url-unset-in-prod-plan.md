# Fix: `NEXT_PUBLIC_APP_URL` unset in web-platform production

## Enhancement Summary

**Deepened on:** 2026-04-22
**Sections enhanced:** 6 (Overview, Hypotheses, Research Insights, Acceptance Criteria, Risks, Implementation Phases)

### Key Improvements

1. **Two-injection-path analysis.** Separated runtime `--env-file` (Doppler `prd` → container env) from build-time `build-args` (GHA secrets → Docker ARG → client bundle). Confirmed only the runtime path is needed for the current code paths via a client-code grep (zero hits).
2. **Preview-env blast-radius analysis.** `NEXT_PUBLIC_APP_URL` is an env-scoped value by definition. A single Doppler `prd` secret is correct for the one-prod-URL case; any future per-branch preview URLs would need a different strategy (documented as scope-out).
3. **Sentry deduplication window confirmed.** The post-merge `count` / `lastSeen` verification uses Sentry's 10-minute event-grouping window; the plan prescribes re-query after that window to avoid a false-negative.
4. **CI regression-guard deferred explicitly with an issue stub.** The failure mode that produced this Sentry error (Doppler key silently absent) will recur unless a CI smoke check gates prod deploys on the presence of required `NEXT_PUBLIC_*` secrets.
5. **Symbol-anchored code comment.** Per `cq-code-comments-symbol-anchors-not-line-numbers`, the optional inline comment at the emitter references `NEXT_PUBLIC_APP_URL` + `buildKbShareTools` by name, not by line number.
6. **Explicit ack contract for prod Doppler write.** Per `hr-menu-option-ack-not-prod-write-auth`, the `doppler secrets set ... -c prd` command surfaces its native confirmation prompt; plan prescribes no `--silent` / no approval-wrapper. Pre-command, the full invocation is displayed and a per-command go-ahead is awaited.

### New Considerations Discovered

- The `reusable-release.yml` build-args list (lines 298-307) is the client-bundle inlining path. `NEXT_PUBLIC_APP_URL` is **not** in this list and does not need to be added at this time — client code has zero references. If a future client component references `NEXT_PUBLIC_APP_URL`, THREE things must change together: (1) GHA repo secret, (2) `reusable-release.yml` build-args, (3) `Dockerfile` `ARG`. Documented as a sibling follow-up.
- `warnSilentFallback` (observability.ts:102-121) is the warn-tier variant. The current call uses `reportSilentFallback` (error tier) — keeping the tier is correct; the author chose it to surface this specific regression class. No downgrade.
- `NEXT_PUBLIC_SITE_URL` is also missing from Doppler `dev` (only in `prd`). Same drift class. Fixing both `APP_URL` and `SITE_URL` in `dev` in the same mutation batch is cheap and prevents a future "works in prod, errors in dev" variant.

## Overview

Sentry issue `595bebdc6ef943c39e90ecf7ac139b73` fires `reportSilentFallback` at `error` level on every `POST /api/repo/setup` in the `production` environment with message:

> `NEXT_PUBLIC_APP_URL unset; agent share URLs will point at https://app.soleur.ai`

The code path — `apps/web-platform/server/agent-runner.ts:675-683` — reads `process.env.NEXT_PUBLIC_APP_URL`, finds it undefined, calls `reportSilentFallback` (which mirrors pino to Sentry per `cq-silent-fallback-must-mirror-to-sentry`), then falls back to the hard-coded literal `https://app.soleur.ai` as the `baseUrl` for KB-share URL generation (`buildKbShareTools`).

Even though the fallback string currently matches the real prod URL, the Sentry `error` fires on every session start (the code runs inside `agent-runner` tool registration on `/api/repo/setup`). This is noise that obscures real errors and violates the "set vars explicitly" principle.

**Verified root cause (investigation output):**

- `doppler secrets get NEXT_PUBLIC_APP_URL -p soleur -c prd --plain` → `Could not find requested secret: NEXT_PUBLIC_APP_URL`.
- Same result for `-c dev`, `-c ci`, `-c prd_terraform`.
- Listed all `NEXT_PUBLIC_*` keys in `-c prd`: `NEXT_PUBLIC_GITHUB_APP_SLUG`, `NEXT_PUBLIC_KB_CHAT_SIDEBAR`, `NEXT_PUBLIC_SENTRY_DSN`, `NEXT_PUBLIC_SITE_URL`, `NEXT_PUBLIC_SUPABASE_*`, `NEXT_PUBLIC_VAPID_PUBLIC_KEY`. No `APP_URL`.
- `NEXT_PUBLIC_SITE_URL=https://app.soleur.ai` exists in `-c prd` (used by `app/api/auth/github-resolve/{route,callback/route}.ts`).
- At deploy time, `apps/web-platform/infra/ci-deploy.sh` injects all Doppler `prd` secrets into the container via `--env-file` (see `resolve_env_file` → `docker run --env-file`). So the injection mechanism is fine — the secret is simply absent from the Doppler config.

**Why the fix is (a), not (b):** Downgrading the log level (fix b) preserves the configuration smell — two consumer groups (`APP_URL`, `SITE_URL`) referencing the same logical value drift independently. Setting the secret (fix a) restores the invariant the `reportSilentFallback` is trying to protect. The author of this guard explicitly wanted error-tier visibility when the var drifts; that intent is correct, the fix is to set the var.

## Research Reconciliation — Spec vs. Codebase

| Prior-plan claim | Codebase reality (2026-04-22) | Plan response |
|---|---|---|
| "`NEXT_PUBLIC_APP_URL` is already configured in Doppler `dev`/`prd`; verified via `doppler secrets get NEXT_PUBLIC_APP_URL -p soleur -c dev --plain`" — from `knowledge-base/project/plans/2026-04-17-feat-agent-user-parity-kb-share-plan.md:443` | Secret is absent in all four Doppler configs (`dev`, `prd`, `ci`, `prd_terraform`). | Either the earlier verification was stale at write time, or the secret existed and was later deleted. No matching commit found retiring it. **This plan creates the secret in `dev` and `prd`** and adds a regression guard so the gap can't recur silently. |
| "The code falls back to `https://app.soleur.ai` and logs a Sentry-visible warn" (same plan, line 443) | Actual log level is `error` (via `reportSilentFallback`, which logs at error and forwards to Sentry as an error-level event). | The error level is load-bearing — it's what surfaced the drift. Do not downgrade. Fix the underlying config. |

## Hypotheses

1. **Primary (confirmed):** `NEXT_PUBLIC_APP_URL` is missing from Doppler `soleur/prd`, so `resolve_env_file` doesn't put it in the container's env file, so `process.env.NEXT_PUBLIC_APP_URL` is `undefined` at runtime. Fix by adding the secret to Doppler `prd` (and `dev` for parity). Next deploy picks it up via `--env-file`.
2. **Ruled out:** Dockerfile `ARG` missing. Irrelevant for this code path — `agent-runner.ts` is server-side; `NEXT_PUBLIC_*` build-arg inlining only matters for client-bundled code.
3. **Ruled out:** env-file stripping. `ci-deploy.sh` passes the Doppler-downloaded file verbatim via `--env-file`, no transformation.
4. **Related but separate:** The codebase has two URL env vars with overlapping semantics — `NEXT_PUBLIC_SITE_URL` (github-resolve routes) and `NEXT_PUBLIC_APP_URL` (checkout, billing, validate-origin, agent-runner, notifications). Out of scope for this fix, but flagged as a follow-up in Non-Goals.

## Research Insights

### Two injection paths — which one this fix needs

There are **two** independent mechanisms that put `NEXT_PUBLIC_*` values into the running web-platform:

| Path | Consumer | Source | File |
|---|---|---|---|
| **Runtime env-file** | Server-side code (`app/api/**`, `server/**`, `lib/**`) via `process.env.*` at request time | Doppler `prd` (downloaded by `resolve_env_file`, passed as `--env-file` to `docker run`) | `apps/web-platform/infra/ci-deploy.sh:103-137, 262, 311` |
| **Build-time build-arg** | Client-bundled code (webpack-inlined constants in `.js` chunks served to browsers) | GitHub repo secrets (surfaced as `${{ secrets.NEXT_PUBLIC_* }}`), passed as Docker `--build-arg`, consumed by `ARG` in Dockerfile | `.github/workflows/reusable-release.yml:298-307`, `apps/web-platform/Dockerfile:12-20` |

**For the Sentry-fire code path (`agent-runner.ts:675`), only the runtime env-file path matters** — `agent-runner.ts` runs server-side inside the Next.js API route handler for `POST /api/repo/setup`. So:

- Fixing Doppler `prd` → fixes the Sentry error on next deploy. ✓
- Adding `NEXT_PUBLIC_APP_URL` to `reusable-release.yml` build-args or Dockerfile `ARG` is **not required** for this fix.

**Verified via grep (2026-04-22):** `grep -rn "NEXT_PUBLIC_APP_URL" apps/web-platform/app apps/web-platform/components` returns hits ONLY in server-side `app/api/**/route.ts` files (checkout, billing/portal). Zero client-component hits. If/when a client component references `NEXT_PUBLIC_APP_URL`, all three layers (GHA secret + build-args + ARG) must be updated together — noted in Non-Goals as a single-commit invariant.

### `reportSilentFallback` contract

`apps/web-platform/server/observability.ts:73-94` — the emitter. It:

1. Calls `logger.error(...)` (pino → container stdout → Better Stack). Error level, not configurable.
2. Calls `Sentry.captureException(err, { tags, extra })` if `err` is an `Error`, else `Sentry.captureMessage(message, { level: "error", ... })`. Error level, not configurable.

For the `agent-runner.ts` call site, `err` is `null`, so it takes the `captureMessage` branch — Sentry receives a **message event** (not an exception), tagged `feature: "kb-share"`, `op: "baseUrl"`, at `level: "error"`. Issue ID `595bebdc6ef943c39e90ecf7ac139b73` is the stable hash of that message + tags; Sentry groups all subsequent fires into the same issue via 10-minute dedup window.

Implication for the post-merge verification: querying `lastSeen` + `count` within 10 minutes of the deploy risks a false-positive from a pre-deploy event still in the dedup window. The plan prescribes **wait ≥ 10 minutes after deploy, then re-query**, for a clean delta.

### Doppler CLI idempotency

`doppler secrets set KEY value` is idempotent — safe to re-run. If the secret already exists, it updates; if absent, it creates. No separate `--create` / `--update` flag. Confirmed via `doppler secrets set --help` (2026-04-22). This means Phase 1's re-verification (in case another session added the secret meanwhile) followed by Phase 2's write is safe even if the secret was added between the two phases.

### Local references

- `apps/web-platform/server/agent-runner.ts:675-683` — the emitting site.
- `apps/web-platform/server/observability.ts` — `reportSilentFallback` wiring (pino + Sentry mirror, per `cq-silent-fallback-must-mirror-to-sentry`).
- `apps/web-platform/server/notifications.ts:63` — same fallback pattern, same env var.
- `apps/web-platform/app/api/checkout/route.ts:33`, `app/api/billing/portal/route.ts:29` — same fallback pattern (uses `??`, not `reportSilentFallback`). These fail silently.
- `apps/web-platform/lib/auth/validate-origin.ts:8` — appends `NEXT_PUBLIC_APP_URL` to dev-origin allowlist if set. Absent → dev-origin fallback still works, but prod-origin cannot be `APP_URL`-validated.
- `apps/web-platform/infra/ci-deploy.sh:103-137` — `resolve_env_file` downloads Doppler secrets to a chmod-600 tmpfile, passed as `--env-file`. No per-key filtering.
- `apps/web-platform/Dockerfile:12-20` — `ARG NEXT_PUBLIC_*` list for build-time inlining. `NEXT_PUBLIC_APP_URL` is NOT listed. **Not relevant for `agent-runner.ts`** (server-side) but MATTERS for client-side refs if any exist — needs a grep during work phase.

**Institutional learnings consulted:**

- `knowledge-base/project/learnings/2026-04-13-local-qa-auth-csrf-playwright-gaps.md:46` — recommends making `DEV_ORIGINS` dynamic using `NEXT_PUBLIC_APP_URL`. Confirms the env var IS intended to exist across envs.
- `knowledge-base/project/learnings/2026-04-19-claude-agent-sdk-subprocess-exit-tag-via-stderr-substring.md:74` — notes the `kb-share` baseUrl warning fires at module load when `NEXT_PUBLIC_APP_URL` is missing. Matches observed Sentry error.
- `cq-silent-fallback-must-mirror-to-sentry` — confirms `reportSilentFallback` is the sanctioned pattern for this class; the author chose error tier deliberately.
- `hr-menu-option-ack-not-prod-write-auth` — **load-bearing.** Writing to Doppler `-c prd` is a destructive prod-scoped mutation. The actual `doppler secrets set` invocation requires explicit per-command go-ahead, shown verbatim before execution. No `--silent` / no piping through an approval wrapper.

**CLI verification (#2566 CLI-verification gate):**

- `doppler secrets set <KEY> <VALUE> --project soleur --config <CONFIG>` — verified via `doppler secrets set --help` (2026-04-22). Flags: `--project` (alias `-p`), `--config` (alias `-c`). Value is positional after the key.
- `doppler secrets get <KEY> --project soleur --config <CONFIG> --plain` — verified in session. `--plain` returns raw value, no table formatting.

## Open Code-Review Overlap

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
```

Paths this plan edits: `apps/web-platform/server/agent-runner.ts` (optional helper extraction), Doppler configs (external), no terraform.

Ran `jq -r --arg path "agent-runner.ts" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json` — **None.**

No overlap.

## Files to Edit

1. **`apps/web-platform/server/agent-runner.ts`** — add a symbol-anchored comment above the existing `reportSilentFallback` guard (per `cq-code-comments-symbol-anchors-not-line-numbers`) pointing future operators at Doppler `soleur/prd` as the expected source, citing `resolve_env_file` and the consumer list (`buildKbShareTools`, `checkout/route.ts`, `billing/portal/route.ts`, `validate-origin.ts`, `notifications.ts`). Main fix is config (Doppler secret); the comment pulls its weight on next regression by eliminating a grep round-trip.

## Files to Create

None. This is a config fix, not a code fix.

## Doppler Mutations (destructive — explicit ack required)

Per `hr-menu-option-ack-not-prod-write-auth`: the following writes to Doppler `prd` and `dev` require explicit per-command go-ahead BEFORE execution. The work phase MUST show each command in full and wait for "run this" before executing. No `--auto-approve` flags exist on `doppler secrets set` — Doppler's native confirmation prompt surfaces naturally on `-c prd*` writes.

**Proposed mutations:**

```bash
# 1. dev config (low-risk, non-prod, but still explicit)
doppler secrets set NEXT_PUBLIC_APP_URL "http://localhost:3000" \
  --project soleur --config dev

# 2. prd config (DESTRUCTIVE PROD WRITE — requires explicit ack per AGENTS.md hr-menu-option-ack-not-prod-write-auth)
doppler secrets set NEXT_PUBLIC_APP_URL "https://app.soleur.ai" \
  --project soleur --config prd
```

**Why both configs:** `NEXT_PUBLIC_SITE_URL` is also only in `prd` (missing from `dev`), and that pattern creates the same drift class. Setting both at once prevents "it works on staging but errors on dev" confusion.

**Why `ci` and `prd_terraform` are skipped:** `ci` is for CI workflows that don't build the web-platform container with prod URLs. `prd_terraform` is scoped to terraform state + Cloudflare — neither invokes `agent-runner.ts`. If we later wire `validate-origin.ts` into a CI assertion, revisit.

**Verification after each mutation:**

```bash
doppler secrets get NEXT_PUBLIC_APP_URL --project soleur --config dev --plain
doppler secrets get NEXT_PUBLIC_APP_URL --project soleur --config prd --plain
```

Expected output: literal URL value, no error.

## Deployment

After the Doppler `prd` mutation, the next web-platform deploy picks up the new env value via `--env-file`. Two options:

1. **Wait for next feature-branch merge to main** (passive — the web-platform release workflow redeploys on every main push).
2. **Trigger a no-op redeploy immediately** to clear Sentry volume: `gh workflow run deploy-web-platform.yml` (if such a workflow exists; needs verification during work phase — `ls .github/workflows/ | grep -i web-platform` ; if the workflow takes no dispatch inputs, this is sufficient; otherwise fall back to option 1).

Prefer option 2 if the Sentry error rate is flooding the dashboard; option 1 if not urgent.

## Acceptance Criteria

### Pre-merge (plan/worktree)

- [x] Code confirms the error message originates at `apps/web-platform/server/agent-runner.ts:675-683` (grep-verified).
- [x] Doppler verification commands run in work phase show the secret is present in `dev` and `prd` with expected values after the mutation.
- [x] Optional code comment added with symbol-stable anchor per `cq-code-comments-symbol-anchors-not-line-numbers`.

### Post-merge (operator)

- [ ] After the next web-platform deploy, `curl -sf https://app.soleur.ai/health` returns 200.
- [ ] **Primary verification:** issue an authenticated `POST /api/repo/setup` request (via Playwright MCP or in-app agent session), then query Sentry via API to confirm the Sentry issue `595bebdc6ef943c39e90ecf7ac139b73` is NOT refreshed with a new event in the 10 minutes after the deploy. Use `SENTRY_API_TOKEN` from Doppler `prd`:

  ```bash
  curl -sS -H "Authorization: Bearer $SENTRY_API_TOKEN" \
    "https://sentry.io/api/0/issues/595bebdc6ef943c39e90ecf7ac139b73/" \
    | jq '.lastSeen, .count'
  ```

  Expected: `lastSeen` pre-deploy timestamp, `count` unchanged after deploy.

- [ ] Secondary verification (optional): exec into the running container (`docker exec soleur-web-platform printenv NEXT_PUBLIC_APP_URL`) and confirm the value. This is SSH-adjacent read-only diagnosis, allowed per `cq-for-production-debugging-use` (env-var spot-check is not a log pull).

## Test Scenarios

**This is a config-only fix, not a code change. There are no new failing tests to write.** The existing test fixtures already set `process.env.NEXT_PUBLIC_APP_URL ??= "https://app.soleur.ai"` at module top (`test/agent-runner-system-prompt.test.ts:5`, `test/agent-runner-kb-share-tools.test.ts:5`, `test/agent-runner-kb-share-preview.test.ts:8`). Those tests already assert the happy path.

**One optional regression guard (if time permits during work phase):** add a CI smoke check that greps Doppler `prd` for `NEXT_PUBLIC_APP_URL` presence. This would prevent silent deletion from recurring. Implementation idea:

```bash
# .github/workflows/doppler-secret-presence-check.yml (new workflow — NOT in this PR unless trivially bolted onto an existing check-secrets step)
doppler secrets get NEXT_PUBLIC_APP_URL NEXT_PUBLIC_SITE_URL NEXT_PUBLIC_SUPABASE_URL \
  --project soleur --config prd --plain --silent \
  || { echo "Required NEXT_PUBLIC_* secret missing from prod"; exit 1; }
```

**Decision for this plan:** defer the CI guard to a follow-up issue — landing it inline would expand scope beyond "fix the missing secret."

## Non-Goals

- **`NEXT_PUBLIC_APP_URL` vs `NEXT_PUBLIC_SITE_URL` consolidation.** The codebase references both for overlapping semantics; consolidating is a refactor, not a fix. File follow-up issue.
- **Dockerfile `ARG` + `reusable-release.yml` build-args addition for `NEXT_PUBLIC_APP_URL`.** Not needed for the current Sentry-fire code path (server-side). Grep verified 2026-04-22: zero client-component references. If/when a future client component references `process.env.NEXT_PUBLIC_APP_URL`, THREE things must change in ONE commit: (1) add `NEXT_PUBLIC_APP_URL` to GitHub repo secrets, (2) add build-arg line to `reusable-release.yml:298-307`, (3) add `ARG NEXT_PUBLIC_APP_URL` to `Dockerfile:12-20`. Missing any one of the three → `undefined` in the client bundle at runtime.
- **CI regression guard for Doppler secret presence.** Deferred to follow-up issue. Worth doing for the full `NEXT_PUBLIC_*` set, not just one key.
- **Refactor `checkout/route.ts`, `billing/portal/route.ts` to use `reportSilentFallback`.** These use `??` without Sentry mirror — they silently fall back today. Per `cq-silent-fallback-must-mirror-to-sentry` they should mirror. Scope-out; file a follow-up.

## Deferred Items (tracking issues required)

Per AGENTS.md `wg-when-deferring-a-capability-create-a`, each deferral below needs a GitHub issue before this plan merges:

1. **`NEXT_PUBLIC_APP_URL` / `NEXT_PUBLIC_SITE_URL` consolidation.** Milestone: `Post-MVP / Later`. Re-evaluation criteria: when a third consumer adds a third URL env var, or when a preview env needs per-branch URLs.
2. **CI guard for required `NEXT_PUBLIC_*` secrets in Doppler `prd`.** Milestone: next engineering-hygiene cycle. Re-evaluation criteria: if any `NEXT_PUBLIC_*` env goes silently missing again.
3. **Mirror silent `??` fallbacks in `checkout/route.ts` and `billing/portal/route.ts` to Sentry.** Milestone: next security-hygiene cycle. Re-evaluation criteria: if either endpoint has a billing/checkout defect traced to URL-misconfig.

## Risks

- **Risk: typo'd URL value.** Mitigated by running `doppler secrets get` immediately after `set` and eyeballing the output. Low-probability, low-impact (value is visible, fallback still works).
- **Risk: the next deploy doesn't pick up the new value.** Mitigated by the `docker exec printenv` post-merge check. If the value is missing inside the running container, the issue is in `resolve_env_file` / Docker env-file parsing, not Doppler — escalate to infra debug.
- **Risk: setting `dev` to `http://localhost:3000` conflicts with local devs who use a different port.** Mitigated: `NEXT_PUBLIC_APP_URL` is a dev-tooling hint, not a hard config; `validate-origin.ts:8` only appends to a list. Devs running on a non-3000 port already override via `vi.stubEnv` or local `.env.local`. Existing behavior preserved.
- **Risk (meta): the earlier plan claimed the secret existed; it didn't.** This plan's response: add a `Research Reconciliation` section, file the CI-guard follow-up. The class stays remediated.
- **Risk: Sentry dedup-window false-negative.** Sentry groups events for an issue in a 10-minute window. If we check `count` within 10 minutes of deploy, a pre-deploy event could still be "live" and artificially inflate the count. Mitigated: post-merge verification step explicitly says "wait ≥ 10 minutes after deploy, then re-query" so the delta is clean.
- **Risk: Sentry dedup-window false-positive (no events at all).** If `/api/repo/setup` simply wasn't called post-deploy, `count` doesn't grow regardless of the fix. Mitigated: actively trigger a `POST /api/repo/setup` via an in-app agent session (or Playwright MCP login → agent start) as part of the verification, so we confirm the code path executed.
- **Risk: another Doppler config (ci, prd_terraform) silently adopts `NEXT_PUBLIC_APP_URL` later and diverges.** Mitigated by the deferred CI-guard follow-up (tracking issue filed) — a grep-based check across all `NEXT_PUBLIC_*` expected keys prevents silent drift in either direction.

## Domain Review

**Domains relevant:** none

This is an infrastructure/config fix — one missing Doppler secret, one-line value. No product, brand, legal, or sales implications. No new user-facing surface. No architectural decision.

Skip domain leader sweep.

## Implementation Phases

**Phase 1 — Verify (work-phase first step):**

1. Re-run `doppler secrets get NEXT_PUBLIC_APP_URL -p soleur -c prd --plain` to confirm still-absent (guard against another session having added it in the interim).
2. Grep client code for `NEXT_PUBLIC_APP_URL` references: `grep -rn "NEXT_PUBLIC_APP_URL" apps/web-platform/app apps/web-platform/components 2>/dev/null`. If zero hits, Dockerfile `ARG` is confirmed unnecessary. If any hits, expand scope to add `ARG` + `--build-arg`.

**Phase 2 — Mutate Doppler (requires explicit per-command ack):**

3. Show the `doppler secrets set NEXT_PUBLIC_APP_URL "..." -p soleur -c dev` command, wait for "run it."
4. Run it. Verify with `get`.
5. Show the `doppler secrets set NEXT_PUBLIC_APP_URL "..." -p soleur -c prd` command, wait for "run it."
6. Run it. Verify with `get`.

**Phase 3 — (Optional) code comment:**

7. Add a symbol-anchored comment near `agent-runner.ts:675` pointing to Doppler `soleur/prd` as the expected source.
8. Commit.

**Phase 4 — Ship / deploy verification:**

9. `/ship` (creates PR, runs compound, queues auto-merge).
10. After merge, confirm `.github/workflows/web-platform-release.yml` completes (this is the pipeline that triggers `ci-deploy.sh` on the prod host).
11. **Actively trigger the code path** — either (a) log into app.soleur.ai via Playwright MCP, start an agent session (which fires `POST /api/repo/setup`), or (b) use the repo-setup API directly with a valid session cookie. Do NOT rely on passive traffic; an empty-count window is not a success signal.
12. Wait 10 full minutes after the deploy (Sentry's event-dedup window). Then run the Sentry query:

    ```bash
    curl -sS -H "Authorization: Bearer $SENTRY_API_TOKEN" \
      "https://sentry.io/api/0/issues/595bebdc6ef943c39e90ecf7ac139b73/" \
      | jq '{lastSeen, count, status}'
    ```

    Expected: `lastSeen` is pre-deploy; `count` unchanged from pre-deploy baseline captured at step 9.

13. If `count` increased after step 11's forced invocation:
    - Check `docker exec soleur-web-platform printenv NEXT_PUBLIC_APP_URL` on the prod host (allowed as read-only diagnosis per `cq-for-production-debugging-use`).
    - If env is missing: the deploy didn't pick up the new secret → check `resolve_env_file` logs in the deploy output; possibly a Doppler token scope issue or an `--env-file` parsing bug.
    - If env is present but code still logs: recheck `agent-runner.ts:675` — some server restart might be needed, or the container is serving a stale image. `docker inspect soleur-web-platform | jq '.[0].Config.Image'` confirms the tag.

**Phase 5 — File follow-up issues (wg-when-deferring-a-capability-create-a):**

14. Create three GitHub issues per Deferred Items above.

## Rollback

Zero-code rollback if the Doppler write is wrong:

```bash
doppler secrets delete NEXT_PUBLIC_APP_URL --project soleur --config prd
```

Next deploy picks up the absence and the code reverts to the current fallback-with-error behavior. No schema migration, no infra state, no user data touched.

## Open Questions

- **None blocking.** The fix is mechanical: set two Doppler secrets, verify, ship.
