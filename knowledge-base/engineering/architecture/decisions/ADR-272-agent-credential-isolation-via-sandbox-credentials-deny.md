---
title: Agent credential isolation uses sandbox.credentials deny, scoped to the Anthropic auth variables
status: adopting
date: 2026-10-06
supersedes: none
issue: 9601
related: [9543, 9599, 9614]
related_adrs: [ADR-075, ADR-079]
tags: [security, credentials, sandbox, bwrap, byok, claude-agent-sdk]
brand_survival_threshold: single-user incident
---

# ADR-272: Agent credential isolation uses `sandbox.credentials` deny, scoped to the Anthropic auth variables

## Status

**Adopting — 2026-10-06.** The mechanism is measured live (below) and guarded in CI at the config, the production-wire and the
argv level. It becomes `accepted` after the first release containing PR #9599 runs with hosted agent sessions starting normally
and the argv test green on the pinned SDK. W1 of the agent-security epic #9601.

**There is no runtime tripwire, by construction.** The SDK settings schema strips unknown keys, so an SDK that renamed or
ignored `sandbox.credentials` would start every session normally with the key exposed, and nothing would reach Sentry:
`failIfUnavailable` covers missing sandbox dependencies (bubblewrap, socat), not option acceptance. The only detector is CI: the
argv test, and the capture gate that fires on a change to the sandbox config, the names module or an SDK bump. Whoever bumps the
SDK owns that signal. (A runtime canary that probes the live image is the stronger control; it is blocked on the canary
fixture, #9614.)

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
   one shared constant, `AGENT_AUTH_ENV_VARS` in `server/agent-auth-env-vars.ts`, whose names `buildAgentEnv` also injects. The
   constant is hand-listed; what keeps it complete is a test that derives the injected set from `buildAgentEnv`'s output (a
   sentinel credential, every scheme and option shape, any key whose value carries it) and requires it to equal the denied set,
   so a third auth variable on the injection side fails that test. The CLI process keeps the variable for its own calls.
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
- The CLI parent's environment is not reachable through `/proc`: sandboxed Bash sees 6 pids in its own PID namespace, no readable
  `environ` or `ps eww` line carries the key (decoy value; counts only). The PID namespace is the barrier, not `denyRead`. Measured
  on the dev host with the production config, not inside the production container image.

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
- The owner's other LLM-provider keys (`OPENAI_API_KEY`, `AWS_ACCESS_KEY_ID`, `GOOGLE_APPLICATION_CREDENTIALS`) are connected-service
  tokens in `PROVIDER_CONFIG`, so they are readable exactly like the other service tokens, and are covered by the same #9543 follow-up,
  not by this deny. Ambient proxy variables (`HTTP_PROXY`, `HTTPS_PROXY`) pass the environment allowlist and may carry proxy credentials.
- Outbound network from sandboxed Bash is closed (`allowedDomains: []`) unless the entitled-token GitHub allowlist applies, and
  `api.anthropic.com` is never on it. That is why the deny removes nothing a session could have used from inside Bash.
- Any credential file readable by the server uid is readable from sandboxed Bash: the sandbox read-binds `/`, and `denyRead`
  lists only sibling workspaces, `/proc` and the C4 staging root. A workspace `.env` is readable by design.
- The deny applies to sandboxed `Bash` only. Hooks and in-process MCP tools run outside the sandbox with the full environment. A
  hosted session loads no project settings or hooks (`settingSources: []`), so the agent does not author them; whether sandboxed
  Bash can write a path a platform hook later executes is unmeasured.

## Out of scope: other places that hold an Anthropic credential

Customer BYOK reaches the CLI only through `agent-runner.ts` → `buildAgentQueryOptions` → `buildAgentEnv`. The rest are different
properties or different credentials:

| Site | Env source | Why not covered here |
|---|---|---|
| `server/inngest/functions/*` agent spawns (`cron-*.ts` via `_cron-claude-eval-substrate.ts`, `event-ship-merge.ts`, `oneshot-*.ts`) | the **operator's** `process.env.ANTHROPIC_API_KEY`; run with `sandbox.enabled:false` behind an allowlist hook | operator credential on platform-authored jobs, not customer BYOK; their containment is the allowlist hook |
| `server/pdf-chapter-router.ts` (`query()` for chapter routing) | passes no `env` and no `sandbox`, so the CLI inherits the server environment | a single-request routing turn, not a Bash surface; hardened in this PR with `tools: []` so no built-in tool is available to it |
| `server/c4-render.ts` (`spawn` of the C4 renderer) | an explicit `env`; no Anthropic variable in the file | does not carry the credential |
| `server/codex-app-server-launcher.ts` | `options.environment(lease)`; no Anthropic variable in the file | a different provider's lease |
| `server/byok-lease.ts`, `server/email-triage/summarize.ts` | direct API calls, not a shell | no shell to read an environment from |

## Consequences

- The owner's Anthropic API key is not readable from a sandboxed shell command, by the routes measured here (environment, `/proc`, `ps`). The deny is not a claim about any other credential.
- The deny changes the real bwrap argv: it adds `--unsetenv ANTHROPIC_API_KEY` and `--unsetenv CLAUDE_CODE_OAUTH_TOKEN`
  (measured on SDK 0.3.284). The committed canary fixture (`infra/sandbox-canary-argv.json`) is a function of (SDK version,
  sandbox config) and was **not** re-captured here: it was already stale (captured at SDK 0.3.197 against the 0.3.284 pin; see
  ADR-079) and cannot be re-captured today because the canary's projection refuses SDK 0.3.284's
  `--tmpfs <HOME>/.claude/bridge-spawn` (#9614). So the faithful canary cannot yet give a trustworthy verdict on this change; the
  deny is guarded at the argv level without the fixture (Verification).
- No plugin skill or hook calls the Anthropic API or the `claude` CLI from a hosted Bash step (grepped at review: the hits are
  CI-workflow generation, docs and the operator-side CLI hook), so the deny removes no legitimate in-session workflow.
- Public security claims stay unchanged until the controls are measured in production (#9603). The Art. 30 register gains a
  measured-control entry only.

## Verification

- `apps/web-platform/test/agent-sandbox-credential-deny.test.ts`: the config object. The injected set derived from
  `buildAgentEnv`'s output equals the denied set, deny mode, service tokens not denied.
- `apps/web-platform/test/agent-runner-query-options.test.ts`: the wire. The `sandbox` option the production factories hand
  `query()` carries the deny (default, entitled-egress and read-only shapes).
- `apps/web-platform/test/sandbox-credential-deny-argv.test.ts`: what the real SDK does with it. Drives the canary's own capture
  function (real SDK, real config, a bwrap shim) against a scripted API stand-in and asserts the real setup argv carries
  `--unsetenv` for exactly the auth variables (no service token, no later `--setenv` of them). No credential, no bubblewrap run, no
  model; about 8 seconds locally. It needs `bwrap` and `socat` on PATH for the SDK's own startup check (CI installs both in the
  webplat job). If an SDK bump stops honouring `sandbox.credentials`, this reds; it is the only detector (see Status).
- Mutation proof: an 8-row battery against these guards, each row confirmed to land, is recorded in
  `knowledge-base/project/specs/feat-agent-security-three-layers/phase-0-measurements.md` §1.4.
- `scripts/verify-agent-security-slice1.sh` as the local discoverability probe.
