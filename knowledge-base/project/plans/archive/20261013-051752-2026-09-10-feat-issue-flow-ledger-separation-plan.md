---
title: "feat: separate the machinery ledger and move the issue-filing lever to filing time"
date: 2026-09-10
slug: feat-issue-flow-ledger-separation
branch: feat-one-shot-issue-flow-ledger-separation
issue: none
lane: cross-domain
type: feature
closes: none
priority: p1-high
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

## Overview

Soleur's open-issue count rises at roughly two filed per one closed, every week
without exception. Measured 2026-09-10: 1,456 open at the write-up, 1,455 on the
live recount during planning; 1,134 opened against 563 closed over the last
eight weeks (net +571); 841 older than 60 days; 330 never commented on.

The backlog is not tech debt. It is **audit exhaust** — the byproduct of running
adversarial review agents over Soleur's own verification machinery. A 1,000-issue
sample carries 626 `domain/engineering` against 39 `domain/product`. The
representative open titles are findings about guards ("guard checks assertion
SHAPE, not that a rehearsal passed"), not about anything a Soleur user receives.

This matters beyond housekeeping because **this machinery ships to customers**
(`hr-weigh-every-decision-against-target-user-impact`). A non-technical founder
running Soleur on their own repo will have work generated faster than they can
absorb it, and will read that as the tool being broken.

Four coupled levers, delivered in one PR because levers 2–4 all key off the
label from lever 1:

1. **Separate the ledgers** — a `meta/machinery` label plus exclusions, so the
   ~39 product issues become visible and the other three levers become measurable.
2. **Move the lever to filing time (PRIMARY)** — a *blocking* PreToolUse gate on
   `gh issue create`, reconciled into the one existing defer rule rather than
   added beside it.
3. **Expire by default** — extend the existing 90-day quiet-period sweeper to the
   machinery ledger. Stock cleanup only.
4. **Make the gate net-negative on a cadence** — a weekly drain with a closing
   floor, plus a weekly measurement that makes the gate's 98 overrides and its
   fail-open path visible instead of indistinguishable from a pass.

**The operator's pushback reshapes the priority order and is binding.** Expiry
drains the *stock*; only the filing-time gate touches the *rate*. At ~2:1 a
90-day sweep buys a one-time drop and then the curve resumes its old slope.
Lever 2 is therefore the primary deliverable, it must be blocking rather than
advisory, and the success criterion for this PR is that **the filing rate falls**
— with expiry-driven closes excluded from that measurement so they cannot mask a
flat or rising filing rate.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "the skill needs an API-budget `<decision_gate>` carrying the sentinel `disclaims warranty for runtime cost`" | **Already satisfied.** `drain-labeled-backlog` is registered in `AUTONOMOUS_LOOP_SKILLS` in `plugins/soleur/test/components.test.ts`, and its `SKILL.md` already carries a `<decision_gate>` with the sentinel. | Reuse `/drain`. Do **not** author a new skill. Cut from scope; see Cut List C2. |
| L3 needs a new "scheduled sweeper" | **Already exists.** `apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts` is a 90-day quiet-period auto-closer with a kill-switch label, an explanatory comment carrying a stable idempotency sentinel, dry-run, Sentry heartbeat, and replay safety. | Generalize its `TARGET_LABEL` to a set. Do **not** build a second sweeper. Cut List C1. |
| D3 says the drain "is a scheduled workflow (see `.github/workflows/scheduled-*.yml` for house pattern)" | **A new `scheduled-*.yml` carrying `schedule:`/`cron:` is DENIED** by `.claude/hooks/new-scheduled-cron-prefer-inngest.sh` per ADR-033 (Inngest is the single scheduling substrate). Both arms verified: a `workflow_dispatch:`-only file never matches the hook's content grep and hits `allow` early. | Use the established Inngest-cron → GHA-dispatch → `workflow_dispatch:{}`-only workflow pattern. **There is no shared helper named `createWorkflowDispatch`** — each cron issues a raw `octokit.request("POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches", …)`. **9** genuine precedents under `apps/web-platform/server/inngest/functions/`: `cron-inngest-config-drift`, `cron-terraform-drift`, `cron-main-health-monitor`, `cron-review-reminder`, `cron-dev-migration-drift`, `cron-supabase-advisor-scan`, `cron-sentry-alert-drift`, `cron-expenses-verify-by`, `cron-domain-model-drift`. (`cron-roadmap-review` mentions `workflow_dispatch` in a comment only and is **not** a precedent.) Do **not** reach for the hook's override hatch. |
| "the label must be excluded from `/drain`'s default scope" | `/drain`'s default is already `deferred-scope-out`, so `meta/machinery` is outside it by construction. The real exposure is the `--label` passthrough and the weekly cadence's default. | Make the exclusion explicit in the query rather than relying on the default, so a future default change cannot silently pull machinery into a user-facing drain. |
| "AGENTS rule additions/edits as needed" | **Both always-loaded budgets are at cap.** `python3 scripts/lint-agents-rule-budget.py` reports `B_ALWAYS=45999` against a 46000 REJECT. Cumulative skill descriptions measure **2400/2400**. | No new rule id, no new skill. Extend `wg-defer-only-after-inline-triage` in place and make the edit byte-**negative** by moving prose into the hook per `cq-agents-md-tier-gate`. |
| The brief's `DRIFT_SUSTAINED_THRESHOLD_MIN` correction | `resolve-target` does not exist on this branch's base; the coordinator verified `git grep -c resolve-target origin/main -- .github/workflows/web-platform-release.yml` returns 0. | Out of scope. Recorded in Non-Goals, documented in place, **not** filed. |
| "open issues 1,459 at session start" | Live recount during planning: **1,455** (`gh api search/issues ... .total_count`). | Record 1,455 as the planning-time baseline alongside the 1,456 write-up figure. The discrepancy is churn within the measurement window, not a contradiction; both are recorded so the 4-week re-check has an honest band. |

## Research Insights

### Premise Validation (Phase 0.6)

The brief cites no open GitHub issue as a blocker — deliberately, since filing one
would be the defect demonstrating itself. Cited artifacts were verified as follows.

- **Source write-up** — read first, in full, via
  `git show feat-one-shot-7931-5806-ci-concurrency-and-workflow-run-deploy:knowledge-base/project/specs/.../resume-prompt-issue-flow.md`.
  Holds. All measured figures reproduce.
- **`plugins/soleur/skills/ship/scripts/net-issue-flow.sh`** — exists, 665 lines.
  `NET = FILED - EXEMPT - CLOSING`; blocks at `NET > 0`. `FILED` has two arms
  (an issue created after the PR that bare-references it, and a `Filed: #N` line
  in the PR body). **No label filter exists anywhere in the script** — an earlier
  design considered scoping to `deferred-scope-out` and rejected it at ~8%
  coverage. Fail-open emits `warn` with a `net-issue-flow fail-open:` prefix;
  a pass emits `applied` with `net-issue-flow pass net=…`. Three escapes:
  the `SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1` env var, the
  `<!-- gate-override: net-issue-flow -->` PR-body marker, and the ADR-155
  `Mandated-By:` exemption.
- **ADR-155** — read in full, per the standing DO-NOT. `[mandates-filing]` is
  derived from the corpus at `git merge-base origin/main HEAD`, is restricted to
  `^(hr|wg)-`, and sits in `SECURITY_TAG_MARKERS` so both adding **and dropping**
  it are loud. The tagged set is **one rule**: `wg-block-pr-ready-on-undeferred-operator-steps`.
  It is the first marker granting a rule authority over a *different* gate, so a
  marker edit is not a local edit. **This plan does not add, weaken, or drop any
  `[mandates-filing]` marker.**
- **`wg-defer-only-after-inline-triage`** — exists, carries a triple test
  (inline-first / concrete trigger / plausible-in-6mo), 529 bytes, no
  enforcement tag. It is the rule to extend.
- **Label set** — `gh label list --limit 300` verified. House style is
  slash-namespaced (`domain/*`, `type/*`, `priority/*`, `ci/*`, `vendor/*`,
  `bot-fix/*`, `security/*`, `compliance/*`, `self-healing/*`). **There is no
  existing `meta/*` namespace**, and no `machinery` label. `meta/machinery`
  matches house style and does not collide.
- **`do-not-autoclose` and `keep-open` already exist** as labels. Any expiry work
  must honor both; the existing sweeper honors only the first.
- **ADR ordinal** — enumerated across all 86 `refs/remotes/origin` refs. Highest
  claimed is **ADR-215**, so **ADR-216 is next-free and provisional** until
  `/ship` re-verifies at merge.

### Property List (Phase 0.6b)

What the ask is actually for, stated as observable outcomes:

- **P1** — A reader of the open-issue list can tell, without opening an issue,
  whether it concerns something a Soleur user receives.
- **P2** — An agent cannot file a user-facing issue without naming a user-visible
  consequence, and cannot narrate past that requirement.
- **P3** — A deferral decision is tested against a *measured* fix size and against
  whether the "we lack the numbers" blocker is derivable, before it becomes a filing.
- **P4** — Machinery findings leave the open set without human attention after a
  quiet period, and never take a human-triaged or product issue with them.
- **P5** — The backlog shrinks over time rather than being held constant.
- **P6** — A silently-failing-open or overridden net-issue-flow gate is
  distinguishable from a passing one in the periodic measurement.
- **P7** — The filing *rate* is measurable independent of expiry-driven closes.

### Cut List (Phase 0.6b)

Mechanisms the brief proposed that an existing mechanism already buys, removed
here rather than researched, designed, or reviewed:

| Cut | Property it bought | What already covers it |
|---|---|---|
| **C1** — a new 90-day expiry sweeper (workflow + script + test + Sentry monitor + dry-run) | P4 | `apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts` — 90-day cutoff, kill-switch label, explanatory comment with a stable idempotency sentinel, GET-before-POST comment guard, `state_reason: "not_planned"` close, dry-run via event payload, Sentry heartbeat, replay-safe. Generalizing `TARGET_LABEL` buys P4 outright. |
| **C2** — a new drain skill carrying its own API-budget `<decision_gate>` | P5 | `drain-labeled-backlog` is already in `AUTONOMOUS_LOOP_SKILLS` and already carries the `disclaims warranty for runtime cost` sentinel. A new skill would also need description-budget headroom that does not exist (2400/2400). |
| **C3** — a new AGENTS rule for the filing-time gate | P2, P3 | `wg-defer-only-after-inline-triage` already states the discipline. A second rule would (a) disagree with the first — the exact failure the operator named — and (b) cannot land against `B_ALWAYS=45999/46000`. |
| **C4** — a bespoke telemetry marker so expiry closes are separable | P7 | The existing sweeper already closes with `state_reason: "not_planned"`, which is a first-class, GitHub-queryable field (`gh issue list --json stateReason`). Local `.claude/.rule-incidents.jsonl` telemetry is the *wrong* substrate here anyway — it is hook-local and a scheduled run cannot contribute to it. |
| **C5** — a new `scheduled-*.yml` with a `cron:` block for the weekly drain | P5 | ADR-033 + `new-scheduled-cron-prefer-inngest.sh` make Inngest the single scheduling substrate; the Inngest-cron → `workflow_dispatch` pattern has 10 precedents. |

**What survives the cut and is genuinely new: the filing-time gate (P2, P3) and
the weekly measurement (P6, P7).** Everything else is a parameterization of
something already running.

### Relevant institutional learnings

- `knowledge-base/project/learnings/workflow-patterns/2026-05-29-net-issue-flow-gate-at-filing-site-not-just-ship.md`
  — **the decisive precedent.** A gate that fires only at the merge boundary is
  bypassed by work done before the boundary. `/ship` Phase 5.5's surfacing was
  bypassed precisely because filings happen in `/work` Phase 4. When a discipline
  must hold for an *action*, enforce it at the moment the action is taken. This
  independently confirms the operator's pushback.
- `knowledge-base/project/learnings/2026-07-20-an-advisory-gate-is-not-a-weak-gate-it-is-no-gate-and-a-ratio-needs-its-denominator-checked.md`
  — an advisory gate in an autonomous pipeline is inert; nothing consumes it. The
  net-issue-flow surface computed correctly for three months as advisory and was
  skipped, including on PRs that filed 3 and closed 0. Binds AC-wise: the filing
  gate must `deny`, not warn.
- `knowledge-base/project/learnings/2026-09-08-every-guard-i-added-to-the-gate-could-not-fail.md`
  — four guards in one gate could not fail. Binds the Guard Contract below:
  every arm needs a mutation that drives it red.
- `knowledge-base/project/learnings/2026-08-10-six-times-a-check-certified-something-other-than-what-it-named.md`
  — checks that certify an adjacent property. Binds: "has a named consequence"
  must assert the consequence is *in this issue's body*, not inferred.
- `knowledge-base/project/learnings/2026-08-20-the-check-failed-because-the-thing-it-checked-for-was-there.md`
  — `cmd | grep -q` under `set -euo pipefail` fails *precisely when the needle is
  present* (SIGPIPE → 141 → pipefail). Binds every shell predicate added here.
- `knowledge-base/project/learnings/integration-issues/2026-06-02-followthrough-gh-probe-needs-secrets-gh-token-env-i-strips-it.md`
  — a script that passes locally via `~/.config/gh` fails silently-forever in a
  sandbox that strips `GH_TOKEN`. Binds the measurement script's auth.
- `knowledge-base/project/learnings/2026-04-02-ship-review-evidence-coupling.md`
  — when review findings moved from `todos/` to labelled issues, downstream
  consumers still read the old signal. Binds L1: introducing `meta/machinery` as
  a source of truth requires sweeping every consumer in the same PR.

### CLAUDE.md / AGENTS conventions in force

`hr-weigh-every-decision-against-target-user-impact` (cited in the Overview),
`hr-technical-fork-is-not-an-operator-question` (D1 and the Non-Goal below were
resolved as technical forks, not asked), `hr-verify-repo-capability-claim-before-assert`
(every "already exists" claim above is grep-backed), `cq-rule-ids-are-immutable`,
`cq-agents-md-why-single-line`, `cq-agents-md-tier-gate`, `cq-cite-content-anchor-not-line-number`,
`cq-assert-anchor-not-bare-token`, `wg-defer-only-after-inline-triage`,
`wg-when-deferring-a-capability-create-a`, and the index/body split in `AGENTS.md`
(bodies stay in `AGENTS.rules.md`).

### Budget headroom (Phase 1.8)

- **AGENTS always-loaded:** `B_ALWAYS=45999` (AGENTS.md 5489 + AGENTS.rules.md 40510)
  against `B_ALWAYS_REJECT=46000`, `PER_RULE_CAP=600`. Authority:
  `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1`.
  Effective headroom is **one byte**. The `wg-defer-only-after-inline-triage`
  body is 529 bytes.
- **Skill descriptions:** cumulative **2400** against `SKILL_DESCRIPTION_WORD_BUDGET = 2400`
  across 95 skills. Headroom **zero**. No skill description may grow, and no
  skill may be added, without an equal sibling trim.

Both figures are load-bearing constraints on the design, not footnotes — they are
why C2 and C3 are cuts rather than deliverables.

## User-Brand Impact

**If this lands broken, the user experiences:** a `gh issue create` that is
refused with an unexplained block, in the middle of an autonomous `/work` or
`/review` run, on their own repo — the pipeline stalls and the founder sees
Soleur unable to complete its own workflow. The second, quieter failure is the
expiry sweeper closing an issue the founder *did* care about, so a real problem
silently leaves their backlog.

**If this leaks, the user's data/workflow is exposed via:** no new data surface
is created. The gate reads only the command string already visible to the hook;
the sweeper and the measurement read only issue metadata already visible to any
repo collaborator. No new secret, store, or network egress is introduced.

- **Brand-survival threshold:** `aggregate pattern`

The blast radius is a workflow-quality regression that compounds across many runs
rather than a single-user incident: no credential, payment, personal data, or
irreversible production write is involved, and both the gate and the sweeper have
explicit, documented escapes. Consequently `requires_cpo_signoff: false` and
`user-impact-reviewer` is not mandatory at review — but the mass-close risk in
lever 3 is treated as the highest-severity item in Risks below, and the
never-close guards are contract-tested rather than assumed.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200` (65 open) and
matched each planned path against the issue bodies with a standalone
`jq --arg path`. **None.** No open `code-review` issue names
`.claude/hooks/guardrails.sh`, `plugins/soleur/skills/ship/scripts/net-issue-flow.sh`,
`plugins/soleur/skills/drain-labeled-backlog`, `plugins/soleur/skills/operator-digest`,
`AGENTS.rules.md`, or `ticket-triage`.

## Architecture Decision (ADR/C4)

### ADR

**Create ADR-216 — "Machinery findings are a separate ledger, and the filing
lever moves to filing time."** Provisional ordinal: highest claimed across all 86
`origin/*` refs is ADR-215. `/ship` re-verifies before merge; if it moves, sweep
`grep -rn 'ADR-216' knowledge-base/project/{plans,specs}/` in the same edit so the
plan, tasks, and any AC naming the ordinal move with it.

The ADR must record:

- **Decision** — machinery findings are separated by a **label**, not a separate
  repo and not a knowledge-base rolling log; and the decisive check on filing
  moves from the merge boundary to the filing site.
- **Rejected: a separate repo.** It breaks the `Closes #N` link from the closing
  PR, and it breaks `net-issue-flow.sh`'s own counting — the script's `FILED` arm
  matches issues in *this* repo that reference the PR, so cross-repo filings would
  become invisible to the gate rather than merely re-scoped.
- **Rejected: a knowledge-base rolling audit log.** It loses close-on-merge
  entirely, needs new tooling to write and query, and has no state model, so an
  entry can never be "resolved" — only appended to.
- **Chosen: a label.** One taxonomy addition, reversible by deleting the label,
  and it immediately makes the ~39 product issues visible without moving anything.
- **Why the filing-site gate rather than a stricter merge-boundary gate** — cite
  the 2026-05-29 learning: per-PR net-zero, perfectly enforced, holds the backlog
  at its current size forever. Only a filing-time check moves the rate.
- **Reconciliation with ADR-155** — the filing gate's third exit is
  `Mandated-By: <rule-id>`, the same closed, human-gated vocabulary ADR-155
  established. This is what makes the mandating gate and the restricting gate one
  gate rather than two that disagree. Record explicitly that no `[mandates-filing]`
  marker is added, weakened, or dropped by this PR.
- **Amends ADR-033's surface, does not contradict it** — the weekly drain is
  scheduled by Inngest and merely *dispatched* to GitHub Actions, because the
  work is an agent pipeline that cannot run inside the Inngest runtime.

### C4 views

Read all three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`
in full — not a keyword grep — and enumerate for this change:

- **external human actors** — none added. The founder/operator actor already
  exists; this change alters what reaches them (the digest excludes machinery),
  which is an edge-description question, not a new actor.
- **external systems** — none added. GitHub Issues, Inngest, and Sentry are all
  already modeled.
- **containers / data stores** — none added.
- **access relationships** — verify whether the operator-digest edge's description
  claims to surface the full `action-required` set; if so, it is falsified by the
  new exclusion and must be corrected.

A "no C4 impact" conclusion is only acceptable if it cites this enumeration
against all three files. **Additionally**, because `model.c4` embeds derived
cardinalities that `c4-count-parity` gates as required context, a no-impact
conclusion must be backed by a green
`plugins/soleur/test/c4-count-parity.test.sh` run — the sweeper generalization
touches no monitor count, but the run is the evidence, not the reasoning. If any
`.c4` edit lands, run `apps/web-platform/test/c4-code-syntax.test.ts` and
`c4-render.test.ts`, which are where an undefined-element `view include` fails.

### Sequencing

No slice defers the decision's truth. The ADR is authored in this PR with
`Status: Accepted`; the soak-gated part (does the rate actually fall?) is a
*measurement* recorded in the plan's success criterion, not a status flip, so no
`adopting → accepted` transition and therefore no follow-through enrollment is
required here.

## Implementation Phases

Phase order is dependency-directed, not file-grouped: the label must exist before
anything keys off it, and the contract-changing edits precede their consumers.

### Phase 0 — Preconditions (verify, do not assume)

0.1 Re-run the two budget authorities and record the numbers in `tasks.md`:
`python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1`
(the `2>&1` is load-bearing — WARN and REJECT print to stderr) and the cumulative
skill-description count. Both are at cap; every later phase must keep them there
or below.

0.2 Re-verify `meta/machinery` is free: `gh label list --limit 300 | grep -c '^meta/'`
must be 0.

0.3 Re-derive the next-free ADR ordinal across **all** `origin/*` refs, not
`origin/main` alone.

0.4 Record the planning-time baseline: `gh api "search/issues?q=repo:jikig-ai/soleur+is:issue+is:open" --jq '.total_count'`.

0.5 Confirm `.claude/hooks/guardrails.test.sh` runs green on the untouched tree,
so a later red is attributable to this change.

### Phase 1 — L1: create the label and sweep every consumer

1.1 **Create the label.** `gh label create 'meta/machinery' --description '<one line>' --color <hex>`.
Match the description style of the existing `domain/*` labels.

1.2 **Sweep the consumers in the same PR** (the 2026-04-02 coupling learning —
introducing a source of truth without migrating its consumers is how the previous
migration broke):

- `plugins/soleur/skills/operator-digest/SKILL.md` — add `meta/machinery` to the
  §4 `action-required` de-pollution EXCLUDE list, beside the existing
  `decision-challenge` and `content-publisher` entries. This is an exact
  in-file precedent; follow its prose shape.
- `plugins/soleur/agents/support/ticket-triage.md` — exclude `meta/machinery`
  from domain routing. A machinery finding has no user-facing domain to route to;
  routing it to `domain/engineering` is what produced the 626:39 skew.
- `plugins/soleur/skills/drain-labeled-backlog/SKILL.md` — make the exclusion
  **explicit in the query** rather than implicit in the default. Today the default
  is `deferred-scope-out`, so machinery is out of scope only by accident of the
  default; a future default change would silently pull it into a user-facing drain.
- **Do NOT exclude `meta/machinery` from `net-issue-flow.sh`.** This is a
  deliberate, load-bearing non-change: the gate must keep counting machinery
  filings, or the machinery ledger grows unbounded with no rate gate at all. The
  label separates *visibility*, not *accountability*. Record this in the ADR.

1.3 **Backfill by evidence rule, never by bulk relabel.** The rule: the issue's
title or body names a guard, gate, ledger, probe, assertion, sweep, or rehearsal
**AND** names no user-visible surface (no route, page, component, CLI command,
email, or user-facing document). Implement as a script that emits a
**proposal file** — issue number, title, matched evidence token, matched
negative-evidence token — and label only from the reviewed proposal. Cap the
first pass and require the proposal to be committed as an artifact so the
classification is auditable. **The backfill classifies; it never closes.**

### Phase 2 — L2 (PRIMARY): the blocking filing-time gate

This is the deliverable the operator's pushback promotes to first rank. It must
`deny`, not warn.

2.1 **Write the mutation matrix before the guard** (Guard Contract below). A
matrix derived from finished code tests the code; a matrix derived from the design
tests the property.

2.2 **Add the check INSIDE the existing `guardrails:require-milestone` block —
do not add a parallel block.** That block already opens on
`grep -qE '(^|&&|\|\||;)\s*gh\s+issue\s+create' <<<"$SCAN"` and already computes
`_our_repo` / `_ext_repo` with a quote-aware `xargs -n1` tokenizer. Duplicating
25 lines of tokenizer is copying, not reuse, and it would create a second pin on
the same fact. Add the new condition **after** `_our_repo`/`_ext_repo` are
computed, so the new gate inherits, for free and without a second implementation:

- the `$SCAN` (quote/heredoc-stripped) match, so a commit message *documenting*
  `gh issue create` is not mistaken for one — the #5192 false-positive class;
- the external-repo exemption (a filing against a non-`jikig-ai/*` repo);
- fail-**toward-gating** on tokenizer error;
- the chained-command detection.

**Consequence that must be declared, not discovered:** the existing fixtures in
`.claude/hooks/guardrails.test.sh` that assert `--milestone` alone is sufficient
to ALLOW a `gh issue create` will no longer hold — after this change `--milestone`
is necessary but not sufficient. Migrating those fixtures is an explicit
deliverable of this phase, named in `## Files to Edit`, not a surprise at GREEN.

**Telemetry id — do not invent a new one.** `scripts/rule-metrics-aggregate.sh`
runs an **orphan gate that exits 5** when the incidents log carries a `rule_id`
that is neither an active AGENTS.md id nor on its reserved-prefix exemption list
(`te-`, `gdpr-gate-`, `context-reviewed-`, `net-issue-flow`, `cost-of-filing-`,
`grep-rewrite-`, `hook-input-`). Emit under the **real rule id**
`wg-defer-only-after-inline-triage`, which is an active AGENTS.md id and is
therefore never an orphan. This is also semantically right — the hook enforces
that rule — and it makes the rule's own `fire_count` accrue, which is the usage
evidence the retirement rung otherwise lacks. Verify with a dry-run
`bash scripts/rule-metrics-aggregate.sh` before merge.

2.3 **Three exits, one gate.** The filing is allowed when **any** holds:

1. `--label meta/machinery` is present → the finding goes to the machinery
   ledger, where a user-visible consequence is not required by construction.
2. The body satisfies **both** required assertions on their own lines:
   - `User-Impact: <named user-visible consequence>` — enforced as a **positive
     allow-list, not a deny-list of bad phrasings.** The value must name a token
     from the **same closed surface taxonomy the Phase 1.3 backfill uses**:
     route, page, component, CLI command, email, or user-facing document. A
     deny-list can only ever catch phrasings already in it, it rots against the
     wording of whichever review agent is current, and a mutation row that tests
     it with a phrase from its own list cannot fail. Inverting to the positive
     form is bounded, does not rot, and — the real win — makes the filing gate
     and the backfill classifier share **one** taxonomy instead of two concepts
     that must be kept in agreement. State plainly in ADR-216 that this is still
     a shape check, not a semantic one.
   - `Fix-Size: <N> lines / <M> files` — a **measured** value. The gate asserts
     the digits are present and parse; it does not trust an adjective. If
     `N <= 100 && M <= 4`, the filing is **refused** with the message that this
     is inside the inline threshold — fix it inline, do not file. This is the
     check that would have caught the 19-lines-in-1-file deferral.
     **The threshold's provenance must be cited, not asserted.** `100`/`4` are
     carried from the brief; `wg-defer-only-after-inline-triage`'s own triple
     test is qualitative ("one small file or ~10-line change") and names no such
     numbers. Before the hook quotes a threshold in a refusal message, locate its
     real source (ADR, skill, or prior PR) and cite it inline; if no source
     exists, derive it in ADR-216 and record the derivation. A refusal that names
     a threshold nobody can trace is how the escape reflex gets trained.
   - **The derivable-inputs check is a deny predicate, not a third field.** When
     the body claims the "we lack the numbers" blocker class (`would have to
     choose`, `we lack`, `no numbers`, `unknown values` and siblings), the filing
     is refused unless an `Inputs-Derived: <source>` line names a **concrete
     source class** — a workflow run, a log query, a telemetry marker, or a prior
     PR. A free-text third field that any single token satisfies enforces
     nothing: the agent that wrote "we lack the numbers" would proceed by
     appending a word. Making the claim itself the trigger, and requiring a
     source class rather than free text, is strictly stronger than the
     three-field form while removing one field from the contract.
3. The body carries `Mandated-By: <rule-id>` on its own line. **This is the
   reconciliation with ADR-155** — the same closed, human-gated vocabulary, so
   the rule that *mandates* a filing and the gate that *restricts* filing cannot
   disagree. The hook does not re-derive the tagged set (that is
   `net-issue-flow.sh`'s job, from the merge-base corpus); it accepts the
   well-formed claim and lets the merge-boundary gate adjudicate it. Two gates,
   one vocabulary, no second pin on the same fact.

2.4 **No escape hatch — deliberately.** An earlier draft added a purpose-named
bypass marker. It is cut: exit 1 (`--label meta/machinery`) is already a free,
always-available exit that the Risks table itself calls "cheap to comply with
honestly." Name the filing that must bypass the gate, cannot be labelled
machinery, and cannot name a user impact — there isn't one. Adding a fourth exit
to a gate that already has a universal one would reproduce exactly the
reflexive-override pathology ADR-155 documents, and the deny incident already
gives the weekly measurement its signal from the other side. Record this cut, and
its reasoning, in ADR-216.

2.5 **Reconcile `wg-defer-only-after-inline-triage` into one rule, byte-negative.**
Per `cq-agents-md-tier-gate`, a rule that becomes `[hook-enforced:]` keeps
`[id]` + tag + a one-line pointer, with the full rule living in the enforcing
artifact. So:

- add `[hook-enforced: .claude/hooks/guardrails.sh guardrails:require-filing-justification]`
  to the existing rule body;
- **move** the triple test's prose into the hook's header comment block (the hook
  file already carries a "Corresponding prose rules" section — extend it) and
  trim the rule body to the pointer form;
- the net edit to `AGENTS.rules.md` **must be negative**, verified by re-running
  `lint-agents-rule-budget.py`. This is not optional polish: at
  `B_ALWAYS=45999/46000` a byte-positive edit cannot merge.
- **Do not rename or retire the id** (`cq-rule-ids-are-immutable`), do not add a
  new id, and do not touch the `AGENTS.md` index pointer line.
- Extending an existing rule body may trip the ADR-092 ack gate. If it does, that
  is a legitimate human-gated ack, not a blocker to route around — record it.

2.6 **Extend `.claude/hooks/guardrails.test.sh`** with the full mutation matrix,
including the harness rows.

### Phase 3 — L3: extend the existing expiry sweeper (stock cleanup only)

**Phase 3.5 of an earlier draft claimed the first live sweep was safe "because the
`meta/machinery` label is brand-new." That argument is false and is corrected
here.** The label is new; the *issues* are not. The sweeper's only age signal is
`updated_at` (via `updated:<${cutoffIso}` in `fetchCandidates`), so label novelty
confers zero age protection, and 58% of the backlog is already older than 60 days.
Both branches of the unexamined question are bad:

- if applying a label does **not** bump `updated_at`, the first daily fire after
  merge closes up to the search cap;
- if it **does**, the entire backfilled cohort becomes eligible on the *same day*
  90 days out — a thundering herd, larger by then, when nobody is watching.

Phase 3.0 therefore replaces the false safety property with four real ones.

3.0 **Real safety properties, in order of value.**

- **Stage the backfill in tranches** (e.g. 50/week) rather than one bulk pass.
  This staggers eligibility naturally and makes the first cohort's reopen rate a
  *measured input* before the next cohort is labelled.
- **`MAX_CLOSES_PER_RUN`, distinct from `SEARCH_MAX_RESULTS`.** The existing
  200-item cap bounds *candidates*, not *closes*. Add a close cap as a single
  named constant cited by both runner and test, and return a `deferred: N` field
  so the unswept remainder is visible in the run log rather than silent.
- **`MACHINERY_SWEEP_NOT_BEFORE`**, an ISO date set to merge + 30 days, gating
  only the `meta/machinery` arm. Zero API calls, trivially unit-testable,
  self-expiring, and it guarantees the operator a full month with the new digest
  before any machinery issue can be closed.
- **Probe the label-bump behaviour empirically and record it**, applying to
  `updated_at` exactly the discipline 3.4 already applies to `stateReason`: the
  field the entire expiry decision keys off must not be inferred from
  documentation. (A planning-time attempt over 40 open issues found no issue whose
  most recent timeline event was `labeled`, so this was not settled at plan time
  and is carried as a Phase 0 probe rather than an assumption.)

3.1 **Generalize the target from a constant to a set — and get the query shape
right, because the obvious implementation silently matches nothing.** In GitHub
search syntax **multiple `label:` qualifiers are ANDed**; comma-separated values
inside **one** qualifier are ORed. Mapping the target list and joining with a
space yields `label:"deferred-scope-out" label:"meta/machinery"`, which matches
only issues carrying *both* — zero. The sweep would then return
`{total: 0, closed: 0}`, post an `ok` Sentry heartbeat, and log "Auto-closed 0
stale issues", which is **indistinguishable from a clean run**. That is precisely
Guard 2's mutation row 5, and it is the single most likely implementation bug in
this phase.

- Emit `label:"deferred-scope-out","meta/machinery"` — one qualifier,
  comma-joined.
- **Unit-test the constructed query string itself**, not merely the sweep result.
- Add a **non-zero-candidate floor**: a run finding zero candidates across a
  600+-issue labelled population is a defect, not a success.
- **Decide OR-query vs. per-label queries explicitly.** Two queries double the
  per-run write budget; one OR-query with `sort:updated-asc` front-loads the
  oldest, which after backfill is *entirely* machinery, permanently starving the
  `deferred-scope-out` arm the cron was built for. Record the choice and its
  starvation mitigation in the ADR.

Keep the Inngest function id, `SENTRY_MONITOR_SLUG`, and the `cron-manifest.ts`
entry **unchanged** — renaming any of them breaks the Terraform-provisioned Sentry
monitor's check-in continuity and the manifest parity test. Update the
`routine-metadata.ts` description: it is the only operator-visible description of
what this cron does, and leaving it saying "deferred scope-outs" would make the
operator's own inventory misrepresent a closer that now touches hundreds of issues.

3.2 **Widen the kill switch and add D2's never-touch guards.** The sweeper must
skip an issue when **any** holds:

- it carries `do-not-autoclose` (existing) **or** `keep-open` (new — the label
  exists and is currently unhonored by this sweeper). Record in the ADR that
  `keep-open` already carries a *different* meaning in
  `.github/workflows/codeql-to-issues.yml` ("tracks something other than the alert
  state", closed with `--reason completed`); adopting it here as a general
  never-auto-close pin is fine, but two sweepers now read one label with two
  definitions and that must be written down;
- it carries a product-facing label (`domain/product`, `type/feature`,
  `action-required`, or a `priority/p0`/`p1` label);
- it has been **human-triaged** — at least one comment authored by a non-bot
  account. Determine this from `user.type === "Bot"` **plus** an allowlist of
  known automation actors, not the allowlist alone. The asymmetry favours us: a
  GitHub App posting via an installation token appears as `type: "Bot"`, while an
  agent using a PAT posts as the human user — so agent comments read as human and
  fail toward skipping. **Fail toward skipping** whenever authorship cannot be
  determined, and give that path its own `op` discriminator so it is not an alert
  storm indistinguishable from write failures. The operator explicitly rejected
  the any-zero-comment variant, so the sweeper's scope stays
  `meta/machinery`-labelled only; the human-triage guard is a second net inside
  that scope, not a widening of it.

The first three are **free** — `fetchCandidates` already materialises
`labels: Array<{ name: string }>` from the search response, so no extra call is
needed. Adding a belt-and-braces `-label:"keep-open" -label:"domain/product"` … to
the query as well is worth it purely to cut write volume, **provided the in-loop
check remains authoritative** (a query-level filter alone is defeated by GitHub
Search's eventual-consistency window, which the existing code already guards
against for the closed-state case).

3.2a **The human-triage guard is an N+1, and as currently structured the dry-run
cannot exercise it.** It needs `GET /issues/{n}/comments` per candidate — and in
the existing file that GET sits on the **write path**, inside the try *below*
`if (dryRun) continue`. So Phase 3.3's "dry-run first" safety step and Test
Scenario 5 ("every never-touch class appears as a skip with its reason") are both
**unsatisfiable** unless the comment fetch is hoisted above the dry-run
short-circuit. Since dry-run is the stated pre-live safety step for the corrected
Phase 3.0, this is load-bearing, not cosmetic.

**Cheap fix for the N+1:** the search response carries a `comments` integer that
`SearchResponseItem` currently discards. Capture it and fetch comments only when
`comments > 0`. Given 330 of 1,455 open issues have zero comments — and machinery
findings skew heavily that way — this removes the GET for most candidates. When
`comments === 0` no `COMMENT_MARKER` can exist either, so the existing idempotency
GET is skippable on the same signal.

3.3 **Close with an explanatory comment stating why and how to reopen**, reusing
the existing `COMMENT_BODY` machinery. The comment must name the quiet period, the
label, and the one-step reopen path.

**The idempotency guard has a defect across sweep generations that must be fixed
here.** If an operator reopens an auto-closed issue and it later goes quiet, the
sweeper re-closes it 90 days on — but the GET-before-POST guard finds
`COMMENT_MARKER` already present and **skips the comment**. The second auto-close
is therefore *silent*: no explanation, no reopen instructions, nothing in the
timeline but a state change — and it fires precisely on issues a human already
said they cared about. Fix by scoping the marker to the current sweep generation
(append a date or sweep epoch), or by bypassing the guard when the issue has been
reopened since the last marker-bearing comment. The guard remains correct for its
intended replay-safety purpose; only the cross-generation case changes.

3.4 **The separability marker: use `COMMENT_MARKER`, not `stateReason`.** An
earlier draft keyed expiry-close identification on
`state_reason: "not_planned"`. That field is **current-state only, not history**:
reopening sets it to `reopened` and the prior `not_planned` is gone. Two
consequences, both fatal to the draft:

- the reopen-count detection — the plan's **only** signal for "the sweeper closed
  a legitimate issue", mitigating the risk ranked Highest — is unimplementable
  against a field that no longer holds the value being filtered on;
- `stateReason` is not attributable anyway: a human closing a machinery issue
  wontfix produces the identical value and is misattributed as an expiry close.

The durable discriminator already exists: the sweeper's stable HTML-comment
marker. It survives reopen, survives re-close, and is attributable to *this
sweeper specifically*. Key **both** the expiry-close count and the reopen count on
it. Verify empirically the round-trip the measurement actually depends on —
**close → reopen → read → re-close** — not merely `stateReason` on close.

3.5 **Exercise dry-run first, and require it to be reviewed.** Fire the
manual-trigger event with `{ data: { dry_run: true } }` and read the candidate
list before any live sweep. With 3.2a's hoist in place the dry-run genuinely
exercises every skip class; without it, the dry-run is not the safety step it
claims to be.

### Phase 4 — L4: net-negative cadence and gate visibility

4.1 **Weekly drain, ADR-033-compliant.** Add an Inngest cron function following
the `cron-dev-migration-drift.ts` shape, which dispatches (raw `octokit.request` POST to the workflow `dispatches` endpoint) a new
`.github/workflows/scheduled-machinery-drain.yml` carrying **`workflow_dispatch: {}`
only** — no `schedule:`/`cron:` block. This is what keeps
`new-scheduled-cron-prefer-inngest.sh` allowing the write without reaching for its
override hatch, and it is the pattern ten sibling crons already use. Register the
function in `cron-manifest.ts`, `app/api/inngest/route.ts`, and
`routine-metadata.ts`, and provision its Sentry cron monitor in Terraform
alongside its siblings.

4.2 **Closing floor, with a candidate-aware arm.** The operator set the floor at
`>= 20` closes per run, failing the run below it. Implement it as a single named
constant cited by both the runner and its test so the two cannot drift — **and
gate it on candidate supply**: the run fails below the floor only when the
candidate pool held at least the floor. When the pool is smaller, the run closes
every candidate and passes, reporting `closed=N of N candidates (floor waived:
pool < floor)`. Without that arm the floor is unsatisfiable-by-construction the
moment the backlog is actually drained — a scheduled monitor whose steady state
on success is red, which trains the operator to ignore it. The waiver is
**reported, never silent**, so a chronically empty pool is visible rather than
indistinguishable from a healthy run.

4.3 **The weekly measurement — the thing that makes the success criterion
checkable.** A script, invoked by the same weekly workflow, reporting **five**
counts:

1. **filed** in the window, and the derived **filed-per-week** beside the
   pre-merge baseline of ≈142/week.
2. **expiry closes** — `meta/machinery`-labelled issues closed with
   `stateReason == "NOT_PLANNED"`. Reported for AC26 attribution: it says how
   much of any open-total drop came from expiry rather than from real work.
3. **`net-issue-flow` override count** — merged PRs in the window whose body
   carries `<!-- gate-override: net-issue-flow -->`, plus `SOLEUR_SKIP_NET_ISSUE_FLOW_GATE`
   env bypasses.
4. **`net-issue-flow` fail-open count** — occurrences of the
   `net-issue-flow fail-open:` warn marker.
5. **open-issue total** against the recorded baseline.

**A filing rate has no close term — this is the correction that makes the
operator's requirement actually hold.** An earlier draft reported a "filing rate
with expiry closes excluded", which is incoherent: filings-per-week is
`filed / weeks` and closes never enter it. The operator's stated requirement is
that expiry closes must not be able to mask a flat or rising filing rate — and
measuring the filing count *directly*, with no close term at all, satisfies that
requirement completely and by construction rather than by subtraction. Expiry
closes are still reported (line 2), but against the open **total**, which is
where they legitimately belong.

Counts 3 and 4 are reported **as their own lines**, never folded into a pass. A
gate that failed open must not read identically to a gate that passed — the same
class as the empty-telemetry-is-not-absence edge — and they carry different
remedies, so they are never summed.

Two further counts belong to the **Observability** section's detection paths, not
to this report, and are named there rather than duplicated here: the filing
gate's own `deny`/`fire` counts (which detect both over-denial and a gate that
silently stopped matching) and the reopen count on expiry-closed issues (which
detects a wrong close). Keeping one canonical enumeration prevents the
two-places-that-disagree drift.

4.4 **The measurement must not itself be a filer.** Find-or-**update** exactly one
standing issue, following the idempotent `model-drift` pattern already in
`.github/workflows/rule-audit.yml`. A measurement that files a fresh issue each
week is the defect reproducing itself inside its own instrument.

4.5 **Auth.** Declare `GH_TOKEN` explicitly and forward it through any `env -i`
allowlist. A script that authenticates locally via `~/.config/gh` and silently
never runs in the sandbox is a documented failure mode here, not a hypothetical.

### Phase 5 — Measurement note and artifacts

5.1 Write `knowledge-base/project/specs/feat-one-shot-issue-flow-ledger-separation/measurement-baseline.md`
recording: the write-up figure (1,456), the planning-time live recount (1,455),
the 8-week opened/closed/net figures, the 60-day and zero-comment counts, the
626:39 domain split, the 98 override count, both budget readings, the exact
commands that produced each, and the date the 4-week re-check falls due. This is
the artifact the success criterion is checked against.

5.2 Author ADR-216 per the section above.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** — `gh label list --limit 300 --json name --jq '.[].name'` includes
  `meta/machinery` exactly once.
- **AC2** — `plugins/soleur/skills/operator-digest/SKILL.md` §4 names
  `meta/machinery` in its EXCLUDE list; the guardrail's presence is asserted, not
  the absence of the token (an exclusion line legitimately *contains* the label
  name, so an absence-grep would false-fail a correct file).
- **AC3** — `ticket-triage` and `drain-labeled-backlog` each carry an explicit
  `meta/machinery` exclusion, asserted the same way.
- **AC4** — `plugins/soleur/skills/ship/scripts/net-issue-flow.sh` is **unchanged
  with respect to label filtering**: `git diff origin/main -- <path>` introduces
  no label filter. The machinery ledger stays inside the gate's count.
- **AC5** — the backfill proposal artifact is committed, and every issue labelled
  in this PR appears in it with its matched evidence token. Zero issues are
  **closed** by the backfill: the count of issues transitioning to closed
  attributable to Phase 1 is 0.
- **AC6** — `bash .claude/hooks/guardrails.test.sh` passes, and every row of the
  Guard Contract mutation matrix below is present in it and drives the stated
  colour.
- **AC6a** — the existing fixtures that asserted `--milestone` alone is
  sufficient to ALLOW a `gh issue create` have been migrated to the new
  contract, and the migration is visible in the diff. `--milestone` is now
  necessary but not sufficient.
- **AC6b** — `.claude/hooks/guardrails.test.sh` carries an **assertion-count
  floor**. It has none today (539 lines, zero hits for `floor`/`PASS_COUNT`/
  `assert_count`/`MIN_`), so a run that executed zero assertions would exit 0 and
  read as a pass. Guard 1's harness row and the Observability
  `discoverability_test` both depend on this floor existing; it is therefore a
  declared deliverable of this PR, not an assumed property. Mutation: set the
  suite to run zero assertions and confirm it exits non-zero.
- **AC7** — the gate **denies**: a `gh issue create` with no `--label meta/machinery`,
  no `User-Impact:`, and no `Mandated-By:` returns `permissionDecision: "deny"`.
  Asserted on the decision field, not on the presence of a warning string.
- **AC8** — the gate **allows** all three exits, each on its own fixture.
- **AC9** — the gate **refuses a filing whose `Fix-Size:` is inside the inline
  threshold** (e.g. `19 lines / 1 file`), with a message naming the threshold.
- **AC10** — `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1`
  reports `B_ALWAYS` **strictly lower** than the 45999 recorded in Phase 0.1, and
  exits 0. A byte-neutral edit does not satisfy this.
- **AC11** — `git diff origin/main -- AGENTS.md` is **empty** (the index is
  untouched), and `AGENTS.rules.md` contains `wg-defer-only-after-inline-triage`
  exactly once, still carrying that id, now carrying the `[hook-enforced: …]` tag.
- **AC12** — no `[mandates-filing]` marker is added, removed, or reworded:
  `git diff origin/main -- AGENTS.rules.md | grep -c 'mandates-filing'` is 0.
- **AC13** — cumulative skill-description word count is **≤ 2400** and no new
  `SKILL.md` was added. `bun test plugins/soleur/test/components.test.ts` passes.
- **AC14** — the sweeper skips every never-touch class: contract tests cover
  `do-not-autoclose`, `keep-open`, each product-facing label, and a human-authored
  comment, each independently forcing a skip.
- **AC15** — the sweeper's Inngest function id, `SENTRY_MONITOR_SLUG`, and
  `cron-manifest.ts` entry are byte-identical to `origin/main`.
- **AC16** — the new weekly-drain GHA workflow contains **no** `schedule:` or
  `cron:` key, and `.claude/hooks/new-scheduled-cron-prefer-inngest.sh` allows its
  write with no override marker present anywhere in the file.
- **AC17** — the new Inngest cron function is registered in all three places
  (`cron-manifest.ts`, `app/api/inngest/route.ts`, `routine-metadata.ts`) and its
  Sentry monitor exists in Terraform; the cron-manifest parity test passes.
- **AC18** — the measurement script's output contains, as separately-counted
  lines, exactly the five counts enumerated in Phase 4.3: filed (with
  filed-per-week beside the ≈142/week baseline), expiry closes, override count,
  fail-open count, open total. A run with zero overrides and a run with a
  fail-open produce **different** output, and neither is folded into a pass line.
- **AC18a** — the detection counts named in `## Observability` (the filing gate's
  deny/fire counts and the reopen count on expiry-closed issues) are emitted by
  their stated paths. Verified separately from AC18 so the two enumerations
  cannot silently diverge.
- **AC18b** — a dry-run `bash scripts/rule-metrics-aggregate.sh` exits 0 with the
  new hook's telemetry present: the emitted `rule_id` is
  `wg-defer-only-after-inline-triage` (an active AGENTS.md id), so the
  aggregator's orphan gate — which exits 5 on an unrecognised id — does not fire.
- **AC19** — the measurement performs a find-or-update against exactly one
  standing issue: a second consecutive invocation creates zero new issues.
- **AC20** — `measurement-baseline.md` exists, names 1,456 and 1,455 with the
  command that produced each, and states the 4-week re-check date.
- **AC21** — `ADR-216-*.md` exists, its ordinal is next-free against a
  freshly-fetched `origin/main` at ship time, and it records the label decision,
  both rejected alternatives with the mechanical reason each was rejected, and the
  ADR-155 reconciliation.
- **AC22** — the C4 conclusion cites the external-actor / external-system /
  access-relationship enumeration against all three `.c4` files, and
  `plugins/soleur/test/c4-count-parity.test.sh` is green.
- **AC23** — full battery green: `bash scripts/test-all.sh` (or the repo's
  canonical full-suite entry), including the orphan suites that no touched-file
  set reaches.
- **AC24** — the PR body contains no `#NNNN` contextual issue reference; the
  narrative is date-anchored prose. No GitHub issue is filed for this work.

### Post-merge (measurement, automated)

- **AC25** — **the success criterion.** Four weeks after merge, the weekly
  measurement's **filed-per-week** figure is **lower** than the pre-merge
  baseline of 1,134 filed over 8 weeks (≈142/week). The metric is
  `filed_in_window / weeks` — a pure filing count with **no close term**, which
  is precisely why no close, expiry or otherwise, can mask a flat or rising
  filing rate. Checked by the standing measurement issue, not by a human
  remembering.
- **AC26** — the open-issue total four weeks after merge is below the 1,455
  planning-time baseline, **and** the measurement reports how much of the drop is
  attributable to expiry closes versus real closes, so a stock sweep is never
  mistaken for a rate improvement.
- **AC26a** — a note in `measurement-baseline.md` records that expiry
  contributes **nothing** to the open total during the first 90 days after the
  backfill if the label-application-resets-the-quiet-clock property holds
  (Phase 3.0). Whichever way that probe resolves, the 4-week expectation for
  AC26 is stated explicitly rather than assumed, so a flat open total at week 4
  is read as "expiry has not started yet", not as "the plan failed".

## Guard Contract

The deliverable includes guards, so each carries a property, an assembly, and a
mutation matrix written **before** the guard.

### Guard 1 — `guardrails:require-filing-justification`

**Property.** No `gh issue create` against a `jikig-ai/*` repo succeeds unless the
filing is either routed to the machinery ledger, carries a named user-visible
consequence with a measured fix size, or carries a well-formed mandate claim.

**Assembly.** An earlier draft claimed the PreToolUse Bash hook was *the*
chokepoint that "every agent-authored `gh issue create` flows through." **That
claim is false**, and by this contract's own standard — a guard scoped to one of
several injection sites is the defect unless the exclusion is stated and justified
— the guard as first specified *was* the defect. The real filing surface has
**five** classes:

| # | Filing path | Covered? |
|---|---|---|
| 1 | Interactive / `/work` / `/review` Bash `gh issue create` | **Yes** — PreToolUse Bash hook |
| 2 | `.github/workflows/*.yml` | No — never traverses a PreToolUse hook. Mandated, machine-authored infra alerts (drift, health, advisor scans). Legitimately out of assembly. |
| 3 | **Inngest cron agent substrate** | **No — and this is the one that matters.** `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts`'s `buildCronEvalSettings` returns a per-spawn settings overlay whose *only* PreToolUse entry is `cron-bash-allowlist-hook.mjs`; the eight-deep chain in `.claude/settings.json`, `guardrails.sh` included, is never loaded. Its `ISSUE_CREATOR_BASH_ALLOWLIST` contains `gh issue create`, applied to `cron-growth-execution`, `cron-competitive-analysis`, `cron-seo-aeo-audit`, `cron-architecture-diagram-sync`, `cron-content-generator`, plus bespoke entries for `cron-roadmap-review`, `cron-growth-audit`, `cron-campaign-calendar`, `cron-community-monitor`, `cron-bug-fixer`. **Ten scheduled agents that file discretionary LLM-authored findings and never traverse the gate** — precisely the audit-exhaust class the Overview blames for the 626:39 skew. Corroboration that the gap is already live: none of these filings carry `--milestone` either, because the sibling gate misses them the same way. |
| 4 | `gh api …/issues -X POST` | No — the trigger regex matches `gh issue create` only. **The route-around is already documented**: `knowledge-base/project/learnings/best-practices/2026-06-11-posttooluse-hooks-that-write-files-need-atomic-restore-symlink-refusal-and-orphan-gate-exemption.md` records a filing made this exact way *after* `guardrails:require-milestone` blocked it. A blocking gate will train this faster than an advisory one did. |
| 5 | Octokit / MCP | No — `apps/web-platform/server/github-tools.ts`'s `create_issue` tool and `apps/web-platform/server/workstream/mutate-workstream-issue.ts` call Octokit directly, no Bash involved; and the hook's `.claude/settings.json` matcher is `"Bash"`, so an `mcp__github__create_issue` never reaches it. |

**The assembly is therefore two chokepoints, not one**, and this PR must cover
both or say plainly that it does not:

- the **PreToolUse Bash hook** for class 1, and
- the **cron Bash allowlist hook** (`cron-bash-allowlist-hook.mjs` +
  `ISSUE_CREATOR_BASH_ALLOWLIST`) for class 3, which is that population's real
  chokepoint and is just as structural.

Class 4 is closed cheaply by widening the trigger to `gh api …/issues` with a
`-X POST` / `--method POST` / `-f title=` discriminator, with its own matrix row.
Classes 2 and 5 stay out of assembly, stated and justified.

**Consequence for the success criterion, which must land before AC25 is trusted:**
re-derive what fraction of the measured 1,134 eight-week filings originate inside
versus outside the covered surface. Guard 1's matrix is all Bash fixtures, so a
fully-green matrix would otherwise certify a gate covering a minority of the
filing surface — the exact "certifies something other than what it names" class
this plan cites elsewhere.

**Mutation matrix** (each must drive the guard RED unless marked PASS):

| # | Mutation | Expected |
|---|---|---|
| 1 | Bare `gh issue create --title X --body Y --milestone M` with no exit satisfied | RED (deny) |
| 2 | Delete the `deny` branch from the hook so it returns `allow` | RED |
| 3 | **Guard's own dispatch:** make the `gh issue create` detection never match (e.g. break the `$SCAN` pattern) so the gate reports zero checks and exits 0 | RED — a gate that checks nothing must not read as a pass |
| 4 | **Second member after a compliant first:** a chained command whose *first* clause is a compliant filing and whose *second* clause is a bare filing | RED — the check must not stop at the first |
| 5 | `User-Impact:` present but its value is a known-vacuous shape ("the guard is imperfect") | RED |
| 6 | `Fix-Size: 19 lines / 1 file` (inside the inline threshold) | RED (refuse — fix inline) |
| 7 | `Fix-Size:` present but non-numeric ("small") | RED |
| 8 | `Mandated-By:` present but malformed (no rule id) | RED |
| 9 | **Harness row:** delete an assertion from `guardrails.test.sh` and confirm the suite's own pass-count floor notices | RED |
| 10 | **Harness row, must-PASS non-canonical:** a compliant filing that differs from the canonical fixture in a way the contract permits — `--label meta/machinery` supplied via `--label=meta/machinery`, and a `User-Impact:` line with different wording and surrounding whitespace | PASS |
| 11 | **Must-PASS:** `gh issue create --repo someone-else/upstream …` with no exit satisfied (external repo) | PASS |
| 12 | **Must-PASS:** a `git commit` whose *message body* documents `gh issue create` | PASS — the #5192 false-positive class the `$SCAN` strip exists to prevent |

Rows 10–12 are what distinguish this guard from one that rejects everything; rows
3–4 are what distinguish it from one that asserts nothing.

### Guard 2 — the sweeper's never-close guards

**Property.** No issue that is human-triaged, product-labelled, or explicitly
pinned is ever auto-closed, at any quiet age.

**Assembly.** The single per-candidate skip evaluation inside the sweep step —
the one place every candidate passes through before the comment/close sequence.
Not the search query: a query-level filter would be silently defeated by GitHub
Search's eventual-consistency window, which the existing code already guards
against for the closed-state case.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the `keep-open` term from the kill-switch set | RED |
| 2 | Remove the `do-not-autoclose` term | RED |
| 3 | Remove the product-label term | RED |
| 4 | Remove the human-comment term | RED |
| 5 | **Guard's own dispatch:** make the candidate loop iterate zero times and still report success | RED |
| 6 | **Second member:** two candidates where the first is closeable and the second carries `keep-open` | RED if the second is closed — the skip must not be short-circuited by the first candidate's outcome |
| 7 | Make the bot-authorship determination throw | RED unless the outcome is *skip* — the guard must fail toward not closing |
| 8 | **Must-PASS:** a `meta/machinery` issue, 91 days quiet, no comments, no pinned or product labels | PASS (closes) |
| 9 | **Must-PASS, non-canonical:** the same but 400 days quiet and carrying an unrelated `chore` label | PASS |

### Guard 3 — the weekly closing floor

**Property.** A weekly drain run that closes fewer than the floor fails loudly
rather than reporting a quiet success.

**Assembly.** The single floor constant, cited by both the runner and its test.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change the floor constant in the runner only | RED — the test must be pinned to the same constant, not a literal copy |
| 2 | Make the closed-count always report the floor exactly | RED — a forged counter must be detectable |
| 3 | **Guard's own dispatch:** the run closes zero and exits 0 | RED |
| 4 | **Must-PASS:** a run closing exactly the floor | PASS |
| 5 | **Must-PASS:** a run closing more than the floor | PASS |

## Observability

```yaml
liveness_signal:
  what: Sentry Crons check-in for the widened expiry sweeper (existing slug,
        unchanged) and a new check-in for the weekly drain cron.
  cadence: expiry sweep daily; drain weekly.
  alert_target: Sentry missed-check-in alert, same margin convention as sibling crons.
  configured_in: Terraform sentry_cron_monitor resources, alongside existing siblings.

error_reporting:
  destination: Sentry via the Inngest sentry-correlation middleware, plus
               reportSilentFallback mirroring (the substrate both new/widened
               crons inherit).
  fail_loud: yes — the drain run exits non-zero below the closing floor; the
             filing gate emits a deny incident on every block.

failure_modes:
  - mode: The filing gate denies a legitimate filing and stalls an autonomous run.
    detection: emit_incident deny events for guardrails-require-filing-justification
               in .claude/.rule-incidents.jsonl, aggregated by
               scripts/rule-metrics-aggregate.sh.
    alert_route: weekly measurement reports the deny count; a spike is visible
                 against the filed count in the same report.
  - mode: The filing gate silently stops matching (guard's own dispatch dies) and
          every filing sails through.
    detection: the same aggregator's fire_count for this rule id dropping to zero
               while filings continue — the empty-telemetry-is-not-absence case.
               The weekly measurement reports fired-count and filed-count side by
               side so zero-fired-with-nonzero-filed is visible rather than silent.
    alert_route: weekly measurement line.
  - mode: The sweeper closes a legitimate issue.
    detection: reopened-issue count on meta/machinery-labelled, NOT_PLANNED-closed
               issues, reported weekly.
    alert_route: weekly measurement line; a nonzero reopen count is the signal the
                 evidence rule or the never-touch guards need tightening.
  - mode: net-issue-flow fails open on an API error and reads as a pass.
    detection: the net-issue-flow fail-open: warn marker, counted separately in
               the weekly measurement (Phase 4.3).
    alert_route: weekly measurement line, reported as its own count.
  - mode: The weekly drain never fires (Inngest cron silent, or the dispatch
          fails).
    detection: Sentry missed-check-in on the drain monitor.
    alert_route: Sentry Crons alert.

logs:
  where: Inngest run logs plus Sentry breadcrumbs for the crons;
         .claude/.rule-incidents.jsonl for the hook.
  retention: as per the existing cron substrate and the repo's incident-log
             rotation; no new retention surface introduced.

discoverability_test:
  command: bash .claude/hooks/guardrails.test.sh
  expected_output: "Fail: 0"
```

The command's first token is `bash`, which is on preflight Check 10's probe-verb
allowlist, and it contains no `ssh`. No credentials are required: the hook suite
is fully local. `Fail: 0` is matched as a substring of the suite's
summary line; it is not on its own a guard against a vacuous run, because
`Total: 0  Pass: 0  Fail: 0` would also contain it. What rules that out is the
suite's own assertion-count floor, which exits non-zero below `MIN_ASSERTIONS`
and so fails the probe on rc rather than on output.

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering

**Status:** reviewed
**Assessment:** The change is entirely inside Soleur's own workflow machinery —
one PreToolUse hook, one rule-body reconciliation, one widened Inngest cron, one
new Inngest cron plus its dispatched workflow, and one measurement script. The
two dominant engineering risks are (a) a blocking hook that over-denies and
stalls autonomous runs, and (b) an auto-closer whose scope is widened. Both are
addressed by contract-tested guards with must-PASS rows rather than by review
attention. The budget-at-cap finding is the most consequential engineering
constraint and is what forces the reuse-over-build shape; it should be treated as
a design input, not a late surprise.

### Product/UX Gate

**Tier:** none
**Decision:** not applicable — no user-facing surface
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

The mechanical UI-surface override was evaluated against the Files lists below:
no path matches `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`.
The only file under `apps/web-platform/` is a server-side Inngest cron. Product is
*relevant* — the whole point is that the ~39 product issues become visible — but
the change implements orchestration, not UI, so the gate is NONE.

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-216-<slug>.md`
- `knowledge-base/project/specs/feat-one-shot-issue-flow-ledger-separation/measurement-baseline.md`
- `knowledge-base/project/specs/feat-one-shot-issue-flow-ledger-separation/tasks.md`
- `apps/web-platform/server/inngest/functions/cron-machinery-drain.ts` (weekly drain dispatcher)
- `.github/workflows/scheduled-machinery-drain.yml` (`workflow_dispatch: {}` only)
- a measurement script under `scripts/`, plus its test
- a backfill-proposal script under `scripts/`, plus the committed proposal artifact

## Files to Edit

- `.claude/hooks/guardrails.sh` — new `guardrails:require-filing-justification` block
- `.claude/hooks/guardrails.test.sh` — Guard 1 mutation matrix
- `AGENTS.rules.md` — `wg-defer-only-after-inline-triage` reconciliation (byte-negative)
- `plugins/soleur/skills/operator-digest/SKILL.md` — §4 exclusion
- `plugins/soleur/agents/support/ticket-triage.md` — routing exclusion
- `plugins/soleur/skills/drain-labeled-backlog/SKILL.md` — explicit exclusion, closing floor
- `apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts` — target set, kill-switch widening, never-touch guards
- `apps/web-platform/server/inngest/cron-manifest.ts`, `app/api/inngest/route.ts`, `routine-metadata.ts` — register the drain cron; update the sweeper description
- the Terraform Sentry-monitor file — new monitor for the drain cron
- the sweeper's existing test file — Guard 2 mutation matrix

**Not edited, deliberately:** `plugins/soleur/skills/ship/scripts/net-issue-flow.sh`
(no label filter — see AC4) and `AGENTS.md` (index untouched — see AC11).

## Non-Goals

- **The `DRIFT_SUSTAINED_THRESHOLD_MIN` correction is out of scope here.** The
  carried-over brief asked for it; it does not belong on this branch. `resolve-target`
  is absent from this branch's base — `git grep -i 'resolve.?target'` on HEAD returns
  only an unrelated step in `cla-evidence-timestamp.yml`. It exists only on the
  CI-concurrency branch, where it replaces the `await-ci` job deleted by
  `32db22d9b feat(release): fire the web-platform deploy off CI completion, not a poll`.
  Raising 207 here would widen a production alert threshold to cover a pipeline shape
  that does not exist yet, leaving the drift alerter blind to real drift for the whole
  window until the other branch merges — strictly worse than the status quo, and the
  "alert that no longer alerts" failure mode. The correction belongs on the
  CI-concurrency branch, where its rationale is already carried in
  `scripts/prod-version-drift-check.test.sh`, in the comment block above
  `crit = max(release_ceiling, job_timeout("resolve-target"))`.

  **Three measured corrections to the brief's framing, recorded so the next reader
  does not inherit them** (verified against this tree, not relayed):
  1. On this tree `await-ci` declares `timeout-minutes: 72`, not 60 — raised by
     #7902 when its in-bash `CEILING_S` moved 3000 → 3600. The declared path is
     therefore `max(release 60, await-ci 72) + migrate 30 + verify 15 + deploy 90 =
     **207**`, which **exactly equals** `DRIFT_SUSTAINED_THRESHOLD_MIN=207`. B9
     passes here at **zero margin**, not with headroom. Any claim of "195, and it
     fits" describes the pre-#7902 pipeline.
  2. "Restoring the CI term" is a misnomer: B9's extractor has **never** carried a
     `ci` term (`git log -S 'job_timeout("ci")'` on that file returns zero hits).
     Folding it in would be an *addition*, and the branch's `70` is derived
     (`test-scripts 60 + test 10`), not declared anywhere as a `timeout-minutes: 70`.
  3. **Lowering the resolve-target 60m ceiling is provably ineffective on its own**,
     independent of any dead-code question. The extractor computes
     `crit = max(release_ceiling, job_timeout("resolve-target")) + 135`, so for any
     `T <= 60` the `max` stays 60 and the sum is unchanged. Dropping it to 5 minutes
     moves the bound by zero. On the dead-code claim itself: the poll **loop** is
     genuinely unreachable (both arms share a `cancel-in-progress: false` concurrency
     key, so the loop exits on iteration 1), but the **60m `timeout-minutes` is not
     dead** — it bounds the whole job and is a live input to B9. The two were
     conflated; only raising the threshold, or cutting a serial term, changes 265.

  Recorded here in place per `wg-when-deferring-a-capability-create-a`; **no issue is
  filed**, consistent with this PR's own thesis and the standing DO-NOT.
- **No mass-close.** The backfill classifies; it never closes. The 330
  zero-comment issues include legitimate ones — one sat untouched for six weeks
  and was entirely valid.
- **No change to `[mandates-filing]`.** Not added, not weakened, not dropped.
- **No change to net-issue-flow's counting.** The gate keeps counting machinery
  filings; only visibility is separated.
- **No GDPR gate invocation.** No regulated-data surface is touched: no schema,
  migration, auth flow, API route, or `.sql` file; no LLM processing of
  operator-session data beyond what `/drain` already does under its existing
  disclosure; no new artifact-distribution surface.
- **No Encryption Posture section.** No persistent store and no new
  cross-component connection is introduced; no `.tf` store resource, migration,
  cloud-init, or compose file is added.

## Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| The sweeper closes a legitimate issue after the label widening | **Highest** | Four independent never-touch guards, each with its own RED mutation row; fail-toward-skip on indeterminate authorship; dry-run before the first live sweep; the `meta/machinery` population is brand-new and fully reviewed at first sweep; weekly reopen-count reporting as the detection signal. |
| The blocking filing gate over-denies and stalls autonomous runs | High | Three exits, one of which (`meta/machinery`) is always available and cheap to comply with honestly; must-PASS rows 10–12 pin the non-denial cases; a purpose-named, incident-emitting escape hatch; the deny count is reported weekly so over-denial is visible within one cycle. |
| The gate is gamed — agents write a vacuous `User-Impact:` to get past it | Medium | Acknowledged in the ADR as a shape check, not a semantic one. The design bet is that the `meta/machinery` exit makes honest compliance cheaper than gaming, and the `Fix-Size:` numeric assertion is not gameable by adjective. The weekly rate measurement is the backstop: if the rate does not fall, the gate is being gamed and that is visible in four weeks. |
| The `AGENTS.rules.md` edit cannot land against a 1-byte budget | Medium | The edit is designed byte-**negative** by construction (prose moves into the hook per `cq-agents-md-tier-gate`), and AC10 asserts strictly-lower rather than not-higher. |
| ADR-216's ordinal collides mid-pipeline | Medium | Verified across all 86 `origin/*` refs, not `origin/main` alone; re-verified at ship; a renumber sweeps `plans/` and `specs/` in the same edit. |
| The new drain workflow is denied by the cron-prefer-Inngest hook | Medium | The workflow carries `workflow_dispatch: {}` only; scheduling lives in Inngest. AC16 asserts both the absent `cron:` key and the absent override marker. |
| The measurement itself grows the backlog | Medium | Find-or-update exactly one standing issue; AC19 asserts a second invocation creates zero. |
| The measurement script authenticates locally but never runs in the sandbox | Medium | `GH_TOKEN` declared explicitly and forwarded through any `env -i` allowlist; the documented silent-forever-transient failure mode. |
| Widening a battle-tested closer increases its blast radius | Medium | Function id, Sentry slug, and manifest entry stay byte-identical (AC15) so monitoring continuity is preserved; the widening is a target-set parameterization inside one code path rather than a fork. |
| `stateReason` does not behave as assumed, breaking the rate exclusion | Low-Medium | Phase 3.4 verifies it empirically on a dry-run candidate before the measurement depends on it, rather than inferring from documentation. |

## Test Scenarios

Beyond the three mutation matrices (which are the primary test surface):

1. A `/work`-style filing with a genuine user consequence, correct measured
   fix-size above the inline threshold → allowed, issue created.
2. The same filing with `Fix-Size: 19 lines / 1 file` → refused, message names the
   inline threshold.
3. A review-agent machinery finding filed with `--label meta/machinery` → allowed,
   and the issue does not appear in the operator digest's §4 output.
4. A `wg-block-pr-ready-on-undeferred-operator-steps` mandated filing carrying
   `Mandated-By:` → allowed by the hook, and still adjudicated by
   `net-issue-flow.sh` at the merge boundary; the two gates agree.
5. Dry-run sweep over the freshly-backfilled `meta/machinery` set → candidate list
   reviewed; every never-touch class appears as a skip with its reason.
6. Weekly drain closing 19 → run fails; closing 20 → run passes.
7. Measurement over a synthetic window containing one override, one fail-open, and
   a mix of real and expiry closes → all four appear as distinct counts, and the
   filing rate excludes the expiry closes.
8. Second consecutive measurement invocation → the standing issue is updated, not
   duplicated.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| **A separate repo for machinery findings** | **Rejected.** Breaks the `Closes #N` link from the closing PR, and breaks `net-issue-flow.sh`'s own counting — its `FILED` arm matches same-repo issues referencing the PR, so cross-repo filings become invisible to the gate rather than merely re-scoped. Recorded in ADR-216. |
| **A knowledge-base rolling audit log instead of issues** | **Rejected.** Loses close-on-merge entirely, needs new tooling to write and query, and has no state model — an entry can be appended but never resolved. Recorded in ADR-216. |
| **A stricter per-PR net-zero gate (e.g. block at NET ≥ 0)** | **Rejected.** Still a merge-boundary gate. Perfectly enforced, per-PR net-zero holds the backlog at 1,455 forever; tightening it to net-negative per-PR would block ordinary work that legitimately files one mandated tracker. The cadence-level closing budget achieves net-negative without making every PR carry the burden. |
| **A filing-time checklist in prose (a skill or rule instruction)** | **Rejected** by the operator's pushback and by the 2026-07-20 learning: an advisory gate in an autonomous pipeline is inert. A checklist an agent can narrate past is worth nothing. |
| **A second AGENTS rule for the filing gate** | **Rejected.** It would disagree with `wg-defer-only-after-inline-triage` — the exact "two gates that disagree" failure the operator named — and cannot land against `B_ALWAYS=45999/46000`. |
| **A new expiry-sweeper workflow and script** | **Rejected (Cut List C1).** `cron-stale-deferred-scope-outs.ts` already implements the entire behaviour; a second sweeper would be a duplicate closer with its own replay-safety and idempotency bugs to rediscover. |
| **Auto-expiring any zero-comment issue** | **Rejected by the operator explicitly.** Scope stays `meta/machinery`-labelled only. The human-triage guard is a second net inside that scope, not a widening of it. |
| **Excluding `meta/machinery` from `net-issue-flow.sh`** | **Rejected.** It would remove the only rate gate on the machinery ledger, letting it grow unbounded. Visibility is separated; accountability is not. |
| **A GHA `scheduled-*.yml` with a `cron:` block for the weekly drain** | **Rejected.** Denied by `new-scheduled-cron-prefer-inngest.sh` per ADR-033. Reaching for the hook's override hatch would reproduce exactly the reflexive-override pathology ADR-155 documents. |
