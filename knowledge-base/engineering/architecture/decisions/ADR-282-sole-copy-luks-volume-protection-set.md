---
title: A sole-copy LUKS volume gets delete protection plus prevent_destroy on the volume, its passphrase pair and the Doppler cascade parents; the sanctioned-replace attachment stays unpinned
status: adopting
date: 2026-10-10
supersedes: none
amends: none
issue: 9879
related: [9879, 9927, 8285, 6894, 9786, 9703, 8316, 9348, 9925]
related_adrs: [ADR-142, ADR-263, ADR-119, ADR-006]
tags: [infrastructure, inngest, luks, terraform, key-loss, sole-copy, doppler]
brand_survival_threshold: single-user incident
---

# ADR-282: A sole-copy LUKS volume gets delete protection plus `prevent_destroy` on the volume, its passphrase pair and the Doppler cascade parents; the sanctioned-replace attachment stays unpinned

## Status

**Adopting - 2026-10-10 (#9879, PR #9925).** This ADR describes the state the decision reaches when PR #9925 is merged,
the merge's per-merge apply (`apply-web-platform-infra.yml`) has landed one in-place update on
`hcloud_volume.inngest_redis_luks`, and the post-apply read-back (runbook section "Sole-copy protection and key loss") has
returned `protection.delete=true`. It flips to accepted only after that read-back passes. Until then every sentence below
that says a protection "is in force" is a plan, not a fact: merging does not by itself prove the live Hetzner object changed.
If the apply is skipped or fails, the delivery route is a `manual-rerun` dispatch of the same workflow, never an
untargeted apply.

The ordinal was probed across the `knowledge-base/engineering/architecture/decisions/` directory, `git ls-tree -r` on
`origin/main` and every other `origin/*` ref, and the open PR file lists on 2026-10-10 (highest claimed: ADR-281). It must be
re-probed immediately before merge.

## Context

The 2026-10-09 retirement of the plaintext backstop (#8285; ADR-142 addendum "PR B: the retirement landed") made
`hcloud_volume.inngest_redis_luks` (Hetzner id 106903269) the only copy of the Inngest queue and run state, and the Doppler
secret `INNGEST_REDIS_LUKS_KEY` in `soleur-inngest/prd` its sole opener. Before this decision nothing at Hetzner or in
Terraform refused the volume's deletion, and ADR-142's "No key escrow" stance rested on the AOF being "transient and
self-healing", a premise its own 2026-10-08 addendum had already sharpened (armed reminders carry unbounded future
fire-times; counsel review item O4).

Web-1's workspaces volume got the equivalent protection after the fact (#9348; ADR-119, ADR-263). This store gets it before
anything goes wrong, with one structural difference: its volume attachment must stay replaceable.

## Decision

### The pin set

| Address | Hetzner delete protection | `prevent_destroy` | Why |
|---|---|---|---|
| `hcloud_volume.inngest_redis_luks` | yes (one code line in the `.tf`) | yes | the data; the two cover different edges (a console or API delete, versus a plan) |
| `random_password.inngest_redis_luks` | n/a | yes | the key's source value; regeneration strands the volume |
| `doppler_secret.inngest_redis_luks_key` | n/a | yes | the sole live opener |
| `doppler_project.inngest` | n/a | yes | cascade parent: a targeted replace deletes the secret without planning the secret's own destroy |
| `doppler_environment.inngest_prd` | n/a | yes | same cascade edge |
| `hcloud_volume_attachment.inngest_redis_luks` | n/a | **no, deliberately** | see below |

Three mechanical guards pin the set, each over a different surface: a new suite over effective (comment-stripped)
Terraform text (`apps/web-platform/infra/inngest-luks-sole-copy.test.sh`, "Guard 1"), the reachability pins over every
workflow and tracked script in `plugins/soleur/test/terraform-target-parity.test.ts` ("Guard 2"), and census row G4h plus
the extended `G4_PROTECTED` list in `tests/scripts/test-infra-privileged-tier-census.sh` ("Guard 3": no `removed {}` or
`moved {}` block names a sole-copy address). The three guards are referenced by name here; their rows and mutation
matrices live in the plan and the suites.

### Why the attachment stays unpinned (contrast ADR-263 and ADR-119)

Web-1's attachment carries `prevent_destroy` because web-1's host-replace dispatch refuses web-1 by name, so nothing
sanctioned ever replaces that attachment. This store is the opposite: the sanctioned `inngest-host-replace` dispatch
replaces the server and therefore, through a ForceNew on `server_id`, this attachment. A `prevent_destroy` there would turn
the legitimate replace into a plan error and force an engineer toward the unsafe repair (deleting the lifecycle block).
The attachment's protection is therefore the existing gate rows (a replace is permitted only together with the server;
the shape gate allows no-op or create only), the reachability pins (exactly the expected (workflow, job, verb) triples
name it), and Guard 1 pinning the absence of a lifecycle block on it so that adding one is a red row and not a quiet
breakage of host replace. Copying the web-1 pin set verbatim would have been the wrong generalisation.

### Deliberate unprotect is two reviewed changes, and no erase path exists

Lifting protection is two reviewed PRs in a fixed order: lift delete protection first and let it apply, then remove
`prevent_destroy`. Removing `prevent_destroy` alone lets a destroy apply detach the mounted volume before Hetzner refuses
the delete (the provider detaches, then deletes). Each PR edits the guards it trips (Guard 1 rows, G4h and
`G4_PROTECTED`, the Guard 2 expected set), so a weakening is visible in review. No workflow can destroy this volume today
and PR B of #8285 deleted the wipe and destroy dispatch, so **no sanctioned erase path exists for this volume**.
Designing one is a separate issue and is relevant to Art. 17 whole-volume erasure (see the Article 30 register).

### Key-loss posture

No new escrow artifact is created. Independent copies of the opener today: the Doppler secret (`soleur-inngest/prd`) and
the Terraform state value `random_password.inngest_redis_luks.result` (R2 backend, no versioning and no point-in-time
recovery; ADR-006 correction). The LUKS header has no off-host copy. Escrow of the header or passphrase to a third store
was rejected on confidentiality grounds (ADR-142; the destruction record) and stays rejected; reopening it is a legal
decision, not an engineering default.

**Canonical loss-mode table (this is the single copy; the runbook links here and does not restate it).**

| Loss mode | Detection | Recovery stance |
|---|---|---|
| Doppler secret deleted | 12h drift plan (create planned) | A create of the Doppler copy alone is legal on the per-merge path and restores the state value; the next merge apply or a `manual-rerun` dispatch re-creates it. |
| Doppler secret overwritten with another value | 12h drift plan (update planned) | The per-merge guard HALTs on any update of the pair (correctly: it cannot tell repair from rotation), so there is no automated repair route. Recovery is Doppler version history (retained per secret on paid tiers; the plan tier and the rollback scope are NOT measured here and are carried by #9927; never print diffs, they carry plaintext). Owner: the repository owner; procedure in the runbook section. Automated repair dispatch is DEFERRED (#9927). |
| Terraform state entry lost | next plan shows a create of the passphrase | Re-import is unverified for this resource class (ADR-006 caveat: `special=false` import plans a replacement). The Doppler copy is the only live opener; the per-merge HALT blocks the create. Owner: the repository owner, who decides the repair; do not apply. The import rehearsal in the rehearsal root is DEFERRED (#9927) and re-import is not claimed as a recovery until it passes. |
| Both copies lost | none possible | Total loss of the store; accepted residual, recited in the Article 30 register. |
| LUKS header corrupted | the hourly probe row proves device binding, not the cipher, so detection lags to the first Redis failure (existing wrong-volume alert; dead-man's switch #9703, not yet armed) | No recovery. Header backup is DEFERRED to the planned host-replace window with a dated trigger (#9927: 2027-01-08 or the next planned host replace, whichever comes first). |
| Hetzner volume deleted despite protection, or project loss | none | No recovery; residual. |

### What losing the store costs (verified, with one claim left unconfirmed)

The earlier reading, carried in ADR-142 ("its total-loss recovery is already built and proven ... the sole-copy reminder
subset can be enumerated/re-armed") and carried into the planning brief as "reminders are re-armable from Postgres", was checked
against the scripts on 2026-10-10 and is **UNCONFIRMED, and the repository evidence points the other way for armed
reminders after a total loss**:

- `apps/web-platform/infra/inngest-enumerate-reminders.sh` builds the re-arm list by querying the running Inngest server's
  own GraphQL on loopback for `reminder.scheduled` events that are still armed. Its source is the live store, not Postgres.
  `inngest-rearm-reminders.sh` consumes that list. Neither can produce a list once the store is gone.
- The only arming surface, `POST /api/internal/schedule-reminder`, does one `inngest.send` and persists nothing app-side
  (its own comment: "nothing was persisted either way, so the caller must re-arm"). No Supabase migration holds a
  reminder table.
- `inngest-wiped-volume-verify.sh` proves that functions re-register (`functions` from `/v0/gql`) and that a throwaway
  marker fires after a wipe of the local `/var/lib/inngest` directory. It deliberately **refuses** to run when any real
  armed reminder exists (`real_reminders_present`), because a wipe would destroy it. That refusal is the script's own
  statement that armed reminders are not independently recoverable.
- Inngest's Postgres holds config and run history (Article 30 PA-13 (e)); no script reads armed reminders from it, and
  whether run history alone could reconstruct a future fire-time is not tested anywhere.

**Confirmed:** after a total loss the platform comes back empty, functions re-register, and new reminders arm normally.
**Not confirmed, and not to be relied on:** that previously armed reminders and in-flight job payloads can be rebuilt. The
working assumption for the posture is that they are lost, and the affected users are the people whose reminders were armed
at the time. Who tells them: the repository owner (the founder, the single CODEOWNER) is the incident owner and sends the
user notice, after consulting counsel on whether a loss of availability of personal data in the store triggers a
notification duty (Art. 4(12) and 33; the breach register is `knowledge-base/legal/breach-register.md`). The runbook names
the same owner and the `soleur:incident` skill as the route.

### Residuals recorded, not mitigated

- **Hetzner project deletion or account loss** is not covered; whether delete protection blocks a project deletion is
  unverified.
- **A holder of the read/write Hetzner token can lift protection.** Protection defends against mistaken deletes (a console
  click, a wrong id, a pasted recipe, the drift workflow's runnable DELETE recipes), not against a leaked read/write token.
  That token is also the silent fallback of the read-only loader; a no-fallback loader is carried by #9927.
- **Other credentials can overwrite or delete the key:** the inngest cutover arm token
  `doppler_service_token.inngest_arm_write` (read/write on `soleur-inngest/prd`, published as `DOPPLER_TOKEN_INNGEST_ARM`)
  and the workplace Doppler token `DOPPLER_TOKEN_TF`. Scoping or revoking the arm token after cutover is carried by #9927.
- **The ciphertext has no backup.** The volume is the only copy of the data; there is no snapshot, replica or export.
- **The host token `inngest-boot` is `read/write`** on the same Doppler config. Downgrading it is a ForceNew host replace
  (the token's `.key` feeds `user_data`), so it rides #9927. Revoking or replacing `doppler_service_token.inngest` is also a
  key-access edge: a reboot is stranded until the replace flow re-delivers the token.
- **An untargeted full apply** would replace the server and its attachment with no gate running (the live host's
  `user_data` is stale until #9786). The volume itself stays pinned. The runbook says never to run one.
- **Detection of lifted protection is generic.** The 12h drift plan already alerts but dedupes by title, and the full-root
  plan is non-empty until #9786, so a lifted protection arrives as one more comment on an open issue. The post-apply
  read-back is the only distinct check.
- **The first sanctioned host replace is the live proof** that Hetzner allows detach of a delete-protected volume (the
  client documentation lists no such precondition; the repo's web-1 note cites provider source). This ADR's PR performs no
  replace. A failure there is not this PR's regression; the runbook carries the break-glass.

### Enforcement posture of the guards (read-only record, 2026-10-10)

Read from `infra/github/ruleset-ci-required.tf`, `scripts/required-checks.txt`, `.github/CODEOWNERS` and the workflows;
nothing was changed.

- **Required checks.** The ruleset requires `test` among its contexts; `test` aggregates `test-webplat`, `test-bun`,
  `test-scripts`, `test-scripts-heavy`, `web-platform-build`, `encryption-posture` and `push-dedupe`.
  Guard 2 (`bun test plugins/soleur/`) runs in the `test-bun` shard and Guard 3 (the privileged-tier census, a `run_suite`
  inside the `want_scripts` block of `scripts/test-all.sh`) in the `test-scripts` shard, so both are inside the required
  `test` context. **Guard 1 is not**: suites under `apps/web-platform/infra/` run in the `deploy-script-tests` job of
  `infra-validation.yml`, whose context is not in the required list, and `scripts/test-all.sh` runs infra suites only for
  `TEST_GROUP` of `all`, `infra` or `affected`, which no CI shard sets. A red Guard 1 therefore does not by itself block a
  merge. This gap goes to #9927 (promote the suite into a required context, or add a thin required aggregator).
- **CODEOWNERS.** `/apps/web-platform/infra/` is owned (`@deruelle`), so `inngest-redis-luks.tf`, `inngest-host.tf` and
  Guard 1 are covered. The other guard files (`plugins/soleur/test/terraform-target-parity.test.ts`,
  `tests/scripts/test-infra-privileged-tier-census.sh`, `tests/scripts/lib/hcl-effective-text.sh`, the host-replace gate
  library) have no row and fall under the `*` default, which names the same single owner. Separately, the CI ruleset has no
  pull-request rule with `require_code_owner_review` (the CODEOWNERS header records that enforcing it is an operator
  follow-up), so CODEOWNERS is a routing hint here, not an independent second reviewer. Adding explicit rows for the guard
  files, and the second-reviewer enforcement, go to #9927.
- **Consequence for the anchor.** The pins and Guards 1 and 2 land in the same commit, so one diff can weaken both. The
  independent anchors are the census rows (a different file, required), the merge-base diff the census computes for G4c
  (a deleted resource block), and the live read (the post-apply read-back and the drift plan), which a weakening of text
  alone cannot change. They are as strong as those being required checks, which is the measurement above.

## Considered options

| Option | Verdict | Why |
|---|---|---|
| Copy web-1's pin set, including `prevent_destroy` on the attachment | Rejected | Breaks the sanctioned `inngest-host-replace` (ForceNew on `server_id`). |
| Widen the two dispatch gates to tolerate a pending protection update | Rejected | A fail-closed abort with a named reason (`luks_volume_touched`) between merge and apply is the safe behaviour; the runbook orders merge-apply before any replace. |
| A reviewer-gated dispatch for lifting protection | Rejected | A new path to the very edge being closed; lifting is a reviewed PR. |
| Escrow the passphrase or header to a third store | Rejected | Confidentiality (ADR-142, destruction record); a legal decision, not an engineering default. |
| On-host header backup or `luksOpen --test-passphrase` continuity probe | Deferred (#9927) | Both edit cloud-init `user_data`, which force-replaces the sole scheduler. |
| Add a per-merge `-target` on the volume | Rejected | Makes the per-merge job a third writer of the sole copy; edits a workflow at its byte limit; a design change, not an inline branch. |

## Consequences

- (+) A mistaken console, API or plan delete of the store is refused at two layers, and a `removed {}`, `moved {}`,
  `-replace` or `-destroy` over the sole-copy addresses is a red check rather than a quiet state edit.
- (+) The sanctioned host replace keeps working, and a gate-library replay tests that a post-apply plan still passes and a
  pre-apply plan aborts with a named reason.
- (-) Between a merge and its apply, or after a skipped or failed apply, a host-replace dispatch aborts
  `luks_volume_touched`; the delivery route is a `manual-rerun` dispatch.
- (-) A legitimate rename (`moved`) or an unrelated volume update (for example a size grow) is blocked or aborted until the
  guards are edited in a reviewed change. This is the intended friction.
- (-) The residuals above are accepted, not mitigated. The policy defends against mistaken deletes, not against a leaked
  read/write credential, and not against loss of the key.

## What this ADR does not change

ADR-142's mechanism, the additive cutover, or the destruction records (attested; never edited). ADR-142 and ADR-263 carry
dated pointer notes to this ADR; the records under `knowledge-base/legal/audits/` are untouched.
