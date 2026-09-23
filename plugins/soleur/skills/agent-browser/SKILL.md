---
name: agent-browser
description: "This skill should be used when automating browser interactions via Vercel's agent-browser CLI. It handles web page navigation, form filling, screenshots, and data scraping using ref-based element selection."
---

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

# agent-browser: CLI Browser Automation

Vercel's headless browser automation CLI designed for AI agents. Uses ref-based selection (@e1, @e2) from accessibility snapshots.

## Setup Check

```bash
# Check installation
command -v agent-browser >/dev/null 2>&1 && echo "Installed" || echo "NOT INSTALLED - run: npm install --prefix ~/.local -g agent-browser@0.22.3 && agent-browser install"
```

### Install if needed

```bash
npm install --prefix ~/.local -g agent-browser@0.22.3
agent-browser install  # Downloads Chrome for Testing (~300MB)
# On Linux if system deps missing:
# agent-browser install --with-deps
```

### Required launch flag on Linux: `--no-sandbox`

On Ubuntu 23.10+, containers, and VMs, the host's AppArmor policy restricts
unprivileged user namespaces, so Chrome for Testing cannot initialize its zygote
sandbox and the browser fails to launch. Export the no-sandbox flag once per
session **before the first `agent-browser` command** — the daemon reads it at
launch and every later command in the session inherits it:

```bash
export AGENT_BROWSER_ARGS="--no-sandbox"
```

Inline alternative (first `open` only): `agent-browser open <url> --args "--no-sandbox"`.
This confines `--no-sandbox` to agent-browser's own ephemeral automation Chrome —
the same posture Playwright already runs here; it does not touch your real browser.

### Troubleshooting: Chrome fails to launch / `open` hangs (no usable sandbox)

Symptom on pinned 0.22.3: `agent-browser open <url>` **hangs indefinitely** with
zero stdout/stderr (even `--debug` prints nothing). On newer versions it fails
fast with `No usable sandbox! ... unprivileged user namespaces ... AppArmor` and a
`--args "--no-sandbox"` hint. Both are the same cause.

1. Set the launch flag: `export AGENT_BROWSER_ARGS="--no-sandbox"` (see above).
2. If it still fails, a stale/wedged daemon may be holding the socket. Clear it:
   `pkill -f agent-browser-linux-x64; rm -rf /tmp/agent-browser/* "/run/user/$(id -u)/agent-browser/"*`
   then retry. (Never kill `playwright-mcp` processes — those are a separate stack.)
   The commonest cause is a daemon whose worktree was REAPED: resolve each match's
   `/proc/<pid>/cwd` and expect one ending `(deleted)`, often weeks old and inherited
   by every later session on the machine. Such a daemon does not answer and **survives
   SIGTERM** — it needs `kill -9`. Nothing in the CLI's error names any of this; the
   only symptom is `Resource temporarily unavailable (os error 11)` (#7947).
3. Verify: `AGENT_BROWSER_ARGS="--no-sandbox" timeout 45 agent-browser open https://example.com --headless` → exit 0 + a `✓` line.

### Troubleshooting: Playwright MCP backend closed between calls

This is the **other** browser-automation symptom #6605 reported (the "MCP tools
de-register" half) — distinct from the agent-browser CLI hang above, and covering the
Playwright **MCP** stack. If a `mcp__plugin_soleur_playwright__browser_*` call
(or the same call on a host's own `mcp__playwright__*` registration) returns
`browserBackend.callTool: Target page, context or browser has been closed`, the browser
backend dropped while the MCP server itself stayed registered (a lifecycle event, not a
dead tool).

Known root cause on this host: a Wayland/Vulkan GPU crash — already diagnosed and
remediated in `.claude/playwright-mcp.config.json` (forces the X11/XWayland backend
and disables the GPU); see `knowledge-base/project/learnings/workflow-patterns/2026-06-17-playwright-mcp-wayland-vulkan-launch-crash.md`.
If it still recurs, recycle the context and re-navigate (the pattern in
`plugins/soleur/skills/qa/SKILL.md`: `browser_close` — safe even if already closed —
then `browser_navigate`); the backend restarts. Note that snapshot `ref=` handles do
**not** survive the restart; target elements by name/selector
(`button:has-text("Save")`, `input[aria-label="..."]`) across it. A separate
`"these deferred tools are no longer available"` notice means the MCP server
disconnected (reload via `ToolSearch`) — a different failure from the backend-close.

### Troubleshooting: version mismatch

If you see "Version mismatch between agent-browser (expects 1200) and installed Playwright (1208)":

1. Check which binary is running: `which agent-browser && agent-browser --version`
2. If it resolves to `/usr/bin/agent-browser` (version 0.5.0), a stale system install is shadowing the correct version
3. Fix: `sudo npm uninstall -g agent-browser` to remove the system binary
4. Verify: `which agent-browser` should now resolve to `~/.local/bin/agent-browser` (0.22.3)

## Core Workflow

**The snapshot + ref pattern is optimal for LLMs:**

1. **Navigate** to URL
2. **Snapshot** to get interactive elements with refs
3. **Interact** using refs (@e1, @e2, etc.)
4. **Re-snapshot** after navigation or DOM changes

### Preflight: verify the plugin install before any snapshot

The redactor is reached through `${CLAUDE_PLUGIN_ROOT}`. An ambient value pointing at a
directory that is not a Soleur install would resolve to a path that does not exist — or, worse,
to one an attacker chose. Verify plugin IDENTITY and halt if it does not hold (ADR-179 decision 2);
a `test -f` on the script alone is a shape check and was measured bypassable.

```bash
[ -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ] \
  && grep -q '"name"[[:space:]]*:[[:space:]]*"soleur"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" \
  || { echo "SOLEUR_SNAPSHOT_HALT reason=plugin-root-unverified root=[${CLAUDE_PLUGIN_ROOT}]" >&2
       echo "  Cannot locate the snapshot redactor, so no accessibility snapshot may be taken here." >&2
       echo "  Root EMPTY: no Soleur plugin is loaded in this session. Install it and start a NEW session." >&2
       echo "  Root set but wrong: a repo checkout is not an install. Run 'claude plugin update soleur@soleur-marketplace' (or the id 'claude plugin list' prints, if you added the repository directly), then RESTART Claude Code." >&2
       echo "  Nothing has been captured yet, so nothing has leaked." >&2
       exit 2; }
```

```bash
# Step 1: Open URL
agent-browser open https://example.com

# Step 2: Get interactive elements with refs
agent-browser snapshot -i --json 2>&1 | python3 "${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/redact-a11y-snapshot.py"

# Step 3: Interact using refs
agent-browser click @e1
agent-browser fill @e2 "search query"

# Step 4: Re-snapshot after changes
agent-browser snapshot -i 2>&1 | python3 "${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/redact-a11y-snapshot.py"
```

## Key Commands

### Navigation

```bash
agent-browser open <url>       # Navigate to URL
agent-browser back             # Go back
agent-browser forward          # Go forward
agent-browser reload           # Reload page
agent-browser close            # Close browser
```

### Snapshots (Essential for AI)

```bash
agent-browser snapshot 2>&1 | python3 "${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/redact-a11y-snapshot.py"  # Full accessibility tree
agent-browser snapshot -i 2>&1 | python3 "${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/redact-a11y-snapshot.py"  # Interactive elements only (recommended)
agent-browser snapshot -i --json 2>&1 | python3 "${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/redact-a11y-snapshot.py"  # JSON output for parsing
agent-browser snapshot -c 2>&1 | python3 "${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/redact-a11y-snapshot.py"  # Compact (remove empty elements)
agent-browser snapshot -d 3 2>&1 | python3 "${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/redact-a11y-snapshot.py"  # Limit depth
```

### Interactions

```bash
agent-browser click @e1                    # Click element
agent-browser dblclick @e1                 # Double-click
agent-browser fill @e1 "text"              # Clear and fill input
agent-browser type @e1 "text"              # Type without clearing
agent-browser press Enter                  # Press key
agent-browser hover @e1                    # Hover element
agent-browser check @e1                    # Check checkbox
agent-browser uncheck @e1                  # Uncheck checkbox
agent-browser select @e1 "option"          # Select dropdown option
agent-browser scroll down 500              # Scroll (up/down/left/right)
agent-browser scrollintoview @e1           # Scroll element into view
```

### Get Information

```bash
agent-browser get text @e1          # Get element text
agent-browser get html @e1          # Get element HTML
agent-browser get value @e1         # Get input value
agent-browser get attr href @e1     # Get attribute
agent-browser get title             # Get page title
agent-browser get url               # Get current URL
agent-browser get count "button"    # Count matching elements
```

### Screenshots & PDFs

```bash
agent-browser screenshot                      # Viewport screenshot
agent-browser screenshot --full               # Full page
agent-browser screenshot output.png           # Save to file
agent-browser screenshot --full output.png    # Full page to file
agent-browser pdf output.pdf                  # Save as PDF
```

### Wait

```bash
agent-browser wait @e1              # Wait for element
agent-browser wait 2000             # Wait milliseconds
agent-browser wait "text"           # Wait for text to appear
```

## Semantic Locators (Alternative to Refs)

```bash
agent-browser find role button click --name "Submit"
agent-browser find text "Sign up" click
agent-browser find label "Email" fill "user@example.com"
agent-browser find placeholder "Search..." fill "query"
```

## Sessions (Parallel Browsers)

```bash
# Run multiple independent browser sessions
agent-browser --session-name browser1 open https://site1.com
agent-browser --session-name browser2 open https://site2.com

# List saved states
agent-browser state list
```

## Examples

### Credential safety on a login or credential page

An accessibility snapshot serializes the **value** of input fields. A value the
agent never typed — a password manager's autofill, a static `value=`, a JS
assignment, or a freshly-minted credential shown in a panel — is rendered into
the transcript and into any snapshot file written to disk. Nothing about the
call looks credential-adjacent, which is why this is a gate and not advice: the
PreToolUse hook `browser-snapshot-credential-guard.sh` denies an unrouted
snapshot before it runs (#7947).

**Route every snapshot on a credential-bearing page through the redactor**,
[redact-a11y-snapshot.py](./scripts/redact-a11y-snapshot.py):

```bash
agent-browser snapshot -i 2>&1 | python3 "${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/redact-a11y-snapshot.py"
```

Stating the ceiling first, because the rule is otherwise read as "piping makes a
snapshot safe": the redactor is **defense-in-depth on one sink**, not a control
that makes snapshotting a credential page safe. It keys on the node's accessible
name, because neither surface serializes the input's `type` — measured, see the
[Phase 0.1 record](../../../../knowledge-base/project/specs/feat-one-shot-7946-7947-sentry-org-token-and-snapshot-redaction/phase-0-measurement.md).
It therefore cannot see a localised field name, a credential outside a
text-input role, or a value split across segmented inputs.

**A screenshot is safe for a `type=password` field** — the browser renders it as
dots — **and is NOT safe for a generated-credential panel.** Measured: a readonly
`type=text` box named "Token" renders its value in clear in the screenshot
exactly as it does in the snapshot. On a page displaying a credential, capture
neither: read the value with `agent-browser get value <sel>` into a file, use it,
and shred the file.

### Login Flow

`fill @e2` needs a ref, and a ref comes from a snapshot — so the login step
snapshots **through the redactor** rather than not at all.

```bash
agent-browser open https://app.example.com/login
agent-browser snapshot -i 2>&1 | python3 "${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/redact-a11y-snapshot.py"
# Output shows: textbox "Email" [ref=e1], textbox "Password" [ref=e2], button "Sign in" [ref=e3]
agent-browser fill @e1 "user@example.com"
# Pass the secret by env indirection -- never a literal, which lands in the
# transcript as the tool-call argument before any snapshot happens.
agent-browser fill @e2 "$APP_PASSWORD"
agent-browser click @e3
agent-browser wait 2000
# Verify logged in -- still through the redactor: the password manager may have
# refilled the field on the post-login page.
agent-browser snapshot -i 2>&1 | python3 "${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/redact-a11y-snapshot.py"
```

### Search and Extract

```bash
agent-browser open https://news.ycombinator.com
agent-browser snapshot -i --json 2>&1 | python3 "${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/redact-a11y-snapshot.py"
# Parse JSON to find story links
agent-browser get text @e12  # Get headline text
agent-browser click @e12     # Click to open story
```

### Form Filling

```bash
agent-browser open https://forms.example.com
agent-browser snapshot -i 2>&1 | python3 "${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/redact-a11y-snapshot.py"
agent-browser fill @e1 "John Doe"
agent-browser fill @e2 "john@example.com"
agent-browser select @e3 "United States"
agent-browser check @e4  # Agree to terms
agent-browser click @e5  # Submit button
agent-browser screenshot confirmation.png
```

### Debug Mode

```bash
# Run with visible browser window
agent-browser --headed open https://example.com
agent-browser --headed snapshot -i 2>&1 | python3 "${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/redact-a11y-snapshot.py"
agent-browser --headed click @e1
```

## JSON Output

Add `--json` for structured output:

```bash
agent-browser snapshot -i --json 2>&1 | python3 "${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/redact-a11y-snapshot.py"
```

Returns:

```json
{
  "success": true,
  "data": {
    "refs": {
      "e1": {"name": "Submit", "role": "button"},
      "e2": {"name": "Email", "role": "textbox"}
    },
    "snapshot": "- button \"Submit\" [ref=e1]\n- textbox \"Email\" [ref=e2]"
  }
}
```

## vs Playwright MCP

| Feature | agent-browser (CLI) | Playwright MCP |
|---------|---------------------|----------------|
| Interface | Bash commands | MCP tools |
| Selection | Refs (@e1) | Refs (e1) |
| Output | Text/JSON | Tool responses |
| Parallel | Session names | Tabs |
| Browser | Chrome for Testing | Chromium |
| Runtime | Rust native | Node.js |
| Best for | Quick automation | Tool integration |

Use agent-browser when:

- You prefer Bash-based workflows
- You want simpler CLI commands
- You need quick one-off automation

Use Playwright MCP when:

- You need deep MCP tool integration
- You want tool-based responses
- You're building complex automation

### Wrapping the server

**The plugin registers the wrapped server.** `plugins/soleur/.mcp.json`
registers `playwright` with `python3` running
`"${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py"`
in front of `npx @playwright/mcp@0.0.78`, so on Claude Code its tools arrive as
`mcp__plugin_soleur_playwright__*` — already wrapped, no customer
configuration. The registration passes
`--user-data-dir-name soleur-playwright-mcp-profile`, so the wrapped browser
runs on its own profile under `$XDG_CACHE_HOME` (default `~/.cache`), separate
from any `playwright` registration the customer configured themselves. On a
registration routed through the proxy, every `tools/call` result is rewritten
through `redact-a11y-snapshot.py` at the stdio boundary — between the server's
stdout and the client's stdin, before the model reads it — which is what
"redacted in flight" means: a content rewrite, not encryption and not
transport security. A registration not routed through it is not covered by
anything at runtime (#7980). **The registration ships no config and no env
block, so the server runs upstream defaults: headed — a visible Chrome window
opens when a tool drives the browser — on channel `chrome` (real Google
Chrome).** Headed is deliberate: the credential-handoff flows need an
operator-visible window. On a display-less host or where Chrome is absent the
server still connects but browser tools fail to launch — see the playbook at
the end of this section.

**Preconditions.** The plugin server exists only where all of these hold: the
session is Claude Code ≥2.1.139 with the soleur plugin installed; `python3`
and `npx` are on `PATH` and both scripts sit under `${CLAUDE_PLUGIN_ROOT}` (the
proxy refuses to start beside a missing redactor); and the server is not
toggled off in `/mcp`. Devin's local CLI also discovers a plugin-root
`.mcp.json` (its own documentation), so the tools may appear there too —
still wrapped; on Codex discovery is unverified. On any harness that does
not discover it, a disabled toggle, or a failed precondition,
`mcp__plugin_soleur_playwright__*` simply does not
exist — treat it as a missing registration and take the file-form path the
calling skill prescribes (the `filename:` + redactor + shred form on the
registration that does answer, or `agent-browser`), never a bare
`browser_snapshot` on an unwrapped server. **The `/mcp` toggle** can disable
the plugin's `playwright` server without uninstalling the plugin; while it is
off the tools are absent for the whole session and the same fallback applies.

**Wrap your own registration (advanced).** A customer's own `playwright`
registration is not covered by the plugin server — it stays unwrapped unless
the customer routes it through the proxy, with the proxy referenced through the
bare plugin-root anchor per ADR-179:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "python3",
      "args": [
        "${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py",
        "--",
        "npx", "@playwright/mcp@0.0.78",
        "--user-data-dir=<profile-dir>"
      ]
    }
  }
}
```

Claude Code does not expand `${CLAUDE_PLUGIN_ROOT}` inside a project `.mcp.json`
(the variable exists for plugin-provided servers). Replace it with the
`installPath` that `claude plugin list --json` prints for `soleur`; that path
carries the plugin version, so re-check it after every plugin update.
`--user-data-dir=<profile-dir>` may instead be
`--user-data-dir-name <basename>` placed before the `--`: the proxy resolves it
under `$XDG_CACHE_HOME` (default `~/.cache`) and refuses a basename carrying a
separator or `..`. Add `--config=<file>` only when the project has that file:
the proxy refuses to start on a named config that does not exist. An
`.mcp.json` edit loads only on a full Claude Code restart, never on a `/mcp`
reconnect, and only the user can restart; afterwards verify with `ToolSearch
select:mcp__playwright__browser_snapshot` — a description ending with the marker
below means wrapped, no match means the server did not connect (see the end of
this section). This repository wraps the command in a `bash -c` prelude (`pkill`
of a stale proxy, server and browser on the same profile; `env -u
WAYLAND_DISPLAY`; an X11 display) that is Linux-only; the proxy itself is POSIX
(stdlib `selectors` + `subprocess`) and does not run on Windows.

**Fail-closed in three arms, no bypass variable.**

1. **At startup** — the proxy writes `playwright-mcp-redact-proxy: refusing to
   start: <reason>` to stderr and exits 2, spawning no server, when it cannot
   load and self-test the redactor, or when the launch opens a raw sink around
   it: a disk/session sink or foreign browser — `--save-session`,
   `--save-trace`, `--save-video`, `--storage-state`, `--secrets`,
   `--output-dir`, `--init-script`, `--init-page`, `--cdp-endpoint`,
   `--endpoint`, `--extension`, `--executable-path`, `--daemon`,
   `--allow-unrestricted-file-access`, `--grant-permissions`,
   `--ignore-https-errors`, `--no-sandbox`, and each setting's
   `PLAYWRIGHT_MCP_*` env twin (`PLAYWRIGHT_MCP_SANDBOX` for `--no-sandbox`),
   plus env-only `PLAYWRIGHT_MCP_USER_DATA_DIR` and
   `PLAYWRIGHT_MCP_SNAPSHOT_MODE`; a trailing valued flag, which would swallow
   the appended `--snapshot-mode none` as its value; a config file (from
   `--config` or `PLAYWRIGHT_MCP_CONFIG`) that is missing, is not JSON, or sets
   `saveSession`, `saveTrace`, `saveVideo`, `secrets`, `outputDir`,
   `allowUnrestrictedFileAccess`, `extension`, `server.port` / `server.host`, a
   capability other than `vision`, `browser.cdpEndpoint` /
   `browser.remoteEndpoint`, `browser.initPage` / `browser.initScript`,
   `browser.contextOptions.storageState` / `.permissions` /
   `.ignoreHTTPSErrors`, `browser.launchOptions.executablePath` /
   `.chromiumSandbox: false` / a remote-debugging `args` flag, or a
   `browser.userDataDir` conflicting with `--user-data-dir-name`; `--port`,
   `--host`, `PLAYWRIGHT_MCP_PORT` or `PLAYWRIGHT_MCP_HOST`
   (an HTTP transport around the relay); `--caps` or `PLAYWRIGHT_MCP_CAPS` other
   than `vision` (devtools, pdf and storage write raw page state);
   `--output-mode file`; a `DEBUG` value that can enable any `pw:` logger (the
   `debug` package splits on whitespace and commas and treats `*` as a wildcard,
   so `pw:*` counts); `DEBUG_FILE`; or a `--user-data-dir-name` that is not a
   bare basename (a separator or `..`), is combined with an explicit
   `--user-data-dir` in the server argv, or resolves under a relative
   `XDG_CACHE_HOME` / an unset `HOME`. The reason names the setting, never its
   value.

2. **Per call** — it appends `--snapshot-mode none` to the child so no action
   tool writes a tree to disk, and refuses, before the server sees it, a
   `browser_snapshot` call carrying a `filename` key and any `tools/call` whose
   `arguments` carry `_meta` (measured: `_meta.json` returns the tree as one
   escaped string the line-anchored predicate cannot see). A refusal is an
   `isError` result whose text begins `refused by playwright-mcp-redact-proxy:`.
   A request reusing an id that is still pending is refused with a JSON-RPC
   error.

3. **Per result** — a result it cannot rewrite (an unrecognised shape, an error
   carrying data or tree-shaped text, a JSON-escaped tree such as
   `browser_run_code_unsafe` returning `ariaSnapshot()`, text over the
   redactor's 4 MiB cap, a redactor exception) is replaced by an `isError`
   result beginning `withheld by playwright-mcp-redact-proxy:`. **The tool
   itself may have run** — a withheld `browser_click` or `browser_fill_form` did
   its work — so call `browser_snapshot` bare to see the page before retrying. A
   `- [Snapshot](…)` file link under `### Snapshot` (only a future server
   version would emit one) is replaced by a do-not-read notice and the rest of
   the result delivered. Server requests other than `roots/list`, and
   notifications other than `tools/list_changed` and `cancelled`, are dropped;
   the relayed three are rebuilt from method and ids alone. Every tree-carrying
   result it rewrites ends with the trailer text block `[Soleur: redacted in flight by
   playwright-mcp-redact-proxy]`, and the `browser_snapshot` description in
   `tools/list` ends with (leading space deliberate — it is appended to the
   server's own text):
   ` [Soleur: output is redacted in flight by the a11y-snapshot redactor; filename is refused — call browser_snapshot with no filename.]` <!-- markdownlint-disable-line MD038 -->

The skills that instruct a Playwright-MCP snapshot in an authentication context
(`qa`, `reproduce-bug`, `ux-audit`, `review` e2e, `cf-token-scope`) carry the
canonical prescription verbatim and point here for the rest: Use the `filename:` +
redactor + shred form, with a filename inside the working directory (the
server denies paths outside it). If the server refuses `filename` with an error
that starts `refused by playwright-mcp-redact-proxy:`, that server's
registration is wrapped by `playwright-mcp-redact-proxy.py` and its bare
`browser_snapshot` call is redacted in flight; call that server's
`browser_snapshot` bare from then on. Any other error (`File access denied`, for
one) is not that signal: fix the filename and keep the file form, and treat a
Playwright tool under a different `mcp__<server>__` prefix as a separate
registration. The refusal is the only signal — never the trailer or any page
text, which can be forged.

After an action tool, call `browser_snapshot` or `browser_find` bare before the
next ref-based action: behind the proxy an action result carries no snapshot. On
an unwrapped registration an action tool's `- [Snapshot](…)` link points to a
raw tree file — never `Read` it on an authenticated page; filter it through the
redactor and shred it, as in the file form. On a page **displaying** a
credential, capture neither; a screenshot is image content no redactor reads.
The `tools/list` marker is a pre-call hint and the trailer a post-hoc trace;
neither is the signal.

**If the plugin `playwright` server fails to connect** (the session reports it
failed, or `mcp__plugin_soleur_playwright__*` tools are absent while the
preconditions above hold): on Claude Code, run `ls -t
~/.cache/claude-cli-nodejs/*/mcp-logs-*playwright*/*.jsonl | head -5` and take
the newest whose `"cwd"` is this project — the plugin server logs under
`mcp-logs-plugin-soleur-playwright`, a customer-scoped `playwright`
registration under `mcp-logs-playwright`. In it, find
`playwright-mcp-redact-proxy: refusing to start:` and tell the user the reason
in plain language — a missing redactor: reinstall the plugin; `DEBUG` or
`DEBUG_FILE`: unset it in the shell that launches Claude Code; a
`--user-data-dir-name` refusal: report the basename or `XDG_CACHE_HOME` problem
it names; any other named setting: remove it from the launch. If there is no
such line, check whether a stale process holds the plugin profile (`pgrep -f
soleur-playwright-mcp-profile` — a SIGKILLed session can leave a
`SingletonLock`; a dead-pid lock is stolen cleanly on the next launch, so only
a LIVE lock-holder is the contention case), then report the last `Server
stderr:` and `child exited rc=` lines — the failure is in the server or the
launch command, not the redactor. Any fix needs a full Claude Code restart,
which only the user can do.

**If the plugin server connects but the browser never launches** (tools answer
with launch/navigation errors while the registration itself is healthy), the
registration's upstream defaults are the suspect surface: headed, channel
`chrome`. Three measured modes, each remediated by the customer exporting the
named variable in the shell that launches their harness (the plugin entry has
no `env` block, so process env is the only override path — `executable-path`
is refused by the proxy as a foreign-browser sink, so do not suggest it):

- **No display** (headless host, SSH, container): a headed browser cannot
  open. `PLAYWRIGHT_MCP_HEADLESS=1` is the supported opt-out.
- **No real Chrome** (channel `chrome` resolves to Google Chrome, not bundled
  Chromium): install Chrome, or `npx playwright install chromium` plus
  `PLAYWRIGHT_MCP_CHANNEL=chromium`.
- **Wayland/GPU variance**: a headed launch on a Wayland host was measured
  working with system Chromium (no Vulkan/ozone/crash lines), but the
  2026-06 dogfood crash class existed — on a crash-looping host,
  `PLAYWRIGHT_MCP_HEADLESS=1` sidesteps the compositor path entirely, or the
  customer keeps their own registration with an env-forcing prelude as this
  repository's `.mcp.json` does.
