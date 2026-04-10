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

Use the `delegate` tool to spawn a subagent for browser tests (preserves main context):

```
spawn: ["browser-test"]
delegate:
  browser-test: "Run browser tests for PR #[number]. Test all affected pages, check for console errors, handle failures by creating task_tracker items and fixing."
```

The subagent will:

1. Identify pages affected by the PR
2. Navigate to each page and capture snapshots (using Playwright MCP or agent-browser CLI)
3. Check for console errors
4. Test critical interactions
5. Pause for human verification on OAuth/email/payment flows
6. Create P1 todos for any failures
7. Fix and retry until all tests pass

**Standalone:** `/test-browser [PR number]`

## If User Accepts iOS Testing

Use the `delegate` tool to spawn a subagent for Xcode tests (preserves main context):

```
spawn: ["xcode-test"]
delegate:
  xcode-test: "Run Xcode tests for scheme [name]. Build for simulator, install, launch, take screenshots, check for crashes."
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
