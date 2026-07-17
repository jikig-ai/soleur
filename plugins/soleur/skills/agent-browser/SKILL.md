---
name: agent-browser
description: "This skill should be used when automating browser interactions via Vercel's agent-browser CLI. It handles web page navigation, form filling, screenshots, and data scraping using ref-based element selection."
---

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
3. Verify: `AGENT_BROWSER_ARGS="--no-sandbox" timeout 45 agent-browser open https://example.com --headless` → exit 0 + a `✓` line.

### Troubleshooting: Playwright MCP backend closed between calls

This is the **other** browser-automation symptom #6605 reported (the "MCP tools
de-register" half) — distinct from the agent-browser CLI hang above, and covering the
Playwright **MCP** stack. If a `mcp__playwright__browser_*` call returns
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

```bash
# Step 1: Open URL
agent-browser open https://example.com

# Step 2: Get interactive elements with refs
agent-browser snapshot -i --json

# Step 3: Interact using refs
agent-browser click @e1
agent-browser fill @e2 "search query"

# Step 4: Re-snapshot after changes
agent-browser snapshot -i
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
agent-browser snapshot              # Full accessibility tree
agent-browser snapshot -i           # Interactive elements only (recommended)
agent-browser snapshot -i --json    # JSON output for parsing
agent-browser snapshot -c           # Compact (remove empty elements)
agent-browser snapshot -d 3         # Limit depth
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

### Login Flow

```bash
agent-browser open https://app.example.com/login
agent-browser snapshot -i
# Output shows: textbox "Email" [ref=e1], textbox "Password" [ref=e2], button "Sign in" [ref=e3]
agent-browser fill @e1 "user@example.com"
agent-browser fill @e2 "password123"
agent-browser click @e3
agent-browser wait 2000
agent-browser snapshot -i  # Verify logged in
```

### Search and Extract

```bash
agent-browser open https://news.ycombinator.com
agent-browser snapshot -i --json
# Parse JSON to find story links
agent-browser get text @e12  # Get headline text
agent-browser click @e12     # Click to open story
```

### Form Filling

```bash
agent-browser open https://forms.example.com
agent-browser snapshot -i
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
agent-browser --headed snapshot -i
agent-browser --headed click @e1
```

## JSON Output

Add `--json` for structured output:

```bash
agent-browser snapshot -i --json
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
