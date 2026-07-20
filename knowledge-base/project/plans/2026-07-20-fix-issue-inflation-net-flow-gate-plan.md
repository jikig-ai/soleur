---
title: "fix(workflow): make the net-issue-flow gate blocking, raise the cost-of-filing threshold, and repair the action-required delivery channel"
type: fix
date: 2026-07-20
branch: feat-one-shot-6769-issue-inflation-net-flow-gate
lane: cross-domain
issue_ref: "Closes #6769"
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix(workflow): make the net-issue-flow gate blocking, raise the cost-of-filing threshold, and repair the action-required delivery channel

> Spec lacks valid `lane:` (no `spec.md` for this branch) — defaulted to `cross-domain` (TR2 fail-closed).
> `Closes #6769` — this PR lands the mechanism AND the diagnosis that issue asked for.
> **This PR files nothing.** It must itself pass the `NET > 0` gate it installs.

## Overview

The self-checking apparatus is the dominant issue *source*. Filing is free; closing is expensive.
The queue is at 1,024 open and growing +20.6/day. This PR installs the one control that can flatten
it — a **blocking** per-PR net-issue-flow gate — plus three supporting changes and two operator
decision artifacts.

The numbers are **given, freshly re-measured 2026-07-20, and are not re-derived here**:

| Metric | Prior 23d | Last 7d |
|---|---|---|
| Issues created | 435 | 269 |
| Issues closed | 269 | 125 |
| Merged PRs | 357 | 132 |
| Filed-per-PR | 1.22 | **2.04** |
| Net-per-PR | +0.46 | **+1.09** |
| Queue growth | +7.2/day | **+20.6/day** |

**Corrected target: filed-per-PR ≤ 0.95.** At 132 PRs/wk and 125 closes/wk, flat queue requires
filed-per-PR ≤ 0.95. The previously circulated 3.5 target is inert — it was already satisfied at 1.22
throughout the entire period the queue grew to 1,024, so it cannot detect the problem.

### The two findings that reshaped this plan

Both were measured this session and both **change the design** relative to the brief.

**Finding 1 — the existing FILED query covers ~8% of filings, so a naive blocking flip produces
another structurally-unfailable gate.**
`ship/SKILL.md`'s current detection filters `gh issue list --label deferred-scope-out`. Measured label
composition of the 270 issues created since 2026-07-13:

| n | label |
|---|---|
| 107 | `type/chore` |
| 70 | `type/bug` |
| **22** | **`deferred-scope-out`** |
| 21 | `action-required` |
| 19 | `follow-through` |
| 13 | `decision-challenge` |

Flipping `NET > 0` to blocking **against the `deferred-scope-out` filter alone** would gate on 22/270
≈ 8% of real filings. A PR could file five `type/chore` issues and compute `NET = 0`. That is precisely
the defect class this repo keeps re-learning (secret-scan #6727; still-open #6766 "infra-validation
cannot fail on main"; still-open #6774 "preflight Check 10 cannot verify run-triggered emitters").
**The gate must drop the label filter and count every PR-cycle-attributable filing.**

**Finding 2 — `action-required` was never a broken label. The delivery channel is dark.**
This is the cheapest-check-first result that #6769 explicitly asked for, and it inverts the deliverable.
The operator-digest pipeline is **fully functional end-to-end**:

- Section 4's query is correct (`operator-digest/SKILL.md:160-171`, List API not `--search`, per the
  #3403 cross-repo trap).
- The workflow is **active** in the private `jikig-ai/operator-digest` repo (two-repo split per
  ADR-057), schedule `0 13 * * 5`.
- It **runs and succeeds**: 7 of 8 runs succeeded (only 2026-06-26 failed at `Synthesize digest`).
- It **posts**: digest issues #1–#7 exist, `Digest: 2026-W24` … `2026-W29`.
- Section 4 **has surfaced the backlog for at least 5 consecutive weeks** — digest #7 names #4023,
  #2970, #2969, #2146, #555, #553 explicitly as "sitting unpublished for weeks or months."

The terminal fact:

```
gh api repos/jikig-ai/operator-digest/subscribers --jq 'length'  →  0
```

**Zero subscribers.** Issues are authored by the `github-actions` bot, so the operator is never
auto-subscribed as author or participant. GitHub generates no notification. All 7 digests are OPEN
with `comments=0`, `assignees=0` — never touched.

**Design consequence:** building an auto-nag or SLA mechanism *first* would have posted the nag into
the same dead channel. The fix is **delivery + ranking**, not a new mechanism. The staleness contract
is still worth having, but it is second in order, not first.

**Corroborating evidence the repo already knows this** — two workflows on the default branch hold
contradictory beliefs:

- `.github/workflows/scheduled-cron-artifact-age.yml:102-108` refuses the label: *"DELIBERATELY NOT
  `action-required`. That queue is 28 items deep … a **measured 0% response rate** … an append, not
  an escalation."*
- `.github/workflows/scheduled-inngest-health.yml:853-856` asserts the opposite: the label is
  *"load-bearing, not decoration."*

The artifact-age workflow is empirically right. This PR reconciles the contradiction.

### Honest arithmetic on what the gate can and cannot reach

Measured authorship of the same 270 issues:

| n | author | governable by a per-PR gate? |
|---|---|---|
| 190 | `deruelle` (agent pipeline under operator token) | **yes** |
| 40 | `app/soleur-ai` | no |
| 39 | `app/github-actions` (crons) | no |
| 1 | `Elvalio` | n/a |

~29% of filings (~79/week) are cron/bot-authored and **structurally out of reach of a per-PR gate**.
Against 125 closes/week the residual is still net-negative, so a flat queue remains achievable — but
the plan must not claim the gate alone gets to zero growth. The gate governs the 190/week majority.
The ADR in Deliverable 5 is where the cron-filing half gets addressed, and it is a **policy question
for the operator, not an engineering fix.**

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "`ship/SKILL.md` ~line 477 … already computes CLOSING/FILED/NET correctly" | Computes them correctly **for `deferred-scope-out` only** (~8% of filings) | Widen FILED to all labels; this is the difference between a real gate and an unfailable one |
| Threshold change is at `review/SKILL.md:507` | The `≤30 lines AND ≤2 files` threshold is stated at **9 sites across 5 files** | Sweep all 9 (enumerated in Phase 2); a partial edit leaves contradictory thresholds across skills |
| "is operator-digest Section 4 actually running?" | **Yes** — active cron, 7/8 successful runs, correct query, has surfaced the backlog ≥5 weeks | Root cause is 0 subscribers, not the harvest. Fix delivery + ranking first |
| Issue #6769 | OPEN, `type/chore`, `domain/engineering`, created 2026-07-20 | `Closes #6769` |
| "secret-scan structurally-unfailable fix merged 2026-07-19" | Commit `7f84318dc`, merged **2026-07-20** (2026-07-19 is the plan file's date) | Cite the commit; copy its test discipline |
| "two still-open instances of the same class" | Confirmed: **#6766**, **#6774** | Cited as precedent in the ADR and the test rationale |
| Gate override marker convention | Settled convention exists; `<!-- gate-override: <name> -->` matched with `grep -qF`, always paired with a `SOLEUR_SKIP_*` env var | Follow it exactly |
| ADR ordinal | Next free is **ADR-130** (highest existing ADR-129) | Provisional — `/ship` re-verifies against `origin/main` |
| ADR `status: proposed` | **No existing ADR uses `proposed`** — all are `accepted` | Phase 5 must confirm no validator rejects the value before relying on it |

## User-Brand Impact

**If this lands broken, the user experiences:** a blocking gate that cannot be satisfied — every
`gh pr ready` denied on a miscounted NET, halting all shipping. This is the highest-blast-radius
failure mode in the PR and is why the fail-open path (Phase 1) and the `SOLEUR_SKIP_*` escape are
mandatory, not optional.

**If this leaks, the user's data/workflow/money is exposed via:** no new data surface. The gate reads
public-repo issue metadata via the existing `gh` auth. No PII, no secrets, no new vendor.

**Brand-survival threshold:** `none` — internal workflow tooling; no user-facing product surface, no
regulated-data path. `threshold: none, reason: the change touches only agent-pipeline gates, hooks and
skill prose; it reads issue metadata already visible to the operator and writes no user data.`

## Deliverables

### D1 — Make the net-issue-flow gate blocking (highest leverage)

**Operator decision already made, not relitigated:** block PR-ready when **`NET > 0`**. Every PR must
close at least as many issues as it files. Not `NET > +1`: at 132 PRs/week a +1 allowance authorizes
+132/week against current growth of +144/week — an ~8% cut that would then declare victory. `NET > 0`
is the only threshold that flattens the queue.

**What this gate does and does not do.** `NET > 0` **stops the bleeding; it does not drain.** A PR
closing 1 and filing 1 passes forever, so the steady state it enforces is a *flat* queue at ~1,024 —
not a shrinking one. Draining requires closing more than is filed, which is a separate campaign
(`/soleur:drain-labeled-backlog`). Stating this plainly matters: the failure mode of this whole class
of work is declaring victory on a metric that was never the goal, which is exactly what the inert 3.5
filed-per-PR target did.

**Escape hatch retained, made deliberate:** `<!-- gate-override: net-issue-flow -->` in the PR body
plus a one-line justification per filed issue. Architectural-pivot deferrals can legitimately be
net-positive. Plus `SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1` as the emergency escape, matching every sibling
gate.

Three artifacts, because prose in a SKILL.md is skippable by construction:

1. **`plugins/soleur/skills/ship/scripts/net-issue-flow.sh`** — executable, testable. Modeled on the
   existing `plugins/soleur/skills/ship/scripts/auto-close-scan.sh` (the repo's precedent for
   extracting ship prose into a script). Computes CLOSING/FILED/NET, prints the display block,
   **exits 1 when `NET > 0` and no override is present**, 0 otherwise.
2. **`.claude/hooks/ship-net-issue-flow-gate.sh`** — PreToolUse hook denying `gh pr ready` /
   `gh pr merge`. Structure copied from
   `.claude/hooks/ship-soak-followthrough-gate.sh`: read stdin JSON → `strip_command_bodies` →
   command regex → `cd "$WORK_DIR"` → env override → PR-body read (fail-open on empty) → override
   marker → `emit_incident … deny` → `jq -n` `permissionDecision: "deny"` → **`exit 0`** (the deny
   travels in the JSON, never the exit code).
**Honest reachability — what the hook does and does not cover.** An earlier draft called the hook
"the layer an agent cannot skip." That is false, and stating it falsely is the same self-congratulation
this PR is meant to end. Plan-review enumerated three merge paths the copied regex misses and two the
hook cannot reach at all:

| Surface | Reached? | Note |
|---|---|---|
| `gh pr ready` | yes | |
| `gh pr merge --auto` | yes | |
| `gh pr merge <N> --squash` | **only after widening** the regex to `gh\s+pr\s+(ready\|merge)` — `main` has an active merge queue (`drain-prs/SKILL.md:74,77`), so plain `--squash` lands without `--auto` ever appearing | fix in 2.3 |
| `gh pr merge <N> --squash --admin` | **only after widening** — the documented BEHIND-exhausted escape (`ship/SKILL.md:1690`) | fix in 2.3 |
| `/drain-prs` bulk merges | after widening, yes (it shells `gh pr merge`) | |
| CI-driven merge (`cla-evidence-timestamp.yml:298`) | **no** — no PreToolUse hook runs in GitHub Actions | structural |
| GitHub native auto-merge (server-side) | **no** — a PR marked ready in a prior session lands with no tool call to intercept | structural |

The two structural gaps are outside a PreToolUse hook **by construction**. Closing them would require a
**required status check** on `main`, not a hook. That is deliberately out of scope here — it is a new
CI gate, and proposing one inside the PR that drafts a gate-moratorium ADR would be tone-deaf. The ADR
is the right place to raise it. **The plan states the gap rather than papering over it.**

3. **`plugins/soleur/skills/ship/SKILL.md`** — section retitled `### Net-Issue-Flow Gate (blocking)`,
   prose replaced by an invocation of the script. Lines ~481, ~543, ~549 (the "advisory", "does NOT
   block", "Why advisory (not blocking)" statements) all removed — a stale "advisory" sentence beside
   a blocking gate is exactly the drift that makes gates unfailable.

**The FILED query change (load-bearing — see Finding 1).** Plan-review measured three further defects
in the naive widening; all are folded in below. **Every one of them biases the gate toward passing** —
which is the unfailable-gate class this PR exists to eliminate, so they are not optional polish.

```diff
- FILED=$(gh issue list \
-   --label deferred-scope-out \
-   --state open \
-   --search "created:>=${PR_CREATED_AT}" \
+ FILED=$(gh issue list \
+   --state all \
+   --limit 500 \
+   --search "created:>=${PR_CREATED_AT_FULL_ISO}" \
```

with the body filter changed from the keyword form to a numeric-boundary bare reference:

```diff
- test("(^|\\s)(Ref|Closes|Fixes) #<PR>(\\s|$|[^0-9])")
+ test("(^|[^0-9A-Za-z])#<PR>([^0-9]|$)")
```

| # | Defect | Measured | Fix |
|---|---|---|---|
| **a** | **`gh issue list` defaults to 30 results.** No `--limit` today. Harmless at ~22 `deferred-scope-out`/week; fatal at 271/week | `--search "created:>=2026-07-13"` → **30**; with `--limit 500` → **271**. A 3-day PR has 81 candidates. gh returns newest-first, so the cap drops the *oldest* — exactly the issues filed early in the PR cycle | `--limit 500`. **A PR open >~18h currently cannot see its own early filings.** Deterministic, silent, always biased toward passing |
| **b** | **`(Ref\|Closes\|Fixes) #N` matches ~40% of filings, not ~100%** | Of 191 `deruelle`-authored issues in-window, 77 (40%) match the keyword form; 93 use `see/from/via/per/PR #`. Per-PR: #6748 strict=0 / any-mention=2; #6727 strict=0 / any-mention=2 — both evade entirely | Match a bare `#<PR>` with a numeric boundary. The evading bodies are ordinary agent prose (`PR #6748 was deliberately scoped…`), not evasion — so a keyword filter is simply the wrong instrument |
| **c** | **`cut -c1-10` truncates `PR_CREATED_AT` to a date**, including everything created earlier that same day, before the PR existed | ~3 spurious candidates/day under the old filter; **~39/day** widened | Pass the full ISO timestamp (`created:>=2026-07-20T14:32:00Z`) — GitHub search accepts it |

**On over-counting.** Fix (b) trades precision for recall, and that is the correct direction here: the
display block enumerates the exact issue numbers behind the verdict, and the override exists. A gate
that over-counts is argued with; a gate that under-counts is invisible.

**This inverts T11.** An earlier draft asserted `see #N` must *not* be counted. It must be. The
near-miss fixture now tests the numeric boundary (`#67491` must not match `#6749`), not the keyword.

### D2 — Raise the cost-of-filing auto-flip threshold, and instrument it

`≤30 lines AND ≤2 files` → **`≤100 lines AND ≤4 files`**.

The brief names one site. There are many more, across five files, and they must move together — a
partial edit leaves `review` auto-flipping at 100 lines while `work` and `compound` still file at 31.
**The line list below is a starting map, not the enumerator** — AC8's grep is the enumerator (an
earlier draft asserted a specific count next to a grep-based check, which is a second source of truth
that goes stale; plan-review P3.3):

| File | Lines |
|---|---|
| `plugins/soleur/skills/review/SKILL.md` | 496, 500, 507, 509, 513, 532, 740, 750, 1055 |
| `plugins/soleur/skills/review/workflows/review.workflow.js` | 279 |
| `plugins/soleur/skills/ship/SKILL.md` | 539 |
| `plugins/soleur/skills/work/SKILL.md` | 887 |
| `plugins/soleur/skills/compound/SKILL.md` | 79 |

`compound/SKILL.md:79` explicitly documents itself as mirroring `review/SKILL.md` §5 — it drifts
silently if left behind.

**Instrumentation is REQUIRED, not optional.** It is what makes the *next* threshold change measurable
instead of another guess. The repo already has the substrate: `.claude/hooks/lib/incidents.sh`
`emit_incident rule_id event prefix cmd hook_event kind` → flock-guarded JSONL at
`.claude/.rule-incidents.jsonl`, with schema versioning and log rotation already built.

```bash
emit_incident cost-of-filing "$DISPOSITION" "<finding-summary>" "" PostToolUse cost_of_filing
# DISPOSITION ∈ { flip, file }
```

**The emission site is `plugins/soleur/skills/review/workflows/review.workflow.js`, NOT SKILL.md
prose.** Plan-review caught this and it is the single sharpest finding of the pass: a plan whose
central argument is *"prose in a SKILL.md is skippable by construction"* cannot then ship its own
telemetry as a SKILL.md instruction. That would be honor-system instrumentation defended by an
argument against honor systems. The workflow file executes; the prose does not.

### D3 — Fix the `action-required` sink (#6769)

Ordered by the diagnosis, cheapest first. **The delivery fix comes before any new mechanism**, because
a nag posted into a 0-subscriber repo is not an escalation.

1. **Make the digest notify — via issue assignment, not watch subscription.**

   The obvious fix is subscribing the operator to the repo. **Measured this session: it is not
   automatable.**

   ```
   $ gh api repos/jikig-ai/operator-digest/subscription
   gh: This API operation needs the "notifications" scope.
   $ gh auth status | grep -i scopes
   Token scopes: 'admin:org', 'admin:public_key', 'gist', 'repo', 'workflow', 'write:packages'
   ```

   `gh auth refresh -s notifications` is an interactive browser flow — a genuine operator step, and
   an earlier draft of this plan wrongly claimed "no operator step" (it would have tripped
   `wg-block-pr-ready-on-undeferred-operator-steps` at ship time).

   **The better fix needs no new scope at all: assign the issue.** GitHub notifies an assignee
   regardless of watch state, and `--assignee` needs only `repo`, which the workflow token already
   has. The diagnosis corroborates the gap directly — all 7 digests have `assignees=0`.

   One-line change at `operator-digest/assets/operator-digest.workflow.yml:94-96`:

   ```diff
     gh issue create -R jikig-ai/operator-digest \
       --title "Digest: ${ISO_WEEK}" \
   +   --assignee "${OPERATOR_GH_LOGIN}" \
       --body-file "$DIGEST"
   ```

   Applied to **both** arms (the withheld-notice arm at :98 too — a withheld digest is exactly when
   the operator most needs to know). This is fully automatable, in-session, no operator step.

   The watch subscription remains a nice-to-have belt-and-braces. It is **explicitly deferred** as a
   one-time optional operator step, not claimed as automated.
2. **Add age and ranking to Section 4.** Currently `--json title,url` with no age field, no sort, no
   cap, no escalation band — so a 130-day blocker renders as one flat bullet among 29, visually
   identical to a 3-day `decision-challenge`. Change to `--json title,url,createdAt,labels`, sort
   descending by age, render `(NNN days old)`, and band: **>90d = escalated**, 30–90d = aging,
   <30d = current. Age becomes the signal, which is what #6769 asked for.
3. **Staleness contract — the SLA arm, not the auto-close arm.** The brief offered three options
   ("auto-nag, an SLA, or auto-close-with-reason"). **Choosing the SLA.** `action-required` means
   *acted on within 90 days or explicitly renewed*; items past 90d render in the escalated band with
   their age. Age is itself the signal, which is what #6769 asked for.

   **Deliberately NOT auto-closing.** Plan-review argued to cut the staleness work entirely; that goes
   further than the brief allows, but its reasoning against *auto-close specifically* holds: an
   auto-closer is new issue-mutating apparatus, inside a PR whose thesis is that apparatus is the
   problem, with a real failure mode (silently closing a live blocker) and a flattering side effect
   (auto-closing ~29 items is a one-time queue drop with no behavior change behind it). The SLA arm
   gets the same signal with none of that. Revisit auto-close only if the soak shows the items still
   sit untouched *after* delivery demonstrably works.
4. **~~Reconcile the two contradictory workflow comments~~ — CUT.** Editing two YAML *comments* has
   zero behavioral effect and is scope creep on a repo with 1,024 open issues (plan-review P2.4). The
   contradiction becomes self-resolving once delivery works; revisit if it misleads someone.
5. **8 of 29 open items are `decision-challenge:`** — informational by design (per `plan/SKILL.md:42`,
   `work/SKILL.md:159`), diluting the queue. Exclude `decision-challenge` from Section 4's
   action-needed harvest and render it in its own short "decisions awaiting your call" line.

**Recorded decision (required by the verification contract):** `action-required` is **retained, not
retired.** The measured 0% resolution rate was a delivery failure, not a label failure. The label now
carries a 90-day staleness contract and an age-ranked digest surface.

### D4 — Budget meta-work (PROPOSAL ONLY — operator sign-off required)

**Proposed** AGENTS.md rule, for operator decision. **Not imposed by this PR. No AGENTS.md edit lands
in this PR.**

> A tooling/meta issue may be filed only with a named drain window. Otherwise, accept the defect
> knowingly and do not file. An unfiled known defect and a filed-and-ignored one are equivalent in
> effect — but the second consumes queue attention and creates false confidence that it is tracked.

**Delivery mechanism — and a trap this plan initially walked into.** The obvious vehicle is
`specs/<branch>/decision-challenges.md`, which `ship` Phase 6 renders into the PR body. But reading
`ship/SKILL.md:1299` shows that mechanism *also* runs
`gh issue create --label action-required --label decision-challenge`. **Using it would make this PR
file an issue, trip its own `NET > 0` gate, and require an override on the very PR that installs the
gate.** Self-defeating in the most literal way.

**Therefore D4's proposal lands in the ADR body instead** (see D5) — ADR-130 carries *two* proposed
policies, this one and the moratorium. Both are "operator decides", both land at `status: proposed`,
zero issues filed. One artifact, one review, one decision point.

**Measured aside, worth the operator's attention:** the decision-challenge mechanism filed **13 issues
in the last 7 days** — all into `action-required`, the queue with the measured 0% resolution rate. It
is a non-trivial share of the pipeline's own filing volume feeding a channel that was dark. D3 fixes
the channel; whether that mechanism should file issues *at all* once delivery works is a question for
the ADR, not for this PR's scope.

### D5 — Gate moratorium ADR (DRAFT ONLY — do not decide, do not impose)

`knowledge-base/engineering/architecture/decisions/ADR-130-gate-moratorium.md`, **`status: proposed`**.

This ADR carries **two** proposed policies for one operator decision session: the meta-work drain-window
rule from D4, and the gate moratorium below. Neither is decided here.

This is a policy call about how the system should behave, not an engineering fix. **An agent must not
settle it alone.** Both sides go to the operator:

**For a moratorium.** Every gate, linter, probe and cron is software whose job is finding defects and
which has defects of its own. The apparatus's own maintenance is now the main workload: 29% of filings
are bot/cron-authored, and the three known unfailable-gate instances (#6727 fixed, #6766 and #6774
still open) are all gate-maintenance work, not product work. Each new gate is a permanent
issue-generator with no drain window.

**Against a moratorium.** The gate in D1 of *this very PR* is a new gate, and it is the single highest-
leverage control available — a blanket moratorium would have forbidden it. Gates that *close* the loop
(this one reduces filings) are categorically different from gates that *detect* (which file). A crude
ban cannot tell them apart and would freeze the one class that helps. Also: the still-open unfailable
gates argue for a **quality** bar on new gates (must ship with a failing-path test), not a **quantity**
ban.

**A synthesis the operator may prefer:** rather than a time-boxed ban, require every new gate to ship
with (a) a test that exercises its failing path, and (b) a named owner and drain window for the issues
it will generate. That is a quality gate on gates. The ADR presents all three options and **decides
none**. Landing at `status: proposed` is the point.

## Implementation Phases

Phase order is load-bearing: the contract-defining script (Phase 1) must precede its consumers
(Phases 2–3), or the hook and the SKILL.md invocation are dead code at their phase boundary.

### Phase 0 — Preconditions (verify, do not assume)

- [ ] 0.1 Confirm `plugins/soleur/skills/ship/scripts/auto-close-scan.sh` exists and read its header
      (output contract + exit policy) — it is the shape being copied.
- [ ] 0.2 Read `.claude/hooks/ship-soak-followthrough-gate.sh` end to end. Confirm the deny shape is
      `jq -n` JSON + `exit 0`, **not** a non-zero exit.
- [ ] 0.3 Confirm `plugins/soleur/test/*.test.sh` is auto-globbed by `scripts/test-all.sh` (it is, at
      line ~316) and that `scripts/*.test.sh` is **not** — an unregistered suite is an orphan that
      never gates.
- [ ] 0.4 Read `plugins/soleur/test/gitleaks-merge-commit.test.sh` header — the #6727 mutation-proof
      discipline this PR must copy.
- [ ] 0.5 Confirm `emit_incident`'s 6th positional arg (`kind`) accepts an arbitrary value and no
      consumer rejects unknown kinds.
- [ ] 0.6 Confirm no validator rejects ADR `status: proposed` (no existing ADR uses it). If one does,
      the ADR uses the nearest accepted-by-validator value and states "proposed" in the body.
- [ ] 0.7 Re-verify next free ADR ordinal against `origin/main` (currently ADR-130, provisional).

### Phase 1 — The gate script (contract-defining; ships first)

- [ ] 1.1 **RED:** write `plugins/soleur/test/net-issue-flow.test.sh` first. Per `cq-write-failing-tests-before`.
- [ ] 1.2 Create `plugins/soleur/skills/ship/scripts/net-issue-flow.sh`. `set -uo pipefail`,
      `export LC_ALL=C`, header documenting the stdout contract and exit-code policy.
- [ ] 1.3 CLOSING extraction: unchanged regex `(close[sd]?|fix(e[sd])?|resolve[sd]?) #[0-9]+`, `sort -u`.
- [ ] 1.4 FILED — all four changes together (any one omitted re-opens a pass-biased hole):
      (a) **drop `--label deferred-scope-out`**; (b) `--state open` → `--state all`;
      (c) **add `--limit 500`** (default is 30 — the single most dangerous defect found in review);
      (d) full ISO `PR_CREATED_AT`, **no `cut -c1-10`**.
- [ ] 1.5 Body filter: numeric-boundary bare reference `(^|[^0-9A-Za-z])#<PR>([^0-9]|$)`, **not** the
      `(Ref|Closes|Fixes)` keyword form (40% coverage, measured).
- [ ] 1.6 Override: `grep -qF '<!-- gate-override: net-issue-flow -->'` on the PR body; plus
      `SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1`.
- [ ] 1.7 Exit `1` when `NET > 0` and no override; `0` otherwise. **Fail-open** on an unreadable PR
      body or a `gh` API error — a gate that blocks on its own transport failure halts all shipping.
- [ ] 1.8 **Fail-opens must be telemetered**, not just printed: `emit_incident net-issue-flow transient …`
      on every fail-open path. Overrides are already logged; without this the gate can sit silently
      open for weeks with clean telemetry. Add one retry with backoff before failing open —
      `--search` hits the Search API (**30 req/min**, vs 5,000/hr REST), so the gate is most likely to
      fail open under exactly the high-throughput conditions it exists to govern.
- [ ] 1.9 Display block enumerates the actual issue numbers behind CLOSING and FILED.
- [ ] 1.10 **GREEN.** Run `bash plugins/soleur/test/net-issue-flow.test.sh`.

### Phase 2 — The PreToolUse hook (the unskippable layer)

- [ ] 2.1 **RED:** `.claude/hooks/ship-net-issue-flow-gate.test.sh`, using the
      `ship-unpushed-commits-gate.test.sh` `assert_deny` / `assert_pass` harness.
- [ ] 2.2 Create `.claude/hooks/ship-net-issue-flow-gate.sh`, delegating computation to the Phase 1
      script (no re-implementation — a hand-mirrored copy is the #6727 antipattern verbatim).
- [ ] 2.3 Command regex **widened to `gh\s+pr\s+(ready|merge)`** — not the `merge\s+.*--auto` form
      copied from the soak gate, which misses `--squash` (merge-queue path) and `--admin`.
      `strip_command_bodies`-guarded.
- [ ] 2.4 Resolve the script path via
      `PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"` —
      **not** the payload's `.cwd`. A `gh pr ready` issued from `apps/web-platform/` would resolve
      `$WORK_DIR/plugins/...` to nothing and fail open silently. Pattern from
      `.claude/hooks/git-commit-secret-scan.sh:35`.
- [ ] 2.5 Wrap the delegated call in `timeout 8` (precedent: `.claude/hooks/pre-merge-auto-close-scan.sh`,
      which makes the same kind of network call).
- [ ] 2.6 Deny via `emit_incident` + `jq -n` `permissionDecision: "deny"` + `exit 0`. Reason string
      offers all three remedies: close an issue, fix inline instead of filing, or apply the override.
- [ ] 2.7 Document in `.claude/hooks/README.md` (the override convention is catalogued at ~line 353).
- [ ] 2.8 **GREEN.**

> **Registration is deliberately NOT in this phase.** See Phase 8.6.

### Phase 3 — SKILL.md prose (consumer; ships after the contract)

- [ ] 3.1 `ship/SKILL.md`: retitle `### Net-Issue-Flow Surfacing (advisory)` →
      `### Net-Issue-Flow Gate (blocking)`.
- [ ] 3.2 Replace the inline bash with an invocation of `[net-issue-flow.sh](./scripts/net-issue-flow.sh)`
      (markdown link form — bare-backtick refs are lint-flagged per `plugins/soleur/AGENTS.md`).
- [ ] 3.3 Delete every "advisory" / "does NOT block" statement (~481, ~543, ~549) including the
      trailing **"Why advisory (not blocking)"** paragraph.
- [ ] 3.4 Document the override marker and the `SOLEUR_SKIP_*` env var.

### Phase 4 — Cost-of-filing threshold + instrumentation

- [ ] 4.1 Sweep all **9 sites** in the D2 table: `≤30` → `≤100`, `≤2 files` → `≤4 files`,
      `>30 lines OR >2 files` → `>100 lines OR >4 files`.
- [ ] 4.2 Update the prose rationale at `review/SKILL.md:500` — the ~30min-bookkeeping vs ~5min-edit
      arithmetic changes at a 100-line fix and must be restated honestly, not left stale.
- [ ] 4.3 Add the `emit_incident … cost_of_filing` instrumentation step to `review/SKILL.md`'s
      disposition flow, emitting `flip` or `file` per finding.
- [ ] 4.4 Verify: `git grep -nE '≤ ?30|30 lines|≤ ?2 files' -- plugins/` returns zero
      cost-of-filing-related hits.

### Phase 5 — action-required sink (#6769)

- [ ] 5.1 Add `--assignee "${OPERATOR_GH_LOGIN}"` to **both** `gh issue create` arms in
      `plugins/soleur/skills/operator-digest/assets/operator-digest.workflow.yml:94-100`. Needs only
      `repo` scope. **Do NOT attempt the watch-subscription API** — the token lacks `notifications`
      (measured; see D3.1).
- [ ] 5.2 `operator-digest/SKILL.md` §4: `--json title,url` → `--json title,url,createdAt,labels`;
      sort by age desc; render `(NNN days old)`; band >90d / 30-90d / <30d. This is the SLA arm of the
      staleness contract — **no auto-close mutation.**
- [ ] 5.3 Exclude `decision-challenge` from the action-needed harvest; render separately (never drop —
      a silent drop would be a second dark channel).
- [ ] 5.4 Record the retain-not-retire decision in the ADR body and the PR body.
- [ ] 5.5 Note the deferred optional operator step (one-time watch subscription) via the repo's
      deferred-operator-step path, so `wg-block-pr-ready-on-undeferred-operator-steps` is satisfied.

### Phase 6 — ADR + proposal artifacts

- [ ] 6.1 Write `ADR-130-gate-moratorium.md`, `status: proposed`, containing the argument, the
      counter-argument, and the synthesis. **Decides nothing.**
- [ ] 6.2 Add the `github -> founder` C4 relationship for digest delivery (see §Architecture Decision).
- [ ] 6.3 Fold the D4 meta-work proposal into ADR-130 as its second proposed policy. **Do NOT write
      `specs/<branch>/decision-challenges.md`** — `ship/SKILL.md:1299` would file an `action-required`
      issue from it and trip this PR's own gate.

### Phase 7 — Follow-through enrollment (mandatory; /ship blocks without it)

The `filed-per-PR ≤ 0.95` target is a post-deploy **soak** criterion, which triggers plan Phase 2.9.1
and is fail-closed at `/ship` Phase 5.5 + the `ship-soak-followthrough-gate.sh` hook.

- [ ] 7.1 `scripts/followthroughs/filed-per-pr-soak-6769.sh`. Exit semantics per the sweeper contract:
      `0` = PASS, `1` = FAIL (still above target), `*` = TRANSIENT. Measures filed-per-PR over a
      trailing 14d window **restricted to PR-attributable filings** — a raw all-issues count would fold
      in the ~29% cron share the gate cannot reach and could never pass.
- [ ] 7.2 Directive on #6769:
      `<!-- soleur:followthrough script=scripts/followthroughs/filed-per-pr-soak-6769.sh earliest=<merge+14d> secrets=GH_TOKEN -->`
      plus the `follow-through` label.
- [ ] 7.3 `GH_TOKEN` is already wired in `scheduled-followthrough-sweeper.yml:56` — no new secret.

### Phase 8 — Mutation evidence (the verification contract)

The work is not done when the gate is asserted to work. It is done when the gate is **seen to fail**.

- [ ] 8.1 Construct a synthetic PR body with `NET = +3` (0 closing, 3 filed).
- [ ] 8.2 Run the gate. **Capture the actual failing output verbatim.**
- [ ] 8.3 Add `<!-- gate-override: net-issue-flow -->`; re-run; capture the passing output.
- [ ] 8.4 Commit both to `knowledge-base/project/specs/<branch>/mutation-evidence.md`, per the repo
      convention established by #6727
      (`specs/feat-one-shot-6721-6723-6724-gitleaks-scan-gaps-ship-signal/mutation-evidence.md`).
- [ ] 8.5 Cite that file in the PR body.
- [ ] 8.6 **ONLY NOW register the hook** in `.claude/settings.json` `hooks.PreToolUse` (matcher
      `Bash`), after `ship-soak-followthrough-gate.sh`. **Operator-visible config change — call it out
      explicitly in the PR body for review.**

      **Why registration is last (plan-review P3-2).** Registering at Phase 2 would mean Phases 3–7 of
      this very PR execute with a live, unproven blocking gate on the shipping path — and this PR must
      itself pass that gate (AC16). A miscount discovered at Phase 8 would leave the PR unable to ship
      the fix for the gate that is blocking it. Everything in Phase 2 lands inert and fully tested;
      only after the failing path is *observed* does the hook go live.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** `bash plugins/soleur/test/net-issue-flow.test.sh` passes, and includes a case asserting
      the gate **exits 1** on a synthetic `NET = +3` body.
- [ ] **AC2** The same suite includes a case asserting the gate **exits 0** when
      `<!-- gate-override: net-issue-flow -->` is present, with NET unchanged at +3.
- [ ] **AC3** The suite includes a case where the filed issue carries **`type/chore`, not
      `deferred-scope-out`**, and the gate still counts it. This is the AC that proves Finding 1 was
      addressed; without it the gate is unfailable in the field.
- [ ] **AC4** The suite **ABORTs (exit 2)** rather than skipping if its `gh` stub is unavailable — per
      #6727, "a fresh mutation proof must never be able to silently skip."
- [ ] **AC5** The threshold assertion is **extracted from the script**, not hand-mirrored in the test.
      Mutation proof: deleting the `NET > 0` comparison from the script must turn the suite red.
- [ ] **AC6** `.claude/hooks/ship-net-issue-flow-gate.test.sh` asserts both `assert_deny` (NET>0) and
      `assert_pass` (NET≤0), and that the hook exits **0** in both cases with the decision in JSON.
- [ ] **AC7** The word "advisory" no longer appears **within the net-issue-flow section**. `git grep -c`
      counts the whole file and `ship/SKILL.md` uses "advisory" elsewhere for unrelated gates, so a
      whole-file count can never reach 0. Use a bounded extraction:
      `awk '/^### Net-Issue-Flow/{f=1;next} /^### /{f=0} f' plugins/soleur/skills/ship/SKILL.md | grep -c advisory`
      returns 0. (Both reviewers flagged the original as unsatisfiable.)
- [ ] **AC8** All 9 threshold sites updated. **The verification regex must cover the hyphenated and
      `>` forms** — a naive `'≤ ?30 lines|≤ ?2 files'` returns 0 while four stale sites survive
      (`review/SKILL.md:500` `≤30-line`, `:532` `>30 lines OR touches >2 files`, `:750` `≤30-line`,
      `:1055` `≤30-line/≤2-file`). Use:
      `git grep -nE '(≤|>) ?30[ -]?line|(≤|>) ?2[ -]?file' -- plugins/soleur/skills/` returns 0.
- [ ] **AC9** The `cost_of_filing` emission lives in
      **`plugins/soleur/skills/review/workflows/review.workflow.js`** (executable), not in SKILL.md
      prose: `git grep -c 'cost_of_filing' plugins/soleur/skills/review/workflows/review.workflow.js`
      ≥ 1. A grep proving prose exists would be honor-system telemetry defended by an argument against
      honor systems.
- [ ] **AC10** Both `gh issue create` arms in `operator-digest.workflow.yml` carry `--assignee`:
      `grep -c -- '--assignee' plugins/soleur/skills/operator-digest/assets/operator-digest.workflow.yml`
      == 2.
- [ ] **AC11** `operator-digest/SKILL.md` §4 query includes `createdAt`, and the section specifies
      age-descending sort with a >90d escalation band.
- [ ] **AC12** `ADR-130-gate-moratorium.md` exists with `status: proposed`, and contains **both** a
      for- and an against- section. An ADR presenting only one side fails this AC.
- [ ] **AC13** ADR-130 also contains the D4 meta-work drain-window proposal, and **no AGENTS.md edit
      appears in the diff** (`git diff --name-only origin/main | grep -c '^AGENTS' == 0`) and **no
      `decision-challenges.md` is created** (`test ! -f specs/<branch>/decision-challenges.md`) —
      creating it would make `ship` file an issue and trip AC16.
- [ ] **AC14** `scripts/followthroughs/filed-per-pr-soak-6769.sh` exists, is executable, and #6769
      carries the `soleur:followthrough` directive + `follow-through` label.
- [ ] **AC15** `specs/<branch>/mutation-evidence.md` contains the **verbatim failing run output** from
      Phase 8.2 — not a description of it.
- [ ] **AC16** **This PR files zero issues.** `NET` for this PR ≤ 0 (it closes #6769). The gate it
      installs passes on itself, with no override marker.
- [ ] **AC17** `bash scripts/test-all.sh` green.

- [ ] **AC20** The gate script passes `--limit 500` and does **not** `cut` `PR_CREATED_AT` to a date:
      `grep -c -- '--limit 500' <script>` ≥ 1 and `grep -c 'cut -c1-10' <script>` == 0. These are the
      two silent pass-biasing defects review measured; both need a standing assertion, not a one-time
      fix.
- [ ] **AC21** Hook registration in `.claude/settings.json` appears in a commit **after** the
      mutation-evidence commit (verifiable in `git log`), per the Phase 8.6 sequencing rationale.

### Post-merge (automated — no operator steps)

- [ ] **AC18** Follow-through sweeper fires `filed-per-pr-soak-6769.sh` at `merge+14d`. **Two
      criteria, both required.** (a) The operator's stated target: filed-per-PR ≤ 0.95 over
      PR-attributable filings. (b) The unfakeable goal check plan-review asked for: total open issue
      count at `merge+14d` ≤ count at merge. Metric (a) alone is scoped to exclude the ~29% cron share
      the gate cannot reach, so it can pass while the queue still grows; metric (b) cannot. Sweeper
      auto-closes #6769 only when both hold.
- [ ] **AC19** Delivery is **observed**, not assumed: the newest `Digest:` issue in
      `jikig-ai/operator-digest` has `assignees` ≥ 1, and by `merge+14d` has non-zero `comments` **or**
      a state change — i.e. a human touched it. An earlier draft verified AC19 by re-asserting AC10,
      which could not detect delivery at all — the exact blind spot that let 7 digests go unread.

## Open Code-Review Overlap

**None.** Queried 61 open `code-review` issues against every planned file path
(`ship/SKILL.md`, `review/SKILL.md`, `operator-digest/SKILL.md`, `work/SKILL.md`, `compound/SKILL.md`,
`.claude/settings.json`) — zero body matches.

## Domain Review

**Domains relevant:** Engineering (CTO lens only).

No Product/UX surface (no `components/**/*.tsx`, no `app/**/page.tsx`, no user-facing route — the
mechanical UI-surface override does not fire). No legal, finance, marketing, sales, support, or
operations implication. This is agent-pipeline tooling.

### Engineering

**Status:** reviewed inline (the two research sweeps in this session *are* the engineering assessment).
**Assessment:** the dominant technical risk is not the threshold value — it is the **denominator**.
Finding 1 shows the brief's literal instruction ("flip the existing computation to blocking") would
have shipped a gate covering 8% of filings while reporting success. The second risk is blast radius: a
blocking gate on `gh pr ready` halts all shipping if it misfires, which is why fail-open on transport
error (Phase 1.6) and the env escape are non-negotiable.

## Observability

```yaml
liveness_signal:
  what: "emit_incident rows with kind=cost_of_filing (flip|file) and rule_id=net-issue-flow (deny)"
  cadence: "per review disposition; per gh pr ready attempt"
  alert_target: ".claude/.rule-incidents.jsonl + the existing weekly rule-metrics aggregator"
  configured_in: ".claude/hooks/lib/incidents.sh (existing substrate, no new infra)"

error_reporting:
  destination: "stderr via headless_or_stderr + the rule-incidents JSONL drop-sentinel path"
  fail_loud: "false — telemetry is fire-and-forget by existing design and must never block the hook; the GATE decision itself is loud (deny JSON)"

failure_modes:
  - mode: "gh API unreachable or PR body unreadable"
    detection: "script exits 0 (fail-open) and prints a TRANSIENT marker to stdout"
    alert_route: "visible in ship output; deliberately does NOT block — a gate that blocks on its own transport failure halts all shipping"
  - mode: "FILED miscount (over-count) blocks a legitimate PR"
    detection: "the display block always prints the enumerated issue numbers behind CLOSING and FILED, so the operator can see exactly which issues drove the verdict"
    alert_route: "override marker + SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1"
  - mode: "gate silently stops firing (the unfailable-gate regression this PR exists to prevent)"
    detection: "AC5 mutation proof in CI: deleting the NET>0 comparison turns the suite red"
    alert_route: "scripts/test-all.sh in CI"
  - mode: "operator-digest subscription silently dropped"
    detection: "AC10 subscribers-count assertion; re-asserted by the follow-through soak script"
    alert_route: "follow-through sweeper comment on #6769"

logs:
  where: ".claude/.rule-incidents.jsonl (flock-guarded, rotated by the existing log-rotation helper)"
  retention: "per existing rotation policy — unchanged by this PR"

discoverability_test:
  command: "bash plugins/soleur/skills/ship/scripts/net-issue-flow.sh --pr <N>; echo \"exit=$?\""
  expected_output: "a CLOSING/FILED/NET display block with the enumerated issue numbers, and exit=1 when NET>0"
```

No `ssh` anywhere in the discoverability path.

## Architecture Decision (ADR/C4)

### ADR

**ADR-130 — Gate moratorium (`status: proposed`).** Ordinal provisional; `/ship` re-verifies the next
free ordinal against `origin/main` before merge and after every Phase 7 sync. **If the ordinal is
renumbered, sweep this plan, `tasks.md`, and AC12 in the same edit** — a renumber that reaches only the
ADR file leaves ACs asserting a nonexistent path.

The ADR also records the D3 decision (`action-required` retained, not retired, now with a 90-day
contract) so the reasoning survives beyond this PR body.

### C4 views

Enumerated against **all three** model files (`model.c4` 542 lines, `views.c4` 62, `spec.c4` 54) — not
a keyword grep, per the completeness mandate:

- **External human actors:** `founder = actor "Founder / Operator"` (model.c4:8) — already modeled.
  No new actor. `emailSender`, `betaContact`, `contributor` — unaffected.
- **External systems:** `github` (model.c4:230, `#external`) — already modeled. The private
  `jikig-ai/operator-digest` repo is a deployment detail *inside* the already-modeled `github` system
  (two-repo split recorded in ADR-057), not a new external system. No new vendor.
- **Containers / data stores:** none added. The new hook lives in the already-modeled
  `hooks = container "Hook Engine"` (model.c4:68); `ship`, `review`, `work`, `compound` are existing
  components (model.c4:111-127).
- **Actor↔surface access relationships:** **one genuine gap found.** There is no `github -> founder`
  edge for digest delivery — grep of all 25 `founder`/`github` relationships (model.c4:318-418) shows
  `founder -> webapp`, `founder -> dashboard`, `contributor -> github`, `github -> webapp`, but no
  digest notification edge. D3 makes that edge load-bearing (it is the channel whose darkness caused
  the 0% resolution rate), so it is an **in-scope task**, not a deferral:

```
github -> founder "Weekly operator digest: a private-repo issue in jikig-ai/operator-digest (ADR-057 two-repo split). Delivery depends on an explicit watch subscription — a 0-subscriber repo generates no notification, which is why 7 digests went unread and the action-required queue measured 0% resolution (#6769)."
```

The relationship is added to `model.c4`. **No `views.c4` `include` line is needed** — both `founder`
and `github` are already included in the `context` view, and LikeC4 renders edges between
already-included elements automatically. After editing, run the C4 validation tests
(`apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts`) — a bad reference fails there,
not at `tsc`.

## Infrastructure (IaC)

**Skipped — no new infrastructure.** No server, systemd unit, cron, vendor account, DNS record, TLS
cert, secret, or firewall rule. Phase 7 reuses `GH_TOKEN`, already wired at
`scheduled-followthrough-sweeper.yml:56`. Phase 5.1 is a single `gh api` call under existing auth,
executed in-session — not an operator step.

## GDPR / Compliance

**Skipped.** No regulated-data surface: no schema, migration, auth flow, API route, or `.sql` file. No
LLM/external-API processing of operator-session data. No new artifact distribution surface. None of
the (a)-(d) expansion triggers fire. The gate reads public issue metadata already visible to the
operator.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Blocking gate halts all shipping on a miscount** — highest blast radius in the PR | Fail-open on transport error (1.6); `SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1`; the display block enumerates the exact issue numbers behind the verdict so a miscount is diagnosable in one read |
| **The widened FILED query over-counts** — an unrelated issue mentioning `Ref #<PR>` inflates NET | Cross-reference regex is anchored (`(^|\s)(Ref|Closes|Fixes) #N(\s|$|[^0-9])`), and `created:>=PR_CREATED_AT` scopes to this PR cycle. AC3's fixture set includes a near-miss body |
| **The override becomes the default** — every PR just adds the marker | The marker requires a one-line justification *per filed issue*; `emit_incident` logs every override, so override frequency is measurable and reviewable. If overrides trend to 100%, the data says so |
| **Raising to ≤100/≤4 imports large unreviewed fixes into review** | The threshold governs *auto-flip to inline*, not review depth; the CONCUR gate still applies above it. Instrumentation (D2) makes the effect measurable rather than a second guess |
| **9-site threshold sweep misses a site** | AC8 greps the whole `plugins/soleur/skills/` tree, not the enumerated list — the grep is the enumerator |
| **ADR-130 ordinal collision** | `/ship`'s ordinal gate re-verifies against `origin/main`; renumber sweeps this plan + tasks.md + AC12 |
| **`status: proposed` rejected by an unknown validator** | Phase 0.6 checks before relying on it |
| **Digest subscription silently reverts** | Re-asserted by the follow-through soak script, not just once at merge |
| **This PR trips its own gate** | AC16. It closes #6769 and files nothing — NET = -1 |

## Plan Review — findings applied, and dissents recorded

Panel: `code-simplicity-reviewer`, `architecture-strategist`. Both returned substantive P1 findings;
**every P1 was applied.** The three that changed the design most:

1. **`gh issue list` defaults to 30** (arch P1-1) — measured 30 vs 271. Silent, deterministic,
   always pass-biased. Would have shipped a gate that a PR open >18h could evade by construction.
2. **The keyword cross-reference filter matches 40% of filings** (arch P1-2) — measured. The plan's own
   Finding 1 logic, carried one step further than the plan had carried it.
3. **`emit_incident` in SKILL.md prose is honor-system telemetry** (simplicity P2.2) — inside a PR
   arguing prose is skippable. Moved to `review.workflow.js`.

Also applied: `--assignee` instead of the unavailable `notifications` scope; AC19 made observational;
auto-close dropped in favour of the SLA arm; Phase 8.6 registration re-sequencing; AC7 bounded
extraction; the widened merge-path regex; `CLAUDE_PROJECT_DIR` path resolution; `timeout 8`; fail-open
telemetry; T11 inversion; T16–T23.

**Dissents NOT applied — recorded for the operator, not silently dropped.** Both are cases where a
reviewer argued against the operator's explicitly stated direction. Per `decision-principles.md`
(ADR-084) the operator's stated direction is the default, so these are surfaced rather than acted on:

| Dissent | Reviewer's case | Why not applied |
|---|---|---|
| **Cut ADR-130 entirely** (simplicity P2.3) | "Decides nothing; needs sign-off through a channel this PR admits is dark; `status: proposed` is used by no existing ADR; the plan already writes the synthesis itself" | The brief names the ADR as Deliverable 5 and specifies `proposed` status explicitly. Not an agent's call to cut. **Operator: this is a real argument and worth your ruling.** |
| **Replace the filed-per-PR target with total-open-count** (simplicity P1.4) | "A metric scoped to exclude what you can't fix will pass while the queue keeps growing" | The brief states filed-per-PR ≤ 0.95 as the *corrected* target and says not to relitigate. **Resolved by addition, not substitution:** AC18 now requires both. |

Two further simplicity findings partially applied: Phase 5.5 (comment reconciliation) cut as agreed;
Phase 5.3 kept (cheap, and dropping `decision-challenge` silently would create a second dark channel);
the mutation-evidence file kept over P3.2 on the strength of the #6727 precedent, since the committed
transcript is what the *operator* reads while the CI proof is what the *machine* reads.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or
  `/work`.
- **Do not "simplify" the FILED query back to `--label deferred-scope-out`.** It will look like a
  tightening. It is the difference between a gate that fires and a gate that cannot. Finding 1 measured
  the coverage at ~8%.
- **Do not implement the computation twice.** The hook must delegate to the Phase 1 script. A
  hand-mirrored copy in the hook is verbatim the #6727 antipattern: the source of truth drifts and the
  suite stays green.
- **The instrumentation is not optional and not a follow-up.** It is the only thing that makes the next
  threshold change evidence-based. Shipping the threshold change without it recreates the guess.
- **Do not file issues for anything discovered during this work.** Fix inline. This PR's entire subject
  is a queue that does not drain; adding to it is self-defeating. At most one umbrella issue, and only
  if the work genuinely spans more than one PR — it does not.
- The `decision-challenge` exclusion in D3 must not silently drop those items — they render in their
  own line. Dropping them would be a second dark channel, which is the exact bug being fixed.

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | PR body: 0 closing, 3 filed (`deferred-scope-out`) | exit 1, NET=+3 |
| T2 | Same, plus `<!-- gate-override: net-issue-flow -->` | exit 0 |
| T3 | 0 closing, 3 filed (**`type/chore`**) | exit 1 — proves Finding 1 fixed |
| T4 | 2 closing, 1 filed | exit 0, NET=-1 |
| T5 | 1 closing, 1 filed | exit 0, NET=0 (boundary: NET>0 is strict) |
| T6 | 0 closing, 0 filed | exit 0, NET=0 |
| T7 | `gh` unreachable | exit 0 + TRANSIENT marker (fail-open) |
| T8 | Empty/unreadable PR body | exit 0 (fail-open) |
| T9 | `SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1` with NET=+3 | exit 0 |
| T10 | Filed issue closed before merge (`--state all`) | still counted; exit 1 |
| T11 | **INVERTED.** Body says `see #N` / `PR #N` (no keyword) | **counted** — measured as 60% of real filings |
| T12 | `gh` stub missing | **ABORT exit 2**, never a silent skip |
| T13 | Mutation: delete the `NET > 0` comparison | suite turns **red** (AC5) |
| T14 | Hook: NET>0 | `assert_deny`, exit 0, decision in JSON |
| T15 | Hook: NET≤0 | `assert_pass`, exit 0 |
| **T16** | **Truncation.** 35 in-window issues; the **31st-newest** carries the cross-reference | **counted** — fails without `--limit 500`. The highest-value new test: without it, T1–T13 all pass against a truncating query |
| **T17** | Numeric boundary: body mentions `#67491` when PR is `6749` | **not** counted |
| **T18** | Issue created earlier the same day, before the PR | **not** counted (full-ISO timestamp, not `cut -c1-10`) |
| **T19** | A *PR* created in-window (GitHub search returns PRs as issues) | **not** counted as a filing |
| **T20** | Hook: `gh pr merge <N> --squash` (merge-queue path, no `--auto`) | `assert_deny` — the widened regex |
| **T21** | Hook: `gh pr merge <N> --squash --admin` | `assert_deny` |
| **T22** | Hook invoked with cwd = `apps/web-platform/` | resolves via `CLAUDE_PROJECT_DIR`, still denies — not a silent fail-open |
| **T23** | Fail-open path taken | emits `emit_incident … transient`, not just a stdout marker |
