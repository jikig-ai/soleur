# Phase 0 measurements: cron spawn isolation (#12824)

Local only: no production host, no SSH, no prd config. Every arm ran under a fresh HOME inside the
session scratch directory, with a minimal `env -i` child environment and a dummy `GH_TOKEN`
(`dummy-not-a-token`). The probe records only `set`/`unset` for `GH_TOKEN`.

- **CLI:** `@anthropic-ai/claude-code@2.1.321`, the pin in `apps/web-platform/package.json`, invoked as
  `npx --yes @anthropic-ai/claude-code@2.1.321`. `--version` printed `2.1.321 (Claude Code)`.
- **Probe:** `probes/cli-isolation-probe.sh`. Re-run one arm with
  `PROBE_SCRATCH=<abs scratch dir> bash probes/cli-isolation-probe.sh --arm <id> [--api mock|real]`.
- **Flag shape:** the same as `spawnClaudeEvalUnguarded` combined with a cron's `CLAUDE_CODE_FLAGS`:
  `--strict-mcp-config --append-system-prompt <text> --output-format json --print --model haiku
  --max-turns N --allowedTools <list> --plugin-dir <abs> -- <prompt>`. The probe plugin sits inside the
  spawn cwd, the way `<clone>/plugins/soleur` does in prod. The npm cache lives outside HOME, so the HOME
  file list shows only what the CLI wrote.
- **Git pin:** `GIT_CONFIG_GLOBAL` and `GIT_CONFIG_NOSYSTEM=1`, as in `CRON_GIT_CONFIG_PIN`. The host has
  no `/usr/local/share/soleur/agent.gitconfig`, so the probe writes the same bytes the Dockerfile writes
  into a scratch file and points the pin there.

## API mode and spend disclosure

Doppler `soleur/dev` and `soleur/dev_personal` hold no `ANTHROPIC_API_KEY`. Both
`doppler secrets get ANTHROPIC_API_KEY -p soleur -c dev --plain` and the same command with `-c dev_personal`
failed with `Doppler Error: Could not find requested secret: ANTHROPIC_API_KEY`. No `anthropic` or `claude`
secret name exists in `dev`, `dev_personal` or `dev_scheduled` either. So the **plan-literal real-API arms
did not run** (`not-run: no dev key`). That covers 0.1, 0.2, 0.3, 0.4, 0.5 and 0.7g, which would have
been 8 haiku runs.

In their place, the probe's `--api mock` mode pointed `ANTHROPIC_BASE_URL` at a local scripted
Messages-API mock (python3 on 127.0.0.1) and used a dummy key. The mock sends a fixed tool-call sequence
for each arm and logs every request body. Hooks, the Bash tool, the permission layer, shell rc
handling, skill expansion and CLAUDE.md loading all run inside the real pinned CLI, so the measured
behaviour is the CLI's own. The one thing a mock cannot show is what a real model chooses to do.
Where a verdict depends on that, it says so.

**Real API runs: 0. API spend: USD 0.** Every CLI spawn had `ANTHROPIC_BASE_URL` set to 127.0.0.1, so no
request reached the Anthropic API. There were about 20 mock spawns in total, counting prototyping and
re-runs after probe fixes. With `--api real`, the probe would make 8 haiku runs, each with `--max-turns`
of 6 or less and `--max-budget-usd 0.05`.

## Results

| Arm | Verdict (pre-written branch) | One-line evidence |
| --- | --- | --- |
| 0.1 | matched: marker absent | no `--plugin-dir`: no SessionStart marker and no hook log |
| 0.2 | matched: result event | `{"type":"result","is_error":false,"num_turns":1}`; session marker present |
| 0.3 | matched: hook runs, edited body runs | hook fired on every Bash call with `gh_token=set`; after a python write, `echo two` logged `EDITED-VIA-INDIRECT`. The CLI itself denied the Edit tool and `sed -i` on the path |
| 0.3c | matched: control holds | `chmod -R a-w`: Edit and sed were denied by the CLI, python got `PermissionError`, no `EDITED*`, file unchanged |
| 0.4 | in-run, and cross-run too | `[]` then `[sourced]` in the same run, `[sourced]` in spawn B; Write and a literal `$HOME/.bashrc` Bash write were denied, an indirect Bash write succeeded |
| 0.5 | matched: absolute | emitted `bash "<abs plugin root>/scripts/x.sh"`; x.sh ran |
| 0.6 | matched: help works, browser missing (`unverified-in-image`) | `--help` exit 0; under an empty HOME the chromium `Executable doesn't exist`, and channel `chrome` is `not found at /opt/google/chrome/chrome` |
| 0.7a | matched | commit author `github-actions[bot] <41898282+…>`; `gh api /rate_limit` returned `Bad credentials (HTTP 401)` |
| 0.7b | matched (record only) | `bun install --frozen-lockfile` exit 124 and `npm ci` exit 124 (both hit the 180 s timeout) |
| 0.7c | matched | uid 1001 → `EACCES`, root → `EROFS` |
| 0.7d | matched | `git branch -r`: `origin/HEAD -> origin/main`, `origin/main` only |
| 0.7e | **MISMATCH** | libs resolved and the worktree landed in the clone, but the script exited 1 with `reason=bot-global-refused` |
| 0.7g | matched: canary REACHES context | both `.git/` canaries appear in Anthropic-bound request bodies |
| 0.7h | matched: exclusion holds | without `claudeMdExcludes` both `.git/` canaries and the nested md reach context; with the shipped list only the root `CLAUDE.md` does. The `@/proc/self/environ` import reached context in neither run |

## Per-arm detail

### 0.1 Negative control

- **Command:** `npx --yes @anthropic-ai/claude-code@2.1.321 --strict-mcp-config --append-system-prompt … --output-format json --print --model haiku --max-turns 2 --allowedTools Bash -- "Reply with the word ok."`, with no `--plugin-dir`.
- **Output:** CLI exit 0, `{"type":"result","is_error":false,"num_turns":1}`. Neither `out/marker-session.log` nor `out/hook.log` was created.
- **Verdict:** matched. No user-level plugin leaks in under an empty HOME.

### 0.2 Fresh empty HOME

- **Command:** the same, plus `--allowedTools Bash,Read --plugin-dir <abs>/cwd/plugins/probe`.
- **Output:** `{"type":"result","is_error":false,...}`, and the SessionStart marker was written, so the plugin loaded under `--plugin-dir`. The CLI created these entries in HOME:

```text
./.claude.json
./.claude/backups/.claude.json.backup.<ts>
./.claude/plugins/data/probe-inline
./.claude/plugins/store/cc-plugin-agents-md_builtin-<hash>.json
./.claude/projects/<cwd-slug>/<session>.jsonl
./.claude/projects/<cwd-slug>/memory
./.claude/session-env/<session>
./.claude/sessions
./.claude/shell-snapshots        (only once the Bash tool runs, seen in 0.4)
```

- **`~/.claude.json` keys (no values recorded):** `firstStartTime`, `firstStartVersion`,
  `hasResetAutoModeOptInForDefaultOffer`, `machineID`, `migrationVersion`, `opusProMigrationComplete`,
  `pluginUsage`, `seenNotifications`, `sonnet1m45MigrationComplete`, `userID`.
- **Verdict:** matched.

### 0.3 Path 3: plugin hook editable mid-run

- **Command:** `--max-turns 6 --allowedTools Bash,Read,Edit --plugin-dir <abs>`. `hooks/hooks.json` registers `PreToolUse` matcher `Bash` → `bash "${CLAUDE_PLUGIN_ROOT}/hooks/pre-bash.sh"`, which appends to `out/hook.log`.
- **Scripted calls:** Read the hook → Edit it → Bash `sed -i … <hook path>` → Bash `python3 -c "…" plugins/probe/hooks/pre-b* <log>` (the path hidden behind a glob) → Bash `echo two`.
- **Raw `hook.log`:**

```text
hook-ran gh_token=set cmd=sed -i "s|^# EDIT-ANCHOR$|echo EDITED-VIA-BASH >> …/hook.log|" …/pre-bash.sh
hook-ran gh_token=set cmd=python3 -c "import pathlib,sys; … 'echo EDITED-VIA-INDIRECT >> '+sys.argv[2]))" …
hook-ran gh_token=set cmd=echo two
EDITED-VIA-INDIRECT
```

- **Tool results:** the Edit and the `sed` call were both refused by the CLI with `Claude requested permissions to edit …/pre-bash.sh which is a sensitive file.` and appear in `permission_denials`. The python call succeeded.
- **Verdict:** matched. The plugin `PreToolUse(Bash)` hook runs in `--print` under `--plugin-dir`, and it sees `GH_TOKEN` as `set`. An edited hook body takes effect on the very next tool call. The CLI's sensitive-file check only catches writes that name the path. A Bash write that hides the path gets through.

### 0.3c Control: read-only plugin dir

- **Command:** the same as 0.3, after `chmod -R a-w <plugin>`.
- **Output:** the hook ran on all three Bash calls. Edit and sed were denied as sensitive files. Python failed with `Exit code 1 … PermissionError`. No `EDITED*` line appeared and the file still contains `# EDIT-ANCHOR`.
- **Verdict:** matched. A non-writable plugin tree closes every write route that was tried.

### 0.4 Path 4: `$HOME/.bashrc` sourcing

- **Commands:** spawn A, `--max-turns 6 --allowedTools Bash,Write`, with `SHELL=/bin/bash` and an empty HOME. Spawn B is `--max-turns 3 --allowedTools Bash` and reuses the same HOME.
- **Scripted calls (A):** `echo "[$PROBE_RC]" >> rc.log` → Write `$HOME/.bashrc` → Bash literal `$HOME/.bashrc` write → Bash indirect write (`n=.bash; n="${n}rc"; printf … > "$HOME/$n"`) → `echo "[$PROBE_RC]"`. B runs `echo "[$PROBE_RC]"` once.
- **Raw `rc.log`:** `[]`, `write-indirect-bash`, `[sourced]` (A, later call), `[sourced]` (B).
- **`permission_denials` (A):** `Write` and the literal-path `Bash`, both as sensitive files.
- **Verdict:** **in-run** re-source (later Bash calls in the same run source a rc file written mid-run), and also cross-run. Under R6, cross-run is closed by a fresh HOME per spawn. The in-run result is recorded and pinned to 2.1.321. In-run only becomes reachable once the CLI's own Write and literal-path checks are bypassed with an indirect Bash write.

### 0.5 `${CLAUDE_PLUGIN_ROOT}` substitution

- **Command:** `--max-turns 4 --allowedTools Bash,Skill --plugin-dir <abs> -- /probe:probe-root`. The skill body contains `bash "${CLAUDE_PLUGIN_ROOT}/scripts/x.sh"`.
- **Output:** the expanded skill text in the request body reads `Base directory for this skill: <abs>/plugins/probe/skills/probe-root` and `bash "<abs>/plugins/probe/scripts/x.sh"`. The mock copies the command from context the way a model would. The hook then logged the emitted command, exactly:

```text
bash "/tmp/claude-1000/-data-git-repositories-jikig-ai-soleur/a0a41931-d65b-418f-8b16-121d13c80855/scratchpad/phase0/arm-0.5/cwd/plugins/probe/scripts/x.sh"
```

- **Verdict:** matched, absolute branch. The CLI substitutes the variable before the model sees the text, so the absolute allowlist line matches the fix-issue SKILL's call.

### 0.6 ux-audit MCP under an empty HOME

- **Label:** `unverified-in-image`. No `web-platform` image exists locally (`docker image ls` lists only postgres and ubuntu), and pulling from GHCR would need registry credentials, so this ran on the host.
- **Command:** `env -i HOME=<empty> … apps/web-platform/node_modules/.bin/playwright-mcp --help`, followed by `chromium.launch()` through the MCP's own `playwright-core` (`1.61.0-alpha-1778188671000`).
- **Output:** `--help` exit 0, `Usage: Playwright MCP [options]`. Launch attempts:
  - default: `Executable doesn't exist at <HOME>/.cache/ms-playwright/chromium_headless_shell-1224/…`
  - `{channel:"chrome"}`, the MCP default: `Chromium distribution 'chrome' is not found at /opt/google/chrome/chrome`
- **Verdict:** matched, browser-missing branch. Under an empty HOME the browser is resolved from `$HOME/.cache/ms-playwright`. The Dockerfile's root-run `npx playwright install` writes to root's cache, so uid 1001 with a fresh HOME very likely cannot launch it. That needs confirming in the image. It is pre-existing; file a follow-up.

### 0.7a git and gh under an empty HOME

- **Commands:** `git init && git add f && git commit -m probe && git log -1 --format="%an <%ae>"` with the pin env, then `GH_TOKEN=dummy-not-a-token gh api /rate_limit`.
- **Output:** `github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com>`, `git-exit=0`. gh printed `{"message":"Bad credentials",…,"status":"401"}` and `gh: Bad credentials (HTTP 401)`, with no config-dir error. gh created `~/.local/state/gh/device-id`.
- **Verdict:** matched.

### 0.7b Cold-cache install (record only)

- **Commands:** in a scratch copy of `apps/web-platform/package.json` and `package-lock.json` (no `bun.lock` exists), with an empty HOME and per-spawn caches under it. `npm_config_registry`, `NPM_CONFIG_REGISTRY` and `BUN_CONFIG_REGISTRY` were set to `http://127.0.0.1:9`. Ran `bun install --frozen-lockfile --ignore-scripts`, then `npm ci --ignore-scripts --no-audit --no-fund`, each under `timeout 180`. `--ignore-scripts` was added as a safety measure.
- **Output:** bun printed `migrated lockfile from package-lock.json` and then hung: exit 124. npm printed nothing: exit 124.
- **Verdict:** matched (record only). A cold cache does not fail fast. It hangs until the outer timeout.

### 0.7c `:ro` errno

- **Command:** `docker run --rm --network none [--user 1001:1001] -v <dir>:/p:ro node:22-slim node -e 'try{require("fs").accessSync("/p",2);console.log("OK")}catch(e){console.log(e.code)}'`. `node:22-slim` was pulled.
- **Output:** `uid1001=EACCES`, `root=EROFS`.
- **Verdict:** matched. The resolver must accept both codes, because uid 1001 hits the permission check before the read-only-mount check.

### 0.7d Clone remote branches

- **Command:** `git clone -q --depth=1 file://<repo git-common-dir> <scratch>/repo`, the `setupEphemeralWorkspace` shape with a local URL, then `git branch -r`.
- **Output:** `origin/HEAD -> origin/main`, `origin/main`.
- **Verdict:** matched. No extra remote branch, so the DWIM `git switch` concern does not apply.

### 0.7e worktree-manager from a read-only copy

- **Command:** `cp -a plugins/soleur` into scratch, `chmod -R a-w`, then in a depth-1 scratch clone run `SOLEUR_WORKTREE_SKIP_INSTALL=1 bash <ro>/skills/git-worktree/scripts/worktree-manager.sh --yes create probe-1`. The pin env and an empty HOME were set.
- **Output:**

```text
SOLEUR_WORKTREE_LEASE_LIB_OK path=<ro>/plugins/soleur/skills/git-worktree/scripts/../../../scripts/lib/session-state.sh
Creating worktree from origin/main...
HEAD is now at 338de186 …
SOLEUR_GIT_LOCK_IDENTITY_WEDGED source=ensure_worktree_identity reason=bot-global-refused file=config
Cannot create worktree — git identity could not be set (see SOLEUR_GIT_LOCK_IDENTITY_WEDGED above).
```

- **Result:** the script exited 1. `git worktree list` shows `<clone>/.worktrees/probe-1 [probe-1]`. The read-only copy's file list did not change.
- **Verdict:** **MISMATCH.** Libs resolve and the worktree is created in the clone, not under the plugin copy, but `create` fails. Under `CRON_GIT_CONFIG_PIN` the only global identity is bot-shaped and the depth-1 clone has no local identity, so `ensure_worktree_identity` refuses by design (ADR-099). Any cron that calls `worktree-manager.sh create` under the pin hits this, and the fix-issue fallback `git worktree add` path is what would run. This needs a decision in the PR.

### 0.7g Nested CLAUDE.md import

- **Setup:** a git repo as the spawn cwd. `CLAUDE.md` holds `ROOT-CLAUDE-MD-LOADED` and `@.git/probe-canary-root.txt`. `sub/CLAUDE.md` holds `NESTED-CLAUDE-MD-LOADED` and `@../.git/probe-canary-nested.txt`. The canaries sit under `.git/`.
- **Command:** `--max-turns 3 --allowedTools Read --plugin-dir <abs>`. The scripted call is a single Read of `sub/file.txt`.
- **Output:** the first request (system and messages) carries `Contents of <cwd>/CLAUDE.md`, then `Contents of <cwd>/.git/probe-canary-root.txt` with `CANARY-ROOT-7G-a1b2`. The request after the Read carries `Contents of <cwd>/sub/CLAUDE.md` with `NESTED-CLAUDE-MD-LOADED`, then `Contents of <cwd>/.git/probe-canary-nested.txt` with `CANARY-NESTED-7G-c3d4`.
- **Verdict:** matched, **canary REACHES context** branch. `@`-imports of `.git/` files are expanded into Anthropic-bound context, both at startup (cwd `CLAUDE.md`) and lazily when a nested `CLAUDE.md` loads after a Read in its directory. Per the plan, the next step is a CLI-native way to exclude nested memory files if 2.1.321 has one, otherwise a write-deny for `(^|/)(CLAUDE(\.local)?|AGENTS)\.md$` inside the confined roots.

### 0.7h Nested CLAUDE.md import under the shipped `claudeMdExcludes` (added during work)

- **Why:** 0.7g took the "reaches context" branch, and CLI 2.1.321 has a native exclusion: `claudeMdExcludes`, picomatch over absolute paths, applied to each memory file and to every file in its import chain (read from the binary's settings schema and loader). The arm checks that the list the substrate ships (`cronClaudeMdExcludes()` in `_cron-claude-eval-substrate.ts`) closes the route.
- **Setup:** as 0.7g, plus `@/proc/self/environ` in `sub/CLAUDE.md` and `PROBE_ENV_CANARY=CANARY-ENV-7H-e5f6` in the child env. Run twice: `none` (no settings) and `excl` (`.claude/settings.json` carrying the list for the arm's cwd).
- **Command:** `PROBE_SCRATCH=<scratch> bash probes/cli-isolation-probe.sh --arm 0.7h --api mock`
- **Output:**
  - `with=none root-md=yes root-canary=yes nested-md=yes nested-canary=yes env-canary=no`
  - `with=excl root-md=yes root-canary=no nested-md=no nested-canary=no env-canary=no`
- **Verdict:** matched. The exclusion holds, so the CLI-native branch of CTO S3 applies and no `CLAUDE.md`/`AGENTS.md` write-deny is added (the 2026-11-16 ruling stands). The runtime self-test refuses a spawn whose `settings.json` lacks the list, and `settings.json` is write-protected. The `/proc` import did not reach context in either run, but it stays excluded anyway.

## Dispositions of the two non-green arms

- **0.6 (browser missing):** this predates #12824. The image installs Chromium as root into `/root/.cache/ms-playwright`, which the uid-1001 cron never had as HOME, before or after this PR. Filed as #12860 (F5).
- **0.7e (worktree-manager refuses under the pin):** this predates #12824. `ensure_worktree_identity` refuses the bot-only global identity that `CRON_GIT_CONFIG_PIN` (#12757) supplies. The fix-issue SKILL already falls back to `git worktree add .worktrees/bot-fix-… -b bot-fix/… origin/main` on a non-zero exit, and that form is allowlisted for bug-fixer. Disposition: degrade through the SKILL fallback, no change here.

