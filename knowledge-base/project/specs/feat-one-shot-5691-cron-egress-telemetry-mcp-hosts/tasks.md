---
plan: knowledge-base/project/plans/2026-06-29-chore-cron-egress-mcp-telemetry-silence-at-source-plan.md
issue: 5691
lane: cross-domain
---

# Tasks: silence-at-source the sporadic cron egress MCP/telemetry drops (#5691)

## Phase 0 — Spikes (gate the code change)

- [ ] 0.1 CWD verify; read each claude-eval cron's `CLAUDE_CODE_FLAGS` shape (trailing `--`?)
- [ ] 0.2 Spike A (LOAD-BEARING): `claude --print --plugin-dir plugins/soleur --strict-mcp-config --debug …` — confirm NO connect to mcp.cloudflare/vercel/stripe/context7 AND skills still resolve. PASS→Phase 2; FAIL→docs-only for MCP hosts
- [ ] 0.3 Spike B: confirm `--strict-mcp-config --mcp-config .mcp.json` keeps Playwright, drops the 4 plugin MCP servers
- [ ] 0.4 Spike C: confirm `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` accepted by the installed CLI

## Phase 1 — Tests first (RED)

- [ ] 1.1 Extend `cron-claude-eval-substrate.test.ts`: assert `spawnClaudeEval` prepends `--strict-mcp-config` (idempotent) + sets `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1"` (spawn spy)
- [ ] 1.2 Parity test: the 2 inline spawners (`cron-daily-triage`, `cron-follow-through-monitor`) carry the flag + env (git-grep-enumerated, no hardcoded count)
- [ ] 1.3 Extend `cron-ux-audit.test.ts`: assert `CLAUDE_CODE_FLAGS` has `--mcp-config` + `.mcp.json`, in lockstep with the `mcp__playwright__*` allowedTools parity

## Phase 2 — strict-mcp-config injection (GREEN; only if Spike A PASS)

- [ ] 2.1 `_cron-claude-eval-substrate.ts` `spawnClaudeEval`: prepend `--strict-mcp-config` to `flags` (idempotent, index 0)
- [ ] 2.2 `cron-ux-audit.ts`: add `--mcp-config`, `.mcp.json` before the trailing `--`; update flags comment
- [ ] 2.3 `cron-daily-triage.ts` + `cron-follow-through-monitor.ts`: add `--strict-mcp-config` to inline flag arrays (no `--mcp-config` — they need no MCP server)

## Phase 3 — Telemetry env (GREEN; ships regardless)

- [ ] 3.1 `spawnClaudeEval`: merge `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1"` into spawn env (line ~732)
- [ ] 3.2 `cron-daily-triage.ts` + `cron-follow-through-monitor.ts`: same env var in inline spawn env

## Phase 4 — Documentation (ships regardless)

- [ ] 4.1 `cron-egress-blocked.md` §"Intended-by-design drops": add "Remote plugin-MCP + CC-telemetry dials (#5691)" sub-section
- [ ] 4.2 `ADR-052-...md`: Amendment (2026-06-29, #5691) — dialer ID, keep-blocked decision, strict-mcp-config + telemetry-env levers, no allowlist/CIDR widening
- [ ] 4.3 `cron-egress-lb-rotation-outage-postmortem.md`: flip #5691 rows (61-62, 206) open→resolved
- [ ] 4.4 New learning `knowledge-base/project/learnings/bug-fixes/<date>-cron-mcp-telemetry-egress-silence-at-source.md`

## Phase 5 — Verify

- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- [ ] 5.2 `./node_modules/.bin/vitest run test/server/inngest/cron-claude-eval-substrate.test.ts test/server/inngest/cron-ux-audit.test.ts`
- [ ] 5.3 `bash apps/web-platform/infra/cron-egress-firewall.test.sh` (allowlist unchanged → still green)
- [ ] 5.4 `git diff --name-only origin/main` shows neither `cron-egress-allowlist.txt` nor `cron-egress-firewall.test.sh`
- [ ] 5.5 KB citation check: `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | xargs -I{} test -f {}`
- [ ] 5.6 PR body: `Ref #5691` (not Closes); record Spike A/B/C transcripts

## Phase 6 — Post-merge (automated)

- [ ] 6.1 After redeploy, Sentry sweep of issue 126858085 over ≥3 days (no SSH): confirm the 5 DSTs absent; `gh issue close 5691`. Datadog 34.x persisting → follow-up issue.
