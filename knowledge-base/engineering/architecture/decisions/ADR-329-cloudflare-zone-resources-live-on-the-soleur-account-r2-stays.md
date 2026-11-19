---
title: Cloudflare zone resources live on the Soleur account; R2 stays on the legacy account
status: adopting
date: 2026-11-19
issue: 12931
amends: [ADR-068, ADR-321]
supersedes: none
related_adrs: [ADR-006, ADR-114, ADR-143, ADR-194, ADR-304]
related_runbooks:
  - knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md
---

# ADR-329: Cloudflare zone resources live on the Soleur account; R2 stays on the legacy account

Plan: `knowledge-base/project/plans/2026-11-18-infra-cloudflare-migrate-terraform-to-soleur-account-plan.md`.
Rulings: `knowledge-base/project/specs/feat-one-shot-12931-cf-account-migration/decision-challenges.md`.
Incident: `knowledge-base/engineering/operations/post-mortems/soleur-ai-cloudflare-account-move-outage-2026-11-18-postmortem.md`.

## Context

On 2026-11-18 the `soleur.ai` zone moved from the legacy Cloudflare account (`4d5ba6f0…`, old zone `5af02a2f…`,
now `status=moved`) to a new Soleur account (`66d4f93f…`, zone `951ce525…`). Records, the site and sign-in were
restored by hand. Terraform still addressed the old ids, so the redirect and SEO rulesets, the noindex header, the
AI-crawler WAF allowlist, the Pages project and the deploy/ssh/registry tunnel hosts were all missing from the new
zone, and the routine apply could not repair them: it verifies through the dead tunnel and HALTs on the deploy-policy
create the new account needs.

Two facts shape the decision:

- **R2 did not move.** The Terraform state backends of every root (8 backend blocks), the LUKS header escrow buckets,
  the privileged state bucket and the CLA-evidence object-locked bucket all live on the legacy account, and
  `var.cf_account_id` homed three of them. A plain flip of that variable would have planned a destroy-and-recreate of
  sole-copy buckets in the new account.
- **`zone_id` and `account_id` are ForceNew, and an `import {}` block is ignored while its address is in state**
  (measured on Terraform 1.17.2; CI pins 1.10.5, same behaviour since 1.5). So the ids cannot be flipped under a
  normal apply (it would destroy in the moved zone, which must never be mutated), and imports alone cannot re-point
  the old entries.

## Considered Options

- **Option A: split the account variable; one Doppler flip guarded by state-forget-then-import (chosen).**
  Pros: one flip, fail-closed against the old ids, R2 untouched, every hand-restored object adopted without a
  rewrite. Cons: needs a dedicated, temporary dispatch job, gate and predicate that the cleanup PR deletes.
- **Option B: flip the ids and let a normal apply converge.** Rejected: ForceNew plans destroys in the moved zone and
  creates that collide with the hand-restored records.
- **Option C: move R2 to the Soleur account too.** Rejected: 8 backend endpoints, the LUKS header escrow (a mis-pointed
  endpoint strands a fresh host's header) and an object-locked legal-evidence bucket, for no user-visible benefit.
- **Option D: parallel `*_soleur` variables, migrated file by file.** Rejected: invites mixed-account plans and
  doubles the variable surface.
- **Option E: `removed {}` blocks plus renaming every resource.** Rejected: cannot tell old entries from new ones, and
  renames about 60 addresses and about 94 test references.
- **Option F: buy Pro and Load Balancing on the new account to keep parity.** Not a technical choice; the operator
  money rows default to staying on Free and deferring Load Balancing.

## Decision

1. **Account split.** Zone- and account-bound Cloudflare resources (DNS records, zone and account rulesets, lists,
   Pages, the tunnel, Access apps, policies and service tokens, notification policies, and the load balancer when
   enabled) follow `var.cf_account_id` and `var.cf_zone_id`, which hold the Soleur account and zone. Every R2 surface
   (`cloudflare_r2_bucket.*`, `local.r2_s3_endpoint`, the backend endpoints, the CLA-evidence root's
   `TF_VAR_cf_account_id`) follows the new `var.cf_r2_account_id` (no default), which holds the legacy account.
2. **Old-id validations.** `cf_zone_id` and `cf_account_id` reject the old ids (compared on `lower()`, proven by
   tftest `expect_failures`). Any plan carrying an old id fails before refresh.
3. **Migration mechanism: state-forget-then-import**, run only by the gated `cf-account-migrate` dispatch, phase by
   phase (`redirects-dns`, `zone-rest`, `tunnel`):
   - a pre-migration `terraform state pull` backup to `web-platform/backups/` in the state bucket;
   - one atomic `terraform state rm` of every non-R2 `cloudflare_*` entry whose own `zone_id`/`account_id` is an old
     id, derived from state rather than a manifest, aborting with nothing removed on any unclassifiable entry;
   - per-phase `import {}` blocks for the hand-restored objects, each required to plan as a pure `["no-op"]` import,
     plus creates for objects absent from the new zone;
   - a phase gate on `tfplan.json` (no destroys, allow-set only, new ids only, `-replace` honoured);
   - a migration-in-progress predicate that refuses every other plan-capable job until the tunnel is in state on the
     new account. A rehearsal (`rehearsal=true`) writes nothing to R2.
4. **Plan-tier gates.** `cf_zone_plan_pro` (default false) nulls the Super Bot Fight Mode fields;
   `cf_load_balancing_enabled` (default false) count-gates the load balancer, pool, monitor and health-alert policy,
   and `cf-lb-overlay.yml` refuses while it is false; `cf_zone_dnssec_enabled` (default false) count-gates DNSSEC,
   which is deferred to a follow-up rather than enabled mid-cutover.
5. **The tunnel is recreated, not moved.** A tunnel token reaches a host only through create-time user_data, so the
   new tunnel is created first and `web-host-replace web-2` delivers its token (ADR-304's mechanism). web-1 is not
   touched; `app.soleur.ai` serves from its plain proxied A record throughout.

Status flips to `accepted` when the routine `manual-rerun` apply is green after the tunnel phase; that flip lands in
the cleanup PR.

## Consequences

- One Doppler flip moves the root, and the validations make a half-flip or a revert-by-flip fail loudly. The default
  after the flip is fix-forward; the full revert (git revert, `_PREV` restore, `state push -force` of the backup) is a
  separate owner-authorized act documented in the runbook.
- Between PR1's merge and the flip, and again until the tunnel phase completes, routine plans of this root fail by
  design; `scheduled-terraform-drift.yml` stays red. These are listed as expected reds.
- `cloudflare_zone_settings_override` has no importer: its create snapshots the new zone's hand-restored settings,
  and a future destroy reverts to that snapshot, not to the old Pro zone's.
- `app.soleur.ai` loses load-balancer steering while LB is gated off: every request and every Inngest step call lands
  on web-1 through the A record. ADR-068's web-2-at-weight-1 serving state does not hold until LB is re-enabled.
- The adopted config ruleset id ADR-321 cites is no longer imported; Terraform creates the config rules in the new
  zone, and the Origin CA certificate is re-minted from the new zone before the old one can be revoked at zone
  deletion.
- The single `cloudflare` node in the C4 model now spans two accounts; the boundary is stated in its description
  rather than drawn.
- Old-account objects the forget leaves behind (LB monitor and pool, service tokens, Access objects, lists, the
  account ruleset, the old tunnel) are deleted by name in the cleanup PR, one owner go each. Old-zone objects are never
  touched.

## Cost Impacts

Neutral to slightly lower. The old zone's Pro plan cost $0; the new zone stays on Free (all rule counts fit the Free
caps; only Super Bot Fight Mode, configured to `allow`, is lost). Load Balancing (about $5/mo base) is deferred.
R2 billing is unchanged because R2 did not move. The expense ledger is updated in the cleanup PR.

## NFR Impacts

NFR-014 (Externalized Environment Configuration): unchanged in tier; the ids stay in Doppler `prd_terraform`, and the
runtime `CF_ZONE_ID` becomes Terraform-managed in `prd` (branch configs are written explicitly, since they do not
inherit). NFR-031 (Periodic Backup & Recovery): the pre-migration state backup is the recovery point for the forget;
it holds the same secrets as live state and is deleted, every object version, in the cleanup PR.

## Principle Alignment

- AP-001 (Terraform-only): Aligned. Every hand-restored object is adopted by import; the only dashboard acts are
  token mints, which have no API path (ADR-130).
- AP-002 (No SSH state mutation): Aligned. The migration job uses only the Cloudflare API; the host change is an
  immutable replace.
- AP-003 (R2 remote backend): Aligned. The backend and its endpoint are unchanged; ADR-006 stands.
- AP-008 (Doppler for secrets): Aligned. Every new token goes stdin-only into Doppler and is never printed.
