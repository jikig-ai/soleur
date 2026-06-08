---
title: "Fix cron bash-sandbox bwrap userns failure so scheduled producers stop self-reporting FAILED (#5000, #5004)"
type: fix
date: 2026-06-08
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related_issues: ["#5000", "#5004", "#4928", "#4960", "#4978"]
related_prs: ["#4932", "#4941", "#4944", "#4975", "#4988"]
---

# Fix cron bash-sandbox bwrap userns failure so scheduled producers stop self-reporting FAILED (#5000, #5004)

## Enhancement Summary

**Deepened on:** 2026-06-08
**Sections enhanced:** Premise Validation, Technical Approach, Risks (verified against installed code + live API + Claude Code docs)

### Key Improvements (verified findings)

1. **Installed `@anthropic-ai/claude-code` is `2.1.142`** (`apps/web-platform/package.json:25`) — the EXACT version at which `code.claude.com/docs/en/settings` documents the `defaultMode` value set including `bypassPermissions` ("As of v2.1.142, the `auto` mode is ignored…"). The prescribed `permissions.defaultMode: "bypassPermissions"` is valid in the pinned version, not just latest docs. No `auto`-mode caveat applies (we use `bypassPermissions`, not `auto`).
2. **`DEFAULT_CLAUDE_SETTINGS` is the SOLE sandbox-config write site** across all 41 inngest functions (`grep -rn "sandbox" …/functions/*.ts` → one hit, `_cron-claude-eval-substrate.ts:113`). The single-file fleet fix is confirmed — no per-producer sandbox config exists to drift.
3. **Spawn-env allowlist verified verbatim** in both #5000/#5004 producers: `{ PATH, HOME, NODE_ENV, ANTHROPIC_API_KEY, GH_TOKEN }` only (`cron-growth-audit.ts:116-124`, `cron-roadmap-review.ts:184-192`). No `DOPPLER_*`/`SENTRY_*`/`GITHUB_APP_PRIVATE_KEY`/`RESEND_API_KEY` — the sandbox-removal blast-radius mitigation in User-Brand Impact is grounded.
4. **The fallback was live when the FAILED reports fired.** #4988 (cohort generalization) merged 2026-06-07T13:19Z; #5000/#5004 fired 2026-06-08 — so the FAILED self-reports are the generalized fallback working-as-designed, not a regression. Strengthens the thesis: fix the bwrap cause, not the (correct) fallback.

### New Considerations Discovered

- **`bypassPermissions` is permission-surface-neutral vs. the working-sandbox case.** `DEFAULT_CLAUDE_SETTINGS` has no `deny` rules (`allow: []` only), so `bypassPermissions` = "auto-allow requested tools" — identical net tool-permission to the prior `autoAllowBashIfSandboxed` behavior. Only the OS isolation layer changes. This bounds the security delta precisely (Risks section updated).
- **No new scheduled job introduced** — the plan modifies EXISTING Inngest crons; the deepen-plan scheduled-work precedent gate (ADR-033 Inngest-vs-GHA) does not apply.
- **Phase 2.8 IaC gate confirmed N/A** — pure code+docs change against already-provisioned surfaces; the #4932 host sysctl/systemd unit is left untouched as defense-in-depth.

## Overview

Two scheduled Inngest cron producers — `cron-growth-audit` (#5000) and
`cron-roadmap-review` (#5004) — filed automated **FAILED self-report** issues on
2026-06-08. Both are working-as-designed outputs of the handler-level
`ensureScheduledAuditIssue` fallback (the #4960 → #4978 cohort generalization,
shipped in PR #4975 + #4988): the run terminated without producing its
`scheduled-<task>` audit issue, so the handler self-reported rather than going
silent. The fallback is correct. **The unfixed root cause is the bash sandbox
(`bwrap`) failing to acquire user-namespace capabilities in the cloud runner**,
which fails every `Bash` tool call inside `claude --print`, so the prompt never
reaches its `gh issue create` / `git push` steps.

This is the **same failure class** as #4928 (roadmap-review, 2026-06-04), which
was root-caused as `kernel.apparmor_restrict_unprivileged_userns` drifting 0→1
and durably fixed in PR #4932 (boot-persistent `bwrap-userns-sysctl.service` +
terraform trigger keyed on `{seccomp hash, server_id}`). That infra fix is
present in `apps/web-platform/infra/server.tf:621-624`. **The recurrence on
2026-06-08 — four days after #4932 merged — means the host-side sysctl fix alone
is not sufficient in practice** (sysctl re-drift, a host event that re-flipped
it, or a cloud-runner whose userns caps cannot be asserted from this host's
provisioning path).

Both issue bodies converge on the durable remediation: stop depending on a
host-mutable kernel sysctl for the cron path. Disable the OS sandbox in the
cron's own settings overlay (`DEFAULT_CLAUDE_SETTINGS` in
`_cron-claude-eval-substrate.ts`), which is host-independent and immune to
sysctl drift — **paired** with a permission mode that auto-approves bash, since
the sandbox is currently the only thing auto-approving bash for the headless
`--print` crons.

## Problem Statement

### The mechanism (authoritative, grounded in Claude Code docs)

The cron eval substrate (`spawnClaudeEval` in
`apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts`)
spawns `claude --print … --allowedTools Bash,Read,Write,… -- <prompt>` inside an
ephemeral cloned workspace whose `.claude/settings.json` is written verbatim
from the in-module `DEFAULT_CLAUDE_SETTINGS` constant (lines 109-116):

```ts
const DEFAULT_CLAUDE_SETTINGS = {
  permissions: { allow: [] as string[] },
  sandbox: { enabled: true },
};
```

Per Claude Code docs (`code.claude.com/docs/en/permissions`,
`…/sandboxing`): **when sandboxing is enabled with
`autoAllowBashIfSandboxed: true` (the default), sandboxed Bash commands run
without prompting** — "the sandbox boundary acts as a substitute for per-command
prompts." This is the ONLY reason these headless crons can run `gh issue
create` / `git push` without a human approver: `permissions.allow` is `[]` and
there is no `--permission-mode` flag, so absent the sandbox auto-approval every
bash command would block on an approval prompt that no headless session can
satisfy.

When `bwrap` cannot create a user namespace / mount `/proc` (because
`kernel.apparmor_restrict_unprivileged_userns=1`), the sandbox is **unavailable**.
With `sandbox.enabled: true` and no `failIfUnavailable`/`allowUnsandboxedCommands`
keys set, the unavailable-sandbox path causes every `Bash` call to fail or
require an approval the headless session denies — so the prompt burns turns
retrying broken bash, never reaches `gh issue create`, and the
handler-level fallback files the FAILED issue. (See the contaminated-evidence
note in `2026-06-04-cron-silence-was-bwrap-userns-drift-not-turn-budget.md`: a
"Reached max turns" notice captured while bash is broken is a symptom, not a
budget shortfall.)

### Why the existing infra fix is not enough

PR #4932 set `kernel.apparmor_restrict_unprivileged_userns=0` via a
boot-persistent systemd unit. The 2026-06-08 recurrence proves that path can
still leave the cron-eval host without working userns caps. Rather than chase the
kernel sysctl with more provisioning, the durable fix removes the cron path's
dependency on it: a sandbox-disabled + permission-bypassed cron does not need
unprivileged userns at all. The host-side sysctl assertion (#4932) and its
non-blocking drift detector (#4944) remain in place as defense-in-depth for any
other sandbox consumer.

### Two converging issue-body recommendations, reconciled

| Issue-body recommendation | Plan disposition |
|---|---|
| "grant the runner the user-namespace caps bwrap needs" | Already attempted (#4932); host-side; recurred. **Keep** as defense-in-depth; do NOT make it the cron's load-bearing dependency. |
| "auto-approve `dangerouslyDisableSandbox: true` when `CI=true`" | Per-command SDK affordance requiring `allowUnsandboxedCommands` + a `canUseTool` handler — `claude --print` does not expose that hook here. **Reject** in favor of the settings-level approach below. |
| "set `sandbox.enabled: false` in settings.json so cron jobs run gh commands without prompts" | **Adopt** — but the issue body omits that disabling the sandbox ALSO removes bash auto-approval. Must pair with `permissions.defaultMode: "bypassPermissions"`. |

The issue bodies (and #5004's stdout tail) say "set `sandbox.enabled: false` in
settings.json." **The settings.json that governs the cron eval is NOT the repo's
`.claude/settings.json`** — it is the runtime-written
`DEFAULT_CLAUDE_SETTINGS` overlay in `_cron-claude-eval-substrate.ts`. The repo
`.claude/settings.json` governs interactive/dev sessions only and must NOT be
changed (it would disable the sandbox for human dev sessions, a regression).

## Proposed Solution

Single-file change to the shared substrate, fixing all 21 claude-eval cron
producers at once:

```ts
const DEFAULT_CLAUDE_SETTINGS = {
  permissions: {
    allow: [] as string[],
    defaultMode: "bypassPermissions",
  },
  sandbox: { enabled: false },
};
```

- `sandbox.enabled: false` — removes the bwrap dependency entirely. Host-independent; immune to sysctl drift.
- `permissions.defaultMode: "bypassPermissions"` — restores the auto-approval the sandbox previously provided, so headless bash (`gh issue create`, `git push`) runs without a prompt. `bypassPermissions` is a valid `defaultMode` per `code.claude.com/docs/en/settings`.

No per-producer `CLAUDE_CODE_FLAGS` edits are required — the pairing lives in the
one shared overlay. (An alternative considered below is adding
`--dangerously-skip-permissions` to each producer's flags; rejected as 14×
duplicated and drift-prone.)

## Technical Approach

### Architecture

The change is localized to `DEFAULT_CLAUDE_SETTINGS`
(`apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts:109-116`),
written into every ephemeral cron workspace by `setupEphemeralWorkspace`
(same file, lines 157-163). All 21 producers that call `setupEphemeralWorkspace`
inherit the new overlay:

```
agent-native-audit, bug-fixer, campaign-calendar, community-monitor,
competitive-analysis, compound-promote, content-generator, content-publisher,
content-vendor-drift, daily-triage, follow-through-monitor, growth-audit,
growth-execution, legal-audit, roadmap-review, rule-prune, seo-aeo-audit,
skill-freshness, strategy-review, ux-audit, workspace-gc
```

All 14 prompt-driven producers pass `Bash` in `--allowedTools` and none has a
permission-mode flag (verified: `grep -nE "allowedTools|permission-mode|dangerously-skip"`
across `cron-*.ts` — every one relies on sandbox auto-approval). They are the
exact cohort that breaks when the sandbox is unavailable, and the exact cohort
the paired `bypassPermissions` default restores.

### Implementation Phases

#### Phase 0 — Live-evidence preconditions (RED gate; no code)

Before touching code, pull the live Sentry `extra` for the #5000 / #5004 runs to
confirm the failure is bwrap-userns (not a contaminated turn-exhaustion or an
upstream API 500), per the "pull live evidence before coding" learning. Use the
Sentry org-issues API with `SENTRY_ISSUE_RW_TOKEN` (read-only; **no SSH**) —
search the `scheduled-output-missing` / `cron-claude-eval` events for
`stderrTail` containing `Operation not permitted` / `bwrap` / `/proc`.

- If the evidence shows bwrap-userns failure → proceed (root cause confirmed).
- If the evidence shows an upstream API 500 / billing / genuine max-turns kill with healthy bash → STOP; this plan's root cause is wrong, re-scope. (Mirrors the #4932 plan-hypothesis-refuted pattern.)

Also assert the current host sysctl state via the non-blocking drift detector
output (#4944) if surfaced in deploy-status/Sentry — to record whether the host
sysctl had re-drifted (informs whether #4932's systemd unit needs a follow-up
issue) WITHOUT blocking this code fix on it.

#### Phase 1 — Failing tests (RED)

Add tests in
`apps/web-platform/test/server/inngest/cron-claude-eval-substrate.test.ts`
(create if absent; mirror the existing `cron-content-generator.test.ts` harness
shape) asserting the **written settings.json content**, not model behavior
(LLM-out-of-the-assertion-path per the plan Sharp Edge on LLM-mediated tests):

- `setupEphemeralWorkspace` writes `.claude/settings.json` whose parsed JSON has `sandbox.enabled === false`.
- …has `permissions.defaultMode === "bypassPermissions"`.
- …has `permissions.allow` still `[]` (no widening of the explicit allowlist).
- A drift-guard assertion that `DEFAULT_CLAUDE_SETTINGS` does NOT regress to `sandbox.enabled: true` (anchored on the literal so a future edit must update the test).

Tests fail against current `sandbox.enabled: true` / no `defaultMode`.

#### Phase 2 — Implement (GREEN)

Edit `DEFAULT_CLAUDE_SETTINGS` per Proposed Solution. Update the surrounding
comment to cite #5000/#5004 + the docs rationale (sandbox auto-approval →
`bypassPermissions` pairing). Run the new tests + the full inngest suite green.

#### Phase 3 — Observability + docs

- Update runbook `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` H2: add a note that the cron eval now runs sandbox-disabled + bypassPermissions, so a bwrap-userns host drift no longer silences producers; the host sysctl (#4932/#4944) is defense-in-depth for non-cron sandbox consumers only.
- Capture a learning in `knowledge-base/project/learnings/integration-issues/` documenting: the real cron `settings.json` is the runtime overlay not the repo file; disabling the sandbox requires the `bypassPermissions` pairing; the sysctl-drift recurrence motivated removing the host dependency from the cron path.

#### Phase 4 — Verify recovery (post-merge, automated)

After merge + deploy, fire `cron/roadmap-review.manual-trigger` and
`cron/growth-audit.manual-trigger` via `/soleur:trigger-cron` (reads the trigger
secret read-only from Doppler — no SSH). Confirm each produces its success
`[Scheduled] …` issue with the correct `scheduled-<task>` label end-to-end. Then
`gh issue close 5000 5004` with a comment linking the merged PR. (Use `Ref
#5000 / #5004` in the PR body, NOT `Closes` — closure happens post-merge after
the manual-trigger recovery is observed, per the ops-remediation Sharp Edge.)

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| **Re-assert the host sysctl only (`terraform apply` of #4932's unit)** | Pure ops-remediation; does not address recurrence. The 2026-06-08 failure four days after #4932 proves the host path is not durable for the cron. Keep as defense-in-depth, not the fix. |
| **Auto-approve `dangerouslyDisableSandbox: true` when `CI=true`** (issue-body option B) | Requires `allowUnsandboxedCommands: true` + a `canUseTool` handler in the SDK invocation; `claude --print` here does not expose that callback. Per-command, not durable for a 21-producer fleet. |
| **Add `--dangerously-skip-permissions` to each producer's `CLAUDE_CODE_FLAGS`** | Functionally equivalent to `bypassPermissions` but duplicated across 14 files; drift-prone (a new producer would forget it). The shared `defaultMode` overlay is the single-point fix. Keeps the sandbox-disable and the permission-bypass colocated so they can never drift apart. |
| **Set `sandbox.enabled: false` alone** (literal issue-body text) | Breaks ALL crons: removes bash auto-approval, every `gh`/`git` command blocks on a prompt no headless session answers. The issue body omits the auto-approval coupling. |
| **Edit repo `.claude/settings.json`** (the file the issue body literally names) | Wrong file — governs interactive dev sessions, not the cron overlay. Would disable the sandbox for human dev sessions (a security regression) and have zero effect on the crons. |
| **`failIfUnavailable: true` + keep sandbox** | Makes the failure louder but does not fix it; crons still can't run when bwrap is down. |

## User-Brand Impact

- **If this lands broken, the user experiences:** the founder's scheduled growth-audit / roadmap-review / community-monitor / content-generator outputs silently stop (or keep self-reporting FAILED), so the operator's autonomous ops cadence — the core Soleur value prop for a non-technical solo founder — degrades unnoticed until the watchdog flags it days later.
- **If this leaks, the user's workflow/data is exposed via:** disabling the OS sandbox removes the bwrap jail around `claude --print`. The exposure surface is the cron's own ephemeral workspace + its scoped env. Mitigations already in place: (a) the spawn env is an **allowlist** (`PATH/HOME/NODE_ENV/ANTHROPIC_API_KEY/GH_TOKEN` only — no `DOPPLER_*`, `SENTRY_*`, `GITHUB_APP_PRIVATE_KEY`, `RESEND_API_KEY`); (b) `GH_TOKEN` is a short-lived scoped installation token; (c) the workspace is a `--depth=1` throwaway clone torn down after the run; (d) the prompt is **trusted, in-repo, constant** — there is no untrusted external input steering the model. The threat actor for a sandbox is an attacker who controls the prompt or repo content; here both are first-party.
- **Brand-survival threshold:** `single-user incident` — a single founder's autonomous-ops substrate going dark (or a sandbox-removal that mishandles the scoped token) is a brand-survival event for a solo-operator product.

Because the threshold is `single-user incident`, this plan carries
`requires_cpo_signoff: true` and `user-impact-reviewer` runs at review time. The
deepen-plan domain triad (security-sentinel + architecture-strategist +
data-integrity-guardian) MUST run — plan-review style agents are structurally
blind to the sandbox-removal security trade-off.

## Observability

```yaml
liveness_signal:
  what: "Per-function Sentry cron monitors (scheduled-growth-audit, scheduled-roadmap-review, + cohort) AND the cron-cloud-task-heartbeat output-aware watchdog (label-presence of scheduled-<task> issues)"
  cadence: "per-run; heartbeat thresholds per task cadence (growth-audit weekly→threshold, roadmap-review weekly→9d)"
  alert_target: "Sentry issue (RED monitor) + cloud-task-silence GitHub issue (watchdog) + handler-level FAILED self-report issue"
  configured_in: "apps/web-platform/server/inngest/functions/cron-cloud-task-heartbeat.ts (TASK_INVENTORY); per-producer postSentryHeartbeat calls; ensureScheduledAuditIssue in _cron-shared.ts:422"
error_reporting:
  destination: "Sentry web-platform via reportSilentFallback / postSentryHeartbeat (SENTRY_DSN)"
  fail_loud: "RED Sentry cron monitor + a [Scheduled] … FAILED self-report issue with exitCode/durationMs/stdoutTail (the exact signal that filed #5000/#5004)"
failure_modes:
  - mode: "bwrap sandbox unavailable again via a DIFFERENT path after sandbox-disable (should be impossible — sandbox is off)"
    detection: "post-fix: a FAILED self-report would now carry a non-bwrap stderrTail; the stdoutTail no longer shows 'Operation not permitted'/bwrap"
    alert_route: "Sentry cron monitor → operator"
  - mode: "bypassPermissions still blocks a write (e.g. an explicit deny rule or critical rm prompt)"
    detection: "FAILED self-report with a permission-denial stderrTail; recovery manual-trigger reproduces"
    alert_route: "handler FAILED issue + Sentry"
  - mode: "host sysctl re-drift affecting a NON-cron sandbox consumer"
    detection: "non-blocking bwrap userns drift detector (#4944) reads kernel.apparmor_restrict_unprivileged_userns; logs on drift"
    alert_route: "deploy-status / Sentry (log-only, non-gating per #4941)"
logs:
  where: "app pino stdout shipped to Better Stack via Vector (#4786); per-line claude-eval stdout/stderr (redacted); Sentry extra carries bounded stdoutTail/stderrTail"
  retention: "Better Stack retention for app logs; Sentry event retention for extras"
discoverability_test:
  command: "gh issue list --label scheduled-roadmap-review --state all --limit 3 --json number,title,createdAt && gh issue list --label scheduled-growth-audit --state all --limit 3 --json number,title,createdAt"
  expected_output: "Most recent issue is a success '[Scheduled] …' (not a FAILED self-report) dated after the fix deploy + manual-trigger"
```

## Acceptance Criteria

### Pre-merge (PR)

#### Functional Requirements

- [ ] `DEFAULT_CLAUDE_SETTINGS` in `_cron-claude-eval-substrate.ts` has `sandbox.enabled === false`.
- [ ] `DEFAULT_CLAUDE_SETTINGS` has `permissions.defaultMode === "bypassPermissions"`.
- [ ] `permissions.allow` remains `[]` (no allowlist widening — verified by test).
- [ ] The repo-root `.claude/settings.json` is UNCHANGED (no sandbox/defaultMode edits to the dev-session file) — `git diff --name-only origin/main..HEAD` does not list `.claude/settings.json`.
- [ ] New test asserts the written `.claude/settings.json` JSON content (sandbox + defaultMode + allow), not model behavior; `vitest run apps/web-platform/test/server/inngest/` green.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean (NOT `npm run -w` — repo root declares no `workspaces`).
- [ ] `scripts/test-all.sh` green (orphan suites included).
- [ ] Runbook H2 updated to reflect sandbox-disabled cron path; learning captured.
- [ ] PR body uses `Ref #5000` / `Ref #5004` (NOT `Closes`), with closure deferred to post-merge recovery.

#### Non-Functional Requirements

- [ ] Security: deepen-plan security-sentinel + `user-impact-reviewer` reviewed the sandbox-removal trade-off against the spawn-env allowlist + scoped-token + ephemeral-workspace + trusted-prompt mitigations; no Critical finding open.
- [ ] CPO sign-off recorded (threshold = single-user incident).

### Post-merge (operator-automatable)

- [ ] Deploy lands (web-platform-release.yml on merge touching `apps/web-platform/**`).
- [ ] `/soleur:trigger-cron` fires `cron/roadmap-review.manual-trigger` + `cron/growth-audit.manual-trigger`; each produces a success `[Scheduled] …` issue with the right label within its run window.
- [ ] `gh issue close 5000 5004` after recovery confirmed, each with a comment linking the merged PR.

## Test Scenarios

### Acceptance Tests (RED targets)

- Given the current substrate, when `setupEphemeralWorkspace` writes the overlay, then the parsed `.claude/settings.json` has `sandbox.enabled === true` (RED) → after fix, `=== false` (GREEN).
- Given the fix, when the overlay is written, then `permissions.defaultMode === "bypassPermissions"`.
- Given the fix, when the overlay is written, then `permissions.allow` deep-equals `[]`.

### Regression Tests

- Given a future edit that flips `sandbox.enabled` back to `true`, when the suite runs, then the drift-guard test FAILs (anchored on the literal).
- Given the dev-session config, when `git diff` is taken, then repo `.claude/settings.json` is untouched.

### Integration Verification (for `/soleur:qa`, post-deploy)

- **API verify:** `gh issue list --label scheduled-roadmap-review --state all --limit 1 --json title,createdAt` expects a non-FAILED `[Scheduled]` title dated after the manual-trigger.
- **Recovery trigger:** `/soleur:trigger-cron` → `cron/roadmap-review.manual-trigger` (read trigger secret read-only from Doppler; no SSH).

## Dependencies & Risks

### Precedent-Diff (Phase 4.4)

The settings-overlay write pattern is NOT novel: `setupEphemeralWorkspace`
already writes `DEFAULT_CLAUDE_SETTINGS` as the canonical `.claude/settings.json`
overlay for every cron (`_cron-claude-eval-substrate.ts:157-163`). This change
edits the overlay's CONTENT only — same write mechanism, same path, same JSON
shape. No new file, no new write site. Verified: `grep -rn "sandbox"
…/functions/*.ts` returns exactly one hit (line 113) — no sibling overlay to
keep in sync. The `permissions.defaultMode` key is added to an object that
already carries `permissions.allow`; the shape is a documented settings.json
form (`code.claude.com/docs/en/settings`), not a novel structure.

### Risks

- **Risk — sandbox removal widens the bash blast radius.** Mitigated by the spawn-env allowlist, scoped short-lived token, throwaway workspace, and first-party trusted prompt (see User-Brand Impact). The sandbox's threat model (untrusted prompt/repo content) does not apply to a constant in-repo prompt.
- **Risk — `bypassPermissions` also bypasses explicit deny rules / critical-rm prompts.** There are no deny rules in `DEFAULT_CLAUDE_SETTINGS` (`allow: []`, no `deny`), so behavior is "auto-allow all requested tools" — identical to the prior sandbox-auto-approve behavior for the bash the crons already ran. Net tool-permission surface is unchanged from the working-sandbox case; only the OS isolation layer is removed.
- **Risk — the real cause is NOT bwrap-userns.** Phase 0 live-evidence gate falsifies this before any code lands.
- **Dependency — none new.** No new packages, no new infra, no new secrets. Pure code + docs change against already-provisioned surfaces (so Phase 2.8 IaC routing does not apply; the #4932 host sysctl stays as-is).

## References & Research

### Internal References

- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts:109-116` — `DEFAULT_CLAUDE_SETTINGS` (the edit target).
- `…/_cron-claude-eval-substrate.ts:157-163` — overlay write site (`setupEphemeralWorkspace`).
- `…/cron-growth-audit.ts:60-71`, `…/cron-roadmap-review.ts:94-103` — `CLAUDE_CODE_FLAGS` (Bash in allowedTools, no permission-mode → relies on sandbox auto-approval).
- `…/_cron-shared.ts:422` — `ensureScheduledAuditIssue` (the #4978 fallback that filed #5000/#5004).
- `apps/web-platform/infra/server.tf:621-624` — #4932 bwrap-userns sysctl + systemd unit (host defense-in-depth, kept).
- `apps/web-platform/infra/bwrap-userns-sysctl.test.sh` — drift-guard for the host sysctl provisioning.
- `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` — H2 (triage target; to update).

### External References

- `code.claude.com/docs/en/permissions` — "When sandboxing is enabled with `autoAllowBashIfSandboxed: true` (default), sandboxed Bash commands run without prompting."
- `code.claude.com/docs/en/sandboxing` — Bash sandbox; Managed-settings sandbox config (`enabled`/`failIfUnavailable`/`allowUnsandboxedCommands`).
- `code.claude.com/docs/en/settings` — `permissions.defaultMode` valid values include `bypassPermissions`.
- `code.claude.com/docs/en/permission-modes`, `…/headless` — `--permission-mode bypassPermissions` ≡ `--dangerously-skip-permissions`.

### Related Work

- PRs: #4975 (content-generator fallback), #4988 (cohort generalization), #4932 (sysctl fix), #4941 (revert too-strict canary), #4944 (non-blocking drift detector).
- Issues: #5000, #5004 (this fix); #4928, #4960 (prior silence incidents); #4978 (cohort generalization, closed).
- Learnings: `knowledge-base/project/learnings/2026-06-04-cron-silence-was-bwrap-userns-drift-not-turn-budget.md`; `…/integration-issues/2026-06-05-cloud-task-silence-per-producer-triage-and-handler-fallback.md`.

## Premise Validation

Checked: #5000 + #5004 both OPEN (not stale); #4960 CLOSED by #4975; #4978 CLOSED
by #4988 — so the handler fallback IS generalized to all 8 always-create
producers (the FAILED self-reports are working-as-designed, not the bug). The
bwrap-userns root cause + #4932 host fix verified present at
`server.tf:621-624`; the 2026-06-08 recurrence (post-#4932) is the load-bearing
new fact that motivates removing the cron's host-sysctl dependency rather than
re-asserting it. `DEFAULT_CLAUDE_SETTINGS` confirmed at
`_cron-claude-eval-substrate.ts:113` (the real cron settings.json, NOT repo
`.claude/settings.json`). Claude Code sandbox↔auto-approval coupling and
`bypassPermissions` `defaultMode` validity confirmed against current Claude Code
docs (not memory). No premise stale.

## Research Reconciliation — Spec vs. Codebase

| Claim (from issue bodies / directive) | Reality (verified) | Plan response |
|---|---|---|
| "set `sandbox.enabled: false` in settings.json" | The cron's settings.json is the runtime `DEFAULT_CLAUDE_SETTINGS` overlay, not repo `.claude/settings.json` | Edit the overlay; leave repo dev-session config untouched |
| "so cron jobs run gh commands without prompts" | Disabling sandbox REMOVES bash auto-approval (`autoAllowBashIfSandboxed`); naive disable breaks all crons | Pair with `permissions.defaultMode: "bypassPermissions"` |
| "the #4960 handler-level fallback" filed these | #4960 was content-generator-only; the cohort generalization is #4978/#4988 | Cite the correct provenance; the fallback is working-as-designed |
| "grant the runner the userns caps bwrap needs" | Already done in #4932 (host systemd unit); recurred 4 days later | Keep as defense-in-depth; remove the cron's dependency on it |
| roadmap-review/growth-audit are silent | They are NOT silent — they self-report FAILED (fallback works) | Fix the underlying bwrap cause, not the (correct) fallback |

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open` for
`_cron-claude-eval-substrate.ts`, `cron-growth-audit.ts`,
`cron-roadmap-review.ts`, and `DEFAULT_CLAUDE_SETTINGS` — zero matches.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Architectural blast-radius is one shared file (`DEFAULT_CLAUDE_SETTINGS`) fanning to 21 producers — the correct single-point fix vs. 14× duplicated per-producer flag edits. The security trade-off (removing OS sandbox isolation) is the load-bearing concern; it is bounded by the spawn-env allowlist, scoped short-lived token, throwaway workspace, and trusted first-party prompt. The host sysctl path (#4932/#4944) stays as defense-in-depth for non-cron sandbox consumers. deepen-plan security-sentinel + architecture-strategist + data-integrity-guardian MUST run (single-user-incident threshold) — they catch the sandbox-removal substance that style-level plan-review cannot.

### Product/UX Gate

**Tier:** none (no UI surface — orchestration/infra change; Files-to-Edit are `apps/*/server/inngest/` + runbook/learning markdown, no `components/**`/`app/**/page.tsx`)
**Decision:** CPO sign-off required at plan time (brand-survival threshold = single-user incident), NOT for wireframes (no page design) but for the product-owner ack on disabling the OS sandbox for the founder's autonomous-ops substrate.
**Agents invoked:** cpo (sign-off) — deferred to deepen-plan / review per single-user-incident staging
**Skipped specialists:** ux-design-lead N/A (no UI surface — not a UI feature, `wg-ui-feature-requires-pen-wireframe` does not fire)
**Pencil available:** N/A (no UI surface)

#### Findings

CPO sign-off is the single product-owner ack that removing the bwrap jail is acceptable given the mitigations. `user-impact-reviewer` enumerates failure modes against the diff at review time. No wireframes — this plan implements an infra/observability change, not a user-facing surface.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above: threshold = single-user incident.)
- The settings.json the issue body names is NOT the file that governs the cron. Editing repo `.claude/settings.json` would do nothing for the crons and regress dev-session security. Edit ONLY `DEFAULT_CLAUDE_SETTINGS`.
- `sandbox.enabled: false` without the `bypassPermissions` pairing is the single most likely implementation slip — it would pass a naive "sandbox is off" reading of the issue body and break every cron at first fire. The pairing is load-bearing; the regression test must assert BOTH keys.
- Tests must assert the WRITTEN settings.json content, not model behavior — keep the LLM out of the assertion path (a `query({prompt})`-driven test proves model compliance, not the config invariant).
