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
at source and confirms via post-deploy Sentry absence.

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
project `.mcp.json` server) → a missed/failed cron check-in (fail-loud via the
existing Sentry Crons monitor), no user-facing surface.
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
- **0.2 — Spike A (LOAD-BEARING): does `--strict-mcp-config` stop plugin MCP
  servers AND leave skills/agents intact?** Run from the repo root:
  ```bash
  claude --print --plugin-dir plugins/soleur --strict-mcp-config --debug \
    --allowedTools Skill "Run /soleur:help and stop" 2>&1 | tee /tmp/spikeA.log
  grep -iE 'mcp\.(cloudflare|vercel|stripe|context7)|connect' /tmp/spikeA.log   # expect: NO connect attempts to the 4 remote MCP hosts
  grep -iE 'skill|soleur:' /tmp/spikeA.log                                       # expect: skills still resolve
  ```
  - **PASS** (no plugin-MCP connection + skills load) → implement the
    `--strict-mcp-config` injection (Phase 2).
  - **FAIL** (plugin MCP still connects) → MCP at-source silencing is not
    achievable via this flag. Fall back to **documentation-only keep-blocked**
    for the MCP hosts (skip the `--strict-mcp-config` edits); STILL ship the
    telemetry env (Phase 3) and all docs. Record the spike result in the PR body.
- **0.3 — Spike B: does `cron-ux-audit` keep Playwright under strict mode?** Confirm
  `--strict-mcp-config --mcp-config .mcp.json` loads ONLY the project Playwright
  server (not the plugin's 4):
  ```bash
  claude --print --plugin-dir plugins/soleur --strict-mcp-config --mcp-config .mcp.json --debug \
    --allowedTools mcp__playwright__browser_navigate "stop" 2>&1 | grep -iE 'playwright|mcp\.(cloudflare|vercel|stripe)'
  # expect: playwright present; cloudflare/vercel/stripe absent
  ```
- **0.4 — Spike C (telemetry):** confirm `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`
  is accepted (no error) on the installed CLI version (documented var; value `1`).

### Phase 1 — Tests first (RED) — `cq-write-failing-tests-before`

- **1.1** Extend `apps/web-platform/test/server/inngest/cron-claude-eval-substrate.test.ts`:
  - assert `spawnClaudeEval` prepends `--strict-mcp-config` to the argv it passes
    to `spawn` (capture `spawn` args via a mock/spy), idempotent when already present;
  - assert the spawn env carries `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1"`.
- **1.2** New parity test (or extend the substrate test) asserting the **2 inline
  spawners** (`cron-daily-triage.ts`, `cron-follow-through-monitor.ts`) also carry
  `--strict-mcp-config` in their inline flag arrays and the telemetry env var —
  enumerate via `git grep` on the inline spawn pattern, do not hardcode a count.
- **1.3** Extend `apps/web-platform/test/server/inngest/cron-ux-audit.test.ts`:
  assert `CLAUDE_CODE_FLAGS` contains `--mcp-config` + `.mcp.json` (so Playwright
  survives strict mode), kept in lockstep with the existing `mcp__playwright__*`
  ↔ `CRON_MCP_ALLOWLISTS["cron-ux-audit"]` parity assertion.

### Phase 2 — `--strict-mcp-config` injection (GREEN; only if Spike A PASS)

- **2.1** `_cron-claude-eval-substrate.ts` `spawnClaudeEval`: prepend
  `--strict-mcp-config` to `flags` (idempotent — skip if already present) at the
  front of the array (a global option, position-safe before `--print` and before
  any trailing `--` prompt separator). Single edit; covers all 15 `spawnClaudeEval`
  callers.
- **2.2** `cron-ux-audit.ts` `CLAUDE_CODE_FLAGS`: add `--mcp-config`, `.mcp.json`
  (before the trailing `--`) so the project Playwright server is re-supplied under
  strict mode. Update the exported-flags comment.
- **2.3** `cron-daily-triage.ts` + `cron-follow-through-monitor.ts`: add
  `--strict-mcp-config` to their inline flag arrays (these crons need no MCP server
  → no `--mcp-config`).

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

- `apps/web-platform/test/server/inngest/cron-inline-spawn-strict-mcp-parity.test.ts` — (if not folded into the substrate test) assert the 2 inline spawners carry the flag + env
- `knowledge-base/project/learnings/bug-fixes/<date>-cron-mcp-telemetry-egress-silence-at-source.md`

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (dialer identified):** plan + ADR amendment + learning state that the
  MCP dials originate from `plugin.json` remote MCP servers auto-connected by
  `--plugin-dir` at CLI startup, and the `34.x` Datadog-vhost dial from CC
  non-essential traffic / context7 backend (default-cert, unproven host).
- [ ] **AC2 (decision recorded):** keep-blocked for all five hosts; no edit to
  `cron-egress-allowlist.txt` or `cron-egress-firewall.test.sh`
  (`git diff --name-only origin/main` shows neither file).
- [ ] **AC3 (silence-at-source, Spike-A-gated):** if Spike A PASSED, `spawnClaudeEval`
  argv contains `--strict-mcp-config` (asserted by substrate test) and the 2 inline
  crons carry it; `cron-ux-audit` re-supplies `.mcp.json` via `--mcp-config`. If
  Spike A FAILED, the PR body records the failure and ships documentation-only for
  MCP hosts.
- [ ] **AC4 (telemetry env):** `spawnClaudeEval` env + the 2 inline crons set
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1"` (asserted by test).
- [ ] **AC5 (no regression):** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
  clean; `./node_modules/.bin/vitest run test/server/inngest/cron-claude-eval-substrate.test.ts test/server/inngest/cron-ux-audit.test.ts` green; `bash apps/web-platform/infra/cron-egress-firewall.test.sh` still green (allowlist unchanged).
- [ ] **AC6 (docs):** runbook §intended-drops sub-section + ADR-052 amendment +
  postmortem rows flipped to resolved + learning file present; every cited
  `knowledge-base/` path resolves (`grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | xargs -I{} test -f {}`).

### Post-merge (operator/automated)

- [ ] **AC7 (live confirmation, automated):** after `web-platform-release.yml`
  redeploys the container, query the `op=egress_blocked` Sentry issue
  (`126858085`) over ≥3 days (incident-skill `SENTRY_ISSUE_RW_TOKEN`, no SSH):
  the `mcp.vercel/cloudflare/stripe` DSTs (`64.239.123.129`, `104.18.25.159`,
  `198.202.176.231`, `198.137.150.161`) and the Datadog `34.149.66.137` DST no
  longer appear. Persisting `34.x` → a dependency phone-home requiring a deeper
  trace; file a follow-up. (`Ref #5691` in PR body; `gh issue close 5691` after
  AC7 confirms — ops-remediation post-merge closure.)

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
  - mode: cron loses a needed MCP tool (e.g. ux-audit Playwright dropped by strict mode)
    detection: cron self-reports FAILED / missed Sentry Crons check-in
    alert_route: existing per-cron Sentry monitor
  - mode: strict-mcp-config also drops project .mcp.json for ux-audit (Spike B regression)
    detection: cron-ux-audit.test.ts parity assertion (pre-merge) + ux-audit FAILED check-in (post-merge)
    alert_route: CI + Sentry Crons
  - mode: Datadog 34.x DST persists post-deploy (dialer not CC telemetry)
    detection: AC7 Sentry egress-blocked DST sweep over 3 days
    alert_route: manual Sentry query → follow-up issue
logs:
  where: Sentry events (kernel drop lines do NOT ship to Better Stack per ADR-052 §5); CC --debug only in spikes
  retention: Sentry default
discoverability_test:
  command: "incident-skill SENTRY_ISSUE_RW_TOKEN query of issue 126858085 events; assert the 5 DSTs absent (no ssh)"
  expected_output: "zero egress-blocked events for mcp.vercel/cloudflare/stripe + 34.149.66.137 over 3 days"
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
is functional (a cron losing a needed MCP server), bounded by the Spike-A/B gates
and the ux-audit parity test. CTO-class concern: confirm `--strict-mcp-config`
does not regress headless skill/agent resolution — covered by Spike A.

### Product/UX Gate
NONE — no file matches a UI-surface glob (`components/**`, `app/**/page.tsx`,
`app/**/layout.tsx`); orchestration/infra/docs only.

## Test Scenarios

1. `spawnClaudeEval` prepends `--strict-mcp-config` (idempotent) + sets the
   telemetry env — substrate unit test with a `spawn` spy.
2. The 2 inline crons carry the flag + env — parity test (git-grep-enumerated).
3. `cron-ux-audit` carries `--mcp-config .mcp.json` in lockstep with its
   `mcp__playwright__*` allowedTools.
4. Allowlist + firewall test unchanged — `cron-egress-firewall.test.sh` green.
5. Spike A/B/C transcripts captured in PR body (verification evidence).

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
- **The 2 inline spawners are easy to miss.** `cron-daily-triage` and
  `cron-follow-through-monitor` do NOT route through `spawnClaudeEval` — the
  substrate injection does not reach them; they need explicit edits + their own
  parity assertion.
- **`34.149.66.137` may not be CC telemetry.** Its host is unproven (default
  GCP-LB cert). If AC7 shows it persisting after both at-source levers, it is a
  dependency phone-home needing a `--debug`/strace trace — file a follow-up; do
  not allowlist it.
- **`Ref #5691`, not `Closes #5691`,** in the PR body — the live confirmation
  (AC7) runs post-merge; closing happens via `gh issue close 5691` after AC7.
