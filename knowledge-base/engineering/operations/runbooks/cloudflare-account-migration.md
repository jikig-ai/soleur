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
  The exception: the full service-token UUIDs and DNS record ids that the job, the pre-delete and the mint print are
  not secret, and Phase 3 commits them in full.
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
  recorded on #12931. Until the tunnel apply, its push apply fails closed at the predicate, and Phase 3 step 6 would
  then apply it unreviewed inside the reopen. The predicate turns true when the tunnel apply lands, not at the reopen.
  So from the tunnel apply until the Phase 3 step 5 release redeploy, nothing that triggers an apply of
  `apps/web-platform/infra` merges, with no exception: a routine apply would create
  `cloudflare_ruleset.cache_shared_binaries` while the running containers still fail their purge (CTO ruling D3). If
  one must, the owner first accepts in writing on #12931 that a revoked share can then be served from the edge for up
  to the 60 s `s-maxage` cap (`cache.tf`).

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
- `token-unreachable`: a token probe got no verdict: it failed in transport (`http=000 e=<curl rc>`) or the API
  answered `429` or a `5xx` (`http=<code>`), so nothing is known about the token; re-dispatch the rehearsal, and never
  re-mint on this reason alone.
- `bad-expected-in-state-updates`: the `expected_in_state_updates` input holds an entry that is not a Terraform
  address; fix the input and re-dispatch.
- `in-state-updates-unexpected`: the gate admitted a different set of in-state updates than the input names (the
  log prints `admitted=` and `expected=`). Copy the rehearsal's `cf-account-migrate in-state-updates admitted=`
  value only after checking each address against Halt `verify-failed` step 4; never widen the input to make it pass.
- `entrypoint-gate-refused`: a live phase entrypoint already holds rules; commit the printed import block first, and
  in the same reviewed PR flip that address's spec class from `create` to `import` in
  `tests/scripts/lib/cf-account-migrate-gate.sh` (every ruleset and list is `create` class, and the phase gate refuses
  an import of a create-class address, so the import block alone is refused one step later).
- `predelete-refused` (tunnel): the pre-delete refused after every gate passed, so nothing was applied. Its own line
  `cf-tunnel-host-predelete verdict=refuse reason=<inner>` (or `verdict=partial`) names the cause:
  - `pins-missing`: the script does not pin six ids. Commit them (Phase 3 step 2) in a reviewed PR.
  - `record-unreadable`: a read got no verdict, or a 404 without Cloudflare code 81044. Nothing was deleted; re-run.
  - `record-mismatch`, `still-present` or `foreign-record` (a record on `deploy.`/`ssh.`/`registry.` that is neither
    pinned nor a proxied CNAME to `*.cfargotunnel.com`): read the named record and stop. Fix it in a reviewed change.
  - `verdict=partial deleted=<n>`: some records are already deleted. Re-dispatch; the pre-delete counts them gone.
  - `no-token`: `CF_API_TOKEN` did not reach the script; nothing was read. Check Doppler and re-dispatch.
- `token-scope-missing`: `CF_API_TOKEN` (or a staged `CF_API_TOKEN_NEXT`, which the probe reads first) lacks a Tunnel,
  Access, service-token or notification-policy read on the new account; re-mint it with the scope.
- `deploy-token-refused` (tunnel): the deploy policy's service token failed its live read. The `deploy-token` line's
  `detail=` names why: `http-404` means the committed id is wrong (re-read the mint's UUID); `name-differs` means it is
  another token; `expiry-out-of-window` means it has under 8016 h (334 days) left, so re-mint it and commit the new id
  in a new PR. The tunnel rehearsal and apply must both run within 31 days of the mint.
- `doppler-write-token-missing` (tunnel): `DOPPLER_TOKEN_WRITE` is not set, so the post-apply CI-SSH sync could not run.
  It refuses before the pre-delete, so nothing was deleted or applied.
- `ci-ssh-sync-failed` (tunnel, `applied=true`): the apply and live probes passed but the CI-SSH pair did not reach
  `prd_terraform` (`cause=output-empty`, `write-refused` or `digest-mismatch`); re-dispatch the same phase.

Every tunnel refusal after the pre-delete carries `predelete=done`: the six A records are gone.

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
| Connector census in `scheduled-inngest-health.yml` red (no tunnel, then 0 connectors) | PR2 merge → web-2 replace | The census looks the tunnel up by name on the Soleur account, a literal in `scripts/tunnel-connector-census.sh` (`CF_TUNNEL_ACCOUNT_ID`), not Doppler's `CF_ACCOUNT_ID`. |
| Inngest liveness reads `probe_unavailable` and never restarts; `restart-inngest-server.yml` fails | Zone move → Phase 3 step 5 proves `deploy.` | Both call `deploy.soleur.ai` (`/hooks/inngest-liveness`, `/hooks/deploy`), which has no working route. An Inngest outage in this window is neither detected nor restarted. The tunnel-avoiding recovery is the operator-authorized Hetzner API act named below this table. |
| `deploy.`/`ssh.`/`registry.` answer 530/1033 instead of Error 1000 | Tunnel apply → web-2 replace | The new tunnel exists with 0 connectors. Both states are down; nothing regresses. |
| The first CI-SSH sync may refuse `ci-ssh-sync-failed applied=true` | First tunnel-phase apply | The sync refuses rather than warns (see its refusal under **The dispatch**). Re-dispatch the phase: every created address plans no-op and the sync runs again. |
| The predicate prints `unnormalized <addr>` | An apply stopped before reaching `<addr>` → its re-dispatch | That record is in state with no `content`, so the routine apply must not take it over. `unnormalized <addr>`: rehearse, then re-dispatch the phase whose spec lists `<addr>`. `cf-account-migrate.yml` is exempt from the predicate, so the red never blocks this fix. |

<!-- lint-infra-ignore start: deferred orchestrator prose, not a step in this runbook's flow. It names the one recovery that works while `deploy.` has no route, gated on operator authorization (hr-menu-option-ack-not-prod-write-auth); the agent surfaces it, the operator says go. -->
The recovery that avoids the tunnel while `deploy.` is unrouted is `Operator-authorizes:` a Hetzner API reboot of the Inngest host (`hcloud_server.inngest`, `POST /v1/servers/<id>/actions/reboot`); the `web-host-reboot.yml` workflow is retired.
<!-- lint-infra-ignore end -->

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
     | jq -r '"success=\(.success) id=\((.result.id // "none")[0:8]) status=\(.result.status // "none")"'
   ```

3. `Operator-authorizes:` delete it in the operator's signed-in dashboard session, signed in as the login that owns
   the token (the 2026-11-26 0b revokes were owned by the old-account-owner login). Run it as ONE
   `browser_run_code_unsafe` body, with all three sub-steps inside one `try`/`catch`. Its tool result is only one
   of `{atok: false}`, `{matches: <n>}`, `{status, contentType, success}` or `{error: e.name}`. Never return the
   `x-atok`, the full id or `e.message`: a thrown request error may carry the request it was sending.
   1. `page.goto('https://dash.cloudflare.com/profile/api-tokens')` first. A page not reloaded since sign-in can show
      a stale token list (observed 2026-11-26: it listed 0 tokens). Then
      `await page.waitForFunction(() => !!(window.bootstrap && window.bootstrap.atok), null, { timeout: 15000, polling: 100 }).catch(() => {})`:
      the dashboard sets the atok after DOMContentLoaded (measured 2026-11-28, about 283 ms), so a read straight
      after the goto returns `{atok: false}` on a signed-in page.
   2. One `page.evaluate` reads `window.bootstrap.atok` and `GET /api/v4/user/tokens`, and keeps the atok and the id
      whose prefix equals step 2's in Node-local variables. No atok: return `{atok: false}` (the page is signed out, or set no atok within the 15 s wait; reload the tab).
      Zero matches: return `{matches: 0}`; this login does not own it, and the agent asks the operator to sign in as
      the owner, never switching logins itself. Several matches: return `{matches: <n>}` and stop.
   3. `page.request.delete('https://dash.cloudflare.com/api/v4/user/tokens/<id>')`. The 2026-11-26 deletes that
      returned `200` (#12931 comment 7203873359) sent the headers `x-atok` and `x-cross-site-security: dash`; the
      second is recorded from that session's browser code, not the comment, and whether it is required was not
      tested. The DELETE is Node-side because an in-page `fetch` DELETE got an HTML
      `403` from the dashboard edge (measured 2026-11-26), while the in-page mint POST to `/user/tokens` did not.
      On 2026-11-28 an in-page `fetch` POST to `/accounts/<acct>/tokens` got the same HTML `403`, twice, so the
      Phase 5 mint body (`p5-mint.js`) sends its token POST Node-side too (`page.request.post`).

   Only `200` with `success: true` is a revoke. A JSON `403` or `404` is an ownership or session refusal: stop and
   report. Anything else (a non-JSON reply, `success: false`, a thrown error, another status): stop, post what the
   result shows on #12931, and do not retry without a fresh authorization.
4. `Agent:` read back: re-run step 2. Expected: `.success` is `false`, printed as a line that starts
   `success=false`. Any other output (`success=true`, `success=null`, an empty line, an error) means the revoke is
   unconfirmed: stop, post it, and keep the key, since it is the only way to re-read the id. Only on `success=false`,
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

1. Mint with `browser_run_code_unsafe`: a `page.evaluate` (it runs in the page, not in Node) creates the token through
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

- A write probe sends **one of two fixed body literals, each built to be rejected**: a non-JSON literal for every
  row except the zone settings PATCH, and for that row (whose endpoint parses JSON before it checks authorization) a
  JSON body naming one nonexistent `cf_token_scope_probe_`-prefixed setting id. A `2xx` to either is still fatal
  (exit 4). Before any write the run reads the zone's settings list. If it lists that id, the run prints
  `probe=zone-rest verdict=refused reason=probe-id-collision` and exits 2. If an item in it is not an object with a
  string id, it prints `reason=settings-list-unevaluable` and exits 2. If the settings read fails, is not one JSON
  document, or returns an empty list, the settings row is skipped and the run exits 3 (`inconclusive`). Never `{"rules":[]}` (which would wipe a
  live entrypoint), never a body naming a real setting. It never `DELETE`s.
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

Expected per row: `authorized (PUT 400, err <code> after a 403 control)` (or `POST`/`PATCH`; the `, err <code>` part
appears when the reply carries a numeric code), and the run line
`probe=<phase> verdict=pass` with exit 0. `probe=<phase> verdict=denied` or `verdict=inconclusive` (exit 3), or
`verdict=refused` (exit 2), blocks that phase's dispatch. An entrypoint the audit reports present is recorded by id and imported, never overwritten.

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
record's live values match `dns.tf`. The provider's Read fills `content` only when it is already set, so each
`cloudflare_record` import plans one update adding `allow_overwrite = false` and `content`, and the apply sends one
same-value PATCH per record (same value on every compared field; a CNAME's `settings` may read back as `{}`). The gate admits exactly that shape, logged as `import-normalize`, and only when a live
read by the pinned id, taken after the plan, equals the planned record (ADR-329, CTO ruling 2026-11-22). Every other
diff is still refused. The gate's admitted plan shape (`cfam_norm_shape`) is not changed to get past a refusal. In
the live compare, a record that is a CNAME both live and in the plan, whose plan holds no `settings` and whose live
`settings` is exactly `{"flatten_cname":false}`, is not a difference: that is the API default (CTO ruling 2026-11-25,
#13056). That the PATCH leaves it `false` is inferred from the provider and cloudflare-go source, not observed; the
post-apply re-read is what detects any other outcome. The job keeps no per-record `settings`: its
`import-normalize reread=ok records=26` line is the evidence, and that line goes on #12931 after the first apply. A re-read `settings:other` is a stop token like any other (no edit, owner decision), and on
`supabase_custom_domain` or a `protonmail_dkim_*` record it is urgent: sign-in or mail authentication may be
degraded, so post it on #12931 with the first line `URGENT reread=differs=<addr>:settings+settings:other`, then
the re-read line exactly as printed. Nobody edits this zone by hand
during the apply: an edit landing between the read and a PATCH is overwritten, and the re-read then passes.

A refusal about a live record prints `REFUSE <addr> differs from the live record (<tokens>)` or
`REFUSE <addr> live record unreadable`; a post-apply re-read prints the same tokens as `reread=differs=<addr>:<tokens>`
(joined with `+`) or `reread=unreadable=<addr,...>`. One difference holds back the admission of every record, so the
other records' `REFUSE` lines name no difference of their own: act only on these lines. Each token has one action, and
a stop token on a record wins over any other token on that record:

| Token | Meaning | Action |
|---|---|---|
| `content:quoted-equal` | The live `content` equals the planned value once surrounding quotes are ignored | Stop token. No edit; stop for an owner decision |
| `tags:absent` | The API response has no `tags` key, so no record edit can satisfy the compare | Stop token. No edit; stop for an owner decision |
| `settings:only-flatten-false` | The live `settings` is exactly `{"flatten_cname":false}` unless the record is a CNAME in both the live read and the plan and the plan holds no `settings` (then it is the API default and compares equal, CTO ruling 2026-11-25). Not expected in normal operation | Stop token. No edit; stop for an owner decision |
| `settings:other` | The live `settings` holds any other non-empty value | Stop token. No edit; stop for an owner decision. On `supabase_custom_domain` or a `protonmail_dkim_*` re-read it is urgent: post the `URGENT` comment on #12931 (Step 2) while the other records are restored |
| `data`, `after` | The live record holds a `data` value `dns.tf` does not declare, or the plan holds no record to compare | Stop token. No edit; stop for an owner decision |
| `unreadable` | The read failed, so nothing is known about the record | Not a difference. No edit. After a re-read, follow Halt **No completed re-read**. After a gate refusal, `Operator-authorizes:` one more rehearsal; a second consecutive refusal stops for an owner decision |
| `notfound` | The record id answers 404 | Halt **A DNS record may hold a wrong value**, its `<addr>:notfound` step |
| `type`, `name`, `content`, `ttl`, `proxied`, `priority`, `comment`, `tags` with no stop token | That field differs from the planned record | Halt **A DNS record may hold a wrong value**, where any record edit is `Operator-authorizes:` |

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
- `cf-account-migrate live-read records=26` on every `redirects-dns` run;
- `cf-account-migrate import-normalize count=26` before the first apply. After an earlier `applying=true`, any count
  from 0 to 26 is valid. The count is the records the apply never reached, which still plan the admitted update. A
  record whose PATCH failed plans a no-op if live still matches, so `count=0` does not prove any PATCH was accepted.
  The gate's `imports=` falls when a record enters state, whether or not its write succeeded, so neither number is
  write progress. Admitted records never belong in `expected_in_state_updates`;
- the entrypoint gate passing on the new zone.

Any `cf_account_migrate_gate: … verdict=REFUSE` line (its `REFUSE <address> …` reason lines print above it), any
`cf-account-migrate phase=<phase> verdict=refuse reason=<code>` line or `verdict=abort` stops the phase. A live-record
line goes by the token table above. For any other reason, read it, fix forward in a PR, re-rehearse.

> Before the first `rehearsal=false` dispatch, the owner posts a comment on #12931 whose first line is exactly one of:
>
> `CF-MIGRATE-FIRST-PATCH: accept-unobserved`
>
> `CF-MIGRATE-FIRST-PATCH: observe-first`
>
> `accept-unobserved` accepts that all 26 records are written in one run with no canary, and that a wrong value is detected only after the run and is not undone. Only this token allows the dispatch to be proposed. `observe-first` stops here: no procedure exists yet, and one needs its own reviewed PR. An agent never posts this token. The token does not authorize the write; the `web-platform-infra-apply` environment approval does.

`Agent:` read the decision:

```bash
(
  rows="$(gh api repos/jikig-ai/soleur/issues/12931/comments --paginate --jq '.[]
    | (.body | split("\n")[0] | rtrimstr("\r")) as $l
    | select($l | test("^CF-MIGRATE-FIRST-PATCH: (accept-unobserved|observe-first)$"))
    | [.user.login, .created_at, .updated_at, ($l | split(": ")[1])] | @tsv')" || { echo unreadable; exit 0; }
  while IFS=$'\t' read -r login created updated value; do
    [ -n "$login" ] || continue
    if ! perm="$(gh api "repos/jikig-ai/soleur/collaborators/$login/permission" --jq .permission 2>&1 </dev/null)"; then
      case "$perm" in *'(HTTP 404)'*) continue ;; *) echo unreadable; break ;; esac
    fi
    [ "$perm" = admin ] || continue
    if [ "$created" = "$updated" ]; then printf '%s\n' "$value"; else echo edited; fi
    break
  done < <(tac <<<"$rows")
)
```

Output `accept-unobserved` passes. `observe-first`, `edited`, `unreadable` and empty all hold. Any failed read other than
a 404 on the permission lookup prints `unreadable`, so a read error can never fall through to an older decision. The
check proves an admin account posted, not that a person did; the environment approval remains the human control.

`Agent:` before the first `rehearsal=false` `redirects-dns` dispatch only, after its rehearsal PASS, save the pre-write
DNS baseline once with the `cfam_dns_save` line under **Verify** below. A re-dispatch reuses that baseline.

`Operator-authorizes:` the same dispatch with `rehearsal=false` (leave `expected_in_state_updates` empty: only a
fix-forward re-dispatch sets it, Halt `verify-failed` step 4), then the person approves the
`web-platform-infra-apply` environment. The real run writes the backup to
`web-platform/backups/pre-cf-account-migration-<utc>.tfstate` before its single `state rm`. `Agent:` record the key on
#12931 (it is disaster-recovery evidence, see Halt):

```bash
gh run view <run-id> --log | grep -oE 'cf-state-migrate backup=uploaded uri=[^ ]+' | head -1
gh issue comment 12931 --body "redirects-dns apply run <run-id>: <the uri line above>"
```

**Verify** (job step, then `Agent:` locally). When the apply carried an admitted record, the job step prints
`cf-account-migrate import-normalize reread=ok records=26` after `applied=true`. With `import-normalize count=0` it runs
no re-read and prints no such line.

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
fewer; a `PAGINATED` line means the list did not fit one page of 50: read the next page before trusting the count).

`Agent:` compare public DNS answers before and after the write, from the repository root. A shell function does not
survive between agent tool calls, so define these functions in each call that uses them, and save each snapshot to a
scratchpad file. These are public DNS answers, so the baseline is posted on #12931 as a comment whose first line is
`CF-MIGRATE-DNS-BASELINE`. The oldest such comment from an admin is the baseline, and nothing replaces it:

```bash
cfam_dns_names() {
  awk '/^resource "cloudflare_record"/{n=""} /^[[:space:]]*name[[:space:]]*=/{n=$3} /^[[:space:]]*type[[:space:]]*=/{print n, $3}' \
    apps/web-platform/infra/dns.tf | tr -d '"' \
    | awk '$2=="MX"||$2=="TXT"||$1=="api"||$1~/^protonmail/' | LC_ALL=C sort -u
}
cfam_dns_snapshot() {
  local name type fqdn body
  while read -r name type; do
    if [ "$name" = soleur.ai ]; then fqdn=soleur.ai; else fqdn="$name.soleur.ai"; fi
    body="$(curl --disable -fsS --max-time 5 -H 'accept: application/dns-json' \
      "https://cloudflare-dns.com/dns-query?name=$fqdn&type=$type")" \
    && printf '%s' "$body" | jq -r --arg q "$fqdn $type" --arg t "$type" '
        ({"CNAME":5,"MX":15,"TXT":16}[$t]) as $n
        | if .Status == 0 then "\($q) " + ([.Answer[]? | select(.type == $n) | .data] | sort | join(" | "))
          elif .Status == 3 then "\($q) NXDOMAIN"
          else "\($q) NO-VERDICT" end' 2>/dev/null \
    || echo "$fqdn $type NO-VERDICT"
  done < <(cfam_dns_names)
}
# Complete means exactly 19 rows and no NO-VERDICT. A run outside the repository root yields 0 rows.
cfam_dns_complete() {
  if [ "$(grep -c . "$1")" -eq 19 ] && ! grep -q 'NO-VERDICT' "$1"; then echo snapshot=complete; else echo snapshot=incomplete; fi
}
# Prints the saved baseline rows, or exactly one of baseline=none, baseline=edited, baseline=unreadable.
cfam_dns_baseline() {
  local rows login created updated body perm
  rows="$(gh api repos/jikig-ai/soleur/issues/12931/comments --paginate --jq '.[]
    | select((.body | split("\n")[0] | rtrimstr("\r")) == "CF-MIGRATE-DNS-BASELINE")
    | [.user.login, .created_at, .updated_at, (.body | @base64)] | @tsv')" || { echo baseline=unreadable; return 0; }
  while IFS=$'\t' read -r login created updated body; do
    [ -n "$login" ] || continue
    if ! perm="$(gh api "repos/jikig-ai/soleur/collaborators/$login/permission" --jq .permission 2>&1 </dev/null)"; then
      case "$perm" in *'(HTTP 404)'*) continue ;; *) echo baseline=unreadable; return 0 ;; esac
    fi
    [ "$perm" = admin ] || continue
    if [ "$created" = "$updated" ]; then printf '%s' "$body" | base64 -d | tail -n +2; else echo baseline=edited; fi
    return 0
  done <<<"$rows"
  echo baseline=none
}
# The one write. It posts only when no baseline exists and the snapshot file is complete.
cfam_dns_save() {
  local have; have="$(cfam_dns_baseline)"
  if [[ "$have" != baseline=* ]] && { [ "$(grep -c . <<<"$have")" -ne 19 ] || grep -q 'NO-VERDICT' <<<"$have"; }; then echo baseline=incomplete; return 1; fi
  case "$have" in
    baseline=none) ;;
    baseline=*) printf '%s\n' "$have"; return 1 ;;
    *) echo baseline=exists; return 0 ;;
  esac
  [ "$(cfam_dns_complete "$1")" = snapshot=complete ] || { echo snapshot=incomplete; return 1; }
  { echo CF-MIGRATE-DNS-BASELINE; cat "$1"; } | gh issue comment 12931 --body-file - >/dev/null || { echo baseline=unsaved; return 1; }
  echo baseline=saved
}
```

Save the baseline with `f=<scratchpad>/dns-baseline.txt; cfam_dns_snapshot >"$f"; cfam_dns_save "$f"`. For the comparison,
write a new snapshot to its own file, run `cfam_dns_complete` on it, and compare it with `cfam_dns_baseline` output. The
wait runs from the apply job's completion, whichever way it ended (`applied=true`, `apply-failed` or a cancel):
`gh run view <run-id> --json jobs --jq '.jobs[] | select(.name == "cf_account_migrate_apply") | .completedAt'`.

Take the first row that matches. A real difference wins over `NO-VERDICT`.

| When | Result | Action |
|---|---|---|
| After the first rehearsal PASS, before the first `rehearsal=false` | `baseline=saved` or `baseline=exists` | Proceed to the dispatch |
| Same | `snapshot=incomplete` | Retry from the repository root; do not dispatch without a saved baseline |
| Same | `baseline=unreadable`, `baseline=edited`, `baseline=incomplete` or `baseline=unsaved` | Stop for an owner decision before the dispatch |
| At least 360 s after the apply job's `completedAt` | `cfam_dns_baseline` prints `baseline=none` or `baseline=edited`: the baseline is lost | A later snapshot would hold post-write answers, so save nothing. Post `dns-answers=unverified baseline-lost`, make no edit and stop for an owner decision |
| Same | `baseline=unreadable` | Retry 3 times, 60 s apart. If it persists, stop for an owner decision |
| Same | A row holds a real answer that differs from the baseline, including `NXDOMAIN`, whether or not another row is `NO-VERDICT` | Re-check twice, 60 s apart. If it persists, `Operator-authorizes:` a rehearsal. A refusal naming a record goes to the wrong-value bullet. If the rehearsal passes, make no edit and stop for an owner decision |
| Same | `snapshot=incomplete` and no real difference | Retry 3 times, 60 s apart. If it persists, post `dns-answers=unverified <names>`. No refusal, no edit, no restore. The next phase waits for a clean snapshot |
| Same | `snapshot=complete` and identical to the baseline | Post `dns-answers=ok` on #12931 |

Then revoke the three superseded 0a tokens with the revoke recipe, one
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

1. **Deploy Access service token.** Mint `CF_API_TOKEN_ACCESS_MINT` (Access: Service Tokens:Edit only, 7-day expiry;
   the script also accepts it staged as `CF_API_TOKEN_ACCESS_MINT_NEXT`) with the Phase 0 hand-off. `Agent:` run
   `apps/web-platform/infra/scripts/cf-access-deploy-token-mint.sh` with no argument: a dry run that proves every
   read, lists the holders and mints nothing. `Operator-authorizes:` the same line with `--apply`.
   It writes `CF_ACCESS_CLIENT_ID`/`CF_ACCESS_CLIENT_SECRET` on stdin to `soleur-infra-privileged/prd`,
   `soleur/prd_terraform`, every other Doppler config that already holds both names (a config holding only one of them
   refuses), and the GitHub repository secrets of the same names (through the infra GitHub App), and prints only the
   token UUID. Doppler copies are checked by digest; GitHub cannot return a secret, so those are checked by their
   `updated_at` moving. Its last line is `verdict=ok token_id=<uuid> written=<n>`; that UUID goes into
   `local.deploy_service_token_ids` (step 2). The 31-day clock of `deploy-token-refused` starts now. After
   `verdict=ok`, revoke `CF_API_TOKEN_ACCESS_MINT` with the revoke recipe. For each `CF_ACCOUNT_ID` holder the
   inventory stage lists outside `prd_terraform`, decide whether it is read for R2 (leave it, or move the reader to `CF_R2_ACCOUNT_ID`) or for zone and Access (write the new id after this
   step): `apps/web-platform/server/inngest/functions/event-cf-token-expiry-check.ts` reads `prd` `CF_ACCOUNT_ID` to
   watch the `github-actions-deploy` token, which now lives on the new account. Record each decision on #12931.
2. **Commit the ids, then merge PR2.** One branch commit, before the merge, carries three things: the token UUID over
   the nil placeholder in `local.deploy_service_token_ids` (`tunnel.tf`), the six pre-delete record ids in
   `PINNED_IDS` of `apps/web-platform/infra/scripts/cf-tunnel-host-predelete.sh` (one bare id per line), and the
   `[skip-web-platform-apply]` kill switch as a line of its message body. Without the six ids the tunnel rehearsal
   refuses `pins-missing` and a second PR is needed. `Agent:` read the ids (record ids are not secret; this only reads):

   ```bash
   for n in ssh.soleur.ai registry.soleur.ai; do
     doppler run -p soleur -c prd_terraform -- bash -c 'printf "Authorization: Bearer %s\n" "$CF_API_TOKEN" \
       | curl --disable --noproxy "*" -sS --max-time 30 --header @- "https://api.cloudflare.com/client/v4/zones/951ce525552201ec6c696b24251abed7/dns_records?type=A&name=$1"' _ "$n" \
       | jq -r '.success, (.result[] | "\(.id) \(.name) \(.proxied) \(.content)")'
   done
   bash apps/web-platform/infra/scripts/cf-tunnel-host-predelete.sh --check-pins
   ```

   Expected: `true` and three proxied rows per name, with content in {`104.26.10.163`, `104.26.11.163`,
   `172.67.73.132`}; any other row count or content is a stop. After the commit, `--check-pins` prints
   `cf-tunnel-host-predelete verdict=pins-ok count=6`. `Operator-authorizes:` merge PR2, with the kill switch checked
   exactly as in Phase 1 (the same `gh pr view <PR2> --json commits` count before queueing).
3. **Tunnel phase.** `Agent:` before the rehearsal, check, read-only:

   ```bash
   doppler secrets --only-names --json -p soleur -c prd_terraform | jq -r 'has("CF_API_TOKEN_NEXT")'      # false
   gh secret list --json name --jq '[.[] | select(.name == "DOPPLER_TOKEN_WRITE")] | length'               # 1
   doppler run -p soleur -c prd_terraform -- bash -c 'printf "Authorization: Bearer %s\n" "$CF_API_TOKEN" \
     | curl --disable --noproxy "*" -sS --max-time 30 --header @- "https://api.cloudflare.com/client/v4/accounts/66d4f93f7397f196544e9fe84c3557c2/cfd_tunnel?name=soleur-web-platform&is_deleted=false"' \
     | jq -r '.success, (.result | length)'                                                              # true, 0
   doppler run -p soleur -c prd_terraform -- bash -c 'printf "Authorization: Bearer %s\n" "$CF_API_TOKEN" \
     | curl --disable --noproxy "*" -sS --max-time 30 --header @- "https://api.cloudflare.com/client/v4/zones/951ce525552201ec6c696b24251abed7/access/apps?per_page=100"' \
     | jq -r '.success, ([.result[] | select(.domain | test("^(deploy|ssh|registry)\\.soleur\\.ai"))] | length)'   # true, 0
   ```

   - A staged `CF_API_TOKEN_NEXT` is what the scope probe grades, while the plan and apply use `CF_API_TOKEN`: swap
     or delete it first.
   - `DOPPLER_TOKEN_WRITE` must be a repository secret: only the apply leg receives it, so the rehearsal cannot prove
     it, and the apply refuses `doppler-write-token-missing` without it.
   - A leftover `soleur-web-platform` tunnel or an Access app on the three hosts collides with the creates: stop for
     an owner decision.
   - Read the latest `scheduled-terraform-drift.yml` plan for the addresses the `cloudflare_record.app` target pulls
     in (`doppler_service_token.*`, `hcloud_volume.workspaces`, `hcloud_placement_group.web_spread`,
     `random_password.zot_pull`, `tls_private_key.ci_ssh`). Drift on any of them refuses the tunnel plan.

   `Agent:` save the pre-write baseline of `cloudflare_record.app` once, before the first `rehearsal=false` dispatch.
   It is the one record the tunnel phase writes, and the `redirects-dns` baseline does not cover it. The content is
   web-1's origin IPv4, which the proxied record keeps off public DNS, so post only its digest on #12931:

   ```bash
   doppler run -p soleur -c prd_terraform -- bash -c 'printf "Authorization: Bearer %s\n" "$CF_API_TOKEN" \
     | curl --disable --noproxy "*" -sS --max-time 30 --header @- https://api.cloudflare.com/client/v4/zones/951ce525552201ec6c696b24251abed7/dns_records/f21d6911cdacb1e109ae31bcfb440e7d' \
     | jq -c 'select(.success == true) | .result | {id, type, name, content, proxied, ttl, comment, tags}' > <scratchpad>/app-record-baseline.json
   jq -r '"\(.type) \(.name) proxied=\(.proxied) ttl=\(.ttl)"' <scratchpad>/app-record-baseline.json
   jq -r '.content' <scratchpad>/app-record-baseline.json | sha256sum
   ```

   `Operator-authorizes:` the dispatch with `migrate_phase=tunnel -f confirm=MIGRATE-CF-tunnel`,
   `rehearsal=true`, then `rehearsal=false`. Once every gate has passed (phase gate, deploy-token read, entrypoint gate,
   `expected_in_state_updates`, the workflow-command token), and just before `applying=true`, the apply leg
   runs the pinned six-record pre-delete (`cf-tunnel-host-predelete.sh --apply`, never from the agent's machine; CTO
   ruling 2026-11-25, so a gate refusal deletes nothing): it GETs each pinned id and deletes all six
   only if every one is a proxied `A` record on `ssh.`/`registry.soleur.ai` with content in
   {`104.26.10.163`, `104.26.11.163`, `172.67.73.132`} in the new zone; one mismatch deletes none
   (`verdict=refuse`). Before any delete it also lists every record on `deploy.`, `ssh.` and `registry.soleur.ai`;
   one that is neither pinned nor a proxied CNAME to `*.cfargotunnel.com` refuses `foreign-record`. The rehearsal
   grades the pin list (`--check-pins`), then dry-runs the pre-delete against the live zone, deleting nothing. The
   gate grades the content of the three Access policies and apps it creates, and reads their include blocks in
   `apps/web-platform/infra/tunnel.tf`, so each block keeps `service_token = <its own token>` as its only statement;
   each app must also leave `policies`, `options_preflight_bypass`, `self_hosted_domains`, `destinations` and
   `cors_headers` unset. Expected gate line: the tunnel, its config, 3 Access apps, 3 policies, 2 service tokens, the
   `service_token_expiry` notification policy and the `deploy`/`ssh`/`registry` CNAMEs created; `random_id.tunnel_secret`
   replaced by request; `doppler_secret.registry_push_access_token_id`/`_secret` updated in place (they carry no
   `ignore_changes`, ADR-331 Decision 3, so no `-replace` is needed); `cloudflare_record.app` an import that plans the
   admitted `import-normalize` update, as every record import does (ADR-329), pinned, read live after the plan and
   re-read after the apply exactly as the `redirects-dns` records are; exactly one create of the deploy policy, whose
   service token the gate read live (`200`, name `github-actions-deploy`, 8016 to 8761 h to expiry,
   `decision = "non_identity"`, a single include); `destroys=1`, the delete half of the `random_id.tunnel_secret`
   replace. The post-apply step syncs `CI_SSH_ACCESS_TOKEN_ID/_SECRET` to `prd_terraform` and checks each by digest.
   After the apply, the new tunnel has 0 connectors (an expected red), and the predicate is now true (Merge freeze).

   **Verify** (job step, then `Agent:` locally). The job runs the gptbot, noindex and app-health probes as for
   `zone-rest`, and the `cloudflare_record.app` re-read (`import-normalize reread=ok records=1`). Then:

   ```bash
   for h in deploy ssh registry; do curl -sS -m 10 -o /dev/null -w "$h %{http_code} %header{cf-access-domain}\n" "https://$h.soleur.ai/"; done
   curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' https://app.soleur.ai/health               # 200
   ```

   Expected: each host answers `401`, `403` or `302` with its own name as `cf-access-domain` (Access answers in front
   of a tunnel with 0 connectors), and `/health` answers `200`.
4. **Replace web-2** (the only path that delivers the new tunnel token: it reaches a host only through create-time
   user_data, ADR-304). `Agent:` first, read-only (plan Phase 5.0 and 5.1):
   - Read the load balancers on the new zone (`GET /zones/951ce525552201ec6c696b24251abed7/load_balancers`), each pool
     they name (`GET /accounts/66d4f93f7397f196544e9fe84c3557c2/load_balancers/pools/<id>`) and the `app.` record. If no
     pool there holds web-2's address and `app.` points only at web-1, record "web-2 serves no app traffic" on #12931
     and continue. Otherwise stop: draining a live pool is a production write outside Terraform. Only on an explicit
     operator go, set web-2's weight to 0 by API, re-read it, and wait until the pool reports it drained.
   - Check stock: `GET https://api.hetzner.cloud/v1/server_types?name=cpx22` with `HCLOUD_TOKEN_READONLY`, and
     require `hel1` among `server_types[0].locations[]` with `available` true. A replace destroys before it creates,
     so no stock means no web-2.

   Skip the `ga-pool-update` drain and serve steps of `web-host-replace.md`: they target the moved zone and drain
   nothing live. `Operator-authorizes:` the rehearsal, then the same line with `plan_only=false`:

   ```bash
   gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=web-host-replace \
     -f web_host_key=web-2 -f confirm=REPLACE-web-2 -f plan_only=true -f reason='#12931 tunnel token'
   ```

   Expected: the replace gate sees exactly its four allow-listed addresses, web-2 boots, and
   `soleur-wait-ready service cloudflared` passes (a failure emits a fresh-boot Sentry event and a Better Stack boot
   trail, source 2457081). web-1 is never touched; `app.soleur.ai` keeps serving from its A record. If the replace
   fails, re-run the stock check first. With `hel1` stock, re-dispatch. With none, stop for an owner decision on
   relocating web-2. If step 4 drained a pool, point that origin at the new IPv4 and restore its weight under the same
   go.

   **Then re-mint the Origin CA certificate from the new zone**, before the release redeploy, with
   `CF_API_TOKEN_ORIGIN_CA` re-scoped to the new zone. prd still holds a valid pair, so the plan needs
   `-f replace=true` (without it the plan refuses `already_minted_not_expiring`):
   `gh workflow run mint-origin-ca-cert.yml --ref main -f mode=plan -f replace=true`, then `Operator-authorizes:` the
   deliberate-rotation apply in `origin-tls-mint.md` §3.
5. **Verify:**
   - the next connector census in `scheduled-inngest-health.yml` (verdict token from `scripts/tunnel-connector-census.sh`)
     reports exactly 1 connector on the new tunnel;
   - `apps/web-platform/infra/scripts/verify-tunnel-ingress-origin.sh` passes (the tunnel id and its account come from
     the Terraform outputs `cf_tunnel_id` and `cf_tunnel_account_id`, not Doppler's `CF_ACCOUNT_ID`; `deploy-status`
     200 through `deploy.` with the new Access pair);
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

   The predicate has been true since the tunnel apply. Expected: green end to end, and the plan in its log carries exactly one
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
  `cf_migration_*` variables, `cf-account-migrate.yml` with its job script, the alert workflow
  `.github/workflows/cf-account-migrate-alert.yml`, the gate and the bootstrap with its suite).
  Keep `cf-access-deploy-token-mint.sh` and the `cf-token-scope.sh` profiles.
- Revoke `CF_API_TOKEN_SOLEUR_ACCT` (if not already) and any superseded old-zone token with the revoke recipe.
  Six tokens remain on the old-account-owner login, measured 2026-11-26. #12931 comment 7205049710 lists them by id
  prefix with the holders a search found. These are inputs for the cleanup PR, not a procedure. That PR writes the
  replacement steps, under its own review, before any of these is revoked.
  - Holders found in `soleur`: `CF_API_TOKEN_AUDIT` (`dev`, `dev_personal`, `dev_scheduled`, `prd_terraform`),
    and `CF_API_TOKEN_ANALYTICS_READ`, `CF_API_TOKEN_PAGERULES_READ` and `CF_API_TOKEN_PURGE_PREV` (all
    `prd_terraform`).
  - Not yet located: the search covered only `CF_*TOKEN*` keys in project `soleur`. So it could not find the Origin
    CA token's documented holder, `CF_API_TOKEN_ORIGIN_CA` in `soleur-infra-privileged/prd` (Phase 3 step 4,
    `origin-tls-mint.md`), or an R2 token's S3 key pair.
  - Not yet read: each token's zone and account scope.

  Constraints the cleanup PR's procedure must meet:
  - Stage the old value as `<KEY>_PREV` before overwriting `<KEY>`, so the revoke recipe reads the old id.
  - Check by digest or verify id, never by key name, that no config's `<KEY>` still holds the old value.
  - Treat `CF_API_TOKEN_ANALYTICS_READ` as an owner mint (`origin-tls-strict-flip.md`).
  - Run `cloudflare-readonly.sh pagerules-ssl` on the new zone before deciding the fate of
    `CF_API_TOKEN_PAGERULES_READ`. That read is pinned in `components.test.ts`. If the token is scoped to the
    old zone, the read fails with a scope or zone-access error; that means "unknown", not "no page rules".

  `CF_API_TOKEN_PURGE_PREV` is revoked at Phase 3 step 5. The R2 token stays, because the old account keeps R2.
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
backup is taken only when something will be removed). On the retry, a record whose PATCH failed plans a no-op if live
still matches, a record the apply never reached plans the admitted `import-normalize` update, and the plan covers only
the remainder. An apply that fails after the forget says the same in its refusal line: fix forward and re-dispatch,
never restore from the backup.

The off-by-default flags `cf_load_balancing_enabled`, `cf_zone_plan_pro` and `cf_zone_dnssec_enabled` are locked to
`false` by `variables.tf` validations (CTO ruling D9). PR2 deleted the `cf_migration_import_app` validation by that same
procedure; only the tunnel phase's plan passes `-var=cf_migration_import_app=true`, and `cf_r2_account_id`
is pinned to the legacy account. Never fix a red by overriding one: turning a flag on is a reviewed PR that deletes its
validation (Load Balancing #12983, DNSSEC #12982).

- **Is the forget committed?** It is a fact of the whole migration, never of one run's log: a re-dispatch after a
  committed forget prints `removed=0` and no `backup=uploaded`, so this run's log alone never answers it. The forget is
  committed once ANY `rehearsal=false` `redirects-dns` run printed `cf-state-migrate backup=uploaded`, even if its gate
  then refused (CTO ruling 2026-11-20). `Agent:` read the cross-run record:

  ```bash
  gh issue view 12931 --json comments --jq '[.comments[].body | select(test("cf-state-migrate backup=uploaded uri="))] | length'
  for r in $(gh run list --workflow cf-account-migrate.yml --limit 100 --json databaseId --jq '.[].databaseId'); do
    if log="$(gh run view "$r" --log)"; then
      grep -m1 -oE 'cf-state-migrate backup=uploaded uri=[^ ]+' <<<"$log" | sed "s/^/run=$r /"
    else echo "run=$r unreadable"; fi
  done
  doppler run -p soleur -c prd_terraform -- bash -c 'source tests/scripts/lib/cf-account-migrate-gate.sh &&
    cfam_r2_aws s3api list-objects-v2 --bucket "$CFAM_STATE_BUCKET" \
      --prefix "${CFAM_BACKUP_PREFIX}pre-cf-account-migration-" --query "length(Contents || \`[]\`)"'
  ```

  Committed: the first command prints `1` or more (the backup-uri comment of Phase 2 step 2), or the loop prints a
  `run=<id> cf-state-migrate backup=uploaded` line, or the listing prints `1` or more (a
  `pre-cf-account-migration-*` object exists). Not committed: ALL THREE
  answered and none says committed: the first command prints `0`, the loop prints no line at all (no `unreadable`),
  and the listing prints `0`. Anything else (a `run=<id> unreadable` line, a `gh` or `doppler` error, a listing that
  prints no number) is not an answer: stop for an owner decision. Never read silence as "not committed": an
  unreadable run log is exactly the run that may have committed it.
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
  with or without `applied=true`): rules may have landed in this run. An `apply-failed` whose message says `exit 124`
  is the apply's one INT at `APPLY_DEADLINE` firing, and takes this same path. One exception comes first: a
  `reread=` value containing `differs=` goes to **A DNS record may hold a wrong value** and restores first, and an
  `unreadable=` value with no `differs=` goes to **No completed re-read**. Otherwise `Agent:` run that phase's local
  Verify block first; on any failure follow the `verify-failed` steps below (an `apply-failed` refusal of any phase
  also carries its own best-effort `verify=ok`, `verify=skipped` or `failing=` field, and `verify=skipped` means no
  public probe ran). Then, after a cancelled `redirects-dns` or `tunnel` run, follow **No completed re-read**. In every
  other case,
  fix the cause forward and re-dispatch.
- **A rehearsal that refused `remote-serial-changed` or `backup-written`**: the one case where a rehearsal may
  have written. `remote-serial-changed`: the remote state's serial moved while the rehearsal ran, so something wrote
  the web-platform state (another writer, which the concurrency group should rule out, or the rehearsal itself); `backup-written`: a new
  `pre-cf-account-migration-*` object appeared, so the rehearsal's forget escaped its scratch copy. Either way: no
  re-dispatch, no revert. `Agent:` post the run id and its refusal line on #12931, run the "Is the forget committed?"
  record above, and stop for an owner decision.
- **A DNS record may hold a wrong value** (`import-normalize-reread-failed` or `apply-failed` whose `reread=` value
  contains `differs=`, the mixed `reread=differs=<addr:field,...>;unreadable=<addr,...>` included, or `gate-refused` or
  `rehearsal-refused` whose log holds a `REFUSE <addr> differs from the live record (<tokens>)` line). A `reread=` value
  with only `unreadable=` is **No completed re-read**, and `REFUSE <addr> live record unreadable` with no `differs` line
  is a re-rehearsal with no edit (the Step 2 token table).
  Treat it as live user impact and restore before any PR, in the order `app` (the `tunnel` phase's one record; a wrong
  value takes the product down for every user), `api`, MX/SPF/DKIM/DMARC, `buttondown_ns1` and
  `buttondown_ns2` (a wrong NS value redelegates `mail.soleur.ai`), `supabase_acme_challenge` (a wrong value can break
  `api` certificate validation later, with no immediate symptom), then the rest. The re-read detects a bad write and
  does not undo it: the wrong value stays live until restored and resolver caches expire.
  - `failing=<list>` on the same line: the `verify-failed` steps apply to those items, `app-health` first. A failing
    `app-health` item follows `verify-failed` step 1 before any record edit, because the product is down for every
    user. The other items follow after the restore.
  - Read each named record's tokens in the Step 2 table. A record with a stop token gets no edit: restore the other
    records, then stop for an owner decision before any re-dispatch.
  - If no `rehearsal=false` run has printed `mode=apply applying=true` (the **Is the forget committed?** loop, grepping
    that marker instead; an unreadable run counts as printed), this job has written nothing and `dns.tf` may be the
    stale side. Make no edit and stop for an owner decision between the restore below and a reviewed PR to `dns.tf`.
  - The expected value is the record's `dns.tf` block. For `pages_apex` and `www`, whose block is
    `cloudflare_pages_project.docs.subdomain`, it is `result.subdomain` from a GET of
    `accounts/<CFAM_NEW_ACCOUNT_ID>/pages/projects/soleur-docs` with `CF_API_TOKEN_PAGES`, requiring HTTP 200,
    `success == true`, `result.name == "soleur-docs"` and a subdomain equal to `soleur-docs-40x.pages.dev`. A failed
    read or a mismatch means no edit and a stop for an owner decision.
  - For `app`, whose block is `hcloud_server.web["web-1"].ipv4_address`, the expected `content` is web-1's IPv4, read
    from the Hetzner API with `HCLOUD_TOKEN_READONLY` (`GET /v1/servers/<id>`, the id Terraform state holds for
    `hcloud_server.web["web-1"]`, whose `ipv4_address` state also holds), never over SSH. It must equal the
    `content` of the baseline file Phase 3 step 3 saved (compare digests); a difference is a stop for an owner
    decision. The restore block below reads the `redirects-dns` pins, which do not list `app`: for it, its `ID=` line takes
    `cf_account_migrate_record_pins tunnel`. The recreate block refuses `app` (its `content` is not a literal): a
    deleted `app` record is a stop for an owner decision.
  - `Operator-authorizes:` one edit of the named field on the NEW zone, only for a record with no stop token. `Agent:`
    runs one block per field from the repository root. `VALUE` is the expected value as JSON (`"text"`, `300`, `true`);
    for `name` it is the full hostname. For a field the record's `dns.tf` block omits, `VALUE` is `null` for `comment`
    and `priority`, `[]` for `tags`, and `false` for `proxied`. The block takes the record id from the pin and the zone
    from the gate library, and GETs the record first: unless that read is the pinned record it prints `pin_http=<code>`
    and `input-refused` and writes nothing. The PATCH sends the record's own `type`, `name` and `ttl` plus the named
    field. A separate GET must then match `VALUE` on that field and the first GET on the other seven of `type`, `name`,
    `content`, `ttl`, `proxied`, `priority`, `comment` and `tags`, with arrays sorted and `""` read as `null`:

    ```bash
    ADDR='<addr>'; FIELD='<field>'; VALUE='<json value>'
    GATE=tests/scripts/lib/cf-account-migrate-gate.sh
    Z="$(bash -c 'source "$1" && printf %s "$CFAM_NEW_ZONE_ID"' _ "$GATE")"
    ID="$(bash -c 'source "$1" && cf_account_migrate_record_pins redirects-dns' _ "$GATE" | awk -F'\t' -v a="$ADDR" '$1 == a {print $2}')"
    IS_PIN='(.success == true) and (.result.id == $id) and (.result.zone_id == null or .result.zone_id == $z)'
    BODY_OF='(.result | {type, name, ttl}) + {($f): $v}'
    CHECK='def n: if type == "array" then sort elif . == "" then null else . end;
      .result as $r | (.success == true) and ($r.id == $id) and (($r[$f] | n) == ($v | n))
      and (["type","name","content","ttl","proxied","priority","comment","tags"] - [$f]
           | all(. as $k | ($r[$k] | n) == ($b.result[$k] | n)))'
    if [[ "$Z" =~ ^[0-9a-f]{32}$ && "$ID" =~ ^[0-9a-f]{32}$ && "$FIELD" =~ ^(type|name|content|ttl|proxied|priority|comment|tags)$ ]] \
      && jq -en --argjson v "$VALUE" 'true' >/dev/null 2>&1; then
      doppler run -p soleur -c prd_terraform -- bash -c '
        t="${CF_API_TOKEN:-}"; case "$t" in ""|*[!A-Za-z0-9._~+/=-]*) echo token-shape-refused; exit 3 ;; esac
        u="https://api.cloudflare.com/client/v4/zones/$1/dns_records/$2"
        api() { curl --disable --noproxy "*" -sS --max-time 10 --config - "$@" < <(printf "header = \"Authorization: Bearer %s\"\n" "$t"); }
        resp="$(api -w "\n%{http_code}" "$u")"; pin="$(printf "%s" "$resp" | tail -n1)"; first="$(printf "%s" "$resp" | sed \$d)"
        if [ "$pin" != 200 ] || ! printf "%s" "$first" | jq -e --arg id "$2" --arg z "$1" "$5" >/dev/null 2>&1 \
          || ! body="$(printf "%s" "$first" | jq -c --arg f "$3" --argjson v "$4" "$6")"; then
          echo "pin_http=$pin"; echo input-refused; exit 0
        fi
        code="$(api -o /dev/null -w "%{http_code}" -X PATCH -H "Content-Type: application/json" --data-binary "$body" "$u")"
        echo "patch_http=$code"
        if api "$u" | jq -e --arg id "$2" --arg f "$3" --argjson v "$4" --argjson b "$first" "$7" >/dev/null 2>&1
        then echo readback=ok; else echo readback=differs; fi
      ' _ "$Z" "$ID" "$FIELD" "$VALUE" "$IS_PIN" "$BODY_OF" "$CHECK"
    else
      echo input-refused
    fi
    ```

    Continue only on `patch_http=200` and `readback=ok`. Any other output means the record's state is not confirmed: do
    not retry the write, post the address and the output on #12931, and stop for an owner decision.
  - `<addr>:notfound`: a re-dispatch cannot repair a deleted record, because a recreated record has a new id.
    `Operator-authorizes:` recreating it on the NEW zone from its `dns.tf` block, to restore service. `Agent:` runs this
    block from the repository root. It reads `name`, `content`, `type`, `ttl`, `proxied` and `priority` from the block,
    with `false` for an omitted `proxied`, `[]` for `tags` and no `comment`. For `pages_apex` and `www`, set
    `PAGES_SUBDOMAIN` to the `result.subdomain` checked above; any other value is refused. Unless the pinned id
    currently answers 404 it prints `pin_http=<code>` and `input-refused` and writes nothing. It POSTs to the new zone
    and reads the returned id back on every field:

    ```bash
    ADDR='<addr>'; PAGES_SUBDOMAIN=''
    GATE=tests/scripts/lib/cf-account-migrate-gate.sh; TF=apps/web-platform/infra/dns.tf
    Z="$(bash -c 'source "$1" && printf %s "$CFAM_NEW_ZONE_ID"' _ "$GATE")"
    ID="$(bash -c 'source "$1" && cf_account_migrate_record_pins redirects-dns' _ "$GATE" | awk -F'\t' -v a="$ADDR" '$1 == a {print $2}')"
    FIELDS="$(awk -v r="${ADDR#cloudflare_record.}" '
      $0 == "resource \"cloudflare_record\" \"" r "\" {" {on=1; next}
      on && /^}/ {exit}
      on && match($0, /^  (name|content|type|ttl|proxied|priority) *= */) {
        k=$1; v=substr($0, RLENGTH+1)
        if (match(v, /^"([^"\\]|\\.)*"/)) v=substr(v, 1, RLENGTH); else sub(/[[:space:]].*$/, "", v)
        print k "\t" v
      }' "$TF")"
    BODY="$(printf '%s\n' "$FIELDS" | jq -Rnc --arg pages "$PAGES_SUBDOMAIN" '
      [inputs | split("\t") | {(.[0]): (.[1]
        | if . == "cloudflare_pages_project.docs.subdomain"
          then (if $pages == "soleur-docs-40x.pages.dev" then $pages else error("pages") end)
          elif test("[$%]\\{") then error("interpolation") else fromjson end)}] | add
      | if (.type | type) != "string" or (.name | type) != "string" or (.content | type) != "string"
           or .content == "" or (.ttl | type) != "number" then error("fields") else . end
      | .name |= (if . == "soleur.ai" or endswith(".soleur.ai") then . else . + ".soleur.ai" end)
      | {type, name, content, ttl, proxied: (if has("proxied") then .proxied else false end), tags: []}
        + (if has("priority") then {priority} else {} end)' 2>/dev/null)"
    NEW_ID='select(.success == true) | .result.id'
    CHECK='def n: if type == "array" then sort elif . == "" then null else . end;
      .result as $r | (.success == true) and ($r.id == $id) and ($r.zone_id == null or $r.zone_id == $z)
      and (["type","name","content","ttl","proxied","priority","comment","tags"]
           | all(. as $k | ($r[$k] | n) == ($want[$k] | n)))'
    if [[ "$Z" =~ ^[0-9a-f]{32}$ && "$ID" =~ ^[0-9a-f]{32}$ && -n "$BODY" ]]; then
      doppler run -p soleur -c prd_terraform -- bash -c '
        t="${CF_API_TOKEN:-}"; case "$t" in ""|*[!A-Za-z0-9._~+/=-]*) echo token-shape-refused; exit 3 ;; esac
        base="https://api.cloudflare.com/client/v4/zones/$1/dns_records"
        api() { curl --disable --noproxy "*" -sS --max-time 10 --config - "$@" < <(printf "header = \"Authorization: Bearer %s\"\n" "$t"); }
        pin="$(api -o /dev/null -w "%{http_code}" "$base/$2")"
        if [ "$pin" != 404 ]; then echo "pin_http=$pin"; echo input-refused; exit 0; fi
        resp="$(api -w "\n%{http_code}" -X POST -H "Content-Type: application/json" --data-binary "$3" "$base")"
        echo "post_http=$(printf "%s" "$resp" | tail -n1)"
        new="$(printf "%s" "$resp" | sed \$d | jq -r "$4" 2>/dev/null)"
        if ! [[ "$new" =~ ^[0-9a-f]{32}$ ]]; then echo new_id=none; echo readback=differs; exit 0; fi
        echo "new_id=${new:0:8}"
        if api "$base/$new" | jq -e --arg id "$new" --arg z "$1" --argjson want "$3" "$5" >/dev/null 2>&1
        then echo readback=ok; else echo readback=differs; fi
      ' _ "$Z" "$ID" "$BODY" "$NEW_ID" "$CHECK"
    else
      echo input-refused
    fi
    ```

    On `readback=ok`, post the address and `new_id` on #12931 and stop for an owner decision. `new_id` is the first 8
    characters, per this runbook's id rule; the reviewed PR reads the full id from the zone by name and type. Any other output means the
    record is not confirmed: do not retry the POST, post the address and the output on #12931, and stop for an owner
    decision. No `terraform state rm`, `terraform import`, state push or lone literal edit: the path back into state
    needs a reviewed PR and a CTO ruling.
  - `verify=skipped` means no public probe ran, so run the local Verify block. `verify=ok` does not clear this bullet,
    because those probes read no mail record. Then `Operator-authorizes:` a rehearsal of the same phase, which reads
    every record that phase pins (26 for `redirects-dns`, `app` alone for `tunnel`), and the re-dispatch.
- **No completed re-read** (`redirects-dns` and `tunnel`, the phases that read records; `zone-rest` reads none: a
  `reread=` value with `unreadable=` and no `differs=`, or a cancelled run with `mode=apply applying=true` once its
  Verify block has run): edit no DNS record. A `failing=` item still follows its `verify-failed` step, and a failing
  `app-health` item follows `verify-failed` step 1 first. On `verify=skipped`, `Agent:` run the local Verify block.
  Then `Operator-authorizes:` a rehearsal, which reads every pinned record even on an all-no-op plan. A `differs from the live record` line goes to the bullet
  above. `live record unreadable` gets one more rehearsal, and a second consecutive one stops for an owner decision.
  On a rehearsal PASS, `Operator-authorizes:` the re-dispatch.
- **`reason=apply-budget-exhausted`** (prints `applied=false`, plus `forget=committed` on `redirects-dns`): fewer than
  `APPLY_MIN_START` (300 s) of apply budget remained, so nothing was applied. `Operator-authorizes:` one re-rehearsal
  and re-dispatch. On a second consecutive refusal, stop for an owner decision. Neither `APPLY_DEADLINE` nor
  `APPLY_MIN_START` is ever raised to get past it.
- **A stop before `applying=true`** (`gate-refused`, `entrypoint-gate-refused`, `state-migrate-failed`, any other
  `verdict=refuse` line printed before `applying=true`, except the two rehearsal reasons above,
  `apply-budget-exhausted`, `import-normalize-reread-failed` and a refusal covered by
  **A DNS record may hold a wrong value**, or a cancelled run with no `mode=apply applying=true`):
  this run applied nothing, so there is nothing to verify and no edited value to carry. A
  `REFUSE <addr> live record unreadable` line with no `differs` line is a failed read: edit nothing and re-rehearse, and
  a second consecutive refusal stops for an owner decision. For any other refusal, fix its cause (a reviewed PR when it
  is in code; nothing for a timeout), re-rehearse, re-dispatch. Whether the revert above is still allowed is the
  committed test, not this refusal.
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
     committed test, never this log's `backup=uploaded` alone. A cancelled run showing `backup=uploaded` and no
     `applying=true` wrote no DNS record. Re-rehearse, then re-dispatch the same phase.

  On `tunnel`, the pre-delete runs just before `applying=true`, so a run cancelled under arm 2 may have deleted the
  six A records (a re-dispatch counts them gone). The tunnel apply has no INT bound, so a cancel or a timeout kill can
  land a create in Cloudflare that never reached state. Before any `tunnel` re-dispatch after a cancel, `Agent:` read
  by name on the new account and zone: the `soleur-web-platform` tunnel, the service tokens `github-actions-ci-ssh` and
  `github-actions-registry-push`, the notification policy `CF Access service token expiring`, and the `deploy.`,
  `ssh.` and `registry.` CNAMEs. Any of them present while state does not hold it is a stop for an owner decision.
- **A `tunnel` refusal with `applied=true`** (`verify-failed`, `import-normalize-reread-failed`,
  `ci-ssh-sync-failed`): the predicate already reads complete, so merge nothing that triggers an apply of
  `apps/web-platform/infra` until this Halt clears. Then follow that reason's bullet; `ci-ssh-sync-failed` is a
  re-dispatch of the phase.
- **`reason=verify-failed applied=true`** (a `redirects-dns`, `zone-rest` or `tunnel` apply landed and a post-apply
  probe failed; the `failing=` list names each item with what came back, `<item>=><code>+<location>`). CTO ruling
  2026-11-20:
  1. Act on each failing item by its code, after any phase. If `app-health` is in `failing=` (the product is down
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
  - `SOLEUR_CFAM_TOKEN_UNREACHABLE`: a token read got no verdict: `e=<curl rc>` (a `curl` error or timeout) or
    `http=<code>` (a `429`, a `5xx`, a body that is not JSON), which says nothing about the token: re-run the stage.
    Never re-mint on this marker.
  - `SOLEUR_CFAM_RUN_IN_FLIGHT`: a writing stage refused because a `cf-account-migrate.yml` run is queued or in
    progress (or `gh` could not list the runs). Wait for that run to finish, read its verdict line, then re-run the
    stage.
  - `SOLEUR_CFAM_PROBE profile=<phase> verdict=not-pass`: the staged scope probe did not pass, so the swap wrote
    nothing. Read the `probe=<phase> verdict=…` line it relayed: `denied` means re-mint the key its relayed
    `row … -> denied (…; re-mint <KEY>)` line names, with the plan's permission groups; `inconclusive` means read
    the relayed `probe=<phase> row <label> -> <status>` lines first. A failed or empty settings control
    (`settings control not established`) means re-run the stage. A settings grant `400` that was not parsed
    (`inconclusive (grant got 400`) or a deny control that got `400` (`got 400, not 403`) means post it on #12931
    and stop for a CTO re-ruling. `refused` (exit 2) is the collision guard: post the `verdict=refused reason=…`
    line and its `refused-detail` line on #12931 and stop. `fatal-mutation` is the write-probe stop: post the
    relayed `probe=<phase> fatal`, `write-response` and `read-back` lines on #12931 and stop. A `not-pass` with no
    relayed `probe=<phase> verdict=` line is a usage error, a missing `_NEXT` secret or table corruption: run the
    probe directly and read stderr.
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
    read `<KEY>` with BOTH its NEW and its OLD read from the table above. NEW `true` and OLD `false`: the verify's own
    read failed (re-run verify). NEW `false`, or OLD `true` (an old "All zones" token), or a read with no verdict: the
    live key is not provably a new-account token and its revert copy is gone: stop for an owner decision.
    `<cfg>/<KEY>=matches-prd_terraform`: run `branch-copies-tokens`; if it refuses with `need=verify`, stop for an
    owner decision. `<cfg>=readable` or `inventory=readable`: as `SOLEUR_CFAM_UNREADABLE`.
- The backup object is disaster-recovery evidence only. It is never pushed back as state; Phase 5 deletes every
  `pre-cf-account-migration-*` object.
- If the migration is abandoned outright, stop at the last verified phase, keep the merge freeze, and record the
  state on #12931 for an owner decision. The old zone was never mutated, and objects created in the new zone or
  account stay there.
