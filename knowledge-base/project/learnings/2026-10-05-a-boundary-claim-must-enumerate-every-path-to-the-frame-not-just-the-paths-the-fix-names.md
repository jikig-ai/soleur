# Learning: a boundary claim must enumerate every path to the frame, not just the paths the fix names

## Problem

The #9539 fix ("a support turn can never schedule WS-bound gate/prompt
frames") was correctly implemented at the three sites the plan named —
schema removal (`SUPPORT_EXTRA_DISALLOWED_TOOLS`), a `canUseTool` persona
belt for AskUserQuestion, and a Bash short-circuit before the review-gate
emitters. The 10-seat review panel then showed the claim failed on at
least six paths the plan had not enumerated:

1. **`emitInteractivePrompt` fires on tool_use *sighting*, not on a
   permission decision.** `bridgeInteractivePromptIfApplicable`
   (soleur-go-runner.ts) runs before `canUseTool` resolves and had no
   persona check, so a schema-removed `TodoWrite`/`ExitPlanMode`/file-edit
   still emitted a WS-bound `interactive_prompt` and registered an
   answerable `pendingPrompts` entry — a cross-surface `tool_result`
   injection into a no-interaction turn.
2. **`allowedTools` bypasses `canUseTool` entirely.** The auto-approve
   list shared members with `SUPPORT_EXTRA_DISALLOWED_TOOLS`
   (TodoWrite/ExitPlanMode): a contradictory config that silently voided
   both the schema removal and the belt.
3. **`edit_c4_diagram` registered, advertised, and auto-approved on the
   read-only persona** — a real repo commit via the installation token
   that executes in the dispatch process, outside `allowWrite:[]`.
4. **The deny→record coverage was partial**: `Agent` (unconditional
   allow), file-tool write-class and outside-workspace denies, platform
   tools, and deny-by-default all produced the dead-end the PR was fixing.
5. **A per-conversation flag misattributes under concurrency** — the
   sticky support conversation + warm-Query `state.events` rebind means a
   second POST steals both the first turn's frames and its escalation
   flag.
6. **The one *allowed* skill's own documented shell-outs hit the new
   deny** (kb-search's `git grep`/`grep`/script paths are not safe-bash
   allowlisted) — the affordance misfires on its main use case.

Each seat found a different slice; no single review lens covered the path
set. Structural enumeration was the seat that tied them together because
it enumerated *paths to the frame*, not paths the diff touched.

## Solution

The pattern that generalizes (PR #9540 fix round, all five re-verifying
seats concurred):

1. **Guard the chokepoint, not the trigger.** The runner bridge got
   `if (state.persona === "support") return;` — one line that closes the
   whole `interactive_prompt` class regardless of which removed tool the
   model emits. When a class has N trigger paths and one emission
   chokepoint, guard the chokepoint.
2. **Intersect the allowlist with the disallowed set by construction.**
   `allowedTools: CC_PATH_ALLOWED_TOOLS.filter(t => persona !== "support"
   || !SUPPORT_EXTRA_DISALLOWED_TOOLS.includes(t))` — the filter is
   generic, so a future member of both lists is handled without a new
   belt.
3. **Gate a capability at its single assignment point.** The whole C4
   surface — tool build, `platformToolNames` entry, prompt addendum,
   advertise list — falls out of `if (c4Enabled && persona !==
   "support")` because every consumer reads `c4ToolName`/`c4PromptAddendum`.
4. **Deny coverage is an iff contract — enumerate every deny arm.** A
   shared `denySupport` helper (log + decision-log + escalation record +
   relayable deny) at *every* deny arm, with a source union
   `{skill, bash, tool}`; UX-signal denies (AskUserQuestion/TodoWrite/
   ExitPlanMode) deliberately do not record.
5. **Serialize at the transport boundary when shared state can't be
   re-keyed.** The escalation flag is keyed by conversationId and a
   per-dispatch key cannot reach the per-Query `canUseTool` ctx — so the
   route rejects a second POST on an in-flight conversation (409), which
   *also* fixes the pre-existing frame-hijack the rebinding caused.
6. **Write the residuals down with issue numbers.** kb-search
   false-positives (#9559), safe-bash `git branch` misclassification
   (#9555), GH-token/askpass/egress not persona-gated (#9558),
   `repoConnected` frame field (#9556), `?q=` param (#9557) — filed, not
   implied.

## Session Errors

- **Vacuous belt test** — the `Edit` write-class test passed via
  deny-by-default (the `isFileTool` mock returned false), not the belt
  being tested. **Prevention:** when a deny is reachable via two paths,
  drive the fixture through the specific arm AND assert a
  path-discriminating signal (message text or the arm's unique
  side-effect), not just `behavior === "deny"`.
- **`no-control-regex` new-instance warning** — the log sanitizer's
  `\x00-\x1f` class adds to a baselined warning count that a ratchet may
  gate on. **Prevention:** `\p{Cc}` (covers C0+C1+DEL) +
  `\u2028\u2029` with the `u` flag sanitizes the same surface without a
  literal-escape regex the rule flags.
- **gh filing-gate rejections ×4** — `--milestone` required, body-file
  must be a literal repo-local path (no `$VAR`/`~`/`/tmp`), and every
  filing needs an exit (`meta/machinery` label, `User-Impact:`+`Fix-Size:`
  pair inside the threshold rules, or `Mandated-By:` on its own line).
  **Prevention:** the gate's own refusal text names the contract — read
  `.claude/hooks/guardrails.sh` once rather than iterating rejects.
- **Mock-implementation leaks across tests** — `vi.clearAllMocks()`
  clears call history, not `mockReturnValue` implementations; a
  mid-describe override persisted into later tests. **Prevention:**
  restore every overridden impl inside the test that set it (or use
  `mockReturnValueOnce`).

## Cross-references

- Issue #9539, PR #9540, ADR-113 addendum (deny → handoff channel)
- `specs/feat-one-shot-9539-support-persona-write-dead-end/review-findings.md`
  — the 45-finding dedup ledger this learning summarizes
- #9555–#9559 — filed residuals
