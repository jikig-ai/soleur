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

# ADR-314: Key rotation for the non-tunnel secrets runs through a second dispatch-only route that sources the Inngest route and overrides it

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
  edits to a production route or its pinned 1806-line suite; one copy of the security-critical chokepoint. Cons: coupling to the
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
  redefines eleven functions by the same name (`kr_refuse`, `kr_ok`, `kr_print_contract`, `main`, `kr_chk_confirm`,
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
- **F2, egress is plan-only.** `mode=plan` covers it; `mode=rotate` refuses `egress_rotate_unsupported_no_vector_restart_lever`
  (#11920). A Doppler CLI write of `EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS` is not acceptable (an untracked mutation of state Terraform
  should own). Flip evidence: a verified no-host-shell restart lever plus a Terraform-managed previous-token secret rotated by
  `-replace` in the same apply.
- **G6 and H2, the authorization posture, stated plainly.** The typed confirm is a fat-finger guard, not an authorization. The
  `infra-privileged` environment has zero required reviewers, a personal-access-token dispatch is indistinguishable from the owner's,
  and "an agent never dispatches rotate" is a policy, not a mechanism. The bounds that are mechanisms: a `main`-only ref rung, a
  bot-actor refusal, a committed exact-match owner-login allowlist checked against both `github.actor` and
  `github.triggering_actor`, an `authorization_stale` bound (the UTC date and at most 60 minutes since the guard), and
  `approval_environment_missing` for the `_prd` keys and the webhook secret until the reviewer-gated environment of #11923 exists
  (lifted by a one-line change in the PR that binds the apply job to it). The dev keys follow parity with ADR-307.
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

ADR-307 gets one pointer line and one `related:` entry; its body is unchanged.

## Consequences

- Seven more secrets rotate without a Terraform stream in a log, with an exact gate, a recovery arm for an interrupted replace, and one
  issue per failed write. The production route and its suite are untouched.
- Coupling: an edit to the sibling that changes a sourced body turns the sha256 pin and the symbol check red here, so the cost of
  evolving the sibling rises by one deliberate update. The reverse test-selection edge keeps that visible on the PR that makes it.
- The webhook secret has a real gap window (single secret in the verifier, #11922) that the workflow narrows but cannot close; the
  owner step stays open and blocks a second rotate until closed.
- Until #11923, three keys cannot be rotated at all through this route; that is the intended failure direction.
- The dev shakedown carries two unverified premises (`-replace` of an `ignore_changes` secret recreates it with the new value;
  `-replace` of an address absent from state plans a plain create); `value_unchanged` and the recovery arm are the detectors.

## Cost Impacts

None. No new vendor, tier or runner class; Doppler, GitHub Actions and the deploy webhook are existing accounts.

## NFR Impacts

None moved between tiers. The secret-handling posture of the generated secrets is unchanged at rest; the change is a rotation route.

## Principle Alignment

AP-001 (Terraform-only): Aligned - every change is a Terraform `-replace`/update through the existing Tier-B apply path; no `.tf` file is
edited. AP-008 (Doppler secrets): Aligned - the copies are read only through a hash on a pipe and written only by Terraform.
