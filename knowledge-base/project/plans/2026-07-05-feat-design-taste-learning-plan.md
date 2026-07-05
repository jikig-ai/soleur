---
title: "feat: design taste-learning — multi-variant fan-out + context-keyed taste-profile"
date: 2026-07-05
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
epic: 5983
closes: 5990
rides: 5989
branch: feat-design-taste-learning
pr: 6053
spec: knowledge-base/project/specs/feat-design-taste-learning/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-07-05-design-taste-learning-brainstorm.md
semver: minor
plan_review: 7-agent panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow, cto-devex, ux-design-lead) + fable advisor; reshaped per operator User-Challenge decision
---

# feat: design taste-learning — multi-variant + context-keyed taste-profile

✨ Wave 3 · FR7 of the gstack-adoption epic (#5983). Adapts gstack's `design-shotgun` into
Soleur's committed-knowledge, all-Claude frame: (1) multi-variant design fan-out and (2) a
committed, **context-keyed** `taste-profile.md` that learns the operator's design preferences
by **recency** (not numeric decay), with contradiction-flagging scoped to the same design
context, **loaded via the FR6 declarative context-injection hook** (#5989, PR #6035,
ADR-086-declarative-skill-context-injection).

## Overview

Soleur's two design surfaces — the `frontend-design` **skill** (coded UI) and the
`ux-design-lead` **agent** (`.pen` wireframes) — each produce a single take with no memory
across sessions. This feature fans out N parallel variants seeded by distinct aesthetic
directions, records the operator's selection into a committed `taste-profile.md`, and primes
future sessions with the learned profile via FR6 (skill) / direct-Read (agent).

**This plan was reshaped after a 7-agent plan-review panel + fable advisor** (operator
User-Challenge decision: *Reshape — context-keyed, recency*). The design-taste + simplification
panels converged that the originally-planned model (single global axis + numeric 90-day decay
+ auto-supersede) would **actively mis-learn**: an operator picking `minimalist` for a dashboard
and `maximalist` for a landing page is *context-conditioned taste*, not a contradiction, so a
context-blind model thrashes ("learned taste" → "the last thing you designed"). The reshape:

- **Context-keyed entries** `(context, axis) → value` — contradiction fires only when the *same*
  design context gets a different value (genuine signal; no cross-surface thrash).
- **Recency, not numeric decay** — most-recently-reinforced (tie-break: higher `reinforce_count`)
  primes; no confidence curve, no half-life. (The prior "90-day half-life" was mislabeled linear-
  to-zero decay hitting the floor at exactly a solo operator's design cadence.)
- **Sanitize ALL model-supplied write tokens** (context, axis, value, date) — not just `value` —
  because every token is written into the committed file FR6 re-injects (ADR-086 content-trust).
- **Agent reads, orchestrator writes** — `ux-design-lead` is an isolated Task subagent with no
  operator, so it cannot capture a selection; it READS the profile to bias designs, and the
  wireframe-approval orchestrator gate captures the pick and does the WRITE.

## Research Reconciliation — Spec vs. Codebase (+ panel reshape)

| Claim / original plan | Codebase / panel reality | Plan response |
|---|---|---|
| "loaded via FR6" for both surfaces | FR6 hook matches the **Skill** tool only (`.tool_input.skill`); `ux-design-lead` is an **agent** → hook never fires (Kieran + architecture confirmed provable) | Skill loads via `context_queries`; agent loads via direct-Read (FR6-equivalent). |
| taste-profile "loaded via FR6" | FR6 requires `git ls-files`-tracked; uncommitted path skipped | **Seed a committed `taste-profile.md`** so the path resolves day one (not gitignored — verified). |
| decaying confidence (issue AC) + single axis | **Design-taste + simplification panels:** context-blind single-axis + numeric decay mis-learns (thrash); "90-day half-life" is mislabeled linear-to-zero (0.5 at day 45) | **Reshape (operator-approved):** `(context, axis)` keying + recency ordering; drop numeric decay. Contradiction still fires (issue AC preserved), scoped to same context. |
| content-trust = validate `<value>` | **architecture-strategist (critical):** `<axis>` + `<date>` are ALSO model-supplied and written into the FR6-re-injected file → injection hole | Validate **all** tokens: context/axis allowlists, value `^[a-z][a-z0-9-]*$`, date `^\d{4}-\d{2}-\d{2}$`; reject-and-preserve; AC asserts each. |
| helper under `frontend-design/scripts/` | **architecture-strategist:** shared by the agent too = ownership inversion / "inappropriate intimacy" | **Hoist to `plugins/soleur/scripts/taste-profile-update.sh`** (plugin-shared; neither consumer owns the other's dependency). |
| helper = awk/`tr` in-place markdown surgery | **fable advisor:** fragile; test matrix explodes | Helper = **parse fenced JSON block → single jq transform → re-render whole file → atomic tmp+mv**. `last_reviewed` passes through untouched by construction. |
| agent Step 3.5 writes taste | **spec-flow (critical, G1):** agent is an isolated Task subagent with no operator → write path orphaned; no orchestrator edited | Agent READS only; the **wireframe-approval orchestrator gate** (brainstorm 3.55b / plan 2.5 §4b) captures the pick and writes. |
| enum "matches" frontend-design tone list | **CTO + Kieran + architecture:** SKILL.md:17 is open prose ("…etc."), slash-compounds → un-assertable 3-way drift | Helper's list is **canonical**; SKILL is "seeded from / documented alongside"; **value is sanitized (open), not a closed enum** (records the operator's genuine novel directions faithfully). |
| FR6 consistency test "resolves taste-profile" | **Kieran (Issue 3):** the real test asserts only `grep -qF 'knowledge-base/'` (≥1 artifact) — already true via brand-guide; doesn't verify the new entry | Add a **direct hook-invocation AC:** `printf '{"tool_input":{"skill":"soleur:frontend-design"}}' \| bash .claude/hooks/skill-context-queries.sh \| grep -qF 'taste-profile.md'`. |
| decay is "deterministic" | **Kieran (Issue 1):** reading stored decayed confidence back in compounds → path-dependent | Moot — recency reshape removes numeric confidence entirely. |
| "no C4 impact" | `agents -> kb "Reads"` (304) falsified by ux-design-lead's `.pen` writes | Broaden to `"Reads/writes"` (assert the **edge string**, not line 304 — Kieran Issue 6). Fan-out spawn stays below the C4 line (noted in ADR). |

## Data Model — `knowledge-base/product/design/taste-profile.md`

Human-legible markdown with a fenced machine block the helper owns:

````markdown
---
last_updated: 2026-07-05      # bumped on every write (automated)
last_reviewed: 2026-07-05     # human-review only — NEVER bumped by the helper
review_cadence: quarterly
owner: CPO
---
# Design Taste Profile
<!-- Machine block: edited ONLY by plugins/soleur/scripts/taste-profile-update.sh. Do not hand-edit. -->
```json
{ "schema": 1,
  "entries": [
    {"context":"dashboard","axis":"aesthetic-direction","value":"minimalist","last_reinforced":"2026-07-05","reinforce_count":2}
  ],
  "contradictions": [
    {"context":"landing-page","axis":"aesthetic-direction","old_value":"editorial","new_value":"maximalist","old_count":1,"date":"2026-07-05"}
  ] }
```
## Reinforced Aesthetics
<!-- human-readable table re-rendered from entries[] by the helper -->
## Contradiction Flags
<!-- human-readable log re-rendered from contradictions[] -->
````

- **context** ∈ fixed allowlist: `landing-page | marketing-site | dashboard | app-ui | docs | email | component`.
- **axis** ∈ fixed allowlist (v1): `aesthetic-direction`. (Axis decomposition — density/color-temp/type — deferred to v2.)
- **value**: sanitized `^[a-z][a-z0-9-]*$`, ≤40 chars (seed suggestions from frontend-design's tone list; open, not closed).
- **Priming:** for the current context, the most-recent entry per axis (tie-break higher `reinforce_count`).
- **Contradiction:** same `(context, axis)`, different `value` → append to `contradictions[]` (old value + old count + date) then supersede. No cross-context contradiction.

## Files to Create

- `knowledge-base/product/design/taste-profile.md` — seeded committed artifact (empty `entries[]`/`contradictions[]`). Committable (verified). Frontmatter `last_reviewed` set once at seed (net-new → `context-reviewed-gate.sh` exempt).
- `plugins/soleur/scripts/taste-profile-update.sh` — plugin-shared helper. Two modes: **write** `<profile> <context> <axis> <value> <today>` (validate all four tokens → parse fenced JSON → one jq transform: upsert `(context,axis)`→value + `last_reinforced=today` + `reinforce_count++`; on differing prior value append a `contradictions[]` entry → supersede → re-render → atomic tmp+mv → bump `last_updated` only); **validate** `--validate <profile>` (schema + allowlist + sanitize check; non-zero on any violation). No decay math.
- `plugins/soleur/scripts/taste-profile-update.test.sh` — git-init fixture harness (pattern: `.claude/hooks/skill-context-queries.test.sh`): upsert/reinforce, recency priming, same-context contradiction append+supersede, **cross-context NON-contradiction** (dashboard≠landing coexist), reject+preserve for out-of-allowlist context/axis, bad-format value, bad-format date, `--validate` failure, `last_reviewed` byte-unchanged, atomic-preserve-on-failure.
- `knowledge-base/engineering/architecture/decisions/ADR-089-context-keyed-taste-profile-and-agent-surface-injection.md` — rich template (new trust boundary + cross-surface decision, per AP-011). Records: (1) Agent-tool surface gap + agent-reads/orchestrator-writes (extends `ADR-086-declarative-skill-context-injection` §Consequences — **full slug**, bare "086" is ambiguous per the triple-collision); (2) context-keyed recency model (recency over numeric decay; `(context,axis)` over global axis to prevent thrash); (3) note fan-out spawn stays below the C4 container line; (4) note injected values carry no confidence number (recency is date-based, read faithfully). Flag the ADR-086 triple-collision as out-of-scope tracking (do not renumber).

## Files to Edit

- `plugins/soleur/skills/frontend-design/SKILL.md` — add `- knowledge-base/product/design/taste-profile.md` to `context_queries`; add a `### Multi-Variant Fan-Out` section (identical grep-anchor, shared with the agent) + a `### Recording Taste` section. Read path runs `taste-profile-update.sh --validate` (fail → design with no bias); biases the N sub-agent seeds (passed via **prompt text**) to the current context's recent entries; **mode predicate**: interactive selection is captured via natural conversation (NOT `AskUserQuestion`); if no operator turn is available (headless/nested Task) → auto-select top-recency + **no write**. Empty-profile fallback: N distinct enum seeds. On selection → call the helper with the current context. Link the helper (`[taste-profile-update.sh](../../scripts/taste-profile-update.sh)`). **No `description:` change** → word budget untouched.
- `plugins/soleur/agents/product/design/ux-design-lead.md` — pre-Step-1 direct-Read + `--validate` of the taste-profile (bias only, fail→no-bias); a `### Multi-Variant Fan-Out` section (same anchor) at Step 1.5; **explicit "this agent never writes taste — the orchestrator does"** directive (mirroring Step 3 item 5). Returns variants + a machine-readable selection-candidate. Honor existing HARD GATEs.
- `plugins/soleur/skills/brainstorm/SKILL.md` (Phase 3.55b) **and** `plugins/soleur/skills/plan/SKILL.md` (Phase 2.5 §4b) — at the wireframe **approve** branch, after operator approval, call `taste-profile-update.sh` with the design context + the approved variant's aesthetic direction. This is the agent surface's real writer path. (Interactive arm only; headless arm already no-pause → no write.)
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `agents -> kb "Reads"` → `agents -> kb "Reads/writes"` (assert the edge string).
- `README.md` / `plugin.json` — **no change** (no new skill/agent/command; scripts + ADR are not counted). Confirm counts unchanged.

## Decisions (post-review)

| Ref | Decision |
|---|---|
| Model | `(context, axis) → value`, recency-ordered; no numeric confidence/decay |
| OQ1 helper | Plugin-shared `plugins/soleur/scripts/taste-profile-update.sh`, jq-over-fenced-JSON, atomic tmp+mv, `--validate` read-path mode |
| OQ2 decay | **Removed** — recency (`last_reinforced`, tie-break `reinforce_count`) replaces the numeric curve |
| OQ3 value | Sanitized open token (`^[a-z][a-z0-9-]*$`), not a closed enum; helper list is canonical seed suggestions; context+axis are closed allowlists |
| OQ4 negative evidence | Deferred (v2) |
| Axis decomposition | Deferred (v2) — single `aesthetic-direction` axis in v1; ux-design-lead's density/color-temp/type sub-axes are the follow-up |
| Agent write | **Orchestrator writes** at the wireframe-approval gate; agent reads only |
| Mode predicate | Interactive = natural-conversation selection; no operator turn (headless/nested Task) = auto-select top-recency, no write. Never `AskUserQuestion` in a design surface. |
| Empty profile | Seeding + headless fall back to N distinct enum seeds / no-op-no-write |
| Surface scope | CLI-first skill FR6 load (web Concierge gap deferred, ADR-086 tracked); agent direct-Read + orchestrator write are surface-independent |
| N variants | 3 (hardcoded; not parameterized) |

## Implementation Phases

**Phase 0 — Preconditions (done):** FR6 hook present; committable; ADR-089 free; `model.c4` edge located; freshness gate net-new-exempt confirmed.

**Phase 1 — Helper + tests (contract first, TDD).** `taste-profile-update.test.sh` RED → `taste-profile-update.sh` GREEN. jq-over-fenced-JSON; validate all four tokens (allowlist context/axis, sanitize value, format date); atomic tmp+mv; `last_updated`-only; `--validate` mode. Idioms: awk `c==1` to slice the fenced block; jq for the transform.

**Phase 2 — Seed the committed `taste-profile.md`** (empty arrays; frontmatter). Commit so FR6 resolves.

**Phase 3 — Wire `frontend-design` skill** (context_queries + fan-out + record-taste + mode predicate + `--validate`).

**Phase 4 — Wire `ux-design-lead` agent** (direct-Read + `--validate` + fan-out; explicit no-write directive).

**Phase 5 — Wire the orchestrator write** at brainstorm 3.55b + plan 2.5 §4b approve branches.

**Phase 6 — ADR-089 + C4** (broaden edge; run `c4-code-syntax.test.ts` + `c4-render.test.ts`).

**Phase 7 — Verify** (`taste-profile-update.test.sh`; the direct FR6 hook-invocation check; AC checks).

## Observability

The helper is under `plugins/*/scripts/` (gate fires). It is an **operator-local interactive tool**, not a dark server/cron surface — the running agent sees stdout/stderr in-session.

```yaml
liveness_signal:
  what: helper invoked on operator variant-selection / wireframe-approval
  cadence: on-demand (no scheduled run)
  alert_target: none (interactive; failure visible in-session)
  configured_in: frontend-design/SKILL.md, brainstorm/plan orchestrator approve gates
error_reporting:
  destination: stderr + non-zero exit surfaced inline by the caller
  fail_loud: true (validation failure exits non-zero; original preserved)
failure_modes:
  - mode: out-of-allowlist context/axis, or metachar/whitespace value, or bad date
    detection: token validation before write; --validate read-path check
    alert_route: non-zero exit + sanitized stderr, in-session; consumer falls back to no-bias
  - mode: malformed fenced JSON / partial write
    detection: jq parse-then-validate; tmp discarded on failure
    alert_route: non-zero exit; taste-profile.md untouched
  - mode: same-context contradiction
    detection: same (context,axis), differing value
    alert_route: appended to contradictions[] (durable, greppable) + in-session echo
logs:
  where: taste-profile.md contradictions[] / Contradiction Flags section; helper stderr
  retention: committed to git (permanent)
discoverability_test:
  command: bash plugins/soleur/scripts/taste-profile-update.test.sh
  expected_output: all cases pass (upsert, recency, same-context contradiction, cross-context non-contradiction, token rejection, --validate, last_reviewed-untouched, atomic-preserve)
```

## Infrastructure (IaC)

None — no server/secret/vendor/DNS/cron/runtime process. Recency is write-time. IaC gate skipped.

## GDPR / Compliance

**Regulated-data surface: none.** Trigger (b) (`single-user incident`) fires the *consideration*; assessment: the taste-profile stores the operator's own **design-aesthetic metadata** (context/axis/value enums + dates), no data subject, no PII, no special category, no egress. Token sanitization + the closed context/axis allowlists block whitespace/multi-word free-form capture (a single hyphenated proper noun remains syntactically possible but is git-revertable, not silent free-text capture); the helper validates every write and the consumers `--validate` on read. No new sub-processor (all-Claude). CLO carry-forward cleared egress. No `compliance-posture.md` write.

## Architecture Decision (ADR/C4)

### ADR
Create **ADR-089** (rich template; provisional ordinal — `/ship` re-verifies next-free before merge; the ADR-086 triple-collision is pre-existing and flagged as out-of-scope tracking). Decisions: agent-surface injection gap + agent-reads/orchestrator-writes; context-keyed recency taste model; token-sanitization trust boundary. References `ADR-086-declarative-skill-context-injection` by **full slug**. `status: Accepted`.

### C4 views
No new element. Enumeration checked against all three `.c4` files: external human actor = existing `founder` (model.c4:8); no new vendor/system (all-Claude); containers `skills`/`agents`/`hooks`/`kb` all present; access edges `hooks -> kb` (302), `skills -> kb "Reads/writes"` (303) model the load+write. **Only** falsified description: `agents -> kb "Reads"` (304) → `"Reads/writes"` (ux-design-lead writes `.pen`; broaden is symmetric with 303). Multi-variant fan-out is a runtime spawn at container granularity, below the C4 line (the model shows spawns only at `api -> claude`); recorded in ADR-089 rather than adding a component-level edge.

### Sequencing
ADR + C4 land in this PR (Phase 6). No deferral.

## Domain Review

**Domains relevant:** Engineering, Legal (carried forward from epic #5983 brainstorm).

### Engineering (CTO)
**Status:** reviewed (carry-forward + FR7 delta + devex panel)
**Assessment:** Ride FR6 (landed), no bespoke loader. Low blast radius — additive frontmatter/agent-body/orchestrator-gate + one plugin-shared tested helper + one committed artifact; no product-runtime code; FR6 fail-open. Devex-panel adjustments folded: helper hoisted to plugin-shared; value sanitized (not a drifting enum-vs-prose "match"); fan-out anchor shared across both files.

### Legal (CLO)
**Status:** reviewed (carry-forward)
**Assessment:** committed design-preference metadata, no egress, no PII. Redaction gate (#5987) governs egress — not tripped. Closed context/axis allowlists + value sanitization keep operator-customer content out.

### Product/UX Gate
**Tier:** none — no UI-surface file in Files to Create/Edit (internal tooling that *generates* UI). Consistent with the brainstorm Phase 3.55 skip.
**Pencil available:** N/A (no UI surface authored by this plan)

## User-Brand Impact

**If this lands broken, the user experiences:** design sessions primed with a wrong learned taste — from (a) a malformed write (mitigated by context-keying + read-path `--validate` fail→no-bias, never a corrupt prime), or (b) a **headless false-write**: a `/work`/`one-shot` design run has no operator to pick, so a recorded selection would be machine-invented. "No write in headless" is a caller-prose contract at all three write sites (`frontend-design` Recording + brainstorm 3.55b + plan 2.5 §4b); a spurious headless write produces a *valid* token `--validate` cannot catch, but it is a single-token, git-revertable entry the consumers only *bias* (never hard-constrain) from.
**If this leaks, the user's data is exposed via:** the `taste-profile.md` artifact — mitigated by closed context/axis allowlists + value sanitization (blocks whitespace/multi-word free-form; a single hyphenated proper noun like a client name remains possible but is git-revertable, not silent capture), helper validation (`--validate` covers the whole machine block — entries[] + contradictions[]), consumers biasing from the validated JSON block (not the unvalidated prose table), and ADR-086's committed-only/path-contained FR6 fencing (fail-open, cannot fail-closed skills).
**Brand-survival threshold:** single-user incident.

`requires_cpo_signoff: true` — CPO framing carried from the epic brainstorm; `user-impact-reviewer` invoked at review time.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1 (variants — shared anchor):** both `frontend-design/SKILL.md` and `ux-design-lead.md` contain the literal `### Multi-Variant Fan-Out`. Verify: `grep -c '^### Multi-Variant Fan-Out' <file>` = 1 each.
- [ ] **AC2 (persist + FR6 load):** `context_queries` in `frontend-design/SKILL.md` includes the taste-profile path; the file is `git ls-files`-tracked; the hook injects it. Verify: `git ls-files --error-unmatch knowledge-base/product/design/taste-profile.md` exits 0 **AND** `printf '{"tool_input":{"skill":"soleur:frontend-design"}}' | bash .claude/hooks/skill-context-queries.sh | grep -qF 'taste-profile.md'`.
- [ ] **AC3 (agent reads, does not write):** `ux-design-lead.md` contains a Read directive for the taste-profile AND an explicit "this agent never writes taste — the orchestrator does" line. Verify: both grep.
- [ ] **AC4 (contradiction — same context only):** test asserts same-`(context,axis)` differing value appends a `contradictions[]` entry (old value+count+date) + supersedes, AND a different-context selection does NOT flag. Both pass.
- [ ] **AC5 (all tokens sanitized):** helper rejects (non-zero, original byte-preserved) an out-of-allowlist `context`, out-of-allowlist `axis`, metachar/whitespace `value`, and malformed `date`. Test asserts each of the four.
- [ ] **AC6 (recency, no decay):** priming selects the most-recent entry per `(context,axis)` (tie-break `reinforce_count`); no `confidence`/`HALFLIFE` tokens exist in the helper or profile. Verify: `! grep -qiE 'halflife|confidence' plugins/soleur/scripts/taste-profile-update.sh`.
- [ ] **AC7 (freshness):** an automated write bumps `last_updated` only; `last_reviewed` byte-unchanged. Test asserts.
- [ ] **AC8 (end-to-end, per surface):** (skill) a simulated in-session selection drives the helper call and adds the `(context,axis)` entry; (agent) a simulated orchestrator approve-branch call adds the entry. Both post-conditions asserted (not grep-presence).
- [ ] **AC9 (read-path validate):** both consumers invoke `taste-profile-update.sh --validate` before biasing, and fall back to no-bias on non-zero. Verify: grep each consumer for `--validate`.
- [ ] **AC10 (helper + FR6 tests):** `taste-profile-update.test.sh` passes; `.claude/hooks/skill-context-queries.test.sh` passes.
- [ ] **AC11 (C4):** `model.c4` contains `agents -> kb "Reads/writes"` (assert the string); `c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
- [ ] **AC12 (ADR):** `ADR-089-*.md` exists, status Accepted, references `ADR-086-declarative-skill-context-injection` by full slug, records the three decisions; 086 collision flagged out-of-scope.
- [ ] **AC13 (no component drift):** README counts + `plugin.json` unchanged.

### Post-merge (operator)
- None. (Web-Concierge FR6 surface port is a deferred follow-up, not a merge-gated step.)

## Deferred / Tracking (file as issues at ship)

- **Axis decomposition** — density / color-temperature / type-style / corners sub-axes (ux-design-lead: the person-invariant signal that transfers across projects). Re-eval after the single-axis loop has real reinforcement data.
- **Negative-evidence learning** (OQ4) — record rejected variants to speed convergence.
- **Web-Concierge FR6 skill-load port** — co-file onto ADR-086's tracked surface-parity follow-up.
- **ADR-086 ordinal triple-collision** — housekeeping renumber of two of the three 086 files.

## Test Scenarios

- Upsert+reinforce: select `dashboard/aesthetic-direction/minimalist` twice → one entry, `reinforce_count=2`, `last_reinforced`=today, `last_updated` bumped, `last_reviewed` unchanged.
- Recency prime: `dashboard→minimalist@t1`, `dashboard→editorial@t2` (t2>t1) → priming for `dashboard` returns `editorial`.
- Same-context contradiction: `landing-page→editorial` then `landing-page→maximalist` → `contradictions[]` gains `{old:editorial, old_count, date}`, entry becomes `maximalist`.
- Cross-context NON-contradiction: `dashboard→minimalist` + `landing-page→maximalist` → both coexist, `contradictions[]` empty.
- Token reject: `context=prod; rm -rf /` (out of allowlist) → non-zero exit, file byte-identical.
- Headless: fan-out auto-selects top-recency for the context, **no write**.

## Sharp Edges

- Empty `## User-Brand Impact` fails `deepen-plan` Phase 4.6 — filled.
- The helper is plugin-shared under `plugins/soleur/scripts/`; both consumers reference it by that stable path. If moved, update the skill, agent, and both orchestrator gates.
- FR6 is **CLI-only** for the skill — the agent's direct-Read + the orchestrator write are the surface-independent paths; do not claim the skill auto-primes in web Concierge.
- Never bump `last_reviewed` from the helper — `context-reviewed-gate.sh` denies commits changing it without a `Context-Reviewed:` trailer.
- **Fan-out sub-agents don't inherit Pencil MCP** (Kieran): each `ux-design-lead` fan-out sub-agent producing a `.pen` must have Pencil MCP available, or the agent's 0-byte HARD GATE fires per variant → N empty files. Confirm MCP availability before fan-out, or degrade to sequential single-variant.
- Never `AskUserQuestion` inside a design surface (skill fan-out or agent) — a nested Task subagent hangs; interactive selection is natural-conversation, headless is auto-select-no-write.
- Provisional ADR-089 ordinal: `/ship` re-verifies next-free against `origin/main` before merge.
