---
title: "fix: ship — add unpushed-commits gate before queuing auto-merge"
type: fix
date: 2026-05-12
issue: "#3632"
classification: workflow-gate
requires_cpo_signoff: false
---

# fix: ship — add unpushed-commits gate before queuing auto-merge

## Enhancement Summary

**Deepened on:** 2026-05-12
**Sections enhanced:** Phase A (empirical hook-input verification), Hook ordering, Test Scenarios (T12-T14 added), Risks (R5-R7 added), Sharp Edges (3 new entries), Out-of-Scope (new section)
**Research sources:**
- `knowledge-base/project/learnings/2026-05-10-empirical-hook-input-shape-prevents-silent-zero-emission.md`
- `knowledge-base/project/learnings/2026-03-28-pretooluse-hook-guard-ordering-matters.md`
- `knowledge-base/project/learnings/2026-03-19-pre-merge-hook-false-positive-on-string-content.md`
- `knowledge-base/project/learnings/2026-03-19-ci-squash-fallback-bypasses-merge-gates.md`
- `knowledge-base/project/learnings/2026-04-02-ship-review-evidence-coupling.md`
- `knowledge-base/project/learnings/2026-03-03-pre-merge-rebase-hook-implementation.md`
- `knowledge-base/project/learnings/2026-03-05-plan-review-scope-reduction-and-hook-enforced-annotations.md`
- Live grep of `.github/workflows/scheduled-*.yml` for `gh pr merge` call sites
- `.claude/hooks/lib/incidents.sh` `emit_incident` contract (lines 148-240)

### Key Improvements
1. **Hook-input shape is now empirically verified before implementation** (Phase A.1) — not hypothesized from training data. The PreToolUse Bash hook payload shape is verified via a stub-capture in a child `claude -p` session before `.claude/hooks/ship-unpushed-commits-gate.sh` is written. This closes the silent-zero-emission class from #3494/#3495.
2. **Guard ordering audited** — the unpushed-commits check fires AFTER `pre-merge-rebase.sh` (its own merge-of-main pushes the new state) but BEFORE the detached HEAD exit within this new hook, mirroring the 2026-03-28 finding that context-independent guards must precede context-dependent exits.
3. **String-content false-positive surface explicitly addressed** — T8 verifies the chain-operator regex does NOT match `gh pr merge` embedded in echo/heredoc strings; the SKILL.md Phase 6.4 prose snippet uses `git rev-list` (no `merge` keyword) so it does not re-trigger `pre-merge-rebase.sh`'s broad scan.
4. **Out-of-Scope section enumerates 14+ `.github/workflows/scheduled-*.yml` `gh pr merge` call sites** that run inside GitHub Actions runners — they are NOT protected by this hook by design. AGENTS.md rule body is the cross-surface contract; a follow-up issue is filed for the workflow surface to be addressed separately.
5. **Add `[hook-enforced: ...]` annotation pattern** — the new AGENTS.core.md rule body uses `[skill-enforced: ship Phase 6.4 + hook ship-unpushed-commits-gate.sh]` per the 2026-03-05 convention to make defense duplication grep-able.
6. **Phase A.1 inspection gate is mandatory** — explicitly load-bearing per the Sharp Edges section; cannot be elided.

### New Considerations Discovered
- The new hook is the FIRST hook in this repo that needs to operate on the OUTPUT of a prior hook (`pre-merge-rebase.sh` may have pushed a merge commit before this hook fires). Ordering in `.claude/settings.json` is therefore load-bearing — see AC11 (T11).
- The chain-operator regex from `pre-merge-rebase.sh:25` (`(^|&&|\|\||;)\s*gh\s+pr\s+merge(\s|$)`) is the canonical form; reusing it verbatim avoids regex-drift in the same hook family.
- `emit_incident` writes to `.claude/.rule-incidents.jsonl` via `flock -x`; tests must use `INCIDENTS_REPO_ROOT` to redirect writes off the operator's real jsonl, per `lib/incidents.sh` convention (lines 19-25).
- Plan-review-scope-reduction (2026-03-05) confirms the three-layer defense (hook + SKILL.md + AGENTS.md) is justified at this scale — a hook alone misses headless `gh` invocations; prose alone misses the orchestrator path that ignored Phase 6 step 1.

## Overview

Add a `PreToolUse` hook that intercepts every `gh pr merge` invocation and fails closed if `git rev-list origin/<branch>..HEAD` returns any commits. This closes the fail-open class that produced the #3624 → #3627 → #3630 incident chain, where 2 of 5 local commits (the actual fix + the review fix) were never pushed before auto-merge was queued. The squash-merge consumed only the 3 pushed commits, GitHub returned `MERGED` to the orchestrator, and the recovery only happened because the post-merge `critical-css-gate` happened to exercise the same code the PR was meant to fix.

The hook is the primary defense (mechanical, can't be skipped). Two layers of defense-in-depth back it up: an explicit Phase 6.4 step in `plugins/soleur/skills/ship/SKILL.md` and a workflow-gate rule in `AGENTS.core.md` that documents the contract for human readers.

## Problem Statement / Motivation

**Incident chain (2026-05-11):**

| PR | Intent | What landed | How the gap surfaced |
|----|--------|-------------|----------------------|
| #3624 | Fix `critical-css-gate` path filter + Playwright cache | _Initial fix_ — scoping + cache-key changes | Merged green |
| #3627 | Recover lost #3624 fix (workflow file + cache-key) | **Only planning artifacts** — actual `ci.yml` and cache-key edits never pushed | Post-merge `critical-css-gate` on main failed with the SAME chromium error #3624 was meant to fix |
| #3630 | Cherry-pick orphaned commits from reflog | Actual workflow fix + cache-key | Caught by post-merge CI on main, NOT by the ship pipeline |

**Root cause:** `plugins/soleur/skills/ship/SKILL.md` Phase 6 step 1 documents `git push -u origin <branch>`, but the one-shot orchestrator went `preflight → gh pr edit → gh pr ready → gh pr merge --squash --auto`, skipping the push because the branch already existed on origin from initial draft-PR creation. Local commits made AFTER that initial push were silently dropped from the merge.

**Why this is a fail-open class (the dangerous one):**

- The orchestrator believed it had shipped the PR.
- `main` believed it had merged the fix (GitHub returns `MERGED`).
- CI alone surfaced the discrepancy, and only because the post-merge gate happened to re-exercise the same code path.

A different class of fix — security-headers update, copy change, anything without a post-merge gate that re-runs the affected code — would have shipped a successful "fix" PR containing nothing of substance and gone undetected indefinitely. This is the worst kind of failure: silent, undetected, and presents as success to every observer except a coincidentally-aligned post-merge check.

**Existing gates that did NOT catch it:**

- `pre-merge-rebase.sh` hook: checks review evidence + dirty tree + merge conflicts + branch sync, but NOT unpushed commits.
- Phase 6.5 mergeability check: GitHub's `mergeable: MERGEABLE` reflects the state of the **pushed** branch — silent about local unpushed commits.
- `gh pr merge --auto`: GitHub has no concept of local commits; once queued, the merge ships whatever is on origin.

## Proposed Solution

**Three-layer defense, hook is primary.**

### Layer 1 (primary): PreToolUse hook `.claude/hooks/ship-unpushed-commits-gate.sh`

Intercepts every `gh pr merge` invocation. Reads the working directory from hook input `.cwd`, resolves the current branch, fetches its upstream tracking ref, and counts `git rev-list <upstream>..HEAD`. If non-zero, emits an `emit_incident` event tagged `wg-ship-push-before-merge` and returns `permissionDecision: deny` with a remediation message naming the unpushed commits.

Wired in `.claude/settings.json` under `hooks.PreToolUse` with `matcher: Bash`, slotted AFTER `pre-merge-rebase.sh` so the rebase step has already updated origin/main and (if it pushed a merge commit) updated the upstream tracking ref. This ordering matters: if `pre-merge-rebase.sh` merges main and pushes, the unpushed-commits gate sees the post-push state, not a transient pre-push state.

**Fail-open conditions (infra/edge cases):**

- Hook input lacks `.cwd` or path doesn't exist → exit 0.
- Not inside a git work tree → exit 0.
- Detached HEAD → exit 0 with stderr warning (no upstream to compare against).
- Branch is `main`/`master` → exit 0 (the agent is merging a PR _into_ main, not from a feature branch).
- No upstream tracking ref configured (`git rev-parse --abbrev-ref --symbolic-full-name @{u}` fails) → exit 0 with stderr warning. The branch was never pushed; this is a different (rarer) failure class; better to let the user see the upstream error from `gh pr merge` than to misclassify it.
- `git fetch origin <branch>` fails (network) → exit 0 with stderr warning. Fail-open on infra error per the same convention as `pre-merge-rebase.sh`.

**Fail-closed condition (the one this hook exists for):**

- `git rev-list <upstream>..HEAD` returns ≥1 commit → deny.

### Layer 2 (defense-in-depth): New Phase 6.4 in `plugins/soleur/skills/ship/SKILL.md`

Inserted between Phase 5.5 ("Pre-Ship Review Gates") and Phase 6 ("Push and Create PR"). The step runs:

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
git fetch origin "$BRANCH" 2>/dev/null || true
UNPUSHED=$(git rev-list "origin/${BRANCH}..HEAD" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$UNPUSHED" -gt 0 ]]; then
  echo "FAIL: ${UNPUSHED} local commits not pushed to origin/${BRANCH}." >&2
  echo "Commits:" >&2
  git log "origin/${BRANCH}..HEAD" --oneline >&2
  echo "Run 'git push' before queuing auto-merge." >&2
  exit 1
fi
```

This is redundant with the hook (the hook will block at the `gh pr merge` step anyway), but the prose-level instruction prevents drift between the hook and the documented workflow. If the hook is ever disabled / mis-wired / fails-open on an unexpected edge case, the prose gate still catches the class before reaching `gh pr merge`.

### Layer 3 (operator-readable contract): New `AGENTS.core.md` rule

```text
- Before running `gh pr merge`, verify `git rev-list origin/<branch>..HEAD` is empty
  [id: wg-ship-push-before-merge] [skill-enforced: ship Phase 6.4 + hook ship-unpushed-commits-gate.sh].
  Unpushed local commits are silently dropped from squash-merge. **Why:** 2026-05-11 #3624→#3627→#3630.
```

This rule is the human-readable contract; the hook is the mechanical enforcement. AGENTS.md is the index; the rule body lives in `AGENTS.core.md`.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (from issue body) | Codebase reality | Plan response |
|---|---|---|
| "Phase 6 step 1 prescribes a `git push -u origin <branch>` call" | Confirmed at `plugins/soleur/skills/ship/SKILL.md:661` | Keep existing push step; new gate sits before `gh pr merge` |
| "Existing hook `pre-merge-rebase.sh` blocks `gh pr merge` on missing review evidence" | Confirmed at `.claude/hooks/pre-merge-rebase.sh:1-197`; chain-operator regex `(^|&&|\|\||;)\s*gh\s+pr\s+merge(\s|$)` | Reuse the same regex pattern in the new hook for consistency |
| "Hook is preferred per the standard hierarchy" | Confirmed: existing CI/workflow guards (`guardrails.sh`, `pre-merge-rebase.sh`, `worktree-write-guard.sh`) all use the PreToolUse pattern with `emit_incident` from `lib/incidents.sh` | Hook is Layer 1; SKILL.md is Layer 2; AGENTS.md is Layer 3 |
| "There's already `rf-before-spawning-review-agents-push-the` for review" | Confirmed at `AGENTS.rest.md:23`. Scope is `/soleur:review`, not merge. | New rule `wg-ship-push-before-merge` is a sibling, not a replacement |

No drift between issue body and codebase. The fix is purely additive.

## User-Brand Impact

- **If this lands broken, the user experiences:** A `gh pr merge` invocation incorrectly blocked at the hook layer when it should have proceeded — observed as a `BLOCKED:` permission-decision message in the agent transcript and a halted ship pipeline. Recovery: the operator inspects the unpushed-commit list the hook prints, runs `git push`, and re-invokes ship.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A — workflow-gate change, no data path touched.
- **Brand-survival threshold:** `none`

`threshold: none, reason: This change is a CI/workflow-gate addition that touches no regulated data surface, no user-facing UI, and no LLM-mediated agent path. The change only narrows the set of commits that can ship via auto-merge — the failure mode is a halted ship pipeline (visible to the operator), not a corrupted production state.`

## Open Code-Review Overlap

None — no open `code-review` issues touch `.claude/hooks/*`, `plugins/soleur/skills/ship/SKILL.md`, or `AGENTS.core.md`.

(Verified via `gh issue list --label code-review --state open --json number,title,body --limit 200` and `jq` substring scan on the planned file paths.)

## Technical Considerations

### Architecture impacts

- New PreToolUse hook adds ~50ms of `git rev-list` + `git fetch` latency to every `gh pr merge` invocation. Acceptable — these invocations are already rare and operator-initiated.
- Hook ordering in `.claude/settings.json`: must be wired AFTER `pre-merge-rebase.sh`. Rationale: if `pre-merge-rebase.sh` merges `origin/main` into the feature branch and pushes the merge commit, the upstream tracking ref advances. Running the unpushed-commits check AFTER ensures it sees the post-push state, not the transient pre-push state.

### Performance implications

- `git fetch origin <branch>` is a single ref fetch (not a full fetch). Typical latency 100-300ms; bounded by network.
- `git rev-list origin/<branch>..HEAD | wc -l` is local-only; sub-millisecond.

### Security considerations

- Hook reads `.cwd` from hook input. The path is operator-supplied via the harness; treated as untrusted. Resolved via `git -C "$WORK_DIR"` rather than `cd "$WORK_DIR"` to avoid PATH/env contamination.
- No secret material is read or written. The hook only counts commits and emits an incident record.

### NFR impacts

- **Reliability:** Closes the fail-open class that produced the #3624→#3627→#3630 chain. Net reliability gain.
- **Observability:** `emit_incident wg-ship-push-before-merge` writes to the rule-incidents jsonl, allowing the weekly aggregator to track how often the gate fires.
- **Operability:** Failure message includes the full list of unpushed commits via `git log origin/<branch>..HEAD --oneline`, so the operator immediately sees what was about to be dropped.

### Attack Surface Enumeration

This is not a security fix per se, but the gate does close a specific *workflow* attack surface:

- **Path 1 (covered):** Agent runs `gh pr merge <N>` after committing locally without pushing → blocked.
- **Path 2 (covered):** Agent chains commands `git commit -m '...' && gh pr merge <N>` → blocked. The chain-operator regex `(^|&&|\|\||;)\s*gh\s+pr\s+merge(\s|$)` catches chained invocations (reused from `pre-merge-rebase.sh`).
- **Path 3 (not covered, by design):** Agent or human runs `gh pr merge` from outside Claude Code (gh CLI directly in a shell, GitHub UI, gh-action workflow). The hook can only intercept tool invocations within the harness. Document this in the gate's docstring; the AGENTS.md rule is the cross-surface contract for these cases.
- **Path 4 (not covered, by design):** Agent runs `gh pr merge` with `--admin` or in a context where the branch is already up-to-date on origin but a fresh commit was made post-push and the upstream tracking ref hasn't been refreshed. Mitigated by `git fetch origin <branch>` at hook entry to refresh the tracking ref before the check.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1: Hook script exists.** `.claude/hooks/ship-unpushed-commits-gate.sh` is a 644-mode executable bash script that takes hook input on stdin and produces JSON on stdout per the existing PreToolUse hook convention.
- [ ] **AC2: Hook fires on the right command shape.** Matches `gh pr merge ...` at start-of-string AND after chain operators `&&`, `||`, `;` (re-using the regex from `pre-merge-rebase.sh:25-27` verbatim). Does NOT match unrelated commands containing the substring (e.g., `echo "gh pr merge"` inside a heredoc).
- [ ] **AC3: Fail-closed on unpushed commits.** Given a feature branch with `git rev-list origin/<branch>..HEAD` returning ≥1 commit, the hook emits `permissionDecision: deny` with a message that names the count and lists the commits, and `emit_incident wg-ship-push-before-merge deny <reason> <command>` writes one row to `.claude/.rule-incidents.jsonl`.
- [ ] **AC4: Pass-through on clean state.** Given a feature branch with `git rev-list origin/<branch>..HEAD` returning 0 commits, the hook exits 0 with empty stdout (or a JSON `additionalContext` confirming the gate passed).
- [ ] **AC5: Fail-open on infra edge cases.** Skips silently (exit 0, no incident emitted) when: (a) not in a git work tree, (b) on `main`/`master` branch, (c) detached HEAD, (d) no upstream tracking ref configured, (e) `git fetch` fails on network error.
- [ ] **AC6: Hook is wired in settings.** `.claude/settings.json` lists the new hook under `hooks.PreToolUse` with `matcher: Bash`, ordered AFTER `pre-merge-rebase.sh` and BEFORE the worktree-write/security/skill-invocation hooks. Settings file remains valid JSON (`jq . .claude/settings.json` exits 0).
- [ ] **AC7: SKILL.md Phase 6.4 is documented.** `plugins/soleur/skills/ship/SKILL.md` contains a new `## Phase 6.4: Unpushed-Commits Gate` section between `## Phase 5.5: Pre-Ship Review Gates` and `## Phase 6: Push and Create PR`. The section names the hook, prescribes the equivalent shell snippet for headless/non-hooked contexts, and references rule id `wg-ship-push-before-merge` via `[skill-enforced: ship Phase 6.4 + hook ship-unpushed-commits-gate.sh]`.
- [ ] **AC8: AGENTS.md rule index updated.** `AGENTS.md` Workflow Gates section adds `- [id: wg-ship-push-before-merge] → core` immediately AFTER `wg-after-marking-a-pr-ready-run-gh-pr-merge`, preserving alphabetical/chronological cluster ordering.
- [ ] **AC9: AGENTS.core.md rule body added.** `AGENTS.core.md` Workflow Gates section contains the new rule body, single line, ≤600 bytes, ending with `[id: wg-ship-push-before-merge] [skill-enforced: ship Phase 6.4 + hook ship-unpushed-commits-gate.sh]`, including the `**Why:** 2026-05-11 #3624→#3627→#3630.` provenance suffix.
- [ ] **AC10: Tests pass.** `bash .claude/hooks/ship-unpushed-commits-gate.test.sh` reports all assertions PASS. Test cases enumerated under `## Test Scenarios`.
- [ ] **AC11: No retired-rule citations.** `grep -n 'wg-ship-push-before-merge' .claude/hooks/ship-unpushed-commits-gate.sh plugins/soleur/skills/ship/SKILL.md AGENTS.md AGENTS.core.md` returns matches in those four files only.
- [ ] **AC12: PR body uses `Closes #3632`** (not `Ref #3632`, not in title).

### Post-merge (operator)

- [ ] **AC13: Telemetry confirmation.** After the PR merges and one ship cycle has run on another PR, verify the gate's incident-emission row exists in `.claude/.rule-incidents.jsonl` (or its aggregated form) by grepping for `wg-ship-push-before-merge` with `event_type in {applied, deny}`. No-op if no ship cycle has fired since merge.

## Test Scenarios

Translate each acceptance criterion into a deterministic test. Tests live in `.claude/hooks/ship-unpushed-commits-gate.test.sh`, modeled on `.claude/hooks/pre-merge-rebase.test.sh`'s fixture-based pattern: each test builds its own tmp work-tree + tmp incidents root, sets `INCIDENTS_REPO_ROOT` to redirect emissions, calls the hook with `make_payload`, and asserts via `assert_deny` / `assert_pass`.

### T1: Unpushed commits → DENY

- **Given** a feature branch `feat-foo` with origin already containing commit A, and a local commit B on top that has NOT been pushed,
- **When** the hook receives `{"cwd": "<work>", "tool_input": {"command": "gh pr merge 999 --squash"}}`,
- **Then** stdout JSON contains `permissionDecision: "deny"` with a message naming "1 local commit", and `.claude/.rule-incidents.jsonl` has exactly one row with `rule_id: wg-ship-push-before-merge`, `event_type: deny`.

### T2: Clean state → PASS

- **Given** a feature branch where `origin/feat-bar` and `HEAD` point to the same commit,
- **When** the hook receives `{"cwd": "<work>", "tool_input": {"command": "gh pr merge 999 --squash --auto"}}`,
- **Then** the hook exits 0 with stdout either empty or a JSON `additionalContext` field. No incident row.

### T3: On main → PASS (fail-open)

- **Given** a checkout on `main`,
- **When** the hook receives a `gh pr merge` command,
- **Then** the hook exits 0 silently. No incident row.

### T4: Detached HEAD → PASS (fail-open)

- **Given** a detached-HEAD checkout (e.g., `git checkout <sha>`),
- **When** the hook receives a `gh pr merge` command,
- **Then** the hook exits 0 with a stderr warning. No incident row.

### T5: No upstream tracking → PASS (fail-open)

- **Given** a freshly-created local branch with no `@{u}` configured,
- **When** the hook receives a `gh pr merge` command,
- **Then** the hook exits 0 with a stderr warning. No incident row.

### T6: Non-merge command → PASS (no-op early exit)

- **Given** any tree state,
- **When** the hook receives `{"tool_input": {"command": "git status"}}`,
- **Then** the hook exits 0 with no output. No git operations performed (verifiable via stderr).

### T7: Chained command form → DENY

- **Given** an unpushed commit on the feature branch,
- **When** the hook receives `{"tool_input": {"command": "git commit -m 'x' && gh pr merge 999 --squash"}}`,
- **Then** stdout JSON contains `permissionDecision: "deny"`. The chain-operator regex catches the embedded `gh pr merge`.

### T8: Substring false-positive → PASS

- **Given** any tree state,
- **When** the hook receives `{"tool_input": {"command": "echo 'gh pr merge example'"}}`,
- **Then** the hook exits 0. (The regex's `\s+pr\s+merge(\s|$)` anchoring keeps the `echo` invocation outside the match.)

### T9: Fetch network failure → PASS (fail-open)

- **Given** a feature branch whose origin remote is set to a non-existent URL (`git remote set-url origin /nonexistent`),
- **When** the hook receives a `gh pr merge` command,
- **Then** the hook exits 0 with a stderr warning. No incident row.

### T10: Settings.json structural validity

- **When** `jq . .claude/settings.json > /dev/null`,
- **Then** exit 0.

### T11: Hook ordering

- **When** parsing `.claude/settings.json` with `jq '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command'`,
- **Then** the order is: `guardrails.sh`, `pre-merge-rebase.sh`, `ship-unpushed-commits-gate.sh`.

### T12: emit_incident contract — prefix length

- **Given** a deny path,
- **When** the hook calls `emit_incident wg-ship-push-before-merge deny <prefix> <cmd>`,
- **Then** the row written to `.claude/.rule-incidents.jsonl` has `rule_text_prefix` ≤ 50 chars (per `lib/incidents.sh:178-180` convention) and `command_snippet` ≤ 1024 chars (per `lib/incidents.sh:185-188`).

### T13: emit_incident contract — INCIDENTS_REPO_ROOT redirect

- **Given** `INCIDENTS_REPO_ROOT=$tmp/incidents` set in the test env,
- **When** the hook fires a deny,
- **Then** the jsonl row lands at `$tmp/incidents/.claude/.rule-incidents.jsonl` (NOT the operator's real path). Necessary to keep test runs from polluting production telemetry.

### T14: JSON output is not corrupted by git progress messages

- **Given** a `git fetch origin <branch>` invocation that may print to stderr (progress messages, hint output),
- **When** the hook's `git fetch` runs,
- **Then** the hook's stdout contains EXACTLY one valid JSON object (no `Auto-merging`, no `From origin`, no warnings interleaved). Verifiable via `jq . <stdout>` exit 0 + single-object check. This is the canonical learning-2026-03-03 regression test for this hook family.

## Files to Edit

- `.claude/settings.json` — wire new hook entry under `hooks.PreToolUse`, slotted AFTER `pre-merge-rebase.sh`.
- `plugins/soleur/skills/ship/SKILL.md` — insert new `## Phase 6.4: Unpushed-Commits Gate` section between Phase 5.5 and Phase 6. Reference the hook by absolute path.
- `AGENTS.md` — add `- [id: wg-ship-push-before-merge] → core` to Workflow Gates index.
- `AGENTS.core.md` — add the rule body in the Workflow Gates cluster.

## Files to Create

- `.claude/hooks/ship-unpushed-commits-gate.sh` — the new PreToolUse hook. ~100 lines, modeled on `pre-merge-rebase.sh` for incident emission, command-shape detection, and JSON output convention.
- `.claude/hooks/ship-unpushed-commits-gate.test.sh` — fixture-based test harness, modeled on `pre-merge-rebase.test.sh`. Implements T1-T11 above.
- `knowledge-base/project/learnings/2026-05-12-ship-unpushed-commits-fail-open-class.md` — learning file capturing the #3624→#3627→#3630 chain, the fail-open class, the hook+phase+rule remediation, and the broader pattern: "auto-merge believes pushed state is canonical; local state is invisible to GitHub."

## Implementation Phases

Phase order is load-bearing — Phase A must land before Phase B because Phase B's test harness depends on the hook script being executable, and Phase D must land before Phase C runs at ship time because SKILL.md references the hook by path.

### Phase A: Create the hook script and tests (RED → GREEN)

#### Phase A.1 — Empirical hook-input shape verification (MANDATORY, BEFORE any code is written)

Per learning `2026-05-10-empirical-hook-input-shape-prevents-silent-zero-emission.md`, the PreToolUse Bash hook input shape MUST be empirically captured from a real Claude Code session before implementation. Field paths reconstructed from training data are unreliable — even the sibling `pre-merge-rebase.sh` script uses `.tool_input.command // ""` and `.cwd // ""`, which is the documented contract, but the schema has drifted before (see #3494). The cost of misreading the shape is silent fail-open: every `gh pr merge` would slip through with `CMD=""` and skip the regex match.

**Procedure:**

1. Write a stub PostToolUse / PreToolUse Bash capture hook to `/tmp/ship-gate-stub-capture.sh` that writes raw stdin to `/tmp/ship-gate-input-sample.json` and exits 0.
2. Wire the stub temporarily in `.claude/settings.json` under `hooks.PreToolUse` matcher `Bash`. Note: `.claude/settings.json` reloads only at session start.
3. Run a child `claude -p 'echo hello'` session from this worktree. The child loads the modified settings, fires the stub on its own internal Bash invocation, and writes the sample to `/tmp/`.
4. Inspect `/tmp/ship-gate-input-sample.json` and confirm:
   - `.tool_input.command` (string) exists.
   - `.cwd` (string) exists and resolves to the worktree path.
   - `.tool_name` is `"Bash"`.
5. Add a date-stamped header comment to the new hook recording the verified shape, mirroring `.claude/hooks/skill-invocation-logger.sh:13-22`:

   ```bash
   # Empirically-verified PreToolUse(Bash) input shape (2026-05-12):
   #   .tool_input.command  (string) — the bash command string
   #   .cwd                 (string) — absolute path to the working directory
   #   .tool_name           ("Bash") — confirms matcher dispatched correctly
   ```

6. Remove the stub from `.claude/settings.json` and delete `/tmp/ship-gate-stub-capture.sh` and `/tmp/ship-gate-input-sample.json`.

**Gate:** If A.1 returns ANY field path different from the sibling hook contract, halt Phase A and surface the drift before proceeding — the entire hook ecosystem (5 active PreToolUse Bash hooks) shares the contract, and a drift discovered here would invalidate the assumptions baked into all five.

**Why this gate exists:** It is the cheapest place to catch a contract drift. Discovered later, the same drift would require re-writing the hook + the test suite + every assertion sketch in this plan.

#### Phase A.2 — RED: write failing tests

1. Write `.claude/hooks/ship-unpushed-commits-gate.test.sh` with T1-T14 stubs (T1-T11 from this plan + T12-T14 added by deepen-plan, see Test Scenarios below). Initially failing because the hook does not exist.

#### Phase A.3 — GREEN: implement the hook

1. Implement `.claude/hooks/ship-unpushed-commits-gate.sh`:
   - Add date-stamped header documenting the verified hook-input shape (from Phase A.1).
   - `set -eo pipefail` (omit `-u` — hook fail-paths must return JSON, not crash on unset; mirrors `pre-merge-rebase.sh:21-22`).
   - Source `lib/incidents.sh` for `emit_incident`.
   - Single `jq` fork to extract both `.tool_input.command` and `.cwd` via `@sh` shell-escape (mirrors `guardrails.sh:30` — halves hot-path overhead).
   - **Guard ordering (load-bearing, per learning 2026-03-28):**
     1. **Early exit on non-merge command:** Regex match `(^|&&|\|\||;)\s*gh\s+pr\s+merge(\s|$)` — exit 0 if no match. Context-independent; fires first.
     2. **Main/master skip:** the agent merges PRs INTO main, not from it. The check is meaningless on main, so this exit is safe to place before the upstream-required guards.
     3. **Detached HEAD skip:** no upstream tracking to compare against. Place AFTER main/master because the unpushed-commits intent doesn't apply.
     4. **No upstream tracking ref skip:** never pushed; out of this gate's scope.
     5. **Work-tree existence skip:** bare repo / missing dir → fail-open.
   - `git -C "$WORK_DIR" fetch origin "$CURRENT_BRANCH" >/dev/null 2>&1 || { echo "warn..." >&2; exit 0; }` — fail-open on network error. **CRITICAL: redirect BOTH stdout and stderr** per learning 2026-03-03 session error #1 (`git fetch` prints progress to stderr; mixing with hook JSON corrupts output).
   - `UNPUSHED=$(git -C "$WORK_DIR" rev-list "origin/${CURRENT_BRANCH}..HEAD" 2>/dev/null | wc -l | tr -d ' ')`.
   - If `UNPUSHED > 0`:
     - Capture `COMMIT_LIST=$(git -C "$WORK_DIR" log "origin/${CURRENT_BRANCH}..HEAD" --oneline 2>/dev/null | head -10)` (cap to 10 commits to bound deny-message length).
     - Call `emit_incident wg-ship-push-before-merge deny "Before running \`gh pr merge\`, verify \`git rev-l" "$CMD"` (50-char prefix per `lib/incidents.sh:178-180` convention).
     - Emit deny-JSON via single `jq -n` fork; message includes count, branch name, and the 10-commit list. Use `jq --arg` for all interpolated values to avoid quote/newline injection.
   - Else: exit 0 with `additionalContext` JSON confirming the gate passed (mirrors `pre-merge-rebase.sh:190-196`).
2. `chmod 755 .claude/hooks/ship-unpushed-commits-gate.sh`.
3. Run `bash .claude/hooks/ship-unpushed-commits-gate.test.sh` until all assertions PASS.

### Phase B: Wire the hook in settings (contract-declaring → must follow Phase A)

1. Edit `.claude/settings.json` — append the new entry to `hooks.PreToolUse` (Bash matcher), positioned after the `pre-merge-rebase.sh` entry, before `worktree-write-guard.sh`. (Note: worktree-write-guard runs on `Write|Edit`, not `Bash`, so ordering between Bash matchers is the only thing that matters.)
2. `jq . .claude/settings.json` to validate JSON.
3. Smoke-test by running the hook against the current branch (which has 0 unpushed commits at this point if the implementation has been committed and pushed locally).

### Phase C: Document Phase 6.4 in ship/SKILL.md

1. Insert `## Phase 6.4: Unpushed-Commits Gate` between current Phase 5.5 and Phase 6.
2. Body names the hook by name, gives the equivalent shell snippet for headless/non-hooked contexts, references rule id `wg-ship-push-before-merge`.
3. Verify the section anchors with `grep -n "^## Phase" plugins/soleur/skills/ship/SKILL.md` (expected: 5.4, 5.5, 6.4, 6, 6.5, 7).

### Phase D: Update AGENTS.md index + AGENTS.core.md rule body

1. Edit `AGENTS.md` — add `- [id: wg-ship-push-before-merge] → core` in the Workflow Gates section, immediately after `wg-after-marking-a-pr-ready-run-gh-pr-merge`.
2. Edit `AGENTS.core.md` — add the single-line rule body in the same cluster.
3. Verify byte budget: `awk '/wg-ship-push-before-merge/ {print length($0)}' AGENTS.core.md` ≤ 600. Trim if over.
4. Verify rule-id immutability/uniqueness: `grep -c '\[id: wg-ship-push-before-merge\]' AGENTS.md AGENTS.core.md` returns 1 per file.

### Phase E: Capture the learning

1. Write `knowledge-base/project/learnings/2026-05-12-ship-unpushed-commits-fail-open-class.md` with the structure used by `2026-03-03-pre-merge-rebase-hook-implementation.md`:
   - Frontmatter: title, date, category `workflow-patterns`, tags `[integration-issues, claude-hooks, ship]`.
   - Problem: #3624→#3627→#3630 chain.
   - Solution: hook + Phase 6.4 + rule.
   - Key Insight: "GitHub's `MERGED` state reflects what's on origin, not what the agent committed locally. Any fail-open class on the push-step is invisible to GitHub and to the orchestrator."
   - Session Errors: TBD during implementation.

### Phase F: Verify across files

1. `grep -rn 'wg-ship-push-before-merge' . --exclude-dir=.git` — should match: hook script, hook test, SKILL.md, AGENTS.md, AGENTS.core.md, learning, plan file. No other call sites.
2. `bash .claude/hooks/ship-unpushed-commits-gate.test.sh` final green.
3. `bash .claude/hooks/pre-merge-rebase.test.sh` still green (regression check — settings changes must not affect prior hooks).

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)

**Status:** reviewed (carry-forward from issue body — issue was filed with `domain/engineering` label and the proposed fix is a hook + SKILL.md + AGENTS.md edit, all CTO-owned surfaces).

**Assessment:** The fix is a workflow-gate addition in the existing hook framework. No architecture impact beyond adding ~50ms to `gh pr merge` invocations. Reuses the proven `emit_incident` + chain-operator-regex + JSON-output pattern from `pre-merge-rebase.sh`. Defense ordering (hook → SKILL.md prose → AGENTS.md rule) follows the standard hierarchy. No cross-domain implications.

No Product/UX gate — change is invisible to end users.

## Success Metrics

- Zero recurrences of the #3624→#3627→#3630 class within 30 days of merge.
- `wg-ship-push-before-merge` `applied` events ≥ `deny` events × 5 in the rule-incidents jsonl (i.e., the gate fires harmlessly far more often than it fires on a real catch — the desired ratio for a successful guardrail).
- Existing ship pipelines continue to merge cleanly with no false-positive blocks. Measured by zero `deny` events on PRs that ultimately merge successfully on the first ship attempt.

## Dependencies & Risks

### Dependencies

- `lib/incidents.sh` (already present, used by all existing hooks).
- `jq` (already a hook-framework requirement).
- `git fetch` requires network connectivity — fail-open if absent.

### Risks

- **R1: False-positive on stale upstream tracking ref.** If `git fetch origin <branch>` fails or is skipped, `origin/<branch>` may be stale and `rev-list` could return commits that ARE on origin but not locally tracked. Mitigation: hook calls `git fetch origin "$BRANCH"` before the check; if fetch fails, fail open with stderr warning rather than deny. Sibling: matches `pre-merge-rebase.sh`'s convention.
- **R2: Hook bypass via direct shell.** If an operator runs `gh pr merge` from outside Claude Code (the gh CLI in a bash terminal), the hook does not fire. Documented in the SKILL.md Phase 6.4 prose; the AGENTS.md rule body is the cross-surface contract. Out of scope for this PR (see Out-of-Scope below).
- **R3: Hook ordering misalignment with pre-merge-rebase.sh.** If `pre-merge-rebase.sh` pushes a merge commit, the new gate must see the post-push state. Mitigated by wiring the new hook AFTER `pre-merge-rebase.sh` in `.claude/settings.json`. Tested in T11.
- **R4: Branch-name-with-special-characters edge case.** A branch like `feat/foo#bar` could mis-tokenize through some shell substitutions. Mitigated by quoting `"origin/${CURRENT_BRANCH}..HEAD"` and using `git -C "$WORK_DIR"` instead of `cd`.
- **R5: JSON output corruption from git progress messages** (learning 2026-03-03). `git fetch` and `git rev-list` can print progress/hints to stderr; redirecting only one stream lets the other interleave with hook JSON and break `jq` parsing on the harness side. Mitigation: every git invocation uses `>/dev/null 2>&1` unless capture is needed; T14 verifies stdout is parseable JSON.
- **R6: String-content false positive** (learning 2026-03-19 — pre-merge-rebase.sh's broad keyword match). The chain-operator regex must anchor at start-of-string or after `&&`/`||`/`;` with `\s+pr\s+merge(\s|$)` boundaries. Without anchoring, `echo 'gh pr merge'` inside a heredoc would trip the hook. T8 explicitly verifies this. The Phase 6.4 prose snippet uses `git rev-list` only (no `merge` keyword in the command string) so it does NOT trip `pre-merge-rebase.sh`'s broader scan when executed as a verification step.
- **R7: Hook silently fails on hook-input shape drift.** If Claude Code's PreToolUse Bash hook input schema changes (`.tool_input.command` becomes nested, renamed to camelCase, etc.), the `jq` extraction returns empty string, the regex never matches, and every `gh pr merge` slips through (silent fail-open — the WORST class). Mitigation: Phase A.1 empirical verification + date-stamped header comment in the hook script + T2 fixture-based test that fires a real `gh pr merge` payload (verifies the contract is honored end-to-end). See learning 2026-05-10.

### Non-Risks

- **Performance:** added ~300ms per `gh pr merge` invocation. Negligible (this is a once-per-PR operation, not a hot loop).
- **Backward compat:** no changes to public skills, agents, or commands. Existing ship invocations on clean state see no behavior change.

## Out-of-Scope (filed as separate follow-up)

The PreToolUse hook protects ONLY `gh pr merge` invocations dispatched through Claude Code's Bash tool. Live grep of `.github/workflows/scheduled-*.yml` identifies 14 additional `gh pr merge` call sites that the hook does NOT protect:

```
.github/workflows/scheduled-campaign-calendar.yml:187
.github/workflows/scheduled-dogfood-3155.yml:119
.github/workflows/scheduled-seo-aeo-audit.yml:105
.github/workflows/scheduled-competitive-analysis.yml:94
.github/workflows/scheduled-gdpr-gate-preflight-eval-50d.yml:97
.github/workflows/scheduled-growth-execution.yml:120
.github/workflows/scheduled-growth-audit.yml:263
.github/workflows/scheduled-disk-io-7d-recheck.yml:195
.github/workflows/scheduled-disk-io-24h-recheck.yml:208
.github/workflows/scheduled-content-generator.yml:181
.github/workflows/scheduled-bug-fixer.yml:252
.github/workflows/scheduled-content-publisher.yml:178
.github/workflows/scheduled-community-monitor.yml:162
.github/workflows/test-pretooluse-hooks.yml:99  (test workflow — N/A)
```

**Why out of scope:** These run inside GitHub Actions runners, not in Claude Code. The runner's job typically writes a file, `git add`/`commit`/`push`, THEN `gh pr merge --squash --auto` in the same step — the `push` is sequential, so the unpushed-commits class observed in #3624→#3627→#3630 (orchestrator skipping the push step) does not arise the same way. If a workflow's `push` step fails AND `--auto` is queued anyway, the workflow step itself fails (CI surfaces it). The risk profile is materially different.

**Defense for these workflows is the cross-surface AGENTS.md rule:** `wg-ship-push-before-merge`. Future workflow authors reading the rule will see the contract and structure their workflow steps to honor it.

**Follow-up filed:** Track via a new issue labeled `domain/engineering`, `type/chore`, `priority/p3-low` (verified via `gh label list`): "Audit `.github/workflows/scheduled-*.yml` `gh pr merge` call sites for unpushed-commits gate parity with the Claude Code hook." Defer until the hook lands and accumulates 30 days of telemetry — at which point the per-workflow risk profile can be assessed empirically rather than speculatively.

Additional out-of-scope surfaces (documented but NOT filed):

- **Manual `gh pr merge` from operator shell.** No mechanical defense possible (no harness intercept point). Cross-surface contract is the only signal.
- **GitHub UI merge button.** Same as above.
- **Third-party plugins / external automations.** Same as above.

## References & Research

### Issue + incident chain

- Issue: [#3632](https://github.com/jikig-ai/soleur/issues/3632)
- Incident chain: PR #3624 (initial fix), PR #3627 (broken — dropped 2 of 5 commits), PR #3630 (recovery via cherry-pick from reflog), commits `399898ce` (recovery merge) and `a23c4197` (broken merge).

### Sibling hook + tests (templates)

- `.claude/hooks/pre-merge-rebase.sh` (197 lines, lines 25-27 = chain-operator regex, lines 100-115 = guard ordering, lines 190-196 = success JSON)
- `.claude/hooks/pre-merge-rebase.test.sh` (217 lines, lines 40-72 = `assert_deny` helper, lines 75-95 = `init_git_repo` fixture)
- `.claude/hooks/guardrails.sh` (lines 24-30 = single-jq-fork `@sh` pattern)

### Hook framework

- `lib/incidents.sh:148-240` `emit_incident <rule_id> <event_type> <prefix> [<command>] [<hook_event>]` — event ∈ {deny, bypass, applied, warn}; prefix ≤50 chars; command_snippet ≤1024 chars; writes JSONL to `.claude/.rule-incidents.jsonl` via `flock -x`.
- `INCIDENTS_REPO_ROOT` env var (lib/incidents.sh:19-25): tests use this to redirect emissions off the operator's real jsonl.

### Sibling rules + conventions

- `AGENTS.rest.md:23` `rf-before-spawning-review-agents-push-the` — same shape (push-before-step), different step (review vs. merge).
- `[skill-enforced: ...]` annotation pattern (learning 2026-03-05): makes defense duplication grep-able for future retirement decisions; `grep -c 'skill-enforced'` gives an instant count.

### Load-bearing learnings (folded into Phase A + Risks + Sharp Edges)

- `2026-05-10-empirical-hook-input-shape-prevents-silent-zero-emission.md` — Phase A.1 gate.
- `2026-03-28-pretooluse-hook-guard-ordering-matters.md` — Phase A.3 guard ordering.
- `2026-03-19-pre-merge-hook-false-positive-on-string-content.md` — chain-operator regex + Sharp Edge on the `merge` keyword in command snippets.
- `2026-03-03-pre-merge-rebase-hook-implementation.md` — stdout/stderr redirect gotcha (R5/T14), fail-open vs fail-closed convention.
- `2026-04-02-ship-review-evidence-coupling.md` — three-signal pattern (local + git log + GitHub issue) — this hook does NOT need multi-signal because the question (`is local commit list non-empty?`) is a single source of truth.
- `2026-03-19-ci-squash-fallback-bypasses-merge-gates.md` — the GitHub Actions workflow surface (Out-of-Scope section) is structurally different — they push-then-merge sequentially in the same step, so the fail-open class is not the same shape. Worth tracking but not in scope.
- `2026-03-05-plan-review-scope-reduction-and-hook-enforced-annotations.md` — `[hook-enforced: ...]` / `[skill-enforced: ...]` convention; defense-in-depth annotation rather than deletion.

### External research

- GitHub auto-merge documentation: <https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request> — confirms that `gh pr merge --auto` queues a merge based on the PR's HEAD ref on origin, and that local commits are invisible to the auto-merge queue.
- `git rev-list <upstream>..HEAD` semantics: <https://git-scm.com/docs/git-rev-list> — confirms that the form returns commits reachable from HEAD but not from `<upstream>`, which is exactly the set of unpushed-or-rewound-but-not-pushed commits.
- Claude Code PreToolUse hook contract: per `lib/incidents.sh:177` and the sibling hooks, the input is JSON on stdin with `.tool_name`, `.tool_input.command`, and `.cwd`. **Phase A.1 verifies this empirically before relying on it.**

## Sharp Edges

- **Phase A.1 (empirical hook-input verification) is load-bearing — do not skip.** Per learning 2026-05-10, the cost of misreading the PreToolUse Bash hook input shape is silent fail-open: every `gh pr merge` slips through with `CMD=""`. Phase A.1 must complete with a date-stamped header comment in the hook source before Phase A.3 (implementation) starts. The verification cost is one `claude -p` child invocation (~5 seconds); the cost of skipping it is potentially shipping a hook that is structurally unable to fire.
- **Redirect BOTH stdout and stderr on every git invocation in the hook** (learning 2026-03-03). `git fetch` prints progress to stderr; `git rev-list` is silent but `git log` is verbose. Anything not explicitly captured for use must go to `/dev/null 2>&1`. T14 is the canonical regression test for this — keep it green.
- **Do not embed the word `merge` in the SKILL.md Phase 6.4 verification command snippet** (learning 2026-03-19 — `pre-merge-rebase.sh` matches `merge` keyword broadly in command strings). Use `git rev-list "origin/${BRANCH}..HEAD"` in the prose; do NOT use `git merge-base` or any other token containing `merge` in a literal command snippet that an agent might copy and execute, or it will trip `pre-merge-rebase.sh`'s review-evidence check. (Note: `merge-base` IS safe in `Files to Edit` text because that's prose, not an executable command.)
- **Hook ordering in `.claude/settings.json` is load-bearing** (learning 2026-03-28). The unpushed-commits hook must fire AFTER `pre-merge-rebase.sh` so that any auto-push performed by the latter has updated the upstream tracking ref. T11 verifies this. If a future hook is inserted between them, re-verify T11.
- **Don't grep for stale `wg-ship-push-before-merge` matches.** This is a NEW rule id; grep should return matches only in the files this PR touches. Any other match is either (a) a stale plan file (acceptable, learning files preserve history) or (b) a bug.
- **Don't put the gate INSIDE `pre-merge-rebase.sh`.** Resist the temptation to fold this into the existing hook to save a file. The existing hook has well-scoped responsibilities (review evidence + dirty tree + main-sync); adding unpushed-commit logic conflates four concerns and makes the failure messages harder to diagnose. Separate hook = separate emit_incident rule_id = separate test = clearer diagnostics.
- **Don't elide `git fetch` to save latency.** Without the fetch, the local tracking ref `origin/<branch>` may be stale; the gate would either silently miss unpushed commits (false-negative on the bug we're fixing) or fire spuriously on already-pushed commits the local ref hasn't caught up on. The 100-300ms latency is the price of correctness.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** Verified: this plan's threshold is `none` with the required scope-out rationale.
- **Phase ordering is load-bearing.** Phase A (hook + tests) must precede Phase B (settings wiring) — wiring a non-existent or broken hook means every Bash invocation fails. Phase D (rule registration) must precede or co-land with Phase C (SKILL.md), because Phase C's `[skill-enforced: ...]` reference assumes the rule exists.
- **The post-merge release-workflow verification (`wg-after-a-pr-merges-to-main-verify-all`) is unaffected.** This PR does not modify Phase 7 or post-merge steps.
