---
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
type: feat
classification: agent-loop-cron-migration
parent_umbrella: 3948
cohort: claude-code-spawn (PR-5 / PR-7 / PR-8 / PR-9 / PR-10)
clo_bucket: ii
---

## Enhancement Summary

**Deepened on:** 2026-05-25
**Sections enhanced:** Research Reconciliation, Phase 0 preconditions, Phase 2 (buildSpawnEnv), Phase 7 (tests), Risks & Mitigations, Acceptance Criteria
**Gates verified:** Phase 4.4 (precedent-diff — substrate matches PR-7/PR-10 verbatim), Phase 4.5 (network-outage — no SSH-class triggers in plan; the `EHOSTUNREACH`-keyword matches inside the failure_modes block are infrastructure-failure prose, not connectivity-fix work), Phase 4.6 (User-Brand Impact present, threshold `aggregate pattern`), Phase 4.7 (Observability section schema-complete), Phase 4.8 (no PAT-shaped variables)

### Key Improvements

1. **ADR-033 conformance declaration.** All 6 invariants (I1-I6) named explicitly in the handler header; cross-referenced to the auto-firing `cron-no-byok-lease-sweep.test.ts` which globs `cron-*.ts` and will pick up the new handler automatically as a regression rail for I2.
2. **Doppler mirror deferred to follow-up tracking issue (operator preference).** Per operator instruction at plan-amend time: the `prd_scheduled` → `prd` mirror is OUT OF SCOPE for this PR. Phase 0 is verify-only (read-only `doppler secrets get` to enumerate missing keys); a follow-up tracking issue is filed in the PR body so the mirror is operator-owned, not pipeline-owned. Accept the known-broken first-fire risk: if the secrets are absent at 08:00 UTC tomorrow, the prompt's failure-branch will file a `FAILED` issue and the operator mirrors then.
3. **buildSpawnEnv negative-class test expanded.** Added `INNGEST_SIGNING_KEY`, `INNGEST_EVENT_KEY`, `SUPABASE_SERVICE_ROLE_KEY` to the negative class — these are present in `prd` Doppler and would be silently leaked if a passthrough widening happened.
4. **Sentry monitor mutation diff captured.** Three field deltas (margin 60→30, runtime 10→55, comment header) — `terraform plan` output shape pinned in AC.
5. **Token-lifetime floor inheritance check.** `TOKEN_MIN_LIFETIME_MS = 60min` is inherited verbatim from PR-7; floor exceeds the 50-min `MAX_TURN_DURATION_MS` envelope.

### New Considerations Discovered

- **`cron-no-byok-lease-sweep.test.ts` auto-coverage** — the test globs `server/inngest/functions/cron-*.ts` (verified at lines 39-41 of the test); zero edit required for I2 invariant enforcement on the new handler. Side-effect: a regression here would be visible on the first vitest run for this PR's branch.
- **Hetzner consumes Doppler `prd` config** — verified at `apps/web-platform/infra/inngest-bootstrap.sh:147` (`doppler run --project soleur --config prd`) and `apps/web-platform/infra/cloud-init.yml:459`. CI deploy re-reads Doppler on every merge (`ci-deploy.sh:175`), so the Doppler mirror MUST land before the merge that triggers deploy — not as a post-merge step.
- **Sentry monitor resource pre-exists** — `sentry_cron_monitor.scheduled_community_monitor` at `cron-monitors.tf:193-203` was provisioned for the GHA-era external heartbeat. This PR mutates in place (`Plan: 0 to add, 1 to change, 0 to destroy`) rather than creating new.
- **Milestone `Post-MVP / Later` verified** — milestone number 6 (open) per `gh api 'repos/jikig-ai/soleur/milestones?state=open' --jq '.[] | select(.title == "Post-MVP / Later")'`.

# feat(TR9 PR-11): Migrate scheduled-community-monitor to Inngest cron substrate

> **Parent umbrella:** #3948 (TR9 group-(c) agent-loop crons)
> **Cohort:** 6th claude-code-spawn handler (PR-5 cron-bug-fixer, PR-7 cron-roadmap-review, PR-8 cron-legal-audit, PR-9 cron-agent-native-audit, PR-10 cron-competitive-analysis).
> **Structural template:** `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts` (closest analogue — daily issue+pr+kb-writer, similar prompt shape, ISSUE-CLOSURE-SAFETY+DEDUP guards added at PR-7 review).
> **Predecessor workflow:** `.github/workflows/scheduled-community-monitor.yml` (DELETE in same PR per TR9 I-13).
> **Cadence:** daily `0 8 * * *` UTC.
> **CLO bucket:** **ii** — first bucket-ii in the claude-code-spawn cohort (kb-writer + pr-creator). Authorization context elevated relative to bucket-i siblings.

## Overview

This is PR-11 of the umbrella #3948 migration. It ports the daily community-monitor agent loop from a GH Actions workflow (`claude-code-action`) to the Inngest substrate established by PR-5. The handler spawns `claude-code` inside `step.run` with the verbatim prompt extracted from the workflow YAML, mints a fresh GitHub-App installation token per fire, clones the repo into an ephemeral workspace, symlinks the deployed plugin tree, and runs the agent under a 50-min `AbortController` envelope.

Five wrinkles differentiate this handler from the prior five in the cohort:

1. **CLO bucket-ii classification.** The agent (a) writes to `knowledge-base/support/community/YYYY-MM-DD-digest.md`, (b) opens a PR for the digest, and (c) files a GitHub Issue with the daily report summary. PR-7 (`cron-roadmap-review`) was the only other handler that both writes KB content AND files an issue, and PR-10 (`cron-competitive-analysis`) similarly writes KB content + opens a PR + files an issue. The structural template inherits cleanly from PR-7; the **bucket-ii** label is the new axis — surfaced in the child issue body so the multi-agent review thread anchors authorization scrutiny on this PR.

2. **External router script — `community-router.sh`.** The prompt invokes the daily fetch loop through `plugins/soleur/skills/community/scripts/community-router.sh` (NOT `router.sh` as some operator notes claimed — verified at plan-write time: the script literally lives at this path with no `router.sh` sibling). The ephemeral `git clone --depth=1` brings the entire repo tree, so reachability is structurally guaranteed by the cohort's clone-and-symlink workspace setup. The script is already `chmod +x` in the repo; no boot-time chmod needed.

3. **Discord env passthrough — `buildSpawnEnv` allowlist widening.** The current GHA workflow injects `DISCORD_WEBHOOK_URL`, `DISCORD_BOT_TOKEN`, `DISCORD_GUILD_ID`, plus X/Bluesky/LinkedIn credentials via the `prd_scheduled` Doppler config (`.github/workflows/scheduled-community-monitor.yml:65-81`). The Inngest handler's `buildSpawnEnv` allowlist across all 5 prior cohort siblings is locked to `PATH, HOME, NODE_ENV, ANTHROPIC_API_KEY, GH_TOKEN` (verbatim PR-5 shape; verified at lines 245-253 of `cron-roadmap-review.ts` and identical in PR-8/PR-9/PR-10). This handler MUST extend the allowlist with the **minimal Discord-and-friends set** — defensively, only the community-monitor-relevant secrets, not full passthrough.

4. **Doppler precondition gap (prd vs prd_scheduled) — verify-only, mirror deferred to follow-up.** Verified at plan-write time: `prd_scheduled` Doppler config holds `DISCORD_BOT_TOKEN`, `DISCORD_GUILD_ID`, `DISCORD_WEBHOOK_URL`, `BSKY_HANDLE`, `BSKY_APP_PASSWORD`, `LINKEDIN_*` — but `prd` Doppler (which the Hetzner Inngest process consumes) does NOT have any of these. Only `DISCORD_OPS_WEBHOOK_URL` is in `prd`. **Operator decision (plan-amend time): the mirror is out of scope for this PR.** Phase 0 enumerates the gap (read-only) and files a follow-up tracking issue in the PR body. The known consequence: the first natural fire at 08:00 UTC after merge will detect "platforms disabled" and file a `[Scheduled] Community Monitor - FAILED` issue; the operator mirrors the secrets at that point and re-runs. This is the deliberately-accepted failure mode (operator-noticeable, daily until fixed, no silent data loss).

5. **Hacker News query.** The HN scraper hits HN's public Algolia API directly (no auth headers). Verified in `plugins/soleur/skills/community/scripts/hn-community.sh`. Structurally always-on per the router's `hn|hn-community.sh||` entry (empty `env_vars`, empty `auth_command` → always enabled).

The plan also re-confirms three safety guards from PR-7 review:

- **DEDUP RULE.** Daily cadence (not weekly), so the title MUST embed an ISO date (`[Scheduled] Community Monitor - YYYY-MM-DD`) — same-day fires collide naturally and the agent's dedup check finds the prior issue and comments rather than filing a duplicate. The GHA prompt already uses ISO-date titles (verified at line 165 of `.github/workflows/scheduled-community-monitor.yml`); the port preserves it verbatim. Daily dedup window: **24 hours** (vs roadmap-review's 6 days for the weekly cadence).
- **ISSUE CLOSURE SAFETY.** Community-monitor does NOT close issues — the prompt only **creates** the daily report issue and writes a digest file. No closure code paths. The PR-7 guard is therefore N/A for this handler. Verified by reading lines 92-167 of the GHA prompt: zero `gh issue close` / `gh issue edit --state closed` invocations.
- **ROADMAP.MD CONFLICT GUARD.** Community-monitor writes to `knowledge-base/support/community/YYYY-MM-DD-digest.md` (date-namespaced, no collision possible) and does NOT edit `knowledge-base/product/roadmap.md`. The PR-7 guard is N/A for this handler. Verified: no roadmap.md references in the GHA prompt.

The Sentry monitor resource `sentry_cron_monitor.scheduled_community_monitor` ALREADY EXISTS in `apps/web-platform/infra/sentry/cron-monitors.tf:193-203` (it was provisioned to monitor the GHA workflow's external heartbeat). The migration mutates the existing resource in place: tighten `checkin_margin_minutes` (60 → 30 — Inngest precedent has minimal jitter), raise `max_runtime_minutes` (10 → 55 — claude-eval cohort budget), and update the header comment to reflect Inngest provenance.

## Research Reconciliation — Spec vs. Codebase

| Spec/source claim | Reality at plan-write time | Plan response |
|---|---|---|
| Router script lives at `plugins/soleur/skills/community/scripts/router.sh` (per some operator notes) | Actual path is `plugins/soleur/skills/community/scripts/community-router.sh` (verified via `ls`) | Plan and prompt extract reference the verified path; no rename needed |
| `buildSpawnEnv` lives in `apps/web-platform/src/inngest/functions/` | Actual path is `apps/web-platform/server/inngest/functions/` (Next.js App Router server tree) | Plan uses verified path throughout |
| Sentry monitor `scheduled_community_monitor` is new in this PR | Resource ALREADY EXISTS at `cron-monitors.tf:193-203` (provisioned for GHA-era heartbeat) | Plan **mutates in place** (margin/runtime/comment), not creates |
| Discord secrets are in `prd` Doppler | Discord secrets live ONLY in `prd_scheduled` config; `prd` has only `DISCORD_OPS_WEBHOOK_URL` | Operator-chosen scope: **mirror deferred to follow-up tracking issue.** Phase 0 enumerates the gap (read-only); first-fire failure is the detection path |
| Community-monitor can close issues (PR-7 ISSUE-CLOSURE-SAFETY applies) | Prompt has zero `gh issue close` invocations | Guard is N/A; not added to prompt |
| Community-monitor edits roadmap.md (PR-7 ROADMAP.MD CONFLICT GUARD applies) | Prompt only writes to date-namespaced `knowledge-base/support/community/YYYY-MM-DD-digest.md` | Guard is N/A; not added to prompt |

## User-Brand Impact

**If this lands broken, the user experiences:** the daily community-monitor digest stops being written to `knowledge-base/support/community/` (KB historical visibility for community trends regresses), AND the daily `[Scheduled] Community Monitor - YYYY-MM-DD` issue stops being filed (operator loses the daily heads-up about Discord/HN/X activity). The user-facing app keeps running — this is an internal operator-facing pipeline.

**If this leaks, the user's data/workflow is exposed via:** Discord secrets bound into the Inngest handler's spawn-env allowlist. If the allowlist accidentally widens beyond `DISCORD_WEBHOOK_URL`, `DISCORD_BOT_TOKEN`, `DISCORD_GUILD_ID` (e.g., DOPPLER_TOKEN, GITHUB_APP_PRIVATE_KEY, SENTRY_AUTH_TOKEN), a prompt-injected agent could `echo $VAR` and leak the bytes into the stdout-streaming line of the handler (the redactor only masks the GH installation token, not arbitrary env vars). Defense: keep the allowlist **explicit and minimal** — only the four community vars + the existing five.

**Brand-survival threshold:** **aggregate pattern**. A single-day digest miss is not user-impacting (community trends summarize across many days; operator notices a missed digest on the second-day miss); a pattern of misses (e.g., a week of silent failures) is operationally bad but not brand-survival. The threshold is therefore `aggregate pattern`, not `single-user incident`. No CPO sign-off required at plan time. The diff DOES touch a sensitive path (Sentry TF + Inngest handler env) — the `threshold: aggregate pattern` resolution exempts from the `single-user incident` CPO gate but the section is non-empty.

## Domain Review

**Domains relevant:** Engineering (infra/observability), Operations (Doppler config), Support (community digest output is the community-manager skill's daily artifact).

### Engineering

**Status:** carry-forward from PR-5/PR-7/PR-8/PR-9/PR-10 brainstorm-and-plan cycles.
**Assessment:** Substrate primitives are locked. Sixth iteration of an established pattern. Risk is no longer architectural; risk is in the wrinkles enumerated above (CLO bucket-ii, env allowlist widening, Doppler mirror).

### Operations

**Status:** verify-only (mirror deferred to follow-up tracking issue per operator preference).
**Assessment:** The `prd_scheduled` → `prd` secret mirror is enumerated by Phase 0 (read-only) and tracked via a follow-up issue filed in the PR body. First-fire failure is the operator-noticeable detection path. If `prd` already had Discord secrets via Doppler-shared inheritance the gap would be a no-op; verified at plan-write time that no such inheritance exists.

### Support (community)

**Status:** carry-forward.
**Assessment:** The community-router.sh + per-platform community scripts are stable. No script edits in this PR. The agent invokes the same shell scripts the GHA workflow invoked; only the host changes.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/sentry/cron-monitors.tf` — **mutate** the existing `sentry_cron_monitor.scheduled_community_monitor` resource (lines 193-203):
  - `checkin_margin_minutes`: 60 → 30 (Inngest-fired precedent — `scheduled_daily_triage`, `scheduled_follow_through`, `scheduled_bug_fixer`, `scheduled_strategy_review`, `scheduled_roadmap_review`, `scheduled_legal_audit`, `scheduled_agent_native_audit`, `scheduled_competitive_analysis`)
  - `max_runtime_minutes`: 10 → 55 (claude-eval cohort budget — mirrors `scheduled_bug_fixer`/`scheduled_roadmap_review`/`scheduled_legal_audit`/`scheduled_agent_native_audit`/`scheduled_competitive_analysis`)
  - Comment header rewritten to reflect Inngest provenance and reference PR-11 + closing issue
- No new Terraform root, no new provider, no new vendor.
- No new sensitive variables.

### Apply path

**(c) `apply-sentry-infra.yml` auto-applies on merge.** The Sentry cron-monitors TF root is already wired to the `apply-sentry-infra` workflow that fires on push-to-main when `apps/web-platform/infra/sentry/**` changes (verified at sibling PRs PR-7/PR-8/PR-9/PR-10). The drift on existing resource is an in-place `terraform apply` (no `-replace=`, no taint). Expected change: 2 field updates per `sentry_cron_monitor.scheduled_community_monitor`.

### Distinctness / drift safeguards

- `dev` Sentry env does not run this cron monitor (Sentry monitors are prd-only by repo convention).
- No `lifecycle.ignore_changes` block needed — the resource is fully managed.
- State storage: existing R2-backed S3 backend (no new bucket / key).

### Vendor-tier reality check

`jianyuan/sentry` v0.15.0-beta2 — same provider version used by all prior cohort PRs. No tier gate change.

## Observability

```yaml
liveness_signal:
  what: "Sentry cron monitor check-in (scheduled-community-monitor) POSTed at end of step.run pipeline"
  cadence: "daily 0 8 * * * UTC (24h fire cycle)"
  alert_target: "Sentry issue alert on scheduled-community-monitor monitor (failure_issue_threshold=1)"
  configured_in: "apps/web-platform/infra/sentry/cron-monitors.tf:193 (sentry_cron_monitor.scheduled_community_monitor)"

error_reporting:
  destination: "Sentry via reportSilentFallback() on workspace-setup failures, claude-eval spawn errors, abort-by-timeout, and Sentry-heartbeat POST failures (verbatim PR-7 shape, feature label rebound to cron-community-monitor)"
  fail_loud: true  # Sentry issue created on first failure (failure_issue_threshold=1), single-miss alert

failure_modes:
  - mode: "Inngest function registration fails at next deploy"
    detection: "apps/web-platform/app/api/inngest/route.ts must register cronCommunityMonitor — Inngest serve endpoint returns 500 on register if missing, surfaced in Vercel/Hetzner build logs and the post-merge `gh run watch` on apply-sentry-infra + Web Platform Release"
    alert_route: "Manual — apply-sentry-infra + Web Platform Release deploy check on PR merge; Sentry monitor stays at 'expected' until first natural fire"
  - mode: "claude binary not found at spawn time"
    detection: "Throws typed error from resolveClaudeBin() at the start of spawnClaudeEval; bubbles to step.run failure → Sentry issue via reportSilentFallback"
    alert_route: "Sentry issue alert on first failure"
  - mode: "Discord secrets missing in prd Doppler (operator-owned precondition gap; deliberately deferred to follow-up tracking issue per operator scope decision)"
    detection: "First natural fire — agent runs `bash $ROUTER platforms` and reports discord/x/bsky as 'disabled'; per the GHA prompt's failure-branch, agent creates issue '[Scheduled] Community Monitor - FAILED' and stops. ALSO detected at Phase 0 verification step before merge"
    alert_route: "Sentry monitor stays green (the agent exited cleanly), but the issue title contains '- FAILED' → operator sees in the daily issue scan. This is the intended detection path given the deferred mirror — see Phase 0 Accepted failure mode"
  - mode: "Installation token expires mid-eval"
    detection: "TOKEN_MIN_LIFETIME_MS = 60min floor enforced by generateInstallationToken({ minRemainingMs }); fails fast with typed error"
    alert_route: "Sentry issue via reportSilentFallback on spawn error"
  - mode: "Ephemeral workspace teardown stranded under /tmp"
    detection: "teardownEphemeralWorkspace() catches rm errors and mirrors to Sentry via reportSilentFallback; acceptable degraded state"
    alert_route: "Sentry warning (not error)"
  - mode: "AbortController fires at 50 min — claude hung"
    detection: "spawnResult.abortedByTimeout === true → reportSilentFallback at op 'claude-eval-timeout'"
    alert_route: "Sentry issue"

logs:
  where: "pino structured logs via reportSilentFallback → Sentry; child stdout/stderr line-streamed through redactToken() to logger.info/error with token bytes masked"
  retention: "Sentry default (90 days for issue events; checkins distinct)"

discoverability_test:
  command: "curl -s https://app.soleur.ai/api/inngest | jq '.functions[] | select(.id == \"cron-community-monitor\")'"
  expected_output: "Returns object containing id=cron-community-monitor, triggers including cron '0 8 * * *' and event 'cron/community-monitor.manual-trigger'"
```

## Implementation Phases

### Phase 0 — Preconditions (run BEFORE any code edit)

1. **Doppler verify (READ-ONLY) + file follow-up tracking issue.** Per operator instruction at plan-amend time, the `prd_scheduled` → `prd` mirror is OUT OF SCOPE for this PR (`hr-menu-option-ack-not-prod-write-auth` prod-write avoided; operator-owned remediation). Enumerate the gap and file a follow-up issue that the operator can action post-merge:

   ```bash
   # 1. Enumerate which community secrets are missing from prd (read-only — no writes)
   MISSING=()
   for K in DISCORD_WEBHOOK_URL DISCORD_BOT_TOKEN DISCORD_GUILD_ID BSKY_HANDLE BSKY_APP_PASSWORD LINKEDIN_ACCESS_TOKEN LINKEDIN_PERSON_URN; do
     V=$(doppler secrets get "$K" -p soleur -c prd --plain 2>/dev/null)
     if [[ -z "$V" ]]; then
       MISSING+=("$K")
     fi
     printf "%-30s %s\n" "$K" "$([ -n "$V" ] && echo present || echo MISSING)"
   done

   # 2. If any missing, capture the list for the follow-up issue body created in Phase 8.
   #    Do NOT mirror. Do NOT call `doppler secrets set`. Operator will mirror post-merge.
   if (( ${#MISSING[@]} > 0 )); then
     echo "Will file follow-up tracking issue listing: ${MISSING[*]}"
   fi
   ```

   **Accepted failure mode.** Hetzner's Inngest service is provisioned by `apps/web-platform/infra/inngest-bootstrap.sh:147` as `doppler run --project soleur --config prd -- /usr/local/bin/inngest start ...` — the Doppler envelope is established at service start. The CI deploy step re-reads Doppler on every merge (`apps/web-platform/infra/ci-deploy.sh:175`) and restarts the service. With the mirror deferred: the first natural fire at 08:00 UTC after merge will detect "platforms disabled" and the prompt's failure-branch will file a `[Scheduled] Community Monitor - FAILED` issue. This is the deliberately-chosen detection path — operator-noticeable, daily until fixed, no silent data loss. Mirror happens post-merge under operator control (separate from the autonomous one-shot loop).

   **NOTE:** `X_*` tokens are intentionally excluded from the enumeration — the prompt forbids X mentions/timeline fetching (`Do NOT call fetch-mentions or fetch-timeline (403 on Free tier)` per `.github/workflows/scheduled-community-monitor.yml:118-119`); the only enabled X command is `x fetch-metrics`. If X-metrics coverage is wanted post-merge, file separately.

2. **Verify Sentry monitor identity.** `terraform plan` against `apps/web-platform/infra/sentry/` and confirm only the in-place `update` on `sentry_cron_monitor.scheduled_community_monitor` (no destroy/create). Capture exact `Plan: 0 to add, 1 to change, 0 to destroy` output in the PR body.

3. **Verify community-router.sh reachability.** From repo root: `bash plugins/soleur/skills/community/scripts/community-router.sh platforms` returns 0. If it errors (chmod, shebang), file a precondition issue and stop. (Already verified at plan-write time — present, executable, runs clean.)

### Phase 1 — Handler scaffold (`apps/web-platform/server/inngest/functions/cron-community-monitor.ts`)

**ADR-033 invariant conformance (binding all 6 invariants):**

- **I1** — `claude` binary spawned INSIDE `step.run("claude-eval", …)` (Inngest replay memoization)
- **I2** — Operator `ANTHROPIC_API_KEY` only; never founder BYOK. Auto-enforced by `apps/web-platform/test/server/cron-no-byok-lease-sweep.test.ts` which globs `server/inngest/functions/cron-*.ts` and asserts `runWithByokLease` is neither imported nor called (4 shapes: direct call, alias-import, bare-import, dynamic-import). New handler is auto-covered.
- **I3** — `AbortSignal` aborts at `MAX_TURN_DURATION_MS = 50min`. Manual SIGTERM→SIGKILL escalation via process-group kill (`detached: true`).
- **I4** — `claude` binary resolved at spawn time via filesystem checks; `CLAUDE_BIN` env var is the override hatch for fresh-host bootstraps.
- **I5** — Deterministic `step.run` return shape: `{ok, exitCode, signal, abortedByTimeout, durationMs}`. stdout is NOT captured (streamed through `redactToken` then to logger).
- **I6** — Event payloads emitted by `cron-*.ts` MUST carry `actor: "platform"`. This handler emits none, so I6 is N/A (same as PR-7/PR-10).

Copy `cron-roadmap-review.ts` as the structural template. Rename:

- File: `cron-community-monitor.ts`
- Exported handler: `cronCommunityMonitorHandler`
- Exported registration: `cronCommunityMonitor`
- All `feature:` and `fn:` labels in `reportSilentFallback` calls: `cron-community-monitor` / `cron-community-monitor`
- ephemeralRoot tmpdir prefix: `soleur-cron-community-monitor-`
- `SENTRY_MONITOR_SLUG`: `"scheduled-community-monitor"` (matches existing TF resource name)
- Function id: `"cron-community-monitor"`
- Cron trigger: `{ cron: "0 8 * * *" }` (daily 08:00 UTC)
- Manual-trigger event: `{ event: "cron/community-monitor.manual-trigger" }`
- Concurrency: identical to PR-7 — `[ { scope: "fn", limit: 1 }, { scope: "account", key: '"cron-platform"', limit: 1 } ]`
- Retries: 1

### Phase 2 — `buildSpawnEnv` widening (THE security-sensitive edit)

Extend the allowlist with the four community-monitor-specific vars:

```ts
function buildSpawnEnv(installationToken: string): NodeJS.ProcessEnv {
  return {
    PATH: process.env.PATH,
    HOME: process.env.HOME,
    NODE_ENV: process.env.NODE_ENV,
    ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
    GH_TOKEN: installationToken,
    // Community-monitor allowlist additions (PR-11). Defensive: ONLY the
    // platform secrets the community-router.sh needs to flip platforms
    // from "disabled" → "enabled". NOT a wholesale process.env passthrough.
    DISCORD_WEBHOOK_URL: process.env.DISCORD_WEBHOOK_URL,
    DISCORD_BOT_TOKEN: process.env.DISCORD_BOT_TOKEN,
    DISCORD_GUILD_ID: process.env.DISCORD_GUILD_ID,
    BSKY_HANDLE: process.env.BSKY_HANDLE,
    BSKY_APP_PASSWORD: process.env.BSKY_APP_PASSWORD,
    LINKEDIN_ACCESS_TOKEN: process.env.LINKEDIN_ACCESS_TOKEN,
    LINKEDIN_PERSON_URN: process.env.LINKEDIN_PERSON_URN,
  };
}
```

The header comment above `buildSpawnEnv` MUST explicitly note the allowlist additions and their bucket-ii authorization rationale (single sentence; the PR-5 verbatim comment block expanded by ~3 lines).

### Phase 3 — Prompt extraction

Extract the prompt block from `.github/workflows/scheduled-community-monitor.yml` lines 92-167 verbatim. Strip the 12-space YAML indentation. Wrap in a backtick-quoted JS template literal `COMMUNITY_MONITOR_PROMPT`. Backticks inside the prompt's fenced code block (the persist-via-PR bash block) MUST be escaped as `\``.

Verbatim-extraction anchors that the test suite will assert:

- `"You are a community monitoring agent"` (opening line)
- `"## Instructions"` (section marker)
- `"plugins/soleur/skills/community/scripts/community-router.sh"` (router path — distinguishes from "router.sh")
- `"ROUTER=\"plugins/soleur/skills/community/scripts/community-router.sh\""` (shell var assignment)
- `"knowledge-base/support/community/YYYY-MM-DD-digest.md"` (digest output path)
- `"[Scheduled] Community Monitor"` (issue title prefix)
- `"scheduled-community-monitor"` (label name)
- `"--milestone \"Post-MVP / Later\""` (MILESTONE RULE)
- `"## Period"`, `"## Activity Summary"`, `"## Top Contributors"` (digest section markers)
- `"Repository Stats"`, `"Community Interactions"` (sub-section markers)

### Phase 4 — Registration in Inngest serve endpoint

Edit `apps/web-platform/app/api/inngest/route.ts`:

1. Add import: `import { cronCommunityMonitor } from "@/server/inngest/functions/cron-community-monitor";`
2. Add to the registration array (alphabetical order: between `cronCompetitiveAnalysis` and `cronLegalAudit`).

### Phase 5 — Sentry TF mutation

Edit `apps/web-platform/infra/sentry/cron-monitors.tf` resource `sentry_cron_monitor.scheduled_community_monitor`:

```hcl
# TR9 PR-11 (closes #<this-PR's-issue>): Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-community-monitor.ts`.
# Migrated from the GHA scheduled-community-monitor workflow (deleted in
# the same PR per TR9 I-13 hygiene). The Sentry monitor resource pre-
# existed (it tracked the GHA-era external heartbeat); this PR updates
# fields in place: tightens checkin_margin (60→30 min, Inngest-fired
# precedent) and raises max_runtime (10→55 min, claude-eval cohort budget
# mirroring scheduled_bug_fixer/scheduled_roadmap_review/scheduled_legal_audit/
# scheduled_agent_native_audit/scheduled_competitive_analysis).
resource "sentry_cron_monitor" "scheduled_community_monitor" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-community-monitor"
  schedule                = { crontab = "0 8 * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 55
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}
```

### Phase 6 — Delete GHA workflow

Delete `.github/workflows/scheduled-community-monitor.yml` in the same commit. Per TR9 I-13: the GHA YAML and the Inngest handler MUST land atomically — no overlap window where both fire at 08:00 UTC, no orphan window where neither fires.

### Phase 7 — Tests (`apps/web-platform/test/server/inngest/cron-community-monitor.test.ts`)

Copy `cron-roadmap-review.test.ts` as the structural template. Adjust:

- Import path
- Registration anchors: `id: "cron-community-monitor"`, `cron: "0 8 * * *"`, `event: "cron/community-monitor.manual-trigger"`
- Prompt anchors (from Phase 3's list)
- Exported timing constants (MAX_TURN_DURATION_MS, KILL_ESCALATION_MS — same values)
- DEDUP RULE anchor remains
- ISSUE CLOSURE SAFETY and ROADMAP.MD CONFLICT GUARD anchors are REMOVED (N/A — see Overview)

**New test class (PR-11 specific): buildSpawnEnv allowlist grep assertion.** Read the SUT source via `readFileSync`, grep-assert that the body of `buildSpawnEnv` contains:
- `DISCORD_WEBHOOK_URL: process.env.DISCORD_WEBHOOK_URL`
- `DISCORD_BOT_TOKEN: process.env.DISCORD_BOT_TOKEN`
- `DISCORD_GUILD_ID: process.env.DISCORD_GUILD_ID`
- `BSKY_HANDLE`, `BSKY_APP_PASSWORD`, `LINKEDIN_ACCESS_TOKEN`, `LINKEDIN_PERSON_URN` (one assertion per name)

AND a negative-class assertion: the function MUST NOT contain ANY of:

- `DOPPLER_TOKEN` — Doppler service token; full secrets-read on prd
- `GITHUB_APP_PRIVATE_KEY` — GitHub App PEM; full repo write across all repos the app is installed on
- `SENTRY_AUTH_TOKEN` — Sentry write API token (NOT the heartbeat public key); full project access
- `SENTRY_IAC_AUTH_TOKEN` — Sentry IaC-write token (jianyuan/sentry provider creds); destructive against Sentry resources
- `SUPABASE_SERVICE_ROLE_KEY` — Supabase service role; bypasses RLS
- `INNGEST_SIGNING_KEY`, `INNGEST_EVENT_KEY` — Inngest substrate auth; allows arbitrary event forging
- `STRIPE_SECRET_KEY` — Stripe API; payment surface
- `RESEND_API_KEY` — Resend email; impersonation surface
- `...process.env` — the spread operator that would defeat the allowlist

The negative-class is the primary security regression detector — additions to the allowlist are caught by code review; widening to a denylist (or spread-passthrough) is caught by this test. The list is intentionally over-broad: anything sensitive in `prd` Doppler that could be added by a future careless edit.

### Phase 8 — PR + child issue body

Open a child issue under #3948 with title `feat(TR9 PR-11): Migrate scheduled-community-monitor to Inngest cron substrate (bucket ii)` and the CLO bucket-ii authorization context inline.

Title pattern matches the PR-7 / PR-8 / PR-9 / PR-10 lineage. Body must:

1. Cite #3948 as parent umbrella and check the corresponding row.
2. Lead with the **bucket-ii** classification (first in the cohort) — surface it for multi-agent review.
3. Enumerate the four migration wrinkles (env allowlist widening, Doppler precondition gap [verify-only + follow-up issue link], router-path verification, sentry-monitor mutate-in-place).
4. List Phase-0 verifications completed (Sentry plan output, community-router.sh reachability, Doppler missing-keys enumeration) + link to the operator-owned follow-up mirror issue.

PR body uses `Closes #<child-issue>` (NOT `Closes #3948` — the umbrella stays open until all 11 children land).

## Files to Edit

- `apps/web-platform/infra/sentry/cron-monitors.tf` — mutate `sentry_cron_monitor.scheduled_community_monitor` in place (margin, runtime, header comment)
- `apps/web-platform/app/api/inngest/route.ts` — register the new function (import + add to array)
- `.github/workflows/scheduled-community-monitor.yml` — **DELETE** (TR9 I-13 atomicity)

## Files to Create

- `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` — new handler (~600 LOC, mirrors `cron-roadmap-review.ts` shape)
- `apps/web-platform/test/server/inngest/cron-community-monitor.test.ts` — handler unit tests + prompt anchors + buildSpawnEnv allowlist grep tests

## Open Code-Review Overlap

Run `gh issue list --label code-review --state open --json number,title,body` against the planned-file set:

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for path in \
  "apps/web-platform/infra/sentry/cron-monitors.tf" \
  "apps/web-platform/app/api/inngest/route.ts" \
  "apps/web-platform/server/inngest/functions/cron-community-monitor.ts" \
  "apps/web-platform/test/server/inngest/cron-community-monitor.test.ts" \
  ".github/workflows/scheduled-community-monitor.yml"; do
  jq -r --arg path "$path" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

To be re-run at deepen-plan time. Expected: **None** (new files; the mutated cron-monitors.tf line range is the very recent PR-10 territory, no open scope-out targets it). Disposition default: **Acknowledge** (no overlap).

## Acceptance Criteria

### Pre-merge (PR)

1. **Doppler verify-only enumeration captured + follow-up issue filed.** The Phase 0 read-only enumeration of which community secrets are missing in `prd` Doppler is included in the PR body verbatim. The follow-up tracking issue (operator-owned mirror) is filed with title `chore(ops): Mirror community-monitor secrets prd_scheduled → prd Doppler (TR9 PR-11 follow-up)`, body lists the MISSING set from Phase 0, milestone `Post-MVP / Later`, labels `domain/operations`, `priority/p1-high` (high because the first-fire failure is daily until resolved). Issue URL linked in PR body. **NO `doppler secrets set` calls in this PR.**
2. **`terraform plan`** against `apps/web-platform/infra/sentry/` shows `Plan: 0 to add, 1 to change, 0 to destroy` and the change is the `sentry_cron_monitor.scheduled_community_monitor` field update (margin 60→30, runtime 10→55). Output captured in PR body.
3. **Handler test passes:** `bun test apps/web-platform/test/server/inngest/cron-community-monitor.test.ts` (or the equivalent vitest invocation per `apps/web-platform/package.json scripts.test`) all green.
4. **buildSpawnEnv allowlist test:** the new test class asserts both positive (community vars present) AND negative (DOPPLER_TOKEN, GITHUB_APP_PRIVATE_KEY, SENTRY_AUTH_TOKEN, spread-operator absent) — green.
5. **Inngest registration test:** `bun test apps/web-platform/test/server/inngest/` — the import-time smoke test for `cronCommunityMonitor` passes (registration shape didn't throw at module load).
6. **Cohort regression:** PR-5/PR-7/PR-8/PR-9/PR-10 tests still pass (no regression in sibling-handler tests).
7. **GHA workflow deleted:** `.github/workflows/scheduled-community-monitor.yml` is in the PR's deleted-files list.
8. **No Inngest cohort tests skipped or marked `.skip`/`.todo`** — verify via `grep -nE '\.skip\(|\.todo\(' apps/web-platform/test/server/inngest/cron-community-monitor.test.ts`; returns 0.
9. **Atomicity grep:** the single commit that lands this PR touches BOTH `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` AND `.github/workflows/scheduled-community-monitor.yml` (the new file appears as added, the GHA appears as deleted) — `git diff main...HEAD --name-status -- apps/web-platform/server/inngest/functions/cron-community-monitor.ts .github/workflows/scheduled-community-monitor.yml | wc -l` returns 2 with one `A` and one `D`.

### Post-merge (operator)

10. **`apply-sentry-infra` workflow green** on the merge commit: `gh run watch <run-id>` exits 0; Sentry resource mutation applied. **AUTOMATED via post-merge ship verification** (no operator dashboard step).
11. **Web Platform Release green** on the merge commit: registers `cron-community-monitor` on the Inngest serve endpoint at `app.soleur.ai/api/inngest`. Verify via `curl -s https://app.soleur.ai/api/inngest | jq '.functions[] | select(.id == "cron-community-monitor")'` — non-empty. **AUTOMATED via curl** (no dashboard step).
12. **First natural fire at next 08:00 UTC** files `[Scheduled] Community Monitor - YYYY-MM-DD` issue AND opens a PR for `knowledge-base/support/community/YYYY-MM-DD-digest.md`. **Automation:** `gh issue list --label scheduled-community-monitor --state open --search 'created:>YYYY-MM-DD'` returns ≥ 1 issue created within the 30-min margin window of the cron tick.
13. **Sentry monitor `scheduled-community-monitor` reports a check-in within the 30-min margin** post-fire. **Automation:** `curl` against the Sentry checkins API for the monitor slug. NOT an operator dashboard step.

## Test Scenarios

The handler unit test inherits the PR-7 shape verbatim plus the new buildSpawnEnv-allowlist class. No new end-to-end tests are required — the cohort already validates the substrate via PR-5/PR-7's first-fire-in-prod runs.

## Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Discord secrets not mirrored to `prd` before merge → first fire detects "platforms disabled" and exits FAILED | Accepted (operator-chosen) | Mirror deliberately deferred per operator scope decision. Detection path: first 08:00 UTC fire files a `FAILED` issue (daily until operator runs the follow-up mirror). No silent data loss. Defense: AC#1 (follow-up issue filed in PR body) ensures the operator has a tracked work item before the first fire |
| `buildSpawnEnv` allowlist accidentally widens to passthrough (`...process.env`) → secret leakage via prompt-injection | High | Phase 7 negative-class test (grep-asserts the 9-item denylist incl. `...process.env`, DOPPLER_TOKEN, GITHUB_APP_PRIVATE_KEY, SENTRY_AUTH_TOKEN/SENTRY_IAC_AUTH_TOKEN, SUPABASE_SERVICE_ROLE_KEY, INNGEST_SIGNING_KEY/EVENT_KEY, STRIPE_SECRET_KEY, RESEND_API_KEY); plus the existing logger-line redactor (only masks GH_TOKEN — defense-in-depth, not the primary brake) |
| Sentry monitor identity confusion — `terraform plan` proposes destroy+create instead of in-place update | Medium | Pre-merge AC#2 — explicit `Plan: 0 to add, 1 to change, 0 to destroy` capture in PR body; if the plan shows `1 to destroy`, halt and investigate before apply. Per `2026-05-15-terraform-import-only-beta-provider-schema-validation.md`, jianyuan/sentry beta is sensitive to attribute schema drift — keep the resource body identical except the three intentional deltas |
| GHA workflow and Inngest function both fire at 08:00 UTC on day of merge | Low | Atomicity AC#9 — single commit ships both the add (handler) and delete (GHA YAML); no overlap window |
| Community-router.sh shebang/chmod broken in ephemeral clone | Low | Verified at plan-write time: script is executable, shebang is `#!/usr/bin/env bash`. The ephemeral `git clone` preserves file mode. Defensive: prompt invokes via `bash $ROUTER ...` (explicit interpreter), not `$ROUTER ...` directly — survives a clone that drops the executable bit |
| Inngest registration regression catches another cohort sibling | Low | Pre-merge AC#6 — sibling-handler tests still pass (smoke test for cohort regression) |
| `cron-no-byok-lease-sweep.test.ts` regression on the new file | Low | The test globs `server/inngest/functions/cron-*.ts` (per `cron-no-byok-lease-sweep.test.ts:39`) — new handler is auto-covered. As long as it does NOT import `runWithByokLease` (it inherits PR-7's verbatim shape, which doesn't), the test passes |
| Doppler mirror over-mirrors a wrong-config secret (e.g., dev-only value) | N/A — no mirror happens in this PR | This PR does not perform any Doppler writes. The follow-up issue body advises the operator to use stdin form (`printf '%s' "$V" \| doppler secrets set $K -p soleur -c prd`) when they mirror, to preserve special characters (`?`, `&`, `=`, `.`) |
| BSKY or LinkedIn tokens expire mid-quarter without rotation | Low | Out of scope. The community-router treats them as "disabled" if absent or expired; the digest gracefully degrades. File a follow-up issue for proactive rotation monitoring if observed in practice |

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| Mirror Doppler secrets pre-merge (as a hard Phase 0 gate) | Rejected by operator at plan-amend time. Rationale: pre-merge mirror is a destructive prod write requiring operator ack under `hr-menu-option-ack-not-prod-write-auth`, which breaks the autonomous one-shot loop. Operator preference: accept first-fire failure as the detection path, mirror under operator control via the follow-up tracking issue |
| Extract `_cron-substrate.ts` shared module before this PR | Out-of-scope. The substrate-extraction backlog now has 6 handlers worth of pattern; the right time to extract is AFTER this PR lands so all 6 are visible. Filed as a follow-up issue at PR-merge time |
| Widen `buildSpawnEnv` to pass all `process.env` through | Rejected. The allowlist (vs denylist) shape is the load-bearing security invariant — bucket-ii prompt-injection has higher blast radius than bucket-i, so the discipline is more important here, not less |
| Mirror X_* tokens to `prd` even though the workflow prompt skips them | Rejected. The GHA prompt explicitly forbids X mentions/timeline fetching (`Do NOT call fetch-mentions or fetch-timeline (403 on Free tier)`). Only `fetch-metrics` would use X tokens; the workflow prompt batches `bash $ROUTER x fetch-metrics` IF enabled. Out-of-scope: bring X coverage online in a follow-up (open question: do we want X-metrics-only via a second token type, or drop X entirely?) |
| Convert the GHA workflow to call `inngest.send` for `cron/community-monitor.manual-trigger` and keep GHA as a thin trigger | Rejected. TR9's stated goal is to escape GHA's cron jitter for agent loops — keeping GHA as a trigger preserves the jitter and adds an unnecessary hop |

## Research Insights — Substrate-Extraction Threshold

**6-handler precedent diff (informational, drives the post-merge follow-up issue, not this PR):**

After PR-11 lands, six handlers share verbatim copies of:

- `resolveClaudeBin()` — ~17 LOC (identical across PR-5/PR-7/PR-8/PR-9/PR-10; PR-11 inherits)
- `buildAuthenticatedCloneUrl()` — ~3 LOC
- `redactToken()` — ~4 LOC
- `mintInstallationToken()` — ~10 LOC
- `spawnSimple()` — ~17 LOC
- `setupEphemeralWorkspace()` — ~50 LOC (only the tmpdir prefix differs)
- `teardownEphemeralWorkspace()` — ~13 LOC
- `postSentryHeartbeat()` — ~45 LOC
- Validator regexes (`SENTRY_DOMAIN_RE`, `SENTRY_PROJECT_RE`, `SENTRY_PUBLIC_KEY_RE`) — ~3 LOC

That's ~160 LOC × 6 handlers = ~960 LOC of verbatim duplication. PR-12 (next group-(c) child) crosses the typical extraction threshold (3+ duplicates). The extraction itself is mechanical (move to `_cron-substrate.ts`, parametrize `feature:` label and `tmpdir-prefix:`) but it's a separate PR with its own review surface. Filed as follow-up.

The reason `buildSpawnEnv` is NOT in the extraction candidate list: its allowlist diverges per handler. PR-7/PR-8/PR-9/PR-10 all return the 5-key shape `{PATH, HOME, NODE_ENV, ANTHROPIC_API_KEY, GH_TOKEN}`; PR-11 returns a 12-key shape with the 7 community vars added. A shared substrate would either require an awkward optional-extension API (per-handler env extension hook) or copy-paste of the wider shape into siblings that don't need it. Keep `buildSpawnEnv` per-handler — it's a small function and the per-handler authorization surface is the right shape for it to live in.

## Deferred / Tracking Issues

- **Doppler `prd_scheduled` → `prd` mirror** (operator-owned remediation): file at PR-open time (BEFORE merge, so the operator has it tracked when first fire fails). Title: `chore(ops): Mirror community-monitor secrets prd_scheduled → prd Doppler (TR9 PR-11 follow-up)`. Body lists the 7 secrets (or whatever Phase 0 enumeration returns) and the stdin-form `doppler secrets set` recipe. Milestone `Post-MVP / Later`, labels `domain/operations`, `priority/p1-high`. Issue URL linked from the PR body so reviewers see the explicit operator-owned remediation path. Re-evaluation criterion: "after PR-11 ships, mirror within the first 24h window to prevent repeated daily FAILED issues."
- **X-metrics-only coverage** (out-of-scope above): file at PR-merge time, milestone `Post-MVP / Later`. Re-evaluation criterion: "after PR-11 ships and first 2 weeks of digests reveal whether the X-metrics gap is operator-noticeable."
- **`_cron-substrate.ts` shared-module extraction**: file at PR-merge time, milestone `Post-MVP / Later`. Re-evaluation criterion: "after PR-11 ships, 6 handlers share verbatim 200+ LOC of substrate (resolveClaudeBin, buildAuthenticatedCloneUrl, redactToken, mintInstallationToken, spawnSimple, setupEphemeralWorkspace, teardownEphemeralWorkspace, postSentryHeartbeat). Extract if PR-12/PR-13 land within 4 weeks."

## PR-body reminder

- `Closes #<child-issue-N>` (NOT `Closes #3948`)
- Reference `#3948` in body (not title)
- Label: `domain/engineering`, `priority/p2-medium`
- Reviewer: multi-agent review per /soleur:review (substrate is mature; this is a 6th-iteration apply of an established pattern — review should focus on the four wrinkles, not the substrate primitives)
