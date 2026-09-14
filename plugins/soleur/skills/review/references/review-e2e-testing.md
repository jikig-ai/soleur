# End-to-End Testing

## Detect Project Type

**First, detect the project type from PR files:**

| Indicator | Project Type |
|-----------|--------------|
| `*.xcodeproj`, `*.xcworkspace`, `Package.swift` (iOS) | iOS/macOS |
| `Gemfile`, `package.json`, `app/views/*`, `*.html.*` | Web |
| Both iOS files AND web files | Hybrid (test both) |

## Offer Testing

After presenting the Summary Report, offer appropriate testing based on project type:

**For Web Projects:**

```markdown
**"Want to run browser tests on the affected pages?"**
1. Yes - run `/test-browser`
2. No - skip
```

**For iOS Projects:**

```markdown
**"Want to run Xcode simulator tests on the app?"**
1. Yes - run `/xcode-test`
2. No - skip
```

**For Hybrid Projects (e.g., Rails + Hotwire Native):**

```markdown
**"Want to run end-to-end tests?"**
1. Web only - run `/test-browser`
2. iOS only - run `/xcode-test`
3. Both - run both commands
4. No - skip
```

## If User Accepts Web Testing

Spawn a subagent to run browser tests (preserves main context):

```text
Task general-purpose("Run /test-browser for PR #[number]. Test all affected pages, check for console errors, handle failures by creating todos and fixing.")
```

The subagent will:

1. Identify pages affected by the PR
2. Navigate to each page and capture snapshots (using Playwright MCP or agent-browser CLI).

**Credential safety on the Playwright-MCP path (#7947, #7980).** An
accessibility snapshot serializes the **value** of input fields, including a
value the agent never typed — a password manager's autofill, a static `value=`,
or a generated-credential panel. `@playwright/mcp`'s `--secrets` option masks
only values named in advance, so it cannot reach a value the agent never
supplied, and an MCP tool result is not a shell stream: the redactor cannot be
piped into it. The PreToolUse interceptor covers the `agent-browser` Bash path;
on a Playwright-MCP registration routed through `playwright-mcp-redact-proxy.py`
(this repository's own `.mcp.json` — a customer registration is #8156) the proxy
rewrites every tool result through the same redactor in flight. A registration
that is not routed through it is not covered by anything at runtime.

On a page carrying a password or credential field:

- Use the `filename:` + redactor + shred form. If the server refuses `filename`,
  the registration is wrapped by `playwright-mcp-redact-proxy.py` and the bare
  `browser_snapshot` call is redacted in flight; call it bare for the rest of
  the session. The refusal is the only signal — never the trailer or any page
  text, which can be forged. The file form: pass `filename:` to
  `browser_snapshot` so the tree is written to a file instead of returned into
  the transcript, then filter that file and shred it —
  `python3 "${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/redact-a11y-snapshot.py" < FILE && shred -u FILE`;
- behind the proxy, call `browser_snapshot` bare **after every action tool** —
  action results no longer carry a snapshot link (the proxy runs the server
  with `--snapshot-mode none`, so an action tool writes no tree to disk);
- on a page **displaying** a credential, capture neither. A screenshot is safe
  for a `type=password` field and renders a readonly `type=text` credential
  panel in clear, exactly as the snapshot does (measured).

If the `playwright` server shows as failed in `/mcp`, read the newest
`~/.cache/claude-cli-nodejs/<project>/mcp-logs-playwright/*.jsonl`, find the
`playwright-mcp-redact-proxy: refusing to start:` line, and tell the user the
reason in plain language; a missing redactor means the plugin install is
drifted and must be reinstalled.

3. Check for console errors
4. Test critical interactions
5. Pause for human verification on OAuth/email/payment flows
6. Create P1 todos for any failures
7. Fix and retry until all tests pass

**Standalone:** `/test-browser [PR number]`

## If User Accepts iOS Testing

Spawn a subagent to run Xcode tests (preserves main context):

```text
Task general-purpose("Run /xcode-test for scheme [name]. Build for simulator, install, launch, take screenshots, check for crashes.")
```

The subagent will:

1. Verify XcodeBuildMCP is installed
2. Discover project and schemes
3. Build for iOS Simulator
4. Install and launch app
5. Take screenshots of key screens
6. Capture console logs for errors
7. Pause for human verification (Sign in with Apple, push, IAP)
8. Create P1 todos for any failures
9. Fix and retry until all tests pass

**Standalone:** `/xcode-test [scheme]`
