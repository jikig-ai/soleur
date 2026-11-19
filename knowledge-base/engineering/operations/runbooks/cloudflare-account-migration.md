---
title: "Runbook: migrate the web-platform Terraform root to the Soleur Cloudflare account (#12931)"
category: infrastructure
tags: [cloudflare, terraform, migration, doppler, tunnel, incident]
date: 2026-11-19
triggers:
  - verdict=cf-account-migration-in-progress
  - cf_zone_id must not be the old soleur.ai zone
  - cf_account_id must not be the old Cloudflare account
  - soleur.ai redirect monitors red after the Cloudflare account move
  - deploy.soleur.ai has no DNS record
  - ssh.soleur.ai or registry.soleur.ai returns Cloudflare Error 1000
  - scheduled-terraform-drift red during the Cloudflare migration
---

# Runbook: migrate the web-platform root to the Soleur Cloudflare account

Decision: [ADR-329](../../architecture/decisions/ADR-329-cloudflare-zone-resources-live-on-the-soleur-account-r2-stays.md).
Plan: `knowledge-base/project/plans/2026-11-18-infra-cloudflare-migrate-terraform-to-soleur-account-plan.md`.
Rulings: `knowledge-base/project/specs/feat-one-shot-12931-cf-account-migration/decision-challenges.md`.
Incident: `knowledge-base/engineering/operations/post-mortems/soleur-ai-cloudflare-account-move-outage-2026-11-18-postmortem.md`.

## Conventions

- **Owners.** `Operator-authorizes:` marks a production-mutating or irreversible act. The agent runs it only after a
  typed go that names the exact command (`hr-menu-option-ack-not-prod-write-auth`); a menu pick is not a go. Each
  apply leg also stops at the reviewer-gated `web-platform-infra-apply` environment, and the operator's approval there
  is the production-write authorization. A standing delegation recorded on #12931 can cover the dispatch lines it names
  verbatim; anything it does not name needs its own go. `Agent:` marks a read-only step the agent runs unprompted.
- **No SSH, anywhere.** Every step talks to the Cloudflare API, Doppler, GitHub Actions or Terraform state. Host health
  is read through the connector census, `verify-tunnel-ingress-origin.sh`, Better Stack and Sentry
  (`hr-no-ssh-fallback-in-runbooks`).
- **No secret on screen.** Every Doppler write pipes the value on stdin with `--silent` and stdout to `/dev/null`.
  Verification compares `sha256sum` of source and destination; non-secret ids print at most an 8-character prefix.
  Never put a token in argv, a shell variable on screen, a Playwright snapshot or a screenshot.
- **Every dispatch arms a watch** (`hr-dispatch-async-must-arm-watch`): `gh run watch <run-id> --exit-status`.
- **Before every dispatch**, refuse if a stale run is queued, waiting or in progress, because a queued run still
  executes:

  ```bash
  for wf in apply-web-platform-infra.yml apply-deploy-pipeline-fix.yml cf-lb-overlay.yml; do
    for st in queued in_progress waiting; do gh run list --workflow "$wf" --status "$st" --limit 5; done
  done
  ```

  Expected: every list empty. The migrate job repeats this check (plus `pending` and `requested`) and refuses with
  `reason=run-in-flight`.

Placeholders: `<phase>` is one of `redirects-dns`, `zone-rest`, `tunnel` (PR2); `<utc>` is `date -u +%Y%m%dT%H%M%SZ`;
`<run-id>` is the dispatched run.

### Ids (not secrets)

| | Old (legacy account) | New (Soleur account) |
|---|---|---|
| Zone `soleur.ai` | `5af02a2f394e9ba6e0ea23c381a26b67` (`status=moved`, read-only, never mutated) | `951ce525552201ec6c696b24251abed7` |
| Account | `4d5ba6f096b2686fbdd404167dd4e125` (keeps R2 only) | `66d4f93f7397f196544e9fe84c3557c2` |

### The dispatch

```bash
gh workflow run cf-account-migrate.yml --ref main -f migrate_phase=<phase> \
  -f confirm=MIGRATE-CF-<phase> -f rehearsal=<true|false> -f reason='#12931 <phase>'
```

The workflow is `.github/workflows/cf-account-migrate.yml` (job `cf_account_migrate`, its own file because
`apply-web-platform-infra.yml` is at its byte cap, CTO L79). It shares the `terraform-apply-web-platform-host`
concurrency group. The job body is `apps/web-platform/infra/scripts/cf-account-migrate-job.sh`.
Before anything is written it checks that Doppler resolves `cf_zone_id`/`cf_account_id` to the new ids
(`reason=zone-id-not-new` / `account-id-not-new` otherwise).
`rehearsal=true` (the default) runs under environment `infra-privileged`, which has no reviewers. A scratch copy of
the root with a `backend "local"` override runs the real state-forget script (`--rehearsal`, backup under
`$RUNNER_TEMP/cf-migrate`) and a plan, and never applies. It writes nothing to R2: the job asserts the remote state
serial is unchanged and that no new object appeared under `web-platform/backups/`.
`rehearsal=false` is the apply (environment `web-platform-infra-apply`, reviewer-gated). Always rehearse first.

## Expected reds (do not "fix" these mid-migration)

| Red | Window | Why |
|---|---|---|
| Every plan of this root fails on the old-id validations, including `web-host-replace` and the registry dispatcher | PR1 merge → Phase 2 flip | Doppler still holds the old ids; the validations fail closed. Keep this window short: flip in the same sitting as the merge. |
| Every plan-capable job of `apply-web-platform-infra.yml`, `apply-deploy-pipeline-fix.yml` and `cf-lb-overlay.yml` exits non-zero with `verdict=cf-account-migration-in-progress` and an `::error::` naming this runbook | Phase 2 flip → end of the tunnel phase plus a live connector | The state-derived predicate is false. Exception: `web_host_replace` with `web_host_key=web-2` once the tunnel is in state on the new account. |
| `scheduled-terraform-drift.yml` red | Phase 2 flip → `manual-rerun` green | Not gated; it only plans, and the plan shows the forgotten and not-yet-adopted addresses. |
| Connector census in `scheduled-inngest-health.yml` red (no tunnel, then 0 connectors) | Phase 2 flip → web-2 replace | The census looks the tunnel up by name under the new `CF_ACCOUNT_ID`. |
| `deploy.`/`ssh.`/`registry.` answer 530/1033 instead of Error 1000 | Tunnel apply → web-2 replace | The new tunnel exists with 0 connectors. Both states are down; nothing regresses. |
| `cron-gh-pages-cert-reissue` reports `precondition_blocked` | Old DNS-edit token revoke → next release redeploy | Its frozen container env still holds the revoked token. Fails closed by design. |
| First CI-SSH token sync warns on an empty secret | First tunnel-phase apply | A freshly synced secret reads empty on the first run; expect one re-dispatch. |

## Phase 0 — credentials (no repo change; before any dispatch)

### 0a and 0b: mint the new-account tokens

`Operator-authorizes:` the mints. They run in the operator's signed-in dashboard session through the `cf-token-scope`
skill flow, because no Soleur token holds API Tokens:Edit (ADR-130). Mint **0a** first (what `redirects-dns` needs:
`CF_API_TOKEN`, `CF_API_TOKEN_RULESETS`, `CF_API_TOKEN_PAGES`); mint **0b** (`CF_API_TOKEN_ZONE_SETTINGS`,
`CF_API_TOKEN_BOT_MANAGEMENT`, `CF_API_TOKEN_DNS_EDIT`, `CF_API_TOKEN_PURGE`) while the first dispatch runs. The
permission groups per key are the plan's Phase 0 table; one token per key, scoped to the new account and the
`soleur.ai` zone only, 90-day expiry. `CF_API_TOKEN_R2` is **not** re-minted.

**Hand-off (CTO L75).** For each token:

1. Mint with `browser_run_code_unsafe`: the Node-side `page.evaluate` creates the token through
   `/api/v4/user/tokens` (session `x-atok`), and `page.request.post` hands the value to a one-shot python sink bound to
   `127.0.0.1` that writes a mode-0600 file in the session scratchpad, outside every git work tree. The tool result
   prints only the token id, the sink status and the length.
2. Write it to the **staging** key, never over the live one:

   ```bash
   doppler secrets set <KEY>_NEXT -p soleur -c prd_terraform --silent < "<scratchpad>/<key>.tok" > /dev/null
   doppler secrets get <KEY>_NEXT -p soleur -c prd_terraform --plain | sha256sum
   sha256sum < "<scratchpad>/<key>.tok"
   ```

   Expected: the two digests are equal.
3. Confirm the token is active without printing it, then shred the file:

   ```bash
   doppler run -p soleur -c prd_terraform -- bash -c 'printf "Authorization: Bearer %s\n" "$<KEY>_NEXT" \
     | curl --disable -sS --max-time 30 --header @- https://api.cloudflare.com/client/v4/user/tokens/verify' \
     | jq -r '.success, .result.status'
   shred -u "<scratchpad>/<key>.tok"
   ```

   Expected: `true`, `active`.
4. Run `git status --porcelain` in the main checkout and in this worktree. Expected: no new untracked file.

`browser_evaluate` with `filename` is banned for secrets (on 2026-11-18 it wrote inside the main repository). No
`browser_snapshot` or screenshot after "Create Token". On any failure, delete that token in the dashboard and re-mint,
or fall back to an operator paste into the same `doppler secrets set … --silent … > /dev/null` form.

`CF_API_TOKEN_SOLEUR_ACCT` (the temporary token) is revoked, `Operator-authorizes:`, as soon as 0a is minted and
probed.

### Write-probe each token before its phase (CTO L49)

`Agent:` run the per-phase new-account profile of
`plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh` once per phase, before that phase's rehearsal, and post
the verdict lines on the PR thread. The exact profile flags are in the script's `--help`. The probe contract:

- A write probe sends **one fixed invalid body literal that can never validate**, never `{"rules":[]}` (which would
  wipe a live entrypoint) and never a valid body. It never `DELETE`s.
- Each profile first proves, with a known-denied token, that the endpoint answers `403` before `400`. Only then does a
  `400` count as authorized.
- **Any `2xx` is a fatal abort**, followed immediately by a read-back of that entrypoint (`GET`, `success:true` and a
  parsed `.result` required). Post the read-back on #12931 and stop.
- Each profile includes one known-present control endpoint, so a degraded `200` or a `404` is never read as "empty".
- Deny probes: each token must be refused on the old account and old zone, and on one permission group it must not
  hold.

The rulesets token is probed on `http_request_dynamic_redirect`, `http_response_headers_transform`,
`http_config_settings`, `http_request_cache_settings`, `http_request_firewall_custom`, the account
`http_request_redirect` and `/accounts/<new>/rules/lists`. A `404` on an entrypoint means nothing hand-made exists
there; an existing entrypoint is recorded by id and imported, never overwritten. Expected: `verdict=authorized` on
every write row; any `denied` blocks that phase's dispatch.

### `CF_R2_ACCOUNT_ID` (before PR1 merges)

`Operator-authorizes:` the write (the variable has no default):

```bash
printf '%s' 4d5ba6f096b2686fbdd404167dd4e125 | doppler secrets set CF_R2_ACCOUNT_ID -p soleur -c prd_terraform --silent > /dev/null
doppler secrets get CF_R2_ACCOUNT_ID -p soleur -c prd_terraform --plain | cut -c1-8
```

Expected: `4d5ba6f0`.

### 0c (optional): early noindex

`Operator-authorizes:` (recommended yes) create only the `http_response_headers_transform` entrypoint in the new zone,
with the four rules `seo-rulesets.tf` declares, rendered from the code by `terraform console`, never hand-typed. The
`redirects-dns` phase then adopts it as a pure import.

## Phase 1 — merge PR1

`Operator-authorizes:` merge PR1 with a merge-commit line containing exactly `[skip-web-platform-apply]`. Arm a watch on
any push-triggered run anyway. Merging alone mutates no production resource. The merge-to-flip window starts now (see
Expected reds); run Phase 2 step 1 in the same sitting.

## Phase 2 — flip, then restore redirects (`redirects-dns`, `zone-rest`)

### Step 1: the flip sequence (one typed go covers all of it)

`Operator-authorizes:` the whole sequence. The agent runs, in order:

1. **Keep the revert values.** For `CF_ZONE_ID`, `CF_ACCOUNT_ID` and each Phase 0a key:

   ```bash
   doppler secrets get <KEY> -p soleur -c prd_terraform --plain \
     | doppler secrets set <KEY>_PREV -p soleur -c prd_terraform --silent > /dev/null
   ```

2. **Flip the ids and swap the tokens.**

   ```bash
   printf '%s' 951ce525552201ec6c696b24251abed7 | doppler secrets set CF_ZONE_ID -p soleur -c prd_terraform --silent > /dev/null
   printf '%s' 66d4f93f7397f196544e9fe84c3557c2 | doppler secrets set CF_ACCOUNT_ID -p soleur -c prd_terraform --silent > /dev/null
   doppler secrets get <KEY>_NEXT -p soleur -c prd_terraform --plain \
     | doppler secrets set <KEY> -p soleur -c prd_terraform --silent > /dev/null
   doppler secrets delete <KEY>_NEXT -p soleur -c prd_terraform --yes > /dev/null
   ```

   Verify each id with `doppler secrets get <KEY> --plain … | cut -c1-8` (expected `951ce525`, `66d4f93f`) and each
   token by comparing the `sha256sum` of `<KEY>` with the digest recorded at mint time.
3. **Write the branch-config copies** (branch configs keep their own copies and do not inherit). Build the write list
   from a names-only listing over every config in `apps/web-platform/infra/doppler-config-inventory.txt`:

   ```bash
   for c in $(grep -E '^[a-z0-9_]+$' apps/web-platform/infra/doppler-config-inventory.txt | sort -u); do
     doppler secrets --only-names --json -p soleur -c "$c" \
       | jq -r --arg c "$c" 'keys[] | select(test("^(CF_ZONE_ID|CF_API_TOKEN_PURGE|CF_API_TOKEN_DNS_EDIT|CF_ACCESS_CLIENT_ID)$")) | "\($c) \(.)"'
   done
   ```

   Expected holders, to be confirmed by the listing rather than assumed: `prd`, `prd_cla`, `prd_ghcr`, `prd_git_data`,
   `prd_kb_drift_walker`, `prd_scheduled`, `prd_workspaces_luks`, `prd_workspaces_luks_marker`,
   `prd_workspaces_luks_web`, `dev`, `dev_personal`, `dev_scheduled`, and `prd_terraform` itself (already flipped).
   For each `<config> <KEY>` row:
   - `CF_ZONE_ID`: `printf '%s' 951ce525552201ec6c696b24251abed7 | doppler secrets set CF_ZONE_ID -p soleur -c <config> --silent > /dev/null`
   - `CF_API_TOKEN_PURGE` / `CF_API_TOKEN_DNS_EDIT`: pipe the new value from `prd_terraform` (the 0b mint) into the
     config the same way, then compare `sha256sum` of source and destination.
   - `CF_ACCESS_CLIENT_ID`: not written here; Phase 3 step 1 writes the new pair.

   Then re-read `CF_ZONE_ID` from every row (`cut -c1-8`, expected `951ce525`). This doubles as the "every config holds
   the new id" preflight.
4. `Operator-authorizes:` revoke the old-zone "Edit zone DNS" token in the dashboard (it stops
   `cron-gh-pages-cert-reissue` from writing DNS on the moved zone; revoking a user token mutates no zone).

### Step 2: `redirects-dns` rehearsal and apply

Before rehearsing, note the 2026-11-19 zone hygiene: in the new zone, six TXT records created by the move's DNS scan
were rewritten unquoted and the comments on three records added during the incident were cleared, so every
`cloudflare_record` import plans as a pure no-op. If a rehearsal shows an import plus update on a TXT record or a
`comment` diff, that record has drifted again: re-read it and fix the record or the pinned id, never widen the gate.

`Operator-authorizes:` the dispatch with `migrate_phase=redirects-dns -f confirm=MIGRATE-CF-redirects-dns
-f rehearsal=true`. Expected in the run log:

- `cf-state-migrate … verdict=ok removed=N skipped=M` against the local rehearsal copy, with the remote serial
  unchanged and no new object under `web-platform/backups/`;
- `cf_account_migrate_gate: phase=redirects-dns verdict=PASS creates=<N> imports=<M> destroys=0`, where the gate
  derives N and M itself (about 8 rulesets and lists created, minus any entrypoint the probe found, which becomes an
  import; 26 records, the Pages project and 2 Pages domains imported; 1 `doppler_secret.cf_zone_id_prd` add). Compare
  nothing by eye.

Any `verdict=REFUSE <reason>` or `verdict=abort` stops the phase: nothing was applied. Read the reason, fix forward in a
PR, re-rehearse.

`Operator-authorizes:` the same dispatch with `rehearsal=false`, then approve the `web-platform-infra-apply`
environment. The real run writes the backup to `web-platform/backups/pre-cf-account-migration-<utc>.tfstate` before its
single `state rm`. Record that object key on #12931: it is the full-revert source.

**Verify** (job step, then `Agent:` locally):

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://soleur.ai/pages/agents.html                         # 301
curl -sS -o /dev/null -w '%{http_code}\n' https://soleur.ai/pages/legal/privacy-policy.html            # 301
curl -sSI https://www.soleur.ai/ | grep -iE '^(HTTP|location)'                                        # 301, location: https://soleur.ai/
curl -sS -o /dev/null -w '%{http_code}\n' https://soleur.ai/blog/2026-03-16-soleur-vs-anthropic-cowork/ # 301
curl -sSI https://app.soleur.ai/ | grep -i '^x-robots-tag'                                            # x-robots-tag: noindex
curl -sS -o /dev/null -w '%{http_code}\n' -A 'Mozilla/5.0 (compatible; GPTBot/1.2)' https://soleur.ai/  # 200
doppler run -p soleur -c prd_terraform -- bash -c 'printf "Authorization: Bearer %s\n" "$BETTERSTACK_API_TOKEN_READONLY" \
  | curl --disable --noproxy "*" -sS --max-time 30 --header @- https://uptime.betterstack.com/api/v2/monitors' \
  | jq -r '.data[] | select(.attributes.pronounceable_name | test("redirect")) | "\(.attributes.pronounceable_name) \(.attributes.status)"'
```

Expected: the four redirect monitors read `up`. Then `Operator-authorizes:` revoke the superseded old-account non-R2
tokens and delete the token `_PREV` keys (the id `_PREV` keys may stay until cleanup). After this point the full revert
needs a re-mint.

### Step 3: `zone-rest` rehearsal and apply

Probe the 0b tokens first. `Operator-authorizes:` the dispatch with `migrate_phase=zone-rest
-f confirm=MIGRATE-CF-zone-rest`, `rehearsal=true`, then `rehearsal=false`. Expected gate line: a
`zone_settings_override` create that adopts the parity settings with no visible change, a `bot_management` create or
update, 2 `github_actions_secret` updates (`CLOUDFLARE_API_TOKEN_PAGES`, `CLOUDFLARE_ACCOUNT_ID_PAGES`) and one
`doppler_secret.cf_api_token_dns_edit` replace (`action_reason=replace_by_request`), destroys 0.

Verify on the next docs push: `deploy-docs.yml` probe A (`https://soleur-docs-40x.pages.dev/version.txt`) passes and
probe B (apex `version.txt`) equals the pushed sha.

## Phase 3 — PR2: tunnel, Access and deploy hosts

1. **Deploy Access service token.** Mint `CF_API_TOKEN_ACCESS_MINT` (Access: Service Tokens:Edit only, 7-day expiry)
   with the Phase 0 hand-off. `Operator-authorizes:` run `apps/web-platform/infra/scripts/cf-access-deploy-token-mint.sh`.
   It writes `CF_ACCESS_CLIENT_ID`/`CF_ACCESS_CLIENT_SECRET` on stdin to `soleur-infra-privileged/prd` and
   `soleur/prd_terraform` (and to every other holder the Phase 2 listing found), and prints only the token UUID. That
   UUID goes into `local.deploy_service_token_ids` in PR2. Then `Operator-authorizes:` revoke `CF_API_TOKEN_ACCESS_MINT`.
2. `Operator-authorizes:` merge PR2 with `[skip-web-platform-apply]`.
3. **Tunnel phase.** `Operator-authorizes:` the dispatch with `migrate_phase=tunnel -f confirm=MIGRATE-CF-tunnel`,
   `rehearsal=true`, then `rehearsal=false`. The apply leg first runs the pinned six-record pre-delete
   (`cf-tunnel-host-predelete.sh --apply`, never from the agent's machine): it GETs each pinned id and deletes all six
   only if every one is a proxied `A` record on `ssh.`/`registry.soleur.ai` with content in
   {`104.26.10.163`, `104.26.11.163`, `172.67.73.132`} in the new zone; one mismatch deletes none
   (`verdict=refuse`). Expected gate line: the tunnel, its config, 3 Access apps, 3 policies, 2 service tokens, the
   `service_token_expiry` notification policy and the `deploy`/`ssh`/`registry` CNAMEs created; `random_id.tunnel_secret`
   and `doppler_secret.registry_push_access_token_id`/`_secret` replaced by request; `cloudflare_record.app` a pure
   import; exactly one create of the deploy policy, whose service token the gate read live (`200`, name
   `github-actions-deploy`, about 8760h to expiry, `decision = "non_identity"`, a single include); destroys 0. The
   post-apply step syncs `CI_SSH_ACCESS_TOKEN_ID/_SECRET` (`apps/web-platform/infra/scripts/sync-ci-ssh-access-token.sh`
   logic); expect one re-dispatch on the first-run empty secret. After the apply, the new tunnel has 0 connectors (an
   expected red).
4. **Replace web-2** (the only path that delivers the new tunnel token: it reaches a host only through create-time
   user_data, ADR-304). `Operator-authorizes:` the rehearsal, then the same line with `plan_only=false`:

   ```bash
   gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=web-host-replace \
     -f web_host_key=web-2 -f confirm=REPLACE-web-2 -f plan_only=true -f reason='#12931 tunnel token'
   ```

   Expected: the replace gate sees exactly its four allow-listed addresses, web-2 boots, and
   `soleur-wait-ready service cloudflared` passes (a failure emits a fresh-boot Sentry event and a Better Stack boot
   trail, source 2457081). web-1 is never touched; `app.soleur.ai` keeps serving from its A record. If the replace
   fails, re-run it.
5. **Re-mint the Origin CA certificate from the new zone** before the release redeploy, with
   `CF_API_TOKEN_ORIGIN_CA` re-scoped to the new zone: `gh workflow run mint-origin-ca-cert.yml --ref main -f mode=plan`,
   then `Operator-authorizes:` the deliberate-rotation apply in `origin-tls-mint.md` §3.
6. **Verify:**
   - the next connector census in `scheduled-inngest-health.yml` (verdict token from `scripts/tunnel-connector-census.sh`)
     reports exactly 1 connector on the new tunnel;
   - `apps/web-platform/infra/scripts/verify-tunnel-ingress-origin.sh` passes (new `CF_ACCOUNT_ID`, new tunnel id,
     `deploy-status` 200 through `deploy.` with the new Access pair);
   - a CI SSH bridge round-trip and a `registry.` push canary succeed;
   - `Operator-authorizes:` `gh workflow run web-platform-release.yml --ref main -f bump_type=patch`; the redeploy
     loads the new runtime `CF_ZONE_ID`, `CF_API_TOKEN_PURGE`, `CF_API_TOKEN_DNS_EDIT` and the new certificate;
     `curl -sS -o /dev/null -w '%{http_code}\n' https://app.soleur.ai/health` returns `200` under `ssl=strict`.
7. **Reopen the routine path.** `Operator-authorizes:`
   `gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=manual-rerun -f reason='#12931 reopen'`.
   The predicate is now true. Expected: green end to end. The `scheduled-terraform-drift.yml` red clears on its next
   run.
8. Before 2026-12-26, record on #12931 that the `api.soleur.ai` `_acme-challenge` renewal works from the new zone.

## Phase 4 — close the incident

Flip the post-mortem to `status: resolved` (frontmatter and `## Status` line), add the recovery timestamps and set the
#12931 action-item row to `resolved` only after all 9 soleur.ai/app Better Stack monitors read `up` and Phase 3 step 6
holds. Never on a projection.

## Phase 5 — cleanup PR (after Phase 3 verification)

- Delete the migration machinery (imports file, state-forget script, predicate and its call sites, the
  `cf_migration_*` variables, `cf-account-migrate.yml` with its job script, and the gate). Keep
  `cf-access-deploy-token-mint.sh` and the `cf-token-scope.sh` profiles.
- `Operator-authorizes:` revoke `CF_API_TOKEN_SOLEUR_ACCT` (if not already) and any superseded old-zone token.
- `Operator-authorizes:` delete the old tunnel `fc4509ed…` in the legacy account once web-2's replace has dropped its
  connections.
- `Operator-authorizes:` delete, one go each and by name, the legacy-account objects the forget left behind, listed from
  the pre-migration backup filtered to old-account non-R2 entries (LB monitor and pool, `ci_ssh` and `registry_push`
  service tokens, Access apps and policies, lists, the account ruleset, notification policies), plus the old deploy
  service token (`d9204def…`) and the old-zone Origin CA certificate. Old-ZONE objects are never touched.
- Delete every object version of the state backup (check bucket versioning first) and log the deletion on #12931.
- Flip ADR-329 to `accepted`; update `knowledge-base/operations/expenses.md`.
- Do NOT remove the TEMPORARY `ssl = "full"` config rule here (CTO L55 re-ruling, 2026-11-19). After the forget,
  `cloudflare_record.github_pages[...]` is absent from state, so the `dns.tf` `github_pages` -> `pages_apex` moved
  block is a no-op on the new zone; removing the rule, that moved block and the apex rollback tooling together is #7799.

## Recovery

**Default: fix forward.** After the flip the validations reject the old ids, so a failed phase is fixed with a new PR
and a re-rehearsal. Every phase is idempotent: a re-run forgets 0, ignores imports already in state and plans only the
remainder.

**Full revert (only if the migration is abandoned; CTO L59).** Each numbered act needs its own go.

1. `Operator-authorizes:` a `git revert` PR of PR1 (and PR2 if merged), merged with `[skip-web-platform-apply]`.
2. `Operator-authorizes:` restore each `<KEY>` from `<KEY>_PREV` with the Phase 2 pipe form. If the token `_PREV` keys
   were already deleted or the old tokens revoked, re-mint on the legacy account first.
3. `Operator-authorizes:` the fresh pull and its upload (a write to the state bucket). From `apps/web-platform/infra`
   on the operator's machine, with the Tier-B read/write pair exported as
   `infra-credential-tiers-8209.md` prescribes (never echoed) and `terraform init -input=false`, take a fresh pull of
   the CURRENT state and park it beside the backup:

   ```bash
   umask 077
   terraform state pull > "<scratchpad>/pre-revert-<utc>.tfstate"
   aws s3 cp "<scratchpad>/pre-revert-<utc>.tfstate" "s3://soleur-terraform-state/web-platform/backups/pre-revert-<utc>.tfstate" \
     --endpoint-url https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com > /dev/null
   aws s3 cp "s3://soleur-terraform-state/web-platform/backups/pre-cf-account-migration-<utc>.tfstate" "<scratchpad>/pre-migration.tfstate" \
     --endpoint-url https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com > /dev/null
   ```

4. `Agent:` lineage check; refuse to continue unless the lineages match:

   ```bash
   jq -r .lineage "<scratchpad>/pre-revert-<utc>.tfstate" "<scratchpad>/pre-migration.tfstate" | sort -u | wc -l   # 1
   jq -r .serial  "<scratchpad>/pre-revert-<utc>.tfstate" "<scratchpad>/pre-migration.tfstate"                     # live > backup
   ```

5. `Operator-authorizes:` (its own act) the forced push. A plain `state push` is refused because the backup's serial is
   lower than live after the forget and imports, and `-force` overwrites unlocked state (`use_lockfile = false`), so
   confirm first that no run of any workflow on this root is queued or in progress:

   ```bash
   terraform state push -force "<scratchpad>/pre-migration.tfstate"
   ```

6. `Agent:` shred both local copies, then plan read-only. Objects created in the new zone or account stay there,
   unmanaged; list them on #12931 for an owner decision. They do not affect the old zone, which was never mutated.
