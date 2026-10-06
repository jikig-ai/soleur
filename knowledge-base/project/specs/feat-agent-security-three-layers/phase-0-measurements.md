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

Raised by the security seat of the PR 1 review: the shipped argv carries `--tmpfs /proc` early and `--bind /proc /proc` last, and a code comment said `/proc` is "already in `denyRead`". Measured through the real SDK 0.3.284 with the production `buildAgentSandboxConfig` (so `enableWeakerNestedSandbox: true`), on the dev host, decoy key in the CLI environment; the probe prints pids, process names and 0/1 flags only. A first run had no positive control (it could not show it could see a decoy at all); this is the corrected measurement, with a control arm.

| Arm | pids visible | readable `environ` files carrying the decoy | `$ANTHROPIC_API_KEY` in the shell |
|---|---|---|---|
| CONTROL (deny entries emptied) | 3 (bubblewrap init, `bash`, `sh`) | **2** (`bash` and `sh`) | PRESENT |
| TREATMENT (production config) | 3 (same) | **0** (pid 1 unreadable; `bash` and `sh` readable, carrying nothing) | ABSENT |

`ps eww` carried no decoy in the treatment arm. Conclusion: no process environment readable from inside the sandbox carries the key, and the probe demonstrably can find the decoy when it is there.

What this does NOT establish is why. A security-seat repro and a code-quality-seat repro, both hand-built bubblewrap runs using the shipped argv shape without the SDK, saw 700+ host pids; one found bubblewrap's init environ readable and carrying the original bytes after `--unsetenv`, the other found no readable environ at all. They disagree with each other and with the SDK-launched run on the mechanism. So the ADR and the code comments no longer attribute the result to the PID namespace (an earlier draft did); they claim the outcome only, and `sandbox-credential-deny-runtime.test.ts` repeats it, control arm included, on every CI run with real bubblewrap. Not measured inside the production container image.

## 1.5 — what does the SDK do with a malformed `credentials` block? (review follow-up)

The ADR said the SDK "strips unknown keys". Measured on SDK 0.3.284 (same harness, decoy key, deny intended for `ANTHROPIC_API_KEY`):

| Block handed to the SDK | Session | `$ANTHROPIC_API_KEY` in the shell |
|---|---|---|
| key renamed (`credentialz`) | starts, turn completes, no error | PRESENT |
| `envVars` renamed (`vars`) | starts, turn completes, no error | PRESENT |
| `envVars` a string, not an array | starts, turn completes, no error | PRESENT |
| `mode` an unknown value | starts, turn completes, no error | PRESENT |

Every malformed variant fails open and silently. There is no runtime signal for a block the SDK ignores, which is why the argv and real-sandbox tests are the detectors and why "sessions start normally" is not an acceptance criterion.

## 1.4 — mutation proof of the W1 guards (review follow-up)

Two batteries, each run in an allocated sandbox copy after an unmutated control, each row confirmed to have landed (`cmp` against the pristine file) and restored from the live tree before the next.

**Battery 1** (control green: 6 files, 70 tests). Each mutation reddened the named guard:

| Mutation | Guard that reddened |
|---|---|
| production factory overrides `credentials` with an empty list (the wire) | `agent-runner-query-options.test.ts` |
| a third auth variable set from the credential in BOTH schemes | `agent-sandbox-credential-deny.test.ts` |
| directive removed from the Concierge baseline prompt | `credentials-prompt-directive.test.ts` |
| directive removed from the legacy prompt builder | `agent-runner-tools.test.ts` |
| OAuth name dropped from the shared constant | `agent-sandbox-credential-deny.test.ts` |
| the names module imports `env` | `oauth-token-injection-site.test.ts` |
| `mode: "deny"` changed to `"mask"` | query-options, unit and argv tests |
| `credentials` block removed from the config | query-options, unit and argv tests |

The first two rows survived the earlier self-run battery, which mutated the config builder and the constant but never the wire to the consumer and never a variable common to every scheme.

**Battery 2** (after the second review round; control green except one test of mine that was wrong, see below). Each row reddened the named guard:

| Mutation | Guard that reddened |
|---|---|
| deny dropped when `serviceTokens` is non-empty (a shape no hand-picked case had) | wire test, the cases carrying service tokens |
| the options factory adds an auth key to `env` | wire test (`env` equals what `buildAgentEnv` built) |
| a transformed (base64) copy of the credential in `buildAgentEnv` | source fence on `credential.value` |
| a production-only (`NODE_ENV`) copy of the credential | source fence on `credential.value` |
| legacy call site overrides `credentials` after the builder | `agent-runner-tools.test.ts` |
| dispatcher call site rebuilds the sandbox object | `cc-dispatcher-real-factory.test.ts` (identity) |
| a sentence appended to the directive | `credentials-prompt-directive.test.ts` (exact wording) |
| support persona / CRM lead prompt loses the directive | `credentials-prompt-directive.test.ts` (each, exactly once) |
| `pdf-chapter-router` drops `settingSources` / `tools` | `pdf-chapter-router.test.ts`; `tools` also the census anchor |
| `excludedCommands` added to the config | unit test (no unsandboxed-command escape) |
| `credentials` key renamed in the config | wire, unit, argv and runtime tests |
| the names module reads `process.env` after a string containing `//` | `oauth-token-injection-site.test.ts` (parser-based comment stripping) |
| a new SDK `query()` import appears under `server/` | `sdk-query-sites.test.ts` |
| `doCapture` ignores its timeout option | `sandbox-credential-deny-argv.test.ts` (never-answering stand-in; test times out) |

**A battery row that was a false kill.** The first version of the `doCapture`-options test used a 1 ms bound, and it was red in the unmutated control: a normal capture simply finishes before a 1 ms abort matters, so the test asserted something false. The mutation row for it was therefore not a kill, and it was caught only because the control was run and read before the rows. It was replaced by a stand-in that never answers, with a 3 s bound. Measured: the abort fires and `doCapture` returns `ok: false` ("Claude Code process aborted by user") in about 5.7 s, bounded by the option and not by the 120 s default. The row above was then re-proven: green control, red when the option is ignored.

## 1.2 — customer hook-decision matrix for W2

Deferred to the start of PR 2 (non-gating for PR 1, gating for PR 2), as the plan states.
