# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-12-fix-concierge-stream-timeout-debug-scroll-plan.md
- Status: complete

### Errors
None. CWD verified equal to WORKING DIRECTORY on first tool call. Branch is feat-one-shot-concierge-stream-timeout-debug-scroll (not main). Deepen-plan mandatory gates (4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT, 4.9 UI-wireframe) passed. Scope verified: only plan + tasks files touched.

### Decisions
- Two-defect scope confirmed; issue 4826 (nav-rail resume) explicitly EXCLUDED — it is the incidental workspace name, not the target.
- Timeout fix = re-arm the server idle watchdog (armRunaway) on the SDK `tool_progress` heartbeat dropped at soleur-go-runner.ts:2171 (Path A). Path B (raise the 90s constant) DELETED as an unfalsifiable magic-number that dissolves hung-tool detection.
- Hung-tool detection PRESERVED: a genuinely hung tool emits no tool_progress, so it still trips the 90s window. AC2b pins this.
- Server precedent: agent-runner.ts:1901-1948 already consumes tool_progress; fix is the symmetric ~3-line addition to soleur-go-runner.ts.
- Debug-panel sticky autoscroll via useRef + ul.scrollTop = ul.scrollHeight (not scrollIntoView, to avoid ancestor-scroll yank in the nested list), named threshold constant.

### Components Invoked
- Skill soleur:plan, Skill soleur:deepen-plan
- Agents: Explore x2, general-purpose x2 (SDK-realism verifier, verify-the-negative), architecture-strategist, code-simplicity-reviewer

## Gates
- requires_cpo_signoff: true (brand_survival_threshold: single-user incident). user-impact-reviewer runs at review time.
- CPO sign-off: APPROVED-WITH-NOTES (gate cleared before /work). Carry-forward:
  1. AC2b (genuinely hung tool with no tool_progress still fires idle_window at 90s) is MERGE-BLOCKING — without it the fix converts premature-death into hang-forever (worse UX).
  2. Client 45s "Retrying…" chip residual on cc surface (tool_progress not forwarded to client) must be filed as a real follow-up issue at /ship and stated plainly in the PR as a known residual — do NOT silent-close.
  3. No wireframe gate (internal debug drawer, no new user-facing surface).
