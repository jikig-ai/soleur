---
title: "Restore Tier-2 deferred crons — scoped to the un-gated subset (cron-ux-audit)"
type: feat
issue: "#5199"
related: "#5046 #5018 #5138 #5089 ADR-033 ADR-052 ADR-054"
branch: feat-one-shot-restore-tier2-deferred-crons-5199
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
created: 2026-06-12
---

# Restore Tier-2 deferred crons — scoped to the un-gated subset

## Enhancement Summary

**Deepened on:** 2026-06-12 · **Agents:** verify-the-negative (sonnet), security-sentinel, Explore ×2 (egress/hook plumbing + cron-restoration learnings).

### Key Improvements (load-bearing corrections, all verified against code)
1. **P0 — the hook never receives `cronName`** (`cron-bash-allowlist-hook.mjs:418` `loadAllowlist(process.argv[2])`; only argv is the allowlist file path). The original Phase 2 `if (cronName === "cron-ux-audit")` mechanism is **infeasible**. Rewrote Phase 2 to a **file-driven** MCP-allow (extend `cron-allow.txt`), the only design where per-cron scoping is structurally true rather than test-asserted-but-globally-true.
2. **P1 — `browser_navigate` re-opens the secret→allowlisted-host exfil path.** Arbitrary URL + firewall-allowed `api.soleur.ai` + bot session in `storage-state.json` = clean exfil. Added a **URL-origin guard** (the load-bearing close) + `storage-state.json` read-deny. The route-list.yaml is a soft prompt convention, NOT an enforced boundary.
3. **P2→P1 — `@playwright/mcp@latest` is unpinned runtime npx-fetch**; `registry.npmjs.org` is NOT in the egress allowlist (verified) → blocked-egress OR must be image-baked. Pin + bake.
4. **Cross-cron negative test required** — proves the MCP-allow does not leak to the 2 restored issue-creator crons.

### New Considerations Discovered
- The firewall allowlisting `soleur.ai`/`api.soleur.ai` is NOT reassurance for ux-audit — it is precisely what makes them viable exfil sinks for a relaxed `browser_navigate`.
- Token narrowing to `{contents:read, issues:write}` confirmed correct (no write needed); the `gh api -f body=@file` attachment step (SKILL.md) must be caught by the Phase-0 bash-verb enumeration (the hook's `argumentInjectionReason` denies `=@`).

🛡️ Follow-up to #5046 (Tier-2 boundary, MERGED via #5089 / web-v0.119.0). This issue (#5199) is the durable anchor for restoring the **9 crons still in `TIER2_DEFERRED_CRONS`** (`apps/web-platform/server/inngest/functions/_cron-shared.ts:337-347`) that produce no weekly operator output.

**Restoration recipe (validated by #5046 PR-2):** per cron, pair removal from `TIER2_DEFERRED_CRONS` with (1) a finite per-construct evidence-gated `CRON_BASH_ALLOWLISTS` entry, (2) the narrowed `DEFAULT_CRON_TOKEN_PERMISSIONS` (or `ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS`) token, (3) validation via `/soleur:trigger-cron` over the identical containment path (Task → relax-minimal hook → `runHookSelfTest` → issue-creator token → DOCKER-USER firewall egress).

## Scope Decision (THIS PR) — read first

**This PR restores exactly ONE cron: `cron-ux-audit`.** The other 8 are deferred back to #5199 with explicit gating notes. The scope was narrowed from "9 crons" / "candidates bug-fixer + ux-audit" after reading the code. The determination:

| Cron | `mergeMode` / write surface | #5138-gated? | This PR |
|---|---|---|---|
| cron-campaign-calendar | `safeCommitAndPr` default → **auto** | **YES** (in #5138's literal 7-cron list) | **Defer** |
| cron-competitive-analysis | `safeCommitAndPr` default → **auto** | **YES** | **Defer** |
| cron-growth-audit | `safeCommitAndPr` default → **auto** | **YES** | **Defer** |
| cron-seo-aeo-audit | `safeCommitAndPr` default → **auto** | **YES** | **Defer** |
| cron-content-generator | `safeCommitAndPr` default → **auto** | **YES** | **Defer** |
| cron-growth-execution | `safeCommitAndPr` default → **auto** | **YES** | **Defer** |
| cron-community-monitor | `safeCommitAndPr` default → **auto** | **YES** (#5199 mis-grouped it under "firewall-dependent"; #5138's body lists it in the gated 7) | **Defer** |
| cron-bug-fixer | `enablePullRequestAutoMerge` on `bot-fix/*` PRs | **YES** (auto-merge silent-disarm — same risk #5138 guards; see Sharp Edge) | **Defer** |
| **cron-ux-audit** | **issue-only** (`gh issue create`; "Do NOT push, Do NOT commit"); NO `safeCommitAndPr`, NO auto-merge | **NO** | **RESTORE** |

**Why only ux-audit:** #5138 (stale `ci/*` bot-PR watchdog — still OPEN, `closedByPullRequestsReferences: []`, NOT yet built; #5133 only consolidated pipelines onto `safeCommitAndPr`) gates "ANY of the 7 `mergeMode:"auto"` crons MUST land this watchdog first." All 6 PR-flow crons default to `mergeMode:"auto"` (none sets it explicitly; `_cron-safe-commit.ts:723` `config.mergeMode ?? "auto"`), and `cron-community-monitor` is explicitly named in #5138's gated list. `cron-bug-fixer` uses the same `enablePullRequestAutoMerge` silent-disarm primitive (`cron-bug-fixer.ts:447`), so even though its `bot-fix/*` head branch falls outside #5138's literal `ci/*`/`self-healing/auto-*` scan, restoring it re-opens the exact silent-stale window #5138 exists to close. `cron-ux-audit` is the only deferred cron with **no PR/auto-merge surface at all** — it is genuinely un-gated by #5138.

**Building the #5138 watchdog is OUT of scope for #5199** — it belongs in #5138 itself. This PR does not touch it.

## Research Reconciliation — Issue/Prompt claim vs. Codebase

| Claim (from #5199 / one-shot prompt) | Reality (verified) | Plan response |
|---|---|---|
| "Candidates: cron-bug-fixer, cron-ux-audit are potentially un-gated" | bug-fixer fires `enablePullRequestAutoMerge` (`cron-bug-fixer.ts:447`) — auto-merge silent-disarm risk = #5138's concern, on `bot-fix/*` branches (`:311`). Only ux-audit has no auto-merge surface. | Restore ux-audit only; defer bug-fixer with auto-merge-risk note. |
| ux-audit is "firewall-dependent (non-GitHub egress)" — implies firewall work needed | The egress firewall (#5089/ADR-052) **already allowlists** `soleur.ai`/`app.soleur.ai`/`api.soleur.ai` (`cron-egress-allowlist.txt:56-58`) — ux-audit's Playwright targets. NO firewall edit needed. | No `cron-egress-allowlist.txt` change. The genuine blocker is the **hook**, not the firewall (see next row). |
| Recipe = "issue-creator allowlist + narrowed token" (mirror agent-native-audit/legal-audit) | ux-audit ALSO needs `mcp__playwright__browser_*` tools (`cron-ux-audit.ts:76`), which the relax-minimal hook **denies** via its catch-all (`cron-bash-allowlist-hook.mjs:397-402`: "any mcp__* tool … denied … pure egress surface"). The 2 restored crons need no MCP. | This PR's novel work is a **per-cron `mcp__playwright__*` hook relaxation** — an evidence-gated security decision beyond the issue-creator recipe. See Phase 2 + Sharp Edges. |
| ux-audit mints the narrowed token already | ux-audit currently mints the **FULL** installation token (`cron-ux-audit.ts:227` — no `permissions` arg). | Narrow to `ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS` (`{contents:read, issues:write}` — sufficient for `gh issue create`+`gh label`). |
| ux-audit files issues on restore | ux-audit currently spawns with `UX_AUDIT_DRY_RUN:"true"` (`cron-ux-audit.ts:308`) — dry-run writes findings to stdout, files NO issue. | The restore must flip `UX_AUDIT_DRY_RUN` to `"false"` (or wire it from env) AND adopt the output-aware heartbeat (`resolveOutputAwareOk`) so a no-issue run is not silent-green. Confirm the dry-run→live flip is the intended restore behavior at /work. |
| `CRON_BASH_ALLOWLISTS` lives in `_cron-shared.ts` | It lives in `_cron-claude-eval-substrate.ts:145`; `TIER2_DEFERRED_CRONS` is in `_cron-shared.ts:337`. | Edit both files. |

## Overview

`cron-ux-audit` (`apps/web-platform/server/inngest/functions/cron-ux-audit.ts`) screenshots live bot routes via Playwright MCP and files capped UX-decay issues (`/soleur:ux-audit`). It is Tier-2 deferred — `deferIfTier2Cron` (`:214`) early-returns before any spawn, so the founder receives no weekly UX Audit issue.

Restoring it through the validated containment path requires:

1. **Remove `cron-ux-audit` from `TIER2_DEFERRED_CRONS`** (`_cron-shared.ts:337-347`).
2. **Add a finite `CRON_BASH_ALLOWLISTS["cron-ux-audit"]` entry.** Its bash surface is issue-only (`gh issue create`/`gh issue list`/`gh label *`) — `ISSUE_CREATOR_BASH_ALLOWLIST` (`_cron-claude-eval-substrate.ts:138`) is the precedent, evidence-gated against the prompt's `gh issue create … --milestone` (`cron-ux-audit.ts:91-104`). Verify there are no other bash verbs in the `/soleur:ux-audit` SKILL.md the prompt invokes.
3. **Relax the hook to allow `mcp__playwright__*` for this cron** — the novel, load-bearing decision (see Phase 2). The relax-minimal hook keeps `mcp__*` denied; ux-audit cannot run without browser-navigate. This is a per-cron MCP allowance, NOT a blanket `mcp__*` allow.
4. **Narrow the token** to `ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS` + `repositories:[REPO_NAME]` (`cron-ux-audit.ts:227`).
5. **Flip out of dry-run** so it files its `scheduled-ux-audit`-labeled issue, and gate the heartbeat on output (`resolveOutputAwareOk`) — confirm intent.
6. **Validate via `/soleur:trigger-cron cron/ux-audit.manual-trigger`** (ux-audit is in the manual-trigger allowlist, `cron-manifest.ts:60`) over the full containment path.

## User-Brand Impact

**If this lands broken, the user experiences:** no weekly UX Audit issue (the status quo, unchanged) OR — worse — a runaway Playwright session that egresses to an allowlisted host the agent shouldn't reach, or a contained-cron regression where the hook relaxation accidentally widens `mcp__*` for OTHER restored crons.

**If this leaks, the user's data/workflow is exposed via:** the `mcp__playwright__browser_navigate` relaxation. Concrete vector (deepen-plan security review): `browser_navigate` takes an arbitrary URL; the firewall allows `api.soleur.ai`; the bot's live Supabase session tokens sit in `storage-state.json` in the workspace and in the browser context. A prompt-injection payload in audited DOM/marketing copy could steer `browser_navigate("https://api.soleur.ai/?x=<session-token>")` — a clean secret-in-querystring exfil to an allowlisted host, bypassing the hook's `mcp__*` deny that exists to sever exactly that path. The firewall (content-blind, off-allowlist-only) does NOT subsume this. THIS is closed only by (a) the URL-origin guard, (b) `storage-state.json` read-deny, (c) per-cron file-driven scoping — all in Phase 2. Scoping alone is necessary but NOT sufficient; the URL-origin guard is the load-bearing close.

**Brand-survival threshold:** single-user incident (the cron runs the agent against the live prod app with a GitHub-App token; a containment regression is a single-user-incident-class exposure). `requires_cpo_signoff: true`.

## Implementation Phases

### Phase 0 — Preconditions (verify before any edit)
- `gh issue view 5138 --json state,closedByPullRequestsReferences` → confirm still OPEN + zero closing PRs (re-verify the gate at /work; if #5138 has landed, RE-SCOPE to include the auto crons).
- Read `plugins/soleur/skills/ux-audit/SKILL.md` and `references/route-list.yaml` — enumerate EVERY bash verb the prompt's `/soleur:ux-audit` invocation can emit. The `CRON_BASH_ALLOWLISTS["cron-ux-audit"]` entry must finitely cover all of them. If the SKILL emits a verb outside `ISSUE_CREATOR_BASH_ALLOWLIST` (e.g. a `git`/`gh api`/screenshot-upload bash step), extend the entry per-construct (evidence-gated) — do NOT widen to a metachar drop.
- Confirm `route-list.yaml` targets resolve via `NEXT_PUBLIC_APP_URL` (`cron-ux-audit.ts:290`) to `app.soleur.ai`/`soleur.ai` — already firewall-allowlisted (`cron-egress-allowlist.txt:56-58`). No firewall edit.
- Read `cron-bash-allowlist-hook.mjs:332-403` switch to confirm the exact insertion point for the per-cron `mcp__playwright__*` allow.

### Phase 1 — Token narrowing + dry-run flip (`cron-ux-audit.ts`)
- Narrow the mint at `:227` to `{ permissions: ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS, repositories: [REPO_NAME] }` (import both from `_cron-shared.ts`).
- Flip `UX_AUDIT_DRY_RUN` from hardcoded `"true"` (`:308`) to live (`"false"`), OR wire from env with a safe default. **Confirm intent at /work** — the restore is meaningless if it stays dry-run, but a wrong flip files issues prematurely. Adopt `resolveOutputAwareOk` for the heartbeat if ux-audit does not already (it legitimately files 0 issues on a clean run — mirror strategy-review's errors-based heartbeat OR file a FAILED self-report via `ensureScheduledAuditIssue`; pick the shape ux-audit's "caps + may file nothing" semantics need).

### Phase 2 — File-driven per-cron `mcp__playwright__*` hook relaxation — LOAD-BEARING (REVISED per deepen-plan security review)

**P0 correction (deepen-plan):** The hook does NOT receive `cronName`. Its only input is `argv[2]` = the allowlist file path (`cron-bash-allowlist-hook.mjs:418` `loadAllowlist(process.argv[2])`; invocation baked at `_cron-claude-eval-substrate.ts:223-226` as `node <hook> <allowlist>`). A `if (cronName === "cron-ux-audit")` branch in the hook **cannot compile** — the only mechanism that keeps per-cron scoping *structurally* true (not test-asserted-but-globally-true) is the **per-cron `cron-allow.txt` file**, which is delivered per-cron and is itself read-denied to the agent (`.claude/` is in `SECRET_PATH_PATTERNS`, `:86`).

Mechanism (mirrors the existing Bash-allowlist file-driven design):
- Extend the `cron-allow.txt` format with an MCP-allow section (e.g. lines prefixed `mcp:` or a `[mcp-allow]` block). For `cron-ux-audit`, list the 5 declared tools (`mcp__playwright__browser_navigate`, `browser_take_screenshot`, `browser_resize`, `browser_close`, `browser_wait_for` — `cron-ux-audit.ts:76`). The 2 issue-creator crons' files carry NO mcp lines → they stay fully `mcp__*`-denied (the comment at `:394-395` invariant holds for them).
- In the hook, parse the MCP-allow lines into an `mcpAllowPrefixes` set. In the `default:` catch-all (`:397`), BEFORE denying: if `tool` starts with `mcp__` AND is in `mcpAllowPrefixes`, evaluate the **URL-origin guard** (next bullet) then allow; else deny. Keep `WebFetch`/`WebSearch` always denied.
- Wire the MCP-allow lines through `setupEphemeralWorkspace` / the `CRON_BASH_ALLOWLISTS` write path (`_cron-claude-eval-substrate.ts:403-408`) — likely a parallel `CRON_MCP_ALLOWLISTS` map or an extension of the per-cron entry.

**P1 correction — `browser_navigate` URL-origin guard (the only thing that closes the exfil leg):** `mcp__playwright__browser_navigate` takes an ARBITRARY URL. The egress firewall is content-blind and allows `api.soleur.ai`, so `browser_navigate("https://api.soleur.ai/?x=<secret>")` is a clean secret-in-querystring exfil to an allowlisted host — the exact (secret-in-context)+(egress) pair the hook exists to sever. The route-list.yaml is a SOFT prompt convention (`UX_AUDIT_PROMPT` "Run /soleur:ux-audit against the route list" + SKILL.md), NOT an enforced boundary; a prompt-injection payload in audited DOM/marketing copy can steer navigation. The hook MUST parse `tool_input.url` for `mcp__playwright__browser_navigate` and deny when the origin is not the `NEXT_PUBLIC_APP_URL` origin (and deny secret-bearing query strings to it). This origin must be passed to the hook (via the allowlist file or a new argv — design at /work; the file is preferred since the agent cannot read it).

**P1 correction — session-secret read-deny:** The bot signs in and writes live Supabase access/refresh tokens to `storage-state.json` in the workspace (`cron-ux-audit.ts:285,299`), loaded into the browser context. `SECRET_PATH_PATTERNS` (`:74-86`) does NOT cover `storage-state.json` or `tmp/ux-audit/` — add them, so the agent cannot Read the session then encode it into an allowlisted `gh` bash call.

**P2/P1 correction — pin `@playwright/mcp` + npm egress:** ux-audit spawns `npx @playwright/mcp@latest` (`cron-ux-audit.ts:256`). `registry.npmjs.org` is NOT in `cron-egress-allowlist.txt` → at runtime this is either (a) blocked egress → cron hangs/fails, or (b) the package must be image-baked/cached (like Chromium per ADR-033 I4). `@latest` is also an unpinned supply-chain dep running in-process with `GH_TOKEN` + the bot session. Pin to an exact version AND image-bake it (mirror the Chromium discipline at `cron-ux-audit.ts:14-15`) OR allowlist `registry.npmjs.org`+pin. Confirm which at /work by checking whether the prod image pre-installs `@playwright/mcp`.

**Self-test (merge precondition):** Extend `runHookSelfTest` (`_cron-claude-eval-substrate.ts:426`) — positive: `mcp__playwright__browser_navigate` to the app origin is ALLOWED for ux-audit; negative: off-origin/secret-query navigate is DENIED, and an off-list mcp tool (`browser_run_code_unsafe`) + `WebFetch` are DENIED. A fail-open aborts the cron.

**Sign-off:** First cron with an `mcp__*` allowance — CPO + security sign-off required (single-user-incident threshold). Document WHY the firewall does not subsume it (content-blind) and the 4 enforced bounds (file-driven per-cron, explicit 5-tool set, URL-origin guard, session-secret read-deny).

### Phase 3 — Allowlist + defer-set edits
- Add `cron-ux-audit` to `CRON_BASH_ALLOWLISTS` (`_cron-claude-eval-substrate.ts:145`) — `ISSUE_CREATOR_BASH_ALLOWLIST` unless Phase 0 found extra verbs.
- Remove `cron-ux-audit` from `TIER2_DEFERRED_CRONS` (`_cron-shared.ts:337-347`).
- Update the `TIER2_DEFERRED_CRONS` block comment (`:311-336`) and the deferral-guard set: the remaining 8 stay deferred; correct the prose so it no longer implies bug-fixer/community-monitor are "firewall-dependent" un-gated (they are #5138-gated). Update the runbook (`cloud-scheduled-tasks.md` cron-containment section) to match the new count (8 deferred).

### Phase 4 — Tests (write failing first per `cq-write-failing-tests-before`)
- Hook unit test: with `cron-ux-audit`'s allowlist file, assert it denies a canonical exfil bash payload, allows `gh issue create`, allows the 5 declared Playwright tools navigating to the app origin, DENIES `browser_navigate` to an off-origin/secret-query URL, DENIES an off-list mcp tool (`browser_run_code_unsafe`) + WebFetch, and DENIES a Read of `storage-state.json`.
- **CROSS-CRON NEGATIVE (required — the only test that proves scoping is real, not globally-true):** run the hook with `cron-legal-audit`'s (or `cron-agent-native-audit`'s) allowlist file and assert `mcp__playwright__browser_navigate` is DENIED. A global-allow implementation would pass the within-ux-audit positive but FAIL this.
- Parity test: `cron-ux-audit` present in `CRON_BASH_ALLOWLISTS` (+ the new MCP-allow map) ⇔ absent from `TIER2_DEFERRED_CRONS`.
- Token test: ux-audit mints `ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS`.

### Phase 5 — Live validation
- `/soleur:trigger-cron cron/ux-audit.manual-trigger` (dry-run first if supported, then live). Confirm: hook self-test passes, Playwright navigates to the live app, a `scheduled-ux-audit` issue is filed (or capped-out cleanly), the heartbeat is GREEN on output, and no `egress-blocked:`/`egress-dns-exfil:` log fires.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `cron-ux-audit` removed from `TIER2_DEFERRED_CRONS` (`_cron-shared.ts`) AND present in `CRON_BASH_ALLOWLISTS` (`_cron-claude-eval-substrate.ts`) — a parity test asserts the biconditional.
- [ ] `cron-ux-audit.ts` mints `ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS` + `repositories:[REPO_NAME]` (not the full grant).
- [ ] Hook allows the 5 declared `mcp__playwright__browser_*` tools for `cron-ux-audit` via the **per-cron `cron-allow.txt` MCP-allow section** (NOT a `cronName` branch — the hook never sees cronName); denies all other `mcp__*` and `WebFetch`/`WebSearch`; a unit test + the cross-cron negative test prove scoping.
- [ ] `browser_navigate` URL-origin guard: hook denies navigation to any origin other than `NEXT_PUBLIC_APP_URL`'s, and denies secret-bearing query strings; unit-tested.
- [ ] `storage-state.json` + `tmp/ux-audit/` added to `SECRET_PATH_PATTERNS`; unit-tested (Read denied).
- [ ] `@playwright/mcp` pinned to an exact version (not `@latest`) AND image-baked OR `registry.npmjs.org` allowlisted — confirm the prod image pre-installs it.
- [ ] `runHookSelfTest` gains positive (app-origin navigate allowed) + negative (off-origin/off-list mcp/WebFetch denied) probes for ux-audit; throws (aborts cron) on fail-open.
- [ ] The 8 remaining crons stay in `TIER2_DEFERRED_CRONS`; the block comment + runbook reflect "8 deferred" and correct the bug-fixer/community-monitor gating prose.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; `./node_modules/.bin/vitest run <touched test paths>` green.
- [ ] PR body uses `Ref #5199` (NOT `Closes` — #5199 is the durable anchor for the remaining 8; it stays open) and notes #5138 must land before the auto crons.

### Post-merge (operator/automated)
- [ ] After deploy (`web-platform-release.yml` restarts the container on merge — function-desync remediated by the merge itself), run `/soleur:trigger-cron cron/ux-audit.manual-trigger` live: confirm a `scheduled-ux-audit` issue is filed (or clean cap-out), GREEN Sentry monitor `scheduled-ux-audit`, no egress-blocked log. Automation: feasible via the trigger-cron skill — bake into /soleur:ship post-merge.

## Domain Review

**Domains relevant:** Engineering (infra/security), Product (UX-audit output is a product-quality signal).

### Engineering (infra/security)
**Status:** reviewed
**Assessment:** The `mcp__playwright__*` hook relaxation is a new egress-surface decision; the firewall (content-blind) does not subsume it. CTO/security review required at deepen-plan (security-sentinel + architecture-strategist) given single-user-incident threshold — they catch substance-level findings (e.g. arbitrary-URL navigate, secret-in-context-then-POST) that style review cannot.

### Product/UX Gate
**Tier:** none
**Decision:** N/A — this restores a producer cron's output; it implements NO user-facing UI surface (no `components/**/*.tsx`, no `app/**/page.tsx`). The `/soleur:ux-audit` output is a GitHub issue, not a rendered page. Mechanical UI-surface override did NOT fire (Files-to-Edit are all `server/`/`infra` code).
**Pencil available:** N/A (no UI surface)

## Infrastructure (IaC)
No new infrastructure. The egress firewall (`cron-egress-allowlist.txt`, DOCKER-USER chain, ADR-052) already allowlists ux-audit's targets (`:56-58`) — no `.tf`/allowlist edit. The hook + cron config ship via the git clone (tracked tree) and deploy via `web-platform-release.yml` on merge. No server provisioning, no new secret, no vendor.

## Observability
```yaml
liveness_signal:    Sentry Crons monitor "scheduled-ux-audit" (postSentryHeartbeat) / weekly cadence / RED on miss / configured_in apps/web-platform/infra/sentry/cron-monitors.tf
error_reporting:    reportSilentFallback → Sentry (op: scheduled-output-missing / verify-output-failed); fail_loud yes (runHookSelfTest throws on fail-open → FAILED self-report issue via ensureScheduledAuditIssue)
failure_modes:
  - {mode: hook fail-open on mcp relaxation, detection: runHookSelfTest negative probe throws pre-spawn, alert_route: cron aborts → no spawn → next-run miss → RED monitor}
  - {mode: Playwright egress to off-allowlist host, detection: nftables egress-blocked/egress-dns-exfil log + cron-egress-alarm.sh, alert_route: Sentry egress_blocked}
  - {mode: spawn exits 0 but files no issue, detection: resolveOutputAwareOk → scheduled-output-missing, alert_route: RED scheduled-ux-audit monitor}
logs:               Sentry events (op-slugged) + nftables egress log (host journald); retention per existing Sentry/Better Stack config
discoverability_test:
  command: /soleur:trigger-cron cron/ux-audit.manual-trigger  (then read Sentry monitor scheduled-ux-audit + the scheduled-ux-audit issue label — NO ssh)
  expected_output: GREEN monitor + a scheduled-ux-audit issue updated in the run window (or clean cap-out with no scheduled-output-missing event)
```

## Risks & Mitigations (precedent-diff — Phase 4.4)

**Precedent for the restoration pattern exists** (not novel): the relax-minimal hook + per-cron `CRON_BASH_ALLOWLISTS` + narrowed token + `runHookSelfTest` is the exact #5046 PR-2 shape that restored `cron-agent-native-audit` + `cron-legal-audit` (`_cron-claude-eval-substrate.ts:172-181`, `ISSUE_CREATOR_BASH_ALLOWLIST` `:138`, `ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS` `_cron-shared.ts:135`). ux-audit's bash surface mirrors theirs (issue-creator).

**The MCP-allow extension IS novel** — no cron has an `mcp__*` allowance today; the hook comment (`:394-395`) states `mcp__*` stays denied because "no restored cron needs them." This plan is the first exception, so the file-driven mechanism + URL-origin guard + session read-deny are new code with NO sibling precedent — flagged for security/CPO scrutiny. The closest precedent is the existing per-cron Bash allowlist file mechanism (`:403-408`), which this extends rather than invents (same delivery channel, same read-deny property).

**Scheduled-work precedent (Phase 4.4):** This restores an EXISTING Inngest cron (`cron-ux-audit.ts`, registered among 42 cron functions) — Inngest is canonical per ADR-033. No GH Actions cron, no new trigger mechanism. Correct.

## Sharp Edges
- **A plan whose `## User-Brand Impact` section is empty or `TBD` will fail `deepen-plan` Phase 4.6 — this section is filled.**
- **The `mcp__playwright__*` relaxation is the first MCP allowance in the containment hook.** Do NOT widen to a blanket `mcp__*` allow — scope it to `cron-ux-audit` AND the explicit 5-tool set. A blanket allow re-opens the egress surface for the 2 already-restored issue-creator crons and any future Task-class cron. The hook's existing comment (`:395`) explicitly states `mcp__*` stays denied "no restored cron needs them" — this PR is the exception that proves the rule, so the relaxation must be cron-conditional.
- **bug-fixer is NOT safely un-gated despite `bot-fix/*` falling outside #5138's `ci/*`/`self-healing/auto-*` scan.** It fires `enablePullRequestAutoMerge` (`cron-bug-fixer.ts:447`), the same silent-disarm-on-conflict primitive #5138 guards. Restoring it without the watchdog re-opens the invisible-stale-PR window. Defer it to #5199 with this note; if its restoration is wanted, EITHER #5138 lands first OR #5138's scan is extended to `bot-fix/*`. Do not silently restore.
- **ux-audit currently spawns `UX_AUDIT_DRY_RUN:"true"`** — restoring without flipping it produces a contained-but-output-less cron (still no weekly issue). Confirm the dry-run→live flip is intended; a heartbeat that goes GREEN in dry-run while filing nothing is a silent-no-op the output-aware heartbeat must catch.
- **At single-user-incident threshold, run deepen-plan** (security-sentinel + architecture-strategist + data-integrity-guardian) — plan-review (DHH/Kieran/Simplicity) is structurally blind to the egress-surface / secret-in-context substance findings this hook relaxation carries. (Done — deepen-plan caught P0 hook-plumbing + P1 exfil-vector findings; see Enhancement Summary.)
- **The hook is cron-agnostic — do NOT branch on `cronName` inside it.** `loadAllowlist(process.argv[2])` is its only input (`cron-bash-allowlist-hook.mjs:418`). Per-cron policy lives ONLY in the per-cron `cron-allow.txt` file. Any `if (cronName === …)` in the hook is unbuildable and, if forced, becomes a silent global allow that leaks to every cron — the cross-cron negative test exists to catch exactly this.
- **Firewall-allowlisted ≠ safe egress target.** For a relaxed `browser_navigate`, the firewall allowing `api.soleur.ai` is the THREAT (a content-blind exfil sink), not reassurance. The hook's URL-origin guard is the only enforceable boundary; route-list.yaml is a soft prompt convention an injection payload can override.
- **`npx <pkg>@latest` in a cron is both a supply-chain risk and a likely blocked-egress hang.** `registry.npmjs.org` is not allowlisted; pin + image-bake `@playwright/mcp` (mirror the Chromium discipline at `cron-ux-audit.ts:14-15`).

## Deferred (tracked on #5199)
The remaining 8 crons stay in `TIER2_DEFERRED_CRONS`, all gated:
- **6 PR-flow + community-monitor (7 `mergeMode:"auto"` crons):** blocked on #5138 (stale bot-PR watchdog) AND need per-construct Bash-allowlist refinement (`date -u`, dynamic `checkout -b`, `npx eleventy` — evidence-gated). #5138 MUST land first.
- **cron-bug-fixer:** auto-merge silent-disarm risk (see Sharp Edge); defer until #5138 lands or its scan covers `bot-fix/*`.

#5199 remains OPEN as the durable anchor. No new tracking issue needed — #5199 + #5138 already track the deferred work. (Verify at /work that #5199's body still enumerates the deferred set; add a comment recording ux-audit restored + the corrected gating if it doesn't.)

## Open Code-Review Overlap
None — no open `code-review` issue touches `_cron-shared.ts`, `_cron-claude-eval-substrate.ts`, `cron-bash-allowlist-hook.mjs`, or `cron-ux-audit.ts` (verify with the Phase 1.7.5 grep at /work once Files-to-Edit is frozen).
