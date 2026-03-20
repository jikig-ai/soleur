# Tasks: audit LS and NotebookRead tools for path validation bypass (#891)

## Phase 1: Investigation

- [ ] 1.1 Determine actual parameter names for LS tool
  - [ ] 1.1.1 Search SDK binary strings or runtime debug logging for LS tool schema
  - [ ] 1.1.2 If binary inspection fails, add temporary `console.log(toolName, toolInput)` to canUseTool and trigger LS via test prompt
  - [ ] 1.1.3 Document the confirmed parameter name(s) for LS

- [ ] 1.2 Determine actual parameter names for NotebookRead tool
  - [ ] 1.2.1 Infer from NotebookEdit schema (confirmed: `notebook_path`) and Read tool schema (confirmed: `file_path`)
  - [ ] 1.2.2 Verify via same method as 1.1
  - [ ] 1.2.3 Document the confirmed parameter name(s) for NotebookRead

## Phase 2: Core Implementation

- [ ] 2.1 Move LS and NotebookRead out of SAFE_TOOLS in `agent-runner.ts`
  - [ ] 2.1.1 Remove `"LS"` and `"NotebookRead"` from the SAFE_TOOLS array (line 270-277)
  - [ ] 2.1.2 Add code comment documenting why remaining SAFE_TOOLS members are safe

- [ ] 2.2 Extend the file-tool path check block
  - [ ] 2.2.1 Add `"LS"` and `"NotebookRead"` to the includes() check (line 210-211)
  - [ ] 2.2.2 Add `notebook_path` to the path extraction logic alongside `file_path` and `path`
  - [ ] 2.2.3 Verify the check covers all three parameter name variants

## Phase 3: Testing

- [ ] 3.1 Add unit tests for LS path validation
  - [ ] 3.1.1 Test: LS with path outside workspace is denied
  - [ ] 3.1.2 Test: LS with path inside workspace is allowed
  - [ ] 3.1.3 Test: LS with path traversal (../) is denied

- [ ] 3.2 Add unit tests for NotebookRead path validation
  - [ ] 3.2.1 Test: NotebookRead with file_path outside workspace is denied
  - [ ] 3.2.2 Test: NotebookRead with file_path inside workspace is allowed

- [ ] 3.3 Add negative-space enumeration test
  - [ ] 3.3.1 Define the canonical list of tools with path arguments
  - [ ] 3.3.2 Assert each tool routes through isPathInWorkspace or has documented exemption
  - [ ] 3.3.3 Verify SAFE_TOOLS contains only genuinely path-free tools

- [ ] 3.4 Run full test suite
  - [ ] 3.4.1 Run `./node_modules/.bin/vitest run` in apps/web-platform
  - [ ] 3.4.2 Verify all 21+ existing sandbox tests pass
  - [ ] 3.4.3 Verify new tests pass

## Phase 4: Documentation

- [ ] 4.1 Update attack surface enumeration learning if new parameter names discovered
- [ ] 4.2 Add code comments in agent-runner.ts explaining the security rationale
