# Review Findings — PR #9540 (issue #9539)

Panel: 10 review seats (pattern-recognition, architecture, security-sentinel,
code-quality, git-history, data-integrity, agent-native, performance,
test-design, structural-enumeration) + 3 deterministic hooks (semgrep-sast 0
findings, anti-slop Tier 1 `[]`, gdpr-gate advisory PASS). Change class: `code`,
tier `none` (linked plan, explicit sensitive-path scope-out). PANEL_SHA at panel
spawn: `2d11c4f47b`; fix round re-reviewed on the fix commit.

## Deduped findings ledger (raw ~45 → 12 canonical)

| # | Finding (canonical) | Seats concurring | Sev | Disposition |
|---|---|---|---|---|
| 1 | `bridgeInteractivePromptIfApplicable` persona-blind — WS `interactive_prompt` + answerable `pendingPrompts` on a schema-removal bypass | structural, security, agent-native, architecture, pattern | P1 | **FIXED** — `state.persona === "support"` early return at bridge head (`soleur-go-runner.ts:1829`) |
| 2 | `allowedTools` auto-approves TodoWrite/ExitPlanMode on support — bypasses `canUseTool` (belt can't see the call) | architecture, security, pattern, agent-native | P1 | **FIXED** — `allowedTools` filtered against `SUPPORT_EXTRA_DISALLOWED_TOOLS` for support (`cc-dispatcher.ts:2814`) |
| 3 | `edit_c4_diagram` registered + advertised + auto-approved on support — real repo write outside the sandbox | structural, security | P1 | **FIXED** — c4 surface gated on `args.persona !== "support"` (tool build, `platformToolNames`, `c4PromptAddendum`, `registeredPlatformToolNames`) |
| 4 | Uncovered deny/allow paths break "every engineering attempt records": Agent allow, file-tool write-class/outside-workspace, platform-tool gated branch, deny-by-default | pattern, structural, data-integrity, security | P2 | **FIXED** — `"tool"` escalation source added; denySupport belts on all five paths; TodoWrite/ExitPlanMode get no-record denies |
| 5 | ConversationId-keyed flag misattributes under concurrent/zombie turns (sticky conv + `state.events` rebind) | data-integrity, agent-native, pattern, security, architecture | P2 | **FIXED** — per-conversation busy guard (409 on second POST while in-flight); zombie-in-window residual documented + accepted (per-dispatch key cannot reach per-Query ctx) |
| 6 | Deny messages hardcode label/href instead of the shared copy module (AC8 non-compliance) | code-quality, pattern, architecture | P2 | **FIXED** — `SUPPORT_AGENT_SESSION_HINT` in `lib/support-handoff.ts`, composed by all deny messages + `SUPPORT_BASH_DENY_MESSAGE` |
| 7 | kb-search's `git grep`/`grep`/script shell-outs hit the new deny → false-positive handoff | security | P2 | **FILED** — #9559 (support-scoped allowlist or tool-based path needs its own review) |
| 8 | Consume-before-enqueue: throw eats flag + skips `finishTurn` → 120s hang, no marker | data-integrity, git-history, structural, security | P3 | **FIXED** — `support-handoff-emit-failed` log + `finishTurn` on terminal in the catch |
| 9 | Deferred-issue filings unverified (safe-bash `git branch`, `repoConnected`, `?q=`) | git-history | P2 | **FILED** — #9555, #9556, #9557 (+ #9558 GH-token/askpass/egress from security F3) |
| 10 | Test gaps: vacuous surrogate fixture, no FIFO-cap test, opt-out-hold arm unpinned, GATE_FRAME_TYPES allowlist, mock strips `warnSilentFallback` | test-design, code-quality | P2 | **FIXED** — odd-boundary fixture (501), cap + insertion-order tests, (b2b) opt-out arm, `sendToClient` not-called asserts, literal terminal-set pin, mock fixed |
| 11 | Observability nits: `requested`→`detail` rename breaks Better Stack query; silent FIFO evict; unsanitized `detail`; AskUserQuestion deny lacks always-on log | git-history, security, data-integrity, architecture | P3 | **FIXED** — `requested` back-compat key, `support-escalation-evicted` log, `\p{Cc}`-class sanitize + 200-char cap, always-on `log.info` for question/UX denies |
| 12 | Naming/comment/doc drift: `handoff` var → `escalationSource`, "strictly turn-scoped" overclaim, tasks.md stale lines, `Array.from` micro | pattern, architecture, performance, code-quality, git-history | P3 | **FIXED** — var renamed, comments corrected to honest residual language, tasks.md synced, `length<=maxChars` short-circuit |

## Declined / deferred

- **`supportTerminalPrefixFrames` rename** (code-quality P3 nit): churn for a
  well-documented name — declined.
- **Route-mock scaffold dedup into `test/helpers/`** (code-quality P3): nice-to-
  have, Medium effort — declined in-scope.
- **Turn-scoped registry keying** (data-integrity P2 alternative): requires
  threading a dispatch id through Query-scoped ctx — the busy guard closes the
  same misattribution at the transport layer. Zombie-in-window residual
  documented in `support-escalation.ts` header + ADR-113.
- **`?msg=` auto-send security model** (agent-native): pre-existing consumer
  (`chat-surface.tsx:218`); the user's own text re-delivered to the same
  authenticated user; "needs a connected repo" copy discloses the repo gate.
- **`conversationId` field on the frame**: kept per plan (telemetry/correlation
  for future consumers; reducer intentionally ignores it).
- **GH-token mint / askpass write / egress widening not persona-gated**
  (security F3, pre-existing): filed #9558 — cc-dispatcher change deserving
  its own review + tests.
- **Verbatim incident shape** (`git branch <name>` auto-approves + prose
  decline): filed #9555; accepted residual recorded in `decision-challenges.md`
  UC-1 and ADR-113 addendum.

## Fix-round disposition

fix_rounds=1 — 5 targeted seats (security, structural-enumeration,
architecture, data-integrity, test-design — the seats that filed every P1/P2)
re-verified on `f4edc9194b`. **All concur:** security=pass,
structural-enumeration=FIXED, architecture=approve, data-integrity=pass,
test-design=concur.

Advisory fixes applied post-round (commit `22d4f5c523`): busy-flag delete
moved into `finally` (theoretical permanent-409 leak flagged by both
data-integrity and security), `support-turn-busy` log on the 409,
`autonomous_posture` WS emit gated off support (security INFO residual),
`SUPPORT_AGENT_SESSION_LABEL` interpolated in the directive link.

Recorded (not filed, documented in-code/ADR): zombie-in-window flag
attribution residual, no `cancel` handler on the stream (409 bounded by the
120s cap), concurrent first-time POST mint-race on the non-unique support
conversation index (pre-existing, two-row dedup edge), plugin-MCP arm lacking
a persona belt (unreachable — `pluginMcpServerNames: []`), Bash
empty-command deny without a record (no-payload shape, consistent with the
no-record design).
