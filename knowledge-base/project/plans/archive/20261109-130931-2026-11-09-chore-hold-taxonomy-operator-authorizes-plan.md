---
title: "chore: hold taxonomy gains an operator-authorizes class — runnable prod acts stop surfacing as operator errands"
type: chore
date: 2026-11-09
slug: chore-hold-taxonomy-operator-authorizes
branch: feat-one-shot-12443-operator-authorizes-class
issue: 12443
closes: 12443
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# chore: hold taxonomy gains an operator-authorizes class — runnable prod acts stop surfacing as operator errands

Closes #12443. Spec lacks `lane:` — defaulted to cross-domain (TR2 fail-closed).

## Overview

The hold taxonomy has three classes — Class R (agent runs freely), delegated (the four-command
`gh` grammar under a recorded standing approval), and `Operator-reserved:` (the operator does it).
There is no fourth class for **operator-authorizes, agent executes**, even though
`hr-menu-option-ack-not-prod-write-auth` (AGENTS.rules.md:46) already permits production writes on
a typed per-command go-ahead and standing-delegation.md section 9's hard limits already name
"in-session per-command owner go naming the command" as the authority for non-delegated writes.
The classification machinery therefore collapses every non-grammar, non-Class-R act into
"Needs you" as if the operator's hands were required — measured live 2026-11-08 (#12443 diagnosis):
five Needs-you items, zero of them requiring the operator's hands.

This plan adds the fourth class as a second hold-word prefix, `Operator-authorizes:`, splits every
classification/set-aside/write site onto the two reserved-family classes, and fixes the secondary
defect: delegation Scope drafted act-by-act instead of enumerating the epic's full remaining
grammar-compatible chain. It does NOT widen the delegation grammar, the denylist, or the
verifier-pinned Excluded sentence (tracked as #12479).

## Research Insights

**Premise Validation (Phase 0.6).** Issue #12443 is OPEN, title/state verified by `gh issue view`.
All cited paths exist on `origin/main` (`git show`): `plugins/soleur/commands/go.md`,
`plugins/soleur/skills/ship/references/operator-holds.md`,
`plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md`,
`plugins/soleur/agents/engineering/cto.md`,
`plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md`,
`plugins/soleur/skills/ship/scripts/hold-gate-eval.sh`,
`plugins/soleur/scripts/delegation-verify.sh`. Cited issues: #10390 OPEN (epic), #12380 CLOSED.
`hr-menu-option-ack-not-prod-write-auth` verified at AGENTS.rules.md:46. Mechanism-vs-ADR check:
ADR-289 (the standing-delegation envelope, `adopting`), ADR-249, ADR-264, ADR-302, ADR-309 read —
no rejected-alternative collision; the proposed class is the already-sanctioned per-command-go lane
(§9 hard limits, §8.1c's "the founder says go in the session for that action"), only missing a
classification slot. Collision precheck (`scripts/collision-precheck.sh 12443`): `prs=none`; a
foreign `test-all.sh` run lives in worktree `feat-one-shot-cloud-sandbox-gh-auth-missing` on a
different issue — reported, not a duplicate.

**Property List (Phase 0.6b).**

- P1: a hold whose act the agent can run after a typed go is classified and rendered as
  "say go and I run it", never as an operator-hands errand.
- P2: a hold that reserves a founder-ONLY act (console-only, credential entry, payment,
  2FA/CAPTCHA, signing a record, closing a tracker, arming PRs, webhook-secret change, credential
  minting) still classifies as operator-executes and still always stands.
- P3: the standing-delegation Scope is drafted from the epic's full remaining grammar-compatible
  act chain, not the next few acts.
- P4: the delegation grammar, denylist, and Excluded sentence stay byte-identical.

**Cut List.** None — every mechanism the issue proposes maps to a property no existing mechanism
buys (P1's slot does not exist; §8.1c's render and §9's hard limits carry the *authority* but no
classification slot produces it). No new machinery beyond the issue's ask is invented.

**Value-Proposition check (0.6c):** not a cost/performance claim — no measurement owed.

**Relevant learnings.**

- `knowledge-base/project/learnings/2026-11-03-a-read-only-class-is-only-as-closed-as-its-per-item-pins-and-its-heading-must-not-match-the-trigger-it-feeds.md` —
  the Class R precedent: same closed-boundary-class addition; four defect classes apply verbatim —
  (a) a heading/label is a match target (the new printed verdict line must not match
  `OWNER_HEAD_RE`/`PARKED` vocabulary; `Say go and I run it:` chosen — `Needs your go:` /
  `Your go:` / `Awaiting your go:` all collide), (b) pin per-item members by equality not presence,
  (c) three files must say the same thing about the boundary, (d) state plainly what the text
  cannot yet do.
- `knowledge-base/project/learnings/2026-11-03-a-pause-label-the-hook-offers-becomes-a-parking-lot-for-agent-owned-steps.md` —
  `unkept-promise-hook.sh` `PARKED_AUTH_RE` already licenses a per-command prod-write pause; a
  go-wait is a legitimate `Paused:`/`Blocked:` reason under "(b) an operator-reserved act
  (... production-mutating authorization)". No hook change needed.
- `knowledge-base/project/learnings/2026-04-17-regex-on-source-delegation-tests-trim-to-negative-space.md` —
  pin the normalized token the recognizer actually compares (`operatorauthorize`), not source
  spellings.

**Budget findings (Phase 1.8).** No `description:` field in any
`plugins/soleur/skills/*/SKILL.md` is edited — `SKILL_DESCRIPTION_WORD_BUDGET`
(`plugins/soleur/test/components.test.ts:22`, 2474) is untouched by design. Body budgets
(`plugins/soleur/test/skill-body-budget.json`): `ship` SKILL.md is 273937/273955 bytes — **18 bytes
of headroom**; `plugins/soleur/skills/ship/SKILL.md` is therefore excluded from Files to Edit and
all ship-side semantics route through `operator-holds.md` (which SKILL.md already links).

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality (verified 2026-11-09) | Plan response |
|---|---|---|
| "three classes, no fourth" | Confirmed — the hold-word prefix set is exactly `Operator-reserved:` (`reserved_hold()` at hold-gate-eval.sh:411-415, `tr -cd 'a-z0-9' | cut -c1-16` == `operatorreserved`); §9 hard limits name the go-lane but no class slot produces it | Add `Operator-authorizes:` as a second always-standing prefix with its own verdict line |
| "delegation Scope drafted act-by-act" | Confirmed — cto.md step 2 says "the Scope items (one per line...)" with no chain-completeness rule; standing-delegation.md §6 `{SCOPE_ITEMS}` has no drafting bound | Add the full-remaining-chain drafting rule at both sites |
| "denylist read as a bound on per-command authorization" | Confirmed — cto.md step 9's "Non-delegable, ever" list routes all of it to `action-required` issues / Undeferred Operator-Step Gate with no agent-execution arm | Split step 9's tail by executor: agent-reachable-after-go → `Operator-authorizes:`; founder-physical → `Operator-reserved:` |

## Problem Statement / Motivation

Each session is locally correct — the acts ARE outside the recorded Scope and DO hit the standing
delegation's closed denylist — but the denylist governs standing approvals, not per-command
authorization, so runnable work is presented as operator errands. Non-technical operators receive
lists of console tasks instead of go-lines. The denylist must stay closed; what is missing is the
class that says "the operator says go, then the agent runs it".

## Proposed Solution

**The fourth class.** `Operator-authorizes:` is a second hold-word prefix beside
`Operator-reserved:`, sharing its semantics (always stands, gates never probed, cleared only by
the operator) and differing in who runs the act after clearance: for `Operator-reserved:` the
operator does it (the closed physical founder-only list); for `Operator-authorizes:` the agent
restates the exact command in-session, the founder types a go naming it
(`hr-menu-option-ack-not-prod-write-auth` — a menu click or bare go is not a go, a key-rotation
workflow is never run without a typed go naming the exact command), the agent runs it, and the
line is removed or rewritten.

**Split rule (the classification boundary, stated identically everywhere).** An act is
`Operator-authorizes:` when it is outside the delegation grammar/denylist *and* the agent can name
a concrete command path for it *and* it is lawful under the §9 hard limits. It is
`Operator-reserved:` when it needs the operator's hands (the closed physical list) or reserves a
founder DECISION rather than an authorization to run an act. Never-authorizable acts (force-push
to main, bypassing required checks, editing the delegation, money/scope/legal/brand decisions)
stay operator categories or prohibited outright — `Operator-authorizes:` never covers them.

**The printed verdict.** `Say go and I run it: <words> - only you can say go` — checked against
`OWNER_HEAD_RE` (technical-ruling-gate.sh:107) and `PARKED_*` vocabulary: no `needs?`/`awaiting`/
`your go` collision (the 2026-11-03 heading-matches-its-own-trigger defect).

## Technical Considerations

**Cross-consumer sweep (hr-type-widening-cross-consumer-grep + hr-write-boundary-sentinel).** The
`Operator-reserved:` token family widens from 1 recognized prefix to 2. Every consumer found by
repo-wide grep (`Operator-reserved|operator-reserved|operatorreserved`):

| Consumer | Change? | Why |
|---|---|---|
| `hold-gate-eval.sh` `reserved_hold()` + `RESERVED` print + `classify_no_delegation` + eval loop | **yes** | recognize `operatorauthorize` (normalized[:16]); new verdict print; same always-stand/exit-2 semantics; skipped in no-delegation classification like reserved |
| `operator-holds.md` §1 format + class paragraph, §2 table, §3 prose-path, §5 prints | **yes** | document the second prefix, its print, its lifecycle |
| `commands/go.md` Step 1.5 (set-aside bullet, classification-route bullet, standing-delegation conversion sentence "must be written `Operator-reserved:`") | **yes** | `Operator-authorizes:` items + `ask me before`/`explicit go-ahead`/`operator approval`-phrased items → authorizes class; `Operator-reserved:` → executes class; second write target in the conversion rule |
| `agents/engineering/cto.md` Own-the-epic steps 2, 3, 9 | **yes** | step 2 Scope drafting from the epic's full remaining chain; step 3's `Operator-reserved:` write rule gains the second token; step 9's non-delegable tail splits by executor |
| `technical-ruling-delegation.md` §1 never-delegable tail + §8.1c Needs-you render | **yes** | §1's "written `Operator-reserved:` ... goes to the Undeferred Operator-Step Gate" splits; §8.1c gains the two line forms |
| `standing-delegation.md` §6 `{SCOPE_ITEMS}`, §9 carve-out paragraph + hard limits + Records | **yes** | §6: Scope enumerates the full remaining grammar-compatible chain; §9 carve-out adds the new token (Class R never applies to it either); Records' unverified-gated merge/deploy hold is written `Operator-authorizes:` (the act is agent-runnable after a go — see Decision Point) |
| `plugins/soleur/scripts/delegation-verify.sh` | **no** | grammar + denylist closed; the new class is not a delegation widening — `git diff origin/main` stays empty (AC7) |
| `plugins/soleur/skills/ship/SKILL.md` | **no** | 18-byte body-budget headroom; §1949's "route a person-only hold to the Undeferred Operator-Step Gate" keys on `Needs a person` verdicts — an `Operator-authorizes:` verdict is exit-2 reserved-family and never reaches that clause; the Undeferred gate's DETECT_RE keys on `operator <verb>` bullets, which the go-line render never produces |
| `.claude/hooks/ship-operator-step-gate.sh` | **no** | same phrasing-anchored detection as SKILL.md's gate |
| `technical-ruling-gate.sh` `CATEGORIES` | **no** | `(operator: <category>)` vocabulary unchanged — authorizes rows still carry `production-mutating`/`irreversible`/etc.; the class lives in the line form, not the category |
| `unkept-promise-hook.sh` | **no** | `PARKED_AUTH_RE` already licenses per-command prod-write pauses; "operator-reserved act" covers a go-wait |
| `plugins/soleur/skills/work/SKILL.md:1417`, `.github/workflows/scheduled-real-sdk-ask-probe.yml` | **no** | concept-level "operator-reserved act" prose, not the hold-token |
| ADR-284, ADR-298, ADR-319 | **no** | historical decision records citing `Operator-reserved:` semantics, which are unchanged |
| Test suites: `hold-gate-eval.test.sh`, `go-hold-routing.test.sh`, `cto-interface-selector.test.sh`, `technical-ruling-owner-list.test.sh`, `components.test.ts` | **yes** | new arms/properties/anchors per the Class R precedent (equality pins, negation checks, polarity anchors) |
| `plugins/soleur/scripts/delegation-verify.test.sh` | **no** | verifier unchanged |

**Decision point (review-visible).** standing-delegation.md §9 Records currently writes an
`Unverified:`-gated merge/deploy hold as `Operator-reserved:`. This plan changes it to
`Operator-authorizes:` because the hold names the agent-runnable ACT and the hard limits already
require the read to be re-run immediately before the act. Conservative alternative: keep
`Operator-reserved:` (strongest operator signal). Flagged for plan-review as a taste row.

**Normalization edge.** `reserved_hold()` compares the first 16 normalized alphanumeric chars.
`operatorauthorizes`[:16] = `operatorauthorize` — disjoint from `operatorreserved`; check order is
irrelevant. `Operator-authorizes:` mid-line does NOT classify (same rule as reserved: "words in the
middle of a hold do not reserve it").

**SpecFlow edge cases folded in (Phase 3, inline — no Task spawn in this context):** authorizes-only
plan with no delegation → exit 3 (prose path, like reserved-only); authorizes + WA-gated sibling →
NODELEG=1 and both lines print; `Operator-authorizes:` inside a fenced example is not a hold
(existing fence rule); a `Delegation:` + `Envelope:` + authorizes plan → delegation verified first,
authorizes still never probed for gates.

## Files to Edit

- `plugins/soleur/skills/ship/scripts/hold-gate-eval.sh` — `authorizes_hold()` recognizer, `AUTHORIZE` verdict print `Say go and I run it: ... - only you can say go`, `classify_no_delegation` skip, eval-loop arm, header comment's grammar paragraph.
- `plugins/soleur/skills/ship/references/operator-holds.md` — §1 format block + class paragraph (both prefixes, the executor split, the lifecycle), §2 exit-2 parenthetical, §3 interactive arm's "What this does not cover", §5 prints list.
- `plugins/soleur/commands/go.md` — Step 1.5: the set-aside bullet's two-class split, the classification-route bullet's class vocabulary, the standing-delegation bullet's conversion rule (second write target).
- `plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md` — §1 `production-mutating` bullet's never-delegable tail (two-class split + Undeferred-gate routing only for executes), §8.1c Needs-you render (authorizes lines read "say go and I run it" with the exact command shown in-session at run time; executes keep the closed founder-only list).
- `plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md` — §6 Scope drafting rule (enumerate the epic's full remaining grammar-compatible chain; acts whose target token does not yet exist are listed in words and the Scope is re-verified at each act boundary — a gap fails closed as `scope-mismatch`/`no-scope-item` into the authorizes path, never an errand), §9 carve-out paragraph + hard-limits paragraph naming the class, Records' unverified-gated hold token.
- `plugins/soleur/agents/engineering/cto.md` — Own-the-epic step 2 (Scope drafting), step 3 (two-token write rule), step 9 (executor split of the non-delegable tail; `Operator-authorizes:` items go to the in-session go path, not the Undeferred gate).
- `knowledge-base/engineering/architecture/decisions/ADR-289-standing-delegation-and-production-envelope.md` — amendment recording the fourth class and the denylist-bounds-standing-approval-only clarification.
- `plugins/soleur/test/hold-gate-eval.test.sh` — new arms mirroring 4c/4e for the prefix, the verdict line, classify_no_delegation skip, and the two-class fixture.
- `plugins/soleur/test/go-hold-routing.test.sh` — updated `classification-route`/`operator-reserved-format`/`reserved-conversion` properties + new authorizes-class properties.
- `plugins/soleur/test/cto-interface-selector.test.sh` — anchor updates where cto.md text moves (`epic-reserved-routing`, the Operator-reserved link check).
- `plugins/soleur/test/technical-ruling-owner-list.test.sh` — rows asserting the authorizes Needs-you line form.
- `plugins/soleur/test/components.test.ts` — PAIRS anchor refreshes + `PAIRS_FLOOR` bump if anchors move.

## Files to Create

- `plugins/soleur/test/operator-authorizes-probe.sh` — the discoverability probe (bash + grep only; asserts the recognizer token, the verdict line, the §8.1c render, and the §1 contract; prints `operator-authorizes: wired`, exit 0/1). Named `*-probe.sh`, NOT `*.test.sh`, so the `plugins/soleur/test/*.test.sh` runner glob (scripts/test-all.sh:97) does not pick it up as a suite.
- `plugins/soleur/test/fixtures/hold-gate-eval/plan-authorizes-web-acceptance.md` — synthesized fixture (cq-test-fixtures-synthesized-only): `## Operator Holds` with an `Operator-authorizes:` hold first and a `web-acceptance`-gated sibling (key absent from `apps/web-platform/server/legal-acceptance/texts/` → deterministic `Could not check`, no network) so `classify_no_delegation` takes the NODELEG=1 arm and the verdict line prints.

## User-Brand Impact

- **If this lands broken, the user experiences:** the Needs-you list keeps mislabeling agent-runnable
  production acts as console errands (the defect persists), or worse, an operator-hands act is
  rendered as "say go and I run it" that the agent then cannot fulfill after the go — a broken
  promise in the operator's plain-language close.
- **If this leaks, the user's workflow is exposed via:** repeated mis-presented authorization asks
  across epics — the observed five-item zero-hands list is exactly this shape; a wrong-direction
  mislabel is bounded by the typed-go + exact-command display at run time (hr-menu-option-ack) and
  the unchanged prod-write defer gate.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the change adds no new execution capability — the agent
  may already run these acts on a typed go today; what changes is the framing the operator sees,
  whose failure mode is a recurring presentation pattern, not a single breach.

## Observability

```yaml
liveness_signal:
  what: "the operator-authorizes classification wiring: the normalized recognizer token + AUTHORIZE verdict line in hold-gate-eval.sh, the 'say go and I run it' render in technical-ruling-delegation.md §8.1c, and the prefix contract in operator-holds.md §1 — all four sites must be wired for the class to reach the operator"
  cadence: "per hold-gate-eval.sh --plan run and per Needs-you render; asserted on every test-all run"
  alert_target: "the calling session's transcript (the printed verdict) and CI (the suite arms + probe)"
  configured_in: "plugins/soleur/skills/ship/scripts/hold-gate-eval.sh (recognizer + print); plugins/soleur/test/operator-authorizes-probe.sh (wiring probe)"
error_reporting:
  destination: "the evaluator's stdout verdict line and exit code; a misclassification surfaces as a wrong Needs-you line in the operator's closing message"
  fail_loud: "an Operator-authorizes hold that fails to classify prints the wrong verdict ('Reserved for you' or 'Needs a person') — never silently correct; the suite's jargon denylist bounds the print vocabulary"
failure_modes:
  - mode: "a runnable act is presented as an operator errand again (the defect this fixes regresses)"
    detection: "the authorizes-class test arms in hold-gate-eval.test.sh + go-hold-routing.test.sh assert the 'say go and I run it' line; the probe greps all four wiring sites"
    alert_route: "CI failure on the touched suites; probe exit 1"
  - mode: "an operator-hands act is offered as a go-line the agent cannot fulfill"
    detection: "the closed physical founder-only list is pinned in §8.1c and cto.md step 9; reserved-class arms assert executes items stay executes; at go time the operator sees the exact named command and can decline"
    alert_route: "CI failure on the classification arms; the operator's typed-go question itself"
  - mode: "prefix normalization drift — a spelling variant or a mid-line mention misclassifies"
    detection: "the 4e-mirror spelling battery (case, spacing, bold, quotes, full-width colon, invisible chars) plus the mid-line negative arm"
    alert_route: "CI failure on hold-gate-eval.test.sh"
logs:
  where: "evaluator stdout in the calling session's transcript; suite/probe output in the test-all or CI log; no persistent log by design"
  retention: "session transcript and CI-log retention only"
discoverability_test:
  command: bash plugins/soleur/test/operator-authorizes-probe.sh
  expected_output: "operator-authorizes: wired"
```

Layer citation (`hr-observability-layer-citation`): this is plugins-side machinery executed by the
calling agent — there is no server runtime, no Sentry path, and no customer self-hosted execution;
its observability layer is the evaluator's printed verdict plus the assertion suites that pin the
wiring, consumed in-session and in CI. `gh`, `python3` and `jq` are mise-shimmed on the authoring
host and absent from the Check-10 sandbox PATH (`/usr/local/bin:/usr/bin:/bin`), so the probe is
deliberately bash+grep only and checks the wiring sites rather than re-running the evaluator
(`need_tools` in hold-gate-eval.sh dies on missing `gh`/`jq` before any verdict prints — a probe
that ran the evaluator inside the sandbox would FAIL on a healthy system).

## Architecture Decision (ADR/C4)

This change adds a class to the hold-classification boundary — a cross-cutting invariant every
consumer (evaluator, go router, CTO agent, Needs-you lint) must honor — and extends ADR-289's
recorded mechanism. The ADR write is a deliverable of THIS plan.

### ADR

Amend `knowledge-base/engineering/architecture/decisions/ADR-289-standing-delegation-and-production-envelope.md`
(its `## Decision`/notes): record (a) the reserved class splits into `Operator-authorizes:` (typed
in-session go naming the exact command, agent executes — the per-command lane the hard limits and
`hr-menu-option-ack-not-prod-write-auth` already sanction) and `Operator-reserved:` (closed
physical founder-only list, operator executes); (b) the standing-delegation denylist bounds what a
standing approval may cover — it is not a bound on per-command authorization; (c) the
full-remaining-chain Scope drafting rule. No new ADR — this is an extension of the recorded
envelope, not a new decision (ADR-289's `related`/`Alternatives Considered` already carry the
three-class frame the amendment supersedes in place).

### C4 views

No C4 impact. Enumerated per the completeness mandate against all three model files
(`model.c4`, `views.c4`, `spec.c4`, all read this session): (a) external human actors — none new
(`founder` already exists, model.c4:73; the classification's operator IS the founder, no new actor);
(b) external systems/vendors — none new (the change touches no vendor edge; github/doppler/cloudflare/
betterstack are already modeled); (c) containers/data stores — none (hold-gate-eval.sh is repo-internal
plugin tooling, not a modeled container); (d) actor↔surface relationships — none change (no
`founder -> platform.*` edge is added, removed, or re-described). No `.c4` edit ships.

## Guard Contract

The deliverable extends an assertion-based test surface over a classification chokepoint — the
suites ARE the guard.

### Guard 1 — the `Operator-authorizes:` prefix is classified and rendered correctly

**Property.** A hold whose words begin `Operator-authorizes:` (however spelt) always stands, is
printed as the go-line (`Say go and I run it:`), is skipped by `classify_no_delegation` like a
reserved hold, and is never probed for gates — and `Operator-reserved:` behavior is byte-identical
to today.

**Assembly.** One chokepoint: `hold-gate-eval.sh` — the recognizer (`reserved_hold()`/new
`authorizes_hold()`), `print_result_line`'s verdict cases, the eval-loop reserved arm, and
`classify_no_delegation`'s skip. Every hold line in a plan or envelope flows through `parse_items`
→ the eval loop; there is no second recognition site (the sweep above confirms it).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `operatorauthorize` recognizer branch — the prefix falls through to an ordinary hold | RED — the authorizes fixture's verdict line + exit-2 assertions fail |
| 2 | Route the `AUTHORIZE` verdict to the `RESERVED` print ("only you can clear this") | RED — the line-form assertion fails (the exact wrong-errand defect) |
| 3 | Recognize the prefix mid-hold instead of only at line start | RED — the mid-line negative arm fails |
| 4 | Add a SECOND member: fixture holds `Operator-reserved:` then `Operator-authorizes:` — drop the second member's class handling | RED — the two-class fixture's per-hold verdict lines must differ |
| 5 | Mutate the harness: give the authorizes hold a `Gate:` line | RED — it still stands (prefix wins over gates, mirroring reserved) |
| 6 | Must-PASS, non-canonical: spelling variants `operator authorizes:`, `**Operator-authorizes:**`, full-width colon, leading invisible chars | PASS — recognized like reserved spellings |

**Anchor.** The verdict-line literal (`say go and I run it`) lives in one committed spec
(operator-holds.md §1) asserted by the suite; weakening both requires one reviewed diff touching
doc + code + test — the merge-base diff is the outside-anchor.

### Guard 2 — classification routes authorization-phrase items to the authorizes class

**Property.** In go.md Step 1.5's set-aside and classification route, an item beginning
`Operator-authorizes:` or containing `ask me before`, `explicit go-ahead` or `operator approval`
is classified operator-authorizes and rendered "say go and I run it" — never as an
operator-executes errand; `Operator-reserved:` items keep the executes class.

**Assembly.** Chokepoints: go.md's set-aside bullet + classification-route bullet + the
standing-delegation conversion sentence (the only site that writes `Operator-reserved:` into a
plan); the §8.1c render contract; `go-hold-routing.test.sh`'s `ALL_PROPS` pin set.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `Operator-authorizes:` from the set-aside — the item reaches the CTO spawn unclassified | RED |
| 2 | Route phrase-list items to the executes class (the regression shape) | RED |
| 3 | Drop the "say go and I run it" render requirement from the route output | RED — a render check that stops at classification proves nothing about the errand shape |
| 4 | Second member after a compliant first: an `Operator-reserved:` item followed by an `ask me before` item in one list | RED if both collapse into one class |
| 5 | Harness row: fixture list where every item is authorizes-class — drop the "0 checked" floor | RED — the property count in ALL_PROPS must not silently shrink |

**Anchor.** go.md's bullet text is the spec; `ALL_PROPS` equality pins its property set — a single
commit weakening both doc and suite is the merge-base-reviewable unit.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** (inline — this run has no subagent spawn; single-domain sweep, assessment-question
match: "significant architectural decisions... beyond normal implementation" — yes, an
authorization-classification boundary move.) The change extends an existing trust boundary rather
than creating a new one; the authority mechanisms (typed go, delegation grammar, denylist, Excluded
sentence) are all pre-existing and unchanged. Residual: the classification is prose machinery — no
hook enforces that a session actually applies the split; correctness rests on the pinned wording +
the evaluator's verdict line (stated plainly per the Class R learning).

### Product/UX Gate

Not applicable — the mechanical UI-surface override cannot fire: no `Files to Create`/`Files to
Edit` entry matches the ui-surface-terms glob superset (`components/**/*.{tsx,jsx,vue,svelte}`,
`app/**/{page,layout,template}.tsx`, `pages/**`, `routes/**`, `*.{njk,html,vue,svelte,astro}`);
every planned file is `.md`, `.sh`, or `.ts` test/ADR content. Tier: NONE —
`wg-ui-feature-requires-pen-wireframe` does not apply because no UI surface is created or modified.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies searched for every planned file
path (2026-11-09): zero hits.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Split the reserved class in the classification machinery: operator-authorizes (the Needs-you line reads \"say go and I run it\"; the exact command is shown in-session at run time per hr-menu-option-ack-not-prod-write-auth) vs operator-executes (console-only, credential entry, payment — the closed physical list)" | Files-to-Edit entries for `hold-gate-eval.sh`, `operator-holds.md`, `go.md`, `technical-ruling-delegation.md`, `cto.md` + FR/test arms | mapped |
| 2 | "Draft the standing-approval Scope from the epic's full remaining act chain, not the next few acts (standing-delegation.md §6 flow / CTO step 2 Scope proposal)" | Files-to-Edit entries for `standing-delegation.md` §6 + `cto.md` step 2 | mapped |
| 3 | "Non-goal for phase 1: widening the four-command delegation grammar or the verifier-pinned Excluded sentence (excluded-incomplete) — a separate, safety-reviewed change" | AC7 (byte-identical non-goal guard) + deferral issue #12479 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `Operator-authorizes:` prefix + evaluator verdict | "operator-authorizes (the Needs-you line reads \"say go and I run it\"" | asked |
| Executor split of cto.md step 9 / §1 tail | "the classification machinery ... collapses every non-grammar, non-Class-R act into Operator-reserved and frames it as an operator errand" | asked |
| Scope drafting rule | "delegation Scope is drafted act-by-act ... landed in Needs-you for no mechanical reason" | asked |
| ADR-289 amendment | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable` — the class is a cross-cutting invariant extending ADR-289's recorded mechanism; the record must not lag the change |
| Probe script + fixture | — | inferred — justification: Phase 2.9 Observability requires a no-SSH discoverability command; `gh`/`jq` are mise-shimmed and absent from the Check-10 sandbox, so a committed bash+grep probe is the only honest shape |
| Test-arm edits across the four suites + components.test.ts | — | inferred — justification: equality pins and anchors rot without updates when the spec text moves (the Class R pin-test precedent) |
| `Operator-authorizes:` for unverified-gated merge/deploy holds (§9 Records) | — | inferred — justification: the hold names an agent-runnable act; the §9 hard limits already require re-running the read before the act. Flagged as a plan-review taste row |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur`, `knowledge-base`
- Planned files: 14 | Estimated changed lines: ~700
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] `bash plugins/soleur/skills/ship/scripts/hold-gate-eval.sh --plan plugins/soleur/test/fixtures/hold-gate-eval/plan-authorizes-web-acceptance.md` prints `Say go and I run it:` for the authorizes hold and exits 2; the hold's gates are never probed.
- [ ] The `Operator-authorizes:` prefix is recognized however spelt — case, spaces, hyphens, underscores, bold, quotes, full-width colon and invisible leading chars (mirroring arm 4e) — and only at the start of a hold's words (a mid-line mention does not classify).
- [ ] `Operator-reserved:` behavior is unchanged: `Reserved for you: ... - only you can clear this` still prints, exit 2, gates unprobed; every pre-existing reserved arm in `hold-gate-eval.test.sh` is unmodified and green.
- [ ] `go.md` Step 1.5: `Operator-authorizes:` items and items containing `ask me before`, `explicit go-ahead` or `operator approval` classify as operator-authorizes (rendered "say go and I run it"); `Operator-reserved:` items classify as operator-executes — both pinned in `go-hold-routing.test.sh`.
- [ ] `cto.md` Own-the-epic: step 2's Scope proposal is drafted from the epic's full remaining grammar-compatible chain; step 9's non-delegable tail splits by executor (agent-reachable-after-go → `Operator-authorizes:` → the in-session go path; founder-physical → `Operator-reserved:` → the Undeferred Operator-Step Gate).
- [ ] `technical-ruling-delegation.md` §8.1c: authorizes Needs-you items read "say go and I run it" and the exact command is shown in-session at run time per `hr-menu-option-ack-not-prod-write-auth`; executes items keep the closed founder-only list — pinned in `technical-ruling-owner-list.test.sh`.
- [ ] `standing-delegation.md` §6 carries the full-remaining-chain Scope drafting rule; §9's carve-out paragraph names `Operator-authorizes:` (Class R never applies to it).
- [ ] Non-goal guard: `git diff origin/main -- plugins/soleur/scripts/delegation-verify.sh` is empty AND the §5 Excluded sentence is byte-identical (`excluded-incomplete` unweakened).
- [ ] `ADR-289` carries the amendment recording the fourth class + the denylist-bounds-standing-approval-only clarification + the Scope drafting rule.
- [ ] `bash plugins/soleur/test/operator-authorizes-probe.sh` prints `operator-authorizes: wired` and exits 0.
- [ ] Suites green: `bash plugins/soleur/test/hold-gate-eval.test.sh`, `bash plugins/soleur/test/go-hold-routing.test.sh`, `bash plugins/soleur/test/cto-interface-selector.test.sh`, `bash plugins/soleur/test/technical-ruling-owner-list.test.sh`, `bun test plugins/soleur/test/components.test.ts`, `bash plugins/soleur/scripts/delegation-verify.test.sh`, `bash scripts/test-all.sh` (or the affected-tests selection it computes).

## Test Scenarios

- Given a plan with `- Hold: Operator-authorizes: <act>` and no other holds/gates, when the evaluator runs, then it exits 3 (prose path, reserved-family — same as reserved-only) or, beside a `web-acceptance`-gated sibling, prints `Say go and I run it:` and exits 2. [unit]
- Given `- Hold: Operator-reserved: <act>` and `- Hold: Operator-authorizes: <act>` in one file, when evaluated, then two distinct verdict lines print in hold order. [unit]
- Given `ask me before revoking the token` as a classification item, when go.md Step 1.5's set-aside runs, then it lands in the authorizes class, not the executes class. [unit]
- Given an authorizes hold carrying a `Gate:` line, when evaluated, then it still stands (the prefix wins over gates — fail-safe direction). [unit]
- Given `Operator-authorizes:` written with a full-width colon / bold marks / leading NBSP, when evaluated, then it classifies identically to the canonical spelling. [unit]
- Given a delegation Scope drafted for an epic with N remaining grammar-compatible acts, when the CTO applies step 2, then the Scope lists all N (each naming its target token), and an act outside the recorded Scope fails closed `scope-mismatch`/`no-scope-item` — surfaced as a go-line, not an errand. [unit]

## Success Metrics

- A classification pass over the #12380-recorded five-item list (the issue's diagnosis table)
  produces zero operator-executes items: two Doppler writes, the CF token revocation and the
  heartbeat unpause classify `Operator-authorizes:`; the canary dispatch and PR-B merge classify
  delegated-under-scope (grammar-compatible).
- Post-change Needs-you lists for epics show the `say go and I run it` line form wherever an act is
  agent-runnable.

## Dependencies & Risks

- **Risk: prose machinery, not enforced by a hook.** The split is honored by the skills/agents that
  read these files; nothing mechanical forces a session to classify honestly. Mitigation: the
  evaluator's verdict line + suite pins are the observable surface; the residual is stated plainly
  (Class R precedent's own accepted residual).
- **Risk: components.test.ts anchor drift.** The PAIRS anchor table pins sentences in the edited
  files (e.g. `or contains 'ask me before', 'explicit go-ahead' or 'operator approval'`); edits must
  keep pinned sentences or update anchors + `PAIRS_FLOOR` in the same commit.
- **Risk: verdict-line vocabulary feeds a trigger.** `Say go and I run it:` is deliberately free of
  `OWNER_HEAD_RE`/`PARKED_*` trigger words — a variant must be re-checked against both regexes if
  the wording changes at work time.
- **Deferral:** grammar/denylist/Excluded-sentence widening → #12479 (filed; `Post-MVP / Later`).
  Related open issue: #11084 (epic-reference scope-class — adjacent, not a duplicate).

## References & Research

- Issue: #12443 (diagnosis + live-verified reachability table); epic #10390; session record #12380.
- Authority: `hr-menu-option-ack-not-prod-write-auth` (AGENTS.rules.md:46); ADR-289, ADR-249, ADR-264, ADR-302, ADR-309.
- Machinery: `plugins/soleur/skills/ship/scripts/hold-gate-eval.sh` (`reserved_hold()` :411, `RESERVED` print :405, `classify_no_delegation` :443, eval loop :572); `commands/go.md` Step 1.5 :538-550 and §649; `agents/engineering/cto.md` Own-the-epic steps 2/3/9; `technical-ruling-delegation.md` §1/§8.1c; `standing-delegation.md` §6/§9.
- Learnings: the Class R closed-class precedent (2026-11-03, two files) — heading-as-match-target,
  equality pins, three-files-one-boundary; the parked-label learning (PARKED_AUTH_RE already covers
  the go-wait).
