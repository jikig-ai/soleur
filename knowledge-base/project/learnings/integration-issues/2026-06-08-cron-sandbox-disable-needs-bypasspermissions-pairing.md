---
module: _cron-claude-eval-substrate / DEFAULT_CLAUDE_SETTINGS
date: 2026-06-08
problem_type: integration_issue
component: inngest_cron
symptoms:
  - "Scheduled producers (#5000 growth-audit, #5004 roadmap-review) self-report FAILED via the handler fallback 4 days after the host sysctl fix (#4932) merged"
  - "bwrap bash sandbox cannot acquire unprivileged user namespaces in the cloud runner; every Bash tool call inside `claude --print` fails"
  - "FAILED self-report stdoutTail names 'bash-sandbox-failure' / 'grant the runner the user-namespace caps bwrap needs'"
root_cause: cron_sandbox_depended_on_host_mutable_userns_sysctl
severity: high
tags: [inngest-cron, bwrap, sandbox, bypassPermissions, claude-code-settings, observability, silent-failure, host-independence]
---

# Learning: disabling the cron bash sandbox requires the `bypassPermissions` pairing, and the real settings.json is the runtime overlay

## Problem

Two scheduled Inngest producers — `cron-growth-audit` (#5000) and
`cron-roadmap-review` (#5004) — filed automated **FAILED self-report** issues on
2026-06-08, via the working-as-designed handler-level fallback (#4978/#4988
cohort generalization). Root cause: the bash **sandbox (`bwrap`) failed to
acquire user-namespace capabilities** in the cloud runner, so every `Bash` tool
call inside `claude --print` failed and the prompt never reached its
`gh issue create` / `git push` step.

This is the **same failure class** as #4928 (roadmap-review, 2026-06-04), which
was root-caused as `kernel.apparmor_restrict_unprivileged_userns` drifting 0→1
and "durably" fixed in PR #4932 (boot-persistent `bwrap-userns-sysctl.service`).
**The recurrence four days after #4932 merged proves the host-side sysctl fix
alone is not durable for the cron path.**

## Three traps, in order

1. **The `settings.json` the issue body names is NOT the repo file.** #5000/#5004
   stdout tails say "set `sandbox.enabled: false` in settings.json." The cron's
   settings.json is the **runtime-written `DEFAULT_CLAUDE_SETTINGS` overlay** in
   `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts`,
   serialized into each ephemeral workspace's `.claude/settings.json` by
   `setupEphemeralWorkspace`. It is the SOLE sandbox-config write site across all
   inngest crons (`grep -rn "sandbox" functions/*.ts` → one hit), so editing it
   fixes the whole 21-producer fleet at once. The **repo-root**
   `.claude/settings.json` governs interactive dev sessions and must stay
   sandbox-enabled — editing it would regress dev-session security and do nothing
   for the crons. (`server/workspace.ts` `provisionWorkspace` is yet a THIRD
   settings writer — the user/agent workspace — which also correctly keeps the
   sandbox enabled.)

2. **`sandbox.enabled: false` ALONE breaks every cron.** Per Claude Code docs,
   when sandboxing is enabled with `autoAllowBashIfSandboxed: true` (default),
   sandboxed Bash runs without prompting — "the sandbox boundary acts as a
   substitute for per-command prompts." That auto-approval is the ONLY reason
   these headless `--print` crons (with `permissions.allow: []` and no
   `--permission-mode` flag) can run `gh`/`git` at all. Disabling the sandbox
   ALSO removes that auto-approval, so a naive sandbox-disable makes every bash
   command block on a prompt no headless session can answer. The fix MUST pair
   `sandbox.enabled: false` with `permissions.defaultMode: "bypassPermissions"`
   (valid `defaultMode` value per `code.claude.com/docs/en/settings`, confirmed
   against the pinned `@anthropic-ai/claude-code@2.1.142`).

3. **Chase host-independence, not the kernel sysctl.** #4932 re-asserted the
   sysctl host-side; it re-drifted. The durable fix removes the cron path's
   dependency on unprivileged userns entirely: a sandbox-disabled cron does not
   need bwrap at all. The host sysctl (#4932) + non-blocking drift detector
   (#4944) stay as defense-in-depth for any NON-cron sandbox consumer.

## Fix

```ts
// _cron-claude-eval-substrate.ts
export const DEFAULT_CLAUDE_SETTINGS = {
  permissions: {
    allow: [] as string[],
    defaultMode: "bypassPermissions", // restores bash auto-approval
  },
  sandbox: { enabled: false },        // drops the bwrap-userns dependency
};
```

## Why the security delta is bounded

`bypassPermissions` against `allow: []` with no `deny` rules = "auto-allow
requested tools" — **identical net tool-permission** to the prior
`autoAllowBashIfSandboxed` behavior. Only the OS isolation layer changes. The
sandbox's threat model (untrusted prompt/repo content) does not apply: the cron
prompt is a constant first-party in-repo string, and the spawn env is a scoped
allowlist (`PATH/HOME/NODE_ENV/ANTHROPIC_API_KEY/GH_TOKEN` only — no
`DOPPLER_*`/`SENTRY_*`/`GITHUB_APP_PRIVATE_KEY`/`RESEND_API_KEY`), `GH_TOKEN` is
a short-lived scoped installation token, and the workspace is a `--depth=1`
throwaway clone torn down after the run.

## How to test it

Assert the **written settings.json content** (the config invariant), never model
behavior — keep the LLM out of the assertion path. A `query({prompt})`-driven
test proves model compliance, not the config. Mirror the exact write expression
(`JSON.parse(JSON.stringify(DEFAULT_CLAUDE_SETTINGS, null, 2) + "\n")`) so the
assertion proves the on-disk bytes. Add a drift-guard anchored on BOTH literals
so a future edit that flips the sandbox back on (or drops the pairing) must
update the test. When extending the overlay, sweep sibling tests that assert the
written `.claude/settings.json` (`cron-bug-fixer.test.ts` exercises the real
write path via a mocked `child_process`) — `tsc` is silent on the value drift;
only the suite catches it.

## Related

- Issues: #5000, #5004 (this fix); #4928 (prior bwrap incident), #4960/#4978 (fallback lineage).
- PRs: #4932 (host sysctl), #4941 (canary revert), #4944 (non-blocking drift detector), #4975/#4988 (handler fallback cohort generalization).
- Learnings: `2026-06-04-cron-silence-was-bwrap-userns-drift-not-turn-budget.md`; `integration-issues/2026-06-05-cloud-task-silence-per-producer-triage-and-handler-fallback.md`.
