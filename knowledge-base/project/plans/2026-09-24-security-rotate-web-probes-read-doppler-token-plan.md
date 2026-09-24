---
title: "security: rotate the web-probes-read prd Doppler token, very likely held in retained web-1 snapshot 411798619"
date: 2026-09-24
slug: security-rotate-web-probes-read-doppler-token
branch: feat-one-shot-8705-rotate-web-probes-read-token
issue: 8705
closes: 8705  # closed by a post-merge step after the Doppler read proves rotation; the PR body carries Ref #8705, never Closes
type: fix
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# security: rotate the web-probes-read prd Doppler token held in retained web-1 snapshot 411798619

## Overview

`doppler_service_token.web_probes` (Doppler name `web-probes-read`, config `soleur/prd`, access
`read`) can read the whole `prd` config, including `SUPABASE_SERVICE_ROLE_KEY`. It was created on
2026-07-18 and written to web-1's disk the same day. On 2026-07-23 a snapshot of web-1's root disk
was taken, and that image (`411798619`) still exists. So anyone holding the image very likely holds a
live token that can read production secrets today.

This plan rotates the token with the same shape PR #8703 used for `doppler_service_token.workspaces_luks`:
a `name` change (ForceNew in the pinned provider) with `lifecycle { create_before_destroy = true }`,
merged with `[ack-destroy]`. The main apply mints the new token and deletes the old one. The SSH stage
of the same run then re-fires the four web-1 installers, whose `triggers_replace` already hash the key.
web-2 has no SSH delivery path; it gets the new token by an immutable `web-host-replace` of web-2 right
after the merge. The plan also records the sweep of every other Doppler service token, with evidence
for each.

**What this closes and what it does not.** Rotating the token closes *forward* read access: after the
merge, the copy in the image can no longer read anything. The image very likely also holds prd secret
**values** as of 2026-07-23, and no token rotation can revoke those. That is tracked in **#8734**,
filed during this planning session.

Details are in Research Insights.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Checked with | Result |
|---|---|---|
| #8705 is open and unresolved | `gh issue view 8705` | OPEN, no closing PR |
| #8703 (luks token rotation) merged with the rename + CBD shape | `gh pr view 8703` | MERGED 2026-09-24T11:13:57Z; `workspaces-luks.tf` on this branch carries `name = "workspaces-luks-boot-2026-09-24"` + `create_before_destroy = true` |
| `web-probes-read` created before the image and still live | Doppler API `GET /v3/configs/config/tokens?project=soleur&config=prd` (read-only, `DOPPLER_TOKEN_TF`) | `web-probes-read`, slug `01941a89…`, created `2026-07-18T11:33:56.040Z`, still listed |
| Image `411798619` is web-1's and still exists | Hetzner `GET /v1/images/411798619` | `inngest-cutover-pre-20260723T153403Z`, created `2026-07-23T15:34:04Z`, `created_from: soleur-web-platform (123931471)`, `status: available`, `protection.delete: false`. It is the **only** snapshot left in the project, and there are no backup images |
| The token reached web-1 before the image | Apply run `29642722055` (push of `1de27ebbc1`, 2026-07-18) log | `doppler_service_token.web_probes: Creation complete … 11:33:56Z`, then over the SSH bridge `private_nic_guard_install`, `zot_consumer_probe_install`, `git_data_probe_install: Creation complete … 11:34:39Z`. So the three `/etc/default/web-*` files held the token 5 days before the image. **Settles Task 1 of the issue: confirmed, not just likely.** |
| "three web-1 installers" | `grep -n 'web_probes.key' apps/web-platform/infra/server.tf` | **Stale: there are four.** `inngest_consumer_probe_install` (#7228) was added later and also writes the token, to `/etc/default/inngest-consumer-probe`. All four hash the key in `triggers_replace` |
| "web-2, 2026-07-27" | Hetzner `GET /v1/servers` | **Stale.** web-2 (`167222136`, cpx22) was re-created **today, 2026-09-24T07:14:25Z**, by the `web-host-replace` dispatch run `35951886838`. Its user_data carries the *current* `web-probes-read` key, so a rotation leaves web-2 holding a dead copy |

### Property List (Phase 0.6b)

- **P1.** After the merge, Doppler has no live service token that was created before
  2026-07-23T15:34Z and was ever written to web-1. Concretely: `web-probes-read` no longer exists,
  and its replacement's `created_at` is later than the image.
- **P2.** web-1's four probe units keep authenticating across the rotation: every host copy of the
  token is re-delivered in the same apply that deletes the old one.
- **P3.** web-2's probe units authenticate with the new token (it has no in-place delivery path).
- **P4.** The next rotation of this token is just as safe. The shape (rename, create-before-destroy,
  and one hash trigger per SSH consumer) is pinned by a test, not remembered.
- **P5.** The sweep is recorded: every other Doppler service token is classified by the issue's
  test (created before the image AND written to web-1), with the evidence for each.

### Cut List (Phase 0.6b)

- **A new web-2 re-seed channel** (an SSH provisioner or refresh job aimed at web-2) → buys P3 →
  already covered by the existing `web-host-replace` dispatch (ADR-148, `runbooks/web-host-replace.md`),
  and `hr-prod-host-config-change-immutable-redeploy` forbids in-place edits on a replaceable host.
  Cut.
- **A #8703-style prove-then-write helper script** → would buy "never write a token that cannot
  read" → the new token is minted by the Doppler provider in the same apply, so it is valid by
  construction. Each `/etc/default/web-*` file is written whole by exactly one installer (`printf >`),
  so there is no shared line to preserve and no missing-file case (the #8724 trap). The probes'
  own heartbeats prove authentication on the host within 60 s (see Observability). Cut.
- **A second resource plus a two-PR add-then-remove rotation (the `moved` → `web_probes_leaked`
  variant the advisor consult proposed)** → would buy "no dead-token window on either host" → costs a
  second merge and the same web-2 dispatch, and it keeps the leaked token **live** until PR 2 merges.
  The CTO ruled against it (Domain Review). Cut (see Alternatives).
- **Deleting image `411798619`** → would buy P1's underlying goal outright → owned by ADR-100's
  2026-09-23 addendum (the soak verbs release it at SOAK CLEAN or by 2026-10-06). It is the #6178
  rollback substrate, so it stays out of scope here.

### Mechanism already on main (not re-built)

- `triggers_replace` hashes `nonsensitive(sha256(doppler_service_token.web_probes.key))` in all four
  web-1 installers (`server.tf`, anchors `resource "terraform_data" "private_nic_guard_install"`,
  `"zot_consumer_probe_install"`, `"inngest_consumer_probe_install"`, `"git_data_probe_install"`).
- The per-merge main apply `-target`s `doppler_service_token.web_probes`
  (`apply-web-platform-infra.yml`, the default allow-list), and the post-bridge SSH stage `-target`s
  all four installers (`Terraform apply (SSH-provisioned resources, over the bridge)`).
  `plugins/soleur/test/terraform-target-parity.test.ts` Guard 1 already enforces that SSH-provisioned
  resources live in the post-bridge stage.
- The destroy guard counts the token replace as one `resource_deletes`, so it demands `[ack-destroy]`
  and nothing else (no host_creates, reboot, LUKS or apex HALT is reachable by a
  `doppler_service_token` replace).

### Measured facts that shape the plan

- **The dead-token window on web-1 is about 35 s.** In run `36005279546` (#8724, the same two-stage
  job), the main apply finished at `13:40:51Z` and the SSH-stage installer finished at `13:41:25Z`.
  The probe timers fire every 60 s (zot, git-data, inngest-consumer) or every 5 min (nic-guard).
  Better Stack allows `period+grace` of 240 s (zot, inngest-consumer) and 480 s (nic-guard) before
  alerting. At most one probe fire fails, and no heartbeat misses.
- **A revoked token fails hard. The CLI does not fall back to its cache.** DopplerHQ/cli
  `pkg/controllers/secrets.go` `FetchSecrets`: `canUseFallback := statusCode != 401 && statusCode != 403 && statusCode != 404`.
  On 401/403 it *deletes* that token's fallback file. So web-2's probes will stop pinging, and its two
  per-host beats (`soleur-web-nic-guard-web-2`, `soleur-web-zot-consumer-web-2`, both live, `paused=false`,
  email alerting) will go down until web-2 is replaced. That is loud, which is correct.
- **Each fallback file is named by a hash that includes the token.** DopplerHQ/cli `pkg/cmd/run.go`
  `initFallbackDir` builds the name as `.secrets-<GenerateFallbackFileHash(token, project, config, …)>.json`.
  So the new token writes a **new** file on web-1, and the old-token file stays under `/root/.doppler`.
  It is deleted only if a probe fires with the old token inside the ~35 s window and gets a 401. The
  leftover file holds prd values encrypted under a passphrase derived from the old token. That adds
  nothing an attacker with root on web-1 could not already read with the new token, so this PR does
  not add host-side cleanup. The image's own copy belongs to #8734.
- **The web-host-replace gate refuses a premature dispatch.** web-2's replace plan pulls in
  `doppler_service_token.web_probes`, because the server's user_data template reads its key. The gate
  refuses any out-of-scope change, so a dispatch *after* the merge but *before* the main apply
  converges is refused on its own (CTO, checked against `tests/scripts/lib/vector-redeliver-gate.sh`,
  which lists the same thing for its target). A dispatch *before* the merge is not caught: it would
  bake the old token into a new web-2. Sharp Edges covers that case.
- **Shared beats are unaffected by web-2.** `GIT_DATA_HEARTBEAT_URL` and `INNGEST_CONSUMER_URL` are
  single shared beats (`web-probe-envwrite.sh` comments), and web-1 keeps feeding them.
- **The per-merge plan cannot touch web-2's host.** `hcloud_server.web` carries
  `ignore_changes = [user_data, ssh_keys, image, placement_group_id]`, so the re-rendered
  `web_probes_token` in the templatefile produces no diff.

### Sweep (Task 3): every Doppler service token, by the issue's test

Live inventory pulled from the Doppler API across all 6 projects and every config (read-only).
"Written to web-1" was traced from every write path on the host: the SSH `terraform_data`
provisioners, web-1's first-boot user_data (2026-03-17), `soleur-doppler-token.tmpl`, the
`workspaces-cutover.sh` write, and inngest's copy of `/etc/default/webhook-deploy`.

| Token (project/config) | Created | Before image? | Written to web-1? | Verdict |
|---|---|---|---|---|
| `web-probes-read` (soleur/prd) | 2026-07-18 | yes | **yes**: 4 installers, run 29642722055 | **ROTATE (this PR)** |
| `workspaces-luks-boot` (prd_workspaces_luks) | 2026-07-18 | yes | yes | already rotated by #8703 (`…-2026-09-24`, created 09-24T11:35Z); the old token is gone from the API listing |
| web-1 first-boot `var.doppler_token` (webhook-deploy) | ≤2026-03-17 | yes | yes | already revoked 2026-07-30 (`server.tf` `local.webhook_doppler_token_env` rationale); today's `DOPPLER_TOKEN` in prd_terraform is `terraform-prd-20260730` (confirmed via `/v3/me`), created after the image |
| `github-ci-prd` (soleur/prd) | 2026-03-29 | yes | no: GitHub secret `DOPPLER_TOKEN_PRD`, used only runner-side (release migrations, verify, secret-presence assert, registry preflight); never forwarded to a host | out of scope |
| `web-arm-read` (prd_terraform) | 2026-07-18 | yes | no: `github_actions_secret.doppler_token_web_arm`, runner-side arm gate only | out of scope |
| `ci-tf-write`, `github-actions-ci` ×2 (prd_terraform) | 03-21 / 05-20 | yes | no: CI-only | out of scope |
| `cloud-scheduled-tasks` (prd_scheduled), `ci-cla-evidence-workflow` (prd_cla), `kb-drift-ci-tf` / `kb-drift-tf-prd` (prd_kb_drift_walker), `dev_scheduled_ci` (dev_scheduled) | 03-24 … 05-20 | yes | no: CI-only | out of scope |
| `zot-registry-boot` (soleur-registry/prd) | 2026-07-07 | yes | no: registry host only, and no registry image exists | out of scope |
| `inngest-boot`, `inngest-cutover-arm`, `git-data-luks-boot`, `git-data-root-read`, `token-drift-ci-tf-*`, `terraform-prd-20260730`, `ghcr-minter-write*` | ≥2026-07-24 | **no** | n/a | out of scope |

**Residual stated plainly.** A Doppler token that someone put on web-1 by hand (for example a
`doppler login` in an SSH session) would not appear in any repo write path. The API cannot attribute
a token to a host, so this sweep cannot rule it out. Nothing points to one.

**A pre-existing finding outside the token class. It goes to a follow-up issue and is not folded in
here.** Token rotation closes only *forward* read access. The image very likely also holds prd secret
**values** as of 2026-07-23:

- the app container's `Config.Env`: `ci-deploy.sh` `resolve_env_file` → `docker run --env-file`, and
  Docker persists that environment under the default `/var/lib/docker/containers/<id>/config.v2.json`
  (no `data-root` override is present in `apps/web-platform/infra`);
- the probes' encrypted Doppler fallback file under `/root/.doppler`, whose default passphrase derives
  from the token the same image holds;
- the create-time user_data secrets.

This contradicts #8632's "service-role and BYOK exposure through the images is closed". The complete
remedy is to delete the image (already scheduled by ADR-100 at SOAK CLEAN or 2026-10-06) or to rotate
the values themselves. It is filed as **#8734** (P1, `type/security`, `domain/legal`). That issue
carries the CLO's evidence-before-deletion, record-correction and value-rotation steps.

### Relevant learnings

- `knowledge-base/project/learnings/2026-09-24-the-verify-rows-i-called-host-health-were-the-verifiers-own.md`:
  the #8703 rotation. It is the source of the rename + CBD + token-hash-trigger shape, and it is where
  the `web-probes-read` finding came from.
- #8724 (`6f5b97523b`): #8703's first merge apply went red in the SSH stage because the target
  EnvironmentFile was absent. The lesson is that the SSH stage runs *after* the old token is deleted,
  so an SSH-stage failure leaves the host holding a dead token. That does not apply here: each
  `/etc/default/web-*` file is created whole by `printf >`, not edited in place.
- `2026-04-06-terraform-data-connection-block-no-auto-replace.md`: only `triggers_replace` re-fires a
  `terraform_data`. That is why Guard 1 pins the hash in every consumer.
- `2026-05-04-snapshot-leak-floor-must-precede-snapshot-infra.md`: a credential baked into a snapshot
  is unrecoverable from the snapshot's side. You rotate the credential or delete the image.

### Related

#8632 / PR #8703 (luks token rotation), #8724 (the EnvironmentFile follow-up), #6178 (the image is
its rollback substrate), ADR-100 2026-09-23 addendum (image release verbs), ADR-119 2026-09-24
addendum (the rotation shape), ADR-148 + `runbooks/web-host-replace.md` (web-2 replace route),
#6669 / `1de27ebbc1` (the token's origin).

### CLAUDE.md / AGENTS conventions applied

`hr-prod-host-config-change-immutable-redeploy` (web-2 is replaced, not edited),
`hr-menu-option-ack-not-prod-write-auth` (the post-merge web-2 dispatch needs a per-command
go-ahead), `hr-no-ssh-fallback-in-runbooks` (every verification is an API read),
`hr-no-dashboard-eyeball-pull-data-yourself` (all premises above were pulled live),
`wg-when-an-audit-identifies-pre-existing` (the snapshot-values finding is filed).

## Research Reconciliation — Issue vs. Codebase

The factual corrections (four installers, not three; web-2 re-created today; Task 1 confirmed) are in
the Premise Validation table above, and each is answered in Proposed Solution. This table keeps only
the rows that change the design:

| Issue claim | Reality | Plan response |
|---|---|---|
| "check what web-2's probe units read" | `web-probe-envwrite.sh` writes the same four `/etc/default/*` files from `SOLEUR_WEB_PROBES_TOKEN` at first boot; no later writer exists | re-seed web-2 by `web-host-replace` after the merge apply is green |
| "the merge needs `[ack-destroy]`" | the ack is read only from the push's `head_commit`; a superseded run loses it, and `manual-rerun` cannot carry it | Phase 3 idle-group precheck, a check by `head_sha`, and a recovery commit |
| Existing `web-probe-read-token.tf` rotation guidance: `terraform apply -replace=doppler_service_token.web_probes` | a same-name `-replace` without CBD deletes first, so a failed create leaves no token; with CBD it needs Doppler to accept two tokens with one name (unprobed, per the `workspaces-luks.tf` note) | replace the guidance with the rename + CBD shape |

## Proposed Solution

One PR, one merge with `[ack-destroy]`, then one reviewer-gated dispatch. **Merging this PR by itself
changes production.** The push-triggered apply mints the new token, deletes `web-probes-read`, and
rewrites four files on web-1. The merge click is the per-command authorization for that change.

### Phase 1: Rotation shape (`apps/web-platform/infra/web-probe-read-token.tf`)

1. Change `name = "web-probes-read"` to `name = "web-probes-read-2026-09-24"`. The name is only a
   label. What gets revoked is the old token's **key**, identified by its slug `01941a89…`.
2. Add `lifecycle { create_before_destroy = true }`.
3. Replace the `State storage:` rotation paragraph with about 8 lines. Point to
   `workspaces-luks.tf`'s ROTATION comment for the shared mechanics, and state only what differs here:
   - Rotation is a `name` change, which is ForceNew in DopplerHQ/doppler v1.21.2, merged with
     `[ack-destroy]`.
   - `create_before_destroy` gives **token-level** failure atomicity only. The main apply finishes the
     replace, delete included, before the SSH stage re-fires the **four** installers. So web-1 holds a
     dead token for about 35 s, and for longer if the SSH stage fails. Do not word the comment as
     though CBD closes that gap.
   - Fresh hosts born before a rotation keep a dead copy (`hcloud_server.web`
     `ignore_changes = [user_data]`). Re-seed each one with `web-host-replace` once the merge apply is
     green.
   - A same-name replace is not used: without CBD it deletes first, and with CBD it depends on Doppler
     accepting two same-named tokens, which has not been probed. Word this without the literal
     `apply -replace=` so the pre-merge absence check stays meaningful.
   - `Rotated 2026-09-24 from web-probes-read (created 2026-07-18; retained web-1 snapshot 411798619 holds it, #8705).`
4. Leave `access`, `config` and `project` unchanged. The existing assertions in
   `web-zot-consumer-probe.test.sh` (`access = "read"`, `config = "prd"`) must stay green.
5. **Required:** reword the four `server.tf` installer comments that say "a `-replace` rotation"
   (the ones beside each `nonsensitive(sha256(doppler_service_token.web_probes.key))` trigger). They
   become "a rotation (rename, create_before_destroy)". This is comment-only and changes no
   `triggers_replace` input: those hash `file()` sources and literals, not `server.tf`'s own text.
6. Add a 2026-09-24 **ADR-119 addendum paragraph** under the existing "luks-monitor token line"
   addendum. It records that `doppler_service_token.web_probes` is the second token rotated with this
   shape, that a same-name `-replace` is not preferred, and that web-1's four `/etc/default/*` rewrites
   rely on ADR-154's standing exception to `hr-prod-host-config-change-immutable-redeploy`. Also add
   "re-seed a rotated baked credential" to the documented uses of
   `knowledge-base/engineering/operations/runbooks/web-host-replace.md`.

### Phase 2: Guard suite (new `apps/web-platform/infra/web-probes-token-rotation.test.sh`)

Write the Guard Contract matrix first, then the suite.

- **One bash file.** It embeds a `python3` checker and a mutation battery that runs in its default
  invocation, so the one registered CI step executes it (the #7942 class is a battery that runs in no
  gate). Model the `ok`/`no` counters and the `MIN_ASSERTIONS` floor on
  `workspaces-luks-host-token-refresh.test.sh`. Model the mutations on the "Guard 1 mutation battery"
  in `plugins/soleur/test/terraform-target-parity.test.ts`: apply each edit to a temporary copy and
  **assert the copy actually changed** before grading it, so a mutation that no longer applies reports
  `mutation did not apply` instead of a false RED or GREEN.
- **Lexing.** Load `tokenize()` from `scripts/lint-doppler-description-length.py` with
  `importlib.util.spec_from_file_location`; the filename is hyphenated, so a plain import is a parse
  error. Add a one-line change to that lint so its `HEREDOC` token carries the heredoc **body** in its
  value slot. The lint's `scan()` never reads that slot (Kieran verified this); rerun the lint to
  confirm it stays green. Treat a `ScanError` as RED, never as a skip.
- **Reference matcher.** It matches `doppler_service_token.web_probes` in three places: `ID . ID`
  token sequences, `STR` tokens whose `has_template` is true (the installers' `printf` references live
  there), and `HEREDOC` bodies.
- **Floors** are counted at the call site, never through `fail`, per `scripts/guard-vacuity-floor.test.sh`.
  If that suite's derived population picks this file up, promote it through `PROMOTED_FILES`. Never
  raise the ratchet.
- **Suite header note:** the installer floor (4) encodes today's probe count. Retiring a probe on
  purpose means editing the floor on purpose.
- **Registration:** add the suite to `.github/workflows/infra-validation.yml` next to the web-probe
  suites (anchor: `run: bash apps/web-platform/infra/web-git-data-probe.test.sh`).

### Phase 2b: Rotation verifier (new `apps/web-platform/infra/scripts/web-probes-token-rotation-verify.sh`)

This one read-only probe is the post-merge check and also the `discoverability_test.command`. An
inline `curl … | jq` cannot fill that role, because preflight Check 10 rejects `|` and `$` in the
command. The verifier is parameterized, and its defaults are this rotation's values:

- `--config prd`
- `--retired-slug 01941a89`
- `--name-prefix web-probes-read-`
- `--not-before 2026-07-23T15:34:04Z`

The next rotation, of this token or a sibling, then needs new arguments, not a new script.

- **Read.** `GET /v3/configs/config/tokens?project=soleur&config=<config>`, authorized with
  `DOPPLER_TOKEN_TF`. The token comes from the environment, or else from
  `doppler secrets get DOPPLER_TOKEN_TF --plain -p soleur -c prd_terraform`. No xtrace. It never prints
  a key; the list endpoint returns none.
- **Verdicts.** Each exit goes through one verdict function:

  | Verdict | Exit | Condition |
  |---|---|---|
  | `ROTATED` | 0 | Green only on positive evidence. The body is a non-empty `tokens` array, no token's slug starts with the retired slug, and at least one token whose name starts with the prefix has `created_at` later than `--not-before`. |
  | `STALE` | 1 | The retired slug is still listed. This is the identity check. The name is only a label (simplicity finding). |
  | `MISSING` | 1 | The retired slug is absent, but no replacement created after `--not-before` exists. |
  | `UNAVAILABLE` | 2 | Empty body, non-array body, unparseable body, or HTTP failure. |

  It never falls through to green (sharp edge #8500).
- **Fixture seam.** `WEB_PROBES_TOKEN_LIST_JSON=<file>`, driven by the Phase 2 suite. Fixtures use
  synthesized slugs and names only.
- **Removal note** in the header: the verifier is only meaningful until image `411798619` is gone
  (#8734). The ratchet entry stays, because it counts the plan's declaration.
- **Ratchet.** This plan's single-line `credentials_required` declaration moves the repo-global
  `BASELINE_DECLARED_PROBES` from 24 to 25 in `plugins/soleur/test/preflight-discoverability-test.test.ts`.
  Record it with a PLACEMENT/TRUTH/NO SUBSTITUTE comment in this same PR. The value must be on one line
  after the key: `parseCredentialsRequired()` reads a bare `>-` as declaring nothing (Kieran P0).

### Phase 3: Merge and verify (ship / postmerge; all reads automated, no SSH)

The `[ack-destroy]` token is read only from `github.event.head_commit.message`. It belongs to one
push, and a `manual-rerun` dispatch has no head commit, so a dispatch can never carry it. So the merge
itself is the fragile step:

1. **Before merging:**
   - **Check that the concurrency group is idle.** `gh run list --workflow apply-web-platform-infra.yml`
     and `--workflow apply-deploy-pipeline-fix.yml` must show nothing `queued`, `in_progress` or
     `waiting`, because a newer queued run cancels a pending one.
   - **Check the main stage deletes nothing else.** Read the plan summary of the latest `main` push
     run's main `Terraform apply` step and confirm it deleted nothing in the targeted set.
     `[ack-destroy]` acks every delete in the plan, not only this one.
2. **Squash message.** Write it with `gh pr merge --squash --body-file <file>`. The file carries
   `Ref #8705`, `Ref #8734`, and `[ack-destroy]` on its own line, outside any fence or trailer.
   Afterwards, check that `git log -1 --format=%B origin/main` contains the line.
3. **Find the run by `head_sha`** and watch it with Monitor (`hr-dispatch-async-must-arm-watch`).
   Its main apply must show `1 added, 0 changed, 1 destroyed`, with only `doppler_service_token.web_probes`
   in it. Its SSH stage must show `Creation complete` for all four installers.
4. **Failure branches:**
   - **The run was cancelled or superseded, or the delete left a deposed object.** Every later push
     run would HALT with no ack. Recover with a follow-up commit to `main` (a comment-only touch of
     `web-probe-read-token.tf`) whose message carries `[ack-destroy]` on its own line. Never re-run an
     older run after `main` has moved; it would apply an old tree.
   - **The SSH stage failed or was skipped.** Fix the cause, then dispatch
     `gh workflow run apply-web-platform-infra.yml -f apply_target=manual-rerun -f reason='deliver #8705 web_probes token to web-1'`.
     The token is already settled, so no ack is needed. That dispatch runs the same apply job,
     including the bridge and SSH stage, as the #7539 notify email's recovery states.
5. **Post a checklist comment on #8705** at merge time, listing the remaining steps below, so a later
   session can resume if this one ends.

### Phase 4: Re-seed web-2 (reviewer-gated dispatch, after the Phase 3 web-1 reads are green)

1. **Send one plain message to the operator.** In plain words: why web-2 needs a fresh start (it
   still holds the old key), that "web-2 down" emails for about 15 minutes are expected, the exact
   command below, and that GitHub will then ask them to approve it.
2. **After the go-ahead** (`hr-menu-option-ack-not-prod-write-auth`), rehearse the dispatch first by
   running the command below with `-f plan_only=true` added. It runs the job's gate with no apply,
   `-replace` or host contact. This is the first web-host-replace with a create-before-destroy token
   among the server's dependencies, so the rehearsal checks that no deposed object makes the gate
   refuse. Then run the real dispatch:

   ```bash
   gh workflow run apply-web-platform-infra.yml \
     -f apply_target=web-host-replace \
     -f web_host_key=web-2 \
     -f confirm=REPLACE-web-2 \
     -f reason='re-seed web-2 with the rotated web_probes token (#8705)'
   ```

   <!-- verified: 2026-09-24 source: knowledge-base/engineering/operations/runbooks/web-host-replace.md (dispatch block); plan_only input: apply-web-platform-infra.yml workflow_dispatch inputs -->

   The job's stock preflight fails closed if cpx22 cannot be ordered, and it destroys nothing in that
   case. The same route re-created web-2 at 07:14Z today (run `35951886838`).
3. **Resolve the run by id and watch it with Monitor.** A merge landing while the run waits for
   approval can drop it, so require the `web_host_replace` job to conclude `success`, and dispatch
   again if the run was dropped. Afterwards, list any push runs `cancelled` while the approval was
   pending, and dispatch `manual-rerun` if any exist. A pending approval holds the group.
4. **If cpx22 cannot be ordered:** web-2 keeps a dead token and its two beats stay down. Keep #8705
   open with a comment, re-dispatch every 6 h until the preflight passes, and do not pause the
   beats.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| `terraform apply -replace=doppler_service_token.web_probes` (the file's current guidance) | Without CBD it deletes first, so a failed create leaves no token. With CBD and the same name it depends on Doppler accepting two same-named tokens, which is unprobed (`workspaces-luks.tf`). The rename sidesteps both, and it matches #8703 and ADR-119's 2026-09-24 addendum |
| Two-PR add-then-remove. The advisor's version: `moved { from = doppler_service_token.web_probes to = doppler_service_token.web_probes_leaked }` plus a new `web_probes`, and PR 2 deletes `web_probes_leaked` | It removes both dead-token windows and the SSH-stage-failure mode, and PR 1 needs no `[ack-destroy]`. But the leaked token stays **live** until PR 2 merges, which is the opposite of what the issue is for. It costs a second merge, a second `[ack-destroy]`, two rounds of `-target`/parity edits (the parity test forces every `doppler_service_token` to be targeted), and the same web-2 dispatch. It also rests on an untested interaction between `moved` and `-target` (fail-closed: if the move were ignored, the destroy guard would HALT without an ack). **The CTO ruled single-PR** (Domain Review): web-2 is a weight-0 standby with email-only alerts, the shared beats stay fed by web-1, and the measured web-1 window misses no heartbeat |
| Delete image `411798619` instead | It is the #6178 rollback substrate until SOAK CLEAN or 2026-10-06 (ADR-100 addendum). Deleting it would close the value exposure too, but that is ADR-100's verb, tracked there |
| A web-2 SSH provisioner or refresh job | No SSH path reaches web-2 (the CF-tunnel bridge fronts web-1 only), and `hr-prod-host-config-change-immutable-redeploy` requires re-provisioning |
| Pausing web-2's beats during the window | A Better Stack write that hides a real fault. The window is short and the alerts are email-only |

## Technical Considerations

- **Attack surface enumeration (security fix).** Every host-side copy of the token:
  1. web-1 `/etc/default/{web-private-nic-guard,web-zot-consumer-probe,inngest-consumer-probe,web-git-data-probe}`:
     rewritten by the 4 installers in the merge apply.
  2. web-1's probe fallback files under `/root/.doppler/`: the old-token file is **not** replaced.
     File names are token-hashed, so the new token writes a sibling file. The old one is deleted only
     if a probe gets a 401 in the ~35 s window. It is left in place deliberately (see Research
     Insights); the image's own copy is #8734.
  3. web-2's same four files and its fallback file: dead after rotation. Removed by the web-2
     replace (the new disk).
  4. web-2's Hetzner user_data (create-time, server metadata): replaced with the server.
  5. Terraform state (R2, encrypted backend): holds the new key, the same as every other
     `doppler_service_token.*.key`.
  6. Image `411798619`: holds the old key, which is dead after the merge. That is the point of this PR.
  7. No `github_actions_secret`, workflow, vector-redeliver or infra-config push consumes this key.
     `cloud-init.yml` is the only template that reads `web_probes_token` (architecture review); the
     inngest, registry and git-data templates do not. Guard 1 fails on any reference outside the
     allowed blocks, so a future consumer is noticed.
- **Blast radius of a failed SSH stage.** The old token is already gone, so web-1's probes fail
  authentication and their beats page within 4–8 min. The run is red (or the #7539 notify-ops email
  fires if the stage was skipped). Recovery is the documented
  `gh workflow run apply-web-platform-infra.yml -f apply_target=manual-rerun`. There is no user
  impact: the probes are monitoring only.
- **Timing.** No scheduled-workflow conflict is known for this token. Unlike #8703 there is no daily
  verify that reads it.
- **NFR.** None affected. It is a credential swap on existing monitoring units.

## Hypotheses (SSH-stage reachability, per plan Phase 1.4 — the rotation re-fires `remote-exec` resources)

- **L3 firewall.** CI does not use public port 22. The SSH stage rides the CF Tunnel SSH bridge
  (`.github/actions/cf-tunnel-ssh-bridge`), so the runner's egress IP is not in the path. web-1's
  firewall (`soleur-web-platform`) shows its tcp/22 rules each carry a 1-source allowlist (Hetzner
  `GET /v1/firewalls`, 2026-09-24) for the operator's direct path, which does not matter here.
  Verified by the most recent end-to-end evidence: the SSH stage of run `36005279546` completed at
  2026-09-24T13:41:25Z.
- **L3 DNS/routing, L7.** Covered by the same green bridge run. Pre-merge check: the latest `main`
  apply's `Terraform apply (SSH-provisioned resources, over the bridge)` step is green, and
  `CI_SSH_ACCESS_TOKEN_ID` is present in `prd_terraform` (the ssh_token_gate input).
- No sshd or fail2ban hypothesis is in play.

## Architecture Decision (ADR/C4)

This plan makes no new architectural decision. It extends one recorded decision, so the record is
updated in this PR.

### ADR

- **Amend ADR-119** (the 2026-09-24 addendum's "Rotation is a rename or `-replace`" paragraph). Add a
  dated paragraph with three points:
  - `doppler_service_token.web_probes` is the second token rotated with the rename +
    create-before-destroy shape;
  - a same-name `-replace` is not preferred, because nobody has probed whether Doppler accepts two
    tokens with one name;
  - web-1's four `/etc/default/*` rewrites rely on **ADR-154**'s standing exception to
    `hr-prod-host-config-change-immutable-redeploy`. web-1 is `cx33`, which cannot be replaced; its
    probe files are rewritten over SSH by token-hash-triggered installers.
- Also record the **ADR-148** web-host-replace route's new documented use, re-seeding a rotated baked
  credential, in `runbooks/web-host-replace.md`.

### C4 views

No C4 change. The existing model already covers every element this touches:

| Kind | Element |
|---|---|
| Actors | operator |
| External systems | Doppler, Hetzner API, Better Stack |
| Containers | web-1 and web-2 hosts |
| Access relationships | web host → Doppler (read), CI runner → web-1 (SSH over the CF tunnel) |

The change swaps one credential on an existing edge. It adds no element, no edge and no count. During
the work phase, read all three files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`)
to confirm those elements are there, then run `plugins/soleur/test/c4-count-parity.test.sh`. It must
stay green.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. The probe units are internal
  monitoring (private-NIC guard, zot, git-data and inngest reachability). A broken rotation shows up
  as paging heartbeats and blind monitoring on web-1 until a re-run. If the rotation silently failed
  to happen, the user-facing risk stays open: a live full-prd read token in a retained image.
- **If this leaks, the user's data is exposed via:** the old token reads the entire `soleur/prd`
  Doppler config, including `SUPABASE_SERVICE_ROLE_KEY` (which bypasses RLS on every user's rows) and
  the BYOK encryption material. Anyone holding image `411798619` holds a token that can read the
  *current* values until this merges.
- **Residual (not closed by this PR):** the service-role key *value*, and the other prd values as of
  2026-07-23, very likely persist in image `411798619` (Docker container env, Doppler fallback
  files). Rotating a token cannot revoke a copied value. This is tracked in **#8734**: delete the image
  by 2026-10-06 at the latest, or rotate the values. The PR text must say "forward read access
  closed; value exposure tracked in #8734", never "exposure closed" (CLO wording rule).
- **Brand-survival threshold:** `single-user incident`. A service-role read of one user's data from a
  leaked image is brand-ending even once. So CPO sign-off applies at plan time, and
  `soleur:engineering:review:user-impact-reviewer` runs at review.

## Observability

```yaml
liveness_signal:
  what: >-
    Better Stack heartbeats fed by the four probe units, each of which beats ONLY after `doppler run`
    authenticates with the delivered token — soleur-web-nic-guard-web-1, soleur-web-zot-consumer-web-1,
    soleur-web-nic-guard-web-2, soleur-web-zot-consumer-web-2, soleur-inngest-consumer-prd, and the
    git-data heartbeat. A beat after the merge is in-surface proof the new token authenticates on that host.
  cadence: "60s probe timers (nic-guard 5 min); beats period 180s/360s, grace 60s/120s"
  alert_target: "operator email (Better Stack heartbeat alerting, email=true)"
  configured_in: "apps/web-platform/infra/web-probe.tf (betteruptime_heartbeat.web_zot_consumer / .web_nic_guard, for_each var.web_hosts)"
error_reporting:
  destination: "Better Stack Logs Source 4 (web-host journald via Vector) for probe FATAL lines; GitHub Actions run conclusion for the apply"
  fail_loud: "apply run red at `Terraform apply (SSH-provisioned resources, over the bridge)`; or the #7539 notify-ops email `SSH stage SKIPPED`; heartbeats flip to down"
failure_modes:
  - mode: "SSH stage fails or is skipped after the main apply deleted the old token (web-1 probes hold a dead token)"
    detection: "apply run conclusion != success at the SSH step, or ssh_apply_skip=true notify-ops email; web-1 heartbeats down within period+grace"
    alert_route: "GitHub failure notification + Better Stack email; recovery `gh workflow run apply-web-platform-infra.yml -f apply_target=manual-rerun`"
  - mode: "web-2 not re-seeded (dispatch not run or failed)"
    detection: "soleur-web-nic-guard-web-2 / soleur-web-zot-consumer-web-2 heartbeats down"
    alert_route: "Better Stack email"
  - mode: "new token create fails in the main apply"
    detection: "main `Terraform apply` step red; create_before_destroy means the old token was NOT deleted, so no host loses auth"
    alert_route: "GitHub failure notification"
  - mode: "rotation silently skipped (e.g. merged with [skip-web-platform-apply])"
    detection: "web-probes-token-rotation-verify.sh prints STALE (exit 1); the post-merge AC read fails"
    alert_route: "ship/postmerge verification step (blocks closing #8705)"
  - mode: "web-2 replace dispatch silently dropped by the workflow concurrency group"
    detection: "no workflow_dispatch run with a web_host_replace job conclusion=success after the dispatch; web-2 beats stay down"
    alert_route: "postmerge verification step re-dispatches; Better Stack email meanwhile"
logs:
  where: "GitHub Actions run logs (apply-web-platform-infra.yml); Better Stack Logs Source 4 for host-side probe lines"
  retention: "GitHub Actions 90 days; Better Stack per plan retention"
discoverability_test:
  command: bash apps/web-platform/infra/scripts/web-probes-token-rotation-verify.sh
  expected_output: "ROTATED"
  credentials_required: "Doppler token-list read on soleur/prd (DOPPLER_TOKEN_TF from Doppler soleur/prd_terraform) — service-token metadata (slug, name, created_at) is exposed by no unauthenticated endpoint, and the property verified (the snapshot-exposed token slug 01941a89 no longer exists; a replacement post-dates the image) is observable only through that listing."
```

## Encryption Posture

The change adds no store and no connection. It swaps the credential inside an existing at-rest store
and an existing delivery channel. The posture of both is declared here because the `.tf` edit
triggers this gate, and because the store's weakness is the reason for the change.

```yaml
at_rest:
  - store: "web-1/web-2 root disk: /etc/default/{web-private-nic-guard,web-zot-consumer-probe,inngest-consumer-probe,web-git-data-probe}"
    mechanism: plaintext-exception
    evidence: "apps/web-platform/infra/server.tf private_nic_guard_install `( umask 0137 && printf ... > /etc/default/web-private-nic-guard )` + `chmod 600`; web-probe-envwrite.sh same shape"
    defends_against: "non-root local users on the host reading the token (mode 0600 root)"
    does_not_defend: "anyone holding a copy of the root disk — a Hetzner snapshot image such as 411798619, a rescue-mode mount, or a root compromise of the host"
    disclosed_as: not-publicly-claimed
    live_verification: "unavailable: no SSH runbook by rule (hr-no-ssh-fallback-in-runbooks); only the Doppler token listing and the heartbeats are verifiable off-host"
in_transit:
  - connection: "GitHub Actions runner -> web-1 (terraform file/remote-exec provisioners)"
    enforced_at: ".github/actions/cf-tunnel-ssh-bridge (cloudflared access over TLS to Cloudflare) + server.tf connection { host_key = local.web_1_ssh_host_key }"
    tls: "TLS 1.3 to the Cloudflare edge, then SSH inside the tunnel"
    cert_verification: "on"
    does_not_defend: "a compromised runner or a compromised CF Access service token (ci_ssh) — either can read what it delivers"
    disclosed_as: not-publicly-claimed
exception:
  justification: "the probe units need a Doppler credential at rest on the host to run `doppler run` on a timer; the host root disk is not encrypted"
  tracking_issue: "#8734"
  reevaluate_when: "image 411798619 is deleted (hard date 2026-10-06 per #8734), or web hosts gain an encrypted root / a non-persistent credential channel"
  expires_on: 2026-12-23
```

## Guard Contract

The plan review cut this section down. The leaked-names denylist and the name-date pattern are
**gone**: a token's name is only a label, and re-using a name mints a new key rather than reviving the
leaked one (simplicity finding). The class taxonomy is gone too, and the heredoc and alias rows were
folded into one rule (DHH).

### Guard 1 — every provisioner consumer of the probe token re-fires on rotation

**Property.** Every block that references `doppler_service_token.web_probes` is one of three kinds.
A `resource "terraform_data"` block is allowed only when its `triggers_replace` expression contains
`sha256(doppler_service_token.web_probes.key)`. The other two are the allowed exceptions:

- the defining `resource "doppler_service_token" "web_probes"` block;
- the `web_probes_token = doppler_service_token.web_probes.key` argument inside
  `resource "hcloud_server" "web"`, the fresh-host path.

Any other reference is RED: a `locals` alias, an `output`, a `github_actions_secret`, or a
`terraform_data` without the hash.

**Assembly.** The chokepoint is every `*.tf` file of `apps/web-platform/infra/`, lexed by
`tokenize()`. Its heredoc token carries its body, per Phase 2. References are matched in `ID . ID`
sequences, templated `STR` tokens, and `HEREDOC` bodies. The population is counted **per enclosing
top-level block**, never per reference. Each installer holds two references, one in its trigger and
one in its `printf`, and the block count is what the property is about.

Floors, counted at the call site:

| Block kind | Floor |
|---|---|
| hash-bearing `terraform_data` blocks | at least 4 |
| `hcloud_server.web` exception | exactly 1 |
| definition block | exactly 1 |

Targeting in the post-bridge SSH stage is enforced by `terraform-target-parity.test.ts` Guard 1. It is
cited here, not duplicated.

**Mutation matrix:**

| # | Mutation (each must be confirmed applied to the temp copy) | Expected |
|---|---|---|
| 1 | Delete the `nonsensitive(sha256(doppler_service_token.web_probes.key))` line from `git_data_probe_install`'s `triggers_replace` | RED |
| 2 | Guard dispatch: scan an empty directory, or break the matcher so it matches nothing | RED (floors) |
| 3 | Add a fifth `terraform_data` whose `remote-exec` `printf` interpolates the key, with no hash trigger, after four compliant members | RED |
| 4 | Move the hash into a `#` comment inside `triggers_replace` | RED (comments are lexed out) |
| 5 | Add `locals { probe_tok = doppler_service_token.web_probes.key }` and consume `local.probe_tok` from a new `terraform_data` | RED (reference outside the allowed blocks) |
| 6 | Put the only key reference of a new `terraform_data` inside a `<<-EOT … EOT` heredoc | RED (heredoc bodies are matched) |

**Harness rows:**

| # | Row | Expected |
|---|---|---|
| H1 | Must-PASS non-canonical input: one installer's trigger rewritten as a bare `triggers_replace = nonsensitive(sha256(doppler_service_token.web_probes.key))`, the `workspaces-luks.tf` form | PASS |
| H2 | Suite edit: stub the per-block check to always return ok | RED (the call-site block counter ≠ the verdict count) |

### Guard 2 — the token keeps `create_before_destroy`

**Property.** `resource "doppler_service_token" "web_probes"` carries
`lifecycle { create_before_destroy = true }`, so a failed create during any future rotation can never
land after the delete.

**Assembly.** Exactly one lexed `doppler_service_token` block labelled `web_probes`, found anywhere in
the root. Finding zero blocks, or two, is RED.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the `lifecycle` block | RED |
| 2 | Set `create_before_destroy = false` | RED |
| 3 | Comment out the `lifecycle` block | RED |
| 4 | Guard dispatch: rename the resource label so the block count is 0 | RED |

**Harness rows:**

| # | Row | Expected |
|---|---|---|
| H1 | Must-PASS non-canonical input: the `lifecycle` block written on one line versus multi-line | PASS in both forms |

### Guard 3 — the rotation verifier reports ROTATED only on positive evidence

**Property.** `web-probes-token-rotation-verify.sh` exits 0 with `ROTATED` if and only if all three
hold:

- the listing is a non-empty `tokens` array;
- no slug in it starts with `--retired-slug`;
- a token whose name starts with `--name-prefix` has `created_at` later than `--not-before`.

**Assembly.** One verdict function, one input (the listing body, from the fixture seam or the API).
The suite asserts that each verdict word occurs exactly once in the script, and that no `exit 0` sits
outside the verdict function.

**Mutation matrix:** (fixtures, synthesized slugs and names only)

| # | Fixture | Expected |
|---|---|---|
| 1 | `{"tokens": []}` | `UNAVAILABLE`, exit 2 |
| 2 | `{}`, or a body that is not JSON | `UNAVAILABLE`, exit 2 |
| 3 | The retired slug together with a dated replacement, a second member after a compliant first | `STALE`, exit 1 |
| 4 | Retired slug absent; replacement `created_at` earlier than `--not-before` | `MISSING`, exit 1 |
| 5 | Retired slug absent; no token with the prefix | `MISSING`, exit 1 |

**Harness rows:**

| # | Row | Expected |
|---|---|---|
| H1 | Must-PASS non-canonical input: a rotated listing that also holds unrelated tokens and a later `web-probes-read-2027-01-15` | `ROTATED`, exit 0 |

## Files to Edit

- `apps/web-platform/infra/web-probe-read-token.tf`: rename the token, add `lifecycle`, and replace
  the rotation comment (Phase 1).
- `apps/web-platform/infra/server.tf`: required comment-only rewording of the four "`-replace`
  rotation" comments (Phase 1 step 5).
- `scripts/lint-doppler-description-length.py`: a one-line change so the `HEREDOC` token carries its
  body. The lint's own behaviour is unchanged (Phase 2).
- `.github/workflows/infra-validation.yml`: register the new suite (Phase 2).
- `plugins/soleur/test/preflight-discoverability-test.test.ts`: `BASELINE_DECLARED_PROBES` goes from
  24 to 25, with a PLACEMENT/TRUTH/NO SUBSTITUTE comment (Phase 2b).
- `knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md`:
  a 2026-09-24 addendum paragraph (Phase 1 step 6).
- `knowledge-base/engineering/operations/runbooks/web-host-replace.md`: add "re-seed a rotated baked
  credential" to the route's documented uses (Phase 1 step 6).
- `scripts/guard-vacuity-floor.test.sh`: edit only if its derived population picks up the new suite,
  and then only through `PROMOTED_FILES` (check at work time).

## Files to Create

- `apps/web-platform/infra/web-probes-token-rotation.test.sh`: Guards 1–3. The mutation battery runs
  in the default invocation.
- `apps/web-platform/infra/scripts/web-probes-token-rotation-verify.sh`: the parameterized, read-only
  rotation verifier (Phase 2b).

## Open Code-Review Overlap

Checked 77 open `code-review` issues against every planned path.

- **#7942** (two mutation batteries under `plugins/soleur/test/` are named `*.mutation.sh` and run in
  no gate) matches `.github/workflows/infra-validation.yml`. **Acknowledge.** It concerns other files.
  Its lesson is folded into this plan's design: the new suite's `--self-test` battery must run inside
  the registered `infra-validation.yml` step (the default invocation runs the battery, or the step
  invokes both modes), so it can never be a battery that runs in no gate.
- **#2197** (billing refactor) matches `server.tf` only incidentally. **Acknowledge.** It is unrelated.

## Deferrals

- **Snapshot `411798619` holds prd secret values, not just tokens.** Filed at plan time as **#8734**
  (P1, `type/security`, `domain/engineering`, `domain/legal`, milestone Phase 4). It is not folded in
  because the remedy is deleting the image (ADR-100's verb) or rotating values across vendors, and
  neither is a token rotation. The re-evaluation trigger is in the issue: image deleted plus evidence
  recorded, with 2026-10-06 as the hard date.

## Acceptance Criteria

### Pre-merge

- [ ] `web-probe-read-token.tf` declares `name = "web-probes-read-2026-09-24"` and
  `lifecycle { create_before_destroy = true }`. `access = "read"`, `config = "prd"` and
  `project = "soleur"` are unchanged.
- [ ] Neither `apps/web-platform/infra/web-probe-read-token.tf` nor `apps/web-platform/infra/server.tf`
  still carries the stale guidance: `! grep -n -e 'apply -replace=doppler_service_token' -e '-replace. rotation' <both files>`
  returns nothing. The new token-file comment names the four installers, the web-2 re-seed, and what
  CBD does *not* cover.
- [ ] `bash apps/web-platform/infra/web-probes-token-rotation.test.sh` exits 0. Its default run grades
  every Guard 1–3 mutation RED (each one confirmed applied) and every must-PASS row green. It prints
  the block floors it measured: hash-bearing `terraform_data` = 4, `hcloud_server.web` exception = 1,
  definition = 1.
- [ ] `python3 scripts/lint-doppler-description-length.py` still exits 0 after the `HEREDOC`-body
  change.
- [ ] The suite is registered in `infra-validation.yml`, and
  `bash apps/web-platform/infra/run-registered-suites.sh` lists it as registered.
- [ ] Against today's Doppler state, `bash apps/web-platform/infra/scripts/web-probes-token-rotation-verify.sh`
  prints `STALE` and exits 1. This is the probe's positive control before merge.
- [ ] `bun test plugins/soleur/test/preflight-discoverability-test.test.ts` passes with
  `BASELINE_DECLARED_PROBES = 25`. This plan's `credentials_required` value sits on one line.
- [ ] These existing suites stay green:
  - `web-zot-consumer-probe.test.sh`
  - `web-private-nic-guard.test.sh`
  - `web-git-data-probe.test.sh`
  - `inngest-consumer-probe.test.sh`
  - `fresh-boot-parity.test.sh`
  - `workspaces-luks-host-token-refresh.test.sh`
  - `bun test plugins/soleur/test/terraform-target-parity.test.ts`
  - `scripts/guard-vacuity-floor.test.sh`
  - `plugins/soleur/test/c4-count-parity.test.sh`
- [ ] `terraform validate` passes in `apps/web-platform/infra`. The PR's `infra-validation.yml` `plan`
  job is untargeted, uses `-refresh=false`, and sits on a standing drift baseline, so compare it with
  main's latest run rather than reading it alone. It differs from that run only by the
  `doppler_service_token.web_probes` create-before-destroy replace and the four installer
  `terraform_data` replaces (their triggers read the not-yet-known key).
- [ ] The first line of the PR body answers "does merging this alone mutate production?" with **yes**:
  the merge apply mints the new token and deletes `web-probes-read`, hence `[ack-destroy]`.
- [ ] The PR body carries `Ref #8705` and `Ref #8734`, never `Closes`, and
  `gh pr view <N> --json closingIssuesReferences` returns `[]`. It says "forward read access closed;
  value exposure tracked in #8734", never "exposure closed". It names the web-2 re-seed and the web-2
  heartbeat alert window.

### Post-merge (automated reads, no SSH)

- [ ] The merge commit message on `origin/main` contains `[ack-destroy]` on its own line, and the push
  run whose `head_sha` is the merge SHA concluded `success` rather than `cancelled`.
- [ ] That run's main apply reads `1 added, 0 changed, 1 destroyed`, and the only address is
  `doppler_service_token.web_probes`. Its SSH stage shows `Creation complete` for
  `private_nic_guard_install`, `zot_consumer_probe_install`, `inngest_consumer_probe_install` and
  `git_data_probe_install`.
- [ ] `bash apps/web-platform/infra/scripts/web-probes-token-rotation-verify.sh` prints `ROTATED` and
  exits 0: slug `01941a89` is gone, and a `web-probes-read-*` token created after the image exists.
- [ ] **web-1 beats, before the web-2 dispatch:** Better Stack `GET /api/v2/heartbeats` (read-only
  token) is read twice, at least 8 minutes apart, both reads after the SSH stage finished. Both reads
  show `status=up` for:
  - `soleur-web-nic-guard-web-1`
  - `soleur-web-zot-consumer-web-1`
  - `soleur-inngest-consumer-prd`
  - the git-data heartbeat

  web-2 still holds a dead token at this point, so the shared beats prove web-1 alone.
- [ ] **web-2:** after the operator's go-ahead, a `plan_only=true` rehearsal passes. The real
  `web-host-replace` run, resolved by id, then has its `web_host_replace` job conclude `success`, and
  Hetzner shows web-2 `created` after the merge. `soleur-web-nic-guard-web-2` and
  `soleur-web-zot-consumer-web-2` read `status=up` on two reads at least 8 minutes apart. A Better Stack
  Logs query of Source 4 for host `soleur-web-2` returns no probe `FATAL` or Doppler `401` lines after
  the job ended.
- [ ] No push run was `cancelled` while the dispatch waited for approval. If one was, a `manual-rerun`
  was dispatched and succeeded.
- [ ] #8705 is closed with a comment that cites the verifier output, the apply run and the web-2
  replace run. #8734 stays open.

## Domain Review

**Domains relevant:** Engineering, Legal, Product. The `security` keyword makes this a cross-domain
lane with at least 2 leaders. Product sign-off is required at the `single-user incident` threshold.

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Accept the single-PR rename + CBD shape. Two alternatives are rejected. The two-PR
add-then-remove keeps the leaked token live through a second merge in exchange for less email. The
same-name `-replace` either deletes first or relies on unprobed same-name coexistence. The ~15 min
of web-2 email alerts is accepted: web-2 is a weight-0 standby, the shared beats stay fed by web-1,
and the alerts are the true re-seed signal. Checked against the repo:

- the destroy guard sees only `resource_deletes=1`, and no HALT arm is reachable;
- only the four installers and the `hcloud_server.web` template argument use the key;
- `inngest_consumer_probe_install` is in the SSH-stage target list;
- the main apply does not touch the installers.

Three fixes are folded in: (1) the post-merge check confirms the web-2 dispatch actually *ran*,
because the concurrency group can drop a pending run; (2) the claim about the fallback file was
corrected (the file names are token-hashed, so the old file stays); (3) Guard 1 now fails on any
reference outside a `resource` block (a `locals` alias). The CTO also suggested one suite
parameterized over token addresses instead of a second parser. That is addressed by reusing the
existing HCL tokenizer, and Guard 2's leaked-names half already spans every `doppler_service_token`,
including `workspaces_luks`. No ADR is needed: this applies ADR-119's recorded rotation shape.

### Legal (CLO)

**Status:** reviewed
**Assessment:** This is not an Art. 33/34 breach on current facts. The image sits in Jikigai's own
Hetzner project (a disclosed Art. 28 processor), and nothing shows third-party access. Record it as
security hardening. This PR needs no change to the Art. 30 register, `docs/legal/**` or
`compliance-posture.md`. Wording rule: say "forward read access closed", never "exposure closed".
The matter widens the 2026-09-23 breach-register row (#8209, limb L3: a server create or rebuild
from a retained image is a fourth `HCLOUD_TOKEN` route to root). That correction, the
evidence-before-deletion step and the value rotation all live in #8734. `soleur:gdpr-gate` is not
required: a `.tf` edit and a credential swap are not on the regulated-data surface list, and none of
the four expanded triggers apply (no new processing activity, no new distribution surface, no
learnings-reading cron). The `single-user incident` trigger (b) is noted; the CLO judged the gate
would not perform the breach assessment, and the breach assessment is carried by #8734.

### Product/UX Gate

**Tier:** none (no user-facing surface; no UI file among the files to edit or create)
**Decision:** reviewed
**Agents invoked:** soleur:product:cpo (threshold sign-off)
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

The CPO requested changes, and all of them are applied: (1) file the value-exposure follow-up, which
is now #8734 at P1 with the 2026-10-06 bound; (2) add the residual-risk line to User-Brand Impact;
(3) remove the dangling pointer to the Session Summary. The CPO re-read the plan after the changes;
its verdict is recorded on the line below.

**CPO sign-off: approved** (re-review after the three changes, 2026-09-24).

## Test Scenarios

- Given the current tree, when the rotation suite runs, then it passes with these block floors:
  4 hash-bearing `terraform_data` blocks, 1 `hcloud_server.web` exception and 1 definition block.
- Given each Guard 1–3 mutation row, when the default run applies it to a temporary copy (confirmed
  changed) or feeds the fixture, then that row grades RED and every must-PASS row grades green.
- Given the merged tree, when the per-merge apply plans, then the destroy guard reports
  `resource_deletes=1` and nothing else. The merge commit's `[ack-destroy]` line clears it, and no HALT
  counter (host_creates, luks, apex, undecidable) is non-zero.
- Given the merge run was superseded, when the next push run plans, then it HALTs on the unacked
  delete. A comment-only commit to `web-probe-read-token.tf` that carries `[ack-destroy]` recovers it.
- Given the SSH stage completed, when the probe timers next fire on web-1, then `doppler run`
  authenticates with the new token and every web-1 beat stays up on two reads 8 minutes apart. The
  heartbeat URLs come only from the `doppler run` environment, so a beat proves a live fetch.
- Given web-2 still holds the old token, when its timers fire after the merge, then `doppler run`
  gets a 401 and deletes that token's fallback (CLI `canUseFallback`), and web-2's per-host beats go
  down. That is the expected signal, and it clears once web-2 is replaced.
- Given the verifier fixtures (rotated, stale, missing, empty, non-JSON), when it runs, then it
  prints exactly `ROTATED`/`STALE`/`MISSING`/`UNAVAILABLE` with exit 0/1/1/2.

## Plan Review Revisions (2026-09-24)

A six-seat panel reviewed the plan: DHH, Kieran, code-simplicity, architecture-strategist,
spec-flow-analyzer, and CTO (devex). Every finding below is Mechanical and was applied. No finding
changed the operator's stated direction (rename + CBD, the web-2 re-seed, the sweep), so there are no
Taste or User-Challenge entries and no `decision-challenges.md`.

- **Cut (simplicity + DHH): the leaked-names denylist and the name-date pattern.** A name is only a
  label, so a re-used name mints a new key. The verifier now keys on the retired slug `01941a89`. Guard
  1's four-class taxonomy became one rule counted per block.
- **Fixed (Kieran P0).** `credentials_required` was a `>-` block, which the parser reads as declaring
  nothing. It is now a single line, so the 24→25 ratchet bump is correct.
- **Fixed (Kieran P0).** `tokenize()` dropped heredoc bodies, so the heredoc row failed open. The
  `HEREDOC` token now carries its body (a one-line change to the lint), and the matcher also reads
  templated `STR` tokens.
- **Fixed (Kieran P1).** Verdicts were undefined for some listings. `MISSING` was added, and
  `ScanError` grades RED.
- **Fixed (spec-flow P0, architecture P1).** `[ack-destroy]` belongs to one push. Phase 3 adds an
  idle-concurrency-group precheck, a check by `head_sha`, and the recovery commit.
- **Fixed (spec-flow P0, architecture P1).** The post-apply "HALT" did not exist. The destroy-set
  check moved before the merge.
- **Fixed (architecture P2).** The PR `plan` job expectation now matches reality: untargeted,
  `-refresh=false`, and the four installers also replace.
- **Added (architecture P2).** A `plan_only=true` rehearsal before the real web-2 replace; the
  vector-redeliver early-dispatch sharp edge; and an ADR-119 addendum citing ADR-154 and ADR-148.
- **Added (spec-flow P1).**
  - the git-data beat;
  - web-1 beat reads finish before the web-2 dispatch;
  - two reads a full period apart;
  - a Source 4 FATAL/401 query for web-2's shared-beat units;
  - the cancelled-push sweep after approval;
  - a resume checklist comment on #8705;
  - Monitor on both runs.
- **Added (CTO devex).** The verifier is parameterized (`--retired-slug`, `--name-prefix`,
  `--not-before`, `--config`). The operator gets one plain-language message before the dispatch. The
  manual cpx22 check was dropped, because the job's own preflight fails closed.
- **Fixed (DHH).**
  - the Encryption Posture exception now tracks #8734, not the issue this plan closes;
  - the `server.tf` comment rewording is required, not optional;
  - the Research Reconciliation rows that duplicated Premise Validation were removed.
- **Declined (DHH, simplicity): replacing the verifier with an inline `curl | jq`.** preflight Check 10
  rejects `|` and `$` in `discoverability_test.command`, and green-only-on-positive-evidence needs the
  fixture rows.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, holds only `TBD`/`TODO`/placeholder text, or
  omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or
  `soleur:work`.
- The merge commit's `[ack-destroy]` must sit on its own line, outside a code fence or trailer
  (`apply-web-platform-infra.yml` anchors it `(^|\n)\[ack-destroy\]($|\n)`).
- Do **not** dispatch the web-2 replace before the merge apply is green. A replace before the rotation
  re-bakes the old token, and nothing catches it: the gate sees no out-of-scope change because the
  token is not yet planned to change. A dispatch after the merge but before the apply converges is
  refused by the gate. The same early-dispatch refusal applies to `apply_target=vector-redeliver`,
  whose plan also pulls in `doppler_service_token.web_probes`
  (`tests/scripts/lib/vector-redeliver-gate.sh`).
- `[ack-destroy]` belongs to one push. A superseded or cancelled merge run leaves every later push
  run HALTing on the unacked token delete. The recovery is a new commit that carries the ack; a
  dispatch cannot carry it, and re-running an older run is also wrong (Phase 3 step 4).
- **Committing this plan already moves the ratchet.** Measured at plan time:
  `bun test plugins/soleur/test/preflight-discoverability-test.test.ts -t G1` gives
  `Expected: 24, Received: 25`. The first work commit bumps `BASELINE_DECLARED_PROBES` to 25, before
  anything else lands.
- Keep the `credentials_required` value on the same line as its key. A bare `>-` block reads as
  "declares nothing" to `parseCredentialsRequired()`, and the ratchet bump then turns red.
- Guard 1 counts **blocks**, not references. Each installer references the key twice, once in the
  trigger and once in the `printf`.
- `-target` is transitive toward dependencies only. The installers are **not** in the main apply's
  target list, so the main apply never touches web-1. Delivery is solely the SSH stage's job. Do not
  "fix" the window by adding the installers to the bridge-less stage: `terraform-target-parity`
  Guard 1 forbids it, and the bridge is not up yet at that point (#7539).
