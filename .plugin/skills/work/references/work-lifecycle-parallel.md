# Tier 0: Lifecycle Parallelism Protocol

Parallel code and test agents working from a shared interface contract. Two agents execute concurrently: one implements source code, the other writes acceptance tests from the contract (ATDD). The coordinator integrates output, commits, and runs test-fix-loop.

## Step 01: Offer (interactive) / Auto-select (pipeline)

**Interactive mode:**

"This plan has independent code and test workstreams that can run in parallel.
Tier 0 spawns two agents -- one for implementation, one for acceptance tests --
from a shared interface contract. Run as Tier 0?"

- If declined: fall through to Tier A
- If accepted: continue to Step 02

**Pipeline mode:** Auto-select Tier 0 without prompting. Continue to Step 02.

## Step 02: Generate interface contract

Read the plan file and generate a markdown contract at `knowledge-base/project/specs/feat-<name>/interface-contract.md` with exactly two sections:

```markdown
## File Scopes

| Agent | Files |
|-------|-------|
| Agent 1 (Code) | (list every source file, config file, package manifest this agent may create or modify) |
| Agent 2 (Tests) | (list every test file this agent may create or modify) |

## Public Interfaces

(function/class signatures with parameter types, return types, and error types)
```

**Contract generation rules:**

- Derive file scopes from the plan's task descriptions and file references
- Derive signatures from acceptance criteria and the plan's technical design
- Every file appears in exactly one agent's scope -- no overlap
- Version triad files (`plugin.json`, `CHANGELOG.md`, root `README.md`) belong to neither agent -- Ship handles those
- The plan provides all other context (motivation, data flow, examples). The contract adds only what agents need to avoid collision.

Commit the contract before spawning agents:

```bash
git add knowledge-base/project/specs/feat-<name>/interface-contract.md
git commit -m "docs: generate interface contract for feat-<name>"
```

## Step 03: Spawn 2 parallel agents

Use the `delegate` tool to spawn both agents so they execute concurrently:

```
spawn: ["code-agent", "test-agent"]
delegate:
  code-agent: "You are Agent 1 (Code) in a parallel lifecycle.

    BRANCH: [current branch name]
    WORKING DIRECTORY: [absolute worktree path]

    INTERFACE CONTRACT:
    [Full contract document from Step 02]

    YOUR FILES:
    [Exact file list from the Agent 1 (Code) row in File Scopes]

    INSTRUCTIONS:
    - Implement the feature to satisfy the public interfaces in the contract
    - Follow existing codebase patterns (read neighboring files for style)
    - Add dependencies to package manifests if needed
    - Do NOT write test files -- the test agent handles all tests
    - Read the plan file for full context: [plan file path]

    CONSTRAINTS:
    - Do NOT commit
    - Do NOT modify files outside YOUR FILES list
    - Do NOT run git commands
    - Report back: files created/modified, any issues encountered"

  test-agent: "You are Agent 2 (Tests) in a parallel lifecycle.

    BRANCH: [current branch name]
    WORKING DIRECTORY: [absolute worktree path]

    INTERFACE CONTRACT:
    [Full contract document from Step 02]

    YOUR FILES:
    [Exact file list from the Agent 2 (Tests) row in File Scopes]

    INSTRUCTIONS:
    - Write acceptance tests from the interface contract (ATDD RED phase)
    - Tests must validate the public interfaces listed in the contract
    - Use Given/When/Then format where the project convention supports it
    - Do NOT read source files -- write tests from the contract only
    - Use the project's test framework (auto-detect from package.json/Cargo.toml/etc.)
    - Read the plan file for full context: [plan file path]

    CONSTRAINTS:
    - Do NOT commit
    - Do NOT modify files outside YOUR FILES list
    - Do NOT run git commands
    - Report back: files created/modified, any issues encountered"
```

## Step 04: Collect results and commit

Wait for both agents to complete. Then:

1. Review each agent's report for completeness and issues
2. **If any agent failed:** keep the successful agent's output and complete the remaining work sequentially via Tier C (the task execution loop). Write the failure to `session-state.md` for compound to pick up. Proceed to the commit step below with whatever output exists.
3. Stage and commit all agent output:

   ```bash
   git add .
   git commit -m "feat: parallel agent output (pre-integration)"
   ```

   The coordinator MUST commit before invoking test-fix-loop. test-fix-loop requires a clean working tree and aborts if uncommitted changes exist.

## Step 05: Integration -- test-fix-loop until GREEN

Run the project's test command to check integration.

- **If tests pass:** Proceed to Step 06.
- **If tests fail:** Iterate a test-fix loop until GREEN (read error, fix, re-run — max 5 iterations).
- **If test-fix-loop cannot converge:** Flag as contract-test mismatch. Write the failing tests and implementation summary to `session-state.md`. Proceed to Phase 3 for user review.

## Step 06: Write docs sequentially, proceed to Phase 3

After GREEN (or after flagging non-convergence):

1. Write documentation sequentially (architecture docs, feature docs). Docs benefit from seeing the final integrated implementation.
2. Create an incremental commit for documentation if any docs were written.
3. Update `task_tracker` to mark all completed tasks.
4. Proceed to Phase 3 (Quality Check).
