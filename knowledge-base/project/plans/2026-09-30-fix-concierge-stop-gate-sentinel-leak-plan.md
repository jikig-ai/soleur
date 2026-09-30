---
title: "fix: Concierge shows raw stop-gate markup instead of the question list, and the turn hangs"
date: 2026-09-30
slug: concierge-stop-gate-sentinel-leak
branch: feat-one-shot-crm-lead-stop-gate-leak
type: fix
priority: p1
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# fix: Concierge shows raw stop-gate markup instead of the question list, and the turn hangs

Spec lacks a valid `lane:` (no `specs/feat-one-shot-crm-lead-stop-gate-leak/spec.md` exists) — defaulted to
`cross-domain` (fail-closed).

## Enhancement Summary

**Deepened on:** 2026-09-30
**Sections enhanced:** Research Insights, Cut List, Phase 1 (verification), Phase 2 (ordering), Sharp Edges
**Research agents used:** repo-research-analyst, learnings-researcher (plan phase); dhh-rails-reviewer, kieran-rails-reviewer,
code-simplicity-reviewer, cto (plan-review, findings already folded in); this pass added SDK-typings verification,
gate halts 4.6/4.7/4.8/4.9/4.11 (all pass), rule-ID / issue-number / hook-population live checks.

### Key improvements
1. Root-cause claim 1 (the web runtime executes plugin hooks) is now backed by the SDK's own typings, verbatim,
   rather than by inference from the incident (see *Deepen-pass evidence*).
2. A rejected-alternative was found that the plan had not considered and that looks attractive: the SDK
   `disableAllHooks` setting — recorded in the Cut List with the reason it cannot be used.
3. Phase 2 gained an ordering constraint (`recordAssistantBlock` must run before the strip) that protects the
   runaway-watchdog re-arm.

### New considerations discovered
- The SDK offers `get_hooks_listing` and `includeHookEvents` as in-surface probes for which hooks fire; not
  adopted in product code (volume/scope) but named as the QA method for Phase 1 step 4.
- The Phase 1 unit tests prove the hook honours the variable and that `buildAgentEnv` sets it; they cannot prove
  the CLI forwards `options.env` to hook children. That stays a measured QA step, not an assumption.

## Overview

In the web Concierge, the user typed "I want to enter a new CRM lead". The agent composed the intake question
list (lastContact, amount + currency, amountBasis, expectedCloseDate, optional note body + lens, "paste
everything in one message; I'll show a review before saving"). The chat bubble instead shows
`<stop>OPERATOR-GATE: I need the lead's details (at minimum a name) from you. ...</stop>`. The question list
survives only in the Debug stream, and the chat sits on "Still working..." with the Stop button although the
turn's `result` (cost $0.1887, 351 output tokens) arrived.

Root cause, established by reading code and reproducing the hook and the client reducer locally:

1. **Where the sentinel comes from — not the CRM prompt, not the Concierge system prompt, not any
   apps/web-platform stop-gate code.** `git grep` finds zero `<stop>` / `OPERATOR-GATE` handling anywhere in
   `apps/`. The sentinel is the escape-hatch vocabulary of the **plugin Stop hook**
   `plugins/soleur/hooks/unkept-promise-hook.sh` (registered in `plugins/soleur/hooks/hooks.json` under
   `Stop`). The web runtime loads the whole plugin — including its `hooks.json` — through the SDK binding
   `plugins: [{ type: "local", path: trustedPluginPath }]` in
   `apps/web-platform/server/agent-runner-query-options.ts`. `settingSources: []` blocks `.claude/settings.json`
   only; it does not stop plugin `hooks.json`. The hook is an **operator-CLI guard** ("the operator caught it
   because they can read pipeline state") that was never scoped out of the end-user Concierge.
2. **Why it fired.** The question list ends "I'll show you a review before saving, and that review is the only
   confirmation step." The hook's `PROMISE_RE` matches `i'll `; no conditional/pending allow arm matches that
   sentence; the message does not end in `?`. Reproduced by piping a synthetic
   `last_assistant_message` of that shape into the hook: `{"decision":"block"}`. The block `reason` instructs the
   model to write `<stop>OPERATOR-GATE: what you are waiting on</stop>`.
3. **Why the sentinel replaced the question list.** The model complied: assistant message 2 is only the stop tag.
   Server: `cc-dispatcher.ts` `onText` calls `state.setText(text)` and sends `stream {content, partial:true}`
   with **replace** semantics (W8) per text block. Client: `chat-state-machine.ts` `case "stream"` replaces the
   bubble content. Reproduced with the real reducer: `stream("list")` then `stream("<stop>x</stop>")` leaves one
   bubble whose content is the stop tag. The Debug stream appends (it never replaces), which is why the list
   survives only there. The persisted assistant row (`consumeForComplete()`) is likewise the last text — the stop
   tag.
4. **Why the turn "does not complete".** Measured with the real `chatReducer`: after `stream` + `stream_end`,
   `ChatState.streamState` **stays `"streaming"`**. The client leaves `streaming` only via `clear_streams`
   (`session_ended`, `error`, socket remount). The legacy `agent-runner.ts` emits
   `session_ended{turn_complete}`; the cc-soleur-go path (`soleur-go-runner.ts` `handleResultMessage` ->
   `onTextTurnEnd` -> `cc-dispatcher.ts` `stream_end`) never does, and the `git log -S turn_complete` history
   confirms it never did. So `streamState` never returns to `idle`: the "Still working..." placeholder
   (`chat-surface.tsx`, `streamState === "streaming" && !awaitingUserInput`) and the Stop button persist.
   **This is not proven to be specific to the stop-hook turn** — it may hit every cc turn, or an unlocated idle
   path may exist. Phase 3 opens with a wire-sequence test that settles this before any client change (see the
   stop condition there).

This plan fixes each link, test first, in order of leverage: stop the web runtime from running the operator
guard (root cause), make the visible text robust to gate markup anyway (the user's explicit requirement),
end the turn cleanly on the client, and record the boundary so the next operator-oriented Stop hook cannot
leak the same way.

## Research Insights

**Premise Validation.** The feature description cites no issue or PR by number. Cited file/symbol paths were
checked on this branch: `plugins/soleur/hooks/unkept-promise-hook.sh` and its test exist and contain the
sentinel; `apps/web-platform/server/cc-dispatcher.ts` `onText`/`onTextTurnEnd`, `soleur-go-runner.ts`
`handleAssistantMessage`/`handleResultMessage`, `lib/ws-client.ts` `chatReducer` all exist. The premise
"find where the sentinel is emitted in the CRM skill / concierge prompt / server stop-gate handling" is
**stale in shape**: none of those emit it (`git grep -n -i "<stop>\|OPERATOR-GATE" -- apps plugins/soleur/skills
plugins/soleur/agents` returns no runtime hit). "Stop-gate handling in apps/web-platform/server" does not
exist — the missing handling *is* the bug. ADR corpus probe for the proposed mechanisms: ADR-093 (SDK plugin
source is platform-deployed) is the governing decision for the plugin binding; it does not record that plugin
hooks execute in web sessions, and `model.c4` (API Routes container description) states the opposite
("settingSources:[] isolates these from the CLI .claude/ shell Hook Engine") — a falsified description this
plan corrects. No ADR rejects an env opt-out for plugin hooks.

**Property List (what must be true afterwards).**
- P1. When the agent composes a question list for the user, that list is the final visible Concierge reply
  (bubble and persisted row).
- P2. Internal stop-gate markup (`<stop>...</stop>`) never reaches a user-visible surface, whichever layer
  produced it.
- P3. A cc turn ends cleanly on the client: the working placeholder clears and Send replaces Stop.
- P4. Operator-CLI-only plugin Stop hooks do not steer end-user Concierge sessions, and adding a new Stop hook
  forces an explicit web classification.

**Cut List.**
- Widen or re-tune `unkept-promise-hook.sh` regexes so a question list stops matching -> buys P1 only for that
  phrasing; the hook's own header (§KNOWN RESIDUALS 0/1) states widening cannot be complete; the env opt-out
  buys P4 for every phrasing -> CUT.
- Rewrite `CRM_LEAD_DIRECTIVE` to avoid closing on "I'll show you a review" -> prompt-tuning around a hook that
  must not run here; leaves every other Concierge closing exposed -> CUT (the directive stays unchanged).
- Emit `session_ended{turn_complete}` from the cc path (`onTextTurnEnd`) -> `clear_streams` also resets
  `workflow` and `spawnIndex` (ws-client `case "clear_streams"`), i.e. it would blank the sticky workflow
  lifecycle bar after every cc turn; a `stream_end`-scoped client idle transition buys P3 without that -> CUT.
- Server-side "accumulate instead of replace" text semantics -> changes W8 for every multi-block turn, far
  beyond this bug; markup-only blocks are dropped instead -> CUT.
- SDK `disableAllHooks` (a `Settings` key, sdk.d.ts ~7105: "Disable all hooks and statusLine execution: the hooks
  defined in settings files and by installed plugins") -> all-or-nothing: it would also disable the plugin's
  `PreToolUse` security guard `browser-snapshot-credential-guard.sh` (`hooks.json` `PreToolUse[0]`), trading a
  leak for a lost guard; the per-hook env opt-out disables exactly one hook -> CUT.
- A new ADR -> the decision extends ADR-093's boundary (what the platform-deployed plugin may execute in web
  sessions); amend ADR-093 rather than mint an ordinal -> CUT (amendment instead).
- `soleur:engineering:discovery:functional-discovery` overlap check -> internal first-party runtime defect, no
  registry-equivalent capability to compare; skipped deliberately.

**Deepen-pass evidence (verified live 2026-09-30, SDK 0.3.284 pinned in `apps/web-platform/package.json`).**

```text
# apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts
5529  export declare type SdkPluginConfig = {
5539     * When true, the engine loads skills/hooks/agents/commands from this plugin but does NOT read its .mcp.json ...
        (the `skipMcpDiscovery` doc — by contrast a plain { type:'local', path } binding loads the plugin's hooks)
2229-2238  settingSources?: ... 'user' | 'project' | 'local' ... Pass `[]` to disable filesystem settings (SDK isolation mode).
        (filesystem settings only — plugin hooks.json is not a settings source)
1638-1644  env?: "Environment variables for the Claude Code process. When set, this value REPLACES the subprocess
           environment entirely — it is not merged with process.env."
```

```text
$ jq '[.hooks.Stop[].hooks[].command]' plugins/soleur/hooks/hooks.json
[ ".../hooks/stop-hook.sh", ".../hooks/browser-cleanup-hook.sh", ".../hooks/unkept-promise-hook.sh" ]   # 3 Stop hooks
$ grep -nE "^MIN_(INVOCATIONS|SUT_RUNS|EXPECT_ROWS|ASSERTIONS)=" plugins/soleur/test/unkept-promise-hook.test.sh
367:MIN_INVOCATIONS=51  370:MIN_SUT_RUNS=51  395:MIN_EXPECT_ROWS=51  404:MIN_ASSERTIONS=62
$ git grep -n "state.events.onTextTurnEnd" -- apps/web-platform/server
apps/web-platform/server/soleur-go-runner.ts:2395   # exactly one call site (handleResultMessage)
```

`SdkPluginConfig`'s `skipMcpDiscovery` doc is the only place the typings name hooks as part of a plugin load;
combined with the incident itself (the hook demonstrably ran) it is sufficient for root-cause claim 1. The
`env` doc says the value goes to "the Claude Code process"; hook commands are that process's children, which is
the standard CLI behaviour — but no typing sentence states it for hooks, so Phase 1 step 4 stays a measurement.
Live ID checks: rule IDs cited in this plan all exist as active rules; issues #3243, #3242, #3374, #3280, #9281
are OPEN and #9281 is the `browser-cleanup-hook.sh` filing.

**Institutional learnings applied** (`knowledge-base/project/learnings/`):
`2026-05-04-cc-soleur-go-cutover-dropped-document-context-and-stream-end.md` (the cc path already lost a
per-turn signal once; `stream_end` is the cc turn boundary),
`2026-04-13-websocket-cumulative-vs-delta-streaming-fix.md` (partial:true is cumulative, replace not append),
`2026-05-06-new-prompt-injection-site-needs-sanitization-parity.md` (audit every site when adding a
sanitizer), `2026-03-20-bare-repo-plugin-hook-sync-gap.md`. Rules in play:
`hr-write-boundary-sentinel-sweep-all-write-sites`, `cq-silent-fallback-must-mirror-to-sentry`,
`cq-write-failing-tests-before`, `hr-weigh-every-decision-against-target-user-impact`.

**Adjacent finding (not fixed here, tracked).** `plugins/soleur/hooks/browser-cleanup-hook.sh` is also a
plugin Stop hook and therefore also runs in web sessions; it `pgrep -f 'chrome.*--remote-debugging-pipe'` and
`kill`s matches on the host. On a multi-tenant web host that could touch another session's Chrome. Recorded as
a `deferred` entry in the parity registry (Phase 4) tracked as #9281.

## Open Code-Review Overlap

Open `code-review` issues naming files this plan edits: #3243 and #3242 (`cc-dispatcher.ts`), #3374 and #3280
(`lib/ws-client.ts`). **Acknowledge, all four:** #3243 is a module-decomposition refactor, #3242 a tool_use wire
field, #3374 a `slot_reclaimed` frame, #3280 a history-fetch state-machine refactor — none is the stop-gate
leak, the text-replace semantics, or `streamState` idling; each remains open. None of the other planned files
have open scope-outs.

## Architecture Decision (ADR/C4)

The plan extends a trust/runtime boundary: the platform-deployed plugin (ADR-093) executes its **command
hooks** inside web sessions, and operator-CLI-oriented hooks must self-disable there through a
platform-injected env override. That is a new cross-cutting invariant (every future plugin Stop hook must be
classified), and the C4 model currently misdescribes the boundary.

### ADR
Amend `ADR-093-sdk-plugin-source-is-platform-deployed-not-connected-repo.md` via `soleur:architecture`: add
`### 2026-09-30 — plugin command hooks execute in web sessions; operator-CLI-only hooks self-disable via
platform env override (SOLEUR_DISABLE_UNKEPT_PROMISE_HOOK)` under `## Amendments`, plus an
`## Alternatives considered` row for each Cut-List item above (hook regex widening, directive rewrite,
cc `session_ended`, accumulate-text) plus two more: excluding hooks at the SDK plugin binding (per-hook exclusion
needs a second web-only `hooks.json` or a filtered plugin copy — deferred; spike whether the SDK exposes a hook
filter) and a single `SOLEUR_RUNTIME=web-concierge` tag read by operator-CLI hooks (better long-term shape than
one variable per hook; per-hook variables are kept because they double as operator kill switches). The amendment
also records the accepted trade-off of disabling the unkept-promise guard in web sessions and states the guard's
scope is the `Stop` event only. No new ordinal is minted, so no ordinal-collision sweep applies. This
is a task in Phase 5, not a follow-up issue.

### C4 views
All three model files were READ (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`):
- External human actor: the end user chatting with the Concierge — modeled already; no new actor.
- External system/vendor: none added (the Claude Agent SDK/CLI edge that runs the hook is already the
  `platform.plugin` / agent-runtime edge).
- Container/data store: none touched.
- Actor-to-surface relationship: unchanged.
- **Falsified description to fix:** `model.c4` `api` container ("API Routes") says
  `settingSources:[] isolates these from the CLI .claude/ shell Hook Engine`. That is true for
  `.claude/settings.json` hooks and **false for plugin `hooks.json` hooks**, which the `plugins:[{local}]`
  binding loads. Edit that sentence directly in `model.c4` to say plugin command hooks DO execute in web
  sessions and that operator-CLI-only ones self-disable via `SOLEUR_DISABLE_*` env overrides from
  `buildAgentEnv`. No `views.c4` change (no new element). After editing run
  `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and
  `plugins/soleur/test/c4-count-parity.test.sh` (the description embeds no derived cardinality; run it anyway).

### Sequencing
Decision is true as soon as Phase 1 lands; the amendment and the C4 edit ship in the same PR.

## User-Brand Impact

- **If this lands broken, the user experiences:** a paying user's first CRM lead entry answered with raw
  `<stop>OPERATOR-GATE:...</stop>` control text instead of the question list, then a chat that appears hung on
  "Still working..." with a Stop button — the flow cannot be completed from the UI.
- **If this leaks, the user's workflow is exposed via:** internal harness vocabulary ("OPERATOR-GATE", hook
  reasons) rendered in the chat bubble and persisted into the `messages` table; no credential or data exposure
  path was found (the markup carries model prose, not secrets).
- **Brand-survival threshold:** `aggregate pattern`

Every Concierge turn whose closing sentence trips the operator hook (any "I'll ...", "Let me ...", bare
gerund without a trailing `?`) is exposed, so this is a pattern across users rather than a single-user data
incident. No `requires_cpo_signoff`. The diff touches `apps/web-platform/server/**` (a sensitive path per
preflight Check 6), and the threshold is not `none`, so no scope-out bullet is needed.

## Observability

```yaml
liveness_signal:
  what: Sentry warning event tagged feature=soleur-go-runner op=stop-gate-markup-stripped, emitted each time the runner removes stop-gate markup from an assistant text block (zero events is the healthy steady state once the env opt-out is live; any event means a hook or model still produced the markup and the boundary caught it)
  cadence: per occurrence
  alert_target: Sentry event stream, searchable by the op tag (no new alert rule is created by this change; a rule can be added later without a code change)
  configured_in: apps/web-platform/server/soleur-go-runner.ts (handleAssistantMessage, via warnSilentFallback from apps/web-platform/server/observability.ts)
error_reporting:
  destination: Sentry web-platform project via the existing SENTRY_DSN (server/observability.ts warnSilentFallback); no message body is attached, only conversationId, markupOnly boolean and stripped-byte count
  fail_loud: warning-level Sentry event with searchable tags feature and op; the user sees the preserved question list rather than an error
failure_modes:
  - mode: operator Stop hook still runs in the web runtime (env override missing from a new env-construction path)
    detection: parity test plugin-stop-hooks-web-parity.test.ts fails in CI; in production the stop-gate-markup-stripped Sentry op fires
    alert_route: CI red on the PR; Sentry event search on op:stop-gate-markup-stripped
  - mode: markup variant the strip regex does not recognise reaches the client (for example a differently-cased or attribute-bearing tag)
    detection: unit table in stop-gate-markup.test.ts covers case, attributes, unterminated tag, multiple tags; a residual leaks to the debug stream only, and the same op fires whenever any variant is caught
    alert_route: Sentry event search on op:stop-gate-markup-stripped (first-seen variant shows in event extra as the tag shape, never the body)
  - mode: client never leaves streaming after a cc turn (turn-end signal regression)
    detection: chat-reducer wire-sequence test (stream then stream_end -> idle) and the Playwright WS-injector e2e assert Send returns; runtime symptom is the existing stuck-watchdog path
    alert_route: CI red on the PR
logs:
  where: pino server logs of the web-platform container plus the Sentry event stream (no SSH needed to read either)
  retention: Sentry project retention; container log retention per the existing web-platform logging configuration
discoverability_test:
  command: grep -o stop-gate-markup-stripped apps/web-platform/server/soleur-go-runner.ts
  expected_output: stop-gate-markup-stripped
```

Affected-surface note (Phase 2.9.2): the sandboxed agent/CLI process is a blind surface, so the in-surface probe
for the hook is behavioural — the parity test spawns the real hook script under the exact env
`buildAgentEnv` produces, and the runner boundary emits its own event from the server side of the same turn.

## Implementation Phases

Write every test first and watch it fail (`cq-write-failing-tests-before`); the commands below run from
`apps/web-platform/` unless stated.

### Phase 1 — root cause: the web runtime must not run the operator guard

1. RED, hook suite (`plugins/soleur/test/unkept-promise-hook.test.sh`): add rows built from the real closing
   in the incident (the four-bullet CRM question list ending "I'll show you a review before saving, and that
   review is the only confirmation step.") plus one differently-phrased promise (`"Implementing the lead form
   now."`). Rows: BLOCK without the env var (must stay BLOCK — the CLI behaviour is unchanged); ALLOW with
   `SOLEUR_DISABLE_UNKEPT_PROMISE_HOOK=1`; ALLOW with the var and `stop_hook_active` absent. Extend `verdict()`
   to accept an env prefix (it currently only takes extra JSON), and raise `MIN_INVOCATIONS`, `MIN_SUT_RUNS`,
   `MIN_EXPECT_ROWS` and `MIN_ASSERTIONS` (currently 51/51/51/62) by exactly the rows added (state the +N per floor in
   the commit message) — the suite's own floors `exit 1` otherwise. Drop the redundant
   "var set and `stop_hook_active` absent" row: the BLOCK-without / ALLOW-with pair suffices.
2. RED, env (`test/agent-env.test.ts`): `buildAgentEnv(...)` returns `SOLEUR_DISABLE_UNKEPT_PROMISE_HOOK === "1"`
   for both `api_key` and `oauth` schemes and with `process.env.SOLEUR_DISABLE_UNKEPT_PROMISE_HOOK` set to `"0"`
   (an ambient value must not override it — it rides `AGENT_ENV_OVERRIDES`, not the allowlist).
3. GREEN: in `plugins/soleur/hooks/unkept-promise-hook.sh`, immediately after the `SOLEUR_HOOK_TRACE` line and
   before the `jq` fail-open, add
   `[[ "${SOLEUR_DISABLE_UNKEPT_PROMISE_HOOK:-0}" == "1" ]] && exit 0` (mirrors
   `compaction-state.sh`'s `SOLEUR_DISABLE_COMPACTION_HOOKS`), with a header paragraph naming the web runtime
   as the reason and adding a KNOWN RESIDUAL entry ("this hook is operator-CLI vocabulary; web sessions opt
   out — accepted trade-off: the hook's header says it matters more for non-technical users, but its block
   reason instructs the model in operator vocabulary a chat user must never see, and the unkept-promise
   class in web is left to the Concierge system prompt"). Add a comment that the switch's position AFTER the
   `SOLEUR_HOOK_TRACE` line and BEFORE the `jq` fail-open is load-bearing: the suite counts executions through
   that stderr marker. In `apps/web-platform/server/agent-env.ts` add the key to `AGENT_ENV_OVERRIDES` with a comment citing
   ADR-093's amendment. `buildAgentQueryOptions` is the single env-construction chokepoint for both runners
   (legacy `agent-runner.ts` and cc), so both are covered.

4. Verification that the hook subprocess really inherits the SDK `env` option (no unit test proves the CLI
   forwards `options.env` to plugin command hooks): precedent is `compaction-state.sh` reading its
   `SOLEUR_DISABLE_COMPACTION_HOOKS` under the same loader, but precedent is not measurement. During `soleur:qa`
   on a dev dispatch, send the CRM prompt from the incident and confirm the Debug stream shows one assistant
   text (the list) and no second `<stop>` message; record the observation in the PR body. If the hook still
   fires, the env is not forwarded and the fix moves to a hook-side runtime marker (for example the Stop
   payload's `cwd` under the workspace root) — re-plan; do not stack Phase 2 on an unverified Phase 1.

### Phase 2 — defence in depth: gate markup never renders, and never replaces the question list

1. RED, unit (`test/stop-gate-markup.test.ts`): table for `stripStopGateMarkup(text)` ->
   `{ text, hadMarkup, markupOnly }`: sentinel-only block (the incident text) -> `markupOnly: true`, empty
   text; markup embedded in prose (before, after, between) -> prose preserved, tag removed; `<STOP>`, `<stop
   reason="x">`, multi-line body, two tags; unterminated `<stop>OPERATOR-GATE: ...` -> truncated at the tag;
   no markup -> input returned by identity with `hadMarkup: false`; lookalikes that must NOT be stripped
   (`<stopwatch>`, the word "stop", a fenced code sample is out of scope and documented as such).
2. RED, runner (`test/soleur-go-runner-stop-gate.test.ts`, modelled on `soleur-go-runner.test.ts`
   `createMockQuery`/`makeAssistant`/`makeResult`): script `assistant(question list)`, `assistant(the
   incident's <stop>OPERATOR-GATE...</stop>)`, `result`. Assert `onText` is called exactly once with the list,
   is never called with a string containing `<stop`, and `onTextTurnEnd` still fires once. Second case:
   markup embedded in a prose block -> `onText` receives the prose without the tag. Third: a markup-only
   *first* block of a turn -> `onText` not called, no empty bubble, and **no empty assistant row persisted**
   (`consumeForComplete()` currently returns `{text: ""}` and `saveAssistantMessage` would write it — guard the
   save in `cc-dispatcher.ts` `onTextTurnEnd` on non-empty text and add a dispatcher test). Fourth (accepted
   limit, asserted as a negative control): a later *prose* block still replaces the list (W8 replace
   semantics) — P1 is guaranteed for markup-only blocks, not for arbitrary later prose.
3. GREEN: new `apps/web-platform/server/stop-gate-markup.ts` (pure, no imports from `@/server/*` logging so it
   is unit-testable) and call it at the single cc text chokepoint, `handleAssistantMessage` in
   `server/soleur-go-runner.ts` (the `b.type === "text"` arm, before the chapter-prefix logic and `onText`).
   `markupOnly` -> skip `onText` entirely (the previous block's text stays the visible/persisted reply);
   otherwise pass the stripped text. When `hadMarkup`, call `warnSilentFallback(null, { feature:
   "soleur-go-runner", op: "stop-gate-markup-stripped", extra: { conversationId, markupOnly, strippedBytes } })`
   — never the body; add `warnSilentFallback` to the existing `import { reportSilentFallback, mirrorWithDebounce } from "./observability"` line (`null` routes to `captureMessage`; assert that path and the `extra` keys in the runner test) (`cq-silent-fallback-must-mirror-to-sentry`; Sentry-value PII discipline as in
   `debug-event.ts`).
4. Sweep of write sites (`hr-write-boundary-sentinel-sweep-all-write-sites`), decided per site:
   - cc `onText` -> persisted `consumeForComplete()` row: covered (both consume the runner's output).
   - Debug stream `emitDebugEvent(kind:"reasoning")` in `cc-dispatcher.ts` `onText`: markup-only blocks no
     longer reach it either; this is acceptable and intended (debug stream is an internal view, but the
     dropped block is reported via Sentry).
   - Legacy `agent-runner.ts` (partial `stream` at the `lastBlock.type === "text"` arm, final block `stream`,
     and `fullText` persistence): **Acknowledged, not edited.** It receives cumulative partials character by
     character, so complete-tag stripping is unsound without buffering; Phase 1's env override removes its
     source (same `buildAgentQueryOptions` chokepoint). Recorded in the ADR-093 amendment as a residual.
   - Comment in `stop-gate-markup.ts`: harness vocabulary hard-coded in the server, removable once the parity guard has run clean for several releases — it must not grow into a permanent tag allowlist.
   - Support persona (`mode.cwdSource === "plugin"`) uses the same runner and query options: covered.

### Phase 3 — the turn ends cleanly on the client

0. Before writing any code, grep the existing reducer, `useWebSocket-abort` and cc e2e tests for an assertion that
   Send returns after `stream_end` (the repo's own comments claim `streamState` "leaves streaming on every
   turn-end path"). If one exists, the bug is a frame after `stream_end`, not a missing transition — go straight to
   the stop condition below.
1. **Wire-sequence characterization test first** (`test/cc-turn-end-wire.test.ts`): use the existing
   `__setCcRunnerForTests` seam (see `test/cc-dispatcher.test.ts` `driveWorktreeEnterFailed`) with a stub
   runner whose `dispatch` invokes `args.events.onText(list)`, `onResult({...})`, `onTextTurnEnd()`; capture the
   `sendToClient` frames; fold them through the real `chatReducer` (`lib/ws-client.ts`) starting from the idle
   `ChatState`. Assert: one assistant bubble whose content is the list and whose `state` is `"done"`, and
   `streamState === "idle"`. Expected today: `streamState` is `"streaming"` (measured 2026-09-30 with the
   reducer alone: `stream`, `stream_end` -> `streaming`).
   **Stop condition:** if this test already passes (an idle path exists that the code reading missed), do NOT
   change the reducer. Re-run the same harness with the incident's exact frame sequence including any
   post-`stream_end` `tool_progress`/`stream`/`stream_start` frame and the debug frames, find the frame that
   re-enters `streaming`, and fix that frame's handling instead; update this plan's root-cause item 4.
2. RED, reducer rows in `test/chat-reducer.test.ts`: `stream_end` for `CC_ROUTER_LEADER_ID` with no remaining
   active stream and `streamState === "streaming"` -> `"idle"`; `"stopping"` stays `"stopping"` (only
   `session_ended:user_aborted` releases it); a `stream_end` for a legacy leader id while another leader's
   stream is still active leaves `"streaming"`; `workflow` and `spawnIndex` are untouched (this is what
   distinguishes it from `clear_streams`); a `review_gate` earlier in the turn does not break the transition; `tool_use` -> `stream_end` -> `stream` (a
   text/tool/text turn) leaves no Send flicker mid-turn — `onTextTurnEnd` fires only from `handleResultMessage`
   (one call site), so `stream_end` marks the turn boundary, not a block boundary; assert that with the row.
3. GREEN: in `chatReducer`'s `stream_event` arm (`lib/ws-client.ts`), compute `nextStreamState` so that
   `action.msg.type === "stream_end"` with `leaderId === CC_ROUTER_LEADER_ID`,
   `result.activeStreams.size === 0` and `state.streamState === "streaming"` yields `"idle"`. Import
   `CC_ROUTER_LEADER_ID` from the client-safe `@/lib/cc-router-id` (never `@/server/*`). Update the
   `StreamState` doc-comment and the `ChatState.streamState` comment (now `stream_end` for the cc leader is a
   fifth transition site), and re-verify the three-pattern union grep if the union changes (it does not).
4. e2e (existing `e2e/cc-soleur-go-bubbles.e2e.ts` + `cc-soleur-go-ws-injector.ts`): inject `stream(list)` +
   `stream_end` and assert the composer shows Send (not Stop) and `[data-testid="live-narration"]` is absent.

### Phase 4 — parity guard so the next operator-only Stop hook cannot leak

Detailed in `## Guard Contract`. New `test/plugin-stop-hooks-web-parity.test.ts`; registry lives in the test.
Classification of today's three Stop hooks: `stop-hook.sh` (ralph loop) = `web-safe` (it acts only on
`.claude/ralph-loop.<PPID>.local.md` state files a web workspace never has; the test spawns it in a fresh temp git
repo and expects exit 0 with no `decision:block`); `unkept-promise-hook.sh` = `web-disabled`;
`browser-cleanup-hook.sh` = `deferred` #9281. The test **fails (never skips)** when `bash` or `jq` is missing,
and takes the opt-out variable name from the `web-disabled` registry field rather than a hard-coded literal, so a
later move to a single runtime tag only edits the registry. The `SessionStart`/`PreCompact` hooks are out of this
guard's scope by design; a follow-up issue covers them (see Dependencies & Risks).
The `browser-cleanup-hook.sh` registry entry is `deferred` and cites #9281 (already filed).

### Phase 5 — records

Amend ADR-093 (Alternatives + Amendment), fix the `model.c4` description, run the three C4 tests. At
`soleur:ship`/compound time capture the learning: "plugin Stop hooks run in web sessions;
`settingSources:[]` does not isolate them".

## Files to Edit

- `plugins/soleur/hooks/unkept-promise-hook.sh` — env opt-out + header residual.
- `plugins/soleur/test/unkept-promise-hook.test.sh` — new rows, env-aware `verdict()`, raised floors.
- `apps/web-platform/server/agent-env.ts` — `AGENT_ENV_OVERRIDES` entry.
- `apps/web-platform/test/agent-env.test.ts` — override assertions.
- `apps/web-platform/server/soleur-go-runner.ts` — strip at `handleAssistantMessage` text arm; import
  `warnSilentFallback`.
- `apps/web-platform/lib/ws-client.ts` — `chatReducer` `stream_event` arm idle transition; comments.
- `apps/web-platform/test/chat-reducer.test.ts` — new rows.
- `apps/web-platform/e2e/cc-soleur-go-bubbles.e2e.ts` — turn-end Send/Stop assertion.
- `knowledge-base/engineering/architecture/decisions/ADR-093-sdk-plugin-source-is-platform-deployed-not-connected-repo.md` — amendment.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `api` container description.

## Files to Create

- `apps/web-platform/server/stop-gate-markup.ts`
- `apps/web-platform/test/stop-gate-markup.test.ts`
- `apps/web-platform/test/soleur-go-runner-stop-gate.test.ts`
- `apps/web-platform/test/cc-turn-end-wire.test.ts`
- `apps/web-platform/test/plugin-stop-hooks-web-parity.test.ts`
- `knowledge-base/project/specs/feat-one-shot-crm-lead-stop-gate-leak/tasks.md`

Path verification (`hr-when-a-plan-specifies-relative-paths-e-g`): every "Files to Edit" path was confirmed
present on this branch (`git ls-files`); every "Files to Create" path's parent directory exists; no globs are
prescribed.

## Guard Contract

### Guard 1 — plugin Stop hooks are classified for the web runtime

**Property.** Every Stop hook registered in `plugins/soleur/hooks/hooks.json` is explicitly classified for the
web runtime (`web-safe`, `web-disabled`, or `deferred` with an issue number), and no hook classified `web-safe`
blocks the incident's closing message while every hook classified `web-disabled` allows it under the exact env
`buildAgentEnv` produces.

**Assembly.** The population is derived, not listed: `.hooks.Stop[].hooks[].command` parsed from
`plugins/soleur/hooks/hooks.json` (three entries today, but the test asserts the parsed count is >= 1 and that
every registry key matches a parsed entry, so a stale or emptied registry fails). The chokepoints the property
flows through: (1) the registry in the test, (2) `AGENT_ENV_OVERRIDES` in `server/agent-env.ts` — the only env
builder, reached by both runners through `buildAgentQueryOptions`, (3) each hook script's early exit. Scoped
to the `Stop` event because it is the only event that can force an extra model turn and rewrite the visible
reply; the `SessionStart`/`PreCompact` command hooks (`compaction-state.sh`, `welcome-hook.sh`, the Devin/Codex
starters) inject context to the model rather than replacing user-visible text and are not classified here —
that boundary is stated in the ADR-093 amendment so the scope is not read as "all hooks".

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a fourth Stop hook entry to `hooks.json` with no registry classification | RED |
| 2 | Delete `SOLEUR_DISABLE_UNKEPT_PROMISE_HOOK` from `AGENT_ENV_OVERRIDES` | RED |
| 3 | Delete the early-exit line from `unkept-promise-hook.sh` | RED |
| 4 | Point the test at an empty/renamed `hooks.json` (parsed Stop count 0) so the loop iterates nothing | RED |
| 5 | Classify a second hook `web-disabled` whose script has no early exit, after the compliant first | RED |
| 6 | Reclassify `unkept-promise-hook.sh` as `web-safe` in the registry (label weakened, behaviour unchanged) | RED |

**Harness rows.** RED: remove the behavioural spawn from the test (registry-only assertions) — the suite must
fail its own floor that counts hook-side `SOLEUR_HOOK_RAN` markers (the hook writes it to stderr on entry, so a
harness that never spawns it cannot satisfy the floor). Must-PASS non-canonical input: the spawn fixture set
includes a differently-phrased blocked closing ("Implementing the lead form now.") in addition to the
incident's CRM list, so a hook that allows everything for one memorised string is not enough, and a
web-disabled hook is proven by ALLOW on both while the same hook without the env is proven by BLOCK on both.

**Anchor.** The registry label alone proves consistency, not integrity: a diff can flip a label and the script
together. The independent anchor is behaviour — `web-safe` entries are spawned with NO opt-out env and must not
block the incident closing (row 6 goes RED because `unkept-promise-hook.sh` does block it), and `web-disabled`
entries are spawned WITH `buildAgentEnv`'s real env (imported, not re-typed). `deferred` entries must cite
`#<number>` and are not spawned (the browser-cleanup hook has host-level side effects).

## Acceptance Criteria

### Functional

- [ ] Piping the incident's CRM question-list closing into `unkept-promise-hook.sh` with
  `SOLEUR_DISABLE_UNKEPT_PROMISE_HOOK=1` produces no `decision:block`; without the var it still blocks
  (`bash plugins/soleur/test/unkept-promise-hook.test.sh` green, floors raised).
- [ ] `buildAgentEnv` always sets `SOLEUR_DISABLE_UNKEPT_PROMISE_HOOK=1` regardless of ambient env
  (`agent-env.ts` `AGENT_ENV_OVERRIDES`; `test/agent-env.test.ts`).
- [ ] Given assistant(list), assistant(`<stop>OPERATOR-GATE...</stop>`), result, the runner calls `onText` once
  with the list and never with `<stop` (`soleur-go-runner.ts` `handleAssistantMessage`;
  `test/soleur-go-runner-stop-gate.test.ts`), and the persisted row text is the list.
- [ ] `stripStopGateMarkup` passes its table including unterminated, multi-tag, case and attribute variants and
  the `<stopwatch>` non-match (`test/stop-gate-markup.test.ts`).
- [ ] After a cc turn's `stream` + `stream_end`, `streamState` is `"idle"`, `workflow`/`spawnIndex` unchanged,
  and `"stopping"` is preserved (`lib/ws-client.ts` `chatReducer`; `test/chat-reducer.test.ts`,
  `test/cc-turn-end-wire.test.ts`), or Phase 3's stop condition was followed and the plan's root-cause item 4
  updated.
- [ ] `test/plugin-stop-hooks-web-parity.test.ts` passes; the PR body attests each of the six mutation-matrix
  rows was demonstrated RED against a scratch copy (an attestation, not a CI check).

### Non-functional / quality gates

- [ ] Sentry event `op:stop-gate-markup-stripped` carries no message body (assert the `extra` keys in the runner
  test).
- [ ] ADR-093 amended (Amendment + Alternatives rows); `model.c4` `api` description corrected; the three C4
  tests are green.
- [ ] `stop-hook.sh` is registered `web-safe` and spawned in a temp git repo; `browser-cleanup-hook.sh` is registered `deferred` citing #9281 (filed 2026-09-30).
- [ ] `tsc --noEmit`, `npx vitest run` for the touched files, and `bash plugins/soleur/test/c4-count-parity.test.sh`
  are green. PR body uses `Closes` only if an issue is opened for this bug (none cited today).

## Test Scenarios

- Incident replay (runner level): list, stop-tag, result -> visible text is the list.
- Incident replay (client level): frames fold through `chatReducer` to one done bubble and `idle`.
- Hook, CLI behaviour preserved: same closing without the env var still BLOCKs (proves the opt-out did not
  neuter the operator guard).
- Multi-leader legacy stream: `stream_end` for a non-cc leader with another leader mid-stream does not idle.
- Stop clicked mid-turn: `stopping` survives a late `stream_end` until `session_ended:user_aborted`.
- Markup-only first block: no empty bubble, no `onText`.
- Parity guard: adding an unclassified Stop hook fails CI.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — engineering-only bug fix on existing surfaces (an existing chat
bubble's text and an existing spinner). The mechanical UI-surface override was checked: no path under
`components/**/*.tsx`, `app/**/page.tsx` or `app/**/layout.tsx` is created or edited (`lib/ws-client.ts` is
client state logic, not a rendered surface), so the Product/UX gate is NONE and no wireframe is required
(`wg-ui-feature-requires-pen-wireframe` does not apply). GDPR gate: no schema, migration, auth flow, API route
or `.sql` file is touched and no new processing of user data is introduced (the Sentry event carries no body),
so `soleur:gdpr-gate` is skipped. No new infrastructure, store or network connection: IaC and encryption-posture
gates do not fire.

## Dependencies & Risks

- **Risk: the idle fix is redundant or misplaced** (root-cause item 4 is partly hypothesis). Mitigated by the
  Phase 3 stop condition: the wire test either fails (fix stands) or passes (re-diagnose with the incident's
  full frame order; never ship a reducer change the test did not demand).
- **Risk: env override name drifts from the hook's read.** Mitigated by the behavioural spawn using the env
  `buildAgentEnv` returns, not a retyped literal.
- **Risk: stripping hides a genuine block reason the model wanted to tell the user.** The only producer of the
  markup is the hook's operator-CLI instruction; with Phase 1 the model has no such instruction. The Sentry op
  makes any recurrence visible.
- **Risk: the unkept-promise suite's floors.** Adding rows without raising `MIN_*` is safe but weakens the
  floors; forgetting the env-aware `verdict()` fails the suite's own SUT-marker conservation check. Both are
  in Phase 1 step 1.
- **Follow-ups filed at work time (one issue each, `Mandated-By: wg-when-deferring-a-capability-create-a`):** (a) classify the non-Stop plugin command hooks (`SessionStart`, `PreCompact`, `PreToolUse`) for the web runtime; (b) evaluate `SOLEUR_RUNTIME` / a plugin-surface split as the classification axis.
- **Not in scope:** the W8 replace semantics for multi-block turns; `compaction-state.sh` `/clear` guidance
  reaching web users (model-visible context only, same class as #9281; note it there when work starts);
  rewording `CRM_LEAD_DIRECTIVE`.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty or omits the threshold fails `deepen-plan` Phase 4.6 — filled
  here (`aggregate pattern`).
- `settingSources: []` isolates `.claude/settings.json` only. Any statement that web sessions are isolated from
  hooks must name which hook registry it means; plugin `hooks.json` is loaded through `plugins:[...]`.
- `chatReducer`'s `clear_streams` is NOT a turn-end: it resets `workflow` and `spawnIndex`. Do not "simplify"
  Phase 3 into dispatching it from `stream_end`.
- The unkept-promise suite counts hook executions through a hook-written stderr marker; a new row that spawns
  the hook outside `verdict()` must also append to `SOLEUR_HOOK_TRACE` or the conservation check trips.
- `recordAssistantBlock(state, "text", null)` (soleur-go-runner.ts, first statement of the text arm) MUST stay ahead of the strip: it re-arms the per-block runaway watchdog, and a markup-only block is still evidence the model is alive. Skipping `onText` must not skip the re-arm.
- The strip must run before the chapter-prefix logic in `handleAssistantMessage`, otherwise a markup-only block
  would consume `prefixEmitted` and drop the routing prefix from the next real block.

## References

- Hook: `plugins/soleur/hooks/unkept-promise-hook.sh`, `plugins/soleur/hooks/hooks.json`
- Web binding: `apps/web-platform/server/agent-runner-query-options.ts` (`plugins:[{type:"local"}]`,
  `settingSources: []`), `apps/web-platform/server/agent-env.ts`
- Text path: `server/soleur-go-runner.ts` (`handleAssistantMessage`, `handleResultMessage`),
  `server/cc-dispatcher.ts` (`onText`, `onTextTurnEnd`, `TurnPersistenceState`)
- Client: `lib/ws-client.ts` (`chatReducer`), `lib/chat-state-machine.ts` (`case "stream"`, `case "stream_end"`),
  `components/chat/chat-surface.tsx` (live-narration slot)
- ADR-093, `knowledge-base/engineering/architecture/diagrams/model.c4`
- Evidence screenshot: `/tmp/claude-1000/-data-git-repositories-jikig-ai-soleur/55923a7f-7fd9-4618-bb76-2d4332e1b386/images/1.png`
