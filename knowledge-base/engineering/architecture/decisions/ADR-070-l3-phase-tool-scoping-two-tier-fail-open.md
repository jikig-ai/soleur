# ADR-070: L3 per-phase tool/skill scoping — the two-tier fail-open rule

- **Status:** Accepted
- **Date:** 2026-06-30
- **Amended:** 2026-06-30 (#5772 — shared-registry resolution; see Amendment below)
- **Amended:** 2026-07-01 (#5843 TR3 — tool-attempt telemetry collector; see Amendment 2 below)
- **Issue:** #5768 (L3 "Execution" gap of the harness 5-layer analysis)
- **Deferred follow-up:** #5772 (web/SDK parity)

## Context

The agent harness exposes a large static surface — 92 skill descriptions (always
in the system prompt), 68 agents, and many MCP tools — without scoping to the
active workflow phase. A planning step still "sees" deploy/ship/merge. The L3
thesis ("fewer tools = better") says a large surface imposes a tool-selection tax.

Two existing mechanisms already shrink the surface, fail-open, and the issue's
framing under-credited both:

- **MCP schemas are already deferred** via the ToolSearch deferred-tool mechanism
  (the heaviest ~100-tool surface is behind a search-to-load gate). Re-fetched on
  demand → inherently fail-open.
- **Change-class scoping already ships** via `.claude/hooks/session-rules-loader.sh`
  (#3493): it injects only the relevant `AGENTS.{core,docs,rest}.md` per diff
  class, with multi-class/empty → load-all (fail-open).

The genuine residual is the **92 always-loaded skill descriptions** (the Claude
Code runtime, not Soleur, owns the menu — a hook can only *hint*, not
un-advertise) and the **absence of a phase signal**.

## Decision

Add a CLI-side, **fail-open additive** phase-scoping layer that biases which
skills/agents the model foregrounds per phase — **without removing anything**.

- **Mechanism:** a single stateless **PostToolUse hook on the `Skill` matcher**
  (`.claude/hooks/phase-surface-hint.sh`). It maps `tool_input.skill` →
  a phase via `.claude/phase-surface-map.json` and injects that phase's hint as
  `hookSpecificOutput.additionalContext`. Live-verified (CC 2.1.196, #5768 Phase
  0 probe): PostToolUse fires for the `Skill` tool and the additionalContext
  reaches the model as a `<system-reminder>`. PreToolUse cannot inject context
  (it returns only `permissionDecision`); PostToolUse can (precedent:
  `pencil-collapse-guard.sh`). PostToolUse fires on every skill call —
  interactive **and** autonomous (`one-shot`) — which `UserPromptSubmit` does not
  (it never fires inside the autonomous pipeline; that was the load-bearing
  defect caught at plan-review).

- **Two-tier fail-open rule (the load-bearing invariant):** deny-by-default is
  permitted ONLY on an already-fail-open layer (MCP/ToolSearch — re-fetches on
  demand). On every other layer — built-in tools, the ~20 PreToolUse safety
  hooks, and the web SDK `canUseTool`/`disallowedTools` — scoping MUST be
  **additive-hint only**. A hard deny there could route an agent *around* the
  safety hook that would have caught it (CLI), or produce a silent "unknown tool"
  failure for a paying user (web SDK). Any phase-classifier ambiguity / unmapped
  skill → emit nothing → full surface (mirrors `session-rules-loader.sh`
  multi-class/empty → load-all). In CLI v1 *nothing is denied on any tier*, so
  the invariant holds trivially; this ADR binds the **deferred** web
  `disallowedTools` implementer (#5772), not just v1.

- **Fail-open is doubly load-bearing at the hook level:** a non-zero hook exit
  does not merely "not block" — CC treats exit 2 as a blocking error and any
  other non-zero exit as "JSON output skipped", i.e. it **silently drops** the
  hint. The hook exits 0 on every path.

- **Security — `tool_input.skill` is model-controlled, not config-trust.** A
  prompt-injected model (e.g. in a WebFetch/research flow) can emit a crafted
  skill name. So the injected hint is composed from **map-derived constant text
  only** (the skill name is a lookup key and never appears in output); the phase
  lookup parameterizes the skill via `jq --arg`; the envelope is built with
  `jq -n --arg`. This is sharper than AGENTS.md (operator-reviewed config); an
  adversarial test gates it.

- **Registry consistency** follows the ADR-053 three-coupling pattern (registry +
  the consuming hook + a consistency test), but the test is a **shell** test
  (`phase-surface-hint.test.sh`, PARITY/CHARSET/NEGATIVE) not a dedicated TS test
  — a stale map entry fails OPEN (no hint), so a fail-closed TS CI gate would be
  disproportionate. Precedent: `eval-harness/test/registry-completeness.test.sh`.

- **Why the web side is deferred (#5772), not skipped.** The web Concierge runs
  the same skill sequence (`/soleur:go` as SDK router, ADR-022), but the SDK agent
  sets `settingSources: []` (`agent-runner-query-options.ts:155`) so it does NOT
  load `.claude/` hooks — the CLI hook physically cannot reach it. Web parity
  needs an SDK-native hook registered in `options.hooks` (where the PreToolUse
  sandbox hook + SubagentStart already live). Separately, `allowedTools` is
  **auto-approve-only** (sdk.d.ts:858-862); the only real web surface restrictor
  is `disallowedTools`, which is **fail-closed** — so the web subset is gated
  behind tool-attempt telemetry + #5768's eval evidence before it ships.

- **Canonical shared-registry location (for #5772).** `.claude/phase-surface-map.json`
  is CLI-local and unreadable by the web server. When web parity lands, the map
  is to be relocated to a shared, runtime-readable location (or duplicated with a
  consistency test across both copies) — decide at #5772 build time; do not let
  the `.claude/` location ossify as the only copy.

## Alternatives considered

- **Full per-phase allowlist framework (hard-deny tools by phase).** Rejected:
  highest risk of safety-hook bypass for low marginal gain (MCP already scoped).
- **Measure-only (ship the eval target, no behavior change).** Rejected: the
  operator wanted a shipped behavior change alongside measurement.
- **`UserPromptSubmit` reader + a phase-token file written by the PreToolUse
  logger.** Rejected at plan-review: `UserPromptSubmit` never fires in `one-shot`
  (the primary autonomous flow), delivering zero surface reduction there; and it
  required a stateful token + session-id plumbing + an on-change sentinel that the
  stateless PostToolUse design eliminates.
- **Web `disallowedTools` subset in v1.** Rejected: fail-closed (silent
  unknown-tool to paying users) → contradicts "fail-open only" → deferred to #5772.

## Consequences

- A new fail-open hook fires on every `Skill` call; worst case (regression /
  bad map) is "no hint", never a broken or restricted surface.
- Effectiveness is measured by the opt-in/manual `eval-harness` `tool-selection`
  target (#5768 AC(c)), not asserted at merge — the mechanism ships, the win is
  evidenced operator-side.
- The two-tier fail-open rule is now the binding constraint for any future
  tool-surface scoping work, especially #5772.

## Amendment — 2026-06-30 (#5772): shared-registry resolution + web lever 1

The original Decision (above) is unchanged. This amendment resolves the
"Canonical shared-registry location" sub-decision that the Decision explicitly
deferred to "#5772 build time", and records how lever 1 shipped on the web.

**Shared-registry location — resolved: bundled `.ts` copy + CI parity test.**
The canonical map stays at `.claude/phase-surface-map.json` (the CLI hook's
source). The web SDK agent gets a bundled copy at
`apps/web-platform/server/phase-surface-map.ts` (a `.ts` const, guaranteed
compiled into `dist/server` regardless of build mechanism), guarded by
`apps/web-platform/test/phase-surface-map-parity.test.ts` which deep-equals it
against the canonical JSON and fails CI on drift (the ADR-053 three-coupling
pattern). Rejected alternatives:

- **Read `.claude/…json` at web runtime** — rejected: the Dockerfile does not
  ship `.claude/` into the container (`.dockerignore`), so the file is absent.
- **Single copy relocated into the vendored plugin tree, read from
  `pluginPath` at runtime** — rejected: the plugin symlink is best-effort
  warn-only (`workspace.ts`), so a missing/broken symlink → ENOENT → the hint
  silently never fires (a prod-only degradation no test catches); and the CLI
  hook must keep reading `.claude/`, so the "single source of truth" is
  illusory — it stays two representations PLUS a runtime fs read. The bundled
  in-process constant makes the fail-open guarantee structurally true (it cannot
  ENOENT) and confines drift to a deterministic CI gate.

**Web lever 1 — per-caller opt-in (consequence the lever-2 implementer inherits).**
The web hook is an SDK-native `PostToolUse(Skill)` callback registered in
`buildAgentQueryOptions` `options.hooks` (`apps/web-platform/server/phase-surface-hook.ts`).
It is registered **only when the caller passes `enablePhaseSurfaceHint: true`** —
the cc-soleur-go Concierge router (the eval-covered workflow-routing path) opts
in; the legacy domain-leader runner does NOT. This per-caller seam is binding for
**lever 2** (`disallowedTools`), which is fail-CLOSED: a "both-callers-always-on"
default would have silently restricted the legacy path (the unknown-tool hazard
the two-tier rule guards against). #5772's +6.7pt eval (`claude-sonnet-4-6`,
PR #5792) covered only the cc workflow-routing path — the lever-2 implementer
inherits this cc-path eval-coverage caveat.

**Cross-surface key normalization (documented coupling).** The web Concierge
emits **bare** Skill names (`work`) in `tool_input.skill`, while the canonical
map is **FQN-keyed** (`soleur:work` — the CLI emits FQN). The web hook normalizes
bare→FQN at lookup (`SOLEUR_SKILL_PREFIX`). Without this, the hint silently never
fires on the web. Re-keying the bundled copy to bare names would break byte-parity
with the canonical JSON, so normalization lives in the hook, not the map.

## Amendment 2 (2026-07-01, #5843 — TR3 tool-attempt telemetry collector)

Lever 2 (`disallowedTools` per phase) is fail-CLOSED and requires evidence of
which tools are *never* attempted per phase before anything is removed. TR3 adds
the measurement instrument. Four decisions, all folded into
`apps/web-platform/server/tool-attempt-telemetry.ts`:

- **(a) Aggregated one-row-per-session, NOT insert-per-tool-call.** An
  insert-per-call design would add per-tool WAL + index write IO on the hot prod
  cc agent path for every user — the exact Disk-IO class that migrations 114/115
  and PR #5736 addressed. The collector accumulates counts in an in-memory
  closure and flushes ONE `public.tool_attempts` jsonb row at query teardown
  (`soleur-go-runner.ts closeQuery` → `cc-dispatcher.ts handleCcCloseQuery`, the
  abort-covering chokepoint that fires exactly once per `ActiveQuery`).

- **(b) Static-availability oracle, NOT SDK-iterator unknown-tool capture.**
  `available(cc)` is derived from config (SDK built-in default toolset minus the
  cc floor `CANONICAL_DISALLOWED_TOOLS ∪ [Edit,Write]`, plus registered MCP), not
  from observation. A tool the model never happened to try is therefore NOT
  falsely dropped from `available`; `never-needed(phase) = available(cc) −
  attempted(phase)` stays sound. The collector only records the *attempted* half.

- **(c) Phase tracked on the PreToolUse(Skill) WAY-IN, not PostToolUse(Skill).**
  `PostToolUse(Skill)` fires AFTER the routed sub-skill runs, so it would
  attribute that skill's own tools to the PREVIOUS phase (off-by-one). A single
  fail-open `PreToolUse` hook sets `phase = skillToPhase(tool_input.skill)` on the
  way in; the routed skill's subsequent tool calls then attribute to the new
  phase. Reading `tool_input.skill` (a known own-property-gated enum key, shared
  `skillToPhase` with lever 1) is the SOLE permitted `tool_input` read — it does
  NOT violate NO-ECHO, which forbids capturing arbitrary `tool_input` for
  non-Skill tools. Tools before the first Skill land under `"unrouted"`.

- **(d) Closure-minted pseudonymous id, never persisted.** The accumulator is
  closure-scoped with a per-query `crypto.randomUUID()` — NOT a module-level
  `Map<sessionId>` (re-identification + leak + unbounded growth). The SDK
  `BaseHookInput.session_id` is UNIQUE-indexed to `user_id`
  (`028_conversations_user_id_session_id_unique.sql`), so it is DELIBERATELY kept
  out of the table: `tool_attempts` has NO session/user/conversation column — the
  row is anonymous (`counts` only), and the cc-side routing map that reaches
  `flush()` is keyed by `(userId, conversationId)` in memory only, drained on
  every close path (mirrors `_ccWorktreeLeases`).

**Opt-in seam (inherits lever 1's per-caller rule).** The telemetry hook is
registered as a SEPARATE matcher-less `PreToolUse` entry (full-surface capture:
`Skill`/`Task`/`mcp__*`/`Read`/`Bash`/…) ONLY when the caller passes
`toolAttemptPreToolUseHook` — the cc-soleur-go router opts in; the legacy runner
leaves it undefined, so its `PreToolUse` array is byte-unchanged (AC5 drift
snapshot). Observe-only + fail-open: the hook always returns `{}` and never
mutates `canUseTool`/`disallowedTools`; a flush DB failure mirrors to Sentry via
`reportSilentFallback` and never fails the agent turn. Retention: 90d pg_cron.

## Amendment (2026-07-10, ADR-113 — support-persona scope)

The support-persona Concierge (ADR-113) uses two tool-scoping mechanisms this ADR
governs, both reconciled as compliant. (1) Its `createCanUseTool` default-deny
returns a graceful `{behavior:"deny", message}` the model relays — this is the
sanctioned deny-with-message shape, NOT the silent phase-scope deny this ADR
forbids. (2) It silently removes `Edit/Write/MultiEdit/NotebookEdit/Task/Agent`
via `disallowedTools`; that silent removal is acceptable here — and NOT the
additive-hint-only violation this ADR forbids — because those are tools a support
end-user NEVER legitimately needs, so their removal breaks no valid flow. The
harm this ADR enumerates (a silent unknown-tool failure for a tool the paying user
legitimately needs) does not arise. This carve-out is scoped to `persona:"support"`
only; the Command Center path is unchanged.
