---
feature: feat-one-shot-8737-rotate-ghcr-minter-token
issue: 8737
plan: knowledge-base/project/plans/2026-09-25-security-rotate-ghcr-minter-write-doppler-token-plan.md
lane: cross-domain
---

# Tasks — rotate ghcr-minter-write and revoke the orphan (#8737)

## 1. Setup

- [x] 1.1 Bump `BASELINE_DECLARED_PROBES` 29 → 30 in `plugins/soleur/test/preflight-discoverability-test.test.ts`, with a PLACEMENT/TRUTH/NO SUBSTITUTE comment. Do this in the first commit; the plan's `credentials_required` already moved the count.
- [x] 1.2 Positive control: the main verifier invocation prints `STALE` (exit 1) against today's Doppler state.

## 2. Core implementation

- [x] 2.1 `apps/web-platform/infra/ghcr-minter-doppler-token.tf`:
  - [x] 2.1.1 Set `name = "ghcr-minter-write-2026-09-25"` and add `lifecycle { create_before_destroy = true }` to `doppler_service_token.ghcr_minter`.
  - [x] 2.1.2 Replace the header's `-replace` rotation sentence with a ROTATION note of four lines at most (rename + CBD + `[ack-destroy]`; inert container copy under `GHCR_MINTER_DISABLED`; rotated-from line with slug `61c939b5…`, #8705/#8737 and the ADR-096 5.4 retirement; the `Verify:` command).
  - [x] 2.1.3 Correct the `doppler_secret` comment: the delivery route is `ci-deploy.sh` → `docker run --env-file`, not `webhook-deploy`, and "a rotation (the rename above)" replaces "a `-replace` rotation".
- [x] 2.2 `apps/web-platform/infra/token-drift-read-tokens.tf`: reword the "NO DISPATCH ROUTE" paragraph (comment only). `web_probes` and `ghcr_minter` now document the rename route, and #7263 still covers the `-replace` arm.
- [x] 2.3 `apps/web-platform/infra/scripts/web-probes-token-rotation-verify.sh`, header comments only:
  - say it is the generic verifier for a Doppler service-token rotation (`web_probes`, `ghcr_minter`);
  - change REMOVAL to "retire when no `.tf` ROTATION note references it".
- [x] 2.4 `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`, in the O12b row and the paragraph that repeats it:
  - change the name to `ghcr-minter-write-*`;
  - replace the `ghcr-minter-doppler-token.tf:45` cite with the content anchor `` resource "doppler_service_token" "ghcr_minter" ``.

## 3. Testing and pre-merge verification

- [x] 3.1 `grep -c -- '-replace' apps/web-platform/infra/ghcr-minter-doppler-token.tf` prints `0`, and `grep -c 'webhook-deploy'` on the same file prints `0`.
- [ ] 3.2 `terraform validate`. In the PR plan, `doppler_service_token.ghcr_minter` shows `must be replaced` (`+/- create replacement and then destroy`) and the secret shows `will be updated in-place`. Stop if either shape differs.
- [x] 3.3 These stay green:
  - `bun test plugins/soleur/test/preflight-discoverability-test.test.ts`
  - `bash apps/web-platform/infra/web-probes-token-rotation.test.sh`
  - `bash plugins/soleur/test/c4-count-parity.test.sh`
  - `bun test plugins/soleur/test/terraform-target-parity.test.ts`
  - `python3 scripts/lint-infra-no-human-steps.py --changed`
- [x] 3.4 C4: read `model.c4`, `views.c4` and `spec.c4`, and confirm there is no element or edge change (`inngest -> doppler` is already marked inert).
- [ ] 3.5 PR body:
  - the first line answers "does merging this mutate production?" with **yes**;
  - it carries `Ref #8737`, `Ref #8734` and `Ref #8714`, never `Closes`;
  - it uses the CLO wording rule;
  - it notes the routine web-platform release and the inert container copy.

## 4. Orphan revoke (agent-run; explicit go-ahead; preferably before the merge)

- [ ] 4.1 Per-item re-read of slug `e8e5187f…`, repeated right before the revoke if more than an hour has passed:
  - full slug, name, access, `created_at` and `last_seen_at`;
  - the creator from the config log (a `user`-kind actor is expected).

  If `last_seen_at` is later than `2026-07-30T11:20:45.359Z`, or the creator is an `apiToken`, take the incident branch: `soleur:incident`, an urgent revoke, and #8734 widened with a prd integrity sweep.
- [ ] 4.2 Send one plain-language message that leads with the decision. After the go-ahead, run the fail-closed revoke from plan Phase 3 step 3: it refuses on an empty `DOPPLER_TOKEN_TF` and has no `2>/dev/null`.
- [ ] 4.3 Post the pre-revoke fields and the outcome on #8737 immediately.
- [ ] 4.4 Run the orphan verifier. It prints `MISSING` before the merge and `ROTATED` after it; `STALE` is a failure.

## 5. Merge and post-merge verification

- [ ] 5.0 Re-read `61c939b5`'s `last_seen_at` and post it on #8737.
  - If it is later than `2026-09-24T14:25:50.862Z`: take the incident branch, and after the go-ahead revoke the token out of band. The next apply is then a plain create with no ack.
  - Merge within 24 hours of the PR being marked ready, or use the same out-of-band revoke.
- [ ] 5.1 Pre-merge checks:
  - none of the four `terraform-apply-web-platform-host` workflows has a run queued, in progress or waiting;
  - the latest main push apply planned 0 to destroy;
  - other merges are held until the apply starts.
- [ ] 5.2 `gh pr merge --squash --match-head-commit <head> --body-file <file>`, with `[ack-destroy]` on its own line.
- [ ] 5.3 Watch the push run by `head_sha` (Monitor). The only new entries against the pre-merge run are the token replace and the secret update, for a total of `2 added, 2 changed, 1 destroyed`. Use the Phase 4 step 3 recovery branches if needed. Send a recovery `[ack-destroy]` only if the halted run's refreshed destroy guard names `doppler_service_token.ghcr_minter` alone.
- [ ] 5.4 Both verifier runs print `ROTATED`, and each verdict's `src=` is recorded. The listing holds exactly these tokens:
  - `web-probes-read-2026-09-24`
  - `token-drift-ci-tf-prd`
  - one `ghcr-minter-write-2026-09-25`
  - `terraform-prd-20260730`
  - `github-ci-prd`

  The names-only `^dp\.` value scan of `soleur/prd` returns only `GHCR_MINTER_DOPPLER_TOKEN`.
- [ ] 5.5 Read the `soleur/prd` config log across every page, down to an empty one, and list the `apiToken` entries since 2026-07-29.
- [ ] 5.6 Hand off:
  - post the evidence on #8737 and close it;
  - post on #8734:
    - the go-signal, scoped to Doppler `soleur/prd` credentials;
    - the write/integrity limb request;
    - the GitHub App key path the signal does not cover;
    - the unexplained 09-24 14:25Z use as an open item;
    - on an incident, a widened scope, not a hold;
  - post on #8714: the UC-1 link, the -target trap, and the request to prioritize 5.4 before 2026-12-23.
