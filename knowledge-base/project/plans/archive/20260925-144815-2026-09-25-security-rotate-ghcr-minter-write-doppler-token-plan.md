---
title: "security: rotate ghcr-minter-write (read/write prd Doppler token, readable via the leaked web-probes-read token) and delete orphan ghcr-minter-write-20260729"
date: 2026-09-25
slug: security-rotate-ghcr-minter-write-doppler-token
branch: feat-one-shot-8737-rotate-ghcr-minter-token
issue: 8737
closes: 8737  # closed by a post-merge step once both verifier runs print ROTATED; the PR body carries Ref #8737, never Closes
type: fix
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# security: rotate the ghcr-minter-write prd Doppler token and delete its orphan sibling

## Enhancement Summary

**Deepened on:** 2026-09-25.

**Agents:**

- soleur:engineering:review:security-sentinel
- soleur:engineering:review:user-impact-reviewer
- soleur:engineering:review:observability-coverage-reviewer
- soleur:engineering:infra:terraform-architect
- a verify-the-negative sweep (standard tier). It confirmed every negative and exclusivity claim
  against the repo and found no contradictions.

**Key improvements:**

1. **The old token's last trace is captured.** `61c939b5`'s `last_seen_at` is re-read just before
   the merge, since the apply destroys it. An advance past `2026-09-24T14:25:50.862Z` takes the
   incident branch.
2. **Containment comes before the merge when needed.** The route is an out-of-band revoke after a
   go-ahead. The pinned provider's `resourceServiceTokenRead` drops a missing slug through
   `handleNotFoundError`, so the merge then plans a plain create with no `[ack-destroy]`. It is
   triggered by an incident or by the PR sitting 24 hours after it is marked ready.
3. **The #8734 hand-off is honest about its scope.**
   - The token-set check now covers every `soleur/prd` token, of any access level, including a
     duplicate from a provider create-retry.
   - #8705's transitive `^dp\.` names-only scan is repeated.
   - The go-signal is scoped to Doppler `soleur/prd` credentials, and names the GitHub App key path
     it does not cover.
   - An incident widens #8734 instead of holding back rotation.
4. **The revoke is safer.** It fails closed on an empty credential, so it never falls back to a
   local CLI login. The orphan's creator is recorded, and a stale role read is repeated before the
   revoke.
5. **Recovery is safer.** A recovery `[ack-destroy]` is sent only when the halted run's refreshed
   destroy guard names `doppler_service_token.ghcr_minter` alone.

**Verified premises:**

- In DopplerHQ/doppler `v1.21.2`, the token's `name` is ForceNew, and so is every other field of the
  resource. For `doppler_secret`, only `project` and `config` are ForceNew; `value` updates in place
  (`resource_secret.go`).
- Under create-before-destroy, the order is: create the new token, update the secret, destroy the
  deposed old token.
- Every cited issue, PR and run was resolved live. That covers #8202, #8714, #8734, #8754, #7263,
  #8850, #8851, #6074, #8733, #8703, #8036, #8209 and #6031, plus runs 36092626570, 36079251562 and
  36077212409.
- Every cited rule id is active in `AGENTS.md`.
- The `discoverability_test.command` passes `probe-verb-gate.sh` (rc 0). The rest of
  `preflight-discoverability-test.test.ts` passes over this plan (122 pass). The one fail is the
  expected G1 ratchet, 29 to 30, which the first work commit bumps.

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

Rotate the read/write `soleur/prd` Doppler service token that the GHCR installation-token minter
uses, with the rename + create-before-destroy shape already used for the web-probes read token, keep
minting working across the swap, and remove the orphaned sibling token that no Terraform resource
declares. This must land before any prd value rotation under #8734.

## Research Insights

### Premise Validation (Phase 0.6)

Every value below was pulled live on 2026-09-25 between 10:40Z and 10:50Z. Doppler reads used
`DOPPLER_TOKEN_TF` (it resolved from `soleur/prd_terraform`) and printed names, slug prefixes and
timestamps only. No secret value was printed.

| Cited premise | Checked with | Result |
|---|---|---|
| #8737 is open | `gh issue view 8737` | OPEN, no closing PR |
| #8705 / PR #8733 (the template) merged | `gh pr view 8733`; Doppler config logs for `soleur/prd` | Merged 2026-09-24T21:42:40Z. Its apply created `web-probes-read-2026-09-24` at 21:44:27.605Z and deleted `web-probes-read` at **21:44:28.389Z**. From that instant on, the leaked token can read nothing. **That is the cut-off used below (`--not-before 2026-09-24T21:44:28Z`).** |
| `ghcr-minter-write` is slug `61c939b5…`, read/write, created 2026-07-30 | `GET /v3/configs/config/tokens?project=soleur&config=prd` | Confirmed: `61c939b5`, `read/write`, created `2026-07-30T11:59:21.952Z`. Terraform state id `soleur.prd.61c939b5-…` (the #8754 drift log) |
| Orphan `ghcr-minter-write-20260729` is live | same listing | Confirmed: `e8e5187f`, `read/write`, created `2026-07-29T20:57:54.251Z` |
| "The running app container holds its env from container start, so the minter keeps the deleted key until the next web-platform deploy. Plan that deploy … so the GHCR token minting does not go dark." | `doppler secrets get GHCR_MINTER_DISABLED -p soleur -c prd` (a boolean flag); `cron-ghcr-token-minter.ts` (the handler's first branch); ADR-088 header; `model.c4` `inngest -> doppler` edge | **Stale premise.** Minting is already dark, on purpose. `GHCR_MINTER_DISABLED=true` in prd (since #6074, 2026-07-05). The handler returns on that flag **before** it reads `GHCR_MINTER_DOPPLER_TOKEN`. ADR-088 is `superseded`: a GitHub App installation token cannot `docker pull` a private GHCR package, so this minter cannot be re-enabled into a working state. The C4 edge records that its `GHCR_READ_TOKEN` write has had no consumer since #8036 1d (2026-09-24). The container's copy of the old key is never presented to Doppler. So the plan does **not** schedule a redeploy (Cut List). |
| "Find where its key is stored, if anywhere" (the orphan) | token listing `last_seen_at`; `soleur/prd` config logs | **Nothing has authenticated with the orphan for 57 days**: `last_seen_at = 2026-07-30T11:20:45.359Z`. `last_seen_at` is live-updated (the Terraform token, `terraform-prd-20260730`, read `10:45:17Z` at a `10:45:23Z` read). The logs show the orphan created at 07-29 20:57:54, a secrets write 14 s later (most likely `GHCR_MINTER_DOPPLER_TOKEN` pointed at it), then Terraform's `ghcr-minter-write` recreated at 07-30 11:59:22 with a secrets write in the same second, which is Terraform writing its own key back into `GHCR_MINTER_DOPPLER_TOKEN` (no `ignore_changes`). The #8754 drift plan shows no diff on `doppler_secret.ghcr_minter_doppler_token`, so the stored value is the Terraform token's key, not the orphan's. |
| #7263: "no dispatch route to rotate any `doppler_service_token`" | `apply-web-platform-infra.yml` main-apply `-target` list | True for `-replace`, which a merge cannot express. It does not block a **rename**. `-target=doppler_service_token.ghcr_minter` and `-target=doppler_secret.ghcr_minter_doppler_token` are both in the per-merge main apply (anchor: `-target=doppler_service_token.ghcr_minter \`). So the merge apply rotates it, gated by `[ack-destroy]`. #8733 set that precedent for `web_probes`. #7263 stays open; this plan does not add the dispatch arm. |
| #8754 drift affects the apply | `gh issue view 8754` (plan excerpt) | **No.** Its deletes and replaces (`doppler_secret.zot_heartbeat_url_prd`, `hcloud_server.git_data` / `.inngest` and their attachments) are either absent from the per-merge `-target` list or only in dispatch arms. Neither `doppler_service_token.ghcr_minter` nor its secret shows a diff. The per-merge apply therefore plans only this rotation. The pre-merge check below confirms it against the latest push run. |

**Additional live finding.** `ghcr-minter-write` (`61c939b5`) was last used at
`2026-09-24T14:25:50.862Z`. The minter is disabled and the inngest scheduler is down (#8850/#8851), so
the reader was not the minter. The most likely candidate is an identification probe during the #8705
review, which named this token's slug. That is unconfirmed. It is recorded on #8737 as evidence, and
it does not change the plan: the token is rotated either way.

### Property List (Phase 0.6b)

- **P1.** After the merge, Doppler `soleur/prd` lists no read/write service token that the leaked
  `web-probes-read` token could have read: slug `61c939b5` is gone.
- **P2.** The orphan read/write token `e8e5187f` no longer exists.
- **P3.** The minter's credential slot (`GHCR_MINTER_DOPPLER_TOKEN`) holds a key created after
  2026-09-24T21:44:28Z. So the slot keeps working if the minter is ever re-enabled, and the #8737
  closing criterion ("a replacement created after #8705's merge apply") holds.
- **P4.** Nothing that runs breaks. The only code reader, the minter, never reads the slot while it
  is disabled. Any deploy that re-enables it reads the flag and the slot from the same env-file, so
  it gets the new key.
- **P5.** #8734's value rotation can start: no credential the leaked token could read can read rotated
  values back.

### Cut List (Phase 0.6b)

- **A dedicated web-platform redeploy after the apply** (the issue's suggestion) → would buy P4 →
  already covered. The kill-switch runs before the token read, the flag and the token arrive in the
  same env-file, and every merge that touches `apps/web-platform/**` fires `web-platform-release.yml`
  anyway (`on.push.paths: 'apps/web-platform/**'`). Cut.
- **Having the minter re-read its token from Doppler at run time** → would buy P4 → same reasoning.
  It would also need a second Doppler credential inside the container to fetch the first. Cut.
- **A guard suite pinning the rotation shape** (the template's `web-probes-token-rotation.test.sh`
  Guards 1–2) → would buy "the next rotation is as safe" → the template pinned four SSH installers
  that each needed a hash trigger. Here the key's only consumer is one `doppler_secret` with no
  `ignore_changes`, and the consumer is disabled. The pre-merge grep ACs and the Terraform plan cover
  this one change. Cut.
- **A new rotation verifier** → buys P1–P3 → `apps/web-platform/infra/scripts/web-probes-token-rotation-verify.sh`
  is parameterized (`--retired-slug`, `--retired-name`, `--name-prefix`, `--not-before`) and matches
  `--retired-name` exactly, so it serves both slugs as-is. The web-probes name is historical. Cut.
- **Adopting the orphan into Terraform so a destroy removes it** → buys P2 → not possible:
  `doppler_service_token` in DopplerHQ/doppler v1.21.2 declares no `Importer`
  (`doppler/resource_service_token.go`). A direct revoke by slug is the only route. Kept as an
  agent-run post-merge step, not cut.

### Mechanism already on main (reused)

- The per-merge main apply `-target`s the token and its secret. The destroy guard counts a
  `doppler_service_token` replace as one `resource_deletes`, which `[ack-destroy]` clears, and no
  HALT arm (`host_creates`, reboot, LUKS, apex) is reachable. #8733 proved this for the same resource
  type on 2026-09-24.
- **A `name` change forces replacement.** It was verified in the pinned provider source, not
  inferred. `doppler/resource_service_token.go` at DopplerHQ/terraform-provider-doppler `v1.21.2`
  says "ForceNew is specified for all user-specified fields" and sets `ForceNew: true` on every
  schema field. The lock file pins `1.21.2`. #8733's rename of `web_probes` applied as a replace
  (`1 added, 1 destroyed`). So the old header's `-replace` recipe was never *needed* for rotation.
  It predates the rename shape.
- `create_before_destroy` on the token: Terraform creates the new token, updates the dependent
  `doppler_secret` in place, then deletes the old token. A failed create leaves the old token and the
  secret untouched.
- The read-only verifier: exit 0 = `ROTATED`, 1 = `STALE`/`MISSING`, 2 = `UNAVAILABLE`, header on a
  file descriptor, `DOPPLER_TOKEN_TF` resolved Tier-B first.
- No other workflow reaches the token. `apply-deploy-pipeline-fix.yml` targets `hcloud_server.web`
  and SSH installers, and no host template reads `ghcr_minter` (`git grep` returns only the workflow's
  two `-target` lines, the minter, its test and a `token-drift-read-tokens.tf` comment).

### Relevant learnings

- `knowledge-base/project/learnings/security-issues/2026-09-24-a-second-apply-workflow-could-perform-the-rotation-without-its-gate.md`:
  every workflow whose `paths:` and `-target` graph reach the rotated resource can apply it. It was
  checked here: only `apply-web-platform-infra.yml` reaches `ghcr_minter`.
- `knowledge-base/project/learnings/2026-09-24-the-verify-rows-i-called-host-health-were-the-verifiers-own.md`:
  the source of the rename + CBD shape (#8703).
- `knowledge-base/project/learnings/best-practices/2026-06-18-live-credential-rotation-and-argv-to-env-redeploy.md`:
  container env is fixed at `docker run`. It applies here only as the reason the premise asked for a
  redeploy; the kill-switch makes it moot.
- The #8705 plan's Sharp Edges (archived at
  `knowledge-base/project/plans/archive/20260925-112809-2026-09-24-security-rotate-web-probes-read-doppler-token-plan.md`):
  `[ack-destroy]` belongs to one push, a superseded run loses it, and the recovery is a new commit that
  carries the ack.

### Related

#8705 / PR #8733 (template), #8703 (first use of the shape), #8734 (value rotation, waits on this),
#7263 (no `-replace` dispatch arm), #8714 (ADR-096 task 5.4 retires this token, the minter and the
`ghcr_read_*` plumbing), #8754 (drift; does not touch this token), #8209 O12b (tokens created under
`DOPPLER_TOKEN_TF`; the replacement joins that set, and O12b enumerates from state), ADR-088
(superseded minter), ADR-096, ADR-119 2026-09-24 addenda (the rotation shape).

### CLAUDE.md / AGENTS conventions applied

- `hr-menu-option-ack-not-prod-write-auth`: the orphan revoke needs an explicit per-command go-ahead.
- `hr-bulk-delete-per-item-live-infra-role-check`: the orphan's role is re-read right before the
  revoke.
- `hr-no-dashboard-eyeball-pull-data-yourself`: every premise above was pulled live.
- `hr-no-ssh-fallback-in-runbooks`: every check is an API read.
- `hr-verify-repo-capability-claim-before-assert`: the verifier's matching was read, not assumed.
- `wg-when-an-audit-identifies-pre-existing`: the retire-instead alternative goes to
  `decision-challenges.md` and #8714.

### Write-limb evidence (added after the CLO review)

Doppler logs secret **writes** and attributes each one to its actor. A service-token write appears
with `user.kind = "apiToken"`, and the entry names the token and its slug. So the write half of the
question can be measured, unlike the read half. A read of the whole `soleur/prd` config log
(75 entries, back to 2026-06-30, taken 2026-09-25) found exactly two `apiToken` writes. Both are from
2026-07-05, by the **original** `ghcr-minter-write` (slug `ceed7f72…`, deleted 2026-07-30). Those
were the minter's first runs, before the kill-switch. **No entry is attributed to `61c939b5` or
`e8e5187f`.** On the log's own evidence, neither live read/write token has written `soleur/prd`.
Post-merge, this read is repeated up to the revocation instant (Acceptance Criteria), and the result
goes on #8734 (see Phase 4).

## Research Reconciliation — Issue vs. Codebase

| Issue claim | Reality | Plan response |
|---|---|---|
| "The running app container holds its env from container start, so the minter keeps the deleted key until the next web-platform deploy. Plan that deploy, or have the minter re-read its token, so the GHCR token minting does not go dark." | Minting has been dark on purpose since 2026-07-05 (`GHCR_MINTER_DISABLED=true`). The kill-switch branch returns before the token is read, and ADR-088 is superseded. | No redeploy step. The container's stale copy is inert and is recorded as such. The merge fires a routine `web-platform-release.yml` run anyway, because its `on.push.paths` include `apps/web-platform/**`. |
| "Rotate … using the rename + `create_before_destroy` shape from #8703 and #8705" | Both `-target`s are already in the per-merge main apply. Unlike `web_probes`, this key has no SSH installer, no `templatefile` consumer and no second workflow that reaches it. | Only the rename, the `lifecycle` block and the comment are needed. The template's guard suite, SSH-stage checks and web-2 re-seed are all left out. |
| "Find where [the orphan's] key is stored, if anywhere, and delete it" | The Doppler API cannot say where a key is stored. `last_seen_at` proves no use since 2026-07-30T11:20:45Z. The provider cannot import the token. | Re-read the orphan's role immediately before acting, then revoke it by slug with the Doppler CLI, after an explicit per-command go-ahead. The revoke is independent of the merge and may run first. |
| Closing criterion: "neither slug … and the replacement token was created after #8705's merge apply" | #8705's apply deleted `web-probes-read` at 2026-09-24T21:44:28.389Z | Two verifier runs, both with `--not-before 2026-09-24T21:44:28Z` |

## Proposed Solution

One small PR. Merging it changes production, because the push-triggered apply mints a new
read/write token, rewrites `GHCR_MINTER_DOPPLER_TOKEN` and deletes the old token. That is why the
merge commit carries `[ack-destroy]`. The orphan revoke is a separate agent-run command with its own
explicit go-ahead. It is independent of the merge and preferably runs first.

### Phase 1: Rotation shape (`apps/web-platform/infra/ghcr-minter-doppler-token.tf`)

1. Change `name = "ghcr-minter-write"` to `name = "ghcr-minter-write-2026-09-25"`. The date is only
   a label; a later merge date does not require changing it. The identity check is the retired slug
   `61c939b5`.
2. Add `lifecycle { create_before_destroy = true }` to `resource "doppler_service_token" "ghcr_minter"`.
   Leave `project`, `config`, `access = "read/write"` and the `doppler_secret` arguments unchanged.
   Do **not** add `ignore_changes` to `doppler_secret.ghcr_minter_doppler_token`: the new key must
   reach the secret in the same apply.
3. Replace the header's stale rotation sentence ("rotation is `terraform apply -replace=…`") with a
   ROTATION note of four lines at most:
   - Rotate by renaming, which is ForceNew in DopplerHQ/doppler v1.21.2, with CBD, merged with
     `[ack-destroy]`. The shared mechanics are in `workspaces-luks.tf`'s ROTATION comment.
   - The running container keeps the old value until its next deploy. That copy is inert while
     `GHCR_MINTER_DISABLED=true`, because the handler returns before reading the token.
   - Rotated 2026-09-25 from `ghcr-minter-write` (slug `61c939b5…`), which the leaked
     `web-probes-read` token could read until 2026-09-24T21:44:28Z (#8705, #8737). ADR-096 task 5.4
     (#8714) retires this file.
   - The `Verify:` line, with the exact command from Phase 4 step 4.
4. Correct the comment above `doppler_secret.ghcr_minter_doppler_token` (architecture review). It
   says the value reaches the minter through "the `> /etc/default/webhook-deploy` write in
   cloud-init.yml", but that file carries only `DOPPLER_TOKEN`, `DOPPLER_CONFIG_DIR` and
   `DOPPLER_ENABLE_VERSION_CHECK`. The real route is `ci-deploy.sh`'s `doppler secrets download`
   into `docker run --env-file`. Replace its "a `-replace` rotation" wording with "a rotation (the
   rename above)".
5. Keep the rest of the header unchanged, including the BLAST RADIUS paragraph. It is still true,
   and 5.4 owns its removal.

### Phase 2: Records (same PR)

1. **Runbook `infra-credential-tiers-8209.md`.** In the O12b row, and in the paragraph that repeats it
   (anchor: `` `doppler_service_token.ghcr_minter` (`ghcr-minter-write` on `soleur/prd`, ``), change
   the Doppler name to `ghcr-minter-write-*`. The wildcard means the next rotation needs no edit.
   The row also cites `ghcr-minter-doppler-token.tf:45`, which this PR's header rewrite moves.
   Replace it with the content anchor `` resource "doppler_service_token" "ghcr_minter" ``
   (`cq-cite-content-anchor-not-line-number`).
2. **`token-drift-read-tokens.tf` comment.** Its "NO DISPATCH ROUTE" paragraph says every sibling
   `doppler_service_token` "documents the same bare recipe". That is false for `web_probes` and, after
   this PR, for `ghcr_minter`. Reword it to say those two document the rename route, and that #7263
   still covers the `-replace` arm. This is a comment-only edit.
3. **Verifier header** (`apps/web-platform/infra/scripts/web-probes-token-rotation-verify.sh`, which
   is comments only). Say it is the generic verifier for a Doppler service-token rotation, now used by
   `web_probes` and `ghcr_minter`. Change the REMOVAL note from "meaningful only until image
   411798619 is deleted" to "retire when no `.tf` ROTATION note references it". Otherwise #8734's
   cleanup could delete a script that this token's `Verify:` line calls. Its suite checks verdict
   words only outside comments (`web-probes-token-rotation.test.sh`, "each verdict word appears once
   outside comments"), so a header edit cannot redden it. Do not rename the file: a rename touches
   the suite, the ratchet comment and an archived plan, all for a label.
4. **Ratchet.** This plan declares a single-line `credentials_required`, which moves
   `BASELINE_DECLARED_PROBES` in `plugins/soleur/test/preflight-discoverability-test.test.ts` from 29
   to 30 (measured: `Expected: 29, Received: 30`). The first work commit makes that bump, with a
   PLACEMENT/TRUTH/NO SUBSTITUTE comment in the style of the #8705 entry above the constant.

No ADR edit. Both simplification reviewers cut the proposed ADR-119 addendum: applying a recorded
shape a third time is not a decision. The architecture reviewer's advisory, a standalone
"token rotation by rename" ADR once a fourth token rotates, is recorded in Plan Review Revisions.

### Phase 3: Revoke the orphan (agent-run; gated on a per-command go-ahead; preferably before the merge)

The orphan is outside Terraform, so nothing waits on the apply. It needs revoking before #8734 for
the same reason as the main token. From 2026-07-29T20:58Z to 2026-07-30T11:59Z,
`GHCR_MINTER_DOPPLER_TOKEN` very likely held **the orphan's** key, so the leaked reader could have
taken it too. No committed configuration ever declared its name: `git log --all -S
'ghcr-minter-write-2026'` over `*.tf`, `*.sh` and `*.yml` returns nothing. It was minted outside
Terraform, so no state holds it, and the provider cannot import it.

1. **Per-item role re-read** (`hr-bulk-delete-per-item-live-infra-role-check`). Read the prd token
   listing. Record five fields of the one entry whose slug starts with `e8e5187f`:
   - the full slug;
   - `name == ghcr-minter-write-20260729`;
   - `access == read/write`;
   - `created_at == 2026-07-29T20:57:54.251Z`;
   - `last_seen_at`.

   Never identify the token by calling `/v3/me` with a stored value (Sharp Edges).

   Also record the orphan's **creator** from the `soleur/prd` config log (deepen: security). The entry
   `2026-07-29T20:57:54Z "Created read/write service token ghcr-minter-write-20260729"` is attributed
   to a `user`-kind actor, the workplace owner account. That same identity performs every Terraform
   apply, so the log cannot tell a Terraform apply from a manual action. An `apiToken`-kind creator
   would mean a service token minted it, which is an incident. If more than an hour passes between
   this read and the revoke (a late go-ahead), repeat it right before the revoke.
2. **Branch on `last_seen_at`:**
   - **Unchanged at `2026-07-30T11:20:45.359Z`:** go to step 3.
   - **Later than that:** an unknown party is using a read/write prd token. That is a security
     incident, not a pause:
     - record the new `last_seen_at` and the full config-log `apiToken` read (every page, down to an
       empty one) on #8737;
     - open a report with `soleur:incident`;
     - ask the operator for the revoke go-ahead **as urgent**, since revoking contains it;
     - **widen #8734 instead of holding it back** (deepen: security). Once both tokens are revoked,
       rotating values is always safe. The incident adds a full `soleur/prd` integrity sweep to
       #8734: every value, and every key an attacker could have added.
3. **One plain-language message to the operator** (CTO devex). It opens with the decision in plain
   words: "delete an unused spare production key that nothing has touched since July 30; it cannot
   be undone, and nothing will break". It then gives the evidence, then the exact command as
   reference. It asks nothing else. UC-1 is not raised here; `ship` carries it. Run the command
   **only after an explicit go-ahead for it** (`hr-menu-option-ack-not-prod-write-auth`):

   ```bash
   set +x
   T="$(doppler secrets get DOPPLER_TOKEN_TF --project soleur-infra-privileged --config prd --plain)" \
     || T="$(doppler secrets get DOPPLER_TOKEN_TF --project soleur --config prd_terraform --plain)"
   [[ -n "$T" ]] || { echo "no DOPPLER_TOKEN_TF resolved; refusing (the CLI would fall back to a local login)" >&2; exit 1; }
   DOPPLER_TOKEN="$T" doppler configs tokens revoke --project soleur --config prd --slug "<full slug from step 1>"
   unset T
   ```

   Fail closed on an empty credential (deepen: security). Otherwise the CLI silently falls back to
   the local login, a different identity. Lookup errors are left visible, with no `2>/dev/null`.

   <!-- verified: 2026-09-25 source: `doppler configs tokens revoke --help` (flags --project, --config, --slug; alias delete) -->

   The token travels in the child's environment, never in argv, and nothing echoes it. The identity is
   the workplace token that the Terraform provider uses to delete service tokens; it deleted
   `web-probes-read` on 2026-09-24.
4. **Record the evidence on #8737 immediately** (CTO devex). Post the step 1 fields and the revoke's
   outcome right after the revoke, not at the end. Once the token is gone, its pre-revoke
   `last_seen_at` can no longer be read. The issue is where a later session resumes.
5. **Verify.** Run
   `bash apps/web-platform/infra/scripts/web-probes-token-rotation-verify.sh --retired-slug e8e5187f --retired-name ghcr-minter-write-20260729 --name-prefix ghcr-minter-write- --not-before 2026-09-24T21:44:28Z`.
   The expected verdict depends on the order:

   | When | Verdict | Meaning |
   |---|---|---|
   | Revoked, rotation not merged yet | `MISSING` (exit 1) | The orphan is gone; no post-cut-off replacement exists yet. This is the correct intermediate state; do not treat exit 1 as a failure here |
   | Revoked, rotation applied | `ROTATED` (exit 0) | Both done |
   | Any time | `STALE` (exit 1) | The revoke did not take |

6. **No go-ahead yet.** Re-ask once a day, in the same plain message. #8737 stays open and #8734's
   go-signal stays withheld, because the orphan is as exposed as the main token. If 2026-10-04
   arrives without a go-ahead, say so on #8734. Its image-deletion deadline is 2026-10-06, and its
   value rotation can then be scheduled with the orphan explicitly named as a live exposure.

### Phase 4: Merge and verify (ship / postmerge; all reads automated, no SSH)

1. **Before merging:**
   - **Idle lock group.** None of the four workflows sharing the concurrency group
     `terraform-apply-web-platform-host` has a run `queued`, `in_progress` or `waiting`:
     `apply-web-platform-infra.yml`, `apply-deploy-pipeline-fix.yml`, `git-data-pin-redeploy.yml`
     and `registry-host-replace-dispatch.yml`. GitHub keeps one pending run per group, so a merge run
     queued behind a sibling is cancelled by the next push, and its `[ack-destroy]` goes with it.
     Hold other merges to `main` until this merge's apply job has **started**.
   - **No other deletes.** The latest `main` push run of `apply-web-platform-infra.yml` concluded
     `success`, and its main `Terraform apply` step planned **0 to destroy**. That run refreshes,
     unlike the PR's `-refresh=false` plan, so it is the pre-merge view of live drift in the targeted
     set. The residual risk is drift that appears between that run and the merge; the post-merge AC
     on the "will be destroyed" list catches it after the fact. `[ack-destroy]` acks every delete in
     the targeted plan, not only this one.
   - **Re-read `61c939b5`'s `last_seen_at`** and post it on #8737 (deepen: observability,
     user-impact and security all flagged this). Once the apply deletes the token, the value can no
     longer be read. If it is later than `2026-09-24T14:25:50.862Z`, take the Phase 3 step 2 incident
     branch. Also **contain first**: after an explicit go-ahead, revoke `61c939b5` out-of-band with
     the same fail-closed command and its full slug. The provider's `resourceServiceTokenRead` passes
     a missing slug to `handleNotFoundError` (DopplerHQ/doppler v1.21.2
     `doppler/resource_service_token.go`), which drops it from state. So the merge apply then plans
     a plain create plus the secret update, with 0 to destroy, and needs no `[ack-destroy]`.
   - **The merge is the containment clock.** `61c939b5` can write every prd secret until the apply
     runs. Merge as soon as the PR is green. If it is not merged within 24 hours of being marked
     ready, use the same out-of-band revoke path.
   - Merge with `gh pr merge --squash --match-head-commit <PR head> --body-file <file>`. The file
     carries `Ref #8737`, `Ref #8734` and `Ref #8714`, and `[ack-destroy]` on its own line, outside
     any fence or trailer.
2. **Find the push run by `head_sha`** and watch it with Monitor (`hr-dispatch-async-must-arm-watch`).
   Its main apply is compared with the latest pre-merge push run, not read as absolute counts. Every
   recent push run already carries two recurring changes, the standing #8202 pair:
   `cloudflare_bot_management.soleur_ai` (updated in place) and
   `github_repository_environment_deployment_policy.web_platform_infra_apply_main` (created). Runs
   36092626570, 36079251562 and 36077212409 each read `Plan: 1 to add, 1 to change, 0 to destroy`.
   The merge run should therefore read `2 added, 2 changed, 1 destroyed`. Its **only new entries**
   are:
   - `doppler_service_token.ghcr_minter`, marked `+/- create replacement and then destroy`;
   - `doppler_secret.ghcr_minter_doppler_token`, updated in place. The P3 evidence is its
     `Modifications complete` line; Doppler's config log does not name the secrets it changes
     (measured).

   The "will be destroyed" list names nothing but the deposed old token. **If the secret instead
   shows `must be replaced`**, stop before merging and re-plan rather than ack two deletes. The
   #8733 precedent had no `doppler_secret` consumer, so this shape is new here.
3. **Failure branches.** Each one ends with the same evidence as step 2, taken from the run that
   finished the job:
   - **Run cancelled or superseded before the apply:** nothing changed, and the next push run HALTs
     on the unacked delete, which blocks every other merge's apply. Recover at once with a
     comment-only commit to `ghcr-minter-doppler-token.tf` carrying `[ack-destroy]` on its own line.
     Only send it if **the halted push run's own destroy-guard output**, a refreshed plan, names
     `doppler_service_token.ghcr_minter` and nothing else (deepen: user-impact). The PR's
     `-refresh=false` plan cannot see drift, so it is not the check. The recovery commit also fires a
     routine web-platform deploy. Never re-run an
     older run after `main` has moved; a dispatch cannot carry the ack.
   - **Create failed:** CBD means nothing was deleted and the secret still holds the old key. Fix the
     cause and recover the same way.
   - **New token created, secret update failed:** the old token is still live and the secret holds
     the old key. The next run plans `0 added, 1 changed, 1 destroyed`. Recover with the same
     `[ack-destroy]` commit.
   - **Old token's delete failed (deposed object):** the verifier prints `STALE`, and the next push
     run HALTs. Recover with the same `[ack-destroy]` commit.
4. **Verify:**
   - `bash apps/web-platform/infra/scripts/web-probes-token-rotation-verify.sh --retired-slug 61c939b5 --retired-name ghcr-minter-write --name-prefix ghcr-minter-write- --not-before 2026-09-24T21:44:28Z`
     prints `ROTATED`.
   - The orphan invocation (Phase 3 step 5) prints `ROTATED`.
   - **The `soleur/prd` token set is exactly the known set** (deepen: security and terraform). One
     listing read must show these five tokens and no others:
     - `web-probes-read-2026-09-24` (Terraform);
     - `token-drift-ci-tf-prd` (Terraform);
     - exactly **one** `ghcr-minter-write-2026-09-25` (Terraform). A provider retry after a timed-out
       create can mint an untracked duplicate (`PerformRequestWithRetry` in `doppler/api.go`).
     - `terraform-prd-20260730` and `github-ci-prd`. Both are read-only and outside Terraform, and
       neither key is stored in `soleur/prd`.

     Any other entry is an incident. Then repeat #8705's transitive test. A names-only scan of
     `soleur/prd` values against `^dp\.(st|sa|pt|ct)\.` prints key **names** only, never values, and
     must return exactly `GHCR_MINTER_DOPPLER_TOKEN`.
   - **The verifier's credential source.** Record the `src=` from both verdict lines. A
     `src=soleur/prd_terraform` verdict carries the verifier's documented RESIDUAL: until #8209 O11,
     `DOPPLER_TOKEN_WRITE` can write that config. That is acceptable only with the listing read above
     taken from the same source, and the evidence comment must name the source.
   - **No Doppler syncs** (review: security). One metadata-only read of `soleur/prd`'s
     integration syncs must return none; a sync would carry the new read/write value off Doppler.
   - **Write-limb evidence, read once, now** (CLO; both simplification reviewers collapsed it to one
     read). Read the `soleur/prd` config log across every page until one comes back empty. List
     every `apiToken`-attributed entry since 2026-07-29. A revoked token cannot write, so this read
     covers the whole window.
5. **Record and hand off:**
   - **#8737:** both verdict lines, the apply run URL and the write-limb read. Then close it by hand.
   - **#8734:** the go-signal once both verdicts read `ROTATED` and the token-set and transitive
     checks are clean. The signal is scoped to **Doppler `soleur/prd` credentials**. The comment names
     the path it does not cover: `GITHUB_APP_PRIVATE_KEY` sits in prd, and the app's
     `administration`, `secrets`, `actions` and `contents` write grants
     (`apps/web-platform/infra/github-app-manifest.json`) are a route to CI-held credentials. That
     path belongs to #8734's value rotation. If any `apiToken` entry by either slug appears (token
     create/delete, config change or secret write), or Phase 3 took the incident branch, open a report
     with `soleur:incident` and **widen** #8734 with a full prd integrity sweep. Do not hold rotation
     back. The comment also asks #8734's step-4 correction to add a separate
     **write/integrity** limb, with the read limb recorded as INCONCLUSIVE. It records the
     unexplained `61c939b5` authentication at 2026-09-24T14:25:50Z as an open item.
   - **#8714:** one comment that links #8737 and UC-1 and asks for 5.4 before the Encryption Posture
     exception expires (2026-12-23). It states the retirement trap: the destroying apply must keep
     the two `-target=` lines, and a follow-up removes them.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| **Retire the token and its secret now** (the token half of ADR-096 task 5.4, #8714) | A stronger security outcome. It removes a read/write prd credential that every prd read token can read, which is a read-to-write escalation; the 13 token-drift read tokens are one example (`token-drift-read-tokens.tf`, BLAST RADIUS). It is safe at runtime, because the kill-switch runs first. But it contradicts the issue's closing criterion ("a replacement created after …") and the direction the issue states. It also has a trap: the destroying apply needs the two `-target` lines kept, and a follow-up removes them. **Recorded as a User-Challenge in `knowledge-base/project/specs/feat-one-shot-8737-rotate-ghcr-minter-token/decision-challenges.md`**, asking that #8714 5.4 be prioritized rather than left for after the #6122 settle period. |
| Same-name `terraform apply -replace=doppler_service_token.ghcr_minter` | A merge cannot express it (#7263). Without CBD it deletes first; with CBD it depends on Doppler accepting two same-named tokens, which is unprobed |
| A dedicated redeploy after the apply | Buys nothing: the minter is disabled, and the flag and the token arrive in the same env-file (Cut List) |
| Adopt the orphan into Terraform, then destroy it | The provider's `doppler_service_token` has no `Importer` |
| Leave the orphan in place | It is a live read/write prd token with no owner, and #8737's closing criterion requires it gone |

## Technical Considerations

- **Attack surface enumeration.** Every copy of the old key (`61c939b5`):
  1. Doppler `soleur/prd` `GHCR_MINTER_DOPPLER_TOKEN`: overwritten in the merge apply.
  2. Terraform state (R2): replaced by the new key in the same apply.
  3. The app container env on each web host (`docker run --env-file`, persisted in the container's
     `config.v2.json` on the root disk): dead after the apply, and replaced at the next deploy.
  4. Anything that read it through the leaked `web-probes-read` before 2026-09-24T21:44:28Z: dead
     after the apply. That is the point of this PR.
  5. **Every whole-config reader of `soleur/prd` holds a copy, and none presents it.** A Doppler
     config is not a consumer boundary. Every `doppler run … -c prd` or `secrets download … -c prd`
     reader receives this value with the rest of the config (`git grep` finds about 25 such files).
     Those readers include:
     - the web-host probe units and their encrypted fallback files under `/root/.doppler`;
     - the inngest host's bootstrap (`inngest-bootstrap.sh`, `cloud-init-inngest.yml`);
     - `web-platform-release.yml` and the release scripts on the CI runner (`github-ci-prd`).

     All of these copies are dead after the apply, and none is rewritten by this PR. Only the minter
     ever *presents* the key, and it is disabled.
  6. No `github_actions_secret`, host template or SSH provisioner consumes the key as a named input
     (`git grep`, Research Insights).
- **Where the new key lands** (deepen: security). It lands in several places:
  - Terraform state on R2;
  - the plan job's `tfplan.json` (`terraform show -json`, written to the infra directory on an
    ephemeral `ubuntu-24.04` runner and never uploaded). It holds the OLD key in plaintext under
    `before` (the new key is unknown at plan time); the same apply revokes that key;
  - `GHCR_MINTER_DOPPLER_TOKEN` in `soleur/prd`;
  - every later whole-config reader's copy, including Doppler fallback files and each web
    container's `config.v2.json` after its next deploy.
- **What the new key inherits.** The same exposure as the old one had: every prd read credential can
  read it, including every web host's root disk through the container env. So a future snapshot of a
  web host holds a live read/write prd token. This is the residual that ADR-096 5.4 (#8714) removes,
  and it is the argument in the decision challenge.
- **Timing.** The inngest scheduler is currently down (#8850/#8851). That does not affect this change,
  because nothing scheduled reads the token.
- **The merge also triggers `web-platform-release.yml`.** It deploys a new app image. That deploy's
  env-file may capture the old or the new key, depending on how it races the apply. Both are inert.
  The PR body says so.

## Hypotheses

No SSH or network step is involved. The change has no `provisioner`, no `connection` block and no
post-bridge SSH stage effect. The network-outage checklist does not apply.

### Network-Outage Deep-Dive (deepen-plan Phase 4.5)

The keyword scan fired on "SSH", but every hit is a negation. The resource-shape trigger does not
fire: neither targeted address has a `provisioner` or a `connection` block. The only network path is
the CI runner and the Terraform Doppler provider talking HTTPS to `api.doppler.com`, plus the
agent's own verifier and revoke calls to the same host.

| Layer | Status | Evidence |
|---|---|---|
| L3 firewall allow-list | Not in path | No host is contacted. Hetzner firewalls gate only tcp/22 and the private net. |
| L3 DNS/routing | Verified | Push runs 36092626570, 36079251562 and 36077212409 (2026-09-25) concluded `success`, including the Doppler provider refresh of `doppler_service_token.ghcr_minter` |
| L7 TLS | Verified | Same runs. The verifier's live read of the prd token listing returned HTTP 200 on 2026-09-25. |
| L7 application | Verified | The `last_seen_at` / config-log reads in Research Insights, 2026-09-25 |

## Architecture Decision (ADR/C4)

This plan makes no new architectural decision. It applies the rotation shape recorded in the ADR-119
2026-09-24 addenda to a third token.

### ADR

No ADR edit. The DHH and simplicity reviews cut the proposed ADR-119 addendum, because a third
use of a recorded shape is not a decision. If a fourth token is ever rotated this way, a standalone
"token rotation by rename" ADR is the right home (architecture review advisory, recorded in Plan
Review Revisions). The token's retirement is already recorded as ADR-096 task 5.4.

### C4 views

No C4 change. The model already contains every element this touches (`knowledge-base/engineering/architecture/diagrams/model.c4`):

| Kind | Element in the model |
|---|---|
| Actor | `founder` ("Founder / Operator") |
| External systems | `doppler` ("Doppler"), `github` ("GitHub"), `ghcr` ("GitHub Container Registry") |
| Container | `inngest` ("Inngest Server") |
| Access relationship | `inngest -> doppler` "Writes GHCR_READ_TOKEN … This minter is ALSO disabled in production (GHCR_MINTER_DISABLED=true), so the edge is declared-but-inert on both ends" |

The change swaps one credential on an existing edge that the model already marks inert. It adds no
element, no edge and no count. The work phase reads all three files (`model.c4`, `views.c4`,
`spec.c4`) to confirm this, then runs `bash plugins/soleur/test/c4-count-parity.test.sh`, which must
stay green.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. The minter is disabled, so no
  user-facing path uses this token. A half-finished rotation (the old token still listed, or no
  replacement) leaves the user-facing risk open: a live read/write prd credential reachable by the
  leaked read token's past holders, which blocks #8734.
- **If this leaks, the user's data is exposed via:** the old token reads **and writes** every
  `soleur/prd` secret. That includes `SUPABASE_SERVICE_ROLE_KEY` (bypasses RLS on every user's rows)
  and `GITHUB_APP_PRIVATE_KEY` (mints tokens that read and write every installed user's repositories).
  A write could also re-point a prd secret, such as a webhook URL or an API key, to an attacker's
  value, and the next deploy would pick it up.
- **Residual, not closed by this PR:**
  - Values already read or written cannot be revoked by rotating a token.
  - Reads: INCONCLUSIVE, because Doppler records no secret reads.
  - Writes: no `apiToken` write attributed to either live token appears in the prd config log
    (Research Insights). That record and the value rotation belong to #8734.
  - The new key carries the same structural exposure (every prd reader can read it) until ADR-096
    5.4 (#8714) retires it.
  - **Unexplained authentication.** `61c939b5` last authenticated at `2026-09-24T14:25:50Z`, inside
    the exposure window, while the minter was disabled and the scheduler down. The most likely
    reader is an identification probe during the #8705 review, but that is unconfirmed. It is
    recorded as an open fact on #8737 and in the #8734 hand-off, never as benign.
- **Wording (CLO):** "closes the leaked read token's forward reach to a read/write prd credential".
  Never "exposure closed", "not exposed" or "clean". The disabled minter is not offered as a
  mitigation of reachability.
- **Brand-survival threshold:** `single-user incident`. A read/write prd token can read the
  service-role key and change prd config, and one such use is brand-ending. CPO sign-off applies at
  plan time, and `soleur:engineering:review:user-impact-reviewer` runs at review.

## Observability

```yaml
liveness_signal:
  what: "Doppler service-token listing for soleur/prd, read by the parameterized verifier: slug 61c939b5 absent and a ghcr-minter-write-* token created after 2026-09-24T21:44:28Z present (a second run for slug e8e5187f)"
  cadence: "on demand: pre-merge (positive control STALE), post-merge (ROTATED); no recurring schedule, because the token has no running consumer while GHCR_MINTER_DISABLED=true"
  alert_target: "the ship/postmerge step that runs it (blocks closing #8737 and blocks #8734's value rotation)"
  configured_in: "apps/web-platform/infra/scripts/web-probes-token-rotation-verify.sh (existing; invoked with --retired-slug/--retired-name/--name-prefix/--not-before)"
error_reporting:
  destination: "workflow run log of the apply-web-platform-infra.yml push run (main Terraform apply step, destroy guard)"
  fail_loud: "the push run goes red at the destroy guard (HALT naming doppler_service_token.ghcr_minter when the ack is missing) or at the main Terraform apply step; GitHub failure notification to the operator"
failure_modes:
  - mode: "merge run cancelled or superseded, so [ack-destroy] is lost and every later push apply HALTs"
    detection: "workflow run log: the push run for the merge head_sha concluded cancelled, or a later run's destroy-guard HALT names doppler_service_token.ghcr_minter"
    alert_route: "GitHub failure notification; recovery = a comment-only commit carrying [ack-destroy] (Phase 4 step 3)"
  - mode: "create or secret update fails in the main apply (old token still live)"
    detection: "workflow run log: main Terraform apply step red"
    alert_route: "GitHub failure notification; recovery = [ack-destroy] commit (Phase 4 step 3)"
  - mode: "rotation not effective: old token still listed (delete failed, apply skipped by [skip-web-platform-apply], or never ran) or orphan revoke did not take"
    detection: "layer: none of 1-7 applies (a one-off change made out of band from the runtime); signal = the verifier prints STALE (exit 1) for --retired-slug 61c939b5 or e8e5187f in the ship/postmerge session, recorded on #8737"
    alert_route: "postmerge step (blocks closing #8737 and the #8734 go-signal)"
  - mode: "verifier cannot read the listing (credential moved by #8209 O10, Doppler outage)"
    detection: "layer: none of 1-7 applies (a one-off change made out of band from the runtime); signal = the verifier prints UNAVAILABLE (exit 2), which is inconclusive and never a verdict"
    alert_route: "postmerge step retries once, then records it on #8737, which stays open"
  - mode: "an unknown party is using the orphan or the old token"
    detection: "layer: none of 1-7 applies (a one-off change made out of band from the runtime); signal = the Doppler token listing's last_seen_at for e8e5187f (> 2026-07-30T11:20:45.359Z, Phase 3 step 2) or 61c939b5 (> 2026-09-24T14:25:50.862Z, Phase 4 step 1), or an apiToken-attributed prd config-log entry by either slug (Phase 4 step 4), read in the ship/postmerge session and recorded on #8737"
    alert_route: "soleur:incident report; out-of-band revoke after the go-ahead; #8734 widened with a prd integrity sweep"
logs:
  where: "GitHub Actions run log (apply-web-platform-infra.yml push run); Doppler soleur/prd config log (token create/delete and apiToken-attributed writes)"
  retention: "GitHub Actions 90 days; Doppler activity log per plan retention"
discoverability_test:
  command: bash apps/web-platform/infra/scripts/web-probes-token-rotation-verify.sh --retired-slug 61c939b5 --retired-name ghcr-minter-write --name-prefix ghcr-minter-write- --not-before 2026-09-24T21:44:28Z
  expected_output: "ROTATED"
  credentials_required: "Doppler workplace token-list read on soleur/prd (DOPPLER_TOKEN_TF, Tier-B: soleur-infra-privileged/prd, pre-#8209-O10 fallback soleur/prd_terraform) — service-token metadata (slug, created_at) is exposed by no unauthenticated endpoint and a read service token gets HTTP 403 on the list (measured 2026-09-24), and the property verified (slug 61c939b5 no longer exists; a replacement post-dates 2026-09-24T21:44:28Z) is observable only through that listing."
```

`ROTATED` is the result expected **after the merge only**. Before the merge, `STALE` is correct. For
the `e8e5187f` run, `MISSING` is correct between the orphan revoke and the apply. The probe is
SKIP-DECLARED at preflight through `credentials_required`. If that waiver is ever removed, set
`DOPPLER_TOKEN_TF` in the environment first: the verifier's two `doppler secrets get --timeout 10s`
fallbacks plus `curl --max-time 10` can exceed Check 10's 15-second cap.

## Encryption Posture

The change adds no store and no connection. It swaps a credential inside existing stores. The posture
is declared because the `.tf` edit triggers this gate.

```yaml
at_rest:
  - store: "Doppler soleur/prd secret GHCR_MINTER_DOPPLER_TOKEN (doppler_secret.ghcr_minter_doppler_token)"
    mechanism: "provider-managed:Doppler-SOC2-AES-256-GCM"
    evidence: "Doppler security page (https://www.doppler.com/security, retrieved_on 2026-09-25): 'SOC 2 certified' and AES-256-GCM encryption of stored secrets"
    defends_against: "a copy of Doppler's storage media or database leaving Doppler's control"
    does_not_defend: "any holder of a soleur/prd read credential (every prd service token, the token-drift read map, the app container env on each web host) reading the value through the API; a Doppler-side compromise"
    disclosed_as: not-publicly-claimed
    live_verification: "unavailable: provider-side encryption has no customer-readable probe; the token listing verifies rotation, not encryption"
  - store: "web host root disk: app container env (docker run --env-file, persisted in the container's config.v2.json)"
    mechanism: plaintext-exception
    evidence: "apps/web-platform/infra/ci-deploy.sh resolve_env_file -> docker run --env-file (full soleur/prd download)"
    defends_against: "non-root local users (dockerd state is root-owned)"
    does_not_defend: "anyone holding a copy of the root disk (a Hetzner snapshot image, a rescue mount) or root on the host"
    disclosed_as: not-publicly-claimed
    live_verification: "unavailable: no SSH runbook by rule (hr-no-ssh-fallback-in-runbooks)"
in_transit:
  - connection: "Terraform doppler provider (CI runner) -> api.doppler.com (token create/delete, secret write)"
    enforced_at: "apps/web-platform/infra/main.tf provider \"doppler\" (default HTTPS API host)"
    tls: "HTTPS, TLS 1.2+"
    cert_verification: "on"
    does_not_defend: "a compromised CI runner or a leaked DOPPLER_TOKEN_TF"
    disclosed_as: not-publicly-claimed
exception:
  justification: "the app container receives the whole prd config as env at start; this token rides that existing path until ADR-096 5.4 retires it"
  tracking_issue: "#8714"
  reevaluate_when: "ADR-096 task 5.4 lands (the token and GHCR_MINTER_DOPPLER_TOKEN are deleted), or the app stops receiving the full prd config as env"
  expires_on: 2026-12-23
```

## Files to Edit

- `apps/web-platform/infra/ghcr-minter-doppler-token.tf`: the rename, the `lifecycle` block, the
  ROTATION note, and the corrected `doppler_secret` comment (Phase 1).
- `apps/web-platform/infra/token-drift-read-tokens.tf`: a comment-only rewording of the "NO DISPATCH
  ROUTE" paragraph (Phase 2 step 2).
- `apps/web-platform/infra/scripts/web-probes-token-rotation-verify.sh`: header comments only, for
  the generic purpose and the REMOVAL note (Phase 2 step 3).
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`: the O12b token
  name and its content anchor (Phase 2 step 1).
- `plugins/soleur/test/preflight-discoverability-test.test.ts`: `BASELINE_DECLARED_PROBES` from 29 to
  30, with a PLACEMENT/TRUTH/NO SUBSTITUTE comment (Phase 2 step 4).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-8737-rotate-ghcr-minter-token/decision-challenges.md`:
  the retire-instead User-Challenge, written at plan time. No code file is created.

## Open Code-Review Overlap

None. Checked the 81 open `code-review` issues against every file to edit. No match on
`ghcr-minter-doppler-token.tf`, `token-drift-read-tokens.tf`, `web-probes-token-rotation-verify.sh`,
`preflight-discoverability-test.test.ts`, `infra-credential-tiers-8209.md` or
`cron-ghcr-token-minter`. `apply-web-platform-infra.yml` matches
#7098, but that file is read, not edited.

## Deferrals

- **Retire the token entirely (ADR-096 5.4).** It is already tracked in **#8714** (open, P2,
  milestone Phase 4). No new issue is filed. The decision challenge asks for it to be prioritized.
- **#7263 (a `-replace` dispatch arm).** Out of scope; it stays open. A rename needs no dispatch arm.

## Acceptance Criteria

### Pre-merge

- [ ] `ghcr-minter-doppler-token.tf` declares `name = "ghcr-minter-write-2026-09-25"` and
  `lifecycle { create_before_destroy = true }` inside `resource "doppler_service_token" "ghcr_minter"`.
  `access = "read/write"`, `config = "prd"` and `project = "soleur"` are unchanged.
  `doppler_secret.ghcr_minter_doppler_token` still has `value = doppler_service_token.ghcr_minter.key`
  and no `lifecycle` block.
- [ ] `grep -c -- '-replace' apps/web-platform/infra/ghcr-minter-doppler-token.tf` prints `0`. It prints
  `2` today (the header and the `doppler_secret` comment), so the check can fail.
- [ ] `grep -c 'webhook-deploy' apps/web-platform/infra/ghcr-minter-doppler-token.tf` prints `0`, and
  the `doppler_secret` comment names `ci-deploy.sh`.
- [ ] The PR's plan output shows `doppler_service_token.ghcr_minter` as `must be replaced` with
  `+/- create replacement and then destroy`. It must **not** show `will be updated in-place`, which
  would mean no rotation; if it does, stop and re-plan.
  `doppler_secret.ghcr_minter_doppler_token` shows `will be updated in-place` (`value`). If it shows
  `must be replaced`, stop and re-plan. Relative to main's latest `infra-validation.yml` plan (it is
  untargeted, uses `-refresh=false` and carries the #8754 baseline), those two are the only
  differences. `terraform validate` passes.
- [ ] Against today's Doppler state, the main verifier invocation prints `STALE` and exits 1. That is
  the positive control.
- [ ] `bun test plugins/soleur/test/preflight-discoverability-test.test.ts` passes with
  `BASELINE_DECLARED_PROBES = 30`. `bash apps/web-platform/infra/web-probes-token-rotation.test.sh`
  stays green after the header edit.
- [ ] `bash plugins/soleur/test/c4-count-parity.test.sh` and
  `bun test plugins/soleur/test/terraform-target-parity.test.ts` stay green.
  `python3 scripts/lint-infra-no-human-steps.py --changed` exits 0.
- [ ] The PR body's first line answers "does merging this alone mutate production?" with **yes**: the
  merge apply mints a new read/write token and deletes `ghcr-minter-write`, hence `[ack-destroy]`.
  The body also says the merge fires a routine web-platform release, and that the container's stale
  copy is inert.
- [ ] The PR body carries `Ref #8737`, `Ref #8734` and `Ref #8714`, never `Closes`.
  `gh pr view <N> --json closingIssuesReferences` returns `[]`. The body uses the CLO wording rule.

### Post-merge (automated reads, no SSH)

- [ ] The merge commit on `origin/main` contains `[ack-destroy]` on its own line. The run that
  performed the rotation concluded `success`. That is the push run for the merge SHA, or the
  recovery commit's run (Phase 4 step 3).
- [ ] That run's main apply, compared with the latest pre-merge push run, adds only two entries:
  `doppler_service_token.ghcr_minter` (create replacement, then destroy the deposed object) and
  `doppler_secret.ghcr_minter_doppler_token` (updated in place, with `Modifications complete`).
  Expected totals: `2 added, 2 changed, 1 destroyed`, including the recurring #8202 pair. The only
  destroyed address is the old token.
- [ ] The main verifier invocation prints `ROTATED` and exits 0.
- [ ] The orphan was revoked after its per-item re-read, and after an explicit go-ahead. Its
  pre-revoke `last_seen_at` is posted on #8737. The orphan verifier invocation prints `ROTATED` and
  exits 0.
- [ ] Just before the merge, `61c939b5`'s `last_seen_at` is posted on #8737. A value later than
  `2026-09-24T14:25:50.862Z` takes the incident branch, and the token is revoked out of band first.
- [ ] One listing read shows exactly five tokens: `web-probes-read-2026-09-24`,
  `token-drift-ci-tf-prd`, one `ghcr-minter-write-2026-09-25`, `terraform-prd-20260730` and
  `github-ci-prd`. The names-only `^dp\.` value scan of `soleur/prd` returns only
  `GHCR_MINTER_DOPPLER_TOKEN`. Each verdict's `src=` is recorded.
- [ ] The `soleur/prd` config log, read across every page until one comes back empty, is quoted on
  #8737 as the list of `apiToken`-attributed entries since 2026-07-29.
  - **If any entry names `61c939b5` or `e8e5187f`:** a report is opened with `soleur:incident`, and
    #8734 is widened with a full prd integrity sweep.
  - **In either case:** #8734 carries the go-signal, scoped to Doppler `soleur/prd` credentials,
    together with the write-limb request and the GitHub App key path it does not cover.
- [ ] #8737 is closed with the evidence comments. #8734 stays open. #8714 carries the comment that
  links UC-1, asks for 5.4 before 2026-12-23, and states the `-target` retirement trap.

## Domain Review

**Domains relevant:** Engineering, Legal, Product

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The rename + CBD approach is correct and matches #8733. The targeted plan should be
exactly one create, one update and one delete; the #8754 host replaces and the zot-secret delete stay
out of the `-target` set. Cutting the redeploy is sound, because the kill-switch check precedes the
token read. The orphan route is acceptable; the CTO advised decoupling it from the merge and revoking
it first. Folding in the token half of 5.4 is the stronger outcome, but it goes against the issue's
closing criterion and the stated direction: record it as a decision challenge and ask for #8714 to
be prioritized. Four points were folded in:

1. the stale `-replace` header guidance and the O12b runbook name;
2. #8734 is gated on both verifier runs printing `ROTATED`;
3. `[ack-destroy]` goes in via `gh pr merge --body-file`;
4. the revoke command's `--slug` flag and the revoking identity are verified.

No new ADR is needed.

### Legal (CLO)

**Status:** reviewed
**Assessment:** This PR changes no legal record. The breach register, the #8209 assessment,
`compliance-posture.md` and Art. 30 are untouched: #8734 step 4 owns the image-matter correction,
and duplicating it here would create a second source for one cell. Four points apply:

- **Evidence before revoking.** Record `last_seen_at` and the config-log write history. The write
  limb is measurable because Doppler attributes writes. The read limb is INCONCLUSIVE.
- **Comment on #8734.** Ask it to add a separate write/integrity limb.
- **Wording.** Use "closes the leaked read token's forward reach to a read/write prd credential".
  Never write "clean" or "not exposed", and never offer the disabled minter as a mitigation.
- **GDPR gate.** `soleur:gdpr-gate` is not needed: no PII field, schema, auth flow or new processing.

### Product/UX Gate

**Tier:** none (no user-facing surface; no UI file in Files to Edit or Files to Create)
**Decision:** reviewed
**Agents invoked:** soleur:product:cpo (threshold sign-off)
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

The CPO's first pass requested two changes, and both are applied:

1. The unexplained `2026-09-24T14:25:50Z` authentication of `61c939b5` is now in the User-Brand Impact
   residual and in the #8734 hand-off.
2. `decision-challenges.md` exists (UC-1), and the post-merge hand-off comments on #8714 to ask for
   5.4 to be prioritized before 2026-12-23.

The CPO re-read the plan after the plan-review revisions and confirmed that the brand framing holds.
It noted one nit, the #8714 AC wording, which is applied.

**CPO sign-off: approved** (re-review, 2026-09-25).

## Test Scenarios

- Given the merged tree, when the per-merge apply plans, then the destroy guard reports
  `resource_deletes=1` and nothing else. The merge commit's `[ack-destroy]` line clears it, and no
  HALT counter (`host_creates`, reboot, LUKS, apex, undecidable) is non-zero
  (`tests/scripts/lib/destroy-guard-filter-web-platform.jq`, `resource_deletes` counts
  `index("delete")`, so a create-before-destroy `["create","delete"]` counts once).
- Given the verifier and the listing:

  | Listing state | `--retired-slug 61c939b5` run | `--retired-slug e8e5187f` run |
  |---|---|---|
  | Today (both old tokens live) | `STALE` (1) | `STALE` (1) |
  | Orphan revoked, merge not yet applied | `STALE` (1) | `MISSING` (1) |
  | Both done | `ROTATED` (0) | `ROTATED` (0) |
  | Listing unreadable | `UNAVAILABLE` (2) | `UNAVAILABLE` (2) |

## Plan Review Revisions (2026-09-25)

The review panel had seven seats: DHH, Kieran, code-simplicity, architecture-strategist,
spec-flow-analyzer, the CTO on developer experience, and the scoped advisor consult. Everything below
is Mechanical and was applied. The only Taste/User-Challenge finding is retiring instead of
rotating (DHH P0). It is persisted as UC-1 in `decision-challenges.md`, and the plan keeps the
stated direction.

- **Fixed (Kieran P1): apply counts.** Every recent push run carries the #8202 pair
  (`cloudflare_bot_management` update, deployment-policy create). The merge run therefore reads
  `2 added, 2 changed, 1 destroyed`, and the ACs now compare against the latest pre-merge run
  instead of absolute counts.
- **Added (spec-flow P0): an incident branch.**
  - An orphan `last_seen_at` later than 2026-07-30, or any `apiToken` write by either slug, is an
    incident (`soleur:incident`). It makes the revoke urgent. The review wrote that it also withholds #8734's go-signal, but deepen-plan replaced that: an incident now widens #8734 with a prd integrity sweep instead of holding the go-signal back.
  - The write-log AC can now fail, and it requires reading every page.
- **Fixed (spec-flow P1): the lock group.** The idle check now covers all four workflows in
  `terraform-apply-web-platform-host`. Other merges are held until the apply starts.
- **Added (spec-flow P1): recovery.**
  - A "secret update failed" recovery state.
  - Post-merge ACs accept the recovery run's evidence.
  - The "no other deletes" check is repeated at recovery.
- **Added (spec-flow P1).**
  - P3 evidence: the apply's `Modifications complete` line. Doppler's config log does not name the
    secrets it changes (measured).
  - A class check: no read/write prd token from before the cut-off remains.
  - A daily re-ask, plus a 2026-10-04 note on #8734, if the revoke go-ahead does not come.
- **Fixed (architecture P1, Kieran P2).**
  - The `doppler_secret` comment named the wrong delivery route (`webhook-deploy`, which carries
    only the Doppler token) and a `-replace` rotation. Both are corrected.
  - The absence grep now covers every `-replace`. It prints 2 today, so it can fail.
  - The runbook's `:45` line cite becomes a content anchor.
- **Added (architecture P2).**
  - The stale "same bare recipe" comment in `token-drift-read-tokens.tf` is reworded.
  - A stop branch if the secret plans `must be replaced`.
  - The #8714 comment carries the `-target` retirement trap.
- **Added (CTO devex P1, Kieran P2).** The verifier's header now says the script is generic. Its
  REMOVAL note no longer ties it to image `411798619`, so #8734's cleanup cannot delete a script this
  token's `Verify:` line calls. It is not renamed.
- **Added (CTO devex).**
  - The Phase 3 evidence is posted to #8737 right after the revoke, so a later session can resume.
  - The operator message opens with the decision in plain words.
  - The runbook uses `ghcr-minter-write-*`.
- **Cut (DHH + simplicity).**
  - The ADR-119 addendum.
  - The #7263 note.
  - The pre-revoke write-log read (now one read, after both revocations).
  - The unreachable "minter re-enabled" failure mode.
  - The "minter cron fires" scenario, which cannot run while the scheduler is down.
  - Duplicate recovery prose.
  - The Terraform-state cross-check for the orphan. Instead: no committed configuration ever named
    it, and the provider cannot import it.
  - The ROTATION note is trimmed to four lines.
- **Confirmed (advisor consult):** a `name` change is ForceNew in the pinned provider source. A
  pre-merge AC requires `must be replaced` in the PR plan.
- **Kept against simplicity's suggestion:** the Encryption Posture block. Plan Phase 2.11 triggers
  on any `\.tf` in Files to Edit, and deepen-plan halts without it.
- **Deepen-plan (2026-09-25), declined with reasons:**
  - **A `postcondition { length(self.key) > 0 }` on the token** (terraform-architect). It is a
    guard-shaped control, so it would need its own Guard Contract. The failure it prevents, an empty
    `GHCR_MINTER_DOPPLER_TOKEN`, is inert while the minter is disabled, and the verifier and the apply
    log would surface it.
  - **Revoking `61c939b5` out of band as the default, not only as the containment branch**
    (security P0-1). This keeps Terraform ownership and the stated rename + CBD shape. The exposure
    difference is the PR's review window, which the 24-hour clock and the pre-merge `last_seen_at`
    trigger now bound.
  - **Refusing any `src=soleur/prd_terraform` verdict** (security P1-6). Today
    `soleur-infra-privileged/prd` does not resolve (measured: the read fell back to
    `prd_terraform`), so this would block all verification. The source is recorded and disclosed
    instead.
- **Advisory, not applied (architecture P2):** a standalone "token rotation by rename" ADR if a
  fourth token is rotated this way.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, holds only `TBD`/`TODO`/placeholder text, or
  omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or
  `soleur:work`.
- **Committing this plan moves the ratchet.** `BASELINE_DECLARED_PROBES` counts every plan (recursive,
  archive included) that declares `credentials_required`. The first work commit bumps it from 29 to
  30, before anything else lands.
- Keep the `credentials_required` value on the same line as its key. A bare `>-` block reads as
  "declares nothing".
- `[ack-destroy]` must sit on its own line in the squash message
  (`(^|\n)\[ack-destroy\]($|\n)`), and it belongs to one push.
- The verifier's `--name-prefix ghcr-minter-write-` also matches the orphan's name. That is harmless:
  the orphan was created before `--not-before`, so it can never count as the replacement. Do not
  "tighten" the prefix to the date, or a later roll-forward rename would read `MISSING`.
- The orphan's `ROTATED` verdict means "gone, and a post-cut-off replacement exists". Before the merge
  it correctly reads `MISSING`.
- Do not read `last_seen_at` of the new token as a liveness signal. It stays empty while the minter
  is disabled.
- **The pre-merge `last_seen_at` read of `61c939b5` is the last chance.** After the apply deletes the
  token, its authentication history is gone for good.
- **Do not probe a token to identify it.** Calling `/v3/me` with a stored token value to learn its
  slug updates that token's `last_seen_at`, which destroys the evidence Phase 3 relies on.
