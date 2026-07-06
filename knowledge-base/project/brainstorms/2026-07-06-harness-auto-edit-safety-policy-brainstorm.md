---
date: 2026-07-06
topic: Additive-only auto-edit policy for AGENTS.md hard rules + semantic-weakening detector (Self-Harness Layer 2 prerequisites)
issue: 6038
parent_brainstorm: knowledge-base/project/brainstorms/2026-07-05-self-improving-harness-brainstorm.md
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Brainstorm: Harness Auto-Edit Safety Policy — Semantic-Weakening Detector + Additive-Only Boundary

## What We're Building

The **unblocked prerequisites** for #6038 (the eval-gated additive-only auto-proposer, Self-Harness
Layer 2). The full auto-proposer BUILD is soak-gated (#6038 criterion 1 needs ≥1 month of #6037
weakness-digests and cannot clear before ~2026-08-05). But two of #6038's three re-evaluation
criteria — and the landmine it names ("the `cq-rule-ids-are-immutable` gap must be closed first") —
are **independent of the soak** and are the real safety design work. This brainstorm scopes them:

1. **An ADR (ADR-092, marked Provisional)** defining the *additive-only boundary* (which self-edits
   may auto-flow to a draft PR vs. which are human-only) and the *semantic-weakening detector*.
2. **A landed semantic-weakening detector** — a standalone CI gate (committed `sha256` body-hash
   manifest per `hr-*`/`wg-*` rule + a deterministic deontic-strength lexer) that blocks ANY diff
   (human, other bot, or the future proposer) that edits/weakens a hard-rule body without a
   hash-manifest bump + explicit human ack. Protects the harness **today**, regardless of whether
   the auto-proposer ever ships.
3. **Assigning the "harness evolution safety" owner** (#6038 criterion 3) — de-ceremonialized for a
   solo-operator project to a *required CI check + explicit operator ack*, not an org-chart role.

Explicitly **NOT** in scope: the auto-proposer build itself (stays deferred under #6038, soak-gated).

## Why This Approach

**The gap is verified in code, not just asserted.** The existing guardrail
`cron-compound-promote.ts:216` (`diffRemovesHardRule`) refuses any diff that *removes a line*
containing `[id: hr-` — and only when `target_path === "AGENTS.core.md"` (`:529`). It is a
line-removal regex. An in-place prose edit of a rule **body** ("Never X" → "avoid X where practical")
removes no `[id: hr-` line, changes no ID, and sails through every existing gate: the target-path
allowlist (`TARGET_ALLOW_RE`), the byte-budget, the PII filter, `lint-rule-ids.py` (ID-based only),
and the eval-gate (ADR-069 — measures skill-arm fixture pass-rate, *not* guardrail coverage). This
is exactly the Goodhart failure the 2026-07-05 parent brainstorm flagged (lines 45–51).

**Land the detector now = highest no-regret value.** The detector is valuable independent of the
auto-proposer: it closes the `cq-rule-ids-are-immutable` gap for real (that linter blocks ID *reuse*
but not body *weakening*), and it protects against a human or any other bot silently weakening a
hard rule during the 1-month soak. The eventual Layer-2 build then reuses it as a ready-made gate.

**CI must re-derive all gating values — never trust proposer-supplied.** The 2026-05-11
compound-promote P1 post-mortem names the precise vector: "hash covers field A but the security
decision depends on field B." The hash manifest MUST be computed by CI over the actual sidecar body
lines, never accepted from an LLM/proposer.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope | **Prerequisites only** (ADR + detector + owner + close cq gap); NOT the auto-proposer build | Build is soak-gated (#6038 crit 1 unmet until ~2026-08-05); prereqs are independent. |
| Build depth | **ADR + land the detector now** | No-regret: protects harness today, hands the future build a ready-made gate. |
| Detector = hybrid | **Deterministic lexer (hard block) + CI-computed sha256 body-hash manifest (hard gate) + LLM-judge (advisory only)** | Deterministic layers fail-closed; the judge may NOT unblock what the lexer flags (it is the same reward-hackable class). |
| Hashing unit | **One sidecar body line per `[id:]`** (rules are single-line per `cq-agents-md-why-single-line`) | Bodies live in `AGENTS.{core,docs,rest}.md`, not the `AGENTS.md` index; hash the body line. |
| Weakening signal | Deontic strength downgrade (`never\|must not\|always\|MUST` → `avoid\|should\|prefer\|where practical`), hedge insertion, net token deletion, quantifier/enumerated-case removal | Deterministic, reproducible; `cq-regex-unicode-separators-escape-only` applies to the lexer. |
| Additive-only boundary | Append-only at the rule-SET level. New rule / new skill section = auto draft-PR. **Any edit to an existing `hr-*`/`wg-*` body = human-only. Any rule deletion = human-only hard block.** | The safe primitive is "add a rule," never "revise a rule." |
| Compliance-control class | **Reuse the existing inline `[compliance-tier]` tag** (already on e.g. `hr-never-paste-secrets`, plus `hr-gdpr-gate`'s `[hook-enforced]`) — any diff touching a `[compliance-tier]` rule auto-flags mandatory human review, never auto-flow even additively | CLO: additive text can narrow scope without deleting a line; no new manifest needed. |
| Recursion invariant | The allowlist + hash-manifest + detector code MUST stay outside the auto-editable target set (currently true: they live in `.ts`/`.py`, targets are `AGENTS.core.md` + `SKILL.md`) — ADR pins this | CTO: AGENTS.md is now both proposer target AND guardrail source; a bot PR must never edit the allowlist governing bot PRs. |
| Owner assignment | **De-ceremonialized**: required CI check (detector blocks additive-boundary violations) + rule that any harness self-edit needs explicit operator ack. No named person. | CPO: "assign an owner" for a solo operator collapses to a review gate, not an org role. |
| ADR status | **Provisional — revisit after #6037 soak** (named trigger: first digest with N samples) | CPO: designing containment with zero digest evidence risks over-fitting; keep principles + constraints, defer tuned thresholds to the soak. |
| ADR authoring | Authored at plan time via `/soleur:architecture create` (`wg-architecture-decision-is-a-plan-deliverable`) | Brainstorm captures WHAT; the ADR + detector code are plan/work deliverables. |
| Human-ack mechanism | Body change to an `hr-*`/`wg-*` rule requires a matching hash-manifest bump in the same commit (an operator's deliberate act) + lexer-pass; a weakening lexer-hit blocks pending explicit ack | Makes ID-stable body edits impossible to slip through silently. |
| Visual design | N/A — no UI surface (pure harness/CI infra) | Phase 3.55 trigger boundary. |
| LLM-authored-edit hygiene | Any future proposer edit must have its cited rule IDs grep-validated against `AGENTS.md` + `retired-rule-ids.txt` (LLMs fabricate plausible IDs) | Deferred into the ADR's proposer requirements; folds the 2026-05-09 fabrication learning in. |

## Open Questions (resolve at plan / ADR time)

- **Manifest location & format:** `.claude/rule-body-hashes.txt` vs. an extension of `rule-metrics.json`
  vs. inline. Lean: a dedicated committed JSON keyed by rule id → `sha256(normalized body line)`,
  regenerated by a script and CI-verified (so a stale manifest fails closed).
- **Detector home:** extend `scripts/lint-rule-ids.py` (already the lefthook rule-ID gate) vs. a
  sibling `scripts/lint-rule-bodies.py`. Lean: sibling script, same lefthook + CI wiring, to keep
  ID-immutability and body-weakening as separable concerns.
- **Normalization for hashing:** trailing-whitespace / tag-ordering normalization so a
  no-op reformat doesn't spuriously trip the gate — but not so aggressive it masks a weakening.
- **Lexer strength lexicon:** the exact deontic marker sets and the hedge-word list; calibrate the
  false-positive rate against the current ~77-rule corpus before wiring as a hard block.
- **`wg-*` coverage:** confirm whether workflow gates get the same body-hash protection as `hr-*`
  (lean: yes — a weakened `wg-` is as dangerous as a weakened `hr-`).
- **Human-ack UX:** is the ack purely "bump the hash manifest yourself," or also a required PR-body
  token / label for `[compliance-tier]` touches (CLO wants a recorded, tamper-evident approval)?

## User-Brand Impact

- **Artifact:** the semantic-weakening detector + additive-only policy (the mechanism that decides
  which self-edits to `AGENTS.md`/skills may auto-flow to a draft PR, and blocks silent guardrail
  weakening).
- **Vector:** an auto-approved (or silently human-missed) edit narrows/removes an existing `hr-*`
  guardrail — e.g. `hr-gdpr-gate-on-regulated-data-surfaces` or `hr-never-paste-secrets` — while
  still passing the eval (Goodhart), disabling a protection that prevents a user-data / secret-leak
  incident.
- **Threshold:** single-user incident.

Tagged user-brand-critical (auto, per #5175). The detector is itself the primary control: it makes
silent hard-rule weakening a fail-closed CI block rather than a reviewable-but-missable diff. The
`[compliance-tier]` sub-class escalates the most safety-load-bearing rules to mandatory human review
on ANY touch. The recursion invariant (guardrail code outside the auto-editable set) prevents the
harness from disarming its own containment.

## Domain Assessments

**Assessed:** Engineering (CTO + repo-research + learnings, full fan-out), Legal (CLO), Product (CPO).
Marketing, Operations, Sales, Finance, Support — not relevant (internal harness/CI infra; no
external, user-facing, credential-provisioning, or vendor-cost surface).

### Engineering (CTO)

**Summary:** Detect weakening with a hybrid — a deterministic deontic-strength lexer as the
fail-closed hard block plus a CI-computed `sha256` body-hash manifest, with an LLM-judge as advisory
only (never allowed to unblock the lexer). Additive = append-only at the rule-set level; `hr-*`/`wg-*`
bodies are off-limits to any auto-proposer. Close the immutability gap with the content-hash pin.
Biggest risk: the harness eroding guardrails the eval doesn't measure — minimal containment is
draft-PR-only (never auto-merge), hr-/wg- bodies off-limits, a hash-manifest CI gate independent of
the harness, and a guardrail-count invariant. Recursion risk: pin the allowlist + manifest outside
the auto-editable target set. Design now = small; eventual build = medium, gated on soak.

### Legal (CLO)

**Summary:** An automated actor editing its own control library is a segregation-of-duties problem —
the auto-flow's write scope must be *technically incapable* of a net-removal/weakening diff on a
governed rule, not merely policy-aspirational. Tag a subset of `hr-*` as compliance controls (reuse
the existing `[compliance-tier]` marker) — any diff touching them, even additive/draft, auto-flags
mandatory human legal review with a recorded, tamper-evident approval (approver, timestamp,
before/after, justification). Split ownership: CTO owns the detector mechanism; CLO owns the
compliance-control classification + attestation. Draft-only is not a safe harbor — a merged draft is
a merged change.

### Product (CPO)

**Summary:** Scoping to the prerequisites is the correct call — building the auto-proposer before
soak evidence would tune containment blind. The semantic-weakening detector is the highest-value
deliverable because it protects the harness regardless of whether the proposer ever ships; prioritize
landing it over polishing ADR prose. "Assign an owner" for a solo operator collapses to a required CI
check + operator ack — skip the org-chart framing. Mark the ADR **Provisional / revisit after soak**
with a named revisit trigger; keep it principles + constraints, not tuned thresholds (thresholds are
what the soak calibrates).

## Capability Gaps

- **No semantic-weakening detector exists** (engineering). Evidence: `cron-compound-promote.ts:216-221`
  (`diffRemovesHardRule`) is a line-removal regex scoped to `AGENTS.core.md`; `scripts/lint-rule-ids.py`
  (lines 129-143, 474-488) is ID-based only (rejects ID removal, enforces `HR_RETIREMENT_ALLOWLIST`,
  but sees no change when a body is reworded under a stable ID); ADR-069 eval-gate measures skill-arm
  fixture pass-rate, not guardrail coverage; `rule-metrics.json` carries telemetry counters + a
  `rule_text_prefix` only, no semantic baseline. No primitive baselines or diffs rule-body *strength*.
- **No content-hash manifest of rule bodies exists** (engineering). Evidence: grep of `.claude/`,
  `scripts/`, and `knowledge-base/project/rule-metrics.json` found no `sha256`-per-rule-body artifact;
  the only committed rule registry is `rule-metrics.json` (telemetry) + `retired-rule-ids.txt` (IDs).
- **No "harness evolution safety" owner assigned** (Product + CTO), per #6038 criterion 3. Resolved
  here as a de-ceremonialized required-CI-check + operator-ack, not an org role.

## Session Errors

- **#6038 build gate not met — re-scoped to prerequisites.** Premise probe at Phase 0 found #6037
  (criterion 1's dependency) shipped 2026-07-05 (PR #6036, closed 16:11), so "≥1 month of digests"
  cannot clear before ~2026-08-05; criteria 2 (ADR) and 3 (owner) were both unmet (only the parent
  brainstorm doc mentions the phrases). Surfaced to the operator, who chose to do the unblocked
  prereqs now rather than park or override. Prevents a wasted full-build brainstorm violating the
  issue's own gate.
- **Concurrent-session worktree reaping.** The first `worktree-manager.sh feature` run created and
  pushed `feat-harness-auto-edit-safety-policy` (branch + remote tracking), but the worktree dir AND
  the remote branch were wiped within ~1 minute despite the session lease — a concurrent session's
  worktree churn (the `git worktree list` changed mid-session). Recreated + pushed the draft PR
  (#6101) immediately. Matches `2026-04-21-concurrent-cleanup-merged-wipes-active-worktree.md` but
  more aggressive (remote branch deleted too) — flagged for follow-up if it recurs.
