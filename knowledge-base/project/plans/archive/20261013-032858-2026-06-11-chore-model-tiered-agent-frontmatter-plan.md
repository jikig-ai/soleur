---
title: "Model-tiered maker/checker: pin cheaper models on explorer agents, stronger models on reviewers"
issue: 5087
type: chore
domain: engineering
priority: p3-low
lane: cross-domain
brand_survival_threshold: none
status: ACTIVE — recommended scope is Option C (narrow, additive, ADR-053-compatible); Options A/B documented for operator awareness
---

# ♻️ Model-tiered maker/checker agent frontmatter (#5087)

> **⚠️ READ THIS FIRST — THE NAIVE READING OF #5087 CONFLICTS WITH ADR-053; THE RECOMMENDED SCOPE DOES NOT.**
> The *full* approach #5087 implies (flip frontmatter to `haiku` on explorers AND `opus` on reviewers) overlaps the **exact alternative ADR-053 evaluated and REJECTED on 2026-06-10** (shipped via PR #5096, the day before this plan). That full path is a `clo-attestation-class change`. **But deepen-plan review surfaced a verified gap ADR-053 did NOT close:** `/plan` and `/brainstorm` spawn research agents via *direct, unpinned `Task` calls* (no `workflows/` dir), and `deepen-plan` deliberately leaves its research fan-out on `inherit` — so ADR-053's call-site pins never reach the research agents #5087 names. That gap is closable by a **narrow, additive, floor-safe pin** that survives all three of ADR-053's rejection reasons (`## Option C`). The plan therefore recommends Option C, keeps Option A (full sweep, incl. reviewer pins) fully specified for an operator who wants it, and notes Option B (close as-is) is now too strong to be the default. See `## Research Reconciliation` and `## Decision Required`.

## Enhancement Summary

**Deepened on:** 2026-06-11
**Sections enhanced:** Research Reconciliation (+1 verified gap row), Decision Required (binary → 3 options), recommendation flipped, Alternatives table, closing rationale.
**Agents used:** architecture-strategist (adversarial review of the recommendation), Explore (verify-the-negative pass on sweep-mechanics claims). All hard gates (4.6 User-Brand, 4.7 Observability, 4.8 PAT, 4.9 UI-wireframe) passed.

### Key Improvements
1. **Found a verified coverage gap that flips the recommendation.** ADR-053's call-site pins do NOT reach the research agents #5087 names — `/plan`/`/brainstorm` spawn them via direct, unpinned `Task` (no `workflows/` dir), and `deepen-plan.workflow.js:333` leaves its research fan-out on `inherit`. Verified directly. So Option B ("already addressed") was withdrawn.
2. **Introduced Option C (recommended): narrow, additive, floor-safe haiku pin on the 5 research agents.** Survives all three ADR-053 rejection reasons (silent-upgrade is *inapplicable* at the haiku floor; context-blindness is an argued tradeoff for read-only summarizers; uses policy §1's existing override mechanism). No ADR supersession, no clo attestation, no reviewer pins.
3. **Downgraded BLOCKED → ACTIVE.** For a `p3-low`, threshold-`none`, reversible change with a defensible narrow direction, the pipeline proceeds with Option C rather than halting for a synchronous operator gate.

### New Considerations Discovered
- The opus reviewer pins (handoff's intent) are *separable* from the cost win and carry the only genuine governance cost (never-downgrade contract, fable-cap, ADR supersession). Isolated to opt-in Option A.
- All sweep-mechanics claims (example-block line numbers 172/142, parser-blindness of `parseComponent`, `VALID_MODELS` enum) independently CONFIRMED.

## Overview

Issue #5087 asks to tier agent models by role: discovery/research agents on a cheaper tier (`haiku`), reviewer/verifier agents on a stronger tier (`opus`), to reduce token cost on autonomous loops. It compounds with the token-cost ledger (#5086) — tiering is the lever, the ledger measures whether it works.

The mechanical premise the handoff verified is correct: the `model:` frontmatter field **already exists** on all 66 spawnable agents set to `model: inherit`. This would be a change-the-value sweep, not an add-frontmatter task. Built-in agent types (`Explore`, `general-purpose`, `claude`) are not soleur `.md` files and are out of scope.

**But the local research surfaced a governing conflict the handoff was unaware of:** the soleur repo *already implemented model tiering* for the same cost-reduction goal (parent issue #3791), and it did so by **deliberately NOT touching agent frontmatter**. ADR-053 (Accepted, 2026-06-10) chose workflow call-site pins instead and lists frontmatter tiering as a rejected alternative. The Model Selection Policy in `plugins/soleur/AGENTS.md` states all agents use `model: inherit` with "Current exceptions: none."

This plan therefore does three things:
1. Documents the ADR-053 interaction precisely, INCLUDING the verified coverage gap ADR-053 left open (`## Research Reconciliation`).
2. Recommends **Option C** — a narrow, additive, floor-safe haiku pin on the 5 research agents that closes the gap without superseding ADR-053 or touching the never-downgrade list (`## Decision Required`, `## Option C Implementation`).
3. Keeps **Option A** (the full sweep, incl. opus reviewer pins) fully specified for an operator who explicitly wants the reviewer pins too — that path DOES require ADR supersession + clo attestation, so it is gated behind an explicit operator choice (`## Implementation Phases (Option A)`).

## Research Reconciliation — Premise vs. Codebase

Per Phase 0.6 premise validation (the cheap probe that must run before research). The handoff's DECISIONS were stated confidently but predate / missed the ADR that resolved this exact question.

| Premise (from #5087 / handoff) | Codebase reality (verified) | Plan response |
|---|---|---|
| "Pin cheaper models on explorers, stronger on reviewers via `model:` frontmatter" is the way to tier. | **ADR-053:47** lists "Frontmatter tiering (pin research agents to `sonnet`)" as a **rejected alternative**, for three reasons: context-blind (applies in every spawn context, not just autonomous loops), silently upgrades cheap sessions, and re-fights the deliberate 2026-02-24 reversal of the one prior tiering attempt. The chosen, shipped mechanism is **workflow call-site pins** (`opts.model` at 12 mechanical steps), gated by `plugins/soleur/test/workflow-model-pins.test.ts`. | **BLOCKER.** Surface to operator. Frontmatter tiering is not an unconsidered idea — it is an explicitly-rejected one. See `## Decision Required`. |
| `model: inherit` is a neutral default ready to be flipped. | **`plugins/soleur/AGENTS.md` Model Selection Policy §1:** "All agents use `model: inherit`… Explicit overrides (`haiku`, `sonnet`, `opus`, `fable`) **require written justification in the agent body text** explaining why the task is fundamentally mismatched with the session model. **Current exceptions: none.**" | Every flipped agent needs a body-text justification block, AND policy §1 + the YAML-frontmatter checklist line ("`model: inherit` … explicit overrides require justification") must be rewritten in lockstep, or the edited agents violate their own stated policy. |
| Pin reviewers to `opus` so adversarial checks never degrade. | The **Never-downgrade exemption list** (AGENTS.md policy §3; ADR-053:16) already protects all `engineering/review/*` agents — but it protects them from being **downgraded** to a cheaper tier, while preserving `inherit` so a *higher* session model still flows through. Pinning them to absolute `opus` is a different contract: per ADR-053:20 an absolute pin can run **ABOVE** a cheaper session (cost upgrade the operator didn't choose) AND **caps** a `fable`-tier session's reviewers DOWN to opus. | The opus pins are not a no-op safety win; they change the contract in both directions. Document the cost-upgrade and the fable-cap consequences explicitly. |
| 66 agents, the field is present on all. | Verified: 67 `.md` files under `plugins/soleur/agents/`; 66 carry `model: inherit`; the 67th (`operations/references/service-deep-links.md`) is a reference doc with no model field (correctly excluded). | Sweep targets 66; leave the reference doc. |
| (handoff) verifier set includes `type-design-analyzer`. | `type-design-analyzer` and `silent-failure-hunter` are **upstream pr-review-toolkit agents**, not soleur `.md` files (`find plugins/soleur/agents -iname '*type-design*'` → empty). They CANNOT be tiered via frontmatter. | Out of scope. The soleur observability reviewer that DOES exist is `observability-coverage-reviewer.md` (covered by the `review/*` glob). |
| (Option B premise) "Tiering is already shipped via ADR-053, so #5087 is fully addressed." | **VERIFIED FALSE for the research agents #5087 names.** ADR-053's call-site pins only reach agents spawned inside `skills/*/workflows/*.workflow.js`. `/plan` spawns its research agents as **direct, unpinned `Task` calls** (`plugins/soleur/skills/plan/SKILL.md:125-126,184-185`; the `plan/` skill has NO `workflows/` dir). `/brainstorm` is the same shape (no `workflows/` dir). `deepen-plan` HAS a workflow script but its research fan-out is explicitly left on inherit (`deepen-plan.workflow.js:333` "research + merge inherit the session model"; only `parse` pinned at `:335`). No research agent appears in the pin allowlist (`plugins/soleur/test/workflow-model-pins.test.ts` — verified absent). So on a Fable/Opus session, `/plan`'s 4-agent research fan-out runs at top tier today — the exact cost surface #5087 targets, **uncovered by #5096.** | **This is the legitimate, ADR-053-compatible scope for #5087.** Drives `## Option C` (recommended): a haiku-FLOOR frontmatter pin on the 5 research agents. Floor-safe (haiku can never upgrade any session → ADR-053 rejection-reason #2 is *inapplicable*), additive (touches no never-downgrade-list agent), and uses policy §1's existing "override with body justification" mechanism (→ not a re-fight of 2026-02-24). |

**Premise validation note:** Two cited issues checked — #5087 OPEN (not closed by any PR), #5086 (token-cost ledger) OPEN. No stale "already-resolved" state. The stale element is not an issue state but a **design premise**: the approach was decided against one day before this handoff. The 2026-02-24 reversal is real (`git log`: commit `8c3d8abea` / PR #295 "document model selection policy and standardize to inherit"). ADR-053 shipped via PR #5096 (`87406c42f`).

## User-Brand Impact

**If this lands broken, the user experiences:** an autonomous-loop run where a review/verifier agent silently runs on a weaker-than-intended model (e.g., a corrupted sweep left `model: inherit` on a security reviewer while a `fable` session was downgraded elsewhere), letting a real defect through review unnoticed — OR a discovery agent flipped to `haiku` misclassifies the codebase and the plan/work built on it is wrong. Both are quality regressions in the maker/checker loop, not crashes.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — this change edits only plugin agent frontmatter and governance docs; it moves no user data, touches no auth/API/schema surface, and persists no secrets.

**Brand-survival threshold:** none.

> `threshold: none, reason: change is confined to plugin agent-definition frontmatter and repo governance docs; it touches no user-data, auth, API, schema, or secret surface (no sensitive-path match).`

## Decision Required

Three options, ordered by recommendation. The plan PICKS **Option C** (reversible, threshold-`none`, `p3-low` → the one-shot pipeline proceeds rather than halting), and leaves A/B documented so the operator can override at plan-review.

### Option C — Narrow additive haiku-floor pin on the 5 research agents (RECOMMENDED — `/work`-ready)

Pin ONLY the 5 read-and-summarize research agents to `model: haiku`. **Do NOT** pin discovery agents in this scope (agent-finder/functional-discovery carry the example-block hazard and are lower-frequency), and **do NOT** add any opus reviewer pins (those are the part that triggers the never-downgrade / fable-cap / supersession cost). This is the scope that captures #5087's actual cost intent — the verified gap where `/plan`/`/brainstorm`/`deepen-plan` research fan-outs run at the full session model today.

Why it is additive to ADR-053, not a reversal of it (each rejection reason answered):
- **Rejection #2 "silently upgrades cheap sessions" — INAPPLICABLE at the floor.** `haiku` is the cheapest tier; it can never upgrade a Haiku/Sonnet/Opus/Fable session. ADR-053:47 wrote that reason against a `sonnet` pin (which *can* upgrade a haiku session). Pinning to the floor neutralizes it entirely.
- **Rejection #1 "context-blind" — an accepted tradeoff for read-only summarizers, not a bar.** These 5 agents are *defined* as retrieval+summarize (repo structure, learnings, external best-practices, framework docs, git-log archaeology). Policy §1 (`plugins/soleur/AGENTS.md`) sanctions an override exactly "when the task is fundamentally mismatched with the session model" — a pure summarizer running on Fable 5 is that mismatch. The cost (an operator who picked Opus for a sharper repo read loses it on these 5) is real but bounded and documented per-agent.
- **Rejection #3 "re-fights 2026-02-24" — no.** This uses policy §1's *existing* "explicit override with written justification" mechanism, which the 2026-02-24 standardization (PR #295) deliberately KEPT alive. It does not return to ad-hoc per-agent models wholesale; it is 5 justified, floor-safe pins.

Cost: 5 agent-file edits (frontmatter line + body justification) + a one-paragraph note in `plugins/soleur/AGENTS.md` policy §1 listing the 5 exceptions and citing this gap. **No ADR-054. No clo attestation. No reviewer pins.** Spec: `## Option C Implementation` below.

### Option A — Full sweep: haiku explorers + opus reviewers (requires ADR supersession)

The handoff's literal intent. Adds the opus reviewer pins on top of Option C. Choose only with eyes open: the opus reviewer pins overlap ADR-053's never-downgrade contract and introduce the absolute-pin hazards (an opus pin runs ABOVE a cheaper session AND caps a `fable` session's reviewers DOWN — ADR-053:20). That makes it a **clo-attestation-class change** (ADR-053:16, policy §3):
- New ADR-054 superseding ADR-053 Decision #1, rebutting all three rejection reasons.
- Rewrite policy §1 "Current exceptions: none" → enumerate the haiku + opus exception sets.
- Per-agent body-text justification in all 25 edited agents.
- clo attestation that the never-downgrade contract is not weakened.

Fully specified in `## Implementation Phases (Option A)`.

### Option B — Close #5087 as already-addressed (NOT recommended — too strong)

This was the initial recommendation, **withdrawn after the deepen-plan coverage-gap finding.** "Already shipped via #5096" is true for the mechanical fan-out steps but FALSE for the research agents #5087 names (they spawn via direct unpinned `Task`, verified). Closing now would leave the named cost surface uncovered. Only choose B if the operator judges the interactive-session research savings too marginal to justify even Option C's 5-file edit.

### Recommendation

**Option C.** It ships #5087's real intent (cheaper research-agent spawns where ADR-053's lever doesn't reach), is floor-safe so it survives ADR-053's own rejection reasons, costs no governance motion, and is a reversible threshold-`none` change appropriate for the one-shot pipeline to execute. Option A's reviewer pins are separable and carry the only genuine governance cost — defer them to an explicit operator opt-in. Option B is withdrawn.

---

# Option C Implementation (RECOMMENDED — what `/work` builds)

## Files to Edit (Option C)

**5 agent frontmatter files → `model: haiku`** (each: frontmatter `model:` line at line 4 + a one-sentence body justification referencing this plan + ADR-053):
- `plugins/soleur/agents/engineering/research/repo-research-analyst.md`
- `plugins/soleur/agents/engineering/research/learnings-researcher.md`
- `plugins/soleur/agents/engineering/research/best-practices-researcher.md`
- `plugins/soleur/agents/engineering/research/framework-docs-researcher.md`
- `plugins/soleur/agents/engineering/research/git-history-analyzer.md`

(None of these 5 contains an example-block `model:` line — verified; the example-block hazard is only in the two *discovery* agents, which Option C does NOT touch. So the sweep here is simpler than Option A.)

**1 governance file:**
- `plugins/soleur/AGENTS.md` — policy §1: change "Current exceptions: none." to enumerate the 5 research-agent haiku exceptions, with a one-line rationale citing the ADR-053 direct-spawn coverage gap (`/plan`/`/brainstorm` spawn research via direct `Task`, unpinned). This is a *within-policy* override registration, not an ADR supersession (no Decision-#1 reversal — ADR-053 governs workflow pins; these are frontmatter pins on the surface ADR-053 explicitly left on `inherit`).

## Acceptance Criteria (Option C)

### Pre-merge (PR)

- [ ] **C-AC1:** Each of the 5 research agents reads `model: haiku` in its frontmatter (`for f in <5 files>; do grep -c '^model: haiku' "$f"; done` → all 1) and contains a one-sentence body justification referencing this plan + ADR-053. Verify shape, not just presence.
- [ ] **C-AC2:** `plugins/soleur/AGENTS.md` policy §1 no longer reads "Current exceptions: none." and lists the 5 research agents (`grep -c 'Current exceptions: none' plugins/soleur/AGENTS.md` → 0; `grep -c 'repo-research-analyst' plugins/soleur/AGENTS.md` → ≥1).
- [ ] **C-AC3:** No reviewer/discovery/orchestrator agent changed — `git diff --name-only` lists exactly the 5 research files + AGENTS.md (+ this plan/tasks). The never-downgrade list is untouched.
- [ ] **C-AC4:** `bun test plugins/soleur/test/components.test.ts` passes (`haiku` already in `VALID_MODELS` `:13`; verified).
- [ ] **C-AC5:** Token-budget guard unaffected — `grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w` still < 2500 (justifications go in the BODY, not `description:`).

### Post-merge (operator)

- [ ] None. Option C requires no operator step (no clo attestation — it's a within-§1 override, not a supersession). The PR merges via the normal gate.

## Observability note (Option C)

Same as Option A — the only "code" touched is the existing `components.test.ts` enum gate (not `apps/*/server|src|infra`, not `plugins/*/scripts/`), so the plan-Phase-2.9 / deepen-Phase-4.7 observability schema does not trigger. CI (`test-bun` job, `.github/workflows/ci.yml:294` → `scripts/test-all.sh:168` → `bun test plugins/soleur/`) IS the liveness signal for the frontmatter validity of all 67 agent files on every PR.

---

# Implementation Phases (Option A) — ONLY if the operator opts into the reviewer pins

> If Option C (recommended) or Option B is chosen, skip everything below.

## Tier classification (verified roster)

Audited the full 66-agent roster (`find plugins/soleur/agents -name '*.md' | grep -v references/`). Conservative classification per the handoff:

**Tier 1 → `model: haiku`** (7 agents — pure read-and-summarize, low misclassification risk):
- `plugins/soleur/agents/engineering/research/repo-research-analyst.md`
- `plugins/soleur/agents/engineering/research/learnings-researcher.md`
- `plugins/soleur/agents/engineering/research/best-practices-researcher.md`
- `plugins/soleur/agents/engineering/research/framework-docs-researcher.md`
- `plugins/soleur/agents/engineering/research/git-history-analyzer.md`
- `plugins/soleur/agents/engineering/discovery/agent-finder.md`
- `plugins/soleur/agents/engineering/discovery/functional-discovery.md`

**Tier 2 → `model: opus`** (18 agents — all `engineering/review/*` + legal verifier, adversarial verification/review):
- All 17 files in `plugins/soleur/agents/engineering/review/` (agent-native-reviewer, architecture-strategist, code-quality-analyst, code-simplicity-reviewer, data-integrity-guardian, data-migration-expert, deployment-verification-agent, dhh-rails-reviewer, kieran-rails-reviewer, legacy-code-expert, observability-coverage-reviewer, pattern-recognition-specialist, performance-oracle, security-sentinel, semgrep-sast, test-design-reviewer, user-impact-reviewer).
- `plugins/soleur/agents/legal/legal-compliance-auditor.md` (verifier-class: audits existing legal docs for compliance gaps).

**Stay `inherit`** (audit decisions — documented, conservative):
- `operations/ops-research.md` — handoff floated it for haiku, but it does **live research + provider comparison + cost-optimization recommendations** (synthesis/judgment, not pure summarize). Keep `inherit`.
- `legal/legal-document-generator.md` — generator, not verifier. `inherit`.
- All C-suite orchestrators, generators, strategy agents (cto, cpo, clo, cfo, coo, cro, cmo, cco, and all marketing/sales/finance/product/operations specialists). `inherit`.
- `engineering/workflow/pr-comment-resolver.md` — resolver/implementer (never-downgrade judgment class per ADR-053:16). `inherit`.
- Out of scope (not soleur files): `type-design-analyzer`, `silent-failure-hunter` (upstream pr-review-toolkit).

Net: **25 agent files edited** (7 haiku + 18 opus), plus governance files.

## Files to Edit

**Agent frontmatter (25 files):** the 7 Tier-1 + 18 Tier-2 files listed above. Each edit: the SINGLE frontmatter `model:` line (the `---`-delimited block at the top), PLUS a body-text justification block (policy §1 requirement).

**Governance (3 files):**
- `plugins/soleur/AGENTS.md` — rewrite Model Selection Policy §1 ("Current exceptions: none" → enumerate the haiku/opus exception sets with rationale) and the frontmatter-checklist line.
- `knowledge-base/engineering/architecture/decisions/ADR-054-*.md` — **NEW** ADR superseding ADR-053 Decision #1; must answer ADR-053:47's three rejection reasons.
- `knowledge-base/engineering/architecture/decisions/ADR-053-per-call-model-tiering-for-workflow-subagent-spawns.md` — add a "Superseded in part by ADR-054" note to Decision #1 (do not delete; ADRs are append-only history).

**No `VALID_MODELS` change required:** `haiku` and `opus` are already in `VALID_MODELS` (`plugins/soleur/test/components.test.ts:13`), so the existing per-agent `model` assertion (`:47-50`) passes. **A new guard test IS needed** (see Sharp Edges) to catch example-block corruption that the existing parser-based test cannot.

## ⚠️ Critical sweep mechanics (Sharp Edges encoded as instructions)

1. **NEVER `sed -i 's/^model: inherit/.../'` globally.** Two of the seven Tier-1 files contain a literal `model: inherit` line INSIDE a fenced ```yaml example block (NOT their own frontmatter):
   - `agent-finder.md` — real frontmatter at **line 4**; example-block copy at **line 172** (inside the "Replace the artifact's original frontmatter" template the agent emits when installing community agents).
   - `functional-discovery.md` — real frontmatter at **line 4**; example-block copy at **line 142**.
   The parser-based test (`parseComponent`, gray-matter first-`---`-block) reads ONLY line 4, so a corrupted line 172/142 **passes CI silently** (it's a documentation-correctness bug, not a test-caught one). Per learning `2026-03-05-awk-scoping-yaml-frontmatter-shell.md`, scope edits to the first `---` block only, OR use the **Edit tool per-file** targeting the exact frontmatter line. Edit-tool-per-file is preferred here (25 files is small; precision > speed).
2. **Post-edit grep verification is mandatory** (learning `2026-02-22-model-id-update-patterns.md` — `replace_all` silently misses variant forms; issue inventories undercount). After the sweep:
   - `grep -c '^model: haiku' <each Tier-1 frontmatter>` → 1 each.
   - `grep -c '^model: opus' <each Tier-2 frontmatter>` → 1 each.
   - Confirm `agent-finder.md:172` and `functional-discovery.md:142` still read `model: inherit` (example blocks UNCHANGED).
3. **Idempotent / already-correct detection:** the sweep must be a no-op on re-run (skip files already at target tier).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (governance — the load-bearing one):** ADR-054 exists, is `Accepted`, supersedes ADR-053 Decision #1, and its Context section explicitly rebuts ADR-053:47's three rejection reasons (context-blindness, silent cheap-session upgrade, 2026-02-24 reversal). ADR-053 carries a "superseded in part" note.
- [ ] **AC2:** `plugins/soleur/AGENTS.md` Model Selection Policy §1 no longer says "Current exceptions: none" — it enumerates the 7 haiku + 18 opus exceptions (`grep -c 'Current exceptions: none' plugins/soleur/AGENTS.md` → 0).
- [ ] **AC3:** Each of the 25 edited agents has a body-text justification block for its override (none of the 25 frontmatter blocks reads `model: inherit`, AND each body contains a justification sentence referencing ADR-054). Verify shape, not just existence.
- [ ] **AC4:** Frontmatter values correct — `for f in <7 tier1>; do grep -c '^model: haiku' "$f"; done` all 1; same for `^model: opus` over the 18 tier2 files.
- [ ] **AC5 (example-block integrity):** `grep -n '^model: inherit' plugins/soleur/agents/engineering/discovery/agent-finder.md` returns line 172 (and only the example-block line); same for `functional-discovery.md` line 142. The fenced ```yaml examples are UNCHANGED.
- [ ] **AC6:** New guard test added to `plugins/soleur/test/components.test.ts` (or a sibling) asserting the two discovery agents' example-block `model: inherit` lines survive — converting AC5 into a CI-blocking gate (the existing parser test structurally cannot see them).
- [ ] **AC7:** `bun test plugins/soleur/test/components.test.ts` passes (no `model` enum / required-field regression across all 67 files).
- [ ] **AC8:** No `engineering/review/*` agent or never-downgrade-list agent ends up on a tier reachable as a DOWNGRADE for any session; opus pins documented as absolute (consequence: caps a `fable` session's reviewers to opus — clo-attestation acknowledges this).
- [ ] **AC9:** Token-budget guard unaffected — `grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w` still < 2500 (descriptions untouched, but verify the body-justification edits didn't leak into `description:`).

### Post-merge (operator)

- [ ] **AC10:** clo attestation recorded (the never-downgrade contract is not weakened by the opus absolute pins). `Automation: not feasible because clo attestation is a human sign-off on a governance-class change (subjective judgment).`

## Test Scenarios

1. **Sweep precision:** edit `agent-finder.md` frontmatter to `haiku`; assert line 4 = `model: haiku` AND line 172 = `model: inherit` (example block intact). The whole sweep's correctness hinges on this distinction.
2. **CI green:** `bun test plugins/soleur/` passes — confirms `haiku`/`opus` clear the `VALID_MODELS` gate and no required field was dropped.
3. **New guard fails on corruption:** temporarily mutate `agent-finder.md:172` to `model: opus`; the new AC6 guard test must FAIL (proving it actually protects the example block). Revert.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is a tooling/governance change confined to plugin agent-definition frontmatter and repo ADR/policy docs. No user-facing surface (Product/UX NONE — the plan's `Files to Edit`/`Files to Create` contain zero `components/**`, `app/**/page.tsx`, or other UI-surface paths). No regulated-data surface (GDPR gate skipped). No new infrastructure (IaC gate skipped — pure docs/config edits against an already-provisioned plugin). No code-class file under `apps/*/server|src|infra` or `plugins/*/scripts/` (Observability gate skipped — the only code edit is a bun test assertion, which is itself the observability for AC5).

> Note: the one governance dimension that *is* engaged — the clo-attestation-class nature of superseding ADR-053 — is handled in `## Decision Required` Option A and AC10, not via a domain-leader spawn, because it is a decision gate (does the operator authorize the reversal) rather than a cross-domain implementation concern.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (63 open) — zero reference `plugins/soleur/agents/` or any model/tier/frontmatter concern. The sweep touches no file an open scope-out tracks.

## Alternative Approaches Considered

| Approach | Disposition |
|---|---|
| **Narrow haiku-floor pin on 5 research agents (Option C)** | **RECOMMENDED.** Closes the verified ADR-053 coverage gap (direct unpinned `/plan`/`/brainstorm` research spawns); floor-safe so it survives ADR-053's rejection reasons; no governance cost. |
| **Full sweep incl. opus reviewer pins (Option A)** | Available behind explicit operator opt-in. The reviewer pins are the part that requires ADR-054 + clo attestation; separable from C. |
| **Close as already-addressed (Option B)** | Withdrawn — "already shipped" is false for the direct-spawn research agents #5087 names. |
| **Workflow call-site pins (ADR-053, shipped)** | The repo's existing lever; covers mechanical fan-out steps but NOT the direct-Task research spawns. Option C is the additive complement, not a replacement. |
| **`sed` global sweep** | Rejected — corrupts the two discovery agents' ```yaml example blocks silently (CI can't see it). Edit-per-file used. (Moot for Option C, which doesn't touch the discovery agents.) |
| **Tier `ops-research` / discovery agents to haiku** | Rejected at audit — ops-research synthesizes/recommends (not pure summarize); discovery agents carry the example-block hazard and are lower-frequency. Kept `inherit`. |
| **Session-relative tiering** | Rejected by ADR-053:48 — runtime supports absolute values only. |

## Research Insights

- **Model `model:` consumption:** no runtime loader reads frontmatter `model:` to select a model — the Claude Code harness honors it at spawn. The only repo consumer is the validation test `plugins/soleur/test/components.test.ts:47-50` against `VALID_MODELS` (`:13` = `["inherit","haiku","sonnet","opus","fable"]`). `haiku`/`opus` already valid → enum won't trip. Agent discovery: `plugins/soleur/test/helpers.ts:9,30`. CI wiring: `scripts/test-all.sh:168` (`bun test plugins/soleur/`) under the `test-bun` job (`.github/workflows/ci.yml:294`).
- **Telemetry caveat (#5086 compound):** the per-agent tee hook (`.claude/hooks/agent-token-tee.sh`, `.claude/.session-tokens.jsonl`) records DIRECT Agent-tool spawns only — NOT workflow `agent()` spawns (ADR-053 finding 1). Any #5087 cost-savings claim for workflow-spawned agents cannot be measured by the tee hook; the executed model lives in the workflow run transcript (`<run-dir>/subagents/workflows/<run-id>/agent-*.jsonl`, ADR-053:28-29). This matters for #5086's ability to validate the lever.
- **Pricing (verify against claude-api skill table, not memory):** Fable 5 $10/$50, Opus 4.8 $5/$25, Sonnet 4.6 $3/$15, Haiku 4.5 $1/$5 per MTok. Pinning a reviewer to opus on a `fable` session is a ~2x DOWN-cost but a quality cap; pinning a researcher to haiku on a sonnet session is a ~3.3x down-cost.
- **Inngest model-tiers registry** (`apps/web-platform/server/inngest/model-tiers.ts`, from #5156) is a SEPARATE concern (cron workload classes, concrete dated model IDs like `claude-opus-4-7`) — do NOT couple the agent sweep to it.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled: threshold `none` with reason.)
- The two discovery agents carry a `model: inherit` line inside a fenced ```yaml example block (agent-finder.md:172, functional-discovery.md:142). The frontmatter validation test (`parseComponent`) cannot see them, so a corrupting sweep passes CI silently. AC5 + AC6 (new guard test) are the only protection — do not drop them.
- Per-agent frontmatter overrides REQUIRE a body-text justification per AGENTS.md policy §1; an override without justification is a self-contradiction the `cq-agents-md-tier-gate` discipline flags. The sweep is NOT just the `model:` line — it is the line + justification block + AGENTS.md policy rewrite + ADR. Treating it as a one-line sweep is the trap.
- `type-design-analyzer` and `silent-failure-hunter` (named in the handoff's verifier set) are upstream pr-review-toolkit agents, not soleur files — they cannot be frontmatter-tiered. The soleur observability reviewer is `observability-coverage-reviewer.md`.

## Why the recommended scope is Option C, not the handoff's literal A

The handoff's DECISIONS were made in good faith but without sight of ADR-053 (merged via #5096 the day before). Implementing the *full* literal handoff (opus reviewer pins + haiku explorers) would partly reverse an Accepted ADR — a `clo-attestation-class change`, and the part (`opus` reviewer pins) that is NOT needed to satisfy #5087's stated cost goal. The deepen-plan adversarial pass then found the dispositive fact: ADR-053's lever does NOT reach the research agents #5087 names (they spawn via direct, unpinned `Task` from `/plan`/`/brainstorm`; `deepen-plan` leaves its research fan-out on `inherit` — all verified). That makes a **narrow, additive, floor-safe haiku pin on the 5 research agents** both (a) the true intent of #5087 and (b) compatible with ADR-053 rather than a reversal of it. Option C ships that. Option A's reviewer pins remain available behind an explicit operator opt-in (they carry the only real governance cost). For a `p3-low`, threshold-`none`, reversible change, the one-shot pipeline proceeds with Option C rather than halting for a synchronous operator gate — the operator can still override to A or B at plan-review.
