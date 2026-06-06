---
title: "Hide per-command Approve/Deny cards in Concierge; stream commands + output into the message box"
date: 2026-06-04
type: feat
status: draft
branch: feat-one-shot-concierge-stream-commands-hide-approval-cards
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: TBD
---

# feat: Stream Concierge commands + output into the message box (hide per-command Approve/Deny cards)

## Enhancement Summary

**Deepened on:** 2026-06-04
**Sections enhanced:** Overview, Research Reconciliation, Domain Review (UX gate tier corrected), Files to Create (wireframe), Research Insights (new).
**Research agents used:** inline (Task tool unavailable in this environment — confirmed via ToolSearch + learning `2026-05-05-cc-permissions-bash-allowlist-hardening.md` §SE#4). All gate verifications run as direct greps/`gh` calls.

### Key Improvements
1. **UX gate corrected ADVISORY → BLOCKING** and a `.pen` wireframe was produced + committed (`knowledge-base/product/design/command-center/concierge-streamed-commands.pen`) — the inline streamed-terminal block is a new visible UI surface, not a copy tweak.
2. **Redaction reuse confirmed with a live precedent-diff:** `redactGithubSourcedText` is already applied at BOTH an emit/INSERT boundary (`insert-draft-card.ts:78`) and render-time (`today-card.tsx:246`) — the exact dual-gate pattern this plan prescribes. The plan extends (not reinvents) it for `GH_TOKEN=`/`Authorization:` (verified absent from the module).
3. **Verify-the-negative confirmed** the load-bearing architectural claim: tool *output* has NO existing server→client path today (grep returned zero emit sites). "Stream output" is correctly scoped as net-new `command_stream` plumbing, not a UI-only tweak.

### New Considerations Discovered
- **Output is its own redaction surface** (not just the command): `env`/`printenv`/`cat .git/config` echo secrets in stdout. Redaction must run on the `output` payload at the emit boundary, mirrored to Sentry on fallthrough. (Folded into Phase 2 + Observability.)
- **#3345 is OPEN and superseded-in-direction** (live-verified). Its Option (b) intent-card direction contradicts this plan's Option (a); AC11 closes it post-merge.
- **The leak is reproduced in code:** `permission-callback.ts:459-460` places the raw `command` (token included) into the `review_gate` question — the screenshot leak's exact origin.

> ✨ **Goal.** Running commands in the Soleur Concierge no longer spams separate
> Approve/Deny cards. Instead the commands **and their output** append live into
> the Soleur Concierge message bubble (cc_router leader) — Claude-Code-terminal
> style — with **secrets redacted** and the **`BLOCKED_BASH_PATTERNS` auto-deny
> guardrail intact**.

## Overview

Today, every Bash tool-use in the Concierge can produce **two** card surfaces and
**zero** command output:

1. **`review_gate`** (authoritative gate) — `apps/web-platform/server/permission-callback.ts`
   Bash branch (verified: lines 303–549). Renders `ReviewGateCard`
   (`components/chat/review-gate-card.tsx`), wired in `chat-surface.tsx` `case "review_gate"`
   (verified: lines 631–645). The question string embeds the raw command
   (`permission-callback.ts:459–460`: `const preview = command.slice(0,200); question = "Run Bash command?\n\n\`${preview}\`"`).
   **This is where the `curl … ghs_<token>` leak in the screenshots came from** — the
   raw command (including the installation token) is placed on the wire verbatim.
2. **`interactive_prompt` kind `bash_approval`** (informational, does NOT gate) —
   emitted by `soleur-go-runner.ts` `classifyInteractiveTool` (verified: lines 614–628,
   `return { kind: "bash_approval", payload: { command, cwd, gated: true } }`), bridged via
   `bridgeInteractivePromptIfApplicable` (line 1505). Renders `BashApprovalCard`
   (`interactive-prompt-card.tsx:358–412`, shows `<pre>{payload.command}</pre>` + `cwd:`),
   wired in `chat-surface.tsx` `case "bash_approval"` (verified: lines 85–96, 660–669).
   **This `<pre>` ALSO renders the raw command including any token, with no redaction.**

**Key discovery (changes the plan shape from "build" to "wire").** The server-side
auto-approve behavior the user wants **already exists**: the `bashAutonomous` toggle
(`permission-callback.ts:405–422`) auto-approves **every NON-BLOCKED** Bash command
(skips the review-gate entirely), while `isBashCommandBlocked` stays authoritative
(deny on `curl|wget|ncat|nc|eval|sudo|sh -c|node -e|base64 -d|/dev/tcp` etc., lines
83–89/317–338). It is wired through `resolveBashAutonomous` (fail-closed `false`,
owner-only RPC) in `cc-dispatcher.ts:994/1229`. **So Option (a) — "auto-approve
non-blocked + stream visibly" — is mostly already built at the permission layer for
autonomous workspaces.** What is missing is the **UI half**: (i) suppress the two card
surfaces, (ii) stream the command + its output into the cc_router bubble, (iii) redact
secrets before they hit the wire.

**Second key discovery (this is net-new plumbing).** Tool **output** does NOT currently
reach the client at all. `onToolUse` → `buildToolUseWSMessage` emits only a redacted
*label* ("Working") as a `tool_use` WS message (`cc-dispatcher.ts:1856–1901`,
`tool-labels.ts:269`); the raw SDK tool name is deliberately withheld from the wire
(#2138 information-disclosure invariant). Tool **results** (`tool_use_result`) are seen
server-side only by `handleUserMessage` (`soleur-go-runner.ts:1891–1895`) for the
runaway-timer and the **content is discarded**. "Stream the output" therefore requires a
**new server→client channel** for command text + truncated output, plus a new client
reducer surface to append it.

This plan chooses **Option (a) with visible streaming + redaction, gated by the existing
`bashAutonomous` toggle** as the design spine, plus an explicit decision (see
Decision D1) on whether streaming applies only to autonomous workspaces or also to
non-autonomous ones.

### Direction confirmation (ambiguity gate)

The feature wants cards GONE + commands streaming. Two server postures are possible:
- **(a)** auto-approve non-blocked commands (like `bashAutonomous`) while streaming them
  visibly. **Cards gone, no gate.**
- **(b)** keep gating but consolidate to one less-intrusive surface. **Cards reshaped,
  gate stays** (this is what open issue **#3345** proposes — intent-shaped approval).

The screenshots + prose ("cards GONE", "append as they progress like Claude Code")
select **(a)**. The blocklist guardrail and redaction are preserved as the safety floor.
**#3345 is therefore superseded in direction** (see Open Code-Review Overlap). **CPO
sign-off is required** (threshold = single-user incident) to confirm (a) over (b) before
`/work` begins — this is the load-bearing product call.

## Premise Validation

Verified against the worktree tree (all citations from the feature prompt confirmed):
- All 8 cited files exist (`permission-callback.ts`, `soleur-go-runner.ts`,
  `review-gate-card.tsx`, `interactive-prompt-card.tsx`, `chat-surface.tsx`,
  `message-bubble.tsx`, `bash-autonomous-toggle.tsx`, `lib/types.ts`).
- `review_gate` Bash branch confirmed at `permission-callback.ts:303–549` (prompt said
  ~303–548). The raw-command leak into the gate question confirmed at `:459–460`.
- `interactive_prompt`/`bash_approval` classifier confirmed at `soleur-go-runner.ts:614–628`.
- `BashApprovalCard` confirmed at `interactive-prompt-card.tsx:358–412`.
- `bashAutonomous` auto-approve-non-blocked confirmed at `permission-callback.ts:405–422`;
  `BLOCKED_BASH_PATTERNS` + `isBashCommandBlocked` at `:83–89`; safe-bash allowlist at `:347–364`.
- `message-bubble.tsx` cc_router streaming/`tool_use`/`done` states confirmed (lines
  143, 172–176, 262–316).
- **Stale assumption corrected:** the prompt implies "stream output" is a UI-only change.
  Verified it is NOT — tool *output* never reaches the client today (see Overview second
  discovery). Plan scopes the new `command_stream` WS channel accordingly.
- **Reuse target found** (not in prompt): `lib/safety/redaction-allowlist.ts`
  `redactGithubSourcedText` already redacts `ghp_/gho_/ghu_/ghs_/ghr_`, `github_pat_`,
  Stripe/Anthropic/OpenAI/AWS/Slack keys, JWTs, emails/IPs, with the 3 PII-scrubber
  invariants (max-input bound, alphabet-aware, no `/g`+`.test()`). **Gap:** it does NOT
  cover `GH_TOKEN=<value>` assignments or `Authorization: Bearer <value>` header literals
  — both explicitly named in the feature's SECURITY DIMENSION. The plan extends it (TR4).

No external GitHub-issue premises to falsify beyond the overlap check below.

## Research Reconciliation — Spec vs. Codebase

| Spec/prompt claim | Codebase reality | Plan response |
|---|---|---|
| "Stream commands + output into the box" reads as UI-only | Tool output never reaches client; only a redacted "Working" label does (`buildToolUseWSMessage`) | Add a `command_stream` WS event (server) + reducer append (client) — TR2/TR5 |
| "review_gate ~303–548" | Confirmed `303–549` | No change |
| "redaction needed for ghs_/gho_/Authorization/GH_TOKEN=" | `redactGithubSourcedText` covers `ghs_/gho_`; misses `GH_TOKEN=` + `Authorization:` literals | Extend redaction module (TR4), reuse not reinvent |
| `bashAutonomous` "auto-approves every non-blocked bash" | Confirmed `permission-callback.ts:405–422`, owner-gated, fail-closed | Reuse as the auto-approve spine; do NOT add a parallel bypass |
| Two parallel card systems | Confirmed; `bash_approval` is informational-only (`gated: true` but never resolves execution) | Suppress BOTH (TR1, TR3) |

## User-Brand Impact

**If this lands broken, the user experiences:** the Concierge runs shell commands with
**no visible record** (cards suppressed but streaming broken) — an opaque code-execution
surface a non-technical operator cannot audit; OR a regression where a blocked command
(`curl … | sh`) slips the guardrail and executes.

**If this leaks, the user's credentials are exposed via:** an un-redacted command string
(installation token `ghs_…`, `GH_TOKEN=…`, `Authorization: Bearer …`) rendered into the
Concierge bubble and persisted in `messages` — exactly the screenshot leak this PR exists
to fix. A redaction miss is a credential-disclosure incident.

**Brand-survival threshold:** single-user incident. (One operator seeing another's — or
their own installation's — token in chat, or one un-gated `curl|sh`, is brand-damaging on
its own.) → `requires_cpo_signoff: true`; `user-impact-reviewer` runs at review time.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — no `bash_approval` card path.** `classifyInteractiveTool` (`soleur-go-runner.ts`)
  returns `null` for `toolName === "Bash"` (the `bash_approval` branch is removed or
  guarded off), AND `chat-surface.tsx` no longer reaches `case "bash_approval"` for Bash
  tool-uses. Verify: `grep -n 'kind: "bash_approval"' apps/web-platform/server/soleur-go-runner.ts`
  returns 0 emit sites (type/union may retain the variant for replay back-compat — see D3).
- [x] **AC2 — no raw-command `review_gate` for non-blocked Bash under streaming mode.**
  In the streaming posture (D1), the Bash branch of `permission-callback.ts` does NOT emit a
  `review_gate` with a raw-command question for non-blocked commands. Verify by unit test on
  `createCanUseTool`: a non-blocked Bash command under streaming-enabled deps returns
  `allow(...)` with **zero** `deps.sendToClient({type:"review_gate"})` calls.
- [x] **AC3 — blocklist guardrail intact.** `isBashCommandBlocked` still denies every
  `BLOCKED_BASH_PATTERNS` member regardless of streaming/autonomous state. Verify: existing
  `permission-callback` deny tests still pass AND a new test asserts a blocked command returns
  `behavior: "deny"` even when streaming deps are wired.
- [x] **AC4 — command text is redacted before it reaches the wire.** A Bash command containing
  `ghs_<30+>`, `gho_<…>`, `GH_TOKEN=<…>`, and `Authorization: Bearer <…>` emits a
  `command_stream` event whose `command` field contains `[redacted-key]`/`[redacted-token]`
  and **none** of the literal secret substrings. Verify: redaction unit test over the extended
  module (TR4) asserts all four shapes are replaced; integration test asserts the WS payload
  carries no secret.
- [x] **AC5 — output streams + appends.** A Bash tool-use produces ≥1 `command_stream` event
  carrying the command, then ≥1 event carrying (truncated, redacted) stdout/stderr; the client
  reducer appends them into the cc_router bubble in order. Verify: reducer unit test
  (`chat-state-machine`) over a `command_stream` event sequence asserts ordered append into the
  cc_router message; component test renders the appended terminal block.
- [x] **AC6 — output is bounded.** `command_stream` output payload is capped (per-chunk byte
  cap + per-command total cap; see D4) with a `[… truncated]` marker. Verify: unit test feeds
  output > cap and asserts the emitted payload length ≤ cap + marker.
- [x] **AC7 — `messages` persistence is redacted.** If the streamed command/output is persisted
  on the assistant message (D5), the persisted body is the **redacted** form. Verify: persistence
  test asserts no secret substring in the saved row.
- [x] **AC8 — `tsc --noEmit` passes** after the `WSMessage` union is widened with
  `command_stream` (run `tsc --noEmit`; every `TS2322 … not assignable to never` exhaustiveness
  rail surfaced is widened — do NOT prescribe a fixed count; the compiler enumerates).
- [x] **AC9 — non-autonomous posture unchanged when streaming is gated to autonomous (if D1=
  autonomous-only).** With `bashAutonomous=false`, the existing `review_gate` path still fires
  for non-blocked, non-safe Bash (no behavioral change). Verify: existing gate tests pass
  unmodified.

### Post-merge (operator)

- [ ] **AC10 — visual QA in Concierge.** With an autonomous workspace, run a Concierge prompt
  that triggers a Bash command; confirm no Approve/Deny card appears and the command + output
  append into the bubble terminal-style. Automation: Playwright MCP against the dashboard chat
  route (see Test Scenarios) — NOT a manual step.
- [ ] **AC11 — #3345 disposition recorded.** Close or relabel #3345 per Open Code-Review Overlap
  (superseded-in-direction). Use `gh issue close 3345 --comment "…"` post-merge.

## Implementation Phases

> TDD: write the failing test first for each phase (`cq-write-failing-tests-before`).
> Phase order is **contract-before-consumer**: the WS type + redaction land before the
> reducer/component consume them.

### Phase 0 — Preconditions (grep-verify, no code)
- Confirm `redactGithubSourcedText` export + signature: `grep -n "export function redactGithubSourcedText" apps/web-platform/lib/safety/redaction-allowlist.ts`.
- Confirm `WSMessage` union + `tool_use` shape: `grep -n "type: \"tool_use\"\|type: \"stream\"\|type: \"stream_end\"" apps/web-platform/lib/types.ts`.
- Confirm `chat-state-machine` reducer `case "stream"` / `tool_use` append semantics (lines 344, 463) so the new `command_stream` case mirrors REPLACE-vs-APPEND correctly (output APPENDS; stream text REPLACES).
- Enumerate `_exhaustive: never` rails: after the type edit run `tsc --noEmit` and treat each error as a rail (do not pre-count).
- Confirm vitest globs: server tests `test/**/*.test.ts`, component tests `test/**/*.test.tsx` (`vitest.config.ts:43–60`) — new tests go under `apps/web-platform/test/…`, NOT co-located (`bunfig.toml` blocks bun discovery).

### Phase 1 — Extend redaction (TR4) — contract leaf, no consumers yet
- Add `GH_TOKEN=` / generic `<UPPER_TOKEN>=<value>` env-assignment redaction + `Authorization: <scheme> <value>` header redaction to `redaction-allowlist.ts` (preserving the 3 PII invariants; order structured-before-numeric per existing comment).
- Add `redactCommandForDisplay(command: string): string` (thin wrapper over the extended module, command-shaped: also collapse `--header @<(printf …ghs_…)` forms). Co-locate; export.
- RED test first: assert all four secret shapes are replaced AND benign commands pass through unchanged.

### Phase 2 — New WS event `command_stream` (TR2) — server contract
- Widen `WSMessage` in `lib/types.ts` with a typed variant, e.g.
  `{ type: "command_stream"; leaderId: DomainLeaderId; command?: string; output?: string; phase: "start" | "output" | "end"; truncated?: boolean }`.
  Run `tsc --noEmit`; widen every exhaustiveness rail surfaced.
- Plumb a new `onToolResult`/output callback through `DispatchEvents` (`soleur-go-runner.ts:719`) so `handleUserMessage` (`:1891`) forwards `tool_use_result` content (currently discarded) for Bash tool-uses, bounded + redacted, to `cc-dispatcher` which emits `command_stream`.
- Emit `command_stream{phase:"start", command: redactCommandForDisplay(cmd)}` at Bash `onToolUse`; `phase:"output"` chunks from the result; `phase:"end"` on completion. All command/output text routed through `redactCommandForDisplay`/redaction at the **emit boundary** (server) — render-time is belt-and-suspenders.

### Phase 3 — Suppress the two card surfaces (TR1, TR3) — consumer
- `soleur-go-runner.ts classifyInteractiveTool`: remove the `case "Bash"` `bash_approval` return (return `null`) so no `interactive_prompt` is bridged for Bash. (AC1)
- `permission-callback.ts` Bash branch: under streaming posture (D1), replace the `review_gate`-emit path for non-blocked, non-safe commands with `allow(...)` (the `bashAutonomous` path already does this — generalize/gate it per D1). Blocklist + safe-bash branches unchanged. (AC2/AC3)
- Leave `ReviewGateCard` + `BashApprovalCard` components in place (still used by `AskUserQuestion`, gated platform tools, plan_preview/diff/todo — do NOT delete; `cq-ref-removal-sweep-cleanup-closures` n/a since other callers remain). Confirm with `grep -n "case \"bash_approval\"\|<BashApprovalCard\|review_gate" apps/web-platform/components/chat/*.tsx`.

### Phase 4 — Client reducer + render (TR5) — consumer
- `chat-state-machine.ts`: add `case "command_stream"` — APPEND command/output into the active cc_router bubble (mirror the cc_router special-casing in `stream`/`stream_end`, lines 463–529). Output APPENDS to a terminal block; do not REPLACE.
- `message-bubble.tsx`: render the appended terminal block (monospace `<pre>` à la `BashApprovalCard`'s style, but inline in the bubble, no buttons) under the cc_router bubble's content; reuse `whitespace-pre-wrap` + `[overflow-wrap:anywhere]`. Render-time redaction pass as the final gate (belt-and-suspenders per `redaction-allowlist.ts:9–14`).

### Phase 5 — Persistence (D5) + observability (Phase 2.9)
- If the streamed terminal block persists onto the assistant `messages` row, persist the **redacted** form only (AC7).
- Wire `command_stream` emit failures + redaction-fallthrough to `reportSilentFallback`/`warnSilentFallback` (`cq-silent-fallback-must-mirror-to-sentry`), mirroring the existing `onText`/`onToolUse` error mirrors.

## Decisions (resolve at CPO sign-off / `/work` Phase 0)

- **D1 — streaming scope: autonomous-only vs. always.** *Recommended: autonomous-only.*
  Reuse `bashAutonomous` as the gate: streaming + card-suppression applies when the workspace
  is autonomous (already owner-gated behind the risk interstitial in `bash-autonomous-toggle.tsx`).
  Non-autonomous workspaces keep the `review_gate` (AC9). This keeps the approval-bypass behind
  the existing informed-consent surface and avoids silently turning every workspace into
  "auto-approve arbitrary non-blocked bash". *Alternative (always-stream):* matches the
  screenshots most literally but removes the gate for everyone — higher blast radius; requires
  CPO to explicitly accept. **This is the load-bearing product call CPO signs off on.**
- **D2 — what "output" means.** Stream the SDK `tool_use_result` text content (stdout/stderr),
  bounded. Do NOT stream binary/non-text results.
- **D3 — keep or drop the `bash_approval` type variant.** Keep the `InteractivePromptPayload`
  union variant (replay back-compat for already-persisted prompts) but stop EMITTING it. Dropping
  it changes the registry exhaustiveness assertion (`soleur-go-runner.ts:551–559`) — only drop if
  no persisted `bash_approval` rows exist (grep/DB check at `/work`).
- **D4 — output caps.** Per-chunk cap + per-command total cap with `[… truncated]`. Reuse the
  256-char sanitize bound shape already in `soleur-go-runner.ts:1480–1481` as precedent; pick a
  generous terminal cap (e.g. 8–16 KB/command) — decide at `/work` with a number justified in the
  spec, not hand-waved.
- **D5 — persist the terminal block?** Default: persist redacted, so a reload shows the terminal
  history. If persistence is deferred, the bubble shows output live-only (acceptable v1).

## Files to Edit

- `apps/web-platform/lib/safety/redaction-allowlist.ts` — extend (`GH_TOKEN=`, `Authorization:`) + `redactCommandForDisplay`.
- `apps/web-platform/lib/types.ts` — widen `WSMessage` with `command_stream`; touch exhaustiveness rails surfaced by `tsc`.
- `apps/web-platform/server/soleur-go-runner.ts` — `classifyInteractiveTool` Bash → `null`; thread `tool_use_result` output via `DispatchEvents`.
- `apps/web-platform/server/cc-dispatcher.ts` — emit `command_stream` (start/output/end) at Bash onToolUse/onToolResult; redact at emit boundary.
- `apps/web-platform/server/permission-callback.ts` — generalize/gate the non-blocked-Bash allow path under streaming posture (D1); preserve blocklist + safe-bash.
- `apps/web-platform/lib/chat-state-machine.ts` — `case "command_stream"` append reducer.
- `apps/web-platform/components/chat/message-bubble.tsx` — render appended terminal block in cc_router bubble.
- `apps/web-platform/components/chat/chat-surface.tsx` — stop routing Bash to `bash_approval`; verify no dead `case`.
- (Test files under `apps/web-platform/test/…` per vitest globs.)

## Files to Create

- `apps/web-platform/test/lib/redact-command-for-display.test.ts` — redaction unit (AC4).
- `apps/web-platform/test/server/cc-dispatcher-command-stream.test.ts` — emit + redaction-at-boundary (AC2/AC4/AC5/AC6).
- `apps/web-platform/test/lib/chat-state-machine-command-stream.test.ts` — reducer append (AC5).
- `apps/web-platform/test/components/chat/message-bubble-command-stream.test.tsx` — render (AC5).
- `apps/web-platform/test/server/permission-callback-streaming.test.ts` — no-gate + blocklist intact (AC2/AC3/AC9).
- **Wireframe (REQUIRED, produced):** `knowledge-base/product/design/command-center/concierge-streamed-commands.pen`
  (committed). Shows the Concierge bubble with a "Streaming" pill, an inline monospace terminal block
  rendering `$ gh pr list … --token [redacted-token]` (redaction visible), streamed stdout, a
  `[… truncated]` marker, a blinking cursor, and an annotation: "No Approve/Deny buttons — command
  executes inline and output streams directly into the message bubble, Claude-Code-terminal style."
  The `message-bubble.tsx` terminal block (Phase 4) implements this layout. (PNG export is gitignored
  by convention; the `.pen` is the tracked artifact.)

## Open Code-Review Overlap

5 open `code-review` issues mention target files. Dispositions:

- **#3345 — "replace raw Bash approval modal with intent-shaped UX"** → **Acknowledge /
  supersede-in-direction.** #3345 proposes Option (b) (keep the gate, reshape it intent-style).
  This plan implements Option (a) (cards gone, stream + auto-approve under `bashAutonomous`),
  which **supersedes #3345's direction**. AC11 + a post-merge `gh issue close 3345` with a
  superseded-by note. Do NOT fold #3345's intent-card design in — it contradicts the chosen
  direction. (CPO confirms at sign-off.)
- **#2220 / #2224 — chat reducer purity / code-quality polish** → **Acknowledge.** Different
  concern (reducer refactor / JSX polish). This plan adds a reducer `case`; it should follow the
  existing reducer conventions but does NOT need to fold in the purity refactor. Leave open.
- **#3703 — client-pii-grep CI + lefthook gate** → **Acknowledge / adjacent.** This plan adds a
  new client-render path for command text; ensure the new `message-bubble` terminal block does not
  regress the client-PII grep. Note in PR body; do not fold the CI gate in.
- **#3333 — createIssue agent tool ("File an issue" parity)** → **Acknowledge.** Unrelated.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO), Legal/Compliance (CLO — credential
redaction + persisted-content minimization).

> Environmental note: the Task tool is unavailable in this planning environment (confirmed via
> ToolSearch + learning `2026-05-05-cc-permissions-bash-allowlist-hardening.md` §Session Errors #4).
> Domain-leader and plan-review fan-out cannot spawn as subagents here; assessments below are
> authored inline and MUST be re-run as agents at `/work` / plan-review when the environment
> supports Task. This is a known constraint, not a skipped gate.

### Engineering (CTO)
**Status:** reviewed (inline)
**Assessment:** The risky part is the **new server→client output channel**. `tool_use_result`
content is currently discarded; forwarding it means attacker-influenced shell output now reaches
the UI and `messages`. Redaction MUST run at the **emit boundary** (server), not only render-time,
and output MUST be byte-capped to bound DoS/flood. Reuse `bashAutonomous` rather than adding a
parallel bypass (avoids a second approval-bypass code path to audit). Exhaustiveness rails on the
`WSMessage` union must be enumerated by `tsc`, not counted.

### Product (CPO) — see User-Brand Impact (single-user incident → sign-off required)
**Status:** reviewed (inline); **CPO sign-off required at plan time before `/work`.**
**Assessment:** The load-bearing call is D1 (autonomous-only vs. always). Recommended autonomous-only
keeps the bypass behind the existing informed-consent interstitial. CPO must confirm Option (a) over
#3345's Option (b), and confirm D1.

### Legal/Compliance (CLO)
**Status:** reviewed (inline)
**Assessment:** Credential redaction is the GDPR/security-minimization gate (Art. 5(1)(c)). Persisted
command/output (D5) must be the redacted form. The redaction extension (`GH_TOKEN=`,
`Authorization:`) closes the exact leak vector in the screenshots. No new regulated-data *schema*
surface; this is content-minimization on an existing surface → GDPR gate is advisory (see 2.7).

### Product/UX Gate
**Tier:** BLOCKING (corrected at deepen-plan Phase 4.9). The mechanical UI-surface override fired:
`Files to Edit` changes `components/chat/message-bubble.tsx` (a component), and the feature renders a
**new visible UI element** — the inline streamed-terminal block in the Concierge bubble. Per
`ui-surface-terms.md` ("creates **or changes** … components" + glob superset forces UI-surface true
"regardless of subjective assessment"), this is a UI feature requiring a wireframe
(`wg-ui-feature-requires-pen-wireframe`). The earlier ADVISORY call was too lenient — a new on-screen
terminal block is a layout/affordance decision a wireframe disambiguates (placement, truncation marker,
monospace styling, output/text interleave).
**Decision:** reviewed — wireframe produced.
**Agents invoked:** none as Tasks (Task tool unavailable in this environment — see Domain Review note).
spec-flow-analyzer / CPO / copywriter must run at plan-review/work when Task is available.
**Skipped specialists:** none — `ux-design-lead` is the non-skippable producer and DID produce the
`.pen` (via `pencil` CLI, `PENCIL_CLI_KEY` from Doppler `soleur/dev`).
**Pencil available:** yes — `.pen` generated + committed:
`knowledge-base/product/design/command-center/concierge-streamed-commands.pen` (18 KB, tracked).
Referenced in `## Files to Create` and bound to Phase 4 (`message-bubble.tsx` render).

## Infrastructure (IaC)

No new infrastructure. Pure code change against an already-provisioned surface
(`apps/web-platform/server/**` + `lib/**` + `components/**`). No server, secret, vendor, cron, or
persistent runtime process introduced. Phase 2.8 skip conditions met.

## Observability

```yaml
liveness_signal:
  what: command_stream events emitted per Bash tool-use (start/output/end)
  cadence: per Bash tool invocation in an autonomous Concierge session
  alert_target: Sentry (existing cc-dispatcher Sentry project)
  configured_in: apps/web-platform/server/cc-dispatcher.ts (emit site) + observability.ts
error_reporting:
  destination: Sentry via reportSilentFallback/warnSilentFallback (existing helpers)
  fail_loud: true  # emit failure + redaction-fallthrough both mirror to Sentry
failure_modes:
  - mode: redaction fallthrough (a secret shape survives redactCommandForDisplay)
    detection: render-time + emit-time fallthrough probe mirrors to Sentry op="command-stream-redact-fallthrough"
    alert_route: Sentry (P0 class — credential leak)
  - mode: command_stream emit throws (WS send failure)
    detection: try/catch → reportSilentFallback op="emitCommandStream"
    alert_route: Sentry
  - mode: output exceeds cap (expected) vs. unbounded (bug)
    detection: cap applied at emit; unit test AC6; a missing-cap regression surfaces as oversized payload
    alert_route: test-time (AC6); runtime cap is deterministic
logs:
  where: pino child logger "permission" / "cc-dispatcher" (sec:true on bash decisions, existing)
  retention: existing platform log retention (no change)
discoverability_test:
  command: ./node_modules/.bin/vitest run test/server/cc-dispatcher-command-stream.test.ts
  expected_output: command_stream events asserted ordered + redacted; zero secret substrings in payload
```

## Research Insights

### Redaction precedent-diff (Phase 4.4 — established pattern, not novel)
`redactGithubSourcedText` (`lib/safety/redaction-allowlist.ts`) is the canonical text-redaction
primitive and is already wired in the exact dual-gate shape this plan needs:
- **Emit/INSERT boundary:** `server/messages/insert-draft-card.ts:78` — `redactGithubSourcedText(input.draft_preview)` before persistence.
- **Render-time gate:** `components/dashboard/today-card.tsx:246` — `redactGithubSourcedText(draftPreview, { source })` at render.
- Module doc (`redaction-allowlist.ts:9-14`): "INSERT-time keeps the audit row redacted-equivalent; render-time is the final Art. 14 gate. If you must drop one, drop INSERT-time. NEVER drop render-time."

**Plan response:** mirror this dual-gate exactly — redact `command` and `output` at the `command_stream`
emit boundary (server), redact again at `message-bubble.tsx` render. The module covers
`ghp_/gho_/ghu_/ghs_/ghr_`, `github_pat_`, Stripe/Anthropic/OpenAI/AWS/Slack keys, JWTs (`API_KEY_RE`,
`JWT_RE`). It does NOT cover `GH_TOKEN=<value>` env-assignments or `Authorization: Bearer <value>`
header literals (verified: `grep -cE "GH_TOKEN|Authorization" redaction-allowlist.ts` → 0). Extend with:
- env-assignment shape `\b([A-Z][A-Z0-9_]*_(TOKEN|KEY|SECRET|PASSWORD|PAT))\s*=\s*['"]?\S+` → `$1=[redacted-key]` (preserve the key name like the existing `AWS_SECRET_ASSIGN_RE` does).
- header shape `\b(Authorization)\s*:\s*(Bearer|Basic|token)\s+\S+` → `$1: [redacted-token]`.
- the redirected-fd form the screenshots showed: `--header @<(printf '…ghs_…')` — the inner `ghs_` already
  matches `API_KEY_RE`, so command-level redaction catches it once the command string is passed through.
Follow the module's 3 PII invariants (max-input bound, alphabet-aware, no `/g`+`.test()` gate).

### Information-disclosure invariant to preserve (#2138)
`buildToolUseWSMessage` (`tool-labels.ts:269`) deliberately keeps the raw SDK tool name OFF the wire
(#2138). The new `command_stream` event intentionally DOES carry command text — but only the
**redacted** form. This is a deliberate, scoped exception to #2138 for the Bash-streaming UX, justified
by the redaction gate; call it out in the PR body so reviewers don't read it as a #2138 regression.

### Verify-the-negative result
- "Tool output never reaches the client today" — CONFIRMED (zero emit sites for `tool_use_result`→client).
- "`bashAutonomous` auto-approves non-blocked" — CONFIRMED at `permission-callback.ts:405-422`.
- "`review_gate` question embeds the raw command" — CONFIRMED at `:459-460` (the leak origin).

### Live citation verification (Phase 6 quality checks)
- `gh issue view 3345` → OPEN, "feat(cc-chat): replace raw Bash approval modal with intent-shaped UX" (superseded-in-direction; AC11).
- `gh issue view 4672` → OPEN, "Structured human-in-the-loop approval queue for write/send actions" (related, out of scope).
- `gh issue view 3703` → OPEN, "review: add client-pii-grep CI + lefthook gate" (adjacent; new render path must not regress it).
- All `knowledge-base/*.md` citations in this plan resolve on disk (grep+`test -f` sweep, 0 broken).

## Test Scenarios

- Redaction: `ghs_`, `gho_`, `GH_TOKEN=…`, `Authorization: Bearer …`, `--header @<(printf …)` → all redacted; benign `git status`/`ls -la` unchanged.
- `createCanUseTool` (streaming deps): non-blocked Bash → `allow`, zero `review_gate` sends; blocked Bash → `deny` (AC3); `bashAutonomous=false` non-streaming → existing gate fires (AC9).
- Reducer: `command_stream` start→output→output→end appends ordered terminal block to cc_router bubble; interleaving with `stream` text preserves order.
- Component: cc_router bubble renders the terminal block monospace; long output shows `[… truncated]`.
- Playwright MCP (AC10, post-merge): autonomous workspace, Concierge prompt triggering a Bash command → no Approve/Deny card; command + output append in the bubble; screenshot diff.

## Non-Goals / Out of Scope

- The **GitHub-403 "can't create issues"** error (workspace-runtime token-path bug). Explicitly
  excluded — separate queued PR. Installation `soleur-ai 122213433` already has `issues:write`, no
  IP allowlist.
- **#4672 (CP2)** batched human-in-the-loop approval queue for write/send actions — strategically
  related (per-call prompts are bad for non-technical operators) but a distinct, larger feature.
  This PR addresses read/non-blocked Bash streaming only; write/send batching stays in #4672.
- Intent-shaped approval cards (**#3345**) — superseded in direction (see Overlap).
- Changing the `BLOCKED_BASH_PATTERNS` set, the safe-bash allowlist, or the `bashAutonomous`
  toggle UX. Reuse as-is.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, `TBD`, or omits the threshold fails
  `deepen-plan` Phase 4.6. It is filled above.
- **Output is the new attack surface, not just the command.** The command leak is fixed by
  redacting `command`; but shell *output* can also echo secrets (`env`, `cat .git/config`,
  `printenv`). Redaction MUST run on the `output` payload too, at the emit boundary. (Captured in
  Phase 2 + Observability redaction-fallthrough.)
- **Do not delete `ReviewGateCard`/`BashApprovalCard`.** Both are still rendered for
  `AskUserQuestion` / gated platform tools / `plan_preview` / `diff` / `todo_write`. Only the
  **Bash → bash_approval** wiring is removed. Grep callers before any deletion.
- **`tsc` enumerates exhaustiveness rails, not the plan.** After widening `WSMessage`, run
  `tsc --noEmit` and fix every `not assignable to never`; the rails live in `*.test-d.ts` and
  adjacent server switches that a source grep undercounts (`tsc-not-source-grep-enumerates-...`).
- **Vitest discovery:** new component test must live under `test/**/*.test.tsx` (jsdom project);
  a co-located `components/**/*.test.tsx` is silently never run (`vitest.config.ts:59–60`).
- **Redaction at render-time is belt-and-suspenders, not primary.** Per `redaction-allowlist.ts:9–14`,
  the emit-boundary (server) redaction is load-bearing; render-time is the final Art. 14 gate. If you
  must drop one, drop emit-time — NEVER drop render-time. (But here, persisted content needs emit-time
  redaction too, so keep both.)

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| (b) Keep gate, intent-shape the card (#3345) | Rejected — contradicts "cards GONE"; doesn't show output; CPO confirms |
| Add a NEW auto-approve bypass independent of `bashAutonomous` | Rejected — a second approval-bypass path to audit; reuse the owner-gated toggle |
| Reuse `tool_use` label channel for output | Rejected — `tool_use` deliberately withholds raw tool data (#2138); output needs its own typed event |
| Stream output but keep both cards | Rejected — the cards are the spam the feature removes |
| Render-time redaction only | Rejected — persisted `messages` row would carry the secret; redact at emit boundary |
