# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-27-feat-git-data-host-birth-route-plan.md
- Status: complete

### Errors
Two write attempts blocked by the `iac-plan-write-guard` PreToolUse hook — both correct catches on
descriptive prose. Resolved by rewording, not acking, so the gate stays armed for the next author.
The first block was load-bearing: investigating it revealed `doppler_config` exists in the installed
provider, which converted the plan's only operator step into a Terraform resource and left
`Post-merge (operator)` genuinely empty.

One agent (`terraform-architect`) returned a preamble with no findings; the planner read the provider
schema directly rather than re-spawning.

### Task-brief premises found false (corrected in plan, re-verified by parent this session)
- `web-host-birth-gate.sh` DOES exist under `tests/scripts/lib/`. The brief asserted no
  `web-host-create` gate file existed and the gate was inline YAML — wrong, and it changed the
  plan's shape from inline-job to sourced gate file. Cause: parent's grep pattern matched
  `host-create|host-replace|stock-preflight` and the file is named *birth*.
- `run-registered-suites.sh` derives its suite list from the workflow file and is scoped to
  `apps/web-platform/infra/`; it structurally cannot run a `tests/scripts/` suite. The brief's
  instruction to register there would have been a silent no-op — the exact failure class the
  instruction existed to prevent.
- The `apply_target` enum has 23 targets, not the 10 the parent's truncated grep displayed.
- The brief supplied a stale line citation that plan v1 propagated unverified — the precise defect
  class this plan is about.

### Decisions
- Requirement arm split by entailment. Three reviewers independently found plan v1's arm would both
  permanently wedge the documented retry path and pass a plan causing irreversible LUKS data loss.
  The sibling gate states the governing rule verbatim; v1 had copied its shape without its reasoning.
- `prd_git_data` became Terraform, not an operator step — verified absent in Doppler, and
  `doppler_config` plus the `zot-registry.tf` precedent make it automatable.
- Cut `doppler_secret.git_data_ssh_host` (Defect 2b) over CPO's advice — a feasibility regression
  (ADR-084's sanctioned exception to "surface, don't decide"): it would make
  `terraform-target-parity.test.ts` RED on landing, and the natural remedy drags
  `hcloud_server.git_data` into the per-merge plan, wedging every merge to main. Dissent in DC-3.
- Closed two gate holes: v1 permitted an `update` adding inbound rules to the deny-all firewall,
  and had dropped the LUKS-passphrase invariant.
- Found a defect neither the issue nor any reviewer caught in full: `hcloud_server.git_data`
  depends on the Doppler *token* but has no edge to the *secret* that token reads, so Terraform may
  boot the host before the LUKS key exists — and per the known trap, that fails silently.

### Operator decisions
- **DC-1 — RESOLVED by operator this session: ship the route now, interlocked.** Enum option, job,
  gate, suite and runbook all land in #6977, held from use by the birth-readiness interlock that
  #6982 flips. Matches the plan's existing disposition; no re-plan required.
- DC-2 (`taste`) and DC-3 (`user-challenge`) remain recorded per ADR-084 for the PR body and the
  `action-required` issue at ship.

### Out of scope, recorded for follow-on
- `git-data-cutover.sh` drives a `soleur-web.service` unit that does not exist, at both its flip and
  its rollback sites — that cutover path would fail today. Belongs to #5274/#6982.
- `apps/web-platform/infra/web-git-data-probe.sh:13` carries a stale citation
  (`git-data.tf:338-341`; the TODO is at 342-345). Deliberately NOT fixed here — the file feeds
  `terraform_data.git_data_probe_install`, which sits in the per-merge SSH apply's `-target` list on
  a step with no destroy-guard, so touching it would root-SSH the live serving host. Rides along
  with #6982's log shipper.

### Components Invoked
`soleur:plan` → `soleur:plan-review` (7 agents: dhh-rails-reviewer, kieran-rails-reviewer,
code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer, cto, cpo) →
`soleur:deepen-plan` (3 agents + halt gates 4.5–4.10, 4.55). Plus `Explore` ×3 and
`learnings-researcher` during research.
