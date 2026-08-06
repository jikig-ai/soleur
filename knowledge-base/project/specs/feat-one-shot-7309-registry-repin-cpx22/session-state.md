# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-08-06-chore-repin-registry-host-cx23-to-cpx22-plan.md`
- Status: complete

### Errors
None. Three findings corrected in-plan rather than inherited:

- **#7309's premise is false.** Live Hetzner API, `.server_types.available`, 3 samples on
  2026-08-06: `cx23` (id 114) is AVAILABLE in `hel1-dc2`, `nbg1-dc3`, `fsn1-dc14` — as is
  `cx33` (id 115), which falsifies a repo-wide "three grandfathered hosts" claim in four
  files. `cax11` (id 45) genuinely remains unavailable and is pinned as a must-survive claim.
- **Two of #7309's own file claims are false.** `tests/scripts/lib/stock-preflight-gate.sh`
  contains ZERO `cx23` (fully parameterised); the workflow's hits are at 2090/2115/2124/2142,
  not the 2085/2094 the issue names, and the type is derived at runtime via `read_default`.
- **A P0 in the plan's own first draft**, caught by review: the `discoverability_test`
  printed the whole `default = …` line and preflight Check 10 substring-matches, so
  `default = "cx23" # was cpx22` would have PASSED on a reverted default. Replaced with a
  comment-stripping, value-extracting form. Re-verified independently by the orchestrator on
  three arms (current `cx23`; spoof rejected; post-fix `cpx22` matches).

### Decisions
- **Rationale of record is stock VOLATILITY, not unorderability.** The falsified claim is
  never restated in the plan, the variable description, or any artifact. This directory is
  now scanned by the ADR-166 causal-claim lint (shipped earlier this session as #7310), so
  repeating a measured-false premise here would be the exact defect that lint exists to stop.
  Note the lint catches `echo`/`printf` messages mechanically but NOT `.tf` comment prose,
  which is where this defect would actually land — so the discipline is manual here.
- **Q1 (replace vs in-place `server_type`) deliberately left open and unmeasured.** The repo
  contradicts itself (ADR-096 vs `variables.tf` + the destroy-guard's `reboot_updates`
  counter). A `terraform plan` would be CONFOUNDED by the already-pending replace — returning
  `["delete","create"]` regardless — and would have manufactured a false "ForceNew confirmed"
  into an ADR that a future one-way recreate would cite. Routed to #7287 under a binding
  Q1-independence invariant.
- **Scope cut 15 files → 12, 20 ACs → 17**, measured against the closest precedent
  (`31092749f`, 7 files).
- **`## Downtime & Cutover` added** — deepen-plan Phase 4.55 fired on the `server_type`
  change. Blue-green is the right shape but blocked: `10.0.1.30` is baked into ~20 consumer
  sites, and ADR-096 clause (g) already names this as unowned (#6126, OPEN). The plan records
  the evaluation and hands it over rather than pretending to close it.
- **Cost recorded as declared-vs-billing, not overwritten.** +€14.00/mo, €168/yr, 3.55×;
  billing does not move until the apply, so overwriting the `active` row would overstate burn
  (the defect #6453 corrected). The +6.77% COGS shift is below the 10% threshold, so
  `cost-model.md` keeps its subtotals.

### Carry into /work
- Phase 0.1 MUST re-probe stock and **stop rather than silently fall back** if `cx23` has
  gone unavailable again — that would make this plan's corrected premise stale in turn.
- The plan schedules NO apply and is merge-inert by construction.

### Components Invoked
`soleur:plan`, `soleur:deepen-plan`; agents: `kieran-rails-reviewer`, `code-simplicity-reviewer`,
scoped advisor consult (ADR-083), 2× `Explore`, 1× verify-the-negative sweep.
Halt gates: 4.5 (no trigger, both arms verified), 4.6 PASS, 4.7 PASS, 4.8 PASS,
4.9 (no UI surface), 4.10 PASS, **4.55 FIRED → section added**.
