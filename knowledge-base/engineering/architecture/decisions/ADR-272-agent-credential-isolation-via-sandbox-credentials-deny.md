---
title: Agent credential isolation uses sandbox.credentials deny, scoped to the Anthropic auth variables
status: adopting
date: 2026-10-06
supersedes: none
issue: 9601
related: [9543, 9534, 9599]
related_adrs: [ADR-075, ADR-079, ADR-093, ADR-051]
tags: [security, credentials, sandbox, bwrap, byok, claude-agent-sdk]
brand_survival_threshold: single-user incident
---

# ADR-272: Agent credential isolation uses `sandbox.credentials` deny, scoped to the Anthropic auth variables

## Status

**Adopting — 2026-10-06.** The mechanism is measured live (below). It becomes `accepted` when the first release after PR #9599
merges shows the canary path running the re-captured fixture without a manual step. W1 of the agent-security epic #9601.

## Context

A hosted agent session runs the Claude CLI with an environment built by `buildAgentEnv` (`apps/web-platform/server/agent-env.ts`).
That environment carries the owner's Anthropic credential (`ANTHROPIC_API_KEY`, or `CLAUDE_CODE_OAUTH_TOKEN` for a subscription),
the short-lived GitHub App installation token (`GH_TOKEN`, `GIT_INSTALLATION_TOKEN`) and the owner's connected-service tokens
(`PROVIDER_CONFIG` env vars). The CLI process needs the Anthropic credential for its own API calls. The agent's `Bash` tool
commands, which a prompt-injected instruction controls, do not.

The only barrier between an injected `printenv` and the owner's key was a regex on the command text in the sandbox hook. A
review of an external article ("three layers of AI agent security") against this code found that gap to be the largest of the
exposures it could name.

## Decision

1. **Deny the Anthropic auth variables to sandboxed Bash with the SDK's per-variable `sandbox.credentials.envVars` entries**
   (`mode: "deny"`, which "unsets the variable for sandboxed commands"). `buildAgentSandboxConfig` returns the entries, built from
   one shared constant, `AGENT_AUTH_ENV_VARS` in `server/agent-auth-env-vars.ts`, which `buildAgentEnv` also injects from. A third
   auth variable therefore cannot be added to the injection side without being denied. The CLI process keeps the variable for its
   own calls.
2. **Do not set `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB`.** It strips every credential-shaped variable (by name or by value shape) from
   Bash, hook and stdio-MCP subprocesses. Connected Services depends on service tokens reaching Bash: `agent-runner.ts` tells the
   agent they are available. The scrub would revoke that promise for every connected service.
3. **Leave service tokens, `GH_TOKEN` and `GIT_INSTALLATION_TOKEN` readable for now.** They are not denied. The fix for them is a
   credential broker (#9543); the SDK's `mask` mode (below) is the in-SDK candidate for it.

## Measurements (2026-10-06, SDK 0.3.284, details in `phase-0-measurements.md`)

A scripted stand-in for the Anthropic Messages API drove one `Bash` tool call through the real SDK and the real
`buildAgentSandboxConfig` object, with decoy variable values. The model is out of the assertion path and no real credential is
involved.

- Without the deny, `ANTHROPIC_API_KEY` **is present** in sandboxed Bash. With it, absent. The CLI turn still completes.
- `CLAUDE_CODE_OAUTH_TOKEN` is **already absent** from sandboxed Bash without the deny (the CLI withholds it), while the CLI
  authenticates with it. Its entry is defense in depth against a CLI behaviour change, not a fix for a live exposure. The
  brainstorm's statement that the OAuth token reaches Bash is corrected here.
- Service tokens and `GH_TOKEN` are present in both arms: the deny touches only the named variables.
- A credentials file under the CLI's `HOME` is readable from sandboxed Bash in both arms (see Residuals).

## Rejected / deferred alternatives

- **`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`** — rejected (Decision 2). It would also cover hooks and stdio MCP servers, which the deny
  does not, but those run outside the sandbox and are not agent-authorable in a hosted session (`settingSources: []`).
- **`sandbox.credentials` `mask` mode for service tokens** — deferred to slice 2 with #9543. It shows the sandbox a sentinel and
  substitutes the real value at the sandbox proxy for requests to listed hosts, so it needs per-service `injectHosts` and matching
  `network.allowedDomains` entries. It is the placeholder-and-swap pattern the article describes, without a custom gateway.
- **A runtime flag to disable the block** — not adopted. A rejected `credentials` block surfaces at sandbox start under
  `failIfUnavailable` (Sentry `feature=agent-sandbox`) and in the canary/probe path before traffic; the rollback is a revert and
  redeploy.

## Residuals (stated so W1 is not read as complete credential isolation)

- Service tokens, `GH_TOKEN` and `GIT_INSTALLATION_TOKEN` stay readable by a prompt-injected agent until #9543.
- Any credential file readable by the server uid is readable from sandboxed Bash: the sandbox read-binds `/`, and `denyRead`
  lists only sibling workspaces, `/proc` and the C4 staging root. A workspace `.env` is readable by design.
- The deny applies to sandboxed `Bash` only. Hooks and in-process MCP tools run outside the sandbox with the full environment; the
  agent cannot author them.

## Out of scope: other places that hold an Anthropic credential

Customer BYOK reaches the CLI only through `agent-runner.ts` → `buildAgentQueryOptions` → `buildAgentEnv`. The rest are different
properties or different credentials:

| Site | Env source | Why not covered here |
|---|---|---|
| `server/inngest/functions/cron-*.ts` via `_cron-claude-eval-substrate.ts` | the **operator's** `process.env.ANTHROPIC_API_KEY`; runs with `sandbox.enabled:false` behind an allowlist hook | operator credential on platform-authored crons, not customer BYOK; its containment is the allowlist hook |
| `server/c4-render.ts` (`spawn` of the C4 renderer) | an explicit `env`; no Anthropic variable in the file | does not carry the credential |
| `server/codex-app-server-launcher.ts` | `options.environment(lease)`; no Anthropic variable in the file | a different provider's lease |
| `server/byok-lease.ts`, `server/email-triage/summarize.ts` | direct API calls, not a shell | no shell to read an environment from |

## Consequences

- P1 holds for the API key: a prompt-injected hosted session cannot read the owner's Anthropic key from a shell command.
- The canary fixture (`infra/sandbox-canary-argv.json`) is a pure function of (SDK version, sandbox config), so it is re-captured
  with this change (ADR-079). It was already stale: captured at SDK 0.3.197 against the 0.3.284 pin.
- Public security claims stay unchanged until the controls are measured in production (#9603). The Art. 30 register gains a
  measured-control entry only.

## Verification

`apps/web-platform/test/agent-sandbox-credential-deny.test.ts` (set equality with what `buildAgentEnv` injects, deny mode, service
tokens not denied; mutation-checked 7/7), the re-captured canary fixture run by the creds-gated CI path, and
`scripts/verify-agent-security-slice1.sh` as the local discoverability probe.
