---
title: "SWE-2 Flash adoption on the Devin harness — docs + routing"
date: 2026-11-05
slug: feat-swe2-flash-devin-tiering
branch: feat-swe2-flash-model-tiering
issue: none
type: feat
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# SWE-2 Flash adoption on the Devin harness — docs + routing

## Overview

Route Soleur's cheap-tier subagent work on Devin onto Devin's own cheap mechanism —
`subagent_explore` (router-default model) for spawns needing no exec/git/`gh`, operator
opt-in `agent.subagent_model: "swe-2-flash-medium"` documented with its disclosure
caveats — correct the stale "Claude model aliases are not Devin model identifiers" claim,
record an ADR-110 addendum, and add a Devin freshness item to `model-launch-review`.
No `TIER_MAPS.devin` row and no profile generator: deferred behind the three measured
gates in #12141.

## Research Insights

**Premise validation (Phase 0.6).** Verified live this session: `TIER_MAPS` lacks `devin`
(`lib/harness-model-map.ts:53-75`, warn→inherit at :84-89); the stale claim sits at
`devin/INSTRUCTIONS.md:247-248`; five research agents pin `model: haiku`; `devin models`
(run 2026-11-05, authenticated) lists `swe-2-flash-medium`/`-high`/`-max` (family
`swe-2-flash`, all `Free, new`). ADR-corpus check (item 4): the mechanism — prose routing
to `subagent_explore` + user-scope config opt-in + `inherit` fallback — appears in no
ADR's rejected-alternatives table; ADR-110's Grok addendum (#8604) is the direct
precedent (unrecognized `model:` on a second harness warns and bills the session
default, so the Grok generator omits it — the same caution defers Devin profile pins).
No cited issue/PR premises to re-validate (#12135 and #12141 were created this session).

**Mechanism minimality (Phase 0.6b).** Property list: (P1) cheap-tier Devin subagent work
can land on a cheaper model; (P2) the stale alias claim stops being asserted; (P3) a
Cognition launch enters the recurring freshness checklist; (P4) the routing rule is
pinned against silent removal. Cut list: `TIER_MAPS.devin` row → P1 partially but has NO
consumer on Devin (canonical spec read as prose; nothing resolves it at spawn time) →
covered by `resolveModelTier` warn→inherit; custom subagent profile generator → P1 for
write-capable spawns, a need that does not exist yet and is unmeasured → deferred
(#12141). Kept: INSTRUCTIONS.md edits (P1+P2), model-launch-review row (P3), a phrase pin
in a devin test file (P4 — SpecFlow finding: G1 would otherwise be vacuous).

**Value-proposition (Phase 0.6c).** The saving is real but unquantified at plan time:
Flash is free through 2026-11-30 (Cognition announcement; verified `Free` tag in
`devin models`), and its post-promo rate card is unpublished. The measurable claim made
here is narrower — routing explore traffic to the router default costs whatever the
router picks (unlabelled in-session), and the opt-in key exists. The post-promo rate +
router-model attribution are recorded as open measurements, not plan justification.

**Research consolidation (Phase 1.7).** Edit inventory (repo-research-analyst):
INSTRUCTIONS.md §Domain agents :239-252 (edit site), :320 (existing exec/git carve-out —
extend, never contradict), :321-323 polling-loop guidance (names no profile — pin it to
`subagent_general` since loops need exec). model-launch-review collateral: lines 18, 26,
57, 168 plus new row after :51. AGENTS.md: append Devin bullet after :189. ADR-110:
addenda sit before `## Alternatives considered` (:85), format `## Addendum — <date>
(<topic>, <issue-ref>)`. Test pins to respect (do NOT violate): `devin-harness.test.ts:108`
pins the generated `harness.ts` string (not this file); `pr-merge-poll.test.ts` pins the
`:310` queue_wait phrase AND reads this file; `devin-cloud-mode.test.ts` pins cache-path
+ identity-recipe presence in §Detection; `invocation-axis.test.ts` flags unacked
user-invoked-skill names in `devin/**/*.md`; no `--fence` literal. Learnings:
`2026-10-24` profile-split convention already in use (explore=read-only rulings,
general=write/review payloads) — this plan documents the convention, doesn't invent it;
`2026-11-01` Devin subagents cannot nest (routing guidance is parent-scoped);
`2026-11-02` free-model subagents die at rate limit rather than retry.
Functional-overlap: `agent.subagent_model` and a Devin freshness row are ABSENT
everywhere shipped; `.grok/agents/` 67 stubs are the profile-generator precedent.

## Problem Statement

On the Devin harness Soleur gives no cheap-tier guidance: `devin/INSTRUCTIONS.md` tells
every spawn to "inherit the session model", asserts a false claim that Claude model
aliases are not Devin model identifiers, and never names the profile lever that decides
cost (`subagent_explore` → server-side router default, pinnable; `subagent_general` →
parent model). Read-only fan-out therefore rides the parent's model unnecessarily, and
the operator has no documented path to route it cheaper.

## Proposed Solution

Docs+routing (Approach A from the brainstorm; B deferred to #12141):

1. **INSTRUCTIONS.md §Domain agents (:239-252)** — rewrite the spawn guidance:
   - Profile rule keyed on TOOL SURFACE (SpecFlow/CPO C3): "spawn `subagent_explore`
     when the task needs read/grep/glob/web_search and nothing else; anything running
     `exec`, `git diff`, test suites, or `gh` (including the exit-coded polling loops of
     §Polling) spawns `subagent_general` — `subagent_explore` has no exec tool." Mixed or
     uncertain → `subagent_general`. Cross-reference the :320 carve-out so the two
     statements cannot drift.
   - Model semantics: `subagent_explore` lands on the router's default subagent model;
     `subagent_general` inherits the parent's model (per docs.devin.ai/cli/subagents —
     phrase per docs; whether `agent.subagent_model` reaches `subagent_general` is
     undocumented, do not assert it).
   - Operator opt-in (CPO C1/C2/C6): `agent.subagent_model: "swe-2-flash-medium"` in
     `~/.config/devin/config.json` — user-scope only, ignored when org-disallowed; the
     CLI does not label a running subagent's model, so the pin's effect is
     unverifiable in-session (checks: `devin models` allowlist, admin policy, Soleur's
     tier `log()` line); free through 2026-11-30 with no published post-promo rate card;
     Free-plan accounts get SWE-1.6 only; local CLI/Desktop only — cloud sessions are
     unaffected.
   - Correct the alias claim (SpecFlow 10): Claude family aliases DO resolve on Devin —
     on model-SELECTION surfaces (`--model`, `/model`, config `model:` fields), NOT as
     `run_subagent` arguments, which take a profile.
   - Scope the guidance to the parent agent: `devin/INSTRUCTIONS.md` is injected into
     every spawned subagent's prompt (`harness.ts:392`) and Devin subagents cannot nest.
   - Pin §Polling's spawn profile: exit-coded poll loops need exec → `subagent_general`.
2. **§Devin-specific considerations :320** — extend the existing bullet with the
   model-inheritance dimension (one sentence; keep the #8471 capability carve-out).
3. **ADR-110 addendum** `## Addendum — 2026-11-05 (Devin harness / SWE-2 Flash launch)`
   before `## Alternatives considered`: measured `devin models` output (CLI version +
   date), the router-not-SKU decision, org-allowlist silent-degradation, Free-plan
   boundary, promo expiry, the profile-arg/registry-id seam and the stale
   generated-string caveat (CPO C4) recorded against #12141, and the title's
   "(Claude Code + Grok Build)" scope note — third-vendor addendum.
4. **model-launch-review SKILL.md** — new checklist row 7 (Devin freshness:
   compare `devin models` output against Devin slugs Soleur references —
   `agent.subagent_model` guidance + ADR-110 addendum); collateral edits at lines 18
   (xAI→+Cognition), 26 (invoke trigger), 57, 168 (flag list).
5. **plugins/soleur/AGENTS.md** — Devin-mapping bullet after :189: the five
   `model: haiku` research agents map to `subagent_explore` + `agent.subagent_model` on
   Devin; `model: haiku` frontmatter is inert there.
6. **Test pin (P4)** — extend a devin test file (e.g. `devin-harness.test.ts` or a new
   small suite) asserting INSTRUCTIONS.md carries the explore/general tool-surface rule
   and the `agent.subagent_model` key, so the routing guidance can't silently rot.

## Files to Edit

- `plugins/soleur/devin/INSTRUCTIONS.md` (§Domain agents, §Devin-specific considerations, §Polling)
- `knowledge-base/engineering/architecture/decisions/ADR-110-harness-semantic-model-tier-map.md` (addendum)
- `plugins/soleur/skills/model-launch-review/SKILL.md` (row 7 + collateral)
- `plugins/soleur/AGENTS.md` (Model Selection Policy bullet)
- `plugins/soleur/test/devin-harness.test.ts` (or sibling — phrase pins)

## Implementation Phases

- **Phase 1 — Edits:** items 1–5 above in one pass, then run the devin suites
  (`devin-harness.test.ts`, `devin-cloud-mode.test.ts`, `devin-plugin.test.ts`,
  `pr-merge-poll.test.ts`, `invocation-axis.test.ts`, `model-launch-review.test.ts`,
  `harness-model-map.test.ts`) + `c4-count-parity.test.sh`.
- **Phase 2 — Test pin + verify:** item 6; re-run the touched suites.

## User-Brand Impact

- **If this lands broken, the user experiences:** plugin instruction prose that misroutes
  spawns (breaking `gh`/exec-requiring seats on a no-exec profile) or steers an operator
  into a billing-relevant config under a silently-expired promo — a wrong instruction in
  `devin/INSTRUCTIONS.md` is the runtime spawn contract for every Devin session.
- **If this leaks, the user's [money] is exposed via:** an undocumented post-promo rate
  card after 2026-11-30, or a silently-ignored `subagent_model` the operator believes is
  active (no in-session model label exists).
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** docs diff, but the docs are the runtime spawn
  contract AND instruct a billing-relevant operator config — a silently-wrong instruction
  reaches exactly one operator's money/review integrity, not a class.

## Domain Review (carry-forward)

### Engineering (CTO — brainstorm assessment)

Canonical-spec reality: `harness-model-map.ts` is prose consumed by tests; the spawn path
is instruction text. `cheap → swe-2-flash` only earns a `TIER_MAPS.devin` row with a real
consumer; `standard`/`strong`/`advisor` → `inherit` is the honest value on a
heterogeneous-family harness. Sequence: config opt-in docs → explore routing → profiles
only after the registration probe. ADR-110 addendum, not a new ADR.

### Operations (COO — brainstorm assessment)

Per-token meter under credits/ACU — router pricing genuinely cuts marginal cost; Flash
free through 2026-11-30, no published post-promo card. Org policy: disallowed keys are
silently ignored; Default-subagent-model=None disables `run_subagent` org-wide; Free plan
is SWE-1.6-only — the router is the always-available entity, not any SKU. Spend
attribution: the CLI labels no running subagent's model; Soleur's tier `log()` line is
the only in-repo trail; `expenses.md` has no Devin row (operator item).

## GDPR note (Phase 2.7)

Invoked via trigger (b) (declared threshold). Diff surface is docs+KB only — zero paths
match the canonical regex, no new processing activity, no distribution surface change.
No findings.

## Architecture Decision (ADR/C4)

- **ADR:** amend `ADR-110-harness-semantic-model-tier-map.md` — dated addendum (item 3 of
  Proposed Solution). In-scope plan task, not a follow-up.
- **C4 views:** no C4 impact. Enumeration checked: (a) external human actors — operator/
  founder, already modeled; (b) external systems — Devin/Cognition modeled at
  `model.c4:36` (`devin = system "Devin (CLI + Cloud)"`); (c) containers/data-stores —
  none touched (docs-only); (d) relationships — `founder -> devin` (:41) unchanged.
  Cardinalities unaffected: `plugins/soleur/test/c4-count-parity.test.sh` ran green
  (13/13) this session.
- **Sequencing:** the addendum describes the adopted state now (router + opt-in) and
  records the deferred SKU-pin decision against #12141's measurement gates.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "shall we update Soleur to make use of it at the right spots/skills in our workflow?" | Proposed Solution 1–5 (docs+routing to the cheap spots) | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|-----------|------------------|---------|
| INSTRUCTIONS.md routing + opt-in text | ask 1 | asked (scoped via brainstorm option A, operator-selected) |
| ADR-110 addendum | ask 1 | inferred — `wg-architecture-decision-is-a-plan-deliverable` |
| model-launch-review Devin row | ask 1 ("skills in our workflow") | inferred — freshness checklist is the recurring-model-release mechanism |
| AGENTS.md Devin note | ask 1 | inferred — Model Selection Policy is the canonical tier-map prose |
| test phrase pin | — | inferred — SpecFlow finding: unguarded routing prose rots silently |

### Split Assessment

- Subsystems touched: 1 — `plugins/soleur/` (+ `knowledge-base/` artifacts)
- Planned files: 5 | Estimated changed lines: ~110
- Recommendation: single PR

## Acceptance Criteria

- [ ] INSTRUCTIONS.md §Domain agents routes on tool surface (no-exec → `subagent_explore`,
      exec/git/`gh` → `subagent_general`), cross-references the :320 carve-out, scopes the
      guidance to the parent, and pins §Polling loops to `subagent_general`
- [ ] `agent.subagent_model` opt-in text carries: user-scope only, org-allowlist
      silent-ignore + unverifiable-in-session, promo expiry 2026-11-30 + no published
      post-promo card, Free-plan SWE-1.6 boundary, local-only scope
- [ ] The alias claim reads true: aliases resolve on model-SELECTION surfaces, never as
      `run_subagent` args
- [ ] ADR-110 addendum committed with measured `devin models` output, the router
      decision, caveats, and the profile-arg/registry-id seam under #12141
- [ ] `model-launch-review` carries the Devin freshness item + collateral edits
- [ ] AGENTS.md Model Selection Policy carries the Devin mapping note
- [ ] A test pins the routing phrases so they cannot silently rot
- [ ] All named devin test suites + `c4-count-parity.test.sh` pass
- [ ] PR #12135 body carries `**Brand-survival threshold:** single-user incident` + the
      decision sentence (CPO C5)

## Test Scenarios

- `unit`: the new phrase pin fails when the routing rule or `agent.subagent_model` key is
  removed from INSTRUCTIONS.md (mutation-check by deleting a phrase locally, expect red).
- `unit`: existing devin suites stay green — INSTRUCTIONS.md text edits must not violate
  `pr-merge-poll`, `devin-cloud-mode`, `invocation-axis` pins.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-11-05-swe2-flash-devin-tiering-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-swe2-flash-model-tiering/spec.md`
- Deferred machinery: #12141 | PR: #12135
- ADR-053, ADR-110 (+#8604 Grok research-stubs addendum precedent)
- `devin models` measured 2026-11-05; docs.devin.ai/cli/{subagents,models}
