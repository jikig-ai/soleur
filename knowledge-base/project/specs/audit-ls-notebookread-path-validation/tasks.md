# Tasks: audit LS and NotebookRead tools for path validation bypass (#891)

## Phase 1: Investigation

- [ ] 1.1 Determine actual parameter names for LS tool
  - [ ] 1.1.1 Add temporary `console.log(toolName, Object.keys(toolInput))` to canUseTool for LS/NotebookRead and trigger via test prompt
  - [ ] 1.1.2 If runtime logging not feasible, proceed with defensive multi-parameter check (`file_path || path || notebook_path`)
  - [ ] 1.1.3 Document the confirmed parameter name(s) for LS

- [ ] 1.2 Determine actual parameter names for NotebookRead tool
  - [ ] 1.2.1 Infer from NotebookEdit schema (confirmed: `notebook_path`) and Read tool schema (confirmed: `file_path`)
  - [ ] 1.2.2 Verify via same method as 1.1
  - [ ] 1.2.3 Document the confirmed parameter name(s) for NotebookRead

- [ ] 1.3 Verify NotebookEdit gap
  - [ ] 1.3.1 Confirm NotebookEdit currently hits deny-by-default (not in SAFE_TOOLS, not in file-tool check)
  - [ ] 1.3.2 Decide: should NotebookEdit within workspace be allowed? (If yes, add to file-tool check; if no, leave as deny-by-default)

## Phase 2: Core Implementation

- [ ] 2.1 Move LS and NotebookRead out of SAFE_TOOLS in `agent-runner.ts`
  - [ ] 2.1.1 Remove `"LS"` and `"NotebookRead"` from the SAFE_TOOLS array (line 270-277)
  - [ ] 2.1.2 Add code comment documenting why remaining SAFE_TOOLS members are safe (reference AgentInput, TodoWriteInput from SDK ToolInputSchemas)

- [ ] 2.2 Extend the file-tool path check block
  - [ ] 2.2.1 Add `"LS"`, `"NotebookRead"`, and `"NotebookEdit"` to the includes() check (line 210-211)
  - [ ] 2.2.2 Add `notebook_path` to the path extraction logic alongside `file_path` and `path`
  - [ ] 2.2.3 Add code comment listing the parameter name variants and which tools use which
  - [ ] 2.2.4 Add runtime warning log when LS/NotebookRead is invoked without a recognized path parameter (SDK version safety net)

## Phase 3: Testing

- [ ] 3.1 Consider extracting canUseTool path logic into `tool-path-checker.ts` for unit testability
  - [ ] 3.1.1 Extract `extractToolPath(toolName, toolInput)` and `FILE_TOOLS` constant
  - [ ] 3.1.2 Extract `isFileToolOutsideWorkspace(toolName, toolInput, workspacePath)` function

- [ ] 3.2 Add unit tests for LS path validation
  - [ ] 3.2.1 Test: LS with path outside workspace is denied
  - [ ] 3.2.2 Test: LS with path inside workspace is allowed
  - [ ] 3.2.3 Test: LS with path traversal (../) is denied
  - [ ] 3.2.4 Test: LS with no path parameter (empty toolInput) is allowed (defaults to cwd)

- [ ] 3.3 Add unit tests for NotebookRead path validation
  - [ ] 3.3.1 Test: NotebookRead with file_path outside workspace is denied
  - [ ] 3.3.2 Test: NotebookRead with file_path inside workspace is allowed

- [ ] 3.4 Add unit tests for NotebookEdit path validation
  - [ ] 3.4.1 Test: NotebookEdit with notebook_path outside workspace is denied
  - [ ] 3.4.2 Test: NotebookEdit with notebook_path inside workspace is allowed

- [ ] 3.5 Add negative-space enumeration test
  - [ ] 3.5.1 Define the canonical list of tools with path arguments: `["Read", "Write", "Edit", "Glob", "Grep", "LS", "NotebookRead", "NotebookEdit"]`
  - [ ] 3.5.2 Assert each tool in FILE_TOOLS routes through isPathInWorkspace
  - [ ] 3.5.3 Assert SAFE_TOOLS `["Agent", "Skill", "TodoRead", "TodoWrite"]` contains only genuinely path-free tools

- [ ] 3.6 Run full test suite
  - [ ] 3.6.1 Run `./node_modules/.bin/vitest run` in apps/web-platform
  - [ ] 3.6.2 Verify all 21+ existing sandbox tests pass
  - [ ] 3.6.3 Verify new tests pass

## Phase 4: Documentation

- [ ] 4.1 Update attack surface enumeration learning if new parameter names discovered
- [ ] 4.2 Add inline code comments in agent-runner.ts:
  - [ ] 4.2.1 Comment on SAFE_TOOLS explaining why each member is safe (with SDK type references)
  - [ ] 4.2.2 Comment on file-tool check block listing all parameter name variants
  - [ ] 4.2.3 Reference #891 in the change comment for future auditors
