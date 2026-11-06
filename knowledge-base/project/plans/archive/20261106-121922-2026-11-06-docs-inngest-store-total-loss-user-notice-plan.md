---
title: "docs(runbook): pre-drafted user notice for a total loss of the Inngest store"
type: docs
date: 2026-11-06
slug: inngest-store-total-loss-user-notice
branch: feat-one-shot-10664-inngest-user-notice
issue: 10664
lane: cross-domain
domain: engineering/operations
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# docs(runbook): pre-drafted user notice for a total loss of the Inngest store

## Overview

Issue #10664 (the Inngest LUKS arc follow-up tracker, OPEN) carries one unchecked item in scope here: a pre-drafted user notice for a total loss of the Inngest store — ready text naming what was lost, the window and the action to take, so a total loss does not start from a blank page. The CPO advisory that originated the item (PR #10652 review, 2026-10-22) routed the legal question of whether and when notification is owed to the CLO; this plan delivers the text and states that send conditions are the CLO's call, deciding nothing about disclosure duty. The artifact is a new file under `knowledge-base/engineering/operations/runbooks/`, cross-linked from the "After a total loss" section of `inngest-luks-cutover-6894.md` and the Quick reference table of `inngest-server.md`. All other tracker items are gated (host-replace window, owner dashboard read, next-cutover trigger) and out of scope.

**Observation (not a work target):** the tracker's "orphan-sweep steps keep the loader-exported token and have no notification path" checkbox is stale — the work shipped in merged PR #10936 (`fix(infra): orphan sweeps read the read-only Hetzner token only and email on failure`, merged 2026-10-24). Editing the issue body is out of scope; the checkbox stays as-is.

## Enhancement Summary

**Deepened on:** 2026-11-06
**Sections enhanced:** gate verification over all sections; no content rewrites needed
**Research agents used:** none — `Reviewed-Coverage: sequential-fallback` (this session has no subagent-spawn capability; the Phase 1/4/5 fan-outs ran as direct repo reads by the orchestrator, and no independent review ran)

### Halt-gate results (deepen-plan)

| Gate | Verdict |
|---|---|
| 4.6 User-Brand Impact | PASS — section present, threshold `single-user incident`, concrete body |
| 4.7 Observability | SKIP — pure-docs (every Files-to-Edit path is `knowledge-base/` or `.md`) |
| 4.8 PAT-shaped variables | PASS — zero matches |
| 4.9 UI wireframe | SKIP — no UI-surface file |
| 4.10 Encryption posture | SKIP — no store or connection |
| 4.11 Guard contract | SKIP — no guard deliverable |
| 4.12 Scope Check | PASS — one live section, all subsections, no unmapped/BLOCKED rows |
| 4.13 Task design | SKIP — no new autonomous-task surface |
| 4.5 Network-outage | SKIP — trigger tokens appear only inside the lint-rule description, not as a plan subject |
| 4.55 Downtime & Cutover | SKIP — no infra/offline-inducing operation |

### Key Improvements

1. AC verification commands were executed at plan-write time (existence/absence greps, the `lint-infra` `--changed` invocation) — the plan file itself was caught once by `lint-infra-no-human-steps.py` and fixed with the documented carve-out.
2. The stale-checkbox observation (orphan-sweep item shipped in PR #10936) is recorded in Overview + AC8 rather than edited into the issue body, per the brief.
3. `decision-challenges.md` passed `technical-ruling-gate.sh --branch` (1 taste row; no technical rows — no forks existed).

### New Considerations Discovered

- `Reviewed-Coverage: sequential-fallback` — the plan-review panel, domain-leader spawns, CPO sign-off consult and `soleur:gdpr-gate` invocation this session could not run are flagged here and in `## Domain Review`; `soleur:review`-time conditional agents (`user-impact-reviewer` at this threshold, `soleur:marketing:copywriter` for user-facing copy) are the coverage path.

## Problem Statement / Motivation

A total loss of the Inngest store (the sole-copy Redis AOF LUKS volume plus, in the worst case, the dedicated Supabase Postgres history project) is a rare, high-pressure incident. The cutover runbook's "After a total loss: who tells affected users" section (`knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md`, §562+) already fixes who sends (the repository owner, as a product notice via `soleur:incident`), who is covered (all active users as a floor — not a ceiling), and what must never be claimed. What it does not contain is the notice text itself. Drafting user-facing wording mid-incident — while a 72-hour Art. 33 assessment clock may be running and the C1 finding constrains every claim — is exactly the blank-page failure the tracker item exists to remove.

## Proposed Solution

Create one new runbook file, `knowledge-base/engineering/operations/runbooks/inngest-store-total-loss-user-notice.md`, holding the ready-to-adapt notice, the constraints the text must keep, the fill-field table, and the CLO-call caveat — then link it from the two places an incident owner already looks.

### New file shape

Runbook frontmatter per the corpus convention (verified against `monitor-send-failed-alert.md` / `dsar-export-failed-job.md`):

```yaml
---
title: "Pre-drafted user notice — total loss of the Inngest store"
date: 2026-11-06
owners: engineering/ops
category: incident-communications
tags: [inngest, luks, incident, user-notice, total-loss]
applies_to:
  - knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md
related_issues: [10664, 9927]
---
```

Sections, in this order:

1. **What this file is** — the standing draft for the user notice the owner sends as a product notice when the loss-mode procedure lands on "After a total loss" (`inngest-luks-cutover-6894.md` §Per-loss-mode rows `volume-gone`, `Both copies lost`, `LUKS header corrupted`, `Volume deleted despite protection, or project loss`, and the `fail_header` key-probe row).
2. **Send conditions are the CLO's call** — the draft decides nothing about whether notification is owed (the Art. 4(12)/33/34 assessment the runbook already names), to whom, on which channel, or when. Those are the incident owner's decisions with counsel; the determination record lands in `knowledge-base/legal/audits/` and `knowledge-base/legal/breach-register.md`. This line is load-bearing — the file exists so wording never has to be improvised, not so disclosure duty is pre-decided.
3. **Constraints the notice text must keep** (each traceable to the runbook's C1 finding):
   - The affected set is "all active users" as a floor — do not state a narrower set (two groups sit outside even that floor: inactive founders and external inbound-email senders).
   - Never claim "no record survives" or "nothing identifies anyone" — the C1 evidence class is **partial** (a user-reference-capable column exists; neither its non-null count nor the oldest row was measured).
   - Never promise armed reminders will be restored — the re-arm path (`apps/web-platform/infra/inngest-rearm-reminders.sh`) covers `reminder.scheduled` only, and whether it ran is an incident-time fact.
   - The notice does not cover the external-sender group (`email/inbound.received`); the runbook names the separate owner step for them — state in one line that this notice is not that step.
   - No per-user identifiers, per-user counts, or "N users affected" figures — C1 measured aggregate only; a count the evidence cannot support is worse than none.
4. **The drafted notice** — a single copy-pasteable block with clearly marked `[...]` fill fields (skeleton below; the work phase writes the final text against the constraints).
5. **Fill fields** — a table: each placeholder, who supplies it, where the value comes from (incident timestamps from the loss-mode finding; the re-arm verdict from whether `inngest-rearm-reminders.sh` ran; the support route).

### Drafted notice skeleton (starting text for the work phase)

> **Subject: An incident affected some automated work in your Soleur workspace**
>
> On [DATE UTC] we lost the store Soleur uses to queue and run automated work — drafts, reminders and approved actions waiting to execute — and the history of those runs.
>
> What this means for you:
>
> - Automated work queued or in progress at [LOSS TIME UTC] on [DATE] did not complete and was not automatically retried.
> - Drafts, reminders or follow-up actions you expected around that time may never have appeared.
> - Run history for affected work is not available.
> - Your repositories, knowledge base and account data were not part of this store.
>
> What we did: the store was rebuilt and your automations re-registered; work scheduled since [RESTORE TIME UTC] runs normally.
>
> What to do:
>
> - Check your dashboard for drafts or reminders you expected but never received, and re-trigger the underlying action where you can.
> - If you approved an action around [DATE] that never executed, approve it again — an approval click is safe to repeat within 23 hours of the original (#10543).
> - If a reminder that mattered did not fire, re-create it.
> - If something you lost is not covered above, write to [SUPPORT ROUTE].
>
> [ONE-SENTENCE prevention/follow-up line — owner fills at send time.]

### Cross-links (two one-line edits)

- `inngest-luks-cutover-6894.md` — under `### After a total loss: who tells affected users`, one sentence: the ready notice text lives in `inngest-store-total-loss-user-notice.md`, and the constraints above bind it.
- `inngest-server.md` — one Quick reference row: `Pre-drafted user notice after a total loss (#10664)` → the new file.

## Technical Considerations

- **Docs-only diff.** No code, infra, store or connection is added — Observability (Phase 2.9), Encryption Posture (2.11), Task Design (2.9.3), IaC routing (2.8), ADR/C4 (2.10) and Guard Contract (2.12) all skip. The deliverable is text; PR review is the correctness gate. A phrase-pinning lint over the notice's required sentences was considered and cut (Cut List below).
<!-- lint-infra-ignore start: describes the gate's own trigger vocabulary; prescribes no operator step -->
- **`scripts/lint-infra-no-human-steps.py` scans the runbook dir.** The new file's prose must not pair a human-actor token (`owner`, `operator`, `you`) with an infra imperative (`ssh`, `terraform apply`, `systemctl`) on a line or adjacent lines outside fences. The notice block is quoted template text — keep it inside a fenced block or blockquote.
<!-- lint-infra-ignore end -->
- **`scripts/markdown-lint.sh` (the single invoker, pinned markdownlint) lints `knowledge-base/engineering/`** — including the new runbook; `knowledge-base/project/` is excluded but the touched runbooks are not. `.markdownlint.json` disables MD013/MD024/MD025/MD018/MD028; MD032 (lists need a blank line before them) is live — author accordingly.
- **`hr-no-ssh-fallback-in-runbooks`** — the file prescribes no host access at any step; trivially satisfied.
- **Citations stay accurate.** Every claim the runbook makes about the store, the evidence class and the re-arm path is already written down in `inngest-luks-cutover-6894.md` (the C1 Superseded block and the event-class table) — the new file points at them rather than restating numbers that can drift (~937k history rows etc. appear only in the constraints context, not the user text).
- **The user-facing claims in the draft are verified against repo state:** the 23-hour re-click window is `#10543` (named in the runbook event table); the re-arm script exists at `apps/web-platform/infra/inngest-rearm-reminders.sh` (verified on disk); "the app's behaviour on an empty store is that functions re-register and new reminders arm normally" is the runbook's own recorded statement.
- **Tracker stays open.** The PR body uses `Ref #10664`, never `Closes #10664` — five other items remain on the tracker.

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 10664` → **OPEN**, title `infra: Inngest LUKS items 6, 8b, C1 follow-ups (site C fallback, sweep steps, user notice, scoped probe role)`. The in-scope item is present and unchecked.
- **Stale checkbox confirmed:** the "Orphan-sweep steps … no notification path" item shipped in merged PR #10936 (2026-10-24) and PR #10967 — its `- [ ]` is stale; recorded as an observation, not a work target (issue-body edit is out of scope).
- Citations verified: #10848 (storage-limitation / Art. 17 — CLOSED, resolved 2026-11-02 per the compliance-posture marker) and #10849 (published-disclosure wording — CLOSED) are citations only, not work targets. PR #10652 is the build PR the item was deferred from; PR #10891 closed the Site C item.
- Referenced artifacts exist on this branch: `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` (§562 "After a total loss", §601 event-class table), `inngest-server.md` (4243 lines, Quick reference table), `apps/web-platform/infra/inngest-rearm-reminders.sh`, `knowledge-base/legal/breach-register.md`, `plugins/soleur/skills/incident/` (internal PIR scaffold — the notice is a distinct artifact).
- ADR corpus check (Phase 0.6 item 4): the mechanism named in the ask ("pre-drafted notice committed as a runbook/KB doc") matches no rejected alternative in `knowledge-base/engineering/architecture/decisions/`; ADR-282's addenda carry the C1 finding this text must not contradict.
- Collision precheck: no open PR other than this branch's own WIP PR #12239 names 10664; no open code-review issue body contains any of the three touched paths (Phase 1.7.5 query, `code-review` label, 200-issue scan).

### Property List (Phase 0.6b)

- **P1** — A ready user-notice text exists in the repo before any incident, so a total loss does not start from a blank page.
- **P2** — The notice names what was lost, the window, and the action the user should take.
- **P3** — The draft decides nothing about disclosure duty; it states that send conditions are the CLO's call.
- **P4** — It is committed under this repo's runbook/KB conventions (frontmatter, location, cross-links, lints).
- **P5** — It cannot contradict the C1 finding's constraints (affected-set floor, no "no record survives", no restoration promise, external-sender carve-out, aggregate-only).

### Cut List (Phase 0.6b)

- **Phrase-pinning lint / test over the notice's required sentences** → property: keeps P3/P5 wording from drifting out later → covered today by PR review on a 3-file docs diff; the file is new, so every future edit passes the same review path. Recorded as an explicit cut — revisit only if the file proves to drift.
- **Embedding the draft inside `inngest-luks-cutover-6894.md`** → rejected: that file is already the densest runbook in the corpus; the notice is a copy-paste artifact that deserves its own frontmatter and `related_issues` row. Placement recorded in `decision-challenges.md`.
- **`knowledge-base/legal/drafts/` placement** → rejected: that directory holds records of sent correspondence (`custodian: clo`, `status: sent`); this is a standing operator-facing template anchored to the runbook's loss path.

### Repo findings

- Runbook conventions: YAML frontmatter (`title`, `date`, `owners`, `category`, `tags`, `applies_to`, `related_issues`), `# Runbook: …` H1, TL;DR or purpose paragraph, cross-links by relative filename. No runbook index file exists — discovery is by filename and in-file links, so the two cross-link edits carry the findability.
- The C1 finding lives in `inngest-luks-cutover-6894.md` §562-615 (measured block + event-class table) and the 2026-10-22 marker in `knowledge-base/legal/compliance-posture.md`; the measurement record is `knowledge-base/project/specs/archive/20261022-221258-feat-one-shot-9927-inngest-luks-items-6-8b-c1/measurements.md`.
- What a "total loss" loses, in user terms (from the runbook event-class table): queued events, in-flight run state, armed reminders, approved-but-unexecuted actions, run history — NOT repositories, knowledge-base content or account data.
- `docs/legal/data-protection-disclosure.md` §2.3(o) already states all three Inngest stores are personal-data-bearing (corrected 2026-11-05, ref #9074) — the notice must not contradict it.
- No spec.md exists for this branch → `lane:` defaults to `cross-domain` (fail-closed; noted per the Save Tasks rule).

### Research mode note

This session has no subagent-spawn capability, so the Phase 1 fan-out (repo-research-analyst, learnings-researcher, functional-discovery) ran as direct repo reads/greps by the orchestrator — the findings above. External research skipped (Phase 1.6): the notice's content is fully determined by in-repo findings; no external best practice can override the C1 constraints. Plan-review panel and domain-leader spawns (Phase 2.5) likewise could not run; gaps are disclosed in `## Domain Review` and flagged for `soleur:review`-time conditional agents (user-impact-reviewer, copywriter).

## Research Reconciliation — Spec vs. Codebase

No spec exists for this branch. Verified issue/prose claims against the tree:

| Spec/issue claim | Reality on this branch | Plan response |
|---|---|---|
| Tracker lists the user-notice item unchecked | Confirmed (`- [ ]` in the issue body) | In scope — this plan |
| Orphan-sweep item reads unchecked | Stale — shipped in PR #10936 (merged 2026-10-24) | Observation only; no issue-body edit |
| "The legal question of whether and when notification is owed is routed to the CLO" | CLO determinations for this arc exist (`legal/audits/2026-11-counsel-review-10848.md`); no send-condition ruling exists for the notice itself | Draft states send conditions are the CLO's call; decides nothing |

## User-Brand Impact

- **If this lands broken, the user experiences:** a product notice that misstates their loss — e.g., "nothing was lost" while their queued draft or approved action silently never ran, or a notice naming a narrower affected set that leaves them out.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no direct data exposure (the draft contains no user data); the vector is a wrongly-worded notice — a per-user count or identifier the partial evidence cannot support, or a placeholder sent unfilled.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one user wrongly told (or wrongly not told) about their own lost work is a brand-level event by itself; `aggregate pattern` was rejected because the failure does not show up as a rate — same reasoning as the parent plan's CPO-signed threshold (PR #10652).

*CPO sign-off note:* `requires_cpo_signoff: true` is set; no subagent capability exists in this planning session to obtain the consult — `soleur:review`-time conditional agents (user-impact-reviewer at this threshold, copywriter for user-facing copy) are the coverage path, flagged for the review phase.

## Implementation Phases

### Phase 1 — Draft the notice runbook

Create `knowledge-base/engineering/operations/runbooks/inngest-store-total-loss-user-notice.md` per "New file shape" above: frontmatter, the five sections, the drafted notice with `[...]` fill fields, and the fill-field table. Constraints list precedes the notice text so an incident-time editor sees the must-nots first.

### Phase 2 — Cross-link

- `inngest-luks-cutover-6894.md`: one sentence under `### After a total loss: who tells affected users` naming the new file and that its constraints bind the notice.
- `inngest-server.md`: one Quick reference row naming the notice runbook (concern → procedure link).

### Phase 3 — Verify

Run the Acceptance Criteria commands (each is written to be executed, and each was executed once at plan time — see Research Insights / verification notes inline in the ACs).

## Files to Create

- `knowledge-base/engineering/operations/runbooks/inngest-store-total-loss-user-notice.md`

## Files to Edit

- `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` — one pointer sentence in the "After a total loss" section
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — one Quick reference table row
- `knowledge-base/project/specs/feat-one-shot-10664-inngest-user-notice/tasks.md` (pipeline artifact)
- `knowledge-base/project/specs/feat-one-shot-10664-inngest-user-notice/decision-challenges.md` (pipeline artifact)
- `knowledge-base/project/specs/feat-one-shot-10664-inngest-user-notice/session-state.md` (pipeline artifact, written by the work phase)

## Open Code-Review Overlap

None. The Phase 1.7.5 query (`gh issue list --label code-review --state open --limit 200`, jq `contains` over each planned path) returned zero matches for all three touched paths.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "a ready notice naming what was lost, the window and the action to take, so a total loss does not start from a blank page" [issue #10664] | Phase 1 + `inngest-store-total-loss-user-notice.md` (P2) | mapped |
| 2 | "The legal question of whether and when notification is owed is routed to the CLO" [issue #10664] | §Send conditions are the CLO's call (P3); AC3 | mapped |
| 3 | "commit it under this repo's runbook/KB conventions" [brief] | Frontmatter + placement + cross-links + lint ACs (P4) | mapped |
| 4 | "note it in the plan as an observation; editing the issue body is out of scope" [brief] | Overview observation block | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| New runbook `inngest-store-total-loss-user-notice.md` | "a ready notice naming what was lost, the window and the action to take" | asked |
| CLO-call caveat section | "The legal question of whether and when notification is owed is routed to the CLO" | asked |
| Constraints list (must-nots) | "commit it under this repo's runbook/KB conventions" | inferred — justification: the runbook's own C1 finding fixes these constraints; a notice violating them would contradict the KB record it lives in |
| Cross-link edits in two runbooks | — | inferred — justification: the corpus has no runbook index; without the links the artifact is unfindable at incident time |
| `Ref #10664` (not `Closes`) in PR body | — | inferred — justification: five other tracker items remain open; `Closes` would falsely resolve them |

### Split Assessment

- Subsystems touched: 1 — `knowledge-base`
- Planned files: 5 (1 create + 2 docs edits + 2 pipeline artifacts) | Estimated changed lines: ~180
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** legal

### Legal

**Status:** reviewed (orchestrator-read; no subagent-spawn capability in this session)
**Assessment:** the artifact sits one step before a legal determination — it supplies wording for a communication whose existence, audience and timing are the CLO's Art. 33/34 call. The plan therefore treats "send conditions are the CLO's call" as a hard content requirement (AC3), cites the determination homes (`legal/audits/`, `breach-register.md`) rather than making one, and keeps the notice aggregate-only per the C1 CLO rulings recorded in `compliance-posture.md`. Product domain assessed as NONE for the gate: no UI-surface file in Files to Create/Edit (mechanical override does not fire); the copy is user-facing in intent, so `soleur:marketing:copywriter` + `soleur:engineering:review:user-impact-reviewer` are flagged for `soleur:review` time rather than spawned here.

## Acceptance Criteria

- [ ] AC1 — `knowledge-base/engineering/operations/runbooks/inngest-store-total-loss-user-notice.md` exists and its frontmatter carries `related_issues` including `10664` (verified at plan time: `test -f` on the path returns absent today).
- [ ] AC2 — The file contains a copy-pasteable notice (fenced or blockquoted) naming all three required elements: what was lost, the window (incident-time `[...]` fill fields), and the action the user should take. Check: `grep -c -e 'lost' -e 'UTC\]' -e 'What to do' <file>` ≥ 3 and the block contains at least two `[` … `]` fill fields.
- [ ] AC3 — The file states that whether/when/whom to notify is the CLO's call (e.g. contains `CLO`); the notice block itself contains no Art. 33/34 or disclosure-duty assertion. Check: the words `Art. 33`, `Art. 34`, `breach` do not appear inside the notice block (they may appear in the constraints/caveat prose).
- [ ] AC4 — The constraints section names all four must-nots: the all-active-users floor (no narrower set), no "no record survives"/"nothing identifies" claim, no armed-reminder restoration promise, and the external-sender carve-out. Check: `grep -c -e 'active users' -e 'record survives' -e 're-arm' -e 'inbound' <file>` ≥ 4.
- [ ] AC5 — `inngest-luks-cutover-6894.md` "After a total loss" section links the new file (`grep -n 'inngest-store-total-loss-user-notice' that-file` ≥ 1) and `inngest-server.md` names it in the Quick reference table (`grep -n 'inngest-store-total-loss-user-notice' inngest-server.md` ≥ 1).
- [ ] AC6 — `bash scripts/markdown-lint.sh` exits 0 with the three touched runbook files in scope, and `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exits 0 (the gate's own invocation, per the CI-sentinel sharp edge — never a hand-restated file list).
- [ ] AC7 — The PR body carries `Ref #10664` and not `Closes #10664` (the tracker must stay open for the remaining items).
- [ ] AC8 — The PR description or plan records the stale-checkbox observation (orphan-sweep item shipped in PR #10936) and that the issue body was deliberately not edited.

## Test Scenarios

- Given the new runbook file, when `grep -c 'CLO'` runs, then ≥ 1 (the CLO-call caveat is present). *unit (docs)*
- Given the notice block, when greps for the forbidden claims run (`no record survives`, `will be restored`, a per-user count), then zero matches inside the block — while the constraints section's own prohibition lines still carry the tokens as documentation (the grep is scoped to the block, not the file). *unit (docs)*
- Given the two cross-link edits, when the referenced anchors are checked (`### After a total loss: who tells affected users` in `inngest-luks-cutover-6894.md`; the Quick reference table in `inngest-server.md`), then both anchors exist and each link resolves. *integration*
- Given the final diff, when `bash scripts/markdown-lint.sh` and `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` run, then both exit 0. *integration*
- Given markdownlint runs on the plan artifacts, when `npx markdownlint-cli2` runs over the plan + tasks.md, then no MD010 (tab) or MD032 (list-after-heading) findings. *unit (docs)*

## Context

- Tracker: #10664 (OPEN) — scope is the single unchecked user-notice item; five other items remain gated.
- Originating advisory: CPO, PR #10652 review 2026-10-22 — "(2) a pre-drafted user notice naming what was lost, the window and the action to take, with the legal notification question routed to the CLO" (parent plan, `knowledge-base/project/plans/archive/20261022-221258-2026-10-20-chore-inngest-luks-items-6-8b-c1-measure-and-no-fallback-plan.md` §211).
- The C1 evidence finding the notice must not contradict: `inngest-luks-cutover-6894.md` §562-615; `compliance-posture.md` 2026-10-22 marker; `knowledge-base/legal/breach-register.md` is where a determination lands if one is made.
- Sibling legal questions (citations only): #10848 (storage-limitation / Art. 17 reach — CLOSED 2026-11-02), #10849 (published-disclosure wording — CLOSED).
- `docs/legal/data-protection-disclosure.md` §2.3(o): all three Inngest stores are personal-data-bearing (corrected 2026-11-05).

## Sharp Edges applied

- PR-body reference form: `Ref #10664`, never `Closes` — tracker stays open (ops-tracker sharp edge).
- AC verification commands were each executed once at plan-write time against current tree state (existence/absence greps for AC1/AC5 targets; the markdownlint and lint-infra invocations).
- No `head`-truncated greps in absence claims; every cited path was `test -f`/grep-verified at write time.
- `lint-infra` AC uses the gate's own `--changed --base origin/main` invocation, not a hand-restated file list.
- The drafted notice keeps placeholder text out of production claims: `[...]` fill fields are clearly marked so an unfilled placeholder can never read as a fact.
- The plan's `## User-Brand Impact` section is populated (not TBD) — required for deepen-plan Phase 4.6.
