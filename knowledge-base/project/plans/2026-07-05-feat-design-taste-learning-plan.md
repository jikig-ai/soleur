---
title: "feat: design taste-learning — multi-variant fan-out + committed taste-profile"
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
---

# feat: design taste-learning — multi-variant + committed taste-profile

✨ Wave 3 · FR7 of the gstack-adoption epic (#5983). Adapts gstack's `design-shotgun`
into Soleur's committed-knowledge, all-Claude frame: (1) multi-variant design fan-out and
(2) a committed `taste-profile.md` that learns the operator's design preferences with
write-time-recomputed decaying confidence + contradiction-flagging, **loaded via the FR6
declarative context-injection hook** (#5989, merged PR #6035, ADR-086).

## Overview

Soleur's two design surfaces — the `frontend-design` **skill** (coded UI) and the
`ux-design-lead` **agent** (`.pen` wireframes) — each produce a single take with no memory
across sessions. This feature fans out N parallel variants seeded by distinct aesthetic
directions, records the operator's selection into a committed `taste-profile.md`, decays
confidence at write time, and primes future sessions with the learned profile via FR6.

Three operator-locked decisions (brainstorm Phase 2) drive the design:
- **Write-time decay** (not a cron) — FR6 injects a *static pointer* (ADR-086), so decay is
  baked into explicit `confidence` values and recomputed/rewritten at session start.
- **Parallel sub-agent fan-out** (not multi-model) — all-Claude per ADR-053.
- **Auto-supersede on contradiction** — the flag still *fires* (detect + log the event),
  then the newest selection supersedes.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| "loaded via FR6" for both surfaces | FR6 hook (`.claude/hooks/skill-context-queries.sh`) matches the **Skill** tool only; `ux-design-lead` is an **agent** (Agent tool) → hook never fires | Skill loads via `context_queries`; agent loads via a direct-Read directive (FR6-equivalent, not a bespoke loader). ADR-086 §Surface scope already anticipates per-consumer surface choice. |
| taste-profile "loaded via FR6" | FR6 requires the path be `git ls-files`-tracked (committed-only); an uncommitted path is skipped | **Seed a committed `taste-profile.md` in this PR** so the `context_queries` path resolves from day one. |
| decaying confidence | ADR-086: pointer-only injection, no load-time compute | Write-time recompute; `confidence` + `last_reinforced` stored explicitly. |
| taste-profile is agent-writable | **ADR-086 §Consequences (content-trust ≠ path-trust):** "consumers MUST sanitize/validate their own content" | Constrain entries to a **fixed enum vocabulary** (no free-form text) → eliminates the injection surface AND makes contradiction detection reliable (elevates brainstorm OQ3 to a decision). Helper sanitizes/validates every write. |
| decay dating | Freshness convention (ADR-086-freshness) + `context-reviewed-gate.sh` PreToolUse hook: `last_updated`=any write, `last_reviewed`=human-review-only | Automated decay/selection writes bump `last_updated` only, **never** `last_reviewed`; seed commit is net-new (gate-exempt). |
| fan-out via sub-agents | Agent-tool sub-agents run isolated — they do NOT inherit the parent's FR6 injection (learning 2026-06-30) | The orchestrator passes each variant sub-agent its aesthetic seed + taste bias via **prompt text**, not FR6. |
| "no C4 impact" | `model.c4:304` `agents -> kb "Reads"` is falsified by ux-design-lead writing taste-profile.md (already writes `.pen` too) | Broaden that one edge to `"Reads/writes"`; no new elements/actors/systems (operator = existing `founder` actor; no new vendor; skills/agents/hooks/kb containers all exist). |
| genuinely-absent taste artifact | grep confirms zero design-taste/design-variant/preference artifacts (only ADR-084 *decision* "taste") | "New capability" framing grounded. |

## Files to Create

- `knowledge-base/product/design/taste-profile.md` — seeded committed artifact (frontmatter + empty `## Reinforced Aesthetics` + `## Contradiction Flags` + an embedded schema comment). Confirmed committable (`git check-ignore` → not ignored).
- `plugins/soleur/skills/frontend-design/scripts/taste-profile-update.sh` — shared write helper: parse frontmatter (awk `c==1` idiom), recompute decay, detect+log contradiction, auto-supersede, **validate against the fixed enum + sanitize**, atomic tmp+mv write, bump `last_updated` only.
- `plugins/soleur/skills/frontend-design/scripts/taste-profile-update.test.sh` — git-init fixture harness (pattern: `.claude/hooks/skill-context-queries.test.sh`): decay math, reinforce-reset, contradiction detect+log+supersede, enum-reject of out-of-vocabulary/injection input, atomic-write-preserves-original-on-failure, `last_reviewed`-untouched.
- `knowledge-base/engineering/architecture/decisions/ADR-087-committed-taste-profile-learned-design-preferences.md` — new ADR (provisional 087; **note the pre-existing ADR-086 triple-collision** — flag as out-of-scope tracking, do not renumber here). Records: skill-vs-agent load asymmetry, write-time-decay-over-cron, fixed-enum content-trust; extends ADR-086 §Consequences with the agent-surface observation.

## Files to Edit

- `plugins/soleur/skills/frontend-design/SKILL.md` — add `- knowledge-base/product/design/taste-profile.md` to `context_queries`; add a `## Multi-Variant Fan-Out` section (spawn N Agent sub-agents seeded by distinct directions biased to the top taste-profile entries, passing the seed via prompt text) and a `## Recording Taste` section (on operator selection → invoke the helper). Link the helper script per skill-compliance (`[taste-profile-update.sh](./scripts/taste-profile-update.sh)`). **No `description:` change** → word-budget untouched.
- `plugins/soleur/agents/product/design/ux-design-lead.md` — add a pre-Step-1 direct-Read directive ("Read `knowledge-base/product/design/taste-profile.md` if present; use top-confidence directions as secondary constraints alongside brand-guide"); add a Step 1.5 variant fan-out; add a Step 3.5 selection-capture invoking the helper. Honor existing HARD GATEs (output path, size gates).
- `knowledge-base/engineering/architecture/diagrams/model.c4` — line 304 `agents -> kb "Reads"` → `agents -> kb "Reads/writes"`.
- `README.md` / `plugin.json` — **no change** (no new skill/agent/command; scripts + ADR are not counted components). Pre-commit checklist: confirm counts unchanged.

## Decisions (brainstorm OQs → resolved)

| Ref | Decision |
|---|---|
| Location | `knowledge-base/product/design/taste-profile.md` |
| OQ1 write path | **Shared jq+bash helper** (decay + contradiction + sanitize + atomic write are non-trivial and MUST be identical across skill+agent per TR3, and deterministic per TR2 — one tested script beats two prose copies that drift) |
| OQ2 decay | Linear-to-floor: `confidence = max(FLOOR, confidence * (1 - days_since_reinforced / HALFLIFE_DAYS))`, `HALFLIFE_DAYS=90` (matches quarterly cadence), `FLOOR=0.1`; reselect resets to `1.0`. Deterministic — date passed in as an arg (no `Date.now()`). |
| OQ3 vocabulary | **Fixed enum** aesthetic-direction axis seeded from `frontend-design`'s tone list (brutally-minimal, maximalist, retro-futuristic, organic, luxury-refined, playful, editorial, brutalist, art-deco, soft-pastel, industrial). Extensible to secondary axes later. Fixed enum = content-trust-safe + reliable contradiction detection. |
| OQ4 negative evidence | MVP records **positive** (selected) evidence only; rejected-variant negative evidence deferred (non-goal). |
| OQ5 rebase | Done — branch base already contains PR #6035 (FR6 hook verified present). |
| Surface scope | **CLI-first**: the skill's FR6 load is CLI-only (web Concierge runs `settingSources:[]`, ADR-086 §Surface scope); the agent's direct-Read is surface-independent. Accept the Concierge skill-load gap; **defer web port** to a tracked follow-up (co-filed with ADR-086's existing deferred surface follow-up). |
| N variants | Default 3 (parameterizable). |
| Headless mode | Fan-out generates variants; auto-selects the highest-confidence direction and does **NOT** write reinforcement (no operator signal = no learning). Mirrors the wireframe-review mode branch. |

## Implementation Phases

**Phase 0 — Preconditions (mostly complete):** FR6 hook present ✓, taste-profile committable ✓, ADR-087 free ✓, `model.c4:304` located ✓, enum sourced from `frontend-design` tone list ✓. Confirm `taste-profile-update.sh` invocation form with a fixture before wiring call sites.

**Phase 1 — Helper + tests (contract first, TDD).** Write `taste-profile-update.test.sh` RED, then `taste-profile-update.sh` GREEN. Helper contract: `taste-profile-update.sh <profile-path> <axis> <value> <today-YYYY-MM-DD>`; validates `<value>` ∈ enum (reject + non-zero exit otherwise, sanitizing the echoed value), recomputes decay across all entries, reinforces/inserts the selected entry (`confidence=1.0`, `last_reinforced=<today>`), detects same-axis contradiction (existing high-confidence entry with a different value) → appends a `## Contradiction Flags` line (flag fires) → supersedes, bumps frontmatter `last_updated` only, writes atomically (tmp + `mv`), preserves the original on any validation failure. Idioms: awk `c==1` frontmatter parse; `tr ',' '\n' | while IFS= read -r` for multi-value (never `tr -d ' '`). **Deterministic** (date is an arg).

**Phase 2 — Seed the committed artifact.** Create `taste-profile.md` (frontmatter `last_updated`/`last_reviewed`/`review_cadence: quarterly`/`owner: CPO`, empty `## Reinforced Aesthetics` table, empty `## Contradiction Flags`, schema comment). Commit so the FR6 path resolves.

**Phase 3 — Wire `frontend-design` skill.** Add the `context_queries` entry; add fan-out + record-taste sections (mode-branch: interactive selection vs headless auto-select-no-write); link the helper.

**Phase 4 — Wire `ux-design-lead` agent.** Direct-Read directive + Step 1.5 fan-out + Step 3.5 helper call. The agent passes each variant's aesthetic seed via prompt text (sub-agents don't inherit FR6).

**Phase 5 — ADR-087 + C4.** Author ADR-087 (extends ADR-086; flags the 086 triple-collision as out-of-scope tracking). Broaden `model.c4:304` to `Reads/writes`; run the C4 validation tests (`apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts`).

**Phase 6 — Verify.** Run `taste-profile-update.test.sh`; run `.claude/hooks/skill-context-queries.test.sh` (FR6 consistency — pilot resolves ≥1 artifact, now also taste-profile via frontend-design); AC checks below.

## Observability

The `taste-profile-update.sh` helper is under `plugins/*/scripts/` (gate fires). It is an **operator-local interactive tool**, not a dark server/cron surface — the agent running it sees stdout/stderr in-session.

```yaml
liveness_signal:
  what: helper invoked on operator variant-selection during a design session
  cadence: on-demand (no scheduled run)
  alert_target: none (interactive; failure is visible in-session)
  configured_in: frontend-design/SKILL.md + ux-design-lead.md call sites
error_reporting:
  destination: stderr + non-zero exit surfaced inline by the calling skill/agent
  fail_loud: true (validation failure exits non-zero, original file preserved)
failure_modes:
  - mode: out-of-enum / injection value in evidence
    detection: enum validation before write
    alert_route: non-zero exit + sanitized stderr message, in-session
  - mode: malformed frontmatter / partial write
    detection: parse-then-validate before atomic mv; tmp file discarded on failure
    alert_route: non-zero exit; original taste-profile.md untouched
  - mode: contradiction on same axis
    detection: same-axis differing high-confidence entry
    alert_route: logged to the `## Contradiction Flags` section (durable, greppable)
logs:
  where: taste-profile.md `## Contradiction Flags` section (event log); helper stderr (errors)
  retention: committed to git (permanent)
discoverability_test:
  command: bash plugins/soleur/skills/frontend-design/scripts/taste-profile-update.test.sh
  expected_output: all cases pass (decay, reinforce, contradiction+supersede, enum-reject, atomic-preserve, last_reviewed-untouched)
```

## Infrastructure (IaC)

None — no server, secret, vendor, DNS, cron, or persistent runtime process. Decay is write-time (no cron). IaC gate skipped.

## GDPR / Compliance

**Regulated-data surface: none.** Trigger (b) (`single-user incident` declared) fires the gate *consideration*; assessment: the taste-profile stores the operator's own **design-aesthetic metadata** (enum axis/value + selection date), no data subject, no PII, no special category, no egress. FR2 + the fixed-enum vocabulary structurally prevent free-form personal-data capture; the helper sanitizes every write. No new sub-processor (all-Claude). CLO carry-forward (below) cleared egress. No `compliance-posture.md` write needed.

## Architecture Decision (ADR/C4)

### ADR
- **Create ADR-087** (provisional ordinal — next free after the ADR-086 triple; the 086 collision is pre-existing and flagged as a separate out-of-scope tracking item, not renumbered here). Decision: committed `taste-profile.md` of learned design preferences, write-time-decayed, fixed-enum-vocabulary (content-trust-safe per ADR-086), loaded via FR6 (skill) / direct-Read (agent). **Extends** ADR-086 §Consequences with the agent-surface observation (the `Skill` matcher does not reach Agent-tool invocations). `status: Accepted` — the decision is true at merge (no soak gate).

### C4 views
- **Container/Component:** no new element. Enumeration checked against all three `.c4` files: external human actor = existing `founder` actor (model.c4:8); no new external system/vendor (all-Claude); no new container (`skills`, `agents`, `hooks`, `kb` all present); access-relationships `hooks -> kb` (context_queries injection, model.c4:302) and `skills -> kb "Reads/writes"` (303) already model the load + write paths. The **only** falsified description is `agents -> kb "Reads"` (304) — ux-design-lead now writes taste-profile.md (and already writes `.pen`). Fix: broaden to `"Reads/writes"`. This is a correctness edit the change requires, not a new view.

### Sequencing
ADR + C4 land in this PR (Phase 5). No deferral.

## Domain Review

**Domains relevant:** Engineering, Legal (carried forward from epic #5983 brainstorm `## Domain Assessments`).

### Engineering (CTO)
**Status:** reviewed (carry-forward + FR7 delta)
**Assessment:** Ride FR6 (landed), no bespoke loader. FR7 delta: FR6 Skill-matcher does not reach the agent surface → direct-Read; write-time decay forced by pointer-only injection; fan-out sub-agents need the taste bias passed via prompt (isolation). Low blast radius — additive frontmatter + agent-body + one committed artifact + one tested helper; no shared-hook edits, no product-runtime code, FR6 is fail-open by construction.

### Legal (CLO)
**Status:** reviewed (carry-forward)
**Assessment:** taste-profile is committed design-preference metadata, no egress to any sub-processor, no PII. Redaction gate (#5987) governs *egress* features — not tripped. Fixed-enum + FR2 keep operator-customer content out of the artifact.

### Product/UX Gate
**Tier:** none
**Decision:** N/A — no UI-surface file in Files to Create/Edit (internal tooling that *generates* UI; does not *add* a product page/component/modal). Mechanical UI-surface override did not fire. Consistent with the brainstorm's Phase 3.55 skip.
**Pencil available:** N/A (no UI surface)

## User-Brand Impact

**If this lands broken, the user experiences:** design sessions primed with a wrong learned taste (a malformed decay/supersede write biasing every future `frontend-design`/`ux-design-lead` run toward a preference the operator never chose), or a design skill that silently ignores the profile.
**If this leaks, the user's data is exposed via:** the `taste-profile.md` artifact — mitigated by the fixed-enum vocabulary (no free-form/PII capture), helper sanitization, and ADR-086's committed-only/path-contained FR6 fencing. FR6 is fail-open (ADR-086: exit 0 every path; PostToolUse cannot fail-closed skills), capping loader-side blast radius.
**Brand-survival threshold:** single-user incident.

`requires_cpo_signoff: true` — CPO framing carried from the epic brainstorm (Product not re-spawned; internal tooling, Product/UX Gate = NONE). `user-impact-reviewer` will be invoked at review time.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1 (variants):** `frontend-design/SKILL.md` and `ux-design-lead.md` each contain a multi-variant fan-out section that seeds N (default 3) distinct aesthetic directions and passes each seed via prompt text. Verify: `grep -c` the fan-out heading in both files = 1 each.
- [ ] **AC2 (persist + load — skill via FR6):** `frontend-design/SKILL.md` frontmatter `context_queries` contains `knowledge-base/product/design/taste-profile.md`; the file is committed and `git ls-files`-tracked. Verify: `git ls-files --error-unmatch knowledge-base/product/design/taste-profile.md` exits 0, and the FR6 consistency test resolves it.
- [ ] **AC3 (load — agent via direct-Read):** `ux-design-lead.md` contains a directive to Read `knowledge-base/product/design/taste-profile.md` before designing. Verify: `grep -q "taste-profile.md" ux-design-lead.md`.
- [ ] **AC4 (contradiction flag fires):** `taste-profile-update.test.sh` includes a case where a new same-axis selection contradicting a high-confidence entry appends a `## Contradiction Flags` log line AND supersedes; test passes.
- [ ] **AC5 (decay determinism):** helper recomputes confidence from `last_reinforced` + a passed-in date with no `Date.now()`; test asserts a known input→output.
- [ ] **AC6 (content-trust):** helper rejects (non-zero exit, original preserved) an out-of-enum / instruction-bearing value; test passes. Enum vocabulary matches `frontend-design`'s tone list.
- [ ] **AC7 (freshness):** an automated decay/selection write bumps `last_updated` only; `last_reviewed` is byte-unchanged. Test asserts.
- [ ] **AC8 (helper tests + FR6 test):** `taste-profile-update.test.sh` passes; `.claude/hooks/skill-context-queries.test.sh` passes.
- [ ] **AC9 (C4):** `model.c4:304` reads `agents -> kb "Reads/writes"`; `c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
- [ ] **AC10 (ADR):** `ADR-087-*.md` exists, status Accepted, references ADR-086, and notes the agent-surface extension; the 086 collision is flagged as out-of-scope.
- [ ] **AC11 (no component drift):** README component counts + `plugin.json` unchanged (no new skill/agent/command).

### Post-merge (operator)
- None. (Web-Concierge FR6 surface port is a **deferred follow-up issue**, not a merge-gated step — see below.)

## Deferred / Tracking

- **Web-Concierge FR6 port** (skill-side taste-profile auto-load on the web surface). ADR-086 already tracks a surface-parity follow-up; co-file this consumer's need there. Re-eval when a design skill is run from Concierge and the missing prime is felt.
- **ADR-086 ordinal triple-collision** (three ADRs numbered 086 on main). File a housekeeping issue to renumber two of them; out of scope here.
- **Negative-evidence learning** (OQ4) — record rejected variants to speed convergence. Re-eval after taste-profile has ≥10 reinforcements.

## Test Scenarios

- Decay: entry at `confidence 0.9, last_reinforced 90d ago` → recomputes to `0.1` floor; at `45d` → `~0.45`.
- Reinforce: selecting an existing axis/value → `confidence 1.0`, `last_reinforced` = today, `last_updated` bumped, `last_reviewed` unchanged.
- Contradiction+supersede: axis `aesthetic-direction` held `minimalist@0.8`; select `maximalist` → `## Contradiction Flags` gains a dated line, entry becomes `maximalist@1.0`, old `minimalist` superseded.
- Injection reject: value `"maximalist; rm -rf /"` (out of enum) → non-zero exit, `taste-profile.md` byte-identical to pre-call.
- Headless: fan-out auto-selects top-confidence direction, no reinforcement write.

## Sharp Edges

- A `## User-Brand Impact` section that is empty/`TBD` fails `deepen-plan` Phase 4.6 — this one is filled.
- The helper lives under a **skill's** `scripts/` but is called by an **agent** too; keep the path stable and the invocation identical across both call sites (TR3). If refactored, update both.
- FR6 is **CLI-only** for the skill — do not claim the taste-profile auto-loads in web Concierge. The agent's direct-Read is the surface-independent path.
- Do NOT let the automated write touch `last_reviewed` — the `context-reviewed-gate.sh` PreToolUse hook denies commits that change it without a `Context-Reviewed:` trailer.
- Provisional ADR-087 ordinal: `/ship` re-verifies next-free against `origin/main` before merge (a sibling PR may claim 087 mid-pipeline).
