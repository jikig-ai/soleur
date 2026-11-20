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
  - share revoke returns 502 purge-failed
---

# Runbook: migrate the web-platform root to the Soleur Cloudflare account

Decision: [ADR-329](../../architecture/decisions/ADR-329-cloudflare-zone-resources-live-on-the-soleur-account-r2-stays.md).
Plan: `knowledge-base/project/plans/archive/20261120-013510-2026-11-18-infra-cloudflare-migrate-terraform-to-soleur-account-plan.md`.
Rulings: `knowledge-base/project/specs/archive/20261120-013510-feat-one-shot-12931-cf-account-migration/decision-challenges.md`.
Incident: `knowledge-base/engineering/operations/post-mortems/soleur-ai-cloudflare-account-move-outage-2026-11-18-postmortem.md`.

## Conventions

- **Owners.** `Operator-authorizes:` marks a production-mutating or irreversible act. The agent runs it only after a
  typed go that names the exact command (`hr-menu-option-ack-not-prod-write-auth`); a menu pick is not a go. Each
  apply leg also stops at the reviewer-gated `web-platform-infra-apply` environment, and the operator's approval there
  is the production-write authorization. A standing delegation recorded on #12931 can cover the dispatch lines it names
  verbatim; anything it does not name needs its own go. `Agent:` marks a read-only step the agent runs unprompted.
- **The agent never approves its own environment gate.** The agent's `gh` identity is the owner's, and the owner is
  the `web-platform-infra-apply` reviewer, so the agent never calls the `pending_deployments` API or clicks approve:
  the person approves (ADR-241, "an agent never approves its own dispatch").
- **No SSH, anywhere.** Every step talks to the Cloudflare API, Doppler, GitHub Actions or Terraform state. Host health
  is read through the connector census, `verify-tunnel-ingress-origin.sh`, Better Stack and Sentry
  (`hr-no-ssh-fallback-in-runbooks`).
- **No secret on screen.** Every Doppler write pipes the value on stdin with `--silent` and stdout to `/dev/null`.
  Verification compares `sha256sum` of source and destination; non-secret ids print at most an 8-character prefix.
- **The stdin pipe form.** `doppler secrets get … --plain` ends its output with one newline that is not part of the
  value (measured), so every value read in a pipe goes through the one-newline strip
  `LC_ALL=C awk 'NR>1{printf "\n"} {printf "%s",$0}'`. A copy is
  `doppler secrets get <SRC> -p soleur -c <cfg> --plain | LC_ALL=C awk 'NR>1{printf "\n"} {printf "%s",$0}' | doppler secrets set <DST> -p soleur -c <cfg> --silent > /dev/null`,
  and its read-back compares the two keys' digests read the same way (`… --plain | <strip> | sha256sum`). The
  bootstrap's `plain_get` is the same strip.
  Never put a token in argv, a shell variable on screen, a Playwright snapshot or a screenshot.
- **Doppler writes go through the bootstrap.** Phase 2's revert copies, id flip, token swaps and branch-config copies
  are the stages of `bootstrap.sh` in the #12931 spec directory (CTO ruling D11), never retyped by hand. Set `B` from
  the repo root (archive-kb moves the directory; exactly one match, else stop):
  `B="$(git ls-files --full-name ':(top)*feat-one-shot-12931-cf-account-migration/bootstrap.sh')"; if [[ $(printf '%s\n' "$B" | grep -c .) -eq 1 ]]; then B="$(git rev-parse --show-toplevel)/$B"; printf 'SOLEUR_CFAM_BOOTSTRAP path=%s\n' "$B"; else printf 'SOLEUR_CFAM_BOOTSTRAP verdict=stop matches=%s\n' "$(printf '%s\n' "$B" | grep -c .)"; false; fi`.
  On `verdict=stop`, stop. A shell variable does not survive between agent tool calls, so substitute the printed
  absolute path literally wherever a later command says `$B`.
  Run it per the `soleur:operator-bootstrap` agent protocol: `--list`; `--stage <name>` prints the plan; relay its
  `SOLEUR_BOOTSTRAP_IMPACT` and `SOLEUR_BOOTSTRAP_ROLLBACK` lines verbatim; issue the printed apply command byte for
  byte as one simple command (it carries the script's absolute path; never respell it with `$B`, which the approval
  prompt does not recognise) and let the approval prompt carry the person's decision. A stage whose plan says `operations=0` is
  already done. `PRECONDITION_FAILED need=<stage>` means run that stage first.
- **Every dispatch arms a watch** (`hr-dispatch-async-must-arm-watch`). Find the run you started, then watch it:

  ```bash
  gh run list --workflow cf-account-migrate.yml --limit 3 --json databaseId,displayTitle,status,createdAt
  gh run watch <run-id> --exit-status
  ```

- **Before every dispatch**, dispatch the rehearsal first: it writes nothing, needs no reviewer, and refuses with
  `reason=run-in-flight`, naming the workflow, while any gated workflow (CTO ruling D1) has a run queued, waiting or
  in progress, because a queued run still executes later.
- **Merge freeze** (CTO ruling D5). From the PR1 merge until the Phase 3 step 6 reopen, no change under
  `apps/web-platform/infra/**` merges unless it belongs to #12931. An exception is the operator's priority call,
  recorded on #12931. Its push apply would fail closed at the predicate anyway, and Phase 3 step 6 would then apply it
  unreviewed inside the reopen.

Placeholders: `<PR1>` is #12932 (this runbook's PR); `<PR2>` is the #12931 follow-up that re-pins `RULESET_ID` and
adds the tunnel phase; `<phase>` is one of `redirects-dns`, `zone-rest`, `tunnel` (PR2); `<utc>` is `date -u +%Y%m%dT%H%M%SZ`;
`<run-id>` is the dispatched run; `B` is the bootstrap path set above.

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

Always rehearse first: `rehearsal=true` needs no reviewer and writes nothing; `rehearsal=false` waits for the
`web-platform-infra-apply` approval. What the job checks, and in which order, is the header of
`apps/web-platform/infra/scripts/cf-account-migrate-job.sh`. The refusals that need an operator action before a
re-dispatch:

- `zone-id-not-new` / `account-id-not-new`: Doppler still holds an old id; do the Phase 2 flip first.
- `token-not-new-zone`: a phase token did not answer `200` on the new zone or account (its `preflight=token` line
  names it); swap or re-mint it.
- `entrypoint-gate-refused`: a live phase entrypoint already holds rules; commit the printed import block first, and
  in the same reviewed PR flip that address's spec class from `create` to `import` in
  `tests/scripts/lib/cf-account-migrate-gate.sh` (every ruleset and list is `create` class, and the phase gate refuses
  an import of a create-class address, so the import block alone is refused one step later).

## Expected reds (do not "fix" these mid-migration)

| Red | Window | Why |
|---|---|---|
| Every gated job fails at the predicate, the last step of `infra-credentials`, with `verdict=cf-account-migration-in-progress` and an `::error::` naming this runbook, before any terraform runs. Gated means every workflow that loads `infra-credentials` and is not on the exempt list: `apply-web-platform-infra.yml`, `apply-deploy-pipeline-fix.yml`, `cf-lb-overlay.yml`, `key-rotate.yml`, `inngest-key-rotate.yml` and any new caller | PR1 merge → the PR2 tunnel phase apply | The predicate is false from merge: the tunnel is still on the legacy account and the phase addresses (`doppler_secret.cf_zone_id_prd` and the rest) are not in state. Exception: `web_host_replace` with `web_host_key=web-2` once the tunnel is in state on the new account. |
| `scheduled-terraform-drift.yml` red | PR1 merge → Phase 3 step 6 `manual-rerun` green | Exempt (plan only). Until the flip its plan fails on the old-id validations; after the flip the plan shows the forgotten and not-yet-adopted addresses. |
| `infra-validation.yml` plan red on a PR touching `apps/web-platform/infra/**` | PR1 merge → Phase 2 flip | Exempt (plan only); Doppler still holds the old ids and the validations fail closed. The merge freeze holds such PRs anyway. |
| `deploy-docs.yml` red (probe A/B mismatch) | PR1 merge → `zone-rest` apply | The merge itself triggers it (this PR edits `deploy-docs.yml` and `plugins/soleur/skills/**`). It publishes with the old-account `CLOUDFLARE_*_PAGES` secrets to the old project, while probe A now reads the new project. Cleared by `gh workflow run deploy-docs.yml --ref main` after `zone-rest` (Phase 2 step 3 verify). Hold a legal-copy docs change until then, or re-run it after. |
| Share revoke answers `502 purge-failed` (Sentry `feature:kb-share op:revoke-purge`) | Now → Phase 3 step 5 release redeploy | The running containers' env was frozen at `docker run` and still holds the old `CF_ZONE_ID` and `CF_API_TOKEN_PURGE`. The revoke itself is recorded; only the edge purge fails, and no edge copy exists to purge because `cache_shared_binaries` is created only after that redeploy (CTO ruling D3). |
| `cron-gh-pages-cert-reissue` reports `precondition_blocked` | Old DNS-edit token revoke → Phase 3 step 5 release redeploy | Its frozen container env still holds the revoked token. Fails closed by design. |
| Token-drift `DEAD credential` issue for a key this runbook just revoked | Revoke → the same act's key delete | A revoked value still sits in a scanned `CF_API_TOKEN*` key. The fix is the revoke recipe's step 4 (delete that key), never a rotation. |
| `inngest-public-sdk-url-preflight.sh` refuses `[ruleset-id]` (the public `sdk_url` replace dispatch) | Phase 2 flip → PR2 re-pin of `RULESET_ID` | It pins the legacy zone's config entrypoint id; after the flip it reads the new zone, whose entrypoint `redirects-dns` creates with a new id. Fails closed. Do not dispatch that replace in this window. |
| Connector census in `scheduled-inngest-health.yml` red (no tunnel, then 0 connectors) | Phase 2 flip → web-2 replace | The census looks the tunnel up by name under the new `CF_ACCOUNT_ID`. |
| `deploy.`/`ssh.`/`registry.` answer 530/1033 instead of Error 1000 | Tunnel apply → web-2 replace | The new tunnel exists with 0 connectors. Both states are down; nothing regresses. |
| First CI-SSH token sync warns on an empty secret | First tunnel-phase apply | A freshly synced secret reads empty on the first run; expect one re-dispatch. |

## Revoke recipe

Used by every revoke below. `<config>`/`<KEY>` is the Doppler key holding the value to kill. Revoking a user token
mutates no zone.

1. `Agent:` run the bootstrap's inventory stage (`bash "$B" --stage inventory`) and confirm no other config holds a
   copy of that value still in use (a `SOLEUR_CFAM_HOLDER` row for the same name outside `prd_terraform` is a stop:
   decide that holder first).
2. `Agent:` read the token id, never the value:

   ```bash
   doppler run -p soleur -c <config> -- bash -c 'printf "Authorization: Bearer %s\n" "$<KEY>" \
     | curl --disable --noproxy "*" -sS --max-time 30 --header @- https://api.cloudflare.com/client/v4/user/tokens/verify' \
     | jq -r '.result.id, .result.status'
   ```

3. `Operator-authorizes:` delete it in the operator's signed-in dashboard session, the same `browser_run_code_unsafe`
   session as the mints: the Node-side `page.evaluate` sends `DELETE /api/v4/user/tokens/<id>` with the session
   `x-atok` and returns only the HTTP status and `success`. A `403` or `404` means the session's user does not own
   that token: stop and report, never retry under another identity.
4. `Agent:` read back: re-run step 2. Expected: `.success` is `false` (the verify fails). Then
   `Operator-authorizes:` delete the key that held it, in the same act, so token-drift never grades a dead value:
   `doppler secrets delete <KEY> -p soleur -c <config> --yes > /dev/null`, and re-run the inventory stage
   (expected: no row for that key). Post the four results (id prefix, delete status, verify `false`, key gone) on
   #12931.

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
   LC_ALL=C awk 'NR>1{printf "\n"} {printf "%s",$0}' < "<scratchpad>/<key>.tok" \
     | doppler secrets set <KEY>_NEXT -p soleur -c prd_terraform --silent > /dev/null
   doppler secrets get <KEY>_NEXT -p soleur -c prd_terraform --plain | LC_ALL=C awk 'NR>1{printf "\n"} {printf "%s",$0}' | sha256sum
   LC_ALL=C awk 'NR>1{printf "\n"} {printf "%s",$0}' < "<scratchpad>/<key>.tok" | sha256sum
   ```

   Expected: the two digests are equal. Nothing later needs this digest: the bootstrap's swap compares `<KEY>` with
   `<KEY>_NEXT` itself before it deletes `_NEXT`.
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

Once 0a is minted and probed, revoke `CF_API_TOKEN_SOLEUR_ACCT` (the temporary token) with the revoke recipe, deleting
its key in every config the inventory stage lists for it.

### Write-probe each token before its phase (CTO L49)

`Agent:` run the scope tool's per-phase new-account profile before that phase's rehearsal, and post the verdict lines
on the PR thread:

```bash
S=plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh
bash "$S" --profile redirects-dns --staged   # before swap-0a
bash "$S" --profile zone-rest --staged       # before swap-0b
```

`--staged` reads each token from its `<KEY>_NEXT` key. After a swap the `_NEXT` keys are gone: drop the flag to probe
the live keys. The swap stages run the same staged probe themselves and refuse to swap unless it passes. What the tool
does:

- A write probe sends **one fixed invalid body literal that can never validate**, never `{"rules":[]}` (which would
  wipe a live entrypoint) and never a valid body. It never `DELETE`s.
- The old account and zone ids are refused before any request (exit 2); every write row targets the new zone or
  account.
- Each write row first sends the same request with a sibling token that must not hold the scope (`CF_API_TOKEN_PAGES`
  for the rulesets and DNS rows, `CF_API_TOKEN_RULESETS` for Pages, `CF_API_TOKEN_BOT_MANAGEMENT` and
  `CF_API_TOKEN_ZONE_SETTINGS` for each other) and requires `403`. Only then does the grant token's `400` count as
  authorized; a `400` on the control reads `inconclusive`.
- **Any `2xx` is a fatal abort**, followed immediately by a read-back of that entrypoint (`GET`, `success:true` and a
  parsed `.result` required): `probe=<phase> verdict=fatal-mutation`, exit 4. Post the read-back on #12931 and stop.
- Each profile includes one known-present control endpoint (the zone and account ruleset lists, the zone settings),
  so a degraded `200` or a `404` is never read as "empty".

`redirects-dns` covers `CF_API_TOKEN_RULESETS` on `http_request_dynamic_redirect`, `http_response_headers_transform`,
`http_config_settings`, `http_request_cache_settings`, `http_request_firewall_custom`, the account
`http_request_redirect` and `/accounts/<new>/rules/lists`, plus `CF_API_TOKEN` on DNS records and `CF_API_TOKEN_PAGES`
on Pages projects. It also prints a whole-list audit (each entrypoint present or absent). `zone-rest` covers
`CF_API_TOKEN_ZONE_SETTINGS` and `CF_API_TOKEN_BOT_MANAGEMENT`. `CF_API_TOKEN_DNS_EDIT` and `CF_API_TOKEN_PURGE` have
no write profile; swap-0b checks them active through `/user/tokens/verify` instead.

Expected per row: `authorized (PUT 400 after a 403 control)` (or `POST`/`PATCH`), and the run line
`probe=<phase> verdict=pass` with exit 0. `probe=<phase> verdict=denied` or `verdict=inconclusive` (exit 3) blocks that
phase's dispatch. An entrypoint the audit reports present is recorded by id and imported, never overwritten.

### Pre-checks on the new zone (read-only, after the 0b mint)

`Agent:`

```bash
doppler run -p soleur -c prd_terraform -- bash -c 'printf "Authorization: Bearer %s\n" "$CF_API_TOKEN_BOT_MANAGEMENT_NEXT" \
  | curl --disable --noproxy "*" -sS --max-time 30 --header @- https://api.cloudflare.com/client/v4/zones/951ce525552201ec6c696b24251abed7/bot_management' \
  | jq -r '.success, .result.fight_mode'
doppler run -p soleur -c prd_terraform -- bash -c 'printf "Authorization: Bearer %s\n" "$CF_API_TOKEN_ZONE_SETTINGS_NEXT" \
  | curl --disable --noproxy "*" -sS --max-time 30 --header @- https://api.cloudflare.com/client/v4/zones/951ce525552201ec6c696b24251abed7/settings/ssl' \
  | jq -r '.success, .result.value'
```

Expected: `true`, `false` (Bot Fight Mode off), and the zone SSL mode, recorded on #12931 (the `redirects-dns` apply
creates the `ssl = "strict"` rule for `app.soleur.ai`). If `fight_mode` is `true`, Bot Fight Mode challenges the
Stripe and GitHub webhooks and a WAF skip cannot bypass it: run `zone-rest` (which sets it `false`) in the same sitting
as `redirects-dns`.

### `CF_R2_ACCOUNT_ID` (before PR1 merges)

Done 2026-11-19 (verified `4d5ba6f0`). Re-check with:

```bash
doppler secrets get CF_R2_ACCOUNT_ID -p soleur -c prd_terraform --plain | cut -c1-8
```

Expected: `4d5ba6f0`. If it is absent, `Operator-authorizes:`
`printf '%s' 4d5ba6f096b2686fbdd404167dd4e125 | doppler secrets set CF_R2_ACCOUNT_ID -p soleur -c prd_terraform --silent > /dev/null`.

### 0c (withdrawn): early noindex

Not recommended since CTO ruling D2. A hand-made `http_response_headers_transform` entrypoint would hold rules, so
the migrate job's entrypoint gate refuses the `redirects-dns` create (`reason=entrypoint-gate-refused`) until an import
block for it lands in a PR, together with the flip of `cloudflare_ruleset.seo_response_headers` from `create` to
`import` class in the phase spec (`tests/scripts/lib/cf-account-migrate-gate.sh`; the phase gate refuses an import of a
create-class address). That costs a code PR to save hours at most; `redirects-dns` creates the same four rules from
`seo-rulesets.tf`. If the operator still wants it, the import block and the class flip are part of the same go.

## Phase 1 — merge PR1

`Operator-authorizes:` merge PR1. The merge queue squashes with the commit messages, so the kill switch rides in a
branch commit's message body: a line that is exactly `[skip-web-platform-apply]`, on its own (a PR-body line never
reaches `main`, `gh pr merge` cannot set the message, and a commit subject becomes a `* <subject>` line in the squash,
which the own-line match ignores). Before queueing, `Agent:` confirm it is in a body line of the commits the queue will
squash; anything but a number of `1` or more (a `0`, an empty output, a `gh` error) means stop:

```bash
gh pr view <PR1> --json commits --jq '[.commits[].messageBody | split("\n")[] | select(. == "[skip-web-platform-apply]")] | length'
```

On the merge SHA, `apply-web-platform-infra.yml` should show `preflight` success and `apply` skipped
(`gh run view <run-id> --json jobs --jq '.jobs[] | "\(.name) \(.conclusion)"'`). An `apply` that fails at the
predicate instead means the marker did not reach the squash: nothing was written (the predicate runs before any
terraform), but record it on #12931.

Merging mutates no Cloudflare zone, Terraform state or Doppler config. It does fire the routine release, docs and
plugin publish workflows as any plugin change does, and `deploy-docs.yml` publishes to the legacy-account Pages
project (Expected reds). Arm a watch on the push-triggered runs. The merge freeze starts now; run Phase 2 step 1 in
the same sitting.

## Phase 2 — flip, then restore redirects (`redirects-dns`, `zone-rest`)

### Step 1: the flip (bootstrap stages)

`Agent:` `bash "$B" --stage inventory`, and post its `SOLEUR_CFAM_HOLDER` rows (config and name only) on #12931.

`Operator-authorizes:` each stage's approval prompt, in this order:

1. `prev-0a`: revert copies `CF_ZONE_ID_PREV`, `CF_ACCOUNT_ID_PREV` and the three 0a `<KEY>_PREV`. It never
   overwrites an existing `_PREV`, and refuses if a key already holds a new value with no revert copy.
2. `flip-ids`: `CF_ZONE_ID` and `CF_ACCOUNT_ID` to the new ids, read back. It refuses unless both `_PREV` hold the
   legacy ids and `CF_R2_ACCOUNT_ID` holds the legacy account.
3. `swap-0a`: runs the `redirects-dns --staged` probe (any outcome but `verdict=pass` stops it before its first write),
   copies each `<KEY>_NEXT` to `<KEY>`, compares the two digests, and only then deletes `<KEY>_NEXT`. A mismatch keeps
   `_NEXT` and prints `SOLEUR_CFAM_SWAP_MISMATCH`.
4. `branch-copies-zone-id`: the new `CF_ZONE_ID` into every config of `apps/web-platform/infra/doppler-config-inventory.txt`
   that holds it (branch configs keep their own copies and do not inherit). An unreadable names listing refuses the
   stage; it is never read as "absent".

Each stage verifies its own writes by a separate read. `CF_API_TOKEN_PURGE`, `CF_API_TOKEN_DNS_EDIT` and
`CF_ACCESS_CLIENT_ID` are not copied here: the first two wait for the 0b swap (step 3), the pair for Phase 3 step 1.

The stages write `soleur/prd_terraform`, but the migrate job reads its values through
`doppler run --preserve-env` (`cf-account-migrate-job.sh` `TF_ENV`), so a name the `infra-credentials` loader already
exported from `soleur-infra-privileged` wins over `prd_terraform`. If a rehearsal's preflight still reports an old id
or token after the flip or a swap (`zone-id-not-new`, `account-id-not-new`, `token-not-new-zone`), check whether
`soleur-infra-privileged` holds that name (`doppler secrets --only-names --json -p soleur-infra-privileged -c prd | jq -r 'keys[]'`,
names only) before re-running any stage: re-flipping `prd_terraform` cannot fix it.

### Step 2: `redirects-dns` rehearsal and apply

Before rehearsing, note the 2026-11-19 zone hygiene: in the new zone, six TXT records created by the move's DNS scan
were rewritten unquoted and the comments on three records added during the incident were cleared, so every
`cloudflare_record` import plans as a pure no-op. If a rehearsal shows an import plus update on a TXT record or a
`comment` diff, that record has drifted again: re-read it and fix the record or the pinned id, never widen the gate.

`Operator-authorizes:` the rehearsal dispatch:

```bash
gh workflow run cf-account-migrate.yml --ref main -f migrate_phase=redirects-dns \
  -f confirm=MIGRATE-CF-redirects-dns -f rehearsal=true -f reason='#12931 redirects-dns rehearsal'
```

Expected in the run log:

- `cf-state-migrate … verdict=ok removed=N skipped=M` against the local rehearsal copy, with the remote serial
  unchanged and no new object under `web-platform/backups/`;
- `cf_account_migrate_gate: phase=redirects-dns verdict=PASS creates=<N> imports=<M> destroys=0`, where the gate
  derives N and M itself: on an empty new zone `creates=8` (7 rulesets and lists plus the
  `doppler_secret.cf_zone_id_prd` add, minus any entrypoint the probe found, which becomes an import) and the imports
  are 26 records, the Pages project and 2 Pages domains. The cache rule
  `cache_shared_binaries` is not in this phase (CTO ruling D3). Compare nothing by eye;
- the entrypoint gate passing on the new zone.

Any `cf_account_migrate_gate: … verdict=REFUSE` line (its `REFUSE <address> …` reason lines print above it), any
`cf-account-migrate phase=<phase> verdict=refuse reason=<code>` line or `verdict=abort` stops the phase. Read the
reason, fix forward in a PR, re-rehearse.

`Operator-authorizes:` the same dispatch with `rehearsal=false` (leave `expected_in_state_updates` empty: only a
fix-forward re-dispatch sets it, Halt `verify-failed` step 4), then the person approves the
`web-platform-infra-apply` environment. The real run writes the backup to
`web-platform/backups/pre-cf-account-migration-<utc>.tfstate` before its single `state rm`. `Agent:` record the key on
#12931 (it is disaster-recovery evidence, see Halt):

```bash
gh run view <run-id> --log | grep -oE 'cf-state-migrate backup=uploaded uri=[^ ]+' | head -1
gh issue comment 12931 --body "redirects-dns apply run <run-id>: <the uri line above>"
```

**Verify** (job step, then `Agent:` locally):

```bash
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' https://soleur.ai/pages/agents.html              # 301 https://soleur.ai/agents/
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' https://soleur.ai/pages/legal/privacy-policy.html # 301 https://soleur.ai/legal/privacy-policy/
curl -sSI https://www.soleur.ai/ | grep -iE '^(HTTP|location)'                                        # 301, location: https://soleur.ai/
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' https://soleur.ai/blog/2026-03-16-soleur-vs-anthropic-cowork/ # 301 https://soleur.ai/blog/soleur-vs-anthropic-cowork/
curl -sSI https://app.soleur.ai/ | grep -i '^x-robots-tag'                                            # x-robots-tag: noindex
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' https://app.soleur.ai/health               # 200 (a 3xx prints its Location: Halt step 1)
curl -sS -o /dev/null -w '%{http_code}\n' -A 'Mozilla/5.0 (compatible; GPTBot/1.2)' https://soleur.ai/  # 200
doppler run -p soleur -c prd_terraform -- bash -c 'printf "Authorization: Bearer %s\n" "$BETTERSTACK_API_TOKEN_READONLY" \
  | curl --disable --noproxy "*" -sS --max-time 30 --header @- "https://uptime.betterstack.com/api/v2/monitors?per_page=50"' \
  | jq -r '(if .pagination.next != null then "PAGINATED: read the next page" else empty end), (.data[] | select(.attributes.pronounceable_name | test("redirect"; "i")) | "\(.attributes.pronounceable_name) \(.attributes.status)")' \
  | tee /dev/stderr | grep -c ' up$'                                                                   # 4
```

Expected: the four redirect monitors listed, each `up`, and the count line `4` (a missing or renamed monitor shows
fewer; a `PAGINATED` line means the list did not fit one page of 50: read the next page before trusting the count). Then revoke the three superseded 0a tokens with the revoke recipe, one
go each, on `prd_terraform` `CF_API_TOKEN_PREV`, `CF_API_TOKEN_RULESETS_PREV` and `CF_API_TOKEN_PAGES_PREV` (the
recipe's step 4 deletes each `_PREV` key). `CF_ZONE_ID_PREV` and `CF_ACCOUNT_ID_PREV` may stay until cleanup; after
this apply they are never restored (Halt).

Then read the new zone's config entrypoint id (`plugins/soleur/scripts/cloudflare-readonly.sh config-entrypoint`, which
prints the id and never a token) and post it on #12931: PR2 must re-pin `RULESET_ID` in
`tests/scripts/lib/inngest-public-sdk-url-preflight.sh` to it, so the public `sdk_url` replace preflight passes again.

### Step 3: the 0b swap, then `zone-rest` rehearsal and apply

`Operator-authorizes:` each stage's approval prompt:

1. `prev-0b`: revert copies of the four 0b keys.
2. `swap-0b`: the `zone-rest --staged` probe, a `/user/tokens/verify` active check for `CF_API_TOKEN_DNS_EDIT_NEXT`
   and `CF_API_TOKEN_PURGE_NEXT`, then the same copy, compare and delete as swap-0a.
3. `branch-copies-tokens`: `CF_API_TOKEN_PURGE` and `CF_API_TOKEN_DNS_EDIT` from the live `prd_terraform` keys into
   every config that holds them, digest-verified. It refuses (`need=swap-0b`) while any
   `CF_API_TOKEN_PURGE_NEXT` or `CF_API_TOKEN_DNS_EDIT_NEXT` exists.

`Agent:` `bash "$B" --stage verify`. Expected: `SOLEUR_CFAM_VERIFY verdict=ok`; post its lines on #12931. Then revoke
the old DNS-edit token with the revoke recipe on `prd_terraform` `CF_API_TOKEN_DNS_EDIT_PREV` (it stops
`cron-gh-pages-cert-reissue` from writing DNS on the moved zone).

`Operator-authorizes:` the rehearsal, then the apply (`rehearsal=false`):

```bash
gh workflow run cf-account-migrate.yml --ref main -f migrate_phase=zone-rest \
  -f confirm=MIGRATE-CF-zone-rest -f rehearsal=true -f reason='#12931 zone-rest rehearsal'
```

Expected gate line: a `zone_settings_override` create that adopts the parity settings with no visible change, a
`bot_management` create, 2 `github_actions_secret` updates (`CLOUDFLARE_API_TOKEN_PAGES`, `CLOUDFLARE_ACCOUNT_ID_PAGES`)
and one `doppler_secret.cf_api_token_dns_edit` replace (`action_reason=replace_by_request`), so `destroys=1`: the gate
counts a replace's delete half, and that one is the only delete it lets through.

**Verify** (job step, then `Agent:` locally). The `zone-rest` apply runs the app-health, GPTBot and noindex probes after
it lands and refuses `reason=verify-failed applied=true failing=<list>` when one fails (Halt, `verify-failed`). Then run
the `x-robots-tag`, `/health` and GPTBot lines of the step 2 Verify block (same expected values), and:

```bash
gh api repos/jikig-ai/soleur/actions/secrets/CLOUDFLARE_API_TOKEN_PAGES --jq .updated_at   # later than the apply
```

`Operator-authorizes:` the docs dispatch, which republishes the production docs site:

```bash
gh workflow run deploy-docs.yml --ref main
```

`Agent:` then watch it:

```bash
gh run list --workflow deploy-docs.yml --limit 1 --json databaseId,createdAt
gh run watch <run-id> --exit-status
gh run view <run-id> --log | grep -E 'probe (A|B)'
```

Expected: the run is green, probe A (`https://soleur-docs-40x.pages.dev/version.txt`) passes (probe A is
`continue-on-error`, so read its step log, not the job conclusion), and probe B (apex `version.txt`) equals the
deployed sha. Then revoke the old `CF_API_TOKEN_ZONE_SETTINGS` and `CF_API_TOKEN_BOT_MANAGEMENT` with the revoke recipe
on their `_PREV` keys.

## Phase 3 — PR2: tunnel, Access and deploy hosts

1. **Deploy Access service token.** Mint `CF_API_TOKEN_ACCESS_MINT` (Access: Service Tokens:Edit only, 7-day expiry)
   with the Phase 0 hand-off. `Operator-authorizes:` run `apps/web-platform/infra/scripts/cf-access-deploy-token-mint.sh`.
   It writes `CF_ACCESS_CLIENT_ID`/`CF_ACCESS_CLIENT_SECRET` on stdin to `soleur-infra-privileged/prd` and
   `soleur/prd_terraform` (and to every other holder the inventory stage lists), and prints only the token UUID. That
   UUID goes into `local.deploy_service_token_ids` in PR2. Then revoke `CF_API_TOKEN_ACCESS_MINT` with the revoke
   recipe. For each `CF_ACCOUNT_ID` holder the inventory stage lists outside `prd_terraform`, decide whether it is
   read for R2 (leave it, or move the reader to `CF_R2_ACCOUNT_ID`) or for zone and Access (write the new id after this
   step): `apps/web-platform/server/inngest/functions/event-cf-token-expiry-check.ts` reads `prd` `CF_ACCOUNT_ID` to
   watch the `github-actions-deploy` token, which now lives on the new account. Record each decision on #12931.
2. `Operator-authorizes:` merge PR2, with the kill switch carried and checked exactly as in Phase 1 (a body line of a
   branch commit, confirmed with the same `gh pr view <PR2> --json commits` count before queueing).
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

   **Then re-mint the Origin CA certificate from the new zone**, before the release redeploy, with
   `CF_API_TOKEN_ORIGIN_CA` re-scoped to the new zone: `gh workflow run mint-origin-ca-cert.yml --ref main -f mode=plan`,
   then `Operator-authorizes:` the deliberate-rotation apply in `origin-tls-mint.md` §3.
5. **Verify:**
   - the next connector census in `scheduled-inngest-health.yml` (verdict token from `scripts/tunnel-connector-census.sh`)
     reports exactly 1 connector on the new tunnel;
   - `apps/web-platform/infra/scripts/verify-tunnel-ingress-origin.sh` passes (new `CF_ACCOUNT_ID`, new tunnel id,
     `deploy-status` 200 through `deploy.` with the new Access pair);
   - a CI SSH bridge round-trip and a `registry.` push canary succeed;
   - `Operator-authorizes:` `gh workflow run web-platform-release.yml --ref main -f bump_type=patch`; the redeploy
     loads the new runtime `CF_ZONE_ID`, `CF_API_TOKEN_PURGE`, `CF_API_TOKEN_DNS_EDIT` and the new certificate;
     `curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' https://app.soleur.ai/health` returns `200` under
     `ssl=strict`;
   - a share revoke now answers `200` (the 502 expected red clears). Then revoke the old `CF_API_TOKEN_PURGE` with the
     revoke recipe on `prd_terraform` `CF_API_TOKEN_PURGE_PREV`.
6. **Reopen the routine path** (CTO ruling D5). `Agent:` first, in this order, and post all three on #12931:

   ```bash
   git fetch origin main
   git log --oneline <PR1-merge-sha>..origin/main -- apps/web-platform/infra
   gh run list --workflow scheduled-terraform-drift.yml --limit 1 --json databaseId,conclusion,createdAt
   gh run view <drift-run-id> --log | grep -E 'apps/web-platform/infra|Plan: |No changes'
   ```

   Expected: the log lists only #12931 commits (anything else is a merge-freeze exception the owner must review), and
   the latest drift plan of the web-platform root shows only the migration remainder plus one
   `cloudflare_ruleset.cache_shared_binaries` create. The owner then reviews both outputs and comments on #12931;
   `Agent:` reads that comment (`gh issue view 12931 --comments`) before the dispatch. `Operator-authorizes:`

   ```bash
   gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=manual-rerun -f reason='#12931 reopen'
   ```

   The predicate is now true. Expected: green end to end, and the plan in its log carries exactly one
   `cloudflare_ruleset.cache_shared_binaries` create (the routine apply's existing `-target`, created now that the
   containers purge with the new token, CTO ruling D3). The `scheduled-terraform-drift.yml` red clears on its next
   run.
7. Before 2026-12-26, record on #12931 that the `api.soleur.ai` `_acme-challenge` renewal works from the new zone.

## Phase 4 — close the incident

`Agent:` read every Better Stack monitor (the endpoint is paginated: follow `.pagination.next` until it is `null`):

```bash
doppler run -p soleur -c prd_terraform -- bash -c 'printf "Authorization: Bearer %s\n" "$BETTERSTACK_API_TOKEN_READONLY" \
  | curl --disable --noproxy "*" -sS --max-time 30 --header @- "https://uptime.betterstack.com/api/v2/monitors?per_page=50"' \
  | jq -r '.pagination.next, (.data[] | select(.attributes.url | test("soleur\\.ai")) | "\(.attributes.pronounceable_name) \(.attributes.status)")'
```

Expected: `null`, then all 9 soleur.ai/app monitors `up`. Only then, and with Phase 3 step 5 holding, flip the
post-mortem to `status: resolved` (frontmatter and `## Status` line), add the recovery timestamps and set the #12931
action-item row to `resolved`. Never on a projection. The Search Console check for indexed `app.soleur.ai` token URLs
(`/shared/<token>`, `/invite/<token>`, `/api/shared/<token>`) is an operator row: the operator records the result on
the PR thread, and its comment is the read-back.

## Phase 5 — cleanup PR (after Phase 3 verification)

- Delete the migration machinery (imports file, state-forget script, predicate and its call sites, the
  `cf_migration_*` variables, `cf-account-migrate.yml` with its job script, the gate and the bootstrap with its suite).
  Keep `cf-access-deploy-token-mint.sh` and the `cf-token-scope.sh` profiles.
- Revoke `CF_API_TOKEN_SOLEUR_ACCT` (if not already) and any superseded old-zone token with the revoke recipe.
- `Operator-authorizes:` delete the old tunnel `fc4509ed…` in the legacy account once web-2's replace has dropped its
  connections. Read-back: the same account's tunnel list by that id shows it deleted.
- `Operator-authorizes:` delete, one go each and by name, the legacy-account objects the forget left behind, listed from
  the pre-migration backup filtered to old-account non-R2 entries (LB monitor and pool, `ci_ssh` and `registry_push`
  service tokens, Access apps and policies, lists, the account ruleset, notification policies), plus the old deploy
  service token (`d9204def…`) and the old-zone Origin CA certificate. Old-ZONE objects are never touched. Read-back per
  object: a `GET` of its id answers `404` (or the list no longer names it); post each on #12931.
- Delete every `web-platform/backups/pre-cf-account-migration-*` object, every version (check bucket versioning
  first), and log the deletion and an empty re-list of that prefix on #12931.
- Flip ADR-329 to `accepted`; update `knowledge-base/operations/expenses.md`.
- Do NOT remove the TEMPORARY `ssl = "full"` config rule here (CTO L55 re-ruling, 2026-11-19). After the forget,
  `cloudflare_record.github_pages[...]` is absent from state, so the `dns.tf` `github_pages` -> `pages_apex` moved
  block is a no-op on the new zone; removing the rule, that moved block and the apex rollback tooling together is #7799.

## Halt

**Default: stop at the last verified phase and fix forward** (CTO ruling D4). Do not start the next phase (the one
exception is a `gptbot=>403` from Bot Fight Mode, under `verify-failed` below). Read the refusal, fix in a PR,
re-rehearse, re-dispatch. A re-dispatch after a committed forget is safe (CTO ruling D10): when only R2 and
non-Cloudflare entries remain, state-migrate prints `cf-state-migrate verdict=ok removed=0` and takes no backup (a
backup is taken only when something will be removed); the plan then skips imports already in state and covers only
the remainder. An apply that fails after the forget says the same in its refusal line: fix forward and re-dispatch,
never restore from the backup.

The off-by-default flags `cf_load_balancing_enabled`, `cf_zone_plan_pro`, `cf_zone_dnssec_enabled` and
`cf_migration_import_app` are locked to `false` by `variables.tf` validations (CTO ruling D9), and `cf_r2_account_id`
is pinned to the legacy account. Never fix a red by overriding one: turning a flag on is a reviewed PR that deletes its
validation (Load Balancing #12983, DNSSEC #12982).

- **Is the forget committed?** It is a fact of the whole migration, never of one run's log: a re-dispatch after a
  committed forget prints `removed=0` and no `backup=uploaded`, so this run's log alone never answers it. The forget is
  committed once ANY `rehearsal=false` `redirects-dns` run printed `cf-state-migrate backup=uploaded`, even if its gate
  then refused (CTO ruling 2026-11-20). `Agent:` read the cross-run record:

  ```bash
  gh issue view 12931 --json comments --jq '[.comments[].body | select(test("cf-state-migrate backup=uploaded uri="))] | length'
  for r in $(gh run list --workflow cf-account-migrate.yml --limit 100 --json databaseId --jq '.[].databaseId'); do
    gh run view "$r" --log 2>/dev/null | grep -m1 -oE 'cf-state-migrate backup=uploaded uri=[^ ]+' | sed "s/^/run=$r /"
  done
  ```

  Committed: the first command prints `1` or more (the backup-uri comment of Phase 2 step 2), or the loop prints a
  `run=` line, or any `pre-cf-account-migration-*` object exists under `web-platform/backups/` in the state bucket.
  Not committed: the first command prints `0` and the loop prints no line. Anything else (a `gh` error, no number) is
  not an answer: stop for an owner decision.
  The job's refusal field says the same for one run only, and only a `redirects-dns` `rehearsal=false` refusal carries
  it (a rehearsal, `zone-rest` or `tunnel` refusal carries none: use the record above). `forget=committed`: this run's
  forget finished ok or uploaded its backup, so the forget is committed. `forget=unknown` (on `state-migrate-failed`
  only): this run printed no `backup=uploaded`, so this run forgot nothing; read its
  `cf-state-migrate verdict=abort reason=<code>` line for the cause, and take whether an earlier run committed the
  forget from the record above.
- **Before the forget is committed** (the record above says not committed), the flip may be undone. The revert
  restores `prd_terraform` only: branch configs the `branch-copies-*` stages wrote keep the new values (never write an
  old id or token back into them; record which ones hold new values on #12931). `Operator-authorizes:`, each with the
  stdin pipe form:
  1. for each token key whose swap ran (no `<KEY>_NEXT` exists and `<KEY>` differs from `<KEY>_PREV` by digest),
     first copy `<KEY>` to `<KEY>_NEXT` and compare the two digests, so the new token is kept for re-entry (the mint
     files are shredded, and the swap stage needs `_NEXT`);
  2. copy `CF_ZONE_ID_PREV` and `CF_ACCOUNT_ID_PREV` back over `CF_ZONE_ID` and `CF_ACCOUNT_ID`, and read each back
     (`cut -c1-8`);
  3. copy each token `<KEY>_PREV` back over `<KEY>`, and compare the two digests.

  That leaves the root closed, not reopened: the validations reject the old ids, so every plan of the root fails, and
  state was never touched.
- **Once the forget is committed**: no id restore, no restore of state from the backup and no `git revert` of PR1.
  Each of those would point Terraform at the moved zone, which must never be mutated, or re-open routine applies
  against state that no longer holds the zone's resources. Fix forward only.
- **A stop after `applying=true`** (`apply-failed`, or a cancelled run whose log shows `mode=apply applying=true`,
  with or without `applied=true`): rules may have landed in this run. `Agent:` run that phase's local Verify block
  first; on any failure follow the `verify-failed` steps below (a `redirects-dns` `apply-failed` refusal also carries
  its own best-effort `verify=ok` or `failing=` field). Then fix the cause forward and re-dispatch.
- **A stop before `applying=true`** (`gate-refused`, `entrypoint-gate-refused`, `state-migrate-failed`, any other
  `verdict=refuse` line, or a cancelled run with no `mode=apply applying=true`): this run applied nothing, so there is
  nothing to verify and no edited value to carry. Fix the refusal's cause (a reviewed PR when it is in code; nothing
  for a timeout), re-rehearse, re-dispatch. Whether the revert above is still allowed is the committed test, not this
  refusal.
- **The apply run was cancelled** (timeout or by hand; the ops email says "did not complete" and the log holds no
  `verdict=refuse` line). `Agent:` read the conclusion and the markers:

  ```bash
  gh run view <run-id> --json conclusion --jq .conclusion
  gh run view <run-id> --log | grep -oE 'cf-account-migrate inflight=none|cf-state-migrate backup=uploaded|mode=apply (applying|applied)=true|verdict=refuse reason=[a-z-]+' | sort -u
  ```

  Read an absence only when the output holds the job's start line `cf-account-migrate inflight=none` or a `reason=`
  line; with neither, the log does not show the job ran its checks: stop for an owner decision. Then, in this order:
  1. `mode=apply applying=true` is present: a stop after `applying=true` (above), so Verify first.
  2. No `mode=apply applying=true`: a stop before `applying=true` (above). Whether the forget is committed is the
     committed test, never this log's `backup=uploaded` alone.
- **`reason=verify-failed applied=true`** (a `redirects-dns` or `zone-rest` apply landed and a post-apply probe
  failed; the `failing=` list names each item with what came back, `<item>=><code>+<location>`). CTO ruling
  2026-11-20:
  1. Act on each failing item by its code, after either phase. If `app-health` is in `failing=` (the product is down
     for every user):
     - `app-health=>525` or `=>526`: `Operator-authorizes:` (owner only, as `origin-tls-strict-flip.md` §Break-glass)
       one dashboard edit on the NEW zone `951ce525…` only: Rules, Configuration Rules (phase `http_config_settings`),
       the rule with ref `dcb85b75bc3c4f4aa2a8c13a080bf854`, SSL `Strict` to `Full`. Not the zone-wide SSL/TLS
       setting. The CLO's 2026-11-13 ruling requires the legal wording to change the same day.
     - `app-health=>3xx`: `Operator-authorizes:` (owner only) read the `Location` the item carries. If it equals a
       Terraform redirect target (`seo-rulesets.tf`, or an item of `cloudflare_list.legal_redirects` in
       `seo-bulk-redirects.tf`), remove only that one rule or list item, on the NEW zone or account. If no Cloudflare
       target matches, it is an origin redirect: no dashboard edit; stop for an owner decision.
     - `app-health=>000` or any other code: no dashboard edit. `Agent:` re-run the local Verify block and stop for an
       owner decision.

     `gptbot=>403` (crawlers blocked): no dashboard edit. After `redirects-dns` with Phase 0's pre-check recorded
     `fight_mode` `true`, it is Bot Fight Mode, which only `zone-rest` turns off: this is the one next-phase start
     the Halt allows. `Operator-authorizes:` run Step 3 now (its stages, verify, rehearsal and apply), then re-run the
     local Verify block. After `zone-rest`, or with `fight_mode` recorded `false`, it is a `zone-rest` value
     (`cloudflare_bot_management.soleur_ai`, `cloudflare_zone_settings_override.soleur_ai`) or the
     `cloudflare_ruleset.allowlist_ai_crawlers` rule: fix forward in a PR (steps 3 and 4), never in the dashboard. Any
     other `gptbot=>` code, and any other item (a redirect pair, `app-noindex`): no dashboard edit; fix forward
     (steps 3 and 4). `Agent:` re-run the local Verify block after any edit. Never edit the old zone.
  2. After a 525/526 window, redeliver the window's failed GitHub App webhook deliveries per
     `origin-tls-strict-flip.md` §"After any 525/526 window" (GitHub never retries them). The window runs from the
     apply job's start (rules land mid-apply) to the first passing local Verify after the edit. `Agent:` list the
     non-2xx deliveries inside it; `Operator-authorizes:` the redelivery (`POST …/attempts` replays events into the app).
  3. A fix-forward PR under #12931 (the merge freeze allows it; its push-apply red is expected). It carries the
     edited value in code (for the ssl rule, the edits `origin-tls-strict-flip.md` §Rollback lists for a forward PR).
     The phase to rehearse and re-dispatch is `redirects-dns` when step 1 edited a rule (every address step 1 can edit
     is in its spec, whichever phase's verify failed), else the phase whose code the PR fixed.
  4. Rehearse that phase. `Agent:` read the gate's lines from the rehearsal log:
     `gh run view <run-id> --log | grep -E 'cf_account_migrate_gate: (in-state-update |phase=[a-z-]+ verdict=PASS)'`.
     Trust an absence only when the output holds exactly one `cf_account_migrate_gate: phase=<phase> verdict=PASS`
     line (none: the gate did not pass or the log is incomplete; more than one: not one rehearsal; either way stop).
     The address step 1 edited must NOT be among the `in-state-update` lines: `cloudflare_ruleset.seo_config_settings`
     for the 525/526 rule, `cloudflare_ruleset.seo_page_redirects` for a removed `seo-rulesets.tf` rule, or
     `cloudflare_list.legal_redirects` for a removed list item. An update to it means the PR does not carry the
     working value and would undo the edit, so stop. A fix to a sibling rule in the same ruleset goes in its own PR
     after this one, so the check stays readable. Then `Operator-authorizes:` the re-dispatch with `rehearsal=false`
     and `-f expected_in_state_updates='<address> …'`: the `in-state-update` addresses the rehearsal printed,
     space-separated, empty when it printed none. The apply refuses before `applying=true` when the set its own gate
     admits differs (a sibling PR merged, or a second dashboard edit made, after the rehearsal), so the set checked
     here is the set applied. The job's verify runs again.
     For a create-class address (every ruleset and list of the phase, and `doppler_secret.cf_zone_id_prd`), the gate
     accepts an in-state `["update"]` only for a Cloudflare object whose `before` carries the NEW zone or account id,
     or for the Doppler zone-id secret when its planned value equals the new zone id. A `mutable` member (the two
     `zone-rest` `github_actions_secret` Pages secrets) accepts an update with no such condition. A fix that plans as
     a replace (a ruleset `phase` or `kind` change, say) is refused: widening the phase spec is a reviewed gate diff in
     `tests/scripts/lib/cf-account-migrate-gate.sh`.
- **A `zone-rest` apply failed between the halves of the `doppler_secret.cf_api_token_dns_edit` replace** (a
  delete-then-create). `Agent:` read the state of it:
  `gh run view <run-id> --log | grep -oE 'doppler_secret\.cf_api_token_dns_edit: (Destruction|Creation) complete'`
  prints `Destruction complete` alone, and
  `doppler secrets --only-names --json -p soleur -c prd | jq -r 'has("CF_API_TOKEN_DNS_EDIT")'` prints `false`
  (names only). The address is then absent from state and `prd` `CF_API_TOKEN_DNS_EDIT` is gone. A re-dispatch plans
  `["create"]` for it, which the gate refuses (the address is `replace` class, and its physical-id check needs a
  `before`). Path: a reviewed PR to `tests/scripts/lib/cf-account-migrate-gate.sh` that admits that one `["create"]`,
  then re-rehearse and re-dispatch `zone-rest`. Never write the token into `prd` by hand.
- **A revert copy is not sound** (a `prev-*` or `swap-*` stage says one of `<KEY>` / `<KEY>_PREV` is not the old
  token). Copy neither way. Both an old and a new token verify active, so status alone cannot tell them apart.
  `Agent:` read each of the two keys with that key's own read (the one the bootstrap uses; a zone read alone fails for
  an account-scoped token), once on the NEW resource and once on the OLD:

  | `<KEY>` | NEW read | OLD read |
  |---|---|---|
  | `CF_API_TOKEN` | `zones/951ce525552201ec6c696b24251abed7/dns_records?per_page=1` | `zones/5af02a2f394e9ba6e0ea23c381a26b67/dns_records?per_page=1` |
  | `CF_API_TOKEN_RULESETS` | `zones/951ce525552201ec6c696b24251abed7/rulesets` | `zones/5af02a2f394e9ba6e0ea23c381a26b67/rulesets` |
  | `CF_API_TOKEN_PAGES` | `accounts/66d4f93f7397f196544e9fe84c3557c2/pages/projects` | `accounts/4d5ba6f096b2686fbdd404167dd4e125/pages/projects` |
  | `CF_API_TOKEN_ZONE_SETTINGS` | `zones/951ce525552201ec6c696b24251abed7/settings` | `zones/5af02a2f394e9ba6e0ea23c381a26b67/settings` |
  | `CF_API_TOKEN_BOT_MANAGEMENT` | `zones/951ce525552201ec6c696b24251abed7/bot_management` | `zones/5af02a2f394e9ba6e0ea23c381a26b67/bot_management` |
  | `CF_API_TOKEN_DNS_EDIT` | `zones/951ce525552201ec6c696b24251abed7/dns_records?per_page=1` | `zones/5af02a2f394e9ba6e0ea23c381a26b67/dns_records?per_page=1` |
  | `CF_API_TOKEN_PURGE` | `zones/951ce525552201ec6c696b24251abed7` | `zones/5af02a2f394e9ba6e0ea23c381a26b67` |

  ```bash
  doppler run -p soleur -c prd_terraform -- bash -c 'printf "Authorization: Bearer %s\n" "$<KEY_OR_PREV>" \
    | curl --disable --noproxy "*" -sS --max-time 30 --header @- "https://api.cloudflare.com/client/v4/<read>"' \
    | jq -r '.success'
  ```

  Each read prints `true` or `false`; anything else (no output, a `curl` or `jq` error) is a transport failure. A key
  reads as NEW when its NEW read prints `true` AND its OLD read prints `false`. If exactly one of the two keys reads as
  NEW, the other is the old token, provided it verifies active (revoke recipe step 2). If both keys read as NEW, or
  neither does, or any read fails in transport, stop for an owner decision: never pick one.
  `Operator-authorizes:` if `<KEY>_PREV` is the one that reads as NEW, delete it and re-run the prev stage, which
  copies `<KEY>` afresh. If `<KEY>` reads as NEW, first read its token id (revoke recipe step 2) and post it on #12931
  so that stray token can be revoked, then copy `<KEY>_PREV` over it with the stdin pipe form, read it back, and re-run
  the swap.
- **Bootstrap markers.** Each failure marker `bootstrap.sh` prints, and what to do. Nothing on this list is fixed by
  re-minting unless it says so.
  - `SOLEUR_CFAM_TOKEN_MALFORMED name=<KEY>_NEXT`: the staged value has a byte outside the token class (often a stored
    trailing newline); no network call was made. Re-stage `<KEY>_NEXT` from the mint file with Phase 0 step 2's strip
    form.
  - `SOLEUR_CFAM_TOKEN_NOT_ACTIVE`: the staged token's `/user/tokens/verify` did not say active: re-mint (Phase 0).
  - `SOLEUR_CFAM_TOKEN_UNREACHABLE`: a token read failed in transport (a `curl` error or timeout), which says nothing
    about the token: re-run the stage. Never re-mint on this marker.
  - `SOLEUR_CFAM_RUN_IN_FLIGHT`: a writing stage refused because a `cf-account-migrate.yml` run is queued or in
    progress (or `gh` could not list the runs). Wait for that run to finish, read its verdict line, then re-run the
    stage.
  - `SOLEUR_CFAM_PROBE profile=<phase> verdict=not-pass`: the staged scope probe did not pass, so the swap wrote
    nothing. Read the `probe=<phase> verdict=…` line it relayed: `denied` means re-mint that key with the plan's
    permission groups; `inconclusive` means re-run the stage; `fatal-mutation` is the write-probe stop (post the
    read-back on #12931 and stop).
  - `SOLEUR_CFAM_COPY_MISMATCH`: the stage stopped before any delete; copy `<KEY>_PREV` over `<KEY>` with the stdin
    pipe form, read it back, and re-run.
  - `SOLEUR_CFAM_SWAP_MISMATCH name=<KEY> kept=<KEY>_NEXT`: the copy read back equal but a re-read before the delete
    did not, so `_NEXT` was kept. Re-run the swap stage: its plan deletes a `_NEXT` that now equals `<KEY>`, copies
    again over a `<KEY>` that still equals `_PREV`, and refuses anything else (then follow "A revert copy is not
    sound").
  - `SOLEUR_CFAM_DELETE_NOT_CONFIRMED`: re-run the stage, which plans only the delete.
  - `SOLEUR_CFAM_ID_READBACK_FAILED target=<cfg>/<name>`: an id write returned ok but its read-back differs, so the key
    may hold the new id, the old one or neither. `Agent:` read its prefix (ids are not secrets:
    `doppler secrets get <name> -p soleur -c <cfg> --plain | cut -c1-8`) and re-run the stage: its plan skips a key that
    already holds the new id and writes one that holds the legacy id. A key holding neither is refused: stop for an
    owner decision.
  - `SOLEUR_CFAM_UNREADABLE config=<cfg>`: that config's names listing could not be read (Doppler auth or network), so
    nothing in it was read as absent. Re-run; if it repeats, check `doppler me` and stop for an owner decision.
  - `SOLEUR_CFAM_VERIFY check=<x> verdict=fail` (the closing `SOLEUR_CFAM_VERIFY verdict=fail` follows the per-check
    lines): act per check. `<cfg>/CF_ZONE_ID=new` or `CF_ACCOUNT_ID=new`: run `flip-ids` (for `prd_terraform`) or
    `branch-copies-zone-id` (a branch config). `CF_R2_ACCOUNT_ID=legacy`: the `CF_R2_ACCOUNT_ID` section above.
    `<KEY>_NEXT=absent` or `<KEY>=swapped`: that key's swap stage has not completed: run it. `<KEY>=swapped-prev-revoked`:
    read `<KEY>` with its NEW read from the table above; `true` means the verify's own read failed (re-run verify);
    `false` means the live key is not a new-account token and its revert copy is gone: stop for an owner decision.
    `<cfg>/<KEY>=matches-prd_terraform`: run `branch-copies-tokens`; if it refuses with `need=verify`, stop for an
    owner decision. `<cfg>=readable` or `inventory=readable`: as `SOLEUR_CFAM_UNREADABLE`.
- The backup object is disaster-recovery evidence only. It is never pushed back as state; Phase 5 deletes every
  `pre-cf-account-migration-*` object.
- If the migration is abandoned outright, stop at the last verified phase, keep the merge freeze, and record the
  state on #12931 for an owner decision. The old zone was never mutated, and objects created in the new zone or
  account stay there.
