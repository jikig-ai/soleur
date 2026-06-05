# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-05-refactor-drain-p4-web-platform-scope-outs-plan.md
- Status: complete

### Errors
None. (Pencil Desktop AppImage crashed on launch, but the wireframe was produced via the registered Pencil MCP server using PENCIL_CLI_KEY from Doppler soleur/dev — no blocker.)

### Decisions
- #3331 scope corrected from issue's 5 files to grep-derived 8 runner test files; helpers have real signature divergence — plan prescribes configurable supersets, not verbatim extraction, with the full vitest suite as the green gate. `narration` has zero local helpers and is excluded.
- #3184 premise partially inverted: login/page.tsx is already a thin wrapper; the real OTP duplication is between components/auth/login-form.tsx and signup/page.tsx's inline SignupForm. Plan targets those, preserving each branch's distinct success route (/dashboard vs /accept-terms), the reportSilentFallback envelope, and login's isNoAccountError→/signup redirect exactly. 5 existing auth tests are the regression gate.
- #3333 write-scope review resolved: the GitHub App already declares issues: write (manifest:23, granted at PR #4226), so createIssue needs no new scope and mirrors createPullRequest's auth path 1:1. Gated via TOOL_TIER_MAP ("gated") + buildGateMessage, identical to createPr.
- Brand-survival threshold `none` with required sensitive-path scope-out bullet (diff touches server/* + lib/auth/* but is behavior-neutral).
- UI-wireframe gate (4.9) satisfied by a committed .pen for the OtpCodeStep surface; Observability gate (4.7) satisfied with a 5-field schema scoped to the createIssue tool's inherited error path.

### Components Invoked
- Skill: soleur:plan, soleur:deepen-plan
- Bash, Read, Edit, Write, ToolSearch + Pencil MCP
