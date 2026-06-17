# Learning: Playwright MCP headed-Chrome crashes every ~2-3 calls on a Wayland session (Vulkan/ozone incompatibility)

## Problem
During the #5480 Resend key mint, every Playwright MCP browser flow died after
~2-3 tool calls with `Error: browserBackend.callTool: Target page, context or
browser has been closed`. Multi-step UI (create-key dialog, delete-confirm,
token capture) could never complete; the instability — not any human gate — was
what blocked the work. This will frustrate any Soleur user whose tasks need the
browser.

## Root cause
The host is a **Wayland** session (`XDG_SESSION_TYPE=wayland`,
`WAYLAND_DISPLAY=wayland-0`; XWayland present at `DISPLAY=:0`). The Playwright
MCP config (`.claude/playwright-mcp.config.json`) deliberately pins
`"headless": false` (headed mode — needed for the credential-handoff workflow,
to dodge the `@playwright/mcp` 0.0.75 silent-headless regression). Headed
Chrome 149 on Wayland auto-selects the **Wayland ozone backend**, which is
incompatible with the Vulkan/SwiftShader GPU path. The browser-launch log shows
it directly:

```
ERROR:ui/ozone/platform/wayland/gpu/wayland_surface_factory.cc:249]
  '--ozone-platform=wayland' is not compatible with Vulkan.
  Consider switching to '--ozone-platform=x11' or disabling Vulkan
...
<process did exit: exitCode=0, signal=null>
```

The GPU process crashes → the renderer/page context drops → every subsequent
tool call sees a closed context. `/mcp` reconnect relaunches the same headed
Wayland Chrome, so it recurs.

## Fix
Add Chrome launch args to `.claude/playwright-mcp.config.json`
`browser.launchOptions.args` — per Chrome's own remediation hint — to force the
X11/XWayland backend (XWayland is present) and software rendering, while keeping
headed mode:

```json
"args": ["--ozone-platform=x11", "--disable-gpu"]
```

- `--ozone-platform=x11` routes Chrome through XWayland (`DISPLAY=:0`) instead of
  the native Wayland surface factory that conflicts with Vulkan.
- `--disable-gpu` forces software GL, sidestepping the Vulkan path entirely
  (belt-and-suspenders; safe for automation).

Both are no-ops on a native X11 host and in headless mode, so the fix is safe
across environments. Headed mode (the credential-handoff requirement) is
preserved.

**Applying it:** edit the config, then reconnect the Playwright MCP server
(`/mcp`) so the new launch args take effect. Verify with a navigate + a few
sequential `browser_snapshot`/`browser_evaluate` calls that the context survives.

## Key Insight
"Browser keeps closing" on a Linux desktop session is usually NOT random MCP
flakiness — read the **browser-launch log** (it's printed on a failed
`browser_navigate`). A `wayland_surface_factory ... not compatible with Vulkan`
line + immediate `process did exit` is the ozone/GPU class, fixed at the launch
flags, not by retrying. Headed automation on Wayland should pin
`--ozone-platform=x11` (or run headless where the workflow allows).

## Tags
category: workflow-patterns
module: .claude/playwright-mcp.config.json
