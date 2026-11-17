---
title: Key rotation for the non-tunnel secrets runs through a second dispatch-only route that sources the Inngest route and overrides it
status: active
date: 2026-11-02
supersedes: none
issue: 11294
related: [11294, 10205, 10540, 11920, 11922, 11923, 11927, 11928, 9294]
related_adrs: [ADR-307, ADR-241, ADR-100]
brand_survival_threshold: single-user incident
tags: [secrets, rotation, terraform, doppler, ci, authorization]
---

# ADR-317: Key rotation for the non-tunnel secrets runs through a second dispatch-only route that sources the Inngest route and overrides it

## Context

The audit behind #11294 found live key material in public Actions logs (a Terraform `random_id`'s `id` is the key in base64url, and
`hex` is not sensitive to Terraform), so the generated secrets need a rotation route that cannot print a Terraform stream. ADR-307
built one for the production Inngest signing and event pair: dispatch-only, every Terraform stream into a private file (`kr_tf`), an
exact gate table, a typed confirm, and a fleet redeploy. Seven further generated secrets have no route: the manual-trigger secret
(`prd` and `dev`), the dev Inngest signing and event keys, the kb-drift ingest signing key (two Doppler copies), the egress-audit
ingest token and the GitHub webhook secret. `tunnel_secret` is deliberately outside (ADR-307 amendment of 2026-10-29: a real rotation
replaces the tunnel and rebuilds web-2).

Facts established while planning, each verified against the repository:

1. ADR-307's body assumes Inngest: its title, its two phases and its host reboot do not describe a single-secret route with no host
   leg, and it has a `converge` mode these keys do not need. Folding the new keys into it would make its title false.
2. `scripts/inngest-key-rotate.sh` has a source guard, a non-readonly `KR_GATE_TABLE`, overridable `kr_refuse`/`kr_ok`, and a `kr_tf`
   that is Inngest-independent. Its Inngest sentences live in callers a new script would inherit, and bash binds late, so only a
   redefinition by the SAME NAME intercepts them.
3. The `infra-privileged` environment has a custom branch policy and zero required reviewers (measured 2026-11-02): the typed
   confirm is derivable from public inputs.
4. `egress_audit_ingest_token`: the route accepts a current and a previous token, but Vector reads the token only at start and no
   restart lever exists without a host shell (restarts live in Terraform provisioners and the Inngest bootstrap).
5. The full `terraform show -json` holds every root variable (including the workplace-scope Doppler token variable) and the prior
   state, so a plan stream is worse than one key.
6. Four of the seven secrets carry `lifecycle.ignore_changes=[value]` (the `inngest_*` ones); the others derive `value` from the
   `random_id` with no `ignore_changes`.

## Considered Options

- **Option A: source `scripts/inngest-key-rotate.sh` from a new `scripts/key-rotate.sh` and override what differs (chosen).** Pros: zero
  edits to a production route or its pinned suite; one copy of the security-critical chokepoint. Cons: coupling to the
  sourced file, bounded by guards (below).
- **Option B: extract a shared library and edit the production route.** Rejected: it edits a production route and its pinned suite for
  a route that is not the production one, and the extraction would have to carry every Inngest assumption out.
- **Option C: copy the chokepoint and add a parity test.** Rejected: it duplicates the security-critical Terraform chokepoint; two
  copies of the redirect that keeps keys out of a public log is the failure this ADR exists to prevent.
- **Option D: a new `apply_target` in `apply-web-platform-infra.yml`.** Rejected for the reason ADR-307 Option A was: the workflow sits
  within a few hundred bytes of its size gate and a per-merge workflow is the wrong place for a destructive single-use act.

## Decision

Build ONE dispatch-only workflow, `.github/workflows/key-rotate.yml`, with body `scripts/key-rotate.sh` (Option A) and suite
`apps/web-platform/infra/key-rotate-workflow.test.sh`. Modes are `plan` and `rotate`; one key per dispatch; the typed confirm
`ROTATE-<KEY>-<YYYY-MM-DD>` names exactly one key. The record, by item:

- **F1, source and override.** The script sources the sibling at top level, type-checks every symbol it relies on (`declare -F` for
  functions, `declare -p` for the three override arrays and the two jq scalars) and refuses with exit 78 before any Terraform call
  when one is missing or changed shape. It assigns `KR_GATE_TABLE`, `KR_INFLIGHT_WORKFLOWS` and `KR_VERDICT_TOKENS` wholesale and
  redefines the sourced functions of the same name (`kr_refuse`, `kr_ok`, `kr_print_contract`, `main`, `kr_chk_confirm`,
  `kr_stop_sentence`, `kr_post_write_stop`, `kr_file_issue`, `kr_verdict_recipe`, `kr_converge_cmd`, `kr_cmd_notify`) plus a `kr_out`
  allowlist. It has no `set -e` and no `trap` (the sourced `kr_init` owns the EXIT trap that removes the key-bearing temp files). The
  suite pins a sha256 over the sourced bodies the script calls and their callees, so a semantic change to the sibling forces a
  deliberate update here, and a sibling edit selects this suite. Fallback if a symbol proves Inngest-specific: Option C, never B.
- **F9, no converge and no redeploy-only mode.** A redeploy-only mode would be a third mutating path with its own authorization
  surface. A half-finished rotation is recovered by a fresh `rotate` of the same key under a fresh typed confirm; the previous value
  is not retained, so the direction is forward only. An interrupted `-replace` (delete then create) can leave copies absent, so the
  gate has a recovery arm: a bare create on the `random_id` row is accepted only when EVERY paired Doppler copy was absent at the
  pre-state, a bare create on a secret row only when its own copy was; a mixed state refuses `partial_absent_state` and is not
  auto-repaired; an unreadable listing refuses `copy_unreadable`.
- **Update in place where there is no `ignore_changes`.** For `kb_drift_ingest_signing_key` (both copies), `github_webhook_secret` and
  `egress_audit_ingest_token` the rotation `-replace`s the `random_id` only; the `doppler_secret` copies update in place, so there is
  no absent-secret window. "Replace both" stays for the four `inngest_*` secrets that carry `ignore_changes=[value]`. The parity test
  in `terraform-target-parity.test.ts` derives each row's flag from the HCL and closes over every block that references the
  `random_id`. A dev plan rehearsal that shows anything other than `["update"]` with `after_unknown.value` reverses this.
- **F2, egress — amended 2026-11-05 (#11920): now fully rotatable.** Both flip criteria are met and the
  `egress_rotate_unsupported_no_vector_restart_lever` refusal is removed. The no-host-shell restart lever is `ci-deploy.sh`'s
  existing `restart` action extended to component `vector`: it runs `sudo /usr/bin/systemctl try-restart vector.service` — the
  exact argv of the already-live `DROPIN_TRY_RESTART` sudoers grant — fans out to every web host through the existing peers
  channel, and verifies `is-active` plus an `ActiveEnterTimestamp` delta per host through merged deploy-status frames. The
  Terraform-managed previous-token secret is `doppler_secret.egress_audit_ingest_token_previous` in `egress-audit.tf`, fed by a
  sensitive variable (`default = ""`, `ignore_changes=[value]`, written only by `-replace`). A Doppler CLI write of
  `EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS` remains unacceptable — an untracked mutation of state Terraform should own. The ordering is
  lossless: apply-A writes PREVIOUS=old AND CURRENT=new in one apply, the fleet redeploys (the app then accepts both), vector
  restarts on every host, and only then a clear apply `-replace`s PREVIOUS back to the empty default. Any host failing the restart
  or its verify ends the run non-success with PREVIOUS retained, so an old-token send is never rejected.
- **G6 and H2, the authorization posture, stated plainly — amended 2026-11-05 (#11923).** The typed confirm is a fat-finger
  guard, not an authorization. The reviewer-gated environment now exists and is bound: `key-rotate-approval`
  (Terraform-provisioned, `required_reviewers` = user 54279, a `main`-only custom deployment-branch policy, `prevent_destroy` on
  the policy), bound by a dedicated credential-free `approve` job between `guard` and the first production-mutating job of
  `key-rotate.yml` (`mode=rotate`) and `inngest-key-rotate.yml` (rotate + converge); `mode=plan` never gates. The env deliberately
  holds no secrets — `DOPPLER_TOKEN_INFRA_PRIVILEGED` is an env-scoped secret the TF GitHub App cannot write (ADR-100 fix-forward,
  ADR-241 Tier-B) — which is why a separate `approve` job binds it rather than rebinding `apply`'s `environment:`. `kk_chk_approval`
  is now a live verify of the environment's `protection_rules`, refusing `approval_environment_unprotected` when
  `required_reviewers` or `branch_policy` is absent, fail-closed on API error — `approval_environment_missing` and the three
  unrotatable keys it named are gone. `authorization_stale` measures from the approve job's `approval_epoch` output, not the
  guard's clock, so a queued approval of any length cannot self-refuse. The other bounds are unchanged mechanisms: a `main`-only
  ref rung, a bot-actor refusal, a committed exact-match owner-login allowlist checked against both `github.actor` and
  `github.triggering_actor`. Residual, stated plainly: a personal-access-token dispatch still STARTS the run, but it now parks at
  `approve` — the reviewer gate bounds it to a distinct human act; a PAT *approval* of that job remains the owner's click by
  design. The "an agent never dispatches rotate" policy is superseded by the 2026-11-08 ruling below; the reviewer-gate mechanism
  still does not trust the dispatch. The dev keys follow parity with ADR-307.
- **F3, the `_dev` keys redeploy too.** A dev rotation is the shakedown of the whole route and does not count unless `track.sh`
  reports success; a dev rotation that skips the redeploy would not exercise the route's last leg. The production redeploy gives a
  dev key no pickup (no production container reads `soleur/dev`); making it skippable once the route has run is #11927.
- **Trio isolation (F7).** The deploy trio (`WEBHOOK_DEPLOY_SECRET`, `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`) is named in
  exactly one step's `env:` (the `track.sh` step of the redeploy job, no `GH_TOKEN`, no Doppler token); the apply job holds the
  Tier-B credentials and never names the trio. The separation is text-level only until #9294 closes: the Terraform job can read the
  trio through `prd_terraform`. The census `@allow` lines are a separate prerequisite change.
- **Redaction sanity (H3).** The credential-free `guard` job runs the redaction suite on the dispatched ref under `env -i`, requires
  the labelled rows for the tainted, deposed and drift shapes, and `apply` runs only if `redaction_ok` is true. This is an ordering and
  sanity step; the safety weight is the no-stream design (a Terraform stream never reaches a log; the plan JSON is projected to five
  fields and deleted at once).
- **Failure channel.** Issues are filed ONLY by the `notify` job (the only job with `issues: write`), with a re-list after the create
  call that fails loudly (`issue_unfiled`); a `github_webhook_secret` rotation ends `owner_step_pending`, a deliberate non-success,
  until the owner updates the GitHub App webhook secret.

ADR-307 gets one pointer line and one `related_adrs` entry; its body is unchanged.

Review round 1 (2026-11-03, rulings R1-R4 in the decision-challenges record): after a landed write the redeploy re-check never refuses
on staleness, the kb window or `quiet_window` (it polls the transient rungs for at most 480 s, then refuses
`rotated_redeploy_failed`); `plan_ok` carries a report-only `rotate_would_refuse=<token|none>` field with no new token; the apply
step refuses `authorization_stale` before the write when its remaining time cannot cover the apply bound plus a margin; a notify
re-run adds no comment to an identical open issue.

Review round 2 (2026-11-03): in redeploy mode the poll does not treat runs of `web-1-swap` member workflows (`web-platform-release.yml`,
`apply-deploy-pipeline-fix.yml`) as blockers, because their deploy jobs are queued behind the redeploy job's own hold (UNVERIFIED live:
the first dev rehearsal settles it); every other related workflow still blocks. The kb_drift window budget includes the Re-checks step,
so the budget is 8100 s and the first unsafe start is about 00:45 UTC. Terraform stream files are deleted as soon as their exit code is
read, and `rotate_would_refuse` no longer reports `authorization_stale` (in plan mode it would measure the plan run's own age).

Membership in the `web-1-swap` group is per JOB, while the poll skips per WORKFLOW. `apply-web-platform-infra.yml` carries six
`web-1-swap` jobs (`ci_ssh_token_replace`, `vector_redeliver`, `web_host_create`, `web_host_replace`, `workspaces_luks_cutover`,
`workspaces_luks_recut`) but is deliberately NOT skipped in redeploy mode, because its routine apply job is not in the group. This is the
conservative side and it is UNVERIFIED live: a merge to main during a redeploy can make that file's routine apply block the poll for the
480 s wait and end in a false `rotated_redeploy_failed` (the new value is landed either way). The first dev rehearsal settles it. The suite
parses each in-flight workflow's swap jobs from the yml and pins the per-job map against a literal.

Suite timing: the suite's weight row is an estimate that has never been measured on CI and its per-suite bound is 840 s, below the leg's
15-minute ceiling so a hung suite fails by name. The first CI wall time of the suite's leg must be recorded here; if the leg exceeds about
700 s the suite moves to a lighter leg.

Amendment (2026-11-05, #11923 + #11920): F2 and G6/H2 are rewritten in place above. The approval gate's mechanism is the dedicated
credential-free `approve` job — rebinding `apply`'s `environment:` to the gated env was considered and rejected because it would force
the Tier-B env secret onto a second environment the TF GitHub App cannot write. The vector-restart lever reuses the existing `restart`
grammar plus the live `DROPIN_TRY_RESTART` sudoers argv — a new webhook hook, a new sudoers alias and an SSH-delivered provisioner were
all considered and rejected (the whole point is zero SSH-delivered artifacts). `infra-privileged` keeps zero reviewers: its
reviewerlessness is load-bearing for the unattended apply-on-merge and scheduled drift paths.

Amendment (2026-11-08): the agent-dispatch ruling. Ruled by CTO agent: an agent may dispatch `key-rotate.yml` /
`inngest-key-rotate.yml` `rotate`|`converge` ONLY under a fresh, per-command, in-session owner go naming the exact full
command; the reviewer click on the `key-rotate-approval` environment (approver: deruelle) is NEVER delegated; the approval
tap should land inside a measured release-quiet stretch — the apply path re-checks in-flight runs itself, so a run parked
at `approve` CAN still refuse post-approval. G6/H2's "an agent never dispatches rotate" is superseded accordingly; the
environment split is unchanged and live-verified 2026-11-08 — see ADR-307's 2026-11-08 amendment for the canonical table.

## Consequences

- Seven more secrets rotate without a Terraform stream in a log, with an exact gate, a recovery arm for an interrupted replace, and one
  issue per failed write. The production route and its suite are untouched.
- Coupling: an edit to the sibling that changes a sourced body turns the sha256 pin and the symbol check red here, so the cost of
  evolving the sibling rises by one deliberate update. The reverse test-selection edge keeps that visible on the PR that makes it.
- The webhook secret has a real gap window (single secret in the verifier, #11922) that the workflow narrows but cannot close; the
  owner step stays open and blocks a second rotate until closed.
- An absent or drifted-unprotected `key-rotate-approval` environment (the #6780 auto-create class, or a reviewers/policy edit)
  refuses every rotate dispatch at guard with `approval_environment_unprotected` — before anything is written, fail-closed on API
  error. Every rotate/converge dispatch then parks at `approve` until a listed reviewer clicks in the Actions UI; an abandoned run
  writes nothing, and the wait cannot self-refuse because `authorization_stale` measures from `approval_epoch`.
- A web host that fails `try-restart` or its verify ends an egress rotate non-success BEFORE the clear apply: PREVIOUS is retained
  and the old token stays accepted — the lossless direction. A failed or skipped clear apply leaves PREVIOUS populated
  indefinitely (the old token stays valid); the run ends non-success and the action-required issue is the record, with
  `doppler secrets get EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS` non-empty as the detector.
- The dev shakedown carries two unverified premises (`-replace` of an `ignore_changes` secret recreates it with the new value;
  `-replace` of an address absent from state plans a plain create); `value_unchanged` and the recovery arm are the detectors.

## Cost Impacts

None. No new vendor, tier or runner class; Doppler, GitHub Actions and the deploy webhook are existing accounts.

## NFR Impacts

None moved between tiers. The secret-handling posture of the generated secrets is unchanged at rest; the change is a rotation route.

## Principle Alignment

AP-001 (Terraform-only): Aligned - every change is a Terraform `-replace`/update through the existing Tier-B apply path; no `.tf` file is
edited. AP-008 (Doppler secrets): Aligned - the copies are read only through a hash on a pipe and written only by Terraform.
