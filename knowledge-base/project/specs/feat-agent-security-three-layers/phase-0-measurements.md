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

## 1.3 — can sandboxed Bash reach the CLI parent's environment through `/proc`? (review follow-up)

Raised by the security seat of the PR 1 review: the argv carries `--tmpfs /proc` early and `--bind /proc /proc` last, and the config comment said `/proc` is "already in `denyRead`". Measured with the real SDK 0.3.284 and the production `buildAgentSandboxConfig` (so `enableWeakerNestedSandbox: true`), on the dev host (not the production container), decoy API key in the CLI environment; the probe prints counts only:

| Probe inside sandboxed Bash | Result |
|---|---|
| pids visible in `/proc` | 6 (the sandbox's own PID namespace; the CLI parent is not among them) |
| `/proc/<pid>/environ` files readable | 2 |
| readable environ files containing the decoy key | **0** |
| `ps eww` lines containing the decoy key | **0** |
| `cat /proc/$PPID/environ` | readable, but `$PPID` is the sandbox's own parent, not the CLI |
| `$ANTHROPIC_API_KEY` | absent |

Conclusion: the PID namespace (`--unshare-pid`), not `denyRead`, keeps the CLI parent's environment out of reach, on this host. The comments in `agent-runner-sandbox-config.ts` were corrected. Not re-measured inside the production container image, which has its own seccomp and AppArmor profiles; the argv shape is the same.

## 1.4 — mutation proof of the W1 guards (review follow-up)

An 8-row battery run in an allocated sandbox copy, after a green unmutated control (6 files, 69 tests); every mutation was confirmed to have landed, and each reddened the named guard:

| Mutation | Guard that reddened |
|---|---|
| production factory overrides `credentials` with an empty list (the wire) | `agent-runner-query-options.test.ts` (3 cases) |
| a third auth variable set from the credential in BOTH schemes | `agent-sandbox-credential-deny.test.ts` (4 cases) |
| directive removed from the Concierge baseline prompt | `credentials-prompt-directive.test.ts` |
| directive removed from the legacy prompt builder | `agent-runner-tools.test.ts` (2 cases) |
| OAuth name dropped from the shared constant | `agent-sandbox-credential-deny.test.ts` (3 cases) |
| the names module imports `env` | `oauth-token-injection-site.test.ts` |
| `mode: "deny"` changed to `"mask"` | query-options, unit and argv tests |
| `credentials` block removed from the config | query-options, unit and argv tests |

The first two rows were survivors of the earlier self-run battery: it mutated the config builder and the constant, never the wire to the consumer and never a variable common to every scheme.

## 1.2 — customer hook-decision matrix for W2

Deferred to the start of PR 2 (non-gating for PR 1, gating for PR 2), as the plan states.
