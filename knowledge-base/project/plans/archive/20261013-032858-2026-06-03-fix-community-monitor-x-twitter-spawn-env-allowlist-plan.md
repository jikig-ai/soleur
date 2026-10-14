---
title: "fix: forward X/Twitter credentials through community-monitor spawn-env allowlist"
date: 2026-06-03
type: fix
status: planned
lane: single-domain
brand_survival_threshold: none
---

# 🐛 fix: X/Twitter shows "disabled" in scheduled community-monitor digest

## Enhancement Summary

**Deepened on:** 2026-06-03
**Sections enhanced:** Overview (precedent diff), Files to Edit (verify-the-negative), Risks & Mitigations (new)
**Gates run:** 4.4 Precedent-Diff, 4.45 Verify-the-Negative + Post-edit self-audit, 4.6 User-Brand Impact (pass), 4.7 Observability (pass), 4.8 PAT-shaped halt (pass), 4.9 UI-wireframe halt (no UI surface — skip)

### Key Improvements
1. **Precedent confirmed:** the fix follows the exact established `<KEY>: process.env.<KEY>` pattern already used for the 7 Discord/Bluesky/LinkedIn vars in the *same* `buildSpawnEnv()` — no novel pattern, sibling precedent is in-file.
2. **Read-vs-write boundary verified against code:** `cron-content-publisher.ts:178` sets `X_ALLOW_POST: "true"` (the publisher posts); the monitor must NOT, and `x-community.sh:611-615` is the posting guard that the omission keeps closed. The read path (`x-community.sh:54+`) needs only the four creds.
3. **Test-file path corrected** to `apps/web-platform/test/server/inngest/cron-community-monitor.test.ts` (the task description's path was wrong).

### New Considerations Discovered
- The four `X_*` vars are already in the Inngest runtime `process.env` (Doppler `prd_scheduled`); this change only widens the in-process forward allowlist — no secret/Doppler change, no new exposure surface beyond the already-trusted subprocess.

## Overview

The 2026-06-03 scheduled community-monitor digest reported X/Twitter as **disabled** even though all four X credentials (`X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET`) are present and verified in Doppler config `soleur/prd_scheduled`.

**Root cause (confirmed against code, not paraphrase):** the community monitor runs as the Inngest function `apps/web-platform/server/inngest/functions/cron-community-monitor.ts`, which spawns `claude --print` behind a **spawn-env allowlist** in `buildSpawnEnv()`. That allowlist (the "PR-11 bucket-ii authorization" addition) forwards `DISCORD_*`, `BSKY_*`, and `LINKEDIN_*` to the subprocess but **omits the four `X_*` vars**. The spawned agent runs `community-router.sh`, whose platform registry entry —

```
"x|x-community.sh|X_API_KEY,X_API_SECRET,X_ACCESS_TOKEN,X_ACCESS_TOKEN_SECRET|"
```

— calls `check_auth()`, which marks the platform **disabled** the moment any one of the four required env vars is empty (`plugins/soleur/skills/community/scripts/community-router.sh:30-34`). Because the four creds never cross the spawn boundary, the subprocess sees them as empty → X is reported disabled. This was a miss in the original PR-11 wiring that added the other three platforms.

**Fix:** add the four `X_*` **read credentials** to the `buildSpawnEnv()` return object. Do **NOT** add `X_ALLOW_POST` — the monitor is digest/read-only and the posting guard (`x-community.sh:611`) must stay closed. Then update the comment block above `buildSpawnEnv()` and extend the spawn-env test.

This is a fresh fix surfaced by an auto-generated digest artifact. **There is no bug-tracking issue — do NOT add a `Closes #N` reference.**

## Research Reconciliation — Spec vs. Codebase

| Task description claim | Codebase reality | Plan response |
| --- | --- | --- |
| Source file `apps/web-platform/server/inngest/functions/cron-community-monitor.ts`, `buildSpawnEnv()` ~lines 208-235 | **Confirmed.** `buildSpawnEnv()` defined at `cron-community-monitor.ts:215`; comment block immediately above at lines ~204-214. | Edit as described. |
| Allowlist forwards Discord/Bluesky/LinkedIn, omits the four X_* | **Confirmed.** Return object lists 7 community keys (`DISCORD_WEBHOOK_URL`, `DISCORD_BOT_TOKEN`, `DISCORD_GUILD_ID`, `BSKY_HANDLE`, `BSKY_APP_PASSWORD`, `LINKEDIN_ACCESS_TOKEN`, `LINKEDIN_PERSON_URN`); no `X_*` keys. | Add four X_* keys. |
| Router `community-router.sh` marks X disabled when creds empty | **Confirmed.** Registry line 14 requires all four; `check_auth()` lines 30-34 returns 1 (disabled) on first empty var. | No router change needed — fix is upstream at the spawn boundary. |
| Test file `apps/web-platform/server/inngest/cron-community-monitor.test.ts` | **WRONG PATH.** Actual file is `apps/web-platform/test/server/inngest/cron-community-monitor.test.ts` (under `test/`, per vitest `include: ["test/**/*.test.ts"]`). | Plan targets the correct path. |
| Do NOT add `X_ALLOW_POST` (read-only monitor) | **Confirmed correct.** `X_ALLOW_POST` is the posting defense-in-depth guard (`x-community.sh:611-613`); it is set to `"true"` only in the *publisher* (`cron-content-publisher.ts:178`), never the monitor. Read paths in `x-community.sh` need only the four creds. | Add only the four read creds; leave `X_ALLOW_POST` out. |

**Premise validation:** No GitHub issue/PR is cited by reference (the symptom is an auto-generated digest, not a tracked issue), so there is no external premise to validate. All cited file/symbol/line artifacts were verified present on the working tree. The only divergence is the test-file path, corrected above.

## User-Brand Impact

**If this lands broken, the user experiences:** the scheduled community-monitor digest continues to report X/Twitter as "disabled," so X mentions/replies are never surfaced — a silent monitoring blind spot on a configured platform. (Same failure as today; a broken fix is a no-op, not a regression.)

**If this leaks, the user's data is exposed via:** N/A for the read-credential addition itself — the four `X_*` vars are forwarded to the same already-trusted `claude --print` subprocess that already receives Discord/Bluesky/LinkedIn creds and `ANTHROPIC_API_KEY`. The allowlist's negative class (no `...process.env` spread, no Doppler/Sentry/Supabase/Stripe secrets) is preserved unchanged.

**Brand-survival threshold:** none — this restores monitoring visibility on a read-only digest path; no user-facing surface, no write/post capability added, no new secret introduced. (threshold: none, reason: read-only credential forwarding to an already-trusted subprocess on an internal cron digest path; no sensitive-path write, no posting capability, no new secret.)

## Files to Edit

1. **`apps/web-platform/server/inngest/functions/cron-community-monitor.ts`**
   - In the `buildSpawnEnv()` return object, add the four read credentials alongside the existing community vars:
     ```ts
     X_API_KEY: process.env.X_API_KEY,
     X_API_SECRET: process.env.X_API_SECRET,
     X_ACCESS_TOKEN: process.env.X_ACCESS_TOKEN,
     X_ACCESS_TOKEN_SECRET: process.env.X_ACCESS_TOKEN_SECRET,
     ```
   - Do **NOT** add `X_ALLOW_POST` (posting stays guarded off; the monitor is read-only).
   - Update the comment block above `buildSpawnEnv()` to list the four `X_*` additions alongside the existing Discord/Bluesky/LinkedIn entries (extend the "PR-11 additions (bucket-ii authorization)" sentence to include the four X_* read creds, and note `X_ALLOW_POST` is deliberately excluded to keep the monitor read-only).

2. **`apps/web-platform/test/server/inngest/cron-community-monitor.test.ts`**
   - Extend the **positive class** `it.each([...])` array in the `"buildSpawnEnv allowlist (PR-11 bucket-ii security surface)"` describe block (currently 7 entries: the Discord/Bluesky/LinkedIn vars) to also include the four X_* keys: `X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET`. The assertion shape is `expect(buildEnvBody).toContain(\`${key}: process.env.${key}\`)`.
   - Add a single assertion that the allowlist does **NOT** contain `X_ALLOW_POST` (read-only invariant), mirroring the negative-class pattern — e.g., `expect(buildEnvBody).not.toContain("X_ALLOW_POST")`. This locks in the read-only intent so a future careless edit can't silently enable posting from the monitor.

## Files to Create

None.

## Open Code-Review Overlap

None. (Checked: no open `code-review` issue body references the two files in this plan.)

## Test Strategy

- Runner: **vitest** (`apps/web-platform` `package.json` → `"test": "vitest"`, CI form `vitest run`). The test file already lives under `test/` matching the node-project include glob `test/**/*.test.ts`.
- Run the existing suite for this file to confirm the four new positive-class rows pass and the new negative-class `X_ALLOW_POST` assertion passes:
  ```
  ./node_modules/.bin/vitest run test/server/inngest/cron-community-monitor.test.ts
  ```
  (invoke from `apps/web-platform/`).
- RED first: adding the four X_* rows to the `it.each` array BEFORE editing the source should fail (`buildEnvBody` does not yet contain `X_API_KEY: process.env.X_API_KEY`). Then add the source keys → GREEN.

## Risks & Mitigations

### Precedent diff (Phase 4.4)

The fix is pattern-bound to an **in-file sibling precedent** — the 7 existing community vars in the same `buildSpawnEnv()` return object. The four new entries are byte-for-byte the same shape:

```ts
// Existing precedent (unchanged, in the same function):
DISCORD_BOT_TOKEN: process.env.DISCORD_BOT_TOKEN,
BSKY_HANDLE: process.env.BSKY_HANDLE,
LINKEDIN_ACCESS_TOKEN: process.env.LINKEDIN_ACCESS_TOKEN,

// New (this plan) — identical pattern:
X_API_KEY: process.env.X_API_KEY,
X_API_SECRET: process.env.X_API_SECRET,
X_ACCESS_TOKEN: process.env.X_ACCESS_TOKEN,
X_ACCESS_TOKEN_SECRET: process.env.X_ACCESS_TOKEN_SECRET,
```

No novel pattern; the existing allowlist is the canonical form. The spawn-env test already asserts this exact `<KEY>: process.env.<KEY>` shape for the precedent vars.

### Verify-the-negative (Phase 4.45)

| Negative claim in plan | Verification | Result |
| --- | --- | --- |
| `buildSpawnEnv()` must NOT contain `X_ALLOW_POST` | `grep -c 'X_ALLOW_POST' cron-community-monitor.ts` | `0` currently — claim holds; the new negative-class test assertion locks it. |
| Monitor is read-only; posting stays guarded | `x-community.sh:611-615` returns 1 unless `X_ALLOW_POST=="true"` | Confirmed — guard closed when X_ALLOW_POST unset (which the plan preserves). |
| Publisher (not monitor) is where posting is armed | `grep -n 'X_ALLOW_POST' cron-content-publisher.ts` → `178: X_ALLOW_POST: "true"` | Confirmed — the read/write boundary is deliberate; monitor must not cross it. |
| Read path needs only the four creds | `x-community.sh:54+` validates `X_API_KEY`…`X_ACCESS_TOKEN_SECRET` for read | Confirmed — forwarding the four creds is sufficient to flip X to "enabled". |
| No `...process.env` spread introduced | negative-class test already asserts `not.toMatch(/\.\.\.process\.env/)` | Unchanged by this fix. |

### Scheduled-work pattern check

Not applicable — no new scheduled job. The Inngest cron `cron-community-monitor.ts` already exists (canonical per ADR-033). This fix only edits its in-process spawn-env allowlist.

## Acceptance Criteria

### Pre-merge (PR)
- [x] `buildSpawnEnv()` return object in `cron-community-monitor.ts` contains all four of `X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET` as `process.env.<KEY>` entries.
- [x] `buildSpawnEnv()` does **NOT** forward `X_ALLOW_POST` (body-scoped invariant; enforced by the test's function-body slice). Note: a file-level `grep -c 'X_ALLOW_POST' …cron-community-monitor.ts` returns `1` — the single match is the intentional comment documenting the exclusion, not a forwarded key.
- [x] The `...process.env` spread is still absent from `buildSpawnEnv()` (negative-class invariant unchanged).
- [x] The comment block above `buildSpawnEnv()` lists the four `X_*` additions and notes `X_ALLOW_POST` is deliberately excluded.
- [x] Positive-class `it.each` in the spawn-env test asserts all four X_* vars are forwarded; negative assertion confirms `X_ALLOW_POST` is absent.
- [x] `./node_modules/.bin/vitest run test/server/inngest/cron-community-monitor.test.ts` passes (run from `apps/web-platform/`).

### Post-merge (operator)
- [ ] None. Credentials are already present in Doppler `soleur/prd_scheduled` (verified) — no Doppler/secret changes. The next scheduled (08:00 UTC) or manually triggered community-monitor run will pick up the new allowlist and report X/Twitter as **enabled**. The `web-platform-release.yml` pipeline restarts the container on merge to `main` touching `apps/web-platform/**`, so no operator restart step is needed.

## Domain Review

**Domains relevant:** Engineering only.

No cross-domain implications detected — this is a single-line spawn-env allowlist correction on an internal read-only cron path. No UI surface (Files to Edit contain no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`), no Product/UX gate, no marketing/legal/finance surface.

## Infrastructure (IaC)

Not applicable. No new server, service, secret, vendor, DNS record, or persistent runtime process. The four `X_*` credentials already exist in Doppler `soleur/prd_scheduled` (verified) and are already injected into the Inngest runtime's `process.env`; this change only widens the in-process allowlist that forwards them to the spawned subprocess. Pure code change against an already-provisioned surface — Phase 2.8 skip condition met.

## Observability

```yaml
liveness_signal:
  what: cron-community-monitor writes a dated digest + creates a "[Scheduled] Community Monitor" GitHub issue every run; X/Twitter now reports "enabled" in the platform-status table
  cadence: daily 08:00 UTC (Inngest cron) + manual trigger
  alert_target: existing output-aware heartbeat (#4730) — turns the monitor RED if a run produces no digest artifact
  configured_in: apps/web-platform/server/inngest/functions/cron-community-monitor.ts
error_reporting:
  destination: Sentry (existing cron instrumentation) + Inngest run logs
  fail_loud: true — output-aware heartbeat gates on artifact presence, not bare spawn exit code
failure_modes:
  - mode: X creds present in Doppler but still reported disabled
    detection: digest platform-status table shows "x  disabled"
    alert_route: visible in the daily digest artifact + Scheduled Community Monitor issue
  - mode: X_ALLOW_POST accidentally forwarded (posting enabled from read-only monitor)
    detection: spawn-env test negative assertion (X_ALLOW_POST absent) fails in CI
    alert_route: CI test failure on the PR
logs:
  where: Inngest run logs + Sentry breadcrumbs for cron-community-monitor
  retention: per existing Inngest/Sentry retention (unchanged)
discoverability_test:
  command: "./node_modules/.bin/vitest run test/server/inngest/cron-community-monitor.test.ts (from apps/web-platform/) — asserts all four X_* forwarded and X_ALLOW_POST absent"
  expected_output: all spawn-env allowlist tests pass (4 new positive rows + X_ALLOW_POST negative assertion green)
```

## Sharp Edges

- The task description names the test file as `apps/web-platform/server/inngest/cron-community-monitor.test.ts`; the **actual** path is `apps/web-platform/test/server/inngest/cron-community-monitor.test.ts` (under `test/`). Editing the wrong (non-existent) path would silently land an untested change. Use the corrected path.
- Do **NOT** add `X_ALLOW_POST` to `buildSpawnEnv()`. It is the posting defense-in-depth guard checked at `x-community.sh:611`; forwarding it would arm posting from a read-only digest path. The negative-class assertion added in this plan locks that out.
- The spawn-env test extracts the `buildSpawnEnv` body via regex `/function buildSpawnEnv\([\s\S]+?\n\}\n/` and greps the slice. The four new keys must be added as `X_API_KEY: process.env.X_API_KEY` (etc.) — the exact `<KEY>: process.env.<KEY>` shape the positive-class assertion checks. A reordered or aliased form (`X_API_KEY: process.env.X_KEY`) would fail.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled with a concrete artifact, exposure vector, and `threshold: none` + reason.

## Roadmap Alignment

Bug fix on the existing scheduled community-monitor capability (already shipped). No roadmap phase change.
