---
title: "docs: record the CTO ruling on agent-dispatched key rotation and the approval-environment split (#11711 residual)"
type: docs
date: 2026-11-08
slug: docs-key-rotation-dispatch-ruling-amendments
branch: feat-one-shot-11711-doc-amendments
issue: 11711
domain: engineering
brand_survival_threshold: none
---

# docs: record the CTO ruling on agent-dispatched key rotation and the approval-environment split (#11711 residual)

## Enhancement Summary

**Deepened on:** 2026-11-08 (sequential-fallback: all deepen-plan research/review roles executed
inline in this subagent — no Task tool; no independent review ran)
**Sections enhanced:** Research Insights (premise validation, property/cut lists, learnings, C4),
stale-claim inventory (completed by repo-wide grep beyond the named files), Observability,
Scope Check, Acceptance Criteria

### Key Improvements

1. Repo-wide stale-claim grep surfaced three surfaces the brief did not name —
   `scripts/inngest-key-rotate.sh`, `scripts/key-rotate.sh`, and the live follow-through probe
   `scripts/followthroughs/inngest-a5-a6-owner-ask-10136.sh` (+ its pinned test) — folded in as
   justified `inferred` scope (learning `2026-04-29-docs-fix-verification-greps-must-span-operator-surfaces`).
2. Live `gh api` re-verification (2026-11-08) confirmed the environment split AND caught a second
   stale claim: `inngest-server.md:2178` calls `infra-privileged` "a required-reviewer approval"
   while the environment has zero required reviewers — corrected under ask (g).
3. Pinned-assertion analysis: `SOURCED_PIN` (`key-rotate-workflow.test.sh` B27) sha-pins sourced
   `inngest-key-rotate.sh` bodies — re-derive it if the edit reddens it; the probe suite pins the
   two stale ask strings at `:302`/`:308`; no suite pins workflow header prose.

### New Considerations Discovered

- `model.c4:596` already models the `founder -> github` approval edge for `key-rotate-approval`
  (stays true under the ruling); edge `:814` carries pre-existing drift ("its apply job alone" —
  `clear` also binds `infra-privileged`) — optional micro-edit offered in Phase 2.
- `scripts/inngest-key-rotate.sh:1137`, `inngest-server.md:2130/:2238/:1721`,
  `key-rotation.md:243` carry *different* never-delegated rules (DONE-line, owner-words records)
  the ruling does NOT touch — explicitly marked KEEP in the inventory so the sweep does not
  over-amend.
- deepen-plan halt gates run clean: Scope Check (1 unfenced, 8 mapped asks, 4 justified inferred),
  User-Brand Impact (threshold `none` + scope-out for the `apps/*/infra/` sensitive-path hit),
  Observability (5 fields, allowlisted `bash` probe, literal `"0"`), no PAT patterns, no UI
  surface, no new store/connection, no guard deliverable (the AC1 grep is verification, not a
  shipped lint — recorded as a CTO ruling in `decision-challenges.md`).

## Overview

Security-epic residual (#11711). All 8 exposed keys are rotated and verified and the defect-fix PRs
are merged; what remains is documentation. A CTO ruling changed the dispatch-authorization policy
for the two rotation routes, and several surfaces still carry the superseded policy ("an agent never
dispatches `rotate`" / "no agent runs it" / "only the owner dispatches"). This plan amends those
surfaces and records the ruling in this branch's `decision-challenges.md`.

**The ruling being recorded (canonical wording — quote verbatim, do not paraphrase):**

> An agent may dispatch `key-rotate.yml` / `inngest-key-rotate.yml` `rotate`|`converge` ONLY under a
> fresh, per-command, in-session owner go naming the exact full command; the reviewer click on the
> `key-rotate-approval` environment (approver: deruelle) is NEVER delegated; the approval tap should
> land inside a measured release-quiet stretch — the apply path re-checks in-flight runs itself, so
> a run parked at `approve` CAN still refuse post-approval.

**The environment split (live-verified 2026-11-08 via `gh api repos/jikig-ai/soleur/environments/*`):**

- `key-rotate-approval`: `required_reviewers` = user `deruelle` (id 54279) + `branch_policy`
  (custom, `main`-only). Bound by the credential-free `approve` job — `key-rotate.yml`
  `mode=rotate`, `inngest-key-rotate.yml` `rotate`/`converge`. The run parks in `Waiting` here.
- `infra-privileged`: `branch_policy` only, **zero required reviewers** — the run does NOT park.
  Bound by `key-rotate.yml` jobs `apply` (yml:171) and `clear` (yml:306), and
  `inngest-key-rotate.yml` jobs `apply1` (yml:196), `reboot` (yml:240) and `apply2` (yml:342).
- `guard`, `redeploy`, `notify` (both files): no environment.

**Linkage note:** `issue: 11711` only — no `closes:`. This PR does NOT close the epic; other rows
remain (exposed-log deletions, `tunnel_secret`, the `inngest-host` pair). The PR body must say
`Ref #11711`, never `Closes #11711` (same convention as the #6588 remediation plan).

## Problem Statement / Motivation

The superseded policy is stated as fact on every surface a session reads before touching the route:
`key-rotation.md:36` ("An agent never dispatches `rotate`; that is policy"), ADR-307 Decision 6
("agents never dispatch `rotate` or `converge`"), ADR-317 G6/H2 ("'An agent never dispatches rotate'
remains policy"), five spots in `inngest-server.md`, both workflow headers' authorization prose, and
three runtime surfaces (`scripts/inngest-key-rotate.sh`, `scripts/key-rotate.sh`,
`scripts/followthroughs/inngest-a5-a6-owner-ask-10136.sh`). Under the ruling, a session reading any
of these would wrongly refuse an owner-authorized dispatch — or worse, read only the amended file
and collide with a sibling surface still claiming the opposite. Separately, `inngest-server.md:2178`
calls the `infra-privileged` binding "a required-reviewer approval"; the live environment has zero
required reviewers (measured 2026-11-08) and the same file says so itself at :1622.

## Proposed Solution

Prose-only amendments following this repo's established amendment conventions: rewrite the stale
clause in place and add a dated amendment/supersession marker where the file's convention is to keep
the old text visible (inngest-server.md uses `*Superseded YYYY-MM-DD:*` inline quotes; ADR-317 keeps
dated `Amendment (YYYY-MM-DD, …)` paragraphs; ADR-307 records amendment notes after `## Decision`).
No mechanism changes, no new workflow inputs, no guard additions.

## Technical Considerations

- **Amendment style per file** (match each file's own convention, verified by reading the files):
  - `key-rotation.md`: rewrite in place; no superseded-quote convention on this page.
  - `inngest-server.md`: rewrite in place; where a passage is the kind it marks superseded, use the
    file's own `*Superseded 2026-11-08:*` quoting convention.
  - `ADR-307`: amend Decision item 6 in place and append a dated amendment note under the existing
    amendment block (`Ruled by CTO agent, 2026-10-29` list) — same shape as its 2026-10-29 entries.
  - `ADR-317`: amend the G6/H2 bullet's last sentence in place and extend the dated
    `Amendment (2026-11-05, #11923 + #11920)` paragraph with a 2026-11-08 amendment line.
  - Workflow headers: comment-block rewrite; no test pins the header prose (verified: zero hits for
    `authorization is`/`owner's fresh`/`in-session go` in both workflow test suites).
- **NFR impacts:** none moved — no runtime, schema, or infra change.

### Stale-claim inventory (complete — verified by repo-wide grep, 2026-11-08)

Every site carrying the superseded claim, grouped by file. Sites marked KEEP carry a *different*
rule the ruling does not touch and must not be edited.

**`knowledge-base/engineering/operations/runbooks/key-rotation.md`**
- `:36` — `**An agent never dispatches `rotate`; that is policy, now backed by the reviewer gate.**` → ruling sentence.
- `:92` — `The rotate command shape (the owner types this themselves, under their own go):` → dispatched under a fresh, per-command, in-session owner go naming the exact line (the owner, or an agent under that go).
- `:181` — refusals table, `actor_not_owner` next-action `only the owner dispatches` → `dispatch only under a fresh per-command owner go`.
- `:24` + `:39-56` — approval-flow prose: state the env split explicitly (plan/apply/clear → `infra-privileged`, no park; rotate → `key-rotate-approval` park; reviewer `deruelle`); add the release-quiet approval-tap guidance and the post-approval re-check note.
- KEEP `:243` — `an agent never does this without an owner ruling` (already conditional; the owner go IS the ruling).

**`knowledge-base/engineering/operations/runbooks/inngest-server.md`**
- `:1713-1714` — envelope owner-human paragraph: `which only the owner dispatches … an agent never runs `rotate` or `converge`` → the dispatch may be agent-run under the form-(b) fresh per-command go; the `key-rotate-approval` reviewer click stays owner-human.
- `:1717-1718` — `the click and the dispatch are the owner's own and are never delegated` → split: the click is never delegated; the dispatch is delegable under the per-command go.
- `:1757` — A5 row `**owner-human** … only the owner dispatches `rotate` and `converge` … an agent never runs either mode` → authority cell rewritten: dispatch under a fresh in-session per-command go (owner or agent under it); the reviewer click stays owner-human; `mode=plan`'s `apply1` binds `infra-privileged` (branch policy, no reviewer — no park) while `rotate`/`converge` park at `key-rotate-approval`.
- `:2115` — `it passes through the `infra-privileged` environment approval` → `infra-privileged` binds by branch policy with zero required reviewers: no approval park.
- `:2117` — `The owner dispatches `rotate` under a fresh in-session go` → dispatched under the go (owner or agent).
- `:2178-2180` — `(a required-reviewer approval)` stale claim → zero required reviewers; the plan gate is the owner's ask, not a GitHub reviewer (live-verified).
- `:2181-2183` — `**`mode=rotate` and `mode=converge` are dispatched only by the owner.** … `no delegation covers it, and an agent never runs either mode` → ruling wording.
- `:2143` — follow-up table parenthetical `A5 is still owner-dispatched` → per the ruling the dispatch may be agent-run under the go.
- `:2251` — `the recovery is `converge` under the owner's own per-command go; no agent runs it` → under a fresh per-command go (agent may run it under that go).
- KEEP `:2130`, `:2238` (`an agent never writes` the `S5-A5-DONE` line), `:1721` (`the agent never drafts` the owner's knowledge sentence) — different rules, untouched by the ruling.

**`knowledge-base/engineering/architecture/decisions/ADR-307-inngest-key-rotation-route.md`**
- `:51` (Decision item 6) — `agents never dispatch `rotate` or `converge`` → ruling wording + dated amendment note.

**`knowledge-base/engineering/architecture/decisions/ADR-317-key-rotation-second-dispatch-only-route-sourcing-the-inngest-route.md`**
- `:103` — `"An agent never dispatches rotate" remains policy, now backed by a mechanism that does not trust the dispatch.` → ruling wording + extend the dated amendment paragraph.

**`.github/workflows/key-rotate.yml`** (header lines 5-15) and **`.github/workflows/inngest-key-rotate.yml`** (header lines 4-10) — authorization prose gains: the agent may dispatch under the fresh per-command go; the reviewer click is never delegated; the approval tap belongs in a measured release-quiet stretch (apply re-checks in-flight itself, so a parked run can still refuse post-approval); the env split is already stated in `THE ORDER` — keep it and name `infra-privileged`/`key-rotate-approval` consistently.

**Runtime prose (inferred scope — see Scope Check):**
- `scripts/inngest-key-rotate.sh`: `:30` comment (`no agent runs it`), `:557` and `:561` stop-sentence `printf`s (`(no agent runs it…)`) — the stop sentences print into `action-required` issues a recovery session reads.
- `scripts/key-rotate.sh`: `:295` comment (`the owner types a fresh confirm; no agent runs it`).
- `scripts/followthroughs/inngest-a5-a6-owner-ask-10136.sh`: `:6` and `:13` header comments; `:310` owner-facing ask (`only you dispatch it … and no agent runs it`) — the daily sweeper posts this to the owner.
- KEEP `scripts/inngest-key-rotate.sh:1137` (`agent never writes a DONE line`) — DONE-line rule, untouched.

**Pinned assertions that move with the prose:**
- `scripts/followthroughs/inngest-a5-a6-owner-ask-10136.test.sh:302,308` — expects `"only you dispatch it"` and `"no agent runs it"`; update to the amended strings.
- `apps/web-platform/infra/key-rotate-workflow.test.sh:458` — `SOURCED_PIN` is a sha256 over the sourced `inngest-key-rotate.sh` function bodies `key-rotate.sh` calls (+ transitive callees). If the edited functions are pinned, recompute the pin (edit the functions, run the suite, update `SOURCED_PIN` to the recomputed value). Verified: no test pins the literal `no agent runs it` / `only the owner dispatches` strings outside the probe suite.

**Deliberately not amended:** `knowledge-base/project/{plans,specs}/archive/**` — point-in-time
records; the stale claims there are historical, not live guidance.

## Files to Edit

| File | Ask | Notes |
|---|---|---|
| `knowledge-base/engineering/operations/runbooks/key-rotation.md` | (a), (g) | 4 edit sites + env-split clarity in the approval section |
| `knowledge-base/engineering/operations/runbooks/inngest-server.md` | (b), (g) | ~9 edit sites incl. the stale `infra-privileged` reviewer claim |
| `knowledge-base/engineering/architecture/decisions/ADR-307-inngest-key-rotation-route.md` | (d) | Decision 6 + dated amendment note |
| `knowledge-base/engineering/architecture/decisions/ADR-317-key-rotation-second-dispatch-only-route-sourcing-the-inngest-route.md` | (c) | G6/H2 sentence + dated amendment line |
| `.github/workflows/key-rotate.yml` | (e), (g) | header comment block only |
| `.github/workflows/inngest-key-rotate.yml` | (e), (g) | header comment block only |
| `scripts/inngest-key-rotate.sh` | inferred | 3 sites: `:30`, `:557`, `:561` |
| `scripts/key-rotate.sh` | inferred | `:295` comment |
| `scripts/followthroughs/inngest-a5-a6-owner-ask-10136.sh` | inferred | `:6`, `:13` comments + `:310` ask |
| `scripts/followthroughs/inngest-a5-a6-owner-ask-10136.test.sh` | inferred | expectations `:302`, `:308` |
| `apps/web-platform/infra/key-rotate-workflow.test.sh` | inferred | `SOURCED_PIN` recompute — only if the pin breaks |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | inferred | optional micro-edit: edge `:596` one-clause note; edge `:814` "apply job alone" → "apply and clear jobs" (pre-existing drift, adjacent) |

## Files to Create

| File | Ask | Notes |
|---|---|---|
| `knowledge-base/project/specs/feat-one-shot-11711-doc-amendments/decision-challenges.md` | (f) | `| Item | Class | Ruling |` table; the dispatch ruling recorded as `technical` / `Ruled by CTO agent: <decision>` |

## Implementation Phases

### Phase 1: ADR amendments (the record of record)

- Amend `ADR-307` Decision 6 in place; append a 2026-11-08 amendment note under the existing
  `Ruled by CTO agent, 2026-10-29` block. The amended item keeps the parts the ruling does not
  change: the typed confirm/`quiet_window` are typo-guards, a go on another issue does not count,
  the `S5-A5-DONE` line is still never agent-posted.
- Amend `ADR-317` G6/H2's final sentence in place; extend the dated amendment paragraph with the
  2026-11-08 ruling. Keep the residual statements (PAT dispatch, PAT approval) untouched.
- Success criterion: both ADRs state the ruling verbatim; each carries a dated amendment marker.

### Phase 2: Runbook amendments + environment split

- `key-rotation.md`: replace `:36`; update `:92` and `:181`; in the `key-rotate-approval` section,
  state the split explicitly — `mode=plan` and the `apply`/`clear` jobs bind `infra-privileged`
  (branch policy, zero required reviewers, no park); `mode=rotate` parks at `key-rotate-approval`
  (required reviewer `deruelle`) — and add the release-quiet approval-tap guidance plus the
  post-approval in-flight re-check note.
- `inngest-server.md`: amend the nine sites listed above; correct the `:2178`/`2115`
  `infra-privileged` claim against the live environment; where a passage follows the file's
  superseded-quote convention, mark the old text `*Superseded 2026-11-08:*`.
- Optional C4 micro-edit (model.c4): extend edge `:596` with one clause ("the parked dispatch may be
  owner- or agent-initiated under the owner's fresh per-command go — the reviewer click stays the
  founder's, CTO ruling 2026-11-08, #11711") and fix edge `:814` "its apply job alone" →
  "its apply and clear jobs".
- Success criterion: zero stale-claim matches outside `*Superseded*` markers (AC1 grep).

### Phase 3: Workflow header prose

- Rewrite the authorization paragraphs of both headers to carry the ruling + the never-delegated
  click + the release-quiet tap; the `THE ORDER` job tables already name the environments — make the
  split sentence consistent with them.
- Success criterion: `key-rotate-workflow.test.sh` and `inngest-key-rotate-workflow.test.sh` still
  green (headers are comments; no suite parses them — verified).

### Phase 4: Runtime-prose consistency sweep (inferred scope)

- Amend the three script surfaces and the probe ask; update the probe's two pinned test
  expectations; run both rotation workflow suites — if `SOURCED_PIN` reddens, recompute it against
  the edited function bodies and update the pin with a comment noting the ruling drove the body
  change.
- Success criterion: `bash scripts/followthroughs/inngest-a5-a6-owner-ask-10136.test.sh` green;
  `bash apps/web-platform/infra/{key-rotate,inngest-key-rotate}-workflow.test.sh` green.

### Phase 5: Ruling record + verification

- Write `decision-challenges.md` (see "Ruling record" below).
- Run the AC1 stale-claim grep across all amended surfaces; run `gh api` against both environments
  and confirm the doc's env-split claims still match live state.

## Research Insights

- **Premise Validation.** All cited artifacts exist: `key-rotation.md`, `inngest-server.md`
  (runbooks dir), `ADR-307-*`, `ADR-317-*` (decisions dir), both workflows, issue #11711 OPEN
  ("security: rotation tracker for every random_id secret whose id was printed in public logs
  (#11294), one row per secret"). Collision pre-check for #11711: one hit — PR #12391, which is
  THIS pipeline's own draft on this branch, not a duplicate. `proc.sh` sibling check could not run
  (exit 1) — disclosed. Live API reads (2026-11-08) confirm the environment claims: `key-rotate-approval`
  = required reviewer `deruelle` (54279) + custom branch policy; `infra-privileged` = branch policy
  only, zero required reviewers — which makes `inngest-server.md:2178`'s "(a required-reviewer
  approval)" a second stale claim the task's (g) covers.
- **Property List (Phase 0.6b).** P1 every operator-facing surface stating the superseded
  agent-never-dispatches claim states the ruling instead; P2 the env split is documented wherever
  approval flow is described; P3 the ruling is recorded in `decision-challenges.md`; P4 the PR
  does not close #11711. **Mechanisms proposed by the ask:** file amendments only — no machinery.
  **Cut List:** none (no mechanism proposed; the stale-claim verification grep is an AC, not a
  shipped guard — considered and deliberately not shipped as a lint: a prose-drift lint over
  natural-language variants is more vacuous than protective).
- **Institutional learnings applied.** `2026-04-29-docs-fix-verification-greps-must-span-operator-surfaces`
  (the stale-claim sweep must cover script/probe surfaces, not just the named docs — this is the
  basis of the Phase 4 inferred scope); `2026-05-06-umbrella-issue-stale-enumeration-requires-live-reverification`
  (live `gh api` + grep re-verification done); `2026-06-18-doc-insertion-stales-cross-artifact-line-citations`
  (amendments cite anchors/sections, not line numbers, inside the docs).
- **Conventions.** ADR amendment style = in-place rewrite + dated amendment paragraph (ADR-317's own
  2026-11-05 precedent); inngest-server.md keeps `*Superseded <date>:*` quoted old text; plan `issue:`
  without `closes:` = Ref-not-Closes (verified across the plan corpus).
- **C4 model.** `model.c4:596` already models the `founder -> github` approval edge for
  `key-rotate-approval`; `:814` documents the `infra-privileged` consumer set ("inngest-key-rotate.yml
  … apply1, apply2 and reboot jobs"; "key-rotate.yml … its apply job alone" — the second clause is
  stale drift: `clear` also binds it, yml:306).
- **Sequential-fallback disclosure.** This plan ran inside a Devin one-shot subagent with no Task
  tool: the repo-research, learnings, functional-overlap, spec-flow, advisor-consult and
  domain-leader roles the skill prescribes as subagent spawns were executed inline in this process
  (`Reviewed-Coverage: sequential-fallback`). No independent review ran.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --json number,title,body --limit 200`
returned zero issues whose body names any file in `## Files to Edit`/`## Files to Create`
(checked 2026-11-08 against every path above, including `key-rotate.yml`, `inngest-key-rotate.yml`,
`key-rotate-workflow.test.sh`, `inngest-a5-a6-owner-ask` and both ADRs).

## Research Reconciliation — Spec vs. Codebase

No `spec.md` exists for this branch (the spec dir is created by this plan's artifacts). Nothing to
reconcile; the plan is grounded on live file reads and `gh api`, not on spec claims.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing direct — the production-mutating mechanism
  (the `key-rotate-approval` reviewer gate, the refusal ladder, the owner allowlist, the typed
  confirm) is untouched by this diff; worst outcome of a wording error is a session refusing an
  owner-authorized dispatch or a reader catching the error at the unchanged mechanical gates.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — the
  diff is prose in a public repository; it names key names and workflow commands (already public),
  never key values.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** prose-only amendments; the authorization mechanism is
  unchanged, so the diff cannot itself reach a production mutation — not `single-user incident`,
  which is reserved for diffs that can cause one.
- `threshold: none, reason: prose-only amendments to docs, comments and operator-ask strings; the reviewer gate, guard ladder and owner allowlist are untouched, so a wording error cannot reach a production mutation on its own.`

## Observability

```yaml
liveness_signal:
  what: the amended-prose invariant — zero stale-claim matches outside Superseded markers, plus the two pinned workflow suites green
  cadence: per-PR (CI)
  alert_target: PR required checks
  configured_in: apps/web-platform/infra/key-rotate-workflow.test.sh, apps/web-platform/infra/inngest-key-rotate-workflow.test.sh, scripts/followthroughs/inngest-a5-a6-owner-ask-10136.test.sh

error_reporting:
  destination: GitHub Actions job log on the PR
  fail_loud: a red required check (suite failure or a nonzero stale-claim grep in review)

failure_modes:
  - mode: a stale claim survives in an amended file
    detection: the AC1 grep run in Phase 5 + reviewer grep
    alert_route: PR check red / review finding
  - mode: SOURCED_PIN drift after editing sourced function bodies
    detection: key-rotate-workflow.test.sh row B27
    alert_route: suite failure naming the pin

logs:
  where: GitHub Actions run log
  retention: 90 days

discoverability_test:
  command: bash -c "grep -rE 'agent never dispatch|agents never dispatch|no agent runs it|dispatched only by the owner|only the owner dispatches' knowledge-base/engineering/operations/runbooks/key-rotation.md knowledge-base/engineering/operations/runbooks/inngest-server.md knowledge-base/engineering/architecture/decisions/ADR-307-inngest-key-rotation-route.md knowledge-base/engineering/architecture/decisions/ADR-317-key-rotation-second-dispatch-only-route-sourcing-the-inngest-route.md .github/workflows/key-rotate.yml .github/workflows/inngest-key-rotate.yml scripts/key-rotate.sh scripts/inngest-key-rotate.sh scripts/followthroughs/inngest-a5-a6-owner-ask-10136.sh | grep -vc 'Superseded'"
  expected_output: "0"
```

## Architecture Decision (ADR/C4)

- **ADR:** this plan's deliverable IS the record — amendments to `ADR-307` Decision 6 and `ADR-317`
  G6/H2 with dated amendment notes. No new ADR (a policy amendment of an existing recorded
  decision, not a new decision; Phase 0.6's corpus read confirms no third ADR touches this claim).
- **C4 views:** no element/edge change required. Enumeration checked against all three model files
  (`model.c4`, `views.c4`, `spec.c4`): (a) external human actors — `founder` exists and its
  `founder -> github` approval edge (model.c4:596, the `key-rotate-approval` reviewer click) stays
  TRUE under the ruling (the click is never delegated); (b) external systems — `github` (Actions
  environments) already modeled at :596 and :814; (c) containers/data-stores — none touched;
  (d) actor↔surface relationships — the only relationship that changes is *who initiates the
  dispatch* (owner-only → agent-under-owner-go); no dispatch edge exists in the model to falsify
  (only the approval boundary is modeled). The optional micro-edit to `:596`/`:814` in Phase 2 keeps
  the record complete; skipping it leaves the model accurate but silent on the new dispatch
  authority. If taken, run `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "the key-rotation runbook (find it, likely knowledge-base/engineering/operations/runbooks/key-rotation.md) — replace the 'An agent never dispatches rotate' line with the CTO ruling: an agent may dispatch key-rotate.yml / inngest-key-rotate.yml rotate\|converge ONLY under a fresh, per-command, in-session owner go naming the exact full command; the reviewer click on the key-rotate-approval environment (approver: deruelle) is NEVER delegated; the approval tap should land inside a measured release-quiet stretch — apply re-checks in-flight itself, so a parked run CAN still refuse post-approval" | Phase 2 / `key-rotation.md` edits (`:36`, `:92`, `:181`, approval section) | mapped |
| 2 | "inngest-server.md — its A5 and rotation sections (same finding for the stale 'agent never dispatches' claim)" | Phase 2 / `inngest-server.md` edits (`:1713`, `:1717`, `:1757`, `:2115`, `:2117`, `:2181`, `:2143`, `:2251`) | mapped |
| 3 | "ADR-317 amendment — find it under knowledge-base/engineering/architecture/decisions/" | Phase 1 / ADR-317 `:103` + dated amendment | mapped |
| 4 | "ADR-307 Decision 6 — same directory" | Phase 1 / ADR-307 `:51` + dated amendment | mapped |
| 5 | "authorization prose in the headers of both workflows — .github/workflows/key-rotate.yml and .github/workflows/inngest-key-rotate.yml" | Phase 3 / both header comment blocks | mapped |
| 6 | "record the ruling in this branch's decision-challenges.md at knowledge-base/project/specs/feat-one-shot-11711-doc-amendments/decision-challenges.md (\| Item \| Class \| Ruling \| table; Class technical, Ruling 'Ruled by CTO agent: <decision>')" | Phase 5 / Files-to-Create entry | mapped |
| 7 | "document the infra-privileged vs key-rotate-approval environment split wherever the runbook/workflow prose describes approval flow: rotate/converge workflow runs park at the key-rotate-approval environment gate; the apply path runs under infra-privileged" | Phase 2+3 / env-split prose in `key-rotation.md`, `inngest-server.md` (incl. the `:2178` stale reviewer claim fix), both workflow headers | mapped |
| 8 | "The plan's own frontmatter should carry Ref #11711 (contextual — this PR does NOT close the epic; other epic rows remain: deletions, tunnel_secret, inngest-host pair)" | frontmatter `issue: 11711` (no `closes:`) + Linkage note + AC9 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `key-rotation.md` edits | ask 1 (quoted above) | asked |
| `inngest-server.md` edits | ask 2 + ask 7 (quoted above) | asked |
| ADR-317 amendment | ask 3 | asked |
| ADR-307 Decision 6 amendment | ask 4 | asked |
| both workflow headers | ask 5 + ask 7 | asked |
| `decision-challenges.md` | ask 6 | asked |
| env-split prose (both runbooks + headers) | ask 7 | asked |
| `issue: 11711`, no `closes:` | ask 8 | asked |
| `scripts/inngest-key-rotate.sh`, `scripts/key-rotate.sh` string/comment edits | — | inferred — justification: the identical superseded claim printed into `action-required` issues and recovery stop sentences (`(no agent runs it)` at :30/:557/:561/:295); a recovery session reading them is told the opposite of the amended docs (learning `2026-04-29-docs-fix-verification-greps-must-span-operator-surfaces`) |
| `scripts/followthroughs/inngest-a5-a6-owner-ask-10136.sh` + its test | — | inferred — justification: the daily sweeper posts the ask to the owner (`only you dispatch it … and no agent runs it`, :310, header :6/:13); same-class stale claim on an operator-facing surface; the test pins the two stale strings (:302/:308) so it moves together or the suite reddens |
| `apps/web-platform/infra/key-rotate-workflow.test.sh` (`SOURCED_PIN`) | — | inferred — justification: conditional pin recompute; `key-rotate.sh` sources `inngest-key-rotate.sh` and row B27 sha-pins the sourced bodies it calls, so editing the sibling can only land with the pin re-derived (ADR-317 F1 mechanism) |
| `model.c4` optional micro-edit | — | inferred — justification: the C4 completeness mandate requires falsified element descriptions be corrected; edge `:814` "its apply job alone" is pre-existing drift (the `clear` job also binds `infra-privileged`, yml:306) on the exact surface item (g) documents, and a one-clause `:596` note records the new dispatch authority |

### Split Assessment

- Subsystems touched: 3 — `knowledge-base/`, `scripts/`, `.github/` (+ `apps/web-platform/infra/` test file only if the pin moves)
- Planned files: 13 | Estimated changed lines: ~120
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the file count crosses no threshold; the inferred script edits are the same claim class as the asked doc edits and splitting them would ship self-contradicting surfaces.

## Acceptance Criteria

- [ ] **AC1** Across the amended surfaces (`key-rotation.md`, `inngest-server.md`, ADR-307, ADR-317, both workflow yml, both `key-rotate*.sh`, `inngest-a5-a6-owner-ask-10136.sh`), `grep -rE 'agent never dispatch|agents never dispatch|no agent runs it|dispatched only by the owner|only the owner dispatches'` filtered to exclude `*Superseded*` marker lines returns zero matches.
- [ ] **AC2** `key-rotation.md` states the ruling verbatim (agent may dispatch `rotate`|`converge` only under a fresh, per-command, in-session owner go naming the exact full command), states the reviewer click on `key-rotate-approval` (approver `deruelle`) is never delegated, and states the release-quiet approval-tap guidance with the post-approval in-flight re-check.
- [ ] **AC3** `inngest-server.md` A5 row, envelope owner-human paragraph, "Who dispatches what", "Key rotation order (A5)" step 3 and the post-apply recovery cell carry the ruling; the `(a required-reviewer approval)` claim about `infra-privileged` is corrected to the live-verified branch-policy-only/zero-reviewer state; KEEP-marked sentences (`:2130`, `:2238`, `:1721`) are byte-unchanged.
- [ ] **AC4** `ADR-307` Decision 6 and `ADR-317` G6/H2 carry the ruling wording plus dated 2026-11-08 amendment notes; the parts the ruling does not change (confirm/quiet_window as typo-guards, no cross-issue go, `S5-A5-DONE` never agent-posted) are retained.
- [ ] **AC5** Both workflow headers' authorization prose carries the ruling, the never-delegated click, the release-quiet tap, and the job→environment split consistent with `THE ORDER` tables.
- [ ] **AC6** `knowledge-base/project/specs/feat-one-shot-11711-doc-amendments/decision-challenges.md` exists with a `## Decision Classes` `| Item | Class | Ruling |` table; the dispatch ruling row reads Class `technical`, Ruling `Ruled by CTO agent: <decision>`.
- [ ] **AC7** Wherever approval-flow prose exists in the amended files, it names the split: `rotate`/`converge` park at `key-rotate-approval` (required reviewer `deruelle`); `mode=plan` and the apply path bind `infra-privileged` (branch policy, zero required reviewers, no park). Spot-check against `gh api repos/jikig-ai/soleur/environments/key-rotate-approval` and `.../infra-privileged`.
- [ ] **AC8** `bash scripts/followthroughs/inngest-a5-a6-owner-ask-10136.test.sh`, `bash apps/web-platform/infra/key-rotate-workflow.test.sh` and `bash apps/web-platform/infra/inngest-key-rotate-workflow.test.sh` all exit 0 (probe expectations updated; `SOURCED_PIN` re-derived if the pin reddened).
- [ ] **AC9** The PR body references the epic as `Ref #11711`, never `Closes #11711` (ship-time check; the epic's deletions/`tunnel_secret`/`inngest-host` rows remain open).

## Test Scenarios

- Given the amended file set, when `grep -rE 'agent never dispatch|agents never dispatch|no agent runs it|dispatched only by the owner|only the owner dispatches' <files> | grep -v Superseded` runs, then it prints nothing (`integration`).
- Given `inngest-key-rotate.sh` stop-sentence edits, when `bash apps/web-platform/infra/key-rotate-workflow.test.sh` runs, then B27 passes (either the pin still matches — the edited functions are unpinned — or `SOURCED_PIN` was re-derived and documented) (`unit`-class suite).
- Given the probe ask edits, when `bash scripts/followthroughs/inngest-a5-a6-owner-ask-10136.test.sh` runs, then the ask-content expectations pass against the new strings (`unit`-class suite).
- Given the workflow header edits, when `bash apps/web-platform/infra/inngest-key-rotate-workflow.test.sh` runs, then it exits 0 (comments are uninspected; control for accidental non-comment edits) (`unit`-class suite).
- Given the env-split prose, when `gh api repos/jikig-ai/soleur/environments/key-rotate-approval --jq '.protection_rules[].type'` and the same for `infra-privileged` run, then output matches what the docs claim (`integration` — read-only live check).

## Domain Review

**Domains relevant:** Engineering, Legal (adjacent)

### Engineering

**Status:** reviewed (inline, sequential-fallback — no Task tool in this subagent)
**Assessment:** docs/prose-only change to engineering operations surfaces; correctness live-verified
against `gh api` environment reads, the workflow `environment:` bindings, and the pinned-suite
mechanics (`SOURCED_PIN`, probe expectations). No architecture change — the authorization mechanism
is untouched; only its recorded policy changes.

### Legal

**Status:** reviewed (inline, sequential-fallback)
**Assessment:** the amendment touches the `inngest-server.md` Production Envelope that embeds
CLO-ruled record conventions. Verified the CLO-protected rules are untouched: owner-words knowledge
claims, the `S5/S6 DONE` vs `-RELAYED` record split, the provenance block, and the banned
"SIGNED BY OWNER" marker all stay as ruled on 2026-11-02. The change is confined to dispatch
authority, not record authority — no CLO re-ruling needed.

### Product/UX Gate

**Tier:** none — no UI-surface file in `## Files to Edit`/`## Files to Create` (mechanical override
scan: no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or other UI-surface term).
A docs/scripts/workflows change with no user-facing surface.

## Deepen Pass Notes

- Scoped advisor consult (Step 4.5): executed inline (sequential-fallback) — reviewed the riskiest
  surface, the nine-site `inngest-server.md` amendment; the consult's own check is that the A5 row's
  `owner-human` label is retained ONLY for the reviewer click, not silently broadened back over the
  dispatch.
- Plan-review panel (sequential-fallback, three eng lenses inline): DHH lens — no overengineering,
  amendments are literal prose and the inferred sweep is bounded; Kieran lens — amendment
  conventions match each file's own precedent, pinned suites accounted for; simplicity lens — no
  new machinery, no lint shipped. Named-panel scan (ADR-267): no business/design/devex lens is
  relevant beyond the already-made CTO ruling; none spawned.

## Success Metrics

- Zero stale-claim matches on the amended surfaces (AC1 grep) at merge.
- Both rotation suites + the probe suite green at merge.
- The docs' env-split claims still match live `gh api` output at ship time.

## Dependencies & Risks

- `SOURCED_PIN` coupling: editing `inngest-key-rotate.sh` may force a pin recompute in
  `key-rotate-workflow.test.sh` — expected, mechanical; the pin must be re-derived by running the
  suite, never hand-edited to silence it.
- Multi-register drift: the same policy is stated in ADR prose, runbook prose, workflow comments,
  script comments/strings, test expectations and the probe's owner ask — Phase 5's grep is the
  completeness tripwire; a missed surface reopens this residual.
- `inngest-server.md` is a hot file (last touched 2026-11-07, #12245): re-check for upstream drift
  before editing; anchor all edits by content, not line number.
- The probe's `:310` ask is operator-facing: the amended wording must keep "your go in a session
  that names the exact line" load-bearing — only the "only you/no agent" claim changes.

## References & Research

- Issue: #11711 (epic, stays open), Ref #11294, Ref #10205, #11923 (approval gate), #11920 (egress)
- ADRs: `ADR-307-inngest-key-rotation-route.md`, `ADR-317-…-inngest-route.md`, ADR-241 (credential tiers)
- Live evidence: `gh api repos/jikig-ai/soleur/environments/{key-rotate-approval,infra-privileged}` (2026-11-08)
- Learnings: `knowledge-base/project/learnings/best-practices/2026-04-29-docs-fix-verification-greps-must-span-operator-surfaces.md`, `2026-05-06-umbrella-issue-stale-enumeration-requires-live-reverification.md`, `2026-06-18-doc-insertion-stales-cross-artifact-line-citations.md`
- Delegation reference: `plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md`
