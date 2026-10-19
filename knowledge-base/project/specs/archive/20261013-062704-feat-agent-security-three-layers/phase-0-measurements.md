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

**Date:** 2026-10-06. **CC version:** 2.1.291 (`claude --version`). **Consumer:** the W2 destructive-command guard (`plan: knowledge-base/project/plans/2026-10-06-feat-plugin-destructive-command-guard-w2-plan.md`, Phase 0.1 and 0.2). Nothing here touched production, read a credential or reached the network.

### 1.2.1 — probe method

- **Stub hook (throwaway, never committed).** A tiny bash script under a `mktemp -d /var/tmp/w2-probe.XXXXXX` directory. It appends its stdin to a file and answers a fixed envelope: `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"<ask|allow|deny>","permissionDecisionReason":"probe"}}`, optionally with a top-level `systemMessage`. A `PostToolUse(Bash)` sentinel hook appends a line when the command actually executes, so "executed" is observed, not inferred. Both are wired through a throwaway `--settings` file.
- **Scripted Anthropic stand-in.** `apps/web-platform/test/helpers/anthropic-stub.ts` was read; its behaviour was reproduced in a throwaway Node script (one `Bash` tool_use per tool-carrying request without a `tool_result`, plain text otherwise; the repo helper is TypeScript and takes one fixed command). One extension was needed and is the only deviation: for the subagent rows, a main-thread request that carries an `Agent` tool answers with an `Agent` tool_use whose prompt contains a marker, and the subagent's own request (marker in its first message) then answers with the `Bash` tool_use. The model is out of the assertion path: every row observes the harness, never a model's compliance.
- **No network beyond loopback, enforced.** Every run executes inside `unshare -rn bash -c 'ip link set lo up; exec unshare -U --map-user=1000 --map-group=1000 bash <inner>'` (a network namespace whose only interface is `lo`, with a nested user namespace mapping back to uid 1000 so `bypassPermissions` is not refused as root). `curl https://example.com` inside it exits 7. `ANTHROPIC_BASE_URL=http://127.0.0.1:18765`, `ANTHROPIC_API_KEY=sk-ant-probe-dummy` (a placeholder, not a credential), a fresh `CLAUDE_CONFIG_DIR`, `DISABLE_AUTOUPDATER=1`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, and every inherited `CLAUDE*` / `AI_AGENT` variable unset (the parent session's `CLAUDE_CODE_ENTRYPOINT` and friends otherwise leak into the probe).
- **Headless rows:** `claude -p "run it" --settings <stub settings> --output-format stream-json --verbose --permission-mode <mode> </dev/null`. **Interactive rows:** the same `claude --settings <stub settings> --permission-mode <mode>` in a detached `tmux` (200x50) inside the same namespace, `run it` typed, the pane captured at 8, 18 and 23 s. The fresh config dir is seeded with a `.claude.json` (`hasCompletedOnboarding`, the project trust flag, the placeholder key approved) because first-run onboarding otherwise opens a connectivity check against `api.anthropic.com` and stalls.
- **Controls run and read before the rows:** `allow` executes (sentinel fired, `permission_denials` 0, tool_result `probe-allow`); `deny` blocks (sentinel absent). So the sentinel can distinguish the cases.

### 1.2.2 — customer hook-decision matrix (CC 2.1.291)

| Row | Result | CC version | Command shape |
|---|---|---|---|
| `claude -p`, `ask` (default flags) | NOT executed. Stream has a `system/permission_denied` event (`decision_reason_type: "hook"`, `decision_reason: "probe"`); the agent's `tool_result` is `is_error: true` with content EXACTLY the reason (no prefix); `result.permission_denials` has 1 entry; the turn completes (`subtype: success`, `terminal_reason: completed`) so the run degrades to a block, never an allow. Re-confirms the 2.1.142 row | 2.1.291 | headless, no `--permission-mode` |
| **Headless default mode** | With no flag the init event reports `permissionMode: "auto"` in this configuration (fresh config dir, API-key auth). The hook payload's `permission_mode` is `auto`. Interactive default reports `default` and the footer says `manual mode on` | 2.1.291 | init event of the row above; interactive pane |
| `claude -p`, `ask`, `--permission-mode default` / `dontAsk` / `auto` / `acceptEdits` / `plan` | Identical to the first row in all five: sentinel absent, `permission_denied` event with the hook reason, `is_error` tool_result carrying the reason. `permission_mode` in the payload equals the flag | 2.1.291 | `--permission-mode <m>` |
| `claude -p`, `ask`, `--permission-mode bypassPermissions` | STILL BLOCKED (sentinel absent, 1 denial, reason as tool_result). Re-confirms ADR-264 row 2 headless | 2.1.291 | `--permission-mode bypassPermissions` |
| `claude -p`, `deny`, `default` and `bypassPermissions` | Blocked; the agent's `tool_result` is `is_error: true`, content `PreToolUse:Bash hook error: <reason>` (a prefix the `ask` path does not carry). Deny holds under `bypassPermissions` | 2.1.291 | `PROBE_DECISION=deny` |
| Interactive, `ask`, `default` | Prompt shown to the person: `Hook PreToolUse:Bash requires confirmation for this command:` then the reason, then `1. Yes / 2. No`. The call waits; the sentinel did not fire before the prompt | 2.1.291 | tmux, `--permission-mode default` |
| Interactive, `ask`, `bypassPermissions` | STILL PROMPTS (same prompt). Payload `permission_mode: "bypassPermissions"`. Re-confirms ADR-264 row 2 interactively | 2.1.291 | tmux, `--permission-mode bypassPermissions` |
| Interactive, `ask`, `dontAsk` | STILL PROMPTS the person (it is NOT auto-denied interactively, unlike headless where the same mode blocks). Payload `permission_mode: "dontAsk"` | 2.1.291 | tmux, `--permission-mode dontAsk` |
| Interactive, `ask`, `auto` | STILL PROMPTS the person. The stand-in logged no classifier request before the prompt, so the hook's `ask` is not resolved by the auto-mode classifier. Payload `permission_mode: "auto"`. The classifier itself (a real model) was not exercised: see UNMEASURED | 2.1.291 | tmux, `--permission-mode auto` |
| Subagent turn, headless, `ask` | The hook FIRES for the subagent's Bash call (1 hook call, 0 from the main thread). Payload carries `agent_id` (e.g. `a6c5ef98c8398feb7`) and `agent_type: "general-purpose"`; both keys are absent on a main-thread call. The `ask` is auto-denied (no person in `-p`): subagent `tool_result` `is_error: true` with the reason, `parent_tool_use_id` set, 1 `permission_denial`, sentinel absent. `allow` runs it (sentinel 1), `deny` blocks it (`PreToolUse:Bash hook error: probe`) | 2.1.291 | stand-in with `Agent` extension, `--permission-mode default` |
| Subagent turn, interactive, `ask` | The `ask` REACHES THE PERSON, labelled `Bash command · from the general-purpose agent`, same prompt text, while the main thread shows `Waiting for 1 background agent to finish`. This CC version launches the subagent asynchronously (`Async agent launched successfully`) | 2.1.291 | tmux, `--permission-mode default` |
| Long multi-line `permissionDecisionReason` (815 chars: rule id, quoted command, stop instruction, escape hatch, URL) | Rendered IN FULL in the interactive prompt (soft-wrapped, newlines kept, no truncation); delivered IN FULL to the agent as the headless `tool_result`. So the D4 reason is not clipped on either surface | 2.1.291 | `reason.txt` read by the stub hook |
| Top-level `systemMessage` on a `deny`, interactive | SURFACED to the person: the transcript shows `Ran 1 shell command` then `PreToolUse:Bash says: <systemMessage>`. WITHOUT a `systemMessage`, the person sees only the collapsed `Ran 1 shell command`: the `permissionDecisionReason` of a deny is NOT shown in that view (the agent sees it; the person does not) | 2.1.291 | tmux, `PROBE_DECISION=deny`, with and without `PROBE_SYSMSG` |
| Top-level `systemMessage`, headless | In `--output-format stream-json` it appears as a `system/informational` event (`level: "notice"`, `content: "PreToolUse:Bash says: <msg>"`) on deny, ask and allow alike. It is absent from `--output-format text` output and absent from the agent's `tool_result` | 2.1.291 | `-p`, `PROBE_SYSMSG` set |
| Top-level `systemMessage` on an `ask`, interactive | Not rendered in the prompt while the prompt is pending (the prompt shows only the reason) | 2.1.291 | tmux, `PROBE_DECISION=ask` |

**Reading for the Decision Set (no contradiction found; two clarifications):**

- **D3 holds on 2.1.291.** `ask` blocks headless in every permission mode and holds under `bypassPermissions` headless and interactive. Clarification to add to the ADR: in an INTERACTIVE session `dontAsk` and `auto` still show the prompt (they do not auto-deny or auto-approve a hook `ask`), while HEADLESS `dontAsk`/`auto` block it. Nothing in the matrix lets a hook `ask` become an allow without a person.
- **D4's conditional clause fires.** The plan says: "If Phase 0.2 shows `systemMessage` renders to the person on a deny, it is added so the person sees the reason without the agent relaying it." It does render, and it is the ONLY way an interactive person sees why a deny happened. D4 therefore adds a top-level `systemMessage` carrying the rule id and the quoted command on every `deny` (the `rm` of `/`, home or an ancestor). On `ask` the prompt already shows the full reason, so no `systemMessage` is needed there.
- **D9's subagent coverage holds.** The hook fires for subagent Bash calls, the envelope carries `agent_id` and `agent_type`, and an `ask` reaches the person interactively (and auto-denies headless).

### 1.2.3 — UNMEASURED rows

- **Hosted Agent SDK `ask` path:** dropped by the plan (D8 disables the hook there); needs a measured hosted `ask` path before it is enabled.
- **A real model's reaction to a block** (whether it obeys "do not retry or rephrase", or tries a rephrased command): needs a paid turn and a credential; the stand-in cannot answer it. Not measured and not claimed.
- **The auto-mode classifier on a real model:** the stand-in cannot play the classifier, so only "the hook `ask` is not resolved by the classifier before the prompt" is measured, not what the classifier does with non-hook asks.
- **Answering the interactive prompt** (Yes, No, Esc) for the main thread and for the subagent: only the appearance and blocking of the prompt was captured, the answer path was not driven.
- **The expanded transcript view (ctrl+o) of a deny:** the "person does not see a deny reason" row is for the default collapsed view only.
- **Subagent under `bypassPermissions`, `dontAsk` and `auto`**, and **`claude -p` on CC 2.1.142 / 2.1.287:** not re-run; the earlier rows in `.claude/hooks/DEFER-DECISION-PAYLOAD-SHAPE.md` stand for those versions.
- **Devin's `ask`:** unmeasured by design (D9 records `skip`).

## 0.1 — W2 read-only checks (ADR ordinal, registry parity, vacuity-floor constraints)

- **a. ADR ordinal.** `git fetch -q origin main; git ls-tree -r origin/main --name-only | grep decisions/ADR-27` lists ADR-270 to ADR-273 only; no ADR-274 exists on `origin/main`. The highest is still ADR-273, so ADR-274 stays the provisional ordinal.
- **b. Registry parity dry run.** The tree needed by `.claude/hooks/devin-matcher-parity.test.sh` (`.claude`, `.devin`, `plugins/soleur/hooks`, `scripts`, copied with `git ls-files -z … | tar`) was copied to a `mktemp -d /var/tmp/w2-parity.XXXXXX` scratch dir; the working tree was not modified. Baseline: `PASS=9 FAIL=0`. After adding one `PreToolUse` entry with matcher `^Bash$`, timeout 10, pointing at a dummy `plugins/soleur/hooks/w2-dummy-guard.sh`, and NO ledger row: `PASS=8 FAIL=1`, and the only failure is T1 with exactly one message: `missing ledger row in devin-dispositions.tsv: soleur-plugin plugins/soleur/hooks/w2-dummy-guard.sh PreToolUse ^Bash$`. T2 to T9 stayed green: no `claude-settings` row and no `.claude/settings.json` entry is demanded, and `^Bash$` matches no Devin tool name (`exec`), so T4 sees no double-fire. Adding the one row `soleur-plugin<TAB>plugins/soleur/hooks/w2-dummy-guard.sh<TAB>PreToolUse<TAB>^Bash$<TAB>skip<TAB><non-empty reason><TAB><evidence>` (7 tab-separated fields; `skip` requires a non-empty reason, T6) returned the suite to `PASS=9 FAIL=0`. **D9 stands: ONE `soleur-plugin` row, no settings entry.**
- **c. `scripts/guard-vacuity-floor.test.sh` constraints for a new suite under `plugins/soleur/test/`.** To be scored FIRES (and not NO_FIRE or CONSTRUCTION):
  1. Be a git-TRACKED `*.test.sh` and not a symlink (the sweep is `git ls-files '*.test.sh'`; an uncommitted or symlinked suite is invisible to it).
  2. Be floor-bearing by SHAPE: a counter the file increments as `X=$((X + 1))` or `((X++))`, compared at a CONDITIONAL OPENER (`if`/`elif`, at line start) with `-lt`, `-le` or `-ge` in `[[ ]]` or `[ ]`, or `<`, `<=`, `>=` in `(( ))`, against that counter or a variable derived from counters in one step (`total=$((pass + fail))`). `-ne`, `-gt` and `-eq` are not matched, so a floor spelled that way is invisible. Comment lines and heredoc bodies never count.
  3. It lands in `COVERED_DIRS` (`^(scripts/|plugins/soleur/test/|plugins/soleur/scripts/)`) automatically, so the gate builds a mutant for it: the slice from the floor `if` to its matching `fi` (same indentation), plus the contiguous simple assignments directly above it (threshold bindings; an arithmetic `$((…))` is carried, a `$(…)` is not), with `command_not_found_handle() { return 0; }` defined (every undefined helper name becomes a silent no-op) and every counter zeroed. The threshold must therefore be a LITERAL (or a literal-bound variable) on the lines directly above the `if`, not computed by suite setup, or the mutant dies unbound and scores CONSTRUCTION.
  4. The floor must REPORT by a direct `printf`/`echo` + `exit 1` in that block, never through `fail()`/`bad()`/`assert()` (neutered, they are no-ops and the mutant exits 0 = NO_FIRE, which reddens ARM 1). The message must contain a sentinel from the oracle vocabulary (`[FATAL]`, `FAIL:`, `vacuity`/`vacuous`, `assertion floor`, `anti-vacuity`, `only <digit>`, `did not execute`, `assertions ran`, `cardinality`), and must not start with `fatal:` or `error:` (a tool error is CONSTRUCTION). Bash's own `path: line N:` diagnostics are stripped before matching.
  5. Where the suite carries a conservation check (`[FATAL] accounting` sentinel, identity `$((A + B)) -ne "$C"`), ARM 10d requires the case counter `C` to be incremented at the call site, never inside a verdict helper, and ARM 10 counts it toward the conserving ratchet. Plan 1.1 already prescribes this shape.
  6. Ratchets: `MAX_CONSTRUCTION_FAILURES=15` (a new CONSTRUCTION suite can redden ARM 2), `MIN_FIRING_SUITES=47` is an absolute floor that new FIRES suites only raise the margin of (the header says to expect it to be raised in the same commit; it is not required to), and the deferred ledger (`MAX_DEFERRED=47`) must not grow, which is why the suite must sit in `plugins/soleur/test/`, not a deferred directory. Each of the three planned suites (`destructive-command-guard-hook`, `shell-argv-parity`, `destructive-command-guard-mutation`) is judged separately if it has a floor.
- **d. Headless and cron surfaces that load the plugin.** `grep -l "soleur@soleur-marketplace" .github/workflows/*.yml` returns two files:

  | Surface | Loads the plugin hooks? | Can it issue a destructive command? | Needs `SOLEUR_DISABLE_DESTRUCTIVE_GUARD`? |
  |---|---|---|---|
  | `.github/workflows/test-pretooluse-hooks.yml` (`claude-code-action`, `plugins: 'soleur@soleur-marketplace'`, `--allowedTools Bash,Read,Write,Edit,Glob,Grep`) | YES, from the marketplace's `main`, so it inherits the hook once released | Its prompt runs `rm -rf .worktrees/test-hook-verification` (a child of the working directory, not an ancestor), `terraform apply -no-color` (not `destroy`, and not `-destroy`), `git commit`, `gh pr merge 1 --delete-branch --squash`, `git add`, `git reset`. None is in D1. A model that improvises a destroy, a default-branch force-push or an `rm -rf` of `/`, `~` or an ancestor would hit `ask` and be blocked headless, which is the intended outcome | No |
  | `.github/workflows/scheduled-marketplace-drift.yml` (matches only through `scripts/plugin-delivery-canary.sh` `PLUGIN_ID`) | Installs and inspects the plugin with `claude plugin install/list`; starts no agent turn, so no hook executes | No | No |

  Other `claude-code-action` workflows (`claude-code-review.yml` loads `code-review@claude-code-plugins`, not Soleur; `scheduled-machinery-drain.yml` and `fix-constraints-stage-a.yml` pass no `plugins:`) do not load `plugins/soleur/hooks/hooks.json`.

  `plugins:` spawns under `apps/web-platform/server`: exactly one binding, `plugins: [{ type: "local", path: trustedPluginPath }]` in `agent-runner-query-options.ts` `buildAgentQueryOptions`, reached by BOTH the legacy `startAgentSession` (`agent-runner.ts`) and the Command Center dispatcher (`cc-dispatcher.ts`). It sets `settingSources: []`, which does NOT exclude the plugin's `hooks.json` (the `agent-env.ts` comment on `SOLEUR_DISABLE_UNKEPT_PROMISE_HOOK` says so). A hosted agent has an arbitrary Bash surface (prompt-injected or confused model) and CAN issue the D1 commands, but runs in the bwrap sandbox behind `canUseTool`/`permission-callback.ts`; the hosted `ask` path is unmeasured, so a hook `ask` there must not be relied on: **it NEEDS the disable env (D8: `AGENT_ENV_OVERRIDES`).** `pdf-chapter-router.ts` runs `query()` with `tools: []`, `settingSources: []` and no `plugins:`, so it loads no plugin hook and needs nothing. `sdk-query-sites.test.ts` already pins the set of session-starting sites.
- **e. Do this repo's own sessions load the plugin hooks?** `.claude/settings.json` has no `enabledPlugins` and no `extraKnownMarketplaces`; its hooks are the `.claude/hooks/*` registrations. Contributors load the plugin explicitly (`CONTRIBUTING.md` "Getting Started": `claude --plugin-dir ./plugins/soleur`, and per-worktree `claude --plugin-dir "$PWD/plugins/soleur"`), and the maintainer's user-level `~/.claude/settings.json` sets `enabledPlugins: {"soleur@soleur": true}`. So YES: a contributor session that loads the plugin runs BOTH the `.claude/settings.json` hooks and `plugins/soleur/hooks/hooks.json`. Consequence for the double-prompt note: on the overlap the decision precedence is deny > defer > ask > allow (recorded in the W2 plan's Research Reconciliation table from ADR-264; not re-measured here), so (1) `rm -rf` of `/`, `$HOME`, repo or worktree roots and ancestors: `guardrails.sh` `block-recursive-delete` already DENIES, the plugin `deny` agrees, no prompt; (2) `terraform|tofu apply -destroy` and `git push [-f|--force|--force-with-lease] origin main|master|HEAD:main|HEAD:master`: `.claude/hooks/prod-write-defer-gate.sh` already DEFERS, which outranks the plugin's `ask`, so the plugin hook is shadowed, not doubled; (3) plain `terraform|tofu destroy`, a force-push to a default branch spelled any other way (`+main`, `--delete`, `-C dir`, a second remote), and the ancestor-of-cwd `rm`: no repo-local hook covers them, so the plugin hook is the SOLE `ask`. There is therefore no double prompt; the note should say the plugin hook adds asks the repo hooks do not have. **Correction to D9's reasoning:** "this repo's own sessions are already covered by `guardrails.sh`" is true only for the recursive-delete deny set; destroy and the non-literal force-push shapes are covered in this repo only when the plugin is loaded.

Probe artifacts (the stub hook, the scripted stand-in, the throwaway settings, the config dir, the parity scratch tree) live under `/var/tmp/w2-probe.*` and `/var/tmp/w2-parity.*` and are disposable; none is committed.

## 1.6 — W2 mutation rows 9-20 (run once at work time)

Method. Rows 9-20 of the Guard 1 mutation matrix in `knowledge-base/project/plans/2026-10-06-feat-plugin-destructive-command-guard-w2-plan.md` (rows M1-M8 run in CI by `plugins/soleur/test/destructive-command-guard-mutation.test.sh`). Each row was split into one or more mutants (43 in all), each a content-anchored edit of a COPY of `plugins/soleur/hooks` and `plugins/soleur/test/lib` in a temp dir (never the working tree), proven to have landed (anchor found the stated number of times, the edited file differs from the pristine copy, no other file differs, the mutant still parses with `bash -n` or `perl -c`). The FULL hook suite (`GUARD_REPO_ROOT` pointed at the copy, no `DCG_ROWS`) ran against each; the unedited control ran first and was 479/479 green (485/485 after the rows added below). KILLED = exit 1 with at least one `[FAIL]` row. The harness was a throwaway script, not committed; these rows are not run in CI.

Result: 43 mutants. First run: 35 killed, 6 survived, 2 errored (one malformed edit, one hang). After inspecting each: 5 survivors were fixture-inadequate (six rows added to the hook suite in commit 1542bef499, floor 479 -> 485, and each of those mutants was re-run and is now killed), 1 survivor is an equivalent mutant, the malformed edit was repaired and re-run (killed), and the hang is a kill by timeout. No survivor revealed a gap in the hook, so the hook was not changed.

| Row | Mutant | Result | First `[FAIL]` row (the designed detector) |
|---|---|---|---|
| 9 | stop unwrapping `bash -c` and `eval` (lexer) | killed (16 rows) | `bash -c 'rm -rf ~'` want deny, got none |
| 10 | also scan the raw decoded command text (matches inside quotes and heredoc bodies) | killed (100 rows) | `rm -rf ~` want deny, got ask; the must-PASS quoted-text and heredoc rows |
| 11 | a mid-word `#` starts a comment | killed (2 rows, both lexer-contract) | `lexer: a mid-word hash is not a comment` |
| 12 | `&>`, `>\|`, `>&`, `<&` no longer read as redirects | killed (1 row, lexer-contract only) | `lexer: a redirect is not a separator (two commands, not four)`. No hook-level row can see this class: over-splitting never turns a destructive command into an allow, so the lexer-contract row is the only detector, by design |
| 13a | `rm`: capital `-R` not recursive | killed | `rm -Rf $HOME` |
| 13b | `rm`: `--recursive` not recognised | killed | `rm --recursive --force ~` |
| 13c | `rm`: flags after a target ignored | killed | `rm ~ -rf (flags after the target)` |
| 13d | `rm`: command word not reduced to its basename | killed (6 rows) | `/bin/rm -rf ~` |
| 13e | `rm`: `--` end-of-options no longer honoured | SURVIVED, fixture-inadequate; killed after the fix | no row put a recursive-looking word after `--`; added `rm -- -rf ~` (none) |
| 14a | resolver follows a bare symlink | killed | `rm -rf . (rm refuses it)` want none got ask (and the bare-symlink row) |
| 14b | `$HOME` and `${HOME}` not resolved | killed (9 rows) | `rm -Rf $HOME` |
| 14c | `~/` forms not expanded | killed | `rm -rf ~/` |
| 14d | `/*` glob suffix not read as contents | killed (14 rows) | `rm -rf ~/* (contents of home)` |
| 14e | relative target resolved against the hook's own cwd | killed by TIMEOUT (both runs, rc 124 after 170 s) | a relative path with no `/` makes the longest-existing-prefix walk in `resolve_phys` loop forever. Unreachable in the shipped hook (every target is made absolute against the simulated cwd before the call, and the hook has a 10 s harness timeout), so recorded as a kill by hang, not a gap |
| 14f | nonexistent-parent walk cut (`RP=""; return 1`) | SURVIVED, fixture-inadequate; killed after the fix | no row reached an ancestor of home through a nonexistent directory with `..`; added the literal row `rm -rf <nonexistent home>/nonexistent-dir/../..` (deny) |
| 15 | `cd`, `pushd`, `popd` not modelled | killed (14 rows) | `cd ~ && rm -rf ./*` want deny got none |
| 16a | remote HEAD never read (only `main` and `master` default) | killed (18 rows) | `boundary: git pu\sh -f origin trunk` |
| 16b | only `origin` consulted | killed | `the second remote's own HEAD` |
| 16c | `git -C <dir>` not parsed | killed | `git -C dir push -f origin trunk` |
| 16d | no-refspec current-branch default not checked | killed (6 rows) | `git -C dir push -f with the current branch default` |
| 17a | `--force-with-lease` and `--force-if-includes` not force | killed (4 rows) | `git push --force-with-lease origin trunk` |
| 17b | `-f` inside a short cluster (`-fu`) not force | killed (20 rows) | `boundary: git pu\sh -f origin trunk` |
| 17c | `+refspec` not a force | killed (4 rows) | `git push origin +trunk` |
| 17d | `HEAD:+main` destination-side `+` not a force | killed | `git push origin HEAD:+trunk` |
| 17e | `:ref` not a delete | killed | `git push origin :main` |
| 17f | `refs/heads/` not stripped | killed | `git push --force origin refs/heads/trunk` |
| 17g | `-o <value>` before the remote not consumed | killed | `git push -o x before the remote` |
| 17h | `--force --all` and `--mirror --force` not asked | killed (3 rows) | `git push --force --all origin` |
| 17i | `--delete` not a delete | killed | `git push --delete origin trunk` |
| 17j | `src:dst` reads the source as the destination | killed (7 rows) | `git push origin feature:trunk -f` |
| 18a | `sudo` not unwrapped | killed (8 rows) | `sudo -u x rm -rf ~` |
| 18b | rule table not retried after `--` | killed (6 rows) | `doppler run -- rm -rf ~` |
| 18c | `command -v` unwrapped like `command` | SURVIVED, fixture-inadequate; killed after the fix | the only `command -v` rows (`command -v rm`, `command -v terraform`) carry no recursive flag or `destroy`, so unwrapping them changes nothing; added `command -v rm -rf ~` (none: a look-up only, `rm` never runs) |
| 18d | `timeout` duration argument not skipped | killed (4 rows) | `timeout 5 rm -rf ~` |
| 18e | `sudo -u <user>` value not skipped | killed after repair (the first edit was malformed: a bare `:` where a case pattern belongs) | `sudo -u x rm -rf ~` |
| 18f | `env`: an assignment (`FOO=1`) not skipped in the wrapper | SURVIVED, EQUIVALENT | the wrapped command is then `FOO=1 terraform destroy`, and `decide_argv` skips leading assignments itself at the next depth, so the wrapper's own assignment skip is redundant. No input distinguishes the two |
| 18g | leading `VAR=value` prefix not skipped | killed | `an assignment prefix` |
| 19a | 32-record cap raised as a lexer bound | SURVIVED when run, and not killable as worded; superseded by 19a-hook | the row mutated the lexer's `$MAX_RECORDS = 32`. The shipped lexer declares that variable and never reads it (the header of `shell-argv.pl` calls it inert), so no input can tell the edit from the original, and the "killed after the fix" this row used to carry named no edit. What the run did show is real and kept: the old "more than 32 benign commands" row carried no keyword and no boundary character, so the zero-spawn prefilter skipped the lexer and a cap in the lexer path was never reached (a quoted variant was added then) |
| 19a-hook | the record cap in the hook (`MAX_RECORDS=2000`) raised to 200000, and lowered to 1000 (measured fix round 2, 2026-10-07, on a copy of the tree, each edit proved landed with a cmp against a pristine copy and exactly one differing file) | killed, both directions | raised: `bound: 2600 benign commands (above the record cap) then rm -rf / asks with the bound reason, in under 5 s` want ask got deny; lowered: `bound: 1500 benign commands then rm -rf / still denies, in under 5 s` want deny got ask |
| 19b | fixed 4096 lexer budget | killed | `a ~90 KB heredoc lexes within the bounds` |
| 19c | a bound trip (exit 3) read as an allow | killed | `a substitution nested past the depth bound asks` |
| 20a | kill switch also read from `$CLAUDE_PROJECT_DIR/.claude/settings.json` | killed | `a project settings file that sets the switch is not read by the hook` |
| 20b | kill switch also read from `./.env` in the process cwd | SURVIVED, fixture-inadequate; killed after the fix (37 rows) | the old decoy `.env` sat in the envelope's `cwd`, not the hook process's working directory, so a hook reading `./.env` never found it; the decoy now sits in the process cwd, plus a `.claude/settings.json` there |
| 20c | header no longer documents the settings-env route | killed | `the header documents that a settings-level env block can set the kill switch` |

Reading of the survivors. "Fixture-inadequate" means the hook is correct and the mutant is a behaviour the old rows could not distinguish; the fix is a row, not a hook change. The one survivor labelled equivalent (18f) has no distinguishing input. The prefilter finding (19a) is worth keeping in mind for future rows: a benign must-PASS row with no keyword and no boundary character never reaches the lexer, so it proves the prefilter, not the lexer.
