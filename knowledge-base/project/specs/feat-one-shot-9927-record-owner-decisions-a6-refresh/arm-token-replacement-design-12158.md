# Design - replacing the arm-token write path, moving flip-read to Tier B, revoking the arm token (Ref #12158, Ref #9927)

Status: design only. Nothing here is built, dispatched, revoked or applied. Written 2026-11-06 for PR 12219. Rulings are cited by row id in `decision-challenges.md` (same folder) and are not recopied: D1, D1b, D1c (the path and its delivery), D2 (the order), D3 to D4 (the revisit). The owner decisions behind them are in the ADR-282 addendum of 2026-11-06. Queue and run state is held on a single volume with no off-project copy; recoverability after a project or account loss is not established.

## The revisit question

At the next host replace, or on 2027-01-08 if that comes first (revisit tracker #12229), one decision must be recorded: **revoke the arm token, or keep it with a new date at most 90 days out.** Revoke becomes possible only when all of these hold: (1) the host replace and `op=resume` have run; (2) a replacement write path exists and has been proven by one green gated run; (3) the flip-read token has moved to Tier B; (4) the revoke change below is merged and the destroy is applied by the owner. If any is missing, the answer is "keep, with a new date".

The exposure that makes the question worth asking is stated once, verbatim, in the ADR-282 addendum of 2026-11-06 ("Standing exposure of the arm token"). In one line: a read/write token on `soleur-inngest/prd` is a repo-level secret that any workflow on a pushed branch can resolve.

## Current state (re-derive with the commands shown)

| Credential | Consumers | Re-derive |
|---|---|---|
| `doppler_service_token.inngest_arm_write` (repo secret `DOPPLER_TOKEN_INNGEST_ARM`) | `op=rollback` and `op=resume` only, via the step "Export Inngest arm token (gated ops only)" in `.github/workflows/cutover-inngest.yml` | `git grep -n DOPPLER_TOKEN_INNGEST_ARM -- .github scripts` |
| flip-read token (`DOPPLER_TOKEN_INNGEST_FLIP_READ`) | the step "Preflight - inherited-done check, fails closed on a blind instrument" of job `inngest_host_replace` | `git grep -n DOPPLER_TOKEN_INNGEST_FLIP_READ -- .github` |
| the Terraform mint and its two `-target` lines | `.github/workflows/apply-web-platform-infra.yml` | `git grep -n 'inngest_arm_write\|doppler_token_inngest_arm' -- .github` |

The two verbs read a flag and make exactly three writes: set `INNGEST_CUTOVER_FLIP=rollback`, delete `INNGEST_HEARTBEAT_URL`, set `INNGEST_CUTOVER_FLIP=flushed`. Their reads could use the flip-read token today; only the three writes need a write token. `scripts/cutover-inngest.sh` has five sites in the `rollback)` and `resume)` arms (`git grep -n DOPPLER_TOKEN_INNGEST_ARM -- scripts/cutover-inngest.sh`). Doppler tokens are scoped to a config, not to keys, so the replacement cannot be narrower than the arm token: the gain is in delivery, not in blast radius.

## The chosen path (by pointer)

Rows D1, D1b and D1c: a new Terraform-declared read/write service token on `soleur-inngest/prd`, with a name distinct from `inngest-cutover-arm`, copied by a staged script into a GitHub environment secret on `inngest-cutover` (a main-only environment with a required-reviewer gate). It is not written into the Tier-B project and the shared loader is untouched. Neither verb is retired.

Requirements that are not in those rows:

- Only `.github/workflows/cutover-inngest.yml` and `scripts/cutover-inngest.sh` change in the build PR. The existing ternary `(inputs.op == 'rollback' || inputs.op == 'resume') && secrets.X || ''` is the pin; the workflow has one job whose job-level `environment:` expression covers backup, rollback and resume, so "the write token and the loader never share a job" holds per dispatch only.
- A stale-token check: the first step of rollback and resume does an authenticated Doppler read with the new secret and refuses with a named verdict such as `write_token_stale` (fail closed). A `-replace` mints a new key and leaves the environment secret stale; the runbook says replace, then re-run the relay script.
- The relay script reads a `sensitive = true` Terraform output with `terraform output -raw`, passes it to `gh secret set --env inngest-cutover` on stdin, never echoes it, and refuses xtrace; a test pins the script text. It exists because the Terraform GitHub App cannot write environment secrets: the comment in `apps/web-platform/infra/inngest-arm-write-token.tf` that begins "secrets: the first apply failed 403 \"Resource not accessible by integration\"" records the 403.

## Sequence

Decision D2, with the precondition list per step. Only documents may land before the window.

0. Window preconditions (ADR-282 addendum, D6): #12213 closed by its owner after a green run on a main SHA containing PR 12210; the userdata-budget check on the dispatch SHA; the probe-carrying config bundle and digest promotion (#11266) with the dead-man alert PR (tracked in #12230); the Better Stack dead-man probe write (owner-authorised for the window, re-asked in session); a per-command in-session go naming the exact command line.
1. Host replace plus `op=resume`. Planning only, not dispatched; dispatch is the owner's per-command in-session go.
2. Build and prove the new write path: one green gated run of `op=resume` or `op=rollback`, or an authenticated Doppler API check that the new token is read/write on `soleur-inngest/prd`.
3. Move flip-read to Tier B: the `inngest_host_replace` job already runs under `environment: infra-privileged`, so its preflight reads the key from the loader once it is seeded into `soleur-infra-privileged/prd`.
4. The revoke change (below), then an owner-gated destroy.

A change to `cutover-inngest.yml`, to the inherited-done preflight, a new secret, or the `-target` lines moves the dispatch SHA, so steps 2 and 3 wait until after the window. If no window has happened by about 2026-12-08, steps 2 and 3 may move earlier with the dispatch SHA re-checked.

## The revoke change and its rollback

The change removes `doppler_service_token.inngest_arm_write` and `github_actions_secret.doppler_token_inngest_arm` from config, removes their two `-target` lines from `apply-web-platform-infra.yml`, drops the export step, keeps `github_repository_environment.inngest_cutover` and `github_repository_environment_deployment_policy.inngest_cutover_main` with their `-target` lines (the environment still gates `op=backup`, rollback and resume), and rewrites the file header. `inngest-arm-write-token.tf` is never deleted whole. Removing the `-target` lines alone does not revoke: the destroy is a separate owner-gated apply, or `doppler configs tokens revoke`.

Named rollback: re-mint with `-replace=doppler_service_token.inngest_arm_write` (documented in the file), then re-run the relay for the secret. Record date and evidence on #12158 when it happens.

## Failure modes

- The blast radius is unchanged by the replacement (a per-config token reads the LUKS key).
- Delivery narrows from a repo secret resolvable on any pushed branch to a main-only environment secret behind a reviewer gate.
- A stale or unset environment secret makes `op=resume` refuse with `write_token_stale` and blocks the recovery step after the next replace; the rehearsal for step 2 must include that refusal.

## Test pins

Listed once; each moves with the change it pins.

- The new secret name appears only in `cutover-inngest.yml`, only in steps limited to rollback or resume, and never in `.github/actions/infra-credentials/action.yml`.
- The Tier-B loader step stays `if: inputs.op == 'backup'`; no op arm combines the loader with the new secret.
- No `github_actions_secret` or `github_actions_environment_secret` resource carries the key (static grep).
- `tests/scripts/test-infra-privileged-tier-census.sh` gains an environment-scoped-name clause, and `DOPPLER_TOKEN_INNGEST_ARM` leaves `REPO_SCOPED_PRIV` in the revoke change.
- `apps/web-platform/infra/cutover-inngest-workflow.test.sh`, `inngest-host-replace-preflight.test.sh` and `test-inngest-host-replace-gate.sh` move with the changes they pin.
- To check at build, not assumed: whether the census or the credential-tiers record requires every environment secret to be registered by name, and that `DOPPLER_TOKEN_INFRA_PRIVILEGED` is present on the `inngest-cutover` environment.
- The new token needs its own revisit coverage once it exists; the revisit probe watches only the arm token.

## ADR-241 fit

`inngest-cutover` is one of the four Tier-B environments, so the environment secret conforms to the tiering rule D2 of that record and removes the advisory deviation the repo-scoped arm and flip-read secrets carry. D3 of that record is not engaged (same reasoning as the ADR-282 addendum of 2026-11-05). The amendment-log entry belongs to the build PR.

## Held

Not authorised by this document or its PR: dispatching `apply_target=inngest-host-replace`; revoking, scoping or deleting the arm token; any write to Hetzner, Doppler or Better Stack; closing #9927, #12158, #12213 or #11265; the A6 sentence; building the off-project copy.

## Recorded now

The six owner decisions and the rulings (ADR-282 addendum of 2026-11-06); the design on this page; the superseded markers on the G2e sunset text; the revisit tracker #12229 and its date-only probe; the deferral tracker #12230.

## Built after the window

The new Terraform-declared write token and its `-target` line; the relay script and its test; the `cutover-inngest.yml` and `scripts/cutover-inngest.sh` changes with the stale-token check; the census clause; the flip-read move to Tier B; the revoke change and the owner-gated destroy; revisit coverage for the new token; the ADR-241 amendment-log entry; the off-project copy once the ADR-282 build conditions C1 to C11 hold.
