# ADR-254: Tester-owned local decision log (`.soleur/decisions.jsonl`) — prose-directed emit, field-allowlisted, no egress

- Status: Accepted
- Date: 2026-09-25
- Issue: #8880; PR: #8868
- Composes with: ADR-091 (local-producer doctrine), ADR-179 (plugin-root
  resolution), ADR-046 (registered-check arming for `cohort-quiet`).

## Context

The alpha cohort needs a durable record of routing decisions to serve three
consumers at once: the #1442 usage metrics (returns, agent-mix), a future
corpus for the (parked) System-1 decision-engine evaluation, and
decision-quality feedback. Two hard constraints bound the design:

- **Posture A** — the tester owns the machine, the key, and the purpose
  (2026-08-06 determination). Any Jikigai-side capture of tester decisions
  would create a new regulated data surface and change the legal posture.
- **Hook parity is ~1.5/4 harnesses.** Claude Code and local Devin expose
  PreToolUse hooks; Grok Build and Codex cloud do not. A hook-based writer
  would capture on 1.5 surfaces and nothing on the rest — a coverage
  imbalance that reads as a usage difference.

## Decision

The plugin writes a field-allowlisted JSONL at `.soleur/decisions.jsonl` in
the project, owned by the tester, with no egress:

- **Single writer chokepoint** — `plugins/soleur/scripts/emit-decision.sh`.
  The NO-ECHO contract (never prompt text, args, file paths, repo names) is
  enforced at this boundary: the schema is `{v,ts,event,label,skill,
  agent_domain,harness,session_id,plugin_sha,repo_hash}`, `repo_hash` is a
  sha256 prefix of the git-root path (correlatable, never the path), and
  quote/backslash content is redacted rather than escaped.
- **Prose-directed emit only.** `commands/go.md` directs the agent to emit
  `route_decision` after routing; skills MAY emit `tool_invocation` at their
  own decision points. No `hooks.json` matcher — the hook path was designed
  and then cut: it adds a bash-JSON parser (no jq on stock macOS), its
  coverage imbalance manufactures a capture-rate≠usage-rate trap, and
  hooks would record attempted tool calls where the event semantics need
  routing decisions. Prose is uniform across all four harnesses.
- **No lock.** A single `printf >>` under PIPE_BUF is atomic on POSIX; two
  lock implementations for a handful of appends per session was cut as
  over-mechanization. Rotation is inline at ~5 MB to `decisions.jsonl.1`.
- **Self-guard.** First write creates `.soleur/.gitignore` containing `*`.
- **Tester-initiated aggregate export.** `alpha-metrics.sh` prints counts
  (totals, per-skill/domain/harness, first/last ts) for the tester to paste
  at checkpoint; `SOLEUR_EMIT_ABSENT`/`SOLEUR_EMIT_EMPTY` are explicit
  signals, never read as zero usage.
- **Capability detection is human.** The guided-session day-0 verify step
  (runbook §Step 5) confirms a line lands — the capability check is a person
  on the call, not a capability-state event type.

## Surface → instrument table

| Surface | Instrument | Artifact location | Who pulls it |
|---|---|---|---|
| Hosted platform (testers #2–#10) | `?cohort=` analytics scope + `cohort-quiet` named-check | Supabase `users`/`conversations` | Server-side at checkpoint |
| Self-hosted CLI (tester #1, dogfood) | `emit-decision.sh` → `.soleur/decisions.jsonl` | Tester's machine | Tester runs `alpha-metrics.sh`, pastes aggregate |

## Residency pin

If a hosted runtime ever executes plugin emit inside a Jikigai-run workspace,
`.soleur/decisions.jsonl` lands on Jikigai infrastructure — which would change
the Posture-A story this decision relies on. The hosted path today does not
run the plugin; if that changes, this ADR's residency premise must be
re-evaluated, not assumed.

## The frozen allowlist

The schema is frozen to the allowlist above. A future corpus need (the parked
System-1 eval) renegotiates the boundary deliberately — it does not creep
fields in one at a time. The corpus is a byproduct, never a requirement.

## Consequences

- Every harness produces the corpus uniformly; capture-rate equals route-rate
  by construction of prose direction (modulo LLM compliance — disclosed).
- No new Jikigai regulated data surface; `users.cohort_key` (Art. 6(1)(f),
  migration 141) is the only server-side addition.
- `alpha-metrics.sh` and `emit-decision.sh` carry a stock-macOS portability
  contract (bash 3.2, no jq/flock/date -d/sed -i/python3).
