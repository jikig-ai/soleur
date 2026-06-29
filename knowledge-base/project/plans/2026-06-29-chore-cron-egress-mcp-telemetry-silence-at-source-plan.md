---
title: "chore: identify + silence-at-source the sporadic cron egress drops to un-enumerated MCP/telemetry hosts (post-#5676)"
issue: 5691
type: chore
date: 2026-06-29
branch: feat-one-shot-5691-cron-egress-telemetry-mcp-hosts
lane: cross-domain
brand_survival_threshold: none
related: [5676, 5685, 5199, "ADR-052"]
---

# chore: Identify + silence-at-source the sporadic cron egress drops to un-enumerated MCP/telemetry hosts (#5691)

🔧 **Type:** chore / investigation + at-source fix · **Priority:** P3-low · **Domain:** engineering

## Enhancement Summary

**Deepened on:** 2026-06-29 · **Reviewers:** architecture-strategist, code-simplicity-reviewer, observability-coverage-reviewer (all code-verified; zero P0 blockers).

Corrections folded in from review:
1. **Pre-merge proof is primary, not the post-merge absence sweep.** Spike A's `--debug` zero-connect trace + the argv unit test *prove* the dial is gone at source; "DST absent over 3 days" is statistically unsound for vol-1..3 sporadic drops (absence ≡ no-fix). AC7 demoted to corroboration.
2. **ux-audit losing Playwright would be a SILENT exit-0 green degradation** — the Sentry Crons monitor is liveness-only (fatal classes: credit/auth/spawn/timeout, `cron-ux-audit.ts:375-440`). The real guard is pre-merge (Spike B + the `cron-ux-audit.ts` parity test), NOT a runtime FAILED check-in. failure_mode-1 corrected.
3. **The 2 inline-spawn crons do NOT pass `--plugin-dir`** (`cron-daily-triage.ts:140`, `cron-follow-through-monitor.ts:237`) → they never dial the MCP hosts; for them ONLY the telemetry env is load-bearing (strict-mcp-config is defensive belt-and-suspenders). AC3 rationale corrected.
4. **Drift guard hardened**: replace the weak git-grep parity with a structural invariant — `resolveClaudeBin()` may be referenced ONLY in the substrate + the 2 known inline crons; a new inline spawner trips the test. Follow-up filed to migrate the 2 inline crons onto the `spawnClaudeEval` chokepoint (deletes ~150 LoC of duplicated abort logic — arch P1-1).
5. Simplicity trims: Spikes B/C folded into Spike A; idempotency guard dropped (no caller sets the flag); separate parity-test file folded into the substrate test.
6. ux-audit's `.mcp.json` is a **per-fire overlay** ux-audit already writes into `spawnCwd` at setup (`cron-ux-audit.ts:302-307`: pinned `@playwright/mcp@0.0.75`, container profile, `npm_config_prefer_offline`); `--mcp-config .mcp.json` (relative to spawnCwd) resolves to that overlay, not the repo-root dev file.

## Overview

Follow-up to #5676 (which silenced the dominant intended drop — the `npx`
`registry.npmjs.org` registry probe — at source via `npm_config_prefer_offline`).
The single grouped `op=egress_blocked` Sentry issue (`126858085`) still shows
**sporadic, low-volume** drops to four un-enumerated destinations:

| Blocked DST | Identified host | Vol |
|---|---|---|
| `64.239.123.129` | `mcp.vercel.com` | 3 |
| `104.18.25.159` | `mcp.cloudflare.com` | 2 |
| `198.202.176.231` / `198.137.150.161` | `mcp.stripe.com` | 1 |
| `34.149.66.137` | GCP global-LB, Datadog `us5` *default* vhost — customer unidentified (default-cert, not proof of dialer) | 21 |

This plan **identifies the dialer for each host** (AC1/AC3), **records the
keep-blocked decision per host** (AC2 — none is a legitimate runtime need; the
default posture is correctly blocked), and **silences the non-essential dials at
source** so the security-critical `egress-blocked` alert stops being polluted by
known-benign noise (the grouped-alert conflation flagged as a real observability
problem in `2026-06-29-egress-residual-is-intended-drop-...md`).

**No allowlist widening.** `cron-egress-allowlist.txt` and
`cron-egress-firewall.test.sh` are **not** touched — allowlisting these hosts
would reverse ADR-052's default-drop boundary for zero benefit (the dials' tools
are denied anyway). The change strictly *reduces* container egress.

## Investigation findings (AC1 + AC3 — root cause, static-traced)

**The dialer of `mcp.vercel.com` / `mcp.cloudflare.com` / `mcp.stripe.com` is
the claude-eval cron substrate itself, NOT any cron's prompt/tool.**

- Every claude-eval cron spawns `claude --print --plugin-dir plugins/soleur …`
  (`_cron-claude-eval-substrate.ts:728`; per-cron `CLAUDE_CODE_FLAGS`).
- `--plugin-dir plugins/soleur` loads `plugins/soleur/.claude-plugin/plugin.json`,
  whose `mcpServers` block bundles **four remote HTTP MCP servers**: `context7`
  (`mcp.context7.com`), `cloudflare` (`mcp.cloudflare.com`), `vercel`
  (`mcp.vercel.com`), `stripe` (`mcp.stripe.com`).
- Claude Code **connects plugin MCP servers automatically at startup**
  (verified: code.claude.com/docs/en/plugins-reference.md — "Plugin MCP servers
  start automatically when the plugin is enabled"). That startup handshake IS
  the egress dial.
- **These dials are non-essential by construction.** The containment hook
  (`buildCronEvalSettings`, relax-minimal) **denies every `mcp__*` tool** by
  default; `CRON_MCP_ALLOWLISTS` grants Playwright tools to `cron-ux-audit`
  ONLY (`_cron-claude-eval-substrate.ts:297-312`). No cron is permitted to use
  cloudflare/vercel/stripe/context7 MCP tools — so the connection attempts are
  pure startup overhead that the firewall correctly drops.

**The dialer of `34.149.66.137` (Datadog `us5` default vhost) is unidentified
and likely Claude Code's own non-essential outbound traffic** (telemetry / error
reporting / auto-update) OR the `context7` MCP backend. The `*.logs.us5.datadoghq.com`
cert is the *default* vhost on a shared GCP global-LB — per
`2026-06-29-egress-residual-is-intended-drop-...md` it does NOT prove the customer.
Claude Code's exact telemetry hosts are not publicly documented, so this cannot
be proven statically; the disposition (below) eliminates every plausible dialer
at source (`--strict-mcp-config` drops context7; `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`
kills CC telemetry), with post-deploy Sentry rate-comparison as corroboration (AC7).

## Decision (AC2) — keep-blocked + silence-at-source per host

| Host | Decision | Mechanism |
|---|---|---|
| `mcp.vercel.com` / `mcp.cloudflare.com` / `mcp.stripe.com` / `mcp.context7.com` | **keep-blocked**; stop dialing | `--strict-mcp-config` on cron spawns → ignores plugin-bundled MCP servers (no allowlist change) |
| `34.149.66.137` (CC telemetry / context7 backend) | **keep-blocked**; stop dialing | `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` in cron spawn env (+ `context7` dropped by `--strict-mcp-config`) |

Provider CIDRs remain forbidden (ADR-052 2026-06-16 amendment). No host is
allowlisted.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue body) | Reality (verified) | Plan response |
|---|---|---|
| "the only configured cron MCP server is the local Playwright npx" | True for `.mcp.json` (project) — but `plugin.json` (loaded via `--plugin-dir`) bundles 4 *remote* HTTP MCP servers that connect at startup | These are the MCP dialers; silenced via `--strict-mcp-config` |
| Premise: each host "needs its own evidence before any allowlist decision" | Evidence found: the hook denies all their tools → no legitimate need | keep-blocked, documented; no allowlist edit |
| `34.149.66.137` = "Datadog us5" | Default-cert only; real dialer unidentified (per 2026-06-29 learning) | Disposition eliminates all plausible dialers at source; confirm via Sentry absence, not by naming the host |

## User-Brand Impact

**If this lands broken, the user experiences:** a cron silently loses a tool it
needs (e.g. `cron-ux-audit` loses Playwright if `--strict-mcp-config` drops the
`.mcp.json` server) → a zero-screenshot run that exits 0 and posts a GREEN liveness
check-in (the runtime monitor is liveness-only — it does NOT catch this, obs P1-c).
The guard is therefore entirely PRE-MERGE (Spike B + the `cron-ux-audit.ts`
`--mcp-config` parity test); no user-facing surface either way.
**If this leaks, the user's data is exposed via:** N/A — the change *removes*
outbound connections; it introduces no new exposure vector and stores no data.
**Brand-survival threshold:** none — internal cron-substrate egress tightening;
no user data, no user-facing surface, strictly reduces attack surface.
`threshold: none, reason: server-side cron-infra change that only removes non-essential outbound dials; no regulated-data surface, no new exposure vector, no user-facing behavior.`

## Premise Validation (Phase 0.6)

- **#5676** (parent) — OPEN; tracks residual drops. **#5685** (the npm-probe
  silence) — MERGED. This issue is the correct follow-up; premise holds.
- **#5199** — CLOSED; `registry.npmjs.org` deliberately off-allowlist. Holds.
- **ADR-052** exists with the 2026-06-16 (grace-window) + 2026-06-29
  (intended-drops) amendments; this plan adds a third amendment.
- **Runbook** `cron-egress-blocked.md` §"Intended-by-design drops" exists.
- **Capability claim self-check:** `--strict-mcp-config`, `--mcp-config`,
  `--plugin-dir` all confirmed present in the installed `claude` CLI
  (`/home/jean/.local/bin/claude --help`). `--strict-mcp-config` = "Only use MCP
  servers from --mcp-config, ignoring all other MCP configurations." Whether it
  stops *plugin-bundled* MCP servers (vs only project/user scope) is NOT
  documented → **Phase 0 spike A is load-bearing.**

## Hypotheses (Phase 1.4 — keyword "firewall" matched)

The network-outage / `hr-ssh-diagnosis-verify-firewall` gate fired on the literal
word "firewall". **N/A here:** there is no connectivity outage and no sshd/fail2ban
hypothesis. The egress firewall is *working as designed* — it is correctly
dropping intended/non-essential dials. The fix tightens (removes dials), it does
not restore connectivity. No L3→L7 outage diagnosis applies; no incident telemetry
emitted.

## Implementation Phases

### Phase 0 — Spikes (gate the code change; documentation ships regardless)

- **0.1 — CWD verify** + read each claude-eval cron's `CLAUDE_CODE_FLAGS`
  (confirm flag-array shape and any trailing `--` separator before editing).
- **0.2 — Spike A (LOAD-BEARING — the PRIMARY acceptance proof): does
  `--strict-mcp-config` stop plugin MCP servers AND leave skills/agents intact?**
  This deterministic `--debug` trace is the evidence that the dial is gone at
  source; it is strictly stronger than any post-merge production-absence inference
  (obs P1-b). Run from the repo root:
  ```bash
  claude --print --plugin-dir plugins/soleur --strict-mcp-config --debug \
    --allowedTools Skill "Run /soleur:ux-audit --help (or load the skill) and stop" 2>&1 | tee /tmp/spikeA.log
  grep -iE 'mcp\.(cloudflare|vercel|stripe|context7)|connect' /tmp/spikeA.log   # expect: NO connect attempts to the 4 remote MCP hosts
  grep -iE 'ux-audit|ux-design-lead|skill|agent' /tmp/spikeA.log                 # expect: the ux-audit skill + its ux-design-lead sub-agent still resolve (arch P2-3)
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 claude --print "stop"; echo "exit=$?"  # telemetry var accepted (folded-in ex-Spike-C)
  ```
  - **PASS** (no plugin-MCP connection + the `ux-audit` skill/`ux-design-lead`
    agent resolve) → implement the `--strict-mcp-config` injection (Phase 2).
  - **FAIL** (plugin MCP still connects, OR skill/agent resolution regresses) →
    MCP at-source silencing is not achievable via this flag. Fall back to
    **documentation-only keep-blocked** for the MCP hosts (skip the
    `--strict-mcp-config` edits); STILL ship the telemetry env (Phase 3) and all
    docs. Record the spike result in the PR body.
- **0.3 — Spike B (folded into A's transcript): does `cron-ux-audit` keep
  Playwright under strict mode?** Confirm `--strict-mcp-config --mcp-config .mcp.json`
  loads ONLY the Playwright server (not the plugin's 4):
  ```bash
  claude --print --plugin-dir plugins/soleur --strict-mcp-config --mcp-config .mcp.json --debug \
    --allowedTools mcp__playwright__browser_navigate "stop" 2>&1 | grep -iE 'playwright|mcp\.(cloudflare|vercel|stripe)'
  # expect: playwright present; cloudflare/vercel/stripe absent
  ```
  **Semantics-proxy note (arch P2-2):** this spike runs against the repo-root dev
  `.mcp.json` (dev `user-data-dir`, `@latest`). Prod loads the **per-fire overlay**
  ux-audit writes into `spawnCwd` (`cron-ux-audit.ts:302-307`: pinned `0.0.75`,
  container profile, prefer-offline). The spike validates the load-bearing
  *semantics* (strict + explicit mcp-config = only the named server, plugin's 4
  suppressed); prod correctness additionally rests on the verified overlay-write +
  the relative `--mcp-config .mcp.json` resolving against `spawnCwd`. Note this in
  the PR body.

### Phase 1 — Tests first (RED) — `cq-write-failing-tests-before`

- **1.1** Extend `apps/web-platform/test/server/inngest/cron-claude-eval-substrate.test.ts`:
  - assert `spawnClaudeEval` prepends `--strict-mcp-config` to the argv it passes
    to `spawn` (capture `spawn` args via a mock/spy), **positioned before `--print`
    so it can never land after a trailing `--` prompt separator** (obs P2-b — assert
    position, not mere presence);
  - assert the spawn env carries `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1"`.
- **1.2 (structural drift invariant — replaces the weak git-grep parity, arch P1-2).**
  In the same substrate test, assert `resolveClaudeBin()` is referenced **ONLY** in
  the known spawn sites: `_cron-claude-eval-substrate.ts` + the 2 inline crons
  (`cron-daily-triage.ts`, `cron-follow-through-monitor.ts`). Implementation:
  `git grep -l 'resolveClaudeBin' apps/web-platform/server/inngest/functions/` must
  equal that exact 3-file set. A NEW inline claude-spawner trips this test, forcing
  the author to either route through `spawnClaudeEval` (auto-inherits the flag+env)
  OR add the flag+env and update the allowed-set. Also assert the 2 inline crons'
  flag arrays carry `--strict-mcp-config` and their spawn env carries the telemetry
  var. (No separate test file — folded here per simplicity review.)
- **1.3** Extend `apps/web-platform/test/server/inngest/cron-ux-audit.test.ts`:
  assert `CLAUDE_CODE_FLAGS` contains `--mcp-config` + `.mcp.json` (so Playwright
  survives strict mode), kept in lockstep with the existing `mcp__playwright__*`
  ↔ `CRON_MCP_ALLOWLISTS["cron-ux-audit"]` parity assertion. This test is the
  PRIMARY pre-merge guard against the silent "ux-audit loses Playwright" mode (the
  runtime monitor cannot catch it — obs P1-c).

### Phase 2 — `--strict-mcp-config` injection (GREEN; only if Spike A PASS)

- **2.1** `_cron-claude-eval-substrate.ts` `spawnClaudeEval`: prepend
  `--strict-mcp-config` at index 0 of `flags` (a global option, position-safe
  before `--print` and before any trailing `--` prompt separator). No idempotency
  guard — no caller sets the flag (verified; dropped per simplicity review). Single
  edit; covers all 15 `spawnClaudeEval` callers.
- **2.2** `cron-ux-audit.ts` `CLAUDE_CODE_FLAGS`: add `--mcp-config`, `.mcp.json`
  (before the trailing `--`) so the Playwright server is re-supplied under strict
  mode. The relative `.mcp.json` resolves against `spawnCwd` → the **per-fire
  overlay** ux-audit already writes at setup (`cron-ux-audit.ts:302-307`, pinned
  `0.0.75` + container profile + prefer-offline), NOT the repo-root dev file.
  Update the exported-flags comment.
- **2.3** `cron-daily-triage.ts` + `cron-follow-through-monitor.ts`: add
  `--strict-mcp-config` to their inline flag arrays. **Rationale (arch P2-1):** these
  crons do NOT pass `--plugin-dir` (`cron-daily-triage.ts:140`,
  `cron-follow-through-monitor.ts:237`), so they never load the plugin's 4 remote
  MCP servers and make no MCP dial — for them the load-bearing fix is the telemetry
  env (Phase 3.2); `--strict-mcp-config` is defensive belt-and-suspenders (guards a
  future `--plugin-dir` addition / project `.mcp.json` auto-discovery). Do NOT
  assert a "stops a dial" invariant for these two.

### Phase 3 — Telemetry env (GREEN; ships regardless of Spike A)

- **3.1** `_cron-claude-eval-substrate.ts` `spawnClaudeEval`: merge
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1"` into the spawn env at the
  `env: buildSpawnEnv(installationToken)` call site (line ~732):
  `env: { ...buildSpawnEnv(installationToken), CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1" }`.
  Single edit; covers all 15 callers.
- **3.2** `cron-daily-triage.ts` + `cron-follow-through-monitor.ts`: add the same
  env var to their inline spawn env objects.

### Phase 4 — Documentation (ships regardless)

- **4.1** `cron-egress-blocked.md` §"Intended-by-design drops": extend with a
  sub-section "Remote plugin-MCP + CC-telemetry dials (#5691)" — these four
  remote MCP servers (plugin.json) + CC non-essential traffic are intended-blocked
  and now silenced at source; do NOT allowlist them; the per-host keep-blocked
  rationale + the `--strict-mcp-config` / `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`
  levers.
- **4.2** `ADR-052-...md`: add **Amendment (2026-06-29, #5691 — non-essential
  cron MCP/telemetry dials silenced at source, not allowlisted)** under §4/§5,
  recording: dialer identification, keep-blocked decision, the strict-mcp-config +
  telemetry-env levers, and that no allowlist/CIDR was widened.
- **4.3** `cron-egress-lb-rotation-outage-postmortem.md`: flip the #5691 follow-up
  table row (line 206) + the two residual-table rows (lines 61-62) from "open /
  stays blocked, tracked in #5691" to "resolved in #5691 — dialer identified
  (plugin-MCP / CC-telemetry), silenced at source, kept blocked."
- **4.4** New learning `knowledge-base/project/learnings/bug-fixes/<topic>.md`
  (date at write-time): the dialer was the substrate's own `--plugin-dir`
  plugin-MCP auto-connect + CC telemetry; the fix is `--strict-mcp-config` +
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, NOT an allowlist edit; spike-gated
  because plugin-MCP suppression by `--strict-mcp-config` is undocumented.

### Phase 5 — Follow-up (file, do not implement here)

- **5.1** File a tracking issue (label `domain/engineering`, `chore`,
  `priority/p3-low`): **migrate `cron-daily-triage` + `cron-follow-through-monitor`
  onto the `spawnClaudeEval` chokepoint** — they currently re-implement ~150 LoC of
  the substrate's spawn + AbortController + SIGTERM/SIGKILL-escalation block
  (`cron-daily-triage.ts:225-237`, `cron-follow-through-monitor.ts:481-493`). Routing
  them through `spawnClaudeEval` auto-inherits the flag+env permanently and dissolves
  the drift class the Phase 1.2 structural invariant currently polices (arch P1-1).
  Out of scope for this P3-low chore (larger refactor); the structural invariant is
  the pragmatic interim guard.

## Files to Edit

- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts` — strict-mcp-config prepend + telemetry env merge in `spawnClaudeEval`
- `apps/web-platform/server/inngest/functions/cron-ux-audit.ts` — `--mcp-config .mcp.json`
- `apps/web-platform/server/inngest/functions/cron-daily-triage.ts` — inline flags + env
- `apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts` — inline flags + env
- `apps/web-platform/test/server/inngest/cron-claude-eval-substrate.test.ts` — substrate assertions
- `apps/web-platform/test/server/inngest/cron-ux-audit.test.ts` — mcp-config parity
- `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md`
- `knowledge-base/engineering/architecture/decisions/ADR-052-container-egress-firewall-docker-user-allowlist.md`
- `knowledge-base/engineering/operations/post-mortems/cron-egress-lb-rotation-outage-postmortem.md`

## Files to Create

- `knowledge-base/project/learnings/bug-fixes/<date>-cron-mcp-telemetry-egress-silence-at-source.md`

(No separate parity-test file — the inline-spawner assertions + the
`resolveClaudeBin()` structural invariant fold into the existing
`cron-claude-eval-substrate.test.ts` per simplicity + arch review.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (dialer identified):** plan + ADR amendment + learning state that the
  MCP dials originate from `plugin.json` remote MCP servers auto-connected by
  `--plugin-dir` at CLI startup, and the `34.x` Datadog-vhost dial from CC
  non-essential traffic / context7 backend (default-cert, unproven host).
- [ ] **AC2 (decision recorded):** keep-blocked for all five hosts; no edit to
  `cron-egress-allowlist.txt` or `cron-egress-firewall.test.sh`
  (`git diff --name-only origin/main` shows neither file).
- [ ] **AC3 (silence-at-source — PRIMARY proof, Spike-A-gated):** Spike A's
  `--debug` transcript (pasted in PR body) shows ZERO connect attempts to
  mcp.cloudflare/vercel/stripe/context7 under `--strict-mcp-config`, AND the
  `ux-audit` skill + `ux-design-lead` sub-agent still resolve. The substrate test
  asserts `spawnClaudeEval` argv carries `--strict-mcp-config` positioned before
  `--print`; `cron-ux-audit` re-supplies `.mcp.json` via `--mcp-config`. The 2 inline
  crons carry the flag as defense (they make no MCP dial — telemetry env is their
  load-bearing fix). If Spike A FAILED, the PR body records it and ships
  documentation-only for MCP hosts.
- [ ] **AC3b (structural drift invariant):** substrate test asserts
  `resolveClaudeBin()` is referenced only in the substrate + the 2 known inline crons.
- [ ] **AC4 (telemetry env):** `spawnClaudeEval` env + the 2 inline crons set
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1"` (asserted by test).
- [ ] **AC5 (no regression):** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
  clean; `./node_modules/.bin/vitest run test/server/inngest/cron-claude-eval-substrate.test.ts test/server/inngest/cron-ux-audit.test.ts` green; `bash apps/web-platform/infra/cron-egress-firewall.test.sh` still green (allowlist unchanged).
- [ ] **AC6 (docs):** runbook §intended-drops sub-section + ADR-052 amendment +
  postmortem rows flipped to resolved + learning file present; every cited
  `knowledge-base/` path resolves (`grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | xargs -I{} test -f {}`).

### Post-merge (operator/automated)

- [ ] **AC7 (live CORROBORATION only — NOT the acceptance gate; obs P1-a/b):** the
  acceptance proof is pre-merge (AC3 Spike A + the argv unit test). Post-merge, the
  per-DST absence sweep is corroboration with known limits: the only no-SSH reader
  `scripts/sentry-issue.sh` exposes issue-summary + latest-event (NOT a 3-day
  per-DST enumeration), and the drops are sporadic (vol 1–3), so an absence window
  shorter than the natural inter-arrival gap cannot *confirm* removal for the low-vol
  MCP hosts — only the source-level proof does. The `34.149.66.137` host (vol 21) is
  the one DST where a rate-vs-baseline comparison carries signal; if it persists
  after both at-source levers it is a dependency phone-home needing a `--debug`/
  strace trace → file a follow-up; do NOT allowlist it. (`Ref #5691` in PR body;
  `gh issue close 5691` after AC3 passes + a best-effort AC7 check — ops-remediation
  post-merge closure.)

## Infrastructure (IaC)

Skipped — introduces no new infrastructure. No host added to the egress
allowlist, no new Doppler secret (`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` is a
literal `"1"` constant set in code, not a secret), no new vendor/service/runtime
process. Pure code + docs against the already-provisioned cron substrate.

## Observability

```yaml
liveness_signal:
  what: per-cron Sentry Crons check-in (unchanged) + the existing op=egress_blocked alert
  cadence: per cron schedule; egress resolver every 1 min
  alert_target: Sentry issue 126858085 (egress-blocked) + per-cron monitors
  configured_in: ADR-052 §5; cron-egress-resolve.sh
error_reporting:
  destination: Sentry (cq-silent-fallback-must-mirror-to-sentry — reportSilentFallback already wraps spawn errors)
  fail_loud: true
failure_modes:
  - mode: ux-audit loses Playwright under strict mode (SILENT — exits 0, green liveness check-in; the monitor's fatal classes are only credit/auth/spawn/timeout, cron-ux-audit.ts:375-440, so a zero-screenshot run is NOT caught at runtime)
    detection: PRE-MERGE ONLY — Spike B + cron-ux-audit.ts --mcp-config parity assertion (the static flag/config cannot drift at runtime once asserted)
    alert_route: CI (vitest); NOT the runtime Sentry Crons monitor
  - mode: --strict-mcp-config regresses headless skill/agent resolution across the 15 substrate crons (SILENT — same exit-0 green class)
    detection: PRE-MERGE ONLY — Spike A --debug asserts the ux-audit skill + ux-design-lead sub-agent resolve under strict mode
    alert_route: CI / spike transcript in PR body
  - mode: Datadog 34.x DST persists post-deploy (dialer not CC telemetry / not context7)
    detection: AC7 rate-vs-baseline comparison (vol 21 carries signal; the low-vol MCP hosts do not)
    alert_route: manual Sentry query → follow-up issue
logs:
  where: Sentry events (kernel drop lines do NOT ship to Better Stack per ADR-052 §5); CC --debug only in spikes
  retention: Sentry default
discoverability_test:
  command: "claude --print --plugin-dir plugins/soleur --strict-mcp-config --debug --allowedTools Skill 'load /soleur:ux-audit and stop' 2>&1 | grep -iE 'mcp\\.(cloudflare|vercel|stripe|context7)|connect'"
  expected_output: "no output (zero connect attempts to the 4 remote plugin MCP hosts) — runnable, no SSH; this deterministic --debug trace is the PRIMARY proof the dial is gone at source (post-merge Sentry absence is corroboration only)"
```

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-052** (existing) with the 2026-06-29 #5691 amendment (Phase 4.2) —
records that the cron substrate's plugin-MCP auto-connect + CC non-essential
traffic are intended-blocked and silenced at source (not allowlisted), preserving
the default-drop boundary. New decision is an *extension* of ADR-052, not a
reversal → amend, do not create a new ADR.

### C4 views
**No C4 impact.** Checked all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`)
for egress/firewall/MCP/cron-eval elements — none modeled (the C4 model covers the
app architecture, not the dev-tooling MCP dials or the egress substrate). Enumerated
for this change: (a) external human actors — none (internal cron infra); (b)
external systems — `mcp.cloudflare/vercel/stripe/context7` + the CC-telemetry host,
NONE of which are C4 elements and all of which this change *removes* dials to
(no new edge added); (c) containers/data-stores touched — none; (d)
actor↔surface access relationships — none changed. A change that only removes
non-modeled outbound dev-tooling dials adds no element/edge.

### Sequencing
ADR amendment authored now (target state is true immediately on merge for the
silence; AC7 confirms the Datadog host empirically). No soak gate.

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)
**Status:** reviewed (carry-forward from `2026-06-29-egress-residual-...md`, which
routed the ADR-052 boundary call to CTO)
**Assessment:** The change strictly *tightens* container egress (removes
non-essential plugin-MCP + telemetry dials), fully aligned with ADR-052's
default-drop philosophy; it widens nothing (no allowlist/CIDR edit). The only risk
is functional (a cron losing a needed MCP server) and SILENT at runtime, bounded
by the PRE-MERGE Spike-A/B gates + the ux-audit parity test. CTO-class concern:
confirm `--strict-mcp-config` does not regress headless skill/agent resolution —
covered by Spike A. **Advisory (arch P2-5):** this is the 3rd change reasoning
against ADR-052's boundary with no named egress principle in
`principles-register.md`; consider registering an "egress default-drop / no
allowlist-widening for non-essential dials" AP that cites ADR-052 (not a blocker).

### Product/UX Gate
NONE — no file matches a UI-surface glob (`components/**`, `app/**/page.tsx`,
`app/**/layout.tsx`); orchestration/infra/docs only.

**Advisory (arch P2-5):** this is the 3rd change reasoning against ADR-052's
boundary; the principles-register has no egress/default-drop AP. Consider
registering an "egress default-drop / no allowlist widening for non-essential
dials" principle citing ADR-052 so future PRs get a named guardrail. Not a blocker.

## Test Scenarios

1. `spawnClaudeEval` prepends `--strict-mcp-config` before `--print` + sets the
   telemetry env — substrate unit test with a `spawn` spy.
2. `resolveClaudeBin()` referenced only in {substrate, daily-triage,
   follow-through-monitor}; those 2 inline crons carry the flag + env — substrate test.
3. `cron-ux-audit` carries `--mcp-config .mcp.json` in lockstep with its
   `mcp__playwright__*` allowedTools.
4. Allowlist + firewall test unchanged — `cron-egress-firewall.test.sh` green.
5. Spike A transcript (incl. folded Spike B + telemetry-var check) captured in PR
   body as the PRIMARY at-source proof.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` returns no issue whose
body references the cron substrate / ADR-052 / plugin.json files this plan edits.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. (Filled above; threshold `none` + reason.)
- **Spike A is load-bearing and undocumented.** `--strict-mcp-config` stopping
  *plugin-bundled* MCP servers (vs only project/user scope) is an inference, not a
  documented guarantee (per claude-code-guide). If the spike shows plugin MCP still
  connects, the MCP-silencing is NOT achievable via this flag — fall back to
  documentation-only keep-blocked + the telemetry env; do NOT add a provider CIDR
  or allowlist entry as a substitute (reverses ADR-052).
- **Position the `--strict-mcp-config` injection BEFORE any trailing `--` prompt
  separator.** Several crons (`cron-ux-audit`) end `CLAUDE_CODE_FLAGS` with `--`;
  appending after it would feed the flag to the CLI as a positional prompt arg.
  Prepending at index 0 (before `--print`) is position-safe.
- **The 2 inline spawners are easy to miss — and do NOT make an MCP dial.**
  `cron-daily-triage` + `cron-follow-through-monitor` do NOT route through
  `spawnClaudeEval` (the substrate injection misses them) AND do NOT pass
  `--plugin-dir` (so they never dial the plugin MCP hosts). For them the telemetry
  env is the load-bearing fix; `--strict-mcp-config` is defensive. The Phase 1.2
  `resolveClaudeBin()` structural invariant is the durable drift guard — a NEW
  inline spawner trips it. (Migrating both onto `spawnClaudeEval` is the real fix —
  filed as Phase 5.1 follow-up.)
- **The headline failure mode is SILENT, not fail-loud.** ux-audit losing Playwright
  (or any cron losing skill/agent resolution) under strict mode exits 0 → green
  liveness check-in; the runtime Sentry Crons monitor cannot catch it. The safety
  net is entirely pre-merge (Spike A/B + the parity test) — do NOT rely on a runtime
  monitor or the post-merge absence sweep to catch a strict-mode regression.
- **`34.149.66.137` may not be CC telemetry.** Its host is unproven (default
  GCP-LB cert). If AC7 shows it persisting after both at-source levers, it is a
  dependency phone-home needing a `--debug`/strace trace — file a follow-up; do
  not allowlist it.
- **`Ref #5691`, not `Closes #5691`,** in the PR body — the live confirmation
  (AC7) runs post-merge; closing happens via `gh issue close 5691` after AC7.
