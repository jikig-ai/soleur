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

Plan: `knowledge-base/project/plans/archive/20261120-013510-2026-11-18-infra-cloudflare-migrate-terraform-to-soleur-account-plan.md`.
Rulings: `knowledge-base/project/specs/archive/20261120-013510-feat-one-shot-12931-cf-account-migration/decision-challenges.md`.
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
   enabled) follow `var.cf_account_id` and `var.cf_zone_id`, which must hold the Soleur account and zone (they do
   from the Phase 2 `flip-ids` stage; until then the validations below refuse every plan). Every
   variable-driven R2 surface (`cloudflare_r2_bucket.*`, `local.r2_s3_endpoint`, the CLA-evidence root's
   `TF_VAR_cf_account_id`) follows the new `var.cf_r2_account_id` (no default, pinned by validation to the legacy
   account). The backend endpoints are literals on the legacy account (a backend
   block cannot read a variable) and stay unchanged.
2. **Old-id validations.** `cf_zone_id` and `cf_account_id` reject the old ids (an exact-literal comparison; an
   upper-case spelling is refused by the lowercase-only 32-hex shape check, proven by tftest `expect_failures`), and
   all three ids must be 32-hex. Any plan carrying an old id fails before refresh.
   `cf_r2_account_id` is pinned to the legacy account `4d5ba6f096b2686fbdd404167dd4e125`.
3. **Migration mechanism: state-forget-then-import**, run only by the gated `cf-account-migrate` dispatch, phase by
   phase (`redirects-dns`, `zone-rest`, `tunnel`):
   - a pre-migration `terraform state pull` backup to `web-platform/backups/` in the state bucket;
   - one atomic `terraform state rm` of every non-R2 `cloudflare_*` entry whose own `zone_id`/`account_id` is an old
     id, derived from state rather than a manifest, aborting with nothing removed on any unclassifiable entry;
   - per-phase `import {}` blocks for the hand-restored objects, each required to plan as a `["no-op"]` import, plus
     creates for objects absent from the new zone. One exception (CTO ruling 2026-11-22, which supersedes for
     `cloudflare_record` only the 2026-11-19 ratification "Import + update passes the gate", under which Guard 1
     refused every import that was not a `["no-op"]`; every other resource type keeps that rule): the provider's Read
     fills `content` only when it is already set, so a `cloudflare_record` import plans an `["update"]` adding
     `allow_overwrite = false` and `content`. The gate admits exactly that shape, bound to the pinned record id and to
     a live read taken after the plan, and logs it as `import-normalize`. After an apply that carried an admitted
     record, the job re-reads every record and halts on any difference or unreadable record, which detects a bad write
     and does not undo it;
   - a phase gate on `tfplan.json` (no destroys, allow-set only, new ids only, `-replace` honoured). A create-class
     address may plan an in-place `["update"]` only when it is already in pre-plan state and, for a Cloudflare object,
     its `before` carries the NEW zone or account id; the one Doppler member must plan exactly the new zone id (CTO
     ruling 2026-11-20, review fork 1). It is the fix-forward path for a rule the `redirects-dns` apply left broken;
   - a migration-in-progress predicate, the last step of `.github/actions/infra-credentials`, that is deny by
     default: every workflow loading those credentials is refused unless the predicate names it exempt (the plan-only
     and migrator workflows, and callers of other roots). It refuses until every phase address is in state, no
     non-R2 entry carries an old id, no import-class `cloudflare_record` is `unnormalized` (in state without a non-empty
     string `content`, which is what a stopped apply leaves on the records it did not reach) and the tunnel is in state
     on the new account; `web-host-replace web-2` is the one exception once the tunnel is in state, and it checks the
     tunnel alone. A rehearsal (`rehearsal=true`) writes nothing to R2.
4. **Plan-tier gates.** `cf_zone_plan_pro` (default false) nulls the Super Bot Fight Mode fields;
   `cf_load_balancing_enabled` (default false) count-gates the load balancer, pool, monitor and health-alert policy,
   and `cf-lb-overlay.yml` refuses while it is false; `cf_zone_dnssec_enabled` (default false) count-gates DNSSEC,
   which is deferred rather than enabled mid-cutover (#12982). Load Balancing on the new account is the operator
   decision tracked by #12983. These three flags and `cf_migration_import_app` are locked to `false` by `variables.tf`
   validations (CTO ruling D9): turning one on is a reviewed PR that deletes its validation, never a tfvar override.
   > **Amended 2026-11-23 (#12937, PR2):** PR2 deleted the `cf_migration_import_app` validation by that procedure. Its
   > default stays `false`, and only the tunnel phase's plan passes `-var=cf_migration_import_app=true`.
5. **The tunnel is recreated, not moved.** A tunnel token reaches a host only through create-time user_data, so the
   new tunnel is created first and `web-host-replace web-2` delivers its token (ADR-304's mechanism). web-1 is not
   touched; `app.soleur.ai` serves from its plain proxied A record throughout.

Status flips to `accepted` when the routine `manual-rerun` apply is green after the tunnel phase; that flip lands in
the cleanup PR.

## Consequences

- One Doppler flip moves the root, and the validations make a half-flip or a revert-by-flip fail loudly. There is no
  full revert (CTO ruling D4, 2026-11-19): on any failure the migration halts at the last verified phase and fixes
  forward. The `_PREV` id restore is allowed only until a `rehearsal=false` `redirects-dns` run prints
  `cf-state-migrate backup=uploaded` (the forget is then committed, even if the gate refuses; CTO ruling 2026-11-20,
  review fork 2), and it leaves the root closed; after that, restoring ids, reverting PR1 or pushing the backup over live state would aim Terraform at the moved zone.
  The runbook's `## Halt` section is the operator text.
- A ruleset create is a whole-list PUT of its phase entrypoint, so creating `seo_config_settings` (and every other
  entrypoint) in the new zone would overwrite any rules a hand-made entrypoint already holds. The migrate job guards
  that by running the ADR-136 pre-apply entrypoint gate on the new zone after the phase gate and before any apply, in
  the rehearsal too (CTO ruling D2); a populated entrypoint refuses `entrypoint-gate-refused` and prints the import
  block to commit instead.
- Between PR1's merge and the flip, and again until the tunnel phase completes, routine plans of this root fail by
  design; `scheduled-terraform-drift.yml` stays red. These are listed as expected reds.
- `cloudflare_zone_settings_override` has no importer: its create snapshots the new zone's hand-restored settings,
  and a future destroy reverts to that snapshot, not to the old Pro zone's.
- `app.soleur.ai` loses load-balancer steering while LB is gated off: every request and every Inngest step call lands
  on web-1 through the A record. ADR-068's web-2-at-weight-1 serving state does not hold until LB is re-enabled
  (#12983).
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
inherit). NFR-031 (Periodic Backup & Recovery): the pre-migration state backup is disaster-recovery evidence for the
forget, never pushed back as state (D4); it holds the same secrets as live state, and every
`pre-cf-account-migration-*` object is deleted, every version, in the cleanup PR.

## Principle Alignment

- AP-001 (Terraform-only): Aligned, with four recorded exceptions. Every hand-restored object is adopted by import;
  the dashboard acts are token mints and revokes, which have no API path for a Soleur token (ADR-130). The live-zone
  edits of 2026-11-19 (six TXT records rewritten unquoted and the comments on three incident-time records cleared, so
  every record's live values match `dns.tf`) were hand edits to records Terraform then adopts unchanged. Phase 0c, a
  hand-made noindex entrypoint, is no longer recommended (D2) and would be adopted by an import block if run.
  The third exception (CTO ruling 2026-11-20) is a bounded break-glass: when the `redirects-dns` verify fails with
  the product down, the owner may make one dashboard edit of one Terraform-managed rule on the NEW zone only; the
  fix-forward PR carries that value and the next gated re-dispatch must plan that address as a no-op.
  The fourth (CTO rulings S4 and F7, 2026-11-23) is a bounded hand edit of a DNS record: when a re-read or a gate
  refusal names a live difference, the owner may authorize one edit of the named field on the NEW zone, to the value in
  the record's `dns.tf` block. For `pages_apex` and `www` that value is the `soleur-docs` Pages project's `subdomain`,
  read and checked per S4, and a failed read or a mismatch means no edit. A deleted record may be recreated the same
  way, and its path back into state needs a reviewed PR and a CTO ruling. A `settings`, `data`, `after`, `tags:absent`
  or `content:quoted-equal` difference gets no edit and stops for an owner decision.
- AP-002 (No SSH state mutation): Aligned. The migration job uses only the Cloudflare API; the host change is an
  immutable replace.
- AP-003 (R2 remote backend): Aligned. The backend and its endpoint are unchanged; ADR-006 stands.
- AP-008 (Doppler for secrets): Aligned. Every new token goes stdin-only into Doppler and is never printed.
