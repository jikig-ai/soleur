# Decision Challenges — feat-one-shot-6712-6718-web1-birth-path-coherence-guards

Persisted by `plan-review` (headless). `ship` Phase 6 renders these into the PR body and files
an `action-required` issue. Not auto-applied: each contradicts the operator's stated direction.

---

## UC-1 — Five of seven reviewers recommend cutting Half B (#6712) from this PR entirely

> **RESOLVED 2026-07-19 — operator ruled Option 2: ship Half A alone; Half B cut to a follow-up.**
> The panel's finding was upheld, and the operator independently confirmed the zombie claim
> (`variables.tf` records web-2 RETIRED 2026-07-17 #6538; `web_2_recreate`'s gate requires
> `web2_server_replaced==1`, unsatisfiable out of state). Plan amended to revision 3 and renamed
> to `2026-07-19-fix-warm-standby-web1-birth-halt-plan.md`. #6712 stays OPEN with `Refs` + a
> design record; its substance is carried by the CPO C2 issue. The force-replace sequencing gate
> was restated (it can no longer key on "#6712 closed") — see plan AC17.

**decisionClass:** user-challenge
**Operator's stated direction (the default):** "Close the two unguarded web-1 birth paths … #6712
and #6718, in ONE PR." Half B is half the brief.

**What the panel found.** Independently, and each verifying against source:

- **dhh-rails-reviewer** — "Cut Half B entirely." The inline block it extracts is 6 lines, and the
  same step *already* calls an extracted script (`resolve-web1-known-good-tag.sh`), so
  "inline-only" is a cosmetic complaint dressed as a structural one. Worse, the refactor touches
  the `-replace`-the-sole-web-host path for zero behaviour change.
- **code-simplicity-reviewer** — "Drop, not defer." A separate PR still costs the script, suite,
  registration and reviewer attention while shipping a resolver with no consumer. Extracting now
  means guessing the interface for a caller that does not exist.
- **architecture-strategist** — falsified the plan's justification: `web_2_recreate` (Half B's
  claimed "one real call site") is a zombie for the *same* reason as `warm_standby` — every
  address keys `web-2` off `var.web_hosts`, and its gate requires `web2_server_replaced==1`,
  unsatisfiable when the instance is absent from state.
- **cto** — same finding: "Half B has *zero* live call sites, not one."
- **spec-flow-analyzer** — Half B builds the resolver for the operator-local apply flow and then
  wires it to `web_2_recreate`, which was **already digest-pinned**. The genuinely exposed
  consumer gets nothing.

**Counter-argument for keeping it (why the plan did not auto-cut):** Half A closes the reachable
risk by prevention; Half B is the only artifact that would let a *future* create path verify
coherence rather than merely be forbidden. Cutting it leaves #6712 with no deliverable at all.

**Options:**
1. **Keep both halves** (current plan, operator's direction) — Half B ships honestly reframed as
   extraction + tests with zero live consumers.
2. **Cut Half B to a follow-up PR** — ship Half A alone; #6712 keeps its `Refs` and its revisit
   comment.
3. **Drop Half B until #6459** — no code; record the design on #6712 only.

**Blocking?** No. The plan proceeds on option 1 (the operator's direction) with Half B's
overclaims corrected.

---

## UC-2 — CTO recommends extracting the guard to a shared lib; the plan keeps it inline

**decisionClass:** taste
**Plan's choice:** add ~5 lines inline to `warm_standby`, leave `apply`'s guard untouched.

**CTO's evidence:** `apply-web-platform-infra.yml` already sources **11 gate libs across 7 files**;
every dispatch job *except* `apply` and `warm_standby` uses the sourced-gate pattern. And
`tests/scripts/lib/web2-recreate-gate.sh` already implements the exact `^[0-9]+$` validation loop
over all counters that R-A1 exists to add — so extraction would fix R-A1 structurally, for every
future counter, and delete the need for a parity test. DHH independently agreed the guard is the
extraction that earns its keep.

**Why the plan declined:** extraction requires editing the `apply` job's guard — the per-PR merge
gate for the whole repo. A defect there either halts every merge or, worse, fails open. That is a
materially larger blast radius than "wire an existing counter into a sibling job", and the brief
scoped #6718 as WIRING. Recorded as the recommended follow-up with CTO's evidence attached.

**Blocking?** No.

---

## UC-3 — CPO sign-off conditions C1 and C2 (blocking per CPO; folded into the plan)

**decisionClass:** user-challenge (they expand scope beyond the brief)

CPO signed off **WITH CONDITIONS**, two of them blocking:

- **C1** — AC10 must not present the "no automated web-host birth path" state as settled. The new
  remediation text must record that this state violates
  `hr-fresh-host-provisioning-reachable-from-terraform-apply` and name an owner.
- **C2** — file a distinct issue, *"web-1 has no executable birth path"*, **not** #6459. CPO
  verified #6459 is blocked by #6570, whose own blocker is **Hetzner cx33/cax11 stock
  availability** — so "revisit when #6459 lands" is a chain with no committed end.

CPO also surfaced a DR fact the plan had not: web-1's live host was armed by SSH `terraform_data`
provisioners, while a *reborn* host would be armed by cloud-init. After this PR the cloud-init
arming path can never execute, so it is never validated and drifts silently — discovered only
during a real DR event.

**Both folded into the plan** (AC10 rewritten; C2 added to Deferrals + AC18). Flagged here because
they expand scope past the brief and the operator may prefer them as separate follow-ups.

**C3 (non-blocking):** `server.tf` calls web-1 "cx33-unrebuildable" while #6538's table says
`hel1 → rebuildable_in_place_today: YES`. One is wrong. Folded in as a Phase 3 doc-coherence item.
