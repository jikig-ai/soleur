---
name: dark-launch-pr-must-exclude-operator-prerequisite-infra
description: A dark-launch (flag-off) PR must not carry infra changes that depend on operator-provisioned prerequisites — the merge-triggered per-PR terraform apply attempts them and fails (destroy-guard or missing-config), even though the code path is inert
metadata:
  type: project
  issue: 5274
  pr: 5918
  hotfix_pr: 5924
  tags: [terraform, dark-launch, ci, infra, cutover, destroy-guard, multi-host]
---

# Dark-launch PRs must exclude operator-prerequisite infra

## What happened

Sub-PR 3.D (#5918) was a **dark launch**: the GA flag ships OFF, so every new code
path is inert. That correctly makes the *application* merge behavior-neutral. But the
PR also carried two **infra** changes whose apply depends on operator-provisioned
prerequisites that do not exist until the maintenance-window cutover:

1. **`dns.tf` `cloudflare_record.app` → `for_each = var.web_hosts`** — a multi-host
   round-robin rewire. Converting a singleton resource to a keyed (`for_each`) address
   is a **destroy + recreate** in terraform's eyes (no `moved` block spans the
   singleton→`["web-1"]` address change for a CF record with no stable import id), and
   the new `["web-2"]` instance references `hcloud_server.web["web-2"]` which is not yet
   provisioned.
2. **`-target=doppler_service_token.git_data`** in `apply-web-platform-infra.yml` — mints
   a scoped token into a `prd_git_data` Doppler config that is an operator precondition
   (created by hand before the cutover, like `prd_kb_drift_walker`).

The merge to `main` triggers `apply-web-platform-infra.yml`, whose plan-stage
**destroy-guard** counts destructive changes across a full plan. My `for_each` produced
`1 to destroy` (`cloudflare_record.app`) → the guard failed the whole workflow →
`Terraform apply: skipped`. **No prod impact** (nothing applied, DNS untouched, flag
off, `/health` 200), but the infra-apply workflow went red and would re-fail on *every*
subsequent infra PR until fixed.

## The lesson

**A flag being OFF makes the CODE inert; it does NOT make the INFRA inert.** The
merge-triggered per-PR `terraform apply` runs regardless of any application flag. So a
dark-launch PR must only carry infra that is **safe to apply per-PR from CI right now** —
i.e. that does not depend on a host, volume, network, or Doppler config the operator has
not yet created. Anything that needs an operator-provisioned prerequisite belongs in the
operator's **full maintenance-window apply** (the cutover), not the merge-apply.

Concretely, before putting an infra change in a dark-launch PR, ask:
- Does this resource reference another resource that only exists after an operator apply
  (a new host, a placement group, a for_each peer)? → defer to the cutover.
- Does it write to a Doppler config / GitHub secret / external resource the operator must
  create first? → defer to the cutover (and keep it out of the CI `-target` set).
- Is it a `for_each`/count conversion of an EXISTING live resource? → it is a
  destroy+recreate unless a `moved` block covers it; the destroy-guard will block it.
  For a dark launch, prefer leaving the live resource untouched and doing the rewire in
  the cutover's full apply.

The **destroy-guard is the backstop that caught this** — it is working as designed;
`[ack-destroy]` in the merge commit is the deliberate override, and a dark-launch PR
should almost never need it.

## The fix (hotfix #5924)

- Revert `dns.tf` to the single `web-1` record; document the `for_each` rewire as an
  operator cutover step (runbook §3).
- Drop `-target=doppler_service_token.git_data` from the apply workflow; classify it in
  `OPERATOR_APPLIED_TOKEN_EXCLUSIONS` in `terraform-target-parity.test.ts` (an
  operator-applied token minted into an operator config for host consumption — NOT a
  CI-published `github_actions_secret`, so #5566's "must be CI-targeted" rule does not
  apply), with a non-vacuity guard.
- The LUKS volume/key/attachment were **already** correctly in `OPERATOR_APPLIED_EXCLUSIONS`
  (they never entered the CI apply) — only the DNS rewire and the CI-targeted token were
  the miss.

## Corollary: distinguish self-introduced from pre-existing merge-apply red

When triaging a red merge-apply after your PR, check whether the workflow was ALREADY
red on the prior commit (`gh run list --workflow=<wf> --branch main --limit 8`). Here,
`apply-web-platform-infra.yml` had been failing since ≥3.B on two 3.A/3.B
operator-maintenance-window resources — `hcloud_server.web["web-2"]` (cloud-init
`user_data` > Hetzner's 32 KB limit) and `hcloud_server.web["web-1"]`
(placement-group attach needs the server offline). My 3.D dns `for_each` destroy
*masked* those (the plan-stage destroy-guard failed before `apply` ran); removing it
un-masked the pre-existing failures. The fix scope is then: fix ONLY what your PR
introduced (`wg-when-tests-fail-and-are-confirmed-pre-existing`), and FILE the
pre-existing failure as a tracked issue (#5925) rather than absorb it into your hotfix.
The `-target=cloudflare_record.app` in the CI apply transitively drags the whole
`hcloud_server.web` for_each into the plan — a targeted resource pulls its dependencies,
so "operator-applied" exclusion of a server is not honored if a *targeted* record
references it.

**Prevention:** relates to `wg-dark-launch-deploy-gates` and
`wg-after-a-pr-merges-to-main-verify-all` (a red infra-apply after merge is a must-fix,
not a shrug) and `wg-when-tests-fail-and-are-confirmed-pre-existing` (file, don't absorb). A candidate workflow gate: at ship time, if a dark-launch/flag-off PR's
diff touches `apps/web-platform/infra/*.tf` with a `for_each`/`count` conversion of an
existing resource OR adds a `-target=` for a resource in a not-yet-created Doppler
config, WARN that the change will hit the merge-apply destroy-guard / missing-config and
should be deferred to the operator apply.
