---
title: "feat(harness): additive-only auto-edit ADR + hard-rule body-weakening gate"
date: 2026-07-06
type: feat
issue: 6103
parent_issue: 6038
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-07-06-harness-auto-edit-safety-policy-brainstorm.md
spec: knowledge-base/project/specs/feat-harness-auto-edit-safety-policy/spec.md
adr: ADR-092 (Provisional — authored as a work deliverable via /soleur:architecture)
review: "4-agent panel (spec-flow, architecture-strategist, security-sentinel, code-simplicity) 2026-07-06 — scope cut to minimal v1 per operator User-Challenge decision"
---

# feat(harness): additive-only auto-edit ADR + hard-rule body-weakening gate ✨

## Overview

Land the soak-**independent** prerequisites for #6038 (Self-Harness Layer 2 auto-proposer). The
proposer BUILD stays deferred under #6038 (criterion 1 needs ≥1 month of #6037 digests, cannot clear
before ~2026-08-05). This plan delivers #6038's criteria 2 (ADR) + 3 (owner) and the landmine it
names ("close the `cq-rule-ids-are-immutable` gap first").

**Design (post-review, minimal v1):** the load-bearing control is a **per-change, hash-bound,
CODEOWNERS-gated human ACK required on ANY `hr-*`/`wg-*` rule-body change or deletion** — NOT a
deontic-strength lexer. Rationale (4-agent panel + operator decision 2026-07-06): the lexer is the
*reward-hackable* half (it misses no-hedge scope-narrowing — including the headline threat rule
`hr-gdpr-gate`, which is `[hook-enforced]`, not `[compliance-tier]`), and it guards a *machine*
writer that does not exist until #6038 ships (~1 month out). Blocking **every** hard-rule body edit
pending a deliberate, per-change, audit-logged human ack closes the silent-weakening gap for **all**
rules today — strictly stronger and ~half the build surface. The lexer, LLM-judge, C4 component,
lefthook mirror, and #6038-soak follow-through are deferred to the proposer PR (where a machine
writes bodies and digest evidence tunes thresholds) — matches brainstorm NG4 + CPO "provisional,
don't tune blind."

Deliverables:
1. **ADR-092 (Provisional)** — additive-only boundary + the body-weakening gate design + recursion
   invariant; Lineage ADR-054/069/027-stateless; lexer/LLM-judge/C4 listed as deferred. Revisit
   trigger: first #6037 digest with ≥N samples (~2026-08-05).
2. **Body-weakening gate** — `scripts/lint-rule-bodies.py --check` + committed `sha256` body-hash
   manifest `.claude/rule-body-hashes.txt` + a **required CI check** wired into the canonical
   ruleset (the real merge-blocker) + a per-change hash-bound WORM ack.
3. **Owner = required CI check + ack** (#6038 criterion 3), de-ceremonialized for a solo operator.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| "sibling `lint-rule-ids.py` on lefthook **+ CI**" | `lint-rule-ids.py` is **lefthook-only**; bot PRs + `--no-verify` skip lefthook | Required **CI** check is the gate; wire it into the canonical ruleset (below). Lefthook mirror **deferred**. |
| a job in `ci.yml` = required check | Merge-blocking is `scripts/ci-required-ruleset-canonical-required-status-checks.json` + `infra/github/ruleset-ci-required.tf` (CODEOWNERS-pinned) — NOT job-existence (SEC-P0-3) | Add `rule-body-lint` context to the canonical JSON + `.tf` in this PR; enroll in the required-check **drift-guard cron** (SF-P1-5). |
| `[compliance-tier]` marks the protected rules | The **headline** rule `hr-gdpr-gate` is `[hook-enforced]`, **not** `[compliance-tier]` (AGENTS.core.md:43) (SF-P0-1) | Ack required on **ALL** `hr-*`/`wg-*` body changes, not just tagged ones. Tag → louder CI message only. |
| ID-immutability = `cq-rule-ids-are-immutable` | `scripts/lint-rule-ids.py` (index IDs; `HR_RETIREMENT_ALLOWLIST` + `retired-rule-ids.txt`) — bodies live one-line-each in `AGENTS.{core,docs,rest}.md` | Detector hashes **sidecar body lines** (union across all 3 sidecars, mirror `lint_union`); reuse the two-key + WORM pattern. |
| ADR-027 = stateless self-modifying cron | Two files share ADR-027 (`…stateless-self-modifying-cron.md` + `…process-local-state-for-runners.md`) — a pre-existing ordinal collision | Cite `ADR-027-stateless-self-modifying-cron.md` by filename in ADR-092 Lineage; collision out of scope. |
| eval-gate would catch a weakening | ADR-069 measures skill-arm fixture pass-rate, not guardrail coverage | Gate is a **separate** pass, never folded into eval-gate. |

## User-Brand Impact

**If this lands broken, the user experiences:** a silently weakened hard-rule guardrail (e.g.
`hr-gdpr-gate-on-regulated-data-surfaces` reworded mandatory→advisory) edited without detection —
the protection preventing a user-data / secret-leak incident is disabled while every existing gate
stays green.
**If this leaks, the user's data is exposed via:** an edit that narrows/removes an `hr-*`
compliance guardrail on a regulated-data surface while passing the eval (Goodhart).
**Brand-survival threshold:** single-user incident.

`requires_cpo_signoff: true` — CPO sign-off carried from the brainstorm; `user-impact-reviewer`
invoked at review time.

## Open Code-Review Overlap
**None.** Scanned 61 open `code-review` issues against every planned file — zero overlaps.

## Architecture Decision (ADR/C4)

### ADR
**Create ADR-092 (Provisional)** via `/soleur:architecture create "Additive-only auto-edit boundary
+ hard-rule body-weakening gate"`. `## Decision`:
- **Additive-only boundary:** append-only at the rule-SET level. New rule (new id) / new skill
  section = eligible for auto draft-PR. Any edit/deletion of an existing `hr-*`/`wg-*` **body** =
  human-only, gated by the per-change ack. The safe primitive is "add a rule," never "revise a rule."
- **Body-weakening gate:** committed `sha256` body-hash manifest (CI re-derives, TR1) + a per-change
  hash-bound ack (`<id>|<new-sha256>|<date>|<PR>|<reason>`) in the CODEOWNERS-owned WORM file
  `.claude/rule-weakening-acks.txt`. ANY `hr-*`/`wg-*` body change or deletion is blocked until a
  matching ack exists. `[compliance-tier]`/`[hook-enforced]`/`[skill-enforced]` tags → louder CI
  annotation (mandatory-human-review), but the ack is required for all hard-rule bodies regardless.
- **Ack = tamper-evidence + human-review gate, NOT full segregation-of-duties** (ARCH-P1-d): a solo
  operator may weaken + ack across a CODEOWNERS-reviewed PR; the control is the required human review
  on the CODEOWNERS-owned ack file + per-change hash binding, not dual-control. Stated as the
  accepted residual under solo-operator de-ceremonialization.
- **Recursion invariant:** `TARGET_ALLOW_RE` (the auto-editable set), the manifest, the ack file, the
  lexicon (when it lands), and the detector code stay OUTSIDE the auto-editable set. Pinned by a test
  that **imports** the exported `TARGET_ALLOW_RE` symbol.
- **`## Alternatives Considered`:** (a) deontic-strength lexer as the gate — **deferred to the
  #6038 proposer PR** (reward-hackable; guards a machine writer that doesn't exist yet; thresholds
  need soak evidence — NG2/NG5); (b) LLM-judge gate — rejected (same reward-hackable class); (c)
  lefthook-only — rejected (bot PRs skip it); (d) ack scoped to `[compliance-tier]` — rejected
  (headline rule isn't tagged).
- **`## Lineage`:** ADR-054 (bot-PR write path) + ADR-069 (sibling validation gate) +
  ADR-027-stateless-self-modifying-cron.
- **`## Status`:** Provisional. Revisit: first #6037 digest with ≥N samples (~2026-08-05).

Register a durable principle row `AP-017 … → ADR-092` in
`knowledge-base/engineering/architecture/principles-register.md` (ARCH-P1-e). Ordinal 091 is
provisional — re-verify at ship + sweep planning docs on any renumber.

### C4 views
**Deferred to the #6038 proposer PR.** Panel consensus: a single CI lint script is below the C4
component threshold (SIMPLICITY), and the honest edges ("auto-proposer → gate → rule corpus")
reference elements that do not exist in the model — inventing them breaks `c4-code-syntax.test.ts`
and violates ADR-069's own no-invented-edge precedent (ARCH-P1-c). The `rulebodygate` component +
its real edge lands when the auto-proposer actor is modeled (with #6038). Noted in ADR-092.

## Observability

```yaml
liveness_signal:
  what: "rule-body-lint required CI check runs on every PR touching AGENTS*.md sidecars or the manifest/ack files"
  cadence: "per-PR"
  alert_target: "required CI check RED blocks merge (via canonical ruleset)"
  configured_in: ".github/workflows/ci.yml + scripts/ci-required-ruleset-canonical-required-status-checks.json + infra/github/ruleset-ci-required.tf"
error_reporting:
  destination: "CI ::error:: naming the rule id + whether an ack is missing/stale/hash-mismatched; non-zero exit"
  fail_loud: true
failure_modes:
  - mode: "hr-*/wg- body change or deletion without a matching per-change ack"
    detection: "CI re-derives sha256 over sidecar bodies vs manifest AND checks ack.hash == new body hash"
    alert_route: "CI RED + ::error:: rule id + 'ack missing/stale for this change'"
  - mode: "stale manifest (body changed, hashes not regenerated)"
    detection: "CI recomputes sha256; mismatch"
    alert_route: "CI RED — 'regenerate .claude/rule-body-hashes.txt + record ack'"
  - mode: "required-check ruleset drift (rule-body-lint silently downgraded to optional)"
    detection: "existing required-check drift-guard cron (mirrors CI-Required / CLA-Required chains)"
    alert_route: "drift-guard issue + Better Stack (per hr-no-dashboard-eyeball)"
  - mode: "compliance-tier / hook-enforced / skill-enforced rule touched"
    detection: "tag present on old∪new body of a changed id"
    alert_route: "CI RED + mandatory-human-review annotation"
  - mode: "lexer-invisible scope-narrowing (ACCEPTED blind spot in v1)"
    detection: "n/a — the per-change ack forces human review on EVERY body change, so no automatic classification is relied upon"
    alert_route: "human review at the required ack (the lexer that would auto-classify is deferred to #6038)"
logs:
  where: "GitHub Actions CI logs (job: rule-body-lint)"
  retention: "GitHub Actions default (90d)"
discoverability_test:
  command: "python3 scripts/lint-rule-bodies.py --check --base $(git merge-base origin/main HEAD)   # NO ssh; the exact CI gate"
  expected_output: "PASS (exit 0) on a clean tree; on an un-acked hr-* body change: 'BLOCKED: hr-<id> body changed without a matching ack (add <id>|<sha256>|<date>|<PR>|<reason> to .claude/rule-weakening-acks.txt)' (exit non-zero)"
```

## Implementation Phases

### Phase 0 — Preconditions
- Confirm worktree exists + push early (concurrent reaping live this session — see the 2026-07-06
  reaping learning).
- Locate the `lint-rule-ids.py` **test harness + runner** (`git ls-files | grep -i lint-rule-ids`) —
  mirror its convention; do NOT hardcode a framework/path.
- Read `lint-rule-ids.py` §`lint_union` to reuse `[id:]` extraction + the cross-sidecar union.
- Confirm `TARGET_ALLOW_RE` is **exported** from `cron-compound-promote.ts` (it is, L63) for the
  recursion test import.
- **Verify CODEOWNERS-review-required is actually enforced on `main`** (live ruleset, per
  hr-no-dashboard-eyeball). If NOT enforced, the ack's human-gate falls back to a required
  `approvals ≥ 1` + the required CI check (record which path is live).

### Phase 1 — Manifest generator + baseline (TDD: calibration test first)
- `scripts/lint-rule-bodies.py` with `--write` (generator) + `--check --base <ref>` (gate). Parse
  `AGENTS.{core,docs,rest}.md`, build ONE global `id → body-line` map across all three sidecars
  (SF-P2-9), for `hr-*` + `wg-*`. Normalize (strip trailing whitespace; DECIDE tag-order
  normalization — Open Question), `sha256` per id → `.claude/rule-body-hashes.txt`
  (`{schema:1, hashes:{<id>:<sha256>}}`).
- Commit the baseline over the current corpus. **Calibration AC (write first):** `--check` against
  HEAD==manifest yields zero findings (no false positives on ~194 rules).

### Phase 2 — Body-change gate (`--check --base <merge-base>`)
- Base = `git merge-base origin/main HEAD` (SF-P1-4), NOT `origin/main` tip. Build the base-side
  id→body map across all 3 sidecars.
- For each `hr-*`/`wg-*` id present at base:
  1. Body line **changed** (hash mismatch) OR **vanished** (deletion under a retained index id —
     ARCH-P2-a): require a matching ack line `<id>|<new-sha256>|<date>|<PR>|<reason>` in
     `.claude/rule-weakening-acks.txt` whose `<new-sha256>` equals the current body hash (SF-P0-2,
     per-change binding). Missing/stale ack → BLOCK. CI **re-derives** the hash (TR1); never trusts
     the committed manifest value (SEC AC).
  2. If the id (old∪new body) carries `[compliance-tier]`/`[hook-enforced]`/`[skill-enforced]` →
     emit the mandatory-human-review annotation (louder message; ack still required).
- Also flag an **added** line under a NEW id carrying a security tag (SF-P2-8) so a toothless new
  compliance control can't land silently.
- Fail-closed: parse error / missing manifest / missing base → non-zero.

### Phase 3 — Wire the required CI check (the real gate)
- Add a `rule-body-lint` job to `.github/workflows/ci.yml` (`python3 scripts/lint-rule-bodies.py
  --check --base $(git merge-base origin/main HEAD)`).
- **Add the `rule-body-lint` context to `scripts/ci-required-ruleset-canonical-required-status-checks.json`
  + `infra/github/ruleset-ci-required.tf`** (SEC-P0-3) — expect a CODEOWNERS review on both. Decide
  standalone context vs. fold into the `test` aggregator (`needs:` at ci.yml). A required context
  that never reports blocks the merge queue → also closes "PR deletes its own job."
- **Enroll `rule-body-lint` in the existing required-check drift-guard cron** (SF-P1-5).

### Phase 4 — CODEOWNERS + recursion invariant + ADR
- **CODEOWNERS rows** (SEC-P1) for: `AGENTS.core.md`, `AGENTS.rest.md`, `AGENTS.docs.md`,
  `scripts/lint-rule-bodies.py`, `.claude/rule-body-hashes.txt`, `.claude/rule-weakening-acks.txt`
  (explicit `@deruelle` rows, matching repo convention).
- **Recursion test** (ARCH-P1-a/b, SEC-P1, SF-P1-6): `import { TARGET_ALLOW_RE }` from
  `cron-compound-promote.ts`; assert the manifest, ack file, `lint-rule-bodies.py`, `ci.yml`,
  `lefthook.yml`, the ADR, and the `.c4` files are all ∉ `TARGET_ALLOW_RE`; AND assert the
  *property that matters* — a synthetic proposer diff to `AGENTS.core.md` that weakens a body or
  drops a security tag IS caught by `--check` (not the vacuous ∉ tautology).
- Author ADR-092 (Provisional) + the `AP-017` register row per the ADR section.

## Files to Create
- `scripts/lint-rule-bodies.py` — gate (`--check`) + generator (`--write`).
- `.claude/rule-body-hashes.txt` — committed sha256-per-rule-body manifest (baseline).
- `.claude/rule-weakening-acks.txt` — CODEOWNERS-owned WORM ack (header + `<id>|<sha256>|<date>|<PR>|<reason>` format).
- `knowledge-base/engineering/architecture/decisions/ADR-092-*.md` — Provisional ADR (via `/soleur:architecture`).
- Test file(s) mirroring `lint-rule-ids.py`'s harness (path/runner verified at Phase 0).

## Files to Edit
- `.github/workflows/ci.yml` — add `rule-body-lint` job.
- `scripts/ci-required-ruleset-canonical-required-status-checks.json` — add the `rule-body-lint` context.
- `infra/github/ruleset-ci-required.tf` — add the `rule-body-lint` required context.
- `.github/CODEOWNERS` — explicit rows for the new load-bearing files + the three sidecars.
- the required-check drift-guard cron workflow — enroll `rule-body-lint`.
- `knowledge-base/engineering/architecture/principles-register.md` — `AP-017 → ADR-092` row.
- `knowledge-base/project/specs/feat-harness-auto-edit-safety-policy/tasks.md` — generated from this plan.

## Acceptance Criteria

### Pre-merge (PR)
- AC1: A diff that changes an `hr-*` body under a stable id **without** a matching per-change ack is
  BLOCKED by `--check` (exit non-zero, message naming the id).
- AC2: A body change **with** a valid ack (`<id>|<sha256>|<date>|<PR>|<reason>`, `<sha256>` == the
  new body hash) PASSES.
- AC3: A **stale** ack (present for the id but `<sha256>` ≠ the current body hash — a *different*
  later weakening) is BLOCKED (SF-P0-2).
- AC4: **Deletion** of a body line under a retained `AGENTS.md` index id is BLOCKED absent an ack
  (ARCH-P2-a).
- AC5: A benign additive edit (new rule, fresh id) PASSES; a **new** id carrying a security tag
  emits the mandatory-human-review annotation (SF-P2-8).
- AC6: The gate re-derives sha256 itself (TR1) — a hand-edited manifest value not matching the body
  is BLOCKED.
- AC7: A no-op reformat (trailing whitespace / tag reorder within the normalization rule) does NOT
  trip the gate; calibration: **zero** findings on the committed baseline (~194 rules).
- AC8: Recursion test **imports** `TARGET_ALLOW_RE`, asserts the new load-bearing files (incl.
  `.claude/rule-weakening-acks.txt`) ∉ the allowlist, AND asserts a synthetic weakening/tag-drop
  diff to `AGENTS.core.md` IS caught (the real property, not the ∉ tautology).
- AC9: `rule-body-lint` runs in `ci.yml` **AND** appears in
  `ci-required-ruleset-canonical-required-status-checks.json` + `ruleset-ci-required.tf` (the merge
  is blocked while the check is RED) **AND** is enrolled in the required-check drift-guard cron.
- AC10: CODEOWNERS has explicit rows for all new load-bearing files + the three sidecars; Phase-0
  verification recorded whether CODEOWNERS-review is enforced on `main` (else the fallback path).
- AC11: `ADR-092-*.md` exists, `## Status: Provisional`, states the additive-only boundary + gate +
  recursion invariant + Lineage (ADR-054/069/027-stateless) + the ~2026-08-05 revisit trigger;
  `AP-017 → ADR-092` row added to the principles register.
- AC12: base is computed via `git merge-base origin/main HEAD` (not `origin/main` tip); the id→body
  map unions all three sidecars.
- AC13: `origin/main` full suite green (typecheck `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`; repo test runner per `package.json`).

### Post-merge (operator — automated)
- AC14: `Closes #6103` in the PR body; `#6038` updated with `Ref` (stays open, soak-gated) + a
  comment enumerating what was deferred into its build scope (lexer, LLM-judge, C4 component,
  lefthook mirror, soak follow-through).

## Test Scenarios
- Change hr-* body, no ack → BLOCK (AC1). With fresh ack → PASS (AC2). With stale (wrong-hash) ack → BLOCK (AC3).
- Delete a body line under a retained index id → BLOCK (AC4).
- New rule / fresh id → PASS; new id + `[compliance-tier]` → mandatory-review annotation (AC5).
- Tampered manifest hash → BLOCK (AC6). No-op reformat → PASS; baseline → zero findings (AC7).
- Recursion: files ∉ TARGET_ALLOW_RE (import) + synthetic core.md weakening IS caught (AC8).
- `wg-*` body moved core→rest + weakened → caught via the unioned base map (AC12).

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (CPO) — carried from the 2026-07-06 brainstorm.

### Engineering (CTO)
**Status:** reviewed (carry-forward + 4-agent plan panel)
**Assessment:** Minimal v1 — manifest + per-change hash-bound ack (all hr-/wg-) + required CI wired
to the canonical ruleset + drift-guard + recursion test. Lexer/LLM-judge/C4 deferred to the proposer
PR. Panel hardened: two-key/per-change ack, merge-base, sidecar union, deletion gate, real recursion
property, ruleset wiring. Design = small.

### Legal (CLO)
**Status:** reviewed (carry-forward)
**Assessment:** The per-change ack on ALL hard-rule bodies (WORM, CODEOWNERS-gated, hash-bound) is
the compliance-control force-function — stronger than a tag-scoped gate. Residual stated explicitly:
tamper-evidence + required human review, not full dual-control (accepted under solo-operator
de-ceremonialization).

### Product/UX Gate
**Tier:** none — no UI surface (Files are scripts/JSON/YAML/`.tf`/markdown). Mechanical override did
not fire. CPO sign-off carried from brainstorm (`requires_cpo_signoff: true`); scope-cut to v1
matches CPO "provisional, don't tune blind."

## Risks & Mitigations
- **Silent weakening lands.** Mitigation: ack required on EVERY hr-/wg- body change/deletion (not a
  reward-hackable lexer, not tag-scoped) — the core fix from the panel.
- **Self-ack / stale ack.** Mitigation: per-change hash binding (AC3) + CODEOWNERS-gated ack file +
  Phase-0 verification that CODEOWNERS-review is enforced (fallback: required approvals ≥ 1).
- **Required check silently downgraded.** Mitigation: ruleset wiring (AC9) + drift-guard cron.
- **Recursion — allowlist widened to reach the gate.** Mitigation: recursion test imports the live
  `TARGET_ALLOW_RE` (rots-safe) + asserts the real catch property (AC8).
- **merge-base vs origin/main-tip false blocks.** Mitigation: `git merge-base` (AC12).

## Sharp Edges
- Test path/runner verified at Phase 0 against the `lint-rule-ids.py` sibling — do NOT hardcode.
- ADR ordinal 091 provisional; re-verify at ship + sweep planning docs on renumber.
- Adding a required context: audit every bot-PR-creating workflow for synthetic-check updates
  (branch-protection sharp edge) — a new required context can wedge bot PRs that don't report it.
- `.tf`/`.json` ruleset edits are CODEOWNERS-pinned and R15-audited — expect a review gate.

## Non-Goals
- NG1: The auto-proposer BUILD (deferred under #6038; soak-gated ~2026-08-05).
- NG2: The **deontic-strength lexer** — deferred to the #6038 proposer PR (guards a machine writer
  that doesn't exist yet; thresholds need soak evidence).
- NG3: The **LLM-judge** — deferred (advisory-only; belongs with the proposer).
- NG4: The **C4 `rulebodygate` component** — deferred until the proposer actor is modeled (honest edge).
- NG5: The **lefthook mirror** — deferred (required CI is the load-bearing gate).
- NG6: The **#6038-soak follow-through** enrollment — belongs to #6038's build.
- NG7: Extending `cron-compound-promote.ts`'s `diffRemovesHardRule` — deferred to the build.
