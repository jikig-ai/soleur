# Phase 0 measurements — W1 credential deny

Measured 2026-10-06 on SDK `@anthropic-ai/claude-agent-sdk` 0.3.284 with the bundled CLI, bubblewrap on the host, inside the real `buildAgentSandboxConfig` object. Probe: a local scripted stand-in for the Anthropic Messages API (first request returns one `Bash` tool call, later requests return text), so the model is out of the assertion path, no credential is used, and no real key ever enters the sandbox. All auth values were decoy sentinels; the probe prints only `PRESENT`/`ABSENT` markers, never a value. Run with `bun` (the builder imports extensionless TypeScript modules, which plain `node` cannot resolve).

## 1.1 — is `options.sandbox.credentials` honoured inline?

Bash command run inside the sandbox: tests `[ -n "$VAR" ]` for each variable and prints a marker.

| Arm | Env given to the CLI | deny entries | `ANTHROPIC_API_KEY` | `CLAUDE_CODE_OAUTH_TOKEN` | service token (`STRIPE_SECRET_KEY`) | `GH_TOKEN` | CLI turn |
|---|---|---|---|---|---|---|---|
| api-control | API key | none | **PRESENT** | absent | PRESENT | PRESENT | success |
| api-treatment | API key | both names | **ABSENT** | absent | PRESENT | PRESENT | success |
| oauth-control | OAuth token only | none | absent | **absent** | PRESENT | PRESENT | success (Bearer auth) |
| oauth-treatment | OAuth token only | both names | absent | absent | PRESENT | PRESENT | success |
| both-control | both set | none | PRESENT | absent | PRESENT | PRESENT | success |
| both-treatment | both set | both names | ABSENT | absent | PRESENT | PRESENT | success |

Conclusions:

- The inline `options.sandbox.credentials.envVars` deny **is honoured**, the CLI still authenticates, and the service token and `GH_TOKEN` are untouched. W1's mechanism works as designed.
- `ANTHROPIC_API_KEY` **is visible to sandboxed Bash by default** (control arms): the exposure is real.
- `CLAUDE_CODE_OAUTH_TOKEN` is **already withheld from sandboxed Bash by the CLI** (absent in the OAuth-only control arm, while the CLI authenticated with it). The OAuth deny entry is therefore defense in depth against a CLI behaviour change, not a fix for a live exposure; ADR-272 says so, and the brainstorm's "OAuth token reaches Bash" claim is corrected here.

## 1.1 — credentials-file residual

With a decoy `~/.claude/.credentials.json` under the CLI's `HOME`, sandboxed Bash reports it **readable** in both arms. The sandbox read-binds `/`, and `denyRead` lists only sibling workspaces and `/proc`, so any credential file readable by the server uid is readable by the agent. This is an unchanged residual that slice 1 does not close; ADR-272 records it. A workspace `.env` is readable by design (the workspace is the sandbox's writable root).

## 1.1.2 — does the deny appear as `--unsetenv` in the bwrap argv?

**Yes.** The repo's own in-image capture procedure (`node:22-slim`, pinned digest, `bun scripts/sandbox-canary.mjs --capture`, scripted API stand-in) was run on the parent commit and on the current tree, with a patched copy that writes the raw argv before projection. The raw bwrap setup argv differs only by two inserted pairs near the front, plus random socket names and proxy passwords the canary already normalizes:

```text
--unsetenv ANTHROPIC_API_KEY
--unsetenv CLAUDE_CODE_OAUTH_TOKEN
```

Both runs then fail in the canary's projection step (`host_path token '/root/.claude/bridge-spawn'`): SDK 0.3.284 adds `--tmpfs <HOME>/.claude/bridge-spawn`, which the canary has no placeholder for. The committed fixture is therefore stale (captured at SDK 0.3.197) and cannot be re-captured today; that is a separate, pre-existing defect, filed as #9614. The W1 guard does not depend on the fixture: `test/sandbox-credential-deny-argv.test.ts` drives the canary's own capture function and asserts the real argv carries both `--unsetenv` pairs.

## 1.2 — customer hook-decision matrix for W2

Deferred to the start of PR 2 (non-gating for PR 1, gating for PR 2), as the plan states.
