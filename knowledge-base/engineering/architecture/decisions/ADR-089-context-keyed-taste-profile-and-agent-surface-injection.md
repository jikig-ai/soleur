# ADR-089: Context-keyed design taste-profile + agent-surface context injection

- **Status:** Accepted
- **Date:** 2026-07-05
- **Issue:** [#5990](https://github.com/jikig-ai/soleur/issues/5990) (gstack-adoption epic [#5983](https://github.com/jikig-ai/soleur/issues/5983), Wave 3 · FR7)
- **Extends:** [ADR-086-declarative-skill-context-injection](./ADR-086-declarative-skill-context-injection.md) — the taste-profile is the first real `context_queries` consumer that ADR named; this ADR records the consequences of that consumer being *agent-writable* and *cross-surface*.
- **Relationship to ADR-053 (all-Claude model policy):** the multi-variant fan-out uses parallel Claude sub-agents, not multiple vendors — gstack `design-shotgun` is a multi-model technique; this is its all-Claude adaptation.

## Context

gstack's `design-shotgun` fans out design variants and learns operator taste, storing state per-machine (`~/.gstack`) keyed on a single global preference. Soleur wanted the capability in its committed-knowledge frame (#5990, riding the FR6 declarative context-injection hook from ADR-086), targeting a **non-technical solo operator** who designs across different surface types.

A 7-agent plan-review panel found the first design (single global "aesthetic-direction" axis + numeric 90-day decay + auto-supersede) would **actively mis-learn**: an operator who prefers `minimalist` for a dashboard and `maximalist` for a landing page is expressing *context-conditioned* taste, not a contradiction — a context-blind model thrashes and the learned profile degenerates to "the last thing you designed." Separately, the numeric decay was mislabeled (linear-to-zero at the operator's own cadence) and false precision for a file that holds <10 reinforcements for a long time.

Two mechanism questions had no prior decision:
- **OQ-A:** how is learned taste keyed so it neither thrashes nor over-fits?
- **OQ-B:** how does the profile reach *both* design surfaces — the `frontend-design` **skill** and the `ux-design-lead` **agent** — given ADR-086's hook only fires for the `Skill` tool?

## Decision

**1. Context-keyed, recency-ordered taste model.** Entries are keyed by `(context, axis) → value`, where `context` ∈ a closed enum (`landing-page | marketing-site | dashboard | app-ui | docs | email | component`) and `axis` ∈ a closed enum (`aesthetic-direction` in v1). Ordering is by **recency** (`last_reinforced`, tie-break `reinforce_count`) — there is **no numeric confidence/decay**. A contradiction fires only when the *same* `(context, axis)` is reinforced with a different value; resolution is supersede, logged to `contradictions[]`. This kills the cross-surface thrash while preserving #5990's "contradiction flag fires" AC (now meaningful).

**2. Agent-surface injection gap → agent reads, orchestrator writes.** ADR-086's `PostToolUse(Skill)` hook is structurally unreachable for Agent-tool invocations, and the `ux-design-lead` agent runs as an isolated Task subagent with **no operator** — it cannot capture a selection. So:
- the `frontend-design` **skill** loads the profile via `context_queries` (FR6) and records the operator's selection in-session;
- the `ux-design-lead` **agent** loads the profile via an explicit **direct Read** (surface-independent — it also works where FR6 does not, e.g. web Concierge) and **never writes**; the wireframe-approval **orchestrator** gate (`brainstorm` Phase 3.55b / `plan` Phase 2.5 §4b) captures the operator's pick and does the write.

This is *not* a bespoke loader (ADR-086 forbade re-building the mechanism) — the artifact, the write helper, and the schema are shared; only the *load-injection* differs by surface class.

**3. Token sanitization is the content-trust boundary.** ADR-086 §Consequences mandates that a consumer pointing `context_queries` at agent-writable content MUST sanitize its own content. Because the file is written into FR6-re-injected context, **every** model-supplied token — `context`, `axis`, `value`, `date`, not just `value` — is validated by the single shared helper (`plugins/soleur/scripts/taste-profile-update.sh`): closed allowlists for context/axis, `^[a-z][a-z0-9-]{0,39}$` for value, `^\d{4}-\d{2}-\d{2}$` for date, reject-and-preserve on any violation. Consumers also run the helper's `--validate` mode on read and fall back to **no bias** on failure (fail-open, mirroring FR6). The helper is the only writer; it re-renders the whole file from a single jq transform over a fenced JSON block and bumps `last_updated` only (never `last_reviewed` — freshness convention).

## Consequences

- **Recency values are read pre-... nothing** — there is no decayed number to be stale; the injected `last_reinforced` date is read faithfully. (This removes the "injected confidence is pre-decay" wrinkle a numeric model would have carried.)
- **Multi-variant fan-out stays below the C4 container line.** The `.c4` model represents runtime spawns only at `api -> claude`; the design fan-out is a runtime spawn at container granularity and is recorded here rather than as a new component edge. The one C4 change this feature requires is broadening `agents -> kb "Reads"` → `"Reads/writes"` (the `ux-design-lead` agent writes `.pen` files today and, via the orchestrator path, taste-profile).
- **CLI-first for the skill surface.** The skill's FR6 auto-load is CLI-only (web Concierge runs `settingSources:[]`, ADR-086 §Surface scope). The agent's direct-Read is surface-independent, so the agent path already covers Concierge; a skill-side web port is deferred onto ADR-086's tracked surface-parity follow-up.
- **Deferred (v2):** axis decomposition (density / color-temperature / type-style sub-axes carry more person-invariant, cross-project signal than the tone bundle), negative-evidence learning.

## Alternatives Considered

- **Single global axis + numeric decay (original plan).** Rejected — mis-learns for a multi-surface operator (thrash); numeric decay is false precision + mislabeled for a <10-entry file.
- **Free-form value (no enum on `value`).** The value is sanitized-but-open (`^[a-z][a-z0-9-]*$`) rather than a closed enum, so the operator's genuine novel directions record faithfully (the parent skill's tone list is explicitly open — "…etc."); `context`/`axis` stay closed because contradiction-scoping and injection-safety need them bounded.
- **Agent writes its own taste (Step 3.5 in the agent).** Rejected — the agent has no operator (isolated Task subagent); the write would be orphaned or auto-select-without-signal. The orchestrator owns the operator interaction, so it owns the write.
- **Scheduled decay cron.** Rejected — infra + a recurring job for a single-operator artifact; recency is write-time and fail-visible.

## Housekeeping note (out of scope)

Three ADRs on `main` share the number **086** (`declarative-skill-context-injection`, `fail-closed-redaction-engine-contract`, `freshness-last-reviewed-source-fix-and-audit-tripwire`). This ADR references the intended one by full slug. Renumbering two of the three is tracked as a separate housekeeping issue — not done here.

## Verification

- `plugins/soleur/scripts/taste-profile-update.test.sh` (fixture harness): upsert/reinforce, recency priming, same-context contradiction + supersede, cross-context non-contradiction, token rejection (context/axis/value/date), `--validate`, `last_reviewed` byte-unchanged, atomic-preserve.
- `.claude/hooks/skill-context-queries.test.sh` (FR6 mechanism unchanged) + a direct hook-invocation check that `soleur:frontend-design` resolves the taste-profile path.
- C4: `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.
