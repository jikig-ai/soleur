# Tasks: fix agent-browser navigation hang (#6605)

Plan: `knowledge-base/project/plans/2026-07-17-fix-agent-browser-nav-hang-no-sandbox-plan.md`
Lane: procedural | Threshold: none

## Phase 0 — Verify premises (fast, before editing)

- [ ] 0.1 Confirm all edit sites exist:
  `git grep -n "agent-browser@0.22.3" plugins/` and `git grep -nE "agent-browser (open|snapshot|screenshot)" plugins/soleur/skills/{agent-browser,test-browser,feature-video}/SKILL.md`.
- [ ] 0.2 Read `plugins/soleur/skills/agent-browser/SKILL.md` (esp. the `:28-33` "Version
  mismatch" Troubleshooting block, to mirror its shape) and `feature-video/scripts/check_deps.sh`.
- [ ] 0.3 Confirm no in-repo Playwright-MCP lifecycle emission site (D3 honesty check):
  `git grep -niE "playwright.?mcp|browserBackend|mcp__playwright" plugins/ apps/ .claude/ scripts/`.
  Record result in the learning file (expected: none we control → documented recipe, not a hook).

## Phase 1 — D1: restore navigation (`--no-sandbox`)

- [ ] 1.1 `agent-browser/SKILL.md`: add `AGENT_BROWSER_ARGS="--no-sandbox"` setup ahead of
  the first `open` example (`:46`); add a "No usable sandbox (Chrome fails to launch / hangs)"
  Troubleshooting entry naming the AppArmor/userns cause + the env/`--args` remedy.
- [ ] 1.2 `test-browser/SKILL.md`: add the setup line near the `open` invocation (`:142`) +
  a one-line cross-reference to the agent-browser Troubleshooting entry.
- [ ] 1.3 `feature-video/SKILL.md`: add the setup line ahead of the recording flow (`:176`)
  + cross-reference.

## Phase 2 — D2: diagnosable failure (no silent hang)

- [ ] 2.1 `feature-video/scripts/check_deps.sh`: after the `command -v agent-browser`
  check, add a **bounded** launch smoke test
  (`AGENT_BROWSER_ARGS="--no-sandbox" timeout 45 agent-browser open ... --headless`) that
  on non-zero/timeout prints an actionable message naming `--no-sandbox` + the userns cause.
  Preserve existing hard/soft dependency exit semantics.
- [ ] 2.2 Document the daemon-cleanup discipline (kill stray `agent-browser-linux-x64`,
  clear `/tmp/agent-browser` + `/run/user/<uid>/agent-browser`) in the SKILL.md
  Troubleshooting so a wedged daemon is not misread as a launch failure.
- [ ] 2.3 **Version-bump decision (GATED).** Decide keep-0.22.3 (default) vs bump-0.32.1.
  If bumping: verify 0.32.1 CDP/Chromium compatibility with the co-resident Playwright MCP
  (Test Scenario 5), then sweep every pin site (plan §D2.2). If keeping: leave pins,
  record the Risks rationale for the PR body. Either way, satisfy AC6.

## Phase 3 — D3 + D4: observability recipe + lesson

- [ ] 3.1 `agent-browser/SKILL.md` Troubleshooting: add the MCP backend-close signature
  (`browserBackend.callTool: Target page, context or browser has been closed`) + recovery
  (re-navigate; selector/name targeting, not stale `ref=`).
- [ ] 3.2 Create
  `knowledge-base/project/learnings/bug-fixes/2026-07-17-agent-browser-hang-is-missing-no-sandbox-not-dead-tool.md`:
  root cause (AppArmor userns → missing `--no-sandbox`), the measured decision matrix, the
  D3 out-of-repo-emission finding, and the durable lesson (probe before declaring a tool
  dead / reclassifying a robot job as a human chore).

## Phase 4 — Verify (Acceptance Criteria)

- [ ] 4.1 AC1: clean-slate `AGENT_BROWSER_ARGS="--no-sandbox" timeout 45 agent-browser open https://example.com --headless` → EXIT=0 + success line.
- [ ] 4.2 AC2: run `check_deps.sh` against a forced-sandbox invocation → bounded non-zero + `--no-sandbox` message; no unbounded hang.
- [ ] 4.3 AC3: `git grep -n "no-sandbox" plugins/soleur/skills/` hits all three SKILL.md files.
- [ ] 4.4 AC4/AC5: Troubleshooting backend-close recipe present; learning file present.
- [ ] 4.5 AC6/AC7: pin-bump branch honored + recorded; `git diff --stat origin/main...HEAD` touches only `plugins/soleur/skills/**` + `knowledge-base/**` (no `apps/**`, `*.tf`, workflow YAML).
- [ ] 4.6 Sweep test daemons at the end (leave no orphan `agent-browser-linux-x64`; never touch Playwright MCP procs).
