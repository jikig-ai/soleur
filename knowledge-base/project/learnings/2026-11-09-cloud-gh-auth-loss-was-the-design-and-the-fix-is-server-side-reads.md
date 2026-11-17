# Learning: Cloud `gh` "no credentials" was the credential quarantine working, not a regression

## Problem

A Soleur Cloud user (Agent web access on) saw `gh` fail with "run gh auth login / populate GH_TOKEN" and read it as a regression of GitHub App token injection (#12469).

## Investigation

- Literal greps of the symptom strings, Supabase `workspaces.web_egress`, Sentry and Better Stack showed no injection fault. With `web_egress` on, ADR-278 Decision 5 deliberately strips `GH_TOKEN`, `GIT_ASKPASS`, `GIT_INSTALLATION_TOKEN` and friends from the bwrap sandbox, keyed on the live egress forwarder. A behavioural `printenv` probe (T9b) shows the OFF arm sees a decoy and the ON arm does not. The "regression" was the design applied to a user who had enabled the toggle.
- Re-adding credentials to the sandbox would reopen the exfiltration path the toggle exists to close. The fix is to restore READS outside the sandbox.

## Solution

Six read-only tools in the `soleur_platform` MCP server (list PRs, read PR, read issue, issue comments, PR comments, CI status), run in the dispatch process with the GitHub App installation token, which never enters the sandbox. Registered only for an entitled `command_center` session on a verified PUBLIC repo; every result framed as untrusted, redacted per field, capped, redirects refused, repo identity revalidated per call. Two review rounds plus a mutation battery hardened it.

## Key Insights

- **Read the design record before calling a "no credentials" report a regression.** A guard working as specified looks identical to a break from the user's seat.
- **A fault text is a product surface.** Mapping a token-mint failure by its own status (401/403/404 reconnect, 429 rate limit, anything else a fixed read-failed text) matters: the first draft told owners to reconnect a working install during a GitHub outage.
- **A shared sink with no identity cannot be debounced by its caller.** The scrubbed 403 mirror sat below a debounced `onFault`, so a looping agent still sent one Sentry event per call until the lower mirror was removed.
- **`null` from a lookup that conflates "error" and "absent" must be named as a residual**, and the identity comparison must run before it (a disconnect is a change, not a blip).
- **Equivalent mutants exist at the observable surface.** Mutation M23 (persona in a catch) survived because the seam that would expose it is gated elsewhere; record it rather than inventing a test that cannot tell the arms apart.

## Session Errors

- **Multi-site `replace` edited the first of two identical strings** — Recovery: a builder test failed on the class name; restored the legacy site and edited the intended one — **Prevention:** in scripted edits assert `count == 1` (not `>= 1`) before replacing, or anchor on surrounding lines.
- **A prompt fix named `github_push_branch` on a path whose census forbids naming a tool that is not registered** — Recovery: removed the clause, the real-factory dark-path rows stayed green — **Prevention:** run the dark-path census suite after any change to text shown when a tool is absent.
- **`cd ..` inside an `&&` chain aborted the test and tsc steps that followed** — Recovery: re-ran from the worktree root — **Prevention:** use absolute `cd` targets in chains.
- **Filing a follow-up issue was blocked twice** (body file created in the same command; no `Mandated-By` line) — Recovery: wrote the body first, added the mandate line — **Prevention:** write the body file in a separate step and add `Mandated-By:` for rule-mandated deferrals.
- **Implementation was committed before its tests, and files were edited while a review panel ran** — Recovery: a 38-row mutation battery over the new guards, no edits while seats were live — **Prevention:** write the failing test first (`cq-write-failing-tests-before`); never touch the tree while a panel is running.
- **Affected-tests gate ended `budget-deferred` (rc=6) and the nav-states gate was INFRA-BLOCKED** — Recovery: ran the selected suites (1927/1927) and tsc; CI is the authoritative gate — **Prevention:** none beyond recording it.

## Tags

category: integration-issues
module: web-platform/cc-dispatcher, github-tools, agent-sandbox
