---
date: 2026-07-17
category: bug-fixes
tags: [agent-browser, playwright, chrome, sandbox, apparmor, tooling, triage]
issue: 6605
pr: TBD
---

# agent-browser's 150s "hang" was a missing `--no-sandbox`, not a dead tool

## Symptom (as reported)

Issue #6605: "both browser-automation paths dead — Playwright MCP tools de-register
AND `agent-browser open` hangs / exits 1 with empty stdout+stderr." Classified
`attempted-blocked-on-tool` and cited as blocking an authorized Sentry billing write.

## What was actually true (measured, not derived)

Only **one** path was broken, and not for the reason assumed.

- **Playwright MCP was not dead.** `ToolSearch` reloaded the `browser_*` tools on
  request and `browser_navigate` returned live pages. The "de-register" symptom is
  the known Wayland/Vulkan GPU crash on this host — already diagnosed and remediated
  in `.claude/playwright-mcp.config.json` (X11 backend + GPU disable) and
  `2026-06-17-playwright-mcp-wayland-vulkan-launch-crash.md`. The blocked billing
  write was completed through Playwright during verification.

- **`agent-browser` was broken by a missing `--no-sandbox` flag.** Root cause:
  Chrome for Testing cannot initialize its zygote sandbox because the host's AppArmor
  policy restricts unprivileged user namespaces (Ubuntu 23.10+, containers, VMs).
  agent-browser (a Rust CLI + Rust daemon) auto-launches Chrome without `--no-sandbox`.

### The decision matrix — every cell executed on-host, clean-slate

| Version | Launch flag | Result |
|---|---|---|
| 0.22.3 (pinned) | default | hang > 45s, 0 bytes stdout AND stderr (even `--debug`) |
| 0.22.3 (pinned) | `--no-sandbox` (via `--args` or `AGENT_BROWSER_ARGS`) | EXIT=0, navigation works |
| 0.32.1 (latest) | default | EXIT=1 in ~1s, precise diagnostic: `No usable sandbox ... AppArmor ... unprivileged user namespaces`, `Hint: try --args "--no-sandbox"` |
| 0.32.1 (latest) | `--no-sandbox` | EXIT=0, navigation + ref-based snapshot both work |

The fix is the **flag** (works on the pinned 0.22.3, so no version bump needed —
avoiding the recurring agent-browser↔Playwright-MCP Chromium-cache mismatch). The
version bump is an orthogonal observability win: 0.32.1 fails loud where 0.22.3 hangs
silent (the daemon routes its stdout to `/dev/null`, and the launch failure happens
during daemon/browser bootstrap, before the CLI's 30s IPC read timeout applies).

## The durable lesson

**A tool that failed once in one session is not a dead tool.** #6605 generalized a
single transient Playwright de-registration into "both paths dead" and reclassified a
robot-automatable task as `attempted-blocked-on-tool` — a classification that requires
*both* paths down, when only one was. Before declaring an outage or handing a robot's
job to the operator:

1. **Probe, don't assume** (`hr-verify-repo-capability-claim-before-assert`). Re-run
   the failing tool. `ToolSearch` reload + one `browser_navigate` disproved the
   Playwright half in seconds.
2. **Measure the vendored tool's behavior, don't derive it.** "0.22.3 hangs → bump to
   0.32.1 fixes it" was a plausible-but-wrong hypothesis; the version bump alone does
   NOT make Chrome launch. Only the on-host matrix revealed the flag was the fix and
   the version was observability.
3. **Read a fast, precise diagnostic before writing a slow, silent workaround.** The
   upstream 0.32.1 message named the exact cause and fix; 0.22.3's silence is the
   actual defect (`cq-silent-fallback-must-mirror-to-sentry`).
4. **Check whether the repo already diagnosed it.** The MCP backend-close was a
   solved problem sitting in `.claude/playwright-mcp.config.json` + a learning file.

## Fix shipped

- `plugins/soleur/skills/agent-browser/SKILL.md`: `AGENT_BROWSER_ARGS="--no-sandbox"`
  setup + Troubleshooting entries for the sandbox hang and the (already-known) MCP
  backend-close.
- `plugins/soleur/skills/{test-browser,feature-video}/SKILL.md`: the same setup line.
- `plugins/soleur/skills/feature-video/scripts/check_deps.sh`: a bounded launch smoke
  test that turns the 150s silent hang into a seconds-long, actionable WARN naming
  `--no-sandbox`.
