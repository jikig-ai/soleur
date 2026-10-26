---
title: A sole-copy LUKS volume gets delete protection plus prevent_destroy on the volume, its passphrase pair and the Doppler cascade parents; the sanctioned-replace attachment stays unpinned
status: accepted
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

> **Accepted 2026-10-15 (#10018).** The condition stated below was met: the post-apply read-back (runbook section 5c, step 3) returned `protected` for volume 106903269 on 2026-10-15 (UTC), the word derived from `origin/main`. The evidence is in the Addendum of that date at the end of this ADR. The paragraph below is the 2026-10-10 text, kept as history: its sentence "Until then every sentence below that says a protection 'is in force' is a plan, not a fact" describes the state before the read-back, and the follow-up PR it promises ("the flip itself is one follow-up PR") is this one.

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
| Doppler secret overwritten with another value | 12h drift plan (update planned) | A repair is a secret update with `random_password` a no-op; the per-merge HALT is still correct to block it unattended (an update of the pair is also what a rotation looks like), and the owner repairs it via the documented route. Two independent recoveries: Doppler version history (retained per secret on paid tiers; the plan tier and the rollback scope are NOT measured here and are carried by #9927; never print diffs, they carry plaintext), and the second, independent copy, the Terraform state value `random_password.inngest_redis_luks.result`, which the owner can write back to the Doppler secret without printing it (runbook section; per-command go-ahead; guarded by a fail-closed length and format check; the write is irreversible without Doppler history; NOT executed or rehearsed). It is total loss only when both copies are gone. While the value stays overwritten, every infra-path merge's per-merge apply halts on the rotation HALT, so infra PRs merge with `[skip-web-platform-apply]` until the key is repaired. Automated repair dispatch is DEFERRED (#9927). **Superseded 2026-10-20 (#9927), as to "the plan tier and the rollback scope are NOT measured here":** the plan tier is still not measured (the Doppler CLI exposes no plan field for this workplace or project, and the credential is a personal CLI token), but two facts are now recorded with evidence classes in the 2026-10-22 addendum: the `soleur-inngest/prd` config log holds 68 entries back to 2026-07-23 (89 days at measurement), which a 3-day activity-log window could not hold, and the documented rollback scope is one log entry (a secret add, update or delete), not a whole config, and is not rehearsed. Route A therefore stays "unverified; treat as unavailable", and Route B above is the only recovery planned on. |
| Terraform state entry lost | next plan shows a create of the passphrase | With the jq create-halt in this PR, the per-merge HALT blocks a create of `random_password.inngest_redis_luks`, alone or together with the Doppler copy; only the password create halts, and a create of the Doppler copy alone stays legal and restores a lost Doppler copy. **The halt wedges every merge's per-merge apply (all infra delivery, not only this store) until the owner repairs state**, by an owner-run state operation. An `import {}` block is not a route that plans as a no-op: it plans the same replacement as a plain import and errors on `prevent_destroy`. The recovery was rehearsed OFFLINE by `inngest-redis-luks-import-rehearsal.test.sh`: verified on local state with a synthetic value only; R2-backed state is unverified (result and limits: the 2026-10-19 addendum). An import takes the passphrase value itself as its id, so a typed import puts it on argv (visible in `ps` and shell history), `terraform import` echoes it, and a committed `import {}` block would expose it in the HCL and in plan output: if tried, it is owner-local with the value from an environment variable, output to a file with mode 0600 on tmpfs, never through CI. Owner: the repository owner, who decides the repair; do not apply. |
| Both copies lost (Doppler secret and Terraform state value) | none possible | Total loss of the store; accepted residual, recited in the Article 30 register. Reserve this label for both copies lost; one surviving copy is a recovery, not a total loss. |
| LUKS header corrupted | the hourly probe row proves device binding, not the cipher, so detection lags to the first Redis failure (existing wrong-volume alert; dead-man's switch #9703, armed 2026-10-12) | No recovery. Header backup is DEFERRED to the planned host-replace window with a dated trigger (#9927: 2027-01-08 or the next planned host replace, whichever comes first). |
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
working assumption for the posture is that they are lost. **No per-user list is kept app-side:**
`schedule-reminder` persists nothing app-side, and whether any surviving record says whose reminders or in-flight
jobs were in the store is NOT established (partial, C1 below). The default is to treat **all active users** as potentially affected; it
is a floor, not a ceiling (it does not cover users who are not currently active, nor the external sender of an inbound email; see the
runbook's event-class table). Whether a
surviving source exists (Inngest Postgres run history, application logs) is open and tracked in #9927; until that is
verified no one may state a narrower affected set. **Superseded 2026-10-22 (#9927 C1), as to "is open and tracked in #9927":**
measured, evidence class **partial**: a candidate source exists (a dedicated Supabase Postgres project with estimated ~937k
`history` and ~182k `events` rows and a column capable of holding a user reference, `events.event_user`, by name, which is Inngest's top-level user field and which this repo's
senders do not set, so it cannot define or bound the affected set); the
non-null count and the oldest row were NOT measured, the default of all active users stays, and no narrower set may be
stated. No row, identifier, email, payload, event body or per-user count was selected, printed, logged or stored. Whether
any surviving record identifies WHICH users had armed reminders or in-flight jobs was NOT established. Measured on
2026-10-22 by three catalog-metadata queries against project `pigsfuxruiopinouvjwy` (the probe script was removed from the PR once the finding was recorded). Who tells them: the repository owner (the founder, the single CODEOWNER) is the incident owner and sends the
user notice, as a product notice via the owner, after assessing with counsel whether a loss of availability of personal
data in the store triggers a notification duty (Art. 4(12), 33 and 34; the breach register is
`knowledge-base/legal/breach-register.md`). Total loss of availability is not necessarily a personal-data breach, so the
word is assess; if any limb is a personal-data breach, the 72-hour clock of Art. 33 runs from the owner's awareness. The runbook names
the same owner and the `soleur:incident` skill as the route.

### Residuals recorded, not mitigated

- **Hetzner project deletion or account loss** is not covered. Whether delete protection blocks a project deletion, or
  survives account loss, is not established: the Hetzner pages read on 2026-10-23 are silent on it (Addendum 2026-10-23; terms and
  conditions and the projects documentation were not read). Plan as if project deletion or account loss destroys the
  volume regardless of delete protection, and never cite delete protection as cover against either. No backup exists to
  fall back on (see "The ciphertext has no backup" below).
- **A holder of the read/write Hetzner token can lift protection.** Protection defends against mistaken deletes (a console
  click, a wrong id, a pasted recipe; the drift workflow's issue bodies printed runnable DELETE recipes until #9927 item 8c
  removed them), not against a leaked read/write token.
  That token is also the silent fallback of the read-only loader; a no-fallback loader is carried by #9927.
  *(Superseded 2026-10-23: the loader and every Hetzner read-only reader, including the Inngest generation anchor, no longer fall
  back to the read/write token; see ADR-241's 2026-10-20 and 2026-10-23 entries.)*
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
  read-back is the point-in-time check; the recurring distinct signal is the drift workflow's `sole-copy-protection-check`
  job (Addendum 2026-10-16, #9927 item 9).
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

## Addendum — 2026-10-14 (#8316)

Appended; nothing above is changed. The retired `inngest_host_dark_gate` (ADR-199) no longer stands behind the lift of this ADR's protection: [ADR-199's addendum](./ADR-199-destructive-clearance-requires-a-measured-empty-store-and-a-dark-host.md#addendum--2026-10-14-8316) records that any destructive-clearing target written after the protection is lifted must reintroduce a measured-empty-store plus dark-host gate before it may plan a destroy. The lift route above (delete protection in its own reviewed change, then `prevent_destroy`) is where that requirement attaches, alongside the Guard 1 rows, `G4_PROTECTED` and `luks_volume_touched` named in this ADR.

## Addendum — 2026-10-15 (#10018, accepted: the read-back)

Appended; nothing above is changed except the frontmatter `status` and the leading blockquote under Status.

**The read-back.** The post-apply read-back of runbook section 5c, step 3 (read-only, cited by section and not reprinted here) returned the word `protected` (exit 0) for Hetzner volume 106903269 (`hcloud_volume.inngest_redis_luks`) on 2026-10-15 (UTC). It was run once by the agent session working #10018, from the section 5c step 3 one-liner, and printed exactly that word. No time of day was captured, so none is recorded. The expected word was derived from `origin/main`, not assumed: `apps/web-platform/infra/inngest-redis-luks.tf` carries `delete_protection = true` inside `resource "hcloud_volume" "inngest_redis_luks"`, delivered by #9925 (commit `67cb281e4f`, an ancestor of `origin/main`). The expected word and the read word match, which is this ADR's own flip condition.

**The run history, as measured.** Merge-SHA apply run 38139392390 applied the in-place update `hcloud_volume.inngest_redis_luks delete_protection false -> true` ("Apply complete! Resources: 0 added, 1 changed, 0 destroyed", 2026-10-11T12:32:53Z); the failing step (`terraform_data.egress_gateway_web2` remote-exec, dial tcp i/o timeout) ended at 12:48:18Z and the job concluded `failure` at 12:48:26Z, after that apply had completed and on an unrelated step. Later runs are mixed: dispatch run 38580429629 (2026-10-14) concluded `failure`, and the latest apply on main, run 38653889114 on 944372f0d5, succeeded. Neither proves the flag; only the read-back does.

**What the read-back is and is not.** It is a point-in-time read of the delete-protection flag only. `prevent_destroy` is a plan-time control, enforced by the guards named in this ADR, and is not read back from any live system. Guard 1 stays advisory until #9927. The residuals, the loss-mode table, the absent Art. 32(1)(c) restore capability and the "no sanctioned erase path" statement are unchanged. Protection defends against mistaken deletes; it does not defend against a holder of the read/write Hetzner token, which can lift it, or against the three writers of the Doppler copy of the key.

**Who flips it** is discharged by this follow-up PR. `soleur:postmerge` Phase 5.7 step 6 files no tracking issue once the status is `accepted`.

## Addendum — 2026-10-15 (#9927 item 8c, drift workflow DELETE recipes removed)

Appended; the only change above is the parenthetical in the residual "A holder of the read/write Hetzner token can lift protection": it now records that the drift workflow's issue bodies no longer print DELETE recipes (PR #10355). Status stays `accepted`. Scope, stated exactly: the removed text templated calls against Hetzner objects labeled `app=soleur-rung2-rehearsal` or `app=soleur-inngest-provision-rehearsal` and against the key-bearing scratch Doppler objects (`prd_git_data_rehearsal_*` in `soleur`, `rehearsal_*` in `soleur-inngest`, identified by name), never against the sole-copy volume, whose resources carry neither label. The residual itself is unchanged: a holder of the read/write token can still lift protection.

## Addendum — 2026-10-16 (#9927 item 9, recurring protection check)

Appended; the only change above is the residual "Detection of lifted protection is generic", which now points at the check below. Status stays `accepted`. Plan: `knowledge-base/project/plans/archive/20261018-182041-2026-10-16-feat-sole-copy-protection-drift-check-plan.md`.

**What was added.** The job `sole-copy-protection-check` in `.github/workflows/scheduled-terraform-drift.yml` makes one read-only GET per attempt (up to three attempts, retried only on a transport failure, 429 or 5xx) and compares the live `protection.delete` flag of the Inngest store volume with the value declared in `apps/web-platform/infra/inngest-redis-luks.tf`. A difference files an issue of its own (labels `infra-drift`, `action-required`), instead of one more comment on the standing drift issue. The post-apply read-back of runbook section 5c stays the point-in-time arbiter; this job is its recurring twin and the distinct signal the residual lacked. It prints no command and mutates nothing.

**The expectation is derived, not stored.** The expected flag is read from the checked-out `.tf`, so a lift that went through the sanctioned two-step route above is quiet by design: after the lift merges and applies, declared and live agree and nothing alerts. The unprotected window stays visible as a warning annotation and a job-summary line on every run, and the dated re-protect issue remains the forcing function. What the job catches is a live flag that differs from a declaration nobody changed. When a re-protect PR merges, live is `false` and declared is `true` until the apply lands, so a 90-minute grace applies: while the last commit to the `.tf` is under 90 minutes old the verdict is a warning, not a finding. Past 90 minutes it files. A commit time that cannot be read fails open to a finding. Any commit that touches `inngest-redis-luks.tf` opens the 90-minute grace, not only a flag edit, so a comment-only edit can also delay a real out-of-band lift to the next run. It is delayed, not lost.

**The id pin, and what it does and does not defend.** The volume is found by name and must also carry the pinned Hetzner id (106903269, the same value as the read-back above and the section 5c one-liner; a test pins the copies equal: the workflow pin, this ADR, the postmerge skill and the runbook section 5c one-liner). An id mismatch, zero matches or more than one match is a finding. The pin defends against a planted read-only token that points at another Hetzner project holding a same-named volume: that token cannot produce a clean verdict. It does not defend against an edit that changes the `.tf`, the pin and the workflow in one diff, so the check proves live-versus-declared consistency, not integrity. The outside anchors are the effective-text pin in `plugins/soleur/test/terraform-target-parity.test.ts` (a required check), Guard 1, and the live Hetzner state, which no diff can edit.

**A mis-minted token is undetectable here.** The job reads `HCLOUD_TOKEN_READONLY` from `prd_terraform` with no fallback to the read/write `HCLOUD_TOKEN`, so the job never selects or exports it (`DOPPLER_TOKEN` could still read the read/write token until the O10 eviction of the legacy fallback; D1 of the plan's decision record). The job cannot tell a Read-permission token from a read/write one stored under that name; the control is step O5 of `infra-credential-tiers-8209.md`, whose probe proves the stored token cannot write. A missing, empty or rejected token yields the verdict `no-token` and a separate could-not-perform issue, never a clean result.

**Limits, stated.** The effective gap between checks can exceed 12 hours: the dispatcher fires at 06:00 and 18:00 UTC, but the workflow's concurrency group keeps one running and one pending run, so a manual dispatch during the queue can drop a scheduled check, and a branch dispatch skips the job. Nothing consumes the job's conclusion automatically (a Sentry check-in is the tracked follow-up #10430), so a red run reaches ops through the issue and the notify-ops-email fallback. The read is a point-in-time flag read; it is not a `prevent_destroy` read-back, which stays a plan-time control enforced by the guards named in this ADR. Scope is the Inngest store volume only; the web-1 `workspaces_luks` volume (ADR-119) is not covered; a check for it is the tracked follow-up #10432. A shared pinned Doppler-install step for the loader, this job and cloud-init is #10431. The residuals, the loss-mode table, the absent Art. 32(1)(c) restore capability and the "no sanctioned erase path" statement are unchanged.

## Addendum — 2026-10-19 (#9927 item 5, state-loss import rehearsal)

Appended, with one exception to the append-only convention, stated here: the loss-mode row "Terraform state entry lost" above was edited in place, rewritten in place: the `import {}` parenthetical, the "State-loss recovery" sentence and the DEFERRED clause are replaced by a short pointer to this addendum, and the argv sentence gained the echo fact and the 0600-file handling. Those sentences were falsified by the result below, and a row that contradicts its own addendum is the worse record. The rehearsal itself lives in a sibling suite, not in the rehearsal root (CTO ruling R1 of this PR: that root's file inventory is closed and it is applied against real state). Status stays `accepted`; no frontmatter change.

**UNVERIFIED first.** Not run against R2-backed state (the real backend has no lock and no versioning). Not run through the per-merge destroy-guard on the full production plan, which also carries the Doppler copy; the guard's filter is fed a one-resource fixture only. Not run for any other passphrase (`workspaces_luks_web` and the rest stay with ADR-006's caveat). The relation to the Doppler copy is not exercised: the owner's digest comparison is circular when the value is taken from that copy, so it detects mistyping only, and nothing in the recipe checks that the value opens the LUKS header. Terraform versions other than the ones named below are not covered. The owner procedure in the runbook as a whole was not executed by any agent: the suite proves the terraform behaviour it relies on, not the credential wrapper, the `gh` in-flight check or the cleanup commands.

**VERIFIED (offline, local state, a synthetic value, the passphrase resource block extracted from `inngest-redis-luks.tf`, random provider 3.9.0 from the parent root's lock).** Suite: `apps/web-platform/infra/inngest-redis-luks-import-rehearsal.test.sh`, run by the `deploy-script-tests` leg. Terraform 1.9.8 locally. The CI leg pins 1.10.5 (`TERRAFORM_VERSION` in `infra-validation.yml`; the suite refuses to run on another version in CI), and the suite PASSED there on 2026-10-19 (`infra-validation` run 39264346083, head `cb03ab32b1`, 81 cases, shard 1/4). So the measurements below hold on both 1.9.8 and 1.10.5. A first CI run of the battery had failed for a reason unrelated to terraform: the provider's unix socket path overflowed under the runner's scratch root, fixed by a short child root. The behaviours were not re-measured by hand on 1.10.5; the passing suite is the observation.

- (terraform 1.9.8, provider 3.9.0.) After state loss, an import of the value gives `special = true` (the provider hard-codes it) and the plan is a replacement (`special true -> false`) that `prevent_destroy` turns into a hard error (exit 1); an apply is refused and the key is unchanged. So, while `prevent_destroy` stays in the configuration, no plan or apply can mint a new key before the repair.
- Pulling the state, setting `special = false` on that one instance, raising the serial by one and pushing it makes the plan report "No changes" (exit 0) with the value digest equal to the pre-loss digest. A stale-serial push is refused without `-force`.
- Negative control: the same sequence without `prevent_destroy` mints a different key, so `prevent_destroy` is the load-bearing backstop.
- The repo's real destroy-guard filter scores the state-loss plan `luks_passphrase_rotations >= 1` (the HALT fires) and the repaired plan `0`.

**Correction.** This ADR and the runbook said an `import {}` block "plans as a no-op and passes the HALT". Measured, it does not: with the value supplied through a sensitive variable it plans "1 to import, 1 to add, 0 to change, 1 to destroy", errors on `prevent_destroy`, and (observed on terraform 1.9.8, recorded by the suite as a note and not as an assertion, like the fact that `terraform import` echoes the id) prints the value in the plan text. Neither route avoids the owner-local handling in the runbook.

**Accepted residuals.** This ADR is now in the leg's PR `paths:` list (added by this PR, beside the runbook entry), so an edit to it runs the suite. As read on 2026-10-19, that edit overlaps the open PR 10501, which also edits `infra-validation.yml`; the two hunks are not adjacent. As read on 2026-10-19, the `deploy-script-tests` leg is advisory, not merge-blocking, so a red suite is visible but does not stop a merge; the main-branch health monitor (its own terraform pin is also 1.10.5, as read on 2026-10-19) opens an issue on a red main run, and a registry outage during the suite's `init` would show there as a red run.

## Addendum — 2026-10-22 (#9927 items 6, 8b and C1, measured versus not measured)

Appended. Measurements live in `knowledge-base/project/specs/archive/20261022-221258-feat-one-shot-9927-inngest-luks-items-6-8b-c1/measurements.md`; rulings in the sibling `decision-challenges.md`. Evidence classes: measured, documented (not measured), could-not-measure, inferred, not measured.

| Item | Question | Answer | Evidence class | Date |
|---|---|---|---|---|
| 6 | Doppler plan tier | not exposed by the CLI identity | could-not-measure (`cli_exposes_no_plan_field`) | 2026-10-20 |
| 6 | Version-history retention by tier | Developer 3 days, Team 90 days (pricing page) | documented, not measured | 2026-10-20 |
| 6 | Oldest entry in the `soleur-inngest/prd` config log | 68 entries, oldest 2026-07-23 (89 days); project created 2026-07-08 | measured | 2026-10-20 |
| 6 | Rollback scope | per log entry (documented); never run | documented, not measured | 2026-10-20 |
| 8b | `HCLOUD_TOKEN_READONLY` listed, `HCLOUD_TOKEN` absent in `soleur/prd_terraform` | listed / absent (names only) | measured | 2026-10-20 |
| C1 | Surviving source for the affected-user list | Inngest Postgres half is a dedicated Supabase project: 14 tables, estimated ~937k `history`, ~182k `events`, ~1.6M `spans` rows, candidate column `events.event_user` (by name) | measured (estimates; names only) | 2026-10-22 |
| C1 | Non-null count, oldest row, rows tied to lost work, which users | not measured | not measured | 2026-10-22 |

Decisions. Item 6: Route A (Doppler version history) stays "unverified; treat as unavailable"; Route B (Terraform state value) is the planned-on recovery; the loss-mode cell carries an in-cell Superseded marker. The Route A rule: it counts as available only if the tier is MEASURED as paid, the documented rollback scope covers the key, and the oldest log entry is inside the repair horizon. The horizon is derived, not recorded anywhere else in the repo: the 12-hour drift cadence plus one working week for the owner to respond, rounded to **7 days**; the 89-day oldest entry meets it, and the tier is still not measured, so Route A stays unavailable. Item 8b: the legacy credential arm reads only `HCLOUD_TOKEN_READONLY` and refuses with a named verdict when it is absent or unusable (ADR-241 amendment-log entry of 2026-10-20; Site C `scripts/cutover-inngest.sh` and its `op=backup` path, which refuses since O10, are deferred to #10664, #9755). Item C1: the three queries (identity, columns, estimates) were sent through the dedicated read-only Management API endpoint (role `supabase_read_only_user`, one pinned project, literal catalog-metadata queries, output limited to numbers and shape-checked identifiers). Evidence class **partial**: a candidate source exists and is untested; "complete" is unreachable by this probe. The default of treating all active users as potentially affected stays in force, and the ciphertext backup (1b) stays parked.

CLO ruling 2026-10-22: C1 may ship, no stop condition. One published sentence (`docs/legal/data-protection-disclosure.md` section 2.3(o), "no external sub-processor") does not describe the Supabase-hosted run-history half; it predates C1 and is tracked in #10849. Retention and Art. 17 reach of the Postgres history are tracked in #10848.

The probe script and its suite were removed in this PR (CTO, 2026-10-22): the finding is recorded, and a committed path to an account-wide Supabase management token that reaches the production app project is the less safe state; the method and queries live in `measurements.md` and git history, and a round 2 would be a separate owner-gated change with its own suite.

C4: no change. `inngestPostgres` and its edge from `inngest` already exist in `model.c4`; the probe was a one-off operator tool, not a standing relationship, so no founder-to-Supabase edge is drawn.

## Addendum — 2026-10-23 (#9927 item 7, Hetzner project-deletion coverage, documentation read only)

Appended; the only change above is the residual "Hetzner project deletion or account loss": it now states the planning posture in place of a bare "unverified". Status stays `accepted`. Evidence classes as in the 2026-10-22 addendum. Public documentation files were read on 2026-10-23; no Hetzner API call, account access, write or live test was made.

| Question | Answer | Evidence class | Date |
|---|---|---|---|
| Does delete protection block deleting the volume itself? | The Cloud API reference (`https://docs.hetzner.cloud/cloud.spec.json`, Delete a Volume) says the Volume must not be attached to a Server and must not have delete protection enabled; the protection flag `delete` "prevents the Volume from being deleted" | documented, not measured | 2026-10-23 |
| Is protection a safeguard against accidental deletion, and on which resource types? | The servers FAQ (`https://docs.hetzner.com/cloud/servers/faq/`) says a protected resource must have its protection removed before deletion, calls protection "an additional safeguard for accidental deletion", and names servers, snapshots and floating IPs (volumes are not named on that page) | documented, not measured | 2026-10-23 |
| Does delete protection block deleting the containing project, or survive account loss? | Not found in the pages read: the API reference holds no text pairing a project with deletion, `docs.hetzner.com/accounts/` returned 404, and the cloud general FAQ (`https://docs.hetzner.com/cloud/general/faq/`) says nothing about whether protection blocks deleting a project, or about account closure (its only mention of deleting a project concerns moving a resource between accounts), nor do the account-deactivation and account-deletion entries of the data-protection page (`https://docs.hetzner.com/general/company-and-policy/data-protection-at-hetzner/`) | not measured | 2026-10-23 |

Terms and conditions, the projects documentation, the cloud changelog and the Terraform provider documentation were not read, so "not found in the pages read" is scoped to the pages above. The planning posture stands until Hetzner documentation or written support confirmation says otherwise, and even then account loss (suspension or closure) would need its own evidence. Delete protection is documented only as a safeguard against accidental deletion; treat it as no cover against project deletion or account loss until evidence says otherwise. The same unknown applies to any other Hetzner volume in the project, including the web-1 workspaces volume (ADR-119 records no such residual); this addendum does not edit ADR-119. For the volume this ADR protects, no off-project copy of its data exists today (see the residual "The ciphertext has no backup"); adding one is a separate spend and effort decision this item does not make.

The optional scratch-volume proof that detach works under delete protection is dropped: it is a Hetzner write and out of scope for a documentation read. The first sanctioned host replace remains the live proof that Hetzner allows detach of a delete-protected volume (see the residual on the first sanctioned host replace above); it proves detach under protection only and does not settle project deletion or account loss.

A written Hetzner support question is one non-binding, owner-side, read-only way to settle the fact; it is not the only route and not a gate, and a live deletion test is out of scope because project deletion is irreversible.

Ruled by CTO agent, 2026-10-23: state the planning posture "plan as if project deletion or account loss destroys the volume regardless of delete protection" and label the underlying fact not established, in the reworded residual plus this addendum - docs-silent evidence does not separate the options, so the stricter one wins: assuming protection survives risks sole-copy data loss, assuming it does not costs no data, only a pending mitigation decision (rationale amended the same day on review dissent; the posture is unchanged).

## Addendum — 2026-10-24 (#10952, the id pin gains two consumers)

Appended; nothing above is edited and the status stays `accepted`. The Hetzner id pin that the recurring protection check carries (addendum 2026-10-16) now has two more consumers: the two orphan sweeps in `scheduled-terraform-drift.yml` each prove, before listing, that their read-only token can see this volume (one GET by id; HTTP 200 and the pinned id). `plugins/soleur/test/sole-copy-drift-check.test.sh` row N1b pins exactly three `readonly VOLUME_ID_PIN=` copies in the workflow, all equal, beside the existing equality with this ADR, the postmerge skill's one-liner and the runbook's. Who owns a bump: the founder, as incident owner, in the same cycle as the change that recreates the volume; the checklist is in the runbook `inngest-luks-cutover-6894.md`. A red sweep during a sanctioned volume recreate, before the bump lands, is expected and not a regression: it is the same condition the protection check reports, and the sweeps list nothing while it holds (recorded in ADR-241, 2026-10-24).
