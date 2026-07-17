---
branch: feat-grok-phase2-open-weight-gpu
issue: 6546
pr: 6597
plan: knowledge-base/project/plans/2026-07-17-feat-phase2-open-weight-gex-gpu-dogfood-plan.md
lane: cross-domain
status: pending
---

# Tasks: Phase 2 open-weight GEX GPU dogfood (#6546)

**Do not order GPU without spend ack + stock + license.** Pre-merge work is artifacts only.

## Phase 1: Setup / ledger

- [ ] 1.1 Add GEX expense rows to `knowledge-base/operations/expenses.md` as `approved-not-billing` (#6546, kill criteria, R&D)
- [ ] 1.2 Document setup fee / IPv4 notes without double-counting
- [ ] 1.3 Edit `spec.md` close semantics: no merge-close of #6546 (`Ref` until post-soak)

## Phase 2: Core — runbook

- [ ] 2.1 Expand runbook Phase 2: architecture, co-location, Approach A
- [ ] 2.2 Fix expenses path to `knowledge-base/operations/expenses.md`
- [ ] 2.3 Order checklist gates 0–3 (Robot-not-Cloud, spend, stock, license) + STOP language
- [ ] 2.4 Forbidden configs (public Ollama, remote base_url, product→GEX)
- [ ] 2.5 Bootstrap invoke docs; license memo steps; config.toml live block
- [ ] 2.6 Measure path: workspace clone, loopback preflight, three classes, YOLO off
- [ ] 2.7 Comparison table skeleton (Phase 1 baseline + empty Phase 2 + brand ban)
- [ ] 2.8 Kill criteria, 14-day clock, smoke-fail 48h disposition, Robot cancel destroy vs Phase 1 TF
- [ ] 2.9 Verify CLI tokens with source citations

## Phase 3: Core — bootstrap + tests

- [ ] 3.1 Create `scripts/dogfood/grok-gpu-bootstrap.sh` (thin: NVIDIA detect, Ollama loopback, license-ok pull, Grok, config, workspace clone, health)
- [ ] 3.2 Create `scripts/dogfood/grok-gpu-bootstrap.test.sh` (`bash -n`, loopback, license gate)
- [ ] 3.3 Confirm `scripts/dogfood/grok-measure.test.sh` still passes

## Phase 4: Core — ADR

- [ ] 4.1 Author short ADR-118 (provisional ordinal) Robot dogfood outside Cloud TF + isolation non-edges
- [ ] 4.2 Do **not** edit C4 this PR (deferred)

## Phase 5: Testing / verification (pre-merge)

- [ ] 5.1 AC1–AC10 green against worktree
- [ ] 5.2 `variables.tf` still rejects GEX types
- [ ] 5.3 PR body uses `Ref #6546` not `Closes`

## Phase 6: Post-merge operator (after gates — not in merge critical path)

- [ ] 6.1 Spend ack + stock + license recorded on #6546
- [ ] 6.2 Order GEX44; expense → `active`; stamp IP + order id + `billable_from:`
- [ ] 6.3 Bootstrap; model pull; smoke Grok→Ollama (AC11b)
- [ ] 6.4 Three-class measure + table on #6546
- [ ] 6.5 Cancel ≤1 week or re-approve; expense → `retired`; cost-model if active
- [ ] 6.6 Close #6546 only after AC11–AC15
