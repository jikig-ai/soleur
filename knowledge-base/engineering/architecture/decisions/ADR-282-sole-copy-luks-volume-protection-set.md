---
title: A sole-copy LUKS volume gets delete protection plus prevent_destroy on the volume, its passphrase pair and the Doppler cascade parents; the sanctioned-replace attachment stays unpinned
status: adopting
date: 2026-10-10
supersedes: none
amends: [ADR-142]
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
returned `protection.delete=true`. It flips to accepted only after that read-back passes. **Who flips it:** the post-merge
verification step runs the read-back (`soleur:postmerge` Phase 5.7, a path-triggered report-only phase, not the merge
itself). When the read-back matches the expected word (`protected`), that phase files ONE tracking issue, "flip ADR-282
adopting to accepted (and the sister records)", so the flip does not depend on memory; the flip itself is one follow-up PR
(a merged PR cannot take a follow-up commit). If the read-back fails or is skipped the status stays adopting and the route is
a `manual-rerun` dispatch, which the agent only names and the owner authorises per command (it applies the whole per-merge
plan). Until then every sentence below
that says a protection "is in force" is a plan, not a fact: merging does not by itself prove the live Hetzner object changed.
If the apply is skipped or fails, the delivery route is a `manual-rerun` dispatch of the same workflow, never an
untargeted apply.

The ordinal was probed across the `knowledge-base/engineering/architecture/decisions/` directory, `git ls-tree -r` on
`origin/main` and every other `origin/*` ref, and the open PR file lists on 2026-10-10 (highest claimed: ADR-281). It must be
re-probed immediately before merge.

## Context

The 2026-10-09 retirement of the plaintext backstop (#8285; ADR-142 addendum "PR B: the retirement landed") made
`hcloud_volume.inngest_redis_luks` (Hetzner id 106903269) the only copy of the Inngest queue and run state, and the Doppler
secret `INNGEST_REDIS_LUKS_KEY` in `soleur-inngest/prd` the only opener the host reads (an independent copy of the passphrase
exists in Terraform state; see Key-loss posture). Before this decision nothing at Hetzner or in
Terraform refused the volume's deletion, and ADR-142's "No key escrow" stance rested on the AOF being "transient and
self-healing", a premise its own 2026-10-08 addendum had already sharpened (armed reminders carry unbounded future
fire-times; counsel review item O4).

Web-1's workspaces volume got the equivalent protection after the fact (#9348; the pin set is ADR-119 D1, declared in
`apps/web-platform/infra/workspaces-luks.tf`). This store gets it before anything goes wrong, with one structural
difference: its volume attachment must stay replaceable.

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
workflow and tracked script in `plugins/soleur/test/terraform-target-parity.test.ts` ("G2/G2e"), and census row G4h plus
the extended `G4_PROTECTED` list in `tests/scripts/test-infra-privileged-tier-census.sh` ("G4h": no `removed {}` or
`moved {}` block names a sole-copy address). The three guards are referenced by name here; their rows and mutation
matrices live in the plan and the suites. Two further pins sit in the required `test` check inside the parity test: an
independent effective-text pin of the volume's delete-protection and `prevent_destroy` lines and of the pair and its
parents, and a pin of the dependency edge by which the volume update reaches the per-merge plan (the alert target
`logtail_exploration.inngest_luks_wrong_volume` and the alias local in `betterstack-logs-alerts.tf`). Guard 1 is advisory
until it is promoted to a required check (#9927).

### Why the attachment stays unpinned (contrast ADR-263 and ADR-119)

Web-1's attachment carries `prevent_destroy` (ADR-119 D1; `hcloud_volume_attachment.workspaces_luks` in
`apps/web-platform/infra/workspaces-luks.tf`; ADR-263 only records the divergence from it) because web-1's host-replace
dispatch refuses web-1 by name, so nothing sanctioned ever replaces that attachment. This store is the opposite: the sanctioned `inngest-host-replace` dispatch
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
`G4_PROTECTED`, the G2 expected set), so a weakening is visible in review. No workflow can destroy this volume today
and PR B of #8285 deleted the wipe and destroy dispatch, so **no sanctioned erase path exists for this volume**.
Designing one is a separate issue and is relevant to Art. 17 whole-volume erasure (see the Article 30 register).

**When a sanctioned replace is blocked by the protection** (for example Hetzner rejecting the detach of a delete-protected
volume; see the residual on the first sanctioned host replace below), the only data-safe route is the same reviewed
two-step route, not an out-of-band call:

1. A PR sets the volume's delete-protection attribute to false (and edits the Guard 1 rows, the parity-test pin and the
   census rows, if any, that it trips); the per-merge apply lands it, so live state equals the HCL again. The PR must also
   remove the cause of any current halt in the same change and must not carry `[skip-web-platform-apply]`, and it opens a
   dated re-protect follow-through issue before it merges. Its post-merge read-back expects `not-protected`, which is not a
   failure.
2. Then dispatch `inngest-host-replace`: the volume now plans as a no-op, which both dispatch gates accept.
3. Then a re-protect PR restores the attribute and the guards. The unprotected window (from step 1's apply to step 3's)
   is a stated cost: once step 1 lands, the HCL, the live state and the drift plan agree on `false` and nothing alerts, so
   the dated issue is the only forcing function.

This takes several merge cycles and there is no faster data-safe route. An out-of-band lift alone does not help: one
`change_protection` call makes the next plan show the attribute going from false back to true on the volume, which is an
in-place update, and both host-replace gates abort `luks_volume_touched` on any volume action other than no-op or create
(`inngest-host-replace-gate.sh`), so the dispatch is refused by construction; and the next infra-path merge or `manual-rerun`
runs the per-merge apply, which re-protects. Any out-of-band lift is reverted by that apply. If the per-merge job is
wedged by another halt (`destroy_count`, `host_creates`, the rotation HALT, an apply error), both gates abort and a
`manual-rerun` dispatch runs the same wedged job. The reviewed route above works then only if its step-1 PR also removes the
cause of the halt in the same change and does not carry `[skip-web-platform-apply]`; otherwise there is **no route**, and
the owner resolves the halt first.

**Key rotation has no route today.** The per-merge rotation HALT cannot be acknowledged and its text names no automated
route, so lifting `prevent_destroy` on the pair is not enough. A leaked-key response is therefore an escalation to the
owner, carried by #9927, not a reviewed edit.

### Key-loss posture

No new escrow artifact is created. The passphrase has TWO independent copies today, so the Doppler copy is the only copy
the host reads, not the only copy that exists: the Doppler secret (`soleur-inngest/prd`) and
the Terraform state value `random_password.inngest_redis_luks.result` (R2 backend, no versioning and no point-in-time
recovery; ADR-006 correction). The writing credentials for the Doppler copy are the arm token, `DOPPLER_TOKEN_TF` and the
host boot token `inngest-boot` (all three). The LUKS header has no off-host copy. Escrow of the header or passphrase to a third store
was rejected on confidentiality grounds (ADR-142; the destruction record) and stays rejected; reopening it is a legal
decision, not an engineering default.

**Canonical loss-mode table (this is the single copy; the runbook links here and does not restate it).**

| Loss mode | Detection | Recovery stance |
|---|---|---|
| Doppler secret deleted | 12h drift plan (create planned) | A create of the Doppler copy alone is legal on the per-merge path and restores the state value; the next merge apply or a `manual-rerun` dispatch re-creates it. |
| Doppler secret overwritten with another value | 12h drift plan (update planned) | A repair is a secret update with `random_password` a no-op; the per-merge HALT is still correct to block it unattended (an update of the pair is also what a rotation looks like), and the owner repairs it via the documented route. Two independent recoveries: Doppler version history (retained per secret on paid tiers; the plan tier and the rollback scope are NOT measured here and are carried by #9927; never print diffs, they carry plaintext), and the second, independent copy, the Terraform state value `random_password.inngest_redis_luks.result`, which the owner can write back to the Doppler secret without printing it (runbook section; per-command go-ahead; guarded by a fail-closed length and format check; the write is irreversible without Doppler history; NOT executed or rehearsed). It is total loss only when both copies are gone. While the value stays overwritten, every infra-path merge's per-merge apply halts on the rotation HALT, so infra PRs merge with `[skip-web-platform-apply]` until the key is repaired. Automated repair dispatch is DEFERRED (#9927). |
| Terraform state entry lost | next plan shows a create of the passphrase | With the jq create-halt in this PR, the per-merge HALT blocks a create of `random_password.inngest_redis_luks`, alone or together with the Doppler copy; only the password create halts, and a create of the Doppler copy alone stays legal and restores a lost Doppler copy. **The halt wedges every merge's per-merge apply (all infra delivery, not only this store) until the owner repairs state**, by an owner-run state operation or an `import {}` block (which plans as a no-op and passes the HALT). State-loss recovery remains UNVERIFIED. An offline measurement showed that importing the `random_password` and then planning gives `special true -> false`, a replacement, which `prevent_destroy` turns into a hard error, so an accidental apply cannot mint a new key; editing `special = false` into the imported state gives "No changes". That edit is recorded as a CANDIDATE recipe only: it was NOT rehearsed and is not claimed. An import takes the passphrase value itself as its id, so a typed import puts it on argv (visible in `ps` and shell history) and a committed `import {}` block would expose it in the HCL and in plan output: if tried, it is owner-local with the value from an environment variable, never through CI. Owner: the repository owner, who decides the repair; do not apply. The import rehearsal in the rehearsal root is DEFERRED (#9927). |
| Both copies lost (Doppler secret and Terraform state value) | none possible | Total loss of the store; accepted residual, recited in the Article 30 register. Reserve this label for both copies lost; one surviving copy is a recovery, not a total loss. |
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

**Confirmed, as app behaviour with an empty store:** functions re-register and new reminders arm normally. **Restoring an empty
store has no automated route**: the recut dispatch is retired (#8285), the per-merge create HALT refuses a new passphrase and
the inngest-host shape gate refuses the volume and passphrase pair, so the owner designs the restoration in a reviewed change
(#9927).
**Not confirmed, and not to be relied on:** that previously armed reminders and in-flight job payloads can be rebuilt. The
working assumption for the posture is that they are lost. **Who is affected is unknowable from surviving data:**
`schedule-reminder` persists nothing app-side, so after a total loss no surviving record says whose reminders or in-flight
jobs were in the store. The default is to treat **all active users** as potentially affected, because `schedule-reminder` persists nothing app-side
and no per-user list exists. Whether a
surviving source exists (Inngest Postgres run history, application logs) is open and tracked in #9927; until that is
verified no one may state a narrower affected set. Who tells them: the repository owner (the founder, the single CODEOWNER) is the incident owner and sends the
user notice, as a product notice via the owner, after assessing with counsel whether a loss of availability of personal
data in the store triggers a notification duty (Art. 4(12), 33 and 34; the breach register is
`knowledge-base/legal/breach-register.md`). Total loss of availability is not necessarily a personal-data breach, so the
word is assess; if any limb is a personal-data breach, the 72-hour clock of Art. 33 runs from the owner's awareness. The runbook names
the same owner and the `soleur:incident` skill as the route.

### Residuals recorded, not mitigated

- **Hetzner project deletion or account loss** is not covered; whether delete protection blocks a project deletion is
  unverified.
- **A holder of the read/write Hetzner token can lift protection.** Protection defends against mistaken deletes (a console
  click, a wrong id, a pasted recipe, the drift workflow's runnable DELETE recipes), not against a leaked read/write token.
  That token is also the silent fallback of the read-only loader; a no-fallback loader is carried by #9927.
- **Other credentials can overwrite or delete the key:** the three writers of the Doppler copy are the inngest cutover arm
  token `doppler_service_token.inngest_arm_write` (read/write on `soleur-inngest/prd`, published as
  `DOPPLER_TOKEN_INNGEST_ARM`), the workplace Doppler token `DOPPLER_TOKEN_TF`, and the host boot token `inngest-boot`
  (below). Scoping or revoking the arm token after cutover is carried by #9927.
- **Not guarded: the R2 state-backend credentials and the script writers.** A read of the R2 state backend exposes the
  passphrase held in state (the second copy); a write there can delete the state entry (loss mode 3 above). Scripts that
  write to `soleur-inngest/prd` are also outside the guards: `scripts/cutover-inngest.sh` (with the arm token) and the host
  scripts `inngest-luks-cutover.sh` and `inngest-cutover-flip.sh`.
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
  replace. A failure there is not this PR's regression; the route is the reviewed two-step route in "Deliberate unprotect"
  above, which takes several merge cycles (the runbook carries the same text). A one-call out-of-band lift does not
  complete a replace.

### Enforcement posture of the guards (read-only record, 2026-10-10)

Read from `infra/github/ruleset-ci-required.tf`, `scripts/required-checks.txt`, `.github/CODEOWNERS` and the workflows;
nothing was changed.

- **Required checks.** The ruleset requires `test` among its contexts; `test` aggregates `test-webplat`, `test-bun`,
  `test-scripts`, `test-scripts-heavy`, `web-platform-build`, `encryption-posture` and `push-dedupe`.
  G2/G2e (`bun test plugins/soleur/`) run in the `test-bun` shard and the census G4h (the privileged-tier census, a `run_suite`
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
- **Consequence for the anchor.** The pins, Guard 1 and the G2e pin land in the same commit, so one diff can weaken both. The
  census rows do not pin the attribute lines; they pin the `removed {}`/`moved {}` blocks and a deleted resource block (the
  merge-base diff the census computes for G4c). The independent anchor for the attribute lines is the effective-text pin in
  the parity test, which runs in the required `test` check, plus the live read (the post-apply read-back and the drift
  plan), which a weakening of text alone cannot change. Guard 1 remains non-required. The anchors are as strong as those
  being required checks, which is the measurement above.

### Fresh-host provisioning tension (`hr-fresh-host-provisioning-reachable-from-terraform-apply`)

With the create-halt, an empty-state apply of this root HALTs on the per-merge path (the passphrase create is refused) and no
sanctioned route replaces it, because the recut dispatch is retired (#8285). That is the same precedent as the web-class
passphrase: the per-merge path is deliberately not a way to birth this store, and a first provisioning of the root is an
operator-applied, separately designed change (#9927), not a per-merge step.

## Considered options

| Option | Verdict | Why |
|---|---|---|
| Copy web-1's pin set, including `prevent_destroy` on the attachment | Rejected | Breaks the sanctioned `inngest-host-replace` (ForceNew on `server_id`). |
| Widen the two dispatch gates to tolerate a pending protection update | Rejected | A fail-closed abort with a named reason (`luks_volume_touched`) between merge and apply is the safe behaviour; the runbook orders merge-apply before any replace. |
| A reviewer-gated dispatch for lifting protection | Rejected | A new path to the very edge being closed; lifting is a reviewed PR. |
| Escrow the passphrase or header to a third store | Rejected | Confidentiality (ADR-142, destruction record); a legal decision, not an engineering default. |
| On-host header backup or `luksOpen --test-passphrase` continuity probe | Deferred (#9927) | Both edit cloud-init `user_data`, which force-replaces the sole scheduler. |
| Add a per-merge `-target` on the volume | Rejected | The per-merge job is already an implicit writer of the volume, through the dependency edge of the alert target `logtail_exploration.inngest_luks_wrong_volume`; that edge is now pinned by a test in the required check. An explicit `-target` would edit a workflow at its byte limit; a design change, not an inline branch. |

## Consequences

- (+) A mistaken console, API or plan delete of the store is refused at two layers, and a `removed {}`, `moved {}`,
  `-replace` or `-destroy` over the sole-copy addresses is a red check rather than a quiet state edit.
- (+) The sanctioned host replace keeps working, and a gate-library replay tests that a post-apply plan still passes and a
  pre-apply plan aborts with a named reason.
- (-) Between a merge and its apply, or after a skipped or failed apply, a host-replace dispatch aborts
  `luks_volume_touched`; the delivery route is a `manual-rerun` dispatch.
- (-) A legitimate rename (`moved`), a region migration (`location` is ForceNew) or a change of `format` is blocked or
  aborted until the guards are edited in a reviewed change. This is the intended friction. A size grow is different: it
  plans as an in-place update, so the per-merge apply would land it unattended (only the existing halts stop an apply)
  while the dispatch gates abort `luks_volume_touched` until it has landed.
- (-) The residuals above are accepted, not mitigated. The policy defends against mistaken deletes, not against a leaked
  read/write credential, and not against loss of the key.

## What this ADR does not change

ADR-142's mechanism, the additive cutover, or the destruction records (attested; never edited). ADR-142 (which this ADR amends in part), ADR-263
and ADR-119 carry dated pointer notes to this ADR; the records under `knowledge-base/legal/audits/` are untouched.
